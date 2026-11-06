#requires -Version 5.1
# Installed under Program Files. Runs once, or as a retry after an offline setup.
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'Connection-Details.ps1')
    $endpoint = [uri]((Get-Content (Join-Path $PSScriptRoot 'Book-Profile.json') -Raw | ConvertFrom-Json).api_server)
    if (-not $endpoint.IsAbsoluteUri -or $endpoint.Scheme -ne 'https' -or $endpoint.UserInfo) { throw 'Invalid enrollment endpoint' }
    $peer = (Invoke-ConnectionCli (Join-Path $PSScriptRoot 'Asystec Desk.exe') @('--get-id')).Trim()
    if ($peer -notmatch '^[0-9]{6,16}$') { throw 'Device ID pending' }
    $machine = ([guid](Get-DeviceIdentity)).ToString('D')
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes("asystec-enroll-v1:${peer}:$machine")
        $proof = [BitConverter]::ToString($hash.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()
    } finally { $hash.Dispose() }
    $body = @{id=$peer; alias=[Environment]::MachineName; proof=$proof} | ConvertTo-Json -Compress
    $reply = Invoke-WebRequest -UseBasicParsing -Method Post -Uri ([uri]::new($endpoint, '/api/asystec/enroll')) -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 12 -MaximumRedirection 0
    if ($reply.StatusCode -ne 204) { throw 'Enrollment pending' }
    Unregister-ScheduledTask -TaskName 'Asystec Desk - Alta libreta' -Confirm:$false -ErrorAction SilentlyContinue
    exit 0
} catch {
    exit 1
}
