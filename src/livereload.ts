/**
 * The half of a live reload that needs nobody: telling attached sessions that the tool
 * list moved, over the stream they already hold open.
 *
 * ## Why this exists at all, and why it is four dozen lines rather than a redesign
 *
 * The README's standing advice was "start a new session; a running one fetched its tool list
 * once at init". That is true of this router and false of the protocol. Measured 2026-08-28
 * against a fixture server and a `claude -p` session started for the purpose:
 *
 *   02:37:22.548  client opens GET /mcp; the standalone SSE stream is held
 *   02:37:22.549  tools/list #1 answered with 1 tool
 *   02:37:32.121  fixture pushes notifications/tools/list_changed down that stream
 *   02:37:32.124  tools/list #2 arrives unprompted, answered with 2 tools
 *
 * Three milliseconds, while the session was inside a 25-second `sleep`, with no person at the
 * keyboard and no model in the loop. `planning/evidence/R29/exp-A-session-id-sent.log`. The same
 * run with the `mcp-session-id` response header suppressed behaves identically
 * (`exp-B-session-id-suppressed.log`), so a stateless server is not excluded from this.
 *
 * The router was already serving that stream and throwing the reference away: every request
 * built a fresh transport and `res.on('close')` closed it. So the whole gap was a registry, and
 * this is it. Nothing here makes the router stateful — a GET stream carries no MCP session
 * state, it is a one-way pipe for server-initiated notifications, and each one is still its own
 * transport.
 *
 * ## What it cannot do, stated here rather than discovered later
 *
 * `notifications/tools/list_changed` has **no payload**. The protocol gives it no field for what
 * changed, so this cannot name the server that moved; it tells the client to re-fetch and the
 * client works out the difference. Naming the change is `sessions.ts`'s job, over a different
 * transport, with a different guarantee.
 *
 * It also reaches only what MCP models: the tool list. Skills, plugins and harness config are
 * not in this protocol and are not reachable from here at any speed.
 */
import { log } from './log.js';

/**
 * The narrow slice of an MCP transport this needs, plus the two things that make a delivery a
 * measurement rather than a claim.
 *
 * `bytesOut` is why this is not just `send`. The SDK's `send()` **returns silently** when the
 * standalone stream is disconnected — `Stream is disconnected - event is stored for replay,
 * nothing more to do`,
 * `node_modules/@modelcontextprotocol/sdk/dist/esm/server/webStandardStreamableHttp.js:835` at
 * `bb3359a`. So an awaited `send()` that resolved proves nothing about whether anything left the
 * machine, and a `delivered` count built on it would report a push to nobody as a push to
 * everybody. Reading the bytes the response has actually handed to its socket turns that into
 * something that can go red.
 *
 * Structural rather than the SDK's class, so the fixture in `scripts/e2e-live-reload.mjs`
 * exercises this registry rather than a copy of it.
 */
export interface NotifiableStream {
  send(message: { jsonrpc: '2.0'; method: string; params?: Record<string, unknown> }): Promise<void>;
  /** False once the underlying response is finished or destroyed. */
  isOpen(): boolean;
  /** Bytes this stream has handed to its socket, buffered included. Monotonic. */
  bytesOut(): number;
}

export interface AnnounceResult {
  /** Streams the registry held when the announcement began. */
  streams: number;
  /** Streams that took the notification, proved by bytes moving rather than by a resolved promise. */
  delivered: number;
  /** Streams that were closed, or took the call without emitting a byte. Each was dropped. */
  failed: number;
  reason: string;
}

/**
 * Every standalone `GET /mcp` SSE stream currently open, and the one thing worth sending down
 * one.
 */
export class LiveReload {
  private readonly streams = new Set<NotifiableStream>();
  /** The manifest stamp the last announcement was made against. See `announceIfMoved`. */
  private announcedStamp: string | undefined;

  /** @returns an unregister function; call it when the stream closes. */
  register(stream: NotifiableStream): () => void {
    this.streams.add(stream);
    log.info(`live-reload: a session opened a notification stream (${this.streams.size} open)`);
    return () => {
      if (this.streams.delete(stream)) {
        log.info(`live-reload: a notification stream closed (${this.streams.size} open)`);
      }
    };
  }

  /** How many sessions a notification would reach right now. */
  get openStreams(): number {
    return this.streams.size;
  }

  /**
   * Tell every attached session to re-fetch its tool list.
   *
   * Best effort by construction, and the direction of the dependency is the reason: a router
   * that waited on a client would be a router any client could stall. A send that throws means
   * that stream is gone, so it is dropped rather than retried — a session that has exited is a
   * normal condition here, not an error, which is the brief's own requirement.
   */
  /**
   * Announce only if the manifest is somewhere this instance has not already announced from.
   *
   * `mcpr index` and the launchd watcher write the manifest from other processes, so a change
   * can land with no control-API request behind it and no `tools/list` to notice it. A poller
   * covers that. It must not double-fire on the changes the control API already announced, and
   * this is what stops it: an announcement records the stamp it was made at, and a tick at that
   * same stamp is not a change.
   *
   * The first call after startup is a seed, not an announcement: the manifest on disk at boot is
   * not news to anybody, and telling every session to re-fetch because the router restarted is
   * the router charging its clients for its own lifecycle.
   */
  async announceIfMoved(stamp: string, reason: string): Promise<AnnounceResult | undefined> {
    if (!stamp) return undefined;
    if (this.announcedStamp === undefined) {
      this.announcedStamp = stamp;
      return undefined;
    }
    if (stamp === this.announcedStamp) return undefined;
    return this.announceToolsChanged(reason, stamp);
  }

  /** Record where a change landed, so the poller does not announce it a second time. */
  noteStamp(stamp: string): void {
    if (stamp) this.announcedStamp = stamp;
  }

  async announceToolsChanged(reason: string, stamp?: string): Promise<AnnounceResult> {
    if (stamp) this.announcedStamp = stamp;
    const targets = [...this.streams];
    let delivered = 0;
    let failed = 0;

    await Promise.all(
      targets.map(async (stream) => {
        const drop = (why: string): void => {
          failed += 1;
          this.streams.delete(stream);
          log.warn(`live-reload: dropping a notification stream — ${why}`);
        };

        if (!stream.isOpen()) return drop('its response is already finished');

        const before = stream.bytesOut();
        try {
          await stream.send({ jsonrpc: '2.0', method: 'notifications/tools/list_changed' });
        } catch (err) {
          return drop(`it refused the notification: ${(err as Error).message}`);
        }

        /*
         * The check that makes `delivered` a number rather than an assertion. A resolved `send`
         * is not evidence: the SDK returns without writing when the stream has gone. If no byte
         * moved, nothing was delivered, whatever the promise said.
         */
        if (stream.bytesOut() <= before) {
          return drop('it accepted the notification without emitting a byte');
        }
        delivered += 1;
      })
    );

    /*
     * Said even when it reached nobody, and said with both numbers in it. "Announced a tool
     * change" over an empty registry is the sentence that makes a push to nobody read as a push.
     */
    log.info(
      `live-reload: ${reason} -> notified ${delivered}/${targets.length} attached session(s)` +
        (failed ? `, ${failed} stream(s) had gone` : '')
    );
    return { streams: targets.length, delivered, failed, reason };
  }
}
