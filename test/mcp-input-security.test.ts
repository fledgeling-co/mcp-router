import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cpSync, mkdtempSync, mkdirSync, readFileSync, writeFileSync, realpathSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { MCP_REQUEST_BYTES, MCP_ARGUMENT_ELEMENTS, checkMcpArgumentLimits } from '../src/mcp-input-limits.js';

const call = (args: unknown) => ({ jsonrpc: '2.0', id: 2, method: 'tools/call', params: { name: 'fixture__ping', arguments: args } });
const pause = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

test('argument budget counts both object members and nested array entries at the exact boundary', () => {
  for (const n of [MCP_ARGUMENT_ELEMENTS - 1, MCP_ARGUMENT_ELEMENTS]) {
    checkMcpArgumentLimits(call(Object.fromEntries(Array.from({ length: n }, (_, i) => ['key' + i, null]))));
    checkMcpArgumentLimits(call({ items: Array(n - 1).fill(null) }));
  }
  assert.throws(() => checkMcpArgumentLimits(call(Object.fromEntries(Array.from({ length: MCP_ARGUMENT_ELEMENTS + 1 }, (_, i) => ['key' + i, null])))), /10000/);
  assert.throws(() => checkMcpArgumentLimits(call({ items: Array(MCP_ARGUMENT_ELEMENTS).fill(null) })), /10000/);
  const nested = (depth: number) => { let value: unknown = {}; for (let i = 0; i < depth; i++) value = { nested: value }; return value; };
  checkMcpArgumentLimits(call(nested(128)));
  assert.throws(() => checkMcpArgumentLimits(call(nested(129))), /nesting limit/);
});

test('real router bounds bytes, batches and arguments while valid calls still reach a real scratch upstream', async () => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'mcpr-input-security-')));
  const home = join(root, 'state'); mkdirSync(home);
  cpSync(dirname(fileURLToPath(new URL('../src/index.js', import.meta.url))), join(root, 'dist'), { recursive: true });
  writeFileSync(join(root, 'package.json'), JSON.stringify({ type: 'module' }));
  symlinkSync(resolve('node_modules'), join(root, 'node_modules'), 'dir');
  const probe = createServer(); await new Promise<void>(resolve => probe.listen(0, '127.0.0.1', resolve));
  const port = (probe.address() as { port: number }).port; await new Promise<void>(resolve => probe.close(() => resolve()));
  const peer = join(root, 'document-peer.mjs');
  writeFileSync(peer, `import {Server} from '@modelcontextprotocol/sdk/server/index.js';
import {StdioServerTransport} from '@modelcontextprotocol/sdk/server/stdio.js';
import {ListToolsRequestSchema,CallToolRequestSchema} from '@modelcontextprotocol/sdk/types.js';
const server=new Server({name:'scratch-documents',version:'1'},{capabilities:{tools:{}}});
server.setRequestHandler(ListToolsRequestSchema,async()=>({tools:[{name:'ping',description:'Synthetic document payload witness',inputSchema:{type:'object',properties:{items:{type:'array',items:{type:'null'}},documents:{type:'array',items:{type:'string'}}},additionalProperties:false}}]}));
server.setRequestHandler(CallToolRequestSchema,async request=>({content:[{type:'text',text:request.params.arguments?.documents?'documents:'+request.params.arguments.documents.length+' bytes:'+request.params.arguments.documents.reduce((n,s)=>n+s.length,0):'fixture:ping'}]}));
// The SDK stdio peer also needs an explicit input capacity for the declared multi-document tool.
await server.connect(new StdioServerTransport(process.stdin,process.stdout,{maxBufferSize:32*1024*1024}));`);
  writeFileSync(join(home, 'servers.json'), JSON.stringify({ port, startupTimeoutMs: 3000, mcpServers: { fixture: { command: process.execPath, args: [peer] } } }));
  const child = spawn(process.execPath, [join(root, 'dist/index.js'), 'serve'], { env: { ...process.env, HOME: home, MCP_ROUTER_HOME: home }, stdio: ['ignore', 'ignore', 'pipe'] });
  let errors = ''; child.stderr.on('data', chunk => errors += chunk);
  const ended = new Promise<void>(resolve => child.once('exit', () => resolve()));
  const base = `http://127.0.0.1:${port}`;
  const post = (body: string) => fetch(base + '/mcp', { method: 'POST', headers: { 'content-type': 'application/json', accept: 'application/json, text/event-stream' }, body });
  try {
    let ready = false;
    for (let i = 0; i < 100; i++) { try { if ((await fetch(base + '/health')).ok) { ready = true; break; } } catch {} await pause(50); }
    assert.ok(ready, errors);
    const initialize = JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-03-26', capabilities: {}, clientInfo: { name: 'scratch-boundary', version: '1' } } });
    for (const bytes of [MCP_REQUEST_BYTES - 1, MCP_REQUEST_BYTES]) {
      const response = await post(initialize + ' '.repeat(bytes - Buffer.byteLength(initialize)));
      assert.equal(response.status, 200, `valid initialization at ${bytes} bytes`); await response.text();
    }
    const oversized = await post(initialize + ' '.repeat(MCP_REQUEST_BYTES + 1 - Buffer.byteLength(initialize)));
    assert.equal(oversized.status, 413); assert.match(await oversized.text(), /33554432/);
    for (const count of [99, 100, 101]) {
      const response = await post(JSON.stringify(Array.from({ length: count }, () => ({ jsonrpc: '2.0', method: 'notifications/initialized' }))));
      assert.equal(response.status, count > 100 ? 400 : 202, `batch boundary ${count}`); await response.text();
    }
    const token = readFileSync(join(home, 'control.token'), 'utf8').trim();
    const indexed = await fetch(base + '/servers/fixture/reindex', { method: 'POST', headers: { 'content-type': 'application/json', 'x-mcpr-token': token }, body: '{}' });
    assert.equal(indexed.status, 200, await indexed.text());
    const documents = Array.from({ length: 4 }, () => 'A'.repeat(4 * 1024 * 1024));
    const documentBody = JSON.stringify(call({ documents }));
    assert.ok(Buffer.byteLength(documentBody) > 4 * 1024 * 1024, 'legitimate multi-document requests exceed the SDK default');
    const documentResponse = await post(documentBody);
    assert.equal(documentResponse.status, 200);
    assert.match(await documentResponse.text(), /documents:4 bytes:16777216/);
    const oversizedControl = await fetch(base + '/servers/fixture/reset', { method: 'POST', headers: { 'content-type': 'application/json', 'x-mcpr-token': token }, body: ' '.repeat(MCP_REQUEST_BYTES + 1) });
    assert.equal(oversizedControl.status, 413, 'oversized control input must not execute as an empty write');
    await oversizedControl.text();
    for (const elements of [MCP_ARGUMENT_ELEMENTS - 1, MCP_ARGUMENT_ELEMENTS, MCP_ARGUMENT_ELEMENTS + 1]) {
      const response = await post(JSON.stringify(call({ items: Array(elements - 1).fill(null) })));
      const text = await response.text();
      assert.equal(response.status, elements > MCP_ARGUMENT_ELEMENTS ? 400 : 200, `argument boundary ${elements}: ${text}`);
      assert.match(text, elements > MCP_ARGUMENT_ELEMENTS ? /10000/ : /fixture:ping/);
    }
    assert.equal((await fetch(base + '/health')).status, 200, 'limits refuse requests without crashing the daemon');
  } finally {
    child.kill('SIGTERM'); await Promise.race([ended, pause(7000)]); if (child.exitCode === null) { child.kill('SIGKILL'); await ended; }
    rmSync(root, { recursive: true, force: true });
  }
});
