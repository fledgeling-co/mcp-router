#!/usr/bin/env node
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import {
  loadConfig,
  ROUTER_HOME,
  DEFAULT_CONFIG_PATH,
  type UpstreamConfig,
} from './config.js';
import { ChildPool } from './pool.js';
import {
  buildManifest,
  loadManifest,
  saveManifest,
  unionTools,
  isStale,
  ManifestStore,
} from './manifest.js';
import { startRouter } from './router.js';
import { cmdWatch } from './watch.js';
import { configureLogging, log } from './log.js';

function arg(name: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}
const has = (name: string): boolean => process.argv.includes(`--${name}`);

function usage(): void {
  process.stdout.write(`mcp-router — one shared HTTP MCP endpoint, lazily spawned upstreams

  mcp-router import [--from <path>]   Generate servers.json from ~/.claude.json
  mcp-router index [--force]          Build/refresh the cached tool manifest
  mcp-router serve [--port N] [--idle-ms N] [--verbose]
  mcp-router status [--port N]        Query a running router
  mcp-router tools                    List the namespaced tools served from cache
  mcp-router watch [--verbose]        One shot: adopt any new stdio server out of
                                      ~/.claude.json (run by launchd on file change)

Config:   ${DEFAULT_CONFIG_PATH}
Manifest: ${join(ROUTER_HOME, 'manifest.json')}
`);
}

/** Copy the stdio servers out of ~/.claude.json into the router's own list. */
function cmdImport(): void {
  const from = arg('from') ?? join(homedir(), '.claude.json');
  if (!existsSync(from)) throw new Error(`no such file: ${from}`);

  const src = JSON.parse(readFileSync(from, 'utf8')) as {
    mcpServers?: Record<string, { type?: string; command?: string; url?: string }>;
  };
  const all = src.mcpServers ?? {};

  const stdio: Record<string, unknown> = {};
  const skipped: string[] = [];
  for (const [name, s] of Object.entries(all)) {
    if ((s.type ?? 'stdio') === 'stdio' && s.command) stdio[name] = s;
    else skipped.push(`${name} (${s.type ?? 'unknown'})`);
  }

  mkdirSync(ROUTER_HOME, { recursive: true });
  if (existsSync(DEFAULT_CONFIG_PATH)) {
    const backup = `${DEFAULT_CONFIG_PATH}.bak-${Date.now()}`;
    writeFileSync(backup, readFileSync(DEFAULT_CONFIG_PATH));
    process.stdout.write(`backed up existing config -> ${backup}\n`);
  }
  writeFileSync(
    DEFAULT_CONFIG_PATH,
    JSON.stringify({ port: 8879, host: '127.0.0.1', idleMs: 300_000, mcpServers: stdio }, null, 2)
  );

  process.stdout.write(`wrote ${Object.keys(stdio).length} stdio servers -> ${DEFAULT_CONFIG_PATH}\n`);
  if (skipped.length) {
    process.stdout.write(
      `skipped ${skipped.length} non-stdio (already shared endpoints, left on their own transport):\n  ${skipped.join('\n  ')}\n`
    );
  }
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

async function withPool<T>(
  fn: (pool: ChildPool, upstreams: UpstreamConfig[], cfgPath: string) => Promise<T>
): Promise<T> {
  const { config, skipped } = loadConfig({
    port: numArg('port'),
    idleMs: numArg('idle-ms'),
  });
  configureLogging(config.logPath, has('verbose'));
  if (skipped.length) log.warn(`not proxied: ${skipped.join(', ')}`);

  const map = new Map(config.upstreams.map((u) => [u.name, u]));
  const pool = new ChildPool(map, config.idleMs, config.startupTimeoutMs);
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
      `\n${unionTools(next, upstreams).length} tools cached -> ${manifestPath}\nAll children shut down; none will start again until a tool is called.\n`
    );
  });
}

async function cmdServe(): Promise<void> {
  const { config, skipped } = loadConfig({
    port: arg('port') ? Number(arg('port')) : undefined,
    idleMs: arg('idle-ms') ? Number(arg('idle-ms')) : undefined,
  });
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

  const map = new Map(config.upstreams.map((u) => [u.name, u]));
  const pool = new ChildPool(map, config.idleMs, config.startupTimeoutMs);
  const { close } = await startRouter(config, store, pool);

  log.info(
    `serving ${unionTools(manifest, config.upstreams).length} tools from ${config.upstreams.length} upstreams; ` +
      `0 children running, idle window ${Math.round(config.idleMs / 1000)}s`
  );

  let closing = false;
  const shutdown = (sig: string) => {
    if (closing) return;
    closing = true;
    log.info(`${sig} received; closing children`);
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
      children: Array<{ name: string; state: string; calls: number; idleSec: number }>;
      tools: number;
      idleMs: number;
    };
    const running = body.children.filter((c) => c.state === 'running');
    process.stdout.write(
      `router on :${port} — ${body.tools} tools, ${running.length}/${body.children.length} children running, idle window ${Math.round(body.idleMs / 1000)}s\n\n`
    );
    for (const c of body.children) {
      const detail = c.state === 'running' ? `${c.calls} calls, idle ${c.idleSec}s` : '';
      process.stdout.write(`  ${c.state.padEnd(9)} ${c.name.padEnd(20)} ${detail}\n`);
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
