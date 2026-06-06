# 🛡️ Admin 2FA Setup — One-Time Guide

**Total time:** 10 minutes
**Required:** Smartphone with authenticator app

This guide sets up **bank-level admin authentication** for DukanList:
- Email + Password (primary)
- TOTP 2FA via authenticator app (second factor)
- Account lockout after 5 failed attempts
- Audit log of every login

---

## 📱 Step 1: Install an Authenticator App (1 min)

On your smartphone, install ONE of these (FREE):

| App | Platform | Recommendation |
|-----|----------|----------------|
| **Google Authenticator** | Android + iOS | ✅ Simplest |
| **Microsoft Authenticator** | Android + iOS | ✅ Backup/sync |
| **Authy** | Android + iOS + Desktop | ✅ Multi-device |
| **1Password** | All platforms | If you use 1Password |

**Recommended:** Google Authenticator (simplest, universal).

---

## 🔐 Step 2: Create Admin Account in Supabase (2 min)

If you don't already have an admin account with **email + password**, create one:

1. Open Supabase Dashboard: https://supabase.com/dashboard/project/qazuyygrpqopwygxmvwq
2. Left sidebar → **Authentication** → **Users**
3. Top-right **"Add user"** button → **"Create new user"**
4. Fill the form:
   - **Email:** `singla223377@gmail.com` (or any email you control)
   - **Password:** Strong password (12+ chars, mix of letters/numbers/symbols)
   - ✅ **Auto Confirm User** (tick yes — skip email verification)
5. Click **"Create user"**
6. **Copy the User UID** (looks like `b7f4e3a1-...`) — you'll need it next

**If you already have a Supabase user with the same email:**
- Just need to set a password
- Click the user → "Send password recovery" OR "Update user" → set new password
- Skip to Step 3

---

## 🗄️ Step 3: Promote User to Admin (1 min)

In Supabase Dashboard → **SQL Editor** → New query:

```sql
-- Add the user as admin (replace UUID with the one from Step 2)
INSERT INTO admin_users (auth_user_id, role, email, display_name)
VALUES (
  'PASTE-USER-UUID-HERE',
  'super_admin',
  'singla223377@gmail.com',
  'Deepak Singla'
)
ON CONFLICT (auth_user_id) DO UPDATE
SET role = EXCLUDED.role,
    email = EXCLUDED.email,
    display_name = EXCLUDED.display_name;

-- Verify
SELECT * FROM admin_users;
```

Click **"Run"** → Should see 1 row in admin_users.

---

## 🔑 Step 4: First Login + Enroll TOTP (3 min)

1. **Push the latest code** if not done:
   - Double-click `push.bat` with message: `"Admin 2FA + premium typography"`
   - Wait 2-3 min for Vercel deploy

2. Open browser (incognito recommended): **https://dukanlist.com/admin/login**

3. **Step A — Enter Credentials:**
   - **Email:** Your admin email (from Step 2)
   - **Password:** Your password (from Step 2)
   - Click **"Continue →"**

4. **Step B — Enroll 2FA (first time only):**
   - You'll see a **QR code** on screen
   - Open **Google Authenticator** on your phone
   - Tap **"+"** (Add account)
   - Choose **"Scan a QR code"**
   - Point camera at the QR code on the screen
   - Authenticator will show: **"DukanList Admin"** with a 6-digit code
   - **Type the 6-digit code** into the website
   - Click **"Verify & Enable 2FA →"**
   - 🎉 **Done!** You're logged in to admin dashboard

   **⚠️ IMPORTANT — Save backup:**
   - On the enrollment screen, you'll see "Or enter secret manually" with a long string
   - **Copy this secret** and save in a SECURE place (password manager, safe document)
   - If you lose your phone, you can re-add to a new authenticator using this secret

---

## 🔄 Step 5: Subsequent Logins (every time)

After first-time setup, every login is:

1. Open: **https://dukanlist.com/admin/login**
2. **Email** + **Password** → Continue
3. Open authenticator app → see "DukanList Admin" with 6-digit code (rotates every 30 sec)
4. Type the 6-digit code → Verify
5. **Logged in** to dashboard

**Total time:** ~15 seconds per login.

---

## 🆘 Recovery & Edge Cases

### Lost your phone?

1. **If you saved the backup secret (recommended):**
   - Install authenticator on new phone
   - "Add account" → "Enter setup key" → paste your saved secret
   - Account restored — same codes work

2. **If you didn't save the backup:**
   - Login to Supabase Dashboard → Authentication → Users
   - Find your user → Click → **"Reset MFA factors"** (or similar)
   - Next login on /admin/login, you'll be prompted to enroll again

### Forgot your password?

1. Supabase Dashboard → Authentication → Users
2. Click your user → **"Send recovery"** OR **"Update user"** → reset password
3. Use new password at /admin/login

### Account locked after 5 failed attempts?

- Wait 30 minutes — auto-unlocks
- Or: Supabase Dashboard → SQL Editor → Run:
  ```sql
  DELETE FROM admin_login_attempts WHERE email = 'your@email.com';
  ```

### Admin gets "Not authorized" after login?

- Check admin_users table:
  ```sql
  SELECT * FROM admin_users WHERE email = 'your@email.com';
  ```
- If empty, run Step 3 again with correct auth_user_id

---

## 👥 Adding More Admins (for Navneet bhai etc.)

1. Repeat **Step 2** in Supabase for the new admin's email
2. Run SQL with new admin's UUID:
   ```sql
   INSERT INTO admin_users (auth_user_id, role, email, display_name)
   VALUES ('new-user-uuid', 'admin', 'navneet@example.com', 'Navneet Singla')
   ON CONFLICT (auth_user_id) DO UPDATE SET role = EXCLUDED.role;
   ```
3. Tell new admin to login at /admin/login — they'll go through the same first-time enroll flow
4. Each admin has their **own 2FA** on their **own phone**

**Roles:**
- `super_admin` — full access including managing other admins
- `admin` — full operational access (approve, reject, delete shops)
- `moderator` — limited access (future use)

---

## 🔒 What Bank-Level Security Means

### Why this is harder to crack than OTP-only:

| Attack | Old (OTP) | New (Email + Pass + 2FA) |
|--------|-----------|--------------------------|
| **Phone number leaked** | Attacker can request OTP | Useless — needs password + 2FA app |
| **SIM swap attack** | Attacker intercepts OTP | Useless — 2FA is app-based |
| **Password leaked** | N/A | Needs phone too — still safe |
| **Phone stolen** | Attacker has full access | Needs password too — still safe |
| **Email hacked** | N/A | Needs phone too — still safe |

**Attacker needs ALL THREE simultaneously:**
1. Your email password
2. Your authenticator app (your phone, unlocked)
3. Knowledge that 2FA is enabled

Practically impossible to compromise. ✅

---

## 🎯 Quick Reference Card

Print this and keep at desk:

```
═══════════════════════════════════════════
  DUKANLIST ADMIN ACCESS
═══════════════════════════════════════════

  Login URL: dukanlist.com/admin/login

  Step 1: Email + Password
  Step 2: 6-digit code from Google Authenticator

  Account locked? Wait 30 min.

  Lost phone? Supabase Dashboard →
              Auth → Users → Reset MFA

  Backup secret stored at:
  ________________________________

═══════════════════════════════════════════
```

---

## ✅ Setup Checklist

- [ ] Authenticator app installed on phone
- [ ] Supabase user created with email + password
- [ ] User UUID copied
- [ ] admin_users SQL run successfully (verified 1 row)
- [ ] Latest code pushed via push.bat
- [ ] Vercel deploy complete (2-3 min wait)
- [ ] /admin/login opened
- [ ] First-time enroll: QR scanned, 6-digit code verified
- [ ] **Backup secret saved** in password manager / secure place
- [ ] Logged in to dashboard successfully
- [ ] Tested logout + re-login flow with 2FA

---

## 📞 Help

If stuck at any step, WhatsApp/screenshot with the exact screen + error.

Built for **DigiMutual Goals Pvt. Ltd.** · Mandi Dabwali, Haryana, India.
