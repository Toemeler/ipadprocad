#!/usr/bin/env python3
"""Shared loading for the knowledge base under `knowledge/`.

WHY THIS FILE EXISTS. Two tools need the same answer to the same question -
"what documents are there, and what does each one declare?" - and they must
never disagree about it. build_index.py writes the menu the app reads;
validate_kb.py checks that the menu can be trusted. If they parsed the folder
differently, CI could pass on an index the app cannot use.

THE FRONTMATTER IS DELIBERATELY PARSED BY HAND. PyYAML is not in this
repository's dependency set and this is not worth adding one for: the schema is
six scalar fields and two flat lists, all of it written by us, all of it
checked by the validator. A hand-rolled reader that refuses anything it does
not recognise is safer here than a permissive general parser - it turns a typo
into a failing build rather than into a silently missing trigger.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
KB_ROOT = REPO_ROOT / "knowledge"

REQUIRED_KEYS = ("id", "title", "type", "process", "triggers", "confidence", "updated")
OPTIONAL_KEYS = ("depends_on",)

VALID_TYPES = {
    "basics", "material", "rules", "recipe",
    "decision", "failures", "checklist", "example",
}
# "design" is not a manufacturing process and sits here anyway, because it is
# retrieved by exactly the same mechanism and has to obey exactly the same
# shape. Issue #82 asked for "ein Designer Kabelhalter" and got a rounded slab:
# the assistant knew how to make a thing and nothing about what makes a thing
# worth looking at, because nobody had written that half down.
VALID_PROCESSES = {"laser", "fdm", "design", "shared"}
VALID_CONFIDENCE = {"high", "medium", "starting-point"}

# The six sections every document carries, in order. See knowledge/TEMPLATE.md.
REQUIRED_SECTIONS = (
    "When this applies",
    "Good starting values",
    "How to build it",
    "When to do it differently",
    "Images",
    "Source & date",
)

# Documents that are structurally different from the rest and are exempt from
# the six-section shape: the contract, the skeleton and the photo wishlist.
EXEMPT_FILES = {"README.md", "TEMPLATE.md", "PHOTOS.md", "index.md"}

_SCALAR = re.compile(r"^([a-z_]+):\s*(.*)$")


@dataclass
class Doc:
    path: Path                      # absolute path on disk
    rel: str                        # path relative to the repo root, for messages
    meta: dict                      # the parsed frontmatter
    body: str                       # everything after the frontmatter
    errors: list = field(default_factory=list)

    @property
    def doc_id(self) -> str:
        return self.meta.get("id", "")


def parse_frontmatter(text: str, rel: str) -> tuple[dict, str, list[str]]:
    """Return (meta, body, errors). Never raises on malformed input."""
    errors: list[str] = []
    if not text.startswith("---\n"):
        return {}, text, [f"{rel}: no YAML frontmatter (file must start with '---')"]

    end = text.find("\n---\n", 4)
    if end == -1:
        return {}, text, [f"{rel}: frontmatter is not closed with '---'"]

    raw = text[4:end]
    body = text[end + 5:]
    meta: dict = {}

    for lineno, line in enumerate(raw.splitlines(), start=2):
        if not line.strip():
            continue
        m = _SCALAR.match(line)
        if not m:
            errors.append(f"{rel}:{lineno}: cannot parse frontmatter line: {line!r}")
            continue
        key, value = m.group(1), m.group(2).strip()
        if value.startswith("[") and value.endswith("]"):
            inner = value[1:-1].strip()
            meta[key] = [v.strip() for v in inner.split(",") if v.strip()] if inner else []
        else:
            meta[key] = value

    return meta, body, errors


def load_docs() -> list[Doc]:
    """Every knowledge document on disk, in a stable order."""
    docs: list[Doc] = []
    for path in sorted(KB_ROOT.rglob("*.md")):
        if path.name in EXEMPT_FILES:
            continue
        rel = str(path.relative_to(REPO_ROOT))
        text = path.read_text(encoding="utf-8")
        meta, body, errors = parse_frontmatter(text, rel)
        docs.append(Doc(path=path, rel=rel, meta=meta, body=body, errors=errors))
    return docs
