/* ============================================================
   DukanList — Simple Universal USP Pack
   ============================================================
   Common-man friendly USP statements that apply to almost any
   shop. Pick 3-5, click to add — combined with " · " into the
   USP field. Bilingual (English-tagline + Hindi-tagline).

   Public API:
     window.SIMPLE_USPS              — themed array
     window.renderSimpleUspPicker(opts) — paints into a container
   ============================================================ */

(function(global){
  'use strict';

  // Each item: { en, hi, emoji }
  // - 'en' is the Hinglish tagline the user picks (most relatable)
  // - 'hi' is pure Devanagari for the Hindi UI side
  // - 'emoji' is the visual cue
  // The PUBLIC USP field gets the EN/HI based on viewer language
  // (frontend picks one — they store EN by default; a future toggle
  // can re-render in Hindi using the 'hi' field if needed)
  global.SIMPLE_USPS = {
    trust: {
      label_en: 'Trust',           label_hi: 'भरोसा',           emoji: '🤝',
      items: [
        { emoji:'🏛️', en:'20+ saal se isi jagah par',                hi:'20+ साल से इसी जगह पर' },
        { emoji:'👨‍👩‍👧', en:'1000+ families ka bharosa',                hi:'1000+ परिवारों का भरोसा' },
        { emoji:'⭐', en:'Sirsa-Bathinda mein jaana-maana naam',     hi:'सिरसा-बठिंडा में जाना-माना नाम' },
        { emoji:'🏠', en:'Family business — personal touch',        hi:'फैमिली बिज़नेस — पर्सनल टच' },
        { emoji:'✅', en:'Honest pricing — no bargain needed',      hi:'ईमानदार दाम — मोलभाव नहीं' },
        { emoji:'💯', en:'Money-back if not satisfied',             hi:'पैसे वापस अगर खुश नहीं' }
      ]
    },
    price: {
      label_en: 'Price',           label_hi: 'दाम',             emoji: '💰',
      items: [
        { emoji:'🏷️', en:'Sabse kam rate guaranteed',                hi:'सबसे कम रेट गारंटी' },
        { emoji:'🚫', en:'No hidden charges, no extra fees',         hi:'कोई छुपा चार्ज नहीं' },
        { emoji:'📦', en:'Wholesale rates available',                hi:'होलसेल रेट उपलब्ध' },
        { emoji:'💳', en:'EMI / installment available',              hi:'EMI / किस्तों पर उपलब्ध' },
        { emoji:'🎁', en:'Bulk order par special discount',          hi:'बल्क ऑर्डर पर स्पेशल छूट' },
        { emoji:'🪙', en:'Festival offers + season discounts',       hi:'त्यौहार ऑफर + सीज़न डिस्काउंट' }
      ]
    },
    service: {
      label_en: 'Service',         label_hi: 'सेवा',             emoji: '🚚',
      items: [
        { emoji:'🛵', en:'Free home delivery 5km tak',               hi:'5km तक फ्री होम डिलीवरी' },
        { emoji:'💬', en:'WhatsApp par turant reply',                hi:'WhatsApp पर तुरंत जवाब' },
        { emoji:'⚡', en:'Same-day service available',                hi:'उसी दिन सर्विस उपलब्ध' },
        { emoji:'🏃', en:'Ghar aakar service deta hu',               hi:'घर आकर सर्विस मिलती है' },
        { emoji:'🆘', en:'24x7 emergency available',                 hi:'24x7 इमरजेंसी उपलब्ध' },
        { emoji:'📱', en:'Online booking + WhatsApp order',          hi:'ऑनलाइन बुकिंग + WhatsApp ऑर्डर' }
      ]
    },
    quality: {
      label_en: 'Quality',         label_hi: 'क्वालिटी',          emoji: '✨',
      items: [
        { emoji:'💎', en:'100% asli maal — pakka guarantee',         hi:'100% असली माल — पक्की गारंटी' },
        { emoji:'🏷️', en:'Sirf branded items',                       hi:'सिर्फ ब्रांडेड आइटम' },
        { emoji:'🧾', en:'Bill aur warranty milta hai',              hi:'बिल और वारंटी मिलती है' },
        { emoji:'🧼', en:'Saaf-suthri dukaan — hygienic',            hi:'साफ-सुथरी दुकान — hygienic' },
        { emoji:'🆕', en:'Latest stock — fresh items',               hi:'ताज़ा स्टॉक — नए माल' },
        { emoji:'🛡️', en:'ISI / FSSAI / govt approved',              hi:'ISI / FSSAI / सरकार से approved' }
      ]
    },
    convenience: {
      label_en: 'Convenience',     label_hi: 'सुविधा',           emoji: '⚡',
      items: [
        { emoji:'💸', en:'UPI / Cash / Card — sab accept',           hi:'UPI / कैश / कार्ड — सब मंज़ूर' },
        { emoji:'📅', en:'Open 7 days a week',                        hi:'हफ़्ते के 7 दिन खुले' },
        { emoji:'❄️', en:'AC waiting area available',                 hi:'AC वेटिंग एरिया उपलब्ध' },
        { emoji:'🅿️', en:'Free parking available',                    hi:'फ्री पार्किंग उपलब्ध' },
        { emoji:'🗣️', en:'Hindi + English — dono mein baat',          hi:'हिंदी + English दोनों में बात' },
        { emoji:'🚶', en:'Walk-in welcome — appointment optional',    hi:'अपॉइंटमेंट ज़रूरी नहीं — सीधे आएं' }
      ]
    },
    specialty: {
      label_en: 'Specialty',       label_hi: 'विशेषता',           emoji: '🎯',
      items: [
        { emoji:'🏆', en:'All major brands available',                hi:'सभी बड़े ब्रांड उपलब्ध' },
        { emoji:'🛠️', en:'Custom orders accepted',                    hi:'कस्टम ऑर्डर लिए जाते हैं' },
        { emoji:'🧪', en:'Trial / demo before purchase',              hi:'खरीद से पहले ट्रायल / डेमो' },
        { emoji:'👨‍🔧', en:'Trained + experienced staff',                hi:'ट्रेन्ड + अनुभवी स्टाफ' },
        { emoji:'📜', en:'Licensed + certified professional',         hi:'लाइसेंस्ड + सर्टिफाइड प्रोफेशनल' },
        { emoji:'🎉', en:'Customer ke saath long relationship',       hi:'ग्राहक के साथ लंबा रिश्ता' }
      ]
    }
  };

  // Get all USPs flat (with theme tag)
  global.getAllSimpleUsps = function(){
    const out = [];
    Object.keys(global.SIMPLE_USPS).forEach(themeKey => {
      const t = global.SIMPLE_USPS[themeKey];
      t.items.forEach(it => {
        out.push({ ...it, themeKey, themeLabel: t.label_en, themeLabelHi: t.label_hi, themeEmoji: t.emoji });
      });
    });
    return out;
  };

  /**
   * Render a Simple USP picker into a container element.
   *
   * @param {Object} opts
   * @param {HTMLElement} opts.container — element to render into
   * @param {HTMLTextAreaElement} opts.target — textarea to insert chosen USPs
   * @param {string}  [opts.lang='en'] — 'en' or 'hi' for which text to insert
   * @param {Function} [opts.onChange] — callback after each toggle
   */
  global.renderSimpleUspPicker = function(opts){
    const ctn  = opts.container;
    const tgt  = opts.target;
    if (!ctn || !tgt) return;
    const lang = (opts.lang === 'hi') ? 'hi' : 'en';

    // Selected = parse current textarea split by ' · '
    const selected = new Set(
      (tgt.value || '').split(/\s*·\s*/).filter(Boolean)
    );

    let activeTheme = 'trust';

    function render(){
      const themeChips = Object.keys(global.SIMPLE_USPS).map(k => {
        const t = global.SIMPLE_USPS[k];
        const cls = k === activeTheme ? 'su-theme-chip active' : 'su-theme-chip';
        return `<button type="button" class="${cls}" data-theme="${k}">${t.emoji} ${lang==='hi' ? t.label_hi : t.label_en}</button>`;
      }).join('');

      const items = global.SIMPLE_USPS[activeTheme].items;
      const grid = items.map((it, i) => {
        const txt = lang==='hi' ? it.hi : it.en;
        const isSel = selected.has(txt);
        return `<button type="button" class="su-pill ${isSel?'selected':''}" data-text="${escapeAttr(txt)}">
          <span class="su-emo">${it.emoji}</span>
          <span class="su-txt">${escapeHtml(txt)}</span>
          ${isSel?'<span class="su-tick">✓</span>':''}
        </button>`;
      }).join('');

      ctn.innerHTML = `
        <div class="su-header">
          <span class="su-title">${lang==='hi' ? '✨ क्विक USP — टैप करके जोड़ें' : '✨ Quick USPs — Tap to add (3-5 best)'}</span>
          <span class="su-count" id="suCount">${selected.size} ${lang==='hi'?'चुने':'picked'}</span>
        </div>
        <div class="su-themes">${themeChips}</div>
        <div class="su-grid">${grid}</div>
        ${selected.size>0 ? `<button type="button" class="su-clear" id="suClear">${lang==='hi' ? '× सब हटाएँ' : '× Clear all'}</button>` : ''}
      `;

      // Bind theme chips
      ctn.querySelectorAll('[data-theme]').forEach(b => {
        b.onclick = () => { activeTheme = b.dataset.theme; render(); };
      });
      // Bind item pills
      ctn.querySelectorAll('[data-text]').forEach(b => {
        b.onclick = () => {
          const t = b.dataset.text;
          if (selected.has(t)) selected.delete(t);
          else selected.add(t);
          tgt.value = Array.from(selected).join(' · ');
          // Trigger input event so any maxlen / counter listeners update
          tgt.dispatchEvent(new Event('input', { bubbles: true }));
          render();
          if (typeof opts.onChange === 'function') opts.onChange(Array.from(selected));
        };
      });
      // Clear all
      const clr = ctn.querySelector('#suClear');
      if (clr) clr.onclick = () => {
        selected.clear();
        tgt.value = '';
        tgt.dispatchEvent(new Event('input', { bubbles: true }));
        render();
      };
    }

    render();
  };

  // Helpers
  function escapeHtml(s){
    if (s==null) return '';
    return String(s).replace(/[&<>"']/g, m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
  }
  function escapeAttr(s){ return escapeHtml(s).replace(/"/g,'&quot;'); }
})(window);
