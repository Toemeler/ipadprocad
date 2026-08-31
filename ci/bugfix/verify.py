#!/usr/bin/env python3
"""Proving the fix works, without asking the model whether it does.

WHY THIS IS A FILE AND NOT A PARAGRAPH IN A PROTOCOL
-----------------------------------------------------
HANDOFF.md's doctrine is "Nur echten Status berichten — nie 'grün' behaupten,
was nicht gebaut wurde". Until now that was enforced by asking the model
nicely, in a markdown file that the conversation condenser was measured
dropping from context five times in a single session. Here the push is
downstream of these functions returning True, so an unverified push is not
disobedience — there is no code path that reaches `git push` without them.

THE TEST-FIRST GATE
-------------------
`gate()` is the part that did not exist before and costs nothing to add.

The old protocol said "a fix with no test is not finished". It did not say the
test has to FAIL without the fix, and nothing checked, so a test asserting the
behaviour the code already had would sail through and pin nothing. This applies
the test alone, requires it to fail, then applies the fix and requires it to
pass. Two extra `flutter test` invocations against one file — seconds of free
CI, and the difference between a regression pin and a decoration.

WHY OUTPUT IS TRUNCATED SO HARD
-------------------------------
Whatever comes back here may be fed to the model as the escalation prompt. A
full `flutter test` failure log runs to thousands of lines; at $1.3184/M for a
cache miss, pasting one back costs more than the call that produced the bug.
FEEDBACK_CHARS is the budget, and it keeps the head and the tail — the failing
assertion is at the top, the summary count at the bottom, and the middle is
nearly always another 900 passing tests.
"""
import os
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
FRONTEND = ROOT / 'frontend'

# What the model is allowed to see of a failure. Enough for the assertion, the
# stack and the counts; not enough to matter on the bill.
FEEDBACK_CHARS = 4000

# The full suite is ~2,977 tests and takes a few minutes. That is free here and
# was not free when a language model was polling it with `sleep 60`.
FULL_SUITE_TIMEOUT = 2400
SINGLE_TEST_TIMEOUT = 600


def _run(args, timeout, cwd=FRONTEND):
    env = dict(os.environ)
    env.setdefault('PUB_CACHE', str(pathlib.Path.home() / '.pub-cache'))
    try:
        p = subprocess.run(args, cwd=cwd, capture_output=True, text=True,
                           timeout=timeout, env=env)
        return p.returncode, (p.stdout or '') + (p.stderr or '')
    except subprocess.TimeoutExpired:
        return 124, f'timed out after {timeout}s: {" ".join(args)}'
    except FileNotFoundError:
        return 127, f'not installed: {args[0]}'


def clip(text, limit=FEEDBACK_CHARS):
    if len(text) <= limit:
        return text
    head = text[: limit * 2 // 3]
    tail = text[-limit // 3:]
    return f'{head}\n\n… [{len(text) - limit} characters elided] …\n\n{tail}'


def pub_get():
    return _run(['flutter', 'pub', 'get'], 600)


# Files gen-l10n writes. Committed on purpose (see l10n.yaml) so a fresh
# checkout can analyze and test without anyone having run the generator.
L10N_GEN = 'frontend/lib/l10n/gen'
ARB_DIR = 'frontend/lib/l10n'


def touches_arb(paths):
    return any(p.startswith(ARB_DIR) and p.endswith('.arb') for p in paths)


def regenerate_l10n():
    """Rebuild lib/l10n/gen from the ARBs. -> (ok, output)

    An ARB edit that is not regenerated does not fail loudly: `t.yourNewKey`
    simply does not exist on the generated class, and `flutter analyze` reports
    an undefined getter in the widget rather than anything about localisation.
    The model then tries to fix the widget, which is the wrong file. So this
    runs automatically whenever an edit touched an ARB, before analyze.
    """
    code, out = _run(['flutter', 'gen-l10n'], 300)
    if code == 0:
        return True, out
    # Older Flutter drives gen-l10n from `pub get` (pubspec `generate: true`).
    code, out2 = _run(['flutter', 'pub', 'get'], 600)
    return code == 0, clip(out + out2)


def analyze():
    """0 errors required. Infos and warnings are pre-existing noise in this repo."""
    code, out = _run(
        ['flutter', 'analyze', '--no-pub', '--no-fatal-infos',
         '--no-fatal-warnings'], 900)
    if code == 0:
        return True, out
    # `flutter analyze` exits non-zero for warnings too depending on version;
    # the repo's own bar is "0 errors", so that is what is checked.
    errors = [ln for ln in out.splitlines() if re.match(r'\s*error\s+•', ln)]
    return (not errors), clip(out if errors else 'analyze: 0 errors\n' + out)


def _frontend_relative(path):
    """Repo-relative -> frontend-relative.

    Everything else in the pipeline names files from the repo root, because
    that is what the model is shown and what `git add` wants. `flutter test`
    runs with cwd=frontend, so handing it `frontend/test/x_test.dart` produced
    `frontend/frontend/test/x_test.dart`, and the runner reported "Does not
    exist".

    That was not merely noisy: it silently defeated the test-first gate. The
    gate requires the new test to FAIL before the fix, and a path that cannot
    be loaded fails -- so the check passed for the wrong reason on every run,
    and then the same bad path failed again after the fix and was reported as
    the model's test being broken.
    """
    p = str(path)
    return p[len('frontend/'):] if p.startswith('frontend/') else p


def test(paths=None, timeout=None):
    args = ['flutter', 'test', '--no-pub']
    if paths:
        args += [_frontend_relative(p) for p in paths]
    code, out = _run(args, timeout or (SINGLE_TEST_TIMEOUT if paths else FULL_SUITE_TIMEOUT))
    return code == 0, out


# A pre-fix run that failed to COMPILE proves only that a symbol was missing.
COMPILE_FAIL_RE = re.compile(
    r'Failed to load|Compilation failed|Error: Method not found|'
    r"Error: (?:The (?:method|getter|setter) '[^']+' isn't defined|"
    r"Type '[^']+' not found|Undefined name)",
    re.IGNORECASE)


def failed_to_compile(output):
    return bool(COMPILE_FAIL_RE.search(output or ''))


# A top-level Dart declaration in an added line.
ADDED_DECL_RE = re.compile(
    r'^\+\s*(?:(?:static|final|const|abstract|late|external)\s+)*'
    r'(?:class|mixin|extension|enum|typedef)\s+(\w+)'
    r'|^\+\s*(?:(?:static|external)\s+)*'
    r'(?:Future<[^>]*>|void|bool|int|double|String|num|dynamic|'
    r'List<[^>]*>|Map<[^>]*>|Set<[^>]*>|[A-Z]\w*<[^>]*>|[A-Z]\w*\??)'
    r'\s+(\w+)\s*\(')


# Called by Flutter, Dart or the test runner rather than by app code, so an
# absence of callers proves nothing about them.
FRAMEWORK_CALLED = frozenset((
    'build', 'createState', 'initState', 'dispose', 'didUpdateWidget',
    'didChangeDependencies', 'setState', 'toString', 'hashCode', 'noSuchMethod',
    'main', 'setUp', 'tearDown', 'setUpAll', 'tearDownAll', 'debugFillProperties',
    'reassemble', 'deactivate', 'activate', 'didChangeAppLifecycleState'))


def dead_new_symbols(root=ROOT):
    """New declarations in lib/ that nothing in lib/ ever calls. -> [names]

    THE FAILURE THIS CATCHES, which shipped as 0431693:

        List<String> exportFormatsFor(String kind) => switch (kind) { … };

    added to home_view.dart, referenced by its own test, and called from
    production code exactly nowhere — the dialog it was supposedly describing
    hardcodes 'STL' and 'STEP' inline. The test then "pinned" that function, so
    the gate was satisfied by an artifact invented to satisfy the gate, while
    the behaviour the report actually asked about stayed untested.

    Requiring a behavioural assertion (see gate) does not catch this on its
    own: an assertion about a dead function is still an assertion. What makes
    it detectable is that the symbol has no callers.
    """
    diff = subprocess.run(['git', 'diff', '--unified=0', '--', 'frontend/lib'],
                          cwd=root, capture_output=True, text=True).stdout
    names = set()
    lines = diff.splitlines()
    for i, line in enumerate(lines):
        m = ADDED_DECL_RE.match(line)
        if not m:
            continue
        name = m.group(1) or m.group(2)
        # A framework override has no explicit caller anywhere and would be a
        # false positive that blocks a legitimate fix. Both spellings of the
        # evidence are honoured: an `@override` on the preceding added line,
        # and the lifecycle names Flutter calls for you.
        prev = lines[i - 1] if i else ''
        if '@override' in prev or name in FRAMEWORK_CALLED:
            continue
        names.add(name)
    if not names:
        return []
    dead = []
    for name in sorted(names):
        hits = subprocess.run(
            ['git', 'grep', '-w', '--no-color', '-c', name, '--', 'frontend/lib'],
            cwd=root, capture_output=True, text=True).stdout
        total = sum(int(l.rsplit(':', 1)[1]) for l in hits.splitlines() if ':' in l)
        # One occurrence is the declaration itself; a real symbol has callers.
        if total <= 1:
            dead.append(name)
    return dead


SOURCE_READ_RE = re.compile(r'readAsString|loadString|File\s*\(')
STRING_LITERAL_RE = re.compile(r"'([^'\n]{12,})'|\"([^\"\n]{12,})\"")


def pins_own_source(test_paths, root=ROOT):
    """Test literals that only restate lines this very diff added. -> [snippets]

    THE THIRD COSTUME OF THE SAME PATHOLOGY. Issue #10's test was:

        final source = File('lib/app_state.dart').readAsStringSync();
        expect(source, contains('nx = ay * bz - az * by;'));

    It asserts that a particular spelling of a particular line exists. Rename
    `nx` to `n0` and it fails while the behaviour is identical; delete the call
    to the writer entirely and it still passes. It cleared the compile-only
    gate honestly (it fails by assertion before the fix) and the dead-symbol
    gate honestly, and it still tests nothing.

    The repo does have LEGITIMATE source-asserting tests — m236_theme_test
    fails the build when `Color(0x…)` appears outside theme.dart. That is a
    standing invariant, and its pattern is not drawn from any one diff. The
    distinction drawn here is exactly that: a literal is only flagged when the
    change being verified ADDED it.
    """
    added = set()
    diff = subprocess.run(['git', 'diff', '--unified=0', '--', 'frontend/lib'],
                          cwd=root, capture_output=True, text=True).stdout
    for line in diff.splitlines():
        if line.startswith('+') and not line.startswith('+++'):
            added.add(line[1:].strip())
    if not added:
        return []
    joined = '\n'.join(added)

    offenders = []
    for rel in test_paths:
        path = pathlib.Path(root) / rel
        if not path.is_file():
            continue
        text = path.read_text(encoding='utf-8', errors='ignore')
        if not SOURCE_READ_RE.search(text):
            continue
        for m in STRING_LITERAL_RE.finditer(text):
            lit = (m.group(1) or m.group(2)).strip()
            if lit and lit in joined:
                offenders.append(lit[:60])
    return offenders


def gate(apply_tests, apply_code, revert, test_paths, allow_weak=False):
    """The test-first gate. -> (ok, reason, log)

    `apply_tests`, `apply_code` and `revert` are callables so this function
    stays ignorant of how edits are represented; `run.py` supplies them.
    """
    err = apply_tests()
    if err:
        return False, 'the test edits did not apply', '\n'.join(err)

    passed, out = test(test_paths)
    if passed:
        revert()
        return (False,
                'the new test PASSES without your fix, so it pins nothing. '
                'Write a test that fails against the current code and passes '
                'with your change.',
                clip(out))

    if failed_to_compile(out) and not allow_weak:
        # The loophole this closes, found on issue #9's shipped fix: the test
        # asserted `exportFormatsFor('part') == ['stl','step']` against a pure
        # helper added by the same commit. It "failed before the fix" because
        # the symbol did not COMPILE, not because it described behaviour that
        # was wrong — and by that standard any test naming any new symbol
        # passes this gate automatically. It tested neither the dialog ordering
        # the report asked for nor a byte of the file it writes.
        revert()
        return (False,
                'your test failed before the fix only because the code it '
                'names does not exist yet — that is a compile error, not a '
                'regression pin, and a test like it would pass this check no '
                'matter how the feature behaved. Assert the BEHAVIOUR the '
                'report describes: the order things happen in, the values '
                'produced, the bytes written. Keep the new symbols, and add at '
                'least one assertion that would still fail if they existed but '
                'were wrong.',
                clip(out))

    err = apply_code()
    if err:
        revert()
        return False, 'the code edits did not apply', '\n'.join(err)

    passed, out = test(test_paths)
    if not passed:
        return (False,
                'with your fix applied, your own new test still fails',
                clip(out))

    pinned = pins_own_source(test_paths)
    if pinned:
        return (False,
                'your test reads the source file and asserts that text you '
                'just added appears in it — for example ' +
                ', '.join(f'`{x}`' for x in pinned[:2]) + '. That pins a '
                'spelling, not a behaviour: renaming a local would fail it, '
                'and deleting the call site would not. Exercise the code '
                'instead — call the function and assert what it returns or '
                'writes, or pump the widget and assert what appears.',
                '')

    dead = dead_new_symbols()
    if dead:
        return (False,
                'you added ' + ', '.join(f'`{d}`' for d in dead) + ' and '
                'nothing in the app calls it. A helper that exists only for '
                'its own test pins nothing — wire it into the code path the '
                'report is about, or drop it and test that path directly.',
                '')
    return True, '', ''


def full_verification():
    """analyze + the whole suite. -> (ok, reason, log)"""
    ok, out = analyze()
    if not ok:
        return False, '`flutter analyze` reports errors', clip(out)
    ok, out = test()
    if not ok:
        return False, '`flutter test` (full suite) fails', clip(out)
    return True, '', ''
