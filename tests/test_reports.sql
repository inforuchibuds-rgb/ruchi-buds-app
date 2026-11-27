-- Behaviour tests for 08_reports.sql. Run against a throwaway database only,
-- after supabase_stub.sql and sql/01 to sql/08, from the tests/ folder.
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
-- Balance of accounts (debit minus credit) up to a date, DEMO included or not.
create or replace function public.t_bal(p_code text, p_to date, p_demo boolean) returns bigint language sql security definer as $$
  select coalesce(sum(l.debit_paise - l.credit_paise), 0)::bigint from journal_lines l join journals j on j.id = l.journal_id
  where l.account_code like p_code and j.status <> 'draft' and l.journal_date <= p_to and (p_demo or not l.is_demo) $$;
grant execute on function public.t_bal(text, date, boolean) to authenticated;
-- Statements hold together: the balance sheet balances, profit = the books, cash flow = change in cash.
create or replace function public.t_fs_ok(p_from date, p_to date, p_demo boolean) returns boolean language plpgsql as $$
declare f jsonb := rb_financial_statements(p_from, p_to, p_demo); c jsonb := rb_cash_flow(p_from, p_to, p_demo);
begin
  return (f->>'bs_difference')::bigint = 0 and (f->'pl'->>'check')::bigint = 0 and (f->'pl_prev'->>'check')::bigint = 0
     and (c->'cur'->>'difference')::bigint = 0 and (c->'prev'->>'difference')::bigint = 0
     and (c->'cur'->>'A_pbt')::bigint = (f->'pl'->>'before_tax')::bigint
     and (c->'cur'->>'closing_cash')::bigint = t_bal('1001%', p_to, p_demo);
end $$;
grant execute on function public.t_fs_ok(date, date, boolean) to authenticated;
create or replace function public.t_cf(p_from date, p_to date, p_demo boolean, p_key text) returns bigint language sql as $$
  select coalesce((rb_cash_flow(p_from, p_to, p_demo)->'cur'->>p_key)::bigint, 0) $$;
grant execute on function public.t_cf(date, date, boolean, text) to authenticated;
create or replace function public.t_line(p_date date, p_demo boolean, p_line text) returns bigint language sql as $$
  select coalesce((rb_financial_statements(p_date, p_date, p_demo)->'bs'->'lines'->>p_line)::bigint, 0) $$;
grant execute on function public.t_line(date, boolean, text) to authenticated;
create or replace function public.t_fsl(p_code text) returns text language sql security definer as $$ select rb_fs_line(p_code) $$;
grant execute on function public.t_fsl(text) to authenticated;

-- 0. The file is in place
select t_ok((select available from screens where code = 'reports'), 'Reports screen is switched on');
select t_ok(exists (select 1 from permissions where code = 'power.year_end'), 'New right: year-end close');
select t_ok((select cash_flow from accounts where code = '20010215') = 'non_cash' and (select cash_flow from accounts where code = '40020120') = 'operating',
            'Accumulated depreciation is non-cash; rent equalisation is operating');
select t_ok(not exists (select 1 from accounts a where a.level = 'posting' and a.e002_active and a.statement <> 'CONSOL'
                        and (select statement from fs_lines where code = rb_fs_line(a.code)) <> case when a.statement = 'PL' then 'PL' else 'BS' end),
            'Every account maps to a line of its own statement');

-- People
insert into auth.users(id, email) values ('00000000-0000-0000-0000-0000000000d1', 'info.ruchibuds@gmail.com');
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
select rb_login_ok() is not null;
select rb_invite_user('acc@example.com', 'Real Accountant', 'RA', null, (select id from user_categories where name='Accountant'), null);
select rb_invite_user('mgr@example.com', 'Real Manager', 'RM', null, (select id from user_categories where name='Manager'), null);
reset role;
insert into auth.users(id, email) values
 ('00000000-0000-0000-0000-0000000000a1', 'acc@example.com'),
 ('00000000-0000-0000-0000-0000000000e1', 'mgr@example.com');
set role authenticated;
\set dir '00000000-0000-0000-0000-0000000000d1'
\set acc '00000000-0000-0000-0000-0000000000a1'
\set mgr '00000000-0000-0000-0000-0000000000e1'
\set bank '(select id from money_accounts where account_code = ''10010205'')'

-- 1. Who can see what
select set_config('request.jwt.claim.sub', :'mgr', false);
select t_err($$select rb_financial_statements('2026-04-01', '2026-11-30')$$, 'right to see reports');
select t_err($$select rb_report_dashboard()$$, 'right to see reports');
select t_err($$select rb_sheets_rows('accounts')$$, 'right to copy the data');
select t_ok((select count(*) from fs_map) = 0, 'A Manager cannot read the statement mapping');
select set_config('request.jwt.claim.sub', :'acc', false);
select t_ok((rb_report_dashboard('2026-11-30')->>'margin_ok')::boolean, 'The Accountant sees the dashboard with margins');
select t_err($$select rb_post_year_end('2026-03-31')$$, 'right to close the year');
select t_err($$select rb_save_report_links('{"looker_url": "https://lookerstudio.google.com/reporting/abc"}')$$, 'right to change the report links');

-- 2. The DEMO books: statements hold together for several periods
select t_ok(t_fs_ok('2026-04-01', '2026-11-30', true), 'FY to date (DEMO): balance sheet balances, profit agrees, cash flow = change in cash');
select t_ok(t_fs_ok('2026-11-01', '2026-11-30', true), 'November (DEMO)');
select t_ok(t_fs_ok('2026-10-01', '2026-10-31', true), 'October (DEMO)');
select t_ok(t_fs_ok('2026-11-10', '2026-11-20', true), 'Any dates (DEMO)');
select t_ok(t_fs_ok('2026-04-01', '2026-11-30', false), 'Without the DEMO entries');
select t_ok((rb_financial_statements('2026-11-01', '2026-11-30')->>'prev_from') = '2026-10-01'
        and (rb_financial_statements('2025-04-01', '2026-03-31')->>'prev_from') = '2024-04-01'
        and (rb_financial_statements('2026-04-01', '2026-11-30')->>'prev_from') = '2025-04-01'
        and (rb_financial_statements('2026-04-01', '2026-11-30')->>'prev_to') = '2025-11-30'
        and (rb_financial_statements('2026-04-01', '2026-11-30')->>'bs_prev_date') = '2026-03-31', 'Comparatives: previous month, previous year, same period last year');
-- Current maturities of long-term loans = what module 7 says falls due within 12 months
select t_ok((rb_financial_statements('2026-11-30', '2026-11-30')->'bs'->>'current_maturities')::bigint =
            (select sum(within_12_paise) from jsonb_to_recordset(rb_loans_summary('2026-11-30')->'loans') as x(within_12_paise bigint, account_code text, status text)
             where status <> 'draft' and t_fsl(account_code) = 'BS_LTB'),
            'Current maturities agree with the loans summary');
select t_ok(t_line('2026-11-30', true, 'BS_LTB') + t_line('2026-11-30', true, 'BS_STB') =
            -(t_bal('4001%', '2026-11-30', true) + t_bal('40020110', '2026-11-30', true) + t_bal('300601%', '2026-11-30', true) - t_bal('30060130', '2026-11-30', true)),
            'Borrowings split between long and short term without changing the total');
select t_ok((rb_cash_flow('2026-04-01', '2026-11-30')->'cur'->>'non_cash_investing')::bigint = 24000000,
            'The DEMO van lease (₹2,40,000) is shown as a non-cash transaction, not as cash spent');
select t_ok(t_cf('2026-04-01', '2026-11-30', true, 'A_adj_prov') = 65000, 'Provision for doubtful debts (₹650) added back');
select t_ok(t_cf('2026-04-01', '2026-11-30', true, 'A_adj_dep') = (select sum((e->>'amount')::bigint) from jsonb_array_elements(rb_financial_statements('2026-04-01', '2026-11-30')->'pl'->'accounts') e where e->>'line' = 'PL_DEP'),
            'Depreciation added back = depreciation charged');

-- 3. Real entries: take-on, sales, equipment, depreciation, a loan and a finance lease
reset role;
select set_config('request.jwt.claim.sub', :'dir', false);
select rb_post_engine(jsonb_build_object('journal_date', '2026-04-01', 'source', 'opening', 'narration', 'Take-on: bank and capital', 'department_id', rb_pur_default_dept()),
  jsonb_build_array(jsonb_build_object('account_code', '10010205', 'debit_paise', 10000000),
                    jsonb_build_object('account_code', '50010130', 'credit_paise', 10000000, 'partner_id', 1)));
select rb_post_engine(jsonb_build_object('journal_date', '2026-11-05', 'source', 'manual', 'narration', 'Cash sales', 'department_id', rb_pur_default_dept()),
  jsonb_build_array(jsonb_build_object('account_code', '10010205', 'debit_paise', 500000), jsonb_build_object('account_code', '60010120', 'credit_paise', 500000)));
select rb_post_engine(jsonb_build_object('journal_date', '2026-11-06', 'source', 'manual', 'narration', 'Mixer grinder', 'department_id', rb_pur_default_dept()),
  jsonb_build_array(jsonb_build_object('account_code', '20010125', 'debit_paise', 3000000), jsonb_build_object('account_code', '10010205', 'credit_paise', 3000000)));
select rb_post_engine(jsonb_build_object('journal_date', '2026-11-30', 'source', 'manual', 'narration', 'Depreciation', 'department_id', rb_pur_default_dept()),
  jsonb_build_array(jsonb_build_object('account_code', '80070105', 'debit_paise', 200000), jsonb_build_object('account_code', '20010215', 'credit_paise', 200000)));
set role authenticated;
select rb_save_loan(jsonb_build_object('kind', 'loan', 'name', 'Oven loan', 'lender', 'SBI', 'start_date', '2026-11-10', 'principal_paise', 2400000,
  'annual_rate', 12, 'instalments', 24, 'fee_paise', 24000, 'money_account_id', :bank)) as l1 \gset
select rb_start_loan(:l1);
select rb_save_loan(jsonb_build_object('kind', 'finance_lease', 'name', 'Sealer lease', 'lender', 'Sai Leasing', 'start_date', '2026-11-12',
  'asset_name', 'Band sealer', 'asset_account', '20010125', 'kitchen', true, 'fair_value_paise', 1000000, 'instalments', 12, 'emi_paise', 90000,
  'in_advance', false, 'useful_life_months', 36, 'money_account_id', :bank)) as l2 \gset
select rb_start_loan(:l2);
select t_ok(t_fs_ok('2026-11-01', '2026-11-30', false), 'Real November: statements hold together');
select t_ok(t_fs_ok('2026-04-01', '2026-11-30', false), 'Real FY to date: statements hold together');
select t_ok(t_cf('2026-04-01', '2026-11-30', false, 'opening_cash') = 10000000, 'Take-on cash counts as cash at the start, not as a cash flow');
select t_ok(t_cf('2026-04-01', '2026-11-30', false, 'C_partners_in') = 0, 'Take-on capital is not "capital introduced"');
select t_ok(t_cf('2026-11-01', '2026-11-30', false, 'B_ppe_out') = -3000000, 'Mixer grinder: purchase of PPE ₹30,000');
select t_ok(t_cf('2026-11-01', '2026-11-30', false, 'A_adj_dep') = 200000, 'Depreciation ₹2,000 added back');
select t_ok(t_cf('2026-11-01', '2026-11-30', false, 'C_borrow_in') = 2400000, 'Loan proceeds ₹24,000 in financing');
select t_ok(t_cf('2026-11-01', '2026-11-30', false, 'C_interest') = -24000, 'Processing fee paid shown with finance costs paid');
select t_ok(t_cf('2026-11-01', '2026-11-30', false, 'A_adj_fin') = 24000, 'Finance cost added back to profit');
select t_ok(t_cf('2026-11-01', '2026-11-30', false, 'non_cash_investing') =
            (select principal_paise from loans where id = :l2), 'Leased sealer: non-cash, not in investing or financing');
select t_ok(t_cf('2026-11-01', '2026-11-30', false, 'B_ppe_out') = -3000000 and t_cf('2026-11-01', '2026-11-30', false, 'C_lease_in') = 0,
            'The lease start is not counted as buying equipment or borrowing');
select t_ok((rb_financial_statements('2026-11-01', '2026-11-30', false)->'pl'->>'PL_REV')::bigint = 500000, 'Revenue ₹5,000');
select t_ok((rb_financial_statements('2026-04-01', '2026-11-30', false)->'bs'->'lines'->>'BS_CAP')::bigint = 10000000, 'Partners'' capital ₹1,00,000');
select t_ok((rb_financial_statements('2026-04-01', '2026-11-30', false)->'bs'->>'current_maturities')::bigint
            = (select sum(principal_paise) from loan_schedule where loan_id in (:l1, :l2) and due_date <= '2027-11-30'),
            'Current maturities: principal due by 30-Nov-2027 on the real loan and lease');

-- 4. Statement lines: the Accountant can change the mapping
select set_config('request.jwt.claim.sub', :'acc', false);
select rb_save_fs_map('{"prefix": "80050150", "line_code": "PL_FIN"}');
select t_ok(t_fsl('80050150') = 'PL_FIN', 'Bank service charges moved to finance costs');
select t_err($$select rb_save_fs_map('{"prefix": "8005", "line_code": "BS_OCA"}')$$, 'cannot go to');
select t_err($$select rb_save_fs_map('{"prefix": "1x", "line_code": "BS_OCA"}')$$, '1 to 8 digits');
select t_err($$select rb_save_fs_map('{"prefix": "123456", "line_code": "BS_OCA"}')$$, 'No account starts');
select t_err($$select rb_delete_fs_map('8')$$, 'kept');
select t_ok(t_fs_ok('2026-04-01', '2026-11-30', true), 'Still holds together after the change');
select t_ok((select count(*) from jsonb_array_elements(rb_fs_map_list()->'accounts')) > 400, 'Mapping list shows every account');

-- 5. Year-end close
reset role;
select rb_post_engine(jsonb_build_object('journal_date', '2026-03-15', 'source', 'manual', 'narration', 'March sales', 'department_id', rb_pur_default_dept()),
  jsonb_build_array(jsonb_build_object('account_code', '10010110', 'debit_paise', 5000000), jsonb_build_object('account_code', '60010120', 'credit_paise', 5000000)));
select rb_post_engine(jsonb_build_object('journal_date', '2026-03-20', 'source', 'manual', 'narration', 'March gas', 'department_id', rb_pur_default_dept()),
  jsonb_build_array(jsonb_build_object('account_code', '70030105', 'debit_paise', 500000), jsonb_build_object('account_code', '10010110', 'credit_paise', 500000)));
set role authenticated;
select set_config('request.jwt.claim.sub', :'dir', false);
select t_err($$select rb_year_end_preview('2026-03-30')$$, 'last day of a financial year');
select t_err($$select rb_post_year_end('2027-03-31')$$, 'once it has ended');
select t_ok((rb_year_end_preview('2026-03-31')->'real'->>'profit')::bigint = 4500000, 'FY 2025-26 profit ₹45,000 to close');
select t_ok((select array_agg((e->>'share')::bigint order by e->>'name') from jsonb_array_elements(rb_year_end_preview('2026-03-31')->'real'->'partners') e)
            = array[1500000, 1500000, 1500000]::bigint[], 'Shared equally by the 1:1:1 ratio');
select jsonb_array_length(rb_post_year_end('2026-03-31')) as n_ye \gset
select t_ok(:n_ye = 1, 'One closing journal (no DEMO entries in that year)');
select t_ok(t_bal('6%', '2026-03-31', false) = 0 and t_bal('7%', '2026-03-31', false) = 0, 'Profit and loss accounts are nil at 31-Mar-2026');
select t_ok((select sum(credit_paise - debit_paise) from journal_lines where account_code = '50010135' and partner_id = 2 and journal_date = '2026-03-31') = 1500000,
            'Partner 2''s current account gets ₹15,000');
select t_ok((rb_financial_statements('2025-04-01', '2026-03-31', false)->'pl'->>'profit')::bigint = 4500000,
            'The year''s statement of profit and loss still shows the profit after the close');
select t_ok(t_fs_ok('2025-04-01', '2026-03-31', false) and t_fs_ok('2026-03-01', '2026-04-30', false), 'Statements hold together across the close');
select t_ok((rb_financial_statements('2026-03-31', '2026-03-31', false)->'bs'->'lines'->>'BS_CUR')::bigint = 4500000
            and coalesce((rb_financial_statements('2026-03-31', '2026-03-31', false)->'bs'->'lines'->>'BS_RES')::bigint, 0) = 0,
            'After the close the profit is in the partners'' current accounts, not in reserves');
select t_err($$select rb_post_year_end('2026-03-31')$$, 'Nothing to close');
-- A late entry, and an earlier year never closed
reset role;
select rb_post_engine(jsonb_build_object('journal_date', '2026-03-25', 'source', 'manual', 'narration', 'Late March sale', 'department_id', rb_pur_default_dept()),
  jsonb_build_array(jsonb_build_object('account_code', '10010110', 'debit_paise', 300000), jsonb_build_object('account_code', '60010120', 'credit_paise', 300000)));
select rb_post_engine(jsonb_build_object('journal_date', '2025-03-10', 'source', 'manual', 'narration', 'Old sale', 'department_id', rb_pur_default_dept()),
  jsonb_build_array(jsonb_build_object('account_code', '10010110', 'debit_paise', 100000), jsonb_build_object('account_code', '60010120', 'credit_paise', 100000)));
set role authenticated;
select t_ok((rb_year_end_preview('2026-03-31')->'real'->>'profit')::bigint = 300000
        and (rb_year_end_preview('2026-03-31')->'real'->>'earlier_unclosed')::bigint = -100000, 'Preview shows the late ₹3,000 and the earlier unclosed year');
select t_err($$select rb_post_year_end('2026-03-31')$$, 'Close the earlier year first');
select rb_post_year_end('2025-03-31');
select rb_post_year_end('2026-03-31');
select t_ok(t_bal('6%', '2026-03-31', false) = 0, 'Late entry closed by a second closing journal');
select t_ok((select count(*) from journals where source = 'year_end' and status = 'posted') = 3, 'Three closing journals');
-- Reverse the latest close: the year shows as open again
select rb_reverse_journal((select max(id) from journals where source = 'year_end'), '2026-03-31', 'Test');
select t_ok((rb_year_end_preview('2026-03-31')->'real'->>'profit')::bigint = 300000, 'After reversing, ₹3,000 is open again');
select rb_post_year_end('2026-03-31');

-- 6. Report links and the Sheets copy
select rb_save_report_links('{"looker_url": "https://lookerstudio.google.com/u/0/reporting/abc-123/page/p1"}');
select t_ok((select looker_url from app_settings) = 'https://lookerstudio.google.com/embed/reporting/abc-123/page/p1', 'Looker link saved as an embed link');
select t_err($$select rb_save_report_links('{"looker_url": "https://example.com/x"}')$$, 'must start with');
reset role;
select set_config('request.jwt.claim.role', 'service_role', false);
select set_config('request.jwt.claim.sub', '', false);
select t_ok((select array_agg(x) from rb_sheets_datasets() x) = array['accounts', 'monthly_balances', 'sales_lines', 'purchase_lines', 'expenses', 'loans'], 'Six datasets');
select t_ok(jsonb_array_length(rb_sheets_rows('accounts', 0, 5000)) > 400, 'Accounts dataset');
select t_ok(jsonb_array_length(rb_sheets_rows('monthly_balances', 0, 5000)) > 50, 'Monthly balances dataset');
select t_ok((select sum((e->>'net')::numeric) from jsonb_array_elements(rb_sheets_rows('monthly_balances', 0, 5000)) e) = 0, 'Monthly balances add up to nil');
select t_ok(jsonb_array_length(rb_sheets_rows('sales_lines', 0, 5000)) >= 10 and not (rb_sheets_rows('sales_lines', 0, 1)->0 ? 'sid'), 'Sales lines dataset');
select t_ok(jsonb_array_length(rb_sheets_rows('purchase_lines', 0, 5000)) >= 10, 'Purchase lines dataset');
select t_ok(jsonb_array_length(rb_sheets_rows('expenses', 0, 5000)) >= 10, 'Expenses dataset');
select t_ok(jsonb_array_length(rb_sheets_rows('loans', 0, 5000)) >= 5, 'Loans dataset');
select t_ok(jsonb_array_length(rb_sheets_rows('sales_lines', 2, 3)) = 3, 'Datasets come in pages');
select rb_set_report_sheet('https://docs.google.com/spreadsheets/d/abc/edit');
select rb_log_backup('sheets', 'ok', 6, 1234, 'Weekly copy');
select set_config('request.jwt.claim.role', 'authenticated', false);
select set_config('request.jwt.claim.sub', :'dir', false);
set role authenticated;
select t_ok((rb_report_dashboard('2026-11-30')->'sheets_copy'->>'status') = 'ok'
        and (rb_report_dashboard('2026-11-30')->'links'->>'report_sheet_url') like 'https://docs.google.com/%', 'Dashboard shows the last Sheets copy and the sheet link');

-- 7. Dashboard and reports
select t_ok((rb_report_dashboard('2026-11-30')->>'sales_mtd')::bigint = (select sum(net_paise) from rb_report_sales('2026-11-01', '2026-11-30')),
            'Dashboard sales this month = the sales report');
select t_ok((rb_report_dashboard('2026-11-30', false)->>'sales_mtd')::bigint = 0, 'Without DEMO: no sales yet');
select t_ok((rb_report_dashboard('2026-11-30')->>'cash_bank')::bigint = t_bal('1001%', '2026-11-30', true), 'Cash and bank = the books');
select t_ok(jsonb_array_length(rb_report_dashboard('2026-11-30')->'daily') = 30 and jsonb_array_length(rb_report_dashboard('2026-11-30')->'monthly') = 12,
            '30 days and 12 months of sales for the charts');
select t_ok((select count(*) from rb_report_purchases('2026-10-01', '2026-11-30')) >= 10, 'Purchases report lists the DEMO bills');

-- 8. Running the file again keeps the Accountant's mapping
reset role;
\ir ../sql/08_reports.sql
set client_min_messages = notice;
select t_ok(t_fsl('80050150') = 'PL_FIN', 'Running 08 again keeps the mapping change');

-- 9. Remove demo data: the real statements still hold together
set role authenticated;
select set_config('request.jwt.claim.sub', :'dir', false);
select rb_remove_demo_data('REMOVE DEMO');
select t_ok(t_fs_ok('2026-04-01', '2026-11-30', true) and t_fs_ok('2025-04-01', '2026-03-31', true), 'After removing DEMO data the statements hold together');

reset role;
\echo ALL MODULE 8 TESTS PASSED
