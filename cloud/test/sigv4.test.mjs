// Checks the presigner against AWS's OWN published example.
//
// A signer cannot be tested by reading it. Every mistake in one — a byte
// encoded the wrong way, a header out of order, the date stamp sliced a
// character short — produces a string that looks exactly as plausible as the
// right one and is rejected by the server with `SignatureDoesNotMatch` and
// nothing else. The only useful test is a known input with a known signature,
// and AWS publishes one:
//
//   "Example: Signature Calculation for Presigned URL"
//   https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-query-string-auth.html
//
// B2's S3 API implements the same SigV4, which is the whole reason a bucket
// there can be reached with an S3 signer at all — so a signer that reproduces
// AWS's example byte for byte is one B2 will accept.
//
// Run: node --test cloud/test/

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { presign, _internal } from '../sigv4.js';

// The credentials from AWS's example. They are documentation, not secrets:
// this exact pair appears in the S3 signing docs and in every SDK's test
// suite, and it authenticates nothing.
const EXAMPLE = {
  accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
  secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
  region: 'us-east-1',
  endpoint: 's3.amazonaws.com',
  bucket: 'examplebucket',
  method: 'GET',
  key: 'test.txt',
  expiresIn: 86400,
  now: new Date(Date.UTC(2013, 4, 24, 0, 0, 0)),
};

test('reproduces the signature from AWS\'s published example', async () => {
  const url = await presign(EXAMPLE);
  const signature = new URL(url).searchParams.get('X-Amz-Signature');
  assert.equal(
    signature,
    'aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404',
  );
});

test('signs the host the request will actually be sent to', async () => {
  const url = new URL(await presign(EXAMPLE));
  assert.equal(url.host, 'examplebucket.s3.amazonaws.com');
  assert.equal(url.pathname, '/test.txt');
});

test('path-style puts the bucket in front of the key instead', async () => {
  const url = new URL(await presign({ ...EXAMPLE, pathStyle: true }));
  assert.equal(url.host, 's3.amazonaws.com');
  assert.equal(url.pathname, '/examplebucket/test.txt');
});

test('the credential scope names the region and the date', async () => {
  const url = new URL(await presign(EXAMPLE));
  assert.equal(
    url.searchParams.get('X-Amz-Credential'),
    'AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request',
  );
  assert.equal(url.searchParams.get('X-Amz-Date'), '20130524T000000Z');
});

// A blob key is `g/<32 hex>/b/<64 hex>`, so the slashes between its segments
// have to stay slashes. Encoding them would sign a path the server never sees
// and every request would fail; this is the exact shape the Worker signs.
test('keeps the separators in a multi-segment key', () => {
  const path = _internal.canonicalKeyPath(
    'bucket',
    'g/abc123/b/deadbeef',
    false,
  );
  assert.equal(path, '/g/abc123/b/deadbeef');
});

// RFC 3986 encodes these four; encodeURIComponent alone does not. A key
// carrying one would sign differently from how it is sent.
test('encodes the characters encodeURIComponent leaves alone', () => {
  assert.equal(_internal.uriEncode("a!b'c(d)e*f"), 'a%21b%27c%28d%29e%2Af');
});

// The stamps are sliced out of an ISO string; an off-by-one in either one
// puts the date in the scope out of step with X-Amz-Date, which AWS rejects.
test('derives both stamps from the same instant', () => {
  const { amzDate, dateStamp } = _internal.stamps(
    new Date(Date.UTC(2026, 8, 22, 11, 42, 33, 500)),
  );
  assert.equal(amzDate, '20260922T114233Z');
  assert.equal(dateStamp, '20260922');
});
