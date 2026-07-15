/* DL REGISTER SIMPLE (2026-07 v20)
   ------------------------------------------
   Golden Pages pivot: hides the "Professional Information Required"
   panel on register.html and forces it to stay hidden even when
   JS tries to show it for regulated categories (CA/Doctor/Lawyer/MFD).

   Keeps panel.style.display === 'none' inline so that
   collectProfessionalData() returns null → validation skips.
*/
(function(){
  'use strict';
  if (!/\/register\.html?$|\/register$/.test(location.pathname)) return;
  console.log('[dl-register]', 'loaded');

  function keepPanelHidden(){
    var panel = document.getElementById('professionalPanel');
    if (!panel) return;
    // Force inline display:none — this defeats both the display:'' clear
    // AND ensures collectProfessionalData()'s check passes
    if (panel.style.display !== 'none') {
      panel.style.display = 'none';
      console.log('[dl-register]', 'panel force-hidden');
    }
  }

  function boot(){
    keepPanelHidden();
    // Watch for style attribute changes on the panel
    var panel = document.getElementById('professionalPanel');
    if (panel && window.MutationObserver) {
      var obs = new MutationObserver(function(){ keepPanelHidden(); });
      obs.observe(panel, { attributes: true, attributeFilter: ['style'] });
    }
    // Also nuke profTier from STATE if it gets set
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
