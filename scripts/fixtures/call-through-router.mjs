/**
 * Call one tool through the router, so the capture has real usage records to record.
 *
 * `/usage` on a router nobody has called is `{since, records: []}` — a shape that decodes whatever
 * the record model says, because there are no records in it to disagree with. The call log is the
 * one surface where an empty fixture proves nothing at all, so the capture makes a real call and
 * records what the router wrote down about it.
 */
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';

const url = process.argv[2];
const toolName = process.argv[3];
if (!url || !toolName) {
  process.stderr.write('usage: call-through-router.mjs <router-mcp-url> <tool-name>\n');
  process.exit(2);
}

const client = new Client({ name: 'mcp-router-fixtures', version: '1.0.0' }, { capabilities: {} });
await client.connect(new StreamableHTTPClientTransport(new URL(url)));

const { tools } = await client.listTools();
const target = tools.find((t) => t.name === toolName || t.name.endsWith(`__${toolName}`));
if (!target) {
  process.stderr.write(`no tool matching "${toolName}" — saw: ${tools.map((t) => t.name).join(', ')}\n`);
  process.exit(1);
}

await client.callTool({ name: target.name, arguments: {} });
process.stdout.write(`called ${target.name}\n`);

// Stay connected while the router works out who called it.
//
// The router attributes a call by running `lsof -sTCP:ESTABLISHED` against the peer port (see
// `ClientIdentity` in src/usage.ts) and that lookup is asynchronous — two spawns, off the request
// path. Closing here the moment the call returns races it: if the socket has left ESTABLISHED by
// the time lsof looks, the router correctly records the call with no `pid`, `cwd`, `project` or
// `client`, because it genuinely could not tell.
//
// That is right for the router and wrong for a *fixture*, which exists to record those fields on
// the wire. Measured back-to-back on one machine, two captures disagreed — one resolved a pid, the
// next did not — so the recording carried the attribution roughly half the time, and the half that
// lost reddened the suite later for a reason that was never a defect.
//
// Holding the socket open covers the lookup, which lands well inside this window.
await new Promise((resolve) => setTimeout(resolve, 1500));

await client.close();
