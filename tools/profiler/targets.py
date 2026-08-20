"""Where the VM Service comes from.

Every target here has the same two obligations and no others: hand back a
`ws://` URL, and be able to say whether the thing being profiled has finished.
Nothing in this file — or anywhere else under `tools/profiler/` — puts code
inside the application. `OPTIMIZATION_PLAN_2.md` §4 is explicit that this
session owns no app code, and it is right on the technical merits too: the VM
Service is an out-of-process debugger interface, so a hook would buy nothing
and cost a permanent edit to a file five other sessions are also editing.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import threading
import time

# `flutter test`, `flutter run`, `dart --observe` and a Flutter iOS app on a
# simulator all announce the service the same way, modulo wording that has
# changed twice ("Observatory", then "The Dart VM service"). Match the URL, not
# the sentence around it.
_URI_RE = re.compile(r"(?:ws|http)s?://(?:127\.0\.0\.1|localhost|\[::1\])"
                     r":\d+/[A-Za-z0-9_=\-]*=?/?")


class Target:
    name = "target"

    def start(self) -> None:
        pass

    def uri(self, timeout_s: float) -> str:
        raise NotImplementedError

    def finished(self) -> bool:
        return False

    def stop(self) -> None:
        pass

    @property
    def log(self) -> str:
        return ""

    @property
    def returncode(self) -> int | None:
        return None


class AttachTarget(Target):
    """A service URI somebody else is responsible for."""
    name = "attach"

    def __init__(self, uri: str):
        self._uri = uri

    def uri(self, timeout_s: float) -> str:
        return self._uri


class ProcessTarget(Target):
    """A child process that prints its service URI on stdout."""

    def __init__(self, argv: list[str], cwd: str | None = None,
                 env: dict | None = None, name: str = "process"):
        self.argv = argv
        self.cwd = cwd
        self.env = env
        self.name = name
        self._proc: subprocess.Popen | None = None
        self._lines: list[str] = []
        self._uri: str | None = None
        self._lock = threading.Lock()

    def start(self) -> None:
        self._proc = subprocess.Popen(
            self.argv, cwd=self.cwd, env=self.env,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1)
        threading.Thread(target=self._pump, daemon=True).start()

    def _pump(self) -> None:
        assert self._proc and self._proc.stdout
        for line in self._proc.stdout:
            with self._lock:
                self._lines.append(line.rstrip("\n"))
                if self._uri is None:
                    m = _URI_RE.search(line)
                    if m and "devtools" not in line.lower():
                        self._uri = m.group(0)

    def uri(self, timeout_s: float) -> str:
        deadline = time.monotonic() + timeout_s
        while time.monotonic() < deadline:
            with self._lock:
                if self._uri:
                    return self._uri
            if self._proc and self._proc.poll() is not None:
                raise RuntimeError(
                    f"{self.name} exited (rc={self._proc.returncode}) before it "
                    f"printed a VM Service URI.\n--- output ---\n{self.log}")
            time.sleep(0.1)
        raise RuntimeError(
            f"{self.name} printed no VM Service URI within {timeout_s}s.\n"
            f"--- output ---\n{self.log}")

    def finished(self) -> bool:
        return bool(self._proc and self._proc.poll() is not None)

    def stop(self) -> None:
        if self._proc and self._proc.poll() is None:
            self._proc.terminate()
            try:
                self._proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                self._proc.kill()

    @property
    def log(self) -> str:
        with self._lock:
            return "\n".join(self._lines)

    @property
    def returncode(self) -> int | None:
        return self._proc.returncode if self._proc else None


def flutter_bin(explicit: str | None = None) -> str:
    for cand in (explicit, os.environ.get("FLUTTER_BIN"), "flutter"):
        if not cand:
            continue
        found = shutil.which(cand) or (cand if os.path.isfile(cand) else None)
        if found:
            return found
    raise RuntimeError("no `flutter` on PATH; pass --flutter-bin")


class FlutterTestTarget(ProcessTarget):
    """`flutter test --start-paused <file>` — the host lane.

    Why a test process is a legitimate profiling target and not a dodge: the
    2D pipeline the profile's largest finding lives in (§5.5, `analyzeSketch`)
    is pure Dart with no FFI on this path, and CI already runs it exactly this
    way on `ubuntu-latest`. Profiling it here measures the same source lines
    the device executes, on a different CPU and a JIT runtime. That licenses
    reading the ATTRIBUTION and forbids reading the milliseconds — the same
    rule §13.3 sets for the simulator, applied to the host.
    """
    name = "flutter test"

    def __init__(self, project: str, dart_file: str, *, flutter: str | None = None,
                 extra_args: list[str] | None = None):
        fb = flutter_bin(flutter)
        argv = [fb, "test", "--start-paused", "--reporter", "expanded",
                *(extra_args or []), dart_file]
        env = dict(os.environ)
        env.setdefault("FLUTTER_SUPPRESS_ANALYTICS", "true")
        super().__init__(argv, cwd=project, env=env, name="flutter test")


class DartTarget(ProcessTarget):
    """`dart run --observe` — for a driver with no Flutter dependency."""
    name = "dart"

    def __init__(self, script: str, *, cwd: str | None = None,
                 dart: str = "dart", args: list[str] | None = None):
        argv = [dart, "run", "--observe=0/127.0.0.1",
                "--pause-isolates-on-start", "--no-serve-devtools",
                script, *(args or [])]
        super().__init__(argv, cwd=cwd, name="dart")


class SimulatorTarget(ProcessTarget):
    """A Flutter iOS app already installed on a booted simulator.

    `simctl launch --console-pty` streams the app's stdout, which is where a
    debug Flutter engine prints its service URI. The simulator shares the
    host's loopback interface, so the URI it prints is directly dialable from
    the runner — no port forwarding, unlike a physical device.

    NOT VERIFIED BY THE SESSION THAT WROTE IT: no macOS host was available.
    The workflow that uses this path fails loudly rather than going green
    without a trace, which is the only guarantee that can honestly be offered
    until a run proves the rest.
    """
    name = "simulator"

    def __init__(self, udid: str, bundle_id: str, *, args: list[str] | None = None):
        argv = ["xcrun", "simctl", "launch", "--console-pty",
                "--terminate-running-process", udid, bundle_id, *(args or [])]
        super().__init__(argv, name="simulator")
        self._udid = udid

    def finished(self) -> bool:
        # `--console-pty` keeps the child alive for as long as the app runs, so
        # process exit does mean the app is gone. It is still not a scenario
        # boundary: the app decides when its own suite ends, and the caller
        # supplies --duration for that.
        return super().finished()
