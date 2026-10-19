import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Pairing, decide, PAIRING_ALPHABET, PAIRING_LIFETIME_MS } from '../src/pairing.js';
import type { PairingListenerStatus } from '../src/pairing-listener.js';

/*
 * The router home is set before control.ts loads, for the same reason refused-write.test.ts gives:
 * control.ts reads ROUTER_HOME when it is imported, and a test must never reach the operator's own
 * servers.json or control.token.
 */
const home = mkdtempSync(join(tmpdir(), 'pairing-test-'));
after(() => rmSync(home, { recursive: true, force: true }));
process.env.MCP_ROUTER_HOME = home;
const { handleControl } = await import('../src/control.js');
import type { ControlDeps } from '../src/control.js';

const NOW = new Date('2026-10-19T10:00:00.000Z');
const CODE = 'ABCD2345';
const OTHER = '00000000';
const SPARE = '11111111';

function live(over: Partial<{ code: string; issuedAt: Date; expiresAt: Date }> = {}) {
  return { code: CODE, issuedAt: NOW, expiresAt: new Date(NOW.getTime() + PAIRING_LIFETIME_MS), ...over };
}

describe('decide, the port of MacPairing.decide', () => {
  test('accepts a live, unexpired code that matches', () => {
    assert.equal(decide({ submitted: CODE, version: 1, live: live(), spent: new Set(), now: NOW }), undefined);
  });

  test('refuses an unsupported version before anything else, even for a spent code', () => {
    const r = decide({ submitted: CODE, version: 2, live: live(), spent: new Set([CODE]), now: NOW });
    assert.deepEqual(r, { kind: 'unsupportedVersion', found: 2 });
  });

  test('reports a spent code as alreadyUsed after the next code has replaced it', () => {
    const r = decide({ submitted: CODE, version: 1, live: live({ code: OTHER }), spent: new Set([CODE]), now: NOW });
    assert.deepEqual(r, { kind: 'alreadyUsed' });
  });

  test('reports notRecognised when nothing is live', () => {
    assert.deepEqual(decide({ submitted: CODE, version: 1, live: undefined, spent: new Set(), now: NOW }), {
      kind: 'notRecognised',
    });
  });

  test('reports notRecognised for a code that is not the live one', () => {
    assert.deepEqual(decide({ submitted: OTHER, version: 1, live: live(), spent: new Set(), now: NOW }), {
      kind: 'notRecognised',
    });
  });

  test('expires at the instant of expiresAt, as hasExpired does (<=)', () => {
    const at = live().expiresAt;
    assert.deepEqual(decide({ submitted: CODE, version: 1, live: live(), spent: new Set(), now: at }), {
      kind: 'expired',
    });
  });
});

describe('Pairing, the stateful half', () => {
  test('issues eight characters, all from the Crockford alphabet with I, L, O and U excluded', () => {
    const p = new Pairing(() => NOW);
    for (let i = 0; i < 200; i++) {
      const { code } = p.issue();
      assert.equal(code.length, 8);
      for (const c of code) assert.ok(PAIRING_ALPHABET.includes(c), `"${c}" is outside the alphabet`);
      assert.doesNotMatch(code, /[ILOU]/);
      p.revoke();
    }
  });

  test('expiry is issuedAt plus 300 seconds, whole seconds, rounded down', () => {
    const p = new Pairing(() => new Date('2026-10-19T10:00:00.750Z'));
    const { expiresAt } = p.issue();
    assert.equal(expiresAt.getTime(), Date.parse('2026-10-19T10:05:00.000Z'));
    assert.equal(PAIRING_LIFETIME_MS, 300_000);
  });

  test('a new issue replaces the live code, so the old one is no longer recognised', () => {
    let now = NOW;
    const p = new Pairing(() => now);
    const first = p.issue().code;
    const second = p.issue().code;
    assert.notEqual(first, second);
    assert.deepEqual(p.submit(first, 1), { kind: 'notRecognised' });
    assert.equal(p.submit(second, 1), undefined);
  });

  test('a code is live until its expiry and not after', () => {
    let now = NOW;
    const p = new Pairing(() => now);
    const { code, expiresAt } = p.issue();
    now = new Date(expiresAt.getTime() - 1);
    assert.ok(p.current(), 'still pending one millisecond before expiry');
    now = expiresAt;
    assert.equal(p.current(), null, 'not named once it has expired');
    assert.deepEqual(p.submit(code, 1), { kind: 'expired' });
  });

  test('burns the code after three wrong attempts, and the right code then fails', () => {
    const p = new Pairing(() => NOW);
    const { code } = p.issue();
    assert.deepEqual(p.submit(OTHER, 1), { kind: 'notRecognised' });
    assert.deepEqual(p.submit(OTHER, 1), { kind: 'notRecognised' });
    assert.deepEqual(p.submit(OTHER, 1), { kind: 'notRecognised' }, 'the third wrong attempt burns it');
    assert.equal(p.current(), null);
    assert.deepEqual(p.submit(code, 1), { kind: 'notRecognised' }, 'the burned code is no longer live');
  });

  test('two wrong attempts followed by the right code still pairs', () => {
    const p = new Pairing(() => NOW);
    const { code } = p.issue();
    p.submit(OTHER, 1);
    p.submit(OTHER, 1);
    assert.equal(p.submit(code, 1), undefined);
    assert.equal(p.current(), null, 'a paired code is no longer live');
    assert.deepEqual(p.submit(code, 1), { kind: 'alreadyUsed' });
  });

  test('the attempt count belongs to each code, so a re-issue starts again at zero', () => {
    const p = new Pairing(() => NOW);
    p.issue();
    p.submit(OTHER, 1);
    p.submit(OTHER, 1);
    const fresh = p.issue().code;
    p.submit(SPARE, 1);
    p.submit(SPARE, 1);
    assert.ok(p.current(), 'two wrong attempts on the new code do not burn it');
    assert.equal(p.submit(fresh, 1), undefined);
  });

  test('revoke clears the live code, and reports whether there was one', () => {
    const p = new Pairing(() => NOW);
    const { code } = p.issue();
    assert.equal(p.revoke(), true);
    assert.equal(p.current(), null);
    assert.deepEqual(p.submit(code, 1), { kind: 'notRecognised' });
    assert.equal(p.revoke(), false);
  });

  test('revoke does not forget a code that was already paired', () => {
    const p = new Pairing(() => NOW);
    const used = p.issue().code;
    assert.equal(p.submit(used, 1), undefined);
    p.issue();
    p.revoke();
    assert.deepEqual(p.submit(used, 1), { kind: 'alreadyUsed' });
  });
});

/*
 * The token gate and the wire shape, driven through handleControl so the routes themselves are what
 * is under test. The pairing branch returns before any other dependency is touched, so the deps
 * object carries only the pairing state.
 */
const TOKEN = 'test-token-0123456789';

interface Reply {
  status: number;
  body: Record<string, unknown>;
}

/** The listener as a router with `pairing.enabled` set and bound reports it. */
const LISTENING: PairingListenerStatus = { enabled: true, port: 8882, advertising: true };
/** The listener as a router with pairing off reports it: nothing bound, nothing announced. */
const OFF: PairingListenerStatus = { enabled: false, port: null, advertising: false };

async function call(
  pairing: Pairing,
  method: string,
  path: string,
  opts: { token?: string; contentType?: string; listener?: PairingListenerStatus } = {}
): Promise<Reply> {
  const headers: Record<string, string> = {};
  if (opts.token !== undefined) headers['x-mcpr-token'] = opts.token;
  if (opts.contentType !== undefined) headers['content-type'] = opts.contentType;
  const captured: Reply = { status: 0, body: {} };
  const res = {
    writeHead(status: number) {
      captured.status = status;
    },
    end(payload: string) {
      captured.body = JSON.parse(payload) as Record<string, unknown>;
    },
  } as unknown as ServerResponse;
  const req = { method, headers } as unknown as IncomingMessage;
  const handled = await handleControl(
    req,
    res,
    new URL(`http://127.0.0.1${path}`),
    {},
    { pairing, pairingListener: () => opts.listener ?? LISTENING } as unknown as ControlDeps,
    TOKEN
  );
  assert.equal(handled, true, `${method} ${path} should be claimed by the control API`);
  return captured;
}

const JSON_TYPE = 'application/json';

describe('pairing routes', () => {
  test('every pairing method is refused without the token, GET included', async () => {
    const p = new Pairing(() => NOW);
    const { code } = p.issue();
    for (const [method, path] of [
      ['POST', '/pairing/codes'],
      ['DELETE', '/pairing/codes'],
      ['GET', '/pairing/state'],
    ] as const) {
      const r = await call(p, method, path, { contentType: JSON_TYPE });
      assert.equal(r.status, 401, `${method} ${path} without a token`);
      assert.doesNotMatch(JSON.stringify(r.body), new RegExp(code), `${method} ${path} must not name the code`);
    }
    assert.ok(p.current(), 'the refused DELETE left the code live');
  });

  test('a wrong token is refused the same way', async () => {
    const p = new Pairing(() => NOW);
    const r = await call(p, 'GET', '/pairing/state', { token: 'not-the-token' });
    assert.equal(r.status, 401);
  });

  test('POST issues a code with the wire shape and an exact whole-second expiry', async () => {
    const p = new Pairing(() => NOW);
    const r = await call(p, 'POST', '/pairing/codes', { token: TOKEN, contentType: JSON_TYPE });
    assert.equal(r.status, 201);
    assert.match(r.body.code as string, /^[0-9A-HJKMNP-TV-Z]{8}$/);
    assert.equal(r.body.issuedAt, '2026-10-19T10:00:00Z');
    assert.equal(r.body.expiresAt, '2026-10-19T10:05:00Z');
  });

  test('POST still requires a JSON content type once the token is right', async () => {
    const p = new Pairing(() => NOW);
    const r = await call(p, 'POST', '/pairing/codes', { token: TOKEN, contentType: 'text/plain' });
    assert.equal(r.status, 415);
    assert.equal(p.current(), null);
  });

  test('GET names the live code, and names nothing once it has expired', async () => {
    let now = NOW;
    const p = new Pairing(() => now);
    assert.deepEqual((await call(p, 'GET', '/pairing/state', { token: TOKEN })).body, { code: null, awaitingAck: [], listener: LISTENING });
    const { code } = p.issue();
    const live = await call(p, 'GET', '/pairing/state', { token: TOKEN });
    assert.equal(live.status, 200);
    assert.equal((live.body.code as { code: string }).code, code);
    now = new Date(NOW.getTime() + PAIRING_LIFETIME_MS);
    assert.deepEqual((await call(p, 'GET', '/pairing/state', { token: TOKEN })).body, { code: null, awaitingAck: [], listener: LISTENING });
  });

  test('GET names a phone whose request is awaiting its ack, by name and time, until it is released', async () => {
    const p = new Pairing(() => NOW);
    p.hold('11111111-1111-1111-1111-111111111111', "Luke's iPhone");
    assert.deepEqual((await call(p, 'GET', '/pairing/state', { token: TOKEN })).body, {
      code: null,
      awaitingAck: [{ phoneName: "Luke's iPhone", requestedAt: '2026-10-19T10:00:00Z' }],
      listener: LISTENING,
    });
    p.release('11111111-1111-1111-1111-111111111111');
    assert.deepEqual((await call(p, 'GET', '/pairing/state', { token: TOKEN })).body, { code: null, awaitingAck: [], listener: LISTENING });
  });

  test('DELETE revokes once and reports nothing to revoke the second time', async () => {
    const p = new Pairing(() => NOW);
    p.issue();
    assert.deepEqual((await call(p, 'DELETE', '/pairing/codes', { token: TOKEN })).body, { revoked: true });
    assert.equal(p.current(), null);
    assert.deepEqual((await call(p, 'DELETE', '/pairing/codes', { token: TOKEN })).body, { revoked: false });
  });

  test('GET reports the listener as it is bound, and reports pairing off as off', async () => {
    const p = new Pairing(() => NOW);
    assert.deepEqual((await call(p, 'GET', '/pairing/state', { token: TOKEN })).body.listener, LISTENING);
    const off = await call(p, 'GET', '/pairing/state', { token: TOKEN, listener: OFF });
    assert.equal(off.status, 200);
    assert.deepEqual(off.body, { code: null, awaitingAck: [], listener: OFF });
  });

  test('POST refuses with a named 503 and mints nothing while the listener is not bound', async () => {
    const p = new Pairing(() => NOW);
    const r = await call(p, 'POST', '/pairing/codes', { token: TOKEN, contentType: JSON_TYPE, listener: OFF });
    assert.equal(r.status, 503);
    assert.equal(r.body.reason, 'pairingDisabled');
    assert.equal(typeof r.body.error, 'string');
    assert.equal(p.current(), null, 'a refused request leaves no live code for a phone to pair with');
  });

  test('DELETE still answers while the listener is off, so a code minted before is taken back', async () => {
    const p = new Pairing(() => NOW);
    p.issue();
    assert.deepEqual((await call(p, 'DELETE', '/pairing/codes', { token: TOKEN, listener: OFF })).body, { revoked: true });
  });

  test('a method the pairing routes do not answer gets a 405, not a silent pass-through', async () => {
    const p = new Pairing(() => NOW);
    const r = await call(p, 'PATCH', '/pairing/codes', { token: TOKEN, contentType: JSON_TYPE });
    assert.equal(r.status, 405);
  });
});
