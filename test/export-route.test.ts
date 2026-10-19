import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, type Server } from 'node:http';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { AddressInfo } from 'node:net';
import type { ControlDeps } from '../src/control.js';

// The route reads servers.json from ROUTER_HOME, which is fixed when config.ts loads. Point it at a
// scratch home before the control module is imported, so the test never reads a real server list.
const home = mkdtempSync(join(tmpdir(), 'mcpr-export-route-'));
process.env.MCP_ROUTER_HOME = home;
writeFileSync(
  join(home, 'servers.json'),
  JSON.stringify({
    mcpServers: {
      alpha: { command: 'node', args: ['/opt/alpha.js', '--token', 'route-argv-secret-0042'], env: { API_KEY: 'route-env-secret-0042' } },
      beta: { url: 'https://beta.example.com/mcp', headers: { Authorization: 'Bearer route-header-secret-0042' } },
    },
  })
);

const { handleControl } = await import('../src/control.js');

const TOKEN = 'ctl_route_test_token_0123456789';
const SECRETS = ['route-argv-secret-0042', 'route-env-secret-0042', 'route-header-secret-0042'];

let server: Server;
let base: string;

before(async () => {
  server = createServer((req, res) => {
    void handleControl(req, res, new URL(req.url ?? '/', 'http://127.0.0.1'), undefined, {} as ControlDeps, TOKEN);
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});

after(() => {
  server.close();
});

test('GET /export refuses a request with no token, and the refusal carries no secret', async () => {
  const res = await fetch(`${base}/export`);
  assert.equal(res.status, 401);
  const body = await res.text();
  for (const secret of SECRETS) assert.ok(!body.includes(secret));
});

test('GET /export refuses a wrong token', async () => {
  const res = await fetch(`${base}/export`, { headers: { 'x-mcpr-token': 'not-the-token' } });
  assert.equal(res.status, 401);
});

test('GET /export answers with the redacted document when given the token', async () => {
  const res = await fetch(`${base}/export`, { headers: { 'x-mcpr-token': TOKEN } });
  assert.equal(res.status, 200);
  assert.equal(res.headers.get('cache-control'), 'no-store');
  const text = await res.text();
  for (const secret of SECRETS) assert.ok(!text.includes(secret), `a secret reached the route body: ${secret}`);
  const doc = JSON.parse(text) as { mcpServers: Record<string, { env?: Record<string, string> }> };
  assert.equal(doc.mcpServers.alpha.env?.API_KEY, '<redacted:env.API_KEY>');
});

test('GET /export?only= filters to the named servers', async () => {
  const res = await fetch(`${base}/export?only=beta`, { headers: { 'x-mcpr-token': TOKEN } });
  assert.equal(res.status, 200);
  const doc = (await res.json()) as { mcpServers: Record<string, unknown> };
  assert.deepEqual(Object.keys(doc.mcpServers), ['beta']);
});

test('GET /export?only= with an unknown name is a 400, not an empty document', async () => {
  const res = await fetch(`${base}/export?only=nope`, { headers: { 'x-mcpr-token': TOKEN } });
  assert.equal(res.status, 400);
  const body = (await res.json()) as { error: string };
  assert.match(body.error, /"nope"/);
});
