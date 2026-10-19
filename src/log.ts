import { appendFileSync, existsSync, mkdirSync, readdirSync, renameSync, rmSync, statSync } from 'node:fs';
import { basename, dirname } from 'node:path';

/**
 * How the log file stays bounded. `maxBytes` is the size the active file may not grow past;
 * `keep` is how many rotated generations (`router.log.1` newest … `router.log.<keep>` oldest)
 * survive. `keep: 0` restarts the active file and keeps none.
 */
export interface LogPolicy {
  maxBytes: number;
  keep: number;
}

export const DEFAULT_LOG_POLICY: LogPolicy = { maxBytes: 10 * 1024 * 1024, keep: 5 };

let logFile: string | undefined;
let verbose = false;
let policy: LogPolicy = DEFAULT_LOG_POLICY;

export function configureLogging(
  file: string | undefined,
  isVerbose: boolean,
  rotation: LogPolicy = DEFAULT_LOG_POLICY
): void {
  logFile = file;
  verbose = isVerbose;
  policy = rotation;
  if (logFile) mkdirSync(dirname(logFile), { recursive: true });
}

/** Indices of `file`'s rotated generations, whatever they are. */
function rotatedIndices(file: string): number[] {
  const prefix = basename(file) + '.';
  return readdirSync(dirname(file))
    .filter((name) => name.startsWith(prefix) && /^\d+$/.test(name.slice(prefix.length)))
    .map((name) => Number(name.slice(prefix.length)));
}

/**
 * Rotate before a write that would take the active file past the cap, so the file never grows
 * past it. The file is opened by path on every write, so nothing holds a descriptor on the file
 * that has just been renamed: the next write creates a fresh active file.
 *
 * A line larger than the cap by itself is written to an empty file rather than rotating for ever.
 */
function rotateFor(file: string, bytes: number): void {
  let size: number;
  try {
    size = statSync(file).size;
  } catch {
    return; // no file yet
  }
  if (size === 0 || size + bytes <= policy.maxBytes) return;

  const { keep } = policy;
  const archive = (n: number) => `${file}.${n}`;
  // Generations past `keep` were left by an earlier, larger setting, and nothing else would remove them.
  for (const n of rotatedIndices(file)) if (n > keep) rmSync(archive(n), { force: true });
  if (keep === 0) {
    rmSync(file, { force: true });
    return;
  }
  rmSync(archive(keep), { force: true });
  for (let n = keep - 1; n >= 1; n--) {
    if (existsSync(archive(n))) renameSync(archive(n), archive(n + 1));
  }
  renameSync(file, archive(1));
}

function emit(level: string, msg: string): void {
  const line = `${new Date().toISOString()} ${level.padEnd(5)} ${msg}`;
  // stdout is never used for logs: it stays clean in case this is ever run over stdio.
  // With a log file, stderr is launchd's uncapped capture, so only errors go there; the file keeps every line.
  if (!logFile || level === 'error') process.stderr.write(line + '\n');
  if (logFile) {
    // Everything here is synchronous, so two emits never interleave, and a rotation finishes before the line it precedes is written.
    try {
      rotateFor(logFile, Buffer.byteLength(line + '\n'));
    } catch {
      /* a failed rotation must not cost the line: the append below still runs */
    }
    try {
      appendFileSync(logFile, line + '\n');
    } catch {
      /* logging must never take the router down */
    }
  }
}

export const log = {
  info: (msg: string) => emit('info', msg),
  warn: (msg: string) => emit('warn', msg),
  error: (msg: string) => emit('error', msg),
  debug: (msg: string) => {
    if (verbose) emit('debug', msg);
  },
};
