import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { IncomingMessage, ServerResponse } from 'node:http';
import type { ControlDeps } from '../src/control.js';
import type { UpstreamConfig } from '../src/config.js';
import type { AnalystPort, AnalystRunRecord, AnalyseOutcome } from '../src/analyst.js';
import { AnalystSettingsRefusal, DEFAULT_SETTINGS, type AnalystSettings } from '../src/analyst-lanes.js';

/*
 * The analyst's three arms, through handleControl. Ported from ControlAnalystRoutesTests.swift, F7 REQ-030.7 and .8.
 *
 * Through the handler rather than the response builders, for the reason the Swift suite gives: a missing dispatch arm is
 * not a broken function, and a test that calls the builder directly cannot fail when the arm is deleted.
 *
 * The router home is set before control.ts loads, because config.ts reads it at import.
 */
const made: string[] = [];
after(() => {
  for (const d of made) rmSync(d, { recursive: true, force: true });
});
process.env.MCP_ROUTER_HOME = mkdtempSync(join(tmpdir(), 'analyst-route-home-'));
made.push(process.env.MCP_ROUTER_HOME);

const { handleControl } = await import('../src/control.js');
const { UpstreamPool } = await import('../src/pool.js');
const { UsageStore } = await import('../src/usage.js');

const usageDir = mkdtempSync(join(tmpdir(), 'analyst-route-usage-'));
made.push(usageDir);

const TOKEN = 'analyst-route-token-0123456789abcdef';
const UPSTREAMS = new Map<string, UpstreamConfig>([
  ['alpha-server', { name: 'alpha-server', transport: 'stdio', command: 'x', args: [] } as unknown as UpstreamConfig],
]);

/** A stub analyst a test can put in any state, including the two a real one will not enter on request. */
class StubAnalyst implements AnalystPort {
  stored: AnalystSettings = { ...DEFAULT_SETTINGS };
  run: AnalystRunRecord | null;
  outcome: AnalyseOutcome | null;
  analyseCalls = 0;

  constructor(opts: { run?: AnalystRunRecord | null; outcome?: AnalyseOutcome | null } = {}) {
    this.run = opts.run ?? null;
    this.outcome = opts.outcome ?? null;
  }

  settings(): AnalystSettings {
    return this.stored;
  }

  lastRun(): AnalystRunRecord | null {
    return this.run;
  }

  async analyse(): Promise<AnalyseOutcome> {
    this.analyseCalls += 1;
    const answer: AnalyseOutcome = this.outcome ?? { kind: 'run', run: RECORD };
    if (answer.kind === 'run') this.run = answer.run;
    return answer;
  }

  update(patch: unknown): AnalystSettings {
    const body = (patch ?? {}) as Record<string, unknown>;
    if ('primary' in body && body.primary !== 'codex') {
      throw new AnalystSettingsRefusal('primary', String(body.primary));
    }
    if ('primary' in body) this.stored = { ...this.stored, primary: 'codex' };
    return this.stored;
  }
}

const RECORD: AnalystRunRecord = {
  lane: 'grok',
  ranAtMilliseconds: 1_700_000_000_000,
  linesRead: 4210,
  discardedLines: 96,
  usedFallback: true,
  rejectedFindings: 1,
  candidatesUnavailable: false,
  stores: [
    {
      harness: 'cursor',
      path: '/h/.cursor/chats',
      read: false,
      lines: 0,
      discarded: 0,
      reason: 'this store is SQLite; the analyst reads JSON Lines only',
    },
  ],
  findings: [
    {
      id: 'analyst-abc',
      entryID: 'docker-mcp',
      subject: 'Docker MCP',
      sentence: 'you read container logs by hand',
      evidenceCount: 31,
      judgedBy: 'grok',
      signals: ['docker logs'],
    },
  ],
};

interface Reply {
  handled: boolean;
  status: number;
  json: any;
}

/** One request through handleControl. `authorized` false omits the token header. */
async function send(
  method: string,
  path: string,
  deps: Partial<ControlDeps>,
  body: unknown = undefined,
  authorized = true,
): Promise<Reply> {
  const headers: Record<string, string> = {};
  if (authorized) headers['x-mcpr-token'] = TOKEN;
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
    body,
    { cfg: { port: 8879 }, upstreams: UPSTREAMS, pool: new UpstreamPool(UPSTREAMS, 0, 1000),
      usage: new UsageStore(join(usageDir, 'usage.jsonl'), join(usageDir, 'usage-stats.json')),
      ...deps } as unknown as ControlDeps,
    TOKEN,
  );
  return { handled, status, json: text ? JSON.parse(text) : undefined };
}

const get = (path: string, deps: Partial<ControlDeps>, authorized = true) => send('GET', path, deps, undefined, authorized);

test('A1 — with no analyst the member is null and both routes name the missing capability', async () => {
  const insights = await get('/insights', {});
  assert.equal(insights.status, 200);
  assert.equal(insights.json.analyst, null);

  const run = await send('POST', '/insights/analyse', {});
  assert.equal(run.status, 503);
  // Not an empty run: an empty run reads as a router that analysed and found nothing.
  assert.ok(String(run.json.error).includes('session analysis is unavailable'));

  const patch = await send('PATCH', '/insights/analyst', {}, { cadence: 'daily' });
  assert.equal(patch.status, 503);
});

test('A2 — an analyst that has never run reports its settings with every reading absent', async () => {
  const { status, json } = await get('/insights', { analyst: new StubAnalyst() });
  assert.equal(status, 200);
  assert.equal(json.analyst.primary.label, 'Claude CLI · haiku');
  assert.equal(json.analyst.cadenceLabel, 'Every 6 hours');
  // Absent rather than zero: a `linesRead: 0` here would measure a run that never happened.
  assert.equal(json.analyst.ranAt, null);
  assert.equal('linesRead' in json.analyst, false);
  assert.deepEqual(json.analyst.stores, []);
});

test('A3 — the cadence is reported as a preference, never as a schedule', async () => {
  const { json } = await get('/insights', { analyst: new StubAnalyst({ run: RECORD }) });
  assert.equal(json.analyst.scheduled, false);
  assert.ok(typeof json.analyst.nextRunAt === 'string', 'the next run is derived from the last one');
});

test('A4 — pressing the button changes what a LATER GET reports', async () => {
  const analyst = new StubAnalyst();
  const deps = { analyst };
  const before = await get('/insights', deps);
  assert.equal(before.json.analyst.findings, undefined);

  const posted = await send('POST', '/insights/analyse', deps);
  assert.equal(posted.status, 200);

  // The outcome, read on the channel the POST did not write: a second GET.
  const after = await get('/insights', deps);
  assert.equal(after.json.analyst.recent[0].entryID, 'docker-mcp');
  assert.equal(after.json.analyst.linesRead, 4210);
  assert.equal(after.json.analyst.rejectedFindings, 1);
  assert.equal(analyst.analyseCalls, 1);
});

test('A5 — the store the analyst could not open is on the wire with its reason', async () => {
  const { json } = await get('/insights', { analyst: new StubAnalyst({ run: RECORD }) });
  const cursor = json.analyst.stores.find((s: { harness: string }) => s.harness === 'cursor');
  assert.equal(cursor.read, false);
  assert.ok(String(cursor.reason).includes('SQLite'));
});

test('A6 — a run already in flight is refused rather than doubled', async () => {
  const { status, json } = await send('POST', '/insights/analyse', {
    analyst: new StubAnalyst({ outcome: { kind: 'alreadyRunning' } }),
  });
  assert.equal(status, 409);
  assert.ok(String(json.error).includes('already running'));
});

test('A7 — every rung refusing is a 502 that names which model was unreachable', async () => {
  const outcome: AnalyseOutcome = { kind: 'ladderExhausted', refusals: ['claude: not on PATH'] };
  const { status, json } = await send('POST', '/insights/analyse', { analyst: new StubAnalyst({ outcome }) });
  assert.equal(status, 502);
  assert.ok(String(json.error).includes('claude'));
});

test('A8 — a PATCH takes, and an unknown lane is refused by member name', async () => {
  const analyst = new StubAnalyst();
  const deps = { analyst };

  const ok = await send('PATCH', '/insights/analyst', deps, { primary: 'codex' });
  assert.equal(ok.status, 200);
  // Read back through GET rather than from the PATCH's own reply.
  const after = await get('/insights', deps);
  assert.equal(after.json.analyst.primary.model, 'gpt-5.6-luna');
  assert.equal(analyst.settings().primary, 'codex');

  const refused = await send('PATCH', '/insights/analyst', deps, { primary: 'llama' });
  assert.equal(refused.status, 422);
  assert.equal(refused.json.member, 'primary');
  assert.equal(analyst.settings().primary, 'codex');
});

test('A9 — both paths are claimed, gated, and method-checked; a neighbour is not claimed', async () => {
  const deps = { analyst: new StubAnalyst() };

  // Claimed: an unauthorised mutation is 401, which only a path the control API owns can answer.
  const unauthorised = await send('POST', '/insights/analyse', deps, {}, false);
  assert.equal(unauthorised.handled, true);
  assert.equal(unauthorised.status, 401);

  // Claimed and method-checked: GET on the write path is 405, not 404.
  const wrongMethod = await get('/insights/analyse', deps);
  assert.equal(wrongMethod.status, 405);

  // Not claimed: a neighbouring path is not owned, so a typo is not turned into a 405 that reads as a wrong method.
  const neighbour = await send('POST', '/insights/analysex', deps, {});
  assert.equal(neighbour.handled, false);
});
