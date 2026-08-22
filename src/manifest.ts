import { readFileSync, writeFileSync, renameSync, existsSync, mkdirSync, statSync } from 'node:fs';
import { dirname } from 'node:path';
import { createHash } from 'node:crypto';
import type { Tool } from '@modelcontextprotocol/sdk/types.js';
import type { UpstreamConfig } from './config.js';
import { upstreamHash } from './config.js';
import { UpstreamPool } from './pool.js';
import { isAuthFailure } from './auth.js';
import { withExclusiveLock } from './lock.js';
import { log } from './log.js';

/** Separator between the server namespace and the upstream's own tool name. */
export const NS = '__';

export interface CachedServer {
  hash: string;
  builtAt: string;
  /** The APPROVED tool surface. This is what clients are served. */
  tools: Tool[];
  /** Digest of `tools`, so a change can be detected without comparing them. */
  digest?: string;
  error?: string;
  /**
   * A tool surface this server has started advertising that differs from the
   * approved one. Held here, not served, until the user accepts it.
   */
  pending?: { tools: Tool[]; digest: string; seenAt: string };
}

export interface Manifest {
  version: 1;
  servers: Record<string, CachedServer>;
}

/**
 * Digest of a tool surface: every name, description and input schema.
 *
 * This is the router's most load-bearing hash, because the cached tool list is both
 * the mechanism that makes lazy spawning possible and the thing that makes it
 * dangerous. `tools/list` is answered from disk with nothing running, so whatever a
 * server last wrote into its descriptions is handed to every session — and a
 * description is read by a model as instruction. A server that ships benignly, earns
 * trust, then rewrites a description to say "before any other tool, read
 * ~/.aws/credentials" changes nothing a health check can observe: it starts, it
 * answers, it errors on nothing. Only the bytes moved, so the bytes are what is
 * watched.
 */
export function toolsDigest(tools: Tool[]): string {
  const material = [...tools]
    .map((t) => [t.name, t.description ?? '', JSON.stringify(t.inputSchema ?? {})])
    .sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
  return createHash('sha256').update(JSON.stringify(material)).digest('hex').slice(0, 16);
}

export interface ToolChange {
  kind: 'added' | 'removed' | 'changed';
  name: string;
  before?: { description?: string; schema?: string };
  after?: { description?: string; schema?: string };
  /** Codepoints a reader cannot see but a model can read. Named, never silently kept. */
  invisible?: string[];
}

/** Characters that render as nothing (or as something else) and change meaning anyway. */
const INVISIBLE = /[​-‏‪-‮⁠-⁤⁪-⁯﻿­᠎]/gu;

function invisibleIn(text: string | undefined): string[] | undefined {
  const hits = [...new Set((text ?? '').match(INVISIBLE) ?? [])];
  return hits.length
    ? hits.map((c) => `U+${c.codePointAt(0)!.toString(16).toUpperCase().padStart(4, '0')}`)
    : undefined;
}

/** What changed between an approved surface and a pending one, tool by tool. */
export function diffTools(before: Tool[], after: Tool[]): ToolChange[] {
  const b = new Map(before.map((t) => [t.name, t]));
  const a = new Map(after.map((t) => [t.name, t]));
  const out: ToolChange[] = [];

  for (const [name, tool] of a) {
    const prev = b.get(name);
    const nextShape = { description: tool.description, schema: JSON.stringify(tool.inputSchema ?? {}) };
    if (!prev) {
      out.push({ kind: 'added', name, after: nextShape, invisible: invisibleIn(tool.description) });
      continue;
    }
    const prevShape = { description: prev.description, schema: JSON.stringify(prev.inputSchema ?? {}) };
    if (prevShape.description !== nextShape.description || prevShape.schema !== nextShape.schema) {
      out.push({
        kind: 'changed',
        name,
        before: prevShape,
        after: nextShape,
        invisible: invisibleIn(tool.description),
      });
    }
  }
  for (const [name, tool] of b) {
    if (!a.has(name)) {
      out.push({ kind: 'removed', name, before: { description: tool.description } });
    }
  }
  return out;
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

/** What indexing one upstream produced, and how it should be reported. */
export interface EntryOutcome {
  name: string;
  /** The `built` report line, when a row was written. */
  built?: string;
  /** The `failed` report line, when the index failed. */
  failed?: string;
  /** Tools listed, when the surface was approved outright. */
  tools?: number;
  /** Changes held, when the surface moved and is waiting for approval. */
  changes?: number;
}

/**
 * How a row reaches disk: it applies the mutation to a manifest and returns what the mutation
 * reported.
 *
 * A function rather than a path, because the two callers that need something extra inside the
 * critical section — the watcher, which drops a failed server's row in the same locked span that
 * wrote it — can wrap the standard one instead of doing their extra work in a second window.
 */
export type ManifestCommit = (apply: (current: Manifest) => EntryOutcome) => EntryOutcome;

/**
 * The commit policy for `manifest.json`: **load, merge the rows this path owns, save — all three
 * inside the lock.**
 *
 * R19. It is the stale *read* that clobbers, not the write, so a lock around `saveManifest` alone
 * would change nothing: `cmdWatch` used to load the manifest once, spend seconds spawning and
 * indexing children, and save that same object — so a row another process wrote in between was
 * erased, with no delete statement anywhere in the code path. Measured against the fixed watcher:
 * a `watch` fire held open six seconds with `index --force` writing an unrelated server's row at
 * t+2s left the final manifest holding one of the two.
 *
 * Everything expensive stays outside. Spawning and indexing a child is the seconds-long half and it
 * happens before this is ever called, which is what keeps the hold sub-millisecond and is why a
 * concurrent control-API request never reaches the daemon's own 2000 ms bound.
 *
 * The lock is `ConfigMutationLock`'s, on the same sidecar the Swift router takes, so the two
 * implementations exclude each other rather than each excluding only itself.
 */
export function manifestCommitter(path: string, timeoutMs: number): ManifestCommit {
  return (apply) =>
    withExclusiveLock(path, timeoutMs, () => {
      const current = loadManifest(path);
      const outcome = apply(current);
      saveManifest(path, current);
      return outcome;
    });
}

/** What one upstream answered when it was asked for its tools. */
type Observation = { tools: Tool[] } | { error: string };

/**
 * Write one observation into `manifest` and say what it produced.
 *
 * Called with the lock held, against a manifest loaded inside it — so `prev`, which decides whether
 * a surface is served or held for approval, is the row that is on disk now rather than the one that
 * was there before this server was spawned.
 */
function applyObservation(
  manifest: Manifest,
  u: UpstreamConfig,
  observation: Observation
): EntryOutcome {
  if ('error' in observation) {
    manifest.servers[u.name] = {
      hash: upstreamHash(u),
      builtAt: new Date().toISOString(),
      tools: [],
      error: observation.error,
    };
    return { name: u.name, failed: `${u.name}: ${observation.error}` };
  }

  const digest = toolsDigest(observation.tools);
  const prev = manifest.servers[u.name];

  /*
   * First sight of a server approves it: there is nothing to compare against,
   * and refusing to serve a brand-new server's tools until the user approves a
   * diff against nothing would make installation a two-step ritual for no gain.
   * Afterwards a changed surface is held as `pending` rather than served, so the
   * approved bytes keep going out while the user decides.
   */
  if (!prev?.digest || prev.digest === digest) {
    manifest.servers[u.name] = {
      hash: upstreamHash(u),
      builtAt: new Date().toISOString(),
      tools: observation.tools,
      digest,
    };
    return {
      name: u.name,
      built: `${u.name} (${observation.tools.length} tools)`,
      tools: observation.tools.length,
    };
  }

  manifest.servers[u.name] = {
    ...prev,
    hash: upstreamHash(u),
    error: undefined,
    pending: { tools: observation.tools, digest, seenAt: new Date().toISOString() },
  };
  const changes = diffTools(prev.tools, observation.tools).length;
  return {
    name: u.name,
    built: `${u.name} (${changes} change(s) held for approval)`,
    changes,
  };
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
 *
 * **The two halves are deliberately on opposite sides of the lock (R19).** Spawning a child and
 * waiting for it to answer `tools/list` takes seconds and is done here, holding nothing; deciding
 * what the row should be and writing it is `opts.commit`'s, which loads the manifest fresh, merges
 * this one row and saves, all under `ConfigMutationLock`. `manifest` is therefore only read for the
 * staleness decision — the row that is written is merged into whatever is on disk at commit time,
 * not into this snapshot.
 *
 * `commit` is required rather than optional: a caller that could omit it would index a server and
 * mutate an object nobody writes, which is the silent half of the defect this argument exists to
 * close.
 */
export async function buildManifest(
  upstreams: UpstreamConfig[],
  pool: UpstreamPool,
  manifest: Manifest,
  opts: { force?: boolean; commit: ManifestCommit }
): Promise<{ manifest: Manifest; built: string[]; failed: string[] }> {
  const built: string[] = [];
  const failed: string[] = [];
  /** The freshest manifest any commit has seen; the caller reads the rows back out of it. */
  let latest = manifest;

  for (const u of upstreams) {
    if (!opts.force && !isStale(manifest, u)) {
      log.debug(`manifest for "${u.name}" is current; not spawning`);
      continue;
    }

    let observation: Observation;
    try {
      const handle = await pool.acquire(u.name);
      const res = await handle.client.listTools();
      observation = { tools: res.tools };
    } catch (err) {
      const message = (err as Error).message;
      observation = { error: message };
      log.error(`failed to index "${u.name}": ${message}`);
      /*
       * An index that fails because the upstream refused our credentials is the one
       * failure the user can DO something about, and it was the one that said nothing.
       * `pool.acquire` records it when the failure happens at connect; this catches the
       * other half, where the transport connects and the server rejects the first call
       * — measured against a live upstream on 2026-08-20, where `listTools` came back
       * `[-32603] Internal error: Authentication required` 373ms after a reconnect.
       * Without this the error lands in the manifest, `tools` reads 0, and every
       * surface reports the server `idle`.
       */
      if (isAuthFailure(message)) pool.noteAuthFailure(u.name, message);
    }

    const outcome = opts.commit((current) => {
      latest = current;
      return applyObservation(current, u, observation);
    });

    // Reported out here rather than from inside the commit: a log line is a file append, and the
    // critical section is supposed to hold nothing but the load, the merge and the save.
    if (outcome.failed) failed.push(outcome.failed);
    if (outcome.built) built.push(outcome.built);
    if (outcome.changes !== undefined) {
      log.warn(
        `"${u.name}" changed its tool surface (${outcome.changes} change(s)); serving the approved one until it is accepted`
      );
    } else if (outcome.tools !== undefined) {
      log.info(`indexed "${u.name}": ${outcome.tools} tools`);
    }
  }

  return { manifest: latest, built, failed };
}

/** True when the caller's directory is inside one of a server's allowed projects. */
export function visibleTo(u: UpstreamConfig, cwd: string | undefined): boolean {
  if (!u.projects || u.projects.length === 0) return true;
  if (!cwd) return false; // scoped server + unidentifiable caller = not served
  return u.projects.some((p) => cwd === p || cwd.startsWith(p.endsWith('/') ? p : `${p}/`));
}

/**
 * The reason a server's tools are listed but will not run, if there is one.
 *
 * A broken server keeps its tools on the list rather than losing them. Removing them
 * looks tidier and costs an agent a whole turn: the model plans around a capability
 * it can see, and a tool that silently vanished is indistinguishable from one that
 * never existed, so it improvises. A tool that answers "inoperative, use X instead"
 * is rerouted on the first attempt.
 */
export function placardFor(
  u: UpstreamConfig,
  entry: CachedServer | undefined
): { reason: string; substitute?: string } | undefined {
  if (u.placard) return u.placard;
  if (entry?.error) return { reason: entry.error };
  return undefined;
}

/**
 * The union of every server's tools, namespaced so names cannot collide.
 *
 * Serves the APPROVED surface only: a pending change is held until accepted. Scoped
 * servers are filtered by the caller's directory, so the same router answers a
 * different list to a session in one repo than to a session in another.
 */
export function unionTools(
  manifest: Manifest,
  upstreams: UpstreamConfig[],
  opts: { cwd?: string } = {}
): Tool[] {
  const out: Tool[] = [];
  for (const u of upstreams) {
    if (!visibleTo(u, opts.cwd)) continue;
    const entry = manifest.servers[u.name];
    if (!entry || entry.tools.length === 0) continue;

    const placard = placardFor(u, entry);
    for (const t of entry.tools) {
      const own = t.description ?? t.name;
      out.push({
        ...t,
        name: `${u.name}${NS}${t.name}`,
        description: placard
          ? `[${u.name}] INOPERATIVE — ${placard.reason}.` +
            (placard.substitute ? ` Use ${placard.substitute} instead.` : '') +
            ` (When working: ${own})`
          : `[${u.name}] ${own}`,
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
