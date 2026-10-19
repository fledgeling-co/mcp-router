import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ExtensionStore, KINDS, type ExtensionFile, type ExtensionKind } from '../src/extensions.js';

/*
 * The store reads and writes the directory tree the Swift store wrote (app/Sources/RouterCore/Extensions).
 * An entry is a directory tree, so these run against real directories: the property under test is what
 * a listing reports from disk, and an in-memory double cannot stand for that.
 */
const made: string[] = [];
after(() => {
  for (const d of made) rmSync(d, { recursive: true, force: true });
});

/** A root that does not exist yet, inside a scratch directory removed afterwards. */
function scratchRoot(): string {
  const parent = mkdtempSync(join(tmpdir(), 'ext-store-'));
  made.push(parent);
  return join(parent, 'extensions');
}

function skill(name: string, description = 'does a thing'): ExtensionFile[] {
  return [{ path: 'SKILL.md', text: `---\nname: ${name}\ndescription: ${description}\n---\n\n# ${name}\n` }];
}

function plugin(name: string): ExtensionFile[] {
  return [{ path: '.claude-plugin/plugin.json', text: `{"name":"${name}","description":"a plugin"}` }];
}

function marketplace(name: string): ExtensionFile[] {
  return [{ path: '.claude-plugin/marketplace.json', text: `{"name":"${name}","owner":{"name":"someone"},"plugins":[]}` }];
}

function filesFor(kind: ExtensionKind, name: string): ExtensionFile[] {
  if (kind === 'skills') return skill(name);
  if (kind === 'plugins') return plugin(name);
  return marketplace(name);
}

function fixedClock(ms: number): () => number {
  return () => ms;
}

/** Advances one step per read, so a second removal of one name is stamped later than the first. */
function steppingClock(start: number, step: number): () => number {
  let current = start;
  return () => (current += step);
}

for (const kind of KINDS) {
  test(`E1 — ${kind} can be added, listed, read and removed`, () => {
    const store = new ExtensionStore(scratchRoot(), fixedClock(1000));
    assert.deepEqual(store.list(kind).records, []);

    const added = store.add(kind, 'alpha', filesFor(kind, 'alpha'));
    assert.equal(added.outcome, 'added');
    if (added.outcome !== 'added') return;
    assert.equal(added.record.name, 'alpha');
    assert.equal(added.record.title, 'alpha');
    assert.equal(added.record.problem, null);
    assert.equal(added.record.files, 1);
    assert.ok(added.record.bytes > 0);

    const listing = store.list(kind);
    assert.deepEqual(listing.records.map((r) => r.name), ['alpha']);
    assert.equal(listing.unreadable, null);
    assert.equal(store.read(kind, 'alpha')?.title, 'alpha');

    const removed = store.remove(kind, 'alpha');
    assert.equal(removed.outcome, 'removed');
    if (removed.outcome !== 'removed') return;
    assert.deepEqual(store.list(kind).records, []);
    assert.equal(store.read(kind, 'alpha'), null);
    // Reversible: the bytes are still there, at the path the outcome named.
    assert.ok(existsSync(join(removed.restorePath, filesFor(kind, 'alpha')[0].path)));
  });
}

test('E2 — an entry written behind the store\'s back is listed; one deleted is gone', () => {
  const root = scratchRoot();
  const store = new ExtensionStore(root, fixedClock(1000));
  store.add('skills', 'alpha', skill('alpha'));

  // Nothing here goes through the store: the reading is of the disk, so a change the router did not
  // make still shows up on the next listing.
  const manual = join(root, 'skills', 'beta');
  mkdirSync(manual, { recursive: true });
  writeFileSync(join(manual, 'SKILL.md'), '---\nname: beta\ndescription: hand written\n---\n');
  assert.deepEqual(store.list('skills').records.map((r) => r.name), ['alpha', 'beta']);
  assert.equal(store.read('skills', 'beta')?.description, 'hand written');

  rmSync(join(root, 'skills', 'alpha'), { recursive: true });
  assert.deepEqual(store.list('skills').records.map((r) => r.name), ['beta']);
});

test('E3 — a descriptor that rots after the add is listed with the problem, not dropped', () => {
  const root = scratchRoot();
  const store = new ExtensionStore(root, fixedClock(1000));
  store.add('plugins', 'alpha', plugin('alpha'));

  writeFileSync(join(root, 'plugins', 'alpha', '.claude-plugin', 'plugin.json'), '{ not json');
  const listing = store.list('plugins');
  // Counted, because the count is the number this route exists to answer.
  assert.equal(listing.records.length, 1);
  assert.equal(listing.records[0].title, null);
  assert.match(listing.records[0].problem ?? '', /is not valid JSON/);
});

test('E4 — an empty store and an absent one both read as zero, and neither is unreadable', () => {
  const store = new ExtensionStore(scratchRoot(), fixedClock(1000));
  for (const kind of KINDS) {
    assert.deepEqual(store.list(kind).records, []);
    assert.equal(store.list(kind).unreadable, null);
  }
});

test('E5 — dotted names are operating-system litter and are not listed', () => {
  const root = scratchRoot();
  const store = new ExtensionStore(root, fixedClock(1000));
  store.add('skills', 'alpha', skill('alpha'));
  mkdirSync(join(root, 'skills', '.DS_Store'), { recursive: true });
  assert.deepEqual(store.list('skills').records.map((r) => r.name), ['alpha']);
});

interface MalformedAdd {
  label: string;
  name: string;
  files: ExtensionFile[];
  reason: string;
}

const malformed: MalformedAdd[] = [
  // path escapes, the two shapes that would reach outside the entry
  { label: 'a path that climbs out', name: 'bad', files: [{ path: '../escape.md', text: 'x' }], reason: 'invalidFilePath' },
  { label: 'an absolute path', name: 'bad', files: [{ path: '/etc/passwd', text: 'x' }], reason: 'invalidFilePath' },
  // a name that is not a name
  { label: 'a name with a separator', name: '../evil', files: [{ path: 'SKILL.md', text: 'x' }], reason: 'invalidName' },
  { label: 'a name that is the trash directory', name: '.removed', files: [{ path: 'SKILL.md', text: 'x' }], reason: 'invalidName' },
  { label: 'an empty name', name: '', files: [{ path: 'SKILL.md', text: 'x' }], reason: 'invalidName' },
  // nothing to write
  { label: 'no files', name: 'bad', files: [], reason: 'noFiles' },
  // the descriptor is absent, unopened, unclosed, unnamed, or names something else
  { label: 'no descriptor', name: 'bad', files: [{ path: 'README.md', text: 'x' }], reason: 'missingDescriptor' },
  { label: 'no frontmatter', name: 'bad', files: [{ path: 'SKILL.md', text: 'no ---' }], reason: 'malformedDescriptor' },
  { label: 'unclosed frontmatter', name: 'bad', files: [{ path: 'SKILL.md', text: '---\nname: bad\n' }], reason: 'malformedDescriptor' },
  { label: 'frontmatter without a name', name: 'bad', files: [{ path: 'SKILL.md', text: '---\ndescription: d\n---\n' }], reason: 'malformedDescriptor' },
  { label: 'a descriptor naming another entry', name: 'bad', files: [{ path: 'SKILL.md', text: '---\nname: other\n---\n' }], reason: 'nameMismatch' },
  // one path given twice: the second copy would silently win
  {
    label: 'one path given twice',
    name: 'bad',
    files: [
      { path: 'SKILL.md', text: '---\nname: bad\n---\n' },
      { path: 'SKILL.md', text: '---\nname: bad\n---\n' },
    ],
    reason: 'duplicateFilePath',
  },
];

for (const c of malformed) {
  test(`E6 — ${c.label} is refused whole and leaves nothing on disk`, () => {
    const root = scratchRoot();
    const store = new ExtensionStore(root, fixedClock(1000));

    const outcome = store.add('skills', c.name, c.files);
    assert.equal(outcome.outcome, 'refused');
    if (outcome.outcome !== 'refused') return;
    assert.equal(outcome.refusal.reason, c.reason);
    assert.equal(outcome.refusal.status, 400);
    // Half-registered is the failure the ordering exists to prevent: nothing under the kind
    // directory, and nothing staged either.
    assert.deepEqual(store.list('skills').records, []);
    assert.equal(existsSync(join(root, '.staging')), false);
  });
}

test('E7 — a second add under one name is 409 and does not overwrite the first', () => {
  const store = new ExtensionStore(scratchRoot(), fixedClock(1000));
  store.add('skills', 'alpha', skill('alpha', 'first'));

  const second = store.add('skills', 'alpha', skill('alpha', 'second'));
  assert.equal(second.outcome, 'refused');
  if (second.outcome !== 'refused') return;
  assert.equal(second.refusal.status, 409);
  assert.equal(second.refusal.reason, 'nameTaken');
  assert.equal(store.read('skills', 'alpha')?.description, 'first');
});

test('E8 — removing something that is not there is 404, and removes nothing', () => {
  const store = new ExtensionStore(scratchRoot(), fixedClock(1000));
  store.add('skills', 'alpha', skill('alpha'));

  const outcome = store.remove('skills', 'ghost');
  assert.equal(outcome.outcome, 'refused');
  if (outcome.outcome !== 'refused') return;
  assert.equal(outcome.refusal.status, 404);
  assert.equal(outcome.refusal.message, 'no skill named "ghost"');
  assert.equal(store.list('skills').records.length, 1);
});

test('E9 — two removals of one name keep both copies rather than the second burying the first', () => {
  const store = new ExtensionStore(scratchRoot(), steppingClock(1000, 1000));

  store.add('skills', 'alpha', skill('alpha', 'first'));
  const first = store.remove('skills', 'alpha');
  store.add('skills', 'alpha', skill('alpha', 'second'));
  const second = store.remove('skills', 'alpha');
  assert.equal(first.outcome, 'removed');
  assert.equal(second.outcome, 'removed');
  if (first.outcome !== 'removed' || second.outcome !== 'removed') return;
  assert.notEqual(first.restorePath, second.restorePath);
  assert.ok(existsSync(join(first.restorePath, 'SKILL.md')));
  assert.ok(existsSync(join(second.restorePath, 'SKILL.md')));
});
