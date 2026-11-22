#ifndef AppVersion
  #error AppVersion is required. Run installer\build-installer.ps1 -App SuperSpecForge.
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
AppId={{620FFFA1-EA88-40A3-BD37-8D9B0ACB6D6A}
AppName=SuperSpecForge
AppVersion={#AppVersion}
AppVerName=SuperSpecForge {#AppVersion}
AppPublisher=desomer
AppPublisherURL=https://github.com/desomer/surfFile
AppSupportURL=https://github.com/desomer/surfFile/issues
AppUpdatesURL=https://github.com/desomer/surfFile/releases
VersionInfoVersion={#AppVersionNumber}
DefaultDirName={localappdata}\Programs\SuperSpecForge
DefaultGroupName=SuperSpecForge
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17134
OutputDir=..\build\installer
OutputBaseFilename=SuperSpecForge-{#AppVersion}-windows-x64-setup
SetupIconFile=..\packages\super_spec_forge\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\super_spec_forge.exe
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
Name: "{group}\SuperSpecForge"; Filename: "{app}\super_spec_forge.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\SuperSpecForge"; Filename: "{app}\super_spec_forge.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\super_spec_forge.exe"; Description: "{cm:LaunchProgram,SuperSpecForge}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
