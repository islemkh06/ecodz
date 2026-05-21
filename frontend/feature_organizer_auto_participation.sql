-- =============================================================================
-- FEATURE: Organizer Auto-Participation for Group Events
-- Replaces the priority participation system with automatic organizer joining
-- Run in Supabase SQL Editor
-- =============================================================================

-- ============================================================================
-- 1. UPDATE cast_approval_vote
--
-- When a GROUP event gets 2 approve votes:
--   - Automatically add organizer to activity_participants
--   - Set participants_count = 1
--   - Status = 'open' (NOT 'priority_pending')
--   - No priority window needed
--
-- Single activities keep their existing behavior (status = 'approved')
-- ============================================================================

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
        -- GROUP EVENT: Auto-add organizer and open immediately
        -- Step 1: Add organizer to participants
        INSERT INTO activity_participants (activity_id, user_id, status)
        VALUES (p_act_id, v_creator_id, 'confirmed')
        ON CONFLICT (activity_id, user_id) DO UPDATE 
          SET status = 'confirmed', joined_at = now();

        -- Step 2: Update activity status and participant count
        UPDATE activite
           SET status = 'open',
               current_participants_count = 1
         WHERE id_act = p_act_id;

        RETURN jsonb_build_object(
          'success',                 true,
          'decided',                 true,
          'new_status',              'open',
          'organizer_auto_joined',   true,
          'vote_count',              v_vote_count
        );
      ELSE
        -- SINGLE ACTIVITY: Approve (no participant table used for single)
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

-- ============================================================================
-- 2. UPDATE join_group_activity
--
-- Remove priority_pending logic entirely
-- Simply allow joins when status = 'open'
-- Check max participants limit
-- ============================================================================

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

  -- Simple check: event must be open
  IF v_act.status <> 'open' THEN
    RETURN json_build_object('success', false, 'error', 'activity_not_open', 'status', v_act.status);
  END IF;

  -- Check max participants
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

  -- Increment participant count
  UPDATE public.activite
     SET current_participants_count = (
           SELECT COUNT(*) FROM public.activity_participants
            WHERE activity_id = p_activity_id AND status = 'confirmed'
         )
   WHERE id_act = p_activity_id;

  RETURN json_build_object('success', true);
END;
$$;

-- ============================================================================
-- 3. DEPRECATE priority participation functions
--
-- These are no longer needed but kept for backward compatibility
-- Mark as deprecated in function comments
-- ============================================================================

-- DEPRECATED: No longer used with auto-organizer participation
CREATE OR REPLACE FUNCTION public.accept_creator_priority(
  p_activity_id integer
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- This function is DEPRECATED - priority participation system removed
  RETURN json_build_object(
    'success', false,
    'error', 'deprecated',
    'message', 'Priority participation system has been removed. Organizers are auto-added on approval.'
  );
END;
$$;

-- DEPRECATED: No longer used with auto-organizer participation
CREATE OR REPLACE FUNCTION public.decline_creator_priority(
  p_activity_id integer
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- This function is DEPRECATED - priority participation system removed
  RETURN json_build_object(
    'success', false,
    'error', 'deprecated',
    'message', 'Priority participation system has been removed. Organizers are auto-added on approval.'
  );
END;
$$;

-- DEPRECATED: No longer used with auto-organizer participation
CREATE OR REPLACE FUNCTION public.expire_creator_priority(
  p_activity_id integer
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- This function is DEPRECATED - priority participation system removed
  RETURN json_build_object(
    'success', false,
    'error', 'deprecated',
    'message', 'Priority participation system has been removed. Organizers are auto-added on approval.'
  );
END;
$$;

-- ============================================================================
-- 4. CLEAN UP priority columns (OPTIONAL - keep for history if needed)
--
-- Uncomment below if you want to remove the priority columns entirely
-- Otherwise, they remain as historical data
-- ============================================================================

-- ALTER TABLE public.activite
--   DROP COLUMN IF EXISTS priority_deadline,
--   DROP COLUMN IF EXISTS creator_priority_status;
--
-- DROP INDEX IF EXISTS idx_activite_priority_deadline;

-- ============================================================================
-- 5. MIGRATION HELPER: Auto-add organizers to existing 'open' group events
--
-- If there are any group events already in 'open' status without the organizer
-- in participants, add them now (one-time migration)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.migrate_organizers_to_participants()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_count int := 0;
  v_rec record;
BEGIN
  -- Find group events that are open and organizer not yet a participant
  FOR v_rec IN
    SELECT a.id_act, a.id_utilisateur
      FROM activite a
     WHERE a.activity_mode = 'group'
       AND a.status = 'open'
       AND NOT EXISTS (
             SELECT 1
               FROM activity_participants
              WHERE activity_id = a.id_act
                AND user_id = a.id_utilisateur
                AND status = 'confirmed'
           )
  LOOP
    INSERT INTO activity_participants (activity_id, user_id, status)
    VALUES (v_rec.id_act, v_rec.id_utilisateur, 'confirmed');
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- Run migration (call once after deploying this SQL)
-- SELECT migrate_organizers_to_participants();
