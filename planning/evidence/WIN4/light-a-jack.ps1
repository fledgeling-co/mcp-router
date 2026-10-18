# Light a jack — WIN4's live-call probe.

# The brief's strongest claim: "a jack lights on a real call and darkens when the child is
# reaped". The reference router runs on this machine at 127.0.0.1:8879 with a fixture server
# (`fixture`, tools ping/echo), so the claim is measurable here: this script performs a REAL
# MCP tools/call through /mcp — the product's own path, the same one a harness takes — then
# polls GET /servers and prints what the router reports, which is exactly what the board
# renders. GET is ungated and this script performs no mutating control call, reads no token,
# and prints nothing secret.

# Exit 0: the call went through and a state transition was observed.
# Exit 1: the call failed or no transition was observed within the window.

param(
    [int] $ObserveSeconds = 45,
    [string] $Router = "http://127.0.0.1:8879"
)

$ErrorActionPreference = 'Stop'

# --- the call, over the router's stateless Streamable HTTP transport -----------------------
# Measured: this router constructs its transport with sessionIdGenerator: undefined
# (src/router.ts line 414), so there is no initialize/session handshake to hold — each POST stands
# alone. If a session id comes back anyway, it is carried forward.

$initBody = @{
    jsonrpc = "2.0"; id = 1
    method  = "initialize"
    params  = @{
        protocolVersion = "2025-06-18"
        capabilities    = @{}
        clientInfo      = @{ name = "win4-light-a-jack-probe"; version = "1.0" }
    }
} | ConvertTo-Json -Depth 6

$init = Invoke-WebRequest -Uri "$Router/mcp" -Method Post `
    -ContentType "application/json" -Body $initBody `
    -Headers @{ Accept = "application/json, text/event-stream" } `
    -TimeoutSec 15
$sessionId = $init.Headers["mcp-session-id"]
Write-Host "initialize -> HTTP $($init.StatusCode), session id present: $([bool]$sessionId)"

$sessionHeaders = @{ Accept = "application/json, text/event-stream" }
if ($sessionId) { $sessionHeaders["mcp-session-id"] = $sessionId }

# Discover the fixture server's echo tool's name on the union endpoint, then call it.
$tools = Invoke-WebRequest -Uri "$Router/mcp" -Method Post `
    -ContentType "application/json" -Headers $sessionHeaders `
    -Body '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' -TimeoutSec 15
$payload = ($tools.Content -split "`n" | Select-String '"result"' | Select-Object -First 1).ToString()
$names = if ($payload) { ([regex]::Matches($payload, '"name"\s*:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }) } else { @() }
Write-Host "tools/list -> $($names -join ', ')"
$echo = $names | Where-Object { $_ -match "echo" } | Select-Object -First 1
if (-not $echo) { Write-Host "no echo tool found"; exit 1 }

$callBody = @{
    jsonrpc = "2.0"; id = 3; method = "tools/call"
    params  = @{ name = $echo; arguments = @{ } }
} | ConvertTo-Json -Depth 6
$call = Invoke-WebRequest -Uri "$Router/mcp" -Method Post `
    -ContentType "application/json" -Headers $sessionHeaders `
    -Body $callBody -TimeoutSec 30
Write-Host "tools/call $echo -> HTTP $($call.StatusCode)"

# --- what the board would render -----------------------------------------------------------
$transition = $false
$idleReturn = $false
$deadline = (Get-Date).AddSeconds($ObserveSeconds)
$lastState = ""
while ((Get-Date) -lt $deadline) {
    $envelope = Invoke-RestMethod -Uri "$Router/servers" -TimeoutSec 5
    foreach ($s in $envelope.servers) {
        if ($s.state -ne $lastState) {
            Write-Host ("{0:HH:mm:ss}  {1}: state={2} inFlight={3} idleSec={4}" -f (Get-Date), $s.name, $s.state, $s.inFlight, $s.idleSec)
            $lastState = $s.state
        }
        if ($s.state -eq "running" -or $s.state -eq "starting") { $transition = $true }
        if ($transition -and $s.state -eq "idle") { $idleReturn = $true }
    }
    if ($idleReturn) { break }
    Start-Sleep -Seconds 1
}

if ($transition) {
    Write-Host "observed: the jack lit (state starting/running) on a real call"
    if ($idleReturn) { Write-Host "observed: the jack darkened (state idle) — the child is at rest again" }
    exit 0
}
Write-Host "no state transition observed within ${ObserveSeconds}s"
exit 1
