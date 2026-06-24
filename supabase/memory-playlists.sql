-- Memory playlists -------------------------------------------------------------
-- A dedicated table so EVERYONE on a memory (the owner and anyone it's shared
-- with) can attach / update the Spotify or Apple Music playlist and see each
-- other's. Storing the playlist only in the memory payload didn't work for
-- shared connections, because only the owner is allowed to update the memory
-- row. One playlist per memory, keyed by memory_id, upserted on change.

create table if not exists public.memory_playlists (
    memory_id  uuid primary key references public.memories (id) on delete cascade,
    author_id  uuid not null default auth.uid() references auth.users (id) on delete cascade,
    payload    jsonb not null,
    updated_at timestamptz not null default now()
);

alter table public.memory_playlists enable row level security;

-- Base table privileges. RLS controls WHICH rows a role can touch, but the role
-- still needs table-level grants to touch the table at all. Without this you get
-- "permission denied for table memory_playlists" (42501) even with correct policies.
grant select, insert, update, delete on public.memory_playlists to authenticated;

-- Read the playlist on any memory you can see (own or shared-with-you).
drop policy if exists "read playlist on accessible memories" on public.memory_playlists;
create policy "read playlist on accessible memories"
    on public.memory_playlists for select
    to authenticated
    using (
        memory_id in (
            select id from public.memories where owner_id = auth.uid()
            union
            select memory_id from public.memory_shares where shared_with = auth.uid()
        )
    );

-- Add a playlist to any memory you can see, as yourself.
drop policy if exists "add playlist to accessible memories" on public.memory_playlists;
create policy "add playlist to accessible memories"
    on public.memory_playlists for insert
    to authenticated
    with check (
        author_id = auth.uid()
        and memory_id in (
            select id from public.memories where owner_id = auth.uid()
            union
            select memory_id from public.memory_shares where shared_with = auth.uid()
        )
    );

-- Update the playlist on any memory you can see (so connections can change it).
drop policy if exists "update playlist on accessible memories" on public.memory_playlists;
create policy "update playlist on accessible memories"
    on public.memory_playlists for update
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

-- Remove the playlist on any memory you can see.
drop policy if exists "delete playlist on accessible memories" on public.memory_playlists;
create policy "delete playlist on accessible memories"
    on public.memory_playlists for delete
    to authenticated
    using (
        memory_id in (
            select id from public.memories where owner_id = auth.uid()
            union
            select memory_id from public.memory_shares where shared_with = auth.uid()
        )
    );
