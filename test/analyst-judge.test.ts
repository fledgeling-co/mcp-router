import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  analystPrompt,
  AnalystJudgeError,
  cliJudge,
  readJudgements,
  type CommandRunner,
} from '../src/analyst-judge.js';
import { laneArguments } from '../src/analyst-lanes.js';

/*
 * The reply reader, the CLI judge and the lane argument vectors, ported from AnalystJudge.swift, AnalystLane.swift and
 * AnalystPrompt. F7 REQ-030.3 and .4: the router keeps only what names a candidate it offered, and counts the rest.
 */
const candidates = [
  { id: 'docker-mcp', name: 'Docker MCP', summary: 'container control' },
  { id: 'pgcli', name: 'pgcli', summary: 'a postgres shell' },
];
const signals = ['docker logs', 'pgcli'];
const read = (reply: string) => readJudgements(reply, candidates, signals);

test('a well-formed line becomes a judgement', () => {
  const out = read('{"entry":"docker-mcp","signal":"docker logs","why":"you read logs by hand"}');
  assert.equal(out.rejected, 0);
  assert.deepEqual(out.accepted.map((j) => j.entryID), ['docker-mcp']);
  assert.equal(out.accepted[0].signal, 'docker logs');
});

test('an id outside the candidate list is rejected and counted', () => {
  // The count is the assertion, not the emptiness: an engine that discarded everything and one handed nothing both
  // produce an empty list.
  const out = read('{"entry":"kubernetes-mcp","signal":"docker logs","why":"invented"}');
  assert.equal(out.accepted.length, 0);
  assert.equal(out.rejected, 1);
});

test('a signal the run never counted is rejected, so the evidence figure cannot be invented', () => {
  const out = read('{"entry":"pgcli","signal":"kubectl get pods","why":"you use kubernetes"}');
  assert.equal(out.accepted.length, 0);
  assert.equal(out.rejected, 1);
});

test('a truncated line is rejected rather than half-read', () => {
  const out = read('{"entry":"pgcli","signal":"pgcli","why":');
  assert.equal(out.accepted.length, 0);
  assert.equal(out.rejected, 1);
});

test('prose around the answer is ignored, and the answer inside it still lands', () => {
  const out = read(
    [
      'Sure! Here is what I found:',
      '{"entry":"pgcli","signal":"pgcli","why":"your shell could not find it"}',
      'Let me know if you want more.',
    ].join('\n'),
  );
  assert.equal(out.accepted.length, 1);
  assert.equal(out.rejected, 0);
});

test('a second line for an entry already accepted is rejected, not delivered twice', () => {
  const out = read(
    [
      '{"entry":"pgcli","signal":"pgcli","why":"first"}',
      '{"entry":"pgcli","signal":"pgcli","why":"second"}',
    ].join('\n'),
  );
  assert.equal(out.accepted.length, 1);
  assert.equal(out.rejected, 1);
});

test('the prompt lists the signals and the candidate ids the answer is checked against', () => {
  const text = analystPrompt(
    [{ kind: 'command', signal: 'docker logs', occurrences: 3, harnesses: ['claudeCode'], examples: ['docker logs a'] }],
    candidates,
  );
  assert.ok(text.includes('What recurred:'));
  assert.ok(text.includes('- command "docker logs" ×3 in Claude Code'));
  assert.ok(text.includes('    e.g. docker logs a'));
  assert.ok(text.includes('- docker-mcp — Docker MCP: container control'));
});

test('an empty reply is refused by the CLI judge as empty, not as a refusal', async () => {
  const runner: CommandRunner = { run: async () => ({ status: 0, output: '   \n' }) };
  await assert.rejects(cliJudge(runner).judge('p', 'claude'), (err: unknown) =>
    err instanceof AnalystJudgeError && err.kind === 'empty',
  );
});

test('a binary that is not installed is not a refusal, so the ladder can fall through', async () => {
  const runner: CommandRunner = { run: async () => null };
  await assert.rejects(cliJudge(runner).judge('p', 'claude'), (err: unknown) =>
    err instanceof AnalystJudgeError && err.kind === 'notInstalled',
  );
});

test('a CLI that exits non-zero is a refusal that names the exit status', async () => {
  const runner: CommandRunner = { run: async () => ({ status: 2, output: 'usage limit reached' }) };
  await assert.rejects(cliJudge(runner).judge('p', 'codex'), (err: unknown) =>
    err instanceof AnalystJudgeError && err.kind === 'refused' && err.message.includes('exited 2'),
  );
});

test('a lane runs with the prompt as one argument, so no shell ever sees it', () => {
  const hostile = 'list $(rm -rf ~) `whoami` ; echo';
  for (const lane of ['claude', 'cursor', 'grok', 'codex', 'gemini'] as const) {
    const args = laneArguments(lane, hostile);
    assert.equal(args.at(-1), hostile, `${lane} passes the prompt as its final, single argument`);
  }
});

test('each lane runs its pinned model, and the Claude lane is the cheap rung', () => {
  assert.deepEqual(laneArguments('claude', 'p'), ['--model', 'claude-haiku-4-5', '-p', 'p']);
  assert.ok(laneArguments('codex', 'p').includes('gpt-5.6-luna'));
  assert.ok(laneArguments('codex', 'p').includes('model_reasoning_effort="low"'));
  assert.ok(laneArguments('grok', 'p').includes('grok-4.6'));
});
