---
status: to-triage
found-by: reckon 1.7.0, 2026-08-29
---

# Prove the tool cache is keyed on a server's identity, rather than asserting it

- origin: reckon 1.7.0, `REQ-002` standing on the project's own word · 2026-08-29
- audience: whoever debugs a router serving tools from a server that has since changed
- platforms: n/a
- proposed-by-ai: true

## What and why

The product states that the tool cache is keyed on each server's command, arguments and environment
identity, and that tools are namespaced per server. That statement carries evidence `reported` —
nothing has watched the key change when the identity does.

It matters because both halves fail invisibly and in opposite directions. A cache that does not
re-key when a server's command changes serves the previous server's tools under the new one's name,
and everything downstream looks correct: the tools list is populated, the names resolve, calls
succeed against the wrong process. A namespace collision has the same quality. Neither produces an
error anybody would trace back.

The capability is small and specific: change one component of a server's identity, and observe that
what the cache holds for it changes with it — and that changing nothing changes nothing, which is the
control that makes the first observation mean something.

## Acceptance sketch

- Altering a server's command, its arguments, or its environment is shown to change what the cache
  holds for that server.
- Leaving a server's identity untouched is shown to leave the cache untouched, so the check has both
  arms.
- Two servers offering a same-named tool are observed keeping their names apart.
- The requirement stops resting on the project's own word, and the requirement-observed denominator
  reflects it.

## Assumptions made writing this

- Assuming the observation is made against a running router and a real cache rather than against the
  keying function alone, since a correct key computed and then not used is the failure worth catching.
- Assuming each component of the identity is exercised separately, because one component being
  load-bearing does not tell you about the others.
