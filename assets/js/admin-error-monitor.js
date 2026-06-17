/* ============================================================
   DukanList — Admin Error Monitor
   ============================================================
   Drop-in script that captures every client-side error and posts it
   to log_admin_error RPC for storage in admin_errors table.

   Captures:
     1. Uncaught JavaScript errors  (window.onerror)
     2. Unhandled promise rejections (window.onunhandledrejection)
     3. Failed fetch/RPC calls       (wrapper helpers)
     4. Manual logs                  (window.logError(msg, payload))

   Features:
     - Debounced (same error within 5 min → not re-sent)
     - Fails silently if Supabase client not available yet
     - Adds page path + user agent + URL automatically
     - Sampling: if > 50 errors in 10 min, throttle to 1/min

   Usage:
     Include in any admin/owner page BEFORE other scripts:
       <script src="/assets/js/admin-error-monitor.js"></script>

     The monitor expects a global `supabase` client to exist (created by
     each page's existing init code). If absent, errors are queued and
     flushed once the client appears.

   ============================================================ */
// AUTO-INJECT the universal admin permission gate so every page that
// already includes admin-error-monitor.js (24 pages — nearly all admin
// pages) also gets nav-hiding + page-level guard for free. Idempotent
// via a flag check.
(function(){
  if (window.__dukanGateInjected) return;
  window.__dukanGateInjected = true;
  // Skip on /admin/login.html — no gating needed (and no session yet)
  if (location.pathname.indexOf('/admin/login') === 0) return;
  var s = document.createElement('script');
  s.src = '/assets/js/admin-permission-gate.js';
  s.async = true;
  (document.head || document.documentElement).appendChild(s);
})();

(function(){
  'use strict';

  var QUEUE = [];          // pending logs while supabase client not ready
  var SEEN  = new Map();   // fingerprint → lastSentAt timestamp
  var RECENT_COUNT = 0;
  var RECENT_RESET_AT = Date.now();
  var SAMPLING_INTERVAL_MS = 600000;   // 10 min
  var SAMPLING_THRESHOLD = 50;          // > this in 10 min → throttle
  var DEBOUNCE_MS = 5 * 60 * 1000;      // same error within 5 min suppressed
  var DEBUG = false;                    // window.DukanErrorMonitor.debug to flip

  // Best-effort access to the page's supabase client. Many admin pages
  // create it as `window.supabase` or `window.sb`. We try both.
  function getClient(){
    return (window.supabase && window.supabase.from) ? window.supabase
         : (window.sb && window.sb.from)             ? window.sb
         : (window.ShopDB && window.ShopDB.client)   ? window.ShopDB.client
         : null;
  }

  function fingerprint(msg, stack){
    // Stack first 100 chars + first 80 of message — enough to dedupe
    return (String(stack || '').slice(0, 100) + '|' + String(msg || '').slice(0, 80));
  }

  function shouldDrop(fp){
    var now = Date.now();
    var lastSent = SEEN.get(fp);
    if (lastSent && (now - lastSent) < DEBOUNCE_MS) return true;

    // Sampling: if very noisy, throttle
    if ((now - RECENT_RESET_AT) > SAMPLING_INTERVAL_MS){
      RECENT_RESET_AT = now;
      RECENT_COUNT = 0;
    }
    RECENT_COUNT++;
    if (RECENT_COUNT > SAMPLING_THRESHOLD){
      // Allow one per minute after threshold
      if (lastSent && (now - lastSent) < 60000) return true;
    }
    SEEN.set(fp, now);
    return false;
  }

  function postLog(entry){
    var c = getClient();
    if (!c){
      QUEUE.push(entry);
      // Try again shortly — most pages create client within 2s
      setTimeout(flushQueue, 1500);
      return;
    }
    c.rpc('log_admin_error', {
      p_page:          entry.page,
      p_error_type:    entry.error_type,
      p_error_message: entry.error_message,
      p_error_stack:   entry.error_stack || null,
      p_url:           entry.url || null,
      p_user_agent:    entry.user_agent || null,
      p_payload:       entry.payload || null
    }).then(function(r){
      if (DEBUG){
        if (r.error) console.warn('[ErrorMonitor] log failed:', r.error);
        else         console.info('[ErrorMonitor] logged:', r.data, entry.error_message);
      }
    }).catch(function(e){
      if (DEBUG) console.warn('[ErrorMonitor] log threw:', e);
    });
  }

  function flushQueue(){
    if (!QUEUE.length) return;
    var c = getClient();
    if (!c){ setTimeout(flushQueue, 1500); return; }
    var batch = QUEUE.splice(0, QUEUE.length);
    batch.forEach(postLog);
  }

  function capture(opts){
    try {
      var entry = {
        page:          location.pathname,
        error_type:    opts.type || 'js',
        error_message: String(opts.message || 'unknown error').slice(0, 4000),
        error_stack:   opts.stack ? String(opts.stack).slice(0, 8000) : null,
        url:           location.href.slice(0, 1000),
        user_agent:    navigator.userAgent.slice(0, 500),
        payload:       opts.payload || null
      };
      var fp = fingerprint(entry.error_message, entry.error_stack);
      if (shouldDrop(fp)){
        if (DEBUG) console.info('[ErrorMonitor] suppressed (debounce):', entry.error_message);
        return;
      }
      postLog(entry);
    } catch(_){
      // never let the monitor itself throw
    }
  }

  // -------- Global handler: uncaught JS errors --------
  window.addEventListener('error', function(ev){
    // Filter out cross-origin script errors (browser hides details — useless)
    var msg = ev.message || (ev.error && ev.error.message) || '';
    if (msg === 'Script error.' && !ev.filename) return;

    capture({
      type:    'js',
      message: msg,
      stack:   ev.error && ev.error.stack,
      payload: {
        filename: ev.filename || null,
        lineno:   ev.lineno   || null,
        colno:    ev.colno    || null
      }
    });
  }, true);

  // -------- Global handler: unhandled promise rejections --------
  window.addEventListener('unhandledrejection', function(ev){
    var reason = ev.reason;
    var msg = (reason && (reason.message || String(reason))) || 'unhandled rejection';
    var stack = reason && reason.stack;
    capture({
      type:    'promise',
      message: msg,
      stack:   stack,
      payload: { reason_type: typeof reason }
    });
  });

  // -------- Public API for manual logging --------
  window.DukanErrorMonitor = {
    log: function(msg, payload){
      capture({ type: 'manual', message: String(msg || ''), payload: payload || null });
    },
    logRpc: function(rpcName, error, payload){
      capture({
        type: 'rpc',
        message: '[RPC ' + rpcName + '] ' + (error.message || error),
        stack: error.stack || null,
        payload: Object.assign({ rpc: rpcName, code: error.code, details: error.details, hint: error.hint }, payload || {})
      });
    },
    logFetch: function(url, status, body){
      capture({
        type: 'fetch',
        message: '[fetch ' + status + '] ' + url,
        payload: { url: url, status: status, body: (body || '').slice(0, 1000) }
      });
    },
    set debug(v){ DEBUG = !!v; },
    get debug(){ return DEBUG; },
    flushQueue: flushQueue,
    seen: SEEN
  };

  // Convenience shorthand
  window.logError = window.DukanErrorMonitor.log;

  // Flush whenever supabase client appears (poll briefly during page init)
  var pollAttempts = 0;
  var pollId = setInterval(function(){
    pollAttempts++;
    if (getClient()){ clearInterval(pollId); flushQueue(); }
    else if (pollAttempts > 30){ clearInterval(pollId); } // give up after 45s
  }, 1500);
})();
