-- =============================================================================
-- FEATURE: Group Event Lifecycle Management
-- Run AFTER: feature_group_activities.sql, feature_creator_priority.sql,
--            gamification_migration.sql
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Add lifecycle columns to activite
-- ---------------------------------------------------------------------------
ALTER TABLE public.activite
  ADD COLUMN IF NOT EXISTS locked_at         timestamptz,   -- set when event transitions to 'locked'
  ADD COLUMN IF NOT EXISTS event_started_at  timestamptz;   -- set when event transitions to 'in_progress' (group)

-- Index: fast lookup of open group events approaching their start time
CREATE INDEX IF NOT EXISTS idx_activite_group_event_date
  ON public.activite (event_date)
  WHERE activity_mode = 'group' AND status IN ('open', 'locked');

-- ---------------------------------------------------------------------------
-- 2. lock_due_group_events()
--
--    Transitions open group events → 'locked' exactly 5 minutes before
--    their event_date.  Call from:
--      • A pg_cron job: SELECT cron.schedule('lock-events','* * * * *','SELECT lock_due_group_events()');
--      • Or each app client on load / background refresh.
--
--    Returns the number of rows locked.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.lock_due_group_events()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  UPDATE public.activite
     SET status    = 'locked',
         locked_at = now()
   WHERE activity_mode = 'group'
     AND status IN ('open', 'approved')   -- both legacy statuses accepted
     AND event_date IS NOT NULL
     AND now() >= event_date - interval '5 minutes'
     AND now() <  event_date;             -- not started yet

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. start_due_group_events()
--
--    Transitions locked group events → 'in_progress' once event_date passes.
--    Also handles any 'open' events that were never locked (edge cases).
--
--    Returns the number of rows started.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.start_due_group_events()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  UPDATE public.activite
     SET status           = 'in_progress',
         event_started_at = now()
   WHERE activity_mode = 'group'
     AND status IN ('locked', 'open', 'approved')
     AND event_date IS NOT NULL
     AND now() >= event_date;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. refresh_group_event_status(p_activity_id)
--
--    Atomically checks and advances a SINGLE group event through the
--    lock → start lifecycle.  Call from the Flutter client when opening
--    the event detail page (or on a 30-second real-time timer).
--
--    Returns the current status after any transitions.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.refresh_group_event_status(p_activity_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_act  public.activite%ROWTYPE;
BEGIN
  SELECT * INTO v_act
    FROM public.activite
   WHERE id_act        = p_activity_id
     AND activity_mode = 'group'
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'event_not_found');
  END IF;

  -- Nothing to do if already past open phase
  IF v_act.status NOT IN ('open', 'approved', 'locked') THEN
    RETURN jsonb_build_object('status', v_act.status, 'changed', false);
  END IF;

  IF v_act.event_date IS NULL THEN
    RETURN jsonb_build_object('status', v_act.status, 'changed', false);
  END IF;

  -- Transition: started
  IF now() >= v_act.event_date THEN
    UPDATE public.activite
       SET status           = 'in_progress',
           event_started_at = now()
     WHERE id_act = p_activity_id;
    RETURN jsonb_build_object('status', 'in_progress', 'changed', true);
  END IF;

  -- Transition: lock (5 min window)
  IF now() >= v_act.event_date - interval '5 minutes' AND v_act.status <> 'locked' THEN
    UPDATE public.activite
       SET status    = 'locked',
           locked_at = now()
     WHERE id_act = p_activity_id;
    RETURN jsonb_build_object('status', 'locked', 'changed', true);
  END IF;

  RETURN jsonb_build_object('status', v_act.status, 'changed', false);
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. update join_group_activity
--    Reject joins when the event is locked or already in_progress.
--    No priority phase logic (organizer is auto-added on approval).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.join_group_activity(
  p_activity_id integer,
  p_user_id     uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_act public.activite%ROWTYPE;
BEGIN
  SELECT * INTO v_act
    FROM public.activite
   WHERE id_act = p_activity_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'activity_not_found');
  END IF;

  IF v_act.activity_mode <> 'group' THEN
    RETURN json_build_object('success', false, 'error', 'not_a_group_activity');
  END IF;

  -- Auto-advance status if needed before checking
  IF v_act.event_date IS NOT NULL AND now() >= v_act.event_date THEN
    UPDATE public.activite
       SET status           = 'in_progress',
           event_started_at = now()
     WHERE id_act = p_activity_id;
    v_act.status := 'in_progress';
  ELSIF v_act.event_date IS NOT NULL
        AND now() >= v_act.event_date - interval '5 minutes'
        AND v_act.status IN ('open', 'approved') THEN
    UPDATE public.activite
       SET status    = 'locked',
           locked_at = now()
     WHERE id_act = p_activity_id;
    v_act.status := 'locked';
  END IF;

  -- Block joins when locked or started
  IF v_act.status = 'locked' THEN
    RETURN json_build_object('success', false, 'error', 'event_locked');
  END IF;

  IF v_act.status = 'in_progress' THEN
    RETURN json_build_object('success', false, 'error', 'event_started');
  END IF;

  IF v_act.status NOT IN ('open', 'approved') THEN
    RETURN json_build_object('success', false, 'error', 'activity_not_open');
  END IF;

  IF v_act.current_participants_count >= COALESCE(v_act.max_participants, 9999) THEN
    RETURN json_build_object('success', false, 'error', 'activity_full');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.activity_participants
     WHERE activity_id = p_activity_id
       AND user_id     = p_user_id
       AND status      = 'confirmed'
  ) THEN
    RETURN json_build_object('success', false, 'error', 'already_joined');
  END IF;

  INSERT INTO public.activity_participants (activity_id, user_id, status)
  VALUES (p_activity_id, p_user_id, 'confirmed')
  ON CONFLICT (activity_id, user_id)
    DO UPDATE SET status = 'confirmed', joined_at = now();

  UPDATE public.activite
     SET current_participants_count = (
           SELECT COUNT(*) FROM public.activity_participants
            WHERE activity_id = p_activity_id AND status = 'confirmed'
         )
   WHERE id_act = p_activity_id;

  -- Creator joining during priority phase → transition to open
  IF v_act.status = 'priority_pending' AND v_act.id_utilisateur = p_user_id THEN
    UPDATE public.activite
       SET status                  = 'open',
           creator_priority_status = 'accepted'
     WHERE id_act = p_activity_id;
  END IF;

  RETURN json_build_object('success', true);
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. update leave_group_activity
--    Reject leaves when the event is locked or already in_progress.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.leave_group_activity(
  p_activity_id integer,
  p_user_id     uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_status   text;
  v_evt_date timestamptz;
BEGIN
  SELECT status, event_date
    INTO v_status, v_evt_date
    FROM public.activite
   WHERE id_act = p_activity_id
   FOR UPDATE;

  -- Auto-advance status if needed
  IF v_evt_date IS NOT NULL AND now() >= v_evt_date THEN
    UPDATE public.activite
       SET status = 'in_progress', event_started_at = now()
     WHERE id_act = p_activity_id AND status IN ('open', 'approved', 'locked');
    v_status := 'in_progress';
  ELSIF v_evt_date IS NOT NULL
        AND now() >= v_evt_date - interval '5 minutes'
        AND v_status IN ('open', 'approved') THEN
    UPDATE public.activite
       SET status = 'locked', locked_at = now()
     WHERE id_act = p_activity_id;
    v_status := 'locked';
  END IF;

  IF v_status = 'locked' THEN
    RETURN json_build_object('success', false, 'error', 'event_locked');
  END IF;

  IF v_status = 'in_progress' THEN
    RETURN json_build_object('success', false, 'error', 'event_started');
  END IF;

  UPDATE public.activity_participants
     SET status = 'cancelled'
   WHERE activity_id = p_activity_id
     AND user_id     = p_user_id;

  UPDATE public.activite
     SET current_participants_count = (
           SELECT COUNT(*) FROM public.activity_participants
            WHERE activity_id = p_activity_id AND status = 'confirmed'
         )
   WHERE id_act = p_activity_id;

  RETURN json_build_object('success', true);
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. submit_group_event_completion(p_activity_id, p_user_id)
--
--    Called by any confirmed participant (or the organizer) after the group
--    event has started.  Transitions the event to 'pending_validation'.
--
--    Rules:
--      • Event must be in 'in_progress' status.
--      • Caller must be a confirmed participant OR the organizer.
--      • Completion photos must already be uploaded (preuve rows with type='apres').
--      • The event start time must have passed (NOW() >= event_date).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_group_event_completion(
  p_activity_id integer,
  p_user_id     uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_act        public.activite%ROWTYPE;
  v_is_member  boolean;
BEGIN
  SELECT * INTO v_act
    FROM public.activite
   WHERE id_act        = p_activity_id
     AND activity_mode = 'group'
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'event_not_found');
  END IF;

  -- Must be in_progress
  IF v_act.status <> 'in_progress' THEN
    RETURN jsonb_build_object('error', 'event_not_started', 'status', v_act.status);
  END IF;

  -- Must have actually started (belt-and-suspenders)
  IF v_act.event_date IS NOT NULL AND now() < v_act.event_date THEN
    RETURN jsonb_build_object('error', 'event_not_started_yet');
  END IF;

  -- Caller must be the organizer or a confirmed participant
  v_is_member := (v_act.id_utilisateur = p_user_id) OR EXISTS (
    SELECT 1 FROM public.activity_participants
     WHERE activity_id = p_activity_id
       AND user_id     = p_user_id
       AND status      = 'confirmed'
  );

  IF NOT v_is_member THEN
    RETURN jsonb_build_object('error', 'not_a_participant');
  END IF;

  -- Require at least one after-photo
  IF NOT EXISTS (
    SELECT 1 FROM public.preuve
     WHERE id_act = p_activity_id
       AND type   = 'apres'
  ) THEN
    RETURN jsonb_build_object('error', 'no_completion_photos');
  END IF;

  UPDATE public.activite
     SET status            = 'pending_validation',
         completed_at      = now(),
         assigned_worker_id = p_user_id   -- track who submitted on behalf of group
   WHERE id_act = p_activity_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- ---------------------------------------------------------------------------
-- 8. update cast_completion_vote
--    For GROUP events: block voting before the event has actually started.
--    For SINGLE activities: no change (backward compatible).
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
  v_mode          text;
  v_event_date    timestamptz;
  v_vote_count    integer;
  v_approve_count integer;
  v_reject_count  integer;
  v_avg_xp        integer;
BEGIN
  SELECT status, assigned_worker_id, id_utilisateur, activity_mode, event_date
    INTO v_status, v_worker, v_creator, v_mode, v_event_date
    FROM activite
   WHERE id_act = p_act_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'activity_not_found');
  END IF;

  IF v_status <> 'pending_validation' THEN
    RETURN jsonb_build_object('error', 'voting_closed', 'status', v_status);
  END IF;

  -- Validate XP proposal is within level-defined bounds (if approving)
  IF p_approve AND p_xp_proposal IS NOT NULL THEN
    DECLARE
      v_xp_min integer;
      v_xp_max integer;
    BEGIN
      SELECT xpmin, xpmax
        INTO v_xp_min, v_xp_max
        FROM activite a
        JOIN niveau_activite n ON a.id_niv_act = n.id_niv_act
       WHERE a.id_act = p_act_id;

      IF v_xp_min IS NOT NULL AND p_xp_proposal < v_xp_min THEN
        RETURN jsonb_build_object(
          'error', 'xp_below_min',
          'min_xp', v_xp_min,
          'proposed_xp', p_xp_proposal
        );
      END IF;

      IF v_xp_max IS NOT NULL AND p_xp_proposal > v_xp_max THEN
        RETURN jsonb_build_object(
          'error', 'xp_above_max',
          'max_xp', v_xp_max,
          'proposed_xp', p_xp_proposal
        );
      END IF;
    END;
  END IF;

  -- For group events: enforce that the event has actually started
  IF COALESCE(v_mode, 'single') = 'group'
     AND v_event_date IS NOT NULL
     AND now() < v_event_date THEN
    RETURN jsonb_build_object('error', 'event_not_started_yet',
                              'event_start', v_event_date::text);
  END IF;

  -- Worker/submitter cannot vote on their own completion
  IF v_worker IS NOT NULL AND v_worker = p_user_id THEN
    RETURN jsonb_build_object('error', 'own_work');
  END IF;

  -- Creator cannot vote either (they initiated the activity)
  IF v_creator = p_user_id THEN
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
       WHERE id_act    = p_act_id
         AND approve   = true
         AND xp_proposal IS NOT NULL;

      -- Award XP to the submitter (for group events) or assigned worker
      IF v_worker IS NOT NULL AND v_avg_xp > 0 THEN
        UPDATE profiles SET xp = xp + v_avg_xp WHERE id = v_worker;
      END IF;

      -- For group activities: also award XP to all confirmed participants
      IF COALESCE(v_mode, 'single') = 'group' AND v_avg_xp > 0 THEN
        UPDATE profiles
           SET xp = xp + v_avg_xp
         WHERE id IN (
           SELECT user_id FROM activity_participants
            WHERE activity_id = p_act_id
              AND status      = 'confirmed'
              AND user_id     <> COALESCE(v_worker, '00000000-0000-0000-0000-000000000000'::uuid)
         );
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
      -- For group events: return to 'open' is inappropriate (already happened)
      -- Instead mark as 'rejected'
      IF COALESCE(v_mode, 'single') = 'group' THEN
        UPDATE activite
           SET status             = 'rejected',
               assigned_worker_id = NULL,
               completed_at       = NULL
         WHERE id_act = p_act_id;

        DELETE FROM vote_completion WHERE id_act = p_act_id;

        RETURN jsonb_build_object(
          'success',    true,
          'decided',    true,
          'new_status', 'rejected',
          'vote_count', v_vote_count
        );
      ELSE
        -- Single activities return to open pool
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
    END IF;
    -- Tie: wait for more votes
  END IF;

  RETURN jsonb_build_object(
    'success',    true,
    'decided',    false,
    'vote_count', v_vote_count
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 9. Update submit_work_completion to also handle group events
--    (participant or organizer can submit, no assigned_worker_id required)
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
  v_status     text;
  v_worker     uuid;
  v_mode       text;
  v_event_date timestamptz;
  v_creator    uuid;
  v_is_member  boolean;
BEGIN
  SELECT status, assigned_worker_id, activity_mode, event_date, id_utilisateur
    INTO v_status, v_worker, v_mode, v_event_date, v_creator
    FROM activite
   WHERE id_act = p_act_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'activity_not_found');
  END IF;

  -- GROUP EVENT path
  IF COALESCE(v_mode, 'single') = 'group' THEN
    IF v_status <> 'in_progress' THEN
      RETURN jsonb_build_object('error', 'event_not_in_progress', 'status', v_status);
    END IF;

    -- Ensure event has actually started
    IF v_event_date IS NOT NULL AND now() < v_event_date THEN
      RETURN jsonb_build_object('error', 'event_not_started_yet');
    END IF;

    -- Must be organizer or confirmed participant
    v_is_member := (v_creator = p_user_id) OR EXISTS (
      SELECT 1 FROM activity_participants
       WHERE activity_id = p_act_id
         AND user_id     = p_user_id
         AND status      = 'confirmed'
    );

    IF NOT v_is_member THEN
      RETURN jsonb_build_object('error', 'not_a_participant');
    END IF;

    -- Require at least one after-photo before marking as pending_validation
    IF NOT EXISTS (
      SELECT 1 FROM preuve
       WHERE id_act = p_act_id
         AND type   = 'apres'
    ) THEN
      RETURN jsonb_build_object('error', 'no_completion_photos');
    END IF;

    UPDATE activite
       SET status            = 'pending_validation',
           completed_at      = now(),
           assigned_worker_id = p_user_id
     WHERE id_act = p_act_id;

    RETURN jsonb_build_object('success', true);
  END IF;

  -- SINGLE ACTIVITY path (original logic, unchanged)
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
-- 10-12. Legacy priority RPC functions (REMOVED)
--
--     The following functions have been removed:
--     - accept_creator_priority(integer)
--     - decline_creator_priority(integer)
--     - expire_creator_priority(integer)
--
--     Reason: Creator is now automatically added to participants on approval.
--             No manual accept/decline step is needed.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 13. Humanize error codes in the Flutter app (documentation only)
--
-- Error codes handled by lifecycle management:
--   'event_locked'         → 'The event is locked 5 minutes before start. You can no longer join or leave.'
--   'event_started'        → 'The event has already started.'
--   'event_not_started'    → 'The event has not started yet.'
--   'event_not_started_yet'→ 'Completion validation is only available after the event starts.'
--   'not_a_participant'    → 'You are not a confirmed participant of this event.'
--   'no_completion_photos' → 'Please upload at least one after-photo before submitting.'
-- ---------------------------------------------------------------------------

-- Verification query (run to confirm functions exist):
-- SELECT routine_name FROM information_schema.routines
-- WHERE routine_schema = 'public'
--   AND routine_name IN (
--     'lock_due_group_events','start_due_group_events','refresh_group_event_status',
--     'join_group_activity','leave_group_activity',
--     'submit_group_event_completion','submit_work_completion',
--     'cast_completion_vote'
--   );
