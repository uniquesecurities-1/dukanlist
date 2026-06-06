# Weekly Email Digest — Setup Guide

Every Monday at **8:00 AM IST**, every active shopkeeper on DukanList
gets a personalized email with their last week's performance and 2
suggested actions. Uses Resend SMTP (already verified for your domain
from previous Supabase auth-email setup).

## Phase 1 — Your one-time setup (10 minutes)

### Step 1: Get your Resend API key
1. Login to https://resend.com (you already have an account from the
   Supabase auth email setup).
2. Go to **API Keys** → **Create API Key**.
3. Name it `DukanList Backend - Digest`.
4. Permissions: **Sending access** → `Full access`.
5. Copy the key (starts with `re_...`). You'll need it next.

### Step 2: Verify the From address
Your previous Resend setup likely verified `dukanlist.com`. Confirm:
1. Resend dashboard → Domains → `dukanlist.com` should show **Verified**.
2. If not verified yet, follow the DNS records they provide (SPF + DKIM
   + DMARC). Cloudflare DNS setup takes ~10 min.

### Step 3: Generate the cron secret
Open a terminal on your computer and run:
```
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```
Copy the 64-char hex string. This is your `DIGEST_CRON_SECRET`.

### Step 4: Add 5 env vars to Vercel
1. Vercel dashboard → **dukanlist** project → **Settings** → **Environment Variables**.
2. Add these (all Production + Preview + Development scope):

| Name | Value | Notes |
|------|-------|-------|
| `SUPABASE_URL` | `https://qazuyygrpqopwygxmvwq.supabase.co` | Already there probably |
| `SUPABASE_SERVICE_ROLE_KEY` | (from Supabase dashboard → Project Settings → API → service_role secret) | **CRITICAL: secret, never expose client-side** |
| `RESEND_API_KEY` | `re_...` (from Step 1) | |
| `RESEND_FROM` | `DukanList <noreply@dukanlist.com>` | Must match verified domain |
| `DIGEST_CRON_SECRET` | (64-char hex from Step 3) | Random secret for manual trigger |

3. Click **Save**. Vercel auto-redeploys.

### Step 5: Run the SQL migration
1. Supabase dashboard → SQL Editor → **New query**.
2. Paste the contents of `db/45-email-digest.sql`.
3. Click **Run**.
4. Verify: `SELECT * FROM businesses WHERE email_digest_enabled = TRUE LIMIT 5;` should return rows.

### Step 6: Test with ONE owner first (your own shop)
On your computer, replace `<YOUR_SECRET>` and `<YOUR_OWNER_UUID>`:
```bash
curl -X POST "https://dukanlist.com/api/send-digest" \
  -H "x-cron-secret: <YOUR_SECRET>" \
  -H "content-type: application/json" \
  -d '{"owner_id":"<YOUR_OWNER_UUID>"}'
```
(Get your owner UUID from Supabase → `auth.users` table → your email row → `id`.)

Expected response: `{"sent":1,"skipped":0,"errors":[],"total_owners":1}`.

Check your inbox in 30 seconds. You should see a beautifully formatted
email with your shop's stats.

### Step 7: Test the cron itself
Vercel dashboard → your project → **Crons** tab should now show:
```
/api/send-digest    Every Monday 02:30 UTC (08:00 IST)
```
Click **Run Now** to test all owners (limit 10 first by adjusting the
SQL if you want).

## Phase 2 — Live

Once your test email looks good, that's it. Every Monday morning
shopkeepers will get their digest automatically.

## How shopkeepers opt out
- Footer of every digest has a link to `/panel/profile.html` where
  they can toggle "Weekly Digest" off.
- Calls `toggle_my_email_digest(business_id, FALSE)` RPC.
- Sets `businesses.email_digest_enabled = FALSE`.
- Next cron run skips them automatically.

## Costs
- Resend free tier: **3,000 emails/month** (100/day).
- At 50 active shops × 1 email/week = 200/month. Free tier covers it
  forever.
- Vercel cron: included in Hobby plan (1 cron per project).
- Total ongoing cost: **₹0/month** for the first ~700 active shops.

## What's in each email
- Shop name in header (saffron gradient)
- 3 stat tiles: Views, Calls+WhatsApp, New Reviews (with % vs last week)
- Suggested actions (top 2, data-driven from `owner_digest_data` RPC)
- Recent reviews this week (up to 3, with star ratings)
- Big CTA: "Open your dashboard →"
- Unsubscribe footer

## Customization later
- Edit `api/send-digest.js` `renderDigestHTML()` to change layout.
- Edit `db/45-email-digest.sql` `owner_digest_data()` to add new metrics.
- Change cron schedule in `vercel.json`: e.g., `"0 3 * * *"` = daily 3am UTC.
- Bilingual email: swap shop name + a few labels based on owner's
  preferred language (need to add `preferred_lang` column).

## Troubleshooting
- **`sent: 0` with errors**: check Vercel function logs for the actual
  Resend error. Most common: From address not verified, or rate limit.
- **No emails delivered**: check Resend dashboard → Logs. Spam folder.
- **Cron not running**: Vercel dashboard → Crons tab. If missing, push
  vercel.json change to trigger re-detection.
- **"Function does not exist"**: forgot Step 5 (SQL migration). Re-run.

## Future enhancements (when you want)
- Owner can choose Daily / Weekly / Monthly cadence
- A/B test subject lines (Resend has SegEvents)
- Click tracking on dashboard CTA
- "Top shops this week" public newsletter (separate API)
