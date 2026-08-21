-- Memory extras ---------------------------------------------------------------
-- One shared table for everything people add INSIDE a memory beyond media:
-- story entries, voice notes, sealed notes, polls, poll votes, prompts,
-- prompt answers, and keepsakes. Like comments, these need their own table so
-- EVERYONE on a memory (owner + shared-with) can contribute — only the owner
-- may update the memory row itself.
--
-- kind values: story | voice | sealed | poll | poll_vote | prompt |
--              prompt_answer | keepsake
-- payload: JSON string with that kind's fields (see MemoryExtras.swift).
--
-- Run this in the Supabase SQL editor.

create table if not exists public.memory_extras (
    id          uuid primary key,
    memory_id   uuid not null references public.memories (id) on delete cascade,
    author_id   uuid not null default auth.uid() references auth.users (id) on delete cascade,
    author_name text not null default '',
    kind        text not null,
    payload     text not null,
    created_at  timestamptz not null default now()
);

create index if not exists memory_extras_memory_idx on public.memory_extras (memory_id);

alter table public.memory_extras enable row level security;

-- Base table privileges (RLS narrows rows, but the role needs table grants).
grant select, insert, update, delete on public.memory_extras to authenticated;

-- Read extras on any memory you can see (own or shared-with-you).
drop policy if exists "read extras on accessible memories" on public.memory_extras;
create policy "read extras on accessible memories"
    on public.memory_extras for select
    to authenticated
    using (
        memory_id in (
            select id from public.memories where owner_id = auth.uid()
            union
            select memory_id from public.memory_shares where shared_with = auth.uid()
        )
    );

-- Add extras to any memory you can see, as yourself.
drop policy if exists "add extras on accessible memories" on public.memory_extras;
create policy "add extras on accessible memories"
    on public.memory_extras for insert
    to authenticated
    with check (
        author_id = auth.uid()
        and memory_id in (
            select id from public.memories where owner_id = auth.uid()
            union
            select memory_id from public.memory_shares where shared_with = auth.uid()
        )
    );

-- Edit your own extras (rewriting a story entry, changing a vote/answer).
drop policy if exists "update own extras" on public.memory_extras;
create policy "update own extras"
    on public.memory_extras for update
    to authenticated
    using (author_id = auth.uid())
    with check (author_id = auth.uid());

-- Delete your own extras, or moderate anything on a memory you own.
drop policy if exists "delete own or owned-memory extras" on public.memory_extras;
create policy "delete own or owned-memory extras"
    on public.memory_extras for delete
    to authenticated
    using (
        author_id = auth.uid()
        or memory_id in (select id from public.memories where owner_id = auth.uid())
    );
