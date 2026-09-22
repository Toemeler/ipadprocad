#!/usr/bin/env python3
"""Render the knowledge base to PDFs — one per document, plus a bound volume per process.

WHY THIS EXISTS. The documents are written to be read by a model, which reads
markdown perfectly well. People do not: a table that is pipes and dashes, an
SVG that is a line of angle brackets, and a caption that is a stray line of
italics are all unreadable as source and clear as rendered pages. This script
produces the human view.

TWO DECISIONS WORTH KNOWING.

  * SVGs are INLINED, not linked. A linked image would need the PDF renderer
    to resolve a relative path at print time, which is fragile and produces a
    silent blank where the diagram should be. Inlining the markup means the
    diagram is vector inside the PDF: it stays sharp at any zoom and the file
    stays small.

  * Image + caption become a <figure> BEFORE markdown conversion. In the
    source, every diagram is an image line followed by an italic caption; left
    alone the converter emits two unrelated paragraphs that a page break can
    separate. Pairing them first lets `break-inside: avoid` keep a diagram and
    its explanation on one page, which is the whole point of the caption.

Requires: python-markdown, and a Chromium binary (Playwright's is used here).
"""

from __future__ import annotations

import base64
import html
import re
import subprocess
import sys
from pathlib import Path

import markdown

REPO = Path(__file__).resolve().parents[2]
KB = REPO / "knowledge"
OUT = REPO / "build" / "kb-pdf"

CHROME_CANDIDATES = [
    "/opt/pw-browsers/chromium-1194/chrome-linux/chrome",
    "/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell",
]

FIGURE_RE = re.compile(
    r"^!\[(?P<alt>[^\]]*)\]\((?P<src>[^)]+)\)[ \t]*\n\*(?P<cap>.+?)\*[ \t]*$",
    re.MULTILINE | re.DOTALL,
)
LONE_IMG_RE = re.compile(r"^!\[(?P<alt>[^\]]*)\]\((?P<src>[^)]+)\)[ \t]*$", re.MULTILINE)

CSS = """
@page { size: A4; margin: 18mm 16mm 16mm 16mm; }
* { box-sizing: border-box; }
body {
  font-family: -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  font-size: 10.5pt; line-height: 1.5; color: #1a1a1a; margin: 0;
  -webkit-print-color-adjust: exact; print-color-adjust: exact;
}
.doc { page-break-after: always; }
.doc:last-child { page-break-after: auto; }
h1 { font-size: 20pt; line-height: 1.2; margin: 0 0 4pt; letter-spacing: -0.01em; }
h2 { font-size: 13pt; margin: 18pt 0 6pt; padding-top: 6pt; border-top: 1px solid #e2e2e2;
     break-after: avoid; }
h3 { font-size: 11.5pt; margin: 13pt 0 4pt; break-after: avoid; }
p { margin: 0 0 7pt; orphans: 2; widows: 2; }
ul, ol { margin: 0 0 8pt; padding-left: 18pt; }
li { margin-bottom: 3pt; }
a { color: #0b5ea8; text-decoration: none; }
code { font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
       font-size: 9pt; background: #f4f4f5; padding: 1px 3px; border-radius: 3px; }
pre { background: #f6f6f7; border: 1px solid #e4e4e7; border-radius: 5px;
      padding: 8pt 10pt; overflow-x: auto; break-inside: avoid; margin: 0 0 9pt; }
pre code { background: none; padding: 0; font-size: 8.5pt; line-height: 1.45; }
blockquote { margin: 0 0 9pt; padding: 6pt 12pt; border-left: 3px solid #0b6bcb;
             background: #f3f7fb; }
blockquote p:last-child { margin-bottom: 0; }
table { border-collapse: collapse; width: 100%; margin: 0 0 10pt; font-size: 9pt;
        break-inside: auto; }
thead { display: table-header-group; }
tr { break-inside: avoid; }
th, td { border: 1px solid #dcdcdf; padding: 4pt 6pt; text-align: left; vertical-align: top; }
th { background: #f2f2f4; font-weight: 600; }
tbody tr:nth-child(even) { background: #fafafa; }
figure { margin: 10pt 0 12pt; break-inside: avoid; text-align: center; }
figure svg { max-width: 100%; height: auto; display: inline-block; border: 1px solid #e6e6e8; border-radius: 6px; }
figure img { max-width: 100%; height: auto; border: 1px solid #e6e6e8; border-radius: 6px; }
figcaption { font-size: 8.5pt; color: #55555c; margin-top: 5pt; line-height: 1.45;
             text-align: left; max-width: 46em; margin-left: auto; margin-right: auto; }
hr { border: none; border-top: 1px solid #e2e2e2; margin: 14pt 0; }
.meta { border: 1px solid #e0e0e3; border-radius: 6px; background: #fafafb;
        padding: 8pt 10pt; margin: 0 0 14pt; font-size: 8.5pt; color: #444; }
.meta dl { display: grid; grid-template-columns: max-content 1fr; gap: 2pt 10pt; margin: 0; }
.meta dt { font-weight: 600; color: #6a6a72; }
.meta dd { margin: 0; }
.meta .path { font-family: ui-monospace, Menlo, Consolas, monospace; font-size: 8pt; }
.badge { display: inline-block; padding: 1px 6px; border-radius: 9px; font-size: 7.5pt;
         font-weight: 600; letter-spacing: 0.02em; text-transform: uppercase; }
.b-design { background: #ece6fa; color: #4c3a8f; }
.b-laser  { background: #fdeadf; color: #92451a; }
.b-fdm    { background: #dff0e6; color: #1f6b3f; }
.b-shared { background: #e8eaed; color: #40444a; }
.volume-title { page-break-after: always; padding-top: 60mm; text-align: center; }
.volume-title h1 { font-size: 30pt; border: none; }
.volume-title p { color: #55555c; font-size: 11pt; }
"""


def find_chrome() -> str:
    for c in CHROME_CANDIDATES:
        if Path(c).exists():
            return c
    sys.exit("no chromium binary found")


def split_frontmatter(text: str) -> tuple[dict, str]:
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---\n", 4)
    if end == -1:
        return {}, text
    meta = {}
    for line in text[4:end].splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            meta[k.strip()] = v.strip()
    return meta, text[end + 5:]


def inline_image(src: str, base: Path) -> str:
    """Return HTML for one image: SVG inlined as vector, raster as base64."""
    target = (base / src.split("#")[0]).resolve()
    if not target.exists():
        return f'<div style="padding:10pt;border:1px dashed #c8c8cc;color:#8a8a90;font-size:9pt">missing image: {html.escape(src)}</div>'
    if target.suffix.lower() == ".svg":
        svg = target.read_text(encoding="utf-8")
        # The width/height attributes are deliberately KEPT: they are the size
        # the diagram was drawn at, and stretching one to the text column makes
        # its labels oversized and its line weights coarse. CSS caps it at the
        # column width for the few that are wider.
        return re.sub(r"<\?xml[^>]*\?>", "", svg).strip()
    data = base64.b64encode(target.read_bytes()).decode()
    mime = {"jpg": "jpeg", "jpeg": "jpeg", "png": "png", "gif": "gif"}.get(
        target.suffix.lower().lstrip("."), "png")
    return f'<img src="data:image/{mime};base64,{data}" alt="">'


def preprocess(body: str, base: Path) -> str:
    """Pair each image with its italic caption into a figure, before conversion."""
    def fig(m):
        cap = re.sub(r"\s+", " ", m.group("cap")).strip()
        return ("\n<figure>" + inline_image(m.group("src"), base)
                + f"<figcaption>{html.escape(cap)}</figcaption></figure>\n")

    body = FIGURE_RE.sub(fig, body)
    body = LONE_IMG_RE.sub(
        lambda m: "\n<figure>" + inline_image(m.group("src"), base) + "</figure>\n", body)
    return body


def meta_block(meta: dict, rel: str) -> str:
    if not meta:
        return f'<div class="meta"><dl><dt>file</dt><dd class="path">{html.escape(rel)}</dd></dl></div>'
    proc = meta.get("process", "shared")
    rows = [
        ("id", f'<code>{html.escape(meta.get("id", "—"))}</code>'),
        ("kind", f'{html.escape(meta.get("type", "—"))} · '
                 f'<span class="badge b-{proc}">{html.escape(proc)}</span>'),
        ("confidence", html.escape(meta.get("confidence", "—"))),
        ("updated", html.escape(meta.get("updated", "—"))),
        ("file", f'<span class="path">{html.escape(rel)}</span>'),
    ]
    trig = meta.get("triggers", "")
    if trig:
        rows.insert(2, ("opens on", html.escape(trig.strip("[]"))))
    dl = "".join(f"<dt>{k}</dt><dd>{v}</dd>" for k, v in rows)
    return f'<div class="meta"><dl>{dl}</dl></div>'


def render_doc(path: Path) -> tuple[str, dict]:
    raw = path.read_text(encoding="utf-8")
    meta, body = split_frontmatter(raw)
    body = preprocess(body, path.parent)
    md = markdown.Markdown(extensions=["tables", "fenced_code", "sane_lists", "md_in_html"])
    inner = md.convert(body)
    # Point cross-references at the PDFs that sit beside this one.
    inner = re.sub(r'(href="[^"]*?)\.md(["#])', r"\1.pdf\2", inner)
    rel = str(path.relative_to(REPO))
    return f'<article class="doc">{meta_block(meta, rel)}{inner}</article>', meta


def page(title: str, content: str) -> str:
    return (f'<!doctype html><html><head><meta charset="utf-8">'
            f"<title>{html.escape(title)}</title><style>{CSS}</style></head>"
            f"<body>{content}</body></html>")


def to_pdf(chrome: str, html_path: Path, pdf_path: Path) -> None:
    pdf_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [chrome, "--headless", "--disable-gpu", "--no-sandbox", "--hide-scrollbars",
         "--no-pdf-header-footer", f"--print-to-pdf={pdf_path}", html_path.as_uri()],
        check=True, capture_output=True, timeout=180,
    )


def main() -> int:
    chrome = find_chrome()
    tmp = OUT / "_html"
    tmp.mkdir(parents=True, exist_ok=True)

    docs = sorted(KB.rglob("*.md"))
    print(f"rendering {len(docs)} documents with {Path(chrome).name}")

    volumes: dict[str, list[tuple[str, str]]] = {}
    for i, path in enumerate(docs, 1):
        rel = path.relative_to(KB)
        article, meta = render_doc(path)
        proc = meta.get("process") or "shared"
        volumes.setdefault(proc, []).append((meta.get("title", path.stem), article))

        html_file = tmp / rel.with_suffix(".html")
        html_file.parent.mkdir(parents=True, exist_ok=True)
        html_file.write_text(page(meta.get("title", path.stem), article), encoding="utf-8")
        to_pdf(chrome, html_file, OUT / "documents" / rel.with_suffix(".pdf"))
        if i % 20 == 0 or i == len(docs):
            print(f"  {i}/{len(docs)}")

    names = {"design": "Design", "laser": "Laser cutting — wood",
             "fdm": "FDM printing", "shared": "Shared"}
    for proc, items in sorted(volumes.items()):
        title = names.get(proc, proc)
        cover = (f'<section class="volume-title"><h1>{html.escape(title)}</h1>'
                 f"<p>{len(items)} documents · manufacturing and design knowledge base</p></section>")
        body = cover + "".join(a for _, a in items)
        hf = tmp / f"volume-{proc}.html"
        hf.write_text(page(title, body), encoding="utf-8")
        to_pdf(chrome, hf, OUT / "volumes" / f"{proc}.pdf")
        print(f"  volume {proc}: {len(items)} documents")

    print(f"\nwritten to {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
