import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { RegistryEntry } from '../src/registry.js';
import { INBOX_RETAIN_DECIDED, InboxStore, reviewDigestOf, declarationFor, type NewInboxRow } from '../src/inbox.js';

/*
 * The router's inbox store (planning/plans/plan-phone-inbox.md §2.1, §5, D10, D11). The store is a
 * file, so these run against a real file in a scratch directory: the properties under test are the
 * mode on disk, what survives a failed write, and what a second read finds.
 */
const made: string[] = [];
after(() => {
  for (const d of made) rmSync(d, { recursive: true, force: true });
});

/** A path inside a scratch directory that does not exist yet, so the store has to create it. */
function scratchPath(): string {
  const parent = mkdtempSync(join(tmpdir(), 'inbox-store-'));
  made.push(parent);
  return join(parent, 'nested', 'inbox.json');
}

function entry(name: string): RegistryEntry {
  return { id: `io.example/${name}`, name, displayName: `${name} server`, description: 'a test entry', source: 'official' };
}

function row(id: string, resolved: RegistryEntry | null = entry(id)): NewInboxRow {
  return {
    id,
    phoneId: 'phone-a',
    deviceName: "Luke's iPhone",
    queuedAt: '2026-10-19T10:00:00Z',
    receivedAt: '2026-10-19T10:00:05Z',
    resolved,
  };
}

const sha256 = (s: string) => createHash('sha256').update(s).digest('hex');

test('the file is written 0600, and its directory is created', () => {
  const path = scratchPath();
  const store = new InboxStore(path);
  assert.equal(store.add(row('alpha')), 'waiting');
  assert.equal(statSync(path).mode & 0o777, 0o600);
});

test('a second submit of the same id answers duplicate and keeps the first resolved entry', () => {
  const store = new InboxStore(scratchPath());
  store.add(row('alpha', entry('first')));
  const before = readFileSync(store.path, 'utf8');

  assert.equal(store.add(row('alpha', entry('second'))), 'duplicate');
  assert.equal(readFileSync(store.path, 'utf8'), before, 'a duplicate writes nothing');

  const rows = store.rows();
  assert.equal(rows.length, 1);
  assert.equal(rows[0].resolved?.name, 'first');
  assert.equal(rows[0].reviewDigest, reviewDigestOf(entry('first')));
});

test('a write that fails leaves the previous file whole', () => {
  const store = new InboxStore(scratchPath());
  store.add(row('alpha'));
  const before = readFileSync(store.path, 'utf8');

  // The temporary file the write goes through is a directory, so the write must fail before the rename.
  mkdirSync(`${store.path}.tmp-${process.pid}`);
  assert.throws(() => store.add(row('beta')));

  assert.equal(readFileSync(store.path, 'utf8'), before);
  assert.deepEqual(
    store.rows().map((r) => r.id),
    ['alpha'],
    'a row whose write failed is not held'
  );
});

test('a Partial row is stored with a null resolved and the digest of nothing', () => {
  const store = new InboxStore(scratchPath());
  store.add(row('unknown', null));

  const [held] = store.rows();
  assert.equal(held.resolved, null);
  assert.equal(held.reviewDigest, sha256(''));
  assert.equal(held.state, 'waiting');
});

test('the review digest is over the canonical JSON, so key order does not change it', () => {
  const a = entry('alpha');
  const reordered = Object.fromEntries(Object.entries(a).reverse()) as unknown as RegistryEntry;

  assert.equal(reviewDigestOf(reordered), reviewDigestOf(a));
  const sorted = Object.fromEntries(Object.entries(a).sort(([x], [y]) => (x < y ? -1 : x > y ? 1 : 0)));
  assert.equal(reviewDigestOf(a), sha256(JSON.stringify(sorted)));
  assert.notEqual(reviewDigestOf({ ...a, displayName: 'changed' }), reviewDigestOf(a));
});

test('a new row keeps every waiting row, and drops the oldest decided row once more than 200 are decided', () => {
  const path = scratchPath();
  mkdirSync(join(path, '..'), { recursive: true });
  const decided = Array.from({ length: INBOX_RETAIN_DECIDED + 1 }, (_, i) => ({
    ...row(`decided-${i}`),
    state: 'accepted',
    reviewDigest: reviewDigestOf(entry(`decided-${i}`)),
    receivedAt: `2026-10-19T10:${String(i % 60).padStart(2, '0')}:00Z`,
  }));
  writeFileSync(path, JSON.stringify({ rows: decided }));

  const store = new InboxStore(path);
  assert.equal(store.add(row('waiting-one')), 'waiting');

  const rows = store.rows();
  const kept = rows.filter((r) => r.state !== 'waiting');
  assert.equal(kept.length, INBOX_RETAIN_DECIDED);
  assert.equal(kept[0].id, 'decided-1', 'the oldest decided row is the one dropped');
  assert.equal(rows.filter((r) => r.state === 'waiting').length, 1, 'a waiting row is never dropped');
  assert.equal(rows.at(-1)?.id, 'waiting-one');
});

test('setState moves one row, keeps the file 0600, and reports a row it does not hold as not moved', () => {
  const store = new InboxStore(scratchPath());
  store.add(row('alpha'));
  store.add(row('beta'));

  assert.equal(store.setState('alpha', 'declined'), true);
  assert.equal(store.setState('gamma', 'declined'), false);
  assert.deepEqual(
    store.rows().map((r) => [r.id, r.state]),
    [
      ['alpha', 'declined'],
      ['beta', 'waiting'],
    ]
  );
  assert.equal(store.find('beta')?.state, 'waiting');
  assert.equal(store.find('gamma'), undefined);
  assert.equal(statSync(store.path).mode & 0o777, 0o600);
});

test('a decision keeps the row it just decided, even when that row is the oldest decided one', () => {
  const path = scratchPath();
  mkdirSync(join(path, '..'), { recursive: true });
  const held = (id: string, state: string) => ({ ...row(id), state, reviewDigest: reviewDigestOf(entry(id)) });
  writeFileSync(
    path,
    JSON.stringify({
      rows: [held('oldest', 'waiting'), ...Array.from({ length: INBOX_RETAIN_DECIDED }, (_, i) => held(`decided-${i}`, 'accepted'))],
    })
  );

  const store = new InboxStore(path);
  assert.equal(store.setState('oldest', 'declined'), true);

  const rows = store.rows();
  assert.equal(rows.find((r) => r.id === 'oldest')?.state, 'declined');
  assert.equal(rows.filter((r) => r.state !== 'waiting').length, INBOX_RETAIN_DECIDED);
  assert.equal(rows.some((r) => r.id === 'decided-0'), false, 'the oldest decided row other than the one just decided is dropped');
});

test('the view names a row without its phone id or receive time', () => {
  const store = new InboxStore(scratchPath());
  store.add(row('alpha'));

  const [view] = store.view();
  assert.deepEqual(Object.keys(view).sort(), ['deviceName', 'id', 'queuedAt', 'resolved', 'reviewDigest', 'state']);
  assert.equal(view.deviceName, "Luke's iPhone");
  assert.equal(JSON.stringify(store.view()).includes('phone-a'), false);
});

test('a store with no file yet reads as empty, and reading creates nothing', () => {
  const path = scratchPath();
  const store = new InboxStore(path);
  assert.deepEqual(store.view(), []);
  assert.throws(() => statSync(path), /ENOENT/);
});


test('namespaced registry entries produce deterministic valid local tool namespaces', () => {
  const built = declarationFor({ ...entry('echo'), name: 'io.fixture/inbox__echo', install: { type: 'http', url: 'https://example.test/mcp' } });
  assert.deepEqual(built, { name: 'io-fixture-inbox_echo', server: { type: 'http', url: 'https://example.test/mcp' } });
});


test('an install with invisible controls is refused rather than running bytes absent from review', () => {
  for (const hidden of ['\n', '\u2028', '\u200b', '\u202e']) {
    const built = declarationFor({ ...entry('echo'), install: { type: 'stdio', command: 'node', args: [`--allow${hidden}-write`] } });
    assert.ok('reason' in built);
    assert.equal(built.reason, 'notInstallable');
  }
});
