#!/usr/bin/env node
// E1 (planning/plans/plan-pairing-typed-spake2.md §5): the TLS 1.3 exporter, and libsodium's
// edwards25519 maps against RFC 9380. A finding, not product code.
//
// Run from this directory after `swift build -j 4`:
//
//   node run-e1.mjs                        the spike
//   E1_MUTANT=nw-label node run-e1.mjs     the mutation: the Network.framework side uses another label
//
// Gates are what E1 must establish before G3 can be built: exporter equality on each leg, the
// exporter's declaration in the installed SDK, and the pinned libsodium version. They set the exit
// code. The libsodium comparison is a finding, reported with counts and negative controls, and does
// not set it.
//
// Exit codes: 0 when every gate holds, 1 when a gate fails, 2 when the spike could not run.

import { execFileSync, spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import tls from 'node:tls';

const here = dirname(fileURLToPath(import.meta.url));
const bin = join(here, '.build', 'debug');

// The label from plan §2.2. Both ends must use it, and the mutant is how the gate is seen to fail.
const LABEL = 'EXPORTER-mcp-router-pair-typed-v1';
const nwLabel = process.env.E1_MUTANT === 'nw-label' ? `${LABEL}-mutant` : LABEL;

const gates = [];
function gate(name, ok, detail = '') {
  gates.push(ok);
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  (${detail})` : ''}`);
}
function finding(text) {
  console.log(`FIND  ${text}`);
}

function makeCert(dir, name) {
  const key = join(dir, `${name}.key`);
  const cert = join(dir, `${name}.pem`);
  const der = join(dir, `${name}.der`);
  // Self-signed and short-lived, for loopback only. The certificate is its own trust anchor: each
  // client is given it, and verifies the server against it, so no verification is turned off. It is
  // a leaf (CA:FALSE, serverAuth). A plain `req -x509` certificate is CA:TRUE with no serverAuth,
  // and Network.framework refuses it with TLS alert 46 and -9808 "bad certificate format".
  execFileSync(
    'openssl',
    ['req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:prime256v1', '-nodes',
      '-keyout', key, '-out', cert, '-subj', `/CN=e1-${name}`, '-days', '1',
      '-addext', 'subjectAltName=IP:127.0.0.1',
      '-addext', 'basicConstraints=critical,CA:FALSE',
      '-addext', 'keyUsage=critical,digitalSignature',
      '-addext', 'extendedKeyUsage=serverAuth'],
    { stdio: 'ignore' }
  );
  execFileSync('openssl', ['x509', '-in', cert, '-outform', 'der', '-out', der], { stdio: 'ignore' });
  return { key: readFileSync(key), cert: readFileSync(cert), der };
}


// One TLS 1.3 server, which exports after each handshake and reports what it exported.
function serve(credentials) {
  return new Promise((resolve, reject) => {
    const server = tls.createServer({ ...credentials, minVersion: 'TLSv1.3' });
    const exported = new Promise((res, rej) => {
      server.once('secureConnection', (socket) => {
        try {
          res({ version: socket.getProtocol(), exporter: socket.exportKeyingMaterial(32, LABEL) });
        } catch (error) {
          rej(error);
        }
        socket.end();
      });
    });
    server.on('error', reject);
    server.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port, exported }));
  });
}

function connectNode(port, credentials) {
  return new Promise((resolve, reject) => {
    const socket = tls.connect({ host: '127.0.0.1', port, minVersion: 'TLSv1.3', ca: credentials.cert });
    socket.once('secureConnect', () => {
      const result = { version: socket.getProtocol(), exporter: socket.exportKeyingMaterial(32, LABEL) };
      socket.end();
      resolve(result);
    });
    socket.once('error', reject);
  });
}

// The Network.framework client. It is a separate process so that the Apple API is the only TLS
// stack on its side of the comparison.
function connectNetworkFramework(port, anchorDer) {
  return new Promise((resolve, reject) => {
    const child = spawn(join(bin, 'e1-nw-exporter'), [String(port), nwLabel, anchorDer]);
    let out = '';
    let err = '';
    child.stdout.on('data', (chunk) => { out += chunk; });
    child.stderr.on('data', (chunk) => { err += chunk; });
    child.on('error', reject);
    child.on('close', (code) => {
      if (code !== 0) {
        reject(new Error(`e1-nw-exporter exited ${code}: ${err.trim()}`));
        return;
      }
      const [version, hexValue] = out.trim().split(' ');
      resolve({ version, exporter: Buffer.from(hexValue, 'hex') });
    });
  });
}

async function exchange(credentials, client) {
  const { server, port, exported } = await serve(credentials);
  try {
    const clientSide = await client(port);
    const serverSide = await exported;
    return { clientSide, serverSide };
  } finally {
    server.close();
  }
}

function checkExporters(name, { clientSide, serverSide }, label) {
  const bothTls13 = clientSide.version === 'TLSv1.3' && serverSide.version === 'TLSv1.3';
  gate(`${name}: ${label} negotiated TLS 1.3 on both ends`, bothTls13,
    `client ${clientSide.version}, server ${serverSide.version}`);
  gate(`${name}: ${label} exporter is 32 bytes on both ends`,
    clientSide.exporter.length === 32 && serverSide.exporter.length === 32,
    `${clientSide.exporter.length}/${serverSide.exporter.length}`);
  gate(`${name}: ${label} both ends export equal bytes`,
    clientSide.exporter.equals(serverSide.exporter));
  return clientSide.exporter;
}

// --- The spike proper -------------------------------------------------------------------------

const workdir = mkdtempSync(join(tmpdir(), 'e1-'));
let exitCode = 0;
try {
  // Gate: the exporter has no context argument in the installed SDK. The header is the reference,
  // since the Apple documentation page for this function is not reachable (plan §1, "Not checked").
  const sdkPath = execFileSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { encoding: 'utf8' }).trim();
  const header = readFileSync(
    join(sdkPath, 'System/Library/Frameworks/Security.framework/Versions/A/Headers/SecProtocolMetadata.h'),
    'utf8'
  );
  const declaration = /sec_protocol_metadata_create_secret\(sec_protocol_metadata_t metadata, size_t label_len,\s*const char \*label, size_t exporter_length\);/;
  gate('SDK declares sec_protocol_metadata_create_secret with no context argument', declaration.test(header),
    sdkPath.split('/').slice(-1)[0]);

  const certA = makeCert(workdir, 'a');
  const certB = makeCert(workdir, 'b');

  // Each leg is one connection, and the equality is asserted inside that connection. Exporters from
  // two connections are never compared with each other: each session has its own secret.
  const exporters = {};
  for (const [name, credentials] of [['cert A', certA], ['cert B', certB]]) {
    const node = await exchange(credentials, (port) => connectNode(port, credentials));
    exporters[name] = checkExporters(name, node, 'Node client <-> Node server');

    const nw = await exchange(credentials, (port) => connectNetworkFramework(port, credentials.der));
    checkExporters(name, nw, 'Network.framework client <-> Node server');
  }

  // Control: the verification above is real only if a client that trusts the other certificate
  // refuses this server. Without this, a client that accepted everything would pass the gates.
  const refusal = await serve(certA);
  try {
    let refused = false;
    try {
      await connectNetworkFramework(refusal.port, certB.der);
    } catch {
      refused = true;
    }
    gate('Network.framework client refuses a server whose certificate is not its anchor', refused);
  } finally {
    refusal.server.close();
  }

  gate('two server certificates give different exporters (the exporter is not constant)',
    !exporters['cert A'].equals(exporters['cert B']));

  // --- libsodium: the RFC 9380 comparison ------------------------------------------------------
  //
  // The RFC gives u0, u1 (field elements), Q0, Q1 (the two map images) and P (their sum, cleared
  // by the cofactor) for each vector. Byte reordering and the RFC 8032 point encoding are the only
  // conversions here. Every group operation is libsodium's, through e1-sodium.

  const { vectors } = JSON.parse(readFileSync(join(here, 'rfc9380-j51.json'), 'utf8'));
  const n = vectors.length;
  // Field elements and points are big-endian in the RFC; libsodium reads them little-endian.
  const leHex = (be) => Buffer.from(be, 'hex').reverse().toString('hex');
  // RFC 8032 encoding: y little-endian, with the parity of x in the top bit.
  const encodePoint = ({ x, y }) => {
    const encoded = Buffer.from(y, 'hex').reverse();
    encoded[31] |= (Buffer.from(x, 'hex')[31] & 1) << 7;
    return encoded.toString('hex');
  };
  const withoutSign = (hexValue) => {
    const bytes = Buffer.from(hexValue, 'hex');
    bytes[31] &= 0x7f;
    return bytes.toString('hex');
  };
  // The encoding of the neutral element, the identity for add.
  const IDENTITY = `01${'00'.repeat(31)}`;

  // A refused operation comes back as `error` and is compared like any other value, so a refusal
  // shows up as a mismatch. An `error` fed into a later operation is malformed to e1-sodium and
  // stops the run, which the top-level handler reports as "could not run".
  let version = '';
  const sodium = (ops) => {
    const out = execFileSync(join(bin, 'e1-sodium'), { input: `${ops.join('\n')}\n`, encoding: 'utf8' })
      .trim()
      .split('\n');
    version = out[0].replace('version ', '');
    const results = out.slice(1);
    if (results.length !== ops.length) throw new Error(`e1-sodium returned ${results.length} results for ${ops.length} operations`);
    return results;
  };

  // Round 1, nine operations per vector: the field-element maps, the hash, and the RFC points.
  const STRIDE = 9;
  const pts = vectors.map((v) => ({ q0: encodePoint(v.q0), q1: encodePoint(v.q1), p: encodePoint(v.p) }));
  const r1 = sodium(vectors.flatMap((v, i) => [
    `uniform ${leHex(v.u0)}`,
    `uniform ${leHex(v.u1)}`,
    `hash ${leHex(v.u0)}${leHex(v.u1)}`,
    `valid ${pts[i].p}`,
    `add ${pts[i].p} ${IDENTITY}`,
    `valid ${pts[i].q0}`,
    `add ${pts[i].q0} ${IDENTITY}`,
    `valid ${pts[i].q1}`,
    `add ${pts[i].q1} ${IDENTITY}`,
  ]));
  gate('libsodium is the pinned 1.0.22', version === '1.0.22', version);
  const at = (i, k) => r1[i * STRIDE + k];

  // Controls about the harness, not the answer: the encoding of RFC P must decode as a point in
  // libsodium's prime-order subgroup and round-trip unchanged. If it did not, every comparison
  // below would be measuring the encoder.
  gate('control: RFC P encodings are valid points and round-trip through add(P, identity)',
    vectors.every((_, i) => at(i, 3) === '1' && at(i, 4) === pts[i].p));

  // Round 2: F0 + F1 per vector, and whether libsodium's own map outputs are valid points.
  const r2 = sodium(vectors.flatMap((_, i) => [
    `add ${at(i, 0)} ${at(i, 1)}`,
    `valid ${at(i, 0)}`,
    `valid ${at(i, 1)}`,
    `valid ${at(i, 2)}`,
  ]));
  const sum = vectors.map((_, i) => r2[i * 4]);
  const double = (points) => sodium(points.map((p) => `add ${p} ${p}`));
  const sum2 = double(sum);
  const sum4 = double(sum2);
  const sum8 = double(sum4);

  const count = { u0: 0, u0Y: 0, u1: 0, u1Y: 0, hash: 0, hashY: 0, hashCleared: 0, hashRaw: 0 };
  const validity = { u0: 0, u1: 0, hash: 0, q0Points: 0, q1Points: 0, q0RoundTrip: 0, q1RoundTrip: 0 };
  const control = { u0AsQ1: 0, hashAsQ0: 0 };
  vectors.forEach((_, i) => {
    const f0 = at(i, 0);
    const f1 = at(i, 1);
    const h = at(i, 2);
    if (f0 === pts[i].q0) count.u0++;
    if (withoutSign(f0) === withoutSign(pts[i].q0)) count.u0Y++;
    if (f1 === pts[i].q1) count.u1++;
    if (withoutSign(f1) === withoutSign(pts[i].q1)) count.u1Y++;
    if (h === pts[i].p) count.hash++;
    if (withoutSign(h) === withoutSign(pts[i].p)) count.hashY++;
    if (h === sum8[i]) count.hashCleared++;
    if (h === sum[i]) count.hashRaw++;
    if (r2[i * 4 + 1] === '1') validity.u0++;
    if (r2[i * 4 + 2] === '1') validity.u1++;
    if (r2[i * 4 + 3] === '1') validity.hash++;
    if (at(i, 5) === '1') validity.q0Points++;
    if (at(i, 7) === '1') validity.q1Points++;
    if (at(i, 6) === pts[i].q0) validity.q0RoundTrip++;
    if (at(i, 8) === pts[i].q1) validity.q1RoundTrip++;
    // Negative controls: a comparison that can never fail proves nothing.
    if (f0 === pts[i].q1) control.u0AsQ1++;
    if (h === pts[i].q0) control.hashAsQ0++;
  });

  finding(`from_uniform(u0) equals RFC 9380 Q0 on ${count.u0}/${n}; y-coordinate alone on ${count.u0Y}/${n}`);
  finding(`from_uniform(u1) equals RFC 9380 Q1 on ${count.u1}/${n}; y-coordinate alone on ${count.u1Y}/${n}`);
  finding(`from_hash(u0 || u1) equals RFC 9380 P on ${count.hash}/${n}; y-coordinate alone on ${count.hashY}/${n}`);
  finding(`from_hash equals 8 * (from_uniform(u0) + from_uniform(u1)) on ${count.hashCleared}/${n}; the uncleared sum on ${count.hashRaw}/${n}`);
  finding(`libsodium's own outputs are valid points: from_uniform(u0) ${validity.u0}/${n}, from_uniform(u1) ${validity.u1}/${n}, from_hash ${validity.hash}/${n}`);
  finding(`RFC Q0 and Q1 as libsodium sees them: valid ${validity.q0Points}/${n} and ${validity.q1Points}/${n}; round-trip ${validity.q0RoundTrip}/${n} and ${validity.q1RoundTrip}/${n}`);
  gate('negative controls do not match (the comparison can fail)',
    control.u0AsQ1 === 0 && control.hashAsQ0 === 0,
    `from_uniform(u0) = Q1 on ${control.u0AsQ1}/${n}, from_hash = Q0 on ${control.hashAsQ0}/${n}`);
} catch (error) {
  console.error(`e1: the spike could not run: ${error.message}`);
  exitCode = 2;
} finally {
  rmSync(workdir, { recursive: true, force: true });
}

if (exitCode === 0) {
  const passed = gates.filter(Boolean).length;
  console.log(`E1: ${passed}/${gates.length} gates hold${process.env.E1_MUTANT ? ` (mutant: ${process.env.E1_MUTANT})` : ''}`);
  exitCode = passed === gates.length ? 0 : 1;
}
process.exitCode = exitCode;
