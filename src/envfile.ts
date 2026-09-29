import { existsSync, readFileSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, isAbsolute, join, resolve, sep } from 'node:path';
import { createHash } from 'node:crypto';

/**
 * Env files for a local stdio server.
 *
 * A local server keeps its keys where its own README says to: a `.env` or `.env.local` in its
 * package root. The router used to spawn it with the router's environment and the entry's `env`
 * block only, so a server whose keys lived in that file started with none of them and reported
 * every keyed capability as unconfigured — measured 2026-09-29 on `dossier`, whose four paid
 * research backends all read "no credentials" while the keys sat in `packages/mcp/.env.local`.
 * The workaround was an `sh -c "set -a; . .env.local; …"` wrapper per entry, which nobody writes
 * until after the failure.
 *
 * Resolution, in order:
 *   - `envFile: false` loads nothing.
 *   - `envFile: "<path>" | ["<path>", …]` loads exactly those, relative to the package root.
 *   - otherwise `.env` then `.env.local` in the package root, whichever exist.
 *
 * The package root is `cwd` when the entry sets one, else the nearest ancestor of the entry's
 * script that holds a package manifest. A workspace root is never inferred: a script inside a
 * monorepo would otherwise inherit the whole repo's `.env.local`, which is the app's secrets and
 * not the server's. Declare `envFile` explicitly to load one there.
 */

const MANIFESTS = ['package.json', 'pyproject.toml', 'Cargo.toml', 'go.mod'];
const WORKSPACE_MARKERS = ['pnpm-workspace.yaml', 'lerna.json', 'nx.json', 'turbo.json'];
const DEFAULT_FILES = ['.env', '.env.local'];

function isFile(p: string): boolean {
  try {
    return statSync(p).isFile();
  } catch {
    return false;
  }
}

function isWorkspaceRoot(dir: string): boolean {
  if (WORKSPACE_MARKERS.some((m) => existsSync(join(dir, m)))) return true;
  const pkg = join(dir, 'package.json');
  if (!isFile(pkg)) return false;
  try {
    return 'workspaces' in (JSON.parse(readFileSync(pkg, 'utf8')) as object);
  } catch {
    return false;
  }
}

/** Nearest manifest-holding ancestor of `file`, stopping at the home directory and at a git root. */
function packageRootOf(file: string): string | undefined {
  const home = homedir();
  let dir = dirname(file);
  for (;;) {
    if (dir === home || dir === dirname(dir)) return undefined;
    if (MANIFESTS.some((m) => existsSync(join(dir, m)))) {
      return isWorkspaceRoot(dir) ? undefined : dir;
    }
    if (existsSync(join(dir, '.git'))) return undefined;
    dir = dirname(dir);
  }
}

/**
 * The script a stdio entry runs: the first absolute path to an existing file, args before
 * command, because the command is usually an interpreter (`node`, `python3`) whose own install
 * directory says nothing about the server. Installed packages and app bundles are skipped.
 */
function entryScript(command: string, args: string[]): string | undefined {
  for (const c of [...args, command]) {
    if (!isAbsolute(c) || !isFile(c)) continue;
    if (c.includes(`${sep}node_modules${sep}`) || c.includes(`.app${sep}`)) continue;
    return c;
  }
  return undefined;
}

export function resolveEnvFiles(
  command: string,
  args: string[],
  cwd: string | undefined,
  envFile: string | string[] | false | undefined
): string[] {
  if (envFile === false) return [];
  const root = cwd ?? (() => {
    const script = entryScript(command, args);
    return script ? packageRootOf(script) : undefined;
  })();
  if (envFile !== undefined) {
    const list = Array.isArray(envFile) ? envFile : [envFile];
    return list.map((f) => (isAbsolute(f) ? f : resolve(root ?? process.cwd(), f)));
  }
  if (!root) return [];
  return DEFAULT_FILES.map((f) => join(root, f)).filter(isFile);
}

/**
 * Parse dotenv syntax: `KEY=value`, an optional `export ` prefix, `#` comments, single or
 * double quotes, and `\n` escapes inside double quotes. No interpolation.
 */
export function parseDotenv(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const m = /^(?:export\s+)?([A-Za-z_][A-Za-z0-9_.]*)\s*=\s*(.*)$/.exec(line);
    if (!m) continue;
    let v = m[2];
    const q = v[0];
    if ((q === '"' || q === "'") && v.lastIndexOf(q) > 0) {
      v = v.slice(1, v.lastIndexOf(q));
      if (q === '"') v = v.replace(/\\n/g, '\n');
    } else {
      v = v.replace(/\s+#.*$/, '').trim();
    }
    out[m[1]] = v;
  }
  return out;
}

/** Merge the files in order, later files winning. A declared file that is missing is an error. */
export function readEnvFiles(files: string[]): Record<string, string> {
  const env: Record<string, string> = {};
  for (const f of files) {
    if (!isFile(f)) throw new Error(`env file not found: ${f}`);
    Object.assign(env, parseDotenv(readFileSync(f, 'utf8')));
  }
  return env;
}

/** Content digest of the files, so a rotated key changes the upstream's config identity. */
export function envFilesDigest(files: string[]): string {
  const h = createHash('sha256');
  for (const f of files) {
    h.update(f);
    h.update(isFile(f) ? readFileSync(f) : '<missing>');
  }
  return h.digest('hex').slice(0, 16);
}
