/*
 * R21 — what the NODE reference's `POST /servers/:name/approve` does when the manifest write is
 * refused, measured on the running code rather than read off it.
 *
 * WHY THIS LANE EXISTS. R21's acceptance asks for "node's `control.ts` equivalent at parity, or the
 * divergence declared in `surface.tsv`", and `planning/parity/surface.tsv`'s `control-approve-post`
 * row says in its own words that the 200 promotion path is proven Swift-side only. The FAILED-write
 * path was never proven on either side against the other: the Swift half is pinned by
 * `ControlApproveDispatchTests.approveWithARefusingFileSystem`, which drives an in-memory
 * `FileSystem` that is told to refuse, and no lane had ever asked the reference the same question.
 * So "both answer 500" was a reading of two source files, and this makes it a measurement of one of
 * them. The Swift half stays a reading, and this file says so rather than implying otherwise.
 *
 * THE DENIAL IS THE FILESYSTEM'S, NOT A MOCK. `saveManifest` (`src/manifest.ts:136`) writes
 * `${path}.tmp-${process.pid}` and renames it over `path`. This lane creates a DIRECTORY at exactly
 * that temp path before calling, so `writeFileSync` is refused with `EISDIR` by the real filesystem
 * at exactly the step that makes the change durable. The lock sidecar and the manifest read are
 * untouched, which is the point: a denial that also stopped the lock would produce a 500 carrying
 * the LOCK's sentence and prove nothing about the save.
 *
 * ACLs were tried first and abandoned, and the reason is recorded because the next person will try
 * them too. `icacls <file> /deny <user>:(D,WD,AD,WEA,WA)` and `icacls <dir> /deny <user>:(DC)` both
 * apply cleanly — `icacls` reads the DENY ace back — and `renameSync` over the target SUCCEEDS
 * anyway on this machine. An ACL that is set, is readable, and does not bite is worse than no
 * control at all: it produces a green arm that never armed.
 *
 * THREE ARMS, because a recorder that has never said no is an echo:
 *   BASELINE  a writable home. The route must answer 200 and the pending change must be gone
 *             from disk. If this is not green the other two arms are measuring a broken fixture.
 *   EFFECT    the temp path occupied. The route's status and body are recorded verbatim.
 *   SILENCE   the occupation removed, the fixture re-seeded. 200 again, so the EFFECT arm's
 *             refusal is attributable to the denial rather than to anything this lane set up.
 *
 * WHAT IS STUBBED, STATED. `deps.liveReload` and `deps.manifest` are stubs: they are the
 * announcement collaborators the 200 path calls AFTER the write, and standing up a real
 * `LiveReload` and `ManifestStore` would put a socket in a lane about a file. The route, the lock,
 * `loadManifest` and `saveManifest` are the shipped ones out of `dist/`.
 *
 *   node scripts/acceptance/r21-approve-write-denied.mjs
 *
 * Exit 0 all three arms as expected · 1 an arm disagreed · 2 the lane could not run.
 */
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const DIST = join(HERE, '..', '..', 'dist', 'control.js');

if (!existsSync(DIST)) {
  console.error(`no build to measure: ${DIST} is absent. Run \`npx tsc -p tsconfig.json\` first.`);
  console.error('exit: 2  (a lane that could not load its subject has not measured it)');
  process.exit(2);
}

// The home has to be set before `control.js` is imported: `config.js` reads MCP_ROUTER_HOME at
// module scope, and a home pointing at the operator's real router is not a fixture.
const home = mkdtempSync(join(tmpdir(), 'r21-approve-'));
process.env.MCP_ROUTER_HOME = home;
const manifestPath = join(home, 'manifest.json');

const { handleControl } = await import(new URL(`file://${DIST.replace(/\\/g, '/')}`));

const SERVER = 'fixture';
const SEED = JSON.stringify(
  {
    version: 1,
    servers: {
      [SERVER]: {
        tools: [{ name: 'old' }],
        digest: 'd1',
        builtAt: '2020-01-01T00:00:00.000Z',
        pending: { tools: [{ name: 'a' }, { name: 'b' }], digest: 'd2', seenAt: '2020-01-02T00:00:00.000Z' },
      },
    },
  },
  null,
  2
);

function seed() {
  writeFileSync(manifestPath, SEED);
}

/** A `ServerResponse` that records rather than writes. */
function recorder() {
  const seen = { status: 0, body: '' };
  return {
    seen,
    res: {
      writeHead(status) {
        seen.status = status;
        return this;
      },
      end(payload) {
        seen.body = String(payload ?? '');
      },
    },
  };
}

const TOKEN = 'a'.repeat(64);

async function approve() {
  const { seen, res } = recorder();
  const req = {
    method: 'POST',
    headers: { authorization: `Bearer ${TOKEN}`, 'content-type': 'application/json' },
  };
  const deps = {
    cfg: {
      port: 0,
      host: '127.0.0.1',
      idleMs: 1000,
      startupTimeoutMs: 1000,
      upstreams: [],
      manifestPath,
      logPath: join(home, 'router.log'),
      usagePath: join(home, 'usage.jsonl'),
      statsPath: join(home, 'usage-stats.json'),
      authDir: join(home, 'auth'),
    },
    upstreams: new Map([[SERVER, { name: SERVER, transport: 'stdio', command: 'true', args: [] }]]),
    pool: {},
    manifest: { fileStamp: () => 0 },
    usage: {},
    liveReload: { announceToolsChanged: async () => undefined },
  };
  await handleControl(req, res, new URL(`http://127.0.0.1/servers/${SERVER}/approve`), undefined, deps, TOKEN);
  return seen;
}

function onDisk() {
  try {
    return readFileSync(manifestPath, 'utf8');
  } catch (err) {
    return `<unreadable: ${err.code}>`;
  }
}

const results = [];
let failures = 0;

function record(arm, seen, expectation, held) {
  const ok = expectation(seen, held);
  if (!ok) failures += 1;
  results.push({ arm, status: seen.status, body: seen.body, pendingOnDisk: held, ok });
  console.log(`  ${ok ? 'as expected' : 'DISAGREED  '}  ${arm}`);
  console.log(`      status ${seen.status}`);
  console.log(`      body   ${seen.body}`);
  console.log(`      manifest.json still holds "pending": ${held}`);
}

console.log('R21 — the node reference\'s approve route against a refused manifest write');
console.log(`  home ${home}`);
console.log();

// ---------------------------------------------------------------- BASELINE
seed();
record('BASELINE — a writable home', await approve(), (s, held) => s.status === 200 && !held, onDisk().includes('"pending"'));

// ---------------------------------------------------------------- EFFECT
seed();
const wall = `${manifestPath}.tmp-${process.pid}`;
mkdirSync(wall);
record(
  'EFFECT — the save\'s temp path occupied by a directory',
  await approve(),
  (s, held) => s.status !== 200 && held,
  onDisk().includes('"pending"')
);

// ---------------------------------------------------------------- SILENCE
rmSync(wall, { recursive: true });
seed();
record('SILENCE — the occupation removed', await approve(), (s, held) => s.status === 200 && !held, onDisk().includes('"pending"'));

console.log();
const effect = results[1];
console.log('  WHAT THE REFERENCE ANSWERS WHEN THE WRITE IS REFUSED');
console.log(`    status ${effect.status}`);
console.log(`    body   ${effect.body}`);
console.log();
console.log('  AGAINST THE SWIFT PORT, WHICH THIS LANE CANNOT RUN. `swift` and `xcodebuild` are');
console.log('  absent on this machine, so the Swift side below is READ, not measured:');
console.log('    AuthRoutes.swift:171-177 catches the save and returns');
console.log('      (500, {"error": "failed to write manifest: <error.localizedDescription>"})');
console.log('    control.ts:600-603 catches it and returns');
console.log('      (500, {"error": "<err.message>"})');
console.log('    The STATUS agrees. The BODY does not: the port prefixes a sentence of its own.');

rmSync(home, { recursive: true, force: true });

if (failures) {
  console.log();
  console.log(`exit: 1  (${failures} arm(s) disagreed with what this lane expected)`);
  process.exit(1);
}
console.log();
console.log('exit: 0');
