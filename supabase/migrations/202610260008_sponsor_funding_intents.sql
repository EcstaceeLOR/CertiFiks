-- Issue #32: safe preparation of immutable sponsor funding instructions.
-- This migration never broadcasts an on-chain transaction, credits funds,
-- or changes an unfunded bounty to "funded".
create table public.certifiks_sponsor_funding_intents (
  intent_id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  bounty_id uuid not null,
  sponsor_user_id uuid not null references public.certifiks_auth_users(user_id),
  idempotency_digest text not null check (idempotency_digest ~ '^[a-f0-9]{64}$'),
  manifest_digest text not null check (manifest_digest ~ '^0x[a-f0-9]{64}$'),
  chain_id numeric(78,0) not null check (chain_id > 0),
  reward_atoms numeric(78,0) not null check (reward_atoms > 0),
  prepared_at timestamptz not null default now(),
  expires_at timestamptz not null,
  state text not null default 'prepared' check (state in ('prepared','cancelled')),
  cancelled_at timestamptz,
  unique (organization_id,sponsor_user_id,idempotency_digest),
  foreign key (organization_id,bounty_id)
    references public.certifiks_bounties(organization_id,bounty_id),
  check (expires_at > prepared_at and expires_at <= prepared_at + interval '24 hours'),
  check ((state='cancelled') = (cancelled_at is not null))
);

create table public.certifiks_sponsor_funding_intent_events (
  event_id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.certifiks_organizations(organization_id),
  intent_id uuid not null references public.certifiks_sponsor_funding_intents(intent_id),
  actor_user_id uuid not null references public.certifiks_auth_users(user_id),
  action text not null check (action in ('prepared','cancelled')),
  occurred_at timestamptz not null default now()
);
create trigger certifiks_guard_sponsor_funding_events
  before update or delete on public.certifiks_sponsor_funding_intent_events
  for each row execute function public.certifiks_reject_immutable_mutation();

-- Direct even-service-role writes to immutable financial terms are blocked.
create function public.certifiks_guard_funding_terms()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.organization_id is distinct from new.organization_id or
     old.bounty_id is distinct from new.bounty_id or
     old.sponsor_user_id is distinct from new.sponsor_user_id or
     old.idempotency_digest is distinct from new.idempotency_digest or
     old.manifest_digest is distinct from new.manifest_digest or
     old.chain_id is distinct from new.chain_id or
     old.reward_atoms is distinct from new.reward_atoms or
     old.prepared_at is distinct from new.prepared_at or
     old.expires_at is distinct from new.expires_at or
     old.state='cancelled' or
     new.state <> 'cancelled' or new.cancelled_at is null
  then raise exception 'prepared funding intent cannot be changed'; end if;
  return new;
end; $$;
create trigger certifiks_guard_funding_terms
before update on public.certifiks_sponsor_funding_intents
for each row execute function public.certifiks_guard_funding_terms();

alter table public.certifiks_sponsor_funding_intents enable row level security;
alter table public.certifiks_sponsor_funding_intent_events enable row level security;
revoke all on public.certifiks_sponsor_funding_intents from public, anon, authenticated;
revoke all on public.certifiks_sponsor_funding_intent_events from public, anon, authenticated;
grant select on public.certifiks_sponsor_funding_intents to service_role;
grant select on public.certifiks_sponsor_funding_intent_events to service_role;

create function public.certifiks_prepare_sponsor_funding(
  p_org uuid, p_bounty uuid, p_actor uuid, p_manifest text,
  p_chain numeric, p_reward numeric, p_idempotency_digest text
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare existing public.certifiks_sponsor_funding_intents%rowtype;
        b public.certifiks_bounties%rowtype;
        created uuid;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'service-only sponsor funding operation';
  end if;
  if p_idempotency_digest !~ '^[a-f0-9]{64}$' or
     p_manifest !~ '^0x[a-f0-9]{64}$' or
     p_chain is null or p_chain <= 0 or p_reward is null or p_reward <= 0
  then raise exception 'invalid sponsor funding instructions'; end if;

  select * into b from public.certifiks_bounties
    where organization_id=p_org and bounty_id=p_bounty for update;
  if not found or b.sponsor_user_id <> p_actor or b.state <> 'draft'
    or b.funded_manifest_digest <> p_manifest or b.chain_id <> p_chain
    or b.reward_atoms <> p_reward
    or b.onchain_bounty_id is not null or b.funded_transaction_hash is not null
    or not exists (select 1 from public.certifiks_auth_users
      where user_id=p_actor and disabled_at is null)
  then raise exception 'sponsor, draft or immutable financial terms mismatch'; end if;

  select * into existing from public.certifiks_sponsor_funding_intents
     where organization_id=p_org and sponsor_user_id=p_actor
       and idempotency_digest=p_idempotency_digest;
  if found then
    if existing.bounty_id<>p_bounty or existing.manifest_digest<>p_manifest
       or existing.chain_id<>p_chain or existing.reward_atoms<>p_reward
    then raise exception 'idempotency digest reused for different funding'; end if;
    return existing.intent_id;
  end if;

  insert into public.certifiks_sponsor_funding_intents (
    organization_id,bounty_id,sponsor_user_id,idempotency_digest,
    manifest_digest,chain_id,reward_atoms,expires_at
  ) values (
    p_org,p_bounty,p_actor,p_idempotency_digest,
    p_manifest,p_chain,p_reward,now()+interval '24 hours'
  ) returning intent_id into created;
  insert into public.certifiks_sponsor_funding_intent_events(
    organization_id,intent_id,actor_user_id,action)
    values(p_org,created,p_actor,'prepared');
  return created;
end;
$$;

create function public.certifiks_cancel_sponsor_funding(
  p_intent uuid,p_org uuid,p_actor uuid
) returns boolean language plpgsql security definer set search_path = ''
as $$
declare n integer;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'service-only sponsor funding operation';
  end if;
  update public.certifiks_sponsor_funding_intents
    set state='cancelled',cancelled_at=now()
    where intent_id=p_intent and organization_id=p_org
       and sponsor_user_id=p_actor and state='prepared';
  get diagnostics n=row_count;
  if n=1 then
    insert into public.certifiks_sponsor_funding_intent_events(
      organization_id,intent_id,actor_user_id,action)
      values(p_org,p_intent,p_actor,'cancelled');
  end if;
  return n=1;
end;
$$;

revoke all on function public.certifiks_prepare_sponsor_funding(
  uuid,uuid,uuid,text,numeric,numeric,text) from public,anon,authenticated;
revoke all on function public.certifiks_cancel_sponsor_funding(
  uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.certifiks_prepare_sponsor_funding(
  uuid,uuid,uuid,text,numeric,numeric,text) to service_role;
grant execute on function public.certifiks_cancel_sponsor_funding(
  uuid,uuid,uuid) to service_role;
