-- =============================================================================
-- ECODZ — FULL FIX MIGRATION
-- Run this ONCE in Supabase → SQL Editor → New query → Run All
-- Safe to re-run (idempotent throughout)
-- =============================================================================
--
-- Issues fixed:
--   1. Missing UNIQUE constraints on vote_approbation & vote_completion
--      → duplicate votes were allowed; RPC dedup logic never triggered
--   2. Missing ON DELETE SET NULL on activite.assigned_worker_id FK
--   3. RLS enabled + policies for: activite, profiles, preuve,
--      type_activite, niveau_activite
--   4. Storage bucket 'activity_image' ensured public + upload policies
--   5. Latest cast_approval_vote (priority_pending flow, not 'approved')
--   6. All gamification RPCs ensured present
--   7. Data backfill: old 'pending' → 'waiting',
--                     old unassigned 'approved' → 'open'
--   8. handle_new_user trigger ensured (auto-creates profiles on signup)
-- =============================================================================


-- =============================================================================
-- FIX 1 — UNIQUE constraints on vote tables
-- Without these the UNIQUE-violation handler in the RPCs never fires,
-- a single user can cast unlimited votes, and the 2-vote cap is broken.
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname    = 'vote_approbation_unique_vote'
       AND conrelid   = 'public.vote_approbation'::regclass
  ) THEN
    ALTER TABLE public.vote_approbation
      ADD CONSTRAINT vote_approbation_unique_vote
      UNIQUE (id_act, id_utilisateur);
    RAISE NOTICE 'Added UNIQUE constraint to vote_approbation';
  ELSE
    RAISE NOTICE 'vote_approbation UNIQUE constraint already exists';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname    = 'vote_completion_unique_vote'
       AND conrelid   = 'public.vote_completion'::regclass
  ) THEN
    ALTER TABLE public.vote_completion
      ADD CONSTRAINT vote_completion_unique_vote
      UNIQUE (id_act, id_utilisateur);
    RAISE NOTICE 'Added UNIQUE constraint to vote_completion';
  ELSE
    RAISE NOTICE 'vote_completion UNIQUE constraint already exists';
  END IF;
END $$;


-- =============================================================================
-- FIX 2 — assigned_worker_id FK: add ON DELETE SET NULL
-- Prevents FK violation if a worker's account is deleted.
-- =============================================================================

ALTER TABLE public.activite
  DROP CONSTRAINT IF EXISTS activite_assigned_worker_id_fkey;

ALTER TABLE public.activite
  ADD CONSTRAINT activite_assigned_worker_id_fkey
  FOREIGN KEY (assigned_worker_id)
  REFERENCES public.profiles(id)
  ON DELETE SET NULL;


-- =============================================================================
-- FIX 3 — RLS on activite
-- Without this, any authenticated user can directly update activite.status
-- or activite.assigned_worker_id, bypassing all RPC business logic.
-- =============================================================================

ALTER TABLE public.activite ENABLE ROW LEVEL SECURITY;

-- All authenticated users can browse all activities (home feed, search, detail)
DROP POLICY IF EXISTS "Authenticated users can read activities" ON public.activite;
CREATE POLICY "Authenticated users can read activities"
  ON public.activite
  FOR SELECT TO authenticated
  USING (true);

-- Only the creator can INSERT a new activity (create_activity_modal.dart)
DROP POLICY IF EXISTS "Users can insert own activities" ON public.activite;
CREATE POLICY "Users can insert own activities"
  ON public.activite
  FOR INSERT TO authenticated
  WITH CHECK (id_utilisateur = auth.uid());

-- No direct UPDATE or DELETE from the client.
-- All status/assignment changes go through SECURITY DEFINER RPC functions
-- which bypass RLS entirely — no UPDATE policy needed here.


-- =============================================================================
-- FIX 4 — RLS on profiles
-- Without this, any user can directly set another user's xp or level.
-- =============================================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- All authenticated users can read all profiles
-- (needed to display organizer names, reputation, etc.)
DROP POLICY IF EXISTS "Authenticated users can read profiles" ON public.profiles;
CREATE POLICY "Authenticated users can read profiles"
  ON public.profiles
  FOR SELECT TO authenticated
  USING (true);

-- Users can INSERT their own profile
-- (needed for the upsert in create_activity_modal.dart and handle_new_user)
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
CREATE POLICY "Users can insert own profile"
  ON public.profiles
  FOR INSERT TO authenticated
  WITH CHECK (id = auth.uid());

-- Users can UPDATE only their own profile
-- XP/level updates go through SECURITY DEFINER RPCs → bypass this policy
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile"
  ON public.profiles
  FOR UPDATE TO authenticated
  USING    (id = auth.uid())
  WITH CHECK (id = auth.uid());


-- =============================================================================
-- FIX 5 — RLS on preuve
-- Without this, any user can insert or delete proofs for any activity.
-- =============================================================================

ALTER TABLE public.preuve ENABLE ROW LEVEL SECURITY;

-- All authenticated users can read proofs
DROP POLICY IF EXISTS "Authenticated users can read proofs" ON public.preuve;
CREATE POLICY "Authenticated users can read proofs"
  ON public.preuve
  FOR SELECT TO authenticated
  USING (true);

-- Only the activity creator (before-photo) OR the assigned worker (after-photo)
-- can insert proofs for a given activity.
DROP POLICY IF EXISTS "Users can insert proofs for their activities" ON public.preuve;
CREATE POLICY "Users can insert proofs for their activities"
  ON public.preuve
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.activite a
       WHERE a.id_act = preuve.id_act
         AND (
           a.id_utilisateur     = auth.uid()   -- creator adding before-photo
           OR a.assigned_worker_id = auth.uid() -- worker adding after-photo
         )
    )
  );


-- =============================================================================
-- FIX 6 — RLS on type_activite and niveau_activite (read-only reference data)
-- Required now that global RLS is tightened on other tables.
-- =============================================================================

ALTER TABLE public.type_activite ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read activity types" ON public.type_activite;
CREATE POLICY "Anyone can read activity types"
  ON public.type_activite
  FOR SELECT
  USING (true);  -- public reference data, no auth required

ALTER TABLE public.niveau_activite ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read activity levels" ON public.niveau_activite;
CREATE POLICY "Anyone can read activity levels"
  ON public.niveau_activite
  FOR SELECT
  USING (true);


-- =============================================================================
-- FIX 7 — Storage bucket 'activity_image'
-- The bucket must be public so getPublicUrl() works without a signed token.
-- Authenticated users must be allowed to upload (INSERT on storage.objects).
-- =============================================================================

-- Create the bucket if it doesn't exist, mark as public
INSERT INTO storage.buckets (id, name, public)
VALUES ('activity_image', 'activity_image', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Public read (allows getPublicUrl CDN links to work)
DROP POLICY IF EXISTS "Public can read activity images" ON storage.objects;
CREATE POLICY "Public can read activity images"
  ON storage.objects
  FOR SELECT
  USING (bucket_id = 'activity_image');

-- Authenticated users can upload images (create_activity_modal + work_completion_page)
DROP POLICY IF EXISTS "Authenticated users can upload activity images" ON storage.objects;
CREATE POLICY "Authenticated users can upload activity images"
  ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'activity_image');

-- Authenticated users can overwrite their own uploads (upsert: true in Flutter)
DROP POLICY IF EXISTS "Authenticated users can update activity images" ON storage.objects;
CREATE POLICY "Authenticated users can update activity images"
  ON storage.objects
  FOR UPDATE TO authenticated
  USING    (bucket_id = 'activity_image')
  WITH CHECK (bucket_id = 'activity_image');

-- Authenticated users can delete their own uploads
DROP POLICY IF EXISTS "Authenticated users can delete activity images" ON storage.objects;
CREATE POLICY "Authenticated users can delete activity images"
  ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'activity_image');


-- =============================================================================
-- FIX 8 — Ensure RLS + policies on vote_approbation
-- (may have been created without policies if voting_migration.sql was skipped)
-- =============================================================================

ALTER TABLE public.vote_approbation ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE tablename = 'vote_approbation'
       AND policyname = 'Authenticated users can read votes'
  ) THEN
    EXECUTE $p$
      CREATE POLICY "Authenticated users can read votes"
        ON public.vote_approbation
        FOR SELECT TO authenticated
        USING (true)
    $p$;
  END IF;
END $$;


-- =============================================================================
-- FIX 9 — Ensure RLS + policies on vote_completion
-- =============================================================================

ALTER TABLE public.vote_completion ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE tablename = 'vote_completion'
       AND policyname = 'Authenticated users can read completion votes'
  ) THEN
    EXECUTE $p$
      CREATE POLICY "Authenticated users can read completion votes"
        ON public.vote_completion
        FOR SELECT TO authenticated
        USING (true)
    $p$;
  END IF;
END $$;


-- =============================================================================
-- FIX 10 — Ensure RLS + policies on notification
-- =============================================================================

ALTER TABLE public.notification ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE tablename = 'notification'
       AND policyname = 'Users can read own notifications'
  ) THEN
    EXECUTE $p$
      CREATE POLICY "Users can read own notifications"
        ON public.notification FOR SELECT TO authenticated
        USING (id_utilisateur = auth.uid())
    $p$;
  END IF;
END $$;


-- =============================================================================
-- FIX 11 — handle_new_user trigger (auto-creates profiles on signup)
-- Safe to re-create — idempotent via CREATE OR REPLACE + DROP TRIGGER IF EXISTS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, phone_number, level, reputation, xp)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)),
    NEW.email,
    NEW.raw_user_meta_data->>'phone',
    1,
    0,
    0
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Backfill: create profiles rows for any auth users who are missing one
INSERT INTO public.profiles (id, full_name, email, level, reputation, xp)
SELECT
  u.id,
  COALESCE(u.raw_user_meta_data->>'name', split_part(u.email, '@', 1)),
  u.email,
  1, 0, 0
FROM auth.users u
WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id);


-- =============================================================================
-- FIX 12 — calculate_level function + trigger
-- =============================================================================

CREATE OR REPLACE FUNCTION public.calculate_level(p_xp integer)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_level       integer := 1;
  v_threshold   integer := 0;
  v_increment   integer := 30;
  v_transitions integer := 0;
BEGIN
  LOOP
    v_threshold  := v_threshold + v_increment;
    EXIT WHEN p_xp <= v_threshold;
    v_level      := v_level + 1;
    v_transitions := v_transitions + 1;
    IF v_transitions >= 2 THEN
      v_increment := v_increment + 30;
    END IF;
    EXIT WHEN v_level >= 100;
  END LOOP;
  RETURN v_level;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_level_from_xp()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.level := public.calculate_level(NEW.xp);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_level ON public.profiles;
CREATE TRIGGER trg_sync_level
  BEFORE UPDATE OF xp ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_level_from_xp();

-- Backfill level for all existing profiles
UPDATE public.profiles
   SET level = public.calculate_level(xp);


-- =============================================================================
-- FIX 13 — cast_approval_vote (CORRECT version: priority_pending flow)
-- This REPLACES any older version that set status = 'approved'.
-- After approval: status = 'priority_pending' + 2-min window for creator.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.cast_approval_vote(
  p_act_id  integer,
  p_user_id uuid,
  p_valeur  integer
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
  SELECT status, id_utilisateur
    INTO v_status, v_creator_id
    FROM activite
   WHERE id_act = p_act_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'activity_not_found');
  END IF;

  IF v_status <> 'waiting' THEN
    RETURN jsonb_build_object('error', 'voting_closed', 'status', v_status);
  END IF;

  IF v_creator_id = p_user_id THEN
    RETURN jsonb_build_object('error', 'own_activity');
  END IF;

  SELECT COUNT(*) INTO v_vote_count
    FROM vote_approbation
   WHERE id_act = p_act_id;

  IF v_vote_count >= 2 THEN
    RETURN jsonb_build_object('error', 'voting_closed');
  END IF;

  BEGIN
    INSERT INTO vote_approbation (id_act, id_utilisateur, valeur)
    VALUES (p_act_id, p_user_id, p_valeur);
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('error', 'already_voted');
  END;

  v_vote_count := v_vote_count + 1;

  IF v_vote_count >= 2 THEN
    SELECT
      COUNT(*) FILTER (WHERE valeur =  1),
      COUNT(*) FILTER (WHERE valeur = -1)
    INTO v_approve_count, v_reject_count
    FROM vote_approbation
    WHERE id_act = p_act_id;

    IF v_approve_count > v_reject_count THEN
      UPDATE activite
         SET status            = 'priority_pending',
             priority_deadline = now() + interval '2 minutes'
       WHERE id_act = p_act_id;

      INSERT INTO notification (type, id_utilisateur, message, id_act)
      VALUES (
        'priority_assignment',
        v_creator_id,
        'Your activity was approved! You have 2 minutes to accept as the assigned worker.',
        p_act_id
      );

      RETURN jsonb_build_object(
        'success',    true,
        'decided',    true,
        'new_status', 'priority_pending',
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


-- =============================================================================
-- FIX 14 — accept_priority_assignment
-- =============================================================================

CREATE OR REPLACE FUNCTION public.accept_priority_assignment(
  p_act_id  integer,
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status   text;
  v_creator  uuid;
  v_deadline timestamptz;
BEGIN
  SELECT status, id_utilisateur, priority_deadline
    INTO v_status, v_creator, v_deadline
    FROM activite
   WHERE id_act = p_act_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'activity_not_found');
  END IF;

  IF v_status <> 'priority_pending' THEN
    RETURN jsonb_build_object('error', 'not_priority_pending', 'status', v_status);
  END IF;

  IF v_creator <> p_user_id THEN
    RETURN jsonb_build_object('error', 'not_creator');
  END IF;

  IF v_deadline IS NOT NULL AND now() > v_deadline THEN
    UPDATE activite
       SET status = 'open', priority_deadline = NULL
     WHERE id_act = p_act_id;
    RETURN jsonb_build_object('error', 'deadline_expired');
  END IF;

  UPDATE activite
     SET status             = 'in_progress',
         assigned_worker_id = p_user_id,
         priority_deadline  = NULL
   WHERE id_act = p_act_id;

  RETURN jsonb_build_object('success', true);
END;
$$;


-- =============================================================================
-- FIX 15 — decline_priority_assignment
-- =============================================================================

CREATE OR REPLACE FUNCTION public.decline_priority_assignment(
  p_act_id  integer,
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status  text;
  v_creator uuid;
BEGIN
  SELECT status, id_utilisateur
    INTO v_status, v_creator
    FROM activite
   WHERE id_act = p_act_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'activity_not_found');
  END IF;

  IF v_status <> 'priority_pending' THEN
    RETURN jsonb_build_object('error', 'not_priority_pending', 'status', v_status);
  END IF;

  IF v_creator <> p_user_id THEN
    RETURN jsonb_build_object('error', 'not_creator');
  END IF;

  UPDATE activite
     SET status            = 'open',
         priority_deadline = NULL
   WHERE id_act = p_act_id;

  RETURN jsonb_build_object('success', true);
END;
$$;


-- =============================================================================
-- FIX 16 — join_open_activity
-- =============================================================================

CREATE OR REPLACE FUNCTION public.join_open_activity(
  p_act_id  integer,
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status  text;
  v_creator uuid;
BEGIN
  SELECT status, id_utilisateur
    INTO v_status, v_creator
    FROM activite
   WHERE id_act = p_act_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'activity_not_found');
  END IF;

  -- Accept both new 'open' and legacy 'approved' statuses
  IF v_status NOT IN ('open', 'approved') THEN
    RETURN jsonb_build_object('error', 'not_available', 'status', v_status);
  END IF;

  IF v_creator = p_user_id THEN
    RETURN jsonb_build_object('error', 'own_activity');
  END IF;

  UPDATE activite
     SET status             = 'in_progress',
         assigned_worker_id = p_user_id
   WHERE id_act = p_act_id;

  RETURN jsonb_build_object('success', true);
END;
$$;


-- =============================================================================
-- FIX 17 — submit_work_completion
-- =============================================================================

CREATE OR REPLACE FUNCTION public.submit_work_completion(
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
  v_worker uuid;
BEGIN
  SELECT status, assigned_worker_id
    INTO v_status, v_worker
    FROM activite
   WHERE id_act = p_act_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'activity_not_found');
  END IF;

  IF v_status <> 'in_progress' THEN
    RETURN jsonb_build_object('error', 'not_in_progress', 'status', v_status);
  END IF;

  IF v_worker <> p_user_id THEN
    RETURN jsonb_build_object('error', 'not_assigned_worker');
  END IF;

  UPDATE activite
     SET status       = 'pending_validation',
         completed_at = now()
   WHERE id_act = p_act_id;

  RETURN jsonb_build_object('success', true);
END;
$$;


-- =============================================================================
-- FIX 18 — cast_completion_vote
-- Community votes on submitted work; majority of min 2 votes decides outcome.
-- Approve → XP awarded to worker, status = 'completed'
-- Reject  → activity returns to 'open', votes cleared for fresh attempt
-- =============================================================================

-- Drop first because PostgreSQL won't allow renaming existing parameters
-- via CREATE OR REPLACE.
DROP FUNCTION IF EXISTS public.cast_completion_vote(integer, uuid, boolean, integer);

CREATE OR REPLACE FUNCTION public.cast_completion_vote(
  p_act_id      integer,
  p_user_id     uuid,
  p_approve     boolean,
  p_xp_proposal integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status        text;
  v_worker        uuid;
  v_vote_count    integer;
  v_approve_count integer;
  v_reject_count  integer;
  v_avg_xp        integer;
BEGIN
  SELECT status, assigned_worker_id
    INTO v_status, v_worker
    FROM activite
   WHERE id_act = p_act_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'activity_not_found');
  END IF;

  IF v_status <> 'pending_validation' THEN
    RETURN jsonb_build_object('error', 'voting_closed', 'status', v_status);
  END IF;

  IF v_worker = p_user_id THEN
    RETURN jsonb_build_object('error', 'own_work');
  END IF;

  SELECT COUNT(*) INTO v_vote_count
    FROM vote_completion
   WHERE id_act = p_act_id;

  IF v_vote_count >= 5 THEN
    RETURN jsonb_build_object('error', 'voting_closed');
  END IF;

  BEGIN
    INSERT INTO vote_completion (id_act, id_utilisateur, approve, xp_proposal)
    VALUES (
      p_act_id,
      p_user_id,
      p_approve,
      CASE WHEN p_approve THEN p_xp_proposal ELSE NULL END
    );
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('error', 'already_voted');
  END;

  v_vote_count := v_vote_count + 1;

  IF v_vote_count >= 2 THEN
    SELECT
      COUNT(*) FILTER (WHERE approve = true),
      COUNT(*) FILTER (WHERE approve = false)
    INTO v_approve_count, v_reject_count
    FROM vote_completion
    WHERE id_act = p_act_id;

    IF v_approve_count > v_reject_count THEN
      SELECT COALESCE(AVG(xp_proposal)::integer, 0)
        INTO v_avg_xp
        FROM vote_completion
       WHERE id_act      = p_act_id
         AND approve     = true
         AND xp_proposal IS NOT NULL;

      IF v_worker IS NOT NULL AND v_avg_xp > 0 THEN
        UPDATE profiles SET xp = xp + v_avg_xp WHERE id = v_worker;
      END IF;

      UPDATE activite SET status = 'completed' WHERE id_act = p_act_id;

      RETURN jsonb_build_object(
        'success',    true,
        'decided',    true,
        'new_status', 'completed',
        'xp_awarded', v_avg_xp,
        'vote_count', v_vote_count
      );

    ELSIF v_reject_count > v_approve_count THEN
      UPDATE activite
         SET status             = 'open',
             assigned_worker_id = NULL,
             completed_at       = NULL
       WHERE id_act = p_act_id;

      DELETE FROM vote_completion WHERE id_act = p_act_id;

      RETURN jsonb_build_object(
        'success',    true,
        'decided',    true,
        'new_status', 'open',
        'vote_count', v_vote_count
      );
    END IF;
    -- Tie → wait for more votes
  END IF;

  RETURN jsonb_build_object(
    'success',    true,
    'decided',    false,
    'vote_count', v_vote_count
  );
END;
$$;


-- =============================================================================
-- FIX 19 — expire_priority_assignments (call on app startup)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.expire_priority_assignments()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  UPDATE activite
     SET status            = 'open',
         priority_deadline = NULL
   WHERE status            = 'priority_pending'
     AND priority_deadline < now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;


-- =============================================================================
-- FIX 20 — Performance indexes
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_activite_status
  ON public.activite(status);

CREATE INDEX IF NOT EXISTS idx_activite_worker
  ON public.activite(assigned_worker_id);

CREATE INDEX IF NOT EXISTS idx_activite_priority_deadline
  ON public.activite(priority_deadline)
  WHERE status = 'priority_pending';

CREATE INDEX IF NOT EXISTS idx_notification_user_unread
  ON public.notification(id_utilisateur, is_read);

CREATE INDEX IF NOT EXISTS idx_vote_approbation_act
  ON public.vote_approbation(id_act);

CREATE INDEX IF NOT EXISTS idx_vote_completion_act
  ON public.vote_completion(id_act);


-- =============================================================================
-- FIX 21 — Data backfill
-- Align old status values with the new vocabulary.
-- =============================================================================

-- Old 'pending' → 'waiting' (new name for the approval-voting phase)
UPDATE public.activite
   SET status = 'waiting'
 WHERE status = 'pending';

-- Old 'approved' with NO assigned worker → 'open'
-- (these were approved under the old system but never picked up)
UPDATE public.activite
   SET status = 'open'
 WHERE status = 'approved'
   AND assigned_worker_id IS NULL;

-- Old 'approved' WITH an assigned worker → 'in_progress'
-- (someone was already working on them)
UPDATE public.activite
   SET status = 'in_progress'
 WHERE status = 'approved'
   AND assigned_worker_id IS NOT NULL;

-- Sync all levels from current XP values
UPDATE public.profiles
   SET level = public.calculate_level(xp);


-- =============================================================================
-- DONE
-- =============================================================================
-- Status vocabulary (for reference):
--   waiting            → created, awaiting 2 community approval votes
--   priority_pending   → approved; creator has 2-min priority window
--   open               → creator declined/expired; open for any user to join
--   in_progress        → assigned worker is actively working
--   pending_validation → worker submitted after-photos; community validates
--   completed          → approved by community; XP awarded to worker
--   rejected           → rejected by approval or validation vote
-- =============================================================================
