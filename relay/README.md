# Bug-report relay

M195 (see the project README/HANDOFF) tried sending bug bundles straight from
the iPad to GitHub and reverted it: there is no anonymous write path into a
GitHub repo, and a repo token baked into the shipped IPA was rightly rejected
— a plaintext credential on a tablet is a plaintext credential in the wild the
moment someone extracts the app bundle.

M285 revisits the goal — a bug report that lands somewhere an AI (or anyone
else) can fetch and act on, without anyone forwarding a `.zip` by hand — by
moving the credential off the device entirely. This directory is a small
Cloudflare Worker that holds the GitHub token. The app never sees it; it only
ever calls this Worker's URL.

## Why the shared secret is not "the same mistake again"

The Worker optionally checks an `x-bug-relay-secret` header against
`SHARED_SECRET`. That value **does** ship inside the IPA (via
`--dart-define=BUG_RELAY_SECRET=...`), so treat it as public — anyone can pull
it out of the binary. That is fine here, and it is *not* the thing M195
rejected, because of what it actually gates:

- A leaked `GITHUB_TOKEN` (the M195 scenario) is full write/issue access to
  the whole repo, usable directly against the GitHub API forever, until
  someone notices and revokes it.
- A leaked `SHARED_SECRET` only lets someone call *this* endpoint, which does
  exactly one thing: commit a file under `bugreports/*.zip` on one dedicated
  branch and open an issue about it. Worst case is issue/commit spam on a
  throwaway branch, cheaply fixed by rotating the secret or deleting it.

So the secret is an abuse throttle, not a security boundary — it exists to
keep casual scraping off the endpoint, not to protect anything of value. Run
without it at all (omit `SHARED_SECRET` on the Worker and `BUG_RELAY_SECRET`
in the app build) if that's simpler; nothing about the security model changes
either way.

## What it does

`POST /report` with `multipart/form-data`:

- `bundle` — the report's `.zip` (required)
- `stem` — the filename stem, e.g. `bug-2026-08-28T091233` (required)
- `description` — what the user typed (may be empty)
- `autofix` — `'1'`/`'0'`, the report dialog's "let the automation fix it"
  checkbox. Absent means `'1'`. `'0'` files the issue under `MANUAL_LABEL`
  (`needs-session`) instead of `ISSUE_LABEL`, which is what keeps `ci/bugfix`
  off it.

> **This field only works on a Worker that has been redeployed since
> 2026‑09‑01.** An older deployment ignores it silently — an unknown multipart
> field is not an error — and files everything under `ISSUE_LABEL`, which is
> exactly how the checkbox came to do nothing at all for its first days alive.
> The app therefore ALSO writes `[autofix: off]` into the `description`, which
> every version of this Worker copies into the issue body untouched, and
> `.github/workflows/bugfix.yml` reads it back and sets the label. Nothing here
> has to be redeployed for the checkbox to work; redeploying simply moves the
> decision one step earlier, and both roads end at the same label. See
> `ci/bugfix/README.md` → "Why the label needs help getting set".

On success it:

1. commits `bugreports/<stem>.zip` to the `bug-reports` branch (created off
   the repo's default branch on first use, so it never touches history CI
   builds from), via the Contents API;
2. opens a GitHub issue linking to that file;
3. returns `{ ok: true, issueUrl, fileUrl }`.

On failure it returns `{ error: "..." }` with a 4xx/5xx status and never
touches or logs `GITHUB_TOKEN`. A failed upload never costs the user their
report — the app always writes the bundle to local storage first, exactly as
it always has; the relay is purely additive.

## Deploying

Requires a Cloudflare account and [`wrangler`](https://developers.cloudflare.com/workers/wrangler/).

```sh
cd relay
npx wrangler deploy
npx wrangler secret put GITHUB_TOKEN
# paste a fine-grained PAT scoped to ONLY this repo:
#   Contents: Read and write
#   Issues:   Read and write
# (optional, recommended)
npx wrangler secret put SHARED_SECRET
```

`wrangler deploy` prints the Worker's URL. Point the app at it:

```sh
flutter build ios \
  --dart-define=BUG_RELAY_URL=https://ipadprocad-bug-relay.<your-subdomain>.workers.dev/report \
  --dart-define=BUG_RELAY_SECRET=<the same value you gave SHARED_SECRET>
```

Leaving `BUG_RELAY_URL` unset (the default in every existing build config)
disables the upload entirely — the app falls back to exactly the M194/M195
behaviour: the bundle is written locally and nothing is sent anywhere.

## Fetching reports

Reports show up as issues on the `bug-report` label in this repo, each
linking to the committed `.zip` under the `bug-reports` branch. Anything with
GitHub read access to the repo — including an AI session with this repo
attached — can list `bug-report`-labelled issues and pull the linked bundle
straight from `bugreports/` on that branch.
