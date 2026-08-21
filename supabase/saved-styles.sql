-- Stores each user's bookmarked community map styles as a JSON array of
-- {"name": "...", "raw": "mapbox://styles/..."} objects on their profile row,
-- so saved styles survive reinstalls and follow their account across devices.
-- The "update own profile" RLS policy (memories-sharing.sql) already lets a
-- user write this column on their own row.
-- Run this in the Supabase SQL editor.

alter table public.profiles
    add column if not exists saved_map_styles jsonb;
