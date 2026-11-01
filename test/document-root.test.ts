import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { parseServer, upstreamHash } from '../src/config.js';
import { readPackageDocuments } from '../src/document.js';
import { buildExport } from '../src/export.js';
import { handleControl, type ControlDeps } from '../src/control.js';

const root = mkdtempSync(join(tmpdir(), 'mcpr-document-root-'));
after(() => rmSync(root, { recursive: true, force: true }));
const pkg = join(root, 'package');
const cwd = join(root, 'work');
mkdirSync(pkg); mkdirSync(cwd);
writeFileSync(join(pkg, 'README.md'), 'Package documentation');
writeFileSync(join(cwd, 'README.md'), 'Working directory');

test('documentation root is explicit, absolute and separate from process and cache identity', () => {
  const raw = { command: process.execPath, args: ['server.mjs'], cwd };
  const plain = parseServer('example', raw);
  const rooted = parseServer('example', { ...raw, packageRoot: pkg });
  assert.ok('upstream' in plain && 'upstream' in rooted);
  assert.equal(rooted.upstream.transport, 'stdio');
  if (rooted.upstream.transport !== 'stdio') return;
  assert.equal(rooted.upstream.cwd, cwd);
  assert.equal(rooted.upstream.packageRoot, pkg);
  assert.deepEqual(rooted.upstream.envFiles, plain.upstream.transport === 'stdio' ? plain.upstream.envFiles : []);
  assert.equal(upstreamHash(rooted.upstream), upstreamHash(plain.upstream));
  for (const bad of ['', 'relative/package', 42]) {
    assert.ok('reason' in parseServer('bad', { ...raw, packageRoot: bad as string }));
  }
  assert.ok('reason' in parseServer('http', { type: 'http', url: 'https://example.com/mcp', packageRoot: pkg }));
  assert.equal(buildExport({ example: { ...raw, packageRoot: pkg } }, 'token').mcpServers.example.packageRoot, pkg);
});

test('document route prefers the explicit root and keeps undeclared packages unavailable', async () => {
  async function request(raw: Parameters<typeof parseServer>[1]) {
    const parsed = parseServer('example', raw);
    assert.ok('upstream' in parsed);
    let status = 0; let text = '';
    const deps = {
      upstreams: new Map([['example', parsed.upstream]]),
      manifest: { current: () => ({ servers: {} }) },
    } as unknown as ControlDeps;
    await handleControl(
      { method: 'GET', headers: {} } as IncomingMessage,
      { writeHead: (n: number) => { status = n; }, end: (s: string) => { text = s; } } as unknown as ServerResponse,
      new URL('http://127.0.0.1/servers/example/document'), undefined, deps, 'token'
    );
    return { status, body: JSON.parse(text) };
  }
  const served = await request({ command: 'node', cwd, packageRoot: pkg });
  assert.equal(served.status, 200);
  assert.equal(served.body.documents.readMe, 'Package documentation');
  const fallback = await request({ command: 'node', cwd });
  assert.equal(fallback.body.documents.readMe, 'Working directory');
  const none = await request({ command: 'node', args: [join(pkg, 'index.js')] });
  assert.equal(none.status, 404);
  assert.equal(none.body.reason, 'noPackageDirectory');
});

test('fixed document names cannot follow symlinks outside the declared package', () => {
  const escaped = join(root, 'escaped'); mkdirSync(escaped);
  const outside = join(root, 'private.txt'); writeFileSync(outside, 'private bytes');
  symlinkSync(outside, join(escaped, 'README.md'));
  const refused = readPackageDocuments(escaped);
  assert.ok('reason' in refused);
  assert.equal(refused.reason, 'escapesPackage');
  assert.equal(JSON.stringify(refused).includes('private bytes'), false);
  const missing = readPackageDocuments(join(root, 'gone'));
  assert.ok('reason' in missing);
  assert.equal(missing.reason, 'packageUnreadable');
});
