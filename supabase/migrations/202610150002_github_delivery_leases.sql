-- Lease-based single-consumer-per-delivery polling and bounded retries.
-- Service role only. Worker must re-fetch GitHub data and installation state
-- using a fresh narrowly scoped token; queue records are NEVER fix proofs.

create or replace function public.certifiks_claim_github_deliveries(
  p_batch integer default 10
) returns setof public.certifiks_github_deliveries
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'server-only action';
  end if;
  if p_batch is null or p_batch < 1 or p_batch > 50 then
    raise exception 'invalid batch size';
  end if;
  return query
  with candidate as (
    select d.delivery_id
      from public.certifiks_github_deliveries d
      join public.certifiks_github_installations i
        on i.installation_id = d.installation_id
     where i.revoked_at is null
       and d.attempts < 8
       and (
         (d.work_state in ('pending', 'retry') and d.next_attempt_at <= now())
         or (d.work_state = 'running' and d.leased_until < now())
       )
     order by d.ingested_at, d.delivery_id
     for update of d skip locked
     limit p_batch
  )
  update public.certifiks_github_deliveries d
     set work_state = 'running',
         attempts = d.attempts + 1,
         leased_until = now() + interval '2 minutes'
    from candidate
   where d.delivery_id = candidate.delivery_id
  returning d.*;
end;
$$;

create or replace function public.certifiks_finish_github_delivery(
  p_delivery_id uuid,
  p_attempt integer,
  p_success boolean,
  p_error_code text default null
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected integer;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'server-only action';
  end if;
  if p_delivery_id is null or p_attempt is null or p_attempt < 1 or p_success is null
     or (p_error_code is not null and p_error_code !~ '^[A-Z0-9_]{3,64}$') then
    raise exception 'invalid queue completion';
  end if;
  update public.certifiks_github_deliveries d
     set work_state = case
           when p_success then 'done'
           when d.attempts >= 8 then 'blocked'
           else 'retry'
         end,
         last_error_code = case when p_success then null
           else coalesce(p_error_code, 'DEPENDENCY_UNAVAILABLE') end,
         leased_until = null,
         next_attempt_at = case
           when p_success then now()
           else now() + make_interval(secs => least(3600, 10 * power(2, least(d.attempts, 8))::integer))
         end
   where d.delivery_id = p_delivery_id
     and d.attempts = p_attempt
     and d.work_state = 'running'
     and d.leased_until >= now()
     and exists (
       select 1 from public.certifiks_github_installations i
        where i.installation_id = d.installation_id
          and i.revoked_at is null
     );
  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;

revoke all on function public.certifiks_claim_github_deliveries(integer)
  from public, anon, authenticated;
revoke all on function public.certifiks_finish_github_delivery(uuid,integer,boolean,text)
  from public, anon, authenticated;
grant execute on function public.certifiks_claim_github_deliveries(integer)
  to service_role;
grant execute on function public.certifiks_finish_github_delivery(uuid,integer,boolean,text)
  to service_role;

-- Note: lease fencing by (delivery_id, attempt) prevents an expired worker
-- from acknowledging the next attempt. Out-of-order GitHub events must only
-- trigger an API re-read; never infer latest PR state from delivery ordering.
