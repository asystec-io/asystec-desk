#requires -Version 5.1
# Executed only in an isolated WindowsTest VM or disposable Windows Sandbox.
$ErrorActionPreference = 'Stop'
$root = 'C:\CodexDrop\Asystec Setup QA'
$results = Join-Path $root 'results'
New-Item -ItemType Directory -Path $results -Force | Out-Null
. (Join-Path $root 'Instalar-Asystec.ps1')
$checks = [ordered]@{}
$first = $null
$artifact = Join-Path $root 'Asystec-Soporte-Setup.exe'
$expected = [ordered]@{host=$PackageInfo.HostAddress;key=$PackageInfo.Key;api='';relay=$PackageInfo.Relay}
$report = [ordered]@{
    checked_at_utc = [DateTime]::UtcNow.ToString('o')
    computer = $env:COMPUTERNAME
    os = (Get-CimInstance Win32_OperatingSystem).Caption
    exe_sha256 = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
    initially_installed = [bool](Find-RustDeskExecutable)
    checks = $checks
}
function Run-Installer([string]$Name, [string]$Extra = '') {
    $log = Join-Path $results ($Name + '.inno.log')
    $arguments = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /RESTARTEXITCODE=3010 /SP- /LOG="{0}" {1}' -f $log,$Extra
    $process = Start-Process -FilePath $artifact -ArgumentList $arguments -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(240000)) {
        throw "$Name installer did not finish within four minutes; no success is assumed."
    }
    $process.Refresh()
    if ($process.ExitCode -notin @(0,3010)) { throw "$Name installer returned $($process.ExitCode). See $log" }
    return $process.ExitCode
}
try {
    $beforeValidation = [bool](Find-RustDeskExecutable)
    Run-Installer 'validate' '/VALIDATEONLY' | Out-Null
    if ([bool](Find-RustDeskExecutable) -ne $beforeValidation) { throw 'ValidateOnly changed installed state.' }
    $checks.exe_payload_validation_without_installing = 'PASS'
    Run-Installer 'install' | Out-Null
    $exe = Find-RustDeskExecutable
    if (-not $exe) { throw 'RustDesk missing after successful EXE.' }
    if (-not (Test-ServerSettingsMatch (Get-RustDeskServerSettings $exe) $expected)) { throw 'Actual installed server settings differ.' }
    $checks.installed_server_key_relay_and_empty_api = 'PASS'
    $service = Get-CimInstance Win32_Service -Filter "Name='RustDesk'"
    if ($service.State -ne 'Running' -or $service.StartMode -ne 'Auto') { throw 'Service is not running with automatic startup.' }
    $checks.automatic_running_service = 'PASS'
    $installedSignature = Get-AuthenticodeSignature -LiteralPath $exe
    if ($installedSignature.Status -ne 'Valid' -or $installedSignature.SignerCertificate.Subject -notmatch 'O=PURSLANE') {
        throw 'Installed client has no valid official signature.'
    }
    $report.installed_version = (Get-Item -LiteralPath $exe).VersionInfo.ProductVersion
    $checks.official_installed_binary_signature = 'PASS'
    $credentialPath = Join-Path $env:ProgramData 'Asystec\RustDesk\credenciales.dat'
    $first = Read-DeviceCredential $credentialPath (Get-DeviceIdentity)
    if (-not $first.applied -or $first.password.Length -ne 24) { throw 'Credential not applied.' }
    $id = Invoke-RustDeskCli $exe @('--get-id')
    if ($id -notmatch '^\d+$' -or $first.client_id -cne $id) { throw 'Stored ID does not match running client.' }
    $report.client_id = $id
    $acl = Get-Acl -LiteralPath (Split-Path $credentialPath -Parent)
    $rules = @($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
    $sids = @($rules | ForEach-Object {$_.IdentityReference.Value} | Sort-Object)
    if (-not $acl.AreAccessRulesProtected -or ($sids -join ',') -ne 'S-1-5-18,S-1-5-32-544') { throw 'Actual credential ACL differs.' }
    if ([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($credentialPath)).Contains($first.password)) { throw 'Plaintext secret in credential file.' }
    $checks.real_dpapi_credentials_and_administrators_system_acl = 'PASS'
    foreach ($entry in @(@('verification-method','use-permanent-password'),@('approve-mode','password-click'))) {
        if ((Invoke-RustDeskCli $exe @('--option',$entry[0])) -cne $entry[1]) { throw "Wrong authentication mode: $($entry[0])" }
    }
    $checks.permanent_password_and_manual_acceptance_modes = 'PASS'
    Run-Installer 'repeat' | Out-Null
    $second = Read-DeviceCredential $credentialPath (Get-DeviceIdentity)
    if ($first.password -cne $second.password -or $first.client_id -cne $second.client_id) { throw 'Repeat changed credentials.' }
    $checks.repeated_exe_preserves_password_and_id = 'PASS'
    # Exercise the actual bootstrap failure path, then restore the exact DPAPI record.
    $credentialBackup = [IO.File]::ReadAllBytes($credentialPath)
    try {
        [IO.File]::WriteAllBytes($credentialPath, [byte[]]@(1,2,3))
        $failureLog = Join-Path $results 'expected-failure.inno.log'
        $failure = Start-Process -FilePath $artifact -ArgumentList (
            '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /LOG="{0}"' -f $failureLog) -WindowStyle Hidden -PassThru
        if (-not $failure.WaitForExit(120000)) { throw 'Failure test did not finish.' }
        $failure.Refresh()
        if ($failure.ExitCode -eq 0 -or $failure.ExitCode -eq 3010) { throw 'EXE falsely reported success with corrupt credentials.' }
        if (([IO.File]::ReadAllBytes($credentialPath)).Length -ne 3) { throw 'Failure replaced the corrupt credential file.' }
        $checks.exe_propagates_configuration_error_without_false_success = 'PASS'
    } finally { [IO.File]::WriteAllBytes($credentialPath, $credentialBackup) }
    Run-Installer 'recovery' | Out-Null
    if ((Read-DeviceCredential $credentialPath (Get-DeviceIdentity)).password -cne $first.password) { throw 'Recovery changed password.' }
    $checks.recovery_after_failed_configuration = 'PASS'
    Restart-Service -Name RustDesk
    (Get-Service RustDesk).WaitForStatus('Running',[TimeSpan]::FromSeconds(30))
    Start-Sleep -Seconds 5
    if ((Invoke-RustDeskCli $exe @('--get-id')) -cne $id -or
        -not (Test-ServerSettingsMatch (Get-RustDeskServerSettings $exe) $expected)) { throw 'Restart lost ID or server config.' }
    $checks.service_restart_preserves_id_and_configuration = 'PASS'
    foreach ($port in @(21115,21116,21117)) {
        $tcp = New-Object Net.Sockets.TcpClient
        try {
            $pending = $tcp.BeginConnect($expected.host,$port,$null,$null)
            if (-not $pending.AsyncWaitHandle.WaitOne(10000)) { throw "Server port $port timed out." }
            $tcp.EndConnect($pending)
            $checks["vm_to_asystec_tcp_$port"] = 'PASS'
        } finally { $tcp.Dispose() }
    }
    $report.result = 'PASS'
    $report.limitations = @('Interactive wizard, credential window, Windows reboot and remote desktop authentication require separate checks.')
} catch {
    $report.result = 'FAIL'
    $report.error = $_.Exception.Message
    throw
} finally {
    Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Filter 'Asystec-RustDesk-*.log*' -File |
        Copy-Item -Destination $results -Force
    Get-ChildItem -LiteralPath $results -Filter '*.log*' -File | ForEach-Object {
        if ($first -and (Get-Content -LiteralPath $_.FullName -Raw).Contains($first.password)) {
            throw 'A log contains the device password; do not export evidence.'
        }
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $results 'verification.json') -Encoding UTF8
}
