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


# Deliberately forgiving about everything except the path and the block
# markers. Issue #9's seventh run produced 13,859 output tokens and not one
# parseable block; a format that only accepts one exact spelling turns a near
# miss into a wasted round, and a wasted round costs more than the tolerance
# does. Quotes may be single or double, `new` may be true/yes/1, the tags may
# be wrapped in markdown fences, and the marker rows may carry a trailing
# label (```<<<<<<< SEARCH home_view.dart```) as several tools emit.
FILE_RE = re.compile(
    r'<file\s+path=["\']([^"\']+)["\']'
    r'(?:\s+new=["\']?(?:true|yes|1)["\']?)?\s*>'
    r'\s*\n(.*?)\n?\s*</file>',
    re.DOTALL | re.IGNORECASE)
FILE_NEW_RE = re.compile(r'<file[^>]*\snew=["\']?(?:true|yes|1)["\']?',
                         re.IGNORECASE)
EXPAND_RE = re.compile(r'<expand\s+path=["\']([^"\']+)["\']\s*>(.*?)</expand>',
                       re.DOTALL | re.IGNORECASE)
BLOCK_RE = re.compile(
    r'^[ \t]*<{5,9}[ \t]*SEARCH[^\n]*\n(.*?)\n?'
    r'^[ \t]*={5,9}[ \t]*\n(.*?)\n?'
    r'^[ \t]*>{5,9}[ \t]*REPLACE[^\n]*$',
    re.DOTALL | re.MULTILINE | re.IGNORECASE)

# A model that wraps its answer in ```xml … ``` is not making a different
# claim, so the fence is stripped rather than rejected.
FENCE_RE = re.compile(r'^\s*```[\w-]*\s*\n(.*)\n\s*```\s*$', re.DOTALL)

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
        path, body = m.group(1), m.group(2)
        is_new = bool(FILE_NEW_RE.match(m.group(0)))
        fenced = FENCE_RE.match(body)
        if fenced:
            body = fenced.group(1)
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


def _reindented_match(current, search):
    """-> (start, end, actual_indent, search_indent) for a unique match that
    differs from `search` only in leading whitespace, else None.

    The belt to render_slices' brace. Getting indentation byte-exact through a
    model is the single most fragile part of a SEARCH/REPLACE format, and on
    issue #9 it cost four rounds. Comparing stripped lines recovers from that,
    and the UNIQUENESS check is what keeps it honest — if the stripped form
    occurs twice the edit is still refused, exactly as an ambiguous exact match
    would be.
    """
    want = [ln.strip() for ln in search.split('\n')]
    lines = current.split('\n')
    hits = []
    for i in range(len(lines) - len(want) + 1):
        if all(lines[i + j].strip() == want[j] for j in range(len(want))):
            hits.append(i)
    if len(hits) != 1:
        return None
    i = hits[0]
    first_real = next((j for j, w in enumerate(want) if w), 0)
    actual = lines[i + first_real][:len(lines[i + first_real])
                                   - len(lines[i + first_real].lstrip())]
    quoted = search.split('\n')[first_real]
    given = quoted[:len(quoted) - len(quoted.lstrip())]
    return i, i + len(want), actual, given


def _shift(text, from_indent, to_indent):
    out = []
    for ln in text.split('\n'):
        if ln.startswith(from_indent):
            out.append(to_indent + ln[len(from_indent):])
        else:
            out.append(ln)
    return '\n'.join(out)


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
            found = _reindented_match(current, e.search)
            if found:
                start, end, actual, given = found
                lines = current.split('\n')
                replacement = _shift(e.replace, given, actual)
                staged[e.path] = '\n'.join(
                    lines[:start] + replacement.split('\n') + lines[end:])
                continue
            errors.append(
                f'{e.path}: SEARCH text not found. It must match the file '
                f'byte for byte, INCLUDING leading whitespace. First line '
                f'looked for: {e.search.splitlines()[0][:120]!r}')
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
