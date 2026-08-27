# M29 decisions — out-of-family lane: gemini-3.7-flash-high via `agy --new-project`

Run 2026-08-25 from `/tmp` (neutral cwd), bounded at 600s, exit 0. The reply names this
project's own subject — `unionTools`, `visibleTo`, the TypeScript reference and the Swift
`RouterCore` port, the macOS servers table — so the lane answered about M29 rather than about
another repo's item. Prompt: `/tmp/m29/prompt.txt` (not retained), option order as listed in the spec.

Verdict: **(a) A1 · (b) B2 · (c) global boolean**.

---

### (a) Keep Manifest Row and Cached State: Take **A1**

**Choice: A1 (Keep manifest row, digest, and approved tools; omit `disabled` from `upstreamHash`)**

* **Why:** 
  1. **UI Fidelity & Held-Schema Flow:** The macOS UI specifically renders Last-seen ("4 d ago") and Tools as an em-dash (`—`), not `0`. If disabling dropped the manifest row or emptied `entry.tools` (A2), cached metadata needed for historical display and held-schema diffing is destroyed.
  2. **Conceptual Separation:** Transport identity belongs in `upstreamHash()`; operational routing policy (`projects`, `warm`, `placard`, `disabled`) does not. Disabling is a temporary administrative toggle. Re-enabling should restore known state immediately without triggering an expensive, unprompted re-index.
* **What A2 is better at:** Guaranteeing schema freshness on re-enable. A2 ensures an upstream that altered its tool definitions while disabled cannot accidentally serve stale definitions without a re-indexing pass.

---

### (b) Skipping Disabled Servers in `unionTools`: Take **B2**

**Choice: B2 (Explicit config check evaluated before manifest lookup)**

* **Why:**
  1. **Eliminates Semantic Overloading:** As noted in the triage report, `entry.tools.length === 0` is already broken by carrying three meanings (*never indexed*, *failed index*, *zero tools declared*). Routing disabled servers through that same check compounds the defect.
  2. **Structural Parity with `visibleTo`:** Filtering by routing policy belongs at the outer dispatch loop before inspecting manifest payload data. Checking `if (u.disabled) continue;` alongside `if (!visibleTo(u, opts.cwd)) continue;` mirrors identically in both the TypeScript reference and Swift `RouterCore`.
* **What B1 is better at:** Minimizing changes to `unionTools`’ signature and loop body by treating "disabled" entirely as data eviction at the manifest store boundary.

---

### (c) Scope: Take **C1**

**Choice: C1 (`disabled?: boolean` — Global)**

* **Why:**
  1. **Matches Threat Model & UI:** The primary driver is the held-schema alert ("Disable mobbin") and the global macOS servers table. If a server’s schema changed unexpectedly, it is untrusted everywhere, not just in specific folders.
  2. **Avoids Precedence Ambiguity:** Introducing a deny-list (C2/C3) creates conflicting states when a path matches both `projects` (allow) and `disabled` (deny), requiring duplicate resolution logic across TypeScript and Swift. `projects` already handles positive scoping ("live in A, not in B").
  3. **Control API Cleanliness:** Keeps `PATCH /servers/:name` simple (`{ disabled?: boolean }`).
* **What C2/C3 is better at:** Negative targeting in large setups (e.g., "disable this heavy indexer in repo X only" without having to explicitly list all other valid repos in `projects`).

---

### Better Approach

Combine **A1 + B2 + C1** with two targeted architectural improvements:

1. **Unified Eligibility Predicate (`isServed`):**
   Instead of ad-hoc checks in `unionTools`, introduce an upstream routing predicate in `manifest.ts` and `RouterCore`:
   ```ts
   export function isServed(u: UpstreamConfig, cwd: string | undefined): boolean {
     return !u.disabled && visibleTo(u, cwd);
   }
   ```
   This encapsulates all pre-manifest filtering in one place and prevents future call sites (tool execution, completions, prompt listings) from omitting the `disabled` check.

2. **Explicit Derived Status on Control API:**
   Do not let the macOS client guess whether a server is disabled, errored, or unindexed by inspecting empty arrays. Return a single derived status enum from the router:
   ```ts
   type ServerStatus = 'active' | 'disabled' | 'error' | 'unindexed';
   ```
   * If `u.disabled === true` $\rightarrow$ `'disabled'`
   * Else if `entry.error` $\rightarrow$ `'error'`
   * Else if `!entry` $\rightarrow$ `'unindexed'`
   * Else $\rightarrow$ `'active'`

This cleanly resolves the existing triage defect, keeps `manifest.json` purely as a cache of remote capabilities, and maintains byte-for-byte behavioral parity across TypeScript and Swift.
