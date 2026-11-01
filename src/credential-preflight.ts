import { execFile } from 'node:child_process';
import { readFileSync, realpathSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { verifyWardenRuntime } from './credentials.js';
import { runtimeReceiptMatches, type CredentialRuntimeReceipt } from './credential-runtime.js';
import { DEFAULT_CONFIG_PATH } from './config.js';

try {
  await verifyWardenRuntime();
  const configFlag = process.argv.indexOf('--config');
  const config = realpathSync(configFlag < 0 ? DEFAULT_CONFIG_PATH : process.argv[configFlag + 1]);
  const port = JSON.parse(readFileSync(config, 'utf8')).port ?? 8879;
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('bad port');
  const token = readFileSync(join(dirname(config), 'control.token'), 'utf8').trim();
  const response = await fetch(`http://127.0.0.1:${port}/runtime/credentials`, {
    headers: { 'x-mcpr-token': token }, signal: AbortSignal.timeout(5000), redirect: 'error',
  });
  if (!response.ok || !response.body) throw new Error('runtime not attested');
  const chunks: Uint8Array[] = [];
  let bytes = 0;
  for await (const chunk of response.body) {
    bytes += chunk.byteLength;
    if (bytes > 65536) throw new Error('oversized receipt');
    chunks.push(chunk);
  }
  const receipt: CredentialRuntimeReceipt = JSON.parse(Buffer.concat(chunks).toString('utf8'));
  const root = realpathSync(join(dirname(fileURLToPath(import.meta.url)), '..'));
  if (!runtimeReceiptMatches(receipt, root, config)) throw new Error('runtime differs');
  const listeners = await promisify(execFile)('/usr/sbin/lsof',
    ['-nP', '-t', `-iTCP:${port}`, '-sTCP:LISTEN'], { timeout: 5000, maxBuffer: 65536 });
  const pids = new Set(listeners.stdout.trim().split(/\s+/).map(Number));
  if (!pids.has(receipt.pid)) throw new Error('receipt not from listener');
  process.stdout.write(JSON.stringify({ supported: true, scheme: 'warden', trusted: true }) + '\n');
} catch {
  process.stdout.write(JSON.stringify({ supported: true, scheme: 'warden', trusted: false,
    reason: 'Migration requires trusted Warden and a token-authenticated running router matching this runtime and configuration' }) + '\n');
  process.exitCode = 1;
}
