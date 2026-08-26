#!/usr/bin/env bash
# M31's rendered oracle for the design of record.
#
# `make mock-fidelity` exits 3 on an inherited break (MeasureDump/main.swift:206, a non-exhaustive
# switch missing `.readme`), so the project's own rendered lane is unavailable. This substitutes
# Obscura against the mock directly: it sets `disabled` on a real control and reads the computed
# cascade, which is what a source read cannot settle.
#
# Dark is reached by applying the page's OWN `@media (prefers-color-scheme: dark)` :root block to
# the root element, because Obscura accepts `Emulation.setEmulatedMedia` and is inert on it. That
# proves the button rule resolves correctly under dark token VALUES; it does not prove the media
# query fires. Stated rather than glossed.
#
# Longhands only — `padding`, `margin` and `borderRadius` shorthands misreport in this engine.
# `backgroundColor`, `color` and `opacity` are on the reliable list.
set -euo pipefail
MOCK="file://$(git rev-parse --show-toplevel)/design/mcp-router-console.html"

echo "== light: a disabled primary, and the adjacent accent-filled controls =="
obscura fetch "$MOCK" --eval "(()=>{const o=[];const snap=e=>{const s=getComputedStyle(e);return s.backgroundColor+' fg='+s.color+' op='+s.opacity+' cur='+s.cursor;};const mk=h=>{const d=document.createElement('div');d.innerHTML=h;document.body.appendChild(d);return d.firstElementChild;};const p=(n,h,m)=>{const e=mk(h);const b=snap(e);m(e);o.push(n+'\n  BEFORE '+b+'\n  AFTER  '+snap(e));};p('btn.primary','<button class=\"btn primary\">P</button>',e=>e.disabled=true);p('btn.primary .disabled','<button class=\"btn primary\">P</button>',e=>e.classList.add('disabled'));p('tb-btn.on','<button class=\"tb-btn on\">T</button>',e=>e.disabled=true);p('switch aria-checked','<button class=\"switch\" role=\"switch\" aria-checked=\"true\"></button>',e=>e.disabled=true);p('trow aria-selected','<div class=\"trow\" aria-selected=\"true\">R</div>',e=>e.classList.add('disabled'));return o.join('\n')})()"

echo "== dark: same control, page's own dark :root values applied =="
obscura fetch "$MOCK" --eval "(()=>{const css=[...document.querySelectorAll('style')].map(s=>s.textContent).join('\n');const m=css.match(/@media \(prefers-color-scheme: dark\)\{\s*:root\{([\s\S]*?)\}/);if(!m)return 'NO DARK BLOCK';let n=0;for(const d of m[1].split(';')){const i=d.indexOf(':');if(i<0)continue;const k=d.slice(0,i).trim();if(!k.startsWith('--'))continue;document.documentElement.style.setProperty(k,d.slice(i+1).trim());n++;}const b=document.querySelector('button.btn.primary');const s=e=>{const c=getComputedStyle(e);return c.backgroundColor+' fg='+c.color+' bc='+c.borderTopColor;};const live=s(b);b.disabled=true;return 'darkVarsApplied='+n+'\n  LIVE     '+live+'\n  DISABLED '+s(b)})()"
