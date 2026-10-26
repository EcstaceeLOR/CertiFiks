-- Issue #28: durable tenant-scoped verifier work queue. No automatic payout.
-- All worker interaction must be through backend service role; untrusted
-- developer code MUST NOT receive this credential or a DB connection.
create table public.certifiks_verification_jobs (
  job_id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  bounty_id uuid not null,
  attempt_id uuid not null,
  manifest_digest text not null check (manifest_digest ~ '^0x[0-9a-f]{64}$'),
  stage text not null check (stage in
    ('checkout','baseline','candidate','regression','review','synchronize','notify')),
  status text not null default 'pending' check (status in
    ('pending','running','retry','succeeded','dead_letter','cancelled')),
  attempts integer not null default 0 check (attempts between 0 and 8),
  max_attempts integer not null default 8 check (max_attempts between 1 and 8),
  lease_id uuid,
  lease_until timestamptz,
  retry_after timestamptz not null default now(),
  expires_at timestamptz not null default (now()+interval '7 days'),
  error_code text check(error_code is null or error_code ~ '^[A-Z0-9_]{3,64}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id,bounty_id,attempt_id)
    references public.certifiks_attempts(organization_id,bounty_id,attempt_id),
  unique (organization_id,bounty_id,attempt_id,manifest_digest,stage),
  check ((status = 'running') = (lease_id is not null and lease_until is not null))
);

create index certifiks_verify_queue_ready
  on public.certifiks_verification_jobs(retry_after,created_at,job_id)
  where status in ('pending','retry');
create index certifiks_verify_queue_orphaned
  on public.certifiks_verification_jobs(lease_until)
  where status = 'running';

alter table public.certifiks_verification_jobs enable row level security;
revoke all on public.certifiks_verification_jobs from public,anon,authenticated;
grant select on public.certifiks_verification_jobs to service_role;

create function public.certifiks_enqueue_verification_stage(
  p_org uuid, p_bounty uuid, p_attempt uuid, p_manifest text, p_stage text
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare expected_manifest text; result_id uuid;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'server role required'; end if;
  if p_stage not in
    ('checkout','baseline','candidate','regression','review','synchronize','notify')
    or p_manifest !~ '^0x[0-9a-f]{64}$'
  then raise exception 'invalid committed stage'; end if;

  select b.funded_manifest_digest into expected_manifest
    from public.certifiks_bounties b
    join public.certifiks_attempts a
      on a.organization_id=b.organization_id and a.bounty_id=b.bounty_id
    where b.organization_id=p_org and b.bounty_id=p_bounty
      and a.attempt_id=p_attempt and b.state not in ('blocked','refunded','settled');
  if expected_manifest is null or expected_manifest <> p_manifest
  then raise exception 'attempt does not match the funded manifest and tenant'; end if;

  insert into public.certifiks_verification_jobs (
    organization_id,bounty_id,attempt_id,manifest_digest,stage
  ) values (p_org,p_bounty,p_attempt,p_manifest,p_stage)
    on conflict (organization_id,bounty_id,attempt_id,manifest_digest,stage)
    do nothing;
  select job_id into result_id
    from public.certifiks_verification_jobs
    where organization_id=p_org and bounty_id=p_bounty and
      attempt_id=p_attempt and manifest_digest=p_manifest and stage=p_stage;
  if result_id is null then raise exception 'could not resolve idempotent job'; end if;
  return result_id;
end;
$$;

create function public.certifiks_claim_verification_jobs(p_limit integer default 5)
returns setof public.certifiks_verification_jobs
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then raise exception 'server role required'; end if;
  if p_limit is null or p_limit not between 1 and 25
  then raise exception 'invalid queue batch size'; end if;
  return query
  with candidates as (
    select j.job_id from public.certifiks_verification_jobs j
    join public.certifiks_bounties b
      on b.organization_id=j.organization_id and b.bounty_id=j.bounty_id
    where
      (j.status in ('pending','retry') and j.retry_after <= now()
       or j.status='running' and j.lease_until < now())
      and j.attempts < j.max_attempts and j.expires_at > now()
      and b.state not in ('blocked','refunded','settled')
    order by j.created_at,j.job_id
    for update of j skip locked limit p_limit
  )
  update public.certifiks_verification_jobs j
    set status='running',attempts=j.attempts+1,
      lease_id=gen_random_uuid(),
      lease_until=now()+interval '2 minutes',
      updated_at=now()
    from candidates
    where j.job_id=candidates.job_id
    returning j.*;
end;
$$;

-- Attempt-fenced completion ensures expired worker never acknowledges retry.
create function public.certifiks_complete_verification_job(
  p_job_id uuid, p_lease uuid, p_attempt integer,
  p_success boolean, p_error_code text default null
) returns boolean language plpgsql security definer set search_path = ''
as $$
declare affected integer;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'server role required'; end if;
  if p_job_id is null or p_lease is null or p_attempt is null or
    p_attempt < 1 or p_success is null or
    (p_error_code is not null and p_error_code !~ '^[A-Z0-9_]{3,64}$')
  then raise exception 'invalid verification completion'; end if;
  update public.certifiks_verification_jobs j
    set status=case when p_success then 'succeeded'
                    when j.attempts >= j.max_attempts then 'dead_letter'
                    else 'retry' end,
      error_code=case when p_success then null
        else coalesce(p_error_code,'RUNNER_UNAVAILABLE') end,
      retry_after=case when p_success then now()
        else now() + make_interval(secs =>
          least(3600,(15*power(2::numeric,least(j.attempts,8)))::integer)) end,
      lease_id=null, lease_until=null,updated_at=now()
    where j.job_id=p_job_id and j.lease_id=p_lease and
      j.attempts=p_attempt and j.status='running' and j.lease_until > now();
  get diagnostics affected=row_count;
  return affected=1;
end;
$$;

create function public.certifiks_heartbeat_verification_job(
  p_job_id uuid,p_lease uuid,p_attempt integer
) returns boolean language plpgsql security definer set search_path = ''
as $$
declare affected integer;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'server role required'; end if;
  update public.certifiks_verification_jobs j
    set lease_until=least(now()+interval '2 minutes',
          j.created_at+interval '15 minutes'),
      updated_at=now()
    where j.job_id=p_job_id and j.lease_id=p_lease and
      j.attempts=p_attempt and j.status='running'
      and j.lease_until > now() and j.created_at+interval '15 minutes' > now();
  get diagnostics affected=row_count;
  return affected=1;
end;
$$;

create function public.certifiks_cancel_verification_job(
  p_job_id uuid,p_error_code text
) returns boolean language plpgsql security definer set search_path = ''
as $$
declare affected integer;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'server role required'; end if;
  if p_error_code is null or p_error_code !~ '^[A-Z0-9_]{3,64}$'
  then raise exception 'cancellation reason required'; end if;
  update public.certifiks_verification_jobs
    set status='cancelled',error_code=p_error_code,lease_id=null,
      lease_until=null,updated_at=now()
    where job_id=p_job_id and status in ('pending','retry','running');
  get diagnostics affected=row_count;
  return affected=1;
end;
$$;

revoke all on function public.certifiks_enqueue_verification_stage(uuid,uuid,uuid,text,text)
  from public,anon,authenticated;
revoke all on function public.certifiks_claim_verification_jobs(integer)
  from public,anon,authenticated;
revoke all on function public.certifiks_complete_verification_job(uuid,uuid,integer,boolean,text)
  from public,anon,authenticated;
revoke all on function public.certifiks_heartbeat_verification_job(uuid,uuid,integer)
  from public,anon,authenticated;
revoke all on function public.certifiks_cancel_verification_job(uuid,text)
  from public,anon,authenticated;
grant execute on function public.certifiks_enqueue_verification_stage(uuid,uuid,uuid,text,text)
  to service_role;
grant execute on function public.certifiks_claim_verification_jobs(integer)
  to service_role;
grant execute on function public.certifiks_complete_verification_job(uuid,uuid,integer,boolean,text)
  to service_role;
grant execute on function public.certifiks_heartbeat_verification_job(uuid,uuid,integer)
  to service_role;
grant execute on function public.certifiks_cancel_verification_job(uuid,text)
  to service_role;
