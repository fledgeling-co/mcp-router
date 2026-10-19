/**
 * The session analyst: corpus, patterns, candidates, judge, reject, dedupe, record. Ported from AnalystEngine.swift,
 * AnalystRecords.swift, AnalystStateCoding.swift, RegistryCandidateSource.swift and the analyst half of
 * ControlAnalyst.swift.
 *
 * F7, spec-F7.md §3. Every figure the analyst reports is one it counted. The finding's subject comes from the
 * router, not the model. A finding seen before stays quiet for thirty days. The cadence is a stored setting the
 * wire says is not a schedule.
 *
 * The state file is the Swift router's `analyst.json`, in the same shape, so either daemon can read the other's file
 * while both exist.
 */
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { readSessionCorpus, type SessionCorpus, type SessionStoreReport } from './analyst-corpus.js';
import { extractPatterns, type SessionPattern } from './analyst-patterns.js';
import {
  AnalystJudgeError,
  analystPrompt,
  readJudgements,
  type AnalystCandidate,
  type AnalystJudge,
} from './analyst-judge.js';
import {
  applySettings,
  cadenceNextRunAt,
  cadenceLabel,
  DEFAULT_SETTINGS,
  encodeSettings,
  isAnalystLane,
  ladderOf,
  laneLabel,
  laneModel,
  parseSettings,
  type AnalystLane,
  type AnalystSettings,
} from './analyst-lanes.js';
import { MCP_CLIENTS, type MCPClient } from './harness.js';
import { searchRegistries, type RegistryEntry, type SearchResult } from './registry.js';
import { log } from './log.js';

/** How long a delivered finding stays quiet. Thirty days. */
export const SUPPRESSION_MILLISECONDS = 30 * 24 * 3_600_000;

export interface AnalystFindingRecord {
  id: string;
  entryID: string;
  subject: string;
  sentence: string;
  evidenceCount: number;
  /** The lane that produced it, carried per finding so a fallback run never reads as the primary's. */
  judgedBy: AnalystLane;
  signals: string[];
}

export interface AnalystRunRecord {
  /** The lane that judged, or null when nothing was judged. */
  lane: AnalystLane | null;
  ranAtMilliseconds: number;
  linesRead: number;
  discardedLines: number;
  usedFallback: boolean;
  /** Replies the run threw away: an id outside the candidate list, or a line it could not read. */
  rejectedFindings: number;
  /** The router could name no capability, so nothing was recommended and nothing was inferred. */
  candidatesUnavailable: boolean;
  stores: SessionStoreReport[];
  findings: AnalystFindingRecord[];
}

export type AnalyseOutcome =
  | { kind: 'run'; run: AnalystRunRecord }
  | { kind: 'alreadyRunning' }
  | { kind: 'ladderExhausted'; refusals: string[] };

/** Where the candidate list comes from. `null` means the router has no way to name a capability. */
export interface AnalystCandidateSource {
  candidates(signals: string[]): Promise<AnalystCandidate[] | null>;
}

/** The analyst as the control API needs it. Absent on the daemon's deps, the routes answer 503 naming the
 * capability. */
export interface AnalystPort {
  settings(): AnalystSettings;
  lastRun(): AnalystRunRecord | null;
  analyse(): Promise<AnalyseOutcome>;
  /** Throws `AnalystSettingsRefusal` naming the member it refused. */
  update(patch: unknown): AnalystSettings;
}

interface AnalystState {
  settings: AnalystSettings;
  lastRun: AnalystRunRecord | null;
  /** Fingerprint and the millisecond it was first delivered. */
  delivered: Array<{ fingerprint: string; at: number }>;
}

export interface AnalystEngineOptions {
  /** The directory the session stores live under. */
  home: string;
  /** Where the settings, last run and delivered fingerprints are kept. */
  statePath: string;
  judge: AnalystJudge;
  candidates: AnalystCandidateSource | null;
  now: () => number;
}

export class AnalystEngine implements AnalystPort {
  private readonly options: AnalystEngineOptions;
  private state: AnalystState;
  private running = false;

  constructor(options: AnalystEngineOptions) {
    this.options = options;
    this.state = loadState(options.statePath);
  }

  settings(): AnalystSettings {
    return this.state.settings;
  }

  lastRun(): AnalystRunRecord | null {
    return this.state.lastRun;
  }

  update(patch: unknown): AnalystSettings {
    this.state.settings = applySettings(patch, this.state.settings);
    this.persist();
    return this.state.settings;
  }

  /**
   * Corpus, patterns, candidates, judge, reject, dedupe, record. A second caller while one run is in flight is refused
   * rather than queued: a queued second run would be a full run nobody asked for.
   */
  async analyse(): Promise<AnalyseOutcome> {
    if (this.running) return { kind: 'alreadyRunning' };
    this.running = true;
    try {
      return await this.analyseOnce();
    } finally {
      this.running = false;
    }
  }

  private async analyseOnce(): Promise<AnalyseOutcome> {
    const corpus = readSessionCorpus(this.options.home);
    const patterns = extractPatterns(corpus.entries);
    // `null` and `[]` are different answers. Only the first is candidatesUnavailable.
    const offered =
      patterns.length === 0
        ? []
        : this.options.candidates === null
          ? null
          : await this.options.candidates.candidates(patterns.map((pattern) => pattern.signal));
    if (offered === null || offered.length === 0 || patterns.length === 0) {
      return { kind: 'run', run: this.record(corpus, { unavailable: offered === null }) };
    }
    return this.judged(corpus, patterns, offered);
  }

  private async judged(
    corpus: SessionCorpus,
    patterns: SessionPattern[],
    candidates: AnalystCandidate[],
  ): Promise<AnalyseOutcome> {
    const prompt = analystPrompt(patterns, candidates);
    const signals = patterns.map((pattern) => pattern.signal);
    const refusals: string[] = [];
    for (const [index, lane] of ladderOf(this.state.settings).entries()) {
      let reply: string;
      try {
        reply = await this.options.judge.judge(prompt, lane);
      } catch (err) {
        refusals.push(`${lane}: ${describe(err)}`);
        continue;
      }
      const read = readJudgements(reply, candidates, signals);
      const findings = this.deliver(read.accepted, patterns, candidates, lane);
      return {
        kind: 'run',
        run: this.record(corpus, { lane, usedFallback: index > 0, rejected: read.rejected, findings }),
      };
    }
    return { kind: 'ladderExhausted', refusals };
  }

  /** Turn accepted judgements into findings, dropping those already delivered inside the window. */
  private deliver(
    judgements: Array<{ entryID: string; sentence: string; signal: string }>,
    patterns: SessionPattern[],
    candidates: AnalystCandidate[],
    lane: AnalystLane,
  ): AnalystFindingRecord[] {
    const now = this.options.now();
    const fresh: AnalystFindingRecord[] = [];
    for (const judgement of judgements) {
      const candidate = candidates.find((c) => c.id === judgement.entryID);
      const pattern = patterns.find((p) => p.signal === judgement.signal);
      if (candidate === undefined || pattern === undefined) continue;
      const finding: AnalystFindingRecord = {
        id: findingId(judgement.entryID, judgement.signal),
        entryID: candidate.id,
        subject: candidate.name,
        sentence: judgement.sentence,
        evidenceCount: pattern.occurrences,
        judgedBy: lane,
        signals: [judgement.signal],
      };
      const key = fingerprint(finding);
      if (isSuppressed(this.state, key, now)) continue;
      this.state.delivered = this.state.delivered.filter((entry) => entry.fingerprint !== key);
      this.state.delivered.push({ fingerprint: key, at: now });
      fresh.push(finding);
    }
    return fresh;
  }

  private record(
    corpus: SessionCorpus,
    judged: {
      lane?: AnalystLane;
      usedFallback?: boolean;
      rejected?: number;
      unavailable?: boolean;
      findings?: AnalystFindingRecord[];
    },
  ): AnalystRunRecord {
    const run: AnalystRunRecord = {
      lane: judged.lane ?? null,
      ranAtMilliseconds: this.options.now(),
      linesRead: corpus.reports.reduce((sum, report) => sum + report.lines, 0),
      discardedLines: corpus.reports.reduce((sum, report) => sum + report.discarded, 0),
      usedFallback: judged.usedFallback ?? false,
      rejectedFindings: judged.rejected ?? 0,
      candidatesUnavailable: judged.unavailable ?? false,
      stores: corpus.reports,
      findings: judged.findings ?? [],
    };
    this.state.lastRun = run;
    this.persist();
    return run;
  }

  private persist(): void {
    try {
      writeFileSync(this.options.statePath, JSON.stringify(encodeState(this.state), null, 2));
    } catch (err) {
      log.warn(`analyst: could not write ${this.options.statePath}: ${(err as Error).message}`);
    }
  }
}

function describe(err: unknown): string {
  return err instanceof AnalystJudgeError ? err.message : String(err);
}

function isSuppressed(state: AnalystState, key: string, now: number): boolean {
  const seen = state.delivered.find((entry) => entry.fingerprint === key);
  return seen !== undefined && now - seen.at < SUPPRESSION_MILLISECONDS;
}

/**
 * What suppression is keyed on: the entry, and the signals that argued for it. The signals are in the key on purpose. A
 * finding whose evidence has grown a new signal is a different finding.
 */
function fingerprint(finding: AnalystFindingRecord): string {
  return [finding.entryID, ...[...finding.signals].sort()].join('\u001f');
}

/**
 * A stable id for one recommendation. FNV-1a over the entry and signal, 64-bit, so the id matches the one the
 * Swift router computes for the same pair. Not a hash anything security-bearing rests on.
 */
export function findingId(entryID: string, signal: string): string {
  let hash = 0xcbf29ce484222325n;
  for (const byte of new TextEncoder().encode(`${entryID}\u001f${signal}`)) {
    hash = BigInt.asUintN(64, (hash ^ BigInt(byte)) * 0x100000001b3n);
  }
  return `analyst-${hash.toString(16)}`;
}

/* ------------------------------------------------------------------ state file */

function loadState(path: string): AnalystState {
  if (!existsSync(path)) return emptyState();
  try {
    return decodeState(JSON.parse(readFileSync(path, 'utf8')));
  } catch (err) {
    log.warn(`analyst: ${path} did not parse, so the analyst starts from its defaults: ${(err as Error).message}`);
    return emptyState();
  }
}

function emptyState(): AnalystState {
  return { settings: { ...DEFAULT_SETTINGS }, lastRun: null, delivered: [] };
}

/**
 * Every member is optional on the way in. This file outlives the build that wrote it, and the thirty-day promise
 * is only kept if a file written by an older router still yields its fingerprints.
 */
function decodeState(value: unknown): AnalystState {
  const record = asRecord(value);
  const delivered = asArray(record.delivered).flatMap((item) => {
    const entry = asRecord(item);
    return typeof entry.fingerprint === 'string' && typeof entry.at === 'number'
      ? [{ fingerprint: entry.fingerprint, at: entry.at }]
      : [];
  });
  return {
    settings: parseSettings(record.settings),
    lastRun: record.lastRun === undefined || record.lastRun === null ? null : decodeRun(record.lastRun),
    delivered,
  };
}

function decodeRun(value: unknown): AnalystRunRecord | null {
  const record = asRecord(value);
  if (typeof record.ranAt !== 'number') return null;
  return {
    lane: isAnalystLane(record.lane) ? record.lane : null,
    ranAtMilliseconds: record.ranAt,
    linesRead: numberOr(record.linesRead, 0),
    discardedLines: numberOr(record.discarded, 0),
    usedFallback: record.usedFallback === true,
    rejectedFindings: numberOr(record.rejected, 0),
    candidatesUnavailable: record.candidatesUnavailable === true,
    stores: asArray(record.stores).flatMap(decodeStore),
    findings: asArray(record.findings).flatMap(decodeFinding),
  };
}

function decodeStore(value: unknown): SessionStoreReport[] {
  const record = asRecord(value);
  if (!isClient(record.harness)) return [];
  return [
    {
      harness: record.harness,
      path: typeof record.path === 'string' ? record.path : '',
      read: record.read === true,
      lines: numberOr(record.lines, 0),
      discarded: numberOr(record.discarded, 0),
      reason: typeof record.reason === 'string' ? record.reason : null,
    },
  ];
}

function decodeFinding(value: unknown): AnalystFindingRecord[] {
  const record = asRecord(value);
  if (typeof record.id !== 'string' || typeof record.entryID !== 'string' || !isAnalystLane(record.judgedBy)) {
    return [];
  }
  return [
    {
      id: record.id,
      entryID: record.entryID,
      subject: typeof record.subject === 'string' ? record.subject : record.entryID,
      sentence: typeof record.sentence === 'string' ? record.sentence : '',
      evidenceCount: numberOr(record.evidenceCount, 0),
      judgedBy: record.judgedBy,
      signals: asArray(record.signals).filter((s): s is string => typeof s === 'string'),
    },
  ];
}

function encodeState(state: AnalystState): Record<string, unknown> {
  return {
    settings: encodeSettings(state.settings),
    lastRun: state.lastRun === null ? null : encodeRun(state.lastRun),
    delivered: state.delivered.map((entry) => ({ fingerprint: entry.fingerprint, at: entry.at })),
  };
}

function encodeRun(run: AnalystRunRecord): Record<string, unknown> {
  return {
    lane: run.lane,
    ranAt: run.ranAtMilliseconds,
    linesRead: run.linesRead,
    discarded: run.discardedLines,
    usedFallback: run.usedFallback,
    rejected: run.rejectedFindings,
    candidatesUnavailable: run.candidatesUnavailable,
    stores: run.stores.map(encodeStore),
    findings: run.findings.map((finding) => ({
      id: finding.id,
      entryID: finding.entryID,
      subject: finding.subject,
      sentence: finding.sentence,
      evidenceCount: finding.evidenceCount,
      judgedBy: finding.judgedBy,
      signals: finding.signals,
    })),
  };
}

function encodeStore(report: SessionStoreReport): Record<string, unknown> {
  return {
    harness: report.harness,
    path: report.path,
    read: report.read,
    lines: report.lines,
    discarded: report.discarded,
    reason: report.reason,
  };
}

const asRecord = (value: unknown): Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
const asArray = (value: unknown): unknown[] => (Array.isArray(value) ? value : []);
const numberOr = (value: unknown, fallback: number): number => (typeof value === 'number' ? value : fallback);
const isClient = (value: unknown): value is MCPClient =>
  typeof value === 'string' && (MCP_CLIENTS as readonly string[]).includes(value);

/* ------------------------------------------------------------------- the wire */

/**
 * The 503 body when the router has no analyst. It names the missing capability, because an empty run is
 * indistinguishable from a router that analysed and found nothing, which is the reading these routes exist to make.
 */
export const ANALYST_UNAVAILABLE = 'session analysis is unavailable: this router has no analyst';

/**
 * The analyst as `GET /insights` and the analyst routes send it. Built member by member, as the Swift `AnalystJSON` is.
 *
 * `scheduled` is false on the wire and says so: the cadence is a stored setting and nothing fires it. Absent
 * readings are null, never zero, because a `linesRead: 0` on a run that never happened is a measurement of nothing.
 */
export function analystEnvelope(run: AnalystRunRecord | null, settings: AnalystSettings): Record<string, unknown> {
  const next = cadenceNextRunAt(settings.cadence, run?.ranAtMilliseconds ?? null);
  return {
    primary: laneChoice(settings.primary),
    fallback: settings.fallback === null ? null : laneChoice(settings.fallback),
    cadence: settings.cadence,
    cadenceLabel: cadenceLabel(settings.cadence),
    scheduled: false,
    nextRunAt: next === null ? null : new Date(next).toISOString(),
    ...runMembers(run),
  };
}

function laneChoice(lane: AnalystLane): Record<string, string> {
  return { lane, model: laneModel(lane), label: laneLabel(lane) };
}

function runMembers(run: AnalystRunRecord | null): Record<string, unknown> {
  if (run === null) return { lane: null, ranAt: null, stores: [], recent: [] };
  return {
    lane: run.lane === null ? null : laneChoice(run.lane),
    ranAt: new Date(run.ranAtMilliseconds).toISOString(),
    linesRead: run.linesRead,
    discarded: run.discardedLines,
    findings: run.findings.length,
    usedFallback: run.usedFallback,
    rejectedFindings: run.rejectedFindings,
    candidatesUnavailable: run.candidatesUnavailable,
    stores: run.stores.map(encodeStore),
    recent: run.findings.map((finding) => ({
      id: finding.id,
      entryID: finding.entryID,
      subject: finding.subject,
      sentence: finding.sentence,
      evidenceCount: finding.evidenceCount,
      // The label, not the rawValue: a surface spells the judge the way its settings readout does.
      judgedBy: laneLabel(finding.judgedBy),
      signals: finding.signals,
    })),
  };
}

/* ------------------------------------------------------------- the candidates */

/** The router names the capabilities. The model only chooses between them. A recommendation must resolve to
 * an entry. */
export const CANDIDATE_SEARCHES = 4;
export const CANDIDATE_RESULTS_PER_SEARCH = 5;
export const CANDIDATE_CAP = 20;

/**
 * Candidates from the registry the Discover board searches. One search per signal, capped, merged in first-seen order.
 * `null` when no search completed, so an unreachable registry reads as candidatesUnavailable rather than as no results.
 */
export function registryCandidates(search: typeof searchRegistries = searchRegistries): AnalystCandidateSource {
  return {
    async candidates(signals) {
      const found: AnalystCandidate[] = [];
      const seen = new Set<string>();
      let reached = false;
      for (const signal of signals.slice(0, CANDIDATE_SEARCHES)) {
        let outcome: SearchResult;
        try {
          outcome = await search(queryOf(signal), CANDIDATE_RESULTS_PER_SEARCH);
        } catch {
          continue;
        }
        reached = true;
        for (const row of outcome.results) {
          const candidate = candidateOf(row);
          if (seen.has(candidate.id)) continue;
          seen.add(candidate.id);
          found.push(candidate);
        }
      }
      return reached ? found.slice(0, CANDIDATE_CAP) : null;
    },
  };
}

/** A command signal is `docker logs`, and the useful query is `docker`. A missing-tool signal is already the term. */
function queryOf(signal: string): string {
  return signal.split(' ').find((part) => part.length > 0) ?? signal;
}

function candidateOf(row: RegistryEntry): AnalystCandidate {
  const id = row.name || row.id;
  return {
    id,
    name: row.displayName || id,
    summary: row.description || 'no description in the registry',
  };
}
