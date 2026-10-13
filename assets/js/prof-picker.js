/* ============================================================
   prof-picker.js — searchable profession picker, up to 3 (v369)
   Turns <input data-prof-picker> into chips + a search box with
   the full list. The original input stays (hidden) and holds the
   value as "A · B · C", so existing save code (input.value) and
   the database column (parivar_people.profession, ≤150, db/260)
   work unchanged. Custom entries are allowed.
   Used by /parivar-profile (member link) and /admin/parivar.
   ============================================================ */
(function(global){
  'use strict';
  var MAX = 3, MAXLEN = 40, SEP = ' · ';
  var LIST = [
    ['Businessman','व्यापारी'],['Shopkeeper','दुकानदार'],['Trader','ट्रेडर'],['Wholesaler','होलसेलर'],['Retailer','रिटेलर'],
    ['Commission Agent (Arhtiya)','आढ़ती'],['Manufacturer','निर्माता'],['Industrialist','उद्योगपति'],['Distributor','डिस्ट्रीब्यूटर'],
    ['Dealer','डीलर'],['Exporter / Importer','एक्सपोर्टर / इम्पोर्टर'],['Contractor','ठेकेदार'],['Builder / Developer','बिल्डर'],
    ['Property Dealer','प्रॉपर्टी डीलर'],['Transporter','ट्रांसपोर्टर'],['Jeweller','ज्वैलर'],['Cloth Merchant','कपड़ा व्यापारी'],
    ['Kiryana / Grocery','किरयाना'],['Hotel / Restaurant','होटल / रेस्टोरेंट'],['Medical Store','मेडिकल स्टोर'],['Petrol Pump','पेट्रोल पंप'],
    ['Chartered Accountant','सीए (चार्टर्ड अकाउंटेंट)'],['Company Secretary','कंपनी सेक्रेटरी'],['Tax Consultant','टैक्स कंसल्टेंट'],
    ['Mutual Fund Distributor','म्यूचुअल फंड डिस्ट्रीब्यूटर'],['Insurance Advisor','बीमा सलाहकार'],['Stock Broker','स्टॉक ब्रोकर'],
    ['Financial Advisor','वित्तीय सलाहकार'],['Banker','बैंकर'],
    ['Doctor','डॉक्टर'],['Dentist','दंत चिकित्सक'],['Ayurvedic Doctor (Vaid)','वैद्य'],['Pharmacist','फार्मासिस्ट'],['Nurse','नर्स'],
    ['Advocate','वकील'],['Engineer','इंजीनियर'],['Architect','आर्किटेक्ट'],['Teacher','अध्यापक'],['Professor','प्रोफेसर'],
    ['School Principal','प्रिंसिपल'],['Coaching / Tutor','कोचिंग / ट्यूटर'],['Software / IT','सॉफ्टवेयर / आईटी'],['Journalist','पत्रकार'],
    ['Photographer','फोटोग्राफर'],['Interior Designer','इंटीरियर डिज़ाइनर'],['Event Manager','इवेंट मैनेजर'],['Travel Agent','ट्रैवल एजेंट'],
    ['Consultant','सलाहकार'],['Farmer','किसान'],['Government Service','सरकारी नौकरी'],['Private Service','प्राइवेट नौकरी'],
    ['Defence / Army','सेना'],['Police','पुलिस'],['Politician','राजनेता'],['Social Worker','समाजसेवी'],['Priest / Pandit','पंडित'],
    ['Student','विद्यार्थी'],['Homemaker','गृहिणी'],['Retired','सेवानिवृत्त']
  ];
  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"']/g, function(c){ return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]; }); }
  function isHi(){ return document.documentElement.getAttribute('data-lang') === 'hi'; }
  function split(v){
    var seen = {}, out = [];
    String(v || '').split(/\s*[·,]\s*/).forEach(function(x){
      x = x.trim().slice(0, MAXLEN); var k = x.toLowerCase();
      if (x && !seen[k] && out.length < MAX){ seen[k] = 1; out.push(x); }
    });
    return out;
  }
  function hiOf(en){ for (var i = 0; i < LIST.length; i++) if (LIST[i][0].toLowerCase() === String(en).toLowerCase()) return LIST[i][1]; return ''; }

  function injectCss(){
    if (document.getElementById('ppCss')) return;
    var st = document.createElement('style'); st.id = 'ppCss';
    st.textContent =
      '.pp{position:relative}' +
      '.pp-box{display:flex;flex-wrap:wrap;gap:6px;align-items:center;border:1.5px solid #CBD5E1;border-radius:10px;padding:7px 8px;background:#fff;cursor:text;min-height:44px}' +
      '.pp-box.on{border-color:#FF6B1A;box-shadow:0 0 0 3px rgba(255,107,26,.15)}' +
      '.pp-chip{display:inline-flex;align-items:center;gap:4px;background:#FFF7ED;border:1px solid #FED7AA;color:#9A3412;border-radius:99px;padding:4px 6px 4px 11px;font-size:.86rem;font-weight:700}' +
      '.pp-chip button{border:0;background:transparent;color:#9A3412;font-size:1rem;line-height:1;cursor:pointer;padding:0 4px}' +
      '.pp input.pp-q[type=text]{flex:1;width:auto;min-width:140px;border:0;border-radius:0;outline:0;box-shadow:none;font:inherit;font-size:.95rem;padding:4px 2px;margin:0;background:transparent}' +
      '.pp-list{position:absolute;left:0;right:0;top:100%;margin-top:4px;background:#fff;border:1px solid #E2E8F0;border-radius:10px;box-shadow:0 10px 28px rgba(15,23,42,.14);max-height:260px;overflow:auto;z-index:50;display:none}' +
      '.pp-list.on{display:block}' +
      '.pp-it{padding:9px 12px;cursor:pointer;font-size:.92rem;display:flex;justify-content:space-between;gap:10px}' +
      '.pp-it small{color:#64748B}' +
      '.pp-it:hover,.pp-it.hl{background:#FFF7ED}' +
      '.pp-add{color:#C2410C;font-weight:700}' +
      '.pp-hint{font-size:.74rem;color:#64748B;margin-top:4px}';
    document.head.appendChild(st);
  }

  function attach(el){
    if (!el || el._pp) return el && el._pp;
    injectCss();
    var vals = split(el.value), hl = 0, items = [];
    el.type = 'hidden';
    var wrap = document.createElement('div'); wrap.className = 'pp';
    wrap.innerHTML = '<div class="pp-box"></div><div class="pp-list" role="listbox"></div><div class="pp-hint"></div>';
    el.parentNode.insertBefore(wrap, el.nextSibling);
    var box = wrap.querySelector('.pp-box'), list = wrap.querySelector('.pp-list'), hint = wrap.querySelector('.pp-hint');
    var q = document.createElement('input'); q.type = 'text'; q.className = 'pp-q'; q.autocomplete = 'off'; q.maxLength = MAXLEN;

    function sync(){ el.value = vals.join(SEP); try { el.dispatchEvent(new Event('change', { bubbles: true })); } catch(_){} }
    function drawChips(){
      box.innerHTML = vals.map(function(v, i){
        return '<span class="pp-chip">' + esc(v) + '<button type="button" data-i="' + i + '" aria-label="Remove">×</button></span>';
      }).join('');
      box.appendChild(q);
      var full = vals.length >= MAX;
      q.style.display = full ? 'none' : '';
      q.placeholder = vals.length ? (isHi() ? '+ और जोड़ें' : '+ add another') : (isHi() ? 'खोजें या लिखें — जैसे CA, Doctor, व्यापारी' : 'Search or type — e.g. CA, Doctor, Trader');
      hint.textContent = full ? (isHi() ? 'अधिकतम 3 — बदलने के लिए × दबाएँ' : 'Maximum 3 — press × to change')
                              : (isHi() ? 'एक से ज़्यादा चुन सकते हैं (3 तक)' : 'You can pick more than one (up to 3)');
    }
    function drawList(){
      var t = q.value.trim().toLowerCase(), chosen = {};
      vals.forEach(function(v){ chosen[v.toLowerCase()] = 1; });
      items = LIST.filter(function(p){
        return !chosen[p[0].toLowerCase()] && (!t || p[0].toLowerCase().indexOf(t) !== -1 || p[1].indexOf(q.value.trim()) !== -1);
      }).map(function(p){ return { v: p[0], hi: p[1] }; });
      var exact = items.some(function(x){ return x.v.toLowerCase() === t; });
      if (t && !exact && !chosen[t]) items.push({ v: q.value.trim(), add: true });
      if (hl >= items.length) hl = 0;
      list.innerHTML = items.length ? items.map(function(x, i){
        return '<div class="pp-it' + (i === hl ? ' hl' : '') + (x.add ? ' pp-add' : '') + '" data-i="' + i + '">'
          + (x.add ? '+ ' + (isHi() ? 'जोड़ें' : 'Add') + ' “' + esc(x.v) + '”' : '<span>' + esc(x.v) + '</span><small>' + esc(x.hi) + '</small>') + '</div>';
      }).join('') : '<div class="pp-it"><small>' + (isHi() ? 'कुछ नहीं मिला' : 'Nothing found') + '</small></div>';
    }
    function open(){ if (vals.length >= MAX) return; box.classList.add('on'); drawList(); list.classList.add('on'); }
    function close(){ box.classList.remove('on'); list.classList.remove('on'); }
    function pick(i){
      var x = items[i]; if (!x || vals.length >= MAX) return;
      vals.push(String(x.v).slice(0, MAXLEN)); q.value = ''; hl = 0; sync(); drawChips();
      if (vals.length < MAX){ q.focus(); drawList(); } else close();
    }

    box.addEventListener('mousedown', function(e){
      var b = e.target.closest('button[data-i]');
      if (b){ e.preventDefault(); vals.splice(+b.getAttribute('data-i'), 1); sync(); drawChips(); q.focus(); open(); return; }
      if (e.target !== q){ e.preventDefault(); q.focus(); open(); }
    });
    list.addEventListener('mousedown', function(e){
      var it = e.target.closest('.pp-it[data-i]'); if (!it) return; e.preventDefault(); pick(+it.getAttribute('data-i'));
    });
    q.addEventListener('focus', open);
    q.addEventListener('blur', function(){ setTimeout(close, 120); });
    q.addEventListener('input', function(){ hl = 0; open(); drawList(); });
    q.addEventListener('keydown', function(e){
      if (e.key === 'ArrowDown'){ e.preventDefault(); hl = Math.min(hl + 1, items.length - 1); drawList(); }
      else if (e.key === 'ArrowUp'){ e.preventDefault(); hl = Math.max(hl - 1, 0); drawList(); }
      else if (e.key === 'Enter' || e.key === ','){ if (q.value.trim() || e.key === 'Enter'){ e.preventDefault(); if (q.value.trim() && items.length) pick(hl); } }
      else if (e.key === 'Backspace' && !q.value && vals.length){ vals.pop(); sync(); drawChips(); drawList(); }
      else if (e.key === 'Escape'){ close(); }
    });
    try { new MutationObserver(function(){ drawChips(); if (list.classList.contains('on')) drawList(); })
            .observe(document.documentElement, { attributes: true, attributeFilter: ['data-lang'] }); } catch(_){}

    var api = {
      set: function(v){ vals = split(v); el.value = vals.join(SEP); drawChips(); },
      get: function(){ return el.value; }
    };
    el._pp = api; drawChips();
    return api;
  }
  function scan(root){ (root || document).querySelectorAll('input[data-prof-picker]').forEach(attach); }
  // admin screens render forms with innerHTML — pick up new inputs automatically
  function watch(){
    scan();
    try { new MutationObserver(function(){ scan(); }).observe(document.body, { childList: true, subtree: true }); } catch(_){}
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', watch); else watch();

  global.ProfPicker = { attach: attach, scan: scan, set: function(el, v){ var a = attach(el); if (a) a.set(v); }, LIST: LIST, hiOf: hiOf };
})(window);
