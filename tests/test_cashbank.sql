-- Behaviour tests for 06_cash_bank.sql. Run against a throwaway database only,
-- after supabase_stub.sql and sql/01 to sql/06.
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
grant execute on function public.t_err(text, text) to anon, authenticated;
create or replace function public.t_ok(p boolean, p_what text) returns void language plpgsql as $$
begin if not coalesce(p, false) then raise exception 'FAIL: %', p_what; end if; raise notice 'ok: %', p_what; end $$;
grant execute on function public.t_ok(boolean, text) to anon, authenticated;
-- Balance of an account from the non-DEMO entries (debit minus credit).
create or replace function public.t_bal(p_code text) returns bigint language sql security definer as $$
  select coalesce(sum(l.debit_paise - l.credit_paise), 0)::bigint from journal_lines l join journals j on j.id = l.journal_id
  where l.account_code like p_code and j.status <> 'draft' and not l.is_demo $$;
create or replace function public.t_val(p_item int, p_pack int default null) returns bigint language sql security definer as $$
  select coalesce(sum(value_paise), 0)::bigint from stock_moves where item_id = p_item and pack_id is not distinct from p_pack $$;
-- Books balance; stock accounts = the stock record item by item; customer and
-- supplier control accounts = their ledgers; open bills = the payables in the books.
create or replace function public.t_books_agree() returns boolean language sql security definer as $$
  select (select sum(debit_paise) = sum(credit_paise) from journal_lines)
     and not exists (
       select 1 from (
         select i.id, case i.kind when 'raw' then '10030105' when 'packaging' then '10030110' when 'wip' then '10030120' else '10030125' end acc,
                coalesce((select sum(value_paise) from stock_moves m where m.item_id = i.id), 0) stock
         from items i) s
       where s.stock <> (select coalesce(sum(l.debit_paise - l.credit_paise), 0) from journal_lines l join journals j on j.id = l.journal_id
                         where l.account_code = s.acc and l.item_id = s.id and j.status <> 'draft'))
     and (select coalesce(sum(debit_paise - credit_paise), 0) from journal_lines where account_code = '10020105')
         = (select coalesce(sum(rb_sal_book_balance(id, null)), 0) from customers)
     and not exists (select 1 from expenses where outstanding_paise < 0 or paid_paise > total_paise)
     and not exists (select 1 from suppliers s where
           (select coalesce(sum(l.credit_paise - l.debit_paise), 0) from journal_lines l where l.account_code = '30010105' and l.supplier_id = s.id)
           < (select coalesce(sum(outstanding_paise), 0) from expenses e where e.supplier_id = s.id)) $$;
create or replace function public.t_cash(p_code text, p_as_of date default null) returns bigint language sql security definer as $$
  select rb_cb_balance(p_code, p_as_of) $$;
grant execute on function public.t_bal(text), public.t_val(int, int), public.t_books_agree(), public.t_cash(text, date) to authenticated;
set client_min_messages = notice;

-- 0. DEMO data
select t_ok((select count(*) from expenses where is_demo) >= 10, '10+ DEMO expenses');
select t_ok((select expense_no from expenses where is_demo and direction = 'out' order by id limit 1) = 'DEMO-EXP/2611/00001', 'DEMO expenses have their own DEMO-EXP series');
select t_ok((select count(*) from expenses where is_demo and status = 'awaiting_approval') = 1, 'A DEMO expense above the limit waits for approval');
select t_ok((select count(*) from expenses where is_demo and direction = 'in') = 2, 'Two DEMO entries of other money received');
select t_ok((select outstanding_paise from expenses where is_demo and supplier_id = (select id from suppliers where code = 'DEMO-S11')) = 450000,
            'DEMO: the Mehta & Co bill of ₹4,500 is still unpaid');
select t_ok((select count(*) from money_transfers where is_demo) = 2 and (select count(*) from partner_entries where is_demo) = 2
        and (select count(*) from cash_counts where is_demo) = 1, 'DEMO transfers, partner entries and a cash count');
select t_ok((select count(*) from month_end_runs where is_demo and status = 'posted') = 2, 'DEMO: both month-end steps posted for Nov 2026');
select t_ok((select amount_paise from month_end_runs where is_demo and kind = 'doubtful_debts') = 65000,
            'DEMO provision: 10% of the ₹6,500 opening balance not on an invoice');
select t_ok((select amount_paise from month_end_runs where is_demo and kind = 'absorption') > 0, 'DEMO labour and overheads added to stock');
select t_ok(t_books_agree(), 'Books balance; stock, customer and supplier ledgers agree with the books');
select t_ok(t_cash('10010110', null) >= 0 and t_cash('10010205', null) >= 0, 'DEMO cash and bank never go below zero');
select t_ok((select available from screens where code = 'cash_bank'), 'Cash, bank and expenses screen is live');
select t_ok(not exists (select 1 from stock_moves group by item_id, pack_id having sum(value_paise) < 0), 'No DEMO stock value below zero');

-- People
insert into auth.users(id, email) values ('00000000-0000-0000-0000-0000000000d1', 'info.ruchibuds@gmail.com');
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
select rb_login_ok() is not null;
select rb_invite_user('acc@example.com', 'Real Accountant', 'RA', null, (select id from user_categories where name='Accountant'), '2027-01-31');
select rb_invite_user('mgr@example.com', 'Real Manager', 'RM', null, (select id from user_categories where name='Manager'), null);
select rb_invite_user('staff@example.com', 'Real Staff', 'RS', null, (select id from user_categories where name='Staff'), null);
select rb_invite_user('fc@example.com', 'Real FC', 'RF', null, (select id from user_categories where name='Financial Controller'), null);
reset role;
insert into auth.users(id, email) values
 ('00000000-0000-0000-0000-0000000000a1', 'acc@example.com'),
 ('00000000-0000-0000-0000-0000000000e1', 'mgr@example.com'),
 ('00000000-0000-0000-0000-0000000000c1', 'staff@example.com'),
 ('00000000-0000-0000-0000-0000000000f1', 'fc@example.com');
insert into suppliers (code, name) values ('T-S1', 'Test Electrician');
-- Test items for the month-end: prawns cleaned into a prepared ingredient, oil, a jar, a pickle in 250 g jars.
insert into items (code, name, kind, base_unit, buy_unit, shelf_life_days) values ('T-WP', 'Test prawns, cleaned', 'wip', 'g', 'g', 30);
insert into items (code, name, kind, base_unit, buy_unit, stages, prepared_item_id) values
  ('T-RM', 'Test prawns', 'raw', 'g', 'kg', '{Clean}', (select id from items where code = 'T-WP'));
insert into items (code, name, kind, base_unit, buy_unit) values ('T-OIL', 'Test oil', 'raw', 'ml', 'l'), ('T-PK', 'Test jar', 'packaging', 'pc', 'pc');
insert into items (code, name, kind, base_unit, buy_unit, sells_by, hsn_code, gst_rate) values ('T-FG', 'Test prawn pickle', 'finished', 'g', 'g', 'pack', '2001', 12);
insert into pack_types (code, name, kind, packaging_item_id) values ('T-PT', '250 g test jar', 'jar', (select id from items where code = 'T-PK'));
insert into product_packs (item_id, pack_type_id, net_qty, retail_price_paise, trader_price_paise) values
  ((select id from items where code = 'T-FG'), (select id from pack_types where code = 'T-PT'), 250, 30000, 25000);
insert into customers (code, kind, name, state_code, credit_limit_paise, credit_days) values ('T-TR1', 'trader', 'Test Trader', '27', 1000000, 10);
insert into customers (code, kind, name) values ('T-OB', 'trader', 'Test Old Customer');
set role authenticated;
\set dir '00000000-0000-0000-0000-0000000000d1'
\set acc '00000000-0000-0000-0000-0000000000a1'
\set mgr '00000000-0000-0000-0000-0000000000e1'
\set staff '00000000-0000-0000-0000-0000000000c1'
\set fc '00000000-0000-0000-0000-0000000000f1'
\set s1 '(select id from suppliers where code = ''T-S1'')'
\set rm '(select id from items where code = ''T-RM'')'
\set wp '(select id from items where code = ''T-WP'')'
\set oil '(select id from items where code = ''T-OIL'')'
\set pk '(select id from items where code = ''T-PK'')'
\set fg '(select id from items where code = ''T-FG'')'
\set jar '(select id from product_packs where item_id = (select id from items where code = ''T-FG''))'
\set tr1 '(select id from customers where code = ''T-TR1'')'
\set ob '(select id from customers where code = ''T-OB'')'
\set cash '(select id from money_accounts where account_code = ''10010110'')'
\set bank1 '(select id from money_accounts where account_code = ''10010205'')'
\set bank2 '(select id from money_accounts where account_code = ''10010210'')'
\set cat_elec '(select id from expense_categories where name = ''Shop or office electricity and water'')'
\set cat_rent '(select id from expense_categories where name = ''Shop or office rent'')'
\set cat_repair '(select id from expense_categories where name = ''Repairs and maintenance (shop, office)'')'
\set cat_wages '(select id from expense_categories where name = ''Kitchen wages'')'
\set cat_krent '(select id from expense_categories where name = ''Kitchen rent'')'
\set cat_int '(select id from expense_categories where name = ''Bank interest received'')'

-- 1. Who can do what
select set_config('request.jwt.claim.sub', :'staff', false);
select t_err($$select rb_save_expense('{}')$$, 'right to enter expenses');
select t_err($$select * from rb_money_balances()$$, 'right to see cash and bank');
select t_ok((select count(*) from expenses) = 0 and (select count(*) from month_end_runs) = 0, 'Staff cannot read expenses or month-end runs');
select set_config('request.jwt.claim.sub', :'mgr', false);
select t_err($$select rb_save_partner_entry('{}')$$, 'right to enter partners');
select t_err($$select rb_absorption_preview('2026-11-01')$$, 'right to run the month-end');
select t_err($$select rb_approve_expense(1)$$, 'right to approve expenses');

-- 2. Expenses paid at once (cash, UPI, bank)
select t_err(format($$select rb_save_expense(jsonb_build_object('category_id', %s, 'expense_date', '2026-11-26', 'amount_paise', 120000))$$, :cat_elec), 'what it was for');
select t_err(format($$select rb_save_expense(jsonb_build_object('category_id', %s, 'expense_date', '2026-11-26', 'description', 'x'))$$, :cat_elec), 'enter the amount');
select rb_save_expense(jsonb_build_object('category_id', :cat_elec, 'expense_date', '2026-11-26', 'description', 'Shop electricity, Nov',
  'amount_paise', 120000, 'payment_mode', 'cash', 'photo', 'data:image/jpeg;base64,AAAA')) as e1 \gset
select t_ok((select expense_no from expenses where id = :e1) = 'TRN-EXP/2611/00001', 'In training, expenses are numbered TRN-EXP/YYMM/00001');
select t_ok((select status from expenses where id = :e1) = 'posted' and t_bal('80020110') = 120000 and t_bal('10010110') = -120000,
            'Below the limit it posts at once: Dr shop electricity ₹1,200, Cr cash');
select t_ok((select department_id from expenses where id = :e1) = (select id from departments where code = 'CC002'), 'The category''s default department is used');
select t_ok((select count(*) from rb_expense_photos(:e1)) = 1, 'The bill photo is kept with the expense');
select t_ok((select count(*) from expense_photos) = 0, 'Bill photos are not readable directly');
select rb_save_expense(jsonb_build_object('category_id', :cat_int, 'expense_date', '2026-11-26', 'description', 'Savings interest',
  'amount_paise', 4500, 'payment_mode', 'bank')) as i1 \gset
select t_ok((select expense_no from expenses where id = :i1) = 'TRN-OIN/2611/00001' and t_bal('90010105') = -4500 and t_bal('10010205') = 4500,
            'Money received: Dr bank, Cr bank interest; own OIN series');
select t_err(format($$select rb_save_expense(jsonb_build_object('category_id', %s, 'expense_date', '2026-11-26', 'description', 'x', 'amount_paise', 100, 'payment_mode', 'credit'))$$, :cat_int),
  'cannot be on credit');
select t_err(format($$select rb_save_expense(jsonb_build_object('category_id', %s, 'expense_date', '2026-11-26', 'description', 'x', 'amount_paise', 100, 'payment_mode', 'bank', 'money_account_id', %s))$$, :cat_elec, :bank2),
  'switched off');
select t_err(format($$select rb_save_expense(jsonb_build_object('category_id', %s, 'expense_date', '2026-11-26', 'description', 'x', 'amount_paise', 100, 'payment_mode', 'cash', 'money_account_id', %s))$$, :cat_elec, :bank1),
  'cannot be used for cash');

-- 3. Above the limit: waits for approval
select rb_save_expense(jsonb_build_object('category_id', :cat_rent, 'expense_date', '2026-11-26', 'description', 'Shop rent, Nov',
  'amount_paise', 1500000, 'payment_mode', 'bank', 'reference', 'NEFT 1234')) as e2 \gset
select t_ok((select status from expenses where id = :e2) = 'awaiting_approval' and (select journal_id from expenses where id = :e2) is null
        and t_bal('80020105') = 0, 'Above the ₹10,000 limit it waits for approval and is not in the books yet');
select rb_save_expense(jsonb_build_object('id', :e2, 'category_id', :cat_rent, 'expense_date', '2026-11-26', 'description', 'Shop rent, Nov',
  'amount_paise', 1400000, 'payment_mode', 'bank'));
select t_ok((select total_paise from expenses where id = :e2) = 1400000 and (select expense_no from expenses where id = :e2) = 'TRN-EXP/2611/00002',
            'The person who entered it can correct it while it waits; the number stays');
select rb_save_expense(jsonb_build_object('category_id', :cat_rent, 'expense_date', '2026-11-26', 'description', 'Advance rent',
  'amount_paise', 2000000, 'payment_mode', 'bank')) as e3 \gset
select set_config('request.jwt.claim.sub', :'acc', false);
select rb_approve_expense(:e2);
select t_ok((select status from expenses where id = :e2) = 'posted' and (select approved_by from expenses where id = :e2) = (select id from app_users where email = 'acc@example.com')
        and t_bal('80020105') = 1400000, 'The Accountant approves it and it posts');
select t_err(format('select rb_approve_expense(%s)', :e2), 'not waiting for approval');
select t_err(format($$select rb_refuse_expense(%s, '')$$, :e3), 'give the reason');
select rb_refuse_expense(:e3, 'Not agreed with the landlord');
select t_ok((select status from expenses where id = :e3) = 'refused' and t_bal('80020105') = 1400000, 'A refused expense never reaches the books');

-- 4. Expense bill on credit, paid later
select set_config('request.jwt.claim.sub', :'mgr', false);
select t_err(format($$select rb_save_expense(jsonb_build_object('category_id', %s, 'expense_date', '2026-11-27', 'description', 'Fan repair', 'amount_paise', 200000, 'payment_mode', 'credit'))$$, :cat_repair),
  'needs the supplier');
select rb_save_expense(jsonb_build_object('category_id', :cat_repair, 'expense_date', '2026-11-27', 'description', 'Fan repair',
  'supplier_id', :s1, 'bill_no', 'E-77', 'amount_paise', 200000, 'gst_paise', 36000, 'payment_mode', 'credit')) as e4 \gset
select t_ok((select gst_claimed from expenses where id = :e4) = false and t_bal('80020135') = 236000 and t_bal('10050105') = 0
        and t_bal('30010105') = -236000, 'Not GST registered: the GST is part of the cost; the bill is owed to the supplier');
select t_ok((select outstanding_paise from expenses where id = :e4) = 236000, 'The bill stays open until paid');
select set_config('request.jwt.claim.sub', :'acc', false);
select t_ok((select balance_paise from rb_supplier_balances() where supplier_id = :s1) = 236000, 'It shows in the supplier''s balance');
select rb_pay_expense_bill(jsonb_build_object('supplier_id', :s1, 'pay_date', '2026-11-28', 'amount_paise', 100000, 'mode', 'upi',
  'allocations', jsonb_build_array(jsonb_build_object('expense_id', :e4, 'amount_paise', 100000)))) as pay1 \gset
select t_ok((select outstanding_paise from expenses where id = :e4) = 136000 and (select paid_paise from expenses where id = :e4) = 100000
        and t_bal('30010105') = -136000, 'Part paid by UPI: ₹1,360 still owed');
select t_ok((select money_account_id from supplier_payments where id = :pay1) = :bank1, 'UPI goes through the main bank account');
select t_err(format($$select rb_pay_expense_bill(jsonb_build_object('supplier_id', %s, 'pay_date', '2026-11-28', 'amount_paise', 200000, 'mode', 'cash',
  'allocations', jsonb_build_array(jsonb_build_object('expense_id', %s, 'amount_paise', 200000))))$$, :s1, :e4), 'only has');
select set_config('request.jwt.claim.sub', :'dir', false);
select t_err(format($$select rb_reverse_expense(%s, '2026-11-28', 'wrong')$$, :e4), 'Reverse those payments first');
select rb_reverse_supplier_payment(:pay1, '2026-11-28', 'Paid twice');
select t_ok((select outstanding_paise from expenses where id = :e4) = 236000, 'Reversing the payment opens the bill again');
select t_ok(t_books_agree(), 'Books agree after the expense bill and payment');

-- 5. After GST registration the GST on bills is claimed
reset role;
update app_settings set gstin = '27AAAAA0000A1Z5', gst_registered_from = '2026-12-01' where id = 1;
set role authenticated;
select set_config('request.jwt.claim.sub', :'mgr', false);
select rb_save_expense(jsonb_build_object('category_id', :cat_repair, 'expense_date', '2026-12-02', 'description', 'Door lock',
  'amount_paise', 100000, 'gst_paise', 18000, 'payment_mode', 'cash')) as e5 \gset
select t_ok((select gst_claimed from expenses where id = :e5) and t_bal('10050105') = 18000 and t_bal('80020135') = 236000 + 100000,
            'GST registered from 01-Dec: the GST goes to input GST, the expense is ₹1,000');
reset role;
update app_settings set gstin = null, gst_registered_from = null where id = 1;
set role authenticated;

-- 6. Transfers
select t_err(format($$select rb_save_transfer(jsonb_build_object('from_account_id', %s, 'to_account_id', %s, 'transfer_date', '2026-11-27', 'amount_paise', 100))$$, :cash, :cash),
  'must be different');
select rb_save_transfer(jsonb_build_object('from_account_id', :cash, 'to_account_id', :bank1, 'transfer_date', '2026-11-27', 'amount_paise', 50000)) as tf1 \gset
select t_ok((select transfer_no from money_transfers where id = :tf1) = 'TRN-CTR/2611/00001' and t_bal('10010110') = -120000 - 118000 - 50000,
            'Cash paid into the bank: cash down ₹500');

-- 7. Partners
select set_config('request.jwt.claim.sub', :'acc', false);
select rb_save_partner_entry(jsonb_build_object('kind', 'capital_in', 'partner_id', 1, 'entry_date', '2026-11-20', 'amount_paise', 1000000,
  'money_account_id', :cash)) as pt1 \gset
select rb_save_partner_entry(jsonb_build_object('kind', 'drawings', 'partner_id', 2, 'entry_date', '2026-11-27', 'amount_paise', 200000,
  'money_account_id', :cash)) as pt2 \gset
select t_ok(t_bal('50010130') = -1000000 and t_bal('50010135') = 200000, 'Capital brought in (Cr capital) and drawings (Dr current account)');
select t_ok((select capital_paise from rb_partner_balances() where partner_id = 1) >= 1000000
        and (select current_paise from rb_partner_balances() where partner_id = 2) <= -200000, 'Partner balances show each partner');
select t_err($$select rb_save_partner_entry(jsonb_build_object('kind', 'capital_in', 'partner_id', 9, 'entry_date', '2026-11-20', 'amount_paise', 100, 'money_account_id', 1))$$,
  'choose the partner');

-- 8. Day-end cash count
reset role;
select t_cash('10010110', '2026-11-28') as book28 \gset
set role authenticated;
select t_err(format($$select rb_save_cash_count(jsonb_build_object('money_account_id', %s, 'count_date', '2026-11-28', 'counted_paise', %s))$$, :cash, :book28 - 10000),
  'give the reason');
select rb_save_cash_count(jsonb_build_object('money_account_id', :cash, 'count_date', '2026-11-28', 'counted_paise', :book28 - 10000,
  'reason', 'Change given short')) as cc1 \gset
select t_ok((select difference_paise from cash_counts where id = :cc1) = -10000 and t_bal('80080135') = 10000,
            'Cash ₹100 short: posted to other operating expenses with the reason');
select t_ok(t_cash('10010110', '2026-11-28') = :book28 - 10000, 'The book cash now equals the cash counted');
select t_err(format($$select rb_save_cash_count(jsonb_build_object('money_account_id', %s, 'count_date', '2026-11-28', 'counted_paise', 0))$$, :cash), 'already counted');
select t_ok(((rb_cash_book(:cash, '2026-11-01', '2026-11-30'))->>'closing_paise')::bigint = t_cash('10010110', '2026-11-30')
        and jsonb_array_length((rb_cash_book(:cash, '2026-11-01', '2026-11-30'))->'counts') = 2, 'The cash book shows the closing balance and the counts');

-- 9. Bank reconciliation, November, main bank account
select rb_bank_recon(:bank1, '2026-11-01') as br \gset
select t_ok(jsonb_array_length(:'br'::jsonb->'lines') > 0, 'The reconciliation lists the bank entries');
select rb_save_bank_recon(jsonb_build_object('account_id', :bank1, 'month', '2026-11-01', 'statement_balance_paise', 123,
  'ticks', (select jsonb_agg(jsonb_build_object('line_id', x->'line_id', 'cleared', true)) from jsonb_array_elements(:'br'::jsonb->'lines') x)));
select t_err(format($$select rb_save_bank_recon(jsonb_build_object('account_id', %s, 'month', '2026-11-01', 'statement_balance_paise', 123, 'finish', true))$$, :bank1),
  'a difference of');
select t_ok(rb_save_bank_recon(jsonb_build_object('account_id', :bank1, 'month', '2026-11-01', 'statement_balance_paise', t_cash('10010205', '2026-11-30'),
  'finish', true))->>'difference_paise' = '0', 'Every entry ticked and the statement agrees: the month is finished');
select t_ok((select status from bank_recons where money_account_id = :bank1 and month = '2026-11-01') = 'done', 'November marked reconciled');
select t_err(format($$select rb_save_bank_recon(jsonb_build_object('account_id', %s, 'month', '2026-11-01'))$$, :bank1), 'already reconciled');
select t_ok(jsonb_array_length((rb_bank_recon(:bank1, '2026-12-01'))->'lines') = 0, 'Entries cleared in November do not show again in December');
select rb_reopen_bank_recon(:bank1, '2026-11-01', 'Statement re-checked');
select t_ok((select status from bank_recons where money_account_id = :bank1 and month = '2026-11-01') = 'draft', 'Reopened with a reason');

-- 10. Month-end step 1: labour and overheads into stock (AS 2), October 2026
select rb_save_stock_count(jsonb_build_object('purpose', 'opening', 'count_date', '2026-10-01', 'lines', jsonb_build_array(
  jsonb_build_object('item_id', :rm, 'qty', 10, 'unit', 'kg', 'rate_paise', 10000),
  jsonb_build_object('item_id', :oil, 'qty', 2, 'unit', 'l', 'rate_paise', 15000),
  jsonb_build_object('item_id', :pk, 'qty', 40, 'unit', 'pc', 'rate_paise', 1000)))) as os \gset
select set_config('request.jwt.claim.sub', :'dir', false);
select rb_post_stock_count(:os);
select set_config('request.jwt.claim.sub', :'mgr', false);
select (rb_save_preparation(jsonb_build_object('batch_date', '2026-10-05', 'raw_item_id', :rm, 'raw_qty', 6, 'raw_unit', 'kg',
  'output_qty', 5, 'output_unit', 'kg', 'stages', jsonb_build_array(jsonb_build_object('stage', 'Clean', 'wastage', 1000)))))::text::bigint as l1 \gset
select rb_save_production(jsonb_build_object('batch_date', '2026-10-06', 'output_item_id', :fg,
  'inputs', jsonb_build_array(jsonb_build_object('item_id', :wp, 'qty', 4, 'unit', 'kg'), jsonb_build_object('item_id', :oil, 'qty', 500, 'unit', 'ml')),
  'outputs', jsonb_build_array(jsonb_build_object('pack_id', :jar, 'packs', 16)))) as p1 \gset
select rb_save_expense(jsonb_build_object('category_id', :cat_wages, 'expense_date', '2026-10-31', 'description', 'Cooks, October',
  'amount_paise', 300000, 'payment_mode', 'cash'));
select rb_save_expense(jsonb_build_object('category_id', :cat_krent, 'expense_date', '2026-10-31', 'description', 'Kitchen rent, October',
  'amount_paise', 200000, 'payment_mode', 'bank'));
select set_config('request.jwt.claim.sub', :'acc', false);
select rb_absorption_preview('2026-10-01') as ap \gset
select t_ok((:'ap'::jsonb->>'demo')::boolean = false and (:'ap'::jsonb->>'method') = 'kg', 'October has real batches, so the real records are used; method kg produced');
select t_ok((:'ap'::jsonb->'detail'->>'pool_paise')::bigint = 500000, 'Pool: kitchen wages ₹3,000 + kitchen rent ₹2,000');
select t_ok((:'ap'::jsonb->'detail'->>'capitalised_paise')::bigint = 500000, 'Everything made is still on hand, so all ₹5,000 goes into stock');
select t_ok((select count(*) from jsonb_object_keys(:'ap'::jsonb->'compare')) = 4, 'The preview compares all four methods');
reset role;
update app_settings set normal_output_kg = 8 where id = 1;
set role authenticated;
select rb_absorption_preview('2026-10-01') as ap2 \gset
select t_ok((:'ap2'::jsonb->'detail'->>'capitalised_paise')::bigint = 400000 and (:'ap2'::jsonb->'detail'->>'stays_in_pl_paise')::bigint = 100000,
            'Normal output 8 kg, actual 4 kg: half the fixed rent (₹1,000) stays in profit and loss');
select t_err($$select rb_post_absorption('2099-12-01')$$, 'once Dec-2099 has ended');
select rb_post_absorption('2026-10-01') as run1 \gset
select t_ok(t_bal('70030140') = -400000 and t_bal('10030125') + t_bal('10030120') - (select coalesce(sum(value_paise), 0) from stock_moves where kind <> 'overhead'
            and item_id in (:fg, :wp)) = 400000, 'Posted: ₹4,000 into stock, credited to overhead absorption');
select t_ok((select count(*) from stock_moves where month_end_run_id = :run1 and kind = 'overhead') >= 1, 'Overheads added to the stock record as "overhead" moves');
select t_ok(t_books_agree(), 'Books agree after the month-end step');
select t_err($$select rb_post_absorption('2026-10-01')$$, 'already in stock');
select set_config('request.jwt.claim.sub', :'dir', false);
select t_err(format($$select rb_reverse_batch(%s, '2026-10-31', 'wrong')$$, :'p1'), 'already in stock');
select set_config('request.jwt.claim.sub', :'acc', false);
select rb_reverse_month_end(:run1, 'Wages were wrong');
select t_ok(t_bal('70030140') = 0 and (select status from month_end_runs where id = :run1) = 'reversed' and t_books_agree(),
            'Reversing the run takes the overheads out of stock again');
select rb_post_absorption('2026-10-01') as run2 \gset
select t_ok((select amount_paise from month_end_runs where id = :run2) = 400000, 'Run again after the correction');

-- Changing the sharing method: a Director only, with a reason
select t_err($$select rb_set_absorption_method('batches', 'test')$$, 'Only a Director');
select set_config('request.jwt.claim.sub', :'fc', false);
select t_err($$select rb_set_absorption_method('batches', 'test')$$, 'Only a Director');
select set_config('request.jwt.claim.sub', :'dir', false);
select t_err($$select rb_set_absorption_method('batches', '')$$, 'give the reason');
select t_err($$select rb_set_absorption_method('kg', 'same')$$, 'already the method');
select rb_set_absorption_method('batches', 'CA advised batches suit our mix better');
select t_ok((select absorption_method from app_settings) = 'batches'
        and (select count(*) from absorption_method_log where new_method = 'batches' and reason like 'CA advised%') = 1
        and exists (select 1 from audit_log where action = 'ABSORPTION_METHOD'), 'Method changed, with the reason in the change log and audit log');
select t_ok(jsonb_array_length((rb_absorption_preview('2026-10-01'))->'log') = 1, 'The preview shows the change log');

-- 11. Month-end step 2: provision for doubtful debts
select t_err($$select rb_save_cashbank_settings(jsonb_build_object('doubtful_debt_bands', jsonb_build_array(jsonb_build_object('upto', 30, 'pct', 5), jsonb_build_object('upto', 10, 'pct', 10), jsonb_build_object('upto', null, 'pct', 50))))$$,
  'go up from band to band');
select t_err($$select rb_save_cashbank_settings(jsonb_build_object('doubtful_debt_bands', jsonb_build_array(jsonb_build_object('upto', 0, 'pct', 0), jsonb_build_object('upto', 30, 'pct', 5))))$$,
  'open-ended');
select t_err($$select rb_save_cashbank_settings(jsonb_build_object('doubtful_debt_bands', jsonb_build_array(jsonb_build_object('upto', 0, 'pct', 0), jsonb_build_object('upto', null, 'pct', 120))))$$,
  'between 0 and 100');
select rb_save_cashbank_settings(jsonb_build_object('doubtful_debt_bands', jsonb_build_array(jsonb_build_object('upto', 0, 'pct', 0),
  jsonb_build_object('upto', 30, 'pct', 5), jsonb_build_object('upto', null, 'pct', 50)), 'doubtful_debt_other_pct', 10,
  'doubtful_debt_rates_note', 'Rates from the CA, Nov 2026'));
select t_ok(not (select doubtful_debt_rates_example from app_settings), 'Saving the CA''s rates clears the "example" flag');
-- An old balance brought forward from before the app (not on an invoice): ₹5,000.
reset role;
select set_config('rb.ledger', 'on', false);
select rb_post_engine(jsonb_build_object('journal_date', '2026-09-15', 'source', 'opening', 'narration', 'Opening balance: Test Old Customer',
  'department_id', rb_cb_dept('CC005'), 'is_demo', false),
  jsonb_build_array(jsonb_build_object('account_code', '10020105', 'debit_paise', 500000, 'customer_id', (select id from customers where code = 'T-OB')),
                    jsonb_build_object('account_code', '97010105', 'credit_paise', 500000)));
select set_config('rb.ledger', 'off', false);
set role authenticated;
select rb_provision_preview('2026-10-01') as pp \gset
select t_ok((:'pp'::jsonb->>'required_paise')::bigint = 50000 and (:'pp'::jsonb->>'change_paise')::bigint = 50000,
            'October: 10% of the ₹5,000 not on an invoice = ₹500 needed');
select rb_post_provision('2026-10-01') as pv1 \gset
select t_ok(t_bal('10020225') = -50000 and t_bal('80080140') = 50000, 'Posted: Dr provision for doubtful debts (expense), Cr provision (against customers)');
select t_err($$select rb_post_provision('2026-10-01')$$, 'already posted');
-- A credit invoice of November, aged at 30-Nov (due 10 days after the invoice date).
select set_config('request.jwt.claim.sub', :'mgr', false);
select rb_save_sale(jsonb_build_object('customer_id', :tr1, 'invoice_date', '2026-11-01', 'payment_mode', 'credit',
  'lines', jsonb_build_array(jsonb_build_object('item_id', :fg, 'pack_id', :jar, 'packs', 4)))) as sl1 \gset
select set_config('request.jwt.claim.sub', :'acc', false);
select rb_provision_preview('2026-11-01') as pp2 \gset
select t_ok((:'pp2'::jsonb->>'required_paise')::bigint = 50000 + 5000 and (:'pp2'::jsonb->>'existing_paise')::bigint = 50000
        and (:'pp2'::jsonb->>'change_paise')::bigint = 5000
        and (:'pp2'::jsonb->'bands'->1->>'amount_paise')::bigint = (:'sl1'::jsonb->>'total_paise')::bigint,
            'November preview: the ₹1,000 invoice is 19 days overdue (5% = ₹50) on top of the ₹500 already held');
select t_ok(exists (select 1 from jsonb_array_elements(:'pp2'::jsonb->'customers') c where (c->>'customer_id')::int = :tr1), 'The preview lists each customer');
select rb_reverse_month_end(:pv1, 'Rates changed');
select t_ok(t_bal('10020225') = 0 and t_bal('80080140') = 0, 'Reversing the provision takes it back out');
select t_ok(t_books_agree(), 'Books agree after the provision');

-- 12. Reversals and learning-phase deletes
select set_config('request.jwt.claim.sub', :'mgr', false);
select t_err(format($$select rb_reverse_cash_entry('transfer', %s, '2026-11-28', 'x')$$, :tf1), 'right to reverse');
select set_config('request.jwt.claim.sub', :'dir', false);
select rb_reverse_cash_entry('transfer', :tf1, '2026-11-28', 'Money never left the till');
select t_ok((select status from money_transfers where id = :tf1) = 'reversed', 'A transfer is reversed, with its reason');
select t_err(format($$select rb_reverse_cash_entry('transfer', %s, '2026-11-28', 'x')$$, :tf1), 'already reversed');
select rb_reverse_expense(:e1, '2026-11-28', 'Paid by the landlord');
select t_ok((select status from expenses where id = :e1) = 'reversed' and t_bal('80020110') = 0, 'An expense is reversed');
-- The Accountant is still in their learning phase: a Director may fully delete their entry.
select rb_hard_delete_cash_entry('partner', :pt2);
select t_ok(not exists (select 1 from partner_entries where id = :pt2) and t_bal('50010135') = 0, 'A learning-phase entry is fully deleted');
select t_err(format($$select rb_hard_delete_cash_entry('expense', %s)$$, :e4), 'learning phase');
select t_ok(t_books_agree(), 'Books agree after reversals and deletes');
select t_ok(exists (select 1 from audit_log where action = 'EXPENSE') and exists (select 1 from audit_log where action = 'APPROVE_EXPENSE')
        and exists (select 1 from audit_log where action = 'MONTH_END_ABSORPTION'), 'Expenses, approvals and month-end runs are in the audit log');

-- 13. Remove demo data, then go live
select rb_remove_demo_data('REMOVE DEMO');
select t_ok(not exists (select 1 from expenses where is_demo) and not exists (select 1 from month_end_runs where is_demo)
        and not exists (select 1 from money_transfers where is_demo) and not exists (select 1 from cash_counts where is_demo),
            'DEMO expenses, transfers, counts and month-end runs removed');
select t_ok(t_books_agree(), 'Books still agree without the DEMO data');
select rb_go_live('2027-04-01', 'GO LIVE');
select t_ok(not exists (select 1 from expenses) and not exists (select 1 from month_end_runs) and not exists (select 1 from bank_recons),
            'Go-live clears training expenses, month-end runs and reconciliations');
select t_ok((select count(*) from money_accounts) = 6 and (select count(*) from expense_categories) >= 30, 'Accounts and categories stay');
select set_config('request.jwt.claim.sub', :'mgr', false);
select rb_save_expense(jsonb_build_object('category_id', :cat_elec, 'expense_date', '2027-04-02', 'description', 'Shop electricity',
  'amount_paise', 50000, 'payment_mode', 'cash')) as e9 \gset
select t_ok((select expense_no from expenses where id = :e9) = 'EXP/2704/00001', 'After go-live, expenses start at EXP/YYMM/00001');

reset role;
\echo ALL MODULE 6 TESTS PASSED
