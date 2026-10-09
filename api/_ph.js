// =====================================================
// api/_ph.js — the no-photo card face (v336, "Option A")
// Shared by the browser (assets/js/image-opt.js mirrors this) and the
// server-rendered pages (api/locality.js, api/area.js). Underscore prefix:
// Vercel does not expose it as a function.
//
// A plumber has no shopfront to photograph, and a grey store icon made his
// card look abandoned. Instead: a flat tint chosen by the trade, a circle
// with the first letter of the name, and the trade written underneath.
// Same trade → same colour across the site; different names → different
// letters, so a row of plumbers does not look like one card repeated.
// =====================================================
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

module.exports = { face, html };
