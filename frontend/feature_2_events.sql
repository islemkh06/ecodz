-- =============================================================================
-- FEATURE 2 — EVENTS SYSTEM
-- Run in Supabase SQL Editor AFTER feature_1 (haversine_distance must exist)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. event table
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.event (
  id                  bigserial    PRIMARY KEY,
  id_act              integer      REFERENCES public.activite(id_act) ON DELETE CASCADE,
  title               text         NOT NULL,
  description         text,
  organizer_id        uuid         NOT NULL REFERENCES public.profiles(id),
  event_date          timestamptz  NOT NULL,
  -- Auto-computed: registrations close 12h before event
  expiration_date     timestamptz  GENERATED ALWAYS AS (event_date - interval '12 hours') STORED,
  max_participants    integer      NOT NULL DEFAULT 10 CHECK (max_participants > 0),
  current_participants integer     NOT NULL DEFAULT 0,
  status              text         NOT NULL DEFAULT 'open'
                                   CHECK (status IN ('open', 'closed', 'expired', 'cancelled')),
  created_at          timestamptz  NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 2. event_registration table
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.event_registration (
  id            bigserial    PRIMARY KEY,
  event_id      bigint       NOT NULL REFERENCES public.event(id) ON DELETE CASCADE,
  user_id       uuid         NOT NULL REFERENCES public.profiles(id),
  registered_at timestamptz  NOT NULL DEFAULT now(),
  status        text         NOT NULL DEFAULT 'confirmed'
                             CHECK (status IN ('confirmed', 'cancelled')),
  CONSTRAINT event_registration_unique UNIQUE (event_id, user_id)
);

-- ---------------------------------------------------------------------------
-- 3. Trigger: enforce capacity + expiration on registration INSERT
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_check_event_registration()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_event public.event%ROWTYPE;
BEGIN
  -- Lock the event row to prevent race conditions
  SELECT * INTO v_event FROM public.event WHERE id = NEW.event_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Event % does not exist', NEW.event_id;
  END IF;

  -- Check event status
  IF v_event.status <> 'open' THEN
    RAISE EXCEPTION 'Event is not open for registration (current status: %)', v_event.status;
  END IF;

  -- Check expiration
  IF now() >= v_event.expiration_date THEN
    UPDATE public.event SET status = 'closed' WHERE id = NEW.event_id;
    RAISE EXCEPTION 'Registration deadline has passed (closes 12h before event)';
  END IF;

  -- Check capacity
  IF v_event.current_participants >= v_event.max_participants THEN
    RAISE EXCEPTION 'Event is full (% / % participants)',
      v_event.current_participants, v_event.max_participants;
  END IF;

  -- Increment participant count; close if now at capacity
  UPDATE public.event
  SET
    current_participants = current_participants + 1,
    status = CASE
               WHEN current_participants + 1 >= max_participants THEN 'closed'
               ELSE status
             END
  WHERE id = NEW.event_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_event_registration_check ON public.event_registration;
CREATE TRIGGER trg_event_registration_check
  BEFORE INSERT ON public.event_registration
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_check_event_registration();

-- ---------------------------------------------------------------------------
-- 4. Trigger: decrement on cancellation UPDATE
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_handle_event_cancellation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Only act when going confirmed → cancelled
  IF OLD.status = 'confirmed' AND NEW.status = 'cancelled' THEN
    UPDATE public.event
    SET
      current_participants = GREATEST(0, current_participants - 1),
      -- Re-open if it was closed due to capacity
      status = CASE
                 WHEN status = 'closed'
                      AND current_participants - 1 < max_participants
                 THEN 'open'
                 ELSE status
               END
    WHERE id = OLD.event_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_event_cancellation ON public.event_registration;
CREATE TRIGGER trg_event_cancellation
  AFTER UPDATE ON public.event_registration
  FOR EACH ROW
  WHEN (OLD.status = 'confirmed' AND NEW.status = 'cancelled')
  EXECUTE FUNCTION public.trg_handle_event_cancellation();

-- ---------------------------------------------------------------------------
-- 5. RPC: join_event — safe insert with structured error return
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.join_event(
  p_event_id bigint,
  p_user_id  uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reg_id bigint;
BEGIN
  INSERT INTO public.event_registration (event_id, user_id)
  VALUES (p_event_id, p_user_id)
  RETURNING id INTO v_reg_id;

  RETURN json_build_object(
    'success',         true,
    'registration_id', v_reg_id
  );
EXCEPTION
  WHEN unique_violation THEN
    RETURN json_build_object('success', false, 'error', 'already_registered');
  WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. RPC: leave_event
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.leave_event(
  p_event_id bigint,
  p_user_id  uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.event_registration
  SET status = 'cancelled'
  WHERE event_id = p_event_id
    AND user_id   = p_user_id
    AND status    = 'confirmed';

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'registration_not_found');
  END IF;

  RETURN json_build_object('success', true);
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. RPC: expire_past_events — call via pg_cron or a scheduled Supabase
--    Edge Function (CRON trigger every 15 minutes).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expire_past_events()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_count integer;
BEGIN
  WITH updated AS (
    UPDATE public.event
    SET status = 'expired'
    WHERE status = 'open'
      AND now() >= expiration_date
    RETURNING id
  )
  SELECT count(*) INTO v_count FROM updated;

  RETURN v_count;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.join_event  TO authenticated;
GRANT EXECUTE ON FUNCTION public.leave_event TO authenticated;
GRANT EXECUTE ON FUNCTION public.expire_past_events TO service_role;

-- ---------------------------------------------------------------------------
-- 8. Row-Level Security
-- ---------------------------------------------------------------------------
ALTER TABLE public.event              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_registration ENABLE ROW LEVEL SECURITY;

-- Events: anyone authenticated can read; only organizer can modify
CREATE POLICY "events_read"   ON public.event FOR SELECT TO authenticated USING (true);
CREATE POLICY "events_insert" ON public.event FOR INSERT TO authenticated
  WITH CHECK (organizer_id = auth.uid());
CREATE POLICY "events_update" ON public.event FOR UPDATE TO authenticated
  USING (organizer_id = auth.uid());
CREATE POLICY "events_delete" ON public.event FOR DELETE TO authenticated
  USING (organizer_id = auth.uid());

-- Registrations: user can read own; insert own; cancel own
CREATE POLICY "reg_read"   ON public.event_registration FOR SELECT TO authenticated
  USING (user_id = auth.uid());
CREATE POLICY "reg_insert" ON public.event_registration FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());
CREATE POLICY "reg_update" ON public.event_registration FOR UPDATE TO authenticated
  USING (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 9. Indexes
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_event_id_act    ON public.event (id_act);
CREATE INDEX IF NOT EXISTS idx_event_status    ON public.event (status);
CREATE INDEX IF NOT EXISTS idx_event_date      ON public.event (event_date);
CREATE INDEX IF NOT EXISTS idx_reg_event_user  ON public.event_registration (event_id, user_id);
CREATE INDEX IF NOT EXISTS idx_reg_user        ON public.event_registration (user_id);
