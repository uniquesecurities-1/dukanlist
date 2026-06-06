/* ============================================================
   install.js — PWA install entry with iOS + Android support
   ============================================================
   USAGE:
     <button id="installBtn">📲 Install App</button>
     <script src="/assets/js/install.js"></script>

     // Or any element with [data-install-btn]:
     <a data-install-btn href="#">Install DukanList</a>

   Android Chrome:
     - We capture the beforeinstallprompt event
     - Clicking the button fires prompt() — native install dialog
   iOS Safari:
     - No prompt API; we show an instruction modal with screenshots
     - "Tap Share button → Add to Home Screen"
   Already installed (display-mode: standalone):
     - Button auto-hides
============================================================ */
(function(global){
  'use strict';

  let deferredPrompt = null;
  const PLATFORM = (function(){
    const ua = (navigator.userAgent || '').toLowerCase();
    if (/iphone|ipad|ipod/.test(ua)) return 'ios';
    if (/android/.test(ua))          return 'android';
    return 'other';
  })();

  function isStandalone(){
    return (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches)
      || window.navigator.standalone === true;
  }

  function show(){
    if (isStandalone()) return; // already installed
    document.querySelectorAll('#installBtn, [data-install-btn]').forEach(b => {
      b.style.display = '';
      b.removeAttribute('hidden');
    });
  }
  function hide(){
    document.querySelectorAll('#installBtn, [data-install-btn]').forEach(b => {
      b.style.display = 'none';
    });
  }

  window.addEventListener('beforeinstallprompt', function(e){
    e.preventDefault();
    deferredPrompt = e;
    show();
  });

  window.addEventListener('appinstalled', function(){
    deferredPrompt = null;
    hide();
    toast('🎉 DukanList installed! Open it from your home screen anytime.');
  });

  async function trigger(){
    // Android Chrome path
    if (deferredPrompt){
      deferredPrompt.prompt();
      const { outcome } = await deferredPrompt.userChoice;
      deferredPrompt = null;
      if (outcome === 'accepted') hide();
      return;
    }
    // iOS Safari path — show instructions modal
    if (PLATFORM === 'ios'){
      openIosModal();
      return;
    }
    // Generic fallback
    openGenericModal();
  }

  function openIosModal(){
    showModal(
      '📲 Install DukanList on iPhone',
      '<div style="text-align:left;line-height:1.6;font-size:14px;color:#0F172A">'
        + '<p style="margin-bottom:12px"><b>3 steps:</b></p>'
        + '<ol style="padding-left:22px;display:flex;flex-direction:column;gap:9px">'
          + '<li>Safari ke <b>bottom me Share button</b> dabaye <span style="font-size:18px">⎘</span></li>'
          + '<li><b>"Add to Home Screen"</b> (होम स्क्रीन पर जोड़ें) chunein</li>'
          + '<li>Top-right <b>"Add"</b> dabaye — DukanList aapke home screen pe app ki tarah ready</li>'
        + '</ol>'
        + '<div style="margin-top:14px;padding:10px 14px;background:#FEF3C7;border-radius:8px;font-size:13px;color:#92400E">'
          + '⚠ <b>Note:</b> iPhone pe Chrome se add to home screen kaam nahi karta — Safari kholiye phir add kijiye.'
        + '</div>'
      + '</div>'
    );
  }

  function openGenericModal(){
    showModal(
      '📲 Install DukanList',
      '<div style="text-align:left;line-height:1.6;font-size:14px">'
        + '<p>Aapke browser me direct install option abhi nahi mil raha. Try this:</p>'
        + '<ul style="padding-left:22px;margin-top:8px;display:flex;flex-direction:column;gap:6px">'
          + '<li><b>Chrome (Android/Desktop):</b> Menu (⋮) → "Install app" / "Add to Home screen"</li>'
          + '<li><b>Safari (iPhone):</b> Share button → "Add to Home Screen"</li>'
          + '<li><b>Edge:</b> Address bar ke right pe "Install" icon dabaye</li>'
        + '</ul>'
      + '</div>'
    );
  }

  function showModal(title, html){
    let bg = document.getElementById('installModal');
    if (bg) bg.remove();
    bg = document.createElement('div');
    bg.id = 'installModal';
    bg.style.cssText = 'position:fixed;inset:0;background:rgba(15,23,42,.55);display:flex;align-items:center;justify-content:center;z-index:99999;padding:18px;animation:imFade .2s ease';
    bg.innerHTML = '<style>@keyframes imFade{from{opacity:0}to{opacity:1}}@keyframes imSlide{from{transform:translateY(20px);opacity:0}to{transform:translateY(0);opacity:1}}</style>'
      + '<div style="background:#fff;border-radius:18px;max-width:480px;width:100%;padding:24px 22px;box-shadow:0 24px 60px rgba(0,0,0,.25);animation:imSlide .25s cubic-bezier(.22,.61,.36,1);font-family:Manrope,Inter,-apple-system,sans-serif">'
        + '<div style="display:flex;justify-content:space-between;align-items:flex-start;gap:10px;margin-bottom:14px">'
          + '<h3 style="font-size:18px;font-weight:800;color:#0F172A;letter-spacing:-.01em;margin:0">' + esc(title) + '</h3>'
          + '<button onclick="document.getElementById(\'installModal\').remove()" style="background:#F1F5F9;border:0;width:32px;height:32px;border-radius:50%;font-size:18px;font-weight:700;color:#475569;cursor:pointer;flex-shrink:0">×</button>'
        + '</div>'
        + html
        + '<div style="margin-top:18px;display:flex;justify-content:flex-end">'
          + '<button onclick="document.getElementById(\'installModal\').remove()" style="background:linear-gradient(135deg,#FF6B1A,#E55100);color:#fff;border:0;padding:10px 22px;border-radius:9px;font-weight:700;font-size:14px;cursor:pointer">Theek Hai</button>'
        + '</div>'
      + '</div>';
    bg.addEventListener('click', function(e){ if (e.target === bg) bg.remove(); });
    document.body.appendChild(bg);
  }

  function toast(msg){
    let t = document.getElementById('__instToast');
    if (!t){
      t = document.createElement('div');
      t.id = '__instToast';
      t.style.cssText = 'position:fixed;bottom:24px;left:50%;transform:translateX(-50%);background:#0F172A;color:#fff;padding:12px 22px;border-radius:10px;font-size:14px;font-weight:600;z-index:99999;box-shadow:0 8px 24px rgba(15,23,42,.25);opacity:0;transition:opacity .2s';
      document.body.appendChild(t);
    }
    t.textContent = msg;
    t.style.opacity = '1';
    clearTimeout(t._tm);
    t._tm = setTimeout(() => { t.style.opacity = '0'; }, 3000);
  }

  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]); }

  // Wire up automatically
  document.addEventListener('DOMContentLoaded', function(){
    document.querySelectorAll('#installBtn, [data-install-btn]').forEach(b => {
      b.addEventListener('click', function(e){
        e.preventDefault();
        trigger();
      });
    });
    if (isStandalone()) hide();
    // Always show on iOS (no beforeinstallprompt event there)
    if (PLATFORM === 'ios' && !isStandalone()) show();
  });

  global.DukanInstall = { trigger, isStandalone, platform: PLATFORM };
})(window);
