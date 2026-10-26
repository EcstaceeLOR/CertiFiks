-- Issue #23: wallet/GitHub identity persistence, replay-proof challenges
-- and opaque sessions. This migration does NOT implement EIP-191 recovery,
-- GitHub OAuth consent, verified roles or a complete login HTTP flow.
create table if not exists public.certifiks_auth_users (
  user_id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  disabled_at timestamptz
);

create table if not exists public.certifiks_auth_wallets (
  chain_id numeric(78,0) not null check (chain_id > 0),
  wallet_address text not null check (wallet_address ~ '^0x[0-9a-f]{40}$'),
  user_id uuid not null references public.certifiks_auth_users(user_id),
  linked_at timestamptz not null default now(),
  revoked_at timestamptz,
  primary key (chain_id, wallet_address)
);

create table if not exists public.certifiks_auth_github_identities (
  github_user_id bigint primary key check (github_user_id > 0),
  user_id uuid not null references public.certifiks_auth_users(user_id),
  linked_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique (user_id, github_user_id)
);

create table if not exists public.certifiks_auth_challenges (
  nonce_digest text primary key check (nonce_digest ~ '^[0-9a-f]{64}$'),
  user_id uuid references public.certifiks_auth_users(user_id),
  wallet_address text not null check (wallet_address ~ '^0x[0-9a-f]{40}$'),
  chain_id numeric(78,0) not null check (chain_id > 0),
  origin text not null,
  message_digest text not null check (message_digest ~ '^[0-9a-f]{64}$'),
  issued_at timestamptz not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  constraint five_minute_challenge check (expires_at > issued_at and expires_at <= issued_at + interval '5 minutes')
);

create table if not exists public.certifiks_auth_sessions (
  token_digest text primary key check (token_digest ~ '^[0-9a-f]{64}$'),
  csrf_digest text not null check (csrf_digest ~ '^[0-9a-f]{64}$'),
  user_id uuid not null references public.certifiks_auth_users(user_id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  rotation_parent_digest text,
  constraint short_lived_session check (expires_at <= created_at + interval '24 hours' and expires_at > created_at)
);
create index if not exists certifiks_auth_sessions_by_user
  on public.certifiks_auth_sessions(user_id) where revoked_at is null;

create table if not exists public.certifiks_auth_role_memberships (
  user_id uuid not null references public.certifiks_auth_users(user_id),
  organization_id uuid not null,
  role text not null check (role in (
    'sponsor','developer','maintainer','verifier','arbitrator','operator'
  )),
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  primary key (user_id, organization_id, role)
);

alter table public.certifiks_auth_users enable row level security;
alter table public.certifiks_auth_wallets enable row level security;
alter table public.certifiks_auth_github_identities enable row level security;
alter table public.certifiks_auth_challenges enable row level security;
alter table public.certifiks_auth_sessions enable row level security;
alter table public.certifiks_auth_role_memberships enable row level security;

revoke all on public.certifiks_auth_users from public, anon, authenticated;
revoke all on public.certifiks_auth_wallets from public, anon, authenticated;
revoke all on public.certifiks_auth_github_identities from public, anon, authenticated;
revoke all on public.certifiks_auth_challenges from public, anon, authenticated;
revoke all on public.certifiks_auth_sessions from public, anon, authenticated;
revoke all on public.certifiks_auth_role_memberships from public, anon, authenticated;

-- Must be called *after* the backend independently verifies the signed
-- challenge against the exact server-stored message and selected wallet.
-- A UNIQUE nonce hash and conditional UPDATE make replay fail atomically.
create or replace function public.certifiks_redeem_wallet_nonce(
  p_nonce_digest text,
  p_message_digest text,
  p_wallet_address text,
  p_chain_id numeric
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare updated_count integer;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'server-only nonce redemption';
  end if;
  update public.certifiks_auth_challenges
     set consumed_at = now()
   where nonce_digest = p_nonce_digest
     and message_digest = p_message_digest
     and wallet_address = p_wallet_address
     and chain_id = p_chain_id
     and consumed_at is null
     and issued_at <= now()
     and expires_at > now();
  get diagnostics updated_count = row_count;
  return updated_count = 1;
end;
$$;

revoke all on function public.certifiks_redeem_wallet_nonce(text,text,text,numeric)
  from public, anon, authenticated;
grant execute on function public.certifiks_redeem_wallet_nonce(text,text,text,numeric)
  to service_role;

-- Authentication/API must never accept arbitrary user-supplied role lists.
-- Role conflicts, sponsor/verifier independence and GitHub account ownership
-- require separately proven membership and context-specific authorization.
