-- =============================================================================
-- FEATURE 1 — SMART ACTIVITY CREATION (ANTI-DUPLICATION)
-- Run in Supabase SQL Editor
-- =============================================================================

-- Enable trigram extension for title similarity matching
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ---------------------------------------------------------------------------
-- 1. Haversine distance helper (returns metres)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION haversine_distance(
  lat1 double precision,
  lon1 double precision,
  lat2 double precision,
  lon2 double precision
)
RETURNS double precision
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT
    2.0 * 6371000.0 * asin(
      sqrt(
        power(sin(radians(lat2 - lat1) / 2.0), 2) +
        cos(radians(lat1)) * cos(radians(lat2)) *
        power(sin(radians(lon2 - lon1) / 2.0), 2)
      )
    )
$$;

-- ---------------------------------------------------------------------------
-- 2. find_nearby_activities RPC
--    Called from Flutter BEFORE inserting a new activity.
--    Returns potential duplicates ordered by distance.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION find_nearby_activities(
  p_lat            double precision,
  p_lon            double precision,
  p_type_id        integer,
  p_radius_meters  double precision DEFAULT 500,
  p_title_hint     text             DEFAULT NULL
)
RETURNS TABLE (
  id_act               integer,
  titre                text,
  localisation         text,
  status               text,
  distance_meters      double precision,
  has_assigned_worker  boolean,
  assigned_worker_id   uuid,
  similarity_score     real
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT
    a.id_act,
    a.titre,
    a.localisation,
    a.status,
    haversine_distance(p_lat, p_lon, a.latitude, a.longitude)   AS distance_meters,
    a.assigned_worker_id IS NOT NULL                            AS has_assigned_worker,
    a.assigned_worker_id,
    CASE
      WHEN p_title_hint IS NOT NULL AND a.titre IS NOT NULL
        THEN similarity(lower(trim(a.titre)), lower(trim(p_title_hint)))
      ELSE 0.0
    END::real                                                   AS similarity_score
  FROM activite a
  WHERE
    a.latitude  IS NOT NULL
    AND a.longitude IS NOT NULL
    AND a.id_type_act = p_type_id
    AND a.status NOT IN ('rejected', 'cancelled', 'completed', 'approved')
    AND haversine_distance(p_lat, p_lon, a.latitude, a.longitude) <= p_radius_meters
  ORDER BY distance_meters ASC
  LIMIT 10;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION find_nearby_activities TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Performance indexes
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_activite_lat_lon
  ON activite (latitude, longitude)
  WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_activite_type_status
  ON activite (id_type_act, status);

CREATE INDEX IF NOT EXISTS idx_activite_titre_trgm
  ON activite USING GIN (titre gin_trgm_ops)
  WHERE titre IS NOT NULL;
