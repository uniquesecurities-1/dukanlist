// =====================================================
// nav.js — Auto-inject hamburger menu + mobile nav drawer
// =====================================================
// Self-initializing on DOMContentLoaded.
// Detects .topbar-inner and adds hamburger + backdrop.
// Works on all pages that have <header class="topbar">.
// =====================================================

(function(){
  function init(){
    const topbarInner = document.querySelector('.topbar-inner');
    if (!topbarInner) return;
    const navLinks = topbarInner.querySelector('.nav-links');
    if (!navLinks) return;

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
