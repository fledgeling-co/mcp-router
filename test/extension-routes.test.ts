import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { IncomingMessage, ServerResponse } from 'node:http';
import type { ControlDeps } from '../src/control.js';
import type { UpstreamConfig } from '../src/config.js';
import { ExtensionStore } from '../src/extensions.js';

/*
 * The /extensions family, through handleControl. Ported from ControlExtensionRoutesTests.
 *
 * The router home is set before control.ts loads, because config.ts reads it at import. Without this,
 * a removal that succeeds would write into the operator's own home.
 */
const made: string[] = [];
after(() => {
  for (const d of made) rmSync(d, { recursive: true, force: true });
});

const home = mkdtempSync(join(tmpdir(), 'ext-routes-home-'));
made.push(home);
process.env.MCP_ROUTER_HOME = home;

const { handleControl } = await import('../src/control.js');

const TOKEN = 'test-token';

const SKILL_BODY = {
  name: 'alpha',
  files: [{ path: 'SKILL.md', text: '---\nname: alpha\ndescription: a test skill\n---\n' }],
};

const UPSTREAMS = new Map<string, UpstreamConfig>([
  ['alpha-server', { name: 'alpha-server', transport: 'stdio', command: 'x', args: [] } as unknown as UpstreamConfig],
  ['beta-server', { name: 'beta-server', transport: 'http', url: 'http://127.0.0.1:1' } as unknown as UpstreamConfig],
]);

/** A store under its own scratch directory, so no test sees another test's entries. */
function scratchStore(): ExtensionStore {
  const parent = mkdtempSync(join(tmpdir(), 'ext-routes-'));
  made.push(parent);
  return new ExtensionStore(join(parent, 'extensions'), () => 1000);
}

interface Call {
  method: string;
  path: string;
  body?: unknown;
  token?: boolean;
  json?: boolean;
}

/** Drive one request through handleControl and capture what it answered. */
async function answer(call: Call, deps: Partial<ControlDeps>): Promise<{ status: number; text: string; json: unknown }> {
  const headers: Record<string, string> = {};
  if (call.json !== false) headers['content-type'] = 'application/json';
  if (call.token !== false) headers['x-mcpr-token'] = TOKEN;
  const req = { method: call.method, headers } as unknown as IncomingMessage;

  let status = 0;
  let text = '';
  const res = {
    writeHead(code: number) {
      status = code;
    },
    end(payload: string) {
      text = payload;
    },
  } as unknown as ServerResponse;

  const url = new URL(call.path, 'http://127.0.0.1:8879');
  const handled = await handleControl(
    req,
    res,
    url,
    call.body,
    { upstreams: UPSTREAMS, ...deps } as unknown as ControlDeps,
    TOKEN
  );
  assert.equal(handled, true, `${call.method} ${call.path} was not claimed by the control API`);
  return { status, text, json: text ? JSON.parse(text) : undefined };
}

test('R1 — a kind is added, listed, read and removed over the routes', async () => {
  const store = scratchStore();
  const deps = { extensions: store };

  const added = await answer({ method: 'POST', path: '/extensions/skills', body: SKILL_BODY }, deps);
  assert.equal(added.status, 201);
  assert.deepEqual(added.json, { added: 'alpha', kind: 'skills', files: 1, bytes: 46 });

  const listed = await answer({ method: 'GET', path: '/extensions/skills' }, deps);
  assert.equal(listed.status, 200);
  const listing = listed.json as { count: number; entries: Array<Record<string, unknown>> };
  assert.equal(listing.count, 1);
  assert.equal(listing.entries[0].name, 'alpha');
  assert.equal(listing.entries[0].description, 'a test skill');
  assert.equal(listing.entries[0].problem, null);

  const one = await answer({ method: 'GET', path: '/extensions/skills/alpha' }, deps);
  assert.equal(one.status, 200);
  assert.equal((one.json as { title: string }).title, 'alpha');

  const removed = await answer({ method: 'DELETE', path: '/extensions/skills/alpha' }, deps);
  assert.equal(removed.status, 200);
  const body = removed.json as { removed: string; restorePath: string };
  assert.equal(body.removed, 'alpha');
  assert.ok(existsSync(join(body.restorePath, 'SKILL.md')), 'the removed bytes must be where restorePath says');

  const empty = await answer({ method: 'GET', path: '/extensions/skills' }, deps);
  assert.equal((empty.json as { count: number }).count, 0);
  // The staging area outlives an add; what must never survive is an entry inside it.
  assert.equal(existsSync(join(store.root, '.staging', 'skills-alpha-1000')), false);
});

test('R2 — one request answers all four counts, with a count for each kind', async () => {
  const deps = { extensions: scratchStore() };
  await answer({ method: 'POST', path: '/extensions/skills', body: SKILL_BODY }, deps);

  const inventory = await answer({ method: 'GET', path: '/extensions' }, deps);
  assert.equal(inventory.status, 200);
  assert.equal(
    inventory.text.startsWith('{"counts":{"servers":2,"skills":1,"plugins":0,"marketplaces":0}'),
    true,
    inventory.text.slice(0, 120)
  );
  for (const kind of ['skills', 'plugins', 'marketplaces']) {
    assert.ok(inventory.text.includes(`"kind":"${kind}"`), `inventory must carry a ${kind} listing`);
  }
});

test('R3 — a malformed add is refused with its reason and registers nothing', async () => {
  const deps = { extensions: scratchStore() };

  const noFrontmatter = await answer(
    { method: 'POST', path: '/extensions/skills', body: { name: 'alpha', files: [{ path: 'SKILL.md', text: 'no frontmatter' }] } },
    deps
  );
  assert.equal(noFrontmatter.status, 400);
  assert.equal((noFrontmatter.json as { reason: string }).reason, 'malformedDescriptor');

  const escape = await answer(
    { method: 'POST', path: '/extensions/skills', body: { name: 'alpha', files: [{ path: '../out.md', text: 'x' }] } },
    deps
  );
  assert.equal(escape.status, 400);
  assert.equal((escape.json as { reason: string }).reason, 'invalidFilePath');

  // Half-registered is what the ordering exists to prevent: after two refusals the collection is empty.
  const listed = await answer({ method: 'GET', path: '/extensions/skills' }, deps);
  assert.equal((listed.json as { count: number }).count, 0);
});

test('R4 — a body with no name, and one with no files, are each refused', async () => {
  const deps = { extensions: scratchStore() };

  const noName = await answer({ method: 'POST', path: '/extensions/skills', body: { files: [] } }, deps);
  assert.equal(noName.status, 400);
  assert.equal(noName.text, '{"error":"name is required"}');

  const noFiles = await answer({ method: 'POST', path: '/extensions/skills', body: { name: 'alpha' } }, deps);
  assert.equal(noFiles.status, 400);
  assert.equal(noFiles.text, '{"error":"files is required, as an array of {path, text}"}');
});

test('R5 — an unknown kind is 404, an unknown entry is 404 in the route\'s own words', async () => {
  const deps = { extensions: scratchStore() };

  const kind = await answer({ method: 'GET', path: '/extensions/widgets' }, deps);
  assert.equal(kind.status, 404);
  assert.equal(kind.text, '{"error":"no extension kind named \\"widgets\\""}');

  const entry = await answer({ method: 'GET', path: '/extensions/plugins/ghost' }, deps);
  assert.equal(entry.status, 404);
  assert.equal(entry.text, '{"error":"no plugin named \\"ghost\\""}');

  const removal = await answer({ method: 'DELETE', path: '/extensions/plugins/ghost' }, deps);
  assert.equal(removal.status, 404);
  assert.equal((removal.json as { reason: string }).reason, 'unknown');
});

test('R6 — a method the family does not serve is 405, not 404', async () => {
  const deps = { extensions: scratchStore() };

  const patched = await answer({ method: 'PATCH', path: '/extensions/skills', body: {} }, deps);
  assert.equal(patched.status, 405);
  const deeper = await answer({ method: 'GET', path: '/extensions/skills/alpha/extra' }, deps);
  assert.equal(deeper.status, 405);
});

test('R7 — every /extensions route needs the token, GET included, and a mutation needs JSON', async () => {
  const store = scratchStore();
  const deps = { extensions: store };
  await answer({ method: 'POST', path: '/extensions/skills', body: SKILL_BODY }, deps);

  const untokenedPost = await answer(
    { method: 'POST', path: '/extensions/skills', body: SKILL_BODY, token: false },
    deps
  );
  assert.equal(untokenedPost.status, 401);

  const untokenedGet = await answer({ method: 'GET', path: '/extensions/skills', token: false }, deps);
  assert.equal(untokenedGet.status, 401);
  const untokenedInventory = await answer({ method: 'GET', path: '/extensions', token: false }, deps);
  assert.equal(untokenedInventory.status, 401);

  const untypedPost = await answer(
    { method: 'POST', path: '/extensions/skills', body: SKILL_BODY, json: false },
    deps
  );
  assert.equal(untypedPost.status, 415);

  // Neither refused call changed the store.
  const listed = await answer({ method: 'GET', path: '/extensions/skills' }, deps);
  assert.equal((listed.json as { count: number }).count, 1);
});

test('R8 — with no store the family says so rather than answering an empty inventory', async () => {
  for (const path of ['/extensions', '/extensions/skills', '/extensions/skills/alpha']) {
    const response = await answer({ method: 'GET', path }, { extensions: undefined });
    assert.equal(response.status, 503);
    assert.match(response.text, /extension storage is unavailable/);
  }
});

test('R9 — a name arrives percent-decoded, and a malformed escape is 400', async () => {
  const deps = { extensions: scratchStore() };
  await answer({ method: 'POST', path: '/extensions/skills', body: SKILL_BODY }, deps);

  const encoded = await answer({ method: 'GET', path: '/extensions/skills/%61lpha' }, deps);
  assert.equal(encoded.status, 200);
  assert.equal((encoded.json as { name: string }).name, 'alpha');

  const malformed = await answer({ method: 'GET', path: '/extensions/skills/%ZZ' }, deps);
  assert.equal(malformed.status, 400);
  assert.equal(malformed.text, '{"error":"URI malformed"}');
});

// F6: GET /extensions/updates is claimed before the :kind parse, so `updates` is never read as a kind.

test('R10 — /extensions/updates answers the report, and /extensions/nonsense still refuses as a kind', async () => {
  const deps = { extensions: scratchStore() };
  await answer({ method: 'POST', path: '/extensions/skills', body: SKILL_BODY }, deps);

  const updates = await answer({ method: 'GET', path: '/extensions/updates' }, deps);
  assert.equal(updates.status, 200);
  const report = updates.json as { summary: { total: number }; entries: Array<{ name: string }> };
  assert.equal(report.summary.total, 1);
  assert.equal(report.entries[0].name, 'alpha');
  assert.doesNotMatch(updates.text, /no extension kind named/);

  const nonsense = await answer({ method: 'GET', path: '/extensions/nonsense' }, deps);
  assert.equal(nonsense.status, 404);
  assert.match(nonsense.text, /no extension kind named \\"nonsense\\"/);
});

test('R11 — /extensions/updates needs the token, as every /extensions route does', async () => {
  const deps = { extensions: scratchStore() };
  const untokened = await answer({ method: 'GET', path: '/extensions/updates', token: false }, deps);
  assert.equal(untokened.status, 401);
});

test('R12 — a mutating verb on /extensions/updates is 405 and changes nothing', async () => {
  const store = scratchStore();
  const deps = { extensions: store };
  await answer({ method: 'POST', path: '/extensions/skills', body: SKILL_BODY }, deps);

  for (const method of ['POST', 'DELETE']) {
    const answered = await answer({ method, path: '/extensions/updates', body: {} }, deps);
    assert.equal(answered.status, 405, `${method} must be 405, not 404`);
  }
  const listed = await answer({ method: 'GET', path: '/extensions/skills' }, deps);
  assert.equal((listed.json as { count: number }).count, 1);
});

test('R13 — kind narrows the rows, name asks about one entry, and a bad window or kind is refused', async () => {
  const deps = { extensions: scratchStore() };
  await answer({ method: 'POST', path: '/extensions/skills', body: SKILL_BODY }, deps);

  const narrowed = await answer({ method: 'GET', path: '/extensions/updates?kind=plugins' }, deps);
  assert.equal(narrowed.status, 200);
  assert.equal((narrowed.json as { summary: { total: number } }).summary.total, 0);

  const named = await answer({ method: 'GET', path: '/extensions/updates?name=alpha' }, deps);
  assert.equal((named.json as { summary: { total: number } }).summary.total, 1);

  const kind = await answer({ method: 'GET', path: '/extensions/updates?kind=widgets' }, deps);
  assert.equal(kind.status, 404);
  assert.match(kind.text, /no extension kind named \\"widgets\\"/);

  const window = await answer({ method: 'GET', path: '/extensions/updates?staleAfterMs=1h' }, deps);
  assert.equal(window.status, 400, 'an unreadable window is asked about, not silently defaulted');

  const defaulted = await answer({ method: 'GET', path: '/extensions/updates' }, deps);
  assert.equal((defaulted.json as { staleAfterMs: number }).staleAfterMs, 86_400_000);
});

test('R14 — with no store /extensions/updates says the capability is missing, not that nothing is stale', async () => {
  const response = await answer({ method: 'GET', path: '/extensions/updates' }, { extensions: undefined });
  assert.equal(response.status, 503);
  assert.match(response.text, /extension storage is unavailable/);
});
