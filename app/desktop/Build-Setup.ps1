#requires -Version 5.1
param([string]$BundleDirectory,[string]$OutputDirectory,[string]$CompilerPath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (-not $BundleDirectory) { $BundleDirectory = Join-Path $repo 'dist\asystec-desk-dev' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repo 'dist' }
if (-not $CompilerPath) { $CompilerPath = Join-Path $env:LOCALAPPDATA 'Asystec\BuildTools\InnoSetup-6.7.3\ISCC.exe' }
foreach ($file in @('Asystec Desk.exe','librustdesk.dll','flutter_windows.dll','Asystec-Desk-source.zip')) {
    if (-not (Test-Path -LiteralPath (Join-Path $BundleDirectory $file))) { throw "Falta $file" }
}
if ((Get-Item -LiteralPath (Join-Path $BundleDirectory 'Asystec Desk.exe')).VersionInfo.ProductName -ne 'Asystec Desk') { throw 'El cliente no tiene la marca esperada.' }
& (Join-Path $PSScriptRoot 'Verify-WindowsBranding.ps1') -Executable (Join-Path $BundleDirectory 'Asystec Desk.exe')
$arguments = @("/DBundleDir=$([IO.Path]::GetFullPath($BundleDirectory))", "/DOutputDir=$([IO.Path]::GetFullPath($OutputDirectory))", "/DDesktopDir=$PSScriptRoot", (Join-Path $PSScriptRoot 'Asystec-Desk.iss'))
& $CompilerPath @arguments
if ($LASTEXITCODE -ne 0) { throw "Inno Setup: $LASTEXITCODE" }
$exe = Join-Path $OutputDirectory 'Asystec-Desk-Setup.exe'
$manifest = [ordered]@{
    at_utc = [DateTime]::UtcNow.ToString('o')
    status = 'BUILT_NOT_RUNTIME_TESTED'
    name = 'Asystec-Desk-Setup.exe'
    sha256 = (Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant()
    bytes = (Get-Item -LiteralPath $exe).Length
    authenticode = [string](Get-AuthenticodeSignature -LiteralPath $exe).Status
    client_sha256 = (Get-FileHash -LiteralPath (Join-Path $BundleDirectory 'Asystec Desk.exe')).Hash.ToLowerInvariant()
    source_sha256 = (Get-FileHash -LiteralPath (Join-Path $BundleDirectory 'Asystec-Desk-source.zip')).Hash.ToLowerInvariant()
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'asystec-desk-setup-manifest.json') -Encoding UTF8
$manifest | ConvertTo-Json
