#ifndef MyAppVersion
  #define MyAppVersion "0.1.0-beta.1"
#endif

#define MyAppName "LexPDF"
#define MyAppExeName "lexpdf_app.exe"
#define MyAppProgId "LexPDF.Document"

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
ChangesAssociations=yes

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na área de trabalho"; GroupDescription: "Atalhos adicionais:"; Flags: unchecked
Name: "pdfassociation"; Description: "Registrar LexPDF como aplicativo para arquivos PDF"; GroupDescription: "Integração com o Windows:"; Flags: checkedonce

[Icons]
Name: "{autoprograms}\LexPDF"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\LexPDF"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
; ProgID and Open With registration. Windows 10/11 may still require the user
; to confirm the default app in Settings, but Explorer immediately exposes
; LexPDF in Open with and routes files through the single running instance.
Root: HKCU; Subkey: "Software\Classes\{#MyAppProgId}"; ValueType: string; ValueName: ""; ValueData: "Documento PDF do LexPDF"; Flags: uninsdeletekey; Tasks: pdfassociation
Root: HKCU; Subkey: "Software\Classes\{#MyAppProgId}\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"; Tasks: pdfassociation
Root: HKCU; Subkey: "Software\Classes\{#MyAppProgId}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Tasks: pdfassociation
Root: HKCU; Subkey: "Software\Classes\.pdf\OpenWithProgids"; ValueType: none; ValueName: "{#MyAppProgId}"; Flags: uninsdeletevalue; Tasks: pdfassociation
Root: HKCU; Subkey: "Software\Classes\Applications\{#MyAppExeName}"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "LexPDF"; Flags: uninsdeletekey; Tasks: pdfassociation
Root: HKCU; Subkey: "Software\Classes\Applications\{#MyAppExeName}\SupportedTypes"; ValueType: string; ValueName: ".pdf"; ValueData: ""; Tasks: pdfassociation
Root: HKCU; Subkey: "Software\Classes\Applications\{#MyAppExeName}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Tasks: pdfassociation

; Always provide a non-destructive Explorer context command even if the user
; does not make LexPDF the default PDF handler.
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.pdf\shell\LexPDF"; ValueType: string; ValueName: "MUIVerb"; ValueData: "Abrir com LexPDF"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.pdf\shell\LexPDF"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\{#MyAppExeName}";
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.pdf\shell\LexPDF\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1""";

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir LexPDF"; Flags: nowait postinstall skipifsilent
