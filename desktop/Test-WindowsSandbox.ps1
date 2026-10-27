#requires -Version 5.1
[CmdletBinding()]
param([string]$BundleDirectory, [string]$RunName = 'asystec-desk-qa')
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (-not $BundleDirectory) { $BundleDirectory = Join-Path $repo 'dist\asystec-desk-dev' }
if (-not (Test-Path -LiteralPath (Join-Path $BundleDirectory 'Asystec Desk.exe'))) { throw 'Falta el cliente compilado.' }
if ($RunName -notmatch '^[a-zA-Z0-9_-]+$') { throw 'RunName invalido.' }
$inputPath = Join-Path $repo "dist\$RunName-input"
$outputPath = Join-Path $repo "dist\$RunName-results"
New-Item -ItemType Directory -Path $inputPath,$outputPath -Force | Out-Null
$bundle = Join-Path $inputPath 'bundle'
New-Item -ItemType Directory -Path $bundle -Force | Out-Null
Get-ChildItem -LiteralPath $BundleDirectory -Exclude '*.zip' | Copy-Item -Destination $bundle -Recurse -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'tests\Sandbox-Runner.ps1'),(Join-Path $PSScriptRoot 'profile.json') -Destination $inputPath -Force
$setup = Join-Path $repo 'dist\Asystec-Desk-Setup.exe'
if (Test-Path -LiteralPath $setup) { Copy-Item -LiteralPath $setup -Destination $inputPath -Force }
$rsa = New-Object Security.Cryptography.RSACryptoServiceProvider 2048
$rsa.PersistKeyInCsp = $false
try {
    [IO.File]::WriteAllText((Join-Path $inputPath 'qa-public.xml'), $rsa.ToXmlString($false))
    $privateBytes = [Text.Encoding]::UTF8.GetBytes($rsa.ToXmlString($true))
    Add-Type -AssemblyName System.Security
    $protected = [Security.Cryptography.ProtectedData]::Protect($privateBytes,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    [IO.File]::WriteAllBytes((Join-Path $repo ".build\$RunName-private.dpapi"),$protected)
} finally { $rsa.Dispose() }
$inputXml = [Security.SecurityElement]::Escape($inputPath)
$outputXml = [Security.SecurityElement]::Escape($outputPath)
$wsb = Join-Path $repo "dist\$RunName.wsb"
@"
<Configuration>
  <MemoryInMB>4096</MemoryInMB>
  <Networking>Enable</Networking>
  <AudioInput>Disable</AudioInput><VideoInput>Disable</VideoInput>
  <ClipboardRedirection>Disable</ClipboardRedirection>
  <MappedFolders>
    <MappedFolder><HostFolder>$inputXml</HostFolder><SandboxFolder>C:\AsystecQAInput</SandboxFolder><ReadOnly>true</ReadOnly></MappedFolder>
    <MappedFolder><HostFolder>$outputXml</HostFolder><SandboxFolder>C:\AsystecQAResults</SandboxFolder><ReadOnly>false</ReadOnly></MappedFolder>
  </MappedFolders>
  <LogonCommand><Command>powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\AsystecQAInput\Sandbox-Runner.ps1</Command></LogonCommand>
</Configuration>
"@ | Set-Content -LiteralPath $wsb -Encoding UTF8
Start-Process -FilePath "$env:SystemRoot\System32\WindowsSandbox.exe" -ArgumentList ('"{0}"' -f $wsb) -WindowStyle Hidden
Write-Output $outputPath
