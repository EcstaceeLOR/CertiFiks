-- Issue #24: run ONLY on a clean database independently restored from
-- pg_dump. These synthetic sentinel rows are not real on-chain activity.
-- This script checks exact lifecycle relationships, provenance digests,
-- finality/public visibility, tenant separation, and recovered immutability.
do $restored_lifecycle$
begin
  if (select count(*) from public.certifiks_bounties) <> 2 or
     (select count(*) from public.certifiks_attempts) <> 1 or
     (select count(*) from public.certifiks_audit_entries) <> 1 then
    raise exception 'restored row counts differ from CI seed';
  end if;

  if not exists (
    select 1
    from public.certifiks_bounties b
    join public.certifiks_repositories r
      on r.organization_id=b.organization_id
     and r.repository_id=b.repository_id
    join public.certifiks_manifest_versions m
      on m.organization_id=b.organization_id
     and m.bounty_id=b.bounty_id
    join public.certifiks_applications app
      on app.organization_id=b.organization_id
     and app.bounty_id=b.bounty_id
    join public.certifiks_assignments ass
      on ass.organization_id=app.organization_id
     and ass.bounty_id=app.bounty_id
     and ass.application_id=app.application_id
    join public.certifiks_attempts att
      on att.organization_id=ass.organization_id
     and att.bounty_id=ass.bounty_id
     and att.assignment_id=ass.assignment_id
    join public.certifiks_github_revision_receipts git
      on git.organization_id=att.organization_id
     and git.bounty_id=att.bounty_id
     and git.attempt_id=att.attempt_id
    join public.certifiks_verification_runs v
      on v.organization_id=att.organization_id
     and v.attempt_id=att.attempt_id
    join public.certifiks_chain_events ev
      on ev.organization_id=b.organization_id
     and ev.bounty_id=b.bounty_id
     and ev.chain_id=b.chain_id
    join public.certifiks_audit_entries audit
      on audit.organization_id=b.organization_id
     and audit.entity_id=b.bounty_id::text
    where b.organization_id='20000000-0000-4000-8000-000000000001'
      and b.bounty_id='30000000-0000-4000-8000-000000000001'
      and b.repository_id=401
      and b.sponsor_user_id='10000000-0000-4000-8000-000000000001'
      and b.chain_id=11155111 and b.reward_atoms=1000000
      and b.funded_manifest_digest='0x'||repeat('a',64)
      and b.onchain_bounty_id=42
      and b.funded_transaction_hash='0x'||repeat('1',64)
      and b.state='funded' and b.public_listing
      and r.full_name='sponsor-a/bugfix' and r.installation_id=1234
      and m.version=1 and m.manifest_digest=b.funded_manifest_digest
      and m.immutable_storage_key='private/manifests/a1'
      and app.developer_user_id='10000000-0000-4000-8000-000000000002'
      and att.attempt_id='60000000-0000-4000-8000-000000000001'
      and att.base_commit_sha=repeat('b',40)
      and att.head_commit_sha=repeat('c',40)
      and git.repository_id=b.repository_id
      and git.installation_id=r.installation_id
      and git.manifest_digest=b.funded_manifest_digest
      and git.base_commit_sha=att.base_commit_sha
      and git.head_commit_sha=att.head_commit_sha
      and git.snapshot_digest='0x'||repeat('f',64)
      and git.image_digest='0x'||repeat('e',64)
      and v.run_id='70000000-0000-4000-8000-000000000001'
      and v.committed_plan_digest='0x'||repeat('d',64)
      and v.image_digest=git.image_digest
      and v.outcome='pending'
      and ev.transaction_hash=b.funded_transaction_hash
      and ev.block_hash='0x'||repeat('2',64)
      and ev.event_digest='0x'||repeat('3',64)
      and ev.finalized and not ev.orphaned
      and audit.action='funded'
      and audit.entity_kind='bounty'
      and audit.entry_digest='0x'||repeat('f',64)
  ) then
    raise exception 'restored funded bounty, committed evidence, chain finality or audit relationship differs';
  end if;

  if (select count(*) from public.certifiks_public_bounties_v1) <> 1 then
    raise exception 'finalized public visibility was not restored';
  end if;
  if not exists (
    select 1 from public.certifiks_repositories
    where organization_id='20000000-0000-4000-8000-000000000002'
      and repository_id=402 and full_name='sponsor-b/bugfix'
  ) then
    raise exception 'second tenant metadata absent after recovery';
  end if;

  -- The schema and protection functions must have been restored as well as
  -- the data. A privileged update to a committed manifest still fails.
  begin
    update public.certifiks_manifest_versions
       set manifest_digest='0x'||repeat('0',64)
     where bounty_id='30000000-0000-4000-8000-000000000001';
    raise exception 'restored immutable manifest was writable';
  exception when raise_exception then
    if sqlerrm <> 'immutable CertiFiks evidence/audit record'
    then raise; end if;
  end;
  begin
    delete from public.certifiks_audit_entries;
    raise exception 'restored audit history could be erased';
  exception when raise_exception then
    if sqlerrm <> 'immutable CertiFiks evidence/audit record'
    then raise; end if;
  end;

  if has_table_privilege('anon','public.certifiks_audit_entries','SELECT') or
     has_table_privilege('authenticated','public.certifiks_manifest_versions','UPDATE') or
     has_table_privilege('anon','public.certifiks_github_revision_receipts','SELECT')
  then
    raise exception 'restored tenant/evidence privacy grants were lost';
  end if;
end;
$restored_lifecycle$;
select 'PASS: restored exact funded lifecycle, authentic references, audit immutability and tenant privacy' as result;
