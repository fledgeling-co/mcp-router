import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { IncomingMessage, ServerResponse } from 'node:http';
import type { ControlDeps } from '../src/control.js';
import type { UpstreamConfig } from '../src/config.js';
import type { HarnessReport, MCPClient } from '../src/harness.js';

/*
 * GET /insights, through handleControl. Ported from the base of ControlInsights.swift. The analyst member is null
 * here because no analyst is wired into these deps; its readout is covered by insights-analyst-route.test.ts.
 *
 * The router home is set before control.ts loads, because config.ts reads it at import. Without this,
 * a usage log a test writes could be read from the operator's own home.
 */
const made: string[] = [];
after(() => {
  for (const d of made) rmSync(d, { recursive: true, force: true });
});

const home = mkdtempSync(join(tmpdir(), 'insights-home-'));
made.push(home);
process.env.MCP_ROUTER_HOME = home;

const { handleControl } = await import('../src/control.js');
const { UsageStore } = await import('../src/usage.js');
const { UpstreamPool } = await import('../src/pool.js');

const TOKEN = 'insights-test-token-0123456789abcdef';
const HOUR = 3_600_000;

/** Every member the Mac model's InsightsResponse reads. The analyst member is null when the router has no analyst. */
const ENVELOPE_KEYS = [
  'analyst',
  'calls',
  'callsByHarness',
  'callsPerHour',
  'children',
  'dutyCycle',
  'generatedAt',
  'logHorizon',
  'otherCalls',
  'resident',
  'windowHours',
  'windowStart',
].sort();
const CALLS_KEYS = ['failed', 'total', 'unreadableLines'].sort();
const CHILDREN_KEYS = ['alive', 'declared'].sort();
const HARNESS_ROW_KEYS = ['calls', 'displayName', 'harness', 'reason'].sort();
const HOUR_KEYS = ['calls', 'hourStart'].sort();
const DUTY_KEYS = ['servers', 'uptimeSeconds'].sort();
const SERVER_KEYS = ['aliveSeconds', 'server'].sort();
const RESIDENT_KEYS = ['children', 'megabytes'].sort();

const UPSTREAMS = new Map<string, UpstreamConfig>([
  ['alpha-server', { name: 'alpha-server', transport: 'stdio', command: 'x', args: [] } as unknown as UpstreamConfig],
  ['beta-server', { name: 'beta-server', transport: 'http', url: 'http://127.0.0.1:1' } as unknown as UpstreamConfig],
]);

const iso = (ms: number): string => new Date(ms).toISOString();

function scratch(): string {
  const dir = mkdtempSync(join(tmpdir(), 'insights-'));
  made.push(dir);
  return dir;
}

/** A usage store over a log that holds `lines`, or over no log at all when `lines` is undefined. */
function usageFrom(lines: string[] | undefined): ControlDeps['usage'] {
  const dir = scratch();
  const logPath = join(dir, 'usage.jsonl');
  if (lines) writeFileSync(logPath, lines.join('\n') + '\n');
  return new UsageStore(logPath, join(dir, 'usage-stats.json'));
}

/** One harness, as far as the route reads it: its client name. */
function harness(client: MCPClient): HarnessReport {
  return { client } as unknown as HarnessReport;
}

/**
 * Drive one request through handleControl and capture the answer. `token` of null omits the header, and
 * the default is the router's own token. Returns `handled` so a path the route does not claim is visible.
 */
async function send(
  method: string,
  path: string,
  deps: Partial<ControlDeps>,
  token: string | null = TOKEN
): Promise<{ handled: boolean; status: number; json: any }> {
  const headers: Record<string, string> = {};
  if (token !== null) headers['x-mcpr-token'] = token;
  // Mutating requests must declare JSON, or the control API answers 415 before the route is reached.
  if (method === 'POST' || method === 'PATCH') headers['content-type'] = 'application/json';
  const req = { method, headers } as unknown as IncomingMessage;

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

  const handled = await handleControl(
    req,
    res,
    new URL(path, 'http://127.0.0.1:8879'),
    undefined,
    { cfg: { port: 8879 }, upstreams: UPSTREAMS, ...deps } as unknown as ControlDeps,
    TOKEN
  );
  return { handled, status, json: text ? JSON.parse(text) : undefined };
}

/** The call-log lines the counting tests share. Every timestamp is relative to `now`, so the window is known. */
function seededLog(now: number): string[] {
  return [
    JSON.stringify({ ts: iso(now - 60_000), server: 'alpha-server', tool: 't', ok: true, client: 'claude' }),
    JSON.stringify({ ts: iso(now - 120_000), server: 'alpha-server', tool: 't', ok: false, client: 'claude' }),
    JSON.stringify({ ts: iso(now - 3 * HOUR), server: 'beta-server', tool: 't', ok: true, client: 'agy' }),
    JSON.stringify({ ts: iso(now - 4 * HOUR), server: 'beta-server', tool: 't', ok: true }),
    JSON.stringify({ ts: iso(now - 5 * HOUR), server: 'beta-server', tool: 't', ok: true, client: '' }),
    // Outside the 24-hour window: not counted, and not unreadable either.
    JSON.stringify({ ts: iso(now - 30 * HOUR), server: 'beta-server', tool: 't', ok: true, client: 'claude' }),
    // Unreadable: a torn line, and a timestamp that is not the fixed-width UTC shape.
    '{"ts":"2026-10',
    JSON.stringify({ ts: 'yesterday', server: 'beta-server', tool: 't', ok: true }),
  ];
}

test('GET /insights is token-gated: refused without the token and with a wrong one', async () => {
  const deps = { pool: new UpstreamPool(UPSTREAMS, 0, 1000), usage: usageFrom(undefined) };
  for (const token of [null, 'not-the-token']) {
    const refused = await send('GET', '/insights', deps, token);
    assert.equal(refused.handled, true, 'the route claims the path, so it answers rather than falling through');
    assert.equal(refused.status, 401);
  }
  const allowed = await send('GET', '/insights', deps);
  assert.equal(allowed.status, 200);
});

test('the envelope carries every member the Mac model reads, with the nested shapes it expects', async () => {
  const now = Date.now();
  const deps = {
    pool: new UpstreamPool(UPSTREAMS, 0, 1000),
    usage: usageFrom(seededLog(now)),
    harnesses: { reports: () => [harness('claudeCode')] },
  };
  const { json: body } = await send('GET', '/insights', deps);

  assert.deepEqual(Object.keys(body).sort(), ENVELOPE_KEYS);
  assert.deepEqual(Object.keys(body.calls).sort(), CALLS_KEYS);
  assert.deepEqual(Object.keys(body.children).sort(), CHILDREN_KEYS);
  assert.deepEqual(Object.keys(body.dutyCycle).sort(), DUTY_KEYS);
  for (const server of body.dutyCycle.servers) assert.deepEqual(Object.keys(server).sort(), SERVER_KEYS);
  for (const hour of body.callsPerHour) assert.deepEqual(Object.keys(hour).sort(), HOUR_KEYS);
  for (const row of body.callsByHarness) assert.deepEqual(Object.keys(row).sort(), HARNESS_ROW_KEYS);

  assert.equal(body.analyst, null, 'no analyst is wired into these deps, so the member is null');
  assert.equal(typeof body.generatedAt, 'string');
  assert.equal(body.windowHours, 24, 'the window is fixed at 24 hours, the same as the reference');
});

test('every count is taken over the window, and the bars reconcile to the headline total', async () => {
  const now = Date.now();
  const deps = {
    pool: new UpstreamPool(UPSTREAMS, 0, 1000),
    usage: usageFrom(seededLog(now)),
    harnesses: { reports: () => [harness('claudeCode'), harness('geminiCLI')] },
  };
  const { json: body } = await send('GET', '/insights', deps);

  // Five records are in the window; the one 30 hours back is outside it, and two lines are unreadable.
  assert.equal(body.calls.total, 5);
  assert.equal(body.calls.failed, 1);
  assert.equal(body.calls.unreadableLines, 2);

  // The log holds claude twice, agy once, and two calls with no peer name. Each harness takes only its own.
  const byHarness = Object.fromEntries(body.callsByHarness.map((row: any) => [row.harness, row.calls]));
  assert.equal(byHarness.claudeCode, 2);
  assert.equal(byHarness.geminiCLI, 1);
  assert.equal(body.otherCalls, 2, 'the two unnamed calls are left over, not credited to a harness');
  const attributed = body.callsByHarness.reduce((sum: number, row: any) => sum + (row.calls ?? 0), 0);
  assert.equal(attributed + body.otherCalls, body.calls.total, 'bars and headline reconcile');

  // The hourly counts cover the same five calls.
  const hourly = body.callsPerHour.reduce((sum: number, hour: any) => sum + hour.calls, 0);
  assert.equal(hourly, body.calls.total);
});

test('the log horizon is the oldest record the window actually holds', async () => {
  const now = Date.now();
  const deps = { pool: new UpstreamPool(UPSTREAMS, 0, 1000), usage: usageFrom(seededLog(now)) };
  const { json: body } = await send('GET', '/insights', deps);
  assert.equal(body.logHorizon, iso(now - 5 * HOUR), 'the record five hours back, not the 30-hour one outside the window');
});

test('a harness that cannot be attributed carries null and a reason, never zero', async () => {
  const now = Date.now();
  const deps = {
    pool: new UpstreamPool(UPSTREAMS, 0, 1000),
    usage: usageFrom(seededLog(now)),
    harnesses: { reports: () => [harness('codexCLI'), harness('claudeDesktop')] },
  };
  const { json: body } = await send('GET', '/insights', deps);
  const codex = body.callsByHarness.find((row: any) => row.harness === 'codexCLI');
  const desktop = body.callsByHarness.find((row: any) => row.harness === 'claudeDesktop');

  assert.equal(codex.calls, null, 'two harnesses share the codex binary, so no count may be claimed');
  assert.match(codex.reason, /codex/);
  assert.equal(codex.displayName, 'Codex CLI');
  assert.equal(desktop.calls, null, 'nothing has established what Claude Desktop calls look like');
  assert.match(desktop.reason, /nothing has established/);
  assert.equal(body.otherCalls, 5, 'with no attributable harness, every call is left over');
});

test('with no harness inventory the bars are empty and every call is left over', async () => {
  const now = Date.now();
  const deps = { pool: new UpstreamPool(UPSTREAMS, 0, 1000), usage: usageFrom(seededLog(now)) };
  const { json: body } = await send('GET', '/insights', deps);
  assert.deepEqual(body.callsByHarness, []);
  assert.equal(body.otherCalls, 5);
});

test('an empty window says so: no horizon, zero counts, and a full 24 hours of empty buckets', async () => {
  const deps = { pool: new UpstreamPool(UPSTREAMS, 0, 1000), usage: usageFrom(undefined) };
  const { json: body } = await send('GET', '/insights', deps);

  assert.equal(body.logHorizon, null, 'no record in the window means no horizon, not a guessed one');
  assert.equal(body.calls.total, 0);
  assert.equal(body.callsPerHour.length, 24);
  assert.ok(body.callsPerHour.every((hour: any) => hour.calls === 0));
  assert.equal(body.windowStart, body.callsPerHour[0].hourStart);
  assert.match(body.windowStart, /:00:00\.000Z$/, 'the window starts on a whole hour, so every bucket is whole');
  const starts = body.callsPerHour.map((hour: any) => Date.parse(hour.hourStart));
  assert.ok(starts.every((start: number, i: number) => i === 0 || start - starts[i - 1] === HOUR));
});

test('with no child process the resident figure is null and every declared server is still listed', async () => {
  const deps = { pool: new UpstreamPool(UPSTREAMS, 0, 1000), usage: usageFrom(undefined) };
  const { json: body } = await send('GET', '/insights', deps);

  assert.equal(body.resident, null, 'nothing is running, so there is no measurement to report');
  assert.deepEqual(body.children, { alive: 0, declared: 2 });
  assert.deepEqual(
    body.dutyCycle.servers.map((server: any) => server.server),
    ['alpha-server', 'beta-server'],
    'a server that has never been opened is a row at zero, not an absence'
  );
  assert.ok(body.dutyCycle.servers.every((server: any) => server.aliveSeconds === 0));
  assert.ok(Number.isInteger(body.dutyCycle.uptimeSeconds) && body.dutyCycle.uptimeSeconds >= 0);
});

test('the duty cycle sums every closed incarnation of a server, including one that fell over', async () => {
  const pool = new UpstreamPool(UPSTREAMS, 0, 1000);
  const now = Date.now();
  // A child alive for 90 seconds that closed on its own, which the reaper never saw.
  pool.recordAlive('beta-server', now - 90_000, now);

  const { json: body } = await send('GET', '/insights', { pool, usage: usageFrom(undefined) });
  const beta = body.dutyCycle.servers.find((server: any) => server.server === 'beta-server');
  assert.equal(beta.aliveSeconds, 90);
});

test('a running child with a measured figure reports resident memory with its denominator', async () => {
  const pool = new UpstreamPool(UPSTREAMS, 0, 1000);
  // A live handle whose process is this test process, so the RSS reading is a real measurement of a real process.
  (pool as unknown as { entries: Map<string, unknown> }).entries.set('beta-server', {
    inFlight: 0,
    handle: {
      client: {},
      transport: { pid: process.pid },
      startedAt: Date.now(),
      lastUsedAt: Date.now(),
      calls: 0,
    },
  });

  const { json: body } = await send('GET', '/insights', { pool, usage: usageFrom(undefined) });
  assert.deepEqual(Object.keys(body.resident).sort(), RESIDENT_KEYS);
  assert.equal(body.resident.children, 1, 'the figure carries how many children it was taken across');
  assert.ok(body.resident.megabytes >= 1);
  assert.deepEqual(body.children, { alive: 1, declared: 2 });
});

test('the two analyst paths are claimed, and with no analyst they answer 503 rather than falling through to /mcp', async () => {
  const deps = { pool: new UpstreamPool(UPSTREAMS, 0, 1000), usage: usageFrom(undefined) };
  const analyse = await send('POST', '/insights/analyse', deps);
  const analyst = await send('PATCH', '/insights/analyst', deps);
  assert.equal(analyse.handled, true);
  assert.equal(analyse.status, 503);
  assert.equal(analyst.handled, true);
  assert.equal(analyst.status, 503);
});
