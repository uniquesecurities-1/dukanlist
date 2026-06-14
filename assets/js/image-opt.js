/* ============================================================
   image-opt.js — Image optimization helper
   ============================================================
   STATUS: Transformation DISABLED by default (Supabase Image Transformation
   requires Pro plan — until enabled, we return original URLs to avoid 404s).

   To enable later (after Supabase Pro upgrade or other CDN setup):
     DukanImg.enableTransform = true;

   Usage stays the same in calling code:
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
    if (typeof global.__dlWebPSupport !== 'undefined') return global.__dlWebPSupport;
    try {
      var canvas = document.createElement('canvas');
      canvas.width = canvas.height = 1;
      var support = canvas.toDataURL('image/webp').indexOf('data:image/webp') === 0;
      global.__dlWebPSupport = support;
      return support;
    } catch(_) { return false; }
  }

  /**
   * Optimize image URL — returns original URL by default.
   * Set DukanImg.enableTransform = true to activate Supabase image transforms.
   */
  function opt(url, opts) {
    if (!url) return url;
    // SAFE PATH: return original URL unchanged
    if (!global.DukanImg || !global.DukanImg.enableTransform) return url;
    // Transformation path (only when explicitly enabled)
    if (!isSupabaseStorage(url)) return url;
    opts = opts || {};
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

  global.DukanImg = { opt: opt, supportsWebP: supportsWebP, enableTransform: false };
})(window);
