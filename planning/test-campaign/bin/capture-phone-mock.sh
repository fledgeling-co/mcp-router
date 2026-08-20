#!/usr/bin/env bash
# Capture ONE unit of an iPhone mock as a design-of-record reference.
#
# The whole-page reference these replace was a 1280x720 viewport shot of the page's top, because
# `obscura fetch --screenshot` has no viewport flag. On the Mac prototype that is survivable — the
# window is 915px tall and roughly 200px falls below the fold. On the phone mocks it is not: Queue
# lives 4205px down i3 and Library 5912px down, so a top-of-page reference for either names a
# subject it does not show, which is the hazard this campaign closed once already.
#
# So the page is conditioned before the shutter: every unit but the named one is removed, and the
# surviving one is moved to the document top. That is the same kind of conditioning as the Mac
# prototype's `?pane=…&only=mac` deep link — it selects what renders and changes nothing about what
# the design specifies. The unit label is read back out of the page and printed, so a capture that
# selected the wrong unit says so rather than being filed under a name it does not show.
set -euo pipefail

mock=$1        # absolute path to the mock html
sect=$2        # the section key: the letter in the h2's badge
unit=$3        # the unit's caption text, exactly, within that section
out=$4         # png path

read -r -d '' JS <<'EOF' || true
(()=>{const want=%%UNIT%%, key=%%SECT%%;
 const s=[...document.querySelectorAll('.sect')].find(e=>{
   const k=e.querySelector('.k'); return k && k.textContent.trim()===key;});
 if(!s) return JSON.stringify({found:false,why:'no section '+key});
 const u=[...s.querySelectorAll('.unit')].find(e=>{
   const b=e.querySelector('.cap b'); return b && b.textContent.trim()===want;});
 if(!u) return JSON.stringify({found:false});
 const label=u.querySelector('.cap b').textContent.trim();
 document.body.innerHTML='';
 document.body.style.padding='24px';
 document.body.appendChild(u);
 return JSON.stringify({found:true,label,h:Math.ceil(document.documentElement.scrollHeight)});})()
EOF
JS=${JS//%%UNIT%%/\'$unit\'}
JS=${JS//%%SECT%%/\'$sect\'}

log=$(obscura fetch "file://$mock" --eval "$JS" --screenshot "$out" 2>&1)
readback=$(printf '%s\n' "$log" | grep -m1 '"evaluation"' || true)
[ -n "$readback" ] || { printf '%s\n' "$log" >&2; echo "no evaluation envelope — the eval did not run" >&2; exit 1; }
python3 - "$readback" <<'PY'
import json, sys
env = json.loads(sys.argv[1])
inner = json.loads(env["evaluation"]) if isinstance(env.get("evaluation"), str) else env["evaluation"]
if isinstance(inner, str):
    inner = json.loads(inner)
if not inner.get("found"):
    sys.exit("not isolated (%s) — the PNG is the whole page, not this unit"
             % inner.get("why", "no such unit in that section"))
print(f"unit readback: {inner['label']!r} · page height after isolation: {inner['h']}px")
PY
