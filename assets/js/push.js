/* ============================================================
   push.js — Web Push subscribe helper
   ============================================================
   USAGE on any page:
     <button id="enableNotifBtn">Enable notifications</button>
     <script>
       DukanPush.attachButton('enableNotifBtn', { audience: 'customer' });
       // or: 'shopkeeper'
     </script>

   Auto-detects already-subscribed state and updates button text.
   Skips render entirely on iOS Chrome (Safari WebView blocks Push).
============================================================ */
(function(global){
  'use strict';

  // ⚠ Public VAPID key — safe to embed client-side
  const VAPID_PUBLIC_KEY = 'BMswiGKd3NGj5ztwpE2IYXPnIW2s2cg3-G3yco1gUu2i_Jz7blIBzoJDO0vvkYjcsXDjcr7ae-O0kduiJfw0khQ';

  function isSupported(){
    return 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  }

  function urlBase64ToUint8Array(base64String){
    const padding = '='.repeat((4 - base64String.length % 4) % 4);
    const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
    const raw = atob(base64);
    const out = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; ++i) out[i] = raw.charCodeAt(i);
    return out;
  }

  function arrayBufferToBase64Url(buf){
    const bytes = new Uint8Array(buf);
    let bin = '';
    for (let i = 0; i < bytes.byteLength; i++) bin += String.fromCharCode(bytes[i]);
    return btoa(bin).replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
  }

  async function getRegistration(){
    if (!('serviceWorker' in navigator)) return null;
    const reg = await navigator.serviceWorker.ready;
    return reg;
  }

  async function currentSubscription(){
    const reg = await getRegistration();
    if (!reg || !reg.pushManager) return null;
    return await reg.pushManager.getSubscription();
  }

  async function subscribe(audience){
    if (!isSupported()) throw new Error('Push not supported on this browser');
    const perm = Notification.permission === 'granted'
      ? 'granted'
      : await Notification.requestPermission();
    if (perm !== 'granted') throw new Error('Permission denied');

    const reg = await getRegistration();
    if (!reg) throw new Error('Service worker not registered');

    let sub = await reg.pushManager.getSubscription();
    if (!sub){
      sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY)
      });
    }

    // Send to backend
    const keys = sub.toJSON().keys || {};
    const payload = {
      endpoint: sub.endpoint,
      p256dh:   keys.p256dh,
      auth:     keys.auth,
      audience: audience || 'customer',
      user_agent: (navigator.userAgent || '').slice(0, 200)
    };
    const c = window.ShopDB && ShopDB.client;
    if (c){
      const r = await c.rpc('subscribe_push', { p_data: payload });
      if (r.error) console.warn('subscribe_push:', r.error.message);
    }
    return sub;
  }

  async function unsubscribe(){
    const sub = await currentSubscription();
    if (sub) await sub.unsubscribe();
    return true;
  }

  function attachButton(btnId, opts){
    const btn = document.getElementById(btnId);
    if (!btn) return;

    if (!isSupported()){
      btn.style.display = 'none';
      return;
    }

    async function refresh(){
      const sub = await currentSubscription();
      if (sub){
        btn.dataset.state = 'on';
        btn.innerHTML = '🔔 Notifications enabled';
        btn.style.background = '#10B981';
      } else {
        btn.dataset.state = 'off';
        btn.innerHTML = '🔔 Enable notifications';
      }
    }

    btn.addEventListener('click', async () => {
      const orig = btn.innerHTML;
      btn.disabled = true; btn.innerHTML = '⏳ …';
      try {
        if (btn.dataset.state === 'on'){
          await unsubscribe();
          btn.innerHTML = '🔕 Notifications off';
        } else {
          await subscribe((opts && opts.audience) || 'customer');
          if (window.DukanAnn && DukanAnn) {/* noop */}
        }
      } catch(e){
        btn.innerHTML = orig;
        if (window.DukanLoginModal) {/* no-op */}
        alert('Could not enable notifications: ' + (e.message || e));
      } finally {
        btn.disabled = false;
        refresh();
      }
    });

    refresh();
  }

  global.DukanPush = { isSupported, subscribe, unsubscribe, attachButton, currentSubscription };
})(window);
