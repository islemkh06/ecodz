-- =============================================================================
-- My Activities Migration
-- Run this in your Supabase SQL Editor (Database > SQL Editor > New query)
-- =============================================================================
-- This migration sets up the reservation table's RLS policies and status
-- convention required by the "My Activities" feature in the Flutter app.
--
-- The reservation table already exists with:
--   id_reserv, datedebut, date_exp, status, id_utilisateur, id_act
--
-- status values used by the app:
--   'active'    → user is currently participating in the activity
--   'completed' → user has finished participating in the activity
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Enable Row Level Security on reservation (if not already enabled)
-- -----------------------------------------------------------------------------
ALTER TABLE public.reservation ENABLE ROW LEVEL SECURITY;


-- -----------------------------------------------------------------------------
-- 2. RLS Policies for reservation
-- -----------------------------------------------------------------------------

-- Users can read their own reservations (needed by My Activities queries)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'reservation'
      AND policyname = 'Users can read own reservations'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "Users can read own reservations"
        ON public.reservation
        FOR SELECT
        TO authenticated
        USING (id_utilisateur = auth.uid())
    $policy$;
  END IF;
END $$;

-- Users can insert their own reservations
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'reservation'
      AND policyname = 'Users can insert own reservations'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "Users can insert own reservations"
        ON public.reservation
        FOR INSERT
        TO authenticated
        WITH CHECK (id_utilisateur = auth.uid())
    $policy$;
  END IF;
END $$;

-- Users can update their own reservations (e.g. marking as completed)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'reservation'
      AND policyname = 'Users can update own reservations'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "Users can update own reservations"
        ON public.reservation
        FOR UPDATE
        TO authenticated
        USING (id_utilisateur = auth.uid())
        WITH CHECK (id_utilisateur = auth.uid())
    $policy$;
  END IF;
END $$;


-- -----------------------------------------------------------------------------
-- 3. Performance index on reservation(id_utilisateur, status)
--    Speeds up the My Activities queries that filter by user + status.
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS reservation_utilisateur_status_idx
  ON public.reservation (id_utilisateur, status);


-- -----------------------------------------------------------------------------
-- 4. Optional helper function: join_activity
--    Lets users reserve / join an approved activity in one call.
--    Returns: { "success": true } or { "error": "already_joined" | "not_approved" | "activity_not_found" }
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.join_activity(
  p_act_id  integer,
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
BEGIN
  -- Check activity exists and is approved
  SELECT status INTO v_status FROM activite WHERE id_act = p_act_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'activity_not_found');
  END IF;

  IF v_status <> 'approved' THEN
    RETURN jsonb_build_object('error', 'not_approved', 'status', v_status);
  END IF;

  -- Prevent duplicate joins
  IF EXISTS (
    SELECT 1 FROM reservation
    WHERE id_act = p_act_id AND id_utilisateur = p_user_id
  ) THEN
    RETURN jsonb_build_object('error', 'already_joined');
  END IF;

  INSERT INTO reservation (id_utilisateur, id_act, status, datedebut)
  VALUES (p_user_id, p_act_id, 'active', now());

  RETURN jsonb_build_object('success', true);
END;
$$;
