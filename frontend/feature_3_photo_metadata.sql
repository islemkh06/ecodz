-- =============================================================================
-- FEATURE 3 — PHOTO METADATA VERIFICATION & FRAUD SCORING
-- Run in Supabase SQL Editor AFTER feature_1 (haversine_distance must exist)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. preuve_metadata table
--    Populated by the Flutter app immediately after a photo is uploaded.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.preuve_metadata (
  id             bigserial    PRIMARY KEY,
  id_preuve      integer      NOT NULL REFERENCES public.preuve(id_preuve) ON DELETE CASCADE,
  id_act         integer      REFERENCES public.activite(id_act) ON DELETE CASCADE,
  photo_type     text         CHECK (photo_type IN ('avant', 'apres')),

  -- GPS extracted from EXIF
  gps_lat        double precision,
  gps_lon        double precision,

  -- Timestamp from EXIF DateTimeOriginal
  taken_at       timestamptz,

  -- Device info
  device_make    text,
  device_model   text,
  image_width    integer,
  image_height   integer,

  -- Full raw EXIF as JSON (for auditability)
  raw_exif       jsonb         NOT NULL DEFAULT '{}',

  -- Fraud scoring
  fraud_score    integer       NOT NULL DEFAULT 0 CHECK (fraud_score BETWEEN 0 AND 100),
  flags          jsonb         NOT NULL DEFAULT '[]',
  -- NULL until fraud check runs
  verified_at    timestamptz,

  created_at     timestamptz   NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 2. compute_fraud_score RPC
--    Evaluates a single preuve_metadata row and writes the score back.
--    Returns the computed score (0–100, higher = more suspicious).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.compute_fraud_score(p_id_preuve integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_meta   public.preuve_metadata%ROWTYPE;
  v_act    public.activite%ROWTYPE;
  v_score  integer       := 0;
  v_flags  jsonb         := '[]'::jsonb;
  v_dist   double precision;
  v_avant  public.preuve_metadata%ROWTYPE;
  v_hours  double precision;
BEGIN
  SELECT * INTO v_meta FROM public.preuve_metadata WHERE id_preuve = p_id_preuve;
  IF NOT FOUND THEN RETURN NULL; END IF;

  SELECT * INTO v_act FROM public.activite WHERE id_act = v_meta.id_act;

  -- ── Rule 1: Missing GPS (+20) ────────────────────────────────────────────
  IF v_meta.gps_lat IS NULL OR v_meta.gps_lon IS NULL THEN
    v_score := v_score + 20;
    v_flags := v_flags || '["missing_gps"]'::jsonb;
  ELSE
    -- ── Rule 2: GPS distance from activity location ──────────────────────
    IF v_act.latitude IS NOT NULL AND v_act.longitude IS NOT NULL THEN
      v_dist := haversine_distance(
        v_meta.gps_lat, v_meta.gps_lon,
        v_act.latitude,  v_act.longitude
      );
      IF v_dist > 1000 THEN          -- > 1 km: highly suspicious
        v_score := v_score + 40;
        v_flags := v_flags || '["gps_far_from_activity"]'::jsonb;
      ELSIF v_dist > 300 THEN        -- > 300 m: mildly suspicious
        v_score := v_score + 15;
        v_flags := v_flags || '["gps_slightly_off"]'::jsonb;
      END IF;
    END IF;
  END IF;

  -- ── Rule 3: Missing timestamp (+15) ─────────────────────────────────────
  IF v_meta.taken_at IS NULL THEN
    v_score := v_score + 15;
    v_flags := v_flags || '["missing_timestamp"]'::jsonb;
  ELSE
    -- ── Rule 4: Future timestamp (+40) ──────────────────────────────────
    IF v_meta.taken_at > now() + interval '5 minutes' THEN
      v_score := v_score + 40;
      v_flags := v_flags || '["future_timestamp"]'::jsonb;
    END IF;

    -- ── Rule 5: Photo taken > 7 days before activity creation (+25) ──────
    IF v_act.datecreation IS NOT NULL
       AND v_meta.taken_at < v_act.datecreation - interval '7 days'
    THEN
      v_score := v_score + 25;
      v_flags := v_flags || '["timestamp_predates_activity"]'::jsonb;
    END IF;
  END IF;

  -- ── Rules for "apres" photos (compare with "avant") ─────────────────────
  IF v_meta.photo_type = 'apres' THEN
    -- Find the most recent "avant" metadata for the same activity
    SELECT pm.*
    INTO   v_avant
    FROM   public.preuve_metadata pm
    JOIN   public.preuve p ON p.id_preuve = pm.id_preuve
    WHERE  p.id_act        = v_meta.id_act
      AND  pm.photo_type   = 'avant'
    ORDER BY pm.created_at DESC
    LIMIT 1;

    IF FOUND THEN
      -- Rule 6: Before/after photos taken at very different GPS locations (+30)
      IF v_avant.gps_lat IS NOT NULL AND v_meta.gps_lat IS NOT NULL THEN
        v_dist := haversine_distance(
          v_meta.gps_lat,  v_meta.gps_lon,
          v_avant.gps_lat, v_avant.gps_lon
        );
        IF v_dist > 500 THEN
          v_score := v_score + 30;
          v_flags := v_flags || '["before_after_gps_mismatch"]'::jsonb;
        END IF;
      END IF;

      -- Rule 7: "apres" timestamp BEFORE "avant" timestamp (+35)
      IF v_avant.taken_at IS NOT NULL AND v_meta.taken_at IS NOT NULL THEN
        v_hours := EXTRACT(EPOCH FROM (v_meta.taken_at - v_avant.taken_at)) / 3600.0;
        IF v_hours < 0 THEN
          v_score := v_score + 35;
          v_flags := v_flags || '["after_photo_before_before_photo"]'::jsonb;
        END IF;
      END IF;
    END IF;
  END IF;

  -- Cap at 100
  v_score := LEAST(100, v_score);

  -- Persist results
  UPDATE public.preuve_metadata
  SET
    fraud_score = v_score,
    flags       = v_flags,
    verified_at = now()
  WHERE id_preuve = p_id_preuve;

  RETURN v_score;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Auto-trigger fraud check after metadata INSERT
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_auto_fraud_score()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Run async-style by deferring to after-row to avoid recursion with UPDATE
  PERFORM public.compute_fraud_score(NEW.id_preuve);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fraud_score_on_metadata ON public.preuve_metadata;
CREATE TRIGGER trg_fraud_score_on_metadata
  AFTER INSERT ON public.preuve_metadata
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_auto_fraud_score();

-- ---------------------------------------------------------------------------
-- 4. View: activities with suspicious photos (for admin dashboard)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_suspicious_activities AS
SELECT
  a.id_act,
  a.titre,
  a.localisation,
  a.status,
  count(pm.id)                          AS suspicious_photo_count,
  max(pm.fraud_score)                   AS max_fraud_score,
  jsonb_agg(DISTINCT pm.flags)          AS all_flags
FROM public.activite a
JOIN public.preuve   p  ON p.id_act      = a.id_act
JOIN public.preuve_metadata pm ON pm.id_preuve = p.id_preuve
WHERE pm.fraud_score >= 50
GROUP BY a.id_act, a.titre, a.localisation, a.status;

-- ---------------------------------------------------------------------------
-- 5. Permissions
-- ---------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.compute_fraud_score TO authenticated;

-- ---------------------------------------------------------------------------
-- 6. Row-Level Security
-- ---------------------------------------------------------------------------
ALTER TABLE public.preuve_metadata ENABLE ROW LEVEL SECURITY;

-- Authenticated users can insert their own proof metadata
CREATE POLICY "meta_insert" ON public.preuve_metadata FOR INSERT TO authenticated WITH CHECK (true);
-- Users can read metadata for their own proofs
CREATE POLICY "meta_read"   ON public.preuve_metadata FOR SELECT TO authenticated USING (true);
-- Only service_role can update (fraud score is system-managed)
CREATE POLICY "meta_update" ON public.preuve_metadata FOR UPDATE TO service_role USING (true);

-- ---------------------------------------------------------------------------
-- 7. Indexes
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_preuve_meta_act   ON public.preuve_metadata (id_act);
CREATE INDEX IF NOT EXISTS idx_preuve_meta_proof ON public.preuve_metadata (id_preuve);
CREATE INDEX IF NOT EXISTS idx_preuve_meta_fraud ON public.preuve_metadata (fraud_score)
  WHERE fraud_score >= 50;
