#ifndef MyAppVersion
  #define MyAppVersion "0.1.0-beta.1"
#endif

#define MyAppName "LexPDF"
#define MyAppExeName "lexpdf_app.exe"

[Setup]
AppId={{A4F539EC-5B2E-4D6A-95D0-E3A5E40E1D01}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=LexPDF
DefaultDirName={autopf}\LexPDF
DefaultGroupName=LexPDF
DisableProgramGroupPage=yes
OutputDir=output
OutputBaseFilename=LexPDF-Setup-{#MyAppVersion}-x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
UninstallDisplayIcon={app}\{#MyAppExeName}

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\LexPDF"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\LexPDF"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na área de trabalho"; GroupDescription: "Atalhos adicionais:"; Flags: unchecked

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir LexPDF"; Flags: nowait postinstall skipifsilent
