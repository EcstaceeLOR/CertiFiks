-- Issue #39: self-hosted partner keys bound to active tenant operators.
-- Keys are provisioned ONLY following independently authenticated maintainer
-- consent. No browser endpoints may mint privileged keys.
create table public.certifiks_partner_keys (
  key_id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.certifiks_organizations(organization_id),
  issued_by_user_id uuid not null references public.certifiks_auth_users(user_id),
  key_sha256 text not null unique check (key_sha256 ~ '^[0-9a-f]{64}$'),
  granted_scope text not null default 'bounties:read'
    check (granted_scope = 'bounties:read'),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  request_window timestamptz not null default now(),
  window_requests integer not null default 0 check (window_requests between 0 and 60),
  check (expires_at > created_at and expires_at <= created_at + interval '90 days')
);
create index certifiks_partner_org_keys on public.certifiks_partner_keys(organization_id, revoked_at);
alter table public.certifiks_partner_keys enable row level security;
revoke all on public.certifiks_partner_keys from public,anon,authenticated;
grant select on public.certifiks_partner_keys to service_role;

-- Atomic shared Postgres rate limit, no per-process limits or client-supplied
-- entitlement. Valid only for real finalized-only PUBLIC bounty views.
create function public.certifiks_authorize_partner_key(
  p_sha256 text,p_scope text
) returns boolean language plpgsql security definer set search_path = ''
as $$
declare item public.certifiks_partner_keys%rowtype;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'server role required'; end if;
  if p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$'
    or p_scope is distinct from 'bounties:read' then return false; end if;
  select * into item from public.certifiks_partner_keys
    where key_sha256=p_sha256 for update;
  if not found or item.revoked_at is not null or item.expires_at<=now()
    or item.granted_scope<>p_scope
    or not exists(select 1 from public.certifiks_auth_role_memberships m
      join public.certifiks_auth_users u on u.user_id=m.user_id
      where m.organization_id=item.organization_id
        and m.user_id=item.issued_by_user_id
        and m.revoked_at is null and u.disabled_at is null)
    or not exists(select 1 from public.certifiks_workspace_members w
      where w.organization_id=item.organization_id
        and w.user_id=item.issued_by_user_id and w.revoked_at is null)
  then return false; end if;

  if item.request_window<=now()-interval '1 minute' then
    update public.certifiks_partner_keys
      set request_window=now(),window_requests=1 where key_id=item.key_id;
  elsif item.window_requests>=60 then
    return false;
  else
    update public.certifiks_partner_keys
      set window_requests=window_requests+1 where key_id=item.key_id;
  end if;
  return true;
end;
$$;

-- Only a trusted authenticated operator workflow may call this function.
-- Revocation is immediate, including across multiple API replicas.
create function public.certifiks_revoke_partner_key(
  p_key_id uuid,p_org uuid,p_actor uuid
) returns boolean language plpgsql security definer set search_path = ''
as $$
declare affected integer;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'server role required'; end if;
  if not exists(select 1 from public.certifiks_workspace_members
    where organization_id=p_org and user_id=p_actor
      and role='owner' and revoked_at is null)
  then raise exception 'active owner authentication required'; end if;
  update public.certifiks_partner_keys set revoked_at=now()
    where key_id=p_key_id and organization_id=p_org and revoked_at is null;
  get diagnostics affected=row_count;
  return affected=1;
end;
$$;

revoke all on function public.certifiks_authorize_partner_key(text,text)
  from public,anon,authenticated;
revoke all on function public.certifiks_revoke_partner_key(uuid,uuid,uuid)
  from public,anon,authenticated;
grant execute on function public.certifiks_authorize_partner_key(text,text)
  to service_role;
grant execute on function public.certifiks_revoke_partner_key(uuid,uuid,uuid)
  to service_role;
