/**
 * End-to-end check against a running router, using the same SDK client Claude Code
 * uses. Proves the initialize handshake, tools/list and tools/call all work over
 * HTTP — and, crucially, that a call spawns only its own upstream.
 *
 *   node scripts/e2e.mjs [--url http://127.0.0.1:8879/mcp]
 */
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';

const url = process.argv.includes('--url')
  ? process.argv[process.argv.indexOf('--url') + 1]
  : 'http://127.0.0.1:8879/mcp';
const base = url.replace(/\/mcp$/, '');

const status = async () => (await fetch(`${base}/status`)).json();
const running = (s) => s.children.filter((c) => c.state === 'running').map((c) => c.name);

let failures = 0;
const check = (label, ok, detail = '') => {
  process.stdout.write(`  ${ok ? 'PASS' : 'FAIL'}  ${label}${detail ? ` — ${detail}` : ''}\n`);
  if (!ok) failures += 1;
};

const before = await status();
process.stdout.write(`router: ${before.tools} tools, children running: ${running(before).length}\n\n`);

const client = new Client({ name: 'mcp-router-e2e', version: '1.0.0' }, { capabilities: {} });
await client.connect(new StreamableHTTPClientTransport(new URL(url)));
check('initialize handshake completes', true);

const { tools } = await client.listTools();
check('tools/list returns the cached union', tools.length === before.tools, `${tools.length} tools`);
check(
  'every tool is namespaced <server>__<tool>',
  tools.every((t) => t.name.includes('__')),
  `${tools.filter((t) => !t.name.includes('__')).length} unnamespaced`
);

const target = tools.find((t) => t.name.startsWith('lifeline__'));
check('a known upstream tool is present', !!target, target?.name);

if (target) {
  const res = await client.callTool({ name: target.name, arguments: {} });
  check('tools/call returns content', Array.isArray(res.content) && res.content.length > 0);

  const after = await status();
  const spawned = running(after);
  check('the called upstream is now running', spawned.includes('lifeline'), spawned.join(', ') || 'none');
  check(
    'no other upstream was spawned',
    spawned.length === 1,
    `${spawned.length} running: ${spawned.join(', ')}`
  );
}

const unknown = await client.callTool({ name: 'nosuchserver__nope', arguments: {} });
check('unknown server returns a tool error, not a crash', unknown.isError === true);
check('router still healthy after a bad call', (await fetch(`${base}/health`)).ok);

await client.close();
process.stdout.write(`\n${failures === 0 ? 'all checks passed' : `${failures} check(s) failed`}\n`);
process.exit(failures === 0 ? 0 : 1);
