-- ============================================================================
-- Guest invites + live people lists (run this whole file in the SQL editor)
-- ============================================================================
-- 1. Lets people a memory is shared with add MORE people, but only when the
--    owner has switched on "Let others add people" for that memory.
-- 2. Lets everyone on a memory see the full share list, so the People section
--    and people counts stay accurate for all participants.
-- Safe to re-run (drop policy if exists / create or replace function).
-- ============================================================================

-- Whether the signed-in user can see the given memory at all.
create or replace function public.has_memory_access(mid uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
    select exists (
        select 1 from memories m
        where m.id = mid and m.owner_id = auth.uid()
    )
    or exists (
        select 1 from memory_shares s
        where s.memory_id = mid and s.shared_with = auth.uid()
    );
$$;

-- Whether the signed-in user may add people to the given memory: always for
-- the owner, and for shared-with users when the owner enabled guest invites.
create or replace function public.can_invite_to_memory(mid uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
    select exists (
        select 1 from memories m
        where m.id = mid
          and (
              m.owner_id = auth.uid()
              or (
                  coalesce((m.payload->>'allowsGuestInvites')::boolean, false)
                  and exists (
                      select 1 from memory_shares s
                      where s.memory_id = mid and s.shared_with = auth.uid()
                  )
              )
          )
    );
$$;

-- Everyone on a memory can read its full share list (needed for accurate
-- people lists / counts on every device).
drop policy if exists "read relevant shares" on public.memory_shares;
drop policy if exists "read shares on accessible memories" on public.memory_shares;
create policy "read shares on accessible memories"
    on public.memory_shares for select
    to authenticated
    using (public.has_memory_access(memory_id));

-- Owner always; guests only when the owner allowed it. The stored owner_id
-- must always be the memory's real owner.
drop policy if exists "insert own shares" on public.memory_shares;
drop policy if exists "insert own or guest shares" on public.memory_shares;
create policy "insert own or guest shares"
    on public.memory_shares for insert
    to authenticated
    with check (
        public.can_invite_to_memory(memory_id)
        and owner_id = (select m.owner_id from public.memories m where m.id = memory_id)
    );
