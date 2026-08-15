#!/usr/bin/env node
//
// A deterministic stand-in for the two live registry indexes.
//
// `GET /registry/search` is the one control route that leaves the machine. The reference calls
// registry.modelcontextprotocol.io and registry.smithery.ai, so two runs a second apart return
// different bytes and the route has never been comparable — `control-registry-search` and
// `fixture-registry-search` were both blocked on that (`D-m`). Both implementations resolve those
// two hosts from `MCP_ROUTER_REGISTRY` / `MCP_ROUTER_SMITHERY` (src/registry.ts:18-19;
// RegistryDeps.officialBase/.smitheryBase), which is the seam this server plugs into: point both
// binaries here and any difference in the response is the port's.
//
// FIVE PROPERTIES, each deliberate.
//
// 1. The corpus is FIXED and is not filtered by the query. A registry filters; a fixture's job is
//    to hand both routers identical bytes.
//
// 2. One entry per index ECHOES the query string it received into its `description`. Without it,
//    ignoring the query would also mean never noticing what the router asked for — and what the
//    router asks for is real behaviour: `String(limit)` for a limit of -1 is "-1" in JavaScript,
//    and a port that stringified a Double would send "-1.0". The echo puts that inside the diffed
//    body, so it fails on content rather than on a check nobody wrote.
//
// 3. `io.acme/atlas` and Smithery's `acme/atlas` carry the SAME github.com repository, so
//    `repoKey` dedupes them into one `source: "both"` row. That is the most interesting path on
//    the route and a naive fixture loses it.
//
// 4. FIXTURE_REGISTRY_FAIL=official|smithery makes that index answer 503. Both implementations
//    turn a non-2xx into the message `HTTP 503` (src/registry.ts:63 `throw new Error(\`HTTP
//    ${r.status}\`)`; RegistrySearch.swift:161), so the warning text agrees on both sides. That is
//    why the failure scenario is an HTTP STATUS rather than a refused connection — though as of
//    P3 a refused connection agrees too, because RegistryHTTPClient maps a transport failure to
//    node's own "fetch failed".
//
// 5. `io.acme/ownerless` carries `repository: "https://github.com/"` — an OWNER-LESS URL the live
//    official index really serves, and the one production deformity in the recorded
//    `registry-search.json` fixture. `repoKey` returns nothing for it, so the row identifies by
//    displayName and is never star-enriched. Without it the deformity lived only in a fixture
//    nothing compares, while the corpus that IS compared held only well-formed URLs.
//
// NOTHING here is time-dependent, random, or read from the network. Every timestamp is a literal.
//
// Usage:  node registry-fixture-server.mjs <port>
//         FIXTURE_REGISTRY_FAIL=smithery node registry-fixture-server.mjs <port>

import { createServer } from 'node:http';

const PORT = Number(process.argv[2] ?? process.env.FIXTURE_REGISTRY_PORT ?? 8968);
const FAIL = process.env.FIXTURE_REGISTRY_FAIL ?? '';

/**
 * The official index: `{servers: [{server, _meta}]}`.
 *
 * `_meta`'s first value is where `updatedAt` is read from (`Object.values(row._meta ?? {})[0]`),
 * so the key name is irrelevant to the reference and is written as the real registry writes it.
 */
const official = (query) => ({
  servers: [
    {
      server: {
        name: 'io.acme/atlas',
        description: 'Atlas — filesystem and search tools',
        version: '1.2.0',
        repository: { url: 'https://github.com/acme/atlas' },
        packages: [{ registryType: 'npm', identifier: '@acme/atlas', version: '1.2.0' }],
      },
      _meta: { 'io.modelcontextprotocol.registry/official': { updatedAt: '2026-03-04T09:15:00.000Z' } },
    },
    {
      server: {
        name: 'io.acme/beacon',
        description: 'Beacon — a Python MCP server',
        version: '0.4.1',
        repository: { url: 'https://github.com/acme/beacon' },
        packages: [{ registryType: 'pypi', identifier: 'beacon-mcp' }],
      },
      // DELIBERATELY OLDER than io.acme/relay's. Neither row has a `useCount`, so the ranking
      // falls to stars and then to `updatedAt`: WITH the seeded stars beacon (128) sorts above
      // relay (none); WITHOUT them both score 0 and relay's later date puts it first. That makes
      // the seeded GitHub cache load-bearing for the ORDER of the compared body, so a cache that
      // silently missed on both sides — which the reference and the port both answer by skipping
      // stars entirely — changes the bytes instead of passing quietly.
      _meta: { 'io.modelcontextprotocol.registry/official': { updatedAt: '2026-02-11T22:00:00.000Z' } },
    },
    {
      server: {
        // The remote branch of officialInstall: `remotes[0].url` wins over `packages`, and every
        // header with a name becomes a `requires` entry.
        name: 'io.acme/relay',
        description: 'Relay — hosted, needs a key',
        version: '3.0.0',
        remotes: [
          {
            type: 'sse',
            url: 'https://relay.acme.invalid/sse',
            headers: [
              { name: 'Authorization', description: 'Bearer <your Acme key>', isSecret: true },
              { description: 'a header with no name is dropped' },
            ],
          },
        ],
      },
      _meta: { 'io.modelcontextprotocol.registry/official': { updatedAt: '2026-06-15T08:00:00.000Z' } },
    },
    {
      server: {
        // `remote.type` that is not 'sse' becomes 'http', which is the other half of the same
        // branch. Both install shapes have to be in the compared body or the lane is asserting
        // the merge over one recipe.
        name: 'io.acme/vault',
        description: 'Vault — hosted over streamable HTTP',
        version: '2.1.0',
        remotes: [{ type: 'streamable-http', url: 'https://vault.acme.invalid/mcp' }],
      },
      _meta: { 'io.modelcontextprotocol.registry/official': { updatedAt: '2026-05-01T00:00:00.000Z' } },
    },
    {
      server: {
        // A REAL DEFORMITY, carried deliberately. `registry-search.json` — the recorded fixture
        // this item declined to re-record — contains `repository: "https://github.com/"`, an
        // owner-less URL the live official index really serves. `repoKey` parses owner/repo from
        // the path and returns nothing for it (src/registry.ts; RegistryMerge.swift:24-25), so the
        // row falls back to the normalised displayName for its identity and is never enriched
        // with stars.
        //
        // It is HERE because that is the one production shape `registry-search.json` was kept for,
        // and without it the deformity was in a fixture nothing compares while the corpus that IS
        // compared held only well-formed URLs. A Swift/TS disagreement on the empty owner — nil
        // versus a bogus key — would have surfaced at cutover against the live registries and
        // nowhere earlier.
        name: 'io.acme/ownerless',
        description: 'Ownerless — a repository URL with no owner/repo path',
        version: '0.1.0',
        repository: { url: 'https://github.com/' },
        packages: [{ registryType: 'pypi', identifier: 'ownerless-mcp' }],
      },
      _meta: { 'io.modelcontextprotocol.registry/official': { updatedAt: '2026-01-15T00:00:00.000Z' } },
    },
    {
      // The echo. No repository, so `keyOf` falls back to the normalised displayName and this row
      // cannot collide with anything above.
      server: {
        name: 'io.probe/echoed-query',
        description: `official received: ${query}`,
      },
      _meta: { 'io.modelcontextprotocol.registry/official': { updatedAt: '2026-01-01T00:00:00.000Z' } },
    },
  ],
});

/** The Smithery index: `{servers: [...]}`, a flatter shape with its own field names. */
const smithery = (query) => ({
  servers: [
    {
      // Same repository as io.acme/atlas, so the two merge into one `source: "both"` row.
      qualifiedName: 'acme/atlas',
      displayName: 'Atlas',
      description: 'Atlas on Smithery',
      homepage: 'https://github.com/acme/atlas',
      iconUrl: 'https://icons.acme.invalid/atlas.png',
      verified: true,
      useCount: 4200,
      remote: true,
      isDeployed: true,
      createdAt: '2026-04-01T12:00:00.000Z',
    },
    {
      qualifiedName: 'zed/cinder',
      displayName: 'Cinder',
      description: 'Cinder — smithery only, not deployed',
      homepage: 'https://cinder.invalid/home',
      verified: false,
      useCount: 900,
      remote: false,
      isDeployed: false,
      createdAt: '2026-03-20T06:30:00.000Z',
    },
    {
      qualifiedName: 'probe/echoed-query-smithery',
      // No displayName, so `s.displayName || s.qualifiedName` takes the qualified name — the
      // reference's `||` is ToBoolean and an empty displayName would do the same.
      description: `smithery received: ${query}`,
      useCount: 0,
      createdAt: '2026-01-01T00:00:00.000Z',
    },
  ],
});

const server = createServer((req, res) => {
  const url = new URL(req.url, 'http://127.0.0.1');
  // The raw query as received, so the echo reports exactly what the router sent — parameter order
  // included, since two routers building the same set in a different order is a real difference.
  const query = url.search.replace(/^\?/, '');

  const send = (status, body) => {
    const text = JSON.stringify(body);
    res.writeHead(status, { 'content-type': 'application/json', 'content-length': Buffer.byteLength(text) });
    res.end(text);
  };

  if (url.pathname === '/v0/servers') {
    if (FAIL === 'official') return send(503, { error: 'official index is down' });
    return send(200, official(query));
  }
  if (url.pathname === '/servers') {
    if (FAIL === 'smithery') return send(503, { error: 'smithery index is down' });
    return send(200, smithery(query));
  }
  // A 404 here would be indistinguishable from a router that asked for the wrong path and then
  // reported an empty registry, so it names itself.
  send(404, { error: `registry fixture has no ${url.pathname}` });
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`registry fixture listening on ${PORT}${FAIL ? ` (failing: ${FAIL})` : ''}`);
});
