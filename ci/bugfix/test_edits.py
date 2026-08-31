#!/usr/bin/env python3
"""Verification for the model→working-tree boundary.

WHY THIS IS THE MOST TESTED FILE IN THE PIPELINE
------------------------------------------------
`edits.py` is the only place where text produced by a language model becomes
changes on disk that are then pushed to `main`. Everything else in the pipeline
either reads (rank, pack) or refuses (verify). So the properties asserted here
are the ones that keep a bad answer from becoming a bad commit:

  * a SEARCH that does not match must fail LOUDLY, never fall through to
    "create the file" — that would land half a module as a new file;
  * an ambiguous SEARCH must fail rather than patch an arbitrary one of the
    matches;
  * a failure in the third block must leave the tree untouched, not
    half-patched, or the escalation round starts from a corrupted checkout;
  * paths the protocol forbids must be rejected here, in code, not merely
    discouraged in a prompt the model may not still be attending to.

Run:  python3 -m unittest discover -s ci/bugfix -p 'test_*.py'
"""
import pathlib
import tempfile
import unittest

import edits


def block(path, search, replace):
    return (f'<file path="{path}">\n<<<<<<< SEARCH\n{search}\n=======\n'
            f'{replace}\n>>>>>>> REPLACE\n</file>')


class TestParse(unittest.TestCase):

    def test_search_replace(self):
        parsed, expands, errors = edits.parse(block('a/b.dart', 'old', 'new'))
        self.assertEqual(errors, [])
        self.assertEqual(len(parsed), 1)
        self.assertEqual((parsed[0].path, parsed[0].search, parsed[0].replace),
                         ('a/b.dart', 'old', 'new'))

    def test_several_blocks_in_one_file(self):
        text = ('<file path="a.dart">\n'
                '<<<<<<< SEARCH\none\n=======\n1\n>>>>>>> REPLACE\n'
                '<<<<<<< SEARCH\ntwo\n=======\n2\n>>>>>>> REPLACE\n</file>')
        parsed, _, errors = edits.parse(text)
        self.assertEqual(errors, [])
        self.assertEqual(len(parsed), 2)

    def test_new_file(self):
        parsed, _, errors = edits.parse(
            '<file path="frontend/test/m9_x_test.dart" new="true">\nbody\n</file>')
        self.assertEqual(errors, [])
        self.assertIsInstance(parsed[0], edits.NewFile)
        self.assertEqual(parsed[0].content, 'body')

    def test_file_without_blocks_is_an_error_not_a_new_file(self):
        # The dangerous misreading: a malformed edit silently creating a file.
        parsed, _, errors = edits.parse('<file path="a.dart">\njust text\n</file>')
        self.assertEqual(parsed, [])
        self.assertTrue(errors)

    def test_expand(self):
        _, expands, _ = edits.parse(
            '<expand path="frontend/lib/theme.dart">floor colour</expand>')
        self.assertEqual(expands[0].path, 'frontend/lib/theme.dart')
        self.assertEqual(expands[0].query, 'floor colour')

    def test_forbidden_paths_rejected(self):
        for path in ('.github/workflows/x.yml', 'relay/worker.js',
                     'ci/bugfix/run.py', 'frontend/lib/l10n/gen/app_l10n.dart',
                     '../outside.dart', '/etc/passwd'):
            with self.subTest(path=path):
                parsed, _, errors = edits.parse(block(path, 'a', 'b'))
                self.assertEqual(parsed, [], path)
                self.assertTrue(errors, path)

    def test_test_paths_recognised(self):
        self.assertTrue(edits.is_test('frontend/test/m1_test.dart'))
        self.assertFalse(edits.is_test('frontend/lib/theme.dart'))


class TestApply(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        (self.root / 'frontend' / 'lib').mkdir(parents=True)
        self.target = self.root / 'frontend' / 'lib' / 'a.dart'
        self.target.write_text('one\ntwo\nthree\n', encoding='utf-8')

    def tearDown(self):
        self.tmp.cleanup()

    def test_applies(self):
        errs = edits.apply([edits.Replace('frontend/lib/a.dart', 'two', '2')],
                           self.root)
        self.assertEqual(errs, [])
        self.assertEqual(self.target.read_text(), 'one\n2\nthree\n')

    def test_missing_search_is_reported_and_writes_nothing(self):
        errs = edits.apply([edits.Replace('frontend/lib/a.dart', 'nope', 'x')],
                           self.root)
        self.assertTrue(errs)
        self.assertIn('not found', errs[0])
        self.assertEqual(self.target.read_text(), 'one\ntwo\nthree\n')

    def test_ambiguous_search_refuses(self):
        self.target.write_text('dup\ndup\n', encoding='utf-8')
        errs = edits.apply([edits.Replace('frontend/lib/a.dart', 'dup', 'x')],
                           self.root)
        self.assertTrue(errs)
        self.assertIn('2 times', errs[0])
        self.assertEqual(self.target.read_text(), 'dup\ndup\n')

    def test_all_or_nothing(self):
        # The second edit is bad; the first must not have landed either, or the
        # escalation round would start from a tree nobody described.
        errs = edits.apply([
            edits.Replace('frontend/lib/a.dart', 'one', '1'),
            edits.Replace('frontend/lib/a.dart', 'absent', 'x'),
        ], self.root)
        self.assertTrue(errs)
        self.assertEqual(self.target.read_text(), 'one\ntwo\nthree\n')

    def test_sequential_edits_to_one_file_see_each_other(self):
        errs = edits.apply([
            edits.Replace('frontend/lib/a.dart', 'one', '1'),
            edits.Replace('frontend/lib/a.dart', 'three', '3'),
        ], self.root)
        self.assertEqual(errs, [])
        self.assertEqual(self.target.read_text(), '1\ntwo\n3\n')

    def test_new_file_created_with_parents(self):
        errs = edits.apply(
            [edits.NewFile('frontend/test/m9_x_test.dart', 'void main() {}')],
            self.root)
        self.assertEqual(errs, [])
        p = self.root / 'frontend' / 'test' / 'm9_x_test.dart'
        self.assertTrue(p.is_file())
        self.assertTrue(p.read_text().endswith('\n'))

    def test_missing_file_reported(self):
        errs = edits.apply([edits.Replace('frontend/lib/gone.dart', 'a', 'b')],
                           self.root)
        self.assertIn('no such file', errs[0])


if __name__ == '__main__':
    unittest.main()
