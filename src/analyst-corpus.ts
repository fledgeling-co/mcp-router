/**
 * The session corpus the analyst reads, ported from SessionCorpus.swift.
 *
 * Every store the router knows about appears in the report, read or not. A store omitted because it was absent,
 * unreadable or of a format this reader does not handle is indistinguishable on the wire from one that held nothing,
 * and the difference decides whether `linesRead` is a coverage figure or a fraction of one nobody can see the
 * denominator of.
 *
 * The reader is read-only. It opens files under the home directory and never writes to them.
 */
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import type { MCPClient } from './harness.js';

/** The most recent lines taken from each store. A history file is unbounded, and a prompt is not summarised
 * by its oldest line. */
export const CORPUS_LINE_CAP = 4000;

/** One line of one harness's session log, reduced to the text the analyst reads. */
export interface SessionEntry {
  harness: MCPClient;
  text: string;
}

/** What one store gave up, including the ones that gave up nothing. */
export interface SessionStoreReport {
  harness: MCPClient;
  path: string;
  read: boolean;
  /** Lines the reader parsed, not lines it opened. */
  lines: number;
  /** Lines opened and not used, by any cause: blank, unparsable, or carrying no prompt member. */
  discarded: number;
  /** Why this store contributed nothing, or null when it was read. */
  reason: string | null;
}

export interface SessionCorpus {
  entries: SessionEntry[];
  reports: SessionStoreReport[];
}

type SessionStore =
  | { harness: MCPClient; path: string; shape: 'file' | 'directory' }
  | { harness: MCPClient; path: string; shape: 'unsupported'; reason: string };

/**
 * Where each harness keeps its sessions, from PRD.md §6.2.
 *
 * Cursor is in the table and is not read. Its store is SQLite where every other one is JSON Lines, so it is a second
 * reader with a second failure surface. It stays here so the wire reports it unread with its reason.
 */
export function sessionStores(home: string): SessionStore[] {
  return [
    { harness: 'claudeCode', path: join(home, '.claude', 'history.jsonl'), shape: 'file' },
    { harness: 'codexCLI', path: join(home, '.codex', 'history.jsonl'), shape: 'file' },
    { harness: 'grokCLI', path: join(home, '.grok', 'sessions'), shape: 'directory' },
    { harness: 'geminiCLI', path: join(home, '.gemini', 'history'), shape: 'directory' },
    {
      harness: 'cursor',
      path: join(home, '.cursor', 'chats'),
      shape: 'unsupported',
      reason: 'this store is SQLite; the analyst reads JSON Lines only',
    },
  ];
}

/** Read every store under `home`. Never throws: a store that cannot be read is reported with its reason. */
export function readSessionCorpus(home: string): SessionCorpus {
  const entries: SessionEntry[] = [];
  const reports: SessionStoreReport[] = [];
  for (const store of sessionStores(home)) {
    const outcome = readStore(store);
    entries.push(...outcome.entries);
    reports.push(outcome.report);
  }
  return { entries, reports };
}

function readStore(store: SessionStore): { entries: SessionEntry[]; report: SessionStoreReport } {
  if (store.shape === 'unsupported') return { entries: [], report: unread(store, store.reason) };
  if (store.shape === 'file') {
    if (!existsSync(store.path)) return { entries: [], report: unread(store, 'no file at this path') };
    return harvest(store, [store.path]);
  }
  let names: string[];
  try {
    names = readdirSync(store.path);
  } catch {
    return { entries: [], report: unread(store, 'this directory could not be listed') };
  }
  const files = names
    .filter((name) => name.endsWith('.jsonl'))
    .sort()
    .map((name) => join(store.path, name));
  if (files.length === 0) return { entries: [], report: unread(store, 'no .jsonl file in this directory') };
  return harvest(store, files);
}

function unread(store: SessionStore, reason: string): SessionStoreReport {
  return { harness: store.harness, path: store.path, read: false, lines: 0, discarded: 0, reason };
}

const UTF8 = new TextDecoder('utf-8', { fatal: true });

function harvest(
  store: Extract<SessionStore, { shape: 'file' | 'directory' }>,
  files: string[],
): { entries: SessionEntry[]; report: SessionStoreReport } {
  const entries: SessionEntry[] = [];
  let discarded = 0;
  let opened = 0;
  for (const file of files) {
    let text: string;
    try {
      text = UTF8.decode(readFileSync(file));
    } catch {
      discarded += 1;
      continue;
    }
    const recent = text.split('\n').slice(-CORPUS_LINE_CAP);
    opened += recent.length;
    for (const line of recent) {
      const harvested = harvestLine(line);
      if (harvested === undefined) discarded += 1;
      else entries.push({ harness: store.harness, text: harvested });
    }
  }
  // A store the reader reached and could use nothing from is reported read, with a reason. Saying it was unread would
  // blame the machine for a format this reader could not use.
  const reason = entries.length === 0 && opened > 0 ? 'every line in this store was discarded' : null;
  return {
    entries,
    report: { harness: store.harness, path: store.path, read: true, lines: entries.length, discarded, reason },
  };
}

/**
 * The members a session line may carry its text in. The five harnesses spell it differently and none documents it, so
 * The members a session line may carry its text in. The five harnesses spell it differently and none documents
 * it, so the reader tries the known spellings in order. A line it cannot name a member in is discarded rather
 * than stringified, because a stringified line puts JSON punctuation into the command histogram.
 */
const LINE_MEMBERS = ['display', 'prompt', 'text', 'content', 'command', 'message'] as const;

export function harvestLine(line: string): string | undefined {
  const trimmed = line.trim();
  if (trimmed === '') return undefined;
  let parsed: unknown;
  try {
    parsed = JSON.parse(trimmed);
  } catch {
    return undefined;
  }
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) return undefined;
  const record = parsed as Record<string, unknown>;
  for (const name of LINE_MEMBERS) {
    const value = record[name];
    if (typeof value === 'string' && value.length > 0) return value;
  }
  return undefined;
}
