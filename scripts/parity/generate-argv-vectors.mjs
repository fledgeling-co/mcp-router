// The DEF-070 argv vectors, generated from the TypeScript reference itself.
//
// `GET /servers` used to publish every stdio upstream's raw argument list, and an argument list is
// where `--token=…`, `--api-key …` and an inline URL password live. The rule that removes them is
// `redactArgs` in `src/secrets.ts`, and the expectation for each case is what that reference
// returns for it. The Swift port must return the same thing.
//
// A module of its own, with its own entry point, the same as `generate-document-vectors.mjs`:
//
//   node scripts/parity/generate-argv-vectors.mjs            # writes argv-redact.json
//   MCP_ROUTER_VECTORS=/tmp/x node scripts/parity/...        # writes it somewhere else

import { writeFileSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

// Each case names every server it needs, because a needle is a literal from another server's env
// as often as from its own. `token` is the control token the router would hold.
const ARGV_CASES = [
  {
    id: 'flag-equals-secret',
    servers: { a: { command: 'npx', args: ['serve', '--token=abcdef123456', '--port=8080'] } },
    target: 'a',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'flag-equals-plain-kept',
    servers: { a: { command: 'npx', args: ['--port=8080', '--verbose', 'serve'] } },
    target: 'a',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'flag-space-secret-value',
    servers: { a: { command: 'npx', args: ['--api-key', 'sk-live-0123456789'] } },
    target: 'a',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'flag-space-next-is-flag',
    servers: { a: { command: 'npx', args: ['--token', '--verbose'] } },
    target: 'a',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'flag-space-value-then-positional',
    servers: { a: { command: 'npx', args: ['--password', 'hunter2hunter2', 'run'] } },
    target: 'a',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'secret-segment-over-redacts',
    servers: { a: { command: 'npx', args: ['--sort-key=name'] } },
    target: 'a',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'word-containing-key-kept',
    servers: { a: { command: 'npx', args: ['--monkey=banana'] } },
    target: 'a',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'url-password',
    servers: { a: { command: 'psql-mcp', args: ['postgres://alice:s3cr3tpass@db.internal:5432/app'] } },
    target: 'a',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'url-token-in-user-position',
    servers: { a: { command: 'git-mcp', args: ['https://ghp_0123456789abcdef@github.com/acme/x.git'] } },
    target: 'a',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'url-without-userinfo-kept',
    servers: { a: { command: 'npx', args: ['https://example.com/mcp?page=2'] } },
    target: 'a',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'query-secret-value',
    servers: { a: { command: 'npx', args: ['https://h.example.com/mcp?api_key=zz99ZZ88&page=2'] } },
    target: 'a',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'env-assignment',
    servers: { a: { command: 'env', args: ['API_TOKEN=abcdef123456', 'MODE=prod'] } },
    target: 'a',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'needle-from-another-server',
    servers: {
      a: { command: 'node', args: ['server.js'], env: { GITHUB_TOKEN: 'ghp_0123456789abcdef' } },
      b: { command: 'node', args: ['--header=ghp_0123456789abcdef'] }
    },
    target: 'b',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'control-token-needle',
    servers: { b: { command: 'node', args: ['--listen', 'ctl_9f8e7d6c5b4a3210'] } },
    target: 'b',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'short-needle-kept',
    servers: {
      a: { command: 'node', env: { DEBUG: '1234567' } },
      b: { command: 'node', args: ['1234567'] }
    },
    target: 'b',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'percent-encoded-needle',
    servers: {
      a: { command: 'node', env: { K: 'a b&c=d/e' } },
      b: { command: 'node', args: ['https://h.example.com/?q=a%20b%26c%3Dd%2Fe'] }
    },
    target: 'b',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'base64-needle',
    servers: {
      a: { command: 'node', env: { K: 'secretvalue123' } },
      b: { command: 'node', args: ['Basic c2VjcmV0dmFsdWUxMjM='] }
    },
    target: 'b',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'non-string-value-after-secret-flag',
    // `cwd` is set because the reference's `parseServer` throws on a non-string argument unless it
    // is, and this case is about the value that follows the flag, not the throw.
    servers: { a: { command: 'node', cwd: '/', args: ['--token', 12345678] } },
    target: 'a',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'camel-case-flag-equals',
    servers: { a: { command: 'npx', args: ['--accessToken=abcdef123456'] } },
    target: 'a',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'camel-case-flag-space',
    servers: { a: { command: 'npx', args: ['--clientSecret', 'hunter2hunter2'] } },
    target: 'a',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'authorization-header-argument',
    servers: { a: { command: 'npx', args: ['-H', 'Authorization: Bearer abcdef123456'] } },
    target: 'a',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'cookie-header-flag',
    servers: { a: { command: 'npx', args: ['--header=Cookie: sid=abcdef123456'] } },
    target: 'a',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'json-header-argument',
    servers: { a: { command: 'npx', args: ['{"Cookie": "sid=abcdef123456"}'] } },
    target: 'a',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'bearer-scheme-argument',
    servers: { a: { command: 'npx', args: ['Bearer abcdef123456'] } },
    target: 'a',
    token: 'ctl_9f8e7d6c5b4a3210'
  },
  {
    id: 'non-string-elements-kept',
    servers: { a: { command: 'node', cwd: '/', args: [1, 2] } },
    target: 'a',
    token: 'ctl_9f8e7d6c5b4a3210'
  }
];

// The servers in a case, parsed by the reference's own `parseServer`. A server it rejects is not an
// upstream, and so it carries no needle.
function parsedUpstreams(parseServer, servers) {
  return Object.entries(servers).flatMap(([name, raw]) => {
    const parsed = parseServer(name, raw);
    return 'upstream' in parsed ? [parsed.upstream] : [];
  });
}

export function writeArgvVectors({ write, distDir, require }) {
  // ---------------------------------------------------------------- DEF-070 · argv redaction
  //
  // Both routers apply this rule to `args` on `GET /servers`, which is not token-gated. A
  // hand-written expectation would record what the author believed the rule does, and every case
  // below is one where that belief and the reference could differ: a flag that takes no value, a
  // value that is a number, a needle that lives in another server's env, a percent-encoded copy.
  const { parseServer } = require(join(distDir, 'config.js'));
  const secrets = require(join(distDir, 'secrets.js'));

  // pin-class: src-export — secrets.collectNeedles and secrets.redactArgs (DEF-070).
  write('argv-redact', {
    description: 'secrets.redactArgs(args, collectNeedles(upstreams, token)) — the args GET /servers serves for a stdio server (DEF-070).',
    cases: ARGV_CASES.map((testCase) => {
      const upstreams = parsedUpstreams(parseServer, testCase.servers);
      const needles = secrets.collectNeedles(upstreams, testCase.token);
      const target = upstreams.find((u) => u.name === testCase.target);
      return {
        id: testCase.id,
        servers: testCase.servers,
        target: testCase.target,
        token: testCase.token,
        expected: secrets.redactArgs(target.args, needles)
      };
    })
  });
}

// Run directly: build the same `write` the main generator uses, and the same output directory.
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const require = createRequire(import.meta.url);
  const here = dirname(fileURLToPath(import.meta.url));
  const repoRoot = join(here, '..', '..');
  const distDir = process.env.MCP_ROUTER_DIST ?? join(repoRoot, 'dist');
  const outDir =
    process.env.MCP_ROUTER_VECTORS ?? join(repoRoot, 'app', 'Tests', 'RouterCoreTests', 'Vectors');
  mkdirSync(outDir, { recursive: true });
  const write = (name, payload) => {
    writeFileSync(join(outDir, `${name}.json`), JSON.stringify(payload, null, 2) + '\n');
    console.log(`${name}: ${payload.cases.length} cases`);
  };
  writeArgvVectors({ write, distDir, require });
}
