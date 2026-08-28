/* Experiment 2: hold the standalone GET SSE stream, push
   notifications/tools/list_changed down it, and record whether the client
   re-fetches tools/list — and whether it sees the NEW tool.
   --no-session-id runs the same experiment with the mcp-session-id header
   suppressed, which is what a stateless (sessionIdGenerator: undefined) server does. */
import { createServer } from 'node:http';
import { appendFileSync } from 'node:fs';

const SUPPRESS = process.argv.includes('--no-session-id');
const LOG = process.argv[process.argv.indexOf('--log') + 1];
const note = (s) => appendFileSync(LOG, `${new Date().toISOString()} ${s}\n`);

let toolSet = 1;              // 1 = one tool, 2 = two tools
let listCalls = 0;
let sse = null;

const tools = () =>
  toolSet === 1
    ? [{ name: 'r29_probe_first', description: 'the tool present at init', inputSchema: { type: 'object', properties: {} } }]
    : [
        { name: 'r29_probe_first', description: 'the tool present at init', inputSchema: { type: 'object', properties: {} } },
        { name: 'r29_probe_second', description: 'ADDED AFTER INIT', inputSchema: { type: 'object', properties: {} } },
      ];

const server = createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    if (req.method === 'GET') {
      note(`GET /mcp -> standalone SSE stream OPENED (session-id header ${SUPPRESS ? 'SUPPRESSED' : 'sent'})`);
      res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-store', connection: 'keep-alive' });
      res.write(': open\n\n');
      sse = res;
      res.on('close', () => { note('GET: standalone SSE stream closed'); sse = null; });
      return;
    }
    if (req.method === 'DELETE') { res.writeHead(200).end(); return; }
    let msg; try { msg = JSON.parse(body); } catch { res.writeHead(202).end(); return; }
    const headers = { 'content-type': 'application/json' };
    if (!SUPPRESS) headers['mcp-session-id'] = 'r29-probe-session';
    const reply = (result) => { res.writeHead(200, headers); res.end(JSON.stringify({ jsonrpc: '2.0', id: msg.id, result })); };
    if (msg.method === 'initialize')
      return reply({ protocolVersion: msg.params?.protocolVersion ?? '2025-06-18', capabilities: { tools: { listChanged: true } }, serverInfo: { name: 'r29-probe', version: '0.0.1' } });
    if (msg.method === 'tools/list') {
      listCalls += 1;
      note(`tools/list #${listCalls} answered with ${tools().length} tool(s): ${tools().map((t) => t.name).join(', ')}`);
      return reply({ tools: tools() });
    }
    if (msg.method === 'tools/call') return reply({ content: [{ type: 'text', text: 'ok' }] });
    if (msg.method?.startsWith('notifications/')) { res.writeHead(202).end(); return; }
    return reply({});
  });
});

server.listen(8977, '127.0.0.1', () => note('listening'));

// After 12s: change the tool set and push the notification.
setTimeout(() => {
  toolSet = 2;
  if (sse) {
    sse.write(`data: ${JSON.stringify({ jsonrpc: '2.0', method: 'notifications/tools/list_changed' })}\n\n`);
    note('PUSHED notifications/tools/list_changed down the standalone SSE stream');
  } else {
    note('COULD NOT PUSH: no standalone SSE stream is open');
  }
}, 12_000);

setTimeout(() => { note(`FINAL: tools/list was called ${listCalls} time(s)`); process.exit(0); }, 90_000);
