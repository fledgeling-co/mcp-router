import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, rmSync, statSync } from 'node:fs';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Pairing } from '../src/pairing.js';
import { appendPairedPhone, readPairedPhones, type PairedPhone } from '../src/paired-phones.js';
import type { ControlDeps } from '../src/control.js';

/*
 * DELETE /pairing/phones/:phoneId, through handleControl. Revoking a phone removes its record, and the record
 * holds the phone's public key, so the removal removes the key too (plan-phone-inbox.md §2.3, §7). The router
 * home is set before control.ts loads, for the same reason pairing.test.ts gives: a test must never reach the
 * operator's own control.token or servers.json.
 */
const home = mkdtempSync(join(tmpdir(), 'pairing-revoke-test-'));
after(() => rmSync(home, { recursive: true, force: true }));
process.env.MCP_ROUTER_HOME = home;
const { handleControl } = await import('../src/control.js');

const TOKEN = 'test-token-0123456789';
const KEPT: PairedPhone = {
  phoneId: '22222222-2222-2222-2222-222222222222',
  phoneName: 'Spare iPad',
  phoneKey: 'a2VwdC1rZXktYg==',
  pairedAt: '2026-10-19T09:00:00Z',
};
const REVOKED: PairedPhone = {
  phoneId: '11111111-1111-1111-1111-111111111111',
  phoneName: "Luke's iPhone",
  phoneKey: 'cmV2b2tlZC1rZXktYQ==',
  pairedAt: '2026-10-19T10:00:00Z',
};

/** A router home holding the given confirmed phones, in the order they were paired. */
function seeded(phones: PairedPhone[]): string {
  const dir = mkdtempSync(join(home, 'run-'));
  for (const phone of phones) appendPairedPhone(dir, phone);
  return dir;
}

interface Reply {
  status: number;
  body: Record<string, unknown>;
}

async function call(
  dir: string,
  method: string,
  path: string,
  opts: { token?: string; pairing?: Pairing } = {}
): Promise<Reply> {
  const headers: Record<string, string> = {};
  if (opts.token !== undefined) headers['x-mcpr-token'] = opts.token;
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
  const deps = { pairing: opts.pairing ?? new Pairing(), routerHome: dir, pairingListener: () => ({ enabled: false, port: null, advertising: false }) } as unknown as ControlDeps;
  const handled = await handleControl(req, res, new URL(`http://127.0.0.1${path}`), undefined, deps, TOKEN);
  assert.equal(handled, true, `${method} ${path} should be claimed by the control API`);
  return captured;
}

describe('DELETE /pairing/phones/:phoneId', () => {
  test('is refused without the token, and the confirmed phone stays paired', async () => {
    const dir = seeded([REVOKED, KEPT]);
    const r = await call(dir, 'DELETE', `/pairing/phones/${REVOKED.phoneId}`);
    assert.equal(r.status, 401);
    assert.deepEqual(readPairedPhones(dir), [REVOKED, KEPT]);
  });

  test('a wrong token is refused the same way', async () => {
    const dir = seeded([REVOKED]);
    const r = await call(dir, 'DELETE', `/pairing/phones/${REVOKED.phoneId}`, { token: 'not-the-token' });
    assert.equal(r.status, 401);
    assert.deepEqual(readPairedPhones(dir), [REVOKED]);
  });

  test('removes the phone and its key, keeps the other phone, and leaves the file 0600', async () => {
    const dir = seeded([REVOKED, KEPT]);
    const r = await call(dir, 'DELETE', `/pairing/phones/${REVOKED.phoneId}`, { token: TOKEN });
    assert.equal(r.status, 200);
    assert.deepEqual(r.body, { revoked: REVOKED.phoneId });
    assert.deepEqual(readPairedPhones(dir), [KEPT]);
    assert.equal(statSync(join(dir, 'paired-phones.json')).mode & 0o777, 0o600);
  });

  test('a phone that is not confirmed is a 404, and the file is left as it was', async () => {
    const dir = seeded([KEPT]);
    const r = await call(dir, 'DELETE', `/pairing/phones/${REVOKED.phoneId}`, { token: TOKEN });
    assert.equal(r.status, 404);
    assert.deepEqual(readPairedPhones(dir), [KEPT]);
  });

  test('with no paired-phones file at all, it is a 404 and creates no file', async () => {
    const dir = mkdtempSync(join(home, 'run-'));
    const r = await call(dir, 'DELETE', `/pairing/phones/${REVOKED.phoneId}`, { token: TOKEN });
    assert.equal(r.status, 404);
    assert.equal(existsSync(join(dir, 'paired-phones.json')), false);
  });

  test('a second revoke of the same phone is a 404, not a second removal', async () => {
    const dir = seeded([REVOKED, KEPT]);
    assert.equal((await call(dir, 'DELETE', `/pairing/phones/${REVOKED.phoneId}`, { token: TOKEN })).status, 200);
    const again = await call(dir, 'DELETE', `/pairing/phones/${REVOKED.phoneId}`, { token: TOKEN });
    assert.equal(again.status, 404);
    assert.deepEqual(readPairedPhones(dir), [KEPT]);
  });

  test('a pending phone, one whose request is held but not yet acked, cannot be revoked as a confirmed one', async () => {
    const dir = seeded([KEPT]);
    const pairing = new Pairing();
    pairing.hold(REVOKED.phoneId, REVOKED.phoneName);
    const r = await call(dir, 'DELETE', `/pairing/phones/${REVOKED.phoneId}`, { token: TOKEN, pairing });
    assert.equal(r.status, 404);
    assert.deepEqual(readPairedPhones(dir), [KEPT]);
    assert.equal(pairing.awaitingAck().length, 1, 'the held request is left for the listener to release');
  });

  test('a method other than DELETE on the phone route gets a 405, not a removal', async () => {
    const dir = seeded([REVOKED]);
    const r = await call(dir, 'GET', `/pairing/phones/${REVOKED.phoneId}`, { token: TOKEN });
    assert.equal(r.status, 405);
    assert.deepEqual(readPairedPhones(dir), [REVOKED]);
  });
});


test('pairing state exposes confirmed public metadata only and removes revoked peers', async () => {
  const dir = seeded([REVOKED, KEPT]);
  const pairing = new Pairing();
  pairing.hold('pending-not-confirmed', 'Waiting phone');
  assert.equal((await call(dir, 'GET', '/pairing/state')).status, 401);
  const first = await call(dir, 'GET', '/pairing/state', { token: TOKEN, pairing });
  assert.equal(first.status, 200);
  assert.deepEqual(first.body.confirmedPhones, [REVOKED, KEPT].map(({ phoneId, phoneName, pairedAt }) => ({ phoneId, phoneName, pairedAt })));
  assert.equal(JSON.stringify(first.body).includes('phoneKey'), false);
  await call(dir, 'DELETE', `/pairing/phones/${REVOKED.phoneId}`, { token: TOKEN });
  const after = await call(dir, 'GET', '/pairing/state', { token: TOKEN, pairing });
  assert.deepEqual(after.body.confirmedPhones, [{ phoneId: KEPT.phoneId, phoneName: KEPT.phoneName, pairedAt: KEPT.pairedAt }]);
});
