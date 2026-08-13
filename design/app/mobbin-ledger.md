# Mobbin reference ledger — mcp-router Mac app

Gathered 2026-08-13 via the mobbin MCP, nine searches, images opened and read.
This is the evidence the app's UI is built from; `design-craft` treats a direction
derived only from memory as the thing that produces "looks like every other app".

## Searches run

| Query | Platform | Useful |
|---|---|---|
| activity log list with timestamps and status indicators for each event | web | ~9 |
| connected integrations settings list with connect and disconnect buttons | web | ~7 |
| plugin or extension marketplace browse and install grid with trending and popular sections | web | ~6 |
| server instances list showing running and stopped state with health indicators | web | ~8 |
| compact status panel widget showing live connection state and quick toggle actions | ios | ~5 |
| storage cleanup screen listing unused large items with last used date and delete action | web | ~4 |
| API request inspector with request list on left and payload detail pane on right | web | ~7 |
| developer tool grouped sidebar navigation with sections and nested project items | web | ~6 |
| inactive members list showing last active date with option to remove or revoke access | web | ~5 |

## Took

1. **Stripe's log inspector** splits ~45/55, list keeping a fixed-width status chip column, then verb, then path — three hard-aligned columns so the eye scans one axis; the right pane repeats the selected row's header verbatim as its title. [screen](https://mobbin.com/screens/83fcb007-5a4a-499a-9ef3-c22fad338955)
2. **Neon** puts state as a text-plus-dot pill inline with the compute name, not in its own column — `● SUSPENDED` sits immediately right of the row title at label size, so state reads as an adjective on the thing. [screen](https://mobbin.com/screens/400c0d93-8e99-43b5-a649-c23b3f0136a9)
3. **Modal** segments one list by lifecycle with count-bearing tabs — `Live Apps 1` / `Stopped Apps 3` — so the idle set is a first-class destination. This is the cleanup view. [screen](https://mobbin.com/screens/02ef5fde-c7b4-4167-8344-308c019d49c0)
4. **Toggl**'s audit log renders a per-row change diff as two pill tokens joined by an arrow, `From None → To 45 USD`, at ~11px in a tinted capsule. [screen](https://mobbin.com/screens/2deef352-1f6b-4757-a4c9-dcce106b0e6a)
5. **Square** groups activity under sticky uppercase date headers and drops the date from the rows, leaving `6:19 am`. [screen](https://mobbin.com/screens/4c14b94a-4abc-4e9b-aa97-de2006ca8498)
6. **Fibery**'s log is a spreadsheet grid with a row-number gutter, `Entity / Event / When / Who / What Changed`, and relative `When` (`10 min ago`). [screen](https://mobbin.com/screens/e2d656a6-35ba-4e9a-b5c7-a14e4fa61bb3)
7. **Replit** ships a literal "MCP Servers" table: name + icon, description, `Connection Status ● Active`, and `Disconnect` as a quiet outlined button in the trailing cell — not hidden in an overflow menu, because there is one action per row. [screen](https://mobbin.com/screens/718e8393-29d9-474c-8a40-c798cc577ea9)
8. **Apollo** splits integrations into `Connected integrations 3` and `Available 30` collapsible sections sharing one column header, the action verb flipping per section. One component, two states, no tab switch. [screen](https://mobbin.com/screens/4d8f6c81-5562-4a49-ae10-49f830806ee7)
9. **Base44** floats the request log as a right-edge overlay with `6 requests 0 logs` as a counter line — a full inspector that never takes the main canvas. [screen](https://mobbin.com/screens/058c7aea-a3fc-4023-9513-35efda53b6b4)
10. **Coinbase** stacks a horizontally scrolling "New and trending" rail above a ranked `Rank / Name / Category / Rating` table of "Popular apps" — browse and compare are two affordances, and the ranked table is where install decisions get made. [screen](https://mobbin.com/screens/28ae4883-ae2a-4acc-afba-0ef06ba34de2)
11. **Jira**'s marketplace card carries trust as small badges above the title plus `3.7/4 ★★★★ (819)` and `36.1K` downloads on one line. [screen](https://mobbin.com/screens/d8ef5d79-a346-4974-8968-1d25b8b5223e)
12. **Tailscale**'s machine table is the closest structural match to a server list: a two-line leading cell (name over owner) carrying identity+scope, every other column single-line, `LAST SEEN ● Connected`, trailing `···`. [screen](https://mobbin.com/screens/4e6b5e40-1d4d-4b51-971f-49dfdd49a5e1)
13. **Customer.io** pairs a health verdict card with "Archive suggestions — Nothing worth cleaning up right now": the cleanup surface has a designed *empty* state that reads as reassurance. [screen](https://mobbin.com/screens/b9743841-5a29-4454-bc39-133d7b0d7d9c)
14. **NordVPN**'s widget family shows the same content at three sizes, degrading by dropping the Recents strip rather than shrinking type. This governs the menu-bar popover. [screen](https://mobbin.com/screens/198cc47b-b67e-4ed4-bbb0-8b48dc48a0ce)
15. **Linear**'s sidebar separates `Workspace` from `Your teams` with tiny uppercase group labels and no dividers; view options live in a popover, not a settings page. [screen](https://mobbin.com/screens/815793b1-5c75-43ac-94c7-93380781e337)
16. **Gemini Exchange**'s user table has a `Last signed in` column whose values include a literal `Never`, plus a `Show inactive users` checkbox — "never used" is a value in the column, not a separate screen. [screen](https://mobbin.com/screens/af6cd8fd-fad7-4de9-b04a-c447a600ccd8)

## Left

- **Discord's audit rows with a 32pt avatar and full-width chevron card** — avatar-per-row is social furniture; a tool call's actor is a project path, and card chrome wastes the vertical budget a dense list needs.
- **Unity/Wix trending tiles with full-bleed marketing art and strikethrough pricing** — MCP servers have no hero art and no price; imagery-led browse forces placeholder graphics, which reads as filler.
- **The trash-can metaphor (Drive Bin, Figma Trash)** — a never-used server was never deleted, so restore/purge misframes it. The frame is "idle, consider removing", closer to Modal's Stopped tab.
- **Railway's canvas of draggable service nodes** — implies a topology between servers that does not exist, and a pannable canvas is deeply non-native inside a NavigationSplitView.
- **Zoho's modal execution preview with raw JSON in a blocking dialog** — a modal breaks the scan-and-select rhythm of a log; on macOS this is an inspector pane or a sheet attached to the row.
- **AWS Health's service × day green-tick matrix** — answers a question nobody asks of a local router, and an all-green field trains the eye to ignore it.

## Density

The log references that work run tight: Stripe, Fibery and Supabase sit at roughly
26–30pt rows with 11–12px body, one line per event, no avatars. Supabase goes
furthest — monospaced timestamp (`11 Aug 19:34:32`), a 3-digit status chip and a
path on one baseline, ~20 rows above the fold. Column widths are fixed and
left-aligned so status chips form a vertical rule down the leading edge; only the
last cell is variable-width. Where a row must carry two facts, the second line
drops to ~10px at ~55% opacity rather than adding a column. Fibery's row-number
gutter and hairline borders are right for a table you scan for anomalies and too
heavy for a popover — the compact surfaces (NordVPN, WHOOP) hold at 44pt rows with
15–17px titles and cut *content* rather than type size to fit.
