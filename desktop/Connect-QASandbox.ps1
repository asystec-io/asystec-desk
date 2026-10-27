# Starts only a connection to the disposable QA device created by our runner.
# The QA password is decrypted in memory and never printed or written as text.
#requires -Version 5.1
param([string]$RunName = 'asystec-desk-qa', [string]$BundleDirectory, [switch]$WrongPassword)
$ErrorActionPreference = 'Stop'
if ($RunName -notmatch '^[a-zA-Z0-9_-]+$') { throw 'RunName invalido.' }
$repo = Split-Path $PSScriptRoot -Parent
$credential = Get-Content (Join-Path $repo "dist\$RunName-results\qa-credential-encrypted.json") -Raw | ConvertFrom-Json
if ($credential.id -notmatch '^\d{6,}$') { throw 'ID de prueba invalido.' }
Add-Type -AssemblyName System.Security
$protected = [IO.File]::ReadAllBytes((Join-Path $repo ".build\$RunName-private.dpapi"))
$private = [Security.Cryptography.ProtectedData]::Unprotect($protected,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
$rsa = New-Object Security.Cryptography.RSACryptoServiceProvider
$rsa.PersistKeyInCsp = $false
try {
    $rsa.FromXmlString([Text.Encoding]::UTF8.GetString($private))
    $password = [Text.Encoding]::UTF8.GetString($rsa.Decrypt([Convert]::FromBase64String($credential.password_rsa_oaep),$true))
    if ($WrongPassword) { $password = 'InvalidAsystecDeskQAPassword' }
    if (-not $BundleDirectory) { $BundleDirectory = Join-Path $repo 'dist\asystec-desk-dev' }
    $exe = Join-Path $BundleDirectory 'Asystec Desk.exe'
    Start-Process -FilePath $exe -ArgumentList @('--connect',$credential.id,'--password',$password,'--relay') -WindowStyle Hidden | Out-Null
    Write-Output 'QA connection launched through the Asystec relay; session outcome must be verified separately.'
} finally {
    $password = $null
    [Array]::Clear($private,0,$private.Length)
    $rsa.Dispose()
}
