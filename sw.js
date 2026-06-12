/* ============================================================
   DukanList Service Worker
   Strategy:
     - install : precache key static assets
     - fetch   : network-first, fallback to cache
     - skip    : /admin/*, /panel/*, supabase API, POSTs, non-GET
   ============================================================ */
const VERSION    = 'dukan-v2.9.25';  // FIX — panel/profile.html Business Hours grid was overflowing mobile viewport. Old: grid-template-columns:100px 1fr 1fr auto — fixed 100px day label + two flex time inputs + auto Closed checkbox totaled too much for narrow phones, Closed column got pushed off-screen. Fixed: (a) day label 90px, time inputs minmax(0,1fr) with width:100% min-width:0 box-sizing:border-box, (b) mobile @media max-width:480px collapses to 3-column grid (62px day + 1fr + 1fr) with Closed checkbox grid-column:1/-1 justify-self:end so it wraps to its own row right-aligned. Also: Country code form-row 140px → 130px minmax(0,1fr) for same overflow safety. Wording: 'review your shop' → 'review your business'.
const STATIC_CACHE = 'dukan-static-' + VERSION;
const RUNTIME_CACHE = 'dukan-runtime-' + VERSION;

const PRECACHE_URLS = [
  '/',
  '/index.html',
  '/manifest.webmanifest',
  '/assets/css/main.css',
  '/assets/js/supabase-init.js',
  '/assets/js/nav.js',
  '/assets/js/hours.js',
  '/browse.html',
  '/search.html'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(STATIC_CACHE)
      .then((cache) => cache.addAll(PRECACHE_URLS).catch(() => {
        // Best-effort precache; individual misses must not block install
        return Promise.all(PRECACHE_URLS.map(u => cache.add(u).catch(() => null)));
      }))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter(k => k !== STATIC_CACHE && k !== RUNTIME_CACHE && k.startsWith('dukan-'))
          .map(k => caches.delete(k))
      )
    ).then(() => self.clients.claim())
  );
});

function shouldBypass(url, request) {
  if (request.method !== 'GET') return true;
  if (url.pathname.startsWith('/admin/')) return true;
  if (url.pathname.startsWith('/panel/')) return true;
  if (url.pathname.startsWith('/api/')) return true;
  // BYPASS frequently-updated pages so users always see fresh content.
  // CRITICAL: include ALL user-facing HTML pages here. Previously only
  // /discover and / were bypassed, so search.html and friends were served
  // from cache for hours after a deploy — fix updates never reached users.
  if (url.pathname === '/discover' || url.pathname === '/discover.html') return true;
  if (url.pathname === '/index.html' || url.pathname === '/') return true;
  if (url.pathname === '/search' || url.pathname === '/search.html') return true;
  if (url.pathname === '/browse' || url.pathname === '/browse.html') return true;
  if (url.pathname === '/business' || url.pathname === '/business.html') return true;
  if (url.pathname === '/shortlist' || url.pathname === '/shortlist.html') return true;
  if (url.pathname === '/register' || url.pathname === '/register.html') return true;
  // BYPASS any HTML at root (covers /local/* dynamic landing pages too)
  if (url.pathname.endsWith('.html')) return true;
  // BYPASS all app JS — they update frequently, must always be fresh
  if (url.pathname.startsWith('/assets/js/')) return true;
  // Supabase + auth endpoints
  if (url.hostname.endsWith('.supabase.co')) return true;
  if (url.hostname.endsWith('.supabase.in')) return true;
  // 3rd-party turnstile / cloudflare challenges
  if (url.hostname.includes('challenges.cloudflare.com')) return true;
  // Range requests (videos)
  if (request.headers.get('range')) return true;
  return false;
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  let url;
  try { url = new URL(request.url); } catch (e) { return; }

  // Only handle same-origin + key CDN assets
  const sameOrigin = url.origin === self.location.origin;
  const allowedCdn = url.hostname === 'fonts.googleapis.com'
    || url.hostname === 'fonts.gstatic.com'
    || url.hostname === 'cdn.jsdelivr.net';

  if (!sameOrigin && !allowedCdn) return;
  if (shouldBypass(url, request)) return;

  event.respondWith(
    fetch(request)
      .then((response) => {
        // Only cache successful, basic/cors responses
        if (!response || response.status !== 200) return response;
        if (response.type !== 'basic' && response.type !== 'cors') return response;
        const copy = response.clone();
        caches.open(RUNTIME_CACHE).then((cache) => {
          cache.put(request, copy).catch(() => {});
        });
        return response;
      })
      .catch(() => {
        return caches.match(request).then((cached) => {
          if (cached) return cached;
          // Fallback for navigations → cached index
          if (request.mode === 'navigate') {
            return caches.match('/index.html') || caches.match('/');
          }
          return new Response('Offline', {
            status: 503,
            statusText: 'Offline',
            headers: { 'Content-Type': 'text/plain' }
          });
        });
      })
  );
});

// Allow page to trigger immediate activation after update
self.addEventListener('message', (event) => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
});

// ============================================================
// PUSH NOTIFICATIONS HANDLER
// ============================================================
self.addEventListener('push', function(event){
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch(_) {
    try { data = { title: event.data.text() }; } catch(_) {}
  }
  const title = data.title || 'DukanList';
  const body  = data.body  || '';
  const url   = data.url   || '/';
  const opts = {
    body: body,
    icon: '/assets/icons/icon-192.png',
    badge: '/assets/icons/icon-96.png',
    image: data.image || undefined,
    tag:   data.tag   || 'dukanlist',
    requireInteraction: !!data.requireInteraction,
    data: { url: url, ...data.payload },
    vibrate: [180, 70, 180]
  };
  event.waitUntil(self.registration.showNotification(title, opts));
});

// On click — focus existing tab or open the URL
self.addEventListener('notificationclick', function(event){
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(list){
      for (const c of list){
        if (c.url.includes(url) && 'focus' in c) return c.focus();
      }
      if (clients.openWindow) return clients.openWindow(url);
    })
  );
});
