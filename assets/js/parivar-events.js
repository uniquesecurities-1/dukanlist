/* ============================================================
   parivar-events.js — upcoming events of Dabwali Parivar organisations (v385, db/270)
   PVE.load(slug?)            → approved, upcoming events (public RPC)
   PVE.strip(el, events)      → "upcoming events" cards; a tap opens the pop-up
   PVE.popup(events, i)       → poster pop-up with date, place, share, call, next/previous
   PVE.auto(events, delayMs)  → on /parivar only: shows the nearest event this visitor has
                                not closed yet, once, after a short delay
   Needs parivar-common.js (PV).
   ============================================================ */
(function(global){
  'use strict';
  var PV = global.PV, esc = PV.esc, bi = PV.bi;
  var SEEN = 'pv_ev_seen_';
  // v386: "already seen" is kept in localStorage AND in a cookie — some phone in-app browsers
  // (WhatsApp / Instagram / Facebook) lose localStorage between visits, a cookie survives
  function cookieIds(){ var m = document.cookie.match(/(?:^|;\s*)pvevs=([^;]*)/); return m ? decodeURIComponent(m[1]).split('.').filter(Boolean) : []; }
  function markSeen(id){
    try { localStorage.setItem(SEEN + id, '1'); } catch(_){}
    try {
      var ids = cookieIds().filter(function(x){ return x !== id; }); ids.push(id);
      document.cookie = 'pvevs=' + encodeURIComponent(ids.slice(-25).join('.')) + ';path=/;max-age=' + (90 * 86400) + ';SameSite=Lax';
    } catch(_){}
  }
  function isSeen(id){
    try { if (localStorage.getItem(SEEN + id) === '1') return true; } catch(_){}
    return cookieIds().indexOf(id) !== -1;
  }

  function css(){
    if (document.getElementById('pveCss')) return;
    var st = document.createElement('style'); st.id = 'pveCss';
    st.textContent =
      '.pve-strip{display:flex;gap:10px;overflow-x:auto;padding:2px 2px 8px;scroll-snap-type:x mandatory;-webkit-overflow-scrolling:touch}' +
      '.pve-card{flex:0 0 250px;scroll-snap-align:start;display:flex;gap:10px;align-items:center;background:#fff;border:1px solid #FED7AA;border-radius:14px;padding:8px;cursor:pointer;text-align:left;font:inherit;color:inherit;box-shadow:0 2px 8px rgba(234,88,12,.08)}' +
      '.pve-card:hover{border-color:#FB923C;transform:translateY(-1px)}' +
      '.pve-card img{width:58px;height:72px;object-fit:cover;border-radius:9px;flex:0 0 auto;background:#F1F5F9}' +
      '.pve-card .d{font-size:.72rem;font-weight:800;color:#C2410C}' +
      '.pve-card .t{font-weight:800;font-size:.9rem;line-height:1.25;margin-top:2px;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}' +
      '.pve-card .o{font-size:.72rem;color:#64748B;margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}' +
      '.pve-bg{position:fixed;inset:0;background:rgba(15,23,42,.72);z-index:9999;display:flex;align-items:center;justify-content:center;padding:14px;animation:pveIn .2s ease}' +
      '@keyframes pveIn{from{opacity:0}to{opacity:1}}' +
      '.pve-box{background:#fff;border-radius:18px;max-width:440px;width:100%;max-height:94vh;overflow:auto;position:relative;box-shadow:0 24px 60px rgba(0,0,0,.35)}' +
      '.pve-x{position:absolute;top:8px;right:8px;width:38px;height:38px;border-radius:50%;border:0;background:rgba(15,23,42,.75);color:#fff;font-size:1.25rem;cursor:pointer;z-index:2;line-height:1}' +
      '.pve-tag{position:absolute;top:10px;left:10px;background:#EA580C;color:#fff;font-size:.72rem;font-weight:800;padding:4px 10px;border-radius:99px;z-index:2}' +
      '.pve-img{display:block;width:100%;max-height:58vh;object-fit:contain;background:#0F172A;border-radius:18px 18px 0 0}' +
      '.pve-body{padding:12px 16px 16px}' +
      '.pve-org{display:flex;align-items:center;gap:8px;font-size:.8rem;color:#475569;font-weight:700;text-decoration:none}' +
      '.pve-org img{width:26px;height:26px;border-radius:7px;object-fit:contain;background:#fff;border:1px solid #E2E8F0}' +
      '.pve-title{font-size:1.15rem;font-weight:900;margin:6px 0 4px;line-height:1.25;color:#0F172A}' +
      '.pve-meta{font-size:.88rem;color:#334155;line-height:1.6}' +
      '.pve-det{font-size:.84rem;color:#64748B;margin-top:6px;white-space:pre-wrap;line-height:1.5}' +
      '.pve-acts{display:flex;gap:8px;margin-top:12px;flex-wrap:wrap}' +
      '.pve-acts a,.pve-acts button{flex:1;min-width:120px;display:inline-flex;align-items:center;justify-content:center;gap:6px;padding:10px 12px;border-radius:11px;font-weight:800;font-size:.88rem;text-decoration:none;border:0;cursor:pointer;font-family:inherit}' +
      '.pve-wa{background:#25D366;color:#fff}.pve-call{background:#fff;color:#0F172A;border:1.5px solid #CBD5E1 !important}' +
      '.pve-nav{display:flex;justify-content:space-between;align-items:center;margin-top:12px;font-size:.8rem;color:#64748B}' +
      '.pve-nav button{background:#F1F5F9;border:0;border-radius:9px;padding:7px 12px;font-weight:800;cursor:pointer;font-family:inherit;color:#0F172A}' +
      '.pve-nav button:disabled{opacity:.35;cursor:default}' +
      'button.pve-tag{border:0;cursor:pointer;font-family:inherit;font-size:.78rem;padding:6px 12px}' +
      '.pve-day{font-weight:800;font-size:.84rem;color:#C2410C;margin:14px 0 6px}' +
      '.pve-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:10px}' +
      '.pve-tile{position:relative;display:flex;flex-direction:column;gap:3px;text-align:left;background:#fff;border:1px solid #E2E8F0;border-radius:12px;padding:6px;cursor:pointer;font-family:inherit;color:#0F172A}' +
      '.pve-tile:hover{border-color:#FB923C}' +
      '.pve-tile img{width:100%;aspect-ratio:4/5;object-fit:cover;border-radius:8px;background:#F1F5F9;display:block}' +
      '.pve-tile b{font-size:.84rem;line-height:1.25;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}' +
      '.pve-tile .pve-sub{font-size:.72rem;color:#64748B;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}' +
      '.pve-tile .pve-new{position:absolute;top:10px;left:10px;background:#EA580C;color:#fff;font-size:.66rem;font-weight:800;padding:2px 8px;border-radius:99px;z-index:1}';
    document.head.appendChild(st);
  }

  function hi(){ return document.documentElement.getAttribute('data-lang') === 'hi'; }
  function when(t, long, forceHi){
    var d = new Date(t), loc = (forceHi || hi()) ? 'hi-IN' : 'en-IN';
    var day = d.toLocaleDateString(loc, long ? { weekday:'long', day:'numeric', month:'long' } : { weekday:'short', day:'numeric', month:'short' });
    var time = d.toLocaleTimeString('en-IN', { hour:'numeric', minute:'2-digit', hour12:true });
    var today = new Date(); var tmr = new Date(Date.now() + 864e5);
    var same = function(a, b){ return a.toDateString() === b.toDateString(); };
    var H = forceHi || hi();
    var rel = same(d, today) ? (H ? 'आज' : 'Today') : same(d, tmr) ? (H ? 'कल' : 'Tomorrow') : '';
    return (rel ? rel + ', ' : '') + day + ' · ' + time;
  }
  function thumb(u, w, h){ return /res\.cloudinary\.com\//.test(u || '') ? u.replace('/upload/', '/upload/w_' + w + (h ? ',h_' + h + ',c_fill' : ',c_limit') + ',q_auto,f_auto/') : u; }
  function shareUrl(e){ return location.origin + '/parivar?event=' + encodeURIComponent(e.id); }

  // v387: up to 30; same date+time → shuffled on every visit, so no organisation is always first
  function load(slug){
    return PV.rpc('parivar_upcoming_events', { p_org_slug: slug || null, p_limit: 30 }).then(function(r){
      r = (r || []).slice().sort(function(a, b){ return new Date(a.starts_at) - new Date(b.starts_at); });
      for (var s = 0; s < r.length; ){
        var e = s; while (e + 1 < r.length && r[e + 1].starts_at === r[s].starts_at) e++;
        for (var k = e; k > s; k--){ var m = s + Math.floor(Math.random() * (k - s + 1)), t = r[k]; r[k] = r[m]; r[m] = t; }
        s = e + 1;
      }
      return r;
    }).catch(function(){ return []; });
  }
  function dayKey(t){ var d = new Date(t); return d.getFullYear() + '-' + d.getMonth() + '-' + d.getDate(); }
  function dayLabel(t){
    var d = new Date(t), today = new Date(), tmr = new Date(Date.now() + 864e5);
    var same = function(a, b){ return a.toDateString() === b.toDateString(); };
    var full = d.toLocaleDateString(hi() ? 'hi-IN' : 'en-IN', { weekday:'long', day:'numeric', month:'long' });
    return same(d, today) ? (hi() ? 'आज' : 'Today') + ' · ' + full : same(d, tmr) ? (hi() ? 'कल' : 'Tomorrow') + ' · ' + full : full;
  }
  function timeOf(t){ return new Date(t).toLocaleTimeString('en-IN', { hour:'numeric', minute:'2-digit', hour12:true }); }

  var STRIP_MAX = 8;
  function strip(el, events){
    css(); if (!el) return;
    if (!events.length){ el.innerHTML = ''; el.style.display = 'none'; return; }
    el.style.display = '';
    var more = events.length > STRIP_MAX;
    el.innerHTML = '<h2 class="pv-h2">🗓 ' + bi('Upcoming events', 'आने वाले कार्यक्रम') + (events.length > 1 ? ' <span style="color:#64748B;font-weight:600;font-size:.85rem">(' + events.length + ')</span>' : '') + '</h2><div class="pve-strip">'
      + events.slice(0, STRIP_MAX).map(function(e, i){
          return '<button type="button" class="pve-card" data-i="' + i + '"><img src="' + esc(thumb(e.poster, 116, 144)) + '" alt="" loading="lazy">'
            + '<div style="min-width:0"><div class="d">' + esc(when(e.starts_at)) + '</div><div class="t">' + esc(e.title) + '</div><div class="o">' + esc(hi() && e.org_hi ? e.org_hi : e.org) + '</div></div></button>';
        }).join('')
      + (more ? '<button type="button" class="pve-card pve-all" data-all="1" style="flex:0 0 150px;justify-content:center;font-weight:800;color:#C2410C">' + bi('See all', 'सब देखें') + ' (' + events.length + ') →</button>' : '')
      + '</div>';
    el.querySelectorAll('.pve-card').forEach(function(b){ b.addEventListener('click', function(){
      if (b.getAttribute('data-all')) popup(events, 0, 'list'); else popup(events, +b.getAttribute('data-i'));
    }); });
  }

  var OPEN = null;
  function close(){ if (OPEN){ OPEN.remove(); OPEN = null; document.removeEventListener('keydown', onKey); } }
  function onKey(e){ if (e.key === 'Escape') close(); }
  // view 'list' = all upcoming events grouped by day (new ones marked); 'detail' = one big poster
  function popup(events, i, view){
    css(); close();
    i = Math.max(0, Math.min(i || 0, events.length - 1));
    view = view === 'list' && events.length > 1 ? 'list' : 'detail';
    var bg = document.createElement('div'); bg.className = 'pve-bg'; OPEN = bg;
    function drawList(){
      var groups = [], last = null;
      events.forEach(function(e, k){ var key = dayKey(e.starts_at); if (key !== last){ groups.push({ t: e.starts_at, items: [] }); last = key; } groups[groups.length - 1].items.push(k); });
      bg.innerHTML = '<div class="pve-box" role="dialog" aria-modal="true"><button class="pve-x" aria-label="Close">×</button>'
        + '<div class="pve-body" style="padding-top:16px"><div class="pve-title" style="margin:0 44px 2px 0">🗓 ' + bi('Upcoming events', 'आने वाले कार्यक्रम') + ' (' + events.length + ')</div>'
        + '<div class="pve-det" style="margin-top:0">' + bi('Tap a poster to see it in full.', 'पूरा पोस्टर देखने के लिए उस पर टैप करें।') + '</div>'
        + groups.map(function(g){
            return '<div class="pve-day">' + esc(dayLabel(g.t)) + ' · ' + g.items.length + ' ' + (g.items.length > 1 ? bi('events', 'कार्यक्रम') : bi('event', 'कार्यक्रम')) + '</div><div class="pve-grid">'
              + g.items.map(function(k){
                  var e = events[k], fresh = !isSeen(e.id);
                  return '<button type="button" class="pve-tile" data-k="' + k + '">' + (fresh ? '<span class="pve-new">' + bi('New', 'नया') + '</span>' : '')
                    + '<img src="' + esc(thumb(e.poster, 240, 300)) + '" alt="" loading="lazy"><b>' + esc(e.title) + '</b><span class="pve-sub">' + esc(timeOf(e.starts_at)) + ' · ' + esc(hi() && e.org_hi ? e.org_hi : e.org) + '</span></button>';
                }).join('') + '</div>';
          }).join('')
        + '</div></div>';
      bg.querySelector('.pve-x').onclick = close;
      bg.querySelectorAll('.pve-tile').forEach(function(b){ b.onclick = function(){ i = +b.getAttribute('data-k'); view = 'detail'; draw(); }; });
    }
    function drawDetail(){
      var e = events[i];
      markSeen(e.id);
      var place = e.venue ? '<div>📍 ' + esc(e.venue) + '</div>' : '';
      // WhatsApp text in Hindi (date too), no emoji — it shows as ? on some phones
      var msg = (e.org_hi || e.org || '') + ' का कार्यक्रम: ' + e.title + '\n' + when(e.starts_at, true, true) + (e.venue ? '\nस्थान: ' + e.venue : '') + '\n\nपूरी जानकारी और पोस्टर: ' + shareUrl(e);
      var c = String(e.contact || '').replace(/\D/g, '').slice(-10);
      bg.innerHTML = '<div class="pve-box" role="dialog" aria-modal="true" aria-label="' + esc(e.title) + '">'
        + '<button class="pve-x" aria-label="Close">×</button>'
        + (events.length > 1 ? '<button class="pve-tag pve-back" type="button">← ' + bi('All events', 'सभी कार्यक्रम') + ' (' + events.length + ')</button>' : '<span class="pve-tag">🗓 ' + bi('Upcoming', 'आने वाला कार्यक्रम') + '</span>')
        + '<img class="pve-img" src="' + esc(thumb(e.poster, 900)) + '" alt="' + esc(e.title) + '">'
        + '<div class="pve-body">'
        + '<a class="pve-org" href="/sanstha/' + encodeURIComponent(e.org_slug) + '">' + (e.org_logo ? '<img src="' + esc(thumb(e.org_logo, 60, 60)) + '" alt="">' : '🏛') + esc(hi() && e.org_hi ? e.org_hi : e.org) + ' →</a>'
        + '<div class="pve-title">' + esc(e.title) + '</div>'
        + '<div class="pve-meta"><div>📅 ' + esc(when(e.starts_at, true)) + '</div>' + place + '</div>'
        + (e.details ? '<div class="pve-det">' + esc(e.details) + '</div>' : '')
        + '<div class="pve-acts"><a class="pve-wa" href="https://wa.me/?text=' + encodeURIComponent(msg) + '" target="_blank" rel="noopener">💬 ' + bi('Share on WhatsApp', 'WhatsApp पर भेजें') + '</a>'
        + (c.length === 10 ? '<a class="pve-call" href="tel:+91' + c + '">📞 ' + bi('Call', 'कॉल करें') + '</a>' : '') + '</div>'
        + (events.length > 1 ? '<div class="pve-nav"><button data-nav="-1"' + (i === 0 ? ' disabled' : '') + '>← ' + bi('Previous', 'पिछला') + '</button><span>' + (i + 1) + ' / ' + events.length + '</span>'
            + '<button data-nav="1"' + (i === events.length - 1 ? ' disabled' : '') + '>' + bi('Next', 'अगला') + ' →</button></div>' : '')
        + '</div></div>';
      bg.querySelector('.pve-x').onclick = close;
      var back = bg.querySelector('.pve-back'); if (back) back.onclick = function(){ view = 'list'; draw(); };
      bg.querySelectorAll('[data-nav]').forEach(function(b){ b.onclick = function(){ i = Math.max(0, Math.min(events.length - 1, i + (+b.getAttribute('data-nav')))); draw(); }; });
    }
    function draw(){ if (view === 'list') drawList(); else drawDetail(); var bx = bg.querySelector('.pve-box'); if (bx) bx.scrollTop = 0; }
    bg.addEventListener('click', function(ev){ if (ev.target === bg) close(); });
    document.addEventListener('keydown', onKey);
    draw(); document.body.appendChild(bg);
  }

  // /parivar only, after a short delay: one event not seen yet → its poster; two or more → the
  // "all events" view with the new ones marked. A poster counts as seen once it has been opened,
  // so the ones not opened yet come back on the next visit. ?event=<id> opens that event once.
  function auto(events, delay){
    if (!events.length) return;
    var want = new URLSearchParams(location.search).get('event');
    if (want){
      try { var u = new URL(location.href); u.searchParams.delete('event'); history.replaceState(null, '', u.pathname + u.search + u.hash); } catch(_){}
      var k = events.findIndex(function(e){ return e.id === want; });
      if (k !== -1 && !isSeen(want)){ popup(events, k); return; }
    }
    var fresh = events.filter(function(e){ return !isSeen(e.id); });
    if (!fresh.length) return;
    setTimeout(function(){
      if (OPEN) return;
      if (fresh.length === 1) popup(events, events.indexOf(fresh[0]));
      else popup(events, 0, 'list');
    }, delay == null ? 2500 : delay);
  }

  global.PVE = { load: load, strip: strip, popup: popup, auto: auto, when: when };
})(window);
