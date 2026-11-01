import { readFileSync, writeFileSync, renameSync, existsSync, mkdirSync } from 'node:fs';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { join } from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { SSEClientTransport } from '@modelcontextprotocol/sdk/client/sse.js';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import {
  isStdio,
  parseServer,
  upstreamHash,
  ROUTER_HOME,
  DEFAULT_CONFIG_PATH,
  type RawServer,
  type RouterConfig,
  type UpstreamConfig,
  type HttpUpstream,
} from './config.js';
import { UpstreamPool } from './pool.js';
import { collectNeedles, redactArgs, type Needle } from './secrets.js';
import { buildExport, parseOnly, readServers } from './export.js';
import {
  buildManifest,
  loadManifest,
  manifestCommitter,
  saveManifest,
  diffTools,
  toolsDigest,
  toolApprovalDigest,
  placardFor,
  type ManifestStore,
} from './manifest.js';
import { withExclusiveLock, lockTimeoutMs, DAEMON_TIMEOUT_MS } from './lock.js';
import { searchRegistries } from './registry.js';
import { isRefusal, readPackageDocuments } from './document.js';
import { UsageStore, projectOf } from './usage.js';
import {
  beginAuth,
  clearAuth,
  hasTokens,
  authorizedAt,
  currentFlow,
  isAuthFailure,
  FileOAuthProvider,
} from './auth.js';
import { LiveReload } from './livereload.js';
import { askSessionsToReload, listSessions } from './sessions.js';
import { harnessEnvelope, type HarnessInventory } from './harness.js';
import { INSIGHTS_WINDOWS, insightsEnvelope, insightsWindowHours } from './insights.js';
import { analystEnvelope, ANALYST_UNAVAILABLE, type AnalystPort } from './analyst.js';
import { AnalystSettingsRefusal } from './analyst-lanes.js';
import { log } from './log.js';
import { wireInstant, type IssuedCode, type Pairing } from './pairing.js';
import { removePairedPhone, readPairedPhones } from './paired-phones.js';
import type { PairingListenerStatus } from './pairing-listener.js';
import { extensionRoute, isExtensionsPath } from './extension-routes.js';
import type { ExtensionStore } from './extensions.js';
import { declarationFor, type InboxRow, type InboxStore } from './inbox.js';
import { skillsValue } from './skills.js';

export const TOKEN_PATH = join(ROUTER_HOME, 'control.token');

/**
 * A shared secret for the mutating half of the control API.
 *
 * The Host allowlist on /mcp defeats DNS rebinding but not plain CSRF: a page the
 * user visits can POST straight to http://127.0.0.1:8879 with a correct Host header,
 * and a `text/plain` body is a CORS "simple request" that needs no preflight — the
 * page cannot read the reply, but the side effect lands. Installing a server means
 * running an arbitrary command with the user's environment, so that side effect is
 * the whole machine. The token lives in a 0600 file no web page can read, and the
 * JSON content-type requirement forces a preflight that is never answered.
 */
export function controlToken(): string {
  if (existsSync(TOKEN_PATH)) {
    const t = readFileSync(TOKEN_PATH, 'utf8').trim();
    if (t) return t;
  }
  mkdirSync(ROUTER_HOME, { recursive: true, mode: 0o700 });
  const t = randomBytes(32).toString('hex');
  writeFileSync(TOKEN_PATH, t + '\n', { mode: 0o600 });
  log.info(`wrote a new control token -> ${TOKEN_PATH}`);
  return t;
}

function tokenOk(req: IncomingMessage, expected: string): boolean {
  const header = req.headers.authorization ?? '';
  const supplied = header.startsWith('Bearer ') ? header.slice(7) : (req.headers['x-mcpr-token'] as string) ?? '';
  const a = Buffer.from(supplied);
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}

export interface ControlDeps {
  cfg: RouterConfig;
  /** The same Map the pool holds, mutated in place so a reload reaches it. */
  upstreams: Map<string, UpstreamConfig>;
  pool: UpstreamPool;
  manifest: ManifestStore;
  usage: UsageStore;
  /** The open standalone GET /mcp streams. R29: telling attached sessions the tool list moved. */
  liveReload: LiveReload;
  /** The phone-pairing codes this router has issued. One per process, shared by every pairing route. */
  pairing: Pairing;
  /** The router home. Where `paired-phones.json` lives, which DELETE /pairing/phones/:phoneId edits. */
  routerHome: string;
  /** What the phone listener has actually bound. Read per request, so a listener that comes or goes is reported as it is. */
  pairingListener: () => PairingListenerStatus;
  /** R28. Absent answers 503 on every /extensions route, as the Swift router does. */
  extensions?: ExtensionStore;
  /** The picks a phone has sent, held for review. Absent answers 503 on every /inbox route. */
  inbox?: InboxStore;
  /** Claude Code's home, which GET /skills reads and never writes. Absent answers 503 on /skills. */
  claudeHome?: string;
  /** Reads each agent client's config for GET /harnesses. Absent means the route answers 503. */
  harnesses?: HarnessInventory;
  /** The session analyst. Absent answers 503 on POST /insights/analyse and PATCH /insights/analyst, and
   * `analyst: null` on GET /insights. */
  analyst?: AnalystPort;
}

/** The wire shape of an issued code. Shared by the route that mints one and the route that names it. */
function codeBody(issued: IssuedCode) {
  return {
    code: issued.code,
    issuedAt: wireInstant(issued.issuedAt),
    expiresAt: wireInstant(issued.expiresAt),
  };
}

function json(res: ServerResponse, status: number, body: unknown): void {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'content-type': 'application/json',
    'content-length': Buffer.byteLength(payload),
    // No Access-Control-Allow-Origin anywhere: a page may be able to *send* a
    // simple request, but it must never be able to read one back.
    'cache-control': 'no-store',
  });
  res.end(payload);
}

/** Read servers.json, apply a change, write it back atomically. */
function editConfigFile(fn: (servers: Record<string, RawServer>) => void): void {
  withExclusiveLock(DEFAULT_CONFIG_PATH, lockTimeoutMs(DAEMON_TIMEOUT_MS), () => {
    const raw = existsSync(DEFAULT_CONFIG_PATH)
      ? (JSON.parse(readFileSync(DEFAULT_CONFIG_PATH, 'utf8')) as { mcpServers?: Record<string, RawServer> })
      : {};
    raw.mcpServers ??= {};
    fn(raw.mcpServers);
    const tmp = `${DEFAULT_CONFIG_PATH}.tmp-${process.pid}`;
    writeFileSync(tmp, JSON.stringify(raw, null, 2), { mode: 0o600 });
    renameSync(tmp, DEFAULT_CONFIG_PATH);
  });
}

/** Re-read servers.json into the live maps, in place, so the pool sees the change. */
function reload(deps: ControlDeps): void {
  const raw = JSON.parse(readFileSync(DEFAULT_CONFIG_PATH, 'utf8')) as {
    mcpServers?: Record<string, RawServer>;
  };
  const next = new Map<string, UpstreamConfig>();
  for (const [name, s] of Object.entries(raw.mcpServers ?? {})) {
    const parsed = parseServer(name, s);
    if ('upstream' in parsed) next.set(name, parsed.upstream);
  }
  deps.upstreams.clear();
  for (const [k, v] of next) deps.upstreams.set(k, v);
  deps.cfg.upstreams.length = 0;
  deps.cfg.upstreams.push(...next.values());
  log.info(`config reloaded: ${next.size} upstreams`);
}

/**
 * Tell every attached session that the served tool list moved.
 *
 * Fired from the mutations that change what `tools/list` would answer, and from nowhere else: a
 * notification on a change that did not alter the tool list is a re-fetch every session pays for
 * and nobody needed. It is deliberately not awaited by the route that triggers it — the client is
 * downstream of the router and must never be able to hold a control-API response open.
 *
 * Whether the config in `servers.json` should ALSO be pushed at the sessions over their unix
 * sockets is `notifySessions`'s decision, and it is off unless the user turned it on. That
 * asymmetry is the point: this notification is the protocol's own, addressed to the client and
 * costing it one re-fetch, while the socket message is text landing in somebody's turn.
 */
function announceTools(deps: ControlDeps, reason: string): void {
  // Record where this change left the manifest, so the poller in `router.ts` does not announce
  // the same move a second time three seconds later.
  void deps.liveReload.announceToolsChanged(reason, deps.manifest.fileStamp()).catch((err: Error) => {
    log.warn(`live-reload: announcing "${reason}" failed: ${err.message}`);
  });
  void maybeAskSessions(reason);
}

/**
 * The opt-in half. Reads the flag from the config file on each call rather than caching it, so
 * turning it off takes effect at once rather than at the next restart.
 */
function notifySessionsEnabled(): boolean {
  try {
    const raw = JSON.parse(readFileSync(DEFAULT_CONFIG_PATH, 'utf8')) as { notifySessions?: unknown };
    return raw.notifySessions === true;
  } catch {
    return false;
  }
}

function maybeAskSessions(reason: string): Promise<unknown> {
  if (!notifySessionsEnabled()) return Promise.resolve(undefined);
  return askSessionsToReload(reason).catch((err: Error) => {
    log.warn(`sessions: asking sessions to reload after "${reason}" failed: ${err.message}`);
  });
}

/** Build the transport factory `beginAuth` needs for one HTTP upstream. */
function authTransportFor(u: HttpUpstream) {
  return (provider: FileOAuthProvider) => {
    const opts = {
      authProvider: provider,
      requestInit: Object.keys(u.headers).length ? { headers: u.headers } : undefined,
    };
    const t =
      u.transport === 'sse'
        ? new SSEClientTransport(new URL(u.url), opts)
        : new StreamableHTTPClientTransport(new URL(u.url), opts);
    const client = new Client({ name: 'mcp-router', version: '0.1.0' }, { capabilities: {} });
    return {
      connect: () => client.connect(t),
      finishAuth: (code: string) => t.finishAuth(code),
      close: async () => {
        await client.close().catch(() => undefined);
        await t.close().catch(() => undefined);
      },
    };
  };
}

/**
 * One server as the app sees it.
 *
 * Env and header VALUES never appear here — only their key names. This endpoint is
 * reachable by anything that can open a loopback socket, and a server's env is
 * where its API keys live. Argument values that look like secrets are removed by
 * `redactArgs` (DEF-070); `needles` carries the literal secrets that pass also removes.
 */
function describe(u: UpstreamConfig, deps: ControlDeps, needles: Needle[]) {
  const entry = deps.manifest.current().servers[u.name];
  const live = deps.pool.status().find((s) => s.name === u.name);
  const stat = deps.usage.statFor(u.name);
  const pending = deps.pool.pending().find((p) => p.server === u.name);
  const needsAuth = !isStdio(u) && u.oauth !== false;

  /*
   * `authorized` used to be `hasTokens(name)` alone, which reports that a FILE exists.
   * Measured on 2026-08-20 against a live upstream: this object carried
   * `indexError: "[-32603] Internal error: Authentication required"` and
   * `auth.authorized: true` at the same time, three lines apart, because the token
   * file was on disk and the server had stopped honouring the refresh inside it.
   * REQ-007 says the router never displays what it does not observe, and a field named
   * `authorized` reporting a fact about the filesystem is exactly that.
   *
   * Read from the manifest as well as the live pool, deliberately: `pendingAuth` is
   * in-memory and empty on a fresh start, while `entry.error` persists, so a router
   * restarted after a rejection would otherwise report `authorized: true` again until
   * something happened to re-index.
   */
  const recordedRefusal =
    entry?.error && isAuthFailure(entry.error) ? entry.error : undefined;
  /*
   * A refusal the manifest recorded BEFORE the credential was last authorized is stale, and
   * reporting it tells the user the credential they have just fixed is still being refused.
   *
   * Without this the field is decided by a race. Completing an authorization re-indexes, and
   * that re-index is fire-and-forget on both routers (`void flow.completed.then(...)` here), so
   * `GET /servers/:name` immediately afterwards may read a manifest written before the browser
   * hop. Measured 20 Aug 2026: the oauth lane run inside the full gate had this router reporting
   * `authorized: true` and the Swift router reporting `authorized: false` with
   * `rejected: "[-32603] Internal error: Authentication required"` and an `authorizedAt` newer
   * than the error beside it; the same lane run on its own, under no load, had both at `true`
   * over 21 checks. Whichever side loses the race is a property of the machine that day.
   *
   * `Date.parse` returns NaN on anything it cannot read, and every comparison against NaN is
   * false, so an unparseable stamp on either side reports the refusal rather than hiding it.
   * That is the safe direction: a refusal shown once too often costs the user a re-authorization
   * they did not need, and one hidden costs them an upstream that silently serves no tools.
   */
  const authorizedAtIso = authorizedAt(u.name);
  const refusalIsStale =
    recordedRefusal !== undefined &&
    entry?.builtAt !== undefined &&
    authorizedAtIso !== undefined &&
    Date.parse(authorizedAtIso) > Date.parse(entry.builtAt);
  const authRejection = pending?.reason ?? (refusalIsStale ? undefined : recordedRefusal);

  return {
    name: u.name,
    transport: u.transport,
    state: live?.state ?? 'idle',
    inFlight: live?.inFlight ?? 0,
    callsServed: live?.callsServed ?? 0,
    idleSec: live?.idleSec ?? 0,
    ...(isStdio(u)
      ? { command: u.command, args: redactArgs(u.args, needles), cwd: u.cwd, envKeys: Object.keys(u.env).sort(), envFiles: u.envFiles }
      : { url: u.url, headerKeys: Object.keys(u.headers).sort() }),
    documentAvailable: isStdio(u) && !!(u.packageRoot || u.cwd),
    hash: upstreamHash(u),
    tools: entry?.error ? 0 : (entry?.tools.length ?? 0),
    toolNames: entry?.error ? [] : entry?.tools.map((t) => t.name) ?? [],
    indexedAt: entry?.builtAt,
    indexError: entry?.error,
    projects: u.projects ?? [],
    warm: !!u.warm,
    /*
     * `!!u.disabled`, matching `warm` above rather than reading the typed field, because
     * `parseServer` copies the raw value through and a config saying `"disabled": "yes"`
     * must report the same truthiness both routers' JavaScript semantics would give it.
     *
     * Reported for EVERY server, never omitted when false. The app decodes this as a
     * non-optional Bool precisely so that a router which stopped sending it fails loudly
     * instead of drawing a disabled server as live.
     *
     * A flat fact rather than a derived status. The app already resolves seven conditions
     * into one row state in its own precedence chain, and a server can be disabled AND
     * holding a schema change at once — which is the ordinary case, since disabling is
     * what the held-change sheet offers — so an enum here could not encode it.
     */
    disabled: !!u.disabled,
    placard: placardFor(u, entry),
    pendingChange: entry?.pending
      ? { seenAt: entry.pending.seenAt, count: diffTools(entry.tools, entry.pending.tools).length }
      : undefined,
    auth: needsAuth
      ? {
          supported: true,
          authorized: hasTokens(u.name) && !authRejection,
          authorizedAt: authorizedAt(u.name),
          // Present only when we hold a credential the upstream has refused, which is
          // the state that has a remedy: `mcp-router auth <name>`. Absent means either
          // working, or never authorized at all — and those two are told apart by
          // `authorizedAt`, which a server that has never authorized does not carry.
          rejected: authRejection,
          pendingUrl: pending?.url,
        }
      : { supported: false, authorized: true },
    usage: stat ?? { calls: 0, errors: 0, projects: {} },
  };
}

/** Spawn one candidate server in a throwaway pool and record its tools. */
async function indexOne(
  u: UpstreamConfig,
  cfg: RouterConfig,
  /*
   * The live pool, so a credential rejection outlives this call.
   *
   * The scratch pool below is deliberate — a re-index must not disturb the serving pool's
   * connections, so it gets its own with `idleMs: 0`. The consequence nobody had noticed is
   * that everything the re-index LEARNS dies with it: `noteAuthFailure` landed on an object
   * shut down four lines later, so `/status` and `mcp-router status` never saw it and an
   * upstream whose token had been revoked kept reporting `idle`. The manifest keeps the
   * error, which is why `describe` can still tell; the pool is what the operator surfaces
   * read, and it was being told nothing.
   */
  live?: UpstreamPool
): Promise<{ tools: number; error?: string }> {
  const pool = new UpstreamPool(new Map([[u.name, u]]), 0, cfg.startupTimeoutMs);
  try {
    /*
     * R19 — the manifest is loaded inside the lock, immediately before the save.
     *
     * `buildManifest` spawns a child and waits for it, which is seconds; the snapshot below is only
     * what decides staleness, and the row it produces is merged into whatever is on disk when the
     * commit runs. The daemon's bound rather than the one-shot's: this runs inside an async control
     * handler, so a contended write should fail fast and visibly rather than stall the control API.
     *
     * A lock that could not be taken is reported as the index's own error. Nothing was changed, and
     * that is what the message says — `POST /servers` answers 422 with it and adds nothing, which
     * is the same answer it already gives for a server that would not start.
     */
    const snapshot = loadManifest(cfg.manifestPath);
    const { manifest, failed } = await buildManifest([u], pool, snapshot, {
      force: true,
      commit: manifestCommitter(cfg.manifestPath, lockTimeoutMs(DAEMON_TIMEOUT_MS)),
    });
    const entry = manifest.servers[u.name];
    const error = failed.length ? entry?.error : undefined;
    // Whatever the scratch pool learned, hand over. `buildManifest` is what noticed the
    // refusal and it wrote the warning already, so this transfers rather than re-announces.
    if (live) for (const entryPending of pool.pending()) live.adoptPending(entryPending);
    return { tools: entry?.tools.length ?? 0, error };
  } catch (err) {
    const message = (err as Error).message;
    log.error(`could not record the index of "${u.name}": ${message}`);
    return { tools: 0, error: message };
  } finally {
    await pool.shutdown();
  }
}

/** A declaration that did not land. Nothing was written when one is returned. */
interface Refusal {
  status: number;
  reason: string;
  error: string;
}

/** Durable evidence that this review row, rather than a pre-existing server, made the declaration. */
interface InboxApproval { id: string; reviewDigest: string }
type ApprovedServer = RawServer & { inboxApproval?: InboxApproval };
class DeclarationRefused extends Error {
  constructor(readonly refusal: Refusal) { super(refusal.error); }
}

/** A declaration that landed: the tools it indexed, and whether its server still needs the authorize button. */
interface Declared {
  tools: number;
  error?: string;
  needsAuth: boolean;
}

/*
 * Declare one server: index it, then write it to servers.json and reload. POST /servers and an inbox accept both come
 * through here (plan §2.4), so the declaration a reviewer accepts is the one a typed POST would make.
 *
 * Index before adopting, so a server that cannot start never lands in the config. The exception is an authorization
 * failure: an OAuth server is *expected* to refuse a first connection, and rejecting it here would make it impossible
 * to add one at all. That case is adopted with its error recorded, and the app's next move is the authorize button.
 */
async function declareServer(
  deps: ControlDeps,
  name: string,
  raw: RawServer,
  opts: { force: boolean; beforeWrite?: () => Refusal | undefined; inboxApproval?: InboxApproval }
): Promise<Declared | Refusal> {
  const taken = { status: 409, reason: 'alreadyDeclared', error: `a server named "${name}" already exists` };
  if (deps.upstreams.has(name)) return taken;
  const parsed = parseServer(name, raw);
  if ('reason' in parsed) return { status: 400, reason: 'badRequest', error: parsed.reason };

  const { tools, error } = await indexOne(parsed.upstream, deps.cfg, deps.pool);
  const authPending = !!error && /not authorized|unauthorized|401/i.test(error);
  if (error && !authPending && !opts.force) return { status: 422, reason: 'indexFailed', error };

  /*
   * The index awaited, so the name may have been declared meanwhile, and the caller's own condition may have changed.
   * Both are checked here, with nothing awaited between the check and the write.
   */
  if (deps.upstreams.has(name)) return taken;
  const refused = opts.beforeWrite?.();
  if (refused) return refused;

  const entry: ApprovedServer = { ...raw };
  delete (entry as { name?: string }).name;
  // Only this accept path writes provenance. A raw POST cannot claim another row's acceptance.
  delete entry.inboxApproval;
  if (opts.inboxApproval) entry.inboxApproval = opts.inboxApproval;
  try {
    editConfigFile((servers) => {
      if (servers[name] !== undefined) throw new DeclarationRefused(taken);
      const refused = opts.beforeWrite?.();
      if (refused) throw new DeclarationRefused(refused);
      servers[name] = entry;
    });
  } catch (err) {
    if (err instanceof DeclarationRefused) return err.refusal;
    throw err;
  }
  reload(deps);
  announceTools(deps, `added the server "${name}"`);
  log.info(`added upstream "${name}" (${tools} tools${error ? `, ${error}` : ''})`);
  return { tools, error, needsAuth: authPending };
}

type InboxVerb = 'accept' | 'decline' | 'restore';

/** What an inbox route answers: the status and the body it writes. */
interface Answered {
  status: number;
  body: unknown;
}

const reply = (status: number, reason: string, error: string): Answered => ({ status, body: { error, reason } });

/*
 * The three decisions on a held row (plan §2.3, §2.4). Only accept declares anything, and it declares through
 * declareServer. Every refusal is answered before anything is written, so neither inbox.json nor servers.json changes.
 */
async function inboxAction(
  deps: ControlDeps,
  inbox: InboxStore,
  id: string,
  verb: InboxVerb,
  body: unknown
): Promise<Answered> {
  const row = inbox.find(id);
  if (!row) return reply(404, 'notFound', `no inbox row "${id}"`);

  if (verb === 'decline') {
    if (row.state !== 'waiting') return reply(409, 'notWaiting', `the row is ${row.state}, not waiting`);
    inbox.setState(id, 'declined');
    return { status: 200, body: { id, state: 'declined' } };
  }
  if (verb === 'restore') {
    if (row.state !== 'declined') {
      return reply(409, 'notDeclined', `the row is ${row.state}; only a declined row can be restored`);
    }
    inbox.setState(id, 'waiting');
    return { status: 200, body: { id, state: 'waiting' } };
  }
  return acceptRow(deps, inbox, row, body);
}

async function acceptRow(deps: ControlDeps, inbox: InboxStore, row: InboxRow, body: unknown): Promise<Answered> {
  if (row.state !== 'waiting') return reply(409, 'notWaiting', `the row is ${row.state}, not waiting`);
  if (row.resolved === null) {
    return reply(422, 'unresolved', `${row.id} did not resolve in the registry, so there is nothing to declare`);
  }
  // The reviewer accepts what they were shown. A row replaced between view and accept has another digest (D11).
  if ((body as { reviewDigest?: unknown } | undefined)?.reviewDigest !== row.reviewDigest) {
    return reply(409, 'reviewChanged', `${row.id} changed after it was shown; review it again`);
  }
  const built = declarationFor(row.resolved);
  if ('reason' in built) return reply(422, built.reason, built.error);
  const wanted = parseServer(built.name, built.server);
  if (!('upstream' in wanted)) return reply(422, 'notInstallable', wanted.reason);

  // A retry can reconcile only a declaration this row itself wrote. The provenance and the whole
  // normalized configuration are checked under the same cross-process lock used by declarations.
  const reconciled = withExclusiveLock(DEFAULT_CONFIG_PATH, lockTimeoutMs(DAEMON_TIMEOUT_MS), () => {
    const held = existsSync(DEFAULT_CONFIG_PATH) ? readServers()[built.name] as ApprovedServer | undefined : undefined;
    if (!held) return undefined;
    const normalized = parseServer(built.name, held);
    if (held.inboxApproval?.id === row.id && held.inboxApproval.reviewDigest === row.reviewDigest &&
        'upstream' in normalized && isDeepStrictEqual(normalized.upstream, wanted.upstream)) {
      return markAccepted(inbox, row.id, built.name, { reconciled: true });
    }
    return reply(409, 'alreadyDeclared', `a server named "${built.name}" already exists; this row did not declare its current configuration`);
  });
  if (reconciled) return reconciled;

  const declared = await declareServer(deps, built.name, built.server, {
    force: false,
    inboxApproval: { id: row.id, reviewDigest: row.reviewDigest },
    // A decline can land while the server indexes. The row must still be waiting when the server is written.
    beforeWrite: () =>
      inbox.find(row.id)?.state !== 'waiting'
        ? { status: 409, reason: 'notWaiting', error: `${row.id} is no longer waiting` }
        : inbox.find(row.id)?.reviewDigest !== row.reviewDigest
          ? { status: 409, reason: 'reviewChanged', error: `${row.id} changed while the server was indexing` }
          : undefined,
  });
  if ('reason' in declared) return reply(declared.status, declared.reason, declared.error);
  return markAccepted(inbox, row.id, built.name, {
    reconciled: false,
    tools: declared.tools,
    needsAuth: declared.needsAuth,
  });
}

/** Mark a row accepted once its server is declared. A failed write here is reported, since the declaration stands. */
function markAccepted(inbox: InboxStore, id: string, server: string, extra: Record<string, unknown>): Answered {
  try {
    inbox.setState(id, 'accepted');
  } catch (err) {
    log.error(`inbox: "${server}" is declared, but ${id} could not be marked accepted: ${(err as Error).message}`);
    return reply(
      500,
      'rowNotMarked',
      `"${server}" is declared, but the row could not be marked accepted. ` +
        'It still reads waiting, and the next accept reconciles it'
    );
  }
  return { status: 200, body: { id, state: 'accepted', server, ...extra } };
}

const REGISTRY_BASE = process.env.MCP_ROUTER_REGISTRY ?? 'https://registry.modelcontextprotocol.io';

/**
 * The facts strip, built only from what this router actually observed.
 *
 * `DESIGN.md` §6 forbids displaying a figure the router does not observe, and `spec-M30.md` §2.1
 * answers the mock's five cells one at a time: `Kind` survives, and `Version`, `Licence`,
 * `Runs in` and `Reads` are all derivations this router cannot make honestly — there is no version
 * on any wire type for an installed upstream, identifying a licence from a file's text is
 * inference, nothing observes which harnesses could run a capability, and nothing observes what a
 * child process reads.
 *
 * The two below `Kind` are here because they are observed, not because the mock drew them: the
 * tool count is the length of the list this router connected and read, and the project list is the
 * visibility restriction this router itself applies. Each is omitted when it was not observed, so
 * the strip's width is a function of what is known rather than of how many labels exist.
 */
function documentFacts(
  u: UpstreamConfig,
  entry: { tools: Array<{ name: string }>; error?: string } | undefined
): Array<{ label: string; value: string }> {
  const facts: Array<{ label: string; value: string }> = [{ label: 'Kind', value: u.transport }];
  if (entry && !entry.error) {
    facts.push({ label: 'Tools', value: String(entry.tools.length) });
  }
  if (u.projects?.length) {
    facts.push({ label: 'Served to', value: u.projects.join(', ') });
  }
  return facts;
}

/**
 * The row cap `/registry/search` applies to a `limit` query value.
 *
 * Extracted from the handler and exported because `scripts/parity/generate-vectors.mjs` builds the
 * `registry-limit` vector from it. It used to be an inline expression there and a transcription of
 * that expression in the generator, which is the shape P9 measured going wrong on `auth-pages`: a
 * vector generated from a copy cannot notice the original change, so raising the cap to 100 would
 * have left the vector asserting 60 and `make parity-regen` green.
 *
 * The coercion ladder is deliberate and load-bearing, so it is preserved exactly: `||` is
 * ToBoolean, so both `0` and `NaN` collapse to 30; `min` caps at 60; and a negative survives all
 * of it and reaches `slice`, where it counts back from the end and drops rows instead of taking
 * them.
 */
export function registrySearchLimit(raw: string | null): number {
  return Math.min(Number(raw ?? 30) || 30, 60);
}

/**
 * The row cap `/usage` applies to a `limit` query value.
 *
 * Exported for the same reason as `registrySearchLimit` above, and closing the same hole: the
 * `usage-limit` vector in `scripts/parity/generate-vectors.mjs` used to re-type this expression
 * under a comment claiming it was "exactly" the one here, and a vector that re-types its reference
 * cannot see that reference drift. Mutating the default from 200 to 3 in `dist/control.js` left
 * `make parity-regen` at exit 0.
 *
 * No ladder here, unlike the registry cap: a bare `Number` with a default. That is the point --
 * `''` and `' '` become 0 rather than 200, `'abc'` becomes NaN, and both reach `recent`, so the
 * default applies only to an absent parameter and never to an unparseable one.
 */
export function usageRecentLimit(raw: string | null): number {
  return Number(raw ?? 200);
}

/** True when this path belongs to the control API rather than to /mcp. */
export function isControlPath(pathname: string): boolean {
  return (
    pathname === '/servers' ||
    pathname.startsWith('/servers/') ||
    pathname === '/export' ||
    pathname === '/usage' ||
    pathname.startsWith('/usage/') ||
    pathname === '/sessions' ||
    pathname.startsWith('/sessions/') ||
    pathname === '/harnesses' ||
    pathname === '/insights' ||
    pathname === '/insights/analyse' ||
    pathname === '/insights/analyst' ||
    pathname.startsWith('/registry/') ||
    pathname.startsWith('/pairing/') ||
    pathname === '/inbox' ||
    pathname.startsWith('/inbox/') ||
    pathname === '/skills' ||
    isExtensionsPath(pathname)
  );
}

/**
 * Handle one control-API request. Returns false when the path is not ours, so the
 * caller can fall through to the MCP endpoint.
 */
export async function handleControl(
  req: IncomingMessage,
  res: ServerResponse,
  url: URL,
  body: unknown,
  deps: ControlDeps,
  token: string
): Promise<boolean> {
  const p = url.pathname;
  const mutating = req.method === 'POST' || req.method === 'DELETE' || req.method === 'PATCH';
  if (!isControlPath(p)) return false;

  // GET /skills names every skill on this machine and the plugin each came from, so it is gated on every method, as the
  // extension family is. It is read-only: nothing it answers writes under Claude's home.
  if (p === '/skills') {
    if (!tokenOk(req, token)) {
      json(res, 401, { error: `unauthorized; the token is in ${TOKEN_PATH}` });
      return true;
    }
    if (req.method !== 'GET') {
      json(res, 405, { error: `${req.method} not allowed on ${p}` });
      return true;
    }
    if (!deps.claudeHome || !deps.extensions) {
      json(res, 503, { error: 'skills are unavailable: this router has no Claude home or extension store' });
      return true;
    }
    json(res, 200, skillsValue(deps.claudeHome, deps.extensions));
    return true;
  }

  // The extension family is gated on every method, GET included. Its listings name what the router holds and
  // where, so a page on this machine must not read them. The existing GETs on this API stay open (decision 3).
  if (isExtensionsPath(p)) {
    if (!tokenOk(req, token)) {
      json(res, 401, { error: `unauthorized; the token is in ${TOKEN_PATH}` });
      return true;
    }
    const ct = String(req.headers['content-type'] ?? '');
    const writes = req.method === 'POST' || req.method === 'PATCH';
    if (writes && !ct.startsWith('application/json')) {
      json(res, 415, { error: 'expected content-type: application/json' });
      return true;
    }
    const answer = extensionRoute(req.method ?? '', p, body, deps, url.searchParams);
    if (answer) json(res, answer.status, answer.body);
    else json(res, 405, { error: `${req.method} not allowed on ${p}` });
    return true;
  }

  // The inbox is gated on every method, GET included: what it names is the list a reviewer decides from, and a
  // page on this machine must not read it. The writes are JSON, as the other mutating routes are, so a cross-origin
  // page cannot send one without a preflight. Only the three decisions are served here; a phone's submit is IB4.
  if (p === '/inbox' || p.startsWith('/inbox/')) {
    if (!tokenOk(req, token)) {
      json(res, 401, { error: `unauthorized; the token is in ${TOKEN_PATH}` });
      return true;
    }
    if (!deps.inbox) {
      json(res, 503, { error: 'the inbox is unavailable: this router has no inbox store' });
      return true;
    }
    if (p === '/inbox' && req.method === 'GET') {
      try {
        json(res, 200, {
          items: deps.inbox.view(),
          pairedDeviceNames: deps.routerHome ? readPairedPhones(deps.routerHome).map((phone) => phone.phoneName) : [],
        });
      } catch (err) {
        // An unreadable store is not an empty inbox: an empty answer would read as "nothing waiting".
        log.error(`inbox: could not read ${deps.inbox.path}: ${(err as Error).message}`);
        json(res, 500, { error: 'the inbox could not be read; see the router log' });
      }
      return true;
    }
    const action = /^\/inbox\/([^/]+)\/(accept|decline|restore)$/.exec(p);
    if (action && req.method === 'POST') {
      const ct = String(req.headers['content-type'] ?? '');
      if (!ct.startsWith('application/json')) {
        json(res, 415, { error: 'expected content-type: application/json' });
        return true;
      }
      let id: string;
      try {
        id = decodeURIComponent(action[1]);
      } catch {
        json(res, 400, { error: 'the row id is not valid percent-encoding', reason: 'badRequest' });
        return true;
      }
      try {
        const answered = await inboxAction(deps, deps.inbox, id, action[2] as InboxVerb, body);
        json(res, answered.status, answered.body);
      } catch (err) {
        log.error(`inbox: ${action[2]} of "${id}" failed: ${(err as Error).message}`);
        json(res, 500, { error: 'the inbox could not be read or written; see the router log', reason: 'storeIo' });
      }
      return true;
    }
    json(res, 405, { error: `${req.method} not allowed on ${p}` });
    return true;
  }

  // The pairing routes are gated on every method, GET included: `/pairing/state` names the code a
  // phone would type, and a page that could read it could pair itself.
  if (mutating || p.startsWith('/pairing/')) {
    if (!tokenOk(req, token)) {
      json(res, 401, { error: `unauthorized; the token is in ${TOKEN_PATH}` });
      return true;
    }
  }
  if (mutating) {
    // Cross-origin JSON forces a preflight, which is never answered.
    const ct = String(req.headers['content-type'] ?? '');
    if (req.method !== 'DELETE' && !ct.startsWith('application/json')) {
      json(res, 415, { error: 'expected content-type: application/json' });
      return true;
    }
  }

  // ---------------------------------------------------------------- export
  /*
   * The server list with every secret value replaced. Gated like the mutating routes rather than
   * like GET /servers: the shape is the same, but a value that escaped redaction here would be
   * readable by anything with a loopback socket, and the token is what stops that.
   */
  if (p === '/export' && req.method === 'GET') {
    if (!tokenOk(req, token)) {
      json(res, 401, { error: `unauthorized; the token is in ${TOKEN_PATH}` });
      return true;
    }
    try {
      json(res, 200, buildExport(readServers(), token, parseOnly(url.searchParams.get('only'))));
    } catch (err) {
      json(res, 400, { error: (err as Error).message });
    }
    return true;
  }

  // ---------------------------------------------------------------- servers
  if (p === '/servers' && req.method === 'GET') {
    const needles = collectNeedles(deps.upstreams.values(), token);
    json(res, 200, {
      port: deps.cfg.port,
      idleMs: deps.cfg.idleMs,
      since: deps.usage.summary().since,
      pendingAuth: currentFlow(),
      servers: [...deps.upstreams.values()].map((u) => describe(u, deps, needles)),
    });
    return true;
  }

  if (p === '/servers' && req.method === 'POST') {
    const b = (body ?? {}) as { name?: string } & RawServer;
    if (!b.name) {
      json(res, 400, { error: 'name is required' });
      return true;
    }
    const declared = await declareServer(deps, b.name, b, { force: url.searchParams.get('force') === '1' });
    if ('reason' in declared) {
      // The retry hint is for this route only: an inbox accept has no force to offer.
      const hint = declared.reason === 'indexFailed' ? { hint: 'retry with ?force=1 to add it anyway' } : {};
      json(res, declared.status, { error: declared.error, ...hint });
      return true;
    }
    json(res, 201, { added: b.name, tools: declared.tools, error: declared.error, needsAuth: declared.needsAuth });
    return true;
  }

  const serverMatch = /^\/servers\/([^/]+)(\/[a-z]+)?$/.exec(p);
  if (serverMatch) {
    const name = decodeURIComponent(serverMatch[1]);
    const sub = serverMatch[2];
    const u = deps.upstreams.get(name);
    if (!u) {
      json(res, 404, { error: `no server named "${name}"` });
      return true;
    }

    if (!sub && req.method === 'GET') {
      json(res, 200, describe(u, deps, collectNeedles(deps.upstreams.values(), token)));
      return true;
    }

    if (!sub && req.method === 'DELETE') {
      editConfigFile((servers) => {
        delete servers[name];
      });
      reload(deps);
      announceTools(deps, `removed the server "${name}"`);
      clearAuth(name);
      if (url.searchParams.get('keepHistory') !== '1') deps.usage.forget(name);
      log.info(`removed upstream "${name}"`);
      json(res, 200, { removed: name });
      return true;
    }

    if (sub === '/reindex' && req.method === 'POST') {
      const { tools, error } = await indexOne(u, deps.cfg, deps.pool);
      // Only on success: a re-index that failed left the manifest where it was, and a
      // notification would send every session to re-fetch a list that did not move.
      if (!error) announceTools(deps, `re-indexed the server "${name}"`);
      json(res, error ? 422 : 200, { name, tools, error });
      return true;
    }

    /*
     * The quarantine surface. `/changes` reports what a server started advertising
     * that differs from what was approved; `/approve` promotes it. Until then the
     * approved bytes keep going out, so a server cannot rewrite what a model reads
     * by changing its own descriptions.
     */
    if (sub === '/changes' && req.method === 'GET') {
      const entry = deps.manifest.current().servers[name];
      json(res, 200, {
        server: name,
        pending: !!entry?.pending,
        seenAt: entry?.pending?.seenAt,
        pendingDigest: entry?.pending ? toolApprovalDigest(u, entry) : undefined,
        changes: entry?.pending ? diffTools(entry.tools, entry.pending.tools) : [],
      });
      return true;
    }

    if (sub === '/approve' && req.method === 'POST') {
      const expectedDigest = (body as { expectedDigest?: unknown } | undefined)?.expectedDigest;
      if (typeof expectedDigest !== 'string' || !/^[a-f0-9]{64}$/.test(expectedDigest)) {
        json(res, 428, { error: 'review the pending change and send its expectedDigest before approving' });
        return true;
      }
      /*
       * R19 — the read is inside the lock, so a re-index landing between it and the write is not
       * clobbered. That matters most here: this route promotes a surface the user has just looked
       * at, and the alternative to the lock is that the promotion is silently undone by whatever
       * re-indexed the same server a moment later.
       *
       * A lock that could not be taken is a 500 carrying the lock's own sentence, which says what
       * happened and that nothing was changed. It is not a 409: 409 asserts there was no pending
       * change, and a run that never read the manifest does not know that.
       */
      let outcome: { status: number; body: unknown };
      try {
        outcome = withExclusiveLock(deps.cfg.manifestPath, lockTimeoutMs(DAEMON_TIMEOUT_MS), () => {
          const manifest = loadManifest(deps.cfg.manifestPath);
          const entry = manifest.servers[name];
          if (!entry?.pending) {
            return { status: 409, body: { error: `no pending change for "${name}"` } };
          }
          const pendingDigest = toolsDigest(entry.pending.tools);
          if (toolApprovalDigest(u, entry) !== expectedDigest) {
            return { status: 409, body: { error: 'the pending tools changed after review; review them again' } };
          }
          const approved = entry.pending.tools.length;
          manifest.servers[name] = {
            ...entry,
            tools: entry.pending.tools,
            digest: pendingDigest,
            builtAt: new Date().toISOString(),
            pending: undefined,
          };
          saveManifest(deps.cfg.manifestPath, manifest);
          return { status: 200, body: { server: name, approved } };
        });
      } catch (err) {
        json(res, 500, { error: (err as Error).message });
        return true;
      }
      if (outcome.status === 200) {
        log.info(
          `approved "${name}"'s new tool surface (${(outcome.body as { approved: number }).approved} tools)`
        );
        /*
         * M38. Promotion moves `entry.tools`, which is the member `unionTools` reads — so this is a
         * mutation that changes what `tools/list` answers, and `announceTools` above says those are
         * announced "and from nowhere else". This was the one that was not.
         *
         * The three-second manifest poller in `router.ts` did reach an attached session eventually,
         * which is why the absence read as working. It arrived late, and it arrived carrying `the
         * tool manifest was rebuilt outside this process` — false about a route this process had
         * just answered, and the sentence somebody reads when they ask why a model's tools changed
         * mid-session. Measured by `scripts/e2e-live-reload.mjs`: 11ms here against the poller's
         * next tick. Announcing here also records the post-write stamp, so the poller does not
         * announce the same move a second time.
         *
         * Only on the 200. A 409 promoted nothing and a 500 wrote nothing; announcing either would
         * send every attached session to re-fetch a list that did not move, and the lane carries
         * that as its own control.
         */
        announceTools(deps, `approved "${name}"'s new tool surface`);
      }
      json(res, outcome.status, outcome.body);
      return true;
    }

    /*
     * The capability document. M30's route, and the first one that reads a package's own files.
     *
     * The root is explicitly declared as `packageRoot`, falling back to the process `cwd`.
     * Neither executable arguments nor package caches grant access to documentation.
     * A separate root leaves child startup and env-file discovery unchanged.
     *
     * The response carries bytes and never a path, so nothing the app receives can be opened.
     * Every refusal names its own `reason`, and the size refusal names which of the three
     * transport caps it hit — `MarkdownLimits` caps the parse, in the app, after the bytes have
     * already crossed, so it cannot be the transport's bound.
     */
    if (sub === '/document' && req.method === 'GET') {
      const packageRoot = isStdio(u) ? u.packageRoot ?? u.cwd : undefined;
      if (!packageRoot) {
        json(res, 404, {
          error: 'this server declares no packageRoot or working directory for documentation',
          reason: 'noPackageDirectory',
          server: name,
        });
        return true;
      }
      const outcome = readPackageDocuments(packageRoot);
      if (isRefusal(outcome)) {
        const { status, ...body } = outcome;
        json(res, status, { ...body, server: name });
        return true;
      }
      json(res, 200, {
        server: name,
        facts: documentFacts(u, deps.manifest.current().servers[name]),
        // An object with at most the three fixed keys, in tab order. A key that is absent means
        // the package published no such file, which is a different thing from an empty one — and
        // the panel says which document is missing rather than drawing a blank pane.
        documents: Object.fromEntries(outcome.documents.map((d) => [d.tab, d.text])),
        images: outcome.images,
        refusedImages: outcome.refusedImages,
      });
      return true;
    }

    /*
     * Editing the operational fields only: which projects a server is served to,
     * whether it stays warm, and whether it is placarded. Command, args and env are
     * deliberately not writable here — a control API that can rewrite a command line
     * is a control API that can run anything, and installing already covers the case
     * where that is what you mean.
     */
    if (!sub && req.method === 'PATCH') {
      const b = (body ?? {}) as {
        projects?: string[];
        warm?: boolean;
        placard?: unknown;
        idleMs?: number;
        disabled?: boolean;
      };
      editConfigFile((servers) => {
        const s = servers[name];
        if (!s) return;
        if ('projects' in b) s.projects = b.projects?.length ? b.projects : undefined;
        if ('warm' in b) s.warm = b.warm || undefined;
        if ('idleMs' in b) s.idleMs = b.idleMs;
        if ('placard' in b) s.placard = b.placard as RawServer['placard'];
        /*
         * LAST, and the position is load-bearing twice over. This object's key order is the
         * order members are appended to the user's `servers.json`, and the Swift port is
         * diffed against this one byte for byte; and the 400 body for a non-object PATCH
         * names whichever key is tested first — "Cannot use 'in' operator to search for
         * 'projects' in …" — so moving `disabled` above it would change a message that has
         * nothing to do with this feature.
         *
         * Shaped like `warm` rather than like `idleMs`: falsy removes the member instead of
         * writing `false`, so turning a server back on leaves the config as it found it.
         */
        if ('disabled' in b) s.disabled = b.disabled || undefined;
      });
      reload(deps);
      /*
       * `disabled` and `projects` are the two fields that change what a session is served —
       * `visibleTo` reads both. `warm`, `idleMs` and `placard` change how a server is run or
       * drawn and leave the tool list exactly as it was, so they announce nothing: a re-fetch
       * every attached session pays for is not free just because it is fast.
       */
      if ('disabled' in b || 'projects' in b) {
        announceTools(deps, `changed what "${name}" serves`);
      }
      if (b.warm) void deps.pool.warmUp();
      json(res, 200, describe(deps.upstreams.get(name)!, deps, collectNeedles(deps.upstreams.values(), token)));
      return true;
    }

    if (sub === '/auth' && req.method === 'POST') {
      if (isStdio(u)) {
        json(res, 400, { error: 'stdio servers do not authorize; their credentials are env vars' });
        return true;
      }
      try {
        const flow = await beginAuth(name, authTransportFor(u));
        // The app opens this. Completing it re-indexes so the tools appear without
        // the user having to know that indexing is a thing that exists.
        void flow.completed
          .then(async () => {
            deps.pool.clearPending(name);
            await indexOne(u, deps.cfg, deps.pool);
          })
          .catch((err: Error) => log.warn(`authorization for "${name}" did not complete: ${err.message}`));
        json(res, 200, { server: name, authorizationUrl: flow.url });
      } catch (err) {
        json(res, 502, { error: (err as Error).message });
      }
      return true;
    }

    if (sub === '/auth' && req.method === 'DELETE') {
      const had = clearAuth(name);
      deps.pool.clearPending(name);
      json(res, 200, { server: name, signedOut: had });
      return true;
    }
  }

  // ---------------------------------------------------------------- usage
  if (p === '/usage' && req.method === 'GET') {
    json(res, 200, {
      since: deps.usage.summary().since,
      records: deps.usage.recent({
        limit: usageRecentLimit(url.searchParams.get('limit')),
        server: url.searchParams.get('server') ?? undefined,
        cwd: url.searchParams.get('cwd') ?? undefined,
      }),
    });
    return true;
  }

  if (p === '/usage/summary' && req.method === 'GET') {
    const s = deps.usage.summary();
    json(res, 200, {
      since: s.since,
      servers: [...deps.upstreams.keys()].map((name) => ({
        name,
        ...(s.servers[name] ?? { calls: 0, errors: 0, projects: {} }),
        projectNames: Object.keys(s.servers[name]?.projects ?? {}).map((d) => ({
          cwd: d,
          project: projectOf(d),
          calls: s.servers[name]!.projects[d],
        })),
      })),
    });
    return true;
  }

  if (p === '/usage/reset' && req.method === 'POST') {
    deps.usage.reset();
    json(res, 200, { ok: true, since: deps.usage.summary().since });
    return true;
  }

  if (p === '/usage/stream' && req.method === 'GET') {
    res.writeHead(200, {
      'content-type': 'text/event-stream',
      'cache-control': 'no-store',
      connection: 'keep-alive',
    });
    res.write(`: connected\n\n`);
    const unsubscribe = deps.usage.subscribe((r) => {
      res.write(`data: ${JSON.stringify(r)}\n\n`);
    });
    // A proxy or a sleeping Mac will drop a silent stream; a comment every 25s is
    // cheap and keeps the app from having to distinguish idle from disconnected.
    const beat = setInterval(() => res.write(`: ping\n\n`), 25_000);
    beat.unref();
    req.on('close', () => {
      clearInterval(beat);
      unsubscribe();
    });
    return true;
  }

  // ---------------------------------------------------------------- sessions
  /*
   * Who a reload can reach, and by which of the two mechanisms.
   *
   * The token is never in this response and never in a log line. The reach classes are the
   * answer to the brief's requirement that a session which cannot be reloaded says so rather
   * than appearing to have been: `exited`, `recycled` and `noSocket` are each a distinct reason,
   * and none of them is an error.
   */
  if (p === '/sessions' && req.method === 'GET') {
    const sessions = listSessions();
    const byReach = sessions.reduce<Record<string, number>>((acc, s) => {
      acc[s.reach] = (acc[s.reach] ?? 0) + 1;
      return acc;
    }, {});
    json(res, 200, {
      // The MCP half. `attachedStreams` is what a tool-list notification would reach right now,
      // and it is a different population from the registry below: a session attached to this
      // router has a stream; a session on this machine may have neither, either or both.
      attachedStreams: deps.liveReload.openStreams,
      notifySessions: notifySessionsEnabled(),
      registry: { total: sessions.length, byReach },
      sessions: sessions.map(({ token: _token, ...rest }) => rest),
    });
    return true;
  }

  /*
   * Fire both mechanisms by hand. `?dryRun=1` reports who the socket ask would reach and sends
   * nothing — the only honest way to look at this before turning `notifySessions` on, because
   * everything it would reach belongs to somebody else's turn.
   */
  if (p === '/sessions/notify' && req.method === 'POST') {
    const b = (body ?? {}) as { reason?: string };
    const reason = typeof b.reason === 'string' && b.reason.trim() ? b.reason.trim() : 'a manual reload request';
    const dryRun = url.searchParams.get('dryRun') === '1';
    const tools = dryRun
      ? { streams: deps.liveReload.openStreams, delivered: 0, failed: 0, reason: 'dry run: nothing sent' }
      : await deps.liveReload.announceToolsChanged(reason);
    const sessions = await askSessionsToReload(reason, { dryRun });
    json(res, 200, { reason, dryRun, tools, sessions });
    return true;
  }

  // ---------------------------------------------------------------- harnesses
  /*
   * Read-only, and gated. Unlike the GETs above, which answer without the token (decision 3 of the
   * retirement plan leaves them for their own item), this one carries session-adjacent data: which
   * servers each agent client has declared and where its config lives. So it checks the token here,
   * on this route alone.
   */
  if (p === '/harnesses' && req.method === 'GET') {
    if (!tokenOk(req, token)) {
      json(res, 401, { error: `unauthorized; the token is in ${TOKEN_PATH}` });
      return true;
    }
    if (!deps.harnesses) {
      json(res, 503, { error: 'harness detection is unavailable: this router has no inventory source' });
      return true;
    }
    const reports = deps.harnesses.reports([...deps.upstreams.values()], deps.cfg.port);
    json(res, 200, harnessEnvelope(reports, deps.cfg.port, Date.now()));
    return true;
  }

  // ---------------------------------------------------------------- insights
  /*
   * Read-only, and gated, for the reason /harnesses is. The call log names the process behind every call, and the
   * hourly counts and duty cycle describe what this machine has been doing. The analyst member is the session
   * analyst's own readout, and it is gated for the same reason: it names the session stores the router read.
   */
  if (p === '/insights' && req.method === 'GET') {
    if (!tokenOk(req, token)) {
      json(res, 401, { error: `unauthorized; the token is in ${TOKEN_PATH}` });
      return true;
    }
    const windowHours = insightsWindowHours(url.searchParams.get('window'));
    if (windowHours === undefined) {
      json(res, 400, { error: `window must be one of ${Object.keys(INSIGHTS_WINDOWS).join(', ')}` });
      return true;
    }
    const now = Date.now();
    json(res, 200, insightsEnvelope({
      now,
      usage: await deps.usage.insights(now, windowHours),
      retention: deps.usage.retention(),
      children: {
        alive: deps.pool.status().filter((s) => s.state === 'running').length,
        declared: deps.upstreams.size,
      },
      resident: await deps.pool.residentReadings(),
      duty: deps.pool.dutyCycle(now),
      reports: deps.harnesses?.reports([...deps.upstreams.values()], deps.cfg.port),
      analyst: deps.analyst ? analystEnvelope(deps.analyst.lastRun(), deps.analyst.settings()) : null,
    }));
    return true;
  }

  // Both writes are gated by the mutating block above, which checks the token and the JSON content type first.
  if (p === '/insights/analyse' && req.method === 'POST') {
    if (!deps.analyst) {
      json(res, 503, { error: ANALYST_UNAVAILABLE });
      return true;
    }
    const outcome = await deps.analyst.analyse();
    if (outcome.kind === 'alreadyRunning') {
      json(res, 409, { error: 'an analysis is already running' });
    } else if (outcome.kind === 'ladderExhausted') {
      // 502 rather than 500: every rung is another program, so what failed is the machine's own CLIs, not this router.
      // The refusals say which model was unreachable rather than reporting "the analyst failed".
      json(res, 502, { error: `no analyst model answered — ${outcome.refusals.join('; ')}` });
    } else {
      json(res, 200, analystEnvelope(outcome.run, deps.analyst.settings()));
    }
    return true;
  }

  if (p === '/insights/analyst' && req.method === 'PATCH') {
    if (!deps.analyst) {
      json(res, 503, { error: ANALYST_UNAVAILABLE });
      return true;
    }
    try {
      const settings = deps.analyst.update(body);
      json(res, 200, analystEnvelope(deps.analyst.lastRun(), settings));
    } catch (err) {
      if (!(err instanceof AnalystSettingsRefusal)) throw err;
      json(res, 422, { error: err.message, member: err.member });
    }
    return true;
  }

  // ---------------------------------------------------------------- registry
  if (p === '/registry/search' && req.method === 'GET') {
    try {
      const out = await searchRegistries(
        url.searchParams.get('q') ?? '',
        registrySearchLimit(url.searchParams.get('limit'))
      );
      // Which servers are already installed, so the app can render "Installed"
      // instead of an install button it would have to disable a moment later.
      const installed = new Set([...deps.upstreams.keys()]);
      json(res, 200, {
        ...out,
        results: out.results.map((r) => ({ ...r, installed: installed.has(r.displayName) })),
      });
    } catch (err) {
      json(res, 502, { error: (err as Error).message });
    }
    return true;
  }

  // ---------------------------------------------------------------- pairing
  /*
   * The Mac's side of the phone handshake. Only this route mints a code, and nothing here spends one:
   * a code is spent when the listener decides a phone's request (`pairing.submit`), which the
   * listener owns. Revoking never forgets a code that was already paired.
   */
  // Refused while no listener is bound. A code minted then would name a port nothing answers on, and a
  // phone handed it would fail with no clue why. The refusal mints nothing, so nothing is left to revoke.
  if (p === '/pairing/codes' && req.method === 'POST') {
    if (!deps.pairingListener().enabled) {
      json(res, 503, {
        error: 'pairing is turned off on this router: set pairing.enabled in the server list and restart the router',
        reason: 'pairingDisabled',
      });
      return true;
    }
    json(res, 201, codeBody(deps.pairing.issue()));
    return true;
  }

  if (p === '/pairing/codes' && req.method === 'DELETE') {
    json(res, 200, { revoked: deps.pairing.revoke() });
    return true;
  }

  // Revokes a confirmed phone by removing its record, which holds the phone's public key, so a later submit from
  // that phone has no key to verify against. Only a confirmed phone is named: a pending one is not in the file,
  // and its held request belongs to the listener, so it answers 404 here.
  const pairedPhone = /^\/pairing\/phones\/([^/]+)$/.exec(p);
  if (pairedPhone && req.method === 'DELETE') {
    const removed = removePairedPhone(deps.routerHome, pairedPhone[1]);
    if (removed) json(res, 200, { revoked: removed.phoneId });
    else json(res, 404, { error: 'no confirmed phone has that id' });
    return true;
  }

  // Names the code only while it can still be paired with. An expired code is not pending, so it is
  // not named here, even though `submit` still answers it as expired.
  //
  // `awaitingAck` lists the phones whose request was accepted and whose `pair.ack` has not come yet. It
  // names the phone and the time, never a key or an id, and it empties the moment the phone acks or drops.
  //
  // `listener` says whether the phone listener is bound, so a sheet can say pairing is off instead of
  // offering a code. The endpoint and certificate fingerprint let the Mac build the QR from observed identity.
  if (p === '/pairing/state' && req.method === 'GET') {
    const live = deps.pairing.current();
    const listener = deps.pairingListener();
    json(res, 200, {
      code: live ? codeBody(live) : null,
      awaitingAck: deps.pairing.awaitingAck().map((a) => ({
        phoneName: a.phoneName,
        requestedAt: wireInstant(a.requestedAt),
      })),
      listener: {
        enabled: listener.enabled, port: listener.port, advertising: listener.advertising,
        host: listener.enabled ? listener.host ?? null : null,
        fingerprint: listener.enabled ? listener.fingerprint ?? null : null,
      },
    });
    return true;
  }

  json(res, 405, { error: `${req.method} not allowed on ${p}` });
  return true;
}
