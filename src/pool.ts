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
      entry = {};
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
    return { client, transport, startedAt: t0, lastUsedAt: Date.now(), calls: 0 };
  }

  /** Reset the idle clock. Called on every use, so a busy server stays warm. */
  private touch(serverName: string, entry: PoolEntry): void {
    if (entry.handle) {
      entry.handle.lastUsedAt = Date.now();
      entry.handle.calls += 1;
    }
    if (entry.reapTimer) clearTimeout(entry.reapTimer);

    const idleMs = this.upstreams.get(serverName)?.idleMs ?? this.defaultIdleMs;
    if (idleMs <= 0) return; // 0 disables reaping for this server

    entry.reapTimer = setTimeout(() => {
      void this.reap(serverName);
    }, idleMs);
    entry.reapTimer.unref();
  }

  private async reap(serverName: string): Promise<void> {
    const entry = this.entries.get(serverName);
    if (!entry?.handle) return;

    const { handle } = entry;
    entry.handle = undefined;
    entry.reapTimer = undefined;

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
    await Promise.all(names.map((n) => this.reap(n)));
  }
}
