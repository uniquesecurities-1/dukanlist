/* ============================================================
   pwa.js — Service-Worker registration + install banner
   Loaded on public pages: index, business, browse, search
   ============================================================ */
(function () {
  'use strict';

  // ---- Service Worker registration ----
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', function () {
      navigator.serviceWorker.register('/sw.js', { scope: '/' }).catch(function (err) {
        console.warn('SW registration failed:', err);
      });
    });
  }

  // ---- Install banner (mobile-first, dismissible) ----
  var DISMISS_KEY = 'dukan_pwa_dismissed_at';
  var DISMISS_DAYS = 7;
  var deferredPrompt = null;

  function isStandalone() {
    return (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches)
      || window.navigator.standalone === true;
  }

  function recentlyDismissed() {
    try {
      var ts = parseInt(localStorage.getItem(DISMISS_KEY) || '0', 10);
      if (!ts) return false;
      var ageMs = Date.now() - ts;
      return ageMs < DISMISS_DAYS * 24 * 60 * 60 * 1000;
    } catch (e) {
      return false;
    }
  }

  function isMobileLike() {
    var ua = (navigator.userAgent || '').toLowerCase();
    if (/android|iphone|ipod|ipad|mobile/.test(ua)) return true;
    return Math.min(window.innerWidth, window.innerHeight) <= 820;
  }

  function buildBanner(showInstallBtn) {
    if (document.getElementById('pwaBanner')) return null;
    var banner = document.createElement('div');
    banner.id = 'pwaBanner';
    banner.setAttribute('role', 'dialog');
    banner.setAttribute('aria-label', 'Install DukanList app');
    banner.style.cssText = [
      'position:fixed',
      'left:12px',
      'right:12px',
      'bottom:max(12px, env(safe-area-inset-bottom))',
      'background:#fff',
      'border:1px solid #E5E7EB',
      'border-radius:14px',
      'box-shadow:0 10px 30px rgba(15,23,42,.18)',
      'padding:12px 14px',
      'z-index:9998',
      'display:flex',
      'align-items:center',
      'gap:12px',
      'font-family:Inter,sans-serif',
      'transform:translateY(120%)',
      'opacity:0',
      'transition:transform .35s ease, opacity .35s ease',
      'max-width:520px',
      'margin:0 auto'
    ].join(';');
    banner.innerHTML =
      '<div style="font-size:1.6rem;line-height:1;flex-shrink:0">📱</div>' +
      '<div style="flex:1;min-width:0">' +
        '<div style="font-weight:800;font-size:.92rem;color:#0B1220;line-height:1.25">Install DukanList app</div>' +
        '<div style="font-size:.78rem;color:#6B7280;margin-top:2px;line-height:1.35">One-tap access — works offline. ' + (showInstallBtn ? '' : 'Tap browser menu → "Add to Home Screen".') + '</div>' +
      '</div>' +
      (showInstallBtn
        ? '<button id="pwaInstallBtn" style="background:linear-gradient(135deg,#FF6B1A,#E55100);color:#fff;border:none;padding:9px 14px;border-radius:9px;font-weight:800;font-size:.85rem;cursor:pointer;font-family:inherit;min-height:38px;white-space:nowrap">Install</button>'
        : '') +
      '<button id="pwaCloseBtn" aria-label="Dismiss" style="background:transparent;border:none;color:#6B7280;font-size:1.3rem;cursor:pointer;padding:4px 6px;line-height:1;font-family:inherit">&times;</button>';
    document.body.appendChild(banner);
    // Slide in
    requestAnimationFrame(function () {
      banner.style.transform = 'translateY(0)';
      banner.style.opacity = '1';
    });
    return banner;
  }

  function dismissBanner() {
    var banner = document.getElementById('pwaBanner');
    if (!banner) return;
    banner.style.transform = 'translateY(120%)';
    banner.style.opacity = '0';
    setTimeout(function () { if (banner.parentNode) banner.parentNode.removeChild(banner); }, 350);
    try { localStorage.setItem(DISMISS_KEY, String(Date.now())); } catch (e) {}
  }

  function wireBanner(banner) {
    if (!banner) return;
    var closeBtn = document.getElementById('pwaCloseBtn');
    if (closeBtn) closeBtn.addEventListener('click', dismissBanner);
    var installBtn = document.getElementById('pwaInstallBtn');
    if (installBtn) {
      installBtn.addEventListener('click', async function () {
        if (!deferredPrompt) {
          dismissBanner();
          return;
        }
        try {
          deferredPrompt.prompt();
          var choice = await deferredPrompt.userChoice;
          if (choice && choice.outcome === 'accepted') {
            dismissBanner();
          } else {
            dismissBanner();
          }
        } catch (e) {
          console.warn('Install prompt failed:', e);
          dismissBanner();
        }
        deferredPrompt = null;
      });
    }
  }

  function maybeShowBanner() {
    if (isStandalone()) return;
    if (recentlyDismissed()) return;
    if (!isMobileLike()) return;
    // Show after 2.5s so the banner doesn't interrupt initial paint
    setTimeout(function () {
      if (isStandalone() || recentlyDismissed()) return;
      var banner = buildBanner(!!deferredPrompt);
      wireBanner(banner);
    }, 2500);
  }

  // beforeinstallprompt may fire even after our timer — handle both orders
  window.addEventListener('beforeinstallprompt', function (e) {
    e.preventDefault();
    deferredPrompt = e;
    // If a banner is already shown without Install btn, re-build with it
    var existing = document.getElementById('pwaBanner');
    if (existing) {
      existing.parentNode.removeChild(existing);
      if (!recentlyDismissed() && !isStandalone()) {
        var banner = buildBanner(true);
        wireBanner(banner);
      }
    }
  });

  window.addEventListener('appinstalled', function () {
    try { localStorage.setItem(DISMISS_KEY, String(Date.now())); } catch (e) {}
    dismissBanner();
    deferredPrompt = null;
  });

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', maybeShowBanner);
  } else {
    maybeShowBanner();
  }
})();
