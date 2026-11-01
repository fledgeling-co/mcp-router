import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const home = mkdtempSync(join(tmpdir(), 'mcpr-issuer-test-'));
process.env.MCP_ROUTER_HOME = home;
const { FileOAuthProvider, hasTokens, hasRefreshToken, recordState } = await import('../src/auth.js');
const dir = join(home, 'auth'); mkdirSync(dir, { recursive: true });
after(() => rmSync(home, { recursive: true, force: true }));

for (const field of ['tokens', 'clientInformation'] as const) {
  test(`legacy ${field} cannot be forwarded or silently bound to a discovered issuer, and its file survives`, () => {
    const server = `scratch-${field}`;
    const record = { tokens: { access_token: 'synthetic-access', token_type: 'Bearer', refresh_token: 'synthetic-refresh' }, clientInformation: { client_id: 'synthetic-client', client_secret: 'synthetic-secret' } };
    const path = join(dir, `${server}.json`); const bytes = JSON.stringify(record); writeFileSync(path, bytes);
    const provider = new FileOAuthProvider(server, () => undefined);
    assert.throws(() => provider[field](), /Authentication required:.*no trusted issuer binding/);
    assert.equal(hasTokens(server), false); assert.equal(hasRefreshToken(server), false);
    assert.equal(recordState(server), 'reauthorization-required');
    assert.equal(readFileSync(path, 'utf8'), bytes);
    const explicit = new FileOAuthProvider(server, () => undefined, true);
    assert.equal(explicit.tokens(), undefined); assert.equal(explicit.clientInformation(), undefined);
    assert.equal(readFileSync(path, 'utf8'), bytes, 'starting reauthorization must not delete or rewrite the existing record');
  });
}

test('new SDK-issued credentials preserve their issuer exactly on disk and in the provider', () => {
  const provider = new FileOAuthProvider('scratch-bound', () => undefined);
  const issuer = 'https://issuer.example.test';
  const tokens = { access_token: 'synthetic-access', token_type: 'Bearer', refresh_token: 'synthetic-refresh', issuer };
  const client = { client_id: 'synthetic-client', client_secret: 'synthetic-secret', issuer };
  provider.saveClientInformation(client); provider.saveTokens(tokens);
  assert.deepEqual(provider.tokens(), tokens); assert.deepEqual(provider.clientInformation(), client);
  assert.equal(hasTokens('scratch-bound'), true); assert.equal(recordState('scratch-bound'), 'authorized');
  assert.equal(JSON.parse(readFileSync(join(dir, 'scratch-bound.json'), 'utf8')).tokens.issuer, issuer);
});

test('SDK discovery of a different issuer never receives the stored refresh token or client secret', async () => {
  const { auth } = await import('@modelcontextprotocol/sdk/client/auth.js');
  const provider = new FileOAuthProvider('scratch-issuer-mismatch', () => { throw new Error('requires an interactive sign-in'); });
  provider.saveClientInformation({ client_id: 'old-client', client_secret: 'old-secret-marker', issuer: 'https://legitimate.example.test' });
  provider.saveTokens({ access_token: 'old-access-marker', refresh_token: 'old-refresh-marker', token_type: 'Bearer', issuer: 'https://legitimate.example.test' });
  const seen: string[] = [];
  const json = (value: unknown) => new Response(JSON.stringify(value), { status: 200, headers: { 'content-type': 'application/json' } });
  const fetchFn: typeof fetch = async (input, init) => {
    const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url);
    seen.push(JSON.stringify({ url: url.href, headers: init?.headers, body: init?.body?.toString() }));
    if (url.pathname.includes('oauth-protected-resource')) return json({ resource: 'https://mcp.example.test/mcp', authorization_servers: ['https://replacement.example.test'] });
    if (url.pathname.includes('well-known')) return json({ issuer: 'https://replacement.example.test', authorization_endpoint: 'https://replacement.example.test/authorize', token_endpoint: 'https://replacement.example.test/token', registration_endpoint: 'https://replacement.example.test/register', response_types_supported: ['code'], code_challenge_methods_supported: ['S256'] });
    if (url.pathname === '/register') return json({ client_id: 'new-public-client', redirect_uris: [provider.redirectUrl] });
    throw new Error('unexpected OAuth request: ' + url.pathname);
  };
  await assert.rejects(auth(provider, { serverUrl: 'https://mcp.example.test/mcp', fetchFn }), /requires an interactive sign-in/);
  assert.ok(seen.some(request => request.includes('replacement.example.test')), 'the replacement issuer must actually be discovered');
  assert.equal(seen.join('\n').includes('old-refresh-marker'), false);
  assert.equal(seen.join('\n').includes('old-secret-marker'), false);
  assert.equal(seen.join('\n').includes('old-access-marker'), false);
});
