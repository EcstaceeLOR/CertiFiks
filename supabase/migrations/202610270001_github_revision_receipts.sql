-- Issue #11: a GitHub App revision snapshot is evidence, not a verifier vote.
-- Protect the *exact* authenticated read receipt, immutable attempt and
-- repository/installation identity. Live service use requires an authenticated
-- wallet + GitHub session and trusted consented installation (#20/#23).
create table if not exists public.certifiks_github_revision_receipts (
  organization_id uuid not null,
  bounty_id uuid not null,
  attempt_id uuid not null,
  repository_id bigint not null check (repository_id > 0),
  source_repository_id bigint not null check (source_repository_id > 0),
  repository_full_name text not null
    check (repository_full_name ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'),
  installation_id bigint not null check (installation_id > 0),
  pull_number bigint not null check (pull_number > 0),
  developer_github_user_id bigint not null check (developer_github_user_id > 0),
  base_commit_sha text not null check (base_commit_sha ~ '^[0-9a-f]{40}$'),
  head_commit_sha text not null check (head_commit_sha ~ '^[0-9a-f]{40}$'),
  manifest_digest text not null check (manifest_digest ~ '^0x[0-9a-f]{64}$'),
  image_digest text not null check (image_digest ~ '^0x[0-9a-f]{64}$'),
  snapshot_digest text not null check (snapshot_digest ~ '^0x[0-9a-f]{64}$'),
  fork boolean not null,
  commit_signature_verified boolean not null,
  captured_at timestamptz not null default now(),
  primary key (organization_id, attempt_id),
  foreign key (organization_id, bounty_id, attempt_id)
    references public.certifiks_attempts(organization_id, bounty_id, attempt_id),
  foreign key (organization_id, repository_id)
    references public.certifiks_repositories(organization_id, repository_id),
  check (base_commit_sha <> head_commit_sha),
  check (fork = (source_repository_id <> repository_id))
);

create index if not exists certifiks_github_revision_receipts_bounty
  on public.certifiks_github_revision_receipts(organization_id, bounty_id, captured_at);

-- A service-role client cannot point a legitimate receipt at a different
-- tenant, detached commit, unrelated manifest or revoked installation.
-- Lock the source rows while checking so concurrent revocation/identity
-- changes cannot slip through admission of a new receipt.
create or replace function public.certifiks_validate_github_revision_receipt()
returns trigger language plpgsql set search_path = public, pg_temp as $$
declare bound record;
begin
  select a.base_commit_sha, a.head_commit_sha, a.status,
         b.repository_id, b.funded_manifest_digest,
         r.full_name, r.installation_id, r.access_revoked_at
    into bound
    from public.certifiks_attempts a
    join public.certifiks_bounties b
      on b.organization_id = a.organization_id and b.bounty_id = a.bounty_id
    join public.certifiks_repositories r
      on r.organization_id = b.organization_id and r.repository_id = b.repository_id
   where a.organization_id = new.organization_id
     and a.bounty_id = new.bounty_id
     and a.attempt_id = new.attempt_id
   for share of a, b, r;

  if not found or
     bound.base_commit_sha <> new.base_commit_sha or
     bound.head_commit_sha <> new.head_commit_sha or
     bound.repository_id <> new.repository_id or
     bound.funded_manifest_digest <> new.manifest_digest or
     lower(bound.full_name) <> lower(new.repository_full_name) or
     bound.installation_id <> new.installation_id or
     bound.access_revoked_at is not null or
     bound.status in ('blocked', 'rejected')
  then
    raise exception 'github receipt disagrees with immutable tenant/attempt/installation';
  end if;
  return new;
end;
$$;

drop trigger if exists certifiks_guard_github_receipt_admission
  on public.certifiks_github_revision_receipts;
create trigger certifiks_guard_github_receipt_admission
before insert on public.certifiks_github_revision_receipts
for each row execute function public.certifiks_validate_github_revision_receipt();

drop trigger if exists certifiks_guard_github_receipt_mutation
  on public.certifiks_github_revision_receipts;
create trigger certifiks_guard_github_receipt_mutation
before update or delete on public.certifiks_github_revision_receipts
for each row execute function public.certifiks_reject_immutable_mutation();

-- Never let a privileged lifecycle API rewrite the proof-bearing attempt once
-- submitted. Status changes can proceed; base/head/ownership are irreversible.
create or replace function public.certifiks_preserve_attempt_identity()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'immutable CertiFiks attempt identity';
  end if;
  if row(
      new.organization_id, new.bounty_id, new.attempt_id,
      new.assignment_id, new.base_commit_sha, new.head_commit_sha,
      new.submitted_at
     ) is distinct from row(
      old.organization_id, old.bounty_id, old.attempt_id,
      old.assignment_id, old.base_commit_sha, old.head_commit_sha,
      old.submitted_at
     )
  then
    raise exception 'immutable CertiFiks attempt identity';
  end if;
  return new;
end;
$$;

drop trigger if exists certifiks_guard_attempt_identity on public.certifiks_attempts;
create trigger certifiks_guard_attempt_identity
before update or delete on public.certifiks_attempts
for each row execute function public.certifiks_preserve_attempt_identity();

-- As with existing tenant tables, service-role bypass of RLS is powerful:
-- callers MUST authenticate roles and installation consent independently.
alter table public.certifiks_github_revision_receipts enable row level security;
revoke all on public.certifiks_github_revision_receipts from public, anon, authenticated;
grant select, insert on public.certifiks_github_revision_receipts to service_role;
