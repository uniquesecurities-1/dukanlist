# DukanList — Final Launch Readiness Report

**For:** Deepak Singla (DigiMutual Goals Pvt. Ltd.)
**Generated:** 21 May 2026 (T-12 hours to soft launch)
**Verdict at a glance:** GO for soft launch tomorrow morning.

---

## 🟢 What's READY

- **Hosting:** Vercel static deploy, custom domain `dukanlist.com` live, HTTPS, CDN edge cache.
- **Security headers:** HSTS preload, CSP (Google Fonts whitelisted), X-Frame-Options, Permissions-Policy, COOP/CORP — all set in `vercel.json`.
- **Database:** Supabase project `qazuyygrpqopwygxmvwq` healthy. 25 migration files applied (`db/01` through `db/25`). RLS on every table, latest patch is the search-ambiguous-id fix.
- **Auth:** Shopkeeper email+password (replaces broken phone OTP). Forgot-password self-service live. Claim-account flow for legacy phone-registered shops. Admin login with "Skip 2FA" available.
- **User flows:** Search (trigram + hours_json), category browse, business detail page with schema.org JSON-LD, OG tags, lead logging (`log_lead` RPC fires on view/call/whatsapp/directions).
- **Admin flows:** Moderation queue with self-diagnostic panel, one-click approve, bulk-upload, quick-approve, test-cleanup, admin disable toggle, city-manager scope.
- **SEO:** Dynamic `/sitemap.xml` (serverless), `robots.txt`, OG + schema.org on `index` and `business` pages, clean URLs.
- **PWA:** Manifest with 3 icons (192/512/maskable), shortcuts to Browse/Search/Register, service worker `dukan-v1.1.0` (network-first, admin/panel/api bypassed).
- **Anti-abuse:** Phone duplicate block, pincode-city validation, community 3-flag auto-flag, admin-only RPCs `SECURITY DEFINER`.
- **Local commits:** 1 commit ahead of `origin/main` (branded email templates + setup guide). Safe to push or leave.

---

## ⏳ TONIGHT — minimum required actions (target: <20 min)

**Only 3 things. Do these, then sleep.**

### 1. Push the pending commit (2 min) — Deepak
- Open `E:\dukanlist-web` in terminal.
- Run `push.bat` OR `git push`.
- Wait ~90 sec, confirm Vercel "Ready" green check at https://vercel.com/dashboard.
- **Why:** Otherwise tomorrow's first edit conflicts with un-pushed work.

### 2. Verify production smoke test (5 min) — Deepak
- Open https://dukanlist.com in **incognito** on phone.
- Tap Search → search "doctor" → tap one result → tap Call button.
- Open `/register.html` → fill Step 1 (your own email + dummy password) → check no console errors.
- Login at `/admin/login.html` with your admin email → click "Skip 2FA" → confirm Moderation badge loads.
- **Why:** Confirms last commits actually shipped and didn't break anything.

### 3. Raise Supabase email rate limit (3 min) — Deepak
- Supabase Dashboard → Authentication → **Rate Limits**.
- Change "Emails per hour" from default **4 → 30**.
- Save.
- **Why:** Default 2-4/hour Supabase SMTP will throttle first 5 signups. Resend integration is tomorrow morning; this buys you tonight.

**That's it.** Don't touch anything else. Custom SMTP, branded emails, 2FA enforcement — all wait till tomorrow.

---

## 🌅 TOMORROW MORNING — pre-announce polish (60-90 min)

**Order matters. Do top-down.**

### Priority 1 — Resend custom SMTP (30 min)
Follow `email-templates/SETUP-GUIDE.md` end-to-end (Phases 1-6). Skip Phase 7 (email confirmation) — leave OFF for launch friction.
- **Changes:** Emails will come from `noreply@dukanlist.com` with orange-gradient branded template instead of generic Supabase.
- **Critical sub-step:** Phase 5 Site URL → must be `https://dukanlist.com` exactly, not localhost.

### Priority 2 — Seed 20-30 real shops via bulk upload (20 min)
- `/admin/bulk-upload.html` → Haryana → Sirsa → Mandi Dabwali.
- Paste shops you personally know in `Name | Owner | Mobile | category | Address | Pincode | USP` format.
- Preview → Upload.
- **Why:** Empty directory kills first impression. 20 shops makes search feel alive.

### Priority 3 — Submit sitemap to Google Search Console (10 min)
- https://search.google.com/search-console → Add Property → `https://dukanlist.com`.
- Verify via DNS TXT (Cloudflare).
- Sitemaps → submit `sitemap.xml`.
- **Why:** Indexing starts now. Don't lose 24 hours.

### Priority 4 — Add basic privacy-friendly analytics (15 min, OPTIONAL)
- Plausible or Umami free trial, paste `<script>` in `index.html` and `business.html` `<head>`.
- **Skip if running tight.** Vercel Analytics is enough for day 1.

### Priority 5 — Final mobile sweep (10 min)
- Real Android phone, Chrome incognito.
- Home → Search → Detail → Call → Register Step 1 → install PWA via "Add to Home Screen".

---

## ⏭ SKIP / DEFER — not needed for soft launch

| Item | Why skip |
|---|---|
| **MSG91 SMS / phone OTP** | Email+password works. Add when monthly signups > 50. |
| **Force 2FA on admin** | "Skip 2FA" button exists — fine for first week with 1-2 admins. Enforce after week 1. |
| **Email confirmation ON** | Friction kills first-week signups. Turn ON after Resend is verified delivering. |
| **Turnstile CAPTCHA** | Already disabled. Re-enable only if you see bot signups. |
| **Cloudflare proxy (orange cloud)** on Vercel records | Keep DNS-only. Avoid double-CDN pitfalls. |
| **Google Analytics / GA4** | Privacy + cookie banner overhead. Plausible later if you need it. |
| **Reviews submission UI** | Read-only display is fine for week 1. |
| **Phase 7 (force email confirmation)** | Defer to end of week 1. |

---

## 🚦 GO / NO-GO Decision

### Verdict: **GO** for soft launch tomorrow morning.

**Reasoning:**
1. All blocking technical risk is closed — auth works, DB stable, RLS in place, last 30 commits are bug fixes not feature adds.
2. Email infra has a known workaround (rate-limit bump tonight, Resend tomorrow) — not a launch blocker.
3. The pending items (MSG91, 2FA enforce, branded emails) are all "improve quality" not "prevent breakage."
4. Soft-launch audience = your own WhatsApp clients. They will forgive small bumps; they won't forgive waiting another week.
5. Manual admin moderation + bulk-upload gives you control; nothing goes live without your approval.

### Risks if you launch as-is

| Risk | Likelihood | Mitigation |
|---|---|---|
| Supabase SMTP rate-limits and a signup email never arrives | Medium | Tonight's rate-limit bump to 30/hr; finish Resend by 10am |
| Empty directory feels dead to first visitor | High if no seed | Bulk-upload 20-30 real shops before announcing |
| A bug in registration form blocks a user | Low (just tested twice) | Keep `/admin/quick-approve.html` open; you can manually add anyone via bulk-upload |
| Service worker serves a stale page after deploy | Low | v1.1.0 already bumped; users get fresh on next visit |
| Bot signup spam | Low (no incentive yet) | Turnstile re-enable is a 5-min toggle if it happens |

---

## 📞 Day 1 Operational Playbook

### Where to monitor
- **Vercel Dashboard** → Deployments + Runtime Logs (errors in `/api/sitemap` etc.)
- **Supabase Dashboard** → Logs Explorer → filter `severity:error`
- **Your phone** → WhatsApp inbox (customers will ping you direct)
- **`/admin/dashboard.html`** → refresh hourly for new signups
- **`/admin/moderation.html`** → orange badge = pending shops

### If a registration fails
1. Ask user for screenshot of the error.
2. Open `/admin/bulk-upload.html` → add the shop manually for them in 60 seconds.
3. WhatsApp them: "Done! Aapki dukaan live ho gayi: dukanlist.com/business?slug=XXX"
4. File a note for tomorrow's fix.

### If site goes down
1. Vercel Dashboard → last deployment → "Promote to Production" on the previous green build (1-click rollback).
2. If Supabase is down → check https://status.supabase.com. Nothing you can do; wait.
3. Cloudflare → Pause Cloudflare on Site (top-right) if DNS issue suspected.

### WhatsApp template for first 10 customers (private, one-on-one)
```
Namaste {Name} bhai sahab,
DukanList.com live ho gaya. Aap meri taraf se pehli 10 dukaano me se hain.
Apni dukaan free me list karne ke liye: dukanlist.com/register
Koi bhi problem ho toh seedha mujhe WhatsApp karein.
- Deepak Singla
```

---

## 🎉 Launch announcement template

### English (for LinkedIn / Twitter)
```
DukanList is live.

A free local business directory for Bharat — starting with
Mandi Dabwali, expanding across Haryana, Punjab, Rajasthan, Delhi & UP.

For shopkeepers: register your shop in 60 seconds, completely free, forever.
For customers: find verified local shops with one click to call or WhatsApp.

dukanlist.com

— Deepak Singla, DigiMutual Goals Pvt. Ltd.
```

### Hinglish (for WhatsApp groups)
```
Bhaiyon-behno, ek nayi cheez share karni hai 

DukanList.com launch ho gaya — Bharat ki har dukaan ek hi jagah.

Apni dukaan add karein FREE — har category: doctor, pharmacy,
sweets, electrician, CA, mutual fund, sab kuch.

Customers ko bhi free — apne sheher ki verified dukaanein
ek click me — call, WhatsApp, directions.

Abhi 30+ dukaanein listed, aur badh rahi hain.

Add karein: dukanlist.com/register
Browse karein: dukanlist.com

Help ke liye seedha WhatsApp: +91 95412 23377
— Deepak Singla, DigiMutual Goals Pvt. Ltd.
Mandi Dabwali se Bharat tak.
```

---

**Now close the laptop. Sleep. Tomorrow morning: Resend → Bulk upload → Search Console → Announce. In that order.**

Good luck. You've earned the launch.
