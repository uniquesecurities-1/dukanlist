/* ============================================================
   geo-nearby.js
   ============================================================
   STRATEGIC PHASE 6 (2026-06-05):
   "Open Near You Now" widget — high-intent customer discovery.

   Behaviour:
     - On homepage load, show a CTA pill: "Find shops open near you"
     - User taps → request geolocation permission
     - Once granted (or denied), persist in localStorage
     - Call get_open_shops_near RPC with radius 3 km, 8 results
     - Render compact horizontal scroller of result cards
     - Each card shows: photo / name / distance / rating /
                        Call + WhatsApp + Directions buttons

   Privacy:
     - Coordinates are NEVER sent to any server other than Supabase RPC
     - Stored only in localStorage (volatile)
     - User can revoke any time via browser settings
   ============================================================ */
(function(global){
'use strict';

const STORAGE_KEY = 'dukanlist.geo';
const STORAGE_DENIED_KEY = 'dukanlist.geo.denied';

// ─── Get stored coords (or null) ────────────────────────────
function getStoredCoords(){
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const obj = JSON.parse(raw);
    // Stale after 7 days
    if (!obj.ts || Date.now() - obj.ts > 7 * 24 * 60 * 60 * 1000) {
      localStorage.removeItem(STORAGE_KEY);
      return null;
    }
    return { lat: obj.lat, lng: obj.lng, ts: obj.ts };
  } catch(_){ return null; }
}

function storeCoords(lat, lng){
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ lat, lng, ts: Date.now() }));
  } catch(_){}
}

function isDenied(){
  try {
    const t = localStorage.getItem(STORAGE_DENIED_KEY);
    if (!t) return false;
    // Re-prompt after 24 hours of denial
    return (Date.now() - parseInt(t, 10) < 24 * 60 * 60 * 1000);
  } catch(_){ return false; }
}

function markDenied(){
  try { localStorage.setItem(STORAGE_DENIED_KEY, String(Date.now())); } catch(_){}
}

// ─── Request browser geolocation ─────────────────────────────
function requestLocation(){
  return new Promise((resolve, reject) => {
    if (!('geolocation' in navigator)) {
      reject(new Error('not_supported'));
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        const lat = Number(pos.coords.latitude.toFixed(6));
        const lng = Number(pos.coords.longitude.toFixed(6));
        storeCoords(lat, lng);
        resolve({ lat, lng });
      },
      (err) => {
        if (err && err.code === 1) markDenied();
        reject(err || new Error('failed'));
      },
      { enableHighAccuracy: false, timeout: 8000, maximumAge: 600000 }
    );
  });
}

// ─── Call RPC and render results ─────────────────────────────
async function fetchNearby(coords, radiusKm){
  if (!global.ShopDB || !ShopDB.client) return { items: [], count: 0 };
  try {
    const { data, error } = await ShopDB.client.rpc('get_open_shops_near', {
      p_lat:       coords.lat,
      p_lng:       coords.lng,
      p_radius_km: radiusKm || 3,
      p_limit:     8
    });
    if (error || !data) return { items: [], count: 0 };
    return data;
  } catch(_){ return { items: [], count: 0 }; }
}

// ─── Render widget into container ────────────────────────────
async function renderWidget(containerId, opts){
  opts = opts || {};
  const el = document.getElementById(containerId);
  if (!el) return;

  // Initial CTA state
  el.innerHTML =
    '<div class="ony-card">' +
    '  <div class="ony-head">' +
    '    <span class="ony-emoji">📍</span>' +
    '    <div class="ony-head-text">' +
    '      <div class="ony-title">Find shops open near you</div>' +
    '      <div class="ony-sub">One tap discovery. Private and instant.</div>' +
    '    </div>' +
    '    <button class="ony-cta" id="onyEnableBtn" type="button">Enable</button>' +
    '  </div>' +
    '  <div class="ony-results" id="onyResults" style="display:none"></div>' +
    '</div>';

  const btn = document.getElementById('onyEnableBtn');
  const results = document.getElementById('onyResults');

  let currentRadius = 3;
  let currentCoords = null;

  async function load(coords, radius){
    radius = radius || 3;
    currentRadius = radius;
    currentCoords = coords;
    btn.disabled = true;
    btn.textContent = 'Finding…';
    results.innerHTML = '<div class="ony-empty" style="opacity:.6">Searching ' + radius + ' km radius…</div>';
    results.style.display = 'block';
    const data = await fetchNearby(coords, radius);
    btn.disabled = false;
    btn.style.display = 'none';
    if (!data || !data.count) {
      const nextRadius = radius < 5 ? 5 : (radius < 10 ? 10 : (radius < 25 ? 25 : 50));
      const showExpand = radius < 50;
      results.innerHTML =
        '<div class="ony-empty">' +
        '  <div style="margin-bottom:10px">No open shops within ' + radius + ' km.</div>' +
        '  <div style="display:flex;gap:8px;flex-wrap:wrap;justify-content:center">' +
        (showExpand
          ? '    <button type="button" class="ony-cta ony-expand" data-r="' + nextRadius + '">🔍 Try ' + nextRadius + ' km</button>'
          : '') +
        '    <button type="button" class="ony-cta ony-refresh" style="background:#f3f4f6;color:#374151">🔄 Refresh</button>' +
        '  </div>' +
        '</div>';
      results.style.display = 'block';
      const exp = results.querySelector('.ony-expand');
      const ref = results.querySelector('.ony-refresh');
      if (exp) exp.addEventListener('click', () => load(currentCoords, Number(exp.getAttribute('data-r')) || nextRadius));
      if (ref) ref.addEventListener('click', () => load(currentCoords, currentRadius));
      return;
    }
    const headerHtml =
      '<div class="ony-results-head" style="display:flex;justify-content:space-between;align-items:center;padding:6px 4px 10px;font-size:12px;color:#6b7280">' +
      '  <span>' + data.count + ' open within ' + radius + ' km</span>' +
      '  <button type="button" class="ony-refresh" style="background:transparent;border:0;color:#2563eb;font-weight:600;cursor:pointer;font-size:12px">🔄 Refresh</button>' +
      '</div>';
    results.innerHTML = headerHtml + (data.items || []).map(renderShopRow).join('');
    results.style.display = 'block';
    const ref = results.querySelector('.ony-refresh');
    if (ref) ref.addEventListener('click', () => load(currentCoords, currentRadius));
  }

  // Cached coords — skip prompt
  const cached = getStoredCoords();
  if (cached && !opts.forcePrompt) {
    await load(cached);
    return;
  }

  if (isDenied()) {
    // Don't pester the user — hide widget
    el.style.display = 'none';
    return;
  }

  btn.addEventListener('click', async () => {
    btn.disabled = true;
    btn.textContent = 'Allow location…';
    try {
      const coords = await requestLocation();
      await load(coords);
    } catch(err) {
      btn.disabled = false;
      btn.textContent = 'Try again';
      if (err && err.code === 1) {
        results.innerHTML = '<div class="ony-empty">Location access blocked. Enable in your browser settings to use this.</div>';
        results.style.display = 'block';
      }
    }
  });
}

function renderShopRow(b){
  const dist = (b.dist_km != null) ? (Number(b.dist_km).toFixed(1) + ' km') : '';
  const rating = (b.rating_count > 0) ? '⭐ ' + Number(b.rating_avg).toFixed(1) : '';
  const photo = b.photo
    ? '<img src="' + escAttr(b.photo) + '" alt="" loading="lazy">'
    : '<span class="ony-row-emoji">🏪</span>';
  const phone = (b.mobile || '').replace(/\D/g, '');
  const wa    = (b.whatsapp || b.mobile || '').replace(/\D/g, '');
  const phoneBtn = phone ? '<a class="ony-act call" href="tel:' + escAttr(phone) + '">📞 Call</a>' : '';
  const waBtn   = wa    ? '<a class="ony-act wa" href="https://wa.me/91' + escAttr(wa) + '" target="_blank" rel="noopener">💬 WhatsApp</a>' : '';
  return '' +
    '<a class="ony-row" href="/business.html?slug=' + encodeURIComponent(b.slug || '') + '">' +
    '  <div class="ony-row-photo">' + photo + '</div>' +
    '  <div class="ony-row-body">' +
    '    <div class="ony-row-name">' + escHtml(b.name || '') + '</div>' +
    '    <div class="ony-row-meta">' +
    '      <span class="ony-dist">' + escHtml(dist) + ' away</span>' +
    (rating ? '<span class="ony-rating">' + escHtml(rating) + '</span>' : '') +
    '    </div>' +
    '    <div class="ony-row-actions">' + phoneBtn + waBtn + '</div>' +
    '  </div>' +
    '</a>';
}

// ─── helpers ────────────────────────────────────────────────
function escHtml(s){ return String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
function escAttr(s){ return escHtml(s); }

// ─── Public API ─────────────────────────────────────────────
global.GeoNearby = {
  getStoredCoords,
  storeCoords,
  requestLocation,
  fetchNearby,
  renderWidget,
  isDenied
};

})(window);
