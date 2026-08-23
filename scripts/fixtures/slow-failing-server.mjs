#!/usr/bin/env node
/**
 * A stdio MCP server that never completes the handshake and exits after a delay.
 *
 * The overlap lane needs one thing no other fixture provides: an index that stays open for
 * SECONDS and then fails. `mcp-fixture-server.mjs` answers instantly, which is right everywhere
 * else and makes the read-modify-write window this fixture exists to widen unobservable.
 *
 * It answers nothing at all, so the router sits in `initialize` until the process exits and the
 * transport closes under it — which is the `Connection closed` shape both routers already record
 * for a server that dies during its index. The delay is the point; the failure is what keeps the
 * watcher from adopting it, and an adoption would rewrite `servers.json` and, on the reference,
 * reach a hardcoded `launchctl kickstart` against the developer's own live router.
 */
const ms = Number(process.env.FIXTURE_FAIL_AFTER_MS ?? 6000);

// Hold stdin open so the parent's pipe stays up for the whole delay; without this the process
// would be free to exit as soon as the event loop drained.
process.stdin.resume();
setTimeout(() => process.exit(1), ms);
