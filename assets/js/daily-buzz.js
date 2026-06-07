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

// ─── Shop strip on business.html (story ring) ──────────────
async function renderShopStrip(targetId, supaClient, businessId){
  const el = document.getElementById(targetId);
  if (!el || !supaClient || !businessId) return;
  try {
    const { data } = await supaClient.rpc('get_shop_active_stories', { p_business_id: businessId });
    const items = Array.isArray(data) ? data : [];
    if (items.length === 0) { el.style.display = 'none'; return; }

    el.innerHTML =
      '<div class="db-strip">' +
      '  <div class="db-strip-label">⚡ Latest from this shop</div>' +
      '  <div class="db-strip-items">' +
      items.map((s, i) =>
        '<button class="db-strip-item" data-idx="' + i + '" style="background:' + gradientCss(s.bg_style) + '">' +
        '  <div class="db-strip-text">' + esc(s.text.slice(0, 60) + (s.text.length > 60 ? '…' : '')) + '</div>' +
        '  <div class="db-strip-age">' + timeAgo(s.created_at) + '</div>' +
        '</button>'
      ).join('') +
      '  </div>' +
      '</div>';
    el.style.display = 'block';

    el.querySelectorAll('.db-strip-item').forEach(btn => {
      btn.addEventListener('click', () => {
        openViewer(items, parseInt(btn.dataset.idx, 10) || 0, supaClient);
      });
    });
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
      items.map((s, i) =>
        '<button class="db-home-card" data-idx="' + i + '" style="background:' + gradientCss(s.bg_style) + '">' +
        '  <div class="db-home-shop">' + esc(s.shop_name || '') + '</div>' +
        '  <div class="db-home-text">' + esc(s.text.slice(0, 90) + (s.text.length > 90 ? '…' : '')) + '</div>' +
        '  <div class="db-home-age">' + timeAgo(s.created_at) + '</div>' +
        '</button>'
      ).join('') +
      '  </div>' +
      '</div>';
    el.style.display = 'block';

    el.querySelectorAll('.db-home-card').forEach(btn => {
      btn.addEventListener('click', () => {
        openViewer(items, parseInt(btn.dataset.idx, 10) || 0, supaClient);
      });
    });
  } catch(_){}
}

// ─── Fullscreen viewer (Instagram-style) ───────────────────
function openViewer(items, startIdx, supaClient){
  let idx = startIdx || 0;
  let timer;

  // Build viewer DOM
  const v = document.createElement('div');
  v.className = 'db-viewer';
  v.innerHTML =
    '<button class="db-v-close">✕</button>' +
    '<div class="db-v-progress" id="dbVProgress"></div>' +
    '<div class="db-v-content" id="dbVContent"></div>' +
    '<div class="db-v-tap-left" id="dbVTapLeft"></div>' +
    '<div class="db-v-tap-right" id="dbVTapRight"></div>';
  document.body.appendChild(v);
  document.body.style.overflow = 'hidden';

  function close(){
    clearInterval(timer);
    document.body.style.overflow = '';
    v.remove();
  }

  function show(i){
    if (i < 0 || i >= items.length) return close();
    idx = i;
    const s = items[i];

    // Bump view count
    if (supaClient) {
      try { supaClient.rpc('story_inc_view', { p_story_id: s.id }); } catch(_){}
    }

    // Progress bars
    const progressEl = v.querySelector('#dbVProgress');
    progressEl.innerHTML = items.map((_, i2) =>
      '<div class="db-v-bar"><div class="db-v-bar-fill" style="' +
      (i2 < idx ? 'width:100%' : i2 === idx ? '' : 'width:0%') +
      '"></div></div>'
    ).join('');

    // Content
    const contentEl = v.querySelector('#dbVContent');
    contentEl.style.background = gradientCss(s.bg_style);
    contentEl.innerHTML =
      '<div class="db-v-head">' +
      '  <div class="db-v-shop">' +
      (s.shop_name ? '<div class="db-v-shop-name">' + esc(s.shop_name) + '</div>' : '') +
      '    <div class="db-v-age">' + timeAgo(s.created_at) + ' ago</div>' +
      '  </div>' +
      '</div>' +
      '<div class="db-v-text">' + esc(s.text) + '</div>' +
      (s.shop_slug ? '<a class="db-v-cta" href="/business.html?slug=' + encodeURIComponent(s.shop_slug) + '">Open shop →</a>' : '');

    // Animate progress bar
    const activeBar = progressEl.querySelectorAll('.db-v-bar-fill')[idx];
    if (activeBar) {
      activeBar.style.transition = 'width 5s linear';
      requestAnimationFrame(() => { activeBar.style.width = '100%'; });
    }

    // Auto-advance after 5s
    clearInterval(timer);
    timer = setTimeout(() => show(idx + 1), 5000);
  }

  v.querySelector('.db-v-close').addEventListener('click', close);
  v.querySelector('#dbVTapLeft').addEventListener('click', () => show(idx - 1));
  v.querySelector('#dbVTapRight').addEventListener('click', () => show(idx + 1));

  function keyHandler(e){
    if (e.key === 'Escape') close();
    if (e.key === 'ArrowRight') show(idx + 1);
    if (e.key === 'ArrowLeft') show(idx - 1);
  }
  document.addEventListener('keydown', keyHandler);
  v.addEventListener('remove', () => document.removeEventListener('keydown', keyHandler));

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

})(window)