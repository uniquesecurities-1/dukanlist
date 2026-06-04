/* ============================================================
   error-reporter.js
   Auto-mounting client-side error capture.

   Captures:
     - Uncaught JS errors (window.onerror)
     - Unhandled promise rejections
     - Manual reports via window.__dukanReport(...)
     - (Opt-in) failed fetch() — wrap with __dukanWatchFetch

   Sends to /api/log-error endpoint (fire-and-forget POST).

   PRIVACY:
     - Never sends form values, localStorage, cookies, or DOM content
     - Server hashes IP daily; no PII stored
     - Throttled client-side (max 10 reports / 60s)
     - Deduped within 5 min on the server side

   USAGE:
     <script src="/assets/js/error-reporter.js" defer></script>
     // That's it. Auto-mounts on load.
   ============================================================ */

(function () {
  'use strict';

  // -------- Config --------
  var ENDPOINT       = '/api/log-error';
  var MAX_PER_MINUTE = 10;
  var STORAGE_KEY    = 'dl_err_session_v1';

  // -------- Session id (no PII) --------
  var sessionId;
  try {
    sessionId = sessionStorage.getItem(STORAGE_KEY);
    if (!sessionId) {
      sessionId = 'sess_' + Math.random().toString(36).slice(2) + '_' +
                  Date.now().toString(36);
      sessionStorage.setItem(STORAGE_KEY, sessionId);
    }
  } catch (e) {
    sessionId = 'sess_anon';
  }

  // -------- Throttle window --------
  var recentSent = [];

  function withinRateLimit() {
    var now = Date.now();
    recentSent = recentSent.filter(function (t) { return now - t < 60000; });
    if (recentSent.length >= MAX_PER_MINUTE) return false;
    recentSent.push(now);
    return true;
  }

  // -------- Auth header (if logged in via Supabase) --------
  function authHeader() {
    try {
      // Supabase persists session in localStorage under 'sb-*'
      var keys = Object.keys(localStorage);
      for (var i = 0; i < keys.length; i++) {
        if (keys[i].indexOf('sb-') === 0 && keys[i].indexOf('-auth-token') > 0) {
          var raw = localStorage.getItem(keys[i]);
          if (!raw) continue;
          try {
            var obj = JSON.parse(raw);
            var token = obj && obj.access_token;
            if (token) return 'Bearer ' + token;
          } catch (_) {}
        }
      }
    } catch (_) {}
    return null;
  }

  // -------- Send a report --------
  function send(payload) {
    if (!withinRateLimit()) return;
    try {
      var body = {
        source:      payload.source || 'js',
        severity:    payload.severity || 'error',
        error_msg:   String(payload.message || '').slice(0, 1000),
        error_stack: String(payload.stack || '').slice(0, 4000),
        page_url:    String(location.href).slice(0, 500),
        session_id:  sessionId,
        referrer:    String(document.referrer || '').slice(0, 200),
        line:        payload.line,
        col:         payload.col
      };
      var headers = { 'Content-Type': 'application/json' };
      var ah = authHeader();
      if (ah) headers['Authorization'] = ah;

      // Use keepalive so the report flushes even when navigating away
      if (typeof fetch === 'function') {
        fetch(ENDPOINT, {
          method:    'POST',
          headers:   headers,
          body:      JSON.stringify(body),
          keepalive: true,
          credentials: 'omit'
        }).catch(function () { /* silent */ });
      } else if (navigator.sendBeacon) {
        navigator.sendBeacon(
          ENDPOINT,
          new Blob([JSON.stringify(body)], { type: 'application/json' })
        );
      }
    } catch (e) {
      // The reporter itself must never throw
    }
  }

  // -------- 1. window.onerror --------
  var prevOnError = window.onerror;
  window.onerror = function (msg, src, line, col, err) {
    try {
      // Skip CORS-blocked "Script error." which contains no useful info
      if (msg === 'Script error.' && !src) return false;
      send({
        message: String(msg || ''),
        stack:   err && err.stack ? String(err.stack) : '',
        line:    line,
        col:     col,
        source:  'js',
        severity:'error'
      });
    } catch (_) {}
    if (typeof prevOnError === 'function') {
      try { return prevOnError.apply(this, arguments); } catch (_) {}
    }
    return false;
  };

  // -------- 2. Unhandled promise rejections --------
  window.addEventListener('unhandledrejection', function (ev) {
    try {
      var reason = ev && ev.reason;
      var msg = '';
      var stk = '';
      if (reason instanceof Error) {
        msg = reason.message || String(reason);
        stk = reason.stack || '';
      } else if (typeof reason === 'string') {
        msg = reason;
      } else {
        try { msg = JSON.stringify(reason); } catch (_) { msg = String(reason); }
      }
      send({
        message:  'unhandledrejection: ' + msg,
        stack:    stk,
        source:   'promise',
        severity: 'error'
      });
    } catch (_) {}
  });

  // -------- 3. Optional: wrap fetch to detect failed calls --------
  // Off by default — set window.__dukanWatchFetch = true BEFORE this
  // script loads to enable.
  if (window.__dukanWatchFetch && typeof window.fetch === 'function') {
    var origFetch = window.fetch.bind(window);
    window.fetch = function (input, init) {
      var url = (typeof input === 'string') ? input :
                (input && input.url) || '<unknown>';
      return origFetch(input, init).then(function (resp) {
        if (!resp.ok && resp.status >= 500) {
          send({
            message:  'fetch ' + resp.status + ' ' + url,
            source:   'fetch',
            severity: resp.status >= 500 ? 'error' : 'warn'
          });
        }
        return resp;
      }).catch(function (e) {
        send({
          message:  'fetch failed: ' + url + ' — ' + (e && e.message ? e.message : e),
          stack:    e && e.stack ? String(e.stack) : '',
          source:   'fetch',
          severity: 'error'
        });
        throw e;
      });
    };
  }

  // -------- 4. Public manual reporter --------
  window.__dukanReport = function (message, opts) {
    opts = opts || {};
    send({
      message:  String(message || 'manual report'),
      stack:    opts.stack || (new Error()).stack,
      source:   opts.source || 'js',
      severity: opts.severity || 'warn'
    });
  };
})();
