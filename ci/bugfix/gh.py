#!/usr/bin/env python3
"""The GitHub calls the bug-fix pipeline makes, and nothing else.

WHY THIS EXISTS RATHER THAN `gh` OR A LIBRARY
---------------------------------------------
The old sessions spent 12-19 turns per issue on GitHub plumbing, and a further
15-32 discovering what the token was called — the injected skill said
`GITHUB_TOKEN`, the sandbox actually set `github_token`, and the agent
rediscovered that the hard way three separate times in one session. Inside a
workflow the token is `GITHUB_TOKEN` by construction and there is nothing to
discover, so the whole category disappears; this file just needs to not
reintroduce it. Six endpoints, urllib, no dependency to install.

CLAIMING IS A COMPARE-AND-SWAP, NOT A CONVENTION
------------------------------------------------
`claim()` removes `bug-report` and adds `openhands-working` and reports whether
IT was the one that removed the label. Two runs racing on near-simultaneous
reports therefore cannot both proceed: the loser sees `claimed=False` and
stops. The old protocol achieved this by asking a session to stay alive for
several minutes re-listing issues, which cost real money to do nothing.
"""
import json
import os
import time
import urllib.error
import urllib.request

API = 'https://api.github.com'

# GITHUB_TOKEN is what Actions injects. The lowercase spelling is what the
# OpenHands sandbox used, and is accepted here so the same scripts can be run
# by hand from that sandbox without the discovery dance that used to cost 32
# turns.
TOKEN = (os.environ.get('GITHUB_TOKEN')
         or os.environ.get('github_token')
         or '')

REPO = os.environ.get('GITHUB_REPOSITORY', 'Toemeler/ipadprocad')

WORKING = 'openhands-working'
BLOCKED = 'openhands-blocked'
REPORT = 'bug-report'

# What the relay files a report under when the reporter cleared the "let the
# automation fix it" box. Nothing here ever claims it — `bugfix.yml` runs only
# for REPORT — so the label exists to be VISIBLE: an issue nobody is working on
# should say so rather than look like one that was missed.
MANUAL = 'needs-session'


def _request(method, path, body=None, retries=3):
    url = path if path.startswith('http') else f'{API}{path}'
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header('Authorization', f'Bearer {TOKEN}')
    req.add_header('Accept', 'application/vnd.github+json')
    req.add_header('User-Agent', 'ipadprocad-bugfix')
    if data:
        req.add_header('Content-Type', 'application/json')
    last = None
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            # 404 and 422 are answers, not failures — a missing label or an
            # already-claimed issue is information the caller acts on.
            if e.code in (404, 422):
                raise
            last = e
        except (urllib.error.URLError, TimeoutError) as e:
            last = e
        time.sleep(2 ** attempt)
    raise last


def issue(number):
    return _request('GET', f'/repos/{REPO}/issues/{number}')


def open_bug_reports():
    got = _request('GET', f'/repos/{REPO}/issues?state=open&labels={REPORT}&per_page=50')
    return [i for i in got if 'pull_request' not in i]


def ensure_labels():
    """Idempotent, and cheap enough to just always run."""
    for name, color, desc in (
            (WORKING, 'ededed', 'an automated run is working on this issue'),
            (BLOCKED, 'b60205', 'automation could not safely fix this; needs a human'),
            (MANUAL, '5319e7',
             'reported with automatic fixing off; waiting for a session')):
        try:
            _request('GET', f'/repos/{REPO}/labels/{name}')
        except urllib.error.HTTPError:
            try:
                _request('POST', f'/repos/{REPO}/labels',
                         {'name': name, 'color': color, 'description': desc})
            except urllib.error.HTTPError:
                pass


def claim(number, force=False):
    """-> True if this run took the issue, False if someone else already had it.

    DELETE on the label is the atomic part: GitHub 404s the second caller.

    `force` IS FOR THE RE-RUN THAT THE README PROMISES AND THIS BROKE.
    `workflow_dispatch` exists to re-run a BLOCKED issue after a fix to the
    pipeline — but a blocked issue has no `bug-report` label, because the run
    that blocked it took the label on the way in. So every manual re-run
    404'd on the DELETE, reported "already claimed by another run", and
    exited 0 in two seconds. Issue #11 was re-run that way and did nothing;
    the workflow went green saying so.

    Under `force` the missing label is not evidence of anything, so the live-
    run signal is consulted instead: `openhands-working` is on the issue for
    exactly as long as a run holds it. Two dispatches racing still cannot both
    proceed, and neither can a dispatch racing the relay.
    """
    try:
        _request('DELETE', f'/repos/{REPO}/issues/{number}/labels/{REPORT}')
    except urllib.error.HTTPError as e:
        if e.code != 404:
            raise
        if not force:
            return False
        if WORKING in {l['name'] for l in issue(number).get('labels', [])}:
            return False
    _request('POST', f'/repos/{REPO}/issues/{number}/labels', {'labels': [WORKING]})
    # Whatever blocked it last time, a run now holds it. Leaving the label on
    # would have the issue reading as blocked and in progress at once.
    try:
        _request('DELETE', f'/repos/{REPO}/issues/{number}/labels/{BLOCKED}')
    except urllib.error.HTTPError as e:
        if e.code != 404:
            raise
    return True


def comment(number, body):
    _request('POST', f'/repos/{REPO}/issues/{number}/comments', {'body': body})


def close(number, body=None):
    if body:
        comment(number, body)
    _request('PATCH', f'/repos/{REPO}/issues/{number}',
             {'state': 'closed', 'state_reason': 'completed'})
    try:
        _request('DELETE', f'/repos/{REPO}/issues/{number}/labels/{WORKING}')
    except urllib.error.HTTPError:
        pass


def hand_off(number, body):
    """Give the issue to a person, because the evidence could not decide it.

    Distinct from `block`, which means the run tried and failed. This means the
    run declined on purpose: two or more different faults would produce the
    reported symptom and nothing in the bundle separates them. Shipping a guess
    there is worse than shipping nothing, because a guess closes the issue and
    leaves the fault in place — which is exactly what happened three times on
    #12 before anyone noticed the log held no record of the action at all.

    `needs-session` is the same label the report form's autofix checkbox puts
    on, so both roads to "a human should take this" end in one queue.
    """
    comment(number, body)
    for label in (WORKING, BLOCKED):
        try:
            _request('DELETE', f'/repos/{REPO}/issues/{number}/labels/{label}')
        except urllib.error.HTTPError:
            pass
    _request('POST', f'/repos/{REPO}/issues/{number}/labels', {'labels': [MANUAL]})


def block(number, body):
    """Hand the issue back to a human, with what was found."""
    comment(number, body)
    try:
        _request('DELETE', f'/repos/{REPO}/issues/{number}/labels/{WORKING}')
    except urllib.error.HTTPError:
        pass
    _request('POST', f'/repos/{REPO}/issues/{number}/labels', {'labels': [BLOCKED]})


def labels(number):
    """The label names currently on an issue."""
    d = issue(number)
    return {l['name'] for l in d.get('labels', []) if isinstance(l, dict)}


def release_if_claimed(number, why):
    """Unstick an issue whose run died where no `except` could see it.

    `run.py` guards its own failures, but a job that is KILLED — the 60-minute
    `timeout-minutes`, a cancelled workflow, an evicted runner — never reaches
    a Python handler. The issue keeps `openhands-working`, which says a run
    holds it while none does; and because `claim` refuses an issue in that
    state, the `workflow_dispatch` re-run that exists for exactly this case
    refuses too, unless someone knows to pass `--force`.

    So this is called from an `if: always()` step. It is a no-op on every
    normal ending, because shipping, blocking and handing off all take
    `openhands-working` off themselves — an issue still wearing it is, by
    construction, one whose run did not finish.

    Returns True when it actually released something.
    """
    if WORKING not in labels(number):
        return False
    block(number, (
        f'The fix run did not finish: {why}\n\nNothing was pushed and `main` '
        'is untouched. The issue is unblocked for a re-run — start the **Bug '
        'report autofix** workflow with this number, or put the `bug-report` '
        'label back on.'))
    return True


if __name__ == '__main__':
    # `python3 ci/bugfix/gh.py release <issue> <why>` — the always() step.
    import sys
    if len(sys.argv) >= 3 and sys.argv[1] == 'release':
        n = int(sys.argv[2])
        reason = ' '.join(sys.argv[3:]) or 'the job ended without completing'
        print(f'#{n}: released' if release_if_claimed(n, reason)
              else f'#{n}: was not left claimed — nothing to do')
    else:
        raise SystemExit('usage: gh.py release <issue> [why]')
