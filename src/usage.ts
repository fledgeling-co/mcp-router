import { appendFileSync, mkdirSync, readFileSync, writeFileSync, renameSync, existsSync, statSync, rmSync } from 'node:fs';
import { dirname, basename } from 'node:path';
import { execFile } from 'node:child_process';
import type { Socket } from 'node:net';
import { log } from './log.js';

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

function run(cmd: string, args: string[], timeoutMs = 2000): Promise<string> {
  return new Promise((resolve) => {
    execFile(cmd, args, { timeout: timeoutMs, maxBuffer: 1024 * 1024 }, (err, stdout) => {
      resolve(err ? '' : stdout);
    });
  });
}

/**
 * Work out which process is on the other end of a loopback connection.
 *
 * The MCP protocol carries nothing that identifies a session: `clientInfo` says
 * "claude-code" for every window on the machine, and this router is deliberately
 * stateless so there is no session id either. The socket, though, is a real object
 * with a real peer, and on macOS `lsof` will name the process holding it. That is
 * what turns "something called browser_navigate" into "the session working in
 * ~/Dev/mcp-router called browser_navigate", which is the question the app exists
 * to answer.
 *
 * Cost is paid once per connection, not per call, and every failure path returns
 * an empty identity: an unattributed record is worth far more than a dropped one.
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
    // `-i :port` matches either end of the connection, so this returns both the
    // client and this router. The one that is not us is the caller.
    const out = await run('/usr/sbin/lsof', ['-nP', `-iTCP:${peerPort}`, '-sTCP:ESTABLISHED', '-Fpc']);
    if (!out) return UNKNOWN;

    let pid: number | undefined;
    let client: string | undefined;
    let currentPid: number | undefined;
    for (const line of out.split('\n')) {
      if (line.startsWith('p')) {
        currentPid = Number(line.slice(1));
      } else if (line.startsWith('c') && currentPid && currentPid !== process.pid) {
        pid = currentPid;
        client = line.slice(1);
        break;
      }
    }
    if (!pid) return UNKNOWN;

    const known = this.byPid.get(pid);
    if (known) return known;

    const cwdOut = await run('/usr/sbin/lsof', ['-a', '-p', String(pid), '-d', 'cwd', '-Fn']);
    const cwd = cwdOut
      .split('\n')
      .find((l) => l.startsWith('n'))
      ?.slice(1);

    const identity: ClientIdentity = { pid, client, cwd: cwd || undefined };
    // A pid is reused eventually, but not within one router lifetime in any
    // realistic case, and the cost of being wrong is a mislabelled log line.
    this.byPid.set(pid, identity);
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
