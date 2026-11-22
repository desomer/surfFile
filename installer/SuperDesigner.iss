#ifndef AppVersion
  #error AppVersion is required. Run installer\build-installer.ps1 -App SuperDesigner.
#endif
#ifndef AppVersionNumber
  #error AppVersionNumber is required.
#endif
#ifndef ReleaseDir
  #error ReleaseDir is required.
#endif
#ifndef RuntimeDir
  #error RuntimeDir is required.
#endif

[Setup]
AppId={{13A8EC73-0A22-402C-8EF7-878FC28A5F0F}
AppName=SuperDesigner
AppVersion={#AppVersion}
AppVerName=SuperDesigner {#AppVersion}
AppPublisher=desomer
AppPublisherURL=https://github.com/desomer/surfFile
AppSupportURL=https://github.com/desomer/surfFile/issues
AppUpdatesURL=https://github.com/desomer/surfFile/releases
VersionInfoVersion={#AppVersionNumber}
DefaultDirName={localappdata}\Programs\SuperDesigner
DefaultGroupName=SuperDesigner
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17134
OutputDir=..\build\installer
OutputBaseFilename=SuperDesigner-{#AppVersion}-windows-x64-setup
SetupIconFile=..\packages\super_designer\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\super_designer.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Excludes: "*.pdb,*.exp,*.lib"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RuntimeDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\SuperDesigner"; Filename: "{app}\super_designer.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\SuperDesigner"; Filename: "{app}\super_designer.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\super_designer.exe"; Description: "{cm:LaunchProgram,SuperDesigner}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
