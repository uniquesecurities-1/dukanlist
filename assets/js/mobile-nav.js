/* ============================================================
   mobile-nav.js — Sticky bottom navigation bar (mobile only ≤700px)
   ============================================================
   USAGE: include on any public page. Auto-injects a fixed bottom
   navigation strip with: 🏠 Home / 🗂 Browse / 🔍 Search /
   🏪 Register / 👤 Account.

   - Auto-hides above 700px (desktop)
   - Active route is highlighted based on current URL
   - Body gets bottom-padding so content isn't hidden
============================================================ */
(function(global){
  'use strict';

  const ITEMS = [
    { href: '/',            icon: '🏠', label: 'Home',     match: /^\/(index\.html)?$/ },
    { href: '/browse',      icon: '🗂', label: 'Browse',   match: /^\/browse(\.html)?$/ },
    { href: '/search.html', icon: '🔍', label: 'Search',   match: /^\/search(\.html)?$/ },
    { href: '/register.html', icon: '🏪', label: 'Register', match: /^\/register(\.html)?$/ },
    { href: '/panel/login.html', icon: '👤', label: 'Account', match: /^\/panel\// }
  ];

  function inject(){
    // Already injected?
    if (document.getElementById('mobileBottomNav')) return;
    // Skip on admin / panel pages (they have their own UI)
    const path = location.pathname;
    if (/^\/admin\//.test(path)) return;

    const nav = document.createElement('nav');
    nav.id = 'mobileBottomNav';
    nav.setAttribute('aria-label', 'Mobile navigation');

    const html = ITEMS.map(item => {
      const active = item.match.test(path);
      return `<a href="${item.href}" class="${active ? 'active' : ''}" aria-label="${item.label}">
        <span class="ico">${item.icon}</span>
        <span class="lbl">${item.label}</span>
      </a>`;
    }).join('');

    nav.innerHTML = html + `<style>
      #mobileBottomNav{
        position:fixed; bottom:0; left:0; right:0; z-index:90;
        display:none;
        background:rgba(255,255,255,.96); backdrop-filter:saturate(180%) blur(12px);
        border-top:1px solid rgba(15,23,42,.08);
        box-shadow:0 -4px 14px rgba(15,23,42,.06);
        padding-bottom:env(safe-area-inset-bottom,0);
      }
      @media (max-width:700px){ #mobileBottomNav{ display:flex } body{ padding-bottom:62px } }
      #mobileBottomNav > a{
        flex:1; display:flex; flex-direction:column; align-items:center; gap:2px;
        padding:8px 4px 6px; text-decoration:none; color:#64748b; font-size:11px; font-weight:700;
        transition:.15s; letter-spacing:.01em;
      }
      #mobileBottomNav > a .ico{ font-size:20px; line-height:1 }
      #mobileBottomNav > a .lbl{ font-size:10px; font-weight:700 }
      #mobileBottomNav > a:hover{ color:#FF6B1A }
      #mobileBottomNav > a.active{ color:#FF6B1A }
      #mobileBottomNav > a.active .ico{ transform:translateY(-1px); filter:drop-shadow(0 2px 4px rgba(255,107,26,.3)) }
    </style>`;

    document.body.appendChild(nav);
  }

  // Inject when DOM ready
  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', inject);
  } else {
    inject();
  }

  global.DukanMobileNav = { inject };
})(window);
