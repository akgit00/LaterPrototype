-- Capsule unlock notifications ---------------------------------------------------
-- A pg_cron job runs every minute, finds capsules whose delivery date has just
-- arrived, and asks the send-push edge function to notify each recipient's
-- devices. Rows are marked notified in the same statement that selects them,
-- so a capsule can never push twice.

-- Tracks whether the unlock push for a capsule has been sent.
alter table public.time_capsules
    add column if not exists notified_at timestamptz;

-- Capsules that were already delivered before this feature existed shouldn't
-- suddenly notify — mark them as handled.
update public.time_capsules
    set notified_at = created_at
    where deliver_at <= now() and notified_at is null;

-- The every-minute scan only ever looks at unnotified capsules.
create index if not exists time_capsules_unnotified_idx
    on public.time_capsules (deliver_at)
    where notified_at is null;

-- Scheduler + async HTTP from Postgres.
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- One-time setup (run manually with the real key — NEVER commit it):
--   select vault.create_secret('<secret-api-key>', 'service_role_key');
-- Use the project's SECRET api key (sb_secret_…) — it must equal the
-- SUPABASE_SERVICE_ROLE_KEY the edge function runtime sees, because send-push
-- compares the bearer against that value to trust this cron as a caller.

create or replace function public.notify_unlocked_capsules()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    service_key text;
    push_url text := 'https://idpqqafwmjbbfyxxbaur.supabase.co/functions/v1/send-push';
    capsule record;
    sender_name text;
    capsule_title text;
    push_body text;
begin
    select decrypted_secret into service_key
    from vault.decrypted_secrets
    where name = 'service_role_key'
    limit 1;

    if service_key is null then
        raise warning 'notify_unlocked_capsules: vault secret "service_role_key" missing';
        return;
    end if;

    for capsule in
        with due as (
            update public.time_capsules
            set notified_at = now()
            where deliver_at <= now()
              and notified_at is null
            returning recipient_id, sender_id, payload
        )
        select * from due
    loop
        capsule_title := coalesce(nullif(left(capsule.payload->>'title', 60), ''), 'A time capsule');
        sender_name := coalesce(nullif(capsule.payload->>'senderName', ''), 'A friend');

        if capsule.recipient_id = capsule.sender_id then
            push_body := 'Your capsule "' || capsule_title || '" from your past self is ready to open.';
        else
            push_body := sender_name || ' sealed "' || capsule_title || '" for you — it just unlocked.';
        end if;

        perform net.http_post(
            url := push_url,
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'apikey', service_key,
                'Authorization', 'Bearer ' || service_key
            ),
            body := jsonb_build_object(
                'recipients', jsonb_build_array(capsule.recipient_id::text),
                'title', 'Time capsule unlocked',
                'body', push_body,
                'threadId', 'capsules'
            ),
            timeout_milliseconds := 8000
        );
    end loop;
end;
$$;

-- Only the scheduler (postgres) should run this.
revoke execute on function public.notify_unlocked_capsules() from public, anon, authenticated;

-- Check for due capsules every minute. Re-scheduling under the same job name
-- replaces the previous schedule, so this file is safe to re-run.
select cron.schedule(
    'notify-unlocked-capsules',
    '* * * * *',
    $job$select public.notify_unlocked_capsules()$job$
);
