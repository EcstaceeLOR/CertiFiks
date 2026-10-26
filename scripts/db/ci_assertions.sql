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
