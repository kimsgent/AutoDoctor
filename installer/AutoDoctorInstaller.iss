#define MyAppId "{{D6F0C8E0-5A63-4E89-BF15-B464C8F7A4AD}"
#define MyAppName "AutoDoctor"
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#define MyAppPublisher "Project Indexly"
#define MyAppURL "https://projectindexly.com"
#define MyServiceName "AutoDoctorAPI"
#define MyServiceDisplayName "AutoDoctor Telemetry API"
#define MyServiceDescription "AutoDoctor monitoring API service"
#define MyAPIHost "127.0.0.1"
#define MyAPIPort "8000"
#define PythonWindowsDownloadsURL "https://www.python.org/downloads/windows/"
#define SourceRoot ".."
#define BuildRoot "..\build\dist"
#define DashboardURL "http://127.0.0.1:" + MyAPIPort + "/dashboard/"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={commonappdata}\AutoDoctor
DisableDirPage=yes
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=output
OutputBaseFilename=AutoDoctor_Installer_{#MyAppVersion}
Compression=lzma
SolidCompression=yes
; Use x64compatible so the 64-bit installer can also target platforms such as
; Windows on ARM that support x64 application compatibility.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
ChangesEnvironment=yes
WizardStyle=modern
SetupIconFile={#SourceRoot}\server\dashboard\favicon.ico
UninstallDisplayIcon={app}\server\dashboard\favicon.ico
LicenseFile={#SourceRoot}\LICENSE.txt

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicons"; Description: "Create desktop shortcuts"; Flags: unchecked
Name: "seedbootstrap"; Description: "Create initial schema and first telemetry snapshot"; Flags: checkedonce
Name: "servicebundled"; Description: "Use bundled service runtime (recommended)"; GroupDescription: "API service installation mode:"; Flags: exclusive checkedonce
Name: "servicepython"; Description: "Use system Python interpreter (advanced)"; GroupDescription: "API service installation mode:"; Flags: exclusive

[Dirs]
Name: "{app}\agent"
Name: "{app}\config"
Name: "{app}\db"
Name: "{app}\diagnostics"
Name: "{app}\logs"
Name: "{app}\reports"
Name: "{app}\server"
Name: "{app}\server\api"
Name: "{app}\server\dashboard"
Name: "{app}\telemetry"

[Files]
Source: "{#BuildRoot}\autodoctor_service\*"; DestDir: "{app}\server\api"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#BuildRoot}\autodoctor_api.exe"; DestDir: "{app}\server\api"; Flags: ignoreversion
Source: "{#SourceRoot}\agent\*"; DestDir: "{app}\agent"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceRoot}\server\api\*.py"; DestDir: "{app}\server\api"; Flags: ignoreversion
Source: "{#SourceRoot}\server\dashboard\*"; DestDir: "{app}\server\dashboard"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceRoot}\VERSION"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\config\config.ps1.template"; DestDir: "{app}\config"; Flags: ignoreversion
Source: "{#SourceRoot}\reports\logo.png"; DestDir: "{app}\reports"; Flags: ignoreversion

[INI]
Filename: "{app}\config\autodoctor.ini"; Section: "Server"; Key: "host"; String: "{#MyAPIHost}"
Filename: "{app}\config\autodoctor.ini"; Section: "Server"; Key: "port"; String: "{#MyAPIPort}"
Filename: "{app}\config\autodoctor.ini"; Section: "Paths"; Key: "root"; String: "{app}"
Filename: "{app}\config\autodoctor.ini"; Section: "Paths"; Key: "config"; String: "{app}\config"
Filename: "{app}\config\autodoctor.ini"; Section: "Paths"; Key: "db"; String: "{app}\db"
Filename: "{app}\config\autodoctor.ini"; Section: "Paths"; Key: "reports"; String: "{app}\reports"
Filename: "{app}\config\autodoctor.ini"; Section: "Paths"; Key: "telemetry"; String: "{app}\telemetry"
Filename: "{app}\config\autodoctor.ini"; Section: "Paths"; Key: "diagnostics"; String: "{app}\diagnostics"
Filename: "{app}\config\autodoctor.ini"; Section: "Paths"; Key: "logs"; String: "{app}\logs"
Filename: "{app}\config\autodoctor.ini"; Section: "Paths"; Key: "server"; String: "{app}\server"
Filename: "{app}\config\autodoctor.ini"; Section: "Paths"; Key: "api"; String: "{app}\server\api"
Filename: "{app}\config\autodoctor.ini"; Section: "Paths"; Key: "dashboard"; String: "{app}\server\dashboard"
Filename: "{app}\config\autodoctor.ini"; Section: "Files"; Key: "database"; String: "{app}\db\autodoctor.db"
Filename: "{app}\config\autodoctor.ini"; Section: "Files"; Key: "report_html"; String: "{app}\reports\AutoDoctor_Report.html"
Filename: "{app}\config\autodoctor.ini"; Section: "Files"; Key: "report_json"; String: "{app}\reports\AutoDoctor_Report.json"
Filename: "{app}\config\autodoctor.ini"; Section: "Files"; Key: "log_file"; String: "{app}\logs\autodoctor.log"
Filename: "{app}\config\autodoctor.ini"; Section: "Files"; Key: "meta_json"; String: "{app}\server\latest_run.json"
Filename: "{app}\config\autodoctor.ini"; Section: "Files"; Key: "api_entrypoint"; String: "{app}\server\api\autodoctor_api.exe"
Filename: "{app}\config\autodoctor.ini"; Section: "Files"; Key: "service_wrapper"; String: "{app}\server\api\autodoctor_service.exe"
Filename: "{app}\config\autodoctor.ini"; Section: "Files"; Key: "dashboard_index"; String: "{app}\server\dashboard\index.html"
Filename: "{app}\config\autodoctor.ini"; Section: "Service"; Key: "name"; String: "{#MyServiceName}"
Filename: "{app}\config\autodoctor.ini"; Section: "Service"; Key: "display_name"; String: "{#MyServiceDisplayName}"
Filename: "{app}\config\autodoctor.ini"; Section: "Service"; Key: "description"; String: "{#MyServiceDescription}"
Filename: "{app}\config\autodoctor.ini"; Section: "Service"; Key: "mode"; String: "bundled"

[Registry]
Root: HKLM64; Subkey: "Software\AutoDoctor"; ValueType: string; ValueName: "APIHost"; ValueData: "{#MyAPIHost}"; Flags: uninsdeletevalue
Root: HKLM64; Subkey: "Software\AutoDoctor"; ValueType: string; ValueName: "APIPort"; ValueData: "{#MyAPIPort}"; Flags: uninsdeletevalue
Root: HKLM64; Subkey: "Software\AutoDoctor"; ValueType: string; ValueName: "Version"; ValueData: "{#MyAppVersion}"; Flags: uninsdeletevalue
Root: HKLM64; Subkey: "Software\AutoDoctor"; ValueType: string; ValueName: "InstallPath"; ValueData: "{app}"; Flags: uninsdeletevalue
Root: HKLM64; Subkey: "Software\AutoDoctor"; ValueType: string; ValueName: "InstallRoot"; ValueData: "{app}"; Flags: uninsdeletevalue

[Icons]
Name: "{group}\Run AutoDoctor Scan"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""{app}\agent\AutoDoctor.ps1"""; WorkingDir: "{app}\agent"; IconFilename: "{app}\server\dashboard\favicon.ico"
Name: "{group}\Initialize AutoDoctor"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""{app}\agent\Initialize-AutoDoctor.ps1"""; WorkingDir: "{app}\agent"; IconFilename: "{app}\server\dashboard\favicon.ico"
Name: "{group}\Open AutoDoctor Dashboard"; Filename: "{cmd}"; Parameters: "/c start """" ""{#DashboardURL}"""; WorkingDir: "{app}"; IconFilename: "{app}\server\dashboard\favicon.ico"
Name: "{commondesktop}\Run AutoDoctor Scan"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""{app}\agent\AutoDoctor.ps1"""; WorkingDir: "{app}\agent"; IconFilename: "{app}\server\dashboard\favicon.ico"; Tasks: desktopicons
Name: "{commondesktop}\Open AutoDoctor Dashboard"; Filename: "{cmd}"; Parameters: "/c start """" ""{#DashboardURL}"""; WorkingDir: "{app}"; IconFilename: "{app}\server\dashboard\favicon.ico"; Tasks: desktopicons

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""{app}\agent\Initialize-AutoDoctor.ps1"""; Flags: runhidden waituntilterminated; Tasks: seedbootstrap; StatusMsg: "Initializing AutoDoctor schema and first telemetry snapshot..."
Filename: "{app}\server\api\autodoctor_service.exe"; Parameters: "--startup auto update"; Flags: runhidden waituntilterminated; Check: WizardIsTaskSelected('servicebundled') and ServiceExists('{#MyServiceName}'); StatusMsg: "Updating AutoDoctor API service..."
Filename: "{app}\server\api\autodoctor_service.exe"; Parameters: "--startup auto install"; Flags: runhidden waituntilterminated; Check: WizardIsTaskSelected('servicebundled') and (not ServiceExists('{#MyServiceName}')); StatusMsg: "Registering AutoDoctor API service..."
Filename: "{app}\server\api\autodoctor_service.exe"; Parameters: "start"; Flags: runhidden waituntilterminated; Check: WizardIsTaskSelected('servicebundled'); StatusMsg: "Starting AutoDoctor API service..."
Filename: "{cmd}"; Parameters: "/c start """" ""{#DashboardURL}"""; Flags: postinstall skipifsilent unchecked; Description: "Open AutoDoctor Dashboard"

[Code]
var
  SystemPythonCommand: string;
  ExistingInstallDetected: Boolean;
  ExistingInstallVersion: string;
  ExistingInstallPath: string;
  UpdateCacheLatestVersion: string;
  UpdateCacheAvailable: Boolean;
  UpgradeOptionVisible: Boolean;
  UpgradeOptionIndex: Integer;
  RepairOptionIndex: Integer;
  RemoveOptionIndex: Integer;
  InstallModePage: TInputOptionWizardPage;
  DisclaimerPage: TWizardPage;

const
  INSTALL_ACTION_UPGRADE = 0;
  INSTALL_ACTION_REPAIR = 1;
  INSTALL_ACTION_REMOVE = 2;

function ServiceExists(const ServiceName: string): Boolean;
begin
  Result := RegKeyExists(HKLM64, 'SYSTEM\CurrentControlSet\Services\' + ServiceName);
end;

function GetRegistryInstallPath(var InstallPath: string): Boolean;
begin
  Result :=
    RegQueryStringValue(HKLM64, 'Software\AutoDoctor', 'InstallPath', InstallPath) or
    RegQueryStringValue(HKLM64, 'Software\AutoDoctor', 'InstallRoot', InstallPath);
end;

function IsValidInstalledLayout(const InstallPath: string): Boolean;
var
  BasePath: string;
begin
  if InstallPath = '' then
  begin
    Result := False;
    exit;
  end;

  BasePath := AddBackslash(InstallPath);

  Result :=
    DirExists(InstallPath) and
    FileExists(BasePath + 'agent\AutoDoctor.ps1') and
    FileExists(BasePath + 'VERSION') and
    FileExists(BasePath + 'unins000.exe');
end;

function GetUpdateCachePath(): string;
begin
  if ExistingInstallPath <> '' then
  begin
    Result := AddBackslash(ExistingInstallPath) + 'cache\update_check.json';
  end
  else
  begin
    Result := ExpandConstant('{commonappdata}\AutoDoctor\cache\update_check.json');
  end;
end;

function ExtractJsonStringValueFromLine(const Line: string; const KeyName: string; var ParsedValue: string): Boolean;
var
  TrimmedLine: string;
  LowerLine: string;
  KeyToken: string;
  ColonPos: Integer;
  QuotePos: Integer;
begin
  Result := False;
  ParsedValue := '';

  TrimmedLine := Trim(Line);
  LowerLine := LowerCase(TrimmedLine);
  KeyToken := '"' + LowerCase(KeyName) + '"';

  if Pos(KeyToken, LowerLine) = 0 then
  begin
    exit;
  end;

  ColonPos := Pos(':', TrimmedLine);
  if ColonPos <= 0 then
  begin
    exit;
  end;

  TrimmedLine := Trim(Copy(TrimmedLine, ColonPos + 1, MaxInt));
  if (Length(TrimmedLine) = 0) or (TrimmedLine[1] <> '"') then
  begin
    exit;
  end;

  Delete(TrimmedLine, 1, 1);
  QuotePos := Pos('"', TrimmedLine);
  if QuotePos <= 0 then
  begin
    exit;
  end;

  ParsedValue := Copy(TrimmedLine, 1, QuotePos - 1);
  Result := True;
end;

procedure ReadUpdateCacheInfo();
var
  CachePath: string;
  CacheLines: TArrayOfString;
  I: Integer;
  Line: string;
  ParsedVersion: string;
begin
  UpdateCacheAvailable := False;
  UpdateCacheLatestVersion := '';

  CachePath := GetUpdateCachePath();
  if not FileExists(CachePath) then
  begin
    exit;
  end;

  if not LoadStringsFromFile(CachePath, CacheLines) then
  begin
    exit;
  end;

  for I := 0 to GetArrayLength(CacheLines) - 1 do
  begin
    Line := Trim(CacheLines[I]);

    if Pos('"update_available"', LowerCase(Line)) > 0 then
    begin
      UpdateCacheAvailable := Pos('true', LowerCase(Line)) > 0;
    end;

    if ExtractJsonStringValueFromLine(Line, 'latest_version', ParsedVersion) then
    begin
      UpdateCacheLatestVersion := ParsedVersion;
    end;
  end;

  if not UpdateCacheAvailable then
  begin
    UpdateCacheLatestVersion := '';
  end;
end;

procedure DetectExistingInstall();
begin
  ExistingInstallDetected := False;
  ExistingInstallVersion := '';
  ExistingInstallPath := '';

  if RegKeyExists(HKLM64, 'Software\AutoDoctor') then
  begin
    RegQueryStringValue(HKLM64, 'Software\AutoDoctor', 'Version', ExistingInstallVersion);
    GetRegistryInstallPath(ExistingInstallPath);

    ExistingInstallDetected := IsValidInstalledLayout(ExistingInstallPath);
  end;

  if ExistingInstallPath = '' then
  begin
    ExistingInstallPath := ExpandConstant('{commonappdata}\AutoDoctor');
  end;
end;

function ResolveSystemPythonCommand(var PythonCommand: string): Boolean;
var
  ResultCode: Integer;
  Candidate: string;
begin
  Result := False;
  PythonCommand := '';

  Candidate := GetEnv('AUTO_DOCTOR_SYSTEM_PYTHON');
  if Candidate <> '' then
  begin
    if FileExists(Candidate) then
    begin
      PythonCommand := '"' + Candidate + '"';
      Result := True;
      exit;
    end;
  end;

  if Exec(ExpandConstant('{cmd}'), '/c py -3 --version', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0) then
  begin
    PythonCommand := 'py -3';
    Result := True;
    exit;
  end;

  if Exec(ExpandConstant('{cmd}'), '/c python --version', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0) then
  begin
    PythonCommand := 'python';
    Result := True;
    exit;
  end;
end;

function ValidateSystemPythonForService(var PythonCommand: string): Boolean;
var
  ResultCode: Integer;
  ImportCheck: string;
  Msg: string;
begin
  Result := False;

  if not ResolveSystemPythonCommand(PythonCommand) then
  begin
    Msg :=
      'System Python was selected for service installation, but no compatible Python runtime was found.'#13#10#13#10 +
      'Install Python 3.12.x for Windows, then rerun setup.'#13#10 +
      '{#PythonWindowsDownloadsURL}';
    MsgBox(Msg, mbError, MB_OK);
    exit;
  end;

  ImportCheck := '/c ' + PythonCommand + ' -c "import win32serviceutil,win32service,win32event,servicemanager,fastapi,uvicorn"';

  if not (Exec(ExpandConstant('{cmd}'), ImportCheck, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0)) then
  begin
    Msg :=
      'System Python was found, but required packages are missing.'#13#10#13#10 +
      'Open an elevated terminal and run:'#13#10 +
      PythonCommand + ' -m pip install pywin32 fastapi uvicorn'#13#10#13#10 +
      'After that, rerun setup.';
    MsgBox(Msg, mbError, MB_OK);
    exit;
  end;

  Result := True;
end;

function RunSystemPythonServiceCommand(const PythonCommand: string; const ServiceArgs: string; const StatusLabel: string): Boolean;
var
  ResultCode: Integer;
  CommandLine: string;
begin
  CommandLine :=
    PythonCommand + ' "' + ExpandConstant('{app}\server\api\autodoctor_service.py') + '" ' + ServiceArgs;

  Log(StatusLabel + ': ' + CommandLine);
  Result := Exec(ExpandConstant('{cmd}'), '/c ' + CommandLine, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
end;

procedure ConfigureServiceModeIni();
begin
  if WizardIsTaskSelected('servicepython') then
  begin
    SetIniString('Service', 'mode', 'system_python', ExpandConstant('{app}\config\autodoctor.ini'));
  end
  else
  begin
    SetIniString('Service', 'mode', 'bundled', ExpandConstant('{app}\config\autodoctor.ini'));
  end;
end;

procedure InstallServiceUsingSystemPython();
var
  ResultCode: Integer;
  Msg: string;
begin
  if not ValidateSystemPythonForService(SystemPythonCommand) then
  begin
    exit;
  end;

  if ServiceExists('{#MyServiceName}') then
  begin
    Exec(ExpandConstant('{sys}\sc.exe'), 'stop {#MyServiceName}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Sleep(1500);
  end;

  if ServiceExists('{#MyServiceName}') then
  begin
    if not RunSystemPythonServiceCommand(SystemPythonCommand, '--startup auto update', 'Updating service via system Python') then
    begin
      Msg := 'Failed to update AutoDoctorAPI service with system Python.'#13#10 +
             'Run this manually in an elevated terminal:'#13#10 +
             SystemPythonCommand + ' "' + ExpandConstant('{app}\server\api\autodoctor_service.py') + '" --startup auto update';
      MsgBox(Msg, mbError, MB_OK);
      exit;
    end;
  end
  else
  begin
    if not RunSystemPythonServiceCommand(SystemPythonCommand, '--startup auto install', 'Installing service via system Python') then
    begin
      Msg := 'Failed to install AutoDoctorAPI service with system Python.'#13#10 +
             'Run this manually in an elevated terminal:'#13#10 +
             SystemPythonCommand + ' "' + ExpandConstant('{app}\server\api\autodoctor_service.py') + '" --startup auto install';
      MsgBox(Msg, mbError, MB_OK);
      exit;
    end;
  end;

  if not RunSystemPythonServiceCommand(SystemPythonCommand, 'start', 'Starting service via system Python') then
  begin
    Msg := 'Service registration succeeded, but startup failed.'#13#10 +
           'Check Windows Event Viewer and AutoDoctor logs in:'#13#10 +
           ExpandConstant('{app}\logs');
    MsgBox(Msg, mbError, MB_OK);
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Result := '';

  if ServiceExists('{#MyServiceName}') then
  begin
    Exec(
      ExpandConstant('{sys}\sc.exe'),
      'stop {#MyServiceName}',
      '',
      SW_HIDE,
      ewWaitUntilTerminated,
      ResultCode
    );
    Sleep(2000);
  end;
end;

procedure StopAndRemoveService();
var
  ResultCode: Integer;
  ServiceExe: string;
begin
  ServiceExe := ExpandConstant('{app}\server\api\autodoctor_service.exe');

  if ServiceExists('{#MyServiceName}') then
  begin
    Exec(
      ExpandConstant('{sys}\sc.exe'),
      'stop {#MyServiceName}',
      '',
      SW_HIDE,
      ewWaitUntilTerminated,
      ResultCode
    );

    if FileExists(ServiceExe) then
    begin
      Exec(
        ServiceExe,
        'remove',
        '',
        SW_HIDE,
        ewWaitUntilTerminated,
        ResultCode
      );
    end;

    if ServiceExists('{#MyServiceName}') then
    begin
      Exec(
        ExpandConstant('{sys}\sc.exe'),
        'delete {#MyServiceName}',
        '',
        SW_HIDE,
        ewWaitUntilTerminated,
        ResultCode
      );
    end;
  end;
end;

function GetSelectedInstallAction(): Integer;
begin
  Result := INSTALL_ACTION_REPAIR;

  if InstallModePage = nil then
  begin
    exit;
  end;

  if (RemoveOptionIndex >= 0) and InstallModePage.Values[RemoveOptionIndex] then
  begin
    Result := INSTALL_ACTION_REMOVE;
    exit;
  end;

  if UpgradeOptionVisible and (UpgradeOptionIndex >= 0) and InstallModePage.Values[UpgradeOptionIndex] then
  begin
    Result := INSTALL_ACTION_UPGRADE;
    exit;
  end;
end;

function RunExistingUninstaller(): Boolean;
var
  UninstallerExe: string;
  UninstallArgs: string;
  ResultCode: Integer;
begin
  Result := False;

  UninstallerExe := AddBackslash(ExistingInstallPath) + 'unins000.exe';
  if not FileExists(UninstallerExe) then
  begin
    exit;
  end;

  if WizardSilent then
  begin
    UninstallArgs := '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART';
  end
  else
  begin
    UninstallArgs := '/SILENT /NORESTART';
  end;

  Result := Exec(UninstallerExe, UninstallArgs, '', SW_SHOW, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
end;

procedure InitializeWizard();
var
  DisclaimerText: TNewStaticText;
  InstalledInfoText: string;
  InstallInfoLabel: TNewStaticText;
  UpdateNoticeLabel: TNewStaticText;
  NextOptionIndex: Integer;
begin
  DetectExistingInstall();

  if ExistingInstallPath <> '' then
  begin
    WizardForm.DirEdit.Text := ExistingInstallPath;
  end;

  ReadUpdateCacheInfo();

  DisclaimerPage := CreateCustomPage(
    wpLicense,
    'Disclaimer',
    'Review the AutoDoctor diagnostic disclaimer before continuing.'
  );

  DisclaimerText := TNewStaticText.Create(DisclaimerPage);
  DisclaimerText.Parent := DisclaimerPage.Surface;
  DisclaimerText.Caption :=
    'Disclaimer:'#13#10 +
    'AutoDoctor diagnostics are informational and provided without warranty.';
  DisclaimerText.Top := ScaleY(12);
  DisclaimerText.Left := ScaleX(0);
  DisclaimerText.Width := DisclaimerPage.SurfaceWidth;
  DisclaimerText.AutoSize := False;
  DisclaimerText.Height := ScaleY(56);
  DisclaimerText.WordWrap := True;

  InstallModePage := nil;
  UpgradeOptionVisible := False;
  UpgradeOptionIndex := -1;
  RepairOptionIndex := -1;
  RemoveOptionIndex := -1;

  if ExistingInstallDetected then
  begin
    InstallModePage := CreateInputOptionPage(
      DisclaimerPage.ID,
      'Existing Installation Detected',
      'Choose how setup should proceed',
      'AutoDoctor is already installed on this machine.',
      True,
      False
    );

    UpgradeOptionVisible := UpdateCacheAvailable and (UpdateCacheLatestVersion <> '');
    NextOptionIndex := 0;

    if UpgradeOptionVisible then
    begin
      UpgradeOptionIndex := NextOptionIndex;
      InstallModePage.Add('Upgrade (default) - install new version files');
      NextOptionIndex := NextOptionIndex + 1;
    end;

    RepairOptionIndex := NextOptionIndex;
    InstallModePage.Add('Repair - reinstall this version');
    NextOptionIndex := NextOptionIndex + 1;

    RemoveOptionIndex := NextOptionIndex;
    InstallModePage.Add('Remove - uninstall AutoDoctor and exit setup');

    if UpgradeOptionVisible then
    begin
      InstallModePage.Values[UpgradeOptionIndex] := True;
    end
    else
    begin
      InstallModePage.Values[RepairOptionIndex] := True;
    end;

    InstalledInfoText := 'Detected installation';
    if ExistingInstallVersion <> '' then
    begin
      InstalledInfoText := InstalledInfoText + #13#10 + 'Installed version: v' + ExistingInstallVersion;
    end;

    if ExistingInstallPath <> '' then
    begin
      InstalledInfoText := InstalledInfoText + #13#10 + 'Path: ' + ExistingInstallPath;
    end;

    InstallInfoLabel := TNewStaticText.Create(InstallModePage);
    InstallInfoLabel.Parent := InstallModePage.Surface;
    InstallInfoLabel.Caption := InstalledInfoText;
    InstallInfoLabel.Top := InstallModePage.CheckListBox.Top + InstallModePage.CheckListBox.Height + ScaleY(8);
    InstallInfoLabel.Left := ScaleX(0);
    InstallInfoLabel.Width := InstallModePage.SurfaceWidth;
    InstallInfoLabel.AutoSize := False;
    InstallInfoLabel.Height := ScaleY(42);
    InstallInfoLabel.WordWrap := True;

    if UpgradeOptionVisible then
    begin
      UpdateNoticeLabel := TNewStaticText.Create(InstallModePage);
      UpdateNoticeLabel.Parent := InstallModePage.Surface;
      UpdateNoticeLabel.Caption := 'A newer version (v' + UpdateCacheLatestVersion + ') is available.';
      UpdateNoticeLabel.Top := InstallInfoLabel.Top + InstallInfoLabel.Height + ScaleY(4);
      UpdateNoticeLabel.Left := ScaleX(0);
      UpdateNoticeLabel.Width := InstallModePage.SurfaceWidth;
      UpdateNoticeLabel.AutoSize := False;
      UpdateNoticeLabel.Height := ScaleY(24);
      UpdateNoticeLabel.WordWrap := True;
    end;
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;

  if (InstallModePage <> nil) and (CurPageID = InstallModePage.ID) then
  begin
    if GetSelectedInstallAction() = INSTALL_ACTION_REMOVE then
    begin
      if not RunExistingUninstaller() then
      begin
        if not WizardSilent then
        begin
          MsgBox(
            'Unable to run the existing AutoDoctor uninstaller automatically. ' +
            'Please uninstall AutoDoctor manually and rerun setup.',
            mbError,
            MB_OK
          );
        end;

        Result := False;
        exit;
      end
      else
      begin
        if not WizardSilent then
        begin
          MsgBox('AutoDoctor removal completed. Setup will now exit.', mbInformation, MB_OK);
        end;
      end;

      Result := False;
      WizardForm.Close;
      exit;
    end;
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
var
  UpdateLine: string;
begin
  if (CurPageID = wpReady) and UpdateCacheAvailable and (UpdateCacheLatestVersion <> '') then
  begin
    UpdateLine := 'Update available: v' + UpdateCacheLatestVersion;

    if Pos(UpdateLine, WizardForm.ReadyMemo.Text) = 0 then
    begin
      WizardForm.ReadyMemo.Lines.Add('');
      WizardForm.ReadyMemo.Lines.Add(UpdateLine);
    end;
  end;
end;


procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    ConfigureServiceModeIni();

    if WizardIsTaskSelected('servicepython') then
    begin
      InstallServiceUsingSystemPython();
    end;
  end;
end;


procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    StopAndRemoveService();
  end;
end;
