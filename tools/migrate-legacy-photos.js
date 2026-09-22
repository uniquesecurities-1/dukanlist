#!/usr/bin/env node
// =====================================================
// tools/migrate-legacy-photos.js — move Supabase-storage photos to Cloudinary
// =====================================================
// WHY
//   Two photo stores exist: business_photos (Cloudinary — thumbnails,
//   f_auto/q_auto, the panel's upload path since db/200) and the older
//   businesses.photos[] with raw Supabase-storage URLs from registration /
//   bulk upload. On 2026-09-22: 43 shops, 114 photos, legacy-only. Those
//   pages download full-size originals on mobile and cannot use the
//   w_160 thumbnails, "Set as Main", or the photo count in ranking v2.
//
// WHAT IT DOES, per legacy-only shop, per photo (in order):
//   1. Uploads the photo to Cloudinary (unsigned, same preset + folder the
//      panel uses: businesses/<business_id>). Tries the remote-URL form
//      first; if the preset refuses remote fetch, downloads the bytes and
//      uploads them.
//   2. Inserts a business_photos row (first photo is_featured).
//   3. Sets businesses.photos[] to the new Cloudinary URLs, in the same
//      order — the db/222 sync would otherwise keep the old URLs appended.
//   Old files in Supabase storage are NOT deleted. Do that by hand in the
//   dashboard after checking a few shops (bucket: shop-photos).
//
// SAFETY
//   * Default is DRY RUN: prints the plan, writes nothing anywhere.
//   * --apply does the work. --only=<slug> limits it to one shop (do this
//     first). --limit=N stops after N shops.
//   * Resumable: tools/.migrate-legacy-photos.state.json records every
//     legacy URL → Cloudinary URL. Re-running skips what is done; a crash
//     mid-shop leaves that shop's photos[] untouched (it is only rewritten
//     after every photo of the shop succeeded).
//   * Needs SUPABASE_SERVICE_ROLE_KEY in the environment for the writes
//     (RLS lets only the owner insert). The key never leaves your machine.
//
// RUN (Windows cmd, from E:\dukanlist-web):
//   node tools\migrate-legacy-photos.js                       (dry run)
//   set SUPABASE_SERVICE_ROLE_KEY=<key>
//   node tools\migrate-legacy-photos.js --apply --only=<slug>  (one shop)
//   node tools\migrate-legacy-photos.js --apply               (all)
// =====================================================
'use strict';
const fs   = require('fs');
const path = require('path');

const CFG = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'config', 'site.json'), 'utf8'));
const SUPABASE_URL = CFG.supabase.url;
const ANON_KEY     = CFG.supabase.anon_key;
const SERVICE_KEY  = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const CLOUD_NAME   = 'dukanlist';          // same as panel/photos.html
const PRESET       = 'dukanlist_shops';    // same as panel/photos.html
const STATE_FILE   = path.join(__dirname, '.migrate-legacy-photos.state.json');

const args   = process.argv.slice(2);
const APPLY  = args.includes('--apply');
const ONLY   = (args.find(a => a.startsWith('--only=')) || '').slice(7);
const LIMIT  = parseInt((args.find(a => a.startsWith('--limit=')) || '').slice(8), 10) || Infinity;

const isLegacy = (u) => typeof u === 'string' && u.includes('/storage/v1/object/public/');
const isCloud  = (u) => typeof u === 'string' && u.includes('res.cloudinary.com/');

function loadState(){ try { return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8')); } catch (_) { return { done: {} }; } }
function saveState(s){ fs.writeFileSync(STATE_FILE, JSON.stringify(s, null, 2)); }

async function sb(pathAndQuery, opts = {}, key = ANON_KEY){
  const r = await fetch(SUPABASE_URL + '/rest/v1/' + pathAndQuery, {
    ...opts,
    headers: { apikey: key, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json', ...(opts.headers || {}) }
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`Supabase ${r.status} on ${pathAndQuery.split('?')[0]}: ${text.slice(0, 200)}`);
  return text ? JSON.parse(text) : null;
}

async function cloudinaryUpload(legacyUrl, businessId){
  const endpoint = `https://api.cloudinary.com/v1_1/${CLOUD_NAME}/image/upload`;
  const common = { upload_preset: PRESET, folder: `businesses/${businessId}`, tags: 'migrated-legacy' };

  // Attempt A — let Cloudinary fetch the URL itself.
  let fd = new FormData();
  Object.entries(common).forEach(([k, v]) => fd.append(k, v));
  fd.append('file', legacyUrl);
  let r = await fetch(endpoint, { method: 'POST', body: fd });
  if (r.ok) return r.json();
  const errA = (await r.text()).slice(0, 160);

  // Attempt B — download the bytes, upload them.
  const src = await fetch(legacyUrl);
  if (!src.ok) throw new Error(`legacy file ${src.status}: ${legacyUrl}`);
  const blob = await src.blob();
  fd = new FormData();
  Object.entries(common).forEach(([k, v]) => fd.append(k, v));
  fd.append('file', blob, 'photo.jpg');
  r = await fetch(endpoint, { method: 'POST', body: fd });
  if (!r.ok) throw new Error(`Cloudinary refused both ways. remote: ${errA} | bytes: ${(await r.text()).slice(0, 160)}`);
  return r.json();
}

(async () => {
  if (APPLY && !SERVICE_KEY){ console.error('--apply needs SUPABASE_SERVICE_ROLE_KEY in the environment.'); process.exit(1); }

  const rows = await sb('businesses?select=id,slug,name,photos&photos=not.is.null&order=slug&limit=3000');
  const cloudRows = await sb('business_photos?select=business_id,cloudinary_url&limit=5000');
  const cloudBy = {};
  for (const c of cloudRows) (cloudBy[c.business_id] = cloudBy[c.business_id] || []).push(c.cloudinary_url);

  let shops = rows.filter(b => Array.isArray(b.photos) && b.photos.some(isLegacy));
  if (ONLY) shops = shops.filter(b => b.slug === ONLY);
  const totalPhotos = shops.reduce((n, b) => n + b.photos.filter(isLegacy).length, 0);
  console.log(`${APPLY ? 'APPLY' : 'DRY RUN'} — ${shops.length} shop(s), ${totalPhotos} legacy photo(s)` + (ONLY ? ` (only ${ONLY})` : ''));
  if (!shops.length) return;

  const state = loadState();
  let doneShops = 0, donePhotos = 0, failed = [];

  for (const b of shops){
    if (doneShops >= LIMIT) break;
    const legacy = b.photos.filter(isLegacy);
    const keepCloud = b.photos.filter(isCloud);              // shops with both: keep existing cloud ones first
    console.log(`\n${b.slug}  (${legacy.length} legacy${keepCloud.length ? ', ' + keepCloud.length + ' already cloud' : ''})`);
    if (!APPLY){ legacy.forEach(u => console.log('   would upload  ' + u.split('/').pop())); doneShops++; donePhotos += legacy.length; continue; }

    const newUrls = [];
    let ok = true;
    for (let i = 0; i < legacy.length; i++){
      const u = legacy[i];
      try {
        let rec = state.done[u];
        if (!rec){
          const up = await cloudinaryUpload(u, b.id);
          rec = { url: up.secure_url, public_id: up.public_id, delete_token: up.delete_token || null };
          const hasFeatured = (cloudBy[b.id] || []).length > 0;
          await sb('business_photos', { method: 'POST', headers: { Prefer: 'return=minimal' },
            body: JSON.stringify({ business_id: b.id, cloudinary_url: rec.url, cloudinary_public_id: rec.public_id,
                                   delete_token: rec.delete_token, is_featured: !hasFeatured && i === 0 }) }, SERVICE_KEY);
          state.done[u] = rec; saveState(state);
          console.log(`   ✓ ${i + 1}/${legacy.length}  ${rec.public_id}`);
        } else console.log(`   ↷ ${i + 1}/${legacy.length}  already migrated`);
        newUrls.push(rec.url);
        donePhotos++;
      } catch (e) {
        ok = false; failed.push({ slug: b.slug, url: u, error: e.message });
        console.log(`   ✗ ${i + 1}/${legacy.length}  ${e.message}`);
        break;                                              // leave this shop's photos[] as it was
      }
    }
    if (ok){
      const finalPhotos = keepCloud.concat(newUrls);
      await sb(`businesses?id=eq.${b.id}`, { method: 'PATCH', headers: { Prefer: 'return=minimal' },
        body: JSON.stringify({ photos: finalPhotos }) }, SERVICE_KEY);
      console.log(`   photos[] → ${finalPhotos.length} Cloudinary URL(s)`);
      doneShops++;
    }
  }

  console.log(`\n${APPLY ? 'Done' : 'Plan'}: ${doneShops} shop(s), ${donePhotos} photo(s)${failed.length ? `, ${failed.length} FAILED` : ''}`);
  if (failed.length){ console.log('\nFailed (re-run to retry; nothing was half-written):'); failed.forEach(f => console.log(`  ${f.slug}: ${f.error}`)); process.exitCode = 1; }
  if (APPLY && doneShops) console.log('\nNext: open 2-3 of these shops on the site, then delete the old files from Supabase Storage → shop-photos when satisfied.');
})().catch(e => { console.error('fatal:', e.message); process.exit(1); });
