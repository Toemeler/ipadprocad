#!/usr/bin/env python3
"""Did the fix we just pushed break the build it could not run?

WHY THIS EXISTS
---------------
`ci/bugfix/run.py` verifies on a Linux runner: `flutter analyze` and the whole
Dart suite. That is genuinely most of the truth and it is what stops a bad fix
reaching `main` — but it is not all of it. Swift cannot be compiled there at
all. The simulator test and the IPA build run on macOS. Even the fast Dart job
runs without the native OCCT library, so a test that touches the FFI passes in
one place and fails in the other.

A fix could therefore go green through the pipeline, land on `main`, and turn
`Core + C-API Build (iOS)` red minutes later with nobody the wiser: the issue
was already closed and the run that closed it had exited successfully. That is
the gap this closes. A push that breaks the build is a failed fix, whatever the
pipeline thought at the time.

WHAT IT DOES NOT DO
-------------------
It does not re-run the fixer. Handing a red build straight back to the model
that produced it invites a loop that pushes to `main` on each turn, which is
the one thing this whole system is careful never to do. It reopens the issue,
labels it `openhands-blocked`, and says exactly what broke — the protocol's own
answer for "cannot safely fix this automatically", reached from the other side.

IT CHECKS WHETHER THE BREAK IS EVEN OURS, AND STAYS QUIET IF NOT
----------------------------------------------------------------
The same job may already have been failing before the fix landed — and on this
repository that is the common case, not the exception: `Core + C-API Build
(iOS)` has gone red on `main` for commits that touched only `.gitignore`, and
its fast Dart job runs without the native OCCT library so `m207` dies in
`Engine.create` regardless of what was pushed.

So the previous run of the same workflow on `main` is consulted first, and if
it was ALSO failing this exits silently. Reopening on a pre-existing failure
would reopen every issue the pipeline ever closes, and an alert that fires
every time is one everybody learns to ignore — including on the day it is
right.
"""
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

API = 'https://api.github.com'
TOKEN = os.environ.get('GITHUB_TOKEN', '')
REPO = os.environ.get('GITHUB_REPOSITORY', 'Toemeler/ipadprocad')
RUN_ID = os.environ.get('FAILED_RUN_ID', '')
SHA = os.environ.get('FAILED_SHA', '')
RUN_URL = os.environ.get('FAILED_URL', '')

# `Bugfix #9: prompt STL/STEP before choosing export location`
SUBJECT_RE = re.compile(r'^Bugfix #(\d+):', re.MULTILINE)

FOOTER = '\n\n---\n_Posted by `ci/bugfix/postpush.py`._'


def api(path, body=None, method=None):
    url = path if path.startswith('http') else f'{API}{path}'
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data,
                                 method=method or ('POST' if data else 'GET'))
    req.add_header('Authorization', f'Bearer {TOKEN}')
    req.add_header('Accept', 'application/vnd.github+json')
    req.add_header('User-Agent', 'ipadprocad-bugfix-postpush')
    if data:
        req.add_header('Content-Type', 'application/json')
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read()
        return json.loads(raw) if raw else {}


def commit_subject(sha):
    out = subprocess.run(['git', 'log', '-1', '--format=%B', sha],
                         capture_output=True, text=True)
    return out.stdout if out.returncode == 0 else ''


def failing_steps(run_id):
    """-> [(job name, failed step name)] so the comment names the real break."""
    try:
        jobs = api(f'/repos/{REPO}/actions/runs/{run_id}/jobs').get('jobs', [])
    except urllib.error.HTTPError:
        return []
    out = []
    for job in jobs:
        if job.get('conclusion') != 'failure':
            continue
        step = next((s['name'] for s in job.get('steps', [])
                     if s.get('conclusion') == 'failure'), '(unknown step)')
        out.append((job['name'], step))
    return out


def previously_failing(workflow_id, run_id, broke=()):
    """Which of the jobs that failed here were ALREADY failing on main?

    A pre-existing failure reported as "your fix broke the build" sends a human
    to read an innocent diff, which is worse than saying nothing.

    The comparison is PER JOB, and that distinction is the whole value of this
    function. It used to compare the previous run's overall conclusion, which
    made one chronically red job disarm the entire check: `Core + C-API Build
    (iOS)` carries five jobs, and while `l10n_no_hardcoded_test` sat red in the
    Dart job, EVERY push looked like "the workflow was already failing" — so a
    fix that broke the Swift build or the IPA would have been waved through in
    silence, by the guard whose whole job is to catch exactly that.

    Returns `(stale, prev_red)` — the subset of `broke` that was already red,
    and whether the previous run failed overall. The second is the fallback for
    when this run's jobs could not be read at all: without names to compare,
    the old whole-run answer is the only one available, and staying quiet on a
    workflow that was already failing beats sending someone to read an
    innocent diff. Returns None when there is no earlier run to compare with.
    """
    try:
        runs = api(f'/repos/{REPO}/actions/workflows/{workflow_id}/runs'
                   f'?branch=main&per_page=10&status=completed').get(
                       'workflow_runs', [])
    except urllib.error.HTTPError:
        return None
    earlier = [r for r in runs if str(r['id']) != str(run_id)]
    if not earlier:
        return None
    prev_red = earlier[0].get('conclusion') == 'failure'
    try:
        jobs = api(f"/repos/{REPO}/actions/runs/{earlier[0]['id']}/jobs").get(
            'jobs', [])
    except urllib.error.HTTPError:
        return set(broke), prev_red
    # A job that did not run last time — skipped behind a red dependency, or
    # cancelled — says nothing either way, and must not be counted as green:
    # that is how a break gets blamed on an innocent commit.
    known = {j['name']: j.get('conclusion') for j in jobs}
    return ({name for name in broke
             if known.get(name) in ('failure', 'skipped', 'cancelled', None)},
            prev_red)


def main():
    subject = commit_subject(SHA)
    match = SUBJECT_RE.search(subject)
    if not match:
        print(f'{SHA[:8]} is not an automated fix — nothing to do')
        return 0
    issue = int(match.group(1))

    steps = failing_steps(RUN_ID)
    detail = '\n'.join(f'- **{job}** — failed at `{step}`' for job, step in steps)
    workflow_id = ''
    try:
        workflow_id = api(f'/repos/{REPO}/actions/runs/{RUN_ID}')['workflow_id']
    except (urllib.error.HTTPError, KeyError):
        pass
    broke = [job for job, _ in steps]
    earlier = (previously_failing(workflow_id, RUN_ID, broke)
               if workflow_id else None)
    stale, prev_red = earlier if earlier else (None, None)

    if stale is not None and (stale.issuperset(broke) if broke else prev_red):
        # Do not reopen. `Core + C-API Build (iOS)` has been red on main across
        # commits that changed only .gitignore, so a job that was already
        # failing says nothing about this fix — and reopening on it would
        # reopen every issue the pipeline ever closes, which trains everyone to
        # ignore the signal precisely when it is real.
        print(f'#{issue}: {RUN_URL} failed, but every job that failed '
              f'({", ".join(sorted(stale))}) was already red on main before '
              f'{SHA[:8]} — not reopening')
        return 0
    if stale is None:
        verdict = 'No earlier run was available to compare against.'
    elif not broke:
        # Red run, no job names, and the previous run was GREEN — so something
        # this commit did is the difference, even though the API would not say
        # what.
        verdict = ('The previous run of this workflow on `main` passed and '
                   'this one failed; its jobs could not be read, so which one '
                   'broke is unknown.')
    else:
        fresh = sorted(set(broke) - stale)
        verdict = (
            'These jobs passed on the previous run of this workflow on `main` '
            'and fail now, so this commit is the most likely cause: '
            + ', '.join(f'**{j}**' for j in fresh) + '.')
        if stale:
            verdict += (' (Already red beforehand, and not counted against '
                        'this commit: ' + ', '.join(sorted(stale)) + '.)')
        # Steps only from the jobs this commit is actually implicated in.
        detail = '\n'.join(f'- **{job}** — failed at `{step}`'
                            for job, step in steps if job in fresh) or detail

    body = (
        f'The fix for this issue landed as `{SHA[:8]}` and '
        f'[{"the iOS build" if not steps else "a post-push build"}]({RUN_URL}) '
        f'then failed on `main`.\n\n'
        f'{detail or "- (no failing step could be read from the run)"}\n\n'
        f'{verdict}\n\n'
        'The fix pipeline verifies on Linux — `flutter analyze` and the full '
        'Dart suite — and cannot compile Swift, run the simulator test, or '
        'link the native OCCT library. This check exists because that leaves '
        'a gap, and reopening is deliberately where it stops: handing a red '
        'build back to the model that wrote it would put a push-to-`main` loop '
        'in motion.' + FOOTER)

    api(f'/repos/{REPO}/issues/{issue}/comments', {'body': body})
    api(f'/repos/{REPO}/issues/{issue}',
        {'state': 'open', 'state_reason': 'reopened'}, method='PATCH')
    try:
        api(f'/repos/{REPO}/issues/{issue}/labels',
            {'labels': ['openhands-blocked']})
    except urllib.error.HTTPError:
        pass
    print(f'reopened #{issue}: {RUN_URL} failed on {SHA[:8]}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
