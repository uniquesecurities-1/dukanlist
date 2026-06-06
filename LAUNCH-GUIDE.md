# 🚀 DukanList Launch Day Guide

**For:** Deepak Singla & Navneet Singla
**Strategy:** Zero-cost launch via manual WhatsApp verification + community trust

---

## ⚡ Quick Status

- ✅ SMS OTP removed from registration
- ✅ WhatsApp click-to-verify flow built
- ✅ Admin moderation panel with 1-click approve + WhatsApp button
- ✅ Pending count badge in nav
- ✅ Bulk upload tool for self-onboarding 50-100 shops
- ✅ Public registration RPC (`register_business_public`)
- ✅ Manual phone-claim flow for future login (`claim_business_by_phone`)

---

## 🎯 Daily Admin Workflow (5 min/day)

1. **Login:** dukanlist.com/admin/login.html
2. **See badge:** If "Moderation" tab shows orange badge (e.g., "3"), 3 new shops pending
3. **Open Moderation:** Each pending shop has:
   - 📞 **Call** button — direct phone call
   - 💬 **WhatsApp Verify** button — pre-filled message: "Namaste {Owner}! DukanList se baat kar raha hu..."
   - ✓ **Approve & Activate** — one click activates the shop
   - ✕ **Reject / Ban** — if fake/suspicious

4. **Quick check (30 seconds per shop):**
   - Shop name matches owner name? ✓
   - Pincode + city match the area? ✓
   - USP isn't gibberish? ✓
   - WhatsApp the owner to confirm (optional but builds trust)

5. **Click Approve** → shop goes live instantly.

---

## 📥 First-Week Strategy (Bootstrap)

### Day 1-2: Self-add 50-100 shops you personally know

1. Go to `/admin/bulk-upload.html`
2. Select state: **Haryana**, district: **Sirsa**, city: **Mandi Dabwali**
3. Paste your shops in this format (one per line):

```
Sharma Mutual Funds | Rajesh Sharma | 9876543210 | mutual-fund-distributor | Main Bazaar Road | 125104 | 20+ years AMFI registered
Singla Pharmacy | Vinod Singla | 9988776655 | pharmacy | Aastha Hospital Street | 125104 | 24x7 home delivery
```

4. **Format:** `Shop Name | Owner | Mobile | category-slug | Address | Pincode | USP`
5. Click **👁 Preview** → review validation
6. Click **✓ Upload** → all valid rows go live as **verified active** shops

### Common category slugs (refer to docs/categories or `/browse.html`)

- `mutual-fund-distributor`
- `stock-broker`
- `insurance-life`, `insurance-health`, `insurance-general`
- `tax-consultant`, `ca`, `financial-advisor`
- `pharmacy`, `doctor`, `dentist`, `pathology-lab`
- `restaurant`, `sweets`, `bakery`, `tiffin-service`
- `grocery`, `clothes`, `jewellery`, `mobile-shop`, `electronics`
- `carpenter`, `plumber`, `electrician`, `painter`, `ac-repair`
- `salon`, `gym`, `yoga-center`, `spa`
- `tuition-coaching`, `music-dance`, `computer-classes`
- `lawyer`, `architect`, `photographer`, `wedding-planner`

### Day 3: Soft-launch

WhatsApp broadcast to your 1000+ Unique Securities clients:

```
🎉 Naya launch — dukanlist.com

Mandi Dabwali ki sabhi dukaanon ko free me list karne ki facility.
✓ Apni dukaan add karein — free forever
✓ Customers automatic find karenge
✓ Reviews, ratings, analytics — sab kuch free

Register karein: dukanlist.com/register
Already 100+ shops listed!

Help: Call/WhatsApp +91 95412 23377
- Deepak Singla
DigiMutual Goals Pvt. Ltd.
```

### Day 4-7: Manual verification mode

- Every morning: check Admin Moderation panel
- For each pending shop, decide:
  - **Known to you:** approve directly
  - **Unknown:** WhatsApp the owner first → confirm → approve
- 30 seconds per shop. 10 shops = 5 minutes.

---

## 🛡️ Genuineness Safeguards

1. **Phone duplicate block** — Same mobile can't register twice while pending
2. **Pincode-city match** — automatic validation
3. **Status = 'pending'** by default — nothing goes live until admin approves
4. **Community flagging** — already built (3 flags from different numbers auto-flag)
5. **Manual WhatsApp** — your personal verification step

---

## 📊 Analytics for You

Visit `/panel/analytics.html` (logged in as a shop) to see:
- Views, calls, WhatsApp clicks, conversion rate
- 7d / 30d / 90d trends
- Smart tips per shop

You can also check `/admin/dashboard.html` for site-wide stats.

---

## 🔧 Technical Notes (For Reference)

### New SQL files to run (in order)

If not already run:
1. `db/13-faqs-column.sql` — adds `faqs_json` column
2. `db/14-owner-analytics.sql` — adds analytics RPC
3. `db/15-public-registration.sql` — adds public registration + bulk upload RPCs

Each goes in Supabase → SQL Editor → Run.

### Future: When MSG91 is integrated

The `register_business_public` RPC will remain. We'll just add an optional OTP verification flag. The bulk upload tool stays as admin-only convenience.

When a shopkeeper later wants to **login** to edit their shop:
- Use email magic link (Supabase free)
- Or admin manually links auth via `claim_business_by_phone` RPC

---

## 🆘 Common Issues

| Issue | Solution |
|-------|----------|
| "Pincode does not match" | Add the pincode mapping in `geo_cities.pincodes` array |
| Bulk upload "Unknown category" | Use exact category slug from list above |
| Shopkeeper says "I didn't get OTP" | Tell them: we don't send OTP anymore. WhatsApp +91 9541223377 to verify |
| Pending count not updating | Refresh dashboard — count is cached for 30 seconds |

---

## 📞 Support

For any technical issue, the project is in `E:\dukanlist-web\`.
All code is in GitHub at `github.com/uniquesecurities-1/dukanlist`.
Auto-deploys via Vercel on git push.

**Daily backup:** Run `backup.bat` weekly (Windows Task Scheduler can automate).

---

## 🎬 Ready to Launch!

1. **Run SQL** in Supabase (file `db/15-public-registration.sql`)
2. **Push code** via `push.bat` with message: `"Zero-cost launch: WhatsApp verify flow + bulk upload"`
3. **Wait 2-3 min** for Vercel auto-deploy
4. **Test registration** — register a fake shop on yourself, verify the WhatsApp button works
5. **Open Bulk Upload** — add your first 10-20 shops
6. **WhatsApp broadcast** to your network

🚀 Let's go!
