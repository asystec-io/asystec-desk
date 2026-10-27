# Run only in Windows Sandbox, with Install-Client.ps1 in C:\AsystecQAInput.
# The fake client reproduces the native command's zero exit code on failure.
$ErrorActionPreference = 'Stop'
$report = [ordered]@{at_utc=[DateTime]::UtcNow.ToString('o');result='RUNNING';checks=[ordered]@{}}
$output = 'C:\AsystecQAResults'
try {
    if ($env:USERNAME -ne 'WDAGUtilityAccount') { throw 'Windows Sandbox required.' }
    $payload = 'C:\AsystecQA\diagnostic-fixture'
    New-Item -ItemType Directory -Path $payload -Force | Out-Null
    Add-Type -TypeDefinition @'
using System;
using System.Reflection;
[assembly: AssemblyProduct("Asystec Desk")]
public class NativeFailure {
    public static int Main() {
        Console.WriteLine("Failed with error: QA simulated native installation failure");
        return 0;
    }
}
'@ -OutputAssembly (Join-Path $payload 'Asystec Desk.exe') -OutputType ConsoleApplication
    $log = Join-Path $output 'native-failure.log'
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File C:\AsystecQAInput\Install-Client.ps1 -PayloadDirectory "{0}" -LogPath "{1}"' -f $payload,$log
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $info.Arguments = $arguments
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $process = [Diagnostics.Process]::Start($info)
    if (-not $process.WaitForExit(30000)) { throw 'Diagnostic test timed out.' }
    if ($process.ExitCode -ne 1) { throw "Expected wrapper exit 1, got $($process.ExitCode)." }
    if ((Get-Content ($log + '.error.txt') -Raw) -notmatch 'QA simulated native installation failure') { throw 'Native error detail was lost.' }
    if ((Get-Content $log -Raw) -notmatch 'Native exit code: 0') { throw 'Native exit code was not logged.' }
    $report.checks.native_failure_with_zero_exit_is_rejected = 'PASS'
    $report.checks.error_detail_and_log_survive_failure = 'PASS'
    $report.result = 'PASS'
} catch {
    $report.result = 'FAIL'
    $report.error = $_.Exception.Message
} finally {
    $report | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $output 'installer-diagnostics.json') -Encoding UTF8
}
