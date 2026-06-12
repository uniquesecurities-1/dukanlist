/* ============================================================
   shortlist.js — Save shops to a localStorage-backed shortlist.
   No login required. Cross-page consistent.
   ============================================================
   Public API:
     DukanShortlist.add(biz)         → bool (true on add, false if exists)
     DukanShortlist.remove(slug)     → bool
     DukanShortlist.toggle(biz)      → 'added' | 'removed'
     DukanShortlist.has(slug)        → bool
     DukanShortlist.list()           → Array<biz>
     DukanShortlist.count()          → int
     DukanShortlist.clear()          → void
     DukanShortlist.onChange(fn)     → unsubscribe()

     // UI helpers
     DukanShortlist.heartBtn(biz)    → HTML string (insertable into cards)
     DukanShortlist.bindAll()        → bind every .dl-heart button in DOM
     DukanShortlist.toast(msg)       → bottom toast (optional)

   Storage:
     key: 'dukan_shortlist_v1'
     value: array of slim biz objects { slug, name, photo, city, category, ts }
     Max: 50 items (oldest drops off)
============================================================ */
(function(global){
  'use strict';

  var KEY = 'dukan_shortlist_v1';
  var MAX = 50;
  var listeners = [];

  function read(){
    try {
      var raw = localStorage.getItem(KEY);
      if (!raw) return [];
      var arr = JSON.parse(raw);
      return Array.isArray(arr) ? arr : [];
    } catch(_){ return []; }
  }
  function write(arr){
    try {
      localStorage.setItem(KEY, JSON.stringify(arr.slice(0, MAX)));
      notify();
      return true;
    } catch(_){ return false; }
  }
  function notify(){
    var c = count();
    listeners.forEach(function(fn){ try { fn(c); } catch(_){} });
  }

  function slim(b){
    if (!b || !b.slug) return null;
    return {
      slug:      String(b.slug),
      name:      String(b.name || 'Shop'),
      photo:     (Array.isArray(b.photos) && b.photos.length ? b.photos[0]
                : (typeof b.photo === 'string' ? b.photo : null)),
      city:      (b.geo_cities && b.geo_cities.name) || b.city_name || b.city || '',
      category:  (b.categories && b.categories.name) || b.category_name || b.category || '',
      icon:      (b.categories && b.categories.icon) || b.category_icon || '',
      ts:        Date.now()
    };
  }

  function has(slug){
    if (!slug) return false;
    var arr = read();
    for (var i = 0; i < arr.length; i++){
      if (arr[i].slug === slug) return true;
    }
    return false;
  }
  function count(){ return read().length; }
  function list(){ return read(); }

  function add(biz){
    var s = slim(biz);
    if (!s) return false;
    var arr = read();
    if (arr.some(function(x){ return x.slug === s.slug; })) return false;
    arr.unshift(s);
    write(arr);
    return true;
  }
  function remove(slug){
    if (!slug) return false;
    var arr = read();
    var i = arr.findIndex(function(x){ return x.slug === slug; });
    if (i < 0) return false;
    arr.splice(i, 1);
    write(arr);
    return true;
  }
  function toggle(biz){
    if (!biz || !biz.slug) return null;
    if (has(biz.slug)){ remove(biz.slug); return 'removed'; }
    add(biz); return 'added';
  }
  function clear(){ write([]); }

  // Subscribe to changes (badge counters etc.)
  function onChange(fn){
    if (typeof fn !== 'function') return function(){};
    listeners.push(fn);
    // Also fire when storage changes from another tab
    if (!global.__dl_shortlist_storage_bound){
      global.__dl_shortlist_storage_bound = true;
      window.addEventListener('storage', function(ev){
        if (ev.key === KEY) notify();
      });
    }
    // Initial call
    try { fn(count()); } catch(_){}
    return function unsubscribe(){
      var i = listeners.indexOf(fn);
      if (i >= 0) listeners.splice(i, 1);
    };
  }

  // ===== UI helpers =====

  function escAttr(s){
    return String(s == null ? '' : s).replace(/[&<>"']/g, function(c){
      return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c];
    });
  }

  // Returns an HTML string. Caller injects via innerHTML and then calls
  // DukanShortlist.bindAll() to wire click handlers.
  function heartBtn(biz, opts){
    opts = opts || {};
    var slug = biz && biz.slug ? String(biz.slug) : '';
    if (!slug) return '';
    var size = opts.size || 'md';
    var active = has(slug);
    // Encode biz as a base64-encoded JSON payload so clicks can re-add
    // without needing the parent scope. Strings are HTML-safe.
    var payload = '';
    try {
      payload = btoa(unescape(encodeURIComponent(JSON.stringify(slim(biz) || { slug: slug }))));
    } catch(_){
      payload = btoa('{"slug":"' + slug.replace(/"/g, '') + '"}');
    }
    var sizePx = (size === 'sm') ? 30 : 36;
    var fontPx = (size === 'sm') ? 14 : 18;
    return '<button type="button"'
      + ' class="dl-heart' + (active ? ' dl-heart-on' : '') + '"'
      + ' data-slug="' + escAttr(slug) + '"'
      + ' data-payload="' + escAttr(payload) + '"'
      + ' aria-label="' + (active ? 'Remove from Shortlist' : 'Save to Shortlist') + '"'
      + ' title="' + (active ? 'Saved — tap to remove' : 'Save to Shortlist') + '"'
      + ' style="width:' + sizePx + 'px;height:' + sizePx + 'px;font-size:' + fontPx + 'px">'
      + (active ? '❤️' : '🤍')
      + '</button>';
  }

  // Single delegated click handler — works for any .dl-heart added later
  // by async card renders. No explicit bindAll() per render needed.
  function handleHeartClick(ev){
    var btn = ev.target;
    while (btn && btn !== document.body && !(btn.classList && btn.classList.contains('dl-heart'))){
      btn = btn.parentNode;
    }
    if (!btn || !btn.classList || !btn.classList.contains('dl-heart')) return;
    ev.preventDefault();
    ev.stopPropagation();
    var slug = btn.dataset.slug;
    if (!slug) return;
    var biz = { slug: slug };
    try {
      var raw = atob(btn.dataset.payload || '');
      var decoded = JSON.parse(decodeURIComponent(escape(raw)));
      if (decoded && decoded.slug) biz = decoded;
    } catch(_){}
    var action = toggle(biz);
    // Update THIS button (the one clicked)
    if (action === 'added'){
      btn.innerHTML = '❤️';
      btn.classList.add('dl-heart-on');
      btn.setAttribute('aria-label', 'Remove from Shortlist');
      btn.setAttribute('title', 'Saved — tap to remove');
      toast('❤️ Saved to your Shortlist');
    } else if (action === 'removed'){
      btn.innerHTML = '🤍';
      btn.classList.remove('dl-heart-on');
      btn.setAttribute('aria-label', 'Save to Shortlist');
      btn.setAttribute('title', 'Save to Shortlist');
      toast('Removed from Shortlist');
    }
    // ALSO sync any OTHER buttons rendering the same shop
    document.querySelectorAll('.dl-heart[data-slug="' + slug.replace(/"/g, '') + '"]').forEach(function(other){
      if (other === btn) return;
      if (has(slug)){
        other.innerHTML = '❤️';
        other.classList.add('dl-heart-on');
      } else {
        other.innerHTML = '🤍';
        other.classList.remove('dl-heart-on');
      }
    });
  }

  // bindAll() retained as a no-op convenience wrapper. Now only refreshes
  // visual state of existing buttons (e.g., if the page was rendered while
  // the user had added the same shop on another tab).
  function bindAll(){
    document.querySelectorAll('.dl-heart').forEach(function(btn){
      var slug = btn.dataset.slug;
      if (!slug) return;
      var on = has(slug);
      btn.classList.toggle('dl-heart-on', on);
      btn.innerHTML = on ? '❤️' : '🤍';
    });
  }

  function toast(msg){
    var t = document.createElement('div');
    t.textContent = msg;
    t.style.cssText = 'position:fixed;bottom:80px;left:50%;transform:translateX(-50%);'
      + 'background:#0F172A;color:#fff;padding:11px 20px;border-radius:99px;font-size:.86rem;'
      + 'font-weight:700;z-index:99998;box-shadow:0 10px 30px rgba(15,23,42,.35);'
      + 'opacity:0;transition:opacity .15s ease, transform .25s ease;font-family:inherit;'
      + 'pointer-events:none';
    document.body.appendChild(t);
    requestAnimationFrame(function(){
      t.style.opacity = '1';
      t.style.transform = 'translateX(-50%) translateY(-6px)';
    });
    setTimeout(function(){
      t.style.opacity = '0';
      setTimeout(function(){ try { t.remove(); } catch(_){} }, 250);
    }, 2200);
  }

  // ===== Inject default CSS once =====
  function injectCSS(){
    if (document.getElementById('dl-heart-css')) return;
    var s = document.createElement('style');
    s.id = 'dl-heart-css';
    s.textContent = ''
      + '.dl-heart{ display:inline-flex; align-items:center; justify-content:center; '
      + '  border-radius:50%; background:rgba(255,255,255,.94); border:1px solid rgba(15,23,42,.06); '
      + '  cursor:pointer; transition:transform .12s, box-shadow .15s, background .15s; '
      + '  box-shadow:0 2px 6px rgba(15,23,42,.08); font-family:inherit; padding:0; '
      + '  -webkit-tap-highlight-color:transparent; line-height:1; }'
      + '.dl-heart:hover{ transform:scale(1.08); background:#FEF2F2; box-shadow:0 4px 12px rgba(220,38,38,.18) }'
      + '.dl-heart:active{ transform:scale(.92) }'
      + '.dl-heart-on{ background:#FEE2E2; border-color:#FCA5A5 }'
      + '.dl-heart-on:hover{ background:#FECACA }';
    document.head.appendChild(s);
  }

  function init(){
    injectCSS();
    bindAll();
    // Delegated click handler — fires for any .dl-heart, present or future
    if (!global.__dl_heart_delegated){
      global.__dl_heart_delegated = true;
      document.addEventListener('click', handleHeartClick, true);
    }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();

  global.DukanShortlist = {
    add: add, remove: remove, toggle: toggle,
    has: has, list: list, count: count, clear: clear,
    onChange: onChange,
    heartBtn: heartBtn, bindAll: bindAll, toast: toast
  };
})(window);
