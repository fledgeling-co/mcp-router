import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { AnalystEngine, type AnalystCandidateSource } from '../src/analyst.js';
import { AnalystJudgeError, type AnalystJudge } from '../src/analyst-judge.js';
import { AnalystSettingsRefusal } from '../src/analyst-lanes.js';

/*
 * The engine end to end, ported from AnalystEngineTests.swift. F7 REQ-030.3 to .6. Every judge here can refuse, and the
 * rejection path is asserted by its count: an engine that found nothing and an engine that broke look the same without it.
 */
const made: string[] = [];
const DAY = 24 * 3_600_000;

/** A home directory whose Claude history holds three docker lines, which is the corpus every test starts from. */
function home(): string {
  const dir = mkdtempSync(join(tmpdir(), 'analyst-engine-'));
  made.push(dir);
  seedHistory(dir, ['docker logs a', 'docker logs b', 'docker logs c']);
  return dir;
}

function seedHistory(dir: string, displays: string[]): void {
  const file = join(dir, '.claude', 'history.jsonl');
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, displays.map((d) => JSON.stringify({ display: d })).join('\n') + '\n');
}

/** A judge that answers per lane, so a ladder can be driven rung by rung. A lane with no reply refuses. */
function ladderJudge(replies: Partial<Record<string, string>>): AnalystJudge {
  return {
    judge: async (_prompt, lane) => {
      const reply = replies[lane];
      if (reply === undefined) throw new AnalystJudgeError('refused', `no ${lane}`);
      return reply;
    },
  };
}

const candidatesOf = (rows: Array<{ id: string; name: string; summary: string }> | null): AnalystCandidateSource => ({
  candidates: async () => rows,
});

const DOCKER_MCP = { id: 'docker-mcp', name: 'Docker MCP', summary: 'container control' };
const DOCKER_REPLY = '{"entry":"docker-mcp","signal":"docker logs","why":"you read container logs by hand"}';

function engine(opts: {
  home: string;
  judge: AnalystJudge;
  candidates?: AnalystCandidateSource | null;
  now?: () => number;
  statePath?: string;
}): { engine: AnalystEngine; statePath: string } {
  const statePath = opts.statePath ?? join(opts.home, 'analyst.json');
  const built = new AnalystEngine({
    home: opts.home,
    statePath,
    judge: opts.judge,
    candidates: opts.candidates === undefined ? candidatesOf([DOCKER_MCP]) : opts.candidates,
    now: opts.now ?? (() => 1_000),
  });
  return { engine: built, statePath };
}

after(() => {
  for (const d of made) rmSync(d, { recursive: true, force: true });
});

test('a run records what it read, what it found, and which rung judged', async () => {
  const dir = home();
  made.push(dir);
  const { engine: analyst, statePath } = engine({ home: dir, judge: ladderJudge({ claude: DOCKER_REPLY }) });
  const run = await analyst.analyse();
  assert.equal(run.kind, 'run');
  if (run.kind !== 'run') return;
  assert.equal(run.run.lane, 'claude');
  assert.equal(run.run.usedFallback, false);
  assert.equal(run.run.linesRead, 3);
  assert.equal(run.run.findings.length, 1);
  assert.equal(run.run.findings[0].entryID, 'docker-mcp');
  assert.equal(run.run.findings[0].evidenceCount, 3);
  // The state file is a separate channel from the returned value: a run that only built an object would pass above and
  // leave nothing behind.
  assert.ok(readFileSync(statePath, 'utf8').includes('docker-mcp'));
});

test('the primary refusing runs the fallback, and the run says so', async () => {
  const dir = home();
  made.push(dir);
  const { engine: analyst } = engine({ home: dir, judge: ladderJudge({ grok: DOCKER_REPLY }) });
  const run = await analyst.analyse();
  assert.equal(run.kind, 'run');
  if (run.kind !== 'run') return;
  assert.equal(run.run.lane, 'grok');
  assert.equal(run.run.usedFallback, true);
  assert.equal(run.run.findings[0].judgedBy, 'grok');
});

test('every rung refusing records no run at all and carries what each one said', async () => {
  const dir = home();
  made.push(dir);
  const { engine: analyst } = engine({ home: dir, judge: ladderJudge({}) });
  const run = await analyst.analyse();
  assert.equal(run.kind, 'ladderExhausted');
  if (run.kind !== 'ladderExhausted') return;
  assert.equal(run.refusals.length, 2);
  assert.equal(analyst.lastRun(), null);
});

test('an off-list recommendation is counted as rejected, not delivered', async () => {
  const dir = home();
  made.push(dir);
  const { engine: analyst } = engine({
    home: dir,
    judge: ladderJudge({ claude: '{"entry":"invented-mcp","signal":"docker logs","why":"no"}' }),
  });
  const run = await analyst.analyse();
  assert.equal(run.kind, 'run');
  if (run.kind !== 'run') return;
  assert.equal(run.run.findings.length, 0);
  assert.equal(run.run.rejectedFindings, 1);
});

test('no candidate source means no findings and a stated reason, never a bare zero', async () => {
  const dir = home();
  made.push(dir);
  const { engine: analyst } = engine({ home: dir, judge: ladderJudge({ claude: DOCKER_REPLY }), candidates: null });
  const run = await analyst.analyse();
  assert.equal(run.kind, 'run');
  if (run.kind !== 'run') return;
  assert.equal(run.run.candidatesUnavailable, true);
  assert.equal(run.run.lane, null);
  assert.equal(run.run.findings.length, 0);
});

test('the same finding inside thirty days is suppressed, and after them it fires again', async () => {
  const dir = home();
  made.push(dir);
  const clock = { now: 1_000 };
  const analyst = new AnalystEngine({
    home: dir,
    statePath: join(dir, 'analyst.json'),
    judge: ladderJudge({ claude: DOCKER_REPLY }),
    candidates: candidatesOf([DOCKER_MCP]),
    now: () => clock.now,
  });
  const first = await analyst.analyse();
  assert.ok(first.kind === 'run' && first.run.findings.length === 1);

  clock.now += 29 * DAY;
  const quiet = await analyst.analyse();
  assert.ok(quiet.kind === 'run' && quiet.run.findings.length === 0);

  clock.now += 2 * DAY;
  const again = await analyst.analyse();
  assert.ok(again.kind === 'run' && again.run.findings.length === 1);
});

test('a finding whose evidence gained a new signal is a new finding', async () => {
  const dir = home();
  made.push(dir);
  const first = engine({ home: dir, judge: ladderJudge({ claude: DOCKER_REPLY }) }).engine;
  const firstRun = await first.analyse();
  assert.ok(firstRun.kind === 'run' && firstRun.run.findings.length === 1);

  seedHistory(dir, [
    'docker logs a',
    'docker logs b',
    'docker logs c',
    'docker compose up',
    'docker compose down',
    'docker compose ps',
  ]);
  const grown = ladderJudge({
    claude: '{"entry":"docker-mcp","signal":"docker compose","why":"and compose too"}',
  });
  const second = await engine({ home: dir, judge: grown }).engine.analyse();
  assert.equal(second.kind, 'run');
  if (second.kind !== 'run') return;
  assert.equal(second.run.findings.length, 1);
  assert.deepEqual(second.run.findings[0].signals, ['docker compose']);
});

test('settings survive a restart, and an unknown lane is refused by name', () => {
  const dir = home();
  made.push(dir);
  const statePath = join(dir, 'analyst.json');
  const first = engine({ home: dir, judge: ladderJudge({}), statePath }).engine;
  first.update({ primary: 'codex', cadence: 'daily' });

  const reopened = engine({ home: dir, judge: ladderJudge({}), statePath }).engine;
  assert.equal(reopened.settings().primary, 'codex');
  assert.equal(reopened.settings().cadence, 'daily');
  // Unchanged by a patch that did not name it, which is the point of a patch.
  assert.equal(reopened.settings().fallback, 'grok');

  assert.throws(() => reopened.update({ primary: 'llama' }), (err: unknown) =>
    err instanceof AnalystSettingsRefusal && err.member === 'primary' && err.value === 'llama',
  );
  assert.equal(reopened.settings().primary, 'codex');
});
