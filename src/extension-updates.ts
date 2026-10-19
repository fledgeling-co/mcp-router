import { existsSync, lstatSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { DESCRIPTOR_PATH, isWellFormedName, KINDS, type ExtensionKind, type ExtensionRecord, type ExtensionStore } from './extensions.js';

/*
 * F6, the marketplace update check. A port of ExtensionFreshness, ExtensionFreshnessScan, MarketplaceCatalogue and
 * SemanticVersion (app/Sources/RouterCore/Extensions), and of ControlUpdatesJSON.swift for the wire.
 *
 * It reads the store and nothing else. It reaches no network and spawns no child, so the age of each catalogue is
 * the evidence a caller has, and `staleAfterMs` says where that evidence stops being fresh.
 *
 * The verdict is eight states and not a boolean. Measured on the machine this product runs on: a version delta
 * against the catalogue finds zero updates over 127 plugins, and finds one difference that points backwards. A
 * report that said "0 updates" would read the same whether it compared everything or nothing, so `compared` and
 * `uncomparable` both travel with the count.
 */

/** One day. The interval the brief's own example names. */
export const DEFAULT_STALE_AFTER_MS = 86_400_000;

export type VerdictState =
  | 'update-available'
  | 'current'
  | 'catalogue-behind'
  | 'unorderable'
  | 'installed-declares-no-version'
  | 'catalogue-declares-no-version'
  | 'not-offered'
  | 'no-catalogue';

/** What comparing one installed entry against one catalogue produced. Only `update-available` costs an install. */
export interface FreshnessVerdict {
  state: VerdictState;
  installed: string | null;
  available: string | null;
  hasUpdate: boolean;
  /** Whether two versions were put side by side. */
  compared: boolean;
  /** What a person reads. It names the versions rather than saying something was wrong. */
  sentence: string;
}

const COMPARED: ReadonlySet<VerdictState> = new Set(['update-available', 'current', 'catalogue-behind', 'unorderable']);

function verdict(state: VerdictState, installed: string | null, available: string | null, sentence: string): FreshnessVerdict {
  return { state, installed, available, hasUpdate: state === 'update-available', compared: COMPARED.has(state), sentence };
}

// MARK: - Versions

export interface ParsedVersion {
  major: number;
  minor: number;
  patch: number;
  /** What followed the patch number, e.g. `-beta.1`. Empty when there was nothing. */
  suffix: string;
}

/**
 * `major.minor.patch` with an optional suffix. A leading `v` is accepted; nothing else is normalised. A two-part
 * `1.2` is not padded to `1.2.0`, because a version this cannot read is one it declines to order.
 */
export function parseVersion(text: string): ParsedVersion | null {
  let body = text.replace(/^[ \t]+|[ \t]+$/g, '');
  if (body.startsWith('v')) body = body.slice(1);
  if (body === '') return null;
  const numbers: number[] = [];
  let index = 0;
  while (numbers.length < 3) {
    const digits = /^[0-9]+/.exec(body.slice(index))?.[0];
    if (digits === undefined || digits.length > 9) return null;
    numbers.push(Number(digits));
    index += digits.length;
    if (numbers.length < 3) {
      if (body[index] !== '.') return null;
      index += 1;
    }
  }
  const suffix = body.slice(index);
  // `1.2.3rc1` is not a version: a separator has to be there.
  if (suffix !== '' && !suffix.startsWith('-') && !suffix.startsWith('+')) return null;
  return { major: numbers[0], minor: numbers[1], patch: numbers[2], suffix };
}

/** `null` when either side cannot be parsed. No ordering is invented for them. */
export function compareVersions(lhs: string, rhs: string): 'ascending' | 'descending' | 'same' | null {
  const left = parseVersion(lhs);
  const right = parseVersion(rhs);
  if (!left || !right) return null;
  const order = compareParsed(left, right);
  if (order === 0) return 'same';
  return order < 0 ? 'ascending' : 'descending';
}

function compareParsed(left: ParsedVersion, right: ParsedVersion): number {
  if (left.major !== right.major) return left.major - right.major;
  if (left.minor !== right.minor) return left.minor - right.minor;
  if (left.patch !== right.patch) return left.patch - right.patch;
  if (left.suffix === right.suffix) return 0;
  // A release outranks any pre-release of the same numbers, which is semver's own rule.
  if ((left.suffix === '') !== (right.suffix === '')) return left.suffix === '' ? 1 : -1;
  return left.suffix < right.suffix ? -1 : 1;
}

// MARK: - Catalogues

export class CatalogueOffer {
  constructor(
    readonly name: string,
    /** `undefined` when the catalogue names the plugin and declares no version for it. */
    readonly version: string | undefined
  ) {}
}

/** What a marketplace descriptor offers. `declaredNoVersion` is a count, so 291 names with 14 versions cannot read as 14. */
export class MarketplaceCatalogue {
  readonly declaredNoVersion: number;

  constructor(readonly offers: CatalogueOffer[]) {
    this.declaredNoVersion = offers.filter((offer) => offer.version === undefined).length;
  }

  offer(name: string): CatalogueOffer | undefined {
    return this.offers.find((offer) => offer.name === name);
  }
}

/**
 * `null` when the text is not a marketplace descriptor at all. An entry with no name is skipped rather than refusing
 * the whole catalogue: one malformed offer among 291 must not take the other 290 with it.
 */
export function readCatalogue(text: string): MarketplaceCatalogue | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return null;
  }
  if (!isObject(parsed) || !Array.isArray(parsed.plugins)) return null;
  const offers: CatalogueOffer[] = [];
  for (const entry of parsed.plugins as unknown[]) {
    if (!isObject(entry) || typeof entry.name !== 'string' || entry.name === '') continue;
    const version = typeof entry.version === 'string' && entry.version !== '' ? entry.version : undefined;
    offers.push(new CatalogueOffer(entry.name, version));
  }
  return new MarketplaceCatalogue(offers);
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

// MARK: - Comparing

export interface FreshnessInput {
  installed: string | null;
  offer: CatalogueOffer | null;
  /** Why the catalogue could not be read, or null. Only the read-failure reaches a verdict, not the age. */
  problem: string | null;
}

/**
 * The order of the guards is the design. The two absent-version rows come before the equality check, because two
 * absent versions are not two equal versions, and `null === null` would report 557 uncomparable offers as current.
 */
export function compareFreshness({ installed, offer, problem }: FreshnessInput): FreshnessVerdict {
  if (problem !== null) return verdict('no-catalogue', null, null, problem);
  if (offer === null) return verdict('not-offered', null, null, 'the catalogue was read and does not offer this entry');
  if (offer.version === undefined) {
    return verdict('catalogue-declares-no-version', installed, null, 'the catalogue names this entry and declares no version for it');
  }
  const available = offer.version;
  if (installed === null) {
    return verdict('installed-declares-no-version', null, null, "this entry's descriptor declares no version, so there is nothing to compare");
  }
  if (installed === available) return verdict('current', installed, installed, `${installed} is installed and is what the catalogue offers`);
  switch (compareVersions(installed, available)) {
    case 'ascending':
      return verdict('update-available', installed, available, `${available} is offered and ${installed} is installed`);
    case 'descending':
      return verdict(
        'catalogue-behind',
        installed,
        available,
        `the catalogue offers ${available} and ${installed} is installed, so this copy of the catalogue is behind rather than the install`
      );
    case 'same':
      return verdict('current', installed, installed, `${installed} is installed and is what the catalogue offers`);
    default:
      return verdict(
        'unorderable',
        installed,
        available,
        `${installed} and ${available} differ and neither pair is orderable, so which is newer cannot be said`
      );
  }
}

// MARK: - The report

export interface CatalogueReading {
  name: string;
  path: string;
  /** Null when the tree could not be measured. Never 0, which would read as "just refreshed". */
  newestModifiedMs: number | null;
  /** Null when the age is unknown, including a catalogue stamped ahead of the clock. */
  ageMs: number | null;
  /** False when the age is unknown: an unknown age is reported, not assumed stale. */
  stale: boolean;
  /** True when the entry holds a `.git` directory. */
  refreshable: boolean;
  offers: number;
  declaredNoVersion: number;
  problem: string | null;
  ageProblem: string | null;
}

export interface FreshnessRow {
  kind: ExtensionKind;
  name: string;
  catalogue: string | null;
  verdict: FreshnessVerdict;
}

export interface FreshnessSummary {
  total: number;
  updatesAvailable: number;
  compared: number;
  uncomparable: number;
  staleCatalogues: number;
}

export interface FreshnessReport {
  rows: FreshnessRow[];
  catalogues: CatalogueReading[];
  summary: FreshnessSummary;
  checkedAtMs: number;
  staleAfterMs: number;
  /** A kind whose directory could not be read, with the reason. Distinct from an empty store. */
  unreadable: string[];
}

export interface FreshnessOptions {
  kinds?: readonly ExtensionKind[];
  staleAfterMs?: number;
  now: number;
  /** Ask about one entry. Absent means every entry of the kinds asked for. */
  name?: string;
}

/** Reads the store and nothing else. A catalogue is read at most once, and only when a row needs it. */
export function buildFreshnessReport(store: ExtensionStore, options: FreshnessOptions): FreshnessReport {
  const staleAfterMs = options.staleAfterMs ?? DEFAULT_STALE_AFTER_MS;
  const context = new Catalogues(store, staleAfterMs, options.now);
  const rows: FreshnessRow[] = [];
  const unreadable: string[] = [];
  for (const kind of options.kinds ?? KINDS) {
    const listing = store.list(kind);
    if (listing.unreadable !== null) unreadable.push(listing.unreadable);
    for (const record of listing.records) {
      if (options.name !== undefined && record.name !== options.name) continue;
      rows.push(context.row(kind, record));
    }
  }
  const catalogues = context.readings();
  return { rows, catalogues, summary: summarise(rows, catalogues), checkedAtMs: options.now, staleAfterMs, unreadable };
}

function summarise(rows: FreshnessRow[], catalogues: CatalogueReading[]): FreshnessSummary {
  const compared = rows.filter((row) => row.verdict.compared).length;
  return {
    total: rows.length,
    updatesAvailable: rows.filter((row) => row.verdict.hasUpdate).length,
    compared,
    uncomparable: rows.length - compared,
    staleCatalogues: catalogues.filter((catalogue) => catalogue.stale).length,
  };
}

interface Memo {
  reading: CatalogueReading;
  catalogue: MarketplaceCatalogue | null;
}

class Catalogues {
  private readonly memo = new Map<string, Memo>();

  constructor(
    private readonly store: ExtensionStore,
    private readonly staleAfterMs: number,
    private readonly now: number
  ) {}

  readings(): CatalogueReading[] {
    return [...this.memo.values()]
      .map((memo) => memo.reading)
      .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  }

  row(kind: ExtensionKind, record: ExtensionRecord): FreshnessRow {
    if (kind === 'plugins') return this.pluginRow(record);
    if (kind === 'skills') {
      const verdictOf =
        record.version === null
          ? verdict('installed-declares-no-version', null, null, "this entry's descriptor declares no version, so there is nothing to compare")
          : verdict(
              'no-catalogue',
              null,
              null,
              `no catalogue in this store offers a skill, so ${record.name}'s declared version has nothing to be compared against`
            );
      return { kind, name: record.name, catalogue: null, verdict: verdictOf };
    }
    // A catalogue has no catalogue above it. Its own freshness is the age of its tree, reported beside this row.
    this.catalogue(record.name);
    return {
      kind,
      name: record.name,
      catalogue: record.name,
      verdict: verdict(
        'no-catalogue',
        null,
        null,
        'a marketplace is the catalogue; its freshness is the age of its own tree, reported beside this row'
      ),
    };
  }

  /** A plugin's name is `<plugin>@<marketplace>`, which is Claude's own identity for it. */
  private pluginRow(record: ExtensionRecord): FreshnessRow {
    const at = record.name.indexOf('@');
    if (at <= 0 || at === record.name.length - 1) {
      return {
        kind: 'plugins',
        name: record.name,
        catalogue: null,
        verdict: verdict(
          'no-catalogue',
          null,
          null,
          `"${record.name}" does not name a marketplace, so no catalogue can be resolved for it`
        ),
      };
    }
    const market = record.name.slice(at + 1);
    const memo = this.catalogue(market);
    return {
      kind: 'plugins',
      name: record.name,
      catalogue: market,
      verdict: compareFreshness({
        installed: record.version,
        offer: memo.catalogue?.offer(record.name.slice(0, at)) ?? null,
        problem: memo.reading.problem,
      }),
    };
  }

  private catalogue(market: string): Memo {
    const existing = this.memo.get(market);
    if (existing) return existing;
    const path = join(this.store.directory('marketplaces'), market);
    const newest = isWellFormedName(market) ? newestModifiedMs(path) : null;
    const text = this.store.descriptorText('marketplaces', market);
    const catalogue = text === null ? null : readCatalogue(text);
    // A negative age is not a young one. A catalogue stamped ahead of this router's clock (skew, a restored backup,
    // an archive with its own timestamps) has an unmeasurable age, not a small one, and a number here would make it
    // read as fresh against every window. It is null with the reason beside it.
    const raw = newest === null ? null : this.now - newest;
    const age = raw === null || raw < 0 ? null : raw;
    const problem =
      newest === null
        ? `this store holds no marketplace named "${market}", so there is no catalogue to compare against`
        : catalogue === null
          ? `"${market}"'s ${DESCRIPTOR_PATH.marketplaces} could not be read as a catalogue`
          : null;
    // Kept apart from `problem`. The catalogue still parses and its offers still compare, so this suppresses nothing.
    const ageProblem =
      newest !== null && age === null
        ? `"${market}"'s newest file is stamped ahead of this router's clock, so how old the catalogue is cannot be said`
        : null;
    const reading: CatalogueReading = {
      name: market,
      path,
      newestModifiedMs: newest,
      ageMs: age,
      stale: age === null ? false : age > this.staleAfterMs,
      refreshable: existsSync(join(path, '.git')),
      offers: catalogue?.offers.length ?? 0,
      declaredNoVersion: catalogue?.declaredNoVersion ?? 0,
      problem,
      ageProblem,
    };
    const memo = { reading, catalogue };
    this.memo.set(market, memo);
    return memo;
  }
}

/**
 * The newest modification time anywhere in a tree, in milliseconds, or null when there is no directory. It follows
 * no symbolic link, and a file it cannot stat contributes 0 rather than being skipped.
 */
function newestModifiedMs(directory: string): number | null {
  if (!isDirectory(directory)) return null;
  let newest = modifiedMs(directory);
  const visit = (dir: string): void => {
    let names: string[];
    try {
      names = readdirSync(dir);
    } catch {
      return;
    }
    for (const name of names) {
      const path = join(dir, name);
      newest = Math.max(newest, modifiedMs(path));
      if (isRealDirectory(path)) visit(path);
    }
  };
  visit(directory);
  return newest;
}

function modifiedMs(path: string): number {
  try {
    return lstatSync(path).mtimeMs;
  } catch {
    return 0;
  }
}

function isDirectory(path: string): boolean {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
}

function isRealDirectory(path: string): boolean {
  try {
    return lstatSync(path).isDirectory();
  } catch {
    return false;
  }
}

// MARK: - The wire

/**
 * The JSON `GET /extensions/updates` answers with, member for member in the Swift order. Every member is always
 * present, and an unobserved figure is null rather than 0.
 */
export function freshnessValue(report: FreshnessReport): Record<string, unknown> {
  return {
    checkedAtMs: report.checkedAtMs,
    staleAfterMs: report.staleAfterMs,
    summary: { ...report.summary },
    catalogues: report.catalogues.map((reading) => ({
      name: reading.name,
      path: reading.path,
      newestModifiedMs: reading.newestModifiedMs,
      ageMs: reading.ageMs,
      stale: reading.stale,
      refreshable: reading.refreshable,
      offers: reading.offers,
      declaredNoVersion: reading.declaredNoVersion,
      problem: reading.problem,
      ageProblem: reading.ageProblem,
    })),
    entries: report.rows.map((row) => ({
      kind: row.kind,
      name: row.name,
      catalogue: row.catalogue,
      state: row.verdict.state,
      installed: row.verdict.installed,
      available: row.verdict.available,
      hasUpdate: row.verdict.hasUpdate,
      compared: row.verdict.compared,
      reason: row.verdict.sentence,
    })),
    unreadable: report.unreadable,
  };
}
