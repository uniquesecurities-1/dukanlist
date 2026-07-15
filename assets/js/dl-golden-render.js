/* ============================================================
   DL GOLDEN RENDER — Homepage Card Redesign (2026-07 v13)
   ------------------------------------------------------------
   Overrides the default photo-heavy card render on the homepage
   and shows a clean Golden-Pages-style directory card with:
     • Category pill (color-coded)
     • FREE badge
     • Business name + Hindi name
     • Owner name
     • Masked phone (XXXXXX-1234)
     • Address line
     • City
     • WhatsApp + Call action buttons
     • Report link

   Runs AFTER homepage.js populates #featuredGrid, then re-fetches
   with the extra fields we need (owner_name, address, category)
   and rewrites the grid.

   Safe: waits for ShopDB. If DB unavailable, leaves default render.
============================================================ */
(function(){
  'use strict';

  // Only run on homepage
  if (!(location.pathname === '/' ||
        location.pathname === '/index.html' ||
        location.pathname === '')) return;

  function escapeHTML(s){
    return String(s == null ? '' : s).replace(/[&<>"']/g, function(c){
      return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];
    });
  }

  function maskPhone(raw){
    var d = String(raw || '').replace(/\D/g, '').slice(-10);
    if (d.length < 10) return '';
    return 'XXXXXX-' + d.slice(-4);
  }

  function goldenCard(b){
    var lang = document.documentElement.dataset.lang === 'hi' ? 'hi' : 'en';
    var cat = b.categories || {};
    var catName = (lang === 'hi' && cat.name_hi) ? cat.name_hi : (cat.name || '');
    var catIcon = cat.icon || '🏪';
    var catColor = cat.color || '#0F2952';
    var city = (b.geo_cities && b.geo_cities.name) || '';
    var addr = [b.address_line1, b.address_line2].filter(Boolean).join(', ');
    var phoneMasked = maskPhone(b.whatsapp || b.mobile);
    var waRaw = String(b.whatsapp || b.mobile || '').replace(/\D/g, '').slice(-10);
    var telRaw = String(b.mobile || '').replace(/\D/g, '').slice(-10);
    var waMsg = encodeURIComponent('Hi ' + (b.name || 'there') + ', I found you on DukanList.');
    var slug = encodeURIComponent(b.slug || '');
    var reportUrl = '/business.html?slug=' + slug + '#report';

    var waBtn = waRaw.length === 10
      ? '<a href="https://wa.me/91' + waRaw + '?text=' + waMsg + '" target="_blank" rel="noopener" '
        + 'style="flex:1;display:inline-flex;align-items:center;justify-content:center;gap:6px;padding:10px 12px;'
        + 'border-radius:10px;background:#25D366;color:#fff;font-weight:800;font-size:.85rem;text-decoration:none;'
        + 'border:1.5px solid #25D366;transition:.15s">💬 ' + (lang==='hi'?'WhatsApp करें':"I'm the owner") + '</a>'
      : '';

    var callBtn = telRaw.length === 10
      ? '<a href="tel:+91' + telRaw + '" '
        + 'style="flex:1;display:inline-flex;align-items:center;justify-content:center;gap:6px;padding:10px 12px;'
        + 'border-radius:10px;background:#fff;color:#0F2952;font-weight:800;font-size:.85rem;text-decoration:none;'
        + 'border:1.5px solid #E5B84F;transition:.15s">📞 ' + (lang==='hi'?'Contact owner':'Contact owner') + '</a>'
      : '';

    return ''
      + '<article style="position:relative;background:#fff;border:2px solid #FED7AA;border-radius:14px;'
      + 'padding:14px 16px;display:flex;flex-direction:column;gap:8px;box-shadow:0 2px 6px rgba(15,23,42,.05);'
      + 'transition:transform .2s,box-shadow .2s" '
      + 'onmouseover="this.style.transform=\'translateY(-2px)\';this.style.boxShadow=\'0 10px 24px rgba(15,23,42,.08)\'" '
      + 'onmouseout="this.style.transform=\'\';this.style.boxShadow=\'0 2px 6px rgba(15,23,42,.05)\'">'
      + '<div style="display:flex;justify-content:space-between;align-items:flex-start;gap:8px">'
      +   '<span style="display:inline-flex;align-items:center;gap:5px;background:#FEF3C7;color:#78350F;padding:4px 10px;'
      +   'border-radius:99px;font-size:.72rem;font-weight:800;letter-spacing:.02em">'
      +     escapeHTML(catIcon) + ' ' + escapeHTML(catName.toUpperCase())
      +   '</span>'
      +   '<span style="background:#10B981;color:#fff;padding:3px 9px;border-radius:99px;font-size:.66rem;'
      +   'font-weight:800;letter-spacing:.04em">✓ FREE</span>'
      + '</div>'
      + '<div style="margin-top:4px">'
      +   '<div style="display:flex;align-items:center;gap:6px;font-family:\'Manrope\',sans-serif;'
      +   'font-size:1.1rem;font-weight:900;color:#0F172A;letter-spacing:-.01em;line-height:1.2">'
      +     '<span style="color:#FF6B1A">🏢</span> ' + escapeHTML(b.name || '')
      +   '</div>'
      +   (b.name_hi
          ? '<div style="font-family:\'Noto Sans Devanagari\',sans-serif;font-size:.9rem;font-weight:700;color:#64748B;margin-top:2px">' + escapeHTML(b.name_hi) + '</div>'
          : '')
      + '</div>'
      + (b.owner_name
          ? '<div style="font-size:.82rem;color:#475569;display:flex;align-items:center;gap:5px">'
            + '<span style="color:#0F2952">👤</span> <b style="color:#0F172A">' + escapeHTML(b.owner_name) + '</b>'
            + '</div>'
          : '')
      + (phoneMasked
          ? '<div style="font-size:.82rem;color:#475569;display:flex;align-items:center;gap:5px;font-family:\'SFMono-Regular\',Consolas,monospace;letter-spacing:.02em">'
            + '<span>📱</span> ' + phoneMasked
            + '</div>'
          : '')
      + (addr
          ? '<div style="font-size:.82rem;color:#475569;display:flex;align-items:flex-start;gap:5px;line-height:1.4">'
            + '<span style="color:#DC2626;flex-shrink:0">📍</span> ' + escapeHTML(addr)
            + '</div>'
          : '')
      + (city
          ? '<div style="font-size:.78rem;color:#64748B;display:flex;align-items:center;gap:5px">'
            + '<span style="color:#0F2952">🏙️</span> ' + escapeHTML(city)
            + '</div>'
          : '')
      + '<div style="display:flex;gap:8px;margin-top:8px;padding-top:10px;border-top:1px dashed #E2E8F0">'
      +   waBtn + callBtn
      +   '<a href="' + reportUrl + '" title="Report" '
      +   'style="width:38px;display:inline-flex;align-items:center;justify-content:center;padding:10px 0;'
      +   'border-radius:10px;background:#fff;color:#F59E0B;border:1.5px solid #FCD34D;font-size:.9rem;text-decoration:none">⚠️</a>'
      + '</div>'
      + '</article>';
  }

  async function renderGoldenPagesHomepage(){
    if (typeof ShopDB === 'undefined' || !ShopDB || !ShopDB.client) {
      // Try again after ShopDB loads
      setTimeout(renderGoldenPagesHomepage, 100);
      return;
    }

    var grid = document.getElementById('featuredGrid');
    if (!grid) return;

    try {
      var c = ShopDB.client;
      var res = await c.from('businesses')
        .select('id,slug,name,name_hi,owner_name,mobile,whatsapp,address_line1,address_line2,pincode,city_id,is_professional_listing,professional_tier,categories(name,name_hi,icon,color),geo_cities(name)')
        .eq('status', 'active')
        .or('professional_tier.is.null,professional_tier.neq.strict')
        .order('created_at', { ascending: false })
        .limit(24);

      if (res.error || !res.data || !res.data.length) return;

      var html = res.data.map(goldenCard).join('');
      grid.innerHTML = html;
      grid.style.display = 'grid';
      grid.style.gridTemplateColumns = 'repeat(auto-fill,minmax(300px,1fr))';
      grid.style.gap = '14px';

      // Also hide the empty state
      var empty = document.getElementById('featuredEmpty');
      if (empty) empty.style.display = 'none';
    } catch(e) {
      console.warn('Golden render failed:', e);
    }
  }

  // Run after homepage.js has finished
  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    setTimeout(renderGoldenPagesHomepage, 100);
  } else {
    window.addEventListener('DOMContentLoaded', function(){
      setTimeout(renderGoldenPagesHomepage, 100);
    });
  }

  // Re-render if user changes language
  window.addEventListener('DOMContentLoaded', function(){
    var enBtn = document.getElementById('langBtnEn');
    var hiBtn = document.getElementById('langBtnHi');
    if (enBtn) enBtn.addEventListener('click', function(){ setTimeout(renderGoldenPagesHomepage, 200); });
    if (hiBtn) hiBtn.addEventListener('click', function(){ setTimeout(renderGoldenPagesHomepage, 200); });
  });
})();
