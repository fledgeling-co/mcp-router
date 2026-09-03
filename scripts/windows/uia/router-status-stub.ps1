<#
.SYNOPSIS
  A stand-in for the router's /status, so the ambient surface can be driven into a named state
  from outside the application. DEF-301's lever.

.DESCRIPTION
  The shell's ambient readout renders whatever the router's /status says. Two of the four states
  it can render - "work in flight" and "a server is waiting for you to sign in" - cannot be
  induced on this host without a real upstream doing real work, and an arm that cannot drive a
  state cannot witness it. So this script answers /status itself, on the port the lane's router
  was using, with counts the lane chose.

  IT IS NOT THE RECORDER AND IT IS NOT PART OF THE PRODUCT. It is the thing being read: the lane
  starts it, the shell polls it knowing nothing about it, and the readout is then read back off
  the automation plane by a third process. What the app is told and what the app displays are
  separate measurements, taken by separate readers.

  A raw TcpListener rather than HttpListener: an HttpListener prefix on 127.0.0.1 needs a URL
  reservation this account does not have, and the failure - Access is denied - reads like the port
  being taken.

.PARAMETER Port
  The loopback port to answer on. The lane passes the port its own router had, so the shell's
  endpoint resolution needs no help.

.PARAMETER InFlight
  Tool calls to claim are in flight, spread over two children so the surface's summing is what is
  being read rather than a single field copied through.

.PARAMETER PendingAuth
  Upstreams to claim are waiting for the operator to sign in.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][int] $Port,
    [int] $InFlight = 0,
    [int] $PendingAuth = 0
)

$ErrorActionPreference = 'Continue'

$first = [Math]::Ceiling($InFlight / 2.0)
$second = $InFlight - $first
$children = @(
    @{ name = 'lane-stub-alpha'; transport = 'stdio'; state = 'running'; callsServed = 1; inFlight = [int] $first; idleSec = 0 },
    @{ name = 'lane-stub-beta';  transport = 'stdio'; state = 'running'; callsServed = 1; inFlight = [int] $second; idleSec = 0 }
)
$pending = @()
for ($i = 0; $i -lt $PendingAuth; $i++) {
    $pending += @{ name = "lane-stub-pending-$i"; url = 'https://example.invalid/mcp' }
}

$body = @{
    ok          = $true
    port        = $Port
    idleMs      = 900000
    children    = $children
    pendingAuth = $pending
    tools       = 0
} | ConvertTo-Json -Depth 6 -Compress

$bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
$header = "HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
$headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()
Write-Host "router-status-stub listening on 127.0.0.1:$Port, inFlight=$InFlight pendingAuth=$PendingAuth"

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            # Read what the client sent before answering. Closing on an unread request stream is
            # how a socket-level reset reaches HttpClient as "the connection was closed", which
            # the shell would report as an unreachable router - a false negative manufactured by
            # the instrument.
            $stream.ReadTimeout = 1500
            $buffer = New-Object byte[] 4096
            try { [void] $stream.Read($buffer, 0, $buffer.Length) } catch { }
            $stream.Write($headerBytes, 0, $headerBytes.Length)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush()
        } catch {
            Write-Host "stub: $($_.Exception.Message)"
        } finally {
            $client.Close()
        }
    }
} finally {
    $listener.Stop()
}
