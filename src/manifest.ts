import { readFileSync, writeFileSync, renameSync, existsSync, mkdirSync, statSync } from 'node:fs';
import { dirname } from 'node:path';
import type { Tool } from '@modelcontextprotocol/sdk/types.js';
import type { UpstreamConfig } from './config.js';
import { upstreamHash } from './config.js';
import { ChildPool } from './pool.js';
import { log } from './log.js';

/** Separator between the server namespace and the upstream's own tool name. */
export const NS = '__';

export interface CachedServer {
  hash: string;
  builtAt: string;
  tools: Tool[];
  error?: string;
}

export interface Manifest {
  version: 1;
  servers: Record<string, CachedServer>;
}

/**
 * The manifest is what makes lazy spawning possible at all.
 *
 * A client needs the full tool list at `tools/list` time, and the only way to learn
 * an stdio server's tools is to start it and ask. Doing that per session is exactly
 * the cost this router exists to remove, so the list is built once, cached to disk,
 * and served from there. Children then start only when a tool is actually called.
 *
 * The cache is keyed on each server's command/args/env identity, so editing a
 * server's config invalidates just that entry.
 */
export function loadManifest(path: string): Manifest {
  if (!existsSync(path)) return { version: 1, servers: {} };
  try {
    return parseManifest(readFileSync(path, 'utf8'));
  } catch (err) {
    log.warn(`manifest at ${path} unreadable (${(err as Error).message}); rebuilding`);
    return { version: 1, servers: {} };
  }
}

/** Strict parse: throws rather than degrading to an empty manifest. */
function parseManifest(raw: string): Manifest {
  const m = JSON.parse(raw) as Manifest;
  if (m.version !== 1 || typeof m.servers !== 'object' || m.servers === null) {
    throw new Error('not a version-1 manifest object');
  }
  return m;
}

export function saveManifest(path: string, manifest: Manifest): void {
  mkdirSync(dirname(path), { recursive: true });
  // Temp + rename, so a reader can never observe a half-written manifest.
  const tmp = `${path}.tmp-${process.pid}`;
  writeFileSync(tmp, JSON.stringify(manifest, null, 2));
  renameSync(tmp, path);
}

/**
 * Serves the manifest to a long-lived `serve` process, re-reading it when the file
 * on disk changes.
 *
 * Without this, a re-index only took effect on the next restart: `serve` read the
 * manifest once and handed that object to the router forever. The check has to stay
 * cheap because it runs on every `tools/list` — so it is a `statSync`, and the JSON
 * is only re-parsed when mtime or size actually moved.
 *
 * A reload that throws keeps the previous manifest. A truncated or half-written file
 * must never empty the tool list, which is the failure a client would see as "all my
 * MCP tools vanished".
 */
export class ManifestStore {
  private manifest: Manifest;
  private stamp = '';
  private retryAfter = 0;

  constructor(private readonly path: string) {
    this.manifest = loadManifest(path);
    this.stamp = this.stampOf();
  }

  private stampOf(): string {
    try {
      const s = statSync(this.path);
      return `${s.mtimeMs}:${s.size}`;
    } catch {
      return '';
    }
  }

  current(): Manifest {
    const now = Date.now();
    if (now < this.retryAfter) return this.manifest;

    const stamp = this.stampOf();
    if (!stamp || stamp === this.stamp) return this.manifest;

    try {
      this.manifest = parseManifest(readFileSync(this.path, 'utf8'));
      this.stamp = stamp;
      this.retryAfter = 0;
      log.info(`manifest reloaded: ${Object.keys(this.manifest.servers).length} servers cached`);
    } catch (err) {
      // Do not record the stamp: the writer may still be mid-write and finish within
      // the same millisecond. Back off briefly instead of re-parsing on every call.
      this.retryAfter = now + 1000;
      log.warn(`manifest reload failed (${(err as Error).message}); serving the previous one`);
    }
    return this.manifest;
  }
}

/** True when the cache has no usable entry for this server's current config. */
export function isStale(manifest: Manifest, u: UpstreamConfig): boolean {
  const entry = manifest.servers[u.name];
  return !entry || entry.hash !== upstreamHash(u) || !!entry.error;
}

/**
 * Spawns each stale server once, records its tools, and shuts it down again.
 * Returns the updated manifest. A server that fails here is recorded with its error
 * rather than dropped, so `status` can show why it is missing instead of silently
 * offering fewer tools.
 */
export async function buildManifest(
  upstreams: UpstreamConfig[],
  pool: ChildPool,
  manifest: Manifest,
  opts: { force?: boolean } = {}
): Promise<{ manifest: Manifest; built: string[]; failed: string[] }> {
  const built: string[] = [];
  const failed: string[] = [];

  for (const u of upstreams) {
    if (!opts.force && !isStale(manifest, u)) {
      log.debug(`manifest for "${u.name}" is current; not spawning`);
      continue;
    }
    try {
      const handle = await pool.acquire(u.name);
      const res = await handle.client.listTools();
      manifest.servers[u.name] = {
        hash: upstreamHash(u),
        builtAt: new Date().toISOString(),
        tools: res.tools,
      };
      built.push(`${u.name} (${res.tools.length} tools)`);
      log.info(`indexed "${u.name}": ${res.tools.length} tools`);
    } catch (err) {
      const message = (err as Error).message;
      manifest.servers[u.name] = {
        hash: upstreamHash(u),
        builtAt: new Date().toISOString(),
        tools: [],
        error: message,
      };
      failed.push(`${u.name}: ${message}`);
      log.error(`failed to index "${u.name}": ${message}`);
    }
  }

  return { manifest, built, failed };
}

/** The union of every cached server's tools, namespaced so names cannot collide. */
export function unionTools(manifest: Manifest, upstreams: UpstreamConfig[]): Tool[] {
  const out: Tool[] = [];
  for (const u of upstreams) {
    const entry = manifest.servers[u.name];
    if (!entry || entry.error) continue;
    for (const t of entry.tools) {
      out.push({
        ...t,
        name: `${u.name}${NS}${t.name}`,
        description: t.description
          ? `[${u.name}] ${t.description}`
          : `[${u.name}] ${t.name}`,
      });
    }
  }
  return out;
}

/** Split a namespaced tool name back into its server and the upstream's own name. */
export function splitToolName(name: string): { server: string; tool: string } | undefined {
  const i = name.indexOf(NS);
  if (i <= 0) return undefined;
  const server = name.slice(0, i);
  const tool = name.slice(i + NS.length);
  if (!server || !tool) return undefined;
  return { server, tool };
}
