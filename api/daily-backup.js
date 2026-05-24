// =====================================================
// api/daily-backup.js -- Daily auto-backup of critical tables
// =====================================================
// Triggered by Vercel cron at 03:00 IST daily (21:30 UTC previous day).
// Exports business/review/leads/deals data as JSON and uploads to
// Supabase Storage 'backups' bucket. Each backup is named
// dukanlist-YYYY-MM-DD.json.
//
// REQUIRED ENV VARS (already in Vercel from email digest):
//   SUPABASE_URL
//   SUPABASE_SERVICE_ROLE_KEY
//   DIGEST_CRON_SECRET  (reused for manual trigger auth)
//
// MANUAL TRIGGER (testing):
//   Invoke-RestMethod -Method Post -Uri 'https://dukanlist.com/api/daily-backup' \
//     -Headers @{'x-cron-secret' = '<DIGEST_CRON_SECRET>'}
// =====================================================

const SUPABASE_URL = process.env.SUPABASE_URL || '';
const SERVICE_KEY  = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const SECRET       = process.env.DIGEST_CRON_SECRET || '';

const TABLES = [
  { name: 'businesses',      select: '*' },
  { name: 'reviews',         select: 'id,business_id,customer_name,rating,text,status,created_at,owner_reply,owner_reply_at' },
  { name: 'leads_log',       select: 'id,business_id,action,created_at,ua_summary,city_from' },
  { name: 'deals',           select: '*' },
  { name: 'business_owners', select: 'business_id,auth_user_id,role,added_at' },
  { name: 'admin_audit_log', select: '*' },
  { name: 'announcements',   select: '*' }
];

export default async function handler(req, res){
  try {
    return await runBackup(req, res);
  } catch(e){
    try {
      return res.status(500).json({
        ok: false,
        error: 'unhandled_exception',
        detail: String(e && e.message || e)
      });
    } catch(_){
      return res.status(500).end('unhandled_exception');
    }
  }
}

async function runBackup(req, res){
  if (req.method !== 'POST' && req.method !== 'GET'){
    return res.status(405).json({ error: 'POST or GET' });
  }
  const isCron = !!req.headers['x-vercel-cron'];
  const secret = req.headers['x-cron-secret'] || (req.query && req.query.secret);
  if (!isCron && (!secret || secret !== SECRET)){
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!SUPABASE_URL || !SERVICE_KEY){
    return res.status(500).json({ error: 'Server not configured' });
  }

  const startMs = Date.now();
  const today = new Date().toISOString().slice(0, 10);
  const filename = 'dukanlist-' + today + '.json';

  const dump = { generated_at: new Date().toISOString(), tables: {} };
  const errors = [];

  for (const t of TABLES){
    try {
      let allRows = [];
      let from = 0;
      let serverTotal = null;
      const PAGE = 1000;
      while (true){
        const headers = {
          'apikey': SERVICE_KEY,
          'Authorization': 'Bearer ' + SERVICE_KEY,
          'Range': from + '-' + (from + PAGE - 1),
          'Range-Unit': 'items'
        };
        if (from === 0) headers['Prefer'] = 'count=estimated';
        const r = await fetch(
          SUPABASE_URL + '/rest/v1/' + t.name + '?select=' + encodeURIComponent(t.select),
          { headers: headers }
        );
        if (!r.ok){
          let body = null;
          try { body = await r.text(); } catch(_){}
          errors.push({ table: t.name, status: r.status, body: (body || '').slice(0, 200) });
          break;
        }
        if (serverTotal === null){
          const cr = r.headers.get('content-range') || '';
          const m = cr.match(/\/(\d+)\s*$/);
          if (m) serverTotal = parseInt(m[1], 10);
        }
        const rows = await r.json();
        if (!Array.isArray(rows) || rows.length === 0) break;
        allRows = allRows.concat(rows);
        if (rows.length < PAGE) break;
        from += PAGE;
        if (allRows.length > 50000){
          errors.push({ table: t.name, error: 'truncated at 50k rows' });
          break;
        }
      }
      dump.tables[t.name] = {
        count: allRows.length,
        server_total: serverTotal,
        rows: allRows
      };
    } catch(e){
      errors.push({ table: t.name, error: String(e && e.message || e) });
    }
  }

  const json = JSON.stringify(dump);
  const sizeBytes = Buffer.byteLength(json, 'utf-8');

  let uploadOk = false;
  let uploadErr = null;
  try {
    const upRes = await fetch(
      SUPABASE_URL + '/storage/v1/object/backups/' + filename,
      {
        method: 'POST',
        headers: {
          'apikey': SERVICE_KEY,
          'Authorization': 'Bearer ' + SERVICE_KEY,
          'Content-Type': 'application/json',
          'x-upsert': 'true'
        },
        body: json
      }
    );
    uploadOk = upRes.ok;
    if (!upRes.ok){
      try { uploadErr = await upRes.text(); } catch(_){ uploadErr = 'upload failed'; }
    }
  } catch(e){
    uploadErr = String(e && e.message || e);
  }

  try {
    await fetch(SUPABASE_URL + '/rest/v1/rpc/log_admin_action', {
      method: 'POST',
      headers: {
        'apikey': SERVICE_KEY,
        'Authorization': 'Bearer ' + SERVICE_KEY,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        p_action: 'daily_backup',
        p_target_type: 'storage',
        p_target_id: filename,
        p_target_name: 'Daily DB backup',
        p_details: {
          size_bytes: sizeBytes,
          tables_dumped: Object.keys(dump.tables).length,
          errors: errors.length,
          ok: uploadOk
        }
      })
    });
  } catch(_){}

  return res.status(uploadOk ? 200 : 500).json({
    ok: uploadOk,
    filename: filename,
    size_bytes: sizeBytes,
    size_kb: (sizeBytes / 1024).toFixed(1),
    tables: Object.fromEntries(Object.entries(dump.tables).map(function(kv){ return [kv[0], kv[1].count]; })),
    totals: Object.fromEntries(Object.entries(dump.tables).map(function(kv){ return [kv[0], kv[1].server_total]; })),
    errors: errors,
    duration_ms: Date.now() - startMs,
    upload_error: uploadErr
  });
}
