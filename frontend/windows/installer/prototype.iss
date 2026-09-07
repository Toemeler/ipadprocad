; Prototype — the Windows installer.
;
; WHY THIS EXISTS: the app shipped as a zip of the Flutter runner directory.
; That is not what a Windows user expects to double-click — there is no icon
; to launch, no Start Menu entry, no listing in "Installed apps", and running
; a second build over the first left two unrelated folders wherever the first
; zip happened to be unpacked. This is an Inno Setup script that turns the
; SAME release bundle into a real installer: a wizard with the app's own
; icon, a Start Menu shortcut, an optional desktop shortcut, a proper
; "Installed apps" entry with an Uninstall button Windows itself puts there —
; and, run again over an existing install, an UPDATE rather than a second
; copy: see IsUpgrade below.
;
; THE VERSION AND THE SOURCE BUNDLE ARE NOT HERE. windows-build.yml passes
; them on the command line —
;
;   iscc /DMyAppVersion=1.0.123 /DSourceDir=C:\...\Release
;        /DOutputDir=C:\...\dist frontend\windows\installer\prototype.iss
;
; — so this script never has to be edited for a release, and a developer
; building locally gets sane defaults (see the #ifndef block) without having
; to pass anything at all: `iscc prototype.iss` after a `flutter build
; windows --release` just works.
;
; THE APPID MUST NEVER CHANGE. It is what lets Setup recognise "this machine
; already has a Prototype" across every future version — change it and every
; user's next install becomes a second, unrelated copy sitting beside the
; first, which is the exact bug this file exists to not have.
#define MyAppName "Prototype"
#define MyAppExeName "prototype.exe"
#define MyAppPublisher "com.prototype"
#define MyAppURL "https://github.com/toemeler/ipadprocad"

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
; Defaults match `flutter build windows --release`'s own output directory,
; run from this file's own location.
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\..\dist"
#endif

[Setup]
AppId={{950E1824-23C2-43EF-AC2B-95E959CD7038}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
VersionInfoVersion={#MyAppVersion}

; {autopf}/{autodesktop}/{group} all adapt to whichever mode Setup actually
; runs in — see PrivilegesRequired below — so nothing here has to branch on
; that itself.
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
; One app, one shortcut folder; asking where to put it is a page nobody
; needs to see twice.
DisableProgramGroupPage=yes
DisableWelcomePage=no

; No admin prompt by default — a zip never asked for one either, and a
; single-user CAD tool has no reason to start demanding elevation now.
; `dialog` still lets someone choose an all-users install from Setup's own
; elevation prompt, for the one machine that wants it shared.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
; The same glyph the taskbar and the window already show — the installer,
; the "Installed apps" entry and the uninstaller all carry it, one logo
; rather than a generic installer-box icon standing in for it.
SetupIconFile=..\runner\resources\app_icon.ico
WizardStyle=modern

Compression=lzma2
SolidCompression=yes
OutputDir={#OutputDir}
OutputBaseFilename=prototype-windows-setup
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; One page fewer: nothing on the ready-to-install summary page is a decision
; the wizard has not already made (destination, shortcuts) — Next simply
; starts the copy, which DisableReadyPage does directly instead of via an
; extra click through a page that only restates the last two.
DisableReadyPage=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; The WHOLE release bundle, exactly as `flutter build windows --release`
; and the CI job's own bundle check (windows-build.yml) already validated it
; — every DLL beside prototype.exe, `data\flutter_assets`, all of it. Nothing
; here re-decides what belongs in the app; it packages what was already
; proven to launch.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; ---------------------------------------------------------------------------
; THE FIREWALL HOLE, WHERE THIS INSTALL IS ALLOWED TO MAKE ONE.
;
; Sharing a code means LISTENING: a TCP port for the mirror and UDP for
; discovery. Windows Defender Firewall blocks an inbound connection to a
; program it has no rule for, and what a person sees when that happens is not
; an error — it is two devices a metre apart, both saying "looking", for ever.
; (The pop-up that would normally ask needs an administrator to answer, so on
; a standard account the block is the whole of the interaction.)
;
; `program=` rather than a port list on purpose: the mirror takes the first
; free port from 47821 upward, so a rule naming one port would come apart the
; day somebody runs two copies. A rule naming the executable covers whatever
; it binds, and covers only this program.
;
; PROFILE=ANY, INCLUDING PUBLIC, and that is a decision rather than an
; oversight. Windows asks once whether a network is private and files it as
; PUBLIC whenever the answer was no or nobody answered — which is a great many
; ordinary home networks. Limiting the rule to `private` would mean sharing
; works or does not according to something the user answered once, months ago,
; in a dialog they do not remember. What is actually exposed is a listener
; that exists only while sharing is switched on, and that hands nothing to a
; peer which cannot answer a nonce with a key derived from the share code.
;
; The delete before the add is what stops a re-install stacking duplicates.
;
; ONLY WHEN ELEVATED. netsh needs an administrator, and this installer asks
; for one only if the person chose an all-users install (PrivilegesRequired=
; lowest, above — a deliberate choice this does not undo for a firewall rule).
; On a per-user install Windows falls back to asking at the first bind, and
; discovery is built to survive the answer being no: the app asks for its mDNS
; replies UNICAST, which the firewall lets back in as a response to the app's
; own outbound query even with no rule at all. See mdns.dart.
; ---------------------------------------------------------------------------
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""{#MyAppName} (LAN sharing)"""; Flags: runhidden; Check: IsAdminInstallMode; StatusMsg: "Allowing {#MyAppName} through the firewall..."
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""{#MyAppName} (LAN sharing)"" dir=in action=allow program=""{app}\{#MyAppExeName}"" enable=yes profile=any"; Flags: runhidden; Check: IsAdminInstallMode; StatusMsg: "Allowing {#MyAppName} through the firewall..."

Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Taken out with the app. A rule naming a program that is no longer there is
; harmless and untidy in equal measure, and untidy is the one that gets found.
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""{#MyAppName} (LAN sharing)"""; Flags: runhidden; RunOnceId: "RemoveSharingFirewallRule"; Check: IsAdminInstallMode

; ---------------------------------------------------------------------------
; RECOGNISING AN EXISTING INSTALL.
;
; Inno already does the mechanical half of "update" for free: AppId ties this
; script to whatever an earlier version registered, so running Setup again
; reuses the SAME install directory (UsePreviousAppDir, on by default) and
; [Files]'s ignoreversion simply overwrites what changed — no second copy,
; no leftover old files from a moved install. What is added here is telling
; the PERSON that is what is about to happen, which the stock wizard does
; not do on its own: the welcome page says "This will install..." whether or
; not anything is already there.
; ---------------------------------------------------------------------------
[Code]
const
  // A LINE MAY NOT BEGIN WITH '#'. The Inno preprocessor reads the first
  // non-space character of every line, [Code] included, and takes '#' as the
  // start of a directive — so a continuation line beginning `#13#10 + ...`
  // is read as an unknown directive named `13` and the compile aborts before
  // Pascal ever sees it. Mid-line it is fine, which is why only one of the
  // four line breaks in InitializeWizard's caption below was the fault.
  // Naming it removes the trap rather than tiptoeing around it.
  CRLF = #13#10;

function GetUninstallString(): String;
var
  key: String;
  fromUser, fromMachine: String;
begin
  // The literal GUID, not a reference to [Setup]'s AppId= line: that line
  // writes it through Inno's OWN "{{" escape (so the registered key is
  // "{950E...}", one brace), and a Pascal string literal here needs the
  // already-unescaped form directly. THIS GUID AND [Setup]'s MUST MATCH —
  // both change together, or never.
  key := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\' +
    '{950E1824-23C2-43EF-AC2B-95E959CD7038}_is1';
  // Two keys, not one: HKCU is where a PER-USER install registers
  // (PrivilegesRequired=lowest writes HKCU regardless of OS bitness), HKLM
  // is where an all-users install does — GetUninstallString has to find
  // whichever kind is already on this machine.
  fromUser := '';
  fromMachine := '';
  RegQueryStringValue(HKCU, key, 'UninstallString', fromUser);
  RegQueryStringValue(HKLM, key, 'UninstallString', fromMachine);
  if fromUser <> '' then
    Result := fromUser
  else
    Result := fromMachine;
end;

function IsUpgrade(): Boolean;
begin
  Result := (GetUninstallString() <> '');
end;

procedure InitializeWizard();
begin
  if IsUpgrade() then
  begin
    WizardForm.WelcomeLabel2.Caption :=
      'An earlier version of {#MyAppName} is already installed on this ' +
      'computer.' + CRLF + CRLF +
      'Click Next to update it to version {#MyAppVersion} - your ' +
      'documents and settings are not touched, only the app itself.' +
      CRLF + CRLF +
      'To remove {#MyAppName} instead, close this window and use ' +
      '"Uninstall {#MyAppName}" from the Start Menu, or "Installed apps" ' +
      'in Windows Settings.';
  end;
end;
