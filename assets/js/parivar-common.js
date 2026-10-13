/* ============================================================
   parivar-common.js — shared bits for Dabwali Parivar (db/251)
   /parivar (search), /parivar/<slug> (person), /sanstha/<slug>.
   Reads go through the public parivar_* functions only; the
   tables themselves are closed and the mobile number is never
   returned unless the person chose "show" or "whatsapp".
   ============================================================ */
(function(global){
  'use strict';
  var CFG = global.DL_CONFIG || {};
  var SB = CFG.supabase || {};

  function rpc(fn, body){
    return fetch(SB.url + '/rest/v1/rpc/' + fn, {
      method: 'POST',
      headers: { apikey: SB.anon_key, Authorization: 'Bearer ' + SB.anon_key, 'Content-Type': 'application/json' },
      body: JSON.stringify(body || {})
    }).then(function(r){
      return r.json().catch(function(){ return null; }).then(function(j){
        if (!r.ok) throw new Error((j && j.message) || ('HTTP ' + r.status));
        return j;
      });
    });
  }
  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"']/g, function(c){ return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]; }); }
  function bi(en, hi){ return '<span data-i18n-en>' + esc(en) + '</span><span data-i18n-hi>' + esc(hi) + '</span>'; }

  var ROLES = {
    president: ['President', 'अध्यक्ष'], vice_president: ['Vice President', 'उपाध्यक्ष'],
    secretary: ['Secretary', 'सचिव'], joint_secretary: ['Joint Secretary', 'संयुक्त सचिव'],
    treasurer: ['Treasurer', 'कोषाध्यक्ष'], pro: ['PRO', 'प्रचार मंत्री'], patron: ['Patron', 'संरक्षक'],
    chairman: ['Chairman', 'चेयरमैन'], director: ['Director', 'निदेशक'], coordinator: ['Coordinator', 'संयोजक'],
    founder: ['Founder', 'संस्थापक'], advisor: ['Advisor', 'सलाहकार'],
    member: ['Member', 'सदस्य'], other: ['Office bearer', 'पदाधिकारी']
  };
  var FIRM_ROLES = {
    founder: ['Founder', 'संस्थापक'], owner: ['Owner', 'मालिक'], proprietor: ['Proprietor', 'प्रोपराइटर'],
    partner: ['Partner', 'पार्टनर'], director: ['Director', 'डायरेक्टर'], ceo: ['CEO', 'CEO'],
    manager: ['Manager', 'मैनेजर'], other: ['Associated', 'जुड़े हुए']
  };
  var KINDS = {
    seva: ['Service club', 'सेवा संस्था'], vyapar: ['Trade association', 'व्यापार मंडल'],
    dharmik: ['Religious', 'धार्मिक संस्था'], shiksha: ['Education', 'शिक्षा संस्था'],
    khel: ['Sports', 'खेल संस्था'], samajik: ['Social', 'सामाजिक संस्था'],
    professional: ['Professional body', 'प्रोफेशनल संस्था'], other: ['Organisation', 'संस्था']
  };
  function roleHtml(role, label){
    if (label) return esc(label);
    var r = ROLES[role] || ROLES.other; return bi(r[0], r[1]);
  }
  function firmRoleHtml(role, label){
    if (label) return esc(label);
    var r = FIRM_ROLES[role] || FIRM_ROLES.other; return bi(r[0], r[1]);
  }
  function kindHtml(k){ var r = KINDS[k] || KINDS.other; return bi(r[0], r[1]); }
  function initials(name){
    var p = String(name || '').trim().split(/\s+/).filter(Boolean);
    return ((p[0] || '?').charAt(0) + (p.length > 1 ? p[p.length - 1].charAt(0) : '')).toUpperCase();
  }
  function avatar(photo, name, size, round){
    size = size || 56;
    var r = round === false ? '14px' : '50%';
    if (photo){
      var src = /res\.cloudinary\.com\//.test(photo) ? photo.replace('/upload/', '/upload/w_' + (size * 2) + ',h_' + (size * 2) + ',c_fill,g_face,q_auto,f_auto/') : photo;
      return '<img src="' + esc(src) + '" alt="" width="' + size + '" height="' + size + '" style="width:' + size + 'px;height:' + size + 'px;border-radius:' + r + ';object-fit:cover;display:block;flex:0 0 auto">';
    }
    return '<span style="width:' + size + 'px;height:' + size + 'px;border-radius:' + r + ';background:#FFEDD5;color:#9A3412;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:' + Math.round(size / 2.6) + 'px;flex:0 0 auto">' + esc(initials(name)) + '</span>';
  }
  // v384: organisation logos — white margins inside the logo file are trimmed off (Cloudinary e_trim),
  // then the whole logo is fitted (never cropped) in a frame of fixed height; a wide logo may use
  // up to 1.6× that width. So a small logo fills its frame and a big one can't grow past it.
  function logo(url, name, size){
    size = size || 80;
    var maxW = Math.round(size * 1.6), pad = Math.round(size * 0.08);
    if (url){
      var src = /res\.cloudinary\.com\//.test(url) ? url.replace('/upload/', '/upload/e_trim:10/w_' + (maxW * 2) + ',h_' + (size * 2) + ',c_fit,q_auto,f_auto/') : url;
      return '<span style="height:' + size + 'px;min-width:' + size + 'px;max-width:' + maxW + 'px;padding:' + pad + 'px;box-sizing:border-box;border-radius:16px;flex:0 0 auto;display:inline-flex;align-items:center;justify-content:center;background:#fff;border:1px solid #E2E8F0;box-shadow:0 2px 8px rgba(15,23,42,.06);overflow:hidden">'
        + '<img src="' + esc(src) + '" alt="' + esc(name || '') + ' logo" data-fit-skip="1" style="display:block;width:auto;height:auto;max-height:' + (size - 2 * pad - 2) + 'px;max-width:' + (maxW - 2 * pad - 2) + 'px;object-fit:contain"></span>';
    }
    return '<span style="width:' + size + 'px;height:' + size + 'px;border-radius:16px;flex:0 0 auto;background:#FFEDD5;color:#9A3412;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:' + Math.round(size / 2.8) + 'px">' + esc(initials(name)) + '</span>';
  }
  // contact for a person: show → number + Call + WhatsApp; whatsapp → button only; hidden → nothing
  function contactHtml(mode, mobile, name){
    var m = String(mobile || '').replace(/\D/g, '').slice(-10);
    if (m.length !== 10 || mode === 'hidden') return '';
    var wa = 'https://wa.me/91' + m + '?text=' + encodeURIComponent('नमस्ते ' + (name || '') + ' जी, डबवाली परिवार (DukanList) पर आपका पेज देखा।');
    var waBtn = '<a class="pv-btn pv-wa" href="' + wa + '" target="_blank" rel="noopener">💬 ' + bi('WhatsApp', 'WhatsApp करें') + '</a>';
    if (mode === 'show'){
      return '<div class="pv-num">+91 ' + esc(m.slice(0, 5) + ' ' + m.slice(5)) + '</div>'
        + '<div class="pv-acts"><a class="pv-btn pv-call" href="tel:+91' + m + '">📞 ' + bi('Call', 'कॉल') + '</a>' + waBtn + '</div>';
    }
    return '<div class="pv-acts">' + waBtn + '</div>';
  }
  function setLang(lang){
    if (lang !== 'en' && lang !== 'hi') lang = 'en';
    document.documentElement.setAttribute('data-lang', lang);
    document.documentElement.setAttribute('lang', lang);
    try { localStorage.setItem('shop_lang', lang); } catch(_){}
    var e = document.getElementById('langBtnEn'), h = document.getElementById('langBtnHi');
    if (e) e.classList.toggle('active', lang === 'en');
    if (h) h.classList.toggle('active', lang === 'hi');
  }
  global.setLang = global.setLang || setLang;
  // inputs can't hold <span data-i18n-*>, so placeholders swap from data-ph-en / data-ph-hi
  function syncPlaceholders(){
    var hi = document.documentElement.getAttribute('data-lang') === 'hi';
    document.querySelectorAll('[data-ph-en]').forEach(function(el){ el.placeholder = hi ? (el.getAttribute('data-ph-hi') || el.getAttribute('data-ph-en')) : el.getAttribute('data-ph-en'); });
  }
  global.PVsyncPlaceholders = syncPlaceholders;
  try { new MutationObserver(syncPlaceholders).observe(document.documentElement, { attributes: true, attributeFilter: ['data-lang'] }); } catch(_){}
  document.addEventListener('DOMContentLoaded', function(){ var l = 'en'; try { l = localStorage.getItem('shop_lang') || 'en'; } catch(_){} global.setLang(l); });

  global.PV = { rpc: rpc, esc: esc, bi: bi, roleHtml: roleHtml, firmRoleHtml: firmRoleHtml, kindHtml: kindHtml,
                avatar: avatar, logo: logo, contactHtml: contactHtml, ROLES: ROLES, FIRM_ROLES: FIRM_ROLES, KINDS: KINDS, initials: initials };
})(window);
