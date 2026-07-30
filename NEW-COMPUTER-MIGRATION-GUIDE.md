# 💻 DukanList — New Computer Migration Safety Guide

**For:** Deepak Singla · DigiMutual Goals Pvt. Ltd.  
**Purpose:** Safely move DukanList development environment from old computer → new computer without losing any code, credentials, or work.  
**Key principle:** All ONLINE accounts stay same (email, Supabase, Vercel, GitHub, Google Play). Sirf **local files + tools + saved passwords** ka backup lena hai.

---

## ⚠️ ROOT PRINCIPLE — DO NOT WIPE OLD COMPUTER UNTIL

You have **verified on the new computer** that:
- ✅ Website live edit + push works end-to-end
- ✅ Admin login works
- ✅ Supabase SQL Editor access works
- ✅ Vercel deployment works
- ✅ Google Play Console access works

**Old computer ko 15-30 din tak backup ke roop me rakho.** Naya setup pura test ho jaye, sab kaam sahi chale, tab wipe/sell/handover karo. Aage badhne ki jaldi mat karo — pehle safety.

---

# 📦 PART 1 — OLD COMPUTER PE BACKUP (Before Migration)

## 1.1 — Entire Project Folder Backup

**Sabse important:** `E:\dukanlist-web` folder ka complete copy lena hai.

### Steps:
1. **External hard drive** ya **large USB drive** (min 32 GB) plug karo
2. Windows Explorer me `E:\dukanlist-web` folder pe **right-click → Send to → [Your USB drive]**
3. Copy khatam hone ka wait karo (10-30 min lag sakta hai, folder size par depend)
4. USB drive me confirm karo ki folder pura aaya hai — size compare karo original vs backup

**Alternative (better):** OneDrive/Google Drive pe backup

Aapke paas `backup-to-onedrive.bat` file already hai project me. Woh double-click karke run karo — automatically OneDrive pe backup ho jayega.

### Verify backup:
```
Original: E:\dukanlist-web → check total size
Backup:   [Backup location]\dukanlist-web → same size (±5%)
```

## 1.2 — Git Status Check

Kuch uncommitted kaam toh nahi pada? Pehle sab push karo.

```
Double-click: quick-push.bat
```

Ye sab pending changes GitHub pe push kar dega. **Migration se pehle git status CLEAN hona chahiye.**

Verify:
1. GitHub.com kholo → dukanlist-web repo → latest commit aaj ka hona chahiye
2. Vercel.com kholo → dashboard → last deploy successful

## 1.3 — Saved Passwords Export

Ye sabse zaroori step hai — koi password bhoolna nahi chahiye.

### Chrome se passwords export karo:
1. Chrome kholo → 3-dot menu → **Settings → Passwords → Google Password Manager**
2. Settings icon (gear) → **Export passwords**
3. CSV file save karo — **encrypted USB drive pe** (naam: `passwords-backup-YYYYMMDD.csv`)

⚠️ **Ye CSV file me sab passwords plain text me hote hain — pen drive lock/encrypt karo. Kisi ko na dena.**

### Manually likh lo (bhoolne ke chances):
- ✅ **Gmail/Google account** password
- ✅ **GitHub** password + Personal Access Token (PAT)
- ✅ **Supabase** login
- ✅ **Vercel** login (usually GitHub SSO)
- ✅ **Google Play Console** login
- ✅ **Cloudflare** (agar use kar rahe ho DNS ke liye)
- ✅ **Domain registrar** login (jahan se dukanlist.com kharida)
- ✅ **Anthropic Claude** login

## 1.4 — 2FA / Authenticator Backup

Agar Google Authenticator ya kisi 2FA app use karte ho — **naye phone/computer pe migrate karna zaroori hai warna login block ho jayega.**

### Google Authenticator migration:
1. Purane phone me Authenticator app kholo
2. Top-right menu → **Transfer accounts → Export accounts**
3. QR code generate hoga
4. Naye phone me install karo Authenticator → **Import accounts** → scan QR

### Backup codes save karo:
- Gmail: [myaccount.google.com/security](https://myaccount.google.com/security) → 2-Step Verification → Backup codes → Download
- GitHub: Settings → Security → Recovery codes
- Supabase: Account settings → Security → Recovery codes

**In sab codes ko print karo aur locker/safe me rakho.**

## 1.5 — Local Files Which May NOT Be In Git

Kuch files sensitive hoti hain aur `.gitignore` me hoti hain — GitHub pe nahi jaati. Ye bhi backup karna hai:

### Check karo:
```
E:\dukanlist-web\.env           ← agar exist kare
E:\dukanlist-web\.env.local     ← agar exist kare
E:\dukanlist-web\node_modules   ← ye backup ki zaroorat NAHI (naye computer pe npm install se aa jayega)
```

Aapke project me `.env` file dikhi nahi, iska matlab keys HTML/JS files me hardcoded hain ya inline hain. Iska matlab **complete folder backup se sab kuch aa jayega** — koi extra file nahi.

Confirm karo:
1. Explorer me `E:\dukanlist-web` folder me jao
2. View menu → **Hidden items** ON karo (hidden files dikhne lage)
3. Dekho koi `.env`, `.env.local`, `secrets.txt` type file dikhe — agar dikhe toh USB pe alag copy karo

## 1.6 — Chrome Bookmarks + Extensions List

### Bookmarks export:
1. Chrome → 3-dot menu → **Bookmarks → Bookmark Manager**
2. 3-dot menu inside manager → **Export bookmarks**
3. HTML file save karo USB pe

### Extensions list note karo:
Kaunsi extensions use karte ho — list bana lo (naye Chrome me manually install karni padegi):
- React DevTools
- JSON Viewer
- Google Play Console related
- Screenshot tools
- Password manager (if any)

## 1.7 — Google Play Console Upload Keystore ⚠️ CRITICAL

Ye **sabse zaroori** cheez hai agar Google Play Store pe app rakhi hui hai. Aapki app rakhi hui hai — DukanList live hai Play Store pe.

### App signing keystore:
Agar aapne khud APK sign kiya tha PWABuilder ya Android Studio se — toh `.jks` ya `.keystore` file computer me kahin hogi.

**Search karo:**
```
Windows Search: *.jks
Windows Search: *.keystore
```

Milte hi USB pe backup karo — password/alias bhi note karo.

⚠️ **Agar ye file lost ho gayi toh Play Store app update kabhi nahi kar paoge — completely new app publish karni padegi. Ye critical hai.**

Agar Google Play App Signing use kar rahe ho (which is default now), toh Google apni taraf se manage karta hai — phir bhi upload keystore backup lena chahiye.

---

# 🖥️ PART 2 — NEW COMPUTER SETUP

## 2.1 — Fresh Windows Setup

1. Naya computer boot karo
2. Same Google account se sign-in karo (jo old computer pe tha)
3. Chrome install karo → same Gmail se sign-in → bookmarks + passwords auto-sync (agar sync ON tha)

## 2.2 — Essential Tools Install (in order)

### 1. **Git for Windows**
- Download: [git-scm.com/download/win](https://git-scm.com/download/win)
- Install with default settings
- **Important during install:** "Git Credential Manager" enable rakho (GitHub login save karega)

### 2. **Node.js LTS**
- Download: [nodejs.org](https://nodejs.org) — LTS version
- Install with defaults

### 3. **VS Code** (recommended editor)
- Download: [code.visualstudio.com](https://code.visualstudio.com)
- Install → sign-in with Microsoft/GitHub → extensions + settings auto-sync

### 4. **Chrome** (probably already installed)
- Sign-in → bookmarks + passwords sync

### 5. **Google Authenticator** on new phone
- Transfer complete karo before old phone wipe

## 2.3 — Restore Project Folder

### Option A: From USB backup
1. USB drive plug karo new computer me
2. `dukanlist-web` folder copy karo → paste at `E:\` (or `C:\dukanlist-web` if no E drive)

### Option B: Fresh clone from GitHub (cleaner)
```
Open Command Prompt
cd E:\   (or wherever you want)
git clone https://github.com/[your-username]/dukanlist-web.git
```

Ye method **cleaner** hai kyunki:
- Git history sab GitHub se aata hai (fresh)
- Purani deleted files ka jhanjhat nahi
- `node_modules` etc. include nahi hote (space bachega)

**Lekin** — agar aapki koi local-only untracked file thi (jo .gitignore me tha), woh option A me ayegi, option B me nahi. Isliye **pehle Option A karo, then verify, phir agar sab theek hai toh Option B pe switch kar sakte ho.**

## 2.4 — Git Credential Setup

Command Prompt kholo:

```
git config --global user.name "Deepak Singla"
git config --global user.email "singla223377@gmail.com"
```

Pehli baar `git push` karoge to popup ayega — GitHub login karo. Windows Credential Manager save kar lega future ke liye.

## 2.5 — Verify Everything Works

### Step 1: Local file access
```
Explorer me E:\dukanlist-web kholo → files dikhne chahiye
```

### Step 2: Git connection
Command Prompt:
```
cd /d E:\dukanlist-web
git status
```
Should show: "working tree clean" or list of files (no error)

### Step 3: Test push (safest way)
1. Kisi HTML file me chhota comment add karo (`<!-- test migration -->`)
2. `quick-push.bat` double-click karo
3. Terminal me "SUCCESS" dikhe → GitHub.com pe commit dikhe → Vercel pe deploy shuru ho
4. 2 min baad `dukanlist.com` refresh karo — site live hai to ✅

### Step 4: Admin panel access
- `dukanlist.com/admin/login.html`
- Same email + password se login karo
- Dashboard load ho jaye → ✅

### Step 5: Supabase access
- `supabase.com` → login
- DukanList project select → Table Editor kholo → data dikhe → ✅

### Step 6: Vercel dashboard
- `vercel.com` → login (GitHub SSO)
- DukanList project dikhe → last deployment green → ✅

### Step 7: Google Play Console
- `play.google.com/console` → login
- DukanList app dikhe → ✅

## 2.6 — Chrome Password Restore

Agar Chrome sync ON tha toh sab passwords already aa gaye. Agar nahi:
1. Chrome → Settings → Password Manager → Settings → **Import passwords**
2. Purani CSV upload karo (backup wali)
3. Import ke baad **CSV file DELETE karo** (secure delete — Shift+Delete)

---

# 🔒 PART 3 — SAFETY CHECKS (Before Wiping Old Computer)

## 3.1 — Dual Verification

Ye 7 checks pass hone chahiye **naye computer pe** before old ko wipe karna:

```
[  ] Chrome bookmarks + passwords accessible
[  ] E:\dukanlist-web folder exists with all files
[  ] git status runs without error
[  ] quick-push.bat successfully pushes a test commit
[  ] dukanlist.com/admin/login.html se login ho gaya
[  ] Supabase project access mila
[  ] Vercel + Google Play Console login mila
```

Sab tick ho jaye → naye pe kaam karna shuru karo 3-5 din. Kuch bhi missing lage → wapas old computer se le lena.

## 3.2 — Wait Period

**Minimum 15 din** old computer ko rakho as backup. Aap 3-5 din kaam karke bhi kuch note karoge — "arre yaar, ye file toh missing hai" — toh old computer se retrieve kar sakte ho.

Ideal: **30 din** wait karo.

## 3.3 — Old Computer Wipe (When Ready)

Jab confidence ho ki naya pe sab kaam kar raha hai:

### Sensitive data delete karo:
1. `E:\dukanlist-web` folder → Shift+Delete
2. Chrome logout → **Advanced → Reset settings**
3. Recycle bin → Empty
4. Windows Settings → **System → Recovery → Reset this PC** → **Remove everything → Clean data**

Ye process 1-2 hours lega but full wipe kar dega. Baad me computer sell/donate karna safe.

⚠️ **Agar computer sell ya kisi aur ko de rahe ho — Reset karna MUST hai. Warna passwords/documents leak ho sakte hain.**

---

# 🚨 PART 4 — TROUBLESHOOTING (Common Issues)

## Issue 1: "git push" pe permission denied
**Solution:** GitHub Personal Access Token expire ho gaya
- GitHub.com → Settings → Developer settings → Personal access tokens → generate new
- Push karte time ye token password ki jagah paste karo

## Issue 2: Supabase login pe "unrecognized device"
**Solution:** Naya device 2FA verification maangega
- Backup codes use karo (jo aapne print kiye the)
- Ya email OTP se verify karo

## Issue 3: quick-push.bat me "node not found"
**Solution:** Node install ke baad computer restart karo (PATH update)

## Issue 4: Vercel deploy nahi ho raha
**Solution:** GitHub webhook check karo
- Vercel dashboard → Settings → Git → Reconnect

## Issue 5: Admin login "invalid credentials"
**Solution:** Password reset karo
- Supabase Dashboard → Authentication → Users → find your email → Reset password

## Issue 6: Google Play Console access nahi mil raha
**Solution:** Ye critical hai — 2FA verify karke login karo. Backup codes ready rakhna. Google support se contact karne ki nobat aayi to app details + payment invoice ready rakhna.

---

# 📋 PART 5 — QUICK REFERENCE CARD (Print This)

Ye card print karke naye computer ke paas rakho:

```
═══════════════════════════════════════════════
  DUKANLIST QUICK REFERENCE
═══════════════════════════════════════════════

WEBSITE:      https://dukanlist.com
ADMIN LOGIN:  https://dukanlist.com/admin/login.html
GITHUB REPO:  https://github.com/[username]/dukanlist-web

FOLDER:       E:\dukanlist-web
PUSH SCRIPT:  Double-click quick-push.bat

SUPABASE:     https://supabase.com/dashboard
VERCEL:       https://vercel.com/dashboard
PLAY CONSOLE: https://play.google.com/console

EMAIL:        singla223377@gmail.com

DB MIGRATION FILE LOCATION:
  E:\dukanlist-web\db\   (run manually in Supabase SQL Editor)

BACKUP SCRIPT:
  Double-click backup-to-onedrive.bat weekly

IF PUSH FAILS:
  1. Check internet
  2. Try push-diagnostic.bat
  3. Try push-retry.bat

═══════════════════════════════════════════════
```

---

# 📅 PART 6 — RECOMMENDED TIMELINE

| Day | Task |
|-----|------|
| **Day -3** | Order new computer + external USB drive (32+ GB) |
| **Day -1** | Full backup: `E:\dukanlist-web` → USB + OneDrive |
| **Day -1** | Export Chrome passwords + bookmarks |
| **Day -1** | Google Authenticator transfer to backup phone |
| **Day 0** | New computer setup — install Git, Node, VS Code, Chrome |
| **Day 0** | Restore project folder + verify 7 checks |
| **Day 0** | Test push with small change |
| **Day 1-15** | Work on new computer normally, keep old as backup |
| **Day 15** | Final verification — nothing missing? |
| **Day 15+** | Wipe old computer safely |

---

# ✅ FINAL CHECKLIST

**Before switch:**
- [ ] Full folder backup on USB + OneDrive
- [ ] All git commits pushed to GitHub
- [ ] Passwords exported to encrypted CSV
- [ ] Authenticator migrated to backup phone
- [ ] Google Play upload keystore backed up (`.jks` file)
- [ ] All 2FA backup codes printed and saved

**After setup on new computer:**
- [ ] Git configured + push works
- [ ] Admin panel login works
- [ ] Supabase + Vercel access works
- [ ] Play Console access works
- [ ] `quick-push.bat` successfully deployed a test change
- [ ] `dukanlist.com` loading correctly

**Before wiping old:**
- [ ] Worked on new computer for 15+ days without issue
- [ ] No file/tool discovered missing
- [ ] Final backup taken (just in case)
- [ ] Then and only then: wipe old computer

---

**Created:** 2026-07-27  
**For:** Deepak Singla · DigiMutual Goals Pvt. Ltd. · DukanList  
**Category:** Infrastructure / Migration / Business continuity

## 💡 MOST IMPORTANT MESSAGE

Bhai, agar sirf ek cheez yaad rakhni hai — **Old computer ko jaldi mat wipe karo.** Naye pe sab test hone tak (15+ din) purana rakho. Uske alawa jo bhi galti hogi, recover ho sakti hai. Sabse badi galti sirf ek hai: dono ke bich data lost ho jana. Ye guide us se bachati hai.

Bas dhyaan se follow karo — sab safe hoga.
