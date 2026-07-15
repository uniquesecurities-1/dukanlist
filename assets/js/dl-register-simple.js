/* DL REGISTER SIMPLE (2026-07 v24)
   - Hides #professionalPanel + nullifies STATE.data.profTier
   - LOCKS State=Haryana, District=Sirsa, City=Mandi Dabwali
   - Hides all other state/district/city options + prevents change
*/
(function(){
  'use strict';
  if (!/\/register\.html?$|\/register$/.test(location.pathname)) return;
  console.log('[dl-register] loaded v24');

  // 1. Hide professional panel
  var style = document.createElement('style');
  style.textContent = '#professionalPanel { display: none !important; }' +
    'select#stateId, select#districtId, select#cityId {' +
    ' background: #F0FDF4 !important; border-color: #10B981 !important;' +
    ' pointer-events: none !important; cursor: not-allowed !important; }';
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

  function lockDropdown(selId, matchStr, cb){
    var sel = document.getElementById(selId);
    if (!sel) return;
    var idx = findOption(sel, matchStr);
    if (idx === -1) return;
    sel.selectedIndex = idx;
    // Hide + disable all other options
    for (var i = 0; i < sel.options.length; i++) {
      if (i === idx) continue;
      var opt = sel.options[i];
      if (!opt.value) continue; // keep placeholder
      opt.style.display = 'none';
      opt.disabled = true;
    }
    try { sel.dispatchEvent(new Event('change', { bubbles: true })); } catch(_){}
    if (cb) setTimeout(cb, 300);
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

  function cascadeAndLock(){
    waitForOptions('stateId', function(){
      lockDropdown('stateId', 'haryana', function(){
        waitForOptions('districtId', function(){
          lockDropdown('districtId', 'sirsa', function(){
            waitForOptions('cityId', function(){
              lockDropdown('cityId', 'dabwali', function(){
                // Auto-fill pincode 125104 (Mandi Dabwali)
                var pin = document.getElementById('pincode');
                if (pin && !pin.value) {
                  pin.value = '125104';
                  try { pin.dispatchEvent(new Event('input', { bubbles: true })); } catch(_){}
                  try { pin.dispatchEvent(new Event('change', { bubbles: true })); } catch(_){}
                }
              });
            });
          });
        });
      });
    });
  }

  // Enforce every second — if user somehow changes, snap back
  function enforceLoop(){
    setInterval(function(){
      var stateSel = document.getElementById('stateId');
      var distSel = document.getElementById('districtId');
      var citySel = document.getElementById('cityId');
      if (stateSel && stateSel.options.length > 1) {
        var stateOpt = stateSel.options[stateSel.selectedIndex];
        var stateTxt = (stateOpt && stateOpt.textContent || '').toLowerCase();
        if (stateTxt.indexOf('haryana') === -1) {
          var hIdx = findOption(stateSel, 'haryana');
          if (hIdx !== -1) {
            stateSel.selectedIndex = hIdx;
            try { stateSel.dispatchEvent(new Event('change', { bubbles: true })); } catch(_){}
          }
        }
      }
      if (distSel && distSel.options.length > 1) {
        var distOpt = distSel.options[distSel.selectedIndex];
        var distTxt = (distOpt && distOpt.textContent || '').toLowerCase();
        if (distTxt.indexOf('sirsa') === -1) {
          var sIdx = findOption(distSel, 'sirsa');
          if (sIdx !== -1) {
            distSel.selectedIndex = sIdx;
            try { distSel.dispatchEvent(new Event('change', { bubbles: true })); } catch(_){}
          }
        }
      }
      if (citySel && citySel.options.length > 1) {
        var cityOpt = citySel.options[citySel.selectedIndex];
        var cityTxt = (cityOpt && cityOpt.textContent || '').toLowerCase();
        if (cityTxt.indexOf('dabwali') === -1) {
          var dIdx = findOption(citySel, 'dabwali');
          if (dIdx !== -1) citySel.selectedIndex = dIdx;
        }
      }
    }, 1500);
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

    cascadeAndLock();
    enforceLoop();
  }

  if (document.readyState !== 'loading') boot();
  else document.addEventListener('DOMContentLoaded', boot);
})();
