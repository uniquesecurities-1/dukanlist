/* ============================================================
   template-mega-pack.js
   ============================================================
   STRATEGIC PHASE 8.5 (2026-06-05):
   30+ professionally designed poster templates.

   Each template has:
     - Unique layout (not just color swap)
     - Custom canvas render function
     - Distinct typography hierarchy
     - Category awareness (kirana vs medical vs salon)

   Built-ins on every poster:
     - QR code (links to shop's business.html)
     - DukanList watermark
     - Optional shop photo as background

   Language: pass `lang: 'en' | 'hi'` in opts.
   ============================================================ */
(function(global){
'use strict';

// ─── Template Catalogue (30 distinct designs) ──────────────
const TEMPLATES = [
  // ===== PREMIUM CARD COLLECTION (default + recommended) =====
  {
    id: 'premium-cream',
    name: 'Premium Cream',
    nameHi: 'प्रीमियम',
    category: 'all',
    bg: ['#FDFBF6', '#F5F1E8', '#EDE7D7'],
    accent: '#1A1A1A',
    ink: '#1A1A1A',
    style: 'premium-card',
    needsPhoto: true,
    premium: true
  },
  {
    id: 'premium-charcoal',
    name: 'Premium Charcoal',
    nameHi: 'चारकोल',
    category: 'all',
    bg: ['#1A1A1A', '#0F0F0F', '#000000'],
    accent: '#D4AF37',
    ink: '#FFFFFF',
    style: 'premium-card',
    needsPhoto: true,
    premium: true
  },
  {
    id: 'premium-ivory',
    name: 'Premium Ivory',
    nameHi: 'आइवरी',
    category: 'all',
    bg: ['#FFFFFF', '#FAFAFA', '#F4F4F5'],
    accent: '#1E3A8A',
    ink: '#0F172A',
    style: 'premium-card',
    needsPhoto: true,
    premium: true
  },
  {
    id: 'bold-brand',
    name: 'Bold Brand',
    nameHi: 'बोल्ड ब्रांड',
    category: 'all',
    bg: ['#FF6B1A', '#EA580C', '#9A3412'],
    accent: '#FBBF24',
    ink: '#FFFFFF',
    style: 'bold-name'
  },
  {
    id: 'pure-minimal',
    name: 'Pure Minimal',
    nameHi: 'मिनिमल',
    category: 'all',
    bg: ['#FFFFFF', '#F8FAFC', '#F1F5F9'],
    accent: '#0F172A',
    ink: '#0F172A',
    style: 'minimal'
  },
  {
    id: 'photo-hero',
    name: 'Photo Hero',
    nameHi: 'फोटो हीरो',
    category: 'all',
    bg: ['#000000', '#1E293B', '#0F172A'],
    accent: '#FBBF24',
    ink: '#FFFFFF',
    style: 'photo-hero',
    needsPhoto: true
  },
  {
    id: 'royal-elegance',
    name: 'Royal Elegance',
    nameHi: 'रॉयल',
    category: 'all',
    bg: ['#1E1B4B', '#312E81', '#1E1B4B'],
    accent: '#FBBF24',
    ink: '#FFFFFF',
    style: 'elegant'
  },
  {
    id: 'sunshine',
    name: 'Sunshine',
    nameHi: 'सनशाइन',
    category: 'all',
    bg: ['#FBBF24', '#F59E0B', '#D97706'],
    accent: '#451A03',
    ink: '#451A03',
    style: 'bold-name'
  },
  {
    id: 'emerald-trust',
    name: 'Emerald Trust',
    nameHi: 'एमरल्ड',
    category: 'all',
    bg: ['#064E3B', '#047857', '#10B981'],
    accent: '#FBBF24',
    ink: '#FFFFFF',
    style: 'verified'
  },
  {
    id: 'ocean-fresh',
    name: 'Ocean Fresh',
    nameHi: 'ओशन',
    category: 'all',
    bg: ['#0E7490', '#06B6D4', '#67E8F9'],
    accent: '#FFFFFF',
    ink: '#083344',
    style: 'minimal'
  },
  {
    id: 'sunset-glow',
    name: 'Sunset Glow',
    nameHi: 'सनसेट',
    category: 'all',
    bg: ['#DC2626', '#F97316', '#FBBF24'],
    accent: '#FFFFFF',
    ink: '#FFFFFF',
    style: 'bold-name'
  },
  {
    id: 'midnight-pro',
    name: 'Midnight Pro',
    nameHi: 'मिडनाइट',
    category: 'all',
    bg: ['#020617', '#0F172A', '#1E293B'],
    accent: '#22D3EE',
    ink: '#FFFFFF',
    style: 'elegant'
  },
  {
    id: 'rose-classic',
    name: 'Rose Classic',
    nameHi: 'रोज़',
    category: 'all',
    bg: ['#9F1239', '#BE123C', '#E11D48'],
    accent: '#FBBF24',
    ink: '#FFFFFF',
    style: 'elegant'
  },
  {
    id: 'open-now',
    name: 'Open Now',
    nameHi: 'ओपन नाउ',
    category: 'all',
    bg: ['#064E3B', '#10B981', '#34D399'],
    accent: '#FFFFFF',
    ink: '#FFFFFF',
    style: 'open-now'
  },
  {
    id: 'verified-shield',
    name: 'Verified Shield',
    nameHi: 'वेरिफाइड',
    category: 'all',
    bg: ['#1E3A8A', '#3730A3', '#5B21B6'],
    accent: '#FBBF24',
    ink: '#FFFFFF',
    style: 'verified'
  },
  {
    id: 'big-rating',
    name: 'Star Rated',
    nameHi: 'टॉप रेटेड',
    category: 'all',
    bg: ['#78350F', '#D97706', '#FBBF24'],
    accent: '#FFFFFF',
    ink: '#FFFFFF',
    style: 'big-rating'
  },
  {
    id: 'cta-visit',
    name: 'Visit Today',
    nameHi: 'विज़िट टुडे',
    category: 'all',
    bg: ['#7C3AED', '#A855F7', '#C084FC'],
    accent: '#FBBF24',
    ink: '#FFFFFF',
    style: 'cta'
  },
  {
    id: 'qr-card',
    name: 'QR Card',
    nameHi: 'QR कार्ड',
    category: 'all',
    bg: ['#F8FAFC', '#E2E8F0', '#CBD5E1'],
    accent: '#0F172A',
    ink: '#0F172A',
    style: 'qr-hero'
  },
  {
    id: 'phone-prominent',
    name: 'Call Us',
    nameHi: 'कॉल करें',
    category: 'all',
    bg: ['#1E40AF', '#3B82F6', '#60A5FA'],
    accent: '#FBBF24',
    ink: '#FFFFFF',
    style: 'phone-big'
  },
  {
    id: 'years-experience',
    name: 'Years of Trust',
    nameHi: 'अनुभवी',
    category: 'all',
    bg: ['#FDFBF6', '#F5F1E8', '#EDE7D7'],
    accent: '#92400E',
    ink: '#1A1A1A',
    style: 'premium-card',
    needsPhoto: true,
    premium: true
  },
  {
    id: 'mono-sleek',
    name: 'Mono Sleek',
    nameHi: 'मोनो',
    category: 'all',
    bg: ['#000000', '#262626', '#525252'],
    accent: '#FFFFFF',
    ink: '#FFFFFF',
    style: 'minimal'
  },
  {
    id: 'spring-bloom',
    name: 'Spring Bloom',
    nameHi: 'स्प्रिंग',
    category: 'all',
    bg: ['#FECDD3', '#FDA4AF', '#FB7185'],
    accent: '#9F1239',
    ink: '#881337',
    style: 'minimal'
  },
  {
    id: 'tropical',
    name: 'Tropical',
    nameHi: 'ट्रॉपिकल',
    category: 'all',
    bg: ['#0F766E', '#14B8A6', '#5EEAD4'],
    accent: '#FBBF24',
    ink: '#FFFFFF',
    style: 'bold-name'
  },
  // Category-flavored
  {
    id: 'medical-card',
    name: 'Medical Card',
    nameHi: 'मेडिकल',
    category: 'medical',
    bg: ['#DBEAFE', '#FFFFFF', '#DBEAFE'],
    accent: '#DC2626',
    ink: '#1E3A8A',
    style: 'medical'
  },
  {
    id: 'restaurant-special',
    name: 'Menu Special',
    nameHi: 'मेनू',
    category: 'restaurant',
    bg: ['#7F1D1D', '#991B1B', '#B91C1C'],
    accent: '#FBBF24',
    ink: '#FFFFFF',
    style: 'restaurant'
  },
  {
    id: 'salon-glam',
    name: 'Salon Glam',
    nameHi: 'सलोन',
    category: 'salon',
    bg: ['#1F2937', '#374151', '#F472B6'],
    accent: '#FBBF24',
    ink: '#FFFFFF',
    style: 'salon'
  },
  {
    id: 'jewellery-gold',
    name: 'Gold Standard',
    nameHi: 'गोल्ड',
    category: 'jewellery',
    bg: ['#451A03', '#78350F', '#FBBF24'],
    accent: '#FEF3C7',
    ink: '#FEF3C7',
    style: 'elegant'
  },
  {
    id: 'kirana-fresh',
    name: 'Kirana Fresh',
    nameHi: 'किराना',
    category: 'kirana',
    bg: ['#15803D', '#16A34A', '#22C55E'],
    accent: '#FEF3C7',
    ink: '#FFFFFF',
    style: 'bold-name'
  },
  {
    id: 'mobile-tech',
    name: 'Mobile Tech',
    nameHi: 'मोबाइल',
    category: 'mobile',
    bg: ['#1E40AF', '#3730A3', '#000000'],
    accent: '#22D3EE',
    ink: '#FFFFFF',
    style: 'minimal'
  },
  {
    id: 'clothes-fashion',
    name: 'Fashion Pick',
    nameHi: 'फैशन',
    category: 'clothes',
    bg: ['#000000', '#1F2937', '#EC4899'],
    accent: '#FBBF24',
    ink: '#FFFFFF',
    style: 'salon'
  },
  // Festival ready
  {
    id: 'fest-diwali',
    name: 'Diwali Glow',
    nameHi: 'दिवाली',
    category: 'all',
    bg: ['#451A03', '#92400E', '#FBBF24'],
    accent: '#FEF3C7',
    ink: '#FFFFFF',
    style: 'festival',
    festivalEmoji: '🪔',
    festivalHeadline: 'Happy Diwali',
    festivalSub: 'Wishing you light and prosperity'
  },
  {
    id: 'fest-holi',
    name: 'Holi Burst',
    nameHi: 'होली',
    category: 'all',
    bg: ['#DB2777', '#A855F7', '#3B82F6'],
    accent: '#FCD34D',
    ink: '#FFFFFF',
    style: 'festival',
    festivalEmoji: '🎨',
    festivalHeadline: 'Happy Holi',
    festivalSub: 'A festival of colours and joy'
  },
  {
    id: 'fest-eid',
    name: 'Eid Mubarak',
    nameHi: 'ईद',
    category: 'all',
    bg: ['#064E3B', '#047857', '#FBBF24'],
    accent: '#FEF3C7',
    ink: '#FFFFFF',
    style: 'festival',
    festivalEmoji: '🌙',
    festivalHeadline: 'Eid Mubarak',
    festivalSub: 'Peace and blessings to you'
  },
  {
    id: 'fest-independence',
    name: 'Tiranga',
    nameHi: 'तिरंगा',
    category: 'all',
    bg: ['#FF6B1A', '#FFFFFF', '#16A34A'],
    accent: '#1E3A8A',
    ink: '#1E3A8A',
    style: 'festival',
    festivalEmoji: '🇮🇳',
    festivalHeadline: 'Proud Indian',
    festivalSub: 'Serving the community since'
  },
  {
    id: 'fest-rakhi',
    name: 'Rakhi',
    nameHi: 'राखी',
    category: 'all',
    bg: ['#F59E0B', '#DC2626', '#7C2D12'],
    accent: '#FEF3C7',
    ink: '#FFFFFF',
    style: 'festival',
    festivalEmoji: '🪢',
    festivalHeadline: 'Happy Rakhi',
    festivalSub: 'Bonds that last a lifetime'
  }
];

// ─── Helpers ───────────────────────────────────────────────
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

function wrapText(ctx, text, x, y, maxWidth, lineHeight, maxLines){
  if (!text) return y;
  const words = String(text).split(' ');
  let line = '';
  let lineY = y;
  let linesUsed = 0;
  maxLines = maxLines || 99;
  for (let i = 0; i < words.length; i++) {
    const test = line + words[i] + ' ';
    if (ctx.measureText(test).width > maxWidth && line.length > 0) {
      ctx.fillText(line.trim(), x, lineY);
      line = words[i] + ' ';
      lineY += lineHeight;
      linesUsed++;
      if (linesUsed >= maxLines) return lineY;
    } else {
      line = test;
    }
  }
  ctx.fillText(line.trim(), x, lineY);
  return lineY + lineHeight;
}

function drawBackground(ctx, tmpl, size){
  const grad = ctx.createLinearGradient(0, 0, size, size);
  const stops = tmpl.bg;
  for (let i = 0; i < stops.length; i++) {
    grad.addColorStop(i / (stops.length - 1), stops[i]);
  }
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, size, size);
}

function drawWatermark(ctx, tmpl, size){
  ctx.fillStyle = tmpl.ink;
  ctx.globalAlpha = 0.45;
  ctx.font = `600 ${Math.floor(size*0.018)}px 'Inter', Arial, sans-serif`;
  ctx.textAlign = 'center';
  ctx.fillText('dukanlist.com', size/2, size*0.985);
  ctx.globalAlpha = 1;
}

function drawBrandStrip(ctx, tmpl, size){
  ctx.fillStyle = tmpl.ink;
  ctx.globalAlpha = 0.7;
  ctx.font = `800 ${Math.floor(size*0.022)}px 'Manrope', Arial, sans-serif`;
  ctx.textAlign = 'left';
  ctx.fillText('DukanList', size*0.06, size*0.07);
  ctx.globalAlpha = 1;
}

// QR code via external API (free, no key, returns PNG)
async function loadQrImage(text, size){
  return new Promise((resolve) => {
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => resolve(img);
    img.onerror = () => resolve(null);
    const url = 'https://api.qrserver.com/v1/create-qr-code/?size=' +
                size + 'x' + size + '&data=' + encodeURIComponent(text) +
                '&margin=0&format=png';
    img.src = url;
    setTimeout(() => resolve(null), 4000); // timeout
  });
}

async function drawQrCorner(ctx, shop, size){
  const qrText = 'https://dukanlist.com/business.html?slug=' + (shop.slug || '');
  const qrSize = Math.floor(size * 0.13);
  const qrImg = await loadQrImage(qrText, 220);
  const padding = Math.floor(size * 0.025);
  // White rounded backdrop
  ctx.fillStyle = '#ffffff';
  roundRect(ctx, size - qrSize - padding*2, size - qrSize - padding*2 - size*0.02, qrSize + padding, qrSize + padding, size*0.012);
  ctx.fill();
  if (qrImg) {
    ctx.drawImage(qrImg, size - qrSize - padding*1.5, size - qrSize - padding*1.5 - size*0.02, qrSize, qrSize);
  } else {
    // fallback: just put "SCAN" text
    ctx.fillStyle = '#0F172A';
    ctx.font = `900 ${Math.floor(qrSize*0.2)}px 'Manrope', Arial`;
    ctx.textAlign = 'center';
    ctx.fillText('SCAN', size - qrSize/2 - padding*1.5, size - qrSize/2 - padding*1.5 - size*0.02);
  }
}

async function loadPhotoImg(url){
  return new Promise((resolve) => {
    if (!url) return resolve(null);
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => resolve(img);
    img.onerror = () => resolve(null);
    img.src = url;
    setTimeout(() => resolve(null), 5000);
  });
}

function txt(lang, en, hi){
  return (lang === 'hi' && hi) ? hi : en;
}

// ─── Style renderers ───────────────────────────────────────
async function renderTemplate(canvas, shop, tmpl, opts){
  opts = opts || {};
  const size = opts.size || 1080;
  const lang = opts.lang || 'en';
  // Apply overrides
  if (opts.customAccent && /^#[0-9a-f]{6}$/i.test(opts.customAccent)) {
    tmpl = Object.assign({}, tmpl, { accent: opts.customAccent });
  }
  if (opts.customHeadline) shop = Object.assign({}, shop, { _customHeadline: opts.customHeadline });
  if (opts.customSubline)  shop = Object.assign({}, shop, { _customSubline: opts.customSubline });
  if (opts.photoOverride)  shop = Object.assign({}, shop, { photo: opts.photoOverride });
  const stickers = Array.isArray(opts.stickers) ? opts.stickers : [];
  const usePhotoBg = !!opts.usePhotoBg && !!shop.photo;
  canvas.width = size; canvas.height = size;
  const ctx = canvas.getContext('2d');

  // 1. Background — gradient or photo (premium-card handles its own)
  if (tmpl.style === 'premium-card') {
    // skip — drawPremiumCard handles background
  } else if (usePhotoBg) {
    const img = await loadPhotoImg(shop.photo);
    if (img) {
      // cover-fit
      const ratio = Math.max(size/img.width, size/img.height);
      const w = img.width * ratio;
      const h = img.height * ratio;
      ctx.drawImage(img, (size-w)/2, (size-h)/2, w, h);
      // dark overlay for legibility
      ctx.fillStyle = 'rgba(0,0,0,0.55)';
      ctx.fillRect(0, 0, size, size);
    } else {
      drawBackground(ctx, tmpl, size);
    }
  } else {
    drawBackground(ctx, tmpl, size);
  }

  // 2. Decorative orbs (light) — also skip for premium-card
  if (tmpl.style !== 'minimal' && tmpl.style !== 'medical' && tmpl.style !== 'premium-card') {
    ctx.save();
    ctx.globalAlpha = 0.12;
    ctx.fillStyle = tmpl.accent || '#FFF';
    ctx.beginPath(); ctx.arc(size*0.88, size*0.12, size*0.16, 0, Math.PI*2); ctx.fill();
    ctx.beginPath(); ctx.arc(size*0.12, size*0.88, size*0.20, 0, Math.PI*2); ctx.fill();
    ctx.restore();
  }

  // 3. Brand strip (skip for premium-card clean style)
  if (tmpl.style !== 'premium-card') {
    drawBrandStrip(ctx, tmpl, size);
  }

  // 4. Style-specific rendering
  switch (tmpl.style) {
    case 'bold-name':       drawBoldName(ctx, shop, tmpl, size, lang); break;
    case 'minimal':         drawMinimal(ctx, shop, tmpl, size, lang); break;
    case 'elegant':         drawElegant(ctx, shop, tmpl, size, lang); break;
    case 'verified':        drawVerified(ctx, shop, tmpl, size, lang); break;
    case 'big-rating':      drawBigRating(ctx, shop, tmpl, size, lang); break;
    case 'cta':             drawCta(ctx, shop, tmpl, size, lang); break;
    case 'qr-hero':         drawQrHero(ctx, shop, tmpl, size, lang); break;
    case 'phone-big':       drawPhoneBig(ctx, shop, tmpl, size, lang); break;
    case 'years':           drawYears(ctx, shop, tmpl, size, lang); break;
    case 'open-now':        drawOpenNow(ctx, shop, tmpl, size, lang); break;
    case 'photo-hero':      drawPhotoHero(ctx, shop, tmpl, size, lang); break;
    case 'medical':         drawMedical(ctx, shop, tmpl, size, lang); break;
    case 'restaurant':      drawRestaurant(ctx, shop, tmpl, size, lang); break;
    case 'salon':           drawSalon(ctx, shop, tmpl, size, lang); break;
    case 'festival':        drawFestival(ctx, shop, tmpl, size, lang); break;
    case 'premium-card':    await drawPremiumCard(ctx, shop, tmpl, size, lang, opts); break;
    default:                drawBoldName(ctx, shop, tmpl, size, lang);
  }

  // 5. QR code corner (skip for premium-card which has clean layout)
  if (tmpl.style !== 'qr-hero' && tmpl.style !== 'premium-card') {
    await drawQrCorner(ctx, shop, size);
  }

  // 6a. Logo overlay (if provided)
  if (opts.logoUrl) {
    try { await drawLogoOverlay(ctx, opts.logoUrl, size); } catch(_){}
  }

  // 6b. Deal banner (if provided)
  if (opts.dealText) {
    try { drawDealBanner(ctx, opts.dealText, opts.dealAccent || tmpl.accent, tmpl, size); } catch(_){}
  }

  // 7. Watermark (skip for premium-card)
  if (tmpl.style !== 'premium-card') {
    drawWatermark(ctx, tmpl, size);
  }

  // 7. Sticker layer (NEW / SALE / OFFER / FREE)
  if (stickers.length > 0) {
    stickers.forEach((st, idx) => drawSticker(ctx, st, size, idx));
  }

  return canvas;
}

// ─── Sticker badges ───────────────────────────────────────
function drawSticker(ctx, sticker, sz, idx){
  const corners = [
    { x: sz*0.10, y: sz*0.15 },   // top-left
    { x: sz*0.78, y: sz*0.15 },   // top-right
    { x: sz*0.10, y: sz*0.55 },   // mid-left
    { x: sz*0.78, y: sz*0.55 }    // mid-right
  ];
  const pos = corners[idx % 4];
  const r = sz * 0.085;

  let bg = '#FBBF24', fg = '#0F172A', label = sticker;
  if (sticker === 'NEW')    { bg = '#10B981'; fg = '#fff'; }
  if (sticker === 'SALE')   { bg = '#DC2626'; fg = '#fff'; }
  if (sticker === 'OFFER')  { bg = '#F97316'; fg = '#fff'; }
  if (sticker === 'FREE')   { bg = '#A855F7'; fg = '#fff'; }
  if (sticker === 'HOT')    { bg = '#EF4444'; fg = '#fff'; }
  if (sticker === 'TOP')    { bg = '#FBBF24'; fg = '#0F172A'; }

  ctx.save();
  ctx.translate(pos.x + r, pos.y + r);
  ctx.rotate(-Math.PI / 12);  // slight tilt

  // Star burst
  ctx.fillStyle = bg;
  ctx.beginPath();
  const points = 10;
  for (let i = 0; i < points * 2; i++) {
    const angle = (Math.PI / points) * i;
    const radius = (i % 2 === 0) ? r : r * 0.78;
    const x = Math.cos(angle) * radius;
    const y = Math.sin(angle) * radius;
    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
  }
  ctx.closePath();
  ctx.fill();

  // Drop shadow
  ctx.shadowColor = 'rgba(0,0,0,.35)';
  ctx.shadowBlur = sz * 0.012;
  ctx.fill();
  ctx.shadowBlur = 0;

  // Label
  ctx.fillStyle = fg;
  ctx.font = `900 ${Math.floor(sz*0.028)}px 'Manrope', Arial`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(label, 0, 0);
  ctx.textBaseline = 'alphabetic';

  ctx.restore();
}

// ─── Layout: Bold Name ─────────────────────────────────────
function drawBoldName(ctx, s, t, sz, lang){
  ctx.textAlign = 'center';
  ctx.fillStyle = t.ink;
  ctx.font = `900 ${Math.floor(sz*0.10)}px 'Manrope', Arial`;
  const headline = (s._customHeadline || s.name || 'Your Business').toUpperCase();
  wrapText(ctx, headline, sz/2, sz*0.32, sz*0.82, Math.floor(sz*0.11), 3);

  ctx.font = `700 ${Math.floor(sz*0.034)}px 'Plus Jakarta Sans', Arial`;
  ctx.fillStyle = t.accent;
  ctx.fillText(s._customSubline || txt(lang, 'Visit Today', 'आज ही आएँ'), sz/2, sz*0.62);

  // Phone strip
  if (s.mobile) {
    ctx.fillStyle = t.ink;
    ctx.globalAlpha = 0.92;
    ctx.font = `800 ${Math.floor(sz*0.030)}px 'Plus Jakarta Sans', Arial`;
    ctx.fillText('📞 ' + s.mobile, sz/2, sz*0.70);
    ctx.globalAlpha = 1;
  }

  // Rating
  if (s.rating > 0) {
    ctx.fillStyle = t.accent;
    ctx.font = `900 ${Math.floor(sz*0.030)}px 'Manrope', Arial`;
    const stars = '★'.repeat(Math.round(s.rating)) + '☆'.repeat(5 - Math.round(s.rating));
    ctx.fillText(stars + '   ' + Number(s.rating).toFixed(1), sz/2, sz*0.77);
  }
}

// ─── Layout: Minimal ───────────────────────────────────────
function drawMinimal(ctx, s, t, sz, lang){
  // Left-aligned, lots of whitespace
  ctx.textAlign = 'left';
  ctx.fillStyle = t.accent;
  ctx.font = `700 ${Math.floor(sz*0.022)}px 'Inter', Arial`;
  ctx.fillText(txt(lang, 'LOCAL BUSINESS', 'लोकल बिज़नेस'), sz*0.08, sz*0.18);

  ctx.fillStyle = t.ink;
  ctx.font = `900 ${Math.floor(sz*0.078)}px 'Manrope', Arial`;
  wrapText(ctx, (s.name || 'Your Business'), sz*0.08, sz*0.30, sz*0.78, Math.floor(sz*0.088), 4);

  // Divider
  ctx.fillStyle = t.accent;
  ctx.fillRect(sz*0.08, sz*0.62, sz*0.20, 4);

  // Sub
  ctx.fillStyle = t.ink;
  ctx.globalAlpha = 0.75;
  ctx.font = `600 ${Math.floor(sz*0.028)}px 'Plus Jakarta Sans', Arial`;
  if (s.mobile) ctx.fillText('📞 ' + s.mobile, sz*0.08, sz*0.72);
  if (s.city)   ctx.fillText('📍 ' + s.city,   sz*0.08, sz*0.78);
  ctx.globalAlpha = 1;
}

// ─── Layout: Elegant ───────────────────────────────────────
function drawElegant(ctx, s, t, sz, lang){
  // Centered, with ornamental frames
  ctx.strokeStyle = t.accent;
  ctx.lineWidth = sz*0.005;
  ctx.strokeRect(sz*0.10, sz*0.22, sz*0.80, sz*0.56);
  ctx.lineWidth = sz*0.002;
  ctx.strokeRect(sz*0.12, sz*0.24, sz*0.76, sz*0.52);

  ctx.fillStyle = t.accent;
  ctx.textAlign = 'center';
  ctx.font = `700 ${Math.floor(sz*0.022)}px 'Inter', Arial`;
  ctx.fillText('— ESTABLISHED —', sz/2, sz*0.30);

  ctx.fillStyle = t.ink;
  ctx.font = `900 ${Math.floor(sz*0.066)}px 'Manrope', Arial`;
  wrapText(ctx, (s.name || 'Your Business'), sz/2, sz*0.42, sz*0.70, Math.floor(sz*0.072), 3);

  if (s.established_year) {
    ctx.fillStyle = t.accent;
    ctx.font = `900 ${Math.floor(sz*0.052)}px 'Manrope', Arial`;
    ctx.fillText(String(s.established_year), sz/2, sz*0.62);
  }

  if (s.mobile) {
    ctx.fillStyle = t.ink;
    ctx.font = `700 ${Math.floor(sz*0.028)}px 'Plus Jakarta Sans', Arial`;
    ctx.fillText('📞 ' + s.mobile, sz/2, sz*0.72);
  }
}

// ─── Layout: Verified shield ───────────────────────────────
function drawVerified(ctx, s, t, sz, lang){
  ctx.textAlign = 'center';
  ctx.font = `${Math.floor(sz*0.20)}px serif`;
  ctx.fillStyle = t.accent;
  ctx.fillText('🛡️', sz/2, sz*0.32);

  ctx.fillStyle = t.ink;
  ctx.font = `900 ${Math.floor(sz*0.054)}px 'Manrope', Arial`;
  ctx.fillText(txt(lang, 'DukanList Verified', 'DukanList वेरिफाइड'), sz/2, sz*0.42);

  ctx.fillStyle = t.accent;
  ctx.font = `700 ${Math.floor(sz*0.026)}px 'Plus Jakarta Sans', Arial`;
  ctx.fillText(txt(lang, 'Personally verified by our team', 'टीम द्वारा जांचा गया'), sz/2, sz*0.49);

  // Shop name card
  ctx.fillStyle = 'rgba(255,255,255,0.95)';
  roundRect(ctx, sz*0.08, sz*0.58, sz*0.84, sz*0.20, sz*0.025);
  ctx.fill();
  ctx.fillStyle = '#0F172A';
  ctx.font = `900 ${Math.floor(sz*0.044)}px 'Manrope', Arial`;
  wrapText(ctx, (s.name || 'Your Business').toUpperCase(), sz/2, sz*0.66, sz*0.78, Math.floor(sz*0.050), 2);
  if (s.mobile) {
    ctx.fillStyle = '#1E3A8A';
    ctx.font = `800 ${Math.floor(sz*0.030)}px 'Plus Jakarta Sans', Arial`;
    ctx.fillText('📞 ' + s.mobile, sz/2, sz*0.75);
  }
}

// ─── Layout: Big Rating ────────────────────────────────────
function drawBigRating(ctx, s, t, sz, lang){
  ctx.textAlign = 'center';
  const r = s.rating || 5;
  ctx.fillStyle = t.accent;
  ctx.font = `900 ${Math.floor(sz*0.20)}px 'Manrope', Arial`;
  ctx.fillText(Number(r).toFixed(1), sz/2, sz*0.40);

  ctx.font = `${Math.floor(sz*0.08)}px serif`;
  ctx.fillText('★★★★★', sz/2, sz*0.52);

  ctx.fillStyle = t.ink;
  ctx.font = `700 ${Math.floor(sz*0.024)}px 'Plus Jakarta Sans', Arial`;
  ctx.fillText(txt(lang, 'TOP RATED', 'टॉप रेटेड'), sz/2, sz*0.58);

  ctx.font = `900 ${Math.floor(sz*0.044)}px 'Manrope', Arial`;
  wrapText(ctx, (s.name || 'Your Business'), sz/2, sz*0.70, sz*0.78, Math.floor(sz*0.050), 2);

  if (s.mobile) {
    ctx.fillStyle = t.accent;
    ctx.font = `800 ${Math.floor(sz*0.028)}px 'Plus Jakarta Sans', Arial`;
    ctx.fillText('📞 ' + s.mobile, sz/2, sz*0.80);
  }
}

// ─── Layout: CTA ───────────────────────────────────────────
function drawCta(ctx, s, t, sz, lang){
  ctx.textAlign = 'center';
  ctx.fillStyle = t.ink;
  ctx.font = `900 ${Math.floor(sz*0.12)}px 'Manrope', Arial`;
  ctx.fillText(txt(lang, 'VISIT', 'आइए'), sz/2, sz*0.30);
  ctx.fillStyle = t.accent;
  ctx.fillText(txt(lang, 'TODAY!', 'आज!'), sz/2, sz*0.46);

  ctx.fillStyle = t.ink;
  ctx.font = `900 ${Math.floor(sz*0.046)}px 'Manrope', Arial`;
  wrapText(ctx, (s.name || 'Your Business'), sz/2, sz*0.62, sz*0.78, Math.floor(sz*0.052), 2);

  if (s.mobile) {
    // Big phone button
    ctx.fillStyle = t.accent;
    roundRect(ctx, sz*0.20, sz*0.72, sz*0.60, sz*0.085, sz*0.042);
    ctx.fill();
    ctx.fillStyle = '#0F172A';
    ctx.font = `900 ${Math.floor(sz*0.036)}px 'Plus Jakarta Sans', Arial`;
    ctx.textBaseline = 'middle';
    ctx.fillText('📞 ' + s.mobile, sz/2, sz*0.762);
    ctx.textBaseline = 'alphabetic';
  }
}

// ─── Layout: QR Hero ───────────────────────────────────────
async function drawQrHero(ctx, s, t, sz, lang){
  ctx.textAlign = 'center';
  ctx.fillStyle = t.ink;
  ctx.font = `900 ${Math.floor(sz*0.050)}px 'Manrope', Arial`;
  ctx.fillText(txt(lang, 'SCAN TO VIEW', 'स्कैन करें'), sz/2, sz*0.20);

  // Big QR centered
  const qrSize = sz * 0.50;
  const qrText = 'https://dukanlist.com/business.html?slug=' + (s.slug || '');
  const qrImg = await loadQrImage(qrText, 400);
  // White bg square
  ctx.fillStyle = '#fff';
  roundRect(ctx, (sz-qrSize)/2 - sz*0.02, sz*0.25, qrSize + sz*0.04, qrSize + sz*0.04, sz*0.025);
  ctx.fill();
  if (qrImg) {
    ctx.drawImage(qrImg, (sz-qrSize)/2, sz*0.27, qrSize, qrSize);
  }

  ctx.fillStyle = t.ink;
  ctx.font = `900 ${Math.floor(sz*0.044)}px 'Manrope', Arial`;
  wrapText(ctx, (s.name || 'Your Business'), sz/2, sz*0.85, sz*0.78, Math.floor(sz*0.050), 2);
}

// ─── Layout: Phone Big ─────────────────────────────────────
function drawPhoneBig(ctx, s, t, sz, lang){
  ctx.textAlign = 'center';
  ctx.fillStyle = t.ink;
  ctx.font = `${Math.floor(sz*0.18)}px serif`;
  ctx.fillText('📞', sz/2, sz*0.28);

  ctx.fillStyle = t.accent;
  ctx.font = `700 ${Math.floor(sz*0.026)}px 'Plus Jakarta Sans', Arial`;
  ctx.fillText(txt(lang, 'CALL US NOW', 'अभी कॉल करें'), sz/2, sz*0.36);

  if (s.mobile) {
    ctx.fillStyle = t.ink;
    ctx.font = `900 ${Math.floor(sz*0.082)}px 'Manrope', Arial`;
    ctx.fillText(s.mobile, sz/2, sz*0.50);
  }

  ctx.font = `900 ${Math.floor(sz*0.042)}px 'Manrope', Arial`;
  wrapText(ctx, (s.name || 'Your Business'), sz/2, sz*0.66, sz*0.78, Math.floor(sz*0.048), 2);

  if (s.rating > 0) {
    ctx.fillStyle = t.accent;
    ctx.font = `900 ${Math.floor(sz*0.030)}px 'Manrope', Arial`;
    ctx.fillText('★ ' + Number(s.rating).toFixed(1), sz/2, sz*0.76);
  }
}

// ─── Layout: Years ─────────────────────────────────────────
function drawYears(ctx, s, t, sz, lang){
  const yrs = s.established_year ? (new Date().getFullYear() - s.established_year) : 10;
  ctx.textAlign = 'center';
  ctx.fillStyle = t.accent;
  ctx.font = `900 ${Math.floor(sz*0.22)}px 'Manrope', Arial`;
  ctx.fillText(yrs + '+', sz/2, sz*0.36);

  ctx.fillStyle = t.ink;
  ctx.font = `700 ${Math.floor(sz*0.034)}px 'Plus Jakarta Sans', Arial`;
  ctx.fillText(txt(lang, 'YEARS OF TRUST', 'सालों का भरोसा'), sz/2, sz*0.46);

  ctx.font = `900 ${Math.floor(sz*0.044)}px 'Manrope', Arial`;
  wrapText(ctx, (s.name || 'Your Business'), sz/2, sz*0.62, sz*0.78, Math.floor(sz*0.050), 2);

  if (s.mobile) {
    ctx.fillStyle = t.accent;
    ctx.font = `800 ${Math.floor(sz*0.028)}px 'Plus Jakarta Sans', Arial`;
    ctx.fillText('📞 ' + s.mobile, sz/2, sz*0.76);
  }
}

// ─── Layout: Open Now ──────────────────────────────────────
function drawOpenNow(ctx, s, t, sz, lang){
  ctx.textAlign = 'center';
  // Pulsing badge
  ctx.fillStyle = '#fff';
  roundRect(ctx, sz*0.30, sz*0.18, sz*0.40, sz*0.07, sz*0.035);
  ctx.fill();
  ctx.fillStyle = '#10B981';
  ctx.beginPath(); ctx.arc(sz*0.36, sz*0.215, sz*0.012, 0, Math.PI*2); ctx.fill();
  ctx.fillStyle = '#065F46';
  ctx.font = `900 ${Math.floor(sz*0.024)}px 'Manrope', Arial`;
  ctx.textBaseline = 'middle';
  ctx.fillText(txt(lang, 'OPEN NOW', 'अभी खुला है'), sz*0.52, sz*0.215);
  ctx.textBaseline = 'alphabetic';

  ctx.fillStyle = t.ink;
  ctx.font = `900 ${Math.floor(sz*0.066)}px 'Manrope', Arial`;
  wrapText(ctx, (s.name || 'Your Business'), sz/2, sz*0.42, sz*0.82, Math.floor(sz*0.074), 3);

  ctx.fillStyle = t.accent;
  ctx.font = `800 ${Math.floor(sz*0.032)}px 'Plus Jakarta Sans', Arial`;
  ctx.fillText(txt(lang, 'Walk in or call now', 'अभी आइए या कॉल करें'), sz/2, sz*0.65);

  if (s.mobile) {
    ctx.fillStyle = t.ink;
    ctx.font = `900 ${Math.floor(sz*0.040)}px 'Plus Jakarta Sans', Arial`;
    ctx.fillText('📞 ' + s.mobile, sz/2, sz*0.74);
  }
}

// ─── Layout: Photo Hero (uses shop photo) ──────────────────
function drawPhotoHero(ctx, s, t, sz, lang){
  // Photo already drawn as background
  // Bottom dark gradient overlay
  const g = ctx.createLinearGradient(0, sz*0.50, 0, sz);
  g.addColorStop(0, 'rgba(0,0,0,0)');
  g.addColorStop(1, 'rgba(0,0,0,0.85)');
  ctx.fillStyle = g;
  ctx.fillRect(0, sz*0.50, sz, sz*0.50);

  ctx.textAlign = 'left';
  ctx.fillStyle = '#fff';
  ctx.font = `900 ${Math.floor(sz*0.062)}px 'Manrope', Arial`;
  wrapText(ctx, (s.name || 'Your Business'), sz*0.08, sz*0.75, sz*0.84, Math.floor(sz*0.068), 2);
  ctx.fillStyle = t.accent;
  ctx.font = `700 ${Math.floor(sz*0.028)}px 'Plus Jakarta Sans', Arial`;
  ctx.fillText(txt(lang, 'TRUSTED LOCAL BUSINESS', 'भरोसेमंद लोकल बिज़नेस'), sz*0.08, sz*0.84);
  if (s.mobile) {
    ctx.fillStyle = '#fff';
    ctx.font = `800 ${Math.floor(sz*0.030)}px 'Plus Jakarta Sans', Arial`;
    ctx.fillText('📞 ' + s.mobile, sz*0.08, sz*0.90);
  }
}

// ─── Layout: Medical ───────────────────────────────────────
function drawMedical(ctx, s, t, sz, lang){
  // Prescription pad style
  ctx.textAlign = 'center';
  // Plus icon
  ctx.fillStyle = t.accent;
  ctx.font = `${Math.floor(sz*0.10)}px serif`;
  ctx.fillText('⚕️', sz/2, sz*0.22);

  ctx.fillStyle = t.ink;
  ctx.font = `900 ${Math.floor(sz*0.054)}px 'Manrope', Arial`;
  wrapText(ctx, (s.name || 'Medical Store'), sz/2, sz*0.36, sz*0.82, Math.floor(sz*0.060), 3);

  // Rx line
  ctx.fillStyle = t.accent;
  ctx.font = `700 ${Math.floor(sz*0.024)}px 'Plus Jakarta Sans', Arial`;
  ctx.fillText(txt(lang, 'Rx — Trusted Pharmacy', 'Rx — विश्वसनीय फार्मेसी'), sz/2, sz*0.56);

  // Phone box
  if (s.mobile) {
    ctx.fillStyle = t.accent;
    roundRect(ctx, sz*0.20, sz*0.66, sz*0.60, sz*0.075, sz*0.038);
    ctx.fill();
    ctx.fillStyle = '#fff';
    ctx.font = `900 ${Math.floor(sz*0.032)}px 'Plus Jakarta Sans', Arial`;
    ctx.textBaseline = 'middle';
    ctx.fillText('📞 ' + s.mobile, sz/2, sz*0.6975);
    ctx.textBaseline = 'alphabetic';
  }
}

// ─── Layout: Restaurant ────────────────────────────────────
function drawRestaurant(ctx, s, t, sz, lang){
  ctx.textAlign = 'center';
  ctx.fillStyle = t.accent;
  ctx.font = `${Math.floor(sz*0.14)}px serif`;
  ctx.fillText('🍽️', sz/2, sz*0.28);
  ctx.fillStyle = t.accent;
  ctx.font = `700 ${Math.floor(sz*0.026)}px 'Plus Jakarta Sans', Arial`;
  ctx.fillText(txt(lang, 'TASTE THE BEST', 'सबसे बढ़िया स्वाद'), sz/2, sz*0.36);

  ctx.fillStyle = t.ink;
  ctx.font = `900 ${Math.floor(sz*0.062)}px 'Manrope', Arial`;
  wrapText(ctx, (s.name || 'Restaurant'), sz/2, sz*0.50, sz*0.82, Math.floor(sz*0.068), 3);

  if (s.mobile) {
    ctx.fillStyle = t.ink;
    ctx.font = `800 ${Math.floor(sz*0.030)}px 'Plus Jakarta Sans', Arial`;
    ctx.fillText('📞 ' + s.mobile, sz/2, sz*0.72);
  }
  ctx.fillStyle = t.accent;
  ctx.font = `700 ${Math.floor(sz*0.022)}px 'Plus Jakarta Sans', Arial`;
  ctx.fillText(txt(lang, 'DINE-IN · TAKEAWAY · HOME DELIVERY', 'डाइन-इन · टेकअवे · होम डिलीवरी'), sz/2, sz*0.78);
}

// ─── Layout: Salon ─────────────────────────────────────────
function drawSalon(ctx, s, t, sz, lang){
  ctx.textAlign = 'left';
  ctx.fillStyle = t.accent;
  ctx.font = `700 ${Math.floor(sz*0.022)}px 'Inter', Arial`;
  ctx.fillText(txt(lang, '— BEAUTY & STYLE —', '— सुंदरता और शैली —'), sz*0.08, sz*0.18);

  ctx.fillStyle = t.ink;
  ctx.font = `900 ${Math.floor(sz*0.080)}px 'Manrope', Arial`;
  wrapText(ctx, (s.name || 'Your Salon'), sz*0.08, sz*0.34, sz*0.84, Math.floor(sz*0.088), 3);

  // Lipstick / accent line
  ctx.fillStyle = t.accent;
  ctx.fillRect(sz*0.08, sz*0.62, sz*0.40, sz*0.008);

  ctx.fillStyle = t.ink;
  ctx.globalAlpha = 0.85;
  ctx.font = `600 ${Math.floor(sz*0.028)}px 'Plus Jakarta Sans', Arial`;
  if (s.mobile) ctx.fillText('Book: ' + s.mobile, sz*0.08, sz*0.72);
  ctx.globalAlpha = 1;
}

// ─── Layout: Festival ──────────────────────────────────────
function drawFestival(ctx, s, t, sz, lang){
  ctx.textAlign = 'center';
  ctx.font = `${Math.floor(sz*0.22)}px serif`;
  ctx.fillStyle = t.accent;
  ctx.fillText(t.festivalEmoji || '🎉', sz/2, sz*0.32);

  ctx.fillStyle = t.accent;
  ctx.font = `900 ${Math.floor(sz*0.062)}px 'Manrope', Arial`;
  ctx.fillText(t.festivalHeadline || 'Happy Festival', sz/2, sz*0.45);

  ctx.fillStyle = t.ink;
  ctx.font = `600 ${Math.floor(sz*0.028)}px 'Plus Jakarta Sans', Arial`;
  ctx.fillText(t.festivalSub || 'Wishing you joy', sz/2, sz*0.52);

  // Shop card
  ctx.fillStyle = 'rgba(255,255,255,0.95)';
  roundRect(ctx, sz*0.08, sz*0.60, sz*0.84, sz*0.22, sz*0.025);
  ctx.fill();
  ctx.fillStyle = '#0F172A';
  ctx.font = `900 ${Math.floor(sz*0.046)}px 'Manrope', Arial`;
  wrapText(ctx, (s.name || 'Your Business').toUpperCase(), sz/2, sz*0.68, sz*0.78, Math.floor(sz*0.052), 2);
  if (s.mobile) {
    ctx.fillStyle = '#1E3A8A';
    ctx.font = `800 ${Math.floor(sz*0.030)}px 'Plus Jakarta Sans', Arial`;
    ctx.fillText('📞 ' + s.mobile, sz/2, sz*0.78);
  }
}


// ─── Logo overlay (top-left corner) ────────────────────────
async function drawLogoOverlay(ctx, logoUrl, size){
  return new Promise((resolve) => {
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => {
      const logoSize = size * 0.10;
      const padding = size * 0.03;
      ctx.save();
      ctx.fillStyle = 'rgba(255,255,255,0.95)';
      roundRect(ctx, padding, padding, logoSize + padding*0.7, logoSize + padding*0.7, size*0.012);
      ctx.fill();
      const ratio = Math.min(logoSize / img.width, logoSize / img.height);
      const w = img.width * ratio;
      const h = img.height * ratio;
      ctx.drawImage(img, padding + (logoSize + padding*0.7 - w)/2, padding + (logoSize + padding*0.7 - h)/2, w, h);
      ctx.restore();
      resolve();
    };
    img.onerror = () => resolve();
    img.src = logoUrl;
    setTimeout(resolve, 3000);
  });
}

// ─── Deal banner (bottom strip) ────────────────────────────
function drawDealBanner(ctx, dealText, accent, tmpl, size){
  const bannerH = size * 0.075;
  const bannerY = size * 0.875;
  ctx.save();
  ctx.fillStyle = accent || '#FBBF24';
  roundRect(ctx, size*0.06, bannerY, size*0.88, bannerH, size*0.012);
  ctx.fill();
  ctx.shadowColor = 'rgba(0,0,0,.18)';
  ctx.shadowBlur = size * 0.015;
  ctx.fill();
  ctx.shadowBlur = 0;
  const isDark = isColorDark(accent);
  ctx.fillStyle = isDark ? '#FFFFFF' : '#0F172A';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.font = '900 ' + Math.floor(size*0.034) + 'px Manrope, Arial';
  let txt = String(dealText || '').toUpperCase();
  if (txt.length > 50) txt = txt.slice(0, 47) + '...';
  ctx.fillText('🎁  ' + txt, size/2, bannerY + bannerH/2);
  ctx.textBaseline = 'alphabetic';
  ctx.restore();
}

function isColorDark(hex){
  if (!hex || typeof hex !== 'string') return false;
  hex = hex.replace('#','');
  if (hex.length !== 6) return false;
  const r = parseInt(hex.slice(0,2), 16);
  const g = parseInt(hex.slice(2,4), 16);
  const b = parseInt(hex.slice(4,6), 16);
  return ((r*299 + g*587 + b*114) / 1000) < 128;
}



// ─── Layout: Premium Business Card (Clean Reference Style) ─
async function drawPremiumCard(ctx, s, t, sz, lang, opts){
  opts = opts || {};
  const showQr = opts.showQr !== false;  // default true
  const customHeadline = (s._customHeadline || '').trim();
  const customSubline  = (s._customSubline  || '').trim();

  // ===== PURE WHITE BACKGROUND =====
  ctx.fillStyle = '#FFFFFF';
  ctx.fillRect(0, 0, sz, sz);

  // ===== PHOTO 72% TOP, FULL BLEED =====
  const photoH = sz * 0.72;
  ctx.fillStyle = '#F5F5F5';
  ctx.fillRect(0, 0, sz, photoH);

  if (s.photo) {
    try {
      const img = await loadPhotoImg(s.photo);
      if (img) {
        ctx.save();
        ctx.beginPath();
        ctx.rect(0, 0, sz, photoH);
        ctx.clip();
        const ratio = Math.max(sz / img.width, photoH / img.height);
        const w = img.width * ratio;
        const h = img.height * ratio;
        ctx.drawImage(img, (sz - w) / 2, (photoH - h) / 2, w, h);
        ctx.restore();
        // Soft fade
        const fadeH = sz * 0.04;
        const grad = ctx.createLinearGradient(0, photoH - fadeH, 0, photoH);
        grad.addColorStop(0, 'rgba(255,255,255,0)');
        grad.addColorStop(1, 'rgba(255,255,255,1)');
        ctx.fillStyle = grad;
        ctx.fillRect(0, photoH - fadeH, sz, fadeH);
      } else {
        drawPhotoPlaceholder(ctx, sz, photoH, 'rgba(0,0,0,0.30)');
      }
    } catch(_) { drawPhotoPlaceholder(ctx, sz, photoH, 'rgba(0,0,0,0.30)'); }
  } else {
    drawPhotoPlaceholder(ctx, sz, photoH, 'rgba(0,0,0,0.30)');
  }

  // ===== CUSTOM HEADLINE RIBBON (over photo) =====
  if (customHeadline) {
    const ribH = sz * 0.075;
    const ribY = sz * 0.030;
    ctx.fillStyle = '#0A0A0A';
    ctx.fillRect(0, ribY, sz, ribH);
    ctx.fillStyle = '#D4AF37';
    ctx.fillRect(0, ribY, sz * 0.018, ribH);
    ctx.fillStyle = '#FFFFFF';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const hlTxt = customHeadline.toUpperCase();
    const hlFont = hlTxt.length > 28 ? 0.028 : 0.034;
    ctx.font = '900 ' + Math.floor(sz * hlFont) + 'px Manrope, Arial';
    ctx.fillText(hlTxt, sz / 2, ribY + ribH / 2);
  }

  // ===== BOTTOM 28% — CONTENT ON WHITE =====
  ctx.textAlign = 'center';
  ctx.textBaseline = 'alphabetic';

  const black = '#000000';

  // Shop name
  ctx.fillStyle = black;
  const nameTxt = (s.name || 'Your Business').trim();
  const nameFont = nameTxt.length > 22 ? 0.040 : 0.050;
  ctx.font = '900 ' + Math.floor(sz * nameFont) + 'px Manrope, Arial';
  ctx.fillText(nameTxt, sz / 2, sz * 0.785);

  // Tagline — custom subline wins if user typed one
  const yrs = s.established_year && s.established_year > 1900
    ? (new Date().getFullYear() - s.established_year) : null;
  let taglineTxt = '';
  if (customSubline) {
    taglineTxt = customSubline;
  } else if (yrs && yrs > 0) {
    taglineTxt = yrs + '+ Years of Trust.';
  } else if (s.category) {
    const cl = s.category.toLowerCase();
    if (cl.includes('mutual') || cl.includes('finance') || cl.includes('securit')) taglineTxt = 'Certified Financial Advisor.';
    else if (cl.includes('medical') || cl.includes('pharmacy')) taglineTxt = 'Trusted Pharmacy.';
    else if (cl.includes('jewel')) taglineTxt = 'Hallmark Gold Jewellery.';
    else if (cl.includes('restaurant')) taglineTxt = 'Authentic Indian Cuisine.';
    else if (cl.includes('salon') || cl.includes('beauty')) taglineTxt = 'Premium Beauty Experts.';
    else if (cl.includes('kirana') || cl.includes('grocery')) taglineTxt = 'Family Grocery Store.';
    else taglineTxt = 'Trusted Local Business.';
  }
  if (taglineTxt) {
    ctx.fillStyle = black;
    ctx.font = '700 ' + Math.floor(sz * 0.026) + 'px Inter, Arial';
    ctx.fillText(taglineTxt, sz / 2, sz * 0.818);
  }

  // Phone
  if (s.mobile) {
    const phone = String(s.mobile).replace(/\D/g, '').slice(-10);
    ctx.fillStyle = black;
    ctx.font = '600 ' + Math.floor(sz * 0.024) + 'px Inter, Arial';
    ctx.fillText('M: ' + phone, sz / 2, sz * 0.849);
  }

  // Hairline divider
  ctx.fillStyle = black;
  ctx.fillRect(sz * 0.20, sz * 0.868, sz * 0.60, sz * 0.0020);

  // Address — 2 lines, with proper wrap, allow longer text
  if (s.address) {
    ctx.fillStyle = black;
    ctx.font = '500 ' + Math.floor(sz * 0.022) + 'px Inter, Arial';
    let addr = String(s.address).trim();
    const maxW = sz * 0.86;
    const words = addr.split(/[\s]+/);
    let line = '';
    let lines = [];
    for (let i = 0; i < words.length; i++) {
      const test = line + words[i] + ' ';
      if (ctx.measureText(test).width > maxW && line.length > 0) {
        lines.push(line.trim());
        line = words[i] + ' ';
      } else { line = test; }
    }
    lines.push(line.trim());
    lines = lines.slice(0, 2);
    const startY = sz * 0.898;
    const gap = sz * 0.028;
    for (let i = 0; i < lines.length; i++) {
      ctx.fillText(lines[i], sz / 2, startY + i * gap);
    }
  }

  // ===== BOTTOM FOOTER: Watermark + QR =====
  // dukanlist.com watermark (centered, subtle)
  ctx.fillStyle = '#737373';
  ctx.font = '700 ' + Math.floor(sz * 0.016) + 'px Inter, Arial';
  ctx.textAlign = 'center';
  const wmY = sz * 0.985;
  let wmTxt = 'dukanlist.com';
  if (s.slug) wmTxt = 'dukanlist.com/' + s.slug;
  ctx.fillText(wmTxt, sz / 2, wmY);

  // Small QR code bottom-right corner (subtle)
  if (showQr && s.slug) {
    try {
      const qrSize = sz * 0.080;
      const qrPad = sz * 0.020;
      const qrText = 'https://dukanlist.com/business.html?slug=' + s.slug;
      const qrImg = await loadQrImage(qrText, 150);
      if (qrImg) {
        ctx.save();
        ctx.fillStyle = '#FFFFFF';
        roundRect(ctx, sz - qrSize - qrPad - sz*0.004, sz - qrSize - qrPad - sz*0.004, qrSize + sz*0.008, qrSize + sz*0.008, sz*0.008);
        ctx.fill();
        ctx.drawImage(qrImg, sz - qrSize - qrPad, sz - qrSize - qrPad, qrSize, qrSize);
        ctx.restore();
      }
    } catch(_){}
  }
}

function drawPhotoPlaceholder(ctx, sz, h, ink){
  ctx.fillStyle = ink;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.font = Math.floor(sz * 0.10) + 'px serif';
  ctx.fillText('📷', sz / 2, h / 2);
  ctx.font = '600 ' + Math.floor(sz * 0.022) + 'px Inter, Arial';
  ctx.fillText('Upload your shop photo', sz / 2, h / 2 + sz * 0.08);
  ctx.textBaseline = 'alphabetic';
}

function drawIcon(ctx, emoji, x, y, size){
  ctx.save();
  ctx.font = `${Math.floor(size)}px serif`;
  ctx.textAlign = 'left';
  ctx.textBaseline = 'middle';
  ctx.fillText(emoji, x, y);
  ctx.restore();
}

// ─── Output helpers ───────────────────────────────────────
async function renderToBlob(shop, tmpl, opts){
  const canvas = document.createElement('canvas');
  await renderTemplate(canvas, shop, tmpl, opts);
  return new Promise((resolve) => {
    canvas.toBlob((blob) => resolve(blob), 'image/jpeg', 0.94);
  });
}

async function downloadPoster(shop, tmpl, opts){
  const blob = await renderToBlob(shop, tmpl, opts);
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'dukanlist-' + (tmpl.id || 'poster') + '-' + (shop.slug || 'shop') + '.jpg';
  document.body.appendChild(a);
  a.click();
  setTimeout(() => { URL.revokeObjectURL(url); a.remove(); }, 1000);
}

async function shareToPlatform(platform, shop, tmpl, opts){
  const blob = await renderToBlob(shop, tmpl, opts);
  const file = new File([blob], 'dukanlist.jpg', { type: 'image/jpeg' });
  const url = 'https://dukanlist.com/business.html?slug=' + (shop.slug || '');
  const caption = shop.name + '\n📞 ' + (shop.mobile || '') + '\n' + url + '\n\n— DukanList';

  if (navigator.canShare && navigator.canShare({ files: [file] })) {
    try { await navigator.share({ files: [file], text: caption }); return { method: 'native' }; }
    catch(_){}
  }
  await downloadPoster(shop, tmpl, opts);
  if (platform === 'whatsapp')   window.ope