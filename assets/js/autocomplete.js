/* ============================================================
   autocomplete.js — Live search suggestions dropdown
   ============================================================
   USAGE:
     <input id="searchInput" type="text">
     <script>
       DukanAutocomplete.attach('searchInput', {
         onSelect: (item) => { ... }   // optional; default: navigate to /search.html
       });
     </script>

   Suggests:
     - matching categories (from /assets/data/categories.json)
     - matching businesses (via search_businesses RPC, limit 5)
   Debounced 250ms. Keyboard nav: ↑ ↓ Enter Esc.
============================================================ */
(function(global){
  'use strict';

  let CATS_CACHE = null;
  async function loadCats(){
    if (CATS_CACHE) return CATS_CACHE;
    try {
      const r = await fetch('/assets/data/categories.json');
      const d = await r.json();
      // Flatten parents + subs into a single searchable list
      const list = [];
      (d.parents || []).forEach(p => {
        list.push({ slug: p.slug, name: p.name, name_hi: p.name_hi, icon: p.icon, isParent: true });
        (p.subs || []).forEach(s => {
          list.push({ slug: s.slug, name: s.name, name_hi: s.name_hi, icon: s.icon, isParent: false });
        });
      });
      CATS_CACHE = list;
      return list;
    } catch(_){ CATS_CACHE = []; return []; }
  }

  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]); }

  function highlight(text, q){
    if (!q) return esc(text);
    const re = new RegExp('(' + q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + ')', 'ig');
    return esc(text).replace(re, '<b style="color:#FF6B1A">$1</b>');
  }

  function attach(inputId, opts){
    opts = opts || {};
    const input = document.getElementById(inputId);
    if (!input) return;
    if (input.dataset.acAttached) return; // idempotent
    input.dataset.acAttached = '1';
    input.setAttribute('autocomplete', 'off');

    // Position parent
    const wrap = input.parentElement;
    if (wrap && getComputedStyle(wrap).position === 'static') wrap.style.position = 'relative';

    // Dropdown element
    const dd = document.createElement('div');
    dd.className = 'dukan-ac-dd';
    dd.style.cssText = 'position:absolute;left:0;right:0;top:calc(100% + 4px);background:#fff;border:1px solid #e2e8f0;border-radius:14px;box-shadow:0 14px 36px rgba(15,23,42,.12);z-index:99;max-height:60vh;overflow-y:auto;display:none;font-family:\'Plus Jakarta Sans\',\'Manrope\',-apple-system,sans-serif';
    (wrap || input.parentNode).appendChild(dd);

    let items = [];
    let activeIdx = -1;
    let lastQ = '';
    let timer = null;

    function close(){ dd.style.display = 'none'; activeIdx = -1; }
    function open(){ dd.style.display = items.length ? '' : 'none'; }

    function paint(q){
      if (!items.length){ close(); return; }
      dd.innerHTML = items.map((it, i) => {
        const isActive = i === activeIdx;
        const subtitle = it.kind === 'cat'
          ? (it.isParent ? 'Category' : 'Sub-category')
          : (it.city ? '📍 ' + esc(it.city) : 'Shop');
        return '<a href="' + esc(it.href) + '" data-i="' + i + '" style="display:flex;align-items:center;gap:10px;padding:10px 14px;text-decoration:none;color:#0F172A;border-bottom:1px solid #f1f5f9;' + (isActive ? 'background:#FFF5EB;' : '') + 'transition:background .12s">'
          + '<span style="font-size:1.25rem;flex-shrink:0;width:30px;text-align:center">' + (it.icon || (it.kind === 'cat' ? '🏷' : '🏪')) + '</span>'
          + '<span style="flex:1;min-width:0">'
          + '<div style="font-size:14px;font-weight:600;line-height:1.3">' + highlight(it.name, q) + '</div>'
          + '<div style="font-size:11px;color:#94a3b8;font-weight:500;margin-top:1px">' + subtitle + '</div>'
          + '</span>'
          + '<span style="color:#cbd5e1;font-size:18px">→</span>'
          + '</a>';
      }).join('');
      open();
    }

    async function fetchSuggestions(q){
      const ql = q.toLowerCase().trim();
      if (!ql || ql.length < 2){ items = []; close(); return; }
      if (ql === lastQ) return;
      lastQ = ql;

      const all = await loadCats();
      const catMatches = all
        .filter(c => (c.name || '').toLowerCase().includes(ql) || (c.slug || '').toLowerCase().includes(ql))
        .slice(0, 5)
        .map(c => ({
          kind: 'cat', name: c.name, icon: c.icon, isParent: c.isParent,
          href: '/search.html?cat=' + encodeURIComponent(c.slug)
        }));

      let bizMatches = [];
      try {
        const c = window.ShopDB && ShopDB.client;
        if (c){
          const r = await c.rpc('search_businesses', {
            p_query: q, p_category: null, p_city_id: null, p_state_id: null, p_limit: 5, p_offset: 0
          });
          if (!r.error && Array.isArray(r.data)){
            bizMatches = r.data.map(b => ({
              kind: 'biz', name: b.name, icon: b.category_icon || '🏪', city: b.city_name,
              href: '/business.html?slug=' + encodeURIComponent(b.slug)
            }));
          }
        }
      } catch(_){}

      items = catMatches.concat(bizMatches);
      activeIdx = -1;
      paint(q);
    }

    input.addEventListener('input', function(){
      const q = input.value;
      clearTimeout(timer);
      timer = setTimeout(() => fetchSuggestions(q), 250);
    });

    input.addEventListener('focus', function(){
      if (items.length) open();
    });

    input.addEventListener('blur', function(){
      // delay close so click can register
      setTimeout(close, 200);
    });

    input.addEventListener('keydown', function(e){
      if (dd.style.display === 'none' || !items.length) return;
      if (e.key === 'ArrowDown'){ e.preventDefault(); activeIdx = (activeIdx + 1) % items.length; paint(lastQ); }
      else if (e.key === 'ArrowUp'){ e.preventDefault(); activeIdx = (activeIdx - 1 + items.length) % items.length; paint(lastQ); }
      else if (e.key === 'Enter' && activeIdx >= 0){
        e.preventDefault();
        const target = items[activeIdx];
        if (target) location.href = target.href;
      }
      else if (e.key === 'Escape'){ close(); }
    });

    dd.addEventListener('mousedown', function(e){
      // mousedown so the click registers before blur
      const a = e.target.closest('a[data-i]');
      if (!a) return;
      e.preventDefault();
      location.href = a.getAttribute('href');
    });
  }

  global.DukanAutocomplete = { attach };
})(window);
