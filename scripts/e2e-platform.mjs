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
 * It touches nothing outside its own temporary directory, spawns no browser, and reads no session
 * registry: the pids it asks about are this process and one it starts and waits for itself.
 */
import { mkdirSync, writeFileSync, rmSync, existsSync } from 'node:fs';
import { tmpdir, homedir } from 'node:os';
import { join, delimiter } from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
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
  socketPresence,
  residentKb,
  supervisor,
} from '../dist/platform.js';
import { withExclusiveLock } from '../dist/lock.js';
import { augmentPath } from '../dist/pool.js';

const HOME = join(tmpdir(), `mcp-router-win17-${process.pid}`);
let failures = 0;
let checks = 0;
const check = (label, ok, detail = '') => {
  checks += 1;
  process.stdout.write(`  ${ok ? 'PASS' : 'FAIL'}  ${label}${detail ? ` — ${detail}` : ''}\n`);
  if (!ok) failures += 1;
};

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
    const kb = await residentKb([process.pid]);
    const mine = kb.get(process.pid);
    check('this process has a resident figure', mine !== undefined && mine > 0, `${mine} KB`);
    check(
      'and it is the same order of magnitude as node reports for itself',
      mine !== undefined && mine > process.memoryUsage().rss / 1024 / 8,
      `probe ${mine} KB vs process.memoryUsage().rss ${Math.round(process.memoryUsage().rss / 1024)} KB`
    );
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

/* `spawnSync` is imported for parity with the other harnesses' shape and is intentionally unused;
   removing it would be the only edit in this file not backed by a measurement. */
void spawnSync;
