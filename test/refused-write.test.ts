import { toolsDigest, toolApprovalDigest, diffTools } from '../src/manifest.js';
import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { ControlDeps } from '../src/control.js';
import type { RouterConfig, UpstreamConfig } from '../src/config.js';

/*
 * A refused manifest write must be a failure the caller sees. The scenarios use a real read-only
 * directory rather than a mocked error, so the refusal is the filesystem's own.
 *
 * Root ignores directory permissions, so the denial cases cannot mean anything there and are skipped.
 */
const denial = process.getuid?.() === 0 ? test.skip : test;

const made: string[] = [];
after(() => {
  for (const d of made) {
    try {
      chmodSync(d, 0o755);
    } catch {
      /* already removed */
    }
    rmSync(d, { recursive: true, force: true });
  }
});

function scratch(): string {
  const d = mkdtempSync(join(tmpdir(), 'refused-write-'));
  made.push(d);
  return d;
}

/*
 * The router home must be set before control.ts loads, because it reads the sessions flag from
 * the home's servers.json. Without this, an approve that succeeds would read the operator's own
 * config and could ask live sessions to reload.
 */
const approveHome = scratch();
process.env.MCP_ROUTER_HOME = approveHome;
const { handleControl } = await import('../src/control.js');

const ENTRY = fileURLToPath(new URL('../src/index.js', import.meta.url));
const SERVERS_JSON = JSON.stringify({ mcpServers: { broken: { command: '/nonexistent/bin/none', args: [] } } });

function runIndex(home: string, args: string[] = []) {
  return spawnSync(process.execPath, [ENTRY, 'index', ...args], {
    env: { ...process.env, MCP_ROUTER_HOME: home },
    encoding: 'utf8',
    timeout: 60_000,
  });
}

describe('mcp-router index when the manifest write is refused', () => {
  test('a writable home indexes and reports the cached row', () => {
    const home = scratch();
    writeFileSync(join(home, 'servers.json'), SERVERS_JSON);
    const r = runIndex(home);
    assert.equal(r.status, 0, r.stderr);
    assert.match(r.stdout, /tools cached -> /);
  });

  denial('exits 1 naming the manifest path and the OS error, and prints no success summary', () => {
    const home = scratch();
    writeFileSync(join(home, 'servers.json'), SERVERS_JSON);
    // The first run writes the manifest and creates the lock sidecar, so the denied run can still
    // take the lock and reach the write it is meant to be refused.
    assert.equal(runIndex(home).status, 0);
    const before = readFileSync(join(home, 'manifest.json'), 'utf8');

    chmodSync(home, 0o555);
    const r = runIndex(home, ['--force']);

    assert.equal(r.status, 1, r.stdout);
    assert.match(r.stderr, /EACCES: permission denied, open '[^']*manifest\.json/);
    assert.doesNotMatch(r.stdout, /tools cached|All upstreams closed/);
    assert.equal(readFileSync(join(home, 'manifest.json'), 'utf8'), before);
  });
});

const TOKEN = 'test-token';
const NEW_TOOL = { name: 'new_tool', description: 'arrived after approval', inputSchema: { type: 'object' as const } };

function writePendingManifest(home: string): string {
  const path = join(home, 'manifest.json');
  writeFileSync(
    path,
    JSON.stringify(
      {
        version: 1,
        servers: {
          broken: {
            hash: 'h',
            builtAt: '2026-10-01T00:00:00.000Z',
            tools: [],
            digest: 'old',
            pending: { tools: [NEW_TOOL], digest: 'new', seenAt: '2026-10-02T00:00:00.000Z' },
          },
        },
      },
      null,
      2
    )
  );
  return path;
}

/** Drive the approve route in-process and capture what it answered and what it announced. */
const TEST_UPSTREAM = { name: 'broken', transport: 'stdio' as const, command: 'x', args: [], env: {}, envFiles: [] };
async function approve(manifestPath: string, expectedDigest?: unknown) {
  if (expectedDigest === undefined) {
    expectedDigest = toolApprovalDigest(TEST_UPSTREAM, JSON.parse(readFileSync(manifestPath, 'utf8')).servers.broken);
  }
  const announced: string[] = [];
  const deps = {
    cfg: { manifestPath } as unknown as RouterConfig,
    upstreams: new Map([['broken', TEST_UPSTREAM]]),
    pool: {} as ControlDeps['pool'],
    manifest: { fileStamp: () => 'stamp' } as unknown as ControlDeps['manifest'],
    usage: {} as ControlDeps['usage'],
    liveReload: {
      announceToolsChanged: async (reason: string) => {
        announced.push(reason);
      },
    } as unknown as ControlDeps['liveReload'],
  };
  const captured = { status: 0, body: undefined as { error?: string; server?: string; approved?: number } | undefined };
  const res = {
    writeHead(status: number) {
      captured.status = status;
    },
    end(payload: string) {
      captured.body = JSON.parse(payload);
    },
  } as unknown as ServerResponse;
  const req = {
    method: 'POST',
    headers: { authorization: `Bearer ${TOKEN}`, 'content-type': 'application/json' },
  } as unknown as IncomingMessage;

  const handled = await handleControl(
    req,
    res,
    new URL('http://127.0.0.1/servers/broken/approve'),
    expectedDigest === null ? {} : { expectedDigest },
    deps as unknown as ControlDeps,
    TOKEN
  );
  assert.equal(handled, true);
  return { ...captured, announced };
}

describe('POST /servers/:name/approve when the manifest write is refused', () => {
  test('a writable home answers 200 and promotes the pending surface', async () => {
    const home = scratch();
    const path = writePendingManifest(home);
    const r = await approve(path);
    assert.equal(r.status, 200);
    assert.deepEqual(r.body, { server: 'broken', approved: 1 });
    const saved = JSON.parse(readFileSync(path, 'utf8'));
    assert.equal(saved.servers.broken.pending, undefined);
    assert.equal(saved.servers.broken.tools.length, 1);
    assert.deepEqual(r.announced, ["approved \"broken\"'s new tool surface"]);
  });

  denial('answers 500 naming the refusal, keeps the pending row, and announces nothing', async () => {
    const home = scratch();
    const path = writePendingManifest(home);
    // The lock sidecar must already exist, so the refusal comes from the manifest write rather than
    // from creating the lock inside the read-only directory.
    writeFileSync(`${path}.lock`, '', { mode: 0o600 });
    const before = readFileSync(path, 'utf8');

    chmodSync(home, 0o555);
    const r = await approve(path);

    assert.equal(r.status, 500);
    assert.match(r.body?.error ?? '', /EACCES: permission denied, open '[^']*manifest\.json/);
    assert.equal(r.body?.server, undefined);
    assert.equal(readFileSync(path, 'utf8'), before);
    assert.deepEqual(r.announced, []);
  });
});


test('approve requires the exact reviewed digest and never promotes a replacement surface', async () => {
  const path = writePendingManifest(scratch());
  const before = readFileSync(path, 'utf8');
  const missing = await approve(path, null);
  assert.equal(missing.status, 428);
  assert.equal(readFileSync(path, 'utf8'), before);
  const replaced = await approve(path, '0'.repeat(64));
  assert.equal(replaced.status, 409);
  assert.equal(readFileSync(path, 'utf8'), before);
  assert.deepEqual(replaced.announced, []);
});


test('review tokens bind complete metadata, approved baseline and declaration identity', () => {
  const tool = { ...NEW_TOOL, annotations: { readOnlyHint: true } };
  const changed = { ...tool, annotations: { readOnlyHint: false } };
  assert.notEqual(toolsDigest([tool]), toolsDigest([changed]));
  assert.equal(diffTools([tool], [changed]).length, 1);
  assert.match(diffTools([tool], [changed])[0].after!.schema!, /readOnlyHint/);
  const entry = { hash: 'h', builtAt: 'now', tools: [], pending: { tools: [tool], digest: 'd', seenAt: 'now' } };
  const reviewed = toolApprovalDigest(TEST_UPSTREAM, entry);
  assert.notEqual(reviewed, toolApprovalDigest(TEST_UPSTREAM, { ...entry, tools: [NEW_TOOL] }));
  assert.notEqual(reviewed, toolApprovalDigest({ ...TEST_UPSTREAM, env: { MODE: 'different' } }, entry));
  assert.notEqual(reviewed, toolApprovalDigest(TEST_UPSTREAM, { ...entry, pending: { ...entry.pending, tools: [changed] } }));
  assert.equal(toolsDigest([NEW_TOOL]), toolsDigest([{ inputSchema: { type: 'object' }, description: NEW_TOOL.description, name: NEW_TOOL.name }]));
});
