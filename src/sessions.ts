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
 */
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { createConnection } from 'node:net';
import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { log } from './log.js';

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

/** `Sat Aug 22 10:02:12 2026` (UTC, as the registry writes it) -> epoch seconds. */
export function parseProcStartUtc(s: string): number | undefined {
  const ms = Date.parse(`${s.trim()} UTC`);
  return Number.isNaN(ms) ? undefined : Math.floor(ms / 1000);
}

/**
 * Start times for the pids given, as epoch seconds, from one `ps`.
 *
 * `LC_ALL=C` is load-bearing: without it `ps` prints `Sat 22 Aug 20:02:12 2026` on this machine
 * and the parse silently yields the wrong instant. One call rather than one per session.
 */
export function processStarts(pids: number[]): Map<number, number> {
  const out = new Map<number, number>();
  const wanted = pids.filter((n) => Number.isSafeInteger(n) && n > 0);
  if (wanted.length === 0) return out;

  const ask = (batch: number[]): string => {
    try {
      return execFileSync('ps', ['-o', 'pid=,lstart=', '-p', batch.join(',')], {
        encoding: 'utf8',
        env: { LC_ALL: 'C', PATH: '/bin:/usr/bin' },
      });
    } catch (err) {
      /*
       * Two different things arrive here and they must not be conflated.
       *
       * Every pid being dead is an ordinary exit-1 from `ps` with the output it did produce
       * still on the error, so that output is read rather than discarded.
       *
       * A single unusable pid is the one that cost this a defect: macOS `ps` rejects the whole
       * invocation — `ps: process id too large: 4194303` — prints NOTHING for the pids that were
       * fine, and exits non-zero. Read as "nobody is alive", one junk row in the registry
       * silently reclassifies every live session on the machine as exited, and the feature then
       * reports nobody reachable at the moment everybody is. That is not a corner case worth a
       * bound: it is a reason never to let one bad entry answer for the others.
       */
      return String((err as { stdout?: unknown }).stdout ?? '');
    }
  };

  const absorb = (raw: string): number => {
    let found = 0;
    for (const line of raw.split('\n')) {
      const m = /^\s*(\d+)\s+(.+?)\s*$/.exec(line);
      if (!m) continue;
      // `ps` prints local time and `Date.parse` of a bare ctime string reads it as local.
      // Correct here, and the exact opposite of how `procStart` must be read — see the header.
      const at = Date.parse(m[2]!);
      if (Number.isNaN(at)) continue;
      out.set(Number(m[1]), Math.floor(at / 1000));
      found += 1;
    }
    return found;
  };

  absorb(ask(wanted));
  /*
   * Only when the batch answered for nobody, and only then: asking once per pid costs one
   * process per session, which is the reason the batched call exists. Reaching here means the
   * batch was refused rather than empty, so the per-pid pass is what separates "the registry
   * holds a junk row" from "nothing is running".
   */
  if (out.size === 0 && wanted.length > 1) {
    for (const pid of wanted) absorb(ask([pid]));
  }
  return out;
}

/**
 * Every session the registry knows about, each classified by whether a message could reach it.
 *
 * Read-only and total: a row that cannot be parsed is dropped with a warning rather than taking
 * the sweep down with it, and the count of what was dropped is reported by the caller.
 */
export function listSessions(home: string = homedir()): SessionView[] {
  const dir = sessionsDir(home);
  if (!existsSync(dir)) return [];

  let names: string[];
  try {
    names = readdirSync(dir);
  } catch (err) {
    log.warn(`sessions: cannot read ${dir}: ${(err as Error).message}`);
    return [];
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
  const starts = processStarts(pids);

  return rows.map((r) => {
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
    const registered = typeof r.procStart === 'string' ? parseProcStartUtc(r.procStart) : undefined;
    if (registered !== undefined && Math.abs(registered - liveAt) > 1) {
      return { ...view, reach: 'recycled' as const };
    }

    if (!socketPath || !existsSync(socketPath)) return { ...view, reach: 'noSocket' as const };

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
  const sessions = listSessions(opts.home ?? homedir());
  const byReach: Record<Reach, number> = {
    reachable: 0,
    unauthenticated: 0,
    exited: 0,
    recycled: 0,
    noSocket: 0,
  };
  for (const s of sessions) byReach[s.reach] += 1;

  const targets = sessions.filter((s) => s.reach === 'reachable' || s.reach === 'unauthenticated');
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
