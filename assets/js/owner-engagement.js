/* ============================================================
   owner-engagement.js — Daily reasons for shopkeepers to return
   ============================================================
   Mounts 3 widgets on the owner panel dashboard:
     1. 🔥 Streak counter — localStorage-tracked login streak
     2. 📊 Yesterday's digest — view/call/WA counts for last 24h
     3. 💡 Today's Quick Win — single rotating high-value action
     4. 📨 Morning digest opt-in — saves preference for backend cron

   Public API:
     window.DukanOwnerEng.init(biz)   — call once after BIZ loads
     window.DukanOwnerEng.bumpStreak() — call on app actions

   Storage keys (localStorage):
     dl_owner_streak       — { count, lastSeenDay, longest }
     dl_owner_digest_optin — '1' or '0'
     dl_owner_qw_seen      — { qwId: lastTimestampMs }
============================================================ */
(function(global){
  'use strict';

  // ---------- Streak ----------
  const STREAK_KEY = 'dl_owner_streak';
  function ymd(d){ d = d || new Date(); return d.getFullYear() + '-' + String(d.getMonth()+1).padStart(2,'0') + '-' + String(d.getDate()).padStart(2,'0'); }
  function loadStreak(){
    try { return JSON.parse(localStorage.getItem(STREAK_KEY) || 'null') || { count:0, lastSeenDay:'', longest:0 }; }
    catch(_){ return { count:0, lastSeenDay:'', longest:0 }; }
  }
  function saveStreak(s){ try { localStorage.setItem(STREAK_KEY, JSON.stringify(s)); } catch(_){} }
  function bumpStreak(){
    const today = ymd();
    const s = loadStreak();
    if (s.lastSeenDay === today) return s;  // already counted today

    // Was the last visit YESTERDAY?
    const yest = new Date(); yest.setDate(yest.getDate() - 1);
    const yestKey = ymd(yest);
    if (s.lastSeenDay === yestKey){
      s.count = (s.count || 0) + 1;
    } else if (!s.lastSeenDay){
      // First-ever visit
      s.count = 1;
    } else {
      // Gap broken — restart at 1
      s.count = 1;
    }
    if ((s.count || 0) > (s.longest || 0)) s.longest = s.count;
    s.lastSeenDay = today;
    saveStreak(s);
    return s;
  }

  function renderStreakBanner(){
    const s = bumpStreak();
    const host = document.getElementById('ownerStreakBanner');
    if (!host) return;
    const n = s.count || 1;
    const longest = s.longest || n;
    let title, sub, color;
    if (n >= 30){
      title = '🏆 ' + n + '-day streak! Top-tier consistency';
      sub = 'Your daily presence is what wins customer trust.';
      color = 'linear-gradient(135deg,#FBBF24,#D97706)';
    } else if (n >= 14){
      title = '🔥 ' + n + '-day streak! On fire';
      sub = 'Keep the momentum — 30 days unlocks the Top-tier badge.';
      color = 'linear-gradient(135deg,#F97316,#DC2626)';
    } else if (n >= 7){
      title = '🔥 ' + n + '-day streak! Going strong';
      sub = 'Don\'t break it — return tomorrow to keep the chain alive.';
      color = 'linear-gradient(135deg,#FB923C,#EA580C)';
    } else if (n >= 3){
      title = '✨ ' + n + '-day streak! Building habit';
      sub = 'Daily check-ins improve your shop ranking over time.';
      color = 'linear-gradient(135deg,#3B82F6,#1D4ED8)';
    } else {
      title = '🌱 Day ' + n + ' — welcome back';
      sub = 'Visit daily to grow your shop\'s reach.';
      color = 'linear-gradient(135deg,#10B981,#059669)';
    }
    host.innerHTML =
      '<div style="background:' + color + ';color:#fff;border-radius:14px;padding:14px 18px;display:flex;align-items:center;gap:14px;box-shadow:0 8px 24px rgba(15,23,42,.12);margin-bottom:16px">'
      + '<div style="font-size:2.4rem;flex-shrink:0;line-height:1">' + (n >= 7 ? '🔥' : (n >= 3 ? '✨' : '🌱')) + '</div>'
      + '<div style="flex:1;min-width:0">'
      +   '<div style="font-weight:900;font-size:1rem;letter-spacing:-.01em">' + escapeHtml(title) + '</div>'
      +   '<div style="font-size:.8rem;opacity:.92;margin-top:2px;font-weight:600">' + escapeHtml(sub) + '</div>'
      + '</div>'
      + (longest > n ? '<div style="text-align:right;flex-shrink:0;font-size:.72rem;font-weight:700;opacity:.85;background:rgba(255,255,255,.18);padding:5px 11px;border-radius:99px">Best: ' + longest + ' days</div>' : '')
      + '</div>';
    host.style.display = '';
  }

  // ---------- Yesterday's Digest ----------
  async function loadYesterdayDigest(biz){
    if (!biz || !biz.id) return null;
    if (typeof ShopDB === 'undefined' || !ShopDB || !ShopDB.client) return null;
    const c = ShopDB.client;
    // Range = yesterday in IST (00:00 → 23:59)
    const now = new Date();
    const yesterdayStart = new Date(now); yesterdayStart.setDate(yesterdayStart.getDate() - 1); yesterdayStart.setHours(0,0,0,0);
    const yesterdayEnd = new Date(yesterdayStart); yesterdayEnd.setHours(23,59,59,999);
    try {
      const [{ count: viewC }, { count: callC }, { count: waC }, { count: revC }] = await Promise.all([
        c.from('leads').select('id', { count:'exact', head:true }).eq('business_id', biz.id).eq('action', 'view').gte('created_at', yesterdayStart.toISOString()).lte('created_at', yesterdayEnd.toISOString()),
        c.from('leads').select('id', { count:'exact', head:true }).eq('business_id', biz.id).eq('action', 'call').gte('created_at', yesterdayStart.toISOString()).lte('created_at', yesterdayEnd.toISOString()),
        c.from('leads').select('id', { count:'exact', head:true }).eq('business_id', biz.id).in('action', ['whatsapp', 'wa']).gte('created_at', yesterdayStart.toISOString()).lte('created_at', yesterdayEnd.toISOString()),
        c.from('reviews').select('id', { count:'exact', head:true }).eq('business_id', biz.id).gte('created_at', yesterdayStart.toISOString()).lte('created_at', yesterdayEnd.toISOString())
      ]);
      return { views: viewC || 0, calls: callC || 0, wa: waC || 0, reviews: revC || 0 };
    } catch(_){
      return null;
    }
  }

  function renderYesterdayDigest(d){
    const host = document.getElementById('ownerYesterdayDigest');
    if (!host) return;
    if (!d){ host.style.display = 'none'; return; }
    const total = d.views + d.calls + d.wa + d.reviews;
    let highlight = '';
    if (total === 0){
      highlight = '💡 No activity yesterday. Share a poster today to bring customers back.';
    } else if (d.calls + d.wa > 0){
      highlight = '🎉 ' + (d.calls + d.wa) + ' customer' + (d.calls + d.wa === 1 ? '' : 's') + ' contacted you yesterday.';
    } else {
      highlight = '👀 ' + d.views + ' view' + (d.views === 1 ? '' : 's') + ' yesterday. Engage them with a fresh poster.';
    }
    host.innerHTML =
      '<div style="background:#fff;border:1px solid #E2E8F0;border-radius:14px;padding:14px 18px;box-shadow:0 1px 3px rgba(15,23,42,.04);margin-bottom:16px">'
      + '<div style="font-size:.7rem;font-weight:800;color:#94A3B8;letter-spacing:.08em;text-transform:uppercase;margin-bottom:10px">📊 Yesterday\'s digest</div>'
      + '<div style="display:grid;grid-template-columns:repeat(4, minmax(0, 1fr));gap:10px;margin-bottom:10px">'
      +   metric('👁️', d.views, 'Views', '#3B82F6')
      +   metric('📞', d.calls, 'Calls', '#10B981')
      +   metric('💬', d.wa,    'WhatsApp', '#22C55E')
      +   metric('⭐', d.reviews, 'Reviews', '#F59E0B')
      + '</div>'
      + '<div style="font-size:.82rem;color:#475569;font-weight:600;padding-top:8px;border-top:1px dashed #E2E8F0">' + escapeHtml(highlight) + '</div>'
      + '</div>';
    host.style.display = '';
  }
  function metric(emoji, value, label, color){
    return '<div style="text-align:center;background:#F8FAFC;border-radius:10px;padding:10px 6px">'
      + '<div style="font-size:1.4rem;line-height:1">' + emoji + '</div>'
      + '<div style="font-size:1.4rem;font-weight:900;color:' + color + ';letter-spacing:-.02em;line-height:1;margin-top:4px;font-family:Manrope,Inter,sans-serif">' + (value || 0) + '</div>'
      + '<div style="font-size:.66rem;color:#64748B;font-weight:700;margin-top:2px;letter-spacing:.04em;text-transform:uppercase">' + label + '</div>'
      + '</div>';
  }

  // ---------- Today's Quick Win (rotating, gap-aware) ----------
  const QUICK_WINS = [
    { id:'add-photo',       icon:'📷', title:'Add 1 photo today', payoff:'Listings with 3+ photos get 5× more views.', href:'/panel/photos.html', test: b => (Array.isArray(b.photos) ? b.photos.length : 0) < 3 },
    { id:'set-hours',       icon:'🕐', title:'Set your business hours', payoff:'Required to appear in the "Open Now" filter.', href:'/panel/profile.html#hours', test: b => !(b.hours_json && Object.keys(b.hours_json || {}).length) },
    { id:'write-usp',       icon:'✨', title:'Write your USP / tagline', payoff:'A sharp tagline is the #1 driver of first-impression clicks.', href:'/panel/profile.html#usp', test: b => !(b.usp_text && b.usp_text.trim().length > 10) },
    { id:'about-section',   icon:'📝', title:'Add an About section', payoff:'Customers compare 3 shops before calling — strong About wins.', href:'/panel/profile.html#about', test: b => !(b.about_text && b.about_text.trim().length > 50) },
    { id:'share-poster',    icon:'⚡', title:'Share a poster on WhatsApp Status', payoff:'30 sec of effort = visibility to 50-200 contacts.', href:'/panel/poster-quick.html', test: () => true },
    { id:'reply-reviews',   icon:'💬', title:'Reply to a customer review', payoff:'Replying lifts your trust score and shows you care.', href:'/panel/reviews.html', test: b => (b.rating_count || 0) > 0 },
    { id:'get-reviews',     icon:'⭐', title:'Ask 3 customers for a review', payoff:'New reviews this month = better ranking.', href:'/panel/get-reviews.html', test: () => true },
    { id:'add-social',      icon:'📱', title:'Link 1 social media account', payoff:'Cross-platform presence = customer trust.', href:'/panel/profile.html#social', test: b => !(b.facebook_url || b.instagram_url || b.youtube_url || b.x_twitter_url || b.linkedin_url || b.website_url) },
    { id:'add-year',        icon:'📅', title:'Add your established year', payoff:'"Since 2010" badge boosts credibility instantly.', href:'/panel/profile.html#trust', test: b => !(b.established_year && b.established_year > 1900) },
    { id:'add-features',    icon:'🎯', title:'Mark your special features', payoff:'Customers filter by features — be discoverable.', href:'/panel/profile.html#trust', test: b => !(Array.isArray(b.special_features) && b.special_features.length) }
  ];

  function pickTodaysQuickWin(biz){
    let seen = {};
    try { seen = JSON.parse(localStorage.getItem('dl_owner_qw_seen') || '{}'); } catch(_){}
    // Filter applicable ones (where test returns true — i.e., shop needs this)
    const applicable = QUICK_WINS.filter(qw => { try { return qw.test(biz || {}); } catch(_){ return false; } });
    if (!applicable.length) return null;
    // Prefer least-recently-shown
    applicable.sort((a, b) => (seen[a.id] || 0) - (seen[b.id] || 0));
    // Pick deterministically — same day = same suggestion
    const dayHash = Math.abs(hashStr(ymd())) % applicable.length;
    return applicable[(0 + dayHash) % applicable.length] || applicable[0];
  }

  function renderQuickWin(biz){
    const host = document.getElementById('ownerQuickWin');
    if (!host) return;
    const qw = pickTodaysQuickWin(biz);
    if (!qw){ host.style.display = 'none'; return; }
    // Mark as seen
    try {
      const seen = JSON.parse(localStorage.getItem('dl_owner_qw_seen') || '{}');
      seen[qw.id] = Date.now();
      localStorage.setItem('dl_owner_qw_seen', JSON.stringify(seen));
    } catch(_){}
    host.innerHTML =
      '<a href="' + qw.href + '" style="display:flex;align-items:center;gap:14px;background:linear-gradient(135deg,#FFF7ED 0%,#FED7AA 100%);border:1px solid #FB923C;border-radius:14px;padding:14px 18px;text-decoration:none;color:#0F172A;box-shadow:0 6px 18px rgba(251,146,60,.15);margin-bottom:16px;transition:transform .15s,box-shadow .15s" onmouseover="this.style.transform=\'translateY(-2px)\';this.style.boxShadow=\'0 10px 26px rgba(251,146,60,.25)\'" onmouseout="this.style.transform=\'\';this.style.boxShadow=\'0 6px 18px rgba(251,146,60,.15)\'">'
      + '<div style="font-size:2rem;flex-shrink:0;width:54px;height:54px;background:#fff;border-radius:13px;display:grid;place-items:center;box-shadow:0 3px 10px rgba(251,146,60,.2)">' + qw.icon + '</div>'
      + '<div style="flex:1;min-width:0">'
      +   '<div style="font-size:.66rem;font-weight:800;color:#9A3412;letter-spacing:.08em;text-transform:uppercase;margin-bottom:4px">💡 Today\'s quick win</div>'
      +   '<div style="font-weight:900;font-size:1rem;color:#0F172A;letter-spacing:-.01em">' + escapeHtml(qw.title) + '</div>'
      +   '<div style="font-size:.78rem;color:#9A3412;font-weight:600;margin-top:2px">' + escapeHtml(qw.payoff) + '</div>'
      + '</div>'
      + '<div style="color:#FF6B1A;font-size:1.3rem;font-weight:900;flex-shrink:0">→</div>'
      + '</a>';
    host.style.display = '';
  }

  // ---------- Morning digest opt-in (preference only — actual send is backend) ----------
  function renderDigestOptIn(){
    const host = document.getElementById('ownerDigestOptin');
    if (!host) return;
    const optedIn = localStorage.getItem('dl_owner_digest_optin') === '1';
    host.innerHTML =
      '<label style="display:flex;align-items:center;gap:12px;background:#F0F9FF;border:1px solid #BAE6FD;border-radius:12px;padding:12px 16px;cursor:pointer;margin-bottom:16px">'
      + '<input type="checkbox" id="ownerDigestChk" ' + (optedIn ? 'checked' : '') + ' style="width:18px;height:18px;accent-color:#3B82F6;cursor:pointer;flex-shrink:0">'
      + '<div style="flex:1;min-width:0">'
      +   '<div style="font-weight:800;font-size:.92rem;color:#0F172A;letter-spacing:-.01em">📨 Get my Morning Digest on WhatsApp</div>'
      +   '<div style="font-size:.74rem;color:#0369A1;font-weight:600;margin-top:1px">Daily 9 AM IST — yesterday\'s leads + today\'s suggestion. Coming soon.</div>'
      + '</div>'
      + '</label>';
    const chk = document.getElementById('ownerDigestChk');
    if (chk){
      chk.addEventListener('change', function(){
        try { localStorage.setItem('dl_owner_digest_optin', chk.checked ? '1' : '0'); } catch(_){}
        if (chk.checked && global.DukanOwnerEng && global.DukanOwnerEng.toast){
          global.DukanOwnerEng.toast('✓ Saved — we will roll out daily WhatsApp digest soon.');
        }
      });
    }
    host.style.display = '';
  }

  // ---------- Helpers ----------
  function escapeHtml(s){ return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function hashStr(s){
    let h = 0;
    for (let i = 0; i < s.length; i++) h = ((h << 5) - h) + s.charCodeAt(i) | 0;
    return h;
  }
  function toast(text){
    const t = document.createElement('div');
    t.textContent = text;
    t.style.cssText = 'position:fixed;bottom:24px;left:50%;transform:translateX(-50%);background:#0F172A;color:#fff;padding:11px 22px;border-radius:99px;font-size:.86rem;font-weight:700;z-index:99999;box-shadow:0 10px 30px rgba(15,23,42,.4)';
    document.body.appendChild(t);
    setTimeout(() => { try { t.remove(); } catch(_){} }, 2500);
  }

  // ---------- Public API ----------
  async function init(biz){
    try { renderStreakBanner(); } catch(e){ console.warn('streak:', e); }
    try { renderQuickWin(biz); } catch(e){ console.warn('quickwin:', e); }
    try { renderDigestOptIn(); } catch(e){ console.warn('digest optin:', e); }
    try {
      const d = await loadYesterdayDigest(biz);
      renderYesterdayDigest(d);
    } catch(e){ console.warn('yesterday digest:', e); }
  }

  global.DukanOwnerEng = {
    init: init,
    bumpStreak: bumpStreak,
    toast: toast
  };
})(window);
