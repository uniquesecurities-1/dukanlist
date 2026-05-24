/* ============================================================
   compare.js — Side-by-side shop comparison state
   ============================================================
   Stores up to 2 shop IDs in localStorage. Renders a sticky
   bottom bar on the page while any shop is selected.

   API:
     DukanCompare.add(shop)        // {id, name, photo}
     DukanCompare.remove(id)
     DukanCompare.clear()
     DukanCompare.has(id)          -> boolean
     DukanCompare.list()           -> [{id, name, photo}]
     DukanCompare.attachBar()      // mount the sticky bar (idempotent)

   On the results pages: cards include a small checkbox bound to
   DukanCompare.toggle(card.dataset). Selecting the 2nd shop opens
   /compare.html?ids=A,B in a new tab (or replaces if same tab).
============================================================ */
(function(global){
  'use strict';
  var KEY = 'dl_compare';
  var MAX = 2;

  function load(){
    try {
      var raw = localStorage.getItem(KEY);
      if (!raw) return [];
      var arr = JSON.parse(raw);
      return Array.isArray(arr) ? arr.slice(0, MAX) : [];
    } catch(_){ return []; }
  }
  function save(arr){
    try { localStorage.setItem(KEY, JSON.stringify(arr.slice(0, MAX))); } catch(_){}
  }
  function list(){ return load(); }
  function has(id){ return load().some(function(s){ return String(s.id) === String(id); }); }

  function add(shop){
    if (!shop || !shop.id) return false;
    var arr = load();
    if (has(shop.id)) return true;
    if (arr.length >= MAX) return false;
    arr.push({ id: shop.id, name: shop.name || 'Shop', photo: shop.photo || null, slug: shop.slug || null });
    save(arr);
    renderBar();
    return true;
  }
  function remove(id){
    var arr = load().filter(function(s){ return String(s.id) !== String(id); });
    save(arr);
    renderBar();
    // Also sync any checkboxes on the page
    document.querySelectorAll('input[data-cmp-id="' + id + '"]').forEach(function(cb){ cb.checked = false; });
    var lbl = document.querySelector('[data-cmp-label-id="' + id + '"]');
    if (lbl) lbl.classList.remove('cmp-selected');
  }
  function clear(){
    save([]);
    renderBar();
    document.querySelectorAll('input[data-cmp-id]').forEach(function(cb){ cb.checked = false; });
    document.querySelectorAll('[data-cmp-label-id]').forEach(function(l){ l.classList.remove('cmp-selected'); });
  }
  function toggle(shop){
    if (has(shop.id)){ remove(shop.id); return false; }
    return add(shop);
  }

  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"']/g, function(c){
    return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c];
  }); }

  function renderBar(){
    var bar = document.getElementById('dukanCompareBar');
    var arr = load();
    if (!bar){
      if (!arr.length) return;
      bar = document.createElement('div');
      bar.id = 'dukanCompareBar';
      document.body.appendChild(bar);
    }
    if (!arr.length){ bar.remove(); return; }

    var slots = '';
    for (var i = 0; i < MAX; i++){
      var s = arr[i];
      if (s){
        slots += '<div class="cmp-slot filled">'
          + (s.photo
              ? '<img src="' + esc(s.photo) + '" alt="">'
              : '<div class="cmp-ph">🏪</div>')
          + '<div class="cmp-name">' + esc(s.name) + '</div>'
          + '<button class="cmp-x" onclick="DukanCompare.remove(\'' + esc(s.id) + '\')" aria-label="Remove">×</button>'
          + '</div>';
      } else {
        slots += '<div class="cmp-slot empty"><span>+ Add a shop to compare</span></div>';
      }
    }
    var canCompare = arr.length === MAX;
    var ids = arr.map(function(s){ return encodeURIComponent(s.id); }).join(',');
    bar.innerHTML =
      '<div class="cmp-inner">'
        + '<div class="cmp-title">⚖️ Compare</div>'
        + '<div class="cmp-slots">' + slots + '</div>'
        + '<div class="cmp-actions">'
          + (canCompare
              ? '<a href="/compare.html?ids=' + ids + '" class="cmp-go">Compare →</a>'
              : '<button class="cmp-go" disabled>Add 1 more</button>')
          + '<button class="cmp-clear" onclick="DukanCompare.clear()">Clear</button>'
        + '</div>'
      + '</div>';
  }

  function attachBar(){
    renderBar();
    // Listen for storage events from other tabs
    window.addEventListener('storage', function(e){
      if (e.key === KEY) renderBar();
    });
  }

  // Checkbox markup helper — pages call this to render the inline picker
  function checkboxHTML(shop){
    var checked = has(shop.id) ? ' checked' : '';
    var sel = has(shop.id) ? ' cmp-selected' : '';
    return '<label class="cmp-pick' + sel + '" data-cmp-label-id="' + esc(shop.id) + '" '
      + 'onclick="event.stopPropagation();" '
      + 'title="Compare this shop">'
      + '<input type="checkbox" data-cmp-id="' + esc(shop.id) + '"' + checked
      +   ' onchange="DukanCompare._onCheck(this, ' + JSON.stringify(shop).replace(/"/g, '&quot;') + ')">'
      + '<span>Compare</span>'
      + '</label>';
  }

  function _onCheck(input, shop){
    if (input.checked){
      var ok = add(shop);
      if (!ok){
        input.checked = false;
        alert('You can compare up to 2 shops. Remove one first.');
        return;
      }
    } else {
      remove(shop.id);
    }
    var lbl = input.closest('.cmp-pick');
    if (lbl) lbl.classList.toggle('cmp-selected', input.checked);
  }

  global.DukanCompare = {
    add: add, remove: remove, clear: clear, has: has, list: list, toggle: toggle,
    attachBar: attachBar, checkboxHTML: checkboxHTML, _onCheck: _onCheck
  };

  // Auto-attach on DOM ready
  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', attachBar);
  } else {
    attachBar();
  }
})(window);
