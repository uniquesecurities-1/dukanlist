/* DL REGISTER SIMPLE (2026-07 v23)
   - Hides #professionalPanel + nullifies STATE.data.profTier
   - Auto-cascades State=Haryana → District=Sirsa → City=Mandi Dabwali
   - Hides all city options except Dabwali (locked-in default)
*/
(function(){
  'use strict';
  if (!/\/register\.html?$|\/register$/.test(location.pathname)) return;
  console.log('[dl-register] loaded v23');

  // 1. Hide professional panel via injected style tag
  var style = document.createElement('style');
  style.textContent = '#professionalPanel { display: none !important; }';
  (document.head || document.documentElement).appendChild(style);

  function keepPanelHidden(){
    var p = document.getElementById('professionalPanel');
    if (p && p.style.display !== 'none') p.style.display = 'none';
  }

  // 2. Auto-select an option by matching value/text substring
  function autoSelect(selectEl, matchStr, cb){
    if (!selectEl) return false;
    var target = matchStr.toLowerCase();
    for (var i = 0; i < selectEl.options.length; i++) {
      var v = (selectEl.options[i].value || '').toLowerCase();
      var t = (selectEl.options[i].textContent || '').toLowerCase();
      if (v.indexOf(target) !== -1 || t.indexOf(target) !== -1) {
        if (selectEl.selectedIndex === i) return true;
        selectEl.selectedIndex = i;
        try { selectEl.dispatchEvent(new Event('change', { bubbles: true })); } catch(_){}
        if (cb) setTimeout(cb, 200);
        return true;
      }
    }
    return false;
  }

  // 3. Hide all city options except Mandi Dabwali
  function lockCityToDabwali(){
    var citySel = document.getElementById('cityId');
    if (!citySel || citySel.options.length < 2) return false;
    var lockedCount = 0;
    for (var i = 0; i < citySel.options.length; i++) {
      var opt = citySel.options[i];
      var v = (opt.value || '').toLowerCase();
      var t = (opt.textContent || '').toLowerCase();
      var isDabwali = t.indexOf('dabwali') !== -1;
      var isPlaceholder = !v; // "-- Select city --"
      if (!isDabwali && !isPlaceholder) {
        opt.style.display = 'none';
        opt.disabled = true;
        lockedCount++;
      }
    }
    return lockedCount > 0;
  }

  // 4. Cascade select: State → District → City
  function cascadeDefaults(){
    var stateSel = document.getElementById('stateId');
    if (!stateSel || stateSel.options.length < 2) return;

    var stateOk = autoSelect(stateSel, 'haryana', function(){
      // Wait for districts to load
      waitForOptions('districtId', function(distSel){
        autoSelect(distSel, 'sirsa', function(){
          // Wait for cities to load
          waitForOptions('cityId', function(citySel){
            autoSelect(citySel, 'dabwali', function(){
              lockCityToDabwali();
            });
          });
        });
      });
    });
  }

  function waitForOptions(selId, cb){
    var tries = 0;
    var iv = setInterval(function(){
      tries++;
      var sel = document.getElementById(selId);
      if (sel && sel.options.length > 1) {
        clearInterval(iv);
        cb(sel);
      } else if (tries > 30) { // 6 sec max
        clearInterval(iv);
      }
    }, 200);
  }

  function boot(){
    keepPanelHidden();
    var panel = document.getElementById('professionalPanel');
    if (panel && window.MutationObserver) {
      new MutationObserver(function(){ keepPanelHidden(); })
        .observe(panel, { attributes: true, attributeFilter: ['style'] });
    }
    setInterval(function(){
      try {
        if (window.STATE && STATE.data && STATE.data.profTier) STATE.data.profTier = null;
      } catch(_){}
    }, 500);

    // Wait for state dropdown to populate then cascade
    waitForOptions('stateId', function(){ cascadeDefaults(); });
  }

  if (document.readyState !== 'loading') boot();
  else document.addEventListener('DOMContentLoaded', boot);
})();
