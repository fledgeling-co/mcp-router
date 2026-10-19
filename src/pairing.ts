import { randomInt } from 'node:crypto';

/*
 * The Mac's half of the phone pairing handshake: issue a code, and decide what a submitted code is
 * worth. A TypeScript port of `MacPairing.decide` (app/Sources/MCPRouterKit/Pairing/MacPairing.swift),
 * plus the attempt limit the Swift side does not enforce.
 *
 * The router is the authority for this state because it is the one process that runs headless
 * (planning/plans/plan-pairing-handshake.md §1). Nothing here is persisted: a code lives for five
 * minutes, and a restart that drops the live code drops nothing a phone could still use.
 */

/** Crockford's alphabet, the same string as `PairingCode.alphabet`. I, L, O and U are not in it. */
export const PAIRING_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
export const PAIRING_CODE_LENGTH = 8;

/** Five minutes, the same as `MacPairing.lifetime`. */
export const PAIRING_LIFETIME_MS = 300_000;

/** A code is burned by its third wrong guess, so eight characters cannot be walked by brute force. */
export const PAIRING_MAX_WRONG_ATTEMPTS = 3;

/** The payload versions a phone can read. Mirrors `PairingPayload.supportedVersions`. */
const SUPPORTED_VERSIONS = new Set([1]);

/** The version this router emits. Mirrors `MacPairing.wireVersion`. */
export const PAIRING_WIRE_VERSION = 1;

export interface IssuedCode {
  code: string;
  issuedAt: Date;
  expiresAt: Date;
}

/**
 * A phone whose request was accepted and whose `pair.ok` is on the wire, held until its `pair.ack`.
 * Held only while its connection is open: a phone that drops before the ack is released, and nothing
 * is recorded for it (planning/plans/plan-pairing-handshake.md §2.2).
 */
export interface AwaitingAck {
  phoneId: string;
  phoneName: string;
  requestedAt: Date;
}

/**
 * Why the router refused a submitted code. The `declined` case of `PairingRefusal` is not here: a
 * human at the Mac dismissing a request is a decision the Mac takes, never the router.
 */
export type PairingRefusal =
  | { kind: 'notRecognised' }
  | { kind: 'expired' }
  | { kind: 'alreadyUsed' }
  | { kind: 'unsupportedVersion'; found: number };

export interface DecideInput {
  submitted: string;
  version: number;
  live: IssuedCode | undefined;
  spent: ReadonlySet<string>;
  now: Date;
}

/**
 * What the router does with a submitted code. Returns `undefined` when the code is accepted.
 *
 * The order is load-bearing and matches the Swift: a version is checked first, a spent code is
 * checked before liveness so a re-submitted code says "already used" once the next code has replaced
 * it, and expiry uses `<=`, so a code is dead at the instant of its expiry.
 */
export function decide({ submitted, version, live, spent, now }: DecideInput): PairingRefusal | undefined {
  if (!SUPPORTED_VERSIONS.has(version)) return { kind: 'unsupportedVersion', found: version };
  if (spent.has(submitted)) return { kind: 'alreadyUsed' };
  if (!live || live.code !== submitted) return { kind: 'notRecognised' };
  if (live.expiresAt.getTime() <= now.getTime()) return { kind: 'expired' };
  return undefined;
}

/**
 * The wire form of an instant: whole seconds, `Z`, no fraction. Matches the Swift `ISO8601Instant`
 * writer, so both ends read one expiry rather than two that differ in the milliseconds.
 */
export function wireInstant(date: Date): string {
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function randomCode(): string {
  let code = '';
  for (let i = 0; i < PAIRING_CODE_LENGTH; i++) {
    code += PAIRING_ALPHABET[randomInt(PAIRING_ALPHABET.length)];
  }
  return code;
}

/**
 * The code state for one router process. Holds the one live code, its wrong-guess count, and the
 * set of codes already paired. The clock is injected so expiry is testable without a wall clock.
 */
export class Pairing {
  private live: IssuedCode | undefined;
  private wrongAttempts = 0;
  private readonly spent = new Set<string>();
  private readonly awaiting = new Map<string, AwaitingAck>();

  constructor(private readonly clock: () => Date = () => new Date()) {}

  /** Mint a code, replacing whatever was live. The expiry is truncated to whole seconds. */
  issue(): IssuedCode {
    const issuedAt = this.clock();
    const expiresAt = new Date(Math.floor((issuedAt.getTime() + PAIRING_LIFETIME_MS) / 1000) * 1000);
    this.live = { code: randomCode(), issuedAt, expiresAt };
    this.wrongAttempts = 0;
    return this.live;
  }

  /** Drop the live code. Returns false when there was nothing to drop. A spent code stays spent. */
  revoke(): boolean {
    const had = this.live !== undefined;
    this.live = undefined;
    this.wrongAttempts = 0;
    return had;
  }

  /**
   * The code a phone could still pair with, or null. An expired code is not pending, so it is not
   * named here, even though it stays on record long enough for `submit` to say it expired.
   */
  current(): IssuedCode | null {
    if (!this.live || this.live.expiresAt.getTime() <= this.clock().getTime()) return null;
    return this.live;
  }

  /**
   * Decide a submitted code and keep the record that decision implies. A paired code is remembered
   * and stops being live. A wrong guess at the live code counts toward its burn, and the third one
   * burns it. Returns the refusal, or `undefined` when the code is accepted.
   */
  submit(code: string, version: number): PairingRefusal | undefined {
    const refusal = decide({ submitted: code, version, live: this.live, spent: this.spent, now: this.clock() });
    if (refusal === undefined) {
      this.spent.add(code);
      this.live = undefined;
      this.wrongAttempts = 0;
      return undefined;
    }
    if (refusal.kind === 'notRecognised' && this.live) {
      this.wrongAttempts += 1;
      if (this.wrongAttempts >= PAIRING_MAX_WRONG_ATTEMPTS) {
        this.live = undefined;
        this.wrongAttempts = 0;
      }
    }
    return refusal;
  }

  /** A phone's request was accepted and its `pair.ok` sent. Held until `release`. */
  hold(phoneId: string, phoneName: string): void {
    this.awaiting.set(phoneId, { phoneId, phoneName, requestedAt: this.clock() });
  }

  /** Drop a held request, on its ack or on its connection closing. Nothing is recorded here. */
  release(phoneId: string): void {
    this.awaiting.delete(phoneId);
  }

  /** The requests whose phones have not yet acked, oldest first. */
  awaitingAck(): AwaitingAck[] {
    return [...this.awaiting.values()];
  }
}
