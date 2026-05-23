/* ============================================================
   breadcrumbs.js — Render breadcrumb trail + Schema.org JSON-LD
   ============================================================
   USAGE:
     <div id="breadcrumbsSlot"></div>
     <script>
       DukanCrumbs.render('breadcrumbsSlot', [
         { name: 'Home', href: '/' },
         { name: 'Mandi Dabwali', href: '/local/mandi-dabwali/healthcare' },
         { name: 'Medical Stores', href: '/local/mandi-dabwali/medical-store' },
         { name: 'Sharma Pharmacy' }   // last item: no href
       ]);
     </script>
============================================================ */
(function(global){
  'use strict';

  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]); }

  function render(slotId, items){
    const el = document.getElementById(slotId);
    if (!el || !Array.isArray(items) || !items.length) return;

    const html = items.map((it, i) => {
      const isLast = (i === items.length - 1);
      if (isLast || !it.href){
        return '<span style="color:#0F172A;font-weight:600">' + esc(it.name) + '</span>';
      }
      return '<a href="' + esc(it.href) + '" style="color:#FF6B1A;font-weight:600;text-decoration:none">' + esc(it.name) + '</a>';
    }).join('<span style="color:#cbd5e1;margin:0 8px">›</span>');

    el.innerHTML = '<nav aria-label="Breadcrumb" style="font-family:\'Plus Jakarta Sans\',\'Manrope\',-apple-system,sans-serif;font-size:.84rem;color:#64748b;padding:10px 0;line-height:1.6;letter-spacing:.01em">' + html + '</nav>';

    // Inject Schema.org BreadcrumbList JSON-LD for SEO
    try {
      const origin = location.origin;
      const ldItems = items
        .filter(it => it.name)
        .map((it, i) => ({
          '@type': 'ListItem',
          position: i + 1,
          name: it.name,
          ...(it.href ? { item: it.href.startsWith('http') ? it.href : origin + it.href } : {})
        }));
      const ld = { '@context': 'https://schema.org', '@type': 'BreadcrumbList', itemListElement: ldItems };
      // Replace existing breadcrumb schema if present
      const existing = document.querySelector('script[data-crumbs-schema]');
      if (existing) existing.remove();
      const s = document.createElement('script');
      s.setAttribute('type', 'application/ld+json');
      s.setAttribute('data-crumbs-schema', '1');
      s.textContent = JSON.stringify(ld);
      document.head.appendChild(s);
    } catch(_){}
  }

  global.DukanCrumbs = { render };
})(window);
