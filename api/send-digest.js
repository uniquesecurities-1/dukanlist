/* ============================================================
   /api/send-digest.js — Weekly email digest sender
   ============================================================
   Triggered by Vercel cron (every Monday 8am IST) OR manually
   via secret token. Loops through all opted-in active shop owners,
   generates a personalized HTML email with last-week metrics +
   suggested actions, sends via Resend.

   ENV VARS REQUIRED (set in Vercel dashboard):
     SUPABASE_URL              — same as client
     SUPABASE_SERVICE_ROLE_KEY — SECRET; never expose
     RESEND_API_KEY            — from https://resend.com/api-keys
     RESEND_FROM               — e.g., "DukanList <noreply@dukanlist.com>"
                                  (domain must be verified in Resend)
     DIGEST_CRON_SECRET        — random 32+ char string; required for manual trigger

   MANUAL TRIGGER (testing):
     curl -X POST "https://dukanlist.com/api/send-digest" \
       -H "x-cron-secret: YOUR_DIGEST_CRON_SECRET" \
       -H "content-type: application/json" \
       -d '{"owner_id":"<uuid>"}'    # optional: send to one owner only

   CRON TRIGGER (Vercel): auto-authenticated via x-vercel-cron header
============================================================ */

const REQUIRED_ENV = ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'RESEND_API_KEY', 'RESEND_FROM', 'DIGEST_CRON_SECRET'];

export default async function handler(req, res){
  // ---------- Method gate ----------
  if (req.method !== 'POST' && req.method !== 'GET'){
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // ---------- Auth gate ----------
  // Allow if: (a) Vercel cron header present, (b) secret matches, (c) admin token
  const isVercelCron = !!req.headers['x-vercel-cron'];
  const secret = req.headers['x-cron-secret'] || (req.query && req.query.secret);
  const authed = isVercelCron || (secret && secret === process.env.DIGEST_CRON_SECRET);
  if (!authed){
    return res.status(401).json({ error: 'Unauthorized' });
  }

  // ---------- Env check ----------
  const missingEnv = REQUIRED_ENV.filter(k => !process.env[k]);
  if (missingEnv.length){
    return res.status(500).json({ error: 'Missing env vars: ' + missingEnv.join(', ') });
  }

  const SUPABASE_URL = process.env.SUPABASE_URL;
  const SERVICE_KEY  = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const RESEND_KEY   = process.env.RESEND_API_KEY;
  const RESEND_FROM  = process.env.RESEND_FROM;

  // ---------- Optional single-owner test mode ----------
  let body = {};
  try { body = req.method === 'POST' ? (req.body || {}) : {}; } catch(_){}
  const singleOwnerId = body.owner_id || (req.query && req.query.owner_id) || null;

  // ---------- Fetch owners ----------
  let owners = [];
  try {
    const r = await fetch(SUPABASE_URL + '/rest/v1/rpc/list_active_owners_for_digest', {
      method: 'POST',
      headers: {
        'apikey': SERVICE_KEY,
        'Authorization': 'Bearer ' + SERVICE_KEY,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({})
    });
    if (!r.ok){
      const t = await r.text();
      return res.status(500).json({ error: 'Owner list fetch failed', detail: t.slice(0, 500) });
    }
    owners = await r.json();
    if (!Array.isArray(owners)) owners = [];
    if (singleOwnerId){
      owners = owners.filter(o => o.owner_id === singleOwnerId);
    }
  } catch(e){
    return res.status(500).json({ error: 'Owner list error', detail: String(e) });
  }

  if (!owners.length){
    return res.status(200).json({ sent: 0, message: 'No active opted-in owners to email' });
  }

  // ---------- Process each owner ----------
  let sent = 0, skipped = 0, errors = [];
  for (const o of owners){
    try {
      // Fetch digest data
      const dr = await fetch(SUPABASE_URL + '/rest/v1/rpc/owner_digest_data', {
        method: 'POST',
        headers: {
          'apikey': SERVICE_KEY,
          'Authorization': 'Bearer ' + SERVICE_KEY,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ p_business_id: o.business_id })
      });
      if (!dr.ok){ skipped++; continue; }
      const data = await dr.json();
      if (!data || !data.business_id){ skipped++; continue; }

      // Skip dead-week shops: 0 views AND 0 leads AND 0 new reviews
      const tw = data.this_week || {};
      const lw = data.last_week || {};
      const hasActivity = (tw.views|0) > 0 || (tw.leads|0) > 0 || (data.new_reviews|0) > 0
                       || (lw.views|0) > 0 || (lw.leads|0) > 0;
      // Always send for newly listed shops (first 30 days) to keep them engaged
      // For now: send to everyone — let opt-out be the gate

      const html = renderDigestHTML(data, o);
      const subj = renderSubject(data, o);

      // Send via Resend
      const er = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': 'Bearer ' + RESEND_KEY,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          from: RESEND_FROM,
          to: [o.owner_email],
          subject: subj,
          html: html
        })
      });
      if (!er.ok){
        const t = await er.text();
        errors.push({ email: o.owner_email, status: er.status, body: t.slice(0, 200) });
        continue;
      }
      sent++;
    } catch(e){
      errors.push({ email: o.owner_email, error: String(e) });
    }
  }

  return res.status(200).json({
    sent, skipped, errors: errors.slice(0, 10),
    total_owners: owners.length
  });
}

// ---------- Email rendering ----------
function renderSubject(d, owner){
  const tw = d.this_week || {};
  const v = tw.views | 0;
  const l = tw.leads | 0;
  const nr = d.new_reviews | 0;
  if (v === 0 && l === 0 && nr === 0){
    return 'Quiet week for ' + d.name + ' — boost it with these tips';
  }
  if (nr > 0){
    return '⭐ ' + nr + ' new review' + (nr === 1 ? '' : 's') + ' for ' + d.name + ' this week';
  }
  if (l > 0){
    return '📞 ' + l + ' lead' + (l === 1 ? '' : 's') + ' this week for ' + d.name;
  }
  return '👀 ' + v + ' people viewed ' + d.name + ' this week';
}

function esc(s){
  return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

function pctChange(current, previous){
  current = current | 0;
  previous = previous | 0;
  if (previous === 0) return current === 0 ? null : { sign: '+', pct: 100, color: '#059669' };
  const d = current - previous;
  const pct = Math.round((d / previous) * 100);
  if (pct === 0) return { sign: '', pct: 0, color: '#64748b' };
  return { sign: pct > 0 ? '+' : '', pct: pct, color: pct > 0 ? '#059669' : '#DC2626' };
}

function renderDigestHTML(d, owner){
  const SITE = 'https://dukanlist.com';
  const dashUrl = SITE + '/panel/dashboard.html';
  const tw = d.this_week || {};
  const lw = d.last_week || {};
  const viewsChange = pctChange(tw.views, lw.views);
  const leadsChange = pctChange(tw.leads, lw.leads);

  // Stat tile helper
  function tile(label, value, change, accent){
    const changeHTML = change
      ? '<div style="font-size:12px;color:' + change.color + ';font-weight:700;margin-top:4px">' + change.sign + change.pct + '% vs last week</div>'
      : '<div style="font-size:11px;color:#94a3b8;margin-top:4px">no data last week</div>';
    return ''
      + '<td valign="top" align="center" style="padding:18px 12px;background:#fff;border:1px solid #e2e8f0;border-radius:12px;width:33%">'
      +   '<div style="font-size:11px;font-weight:800;color:#64748b;text-transform:uppercase;letter-spacing:.06em;margin-bottom:6px">' + esc(label) + '</div>'
      +   '<div style="font-size:32px;font-weight:800;color:' + (accent || '#0F172A') + ';line-height:1;letter-spacing:-.02em;font-family:Arial,sans-serif">' + (value | 0) + '</div>'
      +   changeHTML
      + '</td>';
  }

  // Actions HTML
  let actionsHTML = '';
  const actions = Array.isArray(d.actions) ? d.actions : [];
  if (actions.length){
    actionsHTML = '<div style="margin-top:24px"><div style="font-size:13px;font-weight:800;color:#0F172A;margin-bottom:10px;text-transform:uppercase;letter-spacing:.04em">💡 Suggested next actions</div>';
    actions.forEach(a => {
      actionsHTML += '<a href="' + SITE + esc(a.link) + '" style="display:block;padding:13px 16px;background:#EFF6FF;border:1px solid #93C5FD;border-radius:10px;margin-bottom:8px;text-decoration:none;color:#1E40AF;font-weight:700;font-size:14px">→ ' + esc(a.msg) + '</a>';
    });
    actionsHTML += '</div>';
  }

  // Recent reviews HTML
  let reviewsHTML = '';
  const recent = Array.isArray(d.recent_reviews) ? d.recent_reviews : [];
  if (recent.length){
    reviewsHTML = '<div style="margin-top:24px"><div style="font-size:13px;font-weight:800;color:#0F172A;margin-bottom:10px;text-transform:uppercase;letter-spacing:.04em">⭐ New reviews this week</div>';
    recent.forEach(r => {
      const stars = '★'.repeat(r.rating | 0) + '☆'.repeat(5 - (r.rating | 0));
      reviewsHTML += '<div style="padding:12px 14px;background:#FFFBEB;border:1px solid #FCD34D;border-radius:10px;margin-bottom:8px">'
        + '<div style="color:#F59E0B;font-size:14px;font-weight:700;letter-spacing:2px">' + stars + '</div>'
        + (r.text ? '<div style="margin-top:5px;color:#0F172A;font-size:13px;line-height:1.4">"' + esc(r.text) + '"</div>' : '')
        + '<div style="margin-top:4px;color:#92400E;font-size:11px;font-weight:600">— ' + esc(r.customer_name || 'Customer') + '</div>'
        + '</div>';
    });
    reviewsHTML += '<a href="' + SITE + '/panel/reviews.html" style="display:inline-block;margin-top:4px;color:#1E40AF;font-size:13px;font-weight:700;text-decoration:none">Reply to reviews →</a></div>';
  }

  return ''
    + '<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Your weekly DukanList summary</title></head>'
    + '<body style="margin:0;padding:0;background:#f1f5f9;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Arial,sans-serif">'
    + '<div style="max-width:600px;margin:0 auto;padding:24px 16px">'
      + '<div style="background:linear-gradient(135deg,#FF6B1A,#E55100);color:#fff;padding:24px;border-radius:14px 14px 0 0">'
        + '<div style="font-size:14px;font-weight:600;opacity:.9">Your weekly summary · DukanList</div>'
        + '<div style="font-size:24px;font-weight:800;margin-top:4px;letter-spacing:-.02em">' + esc(d.name) + '</div>'
      + '</div>'
      + '<div style="background:#fff;padding:24px;border-radius:0 0 14px 14px;border:1px solid #e2e8f0;border-top:none">'
        + '<p style="margin:0 0 20px;color:#475569;font-size:15px;line-height:1.5">Here\'s how your shop performed in the <b>last 7 days</b>:</p>'
        + '<table cellpadding="0" cellspacing="6" border="0" width="100%" style="border-collapse:separate;border-spacing:6px"><tr>'
          + tile('Views',       tw.views, viewsChange, '#0F172A')
          + tile('Calls + WA',  tw.leads, leadsChange, '#FF6B1A')
          + tile('New reviews', d.new_reviews, null,   '#F59E0B')
        + '</tr></table>'
        + actionsHTML
        + reviewsHTML
        + '<div style="margin-top:28px;text-align:center">'
          + '<a href="' + dashUrl + '" style="display:inline-block;padding:14px 28px;background:linear-gradient(135deg,#FF6B1A,#E55100);color:#fff;text-decoration:none;border-radius:10px;font-weight:800;font-size:15px;letter-spacing:.01em">Open your dashboard →</a>'
        + '</div>'
        + '<div style="margin-top:28px;padding-top:20px;border-top:1px solid #e2e8f0;color:#94a3b8;font-size:11px;line-height:1.5;text-align:center">'
          + 'You\'re receiving this because you registered ' + esc(d.name) + ' on DukanList.<br>'
          + 'To stop these emails, go to <a href="' + SITE + '/panel/profile.html" style="color:#94a3b8">your profile</a> and turn off Weekly Digest.<br><br>'
          + '<a href="' + SITE + '" style="color:#94a3b8">dukanlist.com</a> · Mandi Dabwali · An initiative by Deepak Singla'
        + '</div>'
      + '</div>'
    + '</div></body></html>';
}
