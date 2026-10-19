import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Pairing } from '../src/pairing.js';
import { startPairing, type PairingAdvertisement, type PairingAdvertisementRequest } from '../src/pairing-listener.js';
import { createBonjourAdvertiser, PAIRING_SERVICE_TYPE, type BonjourResponder } from '../src/pairing-advertise.js';

/*
 * The pairing service advertisement (plan §3). Nothing here touches multicast: the listener is handed a
 * fake advertiser, and the Bonjour adapter is handed a fake responder, so no mDNS packet is sent.
 */
const home = mkdtempSync(join(tmpdir(), 'pairing-advertise-test-'));
after(() => rmSync(home, { recursive: true, force: true }));

const MAC_NAME = 'test-mac';

/** Records every advertisement a listener asks for, and every stop it is asked to perform. */
function recordingAdvertiser(): {
  requests: PairingAdvertisementRequest[];
  stops: string[];
  advertise: (req: PairingAdvertisementRequest) => PairingAdvertisement;
} {
  const requests: PairingAdvertisementRequest[] = [];
  const stops: string[] = [];
  return {
    requests,
    stops,
    advertise: (req) => {
      requests.push(req);
      return {
        stop: async () => {
          stops.push(`stopped ${req.name}`);
        }
      };
    }
  };
}

describe('the pairing listener advertises only while enabled', () => {
  test('advertises the bound port under the Mac name when pairing is enabled', async () => {
    const fake = recordingAdvertiser();
    const running = await startPairing(
      { enabled: true, host: '127.0.0.1', port: 0 },
      { dir: join(home, 'enabled'), pairing: new Pairing(), macName: MAC_NAME, advertise: fake.advertise }
    );
    try {
      assert.ok(running);
      assert.equal(fake.requests.length, 1);
      // The port is the one the socket actually bound, not the 0 the config asked for.
      assert.equal(fake.requests[0].port, running.port);
      assert.notEqual(fake.requests[0].port, 0);
      assert.equal(fake.requests[0].name, MAC_NAME);
      assert.deepEqual(fake.requests[0].txt, { name: MAC_NAME });
    } finally {
      await running?.close();
    }
  });

  test('advertises nothing while pairing is disabled', async () => {
    const fake = recordingAdvertiser();
    const running = await startPairing(
      { enabled: false, host: '127.0.0.1', port: 0 },
      { dir: join(home, 'disabled'), pairing: new Pairing(), macName: MAC_NAME, advertise: fake.advertise }
    );
    assert.equal(running, undefined);
    assert.equal(fake.requests.length, 0);
  });

  test('withdraws the advertisement when the listener closes', async () => {
    const fake = recordingAdvertiser();
    const running = await startPairing(
      { enabled: true, host: '127.0.0.1', port: 0 },
      { dir: join(home, 'stop'), pairing: new Pairing(), macName: MAC_NAME, advertise: fake.advertise }
    );
    assert.ok(running);
    assert.deepEqual(fake.stops, []);
    await running.close();
    assert.deepEqual(fake.stops, [`stopped ${MAC_NAME}`]);
  });

  test('a listener whose advertisement throws still listens', async () => {
    const running = await startPairing(
      { enabled: true, host: '127.0.0.1', port: 0 },
      {
        dir: join(home, 'throws'),
        pairing: new Pairing(),
        macName: MAC_NAME,
        advertise: () => {
          throw new Error('mDNS responder could not bind');
        }
      }
    );
    try {
      // Phones can still pair from the QR, which carries the endpoint, so a missing advertisement is not a dead listener.
      assert.ok(running);
      assert.ok(running.port > 0);
      assert.equal(running.openConnections(), 0);
    } finally {
      await running?.close();
    }
  });

  test('close still completes when stopping the advertisement fails', async () => {
    const running = await startPairing(
      { enabled: true, host: '127.0.0.1', port: 0 },
      {
        dir: join(home, 'stop-fails'),
        pairing: new Pairing(),
        macName: MAC_NAME,
        advertise: () => ({
          stop: async () => {
            throw new Error('goodbye could not be sent');
          }
        })
      }
    );
    assert.ok(running);
    await running.close();
  });
});

describe('the Bonjour adapter', () => {
  /** A responder that records each call in order, and calls back at once unless told not to. */
  function fakeResponder(opts: { destroyCallsBack: boolean }): { responder: BonjourResponder; calls: string[]; published: unknown[] } {
    const calls: string[] = [];
    const published: unknown[] = [];
    const responder: BonjourResponder = {
      publish: (config) => {
        published.push(config);
        calls.push('publish');
        return undefined;
      },
      unpublishAll: (callback) => {
        calls.push('unpublishAll');
        callback();
      },
      destroy: (callback) => {
        calls.push('destroy');
        if (opts.destroyCallsBack) callback();
      }
    };
    return { responder, calls, published };
  }

  test('publishes the pairing service type over TCP with the Mac name as TXT', () => {
    const { responder, published } = fakeResponder({ destroyCallsBack: true });
    createBonjourAdvertiser(() => responder)({ name: MAC_NAME, port: 8882, txt: { name: MAC_NAME } });
    assert.deepEqual(published, [
      { name: MAC_NAME, type: PAIRING_SERVICE_TYPE, protocol: 'tcp', port: 8882, txt: { name: MAC_NAME } }
    ]);
    // The type is the plan's §3 service, `_mcprouter-pair._tcp`, with the underscores and protocol added by the responder.
    assert.equal(PAIRING_SERVICE_TYPE, 'mcprouter-pair');
  });

  test('stop withdraws the service before it releases the responder', async () => {
    const { responder, calls } = fakeResponder({ destroyCallsBack: true });
    const advertisement = createBonjourAdvertiser(() => responder)({ name: MAC_NAME, port: 8882, txt: { name: MAC_NAME } });
    await advertisement.stop();
    assert.deepEqual(calls, ['publish', 'unpublishAll', 'destroy']);
  });

  test('stop resolves even when the responder never reports its socket closed', async () => {
    const { responder } = fakeResponder({ destroyCallsBack: false });
    const advertisement = createBonjourAdvertiser(() => responder)({ name: MAC_NAME, port: 8882, txt: { name: MAC_NAME } });
    // A shutdown that hangs on mDNS is worse than one that leaves a goodbye unsent, so stop is bounded.
    await advertisement.stop();
  });
});
