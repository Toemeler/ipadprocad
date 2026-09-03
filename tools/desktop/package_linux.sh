#!/usr/bin/env bash
# Prototype — assemble a distributable Linux build.
#
#   tools/desktop/package_linux.sh                  # tarball
#   tools/desktop/package_linux.sh --appimage       # tarball + AppImage
#   tools/desktop/package_linux.sh --skip-flutter   # reuse an existing bundle
#
# Produces dist/prototype-linux-x64/ and dist/prototype-linux-x64.tar.gz:
#
#   prototype                 the runner
#   lib/                      Flutter engine, the plugin, the CAD kernels, Qt
#   data/                     flutter_assets + icudtl.dat
#   share/applications/       the .desktop file
#   share/icons/hicolor/      the app icon, 16..512
#   share/mime/packages/      .ptp/.pts/.pas declared to the desktop
#   install.sh, uninstall.sh  per-user install into ~/.local
#
# WHY A TARBALL AND NOT A .deb
# ----------------------------
# A .deb has to name its dependencies, and the honest list for this build is
# "the GTK 3 stack and nothing else" — Qt and OCCT travel INSIDE the bundle
# because the app needs versions no distribution guarantees (Qt 6, OCCT 7.9.3
# built with a specific option set; Ubuntu 24.04 ships OCCT 7.6, whose toolkit
# names are different). A package whose dependency list is one line and whose
# payload is self-contained is a tarball with extra steps. The AppImage is the
# same tree with a runtime bolted on, for people who want one file.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
frontend="$repo/frontend"
name="prototype-linux-x64"
dist="$repo/dist"
stage="$dist/$name"

make_appimage=0
skip_flutter=0
for arg in "$@"; do
  case "$arg" in
    --appimage) make_appimage=1 ;;
    --skip-flutter) skip_flutter=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

say() { printf '\n=== %s ===\n' "$1"; }

bundle="$frontend/build/linux/x64/release/bundle"
if [ "$skip_flutter" = 0 ]; then
  say "flutter build linux --release"
  (cd "$frontend" && flutter build linux --release)
fi
[ -x "$bundle/prototype" ] || {
  echo "no release bundle at $bundle — run without --skip-flutter" >&2; exit 1;
}

say "staging $stage"
rm -rf "$stage"
mkdir -p "$stage"
cp -a "$bundle/." "$stage/"

# The desktop metadata. Kept OUT of the CMake install so that `flutter build
# linux` produces exactly what `flutter run` runs — a bundle with an
# install.sh in it would be a bundle that behaves differently depending on
# whether someone ran it.
pkg="$frontend/linux/packaging"
mkdir -p "$stage/share/applications" "$stage/share/mime/packages"
cp "$pkg/com.prototype.prototype.desktop" "$stage/share/applications/"
cp "$pkg/com.prototype.prototype.xml" "$stage/share/mime/packages/"
for dir in "$pkg/icons"/*/; do
  size="$(basename "$dir")"
  mkdir -p "$stage/share/icons/hicolor/$size/apps"
  cp "$dir/com.prototype.prototype.png" \
     "$stage/share/icons/hicolor/$size/apps/"
done

# Report what the kernels situation is, loudly. A bundle that silently shipped
# without them looks identical until the first extrude.
if [ -f "$stage/lib/libprototype_native.so" ]; then
  echo "kernels: libprototype_native.so present ($(du -h "$stage/lib/libprototype_native.so" | cut -f1))"
else
  echo "kernels: MISSING — this bundle runs on the Dart fallbacks only."
  echo "         Build them first: tools/desktop/build_native.sh"
fi

# ---------------------------------------------------------------------------
# install.sh — a PER-USER install, into ~/.local, with no root and no package
# manager. It is what makes the .desktop file and the MIME types take effect;
# without it the tarball is a folder you run a binary out of, which works and
# gets you no icon, no Open With and no double-click.
# ---------------------------------------------------------------------------
cat > "$stage/install.sh" <<'INSTALL'
#!/usr/bin/env bash
# Installs Prototype for the current user only: no root, no package manager,
# nothing outside $HOME. Re-running it upgrades in place.
set -euo pipefail
src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prefix="${PREFIX:-$HOME/.local}"
app="$prefix/lib/prototype"

echo "installing into $app"
rm -rf "$app"
mkdir -p "$app" "$prefix/bin"
# Everything except the desktop metadata and these scripts, which go to the
# places the desktop actually reads.
(cd "$src" && tar --exclude=./share --exclude=./install.sh \
    --exclude=./uninstall.sh -cf - .) | (cd "$app" && tar -xf -)

# A launcher rather than a symlink: the runner finds its data/ and lib/ from
# the directory of the RESOLVED executable, so a symlink in ~/.local/bin would
# work — but exec'ing through a script also lets the user's own LD_LIBRARY_PATH
# stay out of the bundle's way, which is what stops a system Qt from being
# picked up instead of the one that shipped.
cat > "$prefix/bin/prototype" <<LAUNCH
#!/usr/bin/env bash
exec "$app/prototype" "\$@"
LAUNCH
chmod +x "$prefix/bin/prototype"

mkdir -p "$prefix/share/applications" "$prefix/share/mime/packages"
# The Exec line has to name the launcher we just wrote; the file in the tarball
# says plain "prototype", which is right once ~/.local/bin is on PATH and wrong
# for a desktop file, which is not started from a shell.
sed "s|^Exec=prototype|Exec=$prefix/bin/prototype|" \
  "$src/share/applications/com.prototype.prototype.desktop" \
  > "$prefix/share/applications/com.prototype.prototype.desktop"
cp "$src/share/mime/packages/com.prototype.prototype.xml" \
   "$prefix/share/mime/packages/"
cp -r "$src/share/icons" "$prefix/share/"

# Tell the desktop. All three are best-effort: a missing tool costs an icon or
# a file association, never the install.
command -v update-desktop-database >/dev/null 2>&1 \
  && update-desktop-database "$prefix/share/applications" || true
command -v update-mime-database >/dev/null 2>&1 \
  && update-mime-database "$prefix/share/mime" || true
command -v gtk-update-icon-cache >/dev/null 2>&1 \
  && gtk-update-icon-cache -f -t "$prefix/share/icons/hicolor" || true

echo
echo "installed. Run:  prototype"
case ":$PATH:" in
  *":$prefix/bin:"*) ;;
  *) echo "NOTE: $prefix/bin is not on your PATH." ;;
esac
INSTALL

cat > "$stage/uninstall.sh" <<'UNINSTALL'
#!/usr/bin/env bash
# Removes what install.sh put in $HOME. Leaves your DOCUMENTS alone — they live
# in the app's own data directory and are not this script's to delete.
set -euo pipefail
prefix="${PREFIX:-$HOME/.local}"
rm -rf "$prefix/lib/prototype"
rm -f "$prefix/bin/prototype"
rm -f "$prefix/share/applications/com.prototype.prototype.desktop"
rm -f "$prefix/share/mime/packages/com.prototype.prototype.xml"
find "$prefix/share/icons/hicolor" -name 'com.prototype.prototype.png' \
  -delete 2>/dev/null || true
command -v update-desktop-database >/dev/null 2>&1 \
  && update-desktop-database "$prefix/share/applications" || true
command -v update-mime-database >/dev/null 2>&1 \
  && update-mime-database "$prefix/share/mime" || true
echo "uninstalled. Your documents were not touched."
UNINSTALL
chmod +x "$stage/install.sh" "$stage/uninstall.sh"

say "tarball"
tar -C "$dist" -czf "$dist/$name.tar.gz" "$name"
echo "$dist/$name.tar.gz  ($(du -h "$dist/$name.tar.gz" | cut -f1))"

if [ "$make_appimage" = 1 ]; then
  say "AppImage"
  appdir="$dist/Prototype.AppDir"
  rm -rf "$appdir"
  mkdir -p "$appdir/usr"
  cp -a "$stage/." "$appdir/usr/"
  rm -f "$appdir/usr/install.sh" "$appdir/usr/uninstall.sh"
  # An AppImage wants the .desktop file and the icon at the ROOT of the AppDir
  # as well as under usr/share.
  cp "$pkg/com.prototype.prototype.desktop" "$appdir/"
  cp "$pkg/icons/256x256/com.prototype.prototype.png" "$appdir/"
  cat > "$appdir/AppRun" <<'APPRUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/prototype" "$@"
APPRUN
  chmod +x "$appdir/AppRun"
  tool="${APPIMAGETOOL:-}"
  if [ -z "$tool" ]; then
    tool="$dist/appimagetool"
    if [ ! -x "$tool" ]; then
      echo "fetching appimagetool"
      curl -fsSL -o "$tool" \
        https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
      chmod +x "$tool"
    fi
  fi
  # --appimage-extract-and-run: appimagetool is itself an AppImage and needs
  # FUSE otherwise, which a container almost never has.
  ARCH=x86_64 "$tool" --appimage-extract-and-run "$appdir" \
    "$dist/Prototype-x86_64.AppImage"
  echo "$dist/Prototype-x86_64.AppImage"
fi

say "done"
