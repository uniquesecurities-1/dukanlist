# 🏪 DukanList.com — Project Handover Document

> **Purpose**: Iss file me poora project context hai. Naye Cowork session me Claude ko bolo:
> **"Read E:\dukanlist-web\HANDOVER.md aur wahin se aage badho jahan chhoda tha"**
>
> Last updated: 19 May 2026

---

## 1️⃣ Project Identity

| Field | Value |
|---|---|
| **Project Name** | DukanList.com |
| **Tagline** | "Har Dukan, Ek Pehchan" (Every Shop, One Identity) |
| **Type** | Pan-India local business directory |
| **Origin City** | Mandi Dabwali, Haryana |
| **Domain** | `dukanlist.com` (purchased from Cloudflare Registrar) |
| **States Active** | 5 — Haryana, Punjab, Rajasthan, Delhi, UP |
| **Categories** | 15 starter (doctor, carpenter, plumber, lawyer, CA, sweets, etc.) |
| **Languages** | English (default) + Hindi toggle |
| **Pricing** | Free for shopkeepers, free for customers |
| **Trust Model** | Mobile OTP + Pincode-City match + Photo verification = 85% trust |
| **Approach** | Mobile-first PWA, vanilla HTML/CSS/JS (no framework) |

---

## 2️⃣ Business Owner Info

- **Founder**: Deepak Singla (singla223377@gmail.com)
- **Partner**: Navneet Singla (brother)
- **Registered Firm**: **DigiMutual Goals Pvt. Ltd.**
- **Local Brand**: Unique Securities
- **Address**: Unique Securities, SCO-01, Near IndusInd Bank, Aastha Hospital Street, Chotala Road, Mandi Dabwali-125104, District Sirsa, Haryana
- **AMFI ARN**: ARN-332982 (DigiMutual Goals Pvt. Ltd.)
- **Other Businesses**: MFDTools.com, Nivesheasy.com (Unique Securities — SEBI Authorised Person)

---

## 3️⃣ Tech Stack

- **Frontend**: Vanilla HTML/CSS/JS (no React/Vue/framework)
- **Backend**: Supabase (Postgres + Auth + Storage)
- **Auth**: Mobile OTP via Supabase Phone Auth (Twilio test mode)
- **Hosting**: Vercel (free tier, planned)
- **DNS**: Cloudflare
- **Storage**: Supabase Storage (`shop-photos` bucket, 2MB limit)
- **Search**: PostgreSQL `pg_trgm` + `unaccent` extensions (trigram, typo-tolerant)
- **i18n**: `data-i18n-en` / `data-i18n-hi` CSS toggle pattern

---

## 4️⃣ Supabase Project Credentials

> ⚠️ **`mfdtools-shop` project ka Supabase account is a SEPARATE Gmail alias account**: `singla223377+shop@gmail.com`
> (Main account `singla223377@gmail.com` already had 2 projects — MFDTools + Nivesheasy)

| Field | Value |
|---|---|
| **Supabase Account Email** | singla223377+shop@gmail.com |
| **Organization** | Shop Directory |
| **Project Name** | mfdtools-shop |
| **Project Ref** | `qazuyygrpqopwygxmvwq` |
| **Project URL** | `https://qazuyygrpqopwygxmvwq.supabase.co` |
| **Dashboard** | https://supabase.com/dashboard/project/qazuyygrpqopwygxmvwq |
| **Anon Public Key** | `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFhenV5eWdycHFvcHd5Z3htdndxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxNTUwOTEsImV4cCI6MjA5NDczMTA5MX0.FR8x2kldC2yelpPnK2QKd5WGwHUAQheCVmxfs6hR00I` |

### Phone Auth Test Mode

| Setting | Value |
|---|---|
| **Twilio Account SID** | `AC00000000000000000000000000000000` (dummy) |
| **Twilio Auth Token** | `00000000000000000000000000000000` (dummy) |
| **Message Service SID** | `MG00000000000000000000000000000000` (dummy) |
| **Test Phone** | `919541223377` (no + prefix) |
| **Test OTP** | `123456` |
| **Valid Until** | 31 Dec 2030 |

---

## 5️⃣ File Structure

```
E:\mfdtools-web\shop-project\          ← (move/rename to E:\dukanlist-web\ for fresh session)
│
├── HANDOVER.md                         ← THIS FILE
├── README.md                           ← Architecture + deployment guide
│
├── index.html                          ← Landing page (hero, search, 15 categories)
├── register.html                       ← 4-step registration (OTP → Details → Address → USP)
├── search.html                         ← Search results (query + category + city filters)
├── browse.html                         ← All 15 categories landing
├── business.html                       ← Public business profile (?slug=X)
│
├── panel/
│   ├── login.html                      ← Shopkeeper login via OTP
│   ├── dashboard.html                  ← Stats KPIs, badges, quick actions
│   └── photos.html                     ← Drag-drop uploader, auto-activates listing
│
├── assets/
│   ├── css/
│   │   └── main.css                    ← Saffron + indigo + emerald theme
│   ├── js/
│   │   ├── supabase-init.js            ← ✅ Live keys filled
│   │   ├── otp.js                      ← sendOTP, verifyOTP, isValidIndianMobile
│   │   └── geo.js                      ← loadStates, loadDistricts, cascading dropdowns
│   └── data/
│       └── categories.json             ← 15 categories with EN/HI names
│
└── db/
    ├── 01-schema.sql                   ← 12 tables (businesses, reviews, geo_*, etc.)
    ├── 02-rls-policies.sql             ← Row-Level Security
    ├── 03-seed-categories.sql          ← 15 categories
    ├── 04-seed-geo.sql                 ← 5 states, 49 districts, 12 cities, 10 localities
    ├── 05-rpc-functions.sql            ← 8 SECURITY DEFINER functions
    └── 06-storage-bucket.sql           ← shop-photos bucket + RLS
```

---

## 6️⃣ Database Schema (Verified ✅)

**12 Tables in Supabase**:
1. `geo_states` (5 rows) — Haryana, Punjab, Rajasthan, Delhi, UP
2. `geo_districts` (49 rows)
3. `geo_cities` (12 rows including Mandi Dabwali)
4. `geo_localities` (10 rows — Mandi Dabwali areas)
5. `categories` (15 rows — doctor, plumber, sweets, etc.)
6. `businesses` (main table — slug, name, status, photos JSONB, services_json JSONB, hours_json JSONB)
7. `business_owners` (auth_user_id → business_id link)
8. `reviews` (rating 1-5, customer reviews)
9. `leads_log` (call/whatsapp/directions tracking)
10. `flags` (community moderation — 3 flags → flagged status)
11. (Triggers): auto-update timestamps, recompute ratings, auto-flag threshold

**8 RPC Functions**:
- `generate_business_slug`
- `validate_pincode_city`
- `register_business` (atomic insert)
- `activate_business_after_photos`
- `search_businesses` (trigram-powered)
- `log_lead`
- `submit_review`
- `report_business`
- `get_public_stats`

**1 Storage Bucket**:
- `shop-photos` (public, 2MB limit, jpeg/png/webp)

---

## 7️⃣ ✅ Completed Steps (1-4 done)

| # | Step | Status |
|---|---|---|
| 1 | Supabase project created | ✅ Done |
| 2 | 6 SQL files executed | ✅ Done (verified 15/5/49/12/10/1) |
| 3 | Phone Auth Test Mode | ✅ Done (Phone provider Enabled) |
| 4 | URL + anon key in supabase-init.js | ✅ Done (this session) |

---

## 8️⃣ ⏳ Pending Steps (5-8) — RESUME HERE

| # | Step | Status |
|---|---|---|
| 5 | **Create GitHub repo** | ⏳ **NEXT** |
| 6 | Push code to GitHub | ⏳ |
| 7 | Vercel deploy | ⏳ |
| 8 | Cloudflare DNS → Vercel | ⏳ |

### Immediate Next Action:

**Step 5**: User to create GitHub repo at https://github.com/new
- Name: `dukanlist`
- Public, no README/license/.gitignore
- Then share the repo URL with Claude to get push commands

---

## 9️⃣ Important Decisions Already Made

1. **Domain strategy**: Direct on `dukanlist.com` (NOT a subdomain of mfdtools.com) — Strategy A chosen.
2. **Bilingual**: English DEFAULT, Hindi toggle (because shopkeepers + customers both comfortable with English UI but want Hindi readable).
3. **Free model**: 100% free for both shopkeepers and customers. No paid plans yet.
4. **Trust system**: 85% trust = Mobile OTP (35%) + Pincode-City match (25%) + Min 1 photo (25%). Verified badge shown.
5. **Anti-fake**: Community flag system — 3 flags → auto status `flagged` → admin review.
6. **No business_services table**: Services stored as JSONB in `businesses.services_json` (initial RLS bug fixed by removing references to non-existent table).
7. **Cascading address**: State → District → City → Locality (geo_* tables) for clean data.

---

## 🔟 Known Issues / Notes

- **Local testing via `file://`**: Categories.json fails to load due to CORS — this is NORMAL, will auto-fix on Vercel deploy.
- **Console errors when opening index.html directly**: Expected. Use `python -m http.server 8000` for proper local test, or just deploy to Vercel.
- **Supabase free tier**: Original Gmail account hit 2-project limit. Using `singla223377+shop@gmail.com` alias for this project.
- **Site previously branded as**: `shop.mfdtools.com` (was a subdomain plan). Rebranded across 9 HTML files to `dukanlist.com` (Dukan**List** with em-tag styling).

---

## 1️⃣1️⃣ How to Resume in Fresh Cowork Session

### Option A (Recommended): Move folder to its own home

1. **Move/Rename** the project folder:
   - From: `E:\mfdtools-web\shop-project\`
   - To: `E:\dukanlist-web\`
   - (Use Windows cut + paste, or right-click rename)

2. **Open NEW Cowork session** (Claude desktop app → New Project)

3. **Select folder**: `E:\dukanlist-web\`

4. **First message to Claude**:
   > "Read HANDOVER.md and continue from Step 5 (GitHub repo creation). Project is DukanList.com, a local business directory. Steps 1-4 done, now I need to push code to GitHub and deploy on Vercel."

5. Claude will read HANDOVER.md, confirm state, and give Step 5 instructions.

### Option B: Keep current folder, just open fresh session

1. Open new Cowork session
2. Select folder: `E:\mfdtools-web\` (the parent)
3. Tell Claude:
   > "DukanList project is in `shop-project` subfolder. IGNORE all other folders here (MFDTools etc.). Read `E:\mfdtools-web\shop-project\HANDOVER.md` and resume from Step 5."

---

## 1️⃣2️⃣ Frequently Used Commands (for new session)

### Git push (after GitHub repo created):
```bash
cd E:\dukanlist-web
git init
git add .
git commit -m "Initial commit — DukanList.com MVP"
git branch -M main
git remote add origin https://github.com/USERNAME/dukanlist.git
git push -u origin main
```

### Local test server:
```bash
cd E:\dukanlist-web
python -m http.server 8000
# Open: http://localhost:8000
```

### Vercel deploy (after GitHub push):
1. Go to https://vercel.com/new
2. Import GitHub repo `dukanlist`
3. Framework: **Other** (static site)
4. Build command: (leave empty)
5. Output directory: `./`
6. Deploy

### Cloudflare DNS (after Vercel deploy):
1. Cloudflare → dukanlist.com → DNS → Records
2. Add A record: `@` → `76.76.21.21` (Vercel IP)
3. Add CNAME: `www` → `cname.vercel-dns.com`
4. Vercel project → Settings → Domains → Add `dukanlist.com` + `www.dukanlist.com`

---

## 1️⃣3️⃣ Future Phase 4 Work (after deploy)

- `panel/profile.html` — Edit business profile
- `panel/services.html` — Manage services list
- Review submission flow on `business.html`
- Admin panel for moderation
- Analytics dashboard for shopkeepers
- WhatsApp click-to-chat integration
- Email notifications via Supabase Edge Functions
- Add more cities/states beyond Haryana cluster
- SEO meta tags + sitemap.xml
- Google Search Console submission

---

## ✅ Sanity Check Before Resuming

When new Claude session reads this file, it should confirm:

1. ✅ `assets/js/supabase-init.js` has live keys (NOT `REPLACE_WITH_*`)
2. ✅ All 9 HTML files reference `dukanlist.com` in footers (NOT `shop.mfdtools.com`)
3. ✅ User has Supabase project active at `qazuyygrpqopwygxmvwq`
4. ✅ Domain `dukanlist.com` is purchased from Cloudflare
5. ⏳ GitHub repo creation is the immediate next step

---

**🚀 Ready to resume! Open fresh Cowork → Read this file → Step 5.**
