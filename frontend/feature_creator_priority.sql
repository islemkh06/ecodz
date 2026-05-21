-- =============================================================================
-- Feature: Organizer Auto-Participation (Group Events only)
-- Run AFTER voting_migration.sql and feature_group_activities.sql
-- =============================================================================
-- 
-- When a GROUP event is approved by community vote:
-- - Creator is AUTOMATICALLY added as a participant
-- - Event status becomes 'open'
-- - participants_count starts at 1
-- - No priority window, no accept/decline step
-- =============================================================================

-- =============================================================================
-- 2. Update cast_approval_vote
--
--    When a GROUP activity gets 2 approve votes:
--    - Status transitions to 'open' (NOT 'priority_pending')
--    - Creator is AUTOMATICALLY added as a confirmed participant
--    - participants_count = 1 (the creator)
--    
--    Single activities keep the original 'approved' transition.
-- =============================================================================
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
        -- Group events: auto-add creator as participant and open event
        INSERT INTO activity_participants (activity_id, user_id, status, joined_at)
        VALUES (p_act_id, v_creator_id, 'confirmed', now())
        ON CONFLICT (activity_id, user_id)
          DO UPDATE SET status = 'confirmed', joined_at = now();
        
        UPDATE activite
           SET status                     = 'open',
               current_participants_count = (
                 SELECT COUNT(*) FROM activity_participants
                  WHERE activity_id = p_act_id AND status = 'confirmed'
               )
         WHERE id_act = p_act_id;

        RETURN jsonb_build_object(
          'success',      true,
          'decided',      true,
          'new_status',   'open',
          'auto_joined',  true,
          'message',      'Event approved! Creator automatically added as participant.',
          'vote_count',   v_vote_count
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

-- =============================================================================
-- 3. Update join_group_activity
--
--    Simplified: no priority phase logic.
--    All users (including organizer) can join once status is 'open'.
--    Organizer is automatically added on approval, but they can still manually
--    join again if they left the event (though this is rare).
-- =============================================================================
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

  -- Event must be open or approved
  IF v_act.status NOT IN ('open', 'approved') THEN
    RETURN json_build_object('success', false, 'error', 'activity_not_open');
  END IF;

  -- Check max capacity
  IF v_act.current_participants_count >= COALESCE(v_act.max_participants, 9999) THEN
    RETURN json_build_object('success', false, 'error', 'activity_full');
  END IF;

  -- Check if already joined
  IF EXISTS (
    SELECT 1 FROM public.activity_participants
     WHERE activity_id = p_activity_id
       AND user_id     = p_user_id
       AND status      = 'confirmed'
  ) THEN
    RETURN json_build_object('success', false, 'error', 'already_joined');
  END IF;

  -- Add participant
  INSERT INTO public.activity_participants (activity_id, user_id, status)
  VALUES (p_activity_id, p_user_id, 'confirmed')
  ON CONFLICT (activity_id, user_id)
    DO UPDATE SET status = 'confirmed', joined_at = now();

  -- Update participant count
  UPDATE public.activite
     SET current_participants_count = (
           SELECT COUNT(*) FROM public.activity_participants
            WHERE activity_id = p_activity_id AND status = 'confirmed'
         )
   WHERE id_act = p_activity_id;

  RETURN json_build_object('success', true);
END;
$$;

-- =============================================================================
-- 4. Legacy priority RPCs (REMOVED)
--
--    The following functions have been removed:
--    - accept_creator_priority(integer)
--    - decline_creator_priority(integer)
--    - expire_creator_priority(integer)
--
--    Reason: Creator is now automatically added to participants on approval.
--            No manual accept/decline step is needed.
-- =============================================================================
