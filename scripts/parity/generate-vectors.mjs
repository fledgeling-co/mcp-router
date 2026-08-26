// Generates the differential parity vectors from the TypeScript router itself.
//
// The point of generating rather than writing them: a hand-typed expectation records what the
// author *believed* the reference does. Two out-of-family reviews of this item's spec found
// several places that belief was wrong — the reference accepts `servers: []`, treats a default
// URL port as empty, and destroys a server's approved tools on an indexing failure. Only the
// implementation is authoritative about the implementation.
//
//   node scripts/parity/generate-vectors.mjs
//
// Requires `npm run build` first: it drives `dist/*.js`. The vectors are committed; `dist/` is not.

import { writeFileSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { writeDocumentVectors } from './generate-document-vectors.mjs';

const require = createRequire(import.meta.url);
const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, '..', '..');
// A git worktree carries no `dist/` or `node_modules/` of its own — both are ignored — so the
// reference can be driven from the main checkout while the vectors are written into the branch.
const distDir = process.env.MCP_ROUTER_DIST ?? join(repoRoot, 'dist');
const outDir = process.env.MCP_ROUTER_VECTORS ?? join(repoRoot, 'app', 'Tests', 'RouterCoreTests', 'Vectors');
mkdirSync(outDir, { recursive: true });

const write = (name, payload) => {
  writeFileSync(join(outDir, `${name}.json`), JSON.stringify(payload, null, 2) + '\n');
  console.log(`${name}: ${payload.cases.length} cases`);
};

// ---------------------------------------------------------------- JSON layer
//
// Every case is a JSON *document*. Swift parses it and re-serialises; the expectation is what
// `JSON.stringify(JSON.parse(text))` produces, which is exactly the operation the router performs
// when it re-writes a manifest or hashes a tool schema.
const jsonDocuments = [
  // Ordinary shapes.
  { id: 'empty-object', text: '{}' },
  { id: 'empty-array', text: '[]' },
  { id: 'nested-schema', text: '{"type":"object","properties":{"b":{"type":"string"},"a":{"type":"number"}},"required":["b","a"]}' },
  { id: 'scalars', text: '[null,true,false,"x"]' },

  // N7 — schema member order is significant, so these two must differ.
  { id: 'member-order-za', text: '{"z":0,"a":1}' },
  { id: 'member-order-az', text: '{"a":1,"z":0}' },

  // Duplicate keys: last value wins, at the first key's position.
  { id: 'duplicate-keys', text: '{"b":1,"a":2,"b":3}' },
  { id: 'duplicate-keys-escaped', text: '{"a":1,"\\u0061":2,"b":3}' },

  // JavaScript property enumeration order: array-index keys first, ascending.
  { id: 'index-keys', text: '{"10":"a","2":"b","a":"c","0":"d"}' },
  { id: 'index-key-boundaries', text: '{"4294967295":"x","01":"y","-0":"z","4294967294":"w","0":"v"}' },

  // Strings Swift's `String` cannot hold, or holds wrongly.
  { id: 'lone-high-surrogate', text: '"\\ud800"' },
  { id: 'lone-low-surrogate', text: '"\\udc00"' },
  { id: 'surrogate-pair', text: '"\\ud83d\\ude00"' },
  { id: 'reversed-surrogates', text: '"\\ude00\\ud83d"' },
  // Canonically equivalent, and two distinct keys in JavaScript.
  { id: 'canonical-equivalence', text: '{"\\u00e9":1,"e\\u0301":2}' },

  // Escaping.
  { id: 'control-characters', text: '"\\u0000\\u0008\\u0009\\u000a\\u000b\\u000c\\u000d\\u001f"' },
  { id: 'quote-and-backslash', text: '"he said \\"hi\\" \\\\ done"' },
  { id: 'solidus-stays-raw', text: '"a\\/b"' },
  { id: 'line-separators-stay-raw', text: '"a\\u2028b\\u2029c"' },
  { id: 'non-ascii-raw', text: '"naïve — 日本語"' },

  // Numbers.
  { id: 'number-zero', text: '[0,-0]' },
  { id: 'number-integers', text: '[1,100,1e20]' },
  { id: 'number-exponent-boundary', text: '[1e21,1e-6,1e-7]' },
  { id: 'number-precision-loss', text: '[9007199254740993,1000000000000000128]' },
  { id: 'number-tie-break', text: '[1424953923781206.25]' },
  { id: 'number-overflow-to-null', text: '[1e400,-1e400]' },
  { id: 'number-extremes', text: '[5e-324,1.7976931348623157e308]' },
  { id: 'number-spelling-discarded', text: '[1.2300e+2]' },

  // `__proto__` is an ordinary key when it arrives via JSON.parse.
  { id: 'proto-key', text: '{"__proto__":{"p":1},"x":2}' }
];

write('json-roundtrip', {
  description:
    'JSON.parse then JSON.stringify. `compact` is the digest form; `pretty` is the manifest form.',
  cases: jsonDocuments.map(({ id, text }) => {
    const value = JSON.parse(text);
    return {
      id,
      text,
      compact: JSON.stringify(value),
      pretty: JSON.stringify(value, null, 2)
    };
  })
});

// ---------------------------------------------------------------- string ordering (N1)
//
// The comparator the reference sorts env and header keys with. UTF-16 code-unit order, which
// disagrees with Unicode scalar order exactly where a supplementary character meets a private-use
// one.
const orderingGroups = [
  ['b', 'a', 'c'],
  ['B', 'a'],
  ['\u{1F600}', ''],
  ['', '\u{1F600}'],
  ['é', 'é'],
  ['', 'a'],
  ['a', 'ab']
];

write('string-ordering', {
  description: 'Array.prototype.sort with (a<b?-1:a>b?1:0) — the reference comparator.',
  cases: orderingGroups.map((input, index) => ({
    id: `ordering-${index}`,
    input,
    sorted: [...input].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))
  }))
});

console.log(`\nwrote vectors to ${outDir}`);

// ---------------------------------------------------------------- config layer
//
// From here on the reference itself is driven, so these vectors record what `src/config.ts`
// does rather than what anyone believes it does.
const config = require(join(distDir, 'config.js'));

// Every field of the returned upstream, not just the accept/reject decision — a port that
// reproduces the decisions and drops `projects` or `placard` changes routing while passing a
// decision-only check.
const projectUpstream = (u) => ({
  transport: u.transport,
  name: u.name,
  command: u.command ?? null,
  args: u.args ?? null,
  env: u.env ?? null,
  cwd: u.cwd ?? null,
  url: u.url ?? null,
  headers: u.headers ?? null,
  oauth: u.oauth ?? null,
  idleMs: u.idleMs ?? null,
  startupTimeoutMs: u.startupTimeoutMs ?? null,
  projects: u.projects ?? null,
  warm: u.warm ?? null,
  placard: u.placard ?? null,
  disabled: u.disabled ?? null
});

const serverCases = [
  // Rejections, one per path.
  { id: 'name-bad-charset', name: 'has space', raw: { command: 'x' } },
  { id: 'name-dot', name: 'a.b', raw: { command: 'x' } },
  { id: 'name-empty', name: '', raw: { command: 'x' } },
  { id: 'name-namespace-separator', name: 'foo__bar', raw: { command: 'x' } },
  { id: 'stdio-no-command', name: 'a', raw: {} },
  { id: 'stdio-empty-command', name: 'a', raw: { command: '' } },
  { id: 'http-no-url', name: 'a', raw: { type: 'http' } },
  { id: 'sse-no-url', name: 'a', raw: { type: 'sse' } },
  { id: 'bad-url', name: 'a', raw: { type: 'http', url: 'not a url' } },
  { id: 'unsupported-transport', name: 'a', raw: { type: 'websocket', url: 'http://x' } },

  // Transport selection, including the awkward cases.
  { id: 'stdio-implicit', name: 'a', raw: { command: 'uvx', args: ['docker-mcp'] } },
  { id: 'http-implicit-from-url', name: 'a', raw: { url: 'https://example.com/mcp' } },
  { id: 'stdio-from-empty-url', name: 'a', raw: { url: '', command: 'x' } },
  { id: 'sse-stays-sse', name: 'a', raw: { type: 'sse', url: 'https://example.com/sse' } },
  { id: 'streamable-http-becomes-http', name: 'a', raw: { type: 'streamable-http', url: 'https://e.com' } },
  { id: 'url-ftp-scheme-accepted', name: 'a', raw: { type: 'http', url: 'ftp://host' } },
  { id: 'command-whitespace-accepted', name: 'a', raw: { command: '   ' } },

  // Whole-value fidelity.
  { id: 'stdio-full', name: 'a', raw: {
    command: 'node', args: ['s.js', '--flag'], env: { B: '2', A: '1' }, cwd: '/tmp',
    idleMs: 1000, startupTimeoutMs: 2000, projects: ['/a/b'], warm: true,
    placard: { reason: 'broken', substitute: 'other', until: '2026-01-01' } } },
  { id: 'http-full', name: 'a', raw: {
    type: 'http', url: 'https://e.com', headers: { Z: 'z', A: 'a' }, oauth: false,
    idleMs: 5, projects: [], warm: false } },
  { id: 'stdio-defaults-empty-collections', name: 'a', raw: { command: 'x' } },
  { id: 'http-defaults-empty-headers', name: 'a', raw: { type: 'http', url: 'http://x' } },
  { id: 'unknown-fields-ignored', name: 'a', raw: { command: 'x', nonsense: 1, alsoNonsense: { q: 2 } } },

  // M29 — `disabled` reaches the upstream from both transport branches, and reaches it as
  // written. `parseServer` copies the raw value rather than coercing it, which is why
  // `describe()` reports `!!u.disabled` instead of reading the typed field.
  { id: 'stdio-disabled', name: 'a', raw: { command: 'x', disabled: true } },
  { id: 'http-disabled', name: 'a', raw: { type: 'http', url: 'https://e.com', disabled: true } },
  { id: 'disabled-false-is-carried', name: 'a', raw: { command: 'x', disabled: false } },
  { id: 'disabled-truthy-string-uncoerced', name: 'a', raw: { command: 'x', disabled: 'yes' } }
];

write('parse-server', {
  description: 'parseServer(name, raw) — the whole returned value, not only the decision.',
  cases: serverCases.map(({ id, name, raw }) => {
    const parsed = config.parseServer(name, raw);
    return {
      id,
      name,
      raw,
      reason: 'reason' in parsed ? parsed.reason : null,
      upstream: 'upstream' in parsed ? projectUpstream(parsed.upstream) : null,
      hash: 'upstream' in parsed ? config.upstreamHash(parsed.upstream) : null
    };
  })
});

// upstreamHash — the adversarial set. Named vectors for N1 and N2, plus the exclusion rule.
const hashCases = [
  { id: 'stdio-basic', u: { transport: 'stdio', name: 'a', command: 'uvx', args: ['docker-mcp'], env: {} } },
  { id: 'env-value-changes-hash', u: { transport: 'stdio', name: 'a', command: 'x', args: [], env: { MODE: 'one' } } },
  { id: 'env-value-changed', u: { transport: 'stdio', name: 'a', command: 'x', args: [], env: { MODE: 'two' } } },
  { id: 'env-key-order-irrelevant-a', u: { transport: 'stdio', name: 'a', command: 'x', args: [], env: { A: '1', B: '2' } } },
  { id: 'env-key-order-irrelevant-b', u: { transport: 'stdio', name: 'a', command: 'x', args: [], env: { B: '2', A: '1' } } },
  // N1 — UTF-16 code-unit ordering. Sorting these by Unicode scalar inverts them.
  { id: 'env-utf16-ordering', u: { transport: 'stdio', name: 'a', command: 'x', args: [], env: { '\u{1F600}': 'emoji', '\uE000': 'private' } } },
  // N2 — argument order is significant and must never be sorted.
  { id: 'args-order-za', u: { transport: 'stdio', name: 'a', command: 'x', args: ['z', 'a'], env: {} } },
  { id: 'args-order-az', u: { transport: 'stdio', name: 'a', command: 'x', args: ['a', 'z'], env: {} } },
  { id: 'cwd-absent', u: { transport: 'stdio', name: 'a', command: 'x', args: [], env: {} } },
  { id: 'cwd-present', u: { transport: 'stdio', name: 'a', command: 'x', args: [], env: {}, cwd: '/tmp' } },
  // The exclusion rule: none of these may change the hash.
  { id: 'excluded-name', u: { transport: 'stdio', name: 'different', command: 'x', args: [], env: {} } },
  { id: 'excluded-warm', u: { transport: 'stdio', name: 'a', command: 'x', args: [], env: {}, warm: true } },
  { id: 'excluded-idle', u: { transport: 'stdio', name: 'a', command: 'x', args: [], env: {}, idleMs: 99 } },
  { id: 'excluded-projects', u: { transport: 'stdio', name: 'a', command: 'x', args: [], env: {}, projects: ['/x'] } },
  { id: 'excluded-placard', u: { transport: 'stdio', name: 'a', command: 'x', args: [], env: {}, placard: { reason: 'r' } } },
  // M29 — the fourth member of the family. Disabling must not move the digest, or the toggle
  // invalidates the cache and re-indexing re-spawns the process the user just switched off.
  { id: 'excluded-disabled', u: { transport: 'stdio', name: 'a', command: 'x', args: [], env: {}, disabled: true } },
  // http and sse must differ even with an identical url.
  { id: 'http-transport', u: { transport: 'http', name: 'a', url: 'https://e.com', headers: {} } },
  { id: 'sse-transport', u: { transport: 'sse', name: 'a', url: 'https://e.com', headers: {} } },
  { id: 'header-utf16-ordering', u: { transport: 'http', name: 'a', url: 'https://e.com', headers: { '\u{1F600}': 'e', '\uE000': 'p' } } },
  { id: 'excluded-oauth', u: { transport: 'http', name: 'a', url: 'https://e.com', headers: {}, oauth: true } }
];

write('upstream-hash', {
  description: 'upstreamHash(upstream) — sha256 over JSON.stringify of the material, sliced to 16.',
  cases: hashCases.map(({ id, u }) => ({ id, upstream: u, hash: config.upstreamHash(u) }))
});

// isSelfReference — including the default-port trap (N9).
const selfCases = [
  { id: 'by-name-mcp-router', name: 'mcp-router', raw: {}, port: 8879 },
  { id: 'by-name-router', name: 'router', raw: {}, port: 8879 },
  { id: 'name-case-sensitive', name: 'MCP-Router', raw: {}, port: 8879 },
  { id: 'loopback-matching-port', name: 'x', raw: { url: 'http://127.0.0.1:8879/mcp' }, port: 8879 },
  { id: 'localhost-matching-port', name: 'x', raw: { url: 'http://localhost:8879/mcp' }, port: 8879 },
  { id: 'ipv6-matching-port', name: 'x', raw: { url: 'http://[::1]:8879/mcp' }, port: 8879 },
  { id: 'loopback-other-port', name: 'x', raw: { url: 'http://127.0.0.1:9999/mcp' }, port: 8879 },
  { id: 'default-port-80', name: 'x', raw: { url: 'http://localhost:80' }, port: 80 },
  { id: 'default-port-443', name: 'x', raw: { url: 'https://localhost:443' }, port: 443 },
  { id: 'not-loopback-127-0-0-2', name: 'x', raw: { url: 'http://127.0.0.2:8879' }, port: 8879 },
  { id: 'not-loopback-any-address', name: 'x', raw: { url: 'http://0.0.0.0:8879' }, port: 8879 },
  { id: 'not-loopback-hostname', name: 'x', raw: { url: 'http://mcp-router.example:8879' }, port: 8879 },
  { id: 'no-url', name: 'x', raw: { command: 'y' }, port: 8879 },
  { id: 'unparseable-url', name: 'x', raw: { url: 'not a url' }, port: 8879 }
];

write('self-reference', {
  description: 'isSelfReference(name, raw, port).',
  cases: selfCases.map(({ id, name, raw, port }) => ({
    id, name, raw, port, result: config.isSelfReference(name, raw, port)
  }))
});

// The URL reader, compared against `new URL()` directly — this is what decides both the
// parseability rejection and the self-reference port comparison.
const urlCases = [
  'http://localhost:8879/mcp', 'http://localhost:80', 'https://localhost:443',
  'https://example.com', 'ftp://host', 'mailto:a@b', 'file:///tmp/x',
  'http://[::1]:8879', 'http://user:pass@host:1234/p', 'http://HOST.example',
  'not a url', 'http://', '//host', 'http:/example.com', 'x://y', '1http://y',
  'http://host:0', 'http://host:00080'
];

write('url-parse', {
  description: 'new URL(input) — parseability, hostname, and the port AS REPORTED.',
  cases: urlCases.map((input, index) => {
    try {
      const u = new URL(input);
      return { id: `url-${index}`, input, ok: true, hostname: u.hostname, port: u.port };
    } catch {
      return { id: `url-${index}`, input, ok: false, hostname: null, port: null };
    }
  })
});

console.log(`\nwrote config vectors to ${outDir}`);

// ---------------------------------------------------------------- manifest layer
//
// From here the reference's own manifest module is driven. Two things are stubbed so the output is
// deterministic: the clock, because `buildManifest` stamps `builtAt`/`seenAt` with `new Date()`,
// and the pool, because spawning a real upstream belongs to the next item. Everything else is the
// reference running.
const manifest = require(join(distDir, 'manifest.js'));

const FIXED_MS = 1755100000123; // 2025-08-13T15:46:40.123Z — chosen to exercise a non-zero ms field.

/**
 * Runs `body` with `new Date()` frozen, so `builtAt` and `seenAt` are reproducible.
 *
 * Async, and it awaits *inside* the try: `buildManifest` returns a promise and stamps its
 * timestamps after the first await point, so a synchronous wrapper would restore the real clock
 * before the code being frozen ever read it.
 */
async function atFixedTime(body) {
  const RealDate = globalThis.Date;
  class FrozenDate extends RealDate {
    constructor(...args) {
      if (args.length === 0) super(FIXED_MS);
      else super(...args);
    }
    static now() { return FIXED_MS; }
  }
  globalThis.Date = FrozenDate;
  try { return await body(); } finally { globalThis.Date = RealDate; }
}

// toolsDigest — the material rule, the stable sort, and schema member order.
const digestCases = [
  { id: 'empty', tools: [] },
  { id: 'single', tools: [{ name: 'a', description: 'does a', inputSchema: { type: 'object' } }] },
  // N6 — two tools with the SAME name keep arrival order, so reversing them changes the digest.
  { id: 'duplicate-names-ab', tools: [{ name: 'x', description: 'first' }, { name: 'x', description: 'second' }] },
  { id: 'duplicate-names-ba', tools: [{ name: 'x', description: 'second' }, { name: 'x', description: 'first' }] },
  // N7 — schema member order is significant.
  { id: 'schema-order-za', tools: [{ name: 'a', inputSchema: { z: 0, a: 1 } }] },
  { id: 'schema-order-az', tools: [{ name: 'a', inputSchema: { a: 1, z: 0 } }] },
  // Sorting by name only: these two must produce the same digest.
  { id: 'sorted-by-name-ab', tools: [{ name: 'a', description: 'A' }, { name: 'b', description: 'B' }] },
  { id: 'sorted-by-name-ba', tools: [{ name: 'b', description: 'B' }, { name: 'a', description: 'A' }] },
  // Every other member is ignored — same digest as `single`.
  { id: 'other-members-ignored', tools: [{ name: 'a', description: 'does a', inputSchema: { type: 'object' }, title: 'T', annotations: { readOnlyHint: true }, outputSchema: { type: 'string' } }] },
  // Nullish coalescing: absent and null are alike, and both differ from an empty string only where
  // the reference says they do.
  { id: 'nullish-description', tools: [{ name: 'a' }] },
  { id: 'null-description', tools: [{ name: 'a', description: null }] },
  { id: 'empty-description', tools: [{ name: 'a', description: '' }] },
  { id: 'nullish-schema', tools: [{ name: 'a', description: 'd' }] },
  { id: 'null-schema', tools: [{ name: 'a', description: 'd', inputSchema: null }] },
  { id: 'empty-object-schema', tools: [{ name: 'a', description: 'd', inputSchema: {} }] },
  // UTF-16 ordering reaches the tool sort too.
  { id: 'utf16-name-ordering', tools: [{ name: '\u{1F600}', description: 'emoji' }, { name: '', description: 'private' }] }
];

write('tools-digest', {
  description: 'toolsDigest(tools) — sha256 over the material, sliced to 16.',
  cases: digestCases.map(({ id, tools }) => ({ id, tools, digest: manifest.toolsDigest(tools) }))
});

// diffTools — the whole returned structure, as JSON, so ordering and omitted keys are both checked.
const diffCases = [
  { id: 'no-change', before: [{ name: 'a', description: 'd' }], after: [{ name: 'a', description: 'd' }] },
  { id: 'added', before: [], after: [{ name: 'a', description: 'new' }] },
  { id: 'removed', before: [{ name: 'a', description: 'gone', inputSchema: { type: 'object' } }], after: [] },
  { id: 'changed-description', before: [{ name: 'a', description: 'old' }], after: [{ name: 'a', description: 'new' }] },
  { id: 'changed-schema-only', before: [{ name: 'a', description: 'd', inputSchema: { a: 1 } }], after: [{ name: 'a', description: 'd', inputSchema: { a: 2 } }] },
  // Ordering: added/changed in `after` order, then removals in `before` order.
  { id: 'ordering-mixed', before: [{ name: 'r1' }, { name: 'k', description: 'old' }, { name: 'r2' }], after: [{ name: 'z', description: 'added-z' }, { name: 'k', description: 'new' }, { name: 'a', description: 'added-a' }] },
  // A22/N11 — a planted zero-width character is reported; U+2066 is NOT.
  { id: 'invisible-zero-width', before: [], after: [{ name: 'a', description: 'safe​text' }] },
  { id: 'invisible-u2066-negative', before: [], after: [{ name: 'a', description: 'safe⁦text' }] },
  { id: 'invisible-deduped-by-first-occurrence', before: [], after: [{ name: 'a', description: '​﻿​­' }] },
  { id: 'invisible-not-reported-on-removal', before: [{ name: 'a', description: 'bad​text' }], after: [] },
  { id: 'invisible-not-reported-from-old-description', before: [{ name: 'a', description: 'bad​text' }], after: [{ name: 'a', description: 'clean' }] },
  // Absent vs explicit null description: `null !== undefined`, so this IS a change.
  { id: 'absent-to-null-description', before: [{ name: 'a' }], after: [{ name: 'a', description: null }] },
  // A duplicate name collapses to the last tool at the first name's position.
  { id: 'duplicate-names-collapse', before: [{ name: 'a', description: 'one' }], after: [{ name: 'a', description: 'two' }, { name: 'a', description: 'three' }] }
];

write('diff-tools', {
  description: 'diffTools(before, after) — the returned array, as JSON.stringify writes it.',
  cases: diffCases.map(({ id, before, after }) => ({
    id, before, after, diff: JSON.stringify(manifest.diffTools(before, after))
  }))
});

// visibleTo / splitToolName / isStale / placardFor — the small pure predicates.
const visibilityCases = [
  { id: 'no-projects', u: { name: 'a' }, cwd: '/x' },
  { id: 'empty-projects', u: { name: 'a', projects: [] }, cwd: '/x' },
  { id: 'scoped-no-cwd', u: { name: 'a', projects: ['/a'] }, cwd: undefined },
  { id: 'exact-match', u: { name: 'a', projects: ['/a/b'] }, cwd: '/a/b' },
  { id: 'trailing-slash-project', u: { name: 'a', projects: ['/a/b/'] }, cwd: '/a/b/c' },
  { id: 'prefix-needs-separator', u: { name: 'a', projects: ['/a/b'] }, cwd: '/a/bc' },
  { id: 'child-matches', u: { name: 'a', projects: ['/a/b'] }, cwd: '/a/b/c' },
  { id: 'empty-project-matches-everything', u: { name: 'a', projects: [''] }, cwd: '/anything' },
  { id: 'dotdot-not-normalised', u: { name: 'a', projects: ['/a/b'] }, cwd: '/a/b/../c' },
  { id: 'doubled-separator-not-normalised', u: { name: 'a', projects: ['/a/b'] }, cwd: '/a//b' },
  { id: 'case-sensitive', u: { name: 'a', projects: ['/A/B'] }, cwd: '/a/b' }
];

write('visible-to', {
  description: 'visibleTo(upstream, cwd) — lexical, case-sensitive, never normalised.',
  cases: visibilityCases.map(({ id, u, cwd }) => ({
    id, upstream: u, cwd: cwd ?? null, visible: manifest.visibleTo(u, cwd)
  }))
});

const splitCases = ['server__tool', 'a__b__c', 'a____b', '__leading', 'trailing__', 'nosep', '', '__', 'a__'];

write('split-tool-name', {
  description: 'splitToolName(name) — splits at the FIRST separator.',
  cases: splitCases.map((input, index) => {
    const r = manifest.splitToolName(input);
    return { id: `split-${index}`, input, server: r ? r.server : null, tool: r ? r.tool : null };
  })
});

// isStale — its FALSE cases matter as much as its true ones.
const staleUpstream = { transport: 'stdio', name: 'a', command: 'x', args: [], env: {} };
const staleHash = config.upstreamHash(staleUpstream);
const staleCases = [
  { id: 'absent-entry', servers: {} },
  { id: 'hash-mismatch', servers: { a: { hash: 'deadbeefdeadbeef', builtAt: 't', tools: [] } } },
  { id: 'hash-absent', servers: { a: { builtAt: 't', tools: [] } } },
  { id: 'non-empty-error', servers: { a: { hash: staleHash, builtAt: 't', tools: [], error: 'boom' } } },
  // The four false cases: current despite looking incomplete.
  { id: 'current-missing-digest', servers: { a: { hash: staleHash, builtAt: 't', tools: [{ name: 'x' }] } } },
  { id: 'current-empty-tools', servers: { a: { hash: staleHash, builtAt: 't', tools: [] } } },
  { id: 'current-with-pending', servers: { a: { hash: staleHash, builtAt: 't', tools: [{ name: 'x' }], digest: 'd', pending: { tools: [], digest: 'e', seenAt: 't' } } } },
  { id: 'current-empty-error', servers: { a: { hash: staleHash, builtAt: 't', tools: [], error: '' } } }
];

write('is-stale', {
  description: 'isStale(manifest, upstream) — including the four entries that are CURRENT.',
  cases: staleCases.map(({ id, servers }) => ({
    id, upstream: staleUpstream, servers,
    stale: manifest.isStale({ version: 1, servers }, staleUpstream)
  }))
});

// unionTools — namespacing, placards, and the unreachable-placard defect (N8).
const unionCases = [
  { id: 'plain', servers: { a: { hash: 'h', builtAt: 't', tools: [{ name: 'one', description: 'does one' }] } }, upstreams: [{ transport: 'stdio', name: 'a' }], cwd: undefined },
  { id: 'description-falls-back-to-name', servers: { a: { hash: 'h', builtAt: 't', tools: [{ name: 'one' }] } }, upstreams: [{ transport: 'stdio', name: 'a' }], cwd: undefined },
  { id: 'empty-description-is-kept', servers: { a: { hash: 'h', builtAt: 't', tools: [{ name: 'one', description: '' }] } }, upstreams: [{ transport: 'stdio', name: 'a' }], cwd: undefined },
  { id: 'other-members-survive', servers: { a: { hash: 'h', builtAt: 't', tools: [{ name: 'one', description: 'd', inputSchema: { z: 1, a: 2 }, title: 'T', 'x-vendor': { keep: true } }] } }, upstreams: [{ transport: 'stdio', name: 'a' }], cwd: undefined },
  // A declared placard outranks an entry error, and IS reachable because tools survive.
  { id: 'declared-placard', servers: { a: { hash: 'h', builtAt: 't', tools: [{ name: 'one', description: 'd' }], error: 'entry error' } }, upstreams: [{ transport: 'stdio', name: 'a', placard: { reason: 'under repair', substitute: 'other-server' } }], cwd: undefined },
  { id: 'declared-placard-no-substitute', servers: { a: { hash: 'h', builtAt: 't', tools: [{ name: 'one', description: 'd' }] } }, upstreams: [{ transport: 'stdio', name: 'a', placard: { reason: 'under repair' } }], cwd: undefined },
  // An entry error DOES placard, but only while the tools are still there.
  { id: 'entry-error-placard-with-tools', servers: { a: { hash: 'h', builtAt: 't', tools: [{ name: 'one', description: 'd' }], error: 'boom' } }, upstreams: [{ transport: 'stdio', name: 'a' }], cwd: undefined },
  // N8 — the normal failure path leaves `tools: []`, so the entry is skipped BEFORE the placard.
  { id: 'unreachable-placard-after-failure', servers: { a: { hash: 'h', builtAt: 't', tools: [], error: 'boom' } }, upstreams: [{ transport: 'stdio', name: 'a' }], cwd: undefined },
  { id: 'empty-error-no-placard', servers: { a: { hash: 'h', builtAt: 't', tools: [{ name: 'one', description: 'd' }], error: '' } }, upstreams: [{ transport: 'stdio', name: 'a' }], cwd: undefined },
  { id: 'absent-entry-skipped', servers: {}, upstreams: [{ transport: 'stdio', name: 'a' }], cwd: undefined },
  { id: 'scoped-out', servers: { a: { hash: 'h', builtAt: 't', tools: [{ name: 'one' }] } }, upstreams: [{ transport: 'stdio', name: 'a', projects: ['/other'] }], cwd: '/here' },
  // M29 — a disabled server serves nothing, and the three cases are the three ways a reader
  // might expect it to leak: the entry is fully populated, the placard would normally keep a
  // server listed, and the caller is inside the server's own project.
  { id: 'disabled-withholds-populated-tools', servers: { a: { hash: 'h', builtAt: 't', tools: [{ name: 'one', description: 'd' }] } }, upstreams: [{ transport: 'stdio', name: 'a', disabled: true }], cwd: undefined },
  { id: 'disabled-outranks-declared-placard', servers: { a: { hash: 'h', builtAt: 't', tools: [{ name: 'one', description: 'd' }] } }, upstreams: [{ transport: 'stdio', name: 'a', disabled: true, placard: { reason: 'under repair', substitute: 'other-server' } }], cwd: undefined },
  { id: 'disabled-inside-its-own-project', servers: { a: { hash: 'h', builtAt: 't', tools: [{ name: 'one' }] } }, upstreams: [{ transport: 'stdio', name: 'a', disabled: true, projects: ['/here'] }], cwd: '/here' },
  { id: 'disabled-false-still-serves', servers: { a: { hash: 'h', builtAt: 't', tools: [{ name: 'one', description: 'd' }] } }, upstreams: [{ transport: 'stdio', name: 'a', disabled: false }], cwd: undefined },
  { id: 'two-servers-keep-upstream-order', servers: { b: { hash: 'h', builtAt: 't', tools: [{ name: 'x' }] }, a: { hash: 'h', builtAt: 't', tools: [{ name: 'y' }] } }, upstreams: [{ transport: 'stdio', name: 'a' }, { transport: 'stdio', name: 'b' }], cwd: undefined }
];

write('union-tools', {
  description: 'unionTools(manifest, upstreams, {cwd}) — the served list, as JSON.stringify writes it.',
  cases: unionCases.map(({ id, servers, upstreams, cwd }) => ({
    id, servers, upstreams, cwd: cwd ?? null,
    union: JSON.stringify(manifest.unionTools({ version: 1, servers }, upstreams, { cwd }))
  }))
});

// loadManifest — what the shallow parser accepts, and what it degrades on.
const { writeFileSync: writeTmp, mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const scratch = mkdtempSync(join(tmpdir(), 'mcp-router-vectors-'));
const scratch2 = mkdtempSync(join(tmpdir(), 'mcp-router-vectors-cfg-'));

const manifestTexts = [
  { id: 'ordinary', text: '{"version":1,"servers":{"a":{"hash":"h","builtAt":"t","tools":[]}}}' },
  // A20 — `typeof [] === "object"`, so this is ACCEPTED.
  { id: 'servers-array-accepted', text: '{"version":1,"servers":[]}' },
  { id: 'unknown-top-level-preserved', text: '{"version":1,"servers":{},"generatedBy":"someone","note":{"deep":true}}' },
  { id: 'unknown-entry-fields-preserved', text: '{"version":1,"servers":{"a":{"hash":"h","builtAt":"t","tools":[],"x-vendor":1}}}' },
  { id: 'entries-not-validated', text: '{"version":1,"servers":{"a":{"nonsense":true}}}' },
  { id: 'member-order-preserved', text: '{"servers":{"a":{"tools":[],"builtAt":"t","hash":"h"}},"version":1}' },
  { id: 'version-string-rejected', text: '{"version":"1","servers":{}}' },
  { id: 'version-two-rejected', text: '{"version":2,"servers":{}}' },
  { id: 'servers-null-rejected', text: '{"version":1,"servers":null}' },
  { id: 'servers-string-rejected', text: '{"version":1,"servers":"nope"}' },
  { id: 'servers-absent-rejected', text: '{"version":1}' },
  { id: 'not-json', text: '{oh no' },
  { id: 'top-level-array-rejected', text: '[1,2,3]' }
];

write('manifest-parse', {
  description: 'loadManifest(path) — the shallow parser. A degraded load returns the empty manifest.',
  cases: manifestTexts.map(({ id, text }) => {
    const file = join(scratch, `${id}.json`);
    writeTmp(file, text);
    const loaded = manifest.loadManifest(file);
    return {
      id, text,
      loaded: JSON.stringify(loaded),
      // The empty manifest is exactly what a degraded load returns, so this flag records which of
      // the two happened rather than leaving it to be inferred.
      degraded: JSON.stringify(loaded) === JSON.stringify({ version: 1, servers: {} }),
      reserialised: JSON.stringify(loaded, null, 2)
    };
  })
});

// A missing file is its own case: degrades without an error.
write('manifest-missing', {
  description: 'loadManifest on a path that does not exist.',
  cases: [{ id: 'absent', loaded: JSON.stringify(manifest.loadManifest(join(scratch, 'nope.json'))) }]
});

// buildManifest's four branches, with the clock and the pool stubbed.
const buildUpstream = { transport: 'stdio', name: 'a', command: 'x', args: [], env: {} };
const buildHash = config.upstreamHash(buildUpstream);
const poolReturning = (tools) => ({ acquire: async () => ({ client: { listTools: async () => ({ tools }) } }) });
const poolFailing = (message) => ({ acquire: async () => { throw new Error(message); } });

const buildCases = [
  { id: 'first-sight-approves', servers: {}, observation: { tools: [{ name: 'one', description: 'd' }] }, force: false },
  { id: 'equal-digest-clears-error-and-pending', servers: { a: { hash: buildHash, builtAt: 'old', tools: [{ name: 'one', description: 'd' }], digest: manifest.toolsDigest([{ name: 'one', description: 'd' }]), error: 'stale error', pending: { tools: [], digest: 'x', seenAt: 'old' } } }, observation: { tools: [{ name: 'one', description: 'd' }] }, force: true },
  { id: 'changed-digest-holds-pending', servers: { a: { hash: buildHash, builtAt: 'old', tools: [{ name: 'one', description: 'old' }], digest: manifest.toolsDigest([{ name: 'one', description: 'old' }]), error: 'prior', 'x-vendor': 'kept' } }, observation: { tools: [{ name: 'one', description: 'new' }] }, force: true },
  // N8 — a failure OVERWRITES the approved tools with an empty list.
  { id: 'failure-destroys-approved-tools', servers: { a: { hash: buildHash, builtAt: 'old', tools: [{ name: 'one', description: 'd' }], digest: 'dd' } }, observation: { error: 'spawn failed' }, force: true },
  { id: 'not-stale-is-skipped', servers: { a: { hash: buildHash, builtAt: 'old', tools: [{ name: 'one' }], digest: 'dd' } }, observation: { tools: [{ name: 'CHANGED' }] }, force: false },
  { id: 'force-bypasses-staleness', servers: { a: { hash: buildHash, builtAt: 'old', tools: [{ name: 'one' }], digest: 'dd' } }, observation: { tools: [{ name: 'one' }] }, force: true },
  { id: 'removed-upstreams-stay', servers: { gone: { hash: 'h', builtAt: 'old', tools: [{ name: 'z' }] } }, observation: { tools: [{ name: 'one' }] }, force: false }
];

// The observation is recorded, not just applied: replaying these branches needs the input the
// stub pool supplied, and a vector that records only the output cannot be re-run against anything.
const poolFor = (o) => ('error' in o ? poolFailing(o.error) : poolReturning(o.tools));

const buildResults = [];
for (const { id, servers, observation, force } of buildCases) {
  const input = { version: 1, servers: JSON.parse(JSON.stringify(servers)) };
  const result = await atFixedTime(
    () => manifest.buildManifest([buildUpstream], poolFor(observation), input, { force })
  );
  buildResults.push({
    id, upstream: buildUpstream, force, servers, observation, builtAtMs: FIXED_MS,
    manifest: JSON.stringify(result.manifest),
    built: result.built,
    failed: result.failed,
    // The reference mutates the manifest it was handed rather than returning a copy.
    mutatedInPlace: result.manifest === input
  });
}

write('build-manifest', {
  description: 'buildManifest — the four bookkeeping branches, with a fixed clock and a stub pool.',
  cases: buildResults
});

// loadConfig — nullish precedence (N3) and JavaScript property enumeration order (N10).
//
// Both are behaviours no fixture in the corpus above reaches: precedence is decided by `??` rather
// than `||`, so an explicit `0` must survive, and the skipped list follows object enumeration
// order, where integer-like keys come first in ascending numeric order regardless of how they were
// written in the file.
const loadCases = [
  // N3 — an explicit zero or empty string is honoured, not replaced by a default.
  { id: 'explicit-zeroes-honoured', text: '{"port":0,"host":"","idleMs":0,"mcpServers":{}}', opts: {} },
  { id: 'defaults-when-absent', text: '{"mcpServers":{}}', opts: {} },
  { id: 'options-outrank-the-file', text: '{"port":1,"host":"a","idleMs":2,"mcpServers":{}}', opts: { port: 3, host: 'b', idleMs: 4 } },
  { id: 'option-zero-outranks-the-file', text: '{"port":1,"host":"a","idleMs":2,"mcpServers":{}}', opts: { port: 0, host: '', idleMs: 0 } },
  // startupTimeoutMs has NO option-level override — it comes from the file or the default only.
  // Its default is already proven by `defaults-when-absent`; what no other case reaches is the
  // `??`-versus-`||` boundary on the one field an option cannot reach, so an explicit 0 in the file
  // must survive rather than be replaced by 60000.
  { id: 'startup-timeout-has-no-option', text: '{"startupTimeoutMs":5,"mcpServers":{}}', opts: { port: 9 } },
  { id: 'startup-timeout-zero-honoured', text: '{"startupTimeoutMs":0,"mcpServers":{}}', opts: {} },
  // N10 — integer-like keys enumerate first, ascending, whatever order the file lists them in.
  { id: 'skipped-follow-enumeration-order', text: '{"mcpServers":{"a":{},"10":{},"2":{}}}', opts: {} }
];

const loadResults = loadCases.map(({ id, text, opts }) => {
  const file = join(scratch2, `${id}.json`);
  writeTmp(file, text);
  const r = config.loadConfig({ ...opts, configPath: file });
  return {
    id, text, opts,
    port: r.config.port,
    host: r.config.host,
    idleMs: r.config.idleMs,
    startupTimeoutMs: r.config.startupTimeoutMs,
    skipped: r.skipped
  };
});

write('load-config', {
  description: 'loadConfig(opts) — nullish precedence and the enumeration order of skipped entries.',
  cases: loadResults
});

// The ISO-8601 timestamp every log line and every `builtAt` carries.
write('iso8601', {
  description: 'new Date(ms).toISOString() — the exact shape a log line leads with.',
  cases: [0, 1, 999, 1000, FIXED_MS, 1e12, -1, -86400000, 253402300799999, 1755100000000]
    .map((ms, index) => ({ id: `iso-${index}`, ms, text: new Date(ms).toISOString() }))
});

// The log line itself, captured from the reference's own emitter rather than reconstructed.
//
// Every message here is one the manifest module actually writes, so this is a byte comparison of
// the real output and not a check that two format strings agree. stdout is watched at the same
// time: the reference promises it stays clean for a possible stdio transport, and that promise is
// only worth anything if something asserts it.
const logModule = require(join(distDir, 'log.js'));

const logEvents = [
  { id: 'manifest-unreadable', level: 'warn', call: (l) => l.warn('manifest at /p/manifest.json unreadable (bad); rebuilding') },
  { id: 'manifest-reloaded', level: 'info', call: (l) => l.info('manifest reloaded: 3 servers cached') },
  { id: 'manifest-reload-failed', level: 'warn', call: (l) => l.warn('manifest reload failed (bad); serving the previous one') },
  { id: 'manifest-current', level: 'debug', call: (l) => l.debug('manifest for "alpha" is current; not spawning') },
  { id: 'server-indexed', level: 'info', call: (l) => l.info('indexed "alpha": 7 tools') },
  { id: 'server-surface-changed', level: 'warn', call: (l) => l.warn('"alpha" changed its tool surface (2 change(s)); serving the approved one until it is accepted') },
  { id: 'server-index-failed', level: 'error', call: (l) => l.error('failed to index "alpha": spawn failed') }
];

const logCases = [];
let stdoutBytes = 0;
{
  const realErr = process.stderr.write.bind(process.stderr);
  const realOut = process.stdout.write.bind(process.stdout);
  logModule.configureLogging(undefined, true); // verbose, so the debug line is emitted too
  for (const { id, level, call } of logEvents) {
    let captured = '';
    process.stderr.write = (chunk) => { captured += Buffer.from(chunk).toString('utf8'); return true; };
    process.stdout.write = (chunk) => { stdoutBytes += Buffer.byteLength(chunk); return true; };
    try { await atFixedTime(async () => call(logModule.log)); }
    finally { process.stderr.write = realErr; process.stdout.write = realOut; }
    logCases.push({ id, level, line: captured });
  }
  // And with verbosity off, a debug call must emit nothing at all.
  logModule.configureLogging(undefined, false);
  let quiet = '';
  process.stderr.write = (chunk) => { quiet += Buffer.from(chunk).toString('utf8'); return true; };
  try { await atFixedTime(async () => logModule.log.debug('manifest for "alpha" is current; not spawning')); }
  finally { process.stderr.write = realErr; }
  logCases.push({ id: 'debug-suppressed-when-quiet', level: 'debug', line: quiet });
}

write('log-line', {
  description: 'The bytes src/log.ts writes to stderr, captured from the reference itself.',
  cases: logCases
});

if (stdoutBytes !== 0) throw new Error(`the reference wrote ${stdoutBytes} bytes to stdout, which it must never do`);

// ============================================================ R3 — control, usage, registry
//
// Everything below drives `dist/control.js`, `dist/usage.js` and `dist/registry.js`, or the
// JavaScript engine itself where the behaviour under test *is* an engine semantic the Swift port
// reimplements (`Number`, `localeCompare`, `slice` with a negative or NaN index). Those are not
// hand-written expectations dressed up as vectors: Node's own evaluation is the oracle, and the
// Swift has a from-scratch implementation of each that must agree with it.
//
// This is the corpus B76 requires to grow. R1 left 224 executed cases; a port of three more modules
// that added none would be claiming parity it never measured.

const controlModule = require(join(distDir, 'control.js'));
const usageModule = require(join(distDir, 'usage.js'));

// ---------------------------------------------------------------- isControlPath
//
// The routing predicate. Getting it wrong in either direction is invisible until it is expensive:
// too narrow and a control call falls through to /mcp, too wide and an MCP path is answered by the
// control API. The prefix-vs-equality distinction is the whole of it — `/serverside` is not ours,
// `/servers/` is, and `/registry` alone is not because only `/registry/` is a prefix match.
write('is-control-path', {
  description: 'control.isControlPath — the exact set of paths the control API claims.',
  cases: [
    '/servers', '/servers/', '/servers/alpha', '/servers/alpha/changes', '/servers/a/b/c',
    '/serverside', '/server', '/servers2', '/SERVERS',
    '/usage', '/usage/', '/usage/summary', '/usage/stream', '/usaged', '/usag',
    '/registry/', '/registry/search', '/registry', '/registrys',
    '/mcp', '/', '', '/health', '/servers%2Falpha'
  ].map((pathname, index) => ({
    id: `path-${index}`,
    pathname,
    control: controlModule.isControlPath(pathname)
  }))
});

// ---------------------------------------------------------------- Number(x)
//
// N4 and N6 both hang off this. `Number` is not `parseFloat` and is emphatically not Swift's
// `Double.init`: an empty or all-whitespace string is **0**, a padded numeral trims, `Infinity` is
// a literal, the radix prefixes are accepted, and a trailing character poisons the whole thing to
// NaN. Every one of those is a way a reasonable Swift port answers a different HTTP response.
const numberInputs = [
  '', ' ', '\t\n\r ', '0', '-0', '12', ' 12 ', '12 ', ' 12', '+12', '-12',
  '12.5', '.5', '5.', '1e3', '1E3', '1e-3', '1.2e+3', 'Infinity', '-Infinity', '+Infinity',
  'infinity', 'NaN', 'abc', '12abc', 'abc12', '1 2', '1,2', '0x1f', '0X1F', '0b101', '0o17',
  '0xg', '0b', '1_000', '١٢', 'null', 'undefined', 'true', ' 12 '
];
write('js-to-number', {
  description: 'Number(x) for every string the control API can receive as a query value (N4, N6).',
  cases: numberInputs.map((text, index) => {
    const n = Number(text);
    return {
      id: `number-${index}`,
      text,
      // NaN and the infinities have no JSON spelling, so the expectation is carried as a tag plus a
      // finite value. A vector that serialised NaN as null would silently accept a wrong answer.
      kind: Number.isNaN(n) ? 'nan' : n === Infinity ? 'inf' : n === -Infinity ? '-inf' : 'finite',
      value: Number.isFinite(n) ? n : 0,
      // `JSON.stringify(-0)` is `"0"`, so the sign of a negative zero cannot survive in `value`.
      // It has to: `Number("-0")` is -0, and `slice(-0)` returns the whole array where `slice(0)`
      // of a suffix returns none. Carried as a flag for the same reason NaN is carried as a tag.
      negativeZero: Object.is(n, -0)
    };
  })
});

// ---------------------------------------------------------------- localeCompare
//
// N8. The reference ranks `updatedAt` with `localeCompare`, not `<`. ICU root collation puts `"a"`
// before `"B"` and `"A"` after `"a"` — both the reverse of UTF-16 code-unit order — so the obvious
// Swift substitution reorders the registry results for any pair of rows whose timestamps differ in
// case or in fractional-second digit count.
const comparePairs = [
  ['2024-01-01T00:00:00Z', '2024-01-01T00:00:00.000Z'],
  ['2024-01-01T00:00:00.1Z', '2024-01-01T00:00:00.10Z'],
  ['2024-01-02T00:00:00Z', '2024-01-01T00:00:00Z'],
  ['', '2024-01-01T00:00:00Z'],
  ['', ''],
  ['a', 'B'], ['A', 'a'], ['a', 'A'], ['B', 'a'], ['a', 'b'],
  ['z', 'Z'], ['é', 'e'], ['é', 'é'], ['10', '9'], ['1', '10'],
  ['2024-01-01T00:00:00+00:00', '2024-01-01T00:00:00Z']
];
write('locale-compare', {
  description: 'String.prototype.localeCompare over the ISO domain and the letter cases (N8).',
  cases: comparePairs.map(([lhs, rhs], index) => ({
    id: `compare-${index}`,
    lhs,
    rhs,
    // Normalised to the sign, which is all the sort consumes and all ICU guarantees.
    result: Math.sign(lhs.localeCompare(rhs))
  }))
});

// ---------------------------------------------------------------- projectOf
//
// `basename(cwd)`, which is POSIX basename and not "the text after the last slash": a trailing
// slash is ignored, `/` is `/`, and an empty cwd is falsy so the whole expression is undefined.
write('project-of', {
  description: 'usage.projectOf — the project label the activity view groups by.',
  cases: [
    '/Users/x/Dev/app', '/Users/x/Dev/app/', '/Users/x/Dev/app//', '/', '//', '',  // path-gate: ok — basename() inputs: fictitious cwd strings the vector exercises, never opened
    'app', './app', '/a b/c d', '/Users/x/Dev/.hidden', '/Users/x/Dev/app.tar.gz', '/日本語/プロジェクト'  // path-gate: ok — as above — a dotfile and a dotted name, pinning POSIX basename's behaviour
  ].map((cwd, index) => ({
    id: `project-${index}`,
    cwd,
    // `undefined` has no JSON spelling; the member is omitted, which is exactly what the reference's
    // own serialisation does with it (N1).
    ...(usageModule.projectOf(cwd) === undefined ? {} : { project: usageModule.projectOf(cwd) })
  }))
});

// ---------------------------------------------------------------- /usage?limit
//
// The real `UsageStore.recent`, over a real seeded ring, because the pipeline is three operations
// whose order is the contract: filter, then take the **last** `limit`, then reverse. A port that
// reverses first returns the wrong end of the history and every fixture still passes.
const usageScratch = mkdtempSync(join(tmpdir(), 'mcp-router-vectors-usage-'));
const usageLog = join(usageScratch, 'usage.log');
const usageStats = join(usageScratch, 'usage-stats.json');
{
  const seeded = [];
  for (let i = 0; i < 12; i += 1) {
    seeded.push({
      ts: new Date(1755100000000 + i * 1000).toISOString(),
      server: i % 3 === 0 ? 'alpha' : 'beta',
      tool: `tool-${i}`,
      ok: i % 4 !== 0,
      ms: i,
      cold: i === 0,
      cwd: i % 2 === 0 ? '/Users/x/Dev/one' : '/Users/x/Dev/two'  // path-gate: ok — seeded record cwd: a label the store groups by, not a location
    });
  }
  writeFileSync(usageLog, seeded.map((r) => JSON.stringify(r)).join('\n') + '\n');

  const store = new usageModule.UsageStore(usageLog, usageStats);
  const limitValues = [null, '', ' ', '0', '1', '3', '200', 'abc', '-1', '-5', '-100', '1e2', '2.7', '-2.7'];
  const usageCases = [];
  for (const [index, raw] of limitValues.entries()) {
    // Exactly the expression at src/control.ts's `/usage` branch.
    const limit = Number(raw ?? 200);
    usageCases.push({
      id: `limit-${index}`,
      ...(raw === null ? {} : { limit: raw }),
      records: store.recent({ limit }).map((r) => r.tool)
    });
  }
  // And the two filters, whose interaction with the slice is the part an order-swapped port breaks.
  usageCases.push({ id: 'filter-server', limit: '2', server: 'alpha', records: store.recent({ limit: 2, server: 'alpha' }).map((r) => r.tool) });
  usageCases.push({ id: 'filter-cwd', limit: '3', cwd: '/Users/x/Dev/two', records: store.recent({ limit: 3, cwd: '/Users/x/Dev/two' }).map((r) => r.tool) });  // path-gate: ok — a filter argument matched against stored cwd labels, never opened
  usageCases.push({ id: 'filter-both', limit: 'abc', server: 'beta', cwd: '/Users/x/Dev/two', records: store.recent({ limit: Number('abc'), server: 'beta', cwd: '/Users/x/Dev/two' }).map((r) => r.tool) });  // path-gate: ok — as above — a filter argument, never opened
  usageCases.push({ id: 'filter-no-match', limit: '5', server: 'nobody', records: store.recent({ limit: 5, server: 'nobody' }).map((r) => r.tool) });

  write('usage-limit', {
    description: 'UsageStore.recent over a seeded ring — filter, take the last N, reverse (N4, B45, B46).',
    // The exact bytes of the log the reference read, so the Swift store warms from the same input
    // rather than from a reconstruction of it.
    log: seeded.map((r) => JSON.stringify(r)).join('\n') + '\n',
    cases: usageCases
  });
}

// ---------------------------------------------------------------- /registry/search?limit
//
// `Math.min(Number(x ?? 30) || 30, 60)` then `slice(0, limit)`. Three coercions stacked: `||` is
// ToBoolean so both `0` and `NaN` collapse to 30, `min` caps at 60, and a negative survives all of
// it and reaches `slice`, where it counts back from the end and drops rows instead of taking them.
{
  const rows = Array.from({ length: 70 }, (_, i) => `row-${i}`);
  const limitValues = [null, '', ' ', '0', '1', '30', '59', '60', '61', '500', 'abc', '-1', '-5', '-100', '2.9', '1e1', 'Infinity', '-Infinity'];
  write('registry-limit', {
    description: 'Math.min(Number(x ?? 30) || 30, 60) then slice(0, limit) — the registry cap (N6, B54).',
    rows: rows.length,
    cases: limitValues.map((raw, index) => {
      const limit = Math.min(Number(raw ?? 30) || 30, 60);
      return {
        id: `rlimit-${index}`,
        ...(raw === null ? {} : { limit: raw }),
        kind: Number.isNaN(limit) ? 'nan' : limit === Infinity ? 'inf' : limit === -Infinity ? '-inf' : 'finite',
        coerced: Number.isFinite(limit) ? limit : 0,
        sliced: rows.slice(0, limit)
      };
    })
  });
}


// ---------------------------------------------------------------- M30 · the document route
//
// In a module of its own, and imported rather than inlined, so `generate-document-vectors.mjs` can
// also be run on its own. That is not tidiness: `parity-regen` drives this whole file, and this
// file cannot currently run to completion — `buildManifest` is called here without the `commit`
// option it now requires, which is a break that predates M30 and is recorded in
// `planning/features-to-triage/M31-parity-regen-is-broken.md`. A generator whose only entry point
// is a script that throws is a generator nobody can re-run.
writeDocumentVectors({ write, distDir, require });

rmSync(usageScratch, { recursive: true, force: true });

rmSync(scratch, { recursive: true, force: true });
rmSync(scratch2, { recursive: true, force: true });
console.log(`\nwrote manifest vectors to ${outDir}`);
