/* ============================================================
   impersonation-banner.js — Admin Impersonation Indicator
   ============================================================
   Triggers when admin logs in as another user via magic link.
   Detects ?dukan_impersonating=1&dukan_impersonating_by=<email>
   either on the URL or in localStorage (persists across page nav).

   Renders a sticky red banner at the top with:
     • Clear "ADMIN IMPERSONATION MODE" text
     • Who is impersonating whom
     • Exit Impersonation button (logs out + returns to admin)
============================================================ */
(function(){
  'use strict';

  var KEY = 'dukan_impersonating_meta';

  // Step 1 — detect from URL on first load and persist to localStorage
  try {
    var url = new URL(window.location.href);
    var flag = url.searchParams.get('dukan_impersonating');
    var by   = url.searchParams.get('dukan_impersonating_by');
    if (flag === '1' && by){
      var meta = { by: by, started_at: Date.now() };
      try { localStorage.setItem(KEY, JSON.stringify(meta)); } catch(_){}
      // Clean URL so the params don't leak into screenshots/shares
      url.searchParams.delete('dukan_impersonating');
      url.searchParams.delete('dukan_impersonating_by');
      // also remove anything Supabase might have appended via hash
      var newSearch = url.searchParams.toString();
      var clean = url.pathname + (newSearch ? '?' + newSearch : '') + (url.hash || '');
      try { history.replaceState(null, '', clean); } catch(_){}
    }
  } catch(_){}

  // Step 2 — read persisted state
  var meta = null;
  try {
    var raw = localStorage.getItem(KEY);
    if (raw) meta = JSON.parse(raw);
  } catch(_){}

  if (!meta || !meta.by) return;

  // Step 3 — inject the banner
  function injectBanner(){
    if (document.getElementById('dukanImpersonationBanner')) return;
    var bar = document.createElement('div');
    bar.id = 'dukanImpersonationBanner';
    bar.style.cssText = [
      'position:sticky','top:0','left:0','right:0','width:100%',
      'z-index:99999',
      'background:linear-gradient(90deg,#7F1D1D 0%,#DC2626 50%,#7F1D1D 100%)',
      'color:#fff','padding:10px 14px','font-weight:700','font-size:.86rem',
      'box-shadow:0 4px 16px rgba(127,29,29,.35)',
      'display:flex','align-items:center','justify-content:space-between',
      'gap:14px','flex-wrap:wrap','font-family:inherit',
      'animation:dukanImpPulse 2s ease-in-out infinite'
    ].join(';');

    var msgEsc = (meta.by || '').replace(/[&<>"']/g,function(c){return ({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"})[c];});
    bar.innerHTML =
      '<div style="display:flex;align-items:center;gap:10px;min-width:0;flex:1">'
      + '<span style="display:inline-flex;align-items:center;justify-content:center;width:26px;height:26px;border-radius:50%;background:rgba(255,255,255,.18);font-size:14px;flex-shrink:0">⚠</span>'
      + '<span style="min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">ADMIN IMPERSONATION MODE — logged in as this user by <b>' + msgEsc + '</b>. Every action is logged.</span>'
      + '</div>'
      + '<button type="button" id="dukanImpExitBtn" '
      + 'style="background:#fff;color:#7F1D1D;border:none;padding:7px 14px;border-radius:99px;font-weight:800;font-size:.78rem;cursor:pointer;font-family:inherit;flex-shrink:0">'
      + '✖ Exit Impersonation</button>';

    // Add keyframes for the subtle pulse
    if (!document.getElementById('dukanImpStyles')){
      var s = document.createElement('style');
      s.id = 'dukanImpStyles';
      s.textContent = '@keyframes dukanImpPulse{0%,100%{filter:brightness(1)}50%{filter:brightness(1.12)}}';
      document.head.appendChild(s);
    }

    document.body.insertBefore(bar, document.body.firstChild);

    document.getElementById('dukanImpExitBtn').addEventListener('click', exitImpersonation);
  }

  function exitImpersonation(){
    if (!confirm('Exit impersonation and sign out of this user account?')) return;
    try { localStorage.removeItem(KEY); } catch(_){}
    // Sign out the impersonated session, then redirect to admin
    try {
      if (window.ShopDB && window.ShopDB.client && window.ShopDB.client.auth){
        window.ShopDB.client.auth.signOut().finally(function(){
          window.location.href = '/admin/dashboard.html';
        });
      } else {
        window.location.href = '/admin/dashboard.html';
      }
    } catch(_){
      window.location.href = '/admin/dashboard.html';
    }
  }

  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', injectBanner);
  } else {
    injectBanner();
  }

  // Expose helper for manual exit (used by panel logout flows)
  window.DukanImpersonation = {
    isActive: function(){ return !!meta; },
    by: meta ? meta.by : null,
    exit: exitImpersonation
  };
})();
