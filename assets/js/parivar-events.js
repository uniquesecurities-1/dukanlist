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
      '.pve-nav button:disabled{opacity:.35;cursor:default}';
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

  function load(slug){
    return PV.rpc('parivar_upcoming_events', { p_org_slug: slug || null, p_limit: 12 }).then(function(r){ return r || []; }).catch(function(){ return []; });
  }

  function strip(el, events){
    css(); if (!el) return;
    if (!events.length){ el.innerHTML = ''; el.style.display = 'none'; return; }
    el.style.display = '';
    el.innerHTML = '<h2 class="pv-h2">🗓 ' + bi('Upcoming events', 'आने वाले कार्यक्रम') + '</h2><div class="pve-strip">'
      + events.map(function(e, i){
          return '<button type="button" class="pve-card" data-i="' + i + '"><img src="' + esc(thumb(e.poster, 116, 144)) + '" alt="" loading="lazy">'
            + '<div style="min-width:0"><div class="d">' + esc(when(e.starts_at)) + '</div><div class="t">' + esc(e.title) + '</div><div class="o">' + esc(hi() && e.org_hi ? e.org_hi : e.org) + '</div></div></button>';
        }).join('') + '</div>';
    el.querySelectorAll('.pve-card').forEach(function(b){ b.addEventListener('click', function(){ popup(events, +b.getAttribute('data-i')); }); });
  }

  var OPEN = null;
  function close(){ if (OPEN){ OPEN.remove(); OPEN = null; document.removeEventListener('keydown', onKey); } }
  function onKey(e){ if (e.key === 'Escape') close(); }
  function popup(events, i){
    css(); close();
    i = Math.max(0, Math.min(i || 0, events.length - 1));
    var bg = document.createElement('div'); bg.className = 'pve-bg'; OPEN = bg;
    function draw(){
      var e = events[i];
      markSeen(e.id);
      var place = e.venue ? '<div>📍 ' + esc(e.venue) + '</div>' : '';
      // WhatsApp text in Hindi (date too), no emoji — it shows as ? on some phones
      var msg = (e.org_hi || e.org || '') + ' का कार्यक्रम: ' + e.title + '\n' + when(e.starts_at, true, true) + (e.venue ? '\nस्थान: ' + e.venue : '') + '\n\nपूरी जानकारी और पोस्टर: ' + shareUrl(e);
      var c = String(e.contact || '').replace(/\D/g, '').slice(-10);
      bg.innerHTML = '<div class="pve-box" role="dialog" aria-modal="true" aria-label="' + esc(e.title) + '">'
        + '<button class="pve-x" aria-label="Close">×</button><span class="pve-tag">🗓 ' + bi('Upcoming', 'आने वाला कार्यक्रम') + '</span>'
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
      bg.querySelectorAll('[data-nav]').forEach(function(b){ b.onclick = function(){ i = Math.max(0, Math.min(events.length - 1, i + (+b.getAttribute('data-nav')))); draw(); }; });
    }
    bg.addEventListener('click', function(ev){ if (ev.target === bg) close(); });
    document.addEventListener('keydown', onKey);
    draw(); document.body.appendChild(bg);
  }

  // /parivar only: the nearest event this visitor hasn't closed, once, after a short delay.
  // ?event=<id> opens that event straight away (a shared link).
  function auto(events, delay){
    if (!events.length) return;
    var want = new URLSearchParams(location.search).get('event');
    if (want){
      // a shared event link opens that poster once; the ?event= part is then dropped from the
      // address, so a reload / reopening the tab does not bring it back
      try { var u = new URL(location.href); u.searchParams.delete('event'); history.replaceState(null, '', u.pathname + u.search + u.hash); } catch(_){}
      var k = events.findIndex(function(e){ return e.id === want; });
      if (k !== -1 && !isSeen(want)){ popup(events, k); return; }
    }
    var first = events.findIndex(function(e){ return !isSeen(e.id); });
    if (first === -1) return;
    setTimeout(function(){ if (!OPEN) popup(events, first); }, delay == null ? 2500 : delay);
  }

  global.PVE = { load: load, strip: strip, popup: popup, auto: auto, when: when };
})(window);
