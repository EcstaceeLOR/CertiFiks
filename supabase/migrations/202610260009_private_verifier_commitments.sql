-- Issue #34: private independent reviewer commitment substrate.
-- A stored hash is NEVER a signature, verdict, quorum or chain attestation.
-- Reviewer enrollment is an offline operator governance step until live identity
-- and consent systems are independently verified.
create table public.certifiks_reviewer_registry (
  reviewer_user_id uuid not null references public.certifiks_auth_users(user_id),
  signer_organization_id uuid not null references public.certifiks_organizations(organization_id),
  signer_key_id text not null check (signer_key_id ~ '^[A-Za-z0-9_-]{3,80}$'),
  active_from timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  primary key (reviewer_user_id,signer_organization_id),
  unique (signer_organization_id,signer_key_id),
  check (expires_at > active_from)
);

create table public.certifiks_private_review_commitments (
  organization_id uuid not null,
  run_id uuid not null,
  reviewer_user_id uuid not null references public.certifiks_auth_users(user_id),
  signer_organization_id uuid not null,
  signer_key_id text not null,
  head_commit_sha text not null check (head_commit_sha ~ '^[0-9a-f]{40}$'),
  funded_manifest_digest text not null check (funded_manifest_digest ~ '^0x[a-f0-9]{64}$'),
  runner_result_digest text not null check (runner_result_digest ~ '^0x[a-f0-9]{64}$'),
  signed_report_digest text not null check (signed_report_digest ~ '^0x[a-f0-9]{64}$'),
  concealed_verdict_commitment text not null check (concealed_verdict_commitment ~ '^0x[a-f0-9]{64}$'),
  committed_at timestamptz not null default now(),
  expires_at timestamptz not null,
  primary key (organization_id,run_id,reviewer_user_id),
  unique (organization_id,run_id,signer_organization_id),
  foreign key (organization_id,run_id)
    references public.certifiks_verification_runs(organization_id,run_id),
  foreign key (reviewer_user_id,signer_organization_id)
    references public.certifiks_reviewer_registry(reviewer_user_id,signer_organization_id),
  check (expires_at > committed_at and expires_at <= committed_at+interval '24 hours')
);

create trigger certifiks_guard_private_review_mutation
  before update or delete on public.certifiks_private_review_commitments
  for each row execute function public.certifiks_reject_immutable_mutation();

alter table public.certifiks_reviewer_registry enable row level security;
alter table public.certifiks_private_review_commitments enable row level security;
revoke all on public.certifiks_reviewer_registry from public,anon,authenticated;
revoke all on public.certifiks_private_review_commitments from public,anon,authenticated;
grant select on public.certifiks_reviewer_registry to service_role;
grant select on public.certifiks_private_review_commitments to service_role;

-- Backend-only, blinded, one-time hash commitment. The API must derive the
-- actor from an authenticated session; p_actor is NOT a browser-authoritative
-- identity assertion. Operator registration alone is not cryptographic proof.
create function public.certifiks_commit_private_reviewer_intent(
  p_case_org uuid,p_run uuid,p_actor uuid,p_reviewer_org uuid,
  p_key text,p_head text,p_manifest text,p_runner_digest text,
  p_report_digest text,p_concealed_digest text,p_expires timestamptz
) returns text language plpgsql security definer set search_path = ''
as $$
declare r public.certifiks_verification_runs%rowtype;
  bounty_id uuid;
  sponsor_id uuid;
  developer_id uuid;
  expected_head text;
  expected_manifest text;
  prior public.certifiks_private_review_commitments%rowtype;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'reviewer commitment requires server auth';
  end if;
  if p_report_digest !~ '^0x[a-f0-9]{64}$'
     or p_concealed_digest !~ '^0x[a-f0-9]{64}$'
     or p_runner_digest !~ '^0x[a-f0-9]{64}$'
     or p_manifest !~ '^0x[a-f0-9]{64}$'
     or p_head !~ '^[0-9a-f]{40}$'
     or p_expires is null or p_expires <= now()
     or p_expires > now()+interval '24 hours' then
       raise exception 'invalid immutable commitment binding';
  end if;

  select v.* into r from public.certifiks_verification_runs v
    where v.organization_id=p_case_org and v.run_id=p_run for share;
  if not found or r.result_digest is null or r.result_digest<>p_runner_digest
     or r.completed_at is null
     or r.outcome not in ('passed_claim','failed_claim','needs_review','inconclusive') then
    raise exception 'runner has no completed immutable result';
  end if;

  select a.bounty_id,a.head_commit_sha,b.sponsor_user_id,
         b.funded_manifest_digest,app.developer_user_id
    into bounty_id,expected_head,sponsor_id,expected_manifest,developer_id
    from public.certifiks_attempts a
    join public.certifiks_bounties b
      on b.organization_id=a.organization_id and b.bounty_id=a.bounty_id
    join public.certifiks_assignments assign
      on assign.organization_id=a.organization_id
      and assign.bounty_id=a.bounty_id and assign.assignment_id=a.assignment_id
    join public.certifiks_applications app
      on app.organization_id=assign.organization_id
      and app.bounty_id=assign.bounty_id
      and app.application_id=assign.application_id
    where a.organization_id=p_case_org and a.attempt_id=r.attempt_id;
  if bounty_id is null or expected_head<>p_head
     or expected_manifest<>p_manifest
     or sponsor_id=p_actor or developer_id=p_actor
     or p_case_org=p_reviewer_org then
       raise exception 'reviewer is conflicted or attempted to change pinned evidence';
  end if;

  if not exists(select 1 from public.certifiks_auth_users
      where user_id=p_actor and disabled_at is null)
     or not exists(select 1 from public.certifiks_reviewer_registry registry
       where registry.reviewer_user_id=p_actor
         and registry.signer_organization_id=p_reviewer_org
         and registry.signer_key_id=p_key
         and registry.revoked_at is null
         and registry.active_from<=now() and registry.expires_at>p_expires)
     or not exists(select 1 from public.certifiks_auth_role_memberships roles
       where roles.user_id=p_actor and roles.organization_id=p_reviewer_org
         and roles.role='verifier' and roles.revoked_at is null) then
    raise exception 'reviewer identity or independence not enrolled';
  end if;

  select * into prior from public.certifiks_private_review_commitments
    where organization_id=p_case_org and run_id=p_run
      and reviewer_user_id=p_actor;
  if found then
    if prior.concealed_verdict_commitment<>p_concealed_digest or
       prior.signed_report_digest<>p_report_digest or
       prior.head_commit_sha<>p_head or prior.funded_manifest_digest<>p_manifest
    then raise exception 'cannot change a blinded reviewer commitment'; end if;
    return 'duplicate';
  end if;

  insert into public.certifiks_private_review_commitments (
    organization_id,run_id,reviewer_user_id,signer_organization_id,
    signer_key_id,head_commit_sha,funded_manifest_digest,
    runner_result_digest,signed_report_digest,concealed_verdict_commitment,
    expires_at
  ) values (
    p_case_org,p_run,p_actor,p_reviewer_org,p_key,p_head,p_manifest,
    p_runner_digest,p_report_digest,p_concealed_digest,p_expires
  );
  return 'accepted';
end;
$$;

revoke all on function public.certifiks_commit_private_reviewer_intent(
  uuid,uuid,uuid,uuid,text,text,text,text,text,text,timestamptz
) from public,anon,authenticated;
grant execute on function public.certifiks_commit_private_reviewer_intent(
  uuid,uuid,uuid,uuid,text,text,text,text,text,text,timestamptz
) to service_role;

-- A registered review commitment freezes the exact runner result and image/
-- plan binding. The server must never retroactively mutate a decided case.
create function public.certifiks_guard_reviewed_runner_context()
returns trigger language plpgsql set search_path = '' as $$
begin
  if exists(select 1 from public.certifiks_private_review_commitments
    where organization_id=old.organization_id and run_id=old.run_id)
    and (
      old.attempt_id is distinct from new.attempt_id or
      old.committed_plan_digest is distinct from new.committed_plan_digest or
      old.image_digest is distinct from new.image_digest or
      old.result_digest is distinct from new.result_digest or
      old.outcome is distinct from new.outcome or
      old.completed_at is distinct from new.completed_at
    )
  then raise exception 'immutable reviewed runner context'; end if;
  return new;
end; $$;

create trigger certifiks_guard_reviewed_runner_context
  before update of attempt_id,committed_plan_digest,image_digest,
    result_digest,outcome,completed_at
  on public.certifiks_verification_runs
  for each row execute function public.certifiks_guard_reviewed_runner_context();
