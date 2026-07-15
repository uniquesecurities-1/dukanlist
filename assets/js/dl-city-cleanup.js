/* DL CITY CLEANUP (2026-07 v22)
   --------------------------------
   Golden Pages of Dabwali — hides/removes references to Sirsa,
   Bathinda, Mansa, Muktsar across the site, and pre-selects
   Mandi Dabwali as default city on register form.
*/
(function(){
  'use strict';
  var TAG = '[dl-city]';

  // 1. Pre-select Mandi Dabwali on any city dropdown
  function forceCityDabwali(){
    var selects = document.querySelectorAll('select#cityId, select#citySelect, select[name="city"]');
    for (var i = 0; i < selects.length; i++){
      var sel = selects[i];
      var opts = sel.options;
      for (var j = 0; j < opts.length; j++){
        var v = (opts[j].value || '').toLowerCase();
        var t = (opts[j].textContent || '').toLowerCase();
        if (v.indexOf('dabwali') !== -1 || t.indexOf('dabwali') !== -1) {
          sel.selectedIndex = j;
          // Fire change event so downstream logic runs (locality load etc.)
          try { sel.dispatchEvent(new Event('change', { bubbles: true })); } catch(_){}
          break;
        }
      }
      // Hide other city options (keep only Dabwali visible)
      for (var k = 0; k < opts.length; k++){
        var vv = (opts[k].value || '').toLowerCase();
        var tt = (opts[k].textContent || '').toLowerCase();
        if (vv && vv.indexOf('dabwali') === -1 && tt.indexOf('dabwali') === -1) {
          opts[k].style.display = 'none';
          opts[k].disabled = true;
        }
      }
    }
  }

  // 2. Nuke text nodes containing "Sirsa · Bathinda · Mansa · Muktsar" patterns
  var CITY_RE = /(·\s*(Sirsa|Bathinda|Mansa|Muktsar|Sri Muktsar Sahib|Malout|Gidderbaha|Hanumangarh|Rania|Ellenabad|Kalanwali|Fatehabad|Sri Ganganagar))+/gi;
  var CITY_LIST_RE = /Sirsa\s*[·,]\s*Bathinda\s*[·,]\s*Mansa\s*[·,]\s*Muktsar/gi;

  function nukeCityText(root){
    if (!root) root = document.body;
    if (!root) return;
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null, false);
    var toReplace = [];
    var n;
    while ((n = walker.nextNode())) {
      var t = n.nodeValue;
      if (!t) continue;
      if (CITY_LIST_RE.test(t) || CITY_RE.test(t)) {
        var newT = t.replace(CITY_LIST_RE, 'Mandi Dabwali').replace(CITY_RE, '');
        if (newT !== t) toReplace.push([n, newT]);
      }
      CITY_LIST_RE.lastIndex = 0;
      CITY_RE.lastIndex = 0;
    }
    toReplace.forEach(function(pair){ pair[0].nodeValue = pair[1]; });
  }

  // 3. Hide the 📍 area chip on business.html (redundant since all Dabwali)
  function hideBizLocation(){
    var ids = ['premAreaChip', 'premCityChip', 'premLocationChip', 'bizCityChip'];
    ids.forEach(function(id){
      var el = document.getElementById(id);
      if (el) el.style.display = 'none';
    });
  }

  function run(){
    try { forceCityDabwali(); } catch(e){ console.warn(TAG, 'city sel', e); }
    try { hideBizLocation(); } catch(e){ console.warn(TAG, 'biz loc', e); }
    try { nukeCityText(document.body); } catch(e){ console.warn(TAG, 'text', e); }
  }

  if (document.readyState !== 'loading') run();
  document.addEventListener('DOMContentLoaded', run);
  window.addEventListener('load', function(){ setTimeout(run, 400); });

  // Watch for late renders
  if (window.MutationObserver) {
    var obsCount = 0;
    var obs = new MutationObserver(function(){
      if (obsCount++ > 30) { obs.disconnect(); return; }
      run();
    });
    if (document.body) obs.observe(document.body, { childList: true, subtree: true });
    else document.addEventListener('DOMContentLoaded', function(){
      obs.observe(document.body, { childList: true, subtree: true });
    });
  }
})();
