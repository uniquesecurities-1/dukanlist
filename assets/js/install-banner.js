/* ============================================================
   install-banner.js — Smart "Add to Home Screen" banner
   ============================================================
   Auto-shows a non-intrusive bottom banner promoting PWA install
   AFTER the user has visited >= 3 pages (engaged audience only).

   - First visit: silent (no banner, gives time to evaluate the site)
   - 3rd+ visit: banner slides up from bottom (~5s after load)
   - Dismissible (×) — remembers dismissal for 7 days
   - 'Install' button calls window.DukanInstall.prompt() from install.js
     so the same Android / iOS logic runs
   - Auto-hides if already installed (display-mode: standalone)
   - Hidden on /admin/ + /panel/ (those are owner/admin tools, not the
     PWA experience for end users)
============================================================ */
(function(){
  'use strict';

  var KEY_COUNT = 'dl_page_views';
  var KEY_DISMISSED_AT = 'dl_install_dismissed_at';
  var MIN_VIEWS = 3;
  var DISMISS_TTL_DAYS = 7;

  // Skip admin + panel pages
  if (/^\/(admin|panel)\b/i.test(location.pathname)) return;

  // Skip if already installed
  if (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches) return;
  if (window.navigator && window.navigator.standalone === true) return; // iOS

  // Count this page view
  var views = 0;
  try { views = parseInt(localStorage.getItem(KEY_COUNT) || '0', 10) || 0; } catch(_){}
  views++;
  try { localStorage.setItem(KEY_COUNT, String(views)); } catch(_){}

  if (views < MIN_VIEWS) return; // Wait for engagement

  // Check dismissal cooldown
  try {
    var dismissedAt = parseInt(localStorage.getItem(KEY_DISMISSED_AT) || '0', 10);
    if (dismissedAt > 0){
      var ageDays = (Date.now() - dismissedAt) / (24 * 3600 * 1000);
      if (ageDays < DISMISS_TTL_DAYS) return;
    }
  } catch(_){}

  function inject(){
    if (document.getElementById('dukanInstallBanner')) return;

    var bar = document.createElement('div');
    bar.id = 'dukanInstallBanner';
    bar.style.cssText = 'position:fixed;left:50%;transform:translateX(-50%) translateY(120%);bottom:74px;width:calc(100% - 24px);max-width:420px;background:#0F172A;color:#fff;border-radius:14px;box-shadow:0 14px 40px rgba(15,23,42,.32);padding:14px 16px;display:flex;align-items:center;gap:12px;z-index:9998;font-family:\'Plus Jakarta Sans\',\'Manrope\',-apple-system,sans-serif;transition:transform .35s cubic-bezier(.22,.61,.36,1)';
    bar.innerHTML =
      '<div style="font-size:32px;flex-shrink:0">📲</div>'
      + '<div style="flex:1;min-width:0">'
      +   '<div style="font-size:13px;font-weight:800;line-height:1.3"><span data-i18n-en>Add DukanList to your home screen</span><span data-i18n-hi>DukanList अपने होम स्क्रीन पर लगाएँ</span></div>'
      +   '<div style="font-size:11px;opacity:.75;margin-top:2px;line-height:1.4"><span data-i18n-en>Faster access · works offline</span><span data-i18n-hi>तेज़ एक्सेस · ऑफलाइन काम करे</span></div>'
      + '</div>'
      + '<button id="dukanInstallYes" style="background:#FF6B1A;color:#fff;border:none;padding:8px 14px;border-radius:8px;font-size:12px;font-weight:800;cursor:pointer;font-family:inherit;flex-shrink:0;letter-spacing:.01em"><span data-i18n-en>Install</span><span data-i18n-hi>इंस्टॉल</span></button>'
      + '<button id="dukanInstallNo" aria-label="Dismiss" style="background:transparent;color:rgba(255,255,255,.55);border:none;font-size:20px;cursor:pointer;padding:4px 8px;line-height:1;flex-shrink:0">×</button>';
    document.body.appendChild(bar);

    // Animate in
    setTimeout(function(){ bar.style.transform = 'translateX(-50%) translateY(0)'; }, 100);

    document.getElementById('dukanInstallYes').addEventListener('click', function(){
      // Prefer install.js's DukanInstall.prompt() if exposed; else just click the existing install button
      if (window.DukanInstall && typeof window.DukanInstall.prompt === 'function'){
        window.DukanInstall.prompt();
      } else {
        var btn = document.querySelector('#installBtn, [data-install-btn]');
        if (btn) btn.click();
        else alert('On iOS: tap Share → Add to Home Screen. On Android: open menu → Install app.');
      }
      dismiss(true);
    });
    document.getElementById('dukanInstallNo').addEventListener('click', function(){ dismiss(false); });
  }

  function dismiss(installed){
    var bar = document.getElementById('dukanInstallBanner');
    if (bar){
      bar.style.transform = 'translateX(-50%) translateY(120%)';
      setTimeout(function(){ if (bar.parentNode) bar.parentNode.removeChild(bar); }, 350);
    }
    try { localStorage.setItem(KEY_DISMISSED_AT, String(Date.now())); } catch(_){}
  }

  function ready(){
    setTimeout(inject, 5000); // show 5s after page settles
  }

  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', ready);
  } else {
    ready();
  }
})();
