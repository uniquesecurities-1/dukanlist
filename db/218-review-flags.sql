-- ============================================================
-- db/218 — Review reporting backend (the 🚩 button)
-- ============================================================
-- business.html's reportReview() tried three RPCs
-- (flag_review_public / report_review / flag_review) and then a
-- direct insert into a `review_flags` table. NONE of the four
-- existed, so every visitor who reported a review got
-- "Could not report right now."
--
-- This is the user-generated-content moderation control Play Store
-- expects, so it needs to actually work.
--
-- Creates:
--   TABLE review_flags        — one row per report
--   RPC   flag_review_public  — anon-callable, session-deduped
--   RPC   admin_review_flags  — admin list for moderation
--   RPC   admin_resolve_review_flag — mark handled
--
-- SAFE: additive, idempotent, re-runnable.
-- ============================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.review_flags (
  id          BIGSERIAL PRIMARY KEY,
  review_id   UUID NOT NULL REFERENCES public.reviews(id) ON DELETE CASCADE,
  reason      TEXT NOT NULL DEFAULT 'inappropriate'
              CHECK (reason IN ('inappropriate','spam','fake','offensive','other')),
  session_id  TEXT,
  resolved_at TIMESTAMPTZ,
  resolved_by UUID,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_review_flags_review   ON public.review_flags(review_id);
CREATE INDEX IF NOT EXISTS idx_review_flags_open     ON public.review_flags(created_at DESC) WHERE resolved_at IS NULL;
-- one report per session per review
CREATE UNIQUE INDEX IF NOT EXISTS uq_review_flag_session
  ON public.review_flags(review_id, session_id) WHERE session_id IS NOT NULL;

ALTER TABLE public.review_flags ENABLE ROW LEVEL SECURITY;
-- no direct client access at all; everything goes through the RPCs below
DROP POLICY IF EXISTS review_flags_admin_all ON public.review_flags;
CREATE POLICY review_flags_admin_all ON public.review_flags
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ---- public: report a review -------------------------------
CREATE OR REPLACE FUNCTION public.flag_review_public(
  p_review_id  UUID,
  p_reason     TEXT DEFAULT 'inappropriate',
  p_session_id TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_reason TEXT;
  v_open   INT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.reviews WHERE id = p_review_id) THEN
    RAISE EXCEPTION 'Review not found';
  END IF;

  v_reason := lower(trim(COALESCE(p_reason, 'inappropriate')));
  IF v_reason NOT IN ('inappropriate','spam','fake','offensive','other') THEN
    v_reason := 'other';
  END IF;

  BEGIN
    INSERT INTO public.review_flags (review_id, reason, session_id)
    VALUES (p_review_id, v_reason, NULLIF(trim(COALESCE(p_session_id, '')), ''));
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('success', true, 'already', true);
  END;

  SELECT count(*) INTO v_open
  FROM public.review_flags WHERE review_id = p_review_id AND resolved_at IS NULL;

  RETURN jsonb_build_object('success', true, 'flags', v_open);
END;
$$;

GRANT EXECUTE ON FUNCTION public.flag_review_public(UUID, TEXT, TEXT) TO anon, authenticated;

-- ---- admin: list open flags --------------------------------
CREATE OR REPLACE FUNCTION public.admin_review_flags(p_limit INT DEFAULT 100)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, auth, pg_temp
AS $$
DECLARE v_out JSONB;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  SELECT COALESCE(jsonb_agg(row), '[]'::jsonb) INTO v_out FROM (
    SELECT jsonb_build_object(
      'flag_id',     f.id,
      'review_id',   f.review_id,
      'reason',      f.reason,
      'flag_count',  (SELECT count(*) FROM public.review_flags g
                       WHERE g.review_id = f.review_id AND g.resolved_at IS NULL),
      'created_at',  f.created_at,
      'review_text', r.text,
      'rating',      r.rating,
      'business_id', r.business_id,
      'shop_name',   b.name
    ) AS row
    FROM public.review_flags f
    JOIN public.reviews r    ON r.id = f.review_id
    LEFT JOIN public.businesses b ON b.id = r.business_id
    WHERE f.resolved_at IS NULL
    ORDER BY f.created_at DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500)
  ) t;
  RETURN v_out;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_review_flags(INT) TO authenticated;

-- ---- admin: resolve --------------------------------------
CREATE OR REPLACE FUNCTION public.admin_resolve_review_flag(p_review_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, auth, pg_temp
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  UPDATE public.review_flags
     SET resolved_at = NOW(), resolved_by = auth.uid()
   WHERE review_id = p_review_id AND resolved_at IS NULL;
  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_resolve_review_flag(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- Verify:
--   SELECT flag_review_public('<some-review-uuid>'::uuid, 'spam', 'test-session');
--   SELECT admin_review_flags(10);

DO $$ BEGIN
  RAISE NOTICE '✓ db/218 installed. Review reporting now works end to end.';
END $$;
