#!/usr/bin/env python3
"""Verification for the retriever the bug-fix pipeline is built on.

WHY THIS EXISTS
---------------
`rank.py` replaces the step that used to cost the most: the model reading the
tree one `grep` at a time. Everything downstream assumes the right file is in
the pack. If the ranker silently degrades — someone renames a widget, the ARB
bridge stops loading, the recency window drifts — the pipeline does not crash.
It quietly starts handing the model the wrong five files, and the model starts
writing plausible patches for code that is not broken. That failure is
expensive and invisible, so it is pinned here.

WHAT IS ASSERTED, AND WHY IT IS THIS AND NOT AN ACCURACY NUMBER
---------------------------------------------------------------
The four cases below are the four issues the automation has actually fixed, as
recorded in bugreports/AUTOMATION_NOTES.md, scored from THE ISSUE TITLE ALONE
— the same text the pipeline gets before it has spent a token. The expected
file is the one the shipped commit really touched.

The bar is recall@5, not rank-1. The pipeline sends five slices and the model
picks; demanding that the ranker be right on the first try would be asserting
something the design does not need and does not get (`ribbon.dart` is 3rd for
issue #5, and that is fine). Recall@5 is the property the pack actually
depends on.

A case is allowed to name several files: issues #7 and #8 were cross-cutting
fixes, and finding EITHER end of one is enough to put the model in the right
subsystem. That is a deliberate weakening — see the honest note in
`test_known_misses`, which records what this retriever does not find so that
nobody mistakes recall@5 for "it finds the whole fix".

Run:  python3 -m unittest discover -s ci/bugfix -p 'test_*.py'
"""
import unittest

import rank


# (issue, title as filed, files whose top-5 presence counts as a hit)
#
# Titles are the real ones from the webhook payloads, truncated by GitHub at
# 120 characters exactly as the relay files them — including the typos, which
# are load-bearing: this is what the retriever is actually given.
CASES = [
    (5,
     'the dropdowns color and rendered or with edges is somehow dark and '
     'doesnt really fit in the liquidglass ribbon. change t',
     ['frontend/lib/widgets/ribbon.dart']),
    (6,
     'the triad should be a bit more on the left. right next to the left border',
     ['frontend/lib/widgets/viewport3d.dart',
      'frontend/lib/widgets/viewport_assembly.dart']),
    (7,
     'no way to hide the rendered floor, i want a checkbox to display the floor',
     ['frontend/lib/widgets/ribbon.dart',
      'frontend/lib/part_model.dart']),
    (8,
     'The icons in the Modell browser do not switch colors based on what is '
     'behind them. if there is a dark part which is behi',
     ['frontend/lib/theme.dart',
      'frontend/lib/widgets/model_browser.dart']),
    # #9 is the case that set BRIDGE_MAX_KEYS. It is an interaction bug, not a
    # styling one, so its words ("select", "location", "first") are common in
    # the ARB and used to swamp the query — `home_view.dart` ranked 20th and
    # never entered the pack.
    (9,
     'when i longpress a card and select export i first want to select stl or '
     'step before chosing a location',
     ['frontend/lib/widgets/home_view.dart']),
]


class TestRanking(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.index = rank.Index()

    def test_corpus_is_not_empty(self):
        # A silent empty corpus would make every other assertion here vacuous.
        self.assertGreater(len(self.index.freqs), 100)

    def test_generated_l10n_is_excluded(self):
        # lib/l10n/gen restates every UI string, so it matches every query and
        # is never where a fix goes. If it ever re-enters the corpus it takes
        # the top three slots and the pack becomes useless.
        for path in self.index.freqs:
            self.assertNotIn('/l10n/gen/', '/' + path)

    def test_german_bridge_loaded(self):
        # The template is German (l10n.yaml). Without this bridge a report
        # saying "Boden" cannot reach `showFloor`.
        self.assertGreater(len(self.index.bridge), 500)
        self.assertIn('boden', self.index.bridge)

    def test_recall_at_5(self):
        for issue, title, expected in CASES:
            with self.subTest(issue=issue):
                ranked = [p for p, _ in self.index.rank(title, limit=5)]
                self.assertTrue(
                    any(e in ranked for e in expected),
                    f'issue #{issue}: none of {expected} in top 5: {ranked}')

    def test_slices_are_bounded_and_located(self):
        # The whole point of slicing is that `ribbon.dart` (2,902 lines) never
        # arrives whole. A slice also has to carry its real starting line, or
        # the model cannot cite it and `expand` has nothing to name.
        chunks = self.index.slice_file(
            'frontend/lib/widgets/ribbon.dart', CASES[0][1])
        self.assertTrue(chunks)
        total = sum(len(body) for _, body in chunks)
        self.assertLessEqual(total, 300)
        for start, body in chunks:
            self.assertGreaterEqual(start, 1)
            self.assertTrue(body)

    def test_known_misses(self):
        """The retriever's honest limits, recorded rather than hidden.

        Both of these fixes were cross-cutting and the ranker finds only one
        end of each from the title. That is why the pipeline gives the model an
        `expand` request instead of a fixed five files, and why `run.py` serves
        the file back when an edit fails against code that was never shown.

        This asserts the CURRENT behaviour: if a tuning change ever makes these
        hit, that is good news and the test should be tightened to demand it.
        """
        top5 = {issue: [p for p, _ in self.index.rank(title, limit=5)]
                for issue, title, _ in CASES}
        self.assertNotIn('frontend/lib/theme.dart', top5[8])
        self.assertNotIn('frontend/lib/part_model.dart', top5[7])

    def test_bridge_is_capped_to_discriminative_words(self):
        """The #9 regression: common words must not swamp the query.

        Without the cap, issue #9's 13 words unlocked 123 l10n keys and the
        expansion carried 79 % of the query's weight, pulling the ranking
        toward whichever files merely use the most l10n.
        """
        import re
        title = CASES[-1][1]
        words = set(re.findall(r'\w{3,}', title.lower()))
        terms = self.index.query_terms(title)
        bridged = sum(v for k, v in terms.items() if k not in words)
        self.assertLess(bridged / sum(terms.values()), 0.5)
        # A rare, meaningful word must still bridge — that is the whole point.
        self.assertLess(len(self.index.bridge['boden']), rank.BRIDGE_MAX_KEYS)


if __name__ == '__main__':
    unittest.main()
