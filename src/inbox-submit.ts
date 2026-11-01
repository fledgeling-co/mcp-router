/*
 * The checks a phone's inbox submit passes (planning/plans/plan-phone-inbox.md §1.2 to §1.3, §7). Pure functions and
 * one small counter, so the listener only sequences them: the signed string, the signature, the item limits and the
 * strikes against a phone whose signature keeps failing.
 */
import { createHash, createPublicKey, createVerify } from 'node:crypto';

export const INBOX_ITEMS_MAX = 50;
export const INBOX_ID_MAX = 200;
export const INBOX_DISPLAY_NAME_MAX = 200;

/** §7. Three bad signatures in a row refuse the phone for this long. */
const STRIKES_MAX = 3;
const LOCKOUT_MS = 10 * 60_000;

const SIGNED_PREFIX = 'mcp-router-inbox-v1';

export interface InboxItem {
  id: string;
  displayName: string;
  queuedAt: string;
}

export type InboxItemsDecode = { items: InboxItem[] } | { refused: 'badRequest' | 'tooManyItems' };

/** The text a phone signs (§1.3): the prefix, the nonce, the phoneId, and the hex SHA-256 of the items' UTF-8 bytes. */
export function inboxSignedString(nonce: string, phoneId: string, items: string): string {
  const digest = createHash('sha256').update(items, 'utf8').digest('hex');
  return [SIGNED_PREFIX, nonce, phoneId, digest].join('\n');
}

/**
 * Whether `sigB64` is an ECDSA P-256 SHA-256 signature, in DER, over `signed`, by the phone's SPKI key. Anything
 * that does not parse as one is false, so a malformed signature is a bad signature and not an internal error.
 */
export function verifyInboxSignature(phoneKey: string, sigB64: string, signed: string): boolean {
  try {
    const key = createPublicKey({ key: Buffer.from(phoneKey, 'base64'), format: 'der', type: 'spki' });
    return createVerify('SHA256').update(signed, 'utf8').verify(key, Buffer.from(sigB64, 'base64'));
  } catch {
    return false;
  }
}

/**
 * The picks in a signed `items` string. Count is checked before the items are read one by one, so a batch over the
 * cap is `tooManyItems` whatever its items hold. An empty batch has nothing to hold, so it is `badRequest`.
 */
export function decodeInboxItems(text: string): InboxItemsDecode {
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    return { refused: 'badRequest' };
  }
  if (!Array.isArray(value) || value.length === 0) return { refused: 'badRequest' };
  if (value.length > INBOX_ITEMS_MAX) return { refused: 'tooManyItems' };
  const items: InboxItem[] = [];
  for (const raw of value) {
    const item = decodeItem(raw);
    if (!item) return { refused: 'badRequest' };
    items.push(item);
  }
  return { items };
}

function decodeItem(raw: unknown): InboxItem | undefined {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) return undefined;
  const { id, displayName, queuedAt } = raw as Record<string, unknown>;
  if (typeof id !== 'string' || id === '' || Array.from(id).length > INBOX_ID_MAX) return undefined;
  if (typeof displayName !== 'string' || Array.from(displayName).length > INBOX_DISPLAY_NAME_MAX) return undefined;
  if (typeof queuedAt !== 'string' || Number.isNaN(Date.parse(queuedAt))) return undefined;
  return { id, displayName, queuedAt };
}

/**
 * Counts a phone's bad signatures. The third in a row locks the phone out for ten minutes, and a valid signature
 * clears the count. Only confirmed phones are counted, so the map is bounded by the phones this router has paired.
 */
export class SignatureStrikes {
  private readonly clock: () => number;
  private readonly strikes = new Map<string, { count: number; lockedUntil: number }>();

  constructor(clock: () => number) {
    this.clock = clock;
  }

  /** Whether the phone is inside its lockout. The lockout ends at exactly ten minutes. */
  locked(phoneId: string): boolean {
    const s = this.strikes.get(phoneId);
    return s !== undefined && this.clock() < s.lockedUntil;
  }

  /** A signature from this phone did not verify. */
  fail(phoneId: string): void {
    const s = this.strikes.get(phoneId) ?? { count: 0, lockedUntil: 0 };
    s.count += 1;
    if (s.count >= STRIKES_MAX) {
      s.lockedUntil = this.clock() + LOCKOUT_MS;
      s.count = 0;
    }
    this.strikes.set(phoneId, s);
  }

  /** A signature from this phone verified, so its run of failures is over. */
  pass(phoneId: string): void {
    this.strikes.delete(phoneId);
  }
}
