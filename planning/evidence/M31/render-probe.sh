#!/usr/bin/env bash
# M31's rendered oracle: the same controls sweep-prominent-disabled.py judges from source, read
# back out of a renderer.
#
# The sweep resolves the CSS cascade itself. That is a claim about what the page draws, so it needs
# a second instrument that draws it — otherwise a bug in the resolver reads as a clean surface.
# This probes every control the sweep returns a verdict on and prints BEFORE/AFTER, so the two can
# be compared row by row.
#
# `make mock-fidelity` exits 3 on an inherited break (MeasureDump/main.swift:206, a non-exhaustive
# switch missing `.readme`), so the project's own rendered lane is unavailable and this substitutes
# Obscura.
#
# Attribution, because M31's first pass got it wrong: `.tb-btn.on` was found HERE, not by the sweep.
# The sweep's selector regex was a `\.btn(\.primary)?` fullmatch, so a toolbar button was never in
# its search space, and a commit message credited it with the find anyway. The sweep now resolves
# every rule that paints `var(--accent-ink)` and would find it unaided; that is a repair, not a
# reason to restate the original claim.
#
# Dark is reached by applying the page's OWN `@media (prefers-color-scheme: dark)` :root block to
# the root element, because Obscura accepts `Emulation.setEmulatedMedia` and is inert on it. That
# proves the rules resolve correctly under dark token VALUES; it does not prove the media query
# fires. Stated rather than glossed.
#
# Longhands only — `padding`, `margin` and `borderRadius` shorthands misreport in this engine.
# `backgroundColor`, `color`, `borderTopColor` and `opacity` are on the reliable list.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
MOCK="file://$ROOT/design/mcp-router-console.html"
STORE="file://$ROOT/docs/mcp-router-store.html"

SNAP='const s=e=>{const c=getComputedStyle(e);return c.backgroundColor+" fg="+c.color+" bc="+c.borderTopColor+" op="+c.opacity+" cur="+c.cursor;};const mk=h=>{const d=document.createElement("div");d.innerHTML=h;document.body.appendChild(d);return d.firstElementChild;};'

echo "== console mock, light: every accent-filled control, live then disabled =="
obscura fetch "$MOCK" --eval "(()=>{$SNAP const o=[];const p=(n,h,m)=>{const e=mk(h);const b=s(e);m(e);o.push(n.padEnd(26)+'\n  LIVE     '+b+'\n  DISABLED '+s(e));};
p('.btn.primary','<button class=\"btn primary\">P</button>',e=>e.disabled=true);
p('.tb-btn.on','<button class=\"tb-btn on\">T</button>',e=>e.disabled=true);
{const w=mk('<div class=\"segmented\"><button class=\"seg\" aria-pressed=\"true\">S</button></div>');const e=w.querySelector('.seg');const b=s(e);e.disabled=true;o.push('.seg[aria-pressed]'.padEnd(26)+'\n  LIVE     '+b+'\n  DISABLED '+s(e));}
const sw=document.querySelector('button.switch.disabled');const swl=document.querySelector('button.switch[aria-checked=\"true\"]:not(.disabled)');
o.push('.switch (page markup)'.padEnd(26)+'\n  LIVE     '+s(swl)+'\n  DISABLED '+s(sw)+'\n  KNOB     '+s(sw.querySelector('.knob')));
const tr=document.querySelector('.trow.disabled');const sub=tr.querySelector('.c-sub');
o.push('.trow.disabled unselected'.padEnd(26)+'\n  ROW      '+s(tr));
tr.setAttribute('aria-selected','true');
o.push('.trow.disabled + selected'.padEnd(26)+'\n  ROW      '+s(tr)+(sub?'\n  .c-sub   '+s(sub):''));
return o.join('\n')})()"

echo
echo "== console mock, dark: page's own dark :root values applied =="
obscura fetch "$MOCK" --eval "(()=>{$SNAP const css=[...document.querySelectorAll('style')].map(x=>x.textContent).join('\n');const m=css.match(/@media \(prefers-color-scheme: dark\)\{\s*:root\{([\s\S]*?)\}/);if(!m)return 'NO DARK BLOCK';let n=0;for(const d of m[1].split(';')){const i=d.indexOf(':');if(i<0)continue;const k=d.slice(0,i).trim();if(!k.startsWith('--'))continue;document.documentElement.style.setProperty(k,d.slice(i+1).trim());n++;}
const o=['darkVarsApplied='+n];const p=(n2,h,m2)=>{const e=mk(h);const b=s(e);m2(e);o.push(n2.padEnd(26)+'\n  LIVE     '+b+'\n  DISABLED '+s(e));};
p('.btn.primary','<button class=\"btn primary\">P</button>',e=>e.disabled=true);
p('.tb-btn.on','<button class=\"tb-btn on\">T</button>',e=>e.disabled=true);
const tr=document.querySelector('.trow.disabled');tr.setAttribute('aria-selected','true');
o.push('.trow.disabled + selected'.padEnd(26)+'\n  ROW      '+s(tr));
const sw=document.querySelector('button.switch.disabled');
o.push('.switch (page markup)'.padEnd(26)+'\n  DISABLED '+s(sw)+'\n  KNOB     '+s(sw.querySelector('.knob')));
return o.join('\n')})()"

echo
echo "== store page: the bare .btn IS the accent-filled control, and :1098 is disabled =="
obscura fetch "$STORE" --eval "(()=>{$SNAP const d=document.querySelector('#route');const live=document.querySelector('a.btn:not(.ghost)');
return '.btn live'.padEnd(26)+'\n  LIVE     '+s(live)+'\n'+'.btn#route disabled'.padEnd(26)+'\n  DISABLED '+s(d)})()"
