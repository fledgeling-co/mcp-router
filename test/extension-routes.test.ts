import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
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

/*
 * P2, promote-with-undo and keep. Ported from the undo path in ExtensionIngestUndo.swift: a promotion moves
 * the replaced entry aside rather than deleting it, and an undo refuses rather than overwrite a version that
 * is no longer the one the promotion installed.
 *
 * Each test gets a clock that advances one millisecond per stamp. Under the fixed clock above, a promote and
 * the undo that follows it would share a restore path, and the collision would be a test artefact.
 */
function ticking(): { store: ExtensionStore; root: string } {
  const parent = mkdtempSync(join(tmpdir(), 'ext-promote-'));
  made.push(parent);
  const root = join(parent, 'extensions');
  let now = 1000;
  return { store: new ExtensionStore(root, () => now++), root };
}

/** A skill whose descriptor declares the version it is at, which is what a promotion checks. */
function skillAt(version: string, name = 'alpha'): Array<{ path: string; text: string }> {
  return [{ path: 'SKILL.md', text: `---\nname: ${name}\ndescription: a test skill\nversion: ${version}\n---\n` }];
}

async function installAlpha(deps: Partial<ControlDeps>, version: string): Promise<void> {
  const added = await answer({ method: 'POST', path: '/extensions/skills', body: { name: 'alpha', files: skillAt(version) } }, deps);
  assert.equal(added.status, 201);
}

test('P2 — a promotion replaces the installed version and keeps the one it replaced as a restore copy', async () => {
  const { store, root } = ticking();
  const deps = { extensions: store };
  await installAlpha(deps, '1.0.0');

  const promoted = await answer(
    { method: 'POST', path: '/extensions/skills/alpha/promote', body: { pluginVersion: '2.0.0', files: skillAt('2.0.0') } },
    deps
  );
  assert.equal(promoted.status, 200);
  const body = promoted.json as Record<string, unknown>;
  assert.equal(body.promoted, 'alpha');
  assert.equal(body.kind, 'skills');
  assert.equal(body.pluginVersion, '2.0.0');
  assert.equal(body.replaced, '1.0.0');
  assert.equal(body.files, 1);
  assert.equal(body.bytes, Buffer.byteLength(skillAt('2.0.0')[0].text));
  assert.equal(typeof body.restore, 'string');

  const now = await answer({ method: 'GET', path: '/extensions/skills/alpha' }, deps);
  assert.equal((now.json as { version: string }).version, '2.0.0');

  const copy = readFileSync(join(root, '.removed', 'skills', 'alpha', body.restore as string, 'SKILL.md'), 'utf8');
  assert.match(copy, /version: 1\.0\.0/);
});

test('P2 — an undo puts the replaced version back, and the promoted one is moved aside, not deleted', async () => {
  const { store, root } = ticking();
  const deps = { extensions: store };
  await installAlpha(deps, '1.0.0');
  const promoted = await answer(
    { method: 'POST', path: '/extensions/skills/alpha/promote', body: { pluginVersion: '2.0.0', files: skillAt('2.0.0') } },
    deps
  );
  const restore = (promoted.json as { restore: string }).restore;

  const undone = await answer({ method: 'POST', path: '/extensions/skills/alpha/undo-promote', body: { restore } }, deps);
  assert.equal(undone.status, 200);
  assert.deepEqual(undone.json, { restored: 'alpha', kind: 'skills', version: '1.0.0', withdrawn: '2.0.0' });

  const now = await answer({ method: 'GET', path: '/extensions/skills/alpha' }, deps);
  assert.equal((now.json as { version: string }).version, '1.0.0');

  // Two copies sit in the restore area afterwards: the one the undo brought back is gone from it, and the
  // promoted copy has taken its place beside the entry's history. Nothing was deleted.
  assert.equal(readdirSync(join(root, '.removed', 'skills', 'alpha')).length, 1);
  assert.equal(existsSync(join(root, '.removed', 'skills', 'alpha', restore)), false);
});

test('P2 — an undo is refused when the installed version is no longer the one the promotion installed', async () => {
  const { store } = ticking();
  const deps = { extensions: store };
  await installAlpha(deps, '1.0.0');
  const first = await answer(
    { method: 'POST', path: '/extensions/skills/alpha/promote', body: { pluginVersion: '2.0.0', files: skillAt('2.0.0') } },
    deps
  );
  await answer(
    { method: 'POST', path: '/extensions/skills/alpha/promote', body: { pluginVersion: '3.0.0', files: skillAt('3.0.0') } },
    deps
  );

  // Undoing the first promotion now would overwrite 3.0.0 with the 1.0.0 it replaced.
  const refused = await answer(
    { method: 'POST', path: '/extensions/skills/alpha/undo-promote', body: { restore: (first.json as { restore: string }).restore } },
    deps
  );
  assert.equal(refused.status, 409);
  assert.equal((refused.json as { reason: string }).reason, 'installedChanged');

  const now = await answer({ method: 'GET', path: '/extensions/skills/alpha' }, deps);
  assert.equal((now.json as { version: string }).version, '3.0.0');
});

test('P2 — a promotion cannot be undone twice', async () => {
  const { store } = ticking();
  const deps = { extensions: store };
  await installAlpha(deps, '1.0.0');
  const promoted = await answer(
    { method: 'POST', path: '/extensions/skills/alpha/promote', body: { pluginVersion: '2.0.0', files: skillAt('2.0.0') } },
    deps
  );
  const body = { restore: (promoted.json as { restore: string }).restore };
  assert.equal((await answer({ method: 'POST', path: '/extensions/skills/alpha/undo-promote', body }, deps)).status, 200);

  const again = await answer({ method: 'POST', path: '/extensions/skills/alpha/undo-promote', body }, deps);
  assert.equal(again.status, 409);
  assert.equal((again.json as { reason: string }).reason, 'alreadyUndone');
});

test('P2 — an undo names no promotion that exists, and a malformed stamp is refused as malformed', async () => {
  const { store } = ticking();
  const deps = { extensions: store };
  await installAlpha(deps, '1.0.0');

  const absent = await answer({ method: 'POST', path: '/extensions/skills/alpha/undo-promote', body: { restore: '999' } }, deps);
  assert.equal(absent.status, 404);
  assert.equal((absent.json as { reason: string }).reason, 'unknown');

  const malformed = await answer(
    { method: 'POST', path: '/extensions/skills/alpha/undo-promote', body: { restore: '../../etc' } },
    deps
  );
  assert.equal(malformed.status, 400);
  assert.equal((malformed.json as { reason: string }).reason, 'invalidRestore');

  const missing = await answer({ method: 'POST', path: '/extensions/skills/alpha/undo-promote', body: {} }, deps);
  assert.equal(missing.status, 400);
});

test('P2 — a promotion of an entry the router does not hold is 404 and writes nothing', async () => {
  const { store, root } = ticking();
  const deps = { extensions: store };
  const promoted = await answer(
    { method: 'POST', path: '/extensions/skills/ghost/promote', body: { pluginVersion: '2.0.0', files: skillAt('2.0.0', 'ghost') } },
    deps
  );
  assert.equal(promoted.status, 404);
  assert.equal((promoted.json as { error: string }).error, 'no skill named "ghost"');
  assert.equal(existsSync(join(root, 'skills', 'ghost')), false);
  assert.equal(existsSync(join(root, '.promotions')), false);
});

test('P2 — a promotion whose files name another entry, or another version, is refused before anything is written', async () => {
  const { store, root } = ticking();
  const deps = { extensions: store };
  await installAlpha(deps, '1.0.0');

  const wrongVersion = await answer(
    { method: 'POST', path: '/extensions/skills/alpha/promote', body: { pluginVersion: '3.0.0', files: skillAt('2.0.0') } },
    deps
  );
  assert.equal(wrongVersion.status, 400);
  assert.equal((wrongVersion.json as { reason: string }).reason, 'versionMismatch');

  const wrongName = await answer(
    { method: 'POST', path: '/extensions/skills/alpha/promote', body: { pluginVersion: '2.0.0', files: skillAt('2.0.0', 'beta') } },
    deps
  );
  assert.equal(wrongName.status, 400);
  assert.equal((wrongName.json as { reason: string }).reason, 'nameMismatch');

  const now = await answer({ method: 'GET', path: '/extensions/skills/alpha' }, deps);
  assert.equal((now.json as { version: string }).version, '1.0.0');
  assert.equal(existsSync(join(root, '.removed')), false);
  assert.equal(existsSync(join(root, '.promotions')), false);
});

test('P2 — promoting the version already installed is refused as a conflict', async () => {
  const { store } = ticking();
  const deps = { extensions: store };
  await installAlpha(deps, '1.0.0');
  const same = await answer(
    { method: 'POST', path: '/extensions/skills/alpha/promote', body: { pluginVersion: '1.0.0', files: skillAt('1.0.0') } },
    deps
  );
  assert.equal(same.status, 409);
  assert.equal((same.json as { reason: string }).reason, 'sameVersion');
});

test('P2 — a promotion that cannot move the entry aside answers 500 and leaves the installed version as it was', async () => {
  const { store, root } = ticking();
  const deps = { extensions: store };
  await installAlpha(deps, '1.0.0');
  // A file where the restore area must be a directory makes the move aside impossible.
  writeFileSync(join(root, '.removed'), 'not a directory');

  const failed = await answer(
    { method: 'POST', path: '/extensions/skills/alpha/promote', body: { pluginVersion: '2.0.0', files: skillAt('2.0.0') } },
    deps
  );
  assert.equal(failed.status, 500);
  assert.equal((failed.json as { reason: string }).reason, 'writeFailed');

  const now = await answer({ method: 'GET', path: '/extensions/skills/alpha' }, deps);
  assert.equal((now.json as { version: string }).version, '1.0.0');
  const manifests = existsSync(join(root, '.promotions', 'skills', 'alpha'))
    ? readdirSync(join(root, '.promotions', 'skills', 'alpha'))
    : [];
  assert.deepEqual(manifests, []);
});

test('P2 — keep records the version held for a plugin, without the router holding the plugin', async () => {
  const { store, root } = ticking();
  const deps = { extensions: store };

  const kept = await answer(
    { method: 'POST', path: '/extensions/plugins/demo@market/keep', body: { pluginVersion: '2.0.0' } },
    deps
  );
  assert.equal(kept.status, 200);
  assert.deepEqual(kept.json, { kept: 'demo@market', kind: 'plugins', pluginVersion: '2.0.0' });

  const recorded = JSON.parse(readFileSync(join(root, '.kept', 'plugins', 'demo@market.json'), 'utf8')) as {
    pluginVersion: string;
  };
  assert.equal(recorded.pluginVersion, '2.0.0');
  // Keep is a decision about a held version, not a write to the store: nothing was listed as an entry.
  assert.equal(existsSync(join(root, 'plugins')), false);
});

test('P2 — keep is refused without a version, and for a name the store could not hold', async () => {
  const { store, root } = ticking();
  const deps = { extensions: store };

  const missing = await answer({ method: 'POST', path: '/extensions/plugins/demo@market/keep', body: {} }, deps);
  assert.equal(missing.status, 400);
  assert.equal(missing.text, '{"error":"pluginVersion is required"}');

  const hidden = await answer({ method: 'POST', path: '/extensions/plugins/.hidden/keep', body: { pluginVersion: '2.0.0' } }, deps);
  assert.equal(hidden.status, 400);
  assert.equal((hidden.json as { reason: string }).reason, 'invalidName');
  assert.equal(existsSync(join(root, '.kept')), false);
});

test('P2 — the promote, keep and undo writes all need the token', async () => {
  const { store, root } = ticking();
  const deps = { extensions: store };
  await installAlpha(deps, '1.0.0');

  const keep = await answer(
    { method: 'POST', path: '/extensions/plugins/demo@market/keep', body: { pluginVersion: '2.0.0' }, token: false },
    deps
  );
  assert.equal(keep.status, 401);
  const promote = await answer(
    { method: 'POST', path: '/extensions/skills/alpha/promote', body: { pluginVersion: '2.0.0', files: skillAt('2.0.0') }, token: false },
    deps
  );
  assert.equal(promote.status, 401);
  const undo = await answer(
    { method: 'POST', path: '/extensions/skills/alpha/undo-promote', body: { restore: '1000' }, token: false },
    deps
  );
  assert.equal(undo.status, 401);

  assert.equal(existsSync(join(root, '.kept')), false);
  const now = await answer({ method: 'GET', path: '/extensions/skills/alpha' }, deps);
  assert.equal((now.json as { version: string }).version, '1.0.0');
});

test('P2 — a deeper path, or a method the write does not serve, is 405 and not silently claimed', async () => {
  const { store } = ticking();
  const deps = { extensions: store };
  await installAlpha(deps, '1.0.0');

  const unknownAction = await answer({ method: 'POST', path: '/extensions/skills/alpha/nonsense', body: {} }, deps);
  assert.equal(unknownAction.status, 405);
  const getPromote = await answer({ method: 'GET', path: '/extensions/skills/alpha/promote' }, deps);
  assert.equal(getPromote.status, 405);
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
