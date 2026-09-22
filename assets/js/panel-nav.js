/* ============================================================
   panel-nav.js — the shopkeeper panel's top navigation, once
   ============================================================
   v279. Thirteen panel pages carried a byte-identical copy of the
   14-link <nav>. Adding or renaming one page meant thirteen edits and,
   in practice, drift. Now each page ships an empty
       <nav class="nav-links" data-dl-nav="owner"></nav>
   followed by this script, which fills it synchronously (the element
   already exists when the script runs), so nav.js — which builds the
   hamburger from .nav-links on DOMContentLoaded — sees a full menu.

   Also marks the current page (aria-current="page" + .active), which
   the copied markup never did.

   To add a page: one entry in LINKS below.
============================================================ */
(function(){
  'use strict';

  var SUPPORT_WA = (window.DL_CONFIG && DL_CONFIG.support && DL_CONFIG.support.whatsapp) || '9541223377';

  var LINKS = [
    { href: '/panel/dashboard.html',     en: 'Dashboard',         hi: 'डैशबोर्ड' },
    { href: '/panel/profile.html',       en: 'Profile',           hi: 'प्रोफाइल' },
    { href: '/panel/photos.html',        en: '📸 Photos',         hi: '📸 फोटो' },
    { href: '/panel/services.html',      en: '🛠 Services',       hi: '🛠 सेवाएँ' },
    { href: '/panel/reviews.html',       en: '⭐ My Reviews',     hi: '⭐ मेरे रिव्यू' },
    { href: '/panel/get-reviews.html',   en: '🌟 Get Reviews',    hi: '🌟 रिव्यू लाएँ', style: 'color:#FBBF24;font-weight:800' },
    { href: '/panel/deals.html',         en: '🎁 Deals',          hi: '🎁 डील्स' },
    { href: '/panel/analytics.html',     en: '📊 Analytics',      hi: '📊 आँकड़े' },
    { href: '/panel/qr-code.html',       en: '🔗 QR Code',        hi: '🔗 QR कोड' },
    { href: '/panel/digital-card.html',  en: '📇 Digital Card',   hi: '📇 डिजिटल कार्ड' },
    { href: '/panel/poster-studio.html', en: '✨ Poster Studio',  hi: '✨ पोस्टर' },
    { href: '/pucho-bhai.html',          en: '💬 Pucho Bhai',     hi: '💬 पूछो भाई' },
    { href: 'https://wa.me/91' + SUPPORT_WA + '?text=Hello%20DukanList%20support',
                                         en: '🆘 Get Help',       hi: '🆘 मदद', external: true },
    { href: '#', onclick: 'ShopDB.signOut()', en: 'Logout', hi: 'Logout', cls: 'keep-en', style: 'color:#FCA5A5' }
  ];

  function esc(s){ return String(s).replace(/[&<>"]/g, function(c){ return { '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;' }[c]; }); }

  function currentPath(){
    var p = location.pathname.replace(/\/$/, '');
    if (!/\.html$/.test(p)) p += '.html';           // cleanUrls: /panel/photos → photos.html
    return p;
  }

  function render(nav){
    if (!nav || nav.getAttribute('data-dl-nav-rendered')) return;
    var here = currentPath();
    var html =
      '<div class="lang-toggle">' +
        '<button onclick="setLang(\'en\')" id="langBtnEn">EN</button>' +
        '<button onclick="setLang(\'hi\')" id="langBtnHi" class="keep-en">हिं</button>' +
      '</div>';
    for (var i = 0; i < LINKS.length; i++){
      var l = LINKS[i];
      var active = l.href === here;
      html += '<a href="' + esc(l.href) + '"' +
        (l.external ? ' target="_blank" rel="noopener"' : '') +
        (l.onclick ? ' onclick="' + esc(l.onclick) + '"' : '') +
        (active ? ' aria-current="page"' : '') +
        ((l.cls || active) ? ' class="' + [l.cls, active ? 'active' : ''].filter(Boolean).join(' ') + '"' : '') +
        (l.style ? ' style="' + esc(l.style) + '"' : '') + '>' +
        '<span data-i18n-en>' + esc(l.en) + '</span><span data-i18n-hi>' + esc(l.hi) + '</span></a>';
    }
    nav.innerHTML = html;
    nav.setAttribute('data-dl-nav-rendered', '1');

    if (!document.getElementById('dl-panel-nav-css')){
      var s = document.createElement('style');
      s.id = 'dl-panel-nav-css';
      s.textContent = '.nav-links a.active{ color:#fff; text-decoration:underline; text-decoration-color:#FF6B1A; text-underline-offset:5px; text-decoration-thickness:2px }';
      document.head.appendChild(s);
    }
  }

  function renderAll(){
    var navs = document.querySelectorAll('nav[data-dl-nav="owner"]');
    for (var i = 0; i < navs.length; i++) render(navs[i]);
  }

  renderAll();                                                   // element precedes this script
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', renderAll);

  window.DukanPanelNav = { LINKS: LINKS, render: renderAll };
})();
