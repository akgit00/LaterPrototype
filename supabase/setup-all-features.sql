-- ============================================================================
-- Later — full feature setup (run this whole file in the Supabase SQL editor)
-- ============================================================================
-- This creates every per-memory feature table (comments, direct messages,
-- media, playlists, songs) in the correct order. The base tables this depends
-- on — public.memories, public.memory_shares, public.connections — must
-- already exist (from memories-sharing.sql and connections.sql).
--
-- IMPORTANT: run the ENTIRE file at once. The earlier
-- "relation public.memory_playlists does not exist" error happens when only a
-- GRANT or policy line is run without the CREATE TABLE above it. Everything
-- here is idempotent (create table if not exists / drop policy if exists), so
-- it is safe to re-run.
-- ============================================================================


-- ── Memory comments ─────────────────────────────────────────────────────────
create table if not exists public.memory_comments (
    id         uuid primary key default gen_random_uuid(),
    memory_id  uuid not null references public.memories (id) on delete cascade,
    author_id  uuid not null default auth.uid() references auth.users (id) on delete cascade,
    username   text not null,
    text       text not null,
    created_at timestamptz not null default now()
);
create index if not exists memory_comments_memory_idx on public.memory_comments (memory_id);
alter table public.memory_comments enable row level security;
grant select, insert, delete on public.memory_comments to authenticated;

drop policy if exists "read comments on accessible memories" on public.memory_comments;
create policy "read comments on accessible memories"
    on public.memory_comments for select to authenticated
    using (
        memory_id in (
            select id from public.memories where owner_id = auth.uid()
            union
            select memory_id from public.memory_shares where shared_with = auth.uid()
        )
    );

drop policy if exists "comment on accessible memories" on public.memory_comments;
create policy "comment on accessible memories"
    on public.memory_comments for insert to authenticated
    with check (
        author_id = auth.uid()
        and memory_id in (
            select id from public.memories where owner_id = auth.uid()
            union
            select memory_id from public.memory_shares where shared_with = auth.uid()
        )
    );

drop policy if exists "delete own comments" on public.memory_comments;
create policy "delete own comments"
    on public.memory_comments for delete to authenticated
    using (author_id = auth.uid());


-- ── Direct messages ─────────────────────────────────────────────────────────
create table if not exists public.messages (
    id            uuid primary key default gen_random_uuid(),
    sender_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
    recipient_id  uuid not null references auth.users (id) on delete cascade,
    body          text not null check (char_length(body) between 1 and 4000),
    created_at    timestamptz not null default now(),
    check (sender_id <> recipient_id)
);
create index if not exists messages_sender_idx on public.messages (sender_id);
create index if not exists messages_recipient_idx on public.messages (recipient_id);
create index if not exists messages_created_idx on public.messages (created_at);
alter table public.messages enable row level security;
grant select, insert, delete on public.messages to authenticated;

drop policy if exists "read own messages" on public.messages;
create policy "read own messages"
    on public.messages for select to authenticated
    using (sender_id = auth.uid() or recipient_id = auth.uid());

drop policy if exists "insert own messages" on public.messages;
create policy "insert own messages"
    on public.messages for insert to authenticated
    with check (
        sender_id = auth.uid()
        and exists (
            select 1 from public.connections c
            where c.status = 'accepted'
              and (
                  (c.requester_id = auth.uid() and c.addressee_id = messages.recipient_id)
                  or
                  (c.addressee_id = auth.uid() and c.requester_id = messages.recipient_id)
              )
        )
    );

drop policy if exists "delete own messages" on public.messages;
create policy "delete own messages"
    on public.messages for delete to authenticated
    using (sender_id = auth.uid());


-- ── Memory media (photos / videos) ──────────────────────────────────────────
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
grant select, insert, delete on public.memory_media to authenticated;

drop policy if exists "read media on accessible memories" on public.memory_media;
create policy "read media on accessible memories"
    on public.memory_media for select to authenticated
    using (
        memory_id in (
            select id from public.memories where owner_id = auth.uid()
            union
            select memory_id from public.memory_shares where shared_with = auth.uid()
        )
    );

drop policy if exists "add media to accessible memories" on public.memory_media;
create policy "add media to accessible memories"
    on public.memory_media for insert to authenticated
    with check (
        author_id = auth.uid()
        and memory_id in (
            select id from public.memories where owner_id = auth.uid()
            union
            select memory_id from public.memory_shares where shared_with = auth.uid()
        )
    );

drop policy if exists "delete own media" on public.memory_media;
create policy "delete own media"
    on public.memory_media for delete to authenticated
    using (author_id = auth.uid());


-- ── Memory playlists ────────────────────────────────────────────────────────
create table if not exists public.memory_playlists (
    memory_id  uuid primary key references public.memories (id) on delete cascade,
    author_id  uuid not null default auth.uid() references auth.users (id) on delete cascade,
    payload    jsonb not null,
    updated_at timestamptz not null default now()
);
alter table public.memory_playlists enable row level security;
grant select, insert, update, delete on public.memory_playlists to authenticated;

drop policy if exists "read playlist on accessible memories" on public.memory_playlists;
create policy "read playlist on accessible memories"
    on public.memory_playlists for select to authenticated
    using (
        memory_id in (
            select id from public.memories where owner_id = auth.uid()
            union
            select memory_id from public.memory_shares where shared_with = auth.uid()
        )
    );

drop policy if exists "add playlist to accessible memories" on public.memory_playlists;
create policy "add playlist to accessible memories"
    on public.memory_playlists for insert to authenticated
    with check (
        author_id = auth.uid()
        and memory_id in (
            select id from public.memories where owner_id = auth.uid()
            union
            select memory_id from public.memory_shares where shared_with = auth.uid()
        )
    );

drop policy if exists "update playlist on accessible memories" on public.memory_playlists;
create policy "update playlist on accessible memories"
    on public.memory_playlists for update to authenticated
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

drop policy if exists "delete playlist on accessible memories" on public.memory_playlists;
create policy "delete playlist on accessible memories"
    on public.memory_playlists for delete to authenticated
    using (
        memory_id in (
            select id from public.memories where owner_id = auth.uid()
            union
            select memory_id from public.memory_shares where shared_with = auth.uid()
        )
    );


-- ── Memory songs ────────────────────────────────────────────────────────────
create table if not exists public.memory_songs (
    id         uuid primary key,
    memory_id  uuid not null references public.memories (id) on delete cascade,
    author_id  uuid not null default auth.uid() references auth.users (id) on delete cascade,
    payload    jsonb not null,
    created_at timestamptz not null default now()
);
create index if not exists memory_songs_memory_idx on public.memory_songs (memory_id);
alter table public.memory_songs enable row level security;
grant select, insert, delete on public.memory_songs to authenticated;

drop policy if exists "read songs on accessible memories" on public.memory_songs;
create policy "read songs on accessible memories"
    on public.memory_songs for select to authenticated
    using (
        memory_id in (
            select id from public.memories where owner_id = auth.uid()
            union
            select memory_id from public.memory_shares where shared_with = auth.uid()
        )
    );

drop policy if exists "add songs to accessible memories" on public.memory_songs;
create policy "add songs to accessible memories"
    on public.memory_songs for insert to authenticated
    with check (
        author_id = auth.uid()
        and memory_id in (
            select id from public.memories where owner_id = auth.uid()
            union
            select memory_id from public.memory_shares where shared_with = auth.uid()
        )
    );

drop policy if exists "delete own songs" on public.memory_songs;
create policy "delete own songs"
    on public.memory_songs for delete to authenticated
    using (author_id = auth.uid());
