import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import type { IncomingMessage, ServerResponse } from 'node:http';
import type { ControlDeps } from '../src/control.js';
import type { UpstreamConfig } from '../src/config.js';
import { ExtensionStore } from '../src/extensions.js';

/*
 * Promotion from Claude's plugin cache, and the changelog the update check reads from it, through handleControl.
 *
 * The cache is read-only and confined to `<claudeHome>/plugins/cache`: a symlink that resolves outside it is
 * refused, and nothing outside it is read. The router home is set before control.ts loads, because config.ts reads
 * it at import, so a promotion that succeeds cannot write into the operator's own home.
 */
const made: string[] = [];
after(() => {
  for (const d of made) rmSync(d, { recursive: true, force: true });
});

const home = mkdtempSync(join(tmpdir(), 'plugin-cache-home-'));
made.push(home);
process.env.MCP_ROUTER_HOME = home;

const { handleControl } = await import('../src/control.js');

const TOKEN = 'test-token';
const UPSTREAMS = new Map<string, UpstreamConfig>();
const CHANGELOG = '## 2.0.0\n- new things\n';

function scratch(): string {
  const parent = realpathSync(mkdtempSync(join(tmpdir(), 'plugin-cache-')));
  made.push(parent);
  return parent;
}

function write(path: string, text: string): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, text, 'utf8');
}

function manifest(name: string, version: string): string {
  return JSON.stringify({ name, version });
}

/** A Claude home with `demo` cached at 2.0.0 (with a changelog) and the marketplace `market` offering 2.0.0. */
function claudeHome(): string {
  const claude = join(scratch(), '.claude');
  const version = join(claude, 'plugins', 'cache', 'market', 'demo', '2.0.0');
  write(join(version, '.claude-plugin', 'plugin.json'), manifest('demo', '2.0.0'));
  write(join(version, 'skills', 'alpha', 'SKILL.md'), '---\nname: alpha\ndescription: a plugin skill\n---\n');
  write(join(version, 'CHANGELOG.md'), CHANGELOG);
  return claude;
}

/** A store holding `demo@market` at 1.0.0, and the `market` catalogue offering `offered` (default 2.0.0). */
function storeAt(offered = '2.0.0', installed = '1.0.0'): ExtensionStore {
  // A clock that moves on every stamp: a promotion and its undo must not share a restore directory.
  let tick = 1000;
  const store = new ExtensionStore(join(scratch(), 'extensions'), () => (tick += 1));
  const added = store.add('plugins', 'demo@market', [
    { path: '.claude-plugin/plugin.json', text: manifest('demo@market', installed) },
  ]);
  assert.equal(added.outcome, 'added');
  const market = store.add('marketplaces', 'market', [
    {
      path: '.claude-plugin/marketplace.json',
      text: JSON.stringify({ name: 'market', plugins: [{ name: 'demo', version: offered }] }),
    },
  ]);
  assert.equal(market.outcome, 'added');
  return store;
}

interface Call {
  method: string;
  path: string;
  body?: unknown;
}

/** Drive one request through handleControl and capture what it answered. */
async function answer(call: Call, deps: Partial<ControlDeps>): Promise<{ status: number; json: Record<string, unknown> }> {
  const headers: Record<string, string> = { 'content-type': 'application/json', 'x-mcpr-token': TOKEN };
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
  return { status, json: text ? JSON.parse(text) : {} };
}

const PROMOTE = '/extensions/plugins/demo%40market/promote';

function installedVersion(store: ExtensionStore): string | null {
  return store.read('plugins', 'demo@market')?.version ?? null;
}

test('C1 — promote from the cache installs the cached version and keeps the copy it replaced', async () => {
  const store = storeAt();
  const deps = { extensions: store, claudeHome: claudeHome() };

  const promoted = await answer({ method: 'POST', path: PROMOTE, body: { source: 'cache', pluginVersion: '2.0.0' } }, deps);

  assert.equal(promoted.status, 200, JSON.stringify(promoted.json));
  assert.equal(promoted.json.promoted, 'demo@market');
  assert.equal(promoted.json.pluginVersion, '2.0.0');
  assert.equal(promoted.json.replaced, '1.0.0');
  assert.match(String(promoted.json.restore), /^[0-9]+$/, 'the restore reference is the stamp the replaced copy was moved under');
  assert.equal(installedVersion(store), '2.0.0');
  assert.equal(promoted.json.files, 3, 'the cached copy carries its manifest, its skill and its changelog');
});

test('C2 — an undo of a cache promotion puts the replaced version back', async () => {
  const store = storeAt();
  const deps = { extensions: store, claudeHome: claudeHome() };
  const promoted = await answer({ method: 'POST', path: PROMOTE, body: { source: 'cache', pluginVersion: '2.0.0' } }, deps);
  assert.equal(promoted.status, 200);

  const undone = await answer(
    { method: 'POST', path: '/extensions/plugins/demo%40market/undo-promote', body: { restore: promoted.json.restore } },
    deps
  );

  assert.equal(undone.status, 200, JSON.stringify(undone.json));
  assert.equal(undone.json.version, '1.0.0');
  assert.equal(installedVersion(store), '1.0.0');
});

test('C3 — the body form still promotes from the files it is sent', async () => {
  const store = storeAt();
  const files = [{ path: '.claude-plugin/plugin.json', text: manifest('demo@market', '2.0.0') }];

  const promoted = await answer({ method: 'POST', path: PROMOTE, body: { pluginVersion: '2.0.0', files } }, { extensions: store });

  assert.equal(promoted.status, 200, JSON.stringify(promoted.json));
  assert.equal(installedVersion(store), '2.0.0');
});

test('C4 — a cached copy reached through a symlink to a file outside the cache is refused, and nothing moves', async () => {
  const store = storeAt();
  const claude = claudeHome();
  const secret = join(scratch(), 'outside.md');
  write(secret, 'not part of the plugin');
  symlinkSync(secret, join(claude, 'plugins', 'cache', 'market', 'demo', '2.0.0', 'skills', 'leak.md'));

  const refused = await answer({ method: 'POST', path: PROMOTE, body: { source: 'cache', pluginVersion: '2.0.0' } }, { extensions: store, claudeHome: claude });

  assert.equal(refused.status, 403);
  assert.equal(refused.json.reason, 'outsideCache');
  assert.equal(installedVersion(store), '1.0.0', 'a refused promotion leaves the installed version as it was');
});

test('C5 — a cached version directory that is a symlink outside the cache is refused', async () => {
  const store = storeAt('3.0.0');
  const claude = claudeHome();
  const elsewhere = join(scratch(), 'elsewhere', '3.0.0');
  write(join(elsewhere, '.claude-plugin', 'plugin.json'), manifest('demo', '3.0.0'));
  symlinkSync(elsewhere, join(claude, 'plugins', 'cache', 'market', 'demo', '3.0.0'));

  const refused = await answer({ method: 'POST', path: PROMOTE, body: { source: 'cache', pluginVersion: '3.0.0' } }, { extensions: store, claudeHome: claude });

  assert.equal(refused.status, 403);
  assert.equal(refused.json.reason, 'outsideCache');
  assert.equal(installedVersion(store), '1.0.0');
});

test('C6 — a version the cache does not hold is a 404 that names the reason', async () => {
  const store = storeAt();

  const missing = await answer({ method: 'POST', path: PROMOTE, body: { source: 'cache', pluginVersion: '9.9.9' } }, { extensions: store, claudeHome: claudeHome() });

  assert.equal(missing.status, 404);
  assert.equal(missing.json.reason, 'noCachedVersion');
  assert.equal(installedVersion(store), '1.0.0');
});

test('C7 — a cache promotion is a 503 when the router has no Claude home to read the cache from, as GET /skills is', async () => {
  const store = storeAt();

  const unavailable = await answer({ method: 'POST', path: PROMOTE, body: { source: 'cache', pluginVersion: '2.0.0' } }, { extensions: store });

  assert.equal(unavailable.status, 503);
  assert.match(String(unavailable.json.error), /Claude home/);
  assert.equal(installedVersion(store), '1.0.0');
});

test('C8 — a source the router does not know is refused, and so is a cache promotion that also sends files', async () => {
  const store = storeAt();
  const deps = { extensions: store, claudeHome: claudeHome() };

  const unknown = await answer({ method: 'POST', path: PROMOTE, body: { source: 'network', pluginVersion: '2.0.0' } }, deps);
  assert.equal(unknown.status, 400);
  assert.match(String(unknown.json.error), /source/);

  const both = await answer(
    { method: 'POST', path: PROMOTE, body: { source: 'cache', pluginVersion: '2.0.0', files: [] } },
    deps
  );
  assert.equal(both.status, 400);
  assert.match(String(both.json.error), /files/);
  assert.equal(installedVersion(store), '1.0.0');
});

test('U1 — an update carries the changelog of the version it offers, read from the cache', async () => {
  const deps = { extensions: storeAt(), claudeHome: claudeHome() };

  const updates = await answer({ method: 'GET', path: '/extensions/updates?kind=plugins' }, deps);

  const entry = findEntry(updates.json, 'demo@market');
  assert.equal(entry.hasUpdate, true);
  assert.deepEqual(entry.changelog, { text: CHANGELOG, note: 'CHANGELOG.md from the cached 2.0.0 copy' });
});

test('U2 — an offered version with no CHANGELOG.md says none was published, and carries no text', async () => {
  const claude = claudeHome();
  rmSync(join(claude, 'plugins', 'cache', 'market', 'demo', '2.0.0', 'CHANGELOG.md'));

  const updates = await answer({ method: 'GET', path: '/extensions/updates?kind=plugins' }, { extensions: storeAt(), claudeHome: claude });

  const changelog = findEntry(updates.json, 'demo@market').changelog as { text: string | null; note: string };
  assert.equal(changelog.text, null);
  assert.match(changelog.note, /no changelog was published with 2\.0\.0/i);
});

test('U3 — a changelog over the document route cap is not sent, and the note says why', async () => {
  const claude = claudeHome();
  write(join(claude, 'plugins', 'cache', 'market', 'demo', '2.0.0', 'CHANGELOG.md'), 'x'.repeat(524_289));

  const updates = await answer({ method: 'GET', path: '/extensions/updates?kind=plugins' }, { extensions: storeAt(), claudeHome: claude });

  const changelog = findEntry(updates.json, 'demo@market').changelog as { text: string | null; note: string };
  assert.equal(changelog.text, null);
  assert.match(changelog.note, /over the 524288-byte cap/);
});

test('U4 — a changelog reached through a symlink outside the cache is not read', async () => {
  const claude = claudeHome();
  const secret = join(scratch(), 'secret-changelog.md');
  write(secret, 'not a changelog');
  const path = join(claude, 'plugins', 'cache', 'market', 'demo', '2.0.0', 'CHANGELOG.md');
  rmSync(path);
  symlinkSync(secret, path);

  const updates = await answer({ method: 'GET', path: '/extensions/updates?kind=plugins' }, { extensions: storeAt(), claudeHome: claude });

  const changelog = findEntry(updates.json, 'demo@market').changelog as { text: string | null; note: string };
  assert.equal(changelog.text, null);
  assert.match(changelog.note, /outside the plugin cache/);
});

test('U5 — an offered version the cache does not hold says so, rather than reporting a missing changelog', async () => {
  const updates = await answer(
    { method: 'GET', path: '/extensions/updates?kind=plugins' },
    { extensions: storeAt('4.0.0'), claudeHome: claudeHome() }
  );

  const changelog = findEntry(updates.json, 'demo@market').changelog as { text: string | null; note: string };
  assert.equal(changelog.text, null);
  assert.match(changelog.note, /holds no copy of 4\.0\.0/);
});

test('U6 — an entry with no update carries no changelog at all', async () => {
  const updates = await answer(
    { method: 'GET', path: '/extensions/updates?kind=plugins' },
    { extensions: storeAt('1.0.0'), claudeHome: claudeHome() }
  );

  const entry = findEntry(updates.json, 'demo@market');
  assert.equal(entry.hasUpdate, false);
  assert.equal(entry.changelog, null);
});

test('S1 — GET /skills says the router can promote from the cache, so the Mac can enable Promote', async () => {
  const claude = join(scratch(), '.claude');
  mkdirSync(claude, { recursive: true });

  const skills = await answer({ method: 'GET', path: '/skills' }, { extensions: storeAt(), claudeHome: claude });

  assert.equal(skills.status, 200);
  assert.equal(skills.json.promoteFromCache, true);
});

/** The one entry of the update check for `name`, failing the test rather than returning undefined. */
function findEntry(body: Record<string, unknown>, name: string): Record<string, unknown> & { changelog: unknown; hasUpdate: boolean } {
  const entries = body.entries as Array<Record<string, unknown>>;
  const entry = entries.find((candidate) => candidate.name === name);
  assert.ok(entry, `the update check holds no entry named ${name}: ${JSON.stringify(body)}`);
  return entry as Record<string, unknown> & { changelog: unknown; hasUpdate: boolean };
}
