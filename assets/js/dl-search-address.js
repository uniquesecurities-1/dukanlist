/* DL SEARCH ENRICH v16 — inject owner/phone/address + FREE badge */
(function(){
  'use strict';
  var TAG = '[dl-enrich]';
  var path = location.pathname;
  if (!(path === '/search.html' || path === '/search' ||
        path === '/browse.html' || path === '/browse' ||
        path === '/discover.html' || path === '/discover' ||
        path.indexOf('/local/') === 0)) return;
  console.log(TAG, 'loaded on', path);

  var CACHE = {};
  var loaded = false;

  function esc(s){
    return String(s == null ? '' : s).replace(/[&<>"']/g, function(c){
      return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];
    });
  }

  async function loadData(){
    if (loaded) return;
    if (typeof ShopDB === 'undefined' || !ShopDB || !ShopDB.client) { setTimeout(loadData, 300); return; }
    try {
      var r = await ShopDB.client.from('businesses')
        .select('id,slug,name,owner_name,mobile,whatsapp,address_line1,address_line2,photos,category_id,categories(name,icon)')
        .eq('status', 'active').limit(500);
      if (r.error) { console.warn(TAG, 'err', r.error); return; }
      var bizIds = [];
      (r.data || []).forEach(function(b){
        if (!b.slug) return;
        bizIds.push(b.id);
        var legacyThumb = (Array.isArray(b.photos) && b.photos.length && typeof b.photos[0] === 'string') ? b.photos[0] : '';
        var catInfo = b.categories || {};
        CACHE[b.slug] = {
          id: b.id,
          name: b.name || '',
          owner: b.owner_name || '',
          phone: String(b.whatsapp || b.mobile || '').replace(/\D/g, '').slice(-10),
          addr: [b.address_line1, b.address_line2].filter(Boolean).join(', '),
          thumb: legacyThumb,
          catIcon: catInfo.icon || '🏪',
          catName: catInfo.name || 'BUSINESS'
        };
      });

      // Bulk-fetch Cloudinary photos for all businesses
      if (bizIds.length) {
        try {
          var pr = await ShopDB.client.from('business_photos')
            .select('business_id,cloudinary_url,is_featured')
            .in('business_id', bizIds);
          if (!pr.error && pr.data) {
            var slugById = {};
            Object.keys(CACHE).forEach(function(s){ slugById[CACHE[s].id] = s; });
            pr.data.forEach(function(p){
              if (!p.cloudinary_url) return;
              var s = slugById[p.business_id];
              if (!s) return;
              var thumb = p.cloudinary_url.replace('/upload/', '/upload/w_240,h_240,c_fill,q_auto,f_auto/');
              // Cloudinary overrides legacy; featured overrides first
              if (p.is_featured || !CACHE[s]._hasCloudThumb) {
                CACHE[s].thumb = thumb;
                CACHE[s]._hasCloudThumb = true;
              }
            });
          }
        } catch(pe){ console.warn(TAG, 'photos load skipped', pe); }
      }

      loaded = true;
      console.log(TAG, 'cached', Object.keys(CACHE).length);
      injectAll();
    } catch(e){ console.warn(TAG, 'ex', e); }
  }

  function slugFromCard(card){
    var link = card.querySelector('a[href*="/business.html?slug="]') || card.querySelector('a.biz-card-link');
    if (!link) return null;
    var m = (link.getAttribute('href') || '').match(/slug=([^&#]+)/);
    return m ? decodeURIComponent(m[1]) : null;
  }

  function enrichCard(card){
    if (card.dataset.dlEnriched) return;
    var slug = slugFromCard(card);
    if (!slug || !CACHE[slug]) return;
    var d = CACHE[slug];
    var info = card.querySelector('.biz-info') || card;
    var meta = info.querySelector('.biz-meta');
    var name = info.querySelector('.biz-name');
    var frag = document.createDocumentFragment();

    // Inject photo thumbnail at top of card (real photo OR branded placeholder)
    if (!card.querySelector('.biz-photo img') && !card.querySelector('.dl-thumb')) {
      var thumbWrap = document.createElement('div');
      thumbWrap.className = 'dl-thumb';
      thumbWrap.style.cssText = 'width:calc(100% + 32px);position:relative;padding-bottom:60%;overflow:hidden;background:#F1F5F9;margin:-14px -16px 10px;';
      if (d.thumb) {
        thumbWrap.innerHTML = '<img src="' + d.thumb + '" alt="" loading="lazy" style="position:absolute;top:0;left:0;width:100%;height:100%;object-fit:cover;display:block">';
      } else {
        // Branded fallback — saffron gradient with category icon + shop name
        thumbWrap.style.background = 'linear-gradient(135deg,#FFF7ED 0%,#FED7AA 40%,#FFB870 100%)';
        thumbWrap.innerHTML =
          '<div style="position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;padding:14px;' +
          'background-image:radial-gradient(circle at 20% 20%, rgba(255,255,255,.5), transparent 45%),radial-gradient(circle at 80% 80%, rgba(255,107,26,.15), transparent 55%)">' +
          '<div style="font-size:2.2rem;line-height:1;margin-bottom:4px;filter:drop-shadow(0 2px 4px rgba(120,53,15,.15))">' + esc(d.catIcon || '🏪') + '</div>' +
          '<div style="font-family:\'Manrope\',sans-serif;font-size:.9rem;font-weight:900;color:#7C2D12;letter-spacing:-.01em;line-height:1.15;text-shadow:0 1px 2px rgba(255,255,255,.5);max-width:90%">' + esc(d.name || '') + '</div>' +
          '<div style="font-size:.62rem;font-weight:800;color:#9A3412;margin-top:4px;letter-spacing:.08em;text-transform:uppercase;opacity:.85">' + esc(d.catName || '') + '</div>' +
          '</div>';
      }
      // Insert BEFORE info block so it sits at top of card
      if (info && info.parentNode) info.parentNode.insertBefore(thumbWrap, info);
      else card.insertBefore(thumbWrap, card.firstChild);
    }

    if (d.owner) {
      var o = document.createElement('div');
      o.className = 'dl-owner';
      o.style.cssText = 'font-size:.82rem;color:#475569;margin:6px 0 3px;display:flex;align-items:center;gap:5px;pointer-events:none';
      o.innerHTML = '<span>👤</span> <b style="color:#0F172A">' + esc(d.owner) + '</b>';
      frag.appendChild(o);
    }
    if (d.phone && d.phone.length === 10) {
      var p = document.createElement('div');
      p.style.cssText = 'font-size:.82rem;color:#475569;margin:0 0 3px;display:flex;align-items:center;gap:5px;font-family:monospace;pointer-events:none';
      p.innerHTML = '<span>📱</span> +91-' + d.phone;
      frag.appendChild(p);
    }
    if (d.addr) {
      var a = document.createElement('div');
      a.className = 'dl-biz-addr';
      a.style.cssText = 'font-size:.82rem;color:#475569;margin:0 0 4px;display:flex;align-items:flex-start;gap:5px;line-height:1.4;pointer-events:none';
      a.innerHTML = '<span style="color:#DC2626;flex-shrink:0">📍</span> <span>' + esc(d.addr) + '</span>';
      frag.appendChild(a);
    }
    if (meta && meta.parentNode) meta.parentNode.insertBefore(frag, meta);
    else if (name && name.nextSibling) name.parentNode.insertBefore(frag, name.nextSibling);
    else info.appendChild(frag);
    card.dataset.dlEnriched = '1';
  }

  function injectAll(){
    var cards = document.querySelectorAll('.biz-card, article.biz-card');
    for (var i = 0; i < cards.length; i++) enrichCard(cards[i]);
  }

  function observe(){
    var target = document.getElementById('results') || document.querySelector('.biz-grid') || document.body;
    if (!target || !window.MutationObserver) return;
    new MutationObserver(function(muts){
      if (!loaded) return;
      muts.forEach(function(m){
        m.addedNodes && m.addedNodes.forEach(function(n){
          if (n.nodeType !== 1) return;
          if (n.classList && n.classList.contains('biz-card')) enrichCard(n);
          if (n.querySelectorAll) {
            var kids = n.querySelectorAll('.biz-card');
            for (var i = 0; i < kids.length; i++) enrichCard(kids[i]);
          }
        });
      });
    }).observe(target, { childList: true, subtree: true });
  }

  loadData();
  if (document.readyState !== 'loading') { observe(); setTimeout(injectAll, 500); }
  window.addEventListener('DOMContentLoaded', function(){ observe(); setTimeout(injectAll, 500); });
  window.addEventListener('load', function(){ setTimeout(injectAll, 1000); });
  window.dlEnrichReload = function(){ loaded = false; CACHE = {}; loadData(); };
})();
