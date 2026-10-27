# Dot-source this file in the process that performs the build. No global PATH changes.
$deskToolsRoot = Join-Path $env:LOCALAPPDATA 'Asystec\DeskBuild'
$deskPythonRoot = 'C:\Users\bryan\.cache\codex-runtimes\codex-primary-runtime\dependencies\python'
$env:VCPKG_ROOT = Join-Path $deskToolsRoot 'vcpkg'
$env:VCPKG_DEFAULT_TRIPLET = 'x64-windows-static'
$env:VCPKG_DEFAULT_HOST_TRIPLET = 'x64-windows-static'
$env:LIBCLANG_PATH = Join-Path $deskToolsRoot 'llvm15\bin'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:DART_SUPPRESS_ANALYTICS = 'true'
$env:RUST_LOG = 'info'
$env:PATH = (@(
    (Join-Path $env:USERPROFILE '.cargo\bin'),
    (Join-Path $deskToolsRoot 'flutter\bin'),
    (Join-Path $deskToolsRoot 'nasm-2.16.03'),
    (Join-Path $deskToolsRoot 'python-tools\cmake\data\bin'),
    (Join-Path $deskToolsRoot 'python-tools\bin'),
    $deskPythonRoot,
    $env:PATH
) -join ';')
$deskVswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path -LiteralPath $deskVswhere) {
    $deskVsPath = & $deskVswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $deskVsPath -and (Test-Path -LiteralPath 'C:\BuildTools\Common7\Tools\VsDevCmd.bat')) { $deskVsPath = 'C:\BuildTools' }
    if ($deskVsPath) {
        $deskVsDevCmd = Join-Path $deskVsPath 'Common7\Tools\VsDevCmd.bat'
        $deskEnvLines = & cmd.exe /s /c "`"`"$deskVsDevCmd`" -arch=x64 -host_arch=x64 >nul && set`""
        foreach ($deskEnvLine in $deskEnvLines) {
            if ($deskEnvLine -match '^([^=]+)=(.*)$') {
                [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
            }
        }
    }
}
# VsDevCmd may point VCPKG_ROOT at Visual Studio's read-only bundled copy.
$env:VCPKG_ROOT = Join-Path $deskToolsRoot 'vcpkg'
