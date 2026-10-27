#requires -Version 5.1
# Read-only package checks. Never installs or reconfigures the host RustDesk.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'windows\Instalar-Asystec.ps1')
$checks = [ordered]@{}
$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('Asystec-RustDesk-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDirectory | Out-Null

$settings = [ordered]@{host=$PackageInfo.HostAddress;key=$PackageInfo.Key;api='';relay=$PackageInfo.Relay}
$encoded = ConvertTo-RustDeskConfig $settings
$characters = $encoded.ToCharArray()
[Array]::Reverse($characters)
$base64 = (-join $characters).Replace('-', '+').Replace('_', '/')
while ($base64.Length % 4) { $base64 += '=' }
$decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($base64)) | ConvertFrom-Json
foreach ($name in @('host', 'key', 'api', 'relay')) {
    if ($decoded.$name -cne $settings[$name]) { throw "Config encoding changed $name" }
}
$checks.configuration_encoding = 'PASS'

$wrongSettings = [ordered]@{host=$settings.host;key=$settings.key.ToUpperInvariant();api='';relay=$settings.relay}
if (Test-ServerSettingsMatch $wrongSettings $settings) { throw 'Key comparison must be case-sensitive' }
$wrongSettings = [ordered]@{host=$settings.host;key=$settings.key;api='https://unexpected.example';relay=$settings.relay}
if (Test-ServerSettingsMatch $wrongSettings $settings) { throw 'Unexpected API endpoint must be rejected' }
$wrongSettings = [ordered]@{host='';key='';api='';relay=''}
if (Test-ServerSettingsMatch $wrongSettings $settings) { throw 'Silently unapplied configuration must be rejected' }
$checks.reject_wrong_readback = 'PASS'

# Compile a harmless fixture to verify native argument quoting and output capture,
# including spaces, quotes, ampersands, an empty argument and a trailing slash.
$fixtureSource = @'
using System;
using System.Text;
public class ArgumentEcho {
    public static void Main(string[] args) {
        if (args.Length == 2 && args[0] == "--password") {
            if (args[1].StartsWith("reject-")) {
                Console.WriteLine("Settings are disabled! " + args[1]);
            } else if (!args[1].StartsWith("silent-")) {
                Console.WriteLine("Done!");
            }
            return;
        }
        if (args.Length >= 2 && args[0] == "--option") {
            if (args.Length == 2) {
                if (args[1] == "verification-method") Console.WriteLine("use-permanent-password");
                if (args[1] == "approve-mode") Console.WriteLine("password-click");
            }
            return;
        }
        foreach (string arg in args)
            Console.WriteLine("ARG:" + Convert.ToBase64String(Encoding.UTF8.GetBytes(arg)));
    }
}
'@
$fixturePath = Join-Path $testDirectory 'argument echo.exe'
Add-Type -TypeDefinition $fixtureSource -Language CSharp -OutputAssembly $fixturePath -OutputType ConsoleApplication
$arguments = @('C:\Client folder\O''Brien & more\', 'embedded"quote', '', '--config', $encoded)
$actualOutput = Invoke-RustDeskCli $fixturePath $arguments
$expectedOutput = ($arguments | ForEach-Object { 'ARG:' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($_)) }) -join [Environment]::NewLine
if ($actualOutput -cne $expectedOutput) { throw 'Native process arguments or capture were changed' }
$checks.native_arguments_and_capture = 'PASS'

# Test secrets only inside an isolated temporary directory. No host RustDesk writes.
$credentialPath = Join-Path $testDirectory 'test-credentials.dat'
$record = Get-OrCreateDeviceCredential $credentialPath 'test-device-a' '123456789'
$firstPassword = $record.password
if ($firstPassword -cnotmatch '^[A-Za-z0-9_-]{24}$' -or $record.applied) { throw 'Invalid initial credential' }
$again = Get-OrCreateDeviceCredential $credentialPath 'test-device-a' '987654321'
if ($again.password -cne $firstPassword) { throw 'Rerun rotated the saved password' }
$record.applied = $true
Write-DeviceCredential $credentialPath $record
$again = Read-DeviceCredential $credentialPath 'test-device-a'
if (-not $again.applied -or $again.password -cne $firstPassword) { throw 'Encrypted credential update failed' }
$raw = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($credentialPath))
if ($raw.Contains($firstPassword) -or $raw.Contains('test-device-a')) { throw 'Credential leaked in plaintext' }
$different = Get-OrCreateDeviceCredential (Join-Path $testDirectory 'second-credentials.dat') 'test-device-b' '555555555'
if ($different.password -ceq $firstPassword) { throw 'Two independent devices received the same password' }
$checks.encrypted_storage_and_stable_password_per_device = 'PASS'

$rejected = $false
try { Read-DeviceCredential $credentialPath 'test-device-b' | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Cross-device credential was accepted' }
$corruptPath = Join-Path $testDirectory 'corrupt-credentials.dat'
[IO.File]::WriteAllBytes($corruptPath, [byte[]]@(1, 2, 3))
$rejected = $false
try { Get-OrCreateDeviceCredential $corruptPath 'test-device-a' '123456789' | Out-Null } catch { $rejected = $true }
if (-not $rejected -or ([IO.File]::ReadAllBytes($corruptPath)).Length -ne 3) {
    throw 'Corrupt credentials must fail without generating a replacement'
}
$acl = New-CredentialDirectoryAcl
$rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
$allowedSids = @($rules | ForEach-Object { $_.IdentityReference.Value } | Sort-Object)
if (-not $acl.AreAccessRulesProtected -or $rules.Count -ne 2 -or
    ($allowedSids -join ',') -cne 'S-1-5-18,S-1-5-32-544') { throw 'Credential ACL permits unexpected principals' }
$checks.reject_foreign_or_corrupt_credentials_and_private_acl_definition = 'PASS'

Set-DevicePermanentPassword $fixturePath $firstPassword
foreach ($secret in @('reject-private-sentinel', 'silent-private-sentinel')) {
    $rejected = $false
    try { Set-DevicePermanentPassword $fixturePath $secret } catch {
        $rejected = $true
        if ($_.Exception.Message.Contains($secret)) { throw 'Password leaked in error diagnostics' }
    }
    if (-not $rejected) { throw 'Missing password acknowledgement was accepted' }
}
$checks.password_acknowledgement_modes_and_error_redaction_with_fixture = 'PASS'

$tamperedPath = Join-Path $testDirectory 'tampered.msi'
Set-Content -LiteralPath $tamperedPath -Value 'tampered fixture' -Encoding ASCII
$rejected = $false
try { Assert-OfficialPackage $tamperedPath $PackageInfo.MsiSha256 } catch { $rejected = $true }
if (-not $rejected) { throw 'Tampered package was accepted' }
$checks.reject_tampered_package = 'PASS'

$outputDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) 'dist'
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach ($name in @('Asystec-RustDesk-Instalador', 'Asystec-RustDesk-Portable')) {
    $zip = Join-Path $outputDirectory ($name + '.zip')
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $testDirectory)
}
$extractedInstaller = Join-Path $testDirectory 'Asystec-RustDesk-Instalador'
$extractedPortable = Join-Path $testDirectory 'Asystec-RustDesk-Portable'
foreach ($name in @('Instalar-Asystec.ps1', 'INSTALAR-ASYSTEC.cmd', 'VER-CREDENCIALES.cmd')) {
    $sourceHash = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot "windows\$name")).Hash
    $packageHash = (Get-FileHash -LiteralPath (Join-Path $extractedInstaller $name)).Hash
    if ($sourceHash -ne $packageHash) { throw "Packaged file differs from source: $name" }
}
$checks.packaged_scripts_match_current_revision = 'PASS'
$msiPath = Join-Path $extractedInstaller $PackageInfo.MsiName
Assert-OfficialPackage $msiPath $PackageInfo.MsiSha256
$portable = @(Get-ChildItem -LiteralPath $extractedPortable -Filter '*.exe')
if ($portable.Count -ne 1) { throw 'Expected a single portable executable' }
Assert-OfficialPackage $portable[0].FullName $PackageInfo.ExeSha256
if ($portable[0].Name -cne ('RustDesk-Asystec-host={0},key={1},.exe' -f $settings.host, $settings.key)) {
    throw 'Portable filename does not encode the expected server and key'
}
$checks.extracted_official_binaries_and_portable_name = 'PASS'

$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
& $ps51 -NoProfile -ExecutionPolicy Bypass -File (Join-Path $extractedInstaller 'Instalar-Asystec.ps1') -ValidateOnly
if ($LASTEXITCODE -ne 0) { throw 'Packaged installer validation failed on Windows PowerShell 5.1' }
$checks.packaged_validate_only_powershell51 = 'PASS'

$installed = Find-RustDeskExecutable
if ($installed) {
    $version = Invoke-RustDeskCli $installed @('--version')
    if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Official RustDesk CLI output was not captured' }
    $checks.official_client_cli_capture = 'PASS'
}
$report = [ordered]@{
    checked_at_utc = [DateTime]::UtcNow.ToString('o')
    checks = $checks
    limitations = @(
        'This test suite does not install RustDesk or open a remote desktop. See sandbox-test/verification.json and exe-test-report.md for the separate installation and remote-session evidence.',
        'Password application and option checks were exercised with a CLI fixture. Host RustDesk credentials were not changed.',
        'DPAPI round trips and the ACL definition were tested; applying the production administrator-only ACL requires elevation.',
        'No portable desktop session was launched; existing local RustDesk settings were preserved.'
    )
}
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $outputDirectory 'verification.json') -Encoding UTF8
$report | ConvertTo-Json -Depth 5
