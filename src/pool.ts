import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import type { UpstreamConfig } from './config.js';
import { log } from './log.js';

export interface ChildHandle {
  client: Client;
  transport: StdioClientTransport;
  startedAt: number;
  lastUsedAt: number;
  calls: number;
}

interface PoolEntry {
  handle?: ChildHandle;
  /** Single-flight: concurrent callers await the same spawn rather than racing two children. */
  starting?: Promise<ChildHandle>;
  reapTimer?: NodeJS.Timeout;
  /** Calls currently awaiting a response on this child. Never reap above zero. */
  inFlight: number;
}

/**
 * Owns the lifecycle of every stdio upstream: nothing is spawned until a tool on
 * that server is actually called, and each child is closed again once it has been
 * idle past its window. This is the whole point of the router — a session that
 * never touches a server never pays for it.
 */
export class ChildPool {
  private entries = new Map<string, PoolEntry>();
  private shuttingDown = false;

  constructor(
    private upstreams: Map<string, UpstreamConfig>,
    private defaultIdleMs: number,
    private startupTimeoutMs: number
  ) {}

  /** Environment for a child: the router's own env, then the server's overrides. */
  private buildEnv(u: UpstreamConfig): Record<string, string> {
    const env: Record<string, string> = {};
    for (const [k, v] of Object.entries(process.env)) {
      if (typeof v === 'string') env[k] = v;
    }
    return { ...env, ...u.env };
  }

  async acquire(serverName: string): Promise<ChildHandle> {
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

    entry.starting = this.spawn(u)
      .then((handle) => {
        const e = this.entries.get(serverName);
        if (e) {
          e.handle = handle;
          e.starting = undefined;
          this.touch(serverName, e);
        }
        return handle;
      })
      .catch((err) => {
        const e = this.entries.get(serverName);
        if (e) e.starting = undefined;
        throw err;
      });

    return entry.starting;
  }

  private async spawn(u: UpstreamConfig): Promise<ChildHandle> {
    const t0 = Date.now();
    log.info(`spawning upstream "${u.name}" (${u.command} ${u.args.join(' ')})`.slice(0, 200));

    const transport = new StdioClientTransport({
      command: u.command,
      args: u.args,
      env: this.buildEnv(u),
      cwd: u.cwd,
      stderr: 'pipe',
    });

    const client = new Client(
      { name: 'mcp-router', version: '0.1.0' },
      { capabilities: {} }
    );

    // Drain the child's stderr so a chatty server cannot fill its pipe buffer and wedge.
    transport.stderr?.on('data', (chunk: Buffer) => {
      const text = chunk.toString().trim();
      if (text) log.debug(`[${u.name}] ${text.slice(0, 400)}`);
    });

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
      // A failed spawn must not leave a half-open child behind.
      try {
        await transport.close();
      } catch {
        /* already dead */
      }
      throw err;
    } finally {
      if (timer) clearTimeout(timer);
    }

    log.info(`upstream "${u.name}" ready in ${Date.now() - t0}ms`);

    /*
     * A child that exits on its own — crash, its own idle timeout, a killed
     * process — leaves an entry whose client is dead. Without this the pool keeps
     * handing that client out and every call to the server fails until the idle
     * timer happens to fire, which is up to idleMs of hard failures for a server
     * that would work if it were simply respawned. Evicting on close means the
     * next call spawns a fresh one.
     */
    transport.onclose = () => {
      const e = this.entries.get(u.name);
      if (!e?.handle || e.handle.transport !== transport) return; // already reaped
      log.warn(`upstream "${u.name}" exited on its own; evicting so the next call respawns it`);
      if (e.reapTimer) clearTimeout(e.reapTimer);
      e.reapTimer = undefined;
      e.handle = undefined;
      e.inFlight = 0;
    };

    return { client, transport, startedAt: t0, lastUsedAt: Date.now(), calls: 0 };
  }

  /**
   * Run one tool call, holding the child open for as long as it takes.
   *
   * The idle timer is armed when a child is acquired, not when its work finishes,
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

  /** Reset the idle clock. Called on every use, so a busy server stays warm. */
  private touch(serverName: string, entry: PoolEntry): void {
    if (entry.handle) {
      entry.handle.lastUsedAt = Date.now();
      entry.handle.calls += 1;
    }
    this.armReap(serverName, entry);
  }

  /** (Re)start the idle countdown. A child with work outstanding is never armed. */
  private armReap(serverName: string, entry: PoolEntry): void {
    if (entry.reapTimer) clearTimeout(entry.reapTimer);
    entry.reapTimer = undefined;
    if (entry.inFlight > 0) return;

    const idleMs = this.upstreams.get(serverName)?.idleMs ?? this.defaultIdleMs;
    if (idleMs <= 0) return; // 0 disables reaping for this server

    entry.reapTimer = setTimeout(() => {
      void this.reap(serverName);
    }, idleMs);
    entry.reapTimer.unref();
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
    log.info(
      `reaping idle upstream "${serverName}" after ${handle.calls} call(s), ${Math.round(aliveMs / 1000)}s alive`
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

  status(): Array<{ name: string; state: string; calls: number; idleSec: number }> {
    const out: Array<{ name: string; state: string; calls: number; idleSec: number }> = [];
    for (const name of this.upstreams.keys()) {
      const e = this.entries.get(name);
      if (e?.handle) {
        out.push({
          name,
          state: 'running',
          calls: e.handle.calls,
          idleSec: Math.round((Date.now() - e.handle.lastUsedAt) / 1000),
        });
      } else if (e?.starting) {
        out.push({ name, state: 'starting', calls: 0, idleSec: 0 });
      } else {
        out.push({ name, state: 'idle', calls: 0, idleSec: 0 });
      }
    }
    return out;
  }

  async shutdown(): Promise<void> {
    this.shuttingDown = true;
    const names = [...this.entries.keys()];

    /*
     * Await any spawn still in flight before reaping. reap() returns immediately
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
          /* the spawn failed, so there is nothing to close */
        }
      })
    );

    await Promise.all(names.map((n) => this.reap(n, true)));
  }
}
