# spec-M30 — where a capability document actually comes from

**Depends on** M19 (the renderer, the shield parser, the image resolver, the three-tab panel — all
measured under M23). **Supplies** a second implementation of `CapabilityDocumentSource`, the route
that feeds it in both routers, and the entry point that opens the panel.

The owner decision is made and is binding: **the router serves real documents**. The brief's "do
nothing" alternative is closed and is not re-argued here.

---

## 0 · What this item is not

It does not rebuild the parser, the shield re-drawer, `PackageImageResolver`, `MarkdownLimits` or
`CapabilityDocumentSheet`. It does not build a skills inventory. It does not make the registry
download anything. Everything below is a route, a wire shape, a client, one source implementation,
and the sheet-inventory case that makes the panel reachable.

---

## 1 · The route, and why it hangs off a server

`GET /servers/:name/document`

Three candidate subjects were available and two of them cannot be served honestly today.

- **A skill.** `Skill.path` is a resolved real path, which is what the brief noticed. But neither
  router serves `/skills` at all: `ControlPaths.isControlPath` admits `/servers`, `/usage`,
  `/registry/`, `/harnesses` and `/insights`, and `LiveControlAPIClient+Absent.swift` treats a
  `/skills` 404 as version skew precisely because no router answers it. A document route keyed on a
  skill would need a skills inventory in both implementations first, which is its own item.
- **A registry entry.** `RegistryEntry` is a remote search result merged from two indexes. Nothing
  is downloaded, so there are no bytes on this machine to read.
- **A declared server.** The router holds it in its own config, and for a stdio upstream that
  config carries `cwd` — the directory the router *passes to the child it spawns*. That is
  observation rather than inference, and it is the only package root any wire type carries.

So the package root is `upstream.cwd`, **and only that**. Deriving a root from `args[0]`'s directory
is refused by name: it is a guess about a packaging convention the router does not otherwise use,
and §6's rule is about where a figure came from rather than how plausible it is.

`ServerRoute`'s sub-path grammar already accepts a lowercase-letter segment, so `/document` needs no
change to `isControlPath` and no change to the route regex in either implementation. The route
inherits the existing unknown-server 404, the 405 fallback, and the (deliberately ungated) GET path.

`command`, `args` and `env` stay unwritable through PATCH. This route reads and returns bytes; it
mutates nothing.

---

## 2 · The three questions the triage named

### 2.1 · Which of the five facts-strip cells does the router genuinely observe?

The fixture's strip carries `Kind`, `Version`, `Licence`, `Runs in`, `Reads`. One answer each.

| Cell | Verdict | Why |
| --- | --- | --- |
| **Kind** | **observed — served** | The transport is in the router's own config and decides how the child is started. It is served as the transport word (`stdio`, `http`, `sse`), never as the fixture's `Skill · no server`: this router has no skills inventory, so it cannot know that a capability is a skill. |
| **Version** | **not observed — absent** | No wire type carries a version for an installed upstream. The manifest records `builtAt` and a digest, not a version. Reading a `package.json` would be reading a convention the router does not otherwise use, and the answer would be the version of whatever happens to sit in `cwd`. |
| **Licence** | **not observed — absent** | The router can observe that a file named `LICENSE` exists. It cannot observe that its contents are MIT, and `Licence · MIT` is the claim the cell would be making. Identifying a licence from its text is a derivation. |
| **Runs in** | **not observed — absent** | `/insights` and `/harnesses` observe which harnesses point at **the router**. Nothing observes which harnesses can run **this capability** — that is a skills-side fact and there is no skills side. |
| **Reads** | **not observed — absent** | Nothing in the router observes what a child process reads. The fixture's `4 session stores, locally` is invented and is labelled as such in its own file. |

One of five survives. That is the honest count, and `CapabilityDocument.Fact` is already a list
rather than five named fields for exactly this reason — the type's own comment says a fact nobody
observed must be **absent** rather than empty.

Two further cells are served **because they are observed**, rather than because the mock drew them:

| Cell | When it is served | What the router observed |
| --- | --- | --- |
| **Tools** | only when the manifest holds an approved entry for this server | the router connected to the child and listed its tools; the count is the length of that approved list |
| **Served to** | only when the server declares a non-empty `projects` list | the visibility restriction the router itself applies when deciding whether to publish the server's tools |

A server with no manifest entry gets two cells. A server with one gets three. The strip's width is a
function of what was observed, which is what §6 asks for.

### 2.2 · Do images travel as bytes on the wire?

**Yes — base64 in the response envelope, one entry per reference the documents name.**

M19's resolver returns bytes rather than paths so that nothing downstream of `CapabilityDocument`
holds a path a view could be talked into opening. A wire shape that carried references instead
would put that decision back in the app, and A36 forbids the app resolving it. So the router
resolves every reference, reads the bytes, and sends them.

Consequences that follow and are built rather than assumed:

- The router needs its own **image-reference scan** over the markdown, because it decides which
  files to read. It is the same hand-scan `MarkdownParser.inlineImages` performs — `![alt](ref)`
  with balanced parentheses and a title dropped at the first space — ported to both
  implementations and pinned by a parity vector. A router that extracts a different set of
  references sends a different set of bytes, which is a divergence the app cannot see.
- The router needs its own **resolution and refusal** logic, mirroring `PackageImageResolver`:
  scheme-first, then absolute paths, then a symlink-resolved component-prefix containment check.
  This is the traversal boundary and it is on the router's side of the wire.
- The **response never carries the package root.** The app is not told where the package is, so
  there is nothing in the payload it could open even if it tried.

A reference that is refused travels as a refusal with its reason, so the panel draws M19's
placeholder sentence rather than dropping the figure.

### 2.3 · What is the transport size cap?

`MarkdownLimits` caps the **parse**, in the app, after the bytes have already crossed the wire. It
is not a transport cap and cannot become one. The transport gets three of its own, and **every
refusal names which cap it hit**:

| Cap | Value | What it bounds | What happens when it is hit |
| --- | --- | --- | --- |
| `documentBytes` | 524288 (512 KiB) | one markdown file | the whole request refuses `413` with `reason: "documentTooLarge"`, `cap`, `limit`, `actual` and `file` |
| `imageBytes` | 2097152 (2 MiB) | one image | that image travels as a refusal carrying its limit; the document still travels |
| `imageBudgetBytes` | 8388608 (8 MiB) | every image in one response, together | once spent, every remaining image is refused `budgetExhausted` in document order |

A document over its cap refuses the request rather than truncating: appending a note into the
markdown would be inventing content into a document the app is about to render as the package's own
words, and silently shortening is the failure `MarkdownLimits`' own comment refuses.

At most three documents at 512 KiB is 1.5 MiB, so the documents always fit inside a response whose
images are separately budgeted. The largest response this route can produce is bounded at
1.5 MiB + 8 MiB before base64 expansion.

---

## 3 · The wire

### 3.1 · Success

```json
{
  "server": "trawl",
  "facts": [{ "label": "Kind", "value": "stdio" }, { "label": "Tools", "value": "17" }],
  "documents": { "readMe": "# trawl\n…", "changelog": "…" },
  "images": [{ "reference": "docs/matches.png", "media": "image/png", "base64": "iVBOR…" }],
  "refusedImages": [{ "reference": "../secrets.png", "reason": "escapesPackage" }]
}
```

`documents` carries at most the three fixed keys `readMe`, `changelog`, `capabilities`, in that
order, read from `README.md`, `CHANGELOG.md` and `CAPABILITIES.md` at the package root. A key that
is absent means the package published no such file — which is the distinction
`CapabilityDocument.tabs` already draws, and the panel already says which document is missing.

`images` and `refusedImages` are arrays rather than objects, in document order, because member order
is a wire fact in this repository and an array states it.

### 3.2 · Refusals

| Status | `reason` | When |
| --- | --- | --- |
| 404 | — | no server of that name (the route's existing behaviour, unchanged) |
| 404 | `noPackageDirectory` | the server declares no `cwd`, so there is no package to read |
| 404 | `packageUnreadable` | a `cwd` is declared and is not a readable directory |
| 404 | `noDocuments` | the package carries none of the three files |
| 413 | `documentTooLarge` | a markdown file is over `documentBytes` |

Every refusal body carries `error` — the sentence — alongside its machine-readable `reason`, in the
shape every other control refusal uses.

### 3.3 · Image refusal reasons

`remote` (with `scheme`), `absolutePath`, `escapesPackage`, `notInPackage`, `unsupportedType`
(with `extension`), `tooLarge` (with `limit`), `budgetExhausted`.

The first four are `PackageImageResolver.Refusal`'s existing cases and keep their existing
sentences. The last three are new, and their sentences are added beside the others so the panel has
one wording per state.

`unsupportedType` is a boundary rather than a convenience: an image reference is a request to read a
file, and the set of things the app will render as an image is `png`, `jpg`, `jpeg`, `gif`, `webp`.
`svg` is deliberately outside it — it is a document format that can carry script, and nothing in
this panel needs one.

---

## 4 · The app side

- `ControlAPIClient` gains `capabilityDocument(for server: String) -> CapabilityDocumentPayload`.
  A 404 whose body carries **no** `reason` is version skew and maps to `malformedResponse`, in the
  family `LiveControlAPIClient+Absent.swift` already names. A 404 that carries a `reason` is this
  route answering, and maps to the matching `CapabilityDocumentError` case.
- `ControlAPICapabilityDocumentSource` is the second implementation of `CapabilityDocumentSource`:
  it calls the client, parses each document with `MarkdownParser` under `MarkdownLimits`, decodes
  the images, and maps the refusals. It holds no path and reads no file.
- `UnavailableCapabilityDocumentSource` stays, and `CapabilityDocumentError.notServed` stays
  reachable: it is what a surface with no control client answers, and it is what the phone shell
  answers. Its test stays.
- `CapabilityDocument.Identity.publisher` and `.pitch` become optional, and
  `CapabilityDocumentHeader` omits the row rather than drawing an empty one. The router observes
  neither for an installed upstream, and an empty `Text` in that stack reserves layout for a fact
  nobody has. The fixture keeps supplying both, so M23's captured layer tree is unchanged.

---

## 5 · The entry point

`RouterSheet.Kind.readme` exists in the inventory today, is drawn in the console mock as `sh-readme`,
and declares `owner == "M19"` — the marker for *drawn in the mock, hosted by nothing*. M30 hosts it:

- `RouterSheet.Servers` gains `case document(server: String)`, mapping to `Kind.readme`.
- `Kind.readme.owner` becomes `nil`, so `isHosted` is true.
- `allPresentable` gains the case.
- The Servers board presents `CapabilityDocumentSheet` for it, driven by
  `ControlAPICapabilityDocumentSource`.

`RouterSheetTests`' census of unhosted kinds moves from four to three. That assertion is the
inventory this item deliberately changes; it is disclosed in the completion record rather than
folded into the diff quietly, and the replacement is strictly stronger — it asserts that `readme`
is now hosted **and** that the remaining three are M22's.

---

## 6 · Parity

Two implementations of one route diverge silently unless vectors force them to agree. Three new
vector files, generated from the TypeScript reference by `scripts/parity/generate-vectors.mjs`:

| File | Function | What it pins |
| --- | --- | --- |
| `document-image-refs` | the image-reference scan | balanced parentheses, a dropped title, `!` not followed by `[`, an unterminated span, several per line, an empty reference, a nested bracket |
| `document-resolve` | resolution against a package root | every refusal case, the `pkg-evil` string-prefix trap, a symlink out of the package, a `..` climb that lands back inside |
| `document-caps` | the three caps | which cap fires, in what order, and what the budget leaves for the images after it |

Each is registered in `VectorRegistry` with the rows it speaks for and a consumer that returns its
own executed count, and `executedFloor` rises by the number of cases added — the harness refuses a
corpus that executed fewer.

`src/control.ts` gaining a dispatch line means `parity-manifest-check.sh` demands a `control` row for
`GET /servers/:name/document` and the `# rows:` pin moves in the same change. Both routers answer the
route, so it is a `control` row and not a `divergence` row.

`control-differential.sh` gains rows driving the route at both binaries over a real socket: the
success path, `noPackageDirectory`, `noDocuments`, and the traversal reference.

**The vectors are armed, not assumed.** A divergence is planted in one implementation, the gate is
watched going red, the implementation is restored byte-identically, and the before/after hashes are
reported in the completion record.

---

## 7 · Acceptance

| # | Clause |
| --- | --- |
| A1 | `GET /servers/:name/document` is answered by both routers and returns the package's own `README.md`, `CHANGELOG.md` and `CAPABILITIES.md` where they exist |
| A2 | The facts strip carries only observed cells, per §2.1, and never `Version`, `Licence`, `Runs in` or `Reads` |
| A3 | Images travel as base64 bytes; the response carries no package path |
| A4 | An image reference outside the package is refused, with no bytes read, by both routers |
| A5 | Each of the four request refusals answers with its own `reason` and its own sentence |
| A6 | A document over `documentBytes` refuses 413 naming the cap, the limit, the actual size and the file |
| A7 | `CapabilityDocumentError.notServed` stays reachable and tested |
| A8 | The three new vector files are executed by the parity suite and the floor rises to match |
| A9 | `RouterSheet.Kind.readme` is hosted, and the Servers board presents the panel |
| A10 | A planted divergence in one implementation reddens the vectors; restoring it byte-identically returns them to green |
