-- Behaviour tests for 07_loans_leases.sql. Run against a throwaway database only,
-- after supabase_stub.sql and sql/01 to sql/07.
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
-- The loans subledger agrees with the books, DEMO and real separately:
-- every borrowings account = what the loans say is owed on it; interest
-- payable = interest accrued; lease assets, depreciation, rent equalisation
-- and deposits (on the loans screen's own journals) likewise. And the books balance.
create or replace function public.t_ll_agree() returns boolean language sql security definer as $$
  with d(demo) as (values (true), (false)),
  bk as (select l.account_code acc, l.is_demo demo, sum(l.debit_paise - l.credit_paise) bal
         from journal_lines l join journals j on j.id = l.journal_id where j.status <> 'draft' group by 1, 2),
  bal as (select l.*, b.* from loans l cross join lateral rb_ll_bal(l.id, null, null) b),
  obal as (select o.*, b.* from op_leases o cross join lateral rb_ll_bal(null, o.id, null) b),
  want as (
    select account_code acc, is_demo demo, -sum(owed) amt from bal group by 1, 2
    union all select '30060130', is_demo, -sum(accrued) from bal group by 2
    union all select asset_account, is_demo, sum(asset) from bal where kind = 'finance_lease' group by 1, 2
    union all select acc_dep_account, is_demo, -sum(depreciation) from bal where kind = 'finance_lease' group by 1, 2
    union all select '40020120', is_demo, -sum(equalisation) from obal group by 2),
  w as (select acc, demo, sum(amt) amt from want group by 1, 2)
  select (select sum(debit_paise) = sum(credit_paise) from journal_lines)
     and not exists (select 1 from w left join bk using (acc, demo) where coalesce(bk.bal, 0) <> w.amt)
     and not exists (select 1 from loans l where (select owed from rb_ll_bal(l.id, null, null)) < 0)
     and (select coalesce(sum(debit_paise - credit_paise), 0) from journal_lines where account_code in ('20050130', '10020335')
            and journal_id in (select journal_id from loan_entries union select reversal_journal_id from loan_entries))
         = (select coalesce(sum(deposit), 0) from obal) $$;
create or replace function public.t_owed(p_loan bigint) returns bigint language sql security definer as $$ select owed from rb_ll_bal(p_loan, null, null) $$;
create or replace function public.t_held(p_loan bigint) returns bigint language sql security definer as $$ select accrued from rb_ll_bal(p_loan, null, null) $$;
create or replace function public.t_eq(p_ol bigint) returns bigint language sql security definer as $$ select equalisation from rb_ll_bal(null, p_ol, null) $$;
create or replace function public.t_acc_at(p_loan bigint, p_end date) returns bigint language sql security definer as $$ select rb_ll_accrual_at(p_loan, p_end) $$;
create or replace function public.t_eq_at(p_ol bigint, p_end date) returns bigint language sql security definer as $$ select rb_ll_eq_at(p_ol, p_end) $$;
create or replace function public.t_owed_at(p_kind text, p_at date) returns bigint language sql security definer as $$
  select coalesce(sum(b.owed), 0)::bigint from loans l cross join lateral rb_ll_bal(l.id, null, p_at) b where l.kind = p_kind and not l.is_demo $$;
grant execute on function public.t_bal(text), public.t_ll_agree(), public.t_owed(bigint), public.t_held(bigint), public.t_eq(bigint),
  public.t_acc_at(bigint, date), public.t_eq_at(bigint, date), public.t_owed_at(text, date) to authenticated;
set client_min_messages = notice;

-- 0. DEMO data
select t_ok((select available from screens where code = 'loans'), 'Loans and leases screen is live');
select t_ok((select count(*) from loans where is_demo and kind = 'loan') = 2 and (select count(*) from loans where is_demo and kind = 'finance_lease') = 1
        and (select count(*) from op_leases where is_demo) = 2, 'DEMO: 2 loans, 1 finance lease and 2 operating leases');
select t_ok((select count(*) from loan_entries where is_demo) >= 10, '10+ DEMO entries');
select t_ok((select loan_no from loans where is_demo order by id limit 1) = 'DEMO-LN-001'
        and (select entry_no from loan_entries where is_demo order by id limit 1) = 'DEMO-LNE/2611/00001', 'DEMO records have their own DEMO- numbers');
select t_ok((select emi_paise from loans where loan_no = 'DEMO-LN-001') = 1300100, 'DEMO bank loan: EMI ₹13,001 on ₹4,00,000 at 10.5% over 36 months');
select t_ok((select interest_paise from loan_entries where loan_id = (select id from loans where loan_no = 'DEMO-LN-001') and kind = 'payment') = 45161
        and (select accrued_paise from loan_entries where loan_id = (select id from loans where loan_no = 'DEMO-LN-001') and kind = 'payment') = -304839,
            'DEMO EMI: ₹3,048.39 of October interest brought in is cleared, ₹451.61 charged in November');
select t_ok((select effective_rate between 11.13 and 11.14 from loans where loan_no = 'DEMO-FL-001')
        and (select principal_paise from loans where loan_no = 'DEMO-FL-001') = 24000000, 'DEMO van lease: recorded at its fair value, rate implicit 11.13%');
select t_ok((select depreciation_paise from loan_entries where kind = 'month_end' and loan_id = (select id from loans where loan_no = 'DEMO-FL-001')) = 666667,
            'DEMO van depreciated ₹6,666.67 for November (₹2,40,000 over the 36-month lease)');
select t_ok((select equalisation_paise from loan_entries where kind = 'month_end' and op_lease_id = (select id from op_leases where lease_no = 'DEMO-OL-002')) = 1569167,
            'DEMO shop: rent spread evenly, ₹15,691.67 more than paid for October (rent-free) and November');
select t_ok(not exists (select 1 from loan_entries where kind = 'month_end' and op_lease_id = (select id from op_leases where lease_no = 'DEMO-OL-001')),
            'DEMO kitchen: flat rent, so nothing to spread');
select t_ok((select count(*) from month_end_runs where is_demo and kind = 'loans_leases' and status = 'posted') = 1, 'DEMO month-end step posted for Nov 2026');
select t_ok((select expense_id is not null from op_lease_rents where lease_id = (select id from op_leases where lease_no = 'DEMO-OL-001') and n = 1),
            'The DEMO kitchen rent expense is linked to the lease');
select t_ok(t_ll_agree(), 'Loans, leases and deposits agree with the books');
select t_ok(rb_cb_balance('10010205', null) >= 0, 'DEMO bank does not go below zero');

-- People
insert into auth.users(id, email) values ('00000000-0000-0000-0000-0000000000d1', 'info.ruchibuds@gmail.com');
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
select rb_login_ok() is not null;
select rb_invite_user('acc@example.com', 'Real Accountant', 'RA', null, (select id from user_categories where name='Accountant'), null);
select rb_invite_user('mgr@example.com', 'Real Manager', 'RM', null, (select id from user_categories where name='Manager'), null);
select rb_invite_user('staff@example.com', 'Real Staff', 'RS', null, (select id from user_categories where name='Staff'), null);
reset role;
insert into auth.users(id, email) values
 ('00000000-0000-0000-0000-0000000000a1', 'acc@example.com'),
 ('00000000-0000-0000-0000-0000000000e1', 'mgr@example.com'),
 ('00000000-0000-0000-0000-0000000000c1', 'staff@example.com');
insert into suppliers (code, name) values ('T-LL', 'Test Landlord');
set role authenticated;
\set dir '00000000-0000-0000-0000-0000000000d1'
\set acc '00000000-0000-0000-0000-0000000000a1'
\set mgr '00000000-0000-0000-0000-0000000000e1'
\set staff '00000000-0000-0000-0000-0000000000c1'
\set bank '(select id from money_accounts where account_code = ''10010205'')'
\set cash '(select id from money_accounts where account_code = ''10010110'')'
\set krent '(select id from expense_categories where name = ''Kitchen rent'')'
\set srent '(select id from expense_categories where name = ''Shop or office rent'')'
\set landlord '(select id from suppliers where code = ''T-LL'')'

-- 1. Who can do what
select set_config('request.jwt.claim.sub', :'staff', false);
select t_ok((select count(*) from loans) = 0 and (select count(*) from loan_entries) = 0, 'Staff cannot read loans');
select t_err($$select rb_loans_summary()$$, 'right to see loans');
select set_config('request.jwt.claim.sub', :'mgr', false);
select t_err($$select rb_save_loan('{}')$$, 'right to add loans');
select t_err($$select rb_post_loans_month('2026-10-01')$$, 'right to run the month-end');
select set_config('request.jwt.claim.sub', :'acc', false);
select t_ok((select count(*) from loans) = 3, 'The Accountant reads loans');

-- 2. A new loan: ₹5,00,000 at 10.5% for 36 EMIs, ₹5,000 processing fee
select t_err($$select rb_save_loan(jsonb_build_object('kind', 'loan', 'name', 'x', 'lender', 'y', 'start_date', '2026-08-10', 'principal_paise', 50000000, 'annual_rate', 10.5, 'instalments', 36))$$,
             'bank account the loan money came into');
select t_err($$select rb_save_loan(jsonb_build_object('kind', 'loan', 'name', 'x', 'lender', 'y', 'start_date', '2026-08-10', 'principal_paise', 50000000, 'annual_rate', 10.5, 'money_account_id', 3))$$,
             'number of instalments');
select rb_loan_preview(jsonb_build_object('kind', 'loan', 'name', 'Oven loan', 'lender', 'SBI Andheri', 'start_date', '2026-08-10',
  'principal_paise', 50000000, 'annual_rate', 10.5, 'instalments', 36, 'money_account_id', :bank, 'fee_paise', 500000)) as pv \gset
select t_ok((:'pv'::jsonb->>'emi_paise')::bigint = 1625100 and jsonb_array_length(:'pv'::jsonb->'rows') = 36
        and (:'pv'::jsonb->>'first_due_date') = '2026-09-10' and (:'pv'::jsonb->>'account_code') = '40010105',
            'Preview: EMI ₹16,251, 36 rows, first EMI a month after, kept in Long-term Bank Loans');
select t_ok((select sum((r->>'principal_paise')::bigint) from jsonb_array_elements(:'pv'::jsonb->'rows') r) = 50000000
        and (:'pv'::jsonb->'rows'->35->>'closing_paise')::bigint = 0, 'The schedule repays exactly ₹5,00,000 and ends at nil');
select rb_save_loan(jsonb_build_object('kind', 'loan', 'name', 'Oven loan', 'lender', 'SBI Andheri', 'start_date', '2026-08-10',
  'principal_paise', 50000000, 'annual_rate', 10.5, 'rate_type', 'floating', 'instalments', 36, 'money_account_id', :bank, 'fee_paise', 500000)) as l1 \gset
select t_ok((select loan_no from loans where id = :l1) = 'TRN-LN-001' and (select status from loans where id = :l1) = 'draft'
        and (select count(*) from loan_schedule where loan_id = :l1) = 36 and t_bal('40010105') = 0, 'Saved as a draft TRN-LN-001: schedule, nothing posted');
select set_config('request.jwt.claim.sub', :'mgr', false);
select t_err(format($$select rb_start_loan(%s)$$, :l1), 'right to start');
select set_config('request.jwt.claim.sub', :'dir', false);
select rb_start_loan(:l1);
select t_ok(t_bal('10010205') = 49500000 and t_bal('91010115') = 500000 and t_bal('40010105') = -50000000,
            'Started: Dr bank ₹4,95,000, Dr processing fee ₹5,000, Cr Long-term Bank Loans ₹5,00,000');
select t_ok((select entry_no from loan_entries where loan_id = :l1) = 'TRN-LNE/2608/00001', 'Entries are numbered TRN-LNE/YYMM/00001 in training');
select t_err(format($$select rb_start_loan(%s)$$, :l1), 'already been started');
select t_err(format($$select rb_save_loan(jsonb_build_object('id', %s, 'kind', 'loan', 'name', 'x', 'lender', 'y', 'start_date', '2026-08-10', 'principal_paise', 1, 'instalments', 1, 'money_account_id', 3))$$, :l1),
             'Only a draft');

-- 3. Month-end for August: interest accrued for 22 of 31 days
select set_config('request.jwt.claim.sub', :'acc', false);
select rb_loans_month_preview('2026-08-01') as mp \gset
select t_ok((:'mp'::jsonb->>'demo')::boolean = false and (:'mp'::jsonb->>'interest_paise')::bigint = 310484,
            'August preview (real records): ₹4,375 × 22/31 = ₹3,104.84 interest accrued');
select rb_post_loans_month('2026-08-01') as r8 \gset
select t_ok(t_bal('91010105') = 310484 and t_bal('30060130') = -310484 and t_held(:l1) = 310484, 'Posted: Dr loan interest, Cr Interest Payable');
select t_err($$select rb_post_loans_month('2026-08-01')$$, 'already posted');
select t_err($$select rb_post_loans_month('2026-11-01', false)$$, 'once Nov-2026 has ended');

-- 4. EMI 1 on 10-Sep: the accrued part is cleared, the rest charged
select rb_pay_loan(jsonb_build_object('loan_id', :l1, 'pay_date', '2026-09-10', 'money_account_id', :bank, 'reference', 'ECS')) as p1 \gset
select t_ok(t_held(:l1) = 0 and t_bal('91010105') = 437500 and t_bal('30060130') = 0 and t_owed(:l1) = 50000000 - 1187600
        and t_bal('10010205') = 49500000 - 1625100, 'EMI 1: ₹11,876 repaid, ₹3,104.84 accrued cleared, ₹1,270.16 more interest; bank −₹16,251');
select t_ok((select paid_entry_id from loan_schedule where loan_id = :l1 and n = 1) = :p1, 'The schedule row is marked paid');
-- EMI 2 paid with ₹10,000 more principal than the schedule: the rest is rebuilt.
select (select principal_paise from loan_schedule where loan_id = :l1 and n = 2) as sp2 \gset
select rb_pay_loan(jsonb_build_object('loan_id', :l1, 'pay_date', '2026-10-10', 'money_account_id', :bank, 'principal_paise', :sp2 + 1000000)) as p2 \gset
select t_ok(t_owed(:l1) = 50000000 - 1187600 - :sp2 - 1000000
        and (select opening_paise from loan_schedule where loan_id = :l1 and n = 3) = t_owed(:l1)
        and (select payment_paise from loan_schedule where loan_id = :l1 and n = 3) = 1625100
        and (select payment_paise from loan_schedule where loan_id = :l1 order by n desc limit 1) < 1000000,
            'Paid ₹10,000 more than the schedule: the rest is rebuilt at the same EMI, so the last EMI is much smaller');
select t_err(format($$select rb_pay_loan(jsonb_build_object('loan_id', %s, 'pay_date', '2026-10-11', 'money_account_id', 3, 'principal_paise', 999999999))$$, :l1), 'more than is owed');

-- 5. Part-payment: keep the EMI (fewer instalments) or the end date (lower EMI)
select (select max(n) from loan_schedule where loan_id = :l1) as nmax \gset
select rb_prepay_loan(jsonb_build_object('loan_id', :l1, 'pay_date', '2026-10-15', 'money_account_id', :bank, 'principal_paise', 5000000,
  'charges_paise', 50000, 'keep', 'emi')) as pp1 \gset
select t_ok((select max(n) from loan_schedule where loan_id = :l1) < :nmax and (select emi_paise from loans where id = :l1) = 1625100
        and t_bal('91010130') = 50000, 'Part-payment of ₹50,000, EMI kept: fewer instalments; ₹500 charges to Other Finance Costs');
select (select max(n) from loan_schedule where loan_id = :l1) as nmax2 \gset
select rb_prepay_loan(jsonb_build_object('loan_id', :l1, 'pay_date', '2026-10-16', 'money_account_id', :bank, 'principal_paise', 5000000, 'keep', 'tenure')) as pp2 \gset
select t_ok((select max(n) from loan_schedule where loan_id = :l1) = :nmax2 and (select emi_paise from loans where id = :l1) < 1625100,
            'Part-payment, end date kept: the same number of instalments at a lower EMI');

-- 6. A rate change on the floating-rate loan
select t_err(format($$select rb_change_loan_rate(jsonb_build_object('loan_id', %s, 'new_rate', 11, 'from_date', '2026-10-20'))$$, :l1), 'give the reason');
select (select emi_paise from loans where id = :l1) as emi_before \gset
select rb_change_loan_rate(jsonb_build_object('loan_id', :l1, 'new_rate', 11.25, 'from_date', '2026-10-20', 'keep', 'tenure', 'reason', 'Bank letter: MCLR up'));
select t_ok((select annual_rate from loans where id = :l1) = 11.25 and (select emi_paise from loans where id = :l1) > :emi_before
        and (select count(*) from loan_rate_changes where loan_id = :l1) = 1, 'Rate 10.5% → 11.25%, end date kept: the EMI goes up, and the change is logged');
select t_ok((select interest_paise from loan_schedule where loan_id = :l1 and paid_entry_id is null order by n limit 1)
            = round((select opening_paise from loan_schedule where loan_id = :l1 and paid_entry_id is null order by n limit 1) * 0.1125 / 12),
            'The next instalment''s interest is at the new rate');

-- 7. Reversing payments: only the latest
select set_config('request.jwt.claim.sub', :'mgr', false);
select t_err(format($$select rb_reverse_loan_entry(%s, '2026-10-20', 'x')$$, :p1), 'right to reverse');
select set_config('request.jwt.claim.sub', :'acc', false);
select t_err(format($$select rb_reverse_loan_entry(%s, '2026-10-20', 'Wrong')$$, :p1), 'Reverse the latest one first');
select t_err(format($$select rb_reverse_journal((select journal_id from loan_entries where id = %s), '2026-10-20', 'x')$$, :pp2), 'Loans and leases screen');
select t_owed(:l1) as owed_before \gset
select rb_reverse_loan_entry(:pp2, '2026-10-20', 'Cheque bounced');
select t_ok(t_owed(:l1) = :owed_before + 5000000 and (select status from loan_entries where id = :pp2) = 'reversed', 'A part-payment is reversed: the ₹50,000 is owed again');
select t_ok(t_ll_agree(), 'Loans agree with the books after payments, part-payments, a rate change and a reversal');

-- 8. A loan already running: brought in at the take-on date
select rb_save_loan(jsonb_build_object('kind', 'loan', 'name', 'Old car loan', 'lender', 'HDFC', 'lender_type', 'bank', 'start_date', '2024-04-15',
  'is_takeon', true, 'takeon_date', '2026-09-01', 'takeon_accrued_paise', 150000, 'principal_paise', 20000000, 'annual_rate', 9,
  'instalments', 20, 'first_due_date', '2026-09-15', 'money_account_id', :bank)) as l2 \gset
select set_config('request.jwt.claim.sub', :'dir', false);
select rb_start_loan(:l2);
select t_ok(t_bal('97010105') = 20150000 and t_bal('40010105') = -50000000 + 1187600 + :sp2 + 1000000 + 5000000 - 20000000,
            'Take-on: Dr opening balances ₹2,01,500, Cr the loan ₹2,00,000 and Interest Payable ₹1,500');
select t_ok((select source from journals where id = (select journal_id from loan_entries where loan_id = :l2)) = 'opening', 'The take-on is an opening-balance journal');
select set_config('request.jwt.claim.sub', :'acc', false);
select rb_pay_loan(jsonb_build_object('loan_id', :l2, 'pay_date', '2026-09-15', 'money_account_id', :bank));
select t_ok(t_held(:l2) = 0, 'Its first EMI clears the interest brought in');

-- 9. A loan from a partner: interest only, all repaid at the end; paid off early
select rb_save_loan(jsonb_build_object('kind', 'loan', 'name', 'Partner loan', 'lender', 'Partner 1', 'lender_type', 'related',
  'start_date', '2026-09-01', 'principal_paise', 6000000, 'annual_rate', 12, 'method', 'bullet', 'instalments', 12, 'money_account_id', :bank)) as l3 \gset
select t_ok((select account_code from loans where id = :l3) = '30060135'
        and (select count(*) from loan_schedule where loan_id = :l3 and principal_paise = 0) = 11
        and (select interest_paise from loan_schedule where loan_id = :l3 and n = 1) = 60000,
            'A 12-month partner loan: short-term borrowings; ₹600 interest a month, all repaid with the 12th');
select rb_start_loan(:l3);
select rb_pay_loan(jsonb_build_object('loan_id', :l3, 'pay_date', '2026-10-01', 'money_account_id', :bank));
select rb_prepay_loan(jsonb_build_object('loan_id', :l3, 'pay_date', '2026-10-20', 'money_account_id', :bank, 'close', true, 'interest_paise', 37500));
select t_ok((select status from loans where id = :l3) = 'closed' and t_owed(:l3) = 0 and t_held(:l3) = 0
        and not exists (select 1 from loan_schedule where loan_id = :l3 and paid_entry_id is null), 'Paid off early: closed, nothing owed or accrued');
select t_err(format($$select rb_pay_loan(jsonb_build_object('loan_id', %s, 'pay_date', '2026-10-21', 'money_account_id', 3))$$, :l3), 'not running');

-- 10. Finance leases (AS 19)
select t_err($$select rb_loan_preview(jsonb_build_object('kind', 'finance_lease', 'name', 'x', 'lender', 'y', 'start_date', '2026-08-01', 'emi_paise', 100000, 'instalments', 12,
  'fair_value_paise', 9999999, 'asset_name', 'z', 'asset_account', '20010125', 'useful_life_months', 60))$$, 'cannot be worked out');
-- Rate given, present value above fair value: the liability is the fair value (the lower), and the rate is worked out again.
select rb_loan_preview(jsonb_build_object('kind', 'finance_lease', 'name', 'x', 'lender', 'y', 'start_date', '2026-08-01', 'emi_paise', 1000000, 'instalments', 24,
  'annual_rate', 8, 'fair_value_paise', 20000000, 'asset_name', 'z', 'asset_account', '20010125', 'useful_life_months', 60)) as fp1 \gset
select t_ok((:'fp1'::jsonb->>'principal_paise')::bigint = 20000000 and (:'fp1'::jsonb->>'pv_paise')::bigint > 20000000
        and (:'fp1'::jsonb->>'effective_rate')::numeric > 8, 'PV of payments above fair value: recorded at fair value, at a higher rate');
-- Rate given, present value below fair value: the liability is the present value.
select rb_loan_preview(jsonb_build_object('kind', 'finance_lease', 'name', 'x', 'lender', 'y', 'start_date', '2026-08-01', 'emi_paise', 1000000, 'instalments', 24,
  'annual_rate', 14, 'fair_value_paise', 30000000, 'asset_name', 'z', 'asset_account', '20010125', 'useful_life_months', 60)) as fp2 \gset
select t_ok((:'fp2'::jsonb->>'principal_paise')::bigint = (:'fp2'::jsonb->>'pv_paise')::bigint and (:'fp2'::jsonb->>'effective_rate')::numeric = 14
        and (:'fp2'::jsonb->>'pv_pct_of_fv')::numeric < 100 and (:'fp2'::jsonb->>'term_pct_of_life')::numeric = 40,
            'PV below fair value: recorded at the PV, at the rate given; the screen shows PV as % of fair value and term as % of life');
-- A kitchen machine on lease: 12 payments of ₹10,000 in advance, fair value ₹1,10,000, ₹2,000 initial direct costs.
select rb_save_loan(jsonb_build_object('kind', 'finance_lease', 'name', 'Vacuum packer lease', 'lender', 'Kitchen Leasing', 'start_date', '2026-08-01',
  'emi_paise', 1000000, 'instalments', 12, 'fair_value_paise', 11000000, 'direct_costs_paise', 200000, 'money_account_id', :bank,
  'asset_name', 'Vacuum packing machine', 'asset_account', '20010125', 'kitchen', true, 'useful_life_months', 60)) as fl \gset
select t_ok((select dep_months from loans where id = :fl) = 12 and (select asset_cost_paise from loans where id = :fl) = 11200000
        and (select dep_account from loans where id = :fl) = '70030115' and (select acc_dep_account from loans where id = :fl) = '20010215'
        and (select first_due_date from loans where id = :fl) = '2026-08-01' and (select interest_paise from loan_schedule where loan_id = :fl and n = 1) = 0,
            'Kitchen lease: asset ₹1,12,000 (fair value + direct costs), depreciated over the 12-month term into production depreciation; first payment at the start carries no charge');
select rb_start_loan(:fl);
select t_ok(t_bal('20010125') = 11200000 and t_bal('40020110') = -11000000, 'Lease starts: Dr Production Equipment ₹1,12,000, Cr lease liability ₹1,10,000 (and bank ₹2,000)');
select rb_pay_loan(jsonb_build_object('loan_id', :fl, 'pay_date', '2026-08-01', 'money_account_id', :bank)) as flp1 \gset
select t_err(format($$select rb_prepay_loan(jsonb_build_object('loan_id', %s, 'pay_date', '2026-08-02', 'money_account_id', 3, 'principal_paise', 100))$$, :fl), 'paid by its schedule');
select t_err(format($$select rb_end_finance_lease(jsonb_build_object('loan_id', %s, 'end_date', '2026-08-02', 'reason', 'x'))$$, :fl), 'still');

-- 11. Operating leases (AS 19, straight line)
select t_err(format($$select rb_save_op_lease(jsonb_build_object('name', 'x', 'lessor', 'y', 'category_id', %s, 'start_date', '2026-06-01', 'months', 24, 'rent_paise', 1, 'basis', 'as_paid'))$$, :srent),
             'give the reason');
select rb_save_op_lease(jsonb_build_object('name', 'Shop, Versova', 'lessor', 'Mrs D. Pinto', 'supplier_id', :landlord, 'category_id', :srent,
  'start_date', '2026-06-01', 'months', 24, 'lock_in_months', 12, 'rent_paise', 2000000, 'escalation_pct', 10, 'rent_free_months', 1,
  'deposit_paise', 6000000)) as ol \gset
select t_ok((select count(*) from op_lease_rents where lease_id = :ol) = 24 and (select rent_paise from op_lease_rents where lease_id = :ol and n = 1) = 0
        and (select rent_paise from op_lease_rents where lease_id = :ol and n = 12) = 2000000 and (select rent_paise from op_lease_rents where lease_id = :ol and n = 13) = 2200000,
            'Rent months: June rent-free, ₹20,000 to May, ₹22,000 from the 13th month');
select rb_start_op_lease(:ol);
select t_ok(not exists (select 1 from loan_entries where op_lease_id = :ol), 'A new operating lease posts nothing at the start (no asset, no liability)');
select rb_lease_deposit(jsonb_build_object('lease_id', :ol, 'kind', 'paid', 'entry_date', '2026-06-01', 'amount_paise', 6000000, 'money_account_id', :bank)) as dp \gset
select t_ok(t_bal('20050130') = 6000000, 'Deposit for a 24-month lease: Long-term Security Deposits');
select t_err(format($$select rb_lease_deposit(jsonb_build_object('lease_id', %s, 'kind', 'returned', 'entry_date', '2026-06-02', 'amount_paise', 9000000, 'money_account_id', 3))$$, :ol), 'Only ₹60,000.00');
select t_err(format($$select rb_record_lease_rent(jsonb_build_object('lease_id', %s, 'n', 1))$$, :ol), 'rent-free');
select rb_record_lease_rent(jsonb_build_object('lease_id', :ol, 'n', 2, 'expense_date', '2026-07-01', 'payment_mode', 'credit')) as rx \gset
select t_ok((select supplier_id from expenses where id = :rx) = (select id from suppliers where code = 'T-LL') and (select total_paise from expenses where id = :rx) = 2000000
        and (select category_id from expenses where id = :rx) = :srent, 'July rent entered as an expense on credit to the landlord, in Shop or office rent');
select t_err(format($$select rb_record_lease_rent(jsonb_build_object('lease_id', %s, 'n', 2))$$, :ol), 'already entered');

-- 12. The month-end step catches up September and October
select rb_loans_month_preview('2026-09-01') as m9 \gset
select t_ok(exists (select 1 from jsonb_array_elements(:'m9'::jsonb->'items') i where (i->>'op_lease_id')::bigint = :ol
          and (i->>'eq_required')::bigint = round(48400000 * 4 / 24.0) - 3 * 2000000),
            'September: straight-line rent for 4 lease months (₹4,84,000 ÷ 24 × 4) less the ₹60,000 payable');
select t_ok(exists (select 1 from jsonb_array_elements(:'m9'::jsonb->'items') i where (i->>'loan_id')::bigint = :fl
          and (i->>'dep_required')::bigint = round(11200000 * 2 / 12.0)), 'September: the packer is depreciated for August and September');
select rb_post_loans_month('2026-09-01') as r9 \gset
select t_ok(t_bal('70030115') = round(11200000 * 2 / 12.0) and t_eq(:ol) = round(48400000 * 4 / 24.0) - 6000000, 'Posted: depreciation and the rent equalisation');
-- Step 1 (labour and overheads) already posted for October: the kitchen depreciation would change it, so it is refused.
reset role;
insert into month_end_runs (run_no, kind, month, run_date, status, is_demo) values ('T-ABS', 'absorption', '2026-10-01', '2026-10-31', 'posted', false);
set role authenticated;
select t_err($$select rb_post_loans_month('2026-10-01')$$, 'Reverse step 1 first');
reset role;
delete from month_end_runs where run_no = 'T-ABS';
set role authenticated;
select rb_post_loans_month('2026-10-01') as r10 \gset
select t_ok(t_eq(:ol) = round(48400000 * 5 / 24.0) - 8000000, 'October: equalisation ₹20,833.33');
select t_ok(t_held(:l1) = t_acc_at(:l1, '2026-10-31') and t_held(:l2) = t_acc_at(:l2, '2026-10-31'), 'Interest accrued to 31-Oct is held for each loan');
select t_err($$select rb_post_loans_month('2026-08-01')$$, 'already posted');
select set_config('request.jwt.claim.sub', :'dir', false);
select t_err(format($$select rb_reverse_month_end(%s, 'x')$$, :r9), 'Reverse the latest month first');
select rb_reverse_month_end(:r10, 'Re-run with the bank statement');
select t_ok(not exists (select 1 from loan_entries where run_id = :r10 and status = 'posted') and t_eq(:ol) = round(48400000 * 4 / 24.0) - 6000000,
            'Reversing October''s run takes its entries out');
select rb_post_loans_month('2026-10-01') as r10 \gset
select t_ok(t_ll_agree(), 'Loans and leases agree with the books after the month-end runs');

-- 13. Summary and AS 19 disclosure at 31-Oct-2026
select rb_loans_summary('2026-10-31') as sm \gset
select t_ok((select bool_and((x->>'within_12_paise')::bigint <= (x->>'owed_paise')::bigint) from jsonb_array_elements(:'sm'::jsonb->'loans') x)
        and (select (x->>'within_12_paise')::bigint from jsonb_array_elements(:'sm'::jsonb->'loans') x where (x->>'id')::bigint = :l3) = 0
        and (select (x->>'within_12_paise')::bigint from jsonb_array_elements(:'sm'::jsonb->'loans') x where (x->>'id')::bigint = :fl) = t_owed(:fl),
            'Summary: due within 12 months never more than owed; the packer lease is all current');
select rb_lease_disclosure('2026-04-01', '2026-10-31') as ds \gset
select t_ok((select sum((b->>'principal_paise')::bigint) from jsonb_array_elements(:'ds'::jsonb->'schedules') b where b->>'kind' = 'finance_lease')
            = t_owed_at('finance_lease', '2026-10-31'),
            'Disclosure: present value of the finance lease payments = the lease liability');
select t_ok((select sum((b->>'payments_paise')::bigint) from jsonb_array_elements(:'ds'::jsonb->'operating_future') b) = 7 * 2000000,
            'Disclosure: 7 months of rent left in the 12-month lock-in (Nov to May) under non-cancellable operating leases');
select t_ok((:'ds'::jsonb->>'operating_charge_paise')::bigint = round(48400000 * 5 / 24.0), 'Operating lease rent charged to profit and loss: 5 months straight line');

-- 14. Ending leases
-- Operating lease ended early after 6 months: the rest of the months go; the equalisation is released at the next run.
select t_err(format($$select rb_end_op_lease(jsonb_build_object('lease_id', %s, 'end_date', '2026-06-15', 'reason', 'x'))$$, :ol), 'already entered');
select rb_end_op_lease(jsonb_build_object('lease_id', :ol, 'end_date', '2026-11-30', 'reason', 'Moved out'));
select t_ok((select count(*) from op_lease_rents where lease_id = :ol) = 6 and (select status from op_leases where id = :ol) = 'ended', 'Ended early: 6 months kept');
select t_ok(t_eq_at(:ol, '2026-11-30') = 0, 'At the end, nothing is left to spread');
-- Finance lease ended: pay off the rest (paid in advance each month), then return the packer.
select rb_pay_loan(jsonb_build_object('loan_id', :fl, 'pay_date', '2026-09-01', 'money_account_id', :bank));
reset role;
-- (The test skips ahead: the remaining 10 payments are entered at once.)
set role authenticated;
select rb_pay_loan(jsonb_build_object('loan_id', :fl, 'pay_date', ('2026-08-01'::date + make_interval(months => g))::date, 'money_account_id', :bank))
from generate_series(2, 11) g;
select t_ok((select status from loans where id = :fl) = 'closed' and t_owed(:fl) = 0, 'All 12 lease payments made: the lease liability is nil');
select rb_end_finance_lease(jsonb_build_object('loan_id', :fl, 'end_date', '2026-10-31', 'reason', 'Returned to the lessor')) as fle \gset
select t_ok((select status from loans where id = :fl) = 'ended' and t_bal('20010125') = 0 and t_bal('20010215') = 0,
            'Returned: the asset and its depreciation come out; what was left is written off');
select t_ok(t_ll_agree(), 'Everything still agrees after the leases ended');

-- 15. Take-on of an operating lease and cancelling one
select rb_save_op_lease(jsonb_build_object('name', 'Godown', 'lessor', 'Mr K', 'category_id', :krent, 'start_date', '2026-01-01', 'months', 36,
  'rent_paise', 500000, 'escalation_pct', 6, 'is_takeon', true, 'takeon_date', '2026-09-01', 'deposit_paise', 1500000)) as ol2 \gset
select rb_start_op_lease(:ol2);
select t_ok(t_eq(:ol2) = t_eq_at(:ol2, '2026-08-31') and t_eq(:ol2) > 0 and t_bal('20050130') = 6000000 + 1500000,
            'Take-on: the deposit and the rent equalisation so far come in as opening balances');
select t_err(format($$select rb_record_lease_rent(jsonb_build_object('lease_id', %s, 'n', 3))$$, :ol2), 'before the take-on date');
select rb_save_op_lease(jsonb_build_object('name', 'Mistake', 'lessor', 'Nobody', 'category_id', :krent, 'start_date', '2026-10-01', 'months', 11, 'rent_paise', 100000)) as ol3 \gset
select rb_start_op_lease(:ol3);
select rb_cancel_op_lease(:ol3, 'Entered twice');
select t_ok((select status from op_leases where id = :ol3) = 'cancelled', 'A lease started by mistake is cancelled');
select rb_save_loan(jsonb_build_object('kind', 'loan', 'name', 'Draft', 'lender', 'X', 'start_date', '2026-10-01', 'principal_paise', 100000,
  'instalments', 2, 'money_account_id', :bank)) as l4 \gset
select rb_delete_draft_loan(:l4);
select t_ok(not exists (select 1 from loans where id = :l4), 'A draft loan is deleted');

-- 16. Locked months
select set_config('request.jwt.claim.sub', :'dir', false);
select rb_lock_period('2026-08-01', true, 'August closed');
select t_err(format($$select rb_reverse_loan_entry(%s, '2026-08-20', 'x')$$, :dp), 'locked');
select rb_lock_period('2026-08-01', false, 'Testing');
select t_ok(exists (select 1 from audit_log where action = 'LOAN_STARTED') and exists (select 1 from audit_log where action = 'LOAN_PAYMENT')
        and exists (select 1 from audit_log where action = 'MONTH_END_LOANS') and exists (select 1 from audit_log where action = 'LOAN_RATE'),
            'Loans, payments, rate changes and month-end runs are in the audit log');

-- 17. Running the file again changes nothing
reset role;
select count(*) as n_loans, (select count(*) from loan_entries) as n_entries, (select count(*) from op_leases) as n_ol from loans \gset
\ir ../sql/07_loans_leases.sql
set client_min_messages = notice;
select t_ok((select count(*) from loans) = :n_loans and (select count(*) from loan_entries) = :n_entries and (select count(*) from op_leases) = :n_ol,
            'Running 07 again adds nothing and loses nothing');
select t_ok(t_ll_agree(), 'Still agrees after the re-run');

-- 18. Remove demo data, then go live
set role authenticated;
select set_config('request.jwt.claim.sub', :'dir', false);
select rb_remove_demo_data('REMOVE DEMO');
select t_ok(not exists (select 1 from loans where is_demo) and not exists (select 1 from op_leases where is_demo)
        and not exists (select 1 from loan_entries where is_demo) and not exists (select 1 from month_end_runs where is_demo), 'DEMO loans, leases and entries removed');
select t_ok(t_ll_agree(), 'Books still agree without the DEMO data');
select rb_go_live('2027-04-01', 'GO LIVE');
select t_ok(not exists (select 1 from loans) and not exists (select 1 from op_leases) and not exists (select 1 from loan_entries),
            'Go-live clears training loans and leases');
select set_config('request.jwt.claim.sub', :'acc', false);
select rb_save_loan(jsonb_build_object('kind', 'loan', 'name', 'Real loan', 'lender', 'SBI', 'start_date', '2027-04-02', 'principal_paise', 10000000,
  'annual_rate', 10, 'instalments', 12, 'money_account_id', :bank)) as l9 \gset
select t_ok((select loan_no from loans where id = :l9) = 'LN-001', 'After go-live, loans start at LN-001');

reset role;
\echo ALL MODULE 7 TESTS PASSED
