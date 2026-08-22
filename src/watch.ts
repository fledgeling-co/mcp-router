/**
 * One-shot watcher: absorbs newly-added MCP servers out of `~/.claude.json`.
 *
 * `~/.claude.json` is the staging area. `claude mcp add` writes an stdio server into
 * its `mcpServers`, launchd fires this on the file change, and the server is moved
 * into the router's own list, indexed, and deleted from user scope. From then on it
 * reaches every session through the router instead of starting a copy per session.
 *
 * Two facts shape the whole design:
 *
 * 1. That file is ~268 KB and Claude Code rewrites it constantly with session state,
 *    so this runs *very* often. The common case — nothing about `mcpServers` changed —
 *    must be a read, a hash and an exit, with nothing spawned and nothing written.
 * 2. It holds live session state for every project on the machine. So: back up before
 *    writing, write temp-plus-rename rather than truncating in place, and abandon the
 *    run entirely rather than write anything derived from a parse that failed.
 */
import {
  readFileSync,
  writeFileSync,
  renameSync,
  copyFileSync,
  existsSync,
  mkdirSync,
  appendFileSync,
  readdirSync,
  unlinkSync,
  statSync,
} from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import {
  ROUTER_HOME,
  DEFAULT_CONFIG_PATH,
  upstreamHash,
  parseServer,
  isSelfReference,
  type UpstreamConfig,
} from './config.js';
import { UpstreamPool } from './pool.js';
import { buildManifest, loadManifest, saveManifest, isStale, type Manifest } from './manifest.js';

const CLAUDE_JSON = join(homedir(), '.claude.json');
const STATE_PATH = join(ROUTER_HOME, 'watch-state.json');
const WATCH_LOG = join(ROUTER_HOME, 'watch.log');
const BACKUP_DIR = join(ROUTER_HOME, 'backups');
const LAUNCHD_LABEL = 'gg.rhodes.mcp-router';

/** How long a server that failed to index is left alone before it is tried again. */
const FAILURE_BACKOFF_MS = 5 * 60_000;
const KEEP_BACKUPS = 10;

/** Never adopted: the router's own entry, and anything that is not stdio. */
const RESERVED = new Set(['router']);

interface RawServer {
  type?: string;
  command?: string;
  args?: string[];
  env?: Record<string, string>;
  cwd?: string;
  url?: string;
}

interface WatchState {
  /** Hash of the `mcpServers` object only — the rest of the file churns constantly. */
  mcpServersHash?: string;
  failures?: Record<string, { hash: string; at: number; error: string }>;
}

function watchLog(msg: string): void {
  mkdirSync(ROUTER_HOME, { recursive: true });
  try {
    appendFileSync(WATCH_LOG, `${new Date().toISOString()} ${msg}\n`);
  } catch {
    /* logging must never be the reason this fails */
  }
}

/** Key order in JSON is not meaningful; sort it so a re-serialisation is not a "change". */
function stable(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const k of Object.keys(value as Record<string, unknown>).sort()) {
      out[k] = stable((value as Record<string, unknown>)[k]);
    }
    return out;
  }
  return value;
}

function hashOf(value: unknown): string {
  return createHash('sha256').update(JSON.stringify(stable(value))).digest('hex').slice(0, 32);
}

function loadState(): WatchState {
  try {
    return JSON.parse(readFileSync(STATE_PATH, 'utf8')) as WatchState;
  } catch {
    return {};
  }
}

function saveState(state: WatchState): void {
  mkdirSync(ROUTER_HOME, { recursive: true });
  const tmp = `${STATE_PATH}.tmp-${process.pid}`;
  writeFileSync(tmp, JSON.stringify(state, null, 2));
  renameSync(tmp, STATE_PATH);
}

function backup(path: string): string {
  mkdirSync(BACKUP_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const dest = join(BACKUP_DIR, `${path.split('/').pop()}.${stamp}`);
  copyFileSync(path, dest);
  prune(path.split('/').pop() ?? '');
  return dest;
}

/** Keep the backup directory bounded; ~/.claude.json is 268 KB a copy. */
function prune(prefix: string): void {
  try {
    const mine = readdirSync(BACKUP_DIR)
      .filter((f) => f.startsWith(`${prefix}.`))
      .sort();
    for (const f of mine.slice(0, Math.max(0, mine.length - KEEP_BACKUPS))) {
      unlinkSync(join(BACKUP_DIR, f));
    }
  } catch {
    /* pruning is housekeeping, never a failure */
  }
}

/** Temp file in the same directory, then rename: readers see old or new, never half. */
function writeAtomic(path: string, contents: string, mode = 0o600): void {
  const tmp = `${path}.mcpr-tmp-${process.pid}`;
  writeFileSync(tmp, contents, { mode });
  renameSync(tmp, path);
}

/**
 * Both transports are adoptable now. The one thing that must never be adopted is
 * the router's own entry in ~/.claude.json, which would make it proxy to itself.
 */
function candidateOf(name: string, s: RawServer, port: number): UpstreamConfig | undefined {
  if (isSelfReference(name, s, port)) return undefined;
  const parsed = parseServer(name, s);
  if ('reason' in parsed) {
    watchLog(`skipped "${name}": ${parsed.reason}`);
    return undefined;
  }
  return parsed.upstream;
}

export async function cmdWatch(opts: { verbose?: boolean } = {}): Promise<void> {
  if (!existsSync(CLAUDE_JSON)) return;

  const raw = readFileSync(CLAUDE_JSON, 'utf8');
  let parsed: { mcpServers?: Record<string, RawServer> } & Record<string, unknown>;
  try {
    parsed = JSON.parse(raw) as typeof parsed;
  } catch (err) {
    // A parse failure here is almost always a read that landed mid-write. Writing
    // anything derived from it would destroy the file, so this run simply ends.
    watchLog(`~/.claude.json did not parse (${(err as Error).message}); abandoned, nothing written`);
    return;
  }

  const servers = (parsed.mcpServers ?? {}) as Record<string, RawServer>;
  const hash = hashOf(servers);
  const state = loadState();

  // The whole point of the hash: this is the path taken on nearly every fire.
  if (state.mcpServersHash === hash) {
    if (opts.verbose) process.stdout.write('mcpServers unchanged; nothing to do\n');
    return;
  }

  const routerPort = 8879;
  const candidates: Array<{ name: string; server: RawServer; upstream: UpstreamConfig }> = [];
  for (const [name, s] of Object.entries(servers)) {
    if (RESERVED.has(name)) continue;
    const upstream = candidateOf(name, s, routerPort);
    if (upstream) candidates.push({ name, server: s, upstream });
  }

  if (candidates.length === 0) {
    saveState({ ...state, mcpServersHash: hash });
    if (opts.verbose) process.stdout.write('no entries to adopt\n');
    return;
  }

  if (!existsSync(DEFAULT_CONFIG_PATH)) {
    watchLog(`no router config at ${DEFAULT_CONFIG_PATH}; adoption skipped`);
    return;
  }
  const routerCfg = JSON.parse(readFileSync(DEFAULT_CONFIG_PATH, 'utf8')) as {
    mcpServers?: Record<string, RawServer>;
  } & Record<string, unknown>;
  const routerServers = (routerCfg.mcpServers ?? {}) as Record<string, RawServer>;

  const failures = state.failures ?? {};
  // A failure record for a server that is no longer staged is dead weight.
  for (const name of Object.keys(failures)) {
    if (!candidates.some((c) => c.name === name)) delete failures[name];
  }
  const now = Date.now();
  const manifestPath = join(ROUTER_HOME, 'manifest.json');
  let manifest: Manifest = loadManifest(manifestPath);

  const live: Array<{ name: string; server: RawServer; upstream: UpstreamConfig }> = [];
  const toIndex: UpstreamConfig[] = [];
  const backedOff: string[] = [];

  for (const { name, server, upstream } of candidates) {
    const failure = failures[name];
    if (failure && failure.hash === upstreamHash(upstream) && now - failure.at < FAILURE_BACKOFF_MS) {
      backedOff.push(name);
      continue;
    }
    live.push({ name, server, upstream });
    if (isStale(manifest, upstream)) toIndex.push(upstream);
  }

  // Index before adopting. A server is only written into the router's own list once it
  // has proved it starts and answers `tools/list` — otherwise a typo'd command would
  // be silently swallowed out of user scope and into a config that cannot serve it.
  if (toIndex.length > 0) {
    const pool = new UpstreamPool(
      new Map(toIndex.map((u) => [u.name, u])),
      60_000,
      (routerCfg.startupTimeoutMs as number) ?? 60_000
    );
    try {
      const { manifest: next, built, failed } = await buildManifest(toIndex, pool, manifest);
      for (const f of failed) {
        const name = f.slice(0, f.indexOf(':'));
        const entry = toIndex.find((u) => u.name === name);
        /*
         * The error row `buildManifest` just wrote is KEPT (R17).
         *
         * It used to be deleted here — `delete next.servers[name]` — on the reasoning that
         * an entry carrying an error still "looks indexed" to the next reader. No reader
         * reads it that way: this watcher's own adoption gate rejects `entry.error` a few
         * blocks down, `isStale` returns true for it, `unionTools` skips a zero-tool entry,
         * and `describe` and `reportUpstreams` exist precisely to surface it. What the
         * delete actually did was erase the attempt from the one file those readers join
         * through. `watch-state.json` kept the reason the whole time, durably, and this
         * watcher reads that file every fire — for the backoff, never to show anyone. So it
         * is a record no reader can reach rather than no record at all.
         *
         * Measured on the owner's machine, 2026-08-21: `namecheap` and `lifeline` both fail
         * `MCP error -32000: Connection closed`. `lifeline` is not staged in ~/.claude.json,
         * so this loop never ran over it and the row `index` wrote survived. `namecheap` is
         * staged, so every fire past the backoff re-indexed it and deleted the row again, and
         * the row `index --force` had just written was gone again too — by this delete or by
         * the stale save R19 describes, whichever fire it fell into, because a row written
         * AFTER a fire's load is not in `next` for this delete to reach. `/servers` then
         * reported `error: None, tools: 0, state: idle` for a server whose reason this process
         * had in hand and discarded. The reason survived only in watch-state.json, and nothing
         * reads it back to any surface.
         *
         * That account is SUFFICIENT and not EXCLUSIVE — R19. A second mechanism erases a
         * freshly-written row after this fix, with no delete statement anywhere in its path:
         * `cmdWatch` loads the manifest once, spends seconds spawning and indexing children,
         * and saves that same object at the `saveManifest` a few lines below, so a row another
         * path writes inside that window is clobbered. Demonstrated against the FIXED code by
         * holding a fire open six seconds while `index --force` wrote a second server's row.
         * The owner's measurement came from a timeline where the launchd watch agent and an
         * `index --force` were both live, so what was seen is consistent with either. The route
         * account above is kept for the ASYMMETRY between the two servers, and it is stronger
         * there than "better fit": a stale save can only erase a row written by SOMEONE ELSE
         * during the window, and a staged server is in every fire's own hand, so an R19-only
         * world predicts `namecheap` KEEPS its row and unstaged `lifeline` loses one. That is
         * the opposite of what was measured. The pre-registered prediction held as well: stage
         * `lifeline` too and its row starts disappearing.
         *
         * The backoff below is untouched. It is the retry policy; the manifest row is the
         * record. They answer different questions and neither substitutes for the other.
         */
        watchLog(`failed to index "${f}"; left in ~/.claude.json, will retry`);
        if (entry) failures[name] = { hash: upstreamHash(entry), at: now, error: f };
      }
      for (const b of built) {
        watchLog(`adopted ${b} from ~/.claude.json`);
        delete failures[b.slice(0, b.indexOf(' '))];
      }
      manifest = next;
      saveManifest(manifestPath, manifest);
    } finally {
      await pool.shutdown();
    }
  }

  // Adopt = present in the manifest, error-free, at the current config identity.
  const adopted: string[] = [];
  /** What each adopted name looked like when it was indexed, to compare before deleting. */
  const adoptedDef = new Map<string, RawServer>();
  const pending: string[] = [...backedOff];
  let configChanged = false;
  for (const { name, server, upstream } of live) {
    const entry = manifest.servers[name];
    if (!entry || entry.error || entry.hash !== upstreamHash(upstream)) {
      pending.push(name);
      continue;
    }
    adopted.push(name);
    adoptedDef.set(name, server);
    if (JSON.stringify(stable(routerServers[name])) !== JSON.stringify(stable(server))) {
      routerServers[name] = server;
      configChanged = true;
    }
  }

  if (configChanged) {
    backup(DEFAULT_CONFIG_PATH);
    routerCfg.mcpServers = routerServers;
    writeAtomic(DEFAULT_CONFIG_PATH, `${JSON.stringify(routerCfg, null, 2)}\n`, 0o644);
  }

  if (adopted.length > 0) {
    // Re-read immediately before writing: this file is rewritten constantly, and the
    // copy parsed at the top of this run may be a minute stale by now.
    let fresh2: { mcpServers?: Record<string, RawServer> } & Record<string, unknown>;
    let rawNow: string;
    try {
      rawNow = readFileSync(CLAUDE_JSON, 'utf8');
      fresh2 = JSON.parse(rawNow) as typeof fresh2;
    } catch (err) {
      watchLog(
        `indexed ${adopted.join(', ')} but ~/.claude.json no longer parses ` +
          `(${(err as Error).message}); left it untouched, will retry`
      );
      saveState({ ...state, failures });
      return;
    }

    const staged = (fresh2.mcpServers ?? {}) as Record<string, RawServer>;
    const removed: string[] = [];
    for (const name of adopted) {
      const staging = staged[name];
      if (!staging || 'reason' in parseServer(name, staging) || RESERVED.has(name)) continue;
      /*
       * Only remove what is still exactly what was indexed. Indexing spawns a
       * child and waits for it to initialize, so the window is seconds — long
       * enough for someone to correct the entry they just added. Deleting an
       * edited definition would throw that edit away with nothing to recover it
       * from: the router would hold the pre-edit version and the file it was
       * typed into would no longer have it. Leaving it puts the name back in
       * `pending`, which withholds the state hash so the next fire re-indexes it.
       */
      if (JSON.stringify(stable(staging)) !== JSON.stringify(stable(adoptedDef.get(name)))) {
        watchLog(`"${name}" changed in ~/.claude.json while it was being indexed; left it there for the next fire`);
        pending.push(name);
        continue;
      }
      delete staged[name];
      removed.push(name);
    }

    if (removed.length > 0) {
      backup(CLAUDE_JSON);
      fresh2.mcpServers = staged;
      const mode = statSync(CLAUDE_JSON).mode & 0o777;
      writeAtomic(CLAUDE_JSON, JSON.stringify(fresh2, null, 2), mode);
      watchLog(
        `removed ${removed.length} adopted stdio entr${removed.length === 1 ? 'y' : 'ies'} ` +
          `from ~/.claude.json: ${removed.join(', ')}`
      );
    }

    if (configChanged) restartRouter();

    // Hash what is now on disk, not what was read at the top: our own write is about
    // to fire this watcher again, and that fire must take the fast path.
    const after = hashOf((JSON.parse(readFileSync(CLAUDE_JSON, 'utf8')) as typeof parsed).mcpServers ?? {});
    if (pending.length === 0) {
      saveState({ mcpServersHash: after, failures });
    } else {
      // A server that failed to index leaves the hash unwritten deliberately: the next
      // fire re-runs and retries it, rather than skipping it silently forever.
      watchLog(`still pending (not adopted): ${pending.join(', ')}`);
      saveState({ failures });
    }
    return;
  }

  if (pending.length > 0) {
    saveState({ failures });
    return;
  }

  saveState({ ...state, mcpServersHash: hash, failures });
}

/**
 * The running router loaded its upstream list at startup, so a server that has just
 * been added to servers.json is not one it knows how to spawn yet. The manifest hot-
 * reloads; the upstream list does not, so a config change means a restart.
 */
function restartRouter(): void {
  try {
    execFileSync('/bin/launchctl', ['kickstart', '-k', `gui/${process.getuid?.() ?? 501}/${LAUNCHD_LABEL}`], {
      stdio: 'ignore',
      timeout: 15_000,
    });
    watchLog(`restarted ${LAUNCHD_LABEL} to pick up the new upstream`);
  } catch (err) {
    watchLog(`could not restart ${LAUNCHD_LABEL} (${(err as Error).message}); run it manually`);
  }
}
