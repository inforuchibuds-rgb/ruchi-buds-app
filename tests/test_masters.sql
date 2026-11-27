-- Behaviour tests for 02_masters.sql. Run against a throwaway database only,
-- after supabase_stub.sql, 01_core_users.sql and 02_masters.sql.
\set ON_ERROR_STOP 1
set client_min_messages = warning;
create or replace function public.t_err(p_sql text, p_like text) returns void language plpgsql as $$
begin
  begin execute p_sql;
  exception when others then
    if sqlerrm not ilike '%'||p_like||'%' then raise exception 'FAIL: % -> wrong error: %', p_sql, sqlerrm; end if;
    raise notice 'ok (blocked): %', left(sqlerrm, 100); return;
  end;
  raise exception 'FAIL: expected error "%" from: %', p_like, p_sql;
end $$;
grant execute on function public.t_err(text, text) to anon, authenticated;
create or replace function public.t_ok(p boolean, p_what text) returns void language plpgsql as $$
begin if not coalesce(p, false) then raise exception 'FAIL: %', p_what; end if; raise notice 'ok: %', p_what; end $$;
grant execute on function public.t_ok(boolean, text) to anon, authenticated;
-- Sum of a trial balance column, for checks.
create or replace function public.t_tb(p_from date, p_to date, p_code text) returns bigint language sql as $$
  select closing_paise from rb_trial_balance(p_from, p_to) where account_code = p_code $$;
grant execute on function public.t_tb(date, date, text) to authenticated;
set client_min_messages = notice;

-- 0. Chart of accounts loaded
select t_ok((select count(*) from accounts where level = 'posting' and source = 'master') = 509, '509 Master COA posting accounts loaded');
select t_ok((select count(*) from accounts where level = 'family') = 73, '73 family headers loaded');
select t_ok((select not e002_active from accounts where code = '20020105'), 'Right-of-use assets hidden for Indian AS');
select t_ok((select not e002_active from accounts where code = '10020205'), 'Expected credit loss allowance hidden');
select t_ok((select e002_active and source = 'local' from accounts where code = '70010160'), 'Cost of finished goods sold added for E002');
select t_ok((select cash_flow from accounts where code = '10010110') = 'cash' and (select cash_flow from accounts where code = '20010125') = 'investing'
        and (select cash_flow from accounts where code = '40010105') = 'financing', 'Cash-flow categories set');
select t_ok((select count(*) from posting_rules) >= 60, 'Posting rules loaded');
select t_ok((select count(*) from items where is_demo) >= 10 and (select count(*) from customers where is_demo) = 10
        and (select count(*) from suppliers where is_demo) = 10 and (select count(*) from journals where is_demo) >= 10, '10+ DEMO items, customers, suppliers and journals');

-- People: DS, an Accountant in learning phase, Staff, a second Director
insert into auth.users(id, email) values ('00000000-0000-0000-0000-0000000000d1', 'info.ruchibuds@gmail.com');
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
select rb_login_ok() is not null;
select rb_invite_user('acc@example.com', 'Real Accountant', 'RA', null, (select id from user_categories where name='Accountant'), '2027-01-31');
select rb_invite_user('staff@example.com', 'Real Staff', 'RS', null, (select id from user_categories where name='Staff'), null);
select rb_invite_user('dir2@example.com', 'Second Director', 'D2', null, (select id from user_categories where name='Director'), null);
reset role;
insert into auth.users(id, email) values
 ('00000000-0000-0000-0000-0000000000a1', 'acc@example.com'),
 ('00000000-0000-0000-0000-0000000000c1', 'staff@example.com'),
 ('00000000-0000-0000-0000-0000000000d2', 'dir2@example.com');
set role authenticated;

-- 1. The DEMO books balance
select t_ok((select sum(debit_paise) = sum(credit_paise) from rb_trial_balance('2026-04-01', '2026-11-30')), 'DEMO trial balance: debits = credits');
select t_ok(t_tb('2026-04-01', '2026-11-30', '10010110') = 960000, 'Cash on hand is ₹9,600 after the DEMO entries');
select t_ok(t_tb('2026-04-01', '2026-11-30', '10010205') = 894100, 'Bank is ₹8,941 after the DEMO entries');
select t_ok(t_tb('2026-04-01', '2026-11-30', '50010130') = -3000000, 'Partners'' capital ₹30,000 (credit)');
select t_ok((select count(*) from rb_account_ledger('50010130', '2026-04-01', '2026-11-30', null, null, 1, null) where journal_id is not null) = 1,
            'Capital ledger filters by partner');

-- 2. Staff cannot see the books or suppliers, but can add a retail customer
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
select t_ok((select count(*) from journals) = 0 and (select count(*) from journal_lines) = 0, 'Staff cannot read journals');
select t_ok((select count(*) from suppliers) = 0, 'Staff cannot read suppliers');
select t_ok((select count(*) from items) > 0 and (select count(*) from product_packs) > 0, 'Staff can read items and packs (for selling)');
select t_err($$select rb_trial_balance('2026-04-01', '2026-11-30')$$, 'right to see the trial balance');
select t_err($$select rb_save_journal('{"journal_date":"2026-11-25","narration":"x","lines":[]}')$$, 'right to enter journals');
select t_ok(rb_save_customer('{"kind":"retail","name":"Walk-up Rani","phone":"9999900000","send_promotions":true}') > 0, 'Staff adds a retail customer with promotions consent');
select t_err($$select rb_save_customer('{"kind":"retail","name":"No Phone","send_promotions":true}')$$, 'phone number to send promotions');
select t_err($$select rb_save_supplier('{"name":"X"}')$$, 'right to add suppliers');
select t_err($$select rb_post_engine('{}', '[]')$$, 'permission denied');
select t_err($$insert into journals(journal_date, narration) values ('2026-11-01','x')$$, 'permission denied');

-- 3. Accountant: masters, customers with trader rules, posting rules
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select rb_save_settings('{"trader_required_fields":["phone","gstin"]}');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select t_err($$select rb_save_customer('{"kind":"trader","name":"Big Trader","phone":"98"}')$$, 'gstin is required');
select t_ok(rb_save_customer('{"kind":"trader","name":"Big Trader","phone":"98","gstin":"27abcde1234f1z5"}') > 0, 'Trader saved once required fields are filled');
select t_ok((select gstin from customers where name = 'Big Trader') = '27ABCDE1234F1Z5', 'GSTIN stored in capitals');
select t_ok((select code from customers where name = 'Big Trader') ~ '^C\d{5}$', 'Customer gets a C00001-style code');
select rb_save_supplier('{"name":"Real Fisherman","kind":"fisherman","usually_no_bill":true}');
select t_ok((select code from suppliers where name = 'Real Fisherman') ~ '^S\d{5}$', 'Supplier gets an S00001-style code');
select rb_save_item('{"name":"Prawns","kind":"raw","base_unit":"g","buy_unit":"kg","stages":["Clean","Fry"]}');
select t_ok((select code from items where name = 'Prawns') = 'RM0001' and (select stages from items where name = 'Prawns') = '{Clean,Fry}', 'Raw item with stages and RM0001 code');
select t_err($$select rb_save_item('{"name":"prawns","kind":"raw","base_unit":"g"}')$$, 'already exists');
select t_err($$select rb_save_item('{"name":"Bones","kind":"byproduct","base_unit":"g"}')$$, 'Sellable or Discarded');
select t_err($$select rb_save_product_pack(jsonb_build_object('item_id', (select id from items where name='Prawns'), 'pack_type_id', (select min(id) from pack_types), 'net_qty', 200))$$, 'Only finished goods');
select rb_set_posting_rule('expense', 'gas_power', '80020110');
select t_ok((select account_code from posting_rules where event_code='expense' and line_key='gas_power') = '80020110', 'Accountant changes a posting rule');
select t_err($$select rb_set_posting_rule('expense', 'gas_power', '20020105')$$, 'not a posting account shown');
select t_err($$select rb_save_account('{"code":"10010110","e002_active":false}')$$, 'Posting rules still use');
select rb_save_account('{"code":"80060145","local_name":"Donations and charity"}');
select t_ok((select local_name from accounts where code = '80060145') = 'Donations and charity', 'Local name for an account');
select t_ok(rb_add_local_account('{"code":"80060155","name":"Pooja and festival expenses"}') = '80060155', 'Ruchi Buds account added inside a family');
select t_err($$select rb_add_local_account('{"code":"80069905","name":"X"}')$$, 'no family');
select t_ok((rb_import_accounts('[{"code":"10010260","name":"Bank Account 07 - Reserved","class":"Asset","statement":"BS","normal_balance":"Debit","subledger":"Bank"},{"code":"10010110","name":"Cash on Hand"}]')->>'added')::int = 1,
            'COA import adds a new account and leaves an unchanged one alone');
select t_ok((select not e002_active from accounts where code = '10010260'), 'Imported new accounts start hidden until switched on');
select t_err($$select rb_rename_department((select id from departments where code='CC005'), 'Admin', null)$$, 'right to rename departments');

-- 4. Manual journals: checks, second person, numbering
select t_err($$select rb_save_journal(jsonb_build_object('journal_date','2026-11-25','narration','Stock fix','department_id',(select id from departments where code='CC001'),
  'lines', jsonb_build_array(jsonb_build_object('account_code','10030105','debit_paise',100), jsonb_build_object('account_code','10010110','credit_paise',100))))$$, 'stock accounts');
select t_err($$select rb_save_journal(jsonb_build_object('journal_date','2026-11-25','narration','AR fix','department_id',(select id from departments where code='CC001'),
  'lines', jsonb_build_array(jsonb_build_object('account_code','10020105','debit_paise',100), jsonb_build_object('account_code','10010110','credit_paise',100))))$$, 'needs the customer');
select t_err($$select rb_save_journal(jsonb_build_object('journal_date','2026-11-25','narration','ROU','department_id',(select id from departments where code='CC001'),
  'lines', jsonb_build_array(jsonb_build_object('account_code','20020105','debit_paise',100), jsonb_build_object('account_code','10010110','credit_paise',100))))$$, 'not used by Ruchi Buds');
select t_err($$select rb_save_journal(jsonb_build_object('journal_date','2026-11-25','narration','Family','department_id',(select id from departments where code='CC001'),
  'lines', jsonb_build_array(jsonb_build_object('account_code','80020100','debit_paise',100), jsonb_build_object('account_code','10010110','credit_paise',100))))$$, 'family header');
select t_err($$select rb_save_journal(jsonb_build_object('journal_date','2026-11-25','narration','IC','department_id',(select id from departments where code='CC001'),
  'lines', jsonb_build_array(jsonb_build_object('account_code','10070105','debit_paise',100), jsonb_build_object('account_code','10010110','credit_paise',100))))$$, 'other group business');
-- An unbalanced draft saves, but cannot post
select rb_save_journal(jsonb_build_object('journal_date','2026-11-25','narration','Electricity bill','department_id',(select id from departments where code='CC005'),
  'lines', jsonb_build_array(jsonb_build_object('account_code','80020110','debit_paise',85000), jsonb_build_object('account_code','10010110','credit_paise',80000)))) as j1 \gset
select t_err(format('select rb_post_journal(%s)', :j1), 'must be equal');
select rb_save_journal(jsonb_build_object('id', :j1, 'journal_date','2026-11-25','narration','Electricity bill','department_id',(select id from departments where code='CC005'),
  'lines', jsonb_build_array(jsonb_build_object('account_code','80020110','debit_paise',85000), jsonb_build_object('account_code','10010110','credit_paise',85000))));
select t_err(format('select rb_post_journal(%s)', :j1), 'someone other than the person who entered it');
select t_ok(not rb_can_post_journal(:j1), 'Screen knows the Accountant cannot post their own journal');
-- A customer-subledger journal by the Accountant
select rb_save_journal(jsonb_build_object('journal_date','2026-11-26','narration','Opening balance owed by Big Trader','department_id',(select id from departments where code='CC003'),
  'lines', jsonb_build_array(jsonb_build_object('account_code','10020105','debit_paise',250000,'customer_id',(select id from customers where name='Big Trader')),
                             jsonb_build_object('account_code','97010105','credit_paise',250000)))) as j2 \gset
-- DS approves both
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select t_ok(rb_can_post_journal(:j1), 'DS may post the Accountant''s journal');
select t_ok(rb_post_journal(:j1) = 'TRN/2611/00001', 'Training-mode journals are numbered TRN/YYMM/00001');
select t_ok(rb_post_journal(:j2) = 'TRN/2611/00002', 'Numbers run on');
select t_err(format('select rb_post_journal(%s)', :j1), 'already posted');
select t_ok((select count(*) from audit_log where action = 'POST_JOURNAL' and record_id = :j1::text) = 1, 'Posting is in the audit log');
select t_ok((select balance_paise from rb_account_ledger('10020105', '2026-04-01', '2026-11-30', (select id from customers where name='Big Trader'))
             order by journal_date desc, journal_id desc nulls last limit 1) = 250000, 'Customer ledger shows the balance');
-- DS's own journal: needs a second person by default; switch can turn that off
select rb_save_journal(jsonb_build_object('journal_date','2026-11-26','narration','Water bill','department_id',(select id from departments where code='CC001'),
  'lines', jsonb_build_array(jsonb_build_object('account_code','70030105','debit_paise',30000), jsonb_build_object('account_code','10010110','credit_paise',30000)))) as j3 \gset
select t_err(format('select rb_post_journal(%s)', :j3), 'someone other than the person');
select rb_save_ledger_settings('{"manual_journal_second_person":false}');
select t_ok(rb_post_journal(:j3) like 'TRN/2611/%', 'With the switch off, a Director posts their own journal');
select rb_save_ledger_settings('{"manual_journal_second_person":true}');

-- 5. Posted journals cannot be edited, even directly in the database
reset role;
select t_err(format($$update journals set narration = 'changed' where id = %s$$, :j1), 'cannot be changed');
select t_err(format($$update journal_lines set debit_paise = 1 where journal_id = %s and debit_paise > 0$$, :j1), 'cannot be changed');
update app_settings set training_mode = false;  -- pretend we are live for this check
select t_err(format($$delete from journals where id = %s$$, :j1), 'cannot be deleted');
update app_settings set training_mode = true;
set role authenticated;

-- 6. Reverse, and learning-phase delete
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select t_err(format($$select rb_reverse_journal(%s, '2026-11-26', '')$$, :j1), 'reason');
select rb_reverse_journal(:j1, '2026-11-26', 'Bill was for December') as r1 \gset
select t_ok((select status from journals where id = :j1) = 'reversed' and (select reversal_of from journals where id = :r1) = :j1, 'Reversal links both journals');
select t_err(format($$select rb_reverse_journal(%s, '2026-11-26', 'again')$$, :j1), 'not already reversed');
select t_ok(t_tb('2026-11-01', '2026-11-30', '80020110') = 0, 'Reversed expense nets to zero');
select t_err(format('select rb_hard_delete_journal(%s)', :j2), 'right to fully delete');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select t_err(format('select rb_hard_delete_journal(%s)', :j3), 'learning phase');
select t_err(format('select rb_hard_delete_journal(%s)', :j1), 'reversal pair');
select rb_hard_delete_journal(:j2);
select t_ok(not exists (select 1 from journals where id = :j2), 'Director fully deletes a learning-phase user''s posted journal');
select t_ok(not exists (select 1 from audit_log where action ilike '%DELETE%' and record_id = :j2::text), 'Learning-phase delete is not in the audit log (spec section 4)');

-- 6b. Clone, and Reverse and correct (version 1.1)
-- Reverse and correct DS's Water bill: reversal posted, draft copy saved, same lines
select t_err(format($$select rb_reverse_and_copy_journal(%s, '2026-11-27', ' ')$$, :j3), 'reason');
select t_ok((select status from journals where id = :j3) = 'posted' and not exists (select 1 from journals where copied_from = :j3),
            'A failed Reverse and correct changes nothing');
select t_err(format($$select rb_reverse_and_copy_journal(%s, '2026-11-27', 'x')$$, :r1), 'itself a reversal');
select rb_reverse_and_copy_journal(:j3, '2026-11-27', 'Water bill was ₹250, not ₹300') as rc \gset
select (:'rc'::jsonb->>'draft_id')::bigint as d1, (:'rc'::jsonb->>'reversal_id')::bigint as rv3 \gset
select t_ok((select status from journals where id = :j3) = 'reversed' and (select reversal_of from journals where id = :rv3) = :j3
        and (:'rc'::jsonb->>'reversal_no') like 'TRN/2611/%', 'Reverse and correct posts the reversal');
select t_ok((select status = 'draft' and copied_from = :j3 and journal_date = '2026-11-27' and source = 'manual' and narration = 'Water bill'
                    and entered_by = (select entered_by from journals where id = :j3) and total_paise = 30000 from journals where id = :d1)
        and (select count(*) from journal_lines where journal_id = :d1) = 2
        and (select sum(debit_paise) from journal_lines where journal_id = :d1 and account_code = '70030105') = 30000,
        'and saves a draft copy with the same lines on the same date');
select t_ok((select count(*) from audit_log where action = 'REVERSE_AND_COPY' and record_id = :j3::text) = 1, 'Reverse and correct is in the audit log');
select t_ok((rb_journal_detail(:d1)->>'copied_from_no') = (select journal_no from journals where id = :j3)
        and jsonb_array_length(rb_journal_detail(:j3)->'copies') = 1, 'The journal screen shows the copy and where it came from');
select t_ok((rb_journal_detail(:j3)->>'can_correct')::boolean is false and (rb_journal_detail(:j3)->>'can_copy')::boolean, 'A reversed journal can be cloned, not corrected again');
-- Correct the draft; the person who made it cannot post it, a second Director can
select rb_save_journal(jsonb_build_object('id', :d1, 'journal_date','2026-11-27','narration','Water bill','department_id',(select id from departments where code='CC001'),
  'lines', jsonb_build_array(jsonb_build_object('account_code','70030105','debit_paise',25000), jsonb_build_object('account_code','10010110','credit_paise',25000))));
select t_ok((select copied_from from journals where id = :d1) = :j3, 'Changing the draft keeps the link');
select t_err(format('select rb_post_journal(%s)', :d1), 'someone other than the person');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d2', false);
select t_ok(rb_post_journal(:d1) like 'TRN/2611/%', 'A second person posts the corrected journal');
select t_ok(t_tb('2026-11-01', '2026-11-30', '70030105') = (select coalesce(sum(debit_paise - credit_paise), 0) from journal_lines jl join journals j on j.id = jl.journal_id
              where jl.account_code = '70030105' and j.status <> 'draft' and jl.journal_date between '2026-11-01' and '2026-11-30')
        and (select sum(debit_paise - credit_paise) from journal_lines where account_code = '70030105' and journal_id in (:j3, :rv3, :d1)) = 25000,
        'Books show the corrected ₹250 only');
-- Clone: a new draft from any journal, remembering where it came from
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select rb_save_journal(jsonb_build_object('copied_from', :j1, 'journal_date','2026-11-28','narration','Electricity bill','department_id',(select id from departments where code='CC005'),
  'lines', jsonb_build_array(jsonb_build_object('account_code','80020110','debit_paise',85000), jsonb_build_object('account_code','10010110','credit_paise',85000)))) as c1 \gset
select t_ok((select copied_from = :j1 and status = 'draft' from journals where id = :c1), 'Clone saves a new draft linked to the original');
select t_ok((select status from journals where id = :j1) = 'reversed', 'Cloning leaves the original as it was');
select rb_delete_draft_journal(:c1);
-- Staff cannot use it
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
select t_err(format($$select rb_reverse_and_copy_journal(%s, '2026-11-27', 'x')$$, :j1), 'right to enter journals');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);

-- 7. Month lock
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select t_err($$select rb_lock_period('2026-10-01', true)$$, 'right to lock');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select t_err($$select rb_lock_period('2026-11-01', true)$$, 'draft journals');
select rb_lock_period('2026-10-15', true, 'October closed');
select t_ok(rb_period_locked('2026-10-31') and not rb_period_locked('2026-11-01'), 'October is locked, November open');
select t_err($$select rb_save_journal(jsonb_build_object('journal_date','2026-10-20','narration','Late bill','department_id',(select id from departments where code='CC001'),
  'lines', jsonb_build_array(jsonb_build_object('account_code','70030105','debit_paise',100), jsonb_build_object('account_code','10010110','credit_paise',100))))$$, 'Oct-2026 is locked');
select t_err($$select rb_reverse_journal((select id from journals where journal_no = 'DEMO/2610/00005'), '2026-10-31', 'wrong')$$, 'is locked');
select t_ok(rb_reverse_journal((select id from journals where journal_no = 'DEMO/2610/00005'), '2026-11-02', 'Rent was for November') is not null,
            'A locked month''s journal can be reversed into an open month');
select t_ok((select closing_paise from rb_trial_balance('2026-10-01', '2026-10-31') where account_code = '70030120') = 600000, 'Locked October still shows its figures');
select t_err($$select rb_lock_period('2026-10-01', false, '')$$, 'reason');
select rb_lock_period('2026-10-01', false, 'Correcting a bill');
select t_ok(not rb_period_locked('2026-10-31'), 'Unlocked with a reason');
select t_ok((select count(*) from audit_log where table_name = 'periods') >= 2, 'Locks and unlocks are in the audit log');

-- 8. Departments: rename from a date, merge, undo, delete rules
select rb_rename_department((select id from departments where code='CC005'), 'Office and admin', '2026-11-01');
select t_ok(rb_dept_label((select id from departments where code='CC005'), '2026-10-15') = 'CC005 Administration'
        and rb_dept_label((select id from departments where code='CC005'), '2026-11-15') = 'CC005 Office and admin', 'Rename from a date keeps the old name for older entries');
select rb_rename_department((select id from departments where code='CC001'), 'Kitchen', null);
select t_ok(rb_dept_label((select id from departments where code='CC001'), '2026-01-01') = 'CC001 Kitchen', 'Rename for all history');
select rb_merge_department((select id from departments where code='CC003'), (select id from departments where code='CC002'), null, 'One sales team');
select t_ok(rb_dept_label((select id from departments where code='CC003'), '2026-11-12') = 'CC002 Retail counter', 'Merged department reports under the new one');
select t_ok((select sum(closing_paise) from rb_trial_balance('2026-04-01', '2026-11-30', (select id from departments where code='CC002')) where account_code = '60010115') = -480000,
            'Trial balance by department includes the merged department''s entries');
select t_ok((select not is_active from departments where code='CC003'), 'Merged department is closed for new entries');
select t_err($$select rb_save_journal(jsonb_build_object('journal_date','2026-11-26','narration','x','department_id',(select id from departments where code='CC003'),
  'lines', jsonb_build_array(jsonb_build_object('account_code','70030105','debit_paise',100), jsonb_build_object('account_code','10010110','credit_paise',100))))$$, 'closed or merged');
select rb_undo_department_change((select max(id) from dept_events where kind = 'merge'));
select t_ok((select is_active and merged_into is null from departments where code='CC003')
        and rb_dept_label((select id from departments where code='CC003'), '2026-11-12') = 'CC003 Trade sales', 'Undoing the merge restores the original reporting');
select t_err($$select rb_delete_department((select id from departments where code='CC001'))$$, 'has been used');
select rb_add_department('cc010', 'Catering');
select rb_delete_department((select id from departments where code='CC010'));
select t_ok(not exists (select 1 from departments where code = 'CC010'), 'An unused department can be deleted');

-- 9. Partners with entries stay on the list
select t_err($$select rb_save_settings('{"partners":[{"id":1,"name":"A","weight":1},{"id":2,"name":"B","weight":1}]}')$$, 'has entries in the books');
select rb_save_settings('{"partners":[{"id":1,"name":"Asha","weight":1},{"id":2,"name":"Bina","weight":1},{"id":3,"name":"Chitra","weight":1},{"name":"New partner","weight":1}]}');
select t_ok((select partners->3->>'id' from app_settings) = '4' and rb_partner_name(1) = 'Asha', 'Partners keep their numbers; a new one gets the next');

-- 10. Remove demo data, then go live
select rb_remove_demo_data('REMOVE DEMO');
select t_ok(not exists (select 1 from journals where is_demo) and not exists (select 1 from items where is_demo)
        and not exists (select 1 from customers where is_demo) and not exists (select 1 from departments where is_demo), 'DEMO journals and masters removed');
select t_ok(exists (select 1 from customers where is_walk_in) and exists (select 1 from items where name = 'Prawns')
        and exists (select 1 from journals where id = :j3), 'Real records stay');
select rb_go_live('2027-04-01', 'GO LIVE');
select t_ok(not exists (select 1 from journals) and not exists (select 1 from journal_lines), 'Go-live clears training journals');
select t_ok(exists (select 1 from customers where name = 'Big Trader'), 'Masters made in training stay after go-live');
select rb_save_journal(jsonb_build_object('journal_date','2027-04-01','narration','Opening capital, partner 1','department_id',(select id from departments where code='CC005'),
  'lines', jsonb_build_array(jsonb_build_object('account_code','10010110','debit_paise',1000000),
                             jsonb_build_object('account_code','50010130','credit_paise',1000000,'partner_id',1)))) as j4 \gset
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d2', false);
select t_ok(rb_post_journal(:j4) = 'JV/2704/00001', 'After go-live, journals start at JV/YYMM/00001');

-- 11. A re-run of the file after go-live adds no DEMO data (checked by the runner)
reset role;
\echo ALL MODULE 2 TESTS PASSED
