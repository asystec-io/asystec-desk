#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$repository = Split-Path $PSScriptRoot -Parent
$dist = Join-Path $repository 'dist'
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $dist 'publication' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$exe = Join-Path $dist 'Asystec-Soporte-Setup.exe'
$manifest = Get-Content -LiteralPath (Join-Path $dist 'exe-manifest.json') -Raw | ConvertFrom-Json
$verification = Get-Content -LiteralPath (Join-Path $dist 'exe-verification.json') -Raw | ConvertFrom-Json
$exeHash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
if ($manifest.sha256 -cne $exeHash -or $verification.exe_sha256 -cne $exeHash -or $verification.result -ne 'PASS') {
    throw 'The release EXE must match the successfully tested artifact.'
}
$staging = Join-Path ([IO.Path]::GetTempPath()) ('Asystec-Release-' + [Guid]::NewGuid().ToString('N'))
$folder = Join-Path $staging 'Asystec-RustDesk-Instalador'
New-Item -ItemType Directory -Path $folder | Out-Null
Copy-Item -LiteralPath $exe -Destination $folder
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'windows\LEEME-EXE.txt') -Destination (Join-Path $folder 'LEEME-INSTALADOR.txt')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'windows\LICENSE-RUSTDESK.txt') -Destination $folder
$archivePath = Join-Path $OutputDirectory 'Asystec-RustDesk-Instalador.zip'
Compress-Archive -LiteralPath $folder -DestinationPath $archivePath -CompressionLevel Optimal -Force
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    $entry = @($archive.Entries | Where-Object Name -eq 'Asystec-Soporte-Setup.exe')
    if ($entry.Count -ne 1) { throw 'Release archive does not contain exactly one installer.' }
    $stream = $entry[0].Open()
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $embeddedHash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose(); $stream.Dispose() }
    if ($embeddedHash -cne $exeHash) { throw 'The embedded EXE differs from the tested artifact.' }
    $entries = @($archive.Entries | ForEach-Object { [ordered]@{name=$_.FullName;bytes=$_.Length} })
} finally { $archive.Dispose() }
$release = [ordered]@{
    built_at_utc = [DateTime]::UtcNow.ToString('o')
    installer_version = "$($manifest.rustdesk_version).$($manifest.installer_revision)"
    exe_sha256 = $exeHash
    zip_sha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    zip_bytes = (Get-Item -LiteralPath $archivePath).Length
    entries = $entries
}
$release | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'release-manifest.json') -Encoding UTF8
$release | ConvertTo-Json -Depth 6
