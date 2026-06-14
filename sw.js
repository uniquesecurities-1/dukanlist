/* ============================================================
   DukanList Service Worker
   Strategy:
     - install : precache key static assets
     - fetch   : network-first, fallback to cache
     - skip    : /admin/*, /panel/*, supabase API, POSTs, non-GET
   ============================================================ */
const VERSION    = 'dukan-v2.9.55';  // OG IMAGE FALLBACK FIX — User reported WhatsApp preview showing no photo for Garg Medicose (business with no uploaded photos). Root cause: api/share.js fallback chain pointed at /api/og-card?slug=X for shops without photos, which returns an SVG. WhatsApp's preview crawler does NOT render SVG og:image — only PNG/JPEG. Result: blank preview for ALL businesses without photos (which is most of them initially). Fix: restored static PNG fallback (assets/og-default.png, 83KB) for both review-share and standard-share paths when biz.photos[0] and biz.og_image_url are absent. The /api/og-card endpoint still exists and can be used for direct embeds, but is no longer wired as og:image. Future enhancement (deferred): use @vercel/og to generate per-shop PNG OG cards with owner_name + city + rating — requires adding package.json + npm dep, not done in this hotfix.  // Previous v2.9.54: BMP-ONLY NUDGE EMOJIS — replaced supplementary-plane emojis (🙏 📷 🕐 etc.) with BMP equivalents (✨ ⭐ ⏰) to fix WhatsApp showing � replacement characters on devices with limited emoji font coverage. — User reported � (U+FFFD replacement character) still appearing in WhatsApp nudge message at 🙏 Namaste, 📷 Photos, 🕐 Business Hours. Root cause: those emojis are in Unicode Supplementary Plane (U+1F000+ range, 4-byte UTF-8) and user's device font cannot render them — Android shows U+FFFD instead of missing-glyph box. Fix: replaced ALL supplementary-plane emojis in admin/incomplete-shops.html buildNudgeMessage() with BMP-only equivalents (3-byte UTF-8) that render universally on every WhatsApp install including older phones: 🙏→✨, 📷→⭐, 🕐→⏰, ✨→✦ (already there), 📝→✎, 📍→◆, 📅→★, 🚩→⚑, 🔢→#, 🔗→☞, 💡→⚡, 🛡️→✔. Also fixed empty-state 🎉→✔ . Verified via Python scan — no chars > U+FFFF remain in nudge function.  // Previous v2.9.53: OG CARD OWNER LINE — Enhanced api/og-card.js to fetch owner_name + owner_role from Supabase and render an Owner attribution line in the dynamic 1200x630 SVG OG card. — Enhanced api/og-card.js to fetch owner_name + owner_role from Supabase and render a 'Owner: <Name>' attribution line in the dynamic 1200x630 SVG OG card. Now WhatsApp/Facebook/Twitter share previews show owner dignity alongside business name + city + stars. api/share.js was already wired to /api/og-card?slug=X (review mode) and /api/og-card?slug=X&mode=share (standard share) as og:image fallback chain after biz.og_image_url and biz.photos[0]. Owner line positioned at y=428 (below location) or y=390 (if no location); font-size 26px, weight 600, opacity 85% — subtle but readable. Owner role defaults to 'Owner' if not set; smart fallbacks for 'Founder', 'Partner', 'Director', etc.  // Previous v2.9.52: NUDGE MESSAGE UPGRADE — WhatsApp nudge message redesigned with modern visual hierarchy and inclusive language.
const STATIC_CACHE = 'dukan-static-' + VERSION;
const RUNTIME_CACHE = 'dukan-runtime-' + VERSION;

const PRECACHE_URLS = [
  '/',
  '/index.html',
  '/manifest.webmanifest',
  '/assets/css/main.css',
  '/assets/css/critical-homepage.css',
  '/assets/js/supabase-init.js',
  '/assets/js/nav.js',
  '/assets/js/hours.js',
  '/assets/js/homepage.js',
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
