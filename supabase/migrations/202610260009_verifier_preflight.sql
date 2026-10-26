-- Issue #34: server-side verifier preflight. NO attestation, voting,
-- artifact download, arbitration, custody access, or fabricated decision.
-- Caller MUST derive actor identity from an independently verified session.
create function public.certifiks_verifier_review_preflight(
  p_organization_id uuid,
  p_actor_user_id uuid,
  p_limit integer default 25
)
returns table (
  organization_id uuid,
  bounty_id uuid,
  attempt_id uuid,
  run_id uuid,
  base_commit_sha text,
  head_commit_sha text,
  funded_manifest_digest text,
  plan_digest text,
  runner_image_digest text,
  result_digest text,
  runner_outcome text,
  completed_at timestamptz,
  artifact_count bigint,
  can_attest boolean,
  payout_authorized boolean
)
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'verifier preflight is server-only';
  end if;
  if p_limit is null or p_limit not between 1 and 50
    or p_organization_id is null or p_actor_user_id is null then
    raise exception 'invalid reviewer request';
  end if;
  if not exists (
    select 1 from public.certifiks_auth_role_memberships m
    join public.certifiks_auth_users u on u.user_id=m.user_id
    join public.certifiks_organizations o on o.organization_id=m.organization_id
    where m.organization_id=p_organization_id and m.user_id=p_actor_user_id
      and m.role='verifier' and m.revoked_at is null
      and u.disabled_at is null
  ) then
    raise exception 'reviewer not enrolled in this organization';
  end if;

  return query
  select
    b.organization_id, b.bounty_id, a.attempt_id, v.run_id,
    a.base_commit_sha, a.head_commit_sha, b.funded_manifest_digest,
    v.committed_plan_digest, v.image_digest, v.result_digest,
    v.outcome, v.completed_at,
    (select count(*) from public.certifiks_evidence_artifacts ea
      where ea.organization_id=v.organization_id and ea.run_id=v.run_id
        and ea.deleted_at is null) as artifact_count,
    false as can_attest, false as payout_authorized
  from public.certifiks_verification_runs v
  join public.certifiks_attempts a
    on a.organization_id=v.organization_id and a.attempt_id=v.attempt_id
  join public.certifiks_assignments ass
    on ass.organization_id=a.organization_id
      and ass.assignment_id=a.assignment_id
      and ass.bounty_id=a.bounty_id
  join public.certifiks_applications appl
    on appl.organization_id=ass.organization_id
      and appl.bounty_id=ass.bounty_id
      and appl.application_id=ass.application_id
  join public.certifiks_bounties b
    on b.organization_id=a.organization_id and b.bounty_id=a.bounty_id
  where b.organization_id=p_organization_id
    and b.state not in ('draft','blocked','settled','refunded')
    and v.outcome in ('passed_claim','failed_claim','needs_review','inconclusive')
    and b.sponsor_user_id<>p_actor_user_id
    and appl.developer_user_id<>p_actor_user_id
  order by v.created_at desc, v.run_id
  limit p_limit;
end;
$$;

revoke all on function public.certifiks_verifier_review_preflight(uuid,uuid,integer)
  from public,anon,authenticated;
grant execute on function public.certifiks_verifier_review_preflight(uuid,uuid,integer)
  to service_role;
