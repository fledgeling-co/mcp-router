import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { configureLogging, log } from '../src/log.js';

const made: string[] = [];
after(() => {
  configureLogging(undefined, false);
  for (const d of made) rmSync(d, { recursive: true, force: true });
});

/** A fresh path for a router.log inside a new directory. */
function logPath(): string {
  const dir = mkdtempSync(join(tmpdir(), 'logstderr-test-'));
  made.push(dir);
  return join(dir, 'router.log');
}

/** Run `fn` and return the non-empty lines it wrote to stderr. */
function stderrLines(fn: () => void): string[] {
  const write = process.stderr.write;
  let captured = '';
  process.stderr.write = ((chunk: string | Uint8Array) => {
    captured += String(chunk);
    return true;
  }) as typeof process.stderr.write;
  try {
    fn();
  } finally {
    process.stderr.write = write;
  }
  return captured.split('\n').filter(Boolean);
}

function emitEveryLevel(): void {
  log.info('info line');
  log.warn('warn line');
  log.error('error line');
}

describe('log stderr mirroring', () => {
  test('with a log file in use, only error lines reach stderr', () => {
    const file = logPath();
    configureLogging(file, false);
    const lines = stderrLines(emitEveryLevel);
    configureLogging(undefined, false);

    assert.equal(lines.length, 1, `expected one stderr line, got: ${JSON.stringify(lines)}`);
    assert.match(lines[0], /error line$/);
  });

  test('with a log file in use, the file still holds every level', () => {
    const file = logPath();
    configureLogging(file, false);
    stderrLines(emitEveryLevel);
    configureLogging(undefined, false);

    const written = readFileSync(file, 'utf8');
    assert.match(written, /info line\n/);
    assert.match(written, /warn line\n/);
    assert.match(written, /error line\n/);
  });

  test('with a log file in use, debug lines stay in the file when verbose', () => {
    const file = logPath();
    configureLogging(file, true);
    const lines = stderrLines(() => log.debug('debug line'));
    configureLogging(undefined, false);

    assert.deepEqual(lines, []);
    assert.match(readFileSync(file, 'utf8'), /debug line\n/);
  });

  test('with no log file in use, every line reaches stderr', () => {
    configureLogging(undefined, false);
    const lines = stderrLines(emitEveryLevel);

    assert.equal(lines.length, 3, `expected three stderr lines, got: ${JSON.stringify(lines)}`);
    assert.match(lines[0], /info line$/);
    assert.match(lines[1], /warn line$/);
    assert.match(lines[2], /error line$/);
  });
});
