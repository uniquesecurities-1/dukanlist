# DukanList — Branded Auth Emails Setup Guide

**Total time:** 30 min (one-time)
**Result:** Customer emails come from `noreply@dukanlist.com` with DukanList branding instead of generic Supabase emails

---

## **Phase 1 — Resend account (5 min)**

1. Open https://resend.com → **Sign up** (use Google with `mstock2424@gmail.com`)
2. Free tier: 100 emails/day, 3000/month — enough for launch
3. After signup, go to **API Keys** in left sidebar → **Create API Key**
   - Name: `DukanList Production`
   - Permission: Full access
   - Click **Add** → **Copy the key** (starts with `re_`)
   - ⚠️ **Save this key in a password manager NOW** — it won't be shown again

---

## **Phase 2 — Verify dukanlist.com domain (10 min)**

1. Resend Dashboard → **Domains** → **Add Domain**
2. Enter: `dukanlist.com` → **Add**
3. Resend will show 3 DNS records to add:

   | Type | Name | Value |
   |---|---|---|
   | TXT | `send` | `v=spf1 include:amazonses.com ~all` |
   | TXT | `resend._domainkey` | (long DKIM key — copy from Resend) |
   | MX  | `send` | `feedback-smtp.us-east-1.amazonses.com` priority 10 |

4. Open **Cloudflare** dashboard → `dukanlist.com` → **DNS → Records**
5. Click **Add record** for each row above:
   - Type, Name, Content from the table
   - **Proxy status: DNS only (gray cloud)** for all
   - Save each
6. Back in Resend → click **Verify Domain** (wait 1–5 min for DNS propagation)
7. Green checkmarks ✅ next to each record = verified

---

## **Phase 3 — Supabase Custom SMTP (3 min)**

1. Supabase Dashboard → DukanList project → **Authentication → Emails** (or SMTP Settings)
2. Toggle **Enable Custom SMTP** ON
3. Fill in:

   | Field | Value |
   |---|---|
   | **Sender email** | `noreply@dukanlist.com` |
   | **Sender name** | `DukanList` |
   | **Host** | `smtp.resend.com` |
   | **Port** | `465` |
   | **Username** | `resend` |
   | **Password** | (paste your `re_xxx` API key) |
   | **Minimum interval** | `1` second |

4. **Save**

---

## **Phase 4 — Paste 4 email templates (10 min)**

Supabase Dashboard → **Authentication → Email Templates**

For each template below, click the template name → erase existing HTML → paste the new one → update Subject → **Save**:

| Template | File | Subject |
|---|---|---|
| Confirm signup | `01-confirm-signup.html` | `Confirm your DukanList account ✉️` |
| Reset Password | `02-reset-password.html` | `Reset your DukanList password 🔑` |
| Magic Link | `03-magic-link.html` | `Your DukanList sign-in link ✨` |
| Change Email Address | `04-change-email.html` | `Confirm your new DukanList email ✉️` |

All files are in this `email-templates/` folder of the repo. Open each in any text editor, copy entire content, paste in Supabase's HTML editor.

---

## **Phase 5 — URL Configuration (2 min) — CRITICAL**

Supabase Dashboard → **Authentication → URL Configuration**

1. **Site URL:**
   ```
   https://dukanlist.com
   ```
2. **Redirect URLs** — add each:
   ```
   https://dukanlist.com/**
   https://dukanlist.com/admin/login
   https://dukanlist.com/panel/login.html
   https://dukanlist.com/panel/reset-password.html
   https://dukanlist.com/panel/dashboard.html
   https://dukanlist.com/panel/claim-account.html
   ```
3. **Save**

---

## **Phase 6 — Test (5 min)**

1. **Forgot password test:**
   - Go to `https://dukanlist.com/panel/login.html`
   - Click **Forgot password?**
   - Enter `singla223377@gmail.com`
   - Click **Send Reset Link**
   - Check inbox: email should arrive **from noreply@dukanlist.com** with DukanList branding (orange gradient header)
   - Click button → lands on `dukanlist.com/panel/reset-password.html` (NOT localhost)

2. **Signup confirmation test (after Phase 7 is done):**
   - Use a fresh email to register a fake shop
   - Submit registration
   - Check inbox → confirmation email with DukanList branding
   - Click "Confirm My Email" → lands on dukanlist.com

---

## **Phase 7 — Re-enable email confirmation (production security)**

1. Supabase Dashboard → **Authentication → Providers → Email**
2. **Confirm email** toggle **ON**
3. **Save**

Now: new signups MUST confirm email before login. Old users already confirmed will continue to work normally.

---

## **Troubleshooting**

**Issue:** Email lands in Spam folder
- **Fix:** Add SPF + DKIM correctly (Phase 2). Once Resend shows "Verified" the deliverability is excellent.

**Issue:** "Failed to send password recovery: email rate limit exceeded"
- **Fix:** Supabase Dashboard → Authentication → **Rate Limits** → increase Email rate limit (default 4/hour → set to 50/hour)

**Issue:** Email still comes from `mail.app.supabase.io`
- **Fix:** Custom SMTP toggle not saved. Re-check Phase 3. Logout/relogin to Supabase Dashboard sometimes helps.

**Issue:** "localhost" in email link
- **Fix:** Site URL not set. See Phase 5.

---

## **Cost forecast**

| Volume | Resend Cost |
|---|---|
| 0–3,000 emails/month | **Free** |
| 3,000–50,000 emails/month | $20/mo (Pro plan) |
| 50,000+ | $80/mo |

For launch + first 6 months you're easily on **free tier** (typical local directory at this scale sends < 1000 emails/month).

---

**One-time setup. Done.** 🚀
