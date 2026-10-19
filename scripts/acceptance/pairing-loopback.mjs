#!/usr/bin/env node
/*
 * The driver behind scripts/acceptance/pairing-loopback.sh. The shell owns the router's lifecycle;
 * this file owns the checks.
 *
 * It plays the phone. The phone is a stand-in written from planning/plans/plan-pairing-handshake.md
 * §2.4 and planning/pairing/wire-vectors.json, not LivePairingService: the production TLS transport
 * (B5) is not merged, so the Swift service cannot reach a socket. What this proves is the router's half
 * of the wire over a real TLS socket, and the record order the stand-in keeps. That order follows §7:
 * the phone writes its record after pair.ok and before the ack. A check on the phone side is a check on
 * this stand-in, and the lane's report says so.
 *
 * Exit codes: 0 every check held; 1 a check failed; 2 this driver could not run.
 */
import { createHash, generateKeyPairSync } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { connect } from 'node:tls';
import { parseArgs } from 'node:util';

const PHONE_NAME = "Luke's iPhone";
const PAIRED_FILE = 'paired-phones.json';
const MUTANTS = ['', 'skip-ack'];

function blocked(message) {
  console.error(`BLOCKED: ${message}`);
  process.exit(2);
}

let args;
try {
  ({ values: args } = parseArgs({
    options: {
      'router-home': { type: 'string' },
      'control-port': { type: 'string' },
      'pairing-port': { type: 'string' },
      'phone-home': { type: 'string' },
      mutant: { type: 'string', default: '' },
    },
  }));
} catch (err) {
  blocked(err.message);
}

const routerHome = args['router-home'];
const phoneHome = args['phone-home'];
const controlPort = args['control-port'];
const pairingPortArg = args['pairing-port'];
const mutant = args.mutant;

if (!routerHome || !phoneHome || !controlPort || !pairingPortArg) {
  blocked('the driver needs --router-home, --phone-home, --control-port and --pairing-port');
}
if (!MUTANTS.includes(mutant)) blocked(`there is no mutant called "${mutant}"`);

const pairingPort = Number(pairingPortArg);
const controlBase = `http://127.0.0.1:${controlPort}`;
const pairedPath = join(routerHome, PAIRED_FILE);
const phoneRecordPath = join(phoneHome, 'paired-mac.json');

// Read, never printed. It is the only credential this lane touches, and it lives in the scratch home.
const tokenPath = join(routerHome, 'control.token');
if (!existsSync(tokenPath)) blocked('the router wrote no control token');
const token = readFileSync(tokenPath, 'utf8').trim();

const sha256Hex = (bytes) => createHash('sha256').update(bytes).digest('hex');

// The pin a QR would carry. Read by openssl from the router's certificate file, so the expected value
// does not come from the same code that serves the certificate.
let fingerprint;
try {
  const der = execFileSync('openssl', ['x509', '-in', join(routerHome, 'pairing-cert.pem'), '-outform', 'DER']);
  fingerprint = sha256Hex(der);
} catch (err) {
  blocked(`could not read the router's certificate: ${err.message}`);
}

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

let failures = 0;
function check(held, message) {
  if (held) {
    console.log(`  ok — ${message}`);
  } else {
    failures += 1;
    console.log(`  FAIL — ${message}`);
  }
}

async function scenario(name, body) {
  console.log(name);
  try {
    await body();
  } catch (err) {
    check(false, `${name} could not complete: ${err.message}`);
  }
}

async function waitFor(test, ms) {
  const until = Date.now() + ms;
  while (Date.now() < until) {
    if (await test()) return true;
    await delay(100);
  }
  return false;
}

// ── The router, over its token-gated loopback control API ────────────────────────────────────────

async function control(method, path, body = {}) {
  const res = await fetch(`${controlBase}${path}`, {
    method,
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: method === 'POST' ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.json() };
}

async function mint() {
  const r = await control('POST', '/pairing/codes');
  if (r.status !== 201) throw new Error(`minting a code answered ${r.status}`);
  return r.body.code;
}

const state = async () => (await control('GET', '/pairing/state')).body;

// What the Mac has recorded, read from its file rather than from the API that wrote it.
const routerPhones = () => (existsSync(pairedPath) ? JSON.parse(readFileSync(pairedPath, 'utf8')).phones : []);

// ── The phone, as a stand-in ────────────────────────────────────────────────────────────────────

const newPhoneKey = () =>
  generateKeyPairSync('ec', { namedCurve: 'P-256' }).publicKey.export({ type: 'spki', format: 'der' }).toString('base64');

// A code one character from the live one, so it is well formed and certainly not the live code.
const wrongCode = (code) => (code[0] === 'Y' ? 'Z' : 'Y') + code.slice(1);

// A fingerprint that differs from the pin in its last hex digit.
const wrongPin = (hex) => hex.slice(0, -1) + (hex.endsWith('0') ? '1' : '0');

function frame(message) {
  const body = Buffer.from(JSON.stringify(message), 'utf8');
  const head = Buffer.alloc(4);
  head.writeUInt32BE(body.length);
  return Buffer.concat([head, body]);
}

/* The next whole frame on the socket: four bytes of big-endian length, then UTF-8 JSON. */
function readFrame(socket, ms = 5000) {
  return new Promise((resolve, reject) => {
    let buffered = Buffer.alloc(0);
    const finish = (error, value) => {
      clearTimeout(timer);
      socket.off('data', onData);
      socket.off('close', onClose);
      if (error) reject(error);
      else resolve(value);
    };
    const timer = setTimeout(() => finish(new Error('no frame arrived in time')), ms);
    const onData = (chunk) => {
      buffered = Buffer.concat([buffered, chunk]);
      if (buffered.length < 4) return;
      const length = buffered.readUInt32BE(0);
      if (buffered.length < 4 + length) return;
      try {
        finish(null, JSON.parse(buffered.subarray(4, 4 + length).toString('utf8')));
      } catch (err) {
        finish(err);
      }
    };
    const onClose = () => finish(new Error('the connection closed before a frame arrived'));
    socket.on('data', onData);
    socket.on('close', onClose);
  });
}

/*
 * A TLS 1.3 connection. `rejectUnauthorized: false` is deliberate: the router's certificate is self-signed
 * with no CA, so chain validation would refuse every router. The pin is the check instead, and the caller
 * runs it before any frame is written (planning/plans/plan-pairing-handshake.md §2.2). The same stance as
 * test/pairing-listener.test.ts.
 */
function dial() {
  return new Promise((resolve, reject) => {
    const socket = connect({ host: '127.0.0.1', port: pairingPort, minVersion: 'TLSv1.3', rejectUnauthorized: false });
    socket.setTimeout(5000, () => socket.destroy(new Error('the TLS handshake did not finish in time')));
    socket.once('error', reject);
    socket.once('secureConnect', () => {
      socket.setTimeout(0);
      socket.off('error', reject);
      resolve(socket);
    });
  });
}

// The phone's own record. Written after pair.ok and before the ack, as §7 orders it; restored when the
// ack cannot be sent, the way LivePairingService puts its earlier record back.
const readPhoneRecord = () => (existsSync(phoneRecordPath) ? readFileSync(phoneRecordPath, 'utf8') : null);

function writePhoneRecord(record) {
  writeFileSync(phoneRecordPath, `${JSON.stringify(record)}\n`, { mode: 0o600 });
}

function restorePhoneRecord(snapshot) {
  if (snapshot === null) rmSync(phoneRecordPath, { force: true });
  else writeFileSync(phoneRecordPath, snapshot, { mode: 0o600 });
}

/*
 * One phone's exchange. `pin` is what the phone compares the certificate against. `after` says what the
 * phone does once pair.ok arrives: 'ack' sends the ack; 'drop' closes the socket instead, which is what
 * a network loss between ok and ack looks like from the phone.
 */
async function exchange({ code, pin = fingerprint, after = 'ack' }) {
  const phoneKey = newPhoneKey();
  const socket = await dial();
  socket.on('error', () => undefined);

  if (sha256Hex(socket.getPeerCertificate(true).raw) !== pin) {
    socket.destroy();
    return { identityMismatch: true };
  }

  socket.write(frame({ type: 'pair.request', v: 1, code, phoneName: PHONE_NAME, phoneKey, entry: 'scan' }));
  const reply = await readFrame(socket);
  if (reply.type !== 'pair.ok') {
    socket.destroy();
    return { reply: reply.type, reason: reply.reason };
  }

  // Taken while the connection is open: the Mac must already hold the request, and must not yet have
  // recorded the phone.
  const routerAtOk = routerPhones().length;
  const heldWhileOpen = (await state()).awaitingAck.length;
  const phoneSnapshot = readPhoneRecord();
  writePhoneRecord({ macName: reply.macName, phoneId: reply.phoneId, phoneKey, phoneName: PHONE_NAME, fingerprint: pin });

  if (after === 'drop') {
    socket.destroy();
    restorePhoneRecord(phoneSnapshot);
    return {
      reply: reply.type,
      phoneId: reply.phoneId,
      phoneKey,
      routerAtOk,
      heldWhileOpen,
      acked: false,
      phoneRecordAfter: readPhoneRecord(),
      routerAfter: routerPhones(),
    };
  }

  const closed = new Promise((resolve) => socket.once('close', resolve));
  socket.write(frame({ type: 'pair.ack', v: 1, phoneId: reply.phoneId }));
  const closedInTime = await Promise.race([closed.then(() => true), delay(5000).then(() => false)]);
  socket.destroy();
  return {
    reply: reply.type,
    phoneId: reply.phoneId,
    phoneKey,
    routerAtOk,
    heldWhileOpen,
    acked: true,
    closedInTime,
    phoneRecordAfter: readPhoneRecord(),
    routerAfter: routerPhones(),
  };
}

// ── The checks ──────────────────────────────────────────────────────────────────────────────────

const acked = [];

let firstCode;
await scenario('a scan with the live code pairs, and the Mac records the phone only once the ack has gone out', async () => {
  check(routerPhones().length === 0, 'the scratch router starts with no paired phones');
  firstCode = await mint();
  const r = await exchange({ code: firstCode, after: mutant === 'skip-ack' ? 'drop' : 'ack' });
  check(r.reply === 'pair.ok', 'the router answers a valid scan with pair.ok');
  check(r.routerAtOk === 0, 'the Mac has no record when pair.ok arrives');
  check(r.heldWhileOpen === 1, 'the Mac holds the request while the phone is connected');
  check(r.phoneRecordAfter !== null, 'the phone writes its own record after pair.ok');
  check(r.routerAfter?.length === 1, 'the Mac records exactly one phone once the ack has gone out');
  const [record] = r.routerAfter ?? [];
  check(
    record?.phoneId === r.phoneId && record?.phoneKey === r.phoneKey && record?.phoneName === PHONE_NAME,
    'the record holds the phoneId, key and name the exchange carried'
  );
  if (r.acked) acked.push(r);
});

await scenario('a wrong code is refused and records nothing, and the live code survives it', async () => {
  const live = await mint();
  const before = routerPhones().length;
  const r = await exchange({ code: wrongCode(live) });
  check(r.reply === 'pair.refused' && r.reason === 'notRecognised', 'a code other than the live one is refused as notRecognised');
  check(routerPhones().length === before, 'the refused request leaves the record count unchanged');
  check((await state()).code?.code === live, 'one wrong guess does not burn the live code');
});

await scenario('a code burned by three wrong guesses is refused even when it is then given correctly', async () => {
  const live = await mint();
  const before = routerPhones().length;
  for (let guess = 1; guess <= 3; guess += 1) {
    const r = await exchange({ code: wrongCode(live) });
    check(r.reason === 'notRecognised', `wrong guess ${guess} of 3 is refused as notRecognised`);
  }
  check((await state()).code === null, 'the third wrong guess burns the live code');
  const r = await exchange({ code: live });
  check(r.reply === 'pair.refused' && r.reason === 'notRecognised', 'the burned code, given correctly, is refused as notRecognised');
  check(routerPhones().length === before, 'the burned code records nothing');
});

await scenario('a code that has already paired is refused as alreadyUsed', async () => {
  const before = routerPhones().length;
  const r = await exchange({ code: firstCode });
  check(r.reply === 'pair.refused' && r.reason === 'alreadyUsed', 'a paired code given again is refused as alreadyUsed');
  check(routerPhones().length === before, 'the repeated code records nothing');
});

await scenario('a certificate other than the one the QR named gets no request, and the code is still usable', async () => {
  const live = await mint();
  const before = routerPhones().length;
  const r = await exchange({ code: live, pin: wrongPin(fingerprint) });
  check(r.identityMismatch === true, 'the phone refuses a certificate that does not match the pin before it writes a frame');
  check(routerPhones().length === before, 'the mismatched attempt records nothing');
  const st = await state();
  check(st.code?.code === live && st.awaitingAck.length === 0, 'the Mac never saw the request, so the code is still live and nothing is held');
  const good = await exchange({ code: live });
  check(good.reply === 'pair.ok', 'the same code pairs once the phone pins the right certificate');
  if (good.acked) acked.push(good);
  check(routerPhones().length === before + 1, 'the Mac records the phone after the ack');
});

await scenario('a phone that drops between pair.ok and the ack leaves no record on either side', async () => {
  const live = await mint();
  const before = routerPhones().length;
  const phoneBefore = readPhoneRecord();
  const r = await exchange({ code: live, after: 'drop' });
  check(r.reply === 'pair.ok', 'the router answers the scan with pair.ok before the phone drops');
  check(r.heldWhileOpen === 1, 'the Mac holds the request while the phone is connected');
  const released = await waitFor(async () => (await state()).awaitingAck.length === 0, 5000);
  check(released, 'the Mac releases the held request once the connection drops');
  check(routerPhones().length === before, 'the Mac records nothing for the dropped phone');
  check(r.phoneRecordAfter === phoneBefore, 'the phone puts its own record back when the ack cannot be sent');
});

await scenario('the Mac holds exactly the phones whose ack it received, and nothing else', async () => {
  const phones = routerPhones();
  check(
    JSON.stringify(phones.map((p) => p.phoneId)) === JSON.stringify(acked.map((a) => a.phoneId)),
    'the paired-phones file lists the acked phoneIds, in order, and no others'
  );
  const last = acked.at(-1);
  if (last) {
    const stored = phones.at(-1);
    check(stored?.phoneKey === last.phoneKey, 'the stored key is the one the phone sent');
  }
});

const verdict = failures === 0 ? 'every check held' : `${failures} check(s) failed`;
console.log(`pairing-loopback: ${verdict}${mutant ? ` (mutant: ${mutant})` : ''}`);
process.exit(failures === 0 ? 0 : 1);
