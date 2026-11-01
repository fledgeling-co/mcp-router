import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { createHash, createSign, generateKeyPairSync, type KeyObject } from 'node:crypto';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { connect, type TLSSocket } from 'node:tls';
import { fileURLToPath } from 'node:url';
import { Pairing, PAIRING_LIFETIME_MS } from '../src/pairing.js';
import { certificateFingerprint, loadOrCreatePairingIdentity } from '../src/pairing-identity.js';
import { startPairing, PAIRING_FRAME_MAX, INBOX_FRAME_MAX, PAIRING_CONNECTIONS_MAX, type PairingAdvertiser } from '../src/pairing-listener.js';
import { readPairedPhones, removePairedPhone } from '../src/paired-phones.js';
import { INBOX_FILE, InboxStore, reviewDigestOf } from '../src/inbox.js';
import { inboxSignedString } from '../src/inbox-submit.js';
import type { RegistryEntry } from '../src/registry.js';
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

/** What a test may change about the listener it drives. Everything else is the same for every test. */
interface HarnessOptions {
  idleMs?: number;
  lookup?: (id: string) => Promise<RegistryEntry | null>;
  clock?: () => number;
}

async function harness(pairing = new Pairing(), options: HarnessOptions = {}): Promise<Harness> {
  const dir = mkdtempSync(join(home, 'run-'));
  const running = await startPairing(
    { enabled: true, host: '127.0.0.1', port: 0 },
    {
      dir,
      pairing,
      macName: MAC_NAME,
      idleMs: options.idleMs ?? IDLE_MS,
      inbox: new InboxStore(join(dir, INBOX_FILE)),
      // Nothing resolves unless a test says so. The live lookup would reach the registry from a unit test.
      lookup: options.lookup ?? (async () => null),
      clock: options.clock,
    }
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
  channel?: 'inbox';
  after?: string;
  body?: Record<string, unknown>;
  rawBody?: string;
  declaredLength?: number;
  trailing?: string;
  expect: {
    router?: {
      reply: 'pair.ok' | 'pair.refused' | 'closed' | 'inbox.nonce' | 'inbox.receipt' | 'inbox.refused';
      reason?: string;
      found?: number;
      recorded?: boolean;
      received?: Array<{ id: string; state: string }>;
    };
    phone?: Record<string, unknown>;
  };
}

interface WireVectors {
  placeholders: Record<string, string>;
  fingerprint: { certificate: string; sha256: string };
  inboxSigning: { nonce: string; phoneId: string; items: string; itemsSha256: string; signedString: string };
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
  for (const vector of VECTORS.frames.filter((f) => f.direction === 'toRouter' && f.expect.router && f.channel !== 'inbox')) {
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

/*
 * The inbox submit (planning/plans/plan-phone-inbox.md §1.2 to §1.4, §5, §7). The phone is a test double: it pairs
 * through the real pairing frames, then signs its submits with the key it sent. The signed string is built here by the
 * phone's rule, and the vectors pin that rule's bytes, so a router that built a different string fails in both places.
 */

interface PhoneKeys {
  privateKey: KeyObject;
  spki: string;
}

interface PairedPhone {
  phoneId: string;
  keys: PhoneKeys;
}

function phoneKeys(): PhoneKeys {
  const { publicKey, privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  return { privateKey, spki: publicKey.export({ type: 'spki', format: 'der' }).toString('base64') };
}

/** Pairs a phone through the real frames. It is confirmed once the ack has been written and the router has closed. */
async function pairedPhone(h: Harness, keys = phoneKeys()): Promise<PairedPhone> {
  const { code } = h.pairing.issue();
  const link = await pinned(h.port, h.fp);
  link.write(frame(request(code, { phoneKey: keys.spki })));
  const ok = await nextFrame(link);
  link.write(frame({ type: 'pair.ack', v: 1, phoneId: ok?.phoneId }));
  assert.equal(await nextFrame(link), undefined);
  return { phoneId: String(ok?.phoneId), keys };
}

/** The string a phone signs (§1.3), built by the phone's rule. */
function signedBy(nonce: string, phoneId: string, items: string): string {
  return ['mcp-router-inbox-v1', nonce, phoneId, createHash('sha256').update(items, 'utf8').digest('hex')].join('\n');
}

function sign(keys: PhoneKeys, nonce: string, phoneId: string, items: string): string {
  return createSign('SHA256').update(signedBy(nonce, phoneId, items), 'utf8').sign(keys.privateKey).toString('base64');
}

/** The `items` string a phone sends: a JSON array of picks, each a coordinate and the name the phone shows for it. */
function itemsOf(...ids: string[]): string {
  return JSON.stringify(ids.map((id) => ({ id, displayName: id.split('/').pop() ?? id, queuedAt: '2026-10-20T09:00:00Z' })));
}

function entry(id: string): RegistryEntry {
  const name = id.split('/').pop() ?? id;
  return { id, name, displayName: name, description: 'a test entry', source: 'official' };
}

/** A registry that holds the ids named and answers null for any other. `asked` records every lookup it was given. */
function registryOf(ids: string[]) {
  const asked: string[] = [];
  const lookup = async (id: string): Promise<RegistryEntry | null> => {
    asked.push(id);
    return ids.includes(id) ? entry(id) : null;
  };
  return { lookup, asked };
}

/** Opens a pinned connection and sends inbox.hello for the phone. `reply` is undefined when the router closed instead. */
async function openHello(h: Harness, phoneId: string, over: Record<string, unknown> = {}) {
  const link = await pinned(h.port, h.fp);
  link.write(frame({ type: 'inbox.hello', v: 1, phoneId, ...over }));
  const reply = await nextFrame(link);
  return { link, reply };
}

/** A submit for the nonce the router issued on this connection, signed by the phone over the items it carries. */
function submitFor(phone: PairedPhone, nonce: string, items: string, over: Record<string, unknown> = {}): Record<string, unknown> {
  return { type: 'inbox.submit', v: 1, phoneId: phone.phoneId, nonce, items, sig: sign(phone.keys, nonce, phone.phoneId, items), ...over };
}

function rowsOf(dir: string): Array<Record<string, unknown>> {
  return (JSON.parse(readFileSync(join(dir, INBOX_FILE), 'utf8')) as { rows: Array<Record<string, unknown>> }).rows;
}

describe('inbox hello', () => {
  test('a confirmed phone is given a 32-byte nonce, and nothing is stored', async () => {
    const h = await harness();
    try {
      const phone = await pairedPhone(h);
      const { link, reply } = await openHello(h, phone.phoneId);
      assert.deepEqual(Object.keys(reply ?? {}).sort(), ['nonce', 'type', 'v']);
      assert.equal(reply?.type, 'inbox.nonce');
      assert.equal(reply?.v, 1);
      assert.match(String(reply?.nonce), /^[A-Za-z0-9_-]{43}$/, 'base64url of 32 bytes');
      assert.equal(Buffer.from(String(reply?.nonce), 'base64url').length, 32);
      assert.equal(existsSync(join(h.dir, INBOX_FILE)), false, 'a hello is not a submit');
      link.destroy();
    } finally {
      await h.close();
    }
  });

  test('a phone that is not confirmed is refused unknownPhone, whether it is pending or was never paired', async () => {
    const h = await harness();
    try {
      const { code } = h.pairing.issue();
      const pending = await pinned(h.port, h.fp);
      pending.write(frame(request(code)));
      const ok = await nextFrame(pending);
      assert.equal(ok?.type, 'pair.ok');

      const awaiting = await openHello(h, String(ok?.phoneId));
      assert.deepEqual(awaiting.reply, { type: 'inbox.refused', v: 1, reason: 'unknownPhone' }, 'a pending phone has no key here');
      const stranger = await openHello(h, 'never-paired');
      assert.deepEqual(stranger.reply, { type: 'inbox.refused', v: 1, reason: 'unknownPhone' });
      pending.destroy();
      awaiting.link.destroy();
      stranger.link.destroy();
    } finally {
      await h.close();
    }
  });

  test('a hello with another version is refused unsupportedVersion with the version it found, and one with no phoneId is badRequest', async () => {
    const h = await harness();
    try {
      const phone = await pairedPhone(h);
      const version = await openHello(h, phone.phoneId, { v: 2 });
      assert.deepEqual(version.reply, { type: 'inbox.refused', v: 1, reason: 'unsupportedVersion', found: 2 });
      const missing = await pinned(h.port, h.fp);
      missing.write(frame({ type: 'inbox.hello', v: 1 }));
      assert.deepEqual(await nextFrame(missing), { type: 'inbox.refused', v: 1, reason: 'badRequest' });
    } finally {
      await h.close();
    }
  });
});

describe('inbox submit, a signed batch', () => {
  test('a valid submit is stored waiting, against the phone and its entry, at 0600, and receipted once it is on disk', async () => {
    const { lookup } = registryOf(['io.example/atlas']);
    const h = await harness(new Pairing(), { lookup });
    try {
      const phone = await pairedPhone(h);
      const { link, reply } = await openHello(h, phone.phoneId);
      link.write(frame(submitFor(phone, String(reply?.nonce), itemsOf('io.example/atlas'))));
      assert.deepEqual(await nextFrame(link), {
        type: 'inbox.receipt',
        v: 1,
        received: [{ id: 'io.example/atlas', state: 'waiting' }],
      });

      const [row] = rowsOf(h.dir);
      assert.equal(row.id, 'io.example/atlas');
      assert.equal(row.phoneId, phone.phoneId);
      assert.equal(row.deviceName, PHONE_NAME, 'the device is the confirmed phone, not anything the frame said');
      assert.equal(row.queuedAt, '2026-10-20T09:00:00Z');
      assert.equal(row.state, 'waiting');
      assert.deepEqual(row.resolved, entry('io.example/atlas'), 'the entry is the router’s own lookup');
      assert.equal(row.reviewDigest, reviewDigestOf(entry('io.example/atlas')));
      assert.equal(statSync(join(h.dir, INBOX_FILE)).mode & 0o777, 0o600);
      assert.equal(await nextFrame(link), undefined, 'the router closes once the receipt is sent');
    } finally {
      await h.close();
    }
  });

  test('a pick the registry does not hold is stored as a Partial row, with resolved null', async () => {
    const { lookup } = registryOf([]);
    const h = await harness(new Pairing(), { lookup });
    try {
      const phone = await pairedPhone(h);
      const { link, reply } = await openHello(h, phone.phoneId);
      link.write(frame(submitFor(phone, String(reply?.nonce), itemsOf('io.example/unknown'))));
      assert.equal((await nextFrame(link))?.type, 'inbox.receipt');
      const [row] = rowsOf(h.dir);
      assert.equal(row.resolved, null);
      assert.equal(row.reviewDigest, reviewDigestOf(null));
    } finally {
      await h.close();
    }
  });

  test('a second submit of an id already held answers duplicate, keeps the first row, and does not look the id up again', async () => {
    // The registry can change between the two submits. A later registry that no longer holds the id would make a
    // Partial row, so the first row has to survive and the second lookup must never be asked.
    let registry = registryOf(['io.example/atlas']);
    const h = await harness(new Pairing(), { lookup: (id) => registry.lookup(id) });
    try {
      const phone = await pairedPhone(h);
      const first = await openHello(h, phone.phoneId);
      first.link.write(frame(submitFor(phone, String(first.reply?.nonce), itemsOf('io.example/atlas'))));
      assert.equal((await nextFrame(first.link))?.type, 'inbox.receipt');

      registry = registryOf([]);
      const second = await openHello(h, phone.phoneId);
      second.link.write(frame(submitFor(phone, String(second.reply?.nonce), itemsOf('io.example/atlas'))));
      assert.deepEqual(await nextFrame(second.link), {
        type: 'inbox.receipt',
        v: 1,
        received: [{ id: 'io.example/atlas', state: 'duplicate' }],
      });
      assert.equal(registry.asked.length, 0, 'a held id is not looked up again');
      assert.equal(rowsOf(h.dir).length, 1);
      assert.deepEqual(rowsOf(h.dir)[0].resolved, entry('io.example/atlas'));
    } finally {
      await h.close();
    }
  });

  test('a store that cannot be written sends no receipt, and the file it had is kept whole', async () => {
    const { lookup } = registryOf(['io.example/one', 'io.example/two']);
    const h = await harness(new Pairing(), { lookup });
    try {
      const phone = await pairedPhone(h);
      const first = await openHello(h, phone.phoneId);
      first.link.write(frame(submitFor(phone, String(first.reply?.nonce), itemsOf('io.example/one'))));
      assert.equal((await nextFrame(first.link))?.type, 'inbox.receipt');

      // The file exists and its directory now refuses a new file. The read still works and the write does not.
      chmodSync(h.dir, 0o500);
      try {
        const second = await openHello(h, phone.phoneId);
        second.link.write(frame(submitFor(phone, String(second.reply?.nonce), itemsOf('io.example/two'))));
        assert.equal(await nextFrame(second.link), undefined, 'a receipt is sent only after the write, so none is sent');
      } finally {
        chmodSync(h.dir, 0o700);
      }
      assert.deepEqual(rowsOf(h.dir).map((r) => r.id), ['io.example/one']);
    } finally {
      await h.close();
    }
  });

  test('a signature from another key is refused badSignature, and nothing is stored', async () => {
    const h = await harness(new Pairing(), { lookup: registryOf(['io.example/atlas']).lookup });
    try {
      const phone = await pairedPhone(h);
      const { link, reply } = await openHello(h, phone.phoneId);
      const items = itemsOf('io.example/atlas');
      const impostor: PairedPhone = { phoneId: phone.phoneId, keys: phoneKeys() };
      link.write(frame(submitFor(impostor, String(reply?.nonce), items)));
      assert.deepEqual(await nextFrame(link), { type: 'inbox.refused', v: 1, reason: 'badSignature' });
      assert.equal(existsSync(join(h.dir, INBOX_FILE)), false);
    } finally {
      await h.close();
    }
  });

  test('items changed after signing are refused badSignature, and nothing is stored', async () => {
    const h = await harness(new Pairing(), { lookup: registryOf(['io.example/atlas', 'io.example/other']).lookup });
    try {
      const phone = await pairedPhone(h);
      const { link, reply } = await openHello(h, phone.phoneId);
      const signedItems = itemsOf('io.example/atlas');
      const sentItems = itemsOf('io.example/other');
      const body = submitFor(phone, String(reply?.nonce), signedItems, { items: sentItems });
      link.write(frame(body));
      assert.deepEqual(await nextFrame(link), { type: 'inbox.refused', v: 1, reason: 'badSignature' });
      assert.equal(existsSync(join(h.dir, INBOX_FILE)), false);
    } finally {
      await h.close();
    }
  });

  test('a captured submit sent on a new connection is staleNonce, not a bad signature, and the phone is not struck', async () => {
    const h = await harness(new Pairing(), { lookup: registryOf(['io.example/atlas']).lookup });
    try {
      const phone = await pairedPhone(h);
      const items = itemsOf('io.example/atlas');
      const a = await openHello(h, phone.phoneId);
      const captured = submitFor(phone, String(a.reply?.nonce), items);
      a.link.write(frame(captured));
      assert.equal((await nextFrame(a.link))?.type, 'inbox.receipt');

      const b = await openHello(h, phone.phoneId);
      b.link.write(frame(captured));
      assert.deepEqual(await nextFrame(b.link), { type: 'inbox.refused', v: 1, reason: 'staleNonce' });

      const c = await openHello(h, phone.phoneId);
      c.link.write(frame(submitFor(phone, String(c.reply?.nonce), items)));
      assert.equal((await nextFrame(c.link))?.type, 'inbox.receipt', 'a replay is not counted as a bad signature');
    } finally {
      await h.close();
    }
  });

  test('a nonce older than sixty seconds is staleNonce, and one at exactly sixty seconds is still good', async () => {
    let now = Date.parse('2026-10-20T09:00:00.000Z');
    const h = await harness(new Pairing(), { lookup: registryOf(['io.example/atlas']).lookup, clock: () => now });
    try {
      const phone = await pairedPhone(h);
      const items = itemsOf('io.example/atlas');

      const late = await openHello(h, phone.phoneId);
      now += 60_001;
      late.link.write(frame(submitFor(phone, String(late.reply?.nonce), items)));
      assert.deepEqual(await nextFrame(late.link), { type: 'inbox.refused', v: 1, reason: 'staleNonce' });

      const onTime = await openHello(h, phone.phoneId);
      now += 60_000;
      onTime.link.write(frame(submitFor(phone, String(onTime.reply?.nonce), items)));
      assert.equal((await nextFrame(onTime.link))?.type, 'inbox.receipt');
    } finally {
      await h.close();
    }
  });

  test('fifty items are accepted though they are larger than the pairing frame cap, and fifty-one are tooManyItems', async () => {
    const ids = Array.from({ length: 51 }, (_, i) => `io.example/item-${i}`);
    const { lookup } = registryOf(ids);
    const h = await harness(new Pairing(), { lookup });
    try {
      const phone = await pairedPhone(h);
      const long = (i: number) => ({ id: ids[i], displayName: 'x'.repeat(200), queuedAt: '2026-10-20T09:00:00Z' });
      const fifty = JSON.stringify(Array.from({ length: 50 }, (_, i) => long(i)));
      assert.ok(Buffer.byteLength(fifty, 'utf8') > PAIRING_FRAME_MAX, 'the batch does not fit the pairing cap');

      const ok = await openHello(h, phone.phoneId);
      ok.link.write(frame(submitFor(phone, String(ok.reply?.nonce), fifty)));
      const receipt = await nextFrame(ok.link);
      assert.equal(receipt?.type, 'inbox.receipt');
      assert.equal((receipt?.received as unknown[]).length, 50);
      assert.equal(rowsOf(h.dir).length, 50);

      const over = await openHello(h, phone.phoneId);
      over.link.write(frame(submitFor(phone, String(over.reply?.nonce), JSON.stringify(Array.from({ length: 51 }, (_, i) => long(i))))));
      assert.deepEqual(await nextFrame(over.link), { type: 'inbox.refused', v: 1, reason: 'tooManyItems' });
      assert.equal(rowsOf(h.dir).length, 50, 'a refused batch stores nothing');
    } finally {
      await h.close();
    }
  });

  test('an id or displayName over 200 characters, an empty batch, and a batch that is not an array are badRequest, and nothing is stored', async () => {
    const h = await harness(new Pairing(), { lookup: registryOf([]).lookup });
    try {
      const phone = await pairedPhone(h);
      const cases: Array<[string, string]> = [
        ['an id of 201 characters', JSON.stringify([{ id: 'a'.repeat(201), displayName: 'A', queuedAt: '2026-10-20T09:00:00Z' }])],
        ['a displayName of 201 characters', JSON.stringify([{ id: 'io.example/a', displayName: 'a'.repeat(201), queuedAt: '2026-10-20T09:00:00Z' }])],
        ['an empty batch', '[]'],
        ['items that are not JSON', 'not json'],
        ['an object rather than an array', '{"id":"io.example/a"}'],
        ['a queuedAt that is not an instant', JSON.stringify([{ id: 'io.example/a', displayName: 'A', queuedAt: 'soon' }])],
      ];
      for (const [label, items] of cases) {
        const { link, reply } = await openHello(h, phone.phoneId);
        link.write(frame(submitFor(phone, String(reply?.nonce), items)));
        assert.deepEqual(await nextFrame(link), { type: 'inbox.refused', v: 1, reason: 'badRequest' }, label);
      }
      assert.equal(existsSync(join(h.dir, INBOX_FILE)), false);
    } finally {
      await h.close();
    }
  });

  test('a submit whose declared size is over the inbox cap is refused on its header alone', async () => {
    const h = await harness(new Pairing(), { lookup: registryOf([]).lookup });
    try {
      const phone = await pairedPhone(h);
      const { link } = await openHello(h, phone.phoneId);
      const head = Buffer.alloc(4);
      head.writeUInt32BE(INBOX_FRAME_MAX + 1);
      link.write(Buffer.concat([head, Buffer.from('{}', 'utf8')]));
      assert.deepEqual(await nextFrame(link), { type: 'inbox.refused', v: 1, reason: 'frameTooLarge' });
    } finally {
      await h.close();
    }
  });

  test('a submit with another version is refused unsupportedVersion with the version it found', async () => {
    const h = await harness(new Pairing(), { lookup: registryOf([]).lookup });
    try {
      const phone = await pairedPhone(h);
      const { link, reply } = await openHello(h, phone.phoneId);
      link.write(frame(submitFor(phone, String(reply?.nonce), itemsOf('io.example/a'), { v: 2 })));
      assert.deepEqual(await nextFrame(link), { type: 'inbox.refused', v: 1, reason: 'unsupportedVersion', found: 2 });
    } finally {
      await h.close();
    }
  });

  test('a phone revoked after its hello, and before its submit, is refused unknownPhone', async () => {
    const h = await harness(new Pairing(), { lookup: registryOf(['io.example/atlas']).lookup });
    try {
      const phone = await pairedPhone(h);
      const { link, reply } = await openHello(h, phone.phoneId);
      assert.equal(removePairedPhone(h.dir, phone.phoneId)?.phoneId, phone.phoneId);
      link.write(frame(submitFor(phone, String(reply?.nonce), itemsOf('io.example/atlas'))));
      assert.deepEqual(await nextFrame(link), { type: 'inbox.refused', v: 1, reason: 'unknownPhone' });
      assert.equal(existsSync(join(h.dir, INBOX_FILE)), false);
    } finally {
      await h.close();
    }
  });
});

describe('inbox submit, a phone whose signature keeps failing', () => {
  /** One connection that submits a signature from another key. Answers the refusal it gets. */
  async function badSignature(h: Harness, phone: PairedPhone): Promise<Record<string, unknown> | undefined> {
    const { link, reply } = await openHello(h, phone.phoneId);
    if (reply?.type !== 'inbox.nonce') return reply;
    link.write(frame(submitFor({ phoneId: phone.phoneId, keys: phoneKeys() }, String(reply.nonce), itemsOf('io.example/atlas'))));
    return nextFrame(link);
  }

  test('three bad signatures in a row refuse the phone for ten minutes, then it is admitted again', async () => {
    let now = Date.parse('2026-10-20T09:00:00.000Z');
    const h = await harness(new Pairing(), { lookup: registryOf(['io.example/atlas']).lookup, clock: () => now });
    try {
      const phone = await pairedPhone(h);
      for (let i = 0; i < 3; i++) {
        assert.deepEqual(await badSignature(h, phone), { type: 'inbox.refused', v: 1, reason: 'badSignature' });
      }

      const locked = await openHello(h, phone.phoneId);
      assert.equal(locked.reply, undefined, 'a locked phone is closed with nothing said');
      now += 10 * 60_000 - 1;
      assert.equal((await openHello(h, phone.phoneId)).reply, undefined, 'still locked a millisecond before ten minutes');
      now += 1;
      assert.equal((await openHello(h, phone.phoneId)).reply?.type, 'inbox.nonce', 'admitted at ten minutes');
    } finally {
      await h.close();
    }
  });

  test('a valid submit clears the count, so two bad signatures, a good one and two more do not lock the phone', async () => {
    const h = await harness(new Pairing(), { lookup: registryOf(['io.example/atlas']).lookup });
    try {
      const phone = await pairedPhone(h);
      for (let i = 0; i < 2; i++) await badSignature(h, phone);

      const good = await openHello(h, phone.phoneId);
      good.link.write(frame(submitFor(phone, String(good.reply?.nonce), itemsOf('io.example/atlas'))));
      assert.equal((await nextFrame(good.link))?.type, 'inbox.receipt');

      for (let i = 0; i < 2; i++) await badSignature(h, phone);
      assert.equal((await openHello(h, phone.phoneId)).reply?.type, 'inbox.nonce', 'two in a row is not three');
    } finally {
      await h.close();
    }
  });
});

describe('inbox frames, the wire is fenced', () => {
  test('at most eight connections are held at once, and a ninth is closed without an answer', async () => {
    const h = await harness(new Pairing(), { idleMs: 5_000 });
    const held: TLSSocket[] = [];
    try {
      for (let i = 0; i < 8; i++) held.push(await pinned(h.port, h.fp));
      await until(() => h.open() === 8);
      const ninth = await pinned(h.port, h.fp);
      ninth.on('error', () => undefined);
      assert.equal(await nextFrame(ninth), undefined);
      assert.equal(h.open(), 8);
    } finally {
      for (const socket of held) socket.destroy();
      await h.close();
    }
  });

  test('after an inbox hello, a pairing request is closed with no answer, and its code stays live', async () => {
    const h = await harness(new Pairing(), { lookup: registryOf([]).lookup });
    try {
      const phone = await pairedPhone(h);
      const { link, reply } = await openHello(h, phone.phoneId);
      assert.equal(reply?.type, 'inbox.nonce', 'the connection is in the inbox exchange before the pairing frame is sent');
      const { code } = h.pairing.issue();
      link.write(frame(request(code)));
      assert.equal(await nextFrame(link), undefined);
      assert.ok(h.pairing.current(), 'the code was never decided');
      assert.deepEqual(h.pairing.awaitingAck(), []);
    } finally {
      await h.close();
    }
  });
});

/*
 * The inbox vectors (planning/pairing/wire-vectors.json, `channel: "inbox"`). The phone pairs first, so `{{phoneId}}` is
 * its id, and `{{sig}}` is its own signature over the body's nonce, phoneId and items.
 */
function inboxWireBytes(vector: WireVector, subs: Record<string, string>, keys: PhoneKeys): Buffer {
  const body = JSON.parse(
    JSON.stringify(vector.body).replace(/\{\{(\w+)\}\}/g, (match: string, key: string) => {
      if (key === 'sig') return match;
      if (!(key in subs)) throw new Error(`${vector.name} has no value for {{${key}}}`);
      return subs[key];
    })
  ) as Record<string, string>;
  if (body.sig === '{{sig}}') body.sig = sign(keys, body.nonce, body.phoneId, body.items);
  const payload = Buffer.from(JSON.stringify(body), 'utf8');
  const head = Buffer.alloc(4);
  head.writeUInt32BE(vector.declaredLength ?? payload.length);
  return Buffer.concat([head, payload]);
}

describe('inbox wire vectors, as the router receives them', () => {
  test('the signed string the vectors pin is the one the phone builds and the router builds', () => {
    const s = VECTORS.inboxSigning;
    assert.equal(createHash('sha256').update(s.items, 'utf8').digest('hex'), s.itemsSha256);
    assert.equal(signedBy(s.nonce, s.phoneId, s.items), s.signedString);
    assert.equal(inboxSignedString(s.nonce, s.phoneId, s.items), s.signedString);
  });

  for (const vector of VECTORS.frames.filter((f) => f.channel === 'inbox' && f.direction === 'toRouter')) {
    test(`${vector.name} (${vector.valid ? 'valid' : 'invalid'})`, async () => {
      const h = await harness(new Pairing(), { lookup: registryOf(['io.example/atlas']).lookup });
      const phone = await pairedPhone(h);
      const subs: Record<string, string> = { phoneId: phone.phoneId };
      const socket = await pinned(h.port, h.fp);
      try {
        if (vector.after) {
          const hello = vectorNamed(vector.after);
          socket.write(inboxWireBytes(hello, subs, phone.keys));
          const nonce = await nextFrame(socket);
          assert.equal(nonce?.type, 'inbox.nonce', `${vector.after} is answered before ${vector.name} is sent`);
          subs.nonce = String(nonce?.nonce);
        }
        socket.write(inboxWireBytes(vector, subs, phone.keys));
        const reply = await nextFrame(socket);

        const expected = vector.expect.router;
        if (!expected) throw new Error(`${vector.name} has no router expectation`);
        if (expected.reply === 'closed') {
          assert.equal(reply, undefined, 'the router answers nothing and closes');
        } else {
          assert.equal(reply?.type, expected.reply);
          if (expected.reason !== undefined) assert.equal(reply?.reason, expected.reason);
          if (expected.found !== undefined) assert.equal(reply?.found, expected.found);
          if (expected.received !== undefined) assert.deepEqual(reply?.received, expected.received);
          // The answer has exactly the keys its toPhone twin has, so the two cannot drift.
          const twinName = reply?.type === 'inbox.refused' ? `inbox.refused.${String(reply.reason)}` : String(reply?.type);
          const twin = VECTORS.frames.find((f) => f.name === twinName);
          if (!twin?.body) throw new Error(`no toPhone vector named ${twinName}`);
          assert.deepEqual(Object.keys(reply ?? {}).sort(), Object.keys(twin.body).sort());
        }
      } finally {
        socket.destroy();
        await h.close();
      }
    });
  }
});

describe('the listener reports whether it is advertising', () => {
  async function started(advertise?: PairingAdvertiser) {
    const dir = mkdtempSync(join(home, 'adv-'));
    const running = await startPairing(
      { enabled: true, host: '127.0.0.1', port: 0 },
      { dir, pairing: new Pairing(), macName: MAC_NAME, idleMs: IDLE_MS, advertise }
    );
    if (!running) throw new Error('an enabled listener did not start');
    return running;
  }

  test('advertising is true while an announcement is live, and false once it is withdrawn', async () => {
    let stopped = false;
    const running = await started(() => ({
      stop: async () => {
        stopped = true;
      },
    }));
    assert.equal(running.advertising, true);
    assert.equal(running.host, '127.0.0.1');
    assert.match(running.fingerprint, /^[0-9a-f]{64}$/);
    await running.close();
    assert.equal(stopped, true);
  });

  test('a failed announcement leaves the listener bound and reports it not advertising', async () => {
    const running = await started(() => {
      throw new Error('no multicast on this network');
    });
    assert.equal(running.advertising, false);
    assert.ok(running.port > 0, 'the listener is still bound');
    await running.close();
  });

  test('with no advertiser passed, nothing is announced and the listener says so', async () => {
    const running = await started();
    assert.equal(running.advertising, false);
    await running.close();
  });
});


describe('inbox submit, revocation during registry resolution', () => {
  test('a phone revoked while the registry lookup waits receives no receipt and stores nothing', async () => {
    let resolveLookup!: (value: RegistryEntry | null) => void;
    let lookupStarted = false;
    const h = await harness(new Pairing(), { idleMs: 5_000, lookup: async () => {
      lookupStarted = true;
      return await new Promise<RegistryEntry | null>((resolve) => { resolveLookup = resolve; });
    } });
    try {
      const phone = await pairedPhone(h);
      const { link, reply } = await openHello(h, phone.phoneId);
      link.write(frame(submitFor(phone, String(reply?.nonce), itemsOf('io.example/alpha'))));
      const answer = nextFrame(link);
      await until(() => lookupStarted);
      removePairedPhone(h.dir, phone.phoneId);
      resolveLookup(entry('io.example/alpha'));
      assert.deepEqual(await answer, { type: 'inbox.refused', v: 1, reason: 'unknownPhone' });
      assert.equal(existsSync(join(h.dir, INBOX_FILE)), false, 'revocation prevents a pending lookup from committing picks');
    } finally {
      await h.close();
    }
  });
});
