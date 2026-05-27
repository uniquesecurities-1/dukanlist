/* ============================================================
   ios-install.js — Show "Add to Home Screen" instructions for iOS Safari
   ------------------------------------------------------------
   Why this exists: Android Chrome shows automatic install banner,
   but iOS Safari does NOT have any equivalent. Users must MANUALLY
   tap "Share → Add to Home Screen". Most users don't know this.
   This banner shows them how — only on iOS Safari, only once.
============================================================ */
(function(){
  'use strict';
  const KEY = 'dl_ios_install_seen';

  // iOS detection
  const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream;
  if (!isIOS) return;

  // Already in standalone (installed) → skip
  if (window.navigator.standalone === true) return;

  // Already shown this session/recently → skip
  try {
    const seen = parseInt(localStorage.getItem(KEY) || '0', 10);
    if (seen && Date.now() - seen < 7 * 24 * 60 * 60 * 1000) return;  // skip for 7 days
  } catch(_){}

  // Wait 4 seconds before showing — let user explore first
  setTimeout(showBanner, 4000);

  function showBanner(){
    const b = document.createElement('div');
    b.id = 'dlIosInstall';
    b.style.cssText = [
      'position:fixed','bottom:80px','left:12px','right:12px','z-index:9998',
      'background:linear-gradient(135deg,#FFFFFF,#FFF7ED)',
      'border:1.5px solid #FB923C',
      'border-radius:16px',
      'padding:14px 16px',
      'box-shadow:0 14px 38px rgba(15,23,42,.18)',
      'font-family:"Plus Jakarta Sans","Manrope",-apple-system,sans-serif',
      'animation:dlIosSlide .35s cubic-bezier(.22,.61,.36,1)'
    ].join(';');
    b.innerHTML =
      '<style>@keyframes dlIosSlide{from{opacity:0;transform:translateY(20px)}to{opacity:1;transform:translateY(0)}}</style>' +
      '<div style="display:flex;align-items:flex-start;gap:12px">' +
        '<img src="/assets/icons/apple-touch-icon.png" alt="" style="width:48px;height:48px;border-radius:11px;flex-shrink:0;box-shadow:0 3px 8px rgba(249,115,22,.30)">' +
        '<div style="flex:1;min-width:0">' +
          '<div style="font-weight:800;font-size:14px;color:#0F172A;margin-bottom:2px">📲 Install DukanList on iPhone</div>' +
          '<div style="font-size:12px;color:#475569;line-height:1.45">' +
            'Tap <span style="display:inline-flex;align-items:center;padding:1px 5px;background:#EFF6FF;border:1px solid #BFDBFE;border-radius:5px;color:#1E40AF;font-weight:700">⎙</span> ' +
            '(share) below, then <b>"Add to Home Screen"</b>' +
          '</div>' +
        '</div>' +
        '<button id="dlIosClose" aria-label="Close" style="background:#F1F5F9;border:none;width:28px;height:28px;border-radius:50%;color:#64748b;font-size:16px;cursor:pointer;flex-shrink:0;line-height:1;padding:0">×</button>' +
      '</div>';
    document.body.appendChild(b);
    document.getElementById('dlIosClose').addEventListener('click', dismiss);
    // Auto-dismiss after 14 seconds
    setTimeout(dismiss, 14000);
  }

  function dismiss(){
    const b = document.getElementById('dlIosInstall');
    if (b){ b.style.opacity='0'; b.style.transition='opacity .35s'; setTimeout(function(){ b.remove(); }, 400); }
    try { localStorage.setItem(KEY, String(Date.now())); } catch(_){}
  }
})();
