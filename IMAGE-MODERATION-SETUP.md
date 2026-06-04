# DukanList — Image Moderation Setup (Cloudflare Workers AI)

**Cost: ₹0** — Cloudflare Workers AI free tier (10,000 neurons/day = ~3,000–5,000 image checks/day). Well above DukanList's expected scale.

Image moderation is **OFF by default**. Photo uploads work normally until you set 2 environment variables on Vercel. This is intentional — you can deploy code first, set up the Worker at your own pace.

---

## What it blocks

When enabled, every shop photo uploaded via `/api/upload-shop-photo` is checked against 3 questions using Llava VQA model:

1. **NSFW / sexual content** — porn, nudity → BLOCK
2. **Graphic violence** — blood, gore, weapons → BLOCK
3. **Illegal substances** — drugs, alcohol abuse → BLOCK

If any check returns "yes", the upload is rejected with a clear error to the shopkeeper. Else, the photo is saved normally. **Fail-open:** if Cloudflare is down or slow (>8s), the upload proceeds without moderation.

---

## Setup (15 minutes, one-time)

### Step 1 — Create Cloudflare account (skip if you already have one)
1. Open https://dash.cloudflare.com/sign-up
2. Sign up with the email you use for DukanList
3. No credit card needed

### Step 2 — Create the Worker
1. Go to **Workers & Pages** in the left sidebar
2. Click **Create application** → **Create Worker**
3. Worker name: `dukanlist-image-mod` (or any)
4. Click **Deploy** (default Hello-World code will deploy)
5. After deploy → click **Edit code**
6. **Delete** all default code
7. Open `E:\dukanlist-web\workers\image-moderation\worker.js` on your computer
8. Copy ALL contents and paste into the Cloudflare editor
9. Click **Save and deploy**

### Step 3 — Add the AI binding
1. In the Worker page → **Settings** tab → **Variables**
2. Scroll to **Bindings** section → click **+ Add binding**
3. Type: **Workers AI**
4. Variable name: `AI` (exactly this, capital letters)
5. Click **Save and deploy**

### Step 4 — Generate a shared secret
1. On the same **Variables** page → **Environment Variables**
2. Click **+ Add variable**
3. Variable name: `WORKER_SHARED_SECRET`
4. Value: paste a strong random string (e.g. generate one at https://1password.com/password-generator/)
   - **Save this string somewhere safe — you'll need it in Step 5**
5. Click **Encrypt** then **Save and deploy**

### Step 5 — Copy the Worker URL + add to Vercel
1. On Worker overview page, copy the URL like `https://dukanlist-image-mod.<your-account>.workers.dev`
2. Open https://vercel.com/dashboard → dukanlist project → **Settings** → **Environment Variables**
3. Add two variables (both for Production):
   - `IMG_MOD_WORKER_URL` = `https://dukanlist-image-mod.<your-account>.workers.dev`
   - `IMG_MOD_SECRET` = the same string you saved in Step 4
4. Click **Save**
5. Trigger a redeploy: Vercel → Deployments → "..." on latest → **Redeploy**

### Step 6 — Test it
1. Log in to a shopkeeper panel → Photos page
2. Try uploading a normal shop photo → should work as usual
3. (Optional) Try a clearly inappropriate test image → should be blocked with clear error

---

## How to disable temporarily

Just remove or rename `IMG_MOD_WORKER_URL` in Vercel env vars and redeploy. Uploads will work normally without any moderation. Re-add when you want it back.

---

## Monitoring usage

Cloudflare dashboard → **Workers & Pages** → your worker → **Metrics** tab shows:
- Daily AI neuron usage (cap: 10,000/day on free)
- Request count
- Error rate

If you ever hit the cap, you have 2 options:
1. **Upgrade to Workers Paid plan** ($5/month, 10M neurons/month — basically unlimited for DukanList)
2. **Throttle moderation** — only moderate on first 3 photos per shop (edit `upload-shop-photo.js` if needed)

---

## What if the Worker is down?

The integration **fails open** — if Cloudflare returns error or times out (>8s), the upload proceeds without moderation. A warning is logged to Vercel logs. Your shopkeepers will never see a "moderation failed" error blocking them.

---

## Cost ceiling

| Volume per day | Cloudflare cost |
|---------------|-----------------|
| 100 photos | ₹0 (free) |
| 1,000 photos | ₹0 (free) |
| 3,000 photos | ₹0 (free, near cap) |
| 10,000+ photos | Upgrade to $5/month plan = ~₹420 |

DukanList currently does ~50–100 photo uploads/day. You're at <1% of free tier. Even at 30x growth you're still free.

---

## File reference

| File | Purpose |
|------|---------|
| `workers/image-moderation/worker.js` | The Cloudflare Worker code (paste in dashboard) |
| `api/upload-shop-photo.js` | Optional hook (lines 5.5) — calls worker if env vars set |
| `IMAGE-MODERATION-SETUP.md` | This guide |

---

## Recovery

If you ever lose Cloudflare access:
1. The worker code is in `workers/image-moderation/worker.js` (committed to GitHub)
2. Re-create the Worker, paste the code, re-bind AI, regenerate secret
3. Update `IMG_MOD_SECRET` in Vercel to match new secret
