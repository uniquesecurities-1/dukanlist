# 🏙 City Manager System — Onboarding Guide

**For:** Deepak Singla (Super Admin)
**Purpose:** Onboard local managers to scale DukanList city-by-city while you maintain super-admin control.

---

## 🎯 What You Just Built

A **scoped admin system** where:
- **You** (super_admin) see and control **everything** across all cities + manage other admins
- **City Manager** sees and controls **only assigned cities** — approve, reject, delete shops in their scope only
- Cross-city actions are **blocked at the database level** (not just UI)

This is exactly how Justdial / Sulekha / IndiaMart operate internally.

---

## 📊 Roles Cheat Sheet

| Role | Cities | Approve/Reject | Manage Other Admins | Best For |
|------|--------|----------------|---------------------|----------|
| **super_admin** 👑 | All | ✅ All | ✅ Yes | You + Navneet bhai |
| **city_moderator** 🏙 | Assigned only | ✅ In scope | ❌ No | Per-city local managers |
| **admin** 🔧 | All | ✅ All | ❌ No | Future senior team |
| **moderator** 👁 | (future) | ❌ Read-only | ❌ No | Auditors |

---

## 🚀 Setup — Run SQL First

Before using the new feature:

1. Supabase Dashboard → **SQL Editor** → New query
2. Paste content of `db/19-city-manager-system.sql`
3. Run → **"Success. No rows returned"**
4. Verify:
   ```sql
   SELECT proname FROM pg_proc WHERE proname IN
     ('is_super_admin','get_admin_scope','admin_list_admins','admin_upsert_admin','admin_remove_admin','admin_list_all_cities');
   ```
   (should return 6 rows)

5. **Make yourself a super_admin** (if not already):
   ```sql
   UPDATE admin_users
   SET role = 'super_admin'
   WHERE email = 'singla223377@gmail.com';
   ```

---

## 👥 How to Onboard a City Manager (5 min)

Example: Adding **Rajesh Kumar** as city manager for **Mandi Dabwali + Ellenabad**

### Step 1: Create Supabase Auth user (1 min)

1. Supabase Dashboard → **Authentication** → **Users**
2. **Add user** → **Create new user**
3. Enter:
   - **Email:** `rajesh.dabwali@example.com` (his actual email)
   - **Password:** Set a strong one — share securely (use a password generator)
   - ✅ **Auto Confirm User**
4. **Create**
5. Click on new user → **copy the UID** (looks like `a1b2c3d4-...`)

### Step 2: Add as admin via your panel (1 min)

1. Open: **`https://dukanlist.com/admin/admins`** (login as super_admin)
2. Click **"+ Add Admin / City Manager"** (top right)
3. Fill the form:
   - **Auth User ID:** paste the UUID from Step 1
   - **Email:** `rajesh.dabwali@example.com`
   - **Display Name:** `Rajesh Kumar`
   - **Role:** `City Moderator` (default)
   - **Cities:** Pick from dropdown:
     - Mandi Dabwali (Sirsa, Haryana)
     - Ellenabad (Sirsa, Haryana)
4. Click **"Save Admin"**
5. Done — entry appears in admin list with blue "City Moderator" badge

### Step 3: Share credentials with manager (2 min)

WhatsApp Rajesh:
```
Hi Rajesh!

You are now a City Manager for DukanList — Mandi Dabwali + Ellenabad.

Your login:
URL: https://dukanlist.com/admin/login
Email: rajesh.dabwali@example.com
Password: [share securely]

First time:
1. Login with email + password
2. You'll be asked to set up 2FA — scan QR code with Google Authenticator
3. Save the backup secret (shown below QR)
4. Done — you'll see dashboard for your cities

Daily routine (5 min/day):
1. Open /admin/moderation
2. Approve good shops, reject fake ones, WhatsApp owners to verify

For help: +91 9541223377

Welcome aboard!
- Deepak Singla
```

### Step 4: First login (Rajesh side, 2 min)

Rajesh does on his phone/laptop:
1. Visit `dukanlist.com/admin/login`
2. Email + Password → Continue
3. **QR code appears** → scan with Google Authenticator
4. Enter 6-digit code → Verify & Enable 2FA
5. **Saves the backup secret** (very important)
6. Dashboard opens — but only shows shops in **Mandi Dabwali + Ellenabad**

---

## 🔒 What City Managers Can/Cannot Do

### ✅ Can:
- See shops in their assigned cities
- Approve / Reject / Delete shops in their cities
- WhatsApp / Call owners
- Bulk upload shops (only if pasted shops are in their cities)
- View analytics for their cities' shops

### ❌ Cannot:
- See shops outside their cities (blocked at DB level)
- Approve cross-city shops
- Add or remove other admins (only super_admin)
- Change their own city scope (only super_admin)
- Access other cities even via direct API call

### 🛡 Database-Level Enforcement

The protection is **NOT just frontend** — `admin_approve_business()` and similar RPCs check:

```sql
IF NOT _admin_has_city_access(v_city) THEN
  RAISE EXCEPTION 'Not authorised — this shop is outside your city scope';
END IF;
```

A malicious city manager who tries to call RPCs directly via API will get **rejected at the database**.

---

## 💰 Compensation Models for City Managers

### Model 1: Fixed Monthly (Simple)
- **₹3,000 – ₹5,000/month per city**
- Predictable cost
- Best for early stages

### Model 2: Per Shop Approved (Performance)
- **₹20 – ₹50 per approved shop**
- Drives growth aggressively
- Risk: quality drops

### Model 3: Hybrid ⭐ (Recommended)
- **₹2,000 fixed + ₹30 per shop + 10% revenue share**
- Balanced: stable income + growth incentive + long-term alignment
- Manager earns more as city grows = motivated

### Model 4: Revenue Share Only (Mature)
- **20% of city's Premium subscription revenue**
- Best after city is established
- Pure performance-based

### Worked Example
**Manager for Mandi Dabwali on Hybrid model:**

| Month | Shops Added | Fixed | Per Shop | Premium Revenue Share (10%) | Total |
|-------|-------------|-------|----------|----------------------------|-------|
| 1     | 50          | ₹2,000 | ₹1,500   | ₹500 (5 premium × ₹499 × 10%) | **₹4,000** |
| 3     | 150         | ₹2,000 | ₹4,500   | ₹2,000 (20 premium × ₹499 × 10%) | **₹8,500** |
| 6     | 300         | ₹2,000 | ₹9,000 (cap) | ₹5,000 (50 premium) | **₹16,000** |
| 12    | 500         | ₹2,000 | ₹12,000 (cap) | ₹10,000 (100 premium) | **₹24,000** |

**Cap:** Per-shop bonus capped at ₹300/month to prevent gaming. Real value is revenue share.

---

## 📋 Recruitment Profile — Who to Hire

### Ideal City Manager:
- ✅ Lives in that city
- ✅ Has a local network (knows shopkeepers)
- ✅ Smartphone literate (can use WhatsApp, login)
- ✅ 4-6 hours/week available
- ✅ Honest + reliable references
- ✅ Indian language local fluency

### Ideal Backgrounds:
- Recently retired bank manager / branch employee
- Local insurance/MF agent (already in your network!)
- Local Chamber of Commerce member
- Active community/social worker
- College student looking for side income

### Avoid:
- Anyone outside the city (can't visit shops)
- People without smartphones
- Without reference from someone you trust

---

## 🎬 Suggested Onboarding Roadmap

### Month 1 (You alone)
- Just you and Navneet bhai run Mandi Dabwali
- Goal: 500 shops via personal network + WhatsApp broadcast

### Month 2 (First City Manager)
- Hire 1 manager for **Sirsa city**
- Pay ₹3,000 fixed for first month
- They onboard 100-200 Sirsa shops
- Verify they can use the panel properly

### Month 3 (Scale up)
- Add 2-3 more managers (Hisar, Bhiwani, Rohtak)
- Switch to hybrid model (₹2,000 + ₹30/shop)
- Monthly review call to align

### Month 6 (10-15 cities)
- Hire 1 senior coordinator (₹15K-25K/month) to manage city managers
- Standardize training, scripts
- Performance bonuses for top performers

---

## 📞 Real-World Operations

### Daily Routine (per city manager):
1. **Morning (9 AM):**
   - Check /admin/moderation for new pending shops in their cities
   - Approve known shops directly
   - WhatsApp unknown shops to verify

2. **Evening (7 PM):**
   - Check WhatsApp replies
   - Approve confirmed shops
   - Reject no-replies after 48 hours

### Weekly Routine (Super Admin):
1. **Sunday review:**
   - SQL query to see all admin activity:
     ```sql
     SELECT au.display_name, aal.action, COUNT(*) AS actions
     FROM admin_audit_log aal
     JOIN admin_users au ON au.auth_user_id = aal.admin_user_id
     WHERE aal.created_at > NOW() - INTERVAL '7 days'
     GROUP BY au.display_name, aal.action
     ORDER BY au.display_name, COUNT(*) DESC;
     ```
   - WhatsApp top performers a "well done"
   - Address any issues

2. **Monthly:**
   - Send payments per agreement
   - Review which cities are growing
   - Add/remove city assignments as needed

---

## 🆘 Common Issues & Solutions

### "City manager says login fails"
- Verify their email is correct in admin_users table
- Check if their 2FA was set up properly
- Reset their password from Supabase Auth

### "Manager left or unresponsive"
1. Admin panel → /admin/admins → Find them → **Remove** button
2. This **revokes panel access immediately**
3. Their Supabase Auth account remains (for re-add later if needed)

### "Manager needs more cities"
- /admin/admins → Edit their entry → Add cities → Save
- Effect immediately — no logout/login needed for them

### "Need to demote yourself temporarily"
- Don't do this unless absolutely necessary
- If you do, add another super_admin **first** (e.g., Navneet bhai)
- Otherwise nobody can manage admins

---

## 🔍 Audit Queries for Super Admin

### See who did what:
```sql
SELECT au.display_name, aal.action, aal.target_name, aal.created_at
FROM admin_audit_log aal
JOIN admin_users au ON au.auth_user_id = aal.admin_user_id
WHERE aal.created_at > NOW() - INTERVAL '24 hours'
ORDER BY aal.created_at DESC;
```

### Top performers (this week):
```sql
SELECT au.display_name,
       SUM((aal.action = 'approve_business')::INT) AS approved,
       SUM((aal.action = 'reject_business')::INT) AS rejected
FROM admin_audit_log aal
JOIN admin_users au ON au.auth_user_id = aal.admin_user_id
WHERE aal.created_at > NOW() - INTERVAL '7 days'
GROUP BY au.display_name
ORDER BY approved DESC;
```

### Cities without a manager:
```sql
SELECT gc.name AS city, gs.name AS state, COUNT(b.id) AS shops
FROM geo_cities gc
LEFT JOIN geo_states gs ON gs.id = gc.state_id
LEFT JOIN businesses b ON b.city_id = gc.id
WHERE gc.id NOT IN (
  SELECT unnest(assigned_city_ids)
  FROM admin_users
  WHERE assigned_city_ids IS NOT NULL
)
GROUP BY gc.name, gs.name
HAVING COUNT(b.id) > 10
ORDER BY shops DESC;
```

---

## ✅ Setup Checklist

- [ ] Run `db/19-city-manager-system.sql` in Supabase
- [ ] Verify your `singla223377@gmail.com` user has role = `super_admin`
- [ ] Push.bat to deploy frontend changes
- [ ] Test `/admin/admins` page (loads, shows you as super_admin)
- [ ] Onboard your first city manager (test with a friend / Navneet bhai's email first)
- [ ] Verify city manager only sees their cities
- [ ] Run an audit query to confirm logs work

---

**Built for:** DigiMutual Goals Pvt. Ltd. · Mandi Dabwali, Haryana, India

For questions: Deepak Singla (super-admin) — +91 9541223377
