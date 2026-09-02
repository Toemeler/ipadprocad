#!/usr/bin/env python3
"""M348 - publish a folder of icon renders to the iPad, live.

Watches a folder for PNGs, crops each one to its own content, squares it and
serves the result on the local network. The app polls `manifest.json` once a
second and swaps in anything that changed, so saving a render in Blender shows
up on the tablet in about a second with no build and no install.

    python serve.py [render-folder] [--port 8080] [--size 256]

The render folder defaults to `renders/` beside this script. Name each file
after the icon it replaces - `CR.extrude.png` for `CR['extrude']`, or just
`extrude.png` where no other map has a key by that name. Delete a file and
that icon goes back to the one built into the app.

Needs Pillow:  py -m pip install pillow
"""
import hashlib
import http.server
import json
import os
import socket
import sys
import threading
import time

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is missing.  Run:  py -m pip install pillow")

# How close to pure white still counts as background, when a render arrives
# with no alpha channel at all.
WHITE_TOLERANCE = 8
# Breathing room around the artwork, as a fraction of the square's side. The
# ribbon draws icons edge to edge, so a render cropped tight to its own ink
# reads bigger than the icons beside it.
MARGIN = 0.06


def lan_ip() -> str:
    """This machine's address on the LAN. Connects nothing; just asks the
    routing table which interface would be used to reach the outside."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def square(img: Image.Image, side: int, warned: set) -> Image.Image:
    """Crop to the artwork, centre it in a square, resize to `side`."""
    img = img.convert("RGBA")
    alpha = img.getchannel("A")
    if alpha.getextrema()[0] == 255:
        # Fully opaque: the render has a background baked in. Key out white so
        # the icon does not arrive as a white tile on the dark ribbon. A hard
        # key leaves a little fringing on antialiased edges - the fix is on the
        # Blender side, so say so once rather than pretending it is fine.
        if "white" not in warned:
            warned.add("white")
            print("  ! renders have no transparency - keying out white.")
            print("    Better: Render Properties > Film > Transparent, save as RGBA PNG.")
        px = img.load()
        w, h = img.size
        cut = 255 - WHITE_TOLERANCE
        for y in range(h):
            for x in range(w):
                r, g, b, _ = px[x, y]
                if r >= cut and g >= cut and b >= cut:
                    px[x, y] = (r, g, b, 0)
        alpha = img.getchannel("A")

    box = alpha.getbbox()
    if box is None:
        raise ValueError("the render is empty - nothing but background")
    img = img.crop(box)

    w, h = img.size
    side_px = max(w, h)
    pad = int(side_px * MARGIN)
    canvas = Image.new("RGBA", (side_px + 2 * pad, side_px + 2 * pad), (0, 0, 0, 0))
    canvas.paste(img, (pad + (side_px - w) // 2, pad + (side_px - h) // 2))
    return canvas.resize((side, side), Image.LANCZOS)


class Publisher:
    def __init__(self, src: str, side: int):
        self.src, self.side = src, side
        self.icons: dict[str, bytes] = {}   # name -> png bytes
        self.stamps: dict[str, str] = {}    # name -> content hash
        self._seen: dict[str, float] = {}   # path -> mtime
        self._warned: set = set()
        self._lock = threading.Lock()

    def manifest(self) -> bytes:
        with self._lock:
            body = {"stamp": str(time.time()), "icons": dict(self.stamps)}
        return json.dumps(body).encode()

    def png(self, name: str):
        with self._lock:
            return self.icons.get(name)

    def scan(self):
        try:
            files = {f for f in os.listdir(self.src) if f.lower().endswith(".png")}
        except FileNotFoundError:
            return
        live = {os.path.splitext(f)[0] for f in files}

        with self._lock:
            for gone in [n for n in self.stamps if n not in live]:
                del self.stamps[gone]
                self.icons.pop(gone, None)
                print(f"  - {gone} (removed; back to the built-in icon)")
            for stale in [p for p in self._seen if os.path.basename(p)[:-4] not in live]:
                del self._seen[stale]

        for f in sorted(files):
            path = os.path.join(self.src, f)
            try:
                mtime = os.path.getmtime(path)
            except OSError:
                continue
            if self._seen.get(path) == mtime:
                continue
            # Blender writes the file in pieces; a read that lands mid-write
            # raises, and the next tick picks it up.
            try:
                with Image.open(path) as im:
                    out = square(im, self.side, self._warned)
                buf = __import__("io").BytesIO()
                out.save(buf, "PNG", optimize=True)
                data = buf.getvalue()
            except Exception as e:                      # noqa: BLE001
                print(f"  ! {f}: {e}")
                continue
            self._seen[path] = mtime
            name = os.path.splitext(f)[0]
            stamp = hashlib.md5(data).hexdigest()[:12]
            with self._lock:
                if self.stamps.get(name) == stamp:
                    continue
                self.icons[name] = data
                self.stamps[name] = stamp
            print(f"  + {name}  ({len(data) // 1024} KB)")

    def watch(self):
        while True:
            self.scan()
            time.sleep(0.4)


def handler_for(pub: Publisher):
    class H(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def _send(self, body: bytes, ctype: str):
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            # The tablet polls every second; a cached manifest would freeze it.
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):                                # noqa: N802
            path = self.path.split("?", 1)[0]
            if path in ("/manifest.json", "/"):
                self._send(pub.manifest(), "application/json")
                return
            if path.startswith("/i/") and path.endswith(".png"):
                from urllib.parse import unquote
                name = unquote(path[3:-4])
                data = pub.png(name)
                if data:
                    self._send(data, "image/png")
                    return
            self.send_error(404)

        def log_message(self, *_):
            pass                                          # one line per icon is plenty

    return H


def main():
    argv = sys.argv[1:]
    port, side = 8080, 256
    src = None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--port":
            i += 1
            port = int(argv[i])
        elif a == "--size":
            i += 1
            side = int(argv[i])
        elif a in ("-h", "--help"):
            print(__doc__)
            return
        else:
            src = a
        i += 1
    if src is None:
        src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "renders")
    os.makedirs(src, exist_ok=True)

    pub = Publisher(src, side)
    pub.scan()
    threading.Thread(target=pub.watch, daemon=True).start()

    srv = http.server.ThreadingHTTPServer(("0.0.0.0", port), handler_for(pub))
    ip = lan_ip()
    print()
    print("  Watching:  " + src)
    print(f"  Serving :  {len(pub.stamps)} icon(s) at {side}x{side}")
    print()
    print("  On the iPad:  Settings > Diagnostics > Icon Preview")
    print()
    print(f"      {ip}:{port}")
    print()
    print("  Ctrl+C to stop.")
    print()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\n  stopped.")


if __name__ == "__main__":
    main()
