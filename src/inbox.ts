import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import type { RawServer } from './config.js';
import type { RegistryEntry } from './registry.js';
import { withExclusiveLock, lockTimeoutMs, DAEMON_TIMEOUT_MS } from './lock.js';

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
    return withExclusiveLock(this.path, lockTimeoutMs(DAEMON_TIMEOUT_MS), () => {
      const rows = this.rows();
      if (rows.some((r) => r.id === input.id)) return 'duplicate';
      rows.push({ ...input, state: 'waiting', reviewDigest: reviewDigestOf(input.resolved) });
      this.write(retain(rows));
      return 'waiting';
    });
  }

  /** The row for one id, or undefined when the inbox holds none. */
  find(id: string): InboxRow | undefined {
    return this.rows().find((r) => r.id === id);
  }

  /**
   * Move one row to a decided state, or back to waiting. Returns false when no row has the id, and writes
   * nothing. The row just decided is never the one retention drops, so a decision cannot make its own row vanish.
   */
  setState(id: string, state: InboxState): boolean {
    return withExclusiveLock(this.path, lockTimeoutMs(DAEMON_TIMEOUT_MS), () => {
      const rows = this.rows();
      const row = rows.find((r) => r.id === id);
      if (!row) return false;
      row.state = state;
      this.write(retain(rows, id));
      return true;
    });
  }

  /** Rewrite the file 0600, through a temporary file, so a failed write leaves the previous file whole. */
  private write(rows: InboxRow[]): void {
    mkdirSync(dirname(this.path), { recursive: true, mode: 0o700 });
    const tmp = `${this.path}.tmp-${process.pid}`;
    writeFileSync(tmp, JSON.stringify({ rows }, null, 2) + '\n', { mode: 0o600 });
    renameSync(tmp, this.path);
  }
}

/**
 * D10. Drop the oldest decided rows, which come first in receipt order, until at most the limit remain. `keep` is the
 * row a decision just changed, which is never the one dropped.
 */
function retain(rows: InboxRow[], keep?: string): InboxRow[] {
  let excess = rows.filter((r) => r.state !== 'waiting').length - INBOX_RETAIN_DECIDED;
  return rows.filter((r) => {
    if (excess > 0 && r.state !== 'waiting' && r.id !== keep) {
      excess--;
      return false;
    }
    return true;
  });
}

/** Why an accept cannot declare a row. `reason` is the word the route answers with. */
export interface DeclarationRefusal {
  reason: 'needsCredentials' | 'notInstallable';
  error: string;
}

/**
 * The server an accept declares, built from the entry's install block (plan §2.4, D7, D8). The router builds it so
 * the Mac and Windows boards share one mapping. An entry that names any value the phone must supply is refused,
 * whether or not the value is secret: a declaration without that value is a server that does not work, and D8 keeps
 * secrets out of the request body that accepts it.
 */
export function declarationFor(entry: RegistryEntry): { name: string; server: RawServer } | DeclarationRefusal {
  const install = entry.install;
  if (!install) return { reason: 'notInstallable', error: `${entry.id} says nothing about how to run it` };
  if (install.requires?.length) {
    return {
      reason: 'needsCredentials',
      error: `${entry.id} needs ${install.requires.length} value(s) that cannot be supplied from the phone in v1`,
    };
  }
  // The review surfaces remove these invisible controls. Refuse a command the reviewer cannot see verbatim.
  const hidden = /[\u0000-\u001f\u007f-\u009f\u061c\u200b-\u200f\u2028-\u202e\u2066-\u206f]/;
  const operands = install.type === 'stdio' ? [install.command ?? '', ...(install.args ?? [])] : [install.url ?? ''];
  if (operands.some((value) => hidden.test(value))) {
    return { reason: 'notInstallable', error: `${entry.id} contains invisible controls in its install details` };
  }
  const server: RawServer =
    install.type === 'stdio'
      ? { command: install.command, args: install.args }
      : { type: install.type, url: install.url };
  // Registry ids are commonly namespaced with slashes and dots; local tool namespaces are not.
  const name = entry.name.replace(/[^A-Za-z0-9_-]/g, '-').replace(/_{2,}/g, '_');
  if (!name) return { reason: 'notInstallable', error: `${entry.id} has no valid local server name` };
  return { name, server };
}
