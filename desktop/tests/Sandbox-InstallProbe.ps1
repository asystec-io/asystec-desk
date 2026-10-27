$ErrorActionPreference = 'Continue'
$out = 'C:\AsystecQAResults'
$exe = 'C:\AsystecQA\bundle\Asystec Desk.exe'
$p = Start-Process -FilePath $exe -ArgumentList '--silent-install' -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput (Join-Path $out 'native-install.stdout.txt') -RedirectStandardError (Join-Path $out 'native-install.stderr.txt')
@{exit=$p.ExitCode;at_utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content (Join-Path $out 'native-install-probe.json') -Encoding UTF8
& C:\AsystecQAInput\Sandbox-Diagnostics.ps1
