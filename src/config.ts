import { readFileSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';

interface UpstreamBase {
  /** Logical name; becomes the namespace prefix on every tool it exposes. */
  name: string;
  /** Milliseconds a live upstream may sit unused before it is closed. */
  idleMs?: number;
  /** Milliseconds to wait for the upstream to complete MCP initialize. */
  startupTimeoutMs?: number;
  /**
   * Directory prefixes this server is served to. Absent or empty means everywhere.
   *
   * A global on/off switch cannot say "this server for that repo and not this one",
   * and that is the shape the question actually has when one machine holds work for
   * several clients. The router already resolves the calling process's directory,
   * so scoping is a filter on the tool list rather than a new mechanism.
   */
  projects?: string[];
  /**
   * Kept open from startup and never idle-reaped.
   *
   * Worth paying for on measurement rather than principle: cold start across this
   * machine's real servers runs to a 769ms median and a 3.5s p90, with one at 5.7s.
   */
  warm?: boolean;
  /**
   * Declared inoperative. Its tools stay listed and answer with this instead of
   * running, so an agent reroutes on the first attempt rather than losing a turn.
   */
  placard?: { reason: string; substitute?: string; until?: string };
}

export interface StdioUpstream extends UpstreamBase {
  transport: 'stdio';
  command: string;
  args: string[];
  env: Record<string, string>;
  cwd?: string;
}

export interface HttpUpstream extends UpstreamBase {
  transport: 'http' | 'sse';
  url: string;
  /** Static headers sent on every request — an API key lives here. */
  headers: Record<string, string>;
  /** False disables the OAuth provider for this server, leaving `headers` alone. */
  oauth?: boolean;
}

export type UpstreamConfig = StdioUpstream | HttpUpstream;

export const isStdio = (u: UpstreamConfig): u is StdioUpstream => u.transport === 'stdio';
export const isHttp = (u: UpstreamConfig): u is HttpUpstream => u.transport !== 'stdio';

export interface RouterConfig {
  port: number;
  host: string;
  idleMs: number;
  startupTimeoutMs: number;
  upstreams: UpstreamConfig[];
  manifestPath: string;
  logPath: string;
  usagePath: string;
  statsPath: string;
  authDir: string;
}

/**
 * Where every piece of router state lives: the server list, the manifest, the usage
 * log, the OAuth tokens and the control token.
 *
 * `MCP_ROUTER_HOME` moves all of it together. One home per router instance is the
 * invariant that matters — splitting the token from the config would let a second
 * instance authenticate against the first one's control API.
 */
export const ROUTER_HOME = process.env.MCP_ROUTER_HOME || join(homedir(), '.claude', 'mcp-router');
export const DEFAULT_CONFIG_PATH = join(ROUTER_HOME, 'servers.json');
export const AUTH_DIR = join(ROUTER_HOME, 'auth');

/**
 * Config-identity hash. A changed command, args, cwd or env — keys *or values* —
 * invalidates that server's cached manifest, and for an HTTP upstream a changed
 * url or static header does the same.
 *
 * Values are in the hashed material, not just the key names. A server whose tool
 * surface depends on an env value (a mode flag, or a key that gates which tools
 * it advertises) would otherwise keep serving the tool list it had under the old
 * value, and `index` would report nothing needed doing. The digest is one-way and
 * truncated, so no secret is recoverable from what lands in manifest.json.
 *
 * OAuth tokens are deliberately *not* hashed. They live in the auth store rather
 * than the config, and a routine token refresh must not invalidate a tool list
 * that has not changed.
 */
export function upstreamHash(u: UpstreamConfig): string {
  const material = isStdio(u)
    ? JSON.stringify([
        'stdio',
        u.command,
        u.args,
        u.cwd ?? null,
        Object.entries(u.env).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)),
      ])
    : JSON.stringify([
        u.transport,
        u.url,
        Object.entries(u.headers).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)),
      ]);
  return createHash('sha256').update(material).digest('hex').slice(0, 16);
}

export interface RawServer {
  type?: string;
  command?: string;
  args?: string[];
  env?: Record<string, string>;
  cwd?: string;
  url?: string;
  headers?: Record<string, string>;
  oauth?: boolean;
  idleMs?: number;
  startupTimeoutMs?: number;
  projects?: string[];
  warm?: boolean;
  placard?: { reason: string; substitute?: string; until?: string };
}

/**
 * Turn one entry of a `mcpServers` object into an upstream, or explain why not.
 *
 * Shared by the config loader, `import` and `watch` so that all three agree on
 * what is adoptable. They previously disagreed: `import` took anything with a
 * command and `watch` applied the stricter rules, so a server rejected by one
 * was adopted by the other depending on which ran first.
 */
export function parseServer(name: string, s: RawServer): { upstream: UpstreamConfig } | { reason: string } {
  if (!/^[A-Za-z0-9_-]+$/.test(name)) {
    return { reason: 'name is not [A-Za-z0-9_-]+, so it cannot be a tool namespace' };
  }
  /* `__` is the namespace separator, so a server carrying one in its own name
     makes `<server>__<tool>` ambiguous: "foo__bar" exposing "run" publishes
     "foo__bar__run", which splits to server "foo", tool "bar__run". */
  if (name.includes('__')) {
    return { reason: 'name contains "__", which is the tool namespace separator' };
  }

  const type = s.type ?? (s.url ? 'http' : 'stdio');

  if (type === 'stdio') {
    if (!s.command) return { reason: 'stdio server has no command' };
    return {
      upstream: {
        transport: 'stdio',
        name,
        command: s.command,
        args: s.args ?? [],
        env: s.env ?? {},
        cwd: s.cwd,
        idleMs: s.idleMs,
        startupTimeoutMs: s.startupTimeoutMs,
        projects: s.projects,
        warm: s.warm,
        placard: s.placard,
      },
    };
  }

  if (type === 'http' || type === 'sse' || type === 'streamable-http') {
    if (!s.url) return { reason: `${type} server has no url` };
    try {
      // A malformed url must fail here, not at first call: the router would
      // otherwise index fine and every tool on it would error at use time.
      void new URL(s.url);
    } catch {
      return { reason: `url is not parseable: ${s.url}` };
    }
    return {
      upstream: {
        transport: type === 'sse' ? 'sse' : 'http',
        name,
        url: s.url,
        headers: s.headers ?? {},
        oauth: s.oauth,
        idleMs: s.idleMs,
        startupTimeoutMs: s.startupTimeoutMs,
        projects: s.projects,
        warm: s.warm,
        placard: s.placard,
      },
    };
  }

  return { reason: `unsupported transport "${type}"` };
}

/**
 * True when this entry is the router itself.
 *
 * `~/.claude.json` gains an `mcp-router` HTTP entry at install time, so anything
 * that adopts HTTP servers out of that file will otherwise adopt the router — which
 * then proxies to itself, and every `tools/list` recurses until something gives up.
 * Checked by URL as well as by name, because renaming the entry must not defeat it.
 */
export function isSelfReference(name: string, s: RawServer, port: number): boolean {
  if (name === 'mcp-router' || name === 'router') return true;
  if (!s.url) return false;
  try {
    const u = new URL(s.url);
    const loopback = ['127.0.0.1', 'localhost', '::1', '[::1]'];
    return loopback.includes(u.hostname) && u.port === String(port);
  } catch {
    return false;
  }
}

/**
 * Reads the router's own server list.
 *
 * Both transports are proxied. stdio is the one the router exists for — it is a
 * 1:1 pipe, so every session that declares one pays for its own copy. An HTTP
 * upstream already multiplexes and gains nothing from pooling, but routing it
 * here still buys the two things the app needs: one list of every server the
 * user has, and one place that records what actually got called.
 */
export function loadConfig(opts: {
  configPath?: string;
  port?: number;
  host?: string;
  idleMs?: number;
}): { config: RouterConfig; skipped: string[] } {
  const configPath = opts.configPath ?? DEFAULT_CONFIG_PATH;
  if (!existsSync(configPath)) {
    throw new Error(
      `No server list at ${configPath}. Run \`mcp-router import\` to generate one from ~/.claude.json.`
    );
  }

  const raw = JSON.parse(readFileSync(configPath, 'utf8')) as {
    mcpServers?: Record<string, RawServer>;
    port?: number;
    host?: string;
    idleMs?: number;
    startupTimeoutMs?: number;
  };

  const upstreams: UpstreamConfig[] = [];
  const skipped: string[] = [];

  for (const [name, s] of Object.entries(raw.mcpServers ?? {})) {
    const parsed = parseServer(name, s);
    if ('reason' in parsed) skipped.push(`${name} (${parsed.reason})`);
    else upstreams.push(parsed.upstream);
  }

  return {
    config: {
      port: opts.port ?? raw.port ?? 8879,
      host: opts.host ?? raw.host ?? '127.0.0.1',
      idleMs: opts.idleMs ?? raw.idleMs ?? 300_000,
      startupTimeoutMs: raw.startupTimeoutMs ?? 60_000,
      upstreams,
      manifestPath: join(ROUTER_HOME, 'manifest.json'),
      logPath: join(ROUTER_HOME, 'router.log'),
      usagePath: join(ROUTER_HOME, 'usage.jsonl'),
      statsPath: join(ROUTER_HOME, 'usage-stats.json'),
      authDir: AUTH_DIR,
    },
    skipped,
  };
}
