/* ============================================================
   city-persist.js — Share selected city across all pages
   ============================================================
   Stores the last city the user picked (homepage / search / browse)
   in localStorage and pre-fills any <select id="citySelect"> or
   <select name="city"> found on the next page.

   Public API:
     DukanCity.get()           returns last saved slug, or '' if none
     DukanCity.set(slug)       persists a city slug
     DukanCity.attach(selectEl) wires read+write on a select element

   Auto-attaches to common selectors on DOMContentLoaded.
============================================================ */
(function(global){
  'use strict';
  var KEY = 'dl_city';

  function get(){
    try { return localStorage.getItem(KEY) || ''; } catch(_) { return ''; }
  }
  function set(slug){
    try { if (slug) localStorage.setItem(KEY, String(slug)); else localStorage.removeItem(KEY); } catch(_) {}
  }
  function attach(sel){
    if (!sel || sel.__dukanCityAttached) return;
    sel.__dukanCityAttached = true;
    var saved = get();
    if (saved){
      var hasOpt = false;
      for (var i = 0; i < sel.options.length; i++){
        if (sel.options[i].value === saved){ hasOpt = true; break; }
      }
      if (hasOpt) sel.value = saved;
    }
    sel.addEventListener('change', function(){ set(sel.value || ''); });
  }

  function autoAttach(){
    var candidates = document.querySelectorAll(
      'select#citySelect, select[name="city"], select#citySel'
    );
    candidates.forEach(attach);
  }

  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', autoAttach);
  } else {
    autoAttach();
  }

  global.DukanCity = { get: get, set: set, attach: attach };
})(window);
