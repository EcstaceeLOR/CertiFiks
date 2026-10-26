-- Deterministic, fully executable PostgreSQL tenant/idempotency smoke suite.
-- Uses synthetic metadata only, never real money or real repo secrets.
insert into public.certifiks_auth_users (user_id) values
  ('10000000-0000-4000-8000-000000000001'),
  ('10000000-0000-4000-8000-000000000002');

insert into public.certifiks_github_installations (installation_id) values (1234);

insert into public.certifiks_organizations (organization_id, display_name) values
  ('20000000-0000-4000-8000-000000000001','Example Sponsor A'),
  ('20000000-0000-4000-8000-000000000002','Example Sponsor B');

insert into public.certifiks_repositories
  (organization_id, repository_id, installation_id, full_name)
values
  ('20000000-0000-4000-8000-000000000001',401,1234,'sponsor-a/bugfix'),
  ('20000000-0000-4000-8000-000000000002',402,1234,'sponsor-b/bugfix');

insert into public.certifiks_bounties (
  organization_id,bounty_id,repository_id,sponsor_user_id,
  funded_manifest_digest,chain_id,reward_atoms,state
) values (
  '20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',
  401,
  '10000000-0000-4000-8000-000000000001',
  '0x' || repeat('a',64),
  11155111,1000000,'funded'
);

insert into public.certifiks_manifest_versions
  (organization_id,bounty_id,version,manifest_digest,immutable_storage_key)
values (
  '20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',
  1, '0x' || repeat('a',64), 'private/manifests/a1'
);

insert into public.certifiks_applications (
  organization_id,bounty_id,application_id,developer_user_id
) values (
  '20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',
  '40000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000002'
);

insert into public.certifiks_assignments
  (organization_id,bounty_id,assignment_id,application_id)
values (
  '20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',
  '50000000-0000-4000-8000-000000000001',
  '40000000-0000-4000-8000-000000000001'
);

insert into public.certifiks_attempts
  (organization_id,bounty_id,attempt_id,assignment_id,base_commit_sha,head_commit_sha)
values (
  '20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',
  '60000000-0000-4000-8000-000000000001',
  '50000000-0000-4000-8000-000000000001',
  repeat('b',40),repeat('c',40)
);

insert into public.certifiks_verification_runs
  (organization_id,attempt_id,run_id,committed_plan_digest,image_digest,outcome)
values (
  '20000000-0000-4000-8000-000000000001',
  '60000000-0000-4000-8000-000000000001',
  '70000000-0000-4000-8000-000000000001',
  '0x' || repeat('d',64),'0x' || repeat('e',64),'pending'
);

insert into public.certifiks_audit_entries
  (organization_id,actor_user_id,entity_kind,entity_id,action,entry_digest)
values (
  '20000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'bounty',
  '30000000-0000-4000-8000-000000000001',
  'funded',
  '0x' || repeat('f',64)
);

do $$
declare n integer;
begin
  select count(*) into n from public.certifiks_bounties;
  if n <> 1 then raise exception 'funded bounty not persisted'; end if;

  begin
    insert into public.certifiks_applications (
      organization_id,bounty_id,developer_user_id
    ) values (
      '20000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000002'
    );
    raise exception 'duplicate application was accepted';
  exception when unique_violation then null;
  end;

  begin
    insert into public.certifiks_applications (
      organization_id,bounty_id,developer_user_id
    ) values (
      '20000000-0000-4000-8000-000000000002',
      '30000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000002'
    );
    raise exception 'foreign tenant bounty was accepted';
  exception when foreign_key_violation then null;
  end;

  begin
    update public.certifiks_manifest_versions set manifest_digest =
      '0x' || repeat('9',64);
    raise exception 'immutable manifest was changed';
  exception when raise_exception then
    if sqlerrm <> 'immutable CertiFiks evidence/audit record' then raise; end if;
  end;

  begin
    delete from public.certifiks_audit_entries;
    raise exception 'audit trail deletion was accepted';
  exception when raise_exception then
    if sqlerrm <> 'immutable CertiFiks evidence/audit record' then raise; end if;
  end;

  if has_table_privilege('anon','public.certifiks_bounties','SELECT') or
     has_table_privilege('authenticated','public.certifiks_evidence_artifacts','SELECT')
  then
    raise exception 'browser principal can read private tenant rows';
  end if;
end;
$$;

-- Signed-event processing idempotency. Exact payload replay even with another
-- delivery ID must dedupe, while revocation blocks pending events.
set request.jwt.claim.role = 'service_role';
do $$
declare
 first_result text;
 replay_result text;
begin
  first_result := public.certifiks_ingest_github_event(
    '80000000-0000-4000-8000-000000000001',repeat('1',64),
    'installation','created',1234,null,now()
  );
  replay_result := public.certifiks_ingest_github_event(
    '80000000-0000-4000-8000-000000000002',repeat('1',64),
    'installation','created',1234,null,now()
  );
  if first_result <> 'accepted' or replay_result <> 'duplicate' then
    raise exception 'webhook replay admitted twice';
  end if;
end;
$$;
reset request.jwt.claim.role;

select 'PASS: tenant foreign keys, idempotency, immutable audit, replay and private RLS' as result;

-- Public projection is fail-closed unless the indexer has recorded finality.
do $$
begin
  if (select count(*) from public.certifiks_public_bounties_v1) <> 0 then
    raise exception 'private/unfinalized bounty is listed publicly';
  end if;
  begin
    update public.certifiks_bounties set public_listing = true
     where bounty_id = '30000000-0000-4000-8000-000000000001';
    raise exception 'unfinalized bounty was allowed public listing';
  exception when raise_exception then
    if sqlerrm <> 'public bounty requires finalized independently indexed funding' then
      raise;
    end if;
  end;
end;
$$;

-- Synthetic finalized chain event fixture, not a real chain receipt.
insert into public.certifiks_chain_events (
  organization_id,bounty_id,chain_id,transaction_hash,log_index,
  block_hash,block_number,event_digest,finalized
) values (
  '20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',
  11155111,'0x' || repeat('1',64),0,
  '0x' || repeat('2',64),1000,'0x' || repeat('3',64),true
);
update public.certifiks_bounties
   set onchain_bounty_id = 42,
       funded_transaction_hash = '0x' || repeat('1',64),
       public_listing = true
 where bounty_id = '30000000-0000-4000-8000-000000000001';

do $$
declare
  published_count integer;
  amount_text text;
begin
  select count(*), max(reward_atoms) into published_count, amount_text
    from public.certifiks_public_bounties_v1;
  if published_count <> 1 or amount_text <> '1000000' then
    raise exception 'public projection omitted finalized bounty or lost precision';
  end if;
  if has_table_privilege('anon','public.certifiks_public_bounties_v1','SELECT') then
    raise exception 'anonymous clients must not bypass backend redaction';
  end if;
end;
$$;

-- A chain reorg/finality rollback must immediately remove a once-public bounty.
update public.certifiks_chain_events
   set finalized = false, orphaned = true
 where chain_id = 11155111 and transaction_hash = '0x' || repeat('1',64);
do $$
begin
  if (select count(*) from public.certifiks_public_bounties_v1) <> 0 then
    raise exception 'orphaned funding remained publicly listed';
  end if;
end;
$$;
-- Re-indexed canonical finalized fixture, never an actual RPC proof.
update public.certifiks_chain_events
   set finalized = true, orphaned = false
 where chain_id = 11155111 and transaction_hash = '0x' || repeat('1',64);

-- Issue #27: synthetic chain history and deep-reorg checks. Not a live receipt.
set request.jwt.claim.role = 'service_role';
select public.certifiks_begin_evm_observation(31337,'0x'||repeat('a',64),2);
do $$
declare decision text;
begin
  decision:=public.certifiks_commit_evm_observation(
    31337,1,'0x'||repeat('b',64),'0x'||repeat('a',64),3,
    jsonb_build_array(jsonb_build_object(
      'transactionHash','0x'||repeat('1',64),
      'blockHash','0x'||repeat('b',64),
      'blockNumber','1',
      'logIndex','0','address','0x'||repeat('c',40),
      'topic0','0x'||repeat('d',64),
      'dataSha256','0x'||repeat('e',64)
    ))
  );
  if decision <> 'accepted' then raise exception 'first block rejected'; end if;
  decision:=public.certifiks_commit_evm_observation(
    31337,1,'0x'||repeat('b',64),'0x'||repeat('a',64),3,'[]'::jsonb
  );
  if decision <> 'duplicate' then raise exception 'block replay not idempotent'; end if;
  if (select count(*) from public.certifiks_chain_observed_logs where chain_id=31337)<>1
  then raise exception 'duplicate chain log'; end if;
  begin
    perform public.certifiks_commit_evm_observation(
      31337,3,'0x'||repeat('f',64),'0x'||repeat('b',64),3,'[]'::jsonb
    );
    raise exception 'out-of-sequence block accepted';
  exception when raise_exception then
    if sqlerrm <> 'chain gap or mismatched parent hash' then raise; end if;
  end;
  perform public.certifiks_commit_evm_observation(
    31337,2,'0x'||repeat('c',64),'0x'||repeat('b',64),3,'[]'::jsonb
  );
  perform public.certifiks_rewind_evm_observations(
    31337,1,'0x'||repeat('b',64)
  );
  perform public.certifiks_commit_evm_observation(
    31337,2,'0x'||repeat('d',64),'0x'||repeat('b',64),3,'[]'::jsonb
  );
  if (select count(*) from public.certifiks_chain_observed_blocks
      where chain_id=31337 and block_number=2 and canonical)<>1
     or (select count(*) from public.certifiks_chain_observed_blocks
      where chain_id=31337 and block_number=2 and not canonical)<>1
  then raise exception 'reorg branches were not preserved'; end if;
  if public.certifiks_finalize_evm_observations(31337,3)<>1
  then raise exception 'confirmation depth not respected'; end if;
  begin
    perform public.certifiks_rewind_evm_observations(31337,0,'0x'||repeat('a',64));
    raise exception 'deep reorg of finalized block allowed';
  exception when raise_exception then
    if sqlerrm <> 'deep reorg exceeds finality: operator halt required'
      then raise; end if;
  end;
  if has_table_privilege('anon','public.certifiks_chain_observed_logs','SELECT') then
    raise exception 'browser principal can read private chain event ledger'; end if;
  if (select count(*) from public.certifiks_public_bounties_v1)<>1 then
    raise exception 'synthetic indexer observations changed bounty/funds projection'; end if;
end;
$$;
reset request.jwt.claim.role;
select 'PASS: chain replay, parent gap, reorg, finality, privacy and unchanged bounty funding' as result;

-- Issue #28: durable queue retries, idempotent attempt/stage and lease fencing.
set request.jwt.claim.role = 'service_role';
do $$
declare
  a uuid;
  b uuid;
  claimed public.certifiks_verification_jobs%rowtype;
  replay uuid;
begin
  a := public.certifiks_enqueue_verification_stage(
    '20000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    '60000000-0000-4000-8000-000000000001',
    '0x'||repeat('a',64), 'baseline'
  );
  replay := public.certifiks_enqueue_verification_stage(
    '20000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    '60000000-0000-4000-8000-000000000001',
    '0x'||repeat('a',64), 'baseline'
  );
  if a<>replay then raise exception 'duplicate job created by retry'; end if;
  begin
    perform public.certifiks_enqueue_verification_stage(
      '20000000-0000-4000-8000-000000000002',
      '30000000-0000-4000-8000-000000000001',
      '60000000-0000-4000-8000-000000000001',
      '0x'||repeat('a',64), 'baseline'
    );
    raise exception 'foreign-tenant queued verification';
  exception when raise_exception then
    if sqlerrm<>'attempt does not match the funded manifest and tenant'
    then raise; end if;
  end;
  select * into claimed from public.certifiks_claim_verification_jobs(5);
  if claimed.job_id<>a or claimed.attempts<>1 or claimed.lease_id is null
  then raise exception 'job lease was not atomically acquired'; end if;
  if public.certifiks_complete_verification_job(
      a,gen_random_uuid(),1,true,null)
  then raise exception 'wrong lease completed job'; end if;
  if not public.certifiks_heartbeat_verification_job(
      a,claimed.lease_id,1)
  then raise exception 'valid heartbeat rejected'; end if;
  if not public.certifiks_complete_verification_job(
      a,claimed.lease_id,1,false,'GITHUB_RATE_LIMITED')
  then raise exception 'retry failed'; end if;
  if exists(select 1 from public.certifiks_claim_verification_jobs(5))
  then raise exception 'backoff was not respected'; end if;
  update public.certifiks_verification_jobs
    set retry_after=now()-interval '1 second'
    where job_id=a;
  select * into claimed from public.certifiks_claim_verification_jobs(5);
  if claimed.job_id<>a or claimed.attempts<>2
  then raise exception 'retry attempt not re-leased'; end if;
  if public.certifiks_complete_verification_job(
      a,gen_random_uuid(),1,true,null)
  then raise exception 'expired worker acknowledged new lease'; end if;
  if not public.certifiks_complete_verification_job(
      a,claimed.lease_id,2,true,null)
  then raise exception 'correct lease acknowledgement failed'; end if;
  if (select status from public.certifiks_verification_jobs where job_id=a)<>'succeeded'
  then raise exception 'verified job not terminal'; end if;
  b:=public.certifiks_enqueue_verification_stage(
    '20000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    '60000000-0000-4000-8000-000000000001',
    '0x'||repeat('a',64),'candidate'
  );
  update public.certifiks_verification_jobs
    set max_attempts=1 where job_id=b;
  select * into claimed from public.certifiks_claim_verification_jobs(5);
  if claimed.job_id<>b then raise exception 'candidate stage not claimable'; end if;
  if not public.certifiks_complete_verification_job(
      b,claimed.lease_id,1,false,'RUNNER_CRASHED')
  then raise exception 'failure acknowledgement rejected'; end if;
  if (select status from public.certifiks_verification_jobs where job_id=b)<>'dead_letter'
  then raise exception 'exhausted job did not dead-letter'; end if;
  if (select count(*) from public.certifiks_payments)<>0 then
    raise exception 'verification jobs unexpectedly mutated payments'; end if;
  if has_table_privilege('anon','public.certifiks_verification_jobs','SELECT') then
    raise exception 'browser can access private queue'; end if;
end;
$$;
reset request.jwt.claim.role;
select 'PASS: verifier queue idempotency, lease fencing, backoff, dead-letter and no payout writes' as result;
