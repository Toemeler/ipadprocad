#!/usr/bin/env python3
"""Exercise the actual shared desktop browser scripts without an account."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory() as folder:
    executable = Path(folder) / 'scripts'
    source = r'''
#include "frontend/packages/native_menu/common/grabcad_protocol.h"
#include <cassert>
#include <iostream>
int main() {
  assert(grabcad::MetadataPath("models"));
  assert(grabcad::MetadataPath("models/gear/files?folder_id=2"));
  assert(grabcad::MetadataPath("models/%C3%9Cber/files"));
  for (auto path : {"members/me", "models/../members/me", "models/%2e%2E/members/me",
                    "models/x\\files", "models/x%00", "models/%252e%252e/x"})
    assert(!grabcad::MetadataPath(path));
  assert(grabcad::GrabCadUrl("https://grabcad.com/library/gear/download"));
  for (auto url : {"https://grabcad.com.evil/x", "http://grabcad.com/x", "https://user@grabcad.com/x"})
    assert(!grabcad::GrabCadUrl(url));
  assert(grabcad::FileName("Bearing.step"));
  for (auto name : {"../bearing.step", "x:y.step", "", "x\\gear.step"}) assert(!grabcad::FileName(name));
  const std::string body = "{\"query\":\"cup\\\";window.pwned=true;//\"}";
  std::cout << "{\"login\":" << grabcad::Quote(grabcad::LoginScript())
            << ",\"post\":" << grabcad::Quote(grabcad::RequestScript("metadata-1", "models", &body))
            << ",\"get\":" << grabcad::Quote(grabcad::RequestScript("metadata-2", "models/gear/files?folder_id=2", nullptr)) << "}";
}
'''
    subprocess.run([os.getenv('CXX', 'g++'), '-std=c++17', '-Wall', '-Werror',
                    '-I'+str(ROOT), '-x', 'c++', '-', '-o', str(executable)],
                   input=source, text=True, check=True)
    scripts = json.loads(subprocess.check_output([str(executable)], text=True))
    harness = r'''
const assert = require('node:assert/strict');
const vm = require('node:vm');
const scripts = JSON.parse(process.argv[1]);
let checks = 0;
async function run(script, backend, options = {}) {
  const messages = [], calls = [];
  const channel = {postMessage: m => messages.push(m)};
  const context = vm.createContext({
    window: backend === 'Windows' ? {chrome: {webview: channel}} : {webkit: {messageHandlers: {prototype: channel}}},
    location: {origin: options.origin || 'https://grabcad.com'},
    document: {querySelector: () => ({content: 'private-csrf-token'})},
    AbortController, setTimeout, clearTimeout,
    fetch: async (path, args) => {
      calls.push({path, args});
      if (options.error) throw Object.assign(new Error('private error body'), {name: options.error});
      return {url: 'https://grabcad.com'+path, status: 200, ok: true,
        headers: {get: () => 'application/json'}, text: async () => '{"models":[]}',
        json: async () => ({id: 1, private: 'do-not-export'}), ...options.response};
    }
  });
  await vm.runInContext(script, context);
  assert(!context.window.pwned);
  assert(!messages.join('').includes('private-csrf-token'));
  assert(!messages.join('').includes('do-not-export'));
  ++checks;
  return {messages, calls};
}
(async()=>{
  for (const backend of ['Windows', 'Linux']) {
    let result = await run(scripts.login, backend);
    assert.deepEqual(result.messages, ['auth\n1']);
    assert.equal(result.calls[0].args.credentials, 'same-origin');
    result = await run(scripts.login, backend, {response: {status: 204, json: async()=>{throw Error('must not parse 204')}}});
    assert.deepEqual(result.messages, ['auth\n0']);
    result = await run(scripts.post, backend);
    assert.deepEqual(result.messages, ['metadata-1\n200\napplication/json\n{"models":[]}']);
    assert.equal(result.calls[0].args.headers['X-CSRF-Token'], 'private-csrf-token');
    assert.equal(result.calls[0].args.credentials, 'same-origin');
    assert.equal(result.calls[0].args.redirect, 'manual');
    assert.equal(JSON.parse(result.calls[0].args.body).query, 'cup";window.pwned=true;//');
    result = await run(scripts.get, backend);
    assert.equal(result.calls[0].args.method, 'GET');
    assert.equal(result.calls[0].path, '/community/api/v1/models/gear/files?folder_id=2');
    result = await run(scripts.post, backend, {response: {status: 403, headers: {get: ()=>'text/html'}, text: async()=>{throw Error('do not export login HTML')}}});
    assert.deepEqual(result.messages, ['metadata-1\n403\ntext/html\n']);
    result = await run(scripts.get, backend, {response: {type: 'opaqueredirect'}});
    assert.deepEqual(result.messages, ['metadata-2\n-1\naccess_denied']);
    result = await run(scripts.get, backend, {error: 'AbortError'});
    assert.deepEqual(result.messages, ['metadata-2\n-1\ntimeout']);
    result = await run(scripts.get, backend, {error: 'TypeError'});
    assert.deepEqual(result.messages, ['metadata-2\n-1\nunavailable']);
    result = await run(scripts.get, backend, {origin: 'https://example.com'});
    assert.equal(result.calls.length, 0);
    assert.deepEqual(result.messages, ['metadata-2\n-1\naccess_denied']);
  }
  console.log(`${checks} desktop browser protocol cases passed`);
})().catch(e=>{console.error(e);process.exitCode=1});
'''
    subprocess.run(['node', '-e', harness, json.dumps(scripts)], check=True)
