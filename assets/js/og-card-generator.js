/* =====================================================
 * og-card-generator.js
 * Client-side HTML5 Canvas generator for shop-branded
 * WhatsApp / Facebook / Twitter share cards.
 *
 * 1200×630 PNG — standard Open Graph dimensions.
 * Layout: HUGE shop name (the hero), category icon top-left,
 * ⭐ rating + reviews, 📍 city/locality, 📞 mobile (BIG and orange),
 * 👤 owner name, italic USP, and a tiny dukanlist.com footer
 * (~5% area). DukanList is subtle; shop is the star.
 *
 * Usage:
 *   const blob = await OGCard.generate({
 *     name: 'Sharma Medical Store',
 *     ownerName: 'Suresh Sharma',
 *     mobile: '9876543210',
 *     city: 'Mandi Dabwali',
 *     locality: 'Chotala Road',
 *     ratingAvg: 4.7,
 *     ratingCount: 23,
 *     categoryIcon: '💊',
 *     categoryName: 'Medical Store',
 *     uspText: '24x7 emergency open, home delivery available'
 *   });
 *   // upload `blob` to Supabase Storage 'business-og' bucket
 *
 * NO dependencies. Pure browser Canvas API.
 * ===================================================== */

(function (root) {
  'use strict';

  // ---- Brand palette ----
  var COLORS = {
    bgTop:        '#FFF7ED',  // warm cream
    bgBottom:     '#FFFFFF',
    accent:       '#FF6B1A',  // DukanList saffron — used SPARINGLY
    accentDark:   '#C2410C',
    ink:          '#0F172A',  // navy — shop name
    inkSoft:      '#334155',
    inkMuted:     '#64748B',
    line:         '#E2E8F0',
    gold:         '#F59E0B',  // star fill
    success:      '#16A34A',
    bgPattern:    '#FED7AA'   // dotted texture top-right
  };

  var W = 1200, H = 630;

  /* -------- helpers -------- */
  function wrapText(ctx, text, maxWidth) {
    text = String(text || '').replace(/\s+/g, ' ').trim();
    if (!text) return [];
    var words = text.split(' ');
    var lines = [];
    var cur = '';
    for (var i = 0; i < words.length; i++) {
      var test = cur ? cur + ' ' + words[i] : words[i];
      if (ctx.measureText(test).width > maxWidth && cur) {
        lines.push(cur);
        cur = words[i];
      } else {
        cur = test;
      }
    }
    if (cur) lines.push(cur);
    return lines;
  }

  function fitShopName(ctx, name, maxWidth, maxLines) {
    // Pick the largest font size where the name fits in `maxLines` lines.
    var sizes = [96, 88, 80, 72, 64, 56];
    for (var i = 0; i < sizes.length; i++) {
      ctx.font = '900 ' + sizes[i] + 'px Manrope, "Plus Jakarta Sans", system-ui, sans-serif';
      var lines = wrapText(ctx, name, maxWidth);
      if (lines.length <= maxLines) return { size: sizes[i], lines: lines };
    }
    // Last resort
    ctx.font = '900 48px Manrope, system-ui, sans-serif';
    return { size: 48, lines: wrapText(ctx, name, maxWidth).slice(0, maxLines) };
  }

  function roundRect(ctx, x, y, w, h, r) {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y,     x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x,     y + h, r);
    ctx.arcTo(x,     y + h, x,     y,     r);
    ctx.arcTo(x,     y,     x + w, y,     r);
    ctx.closePath();
  }

  function drawTopBar(ctx, categoryIcon, categoryName) {
    // A thin saffron strip at the very top (subtle brand presence)
    ctx.fillStyle = COLORS.accent;
    ctx.fillRect(0, 0, W, 6);

    // Category badge — top left
    var bx = 50, by = 36, bh = 50;
    ctx.font = '700 24px Manrope, system-ui, sans-serif';
    var labelText = (categoryIcon || '🏪') + '   ' + (categoryName || 'Local Shop');
    var labelW = ctx.measureText(labelText).width + 36;
    ctx.fillStyle = '#FFEDD5';
    roundRect(ctx, bx, by, labelW, bh, 25);
    ctx.fill();
    ctx.fillStyle = COLORS.accentDark;
    ctx.textBaseline = 'middle';
    ctx.fillText(labelText, bx + 18, by + bh / 2);
  }

  function drawShopName(ctx, name) {
    var maxWidth = W - 100; // 50px padding each side
    var fit = fitShopName(ctx, name, maxWidth, 2);

    ctx.font = '900 ' + fit.size + 'px Manrope, "Plus Jakarta Sans", system-ui, sans-serif';
    ctx.fillStyle = COLORS.ink;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'alphabetic';

    var lineGap = fit.size * 1.05;
    var totalH = lineGap * fit.lines.length;
    var startY = 180 + (totalH < 220 ? (220 - totalH) / 2 : 0);

    for (var i = 0; i < fit.lines.length; i++) {
      ctx.fillText(fit.lines[i], W / 2, startY + i * lineGap);
    }

    return startY + totalH; // bottom Y of the name block
  }

  function drawStars(ctx, ratingAvg, ratingCount, cx, cy) {
    var hasRating = ratingCount && ratingCount > 0 && ratingAvg > 0;
    var avg = hasRating ? Math.max(0, Math.min(5, ratingAvg || 0)) : 0;

    var starSize = 28;
    var starGap = 6;
    var labelText = hasRating
      ? ' ' + avg.toFixed(1) + '  (' + ratingCount + ' review' + (ratingCount === 1 ? '' : 's') + ')'
      : '  Be the first to review';

    ctx.font = '700 22px Manrope, system-ui, sans-serif';
    var labelW = ctx.measureText(labelText).width;
    var totalW = (starSize * 5) + (starGap * 4) + labelW;
    var x = cx - totalW / 2;
    var y = cy;

    // 5 stars — outline-only if no rating
    for (var i = 0; i < 5; i++) {
      var filled = hasRating && i < Math.round(avg);
      drawStar(ctx, x + i * (starSize + starGap) + starSize / 2, y, starSize / 2,
        filled ? COLORS.gold : '#E2E8F0');
    }

    ctx.fillStyle = hasRating ? COLORS.inkSoft : COLORS.inkMuted;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    ctx.fillText(labelText, x + (starSize * 5) + (starGap * 4), y);
  }

  function drawStar(ctx, cx, cy, r, fill) {
    var spikes = 5;
    var step = Math.PI / spikes;
    var inner = r * 0.45;
    ctx.beginPath();
    ctx.moveTo(cx, cy - r);
    var rot = -Math.PI / 2;
    for (var i = 0; i < spikes; i++) {
      ctx.lineTo(cx + Math.cos(rot) * r, cy + Math.sin(rot) * r);
      rot += step;
      ctx.lineTo(cx + Math.cos(rot) * inner, cy + Math.sin(rot) * inner);
      rot += step;
    }
    ctx.lineTo(cx, cy - r);
    ctx.closePath();
    ctx.fillStyle = fill;
    ctx.fill();
  }

  function drawLocation(ctx, city, locality, y) {
    var parts = [];
    if (locality) parts.push(locality);
    if (city)     parts.push(city);
    if (!parts.length) return;
    var text = '📍  ' + parts.join(', ');

    ctx.font = '600 26px Manrope, system-ui, sans-serif';
    ctx.fillStyle = COLORS.inkSoft;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'alphabetic';
    ctx.fillText(text, W / 2, y);
  }

  function drawMobile(ctx, mobile, y) {
    if (!mobile) return;
    var formatted = mobile;
    // Format 10-digit as XXXXX-XXXXX for readability
    var digits = String(mobile).replace(/\D/g, '').slice(-10);
    if (digits.length === 10) {
      formatted = digits.slice(0, 5) + ' ' + digits.slice(5);
    }
    var text = '📞  +91  ' + formatted;

    ctx.font = '900 44px Manrope, system-ui, sans-serif';
    var tw = ctx.measureText(text).width;
    var padX = 30, padY = 18, bh = 70;
    var bw = tw + padX * 2;
    var bx = (W - bw) / 2;
    var by = y - bh / 2;

    // Pill background — accent on white
    ctx.fillStyle = COLORS.accent;
    roundRect(ctx, bx, by, bw, bh, bh / 2);
    ctx.fill();

    ctx.fillStyle = '#FFFFFF';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(text, W / 2, y);
  }

  function drawOwner(ctx, ownerName, y) {
    if (!ownerName) return;
    var text = '👤  ' + ownerName + ' — Owner';
    ctx.font = '500 22px Manrope, system-ui, sans-serif';
    ctx.fillStyle = COLORS.inkMuted;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'alphabetic';
    ctx.fillText(text, W / 2, y);
  }

  function drawUsp(ctx, uspText, y) {
    if (!uspText) return y;
    var maxWidth = W - 160;
    ctx.font = 'italic 500 22px Manrope, Georgia, serif';
    var lines = wrapText(ctx, uspText, maxWidth).slice(0, 2);
    if (!lines.length) return y;

    // Left + right quote marks for premium feel
    var lineH = 30;
    var totalH = lines.length * lineH;
    var startY = y;

    ctx.fillStyle = COLORS.inkMuted;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'alphabetic';
    for (var i = 0; i < lines.length; i++) {
      var t = (i === 0 ? '“' : '') + lines[i] + (i === lines.length - 1 ? '”' : '');
      ctx.fillText(t, W / 2, startY + i * lineH);
    }
    return startY + totalH;
  }

  function drawFooter(ctx) {
    // VERY subtle — just a 30px strip at the bottom
    var stripH = 38;
    var y = H - stripH;

    // Thin saffron underline above the strip
    ctx.fillStyle = COLORS.accent;
    ctx.fillRect(0, y - 2, W, 2);

    // Text: "Listed on dukanlist.com · Free Local Directory"
    ctx.font = '600 16px Manrope, system-ui, sans-serif';
    ctx.fillStyle = COLORS.inkMuted;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(
      'Listed on dukanlist.com  ·  Bharat ka local shop directory',
      W / 2,
      y + stripH / 2
    );
  }

  function drawBackground(ctx) {
    // Vertical gradient — warm cream → white
    var grad = ctx.createLinearGradient(0, 0, 0, H);
    grad.addColorStop(0,   COLORS.bgTop);
    grad.addColorStop(0.45, '#FFFDF7');
    grad.addColorStop(1,   COLORS.bgBottom);
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, W, H);

    // Dotted pattern top-right (very subtle — texture only)
    ctx.fillStyle = COLORS.bgPattern;
    ctx.globalAlpha = 0.45;
    for (var y = 30; y < 180; y += 22) {
      for (var x = 800; x < W - 20; x += 22) {
        ctx.beginPath();
        ctx.arc(x, y, 2, 0, Math.PI * 2);
        ctx.fill();
      }
    }
    ctx.globalAlpha = 1;
  }

  /* ================================================
   * PUBLIC API
   * ================================================ */
  function generate(opts) {
    return new Promise(function (resolve, reject) {
      try {
        var c = document.createElement('canvas');
        c.width = W; c.height = H;
        var ctx = c.getContext('2d');

        drawBackground(ctx);
        drawTopBar(ctx, opts.categoryIcon, opts.categoryName);

        // Shop name — the HERO
        var nameBottom = drawShopName(ctx, opts.name || 'Local Shop');

        // Rating row — ALWAYS rendered. drawStars handles 0-review case
        // with outline stars + "Be the first to review" label.
        var cursorY = nameBottom + 30;
        drawStars(ctx, opts.ratingAvg, opts.ratingCount, W / 2, cursorY);
        cursorY += 50;

        // City + locality
        drawLocation(ctx, opts.city, opts.locality, cursorY + 20);
        cursorY += 40;

        // Mobile pill (big, orange — most actionable)
        cursorY += 50;
        drawMobile(ctx, opts.mobile, cursorY);

        // Owner name
        cursorY += 60;
        drawOwner(ctx, opts.ownerName, cursorY);

        // USP (italic)
        cursorY += 30;
        drawUsp(ctx, opts.uspText, cursorY);

        // Footer strip with subtle DukanList mention
        drawFooter(ctx);

        // Export
        c.toBlob(function (blob) {
          if (!blob) return reject(new Error('Canvas toBlob failed'));
          resolve(blob);
        }, 'image/png', 0.92);
      } catch (e) {
        reject(e);
      }
    });
  }

  /* Upload helper — uploads the blob to the business-og bucket,
   * updates businesses.og_image_url via RPC, returns public URL.
   * Requires window.ShopDB.client (Supabase JS) to be available. */
  function uploadAndPersist(supabaseClient, businessId, blob) {
    return new Promise(function (resolve, reject) {
      if (!supabaseClient || !supabaseClient.storage) {
        return reject(new Error('Supabase client missing'));
      }
      if (!businessId) return reject(new Error('businessId required'));

      var path = businessId + '/og.png';
      var file = new File([blob], 'og.png', { type: 'image/png' });

      supabaseClient.storage
        .from('business-og')
        .upload(path, file, {
          upsert: true,
          contentType: 'image/png',
          cacheControl: '3600'
        })
        .then(function (res) {
          if (res.error) throw res.error;
          var pub = supabaseClient.storage.from('business-og').getPublicUrl(path);
          var publicUrl = (pub && pub.data && pub.data.publicUrl) || null;
          if (!publicUrl) throw new Error('Could not get public URL');

          // Cache-bust query string so CDN serves the fresh card
          var urlWithBust = publicUrl + '?v=' + Date.now();

          // Persist URL via RPC (RLS-safe)
          return supabaseClient.rpc('update_my_og_image', { p_og_url: urlWithBust })
            .then(function (r) {
              if (r.error) throw r.error;
              resolve({ publicUrl: urlWithBust });
            });
        })
        .catch(reject);
    });
  }

  /* High-level helper — given a Supabase client and a shop object,
   * regenerates and uploads the card. Convenience wrapper. */
  function refresh(supabaseClient, shop) {
    if (!shop || !shop.id) return Promise.reject(new Error('shop.id missing'));
    return generate({
      name:         shop.name,
      ownerName:    shop.owner_name,
      mobile:       shop.mobile || shop.whatsapp,
      city:         shop.city_name || (shop.city && shop.city.name) || (shop.geo_cities && shop.geo_cities.name),
      locality:     shop.locality_name || (shop.locality && shop.locality.name),
      ratingAvg:    shop.rating_avg,
      ratingCount:  shop.rating_count,
      categoryIcon: shop.category_icon || (shop.category && shop.category.icon),
      categoryName: shop.category_name || (shop.category && shop.category.name),
      uspText:      shop.usp_text
    }).then(function (blob) {
      return uploadAndPersist(supabaseClient, shop.id, blob);
    });
  }

  root.OGCard = {
    generate: generate,
    uploadAndPersist: uploadAndPersist,
    refresh: refresh,
    W: W, H: H
  };
})(window);
