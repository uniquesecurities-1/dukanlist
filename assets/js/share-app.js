/* ============================================================
   share-app.js — "Share DukanList" floating action button
   ============================================================
   Adds a small floating action button on homepage (and any page that
   includes this script) that lets users share DukanList with friends.

   - Uses native navigator.share() API on supported browsers (mobile)
   - Falls back to WhatsApp Web/App share URL on desktop
   - Auto-positions above the mobile bottom nav (avoids overlap)
   - Hidden on /admin/ and /panel/ pages (those are private tools)
============================================================ */
(function(){
  'use strict';

  if (/^\/(admin|panel)\b/i.test(location.pathname)) return;

  var SHARE_DATA = {
    title: 'DukanList — Every Shop, One App',
    text:  'Find any local shop in Sirsa-Bathinda on DukanList. Verified shopkeepers, free for customers.',
    url:   'https://dukanlist.com/'
  };

  function inject(){
    if (document.getElementById('dukanShareFab')) return;
    var btn = document.createElement('button');
    btn.id = 'dukanShareFab';
    btn.setAttribute('aria-label', 'Share DukanList');
    btn.style.cssText = 'position:fixed;right:14px;bottom:78px;width:48px;height:48px;border-radius:50%;background:#25D366;color:#fff;border:none;box-shadow:0 6px 20px rgba(37,211,102,.38);font-size:22px;cursor:pointer;z-index:9996;display:flex;align-items:center;justify-content:center;transition:transform .2s ease, box-shadow .2s ease;font-family:inherit';
    btn.innerHTML = '<svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor" aria-hidden="true"><path d="M18 16.08c-.76 0-1.44.3-1.96.77L8.91 12.7c.05-.23.09-.46.09-.7s-.04-.47-.09-.7l7.05-4.11c.54.5 1.25.81 2.04.81 1.66 0 3-1.34 3-3s-1.34-3-3-3-3 1.34-3 3c0 .24.04.47.09.7L8.04 9.81C7.5 9.31 6.79 9 6 9c-1.66 0-3 1.34-3 3s1.34 3 3 3c.79 0 1.5-.31 2.04-.81l7.12 4.16c-.05.21-.08.43-.08.65 0 1.61 1.31 2.92 2.92 2.92s2.92-1.31 2.92-2.92-1.31-2.92-2.92-2.92z"/></svg>';
    btn.onmouseenter = function(){ btn.style.transform = 'scale(1.08)'; btn.style.boxShadow = '0 8px 24px rgba(37,211,102,.5)'; };
    btn.onmouseleave = function(){ btn.style.transform = 'scale(1)'; btn.style.boxShadow = '0 6px 20px rgba(37,211,102,.38)'; };
    btn.onclick = doShare;
    document.body.appendChild(btn);
  }

  function doShare(){
    if (navigator.share){
      navigator.share(SHARE_DATA).catch(function(){ /* user canceled — silent */ });
      return;
    }
    // Fallback: WhatsApp share URL
    var msg = SHARE_DATA.text + '\n\n' + SHARE_DATA.url;
    var url = 'https://wa.me/?text=' + encodeURIComponent(msg);
    window.open(url, '_blank', 'noopener');
  }

  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', inject);
  } else {
    inject();
  }
})();
