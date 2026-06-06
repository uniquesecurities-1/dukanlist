# Backup + Custom URLs + Share Stats — Setup Guide

3 features shipped in this pack. 2 need one-time Supabase setup.

## A. Daily Auto-Backup

### How it works
Every day at 03:00 IST, Vercel cron hits `/api/daily-backup`. It exports
all critical tables (businesses, reviews, leads_log, deals,
business_owners, admin_audit_log, announcements) as a single JSON file
and uploads it to a Supabase Storage bucket called `backups`. Each
backup is named `dukanlist-YYYY-MM-DD.json`. Worst-case data loss
window is 24 hours.

### One-time Supabase setup (~3 min)

1. Supabase dashboard → **Storage**
2. **Create bucket** → name it **`backups`**
3. **CRITICAL: leave "Public bucket" UNCHECKED**. This bucket must be
   private — it contains personal data.
4. **Create bucket**
5. (Optional but recommended) Click the `backups` bucket → **Policies**
   tab → leave default RLS (only service_role can write)
6. (Optional) **Storage Settings** → enable file lifecycle: delete
   files older than 30 days. This caps storage cost.

### Test manually after deploy

```
curl -X POST https://dukanlist.com/api/daily-backup \
  -H "x-cron-secret: <your DIGEST_CRON_SECRET from email digest setup>"
```

Expect response:
```json
{
  "ok": true,
  "filename": "dukanlist-2026-05-24.json",
  "size_bytes": 12345,
  "tables": { "businesses": 5, "reviews": 0, ... },
  "errors": []
}
```

Check Supabase Storage → backups → file should appear.

### Verify cron registered

Vercel dashboard → your project → **Crons** tab. Should now show:
```
/api/send-digest    Mondays 02:30 UTC
/api/daily-backup   Daily 21:30 UTC (= 03:00 IST next day)
```

### Restore from backup (if ever needed)

1. Supabase Storage → backups → download the JSON for the date you want
2. The file is `{ generated_at, tables: { businesses: { count, rows }, ...} }`
3. Run a small Node/Python script to UPSERT rows back into the tables
   (only do this if accidental data loss happened — never run
   blindly, it can override good data)

---

## B. Custom Shop URLs

### What changed
Before: `https://dukanlist.com/business.html?slug=unique-fun`
After:  `https://dukanlist.com/unique-fun` (cleaner, more shareable)

Both URLs continue to work. The clean URL is just an alias — Vercel
rewrites it to `business.html?slug=unique-fun` server-side.

### No setup needed
The rewrite was added to `vercel.json`. Auto-active on next deploy.

### Safety guard
The rewrite only matches slugs that look like shop slugs:
- 3-60 characters
- Lowercase letters + digits + hyphens only
- Cannot start with a digit

This means /admin, /panel, /api, /search.html, /browse.html, all
existing pages keep working. Only truly unmatched paths fall to the
catch-all and become a shop lookup.

### How to use
You can now print **dukanlist.com/raju-kirana** on visiting cards,
shop banners, WhatsApp bios, anywhere. Much shorter and more
memorable than the `?slug=raju-kirana` version.

---

## C. Shareable Stats Card

### What it does
On a shopkeeper's panel/dashboard.html, a green **"📤 Share my
stats"** button now appears below the KPI grid. Click → modal opens
with a beautiful saffron-gradient SVG card showing their shop name +
this-week views, leads, rating.

Two share options:
1. **📱 Share on WhatsApp** — opens wa.me with a pre-filled message
   "🎉 [Shop Name] is on DukanList! 👀 250 views, 📞 18 calls.
   List your shop free → dukanlist.com/register"
2. **⬇ Download PNG** — saves the SVG as a 1200×630 PNG to their
   device. They can post it as a WhatsApp Status, Instagram story,
   etc.

### Why this drives growth
- Shopkeepers love bragging when they get views
- Friends see the stats card → want their own shop on DukanList
- Each shared card = a tiny ad that costs you ₹0
- 1200×630 dimensions are perfect for WhatsApp / Facebook / Twitter

### No setup needed
Just push the commit. The button appears automatically.

---

## Commit summary

This pack adds:
- `api/daily-backup.js` (~161 lines) — daily JSON backup serverless
- `vercel.json` — adds /:slug catch-all rewrite + daily-backup cron
- `panel/dashboard.html` — Share My Stats button + modal + SVG generator

After push:
1. Create `backups` private bucket in Supabase Storage (3-min)
2. Test backup manually with curl (1-min)
3. Verify cron in Vercel dashboard
4. Open your dashboard, click "Share my stats" — test the modal
