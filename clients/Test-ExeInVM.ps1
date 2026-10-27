#requires -Version 5.1
# Host runner: all installer execution is confined to WindowsTest.
[CmdletBinding()]
param([string]$OutputDirectory, [pscredential]$Credential)
$ErrorActionPreference = 'Stop'
$repository = Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repository 'dist\vm-test' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$statusPath = Join-Path $OutputDirectory 'status.json'
function Write-TestStatus($State, $Detail) {
    @{state=$State; detail=$Detail; at_utc=[DateTime]::UtcNow.ToString('o')} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statusPath -Encoding UTF8
}
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this optional VM test from an administrator PowerShell window. Use Test-ExeInSandbox.ps1 for a fresh disposable environment.'
}
if (-not $Credential) { $Credential = Get-Credential -UserName tester -Message 'Administrator account inside WindowsTest (not the host)' }
if ($Credential.Password.Length -eq 0) { throw 'PowerShell Direct requires a usable guest credential. Use Windows Sandbox for password-free automated testing.' }
$session = $null
try {
    Import-Module Hyper-V
    $vm = Get-VM -Name WindowsTest -ErrorAction Stop
    $checkpoint = 'Before-Asystec-RustDesk-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    Write-TestStatus 'checkpoint' $checkpoint
    & 'C:\VMs\WindowsTestTools\Manage-WindowsTestVM.ps1' -Action checkpoint -SnapshotName $checkpoint |
        Out-File (Join-Path $OutputDirectory 'checkpoint.log')
    if ($vm.State -ne 'Running') {
        & 'C:\VMs\WindowsTestTools\Manage-WindowsTestVM.ps1' -Action start |
            Out-File (Join-Path $OutputDirectory 'start.log')
    }
    Write-TestStatus 'connecting' $checkpoint
    # Do not guess or retry passwords: that can lock the guest account.
    $session = New-PSSession -VMName WindowsTest -Credential $Credential -ErrorAction Stop
    $guestRoot = 'C:\CodexDrop\Asystec Setup QA'
    Invoke-Command -Session $session -ArgumentList $guestRoot -ScriptBlock {
        param($Root)
        New-Item -ItemType Directory -Path $Root -Force | Out-Null
    }
    $installer = Join-Path $repository 'dist\Asystec-Soporte-Setup.exe'
    # Copy via PowerShell Direct, preserving the exact artifact bytes.
    Copy-Item -ToSession $session -LiteralPath $installer -Destination $guestRoot -Force
    Copy-Item -ToSession $session -LiteralPath (Join-Path $PSScriptRoot 'windows\Instalar-Asystec.ps1') -Destination $guestRoot -Force
    $hostHash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
    $guestHash = Invoke-Command -Session $session -ArgumentList $guestRoot -ScriptBlock {
        param($Root)
        (Get-FileHash -LiteralPath (Join-Path $Root 'Asystec-Soporte-Setup.exe') -Algorithm SHA256).Hash
    }
    if ($hostHash -ne $guestHash) { throw 'VM artifact hash differs from the output EXE.' }
    Write-TestStatus 'running' @{checkpoint=$checkpoint; sha256=$hostHash}
    Invoke-Command -Session $session -FilePath (Join-Path $PSScriptRoot 'tests\Test-InstalledExe.ps1')
    Copy-Item -FromSession $session -Path ($guestRoot + '\results\*') -Destination $OutputDirectory -Recurse -Force
    Write-TestStatus 'complete' @{checkpoint=$checkpoint; sha256=$hostHash}
} catch {
    if ($session -and $session.State -eq 'Opened') {
        Copy-Item -FromSession $session -Path 'C:\CodexDrop\Asystec Setup QA\results\*' -Destination $OutputDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-TestStatus 'error' @{message=$_.Exception.Message; detail=($_ | Out-String)}
} finally {
    if ($session) { Remove-PSSession $session }
}
