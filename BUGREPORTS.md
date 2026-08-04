# Bug reports that send themselves (M195)

Pressing the red bug button at the foot of the quick-tool bar writes a bundle
(screenshot, full log, gesture trace, part/sketch state) into

    Files > On My iPad > prototype > bugreports

That has always worked. What M195 adds: the app **uploads each bundle to a
GitHub repository by itself**, so the reports can simply be read from there —
by you, or by an assistant you point at the repo — instead of being carried out
of the Files app by hand.

Nothing is configured in this repository. **No config file on the device = no
uploading**, and the app behaves exactly as before. That is the default for
anyone who clones this.

---

## Choose the destination FIRST

`Toemeler/ipadprocad` is **public**. A bundle pushed there is world-readable,
and a bundle contains your full session log, the model you had open and a
screenshot of your screen.

**Recommended: a separate private repository** that holds nothing but bug
reports — e.g. `Toemeler/ipadprocad-bugs`. Then:

* the bundles are not public,
* the token below can be scoped to *that* repo alone, so if the iPad is lost
  the token cannot touch your source,
* it is still a repository, so it can be fetched and read the same way.

If you would rather keep everything in one place, point the config at
`Toemeler/ipadprocad` with `"branch": "bugreports"` — just do it knowing the
bundles are then public.

## 1. Make a token

GitHub → Settings → Developer settings → **Fine-grained personal access
tokens** → Generate new token.

| Field | Value |
|---|---|
| Repository access | **Only select repositories** → the one repo you chose |
| Permissions | **Contents: Read and write** — nothing else |
| Expiration | Set one. 90 days is plenty; renewing is one file edit |

Anything wider than this is a bigger loss than it needs to be if the iPad goes
missing.

## 2. Put the config on the iPad

Files → On My iPad → prototype → new file **`bugupload.json`** (next to the
`bugreports` folder, not inside it):

```json
{
  "repo": "Toemeler/ipadprocad-bugs",
  "token": "github_pat_..."
}
```

Optional keys:

| Key | Default | Meaning |
|---|---|---|
| `branch` | the repo's default branch | Push bundles to this branch instead |
| `dir` | `bugreports` | Folder inside the repository |

A malformed file is treated as "no config": reports are still written, they are
just not uploaded. That is deliberate — a typo here must never cost you a bug
report.

## 3. That is all

* Press the bug button. The dialog now says **"Report sent"** when the upload
  landed, and **"Report saved"** when it did not.
* No network? The bundle is **queued**: it goes out with the next report, or at
  the next app launch. Nothing is lost and nothing needs remembering.
* Uploaded bundles are **kept on the iPad too** (a `.sent` marker appears
  beside them), because the local copy is the only one you can open on the
  device.

## Reading them back

```bash
git clone https://github.com/<owner>/<the-bug-repo>.git
# or, if you pointed it at a branch of this repo:
git fetch origin bugreports && git checkout bugreports
ls bugreports/
```

Each `bugNNNNNNNNTNNNNNN.zip` is self-contained: unzip it and `report.txt`
explains itself. No explanation has to travel with it — that was the point of
the bundle format in the first place.

## Notes

* **The token is never logged.** `BugUploadConfig.toString()` redacts it, which
  matters more than it looks: the bundle carries the whole log, so a stray
  interpolation would ship the credential inside the very zip being uploaded.
  There is a test pinning that.
* **Bundles over 25 MB are not uploaded** (they stay local and the dialog says
  so). A bundle that big means something went wrong building it, and a tablet
  on cellular should not find that out the slow way.
* **A rejected token stops the queue for that run** rather than retrying every
  bundle — twenty 401s in a row is how you trip a rate limit.
* To turn the whole affordance off, including the button:
  `BugReport.enabled = false` in `lib/widgets/bug_button.dart`.
