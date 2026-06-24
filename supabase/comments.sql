-- Memory comments -------------------------------------------------------------
-- A dedicated table so EVERYONE on a memory (the owner and anyone it's shared
-- with) can comment and see each other's comments. Storing comments in the
-- memory payload didn't work for shared connections, because only the owner is
-- allowed to update the memory row.

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

-- Base table privileges. RLS controls WHICH rows a role can touch, but the role
-- still needs table-level grants to touch the table at all. Without this you get
-- "permission denied for table memory_comments" (42501) even with correct policies.
grant select, insert, delete on public.memory_comments to authenticated;

-- A reusable check: the signed-in user can access this memory if they own it
-- or it has been shared with them.
-- (Inlined in each policy below rather than a function to keep this migration
--  self-contained.)

-- Read comments on any memory you can see (own or shared-with-you).
drop policy if exists "read comments on accessible memories" on public.memory_comments;
create policy "read comments on accessible memories"
    on public.memory_comments for select
    to authenticated
    using (
        memory_id in (
            select id from public.memories where owner_id = auth.uid()
            union
            select memory_id from public.memory_shares where shared_with = auth.uid()
        )
    );

-- Add a comment to any memory you can see, as yourself.
drop policy if exists "comment on accessible memories" on public.memory_comments;
create policy "comment on accessible memories"
    on public.memory_comments for insert
    to authenticated
    with check (
        author_id = auth.uid()
        and memory_id in (
            select id from public.memories where owner_id = auth.uid()
            union
            select memory_id from public.memory_shares where shared_with = auth.uid()
        )
    );

-- You can delete your own comments.
drop policy if exists "delete own comments" on public.memory_comments;
create policy "delete own comments"
    on public.memory_comments for delete
    to authenticated
    using (author_id = auth.uid());
