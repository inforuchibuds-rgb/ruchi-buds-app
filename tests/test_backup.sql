-- Behaviour tests for 09_backup.sql. Run against a throwaway database only,
-- after supabase_stub.sql and sql/01 to sql/09, from the tests/ folder.
\set ON_ERROR_STOP 1
set client_min_messages = warning;
create or replace function public.t_err(p_sql text, p_like text) returns void language plpgsql as $$
begin
  begin execute p_sql;
  exception when others then
    if sqlerrm not ilike '%'||p_like||'%' then raise exception 'FAIL: % -> wrong error: %', p_sql, sqlerrm; end if;
    raise notice 'ok (blocked): %', left(sqlerrm, 110); return;
  end;
  raise exception 'FAIL: expected error "%" from: %', p_like, p_sql;
end $$;
grant execute on function public.t_err(text, text) to anon, authenticated, service_role;
create or replace function public.t_ok(p boolean, p_what text) returns void language plpgsql as $$
begin if not coalesce(p, false) then raise exception 'FAIL: %', p_what; end if; raise notice 'ok: %', p_what; end $$;
grant execute on function public.t_ok(boolean, text) to anon, authenticated, service_role;

-- A fingerprint of every restored table (the logs and the catalogue left out).
create or replace function public.t_state() returns jsonb language plpgsql security definer set search_path = public as $$
declare t text; h text; v jsonb := '{}'::jsonb;
begin
  for t in select table_name::text from information_schema.tables where table_schema = 'public' and table_type = 'BASE TABLE'
           and table_name not in ('restore_jobs', 'restore_chunks', 'audit_log', 'backup_log', 'screens', 'powers', 'permissions', 'fs_lines')
           and table_name not like 't\_%' order by 1 loop
    execute format('select coalesce(md5(string_agg(x, ''|'' order by x)), ''empty'') from (select (to_jsonb(t) - ''temp_password_hash'')::text x from %I t) s', t) into h;
    v := v || jsonb_build_object(t, h);
  end loop;
  return v;
end $$;
grant execute on function public.t_state() to authenticated, service_role;
create or replace function public.t_diff(a jsonb, b jsonb) returns text language sql as $$
  select coalesce(string_agg(k, ', '), '') from jsonb_object_keys(a) k where a->>k is distinct from b->>k $$;
grant execute on function public.t_diff(jsonb, jsonb) to authenticated, service_role;
create or replace function public.t_job(p bigint) returns restore_jobs language sql security definer set search_path = public as $$
  select * from restore_jobs where id = p $$;
grant execute on function public.t_job(bigint) to authenticated, service_role;

-- A backup taken the way the app takes it (rb_backup_tables + rb_backup_rows), kept aside.
create schema if not exists tst;
grant usage on schema tst to authenticated, service_role;
create table tst.t_bk (tbl text, seq int, rows jsonb);
grant all on tst.t_bk to authenticated, service_role;
create or replace function public.t_capture() returns int language plpgsql as $$
declare t text; off int; pg jsonb; n int := 0;
begin
  delete from tst.t_bk;
  for t in select x from rb_backup_tables() x loop
    off := 0;
    loop
      pg := rb_backup_rows(t, off, 700);
      insert into tst.t_bk values (t, off / 700, pg); n := n + jsonb_array_length(pg);
      exit when jsonb_array_length(pg) < 700; off := off + 700;
    end loop;
  end loop;
  return n;
end $$;
grant execute on function public.t_capture() to authenticated, service_role;
-- Loads the kept backup into a restore job, as the Restore screen does.
create or replace function public.t_stage(p_label text) returns bigint language plpgsql as $$
declare j bigint;
begin
  j := rb_restore_start(jsonb_build_object('source', 'file', 'label', p_label, 'taken_at', now(),
         'tables', (select jsonb_object_agg(tbl, n) from (select tbl, sum(jsonb_array_length(rows)) n from tst.t_bk group by tbl) s)));
  perform rb_restore_add(j, tbl, seq, rows) from tst.t_bk order by tbl, seq;
  return j;
end $$;
grant execute on function public.t_stage(text) to authenticated, service_role;

-- 0. The file is in place
select t_ok(exists (select 1 from permissions where code = 'power.restore'), 'New right: restore a backup');
select t_ok((select available and not in_menu from screens where code = 'restore'), 'Restore screen exists (reached from Settings)');
select set_config('request.jwt.claim.role', 'service_role', false);
select t_ok(not exists (select 1 from rb_backup_tables() x where x like 'restore\_%'), 'Backups leave out the restore working tables');

-- People
insert into auth.users(id, email) values ('00000000-0000-0000-0000-0000000000d1', 'info.ruchibuds@gmail.com');
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
select rb_login_ok() is not null;
select rb_invite_user('acc@example.com', 'Real Accountant', 'RA', null, (select id from user_categories where name='Accountant'), null);
reset role;
insert into auth.users(id, email) values ('00000000-0000-0000-0000-0000000000a1', 'acc@example.com');
set role authenticated;
\set dir '00000000-0000-0000-0000-0000000000d1'
\set acc '00000000-0000-0000-0000-0000000000a1'

-- 1. Rights: the Accountant can take a backup but not restore one
select set_config('request.jwt.claim.sub', :'acc', false);
select rb_login_ok() is not null;
select t_ok((select count(*) from rb_backup_tables()) > 50, 'The Accountant can take a backup');
select t_err($$select rb_restore_start('{"tables":{}}')$$, 'restore');
select t_err($$select rb_restore_list()$$, 'restore');
select t_err($$select rb_restore_approve(1, 'RESTORE', 'Testing it')$$, 'not found');
select t_err($$select count(*) from restore_jobs$$, 'permission denied');

-- 2. DS takes a backup (state A), then the books change (state B)
select set_config('request.jwt.claim.sub', :'dir', false);
select t_ok(t_capture() > 500, 'Backup taken through the app''s backup functions');
reset role;
create table tst.t_states (k text primary key, v jsonb);
insert into tst.t_states values ('A', t_state());
-- Changes after the backup: a journal, a new user, a settings change, a deleted DEMO customer note.
select rb_post_engine(jsonb_build_object('journal_date', '2026-11-20', 'source', 'manual', 'narration', 'After the backup', 'department_id', rb_pur_default_dept()),
  jsonb_build_array(jsonb_build_object('account_code', '10010110', 'debit_paise', 123400),
                    jsonb_build_object('account_code', '60010120', 'credit_paise', 123400)));
set role authenticated;
select rb_invite_user('late@example.com', 'Late Joiner', 'LJ', null, (select id from user_categories where name='Manager'), null);
reset role;
update app_settings set firm_name = 'Ruchi Buds (changed)' where id = 1;
insert into tst.t_states values ('B', t_state());
select t_ok(t_diff((select v from tst.t_states where k='A'), (select v from tst.t_states where k='B')) like '%journals%', 'The books changed after the backup');
select count(*) as audit_before from audit_log \gset
set role authenticated;

-- 3. Load the backup and check it
select t_stage('Backup file 20-Nov') as job \gset
select t_err($$select rb_restore_apply($$ || :job || $$)$$, 'not ready');
select t_ok((select rb_restore_finish(:job)->'errors') = '[]'::jsonb, 'The backup checks out');
select t_ok((select x->>'status' from jsonb_array_elements(rb_restore_list()) x where (x->>'id')::bigint = :job) = 'ready', 'It is ready to restore');
select t_ok((select checked->'warnings' from t_job(:job))::text like '%1 user(s) set up after this backup%', 'Warns that the user added later loses access');
select t_ok((select x->>'how' from jsonb_array_elements((select checked->'tables' from t_job(:job))) x where x->>'table' = 'audit_log') = 'append'
        and (select x->>'how' from jsonb_array_elements((select checked->'tables' from t_job(:job))) x where x->>'table' = 'permissions') = 'keep'
        and (select x->>'how' from jsonb_array_elements((select checked->'tables' from t_job(:job))) x where x->>'table' = 'journals') = 'replace',
        'Logs are added to, the catalogue is kept, the books are replaced');

-- 4. Confirmation by a Director or the FC
select t_err($$select rb_restore_apply($$ || :job || $$)$$, 'must confirm');
select t_err($$select rb_restore_approve($$ || :job || $$, 'restore please', 'Wrong entries')$$, 'Type RESTORE');
select t_err($$select rb_restore_approve($$ || :job || $$, 'RESTORE', '')$$, 'reason');
select set_config('request.jwt.claim.sub', :'acc', false);
select t_err($$select rb_restore_approve($$ || :job || $$, 'RESTORE', 'Wrong entries')$$, 'restore');
select set_config('request.jwt.claim.sub', :'dir', false);
select rb_restore_approve(:job, 'restore', 'Wrong entries posted on 20-Nov');

-- 5. Restore
select rb_restore_apply(:job) as res \gset
reset role;
select t_ok(t_diff((select v from tst.t_states where k='A'), t_state()) = '', 'After the restore every table is exactly as in the backup');
select t_ok((select firm_name from app_settings) = 'Ruchi Buds', 'Settings are back as they were');
select t_ok((select count(*) from audit_log) > :audit_before, 'The audit log was not wiped');
select t_ok(exists (select 1 from audit_log where action = 'restore' and note = 'Wrong entries posted on 20-Nov'), 'The restore is in the audit log with its reason');
select t_ok(exists (select 1 from backup_log where kind = 'restore' and status = 'ok' and detail like '%Backup file 20-Nov%'), 'The restore is in the backup log');
select t_ok((select status from t_job(:job)) = 'applied' and not exists (select 1 from restore_chunks where job_id = :job),
            'The job is marked restored and its rows are cleared');
-- Number counters carry on: new entries after the restore get new numbers.
select t_ok(rb_post_engine(jsonb_build_object('journal_date', '2026-11-21', 'source', 'manual', 'narration', 'After the restore', 'department_id', rb_pur_default_dept()),
  jsonb_build_array(jsonb_build_object('account_code', '10010110', 'debit_paise', 5000),
                    jsonb_build_object('account_code', '60010120', 'credit_paise', 5000))) is not null, 'New entries can be posted after the restore');
set role authenticated;
select t_err($$select rb_restore_apply($$ || :job || $$)$$, 'not ready');

-- 6. Undo the restore: back to state B (plus the entry just posted)
select (x->>'id')::bigint as undo from jsonb_array_elements(rb_restore_list()) x where x->>'source' = 'undo' and x->>'status' = 'ready' \gset
select t_ok((select checked->'errors' from t_job(:undo)) = '[]'::jsonb, 'An undo copy was kept and checks out');
reset role;
delete from journal_lines where journal_id = (select id from journals where narration = 'After the restore');
delete from journals where narration = 'After the restore';
set role authenticated;
select rb_restore_approve(:undo, 'RESTORE', 'Undo the test restore');
select rb_restore_apply(:undo);
reset role;
select t_ok(t_diff((select v from tst.t_states where k='B'), t_state()) = '', 'Undo brings back the data as it was just before the restore');
select t_ok((select firm_name from app_settings) = 'Ruchi Buds (changed)', 'Settings are as before the restore');
set role authenticated;

-- 7. A broken backup changes nothing
reset role;
update tst.t_bk set rows = (select jsonb_agg(r) from jsonb_array_elements(rows) r
                        where (r->>'id')::bigint <> (select min(journal_id) from journal_lines))
where tbl = 'journals';
insert into tst.t_states values ('C', t_state());
set role authenticated;
select t_stage('Broken backup') as bad \gset
select t_ok((select rb_restore_finish(:bad)->'errors') = '[]'::jsonb, 'Row counts of the broken backup agree (the gap is found at restore)');
select rb_restore_approve(:bad, 'RESTORE', 'Testing a broken backup');
select t_err($$select rb_restore_apply($$ || :bad || $$)$$, 'does not hold together');
reset role;
select t_ok(t_diff((select v from tst.t_states where k='C'), t_state()) = '', 'Nothing changed after the failed restore');
select t_ok(exists (select 1 from pg_constraint where conname = 'journal_lines_journal_id_fkey'), 'The links between tables are still in place');

-- 8. An incomplete load is refused
set role authenticated;
select rb_restore_start(jsonb_build_object('label', 'Half a file', 'tables', '{"journals": 5000, "app_users": 1}'::jsonb)) as half \gset
select rb_restore_add(:half, 'app_users', 0, (select rows from tst.t_bk where tbl = 'app_users' and seq = 0));
select t_ok((select (rb_restore_finish(:half)->'errors')::text) like '%journals: the backup lists 5000 rows but 0 were loaded%', 'A part-loaded backup is refused');
select t_err($$select rb_restore_approve($$ || :half || $$, 'RESTORE', 'Testing a half file')$$, 'not ready');
select t_err($$select rb_restore_start('{"label":"x"}')$$, 'not a Ruchi Buds backup');
select t_err($$select rb_restore_add($$ || :half || $$, 'drop table x', 0, '[]')$$, 'no longer being loaded');

-- 9. A backup from an older version: a table missing, an extra column, an unknown table
reset role;
select t_capture() is not null from (select set_config('request.jwt.claim.sub', :'dir', false)) s;
delete from tst.t_bk where tbl = 'fs_map';
update tst.t_bk set rows = (select jsonb_agg(r || '{"old_column": 1}') from jsonb_array_elements(rows) r) where tbl = 'units';
insert into tst.t_bk values ('old_table', 0, '[{"id": 1}]');
select count(*) as fsmap from fs_map \gset
set role authenticated;
select t_stage('Older backup') as old \gset
select rb_restore_finish(:old)->'warnings' as w \gset
select t_ok(:'w' like '%fs_map is not in the backup%' and :'w' like '%units: columns old_column%' and :'w' like '%old_table is in the backup but not in this version%',
            'Older backups: missing tables kept, extra columns and tables left out');
select rb_restore_approve(:old, 'RESTORE', 'Testing an older backup');
select rb_restore_apply(:old);
reset role;
select t_ok((select count(*) from fs_map) = :fsmap, 'A table missing from the backup is kept as it is');

-- 10. The Apps Script (secret key): may load, but confirms only on a test copy
set role service_role;
select set_config('request.jwt.claim.sub', '', false);
select set_config('request.jwt.claim.role', 'service_role', false);
select rb_restore_start(jsonb_build_object('source', 'drive', 'label', 'Drive 2026-11-26', 'tables',
         (select jsonb_object_agg(tbl, n) from (select tbl, sum(jsonb_array_length(rows)) n from tst.t_bk where tbl <> 'old_table' group by tbl) s))) as drv \gset
select count(*) from (select rb_restore_add(:drv, tbl, seq, rows) from tst.t_bk where tbl <> 'old_table') s;
select t_ok((select rb_restore_finish(:drv)->'errors') = '[]'::jsonb, 'The Apps Script can load a Drive backup');
select t_err($$select rb_restore_approve($$ || :drv || $$, 'RESTORE', 'Restore drill')$$, 'must be confirmed in the app');
select t_err($$select rb_restore_apply($$ || :drv || $$)$$, 'must confirm');
select t_err($$select rb_mark_test_copy()$$, 'permission denied');
reset role;
select rb_mark_test_copy();
set role service_role;
select rb_restore_approve(:drv, 'RESTORE', 'Restore drill');
select rb_restore_apply(:drv);
select t_ok((select bool_and((rb_restore_counts()->>tbl)::bigint = n)
             from (select tbl, sum(jsonb_array_length(rows)) n from tst.t_bk where tbl not in ('old_table', 'audit_log', 'backup_log', 'screens', 'powers', 'permissions', 'fs_lines') group by tbl) s),
            'Drill: every table has the row count of the backup');
reset role;
update app_settings set is_test_copy = false;

-- 11. Running 09 again keeps the restore history
\i ../sql/09_backup.sql
select t_ok((select count(*) from restore_jobs where status = 'applied') = 4, 'Re-running 09 keeps the restore history');

-- 12. Remove demo data still works after a restore
set role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', false);
select set_config('request.jwt.claim.sub', :'dir', false);
select rb_remove_demo_data('REMOVE DEMO') is not null;
reset role;
select t_ok(not exists (select 1 from journals where is_demo), 'Remove demo data works after a restore');

select 'ALL MODULE 9 TESTS PASSED';
