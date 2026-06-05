/* ============================================================
   daily-poster-engine.js
   ============================================================
   STRATEGIC: "Aaj ka Poster" — Daily auto-rotating WhatsApp Status
   creative for shopkeepers. Roz subah ek fresh design tayyaar.

   7-day theme rotation:
     Monday    — "Naya Hafta — Aaj ke Offers"
     Tuesday   — "Aaj ka Tip" (category-based)
     Wednesday — "Customer Voice" (real review highlighted)
     Thursday  — "Verified Trust" (DukanList Verified focus)
     Friday    — "Weekend Specials"
     Saturday  — "Trending in Your City"
     Sunday    — "Family & Trust"

   USAGE:
     const theme = DailyPoster.getTodayTheme();
     const blob  = await DailyPoster.renderToBlob(shopData, theme, 1080);
     DailyPoster.shareToWhatsApp(blob, shopData);
   ============================================================ */
(function(global){
'use strict';

// ─── 7-day Theme Configurations ──────────────────────────────
const THEMES = {
  0: { // Sunday
    id: 'sunday',
    nameEn: 'Family & Trust',
    nameHi: 'Family & Bharosa',
    bgGradient: ['#FEF3C7', '#FDE68A', '#FBBF24'],
    accent: '#92400E',
    ink: '#451A03',
    headline: (s) => `Apke parivaar ka apna shop`,
    subline: (s) => `${yearsLine(s)} se aapki seva mein`,
    emoji: '🏠',
    layout: 'family',
    cta: 'Visit ya Call karein — Hum hain aapke saath'
  },
  1: { // Monday
    id: 'monday',
    nameEn: 'Fresh Week Special',
    nameHi: 'Naya Hafta',
    bgGradient: ['#FF6B1A', '#F97316', '#EA580C'],
    accent: '#FFF',
    ink: '#FFFFFF',
    headline: (s) => `Naya hafta, fresh stock`,
    subline: (s) => `Aaj hi visit karein`,
    emoji: '🔥',
    layout: 'big-name',
    cta: 'Open Now — Aaj khareedari karein'
  },
  2: { // Tuesday
    id: 'tuesday',
    nameEn: 'Pro Tip Tuesday',
    nameHi: 'Aaj ka Tip',
    bgGradient: ['#1E3A8A', '#3730A3', '#5B21B6'],
    accent: '#FBBF24',
    ink: '#FFFFFF',
    headline: (s) => `${getCategoryTip(s)}`,
    subline: (s) => `— ${s.name}`,
    emoji: '💡',
    layout: 'tip-card',
    cta: 'Trusted expert advice'
  },
  3: { // Wednesday
    id: 'wednesday',
    nameEn: 'Customer Voice',
    nameHi: 'Customer ki Awaaz',
    bgGradient: ['#FDFBF7', '#FBEFD9', '#F3E2C0'],
    accent: '#C24A0A',
    ink: '#1F2937',
    headline: (s) => s.reviewText || `Bahut accha service hai!`,
    subline: (s) => s.reviewer || `Khush customer`,
    emoji: '⭐',
    layout: 'review-card',
    cta: 'Aap bhi try karein'
  },
  4: { // Thursday
    id: 'thursday',
    nameEn: 'Trust Verified',
    nameHi: 'DukanList Verified',
    bgGradient: ['#064E3B', '#065F46', '#047857'],
    accent: '#FBBF24',
    ink: '#FFFFFF',
    headline: (s) => `DukanList Verified Shop`,
    subline: (s) => `Personally checked by our team`,
    emoji: '✅',
    layout: 'verified',
    cta: 'Trusted by DukanList'
  },
  5: { // Friday
    id: 'friday',
    nameEn: 'Weekend Special',
    nameHi: 'Weekend Special',
    bgGradient: ['#7C3AED', '#A21CAF', '#DB2777'],
    accent: '#FCD34D',
    ink: '#FFFFFF',
    headline: (s) => `Weekend hai — Visit karein`,
    subline: (s) => `Saturday-Sunday open`,
    emoji: '🎉',
    layout: 'weekend',
    cta: 'Special weekend offers'
  },
  6: { // Saturday
    id: 'saturday',
    nameEn: 'Trending in City',
    nameHi: 'Aaj Trending',
    bgGradient: ['#DC2626', '#EA580C', '#F59E0B'],
    accent: '#FFFFFF',
    ink: '#FFFFFF',
    headline: (s) => `${s.city || 'Aapke shaher'} mein trending`,
    subline: (s) => `Top rated shop`,
    emoji: '🔥',
    layout: 'trending',
    cta: 'Sabse zyada visit kiya jaane wala shop'
  }
};

// ─── Helpers ─────────────────────────────────────────────────
function yearsLine(s){
  if (s && s.established_year && s.established_year > 1900) {
    const yrs = new Date().getFullYear() - s.established_year;
    if (yrs > 0) return `${yrs}+ saal`;
  }
  return 'Kayi saalon';
}

function getCategoryTip(s){
  const tips = {
    'kirana': 'Hamesha taza maal le — date check karein',
    'grocery': 'Hamesha taza maal le — date check karein',
    'medical': 'Doctor ki prescription zaroor dikhayein',
    'pharmacy': 'Doctor ki prescription zaroor dikhayein',
    'mobile': 'Original bill aur warranty lena na bhulein',
    'electronics': 'Original bill aur warranty lena na bhulein',
    'restaurant': 'Hygiene aur fresh ingredients ka khayal',
    'sweets': 'Festival ke time fresh order karein',
    'salon': 'Apni skin type batao expert se',
    'beauty': 'Apni skin type batao expert se',
    'mechanic': 'Service ke time bill aur warranty lein',
    'tailor': 'Measurements double-check karwayein',
    'clothes': 'Wash care symbols dekh kar khareeden',
    'jewellery': 'Hallmark check karein — purity guarantee',
    'default': 'Quality, trust aur service — yahi sab kuch'
  };
  if (!s || !s.category) return tips.default;
  const c = String(s.category).toLowerCase();
  for (const key in tips) {
    if (c.includes(key)) return tips[key];
  }
  return tips.default;
}

function getTodayTheme(){
  const day = new Date().getDay(); // 0=Sun..6=Sat
  return Object.assign({}, THEMES[day], { dayIndex: day });
}

function getThemeByIndex(idx){
  const i = ((parseInt(idx,10) || 0) % 7 + 7) % 7;
  return Object.assign({}, THEMES[i], { dayIndex: i });
}

// ─── Canvas Rendering ────────────────────────────────────────
async function renderToCanvas(canvas, shopData, theme, size){
  size = size || 1080;
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext('2d');
  theme = theme || getTodayTheme();
  shopData = shopData || {};

  // Background gradient
  const grad = ctx.createLinearGradient(0, 0, size, size);
  const stops = theme.bgGradient || ['#FF6B1A', '#F97316', '#EA580C'];
  for (let i = 0; i < stops.length; i++) {
    grad.addColorStop(i / (stops.length - 1), stops[i]);
  }
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, size, size);

  // Decorative orbs
  ctx.save();
  ctx.globalAlpha = 0.12;
  ctx.fillStyle = theme.accent || '#FFF';
  ctx.beginPath();
  ctx.arc(size*0.85, size*0.15, size*0.18, 0, Math.PI*2);
  ctx.fill();
  ctx.beginPath();
  ctx.arc(size*0.15, size*0.85, size*0.22, 0, Math.PI*2);
  ctx.fill();
  ctx.restore();

  // Top brand strip
  ctx.fillStyle = theme.ink;
  ctx.globalAlpha = 0.65;
  ctx.font = `bold ${Math.floor(size*0.022)}px 'Manrope', Arial, sans-serif`;
  ctx.textAlign = 'left';
  ctx.fillText('DukanList', size*0.06, size*0.075);
  ctx.globalAlpha = 1;

  // Top right: day badge
  const badge = (theme.nameEn || '').toUpperCase();
  ctx.font = `900 ${Math.floor(size*0.022)}px 'Manrope', Arial, sans-serif`;
  ctx.textAlign = 'right';
  ctx.fillStyle = theme.accent;
  // pill bg
  const txtW = ctx.measureText(badge).width;
  const padX = size*0.025, padY = size*0.015;
  ctx.save();
  ctx.globalAlpha = 0.20;
  ctx.fillStyle = theme.accent;
  roundRect(ctx, size*0.94 - txtW - padX*2, size*0.055 - padY, txtW + padX*2, padY*2 + size*0.022, size*0.018);
  ctx.fill();
  ctx.restore();
  ctx.fillStyle = theme.accent;
  ctx.textBaseline = 'middle';
  ctx.fillText(badge, size*0.94 - padX, size*0.062 + padY*0.6);
  ctx.textBaseline = 'alphabetic';

  // Big emoji
  ctx.textAlign = 'center';
  ctx.font = `${Math.floor(size*0.18)}px serif`;
  ctx.fillText(theme.emoji || '✨', size/2, size*0.30);

  // Headline (auto-wrap)
  ctx.fillStyle = theme.ink;
  ctx.font = `900 ${Math.floor(size*0.058)}px 'Manrope', Arial, sans-serif`;
  const headlineText = (typeof theme.headline === 'function')
    ? theme.headline(shopData)
    : (theme.headline || '');
  wrapText(ctx, headlineText, size/2, size*0.42, size*0.85, Math.floor(size*0.072));

  // Subline
  ctx.fillStyle = theme.ink;
  ctx.globalAlpha = 0.85;
  ctx.font = `600 ${Math.floor(size*0.032)}px 'Plus Jakarta Sans', Arial, sans-serif`;
  const subText = (typeof theme.subline === 'function')
    ? theme.subline(shopData)
    : (theme.subline || '');
  wrapText(ctx, subText, size/2, size*0.58, size*0.85, Math.floor(size*0.042));
  ctx.globalAlpha = 1;

  // Shop name card (bottom hero)
  const cardY = size*0.70;
  const cardH = size*0.20;
  ctx.save();
  ctx.fillStyle = 'rgba(255,255,255,0.96)';
  roundRect(ctx, size*0.08, cardY, size*0.84, cardH, size*0.025);
  ctx.fill();
  ctx.restore();

  // Shop name
  ctx.fillStyle = '#0B1220';
  ctx.font = `900 ${Math.floor(size*0.045)}px 'Manrope', Arial, sans-serif`;
  ctx.textAlign = 'center';
  const shopName = (shopData.name || 'Your Shop').toUpperCase();
  wrapText(ctx, shopName, size/2, cardY + size*0.055, size*0.78, Math.floor(size*0.055));

  // Rating row
  if (shopData.rating && shopData.rating > 0) {
    ctx.fillStyle = '#FBBF24';
    ctx.font = `900 ${Math.floor(size*0.035)}px 'Manrope', Arial, sans-serif`;
    const stars = '★'.repeat(Math.round(shopData.rating)) + '☆'.repeat(5 - Math.round(shopData.rating));
    ctx.fillText(stars + '   ' + Number(shopData.rating).toFixed(1), size/2, cardY + size*0.130);
  }

  // Phone
  if (shopData.mobile) {
    ctx.fillStyle = '#1E3A8A';
    ctx.font = `800 ${Math.floor(size*0.030)}px 'Plus Jakarta Sans', Arial, sans-serif`;
    ctx.fillText('📞 ' + shopData.mobile, size/2, cardY + size*0.175);
  }

  // Bottom CTA strip
  ctx.fillStyle = theme.ink;
  ctx.globalAlpha = 0.75;
  ctx.font = `700 ${Math.floor(size*0.024)}px 'Plus Jakarta Sans', Arial, sans-serif`;
  ctx.textAlign = 'center';
  ctx.fillText(theme.cta || '', size/2, size*0.955);
  ctx.globalAlpha = 1;

  // Watermark
  ctx.fillStyle = theme.ink;
  ctx.globalAlpha = 0.45;
  ctx.font = `600 ${Math.floor(size*0.018)}px 'Inter', Arial, sans-serif`;
  ctx.fillText('dukanlist.com', size/2, size*0.978);
  ctx.globalAlpha = 1;

  return canvas;
}

// rounded-rect helper
function roundRect(ctx, x, y, w, h, r){
  ctx.beginPath();
  ctx.moveTo(x+r, y);
  ctx.lineTo(x+w-r, y);
  ctx.quadraticCurveTo(x+w, y, x+w, y+r);
  ctx.lineTo(x+w, y+h-r);
  ctx.quadraticCurveTo(x+w, y+h, x+w-r, y+h);
  ctx.lineTo(x+r, y+h);
  ctx.quadraticCurveTo(x, y+h, x, y+h-r);
  ctx.lineTo(x, y+r);
  ctx.quadraticCurveTo(x, y, x+r, y);
  ctx.closePath();
}

// text wrap helper
function wrapText(ctx, text, x, y, maxWidth, lineHeight){
  if (!text) return;
  const words = String(text).split(' ');
  let line = '';
  let lineY = y;
  for (let i = 0; i < words.length; i++) {
    const test = line + words[i] + ' ';
    if (ctx.measureText(test).width > maxWidth && line.length > 0) {
      ctx.fillText(line.trim(), x, lineY);
      line = words[i] + ' ';
      lineY += lineHeight;
    } else {
      line = test;
    }
  }
  ctx.fillText(line.trim(), x, lineY);
}

// ─── Output helpers ──────────────────────────────────────────
async function renderToBlob(shopData, theme, size){
  const canvas = document.createElement('canvas');
  await renderToCanvas(canvas, shopData, theme, size || 1080);
  return new Promise((resolve) => {
    canvas.toBlob((blob) => resolve(blob), 'image/jpeg', 0.92);
  });
}

async function downloadPoster(shopData, theme, size){
  const blob = await renderToBlob(shopData, theme, size);
  const url  = URL.createObjectURL(blob);
  const a    = document.createElement('a');
  a.href     = url;
  a.download = `dukanlist-${(shopData.slug || shopData.name || 'poster').replace(/[^a-z0-9]/gi,'-')}-${theme.id || 'today'}.jpg`;
  document.body.appendChild(a);
  a.click();
  setTimeout(() => { URL.revokeObjectURL(url); a.remove(); }, 1000);
}

async function shareToWhatsApp(shopData, theme, size){
  const blob = await renderToBlob(shopData, theme, size || 1080);
  const file = new File([blob], 'dukanlist-poster.jpg', { type: 'image/jpeg' });

  // Compose caption
  const caption = composeCaption(shopData, theme);

  // Web Share API path (preferred on Android/iOS PWA)
  if (navigator.canShare && navigator.canShare({ files: [file] })) {
    try {
      await navigator.share({
        files: [file],
        title: shopData.name || 'DukanList',
        text: caption
      });
      return { method: 'share-api' };
    } catch (e) {
      // user cancelled or share blocked — fall through to download
    }
  }

  // Fallback: download + open WhatsApp with text
  await downloadPoster(shopData, theme, size);
  const waUrl = 'https://wa.me/?text=' + encodeURIComponent(caption);
  setTimeout(() => window.open(waUrl, '_blank'), 700);
  return { method: 'download+wa' };
}

function composeCaption(shopData, theme){
  const lines = [];
  if (shopData.name)   lines.push('🏪 ' + shopData.name);
  if (shopData.mobile) lines.push('📞 ' + shopData.mobile);
  if (shopData.slug)   lines.push('🔗 https://dukanlist.com/business.html?slug=' + shopData.slug);
  lines.push('');
  lines.push((theme.cta || 'Aapka local trusted shop'));
  lines.push('');
  lines.push('— DukanList');
  return lines.join('\n');
}

// ─── Public API ──────────────────────────────────────────────
global.DailyPoster = {
  getTodayTheme,
  getThemeByIndex,
  renderToCanvas,
  renderToBlob,
  downloadPoster,
  shareToWhatsApp,
  composeCaption,
  THEMES: THEMES
};

})(window);
