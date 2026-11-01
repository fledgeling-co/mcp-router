import { appendFileSync, mkdirSync, readFileSync, writeFileSync, renameSync, existsSync, statSync, rmSync, readdirSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { dirname, basename, join } from 'node:path';
import type { Socket } from 'node:net';
import { log } from './log.js';
import { peerOfLocalPort } from './platform.js';

/** One tool call, as it happened. This is the unit the app's activity view renders. */
export interface UsageRecord {
  ts: string;
  server: string;
  tool: string;
  ok: boolean;
  /** Wall-clock milliseconds, including any cold start. */
  ms: number;
  /** True when this call is what started the upstream — the cost the router defers. */
  cold: boolean;
  /** Process id of the client that called. Identifies one Claude session. */
  pid?: number;
  /** The client's working directory: which project the call came from. */
  cwd?: string;
  /** Last path segment of cwd, for display. */
  project?: string;
  /** The client's executable name, e.g. `claude`. */
  client?: string;
  err?: string;
}

export interface ServerStat {
  calls: number;
  errors: number;
  firstSeen?: string;
  lastUsed?: string;
  /** Per-directory call counts, so the app can say who uses a server. */
  projects: Record<string, number>;
}

interface StatsFile {
  version: 1;
  since: string;
  servers: Record<string, ServerStat>;
  /** What retention has removed. Optional so a stats file from before retention still reads. */
  retention?: RetentionLedger;
}

/**
 * What retention has removed from the call history, kept in the stats file so it survives a restart.
 *
 * `aged` is the policy working: generations past the retention window. `capped` is a loss: generations
 * removed to stay under the size cap while still inside the window. Only `capped` can make a window
 * incomplete, and `from`/`to` say which part of the history is gone.
 */
export interface RetentionLedger {
  aged: { generations: number; records: number };
  capped: { generations: number; records: number; from: string | null; to: string | null };
}

/** What `GET /insights` reports about retention, so the board can say what the history is made of. */
export interface UsageRetention {
  days: number;
  capMegabytes: number;
  aged: RetentionLedger['aged'];
  capped: RetentionLedger['capped'];
}

export interface ClientIdentity {
  pid?: number;
  cwd?: string;
  client?: string;
}

const UNKNOWN: ClientIdentity = {};
const IDENT = Symbol('mcp-router.client');
const MAX_LOG_BYTES = 8 * 1024 * 1024;
const RING_SIZE = 500;

/** A reset can erase some files before another filesystem operation refuses it. */
export class UsageResetError extends Error {
  readonly partialReset: boolean;

  constructor(
    readonly phase: 'prepare' | 'delete' | 'commit',
    readonly removedFiles: number,
    cause: unknown
  ) {
    const code = (cause as NodeJS.ErrnoException)?.code ?? 'filesystem error';
    super(
      `Usage history reset failed during ${phase} (${code}). ` +
      (removedFiles > 0
        ? 'Some history files were removed; the reset did not complete. Reload usage before trying again.'
        : 'Usage history was not reset.'),
      { cause }
    );
    this.name = 'UsageResetError';
    this.partialReset = removedFiles > 0;
  }
}

/** How long call history is kept. Seven days, so a 7-day window is a measurement of the router's history rather than of whatever survived. */
export const RETAIN_DAYS = 7;
const HOUR_MS = 3_600_000;

/**
 * The knobs retention runs on. Every value is a default a test can replace, so the rotation and cap paths can be
 * exercised over a few hundred bytes rather than eight mebibytes.
 */
export interface UsagePolicy {
  /** The size one generation may reach before the active log rotates. */
  generationBytes: number;
  /**
   * The most history kept on disk, enforced at each rotation: above it the oldest generations go, and the ledger says so.
   * Between rotations the active log grows, so the history can sit above this by one generation.
   */
  capBytes: number;
  /** How old a generation's last write may be before it is removed. */
  retainMs: number;
}

export const DEFAULT_USAGE_POLICY: UsagePolicy = {
  generationBytes: MAX_LOG_BYTES,
  // Seven days at a busy machine's rate is well under this; the cap exists so a runaway caller cannot fill the disk.
  capBytes: 256 * 1024 * 1024,
  retainMs: RETAIN_DAYS * 24 * HOUR_MS,
};

/**
 * Work out which process is on the other end of a loopback connection.
 *
 * The MCP protocol carries nothing that identifies a session: `clientInfo` says
 * "claude-code" for every window on the machine, and this router is deliberately
 * stateless so there is no session id either. The socket, though, is a real object
 * with a real peer, and the OS will name the process holding it. That is what turns
 * "something called browser_navigate" into "the session working in ~/Dev/mcp-router
 * called browser_navigate", which is the question the app exists to answer.
 *
 * Cost is paid once per connection, not per call, and every failure path returns
 * an empty identity: an unattributed record is worth far more than a dropped one.
 *
 * WIN17 — **this is smaller on Windows and that is a deliberate, stated limit.** macOS reads both
 * halves out of `lsof`: the process and its working directory. Windows gives up the pid readily
 * (`netstat -ano`, 23 ms) and the image name from `Get-Process`, but a foreign process's current
 * directory lives in its PEB and is not readable without opening the process. So a Windows usage
 * record carries a pid and a client name and **no cwd**, and therefore no `project` — the field the
 * activity view groups by. That is a narrower record, not a wrong one; nothing is guessed to fill
 * the gap. `platform.ts` holds the mechanism.
 */
export class ClientResolver {
  private byPid = new Map<number, ClientIdentity>();

  async identify(socket: Socket | undefined | null): Promise<ClientIdentity> {
    if (!socket) return UNKNOWN;

    const cached = (socket as unknown as Record<symbol, ClientIdentity | Promise<ClientIdentity>>)[IDENT];
    if (cached) return await cached;

    const port = socket.remotePort;
    if (!port) return UNKNOWN;

    const pending = this.resolve(port).catch(() => UNKNOWN);
    (socket as unknown as Record<symbol, Promise<ClientIdentity>>)[IDENT] = pending;
    const identity = await pending;
    // Replace the promise with the value so later calls skip the microtask.
    (socket as unknown as Record<symbol, ClientIdentity>)[IDENT] = identity;
    return identity;
  }

  private async resolve(peerPort: number): Promise<ClientIdentity> {
    const peer = await peerOfLocalPort(peerPort, process.pid);
    if (!peer.pid) return UNKNOWN;

    const known = this.byPid.get(peer.pid);
    if (known) return known;

    const identity: ClientIdentity = { pid: peer.pid, client: peer.client, cwd: peer.cwd || undefined };
    // A pid is reused eventually, but not within one router lifetime in any
    // realistic case, and the cost of being wrong is a mislabelled log line.
    this.byPid.set(peer.pid, identity);
    if (this.byPid.size > 512) this.byPid.clear();
    return identity;
  }
}

/**
 * Appends every call to a JSONL file, keeps the recent tail in memory for the app,
 * and maintains a durable per-server aggregate.
 *
 * The aggregate is separate from the log on purpose. The log rotates, and a server
 * that has not been called for six months is exactly the one whose evidence rotates
 * out first — so "never used" computed from the log alone would be a lie that gets
 * more confident the longer it is true. The aggregate is what the cleanup view reads.
 */
export class UsageStore {
  private ring: UsageRecord[] = [];
  private stats: StatsFile;
  private subscribers = new Set<(r: UsageRecord) => void>();
  private flushTimer?: NodeJS.Timeout;
  private dirty = false;

  constructor(
    private readonly logPath: string,
    private readonly statsPath: string,
    private readonly policy: UsagePolicy = DEFAULT_USAGE_POLICY
  ) {
    mkdirSync(dirname(logPath), { recursive: true });
    this.stats = this.readStats();
    this.ring = this.readTail();
    this.prune(Date.now());
  }

  private readStats(): StatsFile {
    if (existsSync(this.statsPath)) {
      try {
        const s = JSON.parse(readFileSync(this.statsPath, 'utf8')) as StatsFile;
        if (s.version === 1 && s.servers) return s;
      } catch (err) {
        log.warn(`usage stats unreadable (${(err as Error).message}); starting fresh`);
      }
    }
    return { version: 1, since: new Date().toISOString(), servers: {} };
  }

  /** Warm the in-memory ring from the tail of the log so a restart is not a blank screen. */
  private readTail(): UsageRecord[] {
    if (!existsSync(this.logPath)) return [];
    try {
      const size = statSync(this.logPath).size;
      const raw = readFileSync(this.logPath, 'utf8');
      const from = size > 512 * 1024 ? raw.slice(raw.indexOf('\n', size - 512 * 1024) + 1) : raw;
      const out: UsageRecord[] = [];
      for (const line of from.split('\n')) {
        if (!line) continue;
        try {
          out.push(JSON.parse(line) as UsageRecord);
        } catch {
          /* a torn last line is normal after a hard kill */
        }
      }
      return out.slice(-RING_SIZE);
    } catch {
      return [];
    }
  }

  record(r: UsageRecord): void {
    this.ring.push(r);
    if (this.ring.length > RING_SIZE) this.ring.splice(0, this.ring.length - RING_SIZE);

    const s = (this.stats.servers[r.server] ??= { calls: 0, errors: 0, projects: {} });
    s.calls += 1;
    if (!r.ok) s.errors += 1;
    s.firstSeen ??= r.ts;
    s.lastUsed = r.ts;
    if (r.cwd) s.projects[r.cwd] = (s.projects[r.cwd] ?? 0) + 1;
    this.scheduleFlush();

    try {
      this.rotateIfBig();
      appendFileSync(this.logPath, JSON.stringify(r) + '\n');
    } catch (err) {
      log.warn(`usage log write failed: ${(err as Error).message}`);
    }

    for (const fn of this.subscribers) {
      try {
        fn(r);
      } catch {
        /* a broken subscriber must not stop the others */
      }
    }
  }

  private rotateIfBig(): void {
    try {
      if (statSync(this.logPath).size < this.policy.generationBytes) return;
    } catch {
      return; // no file yet
    }
    // Shift every generation one place older, then move the active log into `.1`. Highest first, so no rename
    // lands on a name still in use.
    for (const g of this.generations()) renameSync(g.path, `${this.logPath}.${g.n + 1}`);
    renameSync(this.logPath, `${this.logPath}.1`);
    log.info(`usage log rotated at ${this.policy.generationBytes} bytes`);
    this.prune(Date.now());
  }

  /**
   * Rotated generations of the log, newest first: `.1` is the most recent archive.
   *
   * Numbered rather than dated so the reader can walk them without parsing names, and the same shape the router's own
   * `router.log` rotation uses. A file from before retention, the old single `.1`, is one of these and reads as one.
   */
  private generations(strict = false): Array<{ n: number; path: string }> {
    const dir = dirname(this.logPath);
    const prefix = `${basename(this.logPath)}.`;
    let names: string[];
    try {
      names = readdirSync(dir);
    } catch (err) {
      if (strict) throw err;
      return [];
    }
    return names
      .filter((name) => name.startsWith(prefix) && /^\d+$/.test(name.slice(prefix.length)))
      .map((name) => ({ n: Number(name.slice(prefix.length)), path: join(dir, name) }))
      .sort((a, b) => b.n - a.n);
  }

  /**
   * Remove what retention no longer keeps, then what the size cap will not keep. Each removal goes into the ledger.
   *
   * A generation is aged out when its last write is older than the window. Every record in it was written at or
   * before that write, so none can be inside the window. A generation is capped out, oldest first, while the
   * history is over the cap; that is a loss, so it is logged at warn and recorded with the span it covered.
   */
  private prune(nowMs: number): void {
    const ledger = this.stats.retention ?? {
      aged: { generations: 0, records: 0 },
      capped: { generations: 0, records: 0, from: null, to: null },
    };
    const cutoff = nowMs - this.policy.retainMs;
    let changed = false;

    const kept: Array<{ n: number; path: string; size: number }> = [];
    for (const g of this.generations()) {
      const info = statSafely(g.path);
      if (!info) continue;
      if (info.mtimeMs < cutoff) {
        const removed = this.remove(g.path);
        ledger.aged.generations += 1;
        ledger.aged.records += removed.records;
        changed = true;
        if (removed.records > 0) log.info(`usage history older than ${RETAIN_DAYS} days removed: ${removed.records} records`);
        continue;
      }
      kept.push({ ...g, size: info.size });
    }

    // The active log is never removed here; it is bounded by rotation, and removing it would drop the file being written.
    let total = (statSafely(this.logPath)?.size ?? 0) + kept.reduce((sum, g) => sum + g.size, 0);
    while (total > this.policy.capBytes && kept.length > 0) {
      const oldest = kept.pop()!;
      const removed = this.remove(oldest.path);
      total -= oldest.size;
      ledger.capped.generations += 1;
      ledger.capped.records += removed.records;
      if (removed.from && (!ledger.capped.from || removed.from < ledger.capped.from)) ledger.capped.from = removed.from;
      if (removed.to && (!ledger.capped.to || removed.to > ledger.capped.to)) ledger.capped.to = removed.to;
      changed = true;
      log.warn(
        `usage history over ${Math.round(this.policy.capBytes / 1024 / 1024)} MiB: dropped ${removed.records} records` +
          (removed.to ? ` from ${removed.from} to ${removed.to}` : '')
      );
    }

    if (changed) {
      this.stats.retention = ledger;
      this.dirty = true;
      this.flush();
    }
  }

  /** Remove one generation and say what was in it. An unreadable file counts as nothing, and is removed all the same. */
  private remove(path: string): { records: number; from: string | null; to: string | null } {
    let records = 0;
    let from: string | null = null;
    let to: string | null = null;
    try {
      for (const line of readFileSync(path, 'utf8').split('\n')) {
        const record = parseRecord(line);
        if (!record) continue;
        records += 1;
        if (from === null || record.ts < from) from = record.ts;
        if (to === null || record.ts > to) to = record.ts;
      }
    } catch {
      /* counted as nothing */
    }
    try {
      rmSync(path, { force: true });
    } catch (err) {
      log.warn(`could not remove ${path}: ${(err as Error).message}`);
    }
    return { records, from, to };
  }

  /** Stats are written on a debounce: a burst of calls must not be a burst of fsyncs. */
  private scheduleFlush(): void {
    this.dirty = true;
    if (this.flushTimer) return;
    this.flushTimer = setTimeout(() => {
      this.flushTimer = undefined;
      this.flush();
    }, 3000);
    this.flushTimer.unref();
  }

  flush(): void {
    if (!this.dirty) return;
    this.dirty = false;
    try {
      const tmp = `${this.statsPath}.tmp-${process.pid}`;
      writeFileSync(tmp, JSON.stringify(this.stats, null, 2));
      renameSync(tmp, this.statsPath);
    } catch (err) {
      log.warn(`usage stats write failed: ${(err as Error).message}`);
    }
  }

  recent(opts: { limit?: number; server?: string; cwd?: string } = {}): UsageRecord[] {
    let out = this.ring;
    if (opts.server) out = out.filter((r) => r.server === opts.server);
    if (opts.cwd) out = out.filter((r) => r.cwd === opts.cwd);
    return out.slice(-(opts.limit ?? 200)).reverse();
  }

  summary(): { since: string; servers: Record<string, ServerStat> } {
    return { since: this.stats.since, servers: this.stats.servers };
  }

  /**
   * The window `GET /insights` answers over, folded from every generation the window can reach plus the active log.
   *
   * A generation whose last write is older than the window start holds nothing in the window, so it is not read.
   * That is what keeps the 24-hour window cheap while the history is a week. A file that cannot be read is not
   * skipped silently: it makes the window incomplete. A log that does not exist yet is an empty window, which is a
   * reading, not an error.
   */
  async insights(nowMs: number, windowHours: number): Promise<UsageWindow> {
    const startMs = windowStartMs(nowMs, windowHours);
    const coverage = {
      observedSince: this.stats.since,
      cappedThrough: this.stats.retention?.capped.to ?? null,
    };
    // Rotation renames files while this reader awaits, so a generation can move past a name already listed and go
    // unread with no error. A listing that changed during the read is read again; if it will not hold still, the
    // window says it is incomplete rather than folding a half-moved history.
    for (let attempt = 1; ; attempt++) {
      const before = this.generations().map((g) => g.path).join('\n');
      const fold = new UsageFold(nowMs, windowHours, coverage);
      const unreadableFiles = await this.foldWindow(fold, startMs);
      const after = this.generations().map((g) => g.path).join('\n');
      if (before === after) return fold.result(unreadableFiles);
      if (attempt === 3) return fold.result(unreadableFiles + 1);
    }
  }

  /** Fold every file the window can reach into `fold`. Returns how many files it could not read. */
  private async foldWindow(fold: UsageFold, startMs: number): Promise<number> {
    let unreadable = 0;
    const candidates = [...this.generations().reverse().map((g) => g.path), this.logPath];
    for (const path of candidates) {
      if (path !== this.logPath) {
        const info = statSafely(path);
        if (!info || info.mtimeMs < startMs) continue; // gone, or last written before the window: nothing in reach
      }
      let text: string;
      try {
        text = await readFile(path, 'utf8');
      } catch (err) {
        if ((err as NodeJS.ErrnoException).code === 'ENOENT' && path === this.logPath) continue; // no log yet
        unreadable += 1;
        continue;
      }
      for (const line of text.split('\n')) fold.add(line);
    }
    return unreadable;
  }


  /** What retention has removed and what it keeps, for the envelope. */
  retention(): UsageRetention {
    const ledger = this.stats.retention ?? {
      aged: { generations: 0, records: 0 },
      capped: { generations: 0, records: 0, from: null, to: null },
    };
    return {
      days: RETAIN_DAYS,
      capMegabytes: Math.round(this.policy.capBytes / 1024 / 1024),
      aged: ledger.aged,
      capped: ledger.capped,
    };
  }

  statFor(server: string): ServerStat | undefined {
    return this.stats.servers[server];
  }

  subscribe(fn: (r: UsageRecord) => void): () => void {
    this.subscribers.add(fn);
    return () => this.subscribers.delete(fn);
  }

  /**
   * Forget everything. `since` moves to now, which is what keeps "never used" honest
   * after a reset: a server with no calls since a reset an hour ago is not the same
   * claim as one with no calls since the router was installed, and the app shows the
   * window rather than an unqualified "never".
   */
  reset(): void {
    const next: StatsFile = { version: 1, since: new Date().toISOString(), servers: {} };
    const tmp = `${this.statsPath}.tmp-${process.pid}`;
    let phase: UsageResetError['phase'] = 'prepare';
    let removedFiles = 0;
    try {
      // Listing and staging must succeed before erasing anything. A swallowed directory-read
      // error could otherwise leave generations behind a successful reset response.
      const paths = [...this.generations(true).map(g => g.path), this.logPath];
      writeFileSync(tmp, JSON.stringify(next, null, 2));
      phase = 'delete';
      for (const path of paths) {
        try {
          rmSync(path);
          removedFiles += 1;
        } catch (err) {
          if ((err as NodeJS.ErrnoException).code !== 'ENOENT') throw err;
        }
      }
      phase = 'commit';
      renameSync(tmp, this.statsPath);
    } catch (err) {
      try { rmSync(tmp, { force: true }); } catch { /* retain the original refusal */ }
      // Deletion is not a transaction: keep the old aggregate/window until its replacement
      // commits, but stop displaying erased records in the recent active-log view.
      if (removedFiles > 0) this.ring = this.readTail();
      throw new UsageResetError(phase, removedFiles, err);
    }
    this.stats = next;
    this.ring = [];
    this.dirty = false;
    if (this.flushTimer) clearTimeout(this.flushTimer);
    this.flushTimer = undefined;
    log.info('usage history reset');
  }

  /** Drop one server's aggregate — called when a server is removed. */
  forget(server: string): void {
    delete this.stats.servers[server];
    this.ring = this.ring.filter((r) => r.server !== server);
    this.dirty = true;
    this.flush();
  }
}

export const projectOf = (cwd: string | undefined): string | undefined =>
  cwd ? basename(cwd) : undefined;

/** The name given to calls whose peer process could not be identified. A real category, not a leftover bucket. */
export const UNATTRIBUTED = 'unattributed';

/** What the call log says about the last `windowHours` hours. Ported from UsageInsights.swift. */
export interface UsageWindow {
  windowHours: number;
  windowStart: string;
  totalCalls: number;
  failedCalls: number;
  /** Calls per peer process name. A process name identifies a process, not a harness. */
  callers: ReadonlyMap<string, number>;
  /**
   * Exactly `windowHours` buckets, oldest first. **`calls` is null for an hour the router did not observe in full**: one
   * that began before it started counting, or one that holds a record the size cap removed. A zero there would be a
   * quiet hour the router never saw.
   */
  hours: Array<{ start: string; calls: number | null }>;
  /** The oldest record inside the window, or null when the window holds none. */
  horizon: string | null;
  /** Lines the reader could not use. A count of what parsed is not a count of what was there. */
  unreadableLines: number;
  /** When the router began counting calls. Nothing before it is observed, whatever the log holds. */
  observedSince: string;
  /**
   * Whether every hour of the window was observed. False when observation began inside it, when the size cap removed
   * history from it, or when a file holding it could not be read. A window that is false is not a whole window.
   */
  complete: boolean;
}

/** What the reader needs to know about the history beyond the lines in it. */
export interface UsageCoverage {
  /** The first moment the router was counting, from the aggregate's `since`. */
  observedSince: string;
  /** The newest record the size cap removed, or null when it has removed none. */
  cappedThrough: string | null;
}

const HOUR_KEY = /^\d{4}-\d{2}-\d{2}T\d{2}/;

const isoAt = (ms: number): string => new Date(ms).toISOString();

/** The first instant of the window: the top of the hour `windowHours - 1` back, so every bucket is a whole hour. */
export function windowStartMs(nowMs: number, windowHours: number): number {
  const currentHour = Math.floor(nowMs / HOUR_MS) * HOUR_MS;
  return currentHour - Math.max(0, windowHours - 1) * HOUR_MS;
}

/**
 * Fold a log into the window ending at `nowMs`.
 *
 * Time is compared as text, deliberately: every timestamp the router writes is `toISOString()`, which is fixed
 * width, UTC and zero-padded, so it sorts in the order it happened. A timestamp in any other shape is counted
 * as unreadable rather than bucketed by whatever characters it starts with.
 */
export function usageWindow(
  lines: Iterable<string>,
  nowMs: number,
  windowHours: number,
  coverage: UsageCoverage
): UsageWindow {
  const fold = new UsageFold(nowMs, windowHours, coverage);
  for (const line of lines) fold.add(line);
  return fold.result(0);
}

/**
 * The window as a fold over lines, so the reader can feed it one generation at a time and never hold the whole history
 * in memory. Buckets are found by hour key, so a record costs one map read rather than a scan of the window.
 */
class UsageFold {
  private readonly startMs: number;
  private readonly windowStart: string;
  private readonly buckets: Array<{ start: string; calls: number }> = [];
  private readonly byHour = new Map<string, { start: string; calls: number }>();
  private total = 0;
  private failed = 0;
  private unreadable = 0;
  private horizon: string | null = null;
  private readonly callers = new Map<string, number>();

  constructor(
    nowMs: number,
    private readonly windowHours: number,
    private readonly coverage: UsageCoverage
  ) {
    // The window starts at the top of the hour `windowHours - 1` back, so every bucket is a whole hour and the last one is
    // the hour in progress. A window that started at "now minus 24h" to the millisecond would make its end buckets partial,
    // and a chart with short end columns reads as a fall in traffic.
    this.startMs = windowStartMs(nowMs, windowHours);
    this.windowStart = isoAt(this.startMs);
    for (let i = 0; i < Math.max(0, windowHours); i++) {
      const bucket = { start: isoAt(this.startMs + i * HOUR_MS), calls: 0 };
      this.buckets.push(bucket);
      this.byHour.set(bucket.start.slice(0, 13), bucket);
    }
  }

  add(line: string): void {
    if (!line) return;
    const record = parseRecord(line);
    const key = record ? HOUR_KEY.exec(record.ts)?.[0] : undefined;
    if (!record || !key) {
      this.unreadable += 1;
      return;
    }
    if (record.ts < this.windowStart) return;

    this.total += 1;
    if (!record.ok) this.failed += 1;
    if (this.horizon === null || record.ts < this.horizon) this.horizon = record.ts;
    // A record stamped after the hour in progress is counted in the total but has no bucket to fall into.
    const bucket = this.byHour.get(key);
    if (bucket) bucket.calls += 1;

    const name = record.client || UNATTRIBUTED;
    this.callers.set(name, (this.callers.get(name) ?? 0) + 1);
  }

  /** An hour is observed in full when it began after the router started counting and after anything the cap removed. */
  private observed(hourStart: string): boolean {
    if (hourStart < this.coverage.observedSince) return false;
    return this.coverage.cappedThrough === null || hourStart > this.coverage.cappedThrough;
  }

  result(unreadableFiles: number): UsageWindow {
    const cappedClear = this.coverage.cappedThrough === null || this.coverage.cappedThrough < this.windowStart;
    return {
      windowHours: this.windowHours,
      windowStart: this.windowStart,
      totalCalls: this.total,
      failedCalls: this.failed,
      callers: this.callers,
      hours: this.buckets.map((b) => ({ start: b.start, calls: this.observed(b.start) ? b.calls : null })),
      horizon: this.horizon,
      unreadableLines: this.unreadable,
      observedSince: this.coverage.observedSince,
      complete: this.coverage.observedSince <= this.windowStart && cappedClear && unreadableFiles === 0,
    };
  }
}

/** Stat a path, or undefined when it is not there. Rotation and retention both move files, so absence is an answer. */
function statSafely(path: string): { size: number; mtimeMs: number } | undefined {
  try {
    const s = statSync(path);
    return { size: s.size, mtimeMs: s.mtimeMs };
  } catch {
    return undefined;
  }
}

/** One log line, if it carries the three fields a record cannot exist without. `ok` defaults to false, as the reference reads it. */
function parseRecord(line: string): { ts: string; ok: boolean; client?: string } | undefined {
  let value: unknown;
  try {
    value = JSON.parse(line);
  } catch {
    return undefined;
  }
  if (typeof value !== 'object' || value === null) return undefined;
  const r = value as Record<string, unknown>;
  if (typeof r.ts !== 'string' || typeof r.server !== 'string' || typeof r.tool !== 'string') return undefined;
  return { ts: r.ts, ok: r.ok === true, client: typeof r.client === 'string' ? r.client : undefined };
}
