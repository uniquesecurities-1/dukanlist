/* DL ADMIN SHOP CLEAN (2026-07 v22 SAFE)
   Safer version — only hides LEAF elements matching exact text
   to avoid accidentally hiding parent containers.
*/
(function(){
  'use strict';
  if (!/\/admin\/shop\.html?$|\/admin\/shop$/.test(location.pathname)) return;
  console.log('[dl-admin-shop] loaded SAFE v22');

  function ownText(el){
    // Get only DIRECT text nodes (skip descendant content)
    var t = '';
    for (var i = 0; i < el.childNodes.length; i++) {
      var n = el.childNodes[i];
      if (n.nodeType === 3) t += n.nodeValue;
    }
    return t.trim();
  }

  function nukeOnce(){
    // Target header: exact text + no children (leaf)
    var divs = document.querySelectorAll('div');
    for (var i = 0; i < divs.length; i++) {
      var d = divs[i];
      if (d.dataset.dlNuked) continue;

      var own = ownText(d);
      var style = d.getAttribute('style') || '';

      // Section header — leaf with exact text + uppercase style
      if (own === '✨ Shop Trust Signals' && style.indexOf('uppercase') !== -1) {
        d.style.display = 'none';
        d.dataset.dlNuked = '1';
        continue;
      }

      // Info blue box — starts with ℹ + has F0F9FF background
      if (own.indexOf('These three fields power') !== -1 && style.indexOf('F0F9FF') !== -1) {
        d.style.display = 'none';
        d.dataset.dlNuked = '1';
      }
    }
  }

  function boot(){
    var tries = 0;
    var iv = setInterval(function(){
      tries++;
      nukeOnce();
      if (tries > 15) clearInterval(iv);
    }, 400);
  }

  if (document.readyState !== 'loading') boot();
  else document.addEventListener('DOMContentLoaded', boot);
})();
