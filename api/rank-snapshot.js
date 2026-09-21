// =====================================================
// api/rank-snapshot.js — weekly rank snapshot
// =====================================================
// Calls snapshot_all_ranks() (db/224), which records where every active shop
// stands this week within its own city + category.
//
// Why a snapshot at all: the rank itself is computed live, so without a
// stored history there is nothing to compare against and a shopkeeper can
// never be shown "you moved up two places". Movement is the part that
// actually motivates; a number that never visibly responds to effort stops
// being a reason to make any.
//
// Auth follows the same rule as api/daily-backup.js after the v227 fix: only
// a real shared secret counts. User-Agent and the x-vercel-cron header are
// client-controlled and are deliberately NOT trusted — anyone could have
// forged them and spammed snapshots, which would corrupt every "last week"
// comparison on the site.
//
// Scheduled from vercel.json.
// =====================================================

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://qazuyygrpqopwygxmvwq.supabase.co';
const SERVICE_KEY  = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const MANUAL_SECRET = process.env.DIGEST_CRON_SECRET || '';

module.exports = async (req, res) => {
  const authHeader = req.headers['authorization'] || '';
  const cronSecret = process.env.CRON_SECRET || '';
  const xCronSec   = req.headers['x-cron-secret'] || '';

  const isBearerCron   = cronSecret && authHeader === ('Bearer ' + cronSecret);
  const isManualSecret = MANUAL_SECRET && xCronSec === MANUAL_SECRET;

  if (!isBearerCron && !isManualSecret){
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }

  if (!SERVICE_KEY){
    // snapshot_all_ranks is deliberately revoked from anon and authenticated —
    // a shop's standing history is its own business — so this needs the
    // service role. Fail loudly rather than silently recording nothing.
    console.error('[rank-snapshot] SUPABASE_SERVICE_ROLE_KEY is not set');
    res.status(500).json({ error: 'Service role key not configured' });
    return;
  }

  try {
    const r = await fetch(SUPABASE_URL + '/rest/v1/rpc/snapshot_all_ranks', {
      method: 'POST',
      headers: {
        apikey: SERVICE_KEY,
        Authorization: 'Bearer ' + SERVICE_KEY,
        'Content-Type': 'application/json'
      },
      body: '{}'
    });

    const text = await r.text();
    if (!r.ok){
      console.error('[rank-snapshot] RPC failed', r.status, text.slice(0, 300));
      res.status(502).json({ error: 'Snapshot failed', status: r.status, detail: text.slice(0, 300) });
      return;
    }

    const rows = Number(text) || 0;
    console.log('[rank-snapshot] recorded standings for', rows, 'shops');
    res.status(200).json({ ok: true, shops: rows, at: new Date().toISOString() });

  } catch (e) {
    console.error('[rank-snapshot] threw:', e && e.message);
    res.status(500).json({ error: e && e.message });
  }
};
