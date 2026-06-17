/* ============================================================
   admin-common.js — shared admin helpers for DukanList
   ------------------------------------------------------------
   Provides:
     1. AdminCommon.requireAdmin()  — auth + admin role check
     2. AdminCommon.renderNav(currentSlug) — unified topbar
     3. AdminCommon.fmtDate(d, opts) — consistent date formatter
     4. AdminCommon.dangerConfirm({title, body, requiredText, reasonRequired})
        — modal with required-text + optional reason field
     5. AdminCommon.toast(msg, isErr) — non-blocking toast
     6. AdminCommon.spinner(targetEl, msg) — loading skeleton helper
   ============================================================ */
(function(global){
  'use strict';

  // ============================================================
  // 1. AUTH + ADMIN ROLE CHECK
  // ============================================================
  async function requireAdmin(){
    if (!global.ShopDB){
      console.error('[admin-common] ShopDB not loaded');
      location.href = '/admin/login.html';
      return null;
    }
    const user = await ShopDB.requireAuth('/admin/login.html');
    if (!user) return null;
    try {
      const c = ShopDB.client;
      const r = await c.rpc('is_admin');
      const isAdmin = r && r.data === true;
      if (!isAdmin){
        toast('Access denied — not an admin account', true);
        setTimeout(() => { location.href = '/admin/login.html'; }, 1500);
        return null;
      }
    } catch(e){
      console.warn('[admin-common] is_admin check failed (non-fatal):', e);
    }
    return user;
  }

  // ============================================================
  // 2. UNIFIED NAV — replaces existing <header class="topbar">
  // ============================================================
  const NAV_ITEMS = [
    { slug: 'dashboard',        href: '/admin/dashboard',              label: '📊 Dashboard' },
    { slug: 'moderation',       href: '/admin/moderation',             label: '⚖️ Moderation', badgeId: 'navPendingBadge' },
    { slug: 'bulk-upload',      href: '/admin/bulk-upload',            label: '📥 Bulk Add' },
    { slug: 'announcements',    href: '/admin/announcements',          label: '📣 News' },
    { slug: 'featured',         href: '/admin/featured.html',          label: '⭐ Featured' },
    { slug: 'deals',            href: '/admin/deals.html',             label: '🎁 Deals' },
    { slug: 'activity',         href: '/admin/activity.html',          label: '📋 Activity' },
    { slug: 'suspicious',       href: '/admin/suspicious.html',        label: '🚨 Suspicious', badgeId: 'navSusBadge' },
    { slug: 'pucho-moderation', href: '/admin/pucho-moderation.html',  label: '💬 Pucho' },
    { slug: 'reviews',          href: '/admin/reviews.html',           label: '⭐ Reviews' },
    { slug: 'categories',       href: '/admin/categories.html',        label: '🏷️ Categories' },
    { slug: 'cities',           href: '/admin/cities.html',            label: '📍 Cities' },
    { slug: 'settings',         href: '/admin/settings.html',          label: '⚙️ Settings' },
    { slug: 'admins',           href: '/admin/admins',                 label: '👥 Admins',  superAdminOnly: true },
    { slug: 'test-cleanup',     href: '/admin/test-cleanup',           label: '🧹 Cleanup', superAdminOnly: true }
  ];

  function renderNav(currentSlug){
    const links = NAV_ITEMS.map(item => {
      const isActive = item.slug === currentSlug;
      const visibility = item.superAdminOnly ? ' data-super-only="1" style="display:none"' : '';
      const badge = item.badgeId
        ? ` <span id="${item.badgeId}" style="display:none;background:#F59E0B;color:#fff;font-size:10px;font-weight:800;padding:2px 6px;border-radius:99px;margin-left:4px"></span>`
        : '';
      return `<a href="${item.href}"${visibility}${isActive ? ' class="active"' : ''}>${item.label}${badge}</a>`;
    }).join('');

    const html = `
      <div class="brand" style="display:flex;align-items:center;gap:10px;font-weight:800;font-size:16px">
        <span>🛡️</span>
        <span>Dukan<em style="font-style:normal;color:#1E3A8A">List</em></span>
        <span class="badge" style="font-size:10px;font-weight:700;background:#1E3A8A;color:white;padding:2px 7px;border-radius:5px;letter-spacing:0.5px">ADMIN</span>
      </div>
      <nav class="nav" style="display:flex;gap:6px;align-items:center;flex-wrap:wrap">
        ${links}
        <a href="/" target="_blank">🌐 Site</a>
        <span class="logout" onclick="AdminCommon.logout()" style="font-size:12px;color:#94a3b8;cursor:pointer;padding:6px 10px;border-radius:6px">⎋ Logout</span>
      </nav>`;

    // Try to replace existing topbar; otherwise prepend to body
    const existing = document.querySelector('header.topbar');
    if (existing){
      existing.innerHTML = html;
    } else {
      const h = document.createElement('header');
      h.className = 'topbar';
      h.style.cssText = 'background:#0F172A;color:#f1f5f9;padding:12px 20px;display:flex;align-items:center;justify-content:space-between;position:sticky;top:0;z-index:100;gap:14px;flex-wrap:wrap';
      h.innerHTML = html;
      document.body.insertBefore(h, document.body.firstChild);
    }

    // Reveal super-admin items if applicable
    revealSuperAdminItems().catch(() => {});
  }

  async function revealSuperAdminItems(){
    if (!global.ShopDB || !ShopDB.client) return;
    try {
      const r = await ShopDB.client.rpc('get_admin_scope');
      const scope = (r && r.data) || {};
      const isSuper = scope.role === 'super_admin';
      if (isSuper){
        document.querySelectorAll('[data-super-only]').forEach(el => {
          el.style.display = '';
        });
      }
      // After we know role, also apply per-page permission gating to
      // the nav items so a regular admin doesn't see (or click into)
      // pages they're not allowed to access.
      applyPermissionGatingToNav().catch(() => {});
    } catch(_){}
  }

  // ============================================================
  // PERMISSION SYSTEM (db/158) — granular per-page access control
  // ============================================================
  // my_admin_permissions() returns the effective permission set.
  // Super admins get every key=TRUE automatically. Regular admins
  // get only what was granted via the Admins UI checkboxes.
  let _permCache = null;
  let _permFetching = null;

  async function getPermissions(force){
    if (_permCache && !force) return _permCache;
    if (_permFetching) return _permFetching;
    _permFetching = (async () => {
      try {
        if (!global.ShopDB || !ShopDB.client) return {};
        const r = await ShopDB.client.rpc('my_admin_permissions');
        const data = (r && r.data) || {};
        _permCache = data;
        return data;
      } catch(_){
        // RPC missing (db/158 not deployed) → silently fall back to
        // "everything granted" so admins aren't locked out by a
        // half-applied migration.
        return { is_admin: true, is_super: true, _fallback: true };
      } finally {
        _permFetching = null;
      }
    })();
    return _permFetching;
  }

  // Mapping from nav-slug → permission key. Slugs use dashes, keys
  // use underscores (matching DB JSONB key shape).
  const SLUG_TO_PERM_KEY = {
    'dashboard':           null,                  // always granted
    'moderation':          'moderation',
    'bulk-upload':         'bulk_upload',
    'announcements':       'announcements',
    'featured':            'featured',
    'deals':               'deals',
    'activity':            'activity',
    'suspicious':          'suspicious',
    'pucho-moderation':    'pucho_moderation',
    'reviews':             'reviews',
    'categories':          'categories',
    'cities':              'cities',
    'settings':            'settings',
    'professional-verify': 'professional_verify',
    'pro-legal-notify':    'pro_legal_notify',
    'health':              'health',
    'monitoring':          'monitoring',
    'duplicates':          'duplicates',
    'incomplete-shops':    'incomplete_shops',
    'broadcast':           'broadcast',
    'spotlight':           'spotlight',
    'verification':        'verification',
    'quick-approve':       'quick_approve',
    'admins':              null,                  // superAdminOnly already gates
    'test-cleanup':        null                   // superAdminOnly already gates
  };

  async function applyPermissionGatingToNav(){
    const perms = await getPermissions();
    // Super admins bypass everything
    if (perms.is_super || perms._fallback) return;

    NAV_ITEMS.forEach(item => {
      const permKey = SLUG_TO_PERM_KEY[item.slug];
      if (permKey == null) return;  // always-on item
      if (perms[permKey] === true) return;  // granted — leave visible
      // Not granted — hide the nav link
      const link = document.querySelector(`a[href="${item.href}"]`);
      if (link) link.style.display = 'none';
    });
  }

  // Page-level guard. Drop at top of any admin page's init() like:
  //   await AdminCommon.requirePermission('moderation');
  // Redirects to dashboard if the current user lacks the permission.
  async function requirePermission(permKey){
    const perms = await getPermissions();
    if (perms.is_super || perms._fallback) return true;
    if (perms[permKey] === true) return true;
    // Denied — bounce to dashboard with a toast
    toast('Access denied — your admin account does not have this permission.', true);
    setTimeout(() => { location.href = '/admin/dashboard.html'; }, 1500);
    return false;
  }

  function logout(){
    if (global.ShopDB && ShopDB.signOut){
      ShopDB.signOut();
    } else {
      location.href = '/admin/login.html';
    }
  }

  // ============================================================
  // 3. CONSISTENT DATE FORMATTER
  // ============================================================
  function fmtDate(input, opts){
    if (!input) return '—';
    const d = (input instanceof Date) ? input : new Date(input);
    if (isNaN(d.getTime())) return '—';
    const style = (opts && opts.style) || 'short'; // 'short', 'long', 'time', 'datetime', 'rel'
    if (style === 'rel'){
      const diffMs = Date.now() - d.getTime();
      const diffSec = Math.floor(diffMs / 1000);
      if (diffSec < 60) return 'just now';
      if (diffSec < 3600) return Math.floor(diffSec / 60) + ' min ago';
      if (diffSec < 86400) return Math.floor(diffSec / 3600) + 'h ago';
      if (diffSec < 7 * 86400) return Math.floor(diffSec / 86400) + 'd ago';
      return d.toLocaleDateString('en-IN', { day:'numeric', month:'short', year:'numeric' });
    }
    const optsMap = {
      'short':    { day:'numeric', month:'short', year:'2-digit' },
      'long':     { day:'numeric', month:'long', year:'numeric' },
      'time':     { hour:'numeric', minute:'2-digit', hour12:true },
      'datetime': { day:'numeric', month:'short', year:'2-digit', hour:'numeric', minute:'2-digit', hour12:true }
    };
    return d.toLocaleString('en-IN', optsMap[style] || optsMap.short);
  }

  // ============================================================
  // 4. DANGER CONFIRM MODAL (replaces window.prompt)
  // ============================================================
  function dangerConfirm(cfg){
    return new Promise(resolve => {
      const id = 'dcModal_' + Date.now();
      const requiredText = cfg.requiredText || 'DELETE';
      const reasonReq   = !!cfg.reasonRequired;
      const html = `
        <div id="${id}" style="position:fixed;inset:0;background:rgba(15,23,42,.65);z-index:9999;display:flex;align-items:center;justify-content:center;padding:20px;backdrop-filter:blur(2px)">
          <div style="background:#fff;border-radius:14px;max-width:480px;width:100%;padding:24px;box-shadow:0 24px 60px rgba(0,0,0,.3);border-top:5px solid #DC2626">
            <h2 style="margin:0 0 8px;font-size:18px;color:#991B1B;font-weight:800">⚠️ ${escapeHtml(cfg.title || 'Confirm dangerous action')}</h2>
            <p style="color:#475569;font-size:14px;line-height:1.55;margin:0 0 14px">${cfg.body || 'This action cannot be undone.'}</p>
            ${reasonReq ? `
              <label style="display:block;font-size:12px;font-weight:700;color:#334155;text-transform:uppercase;letter-spacing:.04em;margin-bottom:5px">Reason for action *</label>
              <textarea id="${id}_reason" placeholder="Why are you doing this? (audit log)" style="width:100%;min-height:60px;padding:9px 11px;border:1.5px solid #CBD5E1;border-radius:8px;font-size:13px;font-family:inherit;margin-bottom:14px;resize:vertical"></textarea>
            ` : ''}
            <label style="display:block;font-size:12px;font-weight:700;color:#334155;text-transform:uppercase;letter-spacing:.04em;margin-bottom:5px">Type <code style="background:#FEE2E2;padding:2px 6px;border-radius:4px;color:#991B1B;font-weight:800">${escapeHtml(requiredText)}</code> to confirm</label>
            <input type="text" id="${id}_input" autocomplete="off" style="width:100%;padding:10px 12px;border:1.5px solid #CBD5E1;border-radius:8px;font-size:14px;font-family:inherit;margin-bottom:16px;letter-spacing:.05em">
            <div style="display:flex;gap:8px;justify-content:flex-end">
              <button id="${id}_cancel" style="background:#fff;color:#0F172A;border:1.5px solid #CBD5E1;padding:9px 18px;border-radius:8px;font-weight:700;font-size:13px;cursor:pointer;font-family:inherit">Cancel</button>
              <button id="${id}_confirm" disabled style="background:#DC2626;color:#fff;border:0;padding:9px 18px;border-radius:8px;font-weight:800;font-size:13px;cursor:not-allowed;opacity:.5;font-family:inherit">${escapeHtml(cfg.confirmLabel || 'Confirm Delete')}</button>
            </div>
          </div>
        </div>`;
      const wrap = document.createElement('div');
      wrap.innerHTML = html;
      document.body.appendChild(wrap.firstElementChild);
      const modal    = document.getElementById(id);
      const input    = document.getElementById(id + '_input');
      const reason   = document.getElementById(id + '_reason');
      const okBtn    = document.getElementById(id + '_confirm');
      const cancelBtn= document.getElementById(id + '_cancel');
      function close(result){ modal.remove(); resolve(result); }
      function checkValid(){
        const textOk = input.value.trim() === requiredText;
        const reasonOk = !reasonReq || (reason && reason.value.trim().length >= 5);
        const ok = textOk && reasonOk;
        okBtn.disabled = !ok;
        okBtn.style.opacity = ok ? '1' : '.5';
        okBtn.style.cursor = ok ? 'pointer' : 'not-allowed';
      }
      input.addEventListener('input', checkValid);
      if (reason) reason.addEventListener('input', checkValid);
      okBtn.addEventListener('click', () => {
        if (okBtn.disabled) return;
        close({ confirmed:true, reason: reason ? reason.value.trim() : '' });
      });
      cancelBtn.addEventListener('click', () => close({ confirmed:false }));
      modal.addEventListener('click', e => { if (e.target === modal) close({ confirmed:false }); });
      input.focus();
    });
  }

  // ============================================================
  // 5. TOAST + 6. SPINNER
  // ============================================================
  let _toastEl = null;
  function toast(msg, isErr){
    if (!_toastEl){
      _toastEl = document.createElement('div');
      _toastEl.style.cssText = 'position:fixed;bottom:24px;left:50%;transform:translateX(-50%);background:#0F172A;color:#fff;padding:11px 18px;border-radius:10px;font-size:14px;font-weight:600;z-index:10000;box-shadow:0 8px 24px rgba(0,0,0,.25);opacity:0;transition:opacity .2s;max-width:80%;text-align:center';
      document.body.appendChild(_toastEl);
    }
    _toastEl.textContent = msg;
    _toastEl.style.background = isErr ? '#DC2626' : '#0F172A';
    _toastEl.style.opacity = '1';
    clearTimeout(_toastEl._timer);
    _toastEl._timer = setTimeout(() => { _toastEl.style.opacity = '0'; }, 3200);
  }

  function spinner(targetEl, msg){
    if (!targetEl) return;
    targetEl.innerHTML = `
      <div style="display:flex;flex-direction:column;align-items:center;gap:10px;padding:36px 12px;color:#64748b">
        <div style="width:32px;height:32px;border:3px solid #E2E8F0;border-top-color:#1E3A8A;border-radius:50%;animation:dl-spin .8s linear infinite"></div>
        <div style="font-size:13px;font-weight:600">${escapeHtml(msg || 'Loading…')}</div>
      </div>
      <style>@keyframes dl-spin{to{transform:rotate(360deg)}}</style>`;
  }

  function escapeHtml(s){
    return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  }

  // ============================================================
  // PUBLIC API
  // ============================================================
  global.AdminCommon = {
    requireAdmin,
    renderNav,
    revealSuperAdminItems,
    fmtDate,
    dangerConfirm,
    toast,
    spinner,
    logout,
    escapeHtml,
    // db/158 permission helpers
    getPermissions,
    requirePermission,
    applyPermissionGatingToNav
  };
})(window);
