; Prototype — the Windows installer.
;
; WHY THIS EXISTS: the app shipped as a zip of the Flutter runner directory.
; That is not what a Windows user expects to double-click — there is no icon
; to launch, no Start Menu entry, no listing in "Installed apps", and running
; a second build over the first left two unrelated folders wherever the first
; zip happened to be unpacked. This is an Inno Setup script that turns the
; SAME release bundle into a real installer: a custom-drawn wizard carrying
; the app's own mark, a Start Menu shortcut, a desktop shortcut, a proper
; "Installed apps" entry with an Uninstall button Windows itself puts there —
; and, run again over an existing install, an UPDATE rather than a second
; copy: see IsUpgrade below.
;
; THE WIZARD ITSELF IS CUSTOM-DRAWN — see [Code]. Setup no longer shows
; Inno's stock title-barred, multi-page wizard: it is a single borderless,
; rounded, dark card matching the app icon, with exactly three screens
; (Welcome, Installing, Finished) and no decisions to make beyond "Install".
; Every other page Inno normally shows (license, select components, select
; program group, select tasks, ready-to-install) is skipped via
; ShouldSkipPage — their defaults (desktop icon on, default install folder)
; apply automatically, which is what "completely automatic" means here.
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

; No admin prompt, no choice offered either — a zip never asked for one,
; and a single-user CAD tool has no reason to start demanding elevation
; now. PrivilegesRequiredOverridesAllowed is deliberately NOT set: it is
; what draws Setup's own "Install for me only / for all users" picker
; BEFORE the custom wizard below ever gets a chance to run — a second
; stock dialog undermining the same one-click promise ShowLanguageDialog
; further down exists to keep. Anyone who genuinely needs an all-users
; install still has the command-line switches; nobody sees a prompt for it.
PrivilegesRequired=lowest

UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
; THE SELF-UPDATE PATH. The app itself (update_check.dart) can download this
; installer and re-run it silently while it is still running — the user
; already said yes inside the app, so there is nothing left for Setup's own
; wizard to ask. That means prototype.exe is open and its own DLL/asset files
; are locked at the exact moment [Files] needs to overwrite them.
;
; CloseApplications uses the Windows Restart Manager to find which running
; processes hold a lock on a file Setup is about to replace and close them —
; here, that is this app closing itself, a moment after it launched the very
; installer doing the closing. RestartApplications reopens whatever it closed
; once the copy is done, so a silent update also finishes back at a running
; app with no code in update_check.dart telling Setup to relaunch anything.
; Both are complete no-ops when nothing is running against these files, which
; is every OTHER install — a first install, and windows-build.yml's own
; silent smoke test — so this changes nothing for either of those.
CloseApplications=yes
RestartApplications=yes
; The same glyph the taskbar and the window already show — the installer,
; the "Installed apps" entry and the uninstaller all carry it, one logo
; rather than a generic installer-box icon standing in for it.
SetupIconFile=..\runner\resources\app_icon.ico
WizardStyle=modern
; The custom [Code] below replaces the wizard's chrome entirely (see
; InitializeWizard), but WizardStyle stays "modern" as the fallback any
; control this script does not touch — a MsgBox, the UAC prompt text — still
; renders under, and as the base the wizard form is built from before the
; skin is applied.

Compression=lzma2
SolidCompression=yes
OutputDir={#OutputDir}
OutputBaseFilename=prototype-windows-setup
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; One page fewer: nothing on the ready-to-install summary page is a decision
; the wizard has not already made (destination, shortcuts) — Next simply
; starts the copy, which DisableReadyPage does directly instead of via an
; extra click through a page that only restates the last two. ShouldSkipPage
; in [Code] skips it too, belt and suspenders.
DisableReadyPage=yes

; THE OTHER STOCK DIALOG BEFORE THE CUSTOM WIZARD. Two [Languages] entries
; make Setup show its own "Select the language to use during the
; installation" picker before InitializeWizard ever runs — the same kind of
; interruption PrivilegesRequiredOverridesAllowed above was removed for.
; ShowLanguageDialog=no silences it; LanguageDetectionMethod=uilanguage
; (Inno 6's own default, named explicitly so it is not silently relying on
; a default that could change) is what still gets German instead of English
; in front of a German Windows install without asking — matched against
; the OS's own UI language, not guessed.
ShowLanguageDialog=no
LanguageDetectionMethod=uilanguage

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"

; THE CUSTOM WIZARD'S OWN STRINGS, in both languages the stock wizard
; already spoke. {#MyAppName} is expanded by the preprocessor here exactly
; as it is in [Setup] above, so the German strings never go stale against a
; renamed app without this file being touched anyway.
[CustomMessages]
english.InstallerWelcomeFresh=Ready to install.
english.InstallerWelcomeUpgrade=Updates your install. Files and settings stay put.
english.InstallerInstall=Install
english.InstallerChooseLocation=Choose install location
english.InstallerInstalling=Installing {#MyAppName}...
english.InstallerCancel=Cancel
english.InstallerFinishedTitle=You are all set
english.InstallerFinishedSubtitle={#MyAppName} is installed.
english.InstallerLaunch=Launch {#MyAppName}
english.InstallerClose=Close

german.InstallerWelcomeFresh=Bereit zur Installation.
german.InstallerWelcomeUpgrade=Aktualisiert Ihre Installation. Dateien und Einstellungen bleiben erhalten.
german.InstallerInstall=Installieren
german.InstallerChooseLocation=Installationsort wählen
german.InstallerInstalling={#MyAppName} wird installiert...
german.InstallerCancel=Abbrechen
german.InstallerFinishedTitle=Fertig
german.InstallerFinishedSubtitle={#MyAppName} wurde installiert.
german.InstallerLaunch={#MyAppName} starten
german.InstallerClose=Schließen

[Tasks]
; No page ever asks about this now (see ShouldSkipPage) — no "unchecked"
; flag means it stays at Inno's own default of CHECKED, so a desktop
; shortcut simply appears, matching the wizard's one-click promise.
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; The WHOLE release bundle, exactly as `flutter build windows --release`
; and the CI job's own bundle check (windows-build.yml) already validated it
; — every DLL beside prototype.exe, `data\flutter_assets`, all of it. Nothing
; here re-decides what belongs in the app; it packages what was already
; proven to launch.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

; THE WIZARD'S OWN ART, not part of the app. `dontcopy` means these never
; land in {app} — they are pulled into Setup's own temp folder on demand by
; ExtractTemporaryFile in [Code] and read from there while the wizard runs.
Source: "assets\card-bg.bmp"; DestDir: "{tmp}"; Flags: dontcopy
Source: "assets\logo.bmp"; DestDir: "{tmp}"; Flags: dontcopy

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

; The checkbox this used to be tied to is gone from the finished page (it is
; a "Launch"/"Close" pill button pair instead — see SetupFinishedPage), but
; the entry itself is unchanged: LaunchBtnClick/CloseLinkClick in [Code] just
; set WizardForm.RunList.Checked[0] before triggering the same Next click
; Setup's own Finished page would have, so this still runs, or does not, the
; same way it always did.
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Taken out with the app. A rule naming a program that is no longer there is
; harmless and untidy in equal measure, and untidy is the one that gets found.
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""{#MyAppName} (LAN sharing)"""; Flags: runhidden; RunOnceId: "RemoveSharingFirewallRule"; Check: IsAdminInstallMode

; ---------------------------------------------------------------------------
; THE CUSTOM WIZARD.
;
; Inno's stock wizard is a title-barred window with a page-name header, a
; Back/Next/Cancel row, and as many pages as there are decisions to make.
; This app has exactly one decision ("go") and an icon worth building around,
; so the wizard below is a single borderless, rounded 660x420 card skinned to
; match it — three screens (Welcome, Installing, Finished), no title bar, no
; page count. It does not drag: the usual click-the-background trick needs
; TBitmapImage.OnMouseDown (or WizardForm.OnMouseDown, tried as a fallback),
; and neither compiles against Inno's Pascal Script binding — confirmed
; against a real Inno Setup 6.7 compile, not assumed. Centered on screen for
; the whole install instead, which a wizard this short (three screens, no
; typing) does not suffer for.
;
; HOW: the stock WizardForm still exists — its pages, its DirEdit, its
; RunList, its NextButton — this only hides the stock chrome (MainPanel, the
; three navigation buttons, every default label) and lays custom, hand-drawn
; controls over the same page panels, wiring them to the SAME underlying
; controls (SimulateClick(WizardForm.NextButton), WizardForm.DirEdit.Text,
; WizardForm.RunList.Checked[0]) rather than reimplementing what Setup
; already does correctly — see SimulateClick's own comment for why it is a
; simulated Win32 button click and not literally .Click. ShouldSkipPage
; removes every OTHER page from the sequence, so a single Install click
; walks straight from Welcome to Installing to Finished.
;
; SILENT INSTALLS SEE NONE OF THIS. InitializeWizard is called even under
; /SILENT and /VERYSILENT — see the Inno Setup help for that event — and the
; very first line below is `if WizardSilent then Exit`. A scripted deploy
; (this is exactly what windows-build.yml's own installer smoke test does)
; never touches the wizard form at all, so nothing here can be what breaks a
; silent install; it can only be what a person doing this by hand sees.
; ---------------------------------------------------------------------------
[Code]
const
  CRLF = #13#10;

  // The card, in the CSS-pixel-equivalent units ScaleX/ScaleY (Inno's own
  // per-monitor-DPI helpers) convert to real pixels at whatever scaling the
  // screen this runs on is set to. Matches the approved design canvas.
  WinW = 660;
  WinH = 420;
  CardRadius = 20;

  SW_MINIMIZE = 6;
  BM_CLICK = $00F5;

var
  // Set once, from InitializeWizard, before anything is drawn — every
  // drawing routine below reads these rather than hard-coding a color, so
  // the palette lives in exactly one place.
  ClrTextPrimary, ClrTextSecondary, ClrTextTertiary: Integer;
  ClrAccentStart, ClrAccentEnd, ClrBtnText: Integer;
  ClrChromeFill, ClrChromeBorder, ClrChromeIcon: Integer;
  ClrRingTrack, ClrCardEdge: Integer;
  // TBitmap/TBitmapImage.Transparent and .TransparentColor do not compile
  // ("Unknown identifier 'TRANSPARENT'" — confirmed against a real Inno
  // Setup 6.7 compile) on either class, so a hand-drawn shape's bitmap
  // cannot be color-keyed transparent the way a loaded PNG's own alpha
  // channel still renders correctly when just stretched onto the page.
  // Every hand-drawn control below (the chrome dots, the pill buttons,
  // the ring, the badge) fills its small bitmap with this approximation
  // of the card gradient instead, so the square corners GDI's rounding
  // or clipping leaves outside the shape read as background rather than
  // a bright, obviously-wrong box.
  ClrCardApprox: Integer;

  // The progress ring on the Installing page redraws itself as
  // CurInstallProgressChanged fires; both are nil/-1 until that page's
  // controls exist, which CurInstallProgressChanged checks for (silent
  // installs never create RingImg at all).
  RingImg: TBitmapImage;
  LastRingPercent: Integer;

  // The inline "type a different folder" field the Welcome page's "Choose
  // install location" link reveals — see ChooseLocationClick.
  CustomDirEdit: TNewEdit;

// ---------------------------------------------------------------------------
// External Win32 calls. The standard, narrow set skinned-Inno-Setup wizards
// use for a rounded window region, clipping a gradient fill to a rounded
// button shape while it is drawn, minimizing a borderless window, and
// simulating a button click (see SimulateClick — TNewButton.Click itself
// does not compile). None of them touch anything outside the handles this
// script itself creates.
// ---------------------------------------------------------------------------
function CreateRoundRectRgn(X1, Y1, X2, Y2, X3, Y3: Integer): Longint;
  external 'CreateRoundRectRgn@gdi32.dll stdcall';
function SetWindowRgn(hWnd: Longint; hRgn: Longint; bRedraw: Boolean): Integer;
  external 'SetWindowRgn@user32.dll stdcall';
function SelectClipRgn(DC: Longint; hRgn: Longint): Integer;
  external 'SelectClipRgn@gdi32.dll stdcall';
function DeleteObject(hObject: Longint): Boolean;
  external 'DeleteObject@gdi32.dll stdcall';
function SendMessage(hWnd: Longint; Msg, wParam, lParam: Longint): Longint;
  external 'SendMessageA@user32.dll stdcall';
// WizardForm.WindowState := wsMinimized does not compile — Inno's Pascal
// Script binding for TForm does not expose WindowState (confirmed against a
// real Inno Setup 6.7 compile: "Unknown identifier 'WINDOWSTATE'"), even
// though it is an ordinary Delphi TForm property. ShowWindow needs no
// property registration at all, only WizardForm.Handle (which IS exposed
// and used elsewhere in this file for the same reason).
function ShowWindow(hWnd: Longint; nCmdShow: Integer): Boolean;
  external 'ShowWindow@user32.dll stdcall';

// ---------------------------------------------------------------------------
// RECOGNISING AN EXISTING INSTALL.
//
// Inno already does the mechanical half of "update" for free: AppId ties this
// script to whatever an earlier version registered, so running Setup again
// reuses the SAME install directory (UsePreviousAppDir, on by default) and
// [Files]'s ignoreversion simply overwrites what changed — no second copy,
// no leftover old files from a moved install. What is added here is telling
// the PERSON that is what is about to happen — SetupWelcomePage below picks
// between InstallerWelcomeFresh and InstallerWelcomeUpgrade from this.
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Small drawing/layout helpers shared by every page.
// ---------------------------------------------------------------------------

function MakeColor(R, G, B: Byte): Integer;
begin
  Result := R or (G shl 8) or (B shl 16);
end;

function LerpInt(A, B: Integer; T: Extended): Integer;
begin
  Result := A + Round((B - A) * T);
end;

// The global Rect() constructor does not compile ("Unknown identifier
// 'Rect'" — confirmed against a real Inno Setup 6.7 compile) even though
// TCanvas.FillRect and the TRect type it takes both do. Building one field
// by field is the only way left to call FillRect at all.
function MakeRect(X1, Y1, X2, Y2: Integer): TRect;
var
  R: TRect;
begin
  R.Left := X1;
  R.Top := Y1;
  R.Right := X2;
  R.Bottom := Y2;
  Result := R;
end;

// A left-to-right approximation of the design's 135-degree button gradient:
// close enough at pill-button width that the diagonal is not missed, and it
// sidesteps hand-rolling per-pixel diagonal fills in Pascal.
function LerpColor(C1, C2: Integer; T: Extended): Integer;
var
  R1, G1, B1, R2, G2, B2: Integer;
begin
  R1 := C1 and $FF;         G1 := (C1 shr 8) and $FF;  B1 := (C1 shr 16) and $FF;
  R2 := C2 and $FF;         G2 := (C2 shr 8) and $FF;  B2 := (C2 shr 16) and $FF;
  Result := MakeColor(LerpInt(R1, R2, T), LerpInt(G1, G2, T), LerpInt(B1, B2, T));
end;

procedure CenterH(C: TControl; ParentWidth: Integer);
begin
  C.Left := (ParentWidth - C.Width) div 2;
end;

function MakeLabel(AParent: TWinControl; AText: String; AColor: Integer;
  AFontSize: Integer; ABold: Boolean): TNewStaticText;
var
  Lbl: TNewStaticText;
begin
  Lbl := TNewStaticText.Create(AParent);
  Lbl.Parent := AParent;
  Lbl.AutoSize := True;
  Lbl.Caption := AText;
  Lbl.Font.Color := AColor;
  if ABold then
    Lbl.Font.Name := 'Segoe UI Semibold'
  else
    Lbl.Font.Name := 'Segoe UI';
  Lbl.Font.Size := AFontSize;
  Result := Lbl;
end;

// ---------------------------------------------------------------------------
// Event handlers. Every one of these reuses a REAL Setup control
// (NextButton, CancelButton, DirEdit, RunList) rather than reimplementing
// navigation, directory handling or the post-install launch — so the wizard
// looks custom while the install itself runs exactly the code Inno's own
// stock wizard would have run.
// ---------------------------------------------------------------------------

procedure MinimizeClick(Sender: TObject);
begin
  ShowWindow(WizardForm.Handle, SW_MINIMIZE);
end;

procedure CloseClick(Sender: TObject);
begin
  // WizardForm.Close, not a bare halt — this still routes through Setup's
  // own cancel-confirmation dialog if a copy is in progress, same as
  // clicking a real title bar's close box always did.
  WizardForm.Close;
end;

// TNewButton.Click does not compile ("Unknown identifier 'CLICK'" — confirmed
// against a real Inno Setup 6.7 compile) — Click is not part of what Inno's
// Pascal Script binding exposes for it, even though the hidden Back/Next/
// Cancel buttons are real Win32 button controls underneath. BM_CLICK is the
// standard message any such control answers exactly as a mouse click would;
// this is what every custom button below uses to trigger Setup's own
// navigation instead of reimplementing it.
procedure SimulateClick(C: TWinControl);
begin
  SendMessage(C.Handle, BM_CLICK, 0, 0);
end;

procedure InstallBtnClick(Sender: TObject);
begin
  if CustomDirEdit.Visible and (Trim(CustomDirEdit.Text) <> '') then
    WizardForm.DirEdit.Text := CustomDirEdit.Text;
  // wpSelectDir is skipped (ShouldSkipPage), but the control behind it —
  // DirEdit — is still what Setup reads {app} from, whether its own page
  // was ever shown or not. Clicking Next here walks straight through every
  // skipped page to wpInstalling in one step.
  SimulateClick(WizardForm.NextButton);
end;

procedure ChooseLocationClick(Sender: TObject);
begin
  CustomDirEdit.Visible := not CustomDirEdit.Visible;
  if CustomDirEdit.Visible and (Trim(CustomDirEdit.Text) = '') then
    CustomDirEdit.Text := WizardForm.DirEdit.Text;
end;

procedure CancelLinkClick(Sender: TObject);
begin
  SimulateClick(WizardForm.CancelButton);
end;

procedure LaunchBtnClick(Sender: TObject);
begin
  if WizardForm.RunList.Items.Count > 0 then
    WizardForm.RunList.Checked[0] := True;
  SimulateClick(WizardForm.NextButton);
end;

procedure CloseLinkClick(Sender: TObject);
begin
  if WizardForm.RunList.Items.Count > 0 then
    WizardForm.RunList.Checked[0] := False;
  SimulateClick(WizardForm.NextButton);
end;

// ---------------------------------------------------------------------------
// Drawing. Everything below paints onto a TBitmapImage's own Bitmap.Canvas.
// Plain GDI has no alpha blending to lean on and Inno's Pascal Script binding
// exposes neither TBitmap.Transparent/TransparentColor nor a way around them
// (see ClrCardApprox) — the same absence of alpha is why the button gradient
// is a flat left-to-right lerp rather than a true diagonal.
// ---------------------------------------------------------------------------

// The card itself: the dark gradient + soft glow baked into card-bg.bmp at
// 2x resolution (see frontend/windows/installer/assets), stretched to the
// card's logical size so it stays crisp from 100% to 200% display scaling.
// BMP, not PNG: TBitmap.LoadFromFile only reads the BMP signature — handed
// a PNG's bytes it raises "Bitmap image is not valid" (confirmed against
// the classic Delphi VCL behaviour; TBitmapImage's own PNG support for
// WizardImageFile does not extend to a script calling Bitmap.LoadFromFile
// directly). A plain rectangle is enough: the rounded corners are the
// WINDOW's own region (set once, in InitializeWizard), which clips
// whatever the bitmap draws in the corners regardless of the bitmap's own
// shape — nothing here needs to be pre-masked for that to look right.
function LoadCardBackground(AParent: TWinControl): TBitmapImage;
var
  Img: TBitmapImage;
begin
  Img := TBitmapImage.Create(AParent);
  Img.Parent := AParent;
  Img.AutoSize := False;
  Img.Stretch := True;
  Img.Left := 0;
  Img.Top := 0;
  Img.Width := ScaleX(WinW);
  Img.Height := ScaleY(WinH);
  Img.Bitmap.LoadFromFile(ExpandConstant('{tmp}\card-bg.bmp'));
  Img.SendToBack;
  Result := Img;
end;

function MakeChromeCircle(AParent: TWinControl; ALeft, ATop: Integer;
  IsClose: Boolean): TBitmapImage;
var
  Img: TBitmapImage;
  Sz, Cy, Pad: Integer;
begin
  Sz := ScaleX(26);
  Img := TBitmapImage.Create(AParent);
  Img.Parent := AParent;
  Img.AutoSize := False;
  Img.Width := Sz;
  Img.Height := Sz;
  Img.Left := ALeft;
  Img.Top := ATop;
  Img.Bitmap.Width := Sz;
  Img.Bitmap.Height := Sz;

  Img.Bitmap.Canvas.Brush.Color := ClrCardApprox;
  Img.Bitmap.Canvas.FillRect(MakeRect(0, 0, Sz, Sz));

  Img.Bitmap.Canvas.Brush.Color := ClrChromeFill;
  Img.Bitmap.Canvas.Pen.Color := ClrChromeBorder;
  Img.Bitmap.Canvas.Ellipse(0, 0, Sz, Sz);

  Cy := Sz div 2;
  Pad := ScaleX(8);
  Img.Bitmap.Canvas.Pen.Color := ClrChromeIcon;
  if IsClose then
  begin
    Img.Bitmap.Canvas.MoveTo(Pad, Pad);
    Img.Bitmap.Canvas.LineTo(Sz - Pad, Sz - Pad);
    Img.Bitmap.Canvas.MoveTo(Sz - Pad, Pad);
    Img.Bitmap.Canvas.LineTo(Pad, Sz - Pad);
  end
  else
  begin
    Img.Bitmap.Canvas.MoveTo(Pad, Cy);
    Img.Bitmap.Canvas.LineTo(Sz - Pad, Cy);
  end;

  Img.Cursor := crHand;
  Result := Img;
end;

// The two minimize/close dots every page carries top-right — a borderless
// window still needs SOME way to minimize or dismiss it that is not
// Alt-F4, since there is no system title bar left to provide one.
procedure AddChromeButtons(AParent: TWinControl);
var
  MinBtn, CloseBtn: TBitmapImage;
  Sz, Gap, CloseLeft, MinLeft: Integer;
begin
  Sz := ScaleX(26);
  Gap := ScaleX(8);
  CloseLeft := ScaleX(WinW) - ScaleX(16) - Sz;
  MinLeft := CloseLeft - Gap - Sz;

  MinBtn := MakeChromeCircle(AParent, MinLeft, ScaleY(16), False);
  MinBtn.OnClick := @MinimizeClick;
  CloseBtn := MakeChromeCircle(AParent, CloseLeft, ScaleY(16), True);
  CloseBtn.OnClick := @CloseClick;
end;

// The "Install" / "Launch Prototype" pills: a gradient fill clipped to a
// fully-rounded rect (corner ellipse = the button's own height, which is
// what makes it a pill rather than a rounded rectangle) with its label
// drawn on top, all inside one bitmap so it behaves as a single clickable
// control.
function MakePillButton(AParent: TWinControl; AWidth, AHeight: Integer;
  AText: String): TBitmapImage;
var
  Img: TBitmapImage;
  Rgn: Longint;
  X, TW, TH: Integer;
  T: Extended;
begin
  Img := TBitmapImage.Create(AParent);
  Img.Parent := AParent;
  Img.AutoSize := False;
  Img.Width := AWidth;
  Img.Height := AHeight;
  Img.Bitmap.Width := AWidth;
  Img.Bitmap.Height := AHeight;

  Img.Bitmap.Canvas.Brush.Color := ClrCardApprox;
  Img.Bitmap.Canvas.FillRect(MakeRect(0, 0, AWidth, AHeight));

  // Clip to the pill shape before filling, so the gradient stripes below
  // never paint past the rounded outline into the corners.
  Rgn := CreateRoundRectRgn(0, 0, AWidth, AHeight, AHeight, AHeight);
  SelectClipRgn(Img.Bitmap.Canvas.Handle, Rgn);
  for X := 0 to AWidth - 1 do
  begin
    T := X / (AWidth - 1);
    Img.Bitmap.Canvas.Pen.Color := LerpColor(ClrAccentStart, ClrAccentEnd, T);
    Img.Bitmap.Canvas.MoveTo(X, 0);
    Img.Bitmap.Canvas.LineTo(X, AHeight);
  end;
  SelectClipRgn(Img.Bitmap.Canvas.Handle, 0);
  DeleteObject(Rgn);

  Img.Bitmap.Canvas.Brush.Style := bsClear;
  Img.Bitmap.Canvas.Font.Name := 'Segoe UI Semibold';
  Img.Bitmap.Canvas.Font.Size := 11;
  Img.Bitmap.Canvas.Font.Color := ClrBtnText;
  TW := Img.Bitmap.Canvas.TextWidth(AText);
  TH := Img.Bitmap.Canvas.TextHeight(AText);
  Img.Bitmap.Canvas.TextOut((AWidth - TW) div 2, (AHeight - TH) div 2, AText);

  Img.Cursor := crHand;
  Result := Img;
end;

// The Installing page's ring: 48 short radial ticks rather than a single
// swept arc. GDI's Arc() draws counterclockwise in a coordinate system that
// does not visually mean what it sounds like once Y points down (the usual
// MM_TEXT screen mapping), which makes "does the progress sweep the right
// way" a real risk with no Windows machine on hand to check it against.
// Ticks sidestep the question entirely: each one's position comes from sin/
// cos this script controls directly, so "clockwise from the top" is just
// the loop below, not a GDI angle convention taken on faith. It also reads
// as the dashed ring the design called for, rather than a smooth stroke.
procedure DrawRing(Percent: Integer);
var
  Bmp: TBitmap;
  Cx, Cy, R, Len, I, N, Filled: Integer;
  Ang: Extended;
  X1, Y1, X2, Y2: Integer;
  PctText: String;
  TW, TH: Integer;
begin
  if RingImg = nil then Exit;
  Bmp := RingImg.Bitmap;

  Bmp.Canvas.Brush.Color := ClrCardApprox;
  Bmp.Canvas.FillRect(MakeRect(0, 0, Bmp.Width, Bmp.Height));

  Cx := Bmp.Width div 2;
  Cy := Bmp.Height div 2;
  R := (Bmp.Width div 2) - ScaleX(4);
  Len := ScaleX(6);
  N := 48;
  Filled := Round(N * (Percent / 100));

  Bmp.Canvas.Pen.Width := ScaleX(2);
  for I := 0 to N - 1 do
  begin
    Ang := (I / N) * 2 * Pi;
    X1 := Cx + Round((R - Len) * Sin(Ang));
    Y1 := Cy - Round((R - Len) * Cos(Ang));
    X2 := Cx + Round(R * Sin(Ang));
    Y2 := Cy - Round(R * Cos(Ang));
    if I < Filled then
      Bmp.Canvas.Pen.Color := ClrAccentEnd
    else
      Bmp.Canvas.Pen.Color := ClrRingTrack;
    Bmp.Canvas.MoveTo(X1, Y1);
    Bmp.Canvas.LineTo(X2, Y2);
  end;

  Bmp.Canvas.Brush.Style := bsClear;
  Bmp.Canvas.Font.Name := 'Segoe UI Semibold';
  Bmp.Canvas.Font.Size := 17;
  Bmp.Canvas.Font.Color := ClrTextPrimary;
  PctText := IntToStr(Percent) + '%';
  TW := Bmp.Canvas.TextWidth(PctText);
  TH := Bmp.Canvas.TextHeight(PctText);
  Bmp.Canvas.TextOut(Cx - TW div 2, Cy - TH div 2, PctText);

  RingImg.Invalidate;
end;

// The Finished page's small checkmark badge, overlapping the logo's
// bottom-right corner — on-brand orange rather than a generic green check.
procedure DrawBadge(Img: TBitmapImage);
var
  Sz: Integer;
begin
  Sz := Img.Width;
  Img.Bitmap.Width := Sz;
  Img.Bitmap.Height := Sz;

  Img.Bitmap.Canvas.Brush.Color := ClrCardApprox;
  Img.Bitmap.Canvas.FillRect(MakeRect(0, 0, Sz, Sz));

  Img.Bitmap.Canvas.Brush.Color := ClrAccentEnd;
  Img.Bitmap.Canvas.Pen.Color := ClrCardEdge;
  Img.Bitmap.Canvas.Pen.Width := ScaleX(3);
  Img.Bitmap.Canvas.Ellipse(0, 0, Sz, Sz);

  Img.Bitmap.Canvas.Pen.Color := ClrBtnText;
  Img.Bitmap.Canvas.Pen.Width := ScaleX(2);
  Img.Bitmap.Canvas.MoveTo(Round(Sz * 0.24), Round(Sz * 0.52));
  Img.Bitmap.Canvas.LineTo(Round(Sz * 0.42), Round(Sz * 0.70));
  Img.Bitmap.Canvas.LineTo(Round(Sz * 0.78), Round(Sz * 0.30));

end;

// ---------------------------------------------------------------------------
// The three pages. Each grabs its page panel via an existing stock
// control's .Parent (WelcomeLabel1, ProgressGauge, FinishedHeadingLabel —
// all children of the panel Inno already built for that page), hides that
// page's default controls, and lays the custom ones over the same panel.
// Coordinates are hand-placed (there is no layout engine here) but every
// one goes through ScaleX/ScaleY, so the whole card scales correctly on a
// 150%/200% display rather than just the window frame around it.
// ---------------------------------------------------------------------------

procedure SetupWelcomePage;
var
  Page: TWinControl;
  ParentW: Integer;
  Logo: TBitmapImage;
  LogoW, LogoH: Integer;
  Title, Subtitle, ChooseLink: TNewStaticText;
  InstallBtn: TBitmapImage;
begin
  Page := WizardForm.WelcomeLabel1.Parent;
  WizardForm.WelcomeLabel1.Visible := False;
  WizardForm.WelcomeLabel2.Visible := False;
  ParentW := ScaleX(WinW);

  LoadCardBackground(Page);
  AddChromeButtons(Page);

  // logo.bmp is pre-composited (see assets/ generation) onto the exact
  // patch of card-bg it sits over at THIS position — 52x84 logical, top
  // 56 — so it can be a plain opaque BMP with no runtime transparency at
  // all. Both pages that show the logo use this same position for
  // exactly that reason: a different position here would show the wrong
  // slice of gradient behind it.
  LogoH := ScaleY(84);
  LogoW := ScaleX(52);
  Logo := TBitmapImage.Create(Page);
  Logo.Parent := Page;
  Logo.AutoSize := False;
  Logo.Stretch := True;
  Logo.Width := LogoW;
  Logo.Height := LogoH;
  Logo.Top := ScaleY(56);
  Logo.Left := (ParentW - LogoW) div 2;
  Logo.Bitmap.LoadFromFile(ExpandConstant('{tmp}\logo.bmp'));

  Title := MakeLabel(Page, '{#MyAppName}', ClrTextPrimary, 19, True);
  Title.Top := ScaleY(156);
  CenterH(Title, ParentW);

  if IsUpgrade() then
    Subtitle := MakeLabel(Page, CustomMessage('InstallerWelcomeUpgrade'), ClrTextSecondary, 10, False)
  else
    Subtitle := MakeLabel(Page, CustomMessage('InstallerWelcomeFresh'), ClrTextSecondary, 10, False);
  Subtitle.Top := ScaleY(190);
  CenterH(Subtitle, ParentW);

  InstallBtn := MakePillButton(Page, ScaleX(170), ScaleY(46), CustomMessage('InstallerInstall'));
  InstallBtn.Top := ScaleY(232);
  CenterH(InstallBtn, ParentW);
  InstallBtn.OnClick := @InstallBtnClick;

  ChooseLink := MakeLabel(Page, CustomMessage('InstallerChooseLocation'), ClrTextTertiary, 8, False);
  ChooseLink.Top := ScaleY(292);
  ChooseLink.Cursor := crHand;
  CenterH(ChooseLink, ParentW);
  ChooseLink.OnClick := @ChooseLocationClick;

  CustomDirEdit := TNewEdit.Create(Page);
  CustomDirEdit.Parent := Page;
  CustomDirEdit.Width := ScaleX(380);
  CustomDirEdit.Top := ScaleY(316);
  CustomDirEdit.Left := (ParentW - CustomDirEdit.Width) div 2;
  CustomDirEdit.Font.Name := 'Segoe UI';
  CustomDirEdit.Font.Size := 9;
  CustomDirEdit.Text := WizardForm.DirEdit.Text;
  CustomDirEdit.Visible := False;
end;

procedure SetupInstallingPage;
var
  Page: TWinControl;
  ParentW, Sz: Integer;
  StatusLbl, CancelLink: TNewStaticText;
begin
  Page := WizardForm.ProgressGauge.Parent;
  WizardForm.ProgressGauge.Visible := False;
  WizardForm.StatusLabel.Visible := False;
  WizardForm.FilenameLabel.Visible := False;
  ParentW := ScaleX(WinW);

  LoadCardBackground(Page);
  AddChromeButtons(Page);

  Sz := ScaleX(132);
  RingImg := TBitmapImage.Create(Page);
  RingImg.Parent := Page;
  RingImg.AutoSize := False;
  RingImg.Width := Sz;
  RingImg.Height := Sz;
  RingImg.Top := ScaleY(107);
  RingImg.Left := (ParentW - Sz) div 2;
  RingImg.Bitmap.Width := Sz;
  RingImg.Bitmap.Height := Sz;
  LastRingPercent := -1;
  DrawRing(0);

  StatusLbl := MakeLabel(Page, CustomMessage('InstallerInstalling'), ClrTextSecondary, 10, False);
  StatusLbl.Top := ScaleY(263);
  CenterH(StatusLbl, ParentW);

  CancelLink := MakeLabel(Page, CustomMessage('InstallerCancel'), ClrTextTertiary, 8, False);
  CancelLink.Top := ScaleY(297);
  CancelLink.Cursor := crHand;
  CenterH(CancelLink, ParentW);
  CancelLink.OnClick := @CancelLinkClick;
end;

procedure SetupFinishedPage;
var
  Page: TWinControl;
  ParentW: Integer;
  Logo, Badge: TBitmapImage;
  LogoW, LogoH, BadgeSz: Integer;
  Title, Subtitle, CloseLink: TNewStaticText;
  LaunchBtn: TBitmapImage;
begin
  Page := WizardForm.FinishedHeadingLabel.Parent;
  WizardForm.FinishedHeadingLabel.Visible := False;
  WizardForm.FinishedLabel.Visible := False;
  WizardForm.RunList.Visible := False;
  ParentW := ScaleX(WinW);

  LoadCardBackground(Page);
  AddChromeButtons(Page);

  // Same position as the Welcome page's logo, and for the same reason —
  // see the comment there. Using a different Top here would show this
  // page's logo sitting on the wrong slice of the pre-composited gradient.
  LogoH := ScaleY(84);
  LogoW := ScaleX(52);
  Logo := TBitmapImage.Create(Page);
  Logo.Parent := Page;
  Logo.AutoSize := False;
  Logo.Stretch := True;
  Logo.Width := LogoW;
  Logo.Height := LogoH;
  Logo.Top := ScaleY(56);
  Logo.Left := (ParentW - LogoW) div 2;
  Logo.Bitmap.LoadFromFile(ExpandConstant('{tmp}\logo.bmp'));

  BadgeSz := ScaleX(32);
  Badge := TBitmapImage.Create(Page);
  Badge.Parent := Page;
  Badge.AutoSize := False;
  Badge.Width := BadgeSz;
  Badge.Height := BadgeSz;
  Badge.Left := Logo.Left + LogoW - Round(BadgeSz * 0.68);
  Badge.Top := Logo.Top + LogoH - Round(BadgeSz * 0.68);
  DrawBadge(Badge);

  // Shifted up 8 from the original 164/196/230/290 to follow the logo's
  // own 8px move (64 -> 56, see above) — the gaps between them are
  // unchanged, only the whole group's position within the card is.
  Title := MakeLabel(Page, CustomMessage('InstallerFinishedTitle'), ClrTextPrimary, 17, True);
  Title.Top := ScaleY(156);
  CenterH(Title, ParentW);

  Subtitle := MakeLabel(Page, CustomMessage('InstallerFinishedSubtitle'), ClrTextSecondary, 10, False);
  Subtitle.Top := ScaleY(188);
  CenterH(Subtitle, ParentW);

  LaunchBtn := MakePillButton(Page, ScaleX(200), ScaleY(46), CustomMessage('InstallerLaunch'));
  LaunchBtn.Top := ScaleY(222);
  CenterH(LaunchBtn, ParentW);
  LaunchBtn.OnClick := @LaunchBtnClick;

  CloseLink := MakeLabel(Page, CustomMessage('InstallerClose'), ClrTextTertiary, 8, False);
  CloseLink.Top := ScaleY(282);
  CloseLink.Cursor := crHand;
  CenterH(CloseLink, ParentW);
  CloseLink.OnClick := @CloseLinkClick;
end;

procedure InitializeWizard();
var
  Rgn: Longint;
begin
  // See the header comment above [Code]: a scripted/silent install must
  // come out byte-for-byte the same as before this wizard existed, so
  // nothing past this line ever runs for one.
  if WizardSilent then Exit;

  ClrTextPrimary   := MakeColor(246, 244, 241);
  ClrTextSecondary := MakeColor(150, 148, 145);
  ClrTextTertiary  := MakeColor(120, 118, 116);
  ClrAccentStart   := MakeColor(255, 106, 56);
  ClrAccentEnd     := MakeColor(224, 67, 26);
  ClrBtnText       := MakeColor(26, 14, 8);
  ClrChromeFill    := MakeColor(41, 39, 45);
  ClrChromeBorder  := MakeColor(58, 56, 62);
  ClrChromeIcon    := MakeColor(205, 203, 200);
  ClrRingTrack     := MakeColor(64, 61, 68);
  ClrCardEdge      := MakeColor(23, 21, 27);
  ClrCardApprox    := MakeColor(27, 23, 22);

  ExtractTemporaryFile('card-bg.bmp');
  ExtractTemporaryFile('logo.bmp');

  WizardForm.BorderStyle := bsNone;
  WizardForm.ClientWidth := ScaleX(WinW);
  WizardForm.ClientHeight := ScaleY(WinH);
  WizardForm.Position := poScreenCenter;

  WizardForm.MainPanel.Visible := False;
  WizardForm.NextButton.Visible := False;
  WizardForm.BackButton.Visible := False;
  WizardForm.CancelButton.Visible := False;
  // The stock wizard's page area does not start at (0,0) — it leaves room
  // above for MainPanel's header and below for the button row, both now
  // hidden. Stretching it to the full client area is what makes the custom
  // background actually reach every edge instead of leaving a stock-colored
  // margin around it.
  WizardForm.InnerNotebook.SetBounds(0, 0, WizardForm.ClientWidth, WizardForm.ClientHeight);

  // The window's own shape: a rounded rect matching the background bitmap's
  // baked-in corners (CardRadius, both in the same ScaleX/ScaleY units), so
  // Windows itself treats the area outside it as outside the window rather
  // than painting square corners the desktop shows through as black.
  Rgn := CreateRoundRectRgn(0, 0, ScaleX(WinW), ScaleY(WinH),
    ScaleX(CardRadius * 2), ScaleY(CardRadius * 2));
  SetWindowRgn(WizardForm.Handle, Rgn, True);

  SetupWelcomePage;
  SetupInstallingPage;
  SetupFinishedPage;
end;

procedure CurInstallProgressChanged(CurProgress, MaxProgress: Integer);
var
  Pct: Integer;
begin
  if RingImg = nil then Exit;
  if MaxProgress <= 0 then
    Pct := 0
  else
    Pct := (CurProgress * 100) div MaxProgress;
  if Pct <> LastRingPercent then
  begin
    DrawRing(Pct);
    LastRingPercent := Pct;
  end;
end;

// Every OTHER page Inno would normally show — license, select components,
// select program group, select tasks, ready-to-install — is skipped, which
// is what makes this a one-click install: their defaults (the default
// folder DirEdit already holds, the desktop-icon task's default-checked
// state) simply apply. wpPreparing is deliberately left off this list: it
// runs Setup's own pre-install checks (disk space and the like) and should
// keep doing whatever it would otherwise do, styled or not.
function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID <> wpWelcome) and (PageID <> wpPreparing) and
    (PageID <> wpInstalling) and (PageID <> wpFinished);
end;
