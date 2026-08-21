-- Persists each user's app-wide map theme pick (a built-in theme name or a
-- custom mapbox://styles/... URL) on their profile row so it survives app
-- reinstalls and follows their account across devices.
-- The "update own profile" RLS policy (memories-sharing.sql) already lets a
-- user write this column on their own row.
-- Run this in the Supabase SQL editor.

alter table public.profiles
    add column if not exists map_theme text;
