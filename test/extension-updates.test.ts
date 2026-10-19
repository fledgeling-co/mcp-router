import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readdirSync, rmSync, statSync, utimesSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ExtensionStore } from '../src/extensions.js';
import {
  buildFreshnessReport,
  compareFreshness,
  compareVersions,
  DEFAULT_STALE_AFTER_MS,
  freshnessValue,
  parseVersion,
  readCatalogue,
} from '../src/extension-updates.js';

/*
 * F6, ported from ExtensionFreshnessTests, ExtensionFreshnessScanTests and MarketplaceCatalogueTests. Every
 * verdict is driven against a fixture store this file builds, because the real machine has none of the
 * update cases on it (spec-F6 §3). No test reaches the network: the check reads the store and nothing else.
 */
const made: string[] = [];
after(() => {
  for (const d of made) rmSync(d, { recursive: true, force: true });
});

const NOW = Date.now();
const HOUR = 3_600_000;

function scratchStore(): ExtensionStore {
  const parent = mkdtempSync(join(tmpdir(), 'ext-updates-'));
  made.push(parent);
  return new ExtensionStore(join(parent, 'extensions'), () => NOW);
}

function plugin(name: string, version?: string): { path: string; text: string }[] {
  const manifest: Record<string, string> = { name };
  if (version !== undefined) manifest.version = version;
  return [{ path: '.claude-plugin/plugin.json', text: JSON.stringify(manifest) }];
}

function marketplace(name: string, offers: Array<{ name: string; version?: string }>): { path: string; text: string }[] {
  return [{ path: '.claude-plugin/marketplace.json', text: JSON.stringify({ name, plugins: offers }) }];
}

/** Stamp every file and directory under `path` with one modification time, so an age is a known number. */
function stampTree(path: string, ms: number): void {
  const when = new Date(ms);
  utimesSync(path, when, when);
  if (!statSync(path).isDirectory()) return;
  for (const name of readdirSync(path)) stampTree(join(path, name), ms);
}

/** The fixture the verdict table is built on: one of each state, and one catalogue that is not stale. */
function stocked(): ExtensionStore {
  const store = scratchStore();
  const add = (kind: 'plugins' | 'marketplaces' | 'skills', name: string, files: { path: string; text: string }[]) => {
    const outcome = store.add(kind, name, files.map((f) => ({ path: f.path, text: f.text })));
    assert.equal(outcome.outcome, 'added', `${name} should be written: ${JSON.stringify(outcome)}`);
  };
  add(
    'marketplaces',
    'm',
    marketplace('m', [
      { name: 'x', version: '2.0.0' },
      { name: 'y', version: '1.0.0' },
      { name: 'z' },
      { name: 'w', version: 'aa11bb22cc33' },
      { name: 'q', version: '1.0.0' },
      { name: '', version: '9.9.9' },
    ])
  );
  add('plugins', 'x@m', plugin('x@m', '1.0.0'));
  add('plugins', 'y@m', plugin('y@m', '1.0.0'));
  add('plugins', 'z@m', plugin('z@m', '1.0.0'));
  add('plugins', 'w@m', plugin('w@m', 'ed404106fcd8'));
  add('plugins', 'q@m', plugin('q@m', '2.0.0'));
  add('plugins', 'r@m', plugin('r@m', '1.0.0'));
  add('plugins', 's@ghost', plugin('s@ghost', '1.0.0'));
  add('plugins', 'bad', plugin('bad', '1.0.0'));
  add('skills', 'alpha', [{ path: 'SKILL.md', text: '---\nname: alpha\n---\n' }]);
  add('skills', 'beta', [{ path: 'SKILL.md', text: '---\nname: beta\nversion: 1.0.0\n---\n' }]);
  // The catalogue was written a moment ago; age it an hour so the default window reads it as fresh.
  stampTree(join(store.root, 'marketplaces', 'm'), NOW - HOUR);
  return store;
}

function rowOf(report: ReturnType<typeof buildFreshnessReport>, name: string) {
  const row = report.rows.find((r) => r.name === name);
  assert.ok(row, `no row named ${name}`);
  return row;
}

// MARK: - Versions

test('V1 — a version is three numbers with an optional suffix, and anything else is not parsed', () => {
  assert.deepEqual(parseVersion('1.2.3'), { major: 1, minor: 2, patch: 3, suffix: '' });
  assert.deepEqual(parseVersion('v1.2.3'), { major: 1, minor: 2, patch: 3, suffix: '' });
  assert.deepEqual(parseVersion('1.2.3-beta.1'), { major: 1, minor: 2, patch: 3, suffix: '-beta.1' });
  assert.equal(parseVersion('1.2'), null, 'a two-part version is not padded to 1.2.0');
  assert.equal(parseVersion('1.2.3rc1'), null, 'a suffix needs a separator');
  assert.equal(parseVersion('ed404106fcd8'), null, 'a git short SHA is not a version');
  assert.equal(parseVersion(''), null);
});

test('V2 — versions order numerically, a release outranks its pre-release, and two spellings of one version are the same', () => {
  assert.equal(compareVersions('1.0.0', '2.0.0'), 'ascending');
  assert.equal(compareVersions('1.10.0', '1.9.0'), 'descending', 'numeric, not lexical');
  assert.equal(compareVersions('1.0.0-beta', '1.0.0'), 'ascending');
  assert.equal(compareVersions('v1.0.0', '1.0.0'), 'same');
  assert.equal(compareVersions('ed404106fcd8', 'aa11bb22cc33'), null, 'two SHAs have no order');
});

// MARK: - Verdicts

test('V3 — each of the eight verdicts is reached, and only update-available is an update', () => {
  const update = compareFreshness({ installed: '1.0.0', offer: { name: 'p', version: '2.0.0' }, problem: null });
  assert.equal(update.state, 'update-available');
  assert.equal(update.hasUpdate, true);

  const current = compareFreshness({ installed: '1.0.0', offer: { name: 'p', version: '1.0.0' }, problem: null });
  assert.equal(current.state, 'current');
  assert.equal(current.hasUpdate, false);

  const behind = compareFreshness({ installed: '2.0.0', offer: { name: 'p', version: '1.0.0' }, problem: null });
  assert.equal(behind.state, 'catalogue-behind');
  assert.equal(behind.hasUpdate, false, 'an older catalogue offer is not an update');
  assert.equal(behind.installed, '2.0.0');
  assert.equal(behind.available, '1.0.0');

  const unorderable = compareFreshness({
    installed: 'ed404106fcd8',
    offer: { name: 'p', version: 'aa11bb22cc33' },
    problem: null,
  });
  assert.equal(unorderable.state, 'unorderable');
  assert.equal(unorderable.compared, true);

  const installedNone = compareFreshness({ installed: null, offer: { name: 'p', version: '1.0.0' }, problem: null });
  assert.equal(installedNone.state, 'installed-declares-no-version');
  assert.equal(installedNone.compared, false);

  const offerNone = compareFreshness({ installed: '1.0.0', offer: { name: 'p', version: undefined }, problem: null });
  assert.equal(offerNone.state, 'catalogue-declares-no-version');
  assert.equal(offerNone.installed, '1.0.0');
  assert.equal(offerNone.compared, false);

  const notOffered = compareFreshness({ installed: '1.0.0', offer: null, problem: null });
  assert.equal(notOffered.state, 'not-offered');

  const noCatalogue = compareFreshness({ installed: '1.0.0', offer: null, problem: 'no such marketplace' });
  assert.equal(noCatalogue.state, 'no-catalogue');
  assert.equal(noCatalogue.sentence, 'no such marketplace');
});

test('V4 — two absent versions are not two equal versions', () => {
  const verdict = compareFreshness({ installed: null, offer: { name: 'p', version: undefined }, problem: null });
  assert.equal(verdict.state, 'catalogue-declares-no-version', 'nil == nil must not read as current');
});

// MARK: - Catalogues

test('C1 — a catalogue is its plugins array; a nameless offer is skipped, an empty version is no version', () => {
  assert.equal(readCatalogue('[]'), null);
  assert.equal(readCatalogue('not json'), null);
  assert.equal(readCatalogue('{"name":"m"}'), null, 'no plugins array means not a catalogue');

  const catalogue = readCatalogue(
    JSON.stringify({
      name: 'm',
      plugins: [{ name: 'a', version: '1.0.0' }, { name: '', version: '2.0.0' }, { name: 'b', version: '' }, 7, { name: 'c' }],
    })
  );
  assert.ok(catalogue);
  assert.deepEqual(
    catalogue.offers.map((o) => o.name),
    ['a', 'b', 'c'],
    'the nameless offer and the non-object entry are skipped, not refused'
  );
  assert.equal(catalogue.declaredNoVersion, 2, 'b and c declare no version');
  assert.equal(catalogue.offer('b')?.version, undefined);
});

// MARK: - The report

test('R1 — the fixture reaches each state, and the summary counts compared and uncomparable as a partition', () => {
  const report = buildFreshnessReport(stocked(), { staleAfterMs: DEFAULT_STALE_AFTER_MS, now: NOW });

  assert.equal(rowOf(report, 'x@m').verdict.state, 'update-available');
  assert.equal(rowOf(report, 'y@m').verdict.state, 'current');
  assert.equal(rowOf(report, 'z@m').verdict.state, 'catalogue-declares-no-version');
  assert.equal(rowOf(report, 'w@m').verdict.state, 'unorderable');
  assert.equal(rowOf(report, 'q@m').verdict.state, 'catalogue-behind');
  assert.equal(rowOf(report, 'r@m').verdict.state, 'not-offered');
  assert.equal(rowOf(report, 's@ghost').verdict.state, 'no-catalogue');
  assert.equal(rowOf(report, 'bad').verdict.state, 'no-catalogue');
  assert.equal(rowOf(report, 'alpha').verdict.state, 'installed-declares-no-version');
  assert.equal(rowOf(report, 'beta').verdict.state, 'no-catalogue');
  assert.equal(rowOf(report, 'm').verdict.state, 'no-catalogue', 'a marketplace row is the catalogue itself');

  const { summary } = report;
  assert.equal(summary.total, report.rows.length);
  assert.equal(summary.updatesAvailable, 1);
  assert.equal(summary.compared + summary.uncomparable, summary.total);
  assert.equal(summary.staleCatalogues, 0);
});

test('R2 — a catalogue older than the window is stale, and an unknown age is reported rather than assumed stale', () => {
  const store = stocked();
  const window = buildFreshnessReport(store, { staleAfterMs: 60_000, now: NOW });
  assert.equal(window.catalogues.find((c) => c.name === 'm')?.stale, true, 'an hour old against a minute window');
  assert.equal(window.summary.staleCatalogues, 1);

  // `ghost` has no tree, so its age cannot be taken: null, and not stale, because nothing measured it.
  const missing = buildFreshnessReport(store, { staleAfterMs: DEFAULT_STALE_AFTER_MS, now: NOW });
  const ghost = missing.catalogues.find((c) => c.name === 'ghost');
  assert.equal(ghost?.ageMs, null);
  assert.equal(ghost?.stale, false);
  assert.equal(rowOf(missing, 's@ghost').catalogue, 'ghost');
});

test('R3 — a catalogue stamped ahead of the clock has a null age, and its offers still compare', () => {
  const store = stocked();
  stampTree(join(store.root, 'marketplaces', 'm'), NOW + DEFAULT_STALE_AFTER_MS);
  const report = buildFreshnessReport(store, { staleAfterMs: 0, now: NOW });

  const reading = report.catalogues.find((c) => c.name === 'm');
  assert.ok(reading);
  assert.equal(reading.ageMs, null, 'a negative age is not a young one');
  assert.equal(reading.stale, false, 'an unknown age is not known to be stale');
  assert.match(reading.ageProblem ?? '', /stamped ahead of this router's clock/);
  assert.equal(reading.problem, null, 'the catalogue still parsed');
  assert.equal(rowOf(report, 'x@m').verdict.state, 'update-available', 'the verdict is untouched by the age');
});

test('R4 — a catalogue with no tree at all says why, with null measurements and no offers', () => {
  const report = buildFreshnessReport(stocked(), { staleAfterMs: DEFAULT_STALE_AFTER_MS, now: NOW, name: 's@ghost' });
  assert.equal(report.rows.length, 1, 'name narrows the rows to the one entry asked for');
  const reading = report.catalogues.find((c) => c.name === 'ghost');
  assert.ok(reading);
  assert.equal(reading.newestModifiedMs, null);
  assert.equal(reading.ageMs, null);
  assert.match(reading.problem ?? '', /no marketplace named "ghost"/);
});

test('R5 — kinds narrows the rows, and a catalogue is read only when a row asks for it', () => {
  const store = stocked();
  const skills = buildFreshnessReport(store, { kinds: ['skills'], staleAfterMs: DEFAULT_STALE_AFTER_MS, now: NOW });
  assert.equal(skills.rows.length, 2);
  assert.equal(skills.catalogues.length, 0, 'no plugin or marketplace row, so no catalogue is read');
});

// MARK: - The wire

test('W1 — the report carries the field list the Swift route answers with, in the same order', () => {
  const report = buildFreshnessReport(stocked(), { staleAfterMs: DEFAULT_STALE_AFTER_MS, now: NOW });
  const value = JSON.parse(JSON.stringify(freshnessValue(report))) as Record<string, unknown>;

  assert.deepEqual(Object.keys(value), ['checkedAtMs', 'staleAfterMs', 'summary', 'catalogues', 'entries', 'unreadable']);
  const summary = value.summary as Record<string, unknown>;
  assert.deepEqual(Object.keys(summary), ['total', 'updatesAvailable', 'compared', 'uncomparable', 'staleCatalogues']);
  const catalogue = (value.catalogues as Record<string, unknown>[])[0];
  assert.deepEqual(Object.keys(catalogue), [
    'name',
    'path',
    'newestModifiedMs',
    'ageMs',
    'stale',
    'refreshable',
    'offers',
    'declaredNoVersion',
    'problem',
    'ageProblem',
  ]);
  const entry = (value.entries as Record<string, unknown>[])[0];
  assert.deepEqual(Object.keys(entry), [
    'kind',
    'name',
    'catalogue',
    'state',
    'installed',
    'available',
    'hasUpdate',
    'compared',
    'reason',
  ]);
});

test('W2 — an unobserved figure is null, never 0, and no entry carries a changelog', () => {
  const report = buildFreshnessReport(stocked(), { staleAfterMs: DEFAULT_STALE_AFTER_MS, now: NOW, name: 's@ghost' });
  const value = JSON.parse(JSON.stringify(freshnessValue(report))) as {
    catalogues: Array<{ ageMs: unknown; newestModifiedMs: unknown }>;
    entries: Array<Record<string, unknown>>;
  };
  assert.equal(value.catalogues[0].ageMs, null);
  assert.equal(value.catalogues[0].newestModifiedMs, null);
  for (const entry of value.entries) {
    assert.equal('changelog' in entry, false, 'the Swift route carries no changelog text, so neither does this');
  }
});
