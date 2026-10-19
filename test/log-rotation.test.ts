import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join } from 'node:path';
import { configureLogging, log, DEFAULT_LOG_POLICY, type LogPolicy } from '../src/log.js';
import { loadConfig } from '../src/config.js';

const made: string[] = [];
after(() => {
  configureLogging(undefined, false);
  for (const d of made) rmSync(d, { recursive: true, force: true });
});

/** A fresh home holding one router.log. */
function home(): { dir: string; file: string } {
  const dir = mkdtempSync(join(tmpdir(), 'logrot-test-'));
  made.push(dir);
  return { dir, file: join(dir, 'router.log') };
}

/** Names of the active file's rotated generations, newest index first. */
function generationIndices(file: string): number[] {
  const base = basename(file) + '.';
  return readdirSync(dirname(file))
    .filter((n) => n.startsWith(base) && /^\d+$/.test(n.slice(base.length)))
    .map((n) => Number(n.slice(base.length)))
    .sort((a, b) => a - b);
}

/** Every file in the home, sorted, so a test can assert on the set rather than on one name. */
function files(file: string): string[] {
  return readdirSync(dirname(file)).sort();
}

/** Every line across the active file and its generations, oldest first. */
function linesOldestFirst(file: string): string[] {
  const gens = generationIndices(file).reverse().map((n) => `${file}.${n}`);
  return [...gens, file].flatMap((p) => readFileSync(p, 'utf8').split('\n').filter(Boolean));
}

function writeServers(dir: string, body: unknown): string {
  const path = join(dir, 'servers.json');
  mkdirSync(dir, { recursive: true });
  writeFileSync(path, JSON.stringify(body));
  return path;
}

describe('log rotation', () => {
  test('rotates before a write would take the active file past maxBytes', () => {
    const { file } = home();
    const policy: LogPolicy = { maxBytes: 300, keep: 3 };
    configureLogging(file, false, policy);
    for (let i = 0; i < 40; i++) log.info(`message ${i}`);

    assert.ok(statSync(file).size <= policy.maxBytes, 'active file grew past the cap');
    assert.ok(generationIndices(file).includes(1), 'nothing was rotated to router.log.1');
    for (const n of generationIndices(file)) {
      assert.ok(statSync(`${file}.${n}`).size <= policy.maxBytes, `generation ${n} is over the cap`);
    }
  });

  test('keeps every line, in order, across rotations', () => {
    const { file } = home();
    configureLogging(file, false, { maxBytes: 300, keep: 100 });
    for (let i = 0; i < 40; i++) log.info(`message ${i}`);
    configureLogging(undefined, false);

    const messages = linesOldestFirst(file).map((l) => l.slice(l.indexOf('message ')));
    assert.deepEqual(
      messages,
      Array.from({ length: 40 }, (_, i) => `message ${i}`),
      'a line was lost, duplicated, or reordered'
    );
  });

  test('retains only the configured number of generations', () => {
    const { file } = home();
    configureLogging(file, false, { maxBytes: 100, keep: 2 });
    for (let i = 0; i < 60; i++) log.info(`message ${i}`);
    configureLogging(undefined, false);

    assert.deepEqual(files(file), ['router.log', 'router.log.1', 'router.log.2']);
  });

  test('keep 0 restarts the active file and keeps no generation', () => {
    const { file } = home();
    configureLogging(file, false, { maxBytes: 100, keep: 0 });
    for (let i = 0; i < 30; i++) log.info(`message ${i}`);
    configureLogging(undefined, false);

    assert.deepEqual(files(file), ['router.log']);
    assert.ok(statSync(file).size <= 100, 'active file grew past the cap');
    assert.match(readFileSync(file, 'utf8'), /message 29\n$/);
  });

  test('removes generations left over from a larger keep', () => {
    const { file } = home();
    writeFileSync(`${file}.3`, 'old\n');
    writeFileSync(`${file}.7`, 'older\n');
    configureLogging(file, false, { maxBytes: 100, keep: 2 });
    for (let i = 0; i < 8; i++) log.info(`message ${i}`);
    configureLogging(undefined, false);

    assert.deepEqual(files(file), ['router.log', 'router.log.1', 'router.log.2']);
  });

  test('a line larger than the cap is written whole to a fresh file', () => {
    const { file } = home();
    configureLogging(file, false, { maxBytes: 20, keep: 1 });
    const big = 'x'.repeat(60);
    log.info('first');
    log.info(big);
    configureLogging(undefined, false);

    assert.ok(readFileSync(file, 'utf8').endsWith(big + '\n'), 'the oversized line was split or lost');
    assert.ok(readFileSync(`${file}.1`, 'utf8').endsWith('first\n'));
  });
});

describe('log policy config', () => {
  test('defaults to a 10 MB cap and five retained generations', () => {
    const { dir } = home();
    const { config } = loadConfig({ configPath: writeServers(dir, { mcpServers: {} }) });

    assert.deepEqual(config.log, { maxBytes: 10 * 1024 * 1024, keep: 5 });
    assert.deepEqual(DEFAULT_LOG_POLICY, { maxBytes: 10 * 1024 * 1024, keep: 5 });
  });

  test('reads an explicit policy, including keep 0', () => {
    const { dir } = home();
    const { config } = loadConfig({
      configPath: writeServers(dir, { mcpServers: {}, log: { maxBytes: 4096, keep: 0 } }),
    });

    assert.deepEqual(config.log, { maxBytes: 4096, keep: 0 });
  });

  test('fills the field left out of a partial log block', () => {
    const { dir } = home();
    const { config } = loadConfig({ configPath: writeServers(dir, { mcpServers: {}, log: { keep: 2 } }) });

    assert.deepEqual(config.log, { maxBytes: 10 * 1024 * 1024, keep: 2 });
  });

  test('rejects an invalid policy, naming the field that is wrong', () => {
    const cases: Array<[unknown, RegExp]> = [
      [{ maxBytes: 0 }, /log\.maxBytes must be a positive integer, got 0/],
      [{ maxBytes: -1 }, /log\.maxBytes must be a positive integer, got -1/],
      [{ maxBytes: 1.5 }, /log\.maxBytes must be a positive integer, got 1\.5/],
      [{ maxBytes: '10485760' }, /log\.maxBytes must be a positive integer, got "10485760"/],
      [{ keep: -1 }, /log\.keep must be a non-negative integer, got -1/],
      [{ keep: 2.5 }, /log\.keep must be a non-negative integer, got 2\.5/],
      [{ keep: null }, /log\.keep must be a non-negative integer, got null/],
      ['yes', /"log" must be an object/],
    ];
    for (const [value, message] of cases) {
      const { dir } = home();
      assert.throws(() => loadConfig({ configPath: writeServers(dir, { mcpServers: {}, log: value }) }), message);
    }
  });
});
