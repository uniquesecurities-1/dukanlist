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
        .select('slug,owner_name,mobile,whatsapp,address_line1,address_line2')
        .eq('status', 'active').limit(500);
      if (r.error) { console.warn(TAG, 'err', r.error); return; }
      (r.data || []).forEach(function(b){
        if (!b.slug) return;
        CACHE[b.slug] = {
          owner: b.owner_name || '',
          phone: String(b.mobile || '').replace(/\D/g, '').slice(-10),
          addr: [b.address_line1, b.address_line2].filter(Boolean).join(', ')
        };
      });
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

    if (d.owner) {
      var o = document.createElement('div');
      o.className = 'dl-owner';
      o.style.cssText = 'font-size:.82rem;color:#475569;margin:6px 0 3px;display:flex;align-items:center;gap:5px';
      o.innerHTML = '<span>👤</span> <b style="color:#0F172A">' + esc(d.owner) + '</b>';
      frag.appendChild(o);
    }
    if (d.phone && d.phone.length === 10) {
      var p = document.createElement('div');
      p.style.cssText = 'font-size:.82rem;color:#475569;margin:0 0 3px;display:flex;align-items:center;gap:5px;font-family:monospace';
      p.innerHTML = '<span>📱</span> +91-' + d.phone;
      frag.appendChild(p);
    }
    if (d.addr) {
      var a = document.createElement('div');
      a.className = 'dl-biz-addr';
      a.style.cssText = 'font-size:.82rem;color:#475569;margin:0 0 4px;display:flex;align-items:flex-start;gap:5px;line-height:1.4';
      a.innerHTML = '<span style="color:#DC2626;flex-shrink:0">📍</span> <span>' + esc(d.addr) + '</span>';
      frag.appendChild(a);
    }
    if (meta && meta.parentNode) meta.parentNode.insertBefore(frag, meta);
    else if (name && name.nextSibling) name.parentNode.insertBefore(frag, name.nextSibling);
    else info.appendChild(frag);

    if (!card.querySelector('.dl-free-badge')) {
      var fb = document.createElement('span');
      fb.className = 'dl-free-badge';
      fb.textContent = '✓ FREE';
      fb.style.cssText = 'position:absolute;top:10px;right:10px;background:#10B981;color:#fff;padding:3px 9px;border-radius:99px;font-size:.66rem;font-weight:800;letter-spacing:.04em;z-index:2';
      if (getComputedStyle(card).position === 'static') card.style.position = 'relative';
      card.appendChild(fb);
    }
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
