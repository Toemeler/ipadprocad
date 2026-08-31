#!/usr/bin/env python3
"""The wire format between the model and the working tree.

WHY SEARCH/REPLACE AND NOT A UNIFIED DIFF
-----------------------------------------
A unified diff carries line numbers and a hunk header, and a model that is off
by two lines produces a patch `git apply` rejects outright. The recovery from
that is another model call, and at this pipeline's budget a wasted call is a
third of the issue's total cost.

A search/replace block carries no line numbers. It fails only if the quoted
text genuinely is not in the file, which is a real error worth escalating
rather than an arithmetic slip. The model is given slices WITH real line
numbers so it can still reason and cite precisely; it just does not have to
count when it writes.

THE FORMAT
----------
    <file path="frontend/lib/widgets/ribbon.dart">
    <<<<<<< SEARCH
    (text exactly as it appears now)
    =======
    (text to put there instead)
    >>>>>>> REPLACE
    </file>

    <file path="frontend/test/m287_thing_test.dart" new="true">
    (the whole file)
    </file>

    <expand path="frontend/lib/theme.dart">floor</expand>

Several SEARCH/REPLACE blocks may appear inside one `<file>`. `expand` is the
model's way of saying the pack did not contain the answer — it is cheaper to
serve one more slice than to let it guess, and the retriever is known to find
only one end of a cross-cutting fix (see test_rank.py::test_known_misses).

WHY `new="true"` IS EXPLICIT
---------------------------
So that a search/replace whose SEARCH text is missing can never be silently
reinterpreted as "create this file", which would let a failed edit land as a
brand-new file full of half the module.
"""
import dataclasses
import pathlib
import re


@dataclasses.dataclass
class Replace:
    path: str
    search: str
    replace: str


@dataclasses.dataclass
class NewFile:
    path: str
    content: str


@dataclasses.dataclass
class Expand:
    path: str
    query: str


FILE_RE = re.compile(
    r'<file\s+path="([^"]+)"(\s+new="true")?\s*>\n(.*?)\n?</file>',
    re.DOTALL)
EXPAND_RE = re.compile(r'<expand\s+path="([^"]+)"\s*>(.*?)</expand>', re.DOTALL)
BLOCK_RE = re.compile(
    r'<{7} SEARCH\n(.*?)\n?={7}\n(.*?)\n?>{7} REPLACE', re.DOTALL)

# Paths the model is never allowed to touch, whatever it says. The protocol
# states this in prose; here it is enforced, because prose in a context window
# is a suggestion and this is not.
FORBIDDEN = ('.github/', 'relay/', 'ci/', 'frontend/lib/l10n/gen/', '.git/')


def _safe(path):
    p = pathlib.PurePosixPath(path)
    if p.is_absolute() or '..' in p.parts:
        return False
    return not any(path.startswith(f) for f in FORBIDDEN)


def parse(text):
    """-> (edits, expands, errors)."""
    edits, errors = [], []
    expands = [Expand(m.group(1), m.group(2).strip())
               for m in EXPAND_RE.finditer(text)]
    for m in FILE_RE.finditer(text):
        path, is_new, body = m.group(1), bool(m.group(2)), m.group(3)
        if not _safe(path):
            errors.append(f'{path}: this path may not be modified')
            continue
        if is_new:
            edits.append(NewFile(path, body))
            continue
        blocks = BLOCK_RE.findall(body)
        if not blocks:
            errors.append(
                f'{path}: <file> without new="true" must contain at least one '
                'SEARCH/REPLACE block')
            continue
        for search, replace in blocks:
            edits.append(Replace(path, search, replace))
    return edits, expands, errors


def is_test(path):
    return path.startswith('frontend/test/')


def apply(edits, root):
    """Apply in order. -> list of error strings; empty means everything landed.

    Nothing is written until every edit has been resolved, so a failure in the
    third block cannot leave the tree half-patched.
    """
    root = pathlib.Path(root)
    staged, errors = {}, []
    for e in edits:
        target = root / e.path
        if isinstance(e, NewFile):
            staged[e.path] = e.content if e.content.endswith('\n') else e.content + '\n'
            continue
        current = staged.get(e.path)
        if current is None:
            if not target.is_file():
                errors.append(f'{e.path}: no such file')
                continue
            current = target.read_text(encoding='utf-8')
        count = current.count(e.search)
        if count == 0:
            errors.append(
                f'{e.path}: SEARCH text not found. It must match the file '
                f'byte for byte. First line looked for: '
                f'{e.search.splitlines()[0][:120]!r}')
            continue
        if count > 1:
            errors.append(
                f'{e.path}: SEARCH text appears {count} times; include enough '
                'surrounding context to make it unique')
            continue
        staged[e.path] = current.replace(e.search, e.replace, 1)
    if errors:
        return errors
    for path, content in staged.items():
        p = root / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding='utf-8')
    return []


def touched(edits):
    seen = []
    for e in edits:
        if e.path not in seen:
            seen.append(e.path)
    return seen
