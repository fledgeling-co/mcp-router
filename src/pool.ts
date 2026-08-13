import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { SSEClientTransport } from '@modelcontextprotocol/sdk/client/sse.js';
import { UnauthorizedError } from '@modelcontextprotocol/sdk/client/auth.js';
import type { Transport } from '@modelcontextprotocol/sdk/shared/transport.js';
import { isStdio, type UpstreamConfig, type HttpUpstream, type StdioUpstream } from './config.js';
import { FileOAuthProvider } from './auth.js';
import { log } from './log.js';

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
  url: string;
  at: string;
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

  /** Environment for a child: the router's own env, then the server's overrides. */
  private buildEnv(u: StdioUpstream): Record<string, string> {
    const env: Record<string, string> = {};
    for (const [k, v] of Object.entries(process.env)) {
      if (typeof v === 'string') env[k] = v;
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
    if (u?.warm) return;

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
    const warm = [...this.upstreams.values()].filter((u) => u.warm);
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
