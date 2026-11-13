; VM Health Check - Inno Setup 6
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "dist"
#endif
#define MyAppName "VM Health Check"
#define MyAppExeName "VMHealthCheck.exe"

[Setup]
AppId={{A3C1E2D4-11AA-4B2C-9F0E-5D6E7F8A9B01}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=vm technology
DefaultDirName={autopf}\VM Health Check
DefaultGroupName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputBaseFilename=VMHealthCheck_Setup_{#MyAppVersion}
SetupIconFile={#SourceDir}\app.ico
Compression=lzma2/ultra64
SolidCompression=yes
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
MinVersion=10.0
DisableProgramGroupPage=yes

[Languages]
Name: "italian"; MessagesFile: "compiler:Languages\Italian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\VMHealthCheck.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\VMHealth.Engine.psm1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\VMHealth.CLI.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\GUI.xaml"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\logo.png"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\app.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Avvia-CLI.cmd"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\app.ico"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\app.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
