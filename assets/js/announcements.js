/* ============================================================
   announcements.js — Fetch + display active admin announcements
   ============================================================
   Auto-loads on any public page that includes this script.
   Reads from list_active_announcements() RPC, picks the top-priority
   one user hasn't already dismissed, shows it as banner (top of page)
   or modal (centered overlay).
============================================================ */
(function(global){
  'use strict';

  const DISMISS_KEY = 'dukan_ann_dismissed_v1';

  function loadDismissed(){
    try { return JSON.parse(localStorage.getItem(DISMISS_KEY) || '{}'); }
    catch(_){ return {}; }
  }
  function saveDismissed(map){
    try { localStorage.setItem(DISMISS_KEY, JSON.stringify(map)); } catch(_){}
  }
  function isDismissed(id){
    const m = loadDismissed();
    const ts = m[id];
    if (!ts) return false;
    // Dismissals expire after 7 days
    return (Date.now() - ts) < 7 * 24 * 60 * 60 * 1000;
  }
  function dismiss(id){
    const m = loadDismissed();
    m[id] = Date.now();
    saveDismissed(m);
  }

  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]); }

  function inferAudience(){
    // Customer pages vs shopkeeper-panel pages
    if (/^\/panel\//.test(location.pathname)) return 'shopkeeper';
    if (/^\/admin\//.test(location.pathname)) return 'admin';
    return 'customer';
  }

  const COLORS = {
    saffron: { bg: 'linear-gradient(135deg,#FF6B1A,#E55100)', text: '#fff', accent: '#fff' },
    indigo:  { bg: 'linear-gradient(135deg,#4F46E5,#3730A3)', text: '#fff', accent: '#FCD34D' },
    emerald: { bg: 'linear-gradient(135deg,#10B981,#047857)', text: '#fff', accent: '#fff' },
    amber:   { bg: 'linear-gradient(135deg,#F59E0B,#B45309)', text: '#fff', accent: '#fff' },
    red:     { bg: 'linear-gradient(135deg,#EF4444,#B91C1C)', text: '#fff', accent: '#FCD34D' }
  };

  function renderBanner(a){
    if (document.getElementById('dukanAnnBanner')) return;
    const c = COLORS[a.color_scheme] || COLORS.saffron;
    const el = document.createElement('div');
    el.id = 'dukanAnnBanner';
    el.style.cssText = 'position:relative;background:' + c.bg + ';color:' + c.text + ';padding:12px 18px;font-family:\'Plus Jakarta Sans\',\'Manrope\',-apple-system,sans-serif;z-index:80;box-shadow:0 2px 8px rgba(15,23,42,.10)';
    el.innerHTML = '<div style="max-width:1140px;margin:0 auto;display:flex;align-items:center;gap:12px;flex-wrap:wrap">'
      + (a.image_url ? '<img src="' + esc(a.image_url) + '" alt="" style="width:34px;height:34px;border-radius:8px;object-fit:cover;background:rgba(255,255,255,.2);flex-shrink:0">' : '')
      + '<div style="flex:1;min-width:200px;line-height:1.4">'
        + '<div style="font-weight:800;font-size:14.5px;letter-spacing:-.01em">' + esc(a.title) + '</div>'
        + (a.body ? '<div style="font-size:12.5px;opacity:.92;margin-top:2px">' + esc(a.body) + '</div>' : '')
      + '</div>'
      + (a.link_url ? '<a href="' + esc(a.link_url) + '" target="_blank" rel="noopener" style="background:rgba(255,255,255,.18);color:' + c.text + ';padding:7px 16px;border-radius:99px;font-weight:700;font-size:12.5px;text-decoration:none;white-space:nowrap;border:1px solid rgba(255,255,255,.3)">' + esc(a.link_label || 'Learn more') + ' →</a>' : '')
      + (a.dismissible ? '<button onclick="DukanAnn.dismiss(\'' + a.id + '\')" aria-label="Dismiss" style="background:transparent;border:0;color:' + c.text + ';opacity:.85;cursor:pointer;font-size:20px;line-height:1;padding:2px 6px;flex-shrink:0">×</button>' : '')
    + '</div>';
    // Insert at very top of body
    document.body.insertBefore(el, document.body.firstChild);
  }

  function renderModal(a){
    if (document.getElementById('dukanAnnModal')) return;
    const c = COLORS[a.color_scheme] || COLORS.saffron;
    const bg = document.createElement('div');
    bg.id = 'dukanAnnModal';
    bg.style.cssText = 'position:fixed;inset:0;background:rgba(15,23,42,.55);display:flex;align-items:center;justify-content:center;z-index:99998;padding:18px;font-family:\'Plus Jakarta Sans\',\'Manrope\',-apple-system,sans-serif;animation:annFade .2s ease';
    bg.innerHTML = '<style>'
      + '@keyframes annFade{from{opacity:0}to{opacity:1}}'
      + '@keyframes annSlide{from{transform:translateY(24px) scale(.97);opacity:0}to{transform:translateY(0) scale(1);opacity:1}}'
      + '</style>'
      + '<div style="background:#fff;border-radius:20px;max-width:460px;width:100%;overflow:hidden;box-shadow:0 24px 60px rgba(0,0,0,.3);animation:annSlide .28s cubic-bezier(.22,.61,.36,1)">'
        + (a.image_url ? '<img src="' + esc(a.image_url) + '" alt="" style="width:100%;display:block;max-height:240px;object-fit:cover">' : '<div style="height:8px;background:' + c.bg + '"></div>')
        + '<div style="padding:24px">'
          + '<div style="display:flex;justify-content:space-between;gap:12px;align-items:flex-start;margin-bottom:10px">'
            + '<h3 style="font-size:20px;font-weight:800;color:#0F172A;letter-spacing:-.02em;margin:0;line-height:1.2">' + esc(a.title) + '</h3>'
            + (a.dismissible ? '<button onclick="DukanAnn.dismiss(\'' + a.id + '\')" aria-label="Close" style="background:#F1F5F9;border:0;width:32px;height:32px;border-radius:50%;font-size:18px;cursor:pointer;color:#475569;flex-shrink:0;line-height:1">×</button>' : '')
          + '</div>'
          + (a.body ? '<p style="font-size:14.5px;color:#475569;line-height:1.65;margin:0 0 16px 0">' + esc(a.body) + '</p>' : '')
          + (a.link_url ? '<a href="' + esc(a.link_url) + '" target="_blank" rel="noopener" style="display:inline-block;background:' + c.bg + ';color:' + c.text + ';padding:12px 24px;border-radius:11px;font-weight:800;font-size:14px;text-decoration:none;box-shadow:0 4px 14px rgba(255,107,26,.3)">' + esc(a.link_label || 'Learn more') + ' →</a>' : '')
          + (a.dismissible ? '<button onclick="DukanAnn.dismiss(\'' + a.id + '\')" style="background:transparent;border:0;color:#94a3b8;font-size:12px;font-weight:600;cursor:pointer;margin-left:12px;padding:12px">Not now</button>' : '')
        + '</div>'
      + '</div>';
    if (a.dismissible){
      bg.addEventListener('click', e => { if (e.target === bg) dismissPublic(a.id); });
    }
    document.body.appendChild(bg);
  }

  function dismissPublic(id){
    dismiss(id);
    const b = document.getElementById('dukanAnnBanner'); if (b) b.remove();
    const m = document.getElementById('dukanAnnModal'); if (m) m.remove();
  }

  async function load(){
    const c = window.ShopDB && ShopDB.client;
    if (!c) return;
    try {
      const r = await c.rpc('list_active_announcements');
      if (r.error || !Array.isArray(r.data) || !r.data.length) return;
      const aud = inferAudience();
      // Filter: target matches + not already dismissed
      const list = r.data.filter(a => (a.target === 'all' || a.target === aud) && !isDismissed(a.id));
      if (!list.length) return;
      // Show top-priority one (sorted ASC priority server-side)
      // If both banner and modal exist in active list, show only the highest priority one.
      const top = list[0];
      if (top.display_type === 'modal'){
        // small delay so page settles, then show
        setTimeout(() => renderModal(top), 800);
      } else {
        renderBanner(top);
      }
    } catch(_){}
  }

  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', load);
  } else {
    load();
  }

  global.DukanAnn = { load, dismiss: dismissPublic };
})(window);
