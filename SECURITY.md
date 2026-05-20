# 🛡️ DukanList Security Architecture

**Last audited:** 20 May 2026
**Compliance target:** DPDP Act 2023, OWASP Top 10, bank-level practices

This document describes the full security stack across **5 defence layers**.
Every public input passes through ALL of these before reaching the database.

---

## 🏗️ Defence Layers

```
┌─────────────────────────────────────────────────┐
│ LAYER 5: Monitoring & Audit                     │
│   • admin_audit_log (immutable)                 │
│   • admin_login_attempts                        │
│   • Pending count badge                         │
├─────────────────────────────────────────────────┤
│ LAYER 4: Bot & Abuse Protection                 │
│   • Honeypot fields (silent bot detection)      │
│   • Time-trap (< 3s submission rejected)        │
│   • Cloudflare Turnstile (optional, ready)      │
│   • Admin login lockout (5 fails / 15 min)      │
├─────────────────────────────────────────────────┤
│ LAYER 3: Browser & Transport                    │
│   • HTTPS-only (HSTS preload)                   │
│   • CSP (no inline JS execution from XSS)       │
│   • X-Frame-Options DENY on admin/panel         │
│   • Referrer-Policy strict                      │
│   • Permissions-Policy minimal                  │
├─────────────────────────────────────────────────┤
│ LAYER 2: Active Protection (DB)                 │
│   • Rate limiting per phone/IP/action           │
│   • Content sanitization (script-tag removal)   │
│   • Pincode-city validation                     │
│   • Duplicate phone block                       │
│   • Length limits on every field                │
├─────────────────────────────────────────────────┤
│ LAYER 1: Data Foundation                        │
│   • RLS on every table                          │
│   • SECURITY DEFINER RPCs gate operations       │
│   • Anon key only in client (RLS enforces)      │
│   • Phone hashing for reviews (anti-spam)       │
│   • CASCADE FK constraints                      │
└─────────────────────────────────────────────────┘
```

---

## 1️⃣ Data Foundation

### Row-Level Security (RLS) — all 13 tables
| Table | RLS | Public Read | Owner Read | Admin Only |
|-------|-----|-------------|------------|-----------|
| businesses | ✓ | active only | own (any status) | all |
| business_categories | ✓ | active biz | own | all |
| business_owners | ✓ | – | self | all |
| reviews | ✓ | active | own | all |
| leads_log | ✓ | – | own biz | all |
| flags | ✓ | – | – | admin SELECT |
| categories | ✓ | active | – | all |
| geo_* | ✓ | active | – | all |
| admin_users | ✓ | – | self | super_admin |
| admin_audit_log | ✓ | – | – | admin SELECT, no UPDATE/DELETE |
| admin_login_attempts | ✓ | – | – | RPC-only |
| rate_limits | ✓ | – | – | RPC-only |

### RPC Access Matrix
| RPC | Anon | Authenticated | Admin Check Inside |
|-----|------|---------------|---------------------|
| register_business_public | ✓ | ✓ | — |
| log_lead | ✓ | ✓ | — |
| submit_review | ✓ | ✓ | — |
| search_businesses | ✓ | ✓ | — |
| get_business_categories | ✓ | ✓ | — |
| public_rate_check | ✓ | ✓ | — |
| sanitize_user_text | ✓ | ✓ | — |
| record_admin_login_attempt | ✓ | ✓ | — |
| check_admin_lockout | ✓ | ✓ | — |
| claim_business_by_phone | — | ✓ | — |
| get_owner_analytics | — | ✓ | owner check |
| is_admin | — | ✓ | — |
| get_admin_stats | — | ✓ | ✓ |
| get_admin_profile | — | ✓ | — |
| admin_list_businesses | — | ✓ | ✓ |
| admin_list_all_businesses | — | ✓ | ✓ |
| admin_approve_business | — | ✓ | ✓ + audit log |
| admin_reject_business | — | ✓ | ✓ + audit log |
| admin_delete_business | — | ✓ | ✓ + audit log |
| admin_resolve_flag | — | ✓ | ✓ |
| admin_bulk_register | — | ✓ | ✓ |
| log_admin_action | — | — | internal only |
| check_rate_limit | — | — | internal only |

---

## 2️⃣ Active Protection (DB)

### Rate Limits (per identifier per action)
| Action | Window | Max | Block Duration |
|--------|--------|-----|----------------|
| Public registration | 1 hour | 3 per phone | 2 hours |
| Review submission | (future) | 1 per phone per business | — |
| Lead log | (future) | 50 per IP per day | — |
| Flag report | (future) | 5 per phone per day | — |
| Admin login | 15 min | 5 failures | 30 min |

### Content Sanitization
The `sanitize_user_text()` PL/pgSQL function strips at write-time:
- `<script>` tags (any case, multiline)
- `<iframe>`, `<object>`, `<embed>`, `<form>`, `<link>`, `<meta>`, `<style>`, `<svg>`
- All `on*=` event handlers (`onclick=`, `onload=`, etc.)
- `javascript:`, `data:`, `vbscript:` URL schemes

Applied to: name, name_hi, owner_name, address_line1, address_line2, usp_text, usp_hi.

### Direct INSERT lockdown
Old policy `p_biz_insert` removed. All inserts to `businesses` MUST go through:
- `register_business_public` (anon path)
- `register_business_v2` (authenticated path, legacy)
- `admin_bulk_register` (admin path)

Direct table insert from any client = blocked by RLS.

---

## 3️⃣ Browser & Transport (vercel.json)

| Header | Value | Purpose |
|--------|-------|---------|
| Strict-Transport-Security | 2-year preload | Force HTTPS |
| X-Content-Type-Options | nosniff | Prevent MIME-type confusion |
| X-Frame-Options | SAMEORIGIN (DENY for admin/panel) | Clickjacking |
| Referrer-Policy | strict-origin-when-cross-origin | Privacy |
| Permissions-Policy | minimal | Disable unused APIs |
| Content-Security-Policy | self + trusted CDNs only | XSS containment |
| Cross-Origin-Opener-Policy | same-origin-allow-popups | Spectre defence |
| Cross-Origin-Resource-Policy | same-site | Resource isolation |

CSP allowed sources:
- Scripts: self, cdn.jsdelivr.net (Supabase, Chart.js), cdnjs.cloudflare.com, challenges.cloudflare.com (Turnstile)
- Styles: self + fonts.googleapis.com
- Images: self, data:, blob:, https: (allows Supabase Storage)
- Connections: self + Supabase REST + Supabase realtime (wss)

---

## 4️⃣ Bot & Abuse Protection

### Honeypot (active by default)
Two invisible fields (`hp_website`, `hp_company`) in register.html.
- Real users can't see them (position absolute, off-screen, opacity 0, pointer-events: none).
- Form-filling bots fill ALL fields → trigger detection.
- If either field has a value at submit → silent rejection.

### Time-trap (active by default)
- Form load timestamp recorded in hidden field at DOMContentLoaded.
- If submission is < 3 seconds after load → bot rejected.
- Real humans always take > 3 seconds.

### Cloudflare Turnstile (optional — ready to enable)
The CAPTCHA infrastructure is wired but inactive by default.

**To enable:**
1. Go to https://dash.cloudflare.com → Turnstile → "Add Site"
2. Domain: `dukanlist.com` (or test subdomain first)
3. Widget mode: **Invisible** (best UX)
4. Copy the **Site Key** and **Secret Key**
5. In Vercel dashboard → Project → Settings → Environment Variables:
   - Add `TURNSTILE_SECRET_KEY` = your secret key
   - Redeploy
6. In `register.html`, add Site Key constant near the top (commented placeholder is included):
   ```js
   const TURNSTILE_SITE_KEY = '0x4AAAAAAAxxxxxxxx';  // your site key
   ```
7. Uncomment the Turnstile loader script block (see comment in register.html).

When configured, `register.html` will:
- Load Turnstile widget invisibly
- Get token before submission
- POST token to `/api/verify-turnstile`
- Block submission if Turnstile rejects

When NOT configured: `/api/verify-turnstile` returns `{ success: true, skipped: true }` and registration proceeds with honeypot + time-trap protection only.

### Admin Login Lockout
- Tracks failed login attempts in `admin_login_attempts` table.
- After 5 failures in 15 min for same email/phone → locked for 30 min.
- `check_admin_lockout()` RPC returns unlock timestamp; admin/login.html should check before sending OTP.

---

## 5️⃣ Monitoring & Audit

### admin_audit_log (immutable)
Every administrative action writes a row:
- `admin_user_id` — who did it
- `action` — what they did (`approve_business`, `reject_business`, `delete_business`, etc.)
- `target_type` + `target_id` + `target_name` — what they acted on
- `details` (JSONB) — action-specific metadata
- `created_at` — when

**Immutability:** No RLS policy allows UPDATE or DELETE. INSERT only via `log_admin_action()` SECURITY DEFINER RPC. Read-access restricted to admins via SELECT policy.

**Useful queries:**
```sql
-- All admin actions in last 24 hours
SELECT * FROM admin_audit_log
WHERE created_at > NOW() - INTERVAL '1 day'
ORDER BY created_at DESC;

-- All deletions ever
SELECT * FROM admin_audit_log
WHERE action = 'delete_business';

-- Activity by specific admin
SELECT * FROM admin_audit_log
WHERE admin_user_id = 'UUID-HERE'
ORDER BY created_at DESC;
```

### Backups
- `backup.bat` runs full project + database snapshot
- Recommended frequency: weekly (Windows Task Scheduler)
- Monthly: full Supabase `pg_dump` via dashboard
- See `LAUNCH-GUIDE.md` for details

---

## 🚦 Threat Model — What We Defend Against

| Threat | Defence |
|--------|---------|
| **SQL injection** | Parameterised queries via Supabase client; no raw SQL in frontend |
| **XSS (stored)** | Content sanitization at write + escape on render + CSP |
| **XSS (reflected)** | CSP blocks inline JS; no `eval`; no `innerHTML` of URL params |
| **CSRF** | SameSite cookies via Supabase auth; no state-changing GETs |
| **Clickjacking** | X-Frame-Options DENY on admin/panel pages |
| **Brute force admin** | Lockout after 5 failures in 15 min |
| **Mass spam registration** | Rate limit 3/phone/hour + honeypot + time-trap |
| **Fake reviews** | Phone hash unique per business + admin moderation |
| **Account takeover** | OTP-based phone auth + Supabase session security |
| **Data leak via API** | RLS enforces row visibility per user |
| **Admin action denial** | Audit log proves who did what |
| **MITM** | HSTS forces HTTPS; preload list submission optional |
| **Cookie theft** | HttpOnly + SameSite + Secure flags from Supabase |

---

## 📋 Pre-Launch Security Checklist

Run these before announcing public launch:

- [ ] All SQL migrations 01-17 applied (`SELECT proname FROM pg_proc` to verify)
- [ ] Vercel deployed with latest `vercel.json` (test headers at securityheaders.com)
- [ ] HTTPS works on dukanlist.com + www subdomain
- [ ] Admin login lockout tested (try 6 wrong OTPs)
- [ ] Registration rate limit tested (4th registration in hour rejected)
- [ ] Honeypot tested (fill hidden field via DevTools → reject)
- [ ] Time-trap tested (submit < 3s → reject)
- [ ] XSS test on USP field: `<script>alert(1)</script>` → sanitised, no script runs
- [ ] CSP scoring at observatory.mozilla.org → grade A
- [ ] securityheaders.com → grade A or A+
- [ ] No service_role keys in client (`grep -r "service_role" assets/`)
- [ ] Direct INSERT to businesses table blocked (try via Supabase SQL Editor as anon)
- [ ] Audit log captures admin actions (approve a test shop, check `admin_audit_log`)
- [ ] Backup tested (run `backup.bat`, verify files in `E:\backups\`)

---

## 🆘 Incident Response

If something looks wrong (e.g., suspicious admin activity, mass spam):

1. **Check audit log:**
   ```sql
   SELECT * FROM admin_audit_log
   WHERE created_at > NOW() - INTERVAL '24 hours'
   ORDER BY created_at DESC;
   ```

2. **Check pending registrations spike:**
   ```sql
   SELECT DATE_TRUNC('hour', created_at), COUNT(*)
   FROM businesses
   WHERE created_at > NOW() - INTERVAL '24 hours'
   GROUP BY 1 ORDER BY 1 DESC;
   ```

3. **Check rate-limit hits:**
   ```sql
   SELECT key, action, count, blocked_until
   FROM rate_limits
   WHERE blocked_until > NOW()
   ORDER BY count DESC;
   ```

4. **Block specific phone (manual):**
   ```sql
   UPDATE businesses SET status = 'banned'
   WHERE mobile = 'BAD-MOBILE-HERE';
   ```

5. **Lock admin account:**
   - Delete the row from `admin_users` table.
   - Or in Supabase Auth → Users → disable user.

6. **Mass cleanup:**
   - Bulk delete suspicious shops via Supabase Table Editor (filter then delete).

---

## 📞 Reporting Security Issues

If you find a vulnerability:
- Email: privacy@dukanlist.com
- Phone/WhatsApp: +91 95412 23377

Please do NOT disclose publicly until we have fixed it.

---

**Site managed by:** DigiMutual Goals Pvt. Ltd. · Mandi Dabwali, Haryana, India
**Security contact:** Deepak Singla (Founder / DPO)
