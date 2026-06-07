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
  if (!global.ShopDB || !ShopDB.client) return { items: [], count: 0, error: 'init' };
  try {
    // Timeout the RPC at 12s to prevent indefinite stuck state
    const rpcPromise = ShopDB.client.rpc('get_open_shops_near', {
      p_lat:       coords.lat,
      p_lng:       coords.lng,
      p_radius_km: radiusKm || 3,
      p_limit:     8
    });
    const timeoutPromise = new Promise((resolve) =>
      setTimeout(() => resolve({ data: null, error: { message: 'timeout' } }), 12000)
    );
    const { data, error } = await Promise.race([rpcPromise, timeoutPromise]);
    if (error) return { items: [], count: 0, error: error.message || 'rpc_error' };
    if (!data) return { items: [], count: 0 };
    return data;
  } catch(e){ return { items: [], count: 0, error: (e && e.message) || 'exception' }; }
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
    // Build searching state with a Cancel/Reset option so user is NEVER fully stuck
    results.innerHTML =
      '<div class="ony-empty" style="opacity:.85">' +
      '  <div style="display:flex;justify-content:center;align-items:center;gap:8px;margin-bottom:6px">' +
      '    <span class="ony-spinner" style="display:inline-block;width:14px;height:14px;border:2px solid rgba(0,0,0,.15);border-top-color:#2563eb;border-radius:50%;animation:onySpin 0.8s linear infinite"></span>' +
      '    <span>Searching ' + radius + ' km radius…</span>' +
      '  </div>' +
      '  <button type="button" class="ony-stuck-fix" style="background:#f3f4f6;color:#374151;padding:6px 12px;border-radius:99px;font-size:12px;font-weight:600;border:0;cursor:pointer">Taking too long? Tap to retry</button>' +
      '</div>' +
      '<style>@keyframes onySpin{to{transform:rotate(360deg)}}</style>';
    results.style.display = 'block';
    const stuckBtn = results.querySelector('.ony-stuck-fix');
    if (stuckBtn) stuckBtn.addEventListener('click', () => load(currentCoords, currentRadius));

    const data = await fetchNearby(coords, radius);
    btn.disabled = false;
    btn.style.display = 'none';

    if (data && data.error) {
      // Error or timeout — show explicit retry option
      results.innerHTML =
        '<div class="ony-empty">' +
        '  <div style="margin-bottom:10px">Could not load shops (' + (data.error === 'timeout' ? 'timeout — slow network' : 'connection issue') + ').</div>' +
        '  <button type="button" class="ony-cta ony-retry">🔄 Try Again</button>' +
        '</div>';
      const r = results.querySelector('.ony-retry');
      if (r) r.addEventListener('click', () => load(currentCoords, currentRadius));
      return;
    }

    if (!data || !data.count) {
      const nextRadius = radius < 5 ? 5 : (radius < 10 ? 10 : (radius < 25 ? 25 : 50));
      const showExpand = radius < 50;
      results.innerHTML =
        '<div class="ony-empty">' +
        '  <div style="margin-bottom:10px">No open shops within ' + radius + ' km right now.</div>' +
        '  <div style="display:flex;gap:8px;flex-wrap:wrap;justify-content:center">' +
        (showExpand
          ? '    <button type="button" class="ony-cta ony-expand" data-r="' + nextRadius + '">🔍 Try ' + nextRadius + ' km</button>'
          : '') +
        '    <button type="button" class="ony-cta ony-refresh" style="background:#f3f4f6;color:#374151">🔄 Refresh</button>' +
        '    <a href="/browse.html" style="background:#FBBF24;color:#78350F;padding:8px 14px;border-radius:99px;font-size:13px;font-weig