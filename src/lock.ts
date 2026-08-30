import { openSync, closeSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { homedir } from 'node:os';
import { exclusiveOpenFlags } from './platform.js';
import { log } from './log.js';

/**
 * The cross-process mutual exclusion a shared config file needs — node's half.
 *
 * This is a port of `app/Sources/RouterCore/Config/ConfigMutationLock.swift`, and it is a port
 * rather than a second design on purpose: the two routers write the same files in the same home,
 * so a lock only one of them takes excludes nothing. Every rule that file records is kept, and the
 * places where node cannot express the Swift version's mechanism are named below rather than left
 * to be rediscovered.
 *
 * **The lock object is a sidecar, `<file>.lock`, never the file itself.** Every writer here commits
 * by writing a temporary file and renaming it over the destination, which replaces the inode. A
 * lock taken on the config would therefore be held on a file that no longer occupies that path, and
 * a second writer opening the new inode would be excluded by nothing. The sidecar is never renamed,
 * never deleted, and never read.
 *
 * **`O_EXLOCK` is how node reaches `flock(2)`.** Node exposes no `flock` binding at all, so the
 * lock is taken by the BSD open flag that applies the same flock-style lock atomically at open
 * time; `O_NONBLOCK` beside it makes the attempt fail with `EAGAIN` instead of blocking, which is
 * `LOCK_EX | LOCK_NB`. Two consequences, both measured on node v22.23.1 / darwin on 2026-08-22:
 *
 *   · `fs.constants.O_EXLOCK` is `undefined` in this build, so the numeric value is used. It is
 *     `0x20` in macOS's `fcntl.h` and has been since BSD; `O_CREAT` agreeing with
 *     `fs.constants.O_CREAT` at `0x200` is the cheap corroboration that the table is the right one.
 *   · the two implementations genuinely exclude each other. With node holding `O_EXLOCK` on the
 *     sidecar, a second process taking `flock(fd, LOCK_EX | LOCK_NB)` on it was refused with
 *     `EWOULDBLOCK` and acquired the moment node closed; with that process holding `LOCK_EX`, node's
 *     open was refused with `EAGAIN`. Both directions, so this is one lock and not two.
 *
 * The kernel releases either form when the descriptor closes, including when the process is killed,
 * so a crash cannot leave a lock file that deadlocks the next run.
 *
 * **WIN17 — that whole paragraph was a macOS paragraph, and off macOS it was excluding nothing.**
 * The flag word above returns `EINVAL` on Windows, and `EINVAL` was in the *unsupported* set below,
 * so every call took the "this filesystem implements no advisory locking, proceed unlocked" branch
 * — which is silent by design, because it was written for a network mount where there was never
 * any exclusion to lose. Measured 2026-08-30 on node v24.19.0 against `dist/lock.js` as shipped:
 * two processes were inside the same critical section simultaneously, and **no `.lock` sidecar was
 * created at all**. `platform.ts`'s `exclusiveOpenFlags()` now supplies the flag word and both
 * errno sets per platform, with Windows's unsupported set deliberately empty — the exclusion there
 * is a share mode the kernel applies to the handle, not a filesystem feature a volume might lack,
 * so no errno legitimately means "carry on unlocked" and an unexpected one becomes a visible
 * `couldNotOpen`. The Windows mechanism was measured to hold in all three directions that matter:
 * a second process refused `EBUSY` while the holder lived, acquiring within 200 ms of its close,
 * and a holder killed with SIGKILL released it.
 */

/** The daemon's bound — a contended control request fails fast and visibly rather than stalling. */
export const DAEMON_TIMEOUT_MS = 2000;
/**
 * The one-shot's bound. `watch`, `index` and `import` are launchd fires or CLI invocations with
 * nothing waiting on them, so they can afford to wait out a whole control-API burst rather than
 * abandon an index they have already paid for.
 */
export const WATCHER_TIMEOUT_MS = 10000;

/**
 * The flag word and the two errno sets, chosen once for this platform.
 *
 * Resolved at module load rather than per call: `exclusiveOpenFlags()` reads `process.platform` and
 * `fs.constants`, neither of which moves, and the flags are wanted inside a retry loop.
 * `platform.ts` carries the measurements behind both branches.
 */
const LOCK_OPEN = exclusiveOpenFlags();

/** How long a refused attempt waits before trying again. `usleep(2000)` on the Swift side. */
const RETRY_INTERVAL_MS = 2;

export type LockFailure = 'notAcquired' | 'reentrant' | 'couldNotOpen';

/**
 * Says what happened, who is responsible, and what was not done — the Swift wording verbatim, so
 * the two routers do not report the same event in two sentences. Blames nobody: another process
 * writing the file is ordinary, not misuse.
 */
export class LockProblem extends Error {
  constructor(
    readonly kind: LockFailure,
    message: string
  ) {
    super(message);
    this.name = 'LockProblem';
  }

  static notAcquired(path: string, timeoutMs: number): LockProblem {
    return new LockProblem(
      'notAcquired',
      `could not lock ${path} within ${timeoutMs}ms; another process is writing it. ` +
        `Nothing was changed.`
    );
  }

  static reentrant(path: string): LockProblem {
    return new LockProblem('reentrant', `${path} is already locked by this process. Nothing was changed.`);
  }

  static couldNotOpen(lockPath: string, reason: string): LockProblem {
    return new LockProblem(
      'couldNotOpen',
      `could not open the lock file ${lockPath} (${reason}). Nothing was changed.`
    );
  }
}

/**
 * The path of the sidecar for a given file.
 *
 * Standardised first, so two spellings of one file — a `..` in the middle, a trailing slash, a
 * leading `~` — resolve to one lock and one nesting key. Without that a nested acquire through the
 * other spelling would evade the guard below, spin the whole timeout, and then report that
 * *another process* holds the file.
 *
 * `path.resolve` is the closest node has to `NSString.standardizingPath`: it resolves `.`, `..` and
 * a trailing slash against the working directory. The tilde is expanded here because `resolve` does
 * not, which is the one part of the Swift behaviour it does not already carry. Neither resolves
 * symlinks, so two spellings that differ only through a symlinked home still take two locks — the
 * Swift side has the same hole and this does not widen it.
 */
export function lockPathFor(configPath: string): string {
  const expanded = configPath.startsWith('~/') ? `${homedir()}/${configPath.slice(2)}` : configPath;
  return `${resolve(expanded)}.lock`;
}

/** The environment override, applied to either default. */
export function lockTimeoutMs(fallback: number, env: NodeJS.ProcessEnv = process.env): number {
  const raw = env.MCPR_CONFIG_LOCK_TIMEOUT_MS;
  if (raw === undefined) return fallback;
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed <= 0) return fallback;
  return parsed;
}

/**
 * Lock paths held on this process's one thread.
 *
 * A second `open` of the same lock file inside one process produces a second open file description
 * that blocks against the first. Across two *processes* that is the lock working. What must not
 * block is a **nested** acquire on one call stack, which can never be released and would spin the
 * whole timeout before reporting that another process is writing the file — a false statement about
 * a bug in this one.
 *
 * A module-level set rather than the Swift version's thread-local, and sound for the same reason it
 * gives: `body` is synchronous. Node runs this code on one thread and cannot interleave another
 * caller into a synchronous acquire-body-release span, so "held anywhere in this process" and "held
 * on this call stack" are the same set here.
 */
const held = new Set<string>();

/** A synchronous sleep. `Atomics.wait` is the only one node has that does not spin a core. */
const parkingLot = new Int32Array(new SharedArrayBuffer(4));
function sleepSync(ms: number): void {
  Atomics.wait(parkingLot, 0, 0, ms);
}

function errnoOf(err: unknown): string {
  return (err as NodeJS.ErrnoException).code ?? 'unknown';
}

/**
 * Run `body` with an exclusive cross-process lock on the file at `path`.
 *
 * Synchronous on purpose. Every caller's critical section is a load, a merge and a save — all
 * synchronous — and making this async would invite an `await` inside the lock, which is exactly the
 * seconds-long hold this exists to avoid.
 */
export function withExclusiveLock<T>(path: string, timeoutMs: number, body: () => T): T {
  const lock = lockPathFor(path);

  if (held.has(lock)) throw LockProblem.reentrant(path);
  held.add(lock);
  try {
    try {
      mkdirSync(dirname(lock), { recursive: true });
    } catch {
      /* the open below reports what actually stops the lock being taken */
    }

    const deadline = Date.now() + timeoutMs;
    let descriptor: number;
    for (;;) {
      try {
        descriptor = openSync(lock, LOCK_OPEN.flags, 0o600);
        break;
      } catch (err: unknown) {
        const code = errnoOf(err);
        /*
         * A filesystem that does not implement advisory locking at all — some network mounts — must
         * not turn a write that worked before this item into one that fails. There was never any
         * exclusion there to lose, so the write proceeds unlocked.
         *
         * "Declared, never silent" is now literally true rather than an intention. This branch was
         * a bare `return body()`, and on Windows every single call reached it via `EINVAL` and said
         * nothing (WIN17). A warning costs one line in a log nobody reads until the day two writers
         * corrupt a config, which is the only day it matters. The set is empty on Windows, so this
         * cannot be reached there at all.
         */
        if (LOCK_OPEN.unsupported.includes(code)) {
          log.warn(
            `lock: ${lock} reports no support for ${LOCK_OPEN.mechanism} (${code}); ` +
              'writing without cross-process exclusion.'
          );
          return body();
        }
        if (!LOCK_OPEN.contended.includes(code)) {
          throw LockProblem.couldNotOpen(lock, (err as Error).message);
        }
        if (Date.now() >= deadline) throw LockProblem.notAcquired(path, timeoutMs);
        sleepSync(RETRY_INTERVAL_MS);
      }
    }

    try {
      return body();
    } finally {
      // Every form of this lock is released by the close and only by the close — `flock` and
      // `O_EXLOCK` on macOS, the handle's exclusive share mode on Windows. There is no separate
      // unlock call to make on either, and both are released by the kernel when the process dies,
      // which was measured on Windows with a SIGKILL'd holder.
      closeSync(descriptor);
    }
  } finally {
    held.delete(lock);
  }
}
