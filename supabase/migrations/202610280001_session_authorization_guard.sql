-- Issue #23: an atomic, server-only decision for an active session and
-- a particular workspace role. This is NOT a wallet signature verifier
-- and MUST NOT enable sign-in or financial API handlers on its own.
create or replace function public.certifiks_authorize_session_v1(
  p_token_digest text,
  p_organization_id uuid,
  p_required_role text,
  p_require_csrf boolean,
  p_csrf_digest text
) returns table (user_id uuid, expires_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'session lookup is service-role only';
  end if;

  if p_token_digest is null or
     p_token_digest !~ '^[0-9a-f]{64}$' or
     p_organization_id is null or
     p_required_role is null or
     p_required_role not in (
       'sponsor','developer','maintainer',
       'verifier','arbitrator','operator'
     ) or
     p_require_csrf is null or
     (p_require_csrf and (
       p_csrf_digest is null or p_csrf_digest !~ '^[0-9a-f]{64}$'
     ))
  then
    return;
  end if;

  return query
  select s.user_id, s.expires_at
  from public.certifiks_auth_sessions s
  join public.certifiks_auth_users u
    on u.user_id = s.user_id
  join public.certifiks_auth_role_memberships m
    on m.user_id = s.user_id
   and m.organization_id = p_organization_id
   and m.role = p_required_role
  where s.token_digest = p_token_digest
    and s.revoked_at is null
    and s.created_at <= now()
    and s.expires_at > now()
    and u.disabled_at is null
    and m.revoked_at is null
    and (not p_require_csrf or s.csrf_digest = p_csrf_digest);
end;
$$;

revoke all on function public.certifiks_authorize_session_v1(
  text,uuid,text,boolean,text
) from public, anon, authenticated;
grant execute on function public.certifiks_authorize_session_v1(
  text,uuid,text,boolean,text
) to service_role;

-- Session identifiers, CSRF values and role membership remain in private
-- service-role tables. The user/browser cannot call the decision function.
