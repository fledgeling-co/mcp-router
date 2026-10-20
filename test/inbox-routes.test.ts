import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { IncomingMessage, ServerResponse } from 'node:http';
import type { ControlDeps } from '../src/control.js';
import type { RouterConfig, UpstreamConfig } from '../src/config.js';
import type { RegistryEntry } from '../src/registry.js';
import { InboxStore, reviewDigestOf } from '../src/inbox.js';

/*
 * The /inbox family, through handleControl (planning/plans/plan-phone-inbox.md §2.3, §2.4, §5). IB1 served the
 * read. IB6 adds accept, decline and restore, and an accept declares the server through the same code path
 * POST /servers uses, so the POST cases at the end pin the route that now shares it.
 *
 * The router home is set before control.ts loads, because config.ts reads it at import. servers.json lives in
 * that home, so each test puts it in the state it needs before it starts.
 */
const made: string[] = [];
after(() => {
  for (const d of made) rmSync(d, { recursive: true, force: true });
});

const home = mkdtempSync(join(tmpdir(), 'inbox-routes-home-'));
made.push(home);
process.env.MCP_ROUTER_HOME = home;

const { handleControl } = await import('../src/control.js');

const TOKEN = 'test-token';
const PHONE_ID = 'phone-id-that-must-not-leave-the-router';
const SERVERS = join(home, 'servers.json');

const MANIFEST_DIR = mkdtempSync(join(tmpdir(), 'inbox-routes-manifest-'));
made.push(MANIFEST_DIR);

/*
 * A stdio server that answers the handshake and one tool, so the real index can run it. It needs no package and
 * no network, which is why it is a `node -e` script and not an npx line.
 */
const FIXTURE_SCRIPT = `
const readline = require('node:readline');
readline.createInterface({ input: process.stdin }).on('line', (line) => {
  const m = JSON.parse(line);
  if (m.id === undefined) return;
  const result =
    m.method === 'initialize'
      ? { protocolVersion: m.params.protocolVersion, capabilities: { tools: {} }, serverInfo: { name: 'fixture', version: '1.0.0' } }
      : m.method === 'tools/list'
        ? { tools: [{ name: 'echo', inputSchema: { type: 'object' } }] }
        : {};
  process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id: m.id, result }) + '\\n');
});
`;
const FIXTURE_ARGS = ['-e', FIXTURE_SCRIPT];

const UPSTREAMS = new Map<string, UpstreamConfig>();

/** A registry entry for `alpha`, installed by the fixture unless the test names another install. */
function alpha(install: RegistryEntry['install'] = { type: 'stdio', command: process.execPath, args: FIXTURE_ARGS }): RegistryEntry {
  return { id: 'io.example/alpha', name: 'alpha', displayName: 'Alpha', description: 'a test', source: 'official', install };
}

/** A store under its own scratch directory, holding one waiting row for `resolved` from a confirmed phone. */
function storeWith(resolved: RegistryEntry | null): InboxStore {
  const parent = mkdtempSync(join(tmpdir(), 'inbox-routes-'));
  made.push(parent);
  const store = new InboxStore(join(parent, 'inbox.json'));
  store.add({
    id: 'io.example/alpha',
    phoneId: PHONE_ID,
    deviceName: "Luke's iPhone",
    queuedAt: '2026-10-19T10:00:00Z',
    receivedAt: '2026-10-19T10:00:05Z',
    resolved,
  });
  return store;
}

function seededStore(): InboxStore {
  return storeWith(alpha());
}

/** Put servers.json in the state a test starts from: absent, or holding exactly these servers. */
function resetServers(servers?: Record<string, unknown>): void {
  if (servers === undefined) rmSync(SERVERS, { force: true });
  else writeFileSync(SERVERS, JSON.stringify({ mcpServers: servers }, null, 2));
}

type Declared = Record<string, { command?: string; args?: string[]; url?: string; type?: string; name?: string }>;

function declaredServers(): Declared {
  return (JSON.parse(readFileSync(SERVERS, 'utf8')) as { mcpServers: Declared }).mcpServers;
}

const rowPath = (verb: string, id = 'io.example/alpha') => `/inbox/${encodeURIComponent(id)}/${verb}`;

/**
 * The deps an accept needs: a live upstream map that reload keeps current, a manifest path the index can write,
 * and stubs for what a declaration announces. The pool is a stub because the index only adopts from it when it
 * holds a pending entry, and none of these tests produce one.
 */
function routeDeps(inbox: InboxStore, upstreams = new Map<string, UpstreamConfig>()): Partial<ControlDeps> {
  return {
    inbox,
    upstreams,
    cfg: { manifestPath: join(MANIFEST_DIR, 'manifest.json'), startupTimeoutMs: 10_000, upstreams: [] } as unknown as RouterConfig,
    pool: { pending: () => [], adoptPending: () => undefined } as unknown as ControlDeps['pool'],
    manifest: { fileStamp: () => 'stamp' } as unknown as ControlDeps['manifest'],
    liveReload: { announceToolsChanged: async () => undefined } as unknown as ControlDeps['liveReload'],
  };
}

interface Call {
  method: string;
  path: string;
  body?: unknown;
  token?: string | null;
  contentType?: string;
}

/** Drive one request through handleControl and capture what it answered. */
async function answer(call: Call, deps: Partial<ControlDeps>): Promise<{ status: number; text: string; json: unknown }> {
  const headers: Record<string, string> = { 'content-type': call.contentType ?? 'application/json' };
  if (call.token !== null) headers['x-mcpr-token'] = call.token ?? TOKEN;
  const req = { method: call.method, headers } as unknown as IncomingMessage;

  let status = 0;
  let text = '';
  const res = {
    writeHead(code: number) {
      status = code;
    },
    end(payload: string) {
      text = payload;
    },
  } as unknown as ServerResponse;

  const url = new URL(call.path, 'http://127.0.0.1:8879');
  const handled = await handleControl(
    req,
    res,
    url,
    call.body,
    { upstreams: UPSTREAMS, ...deps } as unknown as ControlDeps,
    TOKEN
  );
  assert.equal(handled, true, `${call.method} ${call.path} was not claimed by the control API`);
  return { status, text, json: text ? JSON.parse(text) : undefined };
}

/** The body an accept sends: the digest the reviewer was shown, which is the row's stored one. */
const acceptBody = (store: InboxStore) => ({ reviewDigest: store.rows()[0].reviewDigest });

test('GET /inbox refuses without the token, and with a wrong one', async () => {
  const deps = { inbox: seededStore() };
  const none = await answer({ method: 'GET', path: '/inbox', token: null }, deps);
  assert.equal(none.status, 401);
  assert.equal(none.text.includes('io.example/alpha'), false, 'a refusal names no row');

  const wrong = await answer({ method: 'GET', path: '/inbox', token: 'not-the-token' }, deps);
  assert.equal(wrong.status, 401);
});

test('GET /inbox with the token lists the rows, and never names the phone id', async () => {
  const deps = { inbox: seededStore() };
  const listed = await answer({ method: 'GET', path: '/inbox' }, deps);

  assert.equal(listed.status, 200);
  const body = listed.json as { items: Array<Record<string, unknown>> };
  assert.equal(body.items.length, 1);
  assert.deepEqual(Object.keys(body.items[0]).sort(), ['deviceName', 'id', 'queuedAt', 'resolved', 'reviewDigest', 'state']);
  assert.equal(body.items[0].state, 'waiting');
  assert.equal(body.items[0].deviceName, "Luke's iPhone");
  assert.equal(listed.text.includes(PHONE_ID), false, 'the phone id must not appear anywhere in the answer');
});

test('GET /inbox answers an empty list when nothing has been held', async () => {
  const parent = mkdtempSync(join(tmpdir(), 'inbox-routes-empty-'));
  made.push(parent);
  const listed = await answer({ method: 'GET', path: '/inbox' }, { inbox: new InboxStore(join(parent, 'inbox.json')) });
  assert.deepEqual(listed.json, { items: [] });
});

test('GET /inbox answers 500 when inbox.json is unreadable, and never an empty list', async () => {
  const parent = mkdtempSync(join(tmpdir(), 'inbox-routes-corrupt-'));
  made.push(parent);
  const path = join(parent, 'inbox.json');
  writeFileSync(path, '{ not json');

  const listed = await answer({ method: 'GET', path: '/inbox' }, { inbox: new InboxStore(path) });
  assert.equal(listed.status, 500);
  assert.equal((listed.json as { items?: unknown }).items, undefined, 'an unreadable store is not an empty inbox');
});

test('POST /inbox has no submit path yet, and an action answers 405 to a GET', async () => {
  const deps = { inbox: seededStore() };

  const posted = await answer({ method: 'POST', path: '/inbox', body: {} }, deps);
  assert.equal(posted.status, 405, 'the submit path is IB4');

  const read = await answer({ method: 'GET', path: rowPath('accept') }, deps);
  assert.equal(read.status, 405, 'an action is a POST');

  const refused = await answer({ method: 'POST', path: '/inbox', body: {}, token: null }, deps);
  assert.equal(refused.status, 401);
});

test('with no store wired, /inbox answers 503 rather than an empty inbox', async () => {
  const listed = await answer({ method: 'GET', path: '/inbox' }, {});
  assert.equal(listed.status, 503);
});

test('accept, decline and restore refuse without the token, and change nothing', async () => {
  resetServers();
  const inbox = seededStore();
  const before = readFileSync(inbox.path, 'utf8');

  for (const verb of ['accept', 'decline', 'restore']) {
    const refused = await answer(
      { method: 'POST', path: rowPath(verb), body: acceptBody(inbox), token: null },
      routeDeps(inbox)
    );
    assert.equal(refused.status, 401, verb);
  }
  assert.equal(readFileSync(inbox.path, 'utf8'), before);
  assert.equal(existsSync(SERVERS), false, 'a refusal declares nothing');
});

test('an accept sent without a JSON content type answers 415, and declares nothing', async () => {
  resetServers();
  const inbox = seededStore();

  const refused = await answer(
    { method: 'POST', path: rowPath('accept'), body: acceptBody(inbox), contentType: 'text/plain' },
    routeDeps(inbox)
  );
  assert.equal(refused.status, 415);
  assert.equal(inbox.rows()[0].state, 'waiting');
  assert.equal(existsSync(SERVERS), false);
});

test('accept refuses a reviewDigest that is not the stored one, and declares nothing', async () => {
  resetServers();
  const inbox = seededStore();
  const before = readFileSync(inbox.path, 'utf8');

  const replaced = await answer(
    { method: 'POST', path: rowPath('accept'), body: { reviewDigest: '0'.repeat(64) } },
    routeDeps(inbox)
  );
  assert.equal(replaced.status, 409);
  assert.equal((replaced.json as { reason: string }).reason, 'reviewChanged');
  assert.equal(readFileSync(inbox.path, 'utf8'), before);
  assert.equal(existsSync(SERVERS), false);
});

test('accept refuses a Partial row, which has nothing to declare', async () => {
  resetServers();
  const inbox = storeWith(null);
  assert.equal(inbox.rows()[0].reviewDigest, reviewDigestOf(null));

  const partial = await answer({ method: 'POST', path: rowPath('accept'), body: acceptBody(inbox) }, routeDeps(inbox));
  assert.equal(partial.status, 422);
  assert.equal((partial.json as { reason: string }).reason, 'unresolved');
  assert.equal(inbox.rows()[0].state, 'waiting');
  assert.equal(existsSync(SERVERS), false);
});

test('accept refuses an entry that needs a value the phone cannot supply, and declares nothing', async () => {
  resetServers();
  const inbox = storeWith(
    alpha({ type: 'http', url: 'https://example.com/mcp', requires: [{ name: 'Authorization', isSecret: true }] })
  );

  const refused = await answer({ method: 'POST', path: rowPath('accept'), body: acceptBody(inbox) }, routeDeps(inbox));
  assert.equal(refused.status, 422);
  assert.equal((refused.json as { reason: string }).reason, 'needsCredentials');
  assert.equal(inbox.rows()[0].state, 'waiting');
  assert.equal(existsSync(SERVERS), false);
});

test('accept refuses an entry that says nothing about how to run it', async () => {
  resetServers();
  const inbox = storeWith({ ...alpha(), install: undefined });

  const refused = await answer({ method: 'POST', path: rowPath('accept'), body: acceptBody(inbox) }, routeDeps(inbox));
  assert.equal(refused.status, 422);
  assert.equal((refused.json as { reason: string }).reason, 'notInstallable');
  assert.equal(existsSync(SERVERS), false);
});

test('accept declares the server once, marks the row accepted, and refuses a second accept', async () => {
  resetServers({});
  const inbox = seededStore();
  const deps = routeDeps(inbox);

  const first = await answer({ method: 'POST', path: rowPath('accept'), body: acceptBody(inbox) }, deps);
  assert.equal(first.status, 200, first.text);
  assert.equal(inbox.rows()[0].state, 'accepted');
  assert.deepEqual(Object.keys(declaredServers()), ['alpha']);
  assert.equal(declaredServers().alpha.command, process.execPath);
  assert.deepEqual(declaredServers().alpha.args, FIXTURE_ARGS);
  assert.equal(declaredServers().alpha.name, undefined, 'the name is the key, not a field of the entry');
  assert.equal(deps.upstreams?.has('alpha'), true, 'the live map sees the declaration');

  const second = await answer({ method: 'POST', path: rowPath('accept'), body: acceptBody(inbox) }, deps);
  assert.equal(second.status, 409);
  assert.equal((second.json as { reason: string }).reason, 'notWaiting');
  assert.deepEqual(Object.keys(declaredServers()), ['alpha'], 'a second accept declares no second server');

  const restored = await answer({ method: 'POST', path: rowPath('restore') }, deps);
  assert.equal(restored.status, 409, 'an accepted row is undone through DELETE /servers, not restore');
  assert.equal((restored.json as { reason: string }).reason, 'notDeclined');
});

test('accept refuses a name already declared with another command line, and leaves servers.json as it was', async () => {
  resetServers({ alpha: { command: '/usr/bin/other', args: [] } });
  const before = readFileSync(SERVERS, 'utf8');
  const held = new Map<string, UpstreamConfig>([
    ['alpha', { transport: 'stdio', name: 'alpha', command: '/usr/bin/other', args: [], env: {}, envFiles: [] }],
  ]);
  const inbox = seededStore();

  const refused = await answer(
    { method: 'POST', path: rowPath('accept'), body: acceptBody(inbox) },
    routeDeps(inbox, held)
  );
  assert.equal(refused.status, 409);
  assert.equal((refused.json as { reason: string }).reason, 'alreadyDeclared');
  assert.equal(readFileSync(SERVERS, 'utf8'), before);
  assert.equal(inbox.rows()[0].state, 'waiting');
});

test('accept reconciles a row whose exact declaration is already in place, and does not index it again', async () => {
  // The command does not exist, so an index would fail. A 200 here therefore shows nothing ran.
  const install = { type: 'stdio' as const, command: '/nonexistent/bin/none', args: ['x'] };
  resetServers({ alpha: { command: '/nonexistent/bin/none', args: ['x'] } });
  const before = readFileSync(SERVERS, 'utf8');
  const held = new Map<string, UpstreamConfig>([
    ['alpha', { transport: 'stdio', name: 'alpha', command: '/nonexistent/bin/none', args: ['x'], env: {}, envFiles: [] }],
  ]);
  const inbox = storeWith(alpha(install));

  const reconciled = await answer(
    { method: 'POST', path: rowPath('accept'), body: acceptBody(inbox) },
    routeDeps(inbox, held)
  );
  assert.equal(reconciled.status, 200, reconciled.text);
  assert.equal((reconciled.json as { reconciled: boolean }).reconciled, true);
  assert.equal(inbox.rows()[0].state, 'accepted');
  assert.equal(readFileSync(SERVERS, 'utf8'), before);
});

test('accept refuses a server that does not start, leaves the row waiting, and declares nothing', async () => {
  resetServers();
  const inbox = storeWith(alpha({ type: 'stdio', command: '/nonexistent/bin/none', args: [] }));

  const refused = await answer({ method: 'POST', path: rowPath('accept'), body: acceptBody(inbox) }, routeDeps(inbox));
  assert.equal(refused.status, 422);
  assert.equal((refused.json as { reason: string }).reason, 'indexFailed');
  assert.equal(inbox.rows()[0].state, 'waiting');
  assert.equal(existsSync(SERVERS), false);
});

test('a write that fails after the declaration leaves the row waiting, and the next accept reconciles it without declaring twice', async () => {
  resetServers();
  const inbox = seededStore();
  const deps = routeDeps(inbox);

  // The temporary file the row write goes through is a directory, so the write fails after the declaration lands.
  const blocker = `${inbox.path}.tmp-${process.pid}`;
  mkdirSync(blocker);
  try {
    const failed = await answer({ method: 'POST', path: rowPath('accept'), body: acceptBody(inbox) }, deps);
    assert.equal(failed.status, 500);
    assert.equal(inbox.rows()[0].state, 'waiting', 'the row was not marked, because its write failed');
    assert.deepEqual(Object.keys(declaredServers()), ['alpha'], 'the declaration did land');
  } finally {
    rmSync(blocker, { recursive: true, force: true });
  }

  const next = await answer({ method: 'POST', path: rowPath('accept'), body: acceptBody(inbox) }, deps);
  assert.equal(next.status, 200, next.text);
  assert.equal((next.json as { reconciled: boolean }).reconciled, true);
  assert.equal(inbox.rows()[0].state, 'accepted');
  assert.deepEqual(Object.keys(declaredServers()), ['alpha'], 'still one declaration');
});

test('decline sets the row declined, declares nothing, and leaves servers.json as it was', async () => {
  resetServers({ other: { command: '/usr/bin/other', args: [] } });
  const before = readFileSync(SERVERS, 'utf8');
  const inbox = seededStore();

  const declined = await answer({ method: 'POST', path: rowPath('decline') }, routeDeps(inbox));
  assert.equal(declined.status, 200, declined.text);
  assert.equal(inbox.rows()[0].state, 'declined');
  assert.equal(readFileSync(SERVERS, 'utf8'), before);

  const again = await answer({ method: 'POST', path: rowPath('decline') }, routeDeps(inbox));
  assert.equal(again.status, 409);
  assert.equal((again.json as { reason: string }).reason, 'notWaiting');
});

test('restore returns a declined row to waiting, refuses a row that is not declined, and leaves servers.json as it was', async () => {
  resetServers({ other: { command: '/usr/bin/other', args: [] } });
  const before = readFileSync(SERVERS, 'utf8');
  const inbox = seededStore();
  const deps = routeDeps(inbox);

  await answer({ method: 'POST', path: rowPath('decline') }, deps);
  const restored = await answer({ method: 'POST', path: rowPath('restore') }, deps);
  assert.equal(restored.status, 200, restored.text);
  assert.equal(inbox.rows()[0].state, 'waiting');

  const notDeclined = await answer({ method: 'POST', path: rowPath('restore') }, deps);
  assert.equal(notDeclined.status, 409);
  assert.equal((notDeclined.json as { reason: string }).reason, 'notDeclined');
  assert.equal(readFileSync(SERVERS, 'utf8'), before);
});

test('an action on an id the inbox does not hold answers 404', async () => {
  resetServers();
  const inbox = seededStore();

  const missing = await answer({ method: 'POST', path: rowPath('decline', 'io.example/missing') }, routeDeps(inbox));
  assert.equal(missing.status, 404);
  assert.equal((missing.json as { reason: string }).reason, 'notFound');
});

test('POST /servers declares through the shared path, and names a duplicate with 409', async () => {
  resetServers({});
  const deps = routeDeps(seededStore());
  const body = { name: 'alpha', command: process.execPath, args: FIXTURE_ARGS };

  const created = await answer({ method: 'POST', path: '/servers', body }, deps);
  assert.equal(created.status, 201, created.text);
  assert.equal((created.json as { tools: number }).tools, 1);
  assert.deepEqual(Object.keys(declaredServers().alpha).sort(), ['args', 'command'], 'the stored entry carries no name field');

  const duplicate = await answer({ method: 'POST', path: '/servers', body }, deps);
  assert.equal(duplicate.status, 409);
  assert.match((duplicate.json as { error: string }).error, /already exists/);
});

test('POST /servers that does not start answers 422 with the force hint, and declares nothing', async () => {
  resetServers({});
  const deps = routeDeps(seededStore());

  const refused = await answer(
    { method: 'POST', path: '/servers', body: { name: 'broken', command: '/nonexistent/bin/none', args: [] } },
    deps
  );
  assert.equal(refused.status, 422);
  assert.match((refused.json as { hint: string }).hint, /force=1/);
  assert.equal(declaredServers().broken, undefined);
});
