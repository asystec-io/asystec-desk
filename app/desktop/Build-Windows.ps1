#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SourceDirectory,
    [string]$OutputDirectory,
    [string]$Python = 'python',
    [switch]$CheckOnly,
    [switch]$SkipDependencySetup
)
$ErrorActionPreference = 'Stop'
if (-not $SourceDirectory) {
    $SourceDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) 'app'
    if (-not (Test-Path -LiteralPath $SourceDirectory)) {
        $SourceDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) '.build\asystec-desk-source'
    }
}
if (-not $OutputDirectory) { $OutputDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) 'dist\asystec-desk-dev' }
$missing = [Collections.Generic.List[string]]::new()
foreach ($tool in @('git','cargo','rustc','flutter','flutter_rust_bridge_codegen','cargo-expand','cmake','nasm')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { $missing.Add($tool) }
}
if (-not (Get-Command $Python -ErrorAction SilentlyContinue)) { $missing.Add("Python: $Python") }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$visualStudio = ''
if (Test-Path -LiteralPath $vswhere) {
    $visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
}
if (-not $visualStudio) { $missing.Add('Visual Studio 2022 con Desktop development with C++ y Windows SDK') }
if (-not $env:VCPKG_ROOT -or -not (Test-Path -LiteralPath (Join-Path $env:VCPKG_ROOT 'vcpkg.exe'))) {
    $missing.Add('VCPKG_ROOT con vcpkg.exe (commit 9e593bb18ea69cc5095e012465dcd675a822ed0d)')
}
if (-not $env:LIBCLANG_PATH -or -not (Test-Path -LiteralPath (Join-Path $env:LIBCLANG_PATH 'libclang.dll'))) {
    $missing.Add('LIBCLANG_PATH con LLVM 15.0.6/libclang.dll')
}
if (-not (Test-Path -LiteralPath (Join-Path $SourceDirectory 'ASYSTEC-SOURCE-MANIFEST.json'))) {
    $missing.Add('Codigo preparado mediante desktop/prepare.py')
}
$report = [ordered]@{
    checked_at_utc = [DateTime]::UtcNow.ToString('o')
    ready = ($missing.Count -eq 0)
    missing = @($missing.ToArray())
    source = $SourceDirectory
    status = 'NOT_COMPILED'
}
if ($CheckOnly) { $report | ConvertTo-Json -Depth 4; return }
if ($missing.Count) { throw ('Faltan requisitos: ' + ($missing -join '; ')) }
if (Test-Path -LiteralPath $OutputDirectory) { throw 'La salida ya existe; utiliza otra carpeta para conservar artefactos anteriores.' }

function Invoke-Checked([string]$Command, [string[]]$Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Fallo de ${Command}: $LASTEXITCODE" }
}
$SourceDirectory = [IO.Path]::GetFullPath($SourceDirectory)
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
Push-Location $SourceDirectory
try {
    Invoke-Checked $Python @('-c', 'import hashlib,json,pathlib,sys; p=pathlib.Path("."); m=json.loads((p/"ASYSTEC-SOURCE-MANIFEST.json").read_text()); allowed={"flutter/pubspec.lock"} if sys.argv[1]=="True" else set(); bad=[f for f,h in m["files"].items() if f not in allowed and (not (p/f).is_file() or hashlib.sha256((p/f).read_bytes()).hexdigest()!=h)]; assert not bad, "Source modified: "+str(bad[:10])', [string][bool]$SkipDependencySetup)
    # Use the versions in the upstream release workflow. Fail on a different SDK.
    $flutterVersion = (& flutter --version) | Out-String
    if ($flutterVersion -notmatch 'Flutter 3\.24\.5\b') { throw 'Se requiere Flutter 3.24.5.' }
    $rustVersion = (& rustc --version) | Out-String
    if ($rustVersion -notmatch 'rustc 1\.75\.') { throw 'Se requiere el toolchain Rust 1.75 de upstream.' }
    $bridgeVersion = (& flutter_rust_bridge_codegen --version) | Out-String
    if ($bridgeVersion -notmatch '1\.80\.1\b') { throw 'Se requiere flutter_rust_bridge_codegen 1.80.1.' }
    if (-not $SkipDependencySetup) {
        Invoke-Checked (Join-Path $env:VCPKG_ROOT 'vcpkg.exe') @('install','--triplet','x64-windows-static',"--x-install-root=$env:VCPKG_ROOT/installed")
        Push-Location flutter
        try { Invoke-Checked 'flutter' @('pub','get') } finally { Pop-Location }
        Invoke-Checked 'flutter_rust_bridge_codegen' @('--rust-input','./src/flutter_ffi.rs','--dart-output','./flutter/lib/generated_bridge.dart','--c-output','./flutter/macos/Runner/bridge_generated.h','--llvm-path',(Split-Path $env:LIBCLANG_PATH -Parent))
    }
    # MSBuild may retain Runner.rc.res when only the referenced ICO changes.
    (Get-Item -LiteralPath 'flutter/windows/runner/Runner.rc').LastWriteTimeUtc = [DateTime]::UtcNow
    Invoke-Checked $Python @('build.py','--flutter','--skip-portable-pack')
    $release = Join-Path $SourceDirectory 'flutter\build\windows\x64\runner\Release'
    foreach ($required in @('rustdesk.exe','librustdesk.dll','flutter_windows.dll','data')) {
        if (-not (Test-Path -LiteralPath (Join-Path $release $required))) { throw "Compilacion incompleta: falta $required" }
    }
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
    Get-ChildItem -LiteralPath $release | Copy-Item -Destination $OutputDirectory -Recurse
    Rename-Item -LiteralPath (Join-Path $OutputDirectory 'rustdesk.exe') -NewName 'Asystec Desk.exe'
    & (Join-Path $PSScriptRoot 'Verify-WindowsBranding.ps1') -Executable (Join-Path $OutputDirectory 'Asystec Desk.exe')
    Copy-Item -LiteralPath LICENCE,ASYSTEC-NOTICE.txt -Destination $OutputDirectory
    # The source bundle includes generated bridges and branding/build instructions.
    Invoke-Checked $Python @('-c', 'import pathlib,zipfile,sys; root=pathlib.Path("."); out=pathlib.Path(sys.argv[1]); excluded={".git","target","build",".dart_tool","ephemeral","__pycache__"}; z=zipfile.ZipFile(out,"w",zipfile.ZIP_DEFLATED); [z.write(f,"Asystec-Desk-source/"+f.as_posix()) for f in root.rglob("*") if f.is_file() and not excluded.intersection(f.parts)]; z.close()', (Join-Path $OutputDirectory 'Asystec-Desk-source.zip'))
    $report.status = 'COMPILED_NOT_RUNTIME_TESTED'
    $report['files'] = @(Get-ChildItem -LiteralPath $OutputDirectory -Recurse -File | ForEach-Object {
        @{path=$_.FullName.Substring($OutputDirectory.Length + 1); sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
    })
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'build-manifest.json') -Encoding UTF8
    Write-Output $OutputDirectory
} finally { Pop-Location }
