/**
 * The other half of a live reload: the things MCP does not model, and the fact that for those
 * the router can only ask.
 *
 * `livereload.ts` tells attached sessions that the tool list moved, over the protocol's own
 * channel, with nobody in the loop. Skills, plugins and harness config are not in that protocol.
 * The only lever that reaches them is Claude Code's per-session unix socket, and what arrives
 * there is **text in the receiving session's turn**. So this module asks. It never claims to
 * have reloaded anything, and the outcome it reports is `delivered`, never `reloaded`.
 *
 * ## The three limits, measured rather than assumed
 *
 * Taken 2026-08-28 against the shipped `claude` 2.1.250 binary and this machine's session
 * registry. None of it was taken by messaging a session belonging to somebody else's work.
 *
 * 1. **A slash command in the message does not run.** The receiver enqueues an inbound peer
 *    message with `skipSlashCommands` set. So `/reload-skills` in the body is a string the
 *    receiving model reads, not a command the harness executes — the ask is genuinely an ask,
 *    and it is the harness that makes it one, not a convention anybody could change their mind
 *    about.
 * 2. **It drains at the receiver's next tool round.** A session sitting idle with nobody at the
 *    keyboard holds the message until it next does something. There is no wake in this.
 * 3. **The registry is the only address book, and it outlives the sessions in it.** Twenty
 *    sockets existed under `/tmp/cc-socks` when this was measured against fourteen registry
 *    entries; the difference is sessions that exited. A stale socket is the normal condition.
 *
 * ## The trap that would have made this report the opposite of the truth
 *
 * `procStart` in the registry is **UTC**. `ps -o lstart=` is **local**. Measured the same day on
 * two live sessions: the registry says `Sat Aug 22 10:02:12 2026` where `ps` says
 * `Sat Aug 22 20:02:12 2026` — the same instant, a constant +10:00 apart on a machine in AEST.
 * A string comparison between them classifies **every live session as recycled**, so the feature
 * reports nobody reachable at the exact moment everybody is. Instants are compared here, never
 * spellings, and `scripts/e2e-session-push.mjs` plants a session in the other spelling and
 * requires it to still read `reachable`.
 *
 * ## WIN17 — the same failure, through a different door, measured on Windows
 *
 * Everything above is macOS's registry read by macOS's tools. On Windows, on 2026-08-30, this
 * module reported all five live Claude Code sessions on the machine as `exited` — the identical
 * "nobody reachable at the moment everybody is" outcome the note above exists to prevent. Three
 * separate causes, each now a visible branch in `platform.ts`:
 *
 *   · **`ps` is not there.** `execFileSync('ps', …, { PATH: '/bin:/usr/bin' })` failed ENOENT in
 *     under a millisecond, and an empty start-time map reads as "every pid is dead". The Windows
 *     lane is `Get-Process`, and `processStartSeconds` now reports whether the probe *ran*, so
 *     "nobody was asked" is no longer spelled the same as "nobody is alive".
 *   · **`procStart` is a different number, not a different spelling.** Windows writes a FILETIME
 *     decimal string — `"134324966130572677"` — where macOS writes ctime. `Date.parse` of it is
 *     `NaN`, which fell through the `registered !== undefined` guard below, so the recycled-pid
 *     identity check *silently did not run at all* on Windows. `parseProcStart` reads both.
 *   · **The socket is a named pipe and cannot be stat'd.** `messagingSocketPath` on this machine is
 *     `\\.\pipe\cc-msg-<32 hex>`, and `existsSync` returns `false` for a live pipe, so the presence
 *     check below would have classified every Windows session `noSocket`. Presence is
 *     `indeterminate` there and the connect settles it.
 *
 * The reach vocabulary is unchanged — five classes, the same five on both platforms — because the
 * control API is one contract and a Windows client must not have to know which host it is talking
 * to.
 */
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { createConnection } from 'node:net';
import { randomUUID } from 'node:crypto';
import { log } from './log.js';
import { parseProcStart, processStartSeconds, socketPresence } from './platform.js';

/** How long one socket write is given before it is abandoned. A client must never stall the router. */
const PUSH_TIMEOUT_MS = 2_000;

/** How the router names itself in the message wrapper the receiving transcript renders. */
export const SENDER_NAME = 'mcp-router';

export type Reach =
  /** Alive, the identity checks out, the socket is there, and a peer token was found. */
  | 'reachable'
  /** As above but no key file, so the message would go unauthenticated. Some platforms accept that. */
  | 'unauthenticated'
  /** The pid is gone. Ordinary: the registry outlives its sessions. */
  | 'exited'
  /** The pid is alive but is not the process that registered — the number was reused. */
  | 'recycled'
  /** Registered, apparently alive, but the socket file is not there. */
  | 'noSocket';

export interface SessionView {
  pid: number;
  sessionId?: string;
  name?: string;
  cwd?: string;
  version?: string;
  status?: string;
  socketPath?: string;
  reach: Reach;
  /** Present only for `reachable`; never logged, never returned over the control API. */
  token?: string;
}

export interface PushOutcome {
  pid: number;
  name?: string;
  /** `delivered` means the bytes reached the session's inbox. It does not mean anything reloaded. */
  outcome: 'delivered' | 'refused' | 'timeout' | 'skipped';
  detail?: string;
}

const sessionsDir = (home: string): string => join(home, '.claude', 'sessions');

/**
 * `Sat Aug 22 10:02:12 2026` (UTC, as the macOS registry writes it) -> epoch seconds.
 *
 * Kept as the macOS-spelling reader; `parseProcStart` in `platform.ts` is the one that dispatches
 * on the spelling and is what the classifier below calls, because Windows writes a FILETIME
 * decimal rather than a ctime string.
 */
export function parseProcStartUtc(s: string): number | undefined {
  const ms = Date.parse(`${s.trim()} UTC`);
  return Number.isNaN(ms) ? undefined : Math.floor(ms / 1000);
}

/**
 * Start times for the pids given, as epoch seconds, from one OS call.
 *
 * The mechanism is `platform.ts`'s, which is `ps -o pid=,lstart=` on macOS and `Get-Process` on
 * Windows and carries the measurements behind both. This wrapper keeps the shape the rest of the
 * router and `scripts/e2e-session-push.mjs` already use, and drops the `probed` flag, because a
 * caller holding only a Map cannot act on it. `listSessions` reads the flag directly.
 *
 * The defence both lanes keep: one unusable pid must never answer for the others. macOS `ps`
 * rejects the whole invocation over an out-of-range pid — `ps: process id too large: 4194303` —
 * prints nothing for the good ones and exits non-zero; Windows `Get-Process` exits 1 over the same
 * input but does print the good rows. Both are read off the error's stdout, and a batch that
 * answered for nobody is retried one pid at a time.
 */
export function processStarts(pids: number[]): Map<number, number> {
  return processStartSeconds(pids).starts;
}

export interface SessionSweep {
  sessions: SessionView[];
  /**
   * Whether the liveness probe ran at all.
   *
   * `false` means no pid was *asked* about, so every row's `exited` is an artefact of the sweep
   * rather than a fact about the machine. Carried here and not on `SessionView` deliberately: the
   * control API's `/sessions` response is one contract shared with the Windows client, and its five
   * reach classes have no way to say "unknown". Widening that vocabulary is a contract change and
   * belongs with whoever designs the Windows client contract (WIN12, WIN23), not to WIN17. Until
   * then the honest signal goes to the CLI, which is where a person is reading, and to the log.
   */
  livenessProbed: boolean;
  /** Present when `livenessProbed` is false: what was missing. */
  detail?: string;
}

/**
 * Every session the registry knows about, each classified by whether a message could reach it,
 * together with whether the classification could be made at all.
 *
 * Read-only and total: a row that cannot be parsed is dropped with a warning rather than taking
 * the sweep down with it, and the count of what was dropped is reported by the caller.
 */
export function sweepSessions(home: string = homedir()): SessionSweep {
  const dir = sessionsDir(home);
  if (!existsSync(dir)) return { sessions: [], livenessProbed: true };

  let names: string[];
  try {
    names = readdirSync(dir);
  } catch (err) {
    log.warn(`sessions: cannot read ${dir}: ${(err as Error).message}`);
    return { sessions: [], livenessProbed: true };
  }

  /* The key file is `<pid>.<64 hex>.key` and holds `{ peerToken, procStart }` at 0600. Indexed
     by pid so a session's token is found without reading every file twice. */
  const keyFor = new Map<number, string>();
  for (const f of names) {
    const m = /^(\d+)\.[0-9a-f]{64}\.key$/.exec(f);
    if (!m) continue;
    keyFor.set(Number(m[1]), join(dir, f));
  }

  const rows: Array<Record<string, unknown>> = [];
  for (const f of names) {
    if (!/^\d+\.json$/.test(f)) continue;
    try {
      rows.push(JSON.parse(readFileSync(join(dir, f), 'utf8')) as Record<string, unknown>);
    } catch {
      log.warn(`sessions: ${f} did not parse; skipping it`);
    }
  }

  const pids = rows.map((r) => Number(r.pid)).filter((n) => Number.isInteger(n) && n > 0);
  const probe = processStartSeconds(pids);
  const starts = probe.starts;
  if (!probe.probed) {
    log.error(
      `sessions: the liveness probe did not run (${probe.detail ?? 'unknown reason'}), so no pid was asked about; ` +
        `every one of the ${rows.length} row(s) below reads "exited" because nothing answered, not because nothing is running.`
    );
  }

  const sessions = rows.map((r) => {
    const pid = Number(r.pid);
    const socketPath = typeof r.messagingSocketPath === 'string' ? r.messagingSocketPath : undefined;
    const view: SessionView = {
      pid,
      sessionId: typeof r.sessionId === 'string' ? r.sessionId : undefined,
      name: typeof r.name === 'string' ? r.name : undefined,
      cwd: typeof r.cwd === 'string' ? r.cwd : undefined,
      version: typeof r.version === 'string' ? r.version : undefined,
      status: typeof r.status === 'string' ? r.status : undefined,
      socketPath,
      reach: 'exited',
    };

    const liveAt = starts.get(pid);
    if (liveAt === undefined) return view; // exited

    /*
     * The identity check. A pid on its own is not an identity — the number is reused, and a
     * message aimed at a reused pid lands in whatever now owns it. Comparing instants rather
     * than the two spellings of one is the whole of the header note above.
     */
    const registered = typeof r.procStart === 'string' ? parseProcStart(r.procStart) : undefined;
    if (registered !== undefined && Math.abs(registered - liveAt) > 1) {
      return { ...view, reach: 'recycled' as const };
    }

    /*
     * `absent` is the only answer that settles this negatively. On Windows the endpoint is a named
     * pipe, which cannot be stat'd — `existsSync` of a live one returns false — so presence there
     * is `indeterminate` and the row goes on to the key check. What that costs is stated rather
     * than hidden: a stale Windows endpoint is discovered as a `refused` push outcome instead of
     * being filtered out here as `noSocket`.
     */
    if (!socketPath || socketPresence(socketPath) === 'absent') return { ...view, reach: 'noSocket' as const };

    const keyPath = keyFor.get(pid);
    if (!keyPath) return { ...view, reach: 'unauthenticated' as const };
    try {
      const key = JSON.parse(readFileSync(keyPath, 'utf8')) as { peerToken?: unknown };
      if (typeof key.peerToken !== 'string' || !key.peerToken) {
        return { ...view, reach: 'unauthenticated' as const };
      }
      return { ...view, reach: 'reachable' as const, token: key.peerToken };
    } catch {
      return { ...view, reach: 'unauthenticated' as const };
    }
  });

  return { sessions, livenessProbed: probe.probed, detail: probe.detail };
}

/**
 * Every session the registry knows about, classified.
 *
 * The shape every existing caller wants, and unchanged. `sweepSessions` is what to call when the
 * difference between "nothing is running" and "nothing was asked" needs to reach the reader.
 */
export function listSessions(home: string = homedir()): SessionView[] {
  return sweepSessions(home).sessions;
}

/**
 * The body a session receives, wrapped the way the transport's own sender wraps one so the
 * receiving transcript attributes it rather than rendering it as an anonymous `peer`.
 *
 * It says what changed, and it says what it is not: a session that reads a slash command here
 * cannot execute it, so telling it to expect one to work would be the message lying about
 * itself.
 */
export function reloadMessage(what: string): string {
  return [
    `<cross-session-message from="${SENDER_NAME}" from-name="${SENDER_NAME}">`,
    `mcp-router: ${what}`,
    '',
    'Your session read its skills, plugins and harness config once, at startup, and nothing is',
    'watching those files — so this change is not visible to you yet. The MCP tool list is',
    'handled separately and needs nothing from you.',
    '',
    'If this matters to what you are doing, ask the person at this session to run the reload',
    'they need (/reload-skills, /reload-plugins). This message arrived as text with slash',
    'commands disabled, so nothing in it has run or can run on its own.',
    '</cross-session-message>',
  ].join('\n');
}

/**
 * Ask one session to reload. Resolves with an outcome; never throws.
 *
 * The frame shape is the one the transport documents for itself: an `auth` line, then a `user`
 * line, newline-delimited JSON. `session_id` is carried deliberately — the receiver drops a
 * message whose `session_id` does not match its own, which makes a push at a recycled pid a
 * refusal on the receiving end as well as on this one.
 */
export function pushTo(session: SessionView, body: string): Promise<PushOutcome> {
  const { pid, name, socketPath, token, sessionId } = session;
  if (!socketPath) return Promise.resolve({ pid, name, outcome: 'skipped', detail: 'no socket' });

  return new Promise<PushOutcome>((resolve) => {
    let settled = false;
    const done = (o: PushOutcome): void => {
      if (settled) return;
      settled = true;
      socket.destroy();
      resolve(o);
    };

    const socket = createConnection({ path: socketPath });
    socket.setTimeout(PUSH_TIMEOUT_MS, () => done({ pid, name, outcome: 'timeout' }));
    socket.on('error', (err) => done({ pid, name, outcome: 'refused', detail: (err as Error).message }));

    socket.on('connect', () => {
      const lines: string[] = [];
      // The auth line must come first; a connection that sends anything else first is dropped
      // unauthenticated. The token is written and never logged.
      if (token) lines.push(JSON.stringify({ type: 'auth', token }));
      lines.push(
        JSON.stringify({
          type: 'user',
          msg_id: `mcp-router-${randomUUID()}`,
          uuid: randomUUID(),
          priority: 'next',
          ...(sessionId ? { session_id: sessionId } : {}),
          message: { role: 'user', content: body },
        })
      );
      socket.end(`${lines.join('\n')}\n`, () => {
        done({
          pid,
          name,
          outcome: 'delivered',
          detail: token ? undefined : 'sent unauthenticated (no key file)',
        });
      });
    });
  });
}

export interface PushReport {
  /** Every session the registry held, whatever its reach. */
  considered: number;
  /** Sessions a message was actually aimed at. */
  targeted: number;
  outcomes: PushOutcome[];
  /** Counts by reach, so "nobody was reachable" is distinguishable from "nobody was there". */
  byReach: Record<Reach, number>;
  dryRun: boolean;
}

/**
 * Ask every reachable session to reload.
 *
 * Best effort, bounded, and unable to block the router: a session is a dependency the router
 * must never acquire. `dryRun` reports exactly who would be reached and sends nothing, which is
 * the only honest way to look at this before turning it on.
 */
export async function askSessionsToReload(
  what: string,
  opts: { home?: string; dryRun?: boolean } = {}
): Promise<PushReport> {
  const sweep = sweepSessions(opts.home ?? homedir());
  const sessions = sweep.sessions;
  const byReach: Record<Reach, number> = {
    reachable: 0,
    unauthenticated: 0,
    exited: 0,
    recycled: 0,
    noSocket: 0,
  };
  for (const s of sessions) byReach[s.reach] += 1;

  const targets = sessions.filter((s) => s.reach === 'reachable' || s.reach === 'unauthenticated');
  /*
   * A sweep whose liveness probe did not run finds nobody, and "nobody was reachable" is exactly
   * how that looks from the outside. Said here as well as in `sweepSessions`, because this is the
   * call that decides nothing gets sent.
   */
  if (!sweep.livenessProbed) {
    log.error(
      `sessions: no message will be sent — the liveness probe did not run (${sweep.detail ?? 'unknown reason'}), ` +
        `so every one of the ${sessions.length} registered session(s) was classified without being asked.`
    );
  }
  if (opts.dryRun) {
    return {
      considered: sessions.length,
      targeted: targets.length,
      byReach,
      dryRun: true,
      outcomes: targets.map((s) => ({ pid: s.pid, name: s.name, outcome: 'skipped', detail: 'dry run' })),
    };
  }

  const body = reloadMessage(what);
  const outcomes = await Promise.all(targets.map((s) => pushTo(s, body)));
  const delivered = outcomes.filter((o) => o.outcome === 'delivered').length;
  log.info(
    `sessions: asked ${delivered}/${targets.length} session(s) to reload (${sessions.length} in the registry, ` +
      `${byReach.exited} exited, ${byReach.recycled} recycled, ${byReach.noSocket} without a socket)`
  );
  return { considered: sessions.length, targeted: targets.length, byReach, dryRun: false, outcomes };
}
