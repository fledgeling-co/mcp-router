/**
 * Regression check for the idle reaper closing a child out from under a call
 * that is still running.
 *
 * The idle timer is armed when a child is acquired, not when its work finishes.
 * Before the in-flight accounting in ChildPool, a call that outlived idleMs had
 * its own child closed mid-request and came back as `MCP error -32000:
 * Connection closed`. That is not a corner case: a Deep Research run is
 * documented at 4 to 60 minutes and the default idle window is 5 minutes, so
 * every one of those died at the five-minute mark.
 *
 * This runs the router against a purpose-built upstream whose only tool sleeps
 * for as long as it is told, with an idle window deliberately shorter than the
 * call, in an isolated HOME so it cannot touch the real server list.
 *
 *   node scripts/e2e-idle.mjs
 */
import { mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..');
const HOME = join(tmpdir(), `mcp-router-idle-${process.pid}`);
const PORT = 8893;
const IDLE_MS = 2000;
const SLEEP_MS = 6000;

let failures = 0;
const check = (label, ok, detail = '') => {
  process.stdout.write(`  ${ok ? 'PASS' : 'FAIL'}  ${label}${detail ? ` — ${detail}` : ''}\n`);
  if (!ok) failures += 1;
};
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

mkdirSync(join(HOME, '.claude', 'mcp-router'), { recursive: true });
const slowPath = join(HOME, 'slow-server.mjs');
writeFileSync(
  slowPath,
  `import { Server } from '${REPO}/node_modules/@modelcontextprotocol/sdk/dist/esm/server/index.js';
import { StdioServerTransport } from '${REPO}/node_modules/@modelcontextprotocol/sdk/dist/esm/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '${REPO}/node_modules/@modelcontextprotocol/sdk/dist/esm/types.js';
const s = new Server({ name: 'slow', version: '1.0.0' }, { capabilities: { tools: {} } });
s.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: [{ name: 'sleep', description: 'sleep for ms',
  inputSchema: { type: 'object', properties: { ms: { type: 'number' } } } }] }));
s.setRequestHandler(CallToolRequestSchema, async (req) => {
  await new Promise((r) => setTimeout(r, req.params.arguments?.ms ?? 1000));
  return { content: [{ type: 'text', text: 'still alive' }] };
});
await s.connect(new StdioServerTransport());
`
);
writeFileSync(
  join(HOME, '.claude', 'mcp-router', 'servers.json'),
  JSON.stringify({ mcpServers: { slow: { command: 'node', args: [slowPath] } } }, null, 2)
);

const run = (args, opts = {}) =>
  spawn('node', [join(REPO, 'dist', 'index.js'), ...args], {
    env: { ...process.env, HOME },
    stdio: 'ignore',
    ...opts,
  });

let serve;
try {
  await new Promise((resolve, reject) => {
    const p = run(['index']);
    p.on('exit', (c) => (c === 0 ? resolve() : reject(new Error(`index exited ${c}`))));
  });

  serve = run(['serve', '--port', String(PORT), '--idle-ms', String(IDLE_MS)]);
  serve.unref();

  const base = `http://127.0.0.1:${PORT}`;
  for (let i = 0; i < 30; i++) {
    try {
      if ((await fetch(`${base}/health`)).ok) break;
    } catch {
      /* not up yet */
    }
    await wait(500);
  }

  const client = new Client({ name: 'idle-regression', version: '1.0.0' }, { capabilities: {} });
  await client.connect(new StreamableHTTPClientTransport(new URL(`${base}/mcp`)));

  const t0 = Date.now();
  const res = await client.callTool(
    { name: 'slow__sleep', arguments: { ms: SLEEP_MS } },
    undefined,
    { timeout: 60_000 }
  );
  const elapsed = Date.now() - t0;

  check(
    `a ${SLEEP_MS}ms call survives a ${IDLE_MS}ms idle window`,
    res.isError !== true,
    res.isError ? String(res.content?.[0]?.text).slice(0, 90) : `${elapsed}ms`
  );
  check('the call ran to completion rather than being cut short', elapsed >= SLEEP_MS, `${elapsed}ms`);

  // And the window still applies once the work is done: the clock restarts from
  // completion, so the child goes away shortly after rather than lingering.
  await wait(IDLE_MS + 1500);
  const after = await (await fetch(`${base}/status`)).json();
  const stillUp = after.children.filter((c) => c.state === 'running').map((c) => c.name);
  check('the child is reaped once the call has finished', stillUp.length === 0, stillUp.join(', ') || 'none');

  await client.close();
} finally {
  if (serve) serve.kill('SIGTERM');
  rmSync(HOME, { recursive: true, force: true });
}

process.stdout.write(`\n${failures === 0 ? 'all checks passed' : `${failures} check(s) failed`}\n`);
process.exit(failures === 0 ? 0 : 1);
