/* ============================================================
   DukanList — Admin Permission Gate (universal)
   ============================================================
   Drop-in script that runs on EVERY admin page to enforce the
   db/158 page-level permission system. Two jobs:

   1. NAV GATING — finds every `<a href="/admin/...">` link on the
      page (regardless of nav HTML markup style) and hides those
      the current admin lacks permission for.

   2. PAGE-LEVEL GUARD — reads location.pathname, looks up the
      required permission key, and redirects to /admin/dashboard.html
      if the current user doesn't have it. Prevents direct-URL access
      bypass.

   Super admins (is_super=true from my_admin_permissions()) skip
   both checks — god mode is preserved.

   Graceful fallback: if my_admin_permissions() RPC fails or doesn't
   exist yet, neither gating nor guard runs (avoid lockout).

   This script is auto-injected by admin-error-monitor.js so it ships
   to every admin page that already loads the error monitor. For pages
   that don't, include directly:
     <script src="/assets/js/admin-permission-gate.js"></script>
   ============================================================ */
(function(){
  'use strict';

  // ============================================================
  // Map admin URL → permission key.
  // null = always allowed (Dashboard, logout, public site, login)
  // '__super_only__' = only super admin can access (hidden + bounced)
  // string = the key to look up in my_admin_permissions() output
  // ============================================================
  var HREF_TO_PERM = {
    '/admin/dashboard':           null,
    '/admin/login':               null,
    '/admin/moderation':          'moderation',
    '/admin/quick-approve':       'quick_approve',
    '/admin/incomplete-shops':    'incomplete_shops',
    '/admin/duplicates':          'duplicates',
    '/admin/suspicious':          'suspicious',
    '/admin/verification':        'verification',
    '/admin/reviews':             'reviews',
    '/admin/pucho-moderation':    'pucho_moderation',
    '/admin/professional-verify': 'professional_verify',
    '/admin/pro-legal-notify':    'pro_legal_notify',
    '/admin/bulk-upload':         'bulk_upload',
    '/admin/featured':            'featured',
    '/admin/spotlight':           'spotlight',
    '/admin/deals':               'deals',
    '/admin/announcements':       'announcements',
    '/admin/broadcast':           'broadcast',
    '/admin/categories':          'categories',
    '/admin/cities':              'cities',
    '/admin/activity':            'activity',
    '/admin/health':              'health',
    '/admin/monitoring':          'monitoring',
    '/admin/settings':            'settings',
    '/admin/admins':              '__super_only__',
    '/admin/test-cleanup':        '__super_only__',
    // Shop edit page — gate behind 'moderation' since editing a
    // business is essentially a moderation action.
    '/admin/shop':                'moderation'
  };

  // Normalise an href or pathname for lookup:
  //   '/admin/moderation.html?x=1' → '/admin/moderation'
  function normaliseHref(h){
    if (!h) return '';
    return String(h)
      .replace(/\.html$/i, '')
      .replace(/[?#].*$/, '')
      .replace(/\/+$/, '');
  }

  // Resolve the supabase client. Pages use either window.ShopDB or
  // window.supabase / window.sb depending on how supabase-init.js ran.
  function getClient(){
    if (window.ShopDB && window.ShopDB.client) return window.ShopDB.client;
    if (window.supabase && window.supabase.rpc) return window.supabase;
    if (window.sb && window.sb.rpc) return window.sb;
    return null;
  }

  // Wait up to ~3s for a client + auth session to be ready.
  // We need an authenticated session for my_admin_permissions() to
  // return the admin's row — without it the RPC returns is_admin=false
  // and would incorrectly bounce the user.
  function waitForReadyClient(){
    return new Promise(function(resolve){
      var attempts = 0;
      var maxAttempts = 30;  // 30 × 100ms = 3 sec
      var iv = setInterval(function(){
        attempts++;
        var c = getClient();
        if (c){
          // Also check we have a session — auth.uid() must work for RPC
          var s = c.auth && c.auth.getSession ? c.auth.getSession() : Promise.resolve(null);
          Promise.resolve(s).then(function(res){
            if (res && res.data && res.data.session){
              clearInterval(iv);
              resolve(c);
            } else if (attempts >= maxAttempts){
              clearInterval(iv);
              resolve(null);
            }
          }).catch(function(){
            if (attempts >= maxAttempts){ clearInterval(iv); resolve(null); }
          });
        } else if (attempts >= maxAttempts){
          clearInterval(iv);
          resolve(null);
        }
      }, 100);
    });
  }

  async function loadPerms(){
    var c = await waitForReadyClient();
    if (!c) return null;
    try {
      var r = await c.rpc('my_admin_permissions');
      if (r && r.data) return r.data;
    } catch(_){}
    return null;
  }

  function hideNavLinks(perms){
    if (!perms || perms.is_super) return;
    // Scope to common nav containers AND fall back to any /admin/ link.
    var anchors = document.querySelectorAll('a[href^="/admin/"]');
    anchors.forEach(function(a){
      var href = a.getAttribute('href') || '';
      var base = normaliseHref(href);
      if (!(base in HREF_TO_PERM)) return;  // unknown — leave visible
      var key = HREF_TO_PERM[base];
      if (key === null) return;             // always visible
      if (key === '__super_only__'){
        a.style.display = 'none';
        return;
      }
      if (perms[key] !== true){
        a.style.display = 'none';
      }
    });
  }

  function getCurrentPageKey(){
    var path = normaliseHref(location.pathname);
    return path in HREF_TO_PERM ? HREF_TO_PERM[path] : undefined;
  }

  function bounce(msg){
    try {
      // Tiny toast (no alert popup — non-blocking + dismisses quickly)
      var t = document.createElement('div');
      t.style.cssText =
        'position:fixed;top:20px;left:50%;transform:translateX(-50%);'+
        'background:#DC2626;color:#fff;padding:12px 20px;border-radius:10px;'+
        'font-family:-apple-system,sans-serif;font-weight:700;font-size:14px;'+
        'box-shadow:0 8px 24px rgba(220,38,38,.4);z-index:99999;'+
        'max-width:320px;text-align:center;line-height:1.4';
      t.textContent = msg || 'Access denied — redirecting to dashboard.';
      (document.body || document.documentElement).appendChild(t);
    } catch(_){}
    setTimeout(function(){
      location.replace('/admin/dashboard.html');
    }, 1200);
  }

  async function gateCurrentPage(perms){
    if (!perms || perms.is_super) return;
    var key = getCurrentPageKey();
    if (key === null) return;          // always-allowed page
    if (key === undefined) return;     // unknown page — don't block
    if (key === '__super_only__'){
      bounce('🛡 This page is super-admin only.');
      return true;
    }
    if (perms[key] !== true){
      bounce('🛡 You do not have permission for this page.');
      return true;
    }
    return false;
  }

  async function run(){
    // Cache result across navigations of the same page session.
    if (window.__dukanPermGateRan) return;
    window.__dukanPermGateRan = true;

    var perms = await loadPerms();
    if (!perms) return;  // RPC failed → don't gate (avoid lockout)

    // CRITICAL ORDER: page-level guard runs FIRST. If it triggers a
    // bounce, no point hiding nav links (we're leaving anyway).
    var bounced = await gateCurrentPage(perms);
    if (bounced) return;

    hideNavLinks(perms);

    // If nav HTML is injected later (e.g. AdminCommon.renderNav runs
    // post-DOM), re-run gating once on a short delay so dynamically
    // injected links also get hidden.
    setTimeout(function(){ hideNavLinks(perms); }, 800);
  }

  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', run);
  } else {
    run();
  }

  // Expose for manual re-application after late nav injection
  window.DukanPermGate = {
    rerun: async function(){
      var perms = await loadPerms();
      if (perms) hideNavLinks(perms);
    }
  };
})();
