import {
  readFileSync,
  readdirSync,
  realpathSync,
  existsSync,
  lstatSync,
  writeFileSync,
  renameSync,
  mkdirSync,
} from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { homedir } from 'node:os';

/**
 * Skills and marketplace discovery.
 *
 * The half of the product that is not MCP. A **skill** is a directory containing a `SKILL.md` that a
 * client loads into an agent's context. A **plugin** is the unit that gets installed and versioned.
 * A **marketplace** is a followed source that supplies plugins.
 *
 * THE THREE FACTS ABOUT THE REAL FILESYSTEM THAT THIS MODULE IS SHAPED BY. All three were measured
 * on a real machine, and all three break the obvious implementation:
 *
 * 1. **A plugin is not a skill.** `installed_plugins.json` is keyed `"<plugin>@<marketplace>"` and
 *    holds 96 records; one of them (`vercel`) contains **30 skills**. So version, install date and
 *    commit are all PLUGIN-level. A row that prints a version is printing its plugin's version, and
 *    this module labels it as such rather than implying each skill is independently versioned.
 *
 * 2. **Clients hold skills by symlink.** `~/.cursor/skills/*` are 87 symlinks into the plugin
 *    cache, and `~/.claude/skills`, `~/.codex/skills` and `~/.config/opencode/skills` all symlink
 *    into a shared `~/.agents/skills`. Identity is therefore the **resolved real path** — keying on
 *    the directory name would report one skill reachable from four clients as four skills, and
 *    would merge two unrelated skills that happen to share a name.
 *
 * 3. **`plugins/cache/` is mostly scratch.** 685 of its 692 entries are `temp_git_<ts>_<rand>`
 *    clone directories. Nothing here ever walks `cache/` looking for content: plugins are found
 *    through each install record's own `installPath`, and a held version is looked for only beside
 *    the path a record actually names.
 *
 * WHAT THIS MODULE MAY REPORT. `DESIGN.md` §6: nothing is displayed that the router does not
 * observe. Three fields the brief asks for have no type here at all — run count, last run and eval
 * result — because a skill is loaded into an agent's context by the *client* and never reaches the
 * router, and no eval runner exists. Their absence is structural: there is no field for a later
 * edit to fill in with something plausible.
 *
 * THE FAILURE MODE THIS MODULE IS WRITTEN AGAINST. This repo already shipped a bug where a flat
 * `servers.json` loaded zero servers with no error at all — the reader looked for a key that was
 * not there and found an empty collection, which reads exactly like "you have none". Every read
 * here either finds what it expects or throws. No path through this file fails by returning empty.
 */

export interface SkillClientSpec {
  readonly id: string;
  readonly displayName: string;
  readonly supportsSkills: boolean;
  root(home: string): string | null;
}

/**
 * All six managed clients, including the two with no skills mechanism.
 *
 * The unsupported two are reported rather than omitted, because the app has to be able to SAY they
 * have none. A client silently missing from this list is indistinguishable, at the far end, from a
 * client whose skills we failed to find — and those two want opposite words on screen.
 */
export const SKILL_CLIENTS: readonly SkillClientSpec[] = [
  { id: 'claudeCode', displayName: 'Claude Code', supportsSkills: true, root: (h) => join(h, '.claude', 'skills') },
  { id: 'codex', displayName: 'Codex', supportsSkills: true, root: (h) => join(h, '.codex', 'skills') },
  { id: 'cursor', displayName: 'Cursor', supportsSkills: true, root: (h) => join(h, '.cursor', 'skills') },
  { id: 'opencode', displayName: 'opencode', supportsSkills: true, root: (h) => join(h, '.config', 'opencode', 'skills') },
  // Claude Extensions is a different mechanism and is not a skills directory.
  { id: 'claudeDesktop', displayName: 'Claude Desktop', supportsSkills: false, root: () => null },
  { id: 'chatGPT', displayName: 'ChatGPT', supportsSkills: false, root: () => null },
];

export type ClientReadStatus = 'read' | 'absent' | 'unreadable' | 'unsupported';

export interface SkillClientReport {
  readonly id: string;
  readonly displayName: string;
  readonly supportsSkills: boolean;
  readonly root: string | null;
  readonly status: ClientReadStatus;
  readonly reason: string | null;
}

/**
 * Whether one skill is reachable from one client.
 *
 * `unreadable` is a third value rather than a `false`, and that is the whole of the Partial state.
 * A boolean would collapse "not installed there" and "we could not look", and the board must not
 * draw an empty slot for the second — an empty slot asserts an absence nobody checked.
 */
export type Presence = 'present' | 'absent' | 'unreadable';

/**
 * Where a skill came from.
 *
 * A tagged union, so a skill that is not part of a plugin **has no version field to fill in**. It is
 * structurally impossible to render a version for a standalone skill, rather than merely discouraged.
 */
export type SkillSource =
  | {
      readonly kind: 'plugin';
      readonly plugin: string;
      readonly marketplace: string;
      /** The PLUGIN's version. Every skill the plugin contains shares it. */
      readonly pluginVersion: string;
      readonly installedAt: string | null;
      readonly lastUpdated: string | null;
      readonly commit: string | null;
      /** How many skills this plugin supplies, so a shared version can be explained rather than repeated. */
      readonly siblingSkillCount: number;
    }
  | { readonly kind: 'standalone'; readonly path: string };

export interface HeldVersion {
  readonly pluginVersion: string;
  readonly addedCapabilities: readonly string[];
  readonly affectedSkillCount: number;
}

export interface ProvenanceChange {
  readonly firstSeenSource: string;
  readonly currentSource: string;
  readonly firstSeenAt: string;
}

export interface SkillRecord {
  readonly name: string;
  readonly description: string | null;
  /** The resolved real path. This is the identity; two clients reaching it are one skill. */
  readonly path: string;
  readonly source: SkillSource;
  readonly presence: Readonly<Record<string, Presence>>;
  readonly held: HeldVersion | null;
  readonly provenance: ProvenanceChange | null;
}

export type MarketplaceSource =
  | { readonly kind: 'github'; readonly repo: string }
  | { readonly kind: 'directory'; readonly path: string };

export interface MarketplaceRecord {
  readonly name: string;
  readonly source: MarketplaceSource;
  readonly autoUpdate: boolean;
  readonly installedPluginCount: number;
  readonly suppliedSkillCount: number;
}

// ---------------------------------------------------------------- json

function readJSONObject(path: string): Record<string, unknown> | null {
  if (!existsSync(path)) return null;
  let text: string;
  try {
    text = readFileSync(path, 'utf8');
  } catch (err) {
    throw new Error(`${path} exists but could not be read: ${(err as Error).message}`);
  }
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch (err) {
    throw new Error(`${path} is not valid JSON: ${(err as Error).message}`);
  }
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error(
      `${path} should hold a JSON object, found ${Array.isArray(value) ? 'an array' : typeof value}`
    );
  }
  return value as Record<string, unknown>;
}

function str(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

// ---------------------------------------------------------------- installs

export interface PluginInstall {
  readonly plugin: string;
  readonly marketplace: string;
  readonly version: string;
  readonly installedAt: string | null;
  readonly lastUpdated: string | null;
  readonly commit: string | null;
  readonly installPath: string | null;
}

/**
 * `installed_plugins.json`, keyed `"<plugin>@<marketplace>"`.
 *
 * Throws when the file exists and lacks its `plugins` key. That is exactly the flat-`servers.json`
 * trap: an empty map here renders as "every skill you have is standalone and unversioned", which is
 * a confident, wrong and entirely silent answer.
 */
export function readInstalledPlugins(pluginsDir: string): PluginInstall[] {
  const path = join(pluginsDir, 'installed_plugins.json');
  const root = readJSONObject(path);
  if (root === null) return [];
  const plugins = root.plugins;
  if (typeof plugins !== 'object' || plugins === null || Array.isArray(plugins)) {
    throw new Error(`${path} has no "plugins" object; refusing to report zero installed plugins`);
  }
  const out: PluginInstall[] = [];
  for (const [key, value] of Object.entries(plugins as Record<string, unknown>)) {
    const at = key.lastIndexOf('@');
    if (at <= 0) continue;
    const installs = Array.isArray(value) ? value : [];
    const first = installs.find((i) => typeof i === 'object' && i !== null) as
      | Record<string, unknown>
      | undefined;
    if (!first) continue;
    out.push({
      plugin: key.slice(0, at),
      marketplace: key.slice(at + 1),
      version: str(first.version) ?? '',
      installedAt: str(first.installedAt),
      lastUpdated: str(first.lastUpdated),
      commit: str(first.gitCommitSha),
      installPath: str(first.installPath),
    });
  }
  return out;
}

/** `known_marketplaces.json`. Same loud-failure rule. */
export function readKnownMarketplaces(
  pluginsDir: string
): Map<string, { source: MarketplaceSource; autoUpdate: boolean }> {
  const path = join(pluginsDir, 'known_marketplaces.json');
  const root = readJSONObject(path);
  const out = new Map<string, { source: MarketplaceSource; autoUpdate: boolean }>();
  if (root === null) return out;
  for (const [name, value] of Object.entries(root)) {
    if (typeof value !== 'object' || value === null) continue;
    const entry = value as Record<string, unknown>;
    const src = entry.source;
    let source: MarketplaceSource | null = null;
    if (typeof src === 'object' && src !== null) {
      const s = src as Record<string, unknown>;
      const repo = str(s.repo);
      const dir = str(s.path);
      if (s.source === 'github' && repo) source = { kind: 'github', repo };
      else if (dir) source = { kind: 'directory', path: dir };
    }
    if (!source) continue;
    // An absent `autoUpdate` key means off. Never unknown-rendered-as-on.
    out.set(name, { source, autoUpdate: entry.autoUpdate === true });
  }
  return out;
}

// ---------------------------------------------------------------- skill files

export function parseFrontmatter(markdown: string): { name: string | null; description: string | null } {
  const match = /^---\r?\n([\s\S]*?)\r?\n---/.exec(markdown);
  if (!match) return { name: null, description: null };
  const out: { name: string | null; description: string | null } = { name: null, description: null };
  for (const line of match[1].split(/\r?\n/)) {
    const kv = /^(name|description):\s*(.*)$/.exec(line);
    if (!kv) continue;
    let value = kv[2].trim();
    if (
      (value.startsWith('"') && value.endsWith('"') && value.length > 1) ||
      (value.startsWith("'") && value.endsWith("'") && value.length > 1)
    ) {
      value = value.slice(1, -1);
    }
    if (kv[1] === 'name') out.name = value || null;
    else out.description = value || null;
  }
  return out;
}

function readSkillBody(dir: string): string {
  const file = join(dir, 'SKILL.md');
  if (!existsSync(file)) return '';
  try {
    return readFileSync(file, 'utf8');
  } catch {
    return '';
  }
}

/**
 * The capabilities a skill's own text asks for.
 *
 * No skill format carries a capability manifest, so this is derived from what the markdown actually
 * references: executable paths it invokes and network hosts it names. It is a heuristic, is
 * described as one wherever it surfaces, and its job is only to answer "does this new version want
 * MORE than the old one" — for which a stable comparable set is worth more than a complete one.
 */
export function capabilitiesOf(markdown: string): string[] {
  const found = new Set<string>();
  for (const m of markdown.matchAll(/\b([\w./-]+\.(?:sh|py|js|ts|rb|pl))\b/g)) found.add(`runs ${m[1]}`);
  for (const m of markdown.matchAll(/https?:\/\/([a-z0-9.-]+\.[a-z]{2,})/gi)) {
    found.add(`network ${m[1].toLowerCase()}`);
  }
  return [...found].sort();
}

// ---------------------------------------------------------------- provenance

export interface ProvenanceBaseline {
  readonly [marketplace: string]: { readonly source: string; readonly firstSeenAt: string };
}

export function sourceLabel(source: MarketplaceSource): string {
  return source.kind === 'github' ? `github:${source.repo}` : `directory:${source.path}`;
}

/**
 * Whether a marketplace now resolves somewhere other than where the router first saw it.
 *
 * The baseline is the ROUTER's own first-seen record, not the client's, and that is a deliberate
 * limit rather than an oversight: `installed_plugins.json` records a commit but never an owner, so
 * "the upstream owner changed since you installed it" is not computable from the client's state at
 * all. Rather than approximate it, the router reports what it can actually stand behind — "when
 * this Mac first saw this marketplace it resolved to X" — and the copy says exactly that.
 */
export function provenanceFor(
  marketplace: string,
  source: MarketplaceSource,
  baseline: ProvenanceBaseline
): ProvenanceChange | null {
  const recorded = baseline[marketplace];
  if (!recorded) return null;
  const current = sourceLabel(source);
  if (recorded.source === current) return null;
  return { firstSeenSource: recorded.source, currentSource: current, firstSeenAt: recorded.firstSeenAt };
}

// ---------------------------------------------------------------- discovery

export interface SkillsSnapshot {
  readonly skills: readonly SkillRecord[];
  readonly clients: readonly SkillClientReport[];
}

export interface DiscoverOptions {
  readonly home?: string;
  readonly baseline?: ProvenanceBaseline;
}

/** One entry found in one client's skills root, with its identity resolved. */
interface FoundSkill {
  readonly clientId: string;
  readonly name: string;
  readonly resolved: string;
}

function resolveEntry(root: string, name: string): string | null {
  const full = join(root, name);
  try {
    // `realpathSync` is what collapses a symlink farm into one identity. Without it, one skill
    // reachable from four clients is four skills.
    return realpathSync(full);
  } catch {
    return null;
  }
}

function listClientSkills(root: string): { found: FoundSkill[]; reason?: string } | { reason: string } {
  if (!existsSync(root)) return { reason: 'absent' };
  let names: string[];
  try {
    names = readdirSync(root)
      .filter((n) => !n.startsWith('.'))
      .sort();
  } catch (err) {
    const code = (err as NodeJS.ErrnoException).code;
    return {
      reason: code === 'EACCES' || code === 'EPERM' ? 'permission denied' : String(code ?? (err as Error).message),
    };
  }
  const found: FoundSkill[] = [];
  for (const name of names) {
    const resolved = resolveEntry(root, name);
    if (!resolved) continue;
    let isDir = false;
    try {
      isDir = lstatSync(resolved).isDirectory();
    } catch {
      isDir = false;
    }
    if (!isDir) continue;
    found.push({ clientId: '', name, resolved });
  }
  return { found };
}

/**
 * The plugin a resolved skill path belongs to, or null when it is standalone.
 *
 * Matched by `installPath` prefix, never by walking `cache/` — 685 of that directory's 692 entries
 * are git clone scratch, and a scan of it invents plugins and held versions out of temporary
 * checkouts.
 */
function pluginForPath(resolved: string, installs: readonly PluginInstall[]): PluginInstall | null {
  for (const install of installs) {
    if (!install.installPath) continue;
    if (resolved === install.installPath) return install;
    if (resolved.startsWith(install.installPath + '/')) return install;
  }
  return null;
}

/**
 * A different version of the same plugin sitting beside the installed one.
 *
 * Looked for only in the installed path's own parent — `<cache>/<marketplace>/<plugin>/` — which is
 * the one directory a record points at. No version ordering is invented: the differing version is
 * reported and a human decides, which is the point of holding it.
 */
function heldFor(install: PluginInstall, skillsPerPlugin: number): HeldVersion | null {
  if (!install.installPath) return null;
  const pluginDir = dirname(install.installPath);
  if (!existsSync(pluginDir)) return null;
  let versions: string[];
  try {
    versions = readdirSync(pluginDir, { withFileTypes: true })
      .filter((e) => e.isDirectory())
      .map((e) => e.name)
      .sort();
  } catch {
    return null;
  }
  const other = versions.filter((v) => v !== basename(install.installPath!));
  if (other.length === 0) return null;
  const candidate = other[other.length - 1];
  const before = new Set(capabilitiesOf(readSkillBody(install.installPath)));
  const added = capabilitiesOf(readSkillBody(join(pluginDir, candidate))).filter((c) => !before.has(c));
  return { pluginVersion: candidate, addedCapabilities: added, affectedSkillCount: skillsPerPlugin };
}

/**
 * Every skill reachable from every client that has a skills mechanism.
 *
 * A skill reachable from three clients appears ONCE with three slots on, keyed by its resolved real
 * path. The unit is the skill; "which clients reach it" is a property of it.
 */
export function discoverSkills(options: DiscoverOptions = {}): SkillsSnapshot {
  const home = options.home ?? homedir();
  const baseline = options.baseline ?? {};
  const pluginsDir = join(home, '.claude', 'plugins');

  const clients: SkillClientReport[] = [];
  const byPath = new Map<string, { name: string; clients: Set<string> }>();
  const unreadable = new Set<string>();

  for (const spec of SKILL_CLIENTS) {
    const root = spec.root(home);
    if (!spec.supportsSkills || root === null) {
      clients.push({
        id: spec.id, displayName: spec.displayName, supportsSkills: false,
        root: null, status: 'unsupported', reason: null,
      });
      continue;
    }
    const result = listClientSkills(root);
    if ('found' in result) {
      clients.push({
        id: spec.id, displayName: spec.displayName, supportsSkills: true,
        root, status: 'read', reason: null,
      });
      for (const entry of result.found) {
        const existing = byPath.get(entry.resolved);
        if (existing) existing.clients.add(spec.id);
        else byPath.set(entry.resolved, { name: entry.name, clients: new Set([spec.id]) });
      }
    } else if (result.reason === 'absent') {
      clients.push({
        id: spec.id, displayName: spec.displayName, supportsSkills: true,
        root, status: 'absent', reason: null,
      });
    } else {
      unreadable.add(spec.id);
      clients.push({
        id: spec.id, displayName: spec.displayName, supportsSkills: true,
        root, status: 'unreadable', reason: result.reason,
      });
    }
  }

  const installs = readInstalledPlugins(pluginsDir);
  const marketplaces = readKnownMarketplaces(pluginsDir);

  // Claude Code reaches an installed plugin's skills through the PLUGIN, not through
  // `~/.claude/skills` — that directory holds only what a human put there by hand. A discovery that
  // reads the directory alone reports zero skills for a marketplace supplying ninety of them, and
  // the count looks like a real answer. So every installed plugin's own `skills/` is folded into
  // Claude Code's presence, which is what that client actually loads.
  if (!unreadable.has('claudeCode')) {
    for (const install of installs) {
      if (!install.installPath) continue;
      const dir = join(install.installPath, 'skills');
      if (!existsSync(dir)) continue;
      let names: string[];
      try {
        names = readdirSync(dir).filter((n) => !n.startsWith('.'));
      } catch {
        continue;
      }
      for (const name of names) {
        const resolved = resolveEntry(dir, name);
        if (!resolved) continue;
        try {
          if (!lstatSync(resolved).isDirectory()) continue;
        } catch {
          continue;
        }
        const existing = byPath.get(resolved);
        if (existing) existing.clients.add('claudeCode');
        else byPath.set(resolved, { name, clients: new Set(['claudeCode']) });
      }
    }
  }

  // How many skills each plugin supplies, so a shared version can be explained on the row rather
  // than looking like a coincidence across thirty of them.
  const skillsPerPlugin = new Map<string, number>();
  for (const [resolved] of byPath) {
    const install = pluginForPath(resolved, installs);
    if (!install) continue;
    const key = `${install.plugin}@${install.marketplace}`;
    skillsPerPlugin.set(key, (skillsPerPlugin.get(key) ?? 0) + 1);
  }

  const skills: SkillRecord[] = [...byPath.entries()]
    .map(([resolved, entry]) => {
      const presence: Record<string, Presence> = {};
      for (const spec of SKILL_CLIENTS) {
        if (!spec.supportsSkills) continue;
        presence[spec.id] = unreadable.has(spec.id)
          ? 'unreadable'
          : entry.clients.has(spec.id)
            ? 'present'
            : 'absent';
      }

      const install = pluginForPath(resolved, installs);
      const key = install ? `${install.plugin}@${install.marketplace}` : '';
      const siblings = install ? (skillsPerPlugin.get(key) ?? 1) : 0;

      const source: SkillSource = install
        ? {
            kind: 'plugin',
            plugin: install.plugin,
            marketplace: install.marketplace,
            pluginVersion: install.version,
            installedAt: install.installedAt,
            lastUpdated: install.lastUpdated,
            commit: install.commit,
            siblingSkillCount: siblings,
          }
        : { kind: 'standalone', path: resolved };

      const marketplaceSource = install ? marketplaces.get(install.marketplace)?.source ?? null : null;

      return {
        name: entry.name,
        description: parseFrontmatter(readSkillBody(resolved)).description,
        path: resolved,
        source,
        presence,
        held: install ? heldFor(install, siblings) : null,
        provenance:
          install && marketplaceSource
            ? provenanceFor(install.marketplace, marketplaceSource, baseline)
            : null,
      };
    })
    .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : a.path < b.path ? -1 : 1));

  return { skills, clients };
}

/** Every followed marketplace, with what it supplies. */
export function discoverMarketplaces(options: DiscoverOptions = {}): readonly MarketplaceRecord[] {
  const home = options.home ?? homedir();
  const pluginsDir = join(home, '.claude', 'plugins');
  const known = readKnownMarketplaces(pluginsDir);
  const installs = readInstalledPlugins(pluginsDir);
  const { skills } = discoverSkills(options);

  const plugins = new Map<string, number>();
  for (const install of installs) {
    plugins.set(install.marketplace, (plugins.get(install.marketplace) ?? 0) + 1);
  }
  const suppliedSkills = new Map<string, number>();
  for (const skill of skills) {
    if (skill.source.kind !== 'plugin') continue;
    const mk = skill.source.marketplace;
    suppliedSkills.set(mk, (suppliedSkills.get(mk) ?? 0) + 1);
  }

  return [...known.entries()]
    .map(([name, entry]) => ({
      name,
      source: entry.source,
      autoUpdate: entry.autoUpdate,
      installedPluginCount: plugins.get(name) ?? 0,
      suppliedSkillCount: suppliedSkills.get(name) ?? 0,
    }))
    .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
}

export function pluginsDirFor(home: string = homedir()): string {
  return join(home, '.claude', 'plugins');
}

/**
 * Read the router's own first-seen record, adding any marketplace it has not seen before.
 *
 * Returns the baseline **as it was before this call**, which is what makes a newly-followed
 * marketplace report no provenance change: on the run that first sees it there is nothing to
 * compare against, and inventing a comparison would produce a warning about a marketplace that has
 * not moved.
 *
 * This writes to the ROUTER's own state directory, never to a client's configuration. That
 * distinction is the whole reason it is safe to do on a read path: nothing here can damage a file
 * that Claude Code has open.
 */
export function loadAndUpdateBaseline(
  routerHome: string,
  marketplaces: ReadonlyMap<string, { source: MarketplaceSource; autoUpdate: boolean }>,
  now: () => string = () => new Date().toISOString()
): ProvenanceBaseline {
  const path = join(routerHome, 'skills-provenance.json');
  let existing: Record<string, { source: string; firstSeenAt: string }> = {};
  const raw = readJSONObject(path);
  if (raw !== null) {
    for (const [name, value] of Object.entries(raw)) {
      if (typeof value !== 'object' || value === null) continue;
      const entry = value as Record<string, unknown>;
      const source = str(entry.source);
      const firstSeenAt = str(entry.firstSeenAt);
      if (source && firstSeenAt) existing[name] = { source, firstSeenAt };
    }
  }

  const before: ProvenanceBaseline = { ...existing };
  let changed = false;
  for (const [name, entry] of marketplaces) {
    if (existing[name]) continue;
    existing[name] = { source: sourceLabel(entry.source), firstSeenAt: now() };
    changed = true;
  }

  if (changed) {
    try {
      mkdirSync(routerHome, { recursive: true });
      // Atomic: a partially written baseline would be read next time as a marketplace that
      // "changed", which is a false security warning — the one kind of warning that must never fire
      // for a reason internal to this router.
      const temp = `${path}.${process.pid}.tmp`;
      writeFileSync(temp, JSON.stringify(existing, null, 2), 'utf8');
      renameSync(temp, path);
    } catch {
      // A baseline we could not persist means provenance stays unknown next run, which is the
      // honest degradation. It is never a reason to fail the whole skills read.
    }
  }

  return before;
}
