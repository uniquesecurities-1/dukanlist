/* DL ADMIN SHOP CLEAN (2026-07 v23 SAFE)
   Nukes leftover cards CSS can't reliably hide:
   - "Shop Trust Signals" header + info blue box
   - Photos card (.card containing .photos-strip)
   - Customer Reviews card (.card containing #reviewsList)
   - Professional Listing slot (#proFieldsetSlot content)
*/
(function(){
  'use strict';
  if (!/\/admin\/shop\.html?$|\/admin\/shop$/.test(location.pathname)) return;
  console.log('[dl-admin-shop] loaded v23');

  function ownText(el){
    var t = '';
    for (var i = 0; i < el.childNodes.length; i++) {
      var n = el.childNodes[i];
      if (n.nodeType === 3) t += n.nodeValue;
    }
    return t.trim();
  }

  function hideEl(el){
    if (!el || el.dataset.dlNuked) return;
    el.style.display = 'none';
    el.dataset.dlNuked = '1';
  }

  function nukeOnce(){
    // 1. Shop Trust Signals section header + info box (from earlier)
    var divs = document.querySelectorAll('div');
    for (var i = 0; i < divs.length; i++) {
      var d = divs[i];
      if (d.dataset.dlNuked) continue;
      var own = ownText(d);
      var style = d.getAttribute('style') || '';
      if (own === '✨ Shop Trust Signals' && style.indexOf('uppercase') !== -1) {
        hideEl(d); continue;
      }
      if (own.indexOf('These three fields power') !== -1 && style.indexOf('F0F9FF') !== -1) {
        hideEl(d);
      }
    }

    // 2. Photos card — .card containing .photos-strip
    var strips = document.querySelectorAll('.photos-strip');
    for (var j = 0; j < strips.length; j++) {
      var card = strips[j].closest('.card');
      if (card) hideEl(card);
    }

    // 3. Customer Reviews card — .card containing #reviewsList
    var rl = document.getElementById('reviewsList');
    if (rl) {
      var revCard = rl.closest('.card');
      if (revCard) hideEl(revCard);
    }

    // 4. Professional Listing slot content
    var proSlot = document.getElementById('proFieldsetSlot');
    if (proSlot) {
      proSlot.style.display = 'none';
      proSlot.dataset.dlNuked = '1';
    }
  }

  function boot(){
    var tries = 0;
    var iv = setInterval(function(){
      tries++;
      nukeOnce();
      if (tries > 20) clearInterval(iv);
    }, 400);
  }

  if (document.readyState !== 'loading') boot();
  else document.addEventListener('DOMContentLoaded', boot);
})();
