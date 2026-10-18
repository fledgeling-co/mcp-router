import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { envFilesDigest, parseDotenv, readEnvFiles, resolveEnvFiles } from '../src/envfile.js';
import { upstreamHash, type StdioUpstream } from '../src/config.js';
import { UpstreamPool } from '../src/pool.js';

const made: string[] = [];
after(() => {
  for (const d of made) rmSync(d, { recursive: true, force: true });
});

/** A temp tree of files, keyed by path relative to its root. Returns the root. */
function tree(files: Record<string, string>): string {
  const root = mkdtempSync(join(tmpdir(), 'envfile-test-'));
  made.push(root);
  for (const [rel, body] of Object.entries(files)) {
    const p = join(root, rel);
    mkdirSync(dirname(p), { recursive: true });
    writeFileSync(p, body);
  }
  return root;
}

/** The env files a stdio entry resolves to, read back as the merged values the child gets. */
function loadedFor(command: string, args: string[], cwd: string | undefined, envFile?: string | string[] | false) {
  return readEnvFiles(resolveEnvFiles(command, args, cwd, envFile));
}

describe('package root resolution', () => {
  test('cwd, when set, is the root and the script is not consulted', () => {
    const root = tree({
      'pkg/package.json': '{}',
      'pkg/.env': 'FROM=pkg',
      'other/.env': 'FROM=other',
      'pkg/dist/index.js': '',
    });
    const files = resolveEnvFiles('node', [join(root, 'pkg/dist/index.js')], join(root, 'other'), undefined);
    assert.deepEqual(files, [join(root, 'other/.env')]);
  });

  test('without cwd, the nearest manifest-holding ancestor of the script wins', () => {
    const root = tree({
      'outer/package.json': '{}',
      'outer/.env': 'FROM=outer',
      'outer/inner/package.json': '{}',
      'outer/inner/.env': 'FROM=inner',
      'outer/inner/dist/index.js': '',
    });
    const files = resolveEnvFiles('node', [join(root, 'outer/inner/dist/index.js')], undefined, undefined);
    assert.deepEqual(files, [join(root, 'outer/inner/.env')]);
  });

  test('a pyproject.toml is a manifest too', () => {
    const root = tree({
      'py/pyproject.toml': '',
      'py/.env': 'FROM=py',
      'py/bin/serve.py': '',
    });
    assert.deepEqual(resolveEnvFiles('python3', [join(root, 'py/bin/serve.py')], undefined, undefined), [
      join(root, 'py/.env'),
    ]);
  });

  test('a workspace root is never inferred, so the app secrets above a server stay out', () => {
    const root = tree({
      'mono/package.json': JSON.stringify({ workspaces: ['packages/*'] }),
      'mono/.env.local': 'APP_SECRET=do-not-load',
      'mono/packages/srv/dist/index.js': '',
    });
    assert.deepEqual(resolveEnvFiles('node', [join(root, 'mono/packages/srv/dist/index.js')], undefined, undefined), []);
  });

  test('a pnpm-workspace.yaml marker stops the walk the same way', () => {
    const root = tree({
      'pnpm/package.json': '{}',
      'pnpm/pnpm-workspace.yaml': '',
      'pnpm/.env': 'FROM=workspace',
      'pnpm/tools/run.js': '',
    });
    assert.deepEqual(resolveEnvFiles('node', [join(root, 'pnpm/tools/run.js')], undefined, undefined), []);
  });

  test('a server with its own manifest inside a workspace is still found', () => {
    const root = tree({
      'mono/package.json': JSON.stringify({ workspaces: ['packages/*'] }),
      'mono/.env.local': 'APP_SECRET=do-not-load',
      'mono/packages/srv/package.json': '{}',
      'mono/packages/srv/.env': 'FROM=srv',
      'mono/packages/srv/dist/index.js': '',
    });
    assert.deepEqual(loadedFor('node', [join(root, 'mono/packages/srv/dist/index.js')], undefined), {
      FROM: 'srv',
    });
  });

  test('the walk stops at a git root', () => {
    const root = tree({
      'repo/.git': 'gitdir: elsewhere',
      'repo/.env': 'FROM=repo',
      'repo/sub/run.js': '',
    });
    assert.deepEqual(resolveEnvFiles('node', [join(root, 'repo/sub/run.js')], undefined, undefined), []);
  });

  test('a script inside node_modules is not the entry, so its package is not loaded', () => {
    const root = tree({
      'pkg/package.json': '{}',
      'pkg/.env': 'FROM=pkg',
      'pkg/node_modules/dep/package.json': '{}',
      'pkg/node_modules/dep/.env': 'FROM=dep',
      'pkg/node_modules/dep/index.js': '',
    });
    assert.deepEqual(resolveEnvFiles('node', [join(root, 'pkg/node_modules/dep/index.js')], undefined, undefined), []);
  });
});

describe('envFile policy', () => {
  test('envFile: false loads nothing, even with .env present', () => {
    const root = tree({ 'pkg/.env': 'A=1', 'pkg/.env.local': 'B=2' });
    assert.deepEqual(resolveEnvFiles('node', [], join(root, 'pkg'), false), []);
  });

  test('the default is .env then .env.local, whichever exist', () => {
    const both = tree({ 'pkg/.env': 'A=1', 'pkg/.env.local': 'B=2' });
    assert.deepEqual(resolveEnvFiles('node', [], join(both, 'pkg'), undefined), [
      join(both, 'pkg/.env'),
      join(both, 'pkg/.env.local'),
    ]);
    const onlyLocal = tree({ 'pkg/.env.local': 'B=2' });
    assert.deepEqual(resolveEnvFiles('node', [], join(onlyLocal, 'pkg'), undefined), [
      join(onlyLocal, 'pkg/.env.local'),
    ]);
  });

  test('.env.local overrides .env key by key and keeps the keys only .env sets', () => {
    const root = tree({ 'pkg/.env': 'KEY=base\nONLY_BASE=1', 'pkg/.env.local': 'KEY=local' });
    assert.deepEqual(loadedFor('node', [], join(root, 'pkg')), { KEY: 'local', ONLY_BASE: '1' });
  });

  test('an explicit path is resolved against the package root and replaces the defaults', () => {
    const root = tree({ 'pkg/.env': 'A=default', 'pkg/config/prod.env': 'A=prod' });
    assert.deepEqual(resolveEnvFiles('node', [], join(root, 'pkg'), 'config/prod.env'), [
      join(root, 'pkg/config/prod.env'),
    ]);
    assert.deepEqual(loadedFor('node', [], join(root, 'pkg'), 'config/prod.env'), { A: 'prod' });
  });

  test('an absolute explicit path is kept as given', () => {
    const root = tree({ 'elsewhere/x.env': 'A=1' });
    const abs = join(root, 'elsewhere/x.env');
    assert.deepEqual(resolveEnvFiles('node', [], join(root, 'pkg'), abs), [abs]);
  });

  test('a list is loaded in order, later files winning', () => {
    const root = tree({ 'pkg/a.env': 'KEY=a\nA_ONLY=1', 'pkg/b.env': 'KEY=b' });
    assert.deepEqual(loadedFor('node', [], join(root, 'pkg'), ['a.env', 'b.env']), { KEY: 'b', A_ONLY: '1' });
  });

  test('a declared file that is missing is an error, not a silent skip', () => {
    const root = tree({ 'pkg/.env': 'A=1' });
    assert.throws(() => loadedFor('node', [], join(root, 'pkg'), 'missing.env'), /env file not found/);
  });
});

describe('spawn environment', () => {
  // `pool.buildEnv` is private; bracket access is how a test reaches it without changing the class.
  const pool = new UpstreamPool(new Map(), 1000, 1000);
  const stdio = (env: Record<string, string>, envFiles: string[]): StdioUpstream => ({
    transport: 'stdio',
    name: 'srv',
    command: 'node',
    args: [],
    env,
    envFiles,
  });

  test('the entry env wins over the env files, and file-only keys still reach the child', () => {
    const root = tree({ 'pkg/.env': 'KEY=file\nFILE_ONLY=1' });
    const u = stdio({ KEY: 'entry' }, [join(root, 'pkg/.env')]);
    const env = pool['buildEnv'](u);
    assert.equal(env.KEY, 'entry');
    assert.equal(env.FILE_ONLY, '1');
  });

  test('with no entry override, the file value is what the child gets', () => {
    const root = tree({ 'pkg/.env': 'KEY=file' });
    const env = pool['buildEnv'](stdio({}, [join(root, 'pkg/.env')]));
    assert.equal(env.KEY, 'file');
  });
});

describe('envFilesDigest and the config hash', () => {
  test('the digest follows the file contents and returns when they return', () => {
    const root = tree({ 'pkg/.env': 'KEY=1' });
    const f = join(root, 'pkg/.env');
    const before = envFilesDigest([f]);
    writeFileSync(f, 'KEY=2');
    const rotated = envFilesDigest([f]);
    assert.notEqual(rotated, before);
    writeFileSync(f, 'KEY=1');
    assert.equal(envFilesDigest([f]), before);
  });

  test('a file that appears or disappears changes the digest', () => {
    const root = tree({ 'pkg/.env': 'KEY=1' });
    const present = join(root, 'pkg/.env');
    const absent = join(root, 'pkg/.env.local');
    assert.notEqual(envFilesDigest([absent]), envFilesDigest([present]));
  });

  test("an upstream's config hash changes when its env file's contents change", () => {
    const root = tree({ 'pkg/.env': 'KEY=1' });
    const f = join(root, 'pkg/.env');
    const u: StdioUpstream = { transport: 'stdio', name: 'srv', command: 'node', args: [], env: {}, envFiles: [f] };
    const before = upstreamHash(u);
    writeFileSync(f, 'KEY=2');
    assert.notEqual(upstreamHash(u), before);
  });
});

describe('parseDotenv', () => {
  test('handles export, quotes, comments and \\n escapes', () => {
    const text = [
      '# a comment',
      'export A=1',
      'B="two words"',
      "C='single #kept'",
      'D=x # trailing comment dropped',
      'E="line\\nbreak"',
      '',
    ].join('\n');
    assert.deepEqual(parseDotenv(text), {
      A: '1',
      B: 'two words',
      C: 'single #kept',
      D: 'x',
      E: 'line\nbreak',
    });
  });
});
