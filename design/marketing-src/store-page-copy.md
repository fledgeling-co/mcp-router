# MCP Router landing copy

Routed: create-luke-content → marketing persona, over `luke-voice.md` and
`ai-writing-signs.md`. Every figure traces to PRD.md, to this machine's own
`~/.claude/mcp-router/manifest.json`, or to the measurement run recorded in
`design/marketing-src/measured-2026-08-20.json` (24 add-ons launched, taken through
`initialize` and `tools/list`, and read with `ps -o rss` across the whole process tree).

**Who this is written for.** Someone whose Mac started feeling slow after they began
using AI, and who does not know or care what an MCP server is. Every technical term
that survived is one Apple itself uses on a product page (Unified Memory, signed and
notarised). Everything else became plain English, and the working moved to numbered
footnotes at the foot of the page. Nothing was softened into vagueness: where a figure
is an illustration rather than a reading, the page says so where it stands.

**Vocabulary.** MCP server / skill / plugin → **add-on**. Harness → **AI app**. Child
process → **background program**. Resident memory → **Unified Memory**. Cold start →
**wake up**. Session → **window**. Quarantine → **held for review**. Reaper → **it shuts
itself down**. Dropped entirely: stdio, JSON-RPC, npx, uvx, `--strict-mcp-config`,
config-file paths, Host headers, schema diffs.

## Nav

Your Mac · How it works · Store · Privacy · GitHub
Download for macOS  (persistent CTA, stays visible when the links collapse under 860px)

## Hero

MCP Router

# All the AI tools. None of the slowdown.

MCP Router is a free Mac app. It keeps every AI add-on you own in one place and switched
off until something actually needs it, so your Mac stops running dozens of programs
you're not using.

[Download for free]   See what it does ›

Free · macOS 15 or later · No account · Open source

Under the copy: the router at rest, drawn rather than photographed. Twelve add-ons,
91 tools, 0 running.

## Why your Mac feels slower  (the one dark section)

### Every AI app starts its own copy of everything.

Your Mac was fine last year. Then you started using AI, and now the fans come on while
you're doing nothing much at all.

Here's what's happening. Open a window in one AI app and it starts a small background
program for every add-on you've installed. Open a second app and that one starts its own
copies. Leave a few windows going across an afternoon and you're running the same handful
of tools a dozen times over, and almost none of them are doing anything.

**156** background programs, one ordinary afternoon [1]
**17 GB** of Unified Memory they ask for, at rest [1]
**1 in 13** actually in use when we looked [4]

### On a Mac, that memory isn't spare.

Apple silicon shares one pool of Unified Memory between your apps, your graphics and
everything running in the background. That's what makes it quick, and it's also why
there's no separate pile for the things you forgot were on. As the pool fills, macOS
starts compressing memory and writing it out to disk to keep up. That's the point where
everything starts feeling half a second late. [3]

Fan diagram caption: 156 background programs · 17 GB asked for at rest · 1 of 13 actually in use

## How it works

### You install it once, and then you don't think about it.

It finds what you've already got, brings it across, and from then on nothing runs unless
something is genuinely using it. There's no setting to get right.

Figure caption: Eight installed, one in use. The six untouched sockets are entries on a
list, not programs that started.

1. **Everything you own comes across.** Whatever you've already set up in your AI apps is
   found and moved on its own. There's **nothing to reconnect**, and nothing to copy out of
   a settings file.
2. **Your AI still gets the full list.** It asks what it can do and gets the answer straight
   away, because the list is already saved. **Nothing has to run to answer that question**,
   so nothing does.
3. **One wakes up, does the job, goes again.** Only when an add-on is genuinely used does
   that one start. **Five minutes after it finishes it shuts itself down**, and you're back
   to nothing running.

(The three cards deliberately open on three different shapes. All three previously began
"It [verb]", which reads as a template rather than as three separate points.)

The way it works now: **17 GB** · 156 background programs across twelve windows, most of them never used.
The way it works with MCP Router: **82 MB** · Nothing running. The same 91 tools still answer instantly. [1,2]

## The store

### One library, and it works in every app you use.

Add-ons are scattered across the internet in four different formats, and every AI app wants
them installed its own way. MCP Router reads all four and keeps one library. You find
something once, and it works everywhere you already work.

**Every figure here was measured, not estimated.** Twenty-four add-ons were started on one
Mac on 20 August 2026 and their memory read directly. [1] The number under each one is what it
costs while it's running. Add a few and watch the counter at the bottom of the page.

**What one add-on costs**

### The middle one takes **194 MB**, and it takes it twice.

We started twenty-four of them on one Mac and watched. The lightest took 10 MB, the heaviest
269 MB. And **twenty-one of the twenty-four turned out to be two programs, not one**, because
the thing that starts an add-on sits there behind it afterwards instead of getting out of the
way.

Now multiply that by the number of windows you have open. That's the whole problem, and it's
the only arithmetic on this page. [1]

Featured (tap one to see what is in it)
- FOUR WAYS TO ASK · Keep all four search tools
- THE OFFICIAL ONES · The nine everybody starts with
- ALREADY ON THIS MAC · The eight this page was built on

Shelf: What each one costs · Top charts (uses the most memory / slowest to wake up) ·
Categories · Held for review · Browse the library

Note on the artwork: every listing carries a drawn icon rather than a glyph, and the icons are
deliberately not all in one style. Five aesthetics run across the shelf, because a store where
every listing is drawn by one hand reads as a stock icon pack rather than a store. The art
depicts what each add-on does; none of it reproduces a company's logo, wordmark or brand mark,
and where a listing belongs to a real company the icon shows the activity instead.

The fifteen category chips are a sixth aesthetic of their own, uniform across all fifteen:
one matte sculpted symbol per tile, on a flat ground. They carry drawn artwork at the listing
tiles' small size rather than a stroke glyph on a gradient, because the row sits directly under
52px listing art and a glyph there reads as a cheaper layer. All fifteen grounds sit at the same
relative luminance, and the previous palette had six of the fifteen inside a 22-degree blue band,
which is why half the row used to look identical. Brief and colours:
`design/marketing-src/img-src/prompt-category-icons.md`.

Your Mac (sticky): − 12 + windows open · background programs · Unified Memory · to start them all
Note: that counter is what your Mac costs the ordinary way, one program per add-on per window.
It is not what it costs through the router.

## Updates

### An update has to be read before it can run.

Everything is checked when it goes in, and checked again every time it changes. If an update
quietly rewrites what a tool says it does, **that update is held until you've seen the
difference**. Nothing can call it in the meantime, and your AI carries on without it.

This matters more than it sounds. Waiting for a version number to look suspicious doesn't catch
it, because the version did change. What changed underneath it is the part worth reading.

Figure caption: A held add-on is switched out of the path deliberately. Nothing reaches the far
side until you've read what changed.

## Everywhere you work

### Works with the apps you already use.

Claude Code · Cursor · Codex · Grok · Antigravity · OpenCode

It sets each one up itself, in the right place, and takes the old entry out so you're not
paying for the same thing twice. Add something new later and it does the same again, without
being asked.

If something can't be moved across safely, it's left exactly where it was and you're told why.
Nothing gets rewritten that the router couldn't first start and read for itself.

## Privacy

### It never leaves your Mac.

There's no account, no sync, and no server of ours anywhere in the middle. The router runs on
your machine and listens only to your machine. A web page can't reach it, even one pointed
straight at your own address, because it checks where every request came from before it answers.

## Cleanup

### It tells you what you never use.

It counts what actually gets used over a week, a month and three months, and shows you the ones
that have never been touched, with the case for keeping each one beside it. Nothing goes without
you choosing it, and you've got thirty days to change your mind.

## Before you install

### Four things worth knowing first.

**The first use after a quiet spell takes a moment.** That's the trade for nothing running the
rest of the time. If there's one you lean on all day, you can tell the app to **keep it awake**
and skip the wait.

**Everything goes through one place.** If the router stops, every app loses its tools at the same
moment rather than one at a time. That's a real change to how things fail, and you should hear it
from us now rather than find it out later.

**It's not on the App Store.** Its whole job is starting programs and reading settings files, and
App Store apps aren't allowed to do either. So it comes **straight from us, signed and notarised
by Apple**.

**It's free, and it stays free.** No paid tier, no trial, and no account to cancel. The whole
thing is **open source under the MIT licence**, so you can read every line of it if you want to.

## Download

### Get MCP Router.

[Download for macOS]
Free · macOS 15 or later · Signed and notarised by Apple · No account

Prefer the terminal?
`/bin/bash -c "$(curl -fsSL https://mcp-router.fledgeling.app/install.sh)"`

And how to take it back out
`/bin/bash -c "$(curl -fsSL https://mcp-router.fledgeling.app/uninstall.sh)"`
It puts everything back exactly where it found it. Add `--purge` and it takes the saved lists and
history with it as well.

## Where the numbers come from  (page footnotes)

1. Measured on one Mac on 20 August 2026. Twenty-four add-ons were started, taken through the real
   start-up exchange, and their memory read with `ps -o rss` across every program each one left
   behind. Eight of them were the ones installed on that machine: they came to thirteen background
   programs and 1.4 GB for a single window, which is 156 programs and 17 GB across twelve. Twelve
   windows is an ordinary afternoon.
2. 82 MB is the router itself, running, with every add-on closed, read the same way on the same day.
3. The machine this page was written on is an M4 Max with 128 GB of memory. Twenty-five hours into
   an uptime with twenty sessions open it was holding 74 GB of memory squeezed into 30 GB of
   compressor, sitting 3.6 GB deep in swap with 18.9 GB written out since boot. Being fair to the
   figure: that is the whole machine, editors and compilers included, not AI add-ons on their own.
   The part measured cleanly is the arithmetic in note 1.
4. On that same machine, one add-on of thirteen was in use at the moment we looked, and four of the
   twelve installed could not start at all. Three had never been built and one had lost its sign-in.
   Yours will be its own number, and the app counts it rather than assuming it.
5. Memory here is resident memory, which slightly overstates the total because some of it is shared.
   Running six copies of one add-on measured 1,099 MB against 197 MB for a single copy, so the
   sharing is worth about seven per cent. The second copy costs very nearly what the first one did.
6. A developer writing this up in March 2026 counted 172 background programs and about 3 GB across
   seven sessions on a 16 GB MacBook Pro. Different machine, same arithmetic.
7. Limiting which add-ons an app loads at start-up helps a little, but it does not share a program
   between two windows, and it does not hold off starting one until something asks.

## Footer

MCP Router · GitHub · Docs · v0.1.0
