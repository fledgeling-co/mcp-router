import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

/*
 * The phones this router has confirmed. A phone is listed only after its `pair.ack`, so a request that
 * dropped before the ack never appears here (planning/plans/plan-pairing-handshake.md §2.2). The file
 * holds public keys only, so a copy of it pairs nothing (§4).
 */
export const PAIRED_PHONES_FILE = 'paired-phones.json';

export interface PairedPhone {
  phoneId: string;
  phoneName: string;
  /** The phone's P-256 public key, base64 of its SPKI DER, exactly as the phone sent it. */
  phoneKey: string;
  /** Whole seconds, `Z`, as the wire writes every instant. */
  pairedAt: string;
}

export function readPairedPhones(dir: string): PairedPhone[] {
  const path = join(dir, PAIRED_PHONES_FILE);
  if (!existsSync(path)) return [];
  return (JSON.parse(readFileSync(path, 'utf8')) as { phones: PairedPhone[] }).phones;
}

/** Rewrite the file 0600, through a temporary file so a crash leaves the old one whole. */
function writePairedPhones(dir: string, phones: PairedPhone[]): void {
  const path = join(dir, PAIRED_PHONES_FILE);
  const tmp = `${path}.tmp-${process.pid}`;
  writeFileSync(tmp, JSON.stringify({ phones }, null, 2) + '\n', { mode: 0o600 });
  renameSync(tmp, path);
}

/** Append one confirmed phone and rewrite the file 0600, through a temporary file so a crash leaves the old one whole. */
export function appendPairedPhone(dir: string, phone: PairedPhone): void {
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  writePairedPhones(dir, [...readPairedPhones(dir), phone]);
}

/**
 * Remove one confirmed phone, and with it the public key the file holds for it. Returns the removed record, or
 * undefined when no such phone is confirmed, in which case the file is not written at all.
 */
export function removePairedPhone(dir: string, phoneId: string): PairedPhone | undefined {
  const phones = readPairedPhones(dir);
  const removed = phones.find((p) => p.phoneId === phoneId);
  if (!removed) return undefined;
  writePairedPhones(dir, phones.filter((p) => p !== removed));
  return removed;
}
