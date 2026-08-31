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
  * a failed edit sends the file's real source back, not just the error;
  * EVERY losing path records why, so the blocked comment is never blank;
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
        reply = self.replies.pop(0)
        truncated = isinstance(reply, tuple)
        if truncated:
            reply = reply[0]
        return reply, {'prompt_tokens': 9000,
                       'prompt_cache_hit_tokens': 6000,
                       'completion_tokens': 900}, truncated


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

    def test_expanding_forever_is_refused(self):
        # Issue #9's third run spent all four rounds asking to see
        # occt_engine.dart, hunting an STL exporter that is not in this repo.
        e = '<expand path="frontend/lib/ffi/occt_engine.dart">stl</expand>'
        code, h = self.drive([e, e, e, e], max_rounds=4)
        self.assertEqual(h.shipped, [])
        self.assertIn('does not exist yet', h.asked[2])
        self.assertIn('building', h.asked[3].lower())

    def test_a_repeated_expand_is_told_it_is_a_repeat(self):
        e = '<expand path="frontend/lib/theme.dart">floor</expand>'
        code, h = self.drive([e, e, answer()], max_rounds=3)
        self.assertIn('already been shown', h.asked[2])
        self.assertIn('build it', h.asked[2])

    def test_a_packed_file_is_never_re_served(self):
        # The pack's own five files are already in front of the model.
        import rank
        index = rank.Index()
        already = {'frontend/lib/theme.dart'}
        text = run.serve_expands(
            index, [edits_mod.Expand('frontend/lib/theme.dart', 'floor')],
            'q', already)
        self.assertIn('already been shown', text)

    def test_truncated_answer_asks_for_a_smaller_edit(self):
        # A cut-off answer is not a formatting mistake, and saying so is what
        # stops the model repeating the whole-file rewrite that caused it.
        code, h = self.drive([('<file path="frontend/lib/a.dart">\n<<<<<<< SEA',),
                              answer()])
        self.assertEqual(code, 0)
        self.assertIn('cut off at the output limit', h.asked[1])
        self.assertIn('SMALLER', h.asked[1])

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



class RepairPromptTest(unittest.TestCase):
    """Issue #9's lesson: a failed SEARCH must come back WITH the file.

    The retriever had ranked `home_view.dart` 20th, so it never entered the
    pack. The model worked out unaided that the fix belonged there and wrote a
    SEARCH block for code it had not been shown; that cannot match byte for
    byte. Because the repair prompt carried only "SEARCH text not found", it
    guessed again, four times, for $0.097 and no fix.
    """

    @classmethod
    def setUpClass(cls):
        import rank
        cls.index = rank.Index()

    def test_failed_paths_extracts_files_from_apply_errors(self):
        errs = [
            'frontend/lib/widgets/home_view.dart: SEARCH text not found. It '
            'must match the file byte for byte.',
            'frontend/lib/theme.dart: SEARCH text appears 2 times',
            'frontend/lib/widgets/home_view.dart: no such file',
            'no <file> blocks found',
        ]
        self.assertEqual(
            run.failed_paths(errs),
            ['frontend/lib/widgets/home_view.dart', 'frontend/lib/theme.dart'])

    def test_repair_prompt_carries_the_source(self):
        text = run.repair_prompt(
            self.index, 'the code edits did not apply',
            'frontend/lib/widgets/home_view.dart: SEARCH text not found.',
            'longpress a card and select export',
            ['frontend/lib/widgets/home_view.dart'])
        self.assertIn('did not apply', text)
        self.assertIn('as it actually reads', text)
        self.assertIn('home_view.dart', text)
        self.assertIn('```dart', text)
        # And it must be real source, with real line numbers, not a placeholder.
        self.assertNotIn('no such file', text)

    def test_repair_prompt_without_a_named_file_stays_short(self):
        text = run.repair_prompt(self.index, 'the full suite fails',
                                 'some test output', 'q', [])
        self.assertNotIn('as it actually reads', text)
        self.assertIn('Now answer again', text)

    def test_apply_failure_round_serves_the_file(self):
        """End to end: round 2's prompt must contain home_view.dart's code."""
        h = Harness([answer(), answer()])
        with mock.patch.object(run.model, 'ask', h.ask), \
             mock.patch.object(run.gh, 'ensure_labels'), \
             mock.patch.object(run.gh, 'claim', return_value=True), \
             mock.patch.object(run.gh, 'issue',
                               return_value={'title': 'longpress a card and '
                                                      'select export', 'body': ''}), \
             mock.patch.object(run.gh, 'block',
                               side_effect=lambda n, b: h.blocked.append(b)), \
             mock.patch.object(run.edits_mod, 'apply', return_value=[]), \
             mock.patch.object(
                 run.verify, 'gate',
                 return_value=(False, 'the code edits did not apply',
                               'frontend/lib/widgets/home_view.dart: SEARCH '
                               'text not found.')), \
             mock.patch.object(run, 'git_reset'), \
             mock.patch('sys.argv', ['run.py', '--issue', '1',
                                     '--max-rounds', '2']):
            run.main()
        self.assertEqual(len(h.asked), 2)
        self.assertIn('home_view.dart', h.asked[1])
        self.assertIn('```dart', h.asked[1])



class BlockedCommentTest(unittest.TestCase):
    """The blocked comment is the handoff to a human, so it must never be blank.

    Issue #9's re-run blocked with an empty "Last failure" because every early
    `continue` in the loop skipped the assignment that recorded the reason. The
    run cost $0.0822 and told nobody anything. Each losing path is pinned here.
    """

    def drive_to_block(self, replies, **kw):
        h = Harness(replies)
        with mock.patch.object(run.model, 'ask', h.ask), \
             mock.patch.object(run.gh, 'ensure_labels'), \
             mock.patch.object(run.gh, 'claim', return_value=True), \
             mock.patch.object(run.gh, 'issue',
                               return_value={'title': 'the floor is dark',
                                             'body': ''}), \
             mock.patch.object(run.gh, 'block',
                               side_effect=lambda n, b: h.blocked.append(b)), \
             mock.patch.object(run.edits_mod, 'apply', return_value=[]), \
             mock.patch.object(run.verify, 'gate',
                               return_value=kw.get('gate', (True, '', ''))), \
             mock.patch.object(run.verify, 'full_verification',
                               return_value=kw.get('full', (True, '', ''))), \
             mock.patch.object(run, 'git_reset'), \
             mock.patch.object(run, 'ship',
                               side_effect=lambda *a, **k: 'abc1234'), \
             mock.patch('sys.argv', ['run.py', '--issue', '1', '--max-rounds',
                                     str(len(replies))]):
            run.main()
        self.assertEqual(len(h.blocked), 1, 'expected exactly one block comment')
        return h.blocked[0]

    def _assert_says_something(self, comment):
        self.assertIn('**Last failure:**', comment)
        after = comment.split('**Last failure:**', 1)[1].split('```')[0]
        self.assertTrue(after.strip(),
                        f'blocked comment has an empty reason:\n{comment}')

    def test_expand_loop_records_a_reason(self):
        expand = '<expand path="frontend/lib/theme.dart">floor</expand>'
        self._assert_says_something(self.drive_to_block([expand, expand]))

    def test_truncation_loop_records_a_reason(self):
        cut = ('<file path="frontend/lib/a.dart">\n<<<<<<< SEA',)
        c = self.drive_to_block([cut, cut])
        self._assert_says_something(c)
        self.assertIn('cut off', c)

    def test_unparseable_loop_records_a_reason(self):
        c = self.drive_to_block(['just prose', 'more prose'])
        self._assert_says_something(c)
        self.assertIn('could not be applied', c)

    def test_missing_test_loop_records_a_reason(self):
        c = self.drive_to_block([answer(test=False), answer(test=False)])
        self._assert_says_something(c)
        self.assertIn('no test', c)

    def test_gate_failure_records_its_reason(self):
        c = self.drive_to_block([answer(), answer()],
                                gate=(False, 'the full suite fails', 'boom'))
        self._assert_says_something(c)
        self.assertIn('full suite', c)


class ExpandServingTest(unittest.TestCase):

    def test_serves_located_slices(self):
        import rank
        index = rank.Index()
        text = run.serve_expands(
            index, [edits_mod.Expand('frontend/lib/theme.dart', 'floor')],
            'floor colour', set())
        self.assertIn('frontend/lib/theme.dart', text)
        self.assertIn('```', text)

    def test_unknown_path_does_not_crash(self):
        import rank
        index = rank.Index()
        text = run.serve_expands(
            index, [edits_mod.Expand('frontend/lib/nope.dart', 'x')], 'q', set())
        self.assertIn('no such file', text)


if __name__ == '__main__':
    unittest.main()
