-- Issue #27: append-preserving EVM-compatible chain observation ledger.
-- This does NOT certify Portaldot runtime compatibility. Never credit funds
-- from this table until a separately audited ABI decoder and funded-event
-- reconciler bind logs to tenant bounty, amount and contract state.
create table public.certifiks_chain_indexer_heads (
  chain_id numeric(78,0) primary key check (chain_id > 0),
  genesis_hash text not null check (genesis_hash ~ '^0x[0-9a-f]{64}$'),
  last_scanned numeric(78,0) not null default 0 check (last_scanned >= 0),
  last_hash text not null check (last_hash ~ '^0x[0-9a-f]{64}$'),
  last_observed_head numeric(78,0) not null default 0 check (last_observed_head >= 0),
  confirmation_depth integer not null check (confirmation_depth between 1 and 1000),
  halted boolean not null default false,
  updated_at timestamptz not null default now()
);

create table public.certifiks_chain_observed_blocks (
  chain_id numeric(78,0) not null references public.certifiks_chain_indexer_heads(chain_id),
  block_number numeric(78,0) not null check (block_number > 0),
  block_hash text not null check (block_hash ~ '^0x[0-9a-f]{64}$'),
  parent_hash text not null check (parent_hash ~ '^0x[0-9a-f]{64}$'),
  canonical boolean not null default true,
  finalized boolean not null default false,
  observed_at timestamptz not null default now(),
  primary key (chain_id, block_hash),
  check (not (finalized and not canonical))
);
create unique index certifiks_one_canonical_block_height
  on public.certifiks_chain_observed_blocks(chain_id, block_number)
  where canonical = true;

create table public.certifiks_chain_observed_logs (
  chain_id numeric(78,0) not null,
  block_hash text not null,
  transaction_hash text not null check (transaction_hash ~ '^0x[0-9a-f]{64}$'),
  log_index integer not null check (log_index >= 0),
  contract_address text not null check (contract_address ~ '^0x[0-9a-f]{40}$'),
  topic0 text not null check (topic0 ~ '^0x[0-9a-f]{64}$'),
  raw_data_sha256 text not null check (raw_data_sha256 ~ '^0x[0-9a-f]{64}$'),
  canonical boolean not null default true,
  finalized boolean not null default false,
  observed_at timestamptz not null default now(),
  primary key (chain_id, block_hash, transaction_hash, log_index),
  foreign key (chain_id, block_hash)
    references public.certifiks_chain_observed_blocks(chain_id, block_hash),
  check (not (finalized and not canonical))
);
create index certifiks_logs_canonical_finalized
  on public.certifiks_chain_observed_logs(chain_id, finalized, contract_address)
  where canonical = true;

alter table public.certifiks_chain_indexer_heads enable row level security;
alter table public.certifiks_chain_observed_blocks enable row level security;
alter table public.certifiks_chain_observed_logs enable row level security;
revoke all on public.certifiks_chain_indexer_heads from public, anon, authenticated;
revoke all on public.certifiks_chain_observed_blocks from public, anon, authenticated;
revoke all on public.certifiks_chain_observed_logs from public, anon, authenticated;
grant select on public.certifiks_chain_indexer_heads to service_role;
grant select on public.certifiks_chain_observed_blocks to service_role;
grant select on public.certifiks_chain_observed_logs to service_role;

-- Admin must provision *independently verified* chain/genesis/depth.
create function public.certifiks_begin_evm_observation(
  p_chain_id numeric, p_genesis_hash text, p_depth integer
) returns void language plpgsql security definer set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then raise exception 'server role required'; end if;
  if p_chain_id is null or p_chain_id <= 0
    or p_genesis_hash !~ '^0x[0-9a-f]{64}$'
    or p_depth not between 1 and 1000 then
      raise exception 'invalid approved chain identity';
  end if;
  insert into public.certifiks_chain_indexer_heads(
    chain_id,genesis_hash,last_hash,confirmation_depth
  ) values(p_chain_id,p_genesis_hash,p_genesis_hash,p_depth)
  on conflict do nothing;
  if not exists(
    select 1 from public.certifiks_chain_indexer_heads
      where chain_id=p_chain_id and genesis_hash=p_genesis_hash
        and confirmation_depth=p_depth
  ) then raise exception 'chain configuration changed'; end if;
end;
$$;

-- Sequential scan ONLY; no gap, hash discontinuity, or contradictory replay.
-- Raw event payload bytes are never made public. All inputs must originate
-- from separately authenticated RPC and verified ABI/contract allowlist.
create function public.certifiks_commit_evm_observation(
  p_chain_id numeric, p_number numeric, p_hash text,
  p_parent text, p_observed_head numeric, p_logs jsonb
) returns text language plpgsql security definer set search_path = ''
as $$
declare
  cursor_row public.certifiks_chain_indexer_heads%rowtype;
  log jsonb;
  item_index integer;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'server role required'; end if;
  select * into cursor_row from public.certifiks_chain_indexer_heads
     where chain_id=p_chain_id for update;
  if not found or cursor_row.halted then raise exception 'indexer is unconfigured or halted'; end if;
  if p_number is null or p_number <= 0 or p_number > p_observed_head
    or p_hash !~ '^0x[0-9a-f]{64}$'
    or p_parent !~ '^0x[0-9a-f]{64}$'
    or jsonb_typeof(p_logs) is distinct from 'array'
    or jsonb_array_length(p_logs) > 1000 then
      raise exception 'invalid block observation';
  end if;
  if p_number <= cursor_row.last_scanned then
    if exists(select 1 from public.certifiks_chain_observed_blocks
      where chain_id=p_chain_id and block_number=p_number and block_hash=p_hash and canonical)
    then return 'duplicate'; end if;
    raise exception 'conflicting chain replay requires explicit safe rewind';
  end if;
  if p_number <> cursor_row.last_scanned + 1 or p_parent <> cursor_row.last_hash then
    raise exception 'chain gap or mismatched parent hash';
  end if;
  insert into public.certifiks_chain_observed_blocks(
    chain_id,block_number,block_hash,parent_hash
  ) values(p_chain_id,p_number,p_hash,p_parent);
  for log in select value from jsonb_array_elements(p_logs) loop
    if jsonb_typeof(log) <> 'object' or
      log->>'transactionHash' !~ '^0x[0-9a-f]{64}$' or
      log->>'address' !~ '^0x[0-9a-f]{40}$' or
      log->>'topic0' !~ '^0x[0-9a-f]{64}$' or
      log->>'dataSha256' !~ '^0x[0-9a-f]{64}$' or
      log->>'blockHash' is distinct from p_hash or
      log->>'blockNumber' is distinct from p_number::text or
      log->>'logIndex' !~ '^(0|[1-9][0-9]*)$' then
        raise exception 'malformed or wrong-block log';
    end if;
    item_index := (log->>'logIndex')::integer;
    if item_index < 0 then raise exception 'invalid log index'; end if;
    insert into public.certifiks_chain_observed_logs (
      chain_id, block_hash, transaction_hash, log_index, contract_address, topic0, raw_data_sha256
    ) values (
      p_chain_id,p_hash,log->>'transactionHash',item_index,
      log->>'address',log->>'topic0',log->>'dataSha256'
    );
  end loop;
  update public.certifiks_chain_indexer_heads
    set last_scanned=p_number, last_hash=p_hash,
      last_observed_head=greatest(last_observed_head,p_observed_head),updated_at=now()
    where chain_id=p_chain_id;
  return 'accepted';
end;
$$;

-- Explicit local reorg repair, with all replaced historical rows preserved.
-- A deeper-than-finality reorg HALTS indexing: do not fabricate custody state.
create function public.certifiks_rewind_evm_observations(
  p_chain_id numeric, p_ancestor numeric, p_hash text
) returns void language plpgsql security definer set search_path = ''
as $$
declare cursor_row public.certifiks_chain_indexer_heads%rowtype;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'server role required'; end if;
  select * into cursor_row from public.certifiks_chain_indexer_heads
    where chain_id=p_chain_id for update;
  if not found or p_ancestor is null or p_ancestor < 0
    or p_ancestor > cursor_row.last_scanned then raise exception 'invalid rewind'; end if;
  if (p_ancestor=0 and p_hash <> cursor_row.genesis_hash)
    or (p_ancestor > 0 and not exists(select 1 from public.certifiks_chain_observed_blocks
      where chain_id=p_chain_id and block_number=p_ancestor
      and block_hash=p_hash and canonical))
  then raise exception 'unproven ancestor'; end if;
  if exists(select 1 from public.certifiks_chain_observed_blocks
       where chain_id=p_chain_id and block_number > p_ancestor and finalized)
    then raise exception 'deep reorg exceeds finality: operator halt required'; end if;
  update public.certifiks_chain_observed_logs set canonical=false, finalized=false
    where chain_id=p_chain_id and block_hash in
      (select block_hash from public.certifiks_chain_observed_blocks
       where chain_id=p_chain_id and block_number > p_ancestor and canonical);
  update public.certifiks_chain_observed_blocks set canonical=false,finalized=false
    where chain_id=p_chain_id and block_number > p_ancestor and canonical;
  update public.certifiks_chain_indexer_heads
    set last_scanned=p_ancestor,last_hash=p_hash,updated_at=now()
    where chain_id=p_chain_id;
end;
$$;

-- Observed confirmations are PROVISIONAL: must come from an independent
-- trusted chain head. Never finalize outside the independently observed range.
create function public.certifiks_finalize_evm_observations(
  p_chain_id numeric, p_verified_head numeric
) returns integer language plpgsql security definer set search_path = ''
as $$
declare c public.certifiks_chain_indexer_heads%rowtype;
  safe_height numeric; count_blocks integer;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'server role required'; end if;
  select * into c from public.certifiks_chain_indexer_heads where chain_id=p_chain_id for update;
  if not found or c.halted or p_verified_head is null or
     p_verified_head < c.last_scanned or p_verified_head > c.last_observed_head
  then raise exception 'unverified or outdated finality head'; end if;
  safe_height:=p_verified_head-c.confirmation_depth;
  update public.certifiks_chain_observed_blocks set finalized=true
     where chain_id=p_chain_id and canonical and not finalized
       and block_number<=safe_height;
  get diagnostics count_blocks=row_count;
  update public.certifiks_chain_observed_logs set finalized=true
     where chain_id=p_chain_id and canonical and not finalized
       and block_hash in (select block_hash from public.certifiks_chain_observed_blocks
         where chain_id=p_chain_id and canonical and finalized);
  return count_blocks;
end;
$$;

revoke all on function public.certifiks_begin_evm_observation(numeric,text,integer)
  from public,anon,authenticated;
revoke all on function public.certifiks_commit_evm_observation(numeric,numeric,text,text,numeric,jsonb)
  from public,anon,authenticated;
revoke all on function public.certifiks_rewind_evm_observations(numeric,numeric,text)
  from public,anon,authenticated;
revoke all on function public.certifiks_finalize_evm_observations(numeric,numeric)
  from public,anon,authenticated;
grant execute on function public.certifiks_begin_evm_observation(numeric,text,integer) to service_role;
grant execute on function public.certifiks_commit_evm_observation(numeric,numeric,text,text,numeric,jsonb) to service_role;
grant execute on function public.certifiks_rewind_evm_observations(numeric,numeric,text) to service_role;
grant execute on function public.certifiks_finalize_evm_observations(numeric,numeric) to service_role;
