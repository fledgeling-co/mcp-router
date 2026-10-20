import { ed25519 } from '@noble/curves/ed25519.js';
import { randomBytes } from 'node:crypto';

/*
 * The edwards25519 group layer for typed-code pairing (planning/plans/plan-pairing-typed-spake2.md §2.1 and
 * §2.4; RFC 9382 §3.2 and §6). The point arithmetic is @noble/curves, the library the plan chose for it, so
 * nothing here implements curve arithmetic. This module adds what the protocol does with the group: the
 * blinding points M and N, the two blinded elements, the shared point K, and the checks on an element
 * received from the peer. The transcript and key schedule take K as bytes, in src/pairing-spake2.ts.
 */

const Point = ed25519.Point;
const ORDER = Point.Fn.ORDER;
const COFACTOR = 8n;
const ELEMENT_LENGTH = 32;

// RFC 9382 Table 1, the edwards25519 row. The per-user variant in RFC 9382 §5 is not used (plan §2.1).
export const M_HEX = 'd048032c6ea0b6d697ddc2e86bda85a33adac920f1bf18e1b0c6d166a5cecdaf';
export const N_HEX = 'd3bfb518f44f3430f29d0c92af503865a1ed3281dc69b35dd868ba85f886c4ab';
const M = Point.fromHex(M_HEX);
const N = Point.fromHex(N_HEX);

function checkScalar(name: string, scalar: bigint): void {
  if (scalar < 1n || scalar >= ORDER) throw new Error(`${name} must be in [1, L)`);
}

/**
 * A decoded element from the peer. The strict RFC 8032 decode refuses a non-canonical y and an x of 0 with the
 * sign bit set. The order checks then refuse the identity, the small-order points and the points outside the
 * prime-order subgroup (plan §2.4).
 */
function decodeElement(bytes: Uint8Array) {
  if (bytes.length !== ELEMENT_LENGTH) throw new Error(`element must be ${ELEMENT_LENGTH} bytes`);
  const point = Point.fromBytes(bytes);
  if (point.is0()) throw new Error('element is the identity');
  if (point.isSmallOrder()) throw new Error('element has small order');
  if (!point.isTorsionFree()) throw new Error('element is outside the prime-order subgroup');
  return point;
}

/** A scalar uniform in [1, L): 253 random bits, rejected when at or above L or equal to 0 (plan §6 item 6). */
export function randomScalar(): bigint {
  for (;;) {
    const bytes = randomBytes(ELEMENT_LENGTH);
    bytes[ELEMENT_LENGTH - 1] &= 0x1f;
    const candidate = BigInt(`0x${Buffer.from(bytes).reverse().toString('hex')}`);
    if (candidate >= 1n && candidate < ORDER) return candidate;
  }
}

/** pA = x·P + w·M, sent by A (the phone). x is fresh for each exchange. */
export function elementA(x: bigint, w: bigint): Uint8Array {
  checkScalar('x', x);
  checkScalar('w', w);
  return Point.BASE.multiply(x).add(M.multiply(w)).toBytes();
}

/** pB = y·P + w·N, sent by B (the router). y is fresh for each exchange. */
export function elementB(y: bigint, w: bigint): Uint8Array {
  checkScalar('y', y);
  checkScalar('w', w);
  return Point.BASE.multiply(y).add(N.multiply(w)).toBytes();
}

/**
 * K as B computes it from the pA it received: K = h·y·(pA − w·M). The router runs this on pA before it spends
 * the attempt (plan §2.4 step 2).
 */
export function sharedAsB(y: bigint, w: bigint, pA: Uint8Array): Uint8Array {
  checkScalar('y', y);
  checkScalar('w', w);
  return sharedPoint(decodeElement(pA).subtract(M.multiply(w)), y);
}

/**
 * K as A computes it from the pB it received: K = h·x·(pB − w·N). The phone runs this before it checks cB
 * (plan §2.4 step 3).
 */
export function sharedAsA(x: bigint, w: bigint, pB: Uint8Array): Uint8Array {
  checkScalar('x', x);
  checkScalar('w', w);
  return sharedPoint(decodeElement(pB).subtract(N.multiply(w)), x);
}

/**
 * The scalars are secret, so this uses multiply rather than multiplyUnsafe. noble documents that its field
 * operations are not constant-time, and plan §6 item 7 asks the reviewer to weigh that.
 */
function sharedPoint(unblinded: ReturnType<typeof decodeElement>, secret: bigint): Uint8Array {
  const K = unblinded.multiply(secret).multiply(COFACTOR);
  if (K.is0()) throw new Error('shared element is the identity');
  return K.toBytes();
}
