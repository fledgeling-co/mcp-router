import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { SSEClientTransport } from '@modelcontextprotocol/sdk/client/sse.js';
import { UnauthorizedError } from '@modelcontextprotocol/sdk/client/auth.js';
import type { Transport } from '@modelcontextprotocol/sdk/shared/transport.js';
import { isStdio, type UpstreamConfig, type HttpUpstream, type StdioUpstream } from './config.js';
import { FileOAuthProvider, isAuthFailure } from './auth.js';
import { log } from './log.js';
import { readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

/**
 * The most directories PATH discovery will add. A home with thousands of dot-directories would
 * otherwise build an environment long enough to matter to execve.
 */
const CHILD_PATH_DISCOVERY_LIMIT = 64;

/**
 * Every `bin` directory under $HOME or one of its dot-directories, sorted and capped.
 *
 * Launchd hands the router a fixed PATH and every child inherits it, so a routed server that
 * shells out to a CLI installed under the user's home cannot find it and reports the capability
 * unavailable instead of failing. R6, and `planning/specs/spec-R6.md` §2 carries why this is a
 * directory scan rather than `$SHELL -l -c 'echo $PATH'`.
 *
 * Sorted so this router and the Swift one produce one string from one home.
 */
function userBinDirectories(home: string): string[] {
  const candidates = [join(home, 'bin')];
  let entries: string[] = [];
  try {
    entries = readdirSync(home);
  } catch {
    // An unreadable $HOME yields a PATH, not an error.
  }
  for (const entry of entries) {
    if (!entry.startsWith('.') || entry === '.' || entry === '..') continue;
    candidates.push(join(home, entry, 'bin'));
  }
  const found = new Set<string>();
  for (const candidate of candidates) {
    try {
      if (statSync(candidate).isDirectory()) found.add(candidate);
    } catch {
      // Absent or unreadable: not a directory, so not a PATH entry.
    }
  }
  // Sorted by UTF-8 bytes rather than by the default `Array.sort`, which compares UTF-16 code
  // units. Swift compares Strings by Unicode canonical equivalence and the two orderings disagree
  // above the BMP, so a home holding an emoji-named directory and one named U+E000 would order
  // differently in the two routers — and at the cap boundary they would select different
  // directories. Byte order is the one comparison both can express.
  return [...found]
    .sort((a, b) => Buffer.compare(Buffer.from(a, 'utf8'), Buffer.from(b, 'utf8')))
    .slice(0, CHILD_PATH_DISCOVERY_LIMIT);
}

/**
 * Discovery, once per process per home.
 *
 * `buildEnv` runs on every spawn and every filesystem call here is synchronous, so an uncached
 * scan blocks the event loop that is also serving every other upstream. Once per router start is
 * also what `spec-R6.md` claims: a tool installed afterwards is found at the next restart, and the
 * watcher restarts this process on every adoption.
 */
const discoveryCache = new Map<string, string[]>();

function cachedUserBinDirectories(home: string): string[] {
  const cached = discoveryCache.get(home);
  if (cached !== undefined) return cached;
  const found = userBinDirectories(home);
  discoveryCache.set(home, found);
  return found;
}

/**
 * The inherited PATH with the user's own tool directories appended.
 *
 * Append, never prepend: the inherited entries keep their order and their place at the front, so
 * no command that resolved before can resolve to a different binary after. Prepending would let a
 * version manager under $HOME capture `node` and `npx` for every child, and the measured defect is
 * a missing binary rather than a wrong one.
 */
export function augmentPath(inherited: string, home: string): string {
  // Empty components are KEPT. execvp reads an empty entry as the current directory, so dropping
  // one from an inherited `:/usr/bin` would change where a child looks — and this function's whole
  // contract is that the inherited PATH survives unaltered.
  const merged = inherited === '' ? [] : inherited.split(':');
  const seen = new Set(merged);
  for (const directory of cachedUserBinDirectories(home)) {
    if (seen.has(directory)) continue;
    seen.add(directory);
    merged.push(directory);
  }
  return merged.join(':');
}

export interface UpstreamHandle {
  client: Client;
  transport: Transport;
  startedAt: number;
  lastUsedAt: number;
  calls: number;
}

interface PoolEntry {
  handle?: UpstreamHandle;
  /** Single-flight: concurrent callers await the same connect rather than racing two. */
  starting?: Promise<UpstreamHandle>;
  reapTimer?: NodeJS.Timeout;
  /** Calls currently awaiting a response on this upstream. Never reap above zero. */
  inFlight: number;
}

/** An HTTP upstream that answered 401 and wants the user to authorize in a browser. */
export interface PendingAuth {
  server: string;
  /**
   * The browser URL to complete the flow, when there is one.
   *
   * Optional since 2026-08-20: an upstream that rejects a REFRESH never reaches the
   * redirect callback, so there is no URL to offer and the server still needs
   * authorizing. Making this required is what forced the index path to record
   * nothing at all, which is how a dead credential came to read as `idle`.
   */
  url?: string;
  at: string;
  /** The failure text, when the pending state came from a rejection rather than a redirect. */
  reason?: string;
}

/**
 * Owns the lifecycle of every upstream.
 *
 * For stdio that is the whole point of the router: nothing is spawned until a tool
 * on that server is actually called, and each child is closed again once it has been
 * idle past its window, so a session that never touches a server never pays for it.
 *
 * For HTTP there is no process to save — that transport already multiplexes. What
 * pooling buys there is the connection itself: one initialize handshake and one
 * OAuth token exchange serve every session, instead of one per window.
 */
export class UpstreamPool {
  private entries = new Map<string, PoolEntry>();
  private shuttingDown = false;
  private pendingAuth = new Map<string, PendingAuth>();

  constructor(
    private upstreams: Map<string, UpstreamConfig>,
    private defaultIdleMs: number,
    private startupTimeoutMs: number
  ) {}

  /**
   * Environment for a child: the router's own env with PATH augmented, then the server's
   * overrides.
   *
   * The server's own `env` still merges last, so a server that sets PATH wins outright — that
   * override is R6's escape hatch for a prefix the discovery below does not find.
   */
  private buildEnv(u: StdioUpstream): Record<string, string> {
    const env: Record<string, string> = {};
    for (const [k, v] of Object.entries(process.env)) {
      if (typeof v === 'string') env[k] = v;
    }
    if (typeof env.HOME === 'string' && env.HOME !== '') {
      env.PATH = augmentPath(env.PATH ?? '', env.HOME);
    }
    return { ...env, ...u.env };
  }

  /** Servers currently waiting on a browser authorization, for `/servers` to report. */
  pending(): PendingAuth[] {
    return [...this.pendingAuth.values()];
  }

  clearPending(server: string): void {
    this.pendingAuth.delete(server);
  }

  /**
   * Record that an upstream refused our credentials, from a path with no browser URL.
   *
   * The redirect callback in `makeTransport` is the only thing that used to populate
   * this map, and it fires only when the SDK decides to START an authorization flow.
   * A server that rejects a refresh token answers the NEXT call with an error and no
   * redirect, so the map stayed empty while the upstream served nothing. `status`
   * already knows how to print `! <name> needs authorizing`, the app already badges
   * it, and `/servers` already reports it — none of them fired, because nothing put
   * the server in here.
   *
   * A redirect that arrives later overwrites this with the real URL; this never
   * overwrites one, so a usable URL is not lost to a subsequent failure.
   */
  /**
   * Take on a pending state another pool observed, without logging it again.
   *
   * `indexOne` re-indexes on a scratch pool so a re-index cannot disturb the serving
   * pool's connections. That pool is the one that SEES the rejection and it is shut down
   * moments later, so what it learned has to be handed over. Silent, because the pool that
   * observed it has already written the line — two identical warnings for one refusal is
   * the same defect as none, read from the other side.
   */
  adoptPending(entry: PendingAuth): void {
    const existing = this.pendingAuth.get(entry.server);
    if (existing?.url) return;
    this.pendingAuth.set(entry.server, entry);
  }

  noteAuthFailure(server: string, reason: string): void {
    const existing = this.pendingAuth.get(server);
    if (existing?.url) return;
    this.pendingAuth.set(server, { server, at: new Date().toISOString(), reason });
    log.warn(
      `upstream "${server}" refused our credentials (${reason.slice(0, 120)}) — ` +
        `run \`mcp-router auth ${server}\``
    );
  }

  async acquire(serverName: string): Promise<UpstreamHandle> {
    if (this.shuttingDown) throw new Error('router is shutting down');

    const u = this.upstreams.get(serverName);
    if (!u) throw new Error(`unknown upstream server "${serverName}"`);

    let entry = this.entries.get(serverName);
    if (!entry) {
      entry = { inFlight: 0 };
      this.entries.set(serverName, entry);
    }

    if (entry.handle) {
      this.touch(serverName, entry);
      return entry.handle;
    }
    if (entry.starting) return entry.starting;

    entry.starting = this.open(u)
      .then((handle) => {
        const e = this.entries.get(serverName);
        if (e) {
          e.handle = handle;
          e.starting = undefined;
          this.touch(serverName, e);
        }
        this.pendingAuth.delete(serverName);
        return handle;
      })
      .catch((err) => {
        const e = this.entries.get(serverName);
        if (e) e.starting = undefined;
        throw err;
      });

    return entry.starting;
  }

  /** Build the transport for one upstream. stdio spawns a process; http/sse do not. */
  private makeTransport(u: UpstreamConfig): Transport {
    if (isStdio(u)) {
      const t = new StdioClientTransport({
        command: u.command,
        args: u.args,
        env: this.buildEnv(u),
        cwd: u.cwd,
        stderr: 'pipe',
      });
      // Drain the child's stderr so a chatty server cannot fill its pipe buffer and wedge.
      t.stderr?.on('data', (chunk: Buffer) => {
        const text = chunk.toString().trim();
        if (text) log.debug(`[${u.name}] ${text.slice(0, 400)}`);
      });
      return t;
    }

    const http = u as HttpUpstream;
    /*
     * `serve` runs under launchd with no user attached, so it cannot open a browser
     * and must not try. It records the authorization URL instead; `/servers` reports
     * it and `mcp-router auth <name>` — or the app — is what actually completes the
     * flow. The alternative, silently failing every call on a server whose token
     * expired, is the one behaviour there is no way to diagnose from the outside.
     */
    const authProvider =
      http.oauth === false
        ? undefined
        : new FileOAuthProvider(u.name, (url) => {
            this.pendingAuth.set(u.name, {
              server: u.name,
              url: url.toString(),
              at: new Date().toISOString(),
            });
            log.warn(`upstream "${u.name}" needs authorization — run \`mcp-router auth ${u.name}\``);
          });

    const opts = {
      authProvider,
      requestInit: Object.keys(http.headers).length ? { headers: http.headers } : undefined,
    };
    return http.transport === 'sse'
      ? new SSEClientTransport(new URL(http.url), opts)
      : new StreamableHTTPClientTransport(new URL(http.url), opts);
  }

  private async open(u: UpstreamConfig): Promise<UpstreamHandle> {
    const t0 = Date.now();
    log.info(
      isStdio(u)
        ? `spawning upstream "${u.name}" (${u.command} ${u.args.join(' ')})`.slice(0, 200)
        : `connecting upstream "${u.name}" (${u.transport} ${u.url})`.slice(0, 200)
    );

    const transport = this.makeTransport(u);
    const client = new Client({ name: 'mcp-router', version: '0.1.0' }, { capabilities: {} });

    const timeoutMs = u.startupTimeoutMs ?? this.startupTimeoutMs;
    let timer: NodeJS.Timeout | undefined;
    try {
      await Promise.race([
        client.connect(transport),
        new Promise<never>((_, reject) => {
          timer = setTimeout(
            () => reject(new Error(`upstream "${u.name}" did not initialize within ${timeoutMs}ms`)),
            timeoutMs
          );
        }),
      ]);
    } catch (err) {
      // A failed connect must not leave a half-open child or socket behind.
      try {
        await transport.close();
      } catch {
        /* already dead */
      }
      const message = (err as Error).message ?? String(err);
      if (err instanceof UnauthorizedError || isAuthFailure(message)) {
        // Recorded, not just rethrown: the thrown message reaches whoever called, and
        // the caller here is usually the indexer, which writes it into the manifest and
        // moves on. Nothing downstream of that reads it as "needs authorizing".
        this.noteAuthFailure(u.name, err instanceof UnauthorizedError ? 'unauthorized' : message);
      }
      if (err instanceof UnauthorizedError) {
        throw new Error(
          `upstream "${u.name}" is not authorized. Run \`mcp-router auth ${u.name}\` to sign in.`
        );
      }
      throw err;
    } finally {
      if (timer) clearTimeout(timer);
    }

    log.info(`upstream "${u.name}" ready in ${Date.now() - t0}ms`);

    /*
     * An upstream that goes away on its own — a crashed child, its own idle timeout,
     * a dropped HTTP session — leaves an entry whose client is dead. Without this the
     * pool keeps handing that client out and every call fails until the idle timer
     * happens to fire, which is up to idleMs of hard failures for a server that would
     * work if it were simply reconnected. Evicting on close means the next call opens
     * a fresh one.
     */
    transport.onclose = () => {
      const e = this.entries.get(u.name);
      if (!e?.handle || e.handle.transport !== transport) return; // already reaped
      log.warn(`upstream "${u.name}" closed on its own; evicting so the next call reopens it`);
      if (e.reapTimer) clearTimeout(e.reapTimer);
      e.reapTimer = undefined;
      e.handle = undefined;
      e.inFlight = 0;
    };

    return { client, transport, startedAt: t0, lastUsedAt: Date.now(), calls: 0 };
  }

  /**
   * Run one tool call, holding the upstream open for as long as it takes.
   *
   * The idle timer is armed when an upstream is acquired, not when its work finishes,
   * so without this accounting a call that runs longer than idleMs (5 minutes by
   * default) has its own child closed underneath it and fails. That is not
   * hypothetical: a Deep Research run is documented at 4 to 60 minutes, and a
   * sandboxed agent call takes a timeout up to 900 seconds. Every one of those
   * would have died at the five-minute mark.
   */
  async call(
    serverName: string,
    params: Parameters<Client['callTool']>[0]
  ): Promise<Awaited<ReturnType<Client['callTool']>>> {
    const handle = await this.acquire(serverName);

    const entry = this.entries.get(serverName);
    if (entry) {
      entry.inFlight += 1;
      if (entry.reapTimer) clearTimeout(entry.reapTimer);
      entry.reapTimer = undefined;
    }

    try {
      return await handle.client.callTool(params);
    } finally {
      const e = this.entries.get(serverName);
      if (e) {
        e.inFlight = Math.max(0, e.inFlight - 1);
        // Re-arm from completion, so the idle window measures time since the last
        // call ended rather than since it started.
        if (e.inFlight === 0 && e.handle) this.armReap(serverName, e);
      }
    }
  }

  /** True when this upstream is live right now — used to label a call as a cold start. */
  isLive(serverName: string): boolean {
    return !!this.entries.get(serverName)?.handle;
  }

  /** Reset the idle clock. Called on every use, so a busy server stays warm. */
  private touch(serverName: string, entry: PoolEntry): void {
    if (entry.handle) {
      entry.handle.lastUsedAt = Date.now();
      entry.handle.calls += 1;
    }
    this.armReap(serverName, entry);
  }

  /** (Re)start the idle countdown. An upstream with work outstanding is never armed. */
  private armReap(serverName: string, entry: PoolEntry): void {
    if (entry.reapTimer) clearTimeout(entry.reapTimer);
    entry.reapTimer = undefined;
    if (entry.inFlight > 0) return;

    const u = this.upstreams.get(serverName);
    // A warm server is one the user has committed to paying for. Reaping it would
    // undo the only thing it was kept open to buy.
    // A DISABLED server is reaped even when it is warm, and this is the one place the
    // two settings meet. `warm` says "keep paying for this"; `disabled` says "this
    // serves nobody". Without the second term a warm server, once disabled, keeps a
    // resident child process forever with no route to it — the opposite of what the
    // switch is for.
    if (u?.warm && !u.disabled) return;

    const idleMs = u?.idleMs ?? this.defaultIdleMs;
    if (idleMs <= 0) return; // 0 disables reaping for this server

    entry.reapTimer = setTimeout(() => {
      void this.reap(serverName);
    }, idleMs);
    entry.reapTimer.unref();
  }

  /**
   * Open every server marked warm.
   *
   * Failures are logged and swallowed: a warm server that will not start is a
   * problem to report, never a reason the router does not come up.
   */
  async warmUp(): Promise<void> {
    const warm = [...this.upstreams.values()].filter((u) => u.warm && !u.disabled);
    if (!warm.length) return;
    log.info(`pre-opening ${warm.length} warm upstream(s): ${warm.map((u) => u.name).join(', ')}`);
    await Promise.all(
      warm.map((u) =>
        this.acquire(u.name).catch((err: Error) =>
          log.warn(`warm upstream "${u.name}" did not start: ${err.message}`)
        )
      )
    );
  }

  /**
   * Resident size of each live stdio child, in MB.
   *
   * One `ps` for every pid rather than one per server: the warm set is a budget the
   * user sets in memory, so the number behind it has to be measured. HTTP upstreams
   * have no local process and are reported as 0 rather than guessed at.
   */
  async residentMb(): Promise<Record<string, number>> {
    const pids: Array<[string, number]> = [];
    for (const [name, entry] of this.entries) {
      const pid = (entry.handle?.transport as { pid?: number } | undefined)?.pid;
      if (pid) pids.push([name, pid]);
    }
    if (!pids.length) return {};
    const { execFile } = await import('node:child_process');
    const out = await new Promise<string>((resolve) => {
      execFile(
        '/bin/ps',
        ['-o', 'pid=,rss=', '-p', pids.map(([, p]) => p).join(',')],
        { timeout: 2000 },
        (err, stdout) => resolve(err ? '' : stdout)
      );
    });
    const rssByPid = new Map<number, number>();
    for (const line of out.trim().split('\n')) {
      const [pid, rss] = line.trim().split(/\s+/).map(Number);
      if (pid && rss) rssByPid.set(pid, Math.round(rss / 1024));
    }
    return Object.fromEntries(pids.map(([name, pid]) => [name, rssByPid.get(pid) ?? 0]));
  }

  private async reap(serverName: string, force = false): Promise<void> {
    const entry = this.entries.get(serverName);
    if (!entry?.handle) return;
    // Belt and braces: armReap already refuses to schedule above zero. Shutdown
    // forces, because leaving a child open there is the orphan this avoids.
    if (!force && entry.inFlight > 0) return;

    const { handle } = entry;
    entry.handle = undefined;
    entry.reapTimer = undefined;
    // The close below fires transport.onclose; this keeps it from double-evicting.
    handle.transport.onclose = undefined;

    const aliveMs = Date.now() - handle.startedAt;
    const kind = isStdio(this.upstreams.get(serverName)!) ? 'child' : 'connection';
    log.info(
      `closing idle ${kind} "${serverName}" after ${handle.calls} call(s), ${Math.round(aliveMs / 1000)}s alive`
    );
    try {
      await handle.client.close();
    } catch {
      /* best effort */
    }
    try {
      await handle.transport.close();
    } catch {
      /* best effort */
    }
  }

  /**
   * A snapshot of every upstream's live state.
   *
   * `callsServed` and `inFlight` are different questions and were previously conflated:
   * the control API reported the lifetime counter under the name `liveCalls`, so an
   * idle server that had answered three calls an hour ago read as three calls in
   * flight. Only `inFlight` blocks the reaper, so only `inFlight` should ever be
   * presented as work outstanding.
   */
  status(): Array<{
    name: string;
    transport: string;
    state: string;
    callsServed: number;
    inFlight: number;
    idleSec: number;
  }> {
    const out: ReturnType<UpstreamPool['status']> = [];
    for (const [name, u] of this.upstreams) {
      const e = this.entries.get(name);
      const transport = u.transport;
      if (e?.handle) {
        out.push({
          name,
          transport,
          state: 'running',
          callsServed: e.handle.calls,
          inFlight: e.inFlight,
          idleSec: Math.round((Date.now() - e.handle.lastUsedAt) / 1000),
        });
      } else if (e?.starting) {
        out.push({ name, transport, state: 'starting', callsServed: 0, inFlight: e.inFlight, idleSec: 0 });
      } else {
        out.push({ name, transport, state: 'idle', callsServed: 0, inFlight: 0, idleSec: 0 });
      }
    }
    return out;
  }

  async shutdown(): Promise<void> {
    this.shuttingDown = true;
    const names = [...this.entries.keys()];

    /*
     * Await any connect still in flight before reaping. reap() returns immediately
     * when there is no handle yet, so a child being spawned as SIGTERM arrives
     * (launchd restarting the router on a config change, landing during a first
     * call) would finish starting after shutdown resolved and process.exit ran —
     * orphaned, with nothing left to close it. On this machine stdin EOF is not
     * reliable liveness for an stdio MCP server, so that orphan can persist.
     */
    await Promise.all(
      names.map(async (n) => {
        const e = this.entries.get(n);
        if (!e?.starting) return;
        try {
          await e.starting;
        } catch {
          /* the connect failed, so there is nothing to close */
        }
      })
    );

    await Promise.all(names.map((n) => this.reap(n, true)));
  }
}
