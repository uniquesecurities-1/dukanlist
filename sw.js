/* ============================================================
   DukanList Service Worker — v3.66.0 (REBUILT)
   ------------------------------------------------------------
   v3.66.0: CRITICAL REBUILD. The previous sw.js contained only a
   version constant and comments — zero event listeners — so push
   notifications never displayed and offline caching never worked,
   despite the full subscribe/broadcast infra existing.

   Handlers:
     - install  : precache core shell assets
     - activate : clean old caches, claim clients
     - fetch    : network-first for HTML, cache-first for static
                  assets; skips /admin/*, /panel/*, Supabase API,
                  non-GET, cross-origin (except our CDN icons)
     - push     : display notification. Payload from
                  api/push-broadcast.js + api/lead-push.js:
                  { title, body, url, image?, tag }
     - notificationclick : focus/open the target URL
   ============================================================ */

const VERSION = 'dukan-v3.66.0';
const CACHE_NAME = VERSION;

const PRECACHE = [
  '/',
  '/index.html',
  '/search.html',
  '/offline.html',
  '/assets/icons/icon-192.png',
  '/assets/icons/icon-96.png',
  '/manifest.webmanifest'
];

// ---------- install ----------
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(PRECACHE).catch(() => null))
      .then(() => self.skipWaiting())
  );
});

// ---------- activate ----------
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))
      ))
      .then(() => self.clients.claim())
  );
});

// ---------- fetch ----------
function shouldHandle(req) {
  if (req.method !== 'GET') return false;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return false;
  if (url.pathname.startsWith('/admin')) return false;
  if (url.pathname.startsWith('/panel')) return false;
  if (url.pathname.startsWith('/api/')) return false;
  if (url.hostname.endsWith('supabase.co')) return false;
  return true;
}

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (!shouldHandle(req)) return;

  const url = new URL(req.url);
  const isHTML = req.mode === 'navigate'
    || url.pathname.endsWith('.html')
    || url.pathname === '/';

  if (isHTML) {
    // Network-first: always fresh pages; cache fallback when offline
    event.respondWith(
      fetch(req)
        .then((res) => {
          if (res && res.ok) {
            const copy = res.clone();
            caches.open(CACHE_NAME).then((c) => c.put(req, copy)).catch(() => null);
          }
          return res;
        })
        .catch(() =>
          caches.match(req).then((hit) => hit || caches.match('/offline.html'))
        )
    );
  } else {
    // Static assets: cache-first, background refresh
    event.respondWith(
      caches.match(req).then((hit) => {
        const fetchAndCache = fetch(req)
          .then((res) => {
            if (res && res.ok) {
              const copy = res.clone();
              caches.open(CACHE_NAME).then((c) => c.put(req, copy)).catch(() => null);
            }
            return res;
          })
          .catch(() => hit);
        return hit || fetchAndCache;
      })
    );
  }
});

// ---------- push ----------
self.addEventListener('push', (event) => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; }
  catch (e) { data = { title: 'DukanList', body: event.data ? event.data.text() : '' }; }

  const title = data.title || 'DukanList';
  const options = {
    body: data.body || '',
    icon: '/assets/icons/icon-192.png',
    badge: '/assets/icons/icon-96.png',
    tag: data.tag || 'dukanlist',
    renotify: true,
    data: { url: data.url || '/' },
    vibrate: [100, 50, 100]
  };
  if (data.image) options.image = data.image;

  event.waitUntil(self.registration.showNotification(title, options));
});

// ---------- notificationclick ----------
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = (event.notification.data && event.notification.data.url) || '/';

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      // Focus an existing tab already on the target, else open new
      for (const client of list) {
        try {
          const cUrl = new URL(client.url);
          const tUrl = new URL(target, self.location.origin);
          if (cUrl.pathname === tUrl.pathname && 'focus' in client) {
            client.navigate(target).catch(() => null);
            return client.focus();
          }
        } catch (e) { /* ignore */ }
      }
      if (list.length > 0 && 'focus' in list[0]) {
        list[0].navigate(target).catch(() => null);
        return list[0].focus();
      }
      return self.clients.openWindow(target);
    })
  );
});
