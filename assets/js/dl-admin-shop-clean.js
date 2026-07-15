/* DL ADMIN SHOP CLEAN (2026-07 v21)
   ---------------------------------------
   On admin/shop.html: nukes the "Shop Trust Signals" header text +
   blue info box explaining verified_score. These elements are
   dynamically inline-styled and can't be targeted via CSS attribute
   selectors (text content not in style attribute).

   Uses MutationObserver — the shop form is rendered async after data
   fetch, so we watch for it and clean up on each render.
*/
(function(){
  'use strict';
  if (!/\/admin\/shop\.html?$|\/admin\/shop$/.test(location.pathname)) return;
  console.log('[dl-admin-shop]', 'loaded');

  function nukeTrustSignals(){
    // Find all divs with text starting with "✨ Shop Trust Signals"
    var divs = document.querySelectorAll('div');
    for (var i = 0; i < divs.length; i++) {
      var d = divs[i];
      var txt = (d.textContent || '').trim();
      // Kill the section header
      if (txt === '✨ Shop Trust Signals' && d.style.textTransform === 'uppercase') {
        d.style.display = 'none';
      }
      // Kill the blue info box mentioning verified_score
      if (txt.indexOf('These three fields power the Shop Highlights') !== -1) {
        d.style.display = 'none';
      }
    }
    // Also hide the <hr> that precedes the Trust Signals section
    var hrs = document.querySelectorAll('hr');
    for (var j = 0; j < hrs.length; j++) {
      var hr = hrs[j];
      var next = hr.nextElementSibling;
      if (next && (next.textContent || '').trim() === '✨ Shop Trust Signals') {
        hr.style.display = 'none';
      }
    }
  }

  function boot(){
    nukeTrustSignals();
    // Watch for the shop form to be rendered
    if (window.MutationObserver) {
      var obs = new MutationObserver(function(){ nukeTrustSignals(); });
      obs.observe(document.body, { childList: true, subtree: true });
    }
    // Also retry a few times as safety
    var tries = 0;
    var iv = setInterval(function(){
      tries++;
      nukeTrustSignals();
      if (tries > 20) clearInterval(iv);
    }, 300);
  }

  if (document.readyState !== 'loading') boot();
  else document.addEventListener('DOMContentLoaded', boot);
})();
