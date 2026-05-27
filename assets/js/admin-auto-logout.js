/* ============================================================
   admin-auto-logout.js
   Auto-logout the admin after N minutes of inactivity.
   ------------------------------------------------------------
   Default idle timeout: 60 minutes
   Warning shown at:     58 minutes (last 2 min)

   Override on a per-page basis BEFORE this script:
     window.ADMIN_AUTO_LOGOUT_MINS = 30;   // 30-min idle
     window.ADMIN_AUTO_LOGOUT_WARN_MINS = 3; // warn 3 min before

   Activity = mousemove / keydown / click / scroll / touchstart
   Multi-tab safe: any tab's activity resets all tabs (localStorage).
   Independent of Supabase session expiry — clean signOut + redirect.
============================================================ */
(function(){
  'use strict';
  const KEY        = 'dl_admin_last_activity';
  const IDLE_MINS  = (window.ADMIN_AUTO_LOGOUT_MINS  || 60);
  const WARN_MINS  = (window.ADMIN_AUTO_LOGOUT_WARN_MINS || 2);
  const IDLE_MS    = IDLE_MINS * 60 * 1000;
  const WARN_AT_MS = (IDLE_MINS - WARN_MINS) * 60 * 1000;
  const CHECK_MS   = 30 * 1000;     // background check interval
  const THROTTLE_MS = 10 * 1000;    // don't write to localStorage more than every 10s

  let lastWrite = 0;
  let signingOut = false;

  function now(){ return Date.now(); }

  function touch(){
    const n = now();
    try { localStorage.setItem(KEY, String(n)); } catch(_){}
  }

  // Throttled activity handler
  function onActivity(){
    const n = now();
    if (n - lastWrite >= THROTTLE_MS) {
      lastWrite = n;
      touch();
      hideWarning();
    }
  }

  ['mousemove','keydown','click','scroll','touchstart'].forEach(ev => {
    document.addEventListener(ev, onActivity, { passive: true, capture: true });
  });

  // Initial timestamp on first load (resets on every page nav within admin)
  touch();
  lastWrite = now();

  // ====== Warning banner ======
  function ensureBanner(){
    let b = document.getElementById('adminAutoLogoutBanner');
    if (b) return b;
    b = document.createElement('div');
    b.id = 'adminAutoLogoutBanner';
    b.style.cssText = [
      'position:fixed','top:0','left:0','right:0','z-index:2147483647',
      'background:linear-gradient(135deg,#FEF3C7,#FDE68A)',
      'border-bottom:2px solid #F59E0B',
      'padding:10px 16px',
      'display:flex','align-items:center','justify-content:center',
      'gap:14px','flex-wrap:wrap',
      'font-family:"Plus Jakarta Sans","Manrope",-apple-system,sans-serif',
      'font-weight:700','color:#92400E','font-size:.9rem',
      'box-shadow:0 4px 12px rgba(0,0,0,.08)'
    ].join(';');
    b.innerHTML =
      '<span>⏱️ Auto-logout in <b id="ablSecs">--</b>s due to inactivity — move mouse or click to stay</span>' +
      '<button id="ablStay" type="button" style="background:#92400E;color:#fff;border:none;padding:6px 16px;border-radius:99px;font-weight:800;cursor:pointer;font-family:inherit;font-size:.84rem">✓ Stay logged in</button>' +
      '<button id="ablOut" type="button" style="background:#fff;color:#92400E;border:1.5px solid #F59E0B;padding:6px 14px;border-radius:99px;font-weight:700;cursor:pointer;font-family:inherit;font-size:.78rem">Logout now</button>';
    document.body.appendChild(b);
    b.querySelector('#ablStay').onclick = function(){ touch(); hideWarning(); };
    b.querySelector('#ablOut').onclick  = function(){ doLogout(); };
    return b;
  }
  function showWarning(secsLeft){
    const b = ensureBanner();
    const el = b.querySelector('#ablSecs');
    if (el) el.textContent = String(secsLeft);
  }
  function hideWarning(){
    const b = document.getElementById('adminAutoLogoutBanner');
    if (b) b.remove();
  }

  // ====== Force logout ======
  async function doLogout(){
    if (signingOut) return;
    signingOut = true;
    hideWarning();
    try {
      if (window.ShopDB && window.ShopDB.client && window.ShopDB.client.auth) {
        await window.ShopDB.client.auth.signOut();
      }
    } catch(_){}
    try { localStorage.removeItem(KEY); } catch(_){}
    // Use replace so user can't back-navigate into admin
    window.location.replace('/admin/login.html?reason=auto_logout');
  }

  // ====== Background check ======
  setInterval(function(){
    if (signingOut) return;
    let last = 0;
    try { last = parseInt(localStorage.getItem(KEY) || '0', 10); } catch(_){}
    if (!last) { touch(); return; }
    const elapsed = now() - last;
    if (elapsed >= IDLE_MS) {
      doLogout();
    } else if (elapsed >= WARN_AT_MS) {
      const secsLeft = Math.max(1, Math.ceil((IDLE_MS - elapsed) / 1000));
      showWarning(secsLeft);
    } else {
      hideWarning();
    }
  }, CHECK_MS);

  // Cross-tab sync — if another tab updates KEY, hide our warning
  window.addEventListener('storage', function(e){
    if (e.key === KEY) hideWarning();
  });

  // Show a brief log so admins know it's active
  try {
    console.info('[admin-auto-logout] active — idle:', IDLE_MINS, 'min, warn at:', IDLE_MINS - WARN_MINS, 'min');
  } catch(_){}
})();
