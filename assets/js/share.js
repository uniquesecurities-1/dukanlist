/* ============================================================
   dukanlist.com — Share helpers (WhatsApp + native + clipboard)
   ============================================================
   Use:
     <button onclick="DukanShare.whatsapp(event, {slug:'sharma-medical', name:'Sharma Medical', city:'Sirsa'})">
       💬 Share
     </button>

   Or programmatically:
     DukanShare.whatsapp(evt, { slug, name, city });
     DukanShare.native(evt, { slug, name, city });    // uses Web Share API if available
============================================================ */
(function(global){
  'use strict';

  function bizUrl(slug, id){
    // Prefer slug-based URL; fall back to id. Always include
    // ?ref=share so we can attribute viral traffic later in analytics.
    var origin = 'https://dukanlist.com';
    try { if (location && location.origin) origin = location.origin; } catch(_) {}
    if (slug) return origin + '/share?slug=' + encodeURIComponent(slug);
    if (id)   return origin + '/share?id='   + encodeURIComponent(id);
    return origin + '/';
  }

  function defaultMessage(b){
    var name = b.name || 'this shop';
    var city = b.city ? (' in ' + b.city) : '';
    var cat  = b.category ? (' (' + b.category + ')') : '';
    var url  = bizUrl(b.slug, b.id);
    return 'Check out *' + name + '*' + cat + city + ' on DukanList — ' +
           'Bharat ka local shop directory.\n\n' + url +
           '\n\n_Found via dukanlist.com_';
  }

  function stop(ev){
    if (ev){
      try { ev.preventDefault(); ev.stopPropagation(); } catch(_) {}
    }
  }

  // ---- WhatsApp share ----
  function whatsapp(ev, b){
    stop(ev);
    var text = defaultMessage(b);
    var href = 'https://wa.me/?text=' + encodeURIComponent(text);
    window.open(href, '_blank', 'noopener,noreferrer');
  }

  // ---- Native Web Share (mobile preferred) — falls back to WhatsApp ----
  async function native(ev, b){
    stop(ev);
    var url = bizUrl(b.slug, b.id);
    var title = (b.name || 'DukanList') + (b.city ? ' — ' + b.city : '');
    var text = (b.name || 'this shop') + ' on DukanList';
    try {
      if (navigator.share){
        await navigator.share({ title: title, text: text, url: url });
        return;
      }
    } catch(err){
      // user cancelled or share failed — silent
      if (err && err.name === 'AbortError') return;
    }
    // Fallback: WhatsApp web
    whatsapp(null, b);
  }

  // ---- Copy URL to clipboard with little toast ----
  async function copyLink(ev, b){
    stop(ev);
    var url = bizUrl(b.slug, b.id);
    try {
      await navigator.clipboard.writeText(url);
      toast('Link copied to clipboard');
    } catch(_){
      // older browsers: prompt
      prompt('Copy this link:', url);
    }
  }

  function toast(msg){
    var t = document.createElement('div');
    t.textContent = msg;
    t.style.cssText = 'position:fixed;bottom:24px;left:50%;transform:translateX(-50%);'
      + 'background:#0F172A;color:#fff;padding:10px 18px;border-radius:10px;font-size:14px;'
      + 'font-weight:600;z-index:99999;box-shadow:0 8px 24px rgba(15,23,42,.25);'
      + 'opacity:0;transition:opacity .15s ease';
    document.body.appendChild(t);
    requestAnimationFrame(function(){ t.style.opacity = '1'; });
    setTimeout(function(){
      t.style.opacity = '0';
      setTimeout(function(){ t.remove(); }, 250);
    }, 2400);
  }

  // ---- Inline button HTML helper (for cards) ----
  // Use: ${DukanShare.btn({slug, name, city, category})}
  function btn(b, opts){
    opts = opts || {};
    var size = opts.size || 'sm'; // sm or md
    var bSafe = JSON.stringify({ slug:b.slug||'', id:b.id||'', name:b.name||'', city:b.city||'', category:b.category||'' })
      .replace(/"/g, '&quot;');
    var px = size === 'md' ? '10px 14px' : '6px 10px';
    var fs = size === 'md' ? '14px' : '12px';
    return '<button type="button" onclick="DukanShare.whatsapp(event, ' + bSafe + ')" '
      + 'title="Share on WhatsApp" aria-label="Share on WhatsApp" '
      + 'style="display:inline-flex;align-items:center;gap:5px;background:#25D366;color:#fff;'
      + 'border:0;border-radius:8px;padding:' + px + ';font-size:' + fs + ';font-weight:700;'
      + 'cursor:pointer;line-height:1;box-shadow:0 1px 3px rgba(37,211,102,.35);'
      + 'transition:transform .12s">'
      + '<span style="font-size:1.1em">💬</span><span>Share</span></button>';
  }

  global.DukanShare = {
    whatsapp: whatsapp,
    native: native,
    copyLink: copyLink,
    bizUrl: bizUrl,
    btn: btn,
    toast: toast
  };
})(window);
