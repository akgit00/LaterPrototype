-- Direct messages ---------------------------------------------------------------
-- A 1:1 message between two users. Each row is one message from `sender_id` to
-- `recipient_id`. Conversations are derived from the pair of participants.
create table if not exists public.messages (
    id            uuid primary key default gen_random_uuid(),
    sender_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
    recipient_id  uuid not null references auth.users (id) on delete cascade,
    body          text not null check (char_length(body) between 1 and 4000),
    created_at    timestamptz not null default now(),
    -- You can't message yourself.
    check (sender_id <> recipient_id)
);

create index if not exists messages_sender_idx on public.messages (sender_id);
create index if not exists messages_recipient_idx on public.messages (recipient_id);
create index if not exists messages_created_idx on public.messages (created_at);

alter table public.messages enable row level security;

-- Base table privileges. RLS controls WHICH rows a role can touch, but the role
-- still needs table-level grants to touch the table at all. Without this you get
-- "permission denied for table messages" (42501) even with correct policies.
grant select, insert, delete on public.messages to authenticated;

-- Either participant can read a message that involves them.
drop policy if exists "read own messages" on public.messages;
create policy "read own messages"
    on public.messages for select
    to authenticated
    using (sender_id = auth.uid() or recipient_id = auth.uid());

-- You can only send messages as yourself, and only to someone you're connected
-- to (an accepted connection in either direction).
drop policy if exists "insert own messages" on public.messages;
create policy "insert own messages"
    on public.messages for insert
    to authenticated
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

-- The sender can delete their own message.
drop policy if exists "delete own messages" on public.messages;
create policy "delete own messages"
    on public.messages for delete
    to authenticated
    using (sender_id = auth.uid());
