# DukanList — System Architecture

**Last updated: 2026-06-04**
**Owner: Deepak Singla — DigiMutual Goals Pvt. Ltd. / Unique Securities**
**Live site: https://dukanlist.com**

This is the **single source of truth** for how DukanList runs. Read this before making any structural change.

---

## 1. The 30-second elevator pitch

DukanList is a **local business directory** for Sirsa / Bathinda / Mansa / Muktsar / Mandi Dabwali. Shopkeepers register their listing (free), customers find them via category + city + locality search, leave reviews, ask Q&A (Pucho Bhai), and get verified-trust signals. The whole stack is **serverless + zero-cost on the free tiers it currently uses**.

---

## 2. Tech stack

| Layer | Technology | Why |
|-------|-----------|-----|
| Frontend | Static HTML + vanilla JS (no framework) | Fast, deploy-anywhere, zero build step |
| CSS | Hand-written CSS + 2 polish layers (`admin-premium.css`, `public-premium.css`) | Brand-controlled, no bloat |
| Hosting | Vercel (free tier) | Auto-deploy on git push, CDN, serverless functions |
| Backend | Supabase (Pro plan, ~$25/mo) | Postgres + Auth + Storage + RLS |
| DNS | Cloudflare (free) | Fast DNS, future WAF/CDN |
| Email | Resend (free tier) | Transactional emails for digests / reset |
| SMS | MSG91 (DLT-registered) | Mobile OTP if enabled |
| WhatsApp | wa.me click-to-chat (free) | No Business API cost yet |
| Maps | OpenStreetMap iframe (free) | No Google Maps API quota worries |

---

## 3. Repository structure

```
E:\dukanlist-web\
├── *.html                          ← Public pages (index, browse, business, search, …)
├── admin/                          ← Admin panel (super_admin + city_moderator)
│   ├── dashboard.html              ← Today's Focus, KPIs, recent activity
│   ├── moderation.html             ← Pending business approvals + edit diffs
│   ├── shop.html                   ← Full shop editor (admin powers)
│   ├── broadcast.html              ← WhatsApp campaign tool
│   ├── monitoring.html             ← Client errors + health (db/97)
│   ├── duplicates.html             ← Fuzzy duplicate detection (db/99)
│   └── …
├── panel/                          ← Shopkeeper logged-in area
│   ├── dashboard.html              ← Owner home, profile completeness
│   ├── profile.html                ← Edit shop (locked identity fields)
│   ├── photos.html                 ← Upload via /api/upload-shop-photo
│   ├── analytics.html              ← Owner insights (trend, peak hours)
│   └── …
├── api/                            ← Vercel serverless functions (Node)
│   ├── admin-*.js                  ← Admin power tools
│   ├── upload-shop-photo.js        ← Server-side upload (bypasses RLS)
│   ├── log-error.js                ← Client error capture (db/97)
│   ├── health.js                   ← Service health for UptimeRobot
│   ├── send-digest.js              ← Weekly owner email digest (Vercel cron)
│   ├── daily-backup.js             ← Nightly Storage backup (Vercel cron)
│   └── …
├── assets/
│   ├── css/                        ← main.css + admin-premium + public-premium
│   ├── js/                         ← supabase-init, error-reporter, owner-notif, …
│   ├── data/categories.json        ← Static category tree (synced to DB)
│   ├── icons/                      ← Logo, favicons, PWA icons
│   └── og-default.png              ← Default share image
├── db/                             ← Numbered SQL migrations (run in order)
│   ├── 01-…
│   ├── 97-monitoring-error-logs.sql
│   ├── 98-review-spam-filter.sql
│   └── 99-duplicate-shop-detection.sql
├── promo/                          ← Marketing creatives + prompts
├── email-templates/                ← Branded Supabase auth emails
├── workers/                        ← Cloudflare Workers (image moderation)
├── *.bat                           ← Windows automation:
│                                     quick-push, push, backup-to-onedrive, backup
├── *.md                            ← Setup guides + this file
├── vercel.json                     ← Routes, rewrites, headers, CSP, crons
├── manifest.webmanifest            ← PWA manifest
└── sw.js                           ← Service worker (push notifications)
```

---

## 4. Domain model — the 12 critical tables

| Table | Purpose | Notes |
|-------|---------|-------|
| `businesses` | Master shop list | `status`: pending / active / disabled / rejected. `slug` unique. |
| `business_owners` | Links auth.users ↔ business | `auth_user_id` + `business_id` |
| `categories` | Parent + sub categories | `parent_id` self-FK. Also mirrored in `assets/data/categories.json` |
| `geo_cities` / `geo_localities` | Sirsa/Bathinda etc + areas inside | Slug-based filtering |
| `reviews` | Star ratings + comments | Trigger: spam filter (db/98) |
| `community_questions` / `community_replies` | Pucho Bhai | Phone hash, no login required |
| `leads_log` | Every WhatsApp / Call / Direction click | Drives owner analytics |
| `business_edits` | Audit log of every field change | Snapshot-based; admin can review pending edits |
| `flags` / `business_reports` | User-reported issues | Admin moderation queue |
| `admin_users` | Super_admin + city_moderator roles | `disabled` flag for suspend |
| `error_logs` | Client-side errors (db/97) | RPC-only access, daily-rotated IP hash |
| `duplicate_allowlist` | Confirmed non-duplicates (db/99) | Suppresses repeat flags |

---

## 5. Key RPCs (Supabase Postgres functions)

| RPC | Caller | What it does |
|-----|--------|--------------|
| `register_business(jsonb)` | anon → owner | Creates a shop + business_owners link |
| `update_my_business(jsonb)` | owner | Updates editable fields; locks name/email/mobile (db/91) |
| `log_lead(business_id, action)` | anon | Logs WhatsApp/call/directions click |
| `admin_dashboard_digest()` | admin | Today's Focus KPIs (db/94) |
| `admin_get_recent_errors(hours)` | admin | Monitoring viewer (db/97) |
| `admin_find_duplicate_shops(sim, limit)` | admin | Duplicate detection (db/99) |
| `get_owner_analytics()` | owner | Trend + peak hours + top searches |
| `get_owner_notifications()` | owner | Bell-icon notifications |
| `lookup_login_email_by_mobile(mobile)` | anon | Mobile-as-login (db/93) |
| `try_self_heal_owner_link(uuid)` | server (service-role) | Auto-link orphan businesses |
| `check_review_content(text)` | trigger | Spam filter (db/98) |
| `admin_get_flagged_reviews()` | admin | Flagged reviews queue (db/98) |

---

## 6. Auth flow

1. Shopkeeper registers via `register.html` → Supabase `auth.signUp({ email, password })` with `data.business_id` in metadata
2. Confirmation email goes via custom SMTP (branded). Link goes to `/panel/login.html?confirmed=1`
3. Confirmation triggers `auto_link_business_on_email_confirm()` trigger (db/90) which links auth.users → business_owners
4. Login: `panel/login.html` accepts email OR mobile (mobile → `lookup_login_email_by_mobile` RPC → email → standard signInWithPassword)
5. Sessions persisted in `localStorage` under `dukanlist_auth` key
6. Admin auth via `/admin/login.html`. Admin uses Supabase MFA (TOTP) for AAL2 — `aal2` required for sensitive RPCs (verified by `is_admin()` SQL function)

---

## 7. Critical environment variables (Vercel)

| Variable | Where | Used by |
|---------|-------|---------|
| `SUPABASE_URL` | Vercel env | All `/api/*` functions |
| `SUPABASE_ANON_KEY` | Vercel env | Public-side server reads |
| `SUPABASE_SERVICE_ROLE_KEY` | Vercel env | Admin functions only (NEVER client-side) |
| `RESEND_API_KEY` | Vercel env | `/api/send-digest`, `/api/admin-create-owner-account` (welcome email) |
| `MSG91_AUTH_KEY` | Vercel env | OTP sends (if enabled) |
| `TURNSTILE_SECRET` | Vercel env | Captcha verify on register |
| `LOG_IP_SALT` | Vercel env | Error log IP hashing (db/97) |

**⚠️ Never paste service-role key into HTML or JS files.** Service-role bypasses RLS — use only inside `/api/*`.

---

## 8. Deployment flow

```
Local edits in E:\dukanlist-web
        ↓
Double-click  quick-push.bat
        ↓
git add . + git commit + git push origin main
        ↓
GitHub webhook → Vercel
        ↓
Vercel builds + deploys (~1-2 min)
        ↓
Live at https://dukanlist.com

If new db/*.sql added:
   → Open Supabase dashboard → SQL Editor → paste → RUN
```

---

## 9. Backup strategy (3 layers — see BACKUP-SAFETY-GUIDE.md)

| Layer | Where | Frequency | Tool |
|-------|-------|-----------|------|
| 1. GitHub | github.com private repo | Every push | `quick-push.bat` |
| 2. OneDrive | OneDrive\DukanList-Backups | Weekly | `backup-to-onedrive.bat` |
| 3. Local | E:\backups\dukanlist | On-demand | `backup.bat` |
| 4. Database | Supabase Storage | Nightly 9:30 PM | `api/daily-backup.js` cron |
| 5. PITR | Supabase Pro | Always-on | Last 7 days continuous |

---

## 10. Monitoring (4 layers — see MONITORING-SETUP.md)

| Layer | What | Cost |
|-------|------|------|
| Self-hosted error capture | db/97 + `/api/log-error` + `assets/js/error-reporter.js` | ₹0 |
| `/api/health` endpoint | For UptimeRobot to ping | ₹0 |
| Vercel Analytics | Page views + Core Web Vitals | ₹0 (free tier) |
| Sentry (optional) | Advanced source-map debugging | ₹0 (5K events/month free) |

---

## 11. Disaster recovery playbooks

### "Live site is down" (white page or 500)
1. Open https://vercel.com/dashboard → dukanlist project → Deployments
2. Find the last GREEN deployment → click "..." → Promote to Production
3. Within 30 seconds the broken deploy rolls back

### "Database error / shop list empty"
1. Open https://supabase.com/dashboard/project/qazuyygrpqopwygxmvwq
2. Check **Database** → **Health** for outage
3. If query failing, check **Logs Explorer** → filter `level = ERROR`
4. If catastrophic, use Supabase PITR: Settings → Database → Point-in-Time Recovery → pick a time 30 min before incident

### "I broke a SQL migration"
1. Most migrations are idempotent — re-run is safe
2. If a table got corrupted: restore from `daily-backup.js` Storage dump (last 7 days kept)
3. Last resort: PITR snapshot

### "Customer complains login not working"
1. Check `admin/verification.html` — search by email
2. If `email_confirmed_at` is NULL → click "Force Verify Email"
3. If business_owners row missing → click "Link existing user" or "Create login account"
4. If mobile-as-login failing → check `db/93` diagnostic query (last lines of file) for duplicate mobile registrations

### "Photo upload failing for one shop"
1. Open the shop in `admin/shop.html`
2. The diagnostic card shows: auth user link, RLS status, owner record
3. Most fixes: click "Force-link owner" or check `try_self_heal_owner_link` ran

### "WhatsApp Broadcast batch failed mid-way"
1. Open `admin/broadcast.html` → Campaign History
2. Resume from where it stopped (already-sent rows are tracked via localStorage hash)
3. Watch the 200/day per-number quota — pause if WhatsApp warns

### "GitHub push failing"
1. Run `git pull origin main` first — someone else (or Vercel direct edit) may have pushed
2. If credentials expired: GitHub Desktop → reauth, or `gh auth login` in cmd
3. Last resort: `quick-push.bat` failure → push manually via GitHub Desktop

---

## 12. CSP + security headers (vercel.json)

DukanList serves with strict CSP:
- `script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://cdnjs.cloudflare.com https://challenges.cloudflare.com`
- `connect-src 'self' supabase + cloudflare + fonts + inputtools.google.com`
- `frame-src 'self' challenges.cloudflare.com www.google.com www.openstreetmap.org`

If you add a new third-party script/API, **update CSP in `vercel.json`** or browser will silently block it.

---

## 13. The "do not touch" list

These things look harmless but break critical flows if changed without thinking:

- **Vercel rewrite for `/:slug` regex** in `vercel.json` — controls clean URLs like `/sharma-medical`
- **`is_admin()` SQL function** — gate on every admin RPC. Defined in early db/ migration
- **`business_owners` table** — never delete rows manually; use `admin_delete_business` RPC
- **`vercel.json` JSON syntax** — broken JSON blocks the entire deploy. Always validate first
- **`assets/js/supabase-init.js`** — every page depends on it. Don't refactor the singleton
- **`status` enum on businesses** — has a CHECK constraint. Adding a new value needs a `ALTER TABLE` migration

---

## 14. Quick contacts / external accounts

| Service | URL | Login |
|---------|-----|-------|
| Vercel dashboard | https://vercel.com/dashboard | (your account) |
| Supabase dashboard | https://supabase.com/dashboard/project/qazuyygrpqopwygxmvwq | (your account) |
| GitHub repo | https://github.com/uniquesecurities-1/dukanlist | (your account) |
| Cloudflare DNS | https://dash.cloudflare.com | (your account) |
| Resend (email) | https://resend.com/dashboard | (your account) |
| MSG91 (SMS) | https://msg91.com/control | (your account) |
| Google Search Console | https://search.google.com/search-console | (your account) |
| OneDrive backups | `%OneDrive%\DukanList-Backups\` | local |

---

## 15. The cardinal rules

1. **Never paste service-role key into client-side code.** It bypasses RLS — anyone could nuke the DB.
2. **Always test SQL on Supabase Editor before pushing the file.** Cron crashes are silent.
3. **Vercel free tier has function execution limits.** Don't add expensive loops in `/api/*`.
4. **Categories live in 2 places** — `categories.json` (frontend) AND `categories` table (backend). Update both.
5. **Status changes are forever** — `disabled` shops still exist; only `delete` permanently removes (admin RPC).
6. **Push commit messages should be meaningful.** Use `push.bat` (prompts for message) for big changes, `quick-push.bat` (timestamp) for tiny ones.
7. **6 months from now you'll forget this.** That's why this doc exists. Update it when you change architecture.

---

## 16. Future ideas (parking lot)

- Cloudflare Workers AI image moderation (FREE tier covers 10K/day, easy add)
- Sentry advanced error tracking (free 5K events/month)
- UptimeRobot uptime alerts (free, 5-min interval)
- Owner lead inbox / mini-CRM (high retention value)
- Auto review-request via WhatsApp 24h after lead (review velocity)
- WhatsApp Cloud API integration (move from wa.me to conversational)
- Bilingual SEO landing pages per locality+category combo
- Performance pack v3 — WebP image conversion + critical CSS inline
- City-scoped admin badge counts in nav

Pick one when you have a free weekend.
