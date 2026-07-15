/* DL SEARCH ADDRESS INJECTOR (2026-07 v15)
   ---------------------------------------
   On search.html + browse.html: inject full address into every
   .biz-card in the results list. Uses MutationObserver so newly
   rendered cards also get address injected.

   Data source: fetches id/slug/address_line1/address_line2 for
   ALL active businesses once, then maps by slug from card link.
*/
(function(){
  'use strict';
  var TAG = '[dl-addr]';

  // Only on search + browse pages
  var path = location.pathname;
  if (!(path === '/search.html' || path === '/search' ||
        path === '/browse.html' || path === '/browse' ||
        path === '/discover.html' || path === '/discover' ||
        path.indexOf('/local/') === 0)) {
    console.log(TAG, 'not applicable, exiting');
    return;
  }
  console.log(TAG, 'loaded on', path);

  var ADDR_BY_SLUG = {};
  var loaded = false;

  function esc(s){
    return String(s == null ? '' : s).replace(/[&<>"']/g, function(c){
      return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];
    });
  }

  async function loadAddresses(){
    if (loaded) return;
    if (typeof ShopDB === 'undefined' || !ShopDB || !ShopDB.client) {
      setTimeout(loadAddresses, 300);
      return;
    }
    try {
      var r = await ShopDB.client.from('businesses')
        .select('slug,address_line1,address_line2')
        .eq('status', 'active')
        .limit(500);
      if (r.error) { console.warn(TAG, 'fetch err', r.error); return; }
      (r.data || []).forEach(function(b){
        var addr = [b.address_line1, b.address_line2].filter(Boolean).join(', ');
        if (b.slug && addr) ADDR_BY_SLUG[b.slug] = addr;
      });
      loaded = true;
      console.log(TAG, 'loaded ' + Object.keys(ADDR_BY_SLUG).length + ' addresses');
      injectAll();
    } catch(e){ console.warn(TAG, 'ex', e); }
  }

  function extractSlug(card){
    var link = card.querySelector('a[href*="/business.html?slug="]') ||
               card.querySelector('a.biz-card-link');
    if (!link) return null;
    var href = link.getAttribute('href') || '';
    var m = href.match(/slug=([^&#]+)/);
    return m ? decodeURIComponent(m[1]) : null;
  }

  function injectCard(card){
    if (card.dataset.addrInjected) return;
    var slug = extractSlug(card);
    if (!slug) return;
    var addr = ADDR_BY_SLUG[slug];
    if (!addr) return;

    // Find best insertion point: after .biz-name or before .biz-meta or in .biz-info
    var info = card.querySelector('.biz-info') || card;
    var name = info.querySelector('.biz-name');
    var meta = info.querySelector('.biz-meta');

    var addrDiv = document.createElement('div');
    addrDiv.className = 'dl-biz-addr';
    addrDiv.style.cssText = 'font-size:.78rem;color:#475569;margin:6px 0 4px;display:flex;align-items:flex-start;gap:5px;line-height:1.4';
    addrDiv.innerHTML = '<span style="color:#DC2626;flex-shrink:0">📍</span> <span>' + esc(addr) + '</span>';

    // Prefer inserting BEFORE .biz-meta (which has city + share)
    if (meta && meta.parentNode) {
      meta.parentNode.insertBefore(addrDiv, meta);
    } else if (name && name.nextSibling) {
      name.parentNode.insertBefore(addrDiv, name.nextSibling);
    } else {
      info.appendChild(addrDiv);
    }

    card.dataset.addrInjected = '1';
  }

  function injectAll(){
    var cards = document.querySelectorAll('.biz-card, article.biz-card');
    console.log(TAG, 'injecting into ' + cards.length + ' cards');
    for (var i = 0; i < cards.length; i++) injectCard(cards[i]);
  }

  // Watch #results for card additions/replacements
  function observe(){
    var target = document.getElementById('results') ||
                 document.getElementById('bizGrid') ||
                 document.querySelector('.biz-grid') ||
                 document.body;
    if (!target) return;
    var obs = new MutationObserver(function(muts){
      if (!loaded) return;
      var addedCard = false;
      muts.forEach(function(m){
        m.addedNodes && m.addedNodes.forEach(function(n){
          if (n.nodeType !== 1) return;
          if (n.classList && n.classList.contains('biz-card')) {
            injectCard(n);
            addedCard = true;
          }
          if (n.querySelectorAll) {
            var kids = n.querySelectorAll('.biz-card');
            for (var i = 0; i < kids.length; i++) injectCard(kids[i]);
          }
        });
      });
    });
    obs.observe(target, { childList: true, subtree: true });
  }

  // Boot
  loadAddresses();
  if (document.readyState !== 'loading') {
    observe();
    setTimeout(injectAll, 500);
  }
  window.addEventListener('DOMContentLoaded', function(){
    observe();
    setTimeout(injectAll, 500);
  });
  window.addEventListener('load', function(){
    setTimeout(injectAll, 1000);
  });

  window.dlAddrReload = function(){ loaded = false; ADDR_BY_SLUG = {}; loadAddresses(); };
})();
