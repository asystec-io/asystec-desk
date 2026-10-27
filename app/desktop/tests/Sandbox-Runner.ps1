# Runs only in a disposable Windows Sandbox. Never run this script on the host.
$ErrorActionPreference = 'Stop'
$output = 'C:\AsystecQAResults'
$checks = [ordered]@{}
$report = [ordered]@{at_utc=[DateTime]::UtcNow.ToString('o');result='RUNNING';checks=$checks}
function Save-Report { $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'verification.json') -Encoding UTF8 }
function Invoke-DeskCli([string[]]$Arguments) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $script:installed
    $info.Arguments = $Arguments -join ' '
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($info)
    if (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'CLI timeout' }
    $text = $process.StandardOutput.ReadToEnd().Trim()
    if ($process.ExitCode -ne 0) { throw "CLI exit: $($process.ExitCode)" }
    $process.Dispose()
    return $text
}
try {
    if ($env:USERNAME -ne 'WDAGUtilityAccount') { throw 'Este script requiere Windows Sandbox.' }
    if (Test-Path -LiteralPath 'C:\AsystecQA-complete.txt') { return }
    Save-Report
    $profile = Get-Content C:\AsystecQAInput\profile.json -Raw | ConvertFrom-Json
    $payload = 'C:\AsystecQA\bundle'
    New-Item -ItemType Directory -Path $payload -Force | Out-Null
    Copy-Item -Path 'C:\AsystecQAInput\bundle\*' -Destination $payload -Recurse -Force
    $artifact = Join-Path $payload 'Asystec Desk.exe'
    $report.exe_sha256 = (Get-FileHash -LiteralPath $artifact).Hash.ToLowerInvariant()
    $report.product_name = (Get-Item -LiteralPath $artifact).VersionInfo.ProductName
    if ($report.product_name -ne 'Asystec Desk') { throw 'ProductName incorrecto.' }
    $checks.windows_product_brand = 'PASS'
    $installInfo = New-Object Diagnostics.ProcessStartInfo
    $installInfo.UseShellExecute = $false
    $installInfo.CreateNoWindow = $true
    if (Test-Path -LiteralPath 'C:\AsystecQAInput\Asystec-Desk-Setup.exe') {
        $report.setup_sha256 = (Get-FileHash -LiteralPath 'C:\AsystecQAInput\Asystec-Desk-Setup.exe').Hash.ToLowerInvariant()
        $installInfo.FileName = 'C:\AsystecQAInput\Asystec-Desk-Setup.exe'
        $installInfo.Arguments = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
    } else {
        $installInfo.FileName = $artifact
        $installInfo.Arguments = '--silent-install'
    }
    $install = [Diagnostics.Process]::Start($installInfo)
    if (-not $install.WaitForExit(180000)) { throw 'Instalacion no termino.' }
    if ($install.ExitCode -ne 0) { throw "Instalador devolvio $($install.ExitCode)." }
    $script:installed = 'C:\Program Files\Asystec Desk\Asystec Desk.exe'
    $service = $null
    for ($i=0;$i -lt 40;$i++) {
        $service = Get-Service -Name 'Asystec Desk' -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running' -and (Test-Path -LiteralPath $script:installed)) { break }
        Start-Sleep -Seconds 1
    }
    if (-not $service -or $service.Status -ne 'Running') { throw 'Servicio no esta activo.' }
    $checks.installation_and_running_service_with_spaces = 'PASS'
    if ((Get-CimInstance Win32_Service -Filter "Name='Asystec Desk'").StartMode -ne 'Auto') { throw 'Servicio no automatico.' }
    $checks.automatic_startup = 'PASS'
    foreach ($entry in @(@('custom-rendezvous-server',$profile.id_server),@('relay-server',$profile.relay_server),@('key',$profile.public_key),@('api-server',''))) {
        if ((Invoke-DeskCli @('--option',$entry[0])) -cne $entry[1]) { throw "Configuracion incorrecta: $($entry[0])" }
    }
    $checks.compiled_server_key_relay_and_empty_api = 'PASS'
    $id = ''
    for ($i=0;$i -lt 40;$i++) {
        $id = Invoke-DeskCli @('--get-id')
        if ($id -match '^\d{6,}$') { break }
        Start-Sleep -Seconds 1
    }
    if ($id -notmatch '^\d{6,}$') { throw 'No se obtuvo ID valido.' }
    $report.client_id = $id
    $checks.client_id = 'PASS'
    . 'C:\Program Files\Asystec Desk\Connection-Details.ps1'
    $credentialPath = Join-Path $env:ProgramData 'Asystec\Desk\credenciales.dat'
    $record = Read-DeviceCredential $credentialPath (Get-DeviceIdentity)
    if (-not $record.applied -or $record.client_id -cne $id) { throw 'El instalador no dejo las credenciales aplicadas.' }
    $password = $record.password
    if ([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($credentialPath)).Contains($password)) { throw 'Credencial guardada sin cifrar.' }
    $acl = Get-Acl (Split-Path $credentialPath -Parent)
    $sids = @($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]) | ForEach-Object { $_.IdentityReference.Value } | Sort-Object)
    if (-not $acl.AreAccessRulesProtected -or ($sids -join ',') -ne 'S-1-5-18,S-1-5-32-544') { throw 'ACL de credenciales incorrecta.' }
    $checks.installer_created_encrypted_admin_only_credentials = 'PASS'
    foreach ($entry in @(@('verification-method','use-permanent-password'),@('approve-mode','password-click'))) {
        if ((Invoke-DeskCli @('--option',$entry[0])) -cne $entry[1]) { throw 'Modo de autorizacion incorrecto.' }
    }
    $shortcut = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'Asystec Desk\Ver datos de conexion.lnk'
    if (-not (Test-Path -LiteralPath $shortcut)) { throw 'Falta acceso a los datos de conexion.' }
    $checks.connection_details_shortcut = 'PASS'
    $repeat = [Diagnostics.Process]::Start($installInfo)
    if (-not $repeat.WaitForExit(180000) -or $repeat.ExitCode -ne 0) { throw 'La reinstalacion fallo.' }
    $again = Read-DeviceCredential $credentialPath (Get-DeviceIdentity)
    if ($again.password -cne $password -or (Invoke-DeskCli @('--get-id')) -cne $id) { throw 'La reinstalacion cambio las credenciales.' }
    $checks.reinstall_preserves_id_and_password = 'PASS'
    $rsa = New-Object Security.Cryptography.RSACryptoServiceProvider
    $rsa.PersistKeyInCsp = $false
    try {
        $rsa.FromXmlString([IO.File]::ReadAllText('C:\AsystecQAInput\qa-public.xml'))
        $encrypted = [Convert]::ToBase64String($rsa.Encrypt([Text.Encoding]::UTF8.GetBytes($password),$true))
        @{id=$id;password_rsa_oaep=$encrypted} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'qa-credential-encrypted.json') -Encoding UTF8
    } finally { $rsa.Dispose() }
    $password = $null
    $checks.installer_password_exported_encrypted_for_qa = 'PASS'
    Restart-Service -Name 'Asystec Desk'
    (Get-Service -Name 'Asystec Desk').WaitForStatus('Running',[TimeSpan]::FromSeconds(30))
    if ((Invoke-DeskCli @('--get-id')) -cne $id) { throw 'El reinicio cambio el ID.' }
    $checks.service_restart_preserves_id = 'PASS'
    foreach ($port in @(21115,21116,21117)) {
        $tcp = New-Object Net.Sockets.TcpClient
        try {
            $pending = $tcp.BeginConnect($profile.id_server,$port,$null,$null)
            if (-not $pending.AsyncWaitHandle.WaitOne(10000)) { throw "Timeout TCP $port" }
            $tcp.EndConnect($pending)
            $checks["sandbox_to_asystec_tcp_$port"] = 'PASS'
        } finally { $tcp.Dispose() }
    }
    $report.result = 'PASS'
    $report.remote_desktop_session = 'PENDING_SEPARATE_TEST'
    [DateTime]::UtcNow.ToString('o') | Set-Content C:\AsystecQA-complete.txt
    Start-Process -FilePath $script:installed -WindowStyle Hidden
} catch {
    $report.result = 'FAIL'
    $report.error = $_.Exception.Message
} finally {
    Get-ChildItem -LiteralPath $env:TEMP -Filter 'Asystec-Desk-*.log*' -ErrorAction SilentlyContinue |
        Copy-Item -Destination $output -Force -ErrorAction SilentlyContinue
    Save-Report
}
