set -u
cd "$(git rev-parse --show-toplevel)"
MOCK=design/mcp-router-console.html
DESIGN=DESIGN.md
run(){ swift test --package-path app --filter MockButtonFidelityTests 2>&1 | grep -E "Test run with|✘|recorded an issue" | head -6; }

cp "$MOCK" /tmp/m31.mock.bak; cp "$DESIGN" /tmp/m31.design.bak

echo "### ARM 1 — restore cursor:not-allowed (targets: declares no cursor)"
sed -i '' 's|border-color:var(--line);}|border-color:var(--line);cursor:not-allowed;}|' "$MOCK"
run
cp /tmp/m31.mock.bak "$MOCK"

echo "### ARM 2 — add an unclaimed property to .btn.primary (targets: cascade guard)"
sed -i '' 's|^\.btn\.primary{background:var(--accent-ink);|.btn.primary{opacity:1;background:var(--accent-ink);|' "$MOCK"
grep -c "opacity:1;background:var(--accent-ink)" "$MOCK"
run
cp /tmp/m31.mock.bak "$MOCK"

echo "### ARM 3 — perturb the ratio in DESIGN.md (targets: design authority states the semantics)"
sed -i '' 's|2\.94:1 in dark|2.95:1 in dark|' "$DESIGN"
run
cp /tmp/m31.design.bak "$DESIGN"

echo "### RESTORED — baseline re-run"
run
