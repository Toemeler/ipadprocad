#!/usr/bin/env python3
"""One bug report, start to finish.

    ci/bugfix/run.py --issue 12
    ci/bugfix/run.py --issue 12 --dry-run     # pack + model, no writes, no push

WHAT THIS REPLACES
------------------
Three measured OpenHands sessions took 193, 212 and 387 model turns to fix one
issue each, at $1.49, $1.60 and $3.12. Almost none of those turns needed a
language model: they were clone, install, grep, sed, unzip, poll, rebase, push.
Here all of that is code, and the model is called between one and four times —
once to diagnose and patch, and after that only when something it wrote
actually failed.

THE SHAPE OF THE LOOP
---------------------
    pack (free)  ->  ask  ->  expand? serve another slice, ask again
                          ->  edits?  test-first gate, analyze, full suite
                                      pass -> commit, push, close
                                      fail -> tell it exactly what broke, ask again
    out of rounds -> label openhands-blocked, post the diff, push nothing

Escalation feeds back ONLY the failure, clipped to 4,000 characters, on top of
a conversation whose prefix is already cached. A repair round therefore costs
about $0.015 rather than the $1.49 that re-deriving everything used to.

WHY IT NEVER OPENS A PULL REQUEST
---------------------------------
Because bugreports/MAINTAINER_PROTOCOL.md says not to, and that rule predates
this pipeline. One commit per issue, straight to main, rebased immediately
before the push so sibling runs cannot clobber each other.
"""
import argparse
import os
import pathlib
import re
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))

import edits as edits_mod
import gh
import model
import pack
import rank
import verify

ROOT = pathlib.Path(__file__).resolve().parents[2]

# One diagnose call plus at most three repairs. Past that the failures in the
# measured sessions stopped converging and a human is cheaper than a fourth
# guess; the protocol's blocked path exists for exactly this.
MAX_ROUNDS = 4

# How many rounds may be spent looking rather than fixing.
#
# Issue #9's third run spent ALL FOUR asking to see `occt_engine.dart`, hunting
# for an STL exporter that does not exist in this repo. Serving the same file
# again cannot answer that question, and the run ended having written nothing.
# After this budget the model is told it has everything it is going to get.
MAX_EXPAND_ROUNDS = 2

FOOTER = '\n\n---\n_Fixed automatically. Pipeline: `ci/bugfix/`._'


def sh(*args, check=True, cwd=ROOT):
    p = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    if check and p.returncode != 0:
        raise SystemExit(f'{" ".join(args)}\n{p.stdout}\n{p.stderr}')
    return p.stdout.strip()


def git_reset():
    sh('git', 'checkout', '--', '.')
    sh('git', 'clean', '-fd', '--', 'frontend')


def parse_tagged(text, tag):
    m = re.search(rf'<{tag}>(.*?)</{tag}>', text, re.DOTALL)
    return m.group(1).strip() if m else ''


def slices_for(index, paths, query, radius=30, max_lines=160):
    out = []
    for path in paths[:3]:
        chunks = index.slice_file(path, query, radius=radius, max_lines=max_lines)
        if not chunks:
            out.append(f'### {path}\n_(no such file, or nothing matched)_')
            continue
        out.append(pack.render_slices(path, index.header_lines(path) + chunks))
    return '\n\n'.join(out)


# `lib/widgets/home_view.dart:494:30: Error: ...` — Dart names the file
# frontend-relative, the rest of the pipeline names it from the repo root.
ERROR_LOC_RE = re.compile(r'((?:lib|test)/[\w./-]+\.dart):(\d+):\d*')


def error_locations(log, limit=3):
    """-> [(repo_relative_path, line)] the compiler actually pointed at.

    Issue #9's sixth run wrote a call to `partExportStl` and a test calling
    `choosePartExportFormat`, and defined neither. The compiler said exactly
    where, in both files. Serving those neighbourhoods back is a far better
    repair prompt than the error text alone, because what the model needs is
    the surrounding code it has to add the definition INTO.
    """
    seen = []
    for m in ERROR_LOC_RE.finditer(log or ''):
        item = (f'frontend/{m.group(1)}', int(m.group(2)))
        if item[0] not in [p for p, _ in seen]:
            seen.append(item)
        if len(seen) >= limit:
            break
    return seen


def failed_paths(errors):
    """The files an apply failure names, in order, without duplicates.

    Every message `edits.apply` produces starts `'<path>: …'`.
    """
    seen = []
    for e in errors:
        path = e.split(':', 1)[0].strip()
        if '/' in path and path not in seen:
            seen.append(path)
    return seen


def serve_expands(index, expands, query, already):
    """Answer an `expand` request with more source, still for free.

    `already` is the set of paths served in earlier rounds. Re-serving one
    cannot tell the model anything it does not have, and on issue #9 that loop
    consumed every round — so a repeat is answered with the fact itself: what
    you were looking for is not in there.
    """
    fresh = [e for e in expands[:3] if e.path not in already]
    repeats = [e.path for e in expands[:3] if e.path in already]
    parts = []
    if fresh:
        parts.append('\n\n'.join(
            slices_for(index, [e.path], f'{query} {e.query}') for e in fresh))
        already.update(e.path for e in fresh)
    if repeats:
        parts.append(
            'You have already been shown ' + ', '.join(repeats) + '. What you '
            'were looking for is not in there — treat that as the answer: it '
            'does not exist yet, so build it.')
    return ('You asked to see more.\n\n' + '\n\n'.join(parts)
            + '\n\nNow answer with the fix.')


def repair_prompt(index, reason, log, query, paths):
    """The escalation message, with the source the model was missing.

    Issue #9 is why this carries code rather than only the error. The retriever
    had put `home_view.dart` 20th, so it was not in the pack — but the model
    worked out unaided that the fix belonged there and wrote a SEARCH block for
    a function it had never seen. That cannot match byte for byte, so it failed;
    and because the repair prompt said only "SEARCH text not found", it guessed
    again, four times, for $0.097 and no fix.

    A failed edit names its file. Serving that file's slices costs about
    $0.004 and turns a guess into a read.
    """
    body = (f'That did not work: {reason}\n\n```\n{log}\n```\n\n')
    if paths:
        body += ('Here is the file you tried to edit, as it actually reads. '
                 'Copy the SEARCH text from this, byte for byte.\n\n'
                 + slices_for(index, paths, query) + '\n\n')

    located = error_locations(log)
    if located:
        parts = []
        for path, line in located:
            chunks = index.slice_around(path, line)
            if chunks:
                parts.append(pack.render_slices(path, chunks))
        if parts:
            body += (
                'And here is the code around each place the compiler pointed '
                'at. If it says a method is not defined, DEFINE IT — a call '
                'site without its implementation is not a fix.\n\n'
                + '\n\n'.join(parts) + '\n\n')
    return body + 'Now answer again in the required format.'


class RebaseConflict(Exception):
    """`main` moved under us in a way that cannot be resolved mechanically.

    The protocol's answer to this predates the pipeline and has not changed:
    leave `main` alone, say so on the issue, do not force anything.
    """


def ship(number, subject, root_cause, paths, dry_run):
    """Commit, rebase, push, log. Only reachable from a green tree."""
    summary = (root_cause or '').strip() or 'See the issue for the report.'
    message = f'{subject}\n\n{summary}\n\nFiles: {", ".join(paths)}'
    if dry_run:
        print(f'[dry-run] would commit: {subject}')
        return None

    sh('git', 'config', 'user.name', 'ipadprocad-bugfix')
    sh('git', 'config', 'user.email', 'bugfix@users.noreply.github.com')
    sh('git', 'add', '--', *paths)
    sh('git', 'commit', '-m', message)

    # One commit per issue, and the notes entry separately, so each is
    # revertable on its own — the protocol's rule, unchanged.
    notes = ROOT / 'bugreports' / 'AUTOMATION_NOTES.md'
    sha = sh('git', 'rev-parse', '--short', 'HEAD')
    with notes.open('a', encoding='utf-8') as fh:
        fh.write(f'\n- #{number} — {summary.splitlines()[0]} Commit `{sha}`.\n')
    sh('git', 'add', '--', 'bugreports/AUTOMATION_NOTES.md')
    sh('git', 'commit', '-m',
       f'Update AUTOMATION_NOTES.md: log bug-report issue #{number}')

    sh('git', 'fetch', 'origin', 'main')
    rebase = subprocess.run(['git', 'rebase', 'origin/main'], cwd=ROOT,
                            capture_output=True, text=True)
    if rebase.returncode != 0:
        subprocess.run(['git', 'rebase', '--abort'], cwd=ROOT,
                       capture_output=True)
        raise RebaseConflict(rebase.stdout + rebase.stderr)
    sh('git', 'push', 'origin', 'HEAD:main')
    return sh('git', 'rev-parse', '--short', 'HEAD~1')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--issue', type=int, required=True)
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--max-rounds', type=int, default=MAX_ROUNDS)
    args = ap.parse_args()

    number = args.issue
    gh.ensure_labels()
    data = gh.issue(number)
    title, body = data['title'], data.get('body') or ''

    if not args.dry_run:
        if not gh.claim(number):
            print(f'#{number} was already claimed by another run — nothing to do')
            return 0

    index = rank.Index()
    prefix, issue_body, ranked = pack.build(number, title, body, index=index)
    print(f'pack: ~{(len(prefix) + len(issue_body)) // 4} tokens, files={ranked}')

    history, spent = [], 0.0
    expanded, expand_rounds = set(ranked), 0
    # Why the last round ended. Seeded rather than left empty: issue #9's
    # re-run blocked with a BLANK "Last failure" because every early `continue`
    # below skipped the assignment, and the comment is the whole handoff to a
    # human. `note()` is now the only way a round ends.
    last_reason = 'no round completed'
    last_log = ''

    def note(round_no, reason, log=''):
        nonlocal last_reason, last_log
        last_reason, last_log = reason, log
        print(f'  round {round_no}: {reason}')

    # Expand rounds are bounded separately (MAX_EXPAND_ROUNDS) and no longer
    # consume the fix budget. On issue #9's ninth run, rounds 1 and 3 were both
    # expands, leaving only two actual attempts out of four — the model was
    # being cut off for having asked to look, which is behaviour the pipeline
    # explicitly invites.
    round_no = 0
    fix_rounds = 0
    while fix_rounds < args.max_rounds:
        round_no += 1
        if round_no > args.max_rounds + MAX_EXPAND_ROUNDS:
            break
        reply, usage, truncated = model.ask(prefix, issue_body, history)
        spent += model.cost(usage)
        thinking = model.reasoning_tokens(usage)
        print(f'round {round_no}: {usage.get("completion_tokens", 0)} out'
              f'{f" ({thinking} thinking)" if thinking else ""}'
              f'{" TRUNCATED" if truncated else ""}, ${spent:.4f} so far')

        parsed, expands, errors = edits_mod.parse(reply)
        # Anything that is not a served expand is an attempt at the fix, and
        # spends the fix budget. The expand branch below is the one exception.
        if not (expands and not parsed):
            fix_rounds += 1
        if not parsed and not expands:
            # The reply is the only evidence of WHY a format failure happened,
            # and until now it was never recorded — three rounds of issue #9
            # were diagnosed by guessing at what the model might have emitted.
            # It is source code and an explanation, never a credential.
            head = reply[:1200].replace('\n', '\n    | ')
            print(f'  round {round_no}: reply began:\n    | {head}')
        history += [{'role': 'user', 'content': issue_body},
                    {'role': 'assistant', 'content': reply}]

        if truncated and not parsed:
            if not reply.strip():
                # Nothing was written at all: the entire budget went on
                # reasoning. Asking for a "smaller edit" is the wrong
                # instruction — there was no edit.
                note(round_no,
                     f'spent the whole output budget thinking ({thinking} '
                     'tokens) without writing an answer')
                issue_body = (
                    'You used your entire output budget reasoning and emitted '
                    'nothing. Do not deliberate further — you have already '
                    'worked this out. Write the `<file>` blocks NOW, starting '
                    'with the single most important one. A partial fix that '
                    'applies beats a complete one that never gets written.')
                continue
            note(round_no, 'the answer was cut off at the output limit')
            issue_body = (
                'Your answer was cut off at the output limit, so nothing could '
                'be applied. Send a SMALLER edit: SEARCH/REPLACE blocks around '
                'just the lines that change, never a whole rewritten file. If '
                'the change genuinely needs to be large, do the smallest part '
                'that stands alone and say what remains.')
            continue

        if expands and not parsed:
            expand_rounds += 1
            note(round_no,
                 'asked to see more source: '
                 + ', '.join(e.path for e in expands[:3]))
            if expand_rounds > MAX_EXPAND_ROUNDS:
                fix_rounds += 1  # refusing to look again is itself an attempt
                issue_body = (
                    'No. You have had your two rounds of looking, and asking '
                    'again spends the budget without writing anything. If what '
                    'you were shown does not contain the capability you need, '
                    'that IS the finding: it does not exist yet, and building '
                    'it is the job. Answer now with the fix, or say precisely '
                    'which unavailable thing (C++ kernel rebuild, Xcode, a '
                    'physical device) blocks it and what you would have done.')
                continue
            issue_body = serve_expands(index, expands, f'{title} {body}',
                                       expanded)
            continue

        if errors or not parsed:
            note(round_no, 'the answer could not be applied',
                 '\n'.join(errors or ['no <file> blocks found']))
            issue_body = repair_prompt(
                index, 'your answer could not be applied',
                '\n'.join(errors or ['no <file> blocks found']),
                f'{title} {body}', failed_paths(errors))
            continue

        tests = [e for e in parsed if edits_mod.is_test(e.path)]
        code = [e for e in parsed if not edits_mod.is_test(e.path)]
        test_paths = [p for p in edits_mod.touched(tests)]

        if not tests:
            note(round_no, 'code was changed but no test was added')
            issue_body = ('You changed code but added no test under '
                          '`frontend/test/`. A fix with no test is not '
                          'finished. Answer again, with the test.')
            git_reset()
            continue

        applied = {}

        def apply_code():
            errs = edits_mod.apply(code, ROOT)
            applied['c'] = errs
            if errs:
                return errs
            # An ARB edit is only half a change until gen-l10n has run; see
            # verify.regenerate_l10n.
            if verify.touches_arb(edits_mod.touched(code)):
                ok_gen, out = verify.regenerate_l10n()
                if not ok_gen:
                    return [f'gen-l10n failed after your ARB edit:\n{out}']
            return []

        ok, reason, log = verify.gate(
            lambda: applied.setdefault('t', edits_mod.apply(tests, ROOT)),
            apply_code,
            git_reset,
            test_paths)

        if ok:
            ok, reason, log = verify.full_verification()

        if ok:
            paths = edits_mod.touched(parsed)
            # The regenerated localisation belongs in the same commit as the
            # ARB change that caused it, or the next checkout is inconsistent.
            if verify.touches_arb(paths):
                paths.append(verify.L10N_GEN)
            cause = parse_tagged(reply, 'root-cause')
            try:
                sha = ship(number, parse_tagged(reply, 'subject') or
                           f'Bugfix #{number}: automated fix',
                           cause, paths, args.dry_run)
            except RebaseConflict as e:
                git_reset()
                print(f'rebase conflict — main untouched, ${spent:.4f}')
                if not args.dry_run:
                    gh.block(number, (
                        '`main` moved while this fix was being verified and the '
                        'rebase does not resolve mechanically, so nothing was '
                        f'pushed.\n\n```\n{str(e)[:1500]}\n```\n\nRe-running '
                        'the workflow on this issue will start from the new '
                        f'`main`.{FOOTER}'))
                return 1
            print(f'shipped {sha} — ${spent:.4f}')
            if not args.dry_run:
                gh.close(number, f'{cause}\n\nFixed in `{sha}` — '
                                 f'{", ".join(paths)}.{FOOTER}')
            return 0

        note(round_no, reason, log)
        git_reset()
        missing = failed_paths(
            [e for v in applied.values() for e in (v or [])]
            + ([log] if 'did not apply' in reason else []))
        issue_body = repair_prompt(index, reason, log, f'{title} {body}', missing)

    git_reset()
    print(f'blocked after {args.max_rounds} rounds — ${spent:.4f}')
    if not args.dry_run:
        gh.block(number, (
            f'Automated fixing stopped after {args.max_rounds} attempts and '
            f'pushed nothing.\n\n**Last failure:** {last_reason}\n\n'
            f'```\n{last_log[:2500]}\n```\n\n'
            f'Files the retriever ranked highest: {", ".join(ranked)}.'
            f'{FOOTER}'))
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
