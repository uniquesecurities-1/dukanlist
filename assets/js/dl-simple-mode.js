/* ============================================================
   DL SIMPLE MODE — JS activator (2026-07)
   ------------------------------------------------------------
   Activates simple mode across pages by:
   1. Setting html[data-dl-simple-mode="true"]
   2. Adding body.prof-strict on business.html
      (uses page's built-in prof-strict CSS rules which hide
       reviews, ratings, USP, rating breakdown comprehensively)
   3. Setting up a MutationObserver so late-rendered widgets
      also get hidden (some sections render after Supabase fetch)

   Reversibility: Delete this file's <script> tag from HTML.
============================================================ */
(function(){
  'use strict';

  // Mark html with simple mode attribute (for CSS targeting)
  document.documentElement.setAttribute('data-dl-simple-mode', 'true');

  function activate(){
    // On business.html — trigger prof-strict body class
    // (this uses the page's OWN comprehensive hide CSS)
    if (location.pathname.indexOf('/business') === 0 ||
        location.pathname === '/business.html') {
      document.body.classList.add('prof-strict');
    }

    // Also mark body for any body-scoped hiding
    document.body.setAttribute('data-dl-simple-mode', 'true');
  }

  if (document.body) {
    activate();
  } else {
    document.addEventListener('DOMContentLoaded', activate);
  }

  // Late-render safety net: if page re-renders sections after Supabase fetch,
  // re-apply the class so hidden elements stay hidden.
  var reapplied = 0;
  var observer = new MutationObserver(function(mutations){
    if (reapplied > 20) { observer.disconnect(); return; } // safety
    if (!document.body.classList.contains('prof-strict') &&
        (location.pathname.indexOf('/business') === 0 ||
         location.pathname === '/business.html')) {
      document.body.classList.add('prof-strict');
      reapplied++;
    }
  });
  if (document.body) {
    observer.observe(document.body, { childList: true, subtree: false });
  } else {
    document.addEventListener('DOMContentLoaded', function(){
      observer.observe(document.body, { childList: true, subtree: false });
    });
  }
})();
