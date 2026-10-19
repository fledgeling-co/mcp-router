/**
 * Counting what recurs, before any model is asked anything. Ported from SessionPatterns.swift.
 *
 * The model never sees the corpus. What crosses into the judge is a list of counted signals with three examples each.
 */
import { MCP_CLIENTS, type MCPClient } from './harness.js';
import type { SessionEntry } from './analyst-corpus.js';

/** How many times a signal must recur before it reaches the judge. Two is a coincidence often enough that the
 * floor would do nothing. */
export const PATTERN_FLOOR = 3;
export const PATTERN_EXAMPLES = 3;
/** How many patterns reach the judge, so a machine with a thousand distinct commands does not produce a
 * thousand-line prompt. */
export const PATTERN_LIMIT = 12;

export interface SessionPattern {
  /**
   * `command` is a command line reduced to its head and first bare subcommand. `missingTool` is the shell
   * reporting a binary it could not find.
   */
  kind: 'command' | 'missingTool';
  signal: string;
  occurrences: number;
  /** Every harness the signal was seen in, in the fixed harness order. */
  harnesses: MCPClient[];
  /** At most three verbatim lines. */
  examples: string[];
}

interface Tally {
  kind: SessionPattern['kind'];
  name: string;
  occurrences: number;
  seen: Set<MCPClient>;
  examples: string[];
}

export function extractPatterns(entries: SessionEntry[], floor = PATTERN_FLOOR): SessionPattern[] {
  const tallies = new Map<string, Tally>();
  for (const entry of entries) {
    for (const raw of entry.text.split('\n')) {
      const line = raw.trim();
      const signal = signalOf(line);
      if (signal === undefined) continue;
      const key = `${signal.kind}\u001f${signal.name}`;
      let tally = tallies.get(key);
      if (tally === undefined) {
        tally = { kind: signal.kind, name: signal.name, occurrences: 0, seen: new Set(), examples: [] };
        tallies.set(key, tally);
      }
      tally.occurrences += 1;
      tally.seen.add(entry.harness);
      if (tally.examples.length < PATTERN_EXAMPLES && !tally.examples.includes(line)) tally.examples.push(line);
    }
  }
  const ranked = [...tallies.values()]
    .filter((tally) => tally.occurrences >= floor)
    .map(toPattern)
    .sort((left, right) => {
      if (left.occurrences !== right.occurrences) return right.occurrences - left.occurrences;
      return left.signal < right.signal ? -1 : left.signal > right.signal ? 1 : 0;
    });
  return ranked.slice(0, PATTERN_LIMIT);
}

function toPattern(tally: Tally): SessionPattern {
  return {
    kind: tally.kind,
    signal: tally.name,
    occurrences: tally.occurrences,
    harnesses: MCP_CLIENTS.filter((client) => tally.seen.has(client)),
    examples: tally.examples,
  };
}

/**
 * What one line contributes, or nothing.
 *
 * A stated heuristic rather than a parser, and its exclusions are the point. A line counts as a command only when its
 * head looks like a binary name and the line carries either a flag or a bare subcommand within eight tokens. Prose
 * therefore does not count: "can you run the docker logs for me" has no flag and nothing after its head that is a
 * subcommand, so it contributes nothing rather than a command called "can you".
 */
export function signalOf(line: string): { kind: SessionPattern['kind']; name: string } | undefined {
  const missing = missingTool(line);
  if (missing !== undefined) return { kind: 'missingTool', name: missing };
  const tokens = line.split(' ').filter((token) => token.length > 0);
  const head = tokens[0];
  if (head === undefined || !isBinaryName(head) || tokens.length > 8) return undefined;
  const rest = tokens.slice(1);
  const hasFlag = rest.some((token) => token.startsWith('-') && token.length > 1);
  const first = rest[0];
  const subcommand = first !== undefined && isBareWord(first) ? first : undefined;
  if (!hasFlag && subcommand === undefined) return undefined;
  return { kind: 'command', name: subcommand === undefined ? head : `${head} ${subcommand}` };
}

const NOT_FOUND = 'command not found';

/** `zsh: command not found: pgcli`, `bash: pgcli: command not found`, and the bare form. */
export function missingTool(line: string): string | undefined {
  const at = line.indexOf(NOT_FOUND);
  if (at < 0) return undefined;
  const after = line.slice(at + NOT_FOUND.length).trim();
  if (after.startsWith(':')) {
    const name = after.slice(1).trim();
    return isBinaryName(name) ? name : undefined;
  }
  const before = line.slice(0, at).trim();
  if (!before.endsWith(':')) return undefined;
  const candidate = before
    .slice(0, -1)
    .split(':')
    .filter((part) => part.length > 0)
    .pop();
  if (candidate === undefined) return undefined;
  const name = candidate.trim();
  return isBinaryName(name) ? name : undefined;
}

const BINARY_NAME = /^\p{Ll}[\p{Ll}\p{N}_.+-]*$/u;
const BARE_WORD = /^\p{Ll}[\p{Ll}\p{N}-]*$/u;

function withinLength(token: string): boolean {
  const length = [...token].length;
  return length >= 2 && length <= 24;
}

export function isBinaryName(token: string): boolean {
  return withinLength(token) && BINARY_NAME.test(token);
}

export function isBareWord(token: string): boolean {
  return withinLength(token) && BARE_WORD.test(token);
}
