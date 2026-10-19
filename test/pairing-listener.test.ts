import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { createHash, generateKeyPairSync } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { connect, type TLSSocket } from 'node:tls';
import { fileURLToPath } from 'node:url';
import { Pairing, PAIRING_LIFETIME_MS } from '../src/pairing.js';
import { certificateFingerprint, loadOrCreatePairingIdentity } from '../src/pairing-identity.js';
import { startPairing, PAIRING_FRAME_MAX } from '../src/pairing-listener.js';
import { readPairedPhones } from '../src/paired-phones.js';
import { loadConfig, DEFAULT_PAIRING_PORT } from '../src/config.js';

/*
 * The listener, driven by an in-process TLS client on an ephemeral loopback port. The client is the
 * test double of the phone: it pins the fingerprint a QR would carry, and it writes its frames by
 * hand so the codec under test is not checked against itself.
 */
const home = mkdtempSync(join(tmpdir(), 'pairing-listener-test-'));
after(() => rmSync(home, { recursive: true, force: true }));

const MAC_NAME = 'test-mac';
const PHONE_NAME = "Luke's iPhone";
const IDLE_MS = 200;

interface Harness {
  port: number;
  fp: string;
  pairing: Pairing;
  dir: string;
  open(): number;
  close(): Promise<void>;
}

async function harness(pairing = new Pairing()): Promise<Harness> {
  const dir = mkdtempSync(join(home, 'run-'));
  const running = await startPairing(
    { enabled: true, host: '127.0.0.1', port: 0 },
    { dir, pairing, macName: MAC_NAME, idleMs: IDLE_MS }
  );
  if (!running) throw new Error('an enabled listener did not start');
  const { fingerprint } = await loadOrCreatePairingIdentity(dir);
  return { port: running.port, fp: fingerprint, pairing, dir, open: () => running.openConnections(), close: () => running.close() };
}

/** A frame as the phone writes it: a four-byte big-endian length, then UTF-8 JSON. */
function frame(message: object): Buffer {
  const body = Buffer.from(JSON.stringify(message), 'utf8');
  const head = Buffer.alloc(4);
  head.writeUInt32BE(body.length);
  return Buffer.concat([head, body]);
}

function phoneKey(): string {
  const { publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  return publicKey.export({ type: 'spki', format: 'der' }).toString('base64');
}

function request(code: string, over: Record<string, unknown> = {}) {
  return { type: 'pair.request', v: 1, code, phoneName: PHONE_NAME, phoneKey: phoneKey(), entry: 'scan', ...over };
}

/**
 * Pins the router's certificate to the fingerprint the QR carried. Resolves 'identityMismatch' and sends nothing when they differ.
 *
 * `rejectUnauthorized: false` is deliberate. The certificate is self-signed with no CA, so the CA check would reject every
 * router. The pin is the check instead: it runs straight after the handshake and before a single frame is written, which is
 * the trust model in planning/plans/plan-pairing-handshake.md §2.2.
 */
function dial(
  port: number,
  pin: string,
  opts: { minVersion?: 'TLSv1.2' | 'TLSv1.3'; maxVersion?: 'TLSv1.2' | 'TLSv1.3'; allowHalfOpen?: boolean } = {}
) {
  return new Promise<TLSSocket | 'identityMismatch'>((resolve, reject) => {
    // allowHalfOpen is honoured by tls.connect at runtime but is missing from its typings. Off by default, as Node has it.
    // A test that needs a phone which keeps writing after the router's FIN sets it. The options live in a variable so the
    // object-literal excess-property check does not see it.
    const options = {
      host: '127.0.0.1',
      port,
      minVersion: opts.minVersion ?? 'TLSv1.3',
      maxVersion: opts.maxVersion,
      rejectUnauthorized: false,
      allowHalfOpen: opts.allowHalfOpen ?? false,
    };
    const socket = connect(options);
    socket.once('error', reject);
    socket.once('secureConnect', () => {
      const der = socket.getPeerCertificate(true).raw;
      if (createHash('sha256').update(der).digest('hex') !== pin) {
        socket.destroy();
        resolve('identityMismatch');
        return;
      }
      resolve(socket);
    });
  });
}

/** A pinned connection. A mismatch here is a test bug, not a verdict under test, so it throws. */
async function pinned(port: number, pin: string, opts?: { allowHalfOpen?: boolean }): Promise<TLSSocket> {
  const socket = await dial(port, pin, opts);
  if (socket === 'identityMismatch') throw new Error('the pinned fingerprint did not match the router');
  return socket;
}

/** The next whole frame the router writes, or undefined when it closes the connection first. */
function nextFrame(socket: TLSSocket): Promise<Record<string, unknown> | undefined> {
  return new Promise((resolve) => {
    let buffered = Buffer.alloc(0);
    const done = (value: Record<string, unknown> | undefined) => {
      socket.off('data', onData);
      socket.off('end', onEnd);
      socket.off('close', onEnd);
      resolve(value);
    };
    const onEnd = () => done(undefined);
    const onData = (chunk: Buffer) => {
      buffered = Buffer.concat([buffered, chunk]);
      if (buffered.length < 4) return;
      const len = buffered.readUInt32BE(0);
      if (buffered.length < 4 + len) return;
      done(JSON.parse(buffered.subarray(4, 4 + len).toString('utf8')) as Record<string, unknown>);
    };
    socket.on('data', onData);
    socket.once('end', onEnd);
    socket.once('close', onEnd);
  });
}

/** Everything the router writes until it closes the connection. */
function readAll(socket: TLSSocket): Promise<Buffer> {
  return new Promise((resolve) => {
    const parts: Buffer[] = [];
    socket.on('data', (chunk: Buffer) => parts.push(chunk));
    socket.once('close', () => resolve(Buffer.concat(parts)));
  });
}

async function until(cond: () => boolean, ms = 2000): Promise<void> {
  const started = Date.now();
  while (!cond()) {
    if (Date.now() - started > ms) throw new Error('condition not met in time');
    await new Promise((r) => setTimeout(r, 10));
  }
}

describe('pairing listener, the happy path', () => {
  test('ok, then ack, writes the confirmed record at 0600 and nothing before the ack', async () => {
    const h = await harness();
    try {
      const { code } = h.pairing.issue();
      const link = await pinned(h.port, h.fp);

      const req = request(code);
      link.write(frame(req));
      const ok = await nextFrame(link);
      assert.equal(ok?.type, 'pair.ok');
      assert.equal(ok?.v, 1);
      assert.equal(ok?.macName, MAC_NAME);
      const phoneId = ok?.phoneId as string;
      assert.match(phoneId, /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);

      assert.deepEqual(
        h.pairing.awaitingAck().map((a) => a.phoneName),
        [PHONE_NAME],
        'the request is held, awaiting the ack'
      );
      assert.deepEqual(readPairedPhones(h.dir), [], 'nothing is recorded before the ack');

      link.write(frame({ type: 'pair.ack', v: 1, phoneId }));
      assert.equal(await nextFrame(link), undefined, 'the router closes the connection once the record is written');

      const phones = readPairedPhones(h.dir);
      assert.equal(phones.length, 1);
      assert.equal(phones[0].phoneId, phoneId);
      assert.equal(phones[0].phoneName, PHONE_NAME);
      assert.equal(phones[0].phoneKey, req.phoneKey, 'the router stores the public key the phone sent');
      assert.equal(statSync(join(h.dir, 'paired-phones.json')).mode & 0o777, 0o600);
      assert.deepEqual(h.pairing.awaitingAck(), [], 'the acked request is no longer held');
      assert.equal(h.pairing.current(), null, 'the paired code is spent and no longer live');
    } finally {
      await h.close();
    }
  });

  test('a second pairing appends to the record and keeps the first', async () => {
    const h = await harness();
    try {
      for (const name of ['first phone', 'second phone']) {
        const { code } = h.pairing.issue();
        const link = await pinned(h.port, h.fp);
        link.write(frame(request(code, { phoneName: name })));
        const ok = await nextFrame(link);
        link.write(frame({ type: 'pair.ack', v: 1, phoneId: ok?.phoneId }));
        await nextFrame(link);
      }
      assert.deepEqual(
        readPairedPhones(h.dir).map((p) => p.phoneName),
        ['first phone', 'second phone']
      );
    } finally {
      await h.close();
    }
  });
});

describe('pairing listener, refusals record nothing', () => {
  test('a code that is not live is refused with the named reason', async () => {
    const h = await harness();
    try {
      h.pairing.issue();
      const link = await pinned(h.port, h.fp);
      link.write(frame(request('ZZZZZZZZ')));
      assert.deepEqual(await nextFrame(link), { type: 'pair.refused', v: 1, reason: 'notRecognised' });
      assert.deepEqual(readPairedPhones(h.dir), []);
      assert.deepEqual(h.pairing.awaitingAck(), []);
      assert.ok(h.pairing.current(), 'a wrong guess does not spend the live code');
    } finally {
      await h.close();
    }
  });

  test('an expired code is refused as expired', async () => {
    let now = new Date('2026-10-19T10:00:00.000Z');
    const pairing = new Pairing(() => now);
    const h = await harness(pairing);
    try {
      const { code, expiresAt } = pairing.issue();
      now = new Date(expiresAt.getTime());
      const link = await pinned(h.port, h.fp);
      link.write(frame(request(code)));
      assert.deepEqual(await nextFrame(link), { type: 'pair.refused', v: 1, reason: 'expired' });
      assert.deepEqual(readPairedPhones(h.dir), []);
      assert.equal(PAIRING_LIFETIME_MS, 300_000);
    } finally {
      await h.close();
    }
  });

  test('the third wrong guess burns the code, and the right code then gets notRecognised', async () => {
    const h = await harness();
    try {
      const { code } = h.pairing.issue();
      for (let i = 0; i < 3; i++) {
        const link = await pinned(h.port, h.fp);
        link.write(frame(request('ZZZZZZZZ')));
        assert.deepEqual(await nextFrame(link), { type: 'pair.refused', v: 1, reason: 'notRecognised' });
      }
      const link = await pinned(h.port, h.fp);
      link.write(frame(request(code)));
      assert.deepEqual(await nextFrame(link), { type: 'pair.refused', v: 1, reason: 'notRecognised' });
      assert.deepEqual(readPairedPhones(h.dir), []);
    } finally {
      await h.close();
    }
  });

  test('a malformed request, an unsupported version and a typed entry each refuse and leave the code live', async () => {
    const h = await harness();
    try {
      const { code } = h.pairing.issue();

      const malformed = await pinned(h.port, h.fp);
      malformed.write(frame(request(code, { code: 12345 })));
      assert.deepEqual(await nextFrame(malformed), { type: 'pair.refused', v: 1, reason: 'badRequest' });

      const version = await pinned(h.port, h.fp);
      version.write(frame(request(code, { v: 2 })));
      assert.deepEqual(await nextFrame(version), {
        type: 'pair.refused',
        v: 1,
        reason: 'unsupportedVersion',
        found: 2,
      });

      const typed = await pinned(h.port, h.fp);
      typed.write(frame(request(code, { entry: 'typed' })));
      assert.deepEqual(await nextFrame(typed), { type: 'pair.refused', v: 1, reason: 'typedEntryUnavailable' });

      assert.ok(h.pairing.current(), 'none of the three spent or counted against the code');
      assert.deepEqual(readPairedPhones(h.dir), []);

      const scan = await pinned(h.port, h.fp);
      scan.write(frame(request(code)));
      assert.equal((await nextFrame(scan))?.type, 'pair.ok', 'the scan path still pairs with the same code');
    } finally {
      await h.close();
    }
  });

  test('a client pinning a different fingerprint sends nothing, so the code stays live and nothing is recorded', async () => {
    const h = await harness();
    try {
      h.pairing.issue();
      assert.equal(await dial(h.port, 'f'.repeat(64)), 'identityMismatch');
      assert.ok(h.pairing.current(), 'the code was never presented');
      assert.deepEqual(h.pairing.awaitingAck(), []);
      assert.deepEqual(readPairedPhones(h.dir), []);
    } finally {
      await h.close();
    }
  });

  test('a connection dropped after pair.ok records nothing, releases the held request, and leaves the code spent', async () => {
    const h = await harness();
    try {
      const { code } = h.pairing.issue();
      const link = await pinned(h.port, h.fp);
      link.write(frame(request(code)));
      assert.equal((await nextFrame(link))?.type, 'pair.ok');
      assert.equal(h.pairing.awaitingAck().length, 1);

      link.destroy();
      await until(() => h.pairing.awaitingAck().length === 0);
      assert.deepEqual(readPairedPhones(h.dir), []);
      assert.equal(existsSync(join(h.dir, 'paired-phones.json')), false);

      const retry = await pinned(h.port, h.fp);
      retry.write(frame(request(code)));
      assert.deepEqual(await nextFrame(retry), { type: 'pair.refused', v: 1, reason: 'alreadyUsed' });
    } finally {
      await h.close();
    }
  });

  test('an ack for another phone, or any other message after pair.ok, closes the connection with no record', async () => {
    const h = await harness();
    try {
      const { code } = h.pairing.issue();
      const wrongId = await pinned(h.port, h.fp);
      wrongId.write(frame(request(code)));
      assert.equal((await nextFrame(wrongId))?.type, 'pair.ok');
      wrongId.write(frame({ type: 'pair.ack', phoneId: '00000000-0000-0000-0000-000000000000' }));
      assert.equal(await nextFrame(wrongId), undefined);
      assert.deepEqual(readPairedPhones(h.dir), []);

      const { code: second } = h.pairing.issue();
      const repeated = await pinned(h.port, h.fp);
      repeated.write(frame(request(second)));
      assert.equal((await nextFrame(repeated))?.type, 'pair.ok');
      repeated.write(frame(request(second)));
      assert.equal(await nextFrame(repeated), undefined, 'a second request is not an ack');
      assert.deepEqual(readPairedPhones(h.dir), []);
    } finally {
      await h.close();
    }
  });

  test('an idle connection is closed when the ack window runs out', async () => {
    const h = await harness();
    try {
      h.pairing.issue();
      const link = await pinned(h.port, h.fp);
      assert.equal(await nextFrame(link), undefined, 'a silent phone is closed, not held open');
      assert.deepEqual(readPairedPhones(h.dir), []);
    } finally {
      await h.close();
    }
  });
});

describe('pairing listener, the wire is fenced to pairing frames', () => {
  test('a frame over the size cap is refused on its header alone', async () => {
    const h = await harness();
    try {
      const link = await pinned(h.port, h.fp);
      const head = Buffer.alloc(4);
      head.writeUInt32BE(PAIRING_FRAME_MAX + 1);
      link.write(head);
      assert.deepEqual(await nextFrame(link), { type: 'pair.refused', v: 1, reason: 'frameTooLarge' });
    } finally {
      await h.close();
    }
  });

  test('a refused connection closes once the refusal is flushed, even if the phone keeps sending', async () => {
    const h = await harness();
    try {
      // A phone that holds its half open, so the router's FIN does not end the client from underneath the test.
      const link = await pinned(h.port, h.fp, { allowHalfOpen: true });
      link.on('error', () => undefined);
      const head = Buffer.alloc(4);
      head.writeUInt32BE(PAIRING_FRAME_MAX + 1);
      link.write(head);
      assert.deepEqual(await nextFrame(link), { type: 'pair.refused', v: 1, reason: 'frameTooLarge' });

      // Each write is activity, and activity resets the idle timer, so only an explicit close ends this.
      const keepSending = setInterval(() => link.write(Buffer.alloc(1024)), 20);
      try {
        await until(() => h.open() === 0, 1000);
      } finally {
        clearInterval(keepSending);
      }
    } finally {
      await h.close();
    }
  });

  test('an unknown message type gets a closed socket and no answer', async () => {
    const h = await harness();
    try {
      const link = await pinned(h.port, h.fp);
      link.write(frame({ type: 'pair.ping', v: 1 }));
      assert.equal(await nextFrame(link), undefined);
    } finally {
      await h.close();
    }
  });

  test('the listener is not the control API: an HTTP request gets no HTTP answer', async () => {
    const h = await harness();
    try {
      const link = await pinned(h.port, h.fp);
      link.write('GET /pairing/state HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n');
      const reply = (await readAll(link)).toString('latin1');
      assert.doesNotMatch(reply, /HTTP\//, 'nothing HTTP is served on the pairing port');
      assert.doesNotMatch(reply, /"code"|awaitingAck/, 'no control state is named');
    } finally {
      await h.close();
    }
  });

  test('only TLS 1.3 is accepted', async () => {
    const h = await harness();
    try {
      await assert.rejects(dial(h.port, h.fp, { maxVersion: 'TLSv1.2', minVersion: 'TLSv1.2' }));
    } finally {
      await h.close();
    }
  });
});

describe('pairing identity', () => {
  test('is created once with 0600 key and certificate files, and the same one is loaded after', async () => {
    const dir = mkdtempSync(join(home, 'identity-'));
    const first = await loadOrCreatePairingIdentity(dir);
    const second = await loadOrCreatePairingIdentity(dir);
    assert.equal(second.fingerprint, first.fingerprint);
    assert.match(first.fingerprint, /^[0-9a-f]{64}$/);
    for (const name of ['pairing-key.pem', 'pairing-cert.pem']) {
      assert.equal(statSync(join(dir, name)).mode & 0o777, 0o600, `${name} is 0600`);
    }
  });

  test('the fingerprint is the lowercase SHA-256 of the certificate DER', async () => {
    const dir = mkdtempSync(join(home, 'identity-der-'));
    const { fingerprint } = await loadOrCreatePairingIdentity(dir);
    const pem = readFileSync(join(dir, 'pairing-cert.pem'), 'utf8');
    assert.equal(certificateFingerprint(pem), fingerprint);
  });
});

describe('pairing listener configuration', () => {
  function configWith(pairing: unknown) {
    const dir = mkdtempSync(join(home, 'config-'));
    mkdirSync(dir, { recursive: true });
    const path = join(dir, 'servers.json');
    const body: Record<string, unknown> = { mcpServers: {} };
    if (pairing !== undefined) body.pairing = pairing;
    writeFileSync(path, JSON.stringify(body));
    return loadConfig({ configPath: path }).config;
  }

  test('pairing is disabled by default, on the documented port', () => {
    const cfg = configWith(undefined);
    assert.equal(cfg.pairing.enabled, false);
    assert.equal(cfg.pairing.port, DEFAULT_PAIRING_PORT);
    assert.equal(cfg.pairing.host, '0.0.0.0');
  });

  test('a disabled listener does not start, so nothing is bound', async () => {
    const dir = mkdtempSync(join(home, 'off-'));
    const running = await startPairing({ enabled: false, host: '127.0.0.1', port: 0 }, { dir, pairing: new Pairing() });
    assert.equal(running, undefined);
    assert.equal(existsSync(join(dir, 'pairing-key.pem')), false, 'no identity is generated while disabled');
  });

  test('enabling it reads the port and host from config', () => {
    const cfg = configWith({ enabled: true, port: 9100, host: '192.168.1.5' });
    assert.deepEqual(cfg.pairing, { enabled: true, port: 9100, host: '192.168.1.5' });
  });

  test('a port outside 1 to 65535, or a non-boolean enabled, is refused at load', () => {
    assert.throws(() => configWith({ enabled: true, port: 70000 }), /pairing\.port/);
    assert.throws(() => configWith({ enabled: 'yes' }), /pairing\.enabled/);
  });
});

/*
 * The shared wire vectors (planning/pairing/wire-vectors.json, plan §2.4). The phone reads the same file
 * in app/Tests/MCPRouterKitTests/PairingWireVectorsTests.swift. Here each frame the router receives is
 * written as the vector gives it, and the router's answer is checked against `expect.router`.
 */
interface WireVector {
  name: string;
  direction: 'toRouter' | 'toPhone';
  valid: boolean;
  after?: string;
  body?: Record<string, unknown>;
  rawBody?: string;
  declaredLength?: number;
  trailing?: string;
  expect: {
    router?: { reply: 'pair.ok' | 'pair.refused' | 'closed'; reason?: string; found?: number; recorded?: boolean };
    phone?: Record<string, unknown>;
  };
}

interface WireVectors {
  placeholders: Record<string, string>;
  fingerprint: { certificate: string; sha256: string };
  frames: WireVector[];
}

const fromRepo = (path: string) => fileURLToPath(new URL(`../../${path}`, import.meta.url));
const VECTORS = JSON.parse(readFileSync(fromRepo('planning/pairing/wire-vectors.json'), 'utf8')) as WireVectors;

function vectorNamed(name: string): WireVector {
  const found = VECTORS.frames.find((f) => f.name === name);
  if (!found) throw new Error(`no wire vector named ${name}`);
  return found;
}

/** The bytes a vector puts on the wire. `{{key}}` is replaced by `subs[key]`; a missing key is a test bug. */
function wireBytes(vector: WireVector, subs: Record<string, string>): Buffer {
  const text =
    vector.rawBody ??
    JSON.stringify(vector.body).replace(/\{\{(\w+)\}\}/g, (_, key: string) => {
      if (!(key in subs)) throw new Error(`${vector.name} has no value for {{${key}}}`);
      return subs[key];
    });
  const payload = Buffer.from(text, 'utf8');
  const head = Buffer.alloc(4);
  head.writeUInt32BE(vector.declaredLength ?? payload.length);
  return Buffer.concat([head, payload, Buffer.from(vector.trailing ?? '', 'utf8')]);
}

describe('pairing identity, the committed certificate', () => {
  test('renders the fingerprint the shared vectors carry, so both sides pin the same value', () => {
    const pem = readFileSync(fromRepo(VECTORS.fingerprint.certificate), 'utf8');
    assert.equal(certificateFingerprint(pem), VECTORS.fingerprint.sha256);
  });
});

describe('pairing wire vectors, as the router receives them', () => {
  for (const vector of VECTORS.frames.filter((f) => f.direction === 'toRouter' && f.expect.router)) {
    test(`${vector.name} (${vector.valid ? 'valid' : 'invalid'})`, async () => {
      const h = await harness();
      const subs: Record<string, string> = { code: h.pairing.issue().code };
      const socket = await pinned(h.port, h.fp);
      try {
        if (vector.after) {
          socket.write(wireBytes(vectorNamed(vector.after), subs));
          const ok = await nextFrame(socket);
          assert.equal(ok?.type, 'pair.ok', `${vector.after} is accepted before ${vector.name} is sent`);
          subs.phoneId = String(ok?.phoneId);
        }
        socket.write(wireBytes(vector, subs));
        const reply = await nextFrame(socket);

        const expected = vector.expect.router;
        if (!expected) throw new Error(`${vector.name} has no router expectation`);
        if (expected.reply === 'closed') {
          assert.equal(reply, undefined, 'the router answers nothing and closes');
        } else {
          assert.equal(reply?.type, expected.reply);
          if (expected.reason !== undefined) assert.equal(reply?.reason, expected.reason);
          if (expected.found !== undefined) assert.equal(reply?.found, expected.found);
          // The router's answer has exactly the keys the valid vector for that answer has, so the two cannot drift.
          const twinName = reply?.type === 'pair.ok' ? 'pair.ok' : `pair.refused.${String(reply?.reason)}`;
          const twin = VECTORS.frames.find((f) => f.name === twinName);
          if (twin?.body && reply) assert.deepEqual(Object.keys(reply).sort(), Object.keys(twin.body).sort());
        }
        if (expected.recorded !== undefined) {
          assert.equal(readPairedPhones(h.dir).length > 0, expected.recorded, 'a confirmed record exists only after the ack');
        }
      } finally {
        socket.destroy();
        await h.close();
      }
    });
  }
});
