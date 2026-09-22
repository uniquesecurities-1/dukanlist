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
    card:  function (u) { return opt(u, { width: 600, height: 375, crop: 'fill' }); },
    strip: function (u) { return opt(u, { width: 500, height: 312, crop: 'fill' }); },
    thumb: function (u) { return opt(u, { width: 160, height: 160, crop: 'fill' }); },
    supportsWebP: supportsWebP,
    enableTransform: false        // Supabase Storage only; Cloudinary ignores it
  };
})(window);
