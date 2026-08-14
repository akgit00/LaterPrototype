-- ============================================================================
-- Later — sharing visibility fixes (run this whole file in the SQL editor)
-- ============================================================================
-- Fixes two bugs reported in shared memories:
--
--   1. PEOPLE COUNT SHOWS 0 FOR SHARED USERS
--      The old policy only let a person read their OWN share row, so someone
--      a memory was shared with couldn't see who else is on it — the people
--      list (and count) stayed empty for everyone but the owner.
--
--   2. PHOTOS/VIDEOS ADDED BY OTHERS CAN'T BE VIEWED
--      Ensures the media storage bucket exists, is PUBLIC (so uploaded photos
--      and videos load for everyone), and that every participant can upload
--      into their own folder. If the bucket was missing or private, uploads
--      failed silently and the app fell back to device-local file paths that
--      nobody else could display.
--
-- Everything is idempotent — safe to re-run.
-- ============================================================================


-- ── 1. Everyone on a memory can see its full share list ─────────────────────
-- SECURITY DEFINER avoids the infinite-recursion error that a direct
-- self-referencing policy on memory_shares would cause.
create or replace function public.can_access_memory(mid uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
    select exists (
        select 1 from public.memories m
        where m.id = mid and m.owner_id = auth.uid()
    ) or exists (
        select 1 from public.memory_shares s
        where s.memory_id = mid and s.shared_with = auth.uid()
    );
$$;

revoke all on function public.can_access_memory(uuid) from public;
grant execute on function public.can_access_memory(uuid) to authenticated;

drop policy if exists "read relevant shares" on public.memory_shares;
create policy "read relevant shares"
    on public.memory_shares for select
    to authenticated
    using (public.can_access_memory(memory_id));


-- ── 2. Storage: public media bucket + upload policies ───────────────────────
insert into storage.buckets (id, name, public)
values ('memory-media', 'memory-media', true)
on conflict (id) do update set public = true;

drop policy if exists "public read memory media" on storage.objects;
create policy "public read memory media"
    on storage.objects for select
    using (bucket_id = 'memory-media');

drop policy if exists "upload own memory media" on storage.objects;
create policy "upload own memory media"
    on storage.objects for insert
    to authenticated
    with check (
        bucket_id = 'memory-media'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

drop policy if exists "update own memory media" on storage.objects;
create policy "update own memory media"
    on storage.objects for update
    to authenticated
    using (
        bucket_id = 'memory-media'
        and (storage.foldername(name))[1] = auth.uid()::text
    );


-- ── 3. Diagnostics (optional — run separately to inspect) ───────────────────
-- How many media rows still point at device-local files (invisible to others)?
-- The app now repairs these automatically when the person who added them opens
-- the app, so this count should shrink toward zero over time.
--
--   select kind, count(*) from public.memory_media
--   where url like 'file:%' group by kind;
