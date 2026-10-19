/**
 * A deliberately narrow TOML reader for the harness configs, ported from
 * app/Sources/RouterCore/Discovery/MiniTOML.swift and MiniTOMLValues.swift.
 *
 * It scans line by line for table headers and parses values only under `mcp_servers` or
 * `mcpServers`, which is all the harness reconciliation needs. The two client CLIs spell the same
 * table differently, so both are read. It is not a TOML implementation.
 *
 * Anything it does not understand is a named error citing the line, never a skip. A reader that
 * silently ignores syntax it cannot parse produces a config that looks empty, which is the wrong
 * answer this reader exists to avoid.
 */

/** Why a TOML file could not be read. `description` is what a report shows. */
export class TOMLProblem extends Error {
  constructor(
    readonly line: number,
    readonly detail: string,
  ) {
    super(`line ${line}: ${detail}`);
    this.name = 'TOMLProblem';
  }
}

/** A parsed value as plain JSON: a string, a number, a boolean or an array of those. */
export type TomlValue = string | number | boolean | TomlValue[];

export interface TomlTable {
  path: string[];
  pairs: { key: string; value: TomlValue }[];
}

export interface TomlDocument {
  tables: TomlTable[];
}

export const SERVER_TABLE_NAMES = ['mcp_servers', 'mcpServers'];

const BASIC_STRING_DELIMITER = '"""';
const LITERAL_STRING_DELIMITER = "'''";

/** The first table whose path matches exactly. */
export function tableMatching(document: TomlDocument, path: string[]): TomlTable['pairs'] | undefined {
  return document.tables.find((t) => samePath(t.path, path))?.pairs;
}

/** Immediate child names of a table path, in the order they first appear. */
export function childNames(document: TomlDocument, prefix: string[]): string[] {
  const seen: string[] = [];
  for (const table of document.tables) {
    if (table.path.length !== prefix.length + 1 || !samePath(table.path.slice(0, prefix.length), prefix)) {
      continue;
    }
    const name = table.path[prefix.length];
    if (!seen.includes(name)) seen.push(name);
  }
  return seen;
}

export function parseMiniToml(text: string): TomlDocument {
  const scan = new Scan(text.split('\n'));
  const document: TomlDocument = { tables: [] };

  for (let next = scan.next(); next; next = scan.next()) {
    const { number, line } = next;
    if (line === '' || line.startsWith('#')) continue;
    refuseMultiLineString(line, number);

    if (line.startsWith('[')) {
      scan.openTable(line, number, document);
      continue;
    }
    // A key before any table header belongs to the root table, which the reader has no use for.
    if (!scan.started) continue;
    // Only the tables that matter are parsed for values.
    if (!isInteresting(scan.currentPath)) continue;
    scan.readPair(line, number);
  }
  scan.flush(document);
  return document;
}

function samePath(a: string[], b: string[]): boolean {
  return a.length === b.length && a.every((segment, i) => segment === b[i]);
}

function refuseMultiLineString(line: string, number: number): void {
  if (!line.includes(BASIC_STRING_DELIMITER) && !line.includes(LITERAL_STRING_DELIMITER)) return;
  throw new TOMLProblem(
    number,
    'multi-line strings are not supported by this reader, and skipping one could let its contents be read as table headers',
  );
}

function isInteresting(path: string[]): boolean {
  return path.length > 0 && SERVER_TABLE_NAMES.includes(path[0]);
}

/** The line cursor plus the table being filled. A class because reading a value can consume more than one line. */
class Scan {
  index = 0;
  currentPath: string[] = [];
  currentPairs: TomlTable['pairs'] = [];
  started = false;

  constructor(private readonly lines: string[]) {}

  next(): { number: number; line: string } | undefined {
    if (this.index >= this.lines.length) return undefined;
    const i = this.index;
    this.index += 1;
    return { number: i + 1, line: this.lines[i].trim() };
  }

  flush(document: TomlDocument): void {
    if (!this.started) return;
    document.tables.push({ path: this.currentPath, pairs: this.currentPairs });
    this.currentPairs = [];
  }

  /**
   * `[[array of tables]]` is refused only where it would change what a server is. Elsewhere it is
   * an ordinary uninteresting section, and refusing the whole file for it would lose every server
   * in the file.
   */
  openTable(line: string, number: number, document: TomlDocument): void {
    if (!line.endsWith(']')) throw new TOMLProblem(number, 'unterminated table header');
    const isArrayOfTables = line.startsWith('[[');
    if (isArrayOfTables && !line.endsWith(']]')) {
      throw new TOMLProblem(number, 'unterminated array-of-tables header');
    }
    this.flush(document);
    const inner = isArrayOfTables ? line.slice(2, -2) : line.slice(1, -1);
    this.currentPath = parseDottedKey(inner, number);
    if (isArrayOfTables && isInteresting(this.currentPath)) {
      throw new TOMLProblem(
        number,
        'arrays of tables are not supported by this reader, and a server declared as one would be read as a single table',
      );
    }
    this.started = true;
  }

  readPair(line: string, number: number): void {
    const equals = line.indexOf('=');
    if (equals < 0) throw new TOMLProblem(number, 'expected a key/value pair');
    const key = parseKey(line.slice(0, equals).trim(), number);
    const text = this.joinContinuation(line.slice(equals + 1).trim(), number);
    this.currentPairs.push({ key, value: parseValue(text, number) });
  }

  /** A value whose brackets do not balance on its own line continues onto the next ones. */
  private joinContinuation(first: string, number: number): string {
    if (!first.startsWith('[') || bracketDepth(first) <= 0) return first;
    let joined = first;
    while (bracketDepth(joined) > 0) {
      if (this.index >= this.lines.length) {
        throw new TOMLProblem(number, 'an array opened here and the file ended before it closed');
      }
      const continuation = this.lines[this.index].trim();
      this.index += 1;
      refuseMultiLineString(continuation, this.index);
      joined += ` ${continuation}`;
    }
    return joined;
  }
}

/** Open brackets minus closed ones, counting only those outside a quoted string. */
function bracketDepth(text: string): number {
  let depth = 0;
  let inQuotes = false;
  let quote = '"';
  let escaped = false;
  for (const character of text) {
    if (inQuotes) {
      if (escaped) {
        escaped = false;
      } else if (character === '\\' && quote === '"') {
        escaped = true;
      } else if (character === quote) {
        inQuotes = false;
      }
      continue;
    }
    switch (character) {
      case '"':
      case "'":
        inQuotes = true;
        quote = character;
        break;
      case '[':
        depth += 1;
        break;
      case ']':
        depth -= 1;
        break;
      case '#':
        return depth;
    }
  }
  return depth;
}

function parseDottedKey(text: string, line: number): string[] {
  const segments: string[] = [];
  let current = '';
  let inQuotes = false;
  let quote = '"';
  for (const character of text) {
    if (inQuotes) {
      if (character === quote) inQuotes = false;
      else current += character;
    } else if (character === '"' || character === "'") {
      inQuotes = true;
      quote = character;
    } else if (character === '.') {
      segments.push(current.trim());
      current = '';
    } else {
      current += character;
    }
  }
  if (inQuotes) throw new TOMLProblem(line, 'unterminated quoted key');
  segments.push(current.trim());
  const cleaned = segments.filter((segment) => segment !== '');
  if (cleaned.length === 0) throw new TOMLProblem(line, 'empty table header');
  return cleaned;
}

function parseKey(text: string, line: number): string {
  if (text === '') throw new TOMLProblem(line, 'empty key');
  if (text.startsWith('"') || text.startsWith("'")) return parseDottedKey(text, line).join('.');
  return text;
}

function parseValue(text: string, line: number): TomlValue {
  // Trailing comments are only stripped outside a string, so a `#` inside a value survives.
  const trimmed = stripComment(text);
  if (trimmed === '') throw new TOMLProblem(line, 'missing value');
  if (trimmed === 'true') return true;
  if (trimmed === 'false') return false;

  if (trimmed.startsWith('"')) return parseBasicString(trimmed, line);
  if (trimmed.startsWith("'")) {
    if (trimmed.length < 2 || !trimmed.endsWith("'")) {
      throw new TOMLProblem(line, 'unterminated literal string');
    }
    return trimmed.slice(1, -1);
  }
  if (trimmed.startsWith('[')) return arrayValue(trimmed, line);
  const digits = trimmed.replaceAll('_', '');
  if (/^[+-]?\d+$/.test(digits)) return Number(digits);
  throw new TOMLProblem(line, `unsupported value ${trimmed}`);
}

function arrayValue(trimmed: string, line: number): TomlValue[] {
  if (!trimmed.endsWith(']')) {
    throw new TOMLProblem(line, 'an array spanning several lines is not supported by this reader');
  }
  return splitArray(trimmed.slice(1, -1), line).map((part) => parseValue(part, line));
}

function stripComment(text: string): string {
  let result = '';
  let inQuotes = false;
  let quote = '"';
  let escaped = false;
  for (const character of text) {
    if (inQuotes) {
      result += character;
      if (escaped) {
        escaped = false;
      } else if (character === '\\' && quote === '"') {
        escaped = true;
      } else if (character === quote) {
        inQuotes = false;
      }
      continue;
    }
    if (character === '"' || character === "'") {
      inQuotes = true;
      quote = character;
      result += character;
      continue;
    }
    if (character === '#') break;
    result += character;
  }
  return result.trim();
}

/** The escapes a TOML basic string may carry. Anything else is an error rather than a guess. */
const ESCAPES: Record<string, string> = { n: '\n', t: '\t', r: '\r', '"': '"', '\\': '\\' };

function parseBasicString(text: string, line: number): string {
  let result = '';
  const characters = [...text];
  let closed = false;
  for (let i = 1; i < characters.length; i += 1) {
    const character = characters[i];
    if (character === '\\') {
      i += 1;
      if (i >= characters.length) throw new TOMLProblem(line, 'unterminated escape');
      const decoded = ESCAPES[characters[i]];
      if (decoded === undefined) throw new TOMLProblem(line, `unsupported escape \\${characters[i]}`);
      result += decoded;
    } else if (character === '"') {
      closed = true;
      break;
    } else {
      result += character;
    }
  }
  if (!closed) throw new TOMLProblem(line, 'unterminated string');
  return result;
}

function splitArray(text: string, line: number): string[] {
  const parts: string[] = [];
  let current = '';
  let inQuotes = false;
  let quote = '"';
  let depth = 0;
  for (const character of text) {
    if (inQuotes) {
      current += character;
      if (character === quote) inQuotes = false;
      continue;
    }
    switch (character) {
      case '"':
      case "'":
        inQuotes = true;
        quote = character;
        current += character;
        break;
      case '[':
        depth += 1;
        current += character;
        break;
      case ']':
        depth -= 1;
        current += character;
        break;
      case ',':
        if (depth === 0) {
          parts.push(current.trim());
          current = '';
        } else {
          current += character;
        }
        break;
      default:
        current += character;
    }
  }
  if (inQuotes) throw new TOMLProblem(line, 'unterminated string in array');
  const last = current.trim();
  if (last !== '') parts.push(last);
  return parts.filter((part) => part !== '');
}
