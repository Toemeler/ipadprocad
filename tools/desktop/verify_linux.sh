#!/usr/bin/env bash
# Prototype — prove the Linux build is one somebody else can run.
#
# `linux-build.yml` already asserts that the bundle it just made LAUNCHES: a
# first frame, the real kernels, both smokes, the path tracer, the GPU
# viewport. That is the build machine asking whether the build machine can run
# it, and it is not the question. The question is whether the tarball works on
# a computer that has never had Qt, never had OCCT, has no `xdg-user-dir`, and
# is not the machine it was built on — and LINUX.md answers most of that with
# "to check by hand", which is another way of saying nobody checks it.
#
# This is that check, by machine, on one host:
#
#   1  launch        the five things CI asserts, so a local run is comparable
#   2  self-contained the Qt sonames MOVED OUT of the system and the kernels
#                    still load — the four-red-CI-runs lesson in LINUX.md
#   3  documents     land in the data dir with `xdg-user-dir` absent from PATH,
#                    rather than in /tmp to be lost at the next reboot
#   4  shutdown      closing the window runs the save handshake, not a kill
#   5  mirror        two installs on one host pair and a document crosses
#   6  tarball       extracted somewhere else entirely, by a user who is not
#                    the builder, with $HOME empty — and install.sh registers
#                    the icon, the launcher and the MIME types
#   7  double-click  a .ptp named on the command line opens, which is what the
#                    .desktop file's `%f` turns a double-click into
#   8  AppImage      the one-file build starts and finds its kernels too
#
# Every check runs the SHIPPING artefact, never the source tree.
#
#   tools/desktop/verify_linux.sh            # everything
#   tools/desktop/verify_linux.sh 1 3 5      # only those checks
#
# Needs: Xvfb, xdotool, and a bundle — build it first with
# `tools/desktop/build_native.sh && (cd frontend && flutter build linux
# --release)`; check 6 additionally needs `tools/desktop/package_linux.sh`.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
bundle="$repo/frontend/build/linux/x64/release/bundle"
work="${VERIFY_WORK:-/tmp/verify-linux}"
display="${VERIFY_DISPLAY:-:99}"

pass=0; fail=0; skipped=0
declare -a failures=()

say()  { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }
ok()   { pass=$((pass+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()  { fail=$((fail+1)); failures+=("$1"); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
skip() { skipped=$((skipped+1)); printf '  \033[33mSKIP\033[0m %s\n' "$1"; }

# A log line the app wrote, or the empty string. Every assertion in this file
# reads the app's OWN log rather than stdout: the interesting lines (the kernel
# search list above all) go there and nowhere else.
applog() { cat "$1/prototype/logs/prototype_log.txt" 2>/dev/null; }

want() { # want <haystack-file> <needle> <what>
  if grep -qF -- "$2" "$1"; then ok "$3"; else bad "$3"; fi
}

# Start the app with its own data directory, wait for it to say it is up, and
# leave $child holding the pid. Returns 1 if no first frame arrived.
launch() { # launch <binary> <xdg-data-home> [extra env...]
  local bin="$1" xdg="$2"; shift 2
  mkdir -p "$xdg"
  rm -f "$xdg/prototype/logs/prototype_log.txt"
  DISPLAY="$display" XDG_DATA_HOME="$xdg" "$@" "$bin" \
    > "$xdg/stdout.log" 2>&1 &
  child=$!
  local i
  for i in $(seq 1 90); do
    grep -q "time to first frame" "$xdg/stdout.log" 2>/dev/null && return 0
    kill -0 "$child" 2>/dev/null || break
    sleep 1
  done
  return 1
}

stop() { kill "${1:-$child}" 2>/dev/null; wait "${1:-$child}" 2>/dev/null; return 0; }

# The five assertions linux-build.yml makes, against a log this run produced.
# Two of them exist because the failure is SILENT and correct-looking: without
# the kernels the app falls back to the Dart engine, and without Flutter GPU
# the viewport falls back to the CPU painter. Both look like a working app.
assert_healthy() { # assert_healthy <stdout-log> <app-log> <label>
  local out="$1" log="$2" tag="$3"
  want "$out" "time to first frame"           "$tag: reaches a first frame"
  want "$log" "REAL backend active (qcad-ffi)" "$tag: the QCAD core is loaded"
  want "$log" "DART SMOKE: PASS"               "$tag: a geometry round trip works"
  want "$log" "backend=occt-ffi"               "$tag: the OCCT shim answers"
  want "$log" "cycles: ready: device"          "$tag: the path tracer is there"
  want "$log" "renderer: flutter_scene"        "$tag: the GPU viewport is on"
}

xserver_up() {
  if xdpyinfo -display "$display" >/dev/null 2>&1; then return 0; fi
  Xvfb "$display" -screen 0 1600x1200x24 >/dev/null 2>&1 &
  xvfb_pid=$!
  local i
  for i in $(seq 1 30); do
    xdpyinfo -display "$display" >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

# ---------------------------------------------------------------------------

check_1_launch() {
  say "1  the bundle launches, with everything it is supposed to have"
  [ -x "$bundle/prototype" ] || { skip "no bundle at $bundle"; return; }
  local xdg="$work/1"
  rm -rf "$xdg"
  if launch "$bundle/prototype" "$xdg"; then
    applog "$xdg" > "$work/1.applog"
    assert_healthy "$xdg/stdout.log" "$work/1.applog" "launch"
  else
    bad "launch: reaches a first frame"
    tail -30 "$xdg/stdout.log" 2>/dev/null | sed 's/^/      /'
  fi
  stop
}

# Check 2 takes the system's Qt away for a few seconds, which is the only
# thing in this file that touches anything outside $work. Restoring it is not
# allowed to depend on the check finishing: a Ctrl-C in the middle would
# otherwise leave the machine without Qt.
qt_hidden_dir=""
restore_qt() {
  [ -n "$qt_hidden_dir" ] || return 0
  local f
  for f in "$qt_hidden_dir"/*; do
    [ -e "$f" ] || continue
    mv "$f" "/usr/lib/x86_64-linux-gnu/$(basename "$f")" 2>/dev/null
  done
  ldconfig 2>/dev/null
  rmdir "$qt_hidden_dir" 2>/dev/null
  qt_hidden_dir=""
}
trap 'restore_qt' EXIT INT TERM

check_2_self_contained() {
  say "2  it runs on a computer that has never had Qt"
  [ -x "$bundle/prototype" ] || { skip "no bundle at $bundle"; return; }
  if [ "$(id -u)" -ne 0 ]; then
    skip "not root — cannot take the system's Qt away to prove it is unused"
    return
  fi
  local libdir=/usr/lib/x86_64-linux-gnu
  local hidden="$work/qt-moved-aside"
  local -a moved=()
  mkdir -p "$hidden"
  qt_hidden_dir="$hidden"
  # Qt's OWN sonames only. Everything else the kernels need is either bundled
  # beside them or is genuinely base-system furniture (the loader, libc, the
  # graphics stack, GTK) — see LINUX.md, "The bundle has to run on a machine
  # that has never had Qt".
  local so
  while IFS= read -r so; do
    mv "$so" "$hidden/" 2>/dev/null && moved+=("$so")
  done < <(ls "$libdir"/libQt6*.so.* 2>/dev/null)
  if [ "${#moved[@]}" -eq 0 ]; then
    skip "no system Qt to hide — this host proves nothing either way"
    qt_hidden_dir=""
    rmdir "$hidden" 2>/dev/null
    return
  fi
  ldconfig 2>/dev/null
  local xdg="$work/2"
  rm -rf "$xdg"
  if launch "$bundle/prototype" "$xdg"; then
    applog "$xdg" > "$work/2.applog"
    want "$work/2.applog" "REAL backend active (qcad-ffi)" \
      "no system Qt: the kernels still load from the bundle"
  else
    bad "no system Qt: the app still starts"
    tail -20 "$xdg/stdout.log" 2>/dev/null | sed 's/^/      /'
  fi
  stop
  restore_qt
  # And prove the machine got its Qt back, because everything after this check
  # runs on a system this check just edited.
  if ls "$libdir"/libQt6Core.so.* >/dev/null 2>&1; then
    ok "the system's Qt was put back"
  else
    bad "the system's Qt was put back — look in $hidden"
  fi
}

check_3_documents() {
  say "3  documents land where they are meant to, with no xdg-user-dir"
  [ -x "$bundle/prototype" ] || { skip "no bundle at $bundle"; return; }
  local xdg="$work/3"
  rm -rf "$xdg"
  mkdir -p "$xdg/prototype"
  cp "$repo/tools/desktop/testdata/sample.ptp" "$xdg/prototype/Verify.ptp" 2>/dev/null \
    || printf '{"version":1,"type":"part","sketches":[],"features":[]}' \
         > "$xdg/prototype/Verify.ptp"
  # PATH without xdg-user-dir. `getApplicationDocumentsDirectory()` runs that
  # program and THROWS where it is missing; the app used to fall through to
  # /tmp and lose every document at the next reboot, silently.
  local slim; slim="$(mktemp -d "$work/slimpath.XXXX")"
  local b
  for b in sh bash ls cat sed grep zenity; do
    command -v "$b" >/dev/null 2>&1 && ln -sf "$(command -v "$b")" "$slim/$b"
  done
  if launch "$bundle/prototype" "$xdg" env "PATH=$slim"; then
    applog "$xdg" > "$work/3.applog"
    # Two separate resolutions, and they run at different moments: Log.init
    # derives its own directory before the platform channel is up, AppState
    # derives the documents directory after. Either can be the one that falls
    # through to /tmp, so both are asserted.
    if [ -s "$xdg/prototype/logs/prototype_log.txt" ]; then
      ok "the log went to XDG_DATA_HOME/prototype/logs"
    else
      bad "the log went to XDG_DATA_HOME/prototype/logs"
    fi
    want "$work/3.applog" "docs dir = $xdg/prototype" \
      "documents resolve to XDG_DATA_HOME/prototype"
    # The line the app writes when the resolution THREW — which is what
    # `xdg-user-dir` being missing used to do, silently, with /tmp as the
    # answer and every document gone at the next reboot.
    if grep -qF "docs dir failed, using systemTemp" "$work/3.applog"; then
      bad "no fall-through to a temp directory"
    else
      ok "no fall-through to a temp directory"
    fi
  else
    bad "starts with xdg-user-dir absent from PATH"
    tail -20 "$xdg/stdout.log" 2>/dev/null | sed 's/^/      /'
  fi
  stop
  rm -rf "$slim"
}

check_4_shutdown() {
  say "4  closing the window is a save, not a kill"
  [ -x "$bundle/prototype" ] || { skip "no bundle at $bundle"; return; }
  command -v xdotool >/dev/null 2>&1 || { skip "xdotool not installed"; return; }
  local xdg="$work/4"
  rm -rf "$xdg"
  if ! launch "$bundle/prototype" "$xdg"; then
    bad "shutdown: the app started"
    stop; return
  fi
  sleep 3
  local win
  win="$(DISPLAY=$display xdotool search --pid "$child" 2>/dev/null | tail -1)"
  if [ -z "$win" ]; then
    win="$(DISPLAY=$display xdotool search --name . 2>/dev/null | tail -1)"
  fi
  if [ -z "$win" ]; then
    skip "no window found to close"
    stop; return
  fi
  local began; began=$(date +%s%N)
  DISPLAY=$display xdotool windowclose "$win"
  local i gone=1
  for i in $(seq 1 15); do
    kill -0 "$child" 2>/dev/null || { gone=0; break; }
    sleep 0.2
  done
  local took=$(( ($(date +%s%N) - began) / 1000000 ))
  if [ "$gone" -eq 0 ]; then
    ok "the window closing ends the process (${took} ms)"
  else
    bad "the window closing ends the process"
    stop
  fi
  # THE RUNNER'S OWN VERDICT. my_application.cc blocks the close, asks the app
  # `willClose`, and destroys the window in the reply callback — but only for
  # 2500 ms, after which it warns and closes anyway. That ceiling exists so a
  # window is always closable; reaching it means the save did NOT happen, and
  # the window shut all the same. So the warning's ABSENCE is the assertion,
  # and a close that took longer than the ceiling is the same failure by the
  # clock.
  if grep -qF "did not answer willClose" "$xdg/stdout.log" 2>/dev/null; then
    bad "the app answered the close handshake in time"
  elif [ "$gone" -eq 0 ] && [ "$took" -lt 2500 ]; then
    ok "the app answered the close handshake in time"
  else
    bad "the app answered the close handshake in time (${took} ms)"
  fi
}

check_5_mirror() {
  say "5  two installs on one host pair, and a document crosses"
  [ -x "$bundle/prototype" ] || { skip "no bundle at $bundle"; return; }
  local a="$work/5a" b="$work/5b"
  rm -rf "$a" "$b"
  mkdir -p "$a/prototype/.cache" "$b/prototype/.cache"
  local d
  for d in "$a" "$b"; do
    printf '{"sync":{"code":"ABCDEFGHJKLM"}}' > "$d/prototype/.cache/settings.json"
  done
  cp "$repo/tools/desktop/testdata/sample.ptp" "$a/prototype/Mirror.ptp" 2>/dev/null \
    || printf '{"version":1,"type":"part","sketches":[],"features":[]}' \
         > "$a/prototype/Mirror.ptp"
  local pa pb
  launch "$bundle/prototype" "$a"; pa=$child
  launch "$bundle/prototype" "$b"; pb=$child
  local i crossed=1
  for i in $(seq 1 45); do
    [ -f "$b/prototype/Mirror.ptp" ] && { crossed=0; break; }
    sleep 1
  done
  if [ "$crossed" -eq 0 ]; then
    ok "the document reached the second install"
    if cmp -s "$a/prototype/Mirror.ptp" "$b/prototype/Mirror.ptp"; then
      ok "and it arrived byte for byte"
    else
      bad "and it arrived byte for byte"
    fi
  else
    bad "the document reached the second install"
    applog "$a" | grep -a "sync:" | tail -12 | sed 's/^/      A: /'
    applog "$b" | grep -a "sync:" | tail -12 | sed 's/^/      B: /'
  fi
  stop "$pa"; stop "$pb"
}

check_6_tarball() {
  say "6  the tarball, unpacked by somebody who did not build it"
  local tgz="$repo/dist/prototype-linux-x64.tar.gz"
  [ -f "$tgz" ] || { skip "no tarball — run tools/desktop/package_linux.sh"; return; }
  local root="$work/6"
  rm -rf "$root"
  mkdir -p "$root/home" "$root/opt"
  tar -xzf "$tgz" -C "$root/opt" || { bad "the tarball extracts"; return; }
  ok "the tarball extracts"
  local app="$root/opt/prototype-linux-x64/prototype"
  [ -x "$app" ] || { bad "the tarball carries a runnable binary"; return; }
  ok "the tarball carries a runnable binary"
  local xdg="$root/home/.local/share"
  if launch "$app" "$xdg" env "HOME=$root/home"; then
    applog "$xdg" > "$work/6.applog"
    assert_healthy "$xdg/stdout.log" "$work/6.applog" "tarball"
  else
    bad "tarball: reaches a first frame"
    tail -30 "$xdg/stdout.log" 2>/dev/null | sed 's/^/      /'
  fi
  stop
  # install.sh is what turns a folder you run a binary out of into an app with
  # an icon, a launcher and Open With. Into a HOME of its own, so this never
  # touches the machine running the check.
  local ins="$root/opt/prototype-linux-x64/install.sh"
  if [ -x "$ins" ]; then
    if HOME="$root/home" XDG_DATA_HOME="$root/home/.local/share" \
       "$ins" > "$work/6.install.log" 2>&1; then
      ok "install.sh runs into an empty HOME"
    else
      bad "install.sh runs into an empty HOME"
      tail -20 "$work/6.install.log" | sed 's/^/      /'
    fi
    local f
    for f in "applications/com.prototype.prototype.desktop" \
             "icons/hicolor/512x512/apps/com.prototype.prototype.png" \
             "mime/packages/com.prototype.prototype.xml"; do
      if [ -e "$root/home/.local/share/$f" ]; then
        ok "install.sh registered $f"
      else
        bad "install.sh registered $f"
      fi
    done
    local launcher="$root/home/.local/bin/prototype"
    if [ -x "$launcher" ]; then
      ok "install.sh left a launcher on PATH"
    else
      bad "install.sh left a launcher on PATH"
    fi
  else
    skip "no install.sh in the tarball"
  fi
}

check_7_open_argument() {
  say "7  a document named on the command line opens"
  [ -x "$bundle/prototype" ] || { skip "no bundle at $bundle"; return; }
  local xdg="$work/7" doc="$work/7-doc/Double Clicked.ptp"
  rm -rf "$xdg" "$work/7-doc"
  mkdir -p "$work/7-doc"
  cp "$repo/tools/desktop/testdata/sample.ptp" "$doc" 2>/dev/null \
    || printf '{"version":1,"type":"part","sketches":[],"features":[]}' > "$doc"
  # Deliberately OUTSIDE the app's own directory, and with a space in the name:
  # this is the "open in place" path, where the argument is both the handle and
  # the place Save writes back to.
  mkdir -p "$xdg"
  rm -f "$xdg/prototype/logs/prototype_log.txt"
  DISPLAY="$display" XDG_DATA_HOME="$xdg" "$bundle/prototype" "$doc" \
    > "$xdg/stdout.log" 2>&1 &
  child=$!
  local i
  for i in $(seq 1 90); do
    grep -q "time to first frame" "$xdg/stdout.log" 2>/dev/null && break
    kill -0 "$child" 2>/dev/null || break
    sleep 1
  done
  sleep 4
  applog "$xdg" > "$work/7.applog"
  want "$work/7.applog" "launch argument: opening $doc" \
    "the path reaches the app as a launch argument"
  if grep -qF 'opened "Double Clicked"' "$work/7.applog"; then
    ok "the document actually opened"
  elif grep -qF "launch document was refused" "$work/7.applog"; then
    bad "the document actually opened (it was refused)"
  else
    bad "the document actually opened"
    grep -a "doc:" "$work/7.applog" | tail -5 | sed 's/^/      /'
  fi
  stop
}

check_8_appimage() {
  say "8  the AppImage, which is how most people will try it"
  local img
  img="$(ls "$repo/dist"/*.AppImage 2>/dev/null | head -1)"
  [ -n "$img" ] || { skip "no AppImage — run package_linux.sh --appimage"; return; }
  chmod +x "$img"
  local root="$work/8"
  rm -rf "$root"; mkdir -p "$root/home"
  local xdg="$root/home/.local/share"
  # --appimage-extract-and-run: a container almost never has FUSE, and whether
  # the user's machine does is not what this check is about.
  if launch "$img" "$xdg" env "HOME=$root/home" APPIMAGE_EXTRACT_AND_RUN=1; then
    applog "$xdg" > "$work/8.applog"
    assert_healthy "$xdg/stdout.log" "$work/8.applog" "AppImage"
  else
    bad "AppImage: reaches a first frame"
    tail -30 "$xdg/stdout.log" 2>/dev/null | sed 's/^/      /'
  fi
  stop
}

# ---------------------------------------------------------------------------

xserver_up || { echo "no X server on $display — install Xvfb" >&2; exit 2; }
mkdir -p "$work"

wanted=("$@")
[ "${#wanted[@]}" -eq 0 ] && wanted=(1 2 3 4 5 6 7 8)
for n in "${wanted[@]}"; do
  case "$n" in
    1) check_1_launch ;;
    2) check_2_self_contained ;;
    3) check_3_documents ;;
    4) check_4_shutdown ;;
    5) check_5_mirror ;;
    6) check_6_tarball ;;
    7) check_7_open_argument ;;
    8) check_8_appimage ;;
    *) echo "no such check: $n" >&2 ;;
  esac
done

[ -n "${xvfb_pid:-}" ] && kill "$xvfb_pid" 2>/dev/null

printf '\n\033[1m=== %d passed, %d failed, %d skipped ===\033[0m\n' \
  "$pass" "$fail" "$skipped"
if [ "$fail" -gt 0 ]; then
  printf 'failed:\n'
  printf '  - %s\n' "${failures[@]}"
  exit 1
fi
