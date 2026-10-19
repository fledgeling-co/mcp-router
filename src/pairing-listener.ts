import { createPublicKey, randomUUID } from 'node:crypto';
import { hostname } from 'node:os';
import type { AddressInfo } from 'node:net';
import { createServer, type Server, type TLSSocket } from 'node:tls';
import type { PairingConfig } from './config.js';
import { log } from './log.js';
import { Pairing, PAIRING_WIRE_VERSION, wireInstant } from './pairing.js';
import { loadOrCreatePairingIdentity } from './pairing-identity.js';
import { appendPairedPhone } from './paired-phones.js';

/*
 * The phone-pairing listener: a TLS socket that speaks the four pairing frames and nothing else
 * (planning/plans/plan-pairing-handshake.md §2.4). It is not the control API and shares no route with
 * it. Anything other than a pairing frame gets a closed socket, not an answer.
 *
 * One request per connection. A phone sends `pair.request`. A refused request is answered with
 * `pair.refused` and the connection closes. An accepted one is answered with `pair.ok`, and the phone's
 * `pair.ack` for that phoneId writes the confirmed record and closes the connection. A connection that
 * drops first leaves no record, and its held request is released.
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
 * A burned code is `notRecognised`, the same as any code that is not live. Naming the third wrong guess
 * would say which guess burned the code and would not change the phone's remedy, which is the same
 * either way: ask the Mac for a new code. `Pairing.submit` is the authority for all of this.
 */
export const PAIRING_FRAME_MAX = 4096;

/** How long a connection may sit between frames. Long enough for a phone to store what it was just given. */
export const PAIRING_IDLE_MS = 15_000;

const PHONE_NAME_MAX = 64;

export interface RunningPairingListener {
  port: number;
  /**
   * Whether an announcement is live. False when no advertiser was given, or when announcing failed. The
   * listener is bound either way, because the QR carries the endpoint and discovery is only a convenience.
   */
  advertising: boolean;
  /** Connections the listener holds open right now. A refused connection is not counted once it has closed. */
  openConnections(): number;
  close(): Promise<void>;
}

/**
 * What the control API reports about the phone listener: what is bound, not what the config asked for. A
 * router whose listener did not start reports `enabled: false`, so the sheets never offer a code nothing answers.
 */
export interface PairingListenerStatus {
  enabled: boolean;
  port: number | null;
  advertising: boolean;
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
  const sockets = new Set<TLSSocket>();

  const server: Server = createServer(
    { key: identity.keyPem, cert: identity.certPem, minVersion: 'TLSv1.3' },
    (socket) => {
      sockets.add(socket);
      socket.once('close', () => sockets.delete(socket));
      serve(socket, { dir: deps.dir, pairing: deps.pairing, macName, idleMs });
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
    advertising: advertisement !== undefined,
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
}

/** Run one connection: read frames, answer them, and close when the exchange is decided. */
function serve(socket: TLSSocket, deps: ServeDeps): void {
  let buffered = Buffer.alloc(0);
  let phase: 'request' | 'ack' = 'request';
  let pending: { phoneId: string; request: PairRequest } | undefined;
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
    close(encodeFrame({ type: 'pair.refused', v: PAIRING_WIRE_VERSION, reason, ...detail }));
  }

  function drain(): void {
    while (!finished && buffered.length >= 4) {
      const len = buffered.readUInt32BE(0);
      if (len > PAIRING_FRAME_MAX) return refuse('frameTooLarge');
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

    if (message === undefined) return refuse('badRequest');
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
