/* ============================================================
   DukanList — 🔥 Trending This Week (homepage section)
   ------------------------------------------------------------
   Reads get_trending_shops() (db/213) — top active shops by
   weighted engagement (calls/WhatsApp×5, directions/share×3,
   views×1) over the last 7 days. Pure social proof, zero manual
   curation. Section stays hidden if fewer than 3 trending shops.
   ============================================================ */
(function () {
  'use strict';

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (ch) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch];
    });
  }

  async function loadTrending() {
    try {
      if (typeof ShopDB === 'undefined' || !ShopDB || !ShopDB.client) return;
      var c = ShopDB.client;
      var r = await c.rpc('get_trending_shops', { p_city_id: null, p_limit: 8 });
      if (r.error || !Array.isArray(r.data) || r.data.length < 3) return;

      var grid = document.getElementById('trendingGrid');
      var section = document.getElementById('trendingSection');
      if (!grid || !section) return;

      var isHi = document.documentElement.dataset.lang === 'hi';

      grid.innerHTML = r.data.map(function (b, i) {
        var photo = b.photo
          ? (window.DukanImg ? DukanImg.opt(b.photo, { width: 400, quality: 75 }) : b.photo)
          : null;
        var name = (isHi && b.name_hi) ? b.name_hi : b.name;
        var flameRank = i < 3
          ? '<div style="position:absolute;top:8px;left:8px;background:linear-gradient(135deg,#EF4444,#B91C1C);color:#fff;padding:4px 10px;border-radius:99px;font-size:.72rem;font-weight:900;box-shadow:0 3px 10px rgba(239,68,68,.4)">🔥 #' + (i + 1) + '</div>'
          : '';
        return ''
          + '<a href="/business.html?slug=' + encodeURIComponent(b.slug || '') + '" '
          +   'style="background:#fff;border-radius:14px;overflow:hidden;text-decoration:none;color:inherit;display:flex;flex-direction:column;border:1px solid rgba(15,23,42,.06);box-shadow:0 1px 3px rgba(15,23,42,.04);transition:.2s" '
          +   'onmouseover="this.style.transform=\'translateY(-3px)\';this.style.boxShadow=\'0 10px 24px rgba(239,68,68,0.14)\'" '
          +   'onmouseout="this.style.transform=\'\';this.style.boxShadow=\'0 1px 3px rgba(15,23,42,.04)\'">'
          +   '<div style="aspect-ratio:16/10;background:linear-gradient(135deg,#FEE2E2,#FECACA);position:relative;overflow:hidden">'
          +     (photo
                  ? '<img src="' + photo + '" alt="" width="400" height="250" style="width:100%;height:100%;object-fit:cover" loading="lazy" onerror="this.style.display=\'none\'">'
                  : '<div style="height:100%;display:grid;place-items:center;font-size:3rem;opacity:.55">🏪</div>')
          +     flameRank
          +   '</div>'
          +   '<div style="padding:12px 14px">'
          +     '<div style="font-weight:800;color:#0F172A;font-size:.96rem;line-height:1.3;margin-bottom:3px">' + esc(name) + '</div>'
          +     '<div style="font-size:.78rem;color:#64748b;display:flex;gap:8px;align-items:center;flex-wrap:wrap">'
          +       (b.rating_avg > 0 ? '<span style="color:#D97706;font-weight:800">⭐ ' + Number(b.rating_avg).toFixed(1) + '</span>' : '')
          +       (b.category_name ? '<span>' + esc(b.category_name) + '</span>' : '')
          +       '<span style="color:#DC2626;font-weight:700">🔥 ' + Number(b.week_leads || 0) + (isHi ? ' बार देखा गया' : ' visits this week') + '</span>'
          +     '</div>'
          +   '</div>'
          + '</a>';
      }).join('');

      section.style.display = '';
    } catch (e) {
      console.warn('Trending load:', e);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', loadTrending);
  } else {
    loadTrending();
  }
})();
