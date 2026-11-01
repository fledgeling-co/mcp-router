import { createHash } from 'node:crypto';
import { readFileSync, realpathSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const MODULES = ['index.js', 'config.js', 'control.js', 'pool.js', 'credentials.js', 'credential-runtime.js'];
export interface CredentialRuntimeReceipt {
  supported: true;
  scheme: 'warden';
  pid: number;
  runtimeRoot: string;
  configPath: string;
  configSha256: string;
  entrypoint: string;
  modules: Record<string, string>;
}

/** Captured once when the daemon imports its control handler, never reconstructed per request. */
function snapshot(): Omit<CredentialRuntimeReceipt, 'configPath' | 'configSha256'> | null {
  try {
    const directory = realpathSync(dirname(fileURLToPath(import.meta.url)));
    return { supported: true, scheme: 'warden', pid: process.pid,
      runtimeRoot: realpathSync(join(directory, '..')),
      entrypoint: realpathSync(process.argv[1]),
      modules: Object.fromEntries(MODULES.map(name => [name,
        createHash('sha256').update(readFileSync(join(directory, name))).digest('hex')])) };
  } catch { return null; }
}
const STARTUP = snapshot();

export function credentialRuntimeReceipt(configPath: string, configSha256?: string): CredentialRuntimeReceipt | null {
  if (!STARTUP || !configSha256) return null;
  return { ...STARTUP, configPath, configSha256 };
}

/** A new dist folder is not evidence that the serving process loaded its modules. */
export function runtimeReceiptMatches(value: unknown, runtimeRoot: string, configPath: string): boolean {
  try {
    const receipt = value as CredentialRuntimeReceipt;
    const root = realpathSync(runtimeRoot);
    return receipt?.supported === true && receipt.scheme === 'warden' && Number.isSafeInteger(receipt.pid) &&
      receipt.pid > 0 && receipt.runtimeRoot === root && receipt.configPath === realpathSync(configPath) &&
      receipt.configSha256 === createHash('sha256').update(readFileSync(configPath)).digest('hex') &&
      receipt.entrypoint === realpathSync(join(root, 'dist', 'index.js')) &&
      MODULES.every(name => receipt.modules?.[name] ===
        createHash('sha256').update(readFileSync(join(root, 'dist', name))).digest('hex'));
  } catch { return false; }
}
