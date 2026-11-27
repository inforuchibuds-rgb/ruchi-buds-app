-- =====================================================================
-- RUCHI BUDS APP · Module 9: Backup and restore
-- File: 09_backup.sql · Version 1.0 · 27-Nov-2026
--
-- What this file sets up:
--   Restoring a backup, after confirmation by a Director or the FC:
--   - a backup file from Settings -> Backup now (file for restore) is
--     loaded from the Restore screen, or a nightly backup in Google
--     Drive is loaded by the Apps Script (stageLatestBackup);
--   - the app checks it against the database (tables, rows, columns)
--     and shows what will change;
--   - a Director or the FC types RESTORE and gives a reason. The data as
--     it is just before the restore is kept, so the restore can be undone;
--   - the restore runs as one step: either every table is reloaded and
--     every link between tables checks out, or nothing changes.
--   The audit log and the backup log are never wiped: entries from the
--   backup are added to them. The catalogue that the SQL files set up
--   (screens, rights, statement lines) is kept as it is.
--   The restore drill (spec section 12): the Apps Script can reload last
--   night's backup into a separate test copy of the database and check
--   every table's row count, without touching the live data.
--
-- Run 01 to 08 first. Then: Supabase -> SQL Editor -> New query -> paste
-- this whole file -> Run. It is safe to run again; nothing you entered
-- is lost on a re-run. If an earlier file is ever run again, run the
-- later files again straight after it, in order, ending with this one.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Screen, rights and the backup log
-- ---------------------------------------------------------------------

insert into screens (code, name, module, sort, in_menu, available, icon) values
  ('restore', 'Restore a backup', 9, 165, false, true, 'gear')
on conflict (code) do update set name = excluded.name, module = excluded.module, sort = excluded.sort,
  in_menu = excluded.in_menu, icon = excluded.icon, available = true;
insert into permissions (code, kind, screen_code, action, sort) values
  ('restore.view', 'screen', 'restore', 'view', 1651)
on conflict (code) do nothing;

-- New right: restore a backup. Not given to any category: Directors and
-- the FC always have every right, and only they should restore.
insert into powers (code, name, description, sort) values
  ('restore', 'Restore a backup', 'Reload the whole database from a backup (replaces the data entered since)', 105)
on conflict (code) do update set name = excluded.name, description = excluded.description, sort = excluded.sort;
insert into permissions (code, kind, power_code, sort) values ('power.restore', 'power', 'restore', 10105)
on conflict (code) do nothing;

alter table backup_log drop constraint if exists backup_log_kind_check;
alter table backup_log add constraint backup_log_kind_check
  check (kind in ('nightly', 'manual', 'ping', 'restore', 'sheets', 'drill'));

-- A test copy of the database (for the restore drill) is marked by
-- running "select rb_mark_test_copy();" in that project's SQL Editor.
alter table app_settings add column if not exists is_test_copy boolean not null default false;

-- ---------------------------------------------------------------------
-- 2. Tables: a restore job and the backup rows loaded into it
-- ---------------------------------------------------------------------

create table if not exists restore_jobs (
  id           bigserial primary key,
  created_at   timestamptz not null default now(),
  created_by   uuid,
  source       text not null check (source in ('file', 'drive', 'undo', 'drill')),
  label        text not null,
  taken_at     timestamptz,
  expected     jsonb not null default '{}'::jsonb,   -- {table: rows} from the backup's own list
  status       text not null default 'loading'
               check (status in ('loading', 'ready', 'applied', 'failed', 'cancelled')),
  checked      jsonb,
  approved_by  uuid,
  approved_at  timestamptz,
  reason       text,
  applied_at   timestamptz,
  applied_by   uuid,
  detail       text
);
-- No links to app_users: a restore replaces that table.
alter table restore_jobs drop constraint if exists restore_jobs_created_by_fkey;
alter table restore_jobs drop constraint if exists restore_jobs_approved_by_fkey;
alter table restore_jobs drop constraint if exists restore_jobs_applied_by_fkey;
create index if not exists restore_jobs_status_idx on restore_jobs (status, created_at desc);

create table if not exists restore_chunks (
  job_id  bigint not null references restore_jobs(id) on delete cascade,
  tbl     text not null,
  seq     int not null,
  rows    jsonb not null,
  primary key (job_id, tbl, seq)
);

alter table restore_jobs enable row level security;
alter table restore_chunks enable row level security;
revoke all on restore_jobs, restore_chunks from anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. Which tables a backup holds and how each is restored
-- ---------------------------------------------------------------------

-- Tables never backed up or restored: the restore's own working tables.
create or replace function rb_rs_internal(p_table text)
returns boolean language sql immutable as $$ select p_table in ('restore_jobs', 'restore_chunks') $$;

-- Kept as they are now: the catalogue set up by the SQL files.
create or replace function rb_rs_keep(p_table text)
returns boolean language sql immutable as $$ select p_table in ('screens', 'powers', 'permissions', 'fs_lines') $$;

-- Added to, never wiped: the logs.
create or replace function rb_rs_append(p_table text)
returns boolean language sql immutable as $$ select p_table in ('audit_log', 'backup_log') $$;

-- The backup table list now leaves out the restore's working tables
-- (replaces the version in 01_core_users.sql).
create or replace function rb_backup_tables()
returns setof text language plpgsql stable security definer set search_path = public as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    perform rb_require('power.backup_now', 'take a backup');
  end if;
  return query select table_name::text from information_schema.tables
               where table_schema = 'public' and table_type = 'BASE TABLE' and not rb_rs_internal(table_name::text)
               order by table_name;
end $$;

create or replace function rb_rs_is_table(p_table text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from information_schema.tables where table_schema = 'public' and table_type = 'BASE TABLE'
                 and table_name = p_table) and not rb_rs_internal(p_table)
$$;

-- Columns that can be written (generated columns are left out).
create or replace function rb_rs_columns(p_table text)
returns setof text language sql stable security definer set search_path = public as $$
  select column_name::text from information_schema.columns
  where table_schema = 'public' and table_name = p_table and is_generated = 'NEVER'
  order by ordinal_position
$$;

-- Who may load, check and restore: a Director or the FC (power.restore),
-- or the Apps Script with the secret key.
create or replace function rb_rs_require(p_what text)
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then perform rb_require('power.restore', p_what); end if;
end $$;

create or replace function rb_rs_job(p_job bigint)
returns restore_jobs language plpgsql stable security definer set search_path = public as $$
declare j restore_jobs;
begin
  select * into j from restore_jobs where id = p_job;
  if j.id is null then raise exception 'Backup % not found. Load it again.', p_job; end if;
  return j;
end $$;

-- ---------------------------------------------------------------------
-- 4. Loading a backup: start, add rows table by table, finish
-- ---------------------------------------------------------------------

-- p: {source: 'file'|'drive', label, taken_at, tables: {table: rows}}
create or replace function rb_restore_start(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_src text := coalesce(p->>'source', 'file');
begin
  perform rb_rs_require('load a backup for restore');
  if v_src not in ('file', 'drive', 'drill') then raise exception 'Unknown backup source %.', v_src; end if;
  if jsonb_typeof(p->'tables') is distinct from 'object' then
    raise exception 'This file is not a Ruchi Buds backup (it has no list of tables).';
  end if;
  -- One backup at a time: a backup loaded earlier and not restored is set aside.
  update restore_jobs set status = 'cancelled', detail = 'Replaced by a newer backup loaded on ' || to_char(now() at time zone 'Asia/Kolkata', 'DD-Mon-YYYY HH24:MI')
  where status in ('loading', 'ready') and source <> 'undo';
  delete from restore_chunks c using restore_jobs j where j.id = c.job_id and j.status = 'cancelled';
  insert into restore_jobs (created_by, source, label, taken_at, expected)
  values (rb_current_user_id(), v_src, left(coalesce(nullif(p->>'label', ''), 'Backup'), 200),
          nullif(p->>'taken_at', '')::timestamptz, p->'tables')
  returning id into v_id;
  return v_id;
end $$;

create or replace function rb_restore_add(p_job bigint, p_table text, p_seq int, p_rows jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare j restore_jobs := rb_rs_job(p_job);
begin
  perform rb_rs_require('load a backup for restore');
  if j.status <> 'loading' then raise exception 'This backup is no longer being loaded. Load it again.'; end if;
  if p_table !~ '^[a-z_][a-z0-9_]{0,62}$' then raise exception 'Bad table name in the backup: %.', left(p_table, 80); end if;
  if jsonb_typeof(p_rows) is distinct from 'array' then raise exception 'Bad rows for % in the backup.', p_table; end if;
  insert into restore_chunks (job_id, tbl, seq, rows) values (p_job, p_table, p_seq, p_rows)
  on conflict (job_id, tbl, seq) do update set rows = excluded.rows;
  return jsonb_array_length(p_rows);
end $$;

-- What the backup holds against what the database holds now.
create or replace function rb_rs_check(p_job bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  j restore_jobs := rb_rs_job(p_job);
  v_tables jsonb := '[]'::jsonb; v_errors jsonb := '[]'::jsonb; v_warn jsonb := '[]'::jsonb;
  t text; v_in bigint; v_exp bigint; v_now bigint; v_cols text[]; v_extra text[]; v_how text;
  v_rows bigint := 0; v_me uuid := rb_current_user_id(); v_users_gone int;
begin
  -- Every table in the backup, and every table the database has now.
  for t in select x from (select key x from jsonb_each(j.expected)
                          union select distinct tbl from restore_chunks where job_id = p_job
                          union select table_name::text from information_schema.tables
                                where table_schema = 'public' and table_type = 'BASE TABLE') s
           where not rb_rs_internal(x) order by x loop
    select coalesce(sum(jsonb_array_length(rows)), 0) into v_in from restore_chunks where job_id = p_job and tbl = t;
    v_exp := (j.expected->>t)::bigint;
    v_now := null; v_extra := null;
    if rb_rs_is_table(t) then
      execute format('select count(*) from %I', t) into v_now;
      v_cols := array(select rb_rs_columns(t));
      select array_agg(distinct k order by k) into v_extra
      from restore_chunks c, jsonb_array_elements(c.rows) r, jsonb_object_keys(r) k
      where c.job_id = p_job and c.tbl = t and k <> all (v_cols)
        and k not in (select column_name from information_schema.columns where table_schema = 'public' and table_name = t);
    end if;
    v_how := case
      when not rb_rs_is_table(t) then 'skip'
      when rb_rs_keep(t) then 'keep'
      when not (j.expected ? t) and not exists (select 1 from restore_chunks where job_id = p_job and tbl = t) then 'missing'
      when rb_rs_append(t) then 'append'
      else 'replace' end;
    if v_exp is not null and v_in <> v_exp then
      v_errors := v_errors || to_jsonb(format('%s: the backup lists %s rows but %s were loaded. Load the backup again.', t, v_exp, v_in));
    end if;
    if v_how = 'skip' then
      v_warn := v_warn || to_jsonb(format('%s is in the backup but not in this version of the app. It is left out.', t));
    end if;
    if v_how = 'missing' and v_now > 0 then
      v_warn := v_warn || to_jsonb(format('%s is not in the backup (an older version of the app). Its %s rows are kept as they are.', t, v_now));
    end if;
    if v_extra is not null then
      v_warn := v_warn || to_jsonb(format('%s: columns %s are not in this version of the app. They are left out.', t, array_to_string(v_extra, ', ')));
    end if;
    if v_how in ('replace', 'append') then v_rows := v_rows + v_in; end if;
    v_tables := v_tables || jsonb_build_object('table', t, 'backup', v_in, 'now', v_now, 'how', v_how);
  end loop;
  if not exists (select 1 from restore_chunks where job_id = p_job and tbl = 'app_users')
     or not exists (select 1 from restore_chunks where job_id = p_job and tbl = 'journals') then
    v_errors := v_errors || to_jsonb('This is not a full Ruchi Buds backup: it has no users or no journals.'::text);
  end if;
  -- Users entered after the backup lose access (their sign-in stays, but the app does not know them).
  select count(*) into v_users_gone from app_users u
  where not exists (select 1 from restore_chunks c, jsonb_array_elements(c.rows) r
                    where c.job_id = p_job and c.tbl = 'app_users' and r->>'id' = u.id::text);
  if v_users_gone > 0 then
    v_warn := v_warn || to_jsonb(format('%s user(s) set up after this backup will not be able to use the app until they are added again.', v_users_gone));
  end if;
  if v_me is not null and not exists (select 1 from restore_chunks c, jsonb_array_elements(c.rows) r
                                      where c.job_id = p_job and c.tbl = 'app_users' and r->>'id' = v_me::text) then
    v_warn := v_warn || to_jsonb('You are not a user in this backup. After the restore, you will not be able to sign in until a Director or the FC in the backup adds you again.'::text);
  end if;
  return jsonb_build_object('tables', v_tables, 'errors', v_errors, 'warnings', v_warn, 'rows', v_rows);
end $$;

create or replace function rb_restore_finish(p_job bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j restore_jobs := rb_rs_job(p_job); c jsonb;
begin
  perform rb_rs_require('load a backup for restore');
  if j.status not in ('loading', 'ready') then raise exception 'This backup is no longer waiting to be restored. Load it again.'; end if;
  c := rb_rs_check(p_job);
  update restore_jobs set status = case when jsonb_array_length(c->'errors') = 0 then 'ready' else 'failed' end,
         checked = c, detail = case when jsonb_array_length(c->'errors') = 0 then null else c->'errors'->>0 end
  where id = p_job;
  return c;
end $$;

create or replace function rb_restore_cancel(p_job bigint)
returns void language plpgsql security definer set search_path = public as $$
declare j restore_jobs := rb_rs_job(p_job);
begin
  perform rb_rs_require('set aside a backup');
  if j.status in ('applied') then raise exception 'This backup has already been restored.'; end if;
  update restore_jobs set status = 'cancelled', detail = 'Set aside' where id = p_job;
  delete from restore_chunks where job_id = p_job;
end $$;

-- The list for the Restore screen: backups loaded, undo copies and restores done.
create or replace function rb_restore_list()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform rb_rs_require('see the backups loaded for restore');
  -- Housekeeping: loaded backups not restored within 7 days, and undo
  -- copies older than 30 days, are emptied to save space.
  update restore_jobs set status = 'cancelled', detail = 'Not restored within 7 days'
  where status in ('loading', 'ready', 'failed') and source <> 'undo' and created_at < now() - interval '7 days';
  update restore_jobs set status = 'cancelled', detail = 'Undo copy kept for 30 days'
  where status = 'ready' and source = 'undo' and created_at < now() - interval '30 days';
  delete from restore_chunks c using restore_jobs j where j.id = c.job_id and j.status in ('cancelled', 'applied', 'failed');
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', j.id, 'created_at', j.created_at, 'source', j.source, 'label', j.label, 'taken_at', j.taken_at,
      'status', j.status, 'checked', j.checked, 'detail', j.detail, 'reason', j.reason,
      'applied_at', j.applied_at,
      'created_by', (select coalesce(short_name, full_name) from app_users where id = j.created_by),
      'applied_by', (select coalesce(short_name, full_name) from app_users where id = j.applied_by)) order by j.id desc)
    from (select * from restore_jobs order by id desc limit 20) j), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------
-- 5. Restoring
-- ---------------------------------------------------------------------

-- Step 1: a Director or the FC confirms (typed RESTORE and a reason).
-- The confirmation holds for one hour. The Apps Script may confirm only
-- on a test copy (the restore drill).
create or replace function rb_restore_approve(p_job bigint, p_confirm text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare j restore_jobs := rb_rs_job(p_job);
begin
  if coalesce(auth.role(), '') = 'service_role' then
    if not (select is_test_copy from app_settings where id = 1) then
      raise exception 'A restore into the live database must be confirmed in the app by a Director or the FC.';
    end if;
  else
    perform rb_require('power.restore', 'restore a backup');
  end if;
  if j.status <> 'ready' then raise exception 'This backup is not ready to restore (%).', j.status; end if;
  if upper(trim(coalesce(p_confirm, ''))) <> 'RESTORE' then raise exception 'Type RESTORE in capitals to confirm.'; end if;
  if length(trim(coalesce(p_reason, ''))) < 5 then raise exception 'Please give the reason for the restore.'; end if;
  update restore_jobs set approved_by = rb_current_user_id(), approved_at = now(), reason = trim(p_reason) where id = p_job;
  perform rb_audit_write('restore_confirmed', 'restore_jobs', p_job::text, null,
                         jsonb_build_object('label', j.label, 'taken_at', j.taken_at), trim(p_reason));
end $$;

-- Copies the data as it is now into an undo job.
drop function if exists rb_rs_snapshot(text);
create or replace function rb_rs_snapshot(p_label text, p_job bigint)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; t text; v_counts jsonb := '{}'::jsonb; n bigint;
begin
  -- Only the newest undo copy is kept (not counting the one being restored).
  update restore_jobs set status = 'cancelled', detail = 'A newer undo copy was made'
  where source = 'undo' and status = 'ready' and id <> p_job;
  delete from restore_chunks c using restore_jobs j where j.id = c.job_id and j.status = 'cancelled';
  insert into restore_jobs (created_by, source, label, taken_at, status)
  values (rb_current_user_id(), 'undo', p_label, now(), 'loading') returning id into v_id;
  for t in select x from rb_backup_tables() x loop
    execute format('insert into restore_chunks (job_id, tbl, seq, rows)
                    select $1, $2, g, jsonb_agg(r order by rn) from (
                      select to_jsonb(t) - ''temp_password_hash'' r, row_number() over (order by 1) rn,
                             ((row_number() over (order by 1)) - 1) / 2000 g from %I t) s group by g', t)
      using v_id, t;
    execute format('select count(*) from %I', t) into n;
    v_counts := v_counts || jsonb_build_object(t, n);
  end loop;
  update restore_jobs set expected = v_counts where id = v_id;
  return v_id;
end $$;

-- Step 2: the restore itself, in one transaction. Either every table is
-- reloaded and every link between tables checks out, or nothing changes.
create or replace function rb_restore_apply(p_job bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  j restore_jobs; c jsonb; v_undo bigint; t text; v_cols text; v_sel text; v_n bigint; v_total bigint := 0; v_tables int := 0;
  fk record; v_fks jsonb := '[]'::jsonb; v_list text[]; s record; v_max bigint; v_counts jsonb := '{}'::jsonb;
begin
  perform rb_rs_require('restore a backup');
  select * into j from restore_jobs where id = p_job for update;
  if j.id is null then raise exception 'Backup % not found. Load it again.', p_job; end if;
  if j.status <> 'ready' then raise exception 'This backup is not ready to restore (%).', j.status; end if;
  if j.approved_at is null or j.approved_at < now() - interval '1 hour' then
    raise exception 'A Director or the FC must confirm the restore first (the confirmation lasts one hour).';
  end if;
  c := rb_rs_check(p_job);
  if jsonb_array_length(c->'errors') > 0 then raise exception '%', c->'errors'->>0; end if;

  -- The data as it is now, so the restore can be undone.
  v_undo := rb_rs_snapshot(case when j.source = 'undo' then 'Data as it was just before the undo on ' || to_char(now() at time zone 'Asia/Kolkata', 'DD-Mon-YYYY HH24:MI')
                                else 'Data as it was just before restoring "' || j.label || '"' end, p_job);

  -- The tables to reload or add to.
  select array_agg(x->>'table' order by x->>'table') into v_list
  from jsonb_array_elements(c->'tables') x where x->>'how' in ('replace', 'append');

  -- Links between tables are taken off, and checked again at the end.
  for fk in select conrelid::regclass::text tbl, conname, pg_get_constraintdef(oid) def
            from pg_constraint where contype = 'f' and connamespace = 'public'::regnamespace
              and not rb_rs_internal(conrelid::regclass::text) and not rb_rs_internal(confrelid::regclass::text) loop
    v_fks := v_fks || jsonb_build_object('tbl', fk.tbl, 'name', fk.conname, 'def', fk.def);
    execute format('alter table %s drop constraint %I', fk.tbl, fk.conname);
  end loop;

  foreach t in array v_list loop
    execute format('alter table %I disable trigger user', t);
  end loop;
  execute (select 'truncate table ' || string_agg(format('%I', x), ', ')
           from unnest(v_list) x where not rb_rs_append(x));

  foreach t in array v_list loop
    select string_agg(format('%I', col), ', '), string_agg(format('x.%I', col), ', ') into v_cols, v_sel
    from rb_rs_columns(t) col
    where exists (select 1 from restore_chunks ch, jsonb_array_elements(ch.rows) r
                  where ch.job_id = p_job and ch.tbl = t and r ? col);
    if v_cols is not null then
      execute format('insert into %I (%s) select %s from restore_chunks ch, jsonb_populate_recordset(null::%I, ch.rows) x
                      where ch.job_id = $1 and ch.tbl = $2 %s',
                     t, v_cols, v_sel, t, case when rb_rs_append(t) then 'on conflict do nothing' else '' end)
        using p_job, t;
      get diagnostics v_n = row_count;
    else
      v_n := 0;
    end if;
    v_total := v_total + v_n; v_tables := v_tables + 1;
    v_counts := v_counts || jsonb_build_object(t, v_n);
  end loop;

  -- Put the links back: this checks every row points to a row that exists.
  for fk in select x->>'tbl' tbl, x->>'name' conname, x->>'def' def from jsonb_array_elements(v_fks) x loop
    begin
      execute format('alter table %s add constraint %I %s', fk.tbl, fk.conname, fk.def);
    exception when foreign_key_violation then
      raise exception 'The backup does not hold together: some rows in % point to rows that are not in the backup (%). Nothing was changed.',
        fk.tbl, fk.conname;
    end;
  end loop;

  foreach t in array v_list loop
    execute format('alter table %I enable trigger user', t);
  end loop;

  -- Number counters carry on after the highest number restored.
  for s in select tc.relname tbl, a.attname col, pg_get_serial_sequence(format('%I', tc.relname), a.attname) seq
           from pg_class tc join pg_attribute a on a.attrelid = tc.oid
           where tc.relnamespace = 'public'::regnamespace and tc.relkind = 'r' and a.attnum > 0 and not a.attisdropped
             and pg_get_serial_sequence(format('%I', tc.relname), a.attname) is not null
             and tc.relname = any (v_list) loop
    execute format('select max(%I) from %I', s.col, s.tbl) into v_max;
    if v_max is null then perform setval(s.seq, 1, false); else perform setval(s.seq, v_max, true); end if;
  end loop;

  update restore_jobs set status = 'applied', applied_at = now(), applied_by = rb_current_user_id(),
         detail = format('%s tables, %s rows restored', v_tables, v_total) where id = p_job;
  update restore_jobs set status = 'ready', checked = rb_rs_check(v_undo) where id = v_undo;
  delete from restore_chunks where job_id = p_job;
  insert into backup_log (kind, status, tables, rows, detail)
  values ('restore', 'ok', v_tables, v_total, left(format('Restored "%s" (taken %s). Reason: %s',
          j.label, coalesce(to_char(j.taken_at at time zone 'Asia/Kolkata', 'DD-Mon-YYYY HH24:MI'), 'date not known'), j.reason), 2000));
  perform rb_audit_write('restore', 'restore_jobs', p_job::text, null,
                         jsonb_build_object('label', j.label, 'taken_at', j.taken_at, 'rows', v_counts, 'undo_job', v_undo), j.reason);
  return jsonb_build_object('tables', v_tables, 'rows', v_total, 'undo_job', v_undo, 'counts', v_counts);
end $$;

-- ---------------------------------------------------------------------
-- 6. The restore drill (on a separate test copy of the database)
-- ---------------------------------------------------------------------

-- Run once in the TEST project's SQL Editor: "select rb_mark_test_copy();"
-- Only someone with access to that project's SQL Editor can run it.
create or replace function rb_mark_test_copy()
returns text language plpgsql security definer set search_path = public as $$
begin
  update app_settings set is_test_copy = true where id = 1;
  return 'This database is now marked as a test copy. The Apps Script can run the restore drill on it.';
end $$;

-- Row counts after the drill, to compare with the backup.
create or replace function rb_restore_counts()
returns jsonb language plpgsql security definer set search_path = public as $$
declare t text; n bigint; v jsonb := '{}'::jsonb;
begin
  perform rb_rs_require('count the rows');
  for t in select x from rb_backup_tables() x loop
    execute format('select count(*) from %I', t) into n;
    v := v || jsonb_build_object(t, n);
  end loop;
  return v;
end $$;

-- ---------------------------------------------------------------------
-- 7. Grants
-- ---------------------------------------------------------------------

do $$
declare f record;
begin
  for f in select p.oid::regprocedure::text sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and (p.proname like 'rb\_rs\_%' or p.proname like 'rb\_restore\_%'
                                           or p.proname in ('rb_mark_test_copy', 'rb_backup_tables')) loop
    execute format('revoke execute on function %s from public, anon, authenticated, service_role', f.sig);
  end loop;
end $$;
grant execute on function rb_backup_tables(), rb_restore_start(jsonb), rb_restore_add(bigint, text, int, jsonb),
  rb_restore_finish(bigint), rb_restore_cancel(bigint), rb_restore_list(), rb_restore_approve(bigint, text, text),
  rb_restore_apply(bigint), rb_restore_counts()
to authenticated, service_role;

-- End of 09_backup.sql
