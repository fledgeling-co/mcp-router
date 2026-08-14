#!/usr/bin/env node
/**
 * A fixture MCP server with one deliberately slow tool.
 *
 * `mcp-fixture-server.mjs` answers instantly, which is right for every lane that exists — and makes
 * two of the pool's decisions unmeasurable. "A call outstanding is never reaped" needs a call that
 * is still outstanding when the idle window expires, and there is no way to hold one open against a
 * server that always answers in a millisecond.
 *
 * A new file rather than a mode on the existing one: `parity-pool.sh` and the fixture capture both
 * depend on that server's exact tool surface, and adding a tool to it would change every `tools/list`
 * they compare.
 *
 * Newline-delimited JSON-RPC on stdout, which is what the stdio transport on both sides expects.
 */
import { createInterface } from 'node:readline';

const send = (message) => process.stdout.write(`${JSON.stringify(message)}\n`);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const TOOLS = [
  {
    name: 'sleep',
    description: 'Answer after the requested number of milliseconds.',
    inputSchema: {
      type: 'object',
      properties: { ms: { type: 'number' } },
      required: ['ms'],
      additionalProperties: false,
    },
  },
];

createInterface({ input: process.stdin }).on('line', (line) => {
  let request;
  try {
    request = JSON.parse(line);
  } catch {
    return;
  }
  // A notification has no id and gets no answer, which is what keeps `notifications/initialized`
  // from producing a stray response frame the client would not know what to do with.
  if (request.id === undefined) return;

  void (async () => {
    if (request.method === 'initialize') {
      send({
        jsonrpc: '2.0',
        id: request.id,
        result: {
          protocolVersion: '2025-06-18',
          capabilities: { tools: {} },
          serverInfo: { name: 'fixture-slow', version: '1.0.0' },
        },
      });
      return;
    }
    if (request.method === 'tools/list') {
      send({ jsonrpc: '2.0', id: request.id, result: { tools: TOOLS } });
      return;
    }
    if (request.method === 'tools/call') {
      const ms = Number(request.params?.arguments?.ms ?? 0);
      await sleep(Number.isFinite(ms) ? Math.max(0, ms) : 0);
      send({
        jsonrpc: '2.0',
        id: request.id,
        result: { content: [{ type: 'text', text: `slept ${ms}ms` }] },
      });
      return;
    }
    send({ jsonrpc: '2.0', id: request.id, error: { code: -32601, message: 'Method not found' } });
  })();
});
