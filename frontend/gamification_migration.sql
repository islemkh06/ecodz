-- =============================================================================
-- GAMIFICATION + ACTIVITY PRIORITY FLOW MIGRATION
-- Run this in your Supabase SQL Editor (Database > SQL Editor > New query)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Add XP column to profiles
-- ---------------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS xp integer NOT NULL DEFAULT 0;

-- ---------------------------------------------------------------------------
-- 2. Add assignment & deadline columns to activite
-- ---------------------------------------------------------------------------
ALTER TABLE public.activite
  ADD COLUMN IF NOT EXISTS assigned_worker_id uuid
    REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS priority_deadline timestamptz,
  ADD COLUMN IF NOT EXISTS completed_at timestamptz;

-- ---------------------------------------------------------------------------
-- 3. Add id_act & is_read to notification
-- ---------------------------------------------------------------------------
ALTER TABLE public.notification
  ADD COLUMN IF NOT EXISTS is_read boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS id_act integer REFERENCES public.activite(id_act) ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- 4. Create vote_completion table
--    Stores one validation vote per user per activity after work is submitted.
--    xp_proposal is the XP reward proposed by voters who approve the work.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.vote_completion (
  id              serial       PRIMARY KEY,
  id_act          integer      NOT NULL REFERENCES public.activite(id_act) ON DELETE CASCADE,
  id_utilisateur  uuid         NOT NULL REFERENCES public.profiles(id),
  approve         boolean      NOT NULL,
  xp_proposal     integer      CHECK (xp_proposal IS NULL OR xp_proposal >= 0),
  created_at      timestamptz  DEFAULT now(),
  UNIQUE (id_act, id_utilisateur)
);

ALTER TABLE public.vote_completion ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read completion votes"
  ON public.vote_completion FOR SELECT TO authenticated USING (true);

CREATE POLICY "Users can insert own completion votes"
  ON public.vote_completion FOR INSERT TO authenticated
  WITH CHECK (id_utilisateur = auth.uid());

-- ---------------------------------------------------------------------------
-- 5. Performance indexes
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_activite_status
  ON public.activite(status);

CREATE INDEX IF NOT EXISTS idx_activite_worker
  ON public.activite(assigned_worker_id);

CREATE INDEX IF NOT EXISTS idx_activite_priority_deadline
  ON public.activite(priority_deadline)
  WHERE status = 'priority_pending';

CREATE INDEX IF NOT EXISTS idx_notification_user_unread
  ON public.notification(id_utilisateur, is_read);

-- ---------------------------------------------------------------------------
-- 6. calculate_level(xp) – pure, immutable level calculation
--
--    Level thresholds (max XP per level):
--      Level 1 :   0 – 30   (range  30)
--      Level 2 :  31 – 60   (range  30)
--      Level 3 :  61 – 120  (range  60)
--      Level 4 : 121 – 210  (range  90)
--      Level 5 : 211 – 330  (range 120)
--      … each range grows by +30 after level 2
-- ---------------------------------------------------------------------------
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
    v_threshold := v_threshold + v_increment;
    EXIT WHEN p_xp <= v_threshold;          -- still within this level
    v_level      := v_level + 1;
    v_transitions := v_transitions + 1;
    IF v_transitions >= 2 THEN
      v_increment := v_increment + 30;       -- grow range after L2
    END IF;
    EXIT WHEN v_level >= 100;               -- safety cap
  END LOOP;
  RETURN v_level;
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. Trigger: auto-recalculate level whenever XP changes
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 8. cast_approval_vote (updated)
--    Now sets status = 'priority_pending' on approval instead of 'approved',
--    and creates a notification for the creator.
-- ---------------------------------------------------------------------------
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
      -- Give creator a 2-minute priority window
      UPDATE activite
         SET status           = 'priority_pending',
             priority_deadline = now() + interval '2 minutes'
       WHERE id_act = p_act_id;

      -- Notify creator
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

-- ---------------------------------------------------------------------------
-- 9. accept_priority_assignment
--    Creator accepts their priority window → in_progress
-- ---------------------------------------------------------------------------
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

  -- Check if deadline has passed
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

-- ---------------------------------------------------------------------------
-- 10. decline_priority_assignment
--     Creator declines → open for all
-- ---------------------------------------------------------------------------
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
     SET status           = 'open',
         priority_deadline = NULL
   WHERE id_act = p_act_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- ---------------------------------------------------------------------------
-- 11. join_open_activity
--     Any non-creator user joins an open activity → in_progress
-- ---------------------------------------------------------------------------
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

  -- Accept both 'open' (new) and 'approved' (legacy) statuses
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

-- ---------------------------------------------------------------------------
-- 12. submit_work_completion
--     Assigned worker submits → pending_validation
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 13. cast_completion_vote
--     Community votes on completed work with optional XP proposal.
--     Minimum 2 votes; majority wins.
--     On approval: XP = avg(xp_proposal) from YES votes → awarded to worker.
--     On rejection: activity returns to 'open' for reassignment.
-- ---------------------------------------------------------------------------
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
  v_creator       uuid;
  v_vote_count    integer;
  v_approve_count integer;
  v_reject_count  integer;
  v_avg_xp        integer;
BEGIN
  SELECT status, assigned_worker_id, id_utilisateur
    INTO v_status, v_worker, v_creator
    FROM activite
   WHERE id_act = p_act_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'activity_not_found');
  END IF;

  IF v_status <> 'pending_validation' THEN
    RETURN jsonb_build_object('error', 'voting_closed', 'status', v_status);
  END IF;

  -- Worker cannot vote on their own completion
  IF v_worker = p_user_id THEN
    RETURN jsonb_build_object('error', 'own_work');
  END IF;

  SELECT COUNT(*) INTO v_vote_count
    FROM vote_completion
   WHERE id_act = p_act_id;

  -- Cap at 5 votes per activity
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

  -- Decide after minimum 2 votes
  IF v_vote_count >= 2 THEN
    SELECT
      COUNT(*) FILTER (WHERE approve = true),
      COUNT(*) FILTER (WHERE approve = false)
    INTO v_approve_count, v_reject_count
    FROM vote_completion
    WHERE id_act = p_act_id;

    IF v_approve_count > v_reject_count THEN
      -- Average XP from YES voters (who provided a proposal)
      SELECT COALESCE(AVG(xp_proposal)::integer, 0)
        INTO v_avg_xp
        FROM vote_completion
       WHERE id_act = p_act_id
         AND approve = true
         AND xp_proposal IS NOT NULL;

      -- Award XP to worker and auto-update level via trigger
      IF v_worker IS NOT NULL AND v_avg_xp > 0 THEN
        UPDATE profiles
           SET xp = xp + v_avg_xp
         WHERE id = v_worker;
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
      -- Return to open pool for reassignment
      UPDATE activite
         SET status             = 'open',
             assigned_worker_id = NULL,
             completed_at       = NULL
       WHERE id_act = p_act_id;

      -- Clear completion votes so fresh workers can attempt
      DELETE FROM vote_completion WHERE id_act = p_act_id;

      RETURN jsonb_build_object(
        'success',    true,
        'decided',    true,
        'new_status', 'open',
        'vote_count', v_vote_count
      );
    END IF;
    -- Tie: do nothing, wait for more votes
  END IF;

  RETURN jsonb_build_object(
    'success',    true,
    'decided',    false,
    'vote_count', v_vote_count
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 14. expire_priority_assignments
--     Call periodically (e.g., from app startup or a pg_cron job).
--     Moves expired priority_pending activities to 'open'.
-- ---------------------------------------------------------------------------
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
     SET status           = 'open',
         priority_deadline = NULL
   WHERE status = 'priority_pending'
     AND priority_deadline < now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- ---------------------------------------------------------------------------
-- 15. RLS policies for notification
-- ---------------------------------------------------------------------------
ALTER TABLE public.notification ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'notification' AND policyname = 'Users can read own notifications'
  ) THEN
    EXECUTE $p$
      CREATE POLICY "Users can read own notifications"
        ON public.notification FOR SELECT TO authenticated
        USING (id_utilisateur = auth.uid())
    $p$;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'notification' AND policyname = 'System can insert notifications'
  ) THEN
    EXECUTE $p$
      CREATE POLICY "System can insert notifications"
        ON public.notification FOR INSERT TO authenticated
        WITH CHECK (true)
    $p$;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 16. Backfill: sync level for all existing profiles with XP
-- ---------------------------------------------------------------------------
UPDATE public.profiles
   SET level = public.calculate_level(xp)
 WHERE true;

-- ---------------------------------------------------------------------------
-- DONE
-- New activity status vocabulary:
--   waiting           → awaiting community approval votes
--   priority_pending  → approved, creator has 2-min priority window
--   open              → open for any user to join
--   in_progress       → has assigned worker, work ongoing
--   pending_validation → worker submitted, awaiting community validation
--   completed         → fully done, XP awarded
--   rejected          → rejected by community
-- ---------------------------------------------------------------------------
