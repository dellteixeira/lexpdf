#define AppName "LexPDF"
#define AppPublisher "LexPDF"
#define AppExeName "lexpdf_app.exe"
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\build\windows\installer"
#endif

[Setup]
AppId={{C720D1F2-62A4-49E2-A731-DBA9F1935412}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\Programs\LexPDF
DefaultGroupName=LexPDF
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=LexPDF-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
ChangesAssociations=yes
UninstallDisplayIcon={app}\{#AppExeName}
SetupLogging=yes

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na Área de Trabalho"; GroupDescription: "Atalhos:"; Flags: unchecked
Name: "pdfassociation"; Description: "Adicionar LexPDF ao Abrir com para arquivos PDF"; GroupDescription: "Arquivos PDF:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\LexPDF"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"
Name: "{userdesktop}\LexPDF"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Registry]
; Register a stable ProgID and Windows capabilities. Windows 10/11 intentionally
; protect the user's default-app choice, so LexPDF registers as an Open With
; handler instead of overwriting the UserChoice hash behind the user's back.
Root: HKCU; Subkey: "Software\Classes\LexPDF.PDF"; ValueType: string; ValueName: ""; ValueData: "Documento PDF do LexPDF"; Flags: uninsdeletekey; Tasks: pdfassociation
Root: HKCU; Subkey: "Software\Classes\LexPDF.PDF\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#AppExeName},0"; Tasks: pdfassociation
Root: HKCU; Subkey: "Software\Classes\LexPDF.PDF\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" ""%1"""; Tasks: pdfassociation
Root: HKCU; Subkey: "Software\Classes\.pdf\OpenWithProgids"; ValueType: none; ValueName: "LexPDF.PDF"; Flags: uninsdeletevalue; Tasks: pdfassociation
Root: HKCU; Subkey: "Software\Classes\Applications\{#AppExeName}"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "LexPDF"; Flags: uninsdeletekey; Tasks: pdfassociation
Root: HKCU; Subkey: "Software\Classes\Applications\{#AppExeName}\SupportedTypes"; ValueType: string; ValueName: ".pdf"; ValueData: ""; Tasks: pdfassociation
Root: HKCU; Subkey: "Software\Classes\Applications\{#AppExeName}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" ""%1"""; Tasks: pdfassociation
Root: HKCU; Subkey: "Software\LexPDF\Capabilities"; ValueType: string; ValueName: "ApplicationName"; ValueData: "LexPDF"; Flags: uninsdeletekey; Tasks: pdfassociation
Root: HKCU; Subkey: "Software\LexPDF\Capabilities"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "Leitor, editor e caderno digital de PDFs"; Tasks: pdfassociation
Root: HKCU; Subkey: "Software\LexPDF\Capabilities\FileAssociations"; ValueType: string; ValueName: ".pdf"; ValueData: "LexPDF.PDF"; Tasks: pdfassociation
Root: HKCU; Subkey: "Software\RegisteredApplications"; ValueType: string; ValueName: "LexPDF"; ValueData: "Software\LexPDF\Capabilities"; Flags: uninsdeletevalue; Tasks: pdfassociation

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Abrir o LexPDF"; Flags: nowait postinstall skipifsilent
