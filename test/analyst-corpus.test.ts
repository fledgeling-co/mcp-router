import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { readSessionCorpus, sessionStores, CORPUS_LINE_CAP } from '../src/analyst-corpus.js';

/*
 * The session corpus, ported from SessionCorpus.swift. F7 REQ-030.1: every figure it reports is one it counted, and a
 * store it could not use is named with its reason.
 *
 * Every assertion reads a positive quantity or a named reason. A reader that opened nothing produces an empty corpus,
 * and an empty corpus satisfies "no wrong lines were counted", so `linesRead > 0` sits beside every discard.
 */
const made: string[] = [];
after(() => {
  for (const d of made) rmSync(d, { recursive: true, force: true });
});

/** A throwaway home directory with the given files written under it, keyed by path relative to home. */
function homeWith(files: Record<string, string>): string {
  const dir = mkdtempSync(join(tmpdir(), 'analyst-corpus-'));
  made.push(dir);
  for (const [rel, text] of Object.entries(files)) {
    const full = join(dir, rel);
    mkdirSync(dirname(full), { recursive: true });
    writeFileSync(full, text);
  }
  return dir;
}

function seeded(): string {
  return homeWith({
    '.claude/history.jsonl': [
      '{"display":"docker logs mcp-gateway --tail 50"}',
      '{"display":"docker logs mcp-gateway -f"}',
      '{"display":"docker ps -a"}',
      'not json at all',
      '{"noKnownMember":true}',
      '',
      '{"display":"zsh: command not found: pgcli"}',
    ].join('\n'),
    '.codex/history.jsonl': '{"text":"docker logs router --since 1h"}\n{"text":"pgcli: command not found"}\n',
    '.grok/sessions/a.jsonl': '{"prompt":"docker compose up -d"}\n',
  });
}

test('it reports the lines it parsed, and that number is not zero', () => {
  const corpus = readSessionCorpus(seeded());
  // Four from Claude (three docker lines and the not-found line, out of seven opened), two from Codex, one from Grok.
  assert.equal(corpus.entries.length, 7);
  assert.equal(corpus.reports.reduce((sum, r) => sum + r.lines, 0), 7);
});

test('a line it cannot use is counted as discarded rather than dropped in silence', () => {
  const corpus = readSessionCorpus(seeded());
  const claude = corpus.reports.find((r) => r.harness === 'claudeCode');
  // `not json at all`, `{"noKnownMember":true}` and the blank line: three opened, none used.
  assert.equal(claude?.discarded, 3);
  assert.equal(claude?.lines, 4);
});

test('every store appears, and an absent one says why', () => {
  const corpus = readSessionCorpus(seeded());
  // Five, written out. Dropping a store from the table would move a derived count with it, so the literal is what
  // makes the assertion able to fail.
  assert.equal(corpus.reports.length, 5);
  assert.equal(sessionStores('/x').length, 5);
  const gemini = corpus.reports.find((r) => r.harness === 'geminiCLI');
  assert.equal(gemini?.read, false);
  // The directory is absent on this fixture, so the listing fails. The reason says so.
  assert.equal(gemini?.reason, 'this directory could not be listed');
  assert.equal(corpus.entries.some((e) => e.harness === 'geminiCLI'), false);
});

test('the SQLite store is enumerated, unread, and carries the reason it was not opened', () => {
  const cursor = readSessionCorpus(seeded()).reports.find((r) => r.harness === 'cursor');
  assert.equal(cursor?.read, false);
  assert.ok(cursor?.reason?.includes('SQLite'));
});

test('a store the reader reached and could use nothing from is read, with a reason', () => {
  const dir = homeWith({ '.claude/history.jsonl': 'nonsense\nmore nonsense\n' });
  const claude = readSessionCorpus(dir).reports.find((r) => r.harness === 'claudeCode');
  assert.equal(claude?.read, true);
  assert.equal(claude?.lines, 0);
  assert.equal(claude?.discarded, 3);
  assert.equal(claude?.reason, 'every line in this store was discarded');
});

test('a file store reads only its most recent lines, and says how many it opened', () => {
  const rows = Array.from({ length: CORPUS_LINE_CAP + 5 }, (_, i) => `{"display":"echo ${i}"}`);
  const dir = homeWith({ '.claude/history.jsonl': rows.join('\n') });
  const claude = readSessionCorpus(dir).reports.find((r) => r.harness === 'claudeCode');
  assert.equal(claude?.lines, CORPUS_LINE_CAP);
  assert.equal(claude?.discarded, 0);
});
