$ErrorActionPreference = 'Stop'
$p = Start-Process -FilePath 'C:\AsystecQAInput\Asystec-Desk-Setup.exe' -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /LOG="C:\AsystecQAResults\negative-setup.log"' -WindowStyle Hidden -PassThru
if (-not $p.WaitForExit(180000)) { throw 'Negative setup timed out.' }
$p.Refresh()
@{exit_code=$p.ExitCode;expected='nonzero';passed=($p.ExitCode -ne 0);at_utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content C:\AsystecQAResults\negative-setup.json -Encoding UTF8
