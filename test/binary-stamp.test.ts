import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, statSync, utimesSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { binaryStamp, upstreamHash, type StdioUpstream, type UpstreamConfig } from '../src/config.js';
import { isStale, type Manifest } from '../src/manifest.js';

const made: string[] = [];
after(() => {
  for (const d of made) rmSync(d, { recursive: true, force: true });
});

const T0 = new Date('2026-01-01T00:00:00Z');
const T1 = new Date('2026-01-01T00:01:00Z');

/** A binary at a known path, with its mtime pinned so that a rewrite is visible only where we say. */
function binary(body: string): string {
  const dir = mkdtempSync(join(tmpdir(), 'stamp-test-'));
  made.push(dir);
  const p = join(dir, 'server');
  writeFileSync(p, body);
  utimesSync(p, T0, T0);
  return p;
}

function stdio(command: string, args: string[] = []): StdioUpstream {
  return { transport: 'stdio', name: 'srv', command, args, env: {}, envFiles: [] };
}

/** A manifest holding one entry for `u`, with `bin` omitted when the argument is undefined. */
function manifestFor(u: UpstreamConfig, bin?: string): Manifest {
  return {
    version: 1,
    servers: {
      srv: {
        hash: upstreamHash(u),
        ...(bin === undefined ? {} : { bin }),
        builtAt: '2026-01-01T00:00:00Z',
        tools: [],
      },
    },
  };
}

describe('binaryStamp', () => {
  test('is empty for an HTTP upstream', () => {
    const u: UpstreamConfig = { transport: 'http', name: 'srv', url: 'http://127.0.0.1:9', headers: {} };
    assert.equal(binaryStamp(u), '');
  });

  test('is empty when the command is a bare name with no absolute path to stamp', () => {
    assert.equal(binaryStamp(stdio('node', ['index.js'])), '');
  });

  test('a path that cannot be stat-ed contributes nothing and does not throw', () => {
    assert.equal(binaryStamp(stdio('/nonexistent/router-test/server')), '');
  });

  test('is stable while the file is untouched', () => {
    const p = binary('v1');
    assert.equal(binaryStamp(stdio(p)), binaryStamp(stdio(p)));
  });

  test('changes when the size changes', () => {
    const p = binary('v1');
    const before = binaryStamp(stdio(p));
    writeFileSync(p, 'v1-and-more');
    utimesSync(p, T0, T0);
    assert.notEqual(binaryStamp(stdio(p)), before);
  });

  test('changes when only the mtime changes', () => {
    const p = binary('v1');
    const before = binaryStamp(stdio(p));
    writeFileSync(p, 'v2'); // same size as 'v1'
    utimesSync(p, T1, T1);
    assert.equal(statSync(p).size, 2);
    assert.notEqual(binaryStamp(stdio(p)), before);
  });

  test('stamps the script behind an interpreter, not only the interpreter', () => {
    const script = binary('console.log(1)');
    const before = binaryStamp(stdio('node', [script]));
    assert.notEqual(before, '');
    writeFileSync(script, 'console.log(2222)');
    utimesSync(script, T0, T0);
    assert.notEqual(binaryStamp(stdio('node', [script])), before);
  });
});

describe('isStale and the replaced binary', () => {
  test('an entry matching the config and the binary is fresh', () => {
    const u = stdio(binary('v1'));
    assert.equal(isStale(manifestFor(u, binaryStamp(u)), u), false);
  });

  test('an executable replaced in place is stale even though the config is unchanged', () => {
    const u = stdio(binary('v1'));
    const m = manifestFor(u, binaryStamp(u));
    writeFileSync(u.command, 'v1-rebuilt-and-larger');
    utimesSync(u.command, T1, T1);
    assert.equal(isStale(m, u), true);
  });

  test('a same-size rebuild at a new mtime is stale', () => {
    const u = stdio(binary('v1'));
    const m = manifestFor(u, binaryStamp(u));
    writeFileSync(u.command, 'v2');
    utimesSync(u.command, T1, T1);
    assert.equal(isStale(m, u), true);
  });

  test('an entry written before the field existed is re-read once, then trusted', () => {
    const u = stdio(binary('v1'));
    const legacy = manifestFor(u);
    assert.equal(isStale(legacy, u), true);
    assert.equal(isStale(manifestFor(u, binaryStamp(u)), u), false);
  });

  test('a changed command or args is stale', () => {
    const u = stdio(binary('v1'));
    const m = manifestFor(u, binaryStamp(u));
    assert.equal(isStale(m, { ...u, args: ['--other'] }), true);
  });

  test('an entry that recorded an error is stale', () => {
    const u = stdio(binary('v1'));
    const m = manifestFor(u, binaryStamp(u));
    m.servers.srv.error = 'spawn failed';
    assert.equal(isStale(m, u), true);
  });
});
