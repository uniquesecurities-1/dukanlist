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
     DukanCity.chosen()        true once the visitor has picked anything —
                               including "all" (which saves as '')
     DukanCity.slugOrDefault(d) the slug for city-scoped queries:
                               picked city → its slug; picked "all" → null;
                               never picked → d (the site default)
     DukanCity.name()          display name of the saved slug, from any
                               city <select> on the page, else the slug

   v278: this is the ONE store for the visitor's area. Before, the
   homepage had three: the "Pick your area" modal wrote dl_locality_v1
   (nothing read it), Local Pulse read a CityPersist global that did not
   exist, and Browse-by-area read 'dukanlist.city' (nothing wrote it).
   Legacy keys are migrated once, then ignored.

   Auto-attaches to common selectors on DOMContentLoaded.
============================================================ */
(function(global){
  'use strict';
  var KEY = 'dl_city', CHOSEN = 'dl_city_chosen';

  // One-time migration from the two dead keys (see header).
  try {
    if (!localStorage.getItem(KEY) && !localStorage.getItem(CHOSEN)){
      var legacy = null;
      try { legacy = JSON.parse(localStorage.getItem('dl_locality_v1') || 'null'); } catch(_){}
      var slug = legacy && legacy.slug ? String(legacy.slug) : (localStorage.getItem('dukanlist.city') || '');
      if (slug){
        slug = slug.toLowerCase().trim().replace(/\s+/g, '-');
        localStorage.setItem(CHOSEN, '1');
        if (slug !== 'all') localStorage.setItem(KEY, slug);
      }
    }
  } catch(_) {}

  function get(){
    try { return localStorage.getItem(KEY) || ''; } catch(_) { return ''; }
  }
  function chosen(){
    try { return !!(localStorage.getItem(CHOSEN) || localStorage.getItem(KEY)); } catch(_) { return false; }
  }
  function set(slug){
    slug = slug === 'all' ? '' : String(slug || '');
    var before = get();
    try {
      if (slug) localStorage.setItem(KEY, slug); else localStorage.removeItem(KEY);
      localStorage.setItem(CHOSEN, '1');
    } catch(_) {}
    if (before !== slug){
      try { global.dispatchEvent(new CustomEvent('dl:city', { detail: { slug: slug, previous: before } })); } catch(_) {}
    }
  }
  function slugOrDefault(def){
    var s = get();
    if (s) return s;
    return chosen() ? null : (def || null);
  }
  function name(){
    var s = get();
    if (!s) return '';
    var opt = document.querySelector('select#citySelect option[value="' + s + '"], select[name="city"] option[value="' + s + '"]');
    return opt ? opt.textContent.trim() : s.replace(/-/g, ' ').replace(/\b\w/g, function(c){ return c.toUpperCase(); });
  }
  function attach(sel){
    if (!sel || sel.__dukanCityAttached) return;
    sel.__dukanCityAttached = true;
    var saved = get();
    if (!saved && chosen()){
      // visitor picked 'all' — show the blank 'Select city' option, not the default town
      for (var k = 0; k < sel.options.length; k++){ if (sel.options[k].value === ''){ sel.value = ''; break; } }
    }
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

  global.DukanCity = { get: get, set: set, attach: attach, chosen: chosen, slugOrDefault: slugOrDefault, name: name };
})(window);
