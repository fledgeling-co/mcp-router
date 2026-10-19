import { appendFileSync, mkdirSync, readFileSync, writeFileSync, renameSync, existsSync, statSync, rmSync } from 'node:fs';
import { dirname, basename } from 'node:path';
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
    private readonly statsPath: string
  ) {
    mkdirSync(dirname(logPath), { recursive: true });
    this.stats = this.readStats();
    this.ring = this.readTail();
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
      if (statSync(this.logPath).size < MAX_LOG_BYTES) return;
    } catch {
      return; // no file yet
    }
    // One generation kept. The aggregate is what makes history disposable.
    renameSync(this.logPath, `${this.logPath}.1`);
    log.info(`usage log rotated at ${MAX_LOG_BYTES} bytes`);
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
   * The window `GET /insights` answers over. Reads the current log only, as the reference does: the rotated
   * generation is not read, so the window is only as long as what survived, and `horizon` says how far back
   * it actually reaches. A log that does not exist yet is an empty window, which is a reading, not an error.
   */
  insights(nowMs: number, windowHours: number): UsageWindow {
    let text = '';
    try {
      text = readFileSync(this.logPath, 'utf8');
    } catch {
      /* no log yet */
    }
    return usageWindow(text.split('\n'), nowMs, windowHours);
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
    this.ring = [];
    this.stats = { version: 1, since: new Date().toISOString(), servers: {} };
    this.dirty = true;
    this.flush();
    for (const p of [this.logPath, `${this.logPath}.1`]) {
      try {
        if (existsSync(p)) rmSync(p);
      } catch (err) {
        log.warn(`could not remove ${p}: ${(err as Error).message}`);
      }
    }
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
  /** Exactly `windowHours` buckets, oldest first, including the empty ones. */
  hours: Array<{ start: string; calls: number }>;
  /** The oldest record inside the window, or null when the window holds none. */
  horizon: string | null;
  /** Lines the reader could not use. A count of what parsed is not a count of what was there. */
  unreadableLines: number;
}

const HOUR_MS = 3_600_000;
const HOUR_KEY = /^\d{4}-\d{2}-\d{2}T\d{2}/;

const isoAt = (ms: number): string => new Date(ms).toISOString();

/**
 * Fold a log into the window ending at `nowMs`.
 *
 * Time is compared as text, deliberately: every timestamp the router writes is `toISOString()`, which is fixed
 * width, UTC and zero-padded, so it sorts in the order it happened. A timestamp in any other shape is counted
 * as unreadable rather than bucketed by whatever characters it starts with.
 */
export function usageWindow(lines: Iterable<string>, nowMs: number, windowHours: number): UsageWindow {
  // The window starts at the top of the hour `windowHours - 1` back, so every bucket is a whole hour and the
  // last one is the hour in progress. A window that started at "now minus 24h" to the millisecond would make
  // its end buckets partial, and a chart with short end columns reads as a fall in traffic.
  const currentHour = Math.floor(nowMs / HOUR_MS) * HOUR_MS;
  const startMs = currentHour - Math.max(0, windowHours - 1) * HOUR_MS;
  const windowStart = isoAt(startMs);
  const buckets = Array.from({ length: Math.max(0, windowHours) }, (_, i) => {
    const start = isoAt(startMs + i * HOUR_MS);
    return { start, key: start.slice(0, 13), calls: 0 };
  });

  let total = 0;
  let failed = 0;
  let unreadable = 0;
  let horizon: string | null = null;
  const callers = new Map<string, number>();

  for (const line of lines) {
    if (!line) continue;
    const record = parseRecord(line);
    const key = record ? HOUR_KEY.exec(record.ts)?.[0] : undefined;
    if (!record || !key) {
      unreadable += 1;
      continue;
    }
    if (record.ts < windowStart) continue;

    total += 1;
    if (!record.ok) failed += 1;
    if (horizon === null || record.ts < horizon) horizon = record.ts;
    // A record stamped after the hour in progress is counted in the total but has no bucket to fall into.
    const bucket = buckets.find((b) => b.key === key);
    if (bucket) bucket.calls += 1;

    const name = record.client || UNATTRIBUTED;
    callers.set(name, (callers.get(name) ?? 0) + 1);
  }

  return {
    windowHours,
    windowStart,
    totalCalls: total,
    failedCalls: failed,
    callers,
    hours: buckets.map(({ start, calls }) => ({ start, calls })),
    horizon,
    unreadableLines: unreadable,
  };
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
