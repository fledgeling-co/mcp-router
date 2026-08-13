# R1 — Swift router: core, config, manifest

**Depends on:** F1.

Begin the migration of the 3,605-line TypeScript router. **Swift ships alongside TS; TS
stays the installed default until the parity gate in R4 passes.** Neither the user's
working setup nor the installer changes in this item.

Port `src/config.ts`, `src/manifest.ts`, `src/log.ts`: reading and writing
`servers.json` and the tool manifest, client-config discovery, and the structured log.

Two traps recorded from the TypeScript build that must not be reintroduced:
- A flat `servers.json` loads **zero servers with no error** — `loadConfig` reads
  `raw.mcpServers`. The Swift decoder must fail loudly on a shape it does not recognise.
- The two dAIolog CLI configs use different TOML key shapes
  (`[mcp_servers.docker-mcp]` vs `[mcpServers."docker-mcp"]`).

Pin the Swift MCP SDK to an **exact** version: it is pre-1.0 and its README warns that
minor bumps may break.
