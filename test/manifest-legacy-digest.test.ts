import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildManifest, toolsDigest, type Manifest } from '../src/manifest.js';
import { upstreamHash, type UpstreamConfig } from '../src/config.js';
import type { UpstreamPool } from '../src/pool.js';
import type { Tool } from '@modelcontextprotocol/sdk/types.js';

const upstream: UpstreamConfig = { name: 'fixture', transport: 'http', url: 'http://127.0.0.1:9/mcp', headers: {} };
const approved: Tool[] = [{ name: 'read', description: 'Read a fixture', inputSchema: { type: 'object' } }];
async function observe(manifest: Manifest, tools: Tool[]) {
  const pool = { async acquire() { return { client: { async listTools() { return { tools }; } } }; } } as unknown as UpstreamPool;
  await buildManifest([upstream], pool, manifest, { force: true, commit: apply => apply(manifest) });
  return manifest.servers.fixture;
}
function legacy(tools = approved): Manifest {
  return { version: 1, servers: { fixture: { hash: upstreamHash(upstream), builtAt: '2026-10-18', tools, digest: 'legacy-surface-hash' } } };
}

test('digest algorithm changes do not quarantine an unchanged complete approved surface', async () => {
  const row = await observe(legacy(), structuredClone(approved));
  assert.equal(row.pending, undefined);
  assert.equal(row.digest, toolsDigest(approved));
  assert.deepEqual(row.tools, approved);
});

test('a legacy digest never bypasses a changed annotation or an unavailable approved surface', async () => {
  const changed: Tool[] = [{ ...approved[0], annotations: { destructiveHint: true } }];
  const held = await observe(legacy(), changed);
  assert.deepEqual(held.tools, approved);
  assert.deepEqual(held.pending?.tools, changed);
  const unavailable = legacy([]);
  unavailable.servers.fixture.error = 'previous startup failed';
  const recovered = await observe(unavailable, approved);
  assert.deepEqual(recovered.tools, [], 'missing approved bytes cannot be guessed from a legacy digest');
  assert.deepEqual(recovered.pending?.tools, approved, 'one explicit review is required after legacy error recovery');
});
