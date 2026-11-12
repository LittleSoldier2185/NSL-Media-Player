; NSL Resonance installer (Inno Setup 6)
; Build the app first:  flutter build windows --release
; Then compile:         iscc installer\nsl_media_player.iss
; Output:               installer\Output\NSL-Resonance-Setup.exe

#define AppName "NSL Resonance"
#define AppVersion "1.0.0"
#define AppExe "nsl_media_player.exe"
#define ProgId "NslMediaPlayer.File"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{6B0C2E5A-3F4D-4C8E-9A57-0A1B2C3D4E5F}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=NSL
; Per-user install: no admin rights, registry goes to HKCU
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\NSL Resonance
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=NSL-Resonance-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Tell Explorer to refresh file associations
ChangesAssociations=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked
Name: "assoc"; Description: "Add {#AppName} to the ""Open with"" list and Default apps for media files"; Flags: checkedonce

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; --- ProgID: how to open a file ---
Root: HKCU; Subkey: "Software\Classes\{#ProgId}"; ValueType: string; ValueData: "NSL Resonance media file"; Flags: uninsdeletekey; Tasks: assoc
Root: HKCU; Subkey: "Software\Classes\{#ProgId}\DefaultIcon"; ValueType: string; ValueData: "{app}\{#AppExe},0"; Tasks: assoc
Root: HKCU; Subkey: "Software\Classes\{#ProgId}\shell\open\command"; ValueType: string; ValueData: """{app}\{#AppExe}"" ""%1"""; Tasks: assoc

; --- Application registration (Open with + Default apps list) ---
Root: HKCU; Subkey: "Software\Classes\Applications\{#AppExe}"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "{#AppName}"; Flags: uninsdeletekey; Tasks: assoc
Root: HKCU; Subkey: "Software\Classes\Applications\{#AppExe}\shell\open\command"; ValueType: string; ValueData: """{app}\{#AppExe}"" ""%1"""; Tasks: assoc

; --- Capabilities + RegisteredApplications (shows up in Settings > Default apps) ---
Root: HKCU; Subkey: "Software\NSL\MediaPlayer\Capabilities"; ValueType: string; ValueName: "ApplicationName"; ValueData: "{#AppName}"; Flags: uninsdeletekey; Tasks: assoc
Root: HKCU; Subkey: "Software\NSL\MediaPlayer\Capabilities"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "Play audio and video files"; Tasks: assoc
Root: HKCU; Subkey: "Software\RegisteredApplications"; ValueType: string; ValueName: "NSL Resonance"; ValueData: "Software\NSL\MediaPlayer\Capabilities"; Flags: uninsdeletevalue; Tasks: assoc
; The entry written under the old name (before the rename) is removed on upgrade
Root: HKCU; Subkey: "Software\RegisteredApplications"; ValueName: "NSL Media Player"; ValueType: none; Flags: deletevalue; Tasks: assoc

; --- Audio extensions ---
Root: HKCU; Subkey: "Software\NSL\MediaPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".mp3"; ValueData: "{#ProgId}"; Tasks: assoc
Root: HKCU; Subkey: "Software\NSL\MediaPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".flac"; ValueData: "{#ProgId}"; Tasks: assoc
Root: HKCU; Subkey: "Software\NSL\MediaPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".wav"; ValueData: "{#ProgId}"; Tasks: assoc
Root: HKCU; Subkey: "Software\NSL\MediaPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".m4a"; ValueData: "{#ProgId}"; Tasks: assoc
Root: HKCU; Subkey: "Software\NSL\MediaPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".ogg"; ValueData: "{#ProgId}"; Tasks: assoc
Root: HKCU; Subkey: "Software\NSL\MediaPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".aac"; ValueData: "{#ProgId}"; Tasks: assoc
; --- Video extensions ---
Root: HKCU; Subkey: "Software\NSL\MediaPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".mp4"; ValueData: "{#ProgId}"; Tasks: assoc
Root: HKCU; Subkey: "Software\NSL\MediaPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".mkv"; ValueData: "{#ProgId}"; Tasks: assoc
Root: HKCU; Subkey: "Software\NSL\MediaPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".avi"; ValueData: "{#ProgId}"; Tasks: assoc
Root: HKCU; Subkey: "Software\NSL\MediaPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".mov"; ValueData: "{#ProgId}"; Tasks: assoc
Root: HKCU; Subkey: "Software\NSL\MediaPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".webm"; ValueData: "{#ProgId}"; Tasks: assoc

; --- OpenWithProgids per extension (adds us to "Open with"; does NOT steal the default) ---
Root: HKCU; Subkey: "Software\Classes\.mp3\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue; Tasks: assoc
Root: HKCU; Subkey: "Software\Classes\.flac\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue; Tasks: assoc
Root: HKCU; Subkey: "Software\Classes\.wav\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue; Tasks: assoc
Root: HKCU; Subkey: "Software\Classes\.m4a\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue; Tasks: assoc
Root: HKCU; Subkey: "Software\Classes\.ogg\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue; Tasks: assoc
Root: HKCU; Subkey: "Software\Classes\.aac\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue; Tasks: assoc
Root: HKCU; Subkey: "Software\Classes\.mp4\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue; Tasks: assoc
Root: HKCU; Subkey: "Software\Classes\.mkv\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue; Tasks: assoc
Root: HKCU; Subkey: "Software\Classes\.avi\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue; Tasks: assoc
Root: HKCU; Subkey: "Software\Classes\.mov\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue; Tasks: assoc
Root: HKCU; Subkey: "Software\Classes\.webm\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue; Tasks: assoc

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
