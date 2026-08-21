import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { AUTH_DIR, isStdio, type RouterConfig, type UpstreamConfig } from './config.js';
import { isAuthFailure, recordState, authorizedAt, hasRefreshToken, tokenExpiry } from './auth.js';
import type { Manifest } from './manifest.js';

/**
 * The router's own authorization server — the half that faces MCP *clients*.
 *
 * Everything else in this repository that says "OAuth" is the router acting as a client to its
 * upstreams (`auth.ts`). This is the opposite role, on the same machine and the same port, which
 * is why every path here is exact-matched and distinct from `/callback`: a request meant for one
 * role must never be read by the other.
 *
 * WHY IT EXISTS. A client's "Authenticate" action against `http://127.0.0.1:8879/mcp` could not
 * succeed. The router served no metadata, so the client ran discovery, 404'd on every path, fell
 * back to `POST <origin>/register` and reported the router's catch-all 404. A better-worded 404 is
 * not a fix: OAuth defines exactly two terminal states for a flow a user has started — a token, or
 * an error — and there is no compliant way to say "this resource needs no authorization" that a
 * client treats as success.
 *
 * WHAT THE TOKEN MEANS. It authenticates nobody. The router is loopback-bound, protects no
 * client-facing secret, and `/mcp` treats a bearer request and a bare one identically — so a token
 * issued here is worth exactly what unauthenticated loopback access is already worth, which is
 * what the local user already has. It asserts one thing and it is true: the local user completed a
 * loopback flow against this router.
 *
 * THE DEVIATION, RECORDED. Advertising an authorization server while leaving `/mcp` unprotected is
 * knowingly outside the letter of the MCP spec, which says a server advertising an AS MUST
 * validate tokens. The alternative is protecting `/mcp`, which breaks every client already
 * connected until it re-authenticates. That is the owner's decision, taken deliberately, and it is
 * written here rather than left to be rediscovered as a bug. The invariant that pays for it:
 * **`/mcp` never returns 401.**
 *
 * STATELESSNESS. There is no user database and no registration store. `client_id`, access tokens
 * and refresh tokens are all self-encoded blobs signed with one persisted secret, so a token
 * minted before a restart still validates after it and a re-registration is idempotent. The one
 * piece of memory is the used-code set, which is bounded and whose entries expire in 60 seconds.
 */

// ---------------------------------------------------------------------------- paths and secret

export const ISSUER_KEY_PATH = join(AUTH_DIR, 'issuer.key');

export const WELL_KNOWN_RESOURCE = '/.well-known/oauth-protected-resource';
export const WELL_KNOWN_AS = '/.well-known/oauth-authorization-server';
export const REGISTER_PATH = '/register';
export const AUTHORIZE_PATH = '/authorize';
export const TOKEN_PATH_OAUTH = '/token';

/** An access token lives a year. It confers nothing, and a client that never has to re-run the
 *  browser leg is a client that never opens a tab on reconnect. */
const ACCESS_TTL_SECONDS = 365 * 24 * 60 * 60;
/** An authorization code lives 60 seconds and is used within one. */
const CODE_TTL_MS = 60_000;
/** A registration may not name more than this many redirect URIs, each no longer than this. */
const MAX_REDIRECT_URIS = 10;
const MAX_URI_LENGTH = 2048;

let cachedKey: Buffer | undefined;

/**
 * The one persisted secret, `0600` in a `0700` directory beside the upstream credentials.
 *
 * Cached in memory after the first read because every signature verification would otherwise be a
 * filesystem round trip on the request path.
 */
export function issuerKey(): Buffer {
  if (cachedKey) return cachedKey;
  mkdirSync(AUTH_DIR, { recursive: true, mode: 0o700 });
  if (existsSync(ISSUER_KEY_PATH)) {
    const raw = readFileSync(ISSUER_KEY_PATH, 'utf8').trim();
    if (raw) {
      cachedKey = Buffer.from(raw, 'hex');
      return cachedKey;
    }
  }
  const key = randomBytes(32);
  writeFileSync(ISSUER_KEY_PATH, key.toString('hex') + '\n', { mode: 0o600 });
  cachedKey = key;
  return key;
}

/** Test seam: forget the cached key so a suite can point AUTH_DIR somewhere else. */
export function resetIssuerKey(): void {
  cachedKey = undefined;
}

const b64url = (b: Buffer): string => b.toString('base64url');

function sign(payload: string): string {
  return createHmac('sha256', issuerKey()).update(payload).digest('base64url');
}

/** Constant-time, and length-checked first because `timingSafeEqual` throws on a mismatch. */
function signatureOk(payload: string, supplied: string): boolean {
  const expected = Buffer.from(sign(payload));
  const given = Buffer.from(supplied);
  return expected.length === given.length && timingSafeEqual(expected, given);
}

/** `<b64url(json)>.<signature>` — the one shape every self-encoded value here takes. */
function seal(value: unknown): string {
  const payload = b64url(Buffer.from(JSON.stringify(value), 'utf8'));
  return `${payload}.${sign(payload)}`;
}

function unseal<T>(blob: string): T | undefined {
  const dot = blob.lastIndexOf('.');
  if (dot <= 0) return undefined;
  const payload = blob.slice(0, dot);
  if (!signatureOk(payload, blob.slice(dot + 1))) return undefined;
  try {
    return JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as T;
  } catch {
    return undefined;
  }
}

// ---------------------------------------------------------------------------- redirect URIs

/**
 * Loopback only, enforced at registration **and** again at authorize time.
 *
 * This is the constraint that matters most on this whole surface. Without it a page the user is
 * visiting navigates them to `/authorize?redirect_uri=https://attacker.com/cb`, the auto-approval
 * fires, and the attacker holds a code. Checking it only at registration would not be enough,
 * because `client_id` is a self-encoded blob and the authorize leg has to re-verify what it
 * carries rather than trust it.
 *
 * `[::1]` is in the set alongside `127.0.0.1` and `localhost`, any port, per RFC 8252 §7.3. A
 * remote `https` destination is never allowed, whatever the client asks for.
 */
export function isLoopbackRedirect(uri: string): boolean {
  if (uri.length > MAX_URI_LENGTH) return false;
  let url: URL;
  try {
    url = new URL(uri);
  } catch {
    return false;
  }
  if (url.protocol !== 'http:') return false;
  return url.hostname === '127.0.0.1' || url.hostname === 'localhost' || url.hostname === '[::1]';
}

// ---------------------------------------------------------------------------- origins

/**
 * The origins this router is willing to be POSTed to by a browser.
 *
 * Browsers attach `Origin` to every cross-origin POST and MCP clients send none, so refusing a
 * non-self `Origin` closes the CORS simple-request hole on `/token` without touching CORS at all.
 * A form-encoded POST is a *simple* request: no preflight stands in the way, and while the page
 * cannot read the reply, the side effect lands. `/register` takes JSON and does preflight, and no
 * preflight is ever answered — it gets the same check anyway, because a rule that holds only where
 * it happens to be needed is a rule that stops holding when the content type changes.
 */
function selfOrigins(cfg: RouterConfig): string[] {
  return [
    `http://${cfg.host}:${cfg.port}`,
    `http://127.0.0.1:${cfg.port}`,
    `http://localhost:${cfg.port}`,
    `http://[::1]:${cfg.port}`,
  ];
}

function originRefused(req: IncomingMessage, cfg: RouterConfig): boolean {
  const origin = req.headers.origin;
  if (origin === undefined || origin === 'null') return false;
  return !selfOrigins(cfg).includes(origin);
}

// ---------------------------------------------------------------------------- HTML

/**
 * Every value interpolated into the page below goes through here.
 *
 * `AuthPages`' own documentation records that the callback pages interpolate without escaping and
 * that this is a reflected-markup hole preserved for parity. Nothing on this page inherits that:
 * upstream names, error text and query values are all attacker-influenceable in principle, and the
 * page is served on the loopback origin.
 */
export function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// ---------------------------------------------------------------------------- upstream states

export type UpstreamStateKind =
  | 'serving'
  | 'never-authorised'
  | 'half-authorised'
  | 'authorised-not-serving'
  | 'not-an-auth-problem';

export interface UpstreamReport {
  name: string;
  tools: number;
  kind: UpstreamStateKind;
  /** What the state is, in one clause. */
  headline: string;
  /** What to do about it. Empty when there is nothing useful to do. */
  remedy: string;
  /** The command to type, present only when running it can actually help. */
  command?: string;
  /** The error the router recorded, verbatim. */
  detail?: string;
}

/**
 * The verb the installed entry point actually exposes.
 *
 * `mcpr` is a shell function on the author's machine wrapping `node ~/Dev/mcp-router/dist/index.js`,
 * and an install under `~/.local/share` has no alias at all. Printing a command that only works if
 * the reader happens to share one shell profile is worse than printing none, so this is composed
 * from `argv[1]` — the script this process was actually started from.
 */
export function entryPoint(): string {
  const script = process.argv[1];
  if (!script) return 'mcp-router';
  return script.endsWith('.js') ? `node ${script}` : script;
}

/**
 * Every upstream, classified by what is actually wrong with it.
 *
 * The measurement this is written against, taken on 2026-08-21 from the live router: 13 upstreams,
 * 8 serving, 5 silent — and only two of the five are authorization problems. Three of them support
 * no authorization at all, report `authorized: true`, and serve nothing anyway. So the
 * not-an-auth-problem branch is the majority case rather than an edge, and the discriminator is
 * the **tool count**, never `auth.authorized` — which was true for four of the five.
 *
 * `mobbin` is the case this function exists to get right: a valid access token, a refresh token,
 * `authorized: true`, and zero tools. Telling its owner to re-authorize sends them to a command
 * that cannot help, so its row says so and carries no command.
 *
 * Read from `cfg.upstreams`, never from the credential directory. `pocketsmith.json` is on disk
 * with a half-finished registration for a server that is not an upstream at all; a report built
 * from the directory listing would name it and be wrong.
 */
export function reportUpstreams(cfg: RouterConfig, manifest: Manifest): UpstreamReport[] {
  const verb = entryPoint();
  return cfg.upstreams.map((u: UpstreamConfig): UpstreamReport => {
    const entry = manifest.servers[u.name];
    const indexError = entry?.error;
    const tools = indexError ? 0 : (entry?.tools.length ?? 0);
    if (tools > 0) {
      return {
        name: u.name,
        tools,
        kind: 'serving',
        headline: `serving ${tools} tool${tools === 1 ? '' : 's'}`,
        remedy: '',
      };
    }

    // `!isStdio(u) && u.oauth !== false` is `describe`'s own test for "this upstream can be
    // authorized at all". A stdio child and an HTTP upstream with `oauth: false` cannot, so their
    // silence is never an authorization story however encouraging the `auth.authorized` field is.
    const authCapable = !isStdio(u) && u.oauth !== false;
    if (!authCapable) {
      return {
        name: u.name,
        tools: 0,
        kind: 'not-an-auth-problem',
        headline: 'serving no tools, and it does not use authorisation',
        remedy: indexError
          ? 'Authorising will not help. Fix the error below, then re-index it.'
          : 'Authorising will not help. Re-index it and see what it reports.',
        command: `${verb} index --force`,
        detail: indexError,
      };
    }

    switch (recordState(u.name)) {
      case 'none':
        return {
          name: u.name,
          tools: 0,
          kind: 'never-authorised',
          headline: 'never authorised',
          remedy: 'Authorise it, and its tools appear at the next index.',
          command: `${verb} auth ${u.name}`,
          detail: indexError,
        };
      case 'started':
        return {
          name: u.name,
          tools: 0,
          kind: 'half-authorised',
          headline: 'authorisation was started and never finished',
          remedy: 'The browser leg never came back. Run it again.',
          command: `${verb} auth ${u.name}`,
          detail: indexError,
        };
      default: {
        const refused = !!indexError && isAuthFailure(indexError);
        const at = authorizedAt(u.name);
        const expiry = tokenExpiry(u.name);
        const expired = expiry !== undefined && Date.parse(expiry) < Date.now();
        const held = [
          at ? `authorised on ${at}` : 'authorised',
          expired ? `its access token expired on ${expiry}` : undefined,
          hasRefreshToken(u.name) ? 'a refresh token is held' : 'no refresh token is held',
        ]
          .filter(Boolean)
          .join(', ');
        // A refused credential with nothing to refresh from is the one sub-case where
        // re-authorising is the remedy. With a refresh token behind it, it is not.
        if (refused && !hasRefreshToken(u.name)) {
          return {
            name: u.name,
            tools: 0,
            kind: 'authorised-not-serving',
            headline: `${held}, and the credential it holds was refused`,
            remedy: 'There is nothing to refresh from, so authorise it again.',
            command: `${verb} auth ${u.name}`,
            detail: indexError,
          };
        }
        return {
          name: u.name,
          tools: 0,
          kind: 'authorised-not-serving',
          headline: `${held}, and serving no tools anyway`,
          remedy:
            'This is not an authorisation problem and re-authorising will not fix it. ' +
            'The upstream is reachable and authorised and is returning no tools.',
          detail: indexError,
        };
      }
    }
  });
}

/**
 * The same set, as one paragraph for `initialize`'s `instructions` field.
 *
 * This reaches the *model* rather than the human — hosts inject it into the prompt — so it is
 * written to answer "why can't you use X" correctly instead of making the assistant guess. Kept
 * short: it is paid for on every initialize.
 */
export function instructionsFor(cfg: RouterConfig, manifest: Manifest): string | undefined {
  const rows = reportUpstreams(cfg, manifest);
  const silent = rows.filter((r) => r.kind !== 'serving');
  const serving = rows.length - silent.length;
  const head =
    `This router relays ${rows.length} MCP servers; ${serving} are serving tools right now.`;
  if (silent.length === 0) return head;
  const lines = silent.map((r) => {
    const command = r.command ? ` To fix: \`${r.command}\`.` : '';
    return `- ${r.name}: ${r.headline}. ${r.remedy}${command}`;
  });
  return (
    `${head} ${silent.length} are not, and their tools are therefore absent from tools/list. ` +
    `Do not tell the user a capability does not exist when it is one of these:\n${lines.join('\n')}`
  );
}

// ---------------------------------------------------------------------------- sealed values

interface ClientBlob {
  u: string[];
  n?: string;
}

interface CodeBlob {
  c: string;
  r: string;
  h: string;
  x: number;
  j: string;
}

interface TokenBlob {
  t: 'access' | 'refresh';
  iat: number;
  exp?: number;
  s?: string;
}

/**
 * A `client_id` that carries its own registration.
 *
 * There is no store, so the redirect URIs travel inside the identifier and the HMAC is what makes
 * them unforgeable. Two consequences, both wanted: a registration survives a restart, and
 * registering the same URIs twice returns the same `client_id` rather than leaking a new one per
 * attempt. The failure this avoids is concrete — an in-memory authorization server forgets
 * registrations, the next `refresh_token` grant answers `invalid_client`, and some clients mark
 * the server logged-out and stop sending its tools. That is this very bug arriving by another route.
 */
export function mintClientId(redirectUris: string[], name?: string): string {
  return seal({ u: redirectUris, n: name } satisfies ClientBlob);
}

export function readClientId(clientId: string): ClientBlob | undefined {
  const blob = unseal<ClientBlob>(clientId);
  if (!blob || !Array.isArray(blob.u)) return undefined;
  return blob;
}

/**
 * Codes are single-use, and that is the one thing here that cannot be stateless.
 *
 * The set is bounded by the 60-second lifetime rather than by a cap on entries: an expired code is
 * refused by its own `x` field, so remembering it any longer buys nothing. A restart forgets at
 * most 60 seconds of codes, and the worst that costs is one retry of a flow that takes a second.
 */
const usedCodes = new Map<string, number>();

function burnCode(id: string, expiresAt: number): boolean {
  const now = Date.now();
  for (const [key, expiry] of usedCodes) if (expiry < now) usedCodes.delete(key);
  if (usedCodes.has(id)) return false;
  usedCodes.set(id, expiresAt);
  return true;
}

// ---------------------------------------------------------------------------- helpers

function json(res: ServerResponse, status: number, body: unknown): void {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'content-type': 'application/json',
    'content-length': Buffer.byteLength(payload),
    'cache-control': 'no-store',
  });
  res.end(payload);
}

function html(res: ServerResponse, status: number, body: string): void {
  res.writeHead(status, {
    'content-type': 'text/html; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store',
    // So the page cannot be silently framed by a site the user is visiting, in either the
    // legacy header or the modern directive. It is a consent screen; a framed consent screen
    // is a clickjacking target.
    'x-frame-options': 'DENY',
    'content-security-policy': "frame-ancestors 'none'; form-action 'self'",
    'referrer-policy': 'no-referrer',
  });
  res.end(body);
}

/**
 * `application/x-www-form-urlencoded`, and JSON for the clients that send it anyway.
 *
 * RFC 6749 specifies the form encoding and every standard library sends it, but some MCP clients
 * post JSON to `/token`. Accepting both costs four lines and turns a class of "Authenticate
 * failed" into a working flow; the security posture does not depend on the encoding, because the
 * Origin check has already run either way.
 */
function readForm(raw: string | undefined): URLSearchParams {
  if (raw === undefined) return new URLSearchParams();
  const trimmed = raw.trim();
  if (trimmed.startsWith('{')) {
    try {
      const parsed = JSON.parse(trimmed) as Record<string, unknown>;
      const params = new URLSearchParams();
      for (const [k, v] of Object.entries(parsed)) {
        if (typeof v === 'string') params.set(k, v);
      }
      return params;
    } catch {
      return new URLSearchParams();
    }
  }
  return new URLSearchParams(trimmed);
}

function issuerFor(cfg: RouterConfig): string {
  // Derived from the port actually bound, never a constant: a user who moved the port would
  // otherwise be handed endpoint URLs pointing at a router that is not there.
  return `http://127.0.0.1:${cfg.port}`;
}

export function isAuthServerPath(pathname: string): boolean {
  return (
    pathname === WELL_KNOWN_RESOURCE ||
    pathname.startsWith(`${WELL_KNOWN_RESOURCE}/`) ||
    pathname === WELL_KNOWN_AS ||
    pathname.startsWith(`${WELL_KNOWN_AS}/`) ||
    pathname === REGISTER_PATH ||
    pathname === AUTHORIZE_PATH ||
    pathname === TOKEN_PATH_OAUTH
  );
}

// ---------------------------------------------------------------------------- the page

function statePage(
  cfg: RouterConfig,
  manifest: Manifest,
  continueAction: string,
  hidden: Array<[string, string]>
): string {
  const rows = reportUpstreams(cfg, manifest);
  const silent = rows.filter((r) => r.kind !== 'serving');
  const serving = rows.length - silent.length;

  const list = silent
    .map((r) => {
      const command = r.command
        ? `<pre class="cmd">${escapeHtml(r.command)}</pre>`
        : '<p class="none">Nothing to run — see above.</p>';
      const detail = r.detail
        ? `<p class="err">It last reported: ${escapeHtml(r.detail)}</p>`
        : '';
      return (
        `<li><h3>${escapeHtml(r.name)}</h3>` +
        `<p class="state">${escapeHtml(r.headline)}</p>` +
        `<p>${escapeHtml(r.remedy)}</p>${detail}${command}</li>`
      );
    })
    .join('');

  const body = silent.length
    ? `<h2>${silent.length} of ${rows.length} are serving no tools</h2><ul>${list}</ul>`
    : `<h2>All ${rows.length} upstreams are serving tools</h2>`;

  const fields = hidden
    .map(
      ([k, v]) =>
        `<input type="hidden" name="${escapeHtml(k)}" value="${escapeHtml(v)}">`
    )
    .join('');

  return (
    '<!doctype html><meta charset="utf-8"><title>mcp-router</title>' +
    '<style>body{font:15px/1.6 -apple-system,system-ui,sans-serif;background:#141220;color:#eae8f5;' +
    'margin:0;padding:40px 20px}main{max-width:640px;margin:0 auto}' +
    'h1{font-size:19px;margin:0 0 6px}h2{font-size:15px;font-weight:600;margin:28px 0 10px}' +
    'h3{font-size:13px;margin:0 0 2px;font-family:ui-monospace,SFMono-Regular,monospace}' +
    'p{margin:0 0 6px;color:#a6a2c4}ul{list-style:none;padding:0;margin:0}' +
    'li{border:1px solid #2b2842;border-radius:10px;padding:14px 16px;margin:0 0 10px}' +
    '.state{color:#eae8f5}.err{color:#ff9230;font-family:ui-monospace,monospace;font-size:12px}' +
    '.none{font-size:12px}' +
    'pre.cmd{background:#0f0d18;border-radius:6px;padding:8px 10px;margin:8px 0 0;overflow-x:auto;' +
    'font-family:ui-monospace,SFMono-Regular,monospace;font-size:12px;color:#eae8f5}' +
    'button{font:inherit;background:#0091ff;color:#fff;border:0;border-radius:7px;' +
    'padding:8px 16px;margin-top:24px;cursor:pointer}</style>' +
    '<main><h1>Connect to mcp-router</h1>' +
    `<p>This router runs on your own machine and authenticates nobody: the token it is about to ` +
    `issue means "a local user completed this flow", and it grants nothing that loopback access ` +
    `does not already grant. ${serving} of ${rows.length} upstreams are serving tools.</p>` +
    body +
    `<form method="POST" action="${escapeHtml(continueAction)}">${fields}` +
    '<button type="submit">Continue</button></form></main>'
  );
}

// ---------------------------------------------------------------------------- dispatch

export interface AuthServerDeps {
  cfg: RouterConfig;
  manifest: Manifest;
}

/**
 * Handle one authorization-server request. Returns false when the path is not ours.
 *
 * Nothing here sets `Access-Control-Allow-Origin`, answers an `OPTIONS` preflight, sends
 * `Access-Control-Allow-Private-Network`, or puts a token in a cookie. A page may be able to
 * *send* some of these requests; it must never be able to read one back.
 */
export function handleAuthServer(
  req: IncomingMessage,
  res: ServerResponse,
  url: URL,
  rawBody: string | undefined,
  deps: AuthServerDeps
): boolean {
  const p = url.pathname;
  if (!isAuthServerPath(p)) return false;
  const { cfg } = deps;
  const issuer = issuerFor(cfg);

  // ---------------------------------------------------------------- metadata
  if (p === WELL_KNOWN_RESOURCE || p.startsWith(`${WELL_KNOWN_RESOURCE}/`)) {
    if (req.method !== 'GET') return methodNotAllowed(res);
    json(res, 200, {
      resource: `${issuer}/mcp`,
      authorization_servers: [issuer],
      scopes_supported: ['mcp'],
      bearer_methods_supported: ['header'],
    });
    return true;
  }

  if (p === WELL_KNOWN_AS || p.startsWith(`${WELL_KNOWN_AS}/`)) {
    if (req.method !== 'GET') return methodNotAllowed(res);
    json(res, 200, {
      issuer,
      authorization_endpoint: `${issuer}${AUTHORIZE_PATH}`,
      token_endpoint: `${issuer}${TOKEN_PATH_OAUTH}`,
      registration_endpoint: `${issuer}${REGISTER_PATH}`,
      response_types_supported: ['code'],
      grant_types_supported: ['authorization_code', 'refresh_token'],
      code_challenge_methods_supported: ['S256'],
      token_endpoint_auth_methods_supported: ['none'],
      scopes_supported: ['mcp'],
    });
    return true;
  }

  // ---------------------------------------------------------------- registration
  if (p === REGISTER_PATH) {
    if (req.method !== 'POST') return methodNotAllowed(res);
    if (originRefused(req, cfg)) return forbiddenOrigin(res);
    // Parsed here rather than by the dispatcher, so one reader owns the stream. A body that is
    // not JSON is an empty registration, which fails the redirect_uris check below with the
    // message that names the real problem.
    let b: { redirect_uris?: unknown; client_name?: unknown } = {};
    if (rawBody) {
      try {
        b = JSON.parse(rawBody) as typeof b;
      } catch {
        b = {};
      }
    }
    const uris = Array.isArray(b.redirect_uris) ? b.redirect_uris : [];
    if (uris.length === 0 || uris.length > MAX_REDIRECT_URIS) {
      json(res, 400, {
        error: 'invalid_redirect_uri',
        error_description: `redirect_uris must name between 1 and ${MAX_REDIRECT_URIS} URIs`,
      });
      return true;
    }
    for (const uri of uris) {
      if (typeof uri !== 'string' || !isLoopbackRedirect(uri)) {
        json(res, 400, {
          error: 'invalid_redirect_uri',
          error_description:
            'every redirect_uri must be an http loopback address ' +
            '(127.0.0.1, localhost or [::1]); this router never redirects off the machine',
        });
        return true;
      }
    }
    const name = typeof b.client_name === 'string' ? b.client_name.slice(0, 200) : undefined;
    const clientId = mintClientId(uris as string[], name);
    json(res, 201, {
      client_id: clientId,
      client_id_issued_at: Math.floor(Date.now() / 1000),
      redirect_uris: uris,
      grant_types: ['authorization_code', 'refresh_token'],
      response_types: ['code'],
      token_endpoint_auth_method: 'none',
      ...(name ? { client_name: name } : {}),
    });
    return true;
  }

  // ---------------------------------------------------------------- authorize
  if (p === AUTHORIZE_PATH) {
    if (req.method === 'GET') return authorizeGet(res, url, deps);
    if (req.method === 'POST') {
      if (originRefused(req, cfg)) return forbiddenOrigin(res);
      return authorizePost(res, readForm(rawBody));
    }
    return methodNotAllowed(res);
  }

  // ---------------------------------------------------------------- token
  if (p === TOKEN_PATH_OAUTH) {
    if (req.method !== 'POST') return methodNotAllowed(res);
    if (originRefused(req, cfg)) return forbiddenOrigin(res);
    return tokenPost(res, readForm(rawBody));
  }

  return false;
}

function methodNotAllowed(res: ServerResponse): boolean {
  json(res, 405, { error: 'invalid_request', error_description: 'method not allowed' });
  return true;
}

/**
 * A browser POST from an origin that is not this router.
 *
 * 403 rather than a CORS answer, because the point is that the request must not execute at all —
 * a `text/plain` or form-encoded POST is a CORS *simple request* and runs whether or not its
 * response can be read.
 */
function forbiddenOrigin(res: ServerResponse): boolean {
  json(res, 403, {
    error: 'invalid_request',
    error_description: 'cross-origin requests are not accepted on this endpoint',
  });
  return true;
}

interface AuthorizeParams {
  clientId: string;
  redirectUri: string;
  challenge: string;
  state?: string;
  scope?: string;
}

/**
 * Everything `/authorize` must agree about before anything is minted.
 *
 * Returns the parameters or the reason they are unusable. The distinction the caller then draws is
 * the one that matters: an error about the `redirect_uri` itself may never be *redirected* to it,
 * because that would be a hop to a destination we have just decided we do not trust.
 */
function validateAuthorize(query: URLSearchParams): AuthorizeParams | { fatal: string } {
  const clientId = query.get('client_id') ?? '';
  const redirectUri = query.get('redirect_uri') ?? '';
  const client = readClientId(clientId);
  if (!client) return { fatal: 'client_id is not one this router issued' };
  if (!redirectUri) return { fatal: 'redirect_uri is required' };
  // Both, in this order: registered, and loopback. The registration is signed, so the second
  // check is not redundant paranoia — it is what holds if a registration ever predates this rule.
  if (!client.u.includes(redirectUri)) {
    return { fatal: 'redirect_uri is not one this client registered' };
  }
  if (!isLoopbackRedirect(redirectUri)) {
    return { fatal: 'redirect_uri must be an http loopback address' };
  }
  return {
    clientId,
    redirectUri,
    challenge: query.get('code_challenge') ?? '',
    state: query.get('state') ?? undefined,
    scope: query.get('scope') ?? undefined,
  };
}

/** `error=` back to a redirect_uri that has already been proven registered and loopback. */
function redirectError(
  res: ServerResponse,
  redirectUri: string,
  error: string,
  description: string,
  state?: string
): boolean {
  const target = new URL(redirectUri);
  target.searchParams.set('error', error);
  target.searchParams.set('error_description', description);
  if (state !== undefined) target.searchParams.set('state', state);
  res.writeHead(302, { location: target.toString(), 'cache-control': 'no-store' });
  res.end();
  return true;
}

function fatalPage(res: ServerResponse, reason: string): boolean {
  html(
    res,
    400,
    '<!doctype html><meta charset="utf-8"><title>Authorization failed</title>' +
      '<style>body{font:15px/1.6 -apple-system,system-ui,sans-serif;background:#141220;' +
      'color:#eae8f5;display:grid;place-items:center;height:100vh;margin:0;text-align:center}' +
      'h1{font-size:19px;margin:0 0 6px}p{margin:0;color:#a6a2c4}</style>' +
      `<div><h1>Authorization failed</h1><p>${escapeHtml(reason)}</p></div>`
  );
  return true;
}

/**
 * The interstitial. This is the one surface with guaranteed human eyes on it.
 *
 * The "you can close this window" page belongs to the *client's* loopback listener, not to us, so
 * this is the only page the router owns in this flow — which is why the upstream report renders
 * here rather than anywhere further along.
 */
function authorizeGet(res: ServerResponse, url: URL, deps: AuthServerDeps): boolean {
  const checked = validateAuthorize(url.searchParams);
  if ('fatal' in checked) return fatalPage(res, checked.fatal);

  const responseType = url.searchParams.get('response_type') ?? '';
  if (responseType !== 'code') {
    return redirectError(
      res,
      checked.redirectUri,
      'unsupported_response_type',
      'only response_type=code is supported',
      checked.state
    );
  }
  // PKCE S256 is required rather than merely supported. `plain` is a challenge that is its own
  // verifier, which on a machine where any local process can read a redirect is no protection.
  if ((url.searchParams.get('code_challenge_method') ?? '') !== 'S256' || !checked.challenge) {
    return redirectError(
      res,
      checked.redirectUri,
      'invalid_request',
      'code_challenge with code_challenge_method=S256 is required',
      checked.state
    );
  }

  const hidden: Array<[string, string]> = [
    ['client_id', checked.clientId],
    ['redirect_uri', checked.redirectUri],
    ['code_challenge', checked.challenge],
  ];
  if (checked.state !== undefined) hidden.push(['state', checked.state]);
  if (checked.scope !== undefined) hidden.push(['scope', checked.scope]);
  html(res, 200, statePage(deps.cfg, deps.manifest, AUTHORIZE_PATH, hidden));
  return true;
}

/** The Continue button. Everything is re-validated; nothing is trusted for having been on the page. */
function authorizePost(res: ServerResponse, form: URLSearchParams): boolean {
  const checked = validateAuthorize(form);
  if ('fatal' in checked) return fatalPage(res, checked.fatal);
  if (!checked.challenge) {
    return redirectError(
      res,
      checked.redirectUri,
      'invalid_request',
      'code_challenge is required',
      checked.state
    );
  }

  const code = seal({
    c: checked.clientId,
    r: checked.redirectUri,
    h: checked.challenge,
    x: Date.now() + CODE_TTL_MS,
    j: b64url(randomBytes(9)),
  } satisfies CodeBlob);

  const target = new URL(checked.redirectUri);
  target.searchParams.set('code', code);
  if (checked.state !== undefined) target.searchParams.set('state', checked.state);
  res.writeHead(302, { location: target.toString(), 'cache-control': 'no-store' });
  res.end();
  return true;
}

function tokenError(res: ServerResponse, error: string, description: string): boolean {
  json(res, 400, { error, error_description: description });
  return true;
}

function issue(res: ServerResponse, scope: string | undefined): boolean {
  const now = Math.floor(Date.now() / 1000);
  json(res, 200, {
    access_token: seal({
      t: 'access',
      iat: now,
      exp: now + ACCESS_TTL_SECONDS,
      s: scope,
    } satisfies TokenBlob),
    token_type: 'Bearer',
    expires_in: ACCESS_TTL_SECONDS,
    // Deliberately NOT rotated on refresh. A rotating refresh token has to be paired with a
    // grace window, because clients crash between rotating and storing; a stable one has no such
    // window to get wrong, and rotation buys nothing for a credential that confers no privilege.
    refresh_token: seal({ t: 'refresh', iat: now, s: scope } satisfies TokenBlob),
    // Echoed rather than rejected: a client asking for a scope this router does not model is not
    // an error worth failing an otherwise complete flow over.
    ...(scope ? { scope } : {}),
  });
  return true;
}

function tokenPost(res: ServerResponse, form: URLSearchParams): boolean {
  const grant = form.get('grant_type') ?? '';

  if (grant === 'authorization_code') {
    const code = form.get('code') ?? '';
    const verifier = form.get('code_verifier') ?? '';
    const blob = unseal<CodeBlob>(code);
    if (!blob) return tokenError(res, 'invalid_grant', 'the authorization code is not valid');
    if (Date.now() > blob.x) return tokenError(res, 'invalid_grant', 'the authorization code has expired');
    // Bound to the client and the redirect it was issued for, so a code intercepted by another
    // local listener cannot be redeemed against a different registration.
    if (blob.c !== (form.get('client_id') ?? blob.c)) {
      return tokenError(res, 'invalid_grant', 'the code was issued to a different client');
    }
    const redirect = form.get('redirect_uri');
    if (redirect !== null && redirect !== blob.r) {
      return tokenError(res, 'invalid_grant', 'redirect_uri does not match the one the code was issued for');
    }
    if (!verifier) return tokenError(res, 'invalid_request', 'code_verifier is required');
    const digest = b64url(createHash('sha256').update(verifier).digest());
    if (digest !== blob.h) return tokenError(res, 'invalid_grant', 'the PKCE verifier does not match');
    if (!burnCode(blob.j, blob.x)) {
      return tokenError(res, 'invalid_grant', 'the authorization code has already been used');
    }
    return issue(res, form.get('scope') ?? undefined);
  }

  if (grant === 'refresh_token') {
    // Validated rather than waved through. An issuer that mints a fresh token for any refresh
    // request is an issuer whose tokens mean nothing, and validating costs nothing once they are
    // signed — the signature is the whole check.
    const presented = form.get('refresh_token') ?? '';
    const blob = unseal<TokenBlob>(presented);
    if (!blob || blob.t !== 'refresh') {
      return tokenError(res, 'invalid_grant', 'the refresh token is not one this router issued');
    }
    return issue(res, form.get('scope') ?? blob.s ?? undefined);
  }

  return tokenError(
    res,
    'unsupported_grant_type',
    'only authorization_code and refresh_token are supported'
  );
}
