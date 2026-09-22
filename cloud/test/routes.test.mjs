// The Worker as a request handler: routing, refusals, and the shape of what
// comes back.
//
// B2 is stubbed. That is not a weaker test than it looks — what is being
// checked here is every decision the Worker makes BEFORE it talks to B2 and
// what it does with the answer, which is where the refusals live. Whether B2
// accepts the signature is a separate question, answered against AWS's own
// published vector in `sigv4.test.mjs`.
//
// Run: node --test 'test/*.test.mjs'

import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';

import worker from '../worker.js';

const ENV = {
  B2_KEY_ID: 'keyid',
  B2_APP_KEY: 'appkey',
  B2_BUCKET: 'bucket',
  B2_REGION: 'eu-central-003',
  GROUP_SALT: 'salt',
  CLOUD_SECRET: 'throttle',
};

const GROUP = '0123456789abcdef';

/// Every B2 request the Worker made during one call.
let calls = [];
let respond = () => new Response('<ListBucketResult/>', { status: 200 });
const realFetch = globalThis.fetch;

beforeEach(() => {
  calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), method: init?.method, body: init?.body });
    return respond(String(url), init);
  };
});

afterEach(() => {
  globalThis.fetch = realFetch;
  respond = () => new Response('<ListBucketResult/>', { status: 200 });
});

function call(path, { headers = {}, body, method = 'POST' } = {}) {
  return worker.fetch(
    new Request(`https://w.test${path}`, {
      method,
      headers: {
        'x-cloud-group': GROUP,
        'x-cloud-secret': 'throttle',
        'x-cloud-device': 'device-one',
        ...headers,
      },
      body,
    }),
    ENV,
  );
}

test('refuses anything that is not a POST', async () => {
  const res = await call('/v1/pull', { method: 'GET' });
  assert.equal(res.status, 405);
  assert.equal(calls.length, 0, 'and spends no B2 request finding out');
});

test('refuses a wrong throttle secret', async () => {
  const res = await call('/v1/pull', { headers: { 'x-cloud-secret': 'nope' } });
  assert.equal(res.status, 401);
  assert.equal(calls.length, 0);
});

// The group is what scopes the bucket prefix, so anything that is not exactly
// a fingerprint is refused before it can be turned into a path.
test('refuses a group that is not a fingerprint', async () => {
  for (const group of ['', 'short', '0123456789abcdefg', '../../etc', 'G'.repeat(16)]) {
    const res = await call('/v1/pull', { headers: { 'x-cloud-group': group } });
    assert.equal(res.status, 400, `${group} must be refused`);
  }
  assert.equal(calls.length, 0);
});

test('refuses an unknown path', async () => {
  assert.equal((await call('/v1/whatever')).status, 404);
});

test('says which settings are missing rather than failing obscurely', async () => {
  const res = await worker.fetch(
    new Request('https://w.test/v1/pull', { method: 'POST' }),
    { B2_KEY_ID: 'k' },
  );
  assert.equal(res.status, 500);
  const body = await res.json();
  assert.match(body.error, /B2_APP_KEY/);
  assert.match(body.error, /B2_BUCKET/);
});

test('a pull reads every manifest the listing named', async () => {
  respond = (url) => {
    if (url.includes('list-type=2')) {
      return new Response(
        '<ListBucketResult>' +
          '<Contents><Key>g/x/m/one.json</Key></Contents>' +
          '<Contents><Key>g/x/m/two.json</Key></Contents>' +
          '</ListBucketResult>',
        { status: 200 },
      );
    }
    const device = url.includes('two.json') ? 'two' : 'one';
    return new Response(
      JSON.stringify({ device, name: device, at: 1, entries: [], tombs: [] }),
      { status: 200 },
    );
  };
  const res = await call('/v1/pull');
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.deepEqual(body.manifests.map((m) => m.device), ['one', 'two']);
});

// One device's unreadable manifest costs that device's updates this cycle.
// Failing the pull would cost every device's.
test('a pull survives one manifest being corrupt', async () => {
  respond = (url) => {
    if (url.includes('list-type=2')) {
      return new Response(
        '<ListBucketResult>' +
          '<Contents><Key>g/x/m/good.json</Key></Contents>' +
          '<Contents><Key>g/x/m/bad.json</Key></Contents>' +
          '</ListBucketResult>',
        { status: 200 },
      );
    }
    if (url.includes('bad.json')) return new Response('{ not json', { status: 200 });
    return new Response(JSON.stringify({ device: 'good', entries: [] }), {
      status: 200,
    });
  };
  const body = await (await call('/v1/pull')).json();
  assert.deepEqual(body.manifests.map((m) => m.device), ['good']);
});

test('a push refuses a device id that could escape the prefix', async () => {
  for (const device of ['', '../../etc/passwd', 'a/b', 'x'.repeat(33)]) {
    const res = await call('/v1/push', {
      headers: { 'x-cloud-device': device },
      body: '{}',
    });
    assert.equal(res.status, 400, `${device} must be refused`);
  }
});

// Stored unparsed, a bad manifest breaks every OTHER device's pull — a far
// more confusing failure than a 400 here.
test('a push refuses a manifest that is not json', async () => {
  const res = await call('/v1/push', { body: 'not json at all' });
  assert.equal(res.status, 400);
  assert.equal(calls.length, 0, 'and never writes it');
});

test('a push writes the callerid it was given', async () => {
  const res = await call('/v1/push', { body: '{"device":"device-one"}' });
  assert.equal(res.status, 200);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].method, 'PUT');
  assert.match(calls[0].url, /\/g\/[a-f0-9]{32}\/m\/device-one\.json\?/);
});

test('a blob url is signed for exactly the sha asked for', async () => {
  const sha = 'a'.repeat(64);
  const res = await call('/v1/blob', {
    body: JSON.stringify({ op: 'get', sha }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.match(body.url, new RegExp(`/g/[a-f0-9]{32}/b/${sha}\\?`));
  assert.match(body.url, /X-Amz-Signature=[a-f0-9]{64}/);
  assert.equal(calls.length, 0, 'signing is local; it costs no B2 request');
});

test('a blob url is refused for anything that is not a sha', async () => {
  for (const sha of ['', 'xyz', '../../m/one.json', 'a'.repeat(63), 'A'.repeat(64)]) {
    const res = await call('/v1/blob', {
      body: JSON.stringify({ op: 'get', sha }),
    });
    assert.equal(res.status, 400, `${sha} must be refused`);
  }
});

test('a blob url is refused for an operation that is not get or put', async () => {
  for (const op of ['delete', 'DELETE', '', 'list']) {
    const res = await call('/v1/blob', {
      body: JSON.stringify({ op, sha: 'b'.repeat(64) }),
    });
    assert.equal(res.status, 400, `${op} must be refused`);
  }
});

// The collector defaults to reporting. Forgetting the flag must not delete.
test('gc reports rather than deletes unless told otherwise', async () => {
  respond = (url) => {
    if (url.includes(encodeURIComponent('/m/'))) {
      return new Response('<ListBucketResult/>', { status: 200 });
    }
    return new Response('<ListBucketResult/>', { status: 200 });
  };
  const body = await (await call('/v1/gc', { body: '{}' })).json();
  assert.equal(body.dryRun, true);
  assert.equal(
    calls.some((c) => c.method === 'DELETE'),
    false,
    'a dry run deletes nothing',
  );
});

// Collecting against a partial set of manifests is the one mistake here that
// destroys live data, so an unreadable manifest stops the whole run.
test('gc refuses to run when a manifest cannot be read', async () => {
  respond = (url) => {
    if (url.includes('list-type=2')) {
      return new Response(
        '<ListBucketResult><Contents><Key>g/x/m/one.json</Key></Contents></ListBucketResult>',
        { status: 200 },
      );
    }
    return new Response('nope', { status: 500 });
  };
  const res = await call('/v1/gc', { body: '{"dryRun":false}' });
  assert.equal(res.status, 502);
  assert.equal(calls.some((c) => c.method === 'DELETE'), false);
});
