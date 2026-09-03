# Prototype on Linux

The same app, on a desktop. Not a port in the sense of a second codebase: one
Dart tree, one set of kernels, one design, with the handful of places that can
only be answered by a platform answered twice.

This file is for two people. The first wants to build and run it. The second is
about to merge a week of iOS work from `main` and needs to know what, if
anything, that costs on this side. The short answer to the second question is
*almost nothing, by construction*, and the rest of this file is why.

---

## Build it

```bash
sudo apt-get install -y \
  clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
  libstdc++-12-dev zenity \
  g++ qt6-base-dev qt6-declarative-dev qt6-svg-dev

# The CAD kernels. Once, then forget: ~40 minutes, almost all of it OCCT.
tools/desktop/build_native.sh

# The app.
cd frontend && flutter build linux --release
./build/linux/x64/release/bundle/prototype
```

A distributable tarball, an AppImage, and a per-user `install.sh` that
registers the icon, the `.desktop` entry and the `.ptp`/`.pts`/`.pas` file
associations:

```bash
tools/desktop/package_linux.sh --appimage
```

**In a hurry, or only touching UI?** Skip the kernels:

```bash
tools/desktop/build_native.sh --no-occt   # 2D + solver in a few minutes
cd frontend && flutter run -d linux       # or skip build_native.sh entirely
```

Without kernels the app runs on the Dart drawing engine and the Dart solver,
with no 3D and no path tracing — exactly what `flutter run` on any host has
always done. It says so in the log rather than pretending; see
`frontend/lib/ffi/native_lib.dart`.

---

## What runs where

| | iPad | Linux |
|---|---|---|
| UI, layout, tools, gestures, i18n | Flutter | **the same Flutter** |
| 2D geometry, layers, DXF | QCAD core, statically linked | QCAD core, in `libprototype_native.so` |
| Constraints, DOF | libslvs, statically linked | libslvs, same library |
| 3D B-Rep, booleans, STEP, meshes | OCCT, statically linked | OCCT, same library |
| Ribbon, model browser, tab bar, tool bar | UIKit glass (`native_menu`) | **the same material, drawn by a shader** |
| Alerts, action sheets, Settings | UIKit | the app's own Cupertino surfaces |
| Context menus | `UIContextMenuInteraction` | the app's own overlay menu |
| Save a copy / Open / Open with | Files, share sheet | GTK choosers (`native_menu/linux`) |
| Shaded 3D viewport | RealityKit platform view | the Dart CPU renderer |
| Path-traced render | Cycles (Metal) | **not yet** — see below |

Two of those rows deserve their reason spelled out, because they are the
decisions the whole port rests on.

### The Liquid Glass is real

The four chrome surfaces on the iPad are a `UIGlassEffect` — the system
material, with its own refraction, specular edge and response to what is
behind it. That is not decoration here: the app's LAYOUT is built around it.
The document runs edge to edge underneath the ribbon band precisely so the
material has something to refract, the model browser floats over the model as
a card rather than taking a column beside it, and the tab bar is three
floating glass groups over the canvas rather than a strip under it. `RibbonSurface` says why in one line
— *"glass with nothing to refract is a lie about the surface, not a cheaper
version of it"* — and every one of those layout choices is switched on the
same question: is this surface glass?

So a desktop build that answered "no glass" was a different app in three ways
at once, not one. It now answers yes:

- **`frontend/packages/native_menu/shaders/liquid_glass.frag`** — the material.
  A signed-distance field of the same rounded superellipse the app clips with,
  a circular bevel profile whose slope turns over at the rim, displacement
  along the surface normal with per-channel offsets for dispersion, the
  shadow-lifting tint, and the two rim hairlines.
- **`frontend/packages/native_menu/lib/liquid_glass.dart`** — what drives it:
  the program, the styles, and a render object that hands the shader the
  panel's rectangle in the backdrop's own pixel space.

It needs `ImageFilter.shader`, which needs Impeller — which is the Linux
desktop default. Where it is missing (the Skia backend, and the `flutter_test`
host, which is why the suite still exercises the painted panels) the app keeps
the surfaces it always had.

**It was fitted to the device, not to taste.** Every number in
`LiquidGlassStyle.dark` was measured off an iPad screenshot:

| | device | this |
|---|---|---|
| the app's ground under the panel | 31,28,24 → **58,55,50** | → **59,56,51** |
| specular, across the top edge | 98, 66, 63.5, 61.5, 60, 59 | 96, 68, 65, 62, 60, 59 |
| the shaded edge, before its hairline | +6 | +5 |

The tint is the part worth knowing about, because the obvious implementation
gets it backwards. It is not an alpha blend toward a dark colour — that pulls
everything toward the tint and turns a bright render behind the panel to mud.
It is a **screen, damped by how bright the backdrop already is**: it opens the
shadows by about +0.11 and leaves the highlights within a couple of levels of
where they were. That is what makes text legible over anything while the model
stays readable through the panel.

**Cost, and the switch.** The material is two backdrop passes per surface (a
gaussian, then the shader — they cannot be one `ImageFilter.compose`, which
changes the input bounds and breaks the shader's sampler; the source says so
where it matters). Measured in this repo's own perf log, orbiting a part with
six glass surfaces up: raster **384 ms** with the material against **58 ms**
without. That number is from a container with NO GPU at all — llvmpipe, a
debug build — so it is an upper bound and not a hardware figure; what it does
say is that the material is the dominant term when there is nothing to run it
on. `PROTOTYPE_GLASS=0` in the environment (or `--dart-define=PROTOTYPE_GLASS=0`
at build time) turns it off and returns the painted panels, for a VM, a remote
desktop or an old integrated chip.

### The rest of the chrome is Flutter's, on purpose

It would have been possible to write GTK versions of the ribbon, the
outline-view model browser and the tab bar. That would have produced a *GTK
app that resembles this one*, which is the opposite of the goal. What is
already in the tree is better: every one of those surfaces has a Flutter
implementation written by the same hand, in the same design system, that the
app falls back to whenever `Platform.isIOS` is false. `flutter test`'s 3 500
cases have been exercising exactly that path since long before there was a
Linux build. So the desktop runs the app's own drawing of the app — on the
app's own material — and there is no third design to keep in step.

`NativeMenu.isSupported` is the switch for the UIKit surfaces, and it stays
`false` here. `GlassPanel.isSupported` is the switch for the MATERIAL, and
that one is true.

### The file errands are the platform's, on purpose

The other half of the same plugin is not a design surface at all: it is *put
this file where the user says*, *give me a file to open*, *open this in
another program*. Drawing our own Save dialog would throw away the recent
places, the bookmarks, the network mounts and the muscle memory that the
desktop's own chooser has and no widget can reproduce.

So the plugin's Dart API has two gates, not one:

```dart
NativeMenu.isSupported      // the UIKit SURFACES  — iOS only
NativeMenu.hasFileSurfaces  // the file ERRANDS    — iOS, Linux, Windows, macOS
```

`frontend/packages/native_menu/linux/native_menu_plugin.cc` implements the
second set and deliberately answers `not implemented` to the first, so that a
mistake in either direction fails loudly rather than producing half a screen.

---

## Where the platform-specific code lives

Everything Linux-only is in paths that **do not exist on `main`**. That is not
tidiness; it is the merge strategy. A directory `main` has never heard of
cannot conflict with anything `main` does.

```
frontend/linux/                       the GTK runner, packaging, icons
frontend/packages/native_menu/linux/  the GTK half of the plugin
backend/desktop/                      the kernel superbuild + its smoke test
tools/desktop/                        build + package scripts
.github/workflows/linux-build.yml     CI
LINUX.md                              this file
```

Shared code that had to change at all is listed in full below. It is fourteen
places, and every one of them is small, load-bearing and unlikely to move.

---

## The fourteen touches in shared code

Read this list before merging from `main`. If a merge conflicts, it will be in
one of these.

1. **`frontend/lib/ffi/native_lib.dart`** — new file. Where a
   `DynamicLibrary` comes from on each platform.
2. **`frontend/lib/ffi/{qcad,slvs,occt,cycles}_engine.dart`** — four lines.
   `DynamicLibrary.process()` became `NativeLib.open(...)`, plus a null check.
   On iOS `NativeLib.open` *is* `DynamicLibrary.process()`, so the iOS
   behaviour is byte-for-byte what it was.
3. **`frontend/lib/platform/desktop_launch.dart`** — new file. The document a
   launch was asked to open (`Exec=prototype %f`).
4. **`frontend/lib/main.dart`** — two additions. `main()` takes optional args
   and records them; the post-`init` callback opens a launch document. Both
   are no-ops on iOS, where nothing passes arguments.
5. **`frontend/lib/widgets/context_menu.dart`** — new file. The Flutter
   stand-in for a UIKit context menu, driven by the same
   `List<List<NativeMenuItem>>` the native path is handed.
6. **`frontend/lib/widgets/home_view.dart`** — a gallery card gains a
   right-click / long-press context menu **off iOS only**, funnelling into the
   existing `_onMenuSelection`. On iOS the callback is null and the UIKit
   interaction owns the gesture, exactly as before. One further line: the
   `FilePicker` fallback now triggers on `!hasFileSurfaces` rather than
   `!isSupported`, so cancelling the GTK chooser does not open a second one.
7. **`frontend/packages/native_menu/lib/native_menu.dart`** — the
   `hasFileSurfaces` gate described above, and six methods moved onto it.
8. **`frontend/packages/native_menu/pubspec.yaml`** — declares the `linux`
   plugin class next to the `ios` one.
9. **`frontend/lib/ffi/*` imports** — one `import 'native_lib.dart';` each.
10. **`frontend/lib/platform/app_dirs.dart`** — new file. Where the app keeps
    its own files on a desktop. Called from `app_state.dart` (one ternary),
    `log.dart` and `perf.dart` (one branch each, replacing the `isMacOS` half
    of a condition that was only ever right about iOS). See below for why this
    is not cosmetic.
11. **`frontend/lib/platform/desktop_shell.dart`** — new file. The window-close
    handshake. `main.dart` registers it in one line; the callback is the same
    `_LogFlusher` the lifecycle events already use.
12. **`frontend/pubspec.yaml` + `theme.dart`** — the bundled UI typeface. The
    pubspec declares it; `T.fontFamily` returns it only on a desktop and
    `null` on iOS, so the iPad's typography is exactly what it was.
13. **The glass gates.** Seven `if`s that used to ask "is there a UIKit
    platform view here" now ask "is this surface glass" — `GlassPanel`
    instead of `GlassBrowser` / `GlassTabBar`. In `main.dart` (four: the
    browser's column vs its floating card, the tab bar's row vs its pill),
    `viewport3d.dart` and `viewport_assembly.dart` (the triad steps aside for
    the card), and `bottom_tabbar.dart` (`floatingHeight`). Each of them was
    already written against the right question and answered with the wrong
    predicate — the source comments say "off iOS there is no floating card",
    which stopped being true. **iOS is unaffected: on the iPad both
    predicates are true.**
14. **`model_browser.dart`, `bottom_tabbar.dart`, `quick_tools.dart`,
    `home_view.dart`** — the four Flutter chrome surfaces put themselves on
    the material when there is one: the browser becomes the iPad's inset,
    18 pt, shadowed card, the tab bar becomes the bar's three glass groups,
    the tool rail and the gallery's two round buttons get a glass plate
    instead of a painted one.
15. **The chrome the material was holding up** (M368). Putting the Flutter
    panels on glass was not the same as making them the iPad's panels, and
    side by side with the device three things were plainly missing:

    * **The browser card had a "Modell ✕" tab strip across its top.** The
      iPad's card has never had one — the tree starts at the document's own
      root row and the bar along the bottom says which document is open. It
      is still drawn on the OPAQUE fallback, which is a wall beside the
      viewport with nothing else on it.
    * **The card did not retract.** On the iPad it is retracted by default
      (M242) and one tap on the chevron brings the labels back.
      `native_browser_host.dart` already owned all of that — the state, the
      280 ms morph, the chevron beside the rows, the occupancy the triad
      follows — for the platform view; the only thing that branches now is
      what renders inside the card's bounds. `ModelBrowser` gained
      `collapsed` and an `onMetrics` callback reporting the same three
      numbers `GlassBrowserView` sends over its `metrics` channel.
    * **The tab bar was one pill**, house inside it and nothing on the
      right, which is the M260 slab again only smaller. It is three glass
      groups now, exactly as `GlassTabBar.swift` builds them — the house,
      the documents capsule, and the `list.bullet` island that lists every
      open document — with M265's fold (at rest, only the document you are
      in) and every constant taken from `GlassTabBarView`.

    Along the way the tree picked up M361's folder gaps and M129's boxed
    disclosure, and the card's own width was corrected from 264 to 250: 264
    is the PANEL, and `GlassBrowserView` insets its glass 14 pt inside it.
16. **`kRibbonDockDefault` is `left`** (was `top`). The screen is landscape
    and so is the document, so a full-width band across the top costs the
    model the scarcest dimension it has; docked left the band is a column of
    glyphs and the browser, the tab bar and the ribbon all float on one
    shared 14 pt margin. Still a stored preference — all four edges work.
    **This one is NOT desktop-only: it changes where a fresh iPad install
    starts too**, which is deliberate, because the two platforms are meant
    to be the same app.

Nothing else in `frontend/lib` knows this platform exists.

### Known differences that are NOT bugs

The Flutter tree and the UIKit tree are two renderers of one document, not
one renderer twice, and two of their differences are structural rather than
oversights:

* **Folder glyphs are ink, not gold.** `icon_theme.dart` clamps every
  chromatic stop to L ∈ [0.16, 0.46] on a light palette — "a colour that
  reads on charcoal is invisible on paper" — so the amber folder comes out
  dark. UIKit's tree tints `folder.fill` with its own `folderAmber` and
  never passes through that mapping. Special-casing one glyph would make it
  the only icon in the set that ignores the palette.
* **No `E2` / `R1` badges on the rows.** M361's badges are drawn by
  `GlassBrowserView.badged`, compositing text onto an SF Symbol. The Flutter
  tree draws its own artwork and has no equivalent; retracted, its rows lean
  on the dwell tooltip instead.

---

## Merging from `main`

```bash
git checkout claude/linux-app-port-tcdtrl
git fetch origin && git merge origin/main
```

Expect it to be clean. If it is not, the conflict is in one of the fourteen
touches above, and every one of them is a small edit whose *reason* is written
next to it in the source — resolve by keeping `main`'s change and re-applying
the touch, never the other way round.

Then, in order of what each one actually proves:

```bash
cd frontend
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
flutter test                        # ~3 500 cases, all platform-neutral
flutter build linux --release
DISPLAY=:0 ./build/linux/x64/release/bundle/prototype
```

The CI job does the same and adds one thing worth copying if you are checking
by hand: it greps the app's **own log** for `REAL backend active (qcad-ffi)`
and `DART SMOKE: PASS`. A bundle that quietly fell back to the Dart engine
looks and behaves identically until the first extrude, and that grep is what
catches it.

### The bundle has to run on a machine that has never had Qt

This is the one thing the build machine cannot tell you, and it cost four red
CI runs. `ldd` succeeds on the machine that just built against Qt for the one
reason that proves nothing: Qt's own dependencies are installed on it. Two
separate mistakes hid behind that.

**What travels.** `build_native.sh` collected `libQt6*` and nothing else, on
the premise that everything Qt pulls in is "base-system furniture on any
desktop that can run a GTK app". It is not: `libmd4c`, `libdouble-conversion`,
`libpcre2-16` (GTK brings the 8-bit one), `libb2`, ICU and `libproxy` arrive as
dependencies OF QT and of nothing else. So the rule is the closure MINUS a
denylist — the loader and libc, the graphics stack, and GTK's own libraries —
rather than an allowlist of one name, and the script now FAILS if any shipping
library needs something that is neither bundled nor in one of those three
families.

**How it is found.** Even complete, it did not resolve: modern binutils emits
`DT_RUNPATH`, which applies only to the object carrying it, so `$ORIGIN` found
`libQt6Core.so.6` and then Qt Core's own dependencies were looked up in the
system paths alone. `DT_RPATH` is inherited down the chain;
`-Wl,--disable-new-dtags` in `backend/desktop/CMakeLists.txt` is what asks for
it. Debian's Qt libraries carry no runpath of their own — they are built to be
found by `ldconfig` — so the tag on the object the app dlopens is the only one
in the chain.

To check by hand what CI checks for you, move the Qt-only sonames out of
`/usr/lib/x86_64-linux-gnu`, run `ldconfig`, launch the bundle, and put them
back. If the log still says `REAL backend active`, the bundle is self-contained.

The tail is why `deps/` is ~75 MB rather than ~20: `libQt6Network` needs
`libproxy`, which needs its backend, which needs libcurl, which needs gnutls,
openssl, ldap and ssh. The app never opens a socket — the QCAD core links Qt
Network and never calls it — but `DT_NEEDED` is resolved at LOAD time. Cutting
it means dropping Qt Network from what the kernel links, not changing anything
in packaging.

### What a new iOS feature costs here

- **A new tool, dialog, ribbon entry, kernel call, document format** — nothing.
  It is shared Dart, and it works here the moment it works there.
- **A new `native_menu` method** — decide which gate it is behind. A *surface*
  needs a Flutter fallback in the app (which is where the iOS code already
  puts one). An *errand* needs a case in `native_menu_plugin.cc`.
- **A new C-API symbol** — nothing, as long as it starts `qcad_`, `slvs_` or
  `occt_`. `backend/desktop/prototype_native.map` exports by prefix. A new
  *prefix* means editing that file, and `backend/desktop/smoke.c` is what
  notices if you forget.
- **A new Flutter plugin dependency** — check it has a Linux implementation.
  `file_picker` does (it shells out to `zenity`, which is why the packaging
  lists it).

---

## Not yet: the path tracer

Rendered mode has two engines on the iPad. RealityKit draws every frame on the
GPU; Cycles path-traces one image when the camera settles. On Linux the first
is replaced by the Dart CPU renderer, which is the app's own long-standing
fallback and is genuinely fast enough on a desktop CPU. The second is simply
absent: `RenderEngines` still offers the choice, `CyclesFfi.instance` returns
null, and the app reports "no path tracer" rather than pretending.

Making it real is a self-contained job, and the seam for it already exists —
`NativeLib.cycles` looks for a *separate* `libprototype_cycles.so`, so nothing
about the kernels or the bundle has to change to add it:

1. Clone Blender's tree at the pin in `.github/workflows/cycles-render-test.yml`
   and fetch `lib/linux_x64` with `make_update.py`.
2. Graft the shim in as that workflow does
   (`backend/cycles/shim/append.cmake`). The macOS/iOS patches in
   `backend/cycles/patches/` are Apple-specific and are not needed.
3. Build `cycles_shim` plus the Cycles device targets into
   `libprototype_cycles.so` and drop it in `frontend/build/native/`.
   `frontend/linux/CMakeLists.txt` already bundles it if it is there.

The device backend on Linux is CPU, CUDA/OptiX or HIP rather than Metal, which
is a Cycles configuration question and touches nothing in this app.

---

## Windows next

The port was shaped for it. Everything above that says *desktop* rather than
*Linux* is already shared, and `NativeMenu.hasFileSurfaces` already includes
Windows. What a Windows build needs:

1. **`frontend/windows/`** — `flutter create --platforms=windows` into a
   scratch project and copy the runner, then apply the same three changes
   `frontend/linux/runner/my_application.cc` documents: the window title and
   the iPad-sized default, F11 fullscreen, and argv reaching Dart. The
   kernel-bundling block at the end of `frontend/linux/CMakeLists.txt` ports
   almost verbatim.
2. **`frontend/packages/native_menu/windows/`** — the same six methods against
   `IFileDialog` (Save a copy, Open), `ShellExecute` (Open with),
   `TaskDialogIndirect` (the mesh-import question) and
   `GetProcessMemoryInfo`/`GlobalMemoryStatusEx` (the perf probe). The Linux
   file is 460 lines including its reasoning; the Windows one will be similar.
   Add `windows: pluginClass:` to the plugin's `pubspec.yaml`.
3. **The kernels** — `backend/desktop/CMakeLists.txt` is where the two
   MSVC-specific facts go: `--whole-archive` becomes `/WHOLEARCHIVE:`, and the
   version script becomes a `.def` file listing the same three prefixes (MSVC
   has no `--version-script`; a `.def` with `qcad_*` wildcards is the
   equivalent). `NativeLib.fileName` already returns `prototype_native.dll`,
   and `NativeLib.candidates` already searches beside the runner.
4. **CI** — `linux-build.yml`'s three jobs map one-for-one onto
   `windows-2022`; OCCT's flags are unchanged, Qt comes from
   `jurplel/install-qt-action` as it already does in the iOS job.

Two things Windows gets for free because Linux needed them first:
`app_dirs.dart` already returns `%APPDATA%\prototype`, and the window-close
handshake is a channel contract (`prototype/desktop` → `willClose`) rather
than anything GTK-shaped — the Win32 runner answers `WM_CLOSE` the way the GTK
one answers `delete-event`. Windows may not need it at all: its embedder
implements `System.requestAppExit`, and `didRequestAppExit` in `main.dart` is
already written for that.

Nothing in `frontend/lib` should need a fifteenth touch.

---

## Behaviour worth knowing about

- **Window.** Opens at 1376×1032 — the iPad Pro 13" landscape stage in logical
  points, so the desktop build starts life pixel-for-pixel the iPad build. It
  is a starting size, not a constraint; the layout is responsive and the
  minimum is 1024×700. **F11** toggles fullscreen.
- **Right-click** opens context menus everywhere the iPad long-presses: model
  browser rows, features, the end-of-part marker, gallery cards. Long press
  works too, for a touchscreen or a pen.
- **Share** has no desktop equivalent, so it opens the file in whatever the
  system associates with the type, and falls back to Save a copy when nothing
  is registered. **Export** is always Save a copy.
- **The file dialogs speak the app's language.** Their titles and filter names
  come from the ARB catalogue and are passed over the channel — the app is
  natively German, and a chooser titled "Save a copy" above a ribbon that says
  "Exportieren" is a seam the user sees. GTK localises its own buttons.
- **Open in place** is real here: a `.ptp` opened from anywhere is remembered
  by its path, appears in the gallery, and Save writes back to *that* file.
  What iOS needs a security-scoped bookmark for, a path already is.
- **Mesh import** asks convert-or-faceted in a GTK dialog. Off iOS the app
  used to choose `convert` silently; on the desktop it asks, like the iPad.
- **The busy card** during a long mesh conversion is a UIKit view on iOS,
  drawn by the platform thread while the Dart isolate blocks inside the
  kernel. The GTK embedder runs Dart on the *same* thread as the main loop, so
  there is nothing that could animate; a long conversion shows a still window.
  Honest and unpleasant. Fixing it means moving the conversion off the main
  isolate, which is a change to shared code and belongs on `main`, not here.
- **Documents** live in `~/.local/share/prototype` (`$XDG_DATA_HOME` when set;
  `%APPDATA%\prototype` on Windows), with the log and the perf log beside
  them. NOT in `~/Documents`, which belongs to the user rather than to us, and
  NOT via `getApplicationDocumentsDirectory()`, which is what the iPad uses and
  which reaches that answer by running `xdg-user-dir` — a program that is not
  installed everywhere and THROWS where it is not. On a machine without it the
  app used to fall through to `/tmp` and lose every document at the next
  reboot, silently. See `lib/platform/app_dirs.dart`.
- **Closing the window saves the open document.** It has to be arranged: the
  GTK embedder sends `inactive`, `hidden`, and then the process is gone, with
  no `detached` and no `System.requestAppExit`. The runner blocks the close,
  asks the app (`prototype/desktop` → `willClose`), and destroys the window
  when the save reports back — with a 2.5 s ceiling, because a window that
  cannot be closed is a worse bug than a document that was not saved.
- **Typography** is Inter (SIL OFL 1.1), bundled. Not decoration: Flutter on
  Linux asks fontconfig, which answers with whatever the distribution
  installed, so the same build otherwise renders in three different faces with
  three different metrics — and a CAD ribbon is laid out against those. iOS is
  untouched and still resolves the system font.
- **F11** toggles fullscreen; the window opens at the iPad Pro 13" landscape
  size (see above).

---

## Licensing note

The bundle links QCAD (GPLv3) and libslvs (GPLv3) into
`libprototype_native.so`, exactly as the iOS build links them into its Runner.
OCCT is LGPL 2.1 with the OCCT exception, which is what permits static linking
here (see `backend/occt/VENDOR.md`). Qt 6 is used as **shared** libraries and
is bundled unmodified, which is the arrangement LGPL 3 asks for. Inter is SIL
OFL 1.1 and travels with its licence at
`frontend/assets/fonts/Inter-LICENSE.txt`. Nothing about
the desktop build changes the analysis the iOS build already rests on; it only
adds Qt, and adds it in the shape that keeps it simple.
