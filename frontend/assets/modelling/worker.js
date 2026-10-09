'use strict';
importScripts('pyodide.js');
let runtime = null;
async function init() {
  const base = new URL('.', self.location.href).href;
  const manifest = await (await fetch(base + 'manifest.json')).json();
  const py = await loadPyodide({indexURL:base, stdout:()=>{}, stderr:()=>{}});
  await py.loadPackage(manifest.packages);
  // Every dependency is installed from the hash-locked app bundle, without
  // PyPI resolution or network fallback on device.
  py.globals.set('_wheels_json', JSON.stringify(manifest.wheels.map(f => base + f)));
  await py.runPythonAsync(`import json, micropip
await micropip.install(json.loads(_wheels_json), deps=False)
import build123d
`);
  const font = new Uint8Array(await (await fetch(base + 'Inter-Regular.ttf')).arrayBuffer());
  py.FS.writeFile('/tmp/Inter-Regular.ttf', font);
  py.runPython(`from OCP.Font import Font_FontMgr, Font_SystemFont, Font_FA_Regular
from OCP.TCollection import TCollection_AsciiString
_font = Font_SystemFont(TCollection_AsciiString('Inter'))
_font.SetFontPath(Font_FA_Regular, TCollection_AsciiString('/tmp/Inter-Regular.ttf'))
Font_FontMgr.GetInstance_s().RegisterFont(_font, True)
`);
  const source = await (await fetch(base + 'runner.py')).text();
  py.globals.set('_runner_source', source);
  py.runPython(`_cad_runtime = {'__name__': 'cad_runtime'}
exec(compile(_runner_source, 'cad_runtime.py', 'exec'), _cad_runtime)
`);
  return py;
}
self.onmessage = async ({data:{id,job}}) => {
  let initialized = false;
  try {
    runtime ??= init();
    const py = await runtime;
    initialized = true;
    py.globals.set('_job_json', JSON.stringify(job));
    py.globals.set('_job_id', id);
    // Only transient model inputs enter the Python virtual filesystem.
    py.runPython(`import json, js, traceback
_cad_runtime['emit'] = lambda event: js.postMessage(json.dumps({'id':_job_id, 'event':event}, allow_nan=False))
try:
    _cad_runtime['run'](json.loads(_job_json))
except BaseException as error:
    _cad_runtime['emit']({'type':'error', 'error':f'{type(error).__name__}: {error}'[:2000], 'traceback':traceback.format_exc()[-6000:]})
`);
    py.globals.delete('_job_json');
  } catch (error) {
    self.postMessage({id,event:{type:'error',error:String(error).slice(0,6000),fatal:!initialized}});
    runtime = null;
  }
};
