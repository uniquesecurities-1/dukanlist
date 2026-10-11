/* ============================================================
   daily-buzz.js — Shop Stories engine UI
   ============================================================
   STRATEGIC PHASE 9 (2026-06-05):
   Daily Buzz — Instagram-style 24h ephemeral stories.

   Public API:
     DailyBuzz.renderOwnerWidget(targetId, supaClient, biz)
       — dashboard widget for shopkeeper to post stories

     DailyBuzz.renderShopStrip(targetId, supaClient, businessId)
       — story ring/strip on business.html

     DailyBuzz.renderHomepageCarousel(targetId, supaClient, citySlug)
       — homepage horizontal scroller

     DailyBuzz.openViewer(stories, startIdx)
       — fullscreen story viewer (Instagram-style)
   ============================================================ */
(function(global){
'use strict';

// 6 preset gradient backgrounds for stories
const GRADIENTS = {
  'gradient-1': ['#FF6B1A', '#EA580C', '#9A3412'],
  'gradient-2': ['#1E3A8A', '#3730A3', '#5B21B6'],
  'gradient-3': ['#064E3B', '#047857', '#10B981'],
  'gradient-4': ['#7C3AED', '#A855F7', '#EC4899'],
  'gradient-5': ['#451A03', '#92400E', '#FBBF24'],
  'gradient-6': ['#0F172A', '#1E293B', '#312E81']
};

function esc(s){
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function gradientCss(key){
  const stops = GRADIENTS[key] || GRADIENTS['gradient-1'];
  return 'linear-gradient(135deg,' + stops.join(',') + ')';
}

function timeAgo(iso){
  const d = new Date(iso);
  const mins = Math.floor((Date.now() - d) / 60000);
  if (mins < 60) return mins + 'm';
  const hrs = Math.floor(mins / 60);
  return hrs + 'h';
}

// ─── Owner widget (post a story) ────────────────────────────
function renderOwnerWidget(targetId, supaClient, biz){
  const el = document.getElementById(targetId);
  if (!el || !supaClient || !biz || !biz.id) return;

  let activeBg = 'gradient-1';

  el.innerHTML =
    '<div class="db-card">' +
    '  <div class="db-head">' +
    '    <span class="db-icon">⚡</span>' +
    '    <span class="db-title">Post a Daily Buzz</span>' +
    '    <span class="db-sub">Expires in 24h · Max 3 active</span>' +
    '  </div>' +
    '  <textarea class="db-input" id="dbText" maxlength="280" placeholder="Share an update: fresh stock, today\'s offer, closed for lunch, etc..."></textarea>' +
    '  <div class="db-meta">' +
    '    <span class="db-count" id="dbCount">0 / 280</span>' +
    '    <span class="db-bg-picker" id="dbBgPicker">' +
    Object.keys(GRADIENTS).map((g, i) =>
      '<span class="db-bg-dot ' + (i === 0 ? 'active' : '') + '" data-bg="' + g + '" style="background:' + gradientCss(g) + '"></span>'
    ).join('') +
    '    </span>' +
    '    <button class="db-post-btn" id="dbPostBtn" type="button">Post Buzz</button>' +
    '  </div>' +
    '  <div class="db-preview-row" id="dbActiveList"></div>' +
    '</div>';

  const textEl   = document.getElementById('dbText');
  const countEl  = document.getElementById('dbCount');
  const postBtn  = document.getElementById('dbPostBtn');
  const bgPicker = document.getElementById('dbBgPicker');
  const listEl   = document.getElementById('dbActiveList');

  textEl.addEventListener('input', () => {
    countEl.textContent = textEl.value.length + ' / 280';
  });

  bgPicker.querySelectorAll('.db-bg-dot').forEach(d => {
    d.addEventListener('click', () => {
      bgPicker.querySelectorAll('.db-bg-dot').forEach(x => x.classList.remove('active'));
      d.classList.add('active');
      activeBg = d.dataset.bg;
    });
  });

  postBtn.addEventListener('click', async () => {
    const text = textEl.value.trim();
    if (!text) { textEl.focus(); return; }
    postBtn.disabled = true;
    postBtn.textContent = 'Posting…';
    try {
      const { data, error } = await supaClient.rpc('create_shop_story', {
        p_text: text,
        p_image_url: null,
        p_bg_style: activeBg,
        p_accent_color: null
      });
      if (error) throw error;
      textEl.value = '';
      countEl.textContent = '0 / 280';
      postBtn.textContent = '✓ Posted!';
      setTimeout(() => { postBtn.textContent = 'Post Buzz'; postBtn.disabled = false; }, 1500);
      await loadActive();
    } catch(e) {
      postBtn.textContent = 'Post Buzz';
      postBtn.disabled = false;
      alert('Could not post: ' + (e.message || 'Try again'));
    }
  });

  async function loadActive(){
    try {
      const { data } = await supaClient.rpc('get_shop_active_stories', { p_business_id: biz.id });
      const items = Array.isArray(data) ? data : [];
      if (items.length === 0) {
        listEl.innerHTML = '<div class="db-empty">No active stories yet. Post your first buzz above!</div>';
        return;
      }
      listEl.innerHTML = items.map(s => {
        const hrsLeft = Math.max(1, Math.round(s.hours_left || 0));
        return '<div class="db-active-story" style="background:' + gradientCss(s.bg_style) + '">' +
               '  <div class="db-active-text">' + esc(s.text) + '</div>' +
               '  <div class="db-active-meta">' +
               '    <span>⏳ ' + hrsLeft + 'h left · ' + (s.view_count || 0) + ' views</span>' +
               '    <button class="db-del-btn" data-sid="' + s.id + '">✕</button>' +
               '  </div>' +
               '</div>';
      }).join('');
      listEl.querySelectorAll('.db-del-btn').forEach(b => {
        b.addEventListener('click', async () => {
          if (!confirm('Delete this story?')) return;
          try {
            await supaClient.rpc('delete_my_story', { p_story_id: b.dataset.sid });
            loadActive();
          } catch(_){}
        });
      });
    } catch(_){}
  }
  loadActive();
}

// ─── Shop strip on business.html ──────────────────────────
// v354: was a row of orange blocks parked ABOVE the site header. Now a
// "Taaza update" card that sits right under the shop header, each update
// a white card with the shop's colour ring, "NEW" when under 6 hours, and
// a pill in the header ("⚡ 3 nayi updates") that opens the viewer.
const STYLE_ID = 'dbx-style';
function injectStyle(){
  if (document.getElementById(STYLE_ID)) return;
  const st = document.createElement('style'); st.id = STYLE_ID;
  st.textContent =
  '.dbx-strip{background:#fff;border:1px solid #E5E7EB;border-radius:16px;padding:14px 14px 12px;margin:0 0 16px}' +
  '.dbx-strip-h{display:flex;align-items:center;gap:8px;margin-bottom:10px;font-size:.8rem;font-weight:800;color:#0F172A}' +
  '.dbx-strip-h .dot{width:8px;height:8px;border-radius:50%;background:#16A34A;box-shadow:0 0 0 4px rgba(22,163,74,.15);animation:dbxPulse 1.8s ease-in-out infinite}' +
  '.dbx-strip-h .sub{font-weight:600;color:#64748B;font-size:.74rem}' +
  '@keyframes dbxPulse{50%{box-shadow:0 0 0 7px rgba(22,163,74,0)}}' +
  '.dbx-items{display:flex;gap:10px;overflow-x:auto;scrollbar-width:none;padding:2px}' +
  '.dbx-items::-webkit-scrollbar{display:none}' +
  '.dbx-item{flex:0 0 210px;display:flex;gap:10px;align-items:flex-start;text-align:left;background:#fff;border:1px solid #E2E8F0;border-radius:14px;padding:10px 12px;cursor:pointer;font-family:inherit;transition:transform .15s,box-shadow .15s}' +
  '.dbx-item:hover{transform:translateY(-2px);box-shadow:0 8px 20px rgba(15,23,42,.08)}' +
  '.dbx-ring{flex:0 0 38px;height:38px;border-radius:50%;padding:2px;background:var(--ring)}' +
  '.dbx-ring span{display:flex;width:100%;height:100%;border-radius:50%;background:#fff;align-items:center;justify-content:center;font-size:1rem}' +
  '.dbx-ring img{width:100%;height:100%;border-radius:50%;object-fit:cover;border:2px solid #fff;display:block}' +
  '.dbx-txt{font-size:.86rem;font-weight:700;color:#0F172A;line-height:1.35;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}' +
  '.dbx-age{font-size:.7rem;color:#64748B;font-weight:700;margin-top:3px}' +
  '.dbx-new{display:inline-block;background:#DC2626;color:#fff;font-size:.6rem;font-weight:900;letter-spacing:.06em;border-radius:4px;padding:1px 5px;margin-right:5px;vertical-align:1px}' +
  '.dbx-pill{display:inline-flex;align-items:center;gap:6px;background:#FFF7ED;border:1px solid #FED7AA;color:#9A3412;border-radius:99px;padding:4px 11px;font-size:.78rem;font-weight:800;cursor:pointer;font-family:inherit}' +
  '.dbx-pill .dot{width:7px;height:7px;border-radius:50%;background:#EA580C;animation:dbxPulse 1.8s ease-in-out infinite;box-shadow:0 0 0 3px rgba(234,88,12,.18)}' +
  /* viewer */
  '.dbx-v{position:fixed;inset:0;z-index:100000;background:rgba(2,6,23,.92);display:flex;align-items:center;justify-content:center;padding:14px;-webkit-tap-highlight-color:transparent}' +
  '.dbx-card{position:relative;width:min(420px,100%);height:min(86vh,760px);border-radius:22px;overflow:hidden;color:#fff;display:flex;flex-direction:column;box-shadow:0 30px 80px rgba(0,0,0,.5)}' +
  '.dbx-card::before{content:"";position:absolute;inset:0;background:radial-gradient(120% 80% at 15% 0%,rgba(255,255,255,.22),transparent 55%),radial-gradient(90% 70% at 100% 100%,rgba(0,0,0,.28),transparent 60%);pointer-events:none}' +
  '.dbx-bars{position:relative;z-index:3;display:flex;gap:4px;padding:12px 14px 0}' +
  '.dbx-bar{flex:1;height:3px;border-radius:99px;background:rgba(255,255,255,.3);overflow:hidden}' +
  '.dbx-bar i{display:block;height:100%;width:0;background:#fff;border-radius:99px}' +
  '.dbx-head{position:relative;z-index:3;display:flex;align-items:center;gap:10px;padding:12px 14px}' +
  '.dbx-ava{width:38px;height:38px;border-radius:50%;border:2px solid rgba(255,255,255,.9);overflow:hidden;background:rgba(255,255,255,.2);display:flex;align-items:center;justify-content:center;font-weight:900}' +
  '.dbx-ava img{width:100%;height:100%;object-fit:cover}' +
  '.dbx-who{flex:1;min-width:0}' +
  '.dbx-who b{display:block;font-size:.92rem;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}' +
  '.dbx-who span{font-size:.74rem;opacity:.85;font-weight:700}' +
  '.dbx-x{width:36px;height:36px;border-radius:50%;border:0;background:rgba(255,255,255,.18);color:#fff;font-size:1.1rem;cursor:pointer}' +
  '.dbx-body{position:relative;z-index:2;flex:1;display:flex;flex-direction:column;justify-content:center;padding:10px 28px 24px}' +
  '.dbx-q{font-family:Georgia,serif;font-size:4.5rem;line-height:.6;opacity:.35;height:34px}' +
  '.dbx-t{font-weight:800;letter-spacing:-.015em;line-height:1.28;word-break:break-word;text-shadow:0 2px 12px rgba(0,0,0,.18)}' +
  '.dbx-foot{position:relative;z-index:3;display:flex;gap:8px;padding:0 14px 16px}' +
  '.dbx-btn{flex:1;display:inline-flex;align-items:center;justify-content:center;gap:6px;padding:12px;border-radius:12px;font-weight:800;font-size:.9rem;text-decoration:none;border:0;cursor:pointer;font-family:inherit}' +
  '.dbx-btn.wa{background:#25D366;color:#fff}' +
  '.dbx-btn.gh{background:rgba(255,255,255,.18);color:#fff}' +
  '.dbx-tap{position:absolute;top:70px;bottom:80px;width:35%;z-index:2}' +
  '.dbx-tap.l{left:0}.dbx-tap.r{right:0}' +
  '.dbx-paused .dbx-bar i{animation-play-state:paused !important}' +
  '@media (prefers-reduced-motion:reduce){.dbx-strip-h .dot,.dbx-pill .dot{animation:none}}';
  document.head.appendChild(st);
}

function agoText(iso){
  const hi = document.documentElement.dataset.lang === 'hi';
  const mins = Math.max(1, Math.floor((Date.now() - new Date(iso)) / 60000));
  if (mins < 60) return hi ? mins + ' मिनट पहले' : mins + 'm ago';
  const h = Math.floor(mins / 60);
  return hi ? h + ' घंटे पहले' : h + 'h ago';
}

async function renderShopStrip(targetId, supaClient, businessId, shop){
  const el = document.getElementById(targetId);
  if (!el || !supaClient || !businessId) return;
  try {
    const { data } = await supaClient.rpc('get_shop_active_stories', { p_business_id: businessId });
    const items = (Array.isArray(data) ? data : []).slice().sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
    if (items.length === 0) { el.style.display = 'none'; return; }
    injectStyle();
    const ctx = shop || global.BIZ || {};
    const hi = document.documentElement.dataset.lang === 'hi';
    const photo = Array.isArray(ctx.photos) && ctx.photos[0]
      ? (global.DukanImg && DukanImg.avatar ? DukanImg.avatar(ctx.photos[0]) : ctx.photos[0]) : '';
    const ring = s => '<span class="dbx-ring" style="--ring:' + gradientCss(s.bg_style) + '">'
      + (photo ? '<img src="' + esc(photo) + '" alt="" loading="lazy">' : '<span>⚡</span>') + '</span>';
    el.innerHTML =
      '<div class="dbx-strip">' +
      '  <div class="dbx-strip-h"><span class="dot"></span>' + (hi ? 'दुकान की ताज़ा अपडेट' : 'Fresh from this shop') +
      '  <span class="sub">· ' + items.length + (hi ? ' अपडेट · 24 घंटे में हट जाएँगी' : (items.length === 1 ? ' update' : ' updates') + ' · gone in 24h') + '</span></div>' +
      '  <div class="dbx-items">' +
      items.map((s, i) => {
        const fresh = (Date.now() - new Date(s.created_at)) < 6 * 3600 * 1000;
        return '<button type="button" class="dbx-item" data-idx="' + i + '">' + ring(s) +
          '<span><span class="dbx-txt">' + esc(s.text) + '</span>' +
          '<span class="dbx-age">' + (fresh ? '<span class="dbx-new">NEW</span>' : '') + agoText(s.created_at) + '</span></span></button>';
      }).join('') +
      '  </div>' +
      '</div>';
    el.style.display = 'block';
    el.querySelectorAll('.dbx-item').forEach(btn => btn.addEventListener('click', () => openViewer(items, parseInt(btn.dataset.idx, 10) || 0, supaClient, ctx)));

    // header pill — the first thing a visitor sees
    const meta = document.getElementById('premHeroMeta');
    if (meta && !document.getElementById('dbxPill')){
      const p = document.createElement('button');
      p.type = 'button'; p.id = 'dbxPill'; p.className = 'dbx-pill';
      p.innerHTML = '<span class="dot"></span>' + (hi ? items.length + ' नई अपडेट' : items.length + (items.length === 1 ? ' new update' : ' new updates'));
      p.addEventListener('click', () => openViewer(items, 0, supaClient, ctx));
      meta.insertBefore(p, meta.firstChild);
    }
  } catch(_){}
}

// ─── Homepage carousel ─────────────────────────────────────
async function renderHomepageCarousel(targetId, supaClient, citySlug){
  const el = document.getElementById(targetId);
  if (!el || !supaClient) return;
  try {
    const { data } = await supaClient.rpc('get_homepage_buzz', {
      p_city_slug: citySlug || null,
      p_limit: 12
    });
    const items = Array.isArray(data) ? data : [];
    if (items.length === 0) { el.style.display = 'none'; return; }

    el.innerHTML =
      '<div class="db-home">' +
      '  <div class="db-home-label">' +
      '    <span class="db-home-emoji">⚡</span>' +
      '    <span>Today&#39;s Buzz</span>' +
      '    <span class="db-home-count">' + items.length + ' active</span>' +
      '  </div>' +
      '  <div class="db-home-scroll">' +
      // v309: WhatsApp-status card — shop photo (or initial) in a gradient
      // ring, name, the update, time. The old full-gradient block with
      // uppercase text read as an ad banner, not as news from a shop.
      items.map((s, i) => {
        const name = String(s.shop_name || '').trim();
        const initial = (name.match(/[A-Za-z\u0900-\u097F]/) || ['•'])[0].toUpperCase();
        const photo = s.shop_photo
          ? (window.DukanImg && (DukanImg.avatar || DukanImg.thumb) ? (DukanImg.avatar || DukanImg.thumb)(s.shop_photo) : s.shop_photo)
          : null;
        const avatar = photo
          ? '<img src="' + esc(photo) + '" alt="" loading="lazy" width="48" height="48">'
          : '<span class="db-home-initial" style="background:' + gradientCss(s.bg_style) + '">' + esc(initial) + '</span>';
        // v311: a tap goes to the shop. The fullscreen viewer (.db-viewer)
        // never had a stylesheet, so a tap built an invisible overlay and
        // looked like nothing happened. The view count still increments.
        const href = s.shop_slug ? '/' + encodeURIComponent(s.shop_slug) : '#';
        return '<a class="db-home-card" data-idx="' + i + '" data-sid="' + esc(String(s.id || '')) + '" href="' + href + '" style="--db-ring:' + gradientCss(s.bg_style) + '">' +
          '  <span class="db-home-ava">' + avatar + '</span>' +
          '  <span class="db-home-body">' +
          '    <span class="db-home-shop">' + esc(name) + '</span>' +
          '    <span class="db-home-text">' + esc(s.text.slice(0, 110) + (s.text.length > 110 ? '…' : '')) + '</span>' +
          '    <span class="db-home-age">' + timeAgo(s.created_at) + ' · <b>' + ('hi' === document.documentElement.dataset.lang ? 'देखें' : 'View') + '</b></span>' +
          '  </span>' +
          '</a>';
      }).join('') +
      '  </div>' +
      '</div>';
    el.style.display = 'block';

    el.querySelectorAll('.db-home-card').forEach(a => {
      a.addEventListener('click', () => {
        try { if (a.dataset.sid) supaClient.rpc('story_inc_view', { p_story_id: a.dataset.sid }).then(null, function(){}); } catch(_){}
      });
    });
  } catch(_){}
}

// ─── Fullscreen viewer ─────────────────────────────────────
// v354: a 9:16 card with the shop's face and name, the update in large
// type sized to its length, and a WhatsApp button that quotes the update —
// a story should end in a conversation, not just close. Hold to pause.
function openViewer(items, startIdx, supaClient, shop){
  injectStyle();
  const ctx = shop || global.BIZ || {};
  const hi = document.documentElement.dataset.lang === 'hi';
  let idx = startIdx || 0, timer = null, started = 0, remain = 0, paused = false;

  const v = document.createElement('div');
  v.className = 'dbx-v';
  v.setAttribute('role', 'dialog'); v.setAttribute('aria-modal', 'true');
  v.innerHTML = '<div class="dbx-card" id="dbxCard"></div>';
  document.body.appendChild(v);
  const prevOverflow = document.body.style.overflow;
  document.body.style.overflow = 'hidden';
  const card = v.querySelector('#dbxCard');

  function close(){
    clearTimeout(timer);
    document.removeEventListener('keydown', keyHandler);
    document.body.style.overflow = prevOverflow;
    v.remove();
  }
  function durationFor(t){ return Math.min(9000, 4000 + String(t || '').length * 45); }
  function sizeFor(t){ const n = String(t || '').length; return n < 30 ? '2.2rem' : n < 70 ? '1.75rem' : n < 140 ? '1.4rem' : '1.15rem'; }

  function show(i){
    if (i < 0) i = 0;
    if (i >= items.length) return close();
    idx = i;
    const s = items[i];
    if (supaClient) { try { supaClient.rpc('story_inc_view', { p_story_id: s.id }).then(null, function(){}); } catch(_){} }
    const name = s.shop_name || ctx.name || '';
    const photoSrc = s.shop_photo || (Array.isArray(ctx.photos) && ctx.photos[0]) || '';
    const ava = photoSrc
      ? '<img src="' + esc(global.DukanImg && DukanImg.avatar ? DukanImg.avatar(photoSrc) : photoSrc) + '" alt="">'
      : esc(((name.match(/[A-Za-zऀ-ॿ]/) || ['•'])[0]).toUpperCase());
    const raw = String(ctx.whatsapp || ctx.mobile || '').replace(/\D/g, '').slice(-10);
    const onThisShop = !!(ctx && ctx.id) && (!s.shop_slug || s.shop_slug === ctx.slug);
    const waMsg = encodeURIComponent('Namaste, DukanList par aapki update dekhi: "' + s.text + '". Iske baare mein bataiye.');
    const foot =
      (onThisShop && raw.length === 10
        ? '<a class="dbx-btn wa" href="https://wa.me/91' + raw + '?text=' + waMsg + '" target="_blank" rel="noopener" data-act="wa">💬 ' + (hi ? 'WhatsApp पर पूछें' : 'Ask on WhatsApp') + '</a>'
        : '') +
      (!onThisShop && s.shop_slug
        ? '<a class="dbx-btn gh" href="/' + encodeURIComponent(s.shop_slug) + '">' + (hi ? 'दुकान देखें →' : 'Open shop →') + '</a>'
        : '');
    card.style.background = gradientCss(s.bg_style);
    card.innerHTML =
      '<div class="dbx-bars">' + items.map((_, k) => '<div class="dbx-bar"><i style="width:' + (k < idx ? '100%' : '0') + '"></i></div>').join('') + '</div>' +
      '<div class="dbx-head"><div class="dbx-ava">' + ava + '</div><div class="dbx-who"><b>' + esc(name) + '</b><span>' + agoText(s.created_at) + '</span></div>' +
      '<button type="button" class="dbx-x" aria-label="Close">✕</button></div>' +
      '<div class="dbx-tap l"></div><div class="dbx-tap r"></div>' +
      '<div class="dbx-body"><div class="dbx-q">“</div><div class="dbx-t" style="font-size:' + sizeFor(s.text) + '">' + esc(s.text) + '</div></div>' +
      (foot ? '<div class="dbx-foot">' + foot + '</div>' : '');
    card.querySelector('.dbx-x').onclick = close;
    card.querySelector('.dbx-tap.l').onclick = () => show(idx - 1);
    card.querySelector('.dbx-tap.r').onclick = () => show(idx + 1);
    const wa = card.querySelector('[data-act="wa"]');
    if (wa) wa.addEventListener('click', () => { try { if (typeof global.logLead === 'function') global.logLead('whatsapp'); } catch(_){} close(); });
    remain = durationFor(s.text); paused = false;
    run();
  }
  function run(){
    const bar = card.querySelectorAll('.dbx-bar i')[idx];
    if (bar){
      const done = 1 - remain / durationFor(items[idx].text);
      bar.style.transition = 'none'; bar.style.width = (done * 100) + '%';
      requestAnimationFrame(() => requestAnimationFrame(() => { bar.style.transition = 'width ' + remain + 'ms linear'; bar.style.width = '100%'; }));
    }
    started = Date.now();
    clearTimeout(timer);
    timer = setTimeout(() => show(idx + 1), remain);
  }
  function pause(){
    if (paused) return; paused = true;
    clearTimeout(timer);
    remain = Math.max(300, remain - (Date.now() - started));
    const bar = card.querySelectorAll('.dbx-bar i')[idx];
    if (bar){ const w = getComputedStyle(bar).width; bar.style.transition = 'none'; bar.style.width = w; }
  }
  function resume(){ if (!paused) return; paused = false; run(); }

  // hold anywhere on the card to pause (like Instagram)
  card.addEventListener('pointerdown', e => { if (!e.target.closest('a,button')) pause(); });
  ['pointerup', 'pointercancel', 'pointerleave'].forEach(t => card.addEventListener(t, resume));
  v.addEventListener('click', e => { if (e.target === v) close(); });
  function keyHandler(e){
    if (e.key === 'Escape') close();
    if (e.key === 'ArrowRight') show(idx + 1);
    if (e.key === 'ArrowLeft') show(idx - 1);
  }
  document.addEventListener('keydown', keyHandler);
  show(idx);
}

// ─── Public API ────────────────────────────────────────────
global.DailyBuzz = {
  renderOwnerWidget,
  renderShopStrip,
  renderHomepageCarousel,
  openViewer,
  GRADIENTS
};

})(window);
