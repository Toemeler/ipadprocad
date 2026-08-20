"""The websocket frame codec and the URL normalisation, without a network.

A hand-rolled RFC 6455 client is worth exactly as much as its framing is
correct, and framing bugs present as hangs rather than as errors — the server
simply stops answering. So the frames this client emits are decoded here by an
independent reader, and a real handshake is run against a socket served by the
standard library.
"""

import base64
import hashlib
import os
import re
import socket
import struct
import sys
import threading
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import vmservice  # noqa: E402
from vmservice import VmService, VmServiceError, WebSocket, ws_url_from  # noqa: E402


def decode_client_frame(data: bytes):
    """Decode one client->server frame the way a server must."""
    b0, b1 = struct.unpack("!BB", data[:2])
    fin, op = bool(b0 & 0x80), b0 & 0x0F
    masked, n = bool(b1 & 0x80), b1 & 0x7F
    off = 2
    if n == 126:
        (n,) = struct.unpack("!H", data[off:off + 2]); off += 2
    elif n == 127:
        (n,) = struct.unpack("!Q", data[off:off + 8]); off += 8
    key = data[off:off + 4] if masked else b""
    off += 4 if masked else 0
    body = data[off:off + n]
    if masked:
        body = bytes(b ^ key[i % 4] for i, b in enumerate(body))
    return fin, op, masked, body, data[off + n:]


def server_frame(payload: bytes, op=0x1, fin=True):
    """Encode one server->client frame (unmasked, as the RFC requires)."""
    n = len(payload)
    head = struct.pack("!BB", (0x80 if fin else 0) | op, n) if n < 126 else \
        struct.pack("!BBH", (0x80 if fin else 0) | op, 126, n)
    return head + payload


class UrlNormalisationTest(unittest.TestCase):
    def test_every_shape_the_tooling_prints(self):
        want = "ws://127.0.0.1:1234/AbC=/ws"
        for given in (
            "http://127.0.0.1:1234/AbC=/",
            "http://127.0.0.1:1234/AbC=",
            "ws://127.0.0.1:1234/AbC=/ws",
            "  http://127.0.0.1:1234/AbC=/  ",
        ):
            self.assertEqual(ws_url_from(given), want, given)

    def test_https_becomes_wss(self):
        self.assertTrue(ws_url_from("https://h:9/t=/").startswith("wss://"))


class FramingTest(unittest.TestCase):
    """The client's own frames, decoded by the reader above."""

    class _Fake:
        def __init__(self):
            self.sent = b""

        def sendall(self, b):
            self.sent += b

        def close(self):
            pass

    def _ws(self):
        ws = WebSocket.__new__(WebSocket)
        ws._sock = self._Fake()
        ws._buf = b""
        ws._closed = False
        return ws

    def test_client_frames_are_masked(self):
        ws = self._ws()
        ws.send_text("hello")
        fin, op, masked, body, rest = decode_client_frame(ws._sock.sent)
        self.assertTrue(fin)
        self.assertEqual(op, 0x1)
        self.assertTrue(masked, "an unmasked client frame is closed by servers")
        self.assertEqual(body, b"hello")
        self.assertEqual(rest, b"")

    def test_the_two_extended_length_forms(self):
        for n in (125, 126, 70000):
            ws = self._ws()
            ws.send_text("x" * n)
            _, _, _, body, _ = decode_client_frame(ws._sock.sent)
            self.assertEqual(len(body), n)

    def test_utf8_survives_the_mask(self):
        ws = self._ws()
        ws.send_text('{"m":"Größe — µs"}')
        _, _, _, body, _ = decode_client_frame(ws._sock.sent)
        self.assertEqual(body.decode("utf-8"), '{"m":"Größe — µs"}')

    def test_reassembles_a_fragmented_server_message(self):
        ws = self._ws()
        ws._buf = (server_frame(b'{"a":', op=0x1, fin=False) +
                   server_frame(b'1}', op=0x0, fin=True))
        self.assertEqual(ws.recv_text(), '{"a":1}')

    def test_answers_a_ping_with_a_pong_and_keeps_reading(self):
        ws = self._ws()
        ws._buf = server_frame(b"hi", op=0x9) + server_frame(b"ok")
        self.assertEqual(ws.recv_text(), "ok")
        _, op, masked, body, _ = decode_client_frame(ws._sock.sent)
        self.assertEqual(op, 0xA)
        self.assertTrue(masked)
        self.assertEqual(body, b"hi")

    def test_a_close_frame_is_an_error_not_a_hang(self):
        ws = self._ws()
        ws._buf = server_frame(b"", op=0x8)
        with self.assertRaises(VmServiceError):
            ws.recv_text()


class LiveSocketTest(unittest.TestCase):
    """A real handshake and a real RPC round trip over loopback."""

    def _serve(self, sock, script):
        conn, _ = sock.accept()
        data = b""
        while b"\r\n\r\n" not in data:
            data += conn.recv(4096)
        key = re.search(rb"(?i)sec-websocket-key:\s*([^\r\n]+)", data).group(1)
        accept = base64.b64encode(hashlib.sha1(
            key.strip() + vmservice._GUID.encode()).digest()).decode()
        conn.sendall(
            b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
            b"Connection: Upgrade\r\nSec-WebSocket-Accept: " +
            accept.encode() + b"\r\n\r\n")
        script(conn)

    def setUp(self):
        self._sockets = []

    def tearDown(self):
        for s in self._sockets:
            try:
                s.close()
            except OSError:
                pass

    def _server(self, script):
        sock = socket.socket()
        sock.bind(("127.0.0.1", 0))
        sock.listen(1)
        self._sockets.append(sock)
        t = threading.Thread(target=self._serve, args=(sock, script), daemon=True)
        t.start()
        return f"ws://127.0.0.1:{sock.getsockname()[1]}/ws"

    def test_handshake_and_rpc(self):
        import json

        def script(conn):
            data = conn.recv(4096)
            _, _, _, body, _ = decode_client_frame(data)
            req = json.loads(body)
            # An unsolicited stream event first: the client must not mistake it
            # for its own answer.
            conn.sendall(server_frame(json.dumps(
                {"jsonrpc": "2.0", "method": "streamNotify",
                 "params": {"streamId": "Isolate"}}).encode()))
            conn.sendall(server_frame(json.dumps(
                {"jsonrpc": "2.0", "id": req["id"],
                 "result": {"type": "Version", "major": 4}}).encode()))

        svc = VmService(self._server(script), timeout=10)
        self.assertEqual(svc.call("getVersion")["major"], 4)
        self.assertEqual(len(svc.drain_events()), 1)
        svc.close()

    def test_an_rpc_error_is_raised_with_its_message(self):
        import json

        def script(conn):
            data = conn.recv(4096)
            _, _, _, body, _ = decode_client_frame(data)
            conn.sendall(server_frame(json.dumps(
                {"jsonrpc": "2.0", "id": json.loads(body)["id"],
                 "error": {"code": 112, "message": "Isolate must be runnable"}}
            ).encode()))

        svc = VmService(self._server(script), timeout=10)
        with self.assertRaises(VmServiceError) as cm:
            svc.call("resume", {"isolateId": "x"})
        self.assertIn("Isolate must be runnable", str(cm.exception))
        svc.close()

    def test_a_refused_upgrade_is_reported(self):
        sock = socket.socket()
        sock.bind(("127.0.0.1", 0))
        sock.listen(1)
        self._sockets.append(sock)

        def bad():
            conn, _ = sock.accept()
            conn.recv(4096)
            conn.sendall(b"HTTP/1.1 404 Not Found\r\n\r\n")
            conn.close()

        threading.Thread(target=bad, daemon=True).start()
        with self.assertRaises(VmServiceError):
            WebSocket(f"ws://127.0.0.1:{sock.getsockname()[1]}/ws", timeout=5)


if __name__ == "__main__":
    unittest.main()
