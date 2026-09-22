// The Worker's own decisions — the ones that are not the signer.
//
// Everything here is a pure function on purpose. What is left in the Worker
// after the signing is pulled out is request validation and one HMAC, and
// both are the kind of thing that is wrong in a way no deployment surfaces:
// a group prefix that quietly collides puts two people's documents in one
// folder, and a regex that accepts one character too many is a path escape.
//
// Run: node --test cloud/test/

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { _internal } from '../worker.js';

const env = { B2_APP_KEY: 'key-secret', GROUP_SALT: 'salt-for-the-test' };

test('a group prefix is stable for one fingerprint', async () => {
  const a = await _internal.groupPrefix(env, '0123456789abcdef');
  const b = await _internal.groupPrefix(env, '0123456789abcdef');
  assert.equal(a, b);
  assert.match(a, /^[a-f0-9]{32}$/);
});

test('different codes land in different folders', async () => {
  const a = await _internal.groupPrefix(env, '0123456789abcdef');
  const b = await _internal.groupPrefix(env, 'fedcba9876543210');
  assert.notEqual(a, b);
});

// The point of the salt: the prefix is not derivable from the fingerprint
// alone, so reaching the bucket or guessing at the endpoint does not let
// anyone enumerate groups. Two Workers with different salts must not agree.
test('the prefix depends on the salt, not only the fingerprint', async () => {
  const a = await _internal.groupPrefix(env, '0123456789abcdef');
  const b = await _internal.groupPrefix(
    { ...env, GROUP_SALT: 'a different salt' },
    '0123456789abcdef',
  );
  assert.notEqual(a, b);
});

test('the salt falls back to the bucket key when unset', async () => {
  const withFallback = await _internal.groupPrefix(
    { B2_APP_KEY: 'key-secret' },
    '0123456789abcdef',
  );
  const explicit = await _internal.groupPrefix(
    { B2_APP_KEY: 'key-secret', GROUP_SALT: 'key-secret' },
    '0123456789abcdef',
  );
  assert.equal(withFallback, explicit);
});

test('builds the B2 endpoint from the region', () => {
  assert.equal(
    _internal.endpointFor({ B2_REGION: 'eu-central-003' }),
    's3.eu-central-003.backblazeb2.com',
  );
});

test('an explicit endpoint wins over the derived one', () => {
  assert.equal(
    _internal.endpointFor({
      B2_REGION: 'eu-central-003',
      B2_ENDPOINT: 's3.example.test',
    }),
    's3.example.test',
  );
});

test('reads every key out of a listing', () => {
  const xml =
    '<?xml version="1.0"?><ListBucketResult>' +
    '<Contents><Key>g/aa/m/one.json</Key><Size>12</Size></Contents>' +
    '<Contents><Key>g/aa/m/two.json</Key><Size>34</Size></Contents>' +
    '</ListBucketResult>';
  assert.deepEqual(_internal.parseListKeys(xml), [
    'g/aa/m/one.json',
    'g/aa/m/two.json',
  ]);
});

test('an empty listing is no keys, not a crash', () => {
  assert.deepEqual(
    _internal.parseListKeys('<ListBucketResult></ListBucketResult>'),
    [],
  );
});

// ---------------------------------------------------------------------------
// The collector
//
// The only thing in this Worker that destroys anything. `lan_sync.dart` says
// it about deletes and it is no less true here: the failure mode is losing
// work everywhere at once. So these tests are mostly about what it must NOT
// take.
// ---------------------------------------------------------------------------

const DAY = 24 * 60 * 60 * 1000;
const NOW = Date.UTC(2026, 8, 22, 12, 0, 0);
const old = (days) => NOW - days * DAY;

const blob = (sha, ageDays) => ({
  key: `g/aa/b/${sha}`,
  lastModifiedMs: old(ageDays),
});

const manifest = (...shas) => ({
  device: 'd',
  entries: shas.map((h) => ({ p: `${h}.ptp`, s: 1, m: 1, h })),
});

test('collects a blob nothing points at any more', () => {
  const doomed = _internal.unreferenced(
    [blob('aaa', 30), blob('bbb', 30)],
    [manifest('aaa')],
    { nowMs: NOW, minAgeMs: DAY },
  );
  assert.deepEqual(doomed, ['g/aa/b/bbb']);
});

test('never collects a blob a manifest still names', () => {
  const doomed = _internal.unreferenced(
    [blob('aaa', 365)],
    [manifest('aaa')],
    { nowMs: NOW, minAgeMs: DAY },
  );
  assert.deepEqual(doomed, []);
});

// The upload-before-publish invariant means a blob is referenced by nothing
// for the seconds between its PUT and its manifest. Without the age guard the
// collector would take a document somebody is in the middle of uploading.
test('never collects a blob younger than the guard', () => {
  const doomed = _internal.unreferenced(
    [blob('fresh', 0)],
    [manifest('something-else')],
    { nowMs: NOW, minAgeMs: DAY },
  );
  assert.deepEqual(doomed, []);
});

// One device holding a document is enough to keep its bytes, however many
// other devices have moved on from it.
test('one device still naming it is enough to keep it', () => {
  const doomed = _internal.unreferenced(
    [blob('shared', 30)],
    [manifest('moved-on'), manifest('shared')],
    { nowMs: NOW, minAgeMs: DAY },
  );
  assert.deepEqual(doomed, []);
});

// A bucket whose manifests all failed to parse would look like "nothing is
// referenced", which is every blob. The handler refuses to run in that case;
// this pins that the pure function is not the thing being relied on for it.
test('no manifests at all means everything old looks unreferenced', () => {
  const doomed = _internal.unreferenced([blob('aaa', 30)], [], {
    nowMs: NOW,
    minAgeMs: DAY,
  });
  assert.deepEqual(doomed, ['g/aa/b/aaa'],
    'which is why gc() fails rather than proceeding on unreadable manifests');
});

test('survives a manifest with no entries at all', () => {
  const doomed = _internal.unreferenced(
    [blob('aaa', 30)],
    [{ device: 'd' }, null, { device: 'e', entries: null }],
    { nowMs: NOW, minAgeMs: DAY },
  );
  assert.deepEqual(doomed, ['g/aa/b/aaa']);
});

test('reads key and date from the same Contents block', () => {
  const xml =
    '<ListBucketResult>' +
    '<Contents><Key>g/aa/b/one</Key>' +
    '<LastModified>2026-09-01T00:00:00.000Z</LastModified></Contents>' +
    '<Contents><Key>g/aa/b/two</Key>' +
    '<LastModified>2026-09-02T00:00:00.000Z</LastModified></Contents>' +
    '</ListBucketResult>';
  assert.deepEqual(_internal.parseListEntries(xml), [
    { key: 'g/aa/b/one', lastModifiedMs: Date.UTC(2026, 8, 1) },
    { key: 'g/aa/b/two', lastModifiedMs: Date.UTC(2026, 8, 2) },
  ]);
});

// An object missing its date is SKIPPED, not paired with the next one's.
// Zipping two separate scans would shift every following date by one and make
// the collector judge ages by another object's clock.
test('skips an object it cannot date rather than shifting the rest', () => {
  const xml =
    '<ListBucketResult>' +
    '<Contents><Key>g/aa/b/undated</Key></Contents>' +
    '<Contents><Key>g/aa/b/two</Key>' +
    '<LastModified>2026-09-02T00:00:00.000Z</LastModified></Contents>' +
    '</ListBucketResult>';
  assert.deepEqual(_internal.parseListEntries(xml), [
    { key: 'g/aa/b/two', lastModifiedMs: Date.UTC(2026, 8, 2) },
  ]);
});

// A listing capped at 1,000 that was read as the whole bucket would have the
// collector judge "referenced by nothing" against a fraction of it.
test('notices a truncated listing and carries the token', () => {
  const xml =
    '<ListBucketResult><IsTruncated>true</IsTruncated>' +
    '<NextContinuationToken>abc123</NextContinuationToken></ListBucketResult>';
  assert.equal(_internal.parseContinuation(xml), 'abc123');
});

test('a complete listing carries no token', () => {
  assert.equal(
    _internal.parseContinuation(
      '<ListBucketResult><IsTruncated>false</IsTruncated></ListBucketResult>',
    ),
    null,
  );
  assert.equal(_internal.parseContinuation('<ListBucketResult/>'), null);
});
