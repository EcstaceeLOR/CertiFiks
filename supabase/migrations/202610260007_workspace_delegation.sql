-- Issue #30: bounded database workspace delegation.
-- Workspace permission NEVER transfers sponsor wallet or chain custody rights.
create table public.certifiks_workspaces (
  organization_id uuid primary key references public.certifiks_organizations(organization_id),
  owner_user_id uuid not null references public.certifiks_auth_users(user_id),
  archived_at timestamptz,
  created_at timestamptz not null default now()
);
create table public.certifiks_workspace_members (
  organization_id uuid not null references public.certifiks_workspaces(organization_id),
  user_id uuid not null references public.certifiks_auth_users(user_id),
  role text not null check (role in ('owner','billing','maintainer','reviewer','viewer')),
  joined_at timestamptz not null default now(),
  revoked_at timestamptz,
  primary key (organization_id,user_id)
);
create unique index certifiks_one_workspace_owner
  on public.certifiks_workspace_members(organization_id)
  where role='owner' and revoked_at is null;

create table public.certifiks_workspace_invites (
  invitation_id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.certifiks_workspaces(organization_id),
  invited_user_id uuid not null references public.certifiks_auth_users(user_id),
  invited_by_user_id uuid not null references public.certifiks_auth_users(user_id),
  role text not null check (role in ('billing','maintainer','reviewer','viewer')),
  token_digest text not null unique check (token_digest ~ '^[0-9a-f]{64}$'),
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  check (expires_at>issued_at and expires_at<=issued_at+interval '7 days')
);
create unique index certifiks_workspace_pending_invite
  on public.certifiks_workspace_invites(organization_id,invited_user_id,role)
  where accepted_at is null and revoked_at is null;

create table public.certifiks_workspace_role_events (
  event_id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.certifiks_organizations(organization_id),
  actor_user_id uuid not null references public.certifiks_auth_users(user_id),
  target_user_id uuid not null references public.certifiks_auth_users(user_id),
  action text not null check (action in (
    'workspace_created','invite_issued','invite_accepted',
    'member_revoked','owner_transferred','invite_revoked'
  )),
  role text not null check (role in ('owner','billing','maintainer','reviewer','viewer')),
  created_at timestamptz not null default now()
);
create trigger certifiks_guard_workspace_role_events
  before update or delete on public.certifiks_workspace_role_events
  for each row execute function public.certifiks_reject_immutable_mutation();

create table public.certifiks_workspace_repo_policies (
  organization_id uuid not null,
  repository_id bigint not null,
  policy_digest text not null check (policy_digest ~ '^0x[0-9a-f]{64}$'),
  last_reviewed_at timestamptz not null default now(),
  primary key (organization_id,repository_id),
  foreign key (organization_id,repository_id)
    references public.certifiks_repositories(organization_id,repository_id)
);

do $$
declare entity_name text;
begin
  foreach entity_name in array array[
    'certifiks_workspaces','certifiks_workspace_members',
    'certifiks_workspace_invites','certifiks_workspace_role_events',
    'certifiks_workspace_repo_policies'
  ] loop
    execute format('alter table public.%I enable row level security',entity_name);
    execute format('revoke all on public.%I from public,anon,authenticated',entity_name);
    execute format('grant select on public.%I to service_role',entity_name);
  end loop;
end;
$$;

-- Caller must bind actor UUID to a verified wallet/GitHub session BEFORE
-- invoking service role functions. Never expose these RPCs to browsers.
create function public.certifiks_create_workspace(
  p_org uuid,p_owner uuid
) returns boolean language plpgsql security definer set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then raise exception 'server role required'; end if;
  if not exists(select 1 from public.certifiks_auth_users
      where user_id=p_owner and disabled_at is null)
  then raise exception 'owner identity unavailable'; end if;
  insert into public.certifiks_workspaces(organization_id,owner_user_id)
    values(p_org,p_owner);
  insert into public.certifiks_workspace_members(organization_id,user_id,role)
    values(p_org,p_owner,'owner');
  insert into public.certifiks_workspace_role_events(
    organization_id,actor_user_id,target_user_id,action,role)
    values(p_org,p_owner,p_owner,'workspace_created','owner');
  return true;
end;
$$;

create function public.certifiks_invite_workspace_member(
  p_org uuid,p_actor uuid,p_target uuid,p_role text,
  p_token_digest text,p_expires timestamptz
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare owner_id uuid; inviter_role text; new_id uuid;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'server role required'; end if;
  select owner_user_id into owner_id from public.certifiks_workspaces
    where organization_id=p_org and archived_at is null for update;
  select role into inviter_role from public.certifiks_workspace_members
    where organization_id=p_org and user_id=p_actor and revoked_at is null;
  if owner_id is null or (
      p_actor<>owner_id and not (inviter_role='maintainer' and p_role='viewer'))
     or p_role not in ('billing','maintainer','reviewer','viewer')
     or p_actor=p_target
     or p_token_digest !~ '^[0-9a-f]{64}$'
     or p_expires is null or p_expires<=now() or p_expires>now()+interval '7 days'
     or not exists(select 1 from public.certifiks_auth_users
         where user_id=p_target and disabled_at is null)
  then raise exception 'workspace invite denied'; end if;
  insert into public.certifiks_workspace_invites(
    organization_id,invited_user_id,invited_by_user_id,
    role,token_digest,expires_at)
  values(p_org,p_target,p_actor,p_role,p_token_digest,p_expires)
  returning invitation_id into new_id;
  insert into public.certifiks_workspace_role_events(
    organization_id,actor_user_id,target_user_id,action,role)
  values(p_org,p_actor,p_target,'invite_issued',p_role);
  return new_id;
end;
$$;

create function public.certifiks_accept_workspace_invite(
  p_invitation uuid,p_authenticated_user uuid,p_token_digest text
) returns boolean language plpgsql security definer set search_path = ''
as $$
declare invitation public.certifiks_workspace_invites%rowtype;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'server role required'; end if;
  select * into invitation from public.certifiks_workspace_invites
    where invitation_id=p_invitation for update;
  if not found or invitation.invited_user_id<>p_authenticated_user or
    invitation.token_digest<>p_token_digest or invitation.accepted_at is not null
    or invitation.revoked_at is not null or invitation.expires_at<=now()
    or not exists(select 1 from public.certifiks_workspaces
      where organization_id=invitation.organization_id and archived_at is null)
    or exists(select 1 from public.certifiks_workspace_members
      where organization_id=invitation.organization_id and user_id=p_authenticated_user
        and role='owner' and revoked_at is null)
  then raise exception 'invitation not valid for authenticated user'; end if;
  insert into public.certifiks_workspace_members(organization_id,user_id,role,revoked_at)
    values(invitation.organization_id,p_authenticated_user,invitation.role,null)
    on conflict (organization_id,user_id) do update
      set role=excluded.role,revoked_at=null,joined_at=now();
  update public.certifiks_workspace_invites set accepted_at=now()
    where invitation_id=p_invitation;
  insert into public.certifiks_workspace_role_events(
    organization_id,actor_user_id,target_user_id,action,role)
  values(invitation.organization_id,p_authenticated_user,p_authenticated_user,
    'invite_accepted',invitation.role);
  return true;
end;
$$;

create function public.certifiks_revoke_workspace_member(
  p_org uuid,p_owner uuid,p_target uuid
) returns boolean language plpgsql security definer set search_path = ''
as $$
declare old_role text; affected integer;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'server role required'; end if;
  perform 1 from public.certifiks_workspaces
    where organization_id=p_org and owner_user_id=p_owner
      and archived_at is null for update;
  if not found or p_owner=p_target then raise exception 'owner delegation check failed'; end if;
  select role into old_role from public.certifiks_workspace_members
    where organization_id=p_org and user_id=p_target and revoked_at is null;
  if old_role is null or old_role='owner' then raise exception 'member not revocable'; end if;
  update public.certifiks_workspace_members set revoked_at=now()
    where organization_id=p_org and user_id=p_target and revoked_at is null;
  get diagnostics affected=row_count;
  update public.certifiks_workspace_invites set revoked_at=now()
    where organization_id=p_org and invited_user_id=p_target
      and accepted_at is null and revoked_at is null;
  insert into public.certifiks_workspace_role_events(
    organization_id,actor_user_id,target_user_id,action,role)
  values(p_org,p_owner,p_target,'member_revoked',old_role);
  return affected=1;
end;
$$;

create function public.certifiks_transfer_workspace_owner(
  p_org uuid,p_old_owner uuid,p_new_owner uuid
) returns boolean language plpgsql security definer set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then raise exception 'server role required'; end if;
  perform 1 from public.certifiks_workspaces
    where organization_id=p_org and owner_user_id=p_old_owner
      and archived_at is null for update;
  if not found or p_old_owner=p_new_owner or not exists (
    select 1 from public.certifiks_workspace_members
      where organization_id=p_org and user_id=p_new_owner and revoked_at is null
  ) then raise exception 'owner transfer requires active approved successor'; end if;
  update public.certifiks_workspace_members set role='maintainer'
    where organization_id=p_org and user_id=p_old_owner and role='owner';
  update public.certifiks_workspace_members set role='owner'
    where organization_id=p_org and user_id=p_new_owner and revoked_at is null;
  update public.certifiks_workspaces set owner_user_id=p_new_owner
    where organization_id=p_org;
  insert into public.certifiks_workspace_role_events(
    organization_id,actor_user_id,target_user_id,action,role)
  values(p_org,p_old_owner,p_new_owner,'owner_transferred','owner');
  return true;
end;
$$;

revoke all on function public.certifiks_create_workspace(uuid,uuid) from public,anon,authenticated;
revoke all on function public.certifiks_invite_workspace_member(uuid,uuid,uuid,text,text,timestamptz)
  from public,anon,authenticated;
revoke all on function public.certifiks_accept_workspace_invite(uuid,uuid,text)
  from public,anon,authenticated;
revoke all on function public.certifiks_revoke_workspace_member(uuid,uuid,uuid)
  from public,anon,authenticated;
revoke all on function public.certifiks_transfer_workspace_owner(uuid,uuid,uuid)
  from public,anon,authenticated;
grant execute on function public.certifiks_create_workspace(uuid,uuid) to service_role;
grant execute on function public.certifiks_invite_workspace_member(uuid,uuid,uuid,text,text,timestamptz)
  to service_role;
grant execute on function public.certifiks_accept_workspace_invite(uuid,uuid,text)
  to service_role;
grant execute on function public.certifiks_revoke_workspace_member(uuid,uuid,uuid) to service_role;
grant execute on function public.certifiks_transfer_workspace_owner(uuid,uuid,uuid) to service_role;
