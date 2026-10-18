import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isStdio, parseServer, type RawServer, type UpstreamConfig } from '../src/config.js';
import { collectNeedles, redactArgs, type Needle } from '../src/secrets.js';

// Compiled to `build-test/test/`, so two levels up is the checkout.
const here = dirname(fileURLToPath(import.meta.url));
const VECTORS = join(here, '..', '..', 'app', 'Tests', 'RouterCoreTests', 'Vectors', 'argv-redact.json');

const CONTROL = 'ctl_0123456789abcdef';

function upstreamsOf(servers: Record<string, RawServer>): UpstreamConfig[] {
  return Object.entries(servers).flatMap(([name, raw]) => {
    const parsed = parseServer(name, raw);
    return 'upstream' in parsed ? [parsed.upstream] : [];
  });
}

// The corpus the Swift suite reads. Both sides check the same file, so a rule that moves in one
// language and not the other fails here or there.
test('every shared argv vector matches the reference rule', () => {
  const { cases } = JSON.parse(readFileSync(VECTORS, 'utf8')) as {
    cases: { id: string; servers: Record<string, RawServer>; target: string; token: string; expected: unknown }[];
  };
  assert.ok(cases.length > 0, 'the argv corpus is empty');
  for (const c of cases) {
    const upstreams = upstreamsOf(c.servers);
    const target = upstreams.find((u) => u.name === c.target);
    assert.ok(target && isStdio(target), `${c.id}: no stdio target server`);
    assert.deepEqual(redactArgs(target.args, collectNeedles(upstreams, c.token)), c.expected, c.id);
  }
});

test('a secret-named flag keeps its name and loses its value', () => {
  assert.deepEqual(redactArgs(['--token=abcdef123456'], []), ['--token=<redacted>']);
  assert.deepEqual(redactArgs(['--api-key', 'sk-live-0123456789'], []), ['--api-key', '<redacted>']);
});

test('a flag whose next argument is another flag leaves both as they were', () => {
  assert.deepEqual(redactArgs(['--token', '--verbose'], []), ['--token', '--verbose']);
  assert.deepEqual(redactArgs(['--token'], []), ['--token']);
});

test('a word that merely contains a secret word is kept', () => {
  assert.deepEqual(redactArgs(['--monkey=banana', '--port=8080'], []), ['--monkey=banana', '--port=8080']);
});

test('a URL keeps its user and loses its password, or its whole userinfo when there is no password', () => {
  assert.deepEqual(
    redactArgs(['postgres://alice:s3cr3tpass@db.internal:5432/app'], []),
    ['postgres://alice:<redacted>@db.internal:5432/app'],
  );
  assert.deepEqual(
    redactArgs(['https://ghp_0123456789abcdef@github.com/acme/x.git'], []),
    ['https://<redacted>@github.com/acme/x.git'],
  );
});

test('a non-string value after a secret flag is replaced, and other non-strings are kept', () => {
  assert.deepEqual(redactArgs(['--token', 12345678], []), ['--token', '<redacted>']);
  assert.deepEqual(redactArgs([1, 2], []), [1, 2]);
});

test('a literal needle is removed wherever it appears, and labelled with its config key', () => {
  const needles: Needle[] = collectNeedles(
    upstreamsOf({ a: { command: 'x', env: { K: 'ghp_0123456789abcdef' } }, b: { command: 'y' } }),
    CONTROL,
  );
  assert.deepEqual(redactArgs(['--x=ghp_0123456789abcdef'], needles), ['--x=<redacted:a.env.K>']);
});

test('a string args value is one argument, and a non-array non-string value is passed through', () => {
  assert.equal(redactArgs('--token=abcdef123456', []), '--token=<redacted>');
  assert.equal(redactArgs(5, []), 5);
});

test('the needle set holds the control token and env values of eight graphemes or more', () => {
  const needles = collectNeedles(
    upstreamsOf({ a: { command: 'x', env: { LONG: 'abcdefgh', SHORT: '1234567' } } }),
    CONTROL,
  );
  assert.deepEqual(
    needles.map((n) => n.label),
    ['a.env.LONG', 'control.token'],
  );
});
