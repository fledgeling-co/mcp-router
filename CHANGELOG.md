# Changelog

## 2026-09-29

### Added

- **Local stdio servers get their own `.env` / `.env.local`.** The router loads them from the server's package root — its `cwd` when set, otherwise the nearest manifest-holding ancestor of the entry script — and merges them under the entry's `env`. A new `envFile` field takes a path, a list, or `false`. Workspace roots are never inferred. Files are read at every spawn and their digest joins the config hash, so a rotated key re-identifies the server. `GET /servers/<name>` reports the resolved `envFiles`. (`15f1e473`)

  Before this, a server whose keys lived in its own `.env.local` started without them: `dossier`'s four paid research backends all reported "no credentials" while the keys sat in `packages/mcp/.env.local`, and the only fix was a hand-written `sh -c "set -a; . .env.local; …"` wrapper per entry.

### Known limitation

- Re-registering a server through `DELETE` + `POST /servers` does not restart a child that is already running, so new env reaches the process only after that child exits or the router restarts.
