# Mobbin trawl — round 2: marketplace, discovery, pairing

Round 1 (`mobbin-ledger.md`) covered the Mac log/server surfaces. This round covers what
the app grew into: a manager for **two** kinds of installable capability (MCP servers and
skills/plugins) with a phone companion. Three searches, images opened rather than listed.

## The closest existing analogue: Obsidian community plugins (iOS)

Worth naming separately because it is the same product problem, shipped. It is a store for
third-party bundles that execute code inside the user's tool, from an open community, with
no app-store review in between.

What it does, in order: **Restricted mode is ON by default** and community plugins simply
do not run. Turning it off raises a sheet that does not say "are you sure" — it lists the
four things that actually protect you (initial code review, open source so you can inspect
it, peer audit, report mechanism), then says *"We strongly recommend making backups of your
data before doing so."* Only then, the purple button. Afterwards the settings page carries
**"Automatically check for plugin updates"** as an explicit toggle, and **"You currently
have 0 plugins installed"** stated as a fact rather than an empty illustration.

**Took:** the restricted-by-default posture; the enumerate-the-mitigations sheet in place of
a yes/no confirm; auto-update as a visible toggle rather than a silent default; the count
stated in prose.
**Left:** the modal-on-modal stack (two sheets deep before you have installed anything) —
on macOS this belongs in an inspector, and on iOS in one sheet with the mitigations inline.

## Discovery, popular, trending

| Source | Took | Why |
|---|---|---|
| **ChatGPT — Explore GPTs** | Category chips above a two-band layout: *Featured — curated top picks from this week* as cards, then *Trending — most popular by our community* as a **numbered** list with rank, icon, name, description, `By <author>`. | Two bands separate editorial from measured. A single ranked list has to pretend one of those is the other. |
| **Wabi — Explore** | "Popular this week" as ranks 1–5 with icon, name, one-line description, `@handle`; "Recently added" as a second rail below. | Newness and popularity are different questions, and a new marketplace has almost nothing popular yet. Recently-added is what carries a cold catalogue. |
| **OpenSea — Trending** | Rank number, name + verified tick, the metric, and a **signed percentage delta in red/green**. Plus a `24h` window chip and per-row star. | This is the one that defines *trending* properly: trending is a **derivative**, popular is a **level**. Without a window and a direction, "trending" is just "popular" in a different font. |
| **Glow — Trending** | An explicit sort dropdown (Daily / Weekly / Monthly volume) opened over the list. | Makes the window the user's choice rather than a hidden editorial decision. |
| **NAVER — 오픈톡 ranking** | Rank with a small up/down triangle showing **movement since last period**. | A cheaper honest alternative to a % delta when the underlying count is small — and for skills the counts *will* be small. |
| **Deel — app detail** | "You may also like" with a category eyebrow above each name. | Related-capability discovery without needing a recommendation engine. |

**Left, with reasons:**
- **App Store "Must-Have Apps" with a `Get` button on every row.** Install-from-the-list is
  exactly the affordance the adversary frame attacks: it is one tap from a ranked list — a
  ranking that is gameable — to executing someone's code. Detail-then-install is the rule here.
- **Alipay / KakaoBank leaderboards** (gold trophy, 1위/2위 medals, prize chrome). Gamified
  leaderboard styling frames an install as winning something. This decision has a security
  cost and the chrome must not argue otherwise.
- **Shopify's rating / reviews / developer triptych.** No rating data exists for skills or MCP
  servers, and there is no review system to build one from. Three big numbers where two would
  be fabricated is worse than not showing the row.

## Pairing the phone

| Source | Took |
|---|---|
| **Brave — Sync Chain QR** | *"Treat this code like a password. If someone gets hold of it, they can read and modify your synced data."* in red, and a **live countdown**: "This temporary code is valid for the next 0 hour 29 min 48 seconds". |
| **X — link device** | The fallback ladder: QR → "Can't scan the QR code?" → **Enter code** → "Use this device instead". |
| **Comet — Add device** | Instructions that name the **exact menu path on the other device** ("navigate to Comet Sync in the Settings panel and click Join sync"), plus "View sync code" as a text alternative. |

**Left:** Tempo / World App / My BMW all lead with product photography of the thing being
paired. There is no physical object here, and a hero image above a scan is decoration when
the subject is two pieces of software.

**The synthesis for this product:** the pairing code grants a remote party the ability to
install executable code on the user's laptop. That is a higher-stakes grant than Brave's
sync, so Brave's two honesties — the plain-language warning and the visible expiry clock —
are the floor rather than the ceiling. The code expires, and it says so while you look at it.

## Round 3 — replacing the swipe deck on phone triage

The first prototype used a Tinder-style card deck. It was wrong, and the reason is not taste:
**a swipe commits a security decision on a gesture, one item at a time, with no undo and no
record of what was dismissed.** Two searches, images opened.

| Source | Took | Why |
|---|---|---|
| **Replika — New memories** | A grouped checklist of what arrived since last time, a tick per item, and one **Keep all** commit. | The same product problem: review a set that arrived and choose what to keep. A tick survives a misread; a swipe does not. Reading is the whole job on this screen, and a gesture-first UI rewards speed exactly where speed is the enemy. |
| **bless. — my things** | Buckets as segmented tabs: *want / got / didn't get / got rid of*. | **Dismissals get a home.** A swiped-left card is gone with no record, which is the worst property available for a decision about what may execute on your machine. Buckets make "not for me" revisitable from the desk. |
| **Lyft — ride history**, **Bloomberg — Edit Saved Items**, **eBay — Saved items** | The count lives in the button (`DELETE (3)`, "1 ride selected"), and the primary action is disabled until something is selected. | You know the size of what you are committing before you commit it. Adopted verbatim as **"Send 2 to Mac"**. |
| **Whering — Review items** | A numbered stepper `6 · **7** · 8` with the CTA carrying the tally — **Save 7/14** — plus **Review later**. | Position and resumability, which a deck cannot express. Kept in reserve as a one-at-a-time mode; not built, because the phone's job is batching for later review rather than per-item judgment. |
| **Apple Mail / Spark / Fiverr** | Swipe reveals a row of *labelled* circular buttons (More / Flag / Archive / Clear) — the gesture is disclosure, tap is commitment. | The honest way to keep a swipe. Not adopted here because the checklist already gives multi-select, which the reveal pattern cannot. |

**Built:** Undecided / Queued / Not for me as segmented buckets with counts; a checkbox per
row; a one-line colour-coded capability summary on every row (`Read-only · no network` /
`Reads your project · 1 host` / `Shell · network · whole repo`) so the security fact is
visible without opening anything; tap-to-expand for the full capability list; a floating
commit bar carrying the count; and an inline **Undo** after any batch action.

**Left:** the deck, entirely. Also left Paramount+/IKEA's "Are you sure?" confirm dialog —
the commit bar already states what will happen and Undo already exists, so a modal would be
a third telling of the same fact.

