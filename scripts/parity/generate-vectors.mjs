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
  placard: u.placard ?? null
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
  { id: 'unknown-fields-ignored', name: 'a', raw: { command: 'x', nonsense: 1, alsoNonsense: { q: 2 } } }
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
