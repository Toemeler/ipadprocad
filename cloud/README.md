# Cloud mirror — Cloudflare Worker + Backblaze B2

`frontend/lib/sync/lan_sync.dart` mirrors documents between devices that can
see each other on a network. Its own header is blunt about the limit:

> It is NOT a cloud. There is no server, no account and nothing leaves the
> local network.

M423 softened that with a typed-in address over an overlay network (Tailscale,
a VPN), which works and still needs **both devices switched on at once**. The
iPad edited on a train and the desktop opened that evening never overlap, so
they never sync.

This is the other half: a bucket one device leaves files in and another picks
them up from whenever it next runs. It is a **transport**, not a second sync
design — every decision about what wins, what forks and what a delete means is
still `LanSync.verdictFor` on the device. See `frontend/lib/sync/cloud_sync.dart`.

## Why the credential lives in a Worker

Identical to `relay/README.md`'s argument, and the reason this directory is a
Worker rather than the app talking to B2 directly: M195 tried shipping a token
inside the IPA and it was rightly rejected, because a plaintext credential on a
tablet is a plaintext credential in the wild the moment somebody extracts the
app bundle.

The B2 application key is a Worker secret. The app never sees it. What the app
gets instead is a **presigned URL**, good for fifteen minutes, for one object —
so document bytes travel device-to-B2 directly and never pass through the
Worker. That matters twice: the Workers free plan allows 10 ms of CPU per
request, and a `.ptp` is megabytes.

## What it costs

Nothing, at one person's volume, on both free tiers:

| | Free allowance | What a cycle spends |
|---|---|---|
| B2 storage | 10 GB | your gallery, deduplicated |
| B2 Class A (uploads) | free | one PUT per changed document |
| B2 Class B (downloads) | 2,500/day | one LIST + one GET per device per cycle |
| B2 egress | 3× stored/month | 30 GB/month at 10 GB stored |
| Workers requests | 100,000/day | three per cycle |

`CloudSync._cycleEvery` is **two minutes**, and the number is picked against
that Class B line: three devices at two minutes spend about 2,160 transactions
a day and stay inside the free 2,500, where the same three at thirty seconds
would spend 8,640 and start costing money. Pennies — but pennies nobody agreed
to.

## Setting it up

### 1. Backblaze (browser)

1. Sign up for **B2 Cloud Storage** and enable B2 in account settings. Turn on
   2FA; B2 gates application-key creation behind it.
2. **Create a bucket**, set **Private**. Not public, or your documents are
   readable by URL.
3. Note the bucket's **Endpoint**, e.g. `s3.eu-central-003.backblazeb2.com`.
   The middle segment (`eu-central-003`) is the region.
4. **Add an Application Key** scoped to *that one bucket*, read+write, nothing
   else. The secret half is shown **once**.
5. **Set a lifecycle rule: "Keep only the last version."** B2 versions every
   upload by default, and a blob here is written with the same bytes every
   time, so old versions are pure waste.

> **That rule is not what keeps the bucket small.** It collects older versions
> of *one key*, and blobs here are content-addressed: editing a document
> writes a **different** key and leaves the old one orphaned rather than
> superseded, where no lifecycle rule ever sees it. An age-based rule would be
> worse than useless — it would delete the blob of a document that simply has
> not changed in a while, which is most of a gallery.
>
> Orphans are collected by `POST /v1/gc` instead. See **Collecting orphans**.

### 2. The Worker

```sh
cd cloud
npm test                      # 40 tests, no network, no install needed
npx wrangler deploy
npx wrangler secret put B2_KEY_ID
npx wrangler secret put B2_APP_KEY
npx wrangler secret put GROUP_SALT      # any long random string
npx wrangler secret put CLOUD_SECRET    # optional abuse throttle
```

Edit `B2_BUCKET` and `B2_REGION` in `wrangler.toml` first — they are plain
vars, not secrets. `wrangler deploy` prints the Worker's URL.

### 3. The app

```sh
flutter build ios \
  --dart-define=CLOUD_SYNC_URL=https://ipadprocad-cloud-sync.<you>.workers.dev \
  --dart-define=CLOUD_SYNC_SECRET=<the same value you gave CLOUD_SECRET>
```

Leaving `CLOUD_SYNC_URL` unset — the default in every existing build config —
disables the cloud outright: no timer, no request, and the app behaves exactly
as it did before this directory existed. There is a test that says so.

Then type the **same share code** on each device, in Settings, exactly as for
the LAN mirror. One code drives both: `ShareCodes.set` starts each.

## How the bucket is laid out

```
g/<group>/m/<deviceId>.json   one manifest per device
g/<group>/b/<sha256>          document bytes, keyed BY CONTENT
```

**Content-addressed**, which falls out of the mirror rather than being imposed
on it: `SyncEntry` already carries a sha256 of every file and `verdictFor`
already decides everything by comparing shas. A blob named after its own hash
is idempotent to upload, free to rename, and shared between two documents that
contain the same imported STEP file. It also means **no document name ever
reaches the bucket** — the manifest holds the path-to-sha map, and B2 sees hex.

**One manifest per device**, rather than one shared file the group edits:

- It is what the LAN mirror already does — each peer sends its own manifest and
  `verdictFor` compares. Per-device files are the faithful port.
- A shared file would need a compare-and-swap to be safe against two devices
  saving at once, and **B2 does not document `If-Match` on PutObject**. A file
  only ever written by one device needs no such thing.

The one invariant `cloud_sync.dart` owns: **a manifest only ever names blobs
that are already uploaded.** Publish first and a peer asks for bytes that are
not there; upload first and the worst case is a blob nobody references yet.
One of those is a data-loss report, the other is litter.

## Collecting orphans

Editing a document leaves its previous blob referenced by nothing. Nothing
collects those automatically — deletion is the one operation here that can
destroy work, so it does not also run unattended every two minutes.

Ask for a report first. `dryRun` is the default, so forgetting the flag is
safe:

```sh
curl -X POST https://<your-worker>/v1/gc \
  -H 'x-cloud-group: <the 16-hex fingerprint>' \
  -H 'x-cloud-secret: <CLOUD_SECRET>' \
  -d '{}'
# -> {"ok":true,"dryRun":true,"blobs":412,"wouldDelete":97,"keys":[...]}
```

Then, when the numbers look right:

```sh
curl -X POST https://<your-worker>/v1/gc \
  -H 'x-cloud-group: <fingerprint>' -H 'x-cloud-secret: <CLOUD_SECRET>' \
  -d '{"dryRun": false}'
```

Two guards, both tested:

- **Referenced by any manifest is safe** — not "any recent one", any. A device
  that never publishes again pins its blobs for ever, which is the
  conservative direction.
- **Anything younger than a day is safe.** A blob is uploaded *before* the
  manifest that names it, so in between it is referenced by nothing and looks
  exactly like garbage. A cycle takes seconds; the guard is 24 hours.

It also refuses to run at all if any manifest cannot be read, rather than
collecting against a partial set — that is the one mistake here that would
delete live data.

Deletes are Class A on B2, which is free.

## What never leaves the device

**Bug reports do not go to B2.** They are written to `<docs>/bugreports/*.zip`
— inside the very directory the mirror watches — and they hold a screenshot of
the whole window, log tails, and enough of the model to rebuild the sketch.
They have their own destination and their own consent: the report dialog and
the relay in `relay/`.

Three independent barriers keep them out, each pinned by a test in
`m441_cloud_sync_test.dart`:

1. `_scanLocal` lists the documents root **non-recursively** and skips
   anything that is not a file, so `bugreports/` is never descended into.
2. Only `.ptp`, `.pts` and `.pas` are documents. A `.zip` is not, even at the
   top level.
3. `bytesFor` — the only way bytes reach the cloud — goes through `_fileFor`,
   which refuses any document path containing a separator.

The same three keep **logs** out. And the reverse direction is closed too: a
manifest naming `bugreports/evil.zip` cannot write one into the gallery.

The whole mirror carries exactly this: `*.ptp`, `*.pts`, `*.pas`, plus
`settings.json` and a gallery backdrop under `settings/`. Nothing else.

## What is not encrypted yet

**The bytes sit on Backblaze's disks in the clear.** The bucket is private and
TLS covers the wire, so this is on the same footing as keeping documents in
Dropbox or Drive — a company can read them. That is a real step down from the
LAN mirror, where nothing left the house, and it is stated here rather than
implied away.

Closing it means encrypting in `CloudSync._upload` and decrypting in
`_download` — two places — plus a cipher, which this app does not have: the
`crypto` package hashes, it does not encrypt. That is a `pubspec.yaml`
dependency (`cryptography` or `pointycastle`) and a key derived from the share
code the way `shareCodeKey` already derives the handshake key. It was left out
rather than half-done.

**And the share code is still 60 bits.** `share_code.dart` is explicit:

> Twelve of a 32-symbol alphabet is 60 bits. That is not a password and is not
> treated as one — it is a rendezvous token whose exposure is bounded by being
> on one local network.

This removes that bound. Two things narrow it: the bucket prefix is an HMAC
under `GROUP_SALT`, so a code cannot be turned into a bucket path off-device,
and `CLOUD_SECRET` keeps casual traffic off the endpoint. Neither turns the
code into a password. **Anyone who learns your code can read your gallery.**

## Tests

```sh
cd cloud && npm test                                         # 40
cd frontend && flutter test test/m441_cloud_sync_test.dart   # 28
```

The Worker's signer is checked against **AWS's own published presigning
example** — a known input with a known signature. That is the only useful test
for a signer: every mistake in one produces a string that looks exactly as
plausible as the right one and is rejected by the server as
`SignatureDoesNotMatch` with nothing else to go on. B2 implements the same
SigV4, which is why an S3 signer reaches it at all.
