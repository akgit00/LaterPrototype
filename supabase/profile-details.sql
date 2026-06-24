-- Adds editable profile fields (bio + avatar image) so a user's profile
-- customizations persist in the cloud across logout and reinstalls.
-- The "update own profile" RLS policy (in memories-sharing.sql) already
-- allows a user to write these columns on their own row.

alter table public.profiles
    add column if not exists bio text,
    add column if not exists avatar_url text;
