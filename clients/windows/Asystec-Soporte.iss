#ifndef PayloadDir
  #error PayloadDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#ifndef PackageVersion
  #define PackageVersion "1.5.0"
#endif
#ifndef InstallerRevision
  #define InstallerRevision "3"
#endif

[Setup]
AppId=Asystec.RustDesk.Bootstrap
AppName=Soporte Asystec
AppVersion={#PackageVersion}.{#InstallerRevision}
AppPublisher=Asystec
VersionInfoDescription=Instalador de RustDesk para soporte Asystec
VersionInfoProductName=Soporte Asystec
VersionInfoVersion={#PackageVersion}.{#InstallerRevision}
OutputDir={#OutputDir}
OutputBaseFilename=Asystec-Soporte-Setup
CreateAppDir=no
Uninstallable=no
PrivilegesRequired=admin
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
DisableWelcomePage=no
DisableDirPage=yes
DisableProgramGroupPage=yes
AllowCancelDuringInstall=no
CloseApplications=no
RestartApplications=no
SetupLogging=yes
SetupMutex=AsystecRustDeskSetup
LicenseFile={#PayloadDir}\LICENSE-RUSTDESK.txt

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Messages]
spanish.WelcomeLabel2=Este asistente instala RustDesk y lo configura para recibir soporte de Asystec.%n%nSe asigna una contraseña permanente distinta para cada equipo. Si repites la instalación, se conserva la contraseña guardada.%n%nGuarda tu trabajo y finaliza cualquier sesión remota de RustDesk antes de continuar.
spanish.FinishedHeadingLabel=RustDesk configurado para Asystec
spanish.FinishedLabel=Se verificaron los ajustes del servidor y la contraseña permanente.%n%nPuedes abrir RustDesk desde el escritorio. Marca la opción inferior para consultar el ID y la contraseña de este equipo.
spanish.FinishedLabelNoIcons=Se verificaron los ajustes del servidor y la contraseña permanente.%n%nPuedes abrir RustDesk desde el escritorio. Marca la opción inferior para consultar el ID y la contraseña de este equipo.

[Files]
Source: "{#PayloadDir}\rustdesk-{#PackageVersion}-x86_64.msi"; Flags: dontcopy
Source: "{#PayloadDir}\Instalar-Asystec.ps1"; Flags: dontcopy
Source: "{#PayloadDir}\LICENSE-RUSTDESK.txt"; Flags: dontcopy
Source: "{#PayloadDir}\LEEME-INSTALADOR.txt"; Flags: dontcopy

[Run]
Filename: "{sysnative}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{tmp}\Instalar-Asystec.ps1"" -ShowCredentials"; Description: "Ver ID y contraseña de este equipo"; Flags: postinstall skipifsilent runhidden runascurrentuser; Check: WasInstalled

[Code]
var
  SetupSucceeded, RestartRequired: Boolean;
  OperationLog: String;

function ValidateOnly: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), '/VALIDATEONLY') = 0 then
      Result := True;
end;

function WasInstalled: Boolean;
begin
  Result := SetupSucceeded and not ValidateOnly;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo,
  MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  Result := 'Se instalará RustDesk {#PackageVersion} y se aplicará la configuración de Asystec.' +
    NewLine + NewLine + 'El servicio iniciará con Windows.' +
    NewLine + 'Para conectarse: contraseña del equipo o aceptación manual.' +
    NewLine + NewLine + 'RustDesk conserva su nombre y sus binarios oficiales. Código fuente y licencia AGPL v3:' +
    NewLine + 'https://github.com/rustdesk/rustdesk/tree/{#PackageVersion}';
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Params, Detail: String;
  ResultCode: Integer;
  Lines: TArrayOfString;
  I: Integer;
begin
  Result := '';
  SetupSucceeded := False;
  RestartRequired := False;
  ExtractTemporaryFile('Instalar-Asystec.ps1');
  ExtractTemporaryFile('rustdesk-{#PackageVersion}-x86_64.msi');
  ExtractTemporaryFile('LICENSE-RUSTDESK.txt');
  ExtractTemporaryFile('LEEME-INSTALADOR.txt');
  OperationLog := GetTempDir + 'Asystec-RustDesk-' +
    GetDateTimeString('yyyymmdd-hhnnss', '-', ':') + '-' + IntToStr(Random(1000000)) + '.log';
  Log('Registro de instalación y configuración: ' + OperationLog);
  WizardForm.PreparingLabel.Caption := 'Instalando RustDesk y verificando la configuración de Asystec. Espera unos minutos...';
  Params := '-NoProfile -STA -ExecutionPolicy Bypass -File "' +
    ExpandConstant('{tmp}\Instalar-Asystec.ps1') + '" -NoCredentialWindow -LogPath "' +
    OperationLog + '"';
  if ValidateOnly then
    Params := Params + ' -ValidateOnly';
  if not Exec(ExpandConstant('{sysnative}\WindowsPowerShell\v1.0\powershell.exe'),
    Params, ExpandConstant('{tmp}'), SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    Result := 'No se pudo iniciar la instalación: ' + SysErrorMessage(ResultCode);
    Exit;
  end;
  if (ResultCode <> 0) and (ResultCode <> 3010) then
  begin
    Detail := '';
    if LoadStringsFromFile(OperationLog, Lines) then
      for I := 0 to GetArrayLength(Lines) - 1 do
        if Pos('ERROR:', Lines[I]) = 1 then
          Detail := Lines[I];
    Result := 'No se completó la instalación y configuración de Asystec.' + #13#10 +
      Detail + #13#10 + 'Registro: ' + OperationLog;
    Exit;
  end;
  RestartRequired := ResultCode = 3010;
  SetupSucceeded := True;
end;

function NeedRestart: Boolean;
begin
  Result := RestartRequired;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpFinished) and ValidateOnly then
  begin
    WizardForm.FinishedHeadingLabel.Caption := 'Paquete verificado';
    WizardForm.FinishedLabel.Caption := 'Se comprobó la integridad del MSI incluido. No se instaló ni se configuró RustDesk.';
  end;
end;
