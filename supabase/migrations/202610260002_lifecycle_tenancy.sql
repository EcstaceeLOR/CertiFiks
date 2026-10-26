-- CertiFiks Issue #24: tenant-isolated lifecycle schema.
-- Transactional schema, NOT deployment evidence and NOT a payout engine.
-- The API service role must authenticate the user and scope *every* query by
-- organization. Browser clients have zero direct table permissions.

create table if not exists public.certifiks_organizations (
  organization_id uuid primary key default gen_random_uuid(),
  display_name text not null check (length(display_name) between 2 and 160),
  created_at timestamptz not null default now()
);

create table if not exists public.certifiks_repositories (
  organization_id uuid not null references public.certifiks_organizations(organization_id),
  repository_id bigint not null check (repository_id > 0),
  installation_id bigint not null references public.certifiks_github_installations(installation_id),
  full_name text not null check (full_name ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'),
  access_revoked_at timestamptz,
  connected_at timestamptz not null default now(),
  primary key (organization_id, repository_id)
);

create table if not exists public.certifiks_bounties (
  organization_id uuid not null,
  bounty_id uuid not null default gen_random_uuid(),
  repository_id bigint not null,
  sponsor_user_id uuid not null references public.certifiks_auth_users(user_id),
  funded_manifest_digest text not null check (funded_manifest_digest ~ '^0x[0-9a-f]{64}$'),
  chain_id numeric(78,0) not null check (chain_id > 0),
  onchain_bounty_id numeric(78,0) check (onchain_bounty_id > 0),
  reward_atoms numeric(78,0) not null check (reward_atoms > 0),
  state text not null default 'draft' check (
    state in ('draft','funded','assigned','submitted','verifying',
              'review','disputed','payable','settled','refunded','blocked')
  ),
  funded_transaction_hash text check (
    funded_transaction_hash is null or funded_transaction_hash ~ '^0x[0-9a-f]{64}$'
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, bounty_id),
  foreign key (organization_id, repository_id)
    references public.certifiks_repositories(organization_id, repository_id),
  unique (chain_id, funded_transaction_hash),
  unique (chain_id, onchain_bounty_id)
);

create index if not exists certifiks_bounties_tenant_state
  on public.certifiks_bounties(organization_id, state, created_at);

create table if not exists public.certifiks_manifest_versions (
  organization_id uuid not null,
  bounty_id uuid not null,
  version integer not null check (version > 0),
  manifest_digest text not null check (manifest_digest ~ '^0x[0-9a-f]{64}$'),
  immutable_storage_key text not null check (length(immutable_storage_key) between 12 and 320),
  created_at timestamptz not null default now(),
  primary key (organization_id, bounty_id, version),
  foreign key (organization_id, bounty_id)
    references public.certifiks_bounties(organization_id, bounty_id),
  unique (organization_id, bounty_id, manifest_digest)
);

create table if not exists public.certifiks_applications (
  organization_id uuid not null,
  bounty_id uuid not null,
  application_id uuid not null default gen_random_uuid(),
  developer_user_id uuid not null references public.certifiks_auth_users(user_id),
  status text not null default 'pending'
    check (status in ('pending','accepted','rejected','withdrawn')),
  created_at timestamptz not null default now(),
  primary key (organization_id, application_id),
  unique (organization_id, bounty_id, developer_user_id),
  unique (organization_id, bounty_id, application_id),
  foreign key (organization_id, bounty_id)
    references public.certifiks_bounties(organization_id, bounty_id)
);

create table if not exists public.certifiks_assignments (
  organization_id uuid not null,
  bounty_id uuid not null,
  assignment_id uuid not null default gen_random_uuid(),
  application_id uuid not null,
  status text not null default 'active'
    check (status in ('active','replaced','completed','cancelled')),
  assigned_at timestamptz not null default now(),
  primary key (organization_id, assignment_id),
  unique (organization_id, bounty_id, assignment_id),
  foreign key (organization_id, bounty_id, application_id)
    references public.certifiks_applications(organization_id, bounty_id, application_id)
);
create unique index if not exists certifiks_single_active_assignment
  on public.certifiks_assignments(organization_id, bounty_id) where status = 'active';

create table if not exists public.certifiks_attempts (
  organization_id uuid not null,
  bounty_id uuid not null,
  attempt_id uuid not null default gen_random_uuid(),
  assignment_id uuid not null,
  base_commit_sha text not null check (base_commit_sha ~ '^[0-9a-f]{40}$'),
  head_commit_sha text not null check (head_commit_sha ~ '^[0-9a-f]{40}$'),
  status text not null default 'submitted'
    check (status in ('submitted','running','review','rejected','blocked','accepted')),
  submitted_at timestamptz not null default now(),
  primary key (organization_id, attempt_id),
  unique (organization_id, bounty_id, attempt_id),
  unique (organization_id, bounty_id, head_commit_sha),
  foreign key (organization_id, bounty_id, assignment_id)
    references public.certifiks_assignments(organization_id, bounty_id, assignment_id),
  check (base_commit_sha <> head_commit_sha)
);

create table if not exists public.certifiks_verification_runs (
  organization_id uuid not null,
  attempt_id uuid not null,
  run_id uuid not null default gen_random_uuid(),
  committed_plan_digest text not null check (committed_plan_digest ~ '^0x[0-9a-f]{64}$'),
  image_digest text not null check (image_digest ~ '^0x[0-9a-f]{64}$'),
  result_digest text check (result_digest is null or result_digest ~ '^0x[0-9a-f]{64}$'),
  outcome text not null default 'pending'
    check (outcome in ('pending','running','passed_claim','failed_claim',
                      'needs_review','inconclusive','runner_error')),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  primary key (organization_id, run_id),
  unique (organization_id, attempt_id, run_id),
  foreign key (organization_id, attempt_id)
    references public.certifiks_attempts(organization_id, attempt_id),
  unique (organization_id, attempt_id, result_digest)
);

create table if not exists public.certifiks_evidence_artifacts (
  organization_id uuid not null,
  run_id uuid not null,
  artifact_type text not null
    check (artifact_type in ('baseline-log','candidate-log','regression-log','report','private-input')),
  content_digest text not null check (content_digest ~ '^0x[0-9a-f]{64}$'),
  ciphertext_storage_key text not null check (length(ciphertext_storage_key) between 12 and 512),
  size_bytes bigint not null check (size_bytes > 0 and size_bytes <= 67108864),
  retention_until timestamptz not null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (organization_id, run_id, artifact_type),
  foreign key (organization_id, run_id)
    references public.certifiks_verification_runs(organization_id, run_id),
  check (retention_until > created_at)
);

create table if not exists public.certifiks_verifier_votes (
  organization_id uuid not null,
  run_id uuid not null,
  signer_organization_id uuid not null,
  signer_key_id text not null check (length(signer_key_id) between 3 and 160),
  signed_report_digest text not null check (signed_report_digest ~ '^0x[0-9a-f]{64}$'),
  signature_bytes bytea not null check (octet_length(signature_bytes) between 64 and 256),
  created_at timestamptz not null default now(),
  primary key (organization_id, run_id, signer_organization_id),
  foreign key (organization_id, run_id)
    references public.certifiks_verification_runs(organization_id, run_id)
);

create table if not exists public.certifiks_disputes (
  organization_id uuid not null,
  bounty_id uuid not null,
  dispute_id uuid not null default gen_random_uuid(),
  opened_by uuid not null references public.certifiks_auth_users(user_id),
  evidence_digest text not null check (evidence_digest ~ '^0x[0-9a-f]{64}$'),
  state text not null default 'open'
    check (state in ('open','responded','arbitration','resolved','expired')),
  created_at timestamptz not null default now(),
  primary key (organization_id, dispute_id),
  foreign key (organization_id, bounty_id)
    references public.certifiks_bounties(organization_id, bounty_id)
);

create table if not exists public.certifiks_payments (
  organization_id uuid not null,
  bounty_id uuid not null,
  payment_id uuid not null default gen_random_uuid(),
  recipient_address text not null check (recipient_address ~ '^0x[0-9a-f]{40}$'),
  amount_atoms numeric(78,0) not null check (amount_atoms > 0),
  state text not null default 'pending'
    check (state in ('pending','broadcast','finalized','reverted','blocked')),
  chain_id numeric(78,0) not null check (chain_id > 0),
  transaction_hash text check (
    transaction_hash is null or transaction_hash ~ '^0x[0-9a-f]{64}$'
  ),
  created_at timestamptz not null default now(),
  primary key (organization_id, payment_id),
  foreign key (organization_id, bounty_id)
    references public.certifiks_bounties(organization_id, bounty_id),
  unique (chain_id, transaction_hash)
);

create table if not exists public.certifiks_chain_events (
  organization_id uuid not null,
  bounty_id uuid not null,
  chain_id numeric(78,0) not null check (chain_id > 0),
  transaction_hash text not null check (transaction_hash ~ '^0x[0-9a-f]{64}$'),
  log_index integer not null check (log_index >= 0),
  block_hash text not null check (block_hash ~ '^0x[0-9a-f]{64}$'),
  block_number numeric(78,0) not null check (block_number >= 0),
  event_digest text not null check (event_digest ~ '^0x[0-9a-f]{64}$'),
  finalized boolean not null default false,
  orphaned boolean not null default false,
  recorded_at timestamptz not null default now(),
  primary key (chain_id, transaction_hash, log_index),
  foreign key (organization_id, bounty_id)
    references public.certifiks_bounties(organization_id, bounty_id),
  check (not (finalized and orphaned))
);

create table if not exists public.certifiks_notifications (
  notification_id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.certifiks_organizations(organization_id),
  user_id uuid not null references public.certifiks_auth_users(user_id),
  kind text not null check (length(kind) between 3 and 120),
  payload_digest text not null check (payload_digest ~ '^0x[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  delivered_at timestamptz
);

create table if not exists public.certifiks_audit_entries (
  audit_id bigint generated always as identity primary key,
  organization_id uuid not null references public.certifiks_organizations(organization_id),
  actor_user_id uuid references public.certifiks_auth_users(user_id),
  entity_kind text not null check (length(entity_kind) between 3 and 80),
  entity_id text not null check (length(entity_id) between 1 and 180),
  action text not null check (length(action) between 3 and 100),
  entry_digest text not null check (entry_digest ~ '^0x[0-9a-f]{64}$'),
  previous_digest text check (previous_digest is null or previous_digest ~ '^0x[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  unique (organization_id, entry_digest)
);

-- Encrypted installation data: NEVER persist plaintext installation tokens.
create table if not exists public.certifiks_encrypted_credentials (
  credential_id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.certifiks_organizations(organization_id),
  purpose text not null check (purpose in ('github-app','storage-key','webhook')),
  key_id text not null check (length(key_id) between 3 and 120),
  encrypted_value bytea not null check (octet_length(encrypted_value) >= 28),
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique (organization_id, purpose, key_id)
);

-- Enforce append-only evidence and audit data even on privileged UPDATE/DELETE.
create or replace function public.certifiks_reject_immutable_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'immutable CertiFiks evidence/audit record';
end;
$$;

drop trigger if exists certifiks_guard_audit_mutation on public.certifiks_audit_entries;
create trigger certifiks_guard_audit_mutation
before update or delete on public.certifiks_audit_entries
for each row execute function public.certifiks_reject_immutable_mutation();

drop trigger if exists certifiks_guard_manifest_mutation on public.certifiks_manifest_versions;
create trigger certifiks_guard_manifest_mutation
before update or delete on public.certifiks_manifest_versions
for each row execute function public.certifiks_reject_immutable_mutation();

drop trigger if exists certifiks_guard_verifier_vote_mutation on public.certifiks_verifier_votes;
create trigger certifiks_guard_verifier_vote_mutation
before update or delete on public.certifiks_verifier_votes
for each row execute function public.certifiks_reject_immutable_mutation();

-- Deny browser/table access. Backend service-role operations must independently
-- enforce tenant identity; service_role bypasses RLS and is NEVER browser-safe.
do $$
declare table_name text;
begin
  foreach table_name in array array[
    'certifiks_organizations','certifiks_repositories','certifiks_bounties',
    'certifiks_manifest_versions','certifiks_applications',
    'certifiks_assignments','certifiks_attempts','certifiks_verification_runs',
    'certifiks_evidence_artifacts','certifiks_verifier_votes','certifiks_disputes',
    'certifiks_payments','certifiks_chain_events','certifiks_notifications',
    'certifiks_audit_entries','certifiks_encrypted_credentials'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on public.%I from public, anon, authenticated', table_name);
    execute format('grant select, insert, update, delete on public.%I to service_role', table_name);
  end loop;
end;
$$;

grant usage, select on sequence public.certifiks_audit_entries_audit_id_seq to service_role;
