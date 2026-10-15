/* ============================================================
   parivar-poster.js — "Team" poster of an organisation's office bearers (v392)
   PVP.open(org)  — org = parivar_get_org() result. Draws a 1080×1350 image in the
   browser (logo, name, "पदाधिकारी · सत्र 2026-27", photos/initials, names, posts,
   Dabwali Parivar logo + page link), then offers Share / Download.
   No server work: photos come from Cloudinary with CORS; a photo that can't be
   used is replaced by the person's initials.
   Needs parivar-common.js (PV).
   ============================================================ */
(function(global){
  'use strict';
  var PV = global.PV, esc = PV.esc, bi = PV.bi;
  var W = 1080, H = 1920;   // drawn tall, then cropped to what is used (at least 1350 — WhatsApp status friendly)
  var FONT = '"Noto Sans Devanagari", Manrope, "Segoe UI", sans-serif';

  function loadImg(src){
    return new Promise(function(res){
      if (!src) return res(null);
      var im = new Image(); im.crossOrigin = 'anonymous';
      im.onload = function(){ res(im); }; im.onerror = function(){ res(null); };
      im.src = src;
    });
  }
  function cld(u, w, h, mode){ return /res\.cloudinary\.com\//.test(u || '') ? u.replace('/upload/', '/upload/w_' + w + ',h_' + h + ',' + (mode || 'c_fill,g_face') + ',q_auto,f_png/') : u; }
  function roleHi(r, label){ if (r === 'other' && label) return label; var x = PV.ROLES[r]; return x ? x[1] : (label || r); }
  function roleEn(r, label){ if (r === 'other' && label) return label; var x = PV.ROLES[r]; return x ? x[0] : (label || r); }

  function wrap(ctx, text, maxW, maxLines){
    var words = String(text || '').split(/\s+/), lines = [], cur = '';
    words.forEach(function(w){ var t = cur ? cur + ' ' + w : w; if (ctx.measureText(t).width > maxW && cur){ lines.push(cur); cur = w; } else cur = t; });
    if (cur) lines.push(cur);
    if (lines.length > maxLines){ lines = lines.slice(0, maxLines); var l = lines[maxLines - 1]; while (ctx.measureText(l + '…').width > maxW && l.length) l = l.slice(0, -1); lines[maxLines - 1] = l + '…'; }
    return lines;
  }
  function circleImg(ctx, im, cx, cy, r){
    ctx.save(); ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.closePath(); ctx.clip();
    var s = Math.max(2 * r / im.width, 2 * r / im.height), w = im.width * s, h = im.height * s;
    ctx.drawImage(im, cx - w / 2, cy - h / 2, w, h); ctx.restore();
  }
  function initials(ctx, name, cx, cy, r, i){
    var pal = [['#FFEDD5', '#9A3412'], ['#DBEAFE', '#1E3A8A'], ['#DCFCE7', '#166534'], ['#FCE7F3', '#9D174D'], ['#EDE9FE', '#5B21B6']][i % 5];
    ctx.fillStyle = pal[0]; ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = pal[1]; ctx.font = '800 ' + Math.round(r * 0.75) + 'px ' + FONT; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText(PV.initials(name), cx, cy + 2);
  }

  async function draw(o){
    try { if (document.fonts && document.fonts.load){ await Promise.all([document.fonts.load('800 40px "Noto Sans Devanagari"'), document.fonts.load('700 30px "Noto Sans Devanagari"')]); } } catch(_){}
    var people = (o.bearers || []).slice(0, 12);
    var cv = document.createElement('canvas'); cv.width = W; cv.height = H; var ctx = cv.getContext('2d');
    // background
    var g = ctx.createLinearGradient(0, 0, 0, H); g.addColorStop(0, '#FFF7ED'); g.addColorStop(1, '#FFFFFF');
    ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
    ctx.fillStyle = 'rgba(234,88,12,.07)'; for (var y = 18; y < H; y += 30) for (var x = 18; x < W; x += 30){ ctx.beginPath(); ctx.arc(x, y, 2, 0, Math.PI * 2); ctx.fill(); }
    var band = ctx.createLinearGradient(0, 0, W, 0); band.addColorStop(0, '#1E3A8A'); band.addColorStop(1, '#EA580C');
    ctx.fillStyle = band; ctx.fillRect(0, 0, W, 14);

    var imgs = await Promise.all([loadImg(o.logo ? cld(o.logo, 320, 320, 'c_pad,b_white') : null), loadImg('/assets/brand/dabwali-parivar-560.webp')]
      .concat(people.map(function(p){ return loadImg(p.photo ? cld(p.photo, 360, 360) : null); })));
    var logo = imgs[0], brand = imgs[1], faces = imgs.slice(2);

    // header: logo + name + session
    var top = 60;
    if (logo){ ctx.save(); ctx.fillStyle = '#fff'; ctx.shadowColor = 'rgba(15,23,42,.15)'; ctx.shadowBlur = 18; ctx.beginPath(); ctx.arc(W / 2, top + 80, 84, 0, Math.PI * 2); ctx.fill(); ctx.restore(); circleImg(ctx, logo, W / 2, top + 80, 76); top += 180; }
    ctx.textAlign = 'center'; ctx.textBaseline = 'alphabetic'; ctx.fillStyle = '#0F172A'; ctx.font = '800 58px ' + FONT;
    var nameLines = wrap(ctx, o.name_hi || o.name, W - 140, 2);
    nameLines.forEach(function(l, i){ ctx.fillText(l, W / 2, top + 60 + i * 66); });
    top += 60 + (nameLines.length - 1) * 66;
    if (o.name_hi && o.name){ ctx.fillStyle = '#475569'; ctx.font = '700 30px ' + FONT; ctx.fillText(o.name, W / 2, top + 46); top += 46; }
    ctx.fillStyle = '#EA580C'; ctx.font = '800 38px ' + FONT; ctx.fillText('पदाधिकारी · सत्र ' + (o.session || ''), W / 2, top + 62); top += 62;
    ctx.fillStyle = '#FDBA74'; ctx.fillRect(W / 2 - 90, top + 22, 180, 5); top += 50;

    // grid
    // every cell has room for the photo, the post and a two-line name — the poster grows instead of overlapping
    var n = people.length, cols = n <= 2 ? n : (n === 4 ? 2 : (n <= 9 ? 3 : 4)), rows = Math.ceil(n / cols);
    var r = cols <= 2 ? 120 : (cols === 3 ? 92 : 74), cellH = 2 * r + 200, areaTop = top + 10, cellW = (W - 80) / cols;
    people.forEach(function(p, i){
      var row = Math.floor(i / cols), col = i % cols, inRow = Math.min(cols, n - row * cols);
      var offset = (cols - inRow) * cellW / 2;
      var cx = 40 + offset + cellW * col + cellW / 2, cy = areaTop + row * cellH + r + 8;
      ctx.save(); ctx.fillStyle = '#fff'; ctx.shadowColor = 'rgba(15,23,42,.18)'; ctx.shadowBlur = 16; ctx.beginPath(); ctx.arc(cx, cy, r + 7, 0, Math.PI * 2); ctx.fill(); ctx.restore();
      ctx.strokeStyle = i % 2 ? '#1E3A8A' : '#EA580C'; ctx.lineWidth = 5; ctx.beginPath(); ctx.arc(cx, cy, r + 4, 0, Math.PI * 2); ctx.stroke();
      if (faces[i]) circleImg(ctx, faces[i], cx, cy, r); else initials(ctx, p.name, cx, cy, r, i);
      ctx.textAlign = 'center'; ctx.textBaseline = 'alphabetic';
      var fs = cols <= 2 ? 34 : (cols === 3 ? 28 : 24);
      ctx.fillStyle = '#EA580C'; ctx.font = '800 ' + fs + 'px ' + FONT;
      ctx.fillText(roleHi(p.role, p.role_label), cx, cy + r + 46);
      ctx.fillStyle = '#0F172A'; ctx.font = '800 ' + (fs + 2) + 'px ' + FONT;
      wrap(ctx, p.name, cellW - 20, 2).forEach(function(l, k){ ctx.fillText(l, cx, cy + r + 46 + (fs + 10) + k * (fs + 8)); });
    });
    var gridEnd = areaTop + rows * cellH;

    // footer, then crop the canvas to the height used
    var bw = 300, bh = brand ? brand.height * bw / brand.width : 0;
    var finalH = Math.min(H, Math.max(1350, gridEnd + 40 + bh + 90));
    var fy = finalH - 60;
    if (brand) ctx.drawImage(brand, W / 2 - bw / 2, fy - 28 - bh, bw, bh);
    ctx.fillStyle = '#334155'; ctx.font = '700 26px ' + FONT; ctx.textAlign = 'center';
    ctx.fillText('dukanlist.com/sanstha/' + (o.slug || ''), W / 2, fy);
    var out = document.createElement('canvas'); out.width = W; out.height = finalH;
    var oc = out.getContext('2d'); oc.drawImage(cv, 0, 0);
    var band2 = oc.createLinearGradient(0, 0, W, 0); band2.addColorStop(0, '#1E3A8A'); band2.addColorStop(1, '#EA580C');
    oc.fillStyle = band2; oc.fillRect(0, finalH - 14, W, 14);
    return out;
  }

  function modal(html){
    var bg = document.createElement('div'); bg.className = 'pvp-bg';
    bg.style.cssText = 'position:fixed;inset:0;background:rgba(15,23,42,.72);z-index:9999;display:flex;align-items:center;justify-content:center;padding:14px';
    bg.innerHTML = '<div style="background:#fff;border-radius:18px;max-width:440px;width:100%;max-height:94vh;overflow:auto;padding:14px;position:relative">' + html + '</div>';
    bg.addEventListener('click', function(e){ if (e.target === bg) bg.remove(); });
    document.body.appendChild(bg); return bg;
  }

  async function open(o){
    if (!(o.bearers || []).length){ alert('No office bearers yet.'); return; }
    var bg = modal('<div style="text-align:center;padding:30px 10px">⏳ ' + bi('Making the poster…', 'पोस्टर बन रहा है…') + '</div>');
    var cv;
    try { cv = await draw(o); } catch(e){ bg.remove(); alert('Could not make the poster — please try again.'); return; }
    cv.toBlob(function(blob){
      if (!blob){ bg.remove(); alert('Could not make the poster — please try again.'); return; }
      var url = URL.createObjectURL(blob), fname = (o.slug || 'team') + '-team-' + String(o.session || '').replace(/[^0-9-]/g, '') + '.png';
      var file = null; try { file = new File([blob], fname, { type: 'image/png' }); } catch(_){}
      var canShare = !!(file && navigator.canShare && navigator.canShare({ files: [file] }));
      bg.firstChild.innerHTML = '<button type="button" class="pvp-x" style="position:absolute;top:8px;right:8px;width:36px;height:36px;border-radius:50%;border:0;background:rgba(15,23,42,.75);color:#fff;font-size:1.2rem;cursor:pointer">×</button>'
        + '<b style="display:block;margin:2px 40px 8px 2px">📸 ' + bi('Team poster', 'टीम पोस्टर') + ' ' + esc(o.session || '') + '</b>'
        + '<img src="' + url + '" alt="" style="width:100%;border-radius:12px;border:1px solid #E2E8F0;display:block">'
        + '<div style="display:flex;gap:8px;margin-top:10px">'
        + (canShare ? '<button type="button" class="pvp-share" style="flex:1;padding:11px;border-radius:11px;border:0;background:#25D366;color:#fff;font-weight:800;cursor:pointer;font-family:inherit">💬 ' + bi('Share', 'शेयर करें') + '</button>' : '')
        + '<a href="' + url + '" download="' + esc(fname) + '" style="flex:1;padding:11px;border-radius:11px;background:#0F172A;color:#fff;font-weight:800;text-align:center;text-decoration:none">⬇ ' + bi('Download', 'डाउनलोड करें') + '</a></div>'
        + '<div style="font-size:.78rem;color:#64748B;margin-top:8px">' + bi('Put it on WhatsApp status or in your group.', 'इसे WhatsApp स्टेटस या ग्रुप में लगाइए।') + '</div>';
      bg.querySelector('.pvp-x').onclick = function(){ bg.remove(); };
      var sh = bg.querySelector('.pvp-share');
      if (sh) sh.onclick = function(){ navigator.share({ files: [file], title: o.name, text: (o.name_hi || o.name) + ' — पदाधिकारी ' + (o.session || '') + '\n' + location.origin + '/sanstha/' + o.slug }).catch(function(){}); };
    }, 'image/png');
  }

  global.PVP = { open: open, draw: draw };
})(window);
