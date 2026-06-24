-- Memory songs ----------------------------------------------------------------
-- A dedicated table so EVERYONE on a memory (the owner and anyone it's shared
-- with) can add individual songs and see each other's. Storing songs only in
-- the memory payload didn't work for shared connections, because only the owner
-- is allowed to update the memory row. The row id matches the local
-- PlaylistTrack id so the same song isn't duplicated when other devices pull it.

create table if not exists public.memory_songs (
    id         uuid primary key,
    memory_id  uuid not null references public.memories (id) on delete cascade,
    author_id  uuid not null default auth.uid() references auth.users (id) on delete cascade,
    payload    jsonb not null,
    created_at timestamptz not null default now()
);

create index if not exists memory_songs_memory_idx on public.memory_songs (memory_id);

alter table public.memory_songs enable row level security;

-- Base table privileges. RLS controls WHICH rows a role can touch, but the role
-- still needs table-level grants to touch the table at all. Without this you get
-- "permission denied for table memory_songs" (42501) even with correct policies.
-- UPDATE is required because songs are written with an upsert (on_conflict +
-- merge-duplicates), which Postgres runs as INSERT ... ON CONFLICT DO UPDATE and
-- needs UPDATE privilege even when inserting a brand-new row.
grant select, insert, update, delete on public.memory_songs to authenticated;

-- Read songs on any memory you can see (own or shared-with-you).
drop policy if exists "read songs on accessible memories" on public.memory_songs;
create policy "read songs on accessible memories"
    on public.memory_songs for select
    to authenticated
    using (
        memory_id in (
            select id from public.memories where owner_id = auth.uid()
            union
            select memory_id from public.memory_shares where shared_with = auth.uid()
        )
    );

-- Add a song to any memory you can see, as yourself.
drop policy if exists "add songs to accessible memories" on public.memory_songs;
create policy "add songs to accessible memories"
    on public.memory_songs for insert
    to authenticated
    with check (
        author_id = auth.uid()
        and memory_id in (
            select id from public.memories where owner_id = auth.uid()
            union
            select memory_id from public.memory_shares where shared_with = auth.uid()
        )
    );

-- Update songs on any memory you can see (needed so the song upsert's
-- ON CONFLICT DO UPDATE path is allowed by RLS).
drop policy if exists "update songs on accessible memories" on public.memory_songs;
create policy "update songs on accessible memories"
    on public.memory_songs for update
    to authenticated
    using (
        memory_id in (
            select id from public.memories where owner_id = auth.uid()
            union
            select memory_id from public.memory_shares where shared_with = auth.uid()
        )
    )
    with check (
        memory_id in (
            select id from public.memories where owner_id = auth.uid()
            union
            select memory_id from public.memory_shares where shared_with = auth.uid()
        )
    );

-- You can delete your own songs.
drop policy if exists "delete own songs" on public.memory_songs;
create policy "delete own songs"
    on public.memory_songs for delete
    to authenticated
    using (author_id = auth.uid());
