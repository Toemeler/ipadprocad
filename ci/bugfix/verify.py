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


def test(paths=None, timeout=None):
    args = ['flutter', 'test', '--no-pub']
    if paths:
        args += [str(p) for p in paths]
    code, out = _run(args, timeout or (SINGLE_TEST_TIMEOUT if paths else FULL_SUITE_TIMEOUT))
    return code == 0, out


def gate(apply_tests, apply_code, revert, test_paths):
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

    err = apply_code()
    if err:
        revert()
        return False, 'the code edits did not apply', '\n'.join(err)

    passed, out = test(test_paths)
    if not passed:
        return (False,
                'with your fix applied, your own new test still fails',
                clip(out))
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
