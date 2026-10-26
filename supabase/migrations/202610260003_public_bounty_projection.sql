-- Issue #26: opt-in, redacted public bounty projection.
-- Publishing requires a finalized, non-orphaned indexed chain event and
-- explicit funding coordinates, but the upstream indexer MUST independently
-- authenticate those fields before writing them.
alter table public.certifiks_bounties
  add column if not exists public_listing boolean not null default false;

create or replace function public.certifiks_check_publication()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.public_listing and (
    new.state in ('draft','blocked') or
    new.onchain_bounty_id is null or
    new.funded_transaction_hash is null or
    not exists (
      select 1 from public.certifiks_chain_events e
       where e.organization_id = new.organization_id
         and e.bounty_id = new.bounty_id
         and e.chain_id = new.chain_id
         and e.finalized = true
         and e.orphaned = false
    )
  ) then
    raise exception 'public bounty requires finalized independently indexed funding';
  end if;
  return new;
end;
$$;
drop trigger if exists certifiks_guard_public_bounty on public.certifiks_bounties;
create trigger certifiks_guard_public_bounty
before insert or update of public_listing,state,onchain_bounty_id,funded_transaction_hash
on public.certifiks_bounties
for each row execute function public.certifiks_check_publication();

create index if not exists certifiks_public_bounty_page
  on public.certifiks_bounties(created_at desc,bounty_id)
  where public_listing = true;

-- Numeric atomic-unit values must serialize to strings; never JS floats.
-- No private artifact, developer, application or identity fields are exposed.
create or replace view public.certifiks_public_bounties_v1
with (security_invoker = true)
as
select
  b.bounty_id,
  b.repository_id::text as repository_id,
  r.full_name as repository_full_name,
  b.chain_id::text as chain_id,
  b.onchain_bounty_id::text as onchain_bounty_id,
  b.reward_atoms::text as reward_atoms,
  b.funded_manifest_digest as manifest_digest,
  b.state,
  b.created_at
from public.certifiks_bounties b
join public.certifiks_repositories r
  on r.organization_id = b.organization_id
 and r.repository_id = b.repository_id
where b.public_listing = true
  and b.state not in ('draft','blocked')
  and exists (
    select 1 from public.certifiks_chain_events e
     where e.organization_id = b.organization_id
       and e.bounty_id = b.bounty_id
       and e.chain_id = b.chain_id
       and e.finalized = true
       and e.orphaned = false
  );

revoke all on public.certifiks_public_bounties_v1 from public,anon,authenticated;
grant select on public.certifiks_public_bounties_v1 to service_role;
