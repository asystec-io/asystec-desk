# Runs inside Windows Sandbox under its administrator test account.
$ErrorActionPreference = 'Stop'
$outputDirectory = 'C:\AsystecQAResults'
$root = 'C:\CodexDrop\Asystec Setup QA'
$completedMarker = Join-Path $root 'automated-tests-completed.txt'
# Sandbox repeats LogonCommand after a Windows reboot. Do not rerun the
# installer then: reboot checks must observe persistence without reconfiguration.
if (Test-Path -LiteralPath $completedMarker) { return }
function Save-Status($State,$Detail) {
    @{state=$State;detail=$Detail;at_utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $outputDirectory 'status.json') -Encoding UTF8
}
try {
    Save-Status 'running' 'Preparing a fresh Windows installation test.'
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    Copy-Item -Path 'C:\AsystecQAInput\*' -Destination $root -Force
    & (Join-Path $root 'Test-InstalledExe.ps1')
    Save-Status 'complete' 'Automated EXE installation and configuration checks passed.'
    [DateTime]::UtcNow.ToString('o') | Set-Content -LiteralPath $completedMarker
} catch {
    Save-Status 'error' ($_ | Out-String)
} finally {
    if (Test-Path -LiteralPath (Join-Path $root 'results')) {
        Copy-Item -Path (Join-Path $root 'results\*') -Destination $outputDirectory -Recurse -Force
    }
}
# Leave the real installer visible for the interactive UI check after automated checks.
if (Test-Path -LiteralPath (Join-Path $root 'Asystec-Soporte-Setup.exe')) {
    Start-Process -FilePath (Join-Path $root 'Asystec-Soporte-Setup.exe') -WindowStyle Normal
}
