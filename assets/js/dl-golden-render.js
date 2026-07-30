/* DL GOLDEN RENDER v14 — Homepage cards as Golden Pages directory */
(function(){
  'use strict';
  var TAG = '[dl-golden]';
  console.log(TAG, 'loaded, path=', location.pathname);

  if (!(location.pathname === '/' ||
        location.pathname === '/index.html' ||
        location.pathname === '')) return;

  var CATS = {};

  function esc(s){
    return String(s == null ? '' : s).replace(/[&<>"']/g, function(c){
      return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];
    });
  }

  function mask(raw){
    var d = String(raw || '').replace(/\D/g, '').slice(-10);
    if (d.length < 10) return '';
    return 'XXXXXX-' + d.slice(-4);
  }

  function pickThumb(b){
    // Prefer Cloudinary featured/first, fallback to first legacy photo
    if (b._cloudPhoto) {
      return b._cloudPhoto.replace('/upload/', '/upload/w_400,h_240,c_fill,q_auto,f_auto/');
    }
    if (Array.isArray(b.photos) && b.photos.length && typeof b.photos[0] === 'string') {
      return b.photos[0];
    }
    return null;
  }

  function card(b){
    var lang = document.documentElement.dataset.lang === 'hi' ? 'hi' : 'en';
    var cat = CATS[b.category_id] || {};
    var catName = (lang === 'hi' && cat.name_hi) ? cat.name_hi : (cat.name || 'BUSINESS');
    var catIcon = cat.icon || '🏪';
    var thumb = pickThumb(b);
    var city = (b.geo_cities && b.geo_cities.name) || '';
    var addr = [b.address_line1, b.address_line2].filter(Boolean).join(', ');
    var phoneRaw = String(b.whatsapp || b.mobile || '').replace(/[^0-9]/g, '').slice(-10);
    var wa = String(b.whatsapp || b.mobile || '').replace(/\D/g, '').slice(-10);
    var tel = String(b.mobile || '').replace(/\D/g, '').slice(-10);
    var msg = encodeURIComponent('Hi ' + (b.name || 'there') + ', I found you on DukanList.');
    var slug = encodeURIComponent(b.slug || '');
    var report = '/business.html?slug=' + slug + '#report';

    var waBtn = wa.length === 10
      ? '<a href="https://wa.me/91' + wa + '?text=' + msg + '" target="_blank" rel="noopener" style="flex:1;display:inline-flex;align-items:center;justify-content:center;gap:6px;padding:10px 12px;border-radius:10px;background:#25D366;color:#fff;font-weight:800;font-size:.85rem;text-decoration:none;border:1.5px solid #25D366">💬 ' + (lang==='hi'?'WhatsApp':'WhatsApp') + '</a>'
      : '';

    var callBtn = tel.length === 10
      ? '<a href="tel:+91' + tel + '" style="flex:1;display:inline-flex;align-items:center;justify-content:center;gap:6px;padding:10px 12px;border-radius:10px;background:#fff;color:#0F2952;font-weight:800;font-size:.85rem;text-decoration:none;border:1.5px solid #E5B84F">📞 ' + (lang==='hi'?'Call':'Call') + '</a>'
      : '';

    return '<article style="position:relative;background:#fff;border:2px solid #FED7AA;border-radius:14px;padding:0;display:flex;flex-direction:column;gap:0;box-shadow:0 2px 6px rgba(15,23,42,.05);cursor:pointer;overflow:hidden" onclick="if(!event.target.closest(\'a,button\')){window.location.href=\'/business.html?slug=' + slug + '\';}">'
      + (thumb ? '<div style="width:100%;aspect-ratio:16/10;overflow:hidden;background:#F1F5F9"><img src="' + esc(thumb) + '" alt="' + esc(b.name || '') + '" loading="lazy" style="width:100%;height:100%;object-fit:cover;display:block"></div>' : '')
      + '<div style="padding:14px 16px;display:flex;flex-direction:column;gap:8px">'
      + '<div style="display:flex;justify-content:space-between;align-items:flex-start;gap:8px">'
      + '<span style="display:inline-flex;align-items:center;gap:5px;background:#FEF3C7;color:#78350F;padding:4px 10px;border-radius:99px;font-size:.72rem;font-weight:800">' + esc(catIcon) + ' ' + esc(catName.toUpperCase()) + '</span>'
      + ''
      + '</div>'
      + '<div style="margin-top:4px"><div style="display:flex;align-items:center;gap:6px;font-family:\'Manrope\',sans-serif;font-size:1.1rem;font-weight:900;color:#0F172A;line-height:1.2"><span style="color:#FF6B1A">🏢</span> ' + esc(b.name || '') + '</div>'
      + (b.name_hi ? '<div style="font-family:\'Noto Sans Devanagari\',sans-serif;font-size:.9rem;font-weight:700;color:#64748B;margin-top:2px">' + esc(b.name_hi) + '</div>' : '')
      + '</div>'
      + (b.owner_name ? '<div style="font-size:.82rem;color:#475569;display:flex;align-items:center;gap:5px"><span>👤</span> <b style="color:#0F172A">' + esc(b.owner_name) + '</b></div>' : '')
      + (phoneRaw ? '<div style="font-size:.82rem;color:#475569;display:flex;align-items:center;gap:5px;font-family:monospace"><span>📱</span> +91-' + phoneRaw + '</div>' : '')
      + (addr ? '<div style="font-size:.82rem;color:#475569;display:flex;align-items:flex-start;gap:5px;line-height:1.4"><span style="color:#DC2626;flex-shrink:0">📍</span> ' + esc(addr) + '</div>' : '')
      + (city ? '<div style="font-size:.78rem;color:#64748B;display:flex;align-items:center;gap:5px"><span>🏙️</span> ' + esc(city) + '</div>' : '')
      + '<div style="display:flex;gap:8px;margin-top:8px;padding-top:10px;border-top:1px dashed #E2E8F0">' + waBtn + callBtn
      + '</div></div></article>';
  }

  async function loadCats(c){
    try {
      var r = await c.from('categories').select('id,name,name_hi,icon,color');
      if (r.error) { console.warn(TAG, 'cats err', r.error); return; }
      (r.data || []).forEach(function(x){ CATS[x.id] = x; });
      console.log(TAG, 'cats:', Object.keys(CATS).length);
    } catch(e){ console.warn(TAG, 'cats ex', e); }
  }

  async function render(){
    console.log(TAG, 'render attempt, ShopDB=', typeof ShopDB);
    if (typeof ShopDB === 'undefined' || !ShopDB || !ShopDB.client) {
      setTimeout(render, 200);
      return;
    }
    var grid = document.getElementById('featuredGrid');
    if (!grid) { console.warn(TAG, 'no #featuredGrid'); return; }

    try {
      var c = ShopDB.client;
      if (Object.keys(CATS).length === 0) await loadCats(c);
      console.log(TAG, 'fetching businesses...');
      var r = await c.from('businesses')
        .select('id,slug,name,name_hi,owner_name,mobile,whatsapp,address_line1,address_line2,city_id,category_id,photos,is_professional_listing,professional_tier,geo_cities(name)')
        .eq('status', 'active')
        .or('professional_tier.is.null,professional_tier.neq.strict')
        .order('created_at', { ascending: false })
        .limit(24);

      if (r.error) { console.error(TAG, 'biz err', r.error); return; }
      if (!r.data || !r.data.length) { console.warn(TAG, 'no biz'); return; }

      // Bulk-fetch Cloudinary photos for all these businesses in one query
      try {
        var bizIds = r.data.map(function(b){ return b.id; });
        var pr = await c.from('business_photos')
          .select('business_id,cloudinary_url,is_featured')
          .in('business_id', bizIds);
        if (!pr.error && pr.data) {
          var photoMap = {};
          pr.data.forEach(function(p){
            if (!p.cloudinary_url) return;
            if (!photoMap[p.business_id]) photoMap[p.business_id] = null;
            // Prefer featured, else first
            if (p.is_featured || !photoMap[p.business_id]) {
              photoMap[p.business_id] = p.cloudinary_url;
            }
          });
          r.data.forEach(function(b){ b._cloudPhoto = photoMap[b.id] || null; });
        }
      } catch(pe){ console.warn(TAG, 'photos load skipped', pe); }

      console.log(TAG, 'rendering ' + r.data.length + ' cards');
      grid.innerHTML = r.data.map(card).join('');
      grid.style.display = 'grid';
      grid.style.gridTemplateColumns = 'repeat(auto-fill,minmax(300px,1fr))';
      grid.style.gap = '14px';
      var empty = document.getElementById('featuredEmpty');
      if (empty) empty.style.display = 'none';
      console.log(TAG, 'complete');
    } catch(e){ console.error(TAG, 'render fail', e); }
  }

  if (document.readyState !== 'loading') setTimeout(render, 300);
  window.addEventListener('DOMContentLoaded', function(){ setTimeout(render, 300); });
  window.addEventListener('load', function(){ setTimeout(render, 800); });
  window.dlGoldenReload = render;
})();
