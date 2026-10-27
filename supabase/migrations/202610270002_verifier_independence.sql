-- Issue #12: permissioned, manually vetted verifier identities.
-- This is a declared-operator registry, NOT proof of human uniqueness or a
-- live reviewer attestation mechanism. It never authorizes escrow settlement.
create table public.certifiks_verifier_principals (
  organization_id uuid not null references public.certifiks_organizations(organization_id),
  principal_id uuid not null default gen_random_uuid(),
  reviewer_user_id uuid not null references public.certifiks_auth_users(user_id),
  -- Salted, vetted operator-control pseudonym. No plaintext government IDs.
  control_digest text not null check (control_digest ~ '^0x[0-9a-f]{64}$'),
  independent_review_digest text not null
    check (independent_review_digest ~ '^0x[0-9a-f]{64}$'),
  approved_by uuid not null references public.certifiks_auth_users(user_id),
  approved_at timestamptz not null default now(),
  revoked_at timestamptz,
  primary key (organization_id, principal_id),
  unique (organization_id, reviewer_user_id),
  unique (organization_id, control_digest),
  check (reviewer_user_id <> approved_by),
  check (revoked_at is null or revoked_at >= approved_at)
);

create table public.certifiks_verifier_signing_keys (
  organization_id uuid not null,
  principal_id uuid not null,
  signer_key_id text not null check (length(signer_key_id) between 3 and 160),
  registered_at timestamptz not null default now(),
  revoked_at timestamptz,
  primary key (organization_id, principal_id, signer_key_id),
  unique (organization_id, signer_key_id),
  foreign key (organization_id, principal_id)
    references public.certifiks_verifier_principals(organization_id, principal_id),
  check (revoked_at is null or revoked_at >= registered_at)
);

-- A reviewer assignment records a snapshot, not an approval/signature/vote.
-- Multiple keys under one enrolled principal cannot count as independent
-- reviewers for the same run.
create table public.certifiks_verifier_review_assignments (
  organization_id uuid not null,
  bounty_id uuid not null,
  run_id uuid not null,
  principal_id uuid not null,
  signer_key_id text not null,
  assigned_at timestamptz not null default now(),
  primary key (organization_id, run_id, principal_id),
  foreign key (organization_id, bounty_id)
    references public.certifiks_bounties(organization_id, bounty_id),
  foreign key (organization_id, run_id)
    references public.certifiks_verification_runs(organization_id, run_id),
  foreign key (organization_id, principal_id, signer_key_id)
    references public.certifiks_verifier_signing_keys(
      organization_id, principal_id, signer_key_id
    )
);

create function public.certifiks_validate_verifier_principal()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  -- Enrollment needs a different ACTIVE operator and an ACTIVE verifier role.
  -- No unconsented reviewer can sign by merely generating new wallet keys.
  if not exists (
    select 1 from public.certifiks_auth_role_memberships m
    join public.certifiks_auth_users u on u.user_id=m.user_id
    where m.organization_id=new.organization_id
      and m.user_id=new.reviewer_user_id
      and m.role='verifier' and m.revoked_at is null
      and u.disabled_at is null
  ) or not exists (
    select 1 from public.certifiks_auth_role_memberships m
    join public.certifiks_auth_users u on u.user_id=m.user_id
    where m.organization_id=new.organization_id
      and m.user_id=new.approved_by
      and m.role='operator' and m.revoked_at is null
      and u.disabled_at is null
  ) then
    raise exception 'approved verifier and independent operator required';
  end if;
  return new;
end;
$$;
create trigger certifiks_guard_verifier_enrollment
before insert on public.certifiks_verifier_principals
for each row execute function public.certifiks_validate_verifier_principal();

create function public.certifiks_validate_verifier_assignment()
returns trigger language plpgsql set search_path = public, pg_temp as $$
declare
  reviewer uuid;
  sponsor uuid;
  reviewer_revoked timestamptz;
  key_revoked timestamptz;
begin
  -- This selection is purely a review-queue assignment: no vote or transfer.
  -- Lock enrollment + signing key against concurrent revocation.
  select p.reviewer_user_id, p.revoked_at, k.revoked_at
    into reviewer, reviewer_revoked, key_revoked
    from public.certifiks_verifier_principals p
    join public.certifiks_verifier_signing_keys k
      on k.organization_id=p.organization_id
      and k.principal_id=p.principal_id
    where p.organization_id=new.organization_id
      and p.principal_id=new.principal_id
      and k.signer_key_id=new.signer_key_id
    for share of p, k;
  if not found or reviewer_revoked is not null or key_revoked is not null then
    raise exception 'verifier principal or signing key revoked';
  end if;

  select b.sponsor_user_id into sponsor
    from public.certifiks_bounties b
    join public.certifiks_attempts a on
      a.organization_id=b.organization_id and a.bounty_id=b.bounty_id
    join public.certifiks_verification_runs v on
      v.organization_id=a.organization_id and v.attempt_id=a.attempt_id
    where b.organization_id=new.organization_id
      and b.bounty_id=new.bounty_id and v.run_id=new.run_id
      and b.state not in ('draft','blocked','settled','refunded')
    for share of b, a, v;
  if not found then
    raise exception 'run not bound to active bounty and tenant';
  end if;

  if reviewer=sponsor
    or exists (
      select 1 from public.certifiks_applications a
      where a.organization_id=new.organization_id
        and a.bounty_id=new.bounty_id
        and a.developer_user_id=reviewer
    )
    or exists (
      select 1 from public.certifiks_disputes d
      where d.organization_id=new.organization_id
        and d.bounty_id=new.bounty_id
        and d.opened_by=reviewer
    )
    or exists (
      select 1 from public.certifiks_auth_role_memberships m
      where m.user_id=reviewer and m.organization_id=new.organization_id
        and m.role='arbitrator' and m.revoked_at is null
    )
    or not exists (
      select 1 from public.certifiks_auth_role_memberships m
      join public.certifiks_auth_users u on u.user_id=m.user_id
      where m.organization_id=new.organization_id
        and m.user_id=reviewer and m.role='verifier'
        and m.revoked_at is null and u.disabled_at is null
    )
  then
    raise exception 'verifier role conflict or enrollment revoked';
  end if;
  return new;
end;
$$;

create trigger certifiks_guard_verifier_assignment
before insert on public.certifiks_verifier_review_assignments
for each row execute function public.certifiks_validate_verifier_assignment();

-- Identity and key bindings are immutable; only one-way revocation is allowed.
create function public.certifiks_guard_verifier_binding()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'verifier history cannot be removed';
  end if;
  if tg_table_name='certifiks_verifier_principals' then
    if row(new.organization_id,new.principal_id,new.reviewer_user_id,
           new.control_digest,new.independent_review_digest,new.approved_by,
           new.approved_at) is distinct from
       row(old.organization_id,old.principal_id,old.reviewer_user_id,
           old.control_digest,old.independent_review_digest,old.approved_by,
           old.approved_at)
    then raise exception 'verifier identity is immutable'; end if;
  else
    if row(new.organization_id,new.principal_id,new.signer_key_id,new.registered_at)
       is distinct from
       row(old.organization_id,old.principal_id,old.signer_key_id,old.registered_at)
    then raise exception 'verifier key is immutable'; end if;
  end if;
  if old.revoked_at is not null or new.revoked_at is null then
    raise exception 'verifier revocation is one-way';
  end if;
  return new;
end;
$$;

create trigger certifiks_guard_verifier_identity_update
before update or delete on public.certifiks_verifier_principals
for each row execute function public.certifiks_guard_verifier_binding();
create trigger certifiks_guard_verifier_key_update
before update or delete on public.certifiks_verifier_signing_keys
for each row execute function public.certifiks_guard_verifier_binding();
create trigger certifiks_guard_verifier_assignment_mutation
before update or delete on public.certifiks_verifier_review_assignments
for each row execute function public.certifiks_reject_immutable_mutation();

-- All sensitive data remains backend-only; never expose operator identifiers
-- or key IDs via browser roles. An authenticated service must still evaluate
-- identity-vetting evidence off-chain before enrolling any production reviewer.
do $$
declare t text;
begin
  foreach t in array array[
    'certifiks_verifier_principals',
    'certifiks_verifier_signing_keys',
    'certifiks_verifier_review_assignments'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from public, anon, authenticated',t);
    execute format('grant select, insert, update on public.%I to service_role',t);
  end loop;
end;
$$;
