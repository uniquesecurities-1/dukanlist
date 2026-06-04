# DukanList — Backup & Safety Guide

**Last updated: 2026-06-02**
**Owner: Deepak Singla (DigiMutual Goals Pvt. Ltd.)**

---

## Three-layer backup strategy

DukanList ka code 3 alag-alag jagah safe rahta hai. Kisi ek layer me bhi
problem aaye to baaki 2 se recovery ho jaayegi. **Live folder ko OneDrive
pe DIRECTLY MAT rakhein** — uska reason neeche explain kiya hai.

| Layer | Storage location | Kya save hota hai | Kab update hota hai |
|-------|-----------------|-------------------|---------------------|
| **1. GitHub** (primary) | github.com (private repo) | Saara source code + history | Har baar push karte hi |
| **2. OneDrive** (off-site backup) | `OneDrive\DukanList-Backups\dukanlist_<ts>.zip` | Full project snapshot (no .git/node_modules) | Weekly (manual) |
| **3. Local backups** (E: drive) | `E:\backups\dukanlist\` | Full project + git state | `backup.bat` chalane par |

---

## How to use

### Layer 1 — GitHub (sabse zaroori)
Har code change ke baad **`quick-push.bat`** double-click karein.
Ye automatically GitHub par push kar deta hai. Bas yahi enough hai
90% safety ke liye.

### Layer 2 — OneDrive backup (recommended weekly)
**`backup-to-onedrive.bat`** double-click karein. Ye:
- Aapke OneDrive folder me ek ZIP archive banata hai (project ka snapshot)
- `.git/` aur `node_modules/` ko exclude karta hai (conflicts avoid)
- Last 10 backups rakhata hai, purane delete kar deta hai
- OneDrive 1-2 min me ZIP ko cloud me sync kar deta hai

**Recommended schedule:** Har Sunday raat ko ek baar.
Ya phir bade changes ke baad immediately.

### Layer 3 — Local backup (`backup.bat`)
Pehle se hai. E:\backups\dukanlist me timestamped ZIP banata hai.
Yeh tabhi useful hai jab same laptop pe kuch corrupt ho jaaye.

---

## ❓ Why NOT move the live folder to OneDrive?

Live folder ko `OneDrive\dukanlist-web\` me move karne se ye problems hoti hain:

1. **Git conflicts** — `.git/` folder ke hazaron tiny files OneDrive ki
   sync ke saath fight karenge. Resulting in: corrupted git index,
   "fatal: index file corrupt" errors, lost commits.

2. **File locks** — OneDrive jab sync kar raha hota hai, push.bat
   ya editor file ko write nahi kar paaegi.

3. **Mid-write truncation** — OneDrive sync mid-save ho jaata hai to
   files truncate ho sakti hain (live website break ka risk).

4. **Performance** — Har edit pe OneDrive sync trigger hoga,
   laptop slow ho jayega.

**Sahi tarika:** Live code E: drive pe rakho (kahan bhi rakho jahan
OneDrive sync na ho), aur OneDrive me sirf ZIP archives bhejo via
`backup-to-onedrive.bat`.

---

## Disaster recovery

### Case 1: Laptop kharab ho gaya, naya laptop liya
1. Naya laptop pe **Git for Windows** install karein
2. **OneDrive** install karein aur sign in karein
3. Wait for OneDrive folder to sync (5-30 min)
4. Open Command Prompt:
   ```
   cd /d E:\
   git clone https://github.com/<your-github-username>/dukanlist.git dukanlist-web
   cd dukanlist-web
   ```
5. **Done.** Code wapas mil gaya. OneDrive ZIP backup unzip karne ki
   bhi zaroorat nahi padi — GitHub se direct mila.

### Case 2: GitHub bhi access nahi (rare but possible)
1. OneDrive folder me jaayein
2. `DukanList-Backups\dukanlist_<latest>.zip` ko extract karein
3. Folder ko `E:\dukanlist-web\` me rakhein
4. Code wapas mil gaya (without git history, but functional)

### Case 3: Database bhi gaya
- Supabase Pro plan me **Point-in-Time Recovery (PITR)** auto-enabled
  hai. Last 7 days ka snapshot kabhi bhi restore kar sakte hain.
- `api/daily-backup.js` har raat 9:30 PM ko Supabase Storage me bhi
  full DB dump rakhta hai.

---

## Quick reference — kaunsa file kab use karein

| File | Kab double-click karein |
|------|------------------------|
| `quick-push.bat` | Har code change ke baad — turant GitHub upload |
| `push.bat` | Jab meaningful commit message dena ho |
| `backup-to-onedrive.bat` | Har Sunday — OneDrive me weekly ZIP |
| `backup.bat` | Bade milestone ke baad — local E:\backups\ ZIP |

---

## Optional: Schedule weekly OneDrive backup

Windows Task Scheduler me ye batch file har Sunday 9 PM pe automatically
chalwa sakte hain. Step-by-step:

1. **Start** → search "Task Scheduler" → open
2. Right panel → **Create Basic Task**
3. Name: `DukanList Weekly Backup`
4. Trigger: **Weekly** → choose Sunday, 9:00 PM
5. Action: **Start a program**
6. Program: `E:\dukanlist-web\backup-to-onedrive.bat`
7. Finish.

Bas — har Sunday 9 baje raat ko automatic OneDrive backup ho jaayega
jab tak aap log in ho.
