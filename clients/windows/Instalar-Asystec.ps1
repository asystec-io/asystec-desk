#requires -Version 5.1
<#
Installs RustDesk, configures Asystec and creates a permanent password per PC.
Run -ValidateOnly to verify the package without installing or changing RustDesk.
The --config and --option commands are supported by RustDesk 1.5.0.
#>
[CmdletBinding()]
param(
    [switch]$ValidateOnly,
    [switch]$ShowCredentials,
    [switch]$NoCredentialWindow,
    [string]$PackagePath,
    [string]$LogPath
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$script:PackageInfo = [ordered]@{
    Version = '1.5.0'
    InstallerRevision = 3
    HostAddress = '184.197.59.221'
    Relay = '184.197.59.221:21117'
    Key = '6o6MWnTv2Vh6l+1oCrfEnlUSNQmMXaaLpqctaNcCulg='
    MsiName = 'rustdesk-1.5.0-x86_64.msi'
    MsiUrl = 'https://github.com/rustdesk/rustdesk/releases/download/1.5.0/rustdesk-1.5.0-x86_64.msi'
    MsiSha256 = '624fe792ab1d76b35134dab84bff97a6bcd14043ffd090a2c6a2800f77580495'
    ExeName = 'rustdesk-1.5.0-x86_64.exe'
    ExeUrl = 'https://github.com/rustdesk/rustdesk/releases/download/1.5.0/rustdesk-1.5.0-x86_64.exe'
    ExeSha256 = '8555777215510d83d2d61c9dc984e4fcc838bd7e79f9d18a42585431f5e8bb47'
}

function ConvertTo-RustDeskConfig {
    param([System.Collections.IDictionary]$Settings)
    $json = $Settings | ConvertTo-Json -Compress
    $base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)).
        TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $characters = $base64.ToCharArray()
    [Array]::Reverse($characters)
    return -join $characters
}

function Write-SetupLog {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $Message
    Add-Content -LiteralPath $script:SetupLog -Value $line -Encoding UTF8
}

function Assert-OfficialPackage {
    param([string]$Path, [string]$ExpectedHash)
    $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actualHash -ne $ExpectedHash) {
        throw "El SHA256 del archivo no coincide con la version oficial: $Path"
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or
        $null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=PURSLANE(?:,|$)') {
        throw "No se pudo verificar la firma oficial PURSLANE: $($signature.Status). Comprueba la fecha y la conexion a Internet."
    }
}

function Get-VerifiedMsi {
    param([string]$ExplicitPath)
    if ($ExplicitPath) {
        $candidate = (Resolve-Path -LiteralPath $ExplicitPath).Path
    } else {
        $candidate = Join-Path $PSScriptRoot $script:PackageInfo.MsiName
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            $downloadDirectory = Join-Path ([IO.Path]::GetTempPath()) ('Asystec-RustDesk-' + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $downloadDirectory | Out-Null
            $candidate = Join-Path $downloadDirectory $script:PackageInfo.MsiName
            Write-SetupLog 'Descargando RustDesk desde GitHub oficial...'
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            $oldProgress = $ProgressPreference
            try {
                $ProgressPreference = 'SilentlyContinue'
                Invoke-WebRequest -UseBasicParsing -Uri $script:PackageInfo.MsiUrl -OutFile $candidate -TimeoutSec 180
            } finally {
                $ProgressPreference = $oldProgress
            }
        }
    }
    Assert-OfficialPackage -Path $candidate -ExpectedHash $script:PackageInfo.MsiSha256
    Write-SetupLog 'Archivo MSI verificado: SHA256 y firma digital correctos.'
    return $candidate
}

function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string]$Value)
    # Windows CommandLineToArgvW/C runtime quoting, including trailing backslashes.
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

function Invoke-RustDeskCli {
    param([string]$Executable, [string[]]$Arguments)
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Executable
    $startInfo.Arguments = ($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'No se pudo iniciar RustDesk.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            $process.Kill()
            throw 'RustDesk no respondio a la configuracion en 30 segundos.'
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult().Trim()
        $stderr = $stderrTask.GetAwaiter().GetResult().Trim()
        if ($process.ExitCode -ne 0) {
            if ($Arguments[0] -eq '--password') { throw 'RustDesk rechazo la asignacion de la contrasena.' }
            throw "RustDesk devolvio $($process.ExitCode): $stderr"
        }
        # Never include password-command output in diagnostics, even on failure.
        if ($Arguments[0] -eq '--password') {
            if ($stdout -cne 'Done!') { throw 'RustDesk no confirmo que guardo la contrasena permanente.' }
            return $stdout
        }
        if ($stdout -match 'privileges required|Settings are disabled|Failed to') {
            throw "RustDesk no acepto el comando: $stdout"
        }
        return $stdout
    } finally {
        $process.Dispose()
    }
}

function Find-RustDeskExecutable {
    $service = Get-CimInstance Win32_Service -Filter "Name='RustDesk'" -ErrorAction SilentlyContinue
    $candidates = @()
    if ($service -and $service.PathName) {
        if ($service.PathName -match '^"([^"]+\.exe)"') {
            $candidates += $Matches[1]
        } elseif ($service.PathName -match '^(.+?\.exe)(?:\s|$)') {
            $candidates += $Matches[1]
        }
    }
    foreach ($root in @($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($root) { $candidates += Join-Path $root 'RustDesk\rustdesk.exe' }
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Get-RustDeskServerSettings {
    param([string]$Executable)
    return [ordered]@{
        host = Invoke-RustDeskCli $Executable @('--option', 'custom-rendezvous-server')
        key = Invoke-RustDeskCli $Executable @('--option', 'key')
        api = Invoke-RustDeskCli $Executable @('--option', 'api-server')
        relay = Invoke-RustDeskCli $Executable @('--option', 'relay-server')
    }
}

function Test-ServerSettingsMatch {
    param([System.Collections.IDictionary]$Actual, [System.Collections.IDictionary]$Expected)
    foreach ($name in @('host', 'key', 'api', 'relay')) {
        if ($Actual[$name] -cne $Expected[$name]) { return $false }
    }
    return $true
}

function New-DevicePassword {
    # 64 symbols, 24 independent bytes: 144 bits, without modulo bias.
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
    $bytes = New-Object byte[] 24
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $random.GetBytes($bytes)
        return -join @($bytes | ForEach-Object { $alphabet[([int]$_ -band 63)] })
    } finally { $random.Dispose(); [Array]::Clear($bytes, 0, $bytes.Length) }
}

function New-CredentialDirectoryAcl {
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sidValue in @('S-1-5-18', 'S-1-5-32-544')) {
        $sid = New-Object Security.Principal.SecurityIdentifier($sidValue)
        $rule = New-Object Security.AccessControl.FileSystemAccessRule(
            $sid, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    return $acl
}

function Initialize-CredentialDirectory {
    $directory = Join-Path $env:ProgramData 'Asystec\RustDesk'
    # Refuse redirected paths before elevated writes.
    $cursor = $directory
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw 'La carpeta de credenciales no puede ser un enlace ni un archivo.'
            }
        }
        $cursor = Split-Path -Path $cursor -Parent
    }
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    Set-Acl -LiteralPath $directory -AclObject (New-CredentialDirectoryAcl)
    return $directory
}

function Get-DeviceIdentity {
    return (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid).MachineGuid
}

function Read-DeviceCredential {
    param([string]$Path, [string]$DeviceIdentity)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $plaintext = $null
    try {
        if ((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Invalid path' }
        Add-Type -AssemblyName System.Security
        $plaintext = [Security.Cryptography.ProtectedData]::Unprotect(
            [IO.File]::ReadAllBytes($Path), $null, [Security.Cryptography.DataProtectionScope]::LocalMachine)
        $record = [Text.Encoding]::UTF8.GetString($plaintext) | ConvertFrom-Json
        if ($record.schema -ne 1 -or $record.device -cne $DeviceIdentity -or
            $record.password -cnotmatch '^[A-Za-z0-9_-]{24}$' -or
            $record.client_id -notmatch '^\d+$' -or $record.applied -isnot [bool]) { throw 'Invalid record' }
        return $record
    } catch {
        throw 'No se pueden leer las credenciales guardadas de este equipo. No se generara otra contrasena sobre ese archivo.'
    } finally {
        if ($null -ne $plaintext) { [Array]::Clear($plaintext, 0, $plaintext.Length) }
    }
}

function Write-DeviceCredential {
    param([string]$Path, $Record)
    $plaintext = $null
    $temporaryPath = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        Add-Type -AssemblyName System.Security
        $plaintext = [Text.Encoding]::UTF8.GetBytes(($Record | ConvertTo-Json -Compress))
        $ciphertext = [Security.Cryptography.ProtectedData]::Protect(
            $plaintext, $null, [Security.Cryptography.DataProtectionScope]::LocalMachine)
        [IO.File]::WriteAllBytes($temporaryPath, $ciphertext)
        if (Test-Path -LiteralPath $Path) {
            if ((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Invalid path' }
            # PowerShell coerces $null to ""; NullString preserves a null backup path.
            [IO.File]::Replace($temporaryPath, $Path, [System.Management.Automation.Language.NullString]::Value)
        } else {
            [IO.File]::Move($temporaryPath, $Path)
        }
    } catch {
        throw 'No se pudo guardar la copia cifrada de las credenciales.'
    } finally {
        if ($null -ne $plaintext) { [Array]::Clear($plaintext, 0, $plaintext.Length) }
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
}

function Get-OrCreateDeviceCredential {
    param([string]$Path, [string]$DeviceIdentity, [string]$ClientId)
    $record = Read-DeviceCredential $Path $DeviceIdentity
    if ($null -eq $record) {
        $record = [pscustomobject]@{
            schema = 1
            device = $DeviceIdentity
            client_id = $ClientId
            password = New-DevicePassword
            applied = $false
        }
        # Persist before applying: an interrupted run can reuse this same password.
        Write-DeviceCredential $Path $record
    }
    return $record
}

function Set-DevicePermanentPassword {
    param([string]$Executable, [string]$Password)
    $ack = Invoke-RustDeskCli $Executable @('--password', $Password)
    if ($ack -cne 'Done!') { throw 'RustDesk no confirmo la contrasena permanente.' }
    $options = [ordered]@{
        'verification-method' = 'use-permanent-password'
        'approve-mode' = 'password-click'
    }
    foreach ($name in $options.Keys) {
        Invoke-RustDeskCli $Executable @('--option', $name, $options[$name]) | Out-Null
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        $matchesExpected = $true
        foreach ($name in $options.Keys) {
            $actual = Invoke-RustDeskCli $Executable @('--option', $name)
            if ($actual -cne $options[$name]) { $matchesExpected = $false }
        }
        if ($matchesExpected) { return }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'La contrasena se envio, pero no se pudo verificar el modo de autorizacion.'
}

function Show-DeviceCredential {
    param($Record)
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form = New-Object Windows.Forms.Form
    $form.Text = 'Asystec - Credenciales de este equipo'
    $form.ClientSize = New-Object Drawing.Size(540, 260)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.Font = New-Object Drawing.Font('Segoe UI', 10)
    $intro = New-Object Windows.Forms.Label
    $intro.SetBounds(20, 15, 500, 50)
    $intro.Text = "Guarda estos datos para conectar con este equipo.`r`nLa contrasena permanece entre sesiones y reinicios."
    $idLabel = New-Object Windows.Forms.Label
    $idLabel.SetBounds(20, 78, 125, 25)
    $idLabel.Text = 'ID RustDesk:'
    $idField = New-Object Windows.Forms.TextBox
    $idField.SetBounds(150, 75, 365, 28)
    $idField.ReadOnly = $true
    $idField.Text = $Record.client_id
    $passwordLabel = New-Object Windows.Forms.Label
    $passwordLabel.SetBounds(20, 118, 125, 25)
    $passwordLabel.Text = 'Contrasena:'
    $passwordField = New-Object Windows.Forms.TextBox
    $passwordField.SetBounds(150, 115, 365, 28)
    $passwordField.ReadOnly = $true
    $passwordField.UseSystemPasswordChar = $true
    $passwordField.Text = $Record.password
    $reveal = New-Object Windows.Forms.CheckBox
    $reveal.SetBounds(150, 150, 320, 30)
    $reveal.Text = 'Mostrar contrasena'
    $reveal.Add_CheckedChanged({ $passwordField.UseSystemPasswordChar = -not $reveal.Checked })
    $copy = New-Object Windows.Forms.Button
    $copy.SetBounds(20, 200, 255, 35)
    $copy.Text = 'Copiar ID y contrasena'
    $copy.Add_Click({
        try {
            [Windows.Forms.Clipboard]::SetText("Equipo: $env:COMPUTERNAME`r`nID RustDesk: $($idField.Text)`r`nContrasena: $($passwordField.Text)")
            $copy.Text = 'Copiado'
        } catch {
            [Windows.Forms.MessageBox]::Show('No se pudo copiar. Intenta nuevamente.', 'Asystec') | Out-Null
        }
    })
    $close = New-Object Windows.Forms.Button
    $close.SetBounds(390, 200, 125, 35)
    $close.Text = 'Cerrar'
    $close.Add_Click({ $form.Close() })
    $form.Controls.AddRange(@($intro, $idLabel, $idField, $passwordLabel, $passwordField, $reveal, $copy, $close))
    try { $form.ShowDialog() | Out-Null } finally { $passwordField.Clear(); $form.Dispose() }
}

function Invoke-AsystecSetup {
    param([switch]$CheckOnly, [switch]$ViewCredentials, [switch]$NoCredentialWindow, [string]$MsiPath, [string]$RequestedLog)
    if ($CheckOnly -and $ViewCredentials) { throw 'Usa solo uno de los modos ValidateOnly o ShowCredentials.' }
    if ($env:OS -ne 'Windows_NT') { throw 'Este instalador requiere Windows.' }
    $architecture = $env:PROCESSOR_ARCHITEW6432
    if (-not $architecture) { $architecture = $env:PROCESSOR_ARCHITECTURE }
    if ($architecture -ne 'AMD64') { throw 'Este paquete es para Windows de 64 bits (Intel/AMD), no ARM ni 32 bits.' }

    if (-not $RequestedLog) {
        $RequestedLog = Join-Path ([IO.Path]::GetTempPath()) ('Asystec-RustDesk-' + [Guid]::NewGuid().ToString('N') + '.log')
    }
    $script:SetupLog = [IO.Path]::GetFullPath($RequestedLog)
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $CheckOnly -and -not $isAdmin) {
        Write-Host 'Windows solicitara permiso de administrador para instalar y configurar RustDesk.'
        Write-Host 'La instalacion puede tardar unos minutos. Espera el resultado en esta ventana.'
        $powershellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $argumentValues = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-LogPath', $script:SetupLog)
        if ($ViewCredentials) { $argumentValues += '-ShowCredentials' }
        if ($NoCredentialWindow) { $argumentValues += '-NoCredentialWindow' }
        if ($MsiPath) { $argumentValues += @('-PackagePath', (Resolve-Path -LiteralPath $MsiPath).Path) }
        $arguments = ($argumentValues | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
        # Elevation is performed by Windows UAC; no machine-wide policy is changed.
        $child = Start-Process -FilePath $powershellPath -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
        if (Test-Path -LiteralPath $script:SetupLog) {
            Get-Content -LiteralPath $script:SetupLog | ForEach-Object { Write-Host $_ }
        }
        return $child.ExitCode
    }

    if ($ViewCredentials) {
        $credentialPath = Join-Path $env:ProgramData 'Asystec\RustDesk\credenciales.dat'
        $record = Read-DeviceCredential $credentialPath (Get-DeviceIdentity)
        if ($null -eq $record -or -not $record.applied) { throw 'Primero completa el instalador de Asystec para guardar una contrasena permanente.' }
        Show-DeviceCredential $record
        return 0
    }

    Write-SetupLog 'Asystec - instalacion y configuracion de RustDesk'
    $expected = [ordered]@{
        host = $script:PackageInfo.HostAddress
        key = $script:PackageInfo.Key
        api = ''
        relay = $script:PackageInfo.Relay
    }
    $configuration = ConvertTo-RustDeskConfig $expected
    $msi = Get-VerifiedMsi $MsiPath
    if ($CheckOnly) {
        Write-SetupLog "VALIDADO. Version $($script:PackageInfo.Version), servidor $($expected.host). No se instalo ni se modifico RustDesk."
        return 0
    }

    $executable = Find-RustDeskExecutable
    $restartRequired = $false
    $needsInstall = $true
    if ($executable) {
        $versionText = (Get-Item -LiteralPath $executable).VersionInfo.ProductVersion
        if ($versionText -match '^(\d+\.\d+\.\d+)') {
            $needsInstall = [version]$Matches[1] -lt [version]$script:PackageInfo.Version
        }
    }
    if ($needsInstall) {
        Write-SetupLog "Instalando RustDesk $($script:PackageInfo.Version)..."
        $msiLog = $script:SetupLog + '.msi.log'
        $installArguments = '/i "{0}" /qn /norestart CREATESTARTMENUSHORTCUTS=Y CREATEDESKTOPSHORTCUTS=Y INSTALLPRINTER=N /l*v "{1}"' -f $msi, $msiLog
        $installer = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\msiexec.exe') -ArgumentList $installArguments -WindowStyle Hidden -Wait -PassThru
        if ($installer.ExitCode -notin @(0, 3010)) {
            throw "La instalacion MSI fallo con codigo $($installer.ExitCode). Detalle: $msiLog"
        }
        if ($installer.ExitCode -eq 3010) {
            $restartRequired = $true
            Write-SetupLog 'Windows indica que requiere un reinicio. No se reiniciara automaticamente.'
        }
        $executable = Find-RustDeskExecutable
    } else {
        Write-SetupLog 'RustDesk ya esta instalado en esta version o una posterior. Se aplicara la configuracion.'
    }
    if (-not $executable) { throw 'No se encontro el ejecutable instalado de RustDesk.' }
    $installedSignature = Get-AuthenticodeSignature -LiteralPath $executable
    if ($installedSignature.Status -ne 'Valid' -or
        $null -eq $installedSignature.SignerCertificate -or
        $installedSignature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=PURSLANE(?:,|$)') {
        throw 'El ejecutable instalado no tiene una firma oficial valida. No se ejecutara.'
    }

    $service = Get-Service -Name RustDesk -ErrorAction SilentlyContinue
    if (-not $service) {
        Invoke-RustDeskCli $executable @('--install-service') | Out-Null
        $service = Get-Service -Name RustDesk -ErrorAction Stop
    }
    Set-Service -Name RustDesk -StartupType Automatic
    if ($service.Status -ne 'Running') { Start-Service -Name RustDesk }
    $service.WaitForStatus('Running', [TimeSpan]::FromSeconds(30))

    # A numeric ID confirms that the client IPC is available before reading its settings.
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    $clientId = ''
    do {
        $clientId = Invoke-RustDeskCli $executable @('--get-id')
        if ($clientId -match '^\d+$') { break }
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($clientId -notmatch '^\d+$') { throw 'El servicio inicio, pero su interfaz de configuracion no responde. Reinicia Windows y vuelve a ejecutar el instalador.' }

    $previous = Get-RustDeskServerSettings $executable
    $backupPath = $script:SetupLog + '.previous-server.json'
    $previous | ConvertTo-Json | Set-Content -LiteralPath $backupPath -Encoding UTF8
    Write-SetupLog "Respaldo de los ajustes anteriores: $backupPath"
    Write-SetupLog "Configurando servidor $($expected.host)..."
    Invoke-RustDeskCli $executable @('--config', $configuration) | Out-Null

    # Do not trust exit code alone: RustDesk can return zero for an unapplied config.
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    $verified = $false
    do {
        $actual = Get-RustDeskServerSettings $executable
        $verified = Test-ServerSettingsMatch $actual $expected
        if (-not $verified) { Start-Sleep -Seconds 2 }
    } while (-not $verified -and [DateTime]::UtcNow -lt $deadline)
    if (-not $verified) { throw 'No se pudieron verificar los cuatro ajustes. No se considera completada la configuracion. Consulta el registro.' }

    $credentialDirectory = Initialize-CredentialDirectory
    $lock = $null
    try {
        # Serialize credential creation and application across simultaneous installers.
        $lockPath = Join-Path $credentialDirectory 'configuracion.lock'
        if ((Test-Path -LiteralPath $lockPath) -and
            ((Get-Item -LiteralPath $lockPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'La ruta de bloqueo no puede ser un enlace.'
        }
        try { $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
        catch { throw 'Hay otra configuracion de credenciales en curso o no se puede abrir su archivo de bloqueo.' }
        $credentialPath = Join-Path $credentialDirectory 'credenciales.dat'
        $record = Get-OrCreateDeviceCredential $credentialPath (Get-DeviceIdentity) $clientId
        Write-SetupLog 'Asignando la contrasena permanente propia de este equipo...'
        Set-DevicePermanentPassword $executable $record.password
        $record.client_id = $clientId
        $record.applied = $true
        Write-DeviceCredential $credentialPath $record
    } finally { if ($null -ne $lock) { $lock.Dispose() } }

    Write-SetupLog "LISTO. Servidor ID, relay, clave y API verificados. ID del equipo: $clientId"
    Write-SetupLog 'Contrasena permanente aceptada por RustDesk y modos de autorizacion verificados.'
    Write-SetupLog 'La conexion requiere la contrasena permanente o tu aceptacion manual.'
    Write-SetupLog 'Puedes consultar estos datos de nuevo con VER-CREDENCIALES.cmd.'
    Write-SetupLog "Registro: $script:SetupLog"
    if (-not $NoCredentialWindow) {
        Write-SetupLog 'Copia los datos y cierra la ventana de credenciales para terminar.'
        Show-DeviceCredential $record
    }
    if ($restartRequired) { return 3010 }
    return 0
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $result = Invoke-AsystecSetup -CheckOnly:$ValidateOnly -ViewCredentials:$ShowCredentials -NoCredentialWindow:$NoCredentialWindow -MsiPath $PackagePath -RequestedLog $LogPath
        exit [int]$result
    } catch {
        $message = 'ERROR: ' + $_.Exception.Message
        Write-Host $message -ForegroundColor Red
        if (Get-Variable -Name SetupLog -Scope Script -ErrorAction SilentlyContinue) {
            Add-Content -LiteralPath $script:SetupLog -Value $message -Encoding UTF8 -ErrorAction SilentlyContinue
        }
        exit 1
    }
}
