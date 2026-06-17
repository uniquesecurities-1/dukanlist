/* ============================================================
   review-boost.js — Customer Review generation toolkit
   ============================================================
   4 mechanisms, all client-side:

   1. Track contact events — when customer clicks call/WA on a shop
      page, log slug + ts to localStorage.

   2. Post-contact review prompt — when customer revisits a shop they
      previously contacted, show a soft modal: "How was your visit?"
      → 1 tap → opens the existing review modal pre-filled.

   3. "Top reviews this week" widget — finds the 1-3 most recent 4-5★
      reviews and renders a highlight strip above the existing list.

   4. Smart review-request link — for shopkeepers, generates a clean
      shareable URL with attribution params that lands customers on
      the shop's profile with review modal pre-opened.

   Public API:
     window.DukanReviewBoost.trackContact(biz, action)
     window.DukanReviewBoost.maybePrompt(currentBiz)
     window.DukanReviewBoost.topThisWeek(reviews) → array
     window.DukanReviewBoost.buildRequestUrl(biz) → string

   Storage keys (localStorage):
     dl_contacted_shops       — Array<{ slug, name, ts, action }>
     dl_review_prompt_seen    — Object<slug, lastShownMs>
============================================================ */
(function(global){
  'use strict';

  const KEY_CONTACTS = 'dl_contacted_shops';
  const KEY_PROMPT_SEEN = 'dl_review_prompt_seen';
  const MAX_TRACKED = 30;
  const PROMPT_COOLDOWN_MS = 3 * 24 * 60 * 60 * 1000; // don't re-show within 3 days

  // ============================================================
  // 1. Track contact events
  // ============================================================
  function loadContacts(){
    try { return JSON.parse(localStorage.getItem(KEY_CONTACTS) || '[]') || []; }
    catch(_){ return []; }
  }
  function saveContacts(arr){
    try { localStorage.setItem(KEY_CONTACTS, JSON.stringify(arr.slice(0, MAX_TRACKED))); } catch(_){}
  }

  // Compliance gate — strict pros (Doctor/CA/Lawyer/CS/CMA) must never
  // be tracked or prompted for reviews. The host page (business.html)
  // sets body.prof-strict for any strict professional listing; we read
  // that class as a defense-in-depth guard in case a future caller
  // forgets to gate at the call site.
  function isStrictProPage(){
    try {
      return document.body && document.body.classList &&
             document.body.classList.contains('prof-strict');
    } catch(_){ return false; }
  }

  function trackContact(biz, action){
    if (!biz || !biz.slug) return;
    if (isStrictProPage()) return;  // ← strict pro guard
    const arr = loadContacts();
    // Keep latest at front, dedupe by slug
    const i = arr.findIndex(x => x.slug === biz.slug);
    const entry = {
      slug:   String(biz.slug),
      name:   String(biz.name || 'Shop'),
      action: String(action || 'contact'),
      ts:     Date.now()
    };
    if (i >= 0) arr.splice(i, 1);
    arr.unshift(entry);
    saveContacts(arr);
  }

  function getLastContact(slug){
    if (!slug) return null;
    return loadContacts().find(x => x.slug === slug) || null;
  }

  // ============================================================
  // 2. Post-contact review prompt modal
  // ============================================================
  function loadPromptSeen(){
    try { return JSON.parse(localStorage.getItem(KEY_PROMPT_SEEN) || '{}') || {}; }
    catch(_){ return {}; }
  }
  function setPromptSeen(slug){
    if (!slug) return;
    const seen = loadPromptSeen();
    seen[slug] = Date.now();
    try { localStorage.setItem(KEY_PROMPT_SEEN, JSON.stringify(seen)); } catch(_){}
  }

  function shouldPrompt(slug){
    if (!slug) return false;
    const contact = getLastContact(slug);
    if (!contact) return false;
    // Wait at least 6 hours since the contact so the customer has had time to visit
    const minSinceContact = 6 * 60 * 60 * 1000;
    if (Date.now() - contact.ts < minSinceContact) return false;
    const seen = loadPromptSeen()[slug];
    if (seen && Date.now() - seen < PROMPT_COOLDOWN_MS) return false;
    return true;
  }

  function buildPromptModal(biz, onYes, onLater){
    if (document.getElementById('rbReviewPrompt')) return;
    const wrap = document.createElement('div');
    wrap.id = 'rbReviewPrompt';
    wrap.style.cssText =
      'position:fixed;inset:0;z-index:99997;display:flex;align-items:center;justify-content:center;'
      + 'background:rgba(15,23,42,.55);backdrop-filter:blur(4px);'
      + 'padding:20px;opacity:0;transition:opacity .25s ease;'
      + 'font-family:\'Plus Jakarta Sans\',-apple-system,sans-serif';
    wrap.innerHTML =
      '<div style="background:#fff;border-radius:18px;max-width:380px;width:100%;padding:24px;box-shadow:0 20px 60px rgba(0,0,0,.35);transform:translateY(20px);transition:transform .3s ease">'
      + '  <div style="font-size:3rem;text-align:center;margin-bottom:8px">⭐</div>'
      + '  <div style="font-size:1.25rem;font-weight:900;color:#0F172A;text-align:center;letter-spacing:-.02em;line-height:1.2;margin-bottom:6px">How was <b style="color:#FF6B1A">' + escapeHtml(biz.name) + '</b>?</div>'
      + '  <div style="font-size:.92rem;color:#475569;text-align:center;margin-bottom:18px;line-height:1.5">You contacted them recently. A 10-second review really helps other locals find good shops.</div>'
      + '  <div id="rbStars" style="display:flex;justify-content:center;gap:8px;margin-bottom:18px">'
      +     [1,2,3,4,5].map(n => '<button data-r="' + n + '" type="button" style="background:transparent;border:0;font-size:2.4rem;cursor:pointer;padding:0;line-height:1;opacity:.32;transition:opacity .15s,transform .15s">★</button>').join('')
      + '  </div>'
      + '  <button id="rbLater" type="button" style="width:100%;background:#F1F5F9;color:#475569;border:0;padding:11px;border-radius:10px;font-weight:700;font-family:inherit;font-size:.88rem;cursor:pointer">Maybe later</button>'
      + '</div>';
    document.body.appendChild(wrap);
    requestAnimationFrame(() => {
      wrap.style.opacity = '1';
      wrap.firstChild.style.transform = 'translateY(0)';
    });

    const stars = wrap.querySelectorAll('#rbStars button');
    stars.forEach(btn => {
      btn.addEventListener('mouseenter', () => {
        const r = +btn.dataset.r;
        stars.forEach((s, i) => { s.style.opacity = (i < r) ? '1' : '.32'; s.style.color = (i < r) ? '#F59E0B' : '#94A3B8'; });
      });
      btn.addEventListener('click', () => {
        const r = +btn.dataset.r;
        close();
        try { if (typeof onYes === 'function') onYes(r); } catch(_){}
      });
    });
    wrap.querySelectorAll('#rbStars').forEach(host => {
      host.addEventListener('mouseleave', () => {
        stars.forEach(s => { s.style.opacity = '.32'; s.style.color = ''; });
      });
    });
    document.getElementById('rbLater').addEventListener('click', () => {
      close();
      try { if (typeof onLater === 'function') onLater(); } catch(_){}
    });
    // Click backdrop to close (treat as "later")
    wrap.addEventListener('click', (e) => {
      if (e.target === wrap){ close(); try { if (typeof onLater === 'function') onLater(); } catch(_){} }
    });
    function close(){
      wrap.style.opacity = '0';
      wrap.firstChild.style.transform = 'translateY(20px)';
      setTimeout(() => { try { wrap.remove(); } catch(_){} }, 250);
    }
  }

  function maybePrompt(currentBiz){
    if (!currentBiz || !currentBiz.slug) return;
    if (isStrictProPage()) return;  // ← strict pro guard (defense-in-depth)
    if (!shouldPrompt(currentBiz.slug)) return;
    // Soft delay so it doesn't surprise the user the instant page loads
    setTimeout(() => {
      if (!shouldPrompt(currentBiz.slug)) return; // re-check (tab might have changed)
      buildPromptModal(currentBiz,
        function(rating){
          setPromptSeen(currentBiz.slug);
          // Hand off to existing review flow on the page
          try {
            if (typeof openReviewModal === 'function'){
              openReviewModal();
              setTimeout(() => {
                if (typeof setRating === 'function') setRating(rating);
              }, 200);
            }
          } catch(_){}
        },
        function(){
          setPromptSeen(currentBiz.slug);
        }
      );
    }, 4000);
  }

  // ============================================================
  // 3. Top reviews this week — picks best recent ones
  // ============================================================
  function topThisWeek(reviews){
    if (!Array.isArray(reviews)) return [];
    const cutoff = Date.now() - 7 * 24 * 60 * 60 * 1000;
    return reviews
      .filter(r => r && r.rating >= 4 && r.text && r.text.trim().length >= 30)
      .filter(r => { const t = r.created_at ? new Date(r.created_at).getTime() : 0; return t >= cutoff; })
      .sort((a, b) => (b.rating || 0) - (a.rating || 0) || (new Date(b.created_at) - new Date(a.created_at)))
      .slice(0, 3);
  }

  function renderTopWeekWidget(hostId, reviews){
    const top = topThisWeek(reviews);
    const host = document.getElementById(hostId);
    if (!host) return;
    if (!top.length){ host.style.display = 'none'; return; }
    host.innerHTML =
      '<div style="background:linear-gradient(135deg,#FEF3C7 0%,#FED7AA 100%);border:1.5px solid #FB923C;border-radius:14px;padding:14px 18px;margin-bottom:16px;box-shadow:0 4px 14px rgba(251,146,60,.18)">'
      + '  <div style="display:flex;align-items:center;gap:8px;margin-bottom:10px">'
      +     '<span style="font-size:1.1rem">🔥</span>'
      +     '<span style="font-size:.74rem;font-weight:800;color:#9A3412;letter-spacing:.06em;text-transform:uppercase">Hottest reviews this week</span>'
      +   '</div>'
      +   top.map(r => {
            const stars = '⭐'.repeat(r.rating);
            const name = escapeHtml(r.customer_name || 'Customer');
            const text = escapeHtml(String(r.text || '').slice(0, 180));
            return '<div style="background:#fff;border-radius:10px;padding:11px 14px;margin-top:8px;border:1px solid rgba(0,0,0,0.04);box-shadow:0 1px 3px rgba(0,0,0,.04)">'
              + '<div style="display:flex;justify-content:space-between;align-items:center;font-size:.78rem;margin-bottom:4px">'
              +   '<span style="font-weight:800;color:#0F172A">' + name + '</span>'
              +   '<span>' + stars + '</span>'
              + '</div>'
              + '<div style="font-size:.84rem;color:#475569;line-height:1.45;font-style:italic">"' + text + '"</div>'
              + '</div>';
          }).join('')
      + '</div>';
    host.style.display = '';
  }

  // ============================================================
  // 4. Smart review-request link — shopkeeper shares it via WhatsApp
  // ============================================================
  function buildRequestUrl(biz){
    if (!biz || !biz.slug) return '';
    return 'https://dukanlist.com/business?slug=' + encodeURIComponent(biz.slug) + '&review=1&src=wa-request';
  }

  function buildRequestMessage(biz){
    if (!biz) return '';
    const name = biz.name || 'our shop';
    const url = buildRequestUrl(biz);
    return 'Namaste! Thanks for choosing *' + name + '*.\n\n'
      + 'If you had a good experience, a quick 10-second review on DukanList helps a lot — it shows other locals that we are a trusted shop:\n\n'
      + url + '\n\n'
      + 'Just tap the link → rate → done. Thank you!\n— ' + name;
  }

  // ============================================================
  // Helpers
  // ============================================================
  function escapeHtml(s){
    return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  }

  // ============================================================
  // Public API
  // ============================================================
  global.DukanReviewBoost = {
    trackContact:        trackContact,
    maybePrompt:         maybePrompt,
    topThisWeek:         topThisWeek,
    renderTopWeekWidget: renderTopWeekWidget,
    buildRequestUrl:     buildRequestUrl,
    buildRequestMessage: buildRequestMessage,
    getLastContact:      getLastContact
  };
})(window);
