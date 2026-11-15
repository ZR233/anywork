#if Ver < EncodeVer(6, 7, 0)
  #error Inno Setup 6.7.0 or newer is required for RedirectionGuard
#endif

#ifndef MyAppVersion
  #error MyAppVersion is required
#endif
#ifndef SourceDir
  #error SourceDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#ifndef OutputBase
  #error OutputBase is required
#endif

#define MyAppName "anywork"
#define MyAppPublisher "Pure-Lang"
#define MyAppExeName "anywork.exe"

[Setup]
AppId={{701A3525-12D7-4D51-A83E-8A62EE6F3060}
AppName={cm:AppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\anywork
DefaultGroupName={cm:AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
; Keep this non-elevating installer from passing RedirectionGuard to the app
; and its developer tools after installation or an update restart. See #167.
RedirectionGuard=no
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBase}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=yes
SetupLogging=yes
ChangesEnvironment=yes
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
VersionInfoVersion={#MyAppVersion}.0
VersionInfoProductName={#MyAppName}
VersionInfoDescription={#MyAppName} Installer
LicenseFile={#SourceDir}\LICENSE

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "zh"; MessagesFile: "Languages\ChineseSimplified.isl"
Name: "zhTW"; MessagesFile: "compiler:Default.isl"

[LangOptions]
zhTW.LanguageName=繁體中文
zhTW.LanguageID=$0404

[CustomMessages]
en.AppName=anywork
zh.AppName=糊来帮
zhTW.AppName=糊来帮
en.CreateDesktopIcon=Create a desktop shortcut
zh.CreateDesktopIcon=创建桌面快捷方式
zhTW.CreateDesktopIcon=建立桌面捷徑
en.AddToPath=Add anywk to the user PATH (restart terminals after installation)
zh.AddToPath=将 anywk 添加到用户 PATH（安装后请重新打开终端）
zhTW.AddToPath=將 anywk 加入使用者 PATH（安裝後請重新開啟終端機）
en.AdditionalIcons=Additional icons:
zh.AdditionalIcons=附加图标：
zhTW.AdditionalIcons=附加圖示：
en.LaunchApp=Launch %1
zh.LaunchApp=启动 %1
zhTW.LaunchApp=啟動 %1

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "*.pdb"

[Icons]
Name: "{autoprograms}\{cm:AppName}"; Filename: "{app}\{#MyAppExeName}"; AppUserModelID: "io.github.zr233.anywork"
Name: "{autodesktop}\{cm:AppName}"; Filename: "{app}\{#MyAppExeName}"; AppUserModelID: "io.github.zr233.anywork"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

Name: "addtopath"; Description: "{cm:AddToPath}"

[Dirs]
Name: "{localappdata}\anywork\crashes"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\Windows Error Reporting\LocalDumps\{#MyAppExeName}"; ValueType: expandsz; ValueName: "DumpFolder"; ValueData: "{localappdata}\anywork\crashes"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\Windows Error Reporting\LocalDumps\{#MyAppExeName}"; ValueType: dword; ValueName: "DumpType"; ValueData: "2"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\Windows Error Reporting\LocalDumps\{#MyAppExeName}"; ValueType: dword; ValueName: "DumpCount"; ValueData: "10"; Flags: uninsdeletevalue

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchApp,{cm:AppName}}"; Flags: nowait postinstall skipifsilent; Check: not IsAppUpdate

Filename: "{app}\{#MyAppExeName}"; Flags: nowait; Check: ShouldRestartAfterUpdate

[Code]
{ Use Inno Setup's user registry API and ChangesEnvironment notification.
  Store ownership separately so uninstall leaves pre-existing PATH entries alone. }
function PathEntryKey(Value: String): String;
begin
  Result := RemoveBackslashUnlessRoot(RemoveQuotes(Trim(Value)));
end;

function FilterCliPath(Value, CliPath: String; var Found: Boolean): String;
var
  Part: String;
  Separator: Integer;
  First: Boolean;
begin
  Result := '';
  Found := False;
  First := True;
  repeat
    Separator := Pos(';', Value);
    if Separator = 0 then Part := Value
    else Part := Copy(Value, 1, Separator - 1);
    if CompareText(PathEntryKey(Part), PathEntryKey(CliPath)) = 0 then
      Found := True
    else begin
      if not First then Result := Result + ';';
      Result := Result + Part;
      First := False;
    end;
    if Separator = 0 then Break;
    Delete(Value, 1, Separator);
  until False;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Existing, CliPath, Ignored: String;
  Found: Boolean;
begin
  if (CurStep <> ssPostInstall) or not WizardIsTaskSelected('addtopath') then Exit;
  CliPath := ExpandConstant('{app}\bin');
  Existing := '';
  if RegValueExists(HKCU, 'Environment', 'Path') and
    not RegQueryStringValue(HKCU, 'Environment', 'Path', Existing) then
    RaiseException('Cannot read the user PATH.');
  Ignored := FilterCliPath(Existing, CliPath, Found);
  if Found then Exit;
  if not RegWriteStringValue(HKCU, 'Software\anywork\Installer', 'OwnedCliPath', CliPath) then
    RaiseException('Cannot record the anywk PATH entry.');
  { Preserve existing empty entries, including a trailing semicolon. }
  if Existing <> '' then Existing := Existing + ';';
  if not RegWriteExpandStringValue(HKCU, 'Environment', 'Path', Existing + CliPath) then begin
    RegDeleteValue(HKCU, 'Software\anywork\Installer', 'OwnedCliPath');
    RaiseException('Cannot update the user PATH.');
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Existing, Owned, Updated: String;
  Found: Boolean;
begin
  if CurUninstallStep <> usUninstall then Exit;
  if not RegQueryStringValue(HKCU, 'Software\anywork\Installer', 'OwnedCliPath', Owned) then Exit;
  if CompareText(PathEntryKey(Owned), PathEntryKey(ExpandConstant('{app}\bin'))) <> 0 then Exit;
  if RegQueryStringValue(HKCU, 'Environment', 'Path', Existing) then begin
    Updated := FilterCliPath(Existing, Owned, Found);
    if Found and not RegWriteExpandStringValue(HKCU, 'Environment', 'Path', Updated) then
      RaiseException('Cannot remove the anywk user PATH entry.');
  end else if RegValueExists(HKCU, 'Environment', 'Path') then
    RaiseException('Cannot read the user PATH.');
  RegDeleteValue(HKCU, 'Software\anywork\Installer', 'OwnedCliPath');
  RegDeleteKeyIfEmpty(HKCU, 'Software\anywork\Installer');
end;

function IsAppUpdate: Boolean;
begin
  { Published Windows clients still hand off exit-only updates with this value. }
  Result := (ExpandConstant('{param:ANYWORKUPDATE|0}') = '1') or
    (ExpandConstant('{param:ANYWORKUPDATE|0}') = 'exit');
end;

function ShouldRestartAfterUpdate: Boolean;
begin
  Result := ExpandConstant('{param:ANYWORKUPDATE|0}') = '1';
end;

function OpenProcess(Access: LongWord; InheritHandle: Boolean; ProcessId: LongWord): THandle;
  external 'OpenProcess@kernel32.dll stdcall';
function WaitForSingleObject(Handle: THandle; Milliseconds: LongWord): LongWord;
  external 'WaitForSingleObject@kernel32.dll stdcall';
function CloseHandle(Handle: THandle): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';

function InitializeSetup: Boolean;
var
  ProcessId: Integer;
  ProcessHandle: THandle;
  WaitResult: LongWord;
  WaitParameter: String;
begin
  Result := True;
  if not IsAppUpdate then Exit;
  WaitParameter := ExpandConstant('{param:ANYWORKWAITPID|}');
  { Older published clients use Restart Manager instead of the new process-wait protocol. }
  if WaitParameter = '' then Exit;
  ProcessId := StrToIntDef(WaitParameter, 0);
  if ProcessId <= 0 then begin
    Log('Invalid ANYWORKWAITPID; refusing update installation.');
    Result := False;
    Exit;
  end;
  ProcessHandle := OpenProcess($00100000, False, ProcessId); { SYNCHRONIZE }
  if ProcessHandle = 0 then begin
    { ERROR_INVALID_PARAMETER means that the old process has already exited. }
    Result := DLLGetLastError = 87;
    if not Result then Log('Could not observe the old application process; refusing installation.');
    Exit;
  end;
  Log(Format('Waiting for application process %d to exit.', [ProcessId]));
  WaitResult := WaitForSingleObject(ProcessHandle, 30000);
  CloseHandle(ProcessHandle);
  Result := WaitResult = 0; { WAIT_OBJECT_0 }
  if not Result then Log('The old application did not exit; refusing installation.');
end;
