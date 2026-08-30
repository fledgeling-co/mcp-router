/**
 * The one place in the router that reads `process.platform`.
 *
 * WIN17. Before this file there was not a single platform branch in `src/`, which did not mean the
 * router was portable — it meant every platform decision was made once, on macOS, and taken
 * everywhere. Five macOS-only binaries were invoked unconditionally, and every one of them fails on
 * Windows in under a millisecond into a caller that reads the empty result as data. Measured
 * 2026-08-30 on Windows 11 / node v24.19.0, each by `execFileSync` from this repository:
 *
 *   | invocation, as shipped                      | on Windows            | what the caller did with it        |
 *   |---|---|---|
 *   | `/usr/bin/open <url>`      (index.ts auth)   | ENOENT, <1 ms         | callback ignores `err` — silent    |
 *   | `ps -o pid=,lstart=`       (sessions.ts)     | ENOENT, <1 ms         | every live session read `exited`    |
 *   | `/bin/ps -o pid=,rss=`     (pool.ts)         | ENOENT, <1 ms         | every upstream reported 0 MB        |
 *   | `/usr/sbin/lsof`           (usage.ts)        | ENOENT, <1 ms         | every call record unattributed      |
 *   | `/bin/launchctl kickstart` (watch.ts)        | ENOENT, <1 ms         | "could not restart; run it manually" |
 *
 * Only the last of those said anything. The rule this file exists to keep is that a platform
 * difference is a branch somebody can read, and that a capability the host does not have is
 * *reported* rather than absorbed into a plausible-looking empty answer.
 *
 * ## What is genuinely weaker on Windows, and is not pretended otherwise
 *
 * - **Supervision.** launchd's `KeepAlive` restarts the job when it exits, and three places in this
 *   router depend on that: `index.ts`'s deliberate non-zero exit after a stalled shutdown,
 *   `watch.ts`'s restart after adopting a new upstream, and `router.ts`'s note about a hung close.
 *   Windows has no equivalent this daemon can assume, so `supervisor()` reports `none` and the
 *   guarantee is restated at `serve` startup rather than left implied. WIN23 owns choosing one.
 * - **Automatic adoption of a newly-added server.** launchd's `WatchPaths` fires `mcpr watch` on
 *   every write to `~/.claude.json`, so a server added by `claude mcp add` reaches the router on
 *   its own. Nothing does that on Windows, so `configWatcher()` reports `none` and the usage text,
 *   the `serve` banner and `watch`'s own log all say `mcpr watch` has to be run by hand there.
 *   Restating this in the product's output rather than only here is the whole of that fix: the
 *   usage text used to print "(run by launchd on file change)" to a Windows user.
 * - **Client attribution.** `lsof` names the process on the other end of a loopback socket *and*
 *   its working directory. `netstat -ano` gives the pid; a foreign process's cwd is not readable on
 *   Windows without opening the process, so usage records there carry a pid and an image name and
 *   no project. That is a smaller record, not a wrong one.
 * - **Session socket presence.** On macOS the session socket is a file and `existsSync` settles it.
 *   On Windows it is a named pipe (`\\.\pipe\cc-msg-<hex>`, measured in this machine's own registry)
 *   and `existsSync` of a *live* pipe returns `false` — measured against `\\.\pipe\InitShutdown`.
 *   A `readdir` of `\\.\pipe\` does see them, but cost 7 204 ms for 57 792 entries, so it is not an
 *   existence check either. Presence there is `indeterminate` and the connect attempt settles it.
 *
 * ## What proves this file, and what deliberately does not
 *
 * `scripts/e2e-platform.mjs`, run on the host whose behaviour is in question, is the oracle for
 * everything here. The differential parity corpus is **not**, deliberately, and
 * `scripts/parity/generate-vectors.mjs` carries that position in full: a parity vector compares two
 * implementations of one behaviour, and nothing in this file has a second implementation — the
 * Swift `RouterCore` it is compared against builds only on macOS, where every Windows branch below
 * is dead. Windows behaviour is out of the parity corpus on purpose, and its oracle is named.
 */
import { execFileSync, execFile } from 'node:child_process';
import { existsSync, constants as fsConstants } from 'node:fs';
import { delimiter } from 'node:path';

export const PLATFORM: NodeJS.Platform = process.platform;
export const IS_WINDOWS = PLATFORM === 'win32';
export const IS_DARWIN = PLATFORM === 'darwin';

/**
 * PATH's separator, which is `;` on Windows and `:` everywhere else.
 *
 * Named here rather than taken inline because `pool.ts` split on a literal `':'`, and on Windows
 * that turns one entry `C:\Program Files\nodejs` into two — `C` and `\Program Files\nodejs` —
 * before handing the result to every spawned upstream. A child whose PATH has been shredded that
 * way does not fail loudly; it reports the capability missing.
 */
export const PATH_LIST_SEPARATOR = delimiter;

/* ------------------------------------------------------------------ the shell-out helper */

/**
 * Run a command and return its stdout, keeping whatever it managed to print when it exited
 * non-zero.
 *
 * Both platforms need that, for the same reason and from two different measurements. macOS `ps`
 * rejects a whole invocation over one out-of-range pid, prints nothing, and exits 1 — the defect
 * `sessions.ts` already carries a regression arm for. Windows PowerShell's `Get-Process` given
 * `<live pid>,4194303,999999` exits 1 as well, but *does* print the row for the live pid; measured
 * 2026-08-30, `status: 1` with `stdout: '268524 1788041017\r\n'`. Reading only the resolved value
 * would have discarded a correct answer on one platform and a partial one on the other.
 */
function stdoutOf(command: string, args: string[], timeoutMs: number): { out: string; ran: boolean } {
  try {
    return { out: execFileSync(command, args, { encoding: 'utf8', timeout: timeoutMs, maxBuffer: 4 * 1024 * 1024 }), ran: true };
  } catch (err) {
    const e = err as { stdout?: unknown; code?: string; status?: number | null };
    // ENOENT/EACCES mean the probe itself is not on this machine, which is a different fact from
    // "the probe ran and found nothing". Callers must be able to tell those apart.
    const missing = e.code === 'ENOENT' || e.code === 'EACCES' || e.code === 'EPERM';
    return { out: String(e.stdout ?? ''), ran: !missing };
  }
}

/**
 * The same contract as `stdoutOf`, off the event loop.
 *
 * WIN17 gap-fix. The synchronous helper above was used by `residentKb` and `peerOfLocalPort`, both
 * of which are declared `async` and neither of which was: `execFileSync` blocks the whole thread,
 * so an `await` on them yielded to nothing. Measured 2026-08-30 on this machine, from node, with a
 * 10 ms interval sampling its own drift:
 *
 *   | call                                | wall   | event-loop lag |
 *   |---|---|---|
 *   | `peerOfLocalPort` (netstat + PS)    |  93 ms |  83 ms         |
 *   | `residentKb` (one PowerShell)       | 433 ms | 423 ms         |
 *   | a bare synchronous `Get-Process`    | 372 ms | —              |
 *
 * `peerOfLocalPort` runs once per accepted connection (`router.ts`'s `http.on('connection')`) and
 * is awaited again on the request path, so the first request from each new client stopped the
 * router for roughly 0.45 s — timers, other sockets, in-flight upstream reads, all of it. The macOS
 * path this replaced was `execFile` throughout and never did that. Lag here is now the process
 * spawn only: a few milliseconds, whatever the child costs.
 *
 * `stdout` is still read off the *error* as well as the resolved value, for the reason above: both
 * `ps` and `Get-Process` exit non-zero over an unusable pid and one of them still prints the good
 * rows.
 */
function stdoutOfAsync(command: string, args: string[], timeoutMs: number): Promise<{ out: string; ran: boolean }> {
  return new Promise((resolve) => {
    execFile(command, args, { encoding: 'utf8', timeout: timeoutMs, maxBuffer: 4 * 1024 * 1024 }, (err, stdout) => {
      if (!err) return resolve({ out: String(stdout ?? ''), ran: true });
      const code = (err as NodeJS.ErrnoException).code;
      const missing = code === 'ENOENT' || code === 'EACCES' || code === 'EPERM';
      resolve({ out: String(stdout ?? ''), ran: !missing });
    });
  });
}

/** The argv every PowerShell probe here uses. `-NoProfile` keeps a user's profile out of the
 *  timings and the output; `-NonInteractive` keeps a prompt from becoming a hang. */
const powershellArgv = (script: string): string[] => ['-NoProfile', '-NonInteractive', '-Command', script];

/** One PowerShell invocation, synchronously. Only `processStartSeconds` still needs this — see the
 *  note there about why that one probe is not async. */
function powershell(script: string, timeoutMs = 20_000): { out: string; ran: boolean } {
  return stdoutOf('powershell.exe', powershellArgv(script), timeoutMs);
}

/** One PowerShell invocation, off the event loop. */
function powershellAsync(script: string, timeoutMs = 20_000): Promise<{ out: string; ran: boolean }> {
  return stdoutOfAsync('powershell.exe', powershellArgv(script), timeoutMs);
}

/* ------------------------------------------------------------------ opening a browser */

/**
 * The command that hands a URL to the user's browser, or `undefined` where this platform has none.
 *
 * Windows uses `rundll32 url.dll,FileProtocolHandler` rather than `cmd /c start "" <url>`, and the
 * reason is the argument rather than the executable: `start` is a `cmd` builtin, so the URL passes
 * through the command interpreter, which splits on `&` and expands `%NAME%`. An OAuth
 * authorization URL is mostly `&` and percent-escapes, so that route mangles exactly the input this
 * function exists for. `rundll32` is spawned directly with the URL as one argv entry and no shell
 * in the path at all. Both `rundll32.exe` and `url.dll` were confirmed present in
 * `C:\Windows\System32` on 2026-08-30.
 */
export function browserOpenCommand(url: string): { command: string; args: string[] } | undefined {
  switch (PLATFORM) {
    case 'darwin':
      return { command: '/usr/bin/open', args: [url] };
    case 'win32':
      return { command: 'rundll32.exe', args: ['url.dll,FileProtocolHandler', url] };
    default:
      return { command: 'xdg-open', args: [url] };
  }
}

/**
 * Open an authorization URL in the user's browser. Rejects when it could not.
 *
 * The rejection is the point. `index.ts` called `execFile('/usr/bin/open', [url], () => undefined)`,
 * whose callback discards the error — so on Windows the browser never opened, nothing was printed,
 * and the CLI went straight into its five-minute poll for a token that could not arrive. The
 * `needs sign-in` state was unrecoverable and looked like a hang.
 *
 * The scheme is checked before the URL reaches a handler that would open anything: on Windows
 * `FileProtocolHandler` opens `file:` URLs too, and this argument comes off an HTTP response.
 */
export function openInBrowser(url: string): Promise<void> {
  let scheme: string;
  try {
    scheme = new URL(url).protocol;
  } catch {
    return Promise.reject(new Error(`not a URL: ${url.slice(0, 120)}`));
  }
  if (scheme !== 'http:' && scheme !== 'https:') {
    return Promise.reject(new Error(`refusing to open a ${scheme} URL in the browser; only http and https`));
  }

  const opener = browserOpenCommand(url);
  if (!opener) return Promise.reject(new Error(`no known way to open a browser on ${PLATFORM}`));

  return new Promise<void>((resolve, reject) => {
    execFile(opener.command, opener.args, { timeout: 20_000 }, (err) => {
      if (!err) return resolve();
      const why = (err as NodeJS.ErrnoException).code === 'ENOENT' ? `${opener.command} is not on this machine` : err.message;
      reject(new Error(`could not open your browser with ${opener.command} (${why})`));
    });
  });
}

/* ------------------------------------------------------------------ the exclusive lock */

export interface ExclusiveOpenFlags {
  /** The `open(2)` flag word that takes the lock atomically at open time. */
  flags: number;
  /** errno codes meaning another holder has it; the caller retries until its deadline. */
  contended: readonly string[];
  /**
   * errno codes meaning this filesystem implements no advisory locking at all, where the caller
   * proceeds unlocked because there was never any exclusion there to lose. **Empty on Windows**,
   * and that is the whole of the fix — see below.
   */
  unsupported: readonly string[];
  /** What the lock is, in one phrase, for a log line or an error. */
  mechanism: string;
}

/**
 * The flags that take a cross-process exclusive lock on the sidecar, per platform.
 *
 * **macOS** — `O_EXLOCK | O_NONBLOCK` is how node reaches `flock(fd, LOCK_EX | LOCK_NB)`; node
 * exposes no `flock` binding, and `fs.constants.O_EXLOCK` is undefined in these builds, so the
 * numeric value from `fcntl.h` is used. Unchanged from what `lock.ts` has always done.
 *
 * **Windows** — measured 2026-08-30 on node v24.19.0, and it was neither working nor failing before:
 *
 *   · the macOS flag word `O_RDWR|0x200|0x20|0x4|0x1000000` returns **EINVAL** on Windows, and
 *     `EINVAL` was in the *unsupported* set — so every `withExclusiveLock` call took the
 *     "this filesystem has no advisory locking, proceed unlocked" path. Two processes were observed
 *     inside the same critical section at once, and **no `.lock` sidecar was ever created**. The
 *     silent branch was designed for a network mount and Windows walked straight into it.
 *   · `fs.constants.O_CREAT` is `0x100` on Windows and `0x200` on macOS, so even the create flag
 *     was wrong. It is read from `fs.constants` here rather than written down.
 *   · libuv's `UV_FS_O_EXLOCK` (`0x10000000`) does work, and works properly: a second open in the
 *     same process was refused **EBUSY**; a second *process* was refused EBUSY for as long as the
 *     holder lived and acquired 2 s later within 200 ms of the holder closing; and a holder killed
 *     with SIGKILL released it, so a crash cannot strand the lock.
 *   · there is no `O_NONBLOCK` on Windows and none is needed — the refusal is immediate.
 *
 * `unsupported` is empty on Windows on purpose. The exclusion there is enforced by the share mode
 * the kernel applies to the handle, not by a filesystem feature that some volume might lack, so
 * there is no errno that legitimately means "carry on without a lock". Any unexpected code becomes
 * a visible `couldNotOpen` instead of an invisible unlocked write.
 */
export function exclusiveOpenFlags(): ExclusiveOpenFlags {
  const O_RDWR = fsConstants.O_RDWR;
  const O_CREAT = fsConstants.O_CREAT;

  if (IS_WINDOWS) {
    const UV_FS_O_EXLOCK = 0x10000000;
    return {
      flags: O_RDWR | O_CREAT | UV_FS_O_EXLOCK,
      contended: ['EBUSY', 'EAGAIN', 'EINTR'],
      unsupported: [],
      mechanism: 'an exclusive share mode on the lock sidecar (UV_FS_O_EXLOCK)',
    };
  }

  /* macOS `fcntl.h`, read numerically because node exports none of the three.
     `O_CLOEXEC` is belt and braces rather than load-bearing: measured 2026-08-22, node already
     opens with close-on-exec set. It is passed anyway because the pool spawns children constantly
     and an inherited lock descriptor would hold the lock for that child's whole life. */
  const O_EXLOCK = 0x20;
  const O_NONBLOCK = 0x4;
  const O_CLOEXEC = 0x1000000;
  return {
    flags: O_RDWR | O_CREAT | O_EXLOCK | O_NONBLOCK | O_CLOEXEC,
    contended: ['EAGAIN', 'EWOULDBLOCK', 'EINTR'],
    unsupported: ['ENOTSUP', 'EOPNOTSUPP', 'EINVAL'],
    mechanism: 'flock(LOCK_EX | LOCK_NB) via O_EXLOCK',
  };
}

/* ------------------------------------------------------------------ process start times */

export interface StartTimeProbe {
  /** Epoch seconds per pid, for every pid the OS answered for. */
  starts: Map<number, number>;
  /**
   * Whether the probe itself ran. `false` means the tool is not on this machine, so an absent pid
   * means *unknown*, not *dead* — the distinction between "nobody is running" and "nobody was
   * asked", which is the difference between an honest sweep and a confident empty one.
   */
  probed: boolean;
  /** Present when `probed` is false: what was missing. */
  detail?: string;
}

/**
 * The PowerShell expression that turns a `DateTime` into epoch seconds, **flooring**.
 *
 * WIN17 gap-fix, and the reason it is exported rather than written inline is that it must agree
 * exactly with `parseProcStart`, and the only way a harness can prove that is by running the
 * shipped expression rather than a copy of it.
 *
 * The defect it closes: this probe used to cast, `[int64](...TotalSeconds)`, and a .NET cast to
 * an integral type **rounds to nearest** — `[int64]1.6` is `2`, and `[int64]1.5` is `2` as well.
 * `parseProcStart` reads the registry's FILETIME with `BigInt(text) / 10_000_000n`, which
 * truncates. So for any process whose start instant has a fractional second at or above .5, the
 * probe said one second later than the parser did, deterministically. Measured 2026-08-30 across
 * all ten rows of this machine's live session registry, **five of the ten disagreed by exactly one
 * second** — and `sessions.ts` classifies a row `recycled` when the two differ by more than one.
 * Half of all Windows sessions therefore sat exactly on that boundary by construction rather than
 * by clock drift, so any real drift tipped a live session into `recycled` and its message landed
 * nowhere. The earlier note in this file read that symptom — "agreed to within one second" — as
 * headroom, when it was the asymmetry showing.
 *
 * Both sides floor now, and a live process's two spellings agree to zero rather than to one.
 */
export const windowsEpochSeconds = (dateTimeExpr: string): string =>
  `[int64][System.Math]::Floor(((${dateTimeExpr}).ToUniversalTime() - [datetime]'1970-01-01').TotalSeconds)`;

/**
 * Start times for the pids given, as epoch seconds, from one OS call.
 *
 * **macOS** — `ps -o pid=,lstart=`, with `LC_ALL=C` load-bearing: without it `ps` prints
 * `Sat 22 Aug 20:02:12 2026` on this machine and the parse silently yields the wrong instant.
 *
 * **Windows** — `Get-Process`, and the epoch arithmetic is done *inside PowerShell* so the
 * localised `DateTime` spelling never crosses the boundary. That is the same lesson as `LC_ALL=C`,
 * applied one step earlier: `Get-CimInstance` returns `"Sunday, August 30, 2026 7:58:58 AM"`, whose
 * spelling depends on the machine's culture, and parsing it in node would be the `LC_ALL` bug
 * wearing a different hat. `Get-Process` is also the fast lane — 342 ms batched against
 * `Get-CimInstance Win32_Process`'s 3 138 ms and `tasklist`'s 3 782 ms, all measured 2026-08-30.
 * `wmic` is absent on this Windows 11 build (ENOENT) and is not a fallback.
 *
 * **This one probe is still synchronous, and that is a decision rather than an oversight.** Its
 * callers — `sessions.ts`'s `processStarts` and `sweepSessions` — are synchronous all the way up
 * to the `mcpr sessions` CLI, and none of them runs inside the router's request path, so the
 * event-loop cost `residentKb` and `peerOfLocalPort` had to shed does not apply here. Making it
 * async would turn a read-only sweep into an async signature change across `sessions.ts` and the
 * control API's `/sessions` handler for no measured gain.
 *
 * **What that costs is not symmetric between the platforms, and is stated here rather than left to
 * be discovered.** When a batch answers for nobody the sweep falls back to one call per pid — the
 * regression arm that keeps one junk registry row from answering for the others. On macOS a `ps`
 * invocation is a couple of milliseconds, so the fallback is free. On Windows one PowerShell start
 * is 372 ms measured, so the same fallback is 372 ms × the number of rows: about 3.7 s at this
 * machine's registry size of ten, and it blocks while it runs. It is bounded by the registry, it
 * fires only in the degenerate case, and it is a CLI path — but it is 200× the macOS cost for the
 * identical code, and a registry an order of magnitude larger would be felt.
 */
export function processStartSeconds(pids: number[]): StartTimeProbe {
  const starts = new Map<number, number>();
  const wanted = pids.filter((n) => Number.isSafeInteger(n) && n > 0);
  if (wanted.length === 0) return { starts, probed: true };

  const absorb = (raw: string, pattern: RegExp, read: (m: RegExpExecArray) => number | undefined): number => {
    let found = 0;
    for (const line of raw.split('\n')) {
      const m = pattern.exec(line);
      if (!m) continue;
      const at = read(m);
      if (at === undefined || Number.isNaN(at)) continue;
      starts.set(Number(m[1]), at);
      found += 1;
    }
    return found;
  };

  if (IS_WINDOWS) {
    const ask = (batch: number[]): { out: string; ran: boolean } =>
      powershell(
        `$ErrorActionPreference='SilentlyContinue'; Get-Process -Id ${batch.join(',')} | ForEach-Object { "$($_.Id) $(${windowsEpochSeconds('$_.StartTime')})" }`
      );

    const first = ask(wanted);
    if (!first.ran) return { starts, probed: false, detail: 'powershell.exe is not on this machine' };
    absorb(first.out, /^\s*(\d+)\s+(\d+)\s*$/, (m) => Number(m[2]));
    // Same guard as the macOS side and for the same reason: one junk registry row must not answer
    // for the others. Only when the batch answered for nobody, so the cost is paid once.
    if (starts.size === 0 && wanted.length > 1) {
      for (const pid of wanted) absorb(ask([pid]).out, /^\s*(\d+)\s+(\d+)\s*$/, (m) => Number(m[2]));
    }
    return { starts, probed: true };
  }

  const ask = (batch: number[]): { out: string; ran: boolean } => {
    try {
      return {
        out: execFileSync('ps', ['-o', 'pid=,lstart=', '-p', batch.join(',')], {
          encoding: 'utf8',
          env: { LC_ALL: 'C', PATH: '/bin:/usr/bin' },
        }),
        ran: true,
      };
    } catch (err) {
      const e = err as { stdout?: unknown; code?: string };
      return { out: String(e.stdout ?? ''), ran: e.code !== 'ENOENT' };
    }
  };

  const first = ask(wanted);
  if (!first.ran) return { starts, probed: false, detail: '`ps` is not on this machine' };
  // `ps` prints local time and `Date.parse` of a bare ctime string reads it as local. Correct here,
  // and the exact opposite of how a registry `procStart` must be read — see `parseProcStart`.
  absorb(first.out, /^\s*(\d+)\s+(.+?)\s*$/, (m) => Math.floor(Date.parse(m[2]!) / 1000));
  if (starts.size === 0 && wanted.length > 1) {
    for (const pid of wanted) absorb(ask([pid]).out, /^\s*(\d+)\s+(.+?)\s*$/, (m) => Math.floor(Date.parse(m[2]!) / 1000));
  }
  return { starts, probed: true };
}

/** 100-nanosecond intervals between 1601-01-01 and 1970-01-01, which is what a FILETIME counts from. */
const FILETIME_EPOCH_OFFSET_SECONDS = 11_644_473_600n;

/**
 * A session registry's `procStart`, in whichever of the two spellings wrote it, as epoch seconds.
 *
 * **This branches on the spelling, not on the platform**, because the field is written by whichever
 * Claude Code produced the registry and read by whichever router reads it. Measured 2026-08-30
 * against five live sessions in this machine's own `~/.claude/sessions`:
 *
 *   · macOS writes ctime in **UTC** — `Sat Aug 22 10:02:12 2026`.
 *   · Windows writes a **FILETIME decimal string** — `"134324966130572677"`, 100 ns since
 *     1601-01-01 UTC.
 *
 * **Both spellings floor, and that is load-bearing rather than incidental.** `BigInt / 10_000_000n`
 * truncates; `windowsEpochSeconds` floors for the same reason, having previously cast — which
 * rounds to nearest and put half this machine's registry exactly one second away from the probe.
 * The caller compares the two instants with a tolerance of one second, so a systematic one-second
 * offset consumed the entire tolerance and left nothing for real clock drift: see
 * `windowsEpochSeconds` for the ten-row measurement. A live process's registry `procStart` and its
 * `Get-Process` start time now agree exactly, and the tolerance is spent on drift alone.
 *
 * Before any of this, `Date.parse("134324966130572677 UTC")` returned `NaN`, so the caller's
 * `registered !== undefined` guard skipped the identity check entirely and **the recycled-pid
 * check silently did not run on Windows** — a message aimed at a reused pid would have landed in
 * whatever now owns that number.
 */
export function parseProcStart(raw: string): number | undefined {
  const text = raw.trim();
  if (/^\d+$/.test(text)) {
    try {
      return Number(BigInt(text) / 10_000_000n - FILETIME_EPOCH_OFFSET_SECONDS);
    } catch {
      return undefined;
    }
  }
  const ms = Date.parse(`${text} UTC`);
  return Number.isNaN(ms) ? undefined : Math.floor(ms / 1000);
}

/* ------------------------------------------------------------------ session socket presence */

export type SocketPresence = 'present' | 'absent' | 'indeterminate';

/**
 * Whether a session's messaging endpoint is there.
 *
 * A Windows named pipe cannot be stat'd: measured 2026-08-30, `existsSync('\\\\.\\pipe\\InitShutdown')`
 * returns `false` for a pipe that is certainly live, and this machine's session registry holds
 * `messagingSocketPath` values of exactly that shape (`\\.\pipe\cc-msg-<32 hex>`). Left alone, the
 * caller's `!existsSync(socketPath)` would have classified **every** Windows session `noSocket`.
 *
 * So a pipe path is `indeterminate` and the connect settles it. The cost of that is real and is
 * stated rather than hidden: on Windows a stale endpoint is discovered as a `refused` push outcome
 * instead of being filtered out one step earlier as `noSocket`.
 */
export function socketPresence(path: string): SocketPresence {
  if (IS_WINDOWS && /^\\\\[.?]\\pipe\\/i.test(path)) return 'indeterminate';
  return existsSync(path) ? 'present' : 'absent';
}

/* ------------------------------------------------------------------ resident memory */

/**
 * Resident size per pid, in kilobytes, for the pids the OS answered for.
 *
 * macOS reports RSS from `ps -o rss=`. Windows reports the **working set** from
 * `Get-Process`'s `WorkingSet64` — the nearest counterpart rather than the same number, and named
 * as such wherever it is displayed. `tasklist` would have given the same figure but takes 3.8 s
 * against `Get-Process`'s 392 ms, and prints it as a culture-formatted `"62,192 K"` whose thousands
 * separator depends on the machine; the byte count avoids both.
 *
 * The Windows call is `execFile`, not `execFileSync`: this function is `async`, it is awaited from
 * `pool.ts`'s status sweep, and the synchronous version cost 423 ms of event-loop lag every time —
 * see `stdoutOfAsync`.
 */
export async function residentKb(pids: number[]): Promise<Map<number, number>> {
  const out = new Map<number, number>();
  const wanted = pids.filter((n) => Number.isSafeInteger(n) && n > 0);
  if (wanted.length === 0) return out;

  if (IS_WINDOWS) {
    const { out: raw } = await powershellAsync(
      `$ErrorActionPreference='SilentlyContinue'; Get-Process -Id ${wanted.join(',')} | ForEach-Object { "$($_.Id) $($_.WorkingSet64)" }`,
      5_000
    );
    for (const line of raw.split('\n')) {
      const m = /^\s*(\d+)\s+(\d+)\s*$/.exec(line);
      if (m) out.set(Number(m[1]), Math.round(Number(m[2]) / 1024));
    }
    return out;
  }

  const raw = await new Promise<string>((resolve) => {
    execFile('/bin/ps', ['-o', 'pid=,rss=', '-p', wanted.join(',')], { timeout: 2000 }, (err, stdout) =>
      resolve(err ? '' : stdout)
    );
  });
  for (const line of raw.trim().split('\n')) {
    const [pid, rss] = line.trim().split(/\s+/).map(Number);
    if (pid && rss) out.set(pid, rss);
  }
  return out;
}

/* ------------------------------------------------------------------ who is on the other end */

export interface PeerProcess {
  pid?: number;
  /** The executable's name, where the platform will say. */
  client?: string;
  /** The peer's working directory. **Never populated on Windows** — see `peerOfLocalPort`. */
  cwd?: string;
}

/**
 * The process holding the far end of a loopback TCP connection, given the port it is using.
 *
 * **macOS** — `lsof -nP -iTCP:<port>` names the process and a second call reads its cwd, which is
 * what turns "something called browser_navigate" into "the session working in ~/Dev/mcp-router
 * called it".
 *
 * **Windows** — `netstat -ano` carries the owning pid on every row, and the row wanted is the one
 * whose *local* address is that port, since a loopback connection appears twice and the other row
 * is this router. The image name comes from `Get-Process`. **There is no cwd**: a foreign process's
 * current directory lives in its PEB and is not readable without opening the process, so a Windows
 * usage record carries a pid and an image name and reports no project. A smaller record, made
 * deliberately, rather than a guessed one.
 *
 * **Both Windows calls are `execFile`, and on this function that is the whole point.** It runs once
 * per accepted connection from `router.ts`'s `http.on('connection')` and is awaited again on the
 * request path, so a synchronous shell-out here is not one caller waiting — it is the entire router
 * stopped, serving nobody, for as long as the child takes. Measured 2026-08-30 from node: the
 * synchronous pair cost 93 ms wall and 83 ms of event-loop lag, against a header that had quoted
 * netstat at 23 ms. That 23 ms was the command's own time measured in a shell; from node, with the
 * spawn, the pipe and the wait, it is 83–93 ms, and it was the figure the sync choice was made on.
 */
export async function peerOfLocalPort(port: number, selfPid: number): Promise<PeerProcess> {
  if (!Number.isSafeInteger(port) || port <= 0) return {};

  if (IS_WINDOWS) {
    // `netstat` directly rather than through PowerShell: 23 ms against ~350 ms for the command
    // itself, and both are paid off the event loop.
    const { out: raw, ran } = await stdoutOfAsync('netstat', ['-ano', '-p', 'TCP'], 5_000);
    if (!ran) return {};
    let pid: number | undefined;
    for (const line of raw.split('\n')) {
      // `TCP    127.0.0.1:54321    127.0.0.1:8879    ESTABLISHED    1234`
      const m = /^\s*TCP\s+\S+:(\d+)\s+\S+\s+ESTABLISHED\s+(\d+)\s*$/i.exec(line);
      if (!m || Number(m[1]) !== port) continue;
      const candidate = Number(m[2]);
      if (candidate === selfPid) continue;
      pid = candidate;
      break;
    }
    if (!pid) return {};
    const { out: name } = await powershellAsync(
      `$ErrorActionPreference='SilentlyContinue'; Get-Process -Id ${pid} | ForEach-Object { $_.ProcessName }`,
      5_000
    );
    return { pid, client: name.trim() || undefined, cwd: undefined };
  }

  const run = (args: string[]): Promise<string> =>
    new Promise((resolve) => {
      execFile('/usr/sbin/lsof', args, { timeout: 2000, maxBuffer: 1024 * 1024 }, (err, stdout) =>
        resolve(err ? '' : stdout)
      );
    });

  // `-i :port` matches either end of the connection, so this returns both the client and this
  // router. The one that is not us is the caller.
  const out = await run(['-nP', `-iTCP:${port}`, '-sTCP:ESTABLISHED', '-Fpc']);
  if (!out) return {};

  let pid: number | undefined;
  let client: string | undefined;
  let currentPid: number | undefined;
  for (const line of out.split('\n')) {
    if (line.startsWith('p')) {
      currentPid = Number(line.slice(1));
    } else if (line.startsWith('c') && currentPid && currentPid !== selfPid) {
      pid = currentPid;
      client = line.slice(1);
      break;
    }
  }
  if (!pid) return {};

  const cwdOut = await run(['-a', '-p', String(pid), '-d', 'cwd', '-Fn']);
  const cwd = cwdOut
    .split('\n')
    .find((l) => l.startsWith('n'))
    ?.slice(1);
  return { pid, client, cwd: cwd || undefined };
}

/* ------------------------------------------------------------------ supervision */

export interface Supervisor {
  /** What is watching this daemon. `none` is a real answer and is reported as one. */
  kind: 'launchd' | 'none';
  /** One sentence about what the host does when this process exits. Printed at `serve` startup. */
  guarantee: string;
  /** Ask the supervisor to restart the job. Never throws. */
  restart(label: string): { restarted: boolean; detail: string };
}

/**
 * What supervises the router on this platform.
 *
 * On macOS, launchd's `KeepAlive` restarts the job whenever it exits, and the router is built on
 * top of that in three places: the deliberate non-zero exit when a shutdown stalls
 * (`index.ts`), the restart after `watch` adopts an upstream the running process cannot spawn
 * (`watch.ts`), and the reasoning about a hung `close()` (`router.ts`). None of that holds
 * anywhere else.
 *
 * This returns `none` off macOS rather than substituting something. There is a Windows answer — a
 * service, a scheduled task at logon, or the client owning the process — but which one is a
 * product decision about whether the router outlives the app, and WIN23 owns it. Choosing one here
 * would be answering that question by accident.
 */
export function supervisor(): Supervisor {
  if (IS_DARWIN) {
    return {
      kind: 'launchd',
      guarantee: 'launchd KeepAlive restarts this job if it exits.',
      restart(label: string) {
        try {
          execFileSync('/bin/launchctl', ['kickstart', '-k', `gui/${process.getuid?.() ?? 501}/${label}`], {
            stdio: 'ignore',
            timeout: 15_000,
          });
          return { restarted: true, detail: `restarted ${label}` };
        } catch (err) {
          return { restarted: false, detail: `could not restart ${label} (${(err as Error).message})` };
        }
      },
    };
  }

  return {
    kind: 'none',
    guarantee:
      `no supervisor on ${PLATFORM}: nothing restarts this process when it exits, so an exit is a stop. ` +
      'WIN23 decides what supervises the router here.',
    restart(label: string) {
      return {
        restarted: false,
        detail: `no supervisor on ${PLATFORM}, so ${label} was not restarted; start the router again yourself`,
      };
    },
  };
}

/* ------------------------------------------------------------------ the config watcher */

export interface ConfigWatcher {
  /** What fires `mcpr watch` when `~/.claude.json` changes. `none` is a real answer. */
  kind: 'launchd' | 'none';
  /** One sentence for a person: whether a newly-added server is adopted on its own here. */
  guarantee: string;
  /** The parenthetical the `watch` line of the usage text carries on this platform. */
  usageNote: string;
}

/**
 * Whether anything on this host runs `mcpr watch` when `~/.claude.json` changes.
 *
 * WIN17 gap-fix. `supervisor()` above closed the *restart* half of the launchd finding and left
 * this half open, which is the more visible of the two: on macOS a `WatchPaths` job fires `mcpr
 * watch` on every write to `~/.claude.json`, so a server added by `claude mcp add` is adopted into
 * the router within a second and the user never types anything. **Nothing fires it on Windows.**
 * A server added there stays in `~/.claude.json`, is started per-session by Claude Code rather than
 * shared through the router, and no message anywhere says so — `watch.ts`'s own header asserted
 * "launchd fires this on the file change" unconditionally, and the usage text printed "(run by
 * launchd on file change)" to a Windows user reading it on a machine with no launchd.
 *
 * This states the absence rather than papering over it. A Windows watcher is buildable — a
 * `FileSystemWatcher` in a long-lived process, or a scheduled task — but both need something to
 * keep them alive, which is the supervision question `supervisor()` deliberately leaves to WIN23.
 * Inventing one here would answer that by accident, and would answer it worse: a watcher with no
 * supervisor is a watcher that stops silently, which is the same failure wearing a fix.
 *
 * So on Windows the honest product behaviour is `mcpr watch` run by hand or by the client, and the
 * text this returns is what says so, in the usage output, at `serve` startup, and in `watch`'s own
 * log.
 */
export function configWatcher(): ConfigWatcher {
  if (IS_DARWIN) {
    return {
      kind: 'launchd',
      guarantee: 'launchd watches ~/.claude.json and runs `mcpr watch` when it changes.',
      usageNote: 'run by launchd on file change',
    };
  }
  return {
    kind: 'none',
    guarantee:
      `nothing watches ~/.claude.json on ${PLATFORM}: a server added there is NOT adopted on its own, ` +
      'so run `mcpr watch` yourself after `claude mcp add`. WIN23 decides what runs it here.',
    usageNote: `nothing runs this for you on ${PLATFORM} — run it yourself after \`claude mcp add\``,
  };
}
