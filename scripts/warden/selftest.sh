#!/bin/bash
# Proves the W2 migration path end to end against a SCRATCH secret, never a live one.
#
# The arms that matter are the refusals. A migration script that writes is easy; one that declines
# to write a config the router would reject, or one with a credential nobody has placed, is the
# half worth arming — because both failures land at upstream connection time, hours later, as an
# error that names neither.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok()   { echo "  ok    $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL  $1"; fail=$((fail+1)); }

cat > "$TMP/servers.json" <<'JSON'
{ "port": 8879, "mcpServers": {
  "scratch": { "command": "/bin/true", "env": { "SCRATCH_API_KEY": "sk-not-a-real-secret-0000", "PATH": "/usr/bin" } } } }
JSON
chmod 600 "$TMP/servers.json"

cat > "$TMP/plan.json" <<JSON
{ "config": "$TMP/servers.json", "rows": [
  {"upstream":"scratch","block":"env","key":"SCRATCH_API_KEY","is_secret":true,"uri":"<CHOOSE>"},
  {"upstream":"scratch","block":"env","key":"PATH","is_secret":false,"uri":null} ] }
JSON
cp "$TMP/plan.json" "$HERE/migration-plan.json.testbak" 2>/dev/null
[ -f "$HERE/migration-plan.json" ] && cp "$HERE/migration-plan.json" "$TMP/real-plan.json"
cp "$TMP/plan.json" "$HERE/migration-plan.json"

# ARM 1 — a placeholder must refuse, and must not write.
/usr/bin/python3 "$HERE/apply-migration.py" --out "$TMP/out1.json" >/dev/null 2>&1
[ $? -eq 1 ] && [ ! -f "$TMP/out1.json" ] && ok "a credential with no vault URI refuses, and writes nothing" \
  || bad "a placeholder did not refuse, or wrote anyway"

# ARM 2 — a filled plan writes a copy, and the value is gone from it.
sed -i '' 's|<CHOOSE>|warden://scratch/api-key|' "$HERE/migration-plan.json"
/usr/bin/python3 "$HERE/apply-migration.py" --out "$TMP/out2.json" >/dev/null 2>&1
if [ -f "$TMP/out2.json" ] && ! grep -q 'sk-not-a-real-secret' "$TMP/out2.json" \
   && grep -q 'warden://scratch/api-key' "$TMP/out2.json"; then
  ok "a filled plan writes a copy carrying the URI and not the value"
else bad "the copy still holds the value, or lost the URI"; fi

# ARM 3 — the live config is untouched by a copy run.
grep -q 'sk-not-a-real-secret-0000' "$TMP/servers.json" \
  && ok "the source config was not modified by a copy run" || bad "the source config was modified"

# ARM 4 — configuration is copied through, not rewritten.
grep -q '"PATH": "/usr/bin"' "$TMP/out2.json" \
  && ok "a configuration entry passed through untouched" || bad "configuration was rewritten"

# ARM 5 — the copy is 0600.
[ "$(stat -f '%Lp' "$TMP/out2.json")" = "600" ] \
  && ok "the written copy is mode 0600" || bad "the copy is not 0600"

# ARM 6 — a URI the router would reject must refuse.
sed -i '' 's|warden://scratch/api-key|vault:scratch/api-key|' "$HERE/migration-plan.json"
/usr/bin/python3 "$HERE/apply-migration.py" --out "$TMP/out3.json" >/dev/null 2>&1
[ $? -eq 1 ] && [ ! -f "$TMP/out3.json" ] \
  && ok "a URI the router's own predicate rejects refuses, and writes nothing" \
  || bad "an unrecognised URI scheme was accepted"

# ARM 7 — --in-place without --backup refuses.
sed -i '' 's|vault:scratch/api-key|warden://scratch/api-key|' "$HERE/migration-plan.json"
/usr/bin/python3 "$HERE/apply-migration.py" --in-place >/dev/null 2>&1
[ $? -eq 1 ] && grep -q 'sk-not-a-real-secret-0000' "$TMP/servers.json" \
  && ok "--in-place without --backup refuses and leaves the config alone" \
  || bad "--in-place wrote without a backup"

[ -f "$TMP/real-plan.json" ] && cp "$TMP/real-plan.json" "$HERE/migration-plan.json"
rm -f "$HERE/migration-plan.json.testbak"
echo
echo "warden-migration selftest: $pass held, $fail did not"
[ "$fail" -eq 0 ] || exit 1
