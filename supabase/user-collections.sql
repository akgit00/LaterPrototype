-- User collections --------------------------------------------------------------
-- Personal, top-level collections that group whole memories together — an "era"
-- of your life, a trip series, or anything else. The full collection (name,
-- emoji, color, member memory ids) is stored as JSON in `payload`; rows are
-- private to their owner. Auto year-end "Wrapped" collections are computed on
-- device from the memories themselves, so only custom collections live here.
create table if not exists public.user_collections (
    id          uuid primary key,
    owner_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
    payload     jsonb not null,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

create index if not exists user_collections_owner_idx on public.user_collections (owner_id);

alter table public.user_collections enable row level security;

-- Base table privileges. RLS controls WHICH rows a role can touch, but the role
-- still needs table-level grants to touch the table at all.
grant select, insert, update, delete on public.user_collections to authenticated;

-- Collections are private: only the owner can see or change their rows.
drop policy if exists "read own collections" on public.user_collections;
create policy "read own collections"
    on public.user_collections for select
    to authenticated
    using (owner_id = auth.uid());

drop policy if exists "insert own collections" on public.user_collections;
create policy "insert own collections"
    on public.user_collections for insert
    to authenticated
    with check (owner_id = auth.uid());

drop policy if exists "update own collections" on public.user_collections;
create policy "update own collections"
    on public.user_collections for update
    to authenticated
    using (owner_id = auth.uid())
    with check (owner_id = auth.uid());

drop policy if exists "delete own collections" on public.user_collections;
create policy "delete own collections"
    on public.user_collections for delete
    to authenticated
    using (owner_id = auth.uid());
