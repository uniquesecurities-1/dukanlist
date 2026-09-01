/* ============================================================
   DukanList — 🔥 Shop Love button (business.html)
   ------------------------------------------------------------
   v214: shop_likes existed since db/119 but was only usable in
   the Discover feed. This surfaces the same Love mechanic on the
   business page: shows likes_count publicly + lets any visitor
   love a shop (session-deduped, no login).
   Depends: window.BIZ (set by business.html render), ShopDB.
   ============================================================ */
(function () {
  'use strict';

  var LS_SID   = 'dl_love_sid_v1';
  var LS_LOVED = 'dl_loved_shops_v1';

  function sid() {
    try {
      var s = localStorage.getItem(LS_SID);
      if (!s) {
        s = 'lv_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 10);
        localStorage.setItem(LS_SID, s);
      }
      return s;
    } catch (e) { return 'lv_fallback_' + Date.now(); }
  }

  function lovedMap() {
    try { return JSON.parse(localStorage.getItem(LS_LOVED) || '{}'); }
    catch (e) { return {}; }
  }
  function markLoved(id) {
    try {
      var m = lovedMap(); m[id] = 1;
      localStorage.setItem(LS_LOVED, JSON.stringify(m));
    } catch (e) {}
  }
  function isLoved(id) { return !!lovedMap()[id]; }

  function paint(count, loved) {
    var btn = document.getElementById('loveBtn');
    var cnt = document.getElementById('loveCount');
    var ico = document.getElementById('loveIcon');
    if (!btn) return;
    if (cnt) cnt.textContent = String(count || 0);
    if (ico) ico.style.filter = loved ? 'none' : 'grayscale(60%)';
    btn.style.display = '';
    btn.title = loved ? 'You love this shop 🔥' : 'Love this shop';
  }

  async function init() {
    try {
      if (typeof ShopDB === 'undefined' || !ShopDB || !ShopDB.client) return;
      var biz = window.BIZ;
      if (!biz || !biz.id) { setTimeout(init, 600); return; }

      var count = Number(biz.likes_count || 0);
      // Authoritative count if not present on BIZ
      if (!('likes_count' in biz)) {
        try {
          var r = await ShopDB.client.rpc('get_shop_likes', { p_business_id: biz.id });
          if (!r.error && r.data != null) count = Number(r.data) || 0;
        } catch (e) {}
      }
      paint(count, isLoved(biz.id));
    } catch (e) { console.warn('shop-love init:', e); }
  }

  window.shopLoveToggle = async function () {
    try {
      var biz = window.BIZ;
      if (!biz || !biz.id || typeof ShopDB === 'undefined' || !ShopDB.client) return;

      var cnt = document.getElementById('loveCount');
      var already = isLoved(biz.id);

      // Optimistic bump (only when not already loved — toggle fn is add-only)
      if (!already && cnt) cnt.textContent = String((parseInt(cnt.textContent, 10) || 0) + 1);
      markLoved(biz.id);
      paint(parseInt(cnt ? cnt.textContent : '0', 10) || 0, true);

      var r = await ShopDB.client.rpc('toggle_shop_like', {
        p_business_id: biz.id,
        p_session_id: sid()
      });
      if (!r.error && r.data != null) {
        // Server returns authoritative count (INT) or {count, liked}
        var serverCount = (typeof r.data === 'object') ? parseInt(r.data.count, 10) : parseInt(r.data, 10);
        if (!isNaN(serverCount)) paint(serverCount, true);
      }
    } catch (e) { console.warn('shop-love toggle:', e); }
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { setTimeout(init, 400); });
  } else {
    setTimeout(init, 400);
  }
})();
