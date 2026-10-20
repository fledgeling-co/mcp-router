import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { ed25519 } from '@noble/curves/ed25519.js';
import { sha256 } from '@noble/hashes/sha2.js';
import { utf8ToBytes } from '@noble/hashes/utils.js';
import { confirmation, keySchedule, transcript, typedPairingAad } from '../src/pairing-spake2.js';
import { M_HEX, N_HEX, elementA, elementB, randomScalar, sharedAsA, sharedAsB } from '../src/pairing-spake2-group.js';

/*
 * G2 on Node (planning/plans/plan-pairing-typed-spake2.md §4). The group layer on @noble/curves: the blinding
 * points, both sides' shared point K, the rejections for an element received from the peer, and the generated
 * vectors through the shipping transcript.
 */
interface GroupVector {
  name: string;
  identityA: string;
  identityB: string;
  phoneName: string;
  x: string;
  y: string;
  w: string;
  exporter: string;
  aad: string;
  pA: string;
  pB: string;
  K: string;
  TT: string;
  Ke: string;
  Ka: string;
  KcA: string;
  KcB: string;
  confA: string;
  confB: string;
}

const { vectors } = JSON.parse(
  readFileSync(fileURLToPath(new URL('../../planning/pairing/spake2-edwards25519-vectors.json', import.meta.url)), 'utf8'),
) as { vectors: GroupVector[] };

const Point = ed25519.Point;
const L = Point.Fn.ORDER;
const FIELD_P = (1n << 255n) - 19n;
const fromHex = (hex: string): Uint8Array => Uint8Array.from(Buffer.from(hex, 'hex'));
const toHex = (bytes: Uint8Array): string => Buffer.from(bytes).toString('hex');
const scalarFromHex = (hex: string): bigint => BigInt(`0x${hex}`);

/** Asserts the call throws, and that the error matches `message` when one is given. */
function refuse(call: () => unknown, message?: RegExp): void {
  if (message) assert.throws(call, message);
  else assert.throws(call);
}

/** A 32-byte little-endian encoding of y, with the x sign bit set when `signBit` is 1. */
function encodeY(y: bigint, signBit = 0): Uint8Array {
  const out = new Uint8Array(32);
  let rest = y;
  for (let i = 0; i < 32; i++) {
    out[i] = Number(rest & 0xffn);
    rest >>= 8n;
  }
  out[31] |= signBit << 7;
  return out;
}

/** The first hash output that decodes to a point whose torsion part has order 8. */
function order8Bytes(): Uint8Array {
  for (let i = 0; ; i++) {
    const torsion = torsionOf(sha256(utf8ToBytes(`order-8 search ${i}`)));
    if (torsion && !torsion.multiplyUnsafe(4n).is0()) return torsion.toBytes();
  }
}

/** Q·L, which is zero when Q is already in the prime-order subgroup and otherwise lies in the torsion. */
function torsionOf(bytes: Uint8Array) {
  try {
    const Q = Point.fromBytes(bytes);
    return Q.multiplyUnsafe(L - 1n).add(Q);
  } catch {
    return undefined;
  }
}

/** An encoding of a point that is not on the curve: the first small y with no x. */
function offCurveBytes(): Uint8Array {
  for (let y = 2n; ; y++) {
    const bytes = encodeY(y);
    try {
      Point.fromBytes(bytes);
    } catch {
      return bytes;
    }
  }
}

describe('the blinding points are the RFC 9382 Table 1 edwards25519 constants', () => {
  test('M and N are the plan §2.1 hex, decode to themselves and are in the prime-order subgroup', () => {
    assert.equal(M_HEX, 'd048032c6ea0b6d697ddc2e86bda85a33adac920f1bf18e1b0c6d166a5cecdaf');
    assert.equal(N_HEX, 'd3bfb518f44f3430f29d0c92af503865a1ed3281dc69b35dd868ba85f886c4ab');
    for (const hex of [M_HEX, N_HEX]) {
      const point = Point.fromHex(hex);
      assert.equal(point.toHex(), hex);
      assert.equal(point.isTorsionFree(), true);
    }
  });

  test('M and N are distinct and neither is the identity', () => {
    assert.notEqual(M_HEX, N_HEX);
    assert.equal(Point.fromHex(M_HEX).is0(), false);
    assert.equal(Point.fromHex(N_HEX).is0(), false);
  });
});

describe('the generated vectors through the group layer', () => {
  for (const v of vectors) {
    describe(v.name, () => {
      const x = scalarFromHex(v.x);
      const y = scalarFromHex(v.y);
      const w = scalarFromHex(v.w);

      test('pA = x·P + w·M and pB = y·P + w·N', () => {
        assert.equal(toHex(elementA(x, w)), v.pA);
        assert.equal(toHex(elementB(y, w)), v.pB);
      });

      test('both sides derive the same K, and K is 8·x·y·P', () => {
        const fromA = sharedAsA(x, w, fromHex(v.pB));
        const fromB = sharedAsB(y, w, fromHex(v.pA));
        assert.equal(toHex(fromA), v.K);
        assert.equal(toHex(fromB), v.K);
        assert.equal(toHex(Point.BASE.multiply((8n * x * y) % L).toBytes()), v.K);
      });

      test('the shipping transcript, key schedule and confirmations reproduce the vector', () => {
        const K = fromHex(v.K);
        const TT = transcript({
          identityA: utf8ToBytes(v.identityA),
          identityB: utf8ToBytes(v.identityB),
          pA: fromHex(v.pA),
          pB: fromHex(v.pB),
          K,
          w: fromHex(v.w),
        });
        assert.equal(toHex(TT), v.TT);
        const aad = typedPairingAad(fromHex(v.exporter), v.phoneName);
        assert.equal(toHex(aad), v.aad);
        const keys = keySchedule(TT, aad);
        assert.equal(toHex(keys.Ke), v.Ke);
        assert.equal(toHex(keys.Ka), v.Ka);
        assert.equal(toHex(keys.KcA), v.KcA);
        assert.equal(toHex(keys.KcB), v.KcB);
        assert.equal(toHex(confirmation(keys.KcA, TT)), v.confA);
        assert.equal(toHex(confirmation(keys.KcB, TT)), v.confB);
      });
    });
  }
});

describe('an element received from the peer is refused unless it is a prime-order point', () => {
  const y = scalarFromHex(vectors[0].y);
  const w = scalarFromHex(vectors[0].w);
  // The router decodes pA (sharedAsB). The phone decodes pB (sharedAsA); the same checks apply to both.
  const refusals: Array<[string, Uint8Array, RegExp | undefined]> = [
    ['the identity', encodeY(1n), /element is the identity/],
    ['the identity with the x sign bit set', encodeY(1n, 1), undefined],
    ['a point of order 2', encodeY(FIELD_P - 1n), /element has small order/],
    ['a point of order 4', encodeY(0n), /element has small order/],
    ['a point of order 8', order8Bytes(), /element has small order/],
    [
      'a point with a torsion part and a subgroup part',
      Point.BASE.add(Point.fromBytes(order8Bytes())).toBytes(),
      /outside the prime-order subgroup/,
    ],
    ['a non-canonical y, equal to p', encodeY(FIELD_P), undefined],
    ['a y with no x on the curve', offCurveBytes(), undefined],
    ['31 bytes', new Uint8Array(31), /element must be 32 bytes/],
    ['33 bytes', new Uint8Array(33), /element must be 32 bytes/],
  ];

  for (const [label, bytes, message] of refusals) {
    test(`router refuses pA that is ${label}`, () => {
      refuse(() => sharedAsB(y, w, bytes), message);
    });

    test(`phone refuses pB that is ${label}`, () => {
      refuse(() => sharedAsA(y, w, bytes), message);
    });
  }

  test('a pA equal to w·M is in the subgroup but gives K = identity, which is refused', () => {
    const wM = Point.fromHex(M_HEX).multiply(w).toBytes();
    assert.throws(() => sharedAsB(y, w, wM), /shared element is the identity/);
  });
});

describe('scalars are checked against [1, L)', () => {
  const w = scalarFromHex(vectors[0].w);
  const x = scalarFromHex(vectors[0].x);

  test('x of 0 or of L is refused', () => {
    assert.throws(() => elementA(0n, w), /x must be in \[1, L\)/);
    assert.throws(() => elementA(L, w), /x must be in \[1, L\)/);
  });

  test('w of 0 or of L is refused on both sides', () => {
    assert.throws(() => elementA(x, 0n), /w must be in \[1, L\)/);
    assert.throws(() => elementB(x, L), /w must be in \[1, L\)/);
  });

  test('randomScalar draws in [1, L), and the draws vary', () => {
    const draws = Array.from({ length: 200 }, () => randomScalar());
    for (const draw of draws) {
      assert.ok(draw >= 1n && draw < L);
    }
    assert.ok(new Set(draws.map(String)).size > 1);
  });
});
