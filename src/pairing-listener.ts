import { createPublicKey, randomBytes, randomUUID } from 'node:crypto';
import { hostname } from 'node:os';
import type { AddressInfo } from 'node:net';
import { createServer, type Server, type TLSSocket } from 'node:tls';
import type { PairingConfig } from './config.js';
import { type InboxStore } from './inbox.js';
import { decodeInboxItems, inboxSignedString, SignatureStrikes, verifyInboxSignature, type InboxItem } from './inbox-submit.js';
import { log } from './log.js';
import { Pairing, PAIRING_WIRE_VERSION, wireInstant } from './pairing.js';
import { loadOrCreatePairingIdentity } from './pairing-identity.js';
import { appendPairedPhone, readPairedPhones, type PairedPhone } from './paired-phones.js';
import { lookupRegistryEntry, type RegistryEntry } from './registry.js';

/*
 * The phone-pairing listener: a TLS socket that speaks the four pairing frames and, once a phone is confirmed, the
 * inbox frames (planning/plans/plan-pairing-handshake.md §2.4, planning/plans/plan-phone-inbox.md §1.2). It is not the
 * control API and shares no route with it. Anything other than those frames gets a closed socket, not an answer.
 *
 * One request per connection. A phone sends `pair.request`. A refused request is answered with
 * `pair.refused` and the connection closes. An accepted one is answered with `pair.ok`, and the phone's
 * `pair.ack` for that phoneId writes the confirmed record and closes the connection. A connection that
 * drops first leaves no record, and its held request is released.
 *
 * An inbox exchange has the same shape. A confirmed phone sends `inbox.hello` and is answered with a nonce. It then
 * sends one `inbox.submit`, signed over that nonce. The answer is `inbox.receipt`, sent only once the picks are on
 * disk, or `inbox.refused`. Either way the connection closes.
 *
 * Refusal reasons, the value of `pair.refused.reason`:
 *   badRequest              not JSON, or a field the request needs is missing or the wrong type
 *   frameTooLarge           a header over PAIRING_FRAME_MAX, refused before the body is read
 *   typedEntryUnavailable   entry "typed": nothing is decided and no code is spent (D2)
 *   notRecognised           not the live code, or a burned one
 *   expired                 the live code's window has closed
 *   alreadyUsed             the code was already paired
 *   unsupportedVersion      `v` is not one this router speaks; `found` carries it
 *
 * The inbox refusals are `inbox.refused` with the same field names, and add `unknownPhone`, `badSignature`,
 * `staleNonce` and `tooManyItems` (plan-phone-inbox.md §1.2).
 *
 * A burned code is `notRecognised`, the same as any code that is not live. Naming the third wrong guess
 * would say which guess burned the code and would not change the phone's remedy, which is the same
 * either way: ask the Mac for a new code. `Pairing.submit` is the authority for all of this.
 */
export const PAIRING_FRAME_MAX = 4096;

/** The inbox frames take their own cap: a batch of picks does not fit in 4096 bytes (plan-phone-inbox.md §1.2). */
export const INBOX_FRAME_MAX = 65_536;

/** How long a connection may sit between frames. Long enough for a phone to store what it was just given. */
export const PAIRING_IDLE_MS = 15_000;

/** The most connections the listener holds at once. A connection past this is closed before it is served (plan §7). */
export const PAIRING_CONNECTIONS_MAX = 8;

/** A nonce answers one submit, and only for this long (plan-phone-inbox.md §1.2). */
const INBOX_NONCE_MS = 60_000;

const PHONE_NAME_MAX = 64;

export interface RunningPairingListener {
  port: number;
  /** Connections the listener holds open right now. A refused connection is not counted once it has closed. */
  openConnections(): number;
  close(): Promise<void>;
}

/** What the listener asks an advertiser to announce: the bound port, and the name a phone shows. */
export interface PairingAdvertisementRequest {
  name: string;
  port: number;
  txt: Record<string, string>;
}

/** An announcement that is live until `stop` is awaited. */
export interface PairingAdvertisement {
  stop(): Promise<void>;
}

export type PairingAdvertiser = (request: PairingAdvertisementRequest) => PairingAdvertisement;

export interface PairingListenerDeps {
  /** The router home: where the identity and the paired-phones file live. */
  dir: string;
  /** The router's code state, the same instance the control API issues from. */
  pairing: Pairing;
  /** The name a phone sees. Defaults to this host's name without `.local`. */
  macName?: string;
  idleMs?: number;
  /**
   * Announces the listener on the local network. Omitted, nothing is announced. The router passes the Bonjour
   * one; a test passes a fake, so no multicast is sent from a unit test.
   */
  advertise?: PairingAdvertiser;
  /** Where a phone's inbox submit is held. Omitted, the listener serves pairing frames only and closes an inbox hello. */
  inbox?: InboxStore;
  /** Resolves a submitted pick's id against the router's own registry. Omitted, the live lookup. */
  lookup?: (id: string) => Promise<RegistryEntry | null>;
  /** The clock for nonce expiry, the strike lockout and `receivedAt`. Omitted, `Date.now`. */
  clock?: () => number;
}

/** The decoded `pair.request`. Every field is checked by type and never coerced. */
interface PairRequest {
  v: number;
  code: string;
  phoneName: string;
  phoneKey: string;
  entry: 'scan' | 'typed';
}

/**
 * Start the listener when `pairing.enabled` is set, and return `undefined` otherwise, so the caller
 * never has to ask whether it should bind. Binding only the configured `host` and `port`; the
 * control API is a separate socket on its own address.
 */
export async function startPairing(
  cfg: PairingConfig,
  deps: PairingListenerDeps
): Promise<RunningPairingListener | undefined> {
  if (!cfg.enabled) return undefined;

  const identity = await loadOrCreatePairingIdentity(deps.dir);
  const macName = deps.macName ?? hostname().replace(/\.local$/, '');
  const idleMs = deps.idleMs ?? PAIRING_IDLE_MS;
  const clock = deps.clock ?? Date.now;
  const lookup = deps.lookup ?? lookupRegistryEntry;
  const strikes = new SignatureStrikes(clock);
  const sockets = new Set<TLSSocket>();

  const server: Server = createServer(
    { key: identity.keyPem, cert: identity.certPem, minVersion: 'TLSv1.3' },
    (socket) => {
      // Past the cap a connection is closed before it is served, so a flood holds at most this many (plan §7).
      if (sockets.size >= PAIRING_CONNECTIONS_MAX) {
        socket.destroy();
        return;
      }
      sockets.add(socket);
      socket.once('close', () => sockets.delete(socket));
      serve(socket, { dir: deps.dir, pairing: deps.pairing, macName, idleMs, inbox: deps.inbox, lookup, clock, strikes });
    }
  );

  await new Promise<void>((resolve, reject) => {
    server.once('error', reject);
    server.listen(cfg.port, cfg.host, () => {
      server.removeListener('error', reject);
      resolve();
    });
  });

  const { port } = server.address() as AddressInfo;
  log.info(`pairing listening on ${cfg.host}:${port} (TLS 1.3, certificate ${identity.fingerprint})`);

  // Announced only once the port is bound, so the advertisement names the port a phone can actually reach.
  const advertisement = announce(deps.advertise, { name: macName, port, txt: { name: macName } });

  return {
    port,
    openConnections: () => sockets.size,
    close: async () => {
      // Withdrawn first, so a phone stops seeing a listener that is about to refuse it.
      await withdraw(advertisement);
      await new Promise<void>((resolve) => {
        for (const socket of sockets) socket.destroy();
        server.close(() => resolve());
      });
    },
  };
}

/**
 * Announce the listener, or return nothing. A failed announcement is logged and leaves the listener up: the
 * QR carries the endpoint, so a phone can still pair without discovery (plan §3).
 */
function announce(
  advertise: PairingAdvertiser | undefined,
  request: PairingAdvertisementRequest
): PairingAdvertisement | undefined {
  if (!advertise) return undefined;
  try {
    return advertise(request);
  } catch (err) {
    log.warn(`pairing: not announced on the local network: ${(err as Error).message}`);
    return undefined;
  }
}

async function withdraw(advertisement: PairingAdvertisement | undefined): Promise<void> {
  if (!advertisement) return;
  try {
    await advertisement.stop();
  } catch (err) {
    log.warn(`pairing: announcement could not be withdrawn: ${(err as Error).message}`);
  }
}

interface ServeDeps {
  dir: string;
  pairing: Pairing;
  macName: string;
  idleMs: number;
  inbox?: InboxStore;
  lookup: (id: string) => Promise<RegistryEntry | null>;
  clock: () => number;
  strikes: SignatureStrikes;
}

/** Run one connection: read frames, answer them, and close when the exchange is decided. */
function serve(socket: TLSSocket, deps: ServeDeps): void {
  let buffered = Buffer.alloc(0);
  // 'request' takes a pair.request or an inbox.hello. 'ack' waits for the pair.ack. 'nonce' waits for the inbox.submit.
  let phase: 'request' | 'ack' | 'nonce' = 'request';
  // Which exchange this connection is in. It sets the frame cap and the type a refusal is sent as.
  let channel: 'pair' | 'inbox' = 'pair';
  let pending: { phoneId: string; request: PairRequest } | undefined;
  let issued: { phoneId: string; nonce: string; expiresAt: number } | undefined;
  let finished = false;

  socket.setTimeout(deps.idleMs, () => socket.destroy());
  // A phone that drops mid-exchange is the ordinary end of a failed pairing, not an error to report.
  socket.on('error', () => undefined);
  socket.on('close', () => {
    if (pending) deps.pairing.release(pending.phoneId);
  });
  socket.on('data', (chunk: Buffer) => {
    // Once decided, the phone's bytes are not read. Idle time resets on activity, so reading on would let a
    // client hold a decided connection open by talking. Before that, the buffer holds at most one partial
    // frame, since a header over PAIRING_FRAME_MAX is refused before its body arrives.
    if (finished) return;
    buffered = Buffer.concat([buffered, chunk]);
    drain();
  });

  /** Decide the connection: send any final frame, then destroy the socket once that has flushed. */
  function close(frame?: Buffer): void {
    finished = true;
    buffered = Buffer.alloc(0);
    const destroy = () => socket.destroy();
    if (frame) socket.end(frame, destroy);
    else socket.end(destroy);
  }

  function refuse(reason: string, detail: Record<string, unknown> = {}): void {
    const type = channel === 'inbox' ? 'inbox.refused' : 'pair.refused';
    close(encodeFrame({ type, v: PAIRING_WIRE_VERSION, reason, ...detail }));
  }

  /** Close with nothing said: a frame this exchange does not answer, or a phone that is locked out. */
  function dropSilently(): void {
    finished = true;
    socket.destroy();
  }

  function drain(): void {
    while (!finished && buffered.length >= 4) {
      const len = buffered.readUInt32BE(0);
      if (len > (channel === 'inbox' ? INBOX_FRAME_MAX : PAIRING_FRAME_MAX)) return refuse('frameTooLarge');
      if (buffered.length < 4 + len) return;
      const body = buffered.subarray(4, 4 + len);
      buffered = buffered.subarray(4 + len);
      try {
        handle(body);
      } catch (err) {
        // An unexpected failure ends this connection and nothing else. It must not reach the process.
        log.warn(`pairing: connection ended on an internal error: ${(err as Error).message}`);
        finished = true;
        socket.destroy();
      }
    }
  }

  function handle(body: Buffer): void {
    const message = parseMessage(body);

    if (phase === 'ack') {
      if (
        message?.type !== 'pair.ack' ||
        message.v !== PAIRING_WIRE_VERSION ||
        !pending ||
        message.phoneId !== pending.phoneId
      ) {
        finished = true;
        socket.destroy();
        return;
      }
      appendPairedPhone(deps.dir, {
        phoneId: pending.phoneId,
        phoneName: pending.request.phoneName,
        phoneKey: pending.request.phoneKey,
        pairedAt: wireInstant(new Date()),
      });
      deps.pairing.release(pending.phoneId);
      log.info(`pairing: confirmed a phone (${pending.phoneId})`);
      pending = undefined;
      close();
      return;
    }

    if (phase === 'nonce') return submit(message);

    if (message === undefined) return refuse('badRequest');
    if (message.type === 'inbox.hello') return hello(message);
    // Any frame other than a request is not ours to answer. The connection closes with nothing said.
    if (message.type !== 'pair.request') {
      finished = true;
      socket.destroy();
      return;
    }

    const request = decodeRequest(message);
    if (!request) return refuse('badRequest');
    if (request.entry === 'typed') return refuse('typedEntryUnavailable');

    const decision = deps.pairing.submit(request.code, request.v);
    if (decision !== undefined) {
      const { kind, ...detail } = decision;
      log.info(`pairing: refused a request (${kind})`);
      return refuse(kind, detail);
    }

    const phoneId = randomUUID();
    pending = { phoneId, request };
    deps.pairing.hold(phoneId, request.phoneName);
    phase = 'ack';
    socket.write(encodeFrame({ type: 'pair.ok', v: PAIRING_WIRE_VERSION, macName: deps.macName, phoneId }));
  }

  /**
   * An inbox hello. Only a confirmed phone is given a nonce. The nonce is good for this connection, and for one submit
   * within INBOX_NONCE_MS (plan-phone-inbox.md §1.2).
   */
  function hello(message: Record<string, unknown>): void {
    channel = 'inbox';
    if (!deps.inbox) return dropSilently();
    const { phoneId, v } = message;
    if (typeof phoneId !== 'string' || !Number.isInteger(v)) return refuse('badRequest');
    if (v !== PAIRING_WIRE_VERSION) return refuse('unsupportedVersion', { found: v });
    if (deps.strikes.locked(phoneId)) return dropSilently();
    if (!readPairedPhones(deps.dir).some((p) => p.phoneId === phoneId)) return refuse('unknownPhone');

    issued = { phoneId, nonce: randomBytes(32).toString('base64url'), expiresAt: deps.clock() + INBOX_NONCE_MS };
    phase = 'nonce';
    socket.write(encodeFrame({ type: 'inbox.nonce', v: PAIRING_WIRE_VERSION, nonce: issued.nonce }));
  }

  /**
   * An inbox submit. The nonce is checked first, then the phone and its signature, and only a batch that verifies has
   * its items read. Every refusal here stores nothing (plan-phone-inbox.md §1.4, §7).
   */
  function submit(message: Record<string, unknown> | undefined): void {
    const inbox = deps.inbox;
    if (!inbox) return dropSilently();
    if (message === undefined) return refuse('badRequest');
    if (message.type !== 'inbox.submit') return dropSilently();
    const { v, phoneId, nonce, items, sig } = message;
    if (
      !Number.isInteger(v) ||
      typeof phoneId !== 'string' ||
      typeof nonce !== 'string' ||
      typeof items !== 'string' ||
      typeof sig !== 'string'
    ) {
      return refuse('badRequest');
    }
    if (v !== PAIRING_WIRE_VERSION) return refuse('unsupportedVersion', { found: v });

    // A nonce answers one submit, whatever that submit's fate, so it is spent here.
    const grant = issued;
    issued = undefined;
    if (!grant || nonce !== grant.nonce || deps.clock() > grant.expiresAt) return refuse('staleNonce');
    if (phoneId !== grant.phoneId) return refuse('badRequest');

    const phone = readPairedPhones(deps.dir).find((p) => p.phoneId === phoneId);
    if (!phone) return refuse('unknownPhone');
    if (deps.strikes.locked(phoneId)) return dropSilently();
    if (!verifyInboxSignature(phone.phoneKey, sig, inboxSignedString(nonce, phoneId, items))) {
      deps.strikes.fail(phoneId);
      return refuse('badSignature');
    }
    deps.strikes.pass(phoneId);

    const decoded = decodeInboxItems(items);
    if ('refused' in decoded) return refuse(decoded.refused);

    // The batch is the phone's, verified. Its bytes are not read again while the picks resolve and are held.
    finished = true;
    holdPicks(inbox, phone, decoded.items, deps.lookup, deps.clock)
      .then((received) => {
        // Sent only once every row is on disk. A connection that dropped meanwhile has nobody to tell, and the rows stand.
        if (!socket.destroyed) close(encodeFrame({ type: 'inbox.receipt', v: PAIRING_WIRE_VERSION, received }));
      })
      .catch((err: unknown) => {
        // A store that cannot be written sends no receipt, so the phone sends the same picks again.
        log.warn(`inbox: a submit was not held: ${(err as Error).message}`);
        socket.destroy();
      });
  }
}

/**
 * Holds each pick the phone sent, resolved against the router's own registry (plan-phone-inbox.md §2.2). A pick whose
 * id is already held is not looked up again: its first row stands and it is answered `duplicate` (D11). Returns the
 * state each item is told, in the order the phone sent them.
 */
async function holdPicks(
  inbox: InboxStore,
  phone: PairedPhone,
  items: InboxItem[],
  lookup: (id: string) => Promise<RegistryEntry | null>,
  clock: () => number
): Promise<Array<{ id: string; state: 'waiting' | 'duplicate' }>> {
  const held = new Set(inbox.rows().map((row) => row.id));
  const fresh = [...new Set(items.map((item) => item.id))].filter((id) => !held.has(id));
  const found = await Promise.all(fresh.map(async (id) => [id, await lookup(id)] as const));
  const resolved = new Map<string, RegistryEntry | null>(found);
  const receivedAt = wireInstant(new Date(clock()));
  return items.map((item) => ({
    id: item.id,
    state: inbox.add({
      id: item.id,
      phoneId: phone.phoneId,
      deviceName: phone.phoneName,
      queuedAt: item.queuedAt,
      receivedAt,
      resolved: resolved.get(item.id) ?? null,
    }),
  }));
}

/** A frame of the wire format: four bytes of big-endian length, then UTF-8 JSON. */
function encodeFrame(message: object): Buffer {
  const body = Buffer.from(JSON.stringify(message), 'utf8');
  const head = Buffer.alloc(4);
  head.writeUInt32BE(body.length);
  return Buffer.concat([head, body]);
}

/** A JSON object, or undefined for anything else. */
function parseMessage(body: Buffer): Record<string, unknown> | undefined {
  try {
    const value: unknown = JSON.parse(body.toString('utf8'));
    return typeof value === 'object' && value !== null && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : undefined;
  } catch {
    return undefined;
  }
}

/** A request with every field present and the right type, or undefined. A bad key is refused here, before any code is decided. */
function decodeRequest(m: Record<string, unknown>): PairRequest | undefined {
  const { v, code, phoneName, phoneKey, entry } = m;
  if (!Number.isInteger(v)) return undefined;
  if (typeof code !== 'string') return undefined;
  if (typeof phoneName !== 'string' || phoneName.trim() === '' || phoneName.length > PHONE_NAME_MAX) return undefined;
  if (typeof phoneKey !== 'string' || !isP256PublicKey(phoneKey)) return undefined;
  if (entry !== 'scan' && entry !== 'typed') return undefined;
  return { v: v as number, code, phoneName, phoneKey, entry };
}

/** Whether `b64` is a P-256 public key in SPKI DER. Anything else is not a phone this router can record. */
function isP256PublicKey(b64: string): boolean {
  try {
    const key = createPublicKey({ key: Buffer.from(b64, 'base64'), format: 'der', type: 'spki' });
    return key.asymmetricKeyType === 'ec' && key.asymmetricKeyDetails?.namedCurve === 'prime256v1';
  } catch {
    return false;
  }
}
