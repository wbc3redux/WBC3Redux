; PACKAGING.md step 4: the player's installer (Inno Setup 7). Built by packaging/build.ps1 after the game export
; (packaging/build_game.ps1) and importer.exe (packaging/build_importer.ps1):
;   ISCC.exe /DAppVersion=0.1.0 packaging\installer.iss  ->  .local\packaging\installer\<AppFile>-Setup-<version>.exe
;
; Ships only our code: the Godot export, importer.exe and the re-import script. The player's own Warlords Battlecry III
; is converted on their machine after the files are copied (importer.exe, then the game's --prepare-assets pass); the
; original installation is only read. Per-user install, no administrator rights.

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
; The product name (decided 2026-11-17, PACKAGING.md "Name"): WBC3 Redux, always presented as an unofficial fan project
; that requires the original game. File and folder names have no spaces.
; /DTestBuild (packaging/build.ps1 -Test): its own AppId and name, so a test install never takes over a real install's
; registration, Start menu folder or uninstall entry (that happened once, 2026-11-17).
#ifdef TestBuild
  #define AppName "WBC3 Redux test"
  #define AppFile "WBC3Redux-test"
  #define AppIdGuid "6C0E4A57-9B3F-4E2A-8F61-2D7B5A9C1E34"
#else
  #define AppName "WBC3 Redux"
  #define AppFile "WBC3Redux"
  #define AppIdGuid "15FF862D-DD00-4A30-A283-A44497766ADC"
#endif
#define GameExe "WBC3Redux.exe"
#define Build "..\.local\packaging"

[Setup]
AppId={{{#AppIdGuid}}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Unofficial fan project (requires Warlords Battlecry III)
AppComments=Unofficial fan reimplementation of the Warlords Battlecry III skirmish. Requires the original game.
DefaultDirName={autopf}\{#AppFile}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
OutputDir={#Build}\installer
OutputBaseFilename={#AppFile}-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
SetupIconFile=..\artwork\icon\wbc3redux.ico
UninstallDisplayIcon={app}\{#GameExe}
UninstallDisplayName={#AppName}
; The game data ends as one wbc3-data.pck of about 1 GB; while importing and packing, about 2 GB are in use.
ExtraDiskSpaceRequired=2100000000
SetupLogging=yes

#ifndef TestBuild
[InstallDelete]
; An install from before the rename (0.1.0 as "WBC3-Godot"): its exe and shortcuts. Same AppId, so it upgrades in place.
; Release build only: these names belong to a real install, which a test build must never touch (2026-11-17, a test
; install deleted the user's real "WBC3-Godot" Start menu folder through this section).
Type: files; Name: "{app}\WBC3-Godot.exe"
Type: filesandordirs; Name: "{autoprograms}\WBC3-Godot"
Type: files; Name: "{autodesktop}\WBC3-Godot.lnk"
#endif

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "{#Build}\game\{#GameExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Build}\importer\*"; DestDir: "{app}\importer"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "reimport.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}\{#AppName}"; Filename: "{app}\{#GameExe}"; WorkingDir: "{app}"
Name: "{autoprograms}\{#AppName}\Re-import game data"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\reimport.ps1"""; WorkingDir: "{app}"; Comment: "Convert the art, sound and maps of your Warlords Battlecry III again (for example after moving it)"
Name: "{autoprograms}\{#AppName}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#GameExe}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#GameExe}"; Description: "Start {#AppName} now"; WorkingDir: "{app}"; Flags: postinstall nowait skipifsilent; Check: ImportSucceeded

[UninstallDelete]
; Everything the import wrote. Saves and settings stay in the player's profile; the original game is never touched.
Type: files; Name: "{app}\wbc3-data.pck"
Type: files; Name: "{app}\wbc3-data.pck.tmp"
Type: filesandordirs; Name: "{app}\assets"
Type: filesandordirs; Name: "{app}\wbc-import-*"
Type: files; Name: "{app}\source.cfg"
Type: files; Name: "{app}\import-log.txt"
Type: dirifempty; Name: "{app}"

[Code]
var
  WbcPage: TInputDirWizardPage;
  ImportPage: TOutputProgressWizardPage;
  ImportLog: TStringList;
  ImportOk: Boolean;
  ImportFailure: String;

function IsWbcFolder(const Dir: String): Boolean;
begin
  Result := (Trim(Dir) <> '') and FileExists(AddBackslash(Trim(Dir)) + 'Battlecry III.exe');
end;

procedure Consider(var Found: String; const Dir: String);
begin
  if (Found = '') and IsWbcFolder(Dir) then
    Found := RemoveBackslashUnlessRoot(Trim(Dir));
end;

procedure ConsiderRegistry(var Found: String; const RootKey: Integer; const SubKey, ValueName: String);
var
  Value: String;
begin
  if (Found = '') and RegQueryStringValue(RootKey, SubKey, ValueName, Value) then
    Consider(Found, Value);
end;

{ Steam: the main folder plus every library in steamapps\libraryfolders.vdf ("path" lines); the game folder name is
  not verified for Steam, so both spellings are tried. }
procedure ConsiderSteam(var Found: String);
var
  SteamPath, Line, Lib: String;
  Lines: TArrayOfString;
  I, P: Integer;
  Libraries: TStringList;
begin
  if not RegQueryStringValue(HKCU, 'Software\Valve\Steam', 'SteamPath', SteamPath) then
    exit;
  StringChangeEx(SteamPath, '/', '\', True);
  Libraries := TStringList.Create;
  try
    Libraries.Add(SteamPath);
    if LoadStringsFromFile(AddBackslash(SteamPath) + 'steamapps\libraryfolders.vdf', Lines) then
      for I := 0 to GetArrayLength(Lines) - 1 do begin
        Line := Trim(Lines[I]);
        if Pos('"path"', Line) = 1 then begin
          Lib := Trim(Copy(Line, 7, Length(Line)));
          P := Pos('"', Lib);
          if P > 0 then begin
            Lib := Copy(Lib, P + 1, Length(Lib));
            P := Pos('"', Lib);
            if P > 0 then begin
              Lib := Copy(Lib, 1, P - 1);
              StringChangeEx(Lib, '\\', '\', True);
              Libraries.Add(Lib);
            end;
          end;
        end;
      end;
    for I := 0 to Libraries.Count - 1 do begin
      Consider(Found, AddBackslash(Libraries[I]) + 'steamapps\common\Warlords Battlecry III');
      Consider(Found, AddBackslash(Libraries[I]) + 'steamapps\common\Warlords Battlecry 3');
    end;
  finally
    Libraries.Free;
  end;
end;

{ GOG registry, GOG's uninstall entry, Steam, then the usual folders. Empty when nothing is found (the player browses). }
function DetectWbc: String;
begin
  Result := '';
  ConsiderRegistry(Result, HKLM32, 'SOFTWARE\GOG.com\Games\1207658725', 'path');
  ConsiderRegistry(Result, HKLM64, 'SOFTWARE\GOG.com\Games\1207658725', 'path');
  ConsiderRegistry(Result, HKLM32, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\1207658725_is1', 'InstallLocation');
  ConsiderRegistry(Result, HKLM64, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\1207658725_is1', 'InstallLocation');
  ConsiderRegistry(Result, HKCU, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\1207658725_is1', 'InstallLocation');
  ConsiderSteam(Result);
  Consider(Result, ExpandConstant('{commonpf32}\GOG Galaxy\Games\Warlords Battlecry III'));
  Consider(Result, ExpandConstant('{commonpf32}\GOG Games\Warlords Battlecry III'));
  Consider(Result, ExpandConstant('{sd}\GOG Games\Warlords Battlecry III'));
  Consider(Result, ExpandConstant('{commonpf32}\Warlords Battlecry III'));
  Consider(Result, ExpandConstant('{commonpf32}\Infinite Interactive\Warlords Battlecry III'));
end;

function ImportSucceeded: Boolean;
begin
  Result := ImportOk;
end;

procedure InitializeWizard;
begin
  WbcPage := CreateInputDirPage(wpSelectDir,
    'Warlords Battlecry III', 'Where is your copy of Warlords Battlecry III?',
    'This game uses the art, sound and maps of your own Warlords Battlecry III (GOG, Steam or CD). They are converted ' +
    'once, after the files are copied; your Warlords Battlecry III folder is only read, never changed.' + #13#10#13#10 +
    'Choose the folder that contains Battlecry III.exe:', False, '');
  WbcPage.Add('');
  { /WBC3="<folder>" on the command line (silent installs, tests) wins over the previous install and the detection. }
  WbcPage.Values[0] := ExpandConstant('{param:WBC3|}');
  if WbcPage.Values[0] = '' then
    WbcPage.Values[0] := GetPreviousData('WbcPath', DetectWbc());
  ImportPage := CreateOutputProgressPage('Importing your game data',
    'Converting the art, sound and maps of your Warlords Battlecry III. This takes about 7 minutes.');
  ImportLog := TStringList.Create;
end;

procedure RegisterPreviousData(PreviousDataKey: Integer);
begin
  SetPreviousData(PreviousDataKey, 'WbcPath', WbcPage.Values[0]);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = WbcPage.ID then begin
    if not IsWbcFolder(WbcPage.Values[0]) then begin
      MsgBox('This folder does not contain Battlecry III.exe.' + #13#10#13#10 +
        'Choose the folder where Warlords Battlecry III is installed.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo, MemoComponentsInfo,
  MemoGroupInfo, MemoTasksInfo: String): String;
begin
  Result := MemoDirInfo + NewLine + NewLine +
    'Warlords Battlecry III (read only):' + NewLine + Space + WbcPage.Values[0] + NewLine + NewLine +
    'After copying, your game data is imported (about 7 minutes, about 1 GB).';
  if MemoTasksInfo <> '' then
    Result := Result + NewLine + NewLine + MemoTasksInfo;
end;

procedure Remember(const S: String);
begin
  ImportLog.Add(S);
  Log(S);
end;

{ importer.exe prints 'PROGRESS <percent> <label>'; the import fills the first 75 % of the bar. }
procedure OnImportLine(const S: String; const Error, FirstLine: Boolean);
var
  Rest, Caption: String;
  P, Percent: Integer;
begin
  Remember(S);
  if Pos('PROGRESS ', S) = 1 then begin
    Rest := Copy(S, 10, Length(S));
    P := Pos(' ', Rest);
    if P > 0 then begin
      Percent := StrToIntDef(Copy(Rest, 1, P - 1), 0);
      Caption := Copy(Rest, P + 1, Length(Rest));
      if Percent = 78 then
        Caption := Caption + ' (the longest step, about 4 minutes)';
      ImportPage.SetText(Caption, '');
      ImportPage.SetProgress(Percent * 75 div 100, 100);
    end;
  end;
end;

{ The game's --prepare-assets --pack pass prints 'prepare <done>/<total>' (75..92 %), then 'pack <done>/<total>'
  while it writes the single data file (92..100 %). }
procedure OnPrepareLine(const S: String; const Error, FirstLine: Boolean);
var
  Rest: String;
  P, Done, Total, Start, Span: Integer;
  Caption: String;
begin
  Rest := '';
  if Pos('prepare ', S) = 1 then begin
    Rest := Copy(S, 9, Length(S)); Start := 75; Span := 17; Caption := 'Preparing the images';
  end else if Pos('pack ', S) = 1 then begin
    Rest := Copy(S, 6, Length(S)); Start := 92; Span := 8; Caption := 'Packing the game data into one file';
  end else
    Remember(S);
  P := Pos('/', Rest);
  if P > 0 then begin
    Done := StrToIntDef(Copy(Rest, 1, P - 1), 0);
    Total := StrToIntDef(Copy(Rest, P + 1, Length(Rest)), 0);
    if Total > 0 then begin
      ImportPage.SetText(Caption, Format('%d of %d', [Done, Total]));
      ImportPage.SetProgress(Start + Done * Span div Total, 100);
    end;
  end;
end;

procedure RunImport;
var
  Source, Assets: String;
  ResultCode: Integer;
begin
  ImportOk := False;
  ImportFailure := '';
  Source := RemoveBackslashUnlessRoot(Trim(WbcPage.Values[0]));
  Assets := ExpandConstant('{app}\assets');
  SaveStringToFile(ExpandConstant('{app}\source.cfg'), '[source]' + #13#10 + 'path=' + Source + #13#10, False);
  ImportPage.SetText('Starting the import', '');
  ImportPage.SetProgress(0, 100);
  ImportPage.Show;
  try
    Remember('Import from ' + Source + ' into ' + Assets);
    if not ExecAndLogOutput(ExpandConstant('{app}\importer\importer.exe'),
        '--source ' + AddQuotes(Source) + ' --dest ' + AddQuotes(Assets), ExpandConstant('{app}'),
        SW_HIDE, ewWaitUntilTerminated, ResultCode, @OnImportLine) then
      ImportFailure := 'The importer could not be started: ' + SysErrorMessage(ResultCode)
    else if ResultCode = 3 then
      ImportFailure := 'This copy of Warlords Battlecry III is a version the importer does not support yet ' +
        '(it was verified on the GOG release). The details, with the files that differ, are in import-log.txt; ' +
        'please report them.'
    else if ResultCode <> 0 then
      ImportFailure := Format('The import failed (code %d). The details are in import-log.txt.', [ResultCode]);
    if ImportFailure = '' then begin
      Remember('Preparing the images and packing the game data');
      if not ExecAndLogOutput(ExpandConstant('{app}\{#GameExe}'), '--headless -- --prepare-assets --pack',
          ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ResultCode, @OnPrepareLine) then
        ImportFailure := 'The game could not be started to prepare the images: ' + SysErrorMessage(ResultCode)
      else if (ResultCode <> 0) or not FileExists(ExpandConstant('{app}\wbc3-data.pck')) then
        ImportFailure := Format('Preparing and packing the game data failed (code %d). The details are in ' +
          'import-log.txt; run "Re-import game data" to try again.', [ResultCode]);
    end;
    ImportOk := ImportFailure = '';
    if ImportOk then
      Remember('Import finished');
  finally
    ImportLog.SaveToFile(ExpandConstant('{app}\import-log.txt'));
    ImportPage.Hide;
  end;
  if not ImportOk then
    SuppressibleMsgBox(ImportFailure + #13#10#13#10 + 'The game is installed. After fixing the problem, run ' +
      '"Re-import game data" from the Start menu.' + #13#10#13#10 + 'Log: ' + ExpandConstant('{app}\import-log.txt'),
      mbError, MB_OK, IDOK);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    RunImport;
end;

procedure DeinitializeSetup;
begin
  if ImportLog <> nil then
    ImportLog.Free;
end;
