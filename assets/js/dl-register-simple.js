/* DL REGISTER SIMPLE (2026-09 v25)
   - Hides #professionalPanel + nullifies STATE.data.profTier
   - Pre-selects Haryana / Sirsa / Mandi Dabwali as a CONVENIENCE default,
     because that is where most registrations come from — but leaves every
     dropdown fully usable.

   v25 — what changed and why
   --------------------------
   v24 did not default to Haryana, it LOCKED it:
     * CSS put `pointer-events:none` on #stateId/#districtId/#cityId, so the
       dropdowns could not even be opened;
     * every option except Haryana / Sirsa / Mandi Dabwali was set to
       display:none AND disabled;
     * a setInterval ran every 1.5s and snapped the selection back if it
       ever changed.
   The database has always had Punjab active with Bathinda, Mansa and Muktsar
   and 33 towns under them, and there are already live listings in Bathinda
   and Sangat. This script was the only thing standing between a Punjab
   shopkeeper and registering, and because the lock was in a separate file it
   looked from the page source as though everything was fine.
*/
(function(){
  'use strict';
  if (!/\/register\.html?$|\/register$/.test(location.pathname)) return;
  console.log('[dl-register] loaded v25 — geography unlocked (HR + PB)');

  // Professional panel stays hidden. That is a separate product decision and
  // is deliberately left exactly as it was.
  var style = document.createElement('style');
  style.textContent = '#professionalPanel { display: none !important; }';
  (document.head || document.documentElement).appendChild(style);

  function keepPanelHidden(){
    var p = document.getElementById('professionalPanel');
    if (p && p.style.display !== 'none') p.style.display = 'none';
  }

  function findOption(selectEl, matchStr){
    var target = matchStr.toLowerCase();
    for (var i = 0; i < selectEl.options.length; i++) {
      var v = (selectEl.options[i].value || '').toLowerCase();
      var t = (selectEl.options[i].textContent || '').toLowerCase();
      if (v.indexOf(target) !== -1 || t.indexOf(target) !== -1) return i;
    }
    return -1;
  }

  // Select a default WITHOUT hiding or disabling anything else.
  // Returns true if it selected something, false if the option wasn't there.
  function presetDefault(selId, matchStr, cb){
    var sel = document.getElementById(selId);
    if (!sel) return false;
    // Never override a choice the visitor has already made.
    if (sel.value) { if (cb) setTimeout(cb, 0); return true; }
    var idx = findOption(sel, matchStr);
    if (idx === -1) return false;
    sel.selectedIndex = idx;
    try { sel.dispatchEvent(new Event('change', { bubbles: true })); } catch(_){}
    if (cb) setTimeout(cb, 300);
    return true;
  }

  function waitForOptions(selId, cb){
    var tries = 0;
    var iv = setInterval(function(){
      tries++;
      var sel = document.getElementById(selId);
      if (sel && sel.options.length > 1) {
        clearInterval(iv);
        cb(sel);
      } else if (tries > 40) { clearInterval(iv); }
    }, 200);
  }

  // Runs ONCE. No enforcement loop — if the shopkeeper picks Punjab, it stays
  // Punjab.
  var defaultsApplied = false;
  function applyDefaultsOnce(){
    if (defaultsApplied) return;
    defaultsApplied = true;

    waitForOptions('stateId', function(){
      presetDefault('stateId', 'haryana', function(){
        waitForOptions('districtId', function(){
          presetDefault('districtId', 'sirsa', function(){
            waitForOptions('cityId', function(){
              presetDefault('cityId', 'dabwali', function(){
                var pin = document.getElementById('pincode');
                if (pin && !pin.value) {
                  pin.value = '125104';
                  try { pin.dispatchEvent(new Event('input',  { bubbles: true })); } catch(_){}
                  try { pin.dispatchEvent(new Event('change', { bubbles: true })); } catch(_){}
                }
                watchCityChanges();
              });
            });
          });
        });
      });
    });
  }

  // Mandi Dabwali has two pincodes, so register.html's own auto-fill does not
  // overwrite 125104 when the city changes. Left alone, a shop in Bathinda
  // would carry a Dabwali pincode into validation and be rejected with a
  // message that explains nothing. Clear it and let the city's own pincode
  // (or the shopkeeper) fill it.
  function watchCityChanges(){
    var city = document.getElementById('cityId');
    if (!city || city.dataset.pinWatch) return;
    city.dataset.pinWatch = '1';
    city.addEventListener('change', function(){
      var opt = city.options[city.selectedIndex];
      var isDabwali = opt && /dabwali/i.test(opt.textContent || '');
      var pin = document.getElementById('pincode');
      if (!pin || isDabwali) return;
      if (pin.value === '125104') {
        pin.value = '';
        try { pin.dispatchEvent(new Event('input', { bubbles: true })); } catch(_){}
      }
    });
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

    applyDefaultsOnce();
  }

  if (document.readyState !== 'loading') boot();
  else document.addEventListener('DOMContentLoaded', boot);
})();
