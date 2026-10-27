# Invoked only by the Asystec Desk installer, elevated by its setup program.
#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$PayloadDirectory)
$ErrorActionPreference = 'Stop'
try {
    $exe = Join-Path $PayloadDirectory 'Asystec Desk.exe'
    if ((Get-Item -LiteralPath $exe).VersionInfo.ProductName -ne 'Asystec Desk') { throw 'Payload incorrecto.' }
    $process = Start-Process -FilePath $exe -ArgumentList '--silent-install' -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(180000)) { throw 'La instalacion excedio el tiempo permitido.' }
    $installed = 'C:\Program Files\Asystec Desk\Asystec Desk.exe'
    for ($i=0;$i -lt 30;$i++) {
        $service = Get-Service -Name 'Asystec Desk' -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running' -and (Test-Path -LiteralPath $installed)) { break }
        Start-Sleep -Seconds 1
    }
    if (-not $service -or $service.Status -ne 'Running' -or -not (Test-Path -LiteralPath $installed)) {
        throw 'No se pudo verificar el servicio instalado.'
    }
    if ((Get-FileHash -LiteralPath $exe).Hash -ne (Get-FileHash -LiteralPath $installed).Hash) { throw 'El archivo instalado no coincide con el paquete.' }
    exit 0
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
