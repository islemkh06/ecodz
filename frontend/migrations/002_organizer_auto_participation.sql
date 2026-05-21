-- =============================================================================
-- Migration: Group Event Organizer Auto-Participation
-- Version: 002
-- Description: Remove priority participation system and auto-add organizers
-- Created: 2026-05-21
-- Status: Ready for Supabase deployment
-- =============================================================================

-- Run this migration with:
-- 1. Copy entire SQL file
-- 2. Open Supabase dashboard → SQL Editor → New Query
-- 3. Paste and run
-- 
-- Rollback: Not needed - this is a one-way migration (data compatible)
-- =============================================================================

BEGIN;

-- =============================================================================
-- STEP 1: Drop legacy priority RPC functions (if they exist)
-- =============================================================================

DROP FUNCTION IF EXISTS public.accept_creator_priority(integer) CASCADE;
DROP FUNCTION IF EXISTS public.decline_creator_priority(integer) CASCADE;
DROP FUNCTION IF EXISTS public.expire_creator_priority(integer) CASCADE;

-- =============================================================================
-- STEP 2: Update cast_approval_vote() - Core logic for auto-participation
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
        -- GROUP EVENT: Auto-add creator as participant and open event
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
        -- SINGLE ACTIVITY: Keep original behavior (approve immediately)
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

GRANT EXECUTE ON FUNCTION public.cast_approval_vote(integer, uuid, integer) TO authenticated;

-- =============================================================================
-- STEP 3: Update join_group_activity() - Remove priority phase logic
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

  -- Event must be open or approved (no priority_pending)
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

GRANT EXECUTE ON FUNCTION public.join_group_activity(integer, uuid) TO authenticated;

-- =============================================================================
-- STEP 4: Update leave_group_activity() to match join_group_activity changes
-- =============================================================================

CREATE OR REPLACE FUNCTION public.leave_group_activity(
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

  -- Block leaves when locked or started
  IF v_act.status = 'locked' THEN
    RETURN json_build_object('success', false, 'error', 'event_locked');
  END IF;

  IF v_act.status = 'in_progress' THEN
    RETURN json_build_object('success', false, 'error', 'event_started');
  END IF;

  -- Check if participant exists
  IF NOT EXISTS (
    SELECT 1 FROM public.activity_participants
     WHERE activity_id = p_activity_id
       AND user_id     = p_user_id
       AND status      = 'confirmed'
  ) THEN
    RETURN json_build_object('success', false, 'error', 'not_a_participant');
  END IF;

  -- Remove participant
  DELETE FROM public.activity_participants
   WHERE activity_id = p_activity_id
     AND user_id     = p_user_id;

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

GRANT EXECUTE ON FUNCTION public.leave_group_activity(integer, uuid) TO authenticated;

-- =============================================================================
-- STEP 5: Update refresh_group_event_status() - Remove priority checks
-- =============================================================================

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

GRANT EXECUTE ON FUNCTION public.refresh_group_event_status(integer) TO authenticated;

-- =============================================================================
-- STEP 6: Cleanup - Remove priority columns if they still exist (optional)
--         Only uncomment if you want to remove historical data
-- =============================================================================

-- ALTER TABLE public.activite
--   DROP COLUMN IF EXISTS priority_deadline,
--   DROP COLUMN IF EXISTS creator_priority_status;

-- DROP INDEX IF EXISTS idx_activite_priority_deadline;

-- =============================================================================
-- STEP 7: Data integrity check
-- =============================================================================

-- Verify no orphaned group events are stuck in priority_pending status
-- This should return 0 rows. If it doesn't, those events are now 'open'
-- but organizer may not be in participants yet.

-- SELECT id_act, titre, status, id_utilisateur
-- FROM activite
-- WHERE activity_mode = 'group' 
--   AND status = 'priority_pending';

-- To fix any orphaned priority_pending events, run:
-- UPDATE activite
--   SET status = 'open'
--  WHERE activity_mode = 'group'
--    AND status = 'priority_pending';

-- =============================================================================
-- STEP 8: Verification
-- =============================================================================

-- Run these queries to verify the migration:

-- 1. Check function exists:
-- SELECT routine_name FROM information_schema.routines
-- WHERE routine_schema = 'public'
--   AND routine_name IN ('cast_approval_vote', 'join_group_activity', 'leave_group_activity', 'refresh_group_event_status');

-- 2. Check for any remaining priority_pending events:
-- SELECT COUNT(*) as priority_pending_count
-- FROM activite
-- WHERE status = 'priority_pending';

-- 3. Check recent group events with their organizers as participants:
-- SELECT a.id_act, a.titre, a.status, COUNT(ap.user_id) as participant_count
-- FROM activite a
-- LEFT JOIN activity_participants ap ON a.id_act = ap.activity_id AND ap.status = 'confirmed'
-- WHERE a.activity_mode = 'group'
--   AND a.status IN ('open', 'approved', 'locked', 'in_progress')
-- GROUP BY a.id_act, a.titre, a.status
-- LIMIT 10;

COMMIT;

-- =============================================================================
-- Migration Summary
-- =============================================================================
-- 
-- What changed:
-- ✅ Removed accept_creator_priority(), decline_creator_priority(), expire_creator_priority()
-- ✅ Updated cast_approval_vote() to auto-add creators to group event participants
-- ✅ Simplified join_group_activity() - removed priority phase logic
-- ✅ Updated leave_group_activity() for consistency
-- ✅ Updated refresh_group_event_status() - removed priority checks
--
-- Expected behavior after migration:
-- • Group events approved by vote → creator automatically added as participant
-- • Event status goes directly to 'open' (no priority_pending phase)
-- • Participants count starts at 1 (the organizer)
-- • Organizer behaves like normal participant (can leave before lock, subject to limits)
-- • Single activity events are UNCHANGED
--
-- Rollback: Not necessary - this is data-compatible and one-way
-- All old priority_pending events can be manually reset to 'open' if needed
--
-- =============================================================================
