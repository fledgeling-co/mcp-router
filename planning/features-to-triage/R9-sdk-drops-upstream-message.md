# R9 — the upstream's own words survive the SDK that drops them

**Status:** implemented on `ai/r9`, tests green and armed, parity pending.
**Closes:** DEF-047. **Unblocks:** R8's Swift half.

## What is wrong

`modelcontextprotocol/swift-sdk` 0.12.1 decodes a JSON-RPC error, reads the server's
`message`, then maps the code. `-32700`, `-32600`, `-32601` and `-32602` each pass
`unwrapDetail(message)`; `-32603` alone passes `unwrapDetail(nil)`
(`Sources/MCP/Base/Error.swift:217-240`). `unwrapDetail(fallback)` returns `data.detail`
when present and the fallback otherwise, so a server that answers `-32603` with a message
and no `data.detail` has that message discarded, and `Error.swift:91` renders
`"Internal error"` alone.

`-32603` is the code servers use for an arbitrary application error, so it is the one
that loses the most. Measured 20 Aug 2026 against a fixture returning
`Internal error: Authentication required`: the TypeScript reference recorded the whole
sentence, the Swift router recorded `[-32603] Internal error`.

Two consequences. For the whole class of `-32603` upstream errors the Swift router tells
the user strictly less than the reference does. And R8's Swift half cannot detect a
credential refusal, because the text its predicate matches on is exactly the text the SDK
threw away.

## What was done

`RawRequest.perform` claims the tapped response bytes when `context.value` throws, and
reads the `error` member off the wire.

The seam was already open and was opened for the same reason. `TappingTransport.receive`
records every frame before it yields it — the decorator this file has carried since R1,
because the SDK also destroys member order — so the response the SDK is currently failing
to describe was captured strictly before the throw. Nothing new is intercepted; an
existing recording is read.

`UpstreamRPCError` reports only what it read:

- Both `code` and `message` are required. A frame carrying one without the other is not a
  JSON-RPC error object, and reporting a partial read as a whole one puts a guess where a
  reading belongs.
- A response with no `error` member produces nothing, and the SDK's own error stands.
  That is the honest outcome when there is nothing better to say.
- The server's `message` is used verbatim and never prefixed with the canonical name for
  its code. A server answering `-32603` typically sends a message that already begins
  "Internal error", so composing one renders it twice.
- The reader is not special-cased to `-32603`. A reader that only works on the code in the
  defect report is a workaround rather than a reading, and there is a test that says so.

## Why read rather than fork

DEF-047 listed three options: report it upstream, pin a patched swift-sdk, or read the
JSON-RPC error below the SDK.

Reporting it upstream does not fix the router. Pinning a fork takes on a forked dependency
— its own update path, its own drift, its own review surface — for a defect that one local
read closes. The SDK is still wrong and that is still worth reporting; this stops the
router repeating it.

## Evidence

Seven tests in `UpstreamRPCErrorTests`, armed against the SDK's own behaviour rather than
against a deletion: dropping the message the way `unwrapDetail(nil)` does takes 5 of the 7
red. The other two stay green by design — they assert the reader returns nothing on a
result and on a partial error object, which is true before and after, and an arm that
turned them red would mean the negative cases were reading something they should not.

Clean baseline in this worktree 1518 tests in 189 suites; with this, 1525 in 190 — the
`git stash` arithmetic reconciles exactly. `swiftformat` 0 of 487 files require
formatting, `swiftlint --strict` 0 violations in 480 files, both design-value lints pass.

## Scope

Touches `src/`, `install.sh` and `package.json` not at all, so `StandingConstraintsTests`
A38 holds. Independent of R8: R8 needs this, this does not need R8.
