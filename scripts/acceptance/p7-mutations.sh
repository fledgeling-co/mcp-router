#!/usr/bin/env bash
#
# P7 mutation gate — can `scripts/acceptance/parity-oauth.sh` actually go red?
#
# The lane reports 19 checks agreeing across two routers. A series of agreeing observations bounds
# the AGREEMENT rate and says nothing about what the terms MEASURE — `D-p1-e` is this repo's
# standing example, where a term agreed for sixteen observations and was still reading a value no
# stimulus could change. So each mutation below breaks ONE property of the OAuth client the row
# claims to prove, and the lane has to go red on EVERY trial. A mutation that reddens the lane four
# times in five is recorded as a failure here, not rounded up: that is precisely the shape of the
# defect that withdrew `install-launchd-watch`.
#
# Each mutation is a single exact-string edit to production source. The edit is asserted to have
# matched — a mutation that changed nothing would report the unmutated lane's green as proof.
#
# TRIALS is the number of times the lane is run per mutation, and it is printed with every result
# so a reader never has to infer the denominator.
#
# The tree is restored with `git checkout -- app` after every mutation, and once more on exit, so an
# interrupted run leaves the worktree recoverable. Commit before running: the revert is scoped to
# `app/` so it cannot take this script or the lane with it.
#
# Exit codes:
#   0  every mutation reddened the lane on every trial
#   1  a mutation left the lane green, or reddened it only sometimes
#   2  the environment could not run the gate — a mutation that could not be built or a lane that
#      could not run is not a mutation that passed.

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

TRIALS="${P7_MUTATION_TRIALS:-5}"
# A substring filter, so one mutation can be re-run on its own after its snippet went stale. Empty
# runs all of them, which is what a gate run means; a filtered run says so in its own summary.
ONLY="${P7_MUTATION_ONLY:-}"
CLIENT="app/Sources/RouterCore/Auth/OAuthClient.swift"
STARTER="app/Sources/RouterCore/Auth/OAuthFlowStarter.swift"
TOKENS="app/Sources/RouterCore/Auth/OAuthTokenRequest.swift"
LANE="scripts/acceptance/parity-oauth.sh"

restore() { git checkout -- app 2>/dev/null; }
trap 'restore' EXIT INT TERM HUP

[ -f "$LANE" ] || { echo "environment: no lane at $LANE"; exit 2; }
command -v swift >/dev/null 2>&1 || { echo "environment: swift is not installed"; exit 2; }

if ! git diff --quiet -- app; then
  echo "environment: app/ has uncommitted changes. This gate reverts app/ after every mutation,"
  echo "             so it would discard them. Commit or stash first."
  exit 2
fi

build() {
  (cd app && swift build --product MCPRouterCLI 2>&1) > /tmp/p7-mutation-build.log
}

echo "P7 mutation gate — $TRIALS trials per mutation, and every trial must be red"
[ -n "$ONLY" ] && echo "FILTERED to mutations matching \"$ONLY\" — this is not a full gate run"
echo

# The unmutated tree first. A gate that never observes the lane green cannot tell a mutation that
# broke the client from a lane that was broken all along.
build || { echo "environment: the unmutated tree does not build"; sed -n '1,20p' /tmp/p7-mutation-build.log; exit 2; }
if bash "$LANE" > /tmp/p7-mutation-baseline.log 2>&1; then
  echo "baseline: the unmutated lane is GREEN, as it must be before any mutation means anything"
else
  echo "environment: the UNMUTATED lane is not green, so nothing below would be attributable:"
  sed -n '1,40p' /tmp/p7-mutation-baseline.log
  exit 2
fi
echo

pass=0
fail=0
declare -a failures=()

mutate() { # name file python-snippet
  local name="$1" file="$2" snippet="$3"
  local src red green trial status

  if [ -n "$ONLY" ] && [ "${name#*"$ONLY"}" = "$name" ]; then
    return
  fi

  src=$(printf 'import sys\np = sys.argv[1]\ns = open(p).read()\nbefore = s\n%s\nif s == before:\n    sys.exit("the mutation matched nothing, so it is not breaking what it names")\nopen(p, "w").write(s)\n' "$snippet")
  if ! python3 -c "$src" "$file"; then
    echo "FAIL  $name  <- the mutation could not be applied"
    fail=$((fail + 1)); failures+=("$name (unapplied)")
    restore
    return
  fi

  if ! build; then
    echo "FAIL  $name  <- the mutated tree does not build; the mutation is wrong, not the client"
    sed -n '1,12p' /tmp/p7-mutation-build.log | sed 's/^/        /'
    fail=$((fail + 1)); failures+=("$name (unbuildable)")
    restore
    return
  fi

  red=0; green=0
  for trial in $(seq 1 "$TRIALS"); do
    bash "$LANE" > "/tmp/p7-mutation-$trial.log" 2>&1
    status=$?
    case "$status" in
      0) green=$((green + 1)) ;;
      1) red=$((red + 1)) ;;
      *) echo "        trial $trial: the lane could not run (exit $status)"
         sed -n '1,10p' "/tmp/p7-mutation-$trial.log" | sed 's/^/          /'
         green=$((green + 1)) ;;
    esac
  done

  restore
  if [ "$red" = "$TRIALS" ]; then
    echo "RED   $name  <- $red of $TRIALS trials red"
    pass=$((pass + 1))
  else
    echo "FAIL  $name  <- only $red of $TRIALS trials red ($green not red)"
    fail=$((fail + 1)); failures+=("$name ($red/$TRIALS)")
  fi
}

# 1 — PKCE is not sent at all. The fixture's authorization endpoint refuses a request with no
#     challenge, so the flow cannot even reach a code; the URL also differs from the reference's.
mutate "PKCE dropped from the authorization URL" "$CLIENT" '
s = s.replace("""            (name: "code_challenge", value: OAuthPKCE.challenge(for: verifier)),
            (name: "code_challenge_method", value: OAuthPKCE.challengeMethod),
""", "")'

# 2 — `state` is emitted, which is exactly what the vendored Swift SDK does unconditionally and the
#     recorded reason it cannot serve this route. One extra parameter, and it is on the wire.
mutate "a state parameter is emitted" "$CLIENT" '
s = s.replace("""        if let resource { pairs.append((name: "resource", value: resource)) }""",
"""        pairs.append((name: "state", value: "mutant-state"))
        if let resource { pairs.append((name: "resource", value: resource)) }""")'

# 3 — the authorization endpoint is guessed rather than read from the metadata document. This is the
#     mutation the recorded objection to this row asked for: with the provider'"'"'s endpoints behind an
#     unguessable prefix, a client that hardcodes /authorize cannot pass.
mutate "the authorization endpoint is hardcoded at /authorize" "$CLIENT" '
s = s.replace("""        return OAuthTokenRequest.url(metadata.authorizationEndpoint, adding: pairs)""",
"""        let guessed = (OAuthWire.origin(of: metadata.authorizationEndpoint) ?? "") + "/authorize"
        return OAuthTokenRequest.url(guessed, adding: pairs)""")'

# 4 — dynamic client registration is skipped and a client_id is invented. The registration request
#     disappears from the provider'"'"'s log and the client_id differs in the URL and the token request.
mutate "dynamic registration is skipped" "$CLIENT" '
s = s.replace("""        let registered = try await OAuthTokenRequest.register(""",
"""        if true {
            return .object([JSONMember(key: "client_id", value: .string("guessed-client"))])
        }
        let registered = try await OAuthTokenRequest.register(""")'

# 5 — the token request carries no code verifier, so the provider'"'"'s PKCE check refuses the exchange
#     and no credential file is ever written.
mutate "the code verifier is dropped from the token request" "$TOKENS" '
s = s.replace("""            (name: "code_verifier", value: exchange.verifier),
""", "")'

# 6 — the callback listener binds a port the redirect URI does not name. Everything up to the
#     browser hop is unchanged and correct, which is the point: only a lane that follows the
#     redirect through to the router'"'"'s own socket can see this.
mutate "the callback listens on a port nothing redirects to" "$STARTER" '
s = s.replace("""            port: AuthPaths.bindablePort,""",
"""            port: AuthPaths.bindablePort.map { $0 + 7 },""")'

echo
restore
build || { echo "environment: the restored tree does not build"; exit 2; }
if [ "$fail" -eq 0 ]; then
  echo "examined=$pass mutations x $TRIALS trials = $((pass * TRIALS)) lane runs, failures=0"
  echo "every mutation reddened the lane on every trial."
  exit 0
fi
echo "examined=$((pass + fail)) mutations x $TRIALS trials, $fail did not hold:"
for item in "${failures[@]}"; do echo "  - $item"; done
exit 1
