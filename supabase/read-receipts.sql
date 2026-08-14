-- ============================================================================
-- Later — read receipts for direct messages (run this whole file)
-- ============================================================================
-- Adds a `read_at` timestamp to messages. When someone opens a conversation
-- (and has read receipts enabled in the app), the messages they received are
-- stamped read — the sender then sees a "Read" receipt under their message.
-- The same stamp powers cross-device unread badges.
--
-- Idempotent — safe to re-run.

alter table public.messages
    add column if not exists read_at timestamptz;

-- Recipients may update ONLY the read_at column of messages sent to them.
grant update (read_at) on public.messages to authenticated;

drop policy if exists "recipient can mark messages read" on public.messages;
create policy "recipient can mark messages read"
    on public.messages for update
    to authenticated
    using (recipient_id = auth.uid())
    with check (recipient_id = auth.uid());
