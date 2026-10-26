-- Issue #35: private append-only dispute evidence timeline (NOT adjudication).
-- Application must independently authenticate actor user_id before invoking RPC.
create table public.certifiks_dispute_adjudicators (
  organization_id uuid not null,
  dispute_id uuid not null,
  arbitrator_user_id uuid not null references public.certifiks_auth_users(user_id),
  assigned_at timestamptz not null default now(),
  revoked_at timestamptz,
  primary key (organization_id,dispute_id,arbitrator_user_id),
  foreign key (organization_id,dispute_id)
    references public.certifiks_disputes(organization_id,dispute_id)
);
create table public.certifiks_dispute_timeline (
  timeline_id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  dispute_id uuid not null,
  actor_user_id uuid not null references public.certifiks_auth_users(user_id),
  kind text not null check (kind in
    ('case_opened','party_response','supporting_evidence','arbitrator_note')),
  reason_digest text not null check(reason_digest ~ '^0x[0-9a-f]{64}$'),
  artifact_digest text check(
    artifact_digest is null or artifact_digest ~ '^0x[0-9a-f]{64}$'),
  event_idempotency text not null check(event_idempotency ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  foreign key (organization_id,dispute_id)
    references public.certifiks_disputes(organization_id,dispute_id),
  unique(organization_id,dispute_id,event_idempotency)
);
create index certifiks_dispute_timeline_view
 on public.certifiks_dispute_timeline(organization_id,dispute_id,created_at,timeline_id);
create unique index certifiks_dispute_one_opening_event
  on public.certifiks_dispute_timeline(organization_id,dispute_id)
  where kind='case_opened';

create trigger certifiks_guard_dispute_timeline
before update or delete on public.certifiks_dispute_timeline
for each row execute function public.certifiks_reject_immutable_mutation();

alter table public.certifiks_dispute_adjudicators enable row level security;
alter table public.certifiks_dispute_timeline enable row level security;
revoke all on public.certifiks_dispute_adjudicators from public,anon,authenticated;
revoke all on public.certifiks_dispute_timeline from public,anon,authenticated;
grant select on public.certifiks_dispute_adjudicators to service_role;
grant select on public.certifiks_dispute_timeline to service_role;

-- Does not grant access merely because a user claims "arbitrator" role;
-- role AND per-case assignment AND no conflict are all required.
create function public.certifiks_can_read_dispute(
  p_org uuid,p_dispute uuid,p_actor uuid
) returns boolean language sql stable security definer set search_path = ''
as $$
select auth.role() = 'service_role' and exists (
 select 1 from public.certifiks_disputes d
 join public.certifiks_bounties b
  on b.organization_id=d.organization_id and b.bounty_id=d.bounty_id
 where d.organization_id=p_org and d.dispute_id=p_dispute
 and (
  d.opened_by=p_actor
  or b.sponsor_user_id=p_actor
  or exists (
    select 1 from public.certifiks_assignments ass
    join public.certifiks_applications a
     on a.organization_id=ass.organization_id
      and a.application_id=ass.application_id
      and a.bounty_id=ass.bounty_id
    where ass.organization_id=p_org and ass.bounty_id=d.bounty_id
     and a.developer_user_id=p_actor
  )
  or (
    exists (select 1 from public.certifiks_dispute_adjudicators arb
      join public.certifiks_auth_role_memberships m
        on m.organization_id=arb.organization_id and m.user_id=arb.arbitrator_user_id
        and m.role='arbitrator' and m.revoked_at is null
      join public.certifiks_auth_users u
        on u.user_id=arb.arbitrator_user_id and u.disabled_at is null
      where arb.organization_id=p_org and arb.dispute_id=p_dispute
        and arb.arbitrator_user_id=p_actor and arb.revoked_at is null)
    and b.sponsor_user_id<>p_actor and d.opened_by<>p_actor
    and not exists (
      select 1 from public.certifiks_assignments ass
      join public.certifiks_applications a
        on a.organization_id=ass.organization_id
          and a.bounty_id=ass.bounty_id and a.application_id=ass.application_id
      where ass.organization_id=p_org and ass.bounty_id=d.bounty_id
        and a.developer_user_id=p_actor
    )
  )
 )
);
$$;

create function public.certifiks_record_dispute_timeline(
  p_org uuid,p_dispute uuid,p_actor uuid,p_kind text,
  p_reason text,p_artifact text,p_idempotency text
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare result_id uuid; original public.certifiks_dispute_timeline%rowtype;
        case_state text; case_opener uuid; is_assigned_arb boolean;
        is_case_party boolean;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'server role required'; end if;
  select d.state,d.opened_by into case_state,case_opener
    from public.certifiks_disputes d
    where d.organization_id=p_org and d.dispute_id=p_dispute for update;
  if case_state is null or case_state in ('resolved','expired')
    or not public.certifiks_can_read_dispute(p_org,p_dispute,p_actor)
    or p_kind not in ('case_opened','party_response','supporting_evidence','arbitrator_note')
    or p_reason !~ '^0x[0-9a-f]{64}$'
    or p_idempotency !~ '^[0-9a-f]{64}$'
    or (p_artifact is not null and p_artifact !~ '^0x[0-9a-f]{64}$')
  then raise exception 'unauthorized or immutable dispute update'; end if;
  select exists (
    select 1 from public.certifiks_dispute_adjudicators arb
    join public.certifiks_auth_role_memberships m
      on m.organization_id=arb.organization_id
      and m.user_id=arb.arbitrator_user_id
      and m.role='arbitrator' and m.revoked_at is null
    join public.certifiks_disputes d
      on d.organization_id=arb.organization_id and d.dispute_id=arb.dispute_id
    join public.certifiks_bounties b
      on b.organization_id=d.organization_id and b.bounty_id=d.bounty_id
    where arb.organization_id=p_org and arb.dispute_id=p_dispute
      and arb.arbitrator_user_id=p_actor and arb.revoked_at is null
      and d.opened_by<>p_actor and b.sponsor_user_id<>p_actor
      and not exists (
        select 1 from public.certifiks_assignments ass
        join public.certifiks_applications a
          on a.organization_id=ass.organization_id
            and a.bounty_id=ass.bounty_id and a.application_id=ass.application_id
        where ass.organization_id=p_org and ass.bounty_id=d.bounty_id
          and a.developer_user_id=p_actor
      )
  ) into is_assigned_arb;
  select exists(
    select 1 from public.certifiks_disputes d
    join public.certifiks_bounties b
      on b.organization_id=d.organization_id and b.bounty_id=d.bounty_id
    where d.organization_id=p_org and d.dispute_id=p_dispute
      and (d.opened_by=p_actor or b.sponsor_user_id=p_actor
       or exists (
        select 1 from public.certifiks_assignments ass
        join public.certifiks_applications a
          on a.organization_id=ass.organization_id and a.bounty_id=ass.bounty_id
            and a.application_id=ass.application_id
        where ass.organization_id=p_org and ass.bounty_id=d.bounty_id
          and a.developer_user_id=p_actor))
  ) into is_case_party;
  if (p_kind='case_opened' and p_actor<>case_opener)
    or (p_kind='party_response' and (not is_case_party or p_actor=case_opener))
    or (p_kind='supporting_evidence' and not is_case_party)
    or (p_kind='arbitrator_note' and not is_assigned_arb)
  then raise exception 'dispute actor not entitled to this event kind'; end if;

  insert into public.certifiks_dispute_timeline (
    organization_id,dispute_id,actor_user_id,kind,
    reason_digest,artifact_digest,event_idempotency
  ) values (
    p_org,p_dispute,p_actor,p_kind,p_reason,p_artifact,p_idempotency
  ) on conflict (organization_id,dispute_id,event_idempotency) do nothing;
  select * into original from public.certifiks_dispute_timeline
   where organization_id=p_org and dispute_id=p_dispute
     and event_idempotency=p_idempotency;
  if original.timeline_id is null or original.actor_user_id<>p_actor
    or original.kind<>p_kind or original.reason_digest<>p_reason
    or original.artifact_digest is distinct from p_artifact
  then raise exception 'conflicting dispute event replay'; end if;
  result_id:=original.timeline_id;
  return result_id;
end;
$$;

create function public.certifiks_read_dispute_timeline(
  p_org uuid,p_dispute uuid,p_actor uuid,p_limit integer default 25
) returns setof public.certifiks_dispute_timeline
language plpgsql stable security definer set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' or p_limit is null
    or p_limit not between 1 and 50
    or not public.certifiks_can_read_dispute(p_org,p_dispute,p_actor)
  then raise exception 'private dispute inaccessible'; end if;
  return query select * from public.certifiks_dispute_timeline t
    where t.organization_id=p_org and t.dispute_id=p_dispute
    order by t.created_at,t.timeline_id limit p_limit;
end;
$$;

revoke all on function public.certifiks_can_read_dispute(uuid,uuid,uuid)
  from public,anon,authenticated;
revoke all on function public.certifiks_record_dispute_timeline(
  uuid,uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function public.certifiks_read_dispute_timeline(
  uuid,uuid,uuid,integer) from public,anon,authenticated;
grant execute on function public.certifiks_can_read_dispute(uuid,uuid,uuid) to service_role;
grant execute on function public.certifiks_record_dispute_timeline(
  uuid,uuid,uuid,text,text,text,text) to service_role;
grant execute on function public.certifiks_read_dispute_timeline(
  uuid,uuid,uuid,integer) to service_role;
