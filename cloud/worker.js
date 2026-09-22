// Prototype cloud mirror (Cloudflare Worker + Backblaze B2).
//
// WHAT THIS IS. `frontend/lib/sync/lan_sync.dart` mirrors documents between
// devices that can see each other on a network. Its own header comment is
// blunt about the limit: "It is NOT a cloud. There is no server, no account
// and nothing leaves the local network." Two devices on different networks —
// the iPad on a phone connection, the PC at home — never pair, and the status
// row says "looking" for ever.
//
// This is the other half: a place the same mirror can leave its files so a
// device that is switched on later picks them up. It is a TRANSPORT, not a
// second sync design. Every decision about what wins, what forks and what a
// delete means is still made by `verdictFor` on the device — see
// `cloud_sync.dart`, which drives this.
//
// WHY THE CREDENTIAL LIVES HERE. Identical to relay/README.md's argument, and
// it is the whole reason this file exists rather than the app talking to B2
// itself: M195 tried shipping a token inside the IPA and it was rightly
// rejected, because a plaintext credential on a tablet is a plaintext
// credential in the wild the moment somebody extracts the app bundle. The B2
// application key is a Worker secret. The app never sees it and only ever
// calls this URL.
//
// WHAT THE APP GETS INSTEAD is a presigned URL, good for fifteen minutes, for
// one object. Document bytes therefore travel device-to-B2 directly and never
// pass through the Worker, which matters twice: the free plan allows 10ms of
// CPU per request and a `.ptp` is megabytes, and a Worker that streamed every
// document would burn the request budget on bytes it has no opinion about.
//
// HOW THINGS ARE LAID OUT IN THE BUCKET
//
//   g/<group>/m/<deviceId>.json   one manifest per device
//   g/<group>/b/<sha256>          document bytes, keyed BY CONTENT
//
// CONTENT-ADDRESSED, which falls out of the mirror rather than being imposed
// on it: `SyncEntry` already carries a sha256 of every file, `verdictFor`
// already decides everything by comparing shas, and a blob named after its
// own hash is then idempotent to upload, free to "rename", and shared for
// nothing between two documents that contain the same sketch. Names never
// reach B2 at all — the manifest holds the path-to-sha mapping, so the bucket
// does not leak what anybody's documents are called.
//
// ONE MANIFEST PER DEVICE, rather than one shared file the group edits. Two
// reasons, and the second is the load-bearing one:
//
//   * It is what the LAN mirror already does. Each peer sends ITS OWN
//     manifest and `verdictFor` compares the two. Per-device files here are
//     the faithful port; a single merged manifest would be a second sync
//     design living in a Worker, which is exactly what this is not.
//   * A shared file needs a compare-and-swap to be safe against two devices
//     saving at once, and B2 does not document `If-Match` on PutObject. A
//     file only ever written by one device needs no such thing.
//
// WHAT THIS DOES NOT DO, stated plainly rather than implied away:
//
//   * IT DOES NOT ENCRYPT. The bucket is private and TLS covers the wire, so
//     this is on the same footing as keeping documents in Dropbox or Drive —
//     Backblaze can read them, you are trusting a company. That is a real
//     step down from the LAN mirror, where the bytes never left the house,
//     and `cloud_sync.dart` carries the seam (`CloudCipher`) for closing it.
//     See cloud/README.md → "What is not encrypted yet".
//   * THE SHARE CODE IS 60 BITS and share_code.dart says so: "not a password
//     and is not treated as one — a rendezvous token whose exposure is
//     bounded by being on one local network". A public endpoint removes that
//     bound, so the group prefix is an HMAC under a Worker-held salt rather
//     than the fingerprint itself, and CLOUD_SECRET throttles the endpoint.
//     Neither makes the code a password. Read cloud/README.md before putting
//     anything on this you would mind losing.

import { presign } from './sigv4.js';

/// A manifest is entries and tombstones for one device. Kilobytes, not
/// megabytes — but a device with a very large gallery should not be able to
/// make the Worker buffer something unbounded.
const MAX_MANIFEST_BYTES = 4 * 1024 * 1024;

/// How long a presigned URL is good for. Long enough for a slow upload of a
/// large document on a phone connection, short enough that one leaking from a
/// log is not a standing grant.
const URL_TTL_SECONDS = 900;

/// The most manifests one pull will read. A group is "my devices", so this is
/// far above any real number; it exists so a bucket that somehow accumulated
/// junk cannot make the Worker exceed its subrequest limit.
const MAX_DEVICES = 24;

export default {
  async fetch(request, env) {
    if (request.method !== 'POST') {
      return json({ error: 'POST only' }, 405);
    }

    const missing = ['B2_KEY_ID', 'B2_APP_KEY', 'B2_BUCKET', 'B2_REGION']
      .filter((k) => !env[k]);
    if (missing.length) {
      return json({ error: `worker is missing: ${missing.join(', ')}` }, 500);
    }

    if (env.CLOUD_SECRET) {
      const got = request.headers.get('x-cloud-secret') ?? '';
      if (!timingSafeEqual(got, env.CLOUD_SECRET)) {
        return json({ error: 'bad secret' }, 401);
      }
    }

    const fingerprint = request.headers.get('x-cloud-group') ?? '';
    if (!/^[a-f0-9]{16}$/.test(fingerprint)) {
      return json({ error: 'bad group' }, 400);
    }
    const group = await groupPrefix(env, fingerprint);

    const path = new URL(request.url).pathname;
    try {
      switch (path) {
        case '/v1/pull':
          return await pull(env, group);
        case '/v1/push':
          return await push(env, group, request);
        case '/v1/blob':
          return await blob(env, group, request);
        case '/v1/gc':
          return await gc(env, group, request);
        default:
          return json({ error: 'not found' }, 404);
      }
    } catch (e) {
      return json({ error: `${e}` }, 500);
    }
  },
};

// ---------------------------------------------------------------------------
// The three operations
// ---------------------------------------------------------------------------

/// Every device's manifest, including the caller's own.
///
/// The caller's own comes back on purpose rather than being filtered here:
/// `cloud_sync.dart` compares it against what it currently holds to work out
/// what it still owes the bucket, which is how an upload interrupted halfway
/// is noticed and finished on the next cycle.
async function pull(env, group) {
  const listing = await b2(env, 'GET', '', {
    'list-type': '2',
    prefix: `g/${group}/m/`,
    'max-keys': String(MAX_DEVICES),
  });
  if (!listing.ok) {
    return json({ error: `b2 list: ${listing.status}` }, 502);
  }
  const keys = parseListKeys(await listing.text());

  const manifests = [];
  for (const key of keys.slice(0, MAX_DEVICES)) {
    const res = await b2(env, 'GET', key);
    // A manifest that vanished between the listing and the read is a device
    // that left, not an error worth failing the whole cycle for.
    if (!res.ok) continue;
    try {
      manifests.push(JSON.parse(await res.text()));
    } catch {
      // Corrupt or half-written. Skipping it costs one device's updates this
      // cycle; failing the pull would cost every device's.
    }
  }
  return json({ ok: true, manifests });
}

/// Replaces the caller's own manifest.
async function push(env, group, request) {
  const device = request.headers.get('x-cloud-device') ?? '';
  if (!/^[A-Za-z0-9_-]{1,32}$/.test(device)) {
    return json({ error: 'bad device id' }, 400);
  }
  const body = await request.text();
  if (body.length > MAX_MANIFEST_BYTES) {
    return json({ error: 'manifest too large' }, 413);
  }
  // Parsed rather than passed through: a manifest that is not JSON would be
  // stored happily and then break every OTHER device's pull, which is a far
  // more confusing failure than a 400 here.
  try {
    JSON.parse(body);
  } catch (e) {
    return json({ error: `manifest is not json: ${e}` }, 400);
  }

  const res = await b2(env, 'PUT', `g/${group}/m/${device}.json`, {}, body);
  if (!res.ok) {
    return json({ error: `b2 put: ${res.status} ${await res.text()}` }, 502);
  }
  return json({ ok: true });
}

/// A presigned URL for one document blob.
async function blob(env, group, request) {
  let req;
  try {
    req = await request.json();
  } catch (e) {
    return json({ error: `bad request: ${e}` }, 400);
  }
  const sha = String(req.sha ?? '');
  if (!/^[a-f0-9]{64}$/.test(sha)) {
    return json({ error: 'bad sha' }, 400);
  }
  const op = String(req.op ?? '');
  const method = op === 'put' ? 'PUT' : op === 'get' ? 'GET' : null;
  if (method === null) {
    return json({ error: 'op must be get or put' }, 400);
  }

  const url = await presign({
    accessKeyId: env.B2_KEY_ID,
    secretAccessKey: env.B2_APP_KEY,
    region: env.B2_REGION,
    endpoint: endpointFor(env),
    bucket: env.B2_BUCKET,
    method,
    key: `g/${group}/b/${sha}`,
    expiresIn: URL_TTL_SECONDS,
  });
  return json({ ok: true, url, expiresIn: URL_TTL_SECONDS });
}

/// Removes blobs no manifest points at any more.
///
/// WHY THIS HAS TO EXIST, and why a B2 lifecycle rule is not it. "Keep only
/// the last version" collects older VERSIONS OF ONE KEY. Blobs here are
/// content-addressed, so editing a document writes a DIFFERENT key and leaves
/// the old one orphaned rather than superseded — a lifecycle rule never sees
/// it. An age rule would be worse than useless: it would delete the blob of a
/// document that simply has not changed in a while, which is most of a
/// gallery.
///
/// NOT ON A TIMER, and not part of a cycle. It is called when somebody asks,
/// because the one operation here that can destroy something should not also
/// be the one that runs unattended every two minutes. `dryRun` is the default
/// for the same reason: the first thing anyone should do with a collector is
/// watch what it would have taken.
async function gc(env, group, request) {
  let req = {};
  try {
    const text = await request.text();
    if (text) req = JSON.parse(text);
  } catch (e) {
    return json({ error: `bad request: ${e}` }, 400);
  }
  // Opt IN to deleting. A caller that forgets the flag gets a report.
  const dryRun = req.dryRun !== false;
  const minAgeMs = Number.isFinite(req.minAgeMs)
    ? Math.max(0, req.minAgeMs)
    : 24 * 60 * 60 * 1000;

  const manifestKeys = await listAll(env, `g/${group}/m/`, parseListKeys);
  const manifests = [];
  for (const key of manifestKeys.slice(0, MAX_DEVICES)) {
    const res = await b2(env, 'GET', key);
    if (!res.ok) {
      // A manifest that cannot be read is a manifest whose references cannot
      // be honoured, and collecting against a partial set would delete live
      // blobs. Stopping is the only safe answer.
      return json({ error: `gc: could not read ${key}` }, 502);
    }
    try {
      manifests.push(JSON.parse(await res.text()));
    } catch (e) {
      return json({ error: `gc: ${key} is not json` }, 502);
    }
  }

  const blobs = await listAll(env, `g/${group}/b/`, parseListEntries);
  const doomed = unreferenced(blobs, manifests, {
    nowMs: Date.now(),
    minAgeMs,
  });

  if (dryRun) {
    return json({
      ok: true,
      dryRun: true,
      blobs: blobs.length,
      wouldDelete: doomed.length,
      keys: doomed.slice(0, 50),
    });
  }

  let deleted = 0;
  for (const key of doomed) {
    const res = await b2(env, 'DELETE', key);
    // 404 means somebody else got there first, which is success.
    if (res.ok || res.status === 404) deleted++;
  }
  return json({ ok: true, blobs: blobs.length, deleted });
}

// ---------------------------------------------------------------------------
// B2
// ---------------------------------------------------------------------------

/// Every page of one prefix, run through `parse`.
///
/// B2 caps a listing at 1,000 objects and says so with `IsTruncated`. A
/// gallery reaches that easily once blobs are per-version, and a collector
/// that read only the first page would judge "referenced by nothing" against
/// a fraction of the bucket — which is the one mistake here that deletes
/// live data.
async function listAll(env, prefix, parse) {
  const out = [];
  let token = null;
  // Bounded rather than `while (true)`: a server that kept handing back the
  // same token would otherwise spin until the Worker is killed.
  for (let page = 0; page < 64; page++) {
    const query = {
      'list-type': '2',
      prefix,
      'max-keys': '1000',
      ...(token ? { 'continuation-token': token } : {}),
    };
    const res = await b2(env, 'GET', '', query);
    if (!res.ok) throw new Error(`b2 list ${prefix}: ${res.status}`);
    const xml = await res.text();
    out.push(...parse(xml));
    token = parseContinuation(xml);
    if (!token) break;
  }
  return out;
}

function endpointFor(env) {
  return env.B2_ENDPOINT || `s3.${env.B2_REGION}.backblazeb2.com`;
}

/// One signed request the Worker makes on its own behalf.
async function b2(env, method, key, query = {}, body = undefined) {
  const url = await presign({
    accessKeyId: env.B2_KEY_ID,
    secretAccessKey: env.B2_APP_KEY,
    region: env.B2_REGION,
    endpoint: endpointFor(env),
    bucket: env.B2_BUCKET,
    method,
    key,
    expiresIn: 60,
    query,
  });
  return fetch(url, { method, body });
}

/// The `<Key>` elements of a ListObjectsV2 response.
///
/// A regex rather than a parser because the shape is fixed, the Worker owns
/// both ends of it, and adding an XML parser to a single-file Worker to read
/// one element is not a trade worth making. Keys are our own and match
/// `g/<hex>/m/<id>.json`, so there is no entity-escaping to get wrong.
function parseListKeys(xml) {
  const out = [];
  const re = /<Key>([^<]+)<\/Key>/g;
  let m;
  while ((m = re.exec(xml)) !== null) out.push(m[1]);
  return out;
}

/// Key and age together, which the collector needs and a plain key list
/// cannot give it.
///
/// Paired by reading each `<Contents>` block whole rather than zipping two
/// separate scans: a response where one object somehow lacks a `LastModified`
/// would otherwise shift every following date onto the wrong key, and the
/// collector would judge ages by another object's clock.
function parseListEntries(xml) {
  const out = [];
  const re = /<Contents>([\s\S]*?)<\/Contents>/g;
  let m;
  while ((m = re.exec(xml)) !== null) {
    const key = /<Key>([^<]+)<\/Key>/.exec(m[1]);
    const at = /<LastModified>([^<]+)<\/LastModified>/.exec(m[1]);
    if (!key || !at) continue;
    const ms = Date.parse(at[1]);
    if (Number.isNaN(ms)) continue;
    out.push({ key: key[1], lastModifiedMs: ms });
  }
  return out;
}

function parseContinuation(xml) {
  if (!/<IsTruncated>\s*true\s*<\/IsTruncated>/i.test(xml)) return null;
  const m = /<NextContinuationToken>([^<]+)<\/NextContinuationToken>/.exec(xml);
  return m ? m[1] : null;
}

/// Which blobs nothing points at any more.
///
/// THE COLLECTOR IS THE ONE PLACE HERE THAT DELETES, so it is a pure function
/// with its own tests and two independent guards, rather than a loop inside
/// the handler.
///
///   * REFERENCED BY ANY MANIFEST IS SAFE. Not "any recent manifest", not
///     "any manifest but the caller's" — any. A device that never publishes
///     again pins its blobs for ever, which is the conservative direction.
///   * AND SO IS ANYTHING YOUNG. A blob is uploaded before the manifest that
///     names it (see cloud_sync.dart's one invariant), so between those two
///     moments it is referenced by nothing and looks exactly like garbage. A
///     cycle is seconds; the guard is a day.
///
/// The failure mode being guarded against is the worst one this app has —
/// `lan_sync.dart` says it about deletes, and it is no less true here: losing
/// work everywhere at once. So it errs, deliberately, towards keeping a blob
/// nobody wants rather than removing one somebody does.
function unreferenced(blobs, manifests, { nowMs, minAgeMs }) {
  const referenced = new Set();
  for (const m of manifests) {
    for (const e of m?.entries ?? []) {
      if (typeof e?.h === 'string' && e.h) referenced.add(e.h);
    }
  }
  return blobs
    .filter((b) => {
      const sha = b.key.slice(b.key.lastIndexOf('/') + 1);
      if (referenced.has(sha)) return false;
      return nowMs - b.lastModifiedMs >= minAgeMs;
    })
    .map((b) => b.key);
}

// ---------------------------------------------------------------------------
// Group scoping
// ---------------------------------------------------------------------------

/// The bucket prefix for a share code's fingerprint.
///
/// NOT the fingerprint itself. A fingerprint is a truncated hash of a 60-bit
/// code, so the set of all of them is small enough to precompute; using it as
/// the prefix would let anyone who reached the bucket — or who guessed at this
/// endpoint — enumerate groups. An HMAC under a salt only the Worker holds
/// means the prefix cannot be derived off-device at all.
///
/// `GROUP_SALT` unset falls back to the B2 key, which is also Worker-only and
/// so is no weaker; it is a separate secret purely so the salt can be rotated
/// without minting a new bucket key. Rotating either one strands the files
/// already up there under the old prefix.
async function groupPrefix(env, fingerprint) {
  const salt = env.GROUP_SALT || env.B2_APP_KEY;
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(salt),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(`prototype-cloud-group\x00${fingerprint}`),
  );
  return Array.from(new Uint8Array(sig))
    .slice(0, 16)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

// ---------------------------------------------------------------------------

// Not constant-time in the length comparison — the header is an abuse
// throttle, not a credential, for the reason relay/README.md gives.
function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

export const _internal = {
  parseListKeys,
  parseListEntries,
  parseContinuation,
  unreferenced,
  groupPrefix,
  endpointFor,
};
