-- Migration: Add event_image_url column to activite table
-- Run this in the Supabase SQL Editor

ALTER TABLE public.activite
  ADD COLUMN IF NOT EXISTS event_image_url text;

COMMENT ON COLUMN public.activite.event_image_url IS
  'Direct public URL of the group event cover image (uploaded to activity_image storage bucket).';
