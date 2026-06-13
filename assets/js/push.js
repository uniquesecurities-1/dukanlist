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

  // Pre-permission explainer modal — shown BEFORE browser permission dialog.
  // Best-practice UX: explains WHY before WHAT. Reduces permission-denial rate
  // and satisfies Play Store / app review guidelines on permission UX.
  function showPermissionExplainer(audience){
    return new Promise((resolve) => {
      // Safety: if already granted/denied, skip the modal
      if (Notification.permission === 'granted'){ resolve('skip-granted'); return; }
      if (Notification.permission === 'denied'){ resolve('skip-denied'); return; }
      const lang = (document.documentElement.dataset && document.documentElement.dataset.lang === 'hi') ? 'hi' : 'en';
      const isOwner = audience === 'shopkeeper' || audience === 'owner';
      const wrap = document.createElement('div');
      wrap.style.cssText = 'position:fixed;inset:0;z-index:99998;display:flex;align-items:flex-end;justify-content:center;background:rgba(15,23,42,.55);backdrop-filter:blur(6px);font-family:\'Plus Jakarta Sans\',\'Manrope\',-apple-system,sans-serif;animation:dpExpFadeIn .25s ease-out';
      const sty = document.createElement('style');
      sty.textContent = '@keyframes dpExpFadeIn{from{opacity:0}to{opacity:1}}@keyframes dpExpSlideUp{from{transform:translateY(100%)}to{transform:translateY(0)}}';
      wrap.appendChild(sty);
      const titleEn = isOwner ? 'Get notified about your shop' : 'Stay updated about local shops';
      const titleHi = isOwner ? 'अपनी दुकान के बारे में सूचनाएँ पाएँ' : 'स्थानीय व्यवसायों की अपडेट पाएँ';
      const bulletsEn = isOwner
        ? ['🔔 New customer reviews on your listing', '💬 Questions tagged to your shop in Pucho Bhai', '⭐ Important account alerts (verification, security)']
        : ['🆕 New verified shops in your area', '🔥 Trending businesses and weekly spotlights', '💬 Replies to your reviews or Pucho Bhai questions'];
      const bulletsHi = isOwner
        ? ['🔔 आपकी listing पर नए customer reviews', '💬 Pucho Bhai पर tag किए गए सवाल', '⭐ ज़रूरी account alerts (verification, security)']
        : ['🆕 आपके क्षेत्र की नई verified दुकानें', '🔥 Trending व्यवसाय और साप्ताहिक spotlight', '💬 आपके reviews या Pucho Bhai सवालों के जवाब'];
      const bullets = (lang === 'hi') ? bulletsHi : bulletsEn;
      const card = document.createElement('div');
      card.style.cssText = 'background:#fff;border-radius:20px 20px 0 0;max-width:480px;width:100%;padding:24px 22px 20px;box-shadow:0 -10px 40px rgba(0,0,0,.18);animation:dpExpSlideUp .28s cubic-bezier(.2,.85,.3,1.1)';
      card.innerHTML =
        '<div style="text-align:center;margin-bottom:14px"><div style="font-size:2.6rem;line-height:1">🔔</div></div>' +
        '<div style="font-size:1.18rem;font-weight:900;color:#0F172A;text-align:center;letter-spacing:-.015em;line-height:1.25;margin-bottom:6px">' + (lang === 'hi' ? titleHi : titleEn) + '</div>' +
        '<div style="font-size:.86rem;color:#64748b;text-align:center;line-height:1.5;margin-bottom:18px">' + (lang === 'hi' ? 'आप कुछ छोटी सूचनाओं के लिए सहमति देंगे। कभी भी disable कर सकते हैं।' : 'You\'ll receive a small number of relevant alerts. You can disable anytime from your phone Settings.') + '</div>' +
        '<ul style="list-style:none;padding:0;margin:0 0 18px;display:flex;flex-direction:column;gap:8px">' +
          bullets.map(b => '<li style="background:#FFFBEB;border:1px solid #FDE68A;border-radius:10px;padding:9px 12px;font-size:.86rem;color:#0F172A;line-height:1.4;font-weight:600">' + b + '</li>').join('') +
        '</ul>' +
        '<div style="background:#F8FAFC;border:1px solid #E2E8F0;border-radius:10px;padding:9px 12px;margin-bottom:14px;font-size:.74rem;color:#475569;text-align:center;line-height:1.5">' +
          (lang === 'hi' ? '🔒 कोई spam नहीं। हम कभी third party को नहीं देंगे। Privacy Policy देखें।' : '🔒 No spam. We never share with third parties. See Privacy Policy.') +
        '</div>' +
        '<div style="display:flex;gap:8px"><button type="button" id="dpExpSkip" style="flex:1;background:#F1F5F9;color:#475569;border:0;padding:13px;border-radius:11px;font-weight:700;font-size:.92rem;cursor:pointer;font-family:inherit">' + (lang === 'hi' ? 'अभी नहीं' : 'Not now') + '</button><button type="button" id="dpExpAllow" style="flex:2;background:linear-gradient(135deg,#FF6B1A,#E55100);color:#fff;border:0;padding:13px;border-radius:11px;font-weight:800;font-size:.96rem;cursor:pointer;font-family:inherit;box-shadow:0 4px 14px rgba(255,107,26,.35)">🔔 ' + (lang === 'hi' ? 'अनुमति दें' : 'Allow notifications') + '</button></div>';
      wrap.appendChild(card);
      document.body.appendChild(wrap);
      function cleanup(result){
        try { wrap.style.opacity = '0'; setTimeout(() => wrap.remove(), 220); } catch(_){}
        resolve(result);
      }
      card.querySelector('#dpExpAllow').addEventListener('click', () => cleanup('allow'));
      card.querySelector('#dpExpSkip').addEventListener('click', () => cleanup('skip'));
      wrap.addEventListener('click', (e) => { if (e.target === wrap) cleanup('skip'); });
    });
  }

  async function subscribe(audience){
    if (!isSupported()) throw new Error('Push not supported on this browser');
    // Step 1: pre-permission explainer (only if permission is still 'default')
    if (Notification.permission === 'default'){
      const choice = await showPermissionExplainer(audience);
      if (choice === 'skip'){ throw new Error('User chose Not now'); }
      // if 'allow', continue to browser-level requestPermission below
    }
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

  global.DukanPush = { isSupported, subscribe, unsubscribe, attachButton, currentSubscription, showPermissionExplainer };
})(window);
