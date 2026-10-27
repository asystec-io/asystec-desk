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
AppVersion=0.1.3
AppPublisher=Asystec
AppPublisherURL=https://asystec.io
DefaultDirName={autopf}\Asystec Desk
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableWelcomePage=no
Uninstallable=no
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=Asystec-Desk-Setup
SetupIconFile={#DesktopDir}\assets\icon.ico
Compression=lzma2/fast
SolidCompression=yes
WizardStyle=modern
WizardImageFile={#DesktopDir}\assets\wizard.png
WizardSmallImageFile={#DesktopDir}\assets\icon.png
WizardImageBackColor=$451F0F
CloseApplications=no
RestartApplications=no
SetupLogging=yes
VersionInfoDescription=Asystec Desk - Instalador de soporte remoto

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Messages]
spanish.WelcomeLabel1=Bienvenido a Asystec Desk
spanish.WelcomeLabel2=Este asistente instalará Asystec Desk en tu equipo.%n%nSoftware libre basado en RustDesk, bajo licencia AGPL-3.0 y sin garantía.%n%nAl pulsar Siguiente, aceptas los términos de esta licencia.
spanish.FinishedLabel=Asystec Desk está instalado y los datos de conexión están listos.%n%nAl pulsar Finalizar se abrirá la ventana para copiar el ID y la contraseña. También podrás abrirla desde Inicio > Asystec Desk > Ver datos de conexion.
spanish.FinishedLabelNoIcons=Asystec Desk está instalado y los datos de conexión están listos.%n%nAl pulsar Finalizar se abrirá la ventana para copiar el ID y la contraseña. También podrás abrirla desde Inicio > Asystec Desk > Ver datos de conexion.

[Files]
Source: "{#BundleDir}\*"; DestDir: "{tmp}\AsystecDeskPayload"; Excludes: "*.zip"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "{#DesktopDir}\Install-Client.ps1"; DestDir: "{tmp}"; Flags: ignoreversion
Source: "{#DesktopDir}\Connection-Details.ps1"; DestDir: "{tmp}"; Flags: ignoreversion
Source: "{#DesktopDir}\LICENSE.txt"; DestName: "Asystec-Desk-License.txt"; Flags: dontcopy

[Run]
Filename: "{sysnative}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{commonpf64}\Asystec Desk\Connection-Details.ps1"" -ShowCredentials"; Description: "Ver ID y contraseña de este equipo"; Flags: postinstall skipifsilent runhidden runascurrentuser nowait; Check: WasInstalled

[Code]
var
  InstallationFailed: Boolean;
  OperationLog: String;

procedure LicenseLinkClick(Sender: TObject; const Link: String; LinkType: TSysLinkType);
var
  LicenseForm: TSetupForm;
  LicenseText: TNewMemo;
  CloseButton: TNewButton;
begin
  ExtractTemporaryFile('Asystec-Desk-License.txt');
  { Inno Setup 6.7 scales these base dimensions when initializing the form font. }
  LicenseForm := CreateCustomForm(600, 420, True, True);
  try
    LicenseForm.Caption := 'Licencia AGPL-3.0 - Asystec Desk';
    LicenseText := TNewMemo.Create(LicenseForm);
    LicenseText.Parent := LicenseForm;
    LicenseText.Left := ScaleX(12);
    LicenseText.Top := ScaleY(12);
    LicenseText.Width := LicenseForm.ClientWidth - ScaleX(24);
    LicenseText.Height := LicenseForm.ClientHeight - ScaleY(60);
    LicenseText.ReadOnly := True;
    LicenseText.WordWrap := True;
    LicenseText.ScrollBars := ssVertical;
    LicenseText.Lines.LoadFromFile(ExpandConstant('{tmp}\Asystec-Desk-License.txt'));
    CloseButton := TNewButton.Create(LicenseForm);
    CloseButton.Parent := LicenseForm;
    CloseButton.Caption := 'Cerrar';
    CloseButton.Width := ScaleX(90);
    CloseButton.Height := ScaleY(26);
    CloseButton.Left := LicenseForm.ClientWidth - CloseButton.Width - ScaleX(12);
    CloseButton.Top := LicenseForm.ClientHeight - CloseButton.Height - ScaleY(12);
    CloseButton.ModalResult := mrOk;
    CloseButton.Default := True;
    CloseButton.Cancel := True;
    LicenseForm.ActiveControl := CloseButton;
    LicenseForm.FlipAndCenterIfNeeded(True, WizardForm, False);
    LicenseForm.ShowModal();
  finally
    LicenseForm.Free();
  end;
end;

procedure InitializeWizard;
var
  LicenseLink: TNewLinkLabel;
begin
  WizardForm.WelcomeLabel2.Height := ScaleY(155);
  LicenseLink := TNewLinkLabel.Create(WizardForm);
  LicenseLink.Parent := WizardForm.WelcomePage;
  LicenseLink.Left := WizardForm.WelcomeLabel2.Left;
  LicenseLink.Top := WizardForm.WelcomeLabel2.Top + WizardForm.WelcomeLabel2.Height + ScaleY(8);
  LicenseLink.Width := WizardForm.WelcomeLabel2.Width;
  LicenseLink.Height := ScaleY(26);
  LicenseLink.Caption := '<a id="license">Ver licencia AGPL-3.0</a>';
  LicenseLink.OnLinkClick := @LicenseLinkClick;
end;

function GetCustomSetupExitCode: Integer;
begin
  if InstallationFailed then Result := 12 else Result := 0;
end;

function WasInstalled: Boolean;
begin
  Result := not InstallationFailed and FileExists(ExpandConstant('{commonpf64}\Asystec Desk\Connection-Details.ps1'));
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  Arguments: String;
  Detail: String;
  Lines: TArrayOfString;
begin
  if CurStep = ssPostInstall then
  begin
    InstallationFailed := True;
    WizardForm.StatusLabel.Caption := 'Instalando y verificando el servicio de Asystec Desk...';
    OperationLog := GetTempDir + 'Asystec-Desk-' + GetDateTimeString('yyyymmdd-hhnnss', '-', ':') + '-' + IntToStr(Random(1000000)) + '.log';
    Log('Registro de instalacion: ' + OperationLog);
    Arguments := '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\Install-Client.ps1') + '" -PayloadDirectory "' + ExpandConstant('{tmp}\AsystecDeskPayload') + '" -InstallDirectory "' + ExpandConstant('{commonpf64}\Asystec Desk') + '" -LogPath "' + OperationLog + '"';
    if not Exec(ExpandConstant('{sysnative}\WindowsPowerShell\v1.0\powershell.exe'), Arguments, ExpandConstant('{tmp}'), SW_HIDE, ewWaitUntilTerminated, ResultCode) then
      RaiseException('No se pudo iniciar la instalacion de Asystec Desk.');
    if ResultCode <> 0 then
    begin
      Detail := '';
      if LoadStringsFromFile(OperationLog + '.error.txt', Lines) and (GetArrayLength(Lines) > 0) then
        Detail := Copy(Lines[0], 1, 600);
      RaiseException('No se completo la instalacion de Asystec Desk.' + #13#10 + Detail + #13#10 + 'Registro: ' + OperationLog);
    end;
    InstallationFailed := False;
  end;
end;
