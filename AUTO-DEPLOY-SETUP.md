# 🚀 Auto-deploy Setup — 5 Minutes, Done Forever

Bhai, ye one-time setup hai. Iske baad **kabhi bhi SQL manually paste nahi karna padega**.

---

## Aaj kya hai (manual hell)

1. Main GitHub me SQL commit karta hu
2. Aap GitHub se copy karte ho
3. Supabase me paste karte ho
4. Run karte ho
5. Error aaye to repeat

## Aaj ke baad kya hoga (auto magic)

1. Main GitHub me SQL commit karta hu
2. **Bas. 1-2 min me Supabase me automatically apply ho jata hai.**

---

# 🔧 ONE-TIME SETUP (5 minutes)

### Step 1: Supabase access token banao

1. Open: https://supabase.com/dashboard/account/tokens
2. Click **"Generate new token"**
3. Name: `GitHub Actions`
4. Click Generate
5. **Copy the token** (looks like `sbp_abc123def456...`)
   ⚠️ Ye token sirf ek baar dikhega — copy karke kahin save kar lo

### Step 2: Database password lao

1. Open: https://supabase.com/dashboard/project/qazuyygrpqopwygxmvwq/settings/database
2. Scroll to **"Connection string"** section
3. Click **"Reveal password"** / eye icon
4. Copy the password

   ⚠️ Ye **service_role key** se alag hai. Database password chahiye, NOT service role.

### Step 3: GitHub me 3 secrets add karo

1. Open: `https://github.com/<aapka-username>/dukanlist-web/settings/secrets/actions`
   (apna GitHub username daalo URL me)

2. Click **"New repository secret"** 3 baar — har baar:

   | Secret #1 |  |
   |---|---|
   | Name | `SUPABASE_ACCESS_TOKEN` |
   | Value | Step 1 ka token (sbp_...) |

   | Secret #2 |  |
   |---|---|
   | Name | `SUPABASE_PROJECT_REF` |
   | Value | `qazuyygrpqopwygxmvwq` |

   | Secret #3 |  |
   |---|---|
   | Name | `SUPABASE_DB_PASSWORD` |
   | Value | Step 2 ka password |

   Click **"Add secret"** har baar.

### Step 4: DONE

Bas. Ab kabhi bhi main `db/89-xxx.sql` ya kuch bhi naya SQL commit karunga, aap ko sirf:

```
cd E:\dukanlist-web
git push origin main
```

— bas itna karna hoga. 1-2 min me GitHub Actions run hoga, Supabase pe automatically apply ho jaayega.

---

# 🧪 First test (after setup)

1. Setup karne ke baad mujhe batao
2. Main koi chhota safe SQL push karunga (test)
3. Aap GitHub me jao: `https://github.com/<your-username>/dukanlist-web/actions`
4. Aapko ek workflow run dikhega — green checkmark = success!
5. Click karke logs dekh sakte ho

---

# ⚙️ Power features

### Manually run a specific SQL file
GitHub me **Actions** tab → **"Auto-deploy SQL to Supabase"** workflow → **"Run workflow"** button → file path daalo (e.g. `db/88-batch-link-orphan-shopkeepers.sql`) → Run.

### See history
**Actions** tab me sab past runs dikhenge — kab kya apply hua, kya fail hua, sab logs ke saath.

### Failure handling
Kuch fail ho to GitHub Actions me email aayega + workflow red ho jaayega. Mujhe error screenshot bhej do, fix kar dunga.

---

# ⏳ Until you complete this setup — instant relief

Setup karne se PEHLE, ek aur cheez bhi hai jo aap ko abhi karna hai (orphan users link karna):

1. Supabase SQL Editor kholo
2. `db/88-batch-link-orphan-shopkeepers.sql` ka latest content paste karo
3. ▶ Run

Iske baad photo upload kaam karega.

Phir setup kar lo upar wala — uske baad sab kuch auto.

---

# 🎁 Bonus: Vercel deploy ka kya?

Vercel pehle se hi auto-deploys karta hai jab aap `git push origin main` karte ho. Wo already automated hai.

To ab combine kar ke:

| Pushed | What auto-happens |
|---|---|
| HTML/JS change | Vercel rebuilds + deploys (1-2 min) |
| `db/*.sql` change | GitHub Actions runs on Supabase (1-2 min) |
| Both | **Dono ek saath happen** without you doing anything |

Ye **CI/CD pipeline** kehlata hai — proper engineering teams me yahi system hota hai. Aapke pass bhi same setup ab hai.

---

**Bhai setup complete ho jaye to batao — tabhi main confidence ke saath kuch bhi push karunga aur same time pe Supabase pe apply ho jayega. No more "Supabase me run karo" instructions.**
