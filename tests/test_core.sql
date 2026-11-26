-- Behaviour tests for 01_core_users.sql. Run against a throwaway database only.
\set ON_ERROR_STOP 1
set client_min_messages = warning;
create or replace function public.t_err(p_sql text, p_like text) returns void language plpgsql as $$
begin
  begin execute p_sql;
  exception when others then
    if sqlerrm not ilike '%'||p_like||'%' then raise exception 'FAIL: % -> wrong error: %', p_sql, sqlerrm; end if;
    raise notice 'ok (blocked): %', left(sqlerrm, 90); return;
  end;
  raise exception 'FAIL: expected error "%" from: %', p_like, p_sql;
end $$;
grant execute on function public.t_err(text, text) to anon, authenticated;
create or replace function public.t_ok(p boolean, p_what text) returns void language plpgsql as $$
begin if not coalesce(p, false) then raise exception 'FAIL: %', p_what; end if; raise notice 'ok: %', p_what; end $$;
grant execute on function public.t_ok(boolean, text) to anon, authenticated;
set client_min_messages = notice;

-- 1. A login for an email that was never invited is refused
select t_err($$insert into auth.users(email) values ('stranger@example.com')$$, 'not been invited');

-- 2. DS sets up a login and becomes active
insert into auth.users(id, email) values ('00000000-0000-0000-0000-0000000000d1', 'INFO.RuchiBuds@gmail.com');
select t_ok((select status = 'active' from app_users where email = 'info.ruchibuds@gmail.com'), 'DS is active after first sign-in');

-- become DS
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
select t_ok(jsonb_array_length(rb_login_ok()->'permissions') = (select count(*) from permissions), 'DS has every permission');
select t_ok((select count(*) from app_users) = 11, 'DS sees all 11 users');
select rb_invite_user('acc@example.com', 'Real Accountant', 'RA', null, (select id from user_categories where name='Accountant'), '2027-01-31') \gset
select rb_invite_user('staff@example.com', 'Real Staff', 'RS', null, (select id from user_categories where name='Staff'), null) \gset
select rb_invite_user('fc@example.com', 'Real FC', 'FC', null, (select id from user_categories where name='Financial Controller'), null) \gset
select rb_invite_user('dir2@example.com', 'Second Director', 'D2', null, (select id from user_categories where name='Director'), null) \gset
select t_err($$select rb_invite_user('ACC@example.com','Dup','X',null,3::smallint,null)$$, 'already exists');
reset role;
insert into auth.users(id, email) values
 ('00000000-0000-0000-0000-0000000000a1', 'acc@example.com'),
 ('00000000-0000-0000-0000-0000000000c1', 'staff@example.com'),
 ('00000000-0000-0000-0000-0000000000f1', 'fc@example.com'),
 ('00000000-0000-0000-0000-0000000000d2', 'dir2@example.com');

-- 3. Accountant: can add users but not hand out higher categories or edit the grid
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select t_ok(rb_has('users.add') and not rb_has('power.manage_access'), 'Accountant can add users, cannot manage access');
select t_err($$select rb_invite_user('x@example.com','X','X',null,(select id from user_categories where name='Director'),null)$$, 'more rights than your own');
select t_err($$select rb_invite_user('x@example.com','X','X',null,(select id from user_categories where name='Staff'),'2027-01-01')$$, 'Only a Director or FC');
select t_ok(rb_invite_user('newstaff@example.com','New Staff','NS',null,(select id from user_categories where name='Staff'),null) is not null, 'Accountant invites a Staff user');
select t_err($$select rb_set_category_access((select id from user_categories where name='Staff'),'sales.margin',true)$$, 'right to change the access grid');
select t_err($$select rb_reset_password((select id from app_users where email='staff@example.com'),'Temp1234!')$$, 'right to reset passwords');
select t_ok((select count(*) from audit_log) > 0, 'Accountant can read the audit log');
select t_ok((select count(*) from password_reset_requests) = 0, 'Accountant sees no reset requests');

-- 4. Staff: sees only their own row, no audit, cannot add users
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
select t_ok((select count(*) from app_users) = 1, 'Staff sees only their own user row');
select t_ok((select count(*) from audit_log) = 0, 'Staff cannot read the audit log');
select t_ok(not rb_has('power.see_totals') and rb_has('sales.add'), 'Staff: counter sales without totals');
select t_err($$select rb_invite_user('y@example.com','Y','Y',null,8::smallint,null)$$, 'right to add users');
select t_err($$update app_settings set firm_name='Hacked'$$, 'permission denied');
select t_err($$insert into audit_log(action) values ('x')$$, 'permission denied');
select t_err($$select rb_ping()$$, 'permission denied');

-- 5. Wrong passwords lock the account; Accountant unlocks
set role anon;
select rb_login_failed('staff@example.com') from generate_series(1,5);
select t_err($$select * from app_users$$, 'permission denied');
select t_ok((rb_public_branding()->>'firm_name') = 'Ruchi Buds', 'Login screen can read the firm name');
select t_err($$select rb_my_profile()$$, 'permission denied');
set role authenticated;
select t_ok(rb_current_user_id() is null and not rb_has('sales.view') and (select count(*) from screens) = 0, 'Locked staff gets no rights or data (only their own user row, to show the locked message)');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select t_ok((select status from app_users where email='staff@example.com') = 'locked', 'Staff locked after 5 wrong passwords');
select rb_unlock_user((select id from app_users where email='staff@example.com'));
select t_ok((select status from app_users where email='staff@example.com') = 'active', 'Accountant unlocked Staff');

-- 6. Password resets
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select t_ok(rb_reset_password((select id from app_users where email='acc@example.com'), 'Temp1234!') = 'done', 'DS resets Accountant directly');
select t_ok((select must_change_password from app_users where email='acc@example.com'), 'Accountant must choose a new password');
select t_ok(rb_reset_password((select id from app_users where email='fc@example.com'), 'Temp5678!') = 'pending', 'Reset of FC waits for approval');
select t_err($$select rb_decide_password_reset((select max(id) from password_reset_requests), true)$$, 'different Director or FC');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f1', false);
select t_err($$select rb_decide_password_reset((select max(id) from password_reset_requests), true)$$, 'different Director or FC');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d2', false);
select rb_decide_password_reset((select max(id) from password_reset_requests), true);
reset role;
select t_ok((select encrypted_password = extensions.crypt('Temp5678!', encrypted_password) from auth.users where email='fc@example.com'), 'Second Director approved; FC temp password works');
select t_ok((select temp_password_hash is null from password_reset_requests order by id desc limit 1), 'Stored hash is wiped after the decision');
set role authenticated;

-- 7. Categories, tick grid and per-user ticks
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select rb_create_category('Packer', 'Staff', 'Packs orders') \gset
select t_ok((select count(*) from category_access where category_id = :rb_create_category) = 4, 'New category starts with Staff ticks');
select rb_set_category_access(:rb_create_category::smallint, 'stock.view', true);
select t_err($$select rb_set_category_access(1::smallint,'sales.view',false)$$, 'always have every tick');
select rb_set_user_access((select id from app_users where email='staff@example.com'), 'sales.margin', true);
select rb_set_user_access((select id from app_users where email='staff@example.com'), 'sales.add', false);
select t_ok(rb_user_has((select id from app_users where email='staff@example.com'), 'sales.margin')
        and not rb_user_has((select id from app_users where email='staff@example.com'), 'sales.add'), 'Per-user ticks override the category');
select t_err($$select rb_set_user_access(rb_current_user_id(),'sales.view',false)$$, 'your own access');
select rb_rename_category(:rb_create_category::smallint, 'Packing staff', null);
select rb_delete_category(:rb_create_category::smallint);
select t_err($$select rb_delete_category((select id from user_categories where name='Staff'))$$, 'still used');
select t_ok((select count(*) from audit_log where table_name='category_access') >= 2, 'Grid changes are in the audit log');

-- 8. Audit log cannot be changed, even by the database owner via the API
reset role;
select t_err($$delete from audit_log$$, 'cannot be changed');
set role authenticated;

-- 9. Document numbers never restart
reset role;
select t_ok(rb_next_doc_no('DEMO', '2026-11-26') = 'DEMO/2611/00001' and rb_next_doc_no('DEMO', '2027-04-02') = 'DEMO/2704/00002', 'Numbers run on across months');
set role authenticated;

-- 10. Remove demo data, then go live
select t_err($$select rb_remove_demo_data('yes')$$, 'REMOVE DEMO');
select rb_remove_demo_data('REMOVE DEMO');
select t_ok(not exists (select 1 from app_users where is_demo) and not exists (select 1 from user_categories where is_demo), 'All DEMO users and categories removed');
select rb_go_live('2027-04-01', 'GO LIVE');
select t_ok((select not training_mode and go_live_date = '2027-04-01' from app_settings), 'Go-live switches training mode off');

-- 11. Service role (the Apps Script) can list tables, ping and log
reset role;
set role service_role;
select set_config('request.jwt.claim.role', 'service_role', false);
select t_ok((select count(*) from rb_backup_tables()) = 12, 'Backup sees all 12 tables');
select t_ok(rb_ping() is not null, 'Keep-awake ping works');
select rb_log_backup('nightly', 'ok', 12, 100, 'test');
reset role;
\echo ALL TESTS PASSED
