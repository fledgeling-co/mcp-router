import { verifyWardenRuntime } from './credentials.js';
try {
  await verifyWardenRuntime();
  process.stdout.write(JSON.stringify({ supported: true, scheme: 'warden', trusted: true }) + '\n');
} catch {
  process.stdout.write(JSON.stringify({ supported: true, scheme: 'warden', trusted: false,
    reason: 'Installed Warden must pass Gatekeeper and its pinned Developer ID identity before migration' }) + '\n');
  process.exitCode = 1;
}
