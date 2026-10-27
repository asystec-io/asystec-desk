#requires -Version 5.1
# Credential handling adapted from clients/windows/Instalar-Asystec.ps1.
# Dot-source for installer/tests; direct execution only displays saved credentials.
[CmdletBinding()]
param([switch]$ShowCredentials)
$ErrorActionPreference = 'Stop'

function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string]$Value)
    # Windows CommandLineToArgvW/C runtime quoting, including trailing backslashes.
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

function Invoke-ConnectionCli {
    param([string]$Executable, [string[]]$Arguments)
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Executable
    $startInfo.WorkingDirectory = Split-Path $Executable -Parent
    $startInfo.Arguments = ($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'No se pudo iniciar Asystec Desk.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            $process.Kill()
            throw 'Asystec Desk no respondio a la configuracion en 30 segundos.'
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult().Trim()
        $stderr = $stderrTask.GetAwaiter().GetResult().Trim()
        if ($process.ExitCode -ne 0) {
            if ($Arguments[0] -eq '--password') { throw 'Asystec Desk rechazo la asignacion de la contraseña.' }
            throw "Asystec Desk devolvio el codigo $($process.ExitCode)."
        }
        # Never include password-command output in diagnostics, even on failure.
        if ($Arguments[0] -eq '--password') {
            if ($stdout -cne 'Done!') { throw 'Asystec Desk no confirmo que guardo la contraseña permanente.' }
            return $stdout
        }
        if ($stdout -match 'privileges required|Settings are disabled|Failed to') {
            throw 'Asystec Desk no acepto la configuracion solicitada.'
        }
        return $stdout
    } finally {
        $process.Dispose()
    }
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
    $directory = Join-Path $env:ProgramData 'Asystec\Desk'
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
        throw 'No se pueden leer las credenciales guardadas de este equipo. No se generara otra contraseña sobre ese archivo.'
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
    $ack = Invoke-ConnectionCli $Executable @('--password', $Password)
    if ($ack -cne 'Done!') { throw 'Asystec Desk no confirmo la contraseña permanente.' }
    $options = [ordered]@{
        'verification-method' = 'use-permanent-password'
        'approve-mode' = 'password-click'
    }
    foreach ($name in $options.Keys) {
        Invoke-ConnectionCli $Executable @('--option', $name, $options[$name]) | Out-Null
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        $matchesExpected = $true
        foreach ($name in $options.Keys) {
            $actual = Invoke-ConnectionCli $Executable @('--option', $name)
            if ($actual -cne $options[$name]) { $matchesExpected = $false }
        }
        if ($matchesExpected) { return }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'La contraseña se envio, pero no se pudo verificar el modo de autorizacion.'
}

function Initialize-ConnectionDetails {
    param([string]$Executable)
    $directory = Initialize-CredentialDirectory
    $lock = $null
    try {
        $lockPath = Join-Path $directory 'configuracion.lock'
        if ((Test-Path -LiteralPath $lockPath) -and
            ((Get-Item -LiteralPath $lockPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'La ruta de bloqueo no puede ser un enlace.'
        }
        try { $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
        catch { throw 'Hay otra configuracion de credenciales en curso. Espera y vuelve a intentarlo.' }
        $clientId = ''
        for ($attempt = 0; $attempt -lt 30; $attempt++) {
            $clientId = Invoke-ConnectionCli $Executable @('--get-id')
            if ($clientId -match '^\d{6,}$') { break }
            Start-Sleep -Seconds 1
        }
        if ($clientId -notmatch '^\d{6,}$') { throw 'No se pudo obtener el ID de Asystec Desk.' }
        $path = Join-Path $directory 'credenciales.dat'
        $record = Get-OrCreateDeviceCredential $path (Get-DeviceIdentity) $clientId
        Set-DevicePermanentPassword $Executable $record.password
        $record.client_id = $clientId
        $record.applied = $true
        Write-DeviceCredential $path $record
    } finally {
        if ($lock) { $lock.Dispose() }
        $record = $null
    }
}

function Show-DeviceCredential {
    param($Record)
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()
    $form = New-Object Windows.Forms.Form
    $form.Text = 'Asystec Desk - Datos de conexión'
    $form.ClientSize = New-Object Drawing.Size(570, 400)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.AutoScaleMode = 'Dpi'
    $form.Font = New-Object Drawing.Font('Segoe UI', 10)
    $form.BackColor = [Drawing.Color]::White
    $iconPath = Join-Path $PSScriptRoot 'Asystec Desk.exe'
    if (Test-Path -LiteralPath $iconPath) { $form.Icon = [Drawing.Icon]::ExtractAssociatedIcon($iconPath) }
    $brandLogo = New-Object Windows.Forms.PictureBox
    $brandLogo.SetBounds(24, 12, 300, 64)
    $brandLogo.SizeMode = 'Zoom'
    $logoPath = Join-Path $PSScriptRoot 'data\flutter_assets\assets\logo_light.png'
    if (Test-Path -LiteralPath $logoPath) { $brandLogo.Load($logoPath) }
    $heading = New-Object Windows.Forms.Label
    $heading.SetBounds(24, 90, 520, 32)
    $heading.Font = New-Object Drawing.Font('Segoe UI', 16, [Drawing.FontStyle]::Bold)
    $heading.ForeColor = [Drawing.ColorTranslator]::FromHtml('#0F1F45')
    $heading.Text = 'Conecta con este equipo'
    $intro = New-Object Windows.Forms.Label
    $intro.SetBounds(24, 130, 520, 42)
    $intro.Text = "Comparte estos datos con tu técnico de confianza.`r`nLa contraseña se conserva al reinstalar Asystec Desk."
    $idLabel = New-Object Windows.Forms.Label
    $idLabel.SetBounds(24, 188, 135, 25)
    $idLabel.Text = 'ID del equipo'
    $idField = New-Object Windows.Forms.TextBox
    $idField.SetBounds(165, 184, 378, 28)
    $idField.ReadOnly = $true
    $idField.Text = $Record.client_id
    $passwordLabel = New-Object Windows.Forms.Label
    $passwordLabel.SetBounds(24, 232, 135, 25)
    $passwordLabel.Text = 'Contraseña'
    $passwordField = New-Object Windows.Forms.TextBox
    $passwordField.SetBounds(165, 228, 378, 28)
    $passwordField.ReadOnly = $true
    $passwordField.UseSystemPasswordChar = $true
    $passwordField.Text = $Record.password
    $reveal = New-Object Windows.Forms.CheckBox
    $reveal.SetBounds(165, 265, 365, 28)
    $reveal.Text = 'Mostrar contraseña'
    $reveal.Add_CheckedChanged({ $passwordField.UseSystemPasswordChar = -not $reveal.Checked })
    $copyPassword = New-Object Windows.Forms.Button
    $copyPassword.SetBounds(24, 312, 176, 38)
    $copyPassword.Text = 'Copiar contraseña'
    $copyPassword.Add_Click({
        try {
            [Windows.Forms.Clipboard]::SetText($passwordField.Text)
            $copyPassword.Text = 'Contraseña copiada'
        } catch { [Windows.Forms.MessageBox]::Show('No se pudo copiar. Intenta nuevamente.', 'Asystec Desk') | Out-Null }
    })
    $copyAll = New-Object Windows.Forms.Button
    $copyAll.SetBounds(210, 312, 190, 38)
    $copyAll.FlatStyle = 'Flat'
    $copyAll.FlatAppearance.BorderSize = 0
    $copyAll.BackColor = [Drawing.ColorTranslator]::FromHtml('#064589')
    $copyAll.ForeColor = [Drawing.Color]::White
    $copyAll.Text = 'Copiar ID y contraseña'
    $copyAll.Add_Click({
        try {
            [Windows.Forms.Clipboard]::SetText("Asystec Desk`r`nEquipo: $env:COMPUTERNAME`r`nID: $($idField.Text)`r`nContraseña: $($passwordField.Text)")
            $copyAll.Text = 'Datos copiados'
        } catch { [Windows.Forms.MessageBox]::Show('No se pudo copiar. Intenta nuevamente.', 'Asystec Desk') | Out-Null }
    })
    $close = New-Object Windows.Forms.Button
    $close.SetBounds(423, 312, 120, 38)
    $close.Text = 'Cerrar'
    $close.Add_Click({ $form.Close() })
    $form.CancelButton = $close
    $hint = New-Object Windows.Forms.Label
    $hint.SetBounds(24, 365, 520, 22)
    $hint.Text = 'Puedes volver a abrir esta ventana desde el menú Inicio.'
    $hint.ForeColor = [Drawing.Color]::DimGray
    $hint.Font = New-Object Drawing.Font('Segoe UI', 9)
    $form.Controls.AddRange(@($brandLogo,$heading,$intro,$idLabel,$idField,$passwordLabel,$passwordField,$reveal,$copyPassword,$copyAll,$close,$hint))
    try { $form.ShowDialog() | Out-Null } finally {
        $passwordField.Clear()
        if ($brandLogo.Image) { $brandLogo.Image.Dispose() }
        $form.Dispose()
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            $parameters = @('-NoProfile','-STA','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-ShowCredentials')
            $arguments = ($parameters | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
            $child = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
            exit $child.ExitCode
        }
        $record = Read-DeviceCredential (Join-Path $env:ProgramData 'Asystec\Desk\credenciales.dat') (Get-DeviceIdentity)
        if (-not $record -or -not $record.applied) { throw 'Completa la instalacion de Asystec Desk para crear los datos de conexion.' }
        $currentId = Invoke-ConnectionCli (Join-Path $PSScriptRoot 'Asystec Desk.exe') @('--get-id')
        if ($currentId -notmatch '^\d{6,}$') { throw 'Abre Asystec Desk y vuelve a intentar consultar los datos de conexion.' }
        $record.client_id = $currentId
        Show-DeviceCredential $record
        exit 0
    } catch {
        Add-Type -AssemblyName System.Windows.Forms
        [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Asystec Desk',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        exit 1
    }
}

