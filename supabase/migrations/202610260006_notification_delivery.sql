-- Issue #29: persisted, tenant-bound notification identities and consent.
-- This is NOT a claim of real email/GitHub delivery or logged-in UI wiring.
alter table public.certifiks_notifications
  add column idempotency_digest text check (
    idempotency_digest is null or idempotency_digest ~ '^[0-9a-f]{64}$'
  );
alter table public.certifiks_notifications
  add column target_bounty_id uuid;
alter table public.certifiks_notifications
  add column read_at timestamptz;
alter table public.certifiks_notifications
  add constraint certifiks_notification_target_tenant
  foreign key (organization_id,target_bounty_id)
    references public.certifiks_bounties(organization_id,bounty_id);

create unique index certifiks_notification_logical_dedupe
  on public.certifiks_notifications(organization_id,user_id,idempotency_digest)
  where idempotency_digest is not null;
create index certifiks_notification_recipient_inbox
  on public.certifiks_notifications(organization_id,user_id,created_at desc,notification_id);

create table public.certifiks_notification_preferences (
  organization_id uuid not null references public.certifiks_organizations(organization_id),
  user_id uuid not null references public.certifiks_auth_users(user_id),
  in_app_enabled boolean not null default true,
  email_opt_in boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (organization_id,user_id)
);
alter table public.certifiks_notification_preferences enable row level security;
revoke all on public.certifiks_notification_preferences from public,anon,authenticated;
grant select on public.certifiks_notification_preferences to service_role;

create table public.certifiks_notification_outbox (
  notification_id uuid not null references public.certifiks_notifications(notification_id),
  channel text not null check (channel in ('in_app','email')),
  status text not null default 'queued' check (
    status in ('queued','delivering','delivered','retry','blocked','cancelled')
  ),
  delivery_idempotency_key text not null unique check (
    delivery_idempotency_key ~ '^[0-9a-f]{64}$'
  ),
  attempts integer not null default 0 check (attempts between 0 and 5),
  lease_id uuid,
  lease_until timestamptz,
  next_attempt_at timestamptz not null default now(),
  external_receipt_id text check (external_receipt_id is null
    or length(external_receipt_id) between 6 and 255),
  error_code text check (error_code is null or error_code ~ '^[A-Z0-9_]{3,64}$'),
  created_at timestamptz not null default now(),
  primary key (notification_id,channel),
  check ((status='delivering') = (lease_id is not null and lease_until is not null))
);
create index certifiks_notification_delivery_ready
  on public.certifiks_notification_outbox(next_attempt_at,notification_id)
  where status in ('queued','retry');
alter table public.certifiks_notification_outbox enable row level security;
revoke all on public.certifiks_notification_outbox from public,anon,authenticated;
grant select on public.certifiks_notification_outbox to service_role;

create function public.certifiks_enqueue_notification(
  p_org uuid,p_recipient uuid,p_target_bounty uuid,
  p_kind text,p_digest text,p_idempotency text
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare result_id uuid; current_digest text; opted boolean;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'server role required'; end if;
  if p_kind not in (
    'application_received','assignment','submission','run_result',
    'review_required','dispute_deadline','payout_available',
    'verification_failed','refund'
  ) or p_digest !~ '^0x[0-9a-f]{64}$' or
    p_idempotency !~ '^[0-9a-f]{64}$'
  then raise exception 'invalid notification event'; end if;
  if not exists(select 1 from public.certifiks_auth_role_memberships m
     join public.certifiks_auth_users u on u.user_id=m.user_id
     where m.user_id=p_recipient and m.organization_id=p_org and
       m.revoked_at is null and u.disabled_at is null)
  then raise exception 'recipient is not an active tenant member'; end if;
  if p_target_bounty is not null and not exists(
    select 1 from public.certifiks_bounties
    where organization_id=p_org and bounty_id=p_target_bounty)
  then raise exception 'notification target outside tenant'; end if;

  insert into public.certifiks_notifications(
    organization_id,user_id,kind,payload_digest,idempotency_digest,target_bounty_id
  ) values(p_org,p_recipient,p_kind,p_digest,p_idempotency,p_target_bounty)
  on conflict do nothing;

  select notification_id,payload_digest into result_id,current_digest
    from public.certifiks_notifications
    where organization_id=p_org and user_id=p_recipient and
      idempotency_digest=p_idempotency;
  if result_id is null or current_digest<>p_digest
  then raise exception 'notification idempotency content conflict'; end if;

  select coalesce(p.in_app_enabled,true) into opted
    from public.certifiks_notification_preferences p
    where p.organization_id=p_org and p.user_id=p_recipient;
  if opted is distinct from false then
    insert into public.certifiks_notification_outbox(
      notification_id,channel,delivery_idempotency_key
    ) values(result_id,'in_app',
      encode(sha256(convert_to(result_id::text||':in_app','utf8')),'hex'))
    on conflict do nothing;
  end if;
  -- Email deliberately stays disabled until a verified recipient address and
  -- a real provider idempotency API have been integrated, regardless of opt-in.
  return result_id;
end;
$$;

-- Read is a backend-only action, requires independently authenticated session
-- ownership before the server can pass these arguments.
create function public.certifiks_mark_notification_read(
  p_org uuid,p_recipient uuid,p_notification uuid
) returns boolean language plpgsql security definer set search_path = ''
as $$
declare affected integer;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'server role required'; end if;
  update public.certifiks_notifications set read_at=coalesce(read_at,now())
    where notification_id=p_notification and organization_id=p_org
      and user_id=p_recipient;
  get diagnostics affected=row_count;
  return affected=1;
end;
$$;

revoke all on function public.certifiks_enqueue_notification(
  uuid,uuid,uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.certifiks_mark_notification_read(
  uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.certifiks_enqueue_notification(
  uuid,uuid,uuid,text,text,text) to service_role;
grant execute on function public.certifiks_mark_notification_read(
  uuid,uuid,uuid) to service_role;
