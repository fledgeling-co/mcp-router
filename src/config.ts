import { readFileSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';

export interface UpstreamConfig {
  /** Logical name; becomes the namespace prefix on every tool it exposes. */
  name: string;
  command: string;
  args: string[];
  env: Record<string, string>;
  cwd?: string;
  /** Milliseconds a spawned child may sit unused before it is reaped. */
  idleMs?: number;
  /** Milliseconds to wait for the child to complete MCP initialize. */
  startupTimeoutMs?: number;
}

export interface RouterConfig {
  port: number;
  host: string;
  idleMs: number;
  startupTimeoutMs: number;
  upstreams: UpstreamConfig[];
  manifestPath: string;
  logPath: string;
}

export const ROUTER_HOME = join(homedir(), '.claude', 'mcp-router');
export const DEFAULT_CONFIG_PATH = join(ROUTER_HOME, 'servers.json');

/**
 * Config-identity hash. A changed command, args, cwd or env — keys *or values* —
 * invalidates that server's cached manifest.
 *
 * Values are in the hashed material, not just the key names. A server whose tool
 * surface depends on an env value (a mode flag, or a key that gates which tools
 * it advertises) would otherwise keep serving the tool list it had under the old
 * value, and `index` would report nothing needed doing. The digest is one-way and
 * truncated, so no secret is recoverable from what lands in manifest.json.
 */
export function upstreamHash(u: UpstreamConfig): string {
  const env = Object.entries(u.env)
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  const material = JSON.stringify([u.command, u.args, u.cwd ?? null, env]);
  return createHash('sha256').update(material).digest('hex').slice(0, 16);
}

interface RawServer {
  type?: string;
  command?: string;
  args?: string[];
  env?: Record<string, string>;
  cwd?: string;
  url?: string;
  idleMs?: number;
}

/**
 * Reads the router's own server list. Only stdio servers are eligible: an http/sse
 * upstream is already a shared endpoint and forking it through here would add a hop
 * while removing its OAuth context, so those are skipped with a warning rather than
 * proxied.
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

  const servers = raw.mcpServers ?? {};
  const upstreams: UpstreamConfig[] = [];
  const skipped: string[] = [];

  for (const [name, s] of Object.entries(servers)) {
    const type = s.type ?? 'stdio';
    if (type !== 'stdio' || !s.command) {
      skipped.push(`${name} (${type})`);
      continue;
    }
    if (!/^[A-Za-z0-9_-]+$/.test(name)) {
      skipped.push(`${name} (name is not [A-Za-z0-9_-]+, cannot be a tool namespace)`);
      continue;
    }
    /* `__` is the namespace separator, so a server carrying one in its own name
       makes `<server>__<tool>` ambiguous: "foo__bar" exposing "run" publishes
       "foo__bar__run", which splits to server "foo", tool "bar__run". */
    if (name.includes('__')) {
      skipped.push(`${name} (name contains "__", which is the tool namespace separator)`);
      continue;
    }
    upstreams.push({
      name,
      command: s.command,
      args: s.args ?? [],
      env: s.env ?? {},
      cwd: s.cwd,
      idleMs: s.idleMs,
    });
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
    },
    skipped,
  };
}
