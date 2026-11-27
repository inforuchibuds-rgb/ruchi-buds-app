-- =====================================================================
-- RUCHI BUDS APP · Module 7: Loans and leases
-- File: 07_loans_leases.sql · Version 1.0 · 27-Nov-2026
--
-- What this file sets up:
--   Loans: lender, amount, start date, rate (fixed or floating), tenure,
--   the instalment (EMI) schedule, payments made, the balance still owed,
--   part-payments and closing early, rate changes, and the interest of
--   each month. A loan that was already running before the app started
--   is brought in with its balance on the take-on date.
--   Finance leases (AS 19): the lessor, the asset, the term, the
--   payments and the interest rate implicit in the lease. At the start
--   the asset and the lease liability are both recorded at the lower of
--   the asset's fair value and the present value of the minimum lease
--   payments; each payment is split into finance charge and repayment at
--   a constant rate on the balance owed; the asset is depreciated every
--   month.
--   Operating leases (AS 19): rented premises and equipment. The rent is
--   charged to profit and loss evenly (straight line) over the lease
--   term, so rent-free months and yearly increases are spread out; the
--   difference sits in a rent equalisation account. No asset or
--   liability is recorded for the lease itself. Security deposits paid
--   and returned are recorded, and each month's rent is entered as an
--   expense (module 6) straight from the lease.
--   One month-end step (LME) posts, for every loan and lease: interest
--   and finance charges accrued up to month-end, depreciation of leased
--   assets, and the straight-line rent adjustment. It is run before
--   module 6's step 1, because depreciation of kitchen assets and
--   kitchen rent are part of stock cost (AS 2).
--   A summary of everything owed, split into what falls due within 12
--   months and after (for the balance sheet), and the AS 19 disclosure
--   tables.
--
-- Accounting (Indian AS, ICAI): AS 19 Leases (lessee); AS 16 Borrowing
-- Costs (interest is charged as it accrues; loan processing fees are
-- charged when paid); AS 10 Property, Plant and Equipment (straight-line
-- depreciation of leased assets over the lease term, or the useful life
-- if ownership passes at the end); AS 2 (depreciation of kitchen
-- equipment is a production overhead); AS 29 is not used: nothing here
-- is a provision. AS 19 has no "short-term" or "low-value" exemptions:
-- every lease that is not a finance lease is an operating lease.
--
-- Run 01 to 06 first. Then: Supabase -> SQL Editor -> New query -> paste
-- this whole file -> Run. It is safe to run again; nothing you entered
-- is lost on a re-run. If 06 is ever run again, run this file again
-- straight after it.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Screen and rights
-- ---------------------------------------------------------------------

update screens set available = true where code = 'loans';

-- Managers do not see loans. The Accountant already has Loans and
-- leases: view, add, edit, approve and margin (module 1); Directors and
-- the FC always have everything. Running the month-end step needs the
-- Month-end steps power from module 6.

-- ---------------------------------------------------------------------
-- 2. Chart of accounts
-- ---------------------------------------------------------------------

-- Rent equalisation for operating leases (straight-line rent under AS 19).
update accounts set local_name = 'Rent Equalisation - Operating Leases (AS 19)'
where code = '40020120' and local_name is null;

-- ---------------------------------------------------------------------
-- 3. Tables
-- ---------------------------------------------------------------------

-- Loans and finance leases: both are money owed, repaid in instalments.
create table if not exists loans (
  id                   bigserial primary key,
  loan_no              text unique,
  kind                 text not null check (kind in ('loan', 'finance_lease')),
  name                 text not null,                 -- what it is for, e.g. "Kitchen equipment loan"
  lender               text not null,                 -- the lender or lessor
  lender_type          text not null default 'bank' check (lender_type in ('bank', 'nbfc', 'related', 'other')),
  account_code         text not null references accounts(code),   -- where the amount owed is kept
  interest_account     text not null references accounts(code),
  money_account_id     int references money_accounts(id),         -- money received into, and paid from
  department_id        int not null references departments(id),
  start_date           date not null,                 -- money received, or lease starts
  is_takeon            boolean not null default false,
  takeon_date          date,                          -- running before the app: balances as at this date
  takeon_accrued_paise bigint not null default 0,     -- interest owed but not yet due on the take-on date
  principal_paise      bigint not null check (principal_paise > 0),  -- amount borrowed, or owed on the take-on date
  annual_rate          numeric(9,4) not null default 0 check (annual_rate >= 0 and annual_rate < 100),
  rate_type            text not null default 'fixed' check (rate_type in ('fixed', 'floating')),
  method               text not null default 'emi' check (method in ('emi', 'equal_principal', 'bullet')),
  frequency_months     int not null default 1 check (frequency_months in (1, 3, 6, 12)),
  instalments          int not null check (instalments between 1 and 600),
  first_due_date       date not null,
  emi_paise            bigint check (emi_paise is null or emi_paise > 0),
  in_advance           boolean not null default false,
  fee_paise            bigint not null default 0 check (fee_paise >= 0),   -- processing fee, taken from the money received
  -- Finance leases only
  asset_name           text,
  asset_account        text references accounts(code),
  acc_dep_account      text references accounts(code),
  dep_account          text references accounts(code),
  fair_value_paise     bigint,
  residual_paise       bigint not null default 0,      -- guaranteed residual value (part of the minimum lease payments)
  pv_paise             bigint,                         -- present value of the minimum lease payments
  direct_costs_paise   bigint not null default 0,      -- initial direct costs, added to the asset
  asset_cost_paise     bigint,                         -- recorded cost of the asset
  takeon_acc_dep_paise bigint not null default 0,
  useful_life_months   int,
  ownership_transfers  boolean not null default false,
  dep_months           int,                            -- months to depreciate over (from the take-on date for a take-on)
  salvage_paise        bigint not null default 0,      -- value expected at the end of the depreciation period
  effective_rate       numeric(12,6),                  -- the rate used to split each payment
  -- Common
  status               text not null default 'draft' check (status in ('draft', 'active', 'closed', 'ended', 'cancelled')),
  note                 text,
  start_entry_id       bigint,
  closed_date          date,
  entered_by           uuid references app_users(id),
  entered_at           timestamptz not null default now(),
  approved_by          uuid references app_users(id),
  approved_at          timestamptz,
  updated_at           timestamptz,
  updated_by           uuid,
  is_demo              boolean not null default false,
  is_training          boolean not null default false,
  check (not is_takeon or takeon_date is not null),
  check (kind = 'loan' or (asset_name is not null and asset_account is not null and acc_dep_account is not null
                           and dep_account is not null and dep_months > 0))
);

-- The instalment schedule. Unpaid rows are rebuilt after a part-payment,
-- a rate change, or a payment that differs from the schedule.
create table if not exists loan_schedule (
  id               bigserial primary key,
  loan_id          bigint not null references loans(id) on delete cascade,
  n                int not null,
  due_date         date not null,
  opening_paise    bigint not null,
  interest_paise   bigint not null,
  principal_paise  bigint not null,
  payment_paise    bigint not null,
  closing_paise    bigint not null,
  paid_entry_id    bigint,
  is_demo          boolean not null default false,
  is_training      boolean not null default false,
  unique (loan_id, n)
);

-- Rate changes on floating-rate loans.
create table if not exists loan_rate_changes (
  id             bigserial primary key,
  loan_id        bigint not null references loans(id) on delete cascade,
  from_date      date not null,
  old_rate       numeric(9,4) not null,
  new_rate       numeric(9,4) not null,
  keep           text not null check (keep in ('emi', 'tenure')),
  old_emi_paise  bigint,
  new_emi_paise  bigint,
  reason         text,
  changed_by     uuid references app_users(id),
  changed_at     timestamptz not null default now(),
  is_demo        boolean not null default false,
  is_training    boolean not null default false
);

-- Operating leases: rented premises or equipment.
create table if not exists op_leases (
  id                     bigserial primary key,
  lease_no               text unique,
  name                   text not null,                -- e.g. "Kitchen premises, Andheri"
  lessor                 text not null,
  supplier_id            int references suppliers(id), -- the landlord, if rent is ever on credit
  category_id            int not null references expense_categories(id),
  department_id          int not null references departments(id),
  start_date             date not null,
  months                 int not null check (months between 1 and 600),
  lock_in_months         int not null default 0 check (lock_in_months >= 0),  -- cannot be cancelled for this long
  rent_paise             bigint not null check (rent_paise >= 0),             -- monthly rent in the first year
  escalation_pct         numeric(6,3) not null default 0 check (escalation_pct >= 0 and escalation_pct < 100),
  escalation_every       int not null default 12 check (escalation_every between 1 and 120),
  rent_free_months       int not null default 0 check (rent_free_months >= 0),
  basis                  text not null default 'straight_line' check (basis in ('straight_line', 'as_paid')),
  basis_reason           text,
  deposit_paise          bigint not null default 0 check (deposit_paise >= 0),
  is_takeon              boolean not null default false,
  takeon_date            date,
  ended_date             date,
  end_reason             text,
  status                 text not null default 'draft' check (status in ('draft', 'active', 'ended', 'cancelled')),
  note                   text,
  entered_by             uuid references app_users(id),
  entered_at             timestamptz not null default now(),
  approved_by            uuid references app_users(id),
  approved_at            timestamptz,
  updated_at             timestamptz,
  updated_by             uuid,
  is_demo                boolean not null default false,
  is_training            boolean not null default false,
  check (not is_takeon or takeon_date is not null),
  check (basis = 'straight_line' or basis_reason is not null)
);

-- The rent of each lease month, and the expense that recorded it.
create table if not exists op_lease_rents (
  id            bigserial primary key,
  lease_id      bigint not null references op_leases(id) on delete cascade,
  n             int not null,
  period_start  date not null,
  rent_paise    bigint not null check (rent_paise >= 0),
  expense_id    bigint references expenses(id) on delete set null,
  is_demo       boolean not null default false,
  is_training   boolean not null default false,
  unique (lease_id, n)
);

-- Every entry for a loan or lease. The balances (owed, interest accrued,
-- depreciation, rent equalisation, deposit) are the sums of the posted
-- entries, so a reversal always puts them back.
create table if not exists loan_entries (
  id                  bigserial primary key,
  entry_no            text unique,
  loan_id             bigint references loans(id) on delete cascade,
  op_lease_id         bigint references op_leases(id) on delete cascade,
  kind                text not null check (kind in ('start', 'takeon', 'payment', 'prepayment', 'month_end', 'deposit_paid',
                                                    'deposit_returned', 'lease_end')),
  entry_date          date not null,
  schedule_n          int,
  principal_paise     bigint not null default 0,   -- + more owed, - repaid
  accrued_paise       bigint not null default 0,   -- + interest accrued, - accrued interest paid
  interest_paise      bigint not null default 0,   -- charged to profit and loss
  charges_paise       bigint not null default 0,   -- fees and penal charges
  asset_paise         bigint not null default 0,   -- + leased asset recorded, - removed
  depreciation_paise  bigint not null default 0,   -- + depreciation, - removed at the end
  equalisation_paise  bigint not null default 0,   -- + rent equalisation owed
  deposit_paise       bigint not null default 0,   -- + deposit paid, - returned
  cash_paise          bigint not null default 0,   -- + money in, - money out
  money_account_id    int references money_accounts(id),
  run_id              bigint references month_end_runs(id) on delete cascade,
  reference           text,
  note                text,
  status              text not null default 'posted' check (status in ('posted', 'reversed')),
  journal_id          bigint references journals(id) on delete set null,
  reversal_journal_id bigint references journals(id) on delete set null,
  reverse_reason      text,
  entered_by          uuid references app_users(id),
  entered_at          timestamptz not null default now(),
  is_demo             boolean not null default false,
  is_training         boolean not null default false,
  check ((loan_id is null) <> (op_lease_id is null))
);
create index if not exists loan_entries_loan_idx on loan_entries (loan_id, entry_date) where loan_id is not null;
create index if not exists loan_entries_ol_idx on loan_entries (op_lease_id, entry_date) where op_lease_id is not null;
create index if not exists loan_entries_run_idx on loan_entries (run_id) where run_id is not null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'loans_start_entry_fk') then
    alter table loans add constraint loans_start_entry_fk foreign key (start_entry_id) references loan_entries(id) on delete set null;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'loan_schedule_paid_fk') then
    alter table loan_schedule add constraint loan_schedule_paid_fk foreign key (paid_entry_id) references loan_entries(id) on delete set null;
  end if;
end $$;

-- Month-end runs: a third kind, for loans and leases.
alter table month_end_runs drop constraint if exists month_end_runs_kind_check;
alter table month_end_runs add constraint month_end_runs_kind_check check (kind in ('absorption', 'doubtful_debts', 'loans_leases'));

-- ---------------------------------------------------------------------
-- 4. Posting rules (module 2 listed the first ones)
-- ---------------------------------------------------------------------

insert into posting_rules (event_code, line_key, side, account_code, module, label, sort) values
  ('loan',          'interest_payable',    'credit', '30060130', 7, 'Interest accrued on loans and finance leases, not yet paid', 142),
  ('loan',          'fee',                 'debit',  '91010115', 7, 'Loan processing fee (AS 16: charged when paid)', 143),
  ('loan',          'charges',             'debit',  '91010130', 7, 'Late-payment, penal and part-payment charges', 144),
  ('loan',          'opening',             'debit',  '97010105', 7, 'Loans and leases brought in at the take-on date', 145),
  ('finance_lease', 'depreciation_kitchen','debit',  '70030115', 7, 'Depreciation on a leased kitchen asset (production overhead, AS 2)', 155),
  ('op_lease',      'equalisation',        'credit', '40020120', 7, 'Rent equalisation: straight-line rent above the rent payable (AS 19)', 156),
  ('op_lease',      'deposit_long',        'debit',  '20050130', 7, 'Security deposit for a lease longer than 12 months', 157),
  ('op_lease',      'deposit_short',       'debit',  '10020335', 7, 'Security deposit for a lease of 12 months or less', 158)
on conflict (event_code, line_key) do nothing;
update posting_rules set label = 'Finance lease liability, current (the balance sheet shows the part due within 12 months here; the books keep it in the non-current account)'
where event_code = 'finance_lease' and line_key = 'liability_current';
update posting_rules set label = 'Finance lease liability (AS 19)'
where event_code = 'finance_lease' and line_key = 'liability_noncurrent';
update posting_rules set label = 'Loan interest (AS 16)' where event_code = 'loan' and line_key = 'interest';
update posting_rules set label = 'Bank loan (each loan can choose its own account)' where event_code = 'loan' and line_key = 'principal';

-- ---------------------------------------------------------------------
-- 5. Helpers (private: used by the functions below)
-- ---------------------------------------------------------------------

-- The rate for one payment period, from a yearly % and months between payments.
create or replace function rb_ll_r(p_rate numeric, p_freq int)
returns numeric language sql immutable as $$ select coalesce(p_rate, 0) / 100.0 * p_freq / 12.0 $$;

-- Present value of p_n payments (in advance: the first one at the start)
-- plus a residual value at the end of the term.
create or replace function rb_ll_pv(p_pmt numeric, p_r numeric, p_n int, p_adv boolean, p_res numeric)
returns numeric language plpgsql immutable as $$
declare v numeric; a numeric;
begin
  if p_r = 0 then return p_pmt * p_n + coalesce(p_res, 0); end if;
  v := 1 / (1 + p_r);
  a := (1 - power(v, p_n)) / p_r;
  if p_adv then a := a * (1 + p_r); end if;
  return p_pmt * a + coalesce(p_res, 0) * power(v, p_n);
end $$;

-- The yearly rate at which the payments are worth p_target today (the
-- rate implicit in a lease). Null when the payments add up to less.
create or replace function rb_ll_solve_rate(p_target numeric, p_pmt numeric, p_n int, p_freq int, p_adv boolean, p_res numeric)
returns numeric language plpgsql immutable as $$
declare lo numeric := 0; hi numeric := 99; mid numeric;
begin
  if rb_ll_pv(p_pmt, 0, p_n, p_adv, p_res) < p_target then return null; end if;
  if rb_ll_pv(p_pmt, rb_ll_r(hi, p_freq), p_n, p_adv, p_res) > p_target then return null; end if;
  for i in 1..60 loop
    mid := (lo + hi) / 2;
    if rb_ll_pv(p_pmt, rb_ll_r(mid, p_freq), p_n, p_adv, p_res) > p_target then lo := mid; else hi := mid; end if;
  end loop;
  return round((lo + hi) / 2, 6);
end $$;

-- Instalment rows from a balance. Row n falls due p_freq months after row
-- n-1, counted from p_anchor (the due date of row 1). A row due on or
-- before p_start carries no interest (a lease paid in advance).
--   emi:             equal payments (p_pmt, or worked out when null;
--                    rounded to the rupee when p_rupee). With p_count
--                    null, rows run on at p_pmt until the balance is paid.
--   equal_principal: the same repayment each time, plus interest.
--   bullet:          interest only, the whole balance with the last row.
-- The last row always clears the balance (and any residual value).
create or replace function rb_ll_rows(p_open bigint, p_rate numeric, p_freq int, p_first_n int, p_anchor date, p_start date,
                                      p_method text, p_pmt bigint, p_count int, p_res bigint, p_rupee boolean)
returns table (n int, due_date date, opening_paise bigint, interest_paise bigint, principal_paise bigint, payment_paise bigint, closing_paise bigint)
language plpgsql stable security definer set search_path = public as $$
declare r numeric := rb_ll_r(p_rate, p_freq); bal bigint := p_open; k int := 0; v_pmt numeric := p_pmt; v_int bigint; v_pr bigint;
        v_last boolean; v_res bigint := coalesce(p_res, 0); v_eq bigint; v_adv boolean; v_due date; v numeric;
begin
  if p_open <= 0 then return; end if;
  if p_count is null and (p_method <> 'emi' or p_pmt is null) then raise exception 'Internal: the number of instalments is needed.'; end if;
  if p_count is not null and p_count < 1 then raise exception 'There must be at least one instalment.'; end if;
  v_adv := (p_anchor + make_interval(months => (p_first_n - 1) * p_freq))::date <= p_start;
  if p_method = 'emi' and v_pmt is null then
    if r = 0 then v_pmt := (p_open - v_res)::numeric / p_count;
    else
      v := 1 / (1 + r);
      v_pmt := (p_open - v_res * power(v, p_count)) / ((1 - power(v, p_count)) / r * case when v_adv then 1 + r else 1 end);
    end if;
    v_pmt := case when p_rupee then round(v_pmt / 100) * 100 else round(v_pmt) end;
    if v_pmt <= 0 then raise exception 'The instalment works out at nothing. Check the amount and the residual value.'; end if;
  end if;
  if p_method = 'equal_principal' then v_eq := greatest(round((p_open - v_res)::numeric / p_count), 1); end if;
  loop
    k := k + 1;
    if k > 600 then raise exception 'At this instalment the loan would take more than 600 instalments to repay. Check the amount and the rate.'; end if;
    n := p_first_n + k - 1;
    v_due := (p_anchor + make_interval(months => (n - 1) * p_freq))::date;
    due_date := v_due;
    opening_paise := bal;
    v_int := case when v_due <= p_start then 0 else round(bal * r)::bigint end;
    v_last := p_count is not null and k = p_count;
    if p_method = 'emi' then
      v_pr := round(v_pmt)::bigint - v_int;
      if v_pr <= 0 and not v_last then
        raise exception 'The instalment of % does not even cover the interest of %. Check the instalment and the rate.', rb_pur_fmt(round(v_pmt)::bigint), rb_pur_fmt(v_int);
      end if;
      if v_last or v_pr >= bal - v_res then v_pr := bal; v_last := true; end if;
    elsif p_method = 'equal_principal' then
      v_pr := least(v_eq, bal);
      if v_last or v_pr >= bal - v_res then v_pr := bal; v_last := true; end if;
    else
      v_pr := case when v_last then bal else 0 end;
    end if;
    interest_paise := v_int; principal_paise := v_pr; payment_paise := v_int + v_pr; closing_paise := bal - v_pr;
    return next;
    bal := bal - v_pr;
    exit when v_last or bal <= 0;
  end loop;
end $$;

-- Balances of one loan, lease or operating lease from its posted entries
-- (up to a date, or all when p_as_of is null).
create or replace function rb_ll_bal(p_loan bigint, p_ol bigint, p_as_of date)
returns table (owed bigint, accrued bigint, asset bigint, depreciation bigint, equalisation bigint, deposit bigint)
language sql stable security definer set search_path = public as $$
  select coalesce(sum(principal_paise), 0)::bigint, coalesce(sum(accrued_paise), 0)::bigint, coalesce(sum(asset_paise), 0)::bigint,
         coalesce(sum(depreciation_paise), 0)::bigint, coalesce(sum(equalisation_paise), 0)::bigint, coalesce(sum(deposit_paise), 0)::bigint
  from loan_entries
  where status = 'posted' and (loan_id = p_loan or op_lease_id = p_ol) and (p_as_of is null or entry_date <= p_as_of)
$$;

-- One journal line with a signed amount (+ debit, - credit); none for zero.
create or replace function rb_ll_ln(p_acc text, p_amt bigint, p_narr text, p_dept int default null, p_extra jsonb default '{}')
returns jsonb language sql immutable as $$
  select case when coalesce(p_amt, 0) = 0 then '[]'::jsonb else jsonb_build_array(
    jsonb_build_object('account_code', p_acc, case when p_amt > 0 then 'debit_paise' else 'credit_paise' end, abs(p_amt),
                       'narration', p_narr) || case when p_dept is null then '{}'::jsonb else jsonb_build_object('department_id', p_dept) end
    || coalesce(p_extra, '{}')) end
$$;

-- The account a posting rule points to (the Accountant can change it in Accounts).
create or replace function rb_ll_acc(p_event text, p_key text)
returns text language sql stable security definer set search_path = public as $$
  select account_code from posting_rules where event_code = p_event and line_key = p_key
$$;

-- The accumulated depreciation account that goes with a fixed asset account.
create or replace function rb_ll_acc_dep_for(p_asset text)
returns text language sql immutable as $$
  select case p_asset when '20010110' then '20010205' when '20010120' then '20010210' when '20010115' then '20010220'
                      when '20010145' then '20010225' when '20010140' then '20010230'
                      when '20010125' then '20010215' when '20010130' then '20010215' when '20010135' then '20010215'
                      else '20010230' end
$$;

-- Where a loan is kept, unless the person chooses: bank loans for more
-- than 12 months -> Long-term Bank Loans; from a partner or other related
-- party -> Related-party Loans; others -> Other Long-term Borrowings;
-- 12 months or less -> short-term borrowings.
create or replace function rb_ll_default_account(p_type text, p_months int)
returns text language sql immutable as $$
  select case when p_months <= 12 then case when p_type = 'bank' then '30060110' else '30060135' end
              when p_type = 'bank' then '40010105' when p_type = 'related' then '40010120' else '40010110' end
$$;

-- Post one entry for a loan or lease, with its journal.
-- p: event, schedule_n, principal, accrued, interest, charges, asset, depreciation, equalisation, deposit, cash,
--    money_account_id, run_id, reference, note, source ('loans' or 'opening'), journal_id (when one is shared)
create or replace function rb_ll_entry(p_loan bigint, p_ol bigint, p_kind text, p_date date, p jsonb, p_lines jsonb,
                                       p_narr text, p_dept int, p_actor uuid, p_demo boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_no text; v_j bigint := rb_int(p, 'journal_id');
begin
  perform rb_assert_period_open(p_date);
  v_no := rb_cb_no('LNE', p_demo, p_date);
  insert into loan_entries (entry_no, loan_id, op_lease_id, kind, entry_date, schedule_n, principal_paise, accrued_paise, interest_paise,
                            charges_paise, asset_paise, depreciation_paise, equalisation_paise, deposit_paise, cash_paise, money_account_id,
                            run_id, reference, note, entered_by, is_demo, is_training)
  values (v_no, p_loan, p_ol, p_kind, p_date, rb_int(p, 'schedule_n')::int, coalesce(rb_int(p, 'principal'), 0), coalesce(rb_int(p, 'accrued'), 0),
          coalesce(rb_int(p, 'interest'), 0), coalesce(rb_int(p, 'charges'), 0), coalesce(rb_int(p, 'asset'), 0),
          coalesce(rb_int(p, 'depreciation'), 0), coalesce(rb_int(p, 'equalisation'), 0), coalesce(rb_int(p, 'deposit'), 0),
          coalesce(rb_int(p, 'cash'), 0), rb_int(p, 'money_account_id')::int, rb_int(p, 'run_id'), rb_txt(p, 'reference'), rb_txt(p, 'note'),
          p_actor, p_demo, rb_is_training())
  returning id into v_id;
  if v_j is null and jsonb_array_length(coalesce(p_lines, '[]')) > 0 then
    v_j := rb_post_engine(jsonb_build_object('journal_date', p_date, 'source', coalesce(rb_txt(p, 'source'), 'loans'),
      'event_code', coalesce(rb_txt(p, 'event'), p_kind), 'source_ref', v_no, 'narration', p_narr, 'department_id', p_dept,
      'is_demo', p_demo, 'entered_by', p_actor, 'approved_by', p_actor), p_lines);
  end if;
  update loan_entries set journal_id = v_j where id = v_id;
  return v_id;
end $$;

-- Rebuild the unpaid rows of a schedule from the amount still owed.
-- p_keep: 'emi' keeps the instalment (the number of instalments changes),
-- 'tenure' keeps the end date (the instalment changes). p_open: the
-- balance to start from (a draft, before anything is posted).
create or replace function rb_ll_rebuild(p_loan bigint, p_keep text, p_open bigint default null)
returns void language plpgsql security definer set search_path = public as $$
declare v loans; v_maxn int; v_open bigint; v_pmt bigint; v_cnt int; v_start date; v_first bigint; v_rows int;
begin
  select * into v from loans where id = p_loan for update;
  delete from loan_schedule where loan_id = p_loan and paid_entry_id is null;
  select coalesce(max(n), 0) into v_maxn from loan_schedule where loan_id = p_loan;
  v_open := coalesce(p_open, (select owed from rb_ll_bal(p_loan, null, null)));
  if v_open <= 0 then return; end if;
  v_cnt := greatest(v.instalments - v_maxn, 1);
  if v.kind = 'finance_lease' then v_pmt := v.emi_paise;
  elsif v.method = 'emi' and p_keep = 'emi' and v.emi_paise is not null then v_pmt := v.emi_paise; v_cnt := null;
  else v_pmt := null; end if;
  v_start := case when v.is_takeon then v.takeon_date - 1 else v.start_date end;
  insert into loan_schedule (loan_id, n, due_date, opening_paise, interest_paise, principal_paise, payment_paise, closing_paise, is_demo, is_training)
  select p_loan, x.n, x.due_date, x.opening_paise, x.interest_paise, x.principal_paise, x.payment_paise, x.closing_paise, v.is_demo, v.is_training
  from rb_ll_rows(v_open, coalesce(v.effective_rate, v.annual_rate), v.frequency_months, v_maxn + 1, v.first_due_date, v_start,
                  case when v.kind = 'finance_lease' then 'emi' else v.method end, v_pmt, v_cnt,
                  case when v.kind = 'finance_lease' then v.residual_paise else 0 end, v.kind = 'loan') x;
  select count(*), (array_agg(payment_paise order by n))[1] into v_rows, v_first
  from loan_schedule where loan_id = p_loan and paid_entry_id is null;
  update loans set instalments = v_maxn + v_rows,
    emi_paise = case when kind = 'loan' and method = 'emi' and (p_keep = 'tenure' or emi_paise is null) and v_rows > 1 then v_first else emi_paise end
  where id = p_loan;
end $$;

-- When the next payment period started (for interest accrued up to a date).
create or replace function rb_ll_period_start(v loans, p_n int, p_due date)
returns date language sql immutable as $$
  select case when p_n = 1 and not v.is_takeon then v.start_date
              else (p_due - make_interval(months => v.frequency_months))::date end
$$;

-- Interest (or finance charge) accrued and not yet paid at the end of a
-- day: all of it for instalments already due and unpaid, and the part of
-- the next instalment's interest for the days that have passed.
create or replace function rb_ll_accrual_at(p_loan bigint, p_end date)
returns bigint language plpgsql stable security definer set search_path = public as $$
declare v loans; s record; v_tot numeric := 0; v_ps date;
begin
  select * into v from loans where id = p_loan;
  for s in select ls.n, ls.due_date, ls.interest_paise from loan_schedule ls left join loan_entries e on e.id = ls.paid_entry_id
           where ls.loan_id = p_loan and (ls.paid_entry_id is null or e.status <> 'posted' or e.entry_date > p_end)
           order by ls.n loop
    if s.due_date <= p_end then
      v_tot := v_tot + s.interest_paise;
    else
      v_ps := rb_ll_period_start(v, s.n, s.due_date);
      if p_end >= v_ps and s.due_date > v_ps then
        v_tot := v_tot + s.interest_paise * least(1.0, (p_end + 1 - v_ps)::numeric / (s.due_date - v_ps));
      end if;
      exit;
    end if;
  end loop;
  return round(v_tot)::bigint;
end $$;

-- Depreciation of a leased asset up to the end of a day: straight line,
-- an equal amount for each month, and a part month by its days.
create or replace function rb_ll_dep_at(p_loan bigint, p_end date)
returns bigint language plpgsql stable security definer set search_path = public as $$
declare v loans; v_base date; v_open bigint; v_k int; v_a date; v_b date; v_used numeric;
begin
  select * into v from loans where id = p_loan;
  if v.kind <> 'finance_lease' then return 0; end if;
  v_base := case when v.is_takeon then v.takeon_date else v.start_date end;
  v_open := case when v.is_takeon then v.takeon_acc_dep_paise else 0 end;
  if p_end < v_base then return v_open; end if;
  v_k := (extract(year from age(p_end + 1, v_base)) * 12 + extract(month from age(p_end + 1, v_base)))::int;
  v_a := (v_base + make_interval(months => v_k))::date; v_b := (v_base + make_interval(months => v_k + 1))::date;
  v_used := least(v.dep_months, v_k + (p_end + 1 - v_a)::numeric / (v_b - v_a));
  return v_open + round((v.asset_cost_paise - v.salvage_paise - v_open) * v_used / v.dep_months)::bigint;
end $$;

-- Rent equalisation needed at the end of a day: straight-line rent for
-- the lease months started so far, less the rent payable for them.
create or replace function rb_ll_eq_at(p_ol bigint, p_end date)
returns bigint language plpgsql stable security definer set search_path = public as $$
declare v op_leases; k int; v_cum bigint; v_n int; v_tot bigint;
begin
  select * into v from op_leases where id = p_ol;
  if v.basis = 'as_paid' then return 0; end if;
  select count(*), coalesce(sum(rent_paise), 0) into k, v_cum from op_lease_rents where lease_id = p_ol and period_start <= p_end;
  select count(*), coalesce(sum(rent_paise), 0) into v_n, v_tot from op_lease_rents where lease_id = p_ol;
  if v_n = 0 then return 0; end if;
  return round(v_tot::numeric * k / v_n)::bigint - v_cum;
end $$;

-- The deposit account for an operating lease.
create or replace function rb_ll_deposit_acc(p_months int)
returns text language sql stable security definer set search_path = public as $$
  select rb_ll_acc('op_lease', case when p_months > 12 then 'deposit_long' else 'deposit_short' end)
$$;

-- Build the rent of each month of an operating lease.
create or replace function rb_ll_ol_rents(p_ol bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v op_leases;
begin
  select * into v from op_leases where id = p_ol;
  delete from op_lease_rents where lease_id = p_ol;
  insert into op_lease_rents (lease_id, n, period_start, rent_paise, is_demo, is_training)
  select p_ol, g, (v.start_date + make_interval(months => g - 1))::date,
         case when g <= v.rent_free_months then 0
              else round(v.rent_paise * power(1 + v.escalation_pct / 100.0, floor((g - 1)::numeric / v.escalation_every)))::bigint end,
         v.is_demo, v.is_training
  from generate_series(1, v.months) g;
end $$;

-- ---------------------------------------------------------------------
-- 6. Loans and finance leases: set up, start, pay, part-pay, rate change
-- ---------------------------------------------------------------------

-- Check a loan or finance lease form and work out everything from it:
-- the schedule, the instalment, and for a finance lease the present value
-- of the payments, the liability, the asset's cost and the rate used.
-- Nothing is saved. p: kind ('loan' or 'finance_lease'), name, lender, lender_type, account_code,
-- money_account_id, department_id, start_date, is_takeon, takeon_date, takeon_accrued_paise, principal_paise,
-- annual_rate, rate_type, method, frequency_months, instalments, first_due_date, emi_paise (loan: the bank's
-- EMI if known; lease: the lease payment), in_advance, fee_paise, note; finance leases also asset_name,
-- asset_account, kitchen (true when used in the kitchen), fair_value_paise, residual_paise, direct_costs_paise,
-- useful_life_months, ownership_transfers, salvage_paise, asset_cost_paise and takeon_acc_dep_paise and
-- dep_months (take-on only).
create or replace function rb_ll_prepare(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_kind text := coalesce(rb_txt(p, 'kind'), 'loan'); v_lease boolean; v_takeon boolean := coalesce((p->>'is_takeon')::boolean, false);
  v_start date := (p->>'start_date')::date; v_tdate date := (p->>'takeon_date')::date; v_freq int := coalesce(rb_int(p, 'frequency_months')::int, 1);
  v_n int := rb_int(p, 'instalments')::int; v_rate numeric := coalesce(nullif(p->>'annual_rate', '')::numeric, 0);
  v_method text := coalesce(rb_txt(p, 'method'), 'emi'); v_adv boolean; v_first date := (p->>'first_due_date')::date;
  v_pmt bigint := rb_int(p, 'emi_paise'); v_fee bigint := coalesce(rb_int(p, 'fee_paise'), 0); v_p bigint := rb_int(p, 'principal_paise');
  v_type text := coalesce(rb_txt(p, 'lender_type'), 'bank'); v_acc text := rb_txt(p, 'account_code'); v_a accounts; v_m money_accounts;
  v_dept int := rb_int(p, 'department_id')::int; v_kitchen boolean := coalesce((p->>'kitchen')::boolean, false);
  v_fv bigint := rb_int(p, 'fair_value_paise'); v_res bigint := coalesce(rb_int(p, 'residual_paise'), 0);
  v_idc bigint := coalesce(rb_int(p, 'direct_costs_paise'), 0); v_life int := rb_int(p, 'useful_life_months')::int;
  v_own boolean := coalesce((p->>'ownership_transfers')::boolean, false); v_salv bigint := coalesce(rb_int(p, 'salvage_paise'), 0);
  v_cost bigint := rb_int(p, 'asset_cost_paise'); v_accdep bigint := coalesce(rb_int(p, 'takeon_acc_dep_paise'), 0);
  v_depm int := rb_int(p, 'dep_months')::int; v_asset text := rb_txt(p, 'asset_account'); v_eff numeric; v_pv numeric; v_rows jsonb;
  v_accr bigint := coalesce(rb_int(p, 'takeon_accrued_paise'), 0); v_term int; v_r0 date;
begin
  if v_kind not in ('loan', 'finance_lease') then raise exception 'Choose a loan or a finance lease.'; end if;
  v_lease := v_kind = 'finance_lease';
  if rb_txt(p, 'name') is null then raise exception 'Please say what it is for, for example "%".', case when v_lease then 'Delivery van lease' else 'Kitchen equipment loan' end; end if;
  if rb_txt(p, 'lender') is null then raise exception 'Please give the name of the %.', case when v_lease then 'lessor (the leasing company)' else 'lender' end; end if;
  if v_type not in ('bank', 'nbfc', 'related', 'other') then raise exception 'Choose who the lender is: bank, finance company, partner or related party, or other.'; end if;
  if v_start is null then raise exception 'Please choose the % date.', case when v_lease then 'lease start' else 'date the money was received' end; end if;
  if v_takeon then
    if v_tdate is null then raise exception 'Please give the take-on date: the date the balances below are at.'; end if;
    if v_tdate < v_start then raise exception 'The take-on date cannot be before the start date.'; end if;
  else v_tdate := null; v_accr := 0; end if;
  if v_freq not in (1, 3, 6, 12) then raise exception 'Payments can be monthly, quarterly, half-yearly or yearly.'; end if;
  if coalesce(v_n, 0) < 1 or v_n > 600 then raise exception 'Please enter the number of % (1 to 600).', case when v_takeon then 'instalments still to pay' else 'instalments' end; end if;
  if v_rate < 0 or v_rate >= 100 then raise exception 'The interest rate must be between 0%% and 99.99%% a year.'; end if;
  if v_accr < 0 then raise exception 'Interest accrued cannot be negative.'; end if;
  if v_lease then v_method := 'emi'; v_adv := coalesce((p->>'in_advance')::boolean, true); v_fee := 0;
  else v_adv := false; end if;
  if v_method not in ('emi', 'equal_principal', 'bullet') then raise exception 'Choose how it is repaid: equal instalments (EMI), equal principal, or all at the end.'; end if;
  if v_fee < 0 then raise exception 'The processing fee cannot be negative.'; end if;
  -- First instalment.
  if v_lease and v_adv and not v_takeon then v_first := v_start;
  elsif v_first is null and not v_takeon then v_first := (v_start + make_interval(months => v_freq))::date; end if;
  if v_first is null then raise exception 'Please give the date the next instalment falls due.'; end if;
  if v_takeon and v_first < v_tdate then raise exception 'The next instalment must fall due on or after the take-on date.'; end if;
  if not v_takeon and not (v_lease and v_adv) and v_first <= v_start then raise exception 'The first instalment must fall due after the start date.'; end if;
  v_term := v_n * v_freq;
  -- Department.
  v_dept := coalesce(v_dept, rb_cb_dept(case when v_lease and v_kitchen then 'CC001' else 'CC005' end));
  if not exists (select 1 from departments where id = v_dept and is_active) then raise exception 'That department is closed or merged. Choose an open one.'; end if;
  -- Money account (needed when money comes in or goes out at the start).
  if rb_int(p, 'money_account_id') is not null then
    select * into v_m from money_accounts where id = rb_int(p, 'money_account_id');
    if v_m.id is null then raise exception 'That cash or bank account was not found.'; end if;
    if not v_m.is_active then raise exception '% is switched off.', v_m.name; end if;
  end if;
  if not v_lease and not v_takeon and v_m.id is null then raise exception 'Choose the bank account the loan money came into.'; end if;
  if v_lease and v_idc > 0 and not v_takeon and v_m.id is null then raise exception 'Choose the account the initial direct costs were paid from.'; end if;
  if v_lease then
    if rb_txt(p, 'asset_name') is null then raise exception 'Please describe the leased asset, for example "Tata Ace delivery van".'; end if;
    select * into v_a from accounts where code = v_asset;
    if v_a.code is null or v_a.code not like '200101%' or v_a.level <> 'posting' or not v_a.e002_active then
      raise exception 'Choose what kind of asset it is (buildings, plant, equipment, computers, furniture or vehicles).';
    end if;
    if coalesce(v_life, 0) < 1 then raise exception 'Please give the useful life of the asset in months.'; end if;
    if v_res < 0 or v_salv < 0 or v_idc < 0 then raise exception 'Amounts cannot be negative.'; end if;
    if coalesce(v_pmt, 0) <= 0 then raise exception 'Please enter the lease payment.'; end if;
    v_acc := rb_ll_acc('finance_lease', 'liability_noncurrent');
    if v_takeon then
      if coalesce(v_p, 0) <= 0 then raise exception 'Please enter the lease liability still owed on the take-on date.'; end if;
      if coalesce(v_cost, 0) <= 0 then raise exception 'Please enter the cost at which the leased asset was first recorded.'; end if;
      if v_accdep < 0 or v_accdep >= v_cost then raise exception 'Depreciation to date must be less than the asset''s cost.'; end if;
      if coalesce(v_depm, 0) < 1 then raise exception 'Please give the number of months of depreciation still to go.'; end if;
      if v_salv >= v_cost - v_accdep then raise exception 'The value at the end must be less than the value today.'; end if;
      v_eff := v_rate; v_pv := null;
    else
      if coalesce(v_fv, 0) <= 0 then raise exception 'Please enter the fair value of the asset (its cash price) at the start of the lease.'; end if;
      if v_rate > 0 then
        v_pv := rb_ll_pv(v_pmt, rb_ll_r(v_rate, v_freq), v_n, v_adv, v_res);
        if v_fv < v_pv then
          v_p := v_fv; v_eff := rb_ll_solve_rate(v_fv, v_pmt, v_n, v_freq, v_adv, v_res);
        else
          v_p := round(v_pv)::bigint; v_eff := v_rate;
        end if;
      else
        v_eff := rb_ll_solve_rate(v_fv, v_pmt, v_n, v_freq, v_adv, v_res);
        if v_eff is null then
          raise exception 'The payments add up to less than the fair value, so the rate implicit in the lease cannot be worked out. Enter the interest rate (the rate the firm would pay to borrow).';
        end if;
        v_pv := v_fv; v_p := v_fv;
      end if;
      v_cost := v_p + v_idc;
      v_depm := case when v_own then v_life else least(v_term, v_life) end;
      if v_salv >= v_cost then raise exception 'The value at the end must be less than the asset''s cost.'; end if;
      v_accdep := 0;
    end if;
  else
    if coalesce(v_p, 0) <= 0 then raise exception 'Please enter the %.', case when v_takeon then 'amount still owed on the take-on date' else 'amount borrowed' end; end if;
    if v_fee >= v_p then raise exception 'The processing fee cannot be as much as the loan.'; end if;
    if v_takeon then v_fee := 0; end if;
    v_acc := coalesce(v_acc, rb_ll_default_account(v_type, v_term));
    select * into v_a from accounts where code = v_acc;
    if v_a.code is null or v_a.level <> 'posting' or not v_a.e002_active or v_a.class <> 'Liability'
       or not (v_a.code like '4001%' or v_a.code in ('30060110', '30060115', '30060135')) or v_a.code = '40010125' then
      raise exception 'Choose a borrowings account (long-term bank loans, other borrowings, related-party loans or short-term borrowings).';
    end if;
    v_eff := v_rate; v_asset := null;
  end if;
  v_r0 := case when v_takeon then v_tdate - 1 else v_start end;
  select jsonb_agg(to_jsonb(x) order by x.n) into v_rows
  from rb_ll_rows(v_p, v_eff, v_freq, 1, v_first, v_r0, v_method, case when v_lease or v_method = 'emi' then v_pmt end,
                  v_n, case when v_lease then v_res else 0 end, not v_lease) x;
  if v_pmt is null and v_method = 'emi' and jsonb_array_length(v_rows) > 1 then v_pmt := (v_rows->0->>'payment_paise')::bigint; end if;
  return jsonb_build_object(
    'kind', v_kind, 'name', rb_txt(p, 'name'), 'lender', rb_txt(p, 'lender'), 'lender_type', v_type, 'account_code', v_acc,
    'account_name', coalesce(v_a.local_name, (select coalesce(local_name, name) from accounts where code = v_acc)),
    'interest_account', case when v_lease then rb_ll_acc('finance_lease', 'finance_charge') else rb_ll_acc('loan', 'interest') end,
    'money_account_id', v_m.id, 'department_id', v_dept, 'start_date', v_start, 'is_takeon', v_takeon, 'takeon_date', v_tdate,
    'takeon_accrued_paise', v_accr, 'principal_paise', v_p, 'annual_rate', v_rate, 'rate_type', coalesce(rb_txt(p, 'rate_type'), 'fixed'),
    'method', v_method, 'frequency_months', v_freq, 'instalments', jsonb_array_length(v_rows), 'first_due_date', v_first,
    'emi_paise', v_pmt, 'in_advance', v_adv, 'fee_paise', v_fee, 'note', rb_txt(p, 'note'),
    'asset_name', case when v_lease then rb_txt(p, 'asset_name') end, 'asset_account', v_asset,
    'acc_dep_account', case when v_lease then rb_ll_acc_dep_for(v_asset) end,
    'dep_account', case when v_lease then rb_ll_acc('finance_lease', case when v_kitchen then 'depreciation_kitchen' else 'depreciation' end) end,
    'kitchen', v_kitchen, 'fair_value_paise', v_fv, 'residual_paise', case when v_lease then v_res else 0 end,
    'pv_paise', round(v_pv)::bigint, 'direct_costs_paise', case when v_lease then v_idc else 0 end,
    'asset_cost_paise', case when v_lease then v_cost end, 'takeon_acc_dep_paise', case when v_lease then v_accdep else 0 end,
    'useful_life_months', v_life, 'ownership_transfers', v_own, 'dep_months', case when v_lease then v_depm end,
    'salvage_paise', case when v_lease then v_salv else 0 end, 'effective_rate', v_eff, 'term_months', v_term,
    'pv_pct_of_fv', case when v_lease and v_fv > 0 and v_pv is not null then round(v_pv * 100 / v_fv, 1) end,
    'term_pct_of_life', case when v_lease and v_life > 0 then round(v_term * 100.0 / v_life, 1) end,
    'total_payments_paise', (select sum((r->>'payment_paise')::bigint) from jsonb_array_elements(v_rows) r),
    'total_interest_paise', (select sum((r->>'interest_paise')::bigint) from jsonb_array_elements(v_rows) r),
    'rows', v_rows);
end $$;

-- Save a new loan or finance lease (or change one not yet started). It is
-- a draft until someone with Loans and leases -> Approve starts it.
create or replace function rb_ll_save_loan(p jsonb, p_actor uuid, p_demo boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint := rb_int(p, 'id'); v_old loans; x jsonb; v_pre text;
begin
  if v_id is not null then
    select * into v_old from loans where id = v_id for update;
    if v_old.id is null then raise exception 'Loan or lease not found.'; end if;
    if v_old.status <> 'draft' then raise exception 'Only a draft can be changed. Once started, use part-payment or rate change instead.'; end if;
    p_demo := v_old.is_demo;
  end if;
  x := rb_ll_prepare(p);
  if v_id is null then
    v_pre := case when p_demo then 'DEMO-' when rb_is_training() then 'TRN-' else '' end || case when x->>'kind' = 'loan' then 'LN-' else 'FL-' end;
    insert into loans (loan_no, kind, name, lender, lender_type, account_code, interest_account, money_account_id, department_id, start_date,
                       is_takeon, takeon_date, takeon_accrued_paise, principal_paise, annual_rate, rate_type, method, frequency_months,
                       instalments, first_due_date, emi_paise, in_advance, fee_paise, asset_name, asset_account, acc_dep_account, dep_account,
                       fair_value_paise, residual_paise, pv_paise, direct_costs_paise, asset_cost_paise, takeon_acc_dep_paise,
                       useful_life_months, ownership_transfers, dep_months, salvage_paise, effective_rate, note, entered_by, is_demo, is_training)
    values (rb_next_code(v_pre, v_pre, 3), x->>'kind', x->>'name', x->>'lender', x->>'lender_type', x->>'account_code', x->>'interest_account',
            (x->>'money_account_id')::int, (x->>'department_id')::int, (x->>'start_date')::date, (x->>'is_takeon')::boolean,
            (x->>'takeon_date')::date, (x->>'takeon_accrued_paise')::bigint, (x->>'principal_paise')::bigint, (x->>'annual_rate')::numeric,
            x->>'rate_type', x->>'method', (x->>'frequency_months')::int, (x->>'instalments')::int, (x->>'first_due_date')::date,
            (x->>'emi_paise')::bigint, (x->>'in_advance')::boolean, (x->>'fee_paise')::bigint, x->>'asset_name', x->>'asset_account',
            x->>'acc_dep_account', x->>'dep_account', (x->>'fair_value_paise')::bigint, (x->>'residual_paise')::bigint, (x->>'pv_paise')::bigint,
            (x->>'direct_costs_paise')::bigint, (x->>'asset_cost_paise')::bigint, (x->>'takeon_acc_dep_paise')::bigint,
            (x->>'useful_life_months')::int, (x->>'ownership_transfers')::boolean, (x->>'dep_months')::int, (x->>'salvage_paise')::bigint,
            (x->>'effective_rate')::numeric, x->>'note', p_actor, p_demo, rb_is_training())
    returning id into v_id;
  else
    if x->>'kind' <> v_old.kind then raise exception 'A loan cannot be changed into a lease (or back). Delete the draft and start again.'; end if;
    update loans set name = x->>'name', lender = x->>'lender', lender_type = x->>'lender_type', account_code = x->>'account_code',
      interest_account = x->>'interest_account', money_account_id = (x->>'money_account_id')::int, department_id = (x->>'department_id')::int,
      start_date = (x->>'start_date')::date, is_takeon = (x->>'is_takeon')::boolean, takeon_date = (x->>'takeon_date')::date,
      takeon_accrued_paise = (x->>'takeon_accrued_paise')::bigint, principal_paise = (x->>'principal_paise')::bigint,
      annual_rate = (x->>'annual_rate')::numeric, rate_type = x->>'rate_type', method = x->>'method', frequency_months = (x->>'frequency_months')::int,
      instalments = (x->>'instalments')::int, first_due_date = (x->>'first_due_date')::date, emi_paise = (x->>'emi_paise')::bigint,
      in_advance = (x->>'in_advance')::boolean, fee_paise = (x->>'fee_paise')::bigint, asset_name = x->>'asset_name',
      asset_account = x->>'asset_account', acc_dep_account = x->>'acc_dep_account', dep_account = x->>'dep_account',
      fair_value_paise = (x->>'fair_value_paise')::bigint, residual_paise = (x->>'residual_paise')::bigint, pv_paise = (x->>'pv_paise')::bigint,
      direct_costs_paise = (x->>'direct_costs_paise')::bigint, asset_cost_paise = (x->>'asset_cost_paise')::bigint,
      takeon_acc_dep_paise = (x->>'takeon_acc_dep_paise')::bigint, useful_life_months = (x->>'useful_life_months')::int,
      ownership_transfers = (x->>'ownership_transfers')::boolean, dep_months = (x->>'dep_months')::int,
      salvage_paise = (x->>'salvage_paise')::bigint, effective_rate = (x->>'effective_rate')::numeric, note = x->>'note',
      updated_at = now(), updated_by = p_actor
    where id = v_id;
  end if;
  delete from loan_schedule where loan_id = v_id;
  insert into loan_schedule (loan_id, n, due_date, opening_paise, interest_paise, principal_paise, payment_paise, closing_paise, is_demo, is_training)
  select v_id, (r->>'n')::int, (r->>'due_date')::date, (r->>'opening_paise')::bigint, (r->>'interest_paise')::bigint,
         (r->>'principal_paise')::bigint, (r->>'payment_paise')::bigint, (r->>'closing_paise')::bigint, p_demo, rb_is_training()
  from jsonb_array_elements(x->'rows') r;
  perform rb_audit_write(case when v_old.id is null then 'LOAN_SAVED' else 'LOAN_CHANGED' end, 'loans', v_id::text,
    case when v_old.id is not null then to_jsonb(v_old) end,
    jsonb_build_object('loan_no', (select loan_no from loans where id = v_id), 'kind', x->>'kind', 'principal_paise', x->'principal_paise'), null);
  return v_id;
end $$;

-- Start a loan or lease: post the money received (or the asset and the
-- liability), or bring in the balances of one that was already running.
create or replace function rb_ll_start(p_loan bigint, p_actor uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare v loans; v_m money_accounts; v_date date; v_lines jsonb := '[]'; v_e bigint; v_ip text := rb_ll_acc('loan', 'interest_payable');
        v_open text := rb_ll_acc('loan', 'opening'); v_bal bigint; v_narr text;
begin
  select * into v from loans where id = p_loan for update;
  if v.id is null then raise exception 'Loan or lease not found.'; end if;
  if v.status <> 'draft' then raise exception '% has already been started.', v.loan_no; end if;
  v_date := case when v.is_takeon then v.takeon_date else v.start_date end;
  if v.money_account_id is not null then select * into v_m from money_accounts where id = v.money_account_id; end if;
  if v.kind = 'loan' and not v.is_takeon then
    if v_m.id is null or not v_m.is_active then raise exception 'Choose an active bank account for the money received.'; end if;
    v_lines := rb_ll_ln(v_m.account_code, v.principal_paise - v.fee_paise, 'Loan money received from ' || v.lender)
            || rb_ll_ln(rb_ll_acc('loan', 'fee'), v.fee_paise, 'Processing fee, ' || v.loan_no)
            || rb_ll_ln(v.account_code, -v.principal_paise, v.name || ' (' || v.loan_no || ')');
    v_narr := 'Loan ' || v.loan_no || ' received from ' || v.lender || ': ' || v.name;
    v_e := rb_ll_entry(p_loan, null, 'start', v_date, jsonb_build_object('event', 'loan_start', 'principal', v.principal_paise,
      'charges', v.fee_paise, 'cash', v.principal_paise - v.fee_paise, 'money_account_id', v_m.id), v_lines, v_narr, v.department_id, p_actor, v.is_demo);
  elsif v.kind = 'loan' then
    v_lines := rb_ll_ln(v_open, v.principal_paise + v.takeon_accrued_paise, 'Brought in at ' || to_char(v_date, 'DD-Mon-YYYY'))
            || rb_ll_ln(v.account_code, -v.principal_paise, v.name || ' (' || v.loan_no || ')')
            || rb_ll_ln(v_ip, -v.takeon_accrued_paise, 'Interest accrued, ' || v.loan_no);
    v_narr := 'Opening balance: loan ' || v.loan_no || ' from ' || v.lender || ' (' || v.name || '), owed at ' || to_char(v_date, 'DD-Mon-YYYY');
    v_e := rb_ll_entry(p_loan, null, 'takeon', v_date, jsonb_build_object('event', 'opening', 'source', 'opening', 'principal', v.principal_paise,
      'accrued', v.takeon_accrued_paise), v_lines, v_narr, v.department_id, p_actor, v.is_demo);
  elsif not v.is_takeon then
    if v.direct_costs_paise > 0 and (v_m.id is null or not v_m.is_active) then raise exception 'Choose an active account for the initial direct costs.'; end if;
    v_lines := rb_ll_ln(v.asset_account, v.asset_cost_paise, v.asset_name || ' (finance lease ' || v.loan_no || ')')
            || rb_ll_ln(v.account_code, -v.principal_paise, 'Lease liability to ' || v.lender || ' (' || v.loan_no || ')')
            || case when v.direct_costs_paise > 0 then rb_ll_ln(v_m.account_code, -v.direct_costs_paise, 'Initial direct costs, ' || v.loan_no) else '[]' end;
    v_narr := 'Finance lease ' || v.loan_no || ' starts (AS 19): ' || v.asset_name || ' from ' || v.lender ||
              ', recorded at ' || rb_pur_fmt(v.principal_paise) || case when v.fair_value_paise = v.principal_paise then ' (fair value)' else ' (present value of the lease payments)' end;
    v_e := rb_ll_entry(p_loan, null, 'start', v_date, jsonb_build_object('event', 'lease_start', 'principal', v.principal_paise,
      'asset', v.asset_cost_paise, 'cash', -v.direct_costs_paise, 'money_account_id', case when v.direct_costs_paise > 0 then v_m.id end),
      v_lines, v_narr, v.department_id, p_actor, v.is_demo);
  else
    v_bal := v.asset_cost_paise - v.takeon_acc_dep_paise - v.principal_paise - v.takeon_accrued_paise;
    v_lines := rb_ll_ln(v.asset_account, v.asset_cost_paise, v.asset_name || ' (finance lease ' || v.loan_no || ')')
            || rb_ll_ln(v.acc_dep_account, -v.takeon_acc_dep_paise, 'Depreciation to ' || to_char(v_date, 'DD-Mon-YYYY') || ', ' || v.loan_no)
            || rb_ll_ln(v.account_code, -v.principal_paise, 'Lease liability to ' || v.lender || ' (' || v.loan_no || ')')
            || rb_ll_ln(v_ip, -v.takeon_accrued_paise, 'Finance charge accrued, ' || v.loan_no)
            || rb_ll_ln(v_open, -v_bal, 'Brought in at ' || to_char(v_date, 'DD-Mon-YYYY'));
    v_narr := 'Opening balance: finance lease ' || v.loan_no || ', ' || v.asset_name || ' from ' || v.lender || ', at ' || to_char(v_date, 'DD-Mon-YYYY');
    v_e := rb_ll_entry(p_loan, null, 'takeon', v_date, jsonb_build_object('event', 'opening', 'source', 'opening', 'principal', v.principal_paise,
      'accrued', v.takeon_accrued_paise, 'asset', v.asset_cost_paise, 'depreciation', v.takeon_acc_dep_paise), v_lines, v_narr, v.department_id, p_actor, v.is_demo);
  end if;
  update loans set status = 'active', start_entry_id = v_e, approved_by = p_actor, approved_at = now() where id = p_loan;
  perform rb_audit_write('LOAN_STARTED', 'loans', p_loan::text, null,
    jsonb_build_object('loan_no', v.loan_no, 'kind', v.kind, 'principal_paise', v.principal_paise, 'take_on', v.is_takeon), null);
  return v_e;
end $$;

-- Pay the next instalment. The interest accrued at earlier month-ends is
-- cleared first; the rest of the interest is charged now. A payment that
-- differs from the schedule rebuilds the rows still to come.
-- p: loan_id, pay_date, money_account_id, principal_paise, interest_paise (both default to the
--    schedule), charges_paise (late or penal charges), reference, note
create or replace function rb_ll_pay(p jsonb, p_actor uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare v loans; s loan_schedule; v_m money_accounts; v_date date := (p->>'pay_date')::date; v_pr bigint; v_int bigint;
        v_ch bigint := coalesce(rb_int(p, 'charges_paise'), 0); v_owed bigint; v_held bigint; v_use bigint; v_close boolean; v_e bigint;
        v_lines jsonb; v_ip text := rb_ll_acc('loan', 'interest_payable'); v_what text;
begin
  select * into v from loans where id = rb_int(p, 'loan_id') for update;
  if v.id is null then raise exception 'Loan or lease not found.'; end if;
  if v.status <> 'active' then raise exception '% is not running (%).', v.loan_no, v.status; end if;
  select * into s from loan_schedule where loan_id = v.id and paid_entry_id is null order by n limit 1;
  if s.id is null then raise exception 'Nothing is left to pay on %.', v.loan_no; end if;
  if v_date is null then raise exception 'Please choose the date paid.'; end if;
  if v_date < coalesce(v.takeon_date, v.start_date) then raise exception 'The payment date cannot be before the start.'; end if;
  select * into v_m from money_accounts where id = coalesce(rb_int(p, 'money_account_id')::int, v.money_account_id);
  if v_m.id is null then raise exception 'Choose the cash or bank account it was paid from.'; end if;
  if not v_m.is_active then raise exception '% is switched off.', v_m.name; end if;
  v_pr := coalesce(rb_int(p, 'principal_paise'), s.principal_paise);
  v_int := coalesce(rb_int(p, 'interest_paise'), s.interest_paise);
  if v_pr < 0 or v_int < 0 or v_ch < 0 then raise exception 'Amounts cannot be negative.'; end if;
  if v_pr + v_int + v_ch <= 0 then raise exception 'Please enter the amount paid.'; end if;
  select owed into v_owed from rb_ll_bal(v.id, null, null);
  if v_pr > v_owed then raise exception 'The repayment (%) is more than is owed (%).', rb_pur_fmt(v_pr), rb_pur_fmt(v_owed); end if;
  v_close := v_pr = v_owed;
  select accrued into v_held from rb_ll_bal(v.id, null, v_date);
  v_use := case when v_close then greatest(v_held, 0) else least(v_int, greatest(v_held, 0)) end;
  v_what := case when v.kind = 'loan' then 'EMI' else 'Lease payment' end || ' ' || s.n || ' of ' || v.instalments;
  v_lines := rb_ll_ln(v.account_code, v_pr, v_what || ', repayment (' || v.loan_no || ')')
          || rb_ll_ln(v_ip, v_use, 'Interest accrued at earlier month-ends, ' || v.loan_no)
          || rb_ll_ln(v.interest_account, v_int - v_use, case when v.kind = 'loan' then 'Interest, ' else 'Finance charge, ' end || v.loan_no)
          || rb_ll_ln(rb_ll_acc('loan', 'charges'), v_ch, 'Charges, ' || v.loan_no)
          || rb_ll_ln(v_m.account_code, -(v_pr + v_int + v_ch), v.lender);
  v_e := rb_ll_entry(v.id, null, 'payment', v_date, jsonb_build_object('event', case when v.kind = 'loan' then 'loan_payment' else 'lease_payment' end,
    'schedule_n', s.n, 'principal', -v_pr, 'accrued', -v_use, 'interest', v_int - v_use, 'charges', v_ch, 'cash', -(v_pr + v_int + v_ch),
    'money_account_id', v_m.id, 'reference', rb_txt(p, 'reference'), 'note', rb_txt(p, 'note')),
    v_lines, v_what || ' paid to ' || v.lender || ' (' || v.loan_no || ', ' || v.name || ')' || coalesce(', ' || rb_txt(p, 'reference'), ''),
    v.department_id, p_actor, v.is_demo);
  update loan_schedule set paid_entry_id = v_e where id = s.id;
  if v_close then
    delete from loan_schedule where loan_id = v.id and paid_entry_id is null;
    update loans set status = 'closed', closed_date = v_date where id = v.id;
  elsif v_pr <> s.principal_paise or v_int <> s.interest_paise then
    perform rb_ll_rebuild(v.id, 'emi');
  end if;
  perform rb_audit_write('LOAN_PAYMENT', 'loan_entries', v_e::text, null,
    jsonb_build_object('loan_no', v.loan_no, 'n', s.n, 'principal_paise', v_pr, 'interest_paise', v_int, 'charges_paise', v_ch), null);
  return v_e;
end $$;

-- Part-payment, or paying a loan off early. p: loan_id, pay_date, money_account_id, principal_paise
-- (or close = true for everything owed), interest_paise (interest to date charged by the lender),
-- charges_paise (part-payment or foreclosure charges), keep ('emi' or 'tenure'), reference, note
create or replace function rb_ll_prepay(p jsonb, p_actor uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare v loans; v_m money_accounts; v_date date := (p->>'pay_date')::date; v_pr bigint := rb_int(p, 'principal_paise');
        v_int bigint := coalesce(rb_int(p, 'interest_paise'), 0); v_ch bigint := coalesce(rb_int(p, 'charges_paise'), 0);
        v_keep text := coalesce(rb_txt(p, 'keep'), 'emi'); v_owed bigint; v_held bigint; v_use bigint; v_close boolean; v_e bigint;
        v_lines jsonb; v_ip text := rb_ll_acc('loan', 'interest_payable');
begin
  select * into v from loans where id = rb_int(p, 'loan_id') for update;
  if v.id is null then raise exception 'Loan not found.'; end if;
  if v.kind <> 'loan' then raise exception 'A finance lease is paid by its schedule. Ask the CA how to record ending a lease early.'; end if;
  if v.status <> 'active' then raise exception '% is not running (%).', v.loan_no, v.status; end if;
  if v_date is null then raise exception 'Please choose the date paid.'; end if;
  if v_date < coalesce(v.takeon_date, v.start_date) then raise exception 'The payment date cannot be before the start.'; end if;
  if v_keep not in ('emi', 'tenure') then raise exception 'Choose whether the EMI or the end date stays the same.'; end if;
  if v.method <> 'emi' then v_keep := 'tenure'; end if;
  select * into v_m from money_accounts where id = coalesce(rb_int(p, 'money_account_id')::int, v.money_account_id);
  if v_m.id is null or not v_m.is_active then raise exception 'Choose an active cash or bank account it was paid from.'; end if;
  select owed into v_owed from rb_ll_bal(v.id, null, null);
  if coalesce((p->>'close')::boolean, false) then v_pr := v_owed; end if;
  if coalesce(v_pr, 0) <= 0 then raise exception 'Please enter the amount of the loan being repaid.'; end if;
  if v_pr > v_owed then raise exception 'The repayment (%) is more than is owed (%).', rb_pur_fmt(v_pr), rb_pur_fmt(v_owed); end if;
  if v_int < 0 or v_ch < 0 then raise exception 'Amounts cannot be negative.'; end if;
  v_close := v_pr = v_owed;
  select accrued into v_held from rb_ll_bal(v.id, null, v_date);
  v_use := case when v_close then greatest(v_held, 0) else least(v_int, greatest(v_held, 0)) end;
  v_lines := rb_ll_ln(v.account_code, v_pr, case when v_close then 'Paid off early (' else 'Part-payment (' end || v.loan_no || ')')
          || rb_ll_ln(v_ip, v_use, 'Interest accrued at earlier month-ends, ' || v.loan_no)
          || rb_ll_ln(v.interest_account, v_int - v_use, 'Interest to date, ' || v.loan_no)
          || rb_ll_ln(rb_ll_acc('loan', 'charges'), v_ch, case when v_close then 'Foreclosure charges, ' else 'Part-payment charges, ' end || v.loan_no)
          || rb_ll_ln(v_m.account_code, -(v_pr + v_int + v_ch), v.lender);
  v_e := rb_ll_entry(v.id, null, 'prepayment', v_date, jsonb_build_object('event', 'loan_prepayment', 'principal', -v_pr, 'accrued', -v_use,
    'interest', v_int - v_use, 'charges', v_ch, 'cash', -(v_pr + v_int + v_ch), 'money_account_id', v_m.id,
    'reference', rb_txt(p, 'reference'), 'note', rb_txt(p, 'note')),
    v_lines, case when v_close then 'Loan ' || v.loan_no || ' paid off early to ' else 'Part-payment of loan ' || v.loan_no || ' to ' end || v.lender ||
      coalesce(', ' || rb_txt(p, 'reference'), ''), v.department_id, p_actor, v.is_demo);
  if v_close then
    delete from loan_schedule where loan_id = v.id and paid_entry_id is null;
    update loans set status = 'closed', closed_date = v_date where id = v.id;
  else
    perform rb_ll_rebuild(v.id, v_keep);
  end if;
  perform rb_audit_write('LOAN_PREPAYMENT', 'loan_entries', v_e::text, null,
    jsonb_build_object('loan_no', v.loan_no, 'principal_paise', v_pr, 'closed', v_close, 'keep', v_keep), null);
  return v_e;
end $$;

-- A new interest rate (floating-rate loans). The instalments still to
-- come are worked out again at the new rate. p: loan_id, from_date, new_rate, keep, reason
create or replace function rb_ll_rate(p jsonb, p_actor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v loans; v_rate numeric := nullif(p->>'new_rate', '')::numeric; v_keep text := coalesce(rb_txt(p, 'keep'), 'emi');
        v_from date := (p->>'from_date')::date; v_new bigint;
begin
  select * into v from loans where id = rb_int(p, 'loan_id') for update;
  if v.id is null then raise exception 'Loan not found.'; end if;
  if v.kind <> 'loan' then raise exception 'The rate of a finance lease is fixed by the lease.'; end if;
  if v.status <> 'active' then raise exception '% is not running (%).', v.loan_no, v.status; end if;
  if v_rate is null or v_rate < 0 or v_rate >= 100 then raise exception 'Please enter the new rate (%% a year).'; end if;
  if v_rate = v.annual_rate then raise exception 'That is the rate already in use.'; end if;
  if v_from is null then raise exception 'Please give the date the new rate applies from.'; end if;
  if rb_txt(p, 'reason') is null then raise exception 'Please give the reason, for example "Bank''s letter of 1-Dec: repo rate change".'; end if;
  if v_keep not in ('emi', 'tenure') then raise exception 'Choose whether the EMI or the end date stays the same.'; end if;
  if v.method <> 'emi' then v_keep := 'tenure'; end if;
  update loans set annual_rate = v_rate, effective_rate = v_rate, updated_at = now(), updated_by = p_actor where id = v.id;
  perform rb_ll_rebuild(v.id, v_keep);
  select emi_paise into v_new from loans where id = v.id;
  insert into loan_rate_changes (loan_id, from_date, old_rate, new_rate, keep, old_emi_paise, new_emi_paise, reason, changed_by, is_demo, is_training)
  values (v.id, v_from, v.annual_rate, v_rate, v_keep, v.emi_paise, v_new, rb_txt(p, 'reason'), p_actor, v.is_demo, rb_is_training());
  perform rb_audit_write('LOAN_RATE', 'loans', v.id::text, jsonb_build_object('annual_rate', v.annual_rate, 'emi_paise', v.emi_paise),
    jsonb_build_object('annual_rate', v_rate, 'emi_paise', v_new, 'keep', v_keep, 'from', v_from), rb_txt(p, 'reason'));
end $$;

-- End of a finance lease: the asset goes back to the lessor. Whatever is
-- left of its value is written off as depreciation.
create or replace function rb_ll_end_lease(p jsonb, p_actor uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare v loans; v_date date := (p->>'end_date')::date; b record; v_e bigint; v_left bigint;
begin
  select * into v from loans where id = rb_int(p, 'loan_id') for update;
  if v.id is null or v.kind <> 'finance_lease' then raise exception 'Finance lease not found.'; end if;
  if v.status not in ('active', 'closed') then raise exception '% has already ended.', v.loan_no; end if;
  if v_date is null then raise exception 'Please give the date the asset went back.'; end if;
  if rb_txt(p, 'reason') is null then raise exception 'Please add a short note, for example "Van returned to Sai Leasing".'; end if;
  select * into b from rb_ll_bal(v.id, null, null);
  if b.owed <> 0 or b.accrued <> 0 then
    raise exception 'There is still % owed on this lease. Pay the last instalments first.', rb_pur_fmt(b.owed + b.accrued);
  end if;
  if v.ownership_transfers then
    raise exception 'The asset becomes the firm''s own at the end of this lease, so it stays in the books and is depreciated over its useful life.';
  end if;
  v_left := b.asset - b.depreciation;
  v_e := rb_ll_entry(v.id, null, 'lease_end', v_date, jsonb_build_object('event', 'lease_end', 'asset', -b.asset, 'depreciation', -b.depreciation,
    'note', rb_txt(p, 'reason')),
    rb_ll_ln(v.acc_dep_account, b.depreciation, 'Depreciation on ' || v.asset_name)
    || rb_ll_ln(v.dep_account, v_left, 'Value left on ' || v.asset_name || ', written off')
    || rb_ll_ln(v.asset_account, -b.asset, v.asset_name || ' returned to ' || v.lender),
    'Finance lease ' || v.loan_no || ' ended: ' || v.asset_name || ' returned to ' || v.lender || ' (' || rb_txt(p, 'reason') || ')',
    v.department_id, p_actor, v.is_demo);
  update loans set status = 'ended', closed_date = v_date where id = v.id;
  perform rb_audit_write('LEASE_ENDED', 'loans', v.id::text, null, jsonb_build_object('loan_no', v.loan_no, 'date', v_date), rb_txt(p, 'reason'));
  return v_e;
end $$;

-- ---------------------------------------------------------------------
-- 7. Operating leases: set up, start, deposits, rent, ending early
-- ---------------------------------------------------------------------

-- Save a new operating lease (or change one not yet started).
-- p: id, name, lessor, supplier_id, category_id (Kitchen rent, Shop or office rent ...), department_id,
--    start_date, months, lock_in_months, rent_paise, escalation_pct, escalation_every, rent_free_months,
--    basis ('straight_line' or 'as_paid' with basis_reason), deposit_paise, is_takeon, takeon_date, note
create or replace function rb_ll_save_ol(p jsonb, p_actor uuid, p_demo boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint := rb_int(p, 'id'); v_old op_leases; v_c expense_categories; v_start date := (p->>'start_date')::date;
        v_months int := rb_int(p, 'months')::int; v_lock int := coalesce(rb_int(p, 'lock_in_months')::int, 0);
        v_rent bigint := rb_int(p, 'rent_paise'); v_esc numeric := coalesce(nullif(p->>'escalation_pct', '')::numeric, 0);
        v_every int := coalesce(rb_int(p, 'escalation_every')::int, 12); v_free int := coalesce(rb_int(p, 'rent_free_months')::int, 0);
        v_basis text := coalesce(rb_txt(p, 'basis'), 'straight_line'); v_dep bigint := coalesce(rb_int(p, 'deposit_paise'), 0);
        v_takeon boolean := coalesce((p->>'is_takeon')::boolean, false); v_tdate date := (p->>'takeon_date')::date;
        v_dept int; v_sup int := rb_int(p, 'supplier_id')::int; v_pre text;
begin
  if v_id is not null then
    select * into v_old from op_leases where id = v_id for update;
    if v_old.id is null then raise exception 'Lease not found.'; end if;
    if v_old.status <> 'draft' then raise exception 'Only a draft can be changed. A running lease can be ended early, or a new one added.'; end if;
    p_demo := v_old.is_demo;
  end if;
  if rb_txt(p, 'name') is null then raise exception 'Please say what is rented, for example "Kitchen premises, Andheri".'; end if;
  if rb_txt(p, 'lessor') is null then raise exception 'Please give the landlord''s (lessor''s) name.'; end if;
  select * into v_c from expense_categories where id = rb_int(p, 'category_id');
  if v_c.id is null or v_c.direction <> 'out' then raise exception 'Choose the expense category the rent goes to (for example Kitchen rent).'; end if;
  if v_start is null then raise exception 'Please give the date the lease starts.'; end if;
  if coalesce(v_months, 0) < 1 or v_months > 600 then raise exception 'Please give the length of the lease in months.'; end if;
  if v_lock < 0 or v_lock > v_months then raise exception 'The lock-in period cannot be longer than the lease.'; end if;
  if v_rent is null or v_rent < 0 then raise exception 'Please enter the monthly rent.'; end if;
  if v_esc < 0 or v_esc >= 100 then raise exception 'The yearly increase must be between 0%% and 99%%.'; end if;
  if v_every < 1 or v_every > 120 then raise exception 'Say how often the rent goes up, in months (usually 12).'; end if;
  if v_free < 0 or v_free >= v_months then raise exception 'The rent-free months must be fewer than the months of the lease.'; end if;
  if v_basis not in ('straight_line', 'as_paid') then raise exception 'Choose straight line or as paid.'; end if;
  if v_basis = 'as_paid' and rb_txt(p, 'basis_reason') is null then
    raise exception 'AS 19 spreads rent evenly (straight line) unless another basis better matches how the premises are used. Please give the reason, agreed with the CA.';
  end if;
  if v_dep < 0 then raise exception 'The deposit cannot be negative.'; end if;
  if v_takeon then
    if v_tdate is null then raise exception 'Please give the take-on date: the date the app takes over this lease.'; end if;
    if v_tdate <= v_start then raise exception 'The take-on date must be after the start of the lease.'; end if;
    if v_tdate > (v_start + make_interval(months => v_months))::date then raise exception 'This lease ended before the take-on date.'; end if;
  else v_tdate := null; end if;
  if v_sup is not null and not exists (select 1 from suppliers where id = v_sup) then raise exception 'Supplier not found.'; end if;
  v_dept := coalesce(rb_int(p, 'department_id')::int, rb_cb_dept(v_c.default_department_code));
  if not exists (select 1 from departments where id = v_dept and is_active) then raise exception 'That department is closed or merged. Choose an open one.'; end if;
  if v_id is null then
    v_pre := case when p_demo then 'DEMO-' when rb_is_training() then 'TRN-' else '' end || 'OL-';
    insert into op_leases (lease_no, name, lessor, supplier_id, category_id, department_id, start_date, months, lock_in_months, rent_paise,
                           escalation_pct, escalation_every, rent_free_months, basis, basis_reason, deposit_paise, is_takeon, takeon_date,
                           note, entered_by, is_demo, is_training)
    values (rb_next_code(v_pre, v_pre, 3), rb_txt(p, 'name'), rb_txt(p, 'lessor'), v_sup, v_c.id, v_dept, v_start, v_months, v_lock, v_rent,
            v_esc, v_every, v_free, v_basis, case when v_basis = 'as_paid' then rb_txt(p, 'basis_reason') end, v_dep, v_takeon, v_tdate,
            rb_txt(p, 'note'), p_actor, p_demo, rb_is_training())
    returning id into v_id;
  else
    update op_leases set name = rb_txt(p, 'name'), lessor = rb_txt(p, 'lessor'), supplier_id = v_sup, category_id = v_c.id, department_id = v_dept,
      start_date = v_start, months = v_months, lock_in_months = v_lock, rent_paise = v_rent, escalation_pct = v_esc, escalation_every = v_every,
      rent_free_months = v_free, basis = v_basis, basis_reason = case when v_basis = 'as_paid' then rb_txt(p, 'basis_reason') end,
      deposit_paise = v_dep, is_takeon = v_takeon, takeon_date = v_tdate, note = rb_txt(p, 'note'), updated_at = now(), updated_by = p_actor
    where id = v_id;
  end if;
  perform rb_ll_ol_rents(v_id);
  perform rb_audit_write(case when v_old.id is null then 'OP_LEASE_SAVED' else 'OP_LEASE_CHANGED' end, 'op_leases', v_id::text,
    case when v_old.id is not null then to_jsonb(v_old) end, (select to_jsonb(o) from op_leases o where id = v_id), null);
  return v_id;
end $$;

-- Start an operating lease. One already running on the take-on date
-- brings in its deposit and its rent equalisation so far.
create or replace function rb_ll_start_ol(p_ol bigint, p_actor uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare v op_leases; v_e bigint; v_eq bigint; v_c expense_categories; v_open text := rb_ll_acc('loan', 'opening');
begin
  select * into v from op_leases where id = p_ol for update;
  if v.id is null then raise exception 'Lease not found.'; end if;
  if v.status <> 'draft' then raise exception '% has already been started.', v.lease_no; end if;
  select * into v_c from expense_categories where id = v.category_id;
  if v.is_takeon then
    v_eq := rb_ll_eq_at(p_ol, v.takeon_date - 1);
    v_e := rb_ll_entry(null, p_ol, 'takeon', v.takeon_date, jsonb_build_object('event', 'opening', 'source', 'opening',
      'equalisation', v_eq, 'deposit', v.deposit_paise),
      rb_ll_ln(rb_ll_deposit_acc(v.months), v.deposit_paise, 'Security deposit with ' || v.lessor || ' (' || v.lease_no || ')')
      || rb_ll_ln(rb_ll_acc('op_lease', 'equalisation'), -v_eq, 'Rent equalisation to ' || to_char(v.takeon_date - 1, 'DD-Mon-YYYY') || ', ' || v.lease_no)
      || rb_ll_ln(v_open, v_eq - v.deposit_paise, 'Brought in at ' || to_char(v.takeon_date, 'DD-Mon-YYYY')),
      'Opening balance: operating lease ' || v.lease_no || ', ' || v.name || ' from ' || v.lessor, v.department_id, p_actor, v.is_demo);
  end if;
  update op_leases set status = 'active', approved_by = p_actor, approved_at = now() where id = p_ol;
  perform rb_audit_write('OP_LEASE_STARTED', 'op_leases', p_ol::text, null, jsonb_build_object('lease_no', v.lease_no, 'take_on', v.is_takeon), null);
  return v_e;
end $$;

-- Security deposit paid to, or returned by, the landlord.
-- p: lease_id, kind ('paid' or 'returned'), entry_date, amount_paise, money_account_id, reference, note
create or replace function rb_ll_deposit(p jsonb, p_actor uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare v op_leases; v_m money_accounts; v_kind text := rb_txt(p, 'kind'); v_date date := (p->>'entry_date')::date;
        v_amt bigint := rb_int(p, 'amount_paise'); v_held bigint; v_e bigint; v_s int;
begin
  select * into v from op_leases where id = rb_int(p, 'lease_id') for update;
  if v.id is null then raise exception 'Lease not found.'; end if;
  if v.status not in ('active', 'ended') then raise exception 'Start the lease first.'; end if;
  if v_kind not in ('paid', 'returned') then raise exception 'Choose deposit paid or deposit returned.'; end if;
  if v_date is null then raise exception 'Please choose the date.'; end if;
  if coalesce(v_amt, 0) <= 0 then raise exception 'Please enter the amount.'; end if;
  select * into v_m from money_accounts where id = rb_int(p, 'money_account_id');
  if v_m.id is null or not v_m.is_active then raise exception 'Choose an active cash or bank account.'; end if;
  select deposit into v_held from rb_ll_bal(null, v.id, null);
  if v_kind = 'returned' and v_amt > v_held then
    raise exception 'Only % of deposit is held for this lease. If the landlord kept part of it, enter the rest as an expense.', rb_pur_fmt(v_held);
  end if;
  v_s := case when v_kind = 'paid' then 1 else -1 end;
  v_e := rb_ll_entry(null, v.id, case when v_kind = 'paid' then 'deposit_paid' else 'deposit_returned' end, v_date,
    jsonb_build_object('event', 'op_lease_deposit', 'deposit', v_s * v_amt, 'cash', -v_s * v_amt, 'money_account_id', v_m.id,
                       'reference', rb_txt(p, 'reference'), 'note', rb_txt(p, 'note')),
    rb_ll_ln(rb_ll_deposit_acc(v.months), v_s * v_amt, 'Security deposit, ' || v.lease_no)
    || rb_ll_ln(v_m.account_code, -v_s * v_amt, v.lessor),
    'Security deposit ' || case when v_kind = 'paid' then 'paid to ' else 'returned by ' end || v.lessor || ' (' || v.lease_no || ', ' || v.name || ')',
    v.department_id, p_actor, v.is_demo);
  perform rb_audit_write('LEASE_DEPOSIT', 'loan_entries', v_e::text, null, jsonb_build_object('lease_no', v.lease_no, 'kind', v_kind, 'amount_paise', v_amt), null);
  return v_e;
end $$;

-- Enter one month's rent as an expense (module 6), linked to the lease.
-- p: lease_id, n (lease month), expense_date, payment_mode, money_account_id, reference
create or replace function rb_ll_record_rent(p jsonb, p_actor uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare v op_leases; r op_lease_rents; v_x bigint; v_st text; v_mode text := coalesce(rb_txt(p, 'payment_mode'), 'bank');
begin
  select * into v from op_leases where id = rb_int(p, 'lease_id') for update;
  if v.id is null then raise exception 'Lease not found.'; end if;
  if v.status not in ('active', 'ended') then raise exception 'Start the lease first.'; end if;
  select * into r from op_lease_rents where lease_id = v.id and n = rb_int(p, 'n') for update;
  if r.id is null then raise exception 'That month is not part of the lease.'; end if;
  if v.is_takeon and r.period_start < v.takeon_date then raise exception 'That month is before the take-on date, so its rent is already in the old books.'; end if;
  if r.rent_paise = 0 then raise exception 'That month is rent-free.'; end if;
  if r.expense_id is not null then
    select status into v_st from expenses where id = r.expense_id;
    if v_st in ('posted', 'awaiting_approval') then raise exception 'The rent for that month is already entered.'; end if;
  end if;
  v_x := rb_cb_save_expense(jsonb_build_object('category_id', v.category_id, 'expense_date', coalesce(p->>'expense_date', r.period_start::text),
    'department_id', v.department_id, 'supplier_id', case when v_mode = 'credit' then v.supplier_id end,
    'payee', case when v_mode = 'credit' then null else v.lessor end,
    'description', 'Rent for ' || to_char(r.period_start, 'DD-Mon-YYYY') || ' to ' || to_char((r.period_start + interval '1 month - 1 day')::date, 'DD-Mon-YYYY') ||
                   ' (' || v.lease_no || ', ' || v.name || ')',
    'amount_paise', r.rent_paise, 'payment_mode', v_mode, 'money_account_id', rb_int(p, 'money_account_id'),
    'reference', rb_txt(p, 'reference')), p_actor, v.is_demo);
  update op_lease_rents set expense_id = v_x where id = r.id;
  return v_x;
end $$;

-- End an operating lease early. The months after the end date are taken
-- off; the next month-end run releases what is left of the equalisation.
create or replace function rb_ll_end_ol(p jsonb, p_actor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v op_leases; v_date date := (p->>'end_date')::date; v_left int;
begin
  select * into v from op_leases where id = rb_int(p, 'lease_id') for update;
  if v.id is null then raise exception 'Lease not found.'; end if;
  if v.status <> 'active' then raise exception '% is not running.', v.lease_no; end if;
  if v_date is null then raise exception 'Please give the last day of the lease.'; end if;
  if rb_txt(p, 'reason') is null then raise exception 'Please give the reason, for example "Moved to a bigger kitchen".'; end if;
  if v_date < v.start_date then raise exception 'The lease cannot end before it starts.'; end if;
  if exists (select 1 from op_lease_rents r join expenses e on e.id = r.expense_id
             where r.lease_id = v.id and r.period_start > v_date and e.status in ('posted', 'awaiting_approval')) then
    raise exception 'Rent is already entered for months after %. Reverse those expenses first.', to_char(v_date, 'DD-Mon-YYYY');
  end if;
  delete from op_lease_rents where lease_id = v.id and period_start > v_date;
  select count(*) into v_left from op_lease_rents where lease_id = v.id;
  update op_leases set status = 'ended', ended_date = v_date, end_reason = rb_txt(p, 'reason'), months = greatest(v_left, 1),
    lock_in_months = least(lock_in_months, greatest(v_left, 1)), updated_at = now(), updated_by = p_actor
  where id = v.id;
  perform rb_audit_write('OP_LEASE_ENDED', 'op_leases', v.id::text, null, jsonb_build_object('lease_no', v.lease_no, 'end_date', v_date), rb_txt(p, 'reason'));
end $$;

-- ---------------------------------------------------------------------
-- 8. Month-end step: interest, finance charges, depreciation and
--    straight-line rent for every loan and lease
-- ---------------------------------------------------------------------

-- What the step would post for a month (DEMO or real records).
create or replace function rb_ll_month_calc(p_month date, p_demo boolean)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_m date := date_trunc('month', p_month)::date; v_end date; v loans; o op_leases; b record; v_items jsonb := '[]';
        v_ra bigint; v_rd bigint; v_re bigint; v_ti bigint := 0; v_td bigint := 0; v_te bigint := 0; v_pool bigint := 0; v_c expense_categories;
        v_eq_acc text := rb_ll_acc('op_lease', 'equalisation');
begin
  v_end := (v_m + interval '1 month - 1 day')::date;
  for v in select * from loans where is_demo = p_demo and status in ('active', 'closed')
           and coalesce(takeon_date, start_date) <= v_end order by kind, loan_no loop
    select * into b from rb_ll_bal(v.id, null, v_end);
    v_ra := rb_ll_accrual_at(v.id, v_end);
    v_rd := case when v.kind = 'finance_lease' then rb_ll_dep_at(v.id, v_end) else 0 end;
    if v_ra = b.accrued and v_rd = b.depreciation then continue; end if;
    v_items := v_items || jsonb_build_array(jsonb_build_object('type', v.kind, 'loan_id', v.id, 'no', v.loan_no, 'name', v.name,
      'lender', v.lender, 'department_id', v.department_id, 'interest_account', v.interest_account,
      'accrued_required', v_ra, 'accrued_held', b.accrued, 'interest_change', v_ra - b.accrued,
      'dep_account', v.dep_account, 'acc_dep_account', v.acc_dep_account,
      'dep_required', v_rd, 'dep_held', b.depreciation, 'dep_change', v_rd - b.depreciation,
      'eq_change', 0));
    v_ti := v_ti + v_ra - b.accrued; v_td := v_td + v_rd - b.depreciation;
    if v.kind = 'finance_lease' and exists (select 1 from absorption_accounts where account_code = v.dep_account) then
      v_pool := v_pool + abs(v_rd - b.depreciation);
    end if;
  end loop;
  for o in select * from op_leases where is_demo = p_demo and status in ('active', 'ended') and start_date <= v_end order by lease_no loop
    select * into b from rb_ll_bal(null, o.id, v_end);
    v_re := rb_ll_eq_at(o.id, v_end);
    if v_re = b.equalisation then continue; end if;
    select * into v_c from expense_categories where id = o.category_id;
    v_items := v_items || jsonb_build_array(jsonb_build_object('type', 'op_lease', 'op_lease_id', o.id, 'no', o.lease_no, 'name', o.name,
      'lender', o.lessor, 'department_id', o.department_id, 'expense_account', v_c.account_code,
      'eq_required', v_re, 'eq_held', b.equalisation, 'eq_change', v_re - b.equalisation, 'interest_change', 0, 'dep_change', 0));
    v_te := v_te + v_re - b.equalisation;
    if exists (select 1 from absorption_accounts where account_code = v_c.account_code) then v_pool := v_pool + abs(v_re - b.equalisation); end if;
  end loop;
  return jsonb_build_object('month', v_m, 'month_end', v_end, 'demo', p_demo, 'items', v_items,
    'interest_paise', v_ti, 'depreciation_paise', v_td, 'equalisation_paise', v_te, 'pool_paise', v_pool,
    'equalisation_account', v_eq_acc,
    'absorption_posted', exists (select 1 from month_end_runs where kind = 'absorption' and month = v_m and status = 'posted' and is_demo = p_demo),
    'later_run', (select max(month) from month_end_runs where kind = 'loans_leases' and month > v_m and status = 'posted' and is_demo = p_demo),
    'last_run', (select max(month) from month_end_runs where kind = 'loans_leases' and month < v_m and status = 'posted' and is_demo = p_demo),
    'posted', (select to_jsonb(r) - 'details' from month_end_runs r where kind = 'loans_leases' and month = v_m and status = 'posted' and is_demo = p_demo));
end $$;

-- Post the month-end step for loans and leases.
create or replace function rb_ll_post_month(p_month date, p_demo boolean, p_actor uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_m date := date_trunc('month', p_month)::date; v_end date; x jsonb; i jsonb; v_id bigint; v_no text; v_j bigint;
        v_lines jsonb := '[]'; v_ip text := rb_ll_acc('loan', 'interest_payable'); v_dept int;
begin
  if p_month is null then raise exception 'Please choose the month.'; end if;
  v_end := (v_m + interval '1 month - 1 day')::date;
  if v_end >= current_date and not p_demo then
    raise exception 'Run this once % has ended (from %).', to_char(v_m, 'Mon-YYYY'), to_char(v_end + 1, 'DD-Mon-YYYY');
  end if;
  perform rb_assert_period_open(v_end);
  if exists (select 1 from month_end_runs where kind = 'loans_leases' and month = v_m and status = 'posted' and is_demo = p_demo) then
    raise exception 'Loans and leases for % are already posted. Reverse that run first to run it again.', to_char(v_m, 'Mon-YYYY');
  end if;
  x := rb_ll_month_calc(v_m, p_demo);
  if x->>'later_run' is not null then
    raise exception 'Loans and leases are already posted for a later month (%). Months are run in order.', to_char((x->>'later_run')::date, 'Mon-YYYY');
  end if;
  if (x->>'absorption_posted')::boolean and (x->>'pool_paise')::bigint <> 0 then
    raise exception 'Step 1 (labour and overheads into stock) is already posted for %, and this run changes kitchen costs that step 1 shares into stock (depreciation of kitchen assets or kitchen rent). Reverse step 1 first (Cash, bank and expenses -> Month-end), post this, then post step 1 again.',
      to_char(v_m, 'Mon-YYYY');
  end if;
  if jsonb_array_length(x->'items') = 0 then raise exception 'Nothing to post for %: there are no loans or leases with anything due this month.', to_char(v_m, 'Mon-YYYY'); end if;
  v_no := rb_cb_no('ME', p_demo, v_end);
  insert into month_end_runs (run_no, kind, month, run_date, details, amount_paise, entered_by, is_demo, is_training)
  values (v_no, 'loans_leases', v_m, v_end, x, (x->>'interest_paise')::bigint + (x->>'depreciation_paise')::bigint + (x->>'equalisation_paise')::bigint,
          p_actor, p_demo, rb_is_training())
  returning id into v_id;
  for i in select * from jsonb_array_elements(x->'items') loop
    v_dept := (i->>'department_id')::int;
    if i->>'type' = 'op_lease' then
      v_lines := v_lines
        || rb_ll_ln(i->>'expense_account', (i->>'eq_change')::bigint, 'Rent spread evenly (AS 19), ' || (i->>'no') || ' ' || (i->>'name'), v_dept)
        || rb_ll_ln(x->>'equalisation_account', -(i->>'eq_change')::bigint, 'Rent equalisation, ' || (i->>'no'), v_dept);
    else
      v_lines := v_lines
        || rb_ll_ln(i->>'interest_account', (i->>'interest_change')::bigint,
                    case when i->>'type' = 'loan' then 'Interest accrued, ' else 'Finance charge accrued, ' end || (i->>'no') || ' ' || (i->>'name'), v_dept)
        || rb_ll_ln(v_ip, -(i->>'interest_change')::bigint, 'Interest payable, ' || (i->>'no'), v_dept)
        || rb_ll_ln(i->>'dep_account', (i->>'dep_change')::bigint, 'Depreciation of leased asset, ' || (i->>'no') || ' ' || (i->>'name'), v_dept)
        || rb_ll_ln(i->>'acc_dep_account', -(i->>'dep_change')::bigint, 'Accumulated depreciation, ' || (i->>'no'), v_dept);
    end if;
  end loop;
  if jsonb_array_length(v_lines) > 0 then
    v_j := rb_post_engine(jsonb_build_object('journal_date', v_end, 'source', 'loans', 'event_code', 'loans_month_end', 'source_ref', v_no,
      'narration', 'Month-end ' || to_char(v_m, 'Mon-YYYY') || ': loans and leases (interest and finance charges accrued, depreciation of leased assets, rent spread evenly under AS 19)',
      'department_id', rb_cb_dept('CC005'), 'is_demo', p_demo, 'entered_by', p_actor, 'approved_by', p_actor), v_lines);
  end if;
  update month_end_runs set journal_id = v_j where id = v_id;
  for i in select * from jsonb_array_elements(x->'items') loop
    perform rb_ll_entry(case when i->>'type' = 'op_lease' then null else (i->>'loan_id')::bigint end, (i->>'op_lease_id')::bigint, 'month_end', v_end,
      jsonb_build_object('accrued', (i->>'interest_change')::bigint, 'interest', (i->>'interest_change')::bigint,
                         'depreciation', (i->>'dep_change')::bigint, 'equalisation', (i->>'eq_change')::bigint,
                         'run_id', v_id, 'journal_id', v_j, 'reference', v_no), '[]', null, null, p_actor, p_demo);
  end loop;
  perform rb_audit_write('MONTH_END_LOANS', 'month_end_runs', v_id::text, null,
    jsonb_build_object('run_no', v_no, 'month', v_m, 'interest_paise', x->'interest_paise', 'depreciation_paise', x->'depreciation_paise',
                       'equalisation_paise', x->'equalisation_paise'), null);
  return v_id;
end $$;

-- Reversing a loans and leases run (Cash, bank and expenses -> Month-end,
-- or the Loans and leases screen) also reverses its entries. A later
-- month's run must be reversed first.
create or replace function rb_ll_run_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.kind = 'loans_leases' and old.status = 'posted' and new.status = 'reversed' then
    if exists (select 1 from month_end_runs where kind = 'loans_leases' and month > old.month and status = 'posted' and is_demo = old.is_demo) then
      raise exception 'Loans and leases are also posted for a later month. Reverse the latest month first.';
    end if;
    update loan_entries set status = 'reversed', reverse_reason = new.reverse_reason where run_id = old.id and status = 'posted';
  end if;
  return new;
end $$;
drop trigger if exists rb_ll_run_guard on month_end_runs;
create trigger rb_ll_run_guard before update on month_end_runs for each row execute function rb_ll_run_guard();

-- ---------------------------------------------------------------------
-- 9. Journal guard and reversals
-- ---------------------------------------------------------------------

create or replace function rb_ll_journal_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('rb.loans', true), '') = 'on' or coalesce(current_setting('rb.cashbank', true), '') = 'on' then
    return coalesce(new, old);
  end if;
  if tg_op = 'UPDATE' and old.status = 'posted' and new.status = 'reversed'
     and (old.source = 'loans' or (old.source = 'opening' and exists (select 1 from loan_entries where journal_id = old.id))) then
    raise exception 'This entry comes from the Loans and leases screen. Reverse it there, so the loan balances stay right.';
  end if;
  if tg_op = 'DELETE' and old.status <> 'draft' and not old.is_demo and not (old.is_training and rb_is_training())
     and (old.source = 'loans' or exists (select 1 from loan_entries where journal_id = old.id)) then
    raise exception 'This entry comes from the Loans and leases screen. Reverse it there.';
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists rb_ll_journal_guard on journals;
create trigger rb_ll_journal_guard before update or delete on journals for each row execute function rb_ll_journal_guard();

-- Reverse one entry: a payment, part-payment, deposit, the end of a
-- finance lease, or the start (which cancels the loan or lease). Month-end
-- runs are reversed from the Month-end tab.
create or replace function rb_ll_reverse(p_id bigint, p_date date, p_reason text, p_actor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare e loan_entries; v loans; o op_leases; v_rev bigint; b record;
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason for the reversal.'; end if;
  select * into e from loan_entries where id = p_id for update;
  if e.id is null then raise exception 'Entry not found.'; end if;
  if e.status <> 'posted' then raise exception 'This entry is already reversed.'; end if;
  if e.kind = 'month_end' then raise exception 'Month-end entries are reversed with their run, on the Month-end tab.'; end if;
  if p_date is null or p_date < e.entry_date then raise exception 'The reversal date cannot be before the entry''s own date.'; end if;
  if e.loan_id is not null then select * into v from loans where id = e.loan_id for update;
  else select * into o from op_leases where id = e.op_lease_id for update; end if;
  if exists (select 1 from loan_entries x where x.status = 'posted' and x.kind <> 'month_end' and x.id <> e.id
             and (x.loan_id = e.loan_id or x.op_lease_id = e.op_lease_id)
             and (x.entry_date > e.entry_date or (x.entry_date = e.entry_date and x.id > e.id))) then
    raise exception 'There are later entries for this % (payments or deposits). Reverse the latest one first.',
      case when e.loan_id is not null then 'loan or lease' else 'lease' end;
  end if;
  if e.kind in ('start', 'takeon') and exists (select 1 from loan_entries x where x.status = 'posted' and x.id <> e.id
             and (x.loan_id = e.loan_id or x.op_lease_id = e.op_lease_id)) then
    raise exception 'Month-end entries have been posted for it. Reverse those month-end runs first.';
  end if;
  if e.kind = 'deposit_paid' then
    select * into b from rb_ll_bal(null, e.op_lease_id, null);
    if b.deposit < e.deposit_paise then raise exception 'Part of this deposit has already been returned. Reverse the return first.'; end if;
  end if;
  perform set_config('rb.loans', 'on', true);
  v_rev := case when e.journal_id is not null then rb_reverse_journal(e.journal_id, p_date, coalesce(v.loan_no, o.lease_no) || ' ' || e.entry_no || ' reversed: ' || trim(p_reason)) end;
  perform set_config('rb.loans', 'off', true);
  update loan_entries set status = 'reversed', reversal_journal_id = v_rev, reverse_reason = trim(p_reason) where id = e.id;
  if e.kind in ('payment', 'prepayment') then
    update loan_schedule set paid_entry_id = null where paid_entry_id = e.id;
    if v.status = 'closed' then update loans set status = 'active', closed_date = null where id = v.id; end if;
    perform rb_ll_rebuild(v.id, 'emi');
  elsif e.kind = 'lease_end' then
    update loans set status = case when (select owed from rb_ll_bal(v.id, null, null)) = 0 then 'closed' else 'active' end where id = v.id;
  elsif e.kind in ('start', 'takeon') and e.loan_id is not null then
    update loans set status = 'cancelled' where id = v.id;
  elsif e.kind = 'takeon' then
    update op_leases set status = 'cancelled' where id = o.id;
  end if;
  perform rb_audit_write('REVERSE_LOAN_ENTRY', 'loan_entries', p_id::text, null,
    jsonb_build_object('entry_no', e.entry_no, 'kind', e.kind, 'date', p_date), trim(p_reason));
end $$;

-- ---------------------------------------------------------------------
-- 10. What the screens call
-- ---------------------------------------------------------------------

-- Work out a loan or lease from the form, without saving (for the preview).
create or replace function rb_loan_preview(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_me uuid := rb_require('loans.view', 'see loans and leases');
begin
  return rb_ll_prepare(p);
end $$;

create or replace function rb_save_loan(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('loans.add', 'add loans and leases'); v_by uuid;
begin
  if rb_int(p, 'id') is not null then
    select entered_by into v_by from loans where id = rb_int(p, 'id');
    if v_by is distinct from v_me and not rb_has('loans.edit') then
      raise exception 'Only the person who entered it (or someone with Loans and leases -> Edit) can change it.';
    end if;
  end if;
  return rb_ll_save_loan(p, v_me, false);
end $$;

create or replace function rb_delete_draft_loan(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('loans.add', 'delete draft loans'); v loans;
begin
  select * into v from loans where id = p_id for update;
  if v.id is null then raise exception 'Loan or lease not found.'; end if;
  if v.status <> 'draft' then raise exception 'Only a draft can be deleted. Reverse the start to cancel a loan.'; end if;
  if v.entered_by is distinct from v_me and not rb_has('loans.edit') then raise exception 'Only the person who entered it can delete it.'; end if;
  delete from loans where id = p_id;
  perform rb_audit_write('LOAN_DRAFT_DELETED', 'loans', p_id::text, to_jsonb(v), null, null);
end $$;

-- Start (approve) a draft loan or finance lease: this posts it.
create or replace function rb_start_loan(p_id bigint)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('loans.approve', 'start (approve) loans and leases'); v loans;
begin
  select * into v from loans where id = p_id;
  if v.id is null then raise exception 'Loan or lease not found.'; end if;
  if not rb_can_approve('loans', v.entered_by) then raise exception 'You cannot approve your own entries. Ask the FC or a Director.'; end if;
  return rb_ll_start(p_id, v_me);
end $$;

create or replace function rb_pay_loan(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('loans.add', 'enter loan and lease payments');
begin
  return rb_ll_pay(p, v_me);
end $$;

create or replace function rb_prepay_loan(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('loans.add', 'enter loan part-payments');
begin
  return rb_ll_prepay(p, v_me);
end $$;

create or replace function rb_change_loan_rate(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('loans.edit', 'change loan interest rates');
begin
  perform rb_ll_rate(p, v_me);
end $$;

create or replace function rb_end_finance_lease(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('loans.edit', 'end finance leases');
begin
  return rb_ll_end_lease(p, v_me);
end $$;

create or replace function rb_save_op_lease(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('loans.add', 'add leases'); v_by uuid;
begin
  if rb_int(p, 'id') is not null then
    select entered_by into v_by from op_leases where id = rb_int(p, 'id');
    if v_by is distinct from v_me and not rb_has('loans.edit') then
      raise exception 'Only the person who entered it (or someone with Loans and leases -> Edit) can change it.';
    end if;
  end if;
  return rb_ll_save_ol(p, v_me, false);
end $$;

create or replace function rb_delete_draft_op_lease(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('loans.add', 'delete draft leases'); v op_leases;
begin
  select * into v from op_leases where id = p_id for update;
  if v.id is null then raise exception 'Lease not found.'; end if;
  if v.status <> 'draft' then raise exception 'Only a draft can be deleted.'; end if;
  if v.entered_by is distinct from v_me and not rb_has('loans.edit') then raise exception 'Only the person who entered it can delete it.'; end if;
  delete from op_leases where id = p_id;
  perform rb_audit_write('OP_LEASE_DRAFT_DELETED', 'op_leases', p_id::text, to_jsonb(v), null, null);
end $$;

create or replace function rb_start_op_lease(p_id bigint)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('loans.approve', 'start (approve) leases'); v op_leases;
begin
  select * into v from op_leases where id = p_id;
  if v.id is null then raise exception 'Lease not found.'; end if;
  if not rb_can_approve('loans', v.entered_by) then raise exception 'You cannot approve your own entries. Ask the FC or a Director.'; end if;
  return rb_ll_start_ol(p_id, v_me);
end $$;

-- Cancel an operating lease started by mistake (nothing posted for it yet).
create or replace function rb_cancel_op_lease(p_id bigint, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('loans.edit', 'cancel leases'); v op_leases;
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason.'; end if;
  select * into v from op_leases where id = p_id for update;
  if v.id is null or v.status <> 'active' then raise exception 'Only a running lease can be cancelled.'; end if;
  if exists (select 1 from loan_entries where op_lease_id = p_id and status = 'posted') then
    raise exception 'Entries are posted for this lease (deposit, take-on or month-end). Reverse them first, or end the lease instead.';
  end if;
  if exists (select 1 from op_lease_rents r join expenses e on e.id = r.expense_id where r.lease_id = p_id and e.status in ('posted', 'awaiting_approval')) then
    raise exception 'Rent is entered for this lease. Reverse those expenses first, or end the lease instead.';
  end if;
  update op_leases set status = 'cancelled', end_reason = trim(p_reason), updated_at = now(), updated_by = v_me where id = p_id;
  perform rb_audit_write('OP_LEASE_CANCELLED', 'op_leases', p_id::text, null, jsonb_build_object('lease_no', v.lease_no), trim(p_reason));
end $$;

create or replace function rb_lease_deposit(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('loans.add', 'enter lease deposits');
begin
  return rb_ll_deposit(p, v_me);
end $$;

create or replace function rb_record_lease_rent(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('loans.add', 'enter rent');
begin
  return rb_ll_record_rent(p, v_me);
end $$;

create or replace function rb_end_op_lease(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('loans.edit', 'end leases early');
begin
  perform rb_ll_end_ol(p, v_me);
end $$;

create or replace function rb_reverse_loan_entry(p_id bigint, p_date date, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.reverse_entries', 'reverse posted entries');
begin
  perform rb_ll_reverse(p_id, p_date, p_reason, v_me);
end $$;

-- Work on the DEMO records while there are no real loans or leases yet.
create or replace function rb_ll_use_demo()
returns boolean language sql stable security definer set search_path = public as $$
  select not exists (select 1 from loans where not is_demo and status <> 'draft')
     and not exists (select 1 from op_leases where not is_demo and status <> 'draft')
     and (exists (select 1 from loans where is_demo) or exists (select 1 from op_leases where is_demo))
$$;

create or replace function rb_loans_month_preview(p_month date, p_demo boolean default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_demo boolean := coalesce(p_demo, rb_ll_use_demo());
begin
  if not (rb_has('power.month_end') or rb_has('accounts.view')) then raise exception 'You do not have the right to run the month-end steps.'; end if;
  if p_month is null then raise exception 'Please choose the month.'; end if;
  return rb_ll_month_calc(p_month, v_demo);
end $$;

create or replace function rb_post_loans_month(p_month date, p_demo boolean default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.month_end', 'run the month-end steps');
begin
  return rb_ll_post_month(p_month, coalesce(p_demo, rb_ll_use_demo()), v_me);
end $$;

-- ---------------------------------------------------------------------
-- 11. Reading
-- ---------------------------------------------------------------------

-- One loan or finance lease with its schedule, entries and balances.
create or replace function rb_loan_detail(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v loans; b record;
begin
  if not (rb_has('loans.view') or rb_has('accounts.view')) then raise exception 'You do not have the right to see loans and leases.'; end if;
  select * into v from loans where id = p_id;
  if v.id is null then raise exception 'Loan or lease not found.'; end if;
  select * into b from rb_ll_bal(p_id, null, null);
  return jsonb_build_object('loan', to_jsonb(v), 'owed_paise', b.owed, 'accrued_paise', b.accrued, 'asset_paise', b.asset,
    'depreciation_paise', b.depreciation, 'carrying_paise', b.asset - b.depreciation,
    'accrued_today_paise', case when v.status in ('active', 'closed') then rb_ll_accrual_at(p_id, current_date) end,
    'account_name', (select coalesce(local_name, name) from accounts where code = v.account_code),
    'money_account', (select name from money_accounts where id = v.money_account_id),
    'schedule', coalesce((select jsonb_agg(to_jsonb(s) || jsonb_build_object('paid_on', e.entry_date, 'paid_no', e.entry_no) order by s.n)
                          from loan_schedule s left join loan_entries e on e.id = s.paid_entry_id where s.loan_id = p_id), '[]'),
    'entries', coalesce((select jsonb_agg(to_jsonb(e) order by e.entry_date, e.id) from loan_entries e where e.loan_id = p_id), '[]'),
    'rate_changes', coalesce((select jsonb_agg(to_jsonb(r) order by r.id) from loan_rate_changes r where r.loan_id = p_id), '[]'));
end $$;

-- One operating lease with its rent months, entries and balances.
create or replace function rb_op_lease_detail(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v op_leases; b record; v_tot bigint; v_n int;
begin
  if not (rb_has('loans.view') or rb_has('accounts.view')) then raise exception 'You do not have the right to see loans and leases.'; end if;
  select * into v from op_leases where id = p_id;
  if v.id is null then raise exception 'Lease not found.'; end if;
  select * into b from rb_ll_bal(null, p_id, null);
  select coalesce(sum(rent_paise), 0), count(*) into v_tot, v_n from op_lease_rents where lease_id = p_id;
  return jsonb_build_object('lease', to_jsonb(v), 'equalisation_paise', b.equalisation, 'deposit_paise', b.deposit,
    'total_rent_paise', v_tot, 'straight_line_paise', case when v_n > 0 then round(v_tot::numeric / v_n) end,
    'category', (select name from expense_categories where id = v.category_id),
    'expense_account', (select account_code from expense_categories where id = v.category_id),
    'deposit_account', rb_ll_deposit_acc(v.months),
    'rents', coalesce((select jsonb_agg(to_jsonb(r) || jsonb_build_object('expense_no', e.expense_no, 'expense_status', e.status,
                         'before_takeon', v.is_takeon and r.period_start < v.takeon_date) order by r.n)
                       from op_lease_rents r left join expenses e on e.id = r.expense_id where r.lease_id = p_id), '[]'),
    'entries', coalesce((select jsonb_agg(to_jsonb(e) order by e.entry_date, e.id) from loan_entries e where e.op_lease_id = p_id), '[]'));
end $$;

-- Everything owed on loans and finance leases at a date, split into what
-- falls due within 12 months (shown under current liabilities as current
-- maturities) and after; and the operating leases.
create or replace function rb_loans_summary(p_as_of date default current_date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_to date := coalesce(p_as_of, current_date);
begin
  if not (rb_has('loans.view') or rb_has('accounts.view')) then raise exception 'You do not have the right to see loans and leases.'; end if;
  return jsonb_build_object('as_of', v_to,
    'loans', coalesce((select jsonb_agg(x order by x.kind, x.loan_no) from (
      select l.id, l.loan_no, l.kind, l.name, l.lender, l.lender_type, l.status, l.account_code, l.annual_rate, l.rate_type, l.emi_paise,
             l.is_demo, l.asset_name, l.start_date, l.is_takeon,
             (select coalesce(local_name, name) from accounts where code = l.account_code) account_name,
             b.owed owed_paise, b.accrued accrued_paise, b.asset - b.depreciation carrying_paise,
             least(b.owed, (select coalesce(sum(s.principal_paise), 0) from loan_schedule s left join loan_entries e on e.id = s.paid_entry_id
                            where s.loan_id = l.id and s.due_date <= (v_to + interval '12 months')::date
                              and (s.paid_entry_id is null or e.status <> 'posted' or e.entry_date > v_to)))::bigint within_12_paise,
             (select to_jsonb(s) from loan_schedule s where s.loan_id = l.id and s.paid_entry_id is null order by s.n limit 1) next_due,
             (select count(*) from loan_schedule s where s.loan_id = l.id and s.paid_entry_id is null and s.due_date < current_date) overdue
      from loans l cross join lateral rb_ll_bal(l.id, null, v_to) b
      where l.status <> 'cancelled') x), '[]'),
    'op_leases', coalesce((select jsonb_agg(x order by x.lease_no) from (
      select o.id, o.lease_no, o.name, o.lessor, o.status, o.start_date, o.months, o.lock_in_months, o.basis, o.is_demo,
             (o.start_date + make_interval(months => o.months) - interval '1 day')::date end_date,
             (select name from expense_categories where id = o.category_id) category,
             (select rent_paise from op_lease_rents r where r.lease_id = o.id and r.period_start <= v_to order by n desc limit 1) rent_now_paise,
             (select round(avg(rent_paise)) from op_lease_rents r where r.lease_id = o.id) straight_line_paise,
             b.equalisation equalisation_paise, b.deposit deposit_paise,
             (select count(*) from op_lease_rents r left join expenses e on e.id = r.expense_id
              where r.lease_id = o.id and r.period_start <= current_date and r.rent_paise > 0
                and not (o.is_takeon and r.period_start < o.takeon_date)
                and (r.expense_id is null or e.status not in ('posted', 'awaiting_approval'))) rent_not_entered
      from op_leases o cross join lateral rb_ll_bal(null, o.id, v_to) b
      where o.status <> 'cancelled') x), '[]'));
end $$;

-- AS 19 disclosures at a date (and the charges of the period from p_from).
--   Finance leases: minimum lease payments still to pay and their present
--   value, not later than 1 year / 1 to 5 years / later than 5 years;
--   the leased assets; depreciation and finance charges for the period.
--   Operating leases: future payments under the non-cancellable (lock-in)
--   period, in the same bands; rent charged to profit and loss in the period.
--   Loans: principal falling due in the same bands.
--   Works on the DEMO records while there are no real loans or leases yet.
create or replace function rb_lease_disclosure(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_to date := coalesce(p_to, current_date); v_from date := coalesce(p_from, rb_fy_start(coalesce(p_to, current_date)));
        v_demo boolean := rb_ll_use_demo(); y1 date; y5 date; v_fin jsonb; v_ops jsonb; v_loan jsonb; v_assets jsonb; v_chg bigint := 0; v_o op_leases; v_rows bigint;
begin
  if not (rb_has('loans.view') or rb_has('accounts.view')) then raise exception 'You do not have the right to see loans and leases.'; end if;
  if v_from > v_to then raise exception 'Please choose a From date on or before the To date.'; end if;
  y1 := (v_to + interval '1 year')::date; y5 := (v_to + interval '5 years')::date;
  with u as (
    select l.kind, s.due_date, s.payment_paise, s.principal_paise
    from loan_schedule s join loans l on l.id = s.loan_id left join loan_entries e on e.id = s.paid_entry_id
    where l.status in ('active', 'closed', 'ended') and coalesce(l.takeon_date, l.start_date) <= v_to and l.is_demo = v_demo
      and (s.paid_entry_id is null or e.status <> 'posted' or e.entry_date > v_to)),
  bands as (
    select kind, case when due_date <= y1 then 1 when due_date <= y5 then 2 else 3 end band, sum(payment_paise) mlp, sum(principal_paise) pv
    from u group by 1, 2)
  select jsonb_agg(jsonb_build_object('kind', kind, 'band', band, 'payments_paise', mlp, 'principal_paise', pv, 'interest_paise', mlp - pv)
                   order by kind, band) into v_fin from bands;
  select coalesce(jsonb_agg(jsonb_build_object('account', a.code, 'name', coalesce(a.local_name, a.name), 'cost_paise', x.cost,
                   'depreciation_paise', x.dep, 'carrying_paise', x.cost - x.dep) order by a.code), '[]') into v_assets
  from (select l.asset_account, sum(b.asset) cost, sum(b.depreciation) dep from loans l cross join lateral rb_ll_bal(l.id, null, v_to) b
        where l.kind = 'finance_lease' and l.is_demo = v_demo group by 1 having sum(b.asset) <> 0) x join accounts a on a.code = x.asset_account;
  with f as (
    select r.lease_id, r.period_start, r.rent_paise from op_lease_rents r join op_leases o on o.id = r.lease_id
    where o.status = 'active' and o.is_demo = v_demo and r.period_start > v_to and r.period_start < (o.start_date + make_interval(months => o.lock_in_months))::date)
  select coalesce(jsonb_agg(jsonb_build_object('band', band, 'payments_paise', amt) order by band), '[]') into v_ops
  from (select case when period_start <= y1 then 1 when period_start <= y5 then 2 else 3 end band, sum(rent_paise) amt from f group by 1) z;
  for v_o in select * from op_leases where status in ('active', 'ended') and start_date <= v_to and is_demo = v_demo loop
    select coalesce(sum(rent_paise), 0) into v_rows from op_lease_rents where lease_id = v_o.id and period_start between v_from and v_to
      and not (v_o.is_takeon and period_start < v_o.takeon_date);
    v_chg := v_chg + v_rows + rb_ll_eq_at(v_o.id, v_to) - case when v_o.is_takeon and v_o.takeon_date > v_from then rb_ll_eq_at(v_o.id, v_o.takeon_date - 1)
                                                               else rb_ll_eq_at(v_o.id, v_from - 1) end;
  end loop;
  return jsonb_build_object('from', v_from, 'to', v_to, 'demo', v_demo, 'band_labels', jsonb_build_array('Not later than 1 year', 'Later than 1 year and not later than 5 years', 'Later than 5 years'),
    'schedules', coalesce(v_fin, '[]'), 'leased_assets', v_assets, 'operating_future', v_ops, 'operating_charge_paise', v_chg,
    'cancellable_leases', (select count(*) from op_leases where status = 'active' and lock_in_months = 0 and is_demo = v_demo),
    'finance_charge_paise', (select coalesce(sum(e.interest_paise), 0) from loan_entries e join loans l on l.id = e.loan_id
                             where l.kind = 'finance_lease' and l.is_demo = v_demo and e.status = 'posted' and e.entry_date between v_from and v_to),
    'loan_interest_paise', (select coalesce(sum(e.interest_paise), 0) from loan_entries e join loans l on l.id = e.loan_id
                            where l.kind = 'loan' and l.is_demo = v_demo and e.status = 'posted' and e.entry_date between v_from and v_to),
    'depreciation_paise', (select coalesce(sum(e.depreciation_paise), 0) from loan_entries e
                           where e.loan_id is not null and e.is_demo = v_demo and e.kind = 'month_end' and e.status = 'posted' and e.entry_date between v_from and v_to));
end $$;

-- ---------------------------------------------------------------------
-- 12. Row-level security and who may call what
-- ---------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array['loans', 'loan_schedule', 'loan_rate_changes', 'op_leases', 'op_lease_rents', 'loan_entries'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon, authenticated', t);
    execute format('grant select on %I to authenticated', t);
    execute format('grant all on %I to service_role', t);
    execute format('drop policy if exists rb_read on %I', t);
    execute format('create policy rb_read on %I for select to authenticated using (rb_has(''loans.view'') or rb_has(''accounts.view''))', t);
  end loop;
end $$;
revoke all on all sequences in schema public from anon, authenticated;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p
           where p.pronamespace = 'public'::regnamespace
             and (p.proname like 'rb\_ll\_%' or p.proname in (
               'rb_loan_preview', 'rb_save_loan', 'rb_delete_draft_loan', 'rb_start_loan', 'rb_pay_loan', 'rb_prepay_loan',
               'rb_change_loan_rate', 'rb_end_finance_lease', 'rb_save_op_lease', 'rb_delete_draft_op_lease', 'rb_start_op_lease',
               'rb_cancel_op_lease', 'rb_lease_deposit', 'rb_record_lease_rent', 'rb_end_op_lease', 'rb_reverse_loan_entry',
               'rb_loans_month_preview', 'rb_post_loans_month', 'rb_loan_detail', 'rb_op_lease_detail', 'rb_loans_summary',
               'rb_lease_disclosure')) loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;
end $$;
grant execute on function
  rb_loan_preview(jsonb), rb_save_loan(jsonb), rb_delete_draft_loan(bigint), rb_start_loan(bigint), rb_pay_loan(jsonb),
  rb_prepay_loan(jsonb), rb_change_loan_rate(jsonb), rb_end_finance_lease(jsonb), rb_save_op_lease(jsonb),
  rb_delete_draft_op_lease(bigint), rb_start_op_lease(bigint), rb_cancel_op_lease(bigint, text), rb_lease_deposit(jsonb),
  rb_record_lease_rent(jsonb), rb_end_op_lease(jsonb), rb_reverse_loan_entry(bigint, date, text),
  rb_loans_month_preview(date, boolean), rb_post_loans_month(date, boolean), rb_loan_detail(bigint), rb_op_lease_detail(bigint),
  rb_loans_summary(date), rb_lease_disclosure(date, date)
  to authenticated;

-- ---------------------------------------------------------------------
-- 13. DEMO data: two loans (a bank term loan brought in at the take-on
--     date, with its November EMI paid; a loan from a partner, interest
--     only), a finance lease (a delivery van, first payment made), two
--     operating leases (the kitchen on an 11-month leave and licence, and
--     the shop for 3 years with a rent-free month and 5% a year more),
--     both security deposits, the shop's November rent, and the
--     month-end step for November 2026. Only added while the app is in
--     training mode.
-- ---------------------------------------------------------------------

do $$
declare
  v_fc  uuid := coalesce((select id from app_users where email = 'demo.fc@example.com'), (select id from app_users where lower(email) = 'info.ruchibuds@gmail.com'));
  v_acc uuid := coalesce((select id from app_users where email = 'demo.accounts@example.com'), v_fc);
  v_bank int; v_l1 bigint; v_l2 bigint; v_fl bigint; v_ol1 bigint; v_ol2 bigint; v_x bigint; p2 int; p2name text;
begin
  if not (select training_mode from app_settings where id = 1) or exists (select 1 from loans where is_demo)
     or exists (select 1 from op_leases where is_demo) or not exists (select 1 from expenses where is_demo) then
    return;
  end if;
  select id into v_bank from money_accounts where account_code = '10010205';
  select (e->>'id')::int, e->>'name' into p2, p2name from app_settings s, jsonb_array_elements(s.partners) with ordinality x(e, n) where s.id = 1 and n = 2;

  -- 1. A kitchen equipment loan taken in Nov 2025, brought in at 1-Nov-2026
  --    with ₹4,00,000 still owed and 36 EMIs to go; October's interest
  --    accrued (27 of 31 days) comes in with it.
  v_l1 := rb_ll_save_loan(jsonb_build_object('kind', 'loan', 'name', 'Kitchen equipment term loan (DEMO)',
    'lender', 'Bank of Maharashtra, Andheri (DEMO)', 'lender_type', 'bank', 'start_date', '2025-11-05', 'is_takeon', true,
    'takeon_date', '2026-11-01', 'takeon_accrued_paise', 304839, 'principal_paise', 40000000, 'annual_rate', 10.5, 'rate_type', 'floating',
    'instalments', 36, 'first_due_date', '2026-11-05', 'money_account_id', v_bank,
    'note', 'Brought in at the take-on date (DEMO)'), v_acc, true);
  perform rb_ll_start(v_l1, v_fc);
  perform rb_ll_pay(jsonb_build_object('loan_id', v_l1, 'pay_date', '2026-11-05', 'money_account_id', v_bank, 'reference', 'ECS 05-Nov (DEMO)'), v_acc);

  -- 2. A partner lends ₹1,00,000 at 9% for 2 years, interest monthly.
  v_l2 := rb_ll_save_loan(jsonb_build_object('kind', 'loan', 'name', 'Loan from ' || coalesce(p2name, 'a partner') || ' for festival stock (DEMO)',
    'lender', coalesce(p2name, 'Partner 2') || ' (DEMO)', 'lender_type', 'related', 'start_date', '2026-11-10', 'principal_paise', 10000000,
    'annual_rate', 9, 'method', 'bullet', 'instalments', 24, 'first_due_date', '2026-12-10', 'money_account_id', v_bank), v_acc, true);
  perform rb_ll_start(v_l2, v_fc);

  -- 3. A delivery van on a 3-year finance lease: 36 payments of ₹7,800 in
  --    advance; fair value ₹2,40,000; the van returns at the end.
  v_fl := rb_ll_save_loan(jsonb_build_object('kind', 'finance_lease', 'name', 'Delivery van lease (DEMO)', 'lender', 'Sai Leasing and Finance (DEMO)',
    'lender_type', 'nbfc', 'start_date', '2026-11-01', 'emi_paise', 780000, 'instalments', 36, 'in_advance', true,
    'fair_value_paise', 24000000, 'asset_name', 'Tata Ace delivery van (DEMO)', 'asset_account', '20010145', 'useful_life_months', 72,
    'department_id', rb_cb_dept('CC003'), 'money_account_id', v_bank), v_acc, true);
  perform rb_ll_start(v_fl, v_fc);
  perform rb_ll_pay(jsonb_build_object('loan_id', v_fl, 'pay_date', '2026-11-01', 'money_account_id', v_bank, 'reference', 'NACH 01-Nov (DEMO)'), v_acc);

  -- 4. The kitchen: 11-month leave and licence at ₹6,000 a month, 6 months
  --    lock-in, ₹18,000 deposit. November's rent is module 6's DEMO
  --    "Kitchen rent for November".
  v_ol1 := rb_ll_save_ol(jsonb_build_object('name', 'Kitchen premises, Andheri (DEMO)', 'lessor', 'Mr R. Shetty (DEMO)',
    'category_id', (select id from expense_categories where name = 'Kitchen rent'), 'start_date', '2026-11-01', 'months', 11,
    'lock_in_months', 6, 'rent_paise', 600000, 'deposit_paise', 1800000), v_acc, true);
  perform rb_ll_start_ol(v_ol1, v_fc);
  perform rb_ll_deposit(jsonb_build_object('lease_id', v_ol1, 'kind', 'paid', 'entry_date', '2026-11-01', 'amount_paise', 1800000,
    'money_account_id', v_bank, 'reference', 'NEFT (DEMO)'), v_acc);
  update op_lease_rents set expense_id = (select id from expenses where is_demo and description = 'Kitchen rent for November (DEMO)' limit 1)
  where lease_id = v_ol1 and n = 1;

  -- 5. The shop: 3 years from 1-Oct-2026 at ₹15,000 a month, October
  --    rent-free, 5% more each year, 12 months lock-in, ₹30,000 deposit.
  v_ol2 := rb_ll_save_ol(jsonb_build_object('name', 'Shop, Lokhandwala Market (DEMO)', 'lessor', 'Lokhandwala Traders (DEMO)',
    'category_id', (select id from expense_categories where name = 'Shop or office rent'), 'start_date', '2026-10-01', 'months', 36,
    'lock_in_months', 12, 'rent_paise', 1500000, 'escalation_pct', 5, 'escalation_every', 12, 'rent_free_months', 1,
    'deposit_paise', 3000000), v_acc, true);
  perform rb_ll_start_ol(v_ol2, v_fc);
  perform rb_ll_deposit(jsonb_build_object('lease_id', v_ol2, 'kind', 'paid', 'entry_date', '2026-10-01', 'amount_paise', 3000000,
    'money_account_id', v_bank, 'reference', 'Cheque 000112 (DEMO)'), v_acc);
  v_x := rb_ll_record_rent(jsonb_build_object('lease_id', v_ol2, 'n', 2, 'expense_date', '2026-11-02', 'payment_mode', 'bank',
    'money_account_id', v_bank, 'reference', 'NEFT (DEMO)'), v_acc);
  if (select status from expenses where id = v_x) = 'awaiting_approval' then perform rb_cb_post_expense(v_x, v_fc); end if;

  -- 6. The month-end step for November 2026, run by the FC.
  perform rb_ll_post_month('2026-11-01', true, v_fc);
end $$;

-- End of 07_loans_leases.sql
