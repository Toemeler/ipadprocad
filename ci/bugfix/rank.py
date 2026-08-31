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
            for key in self.bridge.get(word, ()):
                for token in split_identifier(key):
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
            if weight:
                hits.append((weight, i))
        if not hits:
            return [(1, lines[:max_lines])] if lines else []

        wanted = set()
        for weight, i in sorted(hits, reverse=True):
            if len(wanted) >= max_lines:
                break
            wanted.update(range(max(0, i - radius), min(len(lines), i + radius + 1)))

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
