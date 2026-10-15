// =====================================================
// api/parivar.js — v394 (Dabwali Parivar phase 4)
// /parivar/:slug  → ?kind=person   (template: parivar-person.html)
// /sanstha/:slug  → ?kind=org      (template: sanstha.html)
//
// Both pages are drawn in the browser. Google mostly runs that script, but
// WhatsApp / Facebook link previews never do — they saw "Dabwali Parivar |
// DukanList" and a generic image for every person and organisation. This
// fills the <head> on the server: title, description, canonical, share
// image, robots, and schema.org data. The page body and its script are
// untouched, so the visible page is exactly what it was.
//
// Privacy: only the public functions the page itself uses
// (parivar_get_org / parivar_get_person). A person who has not confirmed
// their own page stays "noindex" and gets no structured data — same rule
// the page applies in the browser. No phone number goes into the head.
//
// Never worse than before: any failure serves the plain template.
// =====================================================

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://qazuyygrpqopwygxmvwq.supabase.co';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFhenV5eWdycHFvcHd5Z3htdndxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxNTUwOTEsImV4cCI6MjA5NDczMTA5MX0.FR8x2kldC2yelpPnK2QKd5WGwHUAQheCVmxfs6hR00I';
const ORIGIN = process.env.PUBLIC_SITE_URL || 'https://dukanlist.com';
const DEFAULT_IMG = ORIGIN + '/assets/brand/dabwali-parivar-og.jpg';

const TEMPLATES = {};   // cached per cold start

function esc(s){
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}
function attr(s){ return esc(s).replace(/\s+/g, ' ').trim(); }
function clip(s, n){ s = String(s || '').replace(/\s+/g, ' ').trim(); return s.length > n ? s.slice(0, n - 1).trim() + '…' : s; }

async function getTemplate(file){
  if (TEMPLATES[file]) return TEMPLATES[file];
  const r = await fetch(ORIGIN + '/' + file, { headers: { 'User-Agent': 'dukanlist-ssr' } });
  if (!r.ok) throw new Error('template ' + file + ' ' + r.status);
  TEMPLATES[file] = await r.text();
  return TEMPLATES[file];
}
async function rpc(fn, body){
  const r = await fetch(SUPABASE_URL + '/rest/v1/rpc/' + fn, {
    method: 'POST',
    headers: { apikey: SUPABASE_ANON_KEY, Authorization: 'Bearer ' + SUPABASE_ANON_KEY, 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify(body || {})
  });
  if (!r.ok) throw new Error(fn + ' ' + r.status);
  return r.json();
}
// Cloudinary image → 1200×630 share card (logos padded on white, photos cropped on the face)
function shareImg(u, logo){
  if (!/^https:\/\/res\.cloudinary\.com\/[^/]+\/image\/upload\//.test(u || '')) return DEFAULT_IMG;
  return u.replace('/upload/', logo ? '/upload/w_1200,h_630,c_pad,b_white,q_auto,f_jpg/' : '/upload/w_1200,h_630,c_fill,g_face,q_auto,f_jpg/');
}

const ROLE_HI = { president:'अध्यक्ष', vice_president:'उपाध्यक्ष', secretary:'सचिव', joint_secretary:'संयुक्त सचिव', treasurer:'कोषाध्यक्ष', pro:'प्रचार मंत्री',
  patron:'संरक्षक', chairman:'चेयरमैन', founder:'संस्थापक', director:'निदेशक', advisor:'सलाहकार', coordinator:'संयोजक', member:'सदस्य', other:'पदाधिकारी' };
const ROLE_EN = { president:'President', vice_president:'Vice President', secretary:'Secretary', joint_secretary:'Joint Secretary', treasurer:'Treasurer', pro:'PRO',
  patron:'Patron', chairman:'Chairman', founder:'Founder', director:'Director', advisor:'Advisor', coordinator:'Coordinator', member:'Member', other:'Office bearer' };
const KIND_EN = { seva:'Service club', vyapar:'Trade association', dharmik:'Religious organisation', shiksha:'Educational organisation', khel:'Sports club',
  samajik:'Social organisation', professional:'Professional body', other:'Organisation' };
function roleEn(r, l){ return (r === 'other' && l) ? l : (ROLE_EN[r] || l || r); }
function roleHi(r, l){ return (r === 'other' && l) ? l : (ROLE_HI[r] || l || r); }

function headFor(kind, d, slug){
  const url = ORIGIN + (kind === 'org' ? '/sanstha/' : '/parivar/') + slug;
  let title, desc, img, robots, ld = null;
  if (kind === 'org'){
    const name = d.name_hi ? d.name_hi + ' (' + d.name + ')' : d.name;
    const head = (d.bearers || []).find(b => b.role === 'president') || (d.bearers || [])[0];
    const members = (d.members || []).length;
    title = name + ' — ' + (d.city || 'Mandi Dabwali') + ' | डबवाली परिवार';
    desc = clip([KIND_EN[d.kind] || 'Organisation', d.city || 'Mandi Dabwali', members ? members + ' सदस्य' : '',
                 head ? roleHi(head.role, head.role_label) + ': ' + head.name : '', d.session ? 'सत्र ' + d.session : '', d.about || ''].filter(Boolean).join(' · '), 300);
    img = d.logo ? shareImg(d.logo, true) : DEFAULT_IMG;
    robots = 'index, follow';
    ld = {
      '@context': 'https://schema.org', '@type': 'Organization', name: d.name, url,
      alternateName: d.name_hi || undefined, description: clip(d.about || desc, 500), logo: d.logo || undefined,
      foundingDate: d.founded_year ? String(d.founded_year) : undefined,
      address: { '@type': 'PostalAddress', streetAddress: d.address || undefined, addressLocality: d.city || 'Mandi Dabwali', addressRegion: 'Haryana', addressCountry: 'IN' },
      member: (d.bearers || []).slice(0, 15).map(b => ({ '@type': 'OrganizationRole', roleName: roleEn(b.role, b.role_label),
        member: { '@type': 'Person', name: b.name, url: b.slug ? ORIGIN + '/parivar/' + b.slug : undefined } })),
      numberOfEmployees: undefined,
      isPartOf: { '@type': 'WebSite', name: 'Dabwali Parivar — DukanList', url: ORIGIN + '/parivar' }
    };
  } else {
    const cur = (d.roles || []).filter(r => r.current);
    const best = cur.slice().sort((a, b) => (a.role === 'member') - (b.role === 'member'))[0];
    const firm = (d.firms || [])[0];
    title = d.name + (d.profession ? ' — ' + clip(d.profession, 60) : '') + ' | डबवाली परिवार';
    desc = clip([d.profession, firm ? firm.name : '', best ? roleHi(best.role, best.role_label) + ', ' + best.org : '',
                 cur.length > 1 ? cur.length + ' संस्थाओं से जुड़े' : '', d.city || 'Mandi Dabwali', d.bio || ''].filter(Boolean).join(' · '), 300);
    img = d.photo ? shareImg(d.photo, false) : DEFAULT_IMG;
    robots = d.verified ? 'index, follow' : 'noindex, follow';
    if (d.verified){
      ld = {
        '@context': 'https://schema.org', '@type': 'Person', name: d.name, url, alternateName: d.name_hi || undefined,
        jobTitle: d.profession || undefined, image: d.photo || undefined, description: d.bio || undefined,
        homeLocation: { '@type': 'Place', name: d.city || 'Mandi Dabwali, Haryana' },
        worksFor: (d.firms || []).filter(f => f.name).map(f => ({ '@type': 'Organization', name: f.name, url: f.slug ? ORIGIN + '/' + f.slug : undefined })),
        memberOf: cur.map(r => ({ '@type': 'OrganizationRole', roleName: roleEn(r.role, r.role_label),
          memberOf: { '@type': 'Organization', name: r.org, url: ORIGIN + '/sanstha/' + r.org_slug } }))
      };
    }
  }
  const tags = [
    '<link rel="canonical" href="' + attr(url) + '">',
    '<meta property="og:type" content="' + (kind === 'org' ? 'website' : 'profile') + '">',
    '<meta property="og:site_name" content="DukanList — डबवाली परिवार">',
    '<meta property="og:title" content="' + attr(title) + '">',
    '<meta property="og:description" content="' + attr(desc) + '">',
    '<meta property="og:url" content="' + attr(url) + '">',
    '<meta property="og:image" content="' + attr(img) + '">',
    '<meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">',
    '<meta name="twitter:card" content="summary_large_image">',
    ld ? '<script type="application/ld+json">' + JSON.stringify(ld).replace(/</g, '\\u003c') + '</script>' : ''
  ].join('\n');
  return { title, desc, robots, tags };
}

function inject(html, h){
  let out = html.replace(/<title>[\s\S]*?<\/title>/i, '<title>' + esc(h.title) + '</title>')
                .replace(/<meta name="description" content="[^"]*">/i, '<meta name="description" content="' + attr(h.desc) + '">');
  if (/<meta name="robots"[^>]*>/i.test(out)) out = out.replace(/<meta name="robots" content="[^"]*"/i, '<meta name="robots" content="' + h.robots + '"');
  else out = out.replace(/<\/title>/i, '</title>\n<meta name="robots" content="' + h.robots + '">');
  return out.replace(/<\/head>/i, '<!-- v394: filled on the server (api/parivar.js) -->\n' + h.tags + '\n</head>');
}

module.exports = async (req, res) => {
  const kind = req.query.kind === 'org' ? 'org' : 'person';
  const slug = String(req.query.slug || '').toLowerCase();
  const file = kind === 'org' ? 'sanstha.html' : 'parivar-person.html';
  let html;
  try { html = await getTemplate(file); }
  catch(e){ res.statusCode = 302; res.setHeader('Location', '/' + file.replace('.html', '') + '?slug=' + encodeURIComponent(slug)); return res.end(); }
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  if (!/^[a-z0-9][a-z0-9-]{1,80}$/.test(slug)){ res.statusCode = 404; return res.end(html); }
  try {
    const d = await rpc(kind === 'org' ? 'parivar_get_org' : 'parivar_get_person', { p_slug: slug });
    if (!d){
      res.statusCode = 404;
      res.setHeader('Cache-Control', 'public, s-maxage=120');
      return res.end(html.replace(/<meta name="robots" content="[^"]*"/i, '<meta name="robots" content="noindex, follow"'));
    }
    res.setHeader('Cache-Control', 'public, s-maxage=300, stale-while-revalidate=600');
    return res.end(inject(html, headFor(kind, d, slug)));
  } catch(e){
    console.error('[api/parivar]', kind, slug, e && e.message);
    res.setHeader('Cache-Control', 'public, s-maxage=60');
    return res.end(html);   // never worse than the plain page
  }
};
