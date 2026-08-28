/**
 * R29's primary path, end to end against the real router: a session that is already attached is
 * TOLD its tool list moved, and re-fetches, with nobody in the loop.
 *
 * The README's standing advice was that a running session fetched its tool list once at init and
 * would not see a change. That is a fact about this router rather than about the protocol.
 * Claude Code opens a standalone `GET /mcp` SSE stream straight after `notifications/initialized`
 * and holds it for the session — measured 2026-08-28,
 * `planning/evidence/R29/exp-A-session-id-sent.log` — and honours
 * `notifications/tools/list_changed` on it in about three milliseconds. The router was serving
 * that stream and keeping no reference to it.
 *
 * The client here is the SDK's own `Client`, which is the one Claude Code uses, and it opens the
 * same GET stream (`_startOrAuthSse` at `start()`).
 *
 * Self-contained: its own HOME, its own port, its own upstreams. It touches nothing configured.
 *
 *   node scripts/e2e-live-reload.mjs
 *
 * Exit 0 clean · 1 findings · 2 the run could not measure what it was asked to.
 */
import { mkdirSync, writeFileSync, rmSync, readFileSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { ToolListChangedNotificationSchema } from '@modelcontextprotocol/sdk/types.js';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..');
const HOME = join(tmpdir(), `mcp-router-livereload-${process.pid}`);
const PORT = 8894;
const BASE = `http://127.0.0.1:${PORT}`;

let failures = 0;
let checks = 0;
const check = (label, ok, detail = '') => {
  checks += 1;
  process.stdout.write(`  ${ok ? 'PASS' : 'FAIL'}  ${label}${detail ? ` — ${detail}` : ''}\n`);
  if (!ok) failures += 1;
};
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

mkdirSync(join(HOME, '.claude', 'mcp-router'), { recursive: true });

const upstream = (name, tool) => {
  const path = join(HOME, `${name}.mjs`);
  writeFileSync(
    path,
    `import { Server } from '${REPO}/node_modules/@modelcontextprotocol/sdk/dist/esm/server/index.js';
import { StdioServerTransport } from '${REPO}/node_modules/@modelcontextprotocol/sdk/dist/esm/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '${REPO}/node_modules/@modelcontextprotocol/sdk/dist/esm/types.js';
const s = new Server({ name: '${name}', version: '1.0.0' }, { capabilities: { tools: {} } });
s.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: [{ name: '${tool}', description: 'x',
  inputSchema: { type: 'object', properties: {} } }] }));
s.setRequestHandler(CallToolRequestSchema, async () => ({ content: [{ type: 'text', text: 'ok' }] }));
await s.connect(new StdioServerTransport());
`
  );
  return path;
};

const firstPath = upstream('first', 'alpha');
const secondPath = upstream('second', 'beta');
writeFileSync(
  join(HOME, '.claude', 'mcp-router', 'servers.json'),
  JSON.stringify({ mcpServers: { first: { command: 'node', args: [firstPath] } } }, null, 2)
);

const run = (args) =>
  spawn('node', [join(REPO, 'dist', 'index.js'), ...args], { env: { ...process.env, HOME }, stdio: 'ignore' });

let serve;
/** Every list_changed notification the attached client received, in order. */
const NOTICES = [];

try {
  await new Promise((resolve, reject) => {
    const p = run(['index']);
    p.on('exit', (c) => (c === 0 ? resolve() : reject(new Error(`index exited ${c}`))));
  });

  serve = run(['serve', '--port', String(PORT)]);
  serve.unref();
  for (let i = 0; i < 40; i++) {
    try {
      if ((await fetch(`${BASE}/health`)).ok) break;
    } catch {
      /* not up yet */
    }
    await wait(250);
  }

  const token = readFileSync(join(HOME, '.claude', 'mcp-router', 'control.token'), 'utf8').trim();
  const post = (path, body, method = 'POST') =>
    fetch(`${BASE}${path}`, {
      method,
      headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
      body: body === undefined ? undefined : JSON.stringify(body),
    });

  const client = new Client({ name: 'r29-live-reload', version: '1.0.0' }, { capabilities: {} });
  client.setNotificationHandler(ToolListChangedNotificationSchema, () => {
    NOTICES.push(Date.now());
  });
  await client.connect(new StreamableHTTPClientTransport(new URL(`${BASE}/mcp`)));

  const before = await client.listTools();
  check('the attached client sees the one configured server', before.tools.length === 1, `${before.tools.length} tool(s)`);

  // The router must KNOW it is holding a stream. This is the count that made the whole feature
  // possible, and it was zero before this item because nothing kept the reference.
  await wait(300);
  let sessions = await (await fetch(`${BASE}/sessions`)).json();
  check(
    'the router holds a notification stream for the attached client',
    sessions.attachedStreams >= 1,
    `${sessions.attachedStreams} stream(s)`
  );
  check('the socket ask is off unless it was turned on', sessions.notifySessions === false);

  // ------------------------------------------------------------------ the primary path
  NOTICES.length = 0;
  const t0 = Date.now();
  const added = await post('/servers', { name: 'second', command: 'node', args: [secondPath] });
  check('adding a server succeeds', added.status === 201, `HTTP ${added.status}`);

  for (let i = 0; i < 40 && NOTICES.length === 0; i++) await wait(50);
  check('the attached session was told, unprompted', NOTICES.length >= 1, `${NOTICES.length} notification(s)`);
  if (NOTICES.length) {
    process.stdout.write(`        (it arrived ${NOTICES[0] - t0}ms after the add)\n`);
  }

  const after = await client.listTools();
  check(
    'and re-fetching now returns the new tool',
    after.tools.length === 2 && after.tools.some((t) => t.name.startsWith('second__')),
    after.tools.map((t) => t.name).join(', ')
  );

  // ------------------------------------------------------------------ the CLI path
  /*
   * `mcpr index` writes the manifest from a DIFFERENT PROCESS and never touches the control API,
   * so nothing in the request path sees it. This is the arm for the poller that does. Without
   * it, "changing an extension reaches every live session" would be true of the app's route and
   * quietly false of the one people type.
   */
  NOTICES.length = 0;
  await new Promise((resolve, reject) => {
    const p = run(['index', '--force']);
    p.on('exit', (c) => (c === 0 ? resolve() : reject(new Error(`index --force exited ${c}`))));
  });
  for (let i = 0; i < 100 && NOTICES.length === 0; i++) await wait(100);
  check(
    'a manifest rebuilt by `mcpr index` from another process reaches the attached session',
    NOTICES.length >= 1,
    `${NOTICES.length} notification(s)`
  );

  /*
   * And it must not keep announcing. The poller runs every three seconds; one that re-fired on
   * an unchanged manifest would send every attached session to re-fetch twenty times a minute.
   */
  NOTICES.length = 0;
  await wait(7_000);
  check('CONTROL: the poller does not re-announce an unchanged manifest', NOTICES.length === 0, `${NOTICES.length}`);

  // ------------------------------------------------------------------ control 1: silence
  /*
   * A change that does not move the tool list must send NOTHING. `warm` changes how a server is
   * run, not what it serves, and a notification here is a re-fetch every attached session pays
   * for and nobody asked for. A feature that announces everything is indistinguishable from one
   * that announces nothing useful.
   */
  NOTICES.length = 0;
  const patched = await post('/servers/second', { warm: true }, 'PATCH');
  check('a warm-only PATCH succeeds', patched.ok, `HTTP ${patched.status}`);
  await wait(600);
  check('CONTROL: a change that does not move the tool list announces nothing', NOTICES.length === 0, `${NOTICES.length}`);

  // ------------------------------------------------------------------ control 2: nobody
  /*
   * The arm that keeps `delivered` honest. With the only client gone, an announcement must
   * report zero delivered. The SDK's `send()` resolves quietly over a stream that has closed, so
   * a count built on a resolved promise would report this as a full delivery — which is why the
   * registry counts bytes that actually moved instead.
   */
  await client.close();
  await wait(500);
  sessions = await (await fetch(`${BASE}/sessions`)).json();
  check('the stream is dropped when the client goes', sessions.attachedStreams === 0, `${sessions.attachedStreams}`);

  const notified = await (await post('/sessions/notify', { reason: 'a push to nobody' })).json();
  check(
    'CONTROL: a push with nobody attached reports 0 delivered',
    notified.tools.delivered === 0,
    `delivered=${notified.tools.delivered}, streams=${notified.tools.streams}`
  );
  check(
    'CONTROL: and it does not claim any session was reached',
    notified.sessions.targeted === 0 || notified.sessions.outcomes.every((o) => o.outcome !== 'delivered'),
    `targeted=${notified.sessions.targeted}`
  );

  // ------------------------------------------------------------------ removal reaches too
  const client2 = new Client({ name: 'r29-live-reload-2', version: '1.0.0' }, { capabilities: {} });
  const seen2 = [];
  client2.setNotificationHandler(ToolListChangedNotificationSchema, () => seen2.push(Date.now()));
  await client2.connect(new StreamableHTTPClientTransport(new URL(`${BASE}/mcp`)));
  await client2.listTools();
  await wait(300);

  const removed = await post('/servers/second', undefined, 'DELETE');
  check('removing a server succeeds', removed.ok, `HTTP ${removed.status}`);
  for (let i = 0; i < 40 && seen2.length === 0; i++) await wait(50);
  check('a removal reaches an attached session too', seen2.length >= 1, `${seen2.length} notification(s)`);
  const back = await client2.listTools();
  check('and the tool it served is gone from the re-fetch', back.tools.length === 1, `${back.tools.length} tool(s)`);
  await client2.close();
} finally {
  serve?.kill('SIGTERM');
  await wait(500);
  serve?.kill('SIGKILL');
  rmSync(HOME, { recursive: true, force: true });
}

if (checks === 0) {
  process.stdout.write('\nerror: this run made no checks, which is a failure rather than a pass.\n');
  process.exit(2);
}
process.stdout.write(`\n${checks - failures}/${checks} checks passed\n`);
process.exit(failures ? 1 : 0);
