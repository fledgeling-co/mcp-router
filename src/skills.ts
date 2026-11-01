import { existsSync, readdirSync, readFileSync, realpathSync, statSync } from 'node:fs';
import { join, sep } from 'node:path';
import { isWellFormedName, readDescriptor, type ExtensionStore } from './extensions.js';
import { compareVersions, readCatalogue, type MarketplaceCatalogue } from './extension-updates.js';
import { changelogFor, type Changelog } from './plugin-cache.js';

/*
 * GET /skills, the read the Mac and Windows Skills boards draw. A port of the Swift reader of Claude's directories
 * (app/Sources/RouterCore/Extensions: ClaudeTree, ClaudeExtensionScan, ExtensionDescriptor) and of the wire shape
 * the Mac decodes (app/Sources/MCPRouterKit/Control/SkillModels.swift).
 *
 * It reads three places under Claude's home: the skills directory, the installed-plugin register and each
 * marketplace catalogue. It writes nothing there. It reads one client's directory. Every other client is reported as
 * unknown rather than absent, because nothing here looked in its directory, and the board draws an absent key as off.
 *
 * A held version is plugin-level: a plugin whose marketplace offers a newer version than the one installed. The Swift
 * router never computed these, so `addedCapabilities` names that they were not compared. An empty list would read as
 * an update that asks for nothing, which the board counts as safe to promote. The held version carries the changelog
 * its cached copy ships (plugin-cache.ts), so the board can show what the offer says without a second read.
 *
 * Keep: a held version recorded by POST /extensions/plugins/<plugin>@<marketplace>/keep is not reported as held
 * until a version newer than the kept one is offered. A kept version that cannot be ordered against the offer is not
 * suppressed, because "newer than the kept one" cannot then be said.
 */

/** Wire values the Mac's SkillClient and SkillPresence decode. Both are closed sets there. */
type ClientStatus = 'read' | 'absent' | 'unreadable' | 'unsupported';
type Presence = 'present' | 'absent' | 'unreadable';

/** The clients the router names, in the Swift MCPClient order, with the names the board draws. */
const CLIENTS: ReadonlyArray<{ id: string; displayName: string; supportsSkills: boolean }> = [
  { id: 'claudeCode', displayName: 'Claude Code', supportsSkills: true },
  { id: 'claudeDesktop', displayName: 'Claude Desktop', supportsSkills: false },
  { id: 'codexCLI', displayName: 'Codex CLI', supportsSkills: true },
  { id: 'chatGPTCLI', displayName: 'ChatGPT CLI', supportsSkills: true },
  { id: 'cursor', displayName: 'Cursor', supportsSkills: true },
  { id: 'geminiCLI', displayName: 'Gemini CLI', supportsSkills: true },
  { id: 'grokCLI', displayName: 'grok', supportsSkills: false },
  { id: 'opencode', displayName: 'opencode', supportsSkills: true },
];

const CAPABILITIES_NOT_COMPARED = 'capabilities not compared with the installed version';

const NOT_READ_HERE = "this router reads Claude Code's skills directory only";

type Reading<T> = { ok: true; value: T } | { ok: false; problem: string };

interface InstalledPlugin {
  identity: string;
  plugin: string;
  marketplace: string;
  installPath: string;
  version: string;
}

/** A plugin whose install directory exists, resolved once so a skill can be matched to it by real path. */
interface PluginRoot extends InstalledPlugin {
  real: string;
}

interface Row {
  name: string;
  real: string;
  description: string | null;
  owner: PluginRoot | null;
}

/**
 * `GET /skills` as the board reads it. `null` where the Swift model is optional and nothing is known, never a
 * placeholder, so an absent provenance and an unrecorded one cannot be confused.
 */
export function skillsValue(claudeHome: string, store: ExtensionStore): Record<string, unknown> {
  const register = installedPlugins(join(claudeHome, 'plugins', 'installed_plugins.json'));
  const roots = register.ok ? pluginRoots(register.value) : [];
  const skillsDirectory = join(claudeHome, 'skills');
  const listing = claudeSkillNames(skillsDirectory);

  const rows = listing.names.flatMap((name): Row[] => {
    const row = readRow(skillsDirectory, name, roots);
    return row === null ? [] : [row];
  });
  const siblings = new Map<string, number>();
  for (const row of rows) {
    if (row.owner) siblings.set(row.owner.identity, (siblings.get(row.owner.identity) ?? 0) + 1);
  }

  const catalogues = new Map<string, MarketplaceCatalogue | null>();
  const heldFor = new Map<string, Record<string, unknown> | null>();
  const held = (owner: PluginRoot): Record<string, unknown> | null => {
    if (!heldFor.has(owner.identity)) {
      const count = siblings.get(owner.identity) ?? 1;
      const catalogue = catalogueOf(claudeHome, owner.marketplace, catalogues);
      heldFor.set(owner.identity, heldVersion(owner, count, store, catalogue, claudeHome));
    }
    return heldFor.get(owner.identity) ?? null;
  };

  const skills = rows
    .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0))
    .map((row) => ({
      name: row.name,
      description: row.description,
      path: row.real,
      source: row.owner
        ? {
            kind: 'plugin',
            plugin: row.owner.plugin,
            marketplace: row.owner.marketplace,
            pluginVersion: row.owner.version,
            installedAt: null,
            lastUpdated: null,
            commit: null,
            siblingSkillCount: siblings.get(row.owner.identity) ?? 1,
          }
        : { kind: 'standalone', path: row.real },
      presence: presenceFor(listing.status === 'read'),
      held: row.owner ? held(row.owner) : null,
      provenance: null,
    }));

  // `promoteFromCache` says this router serves POST /extensions/plugins/<plugin>@<marketplace>/promote with
  // `source: "cache"`, so the Mac enables Promote only where the route exists. An older router omits the member.
  return {
    skills,
    clients: clientsFor(skillsDirectory, listing, register),
    promoteFromCache: true,
    // Cache promotion changes the router's ExtensionStore, never Claude's installed-plugin register.
    // Claude's latest-only CLI cannot bind an operation to the version and capabilities just reviewed.
    installedPluginUpdates: {
      available: false,
      reason: 'Claude Code cannot bind an update to the reviewed version and capabilities. Update it in Claude Code; this router does not change that installation.',
    },
  };
}

/** The per-skill presence map: Claude Code is the directory this router listed; every other client is unknown. */
function presenceFor(claudeRead: boolean): Record<string, Presence> {
  const presence: Record<string, Presence> = {};
  for (const client of CLIENTS) {
    if (!client.supportsSkills) continue;
    presence[client.id] = client.id === 'claudeCode' && claudeRead ? 'present' : 'unreadable';
  }
  return presence;
}

function clientsFor(
  skillsDirectory: string,
  listing: SkillsListing,
  register: Reading<InstalledPlugin[]>
): Array<Record<string, unknown>> {
  return CLIENTS.map((client) => {
    if (!client.supportsSkills) {
      return { id: client.id, displayName: client.displayName, supportsSkills: false, root: null, status: 'unsupported', reason: null };
    }
    if (client.id !== 'claudeCode') {
      return { id: client.id, displayName: client.displayName, supportsSkills: true, root: null, status: 'unreadable', reason: NOT_READ_HERE };
    }
    // An unreadable register leaves plugin ownership unknown. That is said on the client, since no skill row has a
    // field to say it.
    const status: ClientStatus = register.ok ? listing.status : 'unreadable';
    const reason = register.ok ? listing.reason : register.problem;
    return {
      id: client.id,
      displayName: client.displayName,
      supportsSkills: true,
      root: skillsDirectory,
      status,
      reason,
    };
  });
}

/** Held means the marketplace offers a version newer than the installed one, and Keep has not covered it. */
function heldVersion(
  owner: PluginRoot,
  affected: number,
  store: ExtensionStore,
  catalogue: MarketplaceCatalogue | null,
  claudeHome: string
): Record<string, unknown> | null {
  const offer = catalogue?.offer(owner.plugin);
  if (!offer || offer.version === undefined) return null;
  if (compareVersions(owner.version, offer.version) !== 'ascending') return null;

  const kept = store.keptVersion('plugins', owner.identity);
  if (kept !== null) {
    const order = compareVersions(kept, offer.version);
    // Shown only when the offer is newer than the kept version, or when the two cannot be ordered at all.
    if (order !== null && order !== 'ascending') return null;
  }
  const changelog: Changelog = changelogFor(claudeHome, owner.identity, offer.version);
  return {
    pluginVersion: offer.version,
    addedCapabilities: [CAPABILITIES_NOT_COMPARED],
    affectedSkillCount: affected,
    changelog,
  };
}

// MARK: - Claude's directories

interface SkillsListing {
  status: ClientStatus;
  reason: string | null;
  names: string[];
}

/** The skills directory's entries, as Swift's walk reads them: hidden names skipped, absence distinct from failure. */
function claudeSkillNames(directory: string): SkillsListing {
  if (!existsSync(directory)) return { status: 'absent', reason: null, names: [] };
  try {
    if (!statSync(directory).isDirectory()) {
      return { status: 'unreadable', reason: `${directory} is not a directory`, names: [] };
    }
    const names = readdirSync(directory).filter((name) => !name.startsWith('.')).sort();
    return { status: 'read', reason: null, names };
  } catch {
    return { status: 'unreadable', reason: `${directory} could not be read`, names: [] };
  }
}

/** One skill directory as a row, or null when it is not a skill the board can show: a dangling link, no SKILL.md, or a descriptor that will not read. */
function readRow(directory: string, name: string, roots: PluginRoot[]): Row | null {
  if (!isWellFormedName(name)) return null;
  const real = resolveOrNull(join(directory, name));
  if (real === null || !isDirectory(real)) return null;
  const text = readUtf8(join(real, 'SKILL.md'));
  if (text === null) return null;
  const outcome = readDescriptor('skills', text);
  if (!outcome.ok) return null;
  return { name, real, description: outcome.reading.description, owner: ownerOf(real, roots) };
}

/**
 * The register's `installed_plugins.json`, read as Swift's installedPlugins reads it. An absent register is an empty
 * one. A present register that cannot be read is a problem, not an empty list. A plugin that declares no version is
 * left out, so its skills read as standalone: a skill's version is its plugin's, and there is none to show.
 */
function installedPlugins(path: string): Reading<InstalledPlugin[]> {
  const text = readUtf8(path);
  if (text === null) {
    return existsSync(path) ? { ok: false, problem: `${path} could not be opened` } : { ok: true, value: [] };
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return { ok: false, problem: `${path} is not valid UTF-8 JSON` };
  }
  const members = isObject(parsed) && isObject(parsed.plugins) ? parsed.plugins : null;
  if (members === null) return { ok: false, problem: `${path} carries no plugins object` };

  const rows: InstalledPlugin[] = [];
  for (const [identity, records] of Object.entries(members).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))) {
    const first: unknown = Array.isArray(records) ? records[0] : undefined;
    if (!isObject(first) || typeof first.installPath !== 'string' || first.installPath === '') continue;
    const at = identity.indexOf('@');
    if (at <= 0 || at === identity.length - 1) continue;
    const version = typeof first.version === 'string' && first.version !== '' ? first.version : null;
    if (version === null) continue;
    rows.push({
      identity,
      plugin: identity.slice(0, at),
      marketplace: identity.slice(at + 1),
      installPath: first.installPath,
      version,
    });
  }
  return { ok: true, value: rows };
}

/** Plugins whose install directory is present, resolved for matching. An unresolved install path attributes nothing. */
function pluginRoots(plugins: InstalledPlugin[]): PluginRoot[] {
  const roots: PluginRoot[] = [];
  for (const plugin of plugins) {
    const real = resolveOrNull(plugin.installPath);
    if (real !== null && isDirectory(real)) roots.push({ ...plugin, real });
  }
  return roots;
}

/** The plugin whose install directory contains this skill, the innermost one when several do. */
function ownerOf(real: string, roots: PluginRoot[]): PluginRoot | null {
  let best: PluginRoot | null = null;
  for (const root of roots) {
    const inside = real === root.real || real.startsWith(root.real + sep);
    if (inside && (best === null || root.real.length > best.real.length)) best = root;
  }
  return best;
}

/** A marketplace catalogue, read once. A name that is not a well-formed directory name reads nothing. */
function catalogueOf(
  claudeHome: string,
  marketplace: string,
  memo: Map<string, MarketplaceCatalogue | null>
): MarketplaceCatalogue | null {
  if (!memo.has(marketplace)) {
    const text = isWellFormedName(marketplace)
      ? readUtf8(join(claudeHome, 'plugins', 'marketplaces', marketplace, '.claude-plugin', 'marketplace.json'))
      : null;
    memo.set(marketplace, text === null ? null : readCatalogue(text));
  }
  return memo.get(marketplace) ?? null;
}

// MARK: - Small readers

function resolveOrNull(path: string): string | null {
  try {
    return realpathSync(path);
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

function readUtf8(path: string): string | null {
  try {
    return new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(readFileSync(path));
  } catch {
    return null;
  }
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
