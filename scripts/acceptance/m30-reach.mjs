/*
 * How much of this machine the document route can actually serve.
 *
 * M30's route reads a package out of an upstream's declared `cwd`, and `spec-M30.md` §1 refuses to
 * derive that root from anything else. That is a decision about a trust boundary, and its cost is a
 * number rather than an argument: how many of the servers a developer really has can the route
 * answer for today. This measures that number against the live config instead of reasoning about
 * it.
 *
 * It applies the route's own guard, byte-for-byte from `src/control.ts`:
 *
 *     if (!isStdio(u) || !u.cwd) -> 404 noPackageDirectory
 *
 * so a change to the route that this probe does not follow shows up as a disagreement rather than
 * as a quietly stale figure. Nothing is started and nothing is written: it reads the config and the
 * directories the config names, which is exactly what a GET on the route would have read.
 *
 *     node scripts/acceptance/m30-reach.mjs > planning/evidence/M30-reach.txt
 *
 * Needs a built `dist/` (`npm run build`). Reads `~/.claude/mcp-router/servers.json` unless
 * `MCP_ROUTER_HOME` moves it, which is the same file the running router reads.
 */
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const dist = resolve(here, '../../dist');

const { loadConfig, isStdio, DEFAULT_CONFIG_PATH } = await import(`${dist}/config.js`);
const { readPackageDocuments, isRefusal } = await import(`${dist}/document.js`);

const cfg = loadConfig({ configPath: DEFAULT_CONFIG_PATH });
const ups = cfg.config.upstreams;
console.log('measured  :', new Date().toISOString());
console.log('config    :', DEFAULT_CONFIG_PATH);
console.log('upstreams :', ups.length);
console.log('');

const rows = [];
for (const u of (ups.values ? ups.values() : ups)) {
  // The route's own guard, byte-for-byte from `src/control.ts`.
  if (!isStdio(u) || !u.cwd) {
    rows.push([u.name, u.transport, '404 noPackageDirectory', isStdio(u) ? 'stdio, no cwd declared' : 'not stdio']);
    continue;
  }
  const outcome = readPackageDocuments(u.cwd);
  if (isRefusal(outcome)) rows.push([u.name, u.transport, `${outcome.status} ${outcome.reason}`, u.cwd]);
  else rows.push([u.name, u.transport, '200 served', `${outcome.documents.map((d) => d.tab).join('+')}`]);
}

for (const r of rows) console.log(r[0].padEnd(16), r[1].padEnd(7), r[2].padEnd(24), r[3]);
const served = rows.filter((r) => r[2].startsWith('200'));
console.log('');
console.log(`SERVED ${served.length} of ${rows.length}`);
const byReason = {};
for (const r of rows) byReason[r[2]] = (byReason[r[2]] ?? 0) + 1;
console.log('outcomes:', JSON.stringify(byReason));
