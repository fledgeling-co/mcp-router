import 'reflect-metadata';
import { createHash, createPrivateKey, X509Certificate, webcrypto } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import * as x509 from '@peculiar/x509';

/*
 * The router's TLS identity for the phone-pairing listener (planning/plans/plan-pairing-handshake.md
 * §2.1 and D3, D4).
 *
 * Self-signed, P-256, created once and kept. The phone never checks a CA: it pins the SHA-256 of this
 * certificate's DER, which the QR carries as `fp`. So the name and the validity window are not trust
 * decisions. They exist only so a TLS stack that inspects them does not refuse the certificate outright.
 *
 * Two files under the router home, both 0600, the same storage class as `control.token`.
 */
export const PAIRING_KEY_FILE = 'pairing-key.pem';
export const PAIRING_CERT_FILE = 'pairing-cert.pem';

/** Ten years. The pin is what the phone checks, so a renewal would only change the fingerprint the QR must carry. */
const VALIDITY_MS = 10 * 365 * 24 * 60 * 60 * 1000;

export interface PairingIdentity {
  keyPem: string;
  certPem: string;
  /** Lowercase hex SHA-256 of the certificate's DER: the `fp` a QR carries. */
  fingerprint: string;
}

/** The fingerprint a phone pins, computed from the certificate the router presents. */
export function certificateFingerprint(certPem: string): string {
  return createHash('sha256').update(new X509Certificate(certPem).raw).digest('hex');
}

/** Read the identity under `dir`, or create it on first use. The same identity is returned on every later call. */
export async function loadOrCreatePairingIdentity(dir: string): Promise<PairingIdentity> {
  const keyPath = join(dir, PAIRING_KEY_FILE);
  const certPath = join(dir, PAIRING_CERT_FILE);
  if (existsSync(keyPath) && existsSync(certPath)) {
    const keyPem = readFileSync(keyPath, 'utf8');
    const certPem = readFileSync(certPath, 'utf8');
    return { keyPem, certPem, fingerprint: certificateFingerprint(certPem) };
  }

  const { subtle } = webcrypto;
  const keys = await subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const now = new Date();
  const cert = await x509.X509CertificateGenerator.createSelfSigned({
    name: 'CN=mcp-router pairing',
    notBefore: now,
    notAfter: new Date(now.getTime() + VALIDITY_MS),
    signingAlgorithm: { name: 'ECDSA', hash: 'SHA-256' },
    keys,
    extensions: [
      new x509.BasicConstraintsExtension(false, undefined, true),
      new x509.KeyUsagesExtension(x509.KeyUsageFlags.digitalSignature, true),
      new x509.ExtendedKeyUsageExtension([x509.ExtendedKeyUsage.serverAuth]),
    ],
  });
  const pkcs8 = Buffer.from(await subtle.exportKey('pkcs8', keys.privateKey));
  const keyPem = createPrivateKey({ key: pkcs8, format: 'der', type: 'pkcs8' })
    .export({ format: 'pem', type: 'pkcs8' })
    .toString();
  const certPem = cert.toString('pem');

  mkdirSync(dir, { recursive: true, mode: 0o700 });
  writeFileSync(keyPath, keyPem, { mode: 0o600 });
  writeFileSync(certPath, certPem, { mode: 0o600 });
  return { keyPem, certPem, fingerprint: certificateFingerprint(certPem) };
}
