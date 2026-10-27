#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$CacheDirectory = (Join-Path $env:LOCALAPPDATA 'Asystec\RustDeskBuild\1.5.0'),
    [string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) 'dist'
}
$sourceDirectory = Join-Path $PSScriptRoot 'windows'
. (Join-Path $sourceDirectory 'Instalar-Asystec.ps1')

New-Item -ItemType Directory -Path $CacheDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$buildDirectory = Join-Path ([IO.Path]::GetTempPath()) ('Asystec-RustDesk-build-' + [Guid]::NewGuid().ToString('N'))
$installerDirectory = Join-Path $buildDirectory 'Asystec-RustDesk-Instalador'
$portableDirectory = Join-Path $buildDirectory 'Asystec-RustDesk-Portable'
New-Item -ItemType Directory -Path $installerDirectory, $portableDirectory | Out-Null

foreach ($format in @('Msi', 'Exe')) {
    $filename = $PackageInfo[$format + 'Name']
    $cacheFile = Join-Path $CacheDirectory $filename
    if (-not (Test-Path -LiteralPath $cacheFile)) {
        Invoke-WebRequest -UseBasicParsing -Uri $PackageInfo[$format + 'Url'] -OutFile $cacheFile
    }
    Assert-OfficialPackage -Path $cacheFile -ExpectedHash $PackageInfo[$format + 'Sha256']
}

$licensePath = Join-Path $sourceDirectory 'LICENSE-RUSTDESK.txt'
if (-not (Test-Path -LiteralPath $licensePath)) {
    throw 'Falta LICENSE-RUSTDESK.txt, copia de la licencia de la version oficial.'
}
Copy-Item -LiteralPath (Join-Path $CacheDirectory $PackageInfo.MsiName) -Destination $installerDirectory
foreach ($name in @('Instalar-Asystec.ps1', 'INSTALAR-ASYSTEC.cmd', 'VER-CREDENCIALES.cmd', 'LEEME-INSTALADOR.txt', 'LICENSE-RUSTDESK.txt')) {
    Copy-Item -LiteralPath (Join-Path $sourceDirectory $name) -Destination $installerDirectory
}

$portableName = 'RustDesk-Asystec-host={0},key={1},.exe' -f $PackageInfo.HostAddress, $PackageInfo.Key
if ($portableName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
    throw 'La clave contiene caracteres incompatibles con el metodo de nombre portable.'
}
$portablePath = Join-Path $portableDirectory $portableName
Copy-Item -LiteralPath (Join-Path $CacheDirectory $PackageInfo.ExeName) -Destination $portablePath
Assert-OfficialPackage -Path $portablePath -ExpectedHash $PackageInfo.ExeSha256
Copy-Item -LiteralPath $licensePath -Destination $portableDirectory
Copy-Item -LiteralPath (Join-Path $sourceDirectory 'LEEME-PORTABLE.txt') -Destination $portableDirectory
$launcher = @"
@echo off
setlocal
if not exist "%~dp0$portableName" (
  echo Falta el ejecutable. Extrae el ZIP completo y conserva su nombre.
  pause
  exit /b 1
)
start "" "%~dp0$portableName"
"@
[IO.File]::WriteAllText((Join-Path $portableDirectory 'ABRIR-SOPORTE-ASYSTEC.cmd'), ($launcher -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)

$serverConfiguration = [ordered]@{ host=$PackageInfo.HostAddress; key=$PackageInfo.Key; api=''; relay=$PackageInfo.Relay }
$configString = ConvertTo-RustDeskConfig $serverConfiguration
Set-Content -LiteralPath (Join-Path $OutputDirectory 'Configuracion-Asystec.txt') -Value $configString -Encoding ASCII

foreach ($packageDirectory in @($installerDirectory, $portableDirectory)) {
    $destination = Join-Path $OutputDirectory ((Split-Path $packageDirectory -Leaf) + '.zip')
    Compress-Archive -LiteralPath $packageDirectory -DestinationPath $destination -CompressionLevel Optimal -Force
}
$outputs = Get-ChildItem -LiteralPath $OutputDirectory -Filter '*.zip'
$manifest = [ordered]@{
    built_at_utc = [DateTime]::UtcNow.ToString('o')
    rustdesk_version = $PackageInfo.Version
    installer_revision = $PackageInfo.InstallerRevision
    installer_password_mode = 'random-per-device-persistent'
    server = $PackageInfo.HostAddress
    release = 'https://github.com/rustdesk/rustdesk/releases/tag/1.5.0'
    official_msi_sha256 = $PackageInfo.MsiSha256
    official_exe_sha256 = $PackageInfo.ExeSha256
    packages = @($outputs | ForEach-Object {
        [ordered]@{ name=$_.Name; bytes=$_.Length; sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'manifest.json') -Encoding UTF8
$outputs | Select-Object Name,Length,FullName
