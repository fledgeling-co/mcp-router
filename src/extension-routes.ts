import {
  KINDS,
  SINGULAR,
  type ExtensionFile,
  type ExtensionKind,
  type ExtensionListing,
  type ExtensionRecord,
  type ExtensionStore,
  type Refusal,
} from './extensions.js';
import type { UpstreamConfig } from './config.js';

/*
 * The /extensions family: GET /extensions, and the three collections under it.
 *
 * A collection answers GET and POST, an item answers GET and DELETE, an add that would collide is 409, and
 * an unknown item is 404 in the words `no <kind> named "x"`. Nothing here reads or writes Claude's own
 * directories; the inventory counts what the router holds.
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
  deps: { extensions?: ExtensionStore; upstreams: Map<string, UpstreamConfig> }
): RouteAnswer | null {
  if (!deps.extensions) {
    return { status: 503, body: { error: 'extension storage is unavailable: this router has no store' } };
  }
  const store = deps.extensions;
  const rest = pathname.slice('/extensions'.length);
  if (rest === '') return method === 'GET' ? { status: 200, body: inventory(store, deps.upstreams) } : null;

  const segments = rest.split('/').slice(1);
  const kind = KINDS.find((candidate) => candidate === segments[0]);
  if (!kind) return { status: 404, body: { error: `no extension kind named "${segments[0]}"` } };
  if (segments.length === 1) return collection(kind, store, method, body);
  if (segments.length === 2) return item(kind, segments[1], store, method);
  // Deeper than an item is a path this family claims and does not route.
  return null;
}

function collection(kind: ExtensionKind, store: ExtensionStore, method: string, body: unknown): RouteAnswer | null {
  if (method === 'GET') return { status: 200, body: listingValue(store.list(kind)) };
  if (method === 'POST') return add(kind, store, body);
  return null;
}

function item(kind: ExtensionKind, rawName: string, store: ExtensionStore, method: string): RouteAnswer | null {
  // Percent-decoded as a server name is, and a malformed escape is 400: the router cannot say whether a name
  // it could not read exists.
  let name: string;
  try {
    name = decodeURIComponent(rawName);
  } catch {
    return { status: 400, body: { error: 'URI malformed' } };
  }
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
  if (!Array.isArray(request.files)) {
    return { status: 400, body: { error: 'files is required, as an array of {path, text}' } };
  }
  const files: ExtensionFile[] = [];
  for (const entry of request.files as unknown[]) {
    const file = entry as { path?: unknown; text?: unknown } | null;
    if (
      typeof file !== 'object' ||
      file === null ||
      typeof file.path !== 'string' ||
      file.path === '' ||
      typeof file.text !== 'string'
    ) {
      return { status: 400, body: { error: 'every file needs a non-empty path and a text string' } };
    }
    files.push({ path: file.path, text: file.text });
  }
  const outcome = store.add(kind, name, files);
  if (outcome.outcome === 'refused') return refusalValue(outcome.refusal);
  return {
    status: 201,
    body: { added: name, kind, files: outcome.record.files, bytes: outcome.record.bytes },
  };
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
