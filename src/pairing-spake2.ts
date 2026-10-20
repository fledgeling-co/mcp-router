import { hkdf } from '@noble/hashes/hkdf.js';
import { hmac } from '@noble/hashes/hmac.js';
import { sha256 } from '@noble/hashes/sha2.js';
import { concatBytes, utf8ToBytes } from '@noble/hashes/utils.js';

/*
 * The SPAKE2 transcript and key schedule for typed-code pairing (planning/plans/plan-pairing-typed-spake2.md
 * §2.1 to §2.3; RFC 9382 §3.3 and §4). This module takes the group elements as bytes. The group operations
 * live in the group layer, so nothing here does curve arithmetic. The hashes and the KDF and MAC come from
 * @noble/hashes, the library the plan chose for them.
 */

const W_LENGTH = 32;
const EXPORTER_LENGTH = 32;
const AAD_LABEL = 'pair.typed.v1';
const CONFIRMATION_LABEL = 'ConfirmationKeys';

export interface TranscriptInputs {
  identityA: Uint8Array;
  identityB: Uint8Array;
  pA: Uint8Array;
  pB: Uint8Array;
  K: Uint8Array;
  /** Big-endian and already padded to 32 bytes (RFC 9382 §3.3). */
  w: Uint8Array;
}

export interface KeySchedule {
  /** Not used in v1. Carried so the RFC vectors can check it. */
  Ke: Uint8Array;
  Ka: Uint8Array;
  KcA: Uint8Array;
  KcB: Uint8Array;
}

/** A field in TT, preceded by its length as an 8-byte little-endian integer. */
function prefixed(field: Uint8Array): Uint8Array {
  const length = new Uint8Array(8);
  new DataView(length.buffer).setBigUint64(0, BigInt(field.length), true);
  return concatBytes(length, field);
}

/** TT = len(A) || A || len(B) || B || len(pA) || pA || len(pB) || pB || len(K) || K || len(w) || w. */
export function transcript(inputs: TranscriptInputs): Uint8Array {
  if (inputs.w.length !== W_LENGTH) throw new Error(`w must be ${W_LENGTH} bytes`);
  return concatBytes(
    prefixed(inputs.identityA),
    prefixed(inputs.identityB),
    prefixed(inputs.pA),
    prefixed(inputs.pB),
    prefixed(inputs.K),
    prefixed(inputs.w),
  );
}

/**
 * Ke || Ka = Hash(TT), and KcA || KcB = KDF(Ka, nil, "ConfirmationKeys" || AAD, L), where L is the full hash
 * output so each confirmation key is half of it. `aad` is empty for the RFC vectors, which use nil AAD.
 */
export function keySchedule(TT: Uint8Array, aad: Uint8Array): KeySchedule {
  const hashed = sha256(TT);
  const half = hashed.length / 2;
  const kc = hkdf(sha256, hashed.slice(half), undefined, concatBytes(utf8ToBytes(CONFIRMATION_LABEL), aad), hashed.length);
  return {
    Ke: hashed.slice(0, half),
    Ka: hashed.slice(half),
    KcA: kc.slice(0, half),
    KcB: kc.slice(half),
  };
}

/** c = HMAC-SHA256(Kc, TT). The caller compares it in constant time. */
export function confirmation(Kc: Uint8Array, TT: Uint8Array): Uint8Array {
  return hmac(sha256, Kc, TT);
}

/**
 * AAD = "pair.typed.v1" || E || phoneName, where E is this leg's TLS 1.3 exporter (plan §2.1 and §2.2).
 * E is fixed-length, so the concatenation needs no separators.
 */
export function typedPairingAad(exporter: Uint8Array, phoneName: string): Uint8Array {
  if (exporter.length !== EXPORTER_LENGTH) throw new Error(`exporter must be ${EXPORTER_LENGTH} bytes`);
  return concatBytes(utf8ToBytes(AAD_LABEL), exporter, utf8ToBytes(phoneName));
}
