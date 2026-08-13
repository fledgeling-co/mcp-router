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
const outDir = join(repoRoot, 'app', 'Tests', 'RouterCoreTests', 'Vectors');
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
