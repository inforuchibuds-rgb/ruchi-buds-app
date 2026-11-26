-- =====================================================================
-- RUCHI BUDS APP · 00_reset.sql · Version 1.0 · 26-Nov-2026
--
-- DANGER: this wipes EVERY table, setting, user and audit entry of the
-- app, so you can start again from an empty database. Take a backup
-- first (Settings -> Backup now). Run it only on purpose.
--
-- Logins in Supabase -> Authentication -> Users are kept. Delete them
-- there too if you want people to set up their passwords again.
--
-- After running this, run 01_core_users.sql (and any later module
-- files, in number order) to rebuild.
-- =====================================================================

drop trigger if exists rb_on_auth_user_created on auth.users;

do $$
declare r record;
begin
  -- Drop every app table (anything in public created by the module files).
  for r in select tablename from pg_tables where schemaname = 'public' loop
    execute format('drop table if exists public.%I cascade', r.tablename);
  end loop;
  -- Drop every app function (all start with rb_).
  for r in select p.oid::regprocedure as f from pg_proc p
           join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'rb\_%' loop
    execute format('drop function if exists %s cascade', r.f);
  end loop;
end $$;

-- End of 00_reset.sql
