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
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin
ChangesEnvironment=yes
WizardStyle=modern
SetupIconFile={#SourceRoot}\server\dashboard\favicon.ico
UninstallDisplayIcon={app}\server\dashboard\favicon.ico

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
Root: HKLM64; Subkey: "Software\AutoDoctor"; ValueType: string; ValueName: "InstallRoot"; ValueData: "{app}"; Flags: uninsdeletevalue

[Icons]
Name: "{group}\Run AutoDoctor Scan"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""{app}\agent\AutoDoctor.ps1"""; WorkingDir: "{app}\agent"; IconFilename: "{app}\server\dashboard\favicon.ico"
Name: "{group}\Initialize AutoDoctor"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""{app}\agent\Initialize-AutoDoctor.ps1"""; WorkingDir: "{app}\agent"; IconFilename: "{app}\server\dashboard\favicon.ico"
Name: "{group}\Open AutoDoctor Dashboard"; Filename: "{cmd}"; Parameters: "/c start """" ""{#DashboardURL}"""; WorkingDir: "{app}"; IconFilename: "{app}\server\dashboard\favicon.ico"
Name: "{commondesktop}\Run AutoDoctor Scan"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""{app}\agent\AutoDoctor.ps1"""; WorkingDir: "{app}\agent"; IconFilename: "{app}\server\dashboard\favicon.ico"; Tasks: desktopicons
Name: "{commondesktop}\Open AutoDoctor Dashboard"; Filename: "{cmd}"; Parameters: "/c start """" ""{#DashboardURL}"""; WorkingDir: "{app}"; IconFilename: "{app}\server\dashboard\favicon.ico"; Tasks: desktopicons

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""{app}\agent\Initialize-AutoDoctor.ps1"""; Flags: runhidden waituntilterminated; Tasks: seedbootstrap; StatusMsg: "Initializing AutoDoctor schema and first telemetry snapshot..."
Filename: "{app}\server\api\autodoctor_service.exe"; Parameters: "--startup auto update"; Flags: runhidden waituntilterminated; Check: IsTaskSelected('servicebundled') and ServiceExists('{#MyServiceName}'); StatusMsg: "Updating AutoDoctor API service..."
Filename: "{app}\server\api\autodoctor_service.exe"; Parameters: "--startup auto install"; Flags: runhidden waituntilterminated; Check: IsTaskSelected('servicebundled') and (not ServiceExists('{#MyServiceName}')); StatusMsg: "Registering AutoDoctor API service..."
Filename: "{app}\server\api\autodoctor_service.exe"; Parameters: "start"; Flags: runhidden waituntilterminated; Check: IsTaskSelected('servicebundled'); StatusMsg: "Starting AutoDoctor API service..."
Filename: "{cmd}"; Parameters: "/c start """" ""{#DashboardURL}"""; Flags: postinstall skipifsilent unchecked; Description: "Open AutoDoctor Dashboard"

[Code]
var
  SystemPythonCommand: string;

function ServiceExists(const ServiceName: string): Boolean;
begin
  Result := RegKeyExists(HKLM64, 'SYSTEM\CurrentControlSet\Services\' + ServiceName);
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
  if IsTaskSelected('servicepython') then
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


procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    ConfigureServiceModeIni();

    if IsTaskSelected('servicepython') then
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
