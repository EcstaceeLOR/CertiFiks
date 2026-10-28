-- Issue #23: a rotated browser session must never leave two live children.
-- Server-side session infrastructure ONLY. Does not verify wallet signatures,
-- provision a GitHub OAuth identity, or expose an authentication HTTP route.

alter table public.certifiks_auth_sessions
  add constraint certifiks_session_rotation_parent_digest_format
  check (
    rotation_parent_digest is null or
    rotation_parent_digest ~ '^[a-f0-9]{64}$'
  );

create unique index certifiks_one_rotation_child_per_session
  on public.certifiks_auth_sessions(rotation_parent_digest)
  where rotation_parent_digest is not null;

-- The bearer/CSRF digest, subject, expiry and token ancestry cannot be
-- reassigned in place. Only one-way revocation is permitted. Rotate by
-- inserting a distinct child through the protected function below.
create function public.certifiks_guard_auth_session_integrity()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'auth session history cannot be deleted';
  end if;
  if row(
    new.token_digest, new.csrf_digest, new.user_id, new.created_at,
    new.expires_at, new.rotation_parent_digest
  ) is distinct from row(
    old.token_digest, old.csrf_digest, old.user_id, old.created_at,
    old.expires_at, old.rotation_parent_digest
  ) then
    raise exception 'auth session identity and expiry are immutable';
  end if;
  if old.revoked_at is not null and
     new.revoked_at is distinct from old.revoked_at then
    raise exception 'auth session revocation is one-way';
  end if;
  if new.revoked_at is not null and new.revoked_at < old.created_at then
    raise exception 'auth session revocation cannot precede creation';
  end if;
  return new;
end;
$$;

create trigger certifiks_guard_auth_session_update
before update or delete on public.certifiks_auth_sessions
for each row execute function public.certifiks_guard_auth_session_integrity();

-- A rotation does NOT extend the existing authenticated session's lifetime.
-- A new wallet proof must be collected to create a longer-lived session.
-- The original token+CSRF must be validated by the protected HTTP handler
-- before their SHA-256 digests are provided to this server-only function.
create function public.certifiks_rotate_auth_session_once(
  p_old_token_digest text,
  p_old_csrf_digest text,
  p_new_token_digest text,
  p_new_csrf_digest text,
  p_expires_at timestamptz
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_previous_expiry timestamptz;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'server-only auth session rotation';
  end if;
  if p_old_token_digest !~ '^[a-f0-9]{64}$' or
     p_old_csrf_digest !~ '^[a-f0-9]{64}$' or
     p_new_token_digest !~ '^[a-f0-9]{64}$' or
     p_new_csrf_digest !~ '^[a-f0-9]{64}$' or
     p_old_token_digest = p_new_token_digest or
     p_old_csrf_digest = p_new_csrf_digest then
    raise exception 'invalid rotated session digests';
  end if;

  update public.certifiks_auth_sessions
     set revoked_at = now()
   where token_digest = p_old_token_digest
     and csrf_digest = p_old_csrf_digest
     and revoked_at is null
     and created_at <= now()
     and expires_at > now()
   returning user_id, expires_at into v_user_id, v_previous_expiry;
  if not found then
    return false;
  end if;

  if p_expires_at is null or
     p_expires_at <= now() or
     p_expires_at > v_previous_expiry then
    raise exception 'rotation must not prolong authenticated lifetime';
  end if;

  insert into public.certifiks_auth_sessions (
    token_digest, csrf_digest, user_id, created_at, expires_at,
    rotation_parent_digest
  ) values (
    p_new_token_digest, p_new_csrf_digest, v_user_id, now(), p_expires_at,
    p_old_token_digest
  );
  return true;
end;
$$;

revoke all on function public.certifiks_rotate_auth_session_once(
  text,text,text,text,timestamptz
) from public, anon, authenticated;
grant execute on function public.certifiks_rotate_auth_session_once(
  text,text,text,text,timestamptz
) to service_role;

grant select, insert, update on public.certifiks_auth_sessions to service_role;
