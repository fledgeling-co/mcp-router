import { existsSync, readFileSync } from 'node:fs';
import { DEFAULT_CONFIG_PATH, parseServer, type RawServer } from './config.js';
import { collectNeedles, redactArgs, type Needle } from './secrets.js';

/**
 * The server list as a file a person can share, with every secret value replaced.
 *
 * Each removed value becomes `<redacted:WHERE>`, where WHERE says what it was: `env.API_KEY`,
 * `headers.Authorization`, `url`, or `args.N` for the Nth argument. Keys, names and structure stay,
 * so the file can be read back once the placeholders are filled in by hand. Import is not built.
 *
 * Env and header values are all replaced, not only the ones that look like secrets, because the
 * router cannot tell them apart and the brief's default is to redact every credential field. A
 * field the router does not know is dropped rather than copied: an unrecognised key is as likely to
 * hold a secret as a recognised one, and nothing here can check it.
 */

/** The fields carried over as they are. Anything not listed here, and not handled below, is dropped. */
const KEPT_FIELDS = [
  'type',
  'command',
  'cwd',
  'envFile',
  'oauth',
  'idleMs',
  'startupTimeoutMs',
  'projects',
  'warm',
  'placard',
  'disabled',
] as const;

/** A placeholder redactArgs wrote, whether bare or carrying a literal's label. */
const MARKER = /<redacted(?::[^>]*)?>/g;

export interface ExportDocument {
  mcpServers: Record<string, RawServer>;
}

export function placeholder(label: string): string {
  return `<redacted:${label}>`;
}

/** Read the server list the router loads. A missing file is an error, as it is for the router. */
export function readServers(path: string = DEFAULT_CONFIG_PATH): Record<string, RawServer> {
  if (!existsSync(path)) throw new Error(`No server list at ${path}.`);
  const raw = JSON.parse(readFileSync(path, 'utf8')) as { mcpServers?: Record<string, RawServer> };
  return raw.mcpServers ?? {};
}

/** A `--only` or `?only=` value: comma-separated names. Absent or empty means every server. */
export function parseOnly(value: string | null | undefined): string[] | undefined {
  const names = (value ?? '')
    .split(',')
    .map((name) => name.trim())
    .filter(Boolean);
  return names.length ? names : undefined;
}

/**
 * Build the export. Literals are collected from every server in the list, not only the ones being
 * exported: a secret in one server's env and echoed into another server's argv must not survive
 * because the first server was filtered out. Servers the router would refuse to load contribute no
 * literals, though their own env and header values are still replaced by position.
 */
export function buildExport(
  servers: Record<string, RawServer>,
  controlToken: string,
  only?: string[]
): ExportDocument {
  const names = only ?? Object.keys(servers);
  const missing = names.filter((name) => !Object.hasOwn(servers, name));
  if (missing.length) {
    throw new Error(`no server named ${missing.map((name) => `"${name}"`).join(', ')} in the server list`);
  }
  const upstreams = Object.entries(servers).flatMap(([name, s]) => {
    const parsed = parseServer(name, s);
    return 'upstream' in parsed ? [parsed.upstream] : [];
  });
  const needles = collectNeedles(upstreams, controlToken);
  return {
    mcpServers: Object.fromEntries(names.map((name) => [name, exportOne(servers[name], needles)])),
  };
}

function exportOne(s: RawServer, needles: Needle[]): RawServer {
  const out: Record<string, unknown> = {};
  for (const key of KEPT_FIELDS) {
    if (s[key] !== undefined) out[key] = s[key];
  }
  if (s.command !== undefined) out.command = scrubString(s.command, 'command', needles);
  if (s.args !== undefined) out.args = scrubArgs(s.args, needles);
  if (s.env !== undefined) out.env = replaceValues(s.env, 'env');
  if (s.url !== undefined) out.url = scrubString(s.url, 'url', needles);
  if (s.headers !== undefined) out.headers = replaceValues(s.headers, 'headers');
  return out as RawServer;
}

/**
 * One string through the argv rules. The label names the placeholder the scrub wrote, so a password
 * inside a URL reads `<redacted:url>` where it was.
 */
function scrubString(text: unknown, label: string, needles: Needle[]): string {
  if (typeof text !== 'string') return placeholder(label);
  const scrubbed = redactArgs(text, needles) as string;
  return scrubbed === text ? text : scrubbed.replace(MARKER, placeholder(label));
}

/**
 * The argv rules over the whole list, so a flag's value is recognised from the flag before it. The
 * scrub returns one entry per argument, so a placeholder can name its index.
 */
function scrubArgs(args: unknown, needles: Needle[]): unknown {
  if (!Array.isArray(args)) return placeholder('args');
  const scrubbed = redactArgs(args, needles) as unknown[];
  return scrubbed.map((value, i) =>
    value === args[i] ? value : String(value).replace(MARKER, placeholder(`args.${i}`))
  );
}

/** Every key kept, every value replaced by a placeholder naming that key. */
function replaceValues(map: unknown, prefix: 'env' | 'headers'): unknown {
  if (typeof map !== 'object' || map === null || Array.isArray(map)) return placeholder(prefix);
  return Object.fromEntries(Object.keys(map).map((key) => [key, placeholder(`${prefix}.${key}`)]));
}
