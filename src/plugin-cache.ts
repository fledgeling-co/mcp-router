import { existsSync, lstatSync, readdirSync, readFileSync, realpathSync, statSync, type Stats } from 'node:fs';
import { join, sep } from 'node:path';
import { isWellFormedSegment, type ExtensionFile, type Refusal } from './extensions.js';
import { DOCUMENT_CAPS, documentOverCap } from './document.js';

/*
 * Claude's plugin cache, read for two things: the files of a version a marketplace offers, which a promotion installs,
 * and that version's CHANGELOG.md, which the update check shows. The cache belongs to Claude. The router reads it and
 * never writes it.
 *
 * A version lives at `<claudeHome>/plugins/cache/<marketplace>/<plugin>/<version>`. A plugin's identity is
 * `<plugin>@<marketplace>`, split at the first `@` as the installed-plugin register splits it.
 *
 * Every path is resolved before anything is read, and nothing that resolves outside the cache is read. A symlink is
 * followed only to a regular file inside the cache, so a link a plugin carries cannot bring a file from elsewhere on
 * this machine into the store, or into a changelog a caller reads.
 */

/** What the update check reports about one offered version's changelog. `text` is null wherever it was not sent. */
export interface Changelog {
  text: string | null;
  note: string;
}

export interface PluginIdentity {
  plugin: string;
  marketplace: string;
}

export function pluginIdentity(name: string): PluginIdentity | null {
  const at = name.indexOf('@');
  if (at <= 0 || at === name.length - 1) return null;
  return { plugin: name.slice(0, at), marketplace: name.slice(at + 1) };
}

/** The files of one cached version, ready to promote, or the refusal that says why they cannot be read. */
export type CachedFiles = { ok: true; files: ExtensionFile[] } | { ok: false; refusal: Refusal };

/**
 * The files of `name` at `version` as Claude's cache holds them. Refuses when the router has no Claude home, when the
 * version is not in the cache, when a path resolves outside the cache, and when a file is not UTF-8 text, which the
 * store cannot hold. Nothing is partly read: a refusal anywhere means no files.
 */
export function cachedFiles(claudeHome: string | undefined, name: string, version: string): CachedFiles {
  if (claudeHome === undefined) {
    return fail(503, 'noClaudeHome', 'the router has no Claude home to read the plugin cache from');
  }
  const identity = pluginIdentity(name);
  if (identity === null) {
    return fail(400, 'invalidName', `a plugin is named plugin@marketplace, which "${name}" is not`);
  }
  const resolved = resolveVersion(claudeHome, identity, version);
  if (!resolved.ok) return resolved;
  const files: ExtensionFile[] = [];
  const refusal = walk(resolved.value.directory, resolved.value.root, '', files);
  return refusal === null ? { ok: true, files } : { ok: false, refusal };
}

/**
 * The changelog a cached version ships with, for the update check. Never throws and never refuses: every case the
 * router cannot send a changelog for becomes a note that says which case it was.
 */
export function changelogFor(claudeHome: string | undefined, name: string, version: string): Changelog {
  if (claudeHome === undefined) return { text: null, note: 'the router has no Claude home to read a changelog from' };
  const identity = pluginIdentity(name);
  if (identity === null) return { text: null, note: `"${name}" does not name a marketplace, so no changelog is read` };
  const resolved = resolveVersion(claudeHome, identity, version);
  if (!resolved.ok) {
    if (resolved.refusal.reason === 'noCachedVersion') {
      return { text: null, note: `the router's plugin cache holds no copy of ${version}, so no changelog was read` };
    }
    return { text: null, note: resolved.refusal.message };
  }
  const { root, directory } = resolved.value;
  const label = `CHANGELOG.md for ${version}`;
  const link = lstatOrNull(join(directory, 'CHANGELOG.md'));
  if (link === null) return { text: null, note: `no changelog was published with ${version}` };
  const target = link.isSymbolicLink() ? realpathOrNull(join(directory, 'CHANGELOG.md')) : join(directory, 'CHANGELOG.md');
  if (target === null) return { text: null, note: `${label} is a link the router cannot resolve, so it is not read` };
  if (!inside(target, root)) return { text: null, note: `${label} is a link outside the plugin cache, so it is not read` };
  if (!isFile(target)) return { text: null, note: `${label} is not a file, so it is not read` };
  const size = statSync(target).size;
  if (documentOverCap(size)) {
    return {
      text: null,
      note: `${label} is ${size} bytes, over the ${DOCUMENT_CAPS.documentBytes}-byte cap, so it is not sent`,
    };
  }
  const text = readText(target);
  if (text === null) return { text: null, note: `${label} is not UTF-8 text, so it is not sent` };
  return { text, note: `CHANGELOG.md from the cached ${version} copy` };
}

type Resolution = { ok: true; value: { root: string; directory: string } } | { ok: false; refusal: Refusal };

/** The real cache root and the real version directory, or the refusal. The directory must sit inside the root. */
function resolveVersion(claudeHome: string, identity: PluginIdentity, version: string): Resolution {
  if (![identity.plugin, identity.marketplace, version].every(isWellFormedSegment)) {
    return fail(400, 'invalidVersion', `"${identity.plugin}@${identity.marketplace}" at "${version}" is not a cache path`);
  }
  const cacheRoot = join(claudeHome, 'plugins', 'cache');
  if (!existsSync(cacheRoot)) return missing(identity, version);
  const root = realpathSync(cacheRoot);
  const directory = realpathOrNull(join(cacheRoot, identity.marketplace, identity.plugin, version));
  if (directory === null || !isDirectory(directory)) return missing(identity, version);
  if (!inside(directory, root)) {
    return fail(403, 'outsideCache', `the cached ${identity.plugin}@${identity.marketplace} ${version} resolves outside the plugin cache, so it is not read`);
  }
  return { ok: true, value: { root, directory } };
}

/** Reads one directory's files in name order. A symlink is followed only to a regular file inside the root. */
function walk(directory: string, root: string, relative: string, files: ExtensionFile[]): Refusal | null {
  for (const name of readdirSync(directory).sort()) {
    const path = join(directory, name);
    const label = relative === '' ? name : `${relative}/${name}`;
    const stat = lstatSync(path);
    if (stat.isSymbolicLink()) {
      const target = realpathOrNull(path);
      if (target === null || !inside(target, root)) {
        return refused(403, 'outsideCache', `${label} is a link to a place outside the plugin cache, so the promotion is refused`);
      }
      if (!isFile(target)) return refused(400, 'unsupportedLink', `${label} is a link to something other than a file`);
      const failure = take(target, label, files);
      if (failure !== null) return failure;
    } else if (stat.isDirectory()) {
      const failure = walk(path, root, label, files);
      if (failure !== null) return failure;
    } else if (stat.isFile()) {
      const failure = take(path, label, files);
      if (failure !== null) return failure;
    } else {
      return refused(400, 'unsupportedFile', `${label} is neither a file nor a directory`);
    }
  }
  return null;
}

function take(path: string, label: string, files: ExtensionFile[]): Refusal | null {
  const text = readText(path);
  if (text === null) return refused(400, 'notText', `${label} is not UTF-8 text, so the cached copy cannot be promoted`);
  files.push({ path: label, text });
  return null;
}

function missing(identity: PluginIdentity, version: string): Resolution {
  return fail(404, 'noCachedVersion', `the plugin cache holds no copy of ${identity.plugin}@${identity.marketplace} at ${version}`);
}

function refused(status: number, reason: string, message: string): Refusal {
  return { status, reason, message };
}

function fail(status: number, reason: string, message: string): { ok: false; refusal: Refusal } {
  return { ok: false, refusal: refused(status, reason, message) };
}

/** Whether `path`, already resolved, is `root` or lies beneath it. */
function inside(path: string, root: string): boolean {
  return path === root || path.startsWith(root + sep);
}

function realpathOrNull(path: string): string | null {
  try {
    return realpathSync(path);
  } catch {
    return null;
  }
}

function lstatOrNull(path: string): Stats | null {
  try {
    return lstatSync(path);
  } catch {
    return null;
  }
}

function isDirectory(path: string): boolean {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
}

function isFile(path: string): boolean {
  try {
    return statSync(path).isFile();
  } catch {
    return false;
  }
}

function readText(path: string): string | null {
  try {
    return new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(readFileSync(path));
  } catch {
    return null;
  }
}
