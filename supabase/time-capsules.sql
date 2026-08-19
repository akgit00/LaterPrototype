-- Time capsules -----------------------------------------------------------------
-- A sealed message (plus media) delivered on a chosen date, either to yourself
-- ("Future me") or to a friend. The full capsule is stored as JSON in `payload`;
-- `deliver_at` is duplicated as a column so row-level security can hide a
-- capsule from its recipient until the delivery date arrives.
create table if not exists public.time_capsules (
    id            uuid primary key,
    sender_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
    recipient_id  uuid not null references auth.users (id) on delete cascade,
    deliver_at    timestamptz not null,
    payload       jsonb not null,
    created_at    timestamptz not null default now()
);

create index if not exists time_capsules_sender_idx on public.time_capsules (sender_id);
create index if not exists time_capsules_recipient_idx on public.time_capsules (recipient_id, deliver_at);

alter table public.time_capsules enable row level security;

-- Base table privileges. RLS controls WHICH rows a role can touch, but the role
-- still needs table-level grants to touch the table at all.
grant select, insert, update, delete on public.time_capsules to authenticated;

-- The sender always sees their own capsules. The recipient can only see a
-- capsule once its delivery date has arrived — before that the row is
-- invisible to them, so sealed contents can never leak early.
drop policy if exists "read own or delivered capsules" on public.time_capsules;
create policy "read own or delivered capsules"
    on public.time_capsules for select
    to authenticated
    using (
        sender_id = auth.uid()
        or (recipient_id = auth.uid() and deliver_at <= now())
    );

-- You can only seal capsules as yourself, addressed to yourself or to someone
-- you're connected to (an accepted connection in either direction).
drop policy if exists "insert own capsules" on public.time_capsules;
create policy "insert own capsules"
    on public.time_capsules for insert
    to authenticated
    with check (
        sender_id = auth.uid()
        and (
            recipient_id = auth.uid()
            or exists (
                select 1 from public.connections c
                where c.status = 'accepted'
                  and (
                      (c.requester_id = auth.uid() and c.addressee_id = time_capsules.recipient_id)
                      or
                      (c.addressee_id = auth.uid() and c.requester_id = time_capsules.recipient_id)
                  )
            )
        )
    );

-- Only the sender may update or delete their capsule.
drop policy if exists "update own capsules" on public.time_capsules;
create policy "update own capsules"
    on public.time_capsules for update
    to authenticated
    using (sender_id = auth.uid())
    with check (sender_id = auth.uid());

drop policy if exists "delete own capsules" on public.time_capsules;
create policy "delete own capsules"
    on public.time_capsules for delete
    to authenticated
    using (sender_id = auth.uid());
