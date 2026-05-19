# dukanlist.com — Bharat ka Local Business Directory

> **Tagline:** Har Dukan, Ek Pehchan
> **Stage:** Phase 1 — Foundation
> **Started in:** Mandi Dabwali, Haryana → Pan-India

---

## 🎯 Mission

Pan-India ke local dukandaron ko ek mauke pe identity aur discoverability dena. Dabwali se start, fir pure India me expand.

**Two-sided value:**
- **Shopkeepers:** Free profile + identity + lead generation
- **Customers:** Trusted local discovery in 1 click — doctor, mistri, mechanic, sab kuch

---

## 🏗️ Architecture

| Layer | Tech | Notes |
|---|---|---|
| **Frontend** | Vanilla HTML/CSS/JS | Same approach as MFDTools — no framework lock-in |
| **Backend** | Supabase (NEW project) | Auth + Postgres + Storage isolated from MFDTools |
| **Database** | PostgreSQL + PostGIS | Geospatial for "near me" queries |
| **Auth** | Supabase Phone OTP | WhatsApp + SMS based |
| **Hosting** | Vercel (free tier) | Auto-deploy from GitHub |
| **Domain** | `dukanlist.com` (now) → `<new>.com` (future) | DNS-level migration |
| **Maps** | Leaflet + OpenStreetMap (free) | Google Maps fallback if needed |
| **PWA** | Service worker + manifest | Installable, offline-friendly |

---

## 🎨 Brand

| Element | Value |
|---|---|
| Primary | `#FF6B1A` (Bharat Saffron) |
| Accent | `#1E3A8A` (Trust Indigo) |
| Success | `#059669` (Verified Emerald) |
| Surface | `#FFFBF5` (Warm Cream) |
| Ink | `#0B1220` (Deep Charcoal) |
| Font | Inter + Plus Jakarta Sans |

---

## 🗂️ Categories (15 starter, Dabwali optimised)

1. 🩺 Doctors & Clinics
2. ⚖️ Lawyers & Notaries
3. 🧮 CA / Tax Consultants
4. 🔨 Carpenter (Lakdi ka Mistri)
5. 🚰 Plumber
6. ⚡ Electrician
7. 🚗 Second-hand Car Dealers
8. 🚙 New Car Dealers
9. 🍴 Restaurants & Dhaba
10. 🍬 Sweets & Caterers
11. 🛒 Grocery & Kirana
12. 💊 Medical Store / Pharmacy
13. 👔 Clothes / Tailor
14. 💍 Jewellery
15. 💇 Salon / Beauty Parlour

(Extensible — admin can add more from dashboard)

---

## 🔐 Verification (Day-1 minimum)

- ✅ **Mobile OTP** (WhatsApp OTP via Supabase Auth — free)
- ✅ **Pincode-City match** (auto-validate against `geo_hierarchy` table)
- ✅ **Shop photo upload** (at least 1, max 5 photos)

(Aadhaar / GST verification — Phase 2)

---

## 📦 Database Schema (high-level)

```
geo_states              (id, name, code)
geo_districts           (id, state_id, name)
geo_cities              (id, district_id, name, pincodes[])
geo_localities          (id, city_id, name)

categories              (id, parent_id, slug, name, name_hi, icon, sort_order)

businesses              (
  id, slug,
  category_id, sub_category_id,
  name, name_hi, owner_name,
  mobile, whatsapp, email,
  address_line1, address_line2,
  locality_id, city_id, district_id, state_id, pincode,
  lat, lng,
  hours_json,
  usp_text, usp_hi,
  photos[], video_url,
  status: pending|active|flagged|banned,
  verification: { mobile, address, photo },
  rating_avg, rating_count,
  view_count, lead_count,
  created_at, updated_at, last_active_at
)

business_services       (id, business_id, service_name, price_range, description)
reviews                 (id, business_id, customer_phone_hash, rating, text, photos[], status)
leads_log               (id, business_id, action, timestamp, ip_hash)
flags                   (id, business_id, reporter_phone_hash, reason, status)
```

---

## 🚀 Phased Rollout

| Phase | Time | Scope | Owner |
|---|---|---|---|
| **1. Foundation** | Week 1-2 | DB + landing + categories | Claude |
| **2. Shopkeeper Panel** | Week 3-4 | Registration + profile mgmt | Claude |
| **3. Discovery** | Week 5-6 | Search + business detail + WhatsApp | Claude |
| **4. Trust Layer** | Month 2 | Verification + ratings + flagging | Claude + Deepak (manual onboarding 50 shops) |
| **5. Scale** | Month 3 | PWA + 5-state expansion | Claude |

---

## 📂 Folder Structure

```
shop-project/
├── README.md                  ← this file
├── index.html                 ← landing page
├── browse.html                ← category/city browse
├── search.html                ← search results
├── register.html              ← shopkeeper signup
├── business/[slug].html       ← business detail (SSR pattern)
├── panel/                     ← shopkeeper dashboard
│   ├── login.html
│   ├── dashboard.html
│   ├── profile.html
│   └── photos.html
├── admin/                     ← internal moderation
│   ├── login.html
│   ├── pending.html
│   ├── flagged.html
│   └── analytics.html
├── assets/
│   ├── css/main.css
│   ├── js/
│   │   ├── supabase-init.js
│   │   ├── geo.js             ← location helpers
│   │   ├── otp.js             ← mobile verification
│   │   └── search.js
│   └── data/
│       ├── categories.json    ← 15 categories metadata
│       └── states-cities.json ← 5-state geo data
├── db/
│   ├── 01-schema.sql          ← create tables
│   ├── 02-rls-policies.sql    ← Row-Level Security
│   ├── 03-seed-categories.sql ← seed 15 categories
│   ├── 04-seed-geo.sql        ← seed 5 states + districts
│   └── 05-rpc-functions.sql   ← search RPCs
└── vercel.json                ← deploy config
```

---

## 🛠️ Deployment Steps (Day-zero)

1. **New GitHub repo:** `uniquesecurities-1/mfdtools-shop`
2. **Copy this folder** to repo root
3. **New Supabase project:** Project name `mfdtools-shop`
4. **Run SQL files** in order: 01 → 05 via Supabase SQL Editor
5. **Update** `assets/js/supabase-init.js` with new project's URL + anon key
6. **Push to GitHub**
7. **Connect to Vercel** — auto-deploy
8. **Add custom domain:** `dukanlist.com` → DNS CNAME to Vercel
9. **Wait 5 min for SSL** → site live ✅

---

## 🔮 Future Migration to Own Domain

When ready (e.g., `bharatdukan.in`):
1. Buy domain
2. Vercel project → Settings → Domains → Add `bharatdukan.in`
3. DNS A record at domain registrar → Vercel
4. Old `dukanlist.com` → 301 redirect to new domain (SEO preserved)
5. Update `manifest.json` + canonical URLs in HTML
6. **Code stays exactly the same** ✅
