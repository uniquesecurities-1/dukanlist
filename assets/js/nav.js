// =====================================================
// nav.js — Auto-inject hamburger menu + mobile nav drawer
// =====================================================
// Self-initializing on DOMContentLoaded.
// Detects .topbar-inner and adds hamburger + backdrop.
// Works on all pages that have <header class="topbar">.
// =====================================================

(function(){
  // ===== Shortlist counter pill — injected into .nav-links on every page =====
  function injectShortlistLink(navLinks){
    if (!navLinks) return;
    if (navLinks.querySelector('.nav-shortlist-pill')) return; // avoid double
    const a = document.createElement('a');
    a.href = '/shortlist.html';
    a.className = 'nav-shortlist-pill';
    a.setAttribute('title', 'My saved shops');
    a.innerHTML = '<span aria-hidden="true">❤️</span>'
      + '<span class="nsp-label">Shortlist</span>'
      + '<span class="nsp-count" id="navShortlistCount" style="display:none">0</span>';
    a.style.cssText = 'display:inline-flex;align-items:center;gap:6px;background:#FEF2F2;color:#991B1B;border:1px solid #FECACA;padding:6px 12px;border-radius:99px;font-size:.82rem;font-weight:700;text-decoration:none;transition:.15s;font-family:inherit';
    a.onmouseover = function(){ this.style.background = '#FEE2E2'; this.style.transform = 'translateY(-1px)'; };
    a.onmouseout  = function(){ this.style.background = '#FEF2F2'; this.style.transform = ''; };
    navLinks.appendChild(a);

    // Inject CSS for count badge
    if (!document.getElementById('nav-shortlist-css')){
      const s = document.createElement('style');
      s.id = 'nav-shortlist-css';
      s.textContent = '.nsp-count{ background:#DC2626; color:#fff; font-size:.66rem; font-weight:800; padding:1px 7px; border-radius:99px; letter-spacing:.02em; min-width:18px; text-align:center; line-height:1.4 }'
        + '@media (max-width:520px){ .nav-shortlist-pill .nsp-label{ display:none } .nav-shortlist-pill{ padding:6px 10px !important } }';
      document.head.appendChild(s);
    }

    function updateCount(){
      if (typeof DukanShortlist === 'undefined') { setTimeout(updateCount, 200); return; }
      const n = DukanShortlist.count();
      const el = document.getElementById('navShortlistCount');
      if (!el) return;
      if (n > 0){ el.textContent = n; el.style.display = ''; }
      else { el.style.display = 'none'; }
    }
    updateCount();
    // Subscribe to changes
    if (typeof DukanShortlist !== 'undefined'){
      try { DukanShortlist.onChange(updateCount); } catch(_){}
    } else {
      // Shortlist script may load after nav.js; poll briefly
      let tries = 0;
      const t = setInterval(function(){
        if (typeof DukanShortlist !== 'undefined' || tries++ > 25){
          clearInterval(t);
          try { DukanShortlist && DukanShortlist.onChange(updateCount); } catch(_){}
          updateCount();
        }
      }, 200);
    }
  }

  function init(){
    const topbarInner = document.querySelector('.topbar-inner');
    if (!topbarInner) return;
    const navLinks = topbarInner.querySelector('.nav-links');
    if (!navLinks) return;

    // Inject shortlist pill into nav (every page that has .nav-links)
    injectShortlistLink(navLinks);

    // Avoid double-injection (in case script loads twice)
    if (topbarInner.querySelector('.hamburger')) return;

    // Create hamburger button
    const hamburger = document.createElement('button');
    hamburger.className = 'hamburger';
    hamburger.setAttribute('aria-label', 'Toggle menu');
    hamburger.setAttribute('aria-expanded', 'false');
    hamburger.innerHTML = '<span class="hamburger-icon"><span></span><span></span><span></span></span>';

    // Insert hamburger before nav-links
    topbarInner.insertBefore(hamburger, navLinks);

    // Create backdrop
    const backdrop = document.createElement('div');
    backdrop.className = 'nav-backdrop';
    document.body.appendChild(backdrop);

    // Toggle handlers
    function toggleMenu(){
      const isOpen = navLinks.classList.toggle('open');
      hamburger.classList.toggle('open', isOpen);
      backdrop.classList.toggle('show', isOpen);
      hamburger.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
      document.body.style.overflow = isOpen ? 'hidden' : '';
    }
    function closeMenu(){
      navLinks.classList.remove('open');
      hamburger.classList.remove('open');
      backdrop.classList.remove('show');
      hamburger.setAttribute('aria-expanded', 'false');
      document.body.style.overflow = '';
    }

    hamburger.addEventListener('click', toggleMenu);
    backdrop.addEventListener('click', closeMenu);

    // Close on link click (mobile UX)
    navLinks.querySelectorAll('a').forEach(a => {
      a.addEventListener('click', () => {
        // Small delay so click registers
        setTimeout(closeMenu, 100);
      });
    });

    // Close on Escape key
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && navLinks.classList.contains('open')) closeMenu();
    });

    // Close on resize > tablet breakpoint
    window.addEventListener('resize', () => {
      if (window.innerWidth > 720) closeMenu();
    });
  }

  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
