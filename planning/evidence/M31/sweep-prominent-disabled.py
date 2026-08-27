#!/usr/bin/env python3
"""M31's sweep: every control that resolves an accent fill, and whether its disabled state dims.

The defect M31 was filed for is a disabled accent-filled control that renders *as though enabled*,
because a rule carrying the accent beats the rule that dims it. Both rules exist; the cascade
decides; and a sweep that only asks whether a dimming rule *exists* cannot see the difference.
That is the mistake this file made in its first form: it asked `has_dimming_rule` and reported
`.btn.primary` — the very control M31 was filed for — as satisfied, because a losing rule is still
a present one.

So the CSS lane resolves the cascade instead of inspecting it. For every rule that paints
`var(--accent-ink)`, it builds the element that matches that rule *and* a disabled marker, replays
every rule in the sheet against it by (specificity, source order), and reads off the winning
`background`, `color` and `border-color`. That is a claim about what the page draws, and it is
checkable against the renderer — `render-probe.sh` reads the same five controls out of Obscura, and
the two agree.

Verdicts, and which ones fail:

  * ``DRAWS-AS-ENABLED`` — the resolved disabled fill is still `var(--accent-ink)`. **Fails.**
    This is the M31 defect exactly.
  * ``UNREADABLE`` — the fill dims but a label is left on the accent, or the resolved pairing falls
    under the disabled floor this design of record has actually ratified. **Fails.**
  * ``UNDRAWN`` — the control resolves an accent fill and no rule dims it at all. **Fails when the
    markup or the script can reach the state**, and is reported without failing when neither can:
    an unreachable missing state is a completeness gap against DESIGN.md rule 4, not a control
    that draws its opposite.
  * ``MARKER-MISMATCH`` — a dimming rule exists but is spelled for a marker the markup does not
    use. **Fails.** `.switch:disabled` against `class="switch disabled"` is why this verdict
    exists: the rule was present, correct, and never applied to the one instance in the page.
  * ``DIMS`` — passes, and records the resolved triple with its measured contrast.

The Swift lane reports what a source read can settle and says so. Two things it does not claim:

  * that a style's `@Environment(\\.isEnabled)` is actually installed by SwiftUI. `Controls.swift`
    declines to rely on that and reads the environment from a nested `View` instead; a style that
    reads it directly is ``UNPROVEN`` rather than passing or failing.
  * anything about pixels. `make mock-fidelity` exits 3 on an inherited break
    (`MeasureDump/main.swift:206`, a non-exhaustive switch missing `.readme`), so the rendered lane
    is unavailable for the Swift surfaces. It **is** available for the HTML surfaces, and those
    verdicts are corroborated at the rendered rung by `render-probe.sh` via Obscura.

    A Swift style that resolves an accent fill and has **no** disabled branch reaching that fill
    does fail here, because that is settleable from source: it is the M18 defect shape, and it is
    the one Swift claim that needs no render.

Usage:  python3 planning/evidence/M31/sweep-prominent-disabled.py [--json]
Exit 0 when no surface reproduces the defect; 1 otherwise.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
WINDOW = 14  # lines either side of a call site searched for a `.disabled(` modifier

ACCENT = "var(--accent-ink)"
DISABLED_MARKERS = (".disabled", ":disabled", "[disabled]", '[aria-disabled="true"]')

# The disabled triple DESIGN.md §3 ratifies, and the floor it ratifies it at. `--t4` on `--f3` is
# 2.94:1 dark / 2.62:1 light; anything at or above the lower of those is inside what §3 licensed.
RATIFIED = ("t4", "f3", "line")
RATIFIED_FLOOR = 2.60

# Styles that resolve an accent fill, and how each decides its disabled treatment.
STYLES = {
    "ProminentButtonStyle": {
        "surface": "macOS",
        "disabled_tokens": ("t4", "f3", "line"),
        "reads_environment_from": "a nested View (Controls.swift `Label`)",
        "proven": True,
    },
    "PhoneProminentButtonStyle": {
        "surface": "iPhone",
        "disabled_tokens": ("t4", "raised", None),
        "reads_environment_from": "@Environment on the ButtonStyle type itself",
        "proven": False,
    },
}


# --------------------------------------------------------------------------- colour


def _srgb(c):
    c /= 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _luminance(rgb):
    r, g, b = (_srgb(x) for x in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(fg, bg):
    """WCAG 2.x contrast, in float throughout.

    Float rather than 8-bit-rounded compositing, and the choice is forced rather than stylistic:
    rounding each composited channel to an integer first reproduces three of DESIGN.md §2's four
    published `--t4` figures and breaks the fourth. Float reproduces all four. `--self-check`
    re-derives them so this stays a checked claim.
    """
    a, b = _luminance(fg), _luminance(bg)
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


def _parse_colour(text, ground):
    """`#RGB`, `#RRGGBB`, `rgb()`/`rgba()` → a float triple composited onto `ground`."""
    text = text.strip()
    m = re.fullmatch(r"#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})", text)
    if m:
        h = m.group(1)
        if len(h) == 3:
            h = "".join(c * 2 for c in h)
        return tuple(float(int(h[i:i + 2], 16)) for i in (0, 2, 4))
    m = re.fullmatch(r"rgba?\(([^)]*)\)", text)
    if m:
        parts = [p.strip() for p in re.split(r"[,\s/]+", m.group(1)) if p.strip()]
        rgb = tuple(float(p) for p in parts[:3])
        alpha = float(parts[3]) if len(parts) > 3 else 1.0
        if ground is None or alpha >= 1.0:
            return rgb
        return tuple(alpha * c + (1 - alpha) * g for c, g in zip(rgb, ground))
    return None


def resolve_tokens(css):
    """The `:root` block and its dark counterpart → two token tables, alpha composited on --ground."""
    themes = {}
    light = re.search(r":root\{([^}]*)\}", css)
    dark = re.search(r"@media \(prefers-color-scheme: dark\)\s*\{\s*:root\{([^}]*)\}", css)
    for name, block in (("light", light), ("dark", dark)):
        if not block:
            continue
        raw = {}
        for decl in block.group(1).split(";"):
            if ":" not in decl:
                continue
            k, v = decl.split(":", 1)
            k = k.strip()
            if k.startswith("--"):
                raw[k] = v.strip()
        base = dict(themes.get("light", {}).get("raw", {}))
        base.update(raw)
        ground = _parse_colour(base.get("--ground", "#FFFFFF"), None)
        themes[name] = {
            "raw": base,
            "ground": ground,
            "rgb": {k: _parse_colour(v, ground) for k, v in base.items()},
        }
    return themes


def token_of(value):
    m = re.fullmatch(r"var\((--[a-z0-9-]+)\)", (value or "").strip())
    return m.group(1) if m else None


# ----------------------------------------------------------------------------- CSS


def parse_rules(css, source=""):
    """Ordered (selector, declarations, order) triples. Comments stripped first.

    Stripping comments is load-bearing rather than tidiness: without it the block preceding `.btn{`
    carries the section banner comment, the selector text never trims to `.btn`, and the store page
    — whose bare `.btn` *is* the accent-filled control — reports as having none. A zero meaning
    "wrong vocabulary" reads identically to a zero meaning "nothing here".

    Every block and every declaration this reader cannot turn into a rule is NAMED on stderr rather
    than dropped, grouped by reason. A sweep whose whole claim is "no surface reproduces the defect"
    rests on having replayed the sheet; a block the splitter could not read is a rule that never
    entered the cascade, and a cascade missing a rule resolves the wrong winner without saying so.
    The reasoning that made this function strip comments — a zero meaning "wrong vocabulary" reads
    identically to a zero meaning "nothing here" — applies one layer down to the blocks it skips.
    """
    css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
    css = re.sub(r"@media[^{]*\{", "", css)  # flatten; dark values arrive via resolve_tokens
    rules, order = [], 0
    dropped = []
    for block in css.split("}"):
        brace = block.find("{")
        if brace < 0:
            # The tail after the final `}`, or an at-rule body the `@media` flatten left behind.
            dropped.append(("no `{` in the block", block.strip()[:60]))
            continue
        selectors = block[:brace]
        body = block[brace + 1:]
        if "{" in selectors or not selectors.strip():
            dropped.append(("selector text is empty or still nested", selectors.strip()[:60]))
            continue
        decls = {}
        for decl in body.split(";"):
            if ":" not in decl:
                dropped.append(("declaration carries no `:`", decl.strip()[:60]))
                continue
            k, v = decl.split(":", 1)
            decls[k.strip().lower()] = v.strip()
        if not decls:
            dropped.append(("no readable declaration in the block", selectors.strip()[:60]))
            continue
        for sel in selectors.split(","):
            sel = sel.strip()
            if sel:
                rules.append({"selector": sel, "decls": decls, "order": order})
                order += 1
    # Grouped by reason rather than one line per item, which is `input_accounting.Tally`'s rule and
    # the reason for it: this reader is handed a whole HTML document, so the fragments it discards
    # are mostly `<script>` bodies and base64 data URIs, and 882 individual lines would bury the
    # one number that matters — how much of the sheet never entered the cascade.
    by_reason = {}
    for reason, text in dropped:
        by_reason.setdefault(reason, []).append(text)
    where = f" of {source}" if source else ""
    print("parse_rules%s: %d rule(s) built; %d fragment(s) discarded (%s)"
          % (where, len(rules), len(dropped),
             "; ".join(f"{r} {len(v)}" for r, v in sorted(by_reason.items())) or "none"),
          file=sys.stderr)
    return rules


SIMPLE = re.compile(r"(:not\([^)]*\)|\[[^\]]*\]|::[a-z-]+|:[a-z-]+(?:\([^)]*\))?|\.[-\w]+|#[-\w]+|[-\w]+|\*)")

# The three ways this codebase spells "disabled", grouped by what a browser actually matches.
# `:disabled` and `[disabled]` are one state written two ways — a page whose markup carries the
# `disabled` attribute is matched by both — while `.disabled` is a different state entirely. Keeping
# them apart is what lets MARKER-MISMATCH mean something: `.switch:disabled` against
# `class="switch disabled"` is a rule that exists, is correct, and never applies.
MARKER_FAMILIES = {
    "attr": (":disabled", "[disabled]"),
    "class": (".disabled",),
    "aria": ('[aria-disabled="true"]',),
}


def compound_parts(compound):
    return [p for p in SIMPLE.findall(compound) if p != "*"]


def specificity(selector):
    a = b = c = 0
    for compound in split_descendant(selector):
        for part in compound_parts(compound):
            if part.startswith(":not("):
                inner = part[5:-1]
                ia, ib, ic = specificity(inner)
                a, b, c = a + ia, b + ib, c + ic
            elif part.startswith("#"):
                a += 1
            elif part.startswith("::"):
                c += 1
            elif part.startswith((".", "[", ":")):
                b += 1
            else:
                c += 1
    return (a, b, c)


def split_descendant(selector):
    """`a b` -> ['a', 'b']. Child/sibling combinators are descendant boundaries for our purposes."""
    return [p for p in re.split(r"\s*[>+~]\s*|\s+", selector.strip()) if p]


def compound_matches(compound, tokens):
    """Every simple selector present, and every `:not()` argument absent."""
    parts = compound_parts(compound)
    if not parts:
        return False
    for part in parts:
        if part.startswith(":not("):
            if any(p in tokens for p in compound_parts(part[5:-1])):
                return False
        elif part not in tokens:
            return False
    return True


def matches(selector, chain):
    """Match a full selector against an element CHAIN (ancestors first, the element last).

    Right-to-left with skips, which is what a descendant combinator means. Modelling the chain
    rather than flattening it matters: flattening `.segmented .seg` into one token bag let the
    parent's `background` resolve onto the child and reported a control as dimming to `--raised`
    when the parent is what draws `--raised`.
    """
    compounds = split_descendant(selector)
    if not compounds or not chain:
        return False
    if not compound_matches(compounds[-1], chain[-1]):
        return False
    i = len(chain) - 2
    for compound in reversed(compounds[:-1]):
        while i >= 0 and not compound_matches(compound, chain[i]):
            i -= 1
        if i < 0:
            return False
        i -= 1
    return True


def resolve(rules, chain, prop):
    """The winning declaration of `prop` on the chain's last element, by (specificity, order)."""
    best = None
    for rule in rules:
        if prop not in rule["decls"] or not matches(rule["selector"], chain):
            continue
        key = (specificity(rule["selector"]), rule["order"])
        if best is None or key > best[0]:
            best = (key, rule)
    return best[1] if best else None


def resolve_background(rules, chain):
    """The winning background colour, letting the cascade choose between shorthand and longhand.

    `background:` and `background-color:` both set the background colour, so the winner is whichever
    DECLARATION wins by (specificity, source order) across both property names. Trying one property
    and falling back to the other — which this did first — hides a real defect in one direction: an
    accent rule spelled `background-color:` that legitimately wins the cascade is invisible behind a
    disabled rule spelled `background:` that loses, and the sweep reports DIMS over a control that
    draws its accent. Found by an out-of-family review of this file.
    """
    best = None
    for rule in rules:
        for prop in ("background", "background-color"):
            if prop not in rule["decls"] or not matches(rule["selector"], chain):
                continue
            key = (specificity(rule["selector"]), rule["order"])
            if best is None or key > best[0]:
                best = (key, rule, prop)
    if best is None:
        return None, None
    return best[1], best[1]["decls"][best[2]]


def resolve_descendants(rules, chain, prop):
    """Winning `prop` per descendant compound, for elements nested inside the chain's element."""
    leaves = set()
    for rule in rules:
        compounds = split_descendant(rule["selector"])
        if len(compounds) < 2 or prop not in rule["decls"]:
            continue
        if matches(" ".join(compounds[:-1]), chain):
            leaves.add(compounds[-1])
    winners = {}
    for leaf in leaves:
        probe = chain + [set(compound_parts(leaf))]
        rule = resolve(rules, probe, prop)
        if rule is not None and len(split_descendant(rule["selector"])) >= 2:
            winners[leaf] = rule
    return winners


CONTROL_TAGS = ("button", "input", "select", "textarea", "a", "summary", "label")
CONTROL_ATTRS = ("role=", "tabindex=", "aria-checked", "aria-pressed", "aria-selected",
                 "aria-expanded", "onclick", "data-setstate")


def markup_index(html):
    """Per class: is it drawn on a control, and can that control reach a disabled state?

    A sweep over *controls* needs to know which classes name one. `--accent-ink` also paints
    progress bars, notification glyphs and a shield icon; those have no disabled state to draw and
    counting them as failures would bury the four that do. The test is the markup's own: the class
    appears on an interactive tag, or on an element carrying an interactive attribute.
    """
    control, reach = set(), {}
    for tag, attrs in re.findall(r"<(\w+)([^>]*)>", html):
        classes = re.findall(r'class="([^"]*)"', attrs)
        names = set()
        for c in classes:
            names |= set(c.split())
        if not names:
            continue
        interactive = tag.lower() in CONTROL_TAGS or any(a in attrs for a in CONTROL_ATTRS)
        if interactive:
            control |= names
        fams = set()
        if "disabled" in names:
            fams.add("class")
        if re.search(r"\sdisabled(?=[\s>=]|$)", attrs):
            fams.add("attr")
        if 'aria-disabled="true"' in attrs:
            fams.add("aria")
        for n in names:
            reach.setdefault(n, set())
            reach[n] |= fams
    # A script can reach the state too, and does: the console sets `.disabled` on rows and
    # `el.disabled` on buttons. A class the script can disable is reachable even where no static
    # instance in the page carries the marker.
    if re.search(r"classList\.(?:add|toggle)\(\s*'disabled'", html):
        for n in reach:
            reach[n].add("class")
    if re.search(r"\.disabled\s*=\s*(?:true|!)", html):
        for n in reach:
            reach[n].add("attr")
    return control, reach


def judge(themes, fill_token, label_token):
    """Contrast for the resolved pairing, in both themes, plus the worst of them."""
    out, worst = {}, None
    for name, theme in themes.items():
        fg = theme["rgb"].get(label_token)
        bg = theme["rgb"].get(fill_token)
        if fg is None or bg is None:
            continue
        r = contrast(fg, bg)
        out[name] = round(r, 2)
        worst = r if worst is None else min(worst, r)
    return out, worst


def sweep_html():
    results = []
    for rel in ("design/mcp-router-console.html", "docs/mcp-router-store.html", "docs/index.html",
                "design/banner.html"):
        path = ROOT / rel
        if not path.exists():
            results.append({"file": rel, "verdict": "ABSENT", "controls": []})
            continue
        html = path.read_text()
        rules = parse_rules(html, rel)
        themes = resolve_tokens(re.sub(r"/\*.*?\*/", "", html, flags=re.S))
        control_classes, reachability = markup_index(html)

        accent_rules = [
            r for r in rules
            if "--accent-ink" in (token_of(r["decls"].get("background")),
                                  token_of(r["decls"].get("background-color")))
        ]
        controls, skipped = [], []
        for rule in accent_rules:
            compounds = split_descendant(rule["selector"])
            leaf = set(compound_parts(compounds[-1]))
            base = next((p for p in compounds[-1:] for p in compound_parts(p)
                         if p.startswith(".")), None)
            if base is None or base.lstrip(".") not in control_classes:
                skipped.append({"selector": rule["selector"],
                                "why": "not drawn on a control in this page's markup"})
                continue
            chain_prefix = [set(compound_parts(c)) for c in compounds[:-1]]

            # Which disabled families the sheet offers for this control, and which the page reaches.
            offered = set()
            for r in rules:
                parts = compound_parts(split_descendant(r["selector"])[-1])
                if base not in parts:
                    continue
                for fam, spellings in MARKER_FAMILIES.items():
                    if any(sp in parts for sp in spellings):
                        offered.add(fam)
            reached = reachability.get(base.lstrip("."), set())

            entry = {
                "selector": rule["selector"],
                "dimming_families_in_sheet": sorted(offered),
                "disabled_families_in_markup": sorted(reached),
                "reachable": bool(reached),
                "states": [],
            }
            if not offered:
                entry["verdict"] = "UNDRAWN"
                entry["why"] = ("resolves an accent fill and no rule dims it (DESIGN.md rule 4 "
                                "requires a disabled state of every control)")
                controls.append(entry)
                continue
            if reached and not (offered & reached):
                entry["verdict"] = "MARKER-MISMATCH"
                entry["why"] = ("the sheet dims %s while the markup spells the state %s, so the "
                                "rule never applies to the instance in the page"
                                % (sorted(offered), sorted(reached)))
                controls.append(entry)
                continue

            verdict = "DIMS"
            for fam in sorted(offered):
                probe = chain_prefix + [leaf | set(MARKER_FAMILIES[fam])]
                fill, fill_v = resolve_background(rules, probe)
                label = resolve(rules, probe, "color")
                bezel = resolve(rules, probe, "border-color")
                get = lambda r, *k: next((r["decls"][x] for x in k if r and x in r["decls"]), None)
                label_v = get(label, "color")
                bezel_v = get(bezel, "border-color")
                state = {"family": fam, "resolved_fill": fill_v, "resolved_label": label_v,
                         "resolved_bezel": bezel_v,
                         "fill_rule": (fill or {}).get("selector"),
                         "label_rule": (label or {}).get("selector")}
                if token_of(fill_v) == "--accent-ink":
                    state["verdict"] = "DRAWS-AS-ENABLED"
                    state["why"] = ("`%s` wins `background` over every disabled rule, so the "
                                    "control keeps its accent fill while disabled"
                                    % (fill or {}).get("selector"))
                    verdict = "DRAWS-AS-ENABLED"
                    entry["states"].append(state)
                    continue
                ratios, worst = judge(themes, token_of(fill_v), token_of(label_v))
                state["contrast"] = ratios
                state["verdict"] = "DIMS"
                if worst is not None and worst < RATIFIED_FLOOR:
                    state["verdict"] = "UNREADABLE"
                    state["why"] = ("%s on %s measures %s — under the %.2f:1 DESIGN.md §3 ratifies "
                                    "for a disabled pairing" % (token_of(label_v), token_of(fill_v),
                                                                ratios, RATIFIED_FLOOR))
                    if verdict != "DRAWS-AS-ENABLED":
                        verdict = "UNREADABLE"
                # Anything painted inside the control has to come off the accent with it.
                for dleaf, drule in sorted(resolve_descendants(rules, probe, "color").items()):
                    dtok = token_of(drule["decls"].get("color"))
                    dratios, dworst = judge(themes, token_of(fill_v), dtok)
                    if dworst is not None and dworst < RATIFIED_FLOOR:
                        state.setdefault("descendant_findings", []).append(
                            "`%s` resolves %s on the disabled fill %s (%s)"
                            % (drule["selector"], dtok, token_of(fill_v), dratios))
                        if verdict != "DRAWS-AS-ENABLED":
                            verdict = "UNREADABLE"
                entry["states"].append(state)
            entry["verdict"] = verdict
            controls.append(entry)
        results.append({"file": rel, "controls": controls,
                        "accent_filled_controls": len(controls),
                        "accent_rules_not_on_a_control": skipped})
    return results


# --------------------------------------------------------------------------- Swift


def swift_sites():
    call = re.compile(r"\.buttonStyle\((Phone)?ProminentButtonStyle\(")
    direct = re.compile(r"(Phone)?ProminentButtonStyle\([^)]*\)\.makeBody")
    out = []
    files = sorted((ROOT / "app/Sources").rglob("*.swift"))
    for path in files:
        lines = path.read_text().splitlines()
        for i, line in enumerate(lines):
            m = call.search(line) or direct.search(line)
            if not m:
                continue
            window = "\n".join(lines[max(0, i - WINDOW): i + WINDOW])
            out.append({
                "file": str(path.relative_to(ROOT)),
                "line": i + 1,
                "style": ("Phone" if m.group(1) else "") + "ProminentButtonStyle",
                "disableable": bool(re.search(r"\.disabled\(", window)),
                "hand_invoked": bool(direct.search(line)),
            })
    # This reader is a grep, so the lines it skips are its subject inverted and naming them would
    # name the tree. What a grep CAN lose without saying so is its denominator — `sweep_swift`'s
    # `examined=` counts files that carry a hit, not files walked, so a run over an empty or moved
    # `app/Sources` reports `examined=0` exactly as a run over a tree with no prominent styles does.
    print("swift_sites: walked %d .swift file(s) under app/Sources; %d carry a prominent-style "
          "call site" % (len(files), len(out)), file=sys.stderr)
    return out


def _fill_branches(expr, body):
    """Does this `.fill(...)` expression depend on `isEnabled`, directly or through one binding?

    `PhoneProminentButtonStyle` writes the branch inline. `ProminentButtonStyle` deliberately does
    not: it binds `let tokens = palette(isEnabled)` and paints `tokens.fill.color`, because the
    decision is then assertable without a render and `ButtonPaletteTests` reads it. A check that
    only grepped the `.fill(` line called the second one unconditional — the style that is the
    reference implementation for this very fix. So follow the root identifier one level.
    """
    if "isEnabled" in expr:
        return True
    root = re.match(r"([A-Za-z_]\w*)", expr.strip())
    if not root:
        return False
    binding = re.search(r"\blet\s+%s\s*=\s*([^\n]*)" % re.escape(root.group(1)), body)
    return bool(binding and "isEnabled" in binding.group(1))


def swift_style_bodies():
    """Does each accent-resolving style actually branch its FILL on enablement?

    The one Swift claim a source read settles outright, and the M18 defect shape: a style that
    paints the accent unconditionally cannot draw a disabled state however it colours its label.
    """
    found = {}
    for path in sorted((ROOT / "app/Sources").rglob("*.swift")):
        text = path.read_text()
        for style in STYLES:
            m = re.search(r"public struct %s: ButtonStyle \{(.*?)\n\}" % style, text, re.S)
            if not m:
                continue
            body = m.group(1)
            fills = [f.strip() for f in re.findall(r"\.fill\(([^\n]*)\)", body)]
            found[style] = {
                "file": str(path.relative_to(ROOT)),
                "branches_fill_on_enabled": all(_fill_branches(f, body) for f in fills) and bool(fills),
                "fill_expressions": fills,
            }
    return found


def sweep_swift():
    sites = swift_sites()
    bodies = swift_style_bodies()
    surfaces = {}
    for s in sites:
        surfaces.setdefault(s["file"], []).append(s)

    failures, unproven = [], []
    for style, meta in STYLES.items():
        body = bodies.get(style)
        if body and not body["branches_fill_on_enabled"]:
            failures.append((body["file"], style,
                             "paints the accent fill unconditionally — %s" % body["fill_expressions"]))

    for f, group in surfaces.items():
        style = group[0]["style"]
        meta = STYLES[style]
        if meta["disabled_tokens"][:2] != RATIFIED[:2]:
            unproven.append((f, style, "disabled fill is --%s, DESIGN.md §3 ratifies --%s"
                             % (meta["disabled_tokens"][1], RATIFIED[1])))
        if not meta["proven"] and any(g["disableable"] for g in group):
            unproven.append((f, style, "dims only if SwiftUI installs @Environment on a ButtonStyle"))
        for g in group:
            if g["hand_invoked"]:
                unproven.append((g["file"], style,
                                 "makeBody called directly at :%d, so SwiftUI never installs the "
                                 "style's dynamic properties" % g["line"]))
    return {
        "surfaces_examined": len(surfaces),
        "call_sites_examined": len(sites),
        "disableable_call_sites": sum(1 for s in sites if s["disableable"]),
        "styles": bodies,
        "failures": [{"file": f, "style": s, "why": w} for f, s, w in failures],
        "unproven": [{"file": f, "style": s, "why": w} for f, s, w in unproven],
        "by_style": {
            k: {
                "sites": sum(1 for s in sites if s["style"] == k),
                "disableable": sum(1 for s in sites if s["style"] == k and s["disableable"]),
            } for k in STYLES
        },
    }


# ---------------------------------------------------------------------------- main


def self_check():
    """Re-derive DESIGN.md §2's four published `--t4` figures, and §3's two.

    The control that makes the arithmetic above a measurement rather than an assertion, and it
    discriminates: 8-bit-rounded compositing gives 2.95/2.61 for the §3 pairing and breaks §2's
    published 1.15, so float is the single method that reproduces every published column.
    """
    css = (ROOT / "design/mcp-router-console.html").read_text()
    themes = resolve_tokens(re.sub(r"/\*.*?\*/", "", css, flags=re.S))
    checks = [("--t4", "--ground", "dark", 3.37), ("--t4", "--ground", "light", 2.79),
              ("--t4", "--f3", "dark", 2.94), ("--t4", "--f3", "light", 2.62)]
    ok = True
    for fg, bg, theme, published in checks:
        got = contrast(themes[theme]["rgb"][fg], themes[theme]["rgb"][bg])
        hit = round(got, 2) == published
        ok &= hit
        print("  %-6s %s on %s  computed %.4f -> %.2f  published %.2f  %s"
              % (theme, fg, bg, got, round(got, 2), published, "OK" if hit else "MISMATCH"))
    return ok


def main():
    if "--self-check" in sys.argv:
        return 0 if self_check() else 1

    html = sweep_html()
    swift = sweep_swift()

    html_failures = []
    for surface in html:
        for c in surface.get("controls", []):
            if c["verdict"] in ("DRAWS-AS-ENABLED", "UNREADABLE", "MARKER-MISMATCH"):
                html_failures.append((surface["file"], c))
            elif c["verdict"] == "UNDRAWN" and c.get("reachable"):
                html_failures.append((surface["file"], c))

    report = {"swift": swift, "html": html,
              "failures": len(html_failures) + len(swift["failures"])}

    if "--json" in sys.argv:
        print(json.dumps(report, indent=2))
    else:
        print("Swift surfaces with a primary action: examined=%d call-sites=%d disableable=%d "
              "failures=%d unproven=%d"
              % (swift["surfaces_examined"], swift["call_sites_examined"],
                 swift["disableable_call_sites"], len(swift["failures"]), len(swift["unproven"])))
        for k, v in swift["by_style"].items():
            print("  %-28s sites=%2d disableable=%d" % (k, v["sites"], v["disableable"]))
        for f in swift["failures"]:
            print("  FAIL     %s [%s] — %s" % (f["file"], f["style"], f["why"]))
        for u in swift["unproven"]:
            print("  UNPROVEN %s [%s] — %s" % (u["file"], u["style"], u["why"]))
        total = sum(len(s.get("controls", [])) for s in html)
        print("HTML surfaces: examined=%d accent-filled controls=%d html-failures=%d"
              % (len(html), total, len(html_failures)))
        for surface in html:
            print("  %s" % surface["file"])
            if not surface.get("controls"):
                print("      (no control resolves var(--accent-ink))")
            for c in surface.get("controls", []):
                print("      %-14s %-42s %s" % (c["verdict"], c["selector"],
                                                "reachable" if c.get("reachable") else "unreachable"))
                if c.get("why"):
                    print("          %s" % c["why"])
                for st in c.get("states", []):
                    print("          [%s] %s fill=%s label=%s bezel=%s %s"
                          % (st["family"], st["verdict"], st["resolved_fill"],
                             st["resolved_label"], st["resolved_bezel"],
                             st.get("contrast", "")))
                    if st.get("why"):
                        print("              %s" % st["why"])
                    for n in st.get("descendant_findings", []):
                        print("              descendant: %s" % n)
            for sk in surface.get("accent_rules_not_on_a_control", []):
                print("      not-a-control  %-42s %s" % (sk["selector"], sk["why"]))
        print("TOTAL failures=%d" % report["failures"])
    return 1 if report["failures"] else 0


if __name__ == "__main__":
    sys.exit(main())
