; vnc-stack Setup wizard (Inno Setup 6), "light" version.
; Build: open this file in the Inno Setup Compiler, then Build > Compile (Ctrl+F9).
; Output: installer\Output\vnc-stack-setup-0.4.exe
; The wizard copies the repo files to the install folder, then opens a console window
; that runs windows\win10.ps1 or windows\win11.ps1 (picked from the Windows build).

#define AppName "vnc-stack"
#define AppVersion "0.4"
#define AppPublisher "Audacity Keep"

[Setup]
AppId={{B6F0C3A2-5D1E-4C8A-9B7F-2E4D6A1C9F31}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
SourceDir=..
OutputDir={#SourcePath}Output
OutputBaseFilename=vnc-stack-setup-{#AppVersion}
DefaultDirName=C:\vnc-stack
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
MinVersion=10.0.19041
LicenseFile=LICENSE
Compression=lzma
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#AppName}

[Messages]
WelcomeLabel2=This copies the vnc-stack setup files to your PC, then opens a console window that installs WSL and Ubuntu, TightVNC and the remote-access web page.%n%nThis is a pre-release. It has not been tested on a clean PC yet.

[Tasks]
Name: "skipvdd"; Description: "Do not install the Virtual Display Driver (a virtual monitor)"; GroupDescription: "Options:"; Flags: unchecked

[Files]
Source: "windows\*"; DestDir: "{app}\windows"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "bin\*"; DestDir: "{app}\bin"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "templates\*"; DestDir: "{app}\templates"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "notify.d.examples\*"; DestDir: "{app}\notify.d.examples"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "setup.sh"; DestDir: "{app}"; Flags: ignoreversion
Source: "uninstall.sh"; DestDir: "{app}"; Flags: ignoreversion
Source: "README.md"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "LICENSE"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "installer\run.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion

[Icons]
Name: "{group}\Run vnc-stack setup"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installer\run.ps1"" -Action install"; WorkingDir: "{app}"
Name: "{group}\Uninstall vnc-stack"; Filename: "{uninstallexe}"

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installer\run.ps1"" -Action install{code:GetRunOptions}"; Description: "Run vnc-stack setup now"; Flags: postinstall waituntilterminated skipifsilent

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installer\run.ps1"" -Action uninstall"; RunOnceId: "RemoveVncStack"; Flags: waituntilterminated

[Code]
var
  EmailPage: TInputQueryWizardPage;

procedure InitializeWizard();
begin
  EmailPage := CreateInputQueryPage(wpSelectTasks,
    'Access link email',
    'Optional: get the remote-access link by email',
    'Enter a Gmail address to receive your access link by email, or leave it blank to skip. ' +
    'If you enter one, the setup window asks for the Gmail app password later.');
  EmailPage.Add('Gmail address:', False);
end;

function EndsWith(const S, Suffix: String): Boolean;
begin
  Result := (Length(S) > Length(Suffix)) and
    (Copy(S, Length(S) - Length(Suffix) + 1, Length(Suffix)) = Suffix);
end;

function EmailLooksValid(const E: String): Boolean;
var
  L: String;
begin
  Result := True;
  if E = '' then Exit;
  L := LowerCase(E);
  Result := (Pos(' ', L) = 0) and (Pos('"', L) = 0) and (Pos('''', L) = 0) and
    (EndsWith(L, '@gmail.com') or EndsWith(L, '@googlemail.com'));
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = EmailPage.ID then
  begin
    if not EmailLooksValid(Trim(EmailPage.Values[0])) then
    begin
      MsgBox('Please enter a Gmail address (name@gmail.com) with no spaces, or leave it blank to skip the email.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

function GetRunOptions(Param: String): String;
begin
  Result := '';
  if WizardIsTaskSelected('skipvdd') then
    Result := Result + ' -NoVdd';
  if Trim(EmailPage.Values[0]) <> '' then
    Result := Result + ' -Email ' + Trim(EmailPage.Values[0]);
end;
