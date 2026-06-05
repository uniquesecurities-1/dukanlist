/* ============================================================
   engagement-engine.js
   ============================================================
   STRATEGIC PHASE 2 (2026-06-05):
   Daily-engagement engine for shopkeeper dashboard.

   Modules:
     1. Achievement Badges  — milestone-based recognition
     2. Login Streak Tracker — consecutive day counter
     3. Town Rank Renderer   — visualize get_town_rank() RPC
     4. Smart Tips Renderer  — visualize get_smart_tips() RPC

   All copy is PROFESSIONAL ENGLISH. No Hinglish.
   Zero external API calls. Zero cost.
   ============================================================ */
(function(global){
'use strict';

// ─── 1. ACHIEVEMENT BADGES ──────────────────────────────────
//
// Badges are unlocked based on snapshot of the business data.
// Each badge has: id, label, description, icon, tier, unlocked flag.
// No DB write — purely computed from existing business fields.

const BADGE_DEFINITIONS = [
  // Profile completion ladder
  { id: 'first-listing',     label: 'Listed',              tier: 'starter',  icon: '🎯',
    check: b => true,
    desc: 'Your business is live on DukanList' },
  { id: 'photo-starter',     label: 'Photo Starter',       tier: 'starter',  icon: '📸',
    check: b => (b.photos?.length || 0) >= 1,
    desc: 'Uploaded your first photo' },
  { id: 'photo-master',      label: 'Photo Master',        tier: 'pro',      icon: '🖼️',
    check: b => (b.photos?.length || 0) >= 5,
    desc: 'Five or more photos uploaded' },
  { id: 'storyteller',       label: 'Storyteller',         tier: 'pro',      icon: '📝',
    check: b => (b.about_text || '').length > 50,
    desc: 'Detailed About section written' },
  { id: 'usp-set',           label: 'USP Defined',         tier: 'starter',  icon: '🎤',
    check: b => (b.usp_text || '').length > 10,
    desc: 'Your unique selling point is set' },
  { id: 'hours-set',         label: 'Open Hours',          tier: 'starter',  icon: '⏰',
    check: b => b.hours_json && Object.keys(b.hours_json).length > 0,
    desc: 'Business hours configured' },
  { id: 'payments-set',      label: 'Payments Ready',      tier: 'starter',  icon: '💳',
    check: b => Array.isArray(b.payment_methods) && b.payment_methods.length >= 2,
    desc: 'Multiple payment methods listed' },
  // Trust and reputation
  { id: 'first-review',      label: 'First Review',        tier: 'pro',      icon: '⭐',
    check: b => (b.rating_count || 0) >= 1,
    desc: 'Received your first customer review' },
  { id: 'five-reviews',      label: 'Five Star Rated',     tier: 'pro',      icon: '🌟',
    check: b => (b.rating_count || 0) >= 5,
    desc: 'Five or more customer reviews' },
  { id: 'top-rated',         label: 'Top Rated',           tier: 'elite',    icon: '🏆',
    check: b => (b.rating_count || 0) >= 10 && (b.rating_avg || 0) >= 4.5,
    desc: 'Ten or more reviews with rating 4.5 or higher' },
  // Verification ladder
  { id: 'verified',          label: 'DukanList Verified',  tier: 'pro',      icon: '✅',
    check: b => (b.verified_score || 0) >= 2,
    desc: 'Manually verified by DukanList team' },
  { id: 'trust-bronze',      label: 'Bronze Trust',        tier: 'pro',      icon: '🥉',
    check: b => (b.verified_score || 0) >= 1,
    desc: 'Bronze trust tier earned' },
  { id: 'trust-silver',      label: 'Silver Trust',        tier: 'elite',    icon: '🥈',
    check: b => (b.verified_score || 0) >= 3,
    desc: 'Silver trust tier earned' },
  { id: 'trust-gold',        label: 'Gold Trust',          tier: 'elite',    icon: '🥇',
    check: b => (b.verified_score || 0) >= 5,
    desc: 'Gold trust tier earned' },
  // Community & content
  { id: 'social-connected',  label: 'Online Presence',     tier: 'pro',      icon: '🌐',
    check: b => !!(b.facebook_url || b.instagram_url || b.website_url),
    desc: 'Social media or website linked' },
  { id: 'faq-pro',           label: 'FAQ Expert',          tier: 'pro',      icon: '💡',
    check: b => Array.isArray(b.faqs_json) && b.faqs_json.length >= 3,
    desc: 'Three or more FAQs added' },
  { id: 'established',       label: 'Established',         tier: 'pro',      icon: '🏛️',
    check: b => b.established_year && (new Date().getFullYear() - b.established_year) >= 5,
    desc: 'Business established 5 or more years ago' },
  { id: 'veteran',           label: 'Veteran Business',    tier: 'elite',    icon: '👑',
    check: b => b.established_year && (new Date().getFullYear() - b.established_year) >= 15,
    desc: 'Established 15 or more years ago' }
];

const TIER_META = {
  starter: { color: '#6B7280', bg: '#F3F4F6', label: 'Starter' },
  pro:     { color: '#1E3A8A', bg: '#DBEAFE', label: 'Pro'     },
  elite:   { color: '#92400E', bg: '#FEF3C7', label: 'Elite'   }
};

function computeBadges(b){
  return BADGE_DEFINITIONS.map(def => {
    let unlocked = false;
    try { unlocked = !!def.check(b); } catch(_){ unlocked = false; }
    return {
      id:       def.id,
      label:    def.label,
      desc:     def.desc,
      icon:     def.icon,
      tier:     def.tier,
      unlocked: unlocked
    };
  });
}

function renderBadgeWall(containerId, businessData){
  const el = document.getElementById(containerId);
  if (!el || !businessData) return;
  const badges = computeBadges(businessData);
  const unlocked = badges.filter(b => b.unlocked);
  const locked   = badges.filter(b => !b.unlocked);

  const html = `
    <div class="badge-wall-card">
      <div class="bw-head">
        <div class="bw-title">
          <span class="bw-emoji">🏆</span>
          <span>Your Achievements</span>
        </div>
        <div class="bw-count">${unlocked.length} of ${badges.length} unlocked</div>
      </div>
      <div class="bw-bar">
        <div class="bw-bar-fill" style="width:${(unlocked.length / badges.length * 100).toFixed(0)}%"></div>
      </div>
      <div class="bw-grid">
        ${badges.map(badgeChip).join('')}
      </div>
      <button class="bw-share-btn" id="bwShareBtn" type="button">
        Share your achievements
      </button>
    </div>
  `;
  el.innerHTML = html;

  const shareBtn = el.querySelector('#bwShareBtn');
  if (shareBtn) {
    shareBtn.addEventListener('click', () => shareAchievements(businessData, unlocked));
  }
}

function badgeChip(b){
  const meta = TIER_META[b.tier] || TIER_META.starter;
  return `
    <div class="bw-chip ${b.unlocked ? 'unlocked' : 'locked'}" title="${escapeHtml(b.desc)}">
      <div class="bw-chip-icon" style="${b.unlocked ? `background:${meta.bg};color:${meta.color}` : ''}">
        ${b.unlocked ? b.icon : '🔒'}
      </div>
      <div class="bw-chip-label">${escapeHtml(b.label)}</div>
    </div>
  `;
}

async function shareAchievements(b, unlocked){
  const lines = [
    `🏆 ${b.name || 'My Business'} on DukanList`,
    '',
    'Achievements unlocked:',
    ...unlocked.slice(0, 8).map(u => `${u.icon} ${u.label}`),
    '',
    `View profile: https://dukanlist.com/business.html?slug=${b.slug || ''}`,
    '',
    '— DukanList'
  ].join('\n');

  if (navigator.share) {
    try { await navigator.share({ text: lines, title: 'My achievements' }); return; }
    catch(_) { /* fall through */ }
  }
  window.open('https://wa.me/?text=' + encodeURIComponent(lines), '_blank');
}

// ─── 2. LOGIN STREAK TRACKER ────────────────────────────────
//
// localStorage-based. Counts consecutive days the owner opened
// the dashboard. Resets if more than one day skipped.

function recordLoginStreak(){
  const KEY = 'dl_login_streak';
  const todayStr = new Date().toISOString().slice(0, 10);
  let state;
  try {
    state = JSON.parse(localStorage.getItem(KEY) || '{}');
  } catch(_) { state = {}; }

  const lastDate = state.last_date;
  const currentStreak = parseInt(state.current_streak, 10) || 0;
  const bestStreak    = parseInt(state.best_streak, 10)    || 0;

  let newStreak;
  if (!lastDate) {
    newStreak = 1;
  } else if (lastDate === todayStr) {
    newStreak = currentStreak; // already counted today
  } else {
    const last = new Date(lastDate + 'T00:00:00');
    const tdy  = new Date(todayStr + 'T00:00:00');
    const diffDays = Math.round((tdy - last) / (1000 * 60 * 60 * 24));
    if (diffDays === 1) {
      newStreak = currentStreak + 1;
    } else {
      newStreak = 1; // streak broken
    }
  }

  const newBest = Math.max(bestStreak, newStreak);
  localStorage.setItem(KEY, JSON.stringify({
    last_date:       todayStr,
    current_streak:  newStreak,
    best_streak:     newBest
  }));

  return { current: newStreak, best: newBest };
}

function renderStreakBadge(targetId){
  const el = document.getElementById(targetId);
  if (!el) return;
  const s = recordLoginStreak();
  let label = '';
  if (s.current >= 7) label = ' 🔥 ON FIRE';
  else if (s.current >= 3) label = ' 🔥';
  el.innerHTML = `
    <div class="streak-pill" title="Best streak: ${s.best} days">
      <span class="streak-emoji">📅</span>
      <span class="streak-num">${s.current}</span>
      <span class="streak-lbl">day streak${label}</span>
    </div>
  `;
}

// ─── 3. TOWN RANK RENDERER ──────────────────────────────────

async function renderTownRank(containerId, supaClient, businessId){
  const el = document.getElementById(containerId);
  if (!el || !supaClient || !businessId) return;

  try {
    const { data, error } = await supaClient.rpc('get_town_rank', { p_business_id: businessId });
    if (error || !data) {
      console.warn('town-rank rpc:', error);
      return;
    }

    if (!data.available) {
      el.innerHTML = `
        <div class="tr-card empty">
          <div class="tr-empty-icon">📍</div>
          <div class="tr-empty-msg">${escapeHtml(data.reason || 'Complete your profile to see your local rank')}</div>
        </div>
      `;
      el.style.display = 'block';
      return;
    }

    const isLeader = data.is_leader;
    const isTop3   = data.is_top3;
    const rank     = data.rank || 0;
    const total    = data.total || 0;
    const cityName = data.city_name || 'Your city';
    const catName  = data.category_name || 'Your category';

    const headlineEmoji = isLeader ? '👑' : isTop3 ? '🥇' : '📊';
    const headlineText  = isLeader ? 'You are #1 in your segment'
                         : isTop3 ? 'You are in the Top 3'
                         : 'Your local position';

    const subText = isTop3
      ? `${cityName} · ${catName}`
      : `${data.gap_to_top3 || 0} points needed to enter Top 3`;

    const leaderRow = (!isLeader && data.leader_name)
      ? `<div class="tr-leader">
           <span class="tr-leader-label">Current leader</span>
           <span class="tr-leader-name">${escapeHtml(data.leader_name)}</span>
         </div>`
      : '';

    el.innerHTML = `
      <div class="tr-card ${isLeader ? 'leader' : isTop3 ? 'top3' : ''}">
        <div class="tr-head">
          <span class="tr-emoji">${headlineEmoji}</span>
          <span class="tr-title">${escapeHtml(headlineText)}</span>
        </div>
        <div class="tr-rank-row">
          <div class="tr-rank-big">#${rank}</div>
          <div class="tr-rank-of">of ${total}</div>
          <div class="tr-segment">${escapeHtml(cityName)} · ${escapeHtml(catName)}</div>
        </div>
        <div class="tr-sub">${escapeHtml(subText)}</div>
        ${leaderRow}
      </div>
    `;
    el.style.display = 'block';
  } catch(e) {
    console.warn('town-rank fail:', e);
  }
}

// ─── 4. SMART TIPS RENDERER ─────────────────────────────────

async function renderSmartTips(containerId, supaClient, businessId){
  const el = document.getElementById(containerId);
  if (!el || !supaClient || !businessId) return;

  try {
    const { data, error } = await supaClient.rpc('get_smart_tips', { p_business_id: businessId });
    if (error || !data || !data.tips) {
      console.warn('smart-tips rpc:', error);
      return;
    }

    const tips = Array.isArray(data.tips) ? data.tips.slice(0, 3) : [];
    if (tips.length === 0) {
      el.innerHTML = `
        <div class="st-card empty">
          <div class="st-empty-icon">✨</div>
          <div class="st-empty-msg">You are doing great. No critical actions needed right now.</div>
        </div>
      `;
      el.style.display = 'block';
      return;
    }

    el.innerHTML = `
      <div class="st-card">
        <div class="st-head">
          <span class="st-emoji">💡</span>
          <span class="st-title">Personalised Recommendations</span>
          <span class="st-count">${tips.length}</span>
        </div>
        <div class="st-list">
          ${tips.map(tipRow).join('')}
        </div>
      </div>
    `;
    el.style.display = 'block';
  } catch(e) {
    console.warn('smart-tips fail:', e);
  }
}

function tipRow(t){
  const prio = (t.priority || 'medium').toLowerCase();
  return `
    <a href="${escapeAttr(t.href || '#')}" class="st-row prio-${prio}">
      <div class="st-row-icon">${t.icon || '•'}</div>
      <div class="st-row-body">
        <div class="st-row-title">${escapeHtml(t.title || '')}</div>
        <div class="st-row-detail">${escapeHtml(t.detail || '')}</div>
      </div>
      <div class="st-row-cta">${escapeHtml(t.cta || 'Open')} →</div>
    </a>
  `;
}

// ─── Helpers ────────────────────────────────────────────────
function escapeHtml(s){
  return String(s == null ? '' : s)
    .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
    .replace(/"/g,'&quot;').replace(/'/g,'&#39;');
}
function escapeAttr(s){ return escapeHtml(s); }

// ─── Public API ─────────────────────────────────────────────
global.EngagementEngine = {
  computeBadges,
  renderBadgeWall,
  recordLoginStreak,
  renderStreakBadge,
  renderTownRank,
  renderSmartTips,
  BADGE_DEFINITIONS,
  TIER_META
};

})(window);
