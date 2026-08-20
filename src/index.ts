#!/usr/bin/env node
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { execFile } from 'node:child_process';
import {
  loadConfig,
  parseServer,
  isSelfReference,
  isStdio,
  ROUTER_HOME,
  DEFAULT_CONFIG_PATH,
  type RawServer,
  type UpstreamConfig,
} from './config.js';
import { UpstreamPool } from './pool.js';
import {
  buildManifest,
  loadManifest,
  saveManifest,
  unionTools,
  isStale,
  ManifestStore,
} from './manifest.js';
import { startRouter } from './router.js';
import { UsageStore } from './usage.js';
import { controlToken, TOKEN_PATH } from './control.js';
import { hasTokens, isAuthFailure } from './auth.js';
import { cmdWatch } from './watch.js';
import { configureLogging, log } from './log.js';

function arg(name: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}
const has = (name: string): boolean => process.argv.includes(`--${name}`);

function usage(): void {
  process.stdout.write(`mcp-router — one shared MCP endpoint, upstreams opened on demand

  mcp-router import [--from <path>]   Adopt servers from ~/.claude.json (stdio and http)
  mcp-router index [--force]          Build/refresh the cached tool manifest
  mcp-router serve [--port N] [--idle-ms N] [--verbose]
  mcp-router status [--port N]        Query a running router
  mcp-router tools                    List the namespaced tools served from cache
  mcp-router auth <server>            Authorize an http upstream in your browser
  mcp-router usage [--limit N]        Recent tool calls, with the project that made them
  mcp-router watch [--verbose]        One shot: adopt any new server out of
                                      ~/.claude.json (run by launchd on file change)

Config:   ${DEFAULT_CONFIG_PATH}
Manifest: ${join(ROUTER_HOME, 'manifest.json')}
Token:    ${TOKEN_PATH}
`);
}

/** A flag that is present but not a finite number is an error, not a silent NaN.
 *  `--port abc` would otherwise reach http.listen(NaN), which binds an arbitrary
 *  ephemeral port: the router comes up looking healthy and no client can reach it. */
function numArg(name: string): number | undefined {
  const raw = arg(name);
  if (raw === undefined) return undefined;
  const n = Number(raw);
  if (!Number.isFinite(n)) {
    process.stderr.write(`--${name} expects a number, got "${raw}"\n`);
    process.exit(2);
  }
  return n;
}

/**
 * Copy the servers out of ~/.claude.json into the router's own list.
 *
 * Every candidate is indexed before it is adopted, so a server that cannot start is
 * left where the user typed it rather than disappearing into the router's config to
 * fail there invisibly. That is the contract `watch` has always kept; `import` used
 * to take anything with a command, which is how a server with an unbuilt `dist/`
 * ended up listed in both files and retried every five minutes forever.
 */
async function cmdImport(): Promise<void> {
  const from = arg('from') ?? join(homedir(), '.claude.json');
  if (!existsSync(from)) throw new Error(`no such file: ${from}`);

  const port = numArg('port') ?? 8879;
  const src = JSON.parse(readFileSync(from, 'utf8')) as { mcpServers?: Record<string, RawServer> };
  const all = src.mcpServers ?? {};

  const candidates: Array<{ raw: RawServer; upstream: UpstreamConfig }> = [];
  const skipped: string[] = [];
  for (const [name, s] of Object.entries(all)) {
    if (isSelfReference(name, s, port)) continue; // never proxy to ourselves
    const parsed = parseServer(name, s);
    if ('reason' in parsed) skipped.push(`${name} (${parsed.reason})`);
    else candidates.push({ raw: s, upstream: parsed.upstream });
  }

  configureLogging(join(ROUTER_HOME, 'router.log'), has('verbose'));
  process.stdout.write(`checking ${candidates.length} server(s) before adopting any\n`);

  const manifestPath = join(ROUTER_HOME, 'manifest.json');
  const manifest = loadManifest(manifestPath);
  const pool = new UpstreamPool(
    new Map(candidates.map((c) => [c.upstream.name, c.upstream])),
    0,
    60_000
  );

  const adopt: Record<string, RawServer> = {};
  const failed: string[] = [];
  try {
    for (const { raw, upstream } of candidates) {
      const { failed: bad } = await buildManifest([upstream], pool, manifest, { force: true });
      const entry = manifest.servers[upstream.name];
      // Was `/not authorized|unauthorized|401/i` inline here. That missed the string a
      // live server actually rejects a stale refresh with — `Authentication required` —
      // so `import` reported SKIP for a server that only needed authorizing.
      const authProblem = !!entry?.error && isAuthFailure(entry.error);
      if (!bad.length || authProblem) {
        const { name: _drop, ...rest } = raw as RawServer & { name?: string };
        adopt[upstream.name] = rest;
        process.stdout.write(
          authProblem
            ? `  auth  ${upstream.name} — adopted, needs \`mcp-router auth ${upstream.name}\`\n`
            : `  ok    ${upstream.name} (${entry?.tools.length ?? 0} tools)\n`
        );
      } else {
        failed.push(`${upstream.name}: ${entry?.error ?? 'failed to start'}`);
        process.stdout.write(`  SKIP  ${upstream.name} — ${entry?.error ?? 'failed to start'}\n`);
      }
    }
  } finally {
    await pool.shutdown();
  }

  mkdirSync(ROUTER_HOME, { recursive: true });
  if (existsSync(DEFAULT_CONFIG_PATH)) {
    const backup = `${DEFAULT_CONFIG_PATH}.bak-${Date.now()}`;
    writeFileSync(backup, readFileSync(DEFAULT_CONFIG_PATH));
    process.stdout.write(`backed up existing config -> ${backup}\n`);
  }
  writeFileSync(
    DEFAULT_CONFIG_PATH,
    JSON.stringify({ port, host: '127.0.0.1', idleMs: 300_000, mcpServers: adopt }, null, 2),
    { mode: 0o600 }
  );
  saveManifest(manifestPath, manifest);

  process.stdout.write(`\nadopted ${Object.keys(adopt).length} server(s) -> ${DEFAULT_CONFIG_PATH}\n`);
  if (failed.length) {
    process.stdout.write(
      `left ${failed.length} where you declared it, because it did not start:\n  ${failed.join('\n  ')}\n`
    );
  }
  if (skipped.length) {
    process.stdout.write(`not adoptable:\n  ${skipped.join('\n  ')}\n`);
  }
}

async function withPool<T>(
  fn: (pool: UpstreamPool, upstreams: UpstreamConfig[], cfgPath: string) => Promise<T>
): Promise<T> {
  const { config, skipped } = loadConfig({ port: numArg('port'), idleMs: numArg('idle-ms') });
  configureLogging(config.logPath, has('verbose'));
  if (skipped.length) log.warn(`not proxied: ${skipped.join(', ')}`);

  const map = new Map(config.upstreams.map((u) => [u.name, u]));
  const pool = new UpstreamPool(map, config.idleMs, config.startupTimeoutMs);
  try {
    return await fn(pool, config.upstreams, config.manifestPath);
  } finally {
    await pool.shutdown();
  }
}

async function cmdIndex(): Promise<void> {
  await withPool(async (pool, upstreams, manifestPath) => {
    const manifest = loadManifest(manifestPath);
    const stale = upstreams.filter((u) => isStale(manifest, u));
    process.stdout.write(
      `${upstreams.length} upstreams, ${stale.length} need indexing${has('force') ? ' (forced: all)' : ''}\n`
    );

    const { manifest: next, built, failed } = await buildManifest(upstreams, pool, manifest, {
      force: has('force'),
    });
    saveManifest(manifestPath, next);

    for (const b of built) process.stdout.write(`  ok    ${b}\n`);
    for (const f of failed) process.stdout.write(`  FAIL  ${f}\n`);
    process.stdout.write(
      `\n${unionTools(next, upstreams).length} tools cached -> ${manifestPath}\nAll upstreams closed; none will open again until a tool is called.\n`
    );
  });
}

async function cmdServe(): Promise<void> {
  const { config, skipped } = loadConfig({ port: numArg('port'), idleMs: numArg('idle-ms') });
  configureLogging(config.logPath, has('verbose'));
  if (skipped.length) log.warn(`not proxied: ${skipped.join(', ')}`);

  const store = new ManifestStore(config.manifestPath);
  const manifest = store.current();
  const stale = config.upstreams.filter((u) => isStale(manifest, u));
  if (stale.length) {
    log.warn(
      `${stale.length} upstream(s) not in the manifest (${stale.map((s) => s.name).join(', ')}); ` +
        `their tools will be missing until \`mcp-router index\` runs.`
    );
  }

  // One Map, shared by reference with the pool and the control API, so adding or
  // removing a server through the app reaches the running router without a restart.
  const map = new Map(config.upstreams.map((u) => [u.name, u]));
  const pool = new UpstreamPool(map, config.idleMs, config.startupTimeoutMs);
  const usage = new UsageStore(config.usagePath, config.statsPath);
  const { close } = await startRouter(config, store, pool, map, usage);
  // After listen(), so a slow warm server delays no client: the router is already
  // answering tools/list from cache while these open in the background.
  void pool.warmUp();

  log.info(
    `serving ${unionTools(manifest, config.upstreams).length} tools from ${config.upstreams.length} upstreams; ` +
      `0 open, idle window ${Math.round(config.idleMs / 1000)}s`
  );

  let closing = false;
  const shutdown = (sig: string) => {
    if (closing) return;
    closing = true;
    log.info(`${sig} received; closing upstreams`);
    void close().then(() => process.exit(0));
  };
  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

async function cmdStatus(): Promise<void> {
  const port = numArg('port') ?? 8879;
  try {
    const res = await fetch(`http://127.0.0.1:${port}/status`);
    const body = (await res.json()) as {
      children: Array<{ name: string; transport: string; state: string; calls: number; idleSec: number }>;
      pendingAuth: Array<{ server: string }>;
      tools: number;
      idleMs: number;
    };
    const running = body.children.filter((c) => c.state === 'running');
    process.stdout.write(
      `router on :${port} — ${body.tools} tools, ${running.length}/${body.children.length} upstreams open, idle window ${Math.round(body.idleMs / 1000)}s\n\n`
    );
    for (const c of body.children) {
      const detail = c.state === 'running' ? `${c.calls} calls, idle ${c.idleSec}s` : '';
      process.stdout.write(
        `  ${c.state.padEnd(9)} ${c.transport.padEnd(6)} ${c.name.padEnd(20)} ${detail}\n`
      );
    }
    for (const p of body.pendingAuth ?? []) {
      process.stdout.write(`\n  ! ${p.server} needs authorizing: mcp-router auth ${p.server}\n`);
    }
  } catch (err) {
    process.stdout.write(`no router answering on 127.0.0.1:${port} (${(err as Error).message})\n`);
    process.exitCode = 1;
  }
}

function cmdTools(): void {
  const { config } = loadConfig({});
  const manifest = loadManifest(config.manifestPath);
  const tools = unionTools(manifest, config.upstreams);
  for (const t of tools) process.stdout.write(`${t.name}\n`);
  process.stdout.write(`\n${tools.length} tools from ${config.upstreams.length} upstreams\n`);
}

/**
 * Authorize an HTTP upstream.
 *
 * The flow runs inside the serving process rather than here: the loopback callback
 * binds one fixed port, and two processes racing for it would leave the browser
 * landing on whichever won. This asks the running router to start the flow and then
 * opens the URL it returns.
 */
async function cmdAuth(): Promise<void> {
  const name = process.argv[3];
  if (!name || name.startsWith('--')) throw new Error('usage: mcp-router auth <server>');
  const port = numArg('port') ?? 8879;
  const token = controlToken();

  const res = await fetch(`http://127.0.0.1:${port}/servers/${encodeURIComponent(name)}/auth`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
    body: '{}',
  }).catch((err: Error) => {
    throw new Error(`no router answering on 127.0.0.1:${port} (${err.message}) — start it first`);
  });

  const body = (await res.json()) as { authorizationUrl?: string; error?: string };
  if (!res.ok || !body.authorizationUrl) throw new Error(body.error ?? `authorization could not start`);

  process.stdout.write(`opening your browser to authorize "${name}"\n${body.authorizationUrl}\n`);
  execFile('/usr/bin/open', [body.authorizationUrl], () => undefined);

  // Poll rather than hold the socket: the exchange completes inside the router.
  for (let i = 0; i < 150; i++) {
    await new Promise((r) => setTimeout(r, 2000));
    if (hasTokens(name)) {
      process.stdout.write(`\n✓ ${name} is authorized\n`);
      return;
    }
  }
  process.stdout.write(`\ngave up waiting; run \`mcp-router status\` to check\n`);
  process.exitCode = 1;
}

async function cmdUsage(): Promise<void> {
  const port = numArg('port') ?? 8879;
  const limit = numArg('limit') ?? 40;
  const res = await fetch(`http://127.0.0.1:${port}/usage?limit=${limit}`).catch((err: Error) => {
    throw new Error(`no router answering on 127.0.0.1:${port} (${err.message})`);
  });
  const body = (await res.json()) as {
    since: string;
    records: Array<{
      ts: string;
      server: string;
      tool: string;
      ok: boolean;
      ms: number;
      cold: boolean;
      project?: string;
      pid?: number;
    }>;
  };
  process.stdout.write(`last ${body.records.length} calls (history since ${body.since})\n\n`);
  for (const r of body.records) {
    const when = r.ts.slice(11, 19);
    const where = r.project ? `${r.project}${r.pid ? `:${r.pid}` : ''}` : 'unknown';
    process.stdout.write(
      `  ${when}  ${r.ok ? ' ' : '!'} ${`${r.server}__${r.tool}`.padEnd(38)} ${String(r.ms).padStart(6)}ms ${r.cold ? 'cold' : '    '}  ${where}\n`
    );
  }
}

const cmd = process.argv[2] ?? 'serve';
const run = async (): Promise<void> => {
  switch (cmd) {
    case 'import':
      return cmdImport();
    case 'index':
    case 'refresh':
      return cmdIndex();
    case 'serve':
      return cmdServe();
    case 'status':
      return cmdStatus();
    case 'tools':
      return cmdTools();
    case 'auth':
      return cmdAuth();
    case 'usage':
      return cmdUsage();
    case 'watch':
      return cmdWatch({ verbose: has('verbose') });
    case 'help':
    case '--help':
    case '-h':
      return usage();
    default:
      usage();
      process.exitCode = 1;
  }
};

run().catch((err: Error) => {
  process.stderr.write(`mcp-router: ${err.message}\n`);
  process.exit(1);
});
