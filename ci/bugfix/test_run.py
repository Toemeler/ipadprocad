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
        import rank
        index = rank.Index()
        text = run.repair_prompt(index, 'the code edits did not apply',
                                 self.LOG, 'accent colour settings',
                                 ['frontend/lib/theme.dart'])
        self.assertIn('static Color get accent => scheme.value.accent;', text)
        self.assertIn('final Color accent;', text)


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
