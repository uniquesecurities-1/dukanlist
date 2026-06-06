/* ============================================================
   ptr.js — Pull-to-refresh for mobile listing pages
   ============================================================
   USAGE (on the page after DOM ready):
     DukanPTR.attach(window.location.pathname === '/' ? loadAllHomepageData : runSearch);

   Or with explicit options:
     DukanPTR.attach({
       onRefresh: async () => { await runSearch(); },
       threshold: 70   // pixels of pull before trigger
     });

   - Mobile only (auto-disables above 768px width)
   - Listens to touchstart/touchmove/touchend on document
   - Visual indicator: arrow icon that rotates when threshold crossed
   - "Loading…" state during refresh
   - No-op if scrollTop > 0 (only when at top of page)
============================================================ */
(function(global){
  'use strict';

  var THRESHOLD = 70;
  var MAX_PULL  = 130;
  var attached  = false;
  var refreshing = false;
  var startY = 0, currentY = 0, pulling = false;
  var onRefresh = null;
  var indicator = null;

  function isMobile(){ return window.innerWidth <= 768; }

  function getScrollTop(){
    return window.pageYOffset || document.documentElement.scrollTop || document.body.scrollTop || 0;
  }

  function ensureIndicator(){
    if (indicator) return indicator;
    indicator = document.createElement('div');
    indicator.id = 'dukanPTR';
    indicator.style.cssText = 'position:fixed;top:-60px;left:50%;transform:translateX(-50%) translateY(0px);background:#fff;border:1px solid #e2e8f0;border-radius:99px;padding:9px 18px;box-shadow:0 6px 20px rgba(15,23,42,.12);font-family:\'Plus Jakarta Sans\',\'Manrope\',sans-serif;font-size:13px;font-weight:700;color:#0F172A;z-index:9997;display:flex;align-items:center;gap:8px;transition:transform .2s ease-out;will-change:transform;pointer-events:none';
    indicator.innerHTML = '<span class="ptr-icon" style="display:inline-block;font-size:18px;transition:transform .2s ease">↓</span><span class="ptr-text">Pull to refresh</span>';
    document.body.appendChild(indicator);
    return indicator;
  }

  function setProgress(pullDist){
    if (!indicator) ensureIndicator();
    var capped = Math.min(pullDist, MAX_PULL);
    indicator.style.transform = 'translateX(-50%) translateY(' + (60 + capped * 0.7) + 'px)';
    var icon = indicator.querySelector('.ptr-icon');
    var text = indicator.querySelector('.ptr-text');
    if (capped >= THRESHOLD){
      icon.style.transform = 'rotate(180deg)';
      text.textContent = 'Release to refresh';
    } else {
      icon.style.transform = 'rotate(0deg)';
      text.textContent = 'Pull to refresh';
    }
  }

  function reset(){
    if (!indicator) return;
    indicator.style.transform = 'translateX(-50%) translateY(0px)';
    var icon = indicator.querySelector('.ptr-icon');
    icon.style.transform = 'rotate(0deg)';
  }

  function showLoading(){
    if (!indicator) ensureIndicator();
    indicator.style.transform = 'translateX(-50%) translateY(70px)';
    var icon = indicator.querySelector('.ptr-icon');
    var text = indicator.querySelector('.ptr-text');
    icon.style.transform = 'rotate(0deg)';
    icon.textContent = '↻'; // refresh symbol
    icon.style.animation = 'dukan-ptr-spin 0.9s linear infinite';
    text.textContent = 'Refreshing…';
  }

  function hideLoading(){
    if (!indicator) return;
    indicator.style.transform = 'translateX(-50%) translateY(0px)';
    var icon = indicator.querySelector('.ptr-icon');
    icon.style.animation = '';
    icon.textContent = '↓';
    indicator.querySelector('.ptr-text').textContent = 'Pull to refresh';
  }

  // Inject spin keyframes once
  function injectStyles(){
    if (document.getElementById('dukan-ptr-style')) return;
    var s = document.createElement('style');
    s.id = 'dukan-ptr-style';
    s.textContent = '@keyframes dukan-ptr-spin{from{transform:rotate(0)}to{transform:rotate(360deg)}}';
    document.head.appendChild(s);
  }

  function onTouchStart(e){
    if (!isMobile() || refreshing) return;
    if (getScrollTop() > 0) { pulling = false; return; }
    startY = e.touches[0].clientY;
    pulling = true;
  }

  function onTouchMove(e){
    if (!pulling) return;
    if (getScrollTop() > 0) { pulling = false; reset(); return; }
    currentY = e.touches[0].clientY;
    var dy = currentY - startY;
    if (dy <= 0) { reset(); return; }
    setProgress(dy);
  }

  function onTouchEnd(){
    if (!pulling) return;
    var dy = currentY - startY;
    pulling = false;
    if (dy >= THRESHOLD && !refreshing && typeof onRefresh === 'function'){
      refreshing = true;
      showLoading();
      Promise.resolve(onRefresh()).catch(function(){}).then(function(){
        refreshing = false;
        hideLoading();
      });
    } else {
      reset();
    }
  }

  function attach(cbOrOpts){
    if (attached) {
      // Allow re-binding the refresh callback
      onRefresh = (typeof cbOrOpts === 'function') ? cbOrOpts : (cbOrOpts && cbOrOpts.onRefresh) || onRefresh;
      return;
    }
    onRefresh = (typeof cbOrOpts === 'function') ? cbOrOpts : (cbOrOpts && cbOrOpts.onRefresh);
    if (cbOrOpts && cbOrOpts.threshold) THRESHOLD = cbOrOpts.threshold;
    injectStyles();
    document.addEventListener('touchstart', onTouchStart, { passive: true });
    document.addEventListener('touchmove',  onTouchMove,  { passive: true });
    document.addEventListener('touchend',   onTouchEnd,   { passive: true });
    attached = true;
  }

  global.DukanPTR = { attach: attach };
})(window);
