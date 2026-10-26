-- GitHub delivery journal and transactional ingestion RPC.
-- Repaired prior corrupted predeployment migration during Issue #24 testing.
-- This schema stores only signed webhook metadata, not payloads or secrets.

create table if not exists public.certifiks_github_installations (
  installation_id bigint primary key check (installation_id > 0),
  revoked_at timestamptz,
  last_delivery_id uuid,
  updated_at timestamptz not null default now()
);

create table if not exists public.certifiks_github_deliveries (
  delivery_id uuid primary key,
  body_sha256 text not null unique check (body_sha256 ~ '^[0-9a-f]{64}$'),
  event_type text not null check (
    event_type in ('installation','installation_repositories','pull_request')
  ),
  action text not null check (action ~ '^[a-z_]{3,48}$'),
  installation_id bigint not null check (installation_id > 0),
  repository_id bigint check (repository_id > 0),
  received_at timestamptz not null,
  ingested_at timestamptz not null default now(),
  work_state text not null default 'pending' check (
    work_state in ('pending','running','done','blocked','retry')
  ),
  attempts integer not null default 0 check (attempts >= 0),
  next_attempt_at timestamptz not null default now(),
  leased_until timestamptz,
  last_error_code text
);

create index if not exists certifiks_github_pending_queue
  on public.certifiks_github_deliveries(next_attempt_at,ingested_at,delivery_id)
  where work_state in ('pending','retry');

alter table public.certifiks_github_installations enable row level security;
alter table public.certifiks_github_deliveries enable row level security;
revoke all on public.certifiks_github_installations from public,anon,authenticated;
revoke all on public.certifiks_github_deliveries from public,anon,authenticated;
grant select,insert,update,delete on public.certifiks_github_installations to service_role;
grant select,insert,update,delete on public.certifiks_github_deliveries to service_role;

create or replace function public.certifiks_ingest_github_event(
  p_delivery_id uuid,
  p_body_sha256 text,
  p_event_type text,
  p_action text,
  p_installation_id bigint,
  p_repository_id bigint,
  p_received_at timestamptz
) returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  inserted_count integer;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'server-only action';
  end if;
  if p_delivery_id is null or
     p_body_sha256 is null or p_body_sha256 !~ '^[0-9a-f]{64}$' or
     p_event_type is null or p_event_type not in (
       'installation','installation_repositories','pull_request'
     ) or
     p_action is null or p_action !~ '^[a-z_]{3,48}$' or
     p_installation_id is null or p_installation_id <= 0 or
     p_received_at is null or
     p_received_at > now() + interval '5 minutes' or
     p_received_at < now() - interval '1 day' or
     (p_repository_id is not null and p_repository_id <= 0)
  then
    raise exception 'invalid authenticated GitHub delivery';
  end if;

  insert into public.certifiks_github_deliveries (
    delivery_id,body_sha256,event_type,action,installation_id,repository_id,received_at
  ) values (
    p_delivery_id,p_body_sha256,p_event_type,p_action,p_installation_id,p_repository_id,p_received_at
  ) on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    return 'duplicate';
  end if;

  insert into public.certifiks_github_installations(installation_id)
    values (p_installation_id)
    on conflict (installation_id) do nothing;

  -- Revocation is monotonic. Unsuspend/reinstall needs authenticated current
  -- GitHub installation proof, never an out-of-order webhook alone.
  if p_event_type = 'installation' and p_action in ('deleted','suspend') then
    update public.certifiks_github_installations
       set revoked_at = now(),
           last_delivery_id = p_delivery_id,
           updated_at = now()
     where installation_id = p_installation_id;
    update public.certifiks_github_deliveries
       set work_state = 'blocked',last_error_code = 'INSTALLATION_REVOKED'
     where installation_id = p_installation_id
       and work_state in ('pending','retry');
  end if;
  return 'accepted';
end;
$$;

revoke all on function public.certifiks_ingest_github_event(
  uuid,text,text,text,bigint,bigint,timestamptz
) from public,anon,authenticated;
grant execute on function public.certifiks_ingest_github_event(
  uuid,text,text,text,bigint,bigint,timestamptz
) to service_role;
