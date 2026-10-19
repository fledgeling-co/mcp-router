import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { basename, join } from 'node:path';
import type { UpstreamConfig } from './config.js';
import { compareStrings } from './config.js';
import {
  childNames,
  parseMiniToml,
  SERVER_TABLE_NAMES,
  TOMLProblem,
  tableMatching,
  type TomlDocument,
  type TomlTable,
} from './minitoml.js';

/**
 * Detection of the agent clients on this machine and how each one reaches the router, ported from
 * app/Sources/RouterCore/Discovery (ClientConfigs, HarnessReconciliation, HarnessWiring,
 * HarnessCapability, HarnessReportJSON) and the M22 route in ControlHarnesses.swift.
 *
 * **Read only.** Nothing here writes a harness config, and the route that serves it sits behind the
 * control token. A harness that is wired, unwired, unreadable or absent is reported as it is; the
 * router never offers to change it.
 */

/** The path the router serves MCP on. Mirrors `MCP_PATH` in router.ts, which cannot be imported here without a cycle. */
const MCP_PATH = '/mcp';

const LOOPBACK_HOSTS = new Set(['127.0.0.1', 'localhost', '::1', '[::1]']);

export type MCPClient =
  | 'claudeCode'
  | 'claudeDesktop'
  | 'codexCLI'
  | 'chatGPTCLI'
  | 'cursor'
  | 'geminiCLI'
  | 'grokCLI'
  | 'opencode';

/** Fixed order, so two reads report the same list in the same sequence. */
export const MCP_CLIENTS: MCPClient[] = [
  'claudeCode',
  'claudeDesktop',
  'codexCLI',
  'chatGPTCLI',
  'cursor',
  'geminiCLI',
  'grokCLI',
  'opencode',
];

const DISPLAY_NAMES: Record<MCPClient, string> = {
  claudeCode: 'Claude Code',
  claudeDesktop: 'Claude Desktop',
  codexCLI: 'Codex CLI',
  chatGPTCLI: 'ChatGPT CLI',
  cursor: 'Cursor',
  geminiCLI: 'Gemini CLI',
  grokCLI: 'grok',
  opencode: 'opencode',
};

/** The name a harness is shown under, as the Harnesses and Insights boards spell it. */
export function harnessDisplayName(client: MCPClient): string {
  return DISPLAY_NAMES[client];
}

/**
 * What a harness's calls look like to the router when they arrive, and who established it. The router observes
 * the peer process, not the harness, so turning `claude` into Claude Code is a naming claim. The case carries
 * its provenance so a zero produced by a wrong name cannot pass for a finding. Ported from ClientProcessName.swift.
 */
export type ClientProcessName =
  | { kind: 'measured'; name: string; probe: string; on: string }
  | { kind: 'ambiguous'; name: string; reason: string }
  | { kind: 'unknown' };

/** The process name a harness's calls arrive under, measured where it was measured and marked ambiguous where two harnesses share it. */
export function clientProcessName(client: MCPClient): ClientProcessName {
  switch (client) {
    case 'claudeCode':
      return {
        kind: 'measured',
        name: 'claude',
        probe: 'file $(command -v claude) — Mach-O 64-bit executable arm64',
        on: '2026-08-22',
      };
    case 'geminiCLI':
      return {
        kind: 'measured',
        name: 'agy',
        probe: 'file $(command -v agy) — Mach-O 64-bit executable arm64',
        on: '2026-08-22',
      };
    case 'grokCLI':
      return {
        kind: 'measured',
        name: 'grok',
        probe: 'file $(command -v grok) — Mach-O 64-bit executable arm64',
        on: '2026-08-22',
      };
    // One binary, two harness entries. The calls behind them cannot be told apart, so neither may claim the total.
    case 'codexCLI':
    case 'chatGPTCLI':
      return {
        kind: 'ambiguous',
        name: 'codex',
        reason: 'the Codex and ChatGPT entries are the same binary, so a count cannot be split',
      };
    // A bash wrapper that execs a bundled node, so `proc_name` is the executable's own name, which every node MCP process shares.
    case 'cursor':
      return {
        kind: 'ambiguous',
        name: 'node',
        reason: 'cursor-agent execs a bundled node, which every node MCP process shares',
      };
    case 'opencode':
      return {
        kind: 'ambiguous',
        name: 'node',
        reason: 'opencode is a node script, which every node MCP process shares',
      };
    case 'claudeDesktop':
      return { kind: 'unknown' };
  }
}

/** Every path a harness's config could live at, most current first. Empty when the harness is project-scoped and no project is named. */
export function candidatePaths(client: MCPClient, home: string, project?: string): string[] {
  switch (client) {
    case 'claudeCode':
      return [join(home, '.claude.json')];
    case 'claudeDesktop':
      return [join(home, 'Library/Application Support/Claude/claude_desktop_config.json')];
    case 'codexCLI':
      return [join(home, '.codex/config.toml')];
    case 'chatGPTCLI':
      return project === undefined ? [] : [join(project, '.chatgpt/config.toml')];
    case 'cursor':
      return [join(home, '.cursor/mcp.json')];
    case 'geminiCLI':
      // agy 1.1.17 moved its config here; the older file is what a pre-migration install reads.
      return [join(home, '.gemini/config/mcp_config.json'), join(home, '.gemini/settings.json')];
    case 'grokCLI':
      return [join(home, '.grok/config.toml')];
    case 'opencode':
      return [join(home, '.config/opencode/opencode.json')];
  }
}

/** The path this harness is actually reading: the first candidate present on disk, else the first candidate. */
export function resolvedPath(client: MCPClient, home: string, project?: string): string | undefined {
  const candidates = candidatePaths(client, home, project);
  return candidates.find((path) => existsSync(path)) ?? candidates[0];
}

interface Entry {
  name: string;
  raw: unknown;
}

type ClientConfigResult =
  | { kind: 'absent' }
  | { kind: 'unreadable'; reason: string }
  | { kind: 'declaresNone' }
  | { kind: 'servers'; servers: Entry[] };

function readClient(client: MCPClient, path: string): ClientConfigResult {
  if (!existsSync(path)) return { kind: 'absent' };
  let bytes: Buffer;
  try {
    bytes = readFileSync(path);
  } catch (err) {
    return { kind: 'unreadable', reason: (err as Error).message };
  }
  switch (client) {
    case 'codexCLI':
    case 'chatGPTCLI':
    case 'grokCLI':
      return readToml(bytes);
    case 'claudeCode':
    case 'claudeDesktop':
    case 'cursor':
    case 'geminiCLI':
      return readJson(bytes, 'mcpServers');
    case 'opencode':
      return readJson(bytes, 'mcp');
  }
}

function readJson(bytes: Buffer, key: string): ClientConfigResult {
  let root: unknown;
  try {
    root = JSON.parse(bytes.toString('utf8'));
  } catch (err) {
    return { kind: 'unreadable', reason: (err as Error).message };
  }
  if (!isObject(root) || !Object.hasOwn(root, key)) return { kind: 'declaresNone' };
  const declared = root[key];
  if (!isObject(declared)) {
    return { kind: 'unreadable', reason: `"${key}" is a ${jsonTypeName(declared)}, not an object of servers` };
  }
  return finish(Object.entries(declared).map(([name, raw]) => ({ name, raw })));
}

function readToml(bytes: Buffer): ClientConfigResult {
  // The Swift reader reads invalid UTF-8 as an empty file. Mirror that rather than decoding it lossily.
  let text: string;
  try {
    text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    text = '';
  }
  let document: TomlDocument;
  try {
    document = parseMiniToml(text);
  } catch (err) {
    if (err instanceof TOMLProblem) return { kind: 'unreadable', reason: err.message };
    return { kind: 'unreadable', reason: String(err) };
  }

  const found: Entry[] = [];
  const seen = new Set<string>();
  for (const table of SERVER_TABLE_NAMES) {
    for (const name of childNames(document, [table])) {
      const pairs = tableMatching(document, [table, name]);
      if (pairs === undefined) continue;
      if (seen.has(name)) {
        return {
          kind: 'unreadable',
          reason: `"${name}" is declared under both [mcp_servers] and [mcpServers]. Keep one and remove the other.`,
        };
      }
      seen.add(name);
      found.push({ name, raw: serverValue(document, table, name, pairs) });
    }
  }
  return finish(found);
}

/** `env` and `headers` are sub-tables in TOML, so they are folded back in as nested objects. */
function serverValue(
  document: TomlDocument,
  table: string,
  name: string,
  pairs: TomlTable['pairs'],
): Record<string, unknown> {
  const server: Record<string, unknown> = Object.fromEntries(pairs.map((p) => [p.key, p.value]));
  for (const nested of ['env', 'headers']) {
    const sub = tableMatching(document, [table, name, nested]);
    if (sub === undefined) continue;
    server[nested] = Object.fromEntries(sub.map((p) => [p.key, p.value]));
  }
  return server;
}

function finish(servers: Entry[]): ClientConfigResult {
  return servers.length === 0 ? { kind: 'declaresNone' } : { kind: 'servers', servers };
}

/** The HTTP capability record. Each entry names the instrument, and opencode stays unknown until somebody probes it. */
interface Capability {
  provenance: 'measured' | 'documented' | 'unknown';
  summary: string;
}

function measured(binary: string, probe: string, on: string): Capability {
  return { provenance: 'measured', summary: `speaks streamable HTTP — measured on ${binary}, ${on}: ${probe}` };
}

function capabilityFor(client: MCPClient): Capability {
  switch (client) {
    case 'claudeCode':
      return measured(
        'claude',
        "~/.claude.json carries type:http and the router serves this repository's own sessions through it",
        '2026-08-21',
      );
    case 'codexCLI':
    case 'chatGPTCLI':
      return measured(
        'codex 0.146.0',
        '`codex mcp add <NAME> --url <URL>` documents a streamable HTTP MCP server; links rmcp-1.8.0 streamable_http_client',
        '2026-08-21',
      );
    case 'cursor':
      return measured(
        'cursor-agent 2026.08.11',
        'shipped bundle selects type "streamableHttp" when the mcp.json entry carries a url',
        '2026-08-21',
      );
    case 'geminiCLI':
      return measured(
        'agy 1.1.17',
        'embeds mcp.StreamableClientTransport from the Go MCP SDK; server config struct carries json:"httpUrl"',
        '2026-08-21',
      );
    case 'grokCLI':
      return measured(
        'grok 1.0.5',
        'links rmcp-2.1.0 streamable_http_client and documents [mcp_servers.<name>] url',
        '2026-08-21',
      );
    case 'claudeDesktop':
      return {
        provenance: 'documented',
        summary: "speaks streamable HTTP — taken on documentation: Anthropic's desktop MCP documentation; no binary was probed here",
      };
    case 'opencode':
      return { provenance: 'unknown', summary: 'streamable HTTP support not established' };
  }
}

/** The endpoint keys each harness is shown to use. Gemini writes `serverUrl` and `httpUrl`; nothing else has been shown to. */
function endpointKeysFor(client: MCPClient): string[] {
  return client === 'geminiCLI' ? ['url', 'httpUrl', 'serverUrl'] : ['url'];
}

interface Duplicate {
  harnessName: string;
  routerName: string;
  basis: 'name' | 'identity';
}

type Route =
  | { kind: 'none' }
  | { kind: 'http'; name: string; url: string }
  | { kind: 'stdio-shim'; name: string; bridge: string; url: string };

export interface HarnessReport {
  client: MCPClient;
  path: string;
  exists: boolean;
  unreadable: string | null;
  entryCount: number;
  route: Route;
  capability: Capability;
  duplicates: Duplicate[];
  unparsed: string[];
}

/** Everything the reconciliation says about one harness, from one read of its config. */
export interface HarnessInventory {
  reports(upstreams: UpstreamConfig[], port: number): HarnessReport[];
}

/** Reads the harness configs under `home` off disk, read only. */
export function diskHarnessInventory(home: string = homedir()): HarnessInventory {
  return {
    reports(upstreams, port) {
      const reports: HarnessReport[] = [];
      for (const client of MCP_CLIENTS) {
        const path = resolvedPath(client, home);
        if (path === undefined) continue;
        reports.push(reconcile(client, path, readClient(client, path), upstreams, port));
      }
      return reports;
    },
  };
}

function reconcile(
  client: MCPClient,
  path: string,
  result: ClientConfigResult,
  upstreams: UpstreamConfig[],
  port: number,
): HarnessReport {
  const capability = capabilityFor(client);
  switch (result.kind) {
    case 'absent':
      return empty(client, path, false, null, capability);
    case 'unreadable':
      return empty(client, path, true, result.reason, capability);
    case 'declaresNone':
      return empty(client, path, true, null, capability);
    case 'servers':
      return compare(client, path, capability, result.servers, upstreams, port);
  }
}

function empty(
  client: MCPClient,
  path: string,
  exists: boolean,
  unreadable: string | null,
  capability: Capability,
): HarnessReport {
  return {
    client,
    path,
    exists,
    unreadable,
    entryCount: 0,
    route: { kind: 'none' },
    capability,
    duplicates: [],
    unparsed: [],
  };
}

function compare(
  client: MCPClient,
  path: string,
  capability: Capability,
  entries: Entry[],
  upstreams: UpstreamConfig[],
  port: number,
): HarnessReport {
  const keys = endpointKeysFor(client);
  const route = detectRoute(entries, port, keys);
  const routerEntryName = route.kind === 'none' ? undefined : route.name;
  const others = entries.filter((entry) => entry.name !== routerEntryName);

  const byName = new Set(upstreams.map((u) => u.name));
  const byIdentity = new Map<string, string>();
  for (const upstream of upstreams) {
    const key = identityOfUpstream(upstream);
    if (!byIdentity.has(key)) byIdentity.set(key, upstream.name);
  }

  const duplicates: Duplicate[] = [];
  const unparsed: string[] = [];
  for (const entry of others) {
    if (byName.has(entry.name)) {
      duplicates.push({ harnessName: entry.name, routerName: entry.name, basis: 'name' });
      continue;
    }
    const resolved = resolveDialect(keys, entry);
    if (resolved.kind === 'conflict') {
      unparsed.push(`${entry.name}: ${resolved.reason}`);
      continue;
    }
    const parsed = identityOfEntry(resolved.entry.name, resolved.entry.raw);
    if ('reason' in parsed) {
      unparsed.push(`${resolved.entry.name}: ${parsed.reason}`);
      continue;
    }
    const routerName = byIdentity.get(parsed.identity);
    if (routerName === undefined) continue;
    duplicates.push({ harnessName: resolved.entry.name, routerName, basis: 'identity' });
  }

  return {
    client,
    path,
    exists: true,
    unreadable: null,
    entryCount: others.length,
    route,
    capability,
    duplicates,
    unparsed,
  };
}

function detectRoute(entries: Entry[], port: number, keys: string[]): Route {
  let shim: Route | undefined;
  for (const entry of entries) {
    // A stdio entry is a stdio entry, and an endpoint key on it is not a route.
    if (isStdio(entry)) {
      shim ??= shimRoute(entry, port);
      continue;
    }
    const url = firstEndpoint(endpointsIn(keys, entry.raw), port);
    if (url !== undefined) return { kind: 'http', name: entry.name, url };
  }
  return shim ?? { kind: 'none' };
}

/** A stdio entry: it carries a command, and an explicit HTTP `type` overrides it. */
function isStdio(entry: Entry): boolean {
  if (!truthy(member(entry.raw, 'command'))) return false;
  const declared = member(entry.raw, 'type');
  if (declared === undefined || declared === null) return true;
  return !['http', 'sse', 'streamable-http'].includes(displayString(declared));
}

/** A stdio entry is a bridge to this router when the endpoint appears among its arguments. */
function shimRoute(entry: Entry, port: number): Route | undefined {
  const commandValue = member(entry.raw, 'command');
  if (commandValue === undefined) return undefined;
  const command = displayString(commandValue);
  if (command === '') return undefined;
  const argsValue = member(entry.raw, 'args');
  const args = (Array.isArray(argsValue) ? argsValue : []).map(displayString);
  const url = firstEndpoint([command, ...args], port);
  if (url === undefined) return undefined;
  return { kind: 'stdio-shim', name: entry.name, bridge: bridgeName(command, args, url), url };
}

/** The first argument that is neither a flag nor the endpoint, falling back to the command's last path component. */
function bridgeName(command: string, args: string[], url: string): string {
  for (const arg of args) {
    if (arg !== url && !arg.startsWith('-') && arg !== '') return arg;
  }
  return basename(command);
}

function endpointsIn(keys: string[], raw: unknown): string[] {
  const found: string[] = [];
  for (const key of keys) {
    const text = member(raw, key);
    if (typeof text === 'string' && text !== '') found.push(text);
  }
  return found;
}

function firstEndpoint(candidates: string[], port: number): string | undefined {
  return candidates.find((candidate) => isThisRouter(candidate, port));
}

/** True when `text` parses as a loopback URL at this router's port **and** its MCP path. */
function isThisRouter(text: string, port: number): boolean {
  const url = parseUrl(text);
  if (url === undefined) return false;
  if (!LOOPBACK_HOSTS.has(url.hostname)) return false;
  if (url.port !== String(port)) return false;
  return endpointPathOf(text) === MCP_PATH;
}

function endpointPathOf(text: string): string {
  return endpointParts(text).path;
}

/** The path and the query-or-fragment tail, read off the text. One trailing slash is the same endpoint; two are not. */
function endpointParts(text: string): { path: string; suffix: string } {
  const trimmed = text.trim();
  const colon = trimmed.indexOf(':');
  if (colon < 0) return { path: '', suffix: '' };
  // Up to two slashes are the authority marker, so `http:/127.0.0.1:8879/mcp` reaches the same place.
  let remainder = trimmed.slice(colon + 1);
  let consumed = 0;
  while (consumed < 2 && remainder.startsWith('/')) {
    remainder = remainder.slice(1);
    consumed += 1;
  }
  const start = remainder.search(/[/?#]/);
  if (start < 0) return { path: '', suffix: '' };
  if (remainder[start] !== '/') return { path: '', suffix: remainder.slice(start) };
  const rest = remainder.slice(start);
  const tail = rest.search(/[?#]/);
  const end = tail < 0 ? rest.length : tail;
  let path = rest.slice(0, end);
  if (path.length > 1 && path.endsWith('/')) path = path.slice(0, -1);
  return { path, suffix: rest.slice(end) };
}

/** Two spellings of one endpoint reduced to one string, so a difference that changes no destination is not a disagreement. */
function comparableEndpoint(text: string): string {
  const split = endpointParts(text);
  const url = parseUrl(text);
  if (url === undefined) {
    let trimmed = text.trim();
    if (trimmed.length > 1 && trimmed.endsWith('/')) trimmed = trimmed.slice(0, -1);
    return trimmed;
  }
  return `${url.protocol.slice(0, -1)}://${url.hostname}:${url.port}${split.path}${split.suffix}`;
}

type Resolution = { kind: 'entry'; entry: Entry } | { kind: 'conflict'; reason: string };

/** The entry with a non-standard endpoint spelling rewritten to `url`, or a refusal to pick between two. */
function resolveDialect(keys: string[], entry: Entry): Resolution {
  if (!isObject(entry.raw) || isStdio(entry)) return { kind: 'entry', entry };
  const declared: { key: string; value: string }[] = [];
  for (const key of keys) {
    const value = member(entry.raw, key);
    if (typeof value === 'string' && value !== '') declared.push({ key, value });
  }
  const distinct = new Set(declared.map((d) => comparableEndpoint(d.value)));
  if (distinct.size > 1) {
    const shown = declared.map((d) => `${d.key}=${d.value}`).join(' and ');
    return {
      kind: 'conflict',
      reason: `declares two different endpoints — ${shown} — so which one it means is not established by anything here`,
    };
  }
  if (declared.length === 0) return { kind: 'entry', entry };
  if (declared.length === 1 && declared[0].key === 'url') return { kind: 'entry', entry };
  const dropped = new Set(keys);
  const rewritten = Object.entries(entry.raw as Record<string, unknown>).filter(([key]) => !dropped.has(key));
  rewritten.push(['url', declared[0].value]);
  return { kind: 'entry', entry: { name: entry.name, raw: Object.fromEntries(rewritten) } };
}

/**
 * The identity a server is compared by: its transport and what it runs or reaches, never its name.
 * Routers and harnesses are compared through the same digest, so the two sides only need to agree on
 * the material, which is the same JSON shape here.
 */
function identityOfUpstream(upstream: UpstreamConfig): string {
  if (upstream.transport === 'stdio') {
    return JSON.stringify(['stdio', upstream.command, upstream.args, upstream.cwd ?? null, sortedEntries(upstream.env)]);
  }
  return JSON.stringify([upstream.transport, upstream.url, sortedEntries(upstream.headers)]);
}

/** Parses a harness entry the way the router parses its own, and returns the same identity, or the reason it cannot. */
function identityOfEntry(name: string, raw: unknown): { identity: string } | { reason: string } {
  if (!/^[A-Za-z0-9_-]+$/.test(name)) {
    return { reason: 'name is not [A-Za-z0-9_-]+, so it cannot be a tool namespace' };
  }
  if (name.includes('__')) {
    return { reason: 'name contains "__", which is the tool namespace separator' };
  }
  const declared = member(raw, 'type');
  const typeName = declared !== undefined && declared !== null
    ? displayString(declared)
    : truthy(member(raw, 'url')) ? 'http' : 'stdio';

  if (typeName === 'stdio') {
    if (!truthy(member(raw, 'command'))) return { reason: 'stdio server has no command' };
    return {
      identity: JSON.stringify([
        'stdio',
        member(raw, 'command') ?? null,
        member(raw, 'args') ?? [],
        member(raw, 'cwd') ?? null,
        sortedEntries(member(raw, 'env')),
      ]),
    };
  }
  if (['http', 'sse', 'streamable-http'].includes(typeName)) {
    const url = member(raw, 'url');
    if (!truthy(url)) return { reason: `${typeName} server has no url` };
    const text = displayString(url);
    if (parseUrl(text) === undefined) return { reason: `url is not parseable: ${text}` };
    const transport = typeName === 'sse' ? 'sse' : 'http';
    return { identity: JSON.stringify([transport, url, sortedEntries(member(raw, 'headers'))]) };
  }
  return { reason: `unsupported transport "${typeName}"` };
}

/** `Object.entries(obj).sort(byKey)` as pairs, sorted by UTF-16 code unit as the reference's comparator is. */
function sortedEntries(value: unknown): [string, unknown][] {
  if (!isObject(value)) return [];
  return Object.keys(value)
    .sort(compareStrings)
    .map((key): [string, unknown] => [key, value[key]]);
}

function stateOf(report: HarnessReport): string {
  if (report.duplicates.length > 0 && report.route.kind !== 'none') return 'wired-with-duplicates';
  switch (report.route.kind) {
    case 'none':
      return 'not-wired';
    case 'http':
      return 'wired-http';
    case 'stdio-shim':
      return 'wired-shim';
  }
}

/** One harness as `GET /harnesses` reports it. Field names are the wire contract the Mac and Windows clients decode. */
export function harnessRow(report: HarnessReport): Record<string, unknown> {
  const route = report.route;
  return {
    harness: report.client,
    displayName: DISPLAY_NAMES[report.client],
    path: report.path,
    exists: report.exists,
    unreadable: report.unreadable,
    state: stateOf(report),
    route: route.kind === 'none' ? 'none' : route.kind === 'http' ? 'http' : 'stdio-shim',
    bridge: route.kind === 'stdio-shim' ? route.bridge : null,
    entries: report.entryCount,
    duplicateCount: report.duplicates.length,
    duplicates: report.duplicates.map((d) => ({ harnessName: d.harnessName, routerName: d.routerName, basis: d.basis })),
    unparsed: report.unparsed,
    httpCapability: report.capability.summary,
    capability: report.capability.provenance,
  };
}

/** The whole envelope the route answers with. `readAt` is the board's staleness clock. */
export function harnessEnvelope(reports: HarnessReport[], port: number, readAtMilliseconds: number): Record<string, unknown> {
  return {
    port,
    scope: 'global',
    readAt: new Date(readAtMilliseconds).toISOString(),
    harnesses: reports.map(harnessRow),
  };
}

/** Parses a URL the way the router's own adoption does (WHATWG, via `new URL`), or undefined. */
function parseUrl(text: string): URL | undefined {
  try {
    return new URL(text);
  } catch {
    return undefined;
  }
}

/** JS truthiness over a JSON value, which is what the router's own parser tests. */
function truthy(value: unknown): boolean {
  return Boolean(value);
}

/** How a template literal would render a JSON value, which the router uses for reasons and identities. */
function displayString(value: unknown): string {
  if (typeof value === 'string') return value;
  if (value === null) return 'null';
  if (typeof value === 'boolean') return value ? 'true' : 'false';
  if (typeof value === 'number') return String(value);
  return JSON.stringify(value);
}

function member(raw: unknown, key: string): unknown {
  return isObject(raw) && Object.hasOwn(raw, key) ? raw[key] : undefined;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function jsonTypeName(value: unknown): string {
  if (value === null) return 'null';
  if (Array.isArray(value)) return 'array';
  if (typeof value === 'boolean') return 'boolean';
  if (typeof value === 'number') return 'number';
  if (typeof value === 'string') return 'string';
  return 'object';
}
