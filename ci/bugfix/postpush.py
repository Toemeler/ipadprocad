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

IT CHECKS WHETHER THE BREAK IS EVEN OURS
----------------------------------------
The same job may already have been failing before the fix landed. Reporting a
pre-existing failure as "your fix broke the build" would be worse than saying
nothing: it sends a human to read a diff that is innocent. So the previous run
of the same workflow on `main` is consulted first, and its verdict is carried
into the comment either way.
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


def previously_failing(workflow_id, run_id):
    """Was the same workflow already red on main before this commit?

    A pre-existing failure reported as "your fix broke the build" sends a human
    to read an innocent diff, which is worse than saying nothing.
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
    return earlier[0].get('conclusion') == 'failure'


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
    was_red = previously_failing(workflow_id, RUN_ID) if workflow_id else None

    if was_red:
        verdict = ('The **same workflow was already failing on `main` before '
                   'this commit**, so this is most likely not the fix\'s doing '
                   '— but the fix is now sitting on top of a red build and '
                   'nobody has confirmed which is which.')
    elif was_red is False:
        verdict = ('The previous run of this workflow on `main` **passed**, so '
                   'this commit is the most likely cause.')
    else:
        verdict = 'No earlier run was available to compare against.'

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
