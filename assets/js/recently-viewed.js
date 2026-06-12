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
      category_icon: (biz.categories && biz.categories.icon) || biz.category_icon || '',
      rating_avg:  biz.rating_avg || 0,
      rating_count:biz.rating_count || 0,
      mobile:      String(biz.mobile || '').replace(/\D/g,'').slice(-10),
      whatsapp:    String(biz.whatsapp || biz.mobile || '').replace(/\D/g,'').slice(-10),
      verified:    !!(biz.verified_visit || biz.verified_score >= 1),
      ts:          Date.now()
    });
    save(items);
  }

  function timeAgo(ts){
    if (!ts) return '';
    const diff = Date.now() - ts;
    const m = Math.floor(diff / 60000);
    if (m < 1) return 'just now';
    if (m < 60) return m + 'm ago';
    const h = Math.floor(m / 60);
    if (h < 24) return h + 'h ago';
    const d = Math.floor(h / 24);
    if (d < 7) return d + 'd ago';
    return Math.floor(d / 7) + 'w ago';
  }

  function render(slotId, opts){
    opts = opts || {};
    const slot = document.getElementById(slotId);
    if (!slot) return;
    const items = load().filter(b => !opts.excludeSlug || b.slug !== opts.excludeSlug);
    if (!items.length){ slot.style.display = 'none'; return; }

    slot.style.display = '';
    slot.innerHTML = `
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:14px">
        <h2 style="font-size:1.18rem;font-weight:800;color:#0F172A;letter-spacing:-.015em;font-family:'Plus Jakarta Sans','Manrope',sans-serif;margin:0">
          🕒 Recently viewed
        </h2>
        <button onclick="DukanRecent.clear('${slotId}')" style="background:transparent;border:0;color:#94a3b8;font-size:.78rem;font-weight:700;cursor:pointer;letter-spacing:.04em;text-transform:uppercase">Clear</button>
      </div>
      <style>
        #${slotId} *{box-sizing:border-box}
        #${slotId} .rv-list{display:flex;flex-direction:column;gap:10px}
        #${slotId} .rv-row{display:grid;grid-template-columns:72px 1fr auto;gap:12px;align-items:center;background:#fff;border:1px solid rgba(15,23,42,.06);border-radius:14px;padding:10px;text-decoration:none;color:inherit;transition:.15s;box-shadow:0 1px 3px rgba(15,23,42,.04);min-width:0}
        #${slotId} .rv-row:hover{transform:translateY(-1px);box-shadow:0 10px 24px rgba(15,23,42,.08);text-decoration:none}
        #${slotId} .rv-thumb{width:72px;height:72px;border-radius:11px;background:linear-gradient(135deg,#F8FAFC,#E2E8F0);display:grid;place-items:center;font-size:1.8rem;overflow:hidden;flex-shrink:0}
        #${slotId} .rv-thumb img{width:100%;height:100%;object-fit:cover}
        #${slotId} .rv-mid{min-width:0;display:flex;flex-direction:column;gap:3px}
        #${slotId} .rv-name{font-size:.97rem;font-weight:800;color:#0F172A;line-height:1.25;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
        #${slotId} .rv-line2{display:flex;align-items:center;gap:6px;font-size:.74rem;color:#64748b;font-weight:600}
        #${slotId} .rv-cat{background:#F1F5F9;color:#475569;padding:2px 7px;border-radius:99px;font-size:.7rem;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:120px;display:inline-block}
        #${slotId} .rv-rate{color:#F59E0B;font-weight:800}
        #${slotId} .rv-verify{color:#059669;font-weight:800}
        #${slotId} .rv-actions{display:flex;gap:6px;flex-shrink:0}
        #${slotId} .rv-btn{width:36px;height:36px;border-radius:50%;display:grid;place-items:center;text-decoration:none;font-size:.95rem;transition:.15s;border:0;cursor:pointer}
        #${slotId} .rv-btn.call{background:linear-gradient(135deg,#10B981,#059669);color:#fff;box-shadow:0 3px 8px rgba(16,185,129,.3)}
        #${slotId} .rv-btn.wa{background:linear-gradient(135deg,#25D366,#128C7E);color:#fff;box-shadow:0 3px 8px rgba(37,211,102,.3)}
        #${slotId} .rv-btn:active{transform:scale(.92)}
      </style>
      <div class="rv-list">
        ${items.slice(0, (opts.max || 4)).map(b => {
          const rateStr = b.rating_avg > 0 ? '<span class="rv-rate">⭐ ' + Number(b.rating_avg).toFixed(1) + '</span>' : '';
          const catStr  = b.category ? '<span class="rv-cat">' + (b.category_icon ? esc(b.category_icon) + ' ' : '') + esc(b.category) + '</span>' : '';
          const verify  = b.verified ? '<span class="rv-verify">✓ Verified</span>' : '';
          const cityStr = b.city ? esc(b.city) : '';
          const ago     = b.ts ? timeAgo(b.ts) : '';
          const waMsg   = encodeURIComponent('Hi ' + (b.name || 'there') + ', I found you on DukanList.');
          const callBtn = (b.mobile && b.mobile.length === 10)
            ? `<a class="rv-btn call" href="tel:+91${b.mobile}" onclick="event.stopPropagation()" aria-label="Call ${esc(b.name)}" title="Call">📞</a>` : '';
          const waBtn = (b.whatsapp && b.whatsapp.length === 10)
            ? `<a class="rv-btn wa" href="https://wa.me/91${b.whatsapp}?text=${waMsg}" target="_blank" rel="noopener" onclick="event.stopPropagation()" aria-label="WhatsApp ${esc(b.name)}" title="WhatsApp">💬</a>` : '';
          const actions = (callBtn || waBtn) ? '<div class="rv-actions">' + callBtn + waBtn + '</div>' : '';
          return `<a class="rv-row" href="/business.html?slug=${encodeURIComponent(b.slug)}">
            <div class="rv-thumb">${b.photo ? '<img src="'+esc(b.photo)+'" alt="" loading="lazy">' : (b.category_icon || '🏪')}</div>
            <div class="rv-mid">
              <div class="rv-name">${esc(b.name)}</div>
              <div class="rv-line2">${catStr}${rateStr ? '<span>·</span>'+rateStr : ''}${verify ? '<span>·</span>'+verify : ''}</div>
              <div class="rv-line2" style="font-size:.7rem">${cityStr ? '📍 ' + cityStr : ''}${cityStr && ago ? ' · ' : ''}${ago ? '🕒 ' + ago : ''}</div>
            </div>
            ${actions}
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
