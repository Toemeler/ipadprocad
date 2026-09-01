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
    if not errors:
        return True, 'analyze: 0 errors'
    # ONLY the errors go back. This repo carries ~61 pre-existing infos and
    # warnings, and clipping the raw output kept the head and tail of that
    # noise while eliding the actual errors in the middle — so the repair
    # prompt showed the model a wall of deprecations and not its own mistake.
    others = len(out.splitlines()) - len(errors)
    return False, clip('\n'.join(errors)
                       + f'\n\n({others} pre-existing infos/warnings omitted)')


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


# The same shapes as ADDED_DECL_RE, without the diff's `+`.
DECL_NAME_RE = re.compile(
    r'^\s*(?:(?:static|final|const|abstract|late|external)\s+)*'
    r'(?:class|mixin|extension|enum|typedef)\s+(\w+)'
    r'|^\s*(?:(?:static|external)\s+)*'
    r'(?:Future<[^>]*>|void|bool|int|double|String|num|dynamic|'
    r'List<[^>]*>|Map<[^>]*>|Set<[^>]*>|[A-Z]\w*<[^>]*>|[A-Z]\w*\??)'
    r'\s+(?:get\s+|set\s+)?(\w+)\s*[({=]')


def _enclosing_decls(root=ROOT):
    """The declarations whose BODIES this change edits. -> {name}

    Why this is separate from the added/removed scan: issue #12's shipped fix
    changed two lines INSIDE `exportFormatsFor`. It added no declaration and
    removed no reference, so nothing looked at the function itself — and the
    function has no caller in `lib/` at all.
    """
    diff = subprocess.run(['git', 'diff', '--unified=0', '--', 'frontend/lib'],
                          cwd=root, capture_output=True, text=True).stdout
    names, text = set(), []
    for line in diff.splitlines():
        if line.startswith('+++ b/'):
            path = root / line[6:].strip()
            text = (path.read_text(encoding='utf-8', errors='replace')
                    .splitlines() if path.exists() else [])
        elif line.startswith('@@') and text:
            m = re.match(r'@@ -\S+ \+(\d+)', line)
            if not m:
                continue
            for i in range(min(int(m.group(1)), len(text)) - 1, -1, -1):
                found = DECL_NAME_RE.match(text[i])
                if found:
                    names.add(found.group(1) or found.group(2))
                    break
    return names


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
    # A symbol the change ORPHANS is as dead as one it invents, and issue #10
    # shipped exactly that: it rewrote the STL writer inline and left
    # `_writeBinaryStl` declared and unreferenced on main, where `flutter
    # analyze` has warned about it on every run since. Anything the diff
    # REMOVED a reference to is therefore checked as well.
    for line in lines:
        if line.startswith('-') and not line.startswith('---'):
            for word in re.findall(r'[A-Za-z_]\w{3,}', line[1:]):
                names.add(word)
    # AND THE DECLARATIONS THIS CHANGE EDITED THE INSIDE OF.
    #
    # Issue #12 is why. Its fix changed two lines within `exportFormatsFor` —
    # adding no declaration and removing no reference, so neither scan above
    # looked at the function — and `exportFormatsFor` is called from `lib/`
    # exactly nowhere. The test called it, the coverage gate saw the changed
    # lines execute, the test-first gate saw it fail then pass, and the shipped
    # commit could not affect the app at all. A change to app code has to be
    # reachable FROM app code; otherwise it is a change to the test suite
    # wearing a fix's commit message.
    names |= _enclosing_decls(root)
    if not names:
        return []
    dead = []
    for name in sorted(names):
        if name in FRAMEWORK_CALLED:
            continue
        # LINES, not a count, because a count cannot tell a CALL from a
        # MENTION: a doc comment naming the function reads as a second
        # occurrence and the old "exactly one" rule then saw a caller. That is
        # not what let issue #12 through — there the enclosing declaration was
        # simply never examined — but it is the same rule being credulous, and
        # `exportFormatsFor` carries a doc comment two lines long.
        hits = subprocess.run(
            ['git', 'grep', '-w', '-n', '--no-color', name, '--', 'frontend/lib'],
            cwd=root, capture_output=True, text=True).stdout
        callers, declared = 0, False
        for hit in hits.splitlines():
            body = hit.split(':', 2)[-1]
            if COMMENT_LINE_RE.match(body):
                continue
            found = DECL_NAME_RE.match(body)
            if not declared and found and (found.group(1) or found.group(2)) == name:
                declared = True   # the declaration is not a use of itself
                continue
            callers += 1
        # No CODE line other than the declaration mentions it. A name that is
        # not declared in lib/ at all is not evidence of anything — most words
        # on a removed line are not symbols — so `declared` is required.
        if declared and callers == 0:
            dead.append(name)
    return dead


COMMENT_LINE_RE = re.compile(r'\s*(?://|///|/\*|\*)')

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


# How much of the changed code the new test has to actually run.
#
# Not 100 %: a fix legitimately adds error branches, platform-guarded paths and
# `else` arms that a host test cannot reach. 20 % is a floor that says "this
# test executes the change" without dictating how thoroughly.
COVERAGE_FLOOR = 0.20

# Rejections that `allow_weak` stands down after one attempt, because they can
# be genuinely impossible to satisfy: some features cannot be asserted without
# naming new symbols, and some changed lines are platform-guarded and
# unreachable from a host test.
#
# The other two quality gates — a test that greps its own diff, a helper with
# no callers — are ALWAYS avoidable and are never stood down.
#
# `never runs` joins the soft list for the same reason the coverage floor is
# soft: a function behind `if (NativeMenu.isSupported)` cannot be entered from
# a Linux host however the test is written, and a gate that cannot be satisfied
# is a gate that burns the whole budget. It gets ONE refusal, which is the
# round that matters — both wrong fixes for issue #12 would have been sent back
# on it, and neither had an excuse.
SOFT_REJECTIONS = ('regression pin', 'not exercising the fix', 'never runs')

LCOV_SF_RE = re.compile(r'^SF:(.+)$')
LCOV_DA_RE = re.compile(r'^DA:(\d+),(\d+)')


def added_lib_lines(root=ROOT):
    """{frontend-relative path: {line numbers this change added}}"""
    diff = subprocess.run(['git', 'diff', '--unified=0', '--', 'frontend/lib'],
                          cwd=root, capture_output=True, text=True).stdout
    out, current, line_no = {}, None, 0
    for line in diff.splitlines():
        if line.startswith('+++ b/'):
            current = line[6:]
            if current.startswith('frontend/'):
                current = current[len('frontend/'):]
            out.setdefault(current, set())
        elif line.startswith('@@'):
            m = re.search(r'\+(\d+)', line)
            line_no = int(m.group(1)) if m else 0
        elif line.startswith('+') and not line.startswith('+++'):
            if current is not None:
                out[current].add(line_no)
            line_no += 1
    return {k: v for k, v in out.items() if v}


def _parse_lcov(text):
    out, current = {}, None
    for line in text.splitlines():
        m = LCOV_SF_RE.match(line)
        if m:
            current = m.group(1)
            if current.startswith('frontend/'):
                current = current[len('frontend/'):]
            out.setdefault(current, {})
            continue
        m = LCOV_DA_RE.match(line)
        if m and current is not None:
            out[current][int(m.group(1))] = int(m.group(2))
    return out


def coverage_of_change(test_paths, root=ROOT):
    """Does the new test actually EXECUTE the changed code? -> (hit, total)

    THE GENERAL FORM OF A PROBLEM THAT KEPT COMING BACK IN NEW COSTUMES.

    Three gates were added for three specific evasions — a test that only fails
    to compile, a helper nothing calls, a test that greps its own diff — and
    each was cleared honestly by the next answer. They share one shape: the
    test does not RUN the code that changed. That is measurable directly.

    `flutter test --coverage` reports which lines executed; the diff says which
    lines are new. A test that never touches the change cannot be pinning it,
    whatever else it asserts, and lines are counted rather than intentions.

    Only lines lcov considers executable are counted, so comments, blank lines
    and closing braces do not drag the ratio down.
    """
    added = added_lib_lines(root)
    if not added:
        return 0, 0
    code, _ = _run(['flutter', 'test', '--no-pub', '--coverage']
                   + [_frontend_relative(p) for p in test_paths],
                   SINGLE_TEST_TIMEOUT)
    lcov = pathlib.Path(root) / 'frontend' / 'coverage' / 'lcov.info'
    if not lcov.is_file():
        return 0, 0          # no data is not evidence of absence; do not block
    data = _parse_lcov(lcov.read_text(encoding='utf-8', errors='ignore'))
    hit = total = 0
    for path, lines in added.items():
        counts = data.get(path)
        if not counts:
            continue
        for line in lines:
            if line in counts:      # lcov lists only executable lines
                total += 1
                if counts[line] > 0:
                    hit += 1
    return hit, total


def _decl_at(lines, line_no):
    """The declaration whose body contains 1-based `line_no`. -> name or None."""
    for i in range(min(line_no, len(lines)) - 1, -1, -1):
        found = DECL_NAME_RE.match(lines[i])
        if found:
            return found.group(1) or found.group(2)
    return None


def unrun_changes(test_paths, root=ROOT):
    """Declarations this change edits that the test never ENTERS. -> [names]

    WHY A RATIO WAS THE WRONG SHAPE, measured on issue #12's two attempts.

    `coverage_of_change` asks what FRACTION of the added lines ran. Both wrong
    fixes for #12 changed a pure function AND the widget path that is supposed
    to call it, then tested only the pure function — about a quarter of the
    added lines, which cleared a floor of 0.20 by a whisker. Twice.

    The sharp question is not "how much of the diff ran" but "is there code you
    changed that your test never entered at all". `_sendFile` was rewritten in
    both attempts and entered by neither, and saying exactly that is a better
    rejection than any percentage: a fix whose author never runs the path it
    edits is guessing about what flows through it, which is precisely how both
    attempts invented a premise about the shape of a document name.

    Framework lifecycle methods are exempt, as everywhere else — nothing calls
    `build` explicitly, and a widget test enters it without naming it.
    """
    added = added_lib_lines(root)
    if not added:
        return []
    lcov = pathlib.Path(root) / 'frontend' / 'coverage' / 'lcov.info'
    if not lcov.is_file():
        return []            # no data is not evidence of absence
    data = _parse_lcov(lcov.read_text(encoding='utf-8', errors='ignore'))
    cold = []
    for path, changed in sorted(added.items()):
        counts = data.get(path)
        if not counts:
            continue         # the file is not in the report at all
        text = (root / 'frontend' / path).read_text(
            encoding='utf-8', errors='replace').splitlines()
        entered, seen = {}, {}
        for line in changed:
            if line not in counts:
                continue     # not executable: a comment, a brace, a blank
            name = _decl_at(text, line) or '(top level)'
            seen[name] = True
            entered[name] = entered.get(name, False) or counts[line] > 0
        for name, ran in sorted(entered.items()):
            if not ran and name not in FRAMEWORK_CALLED:
                cold.append(f'{path}:{name}')
    return cold


def gate(apply_tests, apply_code, revert, test_paths, allow_weak=False,
         code_paths=()):
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

    # Swift first, and before the suite: it is the half nothing downstream can
    # check, and it costs milliseconds against the three minutes the suite
    # takes. A broken channel contract is not worth finding out about later.
    swift = swift_braces(code_paths) + swift_contract(code_paths)
    if swift:
        return (False,
                'your platform-channel change does not line up across the two '
                'languages', '\n'.join(swift))

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

    hit, total = coverage_of_change(test_paths)
    # Named first, because "you never ran `_sendFile`" is a better sentence
    # than any percentage, and it reuses the lcov the line above just wrote.
    cold = unrun_changes(test_paths)
    if cold and not allow_weak:
        return (False,
                'your test never runs ' + ', '.join(f'`{c}`' for c in cold[:3])
                + ', and you changed ' + ('them' if len(cold) > 1 else 'it')
                + '. A fix whose author never enters the path it edits is '
                'guessing about what flows through it. Drive that path in the '
                'test — pump the widget and perform the interaction the report '
                'describes, or call the function with the values the app '
                'really passes it.',
                '')
    if total and hit / total < COVERAGE_FLOOR and not allow_weak:
        return (False,
                f'your test runs only {hit} of the {total} executable lines '
                f'this change adds ({hit / total:.0%}). Whatever it asserts, '
                'it is not exercising the fix. Call the changed code path and '
                'assert what it does — for a widget, pump it and drive the '
                'interaction the report describes.',
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


# A failing test, in either reporter. Actions sets GITHUB_ACTIONS, so
# `flutter test` prints `::group::❌ /abs/path/x_test.dart: name (failed)`;
# run by hand it prints `path/x_test.dart: name [E]`.
FAILED_LINE_RE = re.compile(r'\u274c|\[E\]')
TEST_FILE_RE = re.compile(r'([\w./-]*?[\w-]+_test\.dart)')


def failing_test_files(output):
    """-> repo-relative test files named on a failing line, in order, no dupes."""
    seen = []
    for line in (output or '').splitlines():
        if not FAILED_LINE_RE.search(line):
            continue
        m = TEST_FILE_RE.search(line)
        if not m:
            continue
        path = m.group(1)
        cut = path.find('frontend/test/')
        path = path[cut:] if cut >= 0 else path
        if not path.startswith('frontend/'):
            path = 'frontend/' + path.lstrip('/')
        if path not in seen:
            seen.append(path)
    return seen


# ---------------------------------------------------------------------------
# SWIFT: THE HALF THIS RUNNER CANNOT COMPILE
#
# Swift needs Xcode and an Apple SDK, so on a Linux runner there is no build,
# no test and no analyzer for it. Until now that meant a Swift change shipped
# on the model's word alone and was found out — if at all — by the macOS build
# minutes later, with the issue already closed.
#
# Two things ARE checkable here, and between them they cover the way these
# actually break.
#
# 1. THE CHANNEL CONTRACT. Every Dart→UIKit call is a method name and a bag of
#    string keys, matched by hand on the other side. Issues #7 and #8 were both
#    Dart+Swift, and this seam is where such a change silently does nothing: a
#    `case` that was never added, or a key spelled `colour` on one side and
#    `color` on the other, compiles perfectly on BOTH sides and is a no-op at
#    runtime. Neither the Dart suite nor the macOS build would fail. This is
#    the one class of Swift defect a Linux runner can catch, and it is the
#    likeliest one.
#
# 2. BRACES. A search/replace that drops a closing brace is a compile error the
#    macOS job would find twenty minutes later; counting them costs a
#    millisecond.
#
# Only the methods the DIFF touches are checked. The repository has channel
# calls this pipeline did not write, and blocking a fix for a pre-existing
# mismatch would be charging the model for someone else's debt.

# `_ch.invokeMethod<void>('setAccent', {'light': light, 'dark': dark})`
INVOKE_RE = re.compile(
    r"""invokeMethod(?:<[^>]*>)?\(\s*['"]([A-Za-z_]\w*)['"]"""
    r"""(?:\s*,\s*(\{[^{}]*\}))?""", re.S)
# The keys inside that map literal: `'light': light`
MAP_KEY_RE = re.compile(r"""['"](\w+)['"]\s*:""")
# `case "setAccent":` and `case "setViewportColor", "setFloorColor":`
SWIFT_CASE_RE = re.compile(r'case\s+((?:"[^"]*"\s*,\s*)*"[^"]*")\s*:')
SWIFT_STR_RE = re.compile(r'"([^"]*)"')
# Any subscript by string literal: `args["light"]`, `a["argb"]`, `m["id"]`
SWIFT_KEY_RE = re.compile(r'\[\s*"(\w+)"\s*\]')


def _swift_side(dart_path):
    """The plugin's Swift sources for a Dart file, or [] if it has none."""
    parts = pathlib.Path(dart_path).parts
    if 'packages' not in parts:
        return []
    pkg = ROOT.joinpath(*parts[:parts.index('packages') + 2])
    classes = pkg / 'ios' / 'Classes'
    return sorted(classes.glob('*.swift')) if classes.is_dir() else []


def swift_braces(paths):
    """-> [complaint] for a changed .swift file whose brackets do not close."""
    out = []
    for rel in paths:
        if not str(rel).endswith('.swift'):
            continue
        text = (ROOT / rel).read_text(encoding='utf-8', errors='replace')
        # Comments and string literals hold braces that are not structure.
        stripped = re.sub(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\\n])*"', '',
                          text, flags=re.S)
        for open_c, close_c in (('{', '}'), ('(', ')'), ('[', ']')):
            a, b = stripped.count(open_c), stripped.count(close_c)
            if a != b:
                out.append(f'{rel}: {a} `{open_c}` against {b} `{close_c}` — '
                           'the edit did not close what it opened')
    return out


def swift_contract(paths):
    """Do the Dart calls this change makes exist on the Swift side?

    -> [complaint]. Empty when there is no Dart→Swift call in the diff.
    """
    out = []
    for rel in paths:
        rel = str(rel)
        if not rel.endswith('.dart'):
            continue
        swift_files = _swift_side(rel)
        if not swift_files:
            continue
        swift = '\n'.join(f.read_text(encoding='utf-8', errors='replace')
                           for f in swift_files)
        handled = set()
        for m in SWIFT_CASE_RE.finditer(swift):
            handled.update(SWIFT_STR_RE.findall(m.group(1)))
        keys = set(SWIFT_KEY_RE.findall(swift))
        dart = (ROOT / rel).read_text(encoding='utf-8', errors='replace')
        for call in INVOKE_RE.finditer(dart):
            method = call.group(1)
            if method not in changed_lines(rel):
                continue  # not this change's business
            if method not in handled:
                out.append(
                    f'{rel} calls `{method}` over the platform channel and no '
                    f'Swift `case "{method}":` handles it. Add the case in '
                    f'{swift_files[0].parent.relative_to(ROOT)}/, or the call '
                    'compiles on both sides and does nothing at runtime.')
                continue
            for key in MAP_KEY_RE.findall(call.group(2) or ''):
                if key not in keys:
                    out.append(
                        f'{rel} sends `{key}` to `{method}` and no Swift file '
                        f'reads `["{key}"]`. A key spelled differently on the '
                        'two sides compiles and is silently ignored.')
    return out


def changed_lines(rel):
    """The text this change ADDED to one file, for "is this ours?" questions."""
    code, out = _run(['git', 'diff', '--unified=0', '--', rel],
                     60, cwd=ROOT)
    if code != 0:
        return ''
    return '\n'.join(ln for ln in out.splitlines() if ln.startswith('+'))


def full_verification(revert=None, reapply=None):
    """analyze + the whole suite. -> (ok, reason, log)

    WHY THIS TAKES revert/reapply
    -----------------------------
    The suite is the last gate and it is all-or-nothing, so ANY red test on
    `main` blocks every fix the pipeline could ever write — the model is
    charged for a failure it did not cause, gets handed a log about code it
    never touched, and burns its four rounds guessing at it.

    That is not hypothetical. `s10_analyze_memory_test` measures RSS deltas and
    its own instrument gate was set at the line where a reading is provably
    impossible rather than where it stops being trustworthy, so it failed on
    `main` at 45d1222a and skipped on the very next run of the same commit
    range. Issue #11 was in the fixer at the time.

    "The diff did not touch that file" is not enough to acquit a change — a
    one-line edit to `theme.dart` breaks `m236_theme_test` — so the check is
    the only one that settles it: revert everything, run exactly the files that
    failed, and see whether they still fail with the fix gone. If they do, the
    fix did not cause them. Without `revert`/`reapply` the old all-or-nothing
    behaviour is kept, which is what the unit tests want.
    """
    ok, out = analyze()
    if not ok:
        return False, '`flutter analyze` reports errors', clip(out)
    ok, out = test()
    if ok:
        return True, '', ''

    red = failing_test_files(out) if (revert and reapply) else []
    if red:
        revert()
        clean, _ = test(red)
        errs = reapply()
        if errs:
            return (False, 'the fix could not be re-applied after checking '
                    'whether the failure was pre-existing', clip(str(errs)))
        if not clean:
            print('  full suite: ' + ', '.join(red) + ' fail on main WITHOUT '
                  'this change too — not charging them to the fix')
            return True, '', ''
    return False, '`flutter test` (full suite) fails', clip(out)
