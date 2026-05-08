-- =============================================================================
-- Feature: Creator Priority Participation (Group Events only)
-- Run AFTER voting_migration.sql and feature_group_activities.sql
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. New columns on activite
-- -----------------------------------------------------------------------------
ALTER TABLE public.activite
  ADD COLUMN IF NOT EXISTS priority_deadline        timestamptz,
  ADD COLUMN IF NOT EXISTS creator_priority_status  text
    CHECK (creator_priority_status IN ('pending', 'accepted', 'declined', 'expired'));

-- Index for fast look-ups on priority expiration
CREATE INDEX IF NOT EXISTS idx_activite_priority_deadline
  ON public.activite (priority_deadline)
  WHERE status = 'priority_pending';

-- -----------------------------------------------------------------------------
-- 2. Update cast_approval_vote
--
--    When a GROUP activity gets 2 approve votes → status = 'priority_pending'
--    with priority_deadline = NOW() + 1 minute.
--    Single activities keep the original 'approved' transition.
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
  v_status         text;
  v_creator_id     uuid;
  v_activity_mode  text;
  v_vote_count     integer;
  v_approve_count  integer;
  v_reject_count   integer;
BEGIN
  SELECT status, id_utilisateur, activity_mode
    INTO v_status, v_creator_id, v_activity_mode
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
      IF COALESCE(v_activity_mode, 'single') = 'group' THEN
        -- Group events enter creator priority phase for 1 minute
        UPDATE activite
           SET status                  = 'priority_pending',
               priority_deadline       = NOW() + INTERVAL '1 minute',
               creator_priority_status = 'pending'
         WHERE id_act = p_act_id;

        RETURN jsonb_build_object(
          'success',          true,
          'decided',          true,
          'new_status',       'priority_pending',
          'priority_deadline', (NOW() + INTERVAL '1 minute')::text,
          'vote_count',       v_vote_count
        );
      ELSE
        -- Single activities approve immediately
        UPDATE activite SET status = 'approved' WHERE id_act = p_act_id;

        RETURN jsonb_build_object(
          'success',    true,
          'decided',    true,
          'new_status', 'approved',
          'vote_count', v_vote_count
        );
      END IF;
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
-- 3. Update join_group_activity
--
--    During priority_pending, only the creator is permitted to join.
--    After the creator joins, the event opens to everyone.
--    If the priority deadline has passed, the function auto-expires and lets
--    normal joins proceed.
-- -----------------------------------------------------------------------------
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

  -- Handle priority_pending phase
  IF v_act.status = 'priority_pending' THEN
    IF NOW() > v_act.priority_deadline THEN
      -- Deadline passed → auto-expire, allow all joins from now on
      UPDATE activite
         SET status                  = 'open',
             creator_priority_status = 'expired'
       WHERE id_act = p_activity_id;
      v_act.status := 'open';
    ELSIF v_act.id_utilisateur <> p_user_id THEN
      RETURN json_build_object('success', false, 'error', 'creator_priority_active');
    END IF;
  END IF;

  IF v_act.status NOT IN ('open', 'approved', 'priority_pending') THEN
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
         ),
         -- Creator accepted during priority phase → open to all
         status = CASE
                    WHEN status = 'priority_pending' THEN 'open'
                    ELSE status
                  END,
         creator_priority_status = CASE
                                     WHEN status = 'priority_pending' THEN 'accepted'
                                     ELSE creator_priority_status
                                   END
   WHERE id_act = p_activity_id;

  RETURN json_build_object('success', true);
END;
$$;

-- -----------------------------------------------------------------------------
-- 4. RPC: accept_creator_priority
--    Creator explicitly accepts participation during the priority window.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.accept_creator_priority(
  p_activity_id integer
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_act public.activite%ROWTYPE;
BEGIN
  SELECT * INTO v_act
    FROM activite
   WHERE id_act = p_activity_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'activity_not_found');
  END IF;

  IF v_act.id_utilisateur <> v_uid THEN
    RETURN json_build_object('success', false, 'error', 'not_creator');
  END IF;

  IF v_act.status <> 'priority_pending' THEN
    RETURN json_build_object('success', false, 'error', 'not_in_priority_phase');
  END IF;

  IF NOW() > v_act.priority_deadline THEN
    UPDATE activite
       SET status                  = 'open',
           creator_priority_status = 'expired'
     WHERE id_act = p_activity_id;
    RETURN json_build_object('success', false, 'error', 'priority_expired');
  END IF;

  -- Enroll creator as confirmed participant
  INSERT INTO activity_participants (activity_id, user_id, status)
  VALUES (p_activity_id, v_uid, 'confirmed')
  ON CONFLICT (activity_id, user_id)
    DO UPDATE SET status = 'confirmed', joined_at = now();

  UPDATE activite
     SET status                     = 'open',
         creator_priority_status    = 'accepted',
         current_participants_count = (
           SELECT COUNT(*) FROM activity_participants
            WHERE activity_id = p_activity_id AND status = 'confirmed'
         )
   WHERE id_act = p_activity_id;

  RETURN json_build_object('success', true, 'new_status', 'open');
END;
$$;

-- -----------------------------------------------------------------------------
-- 5. RPC: decline_creator_priority
--    Creator explicitly declines — event opens immediately to all.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.decline_creator_priority(
  p_activity_id integer
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_act public.activite%ROWTYPE;
BEGIN
  SELECT * INTO v_act
    FROM activite
   WHERE id_act = p_activity_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'activity_not_found');
  END IF;

  IF v_act.id_utilisateur <> v_uid THEN
    RETURN json_build_object('success', false, 'error', 'not_creator');
  END IF;

  IF v_act.status <> 'priority_pending' THEN
    RETURN json_build_object('success', false, 'error', 'not_in_priority_phase');
  END IF;

  UPDATE activite
     SET status                  = 'open',
         creator_priority_status = 'declined'
   WHERE id_act = p_activity_id;

  RETURN json_build_object('success', true, 'new_status', 'open');
END;
$$;

-- -----------------------------------------------------------------------------
-- 6. RPC: expire_creator_priority
--    Safe to call anytime. Only updates rows where deadline has passed.
--    Call this from Flutter when the client-side countdown reaches zero.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expire_creator_priority(
  p_activity_id integer
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE activite
     SET status                  = 'open',
         creator_priority_status = 'expired'
   WHERE id_act     = p_activity_id
     AND status     = 'priority_pending'
     AND NOW()      > priority_deadline;

  RETURN json_build_object('success', true);
END;
$$;

-- Grant execute permissions (adjust role name if your project uses different roles)
GRANT EXECUTE ON FUNCTION public.accept_creator_priority(integer)    TO authenticated;
GRANT EXECUTE ON FUNCTION public.decline_creator_priority(integer)   TO authenticated;
GRANT EXECUTE ON FUNCTION public.expire_creator_priority(integer)    TO authenticated;
