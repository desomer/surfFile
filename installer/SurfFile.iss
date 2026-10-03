#ifndef AppVersion
  #error AppVersion is required. Run installer\build-installer.ps1.
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
AppId={{55D79B7A-2BD6-4859-8756-A10E4BDA713B}
AppName=SurfFile
AppVersion={#AppVersion}
AppVerName=SurfFile {#AppVersion}
AppPublisher=desomer
AppPublisherURL=https://github.com/desomer/surfFile
AppSupportURL=https://github.com/desomer/surfFile/issues
AppUpdatesURL=https://github.com/desomer/surfFile/releases
VersionInfoVersion={#AppVersionNumber}
DefaultDirName={localappdata}\Programs\SurfFile
DefaultGroupName=SurfFile
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17134
OutputDir=..\build\installer
OutputBaseFilename=SurfFile-{#AppVersion}-windows-x64-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\surf_file.exe
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
Name: "{group}\SurfFile"; Filename: "{app}\surf_file.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\SurfFile"; Filename: "{app}\surf_file.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\surf_file.exe"; Description: "{cm:LaunchProgram,SurfFile}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
