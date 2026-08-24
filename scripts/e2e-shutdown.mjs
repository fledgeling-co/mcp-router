/**
 * Regression check for a SIGTERM that closes the listener and never exits.
 *
 * `http.close(cb)` stops the server accepting immediately and fires its callback
 * only once every EXISTING connection has ended. An MCP client holds its
 * connection for the whole session, so on a machine with sessions attached the
 * callback never came, `process.exit(0)` sat behind that await, and the router
 * ran on with its listening socket already gone.
 *
 * Measured 24 Aug 2026 on the live daemon: SIGTERM at 06:34, "closing upstreams"
 * logged, and 96 minutes later the process still held 11 established connections
 * and zero LISTEN sockets. Every session that had connected before the signal
 * kept working; every new one got ECONNREFUSED. launchd could not help, because
 * KeepAlive watches for an exit and the process had not exited.
 *
 * The check: hold a real client connection open, send SIGTERM, and require the
 * process to be gone inside the deadline. Against the unfixed build it times out.
 *
 *   node scripts/e2e-shutdown.mjs
 */
import { mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..');
const HOME = join(tmpdir(), `mcp-router-shutdown-${process.pid}`);
const PORT = 8894;
// router.ts allows 5s of grace, index.ts backstops at 15s. A correct shutdown
// finishes in well under a second here, because the only connection is idle.
const EXIT_DEADLINE_MS = 20_000;

let failures = 0;
const check = (label, ok, detail = '') => {
  process.stdout.write(`  ${ok ? 'PASS' : 'FAIL'}  ${label}${detail ? ` — ${detail}` : ''}\n`);
  if (!ok) failures += 1;
};
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const alive = (pid) => {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
};

mkdirSync(join(HOME, '.claude', 'mcp-router'), { recursive: true });
const echoPath = join(HOME, 'echo-server.mjs');
writeFileSync(
  echoPath,
  `import { Server } from '${REPO}/node_modules/@modelcontextprotocol/sdk/dist/esm/server/index.js';
import { StdioServerTransport } from '${REPO}/node_modules/@modelcontextprotocol/sdk/dist/esm/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '${REPO}/node_modules/@modelcontextprotocol/sdk/dist/esm/types.js';
const server = new Server({ name: 'echo', version: '0' }, { capabilities: { tools: {} } });
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [{ name: 'echo', description: 'echo', inputSchema: { type: 'object', properties: {} } }],
}));
server.setRequestHandler(CallToolRequestSchema, async () => ({ content: [{ type: 'text', text: 'ok' }] }));
await server.connect(new StdioServerTransport());
`
);
writeFileSync(
  join(HOME, '.claude', 'mcp-router', 'servers.json'),
  JSON.stringify({ mcpServers: { echo: { command: 'node', args: [echoPath] } } }, null, 2)
);

const run = (args, opts = {}) =>
  spawn('node', [join(REPO, 'dist', 'index.js'), ...args], {
    env: { ...process.env, HOME },
    stdio: 'ignore',
    ...opts,
  });

let serve;
let client;
try {
  await new Promise((resolve, reject) => {
    const p = run(['index']);
    p.on('exit', (c) => (c === 0 ? resolve() : reject(new Error(`index exited ${c}`))));
  });

  serve = run(['serve', '--port', String(PORT)]);
  const base = `http://127.0.0.1:${PORT}`;
  let up = false;
  for (let i = 0; i < 40; i++) {
    try {
      await fetch(`${base}/status`);
      up = true;
      break;
    } catch {
      await wait(250);
    }
  }
  check('the router came up', up);
  if (!up) throw new Error('router never listened');

  // A real session, held open — this is the condition that produced the hang.
  client = new Client({ name: 'shutdown-probe', version: '0' }, { capabilities: {} });
  await client.connect(new StreamableHTTPClientTransport(new URL(`${base}/mcp`)));
  await client.listTools();
  check('a client is connected and served', true);

  const before = await fetch(`${base}/status`).then((r) => r.ok).catch(() => false);
  check('the listener answers while a client holds a connection', before);

  const t0 = Date.now();
  process.kill(serve.pid, 'SIGTERM');

  let exited = false;
  while (Date.now() - t0 < EXIT_DEADLINE_MS) {
    if (!alive(serve.pid)) {
      exited = true;
      break;
    }
    await wait(100);
  }
  const took = Date.now() - t0;

  check(
    'SIGTERM exits the process while a connection is open',
    exited,
    exited
      ? `${took}ms`
      : `still alive after ${took}ms — the listener is closed and nothing supervises this state`
  );

  // The half-closed state is the specific thing being ruled out: a process that
  // is alive and not listening looks healthy to everyone already attached.
  if (!exited) {
    const refuses = await fetch(`${base}/status`).then(
      () => false,
      () => true
    );
    check('and it is the half-closed state, not a slow exit', refuses, 'listener already gone');
  }
} catch (err) {
  check('run completed', false, err instanceof Error ? err.message : String(err));
} finally {
  try {
    await client?.close();
  } catch {
    /* the server is going away; nothing to salvage */
  }
  if (serve?.pid && alive(serve.pid)) {
    process.kill(serve.pid, 'SIGKILL');
    process.stdout.write('  note  had to SIGKILL the router to clean up\n');
  }
  rmSync(HOME, { recursive: true, force: true });
}

process.stdout.write(failures ? `\n${failures} failure(s)\n` : '\nshutdown check clean\n');
process.exit(failures ? 1 : 0);
