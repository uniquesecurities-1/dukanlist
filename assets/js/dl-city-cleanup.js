/* DL CITY CLEANUP (2026-09 v23)
   --------------------------------
   Left over from the "Golden Pages of Dabwali" phase, when the site was
   deliberately narrowed to one town.

   v23 — city dropdowns are no longer locked.
   v22 selected Mandi Dabwali and then set display:none + disabled on every
   other city option, on search, browse, discover and the register form. The
   site has since reopened to Sirsa, Bathinda, Mansa and Muktsar — the footer
   and the Pulse card say so, and there are live listings in Bathinda and
   Sangat — so this was stopping customers from filtering to a Punjab town and
   stopping those shopkeepers from registering. Dabwali is still pre-selected
   as a sensible default; nothing is hidden or disabled any more.

   STILL ACTIVE (cosmetic, from the same phase — review when convenient):
     * nukeCityText()   strips "Sirsa · Bathinda · Mansa · Muktsar" runs out of
                        visible text
     * hideBizLocation() hides the city/area chip on a listing page
*/
(function(){
  'use strict';
  var TAG = '[dl-city]';

  // 1. Pre-select Mandi Dabwali on any city dropdown — as a DEFAULT only.
  //    Nothing is hidden and nothing is disabled: the other towns have to stay
  //    reachable or neither customers nor shopkeepers can leave Dabwali.
  //    Runs once, and never overrides a choice the visitor has already made.
  var citySelectsSeeded = [];
  function forceCityDabwali(){
    var selects = document.querySelectorAll('select#cityId, select#citySelect, select[name="city"]');
    for (var i = 0; i < selects.length; i++){
      var sel = selects[i];
      if (citySelectsSeeded.indexOf(sel) !== -1) continue;   // already defaulted
      if (sel.options.length < 2) continue;                  // not populated yet
      citySelectsSeeded.push(sel);
      if (sel.value) continue;                               // visitor already chose
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
