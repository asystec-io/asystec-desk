# Invoked only by the Asystec Desk installer, elevated by its setup program.
#requires -Version 5.1
param(
    [Parameter(Mandatory=$true)][string]$PayloadDirectory,
    [string]$InstallDirectory,
    [string]$LogPath,
    [string]$ErrorPath
)
$ErrorActionPreference = 'Stop'
if (-not $LogPath) { $LogPath = Join-Path ([IO.Path]::GetTempPath()) ('Asystec-Desk-' + [Guid]::NewGuid().ToString('N') + '.log') }
if (-not $ErrorPath) { $ErrorPath = $LogPath + '.error.txt' }
function Write-InstallLog([string]$Message) {
    Add-Content -LiteralPath $LogPath -Value ('{0} {1}' -f [DateTime]::UtcNow.ToString('o'),$Message) -Encoding UTF8
}
function Read-NativeLog([string]$Path) {
    $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $reader = New-Object IO.StreamReader($stream)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}
$process = $null
try {
    Write-InstallLog "Installer process bits: $([IntPtr]::Size * 8)"
    if (-not [Environment]::Is64BitOperatingSystem) { throw 'Asystec Desk requiere Windows de 64 bits.' }
    if (-not $InstallDirectory) {
        $registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
        $key = $null
        try {
            $key = $registry.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion')
            $programs = [string]$key.GetValue('ProgramFilesDir')
        } finally { if ($key) { $key.Dispose() }; $registry.Dispose() }
        if (-not $programs) { throw 'No se pudo obtener la carpeta nativa de programas de Windows.' }
        $InstallDirectory = Join-Path $programs 'Asystec Desk'
    }
    $InstallDirectory = [IO.Path]::GetFullPath($InstallDirectory)
    if ((Split-Path $InstallDirectory -Leaf) -ne 'Asystec Desk') { throw 'La carpeta de destino debe terminar en Asystec Desk.' }
    # The native client reads this inherited variable, including from 32-bit launchers.
    $env:ProgramFiles = Split-Path $InstallDirectory -Parent
    Write-InstallLog "Destination: $InstallDirectory"
    $exe = Join-Path $PayloadDirectory 'Asystec Desk.exe'
    if ((Get-Item -LiteralPath $exe).VersionInfo.ProductName -ne 'Asystec Desk') { throw 'Payload incorrecto.' }
    $stdout = $LogPath + '.native.stdout.txt'
    $stderr = $LogPath + '.native.stderr.txt'
    $process = Start-Process -FilePath $exe -ArgumentList '--silent-install' -WorkingDirectory $PayloadDirectory -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    # Cache the handle before waiting so Windows PowerShell retains ExitCode.
    # Redirect to files: tray/service children may keep stdout pipes open.
    $null = $process.Handle
    if (-not $process.WaitForExit(180000)) { throw 'La instalacion excedio el tiempo permitido.' }
    $process.Refresh()
    $nativeOutput = Read-NativeLog $stdout
    Write-InstallLog "Native exit code: $($process.ExitCode)"
    Write-InstallLog $nativeOutput
    Write-InstallLog (Read-NativeLog $stderr)
    $nativeFailure = @($nativeOutput -split '\r?\n' | Where-Object { $_ -match '^Failed with error:' })
    if ($nativeFailure.Count) { throw ($nativeFailure -join ' ') }
    if ($process.ExitCode -ne 0) { throw "El cliente interno termino con codigo $($process.ExitCode)." }
    $installed = Join-Path $InstallDirectory 'Asystec Desk.exe'
    $service = $null
    for ($i=0;$i -lt 30;$i++) {
        $service = Get-CimInstance Win32_Service -Filter "Name='Asystec Desk'"
        if ($service -and $service.State -eq 'Running' -and (Test-Path -LiteralPath $installed)) { break }
        Start-Sleep -Seconds 1
    }
    if ($service) { Write-InstallLog "Service: $($service.State); image: $($service.PathName); exit: $($service.ExitCode)" }
    if (-not $service -or $service.State -ne 'Running') { throw 'El servicio Asystec Desk no esta activo. Consulta el registro de instalacion.' }
    if (-not (Test-Path -LiteralPath $installed)) { throw "No se encontro el ejecutable instalado en $installed. Servicio: $($service.PathName)" }
    if ($service.PathName -notmatch '^"([^"]+\.exe)"(?:\s|$)' -or [IO.Path]::GetFullPath($Matches[1]) -ine $installed) {
        throw "El servicio usa una ruta distinta de la instalacion: $($service.PathName)"
    }
    if ((Get-FileHash -LiteralPath $exe).Hash -ne (Get-FileHash -LiteralPath $installed).Hash) { throw 'El archivo instalado no coincide con el paquete.' }
    Write-InstallLog 'SUCCESS: service and installed executable verified.'
    exit 0
} catch {
    Write-InstallLog ('ERROR: ' + $_.Exception.Message)
    Set-Content -LiteralPath $ErrorPath -Value $_.Exception.Message -Encoding UTF8
    Write-Error $_ -ErrorAction Continue
    exit 1
} finally {
    if ($process) { $process.Dispose() }
}
