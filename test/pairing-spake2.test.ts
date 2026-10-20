import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { utf8ToBytes } from '@noble/hashes/utils.js';
import { confirmation, keySchedule, transcript, typedPairingAad } from '../src/pairing-spake2.js';

/*
 * G1 on Node. The four RFC 9382 Appendix B vectors (P-256) go through the shipping transcript and
 * key schedule as byte inputs. The P-256 points are never computed here: the vectors supply them.
 */
interface RfcVector {
  name: string;
  identityA: string;
  identityB: string;
  w: string;
  pA: string;
  pB: string;
  K: string;
  TT: string;
  hashTT: string;
  Ke: string;
  Ka: string;
  KcA: string;
  KcB: string;
  confA: string;
  confB: string;
}

const { vectors } = JSON.parse(
  readFileSync(fileURLToPath(new URL('../../planning/pairing/spake2-rfc9382-vectors.json', import.meta.url)), 'utf8'),
) as { vectors: RfcVector[] };

const fromHex = (hex: string): Uint8Array => Uint8Array.from(Buffer.from(hex, 'hex'));
const toHex = (bytes: Uint8Array): string => Buffer.from(bytes).toString('hex');
const NIL_AAD = new Uint8Array(0);

function transcriptOf(v: RfcVector): Uint8Array {
  return transcript({
    identityA: utf8ToBytes(v.identityA),
    identityB: utf8ToBytes(v.identityB),
    pA: fromHex(v.pA),
    pB: fromHex(v.pB),
    K: fromHex(v.K),
    w: fromHex(v.w),
  });
}

describe('transcript and key schedule against RFC 9382 Appendix B (P256-SHA256-HKDF-HMAC)', () => {
  for (const v of vectors) {
    describe(v.name, () => {
      test('transcript TT is byte-identical to the RFC', () => {
        assert.equal(toHex(transcriptOf(v)), v.TT);
      });

      test('Ke and Ka split Hash(TT), and KcA and KcB derive from Ka', () => {
        const keys = keySchedule(fromHex(v.TT), NIL_AAD);
        assert.equal(toHex(keys.Ke), v.Ke);
        assert.equal(toHex(keys.Ka), v.Ka);
        assert.equal(toHex(keys.KcA), v.KcA);
        assert.equal(toHex(keys.KcB), v.KcB);
      });

      test('the confirmations are HMAC-SHA256(KcA, TT) and HMAC-SHA256(KcB, TT)', () => {
        const TT = transcriptOf(v);
        const keys = keySchedule(TT, NIL_AAD);
        assert.equal(toHex(confirmation(keys.KcA, TT)), v.confA);
        assert.equal(toHex(confirmation(keys.KcB, TT)), v.confB);
      });
    });
  }
});

describe('transcript changes with every field', () => {
  const v = vectors[0];

  test('a different identity A changes TT, so a substituted phone key breaks confirmation', () => {
    const honest = transcriptOf(v);
    const substituted = transcript({
      identityA: utf8ToBytes('mallory'),
      identityB: utf8ToBytes(v.identityB),
      pA: fromHex(v.pA),
      pB: fromHex(v.pB),
      K: fromHex(v.K),
      w: fromHex(v.w),
    });
    assert.notEqual(toHex(substituted), toHex(honest));
    const keys = keySchedule(honest, NIL_AAD);
    assert.notEqual(toHex(confirmation(keys.KcA, substituted)), v.confA);
  });

  test('a w that is not 32 bytes is refused', () => {
    assert.throws(
      () =>
        transcript({
          identityA: utf8ToBytes(v.identityA),
          identityB: utf8ToBytes(v.identityB),
          pA: fromHex(v.pA),
          pB: fromHex(v.pB),
          K: fromHex(v.K),
          w: new Uint8Array(31),
        }),
      /w must be 32 bytes/,
    );
  });
});

describe('key schedule binds the AAD into the confirmation keys', () => {
  const TT = transcriptOf(vectors[0]);
  const exporterA = new Uint8Array(32).fill(0x11);
  const exporterB = new Uint8Array(32).fill(0x22);

  test('a different TLS exporter changes KcA and KcB, so a relayed leg cannot confirm', () => {
    const legA = keySchedule(TT, typedPairingAad(exporterA, 'Luke iPhone'));
    const legB = keySchedule(TT, typedPairingAad(exporterB, 'Luke iPhone'));
    assert.equal(toHex(legA.Ka), toHex(legB.Ka));
    assert.notEqual(toHex(legA.KcA), toHex(legB.KcA));
    assert.notEqual(toHex(legA.KcB), toHex(legB.KcB));
  });

  test('the nil-AAD keys differ from the AAD keys', () => {
    const nil = keySchedule(TT, NIL_AAD);
    const bound = keySchedule(TT, typedPairingAad(exporterA, 'Luke iPhone'));
    assert.notEqual(toHex(nil.KcA), toHex(bound.KcA));
  });
});

describe('typedPairingAad', () => {
  test('is the label, then the 32-byte exporter, then the UTF-8 phone name', () => {
    const exporter = new Uint8Array(32).fill(0xab);
    const expected = new Uint8Array([
      ...utf8ToBytes('pair.typed.v1'),
      ...exporter,
      ...utf8ToBytes('Luke iPhone'),
    ]);
    assert.equal(toHex(typedPairingAad(exporter, 'Luke iPhone')), toHex(expected));
  });

  test('refuses an exporter that is not 32 bytes', () => {
    assert.throws(() => typedPairingAad(new Uint8Array(31), 'Luke iPhone'), /exporter must be 32 bytes/);
  });
});
