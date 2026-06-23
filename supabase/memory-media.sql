-- Memory media ----------------------------------------------------------------
-- A dedicated table so EVERYONE on a memory (the owner and anyone it's shared
-- with) can add photos and videos and see each other's. Storing media only in
-- the memory payload didn't work for shared connections, because only the owner
-- is allowed to update the memory row.

create table if not exists public.memory_media (
    id            uuid primary key default gen_random_uuid(),
    memory_id     uuid not null references public.memories (id) on delete cascade,
    author_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
    kind          text not null check (kind in ('photo', 'video')),
    url           text not null,
    thumbnail_url text,
    duration      text,
    created_at    timestamptz not null default now()
);

create index if not exists memory_media_memory_idx on public.memory_media (memory_id);

alter table public.memory_media enable row level security;

-- Read media on any memory you can see (own or shared-with-you).
drop policy if exists "read media on accessible memories" on public.memory_media;
create policy "read media on accessible memories"
    on public.memory_media for select
    to authenticated
    using (
        memory_id in (
            select id from public.memories where owner_id = auth.uid()
            union
            select memory_id from public.memory_shares where shared_with = auth.uid()
        )
    );

-- Add media to any memory you can see, as yourself.
drop policy if exists "add media to accessible memories" on public.memory_media;
create policy "add media to accessible memories"
    on public.memory_media for insert
    to authenticated
    with check (
        author_id = auth.uid()
        and memory_id in (
            select id from public.memories where owner_id = auth.uid()
            union
            select memory_id from public.memory_shares where shared_with = auth.uid()
        )
    );

-- You can delete your own media.
drop policy if exists "delete own media" on public.memory_media;
create policy "delete own media"
    on public.memory_media for delete
    to authenticated
    using (author_id = auth.uid());
