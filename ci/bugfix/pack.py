#!/usr/bin/env python3
"""Everything the model needs about one bug, assembled before it wakes up.

WHY THIS EXISTS
---------------
In the old sessions the model gathered its own context: clone, unzip, grep,
sed, read, re-read. Measured over three runs that was 65-77 % of all turns,
and because each turn replayed a ~55,000-token conversation it was most of the
cost. None of it needed a language model. It is done here instead, for free,
and the model's first turn already contains the answer to "what am I looking
at".

WHAT GOES IN, AND WHAT DELIBERATELY DOES NOT
--------------------------------------------
IN: the issue text, the bundle's own `report.md` (the app triages itself
already — it even says whether to read log.txt or state.txt), `env.txt`,
`reality.txt`, a bounded tail of `log.txt`, and slices of the five files the
retriever ranked highest.

OUT: `screenshot.png`. This is the expensive one. The old sessions installed
Pillow and counted pixels in it — 10 turns in one session, 39 in another —
while the bundle's own README says in as many words that the 3D body is a
RealityKit platform view composited outside Flutter and is therefore NOT in
the image. The evidence those turns were hunting for is in `reality.txt` and
`mesh.txt` as text, and both are included instead.

OUT: whole files. `ribbon.dart` is 2,902 lines and `app_state.dart` 19,550.
Pasting either costs more than this pipeline's entire budget, so `rank.py`
emits located slices and the model asks for more if it needs more.

THE PREFIX/BODY SPLIT IS LOAD-BEARING
-------------------------------------
DeepSeek's cache only hits on a byte-for-byte identical prefix starting at
token 0, and a hit costs $0.0441/M against $1.3184/M for a miss — a factor of
30. So `build()` returns the invariant part (house rules, repo map) separately
from the per-issue part, and `model.py` is careful to send them in that order
and never to let a timestamp, an issue number or a run id leak forward into
the prefix. Getting this wrong does not break anything; it just quietly
multiplies the input bill by thirty.
"""
import io
import json
import os
import pathlib
import re
import subprocess
import urllib.request
import zipfile

import rank

ROOT = pathlib.Path(__file__).resolve().parents[2]
FRONTEND = ROOT / 'frontend'

# Bundle members worth reading, in the order they help. `report.md` first
# because the app has already triaged itself in it.
BUNDLE_FILES = (
    ('report.md', 6000),
    ('env.txt', 800),
    ('reality.txt', 1500),
    ('mesh.txt', 1200),
)

# The report is written at the END of the session, so the interesting lines are
# the last ones. 60 is enough to carry the failure and its lead-up without
# carrying the whole 8,000-line session.
LOG_TAIL_LINES = 60

# A raw pointer stream, only worth its tokens when the complaint is that a
# gesture did the wrong thing.
GESTURE_WORDS = ('tap', 'drag', 'swipe', 'pinch', 'gesture', 'touch', 'press',
                 'tippen', 'ziehen', 'wischen', 'druck')

FILES_IN_PACK = 6

# How many existing l10n entries to show. Enough to convey the naming
# conventions and to reveal a key that already says the thing, not so many that
# 1089 strings arrive at cache-miss prices.
L10N_ENTRIES = 24

# Lines of source the pack may spend, per rank. The top-ranked file gets more
# than twice the last's because the ranking is informative: measured over the
# issues fixed to date, when the culprit is in the pack at all it is usually in
# the first three.
#
# THE FIRST VERSION OF THIS WAS TOO MEAN, and the arithmetic says why. A
# thousand lines of slice is about a cent at cache-miss prices. A rejected
# round is five to ten cents and twenty minutes, and of the ten pipeline
# defects found so far, NINE were the pipeline withholding something the model
# needed — an import, a declaration, the error text, the SEARCH that failed.
# Starving the pack to save a tenth of a cent while spending a nickel on the
# round it causes is a false economy. Sum ≈ 650 lines ≈ 8k tokens.
SLICE_BUDGET = (170, 140, 110, 90, 70, 70)

# Boilerplate the relay appends to every report. It is not description, it is
# plumbing — `fetch_bundle` reads the URL out of the raw body and the ranker
# should never see it. Left in, `bug`, `reports`, `zip`, `github` and `raw` are
# half the query on a short report: issue #11 ("make the accent color ...
# changable in the settings") ranked `bug_capture.dart` and `bug_button.dart`
# above `theme.dart`, the one file the house rules allow a colour to live in.
BUNDLE_LINE_RE = re.compile(r'^\s*(?:Bundle|Raw zip)\s*:\s*\S+\s*$',
                            re.MULTILINE | re.IGNORECASE)


def ranking_query(title, body):
    """What the retriever should read: the report, without the plumbing."""
    return f'{title}\n{BUNDLE_LINE_RE.sub("", body or "")}'.strip()


# Files a house rule makes MANDATORY for a kind of change. The rules already
# tell the model "every colour lives in theme.dart, and m236_theme_test fails
# the build if one is written anywhere else" — so a report about colour that
# does not carry theme.dart is a pack the model cannot answer from, however
# well BM25 ranked the rest. Term frequency cannot see this: the places that
# USE a colour mention it far more often than the one place allowed to define
# it, and on #11 that put a 942-line theme.dart eighth.
# Ordered MOST SPECIFIC FIRST. The first two that appear in the report become
# the grep needles below, so `accent` is used and `color` — which matches five
# hundred lines of theme.dart and would force the sampler to throw away the
# three that matter — is not.
PINNED = (
    (('akzent', 'accent', 'tint', 'palette', 'farbe', 'highlight', 'colour',
      'color', 'theme'), 'frontend/lib/theme.dart'),
)

# How many needle words a pinned file is sliced by.
PINNED_NEEDLES = 2

# Distinct places in a pinned file to show, at 13 lines each. Generous on
# purpose: this is the file the change MUST be written in, and on theme.dart
# the accent has nine — a field, two palette rows, a getter, the Material
# bridge — of which the fix touches at least three. ~120 lines is a sixth of a
# cent; the round it saves is a nickel.
PINNED_SITES = 12


# Where a pinned file lands. Not last, and not first: the slice budget is
# ordered, and the file the change must be WRITTEN in cannot be the one that
# gets the thinnest peek — but the report's own top hits are where the symptom
# is, and they earned their place.
PINNED_RANK = 2


def pinned_needles(query, path):
    """-> the trigger words a pinned file should be grepped for, or ()."""
    words = set(re.findall(r'[a-zA-Z]+', query.lower()))
    for triggers, pinned_path in PINNED:
        if pinned_path != path:
            continue
        return tuple(t for t in triggers if t in words)[:PINNED_NEEDLES]
    return ()


def pin(query, ranked, limit):
    """Promote a mandatory file to PINNED_RANK, whatever BM25 made of it."""
    for triggers, path in PINNED:
        if not pinned_needles(query, path):
            continue
        scores = dict(ranked)
        if path not in scores:
            continue  # not in the index at all; nothing to promote
        rest = [r for r in ranked if r[0] != path]
        ranked = (rest[:PINNED_RANK] + [(path, scores[path])]
                  + rest[PINNED_RANK:])
    return ranked


def _bundle_url(body):
    m = re.search(r'https://raw\.githubusercontent\.com/\S+\.zip', body or '')
    if m:
        return m.group(0)
    m = re.search(r'bugreports/([A-Za-z0-9._-]+\.zip)', body or '')
    if m:
        return m.group(1)
    return None


def fetch_bundle(issue_body):
    """-> ZipFile or None. Tries the checkout first, the network second.

    `git show bug-reports:...` costs nothing when the branch is already
    fetched, which it is inside the workflow. The raw URL is the fallback for
    running this by hand.
    """
    ref = _bundle_url(issue_body)
    if not ref:
        return None
    name = ref.rsplit('/', 1)[-1]
    try:
        blob = subprocess.run(
            ['git', '-C', str(ROOT), 'show', f'origin/bug-reports:bugreports/{name}'],
            capture_output=True, timeout=60)
        if blob.returncode == 0 and blob.stdout[:2] == b'PK':
            return zipfile.ZipFile(io.BytesIO(blob.stdout))
    except (OSError, subprocess.SubprocessError):
        pass
    if ref.startswith('http'):
        try:
            with urllib.request.urlopen(ref, timeout=60) as resp:
                return zipfile.ZipFile(io.BytesIO(resp.read()))
        except Exception:
            return None
    return None


def _read(zf, name, limit):
    try:
        text = zf.read(name).decode('utf-8', 'replace')
    except KeyError:
        return None
    if name == 'report.md':
        # `report.md` ends with a "## Contents" section explaining what each
        # bundle member is. It is byte-identical in every report — 1,121 of the
        # file's 2,051 characters — and arrives as a cache MISS on every issue
        # at $1.3184/M. The same guidance lives in the stable prefix instead,
        # where it is billed once and then cached (see BUNDLE_GUIDE).
        cut = text.find('\n## Contents')
        if cut > 0:
            text = text[:cut]
    return text if len(text) <= limit else text[:limit] + '\n… (truncated)\n'


def bundle_evidence(zf, issue_text):
    """The readable parts of the diagnostic bundle, bounded."""
    if zf is None:
        return '_(no diagnostic bundle could be fetched)_'
    out = []
    for name, limit in BUNDLE_FILES:
        text = _read(zf, name, limit)
        if text:
            out.append(f'### {name}\n```\n{text.strip()}\n```')
    log = _read(zf, 'log.txt', 400000)
    if log:
        tail = '\n'.join(log.splitlines()[-LOG_TAIL_LINES:])
        out.append(f'### log.txt (last {LOG_TAIL_LINES} lines)\n```\n{tail}\n```')
    if any(w in issue_text.lower() for w in GESTURE_WORDS):
        g = _read(zf, 'gestures.txt', 2500)
        if g:
            out.append(f'### gestures.txt\n```\n{g.strip()}\n```')
    return '\n\n'.join(out) if out else '_(bundle contained nothing readable)_'


def repo_map(index):
    """A one-screen orientation, invariant across issues so it stays cached."""
    groups = {}
    for path in sorted(index.freqs):
        groups.setdefault(str(pathlib.PurePosixPath(path).parent), []).append(
            pathlib.PurePosixPath(path).name)
    lines = []
    for d, names in sorted(groups.items()):
        lines.append(f'{d}/  ' + ' '.join(sorted(names)))
    return '\n'.join(lines)


# What the bundle's members are. Identical for every report, so it lives in the
# cached prefix rather than being re-billed inside each `report.md`.
#
# The screenshot line is the expensive one to get wrong: two of the three
# measured sessions spent 10 and 39 turns respectively counting pixels in an
# image that cannot contain the thing they were looking for.
BUNDLE_GUIDE = '''\
Every report ships the same diagnostic bundle:

- `report.md` — the app's own triage, including whether `log.txt` or
  `state.txt` is the file worth reading for this fault.
- `state.txt` — every feature with its parameters and its solid or error, every
  picked edge fingerprint, every sketch with its geometry and constraints.
- `log.txt` — the session, ending at the moment the report was filed.
- `reality.txt` — the last scene Dart handed the native renderer.
- `mesh.txt` — triangle and vertex counts of what was actually drawn.
- `gestures.txt` — the raw pointer stream, before the gesture arena resolved
  it. Read this when the complaint is that a tap or drag did the wrong thing.
- `screenshot.png` — **not included here and not worth asking for.** The 3D
  body is a RealityKit platform view composited outside Flutter, so the shaded
  model is NEVER in the image and an empty-looking viewport is not evidence of
  anything. Use `reality.txt`, `mesh.txt` and `state.txt` for the body.'''


def merge_chunks(chunks):
    """Overlapping ranges from one file, folded into one ordered set.

    `header_lines` and the slicer are independent, so they overlap constantly:
    on issue #11 every file in the pack shipped its first thirty lines twice
    and `ribbon.dart` shipped lines 19-29 as a whole second slice INSIDE the
    header it had just printed. Paid for at cache-miss prices, and read by the
    model as two separate places.
    """
    text = {}
    for start, lines in chunks:
        for n, line in enumerate(lines):
            text.setdefault(start + n, line)
    out, current, first = [], [], None
    for n in sorted(text):
        if first is None or n != first + len(current):
            if current:
                out.append((first, current))
            first, current = n, [text[n]]
        else:
            current.append(text[n])
    if current:
        out.append((first, current))
    return out


def render_slices(path, chunks):
    """Source the model can copy byte for byte.

    The line numbers used to be a gutter on every line (`  485  code`). That is
    unusable for a SEARCH/REPLACE format: the model has to strip a seven-column
    prefix to recover the text, and on issue #9 it got it wrong -- it copied
    `_sendFile`'s signature with four spaces of indentation where the file has
    two, and every edit was rejected as not matching byte for byte.

    The range goes in a header, where it still locates the code but cannot end
    up inside it.
    """
    parts = []
    for start, body in chunks:
        end = start + len(body) - 1
        parts.append(f'# {path} lines {start}-{end}\n'
                     + '\n'.join(body))
    return f'### {path}\n```dart\n' + '\n\n'.join(parts) + '\n```'


def l10n_slice(query, frontend=FRONTEND, limit=L10N_ENTRIES):
    """The localisation entries this issue is likely to need.

    WHY THIS IS IN THE PACK AT ALL
    ------------------------------
    The retriever's corpus is `.dart` and `.swift`, so until now the model
    could not see `app_de.arb` at all. That makes every change adding
    user-facing text impossible to get right: it cannot tell whether a suitable
    key already exists, it cannot follow the naming convention, and it cannot
    know that a key added to one file and not the other fails
    `l10n_completeness_test.dart` and therefore the whole run.

    Issue #9 needs exactly this — a format picker has to say "STL" and "STEP"
    and have a title — and it is the reason the pack now carries l10n.

    The files are 124 KB and 55 KB, so they arrive as a slice: entries whose
    GERMAN OR ENGLISH TEXT matches the report, which is the same trick the
    ranker uses, plus their placeholder metadata.
    """
    de_path = frontend / 'lib' / 'l10n' / 'app_de.arb'
    en_path = frontend / 'lib' / 'l10n' / 'app_en.arb'
    if not de_path.is_file():
        return ''
    de = json.loads(de_path.read_text(encoding='utf-8'))
    en = json.loads(en_path.read_text(encoding='utf-8')) if en_path.is_file() else {}

    # Tokenised, not raw text: a substring test matches "card" inside
    # "discard" and puts `tipDiscardEsc` above `msgStepExportFailed`.
    entries = {}
    for k, v in de.items():
        if k.startswith('@') or not isinstance(v, str):
            continue
        blob = f'{k} {v} {en.get(k, "")}'
        entries[k] = set(rank.split_identifier(blob)) | set(
            re.findall(r'\w{3,}', blob.lower()))

    # Rare words carry the meaning. Counting raw hits instead surfaces whatever
    # matches "select" or "first" — 100+ entries each in this ARB — and buries
    # `exportEllipsis`. Same lesson as BRIDGE_MAX_KEYS in rank.py, same fix.
    words = set(re.findall(r'\w{3,}', query.lower()))
    freq = {w: sum(1 for t in entries.values() if w in t) for w in words}
    scored = []
    for key, tokens in entries.items():
        score = sum(1.0 / (1 + freq[w]) for w in words if w in tokens)
        if score:
            scored.append((score, key))
    scored.sort(reverse=True)

    lines = []
    for _, key in scored[:limit]:
        meta = de.get('@' + key)
        suffix = f'   // {json.dumps(meta, ensure_ascii=False)}' if meta else ''
        lines.append(f'  "{key}": {json.dumps(de[key], ensure_ascii=False)}'
                     f'   /  {json.dumps(en.get(key, ""), ensure_ascii=False)}{suffix}')
    if not lines:
        return ''
    return ('Existing entries related to this report, as `key: German / English`:\n\n'
            + '\n'.join(lines))


def l10n_rules():
    return """\
The app's user-facing text lives in `frontend/lib/l10n/app_de.arb` (the
TEMPLATE — German is the source language) and `frontend/lib/l10n/app_en.arb`
(the translation). Both are plain JSON, one flat object, `"key": "text"`.

If your fix adds or changes any text the user can see:

- Add the key to BOTH files, with the German in `app_de.arb`. A key in only one
  fails `l10n_completeness_test.dart`, and that fails the whole run.
- Follow the neighbouring names: `dlg…` for dialog titles, `msg…` for messages,
  `btn…`/plain verbs for buttons, `ph…` for placeholders, `ctx…` for context
  menu items.
- Reach it in code as `L.of(context)` — conventionally `final t = L.of(context);`
  then `t.yourKey`.
- Do NOT touch `frontend/lib/l10n/gen/` — it is generated from the ARBs by
  `gen-l10n` on every build, and the pipeline regenerates it for you after your
  edits land.
- Check the entries below first: the string you need may already exist."""


def house_rules():
    return '''\
- German is the app's SOURCE language. `frontend/lib/l10n/app_de.arb` is the
  l10n TEMPLATE and `app_en.arb` the translation. A key added to one MUST be
  added to the other or `l10n_completeness_test.dart` fails the build.
- Minimal, surgical diffs: do not change what the report did not ask about. This
  is NOT "write as little code as possible" — a report asking for behaviour the
  app lacks needs that behaviour built, new functions and new files included.
- No unrelated refactors, no speculative abstractions, no new dependencies.
- Comments only where they explain a non-obvious WHY. Never restate the code.
- USER-FACING CHROME IS NATIVE, NOT MATERIAL. This app's own history is a long
  march away from Flutter's Material widgets: M266 replaced two Material
  circles on the gallery header because "they seem like flutter, and they
  were". Do not introduce `SimpleDialog`, `AlertDialog`, `showDialog`,
  `SnackBar`, `PopupMenuButton` or Material buttons in the UI. Use what the app
  already has — `promptForText` in `frontend/lib/widgets/native_prompts.dart`,
  `NativeMenu`/`NativeMenuItem` from the `native_menu` package, the glass
  toolbars and tab bars — and follow the nearest existing call site.
- Tests import through `package:prototype/…`, never a relative `../lib/…` path.
- NATIVE SURFACES HAVE A FLUTTER FALLBACK, AND THE TEST RUNS THE FALLBACK. The
  settings sheet, the model browser and the menus all branch on
  `NativeMenu.isSupported` / `GlassBrowser.isSupported`: native on iOS, a
  Flutter widget everywhere else. A host test is "everywhere else", so a widget
  test only ever sees the fallback branch. If you add something to one branch,
  add it to BOTH — otherwise the feature works on device and your own test
  cannot find it.
- Match the style of the code you are editing, including its milestone-tagged
  comment convention (`// M284 — …`) when you add a comment near one.
- Swift under `frontend/packages/*/ios/` CANNOT be compiled on Linux. Changing
  it is fine and often necessary; it is verified by CI's macOS build, not here.
- Never edit `.github/workflows/*`, `relay/*`, `ci/*`, or generated files under
  `lib/l10n/gen/` (those are regenerated by the build).
- EVERY COLOUR LIVES IN `theme.dart`. `Color(0x…)` written anywhere else fails
  `m236_theme_test.dart` ("no colour is written inline outside theme.dart"),
  which fails the run. To add one: add a field to `Palette`, add a row for it
  to BOTH palettes (`kChalk` and `kEmber`), add a `static Color get x =>
  scheme.value.x;` to `T`, and read it as `T.x` everywhere else. The same test
  also holds every colour to WCAG contrast in both schemes.
- If you use a type a file does not already import, ADD THE IMPORT. Each slice
  begins with that file's import block, so what is in scope is visible — and a
  selective `show` clause means a name from that package may still need adding
  to it.
- Fix the root cause, not the symptom. This codebase's history punishes surface
  patches.'''


def notes_tail(limit=8):
    """The last few AUTOMATION_NOTES entries — prior art, cheaply."""
    p = ROOT / 'bugreports' / 'AUTOMATION_NOTES.md'
    if not p.is_file():
        return ''
    entries = [ln for ln in p.read_text(encoding='utf-8').splitlines()
               if ln.startswith('- #')]
    return '\n'.join(entries[-limit:])


def build(issue_number, title, body, index=None, files=FILES_IN_PACK):
    """-> (stable_prefix, per_issue_body, [paths]).

    The two halves are returned separately because the first is what DeepSeek
    caches between runs and the second is what it cannot.
    """
    index = index or rank.Index()
    query = ranking_query(title, body)
    zf = fetch_bundle(body or '')
    evidence = bundle_evidence(zf, query)

    ranked = pin(query, index.rank(query, limit=files + 6), files)[:files]
    slices = []
    for position, (path, _) in enumerate(ranked):
        budget = SLICE_BUDGET[min(position, len(SLICE_BUDGET) - 1)]
        # A pinned file is grepped, not query-sliced. The query slicer scores
        # line by line and then merges neighbourhoods, so on theme.dart it
        # spent issue #11's whole budget on one 46-line run of `final Color x;`
        # field declarations and never reached `accent: Color(0xFF2FA9A2)` in
        # either palette — the two lines the fix has to edit. `grep` samples
        # its hits ACROSS the file, which is what a person asked to show the
        # accent lines would do.
        needles = pinned_needles(query, path)
        matched = (index.grep(path, needles, radius=6,
                              max_sites=PINNED_SITES)
                   if needles else
                   index.slice_file(path, query, radius=22, max_lines=budget))
        chunks = merge_chunks(index.header_lines(path) + matched)
        slices.append(render_slices(path, chunks))

    prefix = f'''\
## The repository

`Toemeler/ipadprocad` — a Flutter iPad CAD app with a QCAD/OpenCASCADE C++
backend reached over FFI, plus Swift platform plugins for the RealityKit
viewport and the Liquid Glass chrome.

{repo_map(index)}

## House rules

{house_rules()}

## The diagnostic bundle

{BUNDLE_GUIDE}

## Localisation

{l10n_rules()}'''

    issue_body = f'''\
## Issue #{issue_number}

**{title}**

{(body or "_(no description given)_").strip()}

## Diagnostic bundle

{evidence}

## Previously fixed in this repo

{notes_tail() or "_(none recorded)_"}

## Localisation entries you may need

{l10n_slice(query) or "_(no closely related entries; follow the conventions above)_"}

## Candidate code

These are the {len(slices)} files the retriever ranked highest for this report,
sliced around the matching lines; each slice is headed with the line range it
came from. The code inside is VERBATIM — copy your SEARCH text from it exactly,
including its leading whitespace. If the fix belongs somewhere not shown here,
say so with an `expand` request instead of guessing.

{chr(10).join(slices)}'''

    return prefix, issue_body, [p for p, _ in ranked]


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('issue', type=int)
    args = ap.parse_args()
    import gh
    data = gh.issue(args.issue)
    prefix, body, paths = build(args.issue, data['title'], data.get('body') or '')
    print(prefix)
    print(body)
    total = len(prefix) + len(body)
    print(f'\n--- pack: {total} chars, ~{total // 4} tokens, files={paths}',
          file=__import__('sys').stderr)


if __name__ == '__main__':
    main()
