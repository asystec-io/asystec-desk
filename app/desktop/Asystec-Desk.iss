#ifndef BundleDir
  #error BundleDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#ifndef DesktopDir
  #error DesktopDir is required
#endif

[Setup]
AppId=AsystecDeskBootstrap
AppName=Asystec Desk
AppVersion=0.1.0.1
AppPublisher=Asystec
AppPublisherURL=https://asystec.io
DefaultDirName={autopf}\Asystec Desk
DisableDirPage=yes
DisableProgramGroupPage=yes
Uninstallable=no
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=Asystec-Desk-Setup
SetupIconFile={#DesktopDir}\assets\icon.ico
LicenseFile={#DesktopDir}\LICENSE.txt
Compression=lzma2/fast
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
RestartApplications=no
VersionInfoDescription=Asystec Desk - Instalador de soporte remoto

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Files]
Source: "{#BundleDir}\*"; DestDir: "{tmp}\AsystecDeskPayload"; Excludes: "*.zip"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "{#DesktopDir}\Install-Client.ps1"; DestDir: "{tmp}"; Flags: ignoreversion

[Code]
var
  InstallationFailed: Boolean;

function GetCustomSetupExitCode: Integer;
begin
  if InstallationFailed then Result := 12 else Result := 0;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  Arguments: String;
begin
  if CurStep = ssPostInstall then
  begin
    InstallationFailed := True;
    WizardForm.StatusLabel.Caption := 'Instalando y verificando el servicio de Asystec Desk...';
    Arguments := '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\Install-Client.ps1') + '" -PayloadDirectory "' + ExpandConstant('{tmp}\AsystecDeskPayload') + '"';
    if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Arguments, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
      RaiseException('No se pudo iniciar la instalacion de Asystec Desk.');
    if ResultCode <> 0 then
      RaiseException('No se pudo verificar la instalacion de Asystec Desk. Codigo: ' + IntToStr(ResultCode));
    InstallationFailed := False;
  end;
end;
