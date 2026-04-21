-- =============================================================================
-- Voting System Migration
-- Run this in your Supabase SQL Editor (Database > SQL Editor > New query)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. vote_approbation table
--    Stores one approval/rejection vote per user per activity.
--    UNIQUE(id_act, id_utilisateur) enforces the no-double-vote rule at DB level.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.vote_approbation (
  id              serial       PRIMARY KEY,
  id_act          integer      NOT NULL REFERENCES public.activite(id_act) ON DELETE CASCADE,
  id_utilisateur  uuid         NOT NULL REFERENCES public.profiles(id),
  valeur          integer      NOT NULL CHECK (valeur IN (1, -1)),  -- 1 = approve, -1 = reject
  created_at      timestamptz  DEFAULT now(),
  UNIQUE (id_act, id_utilisateur)
);

-- Enable Row Level Security
ALTER TABLE public.vote_approbation ENABLE ROW LEVEL SECURITY;

-- Authenticated users can read all votes (needed to show vote counts)
CREATE POLICY "Authenticated users can read votes"
  ON public.vote_approbation
  FOR SELECT
  TO authenticated
  USING (true);

-- Inserts are done exclusively through the RPC function (SECURITY DEFINER),
-- so no INSERT policy is required on the table itself.


-- -----------------------------------------------------------------------------
-- 2. RPC function: cast_approval_vote
--
--    Handles the full voting lifecycle atomically:
--      - Validates the activity is still in 'waiting' state (row-level lock)
--      - Prevents the creator from voting on their own activity
--      - Prevents duplicate votes (UNIQUE constraint + graceful error)
--      - Enforces the 2-vote cap
--      - Decides outcome after the 2nd vote and updates activite.status
--
--    Returns a jsonb object:
--      { "success": true, "decided": false, "vote_count": 1 }
--      { "success": true, "decided": true,  "new_status": "approved"|"rejected", "vote_count": 2 }
--      { "error": "already_voted" | "own_activity" | "voting_closed" | "activity_not_found" }
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cast_approval_vote(
  p_act_id   integer,
  p_user_id  uuid,
  p_valeur   integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status        text;
  v_creator_id    uuid;
  v_vote_count    integer;
  v_approve_count integer;
  v_reject_count  integer;
BEGIN
  -- Lock the activity row to serialise concurrent votes (prevents race conditions)
  SELECT status, id_utilisateur
    INTO v_status, v_creator_id
    FROM activite
   WHERE id_act = p_act_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'activity_not_found');
  END IF;

  -- Only 'waiting' activities accept votes
  IF v_status <> 'waiting' THEN
    RETURN jsonb_build_object('error', 'voting_closed', 'status', v_status);
  END IF;

  -- Creators cannot vote on their own activity
  IF v_creator_id = p_user_id THEN
    RETURN jsonb_build_object('error', 'own_activity');
  END IF;

  -- Count existing votes; enforce the 2-vote cap
  SELECT COUNT(*) INTO v_vote_count
    FROM vote_approbation
   WHERE id_act = p_act_id;

  IF v_vote_count >= 2 THEN
    RETURN jsonb_build_object('error', 'voting_closed');
  END IF;

  -- Insert vote; UNIQUE constraint prevents duplicates at DB level
  BEGIN
    INSERT INTO vote_approbation (id_act, id_utilisateur, valeur)
    VALUES (p_act_id, p_user_id, p_valeur);
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('error', 'already_voted');
  END;

  v_vote_count := v_vote_count + 1;

  -- If this was the 2nd vote, decide the outcome
  IF v_vote_count >= 2 THEN
    SELECT
      COUNT(*) FILTER (WHERE valeur =  1),
      COUNT(*) FILTER (WHERE valeur = -1)
    INTO v_approve_count, v_reject_count
    FROM vote_approbation
    WHERE id_act = p_act_id;

    IF v_approve_count > v_reject_count THEN
      UPDATE activite SET status = 'approved' WHERE id_act = p_act_id;
      RETURN jsonb_build_object(
        'success',    true,
        'decided',    true,
        'new_status', 'approved',
        'vote_count', v_vote_count
      );
    ELSE
      UPDATE activite SET status = 'rejected' WHERE id_act = p_act_id;
      RETURN jsonb_build_object(
        'success',    true,
        'decided',    true,
        'new_status', 'rejected',
        'vote_count', v_vote_count
      );
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success',    true,
    'decided',    false,
    'vote_count', v_vote_count
  );
END;
$$;


-- -----------------------------------------------------------------------------
-- 3. Update any existing 'pending' activities to 'waiting'
--    (aligns old data with the new status vocabulary)
-- -----------------------------------------------------------------------------
UPDATE public.activite
   SET status = 'waiting'
 WHERE status = 'pending';


-- -----------------------------------------------------------------------------
-- 4. Auto-create a profiles row when a user signs up via Supabase Auth
--
--    Without this, new users have no profiles row, and any insert into
--    activite (which has activite_id_utilisateur_fkey → profiles.id)
--    will throw a foreign-key violation.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, phone_number, level, reputation)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)),
    NEW.email,
    NEW.raw_user_meta_data->>'phone',
    1,
    0
  )
  ON CONFLICT (id) DO NOTHING;   -- idempotent: safe to re-run
  RETURN NEW;
END;
$$;

-- Drop the trigger first so this migration is re-runnable
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Backfill: create profiles for any auth users who are missing one
INSERT INTO public.profiles (id, full_name, email, level, reputation)
SELECT
  u.id,
  COALESCE(u.raw_user_meta_data->>'name', split_part(u.email, '@', 1)),
  u.email,
  1,
  0
FROM auth.users u
WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id);


-- =============================================================================
-- Done. Summary of statuses used by the app:
--   'waiting'  → newly created, visible in voting feed (activity.dart)
--   'approved' → passed community vote, visible in home + search
--   'rejected' → failed community vote, hidden everywhere
-- =============================================================================
