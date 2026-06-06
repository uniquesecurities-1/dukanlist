/* ============================================================
   recently-viewed.js — localStorage-based recently-viewed shops
   ============================================================
   USAGE:
     // On a business detail page, call once after BIZ data loads:
     DukanRecent.track(biz);

     // On homepage or anywhere else, render the strip:
     DukanRecent.render('recentlyViewedSlot');   // targets <div id="…">

   Stores up to 10 shops in localStorage. Skips current shop on render.
============================================================ */
(function(global){
  'use strict';
  const KEY = 'dukan_recently_viewed_v1';
  const MAX = 10;

  function load(){
    try { return JSON.parse(localStorage.getItem(KEY) || '[]'); }
    catch(_){ return []; }
  }
  function save(arr){
    try { localStorage.setItem(KEY, JSON.stringify(arr.slice(0, MAX))); } catch(_){}
  }

  function track(biz){
    if (!biz || !biz.slug) return;
    const items = load().filter(b => b.slug !== biz.slug);
    items.unshift({
      slug:        biz.slug,
      name:        biz.name || 'Shop',
      photo:       (Array.isArray(biz.photos) && biz.photos.length) ? biz.photos[0] : null,
      city:        (biz.geo_cities && biz.geo_cities.name) || biz.city_name || biz.city || '',
      category:    (biz.categories && biz.categories.name) || biz.category_name || biz.primary_category_name || '',
      rating_avg:  biz.rating_avg || 0,
      rating_count:biz.rating_count || 0,
      ts:          Date.now()
    });
    save(items);
  }

  function render(slotId, opts){
    opts = opts || {};
    const slot = document.getElementById(slotId);
    if (!slot) return;
    const items = load().filter(b => !opts.excludeSlug || b.slug !== opts.excludeSlug);
    if (!items.length){ slot.style.display = 'none'; return; }

    slot.style.display = '';
    slot.innerHTML = `
      <div style="display:flex;justify-content:space-between;align-items:baseline;margin-bottom:14px">
        <h2 style="font-size:1.25rem;font-weight:800;color:#0F172A;letter-spacing:-.015em;font-family:'Plus Jakarta Sans','Manrope',sans-serif">
          🕒 Recently viewed
        </h2>
        <button onclick="DukanRecent.clear('${slotId}')" style="background:transparent;border:0;color:#94a3b8;font-size:.78rem;font-weight:700;cursor:pointer;letter-spacing:.04em;text-transform:uppercase">Clear</button>
      </div>
      <div style="display:flex;gap:12px;overflow-x:auto;scroll-snap-type:x mandatory;-webkit-overflow-scrolling:touch;padding-bottom:6px;scrollbar-width:none">
        <style>#${slotId}::-webkit-scrollbar,#${slotId} div::-webkit-scrollbar{display:none}.rv-card{flex:0 0 220px;background:#fff;border:1px solid rgba(15,23,42,.06);border-radius:14px;overflow:hidden;text-decoration:none;color:inherit;scroll-snap-align:start;transition:transform .15s,box-shadow .15s;box-shadow:0 1px 3px rgba(15,23,42,.04)}.rv-card:hover{transform:translateY(-2px);box-shadow:0 12px 28px rgba(15,23,42,.08);text-decoration:none}.rv-photo{width:100%;aspect-ratio:16/10;background:linear-gradient(135deg,#FAFAFA,#F1F5F9);display:grid;place-items:center;font-size:2rem;opacity:.55}.rv-photo img{width:100%;height:100%;object-fit:cover}.rv-info{padding:10px 12px}.rv-name{font-size:.92rem;font-weight:700;color:#0F172A;line-height:1.3;margin-bottom:3px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.rv-meta{font-size:.78rem;color:#64748b;font-weight:600}</style>
        ${items.map(b => {
          const rate = b.rating_avg > 0 ? '⭐ ' + Number(b.rating_avg).toFixed(1) : (b.category || '');
          return `<a class="rv-card" href="/business.html?slug=${encodeURIComponent(b.slug)}">
            <div class="rv-photo">${b.photo ? '<img src="'+esc(b.photo)+'" alt="" loading="lazy">' : '🏪'}</div>
            <div class="rv-info">
              <div class="rv-name">${esc(b.name)}</div>
              <div class="rv-meta">${esc(rate)}${b.city ? ' · ' + esc(b.city) : ''}</div>
            </div>
          </a>`;
        }).join('')}
      </div>
    `;
  }

  function clear(slotId){
    save([]);
    const slot = document.getElementById(slotId);
    if (slot) slot.style.display = 'none';
  }

  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]); }

  global.DukanRecent = { track, render, clear, load };
})(window);
