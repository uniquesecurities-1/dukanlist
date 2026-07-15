/* DL REGISTER SIMPLE (2026-07 v20)
   Self-contained: injects own <style> for #professionalPanel hide,
   plus MutationObserver + STATE nullifier so validation skips.
*/
(function(){
  'use strict';
  if (!/\/register\.html?$|\/register$/.test(location.pathname)) return;
  console.log('[dl-register]', 'loaded');

  var style = document.createElement('style');
  style.textContent = '#professionalPanel { display: none !important; }';
  (document.head || document.documentElement).appendChild(style);

  function keepPanelHidden(){
    var panel = document.getElementById('professionalPanel');
    if (!panel) return;
    if (panel.style.display !== 'none') panel.style.display = 'none';
  }

  function boot(){
    keepPanelHidden();
    var panel = document.getElementById('professionalPanel');
    if (panel && window.MutationObserver) {
      var obs = new MutationObserver(function(){ keepPanelHidden(); });
      obs.observe(panel, { attributes: true, attributeFilter: ['style'] });
    }
    setInterval(function(){
      try {
        if (window.STATE && STATE.data && STATE.data.profTier) {
          STATE.data.profTier = null;
        }
      } catch(_){}
    }, 500);
  }

  if (document.readyState !== 'loading') boot();
  else document.addEventListener('DOMContentLoaded', boot);
})();
