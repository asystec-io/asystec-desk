#requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Connection-Details.ps1')
$testDirectory=Join-Path ([IO.Path]::GetTempPath()) ('Asystec-Details-Test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDirectory | Out-Null
$checks=[ordered]@{}
$path=Join-Path $testDirectory 'credential.dat'
$first=Get-OrCreateDeviceCredential $path 'qa-device-a' '123456789'
$again=Get-OrCreateDeviceCredential $path 'qa-device-a' '123456789'
$other=Get-OrCreateDeviceCredential (Join-Path $testDirectory 'other.dat') 'qa-device-b' '987654321'
if ($first.password -cne $again.password -or $first.password -ceq $other.password) { throw 'Password persistence/uniqueness failed' }
if ([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($path)).Contains($first.password)) { throw 'Plaintext credential on disk' }
$first.applied=$true
Write-DeviceCredential $path $first
if (-not (Read-DeviceCredential $path 'qa-device-a').applied) { throw 'Applied state lost' }
$checks.encrypted_unique_and_persistent_credentials='PASS'
$rejected=$false
try { Read-DeviceCredential $path 'qa-device-b' | Out-Null } catch { $rejected=$true }
if (-not $rejected) { throw 'Foreign credential accepted' }
$corrupt=Join-Path $testDirectory 'corrupt.dat'
[IO.File]::WriteAllBytes($corrupt,[byte[]]@(1,2,3))
$rejected=$false
try { Get-OrCreateDeviceCredential $corrupt 'qa-device-a' '123456789' | Out-Null } catch { $rejected=$true }
if (-not $rejected -or (Get-Item $corrupt).Length -ne 3) { throw 'Corrupt record replaced' }
$checks.corrupt_or_foreign_credentials_are_rejected='PASS'
$source=@'
using System;
public class CredentialCli {
 public static void Main(string[] args) {
  if (args[0]=="--password") {
   Console.WriteLine(args[1].StartsWith("reject-") ? "Rejected: "+args[1] : "Done!");
  } else if (args[0]=="--option" && args.Length==2) {
   Console.WriteLine(args[1]=="verification-method" ? "use-permanent-password" : "password-click");
  }
 }
}
'@
$fixture=Join-Path $testDirectory 'fake client.exe'
Add-Type -TypeDefinition $source -OutputAssembly $fixture -OutputType ConsoleApplication
Set-DevicePermanentPassword $fixture $first.password
$sentinel='reject-private-test-sentinel'
$rejected=$false
try { Set-DevicePermanentPassword $fixture $sentinel } catch {
 $rejected=$true
 if ($_.Exception.Message.Contains($sentinel)) { throw 'Password leaked in diagnostics' }
}
if (-not $rejected) { throw 'Missing acknowledgement accepted' }
$checks.password_acknowledgement_and_error_redaction='PASS'
$report=[ordered]@{at_utc=[DateTime]::UtcNow.ToString('o');result='PASS';checks=$checks}
$report | ConvertTo-Json -Depth 5 | Set-Content (Join-Path (Split-Path $PSScriptRoot -Parent) '.build\connection-details-unit.json') -Encoding UTF8
$report | ConvertTo-Json -Depth 5
