$ErrorActionPreference = 'Continue'
$out = 'C:\AsystecQAResults'
$report = [ordered]@{
    at_utc = [DateTime]::UtcNow.ToString('o')
    is_admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    services = @(Get-CimInstance Win32_Service | Where-Object Name -like '*Asystec*' | Select-Object Name,State,StartMode,PathName,ExitCode)
    installed_files = @(Get-ChildItem 'C:\Program Files\Asystec Desk' -ErrorAction SilentlyContinue | Select-Object Name,Length)
    processes = @(Get-Process 'Asystec Desk','Asystec-Desk-Setup','powershell' -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,Path)
    temp_files = @(Get-ChildItem $env:TEMP -File -ErrorAction SilentlyContinue | Where-Object Name -match 'Asystec|RustDesk|setup' | Select-Object Name,Length)
    system_events = @(Get-WinEvent -FilterHashtable @{LogName='System';StartTime=(Get-Date).AddMinutes(-10)} -ErrorAction SilentlyContinue | Where-Object {$_.ProviderName -eq 'Service Control Manager' -and $_.Message -match 'Asystec'} | Select-Object TimeCreated,Id,Message)
}
$report | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $out 'diagnostics.json') -Encoding UTF8
Get-ChildItem "$env:APPDATA\Asystec Desk\log" -Recurse -File -ErrorAction SilentlyContinue | Copy-Item -Destination $out -Force
