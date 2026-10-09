/* ============================================================
   image-opt.js — ask the CDN for the size we actually display
   ============================================================
   v281. Every shop photo now lives on Cloudinary (migrated
   2026-09-22), and Cloudinary resizes on the fly for free — but this
   helper only ever knew about Supabase Storage, whose transforms need
   a Pro plan, so it was switched off and handed back the original URL.
   Result: the homepage downloaded 216 KB / 133 KB / 129 KB photos into
   a 364x228 card. Measured on the live page: 15 card images were
   1,350 KB; at w_600 they are 645 KB, at w_400 they are 404 KB.

   So: Cloudinary URLs are now resized (always — no flag), Supabase
   Storage ones keep the old disabled-by-default behaviour.

     DukanImg.opt(url, { width: 600, height: 375, crop: 'fill' })
     DukanImg.card(url)      600x375  — grid cards
     DukanImg.strip(url)     500x312  — hero top-shops strip
     DukanImg.thumb(url)     160x160  — small square thumbnails

   q_auto lets Cloudinary pick the quality, f_auto serves WebP/AVIF to
   browsers that take it. Unknown hosts (or a missing URL) come back
   untouched, so a caller can always pass whatever it has.
   ============================================================ */
(function (global) {
  'use strict';

  function isSupabaseStorage(url) {
    return typeof url === 'string' &&
           url.indexOf('/storage/v1/object/public/') !== -1 &&
           /supabase\.(co|in)/.test(url);
  }

  function isCloudinary(url) {
    return typeof url === 'string' && /res\.cloudinary\.com\/[^/]+\/image\/upload\//.test(url);
  }

  function supportsWebP() {
    if (typeof global.__dlWebPSupport !== 'undefined') return global.__dlWebPSupport;
    try {
      var canvas = document.createElement('canvas');
      canvas.width = canvas.height = 1;
      var support = canvas.toDataURL('image/webp').indexOf('data:image/webp') === 0;
      global.__dlWebPSupport = support;
      return support;
    } catch(_) { return false; }
  }

  // Replace any transformation segment already in the URL rather than
  // chaining onto it: a URL that has been through here once (w_1400…)
  // must not come out as w_1400/w_600.
  function cloudinary(url, o) {
    var t = [];
    if (o.width)  t.push('w_' + o.width);
    if (o.height) t.push('h_' + o.height);
    t.push('c_' + (o.crop || 'limit'));
    t.push('q_' + (o.quality || 'auto'));
    t.push('f_auto');
    var seg = t.join(',');
    // .../upload/<maybe transforms>/v123/folder/name.jpg
    var m = url.match(/^(.*\/image\/upload\/)(?:[^/]*[,_][^/]*\/)?(v\d+\/.+)$/);
    if (m) return m[1] + seg + '/' + m[2];
    // No version segment (rare): insert right after /upload/
    return url.replace('/image/upload/', '/image/upload/' + seg + '/');
  }

  function opt(url, opts) {
    if (!url || typeof url !== 'string') return url;
    opts = opts || {};
    if (isCloudinary(url)) return cloudinary(url, opts);

    // Supabase Storage — unchanged: off unless someone flips the flag.
    if (!global.DukanImg || !global.DukanImg.enableTransform) return url;
    if (!isSupabaseStorage(url)) return url;
    var renderUrl = url.replace('/storage/v1/object/public/', '/storage/v1/render/image/public/');
    var params = [];
    params.push('width=' + (opts.width || 400));
    if (opts.height) params.push('height=' + opts.height);
    params.push('quality=' + (opts.quality || 75));
    params.push('resize=' + (opts.resize || 'cover'));
    if (supportsWebP()) params.push('format=webp');
    var separator = renderUrl.indexOf('?') !== -1 ? '&' : '?';
    return renderUrl + separator + params.join('&');
  }

  global.DukanImg = {
    opt: opt,
    // v325: a phone shows a card ~380 CSS px wide; 600 px was 2.3x the
    // pixels on a 1.5x screen (Lighthouse: 159 KiB over the home page).
    // Phones get 400x250, everything else keeps 600x375.
    card:  function (u) { var ph = (global.innerWidth || 1024) <= 520; return opt(u, { width: ph ? 400 : 600, height: ph ? 250 : 375, crop: 'fill' }); },
    strip: function (u) { return opt(u, { width: 500, height: 312, crop: 'fill' }); },
    thumb: function (u) { return opt(u, { width: 160, height: 160, crop: 'fill' }); },
    // 48 px avatars (Today's Buzz): 96 px is 2x, 160 was 3.3x.
    avatar: function (u) { return opt(u, { width: 96, height: 96, crop: 'fill' }); },
    supportsWebP: supportsWebP,
    enableTransform: false        // Supabase Storage only; Cloudinary ignores it
  };
})(window);

/* v336 — no-photo card face ("Option A"). Mirror of api/_ph.js; keep the
   two in step. DukanImg.ph(name, trade, icon, small) → HTML string that
   fills its box; DukanImg.phFace(...) → { bg, dot, ink, letter, label, emoji }. */
(function (global) {
const RAMPS = [
  // [tint bg, circle fill, text]
  ['#E6F1FB', '#185FA5', '#0C447C'],  // blue
  ['#FAECE7', '#993C1D', '#712B13'],  // coral
  ['#FAEEDA', '#854F0B', '#633806'],  // amber
  ['#E1F5EE', '#0F6E56', '#085041'],  // teal
  ['#EEEDFE', '#534AB7', '#3C3489'],  // purple
  ['#EAF3DE', '#3B6D11', '#27500A'],  // green
  ['#FBEAF0', '#993556', '#72243E'],  // pink
  ['#F1EFE8', '#5F5E5A', '#444441']   // gray
];
const TRADES = [
  [/plumb|नल/i,                   '🔧', 0],
  [/paint|पेंट/i,                 '🖌️', 1],
  [/electric|बिजली/i,             '⚡', 2],
  [/carpent|badhai|बढ़ई/i,         '🪚', 3],
  [/mason|mistri|raj ?mistri|मिस्त्री|construct|builder|thekedar/i, '🧱', 7],
  [/mechanic|garage|auto|tyre|puncture/i, '🛠️', 4],
  [/tailor|darzi|दर्जी|boutique/i, '✂️', 6],
  [/\bac\b|fridge|refrigerat|cooler|repair/i, '❄️', 0],
  [/weld|fabricat/i,              '🔥', 1],
  [/driver|taxi|tempo|transport/i, '🚕', 2],
  [/doctor|clinic|dentist|hospital/i, '🩺', 3],
  [/tuition|coach|teacher|tutor/i, '📚', 4],
  [/photo|studio|video/i,         '📷', 4],
  [/salon|parlour|beauty|barber|mehndi/i, '💇', 6],
  [/cook|halwai|cater|tiffin/i,   '🍳', 2],
  [/labour|helper|majdoor/i,      '👷', 7]
];
function hash(s){ let h = 0; s = String(s || ''); for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0; return h; }
function esc(s){ return String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;'); }

// name: shop name · trade: sub-category / category name · icon: category emoji
function face(name, trade, icon){
  name = String(name || '').trim();
  const paren = (name.match(/\(([^)]+)\)\s*$/) || [])[1] || '';
  const label = String(trade || paren || '').trim();
  const probe = label + ' ' + paren + ' ' + name;
  let emoji = icon || '', ramp = -1;
  for (const t of TRADES){ if (t[0].test(probe)){ if (!icon) emoji = t[1]; ramp = t[2]; break; } }
  if (ramp < 0) ramp = hash(label || name) % RAMPS.length;
  const letter = ((name.replace(/^[^A-Za-zऀ-ॿ]+/, '').match(/[A-Za-zऀ-ॿ]/) || ['•'])[0]).toUpperCase();
  return { bg: RAMPS[ramp][0], dot: RAMPS[ramp][1], ink: RAMPS[ramp][2], letter, label, emoji: emoji || '🏪' };
}

// Full card face, fills whatever box it is put in.
function html(name, trade, icon, small){
  const f = face(name, trade, icon);
  const d = small ? 34 : 56, fs = small ? 15 : 22;
  return '<div style="width:100%;height:100%;background:' + f.bg + ';display:flex;flex-direction:column;align-items:center;justify-content:center;gap:' + (small ? 0 : 7) + 'px">'
    + '<div style="width:' + d + 'px;height:' + d + 'px;border-radius:50%;background:' + f.dot + ';color:' + f.bg + ';display:flex;align-items:center;justify-content:center;font-weight:800;font-size:' + fs + 'px;font-family:inherit">' + esc(f.letter) + '</div>'
    + (small || !f.label ? '' : '<div style="font-size:.78rem;font-weight:700;color:' + f.ink + ';display:flex;align-items:center;gap:5px;max-width:90%;overflow:hidden;white-space:nowrap;text-overflow:ellipsis">' + esc(f.emoji) + ' ' + esc(f.label) + '</div>')
    + '</div>';
}

  if (global.DukanImg){ global.DukanImg.ph = html; global.DukanImg.phFace = face; }
})(typeof window !== 'undefined' ? window : this);
