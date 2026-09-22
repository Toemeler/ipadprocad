#!/usr/bin/env python3
"""Check that the knowledge base still holds together.

WHAT THIS PROTECTS. The assistant reaches for a document by id, from an index
generated out of frontmatter, and reads whatever images that document points
at. Three things can silently break that chain:

  * a document whose frontmatter drifts - a missing trigger list, an invalid
    type - so the index entry is useless even though the prose is fine;
  * a `depends_on` or a markdown link pointing at an id or a path that no
    longer exists, so the assistant asks for something that is not there and
    proceeds WITHOUT it, which is worse than never having asked;
  * an index that no longer matches the folder, which makes every other check
    meaningless.

None of these show up when a person reads the document. All of them show up
here in under a second.

THE SIX-SECTION CHECK IS NOT PEDANTRY. The shape is what makes the documents
usable by a model rather than by a reader: "Good starting values" is where the
numbers live, "When to do it differently" is what stops the model either
following a rule blindly or discarding the document whole. A document missing
that section has failed at its job even if every sentence in it is true.

Exit code 0 when clean, 1 when anything is wrong. Warnings do not fail.
"""

from __future__ import annotations

import json
import re
import sys

from kb_common import (
    KB_ROOT,
    REPO_ROOT,
    REQUIRED_KEYS,
    REQUIRED_SECTIONS,
    VALID_CONFIDENCE,
    VALID_PROCESSES,
    VALID_TYPES,
    load_docs,
)
import build_index

ID_RE = re.compile(r"^[a-z0-9]+(?:/[a-z0-9-]+)+$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
HEADING_RE = re.compile(r"^##\s+(.*)$", re.MULTILINE)


def check_frontmatter(doc, errors, warnings):
    meta = doc.meta
    for key in REQUIRED_KEYS:
        if key not in meta:
            errors.append(f"{doc.rel}: frontmatter is missing '{key}'")

    doc_id = meta.get("id", "")
    if doc_id and not ID_RE.match(doc_id):
        errors.append(f"{doc.rel}: id {doc_id!r} should look like 'process/area/name'")

    if (t := meta.get("type")) and t not in VALID_TYPES:
        errors.append(f"{doc.rel}: type {t!r} is not one of {sorted(VALID_TYPES)}")
    if (p := meta.get("process")) and p not in VALID_PROCESSES:
        errors.append(f"{doc.rel}: process {p!r} is not one of {sorted(VALID_PROCESSES)}")
    if (c := meta.get("confidence")) and c not in VALID_CONFIDENCE:
        errors.append(f"{doc.rel}: confidence {c!r} is not one of {sorted(VALID_CONFIDENCE)}")
    if (u := meta.get("updated")) and not DATE_RE.match(str(u)):
        errors.append(f"{doc.rel}: updated {u!r} is not YYYY-MM-DD")

    triggers = meta.get("triggers")
    if isinstance(triggers, list):
        if not triggers:
            errors.append(f"{doc.rel}: triggers is empty - nothing will ever open this document")
        elif len(triggers) < 3:
            warnings.append(f"{doc.rel}: only {len(triggers)} triggers; the menu line is the whole retrieval mechanism")
    elif "triggers" in meta:
        errors.append(f"{doc.rel}: triggers must be a [list]")


def check_sections(doc, errors):
    headings = HEADING_RE.findall(doc.body)
    for section in REQUIRED_SECTIONS:
        if section not in headings:
            errors.append(f"{doc.rel}: missing required section '## {section}'")


def check_links(doc, errors, known_ids):
    for target in LINK_RE.findall(doc.body):
        if target.startswith(("http://", "https://", "#", "mailto:")):
            continue
        clean = target.split("#", 1)[0].strip()
        if not clean:
            continue
        resolved = (doc.path.parent / clean).resolve()
        if not resolved.exists():
            errors.append(f"{doc.rel}: link target does not exist: {clean}")

    for dep in doc.meta.get("depends_on", []) or []:
        if dep not in known_ids:
            errors.append(f"{doc.rel}: depends_on {dep!r} is not an id any document declares")


def check_orphan_images(docs, warnings):
    referenced = set()
    for doc in docs:
        for target in LINK_RE.findall(doc.body):
            if target.startswith(("http://", "https://", "#")):
                continue
            clean = target.split("#", 1)[0].strip()
            if clean:
                referenced.add((doc.path.parent / clean).resolve())

    for img in sorted(KB_ROOT.rglob("img/*")):
        if img.is_file() and img.resolve() not in referenced:
            warnings.append(f"{img.relative_to(REPO_ROOT)}: image is not referenced by any document")


def check_index(docs, errors):
    expected = build_index.build_payload(docs)
    index_path = KB_ROOT / "index.json"
    if not index_path.exists():
        errors.append("knowledge/index.json is missing - run tools/kb/build_index.py")
        return
    actual = json.loads(index_path.read_text(encoding="utf-8"))
    if actual != expected:
        errors.append("knowledge/index.json is stale - run tools/kb/build_index.py and commit the result")

    md_path = KB_ROOT / "index.md"
    if not md_path.exists():
        errors.append("knowledge/index.md is missing - run tools/kb/build_index.py")
    elif md_path.read_text(encoding="utf-8") != build_index.render_markdown(expected):
        errors.append("knowledge/index.md is stale - run tools/kb/build_index.py and commit the result")

    # ISSUE #82 — THE BUNDLE IS THE ONLY COPY THE APP EVER SEES.
    #
    # Everything above checks that the MENU matches the folder. None of it
    # would have caught the actual fault, which was that no build step shipped
    # any of this and no line of Dart read it: CI was green on a knowledge base
    # the assistant could not open. The app now loads exactly one generated
    # file, so that file is what has to be verified - a stale bundle means the
    # assistant is designing from an old document, silently, which is the same
    # class of failure as having none.
    bundle = build_index.BUNDLE
    if not bundle.exists():
        errors.append(
            f"{bundle.relative_to(REPO_ROOT)} is missing - the app ships this, "
            "not knowledge/ - run tools/kb/build_index.py"
        )
        return
    want = json.dumps(
        build_index.build_bundle(docs), indent=1, ensure_ascii=False, sort_keys=True
    ) + "\n"
    if bundle.read_text(encoding="utf-8") != want:
        errors.append(
            f"{bundle.relative_to(REPO_ROOT)} is stale - the app would ship "
            "different text than knowledge/ holds - run tools/kb/build_index.py "
            "and commit the result"
        )


def main() -> int:
    docs = load_docs()
    errors: list[str] = []
    warnings: list[str] = []

    for doc in docs:
        errors.extend(doc.errors)

    seen: dict[str, str] = {}
    for doc in docs:
        doc_id = doc.doc_id
        if doc_id:
            if doc_id in seen:
                errors.append(f"{doc.rel}: id {doc_id!r} is already used by {seen[doc_id]}")
            else:
                seen[doc_id] = doc.rel

    for doc in docs:
        check_frontmatter(doc, errors, warnings)
        check_sections(doc, errors)
        check_links(doc, errors, set(seen))

    check_orphan_images(docs, warnings)
    check_index(docs, errors)

    for w in warnings:
        print(f"warning: {w}")
    for e in errors:
        print(f"ERROR: {e}", file=sys.stderr)

    print(f"\n{len(docs)} documents, {len(errors)} errors, {len(warnings)} warnings")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
