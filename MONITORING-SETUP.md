# DukanList — Monitoring & Alerting Setup

**Last updated: 2026-06-04**

Aapke paas 4 monitoring layers hain. Layer 1 zero setup ke saath kaam karta hai — bas db/97 run karna. Baaki 3 free third-party services hain jinme aap apne accounts banao to powerful tools mil jaate hain.

---

## Layer 1 — Self-hosted Error Capture ✅ (READY, no account needed)

**Kya capture hota hai:**
- Har page pe uncaught JS errors
- Unhandled promise rejections
- Server-side errors (Vercel function failures)
- Manual reports via `window.__dukanReport()`

**Storage:** Supabase `error_logs` table (auto-pruned 30 days)
**Cost:** ₹0
**Setup:**
1. Supabase SQL Editor me **`db/97-monitoring-error-logs.sql`** paste karke RUN karein
2. Push code (`quick-push.bat`)
3. Visit `https://dukanlist.com/admin/monitoring.html` — last 24h ke errors dikhne lagenge

**Where to view:** `/admin/monitoring.html`
**Privacy:** No PII captured. IPs are SHA-256 hashed with daily-rotating salt.

---

## Layer 2 — Health Endpoint + UptimeRobot ⏰ (free, 5 min setup)

**Kya hota hai:** Har 5 minute me ek bot aapke site ko hit karta hai. Site down ho gayi to instant email/SMS/WhatsApp alert.

**Endpoint already deployed:** `https://dukanlist.com/api/health`
Returns JSON: `{ ok: true, checks: { supabase: {...}, runtime: {...} } }`

### Setup (5 minutes):

1. https://uptimerobot.com pe free account banao
2. Dashboard → **+ Add New Monitor**
3. Settings:
   - **Monitor Type:** HTTP(s)
   - **Friendly Name:** DukanList Health
   - **URL:** `https://dukanlist.com/api/health`
   - **Monitoring Interval:** 5 minutes (free tier max)
   - **Monitor Timeout:** 30 seconds
   - **HTTP Method:** GET
4. **Advanced Options:**
   - **Keyword Monitoring:** Check "Keyword Exists"
   - **Keyword:** `"ok":true`
5. **Alert Contacts:** Add your email + (optional) WhatsApp Business webhook
6. **Save**

### Add 2 more monitors (recommended):
- Homepage: `https://dukanlist.com/` (keyword: `DukanList`)
- Search: `https://dukanlist.com/search.html` (keyword: `DukanList`)

**Alerts:** Email instant; SMS/WhatsApp on paid plan ($7/mo).
**Public status page:** UptimeRobot free tier deta hai — share kar sakte ho customers ko.

---

## Layer 3 — Vercel Analytics 📊 (1 toggle, free 2500 events/month)

**Already integrated:** Har public page me `` add ho gaya hai. Bas Vercel dashboard pe enable karna hai.

### Setup (1 minute):

1. https://vercel.com/dashboard pe login karo
2. **dukanlist** project → **Analytics** tab
3. **Enable Web Analytics** button click karo
4. Done — turant data aana shuru ho jayega

**Kya milta hai:**
- Page views (har page ka traffic)
- Top referrers (kahan se traffic aa raha — Google, WhatsApp, Instagram)
- Top countries / regions
- Devices (mobile/desktop split)
- Core Web Vitals (LCP, INP, CLS — Google ranking factors)

**Privacy:** No cookies, no personal tracking. GDPR-compliant.

---

## Layer 4 — Sentry (advanced, optional) 🛡️

**When to add:** Layer 1 enough hai ~95% cases ke liye. Sentry tab consider karein jab:
- Detailed source-map debugging chahiye
- Release tracking + git commit linking
- Performance traces (waterfalls, slow renders)
- Team multiple developers

### Setup (10 min, free 5K events/month):

1. https://sentry.io pe free account banao
2. **Create Project** → Platform: **JavaScript (Browser)**
3. **Copy the DSN** (looks like `https://abc...@o123.ingest.sentry.io/456`)
4. Add to Vercel env vars:
   - https://vercel.com/your-team/dukanlist/settings/environment-variables
   - Name: `NEXT_PUBLIC_SENTRY_DSN` (or just `SENTRY_DSN`)
   - Value: paste your DSN
   - Apply to: Production
5. Once you have a DSN, msg me — I'll add the `assets/js/sentry-loader.js` that conditionally loads Sentry only when DSN is set. (Keeping it conditional means we don't ship 50 KB of Sentry SDK to every visitor if you ever disable it.)

---

## Layer 5 — Supabase Logs Drain 🔬 (Pro plan only)

Supabase aapke Postgres logs (slow queries, failed RPCs, RLS violations) ko external destinations pe forward kar sakta hai.

### Free alternatives:
- **Supabase Pro Dashboard** me built-in Log Explorer — sufficient for most cases
- Filter logs: `level = 'ERROR'` ya `path = '/rest/v1/rpc/log_lead'` (slow queries)

### Paid setup (if you ever want):
- Datadog / Better Stack / Axiom — Supabase me "Log Drains" feature use karein
- Costs: ~₹500/month for typical traffic

---

## Reference — what each file does

| File | Purpose |
|------|---------|
| `db/97-monitoring-error-logs.sql` | Creates `error_logs` table + RPCs |
| `api/log-error.js` | Receives error reports from browser |
| `api/health.js` | Returns service health (used by UptimeRobot) |
| `assets/js/error-reporter.js` | Auto-mounted on every page; catches errors |
| `admin/monitoring.html` | Admin viewer with KPIs + grouped errors |

---

## Verify Layer 1 is working (after deploy + SQL applied)

1. Open `https://dukanlist.com/` in browser
2. Open DevTools Console
3. Run: `__dukanReport('test from console', { severity: 'info' })`
4. Open `https://dukanlist.com/admin/monitoring.html`
5. Refresh — apka test message visible hona chahiye

---

## Recommended priority order

If you have only 30 minutes:

1. ⭐⭐⭐ **Run db/97 in Supabase** (instant self-hosted error capture)
2. ⭐⭐ **Enable Vercel Analytics** (1-click, instant traffic insights)
3. ⭐⭐ **UptimeRobot setup** (5 min, instant downtime alerts)
4. ⭐ **Sentry** (10 min, only if Layer 1 not detailed enough later)

Aap 3-tier safety net mein ho — error capture + uptime + analytics, sab free.
