-- Per-user capsule removals ------------------------------------------------------
-- When a recipient deletes a capsule someone sent them, the row itself must
-- survive (it's the sender's copy), so the removal is recorded here instead.
-- The app syncs these hides so a removed capsule stays gone across all of the
-- recipient's devices. Rows cascade away when the capsule itself is deleted.

create table if not exists public.capsule_hides (
    capsule_id uuid not null references public.time_capsules(id) on delete cascade,
    user_id uuid not null default auth.uid(),
    created_at timestamptz not null default now(),
    primary key (capsule_id, user_id)
);

alter table public.capsule_hides enable row level security;

drop policy if exists "read own capsule hides" on public.capsule_hides;
create policy "read own capsule hides" on public.capsule_hides
    for select using (auth.uid() = user_id);

drop policy if exists "insert own capsule hides" on public.capsule_hides;
create policy "insert own capsule hides" on public.capsule_hides
    for insert with check (auth.uid() = user_id);

drop policy if exists "delete own capsule hides" on public.capsule_hides;
create policy "delete own capsule hides" on public.capsule_hides
    for delete using (auth.uid() = user_id);
