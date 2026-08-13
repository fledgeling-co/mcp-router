import { readFileSync, writeFileSync, mkdirSync, existsSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import type { OAuthClientProvider } from '@modelcontextprotocol/sdk/client/auth.js';
import type {
  OAuthClientInformationMixed,
  OAuthClientMetadata,
  OAuthTokens,
} from '@modelcontextprotocol/sdk/shared/auth.js';
import { AUTH_DIR } from './config.js';
import { log } from './log.js';

/**
 * The loopback port the OAuth callback lands on.
 *
 * It is fixed rather than ephemeral because dynamic client registration sends
 * `redirect_uris` to the authorization server at registration time. Register on a
 * random port today and the next authorization, on a different random port, is
 * rejected as an unregistered redirect — so the port has to be stable across runs
 * for a saved client registration to keep working.
 */
export const AUTH_CALLBACK_PORT = Number(process.env.MCP_ROUTER_AUTH_PORT ?? 8880);
export const AUTH_REDIRECT_URI = `http://127.0.0.1:${AUTH_CALLBACK_PORT}/callback`;

interface AuthRecord {
  clientInformation?: OAuthClientInformationMixed;
  tokens?: OAuthTokens;
  codeVerifier?: string;
  /** When the last successful authorization completed, for the app to display. */
  authorizedAt?: string;
}

const recordPath = (server: string): string => join(AUTH_DIR, `${server}.json`);

function readRecord(server: string): AuthRecord {
  const p = recordPath(server);
  if (!existsSync(p)) return {};
  try {
    return JSON.parse(readFileSync(p, 'utf8')) as AuthRecord;
  } catch (err) {
    log.warn(`auth record for "${server}" unreadable (${(err as Error).message}); treating as unauthorized`);
    return {};
  }
}

function writeRecord(server: string, rec: AuthRecord): void {
  // 0700/0600: this file holds bearer tokens for the user's accounts. The default
  // umask would leave it world-readable, which is not acceptable for a credential.
  mkdirSync(AUTH_DIR, { recursive: true, mode: 0o700 });
  writeFileSync(recordPath(server), JSON.stringify(rec, null, 2), { mode: 0o600 });
}

export function hasTokens(server: string): boolean {
  return !!readRecord(server).tokens?.access_token;
}

export function authorizedAt(server: string): string | undefined {
  return readRecord(server).authorizedAt;
}

/** Forget one server's tokens and client registration. Used by `logout` and on removal. */
export function clearAuth(server: string): boolean {
  const p = recordPath(server);
  if (!existsSync(p)) return false;
  rmSync(p);
  return true;
}

/**
 * An OAuth client whose whole state is one file per server.
 *
 * Claude Code holds its own tokens for the HTTP servers it talks to directly. Once
 * a server is routed through here the router is the client, so the router needs its
 * own registration and its own tokens — which is why authorizing is a thing the app
 * has to be able to drive, rather than something that quietly keeps working.
 */
export class FileOAuthProvider implements OAuthClientProvider {
  constructor(
    private readonly server: string,
    /** Called with the authorization URL. The CLI opens a browser; `serve` records it. */
    private readonly onRedirect: (url: URL) => void | Promise<void>
  ) {}

  get redirectUrl(): string {
    return AUTH_REDIRECT_URI;
  }

  get clientMetadata(): OAuthClientMetadata {
    return {
      client_name: `mcp-router (${this.server})`,
      client_uri: 'https://mcp-router.fledgeling.app',
      redirect_uris: [AUTH_REDIRECT_URI],
      grant_types: ['authorization_code', 'refresh_token'],
      response_types: ['code'],
      // Public client: the router runs on the user's own machine, so it has
      // nowhere to keep a client secret that the user could not already read.
      token_endpoint_auth_method: 'none',
    };
  }

  clientInformation(): OAuthClientInformationMixed | undefined {
    return readRecord(this.server).clientInformation;
  }

  saveClientInformation(info: OAuthClientInformationMixed): void {
    writeRecord(this.server, { ...readRecord(this.server), clientInformation: info });
  }

  tokens(): OAuthTokens | undefined {
    return readRecord(this.server).tokens;
  }

  saveTokens(tokens: OAuthTokens): void {
    writeRecord(this.server, {
      ...readRecord(this.server),
      tokens,
      authorizedAt: new Date().toISOString(),
    });
  }

  saveCodeVerifier(verifier: string): void {
    writeRecord(this.server, { ...readRecord(this.server), codeVerifier: verifier });
  }

  codeVerifier(): string {
    const v = readRecord(this.server).codeVerifier;
    if (!v) throw new Error(`no PKCE code verifier saved for "${this.server}"`);
    return v;
  }

  async redirectToAuthorization(url: URL): Promise<void> {
    await this.onRedirect(url);
  }
}

/**
 * One in-progress browser authorization.
 *
 * `url` is handed to the app, which opens it — the app is frontmost and owns the
 * user's attention, where this daemon runs under launchd and opening a browser
 * from it would be a window appearing from nowhere. `completed` settles when the
 * loopback callback delivers a code and the token exchange succeeds.
 */
export interface AuthFlow {
  server: string;
  url: string;
  completed: Promise<void>;
  cancel: () => void;
}

let current: { flow: AuthFlow; close: () => void } | undefined;

export function currentFlow(): { server: string; url: string } | undefined {
  return current ? { server: current.flow.server, url: current.flow.url } : undefined;
}

const PAGE = (title: string, detail: string): string =>
  `<!doctype html><meta charset="utf-8"><title>${title}</title>` +
  `<style>body{font:15px/1.6 -apple-system,system-ui,sans-serif;background:#141220;color:#eae8f5;` +
  `display:grid;place-items:center;height:100vh;margin:0;text-align:center}` +
  `h1{font-size:19px;margin:0 0 6px}p{margin:0;color:#a6a2c4}</style>` +
  `<div><h1>${title}</h1><p>${detail}</p></div>`;

/**
 * Run the PKCE authorization-code flow for one HTTP upstream.
 *
 * The callback listener binds a fixed port for the reason given on
 * AUTH_CALLBACK_PORT, which means only one flow can be in flight at a time — so
 * starting a second one cancels the first rather than failing to bind and leaving
 * the user with a browser tab that can never land.
 */
export async function beginAuth(
  serverName: string,
  makeTransport: (provider: FileOAuthProvider) => {
    connect: () => Promise<void>;
    finishAuth: (code: string) => Promise<void>;
    close: () => Promise<void>;
  },
  timeoutMs = 5 * 60_000
): Promise<AuthFlow> {
  current?.close();

  const { createServer } = await import('node:http');

  let onUrl: (u: URL) => void = () => undefined;
  const urlReady = new Promise<URL>((resolve) => {
    onUrl = resolve;
  });

  const provider = new FileOAuthProvider(serverName, (u) => onUrl(u));
  const transport = makeTransport(provider);

  let settle!: (err?: Error) => void;
  const completed = new Promise<void>((resolve, reject) => {
    settle = (err) => (err ? reject(err) : resolve());
  });
  // Nothing else awaits this promise until the caller does, and an authorization
  // the user simply abandons would otherwise surface as an unhandled rejection.
  completed.catch(() => undefined);

  const callback = createServer((req, res) => {
    void (async () => {
      const u = new URL(req.url ?? '/', AUTH_REDIRECT_URI);
      if (u.pathname !== '/callback') {
        res.writeHead(404).end();
        return;
      }
      const code = u.searchParams.get('code');
      const error = u.searchParams.get('error');
      if (error || !code) {
        res.writeHead(400, { 'content-type': 'text/html' });
        res.end(PAGE('Authorization failed', error ?? 'the provider returned no code'));
        settle(new Error(error ?? 'no authorization code returned'));
        cleanup();
        return;
      }
      try {
        await transport.finishAuth(code);
        res.writeHead(200, { 'content-type': 'text/html' });
        res.end(PAGE(`${serverName} is connected`, 'You can close this tab and return to mcp-router.'));
        log.info(`authorized upstream "${serverName}"`);
        settle();
      } catch (err) {
        res.writeHead(500, { 'content-type': 'text/html' });
        res.end(PAGE('Authorization failed', (err as Error).message));
        settle(err as Error);
      } finally {
        cleanup();
      }
    })();
  });

  const timer = setTimeout(() => {
    settle(new Error('authorization timed out'));
    cleanup();
  }, timeoutMs);
  timer.unref();

  function cleanup(): void {
    clearTimeout(timer);
    callback.close();
    void transport.close().catch(() => undefined);
    if (current?.flow.server === serverName) current = undefined;
  }

  await new Promise<void>((resolve, reject) => {
    callback.once('error', reject);
    callback.listen(AUTH_CALLBACK_PORT, '127.0.0.1', () => {
      callback.removeListener('error', reject);
      resolve();
    });
  });

  // Expected to reject: the provider redirects rather than returning tokens, and
  // the SDK surfaces that as UnauthorizedError. The URL is the actual output.
  void transport.connect().catch(() => undefined);

  const url = await Promise.race([
    urlReady,
    new Promise<never>((_, reject) =>
      setTimeout(() => reject(new Error('the server never produced an authorization URL')), 20_000).unref()
    ),
  ]).catch((err: Error) => {
    cleanup();
    throw err;
  });

  const flow: AuthFlow = {
    server: serverName,
    url: url.toString(),
    completed,
    cancel: () => {
      settle(new Error('cancelled'));
      cleanup();
    },
  };
  current = { flow, close: cleanup };
  return flow;
}
