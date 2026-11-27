-- =====================================================================
-- RUCHI BUDS APP · Module 6: Cash, bank and expenses
-- File: 06_cash_bank.sql · Version 1.0 · 27-Nov-2026
--
-- What this file sets up:
--   The firm's money accounts (cash in hand, petty cash and up to four
--   bank or UPI accounts on the Master COA bank codes); expenses (rent,
--   gas, electricity, wages, transport, repairs, marketing, bank charges
--   and the rest) each with a category, department, payment mode and a
--   bill photo or note, numbered EXP/YYMM/00001; other money received
--   (bank interest, scrap) numbered OIN/YYMM/00001; expenses on credit,
--   which stay open in the supplier balance until paid, like a credit
--   purchase; approval of expenses above the Settings limit; transfers
--   between cash and bank (CTR/YYMM/00001); partners' capital brought in
--   or taken out and drawings (PTR/YYMM/00001); the cash book with each
--   day's opening and closing balance; the day-end cash count with any
--   difference posted with its reason (CNT/YYMM/00001); the monthly bank
--   reconciliation; and two month-end steps (ME/YYMM/00001):
--     1. AS 2 stock costing: the month's kitchen labour and production
--        overheads are shared over the month's batches (by kg produced,
--        number of batches, hours worked or value of materials) and the
--        part that belongs to stock still on hand at month-end is added
--        to its cost.
--     2. Provision for doubtful debts: customer balances are aged at
--        month-end and the provision is set to the percentages the CA
--        gives for each age band (Settings).
--
-- Accounting (Indian AS, ICAI): expenses are charged when incurred
-- (accrual basis). GST on an expense bill is input credit only for bills
-- dated on or after the "GST registered from" date, exactly as for
-- purchases; before that it is part of the expense. An expense on credit
-- raises the supplier balance (Trade payables). Inventories include the
-- costs of conversion (AS 2 paras 6 to 10): kitchen labour and production
-- overheads (rent, gas, power, repairs and the like) are absorbed into
-- stock; fixed overheads are absorbed on normal capacity when a normal
-- monthly output is set, and the unabsorbed part stays an expense.
-- Selling, administration and storage costs are never added to stock.
-- The provision for doubtful debts is a prudent estimate of customer
-- balances that may not be collected; it is shown as a deduction from
-- trade receivables and its movement is charged (or written back) to
-- profit and loss each month. Partners' capital and drawings go to each
-- partner's capital and current account.
--
-- Run 01 to 05 first. Then: Supabase -> SQL Editor -> New query -> paste
-- this whole file -> Run. It is safe to run again; nothing you entered
-- is lost on a re-run. If 03 is ever run again, run this file again
-- straight after it (this file extends the supplier payment functions).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Screens, settings and the new special right
-- ---------------------------------------------------------------------

update screens set available = true where code = 'cash_bank';

-- Expenses above this need approval (blank = no approval needed).
alter table app_settings add column if not exists expense_approval_limit_paise bigint;
-- How the month's labour and overheads are shared over the batches.
alter table app_settings add column if not exists absorption_method text not null default 'kg';
-- Normal monthly output in kg (AS 2 normal capacity). Blank = not used.
alter table app_settings add column if not exists normal_output_kg numeric(14,3);
-- Provision for doubtful debts: % per age band (days past the due date),
-- and for balances that are not on an invoice. The CA sets the rates.
alter table app_settings add column if not exists doubtful_debt_bands jsonb not null default
  '[{"upto":0,"pct":0},{"upto":30,"pct":0},{"upto":90,"pct":0},{"upto":180,"pct":0},{"upto":365,"pct":0},{"upto":null,"pct":0}]';
alter table app_settings add column if not exists doubtful_debt_other_pct numeric(5,2) not null default 0;
alter table app_settings add column if not exists doubtful_debt_rates_note text;
alter table app_settings add column if not exists doubtful_debt_rates_example boolean not null default false;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'app_settings_absorption_method_check') then
    alter table app_settings add constraint app_settings_absorption_method_check
      check (absorption_method in ('kg', 'batches', 'hours', 'material'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'app_settings_expense_limit_check') then
    alter table app_settings add constraint app_settings_expense_limit_check check (expense_approval_limit_paise is null or expense_approval_limit_paise >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'app_settings_normal_output_check') then
    alter table app_settings add constraint app_settings_normal_output_check check (normal_output_kg is null or normal_output_kg > 0);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'app_settings_dd_other_check') then
    alter table app_settings add constraint app_settings_dd_other_check check (doubtful_debt_other_pct between 0 and 100);
  end if;
  -- New right: run the month-end steps. Given once to every Accountant
  -- category; Directors and the FC always have every right. The Manager
  -- categories get Cash, bank and expenses: view and add, so kitchen
  -- expenses can be entered where they happen (above the limit they wait
  -- for approval).
  if not exists (select 1 from permissions where code = 'power.month_end') then
    insert into powers (code, name, description, sort) values
      ('month_end', 'Month-end steps',
       'Run or reverse the month-end steps: labour and overheads into stock cost (AS 2), and the provision for doubtful debts', 68)
    on conflict (code) do nothing;
    insert into permissions (code, kind, power_code, sort) values ('power.month_end', 'power', 'month_end', 10068)
    on conflict (code) do nothing;
    insert into category_access (category_id, perm)
    select id, 'power.month_end' from user_categories where template = 'Accountant'
    on conflict do nothing;
    insert into category_access (category_id, perm)
    select c.id, x.perm from user_categories c cross join (values ('cash_bank.view'), ('cash_bank.add')) x(perm)
    where c.template = 'Manager'
    on conflict do nothing;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. Chart of accounts: two Ruchi Buds accounts for the provision
-- ---------------------------------------------------------------------

-- The Master COA's "Expected Credit Loss" accounts are IFRS 9 wording and
-- are hidden for E002. Indian AS uses a provision for doubtful debts.
insert into accounts (code, name, class, statement, normal_balance, status, subledger, level, e002_active, cash_flow, source)
values
  ('10020225', 'Provision for Doubtful Debts', 'Contra Asset', 'BS', 'Credit', 'Active', 'AR', 'posting', true, 'non_cash', 'local'),
  ('80080140', 'Provision for Doubtful Debts (charge)', 'Expense', 'PL', 'Debit', 'Active', 'AR', 'posting', true, 'non_cash', 'local')
on conflict (code) do nothing;

-- ---------------------------------------------------------------------
-- 3. Tables
-- ---------------------------------------------------------------------

-- The firm's cash and bank accounts, each on its own Master COA code.
create table if not exists money_accounts (
  id            serial primary key,
  account_code  text not null unique references accounts(code),
  kind          text not null check (kind in ('cash', 'bank')),
  name          text not null,
  bank_name     text,
  account_last4 text,
  upi_id        text,
  is_default    boolean not null default false,
  is_active     boolean not null default true,
  sort          int not null default 100,
  updated_at    timestamptz,
  updated_by    uuid
);
insert into money_accounts (account_code, kind, name, is_default, is_active, sort) values
  ('10010110', 'cash', 'Cash in hand (shop and kitchen)', true,  true,  10),
  ('10010105', 'cash', 'Petty cash',                      false, false, 20),
  ('10010205', 'bank', 'Bank account 1 (main, UPI)',      true,  true,  30),
  ('10010210', 'bank', 'Bank account 2',                  false, false, 40),
  ('10010215', 'bank', 'Bank account 3',                  false, false, 50),
  ('10010220', 'bank', 'Bank account 4',                  false, false, 60)
on conflict (account_code) do nothing;

-- What an expense (or other money received) is for, and the account it goes to.
create table if not exists expense_categories (
  id                     serial primary key,
  name                   text not null unique,
  direction              text not null default 'out' check (direction in ('out', 'in')),
  account_code           text not null references accounts(code),
  default_department_code text,
  hint                   text,
  is_active              boolean not null default true,
  sort                   int not null default 100,
  updated_at             timestamptz,
  updated_by             uuid
);
insert into expense_categories (name, direction, account_code, default_department_code, hint, sort) values
  ('Kitchen rent',                       'out', '70030120', 'CC001', 'Rent for the kitchen and its store (part of stock cost)', 10),
  ('Kitchen gas',                        'out', '70030105', 'CC001', 'Gas cylinders for cooking (part of stock cost)', 20),
  ('Kitchen electricity and water',      'out', '70030105', 'CC001', 'Part of stock cost', 30),
  ('Kitchen wages',                      'out', '70020110', 'CC001', 'Cooks and kitchen workers paid by the day or month (part of stock cost)', 40),
  ('Kitchen helpers on contract',        'out', '70020125', 'CC001', 'Casual or contract kitchen help (part of stock cost)', 50),
  ('Kitchen repairs and cleaning',       'out', '70030110', 'CC001', 'Stove, mixer and kitchen repairs (part of stock cost)', 60),
  ('Kitchen supplies',                   'out', '70030135', 'CC001', 'Gloves, caps, cleaning liquid, cloth (part of stock cost)', 70),
  ('Shop or office rent',                'out', '80020105', 'CC002', null, 80),
  ('Shop or office electricity and water','out', '80020110', 'CC002', null, 90),
  ('Shop and office salaries',           'out', '80010105', 'CC005', 'Sales, delivery and office staff (not part of stock cost)', 100),
  ('Transport and delivery',             'out', '80060125', 'CC003', 'Delivery to customers (not part of stock cost)', 110),
  ('Fuel',                               'out', '80060120', 'CC005', null, 120),
  ('Repairs and maintenance (shop, office)','out', '80020135', 'CC002', null, 130),
  ('Marketing and printing',             'out', '80030105', 'CC002', 'Leaflets, labels for promotions, stalls', 140),
  ('Digital advertising',                'out', '80030110', 'CC004', 'Instagram, Facebook and Google ads', 150),
  ('Phone and internet',                 'out', '80020115', 'CC005', null, 160),
  ('Office supplies and stationery',     'out', '80020120', 'CC005', null, 170),
  ('Bank charges',                       'out', '80050150', 'CC005', null, 180),
  ('Accounting and audit fees',          'out', '80050110', 'CC005', null, 190),
  ('Licence and legal fees',             'out', '80050135', 'CC005', 'FSSAI, trade licence, legal', 200),
  ('Software and subscriptions',         'out', '80040110', 'CC005', null, 210),
  ('Staff welfare (tea, meals)',         'out', '80010135', 'CC005', null, 220),
  ('Travel',                             'out', '80060105', 'CC005', null, 230),
  ('Postage and courier',                'out', '80060135', 'CC005', null, 240),
  ('Insurance',                          'out', '80020145', 'CC005', null, 250),
  ('Donations',                          'out', '80060145', 'CC005', null, 260),
  ('Other expenses',                     'out', '80060140', 'CC005', 'Anything that fits nowhere else: say what it was', 270),
  ('Bank interest received',             'in',  '90010105', 'CC005', null, 500),
  ('Scrap and empty cartons sold',       'in',  '90010135', 'CC005', 'Goods made for sale go through Sales, not here', 510),
  ('Other income',                       'in',  '90010135', 'CC005', null, 520)
on conflict (name) do nothing;

-- Which accounts make up the labour and production overheads shared into
-- stock at month-end (AS 2 costs of conversion), and whether each is fixed
-- (does not change with output) or variable.
create table if not exists absorption_accounts (
  account_code text primary key references accounts(code),
  behaviour    text not null default 'fixed' check (behaviour in ('fixed', 'variable')),
  updated_at   timestamptz,
  updated_by   uuid
);
insert into absorption_accounts (account_code, behaviour) values
  ('70020105', 'fixed'), ('70020110', 'variable'), ('70020115', 'variable'), ('70020120', 'fixed'),
  ('70020125', 'variable'), ('70030105', 'variable'), ('70030110', 'fixed'), ('70030115', 'fixed'),
  ('70030120', 'fixed'), ('70030125', 'fixed'), ('70030130', 'fixed'), ('70030135', 'variable')
on conflict (account_code) do nothing;

-- Each change of the sharing method: reason and who changed it (a Director).
create table if not exists absorption_method_log (
  id          bigserial primary key,
  changed_at  timestamptz not null default now(),
  changed_by  uuid references app_users(id),
  old_method  text,
  new_method  text not null,
  reason      text not null
);

-- Expenses and other money received.
create table if not exists expenses (
  id                  bigserial primary key,
  expense_no          text unique,
  direction           text not null default 'out' check (direction in ('out', 'in')),
  expense_date        date not null,
  category_id         int not null references expense_categories(id),
  account_code        text not null references accounts(code),
  department_id       int not null references departments(id),
  supplier_id         int references suppliers(id),
  payee               text,
  description         text not null,
  bill_no             text,
  bill_date           date,
  amount_paise        bigint not null check (amount_paise > 0),     -- before GST
  gst_paise           bigint not null default 0 check (gst_paise >= 0),
  gst_claimed         boolean not null default false,
  total_paise         bigint not null check (total_paise > 0),
  payment_mode        text not null check (payment_mode in ('cash', 'upi', 'bank', 'credit')),
  money_account_id    int references money_accounts(id),
  reference           text,
  status              text not null default 'posted' check (status in ('awaiting_approval', 'posted', 'refused', 'reversed')),
  paid_paise          bigint not null default 0,
  outstanding_paise   bigint not null default 0,
  journal_id          bigint references journals(id) on delete set null,
  reversal_journal_id bigint references journals(id) on delete set null,
  approval_needed     boolean not null default false,
  approved_by         uuid references app_users(id),
  approved_at         timestamptz,
  refused_reason      text,
  reverse_reason      text,
  entered_by          uuid references app_users(id),
  entered_at          timestamptz not null default now(),
  updated_at          timestamptz,
  updated_by          uuid,
  is_demo             boolean not null default false,
  is_training         boolean not null default false,
  check (payment_mode = 'credit' or money_account_id is not null),
  check (payment_mode <> 'credit' or supplier_id is not null)
);
create index if not exists expenses_date_idx on expenses (expense_date);
create index if not exists expenses_supplier_idx on expenses (supplier_id) where supplier_id is not null;

-- A photo of the bill (stored small).
create table if not exists expense_photos (
  id          bigserial primary key,
  expense_id  bigint not null references expenses(id) on delete cascade,
  data_url    text not null check (data_url like 'data:image/%' and length(data_url) <= 700000),
  added_by    uuid references app_users(id),
  added_at    timestamptz not null default now(),
  is_demo     boolean not null default false,
  is_training boolean not null default false
);
create index if not exists expense_photos_expense_idx on expense_photos (expense_id);

-- Supplier payments can now also settle expense bills on credit, and can
-- be paid from a chosen bank account.
alter table payment_allocations alter column purchase_id drop not null;
alter table payment_allocations add column if not exists expense_id bigint references expenses(id) on delete cascade;
alter table supplier_payments add column if not exists money_account_id int references money_accounts(id);
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'payment_allocations_one_doc') then
    alter table payment_allocations add constraint payment_allocations_one_doc check ((purchase_id is null) <> (expense_id is null));
  end if;
end $$;
create index if not exists payment_allocations_expense_idx on payment_allocations (expense_id) where expense_id is not null;

-- Money moved between cash and bank, or between banks.
create table if not exists money_transfers (
  id                  bigserial primary key,
  transfer_no         text unique,
  transfer_date       date not null,
  from_account_id     int not null references money_accounts(id),
  to_account_id       int not null references money_accounts(id),
  amount_paise        bigint not null check (amount_paise > 0),
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
  check (from_account_id <> to_account_id)
);

-- Partners: capital brought in or taken out, and drawings.
create table if not exists partner_entries (
  id                  bigserial primary key,
  entry_no            text unique,
  kind                text not null check (kind in ('capital_in', 'capital_out', 'drawings')),
  entry_date          date not null,
  partner_id          int not null,
  money_account_id    int not null references money_accounts(id),
  amount_paise        bigint not null check (amount_paise > 0),
  reference           text,
  note                text,
  status              text not null default 'posted' check (status in ('posted', 'reversed')),
  journal_id          bigint references journals(id) on delete set null,
  reversal_journal_id bigint references journals(id) on delete set null,
  reverse_reason      text,
  entered_by          uuid references app_users(id),
  entered_at          timestamptz not null default now(),
  is_demo             boolean not null default false,
  is_training         boolean not null default false
);

-- Day-end cash counts. Any difference is posted with its reason.
create table if not exists cash_counts (
  id                  bigserial primary key,
  count_no            text unique,
  money_account_id    int not null references money_accounts(id),
  count_date          date not null,
  book_paise          bigint not null,
  counted_paise       bigint not null check (counted_paise >= 0),
  difference_paise    bigint not null,               -- counted minus book (+ excess, - shortage)
  denominations       jsonb,
  reason              text,
  status              text not null default 'posted' check (status in ('posted', 'reversed')),
  journal_id          bigint references journals(id) on delete set null,
  reversal_journal_id bigint references journals(id) on delete set null,
  reverse_reason      text,
  entered_by          uuid references app_users(id),
  entered_at          timestamptz not null default now(),
  is_demo             boolean not null default false,
  is_training         boolean not null default false
);
create index if not exists cash_counts_date_idx on cash_counts (money_account_id, count_date);

-- Bank reconciliation, month by month, per bank account.
create table if not exists bank_recons (
  id                      bigserial primary key,
  money_account_id        int not null references money_accounts(id),
  month                   date not null check (extract(day from month) = 1),
  statement_balance_paise bigint,
  book_balance_paise      bigint,
  uncleared_in_paise      bigint,
  uncleared_out_paise     bigint,
  difference_paise        bigint,
  status                  text not null default 'draft' check (status in ('draft', 'done')),
  note                    text,
  done_by                 uuid references app_users(id),
  done_at                 timestamptz,
  updated_at              timestamptz,
  updated_by              uuid,
  is_demo                 boolean not null default false,
  is_training             boolean not null default false,
  unique (money_account_id, month)
);
-- Which book entries have appeared on a bank statement, and in which month.
create table if not exists bank_clearings (
  journal_line_id bigint primary key references journal_lines(id) on delete cascade,
  recon_month     date not null,
  cleared_by      uuid,
  cleared_at      timestamptz not null default now(),
  is_demo         boolean not null default false,
  is_training     boolean not null default false
);

-- Month-end steps: labour and overheads into stock cost, and the provision for doubtful debts.
create table if not exists month_end_runs (
  id                  bigserial primary key,
  run_no              text unique,
  kind                text not null check (kind in ('absorption', 'doubtful_debts')),
  month               date not null check (extract(day from month) = 1),
  run_date            date not null,
  method              text,
  details             jsonb not null default '{}',
  amount_paise        bigint not null default 0,        -- added to stock, or change in the provision
  status              text not null default 'posted' check (status in ('posted', 'reversed')),
  journal_id          bigint references journals(id) on delete set null,
  reversal_journal_id bigint references journals(id) on delete set null,
  reverse_reason      text,
  entered_by          uuid references app_users(id),
  entered_at          timestamptz not null default now(),
  is_demo             boolean not null default false,
  is_training         boolean not null default false
);
create unique index if not exists month_end_runs_one_posted on month_end_runs (kind, month, is_demo) where status = 'posted';

-- Stock movements: a new kind for labour and overheads added at month-end.
alter table stock_moves add column if not exists month_end_run_id bigint references month_end_runs(id) on delete cascade;
alter table stock_moves drop constraint if exists stock_moves_kind_check;
alter table stock_moves add constraint stock_moves_kind_check check (kind in
  ('grn', 'bill_adjust', 'debit_note', 'purchase_return', 'reversal', 'preparation', 'production', 'wastage',
   'write_down', 'count', 'sale', 'sales_return', 'opening', 'overhead'));

-- ---------------------------------------------------------------------
-- 4. Posting rules for this module (module 2 listed the first ones)
-- ---------------------------------------------------------------------

insert into posting_rules (event_code, line_key, side, account_code, module, label, sort) values
  ('expense',        'input_gst',      'debit',  '10050105', 6, 'Input GST on an expense bill (from the GST registration date)', 125),
  ('expense',        'payable',        'credit', '30010105', 6, 'Expense on credit (per supplier)', 126),
  ('capital_in',     'capital',        'credit', '50010130', 6, 'Capital brought in by a partner (per partner)', 132),
  ('capital_out',    'capital',        'debit',  '50010130', 6, 'Capital taken out by a partner (per partner)', 133),
  ('cash_count',     'shortage',       'debit',  '80080135', 6, 'Cash short at the day-end count', 134),
  ('cash_count',     'excess',         'credit', '90010135', 6, 'Cash over at the day-end count', 135),
  ('absorption',     'stock_wip',      'debit',  '10030120', 6, 'Month-end: labour and overheads added to prepared ingredients in stock (AS 2)', 136),
  ('absorption',     'stock_finished', 'debit',  '10030125', 6, 'Month-end: labour and overheads added to finished goods in stock (AS 2)', 137),
  ('absorption',     'absorbed',       'credit', '70030140', 6, 'Month-end: labour and overheads moved into stock (AS 2)', 138),
  ('doubtful_debts', 'expense',        'debit',  '80080140', 6, 'Month-end: provision for doubtful debts charged (or written back)', 139),
  ('doubtful_debts', 'provision',      'credit', '10020225', 6, 'Month-end: provision for doubtful debts', 139)
on conflict (event_code, line_key) do nothing;
update posting_rules set label = 'Partner drawings (per partner)' where event_code = 'drawings' and line_key = 'partner_current';

-- ---------------------------------------------------------------------
-- 5. Helpers (private: used by the functions below)
-- ---------------------------------------------------------------------

-- Balance of an account from the books up to a date (debit-positive).
create or replace function rb_cb_balance(p_code text, p_as_of date)
returns bigint language sql stable security definer set search_path = public as $$
  select coalesce(sum(l.debit_paise - l.credit_paise), 0)::bigint
  from journal_lines l join journals j on j.id = l.journal_id
  where l.account_code = p_code and j.status <> 'draft' and (p_as_of is null or l.journal_date <= p_as_of)
$$;

-- The money account to use for a payment mode: the one chosen, or the
-- default cash account (cash) or default bank account (UPI, bank).
create or replace function rb_cb_money_for(p_mode text, p_id int)
returns money_accounts language plpgsql stable security definer set search_path = public as $$
declare v money_accounts; v_kind text := case when p_mode = 'cash' then 'cash' else 'bank' end;
begin
  if p_id is not null then
    select * into v from money_accounts where id = p_id;
    if v.id is null then raise exception 'That cash or bank account was not found.'; end if;
  else
    select * into v from money_accounts where kind = v_kind and is_active order by is_default desc, sort limit 1;
    if v.id is null then raise exception 'There is no active % account. Set one up in Cash, bank and expenses → Set-up.', v_kind; end if;
  end if;
  if not v.is_active then raise exception '% is switched off. Choose another account.', v.name; end if;
  if v.kind <> v_kind then
    raise exception '% is a % account, so it cannot be used for %.', v.name, v.kind,
      case p_mode when 'cash' then 'cash' when 'upi' then 'UPI' else 'bank' end;
  end if;
  return v;
end $$;

-- Number series: DEMO and training records get their own (as in module 3).
create or replace function rb_cb_no(p_base text, p_demo boolean, p_date date)
returns text language sql security definer set search_path = public as $$
  select rb_next_doc_no(rb_pur_series(p_base, p_demo), p_date)
$$;

-- The default department for an expense category.
create or replace function rb_cb_dept(p_code text)
returns int language sql stable security definer set search_path = public as $$
  select coalesce((select id from departments where code = p_code and is_active), rb_pur_default_dept())
$$;

-- Recompute what is paid and still owed on an expense bill on credit.
create or replace function rb_cb_refresh_expense(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  update expenses e set
    paid_paise = coalesce((select sum(a.amount_paise) from payment_allocations a join supplier_payments s on s.id = a.payment_id
                           where a.expense_id = e.id and s.status = 'posted'), 0)
  where e.id = p_id;
  update expenses set outstanding_paise = case when status = 'posted' and payment_mode = 'credit' then total_paise - paid_paise else 0 end
  where id = p_id;
end $$;

-- Post an expense (or other money received) to the books.
create or replace function rb_cb_post_expense(p_id bigint, p_approver uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_e expenses; v_c expense_categories; v_m money_accounts; v_lines jsonb; v_j bigint; v_who text; v_cost bigint;
begin
  select * into v_e from expenses where id = p_id for update;
  select * into v_c from expense_categories where id = v_e.category_id;
  if v_e.money_account_id is not null then select * into v_m from money_accounts where id = v_e.money_account_id; end if;
  v_who := coalesce((select name from suppliers where id = v_e.supplier_id), v_e.payee);
  v_cost := v_e.amount_paise + case when v_e.gst_claimed then 0 else v_e.gst_paise end;
  if v_e.direction = 'out' then
    v_lines := jsonb_build_array(jsonb_build_object('account_code', v_e.account_code, 'debit_paise', v_cost,
                 'narration', v_c.name || ': ' || v_e.description));
    if v_e.gst_claimed and v_e.gst_paise > 0 then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'expense.input_gst', 'amount_paise', v_e.gst_paise,
                   'narration', 'GST on ' || coalesce('bill ' || v_e.bill_no, v_e.expense_no)));
    end if;
    if v_e.payment_mode = 'credit' then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'expense.payable', 'amount_paise', v_e.total_paise,
                   'supplier_id', v_e.supplier_id, 'narration', coalesce('Bill ' || v_e.bill_no, v_e.expense_no)));
    else
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('account_code', v_m.account_code, 'credit_paise', v_e.total_paise));
    end if;
  else
    v_lines := jsonb_build_array(
      jsonb_build_object('account_code', v_m.account_code, 'debit_paise', v_e.total_paise),
      jsonb_build_object('account_code', v_e.account_code, 'credit_paise', v_e.total_paise, 'narration', v_c.name || ': ' || v_e.description));
  end if;
  v_j := rb_post_engine(jsonb_build_object('journal_date', v_e.expense_date, 'source', 'cash_bank',
    'event_code', case when v_e.direction = 'out' then 'expense' else 'other_income' end, 'source_ref', v_e.expense_no,
    'narration', v_c.name || ': ' || v_e.description || coalesce(' (' || v_who || ')', '') ||
      case v_e.payment_mode when 'credit' then ', on credit' when 'cash' then ', cash' when 'upi' then ', UPI' else ', bank' end,
    'department_id', v_e.department_id, 'is_demo', v_e.is_demo, 'entered_by', v_e.entered_by, 'approved_by', p_approver), v_lines);
  update expenses set status = 'posted', journal_id = v_j,
    approved_by = case when approval_needed then p_approver end, approved_at = case when approval_needed then now() end
  where id = p_id;
  perform rb_cb_refresh_expense(p_id);
end $$;

-- Save an expense (or other money received). A new one is numbered at
-- once; it posts straight away unless it is above the approval limit.
-- p: id (to change one waiting for approval), category_id, expense_date, department_id, supplier_id, payee,
--    description, bill_no, bill_date, amount_paise (before GST), gst_paise, payment_mode, money_account_id,
--    reference, photo (data URL)
create or replace function rb_cb_save_expense(p jsonb, p_actor uuid, p_demo boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint := rb_int(p, 'id'); v_old expenses; v_c expense_categories; v_date date := (p->>'expense_date')::date;
        v_dept int; v_sup int := rb_int(p, 'supplier_id'); v_amt bigint := rb_int(p, 'amount_paise');
        v_gst bigint := coalesce(rb_int(p, 'gst_paise'), 0); v_mode text := coalesce(rb_txt(p, 'payment_mode'), 'cash');
        v_m money_accounts; v_claim boolean; v_total bigint; v_limit bigint; v_needs boolean; v_bill_date date := (p->>'bill_date')::date;
begin
  if v_id is not null then
    select * into v_old from expenses where id = v_id for update;
    if v_old.id is null then raise exception 'Expense not found.'; end if;
    if v_old.status <> 'awaiting_approval' then raise exception 'Only an entry waiting for approval can be changed. Reverse a posted one instead.'; end if;
    if v_old.entered_by is distinct from p_actor and not rb_user_has(p_actor, 'cash_bank.edit') then
      raise exception 'Only the person who entered it (or someone with Cash, bank and expenses → Edit) can change it.';
    end if;
    p_demo := v_old.is_demo;
  end if;
  select * into v_c from expense_categories where id = rb_int(p, 'category_id');
  if v_c.id is null then raise exception 'Please choose what it was for (the category).'; end if;
  if not v_c.is_active and (v_old.id is null or v_old.category_id <> v_c.id) then raise exception '"%" is switched off. Choose another category.', v_c.name; end if;
  if v_date is null then raise exception 'Please choose the date.'; end if;
  perform rb_assert_period_open(v_date);
  if rb_txt(p, 'description') is null then raise exception 'Please say what it was for (a short note), for example "Gas, 2 cylinders".'; end if;
  if coalesce(v_amt, 0) <= 0 then raise exception 'Please enter the amount.'; end if;
  if v_gst < 0 then raise exception 'GST cannot be negative.'; end if;
  if v_c.direction = 'in' and v_gst > 0 then raise exception 'Other money received carries no GST here. Goods sold go through Sales.'; end if;
  if v_mode not in ('cash', 'upi', 'bank', 'credit') then raise exception 'Choose how it was paid: cash, UPI, bank or credit.'; end if;
  if v_mode = 'credit' and v_c.direction = 'in' then raise exception 'Money received cannot be on credit.'; end if;
  if v_mode = 'credit' and v_sup is null then
    raise exception 'An expense on credit needs the supplier, so it stays open in their balance until paid. Add the supplier if they are new.';
  end if;
  if v_sup is not null and not exists (select 1 from suppliers where id = v_sup) then raise exception 'Supplier not found.'; end if;
  if v_mode <> 'credit' then v_m := rb_cb_money_for(v_mode, rb_int(p, 'money_account_id')::int); end if;
  v_dept := coalesce(rb_int(p, 'department_id')::int, rb_cb_dept(v_c.default_department_code));
  if not exists (select 1 from departments where id = v_dept and is_active) then
    raise exception 'That department is closed or merged. Choose an open one.';
  end if;
  v_claim := v_c.direction = 'out' and v_gst > 0 and rb_pur_gst_claimable(coalesce(v_bill_date, v_date));
  v_total := v_amt + v_gst;
  select expense_approval_limit_paise into v_limit from app_settings where id = 1;
  v_needs := v_c.direction = 'out' and v_limit is not null and v_total > v_limit;
  if v_id is null then
    insert into expenses (expense_no, direction, expense_date, category_id, account_code, department_id, supplier_id, payee,
                          description, bill_no, bill_date, amount_paise, gst_paise, gst_claimed, total_paise, payment_mode,
                          money_account_id, reference, status, approval_needed, entered_by, is_demo, is_training)
    values (rb_cb_no(case when v_c.direction = 'out' then 'EXP' else 'OIN' end, p_demo, v_date), v_c.direction, v_date, v_c.id,
            v_c.account_code, v_dept, v_sup, rb_txt(p, 'payee'), rb_txt(p, 'description'), rb_txt(p, 'bill_no'), v_bill_date,
            v_amt, v_gst, v_claim, v_total, v_mode, v_m.id, rb_txt(p, 'reference'),
            case when v_needs then 'awaiting_approval' else 'posted' end, v_needs, p_actor, p_demo, rb_is_training())
    returning id into v_id;
  else
    if v_c.direction <> v_old.direction then raise exception 'An expense cannot be changed into money received (or back). Refuse it and enter it again.'; end if;
    update expenses set expense_date = v_date, category_id = v_c.id, account_code = v_c.account_code, department_id = v_dept,
      supplier_id = v_sup, payee = rb_txt(p, 'payee'), description = rb_txt(p, 'description'), bill_no = rb_txt(p, 'bill_no'),
      bill_date = v_bill_date, amount_paise = v_amt, gst_paise = v_gst, gst_claimed = v_claim, total_paise = v_total,
      payment_mode = v_mode, money_account_id = v_m.id, reference = rb_txt(p, 'reference'),
      status = case when v_needs then 'awaiting_approval' else 'posted' end, approval_needed = v_needs,
      updated_at = now(), updated_by = p_actor
    where id = v_id;
  end if;
  if rb_txt(p, 'photo') is not null then
    insert into expense_photos (expense_id, data_url, added_by, is_demo, is_training)
    values (v_id, p->>'photo', p_actor, p_demo, rb_is_training());
  end if;
  if not v_needs then perform rb_cb_post_expense(v_id, p_actor); end if;
  perform rb_audit_write(case when v_old.id is null then 'EXPENSE' else 'EXPENSE_CHANGED' end, 'expenses', v_id::text,
    case when v_old.id is not null then to_jsonb(v_old) end,
    jsonb_build_object('expense_no', (select expense_no from expenses where id = v_id), 'category', v_c.name, 'total_paise', v_total,
                       'mode', v_mode, 'waiting_for_approval', v_needs), null);
  return v_id;
end $$;

-- A transfer between two money accounts.
create or replace function rb_cb_transfer(p jsonb, p_actor uuid, p_demo boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_date date := (p->>'transfer_date')::date; v_amt bigint := rb_int(p, 'amount_paise');
        v_f money_accounts; v_t money_accounts; v_no text; v_j bigint;
begin
  select * into v_f from money_accounts where id = rb_int(p, 'from_account_id');
  select * into v_t from money_accounts where id = rb_int(p, 'to_account_id');
  if v_f.id is null or v_t.id is null then raise exception 'Choose where the money came from and where it went.'; end if;
  if v_f.id = v_t.id then raise exception 'The two accounts must be different.'; end if;
  if not v_f.is_active or not v_t.is_active then raise exception 'One of the accounts is switched off.'; end if;
  if v_date is null then raise exception 'Please choose the date.'; end if;
  if coalesce(v_amt, 0) <= 0 then raise exception 'Please enter the amount.'; end if;
  perform rb_assert_period_open(v_date);
  v_no := rb_cb_no('CTR', p_demo, v_date);
  insert into money_transfers (transfer_no, transfer_date, from_account_id, to_account_id, amount_paise, reference, note,
                               entered_by, is_demo, is_training)
  values (v_no, v_date, v_f.id, v_t.id, v_amt, rb_txt(p, 'reference'), rb_txt(p, 'note'), p_actor, p_demo, rb_is_training())
  returning id into v_id;
  v_j := rb_post_engine(jsonb_build_object('journal_date', v_date, 'source', 'cash_bank', 'event_code', 'transfer', 'source_ref', v_no,
    'narration', case when v_f.kind = 'cash' and v_t.kind = 'bank' then 'Cash paid into ' || v_t.name
                      when v_f.kind = 'bank' and v_t.kind = 'cash' then 'Cash drawn from ' || v_f.name
                      else 'Moved from ' || v_f.name || ' to ' || v_t.name end || coalesce(' (' || rb_txt(p, 'note') || ')', ''),
    'department_id', rb_cb_dept('CC005'), 'is_demo', p_demo, 'entered_by', p_actor, 'approved_by', p_actor),
    jsonb_build_array(jsonb_build_object('account_code', v_t.account_code, 'debit_paise', v_amt),
                      jsonb_build_object('account_code', v_f.account_code, 'credit_paise', v_amt)));
  update money_transfers set journal_id = v_j where id = v_id;
  perform rb_audit_write('TRANSFER', 'money_transfers', v_id::text, null,
    jsonb_build_object('transfer_no', v_no, 'from', v_f.name, 'to', v_t.name, 'amount_paise', v_amt), null);
  return v_id;
end $$;

-- A partner brings capital in, takes capital out, or draws money.
create or replace function rb_cb_partner(p jsonb, p_actor uuid, p_demo boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_kind text := rb_txt(p, 'kind'); v_date date := (p->>'entry_date')::date; v_amt bigint := rb_int(p, 'amount_paise');
        v_pid int := rb_int(p, 'partner_id'); v_pname text; v_m money_accounts; v_no text; v_j bigint; v_lines jsonb;
begin
  if v_kind not in ('capital_in', 'capital_out', 'drawings') then raise exception 'Choose capital brought in, capital taken out, or drawings.'; end if;
  v_pname := rb_partner_name(v_pid);
  if v_pname is null then raise exception 'Please choose the partner.'; end if;
  if v_date is null then raise exception 'Please choose the date.'; end if;
  if coalesce(v_amt, 0) <= 0 then raise exception 'Please enter the amount.'; end if;
  select * into v_m from money_accounts where id = rb_int(p, 'money_account_id');
  if v_m.id is null then raise exception 'Choose the cash or bank account the money went into or came from.'; end if;
  if not v_m.is_active then raise exception '% is switched off.', v_m.name; end if;
  perform rb_assert_period_open(v_date);
  v_no := rb_cb_no('PTR', p_demo, v_date);
  insert into partner_entries (entry_no, kind, entry_date, partner_id, money_account_id, amount_paise, reference, note,
                               entered_by, is_demo, is_training)
  values (v_no, v_kind, v_date, v_pid, v_m.id, v_amt, rb_txt(p, 'reference'), rb_txt(p, 'note'), p_actor, p_demo, rb_is_training())
  returning id into v_id;
  v_lines := case v_kind
    when 'capital_in' then jsonb_build_array(
      jsonb_build_object('account_code', v_m.account_code, 'debit_paise', v_amt),
      jsonb_build_object('rule', 'capital_in.capital', 'amount_paise', v_amt, 'partner_id', v_pid))
    when 'capital_out' then jsonb_build_array(
      jsonb_build_object('rule', 'capital_out.capital', 'amount_paise', v_amt, 'partner_id', v_pid),
      jsonb_build_object('account_code', v_m.account_code, 'credit_paise', v_amt))
    else jsonb_build_array(
      jsonb_build_object('rule', 'drawings.partner_current', 'amount_paise', v_amt, 'partner_id', v_pid),
      jsonb_build_object('account_code', v_m.account_code, 'credit_paise', v_amt)) end;
  v_j := rb_post_engine(jsonb_build_object('journal_date', v_date, 'source', 'cash_bank', 'event_code', v_kind, 'source_ref', v_no,
    'narration', case v_kind when 'capital_in' then 'Capital brought in by ' when 'capital_out' then 'Capital taken out by '
                 else 'Drawings by ' end || v_pname || ', ' || v_m.name || coalesce(' (' || rb_txt(p, 'note') || ')', ''),
    'department_id', rb_cb_dept('CC005'), 'is_demo', p_demo, 'entered_by', p_actor, 'approved_by', p_actor), v_lines);
  update partner_entries set journal_id = v_j where id = v_id;
  perform rb_audit_write('PARTNER_ENTRY', 'partner_entries', v_id::text, null,
    jsonb_build_object('entry_no', v_no, 'kind', v_kind, 'partner', v_pname, 'amount_paise', v_amt), null);
  return v_id;
end $$;

-- A day-end cash count. The book balance is worked out here; any
-- difference is posted at once, with its reason.
create or replace function rb_cb_count(p jsonb, p_actor uuid, p_demo boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_m money_accounts; v_date date := (p->>'count_date')::date; v_counted bigint := rb_int(p, 'counted_paise');
        v_book bigint; v_diff bigint; v_no text; v_j bigint;
begin
  select * into v_m from money_accounts where id = rb_int(p, 'money_account_id');
  if v_m.id is null or v_m.kind <> 'cash' then raise exception 'Choose the cash account that was counted.'; end if;
  if v_date is null then raise exception 'Please choose the date of the count.'; end if;
  if v_counted is null or v_counted < 0 then raise exception 'Please enter the cash counted.'; end if;
  perform rb_assert_period_open(v_date);
  if exists (select 1 from cash_counts where money_account_id = v_m.id and count_date = v_date and status = 'posted' and is_demo = p_demo) then
    raise exception '% was already counted on %. Reverse that count first if it was wrong.', v_m.name, to_char(v_date, 'DD-Mon-YYYY');
  end if;
  v_book := rb_cb_balance(v_m.account_code, v_date);
  v_diff := v_counted - v_book;
  if v_diff <> 0 and rb_txt(p, 'reason') is null then
    raise exception 'The cash counted is % %. Please give the reason (for example "change given short").',
      rb_pur_fmt(abs(v_diff)), case when v_diff < 0 then 'less than the book' else 'more than the book' end;
  end if;
  v_no := rb_cb_no('CNT', p_demo, v_date);
  insert into cash_counts (count_no, money_account_id, count_date, book_paise, counted_paise, difference_paise, denominations,
                           reason, entered_by, is_demo, is_training)
  values (v_no, v_m.id, v_date, v_book, v_counted, v_diff, p->'denominations', rb_txt(p, 'reason'), p_actor, p_demo, rb_is_training())
  returning id into v_id;
  if v_diff <> 0 then
    v_j := rb_post_engine(jsonb_build_object('journal_date', v_date, 'source', 'cash_bank', 'event_code', 'cash_count', 'source_ref', v_no,
      'narration', 'Cash ' || case when v_diff < 0 then 'short' else 'over' end || ' at the count of ' || v_m.name || ': ' || rb_txt(p, 'reason'),
      'department_id', rb_cb_dept('CC002'), 'is_demo', p_demo, 'entered_by', p_actor, 'approved_by', p_actor),
      case when v_diff < 0 then jsonb_build_array(
        jsonb_build_object('rule', 'cash_count.shortage', 'amount_paise', -v_diff),
        jsonb_build_object('account_code', v_m.account_code, 'credit_paise', -v_diff))
      else jsonb_build_array(
        jsonb_build_object('account_code', v_m.account_code, 'debit_paise', v_diff),
        jsonb_build_object('rule', 'cash_count.excess', 'amount_paise', v_diff)) end);
    update cash_counts set journal_id = v_j where id = v_id;
  end if;
  perform rb_audit_write('CASH_COUNT', 'cash_counts', v_id::text, null,
    jsonb_build_object('count_no', v_no, 'account', v_m.name, 'book_paise', v_book, 'counted_paise', v_counted), rb_txt(p, 'reason'));
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- 6. Supplier payments (module 3) now also settle expense bills on
--    credit, and can name the bank account they were paid from.
--    These replace module 3's versions; everything else is unchanged.
-- ---------------------------------------------------------------------

-- Set one allocation of a payment against a purchase or an expense bill.
create or replace function rb_cb_allocate_one(p_payment bigint, p_supplier int, a jsonb, p_demo boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_pur purchases; v_e expenses; v_amt bigint := coalesce(rb_int(a, 'amount_paise'), 0);
begin
  if v_amt = 0 then return 0; end if;
  if v_amt < 0 then raise exception 'Amounts cannot be negative.'; end if;
  if rb_int(a, 'expense_id') is not null then
    select * into v_e from expenses where id = rb_int(a, 'expense_id') for update;
    if v_e.id is null or v_e.supplier_id is distinct from p_supplier then raise exception 'That expense bill is not from this supplier.'; end if;
    if v_e.status <> 'posted' or v_e.payment_mode <> 'credit' then raise exception '% is not an unpaid bill on credit.', v_e.expense_no; end if;
    if v_amt > v_e.outstanding_paise then
      raise exception '% only has % left to pay.', v_e.expense_no, rb_pur_fmt(v_e.outstanding_paise);
    end if;
    insert into payment_allocations (payment_id, expense_id, amount_paise, is_demo, is_training)
    values (p_payment, v_e.id, v_amt, p_demo, rb_is_training());
    perform rb_cb_refresh_expense(v_e.id);
    return v_amt;
  end if;
  select * into v_pur from purchases where id = rb_int(a, 'purchase_id') for update;
  if v_pur.id is null or v_pur.supplier_id <> p_supplier then raise exception 'That purchase is not from this supplier.'; end if;
  if v_pur.bill_posted_at is null then
    raise exception '% has no supplier bill yet, so it cannot be paid.', rb_pur_label(v_pur);
  end if;
  if v_pur.open_discrepancies > 0 then
    raise exception '% has % difference(s) to settle first (spec: a purchase with an unsettled difference cannot be paid).',
      rb_pur_label(v_pur), v_pur.open_discrepancies;
  end if;
  if v_amt > v_pur.outstanding_paise then
    raise exception '% only has % left to pay.', rb_pur_label(v_pur), rb_pur_fmt(v_pur.outstanding_paise);
  end if;
  insert into payment_allocations (payment_id, purchase_id, amount_paise, is_demo, is_training)
  values (p_payment, v_pur.id, v_amt, p_demo, rb_is_training());
  perform rb_pur_refresh(v_pur.id);
  return v_amt;
end $$;

-- A payment, with its allocations. Private: callers check rights first.
-- p: supplier_id, pay_date, mode, amount_paise, reference, note, department_id,
--    money_account_id (optional: which cash or bank account), allocations [{purchase_id | expense_id, amount_paise}]
create or replace function rb_pur_pay(p jsonb, p_actor uuid, p_demo boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_sup int := rb_int(p, 'supplier_id'); v_date date := (p->>'pay_date')::date;
        v_mode text := coalesce(rb_txt(p, 'mode'), 'cash'); v_amt bigint := rb_int(p, 'amount_paise');
        a jsonb; v_alloc bigint := 0; v_no text; v_j bigint; v_sup_name text; v_dept int; v_m money_accounts;
begin
  if v_sup is null then raise exception 'Please choose the supplier.'; end if;
  select name into v_sup_name from suppliers where id = v_sup;
  if v_sup_name is null then raise exception 'Supplier not found.'; end if;
  if v_date is null then raise exception 'Please choose the payment date.'; end if;
  if v_mode not in ('cash', 'upi', 'bank') then raise exception 'Choose how it was paid: cash, UPI or bank.'; end if;
  if coalesce(v_amt, 0) <= 0 then raise exception 'Please enter the amount paid.'; end if;
  perform rb_assert_period_open(v_date);
  -- The account chosen, or the main cash or bank account.
  v_m := rb_cb_money_for(v_mode, rb_int(p, 'money_account_id')::int);
  v_dept := coalesce(rb_int(p, 'department_id')::int, rb_pur_default_dept());
  v_no := rb_next_doc_no(rb_pur_series('PAY', p_demo), v_date);
  insert into supplier_payments (payment_no, supplier_id, pay_date, mode, amount_paise, reference, note, department_id,
                                 money_account_id, entered_by, is_demo, is_training)
  values (v_no, v_sup, v_date, v_mode, v_amt, rb_txt(p, 'reference'), rb_txt(p, 'note'), v_dept, v_m.id, p_actor, p_demo, rb_is_training())
  returning id into v_id;
  for a in select * from jsonb_array_elements(coalesce(p->'allocations', '[]')) loop
    v_alloc := v_alloc + rb_cb_allocate_one(v_id, v_sup, a, p_demo);
  end loop;
  if v_alloc > v_amt then raise exception 'The amounts set against bills (%) are more than the payment (%).', rb_pur_fmt(v_alloc), rb_pur_fmt(v_amt); end if;
  v_j := rb_post_engine(jsonb_build_object('journal_date', v_date, 'source', 'purchases', 'event_code', 'supplier_payment',
    'source_ref', v_no, 'narration', 'Paid ' || v_sup_name || ' by ' || upper(v_mode) || coalesce(', ref ' || rb_txt(p, 'reference'), '') ||
      case when v_alloc < v_amt then ' (' || rb_pur_fmt(v_amt - v_alloc) || ' on account)' else '' end,
    'department_id', v_dept, 'is_demo', p_demo, 'entered_by', p_actor, 'approved_by', p_actor),
    jsonb_build_array(
      jsonb_build_object('rule', 'supplier_payment.payable', 'amount_paise', v_amt, 'supplier_id', v_sup),
      case when v_m.id is not null then jsonb_build_object('account_code', v_m.account_code, 'credit_paise', v_amt)
           else jsonb_build_object('rule', 'supplier_payment.' || case when v_mode = 'cash' then 'cash' else 'bank' end, 'amount_paise', v_amt) end));
  update supplier_payments set journal_id = v_j where id = v_id;
  perform rb_audit_write('SUPPLIER_PAYMENT', 'supplier_payments', v_id::text, null,
    jsonb_build_object('payment_no', v_no, 'supplier', v_sup_name, 'amount_paise', v_amt, 'mode', v_mode, 'allocated_paise', v_alloc), null);
  return v_id;
end $$;

-- Set an amount paid on account (an advance) against bills later:
-- purchases or expense bills on credit.
create or replace function rb_allocate_payment(p_payment bigint, p_allocations jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_current_user_id(); v_s supplier_payments; a jsonb; v_left bigint; v_done bigint;
begin
  if v_me is null then raise exception 'You are not signed in, or your account is locked or switched off.'; end if;
  if not (rb_has('purchases.add') or rb_has('cash_bank.add')) then raise exception 'You do not have the right to allocate payments.'; end if;
  select * into v_s from supplier_payments where id = p_payment for update;
  if v_s.id is null or v_s.status <> 'posted' then raise exception 'Payment not found.'; end if;
  v_left := v_s.amount_paise - coalesce((select sum(amount_paise) from payment_allocations where payment_id = p_payment), 0);
  for a in select * from jsonb_array_elements(coalesce(p_allocations, '[]')) loop
    if coalesce(rb_int(a, 'amount_paise'), 0) > v_left then raise exception 'Only % of this payment is left to set against bills.', rb_pur_fmt(v_left); end if;
    v_done := rb_cb_allocate_one(p_payment, v_s.supplier_id, a, v_s.is_demo);
    v_left := v_left - v_done;
  end loop;
  perform rb_audit_write('ALLOCATE_PAYMENT', 'supplier_payments', p_payment::text, null, p_allocations, null);
end $$;

create or replace function rb_reverse_supplier_payment(p_id bigint, p_date date, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.reverse_entries', 'reverse posted entries'); v_s supplier_payments; v_rev bigint; v_pid bigint;
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason for the reversal.'; end if;
  select * into v_s from supplier_payments where id = p_id for update;
  if v_s.id is null or v_s.status <> 'posted' then raise exception 'Only a posted payment can be reversed.'; end if;
  perform set_config('rb.purchases', 'on', true);
  v_rev := rb_reverse_journal(v_s.journal_id, p_date, 'Payment ' || v_s.payment_no || ' reversed: ' || trim(p_reason));
  perform set_config('rb.purchases', 'off', true);
  update supplier_payments set status = 'reversed', reversal_journal_id = v_rev, reverse_reason = trim(p_reason) where id = p_id;
  for v_pid in select distinct purchase_id from payment_allocations where payment_id = p_id and purchase_id is not null loop
    perform rb_pur_refresh(v_pid);
  end loop;
  for v_pid in select distinct expense_id from payment_allocations where payment_id = p_id and expense_id is not null loop
    perform rb_cb_refresh_expense(v_pid);
  end loop;
  perform rb_audit_write('REVERSE_PAYMENT', 'supplier_payments', p_id::text, null, jsonb_build_object('payment_no', v_s.payment_no), trim(p_reason));
end $$;

create or replace function rb_hard_delete_supplier_payment(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_current_user_id(); v_s supplier_payments; v_pid bigint;
begin
  if v_me is null then raise exception 'You are not signed in, or your account is locked or switched off.'; end if;
  select * into v_s from supplier_payments where id = p_id for update;
  if v_s.id is null then raise exception 'Payment not found.'; end if;
  if not (rb_can_hard_delete('purchases', v_s.entered_by) or rb_can_hard_delete('cash_bank', v_s.entered_by)) then
    raise exception 'Only payments entered by someone still in their learning phase can be fully deleted. Reverse it instead.';
  end if;
  if v_s.status <> 'posted' then raise exception 'This payment has been reversed. Reversed entries are kept.'; end if;
  perform rb_assert_period_open(v_s.pay_date);
  perform set_config('rb.ledger', 'on', true);
  perform set_config('rb.purchases', 'on', true);
  delete from supplier_payments where id = p_id;
  delete from journals where id = v_s.journal_id;
  perform set_config('rb.purchases', 'off', true);
  perform set_config('rb.ledger', 'off', true);
  for v_pid in select id from purchases where supplier_id = v_s.supplier_id and bill_posted_at is not null loop
    perform rb_pur_refresh(v_pid);
  end loop;
  for v_pid in select id from expenses where supplier_id = v_s.supplier_id and payment_mode = 'credit' loop
    perform rb_cb_refresh_expense(v_pid);
  end loop;
end $$;

-- What each supplier is owed (credit balance) on a date, from the books.
-- Open bills and overdue amounts now count expense bills on credit too.
create or replace function rb_supplier_balances(p_as_of date default current_date, p_include_demo boolean default true)
returns table (supplier_id int, code text, name text, kind text, billed_paise bigint, paid_paise bigint, balance_paise bigint,
               open_bills int, oldest_bill date, oldest_days int, credit_days int, overdue_paise bigint, is_demo boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (rb_has('purchases.view') or rb_has('suppliers.view') or rb_has('accounts.view') or rb_has('cash_bank.view')) then
    raise exception 'You do not have the right to see supplier balances.';
  end if;
  return query
  with ap as (
    select l.supplier_id sid, sum(l.credit_paise)::bigint cr, sum(l.debit_paise)::bigint dr
    from journal_lines l join journals j on j.id = l.journal_id join accounts a on a.code = l.account_code
    where a.control_type = 'supplier' and j.status <> 'draft' and l.journal_date <= p_as_of
      and (p_include_demo or not l.is_demo)
    group by l.supplier_id),
  bills as (
    select p.supplier_id sid, coalesce(p.bill_date, p.purchase_date) d, p.outstanding_paise o
    from purchases p where p.outstanding_paise > 0 and p.status in ('billed') and (p_include_demo or not p.is_demo)
    union all
    select e.supplier_id, coalesce(e.bill_date, e.expense_date), e.outstanding_paise
    from expenses e where e.outstanding_paise > 0 and e.status = 'posted' and (p_include_demo or not e.is_demo)),
  ob as (
    select b.sid, count(*)::int n, min(b.d) d,
           sum(case when b.d + coalesce(s2.credit_days, 0) < p_as_of then b.o else 0 end)::bigint od
    from bills b join suppliers s2 on s2.id = b.sid
    group by b.sid)
  select s.id, s.code, s.name, s.kind, coalesce(ap.cr, 0), coalesce(ap.dr, 0), coalesce(ap.cr, 0) - coalesce(ap.dr, 0),
         coalesce(ob.n, 0), ob.d, (p_as_of - ob.d)::int, s.credit_days, coalesce(ob.od, 0), s.is_demo
  from suppliers s left join ap on ap.sid = s.id left join ob on ob.sid = s.id
  where ap.sid is not null or ob.sid is not null
  order by coalesce(ap.cr, 0) - coalesce(ap.dr, 0) desc, s.name;
end $$;

-- ---------------------------------------------------------------------
-- 7. Month-end step 1: labour and overheads into stock cost (AS 2)
-- ---------------------------------------------------------------------

-- Work out how the month's labour and production overheads are shared.
--  * The pool: the month's net amount on each account in absorption_accounts.
--  * Normal capacity (AS 2 para 9): when a normal monthly output is set and
--    the month made less, fixed overheads are absorbed only in proportion;
--    the rest stays an expense.
--  * Each batch of the month gets a share by the method (kg produced,
--    number of batches, hours worked, value of materials).
--  * A preparation batch's share follows its prepared ingredient: the part
--    used in this month's production batches moves to them; the part still
--    in stock at month-end is added to that preparation batch's stock.
--  * A production batch's share (with what it took over) is spread over
--    what it made by weight; for each product and pack, the part that is
--    still in stock at month-end is added to stock (the latest batches are
--    taken to be the ones still on the shelf). The part that belongs to
--    goods already sold or used stays in profit and loss.
-- p_strict: stop with a message when the method cannot be used (posting);
-- otherwise return null for it (the side-by-side preview).
create or replace function rb_cb_absorb_calc(p_month date, p_method text, p_hours jsonb, p_demo boolean, p_strict boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_m date := date_trunc('month', p_month)::date; v_end date; v_fixed numeric; v_var numeric; v_norm numeric;
        v_kg numeric; v_fixed_abs numeric; v_abs numeric; v_basis numeric; r record; c record; v_h numeric; v_cap bigint;
        v_wip jsonb := '[]'; v_prod jsonb := '[]'; v_total bigint := 0; v_missing int; v_pool jsonb;
begin
  if p_method not in ('kg', 'batches', 'hours', 'material') then raise exception 'Unknown sharing method %.', p_method; end if;
  v_end := (v_m + interval '1 month - 1 day')::date;
  select normal_output_kg into v_norm from app_settings where id = 1;
  -- The pool, account by account.
  select coalesce(jsonb_agg(jsonb_build_object('code', x.code, 'name', x.name, 'behaviour', x.behaviour, 'amount_paise', x.amt)
                            order by x.code), '[]'),
         coalesce(sum(x.amt) filter (where x.behaviour = 'fixed'), 0), coalesce(sum(x.amt) filter (where x.behaviour = 'variable'), 0)
  into v_pool, v_fixed, v_var
  from (select a.account_code code, coalesce(acc.local_name, acc.name) name, a.behaviour,
               coalesce((select sum(l.debit_paise - l.credit_paise) from journal_lines l join journals j on j.id = l.journal_id
                         where l.account_code = a.account_code and j.status <> 'draft' and l.is_demo = p_demo
                           and l.journal_date between v_m and v_end), 0)::bigint amt
        from absorption_accounts a join accounts acc on acc.code = a.account_code) x;

  drop table if exists pg_temp.t_ab_batch;
  create temp table t_ab_batch (id bigint primary key, kind text, batch_no text, batch_date date, item_id int, item text,
    out_qty numeric, kg numeric, material bigint, hours numeric, basis numeric, share numeric default 0,
    transferred numeric default 0) on commit drop;
  insert into t_ab_batch (id, kind, batch_no, batch_date, item_id, item, out_qty, kg, material, hours)
  select b.id, b.kind, b.batch_no, b.batch_date, b.output_item_id, i.name, b.output_qty_base,
         case when u.dimension in ('mass', 'volume') then b.output_qty_base / 1000 else b.output_qty_base end,
         b.input_value_paise, nullif(trim(coalesce(p_hours, '{}') ->> b.id::text), '')::numeric
  from production_batches b join items i on i.id = b.output_item_id join units u on u.code = i.base_unit
  where b.status = 'posted' and b.is_demo = p_demo and b.batch_date between v_m and v_end;
  select coalesce(sum(kg), 0) into v_kg from t_ab_batch where kind = 'production';

  if p_method = 'hours' then
    select count(*) into v_missing from t_ab_batch where hours is null or hours <= 0;
    if v_missing > 0 then
      if p_strict then raise exception 'Enter the hours worked for every batch (% missing).', v_missing; end if;
      return null;
    end if;
  end if;
  update t_ab_batch set basis = case p_method when 'kg' then kg when 'batches' then 1 when 'hours' then hours else material end;
  select coalesce(sum(basis), 0) into v_basis from t_ab_batch;

  -- Normal capacity for fixed overheads.
  v_fixed_abs := case when v_norm is not null and v_kg < v_norm then v_fixed * v_kg / v_norm else v_fixed end;
  v_abs := greatest(v_var + v_fixed_abs, 0);
  if v_basis > 0 then update t_ab_batch set share = v_abs * basis / v_basis; end if;

  -- Preparation batches: pass on what was used, keep what is still in stock.
  for r in select * from t_ab_batch where kind = 'preparation' and share > 0 and out_qty > 0 order by batch_date, id loop
    for c in select l.batch_id, sum(l.qty_base) q from batch_lines l join t_ab_batch b on b.id = l.batch_id
             where l.role = 'input' and l.lot_batch_id = r.id and b.kind = 'production' group by l.batch_id loop
      update t_ab_batch set transferred = transferred + r.share * c.q / r.out_qty where id = c.batch_id;
    end loop;
    v_h := greatest((rb_stk_bal(r.item_id, null, r.id, v_end)).qty, 0);
    v_cap := round(r.share * least(v_h, r.out_qty) / r.out_qty)::bigint;
    v_total := v_total + v_cap;
    v_wip := v_wip || jsonb_build_array(jsonb_build_object('lot_batch_id', r.id, 'batch_no', r.batch_no, 'item_id', r.item_id,
      'label', r.item, 'made', r.out_qty, 'on_hand', v_h, 'share_paise', round(r.share)::bigint,
      'used_paise', round(r.share * least(r.out_qty - least(v_h, r.out_qty), r.out_qty) / r.out_qty)::bigint, 'capitalised_paise', v_cap));
  end loop;

  -- Production batches: spread over what was made; keep what is still in stock.
  for r in select x.item_id, x.pack_id, sum(x.q) made, sum(x.absorbed) absorbed
           from (select l.item_id, l.pack_id, l.qty_base q,
                        (b.share + b.transferred) * l.qty_base / nullif(sum(l.qty_base) over (partition by l.batch_id), 0) absorbed
                 from batch_lines l join t_ab_batch b on b.id = l.batch_id
                 where b.kind = 'production' and l.role = 'output') x
           group by x.item_id, x.pack_id order by x.item_id, x.pack_id loop
    v_h := greatest((rb_stk_bal(r.item_id, r.pack_id, null, v_end)).qty, 0);
    v_cap := case when r.made > 0 then round(coalesce(r.absorbed, 0) * least(v_h, r.made) / r.made)::bigint else 0 end;
    v_total := v_total + v_cap;
    v_prod := v_prod || jsonb_build_array(jsonb_build_object('item_id', r.item_id, 'pack_id', r.pack_id,
      'label', rb_stk_label(r.item_id, r.pack_id), 'unit', (select base_unit from items where id = r.item_id),
      'made', r.made, 'on_hand', v_h, 'absorbed_paise', round(coalesce(r.absorbed, 0))::bigint, 'capitalised_paise', v_cap));
  end loop;

  return jsonb_build_object(
    'month', v_m, 'month_end', v_end, 'method', p_method, 'demo', p_demo,
    'pool', v_pool, 'fixed_paise', v_fixed::bigint, 'variable_paise', v_var::bigint, 'pool_paise', (v_fixed + v_var)::bigint,
    'normal_output_kg', v_norm, 'actual_output_kg', round(v_kg, 3),
    'fixed_absorbed_paise', round(v_fixed_abs)::bigint, 'under_absorbed_paise', round(v_fixed - v_fixed_abs)::bigint,
    'shared_paise', round(case when v_basis > 0 then v_abs else 0 end)::bigint,
    'batches', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'batch_no', batch_no, 'kind', kind, 'batch_date', batch_date,
                 'label', item, 'kg', round(kg, 3), 'material_paise', material, 'hours', hours, 'basis', basis,
                 'share_paise', round(share)::bigint, 'received_paise', round(transferred)::bigint) order by batch_date, id) from t_ab_batch), '[]'),
    'wip', v_wip, 'products', v_prod,
    'capitalised_paise', v_total, 'stays_in_pl_paise', (v_fixed + v_var)::bigint - v_total);
end $$;

-- Are there real (not DEMO) records for this month's batches? If not,
-- and DEMO ones exist, the month-end step works on the DEMO records.
create or replace function rb_cb_use_demo(p_month date, p_kind text)
returns boolean language sql stable security definer set search_path = public as $$
  select case when p_kind = 'absorption' then
      not exists (select 1 from production_batches where not is_demo and status = 'posted'
                  and date_trunc('month', batch_date) = date_trunc('month', p_month))
      and exists (select 1 from production_batches where is_demo and status = 'posted'
                  and date_trunc('month', batch_date) = date_trunc('month', p_month))
    else
      not exists (select 1 from sales where not is_demo and invoice_date < (date_trunc('month', p_month) + interval '1 month'))
      and not exists (select 1 from journal_lines l join accounts a on a.code = l.account_code
                      where a.control_type = 'customer' and not l.is_demo)
      and exists (select 1 from sales where is_demo and invoice_date < (date_trunc('month', p_month) + interval '1 month'))
    end
$$;

-- Post month-end step 1 with the method in Settings.
create or replace function rb_cb_post_absorption(p_month date, p_hours jsonb, p_demo boolean, p_actor uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_m date := date_trunc('month', p_month)::date; v_end date; v_method text; v_x jsonb; v_id bigint; v_no text;
        v_j bigint; v_lines jsonb := '[]'; e jsonb; v_dept int := rb_cb_dept('CC001');
begin
  if p_month is null then raise exception 'Please choose the month.'; end if;
  v_end := (v_m + interval '1 month - 1 day')::date;
  if v_end >= current_date and not p_demo then
    raise exception 'Run this once % has ended (from %).', to_char(v_m, 'Mon-YYYY'), to_char(v_end + 1, 'DD-Mon-YYYY');
  end if;
  perform rb_assert_period_open(v_end);
  if exists (select 1 from month_end_runs where kind = 'absorption' and month = v_m and status = 'posted' and is_demo = p_demo) then
    raise exception 'Labour and overheads for % are already in stock. Reverse that run first to run it again.', to_char(v_m, 'Mon-YYYY');
  end if;
  select absorption_method into v_method from app_settings where id = 1;
  v_x := rb_cb_absorb_calc(v_m, v_method, p_hours, p_demo, true);
  v_no := rb_cb_no('ME', p_demo, v_end);
  insert into month_end_runs (run_no, kind, month, run_date, method, details, amount_paise, entered_by, is_demo, is_training)
  values (v_no, 'absorption', v_m, v_end, v_method, v_x || jsonb_build_object('hours', coalesce(p_hours, '{}')),
          (v_x->>'capitalised_paise')::bigint, p_actor, p_demo, rb_is_training())
  returning id into v_id;
  for e in select * from jsonb_array_elements(v_x->'wip') loop
    if (e->>'capitalised_paise')::bigint = 0 then continue; end if;
    perform rb_stk_move(v_end, (e->>'item_id')::int, null, (e->>'lot_batch_id')::bigint, 0, (e->>'capitalised_paise')::bigint,
                        'overhead', v_no, null, null, null, v_dept, p_actor, p_demo, 'Labour and overheads for ' || to_char(v_m, 'Mon-YYYY'));
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'absorption.stock_wip', 'amount_paise', (e->>'capitalised_paise')::bigint,
      'item_id', (e->>'item_id')::int, 'narration', (e->>'label') || ', batch ' || (e->>'batch_no')));
  end loop;
  for e in select * from jsonb_array_elements(v_x->'products') loop
    if (e->>'capitalised_paise')::bigint = 0 then continue; end if;
    perform rb_stk_move(v_end, (e->>'item_id')::int, (e->>'pack_id')::int, null, 0, (e->>'capitalised_paise')::bigint,
                        'overhead', v_no, null, null, null, v_dept, p_actor, p_demo, 'Labour and overheads for ' || to_char(v_m, 'Mon-YYYY'));
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'absorption.stock_finished', 'amount_paise', (e->>'capitalised_paise')::bigint,
      'item_id', (e->>'item_id')::int, 'narration', e->>'label'));
  end loop;
  if (v_x->>'capitalised_paise')::bigint > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'absorption.absorbed', 'amount_paise', (v_x->>'capitalised_paise')::bigint,
      'narration', 'Labour and overheads in stock at ' || to_char(v_end, 'DD-Mon-YYYY')));
    v_j := rb_post_engine(jsonb_build_object('journal_date', v_end, 'source', 'cash_bank', 'event_code', 'absorption', 'source_ref', v_no,
      'narration', 'Month-end ' || to_char(v_m, 'Mon-YYYY') || ': kitchen labour and overheads added to stock still on hand (AS 2), shared by ' ||
        case v_method when 'kg' then 'kg produced' when 'batches' then 'number of batches' when 'hours' then 'hours worked' else 'value of materials' end,
      'department_id', v_dept, 'is_demo', p_demo, 'entered_by', p_actor, 'approved_by', p_actor), v_lines);
  end if;
  update month_end_runs set journal_id = v_j where id = v_id;
  update stock_moves set month_end_run_id = v_id, journal_id = v_j where doc_no = v_no and kind = 'overhead';
  perform rb_audit_write('MONTH_END_ABSORPTION', 'month_end_runs', v_id::text, null,
    jsonb_build_object('run_no', v_no, 'month', v_m, 'method', v_method, 'pool_paise', v_x->'pool_paise',
                       'capitalised_paise', v_x->'capitalised_paise'), null);
  return v_id;
end $$;

-- A batch cannot be reversed or deleted once its month's labour and
-- overheads are in stock: reverse the month-end run first.
create or replace function rb_cb_batch_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- DEMO records, and training records cleared at go-live, are not held back.
  if old.is_demo or (tg_op = 'DELETE' and old.is_training and rb_is_training()) then
    return coalesce(new, old);
  end if;
  if (tg_op = 'DELETE' or (old.status = 'posted' and new.status = 'reversed'))
     and exists (select 1 from month_end_runs where kind = 'absorption' and status = 'posted' and is_demo = old.is_demo
                 and month = date_trunc('month', old.batch_date)::date) then
    raise exception 'The labour and overheads for % are already in stock (month-end step 1). Reverse that run first (Cash, bank and expenses → Month-end), then this batch, then run the month-end step again.',
      to_char(old.batch_date, 'Mon-YYYY');
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists rb_cb_batch_guard on production_batches;
create trigger rb_cb_batch_guard before update or delete on production_batches
  for each row execute function rb_cb_batch_guard();

-- ---------------------------------------------------------------------
-- 8. Month-end step 2: provision for doubtful debts
-- ---------------------------------------------------------------------

-- Age every customer's balance at month-end and apply the CA's rates.
--  * Each invoice's balance at month-end (receipts, credit notes and
--    write-offs dated on or before it), aged by days past its due date.
--  * Money on account reduces the oldest invoices first; any balance not
--    on an invoice (opening balances, journals) uses its own rate.
create or replace function rb_cb_provision_calc(p_month date, p_demo boolean)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_m date := date_trunc('month', p_month)::date; v_end date; v_bands jsonb; v_other_pct numeric; v_n int;
        v_amt numeric[]; v_cust jsonb := '[]'; cu record; inv record; v_b bigint; v_s bigint; v_excess bigint; v_take bigint;
        v_row numeric[]; v_other bigint; v_other_total bigint := 0; v_prov numeric; v_cprov numeric; v_req bigint := 0;
        v_existing bigint; v_bands_out jsonb := '[]'; i int; v_days int; v_lo int;
begin
  v_end := (v_m + interval '1 month - 1 day')::date;
  select doubtful_debt_bands, doubtful_debt_other_pct into v_bands, v_other_pct from app_settings where id = 1;
  v_n := jsonb_array_length(v_bands);
  v_amt := array_fill(0::numeric, array[v_n]);
  for cu in
    with bal as (
      select l.customer_id cid, sum(l.debit_paise - l.credit_paise)::bigint b
      from journal_lines l join journals j on j.id = l.journal_id join accounts a on a.code = l.account_code
      where a.control_type = 'customer' and j.status <> 'draft' and l.journal_date <= v_end and l.is_demo = p_demo
      group by l.customer_id)
    select c.id, c.code, c.name, bal.b from bal join customers c on c.id = bal.cid where bal.b > 0 order by c.name
  loop
    v_row := array_fill(0::numeric, array[v_n]);
    v_b := cu.b;
    -- Invoice balances at month-end, oldest first.
    select coalesce(sum(o), 0) into v_s from (
      select s.total_paise - s.paid_at_sale_paise
             - coalesce((select sum(a.amount_paise) from ar_allocations a left join customer_receipts r on r.id = a.receipt_id
                         left join sales_returns t on t.id = a.return_id
                         where a.sale_id = s.id and coalesce(r.status, t.status) = 'posted'
                           and coalesce(r.receipt_date, t.return_date) <= v_end), 0)
             - coalesce((select sum(w.amount_paise) from customer_write_offs w
                         where w.sale_id = s.id and w.status = 'posted' and w.write_off_date <= v_end), 0) o
      from sales s where s.customer_id = cu.id and s.status <> 'cancelled' and s.invoice_date <= v_end and s.is_demo = p_demo) x
    where o > 0;
    v_excess := greatest(v_s - v_b, 0);
    for inv in
      select s.id, coalesce(s.due_date, s.invoice_date) due,
             s.total_paise - s.paid_at_sale_paise
             - coalesce((select sum(a.amount_paise) from ar_allocations a left join customer_receipts r on r.id = a.receipt_id
                         left join sales_returns t on t.id = a.return_id
                         where a.sale_id = s.id and coalesce(r.status, t.status) = 'posted'
                           and coalesce(r.receipt_date, t.return_date) <= v_end), 0)
             - coalesce((select sum(w.amount_paise) from customer_write_offs w
                         where w.sale_id = s.id and w.status = 'posted' and w.write_off_date <= v_end), 0) o
      from sales s where s.customer_id = cu.id and s.status <> 'cancelled' and s.invoice_date <= v_end and s.is_demo = p_demo
      order by coalesce(s.due_date, s.invoice_date), s.id
    loop
      continue when inv.o <= 0;
      v_take := least(v_excess, inv.o);
      v_excess := v_excess - v_take;
      continue when inv.o - v_take <= 0;
      v_days := v_end - inv.due;
      i := 1;
      while i < v_n and (v_bands->(i - 1)->>'upto') is not null and v_days > (v_bands->(i - 1)->>'upto')::int loop
        i := i + 1;
      end loop;
      v_row[i] := v_row[i] + (inv.o - v_take);
    end loop;
    v_other := greatest(v_b - v_s, 0);
    v_cprov := v_other * v_other_pct / 100;
    for i in 1..v_n loop
      v_amt[i] := v_amt[i] + v_row[i];
      v_cprov := v_cprov + v_row[i] * coalesce((v_bands->(i - 1)->>'pct')::numeric, 0) / 100;
    end loop;
    v_other_total := v_other_total + v_other;
    v_cust := v_cust || jsonb_build_array(jsonb_build_object('customer_id', cu.id, 'code', cu.code, 'name', cu.name,
      'balance_paise', v_b, 'bands', to_jsonb(v_row), 'other_paise', v_other, 'provision_paise', round(v_cprov)::bigint));
  end loop;
  v_prov := v_other_total * v_other_pct / 100;
  v_lo := 0;
  for i in 1..v_n loop
    v_prov := v_prov + v_amt[i] * coalesce((v_bands->(i - 1)->>'pct')::numeric, 0) / 100;
    v_bands_out := v_bands_out || jsonb_build_array(jsonb_build_object(
      'label', case when i = 1 and (v_bands->0->>'upto')::int = 0 then 'Not yet due'
                    when (v_bands->(i - 1)->>'upto') is null then 'Over ' || (v_lo - 1) || ' days past due'
                    else v_lo || ' to ' || (v_bands->(i - 1)->>'upto') || ' days past due' end,
      'upto', v_bands->(i - 1)->'upto', 'pct', coalesce((v_bands->(i - 1)->>'pct')::numeric, 0), 'amount_paise', round(v_amt[i])::bigint,
      'provision_paise', round(v_amt[i] * coalesce((v_bands->(i - 1)->>'pct')::numeric, 0) / 100)::bigint));
    v_lo := coalesce((v_bands->(i - 1)->>'upto')::int, 0) + 1;
  end loop;
  v_req := round(v_prov)::bigint;
  select -coalesce(sum(l.debit_paise - l.credit_paise), 0)::bigint into v_existing
  from journal_lines l join journals j on j.id = l.journal_id
  where l.account_code = (select account_code from posting_rules where event_code = 'doubtful_debts' and line_key = 'provision')
    and j.status <> 'draft' and l.journal_date <= v_end and l.is_demo = p_demo;
  return jsonb_build_object('month', v_m, 'month_end', v_end, 'demo', p_demo, 'bands', v_bands_out,
    'other', jsonb_build_object('label', 'Balances not on an invoice (opening balances, journals)', 'pct', v_other_pct,
                                'amount_paise', v_other_total, 'provision_paise', round(v_other_total * v_other_pct / 100)::bigint),
    'customers', v_cust, 'required_paise', v_req, 'existing_paise', v_existing, 'change_paise', v_req - v_existing,
    'rates_note', (select doubtful_debt_rates_note from app_settings where id = 1),
    'rates_example', (select doubtful_debt_rates_example from app_settings where id = 1),
    'rates_all_zero', not exists (select 1 from jsonb_array_elements(v_bands) b where coalesce((b->>'pct')::numeric, 0) > 0) and v_other_pct = 0);
end $$;

create or replace function rb_cb_post_provision(p_month date, p_demo boolean, p_actor uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_m date := date_trunc('month', p_month)::date; v_end date; v_x jsonb; v_id bigint; v_no text; v_j bigint; v_chg bigint;
begin
  if p_month is null then raise exception 'Please choose the month.'; end if;
  v_end := (v_m + interval '1 month - 1 day')::date;
  if v_end >= current_date and not p_demo then
    raise exception 'Run this once % has ended (from %).', to_char(v_m, 'Mon-YYYY'), to_char(v_end + 1, 'DD-Mon-YYYY');
  end if;
  perform rb_assert_period_open(v_end);
  if exists (select 1 from month_end_runs where kind = 'doubtful_debts' and month = v_m and status = 'posted' and is_demo = p_demo) then
    raise exception 'The provision for % is already posted. Reverse that run first to run it again.', to_char(v_m, 'Mon-YYYY');
  end if;
  v_x := rb_cb_provision_calc(v_m, p_demo);
  v_chg := (v_x->>'change_paise')::bigint;
  v_no := rb_cb_no('ME', p_demo, v_end);
  insert into month_end_runs (run_no, kind, month, run_date, details, amount_paise, entered_by, is_demo, is_training)
  values (v_no, 'doubtful_debts', v_m, v_end, v_x, v_chg, p_actor, p_demo, rb_is_training())
  returning id into v_id;
  if v_chg <> 0 then
    v_j := rb_post_engine(jsonb_build_object('journal_date', v_end, 'source', 'cash_bank', 'event_code', 'doubtful_debts', 'source_ref', v_no,
      'narration', 'Month-end ' || to_char(v_m, 'Mon-YYYY') || ': provision for doubtful debts ' ||
        case when v_chg > 0 then 'raised' else 'written back' end || ' to ' || rb_pur_fmt((v_x->>'required_paise')::bigint) ||
        ' (customer balances aged at ' || to_char(v_end, 'DD-Mon-YYYY') || ')',
      'department_id', rb_cb_dept('CC005'), 'is_demo', p_demo, 'entered_by', p_actor, 'approved_by', p_actor),
      jsonb_build_array(jsonb_build_object('rule', 'doubtful_debts.expense', 'amount_paise', v_chg),
                        jsonb_build_object('rule', 'doubtful_debts.provision', 'amount_paise', v_chg)));
    update month_end_runs set journal_id = v_j where id = v_id;
  end if;
  perform rb_audit_write('MONTH_END_PROVISION', 'month_end_runs', v_id::text, null,
    jsonb_build_object('run_no', v_no, 'month', v_m, 'required_paise', v_x->'required_paise', 'change_paise', v_chg), null);
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- 9. Journal guard: entries from this screen are reversed here
-- ---------------------------------------------------------------------

create or replace function rb_cb_journal_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('rb.cashbank', true), '') = 'on' then return coalesce(new, old); end if;
  if tg_op = 'UPDATE' and old.source = 'cash_bank' and old.status = 'posted' and new.status = 'reversed' then
    raise exception 'This entry comes from the Cash, bank and expenses screen. Reverse it there, so the cash book, supplier balances and stock stay right.';
  end if;
  if tg_op = 'DELETE' and old.source = 'cash_bank' and old.status <> 'draft' and not old.is_demo
     and not (old.is_training and rb_is_training()) then
    raise exception 'This entry comes from the Cash, bank and expenses screen. Delete or reverse it there.';
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists rb_cb_journal_guard on journals;
create trigger rb_cb_journal_guard before update or delete on journals
  for each row execute function rb_cb_journal_guard();

-- Reverse one journal from this screen.
create or replace function rb_cb_reverse(p_journal bigint, p_date date, p_text text)
returns bigint language plpgsql security definer set search_path = public as $$
declare v bigint;
begin
  if p_journal is null then return null; end if;
  perform set_config('rb.cashbank', 'on', true);
  v := rb_reverse_journal(p_journal, p_date, p_text);
  perform set_config('rb.cashbank', 'off', true);
  return v;
end $$;

-- ---------------------------------------------------------------------
-- 10. What the screens call
-- ---------------------------------------------------------------------

create or replace function rb_save_expense(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('cash_bank.add', 'enter expenses');
begin
  return rb_cb_save_expense(p, v_me, false);
end $$;

create or replace function rb_approve_expense(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('cash_bank.approve', 'approve expenses'); v_e expenses;
begin
  select * into v_e from expenses where id = p_id for update;
  if v_e.id is null then raise exception 'Expense not found.'; end if;
  if v_e.status <> 'awaiting_approval' then raise exception 'This entry is not waiting for approval.'; end if;
  if not rb_can_approve('cash_bank', v_e.entered_by) then raise exception 'You cannot approve your own entries.'; end if;
  perform rb_assert_period_open(v_e.expense_date);
  perform rb_cb_post_expense(p_id, v_me);
  perform rb_audit_write('APPROVE_EXPENSE', 'expenses', p_id::text, null, jsonb_build_object('expense_no', v_e.expense_no), null);
end $$;

create or replace function rb_refuse_expense(p_id bigint, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('cash_bank.approve', 'refuse expenses'); v_e expenses;
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason.'; end if;
  select * into v_e from expenses where id = p_id for update;
  if v_e.id is null or v_e.status <> 'awaiting_approval' then raise exception 'This entry is not waiting for approval.'; end if;
  update expenses set status = 'refused', refused_reason = trim(p_reason), updated_at = now(), updated_by = v_me where id = p_id;
  perform rb_audit_write('REFUSE_EXPENSE', 'expenses', p_id::text, null, jsonb_build_object('expense_no', v_e.expense_no), trim(p_reason));
end $$;

create or replace function rb_reverse_expense(p_id bigint, p_date date, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.reverse_entries', 'reverse posted entries'); v_e expenses; v_rev bigint;
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason for the reversal.'; end if;
  select * into v_e from expenses where id = p_id for update;
  if v_e.id is null or v_e.status <> 'posted' then raise exception 'Only a posted entry can be reversed.'; end if;
  if v_e.paid_paise > 0 then
    raise exception 'Payments have been set against % (%). Reverse those payments first.', v_e.expense_no, rb_pur_fmt(v_e.paid_paise);
  end if;
  if p_date is null or p_date < v_e.expense_date then raise exception 'The reversal date cannot be before the entry''s own date.'; end if;
  v_rev := rb_cb_reverse(v_e.journal_id, p_date, v_e.expense_no || ' reversed: ' || trim(p_reason));
  update expenses set status = 'reversed', reversal_journal_id = v_rev, reverse_reason = trim(p_reason), outstanding_paise = 0,
    updated_at = now(), updated_by = v_me where id = p_id;
  perform rb_audit_write('REVERSE_EXPENSE', 'expenses', p_id::text, null, jsonb_build_object('expense_no', v_e.expense_no, 'date', p_date), trim(p_reason));
end $$;

create or replace function rb_add_expense_photo(p_id bigint, p_data_url text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('cash_bank.add', 'add bill photos'); v_e expenses;
begin
  select * into v_e from expenses where id = p_id;
  if v_e.id is null then raise exception 'Expense not found.'; end if;
  if coalesce(p_data_url, '') = '' then raise exception 'Choose a photo first.'; end if;
  insert into expense_photos (expense_id, data_url, added_by, is_demo, is_training) values (p_id, p_data_url, v_me, v_e.is_demo, rb_is_training());
end $$;

create or replace function rb_expense_photos(p_id bigint)
returns setof text language plpgsql stable security definer set search_path = public as $$
begin
  if not (rb_has('cash_bank.view') or rb_has('accounts.view')) then raise exception 'You do not have the right to see bill photos.'; end if;
  return query select data_url from expense_photos where expense_id = p_id order by id;
end $$;

-- Pay expense bills on credit (a supplier payment, as in Purchases).
create or replace function rb_pay_expense_bill(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('cash_bank.add', 'pay expense bills');
begin
  return rb_pur_pay(p, v_me, false);
end $$;

create or replace function rb_save_transfer(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('cash_bank.add', 'move money between cash and bank');
begin
  return rb_cb_transfer(p, v_me, false);
end $$;

create or replace function rb_save_partner_entry(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('cash_bank.edit', 'enter partners'' capital and drawings');
begin
  return rb_cb_partner(p, v_me, false);
end $$;

create or replace function rb_save_cash_count(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('cash_bank.add', 'enter cash counts');
begin
  return rb_cb_count(p, v_me, false);
end $$;

-- Reverse a transfer, partner entry or cash count.
create or replace function rb_reverse_cash_entry(p_kind text, p_id bigint, p_date date, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.reverse_entries', 'reverse posted entries'); v_no text; v_j bigint; v_status text; v_date date; v_rev bigint;
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason for the reversal.'; end if;
  if p_kind = 'transfer' then select transfer_no, journal_id, status, transfer_date into v_no, v_j, v_status, v_date from money_transfers where id = p_id for update;
  elsif p_kind = 'partner' then select entry_no, journal_id, status, entry_date into v_no, v_j, v_status, v_date from partner_entries where id = p_id for update;
  elsif p_kind = 'count' then select count_no, journal_id, status, count_date into v_no, v_j, v_status, v_date from cash_counts where id = p_id for update;
  else raise exception 'Unknown entry.'; end if;
  if v_no is null then raise exception 'Entry not found.'; end if;
  if v_status <> 'posted' then raise exception 'This entry is already reversed.'; end if;
  if p_date is null or p_date < v_date then raise exception 'The reversal date cannot be before the entry''s own date.'; end if;
  v_rev := rb_cb_reverse(v_j, p_date, v_no || ' reversed: ' || trim(p_reason));
  if p_kind = 'transfer' then update money_transfers set status = 'reversed', reversal_journal_id = v_rev, reverse_reason = trim(p_reason) where id = p_id;
  elsif p_kind = 'partner' then update partner_entries set status = 'reversed', reversal_journal_id = v_rev, reverse_reason = trim(p_reason) where id = p_id;
  else update cash_counts set status = 'reversed', reversal_journal_id = v_rev, reverse_reason = trim(p_reason) where id = p_id; end if;
  perform rb_audit_write('REVERSE_' || upper(p_kind), p_kind, p_id::text, null, jsonb_build_object('no', v_no, 'date', p_date), trim(p_reason));
end $$;

-- Learning phase: a Director or the FC may fully delete an entry made by
-- someone still in their learning phase. Not written to the audit log (spec section 4).
create or replace function rb_hard_delete_cash_entry(p_kind text, p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('cash_bank.delete', 'fully delete entries'); v_by uuid; v_j bigint; v_status text; v_date date;
begin
  if p_kind = 'expense' then select entered_by, journal_id, status, expense_date into v_by, v_j, v_status, v_date from expenses where id = p_id for update;
  elsif p_kind = 'transfer' then select entered_by, journal_id, status, transfer_date into v_by, v_j, v_status, v_date from money_transfers where id = p_id for update;
  elsif p_kind = 'partner' then select entered_by, journal_id, status, entry_date into v_by, v_j, v_status, v_date from partner_entries where id = p_id for update;
  elsif p_kind = 'count' then select entered_by, journal_id, status, count_date into v_by, v_j, v_status, v_date from cash_counts where id = p_id for update;
  else raise exception 'Unknown entry.'; end if;
  if v_status is null then raise exception 'Entry not found.'; end if;
  if not rb_can_hard_delete('cash_bank', v_by) then
    raise exception 'Only entries made by someone still in their learning phase can be fully deleted. Reverse it instead.';
  end if;
  if v_status = 'reversed' then raise exception 'This entry has been reversed. Reversed entries are kept.'; end if;
  perform rb_assert_period_open(v_date);
  if p_kind = 'expense' and exists (select 1 from payment_allocations where expense_id = p_id) then
    raise exception 'Payments have been set against this bill. Delete or reverse those first.';
  end if;
  if v_j is not null and exists (select 1 from bank_clearings c join journal_lines l on l.id = c.journal_line_id where l.journal_id = v_j) then
    raise exception 'This entry is ticked in a bank reconciliation. Untick it there first.';
  end if;
  perform set_config('rb.ledger', 'on', true);
  perform set_config('rb.cashbank', 'on', true);
  if p_kind = 'expense' then delete from expenses where id = p_id;
  elsif p_kind = 'transfer' then delete from money_transfers where id = p_id;
  elsif p_kind = 'partner' then delete from partner_entries where id = p_id;
  else delete from cash_counts where id = p_id; end if;
  if v_j is not null then delete from journals where id = v_j; end if;
  perform set_config('rb.cashbank', 'off', true);
  perform set_config('rb.ledger', 'off', true);
end $$;

-- Set-up: name and switch on the cash and bank accounts.
create or replace function rb_save_money_account(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('cash_bank.edit', 'change the cash and bank accounts'); v_a money_accounts; v_active boolean;
begin
  select * into v_a from money_accounts where id = rb_int(p, 'id') for update;
  if v_a.id is null then raise exception 'Account not found.'; end if;
  if rb_txt(p, 'name') is null then raise exception 'Please give the account a name.'; end if;
  v_active := coalesce((p->>'is_active')::boolean, v_a.is_active);
  if not v_active and v_a.is_default then raise exception 'The main % account cannot be switched off. Make another one the main account first.', v_a.kind; end if;
  if not v_active and rb_cb_balance(v_a.account_code, null) <> 0 then
    raise exception '% still has % in the books. Move it to another account first.', v_a.name, rb_pur_fmt(rb_cb_balance(v_a.account_code, null));
  end if;
  if coalesce((p->>'is_default')::boolean, false) and not v_a.is_default then
    if not v_active then raise exception 'A switched-off account cannot be the main one.'; end if;
    update money_accounts set is_default = false where kind = v_a.kind and id <> v_a.id;
  end if;
  update money_accounts set name = rb_txt(p, 'name'), bank_name = rb_txt(p, 'bank_name'), account_last4 = rb_txt(p, 'account_last4'),
    upi_id = rb_txt(p, 'upi_id'), is_active = v_active,
    is_default = is_default or coalesce((p->>'is_default')::boolean, false), updated_at = now(), updated_by = v_me
  where id = v_a.id;
  perform rb_audit_write('MONEY_ACCOUNT', 'money_accounts', v_a.id::text, to_jsonb(v_a), (select to_jsonb(m) from money_accounts m where id = v_a.id), null);
end $$;

-- Set-up: add or change an expense category (and the account it posts to).
create or replace function rb_save_expense_category(p jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('cash_bank.edit', 'change expense categories'); v_id int := rb_int(p, 'id'); v_old expense_categories;
        v_a accounts; v_dir text := coalesce(rb_txt(p, 'direction'), 'out');
begin
  if rb_txt(p, 'name') is null then raise exception 'Please give the category a name.'; end if;
  select * into v_a from accounts where code = rb_txt(p, 'account_code');
  if v_a.code is null or v_a.level <> 'posting' or not v_a.e002_active then raise exception 'Choose a posting account that Ruchi Buds uses.'; end if;
  if v_dir = 'out' and v_a.statement <> 'PL' then raise exception 'An expense category posts to a profit and loss account. % is a balance sheet account.', v_a.code; end if;
  if v_dir = 'in' and v_a.class not in ('Other Income', 'Revenue') then raise exception 'Money received posts to an income account.'; end if;
  if v_a.control_type is not null then raise exception '% is kept per customer, supplier, item or partner and cannot be used here.', v_a.code; end if;
  if v_id is null then
    insert into expense_categories (name, direction, account_code, default_department_code, hint, sort, updated_at, updated_by)
    values (rb_txt(p, 'name'), v_dir, v_a.code, rb_txt(p, 'default_department_code'), rb_txt(p, 'hint'),
            coalesce(rb_int(p, 'sort')::int, 300), now(), v_me)
    returning id into v_id;
  else
    select * into v_old from expense_categories where id = v_id for update;
    if v_old.id is null then raise exception 'Category not found.'; end if;
    if v_old.direction <> v_dir then raise exception 'A category cannot change between money out and money in.'; end if;
    update expense_categories set name = rb_txt(p, 'name'), account_code = v_a.code, default_department_code = rb_txt(p, 'default_department_code'),
      hint = rb_txt(p, 'hint'), is_active = coalesce((p->>'is_active')::boolean, is_active), updated_at = now(), updated_by = v_me
    where id = v_id;
  end if;
  return v_id;
exception when unique_violation then
  raise exception 'There is already a category called "%".', rb_txt(p, 'name');
end $$;

-- Settings: expense approval limit and the CA's rates for doubtful debts.
create or replace function rb_save_cashbank_settings(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('settings.edit', 'change settings'); v_bands jsonb := p->'doubtful_debt_bands'; b jsonb; v_prev int := -1;
        i int := 0; v_n int; v_pct numeric;
begin
  if v_bands is not null then
    v_n := jsonb_array_length(v_bands);
    if v_n < 2 or v_n > 10 then raise exception 'Use between 2 and 10 age bands.'; end if;
    for b in select * from jsonb_array_elements(v_bands) loop
      i := i + 1;
      v_pct := coalesce(nullif(b->>'pct', '')::numeric, 0);
      if v_pct < 0 or v_pct > 100 then raise exception 'Each rate must be between 0 and 100%%.'; end if;
      if i < v_n then
        if nullif(b->>'upto', '') is null then raise exception 'Only the last band is open-ended ("and over").'; end if;
        if (b->>'upto')::int <= v_prev then raise exception 'The day limits must go up from band to band.'; end if;
        v_prev := (b->>'upto')::int;
      elsif nullif(b->>'upto', '') is not null then
        raise exception 'The last band must be open-ended ("and over").';
      end if;
    end loop;
    select jsonb_agg(jsonb_build_object('upto', case when nullif(x->>'upto', '') is null then null else (x->>'upto')::int end,
                                        'pct', coalesce(nullif(x->>'pct', '')::numeric, 0)) order by n)
    into v_bands from jsonb_array_elements(v_bands) with ordinality t(x, n);
  end if;
  if p ? 'doubtful_debt_other_pct' and coalesce(nullif(p->>'doubtful_debt_other_pct', '')::numeric, 0) not between 0 and 100 then
    raise exception 'Each rate must be between 0 and 100%%.';
  end if;
  update app_settings set
    expense_approval_limit_paise = case when p ? 'expense_approval_limit_paise' then rb_int(p, 'expense_approval_limit_paise') else expense_approval_limit_paise end,
    doubtful_debt_bands = coalesce(v_bands, doubtful_debt_bands),
    doubtful_debt_other_pct = case when p ? 'doubtful_debt_other_pct' then coalesce(nullif(p->>'doubtful_debt_other_pct', '')::numeric, 0) else doubtful_debt_other_pct end,
    doubtful_debt_rates_note = case when p ? 'doubtful_debt_rates_note' then rb_txt(p, 'doubtful_debt_rates_note') else doubtful_debt_rates_note end,
    doubtful_debt_rates_example = case when v_bands is not null or p ? 'doubtful_debt_other_pct' then false else doubtful_debt_rates_example end,
    updated_at = now(), updated_by = v_me
  where id = 1;
end $$;

-- Month-end set-up: which accounts are shared into stock, fixed or variable,
-- and the normal monthly output (AS 2 normal capacity).
create or replace function rb_save_absorption_setup(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.month_end', 'change the month-end set-up'); a jsonb; v_acc accounts; v_old jsonb;
begin
  select jsonb_build_object('normal_output_kg', (select normal_output_kg from app_settings where id = 1),
                            'accounts', (select jsonb_agg(to_jsonb(x) order by account_code) from absorption_accounts x)) into v_old;
  if p ? 'normal_output_kg' then
    if nullif(p->>'normal_output_kg', '') is not null and (p->>'normal_output_kg')::numeric <= 0 then
      raise exception 'The normal monthly output must be more than zero, or blank.';
    end if;
    update app_settings set normal_output_kg = nullif(p->>'normal_output_kg', '')::numeric where id = 1;
  end if;
  if p ? 'accounts' then
    for a in select * from jsonb_array_elements(p->'accounts') loop
      select * into v_acc from accounts where code = rb_txt(a, 'code');
      if v_acc.code is null then raise exception 'Account % not found.', rb_txt(a, 'code'); end if;
      if coalesce((a->>'include')::boolean, true) then
        if v_acc.class <> 'Direct Cost' or v_acc.level <> 'posting' then
          raise exception '% % is not a production cost account (7002 labour or 7003 production overheads). Selling and office costs never go into stock (AS 2).', v_acc.code, v_acc.name;
        end if;
        if v_acc.code like '700101%' or v_acc.code like '700501%' or v_acc.code = '70030140' or v_acc.code like '70030145' or v_acc.code like '70030150' then
          raise exception '% % cannot be shared into stock.', v_acc.code, v_acc.name;
        end if;
        insert into absorption_accounts (account_code, behaviour, updated_at, updated_by)
        values (v_acc.code, coalesce(rb_txt(a, 'behaviour'), 'fixed'), now(), v_me)
        on conflict (account_code) do update set behaviour = excluded.behaviour, updated_at = now(), updated_by = v_me;
      else
        delete from absorption_accounts where account_code = v_acc.code;
      end if;
    end loop;
  end if;
  perform rb_audit_write('ABSORPTION_SETUP', 'absorption_accounts', null, v_old, p, null);
end $$;

-- Change the sharing method for the books: a Director only, with a reason (spec section 7).
create or replace function rb_set_absorption_method(p_method text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.month_end', 'change the sharing method'); v_old text;
begin
  if not exists (select 1 from app_users u join user_categories c on c.id = u.category_id where u.id = v_me and c.template = 'Director') then
    raise exception 'Only a Director can change the sharing method.';
  end if;
  if p_method not in ('kg', 'batches', 'hours', 'material') then raise exception 'Choose kg produced, number of batches, hours worked or value of materials.'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason for the change.'; end if;
  select absorption_method into v_old from app_settings where id = 1;
  if v_old = p_method then raise exception 'That is already the method in use.'; end if;
  update app_settings set absorption_method = p_method, updated_at = now(), updated_by = v_me where id = 1;
  insert into absorption_method_log (changed_by, old_method, new_method, reason) values (v_me, v_old, p_method, trim(p_reason));
  perform rb_audit_write('ABSORPTION_METHOD', 'app_settings', '1', jsonb_build_object('method', v_old), jsonb_build_object('method', p_method), trim(p_reason));
end $$;

-- Month-end previews and posting. p_demo: null = work it out (DEMO
-- records only when the month has no real ones).
create or replace function rb_absorption_preview(p_month date, p_hours jsonb default null, p_demo boolean default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.month_end', 'run the month-end steps'); v_demo boolean := coalesce(p_demo, rb_cb_use_demo(p_month, 'absorption'));
        v_method text; v_x jsonb;
begin
  if p_month is null then raise exception 'Please choose the month.'; end if;
  select absorption_method into v_method from app_settings where id = 1;
  v_x := rb_cb_absorb_calc(p_month, v_method, p_hours, v_demo, false);
  return jsonb_build_object('method', v_method, 'demo', v_demo, 'detail', v_x,
    'compare', jsonb_build_object(
      'kg', (rb_cb_absorb_calc(p_month, 'kg', p_hours, v_demo, false))->'capitalised_paise',
      'batches', (rb_cb_absorb_calc(p_month, 'batches', p_hours, v_demo, false))->'capitalised_paise',
      'hours', (rb_cb_absorb_calc(p_month, 'hours', p_hours, v_demo, false))->'capitalised_paise',
      'material', (rb_cb_absorb_calc(p_month, 'material', p_hours, v_demo, false))->'capitalised_paise'),
    'normal_output_kg', (select normal_output_kg from app_settings where id = 1),
    'posted', (select to_jsonb(r) - 'details' from month_end_runs r where kind = 'absorption' and status = 'posted'
               and month = date_trunc('month', p_month)::date and is_demo = v_demo),
    'log', coalesce((select jsonb_agg(jsonb_build_object('changed_at', l.changed_at, 'by', u.full_name, 'old_method', l.old_method,
               'new_method', l.new_method, 'reason', l.reason) order by l.id desc)
               from absorption_method_log l left join app_users u on u.id = l.changed_by), '[]'));
end $$;

create or replace function rb_post_absorption(p_month date, p_hours jsonb default null, p_demo boolean default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.month_end', 'run the month-end steps');
begin
  return rb_cb_post_absorption(p_month, p_hours, coalesce(p_demo, rb_cb_use_demo(p_month, 'absorption')), v_me);
end $$;

create or replace function rb_provision_preview(p_month date, p_demo boolean default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_me uuid := rb_require('power.month_end', 'run the month-end steps'); v_demo boolean := coalesce(p_demo, rb_cb_use_demo(p_month, 'doubtful_debts'));
begin
  if p_month is null then raise exception 'Please choose the month.'; end if;
  return rb_cb_provision_calc(p_month, v_demo) || jsonb_build_object(
    'posted', (select to_jsonb(r) - 'details' from month_end_runs r where kind = 'doubtful_debts' and status = 'posted'
               and month = date_trunc('month', p_month)::date and is_demo = v_demo));
end $$;

create or replace function rb_post_provision(p_month date, p_demo boolean default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.month_end', 'run the month-end steps');
begin
  return rb_cb_post_provision(p_month, coalesce(p_demo, rb_cb_use_demo(p_month, 'doubtful_debts')), v_me);
end $$;

-- Reverse a month-end run (to run it again after a correction).
create or replace function rb_reverse_month_end(p_id bigint, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.month_end', 'reverse month-end steps'); v_r month_end_runs; v_rev bigint; r record;
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason for the reversal.'; end if;
  select * into v_r from month_end_runs where id = p_id for update;
  if v_r.id is null or v_r.status <> 'posted' then raise exception 'Only a posted run can be reversed.'; end if;
  perform rb_assert_period_open(v_r.run_date);
  if v_r.kind = 'absorption' then
    insert into stock_moves (move_date, item_id, pack_id, lot_batch_id, qty_base, value_paise, kind, doc_no, department_id, note,
                             created_by, month_end_run_id, is_demo, is_training)
    select v_r.run_date, item_id, pack_id, lot_batch_id, 0, -value_paise, 'overhead', v_r.run_no, department_id,
           'Reversed: ' || trim(p_reason), v_me, v_r.id, is_demo, rb_is_training()
    from stock_moves where month_end_run_id = v_r.id and kind = 'overhead' and value_paise > 0;
    for r in select m.item_id, m.pack_id, m.lot_batch_id from stock_moves m where m.month_end_run_id = v_r.id group by 1, 2, 3 loop
      if (select coalesce(sum(value_paise), 0) from stock_moves where item_id = r.item_id and pack_id is not distinct from r.pack_id
          and (r.lot_batch_id is null or lot_batch_id = r.lot_batch_id)) < 0 then
        raise exception 'Some of the stock this run added to (%) has since been used or sold, so its value would go below zero. Reverse those entries first, or leave this run in place.',
          rb_stk_label(r.item_id, r.pack_id);
      end if;
    end loop;
  end if;
  v_rev := rb_cb_reverse(v_r.journal_id, v_r.run_date, v_r.run_no || ' reversed: ' || trim(p_reason));
  update stock_moves set journal_id = v_rev where month_end_run_id = v_r.id and value_paise < 0 and journal_id is null;
  update month_end_runs set status = 'reversed', reversal_journal_id = v_rev, reverse_reason = trim(p_reason) where id = p_id;
  perform rb_audit_write('REVERSE_MONTH_END', 'month_end_runs', p_id::text, null, jsonb_build_object('run_no', v_r.run_no), trim(p_reason));
end $$;

-- ---------------------------------------------------------------------
-- 11. Bank reconciliation
-- ---------------------------------------------------------------------

-- Everything needed to reconcile one bank account for one month: the
-- book entries up to month-end not yet matched to an earlier statement.
create or replace function rb_bank_recon(p_account int, p_month date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_a money_accounts; v_m date := date_trunc('month', p_month)::date; v_end date; v_r bank_recons;
begin
  if not (rb_has('cash_bank.view') and rb_has('power.see_totals')) and not rb_has('accounts.view') then
    raise exception 'You do not have the right to see bank reconciliations.';
  end if;
  select * into v_a from money_accounts where id = p_account;
  if v_a.id is null or v_a.kind <> 'bank' then raise exception 'Choose a bank account.'; end if;
  v_end := (v_m + interval '1 month - 1 day')::date;
  select * into v_r from bank_recons where money_account_id = p_account and month = v_m;
  return jsonb_build_object('account', to_jsonb(v_a), 'month', v_m, 'month_end', v_end, 'recon', to_jsonb(v_r),
    'book_balance_paise', rb_cb_balance(v_a.account_code, v_end),
    'cleared_balance_paise', (select coalesce(sum(l.debit_paise - l.credit_paise), 0) from journal_lines l join journals j on j.id = l.journal_id
                              join bank_clearings c on c.journal_line_id = l.id
                              where l.account_code = v_a.account_code and j.status <> 'draft' and c.recon_month <= v_m),
    'earlier_open', (select count(*) from bank_recons where money_account_id = p_account and month < v_m and status <> 'done'),
    'lines', coalesce((select jsonb_agg(jsonb_build_object('line_id', l.id, 'date', l.journal_date, 'journal_no', j.journal_no,
                 'ref', j.source_ref, 'narration', coalesce(l.narration, j.narration), 'in_paise', l.debit_paise, 'out_paise', l.credit_paise,
                 'cleared', c.recon_month = v_m, 'cleared_later', c.recon_month > v_m, 'is_demo', l.is_demo)
                 order by l.journal_date, l.id)
               from journal_lines l join journals j on j.id = l.journal_id left join bank_clearings c on c.journal_line_id = l.id
               where l.account_code = v_a.account_code and j.status <> 'draft' and l.journal_date <= v_end
                 and (c.journal_line_id is null or c.recon_month >= v_m)), '[]'));
end $$;

-- Save the ticks and the statement balance; "finish" marks the month done
-- once the cleared entries agree with the statement to the paisa.
-- p: account_id, month, statement_balance_paise, note, finish, ticks [{line_id, cleared}]
create or replace function rb_save_bank_recon(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('cash_bank.edit', 'reconcile bank accounts'); v_a money_accounts; v_m date := date_trunc('month', (p->>'month')::date)::date;
        v_end date; v_r bank_recons; t jsonb; v_l journal_lines; v_c bank_clearings; v_cleared bigint; v_book bigint; v_in bigint; v_out bigint;
        v_stmt bigint := rb_int(p, 'statement_balance_paise'); v_diff bigint;
begin
  select * into v_a from money_accounts where id = rb_int(p, 'account_id');
  if v_a.id is null or v_a.kind <> 'bank' then raise exception 'Choose a bank account.'; end if;
  if v_m is null then raise exception 'Please choose the month.'; end if;
  v_end := (v_m + interval '1 month - 1 day')::date;
  select * into v_r from bank_recons where money_account_id = v_a.id and month = v_m for update;
  if v_r.status = 'done' then raise exception 'This month is already reconciled. Reopen it first to change it.'; end if;
  for t in select * from jsonb_array_elements(coalesce(p->'ticks', '[]')) loop
    select * into v_l from journal_lines where id = rb_int(t, 'line_id');
    if v_l.id is null or v_l.account_code <> v_a.account_code or v_l.journal_date > v_end then
      raise exception 'That entry is not in % up to %.', v_a.name, to_char(v_end, 'DD-Mon-YYYY');
    end if;
    select * into v_c from bank_clearings where journal_line_id = v_l.id;
    if coalesce((t->>'cleared')::boolean, false) then
      if v_c.journal_line_id is null then
        insert into bank_clearings (journal_line_id, recon_month, cleared_by, is_demo, is_training)
        values (v_l.id, v_m, v_me, v_l.is_demo, rb_is_training());
      elsif v_c.recon_month <> v_m then
        raise exception 'An entry of % is already matched to the % statement.', to_char(v_l.journal_date, 'DD-Mon-YYYY'), to_char(v_c.recon_month, 'Mon-YYYY');
      end if;
    elsif v_c.recon_month = v_m then
      delete from bank_clearings where journal_line_id = v_l.id;
    end if;
  end loop;
  select coalesce(sum(l.debit_paise - l.credit_paise), 0) into v_cleared from journal_lines l join journals j on j.id = l.journal_id
  join bank_clearings c on c.journal_line_id = l.id where l.account_code = v_a.account_code and j.status <> 'draft' and c.recon_month <= v_m;
  v_book := rb_cb_balance(v_a.account_code, v_end);
  select coalesce(sum(l.debit_paise), 0), coalesce(sum(l.credit_paise), 0) into v_in, v_out
  from journal_lines l join journals j on j.id = l.journal_id left join bank_clearings c on c.journal_line_id = l.id
  where l.account_code = v_a.account_code and j.status <> 'draft' and l.journal_date <= v_end and (c.journal_line_id is null or c.recon_month > v_m);
  v_diff := case when v_stmt is null then null else v_stmt - v_cleared end;
  insert into bank_recons (money_account_id, month, statement_balance_paise, book_balance_paise, uncleared_in_paise, uncleared_out_paise,
                           difference_paise, note, updated_at, updated_by, is_training)
  values (v_a.id, v_m, v_stmt, v_book, v_in, v_out, v_diff, rb_txt(p, 'note'), now(), v_me, rb_is_training())
  on conflict (money_account_id, month) do update set statement_balance_paise = excluded.statement_balance_paise,
    book_balance_paise = excluded.book_balance_paise, uncleared_in_paise = excluded.uncleared_in_paise,
    uncleared_out_paise = excluded.uncleared_out_paise, difference_paise = excluded.difference_paise, note = excluded.note,
    updated_at = now(), updated_by = v_me;
  if coalesce((p->>'finish')::boolean, false) then
    if v_stmt is null then raise exception 'Enter the closing balance on the bank statement.'; end if;
    if v_diff <> 0 then
      raise exception 'The ticked entries come to %, but the statement says %: a difference of %. Tick what is on the statement, and enter anything missing (bank charges, interest) first.',
        rb_pur_fmt(v_cleared), rb_pur_fmt(v_stmt), rb_pur_fmt(abs(v_diff));
    end if;
    update bank_recons set status = 'done', done_by = v_me, done_at = now() where money_account_id = v_a.id and month = v_m;
    perform rb_audit_write('BANK_RECONCILED', 'bank_recons', v_a.id || '/' || v_m, null,
      jsonb_build_object('account', v_a.name, 'month', v_m, 'statement_paise', v_stmt, 'book_paise', v_book), null);
  end if;
  return jsonb_build_object('cleared_balance_paise', v_cleared, 'book_balance_paise', v_book, 'difference_paise', v_diff,
    'uncleared_in_paise', v_in, 'uncleared_out_paise', v_out);
end $$;

create or replace function rb_reopen_bank_recon(p_account int, p_month date, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('cash_bank.approve', 'reopen bank reconciliations'); v_m date := date_trunc('month', p_month)::date;
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason.'; end if;
  if exists (select 1 from bank_recons where money_account_id = p_account and month > v_m and status = 'done') then
    raise exception 'A later month is already reconciled. Reopen the latest month first.';
  end if;
  update bank_recons set status = 'draft', done_by = null, done_at = null, updated_at = now(), updated_by = v_me
  where money_account_id = p_account and month = v_m and status = 'done';
  if not found then raise exception 'That month is not marked done.'; end if;
  perform rb_audit_write('BANK_RECON_REOPENED', 'bank_recons', p_account || '/' || v_m, null, null, trim(p_reason));
end $$;

-- ---------------------------------------------------------------------
-- 12. Reading
-- ---------------------------------------------------------------------

-- Balances of every cash and bank account, with today's money in and out.
create or replace function rb_money_balances(p_as_of date default current_date)
returns table (id int, name text, kind text, account_code text, bank_name text, account_last4 text, is_default boolean,
               is_active boolean, balance_paise bigint, day_in_paise bigint, day_out_paise bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (rb_has('cash_bank.view') and rb_has('power.see_totals')) and not rb_has('accounts.view') then
    raise exception 'You do not have the right to see cash and bank balances.';
  end if;
  return query
  select m.id, m.name, m.kind, m.account_code, m.bank_name, m.account_last4, m.is_default, m.is_active,
         rb_cb_balance(m.account_code, p_as_of),
         coalesce((select sum(l.debit_paise) from journal_lines l join journals j on j.id = l.journal_id
                   where l.account_code = m.account_code and j.status <> 'draft' and l.journal_date = p_as_of), 0)::bigint,
         coalesce((select sum(l.credit_paise) from journal_lines l join journals j on j.id = l.journal_id
                   where l.account_code = m.account_code and j.status <> 'draft' and l.journal_date = p_as_of), 0)::bigint
  from money_accounts m
  where m.is_active or rb_cb_balance(m.account_code, null) <> 0
  order by m.sort;
end $$;

-- The cash book (or bank book) of one account: opening balance, every
-- entry with a running balance, and the closing balance.
create or replace function rb_cash_book(p_account int, p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_a money_accounts; v_open bigint;
begin
  if not (rb_has('cash_bank.view') and rb_has('power.see_totals')) and not rb_has('accounts.view') then
    raise exception 'You do not have the right to see the cash book.';
  end if;
  select * into v_a from money_accounts where id = p_account;
  if v_a.id is null then raise exception 'Choose the cash or bank account.'; end if;
  v_open := rb_cb_balance(v_a.account_code, p_from - 1);
  return jsonb_build_object('account', to_jsonb(v_a), 'from', p_from, 'to', p_to, 'opening_paise', v_open,
    'closing_paise', rb_cb_balance(v_a.account_code, p_to),
    'counts', coalesce((select jsonb_agg(jsonb_build_object('date', count_date, 'count_no', count_no, 'counted_paise', counted_paise,
                 'difference_paise', difference_paise, 'reason', reason) order by count_date)
               from cash_counts where money_account_id = p_account and status = 'posted' and count_date between p_from and p_to), '[]'),
    'lines', coalesce((select jsonb_agg(x order by x.d, x.lid) from (
        select l.journal_date d, l.id lid, j.journal_no, j.source_ref ref, coalesce(j.event_code, j.source) event,
               j.narration, l.debit_paise in_paise, l.credit_paise out_paise, l.is_demo,
               v_open + sum(l.debit_paise - l.credit_paise) over (order by l.journal_date, l.id) balance_paise
        from journal_lines l join journals j on j.id = l.journal_id
        where l.account_code = v_a.account_code and j.status <> 'draft' and l.journal_date between p_from and p_to) x), '[]'));
end $$;

-- Each partner's capital and current account (credit = owed to the partner).
create or replace function rb_partner_balances(p_as_of date default current_date)
returns table (partner_id int, name text, capital_paise bigint, current_paise bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (rb_has('cash_bank.view') and rb_has('power.see_totals')) and not rb_has('accounts.view') then
    raise exception 'You do not have the right to see partners'' accounts.';
  end if;
  return query
  select (e->>'id')::int, e->>'name',
         coalesce((select sum(l.credit_paise - l.debit_paise) from journal_lines l join journals j on j.id = l.journal_id
                   where l.account_code = '50010130' and l.partner_id = (e->>'id')::int and j.status <> 'draft' and l.journal_date <= p_as_of), 0)::bigint,
         coalesce((select sum(l.credit_paise - l.debit_paise) from journal_lines l join journals j on j.id = l.journal_id
                   where l.account_code = '50010135' and l.partner_id = (e->>'id')::int and j.status <> 'draft' and l.journal_date <= p_as_of), 0)::bigint
  from app_settings s, jsonb_array_elements(s.partners) e where s.id = 1;
end $$;

-- Expenses and other money received by month, category and department.
create or replace function rb_expense_report(p_from date, p_to date)
returns table (month date, direction text, category text, account_code text, department text, entries int,
               amount_paise bigint, gst_paise bigint, total_paise bigint, is_demo boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (rb_has('cash_bank.view') and rb_has('power.see_totals')) and not rb_has('accounts.view') then
    raise exception 'You do not have the right to see the expense report.';
  end if;
  return query
  select date_trunc('month', e.expense_date)::date, e.direction, c.name, e.account_code, rb_dept_label(e.department_id, e.expense_date),
         count(*)::int, sum(e.amount_paise)::bigint, sum(e.gst_paise)::bigint, sum(e.total_paise)::bigint, bool_or(e.is_demo)
  from expenses e join expense_categories c on c.id = e.category_id
  where e.status = 'posted' and e.expense_date between p_from and p_to
  group by 1, 2, 3, 4, 5 order by 1, 2 desc, 3;
end $$;

-- The month-end checklist.
create or replace function rb_month_end_status(p_month date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_m date := date_trunc('month', p_month)::date; v_end date;
begin
  if not rb_has('cash_bank.view') and not rb_has('accounts.view') then raise exception 'You do not have the right to see the month-end checklist.'; end if;
  v_end := (v_m + interval '1 month - 1 day')::date;
  return jsonb_build_object('month', v_m, 'month_end', v_end, 'locked', rb_period_locked(v_m),
    'banks', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'name', m.name, 'status', coalesce(r.status, 'not started'),
                 'difference_paise', r.difference_paise) order by m.sort)
               from money_accounts m left join bank_recons r on r.money_account_id = m.id and r.month = v_m
               where m.kind = 'bank' and m.is_active), '[]'),
    'cash', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'name', m.name,
                 'last_count', (select max(count_date) from cash_counts c where c.money_account_id = m.id and c.status = 'posted' and c.count_date <= v_end)) order by m.sort)
               from money_accounts m where m.kind = 'cash' and m.is_active), '[]'),
    'waiting_expenses', (select count(*) from expenses where status = 'awaiting_approval' and expense_date between v_m and v_end),
    'draft_journals', (select count(*) from journals where status = 'draft' and journal_date between v_m and v_end),
    'batches', (select count(*) from production_batches where status = 'posted' and batch_date between v_m and v_end),
    'runs', coalesce((select jsonb_agg(to_jsonb(r) - 'details' order by r.id) from month_end_runs r where r.month = v_m), '[]'));
end $$;

-- ---------------------------------------------------------------------
-- 13. Audit, row-level security and who may call what
-- ---------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array['money_accounts', 'expense_categories', 'absorption_accounts'] loop
    execute format('drop trigger if exists rb_audit on %I', t);
    execute format('create trigger rb_audit after insert or update or delete on %I
                    for each row execute function rb_audit_trigger()', t);
  end loop;
end $$;

do $$
declare t text;
begin
  foreach t in array array['money_accounts', 'expense_categories', 'absorption_accounts', 'absorption_method_log', 'expenses',
                           'expense_photos', 'money_transfers', 'partner_entries', 'cash_counts', 'bank_recons', 'bank_clearings',
                           'month_end_runs'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon, authenticated', t);
    execute format('grant select on %I to authenticated', t);
    execute format('grant all on %I to service_role', t);
    execute format('drop policy if exists rb_read on %I', t);
    if t in ('money_accounts', 'expense_categories') then
      -- lists every form needs
      execute format('create policy rb_read on %I for select to authenticated using (rb_current_user_id() is not null)', t);
    elsif t = 'expense_photos' then
      -- photos are read one expense at a time through rb_expense_photos
      execute format('create policy rb_read on %I for select to authenticated using (false)', t);
    elsif t = 'expenses' then
      -- Purchases also lists unpaid expense bills when a supplier is paid.
      execute format('create policy rb_read on %I for select to authenticated using (rb_has(''cash_bank.view'') or rb_has(''purchases.view'') or rb_has(''accounts.view''))', t);
    else
      execute format('create policy rb_read on %I for select to authenticated using (rb_has(''cash_bank.view'') or rb_has(''accounts.view''))', t);
    end if;
  end loop;
end $$;
-- Suppliers: people on this screen pick the supplier of an expense bill.
drop policy if exists rb_read on suppliers;
create policy rb_read on suppliers for select to authenticated
  using (rb_has('suppliers.view') or rb_has('purchases.view') or rb_has('accounts.view') or rb_has('cash_bank.view'));
revoke all on all sequences in schema public from anon, authenticated;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p
           where p.pronamespace = 'public'::regnamespace
             and (p.proname like 'rb\_cb\_%' or p.proname in (
               'rb_save_expense', 'rb_approve_expense', 'rb_refuse_expense', 'rb_reverse_expense', 'rb_add_expense_photo',
               'rb_expense_photos', 'rb_pay_expense_bill', 'rb_save_transfer', 'rb_save_partner_entry', 'rb_save_cash_count',
               'rb_reverse_cash_entry', 'rb_hard_delete_cash_entry', 'rb_save_money_account', 'rb_save_expense_category',
               'rb_save_cashbank_settings', 'rb_save_absorption_setup', 'rb_set_absorption_method', 'rb_absorption_preview',
               'rb_post_absorption', 'rb_provision_preview', 'rb_post_provision', 'rb_reverse_month_end', 'rb_bank_recon',
               'rb_save_bank_recon', 'rb_reopen_bank_recon', 'rb_money_balances', 'rb_cash_book', 'rb_partner_balances',
               'rb_expense_report', 'rb_month_end_status', 'rb_pur_pay', 'rb_allocate_payment', 'rb_reverse_supplier_payment',
               'rb_hard_delete_supplier_payment', 'rb_supplier_balances')) loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;
end $$;
grant execute on function
  rb_save_expense(jsonb), rb_approve_expense(bigint), rb_refuse_expense(bigint, text), rb_reverse_expense(bigint, date, text),
  rb_add_expense_photo(bigint, text), rb_expense_photos(bigint), rb_pay_expense_bill(jsonb), rb_save_transfer(jsonb),
  rb_save_partner_entry(jsonb), rb_save_cash_count(jsonb), rb_reverse_cash_entry(text, bigint, date, text),
  rb_hard_delete_cash_entry(text, bigint), rb_save_money_account(jsonb), rb_save_expense_category(jsonb),
  rb_save_cashbank_settings(jsonb), rb_save_absorption_setup(jsonb), rb_set_absorption_method(text, text),
  rb_absorption_preview(date, jsonb, boolean), rb_post_absorption(date, jsonb, boolean), rb_provision_preview(date, boolean),
  rb_post_provision(date, boolean), rb_reverse_month_end(bigint, text), rb_bank_recon(int, date), rb_save_bank_recon(jsonb),
  rb_reopen_bank_recon(int, date, text), rb_money_balances(date), rb_cash_book(int, date, date), rb_partner_balances(date),
  rb_expense_report(date, date), rb_month_end_status(date),
  rb_allocate_payment(bigint, jsonb), rb_reverse_supplier_payment(bigint, date, text), rb_hard_delete_supplier_payment(bigint),
  rb_supplier_balances(date, boolean)
  to authenticated;

-- ---------------------------------------------------------------------
-- 14. DEMO data for Nov 2026: 12 expenses (cash, UPI, bank and on
--     credit, one with GST added to cost, one approved above the limit,
--     one waiting for approval), 2 receipts of other money, a credit
--     bill paid from the bank, cash drawn and banked, a partner's
--     capital and drawings, a day-end cash count with a shortage, and
--     both month-end steps posted for Nov 2026. Only added while the app
--     is in training mode.
-- ---------------------------------------------------------------------

do $$
declare
  v_ds  uuid := (select id from app_users where lower(email) = 'info.ruchibuds@gmail.com');
  v_fc  uuid := coalesce((select id from app_users where email = 'demo.fc@example.com'), (select id from app_users where lower(email) = 'info.ruchibuds@gmail.com'));
  v_acc uuid := coalesce((select id from app_users where email = 'demo.accounts@example.com'), v_fc);
  v_mgr uuid := coalesce((select id from app_users where email = 'demo.manager1@example.com'), v_acc);
  cat jsonb; v_cash int; v_bank int; v_gas int; v_ca int; v_e bigint; v_gasbill bigint; p1 int; p3 int;
begin
  if not (select training_mode from app_settings where id = 1) or exists (select 1 from expenses where is_demo)
     or not exists (select 1 from sales where is_demo) then
    return;
  end if;
  select jsonb_object_agg(name, id) into cat from expense_categories;
  select id into v_cash from money_accounts where account_code = '10010110';
  select id into v_bank from money_accounts where account_code = '10010205';
  select id into v_gas from suppliers where code = 'DEMO-S10';
  select (e->>'id')::int into p1 from app_settings s, jsonb_array_elements(s.partners) with ordinality x(e, n) where s.id = 1 and n = 1;
  select (e->>'id')::int into p3 from app_settings s, jsonb_array_elements(s.partners) with ordinality x(e, n) where s.id = 1 and n = 3;
  -- An accountant's office that bills monthly, for an expense bill on credit.
  insert into suppliers (code, kind, name, phone, credit_days, notes, is_demo)
  values ('DEMO-S11', 'company', 'Mehta & Co, Chartered Accountants (DEMO)', '9820011223', 30, 'Monthly accounting fees', true)
  on conflict (code) do nothing;
  select id into v_ca from suppliers where code = 'DEMO-S11';
  -- A limit, so the approval step can be seen (change or clear it in Settings).
  update app_settings set expense_approval_limit_paise = 1000000 where id = 1 and expense_approval_limit_paise is null;

  -- Partner 1 brings in ₹50,000 of capital by bank.
  if p1 is not null then
    perform rb_cb_partner(jsonb_build_object('kind', 'capital_in', 'entry_date', '2026-11-03', 'partner_id', p1, 'money_account_id', v_bank,
      'amount_paise', 5000000, 'reference', 'NEFT from partner', 'note', 'For the festival season stock (DEMO)'), v_fc, true);
  end if;
  -- Expenses.
  perform rb_cb_save_expense(jsonb_build_object('category_id', cat->'Kitchen rent', 'expense_date', '2026-11-01', 'payee', 'Kitchen landlord (DEMO)',
    'description', 'Kitchen rent for November (DEMO)', 'amount_paise', 600000, 'payment_mode', 'bank', 'money_account_id', v_bank,
    'reference', 'NEFT 551203'), v_acc, true);
  perform rb_cb_save_expense(jsonb_build_object('category_id', cat->'Kitchen electricity and water', 'expense_date', '2026-11-04',
    'payee', 'MSEDCL (DEMO)', 'description', 'Kitchen electricity, October bill (DEMO)', 'bill_no', 'EB-10-4471',
    'amount_paise', 285000, 'payment_mode', 'upi', 'money_account_id', v_bank), v_mgr, true);
  perform rb_cb_save_expense(jsonb_build_object('category_id', cat->'Shop or office electricity and water', 'expense_date', '2026-11-06',
    'payee', 'MSEDCL (DEMO)', 'description', 'Shop electricity, October bill (DEMO)', 'amount_paise', 118000, 'payment_mode', 'upi',
    'money_account_id', v_bank), v_acc, true);
  perform rb_cb_save_expense(jsonb_build_object('category_id', cat->'Transport and delivery', 'expense_date', '2026-11-08',
    'payee', 'Local tempo (DEMO)', 'description', 'Tempo to deliver the Konkan Foods order (DEMO)', 'amount_paise', 65000,
    'payment_mode', 'cash', 'money_account_id', v_cash), v_mgr, true);
  perform rb_cb_transfer(jsonb_build_object('transfer_date', '2026-11-09', 'from_account_id', v_bank, 'to_account_id', v_cash,
    'amount_paise', 500000, 'reference', 'ATM', 'note', 'Cash for kitchen expenses (DEMO)'), v_acc, true);
  perform rb_cb_save_expense(jsonb_build_object('category_id', cat->'Digital advertising', 'expense_date', '2026-11-12',
    'payee', 'Meta Platforms (DEMO)', 'description', 'Instagram ads for the festival offer (DEMO)', 'bill_no', 'FBADS-88123',
    'amount_paise', 200000, 'gst_paise', 36000, 'payment_mode', 'bank', 'money_account_id', v_bank), v_acc, true);
  perform rb_cb_save_expense(jsonb_build_object('category_id', cat->'Kitchen supplies', 'expense_date', '2026-11-14',
    'payee', 'Andheri General Stores (DEMO)', 'description', 'Gloves, hair caps and cleaning liquid (DEMO)', 'amount_paise', 78000,
    'payment_mode', 'cash', 'money_account_id', v_cash), v_mgr, true);
  v_gasbill := rb_cb_save_expense(jsonb_build_object('category_id', cat->'Kitchen gas', 'expense_date', '2026-11-16', 'supplier_id', v_gas,
    'description', 'Two commercial gas cylinders (DEMO)', 'bill_no', 'GA/1187', 'bill_date', '2026-11-16', 'amount_paise', 230000,
    'payment_mode', 'credit'), v_acc, true);
  perform rb_cb_save_expense(jsonb_build_object('category_id', cat->'Scrap and empty cartons sold', 'expense_date', '2026-11-18',
    'payee', 'Raddiwala (DEMO)', 'description', 'Empty cartons and old newspapers sold (DEMO)', 'amount_paise', 30000,
    'payment_mode', 'cash', 'money_account_id', v_cash), v_mgr, true);
  perform rb_cb_save_expense(jsonb_build_object('category_id', cat->'Accounting and audit fees', 'expense_date', '2026-11-20', 'supplier_id', v_ca,
    'description', 'Book-keeping and GST advice, November (DEMO)', 'bill_no', 'MC/26/112', 'bill_date', '2026-11-20', 'amount_paise', 450000,
    'payment_mode', 'credit'), v_acc, true);
  if p3 is not null then
    perform rb_cb_partner(jsonb_build_object('kind', 'drawings', 'entry_date', '2026-11-21', 'partner_id', p3, 'money_account_id', v_bank,
      'amount_paise', 300000, 'reference', 'UPI', 'note', 'Personal use (DEMO)'), v_fc, true);
  end if;
  -- The gas bill is paid from the bank.
  perform rb_pur_pay(jsonb_build_object('supplier_id', v_gas, 'pay_date', '2026-11-24', 'mode', 'bank', 'money_account_id', v_bank,
    'amount_paise', 230000, 'reference', 'UPI 0099812', 'allocations', jsonb_build_array(jsonb_build_object('expense_id', v_gasbill, 'amount_paise', 230000))),
    v_acc, true);
  perform rb_cb_save_expense(jsonb_build_object('category_id', cat->'Kitchen helpers on contract', 'expense_date', '2026-11-25',
    'payee', 'Two helpers for the pickle season (DEMO)', 'description', '6 days each at ₹300 a day (DEMO)', 'amount_paise', 360000,
    'payment_mode', 'cash', 'money_account_id', v_cash), v_mgr, true);
  perform rb_cb_transfer(jsonb_build_object('transfer_date', '2026-11-25', 'from_account_id', v_cash, 'to_account_id', v_bank,
    'amount_paise', 200000, 'reference', 'Deposit slip 3321', 'note', 'Shop takings banked (DEMO)'), v_acc, true);
  -- Kitchen wages: above the limit, entered by the Manager and approved by the FC.
  v_e := rb_cb_save_expense(jsonb_build_object('category_id', cat->'Kitchen wages', 'expense_date', '2026-11-26',
    'payee', 'Kitchen staff (3 cooks) (DEMO)', 'description', 'Wages for November (DEMO)', 'amount_paise', 1800000,
    'payment_mode', 'bank', 'money_account_id', v_bank, 'reference', 'Bank transfer batch 26-11'), v_mgr, true);
  perform rb_cb_post_expense(v_e, v_fc);
  -- Waiting for approval.
  perform rb_cb_save_expense(jsonb_build_object('category_id', cat->'Repairs and maintenance (shop, office)', 'expense_date', '2026-11-27',
    'payee', 'Sai Sign Works (DEMO)', 'description', 'New shop signboard lights (DEMO)', 'bill_no', 'SSW-204',
    'amount_paise', 1250000, 'payment_mode', 'bank', 'money_account_id', v_bank), v_mgr, true);
  perform rb_cb_save_expense(jsonb_build_object('category_id', cat->'Bank charges', 'expense_date', '2026-11-27',
    'payee', 'Bank (DEMO)', 'description', 'SMS and NEFT charges (DEMO)', 'amount_paise', 11800, 'payment_mode', 'bank',
    'money_account_id', v_bank), v_acc, true);
  perform rb_cb_save_expense(jsonb_build_object('category_id', cat->'Bank interest received', 'expense_date', '2026-11-27',
    'payee', 'Bank (DEMO)', 'description', 'Savings interest credited (DEMO)', 'amount_paise', 21200, 'payment_mode', 'bank',
    'money_account_id', v_bank), v_acc, true);
  -- Day-end cash count: ₹40 short.
  perform rb_cb_count(jsonb_build_object('money_account_id', v_cash, 'count_date', '2026-11-27',
    'counted_paise', rb_cb_balance('10010110', '2026-11-27') - 4000, 'reason', 'Change given short at the counter (DEMO)'), v_mgr, true);

  -- Example rates so the DEMO provision shows a figure. They are marked as
  -- examples on the screens until the CA's rates are saved in Settings.
  if not exists (select 1 from jsonb_array_elements((select doubtful_debt_bands from app_settings where id = 1)) b
                 where coalesce((b->>'pct')::numeric, 0) > 0) then
    update app_settings set doubtful_debt_bands =
      '[{"upto":0,"pct":0},{"upto":30,"pct":2},{"upto":90,"pct":10},{"upto":180,"pct":25},{"upto":365,"pct":50},{"upto":null,"pct":100}]',
      doubtful_debt_other_pct = 10, doubtful_debt_rates_example = true,
      doubtful_debt_rates_note = 'Example rates for the DEMO only. Replace them with the CA''s rates.'
    where id = 1;
  end if;
  -- An old unpaid balance brought in at the start (no invoice in the app),
  -- so the DEMO provision has something past due to provide for.
  perform rb_post_engine(jsonb_build_object('journal_date', '2026-10-01', 'source', 'opening', 'event_code', 'opening',
    'narration', 'Opening balance: Hill Top Caterers, unpaid from the August wedding order (DEMO)',
    'department_id', rb_cb_dept('CC003'), 'is_demo', true, 'entered_by', v_acc, 'approved_by', v_fc),
    jsonb_build_array(
      jsonb_build_object('account_code', '10020105', 'debit_paise', 650000, 'customer_id', (select id from customers where code = 'DEMO-C09')),
      jsonb_build_object('account_code', '97010105', 'credit_paise', 650000)));
  -- Both month-end steps for Nov 2026, run by the FC.
  perform rb_cb_post_absorption('2026-11-01', null, true, v_fc);
  perform rb_cb_post_provision('2026-11-01', true, v_fc);
end $$;

-- End of 06_cash_bank.sql
