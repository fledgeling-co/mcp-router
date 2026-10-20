import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import type { RegistryEntry } from './registry.js';

/*
 * The picks a phone has sent this router, held until a Mac or Windows reviewer decides them
 * (planning/plans/plan-phone-inbox.md §2.1). A row holds registry metadata and the phone's name for
 * itself, never a key, a token or a credential, so a copy of the file submits nothing and accepts nothing.
 */
export const INBOX_FILE = 'inbox.json';

/** D10. At most this many decided rows are kept. A waiting row is never dropped. */
export const INBOX_RETAIN_DECIDED = 200;

export type InboxState = 'waiting' | 'accepted' | 'declined';

export interface InboxRow {
  /** The phone's queued id, which is the registry entry id and the dedup key. */
  id: string;
  phoneId: string;
  deviceName: string;
  queuedAt: string;
  receivedAt: string;
  state: InboxState;
  /** The router's own registry entry for `id`. `null` is a Partial row: the lookup failed. */
  resolved: RegistryEntry | null;
  reviewDigest: string;
}

/** A row as GET /inbox names it. The phone id stays on the router. */
export type InboxView = Omit<InboxRow, 'phoneId' | 'receivedAt'>;

export type NewInboxRow = Omit<InboxRow, 'state' | 'reviewDigest'>;

/**
 * The digest the reviewer's accept must echo (D11). It is over the canonical JSON of the resolved entry,
 * or over nothing for a Partial row, so a row replaced between view and accept has a different digest.
 */
export function reviewDigestOf(resolved: RegistryEntry | null): string {
  const text = resolved === null ? '' : JSON.stringify(canonical(resolved));
  return createHash('sha256').update(text).digest('hex');
}

/** Key order in JSON carries no meaning, so sort it before the digest is taken. */
function canonical(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const k of Object.keys(value as Record<string, unknown>).sort()) {
      out[k] = canonical((value as Record<string, unknown>)[k]);
    }
    return out;
  }
  return value;
}

export class InboxStore {
  readonly path: string;

  constructor(path: string) {
    this.path = path;
  }

  /** Every row, in the order it was received. A store with no file yet holds none. */
  rows(): InboxRow[] {
    if (!existsSync(this.path)) return [];
    return (JSON.parse(readFileSync(this.path, 'utf8')) as { rows: InboxRow[] }).rows;
  }

  view(): InboxView[] {
    return this.rows().map(({ phoneId: _phoneId, receivedAt: _receivedAt, ...rest }) => rest);
  }

  /**
   * Hold one pick, and answer the state the phone is told. A pick whose id is already held changes
   * nothing, so the first snapshot is the one the reviewer reads (D11). The receipt is only sent after this
   * returns, so a receipt means the row is on disk.
   */
  add(input: NewInboxRow): 'waiting' | 'duplicate' {
    const rows = this.rows();
    if (rows.some((r) => r.id === input.id)) return 'duplicate';
    rows.push({ ...input, state: 'waiting', reviewDigest: reviewDigestOf(input.resolved) });
    this.write(retain(rows));
    return 'waiting';
  }

  /** Rewrite the file 0600, through a temporary file, so a failed write leaves the previous file whole. */
  private write(rows: InboxRow[]): void {
    mkdirSync(dirname(this.path), { recursive: true, mode: 0o700 });
    const tmp = `${this.path}.tmp-${process.pid}`;
    writeFileSync(tmp, JSON.stringify({ rows }, null, 2) + '\n', { mode: 0o600 });
    renameSync(tmp, this.path);
  }
}

/** D10. Drop the oldest decided rows, which come first in receipt order, until at most the limit remain. */
function retain(rows: InboxRow[]): InboxRow[] {
  let excess = rows.filter((r) => r.state !== 'waiting').length - INBOX_RETAIN_DECIDED;
  return rows.filter((r) => {
    if (excess > 0 && r.state !== 'waiting') {
      excess--;
      return false;
    }
    return true;
  });
}
