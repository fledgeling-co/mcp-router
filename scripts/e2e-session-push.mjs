/**
 * The socket half of R29, proved against a fixture session this script creates and owns.
 *
 * **It never reads the real session registry and never writes to a real session.** Every call
 * into `listSessions` is given an explicit temporary HOME, the socket is one this process binds
 * itself, and the pids in the fixture registry are this process and a number that is certainly
 * dead. A live session on this machine belongs to somebody else's work, and a message landing in
 * it mid-task is an interruption they pay for.
 *
 *   node scripts/e2e-session-push.mjs
 *
 * Exit 0 clean · 1 findings · 2 the run could not measure what it was asked to.
 */
import { mkdirSync, writeFileSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createServer } from 'node:net';
import { spawn } from 'node:child_process';
import { listSessions, pushTo, askSessionsToReload, processStarts } from '../dist/sessions.js';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..');
const HOME = join(tmpdir(), `mcp-router-r29-${process.pid}`);
const SESSIONS = join(HOME, '.claude', 'sessions');

let failures = 0;
let checks = 0;
const check = (label, ok, detail = '') => {
  checks += 1;
  process.stdout.write(`  ${ok ? 'PASS' : 'FAIL'}  ${label}${detail ? ` — ${detail}` : ''}\n`);
  if (!ok) failures += 1;
};
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

/** ctime in UTC, which is the spelling the real registry uses for `procStart`. */
const utcCtime = (epochSec) => {
  const d = new Date(epochSec * 1000);
  const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const mons = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const p = (n) => String(n).padStart(2, '0');
  return `${days[d.getUTCDay()]} ${mons[d.getUTCMonth()]} ${String(d.getUTCDate()).padStart(2, ' ')} ${p(d.getUTCHours())}:${p(d.getUTCMinutes())}:${p(d.getUTCSeconds())} ${d.getUTCFullYear()}`;
};
/** The same instant spelled in LOCAL time — the wrong one, and the one a naive reader would use. */
const localCtime = (epochSec) => {
  const d = new Date(epochSec * 1000);
  const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const mons = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const p = (n) => String(n).padStart(2, '0');
  return `${days[d.getDay()]} ${mons[d.getMonth()]} ${String(d.getDate()).padStart(2, ' ')} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())} ${d.getFullYear()}`;
};

const writeSession = (pid, extra) => {
  writeFileSync(join(SESSIONS, `${pid}.json`), JSON.stringify({ pid, kind: 'interactive', ...extra }, null, 2));
};
const writeKey = (pid, token) => {
  writeFileSync(join(SESSIONS, `${pid}.${'a'.repeat(64)}.key`), JSON.stringify({ peerToken: token }), { mode: 0o600 });
};

rmSync(HOME, { recursive: true, force: true });
mkdirSync(SESSIONS, { recursive: true });

/* This process's own start time, read through the module under test rather than assumed, so the
   fixture and the classifier cannot disagree about what "now" means. */
const myStart = processStarts([process.pid]).get(process.pid);
if (myStart === undefined) {
  process.stdout.write('  could not read this process\'s own start time; the run measured nothing\n');
  process.exit(2);
}

/* A pid that is certainly dead, MEASURED rather than assumed: run something trivial, wait for
   it to exit, and take its number. A hard-coded "surely nothing is running here" constant was
   tried first and found the production defect below — `ps` rejects an out-of-range pid outright
   and prints nothing for the good ones, so one junk registry row blinded the whole sweep. The
   fix is in `processStarts`; this fixture no longer depends on the answer. */
const DEAD_PID = await new Promise((resolve, reject) => {
  const p = spawn('true', [], { stdio: 'ignore' });
  p.on('error', reject);
  p.on('exit', () => resolve(p.pid));
});

/* And one row carrying a pid `ps` itself refuses, so the sweep is proved to survive it rather
   than being reclassified wholesale. This is the regression arm for that defect. */
const ABSURD_PID = 4194303;

const RECEIVED = [];
const SOCK = join(HOME, 'fixture.sock');
const fixture = createServer((socket) => {
  let buf = '';
  socket.on('data', (c) => {
    buf += c.toString('utf8');
    let i;
    while ((i = buf.indexOf('\n')) !== -1) {
      const line = buf.slice(0, i);
      buf = buf.slice(i + 1);
      if (line.trim()) RECEIVED.push(line);
    }
  });
  socket.on('end', () => {
    if (buf.trim()) RECEIVED.push(buf);
  });
});
await new Promise((r) => fixture.listen(SOCK, r));

/* A second fixture address that nothing is listening on: a socket file that exists so the
   classifier calls it reachable, and a connect that must therefore be REFUSED rather than
   quietly counted. Bound then closed, leaving the path behind — which is exactly the stale
   socket the real registry is full of. */
const DEAD_SOCK = join(HOME, 'refuses.sock');
const deadServer = createServer(() => {});
await new Promise((r) => deadServer.listen(DEAD_SOCK, r));
await new Promise((r) => deadServer.close(r));

const TOKEN = 'f'.repeat(32);
const SESSION_ID = 'r29-fixture-session-id';

try {
  // ---------------------------------------------------------------- classification
  writeSession(process.pid, {
    sessionId: SESSION_ID,
    name: 'r29-fixture',
    cwd: REPO,
    procStart: utcCtime(myStart),
    messagingSocketPath: SOCK,
    status: 'idle',
  });
  writeKey(process.pid, TOKEN);

  let seen = listSessions(HOME);
  check('the fixture session is found, and only it', seen.length === 1, `${seen.length} row(s)`);
  check('a live session with a matching procStart is reachable', seen[0]?.reach === 'reachable', seen[0]?.reach);
  check('its peer token is resolved from the key file', seen[0]?.token === TOKEN);

  /*
   * The trap arm. `procStart` in the real registry is UTC; `ps -o lstart=` is local. A reader
   * that compares the two spellings as strings gets this arm and the one above EXACTLY
   * INVERTED — it calls every live session recycled and every recycled one live. On a machine
   * whose local time IS UTC the two spellings coincide and this arm cannot discriminate, so it
   * says so rather than passing.
   */
  writeSession(process.pid, {
    sessionId: SESSION_ID,
    name: 'r29-fixture',
    cwd: REPO,
    procStart: localCtime(myStart),
    messagingSocketPath: SOCK,
  });
  seen = listSessions(HOME);
  if (utcCtime(myStart) === localCtime(myStart)) {
    process.stdout.write('  SKIP  the UTC-vs-local arm — this machine runs at UTC, so the two spellings coincide\n');
  } else {
    check(
      'a procStart spelled in local time reads as recycled, not reachable',
      seen[0]?.reach === 'recycled',
      seen[0]?.reach
    );
  }

  // Back to the truthful spelling for everything below.
  writeSession(process.pid, {
    sessionId: SESSION_ID,
    name: 'r29-fixture',
    cwd: REPO,
    procStart: utcCtime(myStart),
    messagingSocketPath: SOCK,
  });

  writeSession(DEAD_PID, { sessionId: 'gone', procStart: utcCtime(myStart), messagingSocketPath: SOCK });
  seen = listSessions(HOME);
  check('a dead pid reads as exited', seen.find((s) => s.pid === DEAD_PID)?.reach === 'exited');

  /*
   * The regression arm for the defect this fixture found. `ps` refuses an out-of-range pid and
   * prints nothing for the pids that were fine, so a reader that trusts one batched call
   * reclassifies EVERY live session as exited on the strength of one junk row. The live session
   * must still read reachable with this row present.
   */
  writeSession(ABSURD_PID, { sessionId: 'junk', procStart: utcCtime(myStart), messagingSocketPath: SOCK });
  seen = listSessions(HOME);
  check(
    'a registry row whose pid `ps` refuses does not blind the sweep',
    seen.find((s) => s.pid === process.pid)?.reach === 'reachable',
    `the live session read ${seen.find((s) => s.pid === process.pid)?.reach}`
  );
  check('and that row itself reads as exited', seen.find((s) => s.pid === ABSURD_PID)?.reach === 'exited');
  rmSync(join(SESSIONS, `${ABSURD_PID}.json`));

  writeSession(process.pid + 0, {
    sessionId: SESSION_ID,
    procStart: utcCtime(myStart),
    messagingSocketPath: join(HOME, 'not-there.sock'),
  });
  seen = listSessions(HOME);
  check(
    'a registered session whose socket is gone reads as noSocket',
    seen.find((s) => s.pid === process.pid)?.reach === 'noSocket',
    seen.find((s) => s.pid === process.pid)?.reach
  );

  // Restore the good row and drop the key file: unauthenticated is its own class, not an error.
  rmSync(join(SESSIONS, `${process.pid}.${'a'.repeat(64)}.key`));
  writeSession(process.pid, {
    sessionId: SESSION_ID,
    procStart: utcCtime(myStart),
    messagingSocketPath: SOCK,
  });
  seen = listSessions(HOME);
  check(
    'a session with no key file reads as unauthenticated, not unreachable',
    seen.find((s) => s.pid === process.pid)?.reach === 'unauthenticated'
  );
  writeKey(process.pid, TOKEN);

  // ---------------------------------------------------------------- the frame on the wire
  RECEIVED.length = 0;
  seen = listSessions(HOME);
  const target = seen.find((s) => s.pid === process.pid);
  const outcome = await pushTo(target, 'BODY-UNDER-TEST');
  await wait(150);

  check('the push reports delivered', outcome.outcome === 'delivered', outcome.detail ?? '');
  check('the fixture received exactly two lines', RECEIVED.length === 2, `${RECEIVED.length}`);

  let auth, user;
  try {
    auth = JSON.parse(RECEIVED[0] ?? '{}');
    user = JSON.parse(RECEIVED[1] ?? '{}');
  } catch (err) {
    check('both lines are JSON', false, String(err));
    auth = {};
    user = {};
  }
  check('the FIRST line is the auth frame', auth.type === 'auth', auth.type);
  check('the auth frame carries the peer token', auth.token === TOKEN);
  check('the second line is a user frame', user.type === 'user', user.type);
  check('the user frame carries the target session id', user.session_id === SESSION_ID, user.session_id);
  check('the body is the one that was passed', user.message?.content === 'BODY-UNDER-TEST');
  check('the frame is attributed to this router', String(user.msg_id ?? '').startsWith('mcp-router-'), user.msg_id);

  // ---------------------------------------------------------------- the refusal arm
  RECEIVED.length = 0;
  const refusedOutcome = await pushTo({ ...target, socketPath: DEAD_SOCK }, 'BODY-UNDER-TEST');
  check(
    'a socket file with nobody behind it is reported refused, not delivered',
    refusedOutcome.outcome === 'refused',
    `${refusedOutcome.outcome}${refusedOutcome.detail ? ` (${refusedOutcome.detail})` : ''}`
  );

  // ---------------------------------------------------------------- the sweep, and its control
  RECEIVED.length = 0;
  const report = await askSessionsToReload('a change under test', { home: HOME });
  await wait(150);
  check('the sweep considered every registry row', report.considered === listSessions(HOME).length, `${report.considered}`);
  check('the sweep targeted only the live one', report.targeted === 1, `${report.targeted}`);
  check('the exited row is counted, not treated as a failure', report.byReach.exited === 1, `${report.byReach.exited}`);
  check('and nothing was aimed at it', report.outcomes.every((o) => o.pid !== DEAD_PID));
  check('the message names what changed', RECEIVED.some((l) => l.includes('a change under test')));
  check(
    'the message is wrapped so the receiving transcript attributes it',
    RECEIVED.some((l) => l.includes('<cross-session-message')),
  );
  check(
    'the message says the slash commands in it will not run',
    RECEIVED.some((l) => l.includes('slash') && l.includes('commands disabled')),
  );

  /*
   * The control. A dry run must send NOTHING and must still say who it would have reached; a
   * dry run that reports the same shape as a real one, having emitted no bytes, is precisely
   * the green this repo has been burned by.
   */
  RECEIVED.length = 0;
  const dry = await askSessionsToReload('a change under test', { home: HOME, dryRun: true });
  await wait(150);
  check('CONTROL: a dry run emits no bytes at all', RECEIVED.length === 0, `${RECEIVED.length} line(s)`);
  check('CONTROL: a dry run still names who it would reach', dry.targeted === 1 && dry.dryRun === true);
  check(
    'CONTROL: a dry run reports no delivery',
    dry.outcomes.every((o) => o.outcome === 'skipped'),
    dry.outcomes.map((o) => o.outcome).join(',')
  );

  /*
   * The second control, and the one that keeps this file honest about itself: an EMPTY registry
   * must report nobody, from zero rows. A sweep that reports a target over an empty directory
   * has measured nothing and must not read as clean.
   */
  for (const f of ['fixture.sock']) void f;
  const EMPTY = join(HOME, 'empty-home');
  mkdirSync(join(EMPTY, '.claude', 'sessions'), { recursive: true });
  const nobody = await askSessionsToReload('a change under test', { home: EMPTY });
  check('CONTROL: an empty registry reports 0 considered and 0 targeted', nobody.considered === 0 && nobody.targeted === 0);
} finally {
  await new Promise((r) => fixture.close(r));
  rmSync(HOME, { recursive: true, force: true });
}

if (checks === 0) {
  process.stdout.write('\nerror: this run made no checks, which is a failure rather than a pass.\n');
  process.exit(2);
}
process.stdout.write(`\n${checks - failures}/${checks} checks passed\n`);
process.exit(failures ? 1 : 0);
