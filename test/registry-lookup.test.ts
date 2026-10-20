import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { InboxStore, reviewDigestOf, type NewInboxRow } from '../src/inbox.js';

/*
 * The live by-id lookup a pick is resolved through (planning/plans/plan-phone-inbox.md §2.2). Both
 * indexes are one local fixture server, so the lookup's requests and answers are the test's own. The
 * registry module reads its base URLs when it loads, so it is imported after the environment is set.
 */
type RegistryModule = typeof import('../src/registry.js');

const scratch = mkdtempSync(join(tmpdir(), 'registry-lookup-'));
const requests: Array<{ path: string; query: string | null }> = [];
const hanging: ServerResponse[] = [];
let server: Server;
let registry: RegistryModule;

const atlasOfficial = {
  name: 'io.acme/atlas',
  description: 'Atlas maps things',
  version: '1.0.0',
  repository: { url: 'https://github.com/acme/atlas' },
  packages: [{ registryType: 'npm', identifier: '@acme/atlas', version: '1.0.0' }],
};

function answer(res: ServerResponse, status: number, body: unknown): void {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
}

function handle(req: IncomingMessage, res: ServerResponse): void {
  const url = new URL(req.url ?? '/', 'http://fixture');
  const q = url.searchParams.get('search') ?? url.searchParams.get('q');
  requests.push({ path: url.pathname, query: q });

  if (url.pathname === '/v0/servers') {
    if (q === 'io.acme/atlas') {
      return answer(res, 200, { servers: [{ server: atlasOfficial, _meta: { x: { updatedAt: '2026-01-01T00:00:00Z' } } }] });
    }
    // A near-miss: the index answers, but with a different id, which must not count as a match.
    if (q === 'io.acme/neighbour') {
      return answer(res, 200, { servers: [{ server: { ...atlasOfficial, name: 'io.acme/neighbour-fork' } }] });
    }
    if (q === 'io.acme/broken') return answer(res, 503, { error: 'down' });
    if (q === 'io.acme/slow') {
      hanging.push(res);
      return;
    }
    return answer(res, 200, { servers: [] });
  }

  if (url.pathname === '/servers' && q === 'acme/atlas') {
    return answer(res, 200, {
      servers: [
        {
          qualifiedName: 'acme/atlas',
          displayName: 'Atlas',
          description: 'Hosted atlas',
          verified: true,
          useCount: 42,
          remote: true,
          isDeployed: true,
          createdAt: '2026-02-01T00:00:00Z',
        },
      ],
    });
  }
  return answer(res, 200, { servers: [] });
}

before(async () => {
  server = createServer(handle);
  await new Promise<void>((done) => server.listen(0, '127.0.0.1', done));
  const { port } = server.address() as AddressInfo;
  process.env.MCP_ROUTER_REGISTRY = `http://127.0.0.1:${port}`;
  process.env.MCP_ROUTER_SMITHERY = `http://127.0.0.1:${port}`;
  process.env.MCP_ROUTER_HOME = scratch;
  registry = await import('../src/registry.js');
});

after(() => {
  for (const res of hanging) res.destroy();
  server.closeAllConnections();
  server.close();
  rmSync(scratch, { recursive: true, force: true });
});

function row(id: string, resolved: NewInboxRow['resolved']): NewInboxRow {
  return {
    id,
    phoneId: 'phone-a',
    deviceName: "Luke's iPhone",
    queuedAt: '2026-10-19T10:00:00Z',
    receivedAt: '2026-10-19T10:00:05Z',
    resolved,
  };
}

test('an official id resolves to the index entry that carries that exact id', async () => {
  requests.length = 0;
  const found = await registry.lookupRegistryEntry('io.acme/atlas');

  assert.ok(found, 'the index holds this id, so it resolves');
  assert.equal(found.id, 'io.acme/atlas');
  assert.equal(found.source, 'official');
  assert.deepEqual(found.install, { type: 'stdio', command: 'npx', args: ['-y', '@acme/atlas@1.0.0'] });
  assert.deepEqual(requests, [{ path: '/v0/servers', query: 'io.acme/atlas' }]);
});

test('a smithery id is looked up by its qualified name and keeps its smithery prefix', async () => {
  requests.length = 0;
  const found = await registry.lookupRegistryEntry('smithery:acme/atlas');

  assert.ok(found);
  assert.equal(found.id, 'smithery:acme/atlas');
  assert.equal(found.source, 'smithery');
  assert.equal(found.install?.url, 'https://server.smithery.ai/acme/atlas/mcp');
  assert.deepEqual(requests, [{ path: '/servers', query: 'acme/atlas' }]);
});

test('an index row whose id differs from the one asked for is not a match', async () => {
  assert.equal(await registry.lookupRegistryEntry('io.acme/neighbour'), null);
});

test('an id no index holds resolves to null', async () => {
  assert.equal(await registry.lookupRegistryEntry('io.acme/missing'), null);
});

test('an index that answers an error resolves to null rather than throwing', async () => {
  assert.equal(await registry.lookupRegistryEntry('io.acme/broken'), null);
});

test('an index that never answers resolves to null within the lookup timeout', async () => {
  const started = Date.now();
  assert.equal(await registry.lookupRegistryEntry('io.acme/slow', 100), null);
  assert.ok(Date.now() - started < 2_000, 'the lookup gave up at its timeout, not the 12-second fetch timeout');
});

test('an empty id resolves to null without asking any index', async () => {
  requests.length = 0;
  assert.equal(await registry.lookupRegistryEntry(''), null);
  assert.equal(await registry.lookupRegistryEntry('smithery:'), null);
  assert.deepEqual(requests, []);
});

test('a pick whose lookup fails is held as a Partial row with the digest of nothing', async () => {
  const store = new InboxStore(join(scratch, 'partial', 'inbox.json'));
  const resolved = await registry.lookupRegistryEntry('io.acme/broken');

  assert.equal(store.add(row('io.acme/broken', resolved)), 'waiting');
  const [held] = store.rows();
  assert.equal(held.resolved, null);
  assert.equal(held.state, 'waiting');
  assert.equal(held.reviewDigest, reviewDigestOf(null));
});

test('a pick whose lookup finds its entry is held resolved, with the digest of that entry', async () => {
  const store = new InboxStore(join(scratch, 'found', 'inbox.json'));
  const resolved = await registry.lookupRegistryEntry('io.acme/atlas');

  store.add(row('io.acme/atlas', resolved));
  const [held] = store.rows();
  assert.equal(held.resolved?.id, 'io.acme/atlas');
  assert.equal(held.reviewDigest, reviewDigestOf(resolved));
});
