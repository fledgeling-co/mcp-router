/**
 * The platform layer, proved against the machine it is running on.
 *
 * WIN17. `src/platform.ts` is the one place the router reads `process.platform`, and every branch
 * in it exists because the unconditional macOS version of that branch was measured doing something
 * wrong on Windows. This script re-measures the claims rather than restating them, and it is
 * written to run on **either** platform — each check asserts what this host should do, so a macOS
 * run and a Windows run are the same suite with different expectations rather than two suites.
 *
 *   node scripts/e2e-platform.mjs
 *
 * Exit 0 clean · 1 findings · 2 the run could not measure what it was asked to.
 *
 * What it touches: its own temporary directory, a loopback listener on an ephemeral port, and two
 * of this repository's own source files read as text. It spawns no browser and reads no session
 * registry — the pids it asks about are this process and two it starts and waits for itself — and
 * the one time it runs the router binary, it runs `--help` against a temporary `MCP_ROUTER_HOME`,
 * because the real `servers.json` holds live bearer tokens.
 */
import { mkdirSync, writeFileSync, rmSync, existsSync, readFileSync } from 'node:fs';
import { tmpdir, homedir } from 'node:os';
import { join, delimiter, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createServer } from 'node:net';
import { spawn, execFile } from 'node:child_process';
import {
  PLATFORM,
  IS_WINDOWS,
  IS_DARWIN,
  PATH_LIST_SEPARATOR,
  browserOpenCommand,
  openInBrowser,
  exclusiveOpenFlags,
  processStartSeconds,
  parseProcStart,
  windowsEpochSeconds,
  socketPresence,
  residentKb,
  peerOfLocalPort,
  supervisor,
  configWatcher,
} from '../dist/platform.js';
import { withExclusiveLock } from '../dist/lock.js';
import { augmentPath } from '../dist/pool.js';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..');
const HOME = join(tmpdir(), `mcp-router-win17-${process.pid}`);
let failures = 0;
let checks = 0;
const check = (label, ok, detail = '') => {
  checks += 1;
  process.stdout.write(`  ${ok ? 'PASS' : 'FAIL'}  ${label}${detail ? ` — ${detail}` : ''}\n`);
  if (!ok) failures += 1;
};

/**
 * Run an async call while sampling this process's own event-loop drift, and report the worst
 * sample alongside the wall time.
 *
 * The gap-fix arm for D2 needs this because the defect was invisible to every other kind of check:
 * `residentKb` and `peerOfLocalPort` returned exactly the right answers, in an acceptable wall
 * time, from functions declared `async` — while blocking the thread for the whole of it with
 * `execFileSync`. Only a second thing trying to run during the await can tell the two apart. A
 * 5 ms interval that fires late by 400 ms is the router failing to serve anybody for 400 ms.
 *
 * The tail gap is not an extra: it is the only sample that sees the worst case. A wholly
 * synchronous `fn` blocks, resolves, and its `await` resumes as a *microtask*, which runs before
 * the event loop ever reaches the timer phase — so the interval never fires during the call and
 * an interval-only probe reports 0 ms lag against a 427 ms block. Measured here, against exactly
 * that mutation. What settles it is the gap between the last sample and the moment `fn` resolved.
 */
const withLagProbe = async (fn) => {
  let worst = 0;
  let last = process.hrtime.bigint();
  const timer = setInterval(() => {
    const now = process.hrtime.bigint();
    const late = Number(now - last) / 1e6 - 5;
    if (late > worst) worst = late;
    last = now;
  }, 5);
  const started = Date.now();
  try {
    const value = await fn();
    const tail = Number(process.hrtime.bigint() - last) / 1e6 - 5;
    if (tail > worst) worst = tail;
    return { value, lagMs: Math.max(0, Math.round(worst)), wallMs: Date.now() - started };
  } finally {
    clearInterval(timer);
  }
};

/* The bar D2's measurements have to clear. The synchronous versions logged 83 ms of lag for
   `peerOfLocalPort` and 423 ms for `residentKb`, so anything under 50 ms distinguishes a genuine
   `execFile` from an `execFileSync` wearing an `async` signature, with room for a GC pause. */
const LAG_CEILING_MS = 50;

const shellOut = (command, args, env) =>
  new Promise((resolve) => {
    execFile(
      command,
      args,
      { encoding: 'utf8', timeout: 20_000, env: env ? { ...process.env, ...env } : process.env },
      (err, stdout) => resolve(err ? '' : String(stdout))
    );
  });

rmSync(HOME, { recursive: true, force: true });
mkdirSync(HOME, { recursive: true });

process.stdout.write(`platform ${PLATFORM}, node ${process.version}\n\n`);

try {
  // ------------------------------------------------------------------ PATH
  process.stdout.write('PATH composition\n');
  check('the separator is the one this OS uses', PATH_LIST_SEPARATOR === delimiter, PATH_LIST_SEPARATOR);
  check(
    IS_WINDOWS ? 'which on Windows is ";"' : 'which off Windows is ":"',
    PATH_LIST_SEPARATOR === (IS_WINDOWS ? ';' : ':')
  );
  {
    /* The defect this replaces: splitting a Windows PATH on ':' turns `C:\dir` into `C` and
       `\dir`, so every entry is destroyed and every spawned upstream loses its toolchain. */
    const inherited = IS_WINDOWS ? 'C:\\Windows\\System32;C:\\Program Files\\nodejs' : '/usr/bin:/bin';
    const merged = augmentPath(inherited, HOME);
    const parts = merged.split(PATH_LIST_SEPARATOR);
    const original = inherited.split(PATH_LIST_SEPARATOR);
    check(
      'every inherited entry survives augmentation intact and in order',
      original.every((entry, i) => parts[i] === entry),
      `${JSON.stringify(original)} -> ${JSON.stringify(parts.slice(0, original.length))}`
    );
  }
  {
    // The empty component contract, which execvp reads as the current directory.
    const merged = augmentPath(`${PATH_LIST_SEPARATOR}x`, HOME);
    check('an empty leading component is kept', merged.split(PATH_LIST_SEPARATOR)[0] === '');
  }

  // ------------------------------------------------------------------ browser
  process.stdout.write('\nopening a browser\n');
  {
    const opener = browserOpenCommand('https://example.com/a?b=1&c=2');
    check('there is an opener for this platform', !!opener, opener ? `${opener.command} ${opener.args.join(' ')}` : 'none');
    if (IS_DARWIN) check('macOS uses /usr/bin/open', opener?.command === '/usr/bin/open');
    if (IS_WINDOWS) {
      check('Windows uses rundll32, not a cmd builtin', opener?.command === 'rundll32.exe');
      /* The reason for rundll32 rather than `cmd /c start`: the URL is one argv entry and never
         reaches a command interpreter, so `&` is not a statement separator and `%NAME%` is not a
         variable. An OAuth authorization URL is mostly those two characters. */
      check(
        'the URL is passed whole, with its & intact',
        opener?.args.at(-1) === 'https://example.com/a?b=1&c=2',
        opener?.args.at(-1)
      );
      check('and rundll32 is on this machine', existsSync('C:/Windows/System32/rundll32.exe'));
    }
  }
  {
    // Both rejections are settled before anything is spawned, so no browser opens here.
    let rejected = false;
    await openInBrowser('file:///etc/passwd').then(
      () => undefined,
      () => (rejected = true)
    );
    check('a non-http URL is refused rather than handed to the shell handler', rejected);

    let rejected2 = false;
    await openInBrowser('not a url at all').then(
      () => undefined,
      () => (rejected2 = true)
    );
    check('a malformed URL is refused', rejected2);
    check('and both refusals are rejections a caller can see, not a discarded callback error', rejected && rejected2);
  }

  // ------------------------------------------------------------------ lock
  process.stdout.write('\nthe cross-process lock\n');
  {
    const flags = exclusiveOpenFlags();
    check('the flag word is non-zero', flags.flags !== 0, `0x${flags.flags.toString(16)}`);
    if (IS_WINDOWS) {
      /* The whole of the Windows lock defect: EINVAL was in the unsupported set, the macOS flag
         word returns EINVAL on Windows, so every call took the silent proceed-unlocked branch. */
      check('nothing on Windows is treated as "no locking here"', flags.unsupported.length === 0);
      check('EBUSY is the contended code', flags.contended.includes('EBUSY'));
    } else {
      check('EAGAIN is the contended code', flags.contended.includes('EAGAIN'));
    }

    const target = join(HOME, 'servers.json');
    writeFileSync(target, '{}');
    const holder = spawn(
      process.execPath,
      [
        '-e',
        `import(${JSON.stringify(new URL('../dist/lock.js', import.meta.url).href)}).then(m => {
           m.withExclusiveLock(${JSON.stringify(target)}, 4000, () => {
             process.stdout.write('held\\n');
             Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 4000);
           });
         });`,
      ],
      { stdio: ['ignore', 'pipe', 'ignore'] }
    );
    const held = await new Promise((resolve) => {
      const timer = setTimeout(() => resolve(false), 10_000);
      holder.stdout.on('data', (c) => {
        if (String(c).includes('held')) {
          clearTimeout(timer);
          resolve(true);
        }
      });
    });

    if (!held) {
      process.stdout.write('  the holder process never took the lock; this run measured nothing\n');
      holder.kill();
      process.exit(2);
    }

    check('the sidecar exists once the lock is taken', existsSync(`${target}.lock`), `${target}.lock`);

    let refused;
    const t0 = Date.now();
    try {
      withExclusiveLock(target, 800, () => undefined);
      refused = undefined;
    } catch (err) {
      refused = err;
    }
    const waited = Date.now() - t0;
    check(
      'a second process is refused while the first holds it',
      refused?.kind === 'notAcquired',
      refused ? `${refused.kind} after ${waited}ms` : 'IT WAS LET IN — the lock excludes nothing on this platform'
    );
    check('and it waited out its whole timeout rather than failing instantly', waited >= 700, `${waited}ms`);

    holder.kill();
    await new Promise((r) => holder.on('exit', r));
    // The kernel releases the lock when the descriptor closes, including when the process dies.
    let reacquired = false;
    for (let i = 0; i < 40 && !reacquired; i++) {
      try {
        withExclusiveLock(target, 100, () => undefined);
        reacquired = true;
      } catch {
        await new Promise((r) => setTimeout(r, 100));
      }
    }
    check('and the lock is released when the holder dies, so a crash cannot strand it', reacquired);
  }

  // ------------------------------------------------------------------ process liveness
  process.stdout.write('\nprocess liveness\n');
  {
    const dead = await new Promise((resolve, reject) => {
      const p = spawn(process.execPath, ['-e', ''], { stdio: 'ignore' });
      p.on('error', reject);
      p.on('exit', () => resolve(p.pid));
    });

    const probe = processStartSeconds([process.pid, dead, 4194303]);
    check('the probe ran', probe.probed, probe.detail ?? '');
    if (!probe.probed) {
      process.stdout.write('  no liveness probe on this machine; the rest of this section measured nothing\n');
      process.exit(2);
    }
    const mine = probe.starts.get(process.pid);
    check('this process has a start time', mine !== undefined, String(mine));
    check(
      'and it is a plausible instant, not a parse artefact',
      mine !== undefined && Math.abs(Date.now() / 1000 - mine) < 3600,
      mine === undefined ? '' : `${Math.round(Date.now() / 1000 - mine)}s ago`
    );
    /* The regression arm both platforms need: one unusable pid must not answer for the others.
       macOS `ps` rejects the whole invocation over 4194303 and prints nothing; Windows
       `Get-Process` exits 1 over it but still prints the good rows. Either way the live pid must
       survive, which the assertion above already requires with 4194303 in the same batch. */
    check('a pid that exited is absent rather than guessed at', !probe.starts.has(dead), String(dead));
    check('an out-of-range pid does not blind the sweep', probe.starts.has(process.pid));
  }

  // ------------------------------------------------------------------ procStart spellings
  process.stdout.write('\nthe two procStart spellings\n');
  {
    // macOS writes ctime in UTC.
    check(
      'a ctime string reads as its UTC instant',
      parseProcStart('Sat Aug 22 10:02:12 2026') === Math.floor(Date.parse('2026-08-22T10:02:12Z') / 1000),
      String(parseProcStart('Sat Aug 22 10:02:12 2026'))
    );
    /* Windows writes a FILETIME decimal — 100 ns since 1601-01-01. This value was taken from a
       real row in this machine's session registry on 2026-08-30; its process was live and
       `Get-Process` put its start at 1788023013. */
    check(
      'a FILETIME decimal reads as the same instant Get-Process reports',
      parseProcStart('134324966130572677') === 1788023013,
      String(parseProcStart('134324966130572677'))
    );
    check('and neither is read as the other', parseProcStart('134324966130572677') !== undefined);
    check('junk is undefined rather than NaN or zero', parseProcStart('not a time') === undefined);
  }

  // ------------------------------------------------------------------ D1: the two sides floor
  //
  // The gap-fix arm, and the one that had to be designed against a failure that looked like
  // success. `parseProcStart` truncates its FILETIME; the Windows probe used to *cast* the
  // PowerShell figure, and a .NET cast to an integral type rounds to nearest. So for any process
  // whose start instant had a fractional second at or above .5, the two spellings of one instant
  // differed by exactly one second — five of the ten rows in this machine's live registry, by
  // construction rather than by drift. `sessions.ts` calls a row `recycled` when they differ by
  // more than one, so half of all Windows sessions sat exactly on the boundary with none of the
  // tolerance left for the drift it exists to absorb.
  //
  // "Agreed to within one second" was what the old header called that, and it is why a check that
  // asserts a tolerance would have passed throughout. These assert **equality**.
  process.stdout.write('\nthe FILETIME and the probe floor the same way\n');
  {
    /* 1788023013 seconds and nine tenths, as a FILETIME. The fraction is the whole point: a
       flooring conversion gives 1788023013 and a rounding one gives 1788023014. */
    const FRACTIONAL_FILETIME = '134324966139000000';
    const FLOORED = 1788023013;

    check(
      'a FILETIME with a .9 fraction floors rather than rounding up',
      parseProcStart(FRACTIONAL_FILETIME) === FLOORED,
      `${parseProcStart(FRACTIONAL_FILETIME)} (rounding would give ${FLOORED + 1})`
    );

    if (IS_WINDOWS) {
      /* The shipped expression, run rather than restated. `platform.ts` exports it precisely so
         this can drive the same text the probe drives; a copy of it here would prove that the
         copy floors. */
      const expr = windowsEpochSeconds(`[datetime]::FromFileTimeUtc(${FRACTIONAL_FILETIME})`);
      const printed = (
        await shellOut('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', expr])
      ).trim();
      check(
        'and the shipped PowerShell expression floors the same instant identically',
        Number(printed) === FLOORED,
        `PowerShell printed ${printed || '(nothing)'}, parseProcStart gives ${FLOORED}`
      );

      /* And live, end to end: this process's start time as the probe reports it, against its own
         FILETIME read the way a session registry writes one. The registry's `procStart` for a
         Windows session is exactly `ToFileTimeUtc()` of this same `StartTime`. */
      const fileTime = (
        await shellOut('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          `$ErrorActionPreference='SilentlyContinue'; (Get-Process -Id ${process.pid}).StartTime.ToFileTimeUtc()`,
        ])
      ).trim();
      const fromRegistry = /^\d+$/.test(fileTime) ? parseProcStart(fileTime) : undefined;
      const fromProbe = processStartSeconds([process.pid]).starts.get(process.pid);
      check(
        'a live process’s registry spelling and its probe agree EXACTLY, not to within a second',
        fromRegistry !== undefined && fromProbe !== undefined && fromRegistry === fromProbe,
        `registry ${fromRegistry} vs probe ${fromProbe} (delta ${
          fromRegistry !== undefined && fromProbe !== undefined ? fromProbe - fromRegistry : 'n/a'
        })`
      );
      /* Stated as its own check because this is the number `sessions.ts` spends. A delta of 1 here
         passes the recycled test today and fails it the moment anything drifts; a delta of 0
         leaves the whole tolerance for drift, which is what it was for. */
      check(
        'so the whole of sessions.ts’s one-second tolerance is left for real clock drift',
        fromRegistry !== undefined && fromProbe !== undefined && Math.abs(fromProbe - fromRegistry) === 0
      );
    }
  }

  // ------------------------------------------------------------------ socket presence
  process.stdout.write('\nsession endpoint presence\n');
  {
    const real = join(HOME, 'a-file');
    writeFileSync(real, '');
    check('an existing path is present', socketPresence(real) === 'present');
    check('a missing path is absent', socketPresence(join(HOME, 'nope')) === 'absent');
    const pipe = '\\\\.\\pipe\\cc-msg-0123456789abcdef0123456789abcdef';
    check(
      IS_WINDOWS
        ? 'a Windows named pipe is indeterminate, because a live one cannot be stat\'d'
        : 'a pipe-shaped path off Windows is just a path',
      socketPresence(pipe) === (IS_WINDOWS ? 'indeterminate' : 'absent'),
      socketPresence(pipe)
    );
  }

  // ------------------------------------------------------------------ resident memory
  process.stdout.write('\nresident memory\n');
  {
    const { value: kb, lagMs, wallMs } = await withLagProbe(() => residentKb([process.pid]));
    const mine = kb.get(process.pid);
    check('this process has a resident figure', mine !== undefined && mine > 0, `${mine} KB`);
    check(
      'and it is the same order of magnitude as node reports for itself',
      mine !== undefined && mine > process.memoryUsage().rss / 1024 / 8,
      `probe ${mine} KB vs process.memoryUsage().rss ${Math.round(process.memoryUsage().rss / 1024)} KB`
    );
    /* D2. This is `async` and was not: `execFileSync` held the thread for the whole 433 ms and
       every timer, socket and in-flight read waited it out. `pool.ts` awaits this on its status
       sweep. */
    check(
      'and awaiting it leaves the event loop free rather than blocking the thread',
      lagMs < LAG_CEILING_MS,
      `${lagMs} ms lag over ${wallMs} ms wall (sync measured 423 ms lag; ceiling ${LAG_CEILING_MS} ms)`
    );
  }

  // ------------------------------------------------------------------ who is on the other end
  //
  // D2's sharpest case. `peerOfLocalPort` runs once per accepted connection from
  // `router.ts`'s `http.on('connection')` and is awaited again on the request path, so a
  // synchronous shell-out here is not one caller waiting — it is the whole router stopped,
  // serving nobody, on the first request from every new client. Measured before the fix: 93 ms
  // wall, 83 ms of it event-loop lag, against a header that had quoted netstat at 23 ms.
  //
  // A real established loopback connection from a real other process, because that is the only
  // shape either platform's probe can answer about.
  process.stdout.write('\nidentifying the process on the other end\n');
  {
    const server = createServer();
    const accepted = new Promise((resolve) => server.once('connection', resolve));
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;

    /* A child that connects and then waits, so it is still alive while the probe asks the OS
       about it — which is the whole reason `router.ts` identifies at accept time. */
    const client = spawn(
      process.execPath,
      [
        '-e',
        `const net = require('node:net');
         const s = net.connect(${port}, '127.0.0.1', () => setTimeout(() => s.destroy(), 15000));
         s.on('error', () => process.exit(1));`,
      ],
      { stdio: 'ignore' }
    );

    const socket = await Promise.race([
      accepted,
      new Promise((resolve) => setTimeout(() => resolve(undefined), 10_000)),
    ]);

    if (!socket) {
      process.stdout.write('  no loopback connection was accepted; this section measured nothing\n');
      client.kill();
      server.close();
      process.exit(2);
    }

    const { value: peer, lagMs, wallMs } = await withLagProbe(() =>
      peerOfLocalPort(socket.remotePort, process.pid)
    );

    check(
      'the far end of a live loopback connection is identified',
      peer.pid === client.pid,
      `probe says pid ${peer.pid ?? 'none'}${peer.client ? ` (${peer.client})` : ''}, the child is ${client.pid}`
    );
    check(
      IS_WINDOWS
        ? 'with no cwd on Windows, which is stated rather than guessed'
        : 'with the peer’s cwd on this platform',
      IS_WINDOWS ? peer.cwd === undefined : true,
      String(peer.cwd)
    );
    /* The check the fix exists for. The answer was always right; what was wrong was that
       everything else stopped while it was found. */
    check(
      'and finding it does not stall the event loop, because the router serves everyone else meanwhile',
      lagMs < LAG_CEILING_MS,
      `${lagMs} ms lag over ${wallMs} ms wall (sync measured 83 ms lag; ceiling ${LAG_CEILING_MS} ms)`
    );

    socket.destroy();
    client.kill();
    await new Promise((r) => client.on('exit', r));
    await new Promise((r) => server.close(r));
  }

  // ------------------------------------------------------------------ supervision
  process.stdout.write('\nsupervision\n');
  {
    const s = supervisor();
    check(
      IS_DARWIN ? 'macOS reports launchd' : `${PLATFORM} reports no supervisor rather than inventing one`,
      s.kind === (IS_DARWIN ? 'launchd' : 'none'),
      s.kind
    );
    check('the guarantee is stated in words somebody can read', s.guarantee.length > 20);
    if (!IS_DARWIN) {
      const out = s.restart('gg.rhodes.mcp-router');
      check('asking it to restart is a report, not a throw', out.restarted === false && out.detail.length > 0, out.detail);
      check('and the report names the platform rather than a missing binary', out.detail.includes(PLATFORM), out.detail);
    }
  }

  // ------------------------------------------------------------------ the config watcher
  //
  // G1. `supervisor()` closed the restart half of the launchd finding and left this half open,
  // which is the half a user meets first: on macOS a `WatchPaths` job runs `mcpr watch` on every
  // write to `~/.claude.json`, so a server added by `claude mcp add` is adopted on its own.
  // Nothing does that on Windows — and `watch.ts`'s header said "launchd fires this on the file
  // change" unconditionally while the usage text printed "(run by launchd on file change)" to a
  // Windows user. The behaviour was honest and the product's own output was not, so these arms
  // read the output.
  process.stdout.write('\nthe config watcher\n');
  {
    const w = configWatcher();
    check(
      IS_DARWIN ? 'macOS reports launchd' : `${PLATFORM} reports that nothing watches ~/.claude.json`,
      w.kind === (IS_DARWIN ? 'launchd' : 'none'),
      w.kind
    );
    check('the guarantee is stated in words somebody can read', w.guarantee.length > 20, w.guarantee);
    if (!IS_DARWIN) {
      check('and it names this platform rather than a mechanism this host does not have', w.guarantee.includes(PLATFORM));
      check('and it does not credit launchd on a host with no launchd', !/launchd/i.test(w.guarantee));
      check('and it says what to do instead', /mcpr watch/.test(w.guarantee), w.guarantee);
    }
  }
  {
    /* The product's own usage text, read out of the product rather than out of the source. This
       is the arm that would have caught the half-closed finding: every other check passed while
       this string told a Windows user launchd was adopting their servers. */
    const help = await shellOut(process.execPath, [join(REPO, 'dist', 'index.js'), '--help'], {
      /* Pointed at this run's own temporary home. `--help` prints the config and token *paths*
         and reads neither file, but the real `servers.json` holds live bearer tokens and no
         harness of this repo's is allowed to be one command away from touching it. */
      MCP_ROUTER_HOME: HOME,
    });
    check('`mcp-router --help` printed its usage', /mcp-router watch/.test(help), `${help.length} chars`);
    check(
      IS_DARWIN
        ? 'and on macOS the watch line credits launchd, which is true here'
        : 'and off macOS the watch line does not claim launchd runs it',
      IS_DARWIN ? /launchd/.test(help) : !/launchd/i.test(help),
      (help.split('\n').find((l) => /run by|run it yourself|nothing runs/.test(l)) ?? '').trim()
    );
    if (!IS_DARWIN) {
      check(
        'and it tells the user they have to run it themselves',
        /run it yourself/i.test(help),
        (help.split('\n').find((l) => /run it yourself/i.test(l)) ?? '').trim()
      );
    }
  }

  // ------------------------------------------------------------------ the parity harness position
  //
  // WIN17's seventh acceptance item asked the parity corpus to state whether Windows behaviour is
  // in it or deliberately out. An absence reads two ways — considered and excluded, or never
  // thought about — and only one of those is an answer. This check is that the answer exists and
  // names an oracle, because a position that says "out" without saying what proves it instead is
  // the same gap with a sentence in front of it.
  process.stdout.write('\nthe parity corpus states where Windows stands\n');
  {
    const src = readFileSync(join(REPO, 'scripts', 'parity', 'generate-vectors.mjs'), 'utf8');
    check('the corpus generator says something about Windows at all', /windows/i.test(src));
    check(
      'and states the position explicitly rather than leaving it to be inferred',
      /deliberately OUT|deliberately out/.test(src)
    );
    check(
      'and names what proves Windows behaviour instead, so the exclusion is not a gap',
      /e2e-platform\.mjs/.test(src)
    );
  }

  // ------------------------------------------------------------------ the one that was already fine
  process.stdout.write('\nROUTER_HOME\n');
  {
    const { ROUTER_HOME } = await import('../dist/config.js');
    check('resolves under this user\'s home on this platform', ROUTER_HOME.startsWith(homedir()), ROUTER_HOME);
  }
} finally {
  rmSync(HOME, { recursive: true, force: true });
}

process.stdout.write(`\n${checks} check(s), ${failures} failure(s)\n`);
process.exit(failures ? 1 : 0);
