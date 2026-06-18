-- Connections (friends) ---------------------------------------------------------
-- A mutual friendship is represented by a single row. The person who sends the
-- request is `requester_id`; the person who receives it is `addressee_id`.
-- `status` moves from 'pending' -> 'accepted' when the addressee accepts.
create table if not exists public.connections (
    id            uuid primary key default gen_random_uuid(),
    requester_id  uuid not null default auth.uid() references auth.users (id) on delete cascade,
    addressee_id  uuid not null references auth.users (id) on delete cascade,
    status        text not null default 'pending' check (status in ('pending', 'accepted')),
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now(),
    -- Only one connection row per ordered pair; prevents duplicate requests.
    unique (requester_id, addressee_id),
    -- You can't befriend yourself.
    check (requester_id <> addressee_id)
);

create index if not exists connections_requester_idx on public.connections (requester_id);
create index if not exists connections_addressee_idx on public.connections (addressee_id);

alter table public.connections enable row level security;

-- Either party can read a connection row that involves them.
drop policy if exists "read own connections" on public.connections;
create policy "read own connections"
    on public.connections for select
    to authenticated
    using (requester_id = auth.uid() or addressee_id = auth.uid());

-- You can only create requests where you are the requester.
drop policy if exists "insert own requests" on public.connections;
create policy "insert own requests"
    on public.connections for insert
    to authenticated
    with check (requester_id = auth.uid());

-- Either party can update the row (the addressee accepts; either can't escalate
-- beyond the allowed status values thanks to the check constraint above).
drop policy if exists "update own connections" on public.connections;
create policy "update own connections"
    on public.connections for update
    to authenticated
    using (requester_id = auth.uid() or addressee_id = auth.uid())
    with check (requester_id = auth.uid() or addressee_id = auth.uid());

-- Either party can delete the connection (decline a request / remove a friend).
drop policy if exists "delete own connections" on public.connections;
create policy "delete own connections"
    on public.connections for delete
    to authenticated
    using (requester_id = auth.uid() or addressee_id = auth.uid());
