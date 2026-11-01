import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { InboxStore } from '../src/inbox.js';

test('separate inbox writers retain every receipted pick and desktop decision', async () => {
  const home = mkdtempSync(join(tmpdir(), 'inbox-concurrent-'));
  const file = join(home, 'inbox.json');
  const moduleURL = new URL('../src/inbox.js', import.meta.url).href;
  const worker = `
    const { InboxStore } = await import(process.argv[1]);
    const store = new InboxStore(process.argv[2]);
    const writer = process.argv[3];
    for (let n = 0; n < 40; n++) {
      const id = writer + '-' + n;
      if (store.add({ id, phoneId: writer, deviceName: writer, queuedAt: '2026-11-02T00:00:00Z', receivedAt: '2026-11-02T00:00:00Z', resolved: null }) !== 'waiting') throw new Error('pick not stored');
      if (n % 2 === 0 && !store.setState(id, 'declined')) throw new Error('decision not stored');
    }
  `;
  try {
    await Promise.all(Array.from({ length: 4 }, (_, n) => new Promise<void>((resolve, reject) => {
      const child = spawn(process.execPath, ['--input-type=module', '-e', worker, moduleURL, file, `writer${n}`], { stdio: ['ignore', 'ignore', 'pipe'] });
      let error = '';
      child.stderr.on('data', chunk => { error += chunk.toString(); });
      child.on('error', reject);
      child.on('close', code => code === 0 ? resolve() : reject(new Error(`writer failed: ${error}`)));
    })));
    const rows = new InboxStore(file).rows();
    assert.equal(rows.length, 160);
    assert.equal(new Set(rows.map(row => row.id)).size, 160);
    for (let writer = 0; writer < 4; writer++) {
      for (let n = 0; n < 40; n++) {
        const row = rows.find(item => item.id === `writer${writer}-${n}`);
        assert.ok(row, 'a stored pick was lost');
        assert.equal(row.state, n % 2 === 0 ? 'declined' : 'waiting');
      }
    }
  } finally {
    rmSync(home, { recursive: true, force: true });
  }
});
