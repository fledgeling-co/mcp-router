import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { IncomingMessage, ServerResponse } from 'node:http';
import type { ControlDeps } from '../src/control.js';
import type { UpstreamConfig } from '../src/config.js';
import { InboxStore } from '../src/inbox.js';

/*
 * The /inbox family, through handleControl (planning/plans/plan-phone-inbox.md §2.3, §5). IB1 adds the
 * read only: GET /inbox, gated on every method. Nothing else on /inbox is served yet, so every other
 * method answers 405 once the token is right.
 *
 * The router home is set before control.ts loads, because config.ts reads it at import.
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

const UPSTREAMS = new Map<string, UpstreamConfig>();

/** A store under its own scratch directory, holding one waiting row from a confirmed phone. */
function seededStore(): InboxStore {
  const parent = mkdtempSync(join(tmpdir(), 'inbox-routes-'));
  made.push(parent);
  const store = new InboxStore(join(parent, 'inbox.json'));
  store.add({
    id: 'io.example/alpha',
    phoneId: PHONE_ID,
    deviceName: "Luke's iPhone",
    queuedAt: '2026-10-19T10:00:00Z',
    receivedAt: '2026-10-19T10:00:05Z',
    resolved: { id: 'io.example/alpha', name: 'alpha', displayName: 'Alpha', description: 'a test', source: 'official' },
  });
  return store;
}

interface Call {
  method: string;
  path: string;
  body?: unknown;
  token?: string | null;
}

/** Drive one request through handleControl and capture what it answered. */
async function answer(call: Call, deps: Partial<ControlDeps>): Promise<{ status: number; text: string; json: unknown }> {
  const headers: Record<string, string> = { 'content-type': 'application/json' };
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

test('every other method on /inbox answers 405 once the token is right, and 401 without it', async () => {
  const deps = { inbox: seededStore() };

  const posted = await answer({ method: 'POST', path: '/inbox', body: {} }, deps);
  assert.equal(posted.status, 405, 'there is no submit path in IB1');

  const accepted = await answer({ method: 'POST', path: '/inbox/io.example%2Falpha/accept', body: {} }, deps);
  assert.equal(accepted.status, 405, 'there is no accept route in IB1');

  const refused = await answer({ method: 'POST', path: '/inbox', body: {}, token: null }, deps);
  assert.equal(refused.status, 401);
});

test('with no store wired, /inbox answers 503 rather than an empty inbox', async () => {
  const listed = await answer({ method: 'GET', path: '/inbox' }, {});
  assert.equal(listed.status, 503);
});
