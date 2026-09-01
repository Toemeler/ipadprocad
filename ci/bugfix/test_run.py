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
  * a test that only fails to COMPILE before the fix is rejected as no pin;
  * the happy path ships exactly once.

Run:  python3 -m unittest discover -s ci/bugfix -p 'test_*.py'
"""
import pathlib
import subprocess
import tempfile
import unittest
import urllib.error
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
        # A real model always answers something. When the script runs out it
        # repeats its last reply, which is what a model stuck in a loop does —
        # and keeps these tests independent of how the round budget is counted.
        reply = self.replies.pop(0) if len(self.replies) > 1 else self.replies[0]
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

    def test_the_same_request_twice_is_told_it_is_a_repeat(self):
        """Issue #9's loop: the same file, the same words, four rounds."""
        e = '<expand path="frontend/lib/theme.dart">floor</expand>'
        code, h = self.drive([e, e, answer()], max_rounds=3)
        self.assertIn('asked for exactly this before', h.asked[2])
        self.assertIn('build it', h.asked[2])

    def test_a_different_part_of_the_same_file_is_served(self):
        """The change that #12 paid $0.077 to discover was missing.

        `app_state.dart` is 19,550 lines and reaches a pack as about ninety of
        them. Asking for a different part of it is a legitimate request, and
        answering "it does not exist yet, so build it" is both false and an
        invitation to reinvent code that is already there.
        """
        import rank
        index = rank.Index()
        already = {}
        first = run.serve_expands(
            index, [edits_mod.Expand('frontend/lib/theme.dart', 'floor')],
            'q', already)
        self.assertNotIn('asked for exactly this before', first)

        second = run.serve_expands(
            index, [edits_mod.Expand('frontend/lib/theme.dart', 'accent')],
            'q', already)
        self.assertNotIn('asked for exactly this before', second)
        self.assertIn('rawAccent', second, 'it must serve the part now asked for')

        again = run.serve_expands(
            index, [edits_mod.Expand('frontend/lib/theme.dart', 'accent')],
            'q', already)
        self.assertIn('asked for exactly this before', again)

    def test_the_pack_does_not_make_its_own_files_unaskable(self):
        code, h = self.drive(
            ['<expand path="frontend/lib/theme.dart">accent</expand>',
             answer()], max_rounds=2)
        self.assertEqual(code, 0)
        self.assertNotIn('asked for exactly this before', h.asked[1],
                         'theme.dart is in the pack, and that must not make a '
                         'request for a different part of it a repeat')

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
        # More than two rounds now, and deliberately: an anchor miss no
        # longer spends the fix budget (MAX_APPLY_ROUNDS). What this test is
        # about is unchanged — the SECOND prompt carries the file's real code.
        self.assertGreaterEqual(len(h.asked), 2)
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
            'floor colour', {})
        self.assertIn('frontend/lib/theme.dart', text)
        self.assertIn('```', text)

    def test_unknown_path_does_not_crash(self):
        import rank
        index = rank.Index()
        text = run.serve_expands(
            index, [edits_mod.Expand('frontend/lib/nope.dart', 'x')], 'q', {})
        self.assertIn('no such file', text)


if __name__ == '__main__':
    unittest.main()


class WeakPinTest(unittest.TestCase):
    """A test must fail on BEHAVIOUR, not on a missing symbol.

    Issue #9's shipped fix exposed the hole: its test asserted
    `exportFormatsFor('part') == ['stl','step']` against a pure helper added by
    the same commit, so it "failed before the fix" because the symbol did not
    compile. By that standard any test naming any new symbol passes the gate,
    which makes the gate decorative.
    """

    def test_compile_failure_is_recognised(self):
        import verify
        for out in ("Failed to load \"x_test.dart\": Does not exist.",
                    'Compilation failed for testPath=/x',
                    "Error: Method not found: 'partExportStl'.",
                    "Error: The method 'foo' isn't defined for the type 'Bar'.",
                    "Error: Type 'NativeMenuItem' not found."):
            with self.subTest(out=out[:40]):
                self.assertTrue(verify.failed_to_compile(out))

    def test_assertion_failure_is_not_a_compile_failure(self):
        import verify
        for out in ('Expected: [1, 2]\n  Actual: [1, 3]',
                    'Expected: exactly one matching candidate\n  Actual: zero',
                    '00:03 +12 -1: some test [E]'):
            with self.subTest(out=out[:40]):
                self.assertFalse(verify.failed_to_compile(out))

    def test_gate_rejects_a_compile_only_pin(self):
        # `verify.test` is stubbed rather than left to the environment: this
        # assertion used to depend on whether Flutter was installed, so it
        # passed locally and failed on CI, where a missing test file produces
        # "Does not exist" — which IS a compile failure.
        import verify
        original = verify.test
        verify.test = lambda paths=None, timeout=None: (
            False, "Failed to load 'x_test.dart': Compilation failed")
        try:
            ok, reason, _ = verify.gate(lambda: [], lambda: [], lambda: None,
                                        ['frontend/test/x_test.dart'],
                                        allow_weak=False)
        finally:
            verify.test = original
        self.assertFalse(ok)
        self.assertIn('regression pin', reason)

    def test_gate_accepts_a_genuine_assertion_failure(self):
        import verify
        original_test, original_dead = verify.test, verify.dead_new_symbols
        verify.test = lambda paths=None, timeout=None: (
            len(seen) > 0, 'Expected: [1, 2]\n  Actual: [1, 3]')
        verify.dead_new_symbols = lambda root=None: []
        seen = []
        try:
            # First call (pre-fix) fails on an assertion; second (post-fix) passes.
            def staged(paths=None, timeout=None):
                if not seen:
                    seen.append(1)
                    return False, 'Expected: [1, 2]\n  Actual: [1, 3]'
                return True, 'All tests passed'
            verify.test = staged
            ok, reason, _ = verify.gate(lambda: [], lambda: [], lambda: None,
                                        ['frontend/test/x_test.dart'])
        finally:
            verify.test, verify.dead_new_symbols = original_test, original_dead
        self.assertTrue(ok, reason)

    def test_gate_stands_down_when_weak_is_allowed(self):
        import verify
        seen = {}

        def fake_test(paths=None, timeout=None):
            seen['n'] = seen.get('n', 0) + 1
            return (False, 'Compilation failed for testPath=/x')

        original = verify.test
        verify.test = fake_test
        try:
            ok, reason, _ = verify.gate(lambda: [], lambda: [], lambda: None,
                                        ['frontend/test/x_test.dart'],
                                        allow_weak=False)
            self.assertIn('regression pin', reason)
            ok2, reason2, _ = verify.gate(lambda: [], lambda: [], lambda: None,
                                          ['frontend/test/x_test.dart'],
                                          allow_weak=True)
            # With weak allowed it proceeds past the pin check and fails later,
            # for a different reason.
            self.assertNotIn('regression pin', reason2)
        finally:
            verify.test = original


class DeadSymbolTest(unittest.TestCase):
    """A helper that only its own test calls is not a fix.

    `exportFormatsFor` shipped in 0431693, was referenced by its own test, and
    is called from production code nowhere — the dialog it purported to
    describe hardcodes 'STL' and 'STEP' inline. Demanding a behavioural
    assertion does not catch that on its own: an assertion about a dead
    function is still an assertion. Having no callers is what makes it
    detectable.
    """

    def test_declarations_are_extracted_from_a_diff(self):
        import verify
        for line, want in (
                ('+List<String> exportFormatsFor(String kind) => switch (k) {',
                 'exportFormatsFor'),
                ('+  Future<String?> partExportStl(String name) async {',
                 'partExportStl'),
                ('+class NativeFormatSheet {', 'NativeFormatSheet')):
            with self.subTest(line=line[:40]):
                m = verify.ADDED_DECL_RE.match(line)
                self.assertTrue(m, line)
                self.assertEqual(m.group(1) or m.group(2), want)

    def test_ordinary_added_lines_are_not_declarations(self):
        import verify
        for line in ('+    if (format == null) return;',
                     '+      path = await widget.app.partExportStl(name);',
                     '+// M289 — which formats a card may offer.'):
            with self.subTest(line=line[:40]):
                self.assertIsNone(verify.ADDED_DECL_RE.match(line))

    def test_framework_overrides_are_not_dead(self):
        # A false positive here would block legitimate fixes: nothing in app
        # code calls build() or dispose(), the framework does.
        import verify
        self.assertIn('build', verify.FRAMEWORK_CALLED)
        self.assertIn('dispose', verify.FRAMEWORK_CALLED)
        self.assertIn('createState', verify.FRAMEWORK_CALLED)

    def test_gate_rejects_a_dead_helper(self):
        import verify
        original_test, original_dead = verify.test, verify.dead_new_symbols
        calls = []

        def staged(paths=None, timeout=None):
            calls.append(1)
            if len(calls) == 1:
                return False, 'Expected: [1, 2]\n  Actual: [1, 3]'
            return True, 'All tests passed'

        verify.test = staged
        verify.dead_new_symbols = lambda root=None: ['exportFormatsFor']
        try:
            ok, reason, _ = verify.gate(lambda: [], lambda: [], lambda: None,
                                        ['frontend/test/x_test.dart'])
        finally:
            verify.test, verify.dead_new_symbols = original_test, original_dead
        self.assertFalse(ok)
        self.assertIn('exportFormatsFor', reason)
        self.assertIn('nothing in the app calls it', reason)


class PinsOwnSourceTest(unittest.TestCase):
    """A test that greps the file it just edited is not a test.

    Issue #10 shipped this, and it cleared both existing gates honestly:

        final source = File('lib/app_state.dart').readAsStringSync();
        expect(source, contains('nx = ay * bz - az * by;'));

    Rename `nx` and it fails though nothing changed; delete the call to the
    writer and it still passes.
    """

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        (self.root / 'frontend' / 'test').mkdir(parents=True)

    def tearDown(self):
        self.tmp.cleanup()

    def _write_test(self, body):
        p = self.root / 'frontend' / 'test' / 't_test.dart'
        p.write_text(body, encoding='utf-8')
        return ['frontend/test/t_test.dart']

    def test_flags_a_literal_the_diff_added(self):
        import verify
        paths = self._write_test(
            "import 'dart:io';\n"
            "void main() { final s = File('lib/app_state.dart')"
            ".readAsStringSync();\n"
            "  expect(s, contains('nx = ay * bz - az * by;')); }")
        original = verify.subprocess.run
        verify.subprocess.run = lambda *a, **k: type(
            'R', (), {'stdout': '+        var nx = ay * bz - az * by;\n',
                      'returncode': 0})()
        try:
            found = verify.pins_own_source(paths, root=self.root)
        finally:
            verify.subprocess.run = original
        self.assertTrue(found)

    def test_ignores_a_standing_invariant_not_from_the_diff(self):
        # m236_theme_test greps source for `Color(0x…)` outside theme.dart.
        # That is a legitimate lint-style test and must keep working.
        import verify
        paths = self._write_test(
            "import 'dart:io';\n"
            "void main() { final s = File('lib/part_render.dart')"
            ".readAsStringSync();\n"
            "  expect(s, isNot(contains('Color(0xFF00FF00)'))); }")
        original = verify.subprocess.run
        verify.subprocess.run = lambda *a, **k: type(
            'R', (), {'stdout': '+        var nx = ay * bz - az * by;\n',
                      'returncode': 0})()
        try:
            found = verify.pins_own_source(paths, root=self.root)
        finally:
            verify.subprocess.run = original
        self.assertEqual(found, [])

    def test_ignores_a_test_that_does_not_read_source(self):
        import verify
        paths = self._write_test(
            "void main() { expect(writeStl(mesh).length, 134); }")
        self.assertEqual(verify.pins_own_source(paths, root=self.root), [])

    def test_gate_rejects_it(self):
        import verify
        original_test = verify.test
        original_pins = verify.pins_own_source
        calls = []

        def staged(paths=None, timeout=None):
            calls.append(1)
            if len(calls) == 1:
                return False, 'Expected: not contains SimpleDialog'
            return True, 'All tests passed'

        verify.test = staged
        verify.pins_own_source = lambda paths, root=None: ['nx = ay * bz']
        try:
            ok, reason, _ = verify.gate(lambda: [], lambda: [], lambda: None,
                                        ['frontend/test/t_test.dart'])
        finally:
            verify.test, verify.pins_own_source = original_test, original_pins
        self.assertFalse(ok)
        self.assertIn('pins a spelling', reason)


class CoverageGateTest(unittest.TestCase):
    """The general form: the test must RUN the code that changed.

    Three gates were added for three specific evasions and each was cleared
    honestly by the next answer. They share one shape — the test never executes
    the change — and that is measurable directly rather than inferred.
    """

    DIFF = ('--- a/frontend/lib/app_state.dart\n'
            '+++ b/frontend/lib/app_state.dart\n'
            '@@ -100,0 +101,3 @@\n'
            '+  final a = 1;\n'
            '+  final b = 2;\n'
            '+  return a + b;\n')

    def _with_diff(self, fn):
        import verify
        original = verify.subprocess.run
        verify.subprocess.run = lambda *a, **k: type(
            'R', (), {'stdout': self.DIFF, 'returncode': 0})()
        try:
            return fn()
        finally:
            verify.subprocess.run = original

    def test_added_lines_are_located(self):
        import verify
        added = self._with_diff(lambda: verify.added_lib_lines())
        self.assertEqual(added, {'lib/app_state.dart': {101, 102, 103}})

    def test_lcov_paths_are_normalised(self):
        import verify
        data = verify._parse_lcov(
            'SF:frontend/lib/theme.dart\nDA:5,2\nDA:6,0\nend_of_record\n')
        self.assertEqual(data, {'lib/theme.dart': {5: 2, 6: 0}})

    def test_gate_rejects_a_test_that_runs_none_of_the_change(self):
        import verify
        originals = (verify.test, verify.coverage_of_change,
                     verify.pins_own_source, verify.dead_new_symbols)
        calls = []

        def staged(paths=None, timeout=None):
            calls.append(1)
            return (len(calls) > 1, 'Expected: x\n  Actual: y')

        verify.test = staged
        verify.coverage_of_change = lambda paths, root=None: (0, 30)
        verify.pins_own_source = lambda paths, root=None: []
        verify.dead_new_symbols = lambda root=None: []
        try:
            ok, reason, _ = verify.gate(lambda: [], lambda: [], lambda: None,
                                        ['frontend/test/t_test.dart'])
        finally:
            (verify.test, verify.coverage_of_change,
             verify.pins_own_source, verify.dead_new_symbols) = originals
        self.assertFalse(ok)
        self.assertIn('0 of the 30', reason)
        self.assertIn('not exercising the fix', reason)

    def test_gate_accepts_a_test_that_runs_the_change(self):
        import verify
        originals = (verify.test, verify.coverage_of_change,
                     verify.pins_own_source, verify.dead_new_symbols)
        calls = []

        def staged(paths=None, timeout=None):
            calls.append(1)
            return (len(calls) > 1, 'Expected: x\n  Actual: y')

        verify.test = staged
        verify.coverage_of_change = lambda paths, root=None: (18, 30)
        verify.pins_own_source = lambda paths, root=None: []
        verify.dead_new_symbols = lambda root=None: []
        try:
            ok, reason, _ = verify.gate(lambda: [], lambda: [], lambda: None,
                                        ['frontend/test/t_test.dart'])
        finally:
            (verify.test, verify.coverage_of_change,
             verify.pins_own_source, verify.dead_new_symbols) = originals
        self.assertTrue(ok, reason)

    def test_no_coverage_data_does_not_block(self):
        # A Swift-only change, or a run where lcov did not appear, must not be
        # treated as evidence that the test is bad.
        import verify
        originals = (verify.test, verify.coverage_of_change,
                     verify.pins_own_source, verify.dead_new_symbols)
        calls = []
        verify.test = lambda paths=None, timeout=None: (
            bool(calls) or calls.append(1), 'Expected: x\n  Actual: y')
        verify.coverage_of_change = lambda paths, root=None: (0, 0)
        verify.pins_own_source = lambda paths, root=None: []
        verify.dead_new_symbols = lambda root=None: []
        try:
            ok, _, _ = verify.gate(lambda: [], lambda: [], lambda: None,
                                   ['frontend/test/t_test.dart'])
        finally:
            (verify.test, verify.coverage_of_change,
             verify.pins_own_source, verify.dead_new_symbols) = originals
        self.assertTrue(ok)


class SoughtSymbolTest(unittest.TestCase):
    """A failed SEARCH names what the model believed existed.

    Issue #11 round 6 looked for `static Color get accent => current.accent;`.
    The real line is `... => scheme.value.accent;`, one grep away — but the
    repair prompt was answering with neighbourhoods ranked by the ISSUE text,
    which is what the model already had and had already failed to use.
    """

    LOG = ("frontend/lib/theme.dart: SEARCH text not found. It must match the "
           "file byte for byte, INCLUDING leading whitespace. First line "
           "looked for: '  static Color get accent => current.accent;'")

    def test_symbols_are_extracted(self):
        self.assertEqual(run.sought_symbols(self.LOG), ['accent', 'current'])

    def test_dart_keywords_are_dropped(self):
        # Grepping `Color` or `static` matches half of theme.dart.
        got = run.sought_symbols(self.LOG)
        for kw in ('static', 'Color', 'get'):
            self.assertNotIn(kw, got)

    def test_nothing_sought_in_an_unrelated_failure(self):
        self.assertEqual(run.sought_symbols('`flutter test` failed'), [])

    def test_repair_prompt_greps_for_them(self):
        """The DECLARATIONS the failed SEARCH named, as the file really reads.

        Asserted on the declaration heads rather than on whole lines. The first
        version of this pinned the getter's entire text, and the accent fix for
        issue #11 wrapped that line — so a test about the retriever failed
        because unrelated source moved, which is a test measuring the wrong
        thing. What must hold is that the grep finds where `accent` is
        declared: the field, the getter, and the row in each palette.
        """
        import rank
        index = rank.Index()
        text = run.repair_prompt(index, 'the code edits did not apply',
                                 self.LOG, 'accent colour settings',
                                 ['frontend/lib/theme.dart'])
        self.assertIn('static Color get accent', text)
        self.assertIn('final Color rawAccent;', text)
        self.assertIn('rawAccent: Color(0x', text)


class PostPushTest(unittest.TestCase):
    """A push that breaks the iOS build is a failed fix.

    run.py verifies on Linux and cannot compile Swift, run the simulator test,
    or link the native OCCT library. A fix can therefore go green, land, and
    turn `Core + C-API Build (iOS)` red minutes later with the issue already
    closed and the run that closed it long since exited successfully.
    """

    def test_only_automated_fix_commits_are_claimed(self):
        import postpush
        self.assertTrue(postpush.SUBJECT_RE.search(
            'Bugfix #9: prompt STL/STEP before choosing export location'))
        self.assertEqual(
            postpush.SUBJECT_RE.search('Bugfix #11: x').group(1), '11')

    def test_a_human_commit_is_ignored(self):
        import postpush
        for subject in ('M270: the first row was the one row M264 did not cover',
                        'Update AUTOMATION_NOTES.md: log bug-report issue #9',
                        'CI(dart): analyze+test logs from run 33418131242'):
            with self.subTest(subject=subject):
                self.assertIsNone(postpush.SUBJECT_RE.search(subject))

    def test_a_pre_existing_failure_does_not_reopen(self):
        """The common case here, not the exception.

        `Core + C-API Build (iOS)` has gone red on main for a commit that
        touched only .gitignore, and its fast Dart job runs without the native
        OCCT library so m207 dies in Engine.create whatever was pushed.
        Reopening on that would reopen every issue the pipeline closes.
        """
        import postpush
        calls = []
        with mock.patch.object(postpush, 'commit_subject',
                               return_value='Bugfix #9: a thing'), \
             mock.patch.object(postpush, 'failing_steps', return_value=[]), \
             mock.patch.object(postpush, 'previously_failing',
                               return_value=True), \
             mock.patch.object(postpush, 'api',
                               side_effect=lambda *a, **k: calls.append(a) or
                               {'workflow_id': 1}):
            self.assertEqual(postpush.main(), 0)
        # Only the workflow lookup; no comment, no reopen, no label.
        self.assertLessEqual(len(calls), 1, calls)

    def test_the_subject_is_matched_at_line_start(self):
        # A commit BODY mentioning "Bugfix #3:" must not claim issue 3.
        import postpush
        body = ('Some change\n\nThis is similar to Bugfix #3: the old one.\n')
        m = postpush.SUBJECT_RE.search(body)
        # MULTILINE means a line STARTING with the marker; the body line here
        # does not, so nothing is claimed.
        self.assertIsNone(m)


class HouseRulesTest(unittest.TestCase):
    """The conventions that the shipped #9 fix violated."""

    def test_native_chrome_rule_is_stated(self):
        import pack
        rules = pack.house_rules()
        self.assertIn('SimpleDialog', rules)
        self.assertIn('native_prompts.dart', rules)
        self.assertIn('NativeMenuItem', rules)

    def test_colour_invariant_is_stated(self):
        # m236_theme_test has a test literally named "no colour is written
        # inline outside theme.dart". Issue #11 kept adding `const Color
        # kAccentTeal = Color(0xFF4DB6AC);` to settings.dart, which fails that
        # test even once it compiles.
        import pack
        rules = pack.house_rules()
        self.assertIn('m236_theme_test', rules)
        self.assertIn('kChalk', rules)
        self.assertIn('scheme.value', rules)

    def test_native_fallback_rule_is_stated(self):
        # Issue #11 added the accent option to the native settings sheet only.
        # `settings_sheet.dart:83` branches on NativeMenu.isSupported, so the
        # host test ran the Flutter fallback and found 0 widgets.
        import pack
        rules = pack.house_rules()
        self.assertIn('isSupported', rules)
        self.assertIn('fallback', rules.lower())
        self.assertIn('BOTH', rules)

    def test_import_rule_is_stated(self):
        import pack
        rules = pack.house_rules()
        self.assertIn('ADD THE IMPORT', rules)
        self.assertIn('show', rules)

    def test_package_import_rule_is_stated(self):
        import pack
        self.assertIn('package:prototype', pack.house_rules())


class PreexistingFailureTest(unittest.TestCase):
    """A test that is red on `main` must not be charged to the model's fix.

    This is not hypothetical tidiness. `s10_analyze_memory_test` compares two
    RSS deltas, and its instrument gate sat exactly on the line where a reading
    is provably impossible instead of where it stops being trustworthy — so it
    failed on `main` at 45d1222a, skipped on the next run of the same code, and
    the whole suite is the pipeline's last gate. Every fix written while it was
    red would have been rejected for it, handed a log about `solver.dart`, and
    told to try again.
    """

    GITHUB_OUT = (
        '::group::❌ /home/runner/work/ipadprocad/ipadprocad/frontend/'
        'test/s10_analyze_memory_test.dart: the dense algorithm (failed)\n'
        'Expected: a value less than <33464320>\n'
        '::endgroup::\n'
        '::error::2993 tests passed, 1 failed.\n')

    PLAIN_OUT = ('00:41 +2993 -1: test/s10_analyze_memory_test.dart: '
                 'the dense algorithm [E]\n')

    def test_reads_the_failing_file_from_the_actions_reporter(self):
        import verify
        self.assertEqual(verify.failing_test_files(self.GITHUB_OUT),
                         ['frontend/test/s10_analyze_memory_test.dart'])

    def test_reads_the_failing_file_from_the_plain_reporter(self):
        import verify
        self.assertEqual(verify.failing_test_files(self.PLAIN_OUT),
                         ['frontend/test/s10_analyze_memory_test.dart'])

    def test_passing_output_names_nothing(self):
        import verify
        self.assertEqual(verify.failing_test_files('All tests passed!'), [])

    def _drive(self, single_result):
        """full_verification with a red suite; the single re-run decides."""
        import verify
        calls = {'revert': 0, 'reapply': 0, 'single': None}

        def fake_test(paths=None, timeout=None):
            if paths is None:
                return False, self.GITHUB_OUT
            calls['single'] = paths
            return single_result, ''

        def revert():
            calls['revert'] += 1

        def reapply():
            calls['reapply'] += 1
            return []

        with mock.patch.object(verify, 'analyze', return_value=(True, '')), \
             mock.patch.object(verify, 'test', side_effect=fake_test):
            out = verify.full_verification(revert, reapply)
        return out, calls

    def test_a_failure_that_survives_the_revert_is_not_the_fix(self):
        (ok, reason, _), calls = self._drive(single_result=False)
        self.assertTrue(ok, 'a test red on main must not block the fix')
        self.assertEqual(reason, '')
        self.assertEqual(calls['revert'], 1)
        self.assertEqual(calls['reapply'], 1, 'the fix must be put back')
        self.assertEqual(calls['single'],
                         ['frontend/test/s10_analyze_memory_test.dart'])

    def test_a_failure_that_goes_away_on_the_revert_is_the_fix(self):
        (ok, reason, _), calls = self._drive(single_result=True)
        self.assertFalse(ok, 'the fix broke it — that must still block')
        self.assertIn('full suite', reason)
        self.assertEqual(calls['reapply'], 1)

    def test_without_revert_and_reapply_it_stays_all_or_nothing(self):
        import verify
        with mock.patch.object(verify, 'analyze', return_value=(True, '')), \
             mock.patch.object(verify, 'test',
                               return_value=(False, self.GITHUB_OUT)):
            ok, reason, _ = verify.full_verification()
        self.assertFalse(ok)
        self.assertIn('full suite', reason)

    def test_a_fix_that_cannot_be_re_applied_blocks(self):
        import verify

        def fake_test(paths=None, timeout=None):
            return (False, self.GITHUB_OUT) if paths is None else (False, '')

        with mock.patch.object(verify, 'analyze', return_value=(True, '')), \
             mock.patch.object(verify, 'test', side_effect=fake_test):
            ok, reason, _ = verify.full_verification(
                lambda: None, lambda: ['no <<<<<<< SEARCH match'])
        self.assertFalse(ok)
        self.assertIn('re-applied', reason)


class ClaimTest(unittest.TestCase):
    """`workflow_dispatch` is how a blocked issue gets re-run. It could not.

    A blocked issue has no `bug-report` label — the run that blocked it took
    the label on the way in — so the DELETE that makes claiming atomic always
    404'd, and every manual re-run printed "already claimed by another run"
    and exited 0 in two seconds, green. Issue #11 was re-run that way after
    four separate fixes to the retriever and did nothing at all.
    """

    def calls(self, force, labels=(), report_label_exists=False):
        import gh
        seen = []

        def fake(method, path, body=None, retries=3):
            seen.append((method, path))
            if method == 'DELETE' and path.endswith(f'/labels/{gh.REPORT}'):
                if not report_label_exists:
                    raise urllib.error.HTTPError(path, 404, 'no', None, None)
                return {}
            if method == 'DELETE' and path.endswith(f'/labels/{gh.BLOCKED}'):
                raise urllib.error.HTTPError(path, 404, 'no', None, None)
            return {}

        with mock.patch.object(gh, '_request', side_effect=fake), \
             mock.patch.object(gh, 'issue',
                               return_value={'labels': [{'name': n}
                                                        for n in labels]}):
            took = gh.claim(1, force=force)
        return took, seen

    def test_the_normal_path_is_still_a_compare_and_swap(self):
        took, _ = self.calls(force=False, report_label_exists=True)
        self.assertTrue(took)
        took, _ = self.calls(force=False, report_label_exists=False)
        self.assertFalse(took, 'a second run must lose the race')

    def test_a_manual_rerun_claims_a_blocked_issue(self):
        import gh
        took, seen = self.calls(force=True, labels=[gh.BLOCKED])
        self.assertTrue(took)
        self.assertIn(('POST', f'/repos/{gh.REPO}/issues/1/labels'), seen)
        self.assertIn(('DELETE', f'/repos/{gh.REPO}/issues/1/labels/{gh.BLOCKED}'),
                      seen, 'blocked and in progress at once is not a state')

    def test_force_still_loses_to_a_run_that_is_live(self):
        import gh
        took, _ = self.calls(force=True, labels=[gh.WORKING])
        self.assertFalse(took, 'openhands-working means somebody holds it')

    def test_the_workflow_passes_force_only_on_a_manual_start(self):
        wf = (pathlib.Path(run.__file__).resolve().parents[2]
              / '.github' / 'workflows' / 'bugfix.yml').read_text()
        self.assertIn("github.event_name == 'workflow_dispatch' && '--force'", wf)


class TreeIsResetTest(unittest.TestCase):
    """The model's own previous patch is still in its context. The tree is not.

    Issue #11's fifth round searched `settings.dart` for
    `import 'dart:ui' show Color, Locale;`. No such line exists — it is what
    the model's OWN earlier round had tried to make out of the real
    `import 'dart:ui' show Locale;`, and `git_reset` had thrown that away
    before the prompt was written. Nothing in the prompt said so.
    """

    def test_the_repair_prompt_says_the_tree_was_reset(self):
        import rank
        text = run.repair_prompt(rank.Index(), 'the code edits did not apply',
                                 'SEARCH text not found', 'accent colour',
                                 ['frontend/lib/settings.dart'])
        self.assertIn('RESET', text)
        self.assertIn('back to how the repository has it', text)
        self.assertIn('ORIGINAL', text)

    def test_it_is_said_before_the_source_is_shown(self):
        import rank
        text = run.repair_prompt(rank.Index(), 'the code edits did not apply',
                                 'SEARCH text not found', 'accent colour',
                                 ['frontend/lib/settings.dart'])
        self.assertLess(text.index('RESET'), text.index('byte for byte'),
                        'the warning has to arrive before the code it is about')

    def test_a_converging_run_gets_more_than_four_rounds(self):
        # #11 ran out one round short, twice, on a feature whose rounds did not
        # repeat: weak pin -> compile error -> failing test -> one SEARCH miss.
        self.assertGreaterEqual(run.MAX_ROUNDS, 6)


class ApplyBudgetTest(unittest.TestCase):
    """A SEARCH that misses is a mechanical failure, not a wrong diagnosis.

    Issue #11's sixth, seventh and eighth attempts lost FIVE of nineteen rounds
    to "the code edits did not apply". The eighth had a complete, verified fix
    on its round 8 — reachable only because expands were already exempt from
    the budget. Anchor misses now get the same bounded exemption.
    """

    def test_the_apply_failures_are_recognised(self):
        for reason in ('the code edits did not apply',
                       'the test edits did not apply',
                       'the answer could not be applied'):
            self.assertTrue(run.is_apply_failure(reason), reason)

    def test_a_wrong_fix_is_not_one_of_them(self):
        for reason in ('with your fix applied, your own new test still fails',
                       'the new test PASSES without your fix, so it pins '
                       'nothing.',
                       '`flutter analyze` reports errors',
                       '`flutter test` (full suite) fails'):
            self.assertFalse(run.is_apply_failure(reason), reason)

    def test_the_exemption_is_bounded(self):
        self.assertEqual(run.MAX_APPLY_ROUNDS, 2)

    def test_a_model_that_never_applies_still_terminates(self):
        """The exemption is used, and then the budget bites anyway."""
        h = Harness([answer()] * 12)
        with mock.patch.object(run.model, 'ask', h.ask), \
             mock.patch.object(run.gh, 'ensure_labels'), \
             mock.patch.object(run.gh, 'claim', return_value=True), \
             mock.patch.object(run.gh, 'issue',
                               return_value={'title': 't', 'body': ''}), \
             mock.patch.object(run.gh, 'block',
                               side_effect=lambda n, b: h.blocked.append(b)), \
             mock.patch.object(run.edits_mod, 'apply', return_value=[]), \
             mock.patch.object(
                 run.verify, 'gate',
                 return_value=(False, 'the code edits did not apply', '')), \
             mock.patch.object(run, 'git_reset'), \
             mock.patch.object(run, 'ship', side_effect=AssertionError), \
             mock.patch('sys.argv', ['run.py', '--issue', '1',
                                     '--max-rounds', '2']):
            code = run.main()
        self.assertEqual(code, 1)
        self.assertEqual(len(h.blocked), 1, 'it must still block')
        self.assertEqual(len(h.asked), 2 + run.MAX_APPLY_ROUNDS,
                         'two exempted anchor misses, then the fix budget')


class LandingTest(unittest.TestCase):
    """`main` moves under a twenty-minute run. That is normal, not an error."""

    def test_a_rejected_push_is_retried_from_a_fresh_fetch(self):
        calls = []

        def fake_sh(*args):
            calls.append(args)
            return 'abc1234'

        pushes = [1, 0]  # rejected once, then accepted

        def fake_run(argv, **kw):
            calls.append(tuple(argv))
            rc = 0
            if argv[:2] == ['git', 'push']:
                rc = pushes.pop(0)
            return subprocess.CompletedProcess(argv, rc, '', '')

        with mock.patch.object(run, 'sh', side_effect=fake_sh), \
             mock.patch.object(run.subprocess, 'run', side_effect=fake_run):
            sha = run._land()
        self.assertEqual(sha, 'abc1234')
        fetches = [c for c in calls if c[:2] == ('git', 'fetch')]
        self.assertEqual(len(fetches), 2, 'the retry must re-fetch, not reuse')

    def test_a_push_that_never_lands_still_raises(self):
        def fake_run(argv, **kw):
            rc = 1 if argv[:2] == ['git', 'push'] else 0
            return subprocess.CompletedProcess(argv, rc, '', 'rejected')

        with mock.patch.object(run, 'sh', return_value=''), \
             mock.patch.object(run.subprocess, 'run', side_effect=fake_run):
            with self.assertRaises(run.RebaseConflict):
                run._land()

    def test_a_real_content_conflict_still_raises_at_once(self):
        def fake_run(argv, **kw):
            rc = 1 if argv[:2] == ['git', 'rebase'] else 0
            return subprocess.CompletedProcess(argv, rc, 'CONFLICT', '')

        # `git diff --diff-filter=U` names a source file, not just the log.
        with mock.patch.object(run, 'sh',
                               return_value='frontend/lib/theme.dart'), \
             mock.patch.object(run.subprocess, 'run', side_effect=fake_run):
            with self.assertRaises(run.RebaseConflict):
                run._land()

    def test_the_append_only_log_keeps_both_entries(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            notes = root / run.NOTES
            notes.parent.mkdir(parents=True)
            notes.write_text('- #9 — first.\n'
                             '<<<<<<< HEAD\n'
                             '- #10 — theirs.\n'
                             '=======\n'
                             '- #11 — ours.\n'
                             '>>>>>>> abc123\n')
            with mock.patch.object(run, 'ROOT', root), \
                 mock.patch.object(run, 'sh', return_value=run.NOTES), \
                 mock.patch.object(
                     run.subprocess, 'run',
                     return_value=subprocess.CompletedProcess([], 0, '', '')):
                self.assertTrue(run._keep_both_notes())
            self.assertEqual(notes.read_text(),
                             '- #9 — first.\n- #10 — theirs.\n- #11 — ours.\n')


class SystemPromptTest(unittest.TestCase):
    def test_the_compile_error_pin_is_in_the_cached_prefix(self):
        """It was rejected on round 2 of all three logged #11 attempts.

        The rejection text lived only in `verify.gate`, so every run paid an
        expensive round (21k-27k output tokens) to be told it. The prefix is a
        cache hit at $0.0441/M, so saying it up front is very nearly free.
        """
        import model
        self.assertIn('COMPILE ERROR IS NOT A FAILING TEST', model.SYSTEM)
        self.assertIn('BEHAVIOUR', model.SYSTEM)


class SwiftGateTest(unittest.TestCase):
    """The half of a cross-cutting fix a Linux runner cannot compile.

    Issues #7 and #8 both needed a Dart change AND a Swift change. The channel
    between them is a method name and a bag of string keys matched by hand, and
    a mismatch there compiles perfectly on BOTH sides and is a no-op at
    runtime — so neither the Dart suite nor the macOS build would fail. That is
    the one class of Swift defect this runner can catch, and the likeliest one.
    """

    DART = ("class NativeMenu {\n"
            "  static Future<void> setAccent({required int light,\n"
            "      required int dark}) async {\n"
            "    await _ch.invokeMethod<void>('setAccent',\n"
            "        {'light': light, 'dark': dark});\n"
            "  }\n"
            "}\n")
    SWIFT = ('switch call.method {\n'
             'case "setAccent":\n'
             '    binder.setAccent(light: color(args["light"]),\n'
             '                     dark: color(args["dark"]))\n'
             '    result(nil)\n'
             'default:\n'
             '    result(FlutterMethodNotImplemented)\n'
             '}\n')

    REL = 'frontend/packages/native_menu/lib/native_menu.dart'

    def build(self, dart=None, swift=None):
        """A miniature package tree. -> (root, [changed paths])"""
        tmp = tempfile.mkdtemp()
        root = pathlib.Path(tmp)
        (root / 'frontend/packages/native_menu/lib').mkdir(parents=True)
        (root / 'frontend/packages/native_menu/ios/Classes').mkdir(parents=True)
        (root / self.REL).write_text(dart if dart is not None else self.DART)
        (root / 'frontend/packages/native_menu/ios/Classes/Plugin.swift'
         ).write_text(swift if swift is not None else self.SWIFT)
        return root

    def check(self, **kw):
        import verify
        root = self.build(**kw)
        # Everything the diff added, so the gate treats the call as ours.
        with mock.patch.object(verify, 'ROOT', root), \
             mock.patch.object(verify, 'changed_lines',
                               side_effect=lambda rel: (root / rel).read_text()):
            return verify.swift_contract([self.REL])

    def test_a_matching_pair_passes(self):
        self.assertEqual(self.check(), [])

    def test_a_call_with_no_swift_case_is_caught(self):
        out = self.check(swift=self.SWIFT.replace('setAccent', 'setAccentColor'))
        self.assertEqual(len(out), 1)
        self.assertIn('no Swift `case "setAccent":`', out[0])

    def test_a_key_spelled_differently_is_caught(self):
        """The failure that compiles on both sides and does nothing."""
        out = self.check(swift=self.SWIFT.replace('args["light"]',
                                                  'args["lightColour"]'))
        self.assertEqual(len(out), 1)
        self.assertIn('sends `light`', out[0])

    def test_a_call_this_change_did_not_make_is_not_its_problem(self):
        import verify
        root = self.build(swift='switch x {\ndefault: break\n}\n')
        with mock.patch.object(verify, 'ROOT', root), \
             mock.patch.object(verify, 'changed_lines', return_value=''):
            self.assertEqual(verify.swift_contract([self.REL]), [],
                             'a pre-existing mismatch is somebody else\'s debt')

    def test_a_dart_file_outside_a_plugin_is_skipped(self):
        import verify
        root = self.build()
        (root / 'frontend/lib').mkdir(parents=True)
        (root / 'frontend/lib/theme.dart').write_text(self.DART)
        with mock.patch.object(verify, 'ROOT', root), \
             mock.patch.object(verify, 'changed_lines', return_value='setAccent'):
            self.assertEqual(verify.swift_contract(['frontend/lib/theme.dart']),
                             [])

    def test_an_unclosed_brace_is_caught(self):
        import verify
        root = self.build(swift=self.SWIFT.replace('}\n', '', 1))
        rel = 'frontend/packages/native_menu/ios/Classes/Plugin.swift'
        with mock.patch.object(verify, 'ROOT', root):
            out = verify.swift_braces([rel])
        self.assertEqual(len(out), 1)
        self.assertIn('did not close what it opened', out[0])

    def test_braces_inside_strings_and_comments_do_not_count(self):
        import verify
        root = self.build(swift='// a { in a comment\nlet s = "a { in a string"\n')
        rel = 'frontend/packages/native_menu/ios/Classes/Plugin.swift'
        with mock.patch.object(verify, 'ROOT', root):
            self.assertEqual(verify.swift_braces([rel]), [])

    def test_the_real_accent_change_passes_both(self):
        """This gate's first real case is the change that motivated it."""
        import verify
        touched = ['frontend/packages/native_menu/lib/native_menu.dart',
                   'frontend/packages/native_menu/ios/Classes/Appearance.swift',
                   'frontend/packages/native_menu/ios/Classes/GlassTabBar.swift',
                   'frontend/packages/native_menu/ios/Classes/'
                   'NativeMenuPlugin.swift']
        self.assertEqual(verify.swift_braces(touched), [])
        with mock.patch.object(verify, 'changed_lines', return_value='setAccent'):
            self.assertEqual(verify.swift_contract(touched), [])


class SwiftCaveatTest(unittest.TestCase):
    """Closing a Swift fix with a plain "fixed" overstates what was proved."""

    def close_body(self, paths):
        h = Harness([answer()])
        bodies = []
        with mock.patch.object(run.model, 'ask', h.ask), \
             mock.patch.object(run.gh, 'ensure_labels'), \
             mock.patch.object(run.gh, 'claim', return_value=True), \
             mock.patch.object(run.gh, 'issue',
                               return_value={'title': 't', 'body': ''}), \
             mock.patch.object(run.gh, 'close',
                               side_effect=lambda n, b=None: bodies.append(b)), \
             mock.patch.object(run.edits_mod, 'apply', return_value=[]), \
             mock.patch.object(run.edits_mod, 'touched', return_value=paths), \
             mock.patch.object(run.verify, 'gate', return_value=(True, '', '')), \
             mock.patch.object(run.verify, 'full_verification',
                               return_value=(True, '', '')), \
             mock.patch.object(run.verify, 'touches_arb', return_value=False), \
             mock.patch.object(run, 'git_reset'), \
             mock.patch.object(run, 'ship', return_value='abc1234'), \
             mock.patch('sys.argv', ['run.py', '--issue', '1']):
            run.main()
        return bodies[0]

    def test_a_swift_fix_says_nothing_built_it(self):
        body = self.close_body(['frontend/lib/theme.dart',
                                'frontend/packages/native_menu/ios/Classes/'
                                'GlassTabBar.swift'])
        self.assertIn('was not compiled here', body)
        self.assertIn('GlassTabBar.swift', body)
        self.assertIn('macOS', body)

    def test_a_pure_dart_fix_carries_no_caveat(self):
        body = self.close_body(['frontend/lib/theme.dart'])
        self.assertNotIn('was not compiled here', body)


class SwiftHouseRuleTest(unittest.TestCase):
    def test_the_channel_contract_is_stated_in_the_cached_prefix(self):
        import pack
        rules = pack.house_rules()
        self.assertIn('CHANNEL CONTRACT', rules)
        self.assertIn('case "setAccent":', rules)
        self.assertIn('does nothing at all at runtime', rules)

    def test_the_push_every_variant_rule_is_stated(self):
        import pack
        rules = pack.house_rules()
        self.assertIn('ValueNotifier', rules)
        self.assertIn('setViewportColor', rules)


class GuardedExitTest(unittest.TestCase):
    """An issue must never be left claimed by a run that is no longer running.

    `claim` takes `bug-report` off and puts `openhands-working` on. Every
    PLANNED ending takes it off again; an unplanned one did not — and the
    `--force` re-run added in the same session refuses exactly when
    `openhands-working` is present, so a crash became a dead end.
    """

    def crash(self, exc, argv=('run.py', '--issue', '11')):
        blocked = []
        with mock.patch.object(run, 'main', side_effect=exc), \
             mock.patch.object(run.gh, 'block',
                               side_effect=lambda n, b: blocked.append((n, b))), \
             mock.patch('sys.argv', list(argv)):
            code = run.guarded()
        return code, blocked

    def test_a_crash_blocks_the_issue_instead_of_stranding_it(self):
        code, blocked = self.crash(RuntimeError('the runner went away'))
        self.assertEqual(code, 1)
        self.assertEqual(len(blocked), 1)
        number, body = blocked[0]
        self.assertEqual(number, 11)
        self.assertIn('ended unexpectedly', body)
        self.assertIn('RuntimeError', body)
        self.assertIn('`main` is untouched', body)
        self.assertIn('re-run', body)

    def test_the_issue_number_survives_argparse_never_running(self):
        _, blocked = self.crash(RuntimeError('x'),
                                argv=('run.py', '--issue=11', '--force'))
        self.assertEqual(blocked[0][0], 11)

    def test_a_normal_exit_is_not_touched(self):
        with mock.patch.object(run, 'main', return_value=0), \
             mock.patch.object(run.gh, 'block',
                               side_effect=AssertionError('must not block')), \
             mock.patch('sys.argv', ['run.py', '--issue', '11']):
            self.assertEqual(run.guarded(), 0)

    def test_argparse_errors_still_exit_normally(self):
        """SystemExit is argparse doing its job, not a crash to report."""
        with mock.patch.object(run, 'main', side_effect=SystemExit(2)), \
             mock.patch.object(run.gh, 'block',
                               side_effect=AssertionError('must not block')), \
             mock.patch('sys.argv', ['run.py', '--issue', '11']):
            with self.assertRaises(SystemExit):
                run.guarded()

    def test_a_crash_with_no_issue_number_does_not_guess(self):
        code, blocked = self.crash(RuntimeError('x'), argv=('run.py',))
        self.assertEqual(code, 1)
        self.assertEqual(blocked, [], 'blocking a guessed issue is worse')

    def test_failing_to_block_does_not_mask_the_exit_code(self):
        with mock.patch.object(run, 'main', side_effect=RuntimeError('x')), \
             mock.patch.object(run.gh, 'block',
                               side_effect=OSError('github is down')), \
             mock.patch('sys.argv', ['run.py', '--issue', '11']):
            self.assertEqual(run.guarded(), 1)


class DerivedValueRuleTest(unittest.TestCase):
    """Bug report #11 needed three attempts and both misses were the same shape.

    A value stored twice has to be changed twice, and in this repo the second
    copy is invisible: nine tokens per palette ARE the accent at another alpha,
    written as their own hex. And an override put at a READER is skipped by
    every other reader — `galleryChrome` hands out a `Palette`, so `T.x` is not
    the only door.
    """

    def test_the_duplicate_value_rule_is_in_the_cached_prefix(self):
        import pack
        rules = pack.house_rules()
        self.assertIn('STORED TWICE', rules)
        self.assertIn('rawCardHoverBorder', rules)
        self.assertIn('m236_theme_test', rules)

    def test_the_override_where_it_lives_rule_is_stated(self):
        import pack
        rules = pack.house_rules()
        self.assertIn('WHERE IT LIVES', rules)
        self.assertIn('galleryChrome', rules)
        self.assertIn('icon_theme.dart', rules)


class UnreachableChangeTest(unittest.TestCase):
    """Issue #12 shipped a fix to a function nothing in the app calls.

    `exportFormatsFor` is declared in `home_view.dart` and referenced only by
    its own tests; the real export path hardcodes its two items. The fix
    changed two lines INSIDE it, so it added no declaration and removed no
    reference — and every gate passed. The test failed before and passed after,
    the coverage gate watched the changed lines execute, and the commit could
    not affect the app at all.

    A change to app code has to be reachable FROM app code. Otherwise it is a
    change to the test suite wearing a fix's commit message.
    """

    def repo(self, edit, extra=''):
        tmp = pathlib.Path(tempfile.mkdtemp())
        (tmp / 'frontend/lib/widgets').mkdir(parents=True)
        base = ('/// Which formats a card offers.\n'
                'List<String> exportFormatsFor(String kind) => switch (kind) {\n'
                "      'part' => ['stl', 'step'],\n"
                '      _ => [],\n'
                '    };\n'
                '\n'
                'Future<void> sendFile(String name) async {\n'
                '  await menu(items: const [1, 2]);\n'
                '}\n'
                '\n'
                'void onTap(String name) {\n'
                '  sendFile(name);\n'
                '}\n' + extra)
        f = tmp / 'frontend/lib/widgets/home_view.dart'
        f.write_text(base)
        for cmd in (['git', 'init', '-q', '.'],
                    ['git', 'config', 'user.email', 't@e'],
                    ['git', 'config', 'user.name', 't'],
                    ['git', 'add', '-A'],
                    ['git', 'commit', '-qm', 'base']):
            subprocess.run(cmd, cwd=tmp, capture_output=True)
        f.write_text(edit(base))
        return tmp

    def test_editing_a_function_nothing_calls_is_caught(self):
        import verify
        root = self.repo(lambda s: s.replace("'part' => ['stl', 'step'],",
                                             "'part' || 'ptp' => ['stl', 'step'],"))
        self.assertEqual(verify._enclosing_decls(root), {'exportFormatsFor'})
        self.assertIn('exportFormatsFor', verify.dead_new_symbols(root))

    def test_editing_a_function_the_app_calls_is_fine(self):
        import verify
        root = self.repo(lambda s: s.replace('await menu(items: const [1, 2]);',
                                             'await menu(items: const [1, 2, 3]);'))
        self.assertEqual(verify._enclosing_decls(root), {'sendFile'})
        self.assertNotIn('sendFile', verify.dead_new_symbols(root),
                         '`onTap` calls it, so the change can reach the app')

    def test_a_doc_comment_is_not_a_caller(self):
        """A mention in prose must not read as a use."""
        import verify
        root = self.repo(
            lambda s: s.replace("'part' => ['stl', 'step'],",
                                "'part' || 'ptp' => ['stl', 'step'],"),
            extra='// exportFormatsFor is described again down here.\n')
        self.assertIn('exportFormatsFor', verify.dead_new_symbols(root))

    def test_a_framework_lifecycle_method_is_exempt(self):
        import verify
        root = self.repo(
            lambda s: s.replace('  await menu(items: const [1, 2]);',
                                '  await menu(items: const [1, 2]);\n  //x'),
            extra='class W {\n  void initState() {\n    final z = 1;\n  }\n}\n')
        self.assertNotIn('initState', verify.dead_new_symbols(root))


class ManualLabelTest(unittest.TestCase):
    """The report dialog's checkbox decides whether this pipeline may run.

    The relay files an opt-OUT report under a different label, and
    `bugfix.yml` runs only for `bug-report` — so the switch is the label, and
    nothing here has to know about the checkbox at all. What must hold is that
    the two names differ and that the manual one exists, because an issue
    nobody is working on should SAY so rather than look like one that was
    missed.
    """

    def test_the_two_labels_are_not_the_same(self):
        import gh
        self.assertNotEqual(gh.MANUAL, gh.REPORT)

    def test_the_manual_label_is_created_alongside_the_others(self):
        import gh
        made = []

        def fake(method, path, body=None, retries=3):
            if method == 'GET':                 # nothing exists yet
                raise urllib.error.HTTPError(path, 404, 'no', None, None)
            if method == 'POST' and body:
                made.append(body['name'])
            return {}

        with mock.patch.object(gh, '_request', side_effect=fake):
            gh.ensure_labels()
        self.assertIn(gh.MANUAL, made)
        self.assertIn(gh.WORKING, made)

    def test_the_workflow_still_gates_on_the_autofix_label_only(self):
        wf = (pathlib.Path(run.__file__).resolve().parents[2]
              / '.github' / 'workflows' / 'bugfix.yml').read_text()
        self.assertIn("contains(github.event.issue.labels.*.name, 'bug-report')",
                      wf)
        self.assertNotIn('needs-session', wf,
                         'the manual label must not be a trigger anywhere')

    def test_the_relay_defaults_to_autofix_when_the_field_is_absent(self):
        """An older build sends no field; it must not park the report."""
        js = (pathlib.Path(run.__file__).resolve().parents[2]
              / 'relay' / 'worker.js').read_text()
        self.assertIn("form.get('autofix') ?? '1'", js)
        self.assertIn("env.MANUAL_LABEL || 'needs-session'", js)


class ExpandCostTest(unittest.TestCase):
    """98% of what a round costs is thinking, and expand rounds think hardest.

    Measured on issue #12: 89% of the $0.3583 was output tokens, and 98.3% of
    those were reasoning. Its two `expand` rounds — which produced no code at
    all — cost 26,645 output tokens, $0.1055, 29% of the run. The model was
    reasoning its way to a fix before noticing it needed a file, and every bit
    of that was re-derived next round with the file in hand.
    """

    def test_the_prefix_says_to_decide_early_and_stop(self):
        import model
        self.assertIn('DECIDE THAT FIRST', model.SYSTEM)
        self.assertIn('cheapest round in the run', model.SYSTEM)

    def test_the_prefix_says_a_different_part_may_be_asked_for(self):
        import model
        self.assertIn('DIFFERENT part of a file you have already been shown',
                      model.SYSTEM)

    def test_it_is_all_in_the_cached_prefix(self):
        """Saying it costs $0.0441/M here and a round anywhere else."""
        import model
        self.assertNotIn('DECIDE THAT FIRST', model.ask.__doc__ or '')


class UnrunChangeTest(unittest.TestCase):
    """"How much of the diff ran" was the wrong question, twice.

    Both wrong fixes for #12 changed a pure function AND the widget path that
    is meant to call it, then tested only the pure function — about a quarter
    of the added lines, clearing a floor of 0.20 by a whisker. The sharp
    question is whether there is code you changed that your test never entered
    at all. `_sendFile` was rewritten in both attempts and entered by neither.
    """

    SRC = ('List<String> exportFormatsFor(String kind) {\n'      # 1
           "  if (kind == 'ptp') {\n"                            # 2
           "    return ['stl', 'step'];\n"                       # 3
           '  }\n'                                               # 4
           "  return ['step'];\n"                                # 5
           '}\n'                                                 # 6
           '\n'                                                  # 7
           'Future<void> sendFile(String name) async {\n'        # 8
           '  final formats = exportFormatsFor(name);\n'         # 9
           '  if (formats.length > 1) {\n'                       # 10
           '    await chooser(formats);\n'                       # 11
           '  }\n'                                               # 12
           '}\n')                                                # 13

    def build(self, counts):
        """A repo whose diff added lines 2,3,9,10, with lcov saying `counts`."""
        tmp = pathlib.Path(tempfile.mkdtemp())
        lib = tmp / 'frontend/lib/widgets'
        lib.mkdir(parents=True)
        (tmp / 'frontend/coverage').mkdir(parents=True)
        f = lib / 'home_view.dart'
        f.write_text('\n')
        for cmd in (['git', 'init', '-q', '.'],
                    ['git', 'config', 'user.email', 't@e'],
                    ['git', 'config', 'user.name', 't'],
                    ['git', 'add', '-A'], ['git', 'commit', '-qm', 'base']):
            subprocess.run(cmd, cwd=tmp, capture_output=True)
        f.write_text(self.SRC)
        lcov = ['SF:lib/widgets/home_view.dart']
        lcov += [f'DA:{n},{c}' for n, c in counts.items()]
        lcov.append('end_of_record')
        (tmp / 'frontend/coverage/lcov.info').write_text('\n'.join(lcov) + '\n')
        return tmp

    def test_a_changed_function_the_test_never_enters_is_named(self):
        import verify
        # exportFormatsFor ran; sendFile did not — #12's shape exactly.
        root = self.build({2: 5, 3: 5, 9: 0, 10: 0, 11: 0})
        self.assertEqual(verify.unrun_changes([], root),
                         ['lib/widgets/home_view.dart:sendFile'])

    def test_when_the_test_drives_both_it_passes(self):
        import verify
        root = self.build({2: 5, 3: 5, 9: 2, 10: 2, 11: 1})
        self.assertEqual(verify.unrun_changes([], root), [])

    def test_one_executed_line_is_enough_to_count_as_entered(self):
        """A branch not taken is not the same as a function never called."""
        import verify
        root = self.build({2: 5, 3: 5, 9: 1, 10: 1, 11: 0})
        self.assertEqual(verify.unrun_changes([], root), [])

    def test_no_coverage_data_never_blocks(self):
        import verify
        root = self.build({2: 5, 3: 5, 9: 0, 10: 0})
        (root / 'frontend/coverage/lcov.info').unlink()
        self.assertEqual(verify.unrun_changes([], root), [],
                         'absence of evidence must not block a fix')

    def test_the_ratio_gate_would_have_let_this_through(self):
        """Why the ratio was not enough, stated as a number."""
        import verify
        root = self.build({2: 5, 3: 5, 9: 0, 10: 0, 11: 0})
        added = verify.added_lib_lines(root)
        executable = {2, 3, 9, 10, 11}
        changed = added['lib/widgets/home_view.dart'] & executable
        ran = {2, 3}
        self.assertGreater(len(ran) / len(changed), verify.COVERAGE_FLOOR,
                           'the ratio clears the floor; the sharp rule does not')


class UnrunStandsDownTest(unittest.TestCase):
    def test_it_is_a_soft_rejection(self):
        """A path behind `NativeMenu.isSupported` cannot be entered on Linux.

        One refusal is the round that matters — both of #12's wrong fixes
        would have been sent back on it, and neither had an excuse — but a
        gate that CANNOT be satisfied would burn the whole budget instead.
        """
        import verify
        self.assertTrue(any(m in 'your test never runs `x`'
                            for m in verify.SOFT_REJECTIONS))

    def test_the_always_avoidable_gates_are_still_hard(self):
        import verify
        for reason in ('your test reads the source file and asserts',
                       'and nothing in the app calls it'):
            self.assertFalse(any(m in reason for m in verify.SOFT_REJECTIONS))


class LogEvidenceTest(unittest.TestCase):
    """The log window must never imply it holds what it does not.

    Issue #12 was reported as "export does nothing". The bundle's log ended
    fifty seconds before the report with the last line of a cold start, and the
    pack handed the model sixty lines of FFI probes under a heading promising
    the session up to the moment of the report. Three attempts in a row then
    asserted which branch of the export code had run — from a file that could
    not possibly say. The absence has to be stated, or it reads as evidence.
    """

    LAUNCH = ['2026-09-01T10:00:%02d.000000 [INFO ] main: boot step %d' % (i, i)
              for i in range(40)]
    REPORT = ['2026-09-01T10:05:02.000000 [INFO ] bug: === BUG REPORT REQUESTED ===',
              '2026-09-01T10:05:02.000100 [INFO ] bug: description: export does nothing']

    def evidence(self, lines):
        import pack
        return pack.log_evidence('\n'.join(lines))

    def test_silence_before_the_report_is_stated_outright(self):
        out = self.evidence(self.LAUNCH + self.REPORT)
        self.assertIn('does not contain the fault', out)
        self.assertIn('uninstrumented', out)
        self.assertIn('Do not assert one', out)

    def test_the_silence_is_measured(self):
        out = self.evidence(self.LAUNCH + self.REPORT)
        # 10:00:39 -> 10:05:02 is 263 s.
        self.assertIn('263 seconds', out)

    def test_a_logged_action_raises_no_warning(self):
        acted = self.LAUNCH + [
            '2026-09-01T10:05:00.000000 [INFO ] menu: picked "export" on gallery/Flange',
            '2026-09-01T10:05:01.000000 [INFO ] gallery: export "Flange" (part=true)',
        ] + self.REPORT
        out = self.evidence(acted)
        self.assertNotIn('does not contain the fault', out)
        self.assertIn('picked "export"', out)

    def test_the_window_is_the_burst_not_a_fixed_tail(self):
        import pack
        # Two hours of idle, then a long burst of user activity.
        old = ['2026-09-01T08:00:%02d.000000 [INFO ] main: yesterday %d' % (i, i)
               for i in range(40)]
        burst = ['2026-09-01T10:05:%02d.000000 [INFO ] ui: step %d' % (i % 60, i)
                 for i in range(30)]
        out = self.evidence(old + burst + self.REPORT)
        self.assertNotIn('yesterday', out)
        self.assertIn('ui: step 0', out)

    def test_the_window_is_bounded(self):
        import pack
        chatty = ['2026-09-01T10:05:00.%06d [INFO ] ui: step %d' % (i, i)
                  for i in range(400)]
        out = self.evidence(chatty + self.REPORT)
        body = out.split('```')[1].strip().splitlines()
        self.assertLessEqual(len(body), pack.LOG_TAIL_MAX)

    def test_an_empty_log_says_so_rather_than_crashing(self):
        self.assertIn('empty', self.evidence(['   ', '']))

    def test_the_guide_no_longer_promises_the_moment_of_the_report(self):
        import pack
        self.assertNotIn('ending at the moment the report was filed',
                         pack.BUNDLE_GUIDE)


DECLINE = '''<cannot-fix>
Symptom: tapping Export on a gallery card does nothing at all, and the
STL/STEP chooser never appears.
Candidate A: the card is not classified as a part, so `_sendFile` takes the
sketch branch, `sketchExportPath` returns null and the method returns before
presenting anything.
Candidate B: the classification is right and the file is written, but UIKit
refuses to present the sheet because the context menu is still dismissing, so
the picker never appears.
Missing: one log line inside `_sendFile` saying which branch ran. The bundle's
log stops fifty seconds before the report, so neither reading can be ruled out.
</cannot-fix>'''


class DeclineTest(unittest.TestCase):
    """The pipeline must be able to say "this report does not decide it".

    Three runs on #12 shipped a fix apiece on a premise the bundle could not
    support, because the only outcomes available were a fix or a crash. Each
    one closed the issue, and the export button still did nothing. Declining is
    the correct answer to a report whose evidence does not separate two faults
    — but only when the model has looked, and only when it names what would
    settle it, or the exit becomes the cheap way out of every hard round.
    """

    def drive(self, replies, max_rounds=4):
        h = Harness(replies)
        handed = []
        with mock.patch.object(run.model, 'ask', h.ask), \
             mock.patch.object(run.gh, 'ensure_labels'), \
             mock.patch.object(run.gh, 'claim', return_value=True), \
             mock.patch.object(run.gh, 'issue',
                               return_value={'title': 'export does nothing',
                                             'body': ''}), \
             mock.patch.object(run.gh, 'close',
                               side_effect=lambda n, b=None: h.closed.append(n)), \
             mock.patch.object(run.gh, 'block',
                               side_effect=lambda n, b: h.blocked.append(b)), \
             mock.patch.object(run.gh, 'hand_off',
                               side_effect=lambda n, b: handed.append(b)), \
             mock.patch.object(run.edits_mod, 'apply', return_value=[]), \
             mock.patch.object(run.verify, 'gate', return_value=(True, '', '')), \
             mock.patch.object(run.verify, 'full_verification',
                               return_value=(True, '', '')), \
             mock.patch.object(run, 'git_reset'), \
             mock.patch.object(run, 'ship',
                               side_effect=lambda *a, **k: h.shipped.append(a) or 'abc1234'), \
             mock.patch('sys.argv', ['run.py', '--issue', '12',
                                     '--max-rounds', str(max_rounds)]):
            code = run.main()
        return code, h, handed

    def test_a_reasoned_refusal_is_handed_to_a_person(self):
        expand = '<expand path="frontend/lib/widgets/home_view.dart">_sendFile</expand>'
        code, h, handed = self.drive([expand, DECLINE])
        self.assertEqual(code, 0)
        self.assertEqual(h.shipped, [])
        self.assertEqual(h.blocked, [])
        self.assertEqual(len(handed), 1)
        self.assertIn('does not separate two different', handed[0])
        self.assertIn('Candidate B', handed[0])

    def test_refusing_before_looking_is_sent_back(self):
        code, h, handed = self.drive([DECLINE, answer()])
        self.assertEqual(handed, [])
        self.assertEqual(len(h.shipped), 1)
        self.assertIn('asked for nothing', h.asked[1])

    def test_a_shapeless_refusal_is_sent_back_for_the_missing_halves(self):
        vague = '<cannot-fix>\nI cannot tell what is wrong here.\n</cannot-fix>'
        code, h, handed = self.drive([vague, vague, answer()])
        self.assertEqual(handed, [])
        self.assertEqual(len(h.shipped), 1)
        self.assertIn('not usable as written', h.asked[2])

    def test_a_refusal_alongside_a_real_fix_is_ignored(self):
        # Edits win: the tag is an exit, not an annotation.
        code, h, handed = self.drive([answer() + '\n' + DECLINE])
        self.assertEqual(handed, [])
        self.assertEqual(len(h.shipped), 1)

    def test_the_declaration_must_name_two_candidates(self):
        one = ('<cannot-fix>\nSymptom: x does nothing.\n'
               'Candidate A: the branch is wrong and returns early before it '
               'ever reaches the presentation, which is a long enough sentence '
               'to clear the length floor on its own without any help at all.\n'
               'Missing: a log line.\n</cannot-fix>')
        self.assertEqual(run.declined(one), '')
        self.assertIsNone(run.declined('just prose'))
