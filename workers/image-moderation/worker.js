/**
 * DukanList — Image Moderation Worker (Cloudflare Workers AI)
 * =========================================================
 * Free tier: 10,000 neurons/day = ~3000-5000 image checks/day
 * (more than enough for DukanList scale — well under that limit)
 *
 * Endpoint: POST  https://image-mod.<your-account>.workers.dev/check
 * Body:     multipart/form-data with field "image" OR JSON {"url": "..."}
 * Auth:     Header  Authorization: Bearer <DUKANLIST_WORKER_SECRET>
 *
 * Response:
 *   200 { ok: true,  verdict: "safe"|"flag"|"block", scores: {...} }
 *   400 { ok: false, error: "..." }
 *   401 { ok: false, error: "unauthorized" }
 *
 * Models used:
 *   - @cf/unum/uform-gen2-qwen-500m         : caption (used as soft signal)
 *   - @cf/llava-hf/llava-1.5-7b-hf          : VQA — direct NSFW/violence question
 *
 * SETUP (one-time):
 *   1. Sign up at https://dash.cloudflare.com (free)
 *   2. Workers & Pages → Create Worker → Quick edit
 *   3. Paste this code, save
 *   4. Settings → Variables → Add secret:
 *        WORKER_SHARED_SECRET = <pick a strong random string, save it!>
 *   5. Bindings → Add → AI → Variable name: AI
 *   6. Deploy
 *   7. Copy the Worker URL — add to Vercel env as IMG_MOD_WORKER_URL
 *      and the secret as IMG_MOD_SECRET
 *
 * Once deployed, /api/upload-shop-photo.js will call this worker
 * before saving a photo to Supabase Storage.
 */

export default {
  async fetch(request, env, ctx) {
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: corsHeaders()
      });
    }
    if (request.method !== 'POST') {
      return json({ ok: false, error: 'method_not_allowed' }, 405);
    }

    // ----- 1. Auth gate -----
    const auth = request.headers.get('authorization') || '';
    if (!env.WORKER_SHARED_SECRET || auth !== 'Bearer ' + env.WORKER_SHARED_SECRET) {
      return json({ ok: false, error: 'unauthorized' }, 401);
    }

    // ----- 2. Load image bytes -----
    let imgBytes;
    try {
      const ct = (request.headers.get('content-type') || '').toLowerCase();
      if (ct.includes('multipart/form-data')) {
        const form = await request.formData();
        const file = form.get('image');
        if (!file || typeof file === 'string') {
          return json({ ok: false, error: 'no_image_in_form' }, 400);
        }
        imgBytes = new Uint8Array(await file.arrayBuffer());
      } else if (ct.includes('application/json')) {
        const body = await request.json();
        if (!body.url) return json({ ok: false, error: 'no_url_in_body' }, 400);
        const r = await fetch(body.url, { cf: { cacheTtl: 0 } });
        if (!r.ok) return json({ ok: false, error: 'fetch_failed', status: r.status }, 400);
        imgBytes = new Uint8Array(await r.arrayBuffer());
      } else if (ct.startsWith('image/')) {
        imgBytes = new Uint8Array(await request.arrayBuffer());
      } else {
        return json({ ok: false, error: 'unsupported_content_type', ct }, 400);
      }
    } catch (e) {
      return json({ ok: false, error: 'body_parse_failed', detail: String(e).slice(0, 200) }, 400);
    }

    if (!imgBytes || imgBytes.length < 100) {
      return json({ ok: false, error: 'image_too_small' }, 400);
    }
    if (imgBytes.length > 10 * 1024 * 1024) {
      return json({ ok: false, error: 'image_too_large_10mb_max' }, 400);
    }

    // ----- 3. Run two checks: NSFW VQA + Violence VQA -----
    const checks = [
      { id: 'nsfw',     question: 'Does this image contain sexual, nude, or pornographic content? Answer only "yes" or "no".' },
      { id: 'violence', question: 'Does this image contain blood, gore, weapons, or graphic violence? Answer only "yes" or "no".' },
      { id: 'illegal',  question: 'Does this image contain illegal drugs, narcotics, or alcohol abuse? Answer only "yes" or "no".' }
    ];

    const scores = {};
    let verdict = 'safe';
    const blockedReasons = [];

    try {
      for (const c of checks) {
        const result = await env.AI.run('@cf/llava-hf/llava-1.5-7b-hf', {
          image: Array.from(imgBytes),
          prompt: c.question,
          max_tokens: 8
        });
        const answer = String(result?.description || result?.response || '').toLowerCase().trim();
        const isYes = /^y(es)?\b/.test(answer) || answer.startsWith('yes');
        scores[c.id] = { answer: answer.slice(0, 50), flagged: isYes };
        if (isYes) {
          blockedReasons.push(c.id);
          verdict = 'block';
        }
      }
    } catch (e) {
      // Model unavailable or rate-limited — fail open so user upload doesn't break
      return json({
        ok: true,
        verdict: 'safe',
        warning: 'ai_unavailable',
        detail: String(e).slice(0, 200)
      }, 200);
    }

    return json({
      ok: true,
      verdict,
      reasons: blockedReasons,
      scores,
      bytes: imgBytes.length
    }, 200);
  }
};

// ============================================================
function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      ...corsHeaders()
    }
  });
}

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization'
  };
}
