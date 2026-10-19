import {
  KINDS,
  SINGULAR,
  type ExtensionFile,
  type ExtensionKind,
  type ExtensionListing,
  type ExtensionRecord,
  type ExtensionStore,
  type PromoteOutcome,
  type Refusal,
} from './extensions.js';
import type { UpstreamConfig } from './config.js';
import { buildFreshnessReport, DEFAULT_STALE_AFTER_MS, freshnessValue, type FreshnessRow } from './extension-updates.js';
import { cachedFiles, changelogFor, pluginIdentity, type Changelog } from './plugin-cache.js';

/*
 * The /extensions family: GET /extensions, the three collections under it, and GET /extensions/updates, the
 * marketplace update check (F6). The update route is matched before the kind parse, or `updates` reads as a kind.
 *
 * A collection answers GET and POST, an item answers GET and DELETE, an add that would collide is 409, and
 * an unknown item is 404 in the words `no <kind> named "x"`. The inventory counts what the router holds.
 *
 * Two reads reach Claude's files, and both are confined to its plugin cache (plugin-cache.ts): a promotion sent as
 * `{source: "cache", pluginVersion}` installs the cached copy of that version, and the update check carries the
 * changelog of the version it offers. Neither writes under Claude's home.
 *
 * This file answers a request to a body and a status. The token and content-type gates, and the write of
 * the reply, belong to control.ts, which calls this only for paths `isExtensionsPath` claims.
 */

export interface RouteAnswer {
  status: number;
  body: unknown;
}

export function isExtensionsPath(pathname: string): boolean {
  return pathname === '/extensions' || pathname.startsWith('/extensions/');
}

/** `null` means the path is claimed but this method is not served, which the caller answers as 405. */
export function extensionRoute(
  method: string,
  pathname: string,
  body: unknown,
  deps: { extensions?: ExtensionStore; upstreams: Map<string, UpstreamConfig>; claudeHome?: string },
  query: URLSearchParams = new URLSearchParams()
): RouteAnswer | null {
  if (!deps.extensions) {
    return { status: 503, body: { error: 'extension storage is unavailable: this router has no store' } };
  }
  const store = deps.extensions;
  const rest = pathname.slice('/extensions'.length);
  if (rest === '') return method === 'GET' ? { status: 200, body: inventory(store, deps.upstreams) } : null;
  // Before the kind parse, or `updates` is read as a kind and answered 404. Any verb but GET is 405.
  if (rest === '/updates') return method === 'GET' ? updates(store, query, deps.claudeHome) : null;

  const segments = rest.split('/').slice(1);
  const kind = KINDS.find((candidate) => candidate === segments[0]);
  if (!kind) return { status: 404, body: { error: `no extension kind named "${segments[0]}"` } };
  if (segments.length === 1) return collection(kind, store, method, body);
  if (segments.length === 2) return item(kind, segments[1], store, method);
  if (segments.length === 3) return action(kind, segments[1], segments[2], store, method, body, deps.claudeHome);
  // Deeper than an action is a path this family claims and does not route.
  return null;
}

/**
 * The marketplace update check. A window that cannot be read is refused rather than replaced by the default: a
 * caller who typed `staleAfterMs=1h` asked a question, and the default would report every catalogue against a
 * window they did not choose.
 */
function updates(store: ExtensionStore, query: URLSearchParams, claudeHome: string | undefined): RouteAnswer {
  const requested = query.get('kind');
  let kinds: readonly ExtensionKind[] = KINDS;
  if (requested !== null) {
    const kind = KINDS.find((candidate) => candidate === requested);
    if (!kind) return { status: 404, body: { error: `no extension kind named "${requested}"` } };
    kinds = [kind];
  }
  const staleAfterMs = staleWindow(query.get('staleAfterMs'));
  if (staleAfterMs === null) {
    return { status: 400, body: { error: 'staleAfterMs must be a non-negative whole number of milliseconds' } };
  }
  const name = query.get('name') ?? undefined;
  const report = buildFreshnessReport(store, { kinds, staleAfterMs, now: Date.now(), name });
  return { status: 200, body: freshnessValue(report, (row) => updateChangelog(row, claudeHome)) };
}

/** The changelog of the version an entry offers, for an entry that has one to offer. Nothing else is read. */
function updateChangelog(row: FreshnessRow, claudeHome: string | undefined): Changelog | null {
  const { hasUpdate, available } = row.verdict;
  if (!hasUpdate || available === null || row.kind !== 'plugins') return null;
  return changelogFor(claudeHome, row.name, available);
}

/** The default when absent, the number when it is ASCII digits, and null when it is present and unreadable. */
function staleWindow(raw: string | null): number | null {
  if (raw === null) return DEFAULT_STALE_AFTER_MS;
  return /^[0-9]+$/.test(raw) ? Number(raw) : null;
}

function collection(kind: ExtensionKind, store: ExtensionStore, method: string, body: unknown): RouteAnswer | null {
  if (method === 'GET') return { status: 200, body: listingValue(store.list(kind)) };
  if (method === 'POST') return add(kind, store, body);
  return null;
}

/** The POST writes under one entry: promote, keep and undo-promote. Any other verb or method is not served. */
function action(
  kind: ExtensionKind,
  rawName: string,
  verb: string,
  store: ExtensionStore,
  method: string,
  body: unknown,
  claudeHome: string | undefined
): RouteAnswer | null {
  if (method !== 'POST') return null;
  const name = decodeName(rawName);
  if (name === null) return { status: 400, body: { error: 'URI malformed' } };
  if (verb === 'promote') return promote(kind, name, store, body, claudeHome);
  if (verb === 'keep') return keep(kind, name, store, body);
  if (verb === 'undo-promote') return undoPromote(kind, name, store, body);
  return null;
}

/** A name arrives percent-decoded, as a server name does. `null` is a malformed escape, which is refused rather than guessed at. */
function decodeName(rawName: string): string | null {
  try {
    return decodeURIComponent(rawName);
  } catch {
    return null;
  }
}

function item(kind: ExtensionKind, rawName: string, store: ExtensionStore, method: string): RouteAnswer | null {
  // A malformed escape is 400: the router cannot say whether a name it could not read exists.
  const name = decodeName(rawName);
  if (name === null) return { status: 400, body: { error: 'URI malformed' } };
  if (method === 'GET') {
    const record = store.read(kind, name);
    if (!record) return { status: 404, body: { error: `no ${SINGULAR[kind]} named "${name}"` } };
    return { status: 200, body: recordValue(record) };
  }
  if (method === 'DELETE') return remove(kind, name, store);
  return null;
}

function add(kind: ExtensionKind, store: ExtensionStore, body: unknown): RouteAnswer {
  const request = (body ?? {}) as { name?: unknown; files?: unknown };
  // Truthiness, as `POST /servers` applies it: an empty string is "required", not a valid name.
  if (typeof request.name !== 'string' || request.name === '') {
    return { status: 400, body: { error: 'name is required' } };
  }
  const name = request.name;
  const parsed = parseFiles(request.files);
  if ('error' in parsed) return { status: 400, body: { error: parsed.error } };
  const outcome = store.add(kind, name, parsed.files);
  if (outcome.outcome === 'refused') return refusalValue(outcome.refusal);
  return {
    status: 201,
    body: { added: name, kind, files: outcome.record.files, bytes: outcome.record.bytes },
  };
}

/**
 * Installs a newer version of an entry. A request sends the files (the original form), or sends `source: "cache"` and
 * the router reads the version from Claude's plugin cache. The two are not mixed: a cache request that also sends
 * files is refused, because the router would not know which copy the caller meant.
 */
function promote(
  kind: ExtensionKind,
  name: string,
  store: ExtensionStore,
  body: unknown,
  claudeHome: string | undefined
): RouteAnswer {
  const request = (body ?? {}) as { source?: unknown; pluginVersion?: unknown; files?: unknown };
  if (typeof request.pluginVersion !== 'string' || request.pluginVersion === '') {
    return { status: 400, body: { error: 'pluginVersion is required' } };
  }
  if (request.source === 'cache') return promoteFromCache(kind, name, request.pluginVersion, store, request.files, claudeHome);
  if (request.source !== undefined) {
    return { status: 400, body: { error: 'source must be "cache" when it is sent, or absent when files are sent' } };
  }
  const parsed = parseFiles(request.files);
  if ('error' in parsed) return { status: 400, body: { error: parsed.error } };
  return promoted(kind, name, request.pluginVersion, store.promote(kind, name, request.pluginVersion, parsed.files));
}

/** Only a plugin has a cache directory, so only a plugin is promoted from the cache. The files are read there, not sent. */
function promoteFromCache(
  kind: ExtensionKind,
  name: string,
  pluginVersion: string,
  store: ExtensionStore,
  files: unknown,
  claudeHome: string | undefined
): RouteAnswer {
  if (kind !== 'plugins') {
    return { status: 400, body: { error: `a ${SINGULAR[kind]} cannot be promoted from the plugin cache, only a plugin can` } };
  }
  if (files !== undefined) {
    return { status: 400, body: { error: 'files is not read for source "cache": the router reads the cached copy itself' } };
  }
  const cached = cachedFiles(claudeHome, name, pluginVersion);
  if (!cached.ok) return refusalValue(cached.refusal);
  // The manifest names the plugin, not `<plugin>@<marketplace>`, so the store is told which title to hold it to.
  const title = pluginIdentity(name)?.plugin ?? name;
  return promoted(kind, name, pluginVersion, store.promote(kind, name, pluginVersion, cached.files, title));
}

function promoted(kind: ExtensionKind, name: string, pluginVersion: string, outcome: PromoteOutcome): RouteAnswer {
  if (outcome.outcome === 'refused') return refusalValue(outcome.refusal);
  return {
    status: 200,
    body: {
      promoted: name,
      kind,
      pluginVersion,
      replaced: outcome.replaced,
      restore: outcome.restore,
      files: outcome.record.files,
      bytes: outcome.record.bytes,
    },
  };
}

function undoPromote(kind: ExtensionKind, name: string, store: ExtensionStore, body: unknown): RouteAnswer {
  const request = (body ?? {}) as { restore?: unknown };
  if (typeof request.restore !== 'string' || request.restore === '') {
    return { status: 400, body: { error: 'restore is required, as the restore reference a promotion returned' } };
  }
  const outcome = store.undoPromotion(kind, name, request.restore);
  if (outcome.outcome === 'refused') return refusalValue(outcome.refusal);
  return {
    status: 200,
    body: { restored: name, kind, version: outcome.record.version, withdrawn: outcome.withdrawn },
  };
}

function keep(kind: ExtensionKind, name: string, store: ExtensionStore, body: unknown): RouteAnswer {
  const request = (body ?? {}) as { pluginVersion?: unknown };
  if (typeof request.pluginVersion !== 'string' || request.pluginVersion === '') {
    return { status: 400, body: { error: 'pluginVersion is required' } };
  }
  const outcome = store.keep(kind, name, request.pluginVersion);
  if (outcome.outcome === 'refused') return refusalValue(outcome.refusal);
  return { status: 200, body: { kept: name, kind, pluginVersion: request.pluginVersion } };
}

/** The files of a request, each with a path and its text, or the sentence that says what is wrong with them. */
function parseFiles(value: unknown): { files: ExtensionFile[] } | { error: string } {
  if (!Array.isArray(value)) return { error: 'files is required, as an array of {path, text}' };
  const files: ExtensionFile[] = [];
  for (const entry of value as unknown[]) {
    const file = entry as { path?: unknown; text?: unknown } | null;
    if (
      typeof file !== 'object' ||
      file === null ||
      typeof file.path !== 'string' ||
      file.path === '' ||
      typeof file.text !== 'string'
    ) {
      return { error: 'every file needs a non-empty path and a text string' };
    }
    files.push({ path: file.path, text: file.text });
  }
  return { files };
}

function remove(kind: ExtensionKind, name: string, store: ExtensionStore): RouteAnswer {
  const outcome = store.remove(kind, name);
  if (outcome.outcome === 'refused') return refusalValue(outcome.refusal);
  // Where the bytes went, on the wire. This route deletes nothing, so the path is what makes it reversible.
  return { status: 200, body: { removed: name, kind, restorePath: outcome.restorePath } };
}

function inventory(store: ExtensionStore, upstreams: Map<string, UpstreamConfig>): unknown {
  const listings = KINDS.map((kind) => store.list(kind));
  const counts: Record<string, number | null> = { servers: upstreams.size };
  for (const listing of listings) {
    counts[listing.kind] = listing.unreadable === null ? listing.records.length : null;
  }
  return {
    counts,
    // Name and transport only. `GET /servers` is where a server's own row lives.
    servers: [...upstreams.entries()].map(([name, upstream]) => ({ name, transport: upstream.transport })),
    ...Object.fromEntries(listings.map((listing) => [listing.kind, listingValue(listing)])),
  };
}

/** One kind's collection. `count` is null, not 0, when the directory could not be read. */
export function listingValue(listing: ExtensionListing): Record<string, unknown> {
  return {
    kind: listing.kind,
    root: listing.root,
    count: listing.unreadable === null ? listing.records.length : null,
    unreadable: listing.unreadable,
    entries: listing.records.map(recordValue),
  };
}

export function recordValue(record: ExtensionRecord): Record<string, unknown> {
  return {
    name: record.name,
    title: record.title,
    description: record.description,
    version: record.version,
    files: record.files,
    bytes: record.bytes,
    problem: record.problem,
  };
}

/** A refusal carries its slug beside its sentence: a caller branches on the slug, a person reads the sentence. */
function refusalValue(refusal: Refusal): RouteAnswer {
  return { status: refusal.status, body: { error: refusal.message, reason: refusal.reason } };
}
