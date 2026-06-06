/* ============================================================
   dukanlist.com — Profile Completeness Score
   ============================================================
   USAGE:
     <div id="completeness-widget"></div>
     <script>DukanCompleteness.render('completeness-widget', business);</script>

   Where `business` is the shopkeeper's businesses row.
============================================================ */
(function(global){
  'use strict';

  // Each item: weight + check fn + label + action link
  const CHECKS = [
    { key: 'name',         w: 0,  label: 'Shop name',         href: '/panel/profile.html', test: b => !!(b.name && b.name.length > 1) },
    { key: 'mobile',       w: 0,  label: 'Mobile number',     href: '/panel/profile.html', test: b => !!(b.mobile && b.mobile.length >= 10) },
    { key: 'usp_text',     w: 18, label: 'USP / Tagline (English)', href: '/panel/profile.html#usp', test: b => !!(b.usp_text && b.usp_text.trim().length >= 20) },
    { key: 'usp_hi',       w: 6,  label: 'USP / Tagline (Hindi)',   href: '/panel/profile.html#usp', test: b => !!(b.usp_hi && b.usp_hi.trim().length >= 10) },
    { key: 'about_text',   w: 14, label: 'About / Description (50+ chars)', href: '/panel/profile.html#about', test: b => !!(b.about_text && b.about_text.trim().length >= 50) },
    { key: 'photos',       w: 20, label: 'Photos (3+)',       href: '/panel/photos.html', test: b => Array.isArray(b.photos) && b.photos.length >= 3,
                                                                                   partial: b => Array.isArray(b.photos) && b.photos.length >= 1 ? 8 : 0 },
    { key: 'whatsapp',     w: 6,  label: 'WhatsApp number',   href: '/panel/profile.html', test: b => !!(b.whatsapp && b.whatsapp.length >= 10) },
    { key: 'hours_json',   w: 10, label: 'Business hours',    href: '/panel/profile.html#hours', test: b => isFilledObj(b.hours_json) },
    { key: 'services_json',w: 10, label: 'Services / Pricing',href: '/panel/services.html', test: b => isNonEmptyArray(b.services_json) },
    { key: 'address_line1',w: 6,  label: 'Address line 1',    href: '/panel/profile.html#addr', test: b => !!(b.address_line1 && b.address_line1.length > 3) },
    { key: 'video_url',    w: 5,  label: '30-sec intro video (optional but boosts trust)', href: '/panel/profile.html#video', test: b => !!(b.video_url && /^https?:/.test(b.video_url)) },
    { key: 'qr',           w: 5,  label: 'QR code printed at shop',                 href: '/panel/qr-code.html', test: b => !!b.qr_printed_marked /* shopkeeper self-marks */ }
  ];

  function isFilledObj(x){
    if (!x || typeof x !== 'object') return false;
    return Object.keys(x).length > 0;
  }
  function isNonEmptyArray(x){
    if (!x) return false;
    if (Array.isArray(x)) return x.length > 0;
    if (typeof x === 'object') return Object.keys(x).length > 0;
    return false;
  }

  function calc(business){
    if (!business) return { score: 0, max: 100, percent: 0, items: [] };
    const items = CHECKS.filter(c => c.w > 0).map(c => {
      const ok = !!c.test(business);
      let earned = ok ? c.w : (c.partial ? c.partial(business) : 0);
      return { key: c.key, label: c.label, href: c.href, weight: c.w, earned, ok };
    });
    const max = items.reduce((s, it) => s + it.weight, 0);
    const score = items.reduce((s, it) => s + it.earned, 0);
    const percent = max ? Math.round((score / max) * 100) : 0;
    return { score, max, percent, items };
  }

  function tier(percent){
    if (percent >= 90) return { name: 'Excellent', emoji: '🏆', color: '#10B981', tag: 'Top-tier listing' };
    if (percent >= 70) return { name: 'Good',      emoji: '✨', color: '#22C55E', tag: 'Customer-ready' };
    if (percent >= 50) return { name: 'Decent',    emoji: '⚡', color: '#F59E0B', tag: 'Add a few more details' };
    if (percent >= 30) return { name: 'Basic',     emoji: '📝', color: '#F97316', tag: 'Profile needs work' };
    return                  { name: 'Incomplete',  emoji: '⚠️', color: '#EF4444', tag: 'Customers may skip your listing' };
  }

  function render(targetId, business){
    const el = document.getElementById(targetId);
    if (!el) return;

    const r = calc(business);
    const t = tier(r.percent);
    const missing = r.items.filter(it => !it.ok && it.earned < it.weight).sort((a,b) => b.weight - a.weight);

    el.innerHTML = `
      <style>
        .pc-card{background:#fff;border:1px solid #e2e8f0;border-radius:14px;padding:18px;box-shadow:0 1px 3px rgba(0,0,0,.04);font-family:Manrope,Inter,-apple-system,sans-serif}
        .pc-head{display:flex;justify-content:space-between;align-items:flex-start;gap:12px;flex-wrap:wrap}
        .pc-title{font-size:14px;font-weight:800;color:#0F172A;display:flex;align-items:center;gap:8px;text-transform:uppercase;letter-spacing:.04em}
        .pc-percent{font-size:38px;font-weight:800;line-height:1;color:${t.color};letter-spacing:-.02em}
        .pc-tier{font-size:13px;font-weight:700;color:${t.color};margin-top:2px}
        .pc-tier .pc-tag{display:block;color:#64748b;font-weight:500;font-size:11px;margin-top:2px;letter-spacing:.02em}
        .pc-bar-wrap{height:8px;background:#F1F5F9;border-radius:6px;overflow:hidden;margin:14px 0 12px}
        .pc-bar{height:100%;background:linear-gradient(90deg, ${t.color}, ${t.color}aa);width:${r.percent}%;border-radius:6px;transition:width .6s cubic-bezier(.4,0,.2,1)}
        .pc-todo-title{font-size:12px;font-weight:700;color:#475569;margin-bottom:8px;text-transform:uppercase;letter-spacing:.04em}
        .pc-todo{display:flex;flex-direction:column;gap:7px}
        .pc-item{display:flex;justify-content:space-between;align-items:center;gap:10px;padding:9px 12px;background:#F8FAFC;border:1px solid #E2E8F0;border-radius:9px;text-decoration:none;color:#0F172A;font-size:13px;font-weight:600;transition:all .15s}
        .pc-item:hover{background:#fff;border-color:#6366F1;transform:translateX(2px)}
        .pc-item .pc-arrow{color:#6366F1;font-weight:700}
        .pc-gain{font-size:11px;font-weight:800;background:${t.color};color:#fff;padding:2px 7px;border-radius:99px}
        .pc-done{padding:14px;background:linear-gradient(135deg,#ECFDF5,#D1FAE5);border:1px solid #6EE7B7;border-radius:10px;text-align:center;font-size:13px;font-weight:700;color:#065F46}
      </style>
      <div class="pc-card">
        <div class="pc-head">
          <div>
            <div class="pc-title">${t.emoji} Profile Completeness</div>
            <div class="pc-tier" style="margin-top:6px">${t.name}<span class="pc-tag">${t.tag}</span></div>
          </div>
          <div style="text-align:right">
            <div class="pc-percent">${r.percent}%</div>
            <div style="font-size:11px;color:#94a3b8;font-weight:600">${r.score} / ${r.max} pts</div>
          </div>
        </div>
        <div class="pc-bar-wrap"><div class="pc-bar"></div></div>
        ${ missing.length === 0
          ? '<div class="pc-done">🎉 Profile is complete. Great job!</div>'
          : `<div class="pc-todo-title">Add these to boost your score</div>
             <div class="pc-todo">
               ${missing.slice(0, 5).map(it => `
                 <a class="pc-item" href="${it.href}">
                   <span>${escapeHtml(it.label)}</span>
                   <span style="display:flex;align-items:center;gap:8px">
                     <span class="pc-gain">+${it.weight - it.earned} pts</span>
                     <span class="pc-arrow">→</span>
                   </span>
                 </a>
               `).join('')}
             </div>`
        }
      </div>
    `;
  }

  function escapeHtml(s){ return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]); }

  global.DukanCompleteness = { render, calc, tier };
})(window);
