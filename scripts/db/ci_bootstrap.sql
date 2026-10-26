-- Minimal Supabase permission shim for ephemeral CI PostgreSQL.
-- Production uses the real Supabase-managed auth schema and roles.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin;
  end if;
end;
$$;
create schema if not exists auth;
create or replace function auth.role() returns text
language sql stable as $$
  select current_setting('request.jwt.claim.role', true)::text
$$;
