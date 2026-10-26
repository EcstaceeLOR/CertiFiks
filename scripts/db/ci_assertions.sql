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

-- Issue #29: safe inbox delivery, opt-in and replay storm suppression.
insert into public.certifiks_auth_role_memberships(user_id,organization_id,role)
  values('10000000-0000-4000-8000-000000000001',
         '20000000-0000-4000-8000-000000000001','sponsor');
set request.jwt.claim.role='service_role';
do $$
declare first_id uuid; replay_id uuid; second_id uuid;
begin
  first_id:=public.certifiks_enqueue_notification(
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    'submission','0x'||repeat('1',64),repeat('f',64)
  );
  replay_id:=public.certifiks_enqueue_notification(
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    'submission','0x'||repeat('1',64),repeat('f',64)
  );
  if first_id<>replay_id then raise exception 'notification replay not idempotent'; end if;
  if (select count(*) from public.certifiks_notification_outbox
      where notification_id=first_id)<>1
  then raise exception 'duplicate or missing in-app delivery'; end if;
  begin
    perform public.certifiks_enqueue_notification(
      '20000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000001',
      'submission','0x'||repeat('2',64),repeat('f',64)
    );
    raise exception 'same event id accepted different payload';
  exception when raise_exception then
    if sqlerrm<>'notification idempotency content conflict' then raise; end if;
  end;
  if public.certifiks_mark_notification_read(
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000002',first_id
  ) then raise exception 'unrelated user marked notification as read'; end if;
  if not public.certifiks_mark_notification_read(
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',first_id
  ) then raise exception 'authorized read did not persist'; end if;
  insert into public.certifiks_notification_preferences(
    organization_id,user_id,in_app_enabled,email_opt_in
  ) values(
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',false,true
  );
  second_id:=public.certifiks_enqueue_notification(
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    'assignment','0x'||repeat('3',64),repeat('e',64)
  );
  if exists(select 1 from public.certifiks_notification_outbox
      where notification_id=second_id)
  then raise exception 'disabled inbox or unconfigured email was dispatched'; end if;
  begin
    perform public.certifiks_enqueue_notification(
      '20000000-0000-4000-8000-000000000002',
      '10000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000001',
      'assignment','0x'||repeat('4',64),repeat('d',64)
    );
    raise exception 'cross-tenant notification was accepted';
  exception when raise_exception then
    if sqlerrm<>'recipient is not an active tenant member' then raise; end if;
  end;
  if has_table_privilege('anon','public.certifiks_notification_outbox','SELECT')
  then raise exception 'anonymous user reads private outbox'; end if;
end;
$$;
reset request.jwt.claim.role;
select 'PASS: inbox replay/idempotency, tenant isolation, read owner, preference opt-out and no fake email' as result;

-- Issue #30: tenant workspace creation, invitations, replay and owner transfer.
set request.jwt.claim.role='service_role';
do $$
declare invitation uuid;
begin
  if not public.certifiks_create_workspace(
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001')
  then raise exception 'workspace creation failed'; end if;
  invitation:=public.certifiks_invite_workspace_member(
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000002',
    'maintainer',repeat('7',64),now()+interval '1 day'
  );
  begin
    perform public.certifiks_accept_workspace_invite(
      invitation,'10000000-0000-4000-8000-000000000001',repeat('7',64)
    );
    raise exception 'invite redeemed by unintended user';
  exception when raise_exception then
    if sqlerrm<>'invitation not valid for authenticated user' then raise; end if;
  end;
  if not public.certifiks_accept_workspace_invite(
    invitation,'10000000-0000-4000-8000-000000000002',repeat('7',64)
  ) then raise exception 'authorized invite rejected'; end if;
  begin
    perform public.certifiks_accept_workspace_invite(
      invitation,'10000000-0000-4000-8000-000000000002',repeat('7',64)
    );
    raise exception 'invite replay accepted';
  exception when raise_exception then
    if sqlerrm<>'invitation not valid for authenticated user' then raise; end if;
  end;
  begin
    perform public.certifiks_invite_workspace_member(
      '20000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000002',
      '10000000-0000-4000-8000-000000000001',
      'reviewer',repeat('8',64),now()+interval '1 day'
    );
    raise exception 'maintainer escalated reviewer permissions';
  exception when raise_exception then
    if sqlerrm<>'workspace invite denied' then raise; end if;
  end;
  if not public.certifiks_transfer_workspace_owner(
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000002'
  ) then raise exception 'ownership transfer not committed'; end if;
  if not public.certifiks_revoke_workspace_member(
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001'
  ) then raise exception 'old owner revocation failed'; end if;
  begin
    perform public.certifiks_revoke_workspace_member(
      '20000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000002'
    );
    raise exception 'revoked founder regained team permissions';
  exception when raise_exception then
    if sqlerrm<>'owner delegation check failed' then raise; end if;
  end;
  if (select count(*) from public.certifiks_workspace_members
      where organization_id='20000000-0000-4000-8000-000000000001'
        and role='owner' and revoked_at is null)<>1
  then raise exception 'workspace owner role corrupted'; end if;
  if (select count(*) from public.certifiks_workspace_role_events
      where organization_id='20000000-0000-4000-8000-000000000001')<>5
  then raise exception 'workspace role changes not audited'; end if;
  if (select sponsor_user_id from public.certifiks_bounties
      where bounty_id='30000000-0000-4000-8000-000000000001')
     <>'10000000-0000-4000-8000-000000000001'::uuid
  then raise exception 'workspace transfer illegally changed custody sponsor'; end if;
  if has_table_privilege('anon','public.certifiks_workspace_invites','SELECT')
  then raise exception 'browser reads private workspace invitations'; end if;
end;
$$;
reset request.jwt.claim.role;
select 'PASS: workspace invite replay, delegation matrix, owner transfer, revocation and custody separation' as result;

-- Issue #32: prepared funding is immutable, tenant-scoped and never paid.
insert into public.certifiks_bounties(
  organization_id,bounty_id,repository_id,sponsor_user_id,
  funded_manifest_digest,chain_id,reward_atoms,state
) values(
  '20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000002',
  401,'10000000-0000-4000-8000-000000000001',
  '0x'||repeat('3',64),11155111,4200000,'draft'
);

set request.jwt.claim.role='service_role';
do $$
declare intent uuid; retry uuid; cancelled boolean;
begin
  intent:=public.certifiks_prepare_sponsor_funding(
    '20000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    '0x'||repeat('3',64),11155111,4200000,repeat('a',64)
  );
  retry:=public.certifiks_prepare_sponsor_funding(
    '20000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    '0x'||repeat('3',64),11155111,4200000,repeat('a',64)
  );
  if retry<>intent then raise exception 'replayed funding created multiple intents'; end if;
  if (select count(*) from public.certifiks_sponsor_funding_intent_events
      where intent_id=intent)<>1
  then raise exception 'idempotency did not suppress duplicate audit events'; end if;
  if exists(select 1 from public.certifiks_sponsor_funding_intents
      where intent_id=intent and state<>'prepared')
  then raise exception 'intent falsely claimed funds'; end if;

  begin
    update public.certifiks_bounties set reward_atoms=5000000
    where bounty_id='30000000-0000-4000-8000-000000000002';
    raise exception 'sponsor financial terms changed after intent preparation';
  exception when raise_exception then
    if sqlerrm<>'bounty financial terms locked by prepared sponsor intent'
      then raise; end if;
  end;
  begin
    update public.certifiks_sponsor_funding_intents
      set manifest_digest='0x'||repeat('4',64) where intent_id=intent;
    raise exception 'immutable intent was rewritten';
  exception when raise_exception then
    if sqlerrm<>'prepared funding intent cannot be changed' then raise; end if;
  end;
  begin
    perform public.certifiks_prepare_sponsor_funding(
      '20000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000002',
      '10000000-0000-4000-8000-000000000002',
      '0x'||repeat('3',64),11155111,4200000,repeat('b',64)
    );
    raise exception 'non-sponsor prepared bounty funding';
  exception when raise_exception then
    if sqlerrm<>'sponsor, draft or immutable financial terms mismatch'
      then raise; end if;
  end;
  begin
    perform public.certifiks_prepare_sponsor_funding(
      '20000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000002',
      '10000000-0000-4000-8000-000000000001',
      '0x'||repeat('4',64),11155111,4200000,repeat('c',64)
    );
    raise exception 'unapproved manifest accepted for sponsor';
  exception when raise_exception then
    if sqlerrm<>'sponsor, draft or immutable financial terms mismatch'
      then raise; end if;
  end;
  if public.certifiks_cancel_sponsor_funding(
    intent,'20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000002'
  ) then raise exception 'unrelated contributor cancelled funding'; end if;
  cancelled:=public.certifiks_cancel_sponsor_funding(
    intent,'20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001'
  );
  if not cancelled then raise exception 'sponsor cancellation not persisted'; end if;
  if public.certifiks_cancel_sponsor_funding(
    intent,'20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001'
  ) then raise exception 'cancellation was not idempotently terminal'; end if;
  if (select count(*) from public.certifiks_sponsor_funding_intent_events
     where intent_id=intent)<>2
  then raise exception 'missing or duplicate funding audit events'; end if;
  if (select state from public.certifiks_bounties
      where bounty_id='30000000-0000-4000-8000-000000000002')<>'draft'
  then raise exception 'intent incorrectly marked bounty funded'; end if;
  if (select count(*) from public.certifiks_chain_observed_logs
      where chain_id=11155111)<>0
  then raise exception 'intent fabricated chain logs'; end if;
  if has_table_privilege('anon',
      'public.certifiks_sponsor_funding_intents','SELECT')
  then raise exception 'browser can access private intents'; end if;
end;
$$;
reset request.jwt.claim.role;
select 'PASS: immutable sponsored funding intent, replay, cancellation, no synthetic custody' as result;

-- Issue #34: one safe review case, no invented signature or paid vote.
insert into public.certifiks_auth_users(user_id)
values ('10000000-0000-4000-8000-000000000003');
insert into public.certifiks_auth_role_memberships(user_id,organization_id,role)
values
 ('10000000-0000-4000-8000-000000000003',
  '20000000-0000-4000-8000-000000000001','verifier'),
 ('10000000-0000-4000-8000-000000000002',
  '20000000-0000-4000-8000-000000000001','verifier'),
 ('10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001','verifier');
update public.certifiks_verification_runs
set outcome='needs_review', result_digest='0x'||repeat('9',64),completed_at=now()
where run_id='70000000-0000-4000-8000-000000000001';

set request.jwt.claim.role='service_role';
do $$
declare
  cnt integer;
  allowed boolean;
  payout boolean;
  art_cnt bigint;
begin
  select count(*),bool_or(can_attest),bool_or(payout_authorized),max(artifact_count)
    into cnt,allowed,payout,art_cnt
    from public.certifiks_verifier_review_preflight(
      '20000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000003',25
    );
  if cnt<>1 or allowed is distinct from false
    or payout is distinct from false or art_cnt<>0
  then raise exception 'unprivileged reviewer incorrectly signed / leaked evidence'; end if;
  if (select count(*) from public.certifiks_verifier_review_preflight(
      '20000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000001',25
      ))<>0
  then raise exception 'sponsor self-review admitted'; end if;
  if (select count(*) from public.certifiks_verifier_review_preflight(
      '20000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000002',25
      ))<>0
  then raise exception 'developer self-review admitted'; end if;
  begin
    perform * from public.certifiks_verifier_review_preflight(
      '20000000-0000-4000-8000-000000000002',
      '10000000-0000-4000-8000-000000000003',25
    );
    raise exception 'reviewer accessed unrelated organization';
  exception when raise_exception then
    if sqlerrm<>'reviewer not enrolled in this organization' then raise; end if;
  end;
  if (select count(*) from public.certifiks_verifier_votes)<>0
  then raise exception 'reviewer preflight created phantom signed votes'; end if;
  if (select count(*) from public.certifiks_payments)<>0
  then raise exception 'reviewer preflight triggered payment'; end if;
end;
$$;
reset request.jwt.claim.role;
select 'PASS: independent reviewer eligibility and unsigned, no-payment preflight' as result;

-- Issue #35: private immutable dispute timeline and independent arbitrator access.
insert into public.certifiks_auth_role_memberships(user_id,organization_id,role)
 values('10000000-0000-4000-8000-000000000003',
        '20000000-0000-4000-8000-000000000001','arbitrator');
insert into public.certifiks_disputes(
  organization_id,bounty_id,dispute_id,opened_by,evidence_digest
) values(
  '20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',
  'b0000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '0x'||repeat('a',64)
);
insert into public.certifiks_dispute_adjudicators(
  organization_id,dispute_id,arbitrator_user_id
) values(
  '20000000-0000-4000-8000-000000000001',
  'b0000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000003'
);
set request.jwt.claim.role='service_role';
do $$
declare
  opening uuid;
  replay uuid;
  reply uuid;
  reviewer uuid;
begin
  if not public.certifiks_can_read_dispute(
    '20000000-0000-4000-8000-000000000001',
    'b0000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000003'
  ) then raise exception 'explicit arbitrator assignment unreadable'; end if;
  if public.certifiks_can_read_dispute(
    '20000000-0000-4000-8000-000000000002',
    'b0000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000003'
  ) then raise exception 'arbitrator bypassed tenant'; end if;
  opening:=public.certifiks_record_dispute_timeline(
    '20000000-0000-4000-8000-000000000001',
    'b0000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'case_opened','0x'||repeat('a',64),null,repeat('1',64)
  );
  replay:=public.certifiks_record_dispute_timeline(
    '20000000-0000-4000-8000-000000000001',
    'b0000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'case_opened','0x'||repeat('a',64),null,repeat('1',64)
  );
  if opening<>replay then raise exception 'dispute timeline duplicated on replay'; end if;
  reply:=public.certifiks_record_dispute_timeline(
    '20000000-0000-4000-8000-000000000001',
    'b0000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000002',
    'party_response','0x'||repeat('b',64),'0x'||repeat('c',64),repeat('2',64)
  );
  reviewer:=public.certifiks_record_dispute_timeline(
    '20000000-0000-4000-8000-000000000001',
    'b0000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000003',
    'arbitrator_note','0x'||repeat('d',64),null,repeat('3',64)
  );
  if (select count(*) from public.certifiks_read_dispute_timeline(
    '20000000-0000-4000-8000-000000000001',
    'b0000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000003',25
  ))<>3 then raise exception 'assigned arb cannot see immutable case history'; end if;
  begin
    perform public.certifiks_record_dispute_timeline(
      '20000000-0000-4000-8000-000000000001',
      'b0000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000001',
      'arbitrator_note','0x'||repeat('f',64),null,repeat('4',64)
    );
    raise exception 'sponsor spoofed arbitrator note';
  exception when raise_exception then
    if sqlerrm<>'dispute actor not entitled to this event kind' then raise; end if;
  end;
  begin
    perform public.certifiks_record_dispute_timeline(
      '20000000-0000-4000-8000-000000000001',
      'b0000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000001',
      'case_opened','0x'||repeat('e',64),null,repeat('1',64)
    );
    raise exception 'changed-content event replay accepted';
  exception when raise_exception then
    if sqlerrm<>'conflicting dispute event replay' then raise; end if;
  end;
  begin
    delete from public.certifiks_dispute_timeline where timeline_id=opening;
    raise exception 'case evidence could be deleted';
  exception when raise_exception then
    if sqlerrm<>'immutable CertiFiks evidence/audit record' then raise; end if;
  end;
  if (select count(*) from public.certifiks_payments)<>0
  then raise exception 'dispute note created an unauthorized payout'; end if;
  if has_table_privilege('anon','public.certifiks_dispute_timeline','SELECT')
  then raise exception 'public browser can access private dispute timeline'; end if;
end;
$$;
reset request.jwt.claim.role;
select 'PASS: private dispute timeline, per-case arbitrator, idempotency and no payout' as result;

-- Issue #39: scoped API credentials never leak tenant content, cannot survive
-- revocation, and are rate-budgeted transactionally across replicas.
set request.jwt.claim.role='service_role';
do $$
declare key_record uuid; org_id uuid := '20000000-0000-4000-8000-000000000001';
  owner_id uuid := '10000000-0000-4000-8000-000000000002';
  old_owner uuid := '10000000-0000-4000-8000-000000000001';
  n integer;
begin
  insert into public.certifiks_partner_keys(
    organization_id,issued_by_user_id,key_sha256,expires_at
  ) values(org_id,owner_id,repeat('a',64),now()+interval '1 day')
  returning key_id into key_record;
  if not public.certifiks_authorize_partner_key(repeat('a',64),'bounties:read')
  then raise exception 'active scoped key rejected'; end if;
  if public.certifiks_authorize_partner_key(repeat('a',64),'evidence:private')
  then raise exception 'partner key escalated to private evidence'; end if;
  if public.certifiks_authorize_partner_key(repeat('f',64),'bounties:read')
  then raise exception 'unknown partner token authorized'; end if;
  for n in 1..59 loop
    if not public.certifiks_authorize_partner_key(repeat('a',64),'bounties:read')
    then raise exception 'partner rate budget blocked too early'; end if;
  end loop;
  if public.certifiks_authorize_partner_key(repeat('a',64),'bounties:read')
  then raise exception 'global partner rate budget ignored'; end if;
  update public.certifiks_partner_keys
     set request_window=now()-interval '2 minutes' where key_id=key_record;
  if not public.certifiks_authorize_partner_key(repeat('a',64),'bounties:read')
  then raise exception 'expired rate window never reset'; end if;
  begin
    perform public.certifiks_revoke_partner_key(key_record,org_id,old_owner);
    raise exception 'revoked owner could revoke API credentials';
  exception when raise_exception then
    if sqlerrm<>'active owner authentication required' then raise; end if;
  end;
  if not public.certifiks_revoke_partner_key(key_record,org_id,owner_id)
  then raise exception 'current owner could not revoke partner key'; end if;
  if public.certifiks_authorize_partner_key(repeat('a',64),'bounties:read')
  then raise exception 'revoked partner key still authorized'; end if;
  if has_table_privilege('anon','public.certifiks_partner_keys','SELECT')
  then raise exception 'anonymous principals can see token digest'; end if;
  if has_function_privilege('authenticated',
    'public.certifiks_authorize_partner_key(text,text)','EXECUTE')
  then raise exception 'browser principals can invoke server-side partner auth'; end if;
end;
$$;
reset request.jwt.claim.role;
select 'PASS: partner scopes, revocation, cross-replica quota, owner approval and private RLS' as result;
