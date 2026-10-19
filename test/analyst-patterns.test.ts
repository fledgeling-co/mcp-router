import { test } from 'node:test';
import assert from 'node:assert/strict';
import { extractPatterns, PATTERN_EXAMPLES, PATTERN_LIMIT } from '../src/analyst-patterns.js';
import type { SessionEntry } from '../src/analyst-corpus.js';
import type { MCPClient } from '../src/harness.js';

/*
 * The counting half, ported from SessionPatterns.swift. F7 REQ-030.2: a signal reaches the judge only when it recurs at
 * or above the floor, and carries its count, its harnesses and at most three verbatim examples. The model never sees
 * the corpus, only these counts.
 */
const entries = (lines: Array<[MCPClient, string]>): SessionEntry[] =>
  lines.map(([harness, text]) => ({ harness, text }));

test('a signal under the floor does not reach the judge', () => {
  const twice = entries([
    ['claudeCode', 'docker logs a'],
    ['claudeCode', 'docker logs b'],
  ]);
  assert.deepEqual(extractPatterns(twice), []);

  const thrice = entries([
    ['claudeCode', 'docker logs a'],
    ['claudeCode', 'docker logs b'],
    ['claudeCode', 'docker logs c'],
  ]);
  const found = extractPatterns(thrice);
  assert.deepEqual(found.map((p) => p.signal), ['docker logs']);
  assert.equal(found[0].occurrences, 3);
});

test('a missing tool is its own kind, and the shell spellings both reach it', () => {
  const found = extractPatterns(
    entries([
      ['claudeCode', 'zsh: command not found: pgcli'],
      ['codexCLI', 'bash: pgcli: command not found'],
      ['claudeCode', 'command not found: pgcli'],
    ]),
  );
  assert.equal(found.length, 1);
  assert.equal(found[0].kind, 'missingTool');
  assert.equal(found[0].signal, 'pgcli');
  assert.deepEqual(found[0].harnesses, ['claudeCode', 'codexCLI']);
});

test('prose does not become a command', () => {
  const prose = 'can you run the docker logs for me and tell me what broke';
  assert.deepEqual(extractPatterns(entries([['claudeCode', prose], ['claudeCode', prose], ['claudeCode', prose]])), []);
});

test('no more than three examples travel with a pattern', () => {
  const nine = Array.from({ length: 9 }, (_, i) => ['claudeCode', `docker logs container-${i + 1}`] as [MCPClient, string]);
  const pattern = extractPatterns(entries(nine))[0];
  assert.equal(pattern.occurrences, 9);
  assert.equal(pattern.examples.length, PATTERN_EXAMPLES);
  assert.equal(PATTERN_EXAMPLES, 3);
});

test('the judge sees at most twelve patterns', () => {
  const lines: Array<[MCPClient, string]> = [];
  for (let tool = 0; tool < 13; tool += 1) {
    for (let rep = 0; rep < 3; rep += 1) lines.push(['claudeCode', `tool${String.fromCharCode(97 + tool)} --flag`]);
  }
  assert.equal(extractPatterns(entries(lines)).length, PATTERN_LIMIT);
  assert.equal(PATTERN_LIMIT, 12);
});
