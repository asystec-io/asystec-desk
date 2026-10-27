#requires -Version 5.1
# Launches a disposable Windows instance. Never runs the installer on the host.
param([ValidatePattern('^[A-Za-z0-9_-]+$')][string]$RunName = 'sandbox-test')
$ErrorActionPreference = 'Stop'
$repository = Split-Path $PSScriptRoot -Parent
$inputDirectory = Join-Path $repository 'dist\sandbox-input'
$outputDirectory = Join-Path $repository ("dist\$RunName")
New-Item -ItemType Directory -Path $inputDirectory,$outputDirectory -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repository 'dist\Asystec-Soporte-Setup.exe') -Destination $inputDirectory -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'windows\Instalar-Asystec.ps1') -Destination $inputDirectory -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'tests\Test-InstalledExe.ps1') -Destination $inputDirectory -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'tests\Start-SandboxTest.ps1') -Destination $inputDirectory -Force
$configPath = Join-Path $repository 'dist\Asystec-Installer-Test.wsb'
$inputXml = [Security.SecurityElement]::Escape($inputDirectory)
$outputXml = [Security.SecurityElement]::Escape($outputDirectory)
@"
<Configuration>
  <MemoryInMB>4096</MemoryInMB>
  <Networking>Enable</Networking>
  <AudioInput>Disable</AudioInput>
  <VideoInput>Disable</VideoInput>
  <ClipboardRedirection>Disable</ClipboardRedirection>
  <MappedFolders>
    <MappedFolder><HostFolder>$inputXml</HostFolder><SandboxFolder>C:\AsystecQAInput</SandboxFolder><ReadOnly>true</ReadOnly></MappedFolder>
    <MappedFolder><HostFolder>$outputXml</HostFolder><SandboxFolder>C:\AsystecQAResults</SandboxFolder><ReadOnly>false</ReadOnly></MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\AsystecQAInput\Start-SandboxTest.ps1</Command>
  </LogonCommand>
</Configuration>
"@ | Set-Content -LiteralPath $configPath -Encoding UTF8
@{state='launching';at_utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $outputDirectory 'status.json') -Encoding UTF8
Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsSandbox.exe') -ArgumentList ('"{0}"' -f $configPath) -WindowStyle Hidden
Write-Output "Sandbox test results: $outputDirectory"
