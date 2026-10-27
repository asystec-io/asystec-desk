#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$CacheDirectory = (Join-Path $env:LOCALAPPDATA 'Asystec\RustDeskBuild\1.5.0'),
    [string]$OutputDirectory,
    [string]$CompilerPath
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'windows\Instalar-Asystec.ps1')
if (-not $OutputDirectory) { $OutputDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) 'dist' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory, $CacheDirectory -Force | Out-Null

if (-not $CompilerPath) {
    $compilerRoot = Join-Path $env:LOCALAPPDATA 'Asystec\BuildTools\InnoSetup-6.7.3'
    $CompilerPath = Join-Path $compilerRoot 'ISCC.exe'
    if (-not (Test-Path -LiteralPath $CompilerPath -PathType Leaf)) {
        $download = Join-Path $CacheDirectory 'innosetup-6.7.3.exe'
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/jrsoftware/issrc/releases/tags/is-6_7_3'
        $asset = @($release.assets | Where-Object name -eq 'innosetup-6.7.3.exe')[0]
        if ($asset.digest -notmatch '^sha256:([0-9a-f]{64})$') { throw 'GitHub did not provide the Inno Setup SHA256.' }
        $expectedCompilerHash = $Matches[1]
        if (-not (Test-Path -LiteralPath $download)) {
            Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $download
        }
        if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ne $expectedCompilerHash) {
            throw 'Inno Setup download hash mismatch.'
        }
        $signature = Get-AuthenticodeSignature -LiteralPath $download
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Pyrsys B\.V\.') {
            throw 'Inno Setup publisher signature is not valid.'
        }
        # Install the build tool only for this user. Never installs RustDesk on the build host.
        $arguments = '/CURRENTUSER /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /DIR="{0}"' -f $compilerRoot
        $process = Start-Process -FilePath $download -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
        if ($process.ExitCode -ne 0) { throw "Inno Setup compiler installation failed: $($process.ExitCode)" }
    }
}
if (-not (Test-Path -LiteralPath $CompilerPath -PathType Leaf)) { throw 'ISCC.exe not found.' }

$msi = Join-Path $CacheDirectory $PackageInfo.MsiName
if (-not (Test-Path -LiteralPath $msi)) {
    Invoke-WebRequest -UseBasicParsing -Uri $PackageInfo.MsiUrl -OutFile $msi
}
Assert-OfficialPackage -Path $msi -ExpectedHash $PackageInfo.MsiSha256
$staging = Join-Path ([IO.Path]::GetTempPath()) ('Asystec-Exe-Build-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $staging | Out-Null
Copy-Item -LiteralPath $msi -Destination $staging
foreach ($name in @('Instalar-Asystec.ps1', 'LICENSE-RUSTDESK.txt', 'LEEME-INSTALADOR.txt')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "windows\$name") -Destination $staging
}
$definitions = @("/DPayloadDir=$staging", "/DOutputDir=$OutputDirectory",
    "/DPackageVersion=$($PackageInfo.Version)", "/DInstallerRevision=$($PackageInfo.InstallerRevision)")
& $CompilerPath @definitions (Join-Path $PSScriptRoot 'windows\Asystec-Soporte.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed: $LASTEXITCODE" }
$output = Join-Path $OutputDirectory 'Asystec-Soporte-Setup.exe'
$manifest = [ordered]@{
    built_at_utc = [DateTime]::UtcNow.ToString('o')
    rustdesk_version = $PackageInfo.Version
    installer_revision = $PackageInfo.InstallerRevision
    server = $PackageInfo.HostAddress
    name = [IO.Path]::GetFileName($output)
    bytes = (Get-Item -LiteralPath $output).Length
    sha256 = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
    authenticode = [string](Get-AuthenticodeSignature -LiteralPath $output).Status
    compiler_version = (Get-Item -LiteralPath $CompilerPath).VersionInfo.FileVersion
    compiler_sha256 = (Get-FileHash -LiteralPath $CompilerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    inputs = @(
        @(Get-ChildItem -LiteralPath $staging -File) + @(Get-Item -LiteralPath (Join-Path $PSScriptRoot 'windows\Asystec-Soporte.iss')) |
            ForEach-Object { [ordered]@{name=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()} }
    )
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'exe-manifest.json') -Encoding UTF8
$manifest | ConvertTo-Json -Depth 6
