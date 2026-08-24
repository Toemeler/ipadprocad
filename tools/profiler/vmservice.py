"""A Dart VM Service client with no dependencies outside the standard library.

Why hand-rolled. The `ci/` tooling in this repository is stdlib-only Python and
runs on three different runner images without a `pip install` step anywhere.
A profiler that needs `websockets` from PyPI would be one network failure away
from a red job whose redness says nothing about the code — and the whole point
of `tools/profiler/` is to produce evidence, not weather.

So this module contains two small things:

  * `WebSocket` — an RFC 6455 client, text frames only, enough of the protocol
    to talk to the VM Service and nothing more (no extensions, no permessage
    deflate, no continuation of a fragmented *send*).
  * `VmService` — JSON-RPC 2.0 over that socket, with the request/notification
    split the VM Service actually uses: responses carry `id`, stream events
    arrive as `streamNotify` notifications with no `id`.

The VM Service protocol reference is
https://github.com/dart-lang/sdk/blob/main/runtime/vm/service/service.md
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
import re
import select
import socket
import ssl
import struct
import threading
import time
import urllib.parse

_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

# Opcodes we care about.
_OP_CONT = 0x0
_OP_TEXT = 0x1
_OP_BINARY = 0x2
_OP_CLOSE = 0x8
_OP_PING = 0x9
_OP_PONG = 0xA


class VmServiceError(RuntimeError):
    """An RPC returned a JSON-RPC error, or the transport gave up."""


class WebSocket:
    """A minimal RFC 6455 client. Blocking, single-threaded reads."""

    def __init__(self, url: str, timeout: float = 30.0):
        parts = urllib.parse.urlsplit(url)
        secure = parts.scheme in ("wss", "https")
        host = parts.hostname or "127.0.0.1"
        port = parts.port or (443 if secure else 80)
        path = parts.path or "/"
        if parts.query:
            path += "?" + parts.query

        self._buf = b""
        self._closed = False
        self._sock = socket.create_connection((host, port), timeout=timeout)
        if secure:
            ctx = ssl.create_default_context()
            self._sock = ctx.wrap_socket(self._sock, server_hostname=host)
        self._sock.settimeout(timeout)

        key = base64.b64encode(os.urandom(16)).decode("ascii")
        req = (
            f"GET {path} HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            "\r\n"
        )
        self._sock.sendall(req.encode("ascii"))

        head = self._read_until(b"\r\n\r\n")
        status = head.split(b"\r\n", 1)[0].decode("latin-1")
        if "101" not in status:
            raise VmServiceError(f"websocket upgrade refused: {status}")
        want = base64.b64encode(
            hashlib.sha1((key + _GUID).encode("ascii")).digest()
        ).decode("ascii")
        m = re.search(rb"(?i)sec-websocket-accept:\s*([^\r\n]+)", head)
        if not m or m.group(1).decode("ascii").strip() != want:
            raise VmServiceError("websocket handshake accept-key mismatch")

    # -- framing ----------------------------------------------------------
    def _read_until(self, marker: bytes) -> bytes:
        while marker not in self._buf:
            chunk = self._sock.recv(65536)
            if not chunk:
                raise VmServiceError("connection closed during handshake")
            self._buf += chunk
        head, self._buf = self._buf.split(marker, 1)
        return head + marker

    def _recv_exact(self, n: int) -> bytes:
        while len(self._buf) < n:
            chunk = self._sock.recv(max(65536, n - len(self._buf)))
            if not chunk:
                raise VmServiceError("connection closed mid-frame")
            self._buf += chunk
        out, self._buf = self._buf[:n], self._buf[n:]
        return out

    def send_text(self, text: str) -> None:
        payload = text.encode("utf-8")
        # Client-to-server frames MUST be masked (RFC 6455 §5.3). Servers close
        # the connection on an unmasked client frame, which presents as a
        # mysterious hang rather than an error, so this is not optional.
        mask = os.urandom(4)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        n = len(payload)
        if n < 126:
            header = struct.pack("!BB", 0x80 | _OP_TEXT, 0x80 | n)
        elif n < (1 << 16):
            header = struct.pack("!BBH", 0x80 | _OP_TEXT, 0x80 | 126, n)
        else:
            header = struct.pack("!BBQ", 0x80 | _OP_TEXT, 0x80 | 127, n)
        self._sock.sendall(header + mask + masked)

    def recv_text(self) -> str:
        """Return the next complete text message, reassembling fragments."""
        parts: list[bytes] = []
        while True:
            b0, b1 = struct.unpack("!BB", self._recv_exact(2))
            fin = bool(b0 & 0x80)
            op = b0 & 0x0F
            masked = bool(b1 & 0x80)
            n = b1 & 0x7F
            if n == 126:
                (n,) = struct.unpack("!H", self._recv_exact(2))
            elif n == 127:
                (n,) = struct.unpack("!Q", self._recv_exact(8))
            key = self._recv_exact(4) if masked else b""
            data = self._recv_exact(n)
            if masked:
                data = bytes(b ^ key[i % 4] for i, b in enumerate(data))

            if op == _OP_PING:
                self._send_control(_OP_PONG, data)
                continue
            if op == _OP_PONG:
                continue
            if op == _OP_CLOSE:
                self._closed = True
                raise VmServiceError("server closed the websocket")
            if op in (_OP_TEXT, _OP_BINARY, _OP_CONT):
                parts.append(data)
                if fin:
                    return b"".join(parts).decode("utf-8", "replace")
                continue
            raise VmServiceError(f"unexpected websocket opcode {op}")

    def _send_control(self, op: int, data: bytes) -> None:
        mask = os.urandom(4)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
        header = struct.pack("!BB", 0x80 | op, 0x80 | len(data))
        self._sock.sendall(header + mask + masked)

    def close(self) -> None:
        if not self._closed:
            try:
                self._send_control(_OP_CLOSE, b"\x03\xe8")
            except OSError:
                pass
            self._closed = True
        try:
            self._sock.close()
        except OSError:
            pass


class VmService:
    """JSON-RPC 2.0 against a Dart VM Service websocket.

    Reads happen on a background thread because the VM Service interleaves
    stream events with RPC responses on one socket: a caller blocking on
    `recv_text()` for its own response would otherwise have to decide what to
    do with somebody else's event mid-call.
    """

    def __init__(self, ws_url: str, timeout: float = 30.0):
        self._ws = WebSocket(ws_url, timeout=timeout)
        self._id = 0
        self._lock = threading.Lock()
        self._pending: dict[str, dict] = {}
        self._events: list[dict] = []
        self._cv = threading.Condition(self._lock)
        self._fatal: Exception | None = None
        self._timeout = timeout
        self._reader = threading.Thread(target=self._read_loop, daemon=True)
        self._reader.start()

    def _read_loop(self) -> None:
        try:
            while True:
                msg = json.loads(self._ws.recv_text())
                with self._cv:
                    if "id" in msg and msg["id"] is not None:
                        self._pending[str(msg["id"])] = msg
                    else:
                        self._events.append(msg)
                    self._cv.notify_all()
        except Exception as exc:  # noqa: BLE001 — surfaced to every caller
            with self._cv:
                self._fatal = exc
                self._cv.notify_all()

    def call(self, method: str, params: dict | None = None,
             timeout: float | None = None) -> dict:
        timeout = self._timeout if timeout is None else timeout
        with self._lock:
            self._id += 1
            rid = str(self._id)
        req = {"jsonrpc": "2.0", "id": rid, "method": method,
               "params": params or {}}
        self._ws.send_text(json.dumps(req))

        deadline = time.monotonic() + timeout
        with self._cv:
            while rid not in self._pending:
                if self._fatal is not None:
                    raise VmServiceError(f"{method}: {self._fatal}")
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise VmServiceError(f"{method}: timed out after {timeout}s")
                self._cv.wait(remaining)
            msg = self._pending.pop(rid)
        if "error" in msg:
            err = msg["error"]
            raise VmServiceError(
                f"{method}: [{err.get('code')}] {err.get('message')} "
                f"{json.dumps(err.get('data', {}))[:400]}")
        return msg.get("result", {})

    def drain_events(self) -> list[dict]:
        with self._lock:
            out, self._events = self._events, []
        return out

    def close(self) -> None:
        self._ws.close()


def ws_url_from(uri: str) -> str:
    """Normalise any of the four shapes the tooling prints into a ws:// URL.

    `flutter test` prints `http://127.0.0.1:PORT/TOKEN=/`, `flutter run` prints
    the same, DevTools prints `ws://127.0.0.1:PORT/TOKEN=/ws`, and a hand-typed
    one may have neither the trailing slash nor the `/ws`. All four have to
    work, because which one a reader has in their clipboard is not something
    this tool gets to choose.
    """
    uri = uri.strip()
    parts = urllib.parse.urlsplit(uri)
    scheme = {"http": "ws", "https": "wss"}.get(parts.scheme, parts.scheme or "ws")
    path = parts.path or "/"
    if not path.endswith("/ws"):
        path = path.rstrip("/") + "/ws"
    return urllib.parse.urlunsplit((scheme, parts.netloc, path, "", ""))
