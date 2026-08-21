The full prompt was truncated, so I’ll read that offload first and then review the diff from the text only.🫥 **One blocker:** `httpUrl` is read for every harness, so a non-Gemini file can be reported wired (or duplicated) on a key that harness does not speak. Truthiness, detect-on-raw, and not teaching `ServerParser` are the right calls; strip `httpUrl` after copying, and do not treat the write-gate as closed.

### Blocking

**`HarnessDialect.endpointKeys` is global.** `endpoint(in:)` and `detect` take raw JSON only. A Claude/Cursor/Codex-as-JSON entry that still carries Gemini’s key — `{ "command": "npx", "args": ["-y", "foo"], "httpUrl": "http://127.0.0.1:8879/mcp" }`, or a Gemini router block pasted into `~/.claude.json` with no `url` — is classified `.directHTTP`. Claude reads `url`; that key is absent, so the harness is not wired. Observable: `state` is `wired-via-HTTP`, `remedy`/`+ add` are suppressed, which is F1 inverted. The same entry with `httpUrl` equal to an HTTP upstream and a different `command` is canonicalised, parsed as HTTP (truthy `url` selects HTTP in `ServerParser`), and reported as an identity duplicate; `- remove` then deletes the stdio server the harness actually runs. The suite defaults `client: .geminiCLI` and the lane only writes `~/.gemini/settings.json`, so this never goes red. Alternative: a per-client key list (Gemini: `url`, `httpUrl`; everyone else: `url`).

### Should-fix

**`canonicalised` injects `url` and leaves `httpUrl`.** `others` become `{httpUrl, url, …}`. Today `httpURLDuplicateByIdentity` proves `UpstreamHash` does not digest the extra key. If it ever hashes unknown members, every Gemini duplicate silently stops matching. Filter `httpUrl` out when you add `url`.

**`member` vs `members.first`.** `endpoint` uses `raw.member(key)`; `canonicalised` uses the first `url` member. If those disagree on duplicate keys, detect can follow `httpUrl` while comparison keeps a different `url`. Use one lookup.

**Write vocabulary is still line-shaped tokens.** `FileHandle.init(forWritingTo:)` does not match `FileHandle\(forWritingTo:`. Neither does `FileHandle(forUpdatingTo:)` / `forUpdatingAtPath`, `OutputStream(url:append:)`, or `Process`+`/bin/cp`. P5 only plants the first spelling; the rest exit 0.

**Rule 3 is two paths.** `MCPRouterCLI/ApplyVerb.swift` that takes a path from argv and `write(toFile:)` names no harness literal, no `ReconciliationPlan`/`ClientConfigs.path(for:)`, and is not `HarnessesVerb.swift`. Rules 1–2 miss it; rule 3 misses it. The gate prints `none writes one`. That is the next F3, just one file to the left of the seam. Widen rule 3 to `MCPRouterCLI/*.swift` (or every new verb), or keep D-r7-m and stop citing this script as the reason an applier cannot land.

**Rule 2 greps comments; rule 1 does not.** `/// Uses ReconciliationPlan` in a type that already `writeFile`s (the `WatchBackup` shape) is a finding. P6 only covers a path in a `///` line.

**`file_writes` is comment-blind and stream-exclude is same-line.** `// write(toFile:` next to a real path name fails rule 1. `let h = FileHandle.standardOutput` / `h.write(data)` does not match `FileHandle\.standard(Output|Error)` on the write line, so `.write(` counts. P7 only plants the one-liner. A usage string containing `~/.claude.json` plus any later log write is the same false positive.

**`code_of` only drops `^[[:space:]]*//`.** A `/* ~/.claude.json */` block in a writer is code for rule 1.

**Pass 4 “fixture unchanged” is `grep -q '"httpUrl"'`.** An in-place rewrite that adds `url` (or any other mutation) and keeps that substring passes. `cmp` against a copy.

**Pass 5 JSON:** any non-empty, non-`MISSING` `unreadable` passes, including `"ok"`. It never asserts `state`/`duplicateCount`/`+ add` on that row.

**Pass 5 human plan:** `gemini_plan` runs until `nothing applies this plan`. If the unreadable block still prints `Gemini CLI —` and `+ add` and omits that footer, awk keeps `f=1` to EOF and the check is `grep -c 'nothing applies'` == 0, which passes. Pass 4 is the only `+ add` assertion.

### Notes

`${SEAM_LIST+"${SEAM_LIST[@]}"}` is the right `set -u` form. `file_writes` as capture-and-test, not `grep -qv`, is the right BSD empty-input fix. I cannot see the ~14 lines between `REPO_ROOT=` and `FAILURES=0`; the selftest only means anything if `$1` becomes `SOURCES` there.

### Decisions

1. Keep truthiness. Change the key list to per-client, as above. Global `httpUrl` is how you get a false route.
2. Keep `ServerParser`/`UpstreamHash` ignorant of `httpUrl`, and keep `detect` on raw entries. Canonicalise only for comparison, and emit a `url`-only object.
3. Keep file scope. Rule 3’s directory is what still lets an applier through.
