'use strict';
// Only this trusted page can communicate with native code. Model Python lives
// in a Worker: no DOM, WebKit handler, app files or credentials.
let worker = null;
let active = null;
let timer = null;
function send(id, event) {
  const payload = {id, event};
  if (window.webkit?.messageHandlers?.cadRuntime) {
    window.webkit.messageHandlers.cadRuntime.postMessage(payload);
  } else if (window.cadTestEvent) {
    window.cadTestEvent(payload);
  }
}
function reset() {
  clearTimeout(timer);
  if (worker) worker.terminate();
  worker = null;
  active = null;
}
window.cadRun = function(id, job) {
  if (active) throw new Error('A local build is already running');
  if (!worker) {
    worker = new Worker('worker.js');
    const launched = worker;
    worker.onerror = e => {
      if (worker !== launched) return;
      if (active) send(active, {type: 'error', error: e.message || 'Local CAD runtime failed'});
      reset();
    };
    worker.onmessage = e => {
      if (worker !== launched) return;
      let payload;
      try { payload = typeof e.data === 'string' ? JSON.parse(e.data) : e.data; }
      catch (_) { send(active, {type:'error',error:'Invalid local CAD event'}); reset(); return; }
      if (payload.id !== active || !payload.event) return;
      send(active, payload.event);
      if (['complete','error'].includes(payload.event.type)) {
        clearTimeout(timer);
        active = null;
      }
    };
  }
  active = id;
  timer = setTimeout(() => {
    send(id, {type:'error',error:'Local CAD build exceeded 150 seconds'});
    reset();
  }, 150000);
  worker.postMessage({id, job});
};
window.cadCancel = function(id) {
  if (active !== id) return;
  send(id, {type:'error',error:'Local CAD build cancelled'});
  reset();
};
