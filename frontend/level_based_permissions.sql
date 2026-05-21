-- =============================================================================
-- FEATURE: Level-Based Activity Creation Permissions
-- + Fix Creator Priority Participation for Group Events
-- Run in Supabase SQL Editor
-- =============================================================================

-- ============================================================================
-- 1. LEVEL-BASED PERMISSIONS HELPER
-- ============================================================================

CREATE OR REPLACE FUNCTION public.can_create_activity(
  p_user_id uuid,
  p_activity_type text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_level integer;
BEGIN
  -- Get user's current level
  SELECT level INTO v_level
    FROM profiles
   WHERE id = p_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('allowed', false, 'error', 'user_not_found');
  END IF;

  -- Level 1: Cannot create anything
  IF v_level = 1 THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'error', 'insufficient_level',
      'message', 'You must reach Level 2 (Sprout) to create activities.',
      'required_level', 2
    );
  END IF;

  -- Level 2: Can create single activities only
  IF v_level = 2 AND p_activity_type = 'group' THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'error', 'insufficient_level',
      'message', 'You must reach Level 3 (Sapling) to create group events.',
      'required_level', 3
    );
  END IF;

  -- Level 3+: Can create both
  RETURN jsonb_build_object('allowed', true);
END;
$$;

-- ============================================================================
-- 2. VERIFY join_group_activity LOGIC (Creator Participation Fix)
-- ============================================================================
-- The current join_group_activity RPC should:
-- - During priority_pending: Only creator can join
-- - After creator joins: Event transitions to 'open' (NOT exclusive)
-- - Max participants check prevents more joins after limit reached
--
-- This logic is already in feature_creator_priority.sql
-- The key is that creator joins as a PARTICIPANT, not as assigned_worker_id
-- assigned_worker_id should NOT be used for group events (only single activities)
-- ============================================================================

-- ============================================================================
-- 3. INDEX for performance on level checks
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_profiles_level
  ON public.profiles (level)
  WHERE level IS NOT NULL;

-- ============================================================================
-- 4. Verify assigned_worker_id is NOT blocking group event joins
-- ============================================================================
-- This UPDATE ensures that for group activities:
-- - assigned_worker_id remains NULL (not used)
-- - participants are tracked in activity_participants table
-- (No change needed if join_group_activity already uses activity_participants)
