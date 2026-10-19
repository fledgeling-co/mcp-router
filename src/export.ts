import { existsSync, readFileSync } from 'node:fs';
import { DEFAULT_CONFIG_PATH, parseServer, type RawServer } from './config.js';
import { collectNeedles, redactArgs, type Needle } from './secrets.js';

/**
 * The server list as a file a person can share, with every secret value replaced.
 *
 * Each removed value becomes `<redacted:WHERE>`, where WHERE says what it was: `env.API_KEY`,
 * `headers.Authorization`, `url.path`, `url.query.KEY`, `url.userinfo`, or `args.N` for the Nth
 * argument. Keys, names and structure stay, so the file can be read back once the placeholders are
 * filled in by hand. Import is not built.
 *
 * Env and header values are all replaced, not only the ones that look like secrets, because the
 * router cannot tell them apart and the brief's default is to redact every credential field. A
 * field the router does not know is dropped rather than copied: an unrecognised key is as likely to
 * hold a secret as a recognised one, and nothing here can check it. A recognised field whose value
 * is not the shape the router reads is replaced rather than copied, for the same reason.
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
    try {
      const parsed = parseServer(name, s);
      return 'upstream' in parsed ? [parsed.upstream] : [];
    } catch {
      // An entry the parser cannot read is still exported, with its values replaced by position; it
      // simply contributes no literals to the scrub of the others.
      return [];
    }
  });
  const needles = collectNeedles(upstreams, controlToken);
  return {
    mcpServers: Object.fromEntries(names.map((name) => [name, exportOne(servers[name], needles)])),
  };
}

function exportOne(s: RawServer, needles: Needle[]): RawServer {
  const out: Record<string, unknown> = {};
  for (const key of KEPT_FIELDS) {
    if (s[key] !== undefined) out[key] = keptValue(key, s[key], needles);
  }
  if (s.args !== undefined) out.args = scrubArgs(s.args, needles);
  if (s.env !== undefined) out.env = replaceValues(s.env, 'env');
  if (s.url !== undefined) out.url = exportUrl(s.url, needles);
  if (s.headers !== undefined) out.headers = replaceValues(s.headers, 'headers');
  return out as RawServer;
}

/**
 * A kept field, copied when its shape is one the router reads and replaced when it is not. A string
 * still goes through the literal scrub, so a secret echoed into a command or a reason is removed too.
 */
function keptValue(key: string, value: unknown, needles: Needle[]): unknown {
  if (typeof value === 'string') return scrubString(value, key, needles);
  if (typeof value === 'number' || typeof value === 'boolean') return value;
  if (Array.isArray(value) && value.every((item) => typeof item === 'string')) {
    return value.map((item) => scrubString(item, key, needles));
  }
  if (key === 'placard' && isObject(value)) {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, keptValue(`${key}.${k}`, v, needles)]));
  }
  return placeholder(key);
}

/**
 * One string through the argv rules. The label names the placeholder the scrub wrote in place of a
 * removed literal or secret-named value.
 */
function scrubString(text: unknown, label: string, needles: Needle[]): string {
  if (typeof text !== 'string') return placeholder(label);
  const scrubbed = redactArgs(text, needles) as string;
  return scrubbed === text ? text : scrubbed.replace(MARKER, placeholder(label));
}

/**
 * The argv rules over the whole list, so a flag's value is recognised from the flag before it. The
 * scrub returns one entry per argument, so a placeholder can name its index. A non-string argument
 * is never a flag and cannot be read for a secret, so it is replaced whole.
 */
function scrubArgs(args: unknown, needles: Needle[]): unknown {
  if (!Array.isArray(args)) return placeholder('args');
  const scrubbed = redactArgs(args, needles) as unknown[];
  return scrubbed.map((value, i) => {
    if (typeof args[i] !== 'string') return placeholder(`args.${i}`);
    return value === args[i] ? value : String(value).replace(MARKER, placeholder(`args.${i}`));
  });
}

/**
 * A URL with its scheme and host kept, and every part that can carry a credential replaced: the
 * userinfo, the path, each query value and the fragment. The path goes even though it is usually
 * only a route, because a path can be the credential itself (a webhook address), and the default
 * here fails closed. A placeholder is what a person fills back in by hand. A value that does not
 * parse as a URL is replaced whole.
 */
function exportUrl(text: unknown, needles: Needle[]): string {
  if (typeof text !== 'string') return placeholder('url');
  let url: URL;
  try {
    url = new URL(text);
  } catch {
    return placeholder('url');
  }
  const userinfo = url.username || url.password ? `${placeholder('url.userinfo')}@` : '';
  const path = url.pathname && url.pathname !== '/' ? placeholder('url.path') : '';
  const query = url.search ? `?${url.search.slice(1).split('&').map(queryPair).join('&')}` : '';
  const fragment = url.hash ? placeholder('url.fragment') : '';
  return `${url.protocol}//${userinfo}${scrubString(url.host, 'url.host', needles)}${path}${query}${fragment}`;
}

/**
 * One query pair, its value replaced and its name kept. A pair with no `=` is a bare token, so the
 * whole pair is replaced by its position: its name is the secret, and keeping it would keep it.
 */
function queryPair(pair: string, index: number): string {
  if (pair === '') return pair;
  const eq = pair.indexOf('=');
  if (eq < 0) return placeholder(`url.query.${index}`);
  const key = pair.slice(0, eq);
  return `${key}=${placeholder(`url.query.${key}`)}`;
}

/** Every key kept, every value replaced by a placeholder naming that key. */
function replaceValues(map: unknown, prefix: 'env' | 'headers'): unknown {
  if (!isObject(map)) return placeholder(prefix);
  return Object.fromEntries(Object.keys(map).map((key) => [key, placeholder(`${prefix}.${key}`)]));
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
