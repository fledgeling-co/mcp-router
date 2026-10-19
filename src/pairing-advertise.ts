import Bonjour from 'bonjour-service';
import type { PairingAdvertisement, PairingAdvertiser } from './pairing-listener.js';

/*
 * The mDNS advertisement of the phone-pairing listener (planning/plans/plan-pairing-handshake.md §3).
 *
 * The listener asks for an advertisement once it has bound, and withdraws it when it closes. The Bonjour
 * package is the only thing in this file that touches multicast; everything else takes the responder as a
 * seam, so a test can say what was published without sending a packet.
 */

/** The service a phone browses for. Advertised as `_mcprouter-pair._tcp`, which is what §3 names. */
export const PAIRING_SERVICE_TYPE = 'mcprouter-pair';

/** How long a withdrawal waits for the responder to report its socket closed before it resolves regardless. */
const WITHDRAW_BOUND_MS = 1_000;

/** The part of `bonjour-service` the advertisement uses. The package's own `Bonjour` class satisfies it. */
export interface BonjourResponder {
  publish(config: {
    name: string;
    type: string;
    protocol: 'tcp';
    port: number;
    txt: Record<string, string>;
  }): unknown;
  unpublishAll(callback: () => void): void;
  destroy(callback: () => void): void;
}

/**
 * An advertiser that publishes through a Bonjour responder. Each advertisement gets its own responder, so
 * stopping one cannot take down another, and the responder's socket is released on stop rather than left
 * bound for the life of the process.
 */
export function createBonjourAdvertiser(
  makeResponder: () => BonjourResponder = () => new Bonjour()
): PairingAdvertiser {
  return (request) => {
    const responder = makeResponder();
    responder.publish({
      name: request.name,
      type: PAIRING_SERVICE_TYPE,
      protocol: 'tcp',
      port: request.port,
      txt: request.txt
    });
    return {
      stop: () =>
        new Promise<void>((resolve) => {
          // Withdraw with goodbye packets, then release the socket. The bound keeps a stuck responder from
          // holding up a shutdown.
          const timer = setTimeout(resolve, WITHDRAW_BOUND_MS);
          responder.unpublishAll(() =>
            responder.destroy(() => {
              clearTimeout(timer);
              resolve();
            })
          );
        })
    } satisfies PairingAdvertisement;
  };
}
