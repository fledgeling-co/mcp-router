import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, type Server as HttpServer } from 'node:http';
import { UpstreamPool } from '../src/pool.js';
import { refreshAuthorization } from '@modelcontextprotocol/sdk/client/auth.js';
import type { AuthorizationServerMetadata } from '@modelcontextprotocol/sdk/shared/auth.js';

async function listen(server: HttpServer): Promise<string> {
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve));
  return `http://127.0.0.1:${(server.address() as { port: number }).port}`;
}
async function close(server: HttpServer) { server.closeAllConnections(); await new Promise<void>(resolve => server.close(() => resolve())); }

for (const transport of ['http', 'sse'] as const) {
  test(`${transport} upstream refuses a cross-origin redirect before forwarding its custom credential`, async () => {
    const leaked: string[] = [];
    const observer = createServer((req, res) => { leaked.push(String(req.headers['x-api-key'])); res.writeHead(500).end(); });
    const destination = await listen(observer);
    const seen: string[] = [];
    const source = createServer((req, res) => { seen.push(String(req.headers['x-api-key'])); res.writeHead(307, { location: destination + '/collect' }).end(); });
    const origin = await listen(source);
    const upstream = { name: 'scratch-redirect', transport, url: origin + '/mcp', headers: { 'X-API-Key': 'synthetic-credential-marker' }, oauth: false };
    const pool = new UpstreamPool(new Map([[upstream.name, upstream]]), 0, 2000);
    try {
      await assert.rejects(pool.acquire(upstream.name));
      assert.ok(seen.length > 0, 'source origin must actually receive the credential');
      assert.equal(seen[0], 'synthetic-credential-marker');
      assert.deepEqual(leaked, [], 'redirect destination must receive no request at all');
    } finally { await pool.shutdown(); await close(source); await close(observer); }
  });
}

test('OAuth refresh blocks307 token-body forwarding to another origin but preserves a same-origin redirect', async () => {
  const leaked: string[] = [];
  const observer = createServer(async (req, res) => { let body = ''; for await (const chunk of req) body += chunk; leaked.push(body); res.writeHead(500).end(); });
  const destination = await listen(observer);
  const seen: string[] = [];
  let crossOrigin = true;
  const source = createServer(async (req, res) => {
    let body = ''; for await (const chunk of req) body += chunk;
    seen.push(body);
    if (req.url === '/token') res.writeHead(307, { location: crossOrigin ? destination + '/collect' : '/issued' }).end();
    else res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({ access_token: 'synthetic-access', token_type: 'Bearer' }));
  });
  const origin = await listen(source);
  const options = {
    metadata: { issuer: origin, authorization_endpoint: origin + '/authorize', token_endpoint: origin + '/token', response_types_supported: ['code'], token_endpoint_auth_methods_supported: ['client_secret_post'] } as AuthorizationServerMetadata,
    clientInformation: { client_id: 'synthetic-client', client_secret: 'synthetic-secret', issuer: origin }, refreshToken: 'synthetic-refresh',
  };
  try {
    await assert.rejects(refreshAuthorization(origin, options));
    assert.match(seen[0], /synthetic-refresh/);
    assert.match(seen[0], /synthetic-secret/);
    assert.deepEqual(leaked, []);
    crossOrigin = false;
    const tokens = await refreshAuthorization(origin, options);
    assert.equal(tokens.access_token, 'synthetic-access');
    assert.match(seen.at(-1)!, /synthetic-refresh/);
    assert.deepEqual(leaked, []);
  } finally { await close(source); await close(observer); }
});
