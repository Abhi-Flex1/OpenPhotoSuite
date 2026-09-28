// Bootstrap injected into the Web page before any upstream module script runs
// (via runJavaScript on onPageBegin; ES modules execute after parsing, so this
// wins the race). It provides the exact window.__TAURI__ surface the upstream
// frontend uses on desktop — core.invoke, store.load, clipboardManager, event —
// routed over the nativeBridge javaScriptProxy to the ArkTS TauriBridge.
//
// Upstream src/ is loaded 1-to-1; this file is the only HarmonyOS-specific JS.

export const TAURI_SHIM_JS: string = `(function () {
  if (window.__TAURI__ && window.__TAURI__.__harmony) return;

  function bytesToB64(bytes) {
    var binary = '';
    var chunk = 8192;
    for (var i = 0; i < bytes.length; i += chunk) {
      var slice = bytes.subarray(i, i + chunk);
      binary += String.fromCharCode.apply(null, slice);
    }
    return btoa(binary);
  }

  function b64ToBytes(b64) {
    var binary = atob(b64);
    var bytes = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  }

  function encodeBinary(value) {
    if (value instanceof Uint8Array) {
      return { __bytesB64: bytesToB64(value) };
    }
    if (value instanceof ArrayBuffer) {
      return { __bytesB64: bytesToB64(new Uint8Array(value)) };
    }
    if (Array.isArray(value)) {
      var out = [];
      for (var i = 0; i < value.length; i++) out.push(encodeBinary(value[i]));
      return out;
    }
    if (value !== null && typeof value === 'object') {
      var obj = {};
      for (var key in value) {
        if (Object.prototype.hasOwnProperty.call(value, key)) obj[key] = encodeBinary(value[key]);
      }
      return obj;
    }
    return value;
  }

  function decodeBinary(value) {
    if (value !== null && typeof value === 'object' && typeof value.__bytesB64 === 'string' &&
      Object.keys(value).length === 1) {
      return b64ToBytes(value.__bytesB64);
    }
    return value;
  }

  var seq = 0;
  var pending = {};

  window.__harmonyResolve = function (id, ok, payloadJson) {
    var entry = pending[id];
    if (!entry) return;
    delete pending[id];
    var value = null;
    try {
      value = JSON.parse(payloadJson);
    } catch (e) {
      if (ok) entry.resolve(null);
      else entry.reject(new Error('bad bridge payload'));
      return;
    }
    if (ok) entry.resolve(decodeBinary(value));
    else entry.reject(new Error(typeof value === 'string' ? value : JSON.stringify(value)));
  };

  function invoke(cmd, args, options) {
    var payload = { id: 'm' + (++seq), cmd: String(cmd), args: encodeBinary(args === undefined ? {} : args) };
    if (options !== undefined) payload.options = encodeBinary(options);
    return new Promise(function (resolve, reject) {
      pending[payload.id] = { resolve: resolve, reject: reject };
      try {
        window.nativeBridge.postMessage(JSON.stringify(payload));
      } catch (e) {
        delete pending[payload.id];
        reject(e instanceof Error ? e : new Error(String(e)));
      }
    });
  }

  function convertFileSrc(path) {
    var p = String(path == null ? '' : path);
    if (p.indexOf('file://') === 0) return p;
    return 'file://' + p;
  }

  // tauri-plugin-store equivalent backed by two hidden native commands that
  // persist one JSON document per store file under the app files directory.
  var storeCache = {};

  function storeLoad(file, opts) {
    var name = String(file);
    if (!storeCache[name]) {
      storeCache[name] = invoke('__store_read', { file: name }).then(function (text) {
        var data = {};
        if (typeof text === 'string' && text.length > 0) {
          try {
            data = JSON.parse(text) || {};
          } catch (e) {
            data = {};
          }
        }
        return { data: data, timer: null };
      });
    }
    var statePromise = storeCache[name];
    function flush() {
      return statePromise.then(function (state) {
        if (state.timer !== null) {
          clearTimeout(state.timer);
          state.timer = null;
        }
        return invoke('__store_write', { file: name, json: JSON.stringify(state.data) }).then(function () {});
      });
    }
    function scheduleFlush(state) {
      if (state.timer !== null) clearTimeout(state.timer);
      state.timer = setTimeout(function () {
        state.timer = null;
        invoke('__store_write', { file: name, json: JSON.stringify(state.data) }).catch(function () {});
      }, 500);
    }
    return Promise.resolve({
      get: function (key) {
        return statePromise.then(function (state) {
          var v = state.data[String(key)];
          return v === undefined ? null : v;
        });
      },
      set: function (key, value) {
        return statePromise.then(function (state) {
          state.data[String(key)] = value === undefined ? null : value;
          scheduleFlush(state);
        });
      },
      save: function () {
        return flush();
      }
    });
  }

  window.__TAURI__ = {
    __harmony: true,
    core: {
      invoke: invoke,
      convertFileSrc: convertFileSrc
    },
    store: {
      load: function (file, opts) {
        return storeLoad(file, opts);
      }
    },
    clipboardManager: {
      writeText: function (text) {
        return invoke('__clipboard_write_text', { text: String(text) }).then(function () {});
      },
      readText: function () {
        return invoke('__clipboard_read_text', {}).then(function (v) {
          return typeof v === 'string' ? v : '';
        });
      },
      readImage: function () {
        return Promise.resolve(null);
      }
    },
    event: {
      listen: function () {
        return Promise.resolve(function () {});
      }
    }
  };
})();`;
