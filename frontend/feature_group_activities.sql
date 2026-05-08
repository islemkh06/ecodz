-- =============================================================================
-- FEATURE: GROUP ACTIVITIES
-- Run in Supabase SQL Editor
-- Adds activity_mode, max_participants, event_date fields to activite table
-- and creates a new activity_participants table with RLS + helper RPCs.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Extend activite table with group-activity fields
-- ---------------------------------------------------------------------------
ALTER TABLE public.activite
  ADD COLUMN IF NOT EXISTS activity_mode          text        NOT NULL DEFAULT 'single'
    CHECK (activity_mode IN ('single', 'group')),
  ADD COLUMN IF NOT EXISTS max_participants        integer,
  ADD COLUMN IF NOT EXISTS event_date              timestamptz,
  ADD COLUMN IF NOT EXISTS current_participants_count integer  NOT NULL DEFAULT 0;

-- ---------------------------------------------------------------------------
-- 2. activity_participants table
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.activity_participants (
  id          bigserial    PRIMARY KEY,
  activity_id integer      NOT NULL REFERENCES public.activite(id_act) ON DELETE CASCADE,
  user_id     uuid         NOT NULL REFERENCES public.profiles(id)     ON DELETE CASCADE,
  joined_at   timestamptz  NOT NULL DEFAULT now(),
  status      text         NOT NULL DEFAULT 'confirmed'
              CHECK (status IN ('confirmed', 'cancelled')),
  CONSTRAINT activity_participants_unique UNIQUE (activity_id, user_id)
);

-- ---------------------------------------------------------------------------
-- 3. RLS on activity_participants
-- ---------------------------------------------------------------------------
ALTER TABLE public.activity_participants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "participants_select_all"
  ON public.activity_participants FOR SELECT
  USING (true);

CREATE POLICY "participants_insert_own"
  ON public.activity_participants FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "participants_update_own"
  ON public.activity_participants FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "participants_delete_own"
  ON public.activity_participants FOR DELETE
  USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- 4. join_group_activity RPC
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
  -- Lock row to prevent race conditions
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

  IF v_act.status NOT IN ('open', 'approved', 'waiting') THEN
    RETURN json_build_object('success', false, 'error', 'activity_not_open');
  END IF;

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

  RETURN json_build_object('success', true);
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. leave_group_activity RPC
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.leave_group_activity(
  p_activity_id integer,
  p_user_id     uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
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
-- 6. Helpful index
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_activity_participants_activity_id
  ON public.activity_participants (activity_id);

CREATE INDEX IF NOT EXISTS idx_activite_activity_mode
  ON public.activite (activity_mode);
