#!/usr/bin/env python3
"""Which files does this bug report point at?

WHY THIS EXISTS
---------------
The bug-report automation used to answer that question with the language
model: 88 to 227 `grep`/`sed` turns per issue, each one a full ~55,000-token
round trip whose only output was "now look over there". Measured across three
sessions that was 41-59 % of every run's turns and the single largest line in
the bill.

It is a retrieval problem, so it is solved here, in about 200 ms, for nothing.
The model is handed the answer instead of being charged to search for it.

WHAT MAKES THIS TRACTABLE IN THIS PARTICULAR REPO
-------------------------------------------------
Two properties of ipadprocad do most of the work:

1. **The app is written in German.** `l10n.yaml` names `app_de.arb` as the
   TEMPLATE, not the translation — so the 1089 user-facing strings are the
   vocabulary the user actually sees, and a bug report arrives in that same
   vocabulary ("der Boden", "Modellbrowser", "Aussehen"). Each string maps to
   an l10n key, and the key appears verbatim in the widget that draws it. So a
   German noun in an issue title is a nearly-direct index into the code. The
   English ARB is bridged too, because reports arrive in both.

2. **Bugs live in fresh code.** Every fix in AUTOMATION_NOTES.md so far landed
   in code touched by the last few milestones. Recency is therefore real
   evidence, not a tiebreaker, and it is weighted as such.

WHY BM25 AND NOT EMBEDDINGS
---------------------------
An embedding index would need a model call to build, a model call to query,
and somewhere to live between runs — reintroducing exactly the per-issue cost
this file removes. BM25 over identifier-split tokens needs no network, no
state, and no API key, and §"validation" in test_rank.py shows it puts a
correct file in the top 5 for all four issues the automation has fixed to
date. When it is wrong it is wrong *cheaply*, and the model can ask for one
more slice; that escalation costs about $0.004, against $1.49 for the search
it replaces.

WHY LENGTH NORMALISATION IS TURNED UP
-------------------------------------
`app_state.dart` is 19,550 lines and mentions nearly every noun in the app. At
BM25's usual b=0.75 it outranks the actual culprit on almost every query. b is
therefore 0.95 — very close to fully length-normalised — which is what pushes
`ribbon.dart` above it for the dropdown report. This is the one tuned constant
in the file and the reason it is called out here.

    ci/bugfix/rank.py "the triad should be a bit more on the left"
"""
import collections
import json
import math
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
FRONTEND = ROOT / 'frontend'

# Generated localisation lives in lib/l10n/gen and is committed (see l10n.yaml)
# — it restates every UI string in the app, so it matches every query and is
# never where a fix goes. Excluded, or it takes the whole top of the ranking.
EXCLUDE_DIRS = ('/l10n/gen', '/.dart_tool', '/build/', '/.symlinks')

# The Dart app, its plugin packages, and the Swift that backs them. Swift is in
# the corpus even though it cannot be COMPILED in the Linux sandbox: issues #7
# and #8 both needed a Dart change and a Swift change together, so leaving the
# platform code out would hide half of a cross-cutting fix.
SOURCE_SUFFIXES = ('.dart', '.swift')

# A path term is worth several body mentions: a file called `model_browser.dart`
# is about the model browser in a way that a file merely mentioning it is not.
PATH_WEIGHT = 4

# BM25. b is high on purpose — see the module docstring.
K1 = 1.2
B = 0.95

# How far back "recently touched" reaches, and how much it is worth. 60 commits
# is roughly the last few milestones in this repo's history.
RECENCY_COMMITS = 60
RECENCY_WEIGHT = 0.6

# An l10n key reached through the German/English bridge is strong evidence but
# indirect — the user typed the string, not the key — so it counts for half of
# a term the user actually wrote.
BRIDGE_WEIGHT = 0.5

# A word is only bridged if it unlocks FEWER than this many l10n keys.
#
# This bound is the lesson from issue #9 ("longpress a card and select export…").
# Its 13 query words unlocked 123 keys between them, because "select", "first",
# "want" and "location" each appear in dozens of UI strings. The expansion ended
# up carrying 79 % of the query's weight and pulled the ranking toward whichever
# files simply use the most l10n — `app_state.dart`, `ribbon.dart`. The file the
# fix actually belonged in, `home_view.dart`, fell to 20th and never made the
# pack; the model worked out where to go on its own and then guessed at code it
# had not been shown, four times.
#
# A word that appears in fifty strings is not evidence of anything. A word that
# appears in two or three — "Boden", "Fase", "Modellbrowser" — is nearly a
# pointer to the code, and those are exactly the ones this keeps.
#
# 22 is the middle of a plateau, not a fitted value: sweeping the five issues
# fixed to date, every cap from 18 to 26 gives recall@5 of 5/5, below 18 issue
# #5 loses `ribbon.dart`, and above ~30 issue #9 starts sliding back down. The
# middle is chosen so the constant is not sitting on an edge.
BRIDGE_MAX_KEYS = 22

# A line that DECLARES something is worth several that merely mention it.
#
# Issue #9 needed to add `partExportStl` beside the existing
# `partExportStep`. The slice of `app_state.dart` (19,550 lines) contained
# three mentions of that name in comments and none of its definition at line
# 7055 -- so the model had neither a template for how such a method is written
# nor an anchor to insert next to, and emitted a call to a method it never
# wrote. Scoring by query-word density alone finds discussion; adding a
# sibling function needs the sibling.
DECL_RE = re.compile(
    r'^\s*(?:@\w+\s+)*'
    r'(?:static\s+|final\s+|const\s+|abstract\s+|late\s+)*'
    r'(?:class|mixin|extension|enum|typedef|func|var|let)\s+\w+'
    r'|^\s*(?:@\w+\s+)*'
    r'(?:static\s+|external\s+|final\s+|const\s+|late\s+)*'
    r'(?:Future<[^>]*>|void|bool|int|double|String|num|dynamic|'
    r'Widget|List<[^>]*>|Map<[^>]*>|Set<[^>]*>|[A-Z]\w*<[^>]*>|[A-Z]\w*\??)'
    # `(` is a method, `;` a bare field, `=` an initialised one. Requiring
    # the paren — all this matched until issue #11 — sees only functions,
    # and a theming change is entirely fields: `final Color accent;` plus
    # the `accent: Color(0xFF2FA9A2),` row of each palette.
    r'\s+\w+\s*[(;=]'
    # A named argument in a const constructor. This repo builds its two
    # palettes that way (M236), so the line actually holding a colour is
    # of this shape and nothing above matches it.
    r'|^\s*\w+:\s*(?:Color|const|\[)')
DECL_BOOST = 4.0

# Prose is context; code is what gets edited.
#
# Issue #11 asked for a configurable accent colour. The slice of `theme.dart`
# came back as lines 12-56 — the file's header essay, which discusses the
# accent alongside "colour", "icons" and "highlight" and therefore outscored
# every real declaration — and not one of `final Color accent;` (line 90) or
# the two `accent: Color(0x…)` palette rows (349, 464). The model invented
# `static const Color accent = Color(0xFF3D9BE9);`, guessing even the hex from
# the reporter's "blueish green".
#
# This repo comments unusually heavily and unusually well, which is exactly why
# its comments crowd out its code under a plain term-frequency score.
COMMENT_RE = re.compile(r'^\s*(?://|///|/\*|\*|#)')
COMMENT_WEIGHT = 0.25

# A query word that occurs on only a handful of lines in a file is a POINTER to
# them, and the slice must contain them all.
#
# Weight-ranked neighbourhoods do not guarantee that. On issue #11, boosting
# declarations moved `theme.dart`'s slice from the header essay to lines
# 123-186 — a different, denser run of field declarations — and STILL missed
# every one of the three lines holding the accent colour, because summed
# term-weight favours wherever query words are thickest, not wherever the one
# word that matters actually is.
#
# So part of each file's budget is reserved: for the rarest query terms present,
# a tight window around each occurrence is included before the general
# neighbourhoods compete for what is left.
# Pointer terms are the ones that made THIS FILE rank, scored by their own BM25
# contribution to it — not the query's globally rarest words.
#
# Global rarity gets it wrong in both directions. Per-file rarity picked
# "which", "now" and "used", scarce in theme.dart and meaningless. Corpus IDF
# then picked "settings", "green" and "icons" — rare across the repo, but not
# what made theme.dart the answer. Only the per-file contribution names
# "accent", which is the whole reason this file is in the pack at all.
# Pointers come from the words the REPORTER TYPED, never from the l10n bridge.
# The bridge earns its place ranking files, but its expansions are not evidence
# about where to look inside one: on issue #11 the three rarest terms in the
# expanded query were `mat`, `backdrop` and `bad` — fragments of unrelated l10n
# keys — while `accent`, the only word that mattered, ranked ninth.
POINTER_TERMS = 5           # how many of the reporter's rarest words to guarantee
POINTER_SITES = 4           # occurrences of each to cover, declarations first
POINTER_RADIUS = 5
POINTER_BUDGET = 0.45       # share of a file's line budget reserved for them

# l10n key NAMING PREFIXES, dropped when a key is split into query terms.
#
# Keys in this repo are named `msgStepExportFailed`, `dlgNewSketch`,
# `phSketchName`. Splitting one into tokens yields the prefix as well as the
# content, and the prefix is a filing convention that says nothing about what
# the user asked for. It is not harmless: on issue #9 `msg` scored 22.3 of
# `app_state.dart`'s 72 — a third of its total, from tf=275 — and helped bury
# `mesh_io.dart` ("M232 — reading a MESH file: STL, OBJ, 3MF"), which is where
# an STL writer belongs and which the model asked for by name.
#
# Exactly one entry, and that is a measured choice rather than restraint for
# its own sake. Sweeping the five issues fixed to date: `msg` alone gives
# recall@5 of 5/5 and moves #9's `home_view.dart` from 2nd to 1st. Adding
# `dlg`/`btn` holds 5/5 but costs #7 a place, and any broader list — `wf`,
# `ov`, `tip` — drops #5's `ribbon.dart` out of the top five entirely. Those
# prefixes turn out to carry meaning; `msg` does not.
KEY_PREFIXES = frozenset(('msg',))


def split_identifier(text):
    """camelCase, snake_case and paths -> lowercase word tokens.

    `setFloorColor` has to match a report that says "floor", and `T.hover6` has
    to match "hover", or nothing in a Dart file matches anything a user writes.
    """
    spaced = re.sub(r'([a-z0-9])([A-Z])', r'\1 \2', text)
    return re.findall(r'[a-z0-9]{3,}', spaced.lower())


def _iter_sources(root):
    for base in ('lib', 'packages'):
        d = root / base
        if not d.is_dir():
            continue
        for path in d.rglob('*'):
            if path.suffix not in SOURCE_SUFFIXES or not path.is_file():
                continue
            rel = path.relative_to(ROOT).as_posix()
            if any(x in '/' + rel for x in EXCLUDE_DIRS):
                continue
            yield rel, path


def load_bridge(frontend=FRONTEND):
    """word (German or English) -> set of l10n keys that contain it.

    The template is German (l10n.yaml), so `app_de.arb` is the app's real
    vocabulary; `app_en.arb` is bridged too because reports arrive in English
    as often as not.
    """
    bridge = collections.defaultdict(set)
    for name in ('app_de.arb', 'app_en.arb'):
        arb = frontend / 'lib' / 'l10n' / name
        if not arb.is_file():
            continue
        data = json.loads(arb.read_text(encoding='utf-8'))
        for key, value in data.items():
            if key.startswith('@') or not isinstance(value, str):
                continue
            for word in re.findall(r'\w{4,}', value.lower()):
                bridge[word].add(key)
    return bridge


def _recency(root=ROOT):
    """path -> 0..1, newest touched file scoring highest."""
    try:
        out = subprocess.run(
            ['git', '-C', str(root), 'log', '--name-only',
             '--pretty=format:', f'-{RECENCY_COMMITS}'],
            capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.SubprocessError):
        return {}
    seen, rank = {}, 0
    for line in out.splitlines():
        line = line.strip()
        if line and line not in seen:
            seen[line] = max(0.0, 1.0 - rank / RECENCY_COMMITS)
            rank += 1
    return seen


class Index:
    """A BM25 index over the app's source, built fresh on every run.

    Building it costs a few hundred milliseconds against 140-odd files, which
    is cheaper than any scheme for keeping it warm between runs and cannot go
    stale against the checkout.
    """

    def __init__(self, root=ROOT):
        self.root = root
        self.texts = {}
        self.freqs = {}
        for rel, path in _iter_sources(root / 'frontend'):
            try:
                text = path.read_text(encoding='utf-8', errors='ignore')
            except OSError:
                continue
            self.texts[rel] = text
            tokens = split_identifier(text) + split_identifier(rel) * PATH_WEIGHT
            self.freqs[rel] = collections.Counter(tokens)
        self.n = max(len(self.freqs), 1)
        self.doc_freq = collections.Counter()
        for counter in self.freqs.values():
            self.doc_freq.update(counter.keys())
        lengths = [sum(c.values()) for c in self.freqs.values()]
        self.avg_len = (sum(lengths) / len(lengths)) if lengths else 1.0
        self.bridge = load_bridge(root / 'frontend')
        self.recency = _recency(root)

    def query_terms(self, query):
        """The user's words, plus the l10n keys those words unlock."""
        terms = collections.Counter()
        words = set(re.findall(r'\w{3,}', query.lower()))
        for word in words:
            terms[word] += 1.0
        for word in words:
            keys = self.bridge.get(word, ())
            if len(keys) >= BRIDGE_MAX_KEYS:
                continue
            for key in keys:
                for token in split_identifier(key):
                    if token in KEY_PREFIXES:
                        continue
                    terms[token] += BRIDGE_WEIGHT
        return terms

    def rank(self, query, limit=5):
        """-> [(path, score)], best first."""
        terms = self.query_terms(query)
        scored = {}
        for rel, counter in self.freqs.items():
            length = sum(counter.values()) or 1
            total = 0.0
            for term, weight in terms.items():
                freq = counter.get(term, 0)
                if not freq:
                    continue
                df = self.doc_freq[term]
                idf = math.log(1 + (self.n - df + 0.5) / (df + 0.5))
                norm = freq * (K1 + 1) / (freq + K1 * (1 - B + B * length / self.avg_len))
                total += weight * idf * norm
            if total:
                scored[rel] = total * (1 + RECENCY_WEIGHT * self.recency.get(rel, 0.0))
        return sorted(scored.items(), key=lambda kv: -kv[1])[:limit]

    def header_lines(self, rel, max_lines=44):
        """The file's imports, always. -> [(1, [lines])] or []

        Issue #9's ninth run wrote `NativeMenuItem(...)` into `app_state.dart`
        and the compiler said the type was not found. It does exist — but line
        12 of that file is

            import 'package:native_menu/native_menu.dart' show NativeMenu;

        a SELECTIVE import, so the type is genuinely not in scope. The model had
        no way to know: slices are query-matched regions from the middle of the
        file, and the import block never appeared in any of them.

        What is in scope, and how to widen it, is not something a retriever can
        guess is relevant — it is relevant to every edit. So it is unconditional.
        """
        lines = self.texts.get(rel, '').splitlines()
        if not lines:
            return []
        last = 0
        for i, line in enumerate(lines[:200]):
            if re.match(r'\s*(?:import|export|part|#include|@_exported)\b', line):
                last = i
        if not last:
            return []
        return [(1, lines[:min(last + 1, max_lines)])]

    def grep(self, rel, needles, radius=4, max_sites=24):
        """Every line mentioning any of `needles`, with context. -> [(start, [lines])]

        `expand` used to re-run the same query-weighted slicer that had already
        failed to show the model what it needed, so asking twice got two
        variations on one guess. Issue #11 is the case: theme.dart is 942 lines,
        the accent lives on three of them (a field and one row in each of two
        palettes), and no ranking of an 80-line budget reliably lands all three.

        A person asked "show me the accent lines" would grep. So does this, and
        it is exact rather than clever — which is the right division of labour,
        since by the time the model is asking it knows the name it wants.
        """
        lines = self.texts.get(rel, '').splitlines()
        if not lines:
            return []
        # Try the rarest needle on its own first. An `expand` query is prose —
        # "accent colour", "floor colour, Palette fields" — and its common word
        # matches everywhere, which forces sampling and then drops the very
        # lines that were asked for. The rare word is the request; the rest is
        # grammar. Broader needles are only used if the narrow one finds
        # nothing.
        # Rank needles by how often each names something DECLARED in this
        # file, not by rarity. Rarity picked "colour" over "accent" for issue
        # #11: this repo writes "color" in code and "colour" in its prose, so
        # the rarer word was the one that appears only in comments. What the
        # request is really asking for is a symbol, and a symbol is declared.
        def declaredness(needle):
            return sum(1 for ln in lines
                       if DECL_RE.match(ln) and needle in split_identifier(ln))
        ordered = sorted(needles, key=lambda n: (-declaredness(n),
                                                 self.doc_freq.get(n) or 10 ** 6))
        rows = []
        for attempt in (ordered[:1], ordered):
            if not attempt:
                continue
            rows = [i for i, line in enumerate(lines)
                    if any(n in split_identifier(line) or n in line
                           for n in attempt)]
            if rows:
                break
        if not rows:
            return []
        # Too many hits are SAMPLED ACROSS THE FILE, never truncated from the
        # top. Truncating is what made the first version useless for issue #11:
        # `accent colour` matched steadily through theme.dart's first three
        # hundred lines, the budget ran out there, and the two palette rows at
        # 349 and 464 — the whole point of the request — were never reached.
        if len(rows) > max_sites:
            step = len(rows) / max_sites
            rows = [rows[min(len(rows) - 1, int(k * step))]
                    for k in range(max_sites)]
        wanted = set()
        for i in rows:
            wanted.update(range(max(0, i - radius),
                                min(len(lines), i + radius + 1)))
        chunks, current, start = [], [], None
        for i in sorted(wanted):
            if start is None:
                start, current = i, [lines[i]]
            elif i == start + len(current):
                current.append(lines[i])
            else:
                chunks.append((start + 1, current))
                start, current = i, [lines[i]]
        if current:
            chunks.append((start + 1, current))
        return chunks

    def slice_around(self, rel, line, radius=30):
        """The neighbourhood of one line. -> [(start, [lines])]

        A compiler error names a file and a line; that is a better pointer than
        any query, so it is followed literally.
        """
        lines = self.texts.get(rel, '').splitlines()
        if not lines:
            return []
        i = max(0, min(len(lines) - 1, line - 1))
        lo = max(0, i - radius)
        hi = min(len(lines), i + radius + 1)
        return [(lo + 1, lines[lo:hi])]

    def slice_file(self, rel, query, radius=40, max_lines=260):
        """The parts of one file the query actually points at.

        Whole files are what made the old sessions expensive: `ribbon.dart` is
        2,902 lines and `app_state.dart` 19,550, and pasting either one costs
        more than the entire budget this pipeline is designed to fit inside.
        So the file is scored line by line and only the neighbourhoods that
        matched are emitted, with their real line numbers kept so the model can
        cite them and so a later `expand` request has something to name.
        """
        terms = self.query_terms(query)
        lines = self.texts.get(rel, '').splitlines()
        hits = []
        for i, line in enumerate(lines):
            tokens = set(split_identifier(line))
            weight = sum(w for t, w in terms.items() if t in tokens)
            if weight and COMMENT_RE.match(line):
                weight *= COMMENT_WEIGHT
            elif weight and DECL_RE.match(line):
                weight *= DECL_BOOST
            if weight:
                hits.append((weight, i))
        if not hits:
            return [(1, lines[:max_lines])] if lines else []

        # A hard cap, not an approximate one: the loop used to break AFTER
        # adding a whole neighbourhood, so a slice could overshoot its budget by
        # up to 2*radius. Every line here is billed at cache-miss prices on
        # every issue, so the budget is the budget.
        wanted = set()

        # Pointer terms first, so the lines the query actually names cannot be
        # crowded out by a denser passage elsewhere in the file.
        typed = set(re.findall(r'\w{3,}', query.lower()))
        counter = self.freqs.get(rel, {})
        length = sum(counter.values()) or 1
        contribution = {}
        for term in typed:
            freq = counter.get(term, 0)
            df = self.doc_freq.get(term, 0)
            if not freq or not df:
                continue
            idf = math.log(1 + (self.n - df + 0.5) / (df + 0.5))
            contribution[term] = idf * freq * (K1 + 1) / (
                freq + K1 * (1 - B + B * length / self.avg_len))
        rarest = sorted(contribution, key=lambda t: -contribution[t])[:POINTER_TERMS]
        reserved = int(max_lines * POINTER_BUDGET)
        sites = {}
        for term in rarest:
            rows = [i for i, ln in enumerate(lines)
                    if term in split_identifier(ln)]
            # A declaration of the thing beats a mention of it, so those sites
            # come first when there are more than the budget allows.
            rows.sort(key=lambda i: (not DECL_RE.match(lines[i]), i))
            # Sites must be SPREAD OUT. Four adjacent lines are one place, not
            # four: on issue #11 `accent`'s first four hits were lines 90, 161,
            # 163 and 171 — the Palette field block, where `onAccent` also
            # splits to "accent" — so the two palette rows at 349 and 464, the
            # lines that actually hold the colour, never made the list.
            spread = []
            for i in rows:
                if all(abs(i - j) > POINTER_RADIUS * 2 for j in spread):
                    spread.append(i)
                if len(spread) >= POINTER_SITES:
                    break
            if spread:
                sites[term] = spread

        # Round robin, not term by term. Taken in order, the first few terms
        # exhaust the reserve and the last never gets a site — which is exactly
        # what happened to `accent` on issue #11, where it ranked fifth of five.
        # Every pointer term gets its best site before any gets its second.
        for nth in range(POINTER_SITES):
            for term in rarest:
                rows = sites.get(term)
                if not rows or nth >= len(rows):
                    continue
                # The first pass is guaranteed; later ones respect the reserve.
                if nth and len(wanted) >= reserved:
                    break
                if len(wanted) >= max_lines:
                    break
                i = rows[nth]
                wanted.update(range(max(0, i - POINTER_RADIUS),
                                    min(len(lines), i + POINTER_RADIUS + 1)))

        for weight, i in sorted(hits, reverse=True):
            if len(wanted) >= max_lines:
                break
            wanted.update(range(max(0, i - radius), min(len(lines), i + radius + 1)))
        if len(wanted) > max_lines:
            wanted = set(sorted(wanted)[:max_lines])

        chunks, current, start = [], [], None
        for i in sorted(wanted):
            if start is None:
                start, current = i, [lines[i]]
            elif i == start + len(current):
                current.append(lines[i])
            else:
                chunks.append((start + 1, current))
                start, current = i, [lines[i]]
        if current:
            chunks.append((start + 1, current))
        return chunks


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip().splitlines()[-1].strip(), file=sys.stderr)
        return 2
    index = Index()
    query = ' '.join(argv[1:])
    print(f'{len(index.freqs)} files indexed\n')
    for i, (path, score) in enumerate(index.rank(query, limit=8), 1):
        print(f'{i:2}. {score:8.1f}  {path}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
