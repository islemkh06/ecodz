-- =============================================================
-- ECODZ – Database seed & migration script
-- Run this once against your Supabase project SQL editor.
-- =============================================================

-- ── 1. Add icone column to type_activite ─────────────────────
ALTER TABLE public.type_activite
  ADD COLUMN IF NOT EXISTS icone text;

-- ── 2. Add lat/lng columns to activite ───────────────────────
--    Used by the Flutter location picker to store precise coords.
ALTER TABLE public.activite
  ADD COLUMN IF NOT EXISTS latitude  double precision;
ALTER TABLE public.activite
  ADD COLUMN IF NOT EXISTS longitude double precision;

-- ── 3. Seed type_activite ─────────────────────────────────────
--    Only inserts if the table is empty (safe to re-run on a fresh DB).
--    If you already have rows, run the INSERT block manually.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.type_activite LIMIT 1) THEN
    INSERT INTO public.type_activite (nom, icone) VALUES
      ('Afforestation',  'park'),
      ('Cleaning',       'cleaning_services'),
      ('Recycling',      'recycling'),
      ('Water',          'water_drop'),
      ('Energy',         'energy_savings_leaf'),
      ('Awareness',      'eco'),
      ('Nature',         'forest'),
      ('Climate',        'public'),
      ('Solar',          'solar_power'),
      ('Compost',        'compost'),
      ('Green Parks',    'grass'),
      ('Eco Tech',       'bolt'),
      ('Mobility',       'electric_bike'),
      ('Farming',        'agriculture'),
      ('Wildlife',       'pets'),
      ('Volunteering',   'volunteer_activism'),
      ('Pollution',      'factory'),
      ('Heat Action',    'wb_sunny'),
      ('Sport',          'sports_soccer'),
      ('Education',      'school'),
      ('Health',         'health_and_safety');
  END IF;
END $$;

-- ── 4. (Optional) Update icone for existing rows ─────────────
--    Run this block if type_activite already has rows but is missing icone values.
/*
UPDATE public.type_activite SET icone = 'park'               WHERE nom = 'Afforestation'  AND icone IS NULL;
UPDATE public.type_activite SET icone = 'cleaning_services'  WHERE nom = 'Cleaning'        AND icone IS NULL;
UPDATE public.type_activite SET icone = 'recycling'          WHERE nom = 'Recycling'       AND icone IS NULL;
UPDATE public.type_activite SET icone = 'water_drop'         WHERE nom = 'Water'           AND icone IS NULL;
UPDATE public.type_activite SET icone = 'energy_savings_leaf' WHERE nom = 'Energy'         AND icone IS NULL;
UPDATE public.type_activite SET icone = 'eco'                WHERE nom = 'Awareness'       AND icone IS NULL;
UPDATE public.type_activite SET icone = 'forest'             WHERE nom = 'Nature'          AND icone IS NULL;
UPDATE public.type_activite SET icone = 'public'             WHERE nom = 'Climate'         AND icone IS NULL;
UPDATE public.type_activite SET icone = 'solar_power'        WHERE nom = 'Solar'           AND icone IS NULL;
UPDATE public.type_activite SET icone = 'compost'            WHERE nom = 'Compost'         AND icone IS NULL;
UPDATE public.type_activite SET icone = 'grass'              WHERE nom = 'Green Parks'     AND icone IS NULL;
UPDATE public.type_activite SET icone = 'bolt'               WHERE nom = 'Eco Tech'        AND icone IS NULL;
UPDATE public.type_activite SET icone = 'electric_bike'      WHERE nom = 'Mobility'        AND icone IS NULL;
UPDATE public.type_activite SET icone = 'agriculture'        WHERE nom = 'Farming'         AND icone IS NULL;
UPDATE public.type_activite SET icone = 'pets'               WHERE nom = 'Wildlife'        AND icone IS NULL;
UPDATE public.type_activite SET icone = 'volunteer_activism' WHERE nom = 'Volunteering'    AND icone IS NULL;
UPDATE public.type_activite SET icone = 'factory'            WHERE nom = 'Pollution'       AND icone IS NULL;
UPDATE public.type_activite SET icone = 'wb_sunny'           WHERE nom = 'Heat Action'     AND icone IS NULL;
UPDATE public.type_activite SET icone = 'sports_soccer'      WHERE nom = 'Sport'           AND icone IS NULL;
UPDATE public.type_activite SET icone = 'school'             WHERE nom = 'Education'       AND icone IS NULL;
UPDATE public.type_activite SET icone = 'health_and_safety'  WHERE nom = 'Health'          AND icone IS NULL;
*/
