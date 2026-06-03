-- ============================================================================
-- Later — cloud memories + friend sharing
-- Run this once in your Supabase project:
--   Dashboard → SQL Editor → New query → paste → Run
--
-- Safe to re-run: everything uses IF NOT EXISTS / CREATE OR REPLACE.
-- Uses native Supabase Auth (auth.uid()), matching how the app signs in.
-- ============================================================================

-- 1. Profiles -----------------------------------------------------------------
create table if not exists public.profiles (
    id           uuid primary key references auth.users (id) on delete cascade,
    username     text unique not null,
    email        text,
    display_name text,
    avatar_color text,
    created_at   timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Enforce globally unique usernames, case-insensitively ("John" == "john").
-- The inline `unique` above covers exact case; this index closes the case gap.
create unique index if not exists profiles_username_lower_key
    on public.profiles (lower(username));

-- Any signed-in user can look up profiles (so friends can be found by name/email).
drop policy if exists "profiles readable by authenticated" on public.profiles;
create policy "profiles readable by authenticated"
    on public.profiles for select
    to authenticated
    using (true);

drop policy if exists "insert own profile" on public.profiles;
create policy "insert own profile"
    on public.profiles for insert
    to authenticated
    with check (id = auth.uid());

drop policy if exists "update own profile" on public.profiles;
create policy "update own profile"
    on public.profiles for update
    to authenticated
    using (id = auth.uid())
    with check (id = auth.uid());

-- 2. Memories -----------------------------------------------------------------
create table if not exists public.memories (
    id         uuid primary key,
    owner_id   uuid not null default auth.uid() references auth.users (id) on delete cascade,
    payload    jsonb not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists memories_owner_idx on public.memories (owner_id);

alter table public.memories enable row level security;

-- 3. Shares -------------------------------------------------------------------
create table if not exists public.memory_shares (
    id          uuid primary key default gen_random_uuid(),
    memory_id   uuid not null references public.memories (id) on delete cascade,
    owner_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
    shared_with uuid not null references auth.users (id) on delete cascade,
    created_at  timestamptz not null default now(),
    unique (memory_id, shared_with)
);

create index if not exists memory_shares_shared_with_idx on public.memory_shares (shared_with);

alter table public.memory_shares enable row level security;

-- Memories: owner has full access; recipients can read shared memories.
drop policy if exists "read own or shared memories" on public.memories;
create policy "read own or shared memories"
    on public.memories for select
    to authenticated
    using (
        owner_id = auth.uid()
        or id in (select memory_id from public.memory_shares where shared_with = auth.uid())
    );

drop policy if exists "insert own memories" on public.memories;
create policy "insert own memories"
    on public.memories for insert
    to authenticated
    with check (owner_id = auth.uid());

drop policy if exists "update own memories" on public.memories;
create policy "update own memories"
    on public.memories for update
    to authenticated
    using (owner_id = auth.uid())
    with check (owner_id = auth.uid());

drop policy if exists "delete own memories" on public.memories;
create policy "delete own memories"
    on public.memories for delete
    to authenticated
    using (owner_id = auth.uid());

-- Shares: the memory owner manages shares; recipients can see their own.
drop policy if exists "read relevant shares" on public.memory_shares;
create policy "read relevant shares"
    on public.memory_shares for select
    to authenticated
    using (owner_id = auth.uid() or shared_with = auth.uid());

drop policy if exists "insert own shares" on public.memory_shares;
create policy "insert own shares"
    on public.memory_shares for insert
    to authenticated
    with check (owner_id = auth.uid());

drop policy if exists "delete own shares" on public.memory_shares;
create policy "delete own shares"
    on public.memory_shares for delete
    to authenticated
    using (owner_id = auth.uid());

-- 4. Storage bucket for photos / videos --------------------------------------
insert into storage.buckets (id, name, public)
values ('memory-media', 'memory-media', true)
on conflict (id) do nothing;

-- Anyone can read media (public bucket); users upload only into their own folder.
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
