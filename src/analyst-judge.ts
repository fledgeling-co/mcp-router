/**
 * The judge: the prompt, the reading of what comes back, and the CLI that answers. Ported from AnalystJudge.swift,
 * AnalystProcessRunner.swift and the prompt half of AnalystPrompt.
 *
 * The candidate ids are in the prompt and the answer is checked against them anyway. Asking for an id from a list is a
 * request; `readJudgements` is the enforcement, and the two are deliberately separate mechanisms.
 */
import { spawn } from 'node:child_process';
import { accessSync, constants, statSync } from 'node:fs';
import { join } from 'node:path';
import { laneArguments, laneBinary, type AnalystLane } from './analyst-lanes.js';
import type { SessionPattern } from './analyst-patterns.js';
import { harnessDisplayName } from './harness.js';
import { PATH_LIST_SEPARATOR } from './platform.js';

/** One thing the router could recommend, as the router knows it. */
export interface AnalystCandidate {
  id: string;
  name: string;
  summary: string;
}

/** A judgement the router has checked against the candidates and the patterns that reached the prompt. */
export interface AnalystJudgement {
  entryID: string;
  sentence: string;
  signal: string;
}

export type AnalystJudgeErrorKind = 'notInstalled' | 'refused' | 'empty';

/**
 * - notInstalled: the binary is not on PATH, so this rung was never tried.
 * - refused: it ran and did not succeed (a usage limit, a signed-out CLI, a non-zero exit).
 * - empty: it ran, succeeded, and wrote nothing. A lane that answers empty is not a lane that is down.
 */
export class AnalystJudgeError extends Error {
  readonly kind: AnalystJudgeErrorKind;

  constructor(kind: AnalystJudgeErrorKind, message: string) {
    super(message);
    this.name = 'AnalystJudgeError';
    this.kind = kind;
  }
}

/** Asks one lane one question. The seam the engine tests drive, so no test reaches a real CLI. */
export interface AnalystJudge {
  judge(prompt: string, lane: AnalystLane): Promise<string>;
}

export interface CommandOutcome {
  status: number;
  output: string;
}

/** Runs one CLI. `null` when the binary is not on PATH: an absence, so the ladder falls through without a refusal. */
export interface CommandRunner {
  run(binary: string, args: string[]): Promise<CommandOutcome | null>;
}

/** The judge that shells out to a CLI the user is already signed into. */
export function cliJudge(runner: CommandRunner): AnalystJudge {
  return {
    async judge(prompt, lane) {
      const binary = laneBinary(lane);
      const outcome = await runner.run(binary, laneArguments(lane, prompt));
      if (outcome === null) throw new AnalystJudgeError('notInstalled', `${binary} is not on PATH`);
      if (outcome.status !== 0) {
        const lines = outcome.output.split('\n').filter((line) => line.length > 0);
        throw new AnalystJudgeError('refused', `${binary} exited ${outcome.status}: ${lines.at(-1) ?? ''}`);
      }
      if (outcome.output.trim() === '') throw new AnalystJudgeError('empty', `${binary} wrote nothing`);
      return outcome.output;
    },
  };
}

/** The prompt. The model sees counted signals and their examples, never the corpus. */
export function analystPrompt(patterns: SessionPattern[], candidates: AnalystCandidate[]): string {
  const lines = [
    "You are reading a summary of one developer's own terminal history.",
    'Recommend capabilities that would remove repeated manual work.',
    '',
    'Answer with one JSON object per line and nothing else:',
    '{"entry": "<id from the list below>", "signal": "<one signal from What recurred>", "why": "<one sentence>"}',
    'Recommend nothing rather than guessing. A line naming anything not in these two lists is discarded.',
    '',
    'What recurred:',
  ];
  for (const pattern of patterns) {
    const seenIn = pattern.harnesses.map(harnessDisplayName).join(', ');
    lines.push(`- ${pattern.kind} "${pattern.signal}" ×${pattern.occurrences} in ${seenIn}`);
    for (const example of pattern.examples) lines.push(`    e.g. ${example}`);
  }
  lines.push('', 'Capabilities available to install:');
  for (const candidate of candidates) {
    lines.push(`- ${candidate.id} — ${candidate.name}: ${candidate.summary}`);
  }
  return lines.join('\n');
}

/**
 * Read the reply, keeping only what names a candidate and a counted signal. Returns the accepted judgements
 * and the number thrown away, because an engine that discarded everything and one handed nothing produce the same
 * empty list.
 */
export function readJudgements(
  reply: string,
  candidates: AnalystCandidate[],
  signals: string[],
): { accepted: AnalystJudgement[]; rejected: number } {
  const known = new Set(candidates.map((candidate) => candidate.id));
  const knownSignals = new Set(signals);
  const accepted: AnalystJudgement[] = [];
  let rejected = 0;
  for (const raw of reply.split('\n')) {
    const text = raw.trim();
    if (!text.startsWith('{')) continue;
    const parsed = parseRecord(text);
    const entry = parsed?.entry;
    const signal = parsed?.signal;
    const why = parsed?.why;
    if (typeof entry !== 'string' || typeof signal !== 'string' || typeof why !== 'string' || why === '') {
      rejected += 1;
      continue;
    }
    if (!known.has(entry) || !knownSignals.has(signal) || accepted.some((a) => a.entryID === entry)) {
      rejected += 1;
      continue;
    }
    accepted.push({ entryID: entry, sentence: why, signal });
  }
  return { accepted, rejected };
}

function parseRecord(text: string): Record<string, unknown> | undefined {
  try {
    const parsed: unknown = JSON.parse(text);
    return typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)
      ? (parsed as Record<string, unknown>)
      : undefined;
  } catch {
    return undefined;
  }
}

/** One judgement's wall-clock budget. The caller is a button, so a run is abandoned rather than held open. */
export const ANALYST_TIMEOUT_MS = 120_000;
/** How much of a reply is kept. A CLI that prints a transcript must not be able to spend the router's memory. */
export const ANALYST_OUTPUT_CAP = 256 * 1024;

/**
 * The real runner: one CLI, no shell, bounded in time and in how much output is kept. The arguments go to `spawn`
 * directly and are never joined into a command line. The prompt carries excerpts of the user's own shell history, and a
 * `$(` or a backtick in something they ran would be executed by any shell that saw it.
 */
export function processRunner(
  environment: NodeJS.ProcessEnv = process.env,
  timeoutMs = ANALYST_TIMEOUT_MS,
): CommandRunner {
  return {
    run: (binary, args) => {
      const executable = resolveOnPath(binary, environment.PATH ?? '');
      if (executable === undefined) return Promise.resolve(null);
      return new Promise<CommandOutcome | null>((resolve) => {
        let settled = false;
        const settle = (outcome: CommandOutcome | null): void => {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          resolve(outcome);
        };

        // Stdin is ignored, so a CLI that decides to prompt reads end-of-file and exits rather than
        // waiting for a person.
        const child = spawn(executable, args, { env: environment, stdio: ['ignore', 'pipe', 'pipe'] });
        const chunks: Buffer[] = [];
        let kept = 0;
        const take = (chunk: Buffer): void => {
          if (kept >= ANALYST_OUTPUT_CAP) return;
          const part = chunk.subarray(0, ANALYST_OUTPUT_CAP - kept);
          chunks.push(part);
          kept += part.length;
        };
        child.stdout.on('data', take);
        child.stderr.on('data', take);
        const timer = setTimeout(() => {
          child.kill('SIGTERM');
          settle({ status: 124, output: `timed out after ${timeoutMs / 1000}s` });
        }, timeoutMs);
        // A binary that cannot be started is an absence, the same as one not on PATH.
        child.on('error', () => settle(null));
        child.on('close', (code) => {
          // Lossy decoding is deliberate: a readable answer is not refused because one byte was not UTF-8.
          settle({ status: code ?? -1, output: Buffer.concat(chunks).toString('utf8') });
        });
      });
    },
  };
}

/** A PATH lookup by hand, so a binary that is absent is reported as absent rather than as a rung that exited 127. */
function resolveOnPath(binary: string, path: string): string | undefined {
  for (const directory of path.split(PATH_LIST_SEPARATOR)) {
    if (directory === '') continue;
    const candidate = join(directory, binary);
    try {
      accessSync(candidate, constants.X_OK);
      if (statSync(candidate).isFile()) return candidate;
    } catch {
      // Not here, or not executable here: keep looking along PATH.
    }
  }
  return undefined;
}
