#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$Executable)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$actualIcon = [Drawing.Icon]::ExtractAssociatedIcon([IO.Path]::GetFullPath($Executable))
$expectedIcon = [Drawing.Icon]::ExtractAssociatedIcon((Join-Path $PSScriptRoot 'assets\icon.ico'))
$actual = $null
$expected = $null
try {
    $actual = $actualIcon.ToBitmap()
    $expected = $expectedIcon.ToBitmap()
    if ($actual.Size -ne $expected.Size) { throw 'El tamano del icono del EXE no coincide con la marca.' }
    for ($y = 0; $y -lt $actual.Height; $y++) {
        for ($x = 0; $x -lt $actual.Width; $x++) {
            if ($actual.GetPixel($x, $y).ToArgb() -ne $expected.GetPixel($x, $y).ToArgb()) {
                throw 'El EXE conserva un icono distinto. Recompila Runner.rc antes de empaquetar.'
            }
        }
    }
    Write-Output 'PASS: el icono integrado en el EXE coincide con el ICO final.'
} finally {
    if ($actual) { $actual.Dispose() }
    if ($expected) { $expected.Dispose() }
    $actualIcon.Dispose()
    $expectedIcon.Dispose()
}
