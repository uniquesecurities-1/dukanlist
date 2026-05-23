/* ============================================================
   filter-chips.js — Active filter pills above search results
   ============================================================
   USAGE on search.html (call after results render):
     <div id="filterChipsSlot"></div>
     <script>
       DukanChips.render('filterChipsSlot', {
         q:      { label: 'doctor',       remove: () => clearAndSearch('q') },
         cat:    { label: 'Healthcare',   remove: () => clearAndSearch('cat') },
         city:   { label: 'Mandi Dabwali',remove: () => clearAndSearch('city') },
         pin:    { label: '125104',       remove: () => clearAndSearch('pin') },
         open:   { label: 'Open Now',     remove: () => clearAndSearch('open') }
       });
     </script>

   Each filter param shows a colored chip with × — click × calls
   the remove callback which should clear that param + re-search.
============================================================ */
(function(global){
  'use strict';

  const ICONS = {
    q:    '🔍',
    cat:  '🏷',
    city: '📍',
    pin:  '📮',
    open: '🟢'
  };
  const COLORS = {
    q:    { bg: '#EEF2FF', border: '#C7D2FE', text: '#4338CA' },
    cat:  { bg: '#FFF5EB', border: '#FED7AA', text: '#9A3412' },
    city: { bg: '#ECFDF5', border: '#86EFAC', text: '#065F46' },
    pin:  { bg: '#FEF3C7', border: '#FDE68A', text: '#92400E' },
    open: { bg: '#D1FAE5', border: '#6EE7B7', text: '#047857' }
  };

  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]); }

  // The render fn produces chip buttons but uses event delegation for clicks.
  // We attach a single click listener per slot and call the matching remove.
  const REMOVE_CB = {};

  function render(slotId, filters){
    const slot = document.getElementById(slotId);
    if (!slot) return;
    REMOVE_CB[slotId] = {};

    const chips = [];
    Object.keys(filters || {}).forEach(key => {
      const f = filters[key];
      if (!f || !f.label) return;
      if (typeof f.remove === 'function') REMOVE_CB[slotId][key] = f.remove;
      const c = COLORS[key] || COLORS.q;
      const ico = ICONS[key] || '';
      chips.push(
        '<button type="button" data-key="' + esc(key) + '" '
        + 'style="display:inline-flex;align-items:center;gap:6px;background:' + c.bg + ';color:' + c.text + ';border:1px solid ' + c.border + ';padding:7px 6px 7px 12px;border-radius:99px;font-size:.84rem;font-weight:700;cursor:default;font-family:\'Plus Jakarta Sans\',\'Manrope\',sans-serif;line-height:1">'
        + (ico ? '<span style="font-size:.95em">' + ico + '</span> ' : '')
        + '<span>' + esc(f.label) + '</span>'
        + '<span data-remove="1" style="display:inline-flex;align-items:center;justify-content:center;width:20px;height:20px;border-radius:50%;background:rgba(255,255,255,.7);font-size:11px;font-weight:800;cursor:pointer;margin-left:2px;transition:background .12s" '
        + 'onmouseover="this.style.background=&quot;#fff&quot;" onmouseout="this.style.background=&quot;rgba(255,255,255,.7)&quot;">'
        + '×</span>'
        + '</button>'
      );
    });

    if (!chips.length){
      slot.innerHTML = '';
      slot.style.display = 'none';
      return;
    }

    slot.style.display = '';
    slot.innerHTML = '<div style="display:flex;gap:8px;flex-wrap:wrap;align-items:center;padding:10px 0">'
      + '<span style="font-size:.76rem;color:#64748b;font-weight:700;text-transform:uppercase;letter-spacing:.06em;margin-right:4px">Filters</span>'
      + chips.join('')
      + (chips.length >= 2 ? '<button type="button" data-key="__all__" style="background:transparent;border:0;color:#EF4444;font-size:.82rem;font-weight:700;cursor:pointer;padding:7px 10px;letter-spacing:.01em">Clear all</button>' : '')
      + '</div>';

    // Single delegated listener (re-bound each render)
    slot.onclick = function(ev){
      const btn = ev.target.closest('button[data-key]');
      if (!btn) return;
      const key = btn.getAttribute('data-key');
      if (key === '__all__'){
        Object.values(REMOVE_CB[slotId] || {}).forEach(fn => { try { fn(); } catch(_){} });
        return;
      }
      // Only fire on × click (or anywhere on chip)
      const cb = (REMOVE_CB[slotId] || {})[key];
      if (cb) try { cb(); } catch(_){}
    };
  }

  global.DukanChips = { render };
})(window);
