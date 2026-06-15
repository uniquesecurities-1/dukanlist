/* ============================================================
   photo-fit.js — Adaptive object-fit for shop photos
   ============================================================
   PROBLEM: Owners upload photos in mixed aspect ratios (tall posters,
   wide facades, square IG-style). Cards use object-fit:cover which
   crops tall photos awkwardly — logos, signboards, faces get cut.

   SOLUTION: Detect each image's natural aspect ratio after load.
   - Tall portraits (ratio < 0.78) → switch to object-fit:contain
     with a soft cream gradient background so the FULL photo shows
     (letterboxed) instead of being cropped.
   - Everything else → keep object-fit:cover (default, works fine).

   FEATURES:
   - Universal: scans all <img> on the page after DOM ready.
   - Reactive: MutationObserver catches dynamically added images
     (e.g. cards loaded via async fetch).
   - Idempotent: each image processed once via data-fit-checked.
   - Robust: ignores images that aren't displayed in containers
     (icons, logos, decorative bg).

   ZERO RISK: only sets inline styles on <img> elements. Doesn't
   touch IDs, classes, handlers, or DB. Disable by removing the
   <script> include or by adding data-fit-skip="1" to an <img>.
============================================================ */
(function(){
  'use strict';

  // Portrait threshold — if image naturalWidth/naturalHeight < this,
  // we treat it as "tall" and switch to contain.
  // 0.78 ≈ slightly taller than 4:5 IG portrait.
  // Adjust higher to be more aggressive (more images get contain'd).
  var PORTRAIT_THRESHOLD = 0.78;

  // Soft branded background applied behind contained images
  var CONTAIN_BG = 'linear-gradient(135deg, #FFF7ED, #FFEDD5)';

  // Skip very small images (icons, logos, avatars under this size)
  var MIN_DISPLAY_SIZE_PX = 100;

  function processImg(img){
    if (img.dataset.fitChecked) return;
    if (img.dataset.fitSkip) return;

    var handle = function(){
      try {
        if (!img.naturalWidth || !img.naturalHeight) return;

        // Skip tiny decorative images
        var rect = img.getBoundingClientRect();
        if (rect.width < MIN_DISPLAY_SIZE_PX && rect.height < MIN_DISPLAY_SIZE_PX) return;

        var naturalRatio = img.naturalWidth / img.naturalHeight;

        if (naturalRatio < PORTRAIT_THRESHOLD){
          // Tall portrait — show full image with soft background
          img.style.objectFit = 'contain';

          // Set background on the IMG's parent if it's a "photo container"
          // (heuristic: parent has aspect-ratio defined OR has overflow:hidden)
          var parent = img.parentElement;
          if (parent){
            var cs = window.getComputedStyle(parent);
            var looksLikePhotoBox = (
              cs.aspectRatio !== 'auto' ||
              cs.overflow === 'hidden' ||
              parent.style.background === '' &&
                (cs.backgroundColor === 'rgba(0, 0, 0, 0)' || cs.backgroundColor === 'transparent')
            );
            if (looksLikePhotoBox && !parent.dataset.fitBgSet){
              // Only set if parent doesn't already have a strong background
              var existingBg = parent.style.background || cs.backgroundImage;
              if (!existingBg || existingBg === 'none'){
                parent.style.background = CONTAIN_BG;
                parent.dataset.fitBgSet = '1';
              }
            }
          }

          img.dataset.fitMode = 'contain';
        } else {
          // Landscape or square — cover is fine (default)
          img.dataset.fitMode = 'cover';
        }
      } catch(_){}
      img.dataset.fitChecked = '1';
    };

    if (img.complete && img.naturalWidth){
      handle();
    } else {
      img.addEventListener('load', handle, { once: true });
      // Also handle error gracefully (don't try forever)
      img.addEventListener('error', function(){ img.dataset.fitChecked = '1'; }, { once: true });
    }
  }

  function processAll(root){
    (root || document).querySelectorAll('img').forEach(processImg);
  }

  // Initial pass
  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', function(){ processAll(); });
  } else {
    processAll();
  }

  // Watch for dynamically added images (cards loaded via fetch, infinite scroll, etc.)
  var observer = new MutationObserver(function(mutations){
    mutations.forEach(function(m){
      m.addedNodes.forEach(function(node){
        if (node.nodeType !== 1) return;
        if (node.tagName === 'IMG'){
          processImg(node);
        } else if (node.querySelectorAll){
          node.querySelectorAll('img').forEach(processImg);
        }
      });
    });
  });

  // Wait for body
  function startObserver(){
    if (document.body){
      observer.observe(document.body, { childList: true, subtree: true });
    } else {
      setTimeout(startObserver, 50);
    }
  }
  startObserver();

  // Public API (optional usage from console / other scripts)
  window.DukanPhotoFit = {
    rescan: processAll,
    threshold: PORTRAIT_THRESHOLD,
    setThreshold: function(t){ PORTRAIT_THRESHOLD = t; }
  };
})();
