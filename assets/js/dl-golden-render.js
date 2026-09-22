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
    // v281: both branches are Cloudinary now — resize either way, so the
    // legacy fallback stops shipping a full-size original into a small card.
    var src = b._cloudPhoto ||
      ((Array.isArray(b.photos) && b.photos.length && typeof b.photos[0] === 'string') ? b.photos[0] : null);
    if (src) return window.DukanImg ? DukanImg.opt(src, { width: 400, height: 240, crop: 'fill' })
                                    : src.replace('/upload/', '/upload/w_400,h_240,c_fill,q_auto,f_auto/');
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
    var report = '/' + slug + '#report';

    var waBtn = wa.length === 10
      ? '<a href="https://wa.me/91' + wa + '?text=' + msg + '" target="_blank" rel="noopener" style="flex:1;display:inline-flex;align-items:center;justify-content:center;gap:6px;padding:10px 12px;border-radius:10px;background:#25D366;color:#fff;font-weight:800;font-size:.85rem;text-decoration:none;border:1.5px solid #25D366">💬 ' + (lang==='hi'?'WhatsApp':'WhatsApp') + '</a>'
      : '';

    var callBtn = tel.length === 10
      ? '<a href="tel:+91' + tel + '" style="flex:1;display:inline-flex;align-items:center;justify-content:center;gap:6px;padding:10px 12px;border-radius:10px;background:#fff;color:#0F2952;font-weight:800;font-size:.85rem;text-decoration:none;border:1.5px solid #E5B84F">📞 ' + (lang==='hi'?'Call':'Call') + '</a>'
      : '';

    return '<article style="position:relative;background:#fff;border:2px solid #FED7AA;border-radius:14px;padding:0;display:flex;flex-direction:column;gap:0;box-shadow:0 2px 6px rgba(15,23,42,.05);cursor:pointer;overflow:hidden" onclick="if(!event.target.closest(\'a,button\')){window.location.href=\'/' + slug + '\';}">'
      + (thumb
          ? '<div style="width:100%;position:relative;padding-bottom:62.5%;overflow:hidden;background:#F1F5F9"><img src="' + esc(thumb) + '" alt="' + esc(b.name || '') + '" width="400" height="240" loading="lazy" style="position:absolute;top:0;left:0;width:100%;height:100%;object-fit:cover;display:block"></div>'
          : '<div style="width:100%;position:relative;padding-bottom:62.5%;overflow:hidden;background:linear-gradient(135deg,#FFF7ED 0%,#FED7AA 40%,#FFB870 100%)"><div style="position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;padding:16px;background-image:radial-gradient(circle at 20% 20%, rgba(255,255,255,.5), transparent 45%),radial-gradient(circle at 80% 80%, rgba(255,107,26,.15), transparent 55%)"><div style="font-size:3.4rem;line-height:1;filter:drop-shadow(0 3px 6px rgba(120,53,15,.20))">' + esc(catIcon) + '</div><div style="position:absolute;bottom:8px;right:10px;font-size:.62rem;font-weight:800;color:#9A3412;letter-spacing:.1em;text-transform:uppercase;opacity:.6">dukanlist</div></div></div>')
      + '<div style="padding:14px 16px;display:flex;flex-direction:column;gap:8px">'
      + '<div style="display:flex;justify-content:space-between;align-items:flex-start;gap:8px">'
      + '<span style="display:inline-flex;align-items:center;gap:5px;background:#FEF3C7;color:#78350F;padding:4px 10px;border-radius:99px;font-size:.72rem;font-weight:800">' + esc(catIcon) + ' ' + esc(catName.toUpperCase()) + '</span>'
      + ''
      + '</div>'
      + '<div style="margin-top:4px"><div style="display:flex;align-items:center;gap:6px;font-family:\'Manrope\',sans-serif;font-size:1.1rem;font-weight:900;color:#0F172A;line-height:1.2"><span style="color:#FF6B1A">🏢</span> <a href="/' + esc(slug) + '" style="color:inherit;text-decoration:none">' + esc(b.name || '') + '</a></div>'
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

  // ---------------------------------------------------------------
  // v264 — this used to run THREE times on every page load.
  //
  // The three triggers at the bottom of this file (readyState,
  // DOMContentLoaded, load) each called render(), and nothing stopped
  // a second or third run. Measured on the live homepage at 430px,
  // counting identical full URLs:
  //
  //     businesses?select=id,slug,name,name_hi,owner_name,...   3x
  //     business_photos?select=...&business_id=in.(...)         3x
  //     categories?select=id,name,name_hi,icon,color            2x
  //
  // Exactly what three overlapping runs produce — the third run found
  // CATS already populated and skipped the category fetch, which is
  // why that one is 2x and not 3x. Six wasted round trips out of the
  // homepage's thirty, and the whole featured grid was built, thrown
  // away and rebuilt three times: three lots of DOM work and image
  // decoding on a phone that can least afford it.
  //
  // RENDERED   a full render finished — do not do it again
  // RUNNING    one is in flight right now
  // RETRY_WAIT a ShopDB-not-ready retry is already queued, so the
  //            other triggers must not start their own retry chain
  // ---------------------------------------------------------------
  var RENDERED = false, RUNNING = false, RETRY_WAIT = false, RETRIES = 0;

  async function render(force){
    if (force) RENDERED = false;
    if (RENDERED || RUNNING) return;

    if (typeof ShopDB === 'undefined' || !ShopDB || !ShopDB.client) {
      if (RETRY_WAIT) return;
      if (++RETRIES > 40) { console.warn(TAG, 'ShopDB never arrived; giving up'); return; }
      RETRY_WAIT = true;
      setTimeout(function(){ RETRY_WAIT = false; render(); }, 200);
      return;
    }
    RUNNING = true;
    try { await doRender(); RENDERED = true; }
    finally { RUNNING = false; }
  }

  async function doRender(){
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

  // All three triggers stay: whichever fires first does the work and the
  // guard above makes the rest free. The 'load' one is the safety net for a
  // slow ShopDB. They are no longer three separate renders.
  if (document.readyState !== 'loading') setTimeout(function(){ render(); }, 300);
  window.addEventListener('DOMContentLoaded', function(){ setTimeout(function(){ render(); }, 300); });
  window.addEventListener('load', function(){ setTimeout(function(){ render(); }, 800); });

  // Public hook — an explicit reload is meant to re-render, so it forces.
  window.dlGoldenReload = function(){ return render(true); };
})();
