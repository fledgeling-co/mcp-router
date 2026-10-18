/**
 * The argv half of R22's scrub, applied to `GET /servers` before it serialises each upstream's
 * args (DEF-070).
 *
 * `GET /servers` is not token-gated, so anything that can open a loopback socket reads every
 * stdio upstream's `args`. An argument list is a credential channel: `--token=…`, `--api-key …`
 * and a connection string with an inline password are each the one place a config writer had to
 * put a secret. This module reads the shape of each argument and then removes any literal the
 * router knows, as the diagnostics bundle does.
 *
 * `app/Sources/RouterCore/Diagnostics/ArgvRedaction.swift` implements the same rules with the same
 * replacement strings. The vector file `app/Tests/RouterCoreTests/Vectors/argv-redact.json` is
 * generated from this module by `scripts/parity/generate-argv-vectors.mjs`, and the Swift suite
 * reads it back, so a rule changed in one language and not the other fails.
 *
 * The rules, applied to each argument in order:
 *   1. A value consumed by a secret-named flag is replaced. `--name=value` keeps its name and loses
 *      its value. `--name value` loses the next argument, unless that argument is itself a flag
 *      (`--…`), in which case the first flag stood alone. A non-string value is replaced too.
 *   2. `NAME=value` with a secret-named `NAME` loses its value.
 *   3. In a URL the password is replaced and the user kept. A userinfo with no password is
 *      replaced whole, because `https://<token>@host` carries the token in the user position.
 *   4. A query parameter with a secret-named key loses its value.
 *   5. Every literal needle is replaced with `<redacted:LABEL>`.
 */
import { isHttp, isStdio, type UpstreamConfig } from './config.js';

/** What a structural rule writes in place of a value. */
export const REDACTED = '<redacted>';

/** The shortest secret that may be scrubbed from free text. Matches `SecretNeedles`. */
export const MINIMUM_NEEDLE_LENGTH = 8;

/** The name segments that mark a value as a secret. Matches `ArgvRedaction.secretSegments`. */
const SECRET_SEGMENTS = new Set([
  'token', 'tokens', 'secret', 'secrets', 'password', 'passwd', 'pass', 'pwd', 'key', 'apikey',
  'auth', 'authorization', 'bearer', 'credential', 'credentials', 'cookie', 'cookies',
]);

/** `--name=value` or `-name=value`. */
const FLAG_ASSIGN = /^(--?)([A-Za-z0-9][A-Za-z0-9._-]*)=([\s\S]*)$/;
/** `--name` or `-name` standing alone. */
const FLAG_BARE = /^--?([A-Za-z0-9][A-Za-z0-9._-]*)$/;
/** `NAME=value`. */
const ENV_ASSIGN = /^([A-Za-z_][A-Za-z0-9_]*)=([\s\S]*)$/;
/** Everything between `://` and the last `@` of the authority. */
const USERINFO = /:\/\/([^\/?#\s]*)@/g;
/** A query parameter: its separator, its key and its value. */
const QUERY_PARAMETER = /([?&])([A-Za-z0-9._-]+)=([^&#\s]*)/g;

/** One literal the router can name as a secret, with the config key it came from. */
export interface Needle {
  label: string;
  literal: string;
}

const graphemes = new Intl.Segmenter(undefined, { granularity: 'grapheme' });

/** Swift's `String.count`: grapheme clusters, not UTF-16 units. */
function graphemeCount(text: string): number {
  return [...graphemes.segment(text)].length;
}

/** Whether a flag or parameter name marks its value as a secret. */
export function isSecretName(name: string): boolean {
  return name
    .toLowerCase()
    .split(/[-_.]/)
    .some((segment) => SECRET_SEGMENTS.has(segment));
}

/**
 * The literal secrets this router can name: env values, header values, URL passwords, and the
 * control token. The same set `SecretNeedles.collect` builds, in the same order, with the same
 * floor.
 */
export function collectNeedles(upstreams: Iterable<UpstreamConfig>, controlToken: string): Needle[] {
  const needles: Needle[] = [];
  const consider = (label: string, value: string) => {
    if (graphemeCount(value) >= MINIMUM_NEEDLE_LENGTH) needles.push({ label, literal: value });
  };
  for (const u of upstreams) {
    if (isStdio(u)) {
      for (const [key, value] of Object.entries(u.env)) consider(`${u.name}.env.${key}`, value);
    }
    if (isHttp(u)) {
      for (const [key, value] of Object.entries(u.headers)) consider(`${u.name}.headers.${key}`, value);
      const password = urlPassword(u.url);
      if (password !== undefined) consider(`${u.name}.url.userinfo`, password);
    }
  }
  consider('control.token', controlToken);
  return needles;
}

/** The password in `scheme://user:password@host/…`, or undefined. Matches `URLUserinfo.secret`. */
function urlPassword(url: string): string | undefined {
  const schemeEnd = url.indexOf('://');
  if (schemeEnd < 0) return undefined;
  const rest = url.slice(schemeEnd + 3);
  const authorityEnd = rest.search(/[\/?#]/);
  const authority = authorityEnd < 0 ? rest : rest.slice(0, authorityEnd);
  const at = authority.lastIndexOf('@');
  if (at < 0) return undefined;
  const userinfo = authority.slice(0, at);
  const colon = userinfo.indexOf(':');
  if (colon < 0) return undefined;
  const password = userinfo.slice(colon + 1);
  return password === '' ? undefined : password;
}

/**
 * An `args` value as `describe` emits it. An array keeps its element types; a string is one
 * argument; any other value is passed through unchanged.
 */
export function redactArgs(args: unknown, needles: Needle[]): unknown {
  if (Array.isArray(args)) return redactItems(args, needles);
  if (typeof args === 'string') return redactItems([args], needles)[0];
  return args;
}

function redactItems(items: unknown[], needles: Needle[]): unknown[] {
  const out: unknown[] = [];
  // Set by a secret-named flag written without `=`: the next argument is its value.
  let valueNext = false;
  for (const item of items) {
    if (typeof item !== 'string') {
      // A non-string is never a flag, so it can only be the value a flag asked for.
      out.push(valueNext ? REDACTED : item);
      valueNext = false;
      continue;
    }
    if (valueNext) {
      valueNext = false;
      if (!item.startsWith('--')) {
        out.push(REDACTED);
        continue;
      }
    }
    const assign = FLAG_ASSIGN.exec(item);
    if (assign && isSecretName(assign[2])) {
      out.push(`${assign[1]}${assign[2]}=${REDACTED}`);
      continue;
    }
    const bare = FLAG_BARE.exec(item);
    if (bare && isSecretName(bare[1])) {
      out.push(item);
      valueNext = true;
      continue;
    }
    const env = ENV_ASSIGN.exec(item);
    if (env && isSecretName(env[1])) {
      out.push(`${env[1]}=${REDACTED}`);
      continue;
    }
    out.push(scrubText(item, needles));
  }
  return out;
}

/** Rules 3, 4 and 5, in that order. */
function scrubText(text: string, needles: Needle[]): string {
  const withoutPassword = text.replace(USERINFO, (_match, userinfo: string) => {
    if (userinfo === '') return '://@';
    const colon = userinfo.indexOf(':');
    return colon < 0 ? `://${REDACTED}@` : `://${userinfo.slice(0, colon)}:${REDACTED}@`;
  });
  const withoutQueryValue = withoutPassword.replace(
    QUERY_PARAMETER,
    (match, separator: string, key: string) =>
      isSecretName(key) ? `${separator}${key}=${REDACTED}` : match,
  );
  return scrubLiterals(withoutQueryValue, needles);
}

/** Every form of every needle, longest first. Equal lengths keep the order the needles came in. */
function literalForms(needles: Needle[]): { text: string; label: string }[] {
  return needles
    .flatMap(({ label, literal }) => variants(literal).map((text) => ({ text, label })))
    .sort((a, b) => graphemeCount(b.text) - graphemeCount(a.text));
}

/** The literal, its percent-encoded form, and its base64 form, where they differ. */
function variants(literal: string): string[] {
  const forms = [literal];
  const encoded = percentEncode(literal);
  if (encoded !== literal) forms.push(encoded);
  const base64 = Buffer.from(literal, 'utf8').toString('base64');
  if (base64 !== literal) forms.push(base64);
  return forms;
}

/**
 * Foundation's `addingPercentEncoding(withAllowedCharacters: .alphanumerics)`: every character
 * outside letters and numbers is escaped as its UTF-8 bytes, in uppercase hex.
 */
function percentEncode(text: string): string {
  let out = '';
  for (const ch of text) {
    if (/^[\p{L}\p{N}]$/u.test(ch)) {
      out += ch;
    } else {
      for (const byte of Buffer.from(ch, 'utf8')) {
        out += `%${byte.toString(16).toUpperCase().padStart(2, '0')}`;
      }
    }
  }
  return out;
}

function scrubLiterals(text: string, needles: Needle[]): string {
  let out = text;
  for (const form of literalForms(needles)) {
    if (form.text === '' || !out.includes(form.text)) continue;
    out = out.split(form.text).join(`<redacted:${form.label}>`);
  }
  return out;
}
