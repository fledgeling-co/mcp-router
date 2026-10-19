import { readFileSync, existsSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { resolveEnvFiles, envFilesDigest } from './envfile.js';
import { DEFAULT_LOG_POLICY, type LogPolicy } from './log.js';

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
  /**
   * Declared and not served. The third state, between adopted and removed.
   *
   * Distinct from `placard`, which keeps a server's tools LISTED and answering with a
   * reason: a disabled server contributes nothing to `tools/list` at all, cannot be
   * called by name, is never spawned to be warmed or indexed, and is reaped if it
   * happens to be up. The router still knows everything it knew — the manifest row,
   * the digest and the approved tool surface all survive untouched — so re-enabling
   * costs nothing and, more importantly, cannot launder an approval: a surface the
   * user refused by disabling the server does not come back as a first sight.
   *
   * Absent from `upstreamHash` for the same reason `projects`, `warm` and `placard`
   * are. None of them changes what the upstream advertises, and hashing this one
   * would invalidate the cache on a toggle and re-spawn the process it turned off.
   *
   * Global, not per-project. `projects` is the allow-list that already says "live in
   * this repo and not that one"; this is the switch, and the surfaces that set it —
   * a whole-router table and a "this server changed under me" kill switch — are both
   * global. See planning/specs/spec-M29.md §3.3.
   */
  disabled?: boolean;
}

export interface StdioUpstream extends UpstreamBase {
  transport: 'stdio';
  command: string;
  args: string[];
  env: Record<string, string>;
  cwd?: string;
  /**
   * Env files read at every spawn, merged under `env`. Resolved once at parse time from
   * `envFile` or the package root's `.env` / `.env.local`; see envfile.ts.
   */
  envFiles: string[];
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
  /** Size cap and retained-generation count for `logPath`. Defaults are 10 MB and five. */
  log: LogPolicy;
  /** The phone-pairing listener. Off unless `pairing.enabled` is set; see PairingConfig. */
  pairing: PairingConfig;
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
/**
 * Code-unit ordering: the comparator every digest in this repo sorts with.
 *
 * One definition rather than three inline copies, and exported, because
 * `scripts/parity/generate-vectors.mjs` builds the `string-ordering` vector from it. Both digests
 * below and `manifest.toolsDigest` call it, so a change here moves the vector and reddens
 * `make parity-regen`; a copy in the generator could not see that.
 *
 * The exemption argued in an earlier P9 round -- that a comparator change reddens regen anyway
 * through the reference-driven `upstream-hash` and `tools-digest` vectors -- holds only for the
 * mutation nobody makes. Reversing the comparator at all three sites does redden regen. Swapping
 * it to `localeCompare` did not, and that is the swap someone reaches for: ICU root collation
 * disagrees with code-unit order on `B/a`, `A/a`, `Z/a`, `e-acute/z` and `1/_`, so both digests
 * would change while every vector kept passing.
 *
 * `localeCompare` is the wrong answer for a digest regardless of locale data: it is
 * environment-dependent, and these digests are compared across processes and across ports.
 */
export function compareStrings(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

/**
 * Identity of the executable behind a stdio upstream: its size and mtime.
 *
 * `upstreamHash` covers what the *configuration* says, and its own rule is that a
 * field belongs there when it "changes what the upstream advertises". The bytes on
 * disk change exactly that and were not covered, so replacing a server's binary in
 * place left the cached tool surface stale for ever: the command, args, cwd and env
 * are all identical, so `isStale` answered false and `index --force` skipped it.
 *
 * Measured 2026-09-09. Warden gained a `project` property on two tools and was
 * rebuilt over `/Applications/Warden.app`. A full re-index reported success and kept
 * a schema from two days earlier, so a router change that matched on that property
 * could never fire — and the failure read as the new code not working rather than as
 * a cache that could not see it.
 *
 * Size and mtime rather than a content hash: a server binary can be tens of
 * megabytes and this runs for every upstream on every staleness check, while the
 * thing being detected is a rebuild or a reinstall, both of which move both fields.
 * A rebuild that reproduced byte-identical output at an identical timestamp would be
 * missed, and that is a rebuild with nothing to re-index.
 *
 * The first absolute-path argument is stamped too, because the interesting file for
 * `node /path/to/dist/index.js` is the script rather than the interpreter. A path
 * that cannot be stat-ed contributes nothing instead of throwing: a stamp is a
 * staleness hint, and it must never be the reason a router fails to start.
 */
export function binaryStamp(u: UpstreamConfig): string {
  if (!isStdio(u)) return '';
  const parts: string[] = [];
  const candidates = [u.command, ...(u.args ?? []).filter((a) => a.startsWith('/'))];
  for (const p of candidates) {
    if (!p.startsWith('/')) continue;
    try {
      const st = statSync(p);
      parts.push(`${p}:${st.size}:${Math.trunc(st.mtimeMs)}`);
    } catch {
      // Absent, unreadable, or not a real path. Nothing to say about it.
    }
  }
  if (parts.length === 0) return '';
  return createHash('sha256').update(parts.join('\n')).digest('hex').slice(0, 16);
}

export function upstreamHash(u: UpstreamConfig): string {
  const material = isStdio(u)
    ? JSON.stringify([
        'stdio',
        u.command,
        u.args,
        u.cwd ?? null,
        Object.entries(u.env).sort(([a], [b]) => compareStrings(a, b)),
        ...(u.envFiles.length ? [envFilesDigest(u.envFiles)] : []),
      ])
    : JSON.stringify([
        u.transport,
        u.url,
        Object.entries(u.headers).sort(([a], [b]) => compareStrings(a, b)),
      ]);
  return createHash('sha256').update(material).digest('hex').slice(0, 16);
}

export interface RawServer {
  type?: string;
  command?: string;
  args?: string[];
  env?: Record<string, string>;
  cwd?: string;
  envFile?: string | string[] | false;
  url?: string;
  headers?: Record<string, string>;
  oauth?: boolean;
  idleMs?: number;
  startupTimeoutMs?: number;
  projects?: string[];
  warm?: boolean;
  placard?: { reason: string; substitute?: string; until?: string };
  disabled?: boolean;
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
        envFiles: resolveEnvFiles(s.command, s.args ?? [], s.cwd, s.envFile),
        idleMs: s.idleMs,
        startupTimeoutMs: s.startupTimeoutMs,
        projects: s.projects,
        warm: s.warm,
        placard: s.placard,
        disabled: s.disabled,
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
        disabled: s.disabled,
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

function isCount(v: unknown, min: number): v is number {
  return typeof v === 'number' && Number.isSafeInteger(v) && v >= min;
}

/**
 * The `log` block of the server list, with defaults for whatever it leaves out.
 *
 * Refuses rather than clamps. A `maxBytes` of 0, or the string "10485760", would otherwise be
 * accepted and quietly mean something other than what was written, and the symptom would be a
 * log that never rotates. The message names the file and the field so the fix is one lookup.
 */
export function parseLogPolicy(raw: unknown, source: string): LogPolicy {
  if (raw === undefined) return { ...DEFAULT_LOG_POLICY };
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    throw new Error(`${source}: "log" must be an object, with maxBytes and keep`);
  }
  const { maxBytes = DEFAULT_LOG_POLICY.maxBytes, keep = DEFAULT_LOG_POLICY.keep } = raw as Record<
    string,
    unknown
  >;
  if (!isCount(maxBytes, 1)) {
    throw new Error(`${source}: log.maxBytes must be a positive integer, got ${JSON.stringify(maxBytes)}`);
  }
  if (!isCount(keep, 0)) {
    throw new Error(`${source}: log.keep must be a non-negative integer, got ${JSON.stringify(keep)}`);
  }
  return { maxBytes, keep };
}

/** The port the phone-pairing listener takes when `pairing.port` is left out. 8879 is the router, 8880 the OAuth callback. */
export const DEFAULT_PAIRING_PORT = 8882;

/**
 * The `pairing` block of the server list. Off unless `enabled` is set, so a router that has not been
 * asked to take phones binds no second socket at all.
 *
 * `host` defaults to every interface because a phone reaches the Mac over the LAN. It is not the
 * control API's address, which stays on loopback however this is set.
 */
export interface PairingConfig {
  enabled: boolean;
  host: string;
  port: number;
}

/** The `pairing` block, with defaults for whatever it leaves out. Refuses rather than clamps, as `parseLogPolicy` does. */
export function parsePairingConfig(raw: unknown, source: string): PairingConfig {
  const defaults: PairingConfig = { enabled: false, host: '0.0.0.0', port: DEFAULT_PAIRING_PORT };
  if (raw === undefined) return defaults;
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    throw new Error(`${source}: "pairing" must be an object, with enabled, port and host`);
  }
  const { enabled = defaults.enabled, port = defaults.port, host = defaults.host } = raw as Record<string, unknown>;
  if (typeof enabled !== 'boolean') {
    throw new Error(`${source}: pairing.enabled must be true or false, got ${JSON.stringify(enabled)}`);
  }
  if (!isCount(port, 1) || (port as number) > 65535) {
    throw new Error(`${source}: pairing.port must be a port from 1 to 65535, got ${JSON.stringify(port)}`);
  }
  if (typeof host !== 'string' || host === '') {
    throw new Error(`${source}: pairing.host must be a non-empty string, got ${JSON.stringify(host)}`);
  }
  return { enabled, host, port: port as number };
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
    log?: unknown;
    pairing?: unknown;
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
      log: parseLogPolicy(raw.log, configPath),
      pairing: parsePairingConfig(raw.pairing, configPath),
      usagePath: join(ROUTER_HOME, 'usage.jsonl'),
      statsPath: join(ROUTER_HOME, 'usage-stats.json'),
      authDir: AUTH_DIR,
    },
    skipped,
  };
}
