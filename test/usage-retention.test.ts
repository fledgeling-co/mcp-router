import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, statSync, utimesSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DEFAULT_USAGE_POLICY, UsageStore, type UsagePolicy, type UsageRecord } from '../src/usage.js';

/*
 * Call history kept by time, rotated into numbered generations, and folded into windows that say what they cover.
 * Every test runs over a fixed clock (`NOW`) and a scratch home, so no test reads the operator's own usage log.
 */
const made: string[] = [];
after(() => {
  for (const d of made) rmSync(d, { recursive: true, force: true });
});

const HOUR = 3_600_000;
const DAY = 24 * HOUR;
/** 2026-10-20T12:00Z, on the hour, so the windows' bucket arithmetic is exact. */
const NOW = Date.UTC(2026, 9, 20, 12, 0, 0);

/** A policy small enough that a few dozen records rotate several times. */
const SMALL: UsagePolicy = { ...DEFAULT_USAGE_POLICY, generationBytes: 400 };

function scratch(): { dir: string; log: string; stats: string } {
  const dir = mkdtempSync(join(tmpdir(), 'usage-retention-'));
  made.push(dir);
  return { dir, log: join(dir, 'usage.jsonl'), stats: join(dir, 'usage-stats.json') };
}

/** A stats file whose `since` is `sinceMs`, so the router is taken to have been counting from then. */
function seedSince(statsPath: string, sinceMs: number): void {
  writeFileSync(statsPath, JSON.stringify({ version: 1, since: new Date(sinceMs).toISOString(), servers: {} }));
}

function rec(tsMs: number, extra: Partial<UsageRecord> = {}): UsageRecord {
  return { ts: new Date(tsMs).toISOString(), server: 'alpha-server', tool: 't', ok: true, ms: 1, cold: false, client: 'claude', ...extra };
}

/** Forty records, one an hour, from forty hours before `NOW` up to one hour before it. */
function fortyHourly(store: UsageStore): void {
  for (let i = 0; i < 40; i++) store.record(rec(NOW - (40 - i) * HOUR));
}

function generationNames(dir: string): string[] {
  return readdirSync(dir)
    .filter((n) => n.startsWith('usage.jsonl.'))
    .sort();
}

test('history rotates into numbered generations, and the 7-day window reads every one of them', async () => {
  const { dir, log, stats } = scratch();
  seedSince(stats, NOW - 30 * DAY);
  const store = new UsageStore(log, stats, SMALL);
  fortyHourly(store);

  assert.ok(generationNames(dir).length >= 3, `the log rotated into several generations, found ${generationNames(dir)}`);
  const window = await store.insights(NOW, 7 * 24);
  assert.equal(window.totalCalls, 40, 'every record inside seven days is counted, across every generation');
  assert.equal(window.unreadableLines, 0);
  assert.equal(window.horizon, new Date(NOW - 40 * HOUR).toISOString(), 'the horizon is the oldest record the window holds');
  assert.equal(window.complete, true, 'observation began before the window, and nothing was removed from it');
});

test('a 24-hour window counts only the hours it covers, and the 7-day window counts the whole week', async () => {
  const { log, stats } = scratch();
  seedSince(stats, NOW - 30 * DAY);
  const store = new UsageStore(log, stats, SMALL);
  fortyHourly(store);

  // The window starts at the top of the hour 23 back, so the records one to twenty-three hours before NOW count.
  assert.equal((await store.insights(NOW, 24)).totalCalls, 23);
  assert.equal((await store.insights(NOW, 7 * 24)).totalCalls, 40);
});

test('history older than the retention window is removed by age, and counted as aged rather than lost', () => {
  const { dir, log, stats } = scratch();
  seedSince(stats, NOW - 30 * DAY);

  // A generation last written nine days ago, holding two records from that time.
  const old = join(dir, 'usage.jsonl.2');
  writeFileSync(old, [rec(NOW - 9 * DAY), rec(NOW - 9 * DAY + HOUR)].map((r) => JSON.stringify(r)).join('\n') + '\n');
  const agedAt = new Date(Date.now() - 9 * DAY);
  utimesSync(old, agedAt, agedAt);
  // A generation written recently, which must survive.
  const recent = join(dir, 'usage.jsonl.1');
  writeFileSync(recent, JSON.stringify(rec(NOW - 2 * DAY)) + '\n');

  const store = new UsageStore(log, stats, SMALL);
  assert.equal(existsSync(old), false, 'the aged generation is removed when the router starts');
  assert.equal(existsSync(recent), true, 'a recent generation is kept');
  assert.deepEqual(store.retention().aged, { generations: 1, records: 2 });
  assert.deepEqual(store.retention().capped, { generations: 0, records: 0, from: null, to: null });
});

test('a generation counts as aged only when its last write is older than the window', () => {
  const { dir, log, stats } = scratch();
  seedSince(stats, NOW - 30 * DAY);
  const borderline = join(dir, 'usage.jsonl.1');
  writeFileSync(borderline, JSON.stringify(rec(NOW - 6 * DAY)) + '\n');
  const justInside = new Date(Date.now() - (DEFAULT_USAGE_POLICY.retainMs - HOUR));
  utimesSync(borderline, justInside, justInside);

  new UsageStore(log, stats, SMALL);
  assert.equal(existsSync(borderline), true, 'written inside the window, so it is kept');
});

test('the size cap drops the oldest generations, reports the span they covered, and marks the 7-day window incomplete', async () => {
  const { dir, log, stats } = scratch();
  seedSince(stats, NOW - 30 * DAY);
  const store = new UsageStore(log, stats, { ...SMALL, capBytes: 1000 });
  fortyHourly(store);

  const ledger = store.retention();
  assert.ok(ledger.capped.generations > 0, 'generations were removed to stay under the cap');
  assert.ok(ledger.capped.records > 0, 'the removed records are counted');
  assert.ok(ledger.capped.from && ledger.capped.to, 'the span removed is named');
  assert.ok(ledger.capped.from! <= ledger.capped.to!, 'the span runs forwards');

  const kept = readdirSync(dir)
    .filter((n) => n.startsWith('usage.jsonl'))
    .reduce((sum, n) => sum + statSync(join(dir, n)).size, 0);
  // The cap is enforced at each rotation. Between rotations the active log grows by up to one generation and a record,
  // so the history can sit above the cap by that much and no more.
  const slack = Buffer.byteLength(JSON.stringify(rec(NOW))) + 1;
  assert.ok(kept <= 1000 + SMALL.generationBytes + slack, `history stays within one generation of the cap, found ${kept} bytes`);

  const week = await store.insights(NOW, 7 * 24);
  assert.equal(week.complete, false, 'history inside the window was removed, so the window is not whole');
  assert.ok(week.totalCalls < 40, 'the removed records are not in the count');
  const nulls = week.hours.filter((h) => h.calls === null).length;
  assert.ok(nulls > 0, 'an hour the cap emptied is null, not a zero the router never observed');
});

test('a window that starts before the router began counting is incomplete, and its unobserved hours are null', async () => {
  const { log, stats } = scratch();
  seedSince(stats, NOW - 2 * DAY);
  const store = new UsageStore(log, stats, SMALL);
  fortyHourly(store);

  const week = await store.insights(NOW, 7 * 24);
  assert.equal(week.observedSince, new Date(NOW - 2 * DAY).toISOString());
  assert.equal(week.complete, false, 'the 7-day window reaches back past the start of observation');
  // Window hours run from NOW-167h. Those that start before NOW-48h were not observed: 119 of 168.
  assert.equal(week.hours.filter((h) => h.calls === null).length, 119);
  assert.equal(week.hours.filter((h) => h.calls !== null).length, 49);

  const day = await store.insights(NOW, 24);
  assert.equal(day.complete, true, 'the 24-hour window starts inside observation');
  assert.ok(day.hours.every((h) => h.calls !== null), 'every hour of the day was observed');
});

test('a window the router has observed in full is complete, and every hour is a count', async () => {
  const { log, stats } = scratch();
  seedSince(stats, NOW - 30 * DAY);
  const store = new UsageStore(log, stats, SMALL);
  fortyHourly(store);

  const week = await store.insights(NOW, 7 * 24);
  assert.equal(week.complete, true);
  assert.ok(week.hours.every((h) => h.calls !== null), 'no hour is unobserved');
});

test('a generation that cannot be read makes the window incomplete rather than quietly short', async () => {
  const { dir, log, stats } = scratch();
  seedSince(stats, NOW - 30 * DAY);
  const store = new UsageStore(log, stats, SMALL);
  fortyHourly(store);
  // A directory where a generation should be: its name matches, its mtime is fresh, and it cannot be read as a file.
  mkdirSync(join(dir, 'usage.jsonl.99'));

  const week = await store.insights(NOW, 7 * 24);
  assert.equal(week.complete, false, 'a generation the window could reach was not read');
});

test('reset removes every generation as well as the active log', () => {
  const { dir, log, stats } = scratch();
  seedSince(stats, NOW - 30 * DAY);
  const store = new UsageStore(log, stats, SMALL);
  fortyHourly(store);
  assert.ok(generationNames(dir).length > 0);

  store.reset();
  assert.deepEqual(readdirSync(dir).filter((n) => n.startsWith('usage.jsonl')), []);
});
