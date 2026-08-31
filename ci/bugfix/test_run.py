#!/usr/bin/env python3
"""Verification for the loop that decides whether anything gets pushed.

WHY THIS EXISTS
---------------
`run.py` is short, but it is the only component that can push to `main`, and
its important behaviour is what it does when the model is WRONG — which, at
one to four calls per issue, is a routine event rather than an edge case. Those
paths are exactly the ones that never get exercised by a happy-path manual run,
so they are exercised here with a scripted model instead.

The model, GitHub and Flutter are all replaced with fakes. That is the point:
these tests are about control flow, and the real versions cost money, mutate a
public repository, and take four minutes respectively.

WHAT IS ASSERTED
----------------
  * a test that passes WITHOUT the fix is rejected — the gate that makes this
    pipeline stricter than the protocol it replaces;
  * a failing full suite never reaches `ship()`;
  * `expand` is answered with source rather than treated as an answer;
  * running out of rounds blocks the issue and pushes NOTHING;
  * a rebase conflict blocks rather than becoming a force-push;
  * the happy path ships exactly once.

Run:  python3 -m unittest discover -s ci/bugfix -p 'test_*.py'
"""
import unittest
from unittest import mock

import edits as edits_mod
import run


def answer(subject='Bugfix #1: do the thing', root='It was wrong.',
           code=True, test=True):
    parts = [f'<root-cause>{root}</root-cause>', f'<subject>{subject}</subject>']
    if code:
        parts.append('<file path="frontend/lib/a.dart">\n'
                     '<<<<<<< SEARCH\nold\n=======\nnew\n>>>>>>> REPLACE\n</file>')
    if test:
        parts.append('<file path="frontend/test/m999_x_test.dart" new="true">\n'
                     'void main() {}\n</file>')
    return '\n\n'.join(parts)


class Harness:
    """Scripts the model's replies and records what the pipeline did."""

    def __init__(self, replies):
        self.replies = list(replies)
        self.asked = []
        self.shipped = []
        self.blocked = []
        self.closed = []

    def ask(self, prefix, body, history=None, timeout=300):
        self.asked.append(body)
        return self.replies.pop(0), {'prompt_tokens': 9000,
                                     'prompt_cache_hit_tokens': 6000,
                                     'completion_tokens': 900}


class RunTest(unittest.TestCase):

    def drive(self, replies, gate=(True, '', ''), full=(True, '', ''),
              max_rounds=4):
        h = Harness(replies)
        with mock.patch.object(run.model, 'ask', h.ask), \
             mock.patch.object(run.gh, 'ensure_labels'), \
             mock.patch.object(run.gh, 'claim', return_value=True), \
             mock.patch.object(run.gh, 'issue',
                               return_value={'title': 'the floor is dark',
                                             'body': ''}), \
             mock.patch.object(run.gh, 'close',
                               side_effect=lambda n, b=None: h.closed.append(n)), \
             mock.patch.object(run.gh, 'block',
                               side_effect=lambda n, b: h.blocked.append(b)), \
             mock.patch.object(run.edits_mod, 'apply', return_value=[]), \
             mock.patch.object(run.verify, 'gate', return_value=gate), \
             mock.patch.object(run.verify, 'full_verification', return_value=full), \
             mock.patch.object(run, 'git_reset'), \
             mock.patch.object(run, 'ship',
                               side_effect=lambda *a, **k: h.shipped.append(a) or 'abc1234'), \
             mock.patch('sys.argv', ['run.py', '--issue', '1',
                                     '--max-rounds', str(max_rounds)]):
            code = run.main()
        return code, h

    def test_happy_path_ships_once(self):
        code, h = self.drive([answer()])
        self.assertEqual(code, 0)
        self.assertEqual(len(h.shipped), 1)
        self.assertEqual(h.closed, [1])
        self.assertEqual(h.blocked, [])

    def test_test_that_passes_without_the_fix_is_rejected(self):
        # The gate reports the rejection; the loop must retry, not ship.
        reason = 'the new test PASSES without your fix, so it pins nothing.'
        code, h = self.drive([answer(), answer()],
                             gate=(False, reason, 'log'), max_rounds=2)
        self.assertEqual(code, 1)
        self.assertEqual(h.shipped, [])
        self.assertEqual(len(h.blocked), 1)
        self.assertIn('pins nothing', h.blocked[0])
        # The second prompt must actually carry the reason back.
        self.assertIn('pins nothing', h.asked[1])

    def test_red_full_suite_never_ships(self):
        code, h = self.drive([answer(), answer()],
                             full=(False, '`flutter test` (full suite) fails', 'boom'),
                             max_rounds=2)
        self.assertEqual(h.shipped, [])
        self.assertEqual(len(h.blocked), 1)
        self.assertIn('full suite', h.blocked[0])

    def test_code_without_a_test_is_refused(self):
        code, h = self.drive([answer(test=False), answer()], max_rounds=2)
        self.assertEqual(len(h.shipped), 1)
        self.assertIn('no test', h.asked[1])

    def test_expand_is_answered_with_source_not_treated_as_an_answer(self):
        expand = '<expand path="frontend/lib/theme.dart">floor colour</expand>'
        code, h = self.drive([expand, answer()])
        self.assertEqual(code, 0)
        self.assertEqual(len(h.shipped), 1)
        self.assertIn('You asked to see more', h.asked[1])
        # And the served slice must be real source from the repo.
        self.assertIn('frontend/lib/theme.dart', h.asked[1])

    def test_unparseable_answer_is_sent_back(self):
        code, h = self.drive(['I think the problem is the colour.', answer()])
        self.assertEqual(code, 0)
        self.assertIn('could not be applied', h.asked[1])

    def test_rounds_are_bounded_and_block_pushes_nothing(self):
        code, h = self.drive([answer()] * 3, gate=(False, 'nope', 'log'),
                             max_rounds=3)
        self.assertEqual(code, 1)
        self.assertEqual(h.shipped, [])
        self.assertEqual(len(h.asked), 3)
        self.assertEqual(len(h.blocked), 1)

    def test_already_claimed_issue_costs_nothing(self):
        h = Harness([])
        with mock.patch.object(run.gh, 'ensure_labels'), \
             mock.patch.object(run.gh, 'issue',
                               return_value={'title': 't', 'body': ''}), \
             mock.patch.object(run.gh, 'claim', return_value=False), \
             mock.patch.object(run.model, 'ask', h.ask), \
             mock.patch('sys.argv', ['run.py', '--issue', '1']):
            self.assertEqual(run.main(), 0)
        self.assertEqual(h.asked, [])  # the model was never called

    def test_rebase_conflict_blocks_and_pushes_nothing(self):
        """`main` moving under a verified fix must not become a force-push."""
        h = Harness([answer()])
        with mock.patch.object(run.model, 'ask', h.ask), \
             mock.patch.object(run.gh, 'ensure_labels'), \
             mock.patch.object(run.gh, 'claim', return_value=True), \
             mock.patch.object(run.gh, 'issue',
                               return_value={'title': 't', 'body': ''}), \
             mock.patch.object(run.gh, 'block',
                               side_effect=lambda n, b: h.blocked.append(b)), \
             mock.patch.object(run.edits_mod, 'apply', return_value=[]), \
             mock.patch.object(run.verify, 'gate', return_value=(True, '', '')), \
             mock.patch.object(run.verify, 'full_verification',
                               return_value=(True, '', '')), \
             mock.patch.object(run, 'git_reset'), \
             mock.patch.object(run, 'ship',
                               side_effect=run.RebaseConflict('CONFLICT (content)')), \
             mock.patch('sys.argv', ['run.py', '--issue', '1']):
            code = run.main()
        self.assertEqual(code, 1)
        self.assertEqual(len(h.blocked), 1)
        self.assertIn('nothing was pushed', h.blocked[0])


class ExpandServingTest(unittest.TestCase):

    def test_serves_located_slices(self):
        import rank
        index = rank.Index()
        text = run.serve_expands(
            index, [edits_mod.Expand('frontend/lib/theme.dart', 'floor')],
            'floor colour')
        self.assertIn('frontend/lib/theme.dart', text)
        self.assertIn('```', text)

    def test_unknown_path_does_not_crash(self):
        import rank
        index = rank.Index()
        text = run.serve_expands(
            index, [edits_mod.Expand('frontend/lib/nope.dart', 'x')], 'q')
        self.assertIn('no such file', text)


if __name__ == '__main__':
    unittest.main()
