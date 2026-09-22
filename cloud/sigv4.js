// AWS SigV4 presigning, for Backblaze B2's S3-compatible API.
//
// WHY BY HAND rather than `aws4fetch` or the AWS SDK. The SDK does not run in
// a Worker at all — it reaches for DOMParser, which is not there — and
// aws4fetch would make this directory an npm project for one function. The
// Worker is otherwise a single file `wrangler deploy` uploads as-is, and
// relay/ next door is the same shape. Eighty lines of WebCrypto keeps it that
// way.
//
// EVERYTHING IS PRESIGNED, including the requests the Worker makes itself.
// Signing into the `Authorization` header and signing into the query string
// are two code paths that differ in exactly one place, and the query-string
// form is the one the app needs anyway — so the Worker builds a URL and
// fetches it, rather than carrying a second signer for its own use.
//
// The payload is always UNSIGNED-PAYLOAD. A presigned PUT cannot hash a body
// the Worker never sees (that is the whole point — document bytes go device
// to B2 directly), and B2 accepts it exactly as S3 does.

const ALGORITHM = 'AWS4-HMAC-SHA256';
const SERVICE = 's3';

/// RFC 3986, which is stricter than encodeURIComponent: AWS wants the four
/// characters it leaves alone encoded too, and a signature that disagrees with
/// the server about one byte fails with no useful message.
function uriEncode(str) {
  return encodeURIComponent(str).replace(
    /[!'()*]/g,
    (c) => '%' + c.charCodeAt(0).toString(16).toUpperCase(),
  );
}

/// Where the bucket goes: in the host (virtual-hosted, the default and what
/// both AWS and B2 document) or in front of the key (path-style).
///
/// Both are kept because they are one line each and the choice is not ours to
/// make for ever: B2 serves both today, a bucket name with a dot in it breaks
/// virtual-hosted TLS, and `B2_PATH_STYLE` is the escape hatch for the day one
/// of those matters. Virtual-hosted is also what AWS's published presigning
/// example uses, which is what `test/sigv4.test.mjs` checks this against —
/// there is no other way to know a signer is right short of a live bucket.
function canonicalKeyPath(bucket, key, pathStyle) {
  const segments = key.split('/').map(uriEncode).join('/');
  return pathStyle ? `/${uriEncode(bucket)}/${segments}` : `/${segments}`;
}

function hostFor(endpoint, bucket, pathStyle) {
  const host = endpoint.replace(/^https?:\/\//, '').replace(/\/$/, '');
  return pathStyle ? host : `${bucket}.${host}`;
}

async function sha256Hex(data) {
  const bytes =
    typeof data === 'string' ? new TextEncoder().encode(data) : data;
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return hex(new Uint8Array(digest));
}

async function hmac(key, message) {
  const k = await crypto.subtle.importKey(
    'raw',
    typeof key === 'string' ? new TextEncoder().encode(key) : key,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign(
    'HMAC',
    k,
    new TextEncoder().encode(message),
  );
  return new Uint8Array(sig);
}

function hex(bytes) {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/// The `20260922T114233Z` / `20260922` pair every part of the signature needs.
function stamps(now) {
  const iso = now.toISOString().replace(/[:-]|\.\d{3}/g, '');
  return { amzDate: iso, dateStamp: iso.slice(0, 8) };
}

/// A presigned URL for one object operation.
///
/// `query` carries operation parameters that must be SIGNED — the listing's
/// `list-type` and `prefix`, say. Anything not passed here and appended later
/// would invalidate the signature, so there is nowhere else to put them.
export async function presign({
  accessKeyId,
  secretAccessKey,
  region,
  endpoint,
  bucket,
  method,
  key,
  expiresIn = 900,
  query = {},
  pathStyle = false,
  now = new Date(),
}) {
  const host = hostFor(endpoint, bucket, pathStyle);
  const { amzDate, dateStamp } = stamps(now);
  const scope = `${dateStamp}/${region}/${SERVICE}/aws4_request`;

  const params = {
    ...query,
    'X-Amz-Algorithm': ALGORITHM,
    'X-Amz-Credential': `${accessKeyId}/${scope}`,
    'X-Amz-Date': amzDate,
    'X-Amz-Expires': String(expiresIn),
    'X-Amz-SignedHeaders': 'host',
  };

  // Sorted by key, as the canonical form requires. Object key order is close
  // enough to insertion order in practice and not close enough to rely on.
  const canonicalQuery = Object.keys(params)
    .sort()
    .map((k) => `${uriEncode(k)}=${uriEncode(params[k])}`)
    .join('&');

  const canonicalUri = canonicalKeyPath(bucket, key, pathStyle);
  const canonicalRequest = [
    method,
    canonicalUri,
    canonicalQuery,
    `host:${host}\n`,
    'host',
    'UNSIGNED-PAYLOAD',
  ].join('\n');

  const stringToSign = [
    ALGORITHM,
    amzDate,
    scope,
    await sha256Hex(canonicalRequest),
  ].join('\n');

  let signing = await hmac(`AWS4${secretAccessKey}`, dateStamp);
  signing = await hmac(signing, region);
  signing = await hmac(signing, SERVICE);
  signing = await hmac(signing, 'aws4_request');
  const signature = hex(await hmac(signing, stringToSign));

  return `https://${host}${canonicalUri}?${canonicalQuery}&X-Amz-Signature=${signature}`;
}

export const _internal = {
  uriEncode,
  canonicalKeyPath,
  hostFor,
  sha256Hex,
  stamps,
};
