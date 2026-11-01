import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { UsageStore, type UsageRecord } from '../src/usage.js';
import type { ControlDeps } from '../src/control.js';

const dirs: string[] = [];
after(() => { for (const dir of dirs) rmSync(dir, { force: true, recursive: true }); });
// control.ts captures its home at import. Never point even unused dependencies at owner history.
const home = mkdtempSync(join(tmpdir(), 'usage-reset-control-'));
dirs.push(home);
process.env.MCP_ROUTER_HOME = home;
const { handleControl } = await import('../src/control.js');
const TOKEN = 'scratch-usage-reset-token';
const OLD_SINCE = '2020-01-01T00:00:00.000Z';

function record(tool: string): UsageRecord {
  return { ts: new Date().toISOString(), server: 'scratch', tool, ok: true, ms: 1, cold: false };
}
function scratch() {
  const dir = mkdtempSync(join(tmpdir(), 'usage-reset-'));
  dirs.push(dir);
  const log = join(dir, 'usage.jsonl');
  const stats = join(dir, 'usage-stats.json');
  writeFileSync(stats, JSON.stringify({ version: 1, since: OLD_SINCE, servers: {} }));
  const store = new UsageStore(log, stats);
  store.record(record('before-reset'));
  store.flush();
  return { dir, log, stats, store };
}
function resetFailure(phase: string, removedFiles: number) {
  return (error: unknown) => {
    assert.ok(error instanceof Error);
    const detail = error as Error & { phase: string; removedFiles: number; partialReset: boolean };
    assert.equal(detail.phase, phase);
    assert.equal(detail.removedFiles, removedFiles);
    assert.equal(detail.partialReset, removedFiles > 0);
    assert.match(detail.message, /reset failed/i);
    return true;
  };
}
function restartedReadback(log: string, stats: string) {
  const child = spawnSync(process.execPath, ['--input-type=module', '-e', `
    const { UsageStore } = await import(process.argv[1]);
    const store = new UsageStore(process.argv[2], process.argv[3]);
    const window = await store.insights(Date.now(), 24);
    console.log(JSON.stringify({ pid: process.pid, summary: store.summary(), records: store.recent(), totalCalls: window.totalCalls }));
  `, new URL('../src/usage.js', import.meta.url).href, log, stats], {
    encoding: 'utf8', env: { ...process.env, MCP_ROUTER_HOME: home },
  });
  assert.equal(child.status, 0, child.stderr);
  const result = JSON.parse(child.stdout) as {
    pid: number; summary: ReturnType<UsageStore['summary']>; records: UsageRecord[]; totalCalls: number;
  };
  assert.notEqual(result.pid, process.pid, 'readback comes from a fresh Node process');
  return result;
}

test('reset commits an empty observation window across restart and retains subsequent calls', async () => {
  const { dir, log, stats, store } = scratch();
  writeFileSync(`${log}.1`, JSON.stringify(record('archive')) + '\n');
  store.record(record('pending-debounce'));
  const before = Date.now();
  store.reset();
  const since = store.summary().since;
  assert.ok(Date.parse(since) >= before);
  assert.deepEqual(store.summary().servers, {});
  assert.deepEqual(store.recent(), []);
  assert.deepEqual(store.retention().aged, { generations: 0, records: 0 });
  assert.deepEqual(store.retention().capped, { generations: 0, records: 0, from: null, to: null });
  assert.deepEqual(readdirSync(dir).filter(name => name.startsWith('usage.jsonl')), []);
  const emptyRestart = restartedReadback(log, stats);
  assert.equal(emptyRestart.summary.since, since);
  assert.deepEqual(emptyRestart.summary.servers, {});
  assert.deepEqual(emptyRestart.records, []);
  assert.equal(emptyRestart.totalCalls, 0);

  store.record(record('after-reset'));
  // The pre-reset debounce must not restore old aggregates, and post-reset debounce must persist the new call.
  await delay(3100);
  const reopened = restartedReadback(log, stats);
  assert.equal(reopened.summary.since, since);
  assert.equal(reopened.summary.servers.scratch.calls, 1);
  assert.deepEqual(reopened.records.map(r => r.tool), ['after-reset']);
  assert.equal(reopened.totalCalls, 1);
});

test('a real staging write failure refuses reset before any history is erased', () => {
  const { log, stats, store } = scratch();
  const oldLog = readFileSync(log); const oldStats = readFileSync(stats);
  mkdirSync(`${stats}.tmp-${process.pid}`);
  assert.throws(() => store.reset(), resetFailure('prepare', 0));
  assert.deepEqual(readFileSync(log), oldLog);
  assert.deepEqual(readFileSync(stats), oldStats);
  assert.equal(store.summary().since, OLD_SINCE);
  assert.equal(store.statFor('scratch')?.calls, 1);
  assert.deepEqual(store.recent().map(r => r.tool), ['before-reset']);
});

test('a failed generation listing cannot silently reset only the active log', () => {
  const { dir, log, stats, store } = scratch();
  const moved = `${dir}-moved`; dirs.push(moved);
  const oldLog = readFileSync(log); const oldStats = readFileSync(stats);
  renameSync(dir, moved);
  try {
    assert.throws(() => store.reset(), resetFailure('prepare', 0));
    assert.deepEqual(readFileSync(join(moved, 'usage.jsonl')), oldLog);
    assert.deepEqual(readFileSync(join(moved, 'usage-stats.json')), oldStats);
    assert.equal(store.summary().since, OLD_SINCE);
  } finally { renameSync(moved, dir); }
});

test('an obstructed generation refuses deletion without claiming an empty history', () => {
  const { log, stats, store } = scratch();
  const oldStats = readFileSync(stats);
  mkdirSync(`${log}.99`);
  assert.throws(() => store.reset(), resetFailure('delete', 0));
  assert.ok(existsSync(log));
  assert.ok(existsSync(`${log}.99`), 'reset never recursively removes a directory');
  assert.deepEqual(readFileSync(stats), oldStats);
  assert.equal(store.summary().since, OLD_SINCE);
  assert.deepEqual(store.recent().map(r => r.tool), ['before-reset']);
});

test('partial deletion is explicit, preserves the old aggregate and keeps subsequent records', async () => {
  const { log, stats, store } = scratch();
  writeFileSync(`${log}.2`, JSON.stringify(record('removed-archive')) + '\n');
  mkdirSync(`${log}.1`);
  const oldStats = readFileSync(stats);
  assert.throws(() => store.reset(), resetFailure('delete', 1));
  assert.equal(existsSync(`${log}.2`), false, 'an earlier deletion cannot be rolled back');
  assert.ok(existsSync(log));
  assert.deepEqual(readFileSync(stats), oldStats);
  assert.equal(store.summary().since, OLD_SINCE);
  store.record(record('after-refusal'));
  store.flush();
  const reopened = new UsageStore(log, stats);
  assert.equal(reopened.summary().since, OLD_SINCE);
  assert.equal(reopened.statFor('scratch')?.calls, 2);
  assert.deepEqual(reopened.recent().map(r => r.tool), ['after-refusal', 'before-reset']);
  assert.equal((await reopened.insights(Date.now(), 24)).complete, false);
});

test('a stats commit failure after erasure reports partial reset and reconciles the recent ring', () => {
  const { log, stats, store } = scratch();
  const oldStats = readFileSync(stats);
  rmSync(stats); mkdirSync(stats);
  assert.throws(() => store.reset(), resetFailure('commit', 1));
  assert.equal(existsSync(log), false);
  assert.deepEqual(store.recent(), [], 'erased records cannot remain in the recent ring');
  assert.equal(store.summary().since, OLD_SINCE, 'the aggregate is not declared reset before its durable commit');
  assert.equal(store.statFor('scratch')?.calls, 1);
  assert.equal(existsSync(`${stats}.tmp-${process.pid}`), false, 'failed reset cleans its staging file');
  rmSync(stats, { recursive: true }); writeFileSync(stats, oldStats);
  store.reset();
  store.record(record('after-retry')); store.flush();
  assert.equal(new UsageStore(log, stats).statFor('scratch')?.calls, 1);
  assert.deepEqual(new UsageStore(log, stats).recent().map(r => r.tool), ['after-retry']);
});

test('the real HTTP control route reports deletion failure, then successful reset and authoritative readback', async () => {
  const { log, stats, store } = scratch();
  mkdirSync(`${log}.99`);
  const deps = { usage: store, upstreams: new Map([['scratch', {}]]) } as unknown as ControlDeps;
  const server = createServer((req, res) => {
    void handleControl(req, res, new URL(req.url ?? '/', 'http://127.0.0.1'), undefined, deps, TOKEN)
      .then(handled => { if (!handled) { res.writeHead(404); res.end(); } })
      .catch(() => { res.writeHead(599); res.end('uncaught control failure'); });
  });
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve));
  const address = server.address(); assert.ok(address && typeof address !== 'string');
  const base = `http://127.0.0.1:${address.port}`;
  try {
    const unauthorized = await fetch(`${base}/usage/reset`, { method: 'POST' });
    assert.equal(unauthorized.status, 401);
    assert.equal(store.summary().since, OLD_SINCE);
    const refused = await fetch(`${base}/usage/reset`, { method: 'POST', headers: { authorization: `Bearer ${TOKEN}`, 'content-type': 'application/json' }, body: '{}' });
    assert.equal(refused.status, 500);
    const failure = await refused.json() as Record<string, unknown>;
    assert.equal(failure.reason, 'usageResetFailed');
    assert.equal(failure.phase, 'delete');
    assert.equal(failure.partialReset, false);
    assert.equal(failure.ok, undefined);
    assert.match(String(failure.error), /reset failed/i);
    rmSync(`${log}.99`, { recursive: true });
    writeFileSync(`${log}.2`, JSON.stringify(record('removed-archive')) + '\n');
    mkdirSync(`${log}.1`);
    const partial = await fetch(`${base}/usage/reset`, { method: 'POST', headers: { authorization: `Bearer ${TOKEN}`, 'content-type': 'application/json' }, body: '{}' });
    assert.equal(partial.status, 500);
    const partialBody = await partial.json() as Record<string, unknown>;
    assert.equal(partialBody.partialReset, true);
    assert.equal(partialBody.removedFiles, 1);
    assert.equal(partialBody.ok, undefined);
    assert.equal(store.summary().since, OLD_SINCE);
    rmSync(`${log}.1`, { recursive: true });
    const reset = await fetch(`${base}/usage/reset`, { method: 'POST', headers: { authorization: `Bearer ${TOKEN}`, 'content-type': 'application/json' }, body: '{}' });
    assert.equal(reset.status, 200);
    const body = await reset.json() as { ok: boolean; since: string };
    assert.equal(body.ok, true);
    assert.notEqual(body.since, OLD_SINCE);
    assert.equal(new UsageStore(log, stats).summary().since, body.since);
    store.record(record('http-after-reset')); store.flush();
    const readback = await fetch(`${base}/usage/summary`);
    assert.equal(readback.status, 200);
    const observed = await readback.json() as { since: string; servers: Array<{ name: string; calls: number }> };
    assert.equal(observed.since, body.since);
    assert.equal(observed.servers[0].calls, 1);
    const recent = await fetch(`${base}/usage`);
    const recentBody = await recent.json() as { records: UsageRecord[] };
    assert.deepEqual(recentBody.records.map(r => r.tool), ['http-after-reset']);
    assert.deepEqual(new UsageStore(log, stats).recent().map(r => r.tool), ['http-after-reset']);
  } finally {
    server.closeAllConnections();
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
});
