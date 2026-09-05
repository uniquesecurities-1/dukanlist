/* ============================================================
   owner-notifications.js
   Shared notification bell widget for shopkeeper panel pages.
   Auto-mounts when included — looks for a Supabase client at
   window.c (the panel convention) and a logged-in session.
   ============================================================
   Behaviour:
     - Injects a bell button in the panel topbar (top-right).
     - Calls RPC get_owner_notifications() on load.
     - Shows red badge with unread count.
     - Click → dropdown panel with notification list.
     - Each item is clickable → navigates to .href .
     - Mark-as-seen tracking via localStorage (zero DB).
     - Refreshes every 60 seconds while page is open.
   ============================================================ */

(function() {
  'use strict';

  // Defer until DOM ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  function init() {
    // v218 FIX: window.c was NEVER set anywhere in the codebase, so this
    // script has been dead on all 10 pages since it shipped. The actual
    // client lives at ShopDB.client (supabase-init.js). We now adopt it
    // into window.c so the rest of this file works unchanged.
    var tries = 0;
    var poll = setInterval(function() {
      tries++;
      if (!window.c && window.ShopDB && window.ShopDB.client) {
        window.c = window.ShopDB.client;
      }
      if (window.c && window.c.auth) {
        clearInterval(poll);
        boot();
      } else if (tries > 30) {  // ~6 seconds
        clearInterval(poll);
      }
    }, 200);
  }

  function boot() {
    window.c.auth.getSession().then(function(res) {
      if (!res || !res.data || !res.data.session) return;
      mountBell();
      refresh();
      setInterval(refresh, 60000);  // every 60s
    }).catch(function() { /* silent */ });
  }

  var bellRoot = null;
  var listRoot = null;
  var badgeEl  = null;
  var isOpen   = false;

  function mountBell() {
    if (document.getElementById('ownerNotifBell')) return;

    var css = `
      #ownerNotifBell{
        position: fixed; top: 14px; right: 16px; z-index: 9990;
        width: 42px; height: 42px;
        background: #FFFFFF; color: #1E3A8A;
        border: 1.5px solid #E6E9EE; border-radius: 12px;
        display: grid; place-items: center; cursor: pointer;
        box-shadow: 0 4px 12px rgba(15,23,42,.08), 0 1px 2px rgba(15,23,42,.04);
        transition: all .15s ease; font-size: 18px; user-select: none;
      }
      #ownerNotifBell:hover{ transform: translateY(-1px); box-shadow: 0 8px 20px rgba(15,23,42,.12); border-color: #FF6B1A; color: #FF6B1A; }
      #ownerNotifBell:active{ transform: translateY(0); }
      #ownerNotifBadge{
        position: absolute; top: -4px; right: -4px;
        min-width: 18px; height: 18px; padding: 0 5px;
        background: linear-gradient(180deg,#EF4444,#DC2626); color: #fff;
        border: 2px solid #fff; border-radius: 99px;
        font-size: 11px; font-weight: 800; line-height: 14px;
        display: none; place-items: center;
        box-shadow: 0 2px 6px rgba(220,38,38,.35);
      }
      #ownerNotifBadge.show{ display: grid; }
      #ownerNotifPanel{
        position: fixed; top: 64px; right: 16px; z-index: 9991;
        width: 360px; max-width: calc(100vw - 32px);
        background: #FFFFFF; border: 1px solid #E6E9EE; border-radius: 14px;
        box-shadow: 0 18px 44px rgba(15,23,42,.14), 0 6px 14px rgba(15,23,42,.06);
        display: none; max-height: 70vh; overflow: hidden;
        flex-direction: column;
      }
      #ownerNotifPanel.show{ display: flex; }
      .onp-head{
        padding: 14px 18px; border-bottom: 1px solid #EEF1F6;
        display: flex; align-items: center; justify-content: space-between;
        background: linear-gradient(180deg,#FAFBFD,#F4F6FB);
        border-radius: 14px 14px 0 0;
      }
      .onp-title{ font-weight: 800; font-size: 14px; color: #0F1729; letter-spacing: -.01em; }
      .onp-clear{
        font-size: 11px; font-weight: 700; color: #6B7385;
        background: none; border: none; cursor: pointer; padding: 4px 8px;
        border-radius: 6px;
      }
      .onp-clear:hover{ background: #EEF1F6; color: #1E3A8A; }
      .onp-list{ overflow-y: auto; flex: 1; padding: 6px; }
      .onp-empty{ padding: 32px 18px; text-align: center; color: #94A3B8; font-size: 13px; }
      .onp-item{
        display: block; padding: 12px 14px; margin: 4px 2px;
        border-radius: 10px; text-decoration: none; color: inherit;
        border: 1px solid transparent;
        transition: all .15s ease; cursor: pointer;
      }
      .onp-item:hover{ background: #F4F6FB; border-color: #E6E9EE; }
      .onp-item-row{ display: flex; gap: 10px; align-items: flex-start; }
      .onp-icon{
        font-size: 18px; width: 34px; height: 34px;
        flex-shrink: 0; display: grid; place-items: center;
        background: #FFFFFF; border: 1px solid #E6E9EE; border-radius: 9px;
      }
      .onp-icon.urgent{ background: #FEF2F2; border-color: #FCA5A5; }
      .onp-icon.warn{ background: #FFFBEB; border-color: #FCD34D; }
      .onp-icon.success{ background: #F0FDF4; border-color: #86EFAC; }
      .onp-icon.info{ background: #EFF6FF; border-color: #93C5FD; }
      .onp-body{ flex: 1; min-width: 0; }
      .onp-itm-title{ font-weight: 700; font-size: 13.5px; color: #0F1729; margin-bottom: 2px; line-height: 1.35; }
      .onp-itm-sub{ font-size: 12px; color: #6B7385; line-height: 1.4; }
      .onp-dot{
        width: 7px; height: 7px; border-radius: 50%; background: #FF6B1A;
        margin-top: 7px; flex-shrink: 0;
      }
      .onp-item.seen .onp-dot{ background: transparent; }
      .onp-foot{
        padding: 10px 14px; border-top: 1px solid #EEF1F6;
        text-align: center; font-size: 11px; color: #94A3B8;
        background: #FAFBFD; border-radius: 0 0 14px 14px;
      }
      @media (max-width: 640px){
        #ownerNotifBell{ top: 10px; right: 10px; width: 38px; height: 38px; font-size: 16px; }
        #ownerNotifPanel{ top: 56px; right: 10px; left: 10px; width: auto; }
      }
    `;
    var style = document.createElement('style');
    style.id = 'ownerNotifStyle';
    style.textContent = css;
    document.head.appendChild(style);

    bellRoot = document.createElement('div');
    bellRoot.id = 'ownerNotifBell';
    bellRoot.title = 'Notifications';
    bellRoot.innerHTML = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg><span id="ownerNotifBadge"></span>';
    document.body.appendChild(bellRoot);
    badgeEl = document.getElementById('ownerNotifBadge');

    listRoot = document.createElement('div');
    listRoot.id = 'ownerNotifPanel';
    listRoot.innerHTML =
      '<div class="onp-head">' +
        '<span class="onp-title">Notifications</span>' +
        '<button class="onp-clear" id="onpClear">Mark all read</button>' +
      '</div>' +
      '<div class="onp-list" id="onpList">' +
        '<div class="onp-empty">Loading…</div>' +
      '</div>' +
      '<div class="onp-foot">Refreshes every minute</div>';
    document.body.appendChild(listRoot);

    bellRoot.addEventListener('click', function(e){
      e.stopPropagation();
      toggle();
    });
    document.addEventListener('click', function(e){
      if (isOpen && !listRoot.contains(e.target) && !bellRoot.contains(e.target)) {
        close();
      }
    });
    document.getElementById('onpClear').addEventListener('click', function(e){
      e.stopPropagation();
      markAllSeen();
    });
  }

  function toggle(){
    if (isOpen) { close(); } else { open(); }
  }
  function open(){
    listRoot.classList.add('show');
    isOpen = true;
    refresh();
  }
  function close(){
    listRoot.classList.remove('show');
    isOpen = false;
  }

  function seenKey(uid){ return 'dl_notif_seen_v1_' + (uid || 'anon'); }
  function getSeen(uid){
    try {
      var raw = localStorage.getItem(seenKey(uid));
      return raw ? JSON.parse(raw) : {};
    } catch(e){ return {}; }
  }
  function setSeen(uid, map){
    try { localStorage.setItem(seenKey(uid), JSON.stringify(map)); } catch(e){}
  }
  function markAllSeen(){
    window.c.auth.getUser().then(function(r){
      var uid = r && r.data && r.data.user ? r.data.user.id : null;
      var seen = getSeen(uid);
      (window.__lastNotifs || []).forEach(function(n){ seen[n.key] = 1; });
      setSeen(uid, seen);
      render(window.__lastNotifs || []);
    });
  }

  function refresh(){
    if (!window.c) return;
    window.c.rpc('get_owner_notifications').then(function(r){
      if (r.error) { return; }
      var list = Array.isArray(r.data) ? r.data : [];
      window.__lastNotifs = list;
      render(list);
    }).catch(function(){ /* silent */ });
  }

  function render(notifs){
    window.c.auth.getUser().then(function(r){
      var uid = r && r.data && r.data.user ? r.data.user.id : null;
      var seen = getSeen(uid);
      var unread = notifs.filter(function(n){ return !seen[n.key]; });

      if (badgeEl) {
        if (unread.length > 0) {
          badgeEl.textContent = unread.length > 9 ? '9+' : String(unread.length);
          badgeEl.classList.add('show');
        } else {
          badgeEl.classList.remove('show');
        }
      }

      var listEl = document.getElementById('onpList');
      if (!listEl) return;
      if (notifs.length === 0) {
        listEl.innerHTML = '<div class="onp-empty">🎉 All caught up — no pending tasks!</div>';
        return;
      }
      var html = notifs.map(function(n){
        var isSeen = !!seen[n.key];
        var tone = n.tone || 'info';
        var icon = n.icon || '🔔';
        var title = escapeHtml(n.title || '');
        var sub   = escapeHtml(n.subtitle || '');
        var href  = n.href || '#';
        return '<a class="onp-item ' + (isSeen ? 'seen' : '') + '" href="' + escapeAttr(href) + '" data-key="' + escapeAttr(n.key) + '">' +
          '<div class="onp-item-row">' +
            '<div class="onp-icon ' + tone + '">' + icon + '</div>' +
            '<div class="onp-body">' +
              '<div class="onp-itm-title">' + title + '</div>' +
              '<div class="onp-itm-sub">' + sub + '</div>' +
            '</div>' +
            '<div class="onp-dot"></div>' +
          '</div>' +
        '</a>';
      }).join('');
      listEl.innerHTML = html;

      // Click handler — mark as seen on click
      Array.prototype.forEach.call(listEl.querySelectorAll('.onp-item'), function(a){
        a.addEventListener('click', function(){
          var key = a.getAttribute('data-key');
          var s = getSeen(uid);
          s[key] = 1;
          setSeen(uid, s);
        });
      });
    });
  }

  function escapeHtml(s){
    return String(s || '').replace(/[&<>"']/g, function(c){
      return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];
    });
  }
  function escapeAttr(s){ return escapeHtml(s).replace(/"/g, '&quot;'); }
})();
