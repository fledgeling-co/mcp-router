import {
  existsSync,
  lstatSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { dirname, join } from 'node:path';

/*
 * The router's extension store: skills, plugins and marketplaces, one directory per entry.
 *
 * This is the on-disk format the Swift store wrote (app/Sources/RouterCore/Extensions), kept so that an
 * entry written by either router reads back in the other:
 *
 *   <root>/<kind>/<name>/<descriptor>     one entry; the descriptor file says what it is
 *   <root>/.staging/                      a write lands here, then is renamed into place
 *   <root>/.removed/<kind>/<name>/<ms>/   a removed entry is moved here, never deleted
 *
 * There is no index. Every listing reads the directory, so nothing can disagree with the bytes on disk.
 * Nothing outside `root` is read or written.
 */

export const KINDS = ['skills', 'plugins', 'marketplaces'] as const;
export type ExtensionKind = (typeof KINDS)[number];

/** The path, inside one entry, of the file that says what the entry is. */
export const DESCRIPTOR_PATH: Record<ExtensionKind, string> = {
  skills: 'SKILL.md',
  plugins: '.claude-plugin/plugin.json',
  marketplaces: '.claude-plugin/marketplace.json',
};

/** What one entry of a kind is called in a sentence, matching `no server named "x"`. */
export const SINGULAR: Record<ExtensionKind, string> = {
  skills: 'skill',
  plugins: 'plugin',
  marketplaces: 'marketplace',
};

export const MAX_NAME_LENGTH = 128;

export interface ExtensionFile {
  /** A relative path inside the entry. */
  path: string;
  text: string;
}

/**
 * One entry as it exists on disk right now. Every field is a reading, not something remembered from
 * the request that added it. `problem` is set when the entry cannot be read as its kind, and the entry
 * is still listed: dropping it would report a store with a broken entry as one entry fewer.
 */
export interface ExtensionRecord {
  name: string;
  title: string | null;
  description: string | null;
  version: string | null;
  files: number;
  bytes: number;
  problem: string | null;
}

export interface ExtensionListing {
  kind: ExtensionKind;
  root: string;
  records: ExtensionRecord[];
  /** Set when the kind directory exists but could not be read. Distinct from an empty store. */
  unreadable: string | null;
}

export interface Refusal {
  status: number;
  /** The stable slug a caller branches on. */
  reason: string;
  /** The sentence a person reads. */
  message: string;
}

export type WriteOutcome =
  | { outcome: 'added'; record: ExtensionRecord }
  | { outcome: 'refused'; refusal: Refusal };

export type RemoveOutcome =
  | { outcome: 'removed'; restorePath: string }
  | { outcome: 'refused'; refusal: Refusal };

/** `restore` is the stamp an undo is given to find the copy this promotion replaced. */
export type PromoteOutcome =
  | { outcome: 'promoted'; record: ExtensionRecord; replaced: string | null; restore: string }
  | { outcome: 'refused'; refusal: Refusal };

export type UndoOutcome =
  | { outcome: 'undone'; record: ExtensionRecord; withdrawn: string }
  | { outcome: 'refused'; refusal: Refusal };

export type KeepOutcome = { outcome: 'kept' } | { outcome: 'refused'; refusal: Refusal };

/**
 * What a promotion did, written down before anything moves. An undo reads it back and checks the installed
 * version against `pluginVersion` before it touches a byte, so an undo refuses rather than overwrite a version
 * that was installed after the promotion.
 */
interface Promotion {
  kind: ExtensionKind;
  name: string;
  /** The version the promotion installed. */
  pluginVersion: string;
  /** The version it replaced, or null when the replaced entry declared none. */
  replacedVersion: string | null;
  /** The stamp of the undo that reversed it, or null while it stands. */
  undoneAt: string | null;
}

// MARK: - Naming

/** One path segment: ASCII letters, digits, `.`, `_`, `-` and `@`, never `.` or `..` alone. */
const SEGMENT = /^[A-Za-z0-9._@-]+$/;

export function isWellFormedSegment(segment: string): boolean {
  return segment !== '' && segment !== '.' && segment !== '..' && SEGMENT.test(segment);
}

/** An entry's own name: one well-formed segment that does not begin with a dot. */
export function isWellFormedName(name: string): boolean {
  return name.length > 0 && name.length <= MAX_NAME_LENGTH && !name.startsWith('.') && isWellFormedSegment(name);
}

/** A restore reference is the millisecond stamp a promotion or removal was given: digits only. */
export function isWellFormedStamp(stamp: string): boolean {
  return /^[0-9]+$/.test(stamp);
}

/** A relative file path inside one entry: at least one segment, every segment well-formed. */
export function isWellFormedRelativePath(path: string): boolean {
  if (path === '' || path.startsWith('/')) return false;
  return path.split('/').every(isWellFormedSegment);
}

// MARK: - Descriptors

/** What a descriptor says about its entry, or why it could not be read as one. */
export interface Reading {
  title: string;
  description: string | null;
  version: string | null;
}

export type DescriptorOutcome = { ok: true; reading: Reading } | { ok: false; problem: string };

/** One rule, applied to the bytes in a request before anything is written, and to the bytes on disk on every read. */
export function readDescriptor(kind: ExtensionKind, text: string): DescriptorOutcome {
  return kind === 'skills' ? readFrontmatter(text) : readManifest(text, kind === 'marketplaces');
}

/**
 * The YAML frontmatter a skill carries: a `---` line, `key: value` lines, a closing `---`. Deliberately
 * not a YAML parser; a key it does not recognise is ignored rather than refused.
 */
function readFrontmatter(text: string): DescriptorOutcome {
  const file = DESCRIPTOR_PATH.skills;
  const lines = text.split('\n');
  if (trimBlank(lines[0]) !== '---') {
    return { ok: false, problem: `${file} does not open with a --- frontmatter block` };
  }
  let title: string | null = null;
  let description: string | null = null;
  let version: string | null = null;
  let closed = false;
  for (const line of lines.slice(1)) {
    if (trimBlank(line) === '---') {
      closed = true;
      break;
    }
    const separator = line.indexOf(':');
    if (separator < 0) continue;
    const key = trimBlank(line.slice(0, separator));
    const value = trimBlank(line.slice(separator + 1));
    if (key === 'name' && value) title = value;
    if (key === 'description' && value) description = value;
    if (key === 'version' && value) version = value;
  }
  if (!closed) return { ok: false, problem: `${file}'s frontmatter block is never closed by a second ---` };
  if (title === null) return { ok: false, problem: `${file}'s frontmatter carries no name` };
  return { ok: true, reading: { title, description, version } };
}

/** `plugin.json` and `marketplace.json`. A marketplace must also carry a `plugins` array. */
function readManifest(text: string, requiresPlugins: boolean): DescriptorOutcome {
  const file = requiresPlugins ? DESCRIPTOR_PATH.marketplaces : DESCRIPTOR_PATH.plugins;
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return { ok: false, problem: `${file} is not valid JSON` };
  }
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
    return { ok: false, problem: `${file} is not a JSON object` };
  }
  const object = parsed as Record<string, unknown>;
  if (typeof object.name !== 'string' || object.name === '') {
    return { ok: false, problem: `${file} carries no name` };
  }
  if (requiresPlugins && !Array.isArray(object.plugins)) {
    return { ok: false, problem: `${file} carries no plugins array` };
  }
  return {
    ok: true,
    reading: { title: object.name, description: nonEmpty(object.description), version: nonEmpty(object.version) },
  };
}

function nonEmpty(value: unknown): string | null {
  return typeof value === 'string' && value !== '' ? value : null;
}

/** Spaces and tabs only, which is what the Swift frontmatter scan trims. */
function trimBlank(text: string): string {
  return text.replace(/^[ \t]+|[ \t]+$/g, '');
}

// MARK: - Store

/**
 * The store, rooted at one directory. `now` stamps a removal and a staged write, so a test can pin
 * the time; the router passes `Date.now`.
 */
export class ExtensionStore {
  readonly root: string;
  private readonly now: () => number;

  constructor(root: string, now: () => number = () => Date.now()) {
    this.root = root;
    this.now = now;
  }

  directory(kind: ExtensionKind): string {
    return join(this.root, kind);
  }

  /** Enumerated from the directory on every call. A store nobody has written yet is empty, not unreadable. */
  list(kind: ExtensionKind): ExtensionListing {
    const directory = this.directory(kind);
    if (!isDirectory(directory)) return { kind, root: directory, records: [], unreadable: null };
    let names: string[];
    try {
      names = readdirSync(directory);
    } catch (error) {
      return { kind, root: directory, records: [], unreadable: `${directory} could not be read: ${errorText(error)}` };
    }
    // Dotted names are the operating system's litter, not entries: nothing this store writes can be one.
    const entries = names.filter((name) => !name.startsWith('.')).sort();
    return { kind, root: directory, records: entries.map((name) => this.record(kind, name)), unreadable: null };
  }

  read(kind: ExtensionKind, name: string): ExtensionRecord | null {
    if (!isWellFormedName(name) || !isDirectory(this.entryPath(kind, name))) return null;
    return this.record(kind, name);
  }

  /** The text of one entry's descriptor, or null when the name is not well formed or the file is not readable UTF-8. */
  descriptorText(kind: ExtensionKind, name: string): string | null {
    if (!isWellFormedName(name)) return null;
    return readUtf8(join(this.entryPath(kind, name), DESCRIPTOR_PATH[kind]));
  }

  /**
   * Validate everything, stage the whole entry, then move it into place. Every refusal happens before a
   * byte is written, so a malformed request leaves nothing behind.
   */
  add(kind: ExtensionKind, name: string, files: ExtensionFile[]): WriteOutcome {
    const refusal = refuseAdd(kind, name, files);
    if (refusal) return { outcome: 'refused', refusal };
    const destination = this.entryPath(kind, name);
    if (existsSync(destination)) {
      return {
        outcome: 'refused',
        refusal: { status: 409, reason: 'nameTaken', message: `a ${SINGULAR[kind]} named "${name}" already exists` },
      };
    }
    // Nothing between this check and the rename yields, so no second add in this process can take the name.
    const staging = join(this.root, '.staging', `${kind}-${name}-${this.stamp()}`);
    try {
      writeFiles(files, staging);
      mkdirSync(this.directory(kind), { recursive: true });
      renameSync(staging, destination);
    } catch (error) {
      rmSync(staging, { recursive: true, force: true });
      return {
        outcome: 'refused',
        refusal: { status: 500, reason: 'writeFailed', message: `${name} could not be written: ${errorText(error)}` },
      };
    }
    // Read back from disk, so the reply says what the store holds rather than what the request said.
    const record = this.read(kind, name);
    if (!record) {
      return {
        outcome: 'refused',
        refusal: { status: 500, reason: 'writeFailed', message: `${name} was written and could not be read back` },
      };
    }
    return { outcome: 'added', record };
  }

  /** Moved, never deleted. The outcome names where the bytes went, which is what makes a removal reversible. */
  remove(kind: ExtensionKind, name: string): RemoveOutcome {
    if (!isWellFormedName(name)) return { outcome: 'refused', refusal: invalidName(name) };
    const entry = this.entryPath(kind, name);
    if (!existsSync(entry)) return { outcome: 'refused', refusal: unknownEntry(kind, name) };
    const destination = join(this.root, '.removed', kind, name, this.stamp());
    try {
      mkdirSync(dirname(destination), { recursive: true });
      if (existsSync(destination)) throw new Error(`${destination} already exists`);
      renameSync(entry, destination);
    } catch (error) {
      return {
        outcome: 'refused',
        refusal: {
          status: 500,
          reason: 'removeFailed',
          message: `${name} could not be moved aside: ${errorText(error)}`,
        },
      };
    }
    return { outcome: 'removed', restorePath: destination };
  }

  /**
   * Replace an installed entry with a newer version of it. The entry it replaces is moved aside, never deleted,
   * and the promotion is written down before anything moves, so an undo can check what it reverses. Every
   * refusal happens before a byte moves, and a failure part-way puts the entry back where it was.
   */
  promote(kind: ExtensionKind, name: string, pluginVersion: string, files: ExtensionFile[]): PromoteOutcome {
    const refusal = refuseAdd(kind, name, files) ?? refuseVersion(kind, pluginVersion, files);
    if (refusal) return { outcome: 'refused', refusal };
    const current = this.read(kind, name);
    if (!current) return { outcome: 'refused', refusal: unknownEntry(kind, name) };
    if (current.version === pluginVersion) {
      return {
        outcome: 'refused',
        refusal: { status: 409, reason: 'sameVersion', message: `${name} is already at version ${pluginVersion}` },
      };
    }

    const stamp = this.stamp();
    const entry = this.entryPath(kind, name);
    const restoreDir = join(this.root, '.removed', kind, name, stamp);
    const staging = join(this.root, '.staging', `promote-${kind}-${name}-${stamp}`);
    const promotionFile = this.promotionPath(kind, name, stamp);
    const promotion: Promotion = { kind, name, pluginVersion, replacedVersion: current.version, undoneAt: null };
    let movedAside = false;
    try {
      writeJsonAtomic(promotionFile, promotion);
      writeFiles(files, staging);
      mkdirSync(dirname(restoreDir), { recursive: true });
      if (existsSync(restoreDir)) throw new Error(`${restoreDir} already exists`);
      renameSync(entry, restoreDir);
      movedAside = true;
      renameSync(staging, entry);
    } catch (error) {
      const rollback = [
        tryStep(() => rmSync(staging, { recursive: true, force: true })),
        tryStep(() => rmSync(promotionFile, { force: true })),
        movedAside ? tryStep(() => renameSync(restoreDir, entry)) : null,
      ];
      return { outcome: 'refused', refusal: writeRefusal(`${name} could not be promoted`, error, rollback) };
    }
    const record = this.read(kind, name);
    if (!record) {
      return {
        outcome: 'refused',
        refusal: { status: 500, reason: 'writeFailed', message: `${name} was promoted and could not be read back` },
      };
    }
    return { outcome: 'promoted', record, replaced: current.version, restore: stamp };
  }

  /**
   * Put back the entry a promotion replaced. Refuses when the installed version is no longer the one the
   * promotion installed, or when the replaced copy is gone, and nothing moves in either case. The promoted
   * copy is moved aside rather than deleted, so the undo is itself reversible.
   */
  undoPromotion(kind: ExtensionKind, name: string, restore: string): UndoOutcome {
    if (!isWellFormedName(name)) return { outcome: 'refused', refusal: invalidName(name) };
    if (!isWellFormedStamp(restore)) {
      return {
        outcome: 'refused',
        refusal: { status: 400, reason: 'invalidRestore', message: `"${restore}" is not a restore reference` },
      };
    }
    const promotion = this.readPromotion(kind, name, restore);
    if (!promotion) {
      return {
        outcome: 'refused',
        refusal: {
          status: 404,
          reason: 'unknown',
          message: `no promotion of ${SINGULAR[kind]} "${name}" is recorded at ${restore}`,
        },
      };
    }
    if (promotion.undoneAt !== null) {
      return {
        outcome: 'refused',
        refusal: { status: 409, reason: 'alreadyUndone', message: `that promotion of ${name} was already undone` },
      };
    }
    const current = this.read(kind, name);
    if (!current) {
      return {
        outcome: 'refused',
        refusal: {
          status: 409,
          reason: 'installedChanged',
          message: `${name} is no longer installed, so the promotion has no installed version to reverse`,
        },
      };
    }
    if (current.version !== promotion.pluginVersion) {
      return {
        outcome: 'refused',
        refusal: {
          status: 409,
          reason: 'installedChanged',
          message:
            `${name} is at version ${current.version ?? 'none'}, not the ${promotion.pluginVersion} this promotion ` +
            'installed, so undoing it would overwrite that version',
        },
      };
    }
    const restoreDir = join(this.root, '.removed', kind, name, restore);
    if (!isDirectory(restoreDir)) {
      return {
        outcome: 'refused',
        refusal: {
          status: 409,
          reason: 'restoreMissing',
          message: `the copy of ${name} this promotion replaced is no longer in the restore area`,
        },
      };
    }

    const stamp = this.stamp();
    const entry = this.entryPath(kind, name);
    const aside = join(this.root, '.removed', kind, name, stamp);
    const promotionFile = this.promotionPath(kind, name, restore);
    let movedAside = false;
    try {
      writeJsonAtomic(promotionFile, { ...promotion, undoneAt: stamp });
      mkdirSync(dirname(aside), { recursive: true });
      if (existsSync(aside)) throw new Error(`${aside} already exists`);
      renameSync(entry, aside);
      movedAside = true;
      renameSync(restoreDir, entry);
    } catch (error) {
      const rollback = [
        tryStep(() => writeJsonAtomic(promotionFile, promotion)),
        movedAside ? tryStep(() => renameSync(aside, entry)) : null,
      ];
      return { outcome: 'refused', refusal: writeRefusal(`${name} could not be restored`, error, rollback) };
    }
    const record = this.read(kind, name);
    if (!record) {
      return {
        outcome: 'refused',
        refusal: { status: 500, reason: 'writeFailed', message: `${name} was restored and could not be read back` },
      };
    }
    return { outcome: 'undone', record, withdrawn: promotion.pluginVersion };
  }

  /**
   * Record the version of a held update that was kept, so the held badge stops until a newer one arrives. It
   * needs no entry in this store, because most held plugins are not in it: the decision is about the plugin.
   */
  keep(kind: ExtensionKind, name: string, pluginVersion: string): KeepOutcome {
    if (!isWellFormedName(name)) return { outcome: 'refused', refusal: invalidName(name) };
    try {
      writeJsonAtomic(this.keptPath(kind, name), { pluginVersion, keptAt: this.stamp() });
    } catch (error) {
      return {
        outcome: 'refused',
        refusal: { status: 500, reason: 'writeFailed', message: `${name} could not be recorded: ${errorText(error)}` },
      };
    }
    return { outcome: 'kept' };
  }

  /** The held version a keep recorded for this entry, or null when none was kept or the record cannot be read. */
  keptVersion(kind: ExtensionKind, name: string): string | null {
    if (!isWellFormedName(name)) return null;
    const text = readUtf8(this.keptPath(kind, name));
    if (text === null) return null;
    try {
      const parsed = JSON.parse(text) as { pluginVersion?: unknown };
      return typeof parsed.pluginVersion === 'string' ? parsed.pluginVersion : null;
    } catch {
      return null;
    }
  }

  private promotionPath(kind: ExtensionKind, name: string, stamp: string): string {
    return join(this.root, '.promotions', kind, name, `${stamp}.json`);
  }

  private keptPath(kind: ExtensionKind, name: string): string {
    return join(this.root, '.kept', kind, `${name}.json`);
  }

  private readPromotion(kind: ExtensionKind, name: string, stamp: string): Promotion | null {
    const text = readUtf8(this.promotionPath(kind, name, stamp));
    if (text === null) return null;
    try {
      return JSON.parse(text) as Promotion;
    } catch {
      // A manifest that does not parse names no promotion this store can undo.
      return null;
    }
  }

  private entryPath(kind: ExtensionKind, name: string): string {
    return join(this.directory(kind), name);
  }

  private stamp(): string {
    return String(Math.trunc(this.now()));
  }

  private record(kind: ExtensionKind, name: string): ExtensionRecord {
    const entry = this.entryPath(kind, name);
    if (!isDirectory(entry)) return unread(name, 0, 0, `${name} is not a directory`);
    const { files, bytes } = walkFiles(entry);
    const descriptor = DESCRIPTOR_PATH[kind];
    const text = readUtf8(join(entry, descriptor));
    if (text === null) return unread(name, files, bytes, `${descriptor} is missing or is not UTF-8`);
    const outcome = readDescriptor(kind, text);
    if (!outcome.ok) return unread(name, files, bytes, outcome.problem);
    return {
      name,
      title: outcome.reading.title,
      description: outcome.reading.description,
      version: outcome.reading.version,
      files,
      bytes,
      problem: null,
    };
  }
}

function unread(name: string, files: number, bytes: number, problem: string): ExtensionRecord {
  return { name, title: null, description: null, version: null, files, bytes, problem };
}

function refuseAdd(kind: ExtensionKind, name: string, files: ExtensionFile[]): Refusal | null {
  if (!isWellFormedName(name)) return invalidName(name);
  if (files.length === 0) {
    return { status: 400, reason: 'noFiles', message: `a ${SINGULAR[kind]} needs at least ${DESCRIPTOR_PATH[kind]}` };
  }
  const seen: string[] = [];
  for (const file of files) {
    if (!isWellFormedRelativePath(file.path)) {
      return {
        status: 400,
        reason: 'invalidFilePath',
        message: `"${file.path}" is not a relative path inside the entry`,
      };
    }
    if (seen.includes(file.path)) {
      return {
        status: 400,
        reason: 'duplicateFilePath',
        message: `"${file.path}" is given twice, so one copy would be lost`,
      };
    }
    seen.push(file.path);
  }
  const descriptor = files.find((file) => file.path === DESCRIPTOR_PATH[kind]);
  if (!descriptor) {
    return {
      status: 400,
      reason: 'missingDescriptor',
      message: `a ${SINGULAR[kind]} must carry ${DESCRIPTOR_PATH[kind]}`,
    };
  }
  // The descriptor has to parse and name the entry it is being added as. Otherwise the directory and the
  // descriptor disagree, and ingestion could not tell one entry from two.
  const outcome = readDescriptor(kind, descriptor.text);
  if (!outcome.ok) return { status: 400, reason: 'malformedDescriptor', message: outcome.problem };
  if (outcome.reading.title !== name) {
    return {
      status: 400,
      reason: 'nameMismatch',
      message: `${DESCRIPTOR_PATH[kind]} names "${outcome.reading.title}", which is not the "${name}" it is being added as`,
    };
  }
  return null;
}

function invalidName(name: string): Refusal {
  return {
    status: 400,
    reason: 'invalidName',
    message:
      `"${name}" is not a usable name: letters, digits, dot, underscore and hyphen only, no leading dot, ` +
      `at most ${MAX_NAME_LENGTH} characters`,
  };
}

function unknownEntry(kind: ExtensionKind, name: string): Refusal {
  return { status: 404, reason: 'unknown', message: `no ${SINGULAR[kind]} named "${name}"` };
}

/**
 * The files must declare the version the promotion names. A promotion that says 2.0.0 and carries 1.0.0 is
 * refused before anything is written, because the version recorded beside the entry would then be a lie.
 */
function refuseVersion(kind: ExtensionKind, pluginVersion: string, files: ExtensionFile[]): Refusal | null {
  const descriptor = files.find((file) => file.path === DESCRIPTOR_PATH[kind]);
  const outcome = descriptor ? readDescriptor(kind, descriptor.text) : null;
  const declared = outcome !== null && outcome.ok ? outcome.reading.version : null;
  if (declared === pluginVersion) return null;
  const file = DESCRIPTOR_PATH[kind];
  return {
    status: 400,
    reason: 'versionMismatch',
    message:
      declared === null
        ? `${file} declares no version, so it cannot be promoted as ${pluginVersion}`
        : `${file} declares ${declared}, not the ${pluginVersion} being promoted`,
  };
}

/** A failed write answers 500 and says what was attempted. A rollback that also failed is named beside it. */
function writeRefusal(sentence: string, error: unknown, rollback: Array<string | null>): Refusal {
  const failed = rollback.filter((step): step is string => step !== null);
  const tail = failed.length === 0 ? '' : `; the rollback also failed, so the entry may need putting back by hand: ${failed.join('; ')}`;
  return { status: 500, reason: 'writeFailed', message: `${sentence}: ${errorText(error)}${tail}` };
}

/** One step of a rollback. A step that fails is reported beside the failure that started it, never thrown past it. */
function tryStep(step: () => void): string | null {
  try {
    step();
    return null;
  } catch (error) {
    return errorText(error);
  }
}

/** A small record in one step: written beside its destination, then renamed into place. */
function writeJsonAtomic(path: string, value: unknown): void {
  mkdirSync(dirname(path), { recursive: true });
  const temporary = `${path}.tmp`;
  writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
  renameSync(temporary, path);
}

function writeFiles(files: ExtensionFile[], staging: string): void {
  mkdirSync(staging, { recursive: true });
  for (const file of files) {
    const path = join(staging, file.path);
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, file.text, 'utf8');
  }
}

/** How many files an entry holds and how many bytes they come to. Both counted from disk on every read. */
function walkFiles(entry: string): { files: number; bytes: number } {
  let files = 0;
  let bytes = 0;
  const visit = (dir: string): void => {
    let names: string[];
    try {
      names = readdirSync(dir);
    } catch {
      return;
    }
    for (const name of names) {
      const path = join(dir, name);
      // A symbolic link to a directory is not descended into, and is not counted as a file either.
      if (isDirectory(path)) {
        if (lstatSync(path).isDirectory()) visit(path);
        continue;
      }
      files += 1;
      bytes += sizeOf(path);
    }
  };
  visit(entry);
  return { files, bytes };
}

function isDirectory(path: string): boolean {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
}

function sizeOf(path: string): number {
  try {
    return lstatSync(path).size;
  } catch {
    return 0;
  }
}

function readUtf8(path: string): string | null {
  try {
    return new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(readFileSync(path));
  } catch {
    return null;
  }
}

function errorText(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
