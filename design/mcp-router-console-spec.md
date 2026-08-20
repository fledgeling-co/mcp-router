# MCP Router — Console: design delivery

Artifact: `design/mcp-router-console.html` · 4,223 lines · self-contained (0 external references) · built from `PRD.md`, deliberately ignoring the project's existing `DESIGN.md` and `design/mocks/prototype.html` per the brief.

## Direction

**Patchbay** — a light-first precision routing console. The subject is a signal router, so the design language comes from routing hardware rather than from dashboard convention: a **signal path** across the top of the Servers board reads *harnesses → one endpoint → eleven upstreams*, and each upstream is a **jack** whose plug lights the instant something calls it and goes dark when the reaper closes the child. State is carried by the plug and the jack's border, never by colour alone — every jack also names its condition in words (`3:41 left`, `tripped`, `2 held changes`, `needs sign-in`).

Ground is white with a graphite chrome step (`#F1F1F4` sidebar against `#FFFFFF` content), the system accent for selection and rings, and three indicator hues that each carry a text-safe twin. Type is the platform stack (`-apple-system`) with `ui-monospace` for anything the user could paste into a terminal — commands, paths, tool names, durations, hashes. No display face, because an app that rewrites `~/.claude.json` earns trust by looking like the system, not by having a voice.

**Runner-up: Blueprint Graphite** — a dark technical drawing with hairline rules and cyan annotation. Rejected because the project's prior design was already dark graphite, so it would have read as a re-skin rather than a decision, and because the boards that matter most (Harnesses, Cleanup, Checks) are dense reading surfaces where a light ground is simply easier.

**Deliberately avoided**: Warm Paper and Terminal Dark, which `mac-craft` records as simultaneously corpus-proven *and* the two looks this model defaults to; Space Grotesk/Inter as "distinctive" faces; tracked-uppercase section headers (the corpus's loudest web tell); `cursor: pointer` on any control; and the `border-radius: 12px; border-left: 4px` default card — `border-left` appears only on the attention band, where the emphasis is semantic.

**Risk in this direction**: the patchbay is a metaphor, and a metaphor that stops matching the data becomes decoration. It survives here only because every element of it is observed — the plug states are the router's real lifecycle, the "0 at rest" in the hub is the product's whole thesis, and the arrow count is the actual topology. If the router ever pools differently, the signature has to change with it rather than be kept for its looks.

## Signature and its provenance

The Signal Path band is the one element that exists nowhere in the corpus and could not be derived from it. Everything around it is corpus-canon: a 256px source-list sidebar with sentence-case section headers and r8 inset-rounded accent selection; a 52px unified toolbar; grouped inset settings cards on a shared label/control axis with native capsule switches and double-chevron pop-ups; sheets that drop from the titlebar rather than floating as modals.

## Settings is a window, not a board

Settings has its own window rather than a tenth board, because that is what the corpus does: all eight settings surfaces in `mac-craft`'s pattern set are separate windows, and the tell that identifies one at a glance is **minimise and zoom greyed out** while close stays live. That is built here, and it is the reason Settings also left the console's source list — on macOS a settings window is reached from the app menu (⌘,), never from a navigation list, so the sidebar now ends at Insights and the health card sits directly under it.

Seven panes in a 200px source list at the kit's Medium row height, r8 accent selection: **Router · Harnesses · Session analyst · Updates · Security · Menu bar · Advanced**. Seven is past the point where a preferences tab bar works, which is what makes a sidebar the right call rather than a preference. Each pane opens with a hero header — its name and one line saying what it governs — then the grouped inset cards the corpus calls canon: label left, control right on a shared axis, inset hairlines between rows, native capsule switches and double-chevron pop-ups. Nothing has a Save button, because every control applies on change.

The window opens from the app menu, ⌘, or ⌘0, and from the Window menu, where a tick tracks whether it is open. Escape closes it. While it is frontmost it owns the state the preview control drives, and the console's own toolbar and tallies are left alone — a second window does not get to rewrite the first one's chrome.

## State matrix — 40 of 40 cells built

Nine boards and the Settings window, four states each, every cell carrying its own copy rather than a shared template. The chrome follows the state: the toolbar subtitle and the sidebar tallies change with it, and the sidebar health card cannot say "Router serving" over a board that says the router is unreachable.

| Board | ideal | empty | loading | error |
|---|---|---|---|---|
| Servers | 11 declared, 2 awake | No servers adopted yet | Indexing each server once | Cannot reach the router |
| Activity | live stream, 1,482 calls | Nothing has called a tool yet | — | The event stream dropped |
| Harnesses | 6 detected, 2 want a decision | No AI harnesses found | Reading six configuration files | Codex's configuration would not parse |
| Skills | 38 installed, 1 held | No skills installed | Fetching fledgeling-plugins | Doctor found 3 broken links |
| Discover | 4 results for "postgres" | No results for "kubernetes log tailing" | Asking both indexes | One index answered, the other did not |
| Inbox | 3 undecided | Nothing is waiting on you | Installing postgres-mcp | postgres-mcp failed to install |
| Insights | 9,418 calls, analyst ran | Not enough history yet | Analysing your sessions | Primary analyst hit its limit, fallback ran |
| Checks | 4 suites, 1 stale | Nothing here ships a check suite | Running trawl · 1.5.0 | 2 of 11 checks failed |
| Cleanup | 3 never called, 2 quiet | Everything installed has been used | Counting 90 days of calls | The usage store only goes back 6 days |
| Settings *(window)* | seven panes | Settings unavailable while stopped | Reading the router's configuration | Response this version does not understand |

Two conditional states beyond the six: **overflow** is exercised (11 upstreams in a 250px jack field, a 7-column table beside a 340px inspector, 18 Antigravity servers in a diff) and **disabled** is exercised on 11 rules. **Offline** is `n/a` — the router is loopback-only, so there is no network for the app to lose.

Twelve sheets, each a decision with its evidence attached: pair, reconcile, quarantine, readme, capability-delta, add-server, add-marketplace, recommendation, queued-detail, analyzer, path, confirm-remove.

## Destructive actions and their gates

| Action | Blast radius | Gate built |
|---|---|---|
| Remove 10 duplicates from `~/.gemini/settings.json` | someone else's config file | full unified diff, before/after counts, "Open the file instead", named-consequence button |
| Remove selected (Cleanup) | installed capability | checkbox multi-select, named count, 30-day undo window stated on the surface |
| Accept both held schema changes | a tool regains callability | both diffs shown, schema *and* description, with the reason it was held |
| Disable mobbin | one server stops answering | quiet destructive-red text button, not the primary |
| Trip breaker / Wake now | one child process | none — reversible in one press, and the state is visible |
| Approve a phone-queued install | executable code on this Mac | phone queues only; the Mac shows tools + capability summary and asks |
| Stop Router | every session loses its tools | menu item, no accelerator |

No action in the file is gated by a toast alone, and no reversible action asks "are you sure".

## Token table

Thirty metric rows, each tagged with where its number comes from. `kit` values are Apple's published control and window metrics; `corpus` is the cross-app synthesis; `research` and `direction` are this design's own decisions, and are marked as such rather than dressed as measurements.

| Tier | Rows |
|---|---|
| `kit` (19) | titlebar 33 · unified toolbar 52 · compact toolbar 40 · control tiers 16/20/24/28/36 · body 13 · sidebar 256 · sidebar rows 32/40 · selection radius 8 · popover radius 20 · scrollbar 12 · accent `#0088FF` · live `#34C759` · attn `#FF8D28` · fail `#FF383C` |
| `corpus` (1) | card radius 10 |
| `research` (1) | accent-ink `#0071E3` |
| `direction` (9) | accent-text · live/attn/fail inks · ground · chrome · panel · jack lane 44 · grid unit 8 |

**The accent had to be split, and the split is the honest exit the gate names.** Apple's published system Blue measures 3.52:1 against white, below the 4.5:1 floor for a 13px label. Rather than shipping the platform's own number as if it passed, `--accent` stays the kit hue for rings, plugs and tints, and `--accent-ink` (`#0071E3` light / `#0A6FD6` dark) carries any accent surface with text on it — 4.70:1 and 4.93:1. Every indicator hue has the same twin: `--live-ink`, `--attn-ink`, `--fail-ink`, each solved against all three grounds, plus `--shield-good` and `--badge-bg` for the two filled badges that carry white.

89 colours live in the token block and **zero colour literals appear outside it**, across six appearance contexts: light, dark, `.is-light`/`.is-dark` for the in-mock switch, and two *separate* increased-contrast blocks — authored per appearance, because one scheme-agnostic `prefers-contrast` block paints dark ink on a graphite ground in whichever of the two it wasn't written for.

## Audits

| Audit | Result |
|---|---|
| `mock_check.py --interactive` | **exit 0** — 0 failures, 3 notes, 0 unmeasurable |
| contrast | **5,788 pairs, 0 failures, 0 unresolved**, across 4 contexts (light, dark, light+contrast, dark+contrast); 60 disabled-tier pairs exempt under WCAG 1.4.3 incidental |
| `ux-lint.py --static` | **exit 0** — 0 failures, 0 warnings, 3,213 elements |
| `design-lint.py` | exit 1 — 14 criticals, all instrument disagreements (below); 3 majors, all false positives; 21 minors, 18 of which are JS property accesses parsed as CSS classes |
| tokens | 89 token-block colours, 0 literals outside |
| casing | 398 rules, 0 tracked-uppercase, 0 uppercase at heading size |
| cursor | 398 rules, 0 `pointer` |
| keyboard | 4 `:focus-visible` rules, 208 roles, 354 semantic controls, 0 clickable non-semantic elements |
| a11y media queries | 3 of 3 present (`prefers-contrast`, `prefers-reduced-transparency`, `prefers-reduced-motion`) |
| content | 0 lorem, 0 template placeholders, 4 marked placeholders — all `[YOU]` standing in for the real home-directory username |
| glyphs | 37 icons, all hand-drawn inline SVG on a 16px grid at one stroke weight. None substituted, none a marked box. |

**The 14 design-lint criticals, named rather than waved away.** Eleven are `--on-accent` (white) or `--t4` (disabled) measured against the page's `body` background, because that script has no ancestry model and composites every rule against one ground; `mock_check` walks the actual ancestor chain in four appearance contexts and passes all of them. Three are `outline: none` reported without noticing the `:focus-visible` replacement two lines below. Both classes were confirmed by reading the two scripts, not assumed.

## Defects found by looking, and fixed

The renders caught eleven things the gates could not, which is the argument for opening the file rather than reasoning about it:

1. The window collapsed to its 52px toolbar — `height: 100%` on a grid item under `place-items: center` is circular.
2. Every progress bar painted empty: `.fill` is a `<span>` with no `display`, so it was inline and ignored `width` entirely. **This one would have shipped broken in any browser.**
3. Every button label wrapped out of its fixed-height box.
4. The servers table ran under the inspector pane — a flex child floors at min-content without `min-width: 0`.
5. Seven columns do not fit beside a 340px inspector; the table now drops its two least load-bearing columns in the paned layout.
6. The menu-bar app name wrapped onto two lines.
7. The empty and error states were shown over chrome still counting eleven servers, and the sidebar health card said "Router serving" over a board saying the router was unreachable.
8. The Discover result count said seven over four rows; the Checks header said six suites and two stale over four suites and one.
9. The analyst table truncated the model names — the one thing that table exists to say.
10. Buttons and shortcuts inside the notification's live region, which assistive technology flattens to plain text; the announcement is now a permanent clipped region written into on fire, and the banner is a group.
11. The jack field ran eleven rows deep at the real window width, pushing the table off the board.
12. Splitting Settings into its own window gave the file two source lists sharing one row class, and the console's board switcher was clearing the settings panes' selection through an unscoped `$$('.side-row')` — the selected pane rendered with no fill at all.

## What was NOT checked

- **Motion is specified, not measured.** Obscura runs no CSS animations and `document.getAnimations()` returns 0, so the jack transitions, the sheet entry, the notification slide and the skeleton shimmer are source claims. A mid-flight capture equals the at-rest capture here.
- **The three accessibility media queries are specified, not measured.** `Emulation.setEmulatedMedia` is accepted and inert on this engine, so `prefers-contrast`, `prefers-reduced-motion` and `prefers-reduced-transparency` were authored and contrast-checked from source across four contexts, never rendered.
- **Type fidelity is unmeasured** — no web fonts load on this engine. The `-apple-system` stack is a source claim about what a Mac would resolve.
- **Sheet stacking is unverified on this engine.** Obscura paints in a flat order and does not honour stacking contexts, so board text composites over any overlay regardless of `z-index`; established through four probes, including one that painted a red test fill *behind* the board's text. The scrim (`z-index: 200`) and sheets are correct CSS and were read by hiding the boards. This needs one look in a real browser.
- **Screen-reader output, real keyboard traversal and assistive-technology behaviour** — these need a device and a person. The roles, labels, focus order and key handling are authored and linted; none of that is a conformance claim.
- **Coverage of the looking itself: 27 surface renders examined of roughly 90 possible** (10 boards ideal-light, 3 further states on Servers, 1 board dark, 6 sheets, 1 menu of 9, the status popover, the notification, and the Settings window in two panes plus its error state). Five of the seven settings panes were never rendered. The 40-cell state grid was verified structurally in the DOM and by reading every variant's copy, not by capturing all 40. Nine boards were not seen in dark, six sheets and eight menus were not captured, and the increased-contrast appearances were not rendered at all.
- **Every viewport but one.** All captures are a 1280×720 viewport; the mock is authored for a 1320×860 window and has one breakpoint at 1180px that was never rendered.
