#!/usr/bin/env python3
"""
Premium Play Store screenshot renderer for DukanList.

Layout per screenshot (1080×1920):
  • Cream gradient background (#FFFBF5 → #FFE4B5 subtle)
  • Top caption block (450px) — English headline + Hindi sub-head
    — proper text-wrapping, auto-fit, NO overflow
  • Phone mockup (centered, ~620px wide × ~1280px tall)
    — drop shadow underneath for depth
    — subtle device-frame border in dark navy
  • Small DukanList wordmark at bottom

All rendering happens in the user's browser (Chrome/Edge) where Google
Fonts work — so Hindi prints correctly.

Run:    python3 marketing/play-store/build-renderer.py
Output: marketing/play-store/render-screenshots.html
"""

import base64
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw"
OUT = ROOT / "render-screenshots.html"

CAPTIONS = {
    1: ("Every shop in your town",          "हर दुकान आपके फ़ोन पर"),
    2: ("Browse 370+ categories",           "370+ श्रेणियाँ खोजें"),
    3: ("Call, WhatsApp, Maps in one tap",  "एक टैप पर कॉल, WhatsApp, नक्शा"),
    4: ("Real reviews from real customers", "असली ग्राहकों की सच्ची राय"),
    5: ("Find them on Google Maps",         "Google Maps पर सीधा रास्ता"),
    6: ("Ask your neighbourhood anything",  "अपने मोहल्ले से पूछिए"),
    7: ("List your shop free, forever",     "अपनी दुकान मुफ़्त में रजिस्टर करें"),
    8: ("Works in English and Hindi",       "अंग्रेज़ी और हिंदी, दोनों में"),
}


def b64_image(num):
    p = RAW / f"screen-{num}.jpg"
    if not p.exists():
        return ""
    return base64.b64encode(p.read_bytes()).decode()


def main():
    imgs_js = "{\n"
    for n in range(1, 9):
        en, hi = CAPTIONS[n]
        b64 = b64_image(n)
        en_safe = en.replace("\\", "\\\\").replace("'", "\\'")
        hi_safe = hi.replace("\\", "\\\\").replace("'", "\\'")
        imgs_js += f"  {n}: {{ en: '{en_safe}', hi: '{hi_safe}', b64: '{b64}' }},\n"
    imgs_js += "}"

    html = HTML_TEMPLATE.replace("__IMGS__", imgs_js)
    OUT.write_text(html, encoding="utf-8")
    size_kb = OUT.stat().st_size // 1024
    print(f"✓ wrote {OUT} ({size_kb} KB)")
    print(f"  Open in your browser, click 'Download all 8', done.")


HTML_TEMPLATE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>DukanList — Premium screenshot renderer</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@500;700;800;900&family=Noto+Sans+Devanagari:wght@500;700&display=swap" rel="stylesheet">
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:'Manrope','Inter',sans-serif;background:#F8FAFC;color:#0F172A;padding:24px;min-height:100vh}
  .wrap{max-width:1400px;margin:0 auto}
  h1{font-weight:900;font-size:1.8rem;margin-bottom:6px;letter-spacing:-.02em}
  .lede{color:#64748B;margin-bottom:18px;font-size:.95rem}

  .toolbar{background:#fff;border:1.5px solid #E2E8F0;border-radius:14px;padding:20px;margin-bottom:20px;display:flex;gap:12px;align-items:center;flex-wrap:wrap;box-shadow:0 4px 16px rgba(15,23,42,.04)}

  .btn{background:linear-gradient(135deg,#D97706,#92400E);color:#fff;border:0;padding:12px 22px;border-radius:10px;font-weight:800;font-size:.95rem;cursor:pointer;font-family:inherit}
  .btn:hover{filter:brightness(1.07)}
  .btn-big{padding:14px 28px;font-size:1.05rem;background:linear-gradient(135deg,#FF6B1A,#D97706);box-shadow:0 8px 24px rgba(255,107,26,.3)}

  .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:20px}
  .card{background:#fff;border:1.5px solid #E2E8F0;border-radius:14px;padding:16px;box-shadow:0 4px 16px rgba(15,23,42,.04);text-align:center}
  .card h3{font-weight:800;font-size:.95rem;margin-bottom:6px;color:#0F172A}
  .card .hi{color:#92400E;font-family:'Noto Sans Devanagari',sans-serif;font-size:.8rem;margin-bottom:12px}
  .card canvas{width:100%;height:auto;border-radius:8px;box-shadow:0 4px 12px rgba(15,23,42,.15);margin-bottom:10px}
  .card button{width:100%}

  .status{padding:8px 12px;border-radius:8px;background:#FEF3C7;color:#78350F;font-size:.88rem;font-weight:700}
  .status.ok{background:#D1FAE5;color:#065F46}

  .toast{position:fixed;top:20px;right:20px;background:#10B981;color:#fff;padding:14px 22px;border-radius:10px;font-weight:800;box-shadow:0 12px 32px rgba(16,185,129,.4);transform:translateY(-100px);transition:.3s;z-index:9999}
  .toast.show{transform:translateY(0)}
</style>
</head>
<body>

<div class="toast" id="toast">Saved!</div>

<div class="wrap">

  <h1>DukanList — Premium Screenshot Renderer</h1>
  <p class="lede">Clean cream background, centered phone mockup with shadow, bilingual headline above. 1080×1920 PNG output, ready for Play Store upload.</p>

  <div class="toolbar">
    <div class="status" id="loadStatus">Loading fonts and images…</div>
    <button class="btn btn-big" id="downloadAll" disabled>⬇ Download all 8 PNGs</button>
    <span style="color:#64748B;font-size:.88rem">or download each individually below ↓</span>
  </div>

  <div class="grid" id="grid"></div>

</div>

<script>
const IMGS = __IMGS__;

const CANVAS_W = 1080;
const CANVAS_H = 1920;

// Background colours
const BG_TOP = '#FFFBF5';
const BG_BOT = '#FFE4B5';
const INK = '#0F172A';
const SAFFRON = '#FF6B1A';
const DEEP_SAFFRON = '#D97706';
const DARK_SAFFRON = '#92400E';
const PHONE_FRAME = '#0F172A';

// Layout zones
const TOP_PAD = 80;
const CAPTION_TOP = 90;
const CAPTION_HEIGHT_MAX = 280;
const PHONE_TOP_PAD = 60;
const WORDMARK_BOTTOM = 70;

const grid = document.getElementById('grid');
const loadStatus = document.getElementById('loadStatus');
const downloadAllBtn = document.getElementById('downloadAll');
const toast = document.getElementById('toast');

document.fonts.ready.then(() => {
  loadStatus.textContent = 'Fonts loaded, rendering all 8 screenshots…';
  loadStatus.classList.add('ok');
  renderAll();
});

async function renderAll(){
  const canvases = [];
  for (let n = 1; n <= 8; n++){
    const c = await renderOne(n);
    canvases.push({ n, canvas: c });
  }
  loadStatus.textContent = '✓ All 8 rendered. Click "Download all" or each Download button.';
  downloadAllBtn.disabled = false;
  downloadAllBtn.addEventListener('click', async () => {
    for (const item of canvases){
      downloadCanvas(item.canvas, `dukanlist-screenshot-${item.n}.png`);
      await new Promise(r => setTimeout(r, 350));
    }
    showToast('Saved 8 PNGs to your Downloads folder');
  });
}

function renderOne(n){
  return new Promise(resolve => {
    const data = IMGS[n];
    const img = new Image();
    img.onload = () => {
      const canvas = document.createElement('canvas');
      canvas.width = CANVAS_W; canvas.height = CANVAS_H;
      const ctx = canvas.getContext('2d');

      // ── 1. Cream gradient background
      const grad = ctx.createLinearGradient(0, 0, 0, CANVAS_H);
      grad.addColorStop(0, BG_TOP);
      grad.addColorStop(1, BG_BOT);
      ctx.fillStyle = grad;
      ctx.fillRect(0, 0, CANVAS_W, CANVAS_H);

      // ── 2. Caption block (top)
      drawCaption(ctx, data.en, data.hi);

      // ── 3. Phone mockup centered with shadow
      drawPhoneMockup(ctx, img);

      // ── 4. DukanList wordmark at bottom
      drawWordmark(ctx);

      addToGrid(n, data, canvas);
      resolve(canvas);
    };
    img.src = 'data:image/jpeg;base64,' + data.b64;
  });
}

function drawCaption(ctx, en, hi){
  const yStart = CAPTION_TOP + 80;  // baseline for English

  // ── English headline
  // Dynamic sizing — start at 76px, shrink if too wide
  let enSize = 76;
  ctx.font = `900 ${enSize}px "Manrope", sans-serif`;
  while (ctx.measureText(en).width > CANVAS_W - 120 && enSize > 50){
    enSize -= 2;
    ctx.font = `900 ${enSize}px "Manrope", sans-serif`;
  }
  // If still too wide → wrap to 2 lines
  if (ctx.measureText(en).width > CANVAS_W - 120){
    // Find natural break point
    const words = en.split(' ');
    const half = Math.ceil(words.length / 2);
    const line1 = words.slice(0, half).join(' ');
    const line2 = words.slice(half).join(' ');
    enSize = 64;
    ctx.font = `900 ${enSize}px "Manrope", sans-serif`;
    ctx.fillStyle = INK;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(line1, CANVAS_W / 2, yStart - 38);
    ctx.fillText(line2, CANVAS_W / 2, yStart + 38);
  } else {
    ctx.fillStyle = INK;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(en, CANVAS_W / 2, yStart);
  }

  // ── Hindi sub-head (below English)
  let hiSize = 44;
  ctx.font = `500 ${hiSize}px "Noto Sans Devanagari", sans-serif`;
  while (ctx.measureText(hi).width > CANVAS_W - 140 && hiSize > 32){
    hiSize -= 2;
    ctx.font = `500 ${hiSize}px "Noto Sans Devanagari", sans-serif`;
  }
  ctx.fillStyle = DARK_SAFFRON;
  ctx.fillText(hi, CANVAS_W / 2, yStart + 90);

  // ── Small accent line under captions
  ctx.fillStyle = SAFFRON;
  const lineW = 80, lineH = 5;
  ctx.fillRect((CANVAS_W - lineW) / 2, yStart + 145, lineW, lineH);
}

function drawPhoneMockup(ctx, img){
  // Phone canvas takes ~620px wide × keeping 9:19.5 ratio = 1300 tall
  const phoneW = 620;
   const phoneH = 1340;
  const phoneX = (CANVAS_W - phoneW) / 2;
  const phoneY = CAPTION_TOP + CAPTION_HEIGHT_MAX + 60;

  ctx.shadowColor = 'rgba(15, 23, 42, 0.25)';
  ctx.shadowBlur = 40;
  ctx.shadowOffsetY = 16;

  const radius = 56;
  ctx.fillStyle = PHONE_FRAME;
  roundRect(ctx, phoneX, phoneY, phoneW, phoneH, radius);
  ctx.fill();

  ctx.shadowColor = 'transparent';
  ctx.shadowBlur = 0;
  ctx.shadowOffsetY = 0;

  const screenPad = 16;
  const screenX = phoneX + screenPad;
  const screenY = phoneY + screenPad;
  const screenW = phoneW - 2 * screenPad;
  const screenH = phoneH - 2 * screenPad;
  const screenRadius = radius - 12;

  ctx.save();
  roundRect(ctx, screenX, screenY, screenW, screenH, screenRadius);
  ctx.clip();

  const scale = screenW / img.width;
  const drawH = img.height * scale;
  ctx.drawImage(img, screenX, screenY, screenW, drawH);

  ctx.restore();
}

function drawWordmark(ctx){
  const y = CANVAS_H - WORDMARK_BOTTOM;
  ctx.fillStyle = SAFFRON;
  ctx.beginPath();
  ctx.arc(CANVAS_W / 2 - 130, y, 8, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = INK;
  ctx.font = '800 38px "Manrope", sans-serif';
  ctx.textAlign = 'left';
  ctx.textBaseline = 'middle';
  ctx.fillText('Dukan', CANVAS_W / 2 - 110, y);
  ctx.fillStyle = SAFFRON;
  ctx.font = '800 38px "Manrope", sans-serif';
  const dukanWidth = ctx.measureText('Dukan').width;
  ctx.fillText('List', CANVAS_W / 2 - 110 + dukanWidth, y);
}

function roundRect(ctx, x, y, w, h, r){
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

function addToGrid(n, data, srcCanvas){
  const card = document.createElement('div');
  card.className = 'card';
  card.innerHTML = '<h3>Frame ' + n + ' &mdash; ' + data.en + '</h3><div class="hi">' + data.hi + '</div>';
  const preview = document.createElement('canvas');
  preview.width = srcCanvas.width;
  preview.height = srcCanvas.height;
  preview.getContext('2d').drawImage(srcCanvas, 0, 0);
  card.appendChild(preview);
  const btn = document.createElement('button');
  btn.className = 'btn';
  btn.textContent = 'Download screenshot-' + n + '.png';
  btn.onclick = function(){
    downloadCanvas(srcCanvas, 'dukanlist-screenshot-' + n + '.png');
    showToast('Saved screenshot-' + n + '.png');
  };
  card.appendChild(btn);
  grid.appendChild(card);
}

function downloadCanvas(canvas, name){
  canvas.toBlob(function(blob){
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = name;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(function(){ URL.revokeObjectURL(url); }, 1000);
  }, 'image/png');
}

function showToast(msg){
  toast.textContent = msg;
  toast.classList.add('show');
  clearTimeout(toast._t);
  toast._t = setTimeout(function(){ toast.classList.remove('show'); }, 2200);
}
</script>

</body>
</html>
"""


if __name__ == "__main__":
    main()
.createElement('a');
    a.href = url;
    a.download = name;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }, 'image/png');
}

function showToast(msg){
  toast.textContent = msg;
  toast.classList.add('show');
  clearTimeout(toast._t);
  toast._t = setTimeout(() => toast.classList.remove('show'), 2200);
}
</script>

</body>
</html>
"""


if __name__ == "__main__":
    main()
