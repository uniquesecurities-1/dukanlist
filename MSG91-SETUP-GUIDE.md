# MSG91 SMS Integration — Setup Guide

OTP-based mobile verification for DukanList using MSG91. Currently the
site uses WhatsApp-link verification (no OTP). MSG91 will give you a
proper 6-digit SMS OTP flow.

This guide is split into:
1. What you (user) need to do on MSG91 + DLT
2. What I (Claude) build once you share the API key

---

## Phase 1 — Your setup work (~2 hours, mostly waiting)

### Step 1: Create MSG91 account
1. Go to https://msg91.com/in/signup
2. Sign up with your Unique Securities business email
3. Verify email + phone

### Step 2: Add money to wallet
1. MSG91 dashboard → Wallet → Add money
2. Minimum ₹500. Each SMS costs ~₹0.20 (Transactional) or ₹0.12 (Promotional). 
3. ₹500 = ~2500 OTP messages = ~6 months of usage at current volume

### Step 3: DLT Registration (Telecom Compliance — MANDATORY in India)
DLT (Distributed Ledger Technology) registration is required by TRAI for
all commercial SMS in India. Without DLT, MSG91 won't send your SMS.

1. Pick ONE registrar (any works — Vi/Jio/Airtel/BSNL):
   - **Vi (Vodafone Idea)**: https://www.vilpower.in
   - Jio: https://trueconnect.jio.com
   - Airtel: https://www.airtel.in/business/airtel-iq

2. Register your entity (your firm name: DigiMutual Goals Pvt. Ltd.)
   - Upload: PAN, GST, Letter of Authorization
   - Cost: ₹0–5,900 depending on registrar
   - Takes 1–3 business days for approval

3. After entity approval, register a **Header (Sender ID)**:
   - 6-character alphabetic ID, e.g., `DUKLST` or `UNQSEC`
   - "DLT Principal Entity ID" + "Header" both needed
   - Approval: 1–2 days

4. Register your **Content Templates** (the exact SMS text MSG91 will send):
   - Variable spots use {#var#} syntax
   - Examples to register (copy-paste these):
     
     **Template 1 — OTP for shop registration:**
     ```
     {#var#} is your DukanList verification OTP. Valid 10 mins. 
     Do not share. - DukanList by DigiMutual Goals
     ```
     Variable: `{#var#}` = the 6-digit OTP
     
     **Template 2 — Welcome after register:**
     ```
     Welcome to DukanList! Your shop {#var#} is registered. 
     We'll verify in 24 hrs. - DukanList
     ```
     Variable: `{#var#}` = shop name
     
     **Template 3 — Status update:**
     ```
     Your DukanList shop is now LIVE. View: dukanlist.com/{#var#} 
     - DukanList
     ```
     Variable: `{#var#}` = shop slug

   - Approval: 2–4 hours each (usually fast)
   - Note the **DLT Template ID** for each (you'll need them in MSG91)

### Step 4: Connect DLT to MSG91
1. MSG91 dashboard → Settings → DLT Configuration
2. Enter your DLT Principal Entity ID + Header
3. Add the approved templates (paste DLT Template IDs from Step 3.4)
4. MSG91 will verify each template against the registrar

### Step 5: Get your MSG91 API Key
1. MSG91 dashboard → API → Auth Keys
2. Generate a new auth key with label "DukanList Backend"
3. Copy the key (looks like `4xx1234567abcd0987654321xyz`)
4. ALSO copy your sender_id (the 6-char header you registered, e.g., `DUKLST`)
5. ALSO copy each template_id for OTP / Welcome / Live

### Step 6: Share securely with me
Send via your Cowork chat (encrypted):
```
MSG91_AUTH_KEY  = <your key>
MSG91_SENDER_ID = DUKLST (or whatever you picked)
TEMPLATE_OTP    = <DLT template ID for OTP>
TEMPLATE_WELCOME = <DLT template ID for welcome>
TEMPLATE_LIVE   = <DLT template ID for live notification>
```

---

## Phase 2 — What I build (~1.5 hours after you share keys)

Once you share the credentials, I will:

1. **Add 3 env vars to Vercel** (you confirm in Vercel dashboard):
   - `MSG91_AUTH_KEY` (secret)
   - `MSG91_SENDER_ID` (public ok)
   - `MSG91_TEMPLATE_OTP_ID`, `MSG91_TEMPLATE_WELCOME_ID`, `MSG91_TEMPLATE_LIVE_ID`

2. **Create `/api/sms-send.js`** — Vercel serverless function
   - Accepts: `{mobile, type, vars}` where type = 'otp' | 'welcome' | 'live'
   - Picks the right template ID + fills variables
   - Calls MSG91 REST API
   - Returns: `{success: true, request_id}` or `{error}`
   - Server-side rate limiting (max 3 SMS per mobile per hour)

3. **Wire OTP flow into register.html Step 1:**
   - "Continue" button → calls `/api/sms-send` with OTP
   - New "Enter OTP" sub-step appears with 6-digit input
   - Verify locally + via Supabase RPC to mark mobile as verified
   - Stop spoofing: 3 wrong attempts → 30 min cooldown

4. **Welcome SMS** on successful submit (Step 4 final submit)
   - Fires after `register_business_v2` RPC succeeds
   - Sends shop name in the template

5. **Live notification SMS** when admin marks shop as live
   - Add trigger in `admin_approve_shop` RPC (or webhook)
   - Sends shop's public URL to owner

6. **Admin SMS log** in `/admin/activity.html`
   - Show every SMS sent: timestamp, mobile, template, status
   - Reuses existing `admin_audit_log` (just add 'sms_sent' actions)

---

## Phase 3 — Testing checklist (we do together)

- [ ] Test OTP delivery (send to your own mobile)
- [ ] Test wrong OTP entry (3x → cooldown)
- [ ] Test welcome SMS (register a test shop)
- [ ] Test live SMS (admin approve, owner gets SMS)
- [ ] Check MSG91 dashboard for delivery reports
- [ ] Verify wallet deduction matches our internal log

---

## Estimated costs (steady state)

Assuming ~50 new shop registrations / month:
- 50 × OTP attempts (avg 1.2 per shop) = 60 SMS
- 50 × Welcome SMS = 50 SMS
- 50 × Live notification SMS = 50 SMS
- Total: ~160 SMS/month × ₹0.20 = ~₹32/month
- Plus 1-time DLT registration: ₹0–5,900 (one-time)

Very economical compared to WhatsApp Business API (~₹0.40/message + setup
fee). Continue WhatsApp for unverified-side communication; SMS is for
the trust-critical OTP/Welcome/Live moments.

---

## Quick links
- MSG91 docs: https://docs.msg91.com
- DLT explainer: https://msg91.com/in/help/dlt-registration
- Vi DLT portal: https://www.vilpower.in
- TRAI rules: https://www.trai.gov.in

Once you complete Phase 1, just send me the keys and I'll ship Phase 2
in one session.
