/* ============================================================
   image-opt.js — Supabase Storage image optimization helper
   ============================================================
   Wraps Supabase Storage URLs with image transformation params:
     - format=webp (30-50% smaller than JPEG)
     - width=400 (typical card display)
     - quality=75 (good balance)
     - resize=cover

   Non-Supabase URLs pass through unchanged (idempotent + safe).
   Auto-replaces /storage/v1/object/public/ with /storage/v1/render/image/public/

   Usage:
     <img src="${DukanImg.opt(b.photos[0], {width:400, quality:75})}" ...>
   ============================================================ */
(function (global) {
  'use strict';

  function isSupabaseStorage(url) {
    return typeof url === 'string' &&
           url.indexOf('/storage/v1/object/public/') !== -1 &&
           /supabase\.(co|in)/.test(url);
  }

  function supportsWebP() {
    // Modern browser feature detection (cached)
    if (typeof global.__dlWebPSupport !== 'undefined') return global.__dlWebPSupport;
    var canvas = document.createElement('canvas');
    canvas.width = canvas.height = 1;
    var support = canvas.toDataURL('image/webp').indexOf('data:image/webp') === 0;
    global.__dlWebPSupport = support;
    return support;
  }

  /**
   * Optimize a Supabase Storage URL for delivery.
   * @param {string} url - Original image URL
   * @param {object} opts - { width, height, quality, format, resize }
   * @returns {string} Optimized URL or original URL if not Supabase
   */
  function opt(url, opts) {
    if (!url) return url;
    opts = opts || {};
    // Pass through non-Supabase URLs unchanged
    if (!isSupabaseStorage(url)) return url;

    // Convert object endpoint → render endpoint
    var renderUrl = url.replace('/storage/v1/object/public/', '/storage/v1/render/image/public/');

    // Build query params
    var params = [];
    var width = opts.width || 400;
    var quality = opts.quality || 75;
    var format = opts.format || (supportsWebP() ? 'webp' : 'origin');
    var resize = opts.resize || 'cover';

    params.push('width=' + width);
    if (opts.height) params.push('height=' + opts.height);
    params.push('quality=' + quality);
    params.push('resize=' + resize);
    if (format !== 'origin') params.push('format=' + format);

    var separator = renderUrl.indexOf('?') !== -1 ? '&' : '?';
    return renderUrl + separator + params.join('&');
  }

  global.DukanImg = { opt: opt, supportsWebP: supportsWebP };
})(window);
