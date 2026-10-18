import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { type StdioUpstream } from '../src/config.js';
import { UpstreamPool } from '../src/pool.js';

/** A stdio upstream that runs `/bin/sh -c <script>`: a real command that exists and runs. */
function shell(name: string, script: string, startupTimeoutMs?: number): StdioUpstream {
  return {
    transport: 'stdio',
    name,
    command: '/bin/sh',
    args: ['-c', script],
    env: {},
    envFiles: [],
    startupTimeoutMs,
  };
}

/** Opens one upstream through a pool with the default budget, and returns the failure's text. */
async function openFailure(u: StdioUpstream, budgetMs: number): Promise<{ message: string; elapsedMs: number }> {
  const pool = new UpstreamPool(new Map([[u.name, u]]), 60_000, budgetMs);
  const started = Date.now();
  try {
    await pool.acquire(u.name);
  } catch (err) {
    return { message: (err as Error).message, elapsedMs: Date.now() - started };
  }
  assert.fail(`${u.name} must not open as an upstream`);
}

describe('a stdio child that ends before it initializes', () => {
  test('fails at once and names its exit status', async () => {
    const { message, elapsedMs } = await openFailure(shell('dies', 'exit 17'), 5000);
    assert.equal(message, 'upstream "dies" exited with status 17 before initializing');
    assert.ok(elapsedMs < 2000, `the failure took ${elapsedMs}ms; the child had already exited`);
  });

  test('names the signal when a signal ends it', async () => {
    const { message, elapsedMs } = await openFailure(shell('killed', 'kill -9 $$'), 5000);
    assert.equal(message, 'upstream "killed" exited on signal 9 before initializing');
    assert.ok(elapsedMs < 2000, `the failure took ${elapsedMs}ms; the child had already exited`);
  });

  test('a child that is alive but silent keeps the timeout message', async () => {
    const { message, elapsedMs } = await openFailure(shell('slow', 'sleep 30', 300), 60_000);
    assert.equal(message, 'upstream "slow" did not initialize within 300ms');
    assert.ok(elapsedMs < 5000, `the timeout took ${elapsedMs}ms against a 300ms budget`);
  });
});
