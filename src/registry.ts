import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { ROUTER_HOME } from './config.js';
import { log } from './log.js';

/**
 * Server discovery across two indexes, because neither one answers the question alone.
 *
 * The official registry (registry.modelcontextprotocol.io) is the authoritative list of
 * what exists and how to run it — but it publishes no downloads, no ratings and no stars,
 * so it cannot rank anything. Smithery publishes `useCount` and a `verified` flag, which
 * is the only popularity signal available without scraping, but it indexes its own hosted
 * subset rather than everything. Merging them gives a list that is both complete and
 * sortable; keeping the source on every row is what stops that being a claim the data
 * cannot support.
 */

const OFFICIAL = process.env.MCP_ROUTER_REGISTRY ?? 'https://registry.modelcontextprotocol.io';
const SMITHERY = process.env.MCP_ROUTER_SMITHERY ?? 'https://registry.smithery.ai';
const GH_CACHE = join(ROUTER_HOME, 'github-cache.json');
const GH_TTL_MS = 24 * 60 * 60_000;

export interface RegistryEntry {
  id: string;
  name: string;
  displayName: string;
  description: string;
  source: 'official' | 'smithery' | 'both';
  repository?: string;
  version?: string;
  updatedAt?: string;
  /** Smithery only: sessions started. The only popularity number either index publishes. */
  useCount?: number;
  verified?: boolean;
  iconUrl?: string;
  stars?: number;
  forks?: number;
  pushedAt?: string;
  archived?: boolean;
  /** Ready to POST to /servers. Absent when neither index says how to run it. */
  install?: {
    type: 'stdio' | 'http' | 'sse';
    command?: string;
    args?: string[];
    url?: string;
    /** Headers the server requires, by name. Values are never carried; the user supplies them. */
    requires?: Array<{ name: string; description?: string; isSecret?: boolean }>;
  };
}

/** github.com/owner/repo out of any URL shape, lowercased, so two indexes dedupe. */
function repoKey(url: string | undefined): string | undefined {
  if (!url) return undefined;
  const m = /github\.com[/:]([^/]+)\/([^/.?#]+)/i.exec(url);
  return m ? `${m[1].toLowerCase()}/${m[2].toLowerCase()}` : undefined;
}

async function getJson(url: string, timeoutMs = 12_000): Promise<unknown> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const r = await fetch(url, { headers: { accept: 'application/json' }, signal: ctrl.signal });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    return await r.json();
  } finally {
    clearTimeout(t);
  }
}

/* ------------------------------------------------------------------ official */

interface OfficialServer {
  name?: string;
  description?: string;
  version?: string;
  repository?: { url?: string };
  remotes?: Array<{ type?: string; url?: string; headers?: Array<{ name?: string; description?: string; isSecret?: boolean }> }>;
  packages?: Array<{ registryType?: string; identifier?: string; runtimeHint?: string; version?: string }>;
}

/** Turn an official entry's packages/remotes into something the app can install. */
function officialInstall(s: OfficialServer): RegistryEntry['install'] | undefined {
  const remote = s.remotes?.[0];
  if (remote?.url) {
    return {
      type: remote.type === 'sse' ? 'sse' : 'http',
      url: remote.url,
      requires: (remote.headers ?? [])
        .filter((h) => h.name)
        .map((h) => ({ name: h.name!, description: h.description, isSecret: h.isSecret })),
    };
  }
  const pkg = s.packages?.[0];
  if (!pkg?.identifier) return undefined;
  // npm and pypi are the two the registry actually carries; anything else would be a
  // guess at a command line, and a wrong command is worse than no install button.
  if (pkg.registryType === 'npm') {
    return { type: 'stdio', command: 'npx', args: ['-y', pkg.version ? `${pkg.identifier}@${pkg.version}` : pkg.identifier] };
  }
  if (pkg.registryType === 'pypi') {
    return { type: 'stdio', command: 'uvx', args: [pkg.identifier] };
  }
  return undefined;
}

async function searchOfficial(q: string, limit: number): Promise<RegistryEntry[]> {
  const u = new URL('/v0/servers', OFFICIAL);
  if (q) u.searchParams.set('search', q);
  u.searchParams.set('limit', String(limit));
  const body = (await getJson(u.toString())) as {
    servers?: Array<{ server?: OfficialServer; _meta?: Record<string, { updatedAt?: string }> }>;
  };
  return (body.servers ?? []).flatMap((row) => {
    const s = row.server;
    if (!s?.name) return [];
    const meta = Object.values(row._meta ?? {})[0];
    return [
      {
        id: s.name,
        name: s.name,
        // Registry names are namespaced like `ai.smithery/owner-thing`; the last
        // segment is what a person recognises.
        displayName: s.name.split('/').pop() ?? s.name,
        description: s.description ?? '',
        source: 'official' as const,
        repository: s.repository?.url,
        version: s.version,
        updatedAt: meta?.updatedAt,
        install: officialInstall(s),
      },
    ];
  });
}

/* ------------------------------------------------------------------ smithery */

async function searchSmithery(q: string, limit: number): Promise<RegistryEntry[]> {
  const u = new URL('/servers', SMITHERY);
  if (q) u.searchParams.set('q', q);
  u.searchParams.set('pageSize', String(limit));
  const body = (await getJson(u.toString())) as {
    servers?: Array<{
      qualifiedName?: string;
      displayName?: string;
      description?: string;
      iconUrl?: string;
      verified?: boolean;
      useCount?: number;
      remote?: boolean;
      isDeployed?: boolean;
      createdAt?: string;
      homepage?: string;
    }>;
  };
  return (body.servers ?? []).flatMap((s) => {
    if (!s.qualifiedName) return [];
    return [
      {
        id: `smithery:${s.qualifiedName}`,
        name: s.qualifiedName,
        displayName: s.displayName || s.qualifiedName,
        description: s.description ?? '',
        source: 'smithery' as const,
        repository: s.homepage,
        updatedAt: s.createdAt,
        useCount: s.useCount,
        verified: s.verified,
        iconUrl: s.iconUrl,
        // Smithery's hosted servers all speak streamable HTTP at one URL shape, and
        // all of them want a Smithery key, so it is declared rather than assumed.
        install:
          s.remote && s.isDeployed
            ? {
                type: 'http',
                url: `https://server.smithery.ai/${s.qualifiedName}/mcp`,
                requires: [
                  { name: 'Authorization', description: 'Bearer <your Smithery API key>', isSecret: true },
                ],
              }
            : undefined,
      },
    ];
  });
}

/* -------------------------------------------------------------------- github */

interface GhRecord {
  stars?: number;
  forks?: number;
  pushedAt?: string;
  archived?: boolean;
  at: number;
}

function readGhCache(): Record<string, GhRecord> {
  try {
    return JSON.parse(readFileSync(GH_CACHE, 'utf8')) as Record<string, GhRecord>;
  } catch {
    return {};
  }
}

function writeGhCache(c: Record<string, GhRecord>): void {
  try {
    mkdirSync(ROUTER_HOME, { recursive: true });
    writeFileSync(GH_CACHE, JSON.stringify(c));
  } catch {
    /* the cache is an optimisation; failing to write it is not an error */
  }
}

/**
 * Add stars to whatever has a GitHub repo, from a day-old cache.
 *
 * Unauthenticated GitHub allows 60 requests an hour, which one search of thirty
 * results would spend half of. So: cache for a day, only fetch what is missing, cap
 * how many are fetched per call, and stop entirely on the first rate-limit response
 * rather than burning the rest of the budget discovering the same thing repeatedly.
 * `GITHUB_TOKEN` raises the ceiling to 5,000 if one is present.
 */
async function enrichWithStars(entries: RegistryEntry[], budget = 10): Promise<string[]> {
  const warnings: string[] = [];
  const cache = readGhCache();
  const now = Date.now();
  let spent = 0;
  let rateLimited = false;
  const token = process.env.GITHUB_TOKEN ?? process.env.GH_TOKEN;

  for (const e of entries) {
    const key = repoKey(e.repository);
    if (!key) continue;

    const hit = cache[key];
    if (hit && now - hit.at < GH_TTL_MS) {
      Object.assign(e, { stars: hit.stars, forks: hit.forks, pushedAt: hit.pushedAt, archived: hit.archived });
      continue;
    }
    if (rateLimited || spent >= budget) continue;

    spent += 1;
    try {
      const r = await fetch(`https://api.github.com/repos/${key}`, {
        headers: {
          accept: 'application/vnd.github+json',
          ...(token ? { authorization: `Bearer ${token}` } : {}),
        },
      });
      if (r.status === 403 || r.status === 429) {
        rateLimited = true;
        warnings.push(
          token
            ? 'GitHub rate limit reached; star counts are partial.'
            : 'GitHub allows 60 requests an hour without a token, so star counts are partial. Set GITHUB_TOKEN to raise it.'
        );
        continue;
      }
      if (!r.ok) continue;
      const d = (await r.json()) as {
        stargazers_count?: number;
        forks_count?: number;
        pushed_at?: string;
        archived?: boolean;
      };
      const rec: GhRecord = {
        stars: d.stargazers_count,
        forks: d.forks_count,
        pushedAt: d.pushed_at,
        archived: d.archived,
        at: now,
      };
      cache[key] = rec;
      Object.assign(e, { stars: rec.stars, forks: rec.forks, pushedAt: rec.pushedAt, archived: rec.archived });
    } catch {
      /* one repo failing to resolve is not a failed search */
    }
  }
  writeGhCache(cache);
  return warnings;
}

/* --------------------------------------------------------------------- merge */

export interface SearchResult {
  results: RegistryEntry[];
  sources: { official: number; smithery: number; merged: number };
  warnings: string[];
}

/**
 * Search both indexes, dedupe, enrich, and rank.
 *
 * Deduping is by GitHub repository first and normalised name second: the same server
 * genuinely appears in both indexes, and showing it twice would read as two options
 * where there is one. A merged row keeps the official install instructions (they are
 * authoritative) and Smithery's numbers (it is the only one that has any).
 */
export async function searchRegistries(q: string, limit = 30): Promise<SearchResult> {
  const warnings: string[] = [];
  const [official, smithery] = await Promise.all([
    searchOfficial(q, limit).catch((err: Error) => {
      warnings.push(`official registry unreachable: ${err.message}`);
      return [] as RegistryEntry[];
    }),
    searchSmithery(q, limit).catch((err: Error) => {
      warnings.push(`Smithery unreachable: ${err.message}`);
      return [] as RegistryEntry[];
    }),
  ]);

  const byKey = new Map<string, RegistryEntry>();
  const keyOf = (e: RegistryEntry): string =>
    repoKey(e.repository) ?? e.displayName.toLowerCase().replace(/[^a-z0-9]/g, '');

  for (const e of official) byKey.set(keyOf(e), e);
  for (const e of smithery) {
    const k = keyOf(e);
    const existing = byKey.get(k);
    if (!existing) {
      byKey.set(k, e);
      continue;
    }
    byKey.set(k, {
      ...existing,
      source: 'both',
      useCount: e.useCount ?? existing.useCount,
      verified: e.verified ?? existing.verified,
      iconUrl: e.iconUrl ?? existing.iconUrl,
      // Official install wins: it is the authoritative statement of how to run it.
      install: existing.install ?? e.install,
    });
  }

  const results = [...byKey.values()];
  warnings.push(...(await enrichWithStars(results)));

  /*
   * Rank on what is actually measured, in that order: Smithery sessions, then GitHub
   * stars, then recency. An entry with neither number sorts below one that has either,
   * rather than being assigned a made-up score to keep the sort total.
   */
  results.sort((a, b) => {
    const use = (b.useCount ?? 0) - (a.useCount ?? 0);
    if (use) return use;
    const stars = (b.stars ?? 0) - (a.stars ?? 0);
    if (stars) return stars;
    return (b.updatedAt ?? '').localeCompare(a.updatedAt ?? '');
  });

  log.debug(`registry search "${q}": ${official.length} official + ${smithery.length} smithery -> ${results.length}`);
  return {
    results: results.slice(0, limit),
    sources: { official: official.length, smithery: smithery.length, merged: results.length },
    warnings,
  };
}
