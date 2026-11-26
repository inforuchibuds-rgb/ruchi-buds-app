-- =====================================================================
-- RUCHI BUDS APP · Module 2: Masters, chart of accounts and ledger
-- File: 02_masters.sql · Version 1.0 · 26-Nov-2026
--
-- What this file sets up:
--   Units, items (raw, prepared / WIP, finished, by-products, packaging),
--   pack types and product packs with prices, customers, suppliers,
--   departments with rename / merge history, the group entity list,
--   the Master chart of accounts (loaded from the Master COA, entity E002),
--   posting rules, the journal engine, manual journals with approval,
--   reversal and learning-phase delete, month lock, trial balance and
--   account ledger.
--
-- Run 01_core_users.sql first. Then: Supabase -> SQL Editor -> New query
-- -> paste this whole file -> Run. It is safe to run again; nothing is
-- lost on a re-run, and your own changes to accounts and rules are kept.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Settings, screens and the new special right
-- ---------------------------------------------------------------------

alter table app_settings add column if not exists manual_journal_second_person boolean not null default true;
alter table app_settings add column if not exists stock_valuation text not null default 'Weighted average'
  check (stock_valuation in ('Weighted average', 'FIFO'));

-- The screens this module brings to life.
update screens set available = true where code in ('masters', 'accounts', 'customers', 'suppliers');

insert into powers (code, name, description, sort) values
  ('departments', 'Rename, merge and delete departments',
   'Rename or merge departments (for all history or from a date), undo those changes, and delete unused departments', 75)
on conflict (code) do update set name = excluded.name, description = excluded.description, sort = excluded.sort;
insert into permissions (code, kind, power_code, sort)
select 'power.' || p.code, 'power', p.code, 10000 + p.sort from powers p
on conflict (code) do nothing;

-- Partners get a fixed number so their capital and current accounts stay
-- linked to the right person even if names change in Settings.
create or replace function rb_partner_ids()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_out jsonb := '[]'; v_e jsonb; v_old jsonb; v_next int; i int := 0; v_id int;
begin
  v_old := case when tg_op = 'UPDATE' then coalesce(old.partners, '[]') else '[]' end;
  select coalesce(max((e->>'id')::int), 0) into v_next
  from jsonb_array_elements(v_old || coalesce(new.partners, '[]')) e where e ? 'id';
  for v_e in select * from jsonb_array_elements(coalesce(new.partners, '[]')) loop
    if not (v_e ? 'id') then
      -- Screens from module 1 do not send the number: keep the one in the same place.
      v_id := (v_old -> i ->> 'id')::int;
      if v_id is null or exists (select 1 from jsonb_array_elements(new.partners) x where (x->>'id')::int = v_id)
         or exists (select 1 from jsonb_array_elements(v_out) x where (x->>'id')::int = v_id) then
        v_next := v_next + 1; v_id := v_next;
      end if;
      v_e := v_e || jsonb_build_object('id', v_id);
    end if;
    v_out := v_out || jsonb_build_array(v_e);
    i := i + 1;
  end loop;
  new.partners := v_out;
  -- A partner who has entries in the books cannot be taken off the list.
  if to_regclass('public.journal_lines') is not null then
    select (o->>'id')::int into v_id
    from jsonb_array_elements(v_old) o
    where not exists (select 1 from jsonb_array_elements(new.partners) n where n->>'id' = o->>'id')
      and exists (select 1 from journal_lines l where l.partner_id = (o->>'id')::int)
    limit 1;
    if v_id is not null then
      raise exception 'Partner % has entries in the books, so they must stay on the list. You can rename them.', v_id;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists rb_partner_ids on app_settings;
create trigger rb_partner_ids before insert or update of partners on app_settings
  for each row execute function rb_partner_ids();
update app_settings set partners = partners where id = 1;  -- give today's partners their numbers

-- ---------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------

-- Group entities (from the Master COA entity register).
create table if not exists entities (
  code          text primary key,
  name          text not null,
  country       text,
  currency      text not null,
  parent_code   text,
  local_gaap    text,
  is_self       boolean not null default false
);

-- Units of measure. Quantities are stored in the base unit of their kind
-- (grams, millilitres, pieces or boxes), so nothing drifts over 5 years.
create table if not exists units (
  code        text primary key,
  name        text not null,
  dimension   text not null check (dimension in ('mass', 'volume', 'piece', 'box')),
  to_base     numeric not null check (to_base > 0),
  sort        int not null default 100,
  is_demo     boolean not null default false
);

-- Items: raw materials, prepared ingredients (WIP), finished goods,
-- by-products and packaging (empty bottles and pouches).
create table if not exists items (
  id               serial primary key,
  code             text not null unique,
  name             text not null,
  kind             text not null check (kind in ('raw', 'wip', 'finished', 'byproduct', 'packaging')),
  base_unit        text not null references units(code),
  buy_unit         text references units(code),
  stages           text[] not null default '{}',     -- preparation stages, wastage recorded at each
  prepared_item_id int references items(id),         -- raw material -> the prepared ingredient it becomes
  shelf_life_days  int check (shelf_life_days > 0),   -- prepared items: warn after this many days
  byproduct_use    text check (byproduct_use in ('sellable', 'discarded')),
  sells_by         text check (sells_by in ('pack', 'weight', 'piece')),
  loose_price_paise bigint check (loose_price_paise >= 0),  -- per kg (or per piece) when sold loose
  hsn_code         text,
  gst_rate         numeric(5,2) check (gst_rate between 0 and 40),
  notes            text,
  is_active        boolean not null default true,
  is_demo          boolean not null default false,
  created_at       timestamptz not null default now(),
  created_by       uuid,
  updated_at       timestamptz,
  updated_by       uuid,
  check (kind = 'byproduct' or byproduct_use is null),
  check (kind in ('finished', 'byproduct') or loose_price_paise is null)
);
create unique index if not exists items_name_key on items (lower(name));

-- Pack types: the bottle or pouch itself (e.g. "200 g bottle").
create table if not exists pack_types (
  id                serial primary key,
  code              text not null unique,
  name              text not null,
  kind              text not null check (kind in ('bottle', 'pouch', 'jar', 'box', 'other')),
  packaging_item_id int references items(id),       -- the empty bottle / pouch held in stock
  is_active         boolean not null default true,
  is_demo           boolean not null default false,
  created_at        timestamptz not null default now(),
  created_by        uuid,
  updated_at        timestamptz,
  updated_by        uuid
);

-- What each finished product holds in each pack, and its prices.
create table if not exists product_packs (
  id                 serial primary key,
  item_id            int not null references items(id),
  pack_type_id       int not null references pack_types(id),
  net_qty            numeric not null check (net_qty > 0),  -- in the product's base unit (grams, ml or pieces)
  retail_price_paise bigint check (retail_price_paise >= 0),
  trader_price_paise bigint check (trader_price_paise >= 0),
  online_price_paise bigint check (online_price_paise >= 0),
  is_active          boolean not null default true,
  is_demo            boolean not null default false,
  created_at         timestamptz not null default now(),
  created_by         uuid,
  updated_at         timestamptz,
  updated_by         uuid,
  unique (item_id, pack_type_id)
);

create table if not exists customers (
  id               serial primary key,
  code             text not null unique,
  kind             text not null check (kind in ('retail', 'trader')),
  name             text not null,
  phone            text,
  send_promotions  boolean not null default false,
  promotions_consent_at timestamptz,
  address          text,
  email            text,
  gstin            text,
  state_code       text,
  contact_person   text,
  credit_limit_paise bigint check (credit_limit_paise >= 0),
  credit_days      int check (credit_days >= 0),
  is_walk_in       boolean not null default false,
  notes            text,
  is_active        boolean not null default true,
  is_demo          boolean not null default false,
  created_at       timestamptz not null default now(),
  created_by       uuid,
  updated_at       timestamptz,
  updated_by       uuid,
  check (send_promotions = false or phone is not null)
);

create table if not exists suppliers (
  id               serial primary key,
  code             text not null unique,
  kind             text not null default 'local' check (kind in ('fisherman', 'farmer', 'local', 'company', 'other')),
  name             text not null,
  phone            text,
  address          text,
  email            text,
  gstin            text,
  state_code       text,
  contact_person   text,
  credit_days      int check (credit_days >= 0),
  usually_no_bill  boolean not null default false,
  notes            text,
  is_active        boolean not null default true,
  is_demo          boolean not null default false,
  created_at       timestamptz not null default now(),
  created_by       uuid,
  updated_at       timestamptz,
  updated_by       uuid
);

-- Departments / cost centres. Original entries are never rewritten:
-- renames and merges are stored as dated events that reports apply.
create table if not exists departments (
  id             serial primary key,
  code           text not null unique,
  original_name  text not null,
  name           text not null,          -- the name for new entries today
  is_active      boolean not null default true,
  merged_into    int references departments(id),
  is_demo        boolean not null default false,
  created_at     timestamptz not null default now(),
  created_by     uuid,
  updated_at     timestamptz,
  updated_by     uuid
);

create table if not exists dept_events (
  id              serial primary key,
  dept_id         int not null references departments(id) on delete cascade,
  kind            text not null check (kind in ('rename', 'merge')),
  new_name        text,
  into_dept_id    int references departments(id),
  effective_from  date,                   -- null = all history
  note            text,
  created_at      timestamptz not null default now(),
  created_by      uuid,
  undone_at       timestamptz,
  undone_by       uuid,
  is_demo         boolean not null default false,
  check ((kind = 'rename' and new_name is not null) or (kind = 'merge' and into_dept_id is not null))
);

-- The chart of accounts: families (non-posting headers) and posting accounts.
create table if not exists accounts (
  code            text primary key check (code ~ '^\d{8}$'),
  name            text not null,
  local_name      text,                  -- optional Ruchi Buds wording, shown instead of the group name
  class           text not null,
  statement       text not null check (statement in ('BS', 'PL', 'CONSOL')),
  normal_balance  text not null check (normal_balance in ('Debit', 'Credit', 'Either')),
  level           text not null check (level in ('family', 'posting')),
  status          text not null default 'Active',
  subledger       text,
  standard        text,                  -- the group's IFRS reference, kept for information only
  e002_active     boolean not null default true,
  cash_flow       text not null default 'operating'
                  check (cash_flow in ('cash', 'operating', 'investing', 'financing', 'non_cash', 'none')),
  control_type    text check (control_type in ('customer', 'supplier', 'item', 'partner', 'intercompany')),
  source          text not null default 'master' check (source in ('master', 'local')),
  family_code     text generated always as (left(code, 6) || '00') stored,
  updated_at      timestamptz,
  updated_by      uuid
);

-- Which account each kind of entry posts to. The Accountant can change
-- a mapping without any code change.
create table if not exists posting_rules (
  event_code    text not null,
  line_key      text not null,
  side          text not null check (side in ('debit', 'credit')),
  account_code  text not null references accounts(code),
  module        int not null,
  label         text not null,
  note          text,
  sort          int not null default 100,
  updated_at    timestamptz,
  updated_by    uuid,
  primary key (event_code, line_key)
);

-- Locked months. A month with no row here is open.
create table if not exists periods (
  month       date primary key check (extract(day from month) = 1),
  is_locked   boolean not null default false,
  locked_at   timestamptz,
  locked_by   uuid,
  note        text,
  updated_at  timestamptz,
  updated_by  uuid
);

create table if not exists journals (
  id             bigserial primary key,
  journal_no     text unique,
  journal_date   date not null,
  entity_code    text not null default 'E002' references entities(code),
  currency       text not null default 'INR',
  source         text not null default 'manual' check (source in
                 ('manual', 'opening', 'reversal', 'purchases', 'stock', 'production', 'sales',
                  'cash_bank', 'loans', 'shop', 'year_end', 'system')),
  event_code     text,
  source_ref     text,
  narration      text not null,
  status         text not null default 'draft' check (status in ('draft', 'posted', 'reversed')),
  reversal_of    bigint references journals(id),
  reversed_by    bigint references journals(id),
  reverse_reason text,
  total_paise    bigint not null default 0,
  entered_by     uuid references app_users(id),
  entered_at     timestamptz not null default now(),
  approved_by    uuid references app_users(id),
  posted_at      timestamptz,
  is_demo        boolean not null default false,
  is_training    boolean not null default false,
  updated_at     timestamptz,
  updated_by     uuid
);
create index if not exists journals_date_idx on journals (journal_date);
create index if not exists journals_status_idx on journals (status);

create table if not exists journal_lines (
  id                  bigserial primary key,
  journal_id          bigint not null references journals(id) on delete cascade,
  line_no             int not null,
  journal_date        date not null,
  account_code        text not null references accounts(code),
  department_id       int not null references departments(id),
  debit_paise         bigint not null default 0 check (debit_paise >= 0),
  credit_paise        bigint not null default 0 check (credit_paise >= 0),
  narration           text,
  customer_id         int references customers(id),
  supplier_id         int references suppliers(id),
  item_id             int references items(id),
  partner_id          int,
  counterparty_entity text references entities(code),
  currency            text not null default 'INR',
  is_demo             boolean not null default false,
  is_training         boolean not null default false,
  check ((debit_paise > 0) <> (credit_paise > 0))
);
create index if not exists journal_lines_journal_idx on journal_lines (journal_id);
create index if not exists journal_lines_account_idx on journal_lines (account_code, journal_date);
create index if not exists journal_lines_customer_idx on journal_lines (customer_id) where customer_id is not null;
create index if not exists journal_lines_supplier_idx on journal_lines (supplier_id) where supplier_id is not null;

-- ---------------------------------------------------------------------
-- 3. Starting data: entities, units, chart of accounts
-- ---------------------------------------------------------------------

insert into entities (code, name, country, currency, parent_code, local_gaap, is_self) values
  ('E001', 'Parent',     'UK',    'GBP', null,   'IFRS',            false),
  ('E002', 'Ruchi Buds', 'India', 'INR', 'E001', 'Indian AS (ICAI)', true),
  ('E005', 'Zochi',      'India', 'INR', 'E001', 'IFRS',            false)
on conflict (code) do update set name = excluded.name, country = excluded.country,
  currency = excluded.currency, parent_code = excluded.parent_code, local_gaap = excluded.local_gaap,
  is_self = excluded.is_self;

insert into units (code, name, dimension, to_base, sort) values
  ('g',   'grams',       'mass',   1,    10),
  ('kg',  'kilograms',   'mass',   1000, 20),
  ('ml',  'millilitres', 'volume', 1,    30),
  ('l',   'litres',      'volume', 1000, 40),
  ('pc',  'pieces',      'piece',  1,    50),
  ('box', 'boxes',       'box',    1,    60)
on conflict (code) do nothing;

-- Family headers (non-posting).
insert into accounts (code, name, class, statement, normal_balance, level, e002_active, cash_flow)
select f.code, f.name, f.class, f.statement, 'Either', 'family', true, 'none'
from (values
  ('10010100','Cash 100101','Asset','BS'),
  ('10010200','Bank 100102','Asset','BS'),
  ('10010300','Settlement 100103','Asset','BS'),
  ('10020100','AR 100201','Asset','BS'),
  ('10020200','AR 100202','Contra Asset','BS'),
  ('10020300','Other receivables 100203','Asset','BS'),
  ('10030100','Inventory 100301','Asset','BS'),
  ('10030200','Inventory 100302','Contra Asset','BS'),
  ('10040100','Prepayment 100401','Asset','BS'),
  ('10040200','Contract 100402','Asset','BS'),
  ('10050100','Tax 100501','Asset','BS'),
  ('10060100','Treasury 100601','Asset','BS'),
  ('10070100','Intercompany 100701','Asset','BS'),
  ('20010100','Fixed assets 200101','Asset','BS'),
  ('20010200','Fixed assets 200102','Contra Asset','BS'),
  ('20020100','Lease 200201','Asset','BS'),
  ('20020200','Lease 200202','Contra Asset','BS'),
  ('20030100','Intangible 200301','Asset','BS'),
  ('20030200','Intangible 200302','Contra Asset','BS'),
  ('20040100','Investment 200401','Asset','BS'),
  ('20050100','Contract 200501','Asset','BS'),
  ('20060100','Intercompany 200601','Asset','BS'),
  ('30010100','AP 300101','Liability','BS'),
  ('30010200','Accrual 300102','Liability','BS'),
  ('30020100','Payroll 300201','Liability','BS'),
  ('30030100','Tax 300301','Liability','BS'),
  ('30040100','Contract 300401','Liability','BS'),
  ('30050100','Commission 300501','Liability','BS'),
  ('30060100','Debt / Lease 300601','Liability','BS'),
  ('30070100','Intercompany 300701','Liability','BS'),
  ('30080100','Settlement 300801','Liability','BS'),
  ('30090100','Provision 300901','Liability','BS'),
  ('40010100','Debt 400101','Liability','BS'),
  ('40020100','Lease 400201','Liability','BS'),
  ('40030100','Tax / Contract 400301','Liability','BS'),
  ('40040100','Provision 400401','Liability','BS'),
  ('40050100','Intercompany 400501','Liability','BS'),
  ('50010100','Equity 500101','Equity','BS'),
  ('50020100','Equity 500201','Equity','BS'),
  ('50030100','Equity 500301','Equity','BS'),
  ('50040100','Consolidation 500401','Equity','BS'),
  ('60010100','Sales 600101','Revenue','PL'),
  ('60020100','Contract 600201','Revenue','PL'),
  ('60030100','Contract 600301','Revenue','PL'),
  ('60040100','Commission 600401','Revenue','PL'),
  ('60050100','Contract 600501','Revenue','PL'),
  ('60060100','Sales 600601','Revenue','PL'),
  ('60070100','Intercompany 600701','Revenue','PL'),
  ('70010100','Inventory 700101','Direct Cost','PL'),
  ('70020100','Payroll 700201','Direct Cost','PL'),
  ('70030100','Costing 700301','Direct Cost','PL'),
  ('70040100','Project 700401','Direct Cost','PL'),
  ('70050100','Settlement 700501','Direct Cost','PL'),
  ('70060100','Contract 700601','Direct Cost','PL'),
  ('70070100','Inventory 700701','Direct Cost','PL'),
  ('70080100','Intercompany 700801','Direct Cost','PL'),
  ('80010100','Payroll 800101','Expense','PL'),
  ('80020100','Expense 800201','Expense','PL'),
  ('80030100','Commission 800301','Expense','PL'),
  ('80040100','Project 800401','Expense','PL'),
  ('80050100','Expense 800501','Expense','PL'),
  ('80060100','Expense 800601','Expense','PL'),
  ('80070100','Fixed assets 800701','Expense','PL'),
  ('80080100','AR 800801','Expense','PL'),
  ('80090100','Intercompany 800901','Expense','PL'),
  ('90010100','Treasury 900101','Other Income','PL'),
  ('91010100','Debt / Lease 910101','Finance Cost','PL'),
  ('92010100','Tax 920101','Tax Expense','PL'),
  ('93010100','Investment 930101','Other PL','PL'),
  ('95010100','Consolidation 950101','Consolidation','CONSOL'),
  ('95020100','Consolidation 950201','Consolidation','CONSOL'),
  ('96010100','Consolidation 960101','Adjustment','CONSOL'),
  ('97010100','Control 970101','Control','BS')
) as f(code, name, class, statement)
on conflict (code) do update set class = excluded.class, statement = excluded.statement;

-- Posting accounts from the Master COA. On a re-run only the group's own
-- columns are refreshed; Ruchi Buds' choices (shown for E002, local name,
-- cash-flow category) are kept.
-- e002_active = false hides accounts that only exist under IFRS (right-of-use
-- assets, expected credit loss, contract assets, OCI reserves, share capital,
-- consolidation-only accounts), because Ruchi Buds reports under Indian AS.
insert into accounts (code, name, class, statement, normal_balance, status, subledger, standard,
                      e002_active, cash_flow, control_type, source, level)
select a.code, a.name, a.class, a.statement, a.normal_balance, a.status, a.subledger, a.standard,
       a.e002_active, a.cash_flow, a.control_type, a.source, 'posting'
from (values
  ('10010105','Petty Cash','Asset','BS','Debit','Active','Cash',null,true,'cash',null,'master'),
  ('10010110','Cash on Hand','Asset','BS','Debit','Active','Cash',null,true,'cash',null,'master'),
  ('10010115','Cash in Transit','Asset','BS','Debit','Active','Cash',null,true,'cash',null,'master'),
  ('10010120','Cash Clearing','Asset','BS','Debit','Active','Cash',null,true,'cash',null,'master'),
  ('10010205','Bank Account 01','Asset','BS','Debit','Active','Bank',null,true,'cash',null,'master'),
  ('10010210','Bank Account 02','Asset','BS','Debit','Active','Bank',null,true,'cash',null,'master'),
  ('10010215','Bank Account 03','Asset','BS','Debit','Active','Bank',null,true,'cash',null,'master'),
  ('10010220','Bank Account 04','Asset','BS','Debit','Active','Bank',null,true,'cash',null,'master'),
  ('10010225','Bank Account 05 - Reserved','Asset','BS','Debit','Active','Bank',null,true,'cash',null,'master'),
  ('10010230','Bank Account 06 - Reserved','Asset','BS','Debit','Active','Bank',null,true,'cash',null,'master'),
  ('10010235','Foreign Currency Bank Account','Asset','BS','Debit','Active','Bank',null,true,'cash',null,'master'),
  ('10010240','Savings Bank Account','Asset','BS','Debit','Active','Bank',null,true,'cash',null,'master'),
  ('10010245','Restricted Bank Account','Asset','BS','Debit','Active','Bank',null,true,'cash',null,'master'),
  ('10010250','Bank Transfer Clearing','Asset','BS','Debit','Active','Bank',null,true,'cash',null,'master'),
  ('10010255','Bank Reconciliation Suspense','Asset','BS','Debit','Active','Bank',null,true,'cash',null,'master'),
  ('10010305','Payment Gateway Clearing','Asset','BS','Debit','Active','Settlement','IFRS 9',true,'operating',null,'master'),
  ('10010310','Card Acquirer Clearing','Asset','BS','Debit','Active','Settlement','IFRS 9',true,'operating',null,'master'),
  ('10010315','Digital Wallet Clearing','Asset','BS','Debit','Active','Settlement','IFRS 9',true,'operating',null,'master'),
  ('10010320','Collection Agent Clearing','Asset','BS','Debit','Active','Settlement','IFRS 9',true,'operating',null,'master'),
  ('10010325','Settlement Receivable','Asset','BS','Debit','Active','Settlement','IFRS 9',true,'operating',null,'master'),
  ('10010330','Settlement Suspense','Asset','BS','Debit','Active','Settlement','IFRS 9',true,'operating',null,'master'),
  ('10010335','Cash in Escrow','Asset','BS','Debit','Active','Settlement','IFRS 9',true,'operating',null,'master'),
  ('10020105','Trade Receivables Control','Asset','BS','Debit','Active','AR','IFRS 9 / IFRS 15',true,'operating','customer','master'),
  ('10020110','Unbilled Receivables','Asset','BS','Debit','Active','AR','IFRS 9 / IFRS 15',true,'operating',null,'master'),
  ('10020115','Notes Receivable','Asset','BS','Debit','Active','AR','IFRS 9 / IFRS 15',true,'operating',null,'master'),
  ('10020120','Receivables Retention','Asset','BS','Debit','Active','AR','IFRS 9 / IFRS 15',true,'operating',null,'master'),
  ('10020125','Receivable from Agents','Asset','BS','Debit','Active','AR','IFRS 9 / IFRS 15',true,'operating',null,'master'),
  ('10020130','Receivable from Payment Processors','Asset','BS','Debit','Active','AR','IFRS 9 / IFRS 15',true,'operating',null,'master'),
  ('10020135','Other Trade Receivables','Asset','BS','Debit','Active','AR','IFRS 9 / IFRS 15',true,'operating',null,'master'),
  ('10020205','Expected Credit Loss Allowance - Trade','Contra Asset','BS','Credit','Active','AR','IFRS 9',false,'operating',null,'master'),
  ('10020210','Expected Credit Loss Allowance - Other','Contra Asset','BS','Credit','Active','AR','IFRS 9',false,'operating',null,'master'),
  ('10020215','Receivables Write-off Clearing','Contra Asset','BS','Credit','Active','AR','IFRS 9',true,'operating',null,'master'),
  ('10020220','Factored Receivables Control','Contra Asset','BS','Credit','Active','AR','IFRS 9',true,'operating',null,'master'),
  ('10020305','Employee Advances','Asset','BS','Debit','Active','Other receivables',null,true,'operating',null,'master'),
  ('10020310','Supplier Advances','Asset','BS','Debit','Active','Other receivables',null,true,'operating',null,'master'),
  ('10020315','Refund Receivables','Asset','BS','Debit','Active','Other receivables',null,true,'operating',null,'master'),
  ('10020320','Insurance Claims Receivable','Asset','BS','Debit','Active','Other receivables',null,true,'operating',null,'master'),
  ('10020325','Interest Receivable','Asset','BS','Debit','Active','Other receivables',null,true,'operating',null,'master'),
  ('10020330','Other Receivables','Asset','BS','Debit','Active','Other receivables',null,true,'operating',null,'master'),
  ('10020335','Security Deposits - Current','Asset','BS','Debit','Active','Other receivables',null,true,'operating',null,'master'),
  ('10030105','Raw Materials Inventory','Asset','BS','Debit','Active','Inventory','IAS 2',true,'operating','item','master'),
  ('10030110','Packaging Materials Inventory','Asset','BS','Debit','Active','Inventory','IAS 2',true,'operating','item','master'),
  ('10030115','Consumables Inventory','Asset','BS','Debit','Active','Inventory','IAS 2',true,'operating','item','master'),
  ('10030120','Work in Progress Inventory','Asset','BS','Debit','Active','Inventory','IAS 2',true,'operating','item','master'),
  ('10030125','Finished Goods Inventory','Asset','BS','Debit','Active','Inventory','IAS 2',true,'operating','item','master'),
  ('10030130','Merchandise Inventory','Asset','BS','Debit','Active','Inventory','IAS 2',true,'operating',null,'master'),
  ('10030135','Goods in Transit','Asset','BS','Debit','Active','Inventory','IAS 2',true,'operating',null,'master'),
  ('10030140','Goods Held by Third Parties','Asset','BS','Debit','Active','Inventory','IAS 2',true,'operating',null,'master'),
  ('10030145','Inventory Returns','Asset','BS','Debit','Active','Inventory','IAS 2',true,'operating',null,'master'),
  ('10030150','Inventory Samples','Asset','BS','Debit','Active','Inventory','IAS 2',true,'operating',null,'master'),
  ('10030155','Spare Parts Inventory','Asset','BS','Debit','Active','Inventory','IAS 2',true,'operating',null,'master'),
  ('10030205','Inventory Obsolescence Allowance','Contra Asset','BS','Credit','Active','Inventory','IAS 2',true,'operating',null,'master'),
  ('10030210','Inventory Shrinkage Allowance','Contra Asset','BS','Credit','Active','Inventory','IAS 2',true,'operating',null,'master'),
  ('10030215','Inventory Valuation Adjustment','Contra Asset','BS','Credit','Active','Inventory','IAS 2',true,'operating',null,'master'),
  ('10030220','Standard Cost Variance Clearing','Contra Asset','BS','Credit','Active','Inventory','IAS 2',true,'operating',null,'master'),
  ('10030225','Inventory Receipt Clearing','Contra Asset','BS','Credit','Active','Inventory','IAS 2',true,'operating',null,'master'),
  ('10030230','Inventory Issue Clearing','Contra Asset','BS','Credit','Active','Inventory','IAS 2',true,'operating',null,'master'),
  ('10040105','Prepaid Insurance','Asset','BS','Debit','Active','Prepayment',null,true,'operating',null,'master'),
  ('10040110','Prepaid Rent','Asset','BS','Debit','Active','Prepayment',null,true,'operating',null,'master'),
  ('10040115','Prepaid Software','Asset','BS','Debit','Active','Prepayment',null,true,'operating',null,'master'),
  ('10040120','Prepaid Maintenance','Asset','BS','Debit','Active','Prepayment',null,true,'operating',null,'master'),
  ('10040125','Prepaid Marketing','Asset','BS','Debit','Active','Prepayment',null,true,'operating',null,'master'),
  ('10040130','Prepaid Subscriptions','Asset','BS','Debit','Active','Prepayment',null,true,'operating',null,'master'),
  ('10040135','Other Prepayments','Asset','BS','Debit','Active','Prepayment',null,true,'operating',null,'master'),
  ('10040205','Contract Assets - Current','Asset','BS','Debit','Active','Contract','IFRS 15',false,'operating',null,'master'),
  ('10040210','Capitalised Contract Acquisition Costs - Current','Asset','BS','Debit','Active','Contract','IFRS 15',false,'operating',null,'master'),
  ('10040215','Capitalised Contract Fulfilment Costs - Current','Asset','BS','Debit','Active','Contract','IFRS 15',false,'operating',null,'master'),
  ('10040220','Accrued Revenue','Asset','BS','Debit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('10040225','Deferred Contract Costs - Current','Asset','BS','Debit','Active','Contract','IFRS 15',false,'operating',null,'master'),
  ('10050105','Input VAT/GST Recoverable','Asset','BS','Debit','Active','Tax','IAS 12 / local',true,'operating',null,'master'),
  ('10050110','VAT/GST Refund Receivable','Asset','BS','Debit','Active','Tax','IAS 12 / local',true,'operating',null,'master'),
  ('10050115','Customs Duty Recoverable','Asset','BS','Debit','Active','Tax','IAS 12 / local',true,'operating',null,'master'),
  ('10050120','Withholding Tax Recoverable','Asset','BS','Debit','Active','Tax','IAS 12 / local',true,'operating',null,'master'),
  ('10050125','Income Tax Prepayment','Asset','BS','Debit','Active','Tax','IAS 12 / local',true,'operating',null,'master'),
  ('10050130','Other Indirect Tax Recoverable','Asset','BS','Debit','Active','Tax','IAS 12 / local',true,'operating',null,'master'),
  ('10050135','Tax Settlement Clearing','Asset','BS','Debit','Active','Tax','IAS 12 / local',true,'operating',null,'master'),
  ('10060105','Short-term Deposits','Asset','BS','Debit','Active','Treasury','IFRS 9',true,'investing',null,'master'),
  ('10060110','Short-term Investments - Amortised Cost','Asset','BS','Debit','Active','Treasury','IFRS 9',true,'investing',null,'master'),
  ('10060115','Short-term Investments - FVPL','Asset','BS','Debit','Active','Treasury','IFRS 9',false,'investing',null,'master'),
  ('10060120','Short-term Investments - FVOCI','Asset','BS','Debit','Active','Treasury','IFRS 9',false,'investing',null,'master'),
  ('10060125','Derivative Assets - Current','Asset','BS','Debit','Active','Treasury','IFRS 9',false,'investing',null,'master'),
  ('10060130','Margin Deposits - Current','Asset','BS','Debit','Active','Treasury','IFRS 9',true,'investing',null,'master'),
  ('10070105','Intercompany Trade Receivables - Current','Asset','BS','Debit','Active','Intercompany','IFRS 10',true,'operating','intercompany','master'),
  ('10070110','Intercompany Loan Receivables - Current','Asset','BS','Debit','Active','Intercompany','IFRS 10',true,'investing','intercompany','master'),
  ('10070115','Intercompany Interest Receivable','Asset','BS','Debit','Active','Intercompany','IFRS 10',true,'operating','intercompany','master'),
  ('10070120','Intercompany Settlement Clearing','Asset','BS','Debit','Active','Intercompany','IFRS 10',true,'operating','intercompany','master'),
  ('20010105','Land','Asset','BS','Debit','Active','Fixed assets','IAS 16',true,'investing',null,'master'),
  ('20010110','Buildings','Asset','BS','Debit','Active','Fixed assets','IAS 16',true,'investing',null,'master'),
  ('20010115','Leasehold Improvements','Asset','BS','Debit','Active','Fixed assets','IAS 16',true,'investing',null,'master'),
  ('20010120','Plant and Machinery','Asset','BS','Debit','Active','Fixed assets','IAS 16',true,'investing',null,'master'),
  ('20010125','Production Equipment','Asset','BS','Debit','Active','Fixed assets','IAS 16',true,'investing',null,'master'),
  ('20010130','Office Equipment','Asset','BS','Debit','Active','Fixed assets','IAS 16',true,'investing',null,'master'),
  ('20010135','Computer Equipment','Asset','BS','Debit','Active','Fixed assets','IAS 16',true,'investing',null,'master'),
  ('20010140','Furniture and Fixtures','Asset','BS','Debit','Active','Fixed assets','IAS 16',true,'investing',null,'master'),
  ('20010145','Vehicles and Transport Equipment','Asset','BS','Debit','Active','Fixed assets','IAS 16',true,'investing',null,'master'),
  ('20010150','Tools and Instruments','Asset','BS','Debit','Active','Fixed assets','IAS 16',true,'investing',null,'master'),
  ('20010155','Capital Work in Progress','Asset','BS','Debit','Active','Fixed assets','IAS 16',true,'investing',null,'master'),
  ('20010160','Assets Under Installation','Asset','BS','Debit','Active','Fixed assets','IAS 16',true,'investing',null,'master'),
  ('20010165','Other Tangible Assets','Asset','BS','Debit','Active','Fixed assets','IAS 16',true,'investing',null,'master'),
  ('20010205','Accumulated Depreciation - Buildings','Contra Asset','BS','Credit','Active','Fixed assets','IAS 16 / IAS 36',true,'investing',null,'master'),
  ('20010210','Accumulated Depreciation - Plant','Contra Asset','BS','Credit','Active','Fixed assets','IAS 16 / IAS 36',true,'investing',null,'master'),
  ('20010215','Accumulated Depreciation - Equipment','Contra Asset','BS','Credit','Active','Fixed assets','IAS 16 / IAS 36',true,'investing',null,'master'),
  ('20010220','Accumulated Depreciation - Improvements','Contra Asset','BS','Credit','Active','Fixed assets','IAS 16 / IAS 36',true,'investing',null,'master'),
  ('20010225','Accumulated Depreciation - Transport','Contra Asset','BS','Credit','Active','Fixed assets','IAS 16 / IAS 36',true,'investing',null,'master'),
  ('20010230','Accumulated Depreciation - Other','Contra Asset','BS','Credit','Active','Fixed assets','IAS 16 / IAS 36',true,'investing',null,'master'),
  ('20010235','PPE Impairment Allowance','Contra Asset','BS','Credit','Active','Fixed assets','IAS 16 / IAS 36',true,'investing',null,'master'),
  ('20020105','Right-of-use Assets - Property','Asset','BS','Debit','Active','Lease','IFRS 16',false,'investing',null,'master'),
  ('20020110','Right-of-use Assets - Equipment','Asset','BS','Debit','Active','Lease','IFRS 16',false,'investing',null,'master'),
  ('20020115','Right-of-use Assets - Transport','Asset','BS','Debit','Active','Lease','IFRS 16',false,'investing',null,'master'),
  ('20020120','Right-of-use Assets - Other','Asset','BS','Debit','Active','Lease','IFRS 16',false,'investing',null,'master'),
  ('20020125','ROU Asset Adjustments','Asset','BS','Debit','Active','Lease','IFRS 16',false,'investing',null,'master'),
  ('20020205','Accumulated Depreciation - ROU Property','Contra Asset','BS','Credit','Active','Lease','IFRS 16',false,'investing',null,'master'),
  ('20020210','Accumulated Depreciation - ROU Equipment','Contra Asset','BS','Credit','Active','Lease','IFRS 16',false,'investing',null,'master'),
  ('20020215','Accumulated Depreciation - ROU Transport','Contra Asset','BS','Credit','Active','Lease','IFRS 16',false,'investing',null,'master'),
  ('20020220','Accumulated Depreciation - ROU Other','Contra Asset','BS','Credit','Active','Lease','IFRS 16',false,'investing',null,'master'),
  ('20020225','ROU Impairment Allowance','Contra Asset','BS','Credit','Active','Lease','IFRS 16',false,'investing',null,'master'),
  ('20030105','Purchased Software','Asset','BS','Debit','Active','Intangible','IAS 38 / IFRS 3',true,'investing',null,'master'),
  ('20030110','Internally Developed Software','Asset','BS','Debit','Active','Intangible','IAS 38 / IFRS 3',true,'investing',null,'master'),
  ('20030115','Capitalised Development Costs','Asset','BS','Debit','Active','Intangible','IAS 38 / IFRS 3',true,'investing',null,'master'),
  ('20030120','Licences and Rights','Asset','BS','Debit','Active','Intangible','IAS 38 / IFRS 3',true,'investing',null,'master'),
  ('20030125','Patents and Intellectual Property','Asset','BS','Debit','Active','Intangible','IAS 38 / IFRS 3',true,'investing',null,'master'),
  ('20030130','Customer Relationships','Asset','BS','Debit','Active','Intangible','IAS 38 / IFRS 3',true,'investing',null,'master'),
  ('20030135','Brands and Trademarks','Asset','BS','Debit','Active','Intangible','IAS 38 / IFRS 3',true,'investing',null,'master'),
  ('20030140','Goodwill','Asset','BS','Debit','Active','Intangible','IAS 38 / IFRS 3',true,'investing',null,'master'),
  ('20030145','Intangibles Under Development','Asset','BS','Debit','Active','Intangible','IAS 38 / IFRS 3',true,'investing',null,'master'),
  ('20030205','Accumulated Amortisation - Software','Contra Asset','BS','Credit','Active','Intangible','IAS 38 / IAS 36',true,'investing',null,'master'),
  ('20030210','Accumulated Amortisation - Development','Contra Asset','BS','Credit','Active','Intangible','IAS 38 / IAS 36',true,'investing',null,'master'),
  ('20030215','Accumulated Amortisation - Licences','Contra Asset','BS','Credit','Active','Intangible','IAS 38 / IAS 36',true,'investing',null,'master'),
  ('20030220','Accumulated Amortisation - Other','Contra Asset','BS','Credit','Active','Intangible','IAS 38 / IAS 36',true,'investing',null,'master'),
  ('20030225','Intangible Impairment Allowance','Contra Asset','BS','Credit','Active','Intangible','IAS 38 / IAS 36',true,'investing',null,'master'),
  ('20030230','Goodwill Impairment','Contra Asset','BS','Credit','Active','Intangible','IAS 38 / IAS 36',true,'investing',null,'master'),
  ('20040105','Long-term Deposits','Asset','BS','Debit','Active','Investment','IFRS 9 / IAS 28',true,'investing',null,'master'),
  ('20040110','Long-term Investments - Amortised Cost','Asset','BS','Debit','Active','Investment','IFRS 9 / IAS 28',true,'investing',null,'master'),
  ('20040115','Long-term Investments - FVPL','Asset','BS','Debit','Active','Investment','IFRS 9 / IAS 28',false,'investing',null,'master'),
  ('20040120','Long-term Investments - FVOCI','Asset','BS','Debit','Active','Investment','IFRS 9 / IAS 28',false,'investing',null,'master'),
  ('20040125','Investment in Subsidiaries','Asset','BS','Debit','Active','Investment','IFRS 9 / IAS 28',false,'investing',null,'master'),
  ('20040130','Investment in Associates','Asset','BS','Debit','Active','Investment','IFRS 9 / IAS 28',false,'investing',null,'master'),
  ('20040135','Investment in Joint Ventures','Asset','BS','Debit','Active','Investment','IFRS 9 / IAS 28',false,'investing',null,'master'),
  ('20040140','Long-term Loan Receivables','Asset','BS','Debit','Active','Investment','IFRS 9 / IAS 28',true,'investing',null,'master'),
  ('20040145','Derivative Assets - Non-current','Asset','BS','Debit','Active','Investment','IFRS 9 / IAS 28',false,'investing',null,'master'),
  ('20050105','Deferred Tax Assets','Asset','BS','Debit','Active','Contract','IAS 12 / IFRS 15',true,'operating',null,'master'),
  ('20050110','Long-term Contract Assets','Asset','BS','Debit','Active','Contract','IAS 12 / IFRS 15',false,'investing',null,'master'),
  ('20050115','Capitalised Contract Acquisition Costs - Non-current','Asset','BS','Debit','Active','Contract','IAS 12 / IFRS 15',false,'investing',null,'master'),
  ('20050120','Capitalised Contract Fulfilment Costs - Non-current','Asset','BS','Debit','Active','Contract','IAS 12 / IFRS 15',false,'investing',null,'master'),
  ('20050125','Long-term Prepayments','Asset','BS','Debit','Active','Contract','IAS 12 / IFRS 15',true,'operating',null,'master'),
  ('20050130','Long-term Security Deposits','Asset','BS','Debit','Active','Contract','IAS 12 / IFRS 15',true,'investing',null,'master'),
  ('20060105','Intercompany Loans Receivable - Non-current','Asset','BS','Debit','Active','Intercompany','IFRS 10',true,'investing','intercompany','master'),
  ('20060110','Intercompany Investments','Asset','BS','Debit','Active','Intercompany','IFRS 10',true,'investing','intercompany','master'),
  ('20060115','Other Intercompany Non-current Receivables','Asset','BS','Debit','Active','Intercompany','IFRS 10',true,'investing','intercompany','master'),
  ('30010105','Trade Payables Control','Liability','BS','Credit','Active','AP',null,true,'operating','supplier','master'),
  ('30010110','Accrued Purchases','Liability','BS','Credit','Active','AP',null,true,'operating',null,'master'),
  ('30010115','Goods Received Not Invoiced','Liability','BS','Credit','Active','AP',null,true,'operating',null,'master'),
  ('30010120','Supplier Retentions Payable','Liability','BS','Credit','Active','AP',null,true,'operating',null,'master'),
  ('30010125','Refunds Payable','Liability','BS','Credit','Active','AP',null,true,'operating',null,'master'),
  ('30010130','Other Trade Payables','Liability','BS','Credit','Active','AP',null,true,'operating',null,'master'),
  ('30010205','Accrued Operating Expenses','Liability','BS','Credit','Active','Accrual',null,true,'operating',null,'master'),
  ('30010210','Accrued Professional Fees','Liability','BS','Credit','Active','Accrual',null,true,'operating',null,'master'),
  ('30010215','Accrued Utilities','Liability','BS','Credit','Active','Accrual',null,true,'operating',null,'master'),
  ('30010220','Accrued Marketing','Liability','BS','Credit','Active','Accrual',null,true,'operating',null,'master'),
  ('30010225','Accrued Interest','Liability','BS','Credit','Active','Accrual',null,true,'operating',null,'master'),
  ('30010230','Other Accruals','Liability','BS','Credit','Active','Accrual',null,true,'operating',null,'master'),
  ('30020105','Salaries Payable','Liability','BS','Credit','Active','Payroll','IAS 19',true,'operating',null,'master'),
  ('30020110','Wages Payable','Liability','BS','Credit','Active','Payroll','IAS 19',true,'operating',null,'master'),
  ('30020115','Bonus Payable','Liability','BS','Credit','Active','Payroll','IAS 19',true,'operating',null,'master'),
  ('30020120','Holiday Pay Accrual','Liability','BS','Credit','Active','Payroll','IAS 19',true,'operating',null,'master'),
  ('30020125','Employee Reimbursements Payable','Liability','BS','Credit','Active','Payroll','IAS 19',true,'operating',null,'master'),
  ('30020130','Pension Contributions Payable','Liability','BS','Credit','Active','Payroll','IAS 19',true,'operating',null,'master'),
  ('30020135','Payroll Taxes Payable','Liability','BS','Credit','Active','Payroll','IAS 19',true,'operating',null,'master'),
  ('30020140','Employee Benefits Payable','Liability','BS','Credit','Active','Payroll','IAS 19',true,'operating',null,'master'),
  ('30020145','Termination Benefits Payable','Liability','BS','Credit','Active','Payroll','IAS 19',true,'operating',null,'master'),
  ('30030105','Output VAT/GST Payable','Liability','BS','Credit','Active','Tax','IAS 12 / local',true,'operating',null,'master'),
  ('30030110','VAT/GST Net Settlement','Liability','BS','Credit','Active','Tax','IAS 12 / local',true,'operating',null,'master'),
  ('30030115','Sales Tax Payable','Liability','BS','Credit','Active','Tax','IAS 12 / local',true,'operating',null,'master'),
  ('30030120','Withholding Tax Payable','Liability','BS','Credit','Active','Tax','IAS 12 / local',true,'operating',null,'master'),
  ('30030125','Payroll Withholding Payable','Liability','BS','Credit','Active','Tax','IAS 12 / local',true,'operating',null,'master'),
  ('30030130','Customs Duty Payable','Liability','BS','Credit','Active','Tax','IAS 12 / local',true,'operating',null,'master'),
  ('30030135','Other Indirect Taxes Payable','Liability','BS','Credit','Active','Tax','IAS 12 / local',true,'operating',null,'master'),
  ('30030140','Current Income Tax Payable','Liability','BS','Credit','Active','Tax','IAS 12 / local',true,'operating',null,'master'),
  ('30040105','Customer Deposits','Liability','BS','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('30040110','Customer Advances','Liability','BS','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('30040115','Deferred Revenue - Goods','Liability','BS','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('30040120','Deferred Revenue - Services','Liability','BS','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('30040125','Deferred Subscription Revenue','Liability','BS','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('30040130','Contract Liabilities - Current','Liability','BS','Credit','Active','Contract','IFRS 15',false,'operating',null,'master'),
  ('30040135','Gift Voucher Liabilities','Liability','BS','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('30040140','Customer Loyalty Liabilities','Liability','BS','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('30040145','Customer Refund Liabilities','Liability','BS','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('30050105','Accrued Lead Generation Fees','Liability','BS','Credit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('30050110','Accrued Conversion Commissions','Liability','BS','Credit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('30050115','Accrued Referral Commissions','Liability','BS','Credit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('30050120','Accrued Affiliate Commissions','Liability','BS','Credit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('30050125','Commission Payables Control','Liability','BS','Credit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('30050130','Commission Chargeback Provision','Liability','BS','Credit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('30060105','Bank Overdraft','Liability','BS','Credit','Active','Debt / Lease','IFRS 16 / IFRS 9',true,'financing',null,'master'),
  ('30060110','Short-term Bank Borrowings','Liability','BS','Credit','Active','Debt / Lease','IFRS 16 / IFRS 9',true,'financing',null,'master'),
  ('30060115','Current Portion of Long-term Debt','Liability','BS','Credit','Active','Debt / Lease','IFRS 16 / IFRS 9',true,'financing',null,'master'),
  ('30060120','Current Finance Lease Liability - Legacy/Local','Liability','BS','Credit','Active','Debt / Lease','IFRS 16 / IFRS 9',true,'financing',null,'master'),
  ('30060125','Current Lease Liability - IFRS 16','Liability','BS','Credit','Active','Debt / Lease','IFRS 16 / IFRS 9',false,'financing',null,'master'),
  ('30060130','Interest Payable','Liability','BS','Credit','Active','Debt / Lease','IFRS 16 / IFRS 9',true,'financing',null,'master'),
  ('30060135','Other Short-term Financing','Liability','BS','Credit','Active','Debt / Lease','IFRS 16 / IFRS 9',true,'financing',null,'master'),
  ('30070105','Intercompany Trade Payables - Current','Liability','BS','Credit','Active','Intercompany','IFRS 10',true,'operating','intercompany','master'),
  ('30070110','Intercompany Loan Payables - Current','Liability','BS','Credit','Active','Intercompany','IFRS 10',true,'financing','intercompany','master'),
  ('30070115','Intercompany Interest Payable','Liability','BS','Credit','Active','Intercompany','IFRS 10',true,'operating','intercompany','master'),
  ('30070120','Intercompany Settlement Payable','Liability','BS','Credit','Active','Intercompany','IFRS 10',true,'operating','intercompany','master'),
  ('30080105','Client Funds Held - Liability','Liability','BS','Credit','Active','Settlement','IFRS 9 / regulatory',false,'operating',null,'master'),
  ('30080110','Customer Funds Held - Liability','Liability','BS','Credit','Active','Settlement','IFRS 9 / regulatory',false,'operating',null,'master'),
  ('30080115','Merchant Funds Payable','Liability','BS','Credit','Active','Settlement','IFRS 9 / regulatory',false,'operating',null,'master'),
  ('30080120','Settlement Payables','Liability','BS','Credit','Active','Settlement','IFRS 9 / regulatory',true,'operating',null,'master'),
  ('30080125','Safeguarded Funds Liability','Liability','BS','Credit','Active','Settlement','IFRS 9 / regulatory',false,'operating',null,'master'),
  ('30080130','Unallocated Customer Receipts','Liability','BS','Credit','Active','Settlement','IFRS 9 / regulatory',true,'operating',null,'master'),
  ('30080135','Chargeback Payable','Liability','BS','Credit','Active','Settlement','IFRS 9 / regulatory',true,'operating',null,'master'),
  ('30080140','Payment Processor Clearing Liability','Liability','BS','Credit','Active','Settlement','IFRS 9 / regulatory',true,'operating',null,'master'),
  ('30090105','Warranty Provision - Current','Liability','BS','Credit','Active','Provision','IAS 37',true,'operating',null,'master'),
  ('30090110','Legal Provision - Current','Liability','BS','Credit','Active','Provision','IAS 37',true,'operating',null,'master'),
  ('30090115','Restructuring Provision - Current','Liability','BS','Credit','Active','Provision','IAS 37',true,'operating',null,'master'),
  ('30090120','Onerous Contract Provision - Current','Liability','BS','Credit','Active','Provision','IAS 37',true,'operating',null,'master'),
  ('30090125','Other Provisions - Current','Liability','BS','Credit','Active','Provision','IAS 37',true,'operating',null,'master'),
  ('40010105','Long-term Bank Loans','Liability','BS','Credit','Active','Debt','IFRS 9',true,'financing',null,'master'),
  ('40010110','Other Long-term Borrowings','Liability','BS','Credit','Active','Debt','IFRS 9',true,'financing',null,'master'),
  ('40010115','Bonds and Notes Payable','Liability','BS','Credit','Active','Debt','IFRS 9',true,'financing',null,'master'),
  ('40010120','Related-party Loans - Non-current','Liability','BS','Credit','Active','Debt','IFRS 9',true,'financing',null,'master'),
  ('40010125','Loan Arrangement Costs - Contra Liability','Liability','BS','Credit','Active','Debt','IFRS 9',true,'financing',null,'master'),
  ('40020105','Lease Liability - IFRS 16 Non-current','Liability','BS','Credit','Active','Lease','IFRS 16',false,'financing',null,'master'),
  ('40020110','Finance Lease Liability - Legacy/Local Non-current','Liability','BS','Credit','Active','Lease','IFRS 16',true,'financing',null,'master'),
  ('40020115','Lease Restoration Provision','Liability','BS','Credit','Active','Lease','IFRS 16',true,'financing',null,'master'),
  ('40020120','Lease Incentive Liability - Local GAAP','Liability','BS','Credit','Active','Lease','IFRS 16',true,'financing',null,'master'),
  ('40030105','Deferred Tax Liabilities','Liability','BS','Credit','Active','Tax / Contract','IAS 12 / IAS 19',true,'operating',null,'master'),
  ('40030110','Long-term Contract Liabilities','Liability','BS','Credit','Active','Tax / Contract','IAS 12 / IAS 19',false,'operating',null,'master'),
  ('40030115','Long-term Customer Deposits','Liability','BS','Credit','Active','Tax / Contract','IAS 12 / IAS 19',true,'operating',null,'master'),
  ('40030120','Long-term Employee Benefit Liabilities','Liability','BS','Credit','Active','Tax / Contract','IAS 12 / IAS 19',true,'operating',null,'master'),
  ('40030125','Other Long-term Payables','Liability','BS','Credit','Active','Tax / Contract','IAS 12 / IAS 19',true,'operating',null,'master'),
  ('40040105','Warranty Provision - Non-current','Liability','BS','Credit','Active','Provision','IAS 37',true,'operating',null,'master'),
  ('40040110','Legal Provision - Non-current','Liability','BS','Credit','Active','Provision','IAS 37',true,'operating',null,'master'),
  ('40040115','Asset Retirement Obligation','Liability','BS','Credit','Active','Provision','IAS 37',true,'operating',null,'master'),
  ('40040120','Onerous Contract Provision - Non-current','Liability','BS','Credit','Active','Provision','IAS 37',true,'operating',null,'master'),
  ('40040125','Other Provisions - Non-current','Liability','BS','Credit','Active','Provision','IAS 37',true,'operating',null,'master'),
  ('40050105','Intercompany Loans Payable - Non-current','Liability','BS','Credit','Active','Intercompany','IFRS 10',true,'financing','intercompany','master'),
  ('40050110','Other Intercompany Non-current Liabilities','Liability','BS','Credit','Active','Intercompany','IFRS 10',true,'financing','intercompany','master'),
  ('50010105','Ordinary Share Capital','Equity','BS','Credit','Active','Equity','IAS 32',false,'financing',null,'master'),
  ('50010110','Preference Share Capital','Equity','BS','Credit','Active','Equity','IAS 32',false,'financing',null,'master'),
  ('50010115','Share Premium','Equity','BS','Credit','Active','Equity','IAS 32',false,'financing',null,'master'),
  ('50010120','Capital Contributions','Equity','BS','Credit','Active','Equity','IAS 32',true,'financing',null,'master'),
  ('50010125','Treasury Shares - Contra Equity','Equity','BS','Credit','Active','Equity','IAS 32',false,'financing',null,'master'),
  ('50010130','Partners Capital','Equity','BS','Credit','Active','Equity','IAS 32',true,'financing','partner','master'),
  ('50010135','Partners Current Account','Equity','BS','Credit','Active','Equity','IAS 32',true,'financing','partner','master'),
  ('50020105','Retained Earnings - Opening','Equity','BS','Credit','Active','Equity','IAS 1',true,'none',null,'master'),
  ('50020110','Current Year Profit or Loss','Equity','BS','Credit','Active','Equity','IAS 1',true,'none',null,'master'),
  ('50020115','Prior Period Adjustments','Equity','BS','Credit','Active','Equity','IAS 1',true,'none',null,'master'),
  ('50020120','Dividends Declared','Equity','BS','Credit','Active','Equity','IAS 1',false,'financing',null,'master'),
  ('50020125','Distributions to Owners','Equity','BS','Credit','Active','Equity','IAS 1',true,'financing',null,'master'),
  ('50020130','Statutory Reserves','Equity','BS','Credit','Active','Equity','IAS 1',true,'financing',null,'master'),
  ('50020135','General Reserves','Equity','BS','Credit','Active','Equity','IAS 1',true,'financing',null,'master'),
  ('50030105','Foreign Currency Translation Reserve','Equity','BS','Credit','Active','Equity','IAS 21 / IFRS 9',false,'none',null,'master'),
  ('50030110','FVOCI Reserve','Equity','BS','Credit','Active','Equity','IAS 21 / IFRS 9',false,'none',null,'master'),
  ('50030115','Cash Flow Hedge Reserve','Equity','BS','Credit','Active','Equity','IAS 21 / IFRS 9',false,'none',null,'master'),
  ('50030120','Revaluation Surplus','Equity','BS','Credit','Active','Equity','IAS 21 / IFRS 9',true,'none',null,'master'),
  ('50030125','Actuarial Remeasurement Reserve','Equity','BS','Credit','Active','Equity','IAS 21 / IFRS 9',false,'none',null,'master'),
  ('50030130','Other OCI Reserves','Equity','BS','Credit','Active','Equity','IAS 21 / IFRS 9',false,'none',null,'master'),
  ('50040105','Non-controlling Interests','Equity','BS','Credit','Active','Consolidation','IFRS 10',false,'none',null,'master'),
  ('50040110','Consolidation Equity Adjustments','Equity','BS','Credit','Active','Consolidation','IFRS 10',false,'none',null,'master'),
  ('50040115','Merger Reserve','Equity','BS','Credit','Active','Consolidation','IFRS 10',false,'none',null,'master'),
  ('50040120','Group Reorganisation Reserve','Equity','BS','Credit','Active','Consolidation','IFRS 10',false,'none',null,'master'),
  ('60010105','Product Sales - Domestic','Revenue','PL','Credit','Active','Sales','IFRS 15',true,'operating',null,'master'),
  ('60010110','Product Sales - Export','Revenue','PL','Credit','Active','Sales','IFRS 15',true,'operating',null,'master'),
  ('60010115','Product Sales - Wholesale','Revenue','PL','Credit','Active','Sales','IFRS 15',true,'operating',null,'master'),
  ('60010120','Product Sales - Retail','Revenue','PL','Credit','Active','Sales','IFRS 15',true,'operating',null,'master'),
  ('60010125','Product Sales - Online','Revenue','PL','Credit','Active','Sales','IFRS 15',true,'operating',null,'master'),
  ('60010130','Product Sales - Other','Revenue','PL','Credit','Active','Sales','IFRS 15',true,'operating',null,'master'),
  ('60010135','Sales Returns and Allowances','Revenue','PL','Credit','Active','Sales','IFRS 15',true,'operating',null,'master'),
  ('60010140','Sales Discounts','Revenue','PL','Credit','Active','Sales','IFRS 15',true,'operating',null,'master'),
  ('60010145','Sales Rebates','Revenue','PL','Credit','Active','Sales','IFRS 15',true,'operating',null,'master'),
  ('60020105','Professional Service Fees','Revenue','PL','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('60020110','Consultancy Fees','Revenue','PL','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('60020115','Project Fees','Revenue','PL','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('60020120','Implementation Fees','Revenue','PL','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('60020125','Support and Maintenance Fees','Revenue','PL','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('60020130','Managed Service Fees','Revenue','PL','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('60020135','Training Fees','Revenue','PL','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('60020140','Advisory Fees','Revenue','PL','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('60020145','Contract Service Revenue','Revenue','PL','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('60030105','Subscription Revenue','Revenue','PL','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('60030110','Licence Revenue','Revenue','PL','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('60030115','Usage-based Revenue','Revenue','PL','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('60030120','Platform Access Revenue','Revenue','PL','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('60030125','Transaction Processing Revenue','Revenue','PL','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('60030130','Service Charge Revenue','Revenue','PL','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('60030135','Recurring Contract Revenue','Revenue','PL','Credit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('60040105','Lead Generation Fee Income','Revenue','PL','Credit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('60040110','Lead Conversion Commission Income','Revenue','PL','Credit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('60040115','Referral Commission Income','Revenue','PL','Credit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('60040120','Agency Commission Income','Revenue','PL','Credit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('60040125','Affiliate Commission Income','Revenue','PL','Credit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('60040130','Sales Commission Income','Revenue','PL','Credit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('60040135','Other Commission Income','Revenue','PL','Credit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('60050105','Accommodation Revenue','Revenue','PL','Credit','Active','Contract','IFRS 15 / IFRS 16',true,'operating',null,'master'),
  ('60050110','Facility Usage Revenue','Revenue','PL','Credit','Active','Contract','IFRS 15 / IFRS 16',true,'operating',null,'master'),
  ('60050115','Rental Revenue - Short-term','Revenue','PL','Credit','Active','Contract','IFRS 15 / IFRS 16',true,'operating',null,'master'),
  ('60050120','Rental Revenue - Equipment','Revenue','PL','Credit','Active','Contract','IFRS 15 / IFRS 16',true,'operating',null,'master'),
  ('60050125','Rental Revenue - Other','Revenue','PL','Credit','Active','Contract','IFRS 15 / IFRS 16',true,'operating',null,'master'),
  ('60050130','Reservation Service Revenue','Revenue','PL','Credit','Active','Contract','IFRS 15 / IFRS 16',true,'operating',null,'master'),
  ('60050135','Booking Fee Income','Revenue','PL','Credit','Active','Contract','IFRS 15 / IFRS 16',true,'operating',null,'master'),
  ('60050140','Ancillary Service Revenue','Revenue','PL','Credit','Active','Contract','IFRS 15 / IFRS 16',true,'operating',null,'master'),
  ('60050145','Package Service Revenue','Revenue','PL','Credit','Active','Contract','IFRS 15 / IFRS 16',true,'operating',null,'master'),
  ('60060105','Manufacturing Service Revenue','Revenue','PL','Credit','Active','Sales','IFRS 15',true,'operating',null,'master'),
  ('60060110','Processing Fee Income','Revenue','PL','Credit','Active','Sales','IFRS 15',true,'operating',null,'master'),
  ('60060115','Customisation Revenue','Revenue','PL','Credit','Active','Sales','IFRS 15',true,'operating',null,'master'),
  ('60060120','Installation Revenue','Revenue','PL','Credit','Active','Sales','IFRS 15',true,'operating',null,'master'),
  ('60060125','Delivery Charges Recovered','Revenue','PL','Credit','Active','Sales','IFRS 15',true,'operating',null,'master'),
  ('60060130','Handling Charges Recovered','Revenue','PL','Credit','Active','Sales','IFRS 15',true,'operating',null,'master'),
  ('60060135','Other Operating Revenue','Revenue','PL','Credit','Active','Sales','IFRS 15',true,'operating',null,'master'),
  ('60070105','Intercompany Product Sales','Revenue','PL','Credit','Active','Intercompany','IFRS 10',true,'operating','intercompany','master'),
  ('60070110','Intercompany Service Revenue','Revenue','PL','Credit','Active','Intercompany','IFRS 10',true,'operating','intercompany','master'),
  ('60070115','Intercompany Management Fees','Revenue','PL','Credit','Active','Intercompany','IFRS 10',true,'operating','intercompany','master'),
  ('60070120','Intercompany Commission Income','Revenue','PL','Credit','Active','Intercompany','IFRS 10',true,'operating','intercompany','master'),
  ('60070125','Intercompany Other Revenue','Revenue','PL','Credit','Active','Intercompany','IFRS 10',true,'operating','intercompany','master'),
  ('70010105','Raw Materials Consumed','Direct Cost','PL','Debit','Active','Inventory','IAS 2',true,'operating',null,'master'),
  ('70010110','Packaging Materials Consumed','Direct Cost','PL','Debit','Active','Inventory','IAS 2',true,'operating',null,'master'),
  ('70010115','Purchased Goods Sold','Direct Cost','PL','Debit','Active','Inventory','IAS 2',true,'operating',null,'master'),
  ('70010120','Direct Consumables','Direct Cost','PL','Debit','Active','Inventory','IAS 2',true,'operating',null,'master'),
  ('70010125','Direct Components','Direct Cost','PL','Debit','Active','Inventory','IAS 2',true,'operating',null,'master'),
  ('70010130','Material Purchase Price Variance','Direct Cost','PL','Debit','Active','Inventory','IAS 2',true,'operating',null,'master'),
  ('70010135','Material Usage Variance','Direct Cost','PL','Debit','Active','Inventory','IAS 2',true,'operating',null,'master'),
  ('70010140','Inbound Freight - Inventory','Direct Cost','PL','Debit','Active','Inventory','IAS 2',true,'operating',null,'master'),
  ('70010145','Import Duty - Inventory','Direct Cost','PL','Debit','Active','Inventory','IAS 2',true,'operating',null,'master'),
  ('70010150','Inventory Write-down Expense','Direct Cost','PL','Debit','Active','Inventory','IAS 2',true,'operating',null,'master'),
  ('70010155','Inventory Shrinkage Expense','Direct Cost','PL','Debit','Active','Inventory','IAS 2',true,'operating',null,'master'),
  ('70020105','Direct Labour - Salaries','Direct Cost','PL','Debit','Active','Payroll','IAS 2',true,'operating',null,'master'),
  ('70020110','Direct Labour - Wages','Direct Cost','PL','Debit','Active','Payroll','IAS 2',true,'operating',null,'master'),
  ('70020115','Direct Labour - Overtime','Direct Cost','PL','Debit','Active','Payroll','IAS 2',true,'operating',null,'master'),
  ('70020120','Direct Labour - Employer Contributions','Direct Cost','PL','Debit','Active','Payroll','IAS 2',true,'operating',null,'master'),
  ('70020125','Direct Labour - Contract Staff','Direct Cost','PL','Debit','Active','Payroll','IAS 2',true,'operating',null,'master'),
  ('70020130','Direct Labour Efficiency Variance','Direct Cost','PL','Debit','Active','Payroll','IAS 2',true,'operating',null,'master'),
  ('70030105','Production Utilities','Direct Cost','PL','Debit','Active','Costing','IAS 2',true,'operating',null,'master'),
  ('70030110','Production Repairs and Maintenance','Direct Cost','PL','Debit','Active','Costing','IAS 2',true,'operating',null,'master'),
  ('70030115','Production Depreciation','Direct Cost','PL','Debit','Active','Costing','IAS 2',true,'operating',null,'master'),
  ('70030120','Production Rent and Occupancy','Direct Cost','PL','Debit','Active','Costing','IAS 2',true,'operating',null,'master'),
  ('70030125','Factory Indirect Labour','Direct Cost','PL','Debit','Active','Costing','IAS 2',true,'operating',null,'master'),
  ('70030130','Quality Control Costs','Direct Cost','PL','Debit','Active','Costing','IAS 2',true,'operating',null,'master'),
  ('70030135','Production Supplies','Direct Cost','PL','Debit','Active','Costing','IAS 2',true,'operating',null,'master'),
  ('70030140','Manufacturing Overhead Absorption','Direct Cost','PL','Debit','Active','Costing','IAS 2',true,'operating',null,'master'),
  ('70030145','Under-absorbed Overhead','Direct Cost','PL','Debit','Active','Costing','IAS 2',true,'operating',null,'master'),
  ('70030150','Over-absorbed Overhead','Direct Cost','PL','Debit','Active','Costing','IAS 2',true,'operating',null,'master'),
  ('70040105','Direct Service Labour','Direct Cost','PL','Debit','Active','Project','IFRS 15',true,'operating',null,'master'),
  ('70040110','Direct Project Contractors','Direct Cost','PL','Debit','Active','Project','IFRS 15',true,'operating',null,'master'),
  ('70040115','Direct Software Hosting','Direct Cost','PL','Debit','Active','Project','IFRS 15',true,'operating',null,'master'),
  ('70040120','Direct Licence Costs','Direct Cost','PL','Debit','Active','Project','IFRS 15',true,'operating',null,'master'),
  ('70040125','Direct Implementation Costs','Direct Cost','PL','Debit','Active','Project','IFRS 15',true,'operating',null,'master'),
  ('70040130','Direct Professional Fees','Direct Cost','PL','Debit','Active','Project','IFRS 15',true,'operating',null,'master'),
  ('70040135','Direct Project Travel','Direct Cost','PL','Debit','Active','Project','IFRS 15',true,'operating',null,'master'),
  ('70040140','Direct Service Delivery Costs','Direct Cost','PL','Debit','Active','Project','IFRS 15',true,'operating',null,'master'),
  ('70040145','Direct Contract Fulfilment Costs','Direct Cost','PL','Debit','Active','Project','IFRS 15',true,'operating',null,'master'),
  ('70050105','Merchant Processing Fees','Direct Cost','PL','Debit','Active','Settlement','IFRS 15 / IFRS 9',true,'operating',null,'master'),
  ('70050110','Payment Network Fees','Direct Cost','PL','Debit','Active','Settlement','IFRS 15 / IFRS 9',true,'operating',null,'master'),
  ('70050115','Transaction Processing Costs','Direct Cost','PL','Debit','Active','Settlement','IFRS 15 / IFRS 9',true,'operating',null,'master'),
  ('70050120','Settlement Fees','Direct Cost','PL','Debit','Active','Settlement','IFRS 15 / IFRS 9',true,'operating',null,'master'),
  ('70050125','Chargeback Costs','Direct Cost','PL','Debit','Active','Settlement','IFRS 15 / IFRS 9',true,'operating',null,'master'),
  ('70050130','Direct Platform Usage Fees','Direct Cost','PL','Debit','Active','Settlement','IFRS 15 / IFRS 9',true,'operating',null,'master'),
  ('70050135','Direct Customer Servicing Costs','Direct Cost','PL','Debit','Active','Settlement','IFRS 15 / IFRS 9',true,'operating',null,'master'),
  ('70060105','Direct Booking Costs','Direct Cost','PL','Debit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('70060110','Third-party Service Purchases','Direct Cost','PL','Debit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('70060115','Direct Facility Operating Costs','Direct Cost','PL','Debit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('70060120','Direct Rental Operating Costs','Direct Cost','PL','Debit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('70060125','Direct Reservation Costs','Direct Cost','PL','Debit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('70060130','Direct Commission Costs','Direct Cost','PL','Debit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('70060135','Direct Package Costs','Direct Cost','PL','Debit','Active','Contract','IFRS 15',true,'operating',null,'master'),
  ('70070105','Freight Outward','Direct Cost','PL','Debit','Active','Inventory','IAS 2 / IFRS 15',true,'operating',null,'master'),
  ('70070110','Fulfilment and Dispatch','Direct Cost','PL','Debit','Active','Inventory','IAS 2 / IFRS 15',true,'operating',null,'master'),
  ('70070115','Shipping and Delivery','Direct Cost','PL','Debit','Active','Inventory','IAS 2 / IFRS 15',true,'operating',null,'master'),
  ('70070120','Returns Processing','Direct Cost','PL','Debit','Active','Inventory','IAS 2 / IFRS 15',true,'operating',null,'master'),
  ('70070125','Warehouse Handling','Direct Cost','PL','Debit','Active','Inventory','IAS 2 / IFRS 15',true,'operating',null,'master'),
  ('70070130','Customs Clearance Charges','Direct Cost','PL','Debit','Active','Inventory','IAS 2 / IFRS 15',true,'operating',null,'master'),
  ('70070135','Export Documentation Charges','Direct Cost','PL','Debit','Active','Inventory','IAS 2 / IFRS 15',true,'operating',null,'master'),
  ('70070140','Distribution Packaging','Direct Cost','PL','Debit','Active','Inventory','IAS 2 / IFRS 15',true,'operating',null,'master'),
  ('70080105','Intercompany Cost of Goods','Direct Cost','PL','Debit','Active','Intercompany','IFRS 10',true,'operating','intercompany','master'),
  ('70080110','Intercompany Service Costs','Direct Cost','PL','Debit','Active','Intercompany','IFRS 10',true,'operating','intercompany','master'),
  ('70080115','Intercompany Management Charges','Direct Cost','PL','Debit','Active','Intercompany','IFRS 10',true,'operating','intercompany','master'),
  ('70080120','Intercompany Commission Expense','Direct Cost','PL','Debit','Active','Intercompany','IFRS 10',true,'operating','intercompany','master'),
  ('80010105','Administrative Salaries','Expense','PL','Debit','Active','Payroll','IAS 19',true,'operating',null,'master'),
  ('80010110','Administrative Wages','Expense','PL','Debit','Active','Payroll','IAS 19',true,'operating',null,'master'),
  ('80010115','Employer Social Contributions','Expense','PL','Debit','Active','Payroll','IAS 19',true,'operating',null,'master'),
  ('80010120','Employee Benefits','Expense','PL','Debit','Active','Payroll','IAS 19',true,'operating',null,'master'),
  ('80010125','Staff Recruitment','Expense','PL','Debit','Active','Payroll','IAS 19',true,'operating',null,'master'),
  ('80010130','Staff Training','Expense','PL','Debit','Active','Payroll','IAS 19',true,'operating',null,'master'),
  ('80010135','Staff Welfare','Expense','PL','Debit','Active','Payroll','IAS 19',true,'operating',null,'master'),
  ('80010140','Staff Travel','Expense','PL','Debit','Active','Payroll','IAS 19',true,'operating',null,'master'),
  ('80010145','Staff Insurance','Expense','PL','Debit','Active','Payroll','IAS 19',true,'operating',null,'master'),
  ('80010150','Payroll Processing Fees','Expense','PL','Debit','Active','Payroll','IAS 19',true,'operating',null,'master'),
  ('80020105','Office Rent - Exempt/Variable Leases','Expense','PL','Debit','Active','Expense','IFRS 16',true,'operating',null,'master'),
  ('80020110','Utilities','Expense','PL','Debit','Active','Expense','IFRS 16',true,'operating',null,'master'),
  ('80020115','Telecommunications','Expense','PL','Debit','Active','Expense','IFRS 16',true,'operating',null,'master'),
  ('80020120','Office Supplies','Expense','PL','Debit','Active','Expense','IFRS 16',true,'operating',null,'master'),
  ('80020125','Cleaning and Maintenance','Expense','PL','Debit','Active','Expense','IFRS 16',true,'operating',null,'master'),
  ('80020130','Security Expenses','Expense','PL','Debit','Active','Expense','IFRS 16',true,'operating',null,'master'),
  ('80020135','Repairs and Maintenance','Expense','PL','Debit','Active','Expense','IFRS 16',true,'operating',null,'master'),
  ('80020140','Property Taxes','Expense','PL','Debit','Active','Expense','IFRS 16',true,'operating',null,'master'),
  ('80020145','Office Insurance','Expense','PL','Debit','Active','Expense','IFRS 16',true,'operating',null,'master'),
  ('80020150','Facilities Management','Expense','PL','Debit','Active','Expense','IFRS 16',true,'operating',null,'master'),
  ('80030105','Advertising and Promotions','Expense','PL','Debit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('80030110','Digital Advertising','Expense','PL','Debit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('80030115','Brand Development','Expense','PL','Debit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('80030120','Lead Generation Fees Paid','Expense','PL','Debit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('80030125','Lead Conversion Commissions Paid','Expense','PL','Debit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('80030130','Referral Commissions Paid','Expense','PL','Debit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('80030135','Affiliate Commissions Paid','Expense','PL','Debit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('80030140','Sales Incentives','Expense','PL','Debit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('80030145','Marketing Events','Expense','PL','Debit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('80030150','Customer Acquisition Campaigns','Expense','PL','Debit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('80030155','Sales Travel','Expense','PL','Debit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('80030160','Customer Retention Expenses','Expense','PL','Debit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('80030165','Market Research','Expense','PL','Debit','Active','Commission','IFRS 15',true,'operating',null,'master'),
  ('80040105','Cloud Hosting','Expense','PL','Debit','Active','Project','IAS 38',true,'operating',null,'master'),
  ('80040110','Software Subscriptions','Expense','PL','Debit','Active','Project','IAS 38',true,'operating',null,'master'),
  ('80040115','IT Support','Expense','PL','Debit','Active','Project','IAS 38',true,'operating',null,'master'),
  ('80040120','Cybersecurity','Expense','PL','Debit','Active','Project','IAS 38',true,'operating',null,'master'),
  ('80040125','Data Services','Expense','PL','Debit','Active','Project','IAS 38',true,'operating',null,'master'),
  ('80040130','Domain and Hosting','Expense','PL','Debit','Active','Project','IAS 38',true,'operating',null,'master'),
  ('80040135','Technical Maintenance','Expense','PL','Debit','Active','Project','IAS 38',true,'operating',null,'master'),
  ('80040140','Software Testing','Expense','PL','Debit','Active','Project','IAS 38',true,'operating',null,'master'),
  ('80040145','Research Expenditure','Expense','PL','Debit','Active','Project','IAS 38',true,'operating',null,'master'),
  ('80040150','Development Expenditure - Expensed','Expense','PL','Debit','Active','Project','IAS 38',true,'operating',null,'master'),
  ('80040155','IT Equipment Maintenance','Expense','PL','Debit','Active','Project','IAS 38',true,'operating',null,'master'),
  ('80050105','Audit Fees','Expense','PL','Debit','Active','Expense',null,true,'operating',null,'master'),
  ('80050110','Accounting Fees','Expense','PL','Debit','Active','Expense',null,true,'operating',null,'master'),
  ('80050115','Legal Fees','Expense','PL','Debit','Active','Expense',null,true,'operating',null,'master'),
  ('80050120','Tax Advisory Fees','Expense','PL','Debit','Active','Expense',null,true,'operating',null,'master'),
  ('80050125','Consultancy Fees','Expense','PL','Debit','Active','Expense',null,true,'operating',null,'master'),
  ('80050130','Regulatory Fees','Expense','PL','Debit','Active','Expense',null,true,'operating',null,'master'),
  ('80050135','Licensing Fees','Expense','PL','Debit','Active','Expense',null,true,'operating',null,'master'),
  ('80050140','Compliance Costs','Expense','PL','Debit','Active','Expense',null,true,'operating',null,'master'),
  ('80050145','Professional Membership Fees','Expense','PL','Debit','Active','Expense',null,true,'operating',null,'master'),
  ('80050150','Bank Service Charges','Expense','PL','Debit','Active','Expense',null,true,'operating',null,'master'),
  ('80060105','Business Travel','Expense','PL','Debit','Active','Expense',null,true,'operating',null,'master'),
  ('80060110','Accommodation and Subsistence','Expense','PL','Debit','Active','Expense',null,true,'operating',null,'master'),
  ('80060115','Vehicle Running Costs','Expense','PL','Debit','Active','Expense',null,true,'operating',null,'master'),
  ('80060120','Fuel','Expense','PL','Debit','Active','Expense',null,true,'operating',null,'master'),
  ('80060125','Transport and Delivery - Admin','Expense','PL','Debit','Active','Expense',null,true,'operating',null,'master'),
  ('80060130','Meals and Entertainment','Expense','PL','Debit','Active','Expense',null,true,'operating',null,'master'),
  ('80060135','Postage and Courier','Expense','PL','Debit','Active','Expense',null,true,'operating',null,'master'),
  ('80060140','General Administration','Expense','PL','Debit','Active','Expense',null,true,'operating',null,'master'),
  ('80060145','Donations','Expense','PL','Debit','Active','Expense',null,true,'operating',null,'master'),
  ('80060150','Subscriptions and Publications','Expense','PL','Debit','Active','Expense',null,true,'operating',null,'master'),
  ('80070105','Depreciation - Property and Equipment','Expense','PL','Debit','Active','Fixed assets','IFRS 16 / IAS 16',true,'non_cash',null,'master'),
  ('80070110','Depreciation - ROU Assets','Expense','PL','Debit','Active','Fixed assets','IFRS 16 / IAS 16',false,'non_cash',null,'master'),
  ('80070115','Amortisation - Intangibles','Expense','PL','Debit','Active','Fixed assets','IFRS 16 / IAS 16',true,'non_cash',null,'master'),
  ('80070120','Impairment - Non-financial Assets','Expense','PL','Debit','Active','Fixed assets','IFRS 16 / IAS 16',true,'non_cash',null,'master'),
  ('80070125','Loss on Disposal of Assets','Expense','PL','Debit','Active','Fixed assets','IFRS 16 / IAS 16',true,'non_cash',null,'master'),
  ('80070130','Short-term Lease Expense','Expense','PL','Debit','Active','Fixed assets','IFRS 16 / IAS 16',false,'operating',null,'master'),
  ('80070135','Low-value Lease Expense','Expense','PL','Debit','Active','Fixed assets','IFRS 16 / IAS 16',false,'operating',null,'master'),
  ('80070140','Variable Lease Payments Not Included in Liability','Expense','PL','Debit','Active','Fixed assets','IFRS 16 / IAS 16',false,'operating',null,'master'),
  ('80080105','Expected Credit Loss Expense','Expense','PL','Debit','Active','AR','IFRS 9',true,'operating',null,'master'),
  ('80080110','Bad Debt Write-offs','Expense','PL','Debit','Active','AR','IFRS 9',true,'operating',null,'master'),
  ('80080115','Warranty Expense','Expense','PL','Debit','Active','AR','IFRS 9',true,'operating',null,'master'),
  ('80080120','Legal Settlement Expense','Expense','PL','Debit','Active','AR','IFRS 9',true,'operating',null,'master'),
  ('80080125','Other Provision Expense','Expense','PL','Debit','Active','AR','IFRS 9',true,'operating',null,'master'),
  ('80080130','Foreign Exchange Loss - Operating','Expense','PL','Debit','Active','AR','IFRS 9',true,'operating',null,'master'),
  ('80080135','Other Operating Expenses','Expense','PL','Debit','Active','AR','IFRS 9',true,'operating',null,'master'),
  ('80090105','Intercompany Administrative Charges','Expense','PL','Debit','Active','Intercompany','IFRS 10',true,'operating','intercompany','master'),
  ('80090110','Intercompany Shared Service Charges','Expense','PL','Debit','Active','Intercompany','IFRS 10',true,'operating','intercompany','master'),
  ('80090115','Intercompany Royalty Expense','Expense','PL','Debit','Active','Intercompany','IFRS 10',true,'operating','intercompany','master'),
  ('90010105','Interest Income - Bank','Other Income','PL','Credit','Active','Treasury','IFRS 9',true,'investing',null,'master'),
  ('90010110','Interest Income - Loans','Other Income','PL','Credit','Active','Treasury','IFRS 9',true,'investing',null,'master'),
  ('90010115','Investment Income','Other Income','PL','Credit','Active','Treasury','IFRS 9',true,'investing',null,'master'),
  ('90010120','Dividend Income','Other Income','PL','Credit','Active','Treasury','IFRS 9',true,'investing',null,'master'),
  ('90010125','Foreign Exchange Gain - Operating','Other Income','PL','Credit','Active','Treasury','IFRS 9',true,'operating',null,'master'),
  ('90010130','Gain on Disposal of Assets','Other Income','PL','Credit','Active','Treasury','IFRS 9',true,'non_cash',null,'master'),
  ('90010135','Other Non-operating Income','Other Income','PL','Credit','Active','Treasury','IFRS 9',true,'operating',null,'master'),
  ('91010105','Interest Expense - Borrowings','Finance Cost','PL','Debit','Active','Debt / Lease','IFRS 16 / IFRS 9',true,'financing',null,'master'),
  ('91010110','Interest Expense - Lease Liabilities','Finance Cost','PL','Debit','Active','Debt / Lease','IFRS 16 / IFRS 9',true,'financing',null,'master'),
  ('91010115','Bank Financing Charges','Finance Cost','PL','Debit','Active','Debt / Lease','IFRS 16 / IFRS 9',true,'financing',null,'master'),
  ('91010120','Debt Arrangement Fee Amortisation','Finance Cost','PL','Debit','Active','Debt / Lease','IFRS 16 / IFRS 9',true,'financing',null,'master'),
  ('91010125','Foreign Exchange Loss - Financing','Finance Cost','PL','Debit','Active','Debt / Lease','IFRS 16 / IFRS 9',true,'financing',null,'master'),
  ('91010130','Other Finance Costs','Finance Cost','PL','Debit','Active','Debt / Lease','IFRS 16 / IFRS 9',true,'financing',null,'master'),
  ('92010105','Current Income Tax Expense','Tax Expense','PL','Debit','Active','Tax','IAS 12',true,'operating',null,'master'),
  ('92010110','Deferred Income Tax Expense','Tax Expense','PL','Debit','Active','Tax','IAS 12',true,'operating',null,'master'),
  ('92010115','Prior-year Tax Adjustment','Tax Expense','PL','Debit','Active','Tax','IAS 12',true,'operating',null,'master'),
  ('92010120','Withholding Tax Expense - Nonrecoverable','Tax Expense','PL','Debit','Active','Tax','IAS 12',true,'operating',null,'master'),
  ('92010125','Other Profit Taxes','Tax Expense','PL','Debit','Active','Tax','IAS 12',true,'operating',null,'master'),
  ('93010105','Fair Value Gain - Financial Instruments','Other PL','PL','Debit','Active','Investment','IFRS 9 / IAS 28',false,'non_cash',null,'master'),
  ('93010110','Fair Value Loss - Financial Instruments','Other PL','PL','Debit','Active','Investment','IFRS 9 / IAS 28',false,'non_cash',null,'master'),
  ('93010115','Derivative Gain or Loss','Other PL','PL','Debit','Active','Investment','IFRS 9 / IAS 28',false,'non_cash',null,'master'),
  ('93010120','Share of Profit or Loss of Associates','Other PL','PL','Debit','Active','Investment','IFRS 9 / IAS 28',false,'non_cash',null,'master'),
  ('93010125','Discontinued Operations Result','Other PL','PL','Debit','Active','Investment','IFRS 9 / IAS 28',true,'non_cash',null,'master'),
  ('95010105','Elimination - Intercompany Receivables','Consolidation','CONSOL','Either','Active','Consolidation','IFRS 10',false,'none',null,'master'),
  ('95010110','Elimination - Intercompany Payables','Consolidation','CONSOL','Either','Active','Consolidation','IFRS 10',false,'none',null,'master'),
  ('95010115','Elimination - Intercompany Revenue','Consolidation','CONSOL','Either','Active','Consolidation','IFRS 10',false,'none',null,'master'),
  ('95010120','Elimination - Intercompany Costs','Consolidation','CONSOL','Either','Active','Consolidation','IFRS 10',false,'none',null,'master'),
  ('95010125','Elimination - Intercompany Interest','Consolidation','CONSOL','Either','Active','Consolidation','IFRS 10',false,'none',null,'master'),
  ('95010130','Elimination - Intercompany Dividends','Consolidation','CONSOL','Either','Active','Consolidation','IFRS 10',false,'none',null,'master'),
  ('95010135','Elimination - Unrealised Inventory Profit','Consolidation','CONSOL','Either','Active','Consolidation','IFRS 10',false,'none',null,'master'),
  ('95010140','Elimination - Unrealised Fixed Asset Profit','Consolidation','CONSOL','Either','Active','Consolidation','IFRS 10',false,'none',null,'master'),
  ('95020105','Investment in Subsidiary Elimination','Consolidation','CONSOL','Either','Active','Consolidation','IFRS 3 / IFRS 10',false,'none',null,'master'),
  ('95020110','Acquisition Fair Value Adjustments','Consolidation','CONSOL','Either','Active','Consolidation','IFRS 3 / IFRS 10',false,'none',null,'master'),
  ('95020115','Goodwill Consolidation Adjustment','Consolidation','CONSOL','Either','Active','Consolidation','IFRS 3 / IFRS 10',false,'none',null,'master'),
  ('95020120','Non-controlling Interest Adjustment','Consolidation','CONSOL','Either','Active','Consolidation','IFRS 3 / IFRS 10',false,'none',null,'master'),
  ('95020125','Consolidation Retained Earnings Adjustment','Consolidation','CONSOL','Either','Active','Consolidation','IFRS 3 / IFRS 10',false,'none',null,'master'),
  ('95020130','Group Currency Translation Adjustment','Consolidation','CONSOL','Either','Active','Consolidation','IFRS 3 / IFRS 10',false,'none',null,'master'),
  ('95020135','Consolidation Deferred Tax Adjustment','Consolidation','CONSOL','Either','Active','Consolidation','IFRS 3 / IFRS 10',false,'none',null,'master'),
  ('96010105','Local GAAP to IFRS - Revenue','Adjustment','CONSOL','Either','Active','Consolidation','IFRS bridge',false,'none',null,'master'),
  ('96010110','Local GAAP to IFRS - Leases','Adjustment','CONSOL','Either','Active','Consolidation','IFRS bridge',false,'none',null,'master'),
  ('96010115','Local GAAP to IFRS - Financial Instruments','Adjustment','CONSOL','Either','Active','Consolidation','IFRS bridge',false,'none',null,'master'),
  ('96010120','Local GAAP to IFRS - Inventory','Adjustment','CONSOL','Either','Active','Consolidation','IFRS bridge',false,'none',null,'master'),
  ('96010125','Local GAAP to IFRS - Tax','Adjustment','CONSOL','Either','Active','Consolidation','IFRS bridge',false,'none',null,'master'),
  ('96010130','Local GAAP to IFRS - Other','Adjustment','CONSOL','Either','Active','Consolidation','IFRS bridge',false,'none',null,'master'),
  ('97010105','Opening Balance Migration Clearing','Control','BS','Either','Active','Control','Clear before reporting',true,'none',null,'master'),
  ('97010110','Unallocated Transactions Suspense','Control','BS','Either','Active','Control','Clear before reporting',true,'none',null,'master'),
  ('97010115','Bank Reconciliation Suspense - Group','Control','BS','Either','Active','Control','Clear before reporting',true,'none',null,'master'),
  ('97010120','Intercompany Reconciliation Suspense','Control','BS','Either','Active','Control','Clear before reporting',true,'none',null,'master'),
  ('97010125','Rounding Adjustment','Control','BS','Either','Active','Control','Clear before reporting',true,'none',null,'master'),
  ('97010130','Unmapped Account Suspense','Control','BS','Either','Active','Control','Clear before reporting',true,'none',null,'master')
) as a(code, name, class, statement, normal_balance, status, subledger, standard,
       e002_active, cash_flow, control_type, source)
on conflict (code) do update set
  name = excluded.name, class = excluded.class, statement = excluded.statement,
  normal_balance = excluded.normal_balance, status = excluded.status, subledger = excluded.subledger,
  standard = excluded.standard, control_type = excluded.control_type
where accounts.source = 'master';

-- Gap in the Master COA: there is no "cost of finished goods sold" account.
-- Added for E002 in family 700101, as suggested in the build plan.
insert into accounts (code, name, class, statement, normal_balance, status, subledger, level,
                      e002_active, cash_flow, source)
values ('70010160', 'Cost of Finished Goods Sold', 'Direct Cost', 'PL', 'Debit', 'Active', 'Inventory',
        'posting', true, 'operating', 'local')
on conflict (code) do nothing;

-- ---------------------------------------------------------------------
-- 4. Posting rules (the build plan's posting map, for the Accountant and
--    CA to confirm). Later modules post through these keys.
-- ---------------------------------------------------------------------

insert into posting_rules (event_code, line_key, side, account_code, module, label, sort) values
  ('opening',        'cash',            'debit',  '10010110', 2, 'Opening capital received in cash', 10),
  ('opening',        'bank',            'debit',  '10010205', 2, 'Opening capital received in the bank', 11),
  ('opening',        'capital',         'credit', '50010130', 2, 'Partners'' capital (per partner)', 12),
  ('grn',            'stock_raw',       'debit',  '10030105', 3, 'Goods received: raw materials', 20),
  ('grn',            'stock_packaging', 'debit',  '10030110', 3, 'Goods received: empty bottles and pouches', 21),
  ('grn',            'grni',            'credit', '30010115', 3, 'Goods received not invoiced', 22),
  ('supplier_bill',  'grni',            'debit',  '30010115', 3, 'Clears goods received not invoiced', 30),
  ('supplier_bill',  'input_gst',       'debit',  '10050105', 3, 'Input GST recoverable', 31),
  ('supplier_bill',  'payable',         'credit', '30010105', 3, 'Trade payables (per supplier)', 32),
  ('direct_purchase','stock_raw',       'debit',  '10030105', 3, 'Direct purchase into raw-material stock', 40),
  ('direct_purchase','cash',            'credit', '10010110', 3, 'Paid in cash', 41),
  ('direct_purchase','bank',            'credit', '10010205', 3, 'Paid by bank or UPI', 42),
  ('direct_purchase','payable',         'credit', '30010105', 3, 'On credit (per supplier)', 43),
  ('supplier_payment','payable',        'debit',  '30010105', 3, 'Supplier paid (per supplier)', 45),
  ('supplier_payment','cash',           'credit', '10010110', 3, 'Paid in cash', 46),
  ('supplier_payment','bank',           'credit', '10010205', 3, 'Paid by bank or UPI', 47),
  ('purchase_return','payable',         'debit',  '30010105', 3, 'Reduces the supplier balance', 48),
  ('purchase_return','stock_raw',       'credit', '10030105', 3, 'Goods returned out of stock', 49),
  ('preparation',    'wip',             'debit',  '10030120', 4, 'Prepared ingredients (work in progress)', 50),
  ('preparation',    'stock_raw',       'credit', '10030105', 4, 'Raw materials used', 51),
  ('production',     'finished',        'debit',  '10030125', 4, 'Finished goods made', 60),
  ('production',     'wip',             'credit', '10030120', 4, 'Prepared ingredients used', 61),
  ('production',     'stock_raw',       'credit', '10030105', 4, 'Other raw materials used', 62),
  ('production',     'packaging',       'credit', '10030110', 4, 'Bottles and pouches used', 63),
  ('wastage',        'abnormal_loss',   'debit',  '70010150', 4, 'Unusual wastage (normal wastage stays in batch cost)', 70),
  ('wastage',        'stock',           'credit', '10030105', 4, 'Stock written off', 71),
  ('stock_count',    'shortage',        'debit',  '70010155', 4, 'Stock count shortage', 75),
  ('stock_count',    'excess',          'credit', '70010155', 4, 'Stock count excess', 76),
  ('sale',           'cash',            'debit',  '10010110', 5, 'Paid in cash', 80),
  ('sale',           'bank',            'debit',  '10010205', 5, 'Paid by UPI or bank', 81),
  ('sale',           'receivable',      'debit',  '10020105', 5, 'On credit (per customer)', 82),
  ('sale',           'revenue_retail',  'credit', '60010120', 5, 'Retail sales', 83),
  ('sale',           'revenue_trader',  'credit', '60010115', 5, 'Trader (wholesale) sales', 84),
  ('sale',           'revenue_online',  'credit', '60010125', 5, 'Online sales', 85),
  ('sale',           'discount',        'debit',  '60010140', 5, 'Counter discount', 86),
  ('sale',           'output_gst',      'credit', '30030105', 5, 'Output GST', 87),
  ('sale',           'delivery',        'credit', '60060125', 5, 'Delivery charges recovered', 88),
  ('sale_cost',      'cost_of_sales',   'debit',  '70010160', 5, 'Cost of finished goods sold', 90),
  ('sale_cost',      'finished',        'credit', '10030125', 5, 'Finished goods out of stock', 91),
  ('sales_return',   'returns',         'debit',  '60010135', 5, 'Sales returns', 95),
  ('sales_return',   'refund_cash',     'credit', '10010110', 5, 'Refund paid in cash', 96),
  ('sales_return',   'receivable',      'credit', '10020105', 5, 'Credit to the customer''s balance', 97),
  ('customer_receipt','cash',           'debit',  '10010110', 5, 'Received in cash', 100),
  ('customer_receipt','bank',           'debit',  '10010205', 5, 'Received by UPI or bank', 101),
  ('customer_receipt','receivable',     'credit', '10020105', 5, 'Customer balance (per customer)', 102),
  ('gateway_fee',    'fee',             'debit',  '70050105', 10, 'Payment gateway fee', 110),
  ('gateway_fee',    'clearing',        'credit', '10010305', 10, 'Payment gateway clearing', 111),
  ('expense',        'rent_kitchen',    'debit',  '70030120', 6, 'Kitchen rent (operating lease)', 120),
  ('expense',        'rent_office',     'debit',  '80020105', 6, 'Shop or office rent (operating lease)', 121),
  ('expense',        'gas_power',       'debit',  '70030105', 6, 'Kitchen gas, electricity and water', 122),
  ('expense',        'wages',           'debit',  '70020110', 6, 'Kitchen wages paid', 123),
  ('expense',        'bank_charges',    'debit',  '80050150', 6, 'Bank charges', 124),
  ('drawings',       'partner_current', 'debit',  '50010135', 6, 'Partner drawings (per partner)', 130),
  ('drawings',       'cash',            'credit', '10010110', 6, 'Paid in cash', 131),
  ('loan',           'interest',        'debit',  '91010105', 7, 'Loan interest', 140),
  ('loan',           'principal',       'credit', '40010105', 7, 'Long-term bank loan', 141),
  ('finance_lease',  'depreciation',    'debit',  '80070105', 7, 'Depreciation on leased asset (AS 19)', 150),
  ('finance_lease',  'acc_depreciation','credit', '20010215', 7, 'Accumulated depreciation', 151),
  ('finance_lease',  'finance_charge',  'debit',  '91010110', 7, 'Finance charge on lease (AS 19)', 152),
  ('finance_lease',  'liability_current','credit','30060120', 7, 'Finance lease liability, current', 153),
  ('finance_lease',  'liability_noncurrent','credit','40020110', 7, 'Finance lease liability, non-current', 154),
  ('year_end',       'profit',          'debit',  '50020110', 8, 'Current year profit or loss', 160),
  ('year_end',       'partner_current', 'credit', '50010135', 8, 'Partners'' current accounts (profit share)', 161),
  ('rounding',       'rounding',        'debit',  '97010125', 2, 'Rounding adjustment', 170)
on conflict (event_code, line_key) do nothing;

-- ---------------------------------------------------------------------
-- 5. Helpers: months, departments, partners
-- ---------------------------------------------------------------------

-- First day of the financial year a date falls in (April to March).
create or replace function rb_fy_start(p_date date)
returns date language sql stable security definer set search_path = public as $$
  select make_date(case when extract(month from p_date) >= m then extract(year from p_date)::int
                        else extract(year from p_date)::int - 1 end, m, 1)
  from (select coalesce((select fy_start_month from app_settings where id = 1), 4) as m) s
$$;

create or replace function rb_period_locked(p_date date)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_locked from periods where month = date_trunc('month', p_date)::date), false)
$$;

create or replace function rb_assert_period_open(p_date date)
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if p_date is null then raise exception 'Please choose the date.'; end if;
  if rb_period_locked(p_date) then
    raise exception '% is locked, so nothing can be posted, changed or deleted in it. Ask a Director or the FC to unlock it first.',
      to_char(p_date, 'Mon-YYYY');
  end if;
end $$;

-- The department a line counts under in reports, after merges.
create or replace function rb_dept_resolve(p_dept int, p_date date)
returns int language plpgsql stable security definer set search_path = public as $$
declare v int := p_dept; v_next int; i int := 0;
begin
  loop
    v_next := null;
    select e.into_dept_id into v_next from dept_events e
    where e.dept_id = v and e.kind = 'merge' and e.undone_at is null
      and (e.effective_from is null or e.effective_from <= p_date)
    order by e.id desc limit 1;
    exit when v_next is null or i >= 10;
    v := v_next; i := i + 1;
  end loop;
  return v;
end $$;

-- A department's name as reports show it for an entry on that date.
create or replace function rb_dept_name(p_dept int, p_date date)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(
    (select e.new_name from dept_events e where e.dept_id = p_dept and e.kind = 'rename' and e.undone_at is null
       and (e.effective_from is null or e.effective_from <= p_date) order by e.id desc limit 1),
    (select original_name from departments where id = p_dept))
$$;

-- "CC001 Kitchen" for a line, after renames and merges.
create or replace function rb_dept_label(p_dept int, p_date date)
returns text language sql stable security definer set search_path = public as $$
  select d.code || ' ' || rb_dept_name(d.id, p_date)
  from departments d where d.id = rb_dept_resolve(p_dept, p_date)
$$;

create or replace function rb_partner_name(p_partner int)
returns text language sql stable security definer set search_path = public as $$
  select e->>'name' from app_settings s, jsonb_array_elements(s.partners) e
  where s.id = 1 and (e->>'id')::int = p_partner
$$;

-- Next code in a simple series, e.g. rb_next_code('CUSTOMER', 'C', 5) -> C00001.
create or replace function rb_next_code(p_series text, p_prefix text, p_digits int)
returns text language plpgsql security definer set search_path = public as $$
declare v_no bigint;
begin
  insert into doc_counters (series, last_no) values (p_series, 1)
  on conflict (series) do update set last_no = doc_counters.last_no + 1
  returning last_no into v_no;
  return p_prefix || lpad(v_no::text, p_digits, '0');
end $$;

-- Small helpers for reading the JSON the screens send.
create or replace function rb_txt(p jsonb, k text)
returns text language sql immutable as $$ select nullif(trim(p->>k), '') $$;
create or replace function rb_int(p jsonb, k text)
returns bigint language sql immutable as $$ select nullif(trim(p->>k), '')::numeric::bigint $$;

-- ---------------------------------------------------------------------
-- 6. Masters: units, items, packs
-- ---------------------------------------------------------------------

create or replace function rb_save_unit(p jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare v_code text := lower(rb_txt(p, 'code'));
begin
  perform rb_require('masters.edit', 'change units');
  if v_code is null or rb_txt(p, 'name') is null then raise exception 'Please enter the unit code and name.'; end if;
  if coalesce((p->>'to_base')::numeric, 0) <= 0 then raise exception 'Please say how many base units one of this unit holds.'; end if;
  if exists (select 1 from units where code = v_code) then
    if exists (select 1 from items where base_unit = v_code or buy_unit = v_code)
       and exists (select 1 from units where code = v_code and (to_base <> (p->>'to_base')::numeric or dimension <> p->>'dimension')) then
      raise exception 'This unit is already used by items, so only its name can change.';
    end if;
    update units set name = rb_txt(p, 'name'), dimension = p->>'dimension', to_base = (p->>'to_base')::numeric
    where code = v_code;
  else
    insert into units (code, name, dimension, to_base) values (v_code, rb_txt(p, 'name'), p->>'dimension', (p->>'to_base')::numeric);
  end if;
  return v_code;
end $$;

create or replace function rb_save_item(p jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_id int := rb_int(p, 'id'); v_me uuid; v_kind text := p->>'kind'; v_code text := upper(rb_txt(p, 'code'));
  v_prefix text; v_base text := rb_txt(p, 'base_unit'); v_old items;
  v_stages text[];
begin
  v_me := rb_require(case when v_id is null then 'masters.add' else 'masters.edit' end,
                     case when v_id is null then 'add items' else 'change items' end);
  if rb_txt(p, 'name') is null then raise exception 'Please enter the item name.'; end if;
  if v_kind not in ('raw', 'wip', 'finished', 'byproduct', 'packaging') then raise exception 'Please choose the kind of item.'; end if;
  if v_base is null or not exists (select 1 from units where code = v_base) then raise exception 'Please choose the unit.'; end if;
  select coalesce(array_agg(trim(x)) filter (where trim(x) <> ''), '{}') into v_stages
  from jsonb_array_elements_text(coalesce(p->'stages', '[]')) x;
  if v_kind = 'byproduct' and rb_txt(p, 'byproduct_use') is null then
    raise exception 'Please mark the by-product as Sellable or Discarded.';
  end if;
  if v_id is not null then
    select * into v_old from items where id = v_id;
    if v_old.id is null then raise exception 'Item not found.'; end if;
    if v_old.kind <> v_kind and exists (select 1 from journal_lines where item_id = v_id) then
      raise exception 'This item already has entries, so its kind cannot change.';
    end if;
    if v_old.base_unit <> v_base and (select dimension from units where code = v_old.base_unit) <> (select dimension from units where code = v_base)
       and exists (select 1 from journal_lines where item_id = v_id) then
      raise exception 'This item already has entries, so it cannot change from weight to volume or pieces.';
    end if;
  end if;
  if v_code is null then
    if v_id is not null then v_code := v_old.code;
    else
      v_prefix := case v_kind when 'raw' then 'RM' when 'wip' then 'WP' when 'finished' then 'FG'
                              when 'byproduct' then 'BP' else 'PK' end;
      loop
        v_code := rb_next_code('ITEM-' || v_prefix, v_prefix, 4);
        exit when not exists (select 1 from items where code = v_code);
      end loop;
    end if;
  end if;
  if v_id is null then
    insert into items (code, name, kind, base_unit, buy_unit, stages, prepared_item_id, shelf_life_days, byproduct_use,
                       sells_by, loose_price_paise, hsn_code, gst_rate, notes, created_by)
    values (v_code, rb_txt(p, 'name'), v_kind, v_base, coalesce(rb_txt(p, 'buy_unit'), v_base), v_stages,
            rb_int(p, 'prepared_item_id'), rb_int(p, 'shelf_life_days'),
            case when v_kind = 'byproduct' then rb_txt(p, 'byproduct_use') end,
            case when v_kind in ('finished', 'byproduct') then coalesce(rb_txt(p, 'sells_by'), 'pack') end,
            case when v_kind in ('finished', 'byproduct') then rb_int(p, 'loose_price_paise') end,
            rb_txt(p, 'hsn_code'), nullif(p->>'gst_rate', '')::numeric, rb_txt(p, 'notes'), v_me)
    returning id into v_id;
  else
    update items set code = v_code, name = rb_txt(p, 'name'), kind = v_kind, base_unit = v_base,
      buy_unit = coalesce(rb_txt(p, 'buy_unit'), v_base), stages = v_stages,
      prepared_item_id = rb_int(p, 'prepared_item_id'), shelf_life_days = rb_int(p, 'shelf_life_days'),
      byproduct_use = case when v_kind = 'byproduct' then rb_txt(p, 'byproduct_use') end,
      sells_by = case when v_kind in ('finished', 'byproduct') then coalesce(rb_txt(p, 'sells_by'), 'pack') end,
      loose_price_paise = case when v_kind in ('finished', 'byproduct') then rb_int(p, 'loose_price_paise') end,
      hsn_code = rb_txt(p, 'hsn_code'), gst_rate = nullif(p->>'gst_rate', '')::numeric, notes = rb_txt(p, 'notes'),
      updated_at = now(), updated_by = v_me
    where id = v_id;
  end if;
  if exists (select 1 from items i join items w on w.id = i.prepared_item_id where i.id = v_id and w.kind <> 'wip') then
    raise exception 'The "becomes" item must be a prepared ingredient (work in progress).';
  end if;
  return v_id;
exception when unique_violation then
  raise exception 'An item with that name or code already exists.';
end $$;

create or replace function rb_set_item_active(p_id int, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('masters.edit', 'switch items on or off');
begin
  update items set is_active = p_active, updated_at = now(), updated_by = v_me where id = p_id;
  if not found then raise exception 'Item not found.'; end if;
end $$;

create or replace function rb_delete_item(p_id int)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform rb_require('masters.delete', 'delete items');
  if exists (select 1 from journal_lines where item_id = p_id) then
    raise exception 'This item has entries in the books. Switch it off instead.';
  end if;
  delete from product_packs where item_id = p_id;
  delete from items where id = p_id;
exception when foreign_key_violation then
  raise exception 'This item is still used elsewhere (for example as a pack''s empty bottle). Switch it off instead.';
end $$;

create or replace function rb_save_pack_type(p jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare v_id int := rb_int(p, 'id'); v_me uuid; v_code text := upper(rb_txt(p, 'code'));
begin
  v_me := rb_require(case when v_id is null then 'masters.add' else 'masters.edit' end, 'change pack types');
  if rb_txt(p, 'name') is null then raise exception 'Please enter the pack name, e.g. 200 g bottle.'; end if;
  if rb_int(p, 'packaging_item_id') is not null and not exists
     (select 1 from items where id = rb_int(p, 'packaging_item_id') and kind = 'packaging') then
    raise exception 'The empty bottle or pouch must be a packaging item.';
  end if;
  if v_code is null then v_code := coalesce((select code from pack_types where id = v_id), rb_next_code('PACK', 'PT', 3)); end if;
  if v_id is null then
    insert into pack_types (code, name, kind, packaging_item_id, created_by)
    values (v_code, rb_txt(p, 'name'), coalesce(rb_txt(p, 'kind'), 'bottle'), rb_int(p, 'packaging_item_id'), v_me)
    returning id into v_id;
  else
    update pack_types set code = v_code, name = rb_txt(p, 'name'), kind = coalesce(rb_txt(p, 'kind'), 'bottle'),
      packaging_item_id = rb_int(p, 'packaging_item_id'),
      is_active = coalesce((p->>'is_active')::boolean, is_active), updated_at = now(), updated_by = v_me
    where id = v_id;
  end if;
  return v_id;
exception when unique_violation then
  raise exception 'A pack type with that code already exists.';
end $$;

create or replace function rb_save_product_pack(p jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare v_id int := rb_int(p, 'id'); v_me uuid;
begin
  v_me := rb_require(case when v_id is null then 'masters.add' else 'masters.edit' end, 'change product packs');
  if not exists (select 1 from items where id = rb_int(p, 'item_id') and kind in ('finished', 'byproduct')) then
    raise exception 'Only finished goods (and sellable by-products) are packed for sale.';
  end if;
  if coalesce((p->>'net_qty')::numeric, 0) <= 0 then raise exception 'Please enter how much one pack holds.'; end if;
  if v_id is null then
    insert into product_packs (item_id, pack_type_id, net_qty, retail_price_paise, trader_price_paise, online_price_paise, created_by)
    values (rb_int(p, 'item_id'), rb_int(p, 'pack_type_id'), (p->>'net_qty')::numeric, rb_int(p, 'retail_price_paise'),
            rb_int(p, 'trader_price_paise'), rb_int(p, 'online_price_paise'), v_me)
    returning id into v_id;
  else
    update product_packs set pack_type_id = rb_int(p, 'pack_type_id'), net_qty = (p->>'net_qty')::numeric,
      retail_price_paise = rb_int(p, 'retail_price_paise'), trader_price_paise = rb_int(p, 'trader_price_paise'),
      online_price_paise = rb_int(p, 'online_price_paise'),
      is_active = coalesce((p->>'is_active')::boolean, is_active), updated_at = now(), updated_by = v_me
    where id = v_id;
  end if;
  return v_id;
exception when unique_violation then
  raise exception 'This product already has that pack. Change the existing line instead.';
end $$;

-- ---------------------------------------------------------------------
-- 7. Customers and suppliers
-- ---------------------------------------------------------------------

create or replace function rb_save_customer(p jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_id int := rb_int(p, 'id'); v_me uuid; v_kind text := coalesce(rb_txt(p, 'kind'), 'retail');
  v_req text[]; f text; v_phone text := rb_txt(p, 'phone'); v_promo boolean := coalesce((p->>'send_promotions')::boolean, false);
  v_old customers;
begin
  v_me := rb_require(case when v_id is null then 'customers.add' else 'customers.edit' end,
                     case when v_id is null then 'add customers' else 'change customers' end);
  if rb_txt(p, 'name') is null then raise exception 'Please enter the customer''s name.'; end if;
  if v_kind = 'trader' then
    select trader_required_fields into v_req from app_settings where id = 1;
    foreach f in array coalesce(v_req, '{}') loop
      if rb_txt(p, f) is null then
        raise exception 'For a trader, % is required (set in Settings).', replace(f, '_', ' ');
      end if;
    end loop;
  end if;
  if v_promo and v_phone is null then raise exception 'Enter a phone number to send promotions.'; end if;
  if v_id is not null then
    select * into v_old from customers where id = v_id;
    if v_old.id is null then raise exception 'Customer not found.'; end if;
    if v_old.is_walk_in and v_kind <> 'retail' then raise exception 'The walk-in customer stays a retail customer.'; end if;
  end if;
  if v_id is null then
    insert into customers (code, kind, name, phone, send_promotions, promotions_consent_at, address, email, gstin, state_code,
                           contact_person, credit_limit_paise, credit_days, notes, created_by)
    values (rb_next_code('CUSTOMER', 'C', 5), v_kind, rb_txt(p, 'name'), v_phone, v_promo, case when v_promo then now() end,
            rb_txt(p, 'address'), lower(rb_txt(p, 'email')), upper(rb_txt(p, 'gstin')), rb_txt(p, 'state_code'),
            rb_txt(p, 'contact_person'), rb_int(p, 'credit_limit_paise'), rb_int(p, 'credit_days'), rb_txt(p, 'notes'), v_me)
    returning id into v_id;
  else
    update customers set kind = v_kind, name = rb_txt(p, 'name'), phone = v_phone, send_promotions = v_promo,
      promotions_consent_at = case when v_promo and not v_old.send_promotions then now()
                                   when not v_promo then null else promotions_consent_at end,
      address = rb_txt(p, 'address'), email = lower(rb_txt(p, 'email')), gstin = upper(rb_txt(p, 'gstin')),
      state_code = rb_txt(p, 'state_code'), contact_person = rb_txt(p, 'contact_person'),
      credit_limit_paise = rb_int(p, 'credit_limit_paise'), credit_days = rb_int(p, 'credit_days'),
      notes = rb_txt(p, 'notes'), is_active = coalesce((p->>'is_active')::boolean, is_active),
      updated_at = now(), updated_by = v_me
    where id = v_id;
  end if;
  return v_id;
end $$;

create or replace function rb_save_supplier(p jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare v_id int := rb_int(p, 'id'); v_me uuid;
begin
  v_me := rb_require(case when v_id is null then 'suppliers.add' else 'suppliers.edit' end,
                     case when v_id is null then 'add suppliers' else 'change suppliers' end);
  if rb_txt(p, 'name') is null then raise exception 'Please enter the supplier''s name.'; end if;
  if v_id is null then
    insert into suppliers (code, kind, name, phone, address, email, gstin, state_code, contact_person, credit_days,
                           usually_no_bill, notes, created_by)
    values (rb_next_code('SUPPLIER', 'S', 5), coalesce(rb_txt(p, 'kind'), 'local'), rb_txt(p, 'name'), rb_txt(p, 'phone'),
            rb_txt(p, 'address'), lower(rb_txt(p, 'email')), upper(rb_txt(p, 'gstin')), rb_txt(p, 'state_code'),
            rb_txt(p, 'contact_person'), rb_int(p, 'credit_days'), coalesce((p->>'usually_no_bill')::boolean, false),
            rb_txt(p, 'notes'), v_me)
    returning id into v_id;
  else
    update suppliers set kind = coalesce(rb_txt(p, 'kind'), 'local'), name = rb_txt(p, 'name'), phone = rb_txt(p, 'phone'),
      address = rb_txt(p, 'address'), email = lower(rb_txt(p, 'email')), gstin = upper(rb_txt(p, 'gstin')),
      state_code = rb_txt(p, 'state_code'), contact_person = rb_txt(p, 'contact_person'),
      credit_days = rb_int(p, 'credit_days'), usually_no_bill = coalesce((p->>'usually_no_bill')::boolean, false),
      notes = rb_txt(p, 'notes'), is_active = coalesce((p->>'is_active')::boolean, is_active),
      updated_at = now(), updated_by = v_me
    where id = v_id;
    if not found then raise exception 'Supplier not found.'; end if;
  end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- 8. Departments: add, rename, merge, undo, switch off, delete
-- ---------------------------------------------------------------------

create or replace function rb_dept_refresh(p_dept int)
returns void language sql security definer set search_path = public as $$
  update departments d set
    name = rb_dept_name(d.id, current_date),
    merged_into = (select case when x <> d.id then x end from rb_dept_resolve(d.id, current_date) x),
    updated_at = now()
  where d.id = p_dept
$$;

create or replace function rb_add_department(p_code text, p_name text)
returns int language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('masters.add', 'add departments'); v_id int;
begin
  if coalesce(trim(p_code), '') = '' or coalesce(trim(p_name), '') = '' then
    raise exception 'Please enter the department code and name.';
  end if;
  insert into departments (code, original_name, name, created_by)
  values (upper(trim(p_code)), trim(p_name), trim(p_name), v_me) returning id into v_id;
  return v_id;
exception when unique_violation then
  raise exception 'A department with the code % already exists.', upper(trim(p_code));
end $$;

-- p_from null = all history; a date = entries from that date onwards.
create or replace function rb_rename_department(p_dept int, p_name text, p_from date, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.departments', 'rename departments');
begin
  if coalesce(trim(p_name), '') = '' then raise exception 'Please enter the new name.'; end if;
  if not exists (select 1 from departments where id = p_dept) then raise exception 'Department not found.'; end if;
  insert into dept_events (dept_id, kind, new_name, effective_from, note, created_by)
  values (p_dept, 'rename', trim(p_name), p_from, p_note, v_me);
  perform rb_dept_refresh(p_dept);
end $$;

create or replace function rb_merge_department(p_from_dept int, p_into int, p_from date, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.departments', 'merge departments');
begin
  if p_from_dept = p_into then raise exception 'Choose two different departments.'; end if;
  if not exists (select 1 from departments where id = p_into and is_active and merged_into is null) then
    raise exception 'The department to merge into must be open.';
  end if;
  if rb_dept_resolve(p_into, coalesce(p_from, current_date)) = p_from_dept then
    raise exception 'That would merge the department into itself.';
  end if;
  insert into dept_events (dept_id, kind, into_dept_id, effective_from, note, created_by)
  values (p_from_dept, 'merge', p_into, p_from, p_note, v_me);
  update departments set is_active = false, updated_by = v_me where id = p_from_dept;
  perform rb_dept_refresh(p_from_dept);
end $$;

create or replace function rb_undo_department_change(p_event int)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.departments', 'undo department changes'); v_e dept_events;
begin
  select * into v_e from dept_events where id = p_event and undone_at is null;
  if v_e.id is null then raise exception 'That change was already undone.'; end if;
  update dept_events set undone_at = now(), undone_by = v_me where id = p_event;
  if v_e.kind = 'merge' and not exists (select 1 from dept_events where dept_id = v_e.dept_id and kind = 'merge' and undone_at is null) then
    update departments set is_active = true, updated_by = v_me where id = v_e.dept_id;
  end if;
  perform rb_dept_refresh(v_e.dept_id);
end $$;

create or replace function rb_set_department_active(p_dept int, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('masters.edit', 'switch departments on or off');
begin
  if p_active and exists (select 1 from departments where id = p_dept and merged_into is not null) then
    raise exception 'This department was merged. Undo the merge to open it again.';
  end if;
  update departments set is_active = p_active, updated_at = now(), updated_by = v_me where id = p_dept;
  if not found then raise exception 'Department not found.'; end if;
end $$;

create or replace function rb_delete_department(p_dept int)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform rb_require('power.departments', 'delete departments');
  if exists (select 1 from journal_lines where department_id = p_dept) then
    raise exception 'This department has been used, so it cannot be deleted. Merge it or switch it off instead.';
  end if;
  if exists (select 1 from dept_events where into_dept_id = p_dept and undone_at is null) then
    raise exception 'Other departments were merged into this one. Undo those merges first.';
  end if;
  delete from departments where id = p_dept;
end $$;

-- ---------------------------------------------------------------------
-- 9. Chart of accounts and posting rules: changes by the Accountant
-- ---------------------------------------------------------------------

create or replace function rb_save_account(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('accounts.edit', 'change the chart of accounts');
        v_code text := rb_txt(p, 'code'); v_a accounts; v_active boolean;
begin
  select * into v_a from accounts where code = v_code;
  if v_a.code is null then raise exception 'Account % not found.', v_code; end if;
  if v_a.level = 'family' then raise exception 'Family headers are not posted to and cannot be changed.'; end if;
  v_active := coalesce((p->>'e002_active')::boolean, v_a.e002_active);
  if not v_active and exists (select 1 from posting_rules where account_code = v_code) then
    raise exception 'Posting rules still use %. Point those rules at another account first.', v_code;
  end if;
  update accounts set
    local_name  = case when p ? 'local_name' then rb_txt(p, 'local_name') else local_name end,
    name        = case when source = 'local' and rb_txt(p, 'name') is not null then rb_txt(p, 'name') else name end,
    e002_active = v_active,
    cash_flow   = coalesce(rb_txt(p, 'cash_flow'), cash_flow),
    updated_at  = now(), updated_by = v_me
  where code = v_code;
end $$;

-- Add a Ruchi Buds account inside an existing family (detail code 05 to 95).
create or replace function rb_add_local_account(p jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('accounts.edit', 'add accounts'); v_code text := rb_txt(p, 'code'); v_f accounts;
begin
  if v_code !~ '^\d{8}$' or right(v_code, 2) = '00' then
    raise exception 'The code must be 8 digits and must not end in 00.';
  end if;
  select * into v_f from accounts where code = left(v_code, 6) || '00' and level = 'family';
  if v_f.code is null then raise exception 'There is no family % in the chart. New families are added by the group.', left(v_code, 6) || '00'; end if;
  if exists (select 1 from accounts where code = v_code) then raise exception 'Account % already exists.', v_code; end if;
  if rb_txt(p, 'name') is null then raise exception 'Please enter the account name.'; end if;
  insert into accounts (code, name, class, statement, normal_balance, level, status, subledger, e002_active, cash_flow, source, updated_by)
  select v_code, rb_txt(p, 'name'), v_f.class, v_f.statement,
         coalesce(rb_txt(p, 'normal_balance'), (select normal_balance from accounts where family_code = v_f.code and level = 'posting' limit 1), 'Debit'),
         'posting', 'Active', (select subledger from accounts where family_code = v_f.code and level = 'posting' limit 1),
         true, coalesce(rb_txt(p, 'cash_flow'), (select cash_flow from accounts where family_code = v_f.code and level = 'posting' limit 1), 'operating'),
         'local', v_me;
  return v_code;
end $$;

-- Load or refresh the chart from the group's Master COA workbook (rows read in the browser).
-- Adds new accounts and refreshes names; never deletes or renumbers an account.
create or replace function rb_import_accounts(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('accounts.edit', 'import the chart of accounts');
        r jsonb; v_code text; v_new int := 0; v_upd int := 0; v_skip int := 0; v_fam text;
begin
  for r in select * from jsonb_array_elements(p_rows) loop
    v_code := regexp_replace(coalesce(r->>'code', ''), '\D', '', 'g');
    if v_code !~ '^\d{8}$' or coalesce(trim(r->>'name'), '') = '' then v_skip := v_skip + 1; continue; end if;
    if right(v_code, 2) = '00' then v_skip := v_skip + 1; continue; end if;  -- family headers come from the group
    v_fam := left(v_code, 6) || '00';
    if not exists (select 1 from accounts where code = v_fam) then
      insert into accounts (code, name, class, statement, normal_balance, level, e002_active, cash_flow)
      values (v_fam, coalesce(nullif(r->>'subledger', ''), 'Family') || ' ' || left(v_code, 6), coalesce(r->>'class', 'Asset'),
              coalesce(nullif(r->>'statement', ''), 'BS'), 'Either', 'family', true, 'none');
    end if;
    if exists (select 1 from accounts where code = v_code) then
      update accounts set name = trim(r->>'name'), class = coalesce(nullif(r->>'class', ''), class),
        subledger = coalesce(nullif(r->>'subledger', ''), subledger), standard = coalesce(nullif(r->>'standard', ''), standard),
        status = coalesce(nullif(r->>'status', ''), status), updated_at = now(), updated_by = v_me
      where code = v_code and source = 'master' and level = 'posting'
        and (name, class, coalesce(subledger, ''), coalesce(standard, ''), status) is distinct from
            (trim(r->>'name'), coalesce(nullif(r->>'class', ''), class), coalesce(nullif(r->>'subledger', ''), subledger, ''),
             coalesce(nullif(r->>'standard', ''), standard, ''), coalesce(nullif(r->>'status', ''), status));
      if found then v_upd := v_upd + 1; end if;
    else
      if coalesce(r->>'statement', '') not in ('BS', 'PL', 'CONSOL') or coalesce(r->>'normal_balance', '') not in ('Debit', 'Credit', 'Either') then
        v_skip := v_skip + 1; continue;
      end if;
      insert into accounts (code, name, class, statement, normal_balance, status, subledger, standard, level,
                            e002_active, cash_flow, source, updated_by)
      values (v_code, trim(r->>'name'), coalesce(r->>'class', ''), r->>'statement', r->>'normal_balance',
              coalesce(nullif(r->>'status', ''), 'Active'), nullif(r->>'subledger', ''), nullif(r->>'standard', ''), 'posting',
              false, 'operating', 'master', v_me);
      v_new := v_new + 1;
    end if;
  end loop;
  perform rb_audit_write('IMPORT_COA', 'accounts', null, null,
    jsonb_build_object('added', v_new, 'updated', v_upd, 'skipped', v_skip), null);
  return jsonb_build_object('added', v_new, 'updated', v_upd, 'skipped', v_skip);
end $$;

create or replace function rb_set_posting_rule(p_event text, p_key text, p_account text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('accounts.edit', 'change posting rules');
begin
  if not exists (select 1 from accounts where code = p_account and level = 'posting' and e002_active) then
    raise exception 'Account % is not a posting account shown for Ruchi Buds.', p_account;
  end if;
  update posting_rules set account_code = p_account, updated_at = now(), updated_by = v_me
  where event_code = p_event and line_key = p_key;
  if not found then raise exception 'Posting rule not found.'; end if;
end $$;

create or replace function rb_save_ledger_settings(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('settings.edit', 'change the ledger settings');
begin
  update app_settings set
    manual_journal_second_person = coalesce((p->>'manual_journal_second_person')::boolean, manual_journal_second_person),
    stock_valuation = coalesce(rb_txt(p, 'stock_valuation'), stock_valuation),
    updated_at = now(), updated_by = v_me
  where id = 1;
end $$;

-- ---------------------------------------------------------------------
-- 10. Month lock
-- ---------------------------------------------------------------------

create or replace function rb_lock_period(p_month date, p_lock boolean, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.lock_periods', 'lock or unlock months');
        v_m date := date_trunc('month', p_month)::date;
begin
  if p_month is null then raise exception 'Please choose the month.'; end if;
  if not p_lock and coalesce(trim(p_note), '') = '' then
    raise exception 'Please give a reason for unlocking the month.';
  end if;
  if p_lock and exists (select 1 from journals where status = 'draft' and date_trunc('month', journal_date) = v_m) then
    raise exception 'There are draft journals in %. Post or delete them before locking the month.', to_char(v_m, 'Mon-YYYY');
  end if;
  insert into periods (month, is_locked, locked_at, locked_by, note, updated_at, updated_by)
  values (v_m, p_lock, case when p_lock then now() end, case when p_lock then v_me end, p_note, now(), v_me)
  on conflict (month) do update set is_locked = p_lock,
    locked_at = case when p_lock then now() else periods.locked_at end,
    locked_by = case when p_lock then v_me else periods.locked_by end,
    note = p_note, updated_at = now(), updated_by = v_me;
end $$;

-- ---------------------------------------------------------------------
-- 11. The journal engine
-- ---------------------------------------------------------------------

-- Posted journals and their lines are never edited. Corrections are
-- reversals. Only the rb_ functions below may change them (they switch
-- rb.ledger on for the moment they need it), plus the DEMO and go-live clean-ups.
create or replace function rb_journal_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_on boolean := coalesce(current_setting('rb.ledger', true), '') = 'on';
        v_status text;
begin
  if tg_table_name = 'journals' then
    if tg_op = 'UPDATE' and old.status <> 'draft' and not v_on then
      raise exception 'Posted journals cannot be changed. Reverse the journal instead.';
    end if;
    if tg_op = 'DELETE' and old.status <> 'draft' and not v_on and not old.is_demo
       and not (old.is_training and rb_is_training()) then
      raise exception 'Posted journals cannot be deleted. Reverse the journal instead.';
    end if;
    return coalesce(new, old);
  end if;
  -- journal_lines
  if tg_op = 'UPDATE' and not v_on then
    raise exception 'Journal lines cannot be changed once saved. Save the draft again instead.';
  end if;
  select status into v_status from journals where id = coalesce(new.journal_id, old.journal_id);
  if v_status is not null and v_status <> 'draft' and not v_on then
    if tg_op = 'INSERT' then raise exception 'Lines cannot be added to a posted journal.'; end if;
    if tg_op = 'DELETE' and not old.is_demo and not (old.is_training and rb_is_training()) then
      raise exception 'Lines of a posted journal cannot be deleted. Reverse the journal instead.';
    end if;
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists rb_journal_guard on journals;
create trigger rb_journal_guard before update or delete on journals
  for each row execute function rb_journal_guard();
drop trigger if exists rb_journal_guard on journal_lines;
create trigger rb_journal_guard before insert or update or delete on journal_lines
  for each row execute function rb_journal_guard();

-- Check one line against the chart's rules. p_source = 'manual' for hand-keyed journals.
create or replace function rb_check_line(p_line journal_lines, p_source text)
returns void language plpgsql stable security definer set search_path = public as $$
declare v_a accounts; v_self text;
begin
  select * into v_a from accounts where code = p_line.account_code;
  if v_a.code is null then raise exception 'Line %: account % is not in the chart.', p_line.line_no, p_line.account_code; end if;
  if v_a.level <> 'posting' then raise exception 'Line %: % is a family header and cannot be posted to.', p_line.line_no, v_a.code; end if;
  if not v_a.e002_active or v_a.status <> 'Active' then
    raise exception 'Line %: account % % is not used by Ruchi Buds.', p_line.line_no, v_a.code, v_a.name;
  end if;
  if v_a.statement = 'CONSOL' then raise exception 'Line %: consolidation accounts are only used by the group.', p_line.line_no; end if;
  if p_line.department_id is null then raise exception 'Line %: please choose the department.', p_line.line_no; end if;
  if p_source <> 'reversal' and not exists (select 1 from departments where id = p_line.department_id and is_active) then
    raise exception 'Line %: that department is closed or merged. Choose an open one.', p_line.line_no;
  end if;
  if v_a.control_type = 'item' then
    if p_source = 'manual' then
      raise exception 'Line %: stock accounts (%) are posted only from the Purchases, Stock and Sales screens, so stock and the books always agree.', p_line.line_no, v_a.code;
    end if;
    if p_line.item_id is null then raise exception 'Line %: stock account % needs the item.', p_line.line_no, v_a.code; end if;
  end if;
  if v_a.control_type = 'customer' and p_line.customer_id is null then
    raise exception 'Line %: % needs the customer, so the customer ledger agrees with the books.', p_line.line_no, v_a.code;
  end if;
  if v_a.control_type = 'supplier' and p_line.supplier_id is null then
    raise exception 'Line %: % needs the supplier, so the supplier ledger agrees with the books.', p_line.line_no, v_a.code;
  end if;
  if v_a.control_type = 'partner' and rb_partner_name(p_line.partner_id) is null then
    raise exception 'Line %: % needs the partner.', p_line.line_no, v_a.code;
  end if;
  if v_a.control_type = 'intercompany' then
    select code into v_self from entities where is_self;
    if p_line.counterparty_entity is null or p_line.counterparty_entity = v_self then
      raise exception 'Line %: intercompany account % needs the other group business (entity code).', p_line.line_no, v_a.code;
    end if;
  end if;
end $$;

-- Check a whole journal before posting.
create or replace function rb_check_journal(p_id bigint)
returns void language plpgsql stable security definer set search_path = public as $$
declare v_j journals; v_l journal_lines; v_dr bigint; v_cr bigint; v_n int;
begin
  select * into v_j from journals where id = p_id;
  if v_j.id is null then raise exception 'Journal not found.'; end if;
  if coalesce(trim(v_j.narration), '') = '' then raise exception 'Please say what the journal is for.'; end if;
  perform rb_assert_period_open(v_j.journal_date);
  select count(*), coalesce(sum(debit_paise), 0), coalesce(sum(credit_paise), 0) into v_n, v_dr, v_cr
  from journal_lines where journal_id = p_id;
  if v_n < 2 then raise exception 'A journal needs at least two lines.'; end if;
  if v_dr <> v_cr then
    raise exception 'Debits (₹%) and credits (₹%) must be equal. Difference ₹%.',
      to_char(v_dr / 100.0, 'FM99,99,99,99,990.00'), to_char(v_cr / 100.0, 'FM99,99,99,99,990.00'),
      to_char(abs(v_dr - v_cr) / 100.0, 'FM99,99,99,99,990.00');
  end if;
  for v_l in select * from journal_lines where journal_id = p_id order by line_no loop
    perform rb_check_line(v_l, v_j.source);
  end loop;
end $$;

-- Write lines for a journal from JSON. Each line has account_code (or rule = 'event.key'),
-- and either debit_paise / credit_paise, or amount_paise (on the rule's side; negative flips it).
create or replace function rb_write_lines(p_id bigint, p_lines jsonb, p_default_dept int)
returns void language plpgsql security definer set search_path = public as $$
declare v_j journals; l jsonb; i int := 0; v_acc text; v_side text; v_amt bigint; v_dr bigint; v_cr bigint; v_rule posting_rules;
begin
  select * into v_j from journals where id = p_id;
  for l in select * from jsonb_array_elements(coalesce(p_lines, '[]')) loop
    v_acc := rb_txt(l, 'account_code'); v_dr := coalesce(rb_int(l, 'debit_paise'), 0); v_cr := coalesce(rb_int(l, 'credit_paise'), 0);
    if rb_txt(l, 'rule') is not null then
      select * into v_rule from posting_rules
      where event_code = split_part(l->>'rule', '.', 1) and line_key = split_part(l->>'rule', '.', 2);
      if v_rule.event_code is null then raise exception 'Unknown posting rule %.', l->>'rule'; end if;
      v_acc := v_rule.account_code;
      if l ? 'amount_paise' then
        v_amt := rb_int(l, 'amount_paise');
        v_side := case when (v_amt >= 0) = (v_rule.side = 'debit') then 'debit' else 'credit' end;
        v_dr := case when v_side = 'debit' then abs(v_amt) else 0 end;
        v_cr := case when v_side = 'credit' then abs(v_amt) else 0 end;
      end if;
    end if;
    if v_acc is null and v_dr = 0 and v_cr = 0 then continue; end if;  -- blank row on the screen
    i := i + 1;
    if v_acc is null then raise exception 'Line %: please choose the account.', i; end if;
    if v_dr < 0 or v_cr < 0 then raise exception 'Line %: amounts cannot be negative.', i; end if;
    if (v_dr > 0) = (v_cr > 0) then raise exception 'Line %: enter either a debit or a credit.', i; end if;
    insert into journal_lines (journal_id, line_no, journal_date, account_code, department_id, debit_paise, credit_paise,
                               narration, customer_id, supplier_id, item_id, partner_id, counterparty_entity, currency,
                               is_demo, is_training)
    values (p_id, i, v_j.journal_date, v_acc, coalesce(rb_int(l, 'department_id')::int, p_default_dept), v_dr, v_cr,
            rb_txt(l, 'narration'), rb_int(l, 'customer_id'), rb_int(l, 'supplier_id'), rb_int(l, 'item_id'),
            rb_int(l, 'partner_id'), upper(rb_txt(l, 'counterparty_entity')), v_j.currency, v_j.is_demo, v_j.is_training);
  end loop;
  update journals set total_paise = (select coalesce(sum(debit_paise), 0) from journal_lines where journal_id = p_id)
  where id = p_id;
end $$;

-- Give a journal its number and mark it posted (caller has checked who may do it).
create or replace function rb_finish_post(p_id bigint, p_approver uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_j journals; v_no text; v_series text;
begin
  perform rb_check_journal(p_id);
  select * into v_j from journals where id = p_id;
  v_series := case when v_j.is_demo then 'DEMO' when v_j.is_training then 'TRN'
                   when v_j.source in ('manual', 'reversal', 'opening') then 'JV'
                   else 'JV-' || upper(v_j.source) end;
  v_no := coalesce(v_j.journal_no, rb_next_doc_no(v_series, v_j.journal_date));
  perform set_config('rb.ledger', 'on', true);
  update journals set status = 'posted', journal_no = v_no, approved_by = p_approver, posted_at = now()
  where id = p_id;
  perform set_config('rb.ledger', 'off', true);
  perform rb_audit_write('POST_JOURNAL', 'journals', p_id::text, null,
    jsonb_build_object('journal_no', v_no, 'date', v_j.journal_date, 'total_paise', v_j.total_paise,
                       'narration', v_j.narration, 'source', v_j.source), null);
  return v_no;
end $$;

-- For later modules (purchases, stock, sales, cash and bank ...): post a balanced
-- journal in one go. Not callable from the screens; each module's own rb_ function
-- checks the person's rights and then calls this inside the same transaction.
-- p_head: journal_date, narration, source, event_code, source_ref, department_id, is_demo, entered_by
create or replace function rb_post_engine(p_head jsonb, p_lines jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_me uuid := rb_current_user_id(); v_date date := (p_head->>'journal_date')::date;
begin
  perform rb_assert_period_open(v_date);
  insert into journals (journal_date, source, event_code, source_ref, narration, status, entered_by, is_demo, is_training,
                        entity_code, currency)
  select v_date, coalesce(rb_txt(p_head, 'source'), 'system'), rb_txt(p_head, 'event_code'), rb_txt(p_head, 'source_ref'),
         coalesce(rb_txt(p_head, 'narration'), 'Posting'), 'draft',
         coalesce((p_head->>'entered_by')::uuid, v_me), coalesce((p_head->>'is_demo')::boolean, false), rb_is_training(),
         s.entity_code, s.currency
  from app_settings s where s.id = 1
  returning id into v_id;
  perform rb_write_lines(v_id, p_lines, rb_int(p_head, 'department_id')::int);
  perform rb_finish_post(v_id, coalesce((p_head->>'approved_by')::uuid, v_me));
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- 12. Manual journals: save draft, post (approve), delete draft,
--     reverse, learning-phase delete
-- ---------------------------------------------------------------------

-- p: id (to change a draft), journal_date, narration, department_id (default for lines), lines [...]
create or replace function rb_save_journal(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint := rb_int(p, 'id'); v_me uuid; v_j journals; v_date date := (p->>'journal_date')::date;
begin
  v_me := rb_require(case when v_id is null then 'accounts.add' else 'accounts.edit' end,
                     case when v_id is null then 'enter journals' else 'change journals' end);
  perform rb_assert_period_open(v_date);
  if coalesce(trim(p->>'narration'), '') = '' then raise exception 'Please say what the journal is for.'; end if;
  if v_id is null then
    insert into journals (journal_date, source, narration, status, entered_by, is_training, entity_code, currency)
    select v_date, case when p->>'source' = 'opening' then 'opening' else 'manual' end, trim(p->>'narration'),
           'draft', v_me, rb_is_training(), s.entity_code, s.currency
    from app_settings s where s.id = 1
    returning id into v_id;
  else
    select * into v_j from journals where id = v_id;
    if v_j.id is null then raise exception 'Journal not found.'; end if;
    if v_j.status <> 'draft' then raise exception 'Only a draft can be changed. Reverse a posted journal instead.'; end if;
    if v_j.source not in ('manual', 'opening') then raise exception 'This journal comes from another screen and is changed there.'; end if;
    perform rb_assert_period_open(v_j.journal_date);
    delete from journal_lines where journal_id = v_id;
    update journals set journal_date = v_date, narration = trim(p->>'narration'),
      source = case when p->>'source' = 'opening' then 'opening' else 'manual' end,
      updated_at = now(), updated_by = v_me
    where id = v_id;
  end if;
  perform rb_write_lines(v_id, p->'lines', rb_int(p, 'department_id')::int);
  -- Check each line now, so mistakes show while the person is still on the screen.
  declare v_l journal_lines; v_src text;
  begin
    select source into v_src from journals where id = v_id;
    for v_l in select * from journal_lines where journal_id = v_id order by line_no loop
      perform rb_check_line(v_l, v_src);
    end loop;
  end;
  return v_id;
end $$;

-- May the signed-in person post (approve) this manual journal?
create or replace function rb_can_post_journal(p_id bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select rb_can_approve('accounts', j.entered_by)
       and (j.entered_by is distinct from rb_current_user_id()
            or not (select manual_journal_second_person from app_settings where id = 1))
    from journals j where j.id = p_id), false)
$$;

create or replace function rb_post_journal(p_id bigint)
returns text language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('accounts.approve', 'post (approve) journals'); v_j journals;
begin
  select * into v_j from journals where id = p_id for update;
  if v_j.id is null then raise exception 'Journal not found.'; end if;
  if v_j.status <> 'draft' then raise exception 'This journal is already posted.'; end if;
  perform rb_check_journal(p_id);  -- mistakes first, so the person who entered it can fix them
  if v_j.entered_by = v_me and (select manual_journal_second_person from app_settings where id = 1) then
    raise exception 'A manual journal must be approved by someone other than the person who entered it.';
  end if;
  if not rb_can_approve('accounts', v_j.entered_by) then
    raise exception 'You cannot approve your own entries.';
  end if;
  return rb_finish_post(p_id, v_me);
end $$;

create or replace function rb_delete_draft_journal(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('accounts.view', 'delete drafts'); v_j journals;
begin
  select * into v_j from journals where id = p_id;
  if v_j.id is null or v_j.status <> 'draft' then raise exception 'Only a draft can be deleted this way.'; end if;
  if v_j.entered_by is distinct from v_me and not rb_has('accounts.delete') then
    raise exception 'Only the person who entered this draft can delete it.';
  end if;
  delete from journals where id = p_id;
  perform rb_audit_write('DELETE_DRAFT', 'journals', p_id::text, to_jsonb(v_j), null, null);
end $$;

-- Reverse a posted journal with a mirror journal on p_date.
create or replace function rb_reverse_journal(p_id bigint, p_date date, p_reason text)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.reverse_entries', 'reverse posted entries'); v_j journals; v_new bigint;
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason for the reversal.'; end if;
  select * into v_j from journals where id = p_id for update;
  if v_j.id is null then raise exception 'Journal not found.'; end if;
  if v_j.status <> 'posted' then raise exception 'Only a posted journal that is not already reversed can be reversed.'; end if;
  if v_j.reversal_of is not null then raise exception 'This journal is itself a reversal.'; end if;
  if p_date < v_j.journal_date then raise exception 'The reversal date cannot be before the journal''s own date.'; end if;
  perform rb_assert_period_open(p_date);
  insert into journals (journal_date, source, event_code, source_ref, narration, status, reversal_of, reverse_reason,
                        entered_by, is_demo, is_training, entity_code, currency)
  values (p_date, 'reversal', v_j.event_code, v_j.journal_no, 'Reversal of ' || v_j.journal_no || ': ' || trim(p_reason),
          'draft', p_id, trim(p_reason), v_me, v_j.is_demo, v_j.is_training or rb_is_training(), v_j.entity_code, v_j.currency)
  returning id into v_new;
  insert into journal_lines (journal_id, line_no, journal_date, account_code, department_id, debit_paise, credit_paise,
                             narration, customer_id, supplier_id, item_id, partner_id, counterparty_entity, currency, is_demo, is_training)
  select v_new, line_no, p_date, account_code, department_id, credit_paise, debit_paise, narration, customer_id,
         supplier_id, item_id, partner_id, counterparty_entity, currency, is_demo, v_j.is_training or rb_is_training()
  from journal_lines where journal_id = p_id;
  update journals set total_paise = v_j.total_paise where id = v_new;
  perform rb_finish_post(v_new, v_me);
  perform set_config('rb.ledger', 'on', true);
  update journals set status = 'reversed', reversed_by = v_new, reverse_reason = trim(p_reason) where id = p_id;
  perform set_config('rb.ledger', 'off', true);
  perform rb_audit_write('REVERSE_JOURNAL', 'journals', p_id::text, null,
    jsonb_build_object('journal_no', v_j.journal_no, 'reversal_id', v_new, 'date', p_date), trim(p_reason));
  return v_new;
end $$;

-- Learning phase: a Director or the FC may fully delete a posted journal entered by
-- someone still in their learning phase. Not written to the audit log (spec section 4).
create or replace function rb_hard_delete_journal(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('accounts.delete', 'fully delete journals'); v_j journals;
begin
  select * into v_j from journals where id = p_id for update;
  if v_j.id is null then raise exception 'Journal not found.'; end if;
  if v_j.status = 'draft' then raise exception 'This is a draft: use Delete draft.'; end if;
  if not rb_can_hard_delete('accounts', v_j.entered_by) then
    raise exception 'Only entries made by someone still in their learning phase can be fully deleted. Reverse it instead.';
  end if;
  if v_j.reversed_by is not null or v_j.reversal_of is not null then
    raise exception 'This journal is part of a reversal pair. Reverse entries are kept.';
  end if;
  perform rb_assert_period_open(v_j.journal_date);
  perform set_config('rb.ledger', 'on', true);
  delete from journals where id = p_id;
  perform set_config('rb.ledger', 'off', true);
end $$;

-- ---------------------------------------------------------------------
-- 13. Reports: trial balance and account ledger
-- ---------------------------------------------------------------------

-- Balances are debit-positive. Profit and loss accounts start each
-- financial year at zero; earlier years' profit shows in Retained
-- Earnings - Opening until year-end closing journals arrive (module 8).
create or replace function rb_trial_balance(p_from date, p_to date, p_dept int default null, p_include_demo boolean default true)
returns table (account_code text, account_name text, class_code text, statement text, normal_balance text,
               cash_flow text, opening_paise bigint, debit_paise bigint, credit_paise bigint, closing_paise bigint)
language plpgsql stable security definer set search_path = public as $$
declare v_fy date;
begin
  perform rb_require('accounts.view', 'see the trial balance');
  if p_from is null or p_to is null or p_from > p_to then raise exception 'Please choose a From date on or before the To date.'; end if;
  v_fy := rb_fy_start(p_from);
  return query
  with l as (
    select jl.account_code as code, jl.journal_date as d, jl.debit_paise as dr, jl.credit_paise as cr, a.statement as st
    from journal_lines jl
    join journals j on j.id = jl.journal_id
    join accounts a on a.code = jl.account_code
    where j.status in ('posted', 'reversed') and jl.journal_date <= p_to
      and (p_include_demo or not jl.is_demo)
      and (p_dept is null or rb_dept_resolve(jl.department_id, jl.journal_date) = p_dept)
  ), agg as (
    select code,
           sum(case when d < p_from and (st <> 'PL' or d >= v_fy) then dr - cr else 0 end) as op,
           sum(case when d >= p_from then dr else 0 end) as sdr,
           sum(case when d >= p_from then cr else 0 end) as scr
    from l group by code
    union all
    select '50020105', sum(dr - cr), 0, 0 from l where st = 'PL' and d < v_fy having count(*) > 0
  )
  select a.code, coalesce(a.local_name, a.name), left(a.code, 2), a.statement, a.normal_balance, a.cash_flow,
         sum(agg.op)::bigint, sum(agg.sdr)::bigint, sum(agg.scr)::bigint, sum(agg.op + agg.sdr - agg.scr)::bigint
  from agg join accounts a on a.code = agg.code
  group by a.code
  having sum(abs(agg.op)) + sum(agg.sdr) + sum(agg.scr) <> 0
  order by a.code;
end $$;

-- One account's lines with a running balance. Filters are optional.
create or replace function rb_account_ledger(p_account text, p_from date, p_to date,
  p_customer int default null, p_supplier int default null, p_partner int default null, p_dept int default null)
returns table (journal_id bigint, journal_no text, journal_date date, narration text, department text,
               party text, debit_paise bigint, credit_paise bigint, balance_paise bigint, is_demo boolean, status text)
language plpgsql stable security definer set search_path = public as $$
declare v_open bigint; v_fy date; v_pl boolean;
begin
  perform rb_require('accounts.view', 'see account ledgers');
  if p_from is null or p_to is null or p_from > p_to then raise exception 'Please choose a From date on or before the To date.'; end if;
  v_fy := rb_fy_start(p_from);
  select statement = 'PL' into v_pl from accounts where code = p_account;
  if v_pl is null then raise exception 'Account % not found.', p_account; end if;
  select coalesce(sum(jl.debit_paise - jl.credit_paise), 0) into v_open
  from journal_lines jl join journals j on j.id = jl.journal_id
  where jl.account_code = p_account and j.status in ('posted', 'reversed')
    and jl.journal_date < p_from and (not v_pl or jl.journal_date >= v_fy)
    and (p_customer is null or jl.customer_id = p_customer) and (p_supplier is null or jl.supplier_id = p_supplier)
    and (p_partner is null or jl.partner_id = p_partner)
    and (p_dept is null or rb_dept_resolve(jl.department_id, jl.journal_date) = p_dept);
  return query
  select null::bigint, null::text, p_from, 'Opening balance'::text, null::text, null::text, null::bigint, null::bigint, v_open, false, null::text
  union all
  select x.journal_id, x.journal_no, x.journal_date, x.narration, x.department, x.party, x.debit_paise, x.credit_paise,
         (v_open + sum(x.debit_paise - x.credit_paise) over (order by x.journal_date, x.journal_id, x.line_no))::bigint,
         x.is_demo, x.status
  from (
    select j.id as journal_id, j.journal_no, jl.journal_date, coalesce(jl.narration, j.narration) as narration,
           rb_dept_label(jl.department_id, jl.journal_date) as department,
           coalesce(c.name, s.name, rb_partner_name(jl.partner_id), jl.counterparty_entity) as party,
           jl.debit_paise, jl.credit_paise, jl.is_demo, j.status, jl.line_no
    from journal_lines jl join journals j on j.id = jl.journal_id
    left join customers c on c.id = jl.customer_id
    left join suppliers s on s.id = jl.supplier_id
    where jl.account_code = p_account and j.status in ('posted', 'reversed')
      and jl.journal_date between p_from and p_to
      and (p_customer is null or jl.customer_id = p_customer) and (p_supplier is null or jl.supplier_id = p_supplier)
      and (p_partner is null or jl.partner_id = p_partner)
      and (p_dept is null or rb_dept_resolve(jl.department_id, jl.journal_date) = p_dept)
  ) x;
end $$;

-- One journal with its lines, for the journal screen.
create or replace function rb_journal_detail(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  perform rb_require('accounts.view', 'see journals');
  select to_jsonb(j) || jsonb_build_object(
    'entered_name', (select coalesce(short_name, full_name) from app_users where id = j.entered_by),
    'approved_name', (select coalesce(short_name, full_name) from app_users where id = j.approved_by),
    'can_post', j.status = 'draft' and rb_has('accounts.approve') and rb_can_post_journal(j.id),
    'can_reverse', j.status = 'posted' and j.reversal_of is null and rb_has('power.reverse_entries'),
    'can_hard_delete', j.status <> 'draft' and j.reversal_of is null and j.reversed_by is null
                       and rb_can_hard_delete('accounts', j.entered_by),
    'period_locked', rb_period_locked(j.journal_date),
    'lines', coalesce((select jsonb_agg(to_jsonb(l) || jsonb_build_object(
        'account_name', coalesce(a.local_name, a.name),
        'department', rb_dept_label(l.department_id, l.journal_date),
        'party', coalesce(c.name, s.name, rb_partner_name(l.partner_id), l.counterparty_entity)) order by l.line_no)
      from journal_lines l join accounts a on a.code = l.account_code
      left join customers c on c.id = l.customer_id left join suppliers s on s.id = l.supplier_id
      where l.journal_id = j.id), '[]'::jsonb))
  into v from journals j where j.id = p_id;
  return v;
end $$;

-- ---------------------------------------------------------------------
-- 14. Audit, row-level security and who may call what
-- ---------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array['units','items','pack_types','product_packs','customers','suppliers','departments',
                           'dept_events','accounts','posting_rules','periods','entities'] loop
    execute format('drop trigger if exists rb_audit on %I', t);
    execute format('create trigger rb_audit after insert or update or delete on %I
                    for each row execute function rb_audit_trigger()', t);
  end loop;
end $$;

do $$
declare t text;
begin
  foreach t in array array['entities','units','items','pack_types','product_packs','customers','suppliers',
    'departments','dept_events','accounts','posting_rules','periods','journals','journal_lines'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon, authenticated', t);
    execute format('grant select on %I to authenticated', t);
    execute format('grant all on %I to service_role', t);
    execute format('drop policy if exists rb_read on %I', t);
  end loop;
end $$;
revoke all on all sequences in schema public from anon, authenticated;

-- Lists every screen needs (items, packs, units, departments, accounts, months).
create policy rb_read on entities      for select to authenticated using (rb_current_user_id() is not null);
create policy rb_read on units         for select to authenticated using (rb_current_user_id() is not null);
create policy rb_read on items         for select to authenticated using (rb_current_user_id() is not null);
create policy rb_read on pack_types    for select to authenticated using (rb_current_user_id() is not null);
create policy rb_read on product_packs for select to authenticated using (rb_current_user_id() is not null);
create policy rb_read on departments   for select to authenticated using (rb_current_user_id() is not null);
create policy rb_read on dept_events   for select to authenticated using (rb_current_user_id() is not null);
create policy rb_read on accounts      for select to authenticated using (rb_current_user_id() is not null);
create policy rb_read on periods       for select to authenticated using (rb_current_user_id() is not null);
-- Customers and suppliers: only people who work with them.
create policy rb_read on customers for select to authenticated
  using (rb_has('customers.view') or rb_has('sales.view') or rb_has('invoices.view') or rb_has('receipts.view')
         or rb_has('accounts.view'));
create policy rb_read on suppliers for select to authenticated
  using (rb_has('suppliers.view') or rb_has('purchases.view') or rb_has('accounts.view'));
-- The books: Accounts and journals screen only.
create policy rb_read on posting_rules for select to authenticated using (rb_has('accounts.view'));
create policy rb_read on journals      for select to authenticated using (rb_has('accounts.view'));
create policy rb_read on journal_lines for select to authenticated using (rb_has('accounts.view'));

revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on all functions in schema public to service_role;
-- Module 1's grants again (the line above resets them).
grant execute on function rb_public_branding(), rb_login_failed(text) to anon, authenticated;
grant execute on function
  rb_current_user_id(), rb_has(text), rb_user_has(uuid, text), rb_user_perms(uuid),
  rb_my_profile(), rb_login_ok(), rb_password_changed(),
  rb_invite_user(text, text, text, text, smallint, date),
  rb_update_user(uuid, text, text, text, smallint, date),
  rb_set_user_active(uuid, boolean), rb_delete_invite(uuid), rb_unlock_user(uuid),
  rb_reset_password(uuid, text), rb_decide_password_reset(bigint, boolean),
  rb_create_category(text, text, text), rb_rename_category(smallint, text, text),
  rb_delete_category(smallint), rb_set_category_access(smallint, text, boolean),
  rb_set_user_access(uuid, text, boolean), rb_preview_user_perms(uuid),
  rb_save_settings(jsonb), rb_remove_demo_data(text), rb_go_live(date, text),
  rb_backup_tables(), rb_backup_rows(text, int, int), rb_log_backup(text, text, int, bigint, text),
  rb_in_learning_phase(uuid), rb_can_hard_delete(text, uuid), rb_can_approve(text, uuid),
  rb_is_training()
  to authenticated;
-- Module 2.
grant execute on function
  rb_txt(jsonb, text), rb_int(jsonb, text),
  rb_fy_start(date), rb_period_locked(date), rb_dept_resolve(int, date), rb_dept_name(int, date),
  rb_dept_label(int, date), rb_partner_name(int),
  rb_save_unit(jsonb), rb_save_item(jsonb), rb_set_item_active(int, boolean), rb_delete_item(int),
  rb_save_pack_type(jsonb), rb_save_product_pack(jsonb),
  rb_save_customer(jsonb), rb_save_supplier(jsonb),
  rb_add_department(text, text), rb_rename_department(int, text, date, text),
  rb_merge_department(int, int, date, text), rb_undo_department_change(int),
  rb_set_department_active(int, boolean), rb_delete_department(int),
  rb_save_account(jsonb), rb_add_local_account(jsonb), rb_import_accounts(jsonb),
  rb_set_posting_rule(text, text, text), rb_save_ledger_settings(jsonb), rb_lock_period(date, boolean, text),
  rb_save_journal(jsonb), rb_can_post_journal(bigint), rb_post_journal(bigint), rb_delete_draft_journal(bigint),
  rb_reverse_journal(bigint, date, text), rb_hard_delete_journal(bigint),
  rb_trial_balance(date, date, int, boolean),
  rb_account_ledger(text, date, date, int, int, int, int), rb_journal_detail(bigint)
  to authenticated;
-- Kept private: rb_post_engine, rb_finish_post, rb_write_lines, rb_check_line, rb_check_journal,
-- rb_next_code, rb_dept_refresh, rb_assert_period_open (later modules call them from their own functions).

-- ---------------------------------------------------------------------
-- 15. Starting departments, walk-in customer and DEMO data
-- ---------------------------------------------------------------------

-- A first department list (a guess; rename, merge or add to it in Masters
-- once the group list arrives). Codes follow the Master COA's CC001 style.
insert into departments (code, original_name, name) values
  ('CC001', 'Kitchen and production', 'Kitchen and production'),
  ('CC002', 'Retail counter',         'Retail counter'),
  ('CC003', 'Trade sales',            'Trade sales'),
  ('CC004', 'Online shop',            'Online shop'),
  ('CC005', 'Administration',         'Administration')
on conflict (code) do nothing;

-- A standing customer for anonymous counter sales.
insert into customers (code, kind, name, is_walk_in, notes)
select 'C00000', 'retail', 'Walk-in customer', true, 'For counter sales where the customer gives no name'
where not exists (select 1 from customers where is_walk_in);

-- DEMO records: only added while the app is in training mode, so a re-run
-- after go-live never brings them back.
do $$
declare
  v_train boolean := (select training_mode from app_settings where id = 1);
  v_ds uuid := (select id from app_users where lower(email) = 'info.ruchibuds@gmail.com');
  v_acc uuid := (select id from app_users where email = 'demo.accounts@example.com');
  d_kit int; d_ret int; d_adm int; d_trd int; d_evt int;
  v_j bigint; p1 int; p2 int; p3 int; v_sup int; v_cus int;
begin
  if not v_train or exists (select 1 from items where is_demo) then return; end if;

  -- Items
  insert into items (code, name, kind, base_unit, buy_unit, stages, shelf_life_days, byproduct_use, sells_by,
                     loose_price_paise, hsn_code, gst_rate, notes, is_demo) values
    ('D-WP01', 'Fish, cleaned and fried (DEMO)',    'wip', 'g', 'g', '{}', 1,  null, null, null, null, null, 'Used the same day', true),
    ('D-WP02', 'Chicken, shredded (DEMO)',          'wip', 'g', 'g', '{}', 1,  null, null, null, null, null, 'Used the same day', true),
    ('D-WP03', 'Meat, dried and shredded (DEMO)',   'wip', 'g', 'g', '{}', 30, null, null, null, null, null, 'Stored while drying', true),
    ('D-WP04', 'Ginger, peeled (DEMO)',             'wip', 'g', 'g', '{}', 14, null, null, null, null, null, null, true),
    ('D-WP05', 'Garlic, chopped (DEMO)',            'wip', 'g', 'g', '{}', 14, null, null, null, null, null, null, true),
    ('D-WP06', 'Onion, chopped (DEMO)',             'wip', 'g', 'g', '{}', 14, null, null, null, null, null, null, true),
    ('D-RM01', 'Fish, fresh (DEMO)',          'raw', 'g',  'kg', '{Clean,"Boil and de-bone",Fry}', null, null, null, null, '0302', 0, 'Bought from fishermen, no bill', true),
    ('D-RM02', 'Chicken (DEMO)',              'raw', 'g',  'kg', '{Skin,Boil,Debone,Shred}',       null, null, null, null, '0207', 0, null, true),
    ('D-RM03', 'Meat (DEMO)',                 'raw', 'g',  'kg', '{Debone,Dry,Crush,Shred}',       null, null, null, null, '0201', 0, null, true),
    ('D-RM04', 'Dried meat (DEMO)',           'raw', 'g',  'kg', '{}', null, null, null, null, '0210', 5, 'Separate item from smoked dried meat', true),
    ('D-RM05', 'Smoked dried meat (DEMO)',    'raw', 'g',  'kg', '{}', null, null, null, null, '0210', 5, null, true),
    ('D-RM06', 'Ginger (DEMO)',               'raw', 'g',  'kg', '{Wash,Peel}',  null, null, null, null, '0910', 0, null, true),
    ('D-RM07', 'Garlic (DEMO)',               'raw', 'g',  'kg', '{Peel,Chop}',  null, null, null, null, '0703', 0, null, true),
    ('D-RM08', 'Onion (DEMO)',                'raw', 'g',  'kg', '{Peel,Chop}',  null, null, null, null, '0703', 0, null, true),
    ('D-RM09', 'Mustard oil (DEMO)',          'raw', 'ml', 'l',  '{}', null, null, null, null, '1514', 5, null, true),
    ('D-RM10', 'Dried red chilli (DEMO)',     'raw', 'g',  'kg', '{}', null, null, null, null, '0904', 0, null, true),
    ('D-FG01', 'Fish pickle (DEMO)',          'finished', 'g', 'g', '{}', null, null, 'pack',   null,   '2001', 12, null, true),
    ('D-FG02', 'Chicken pickle (DEMO)',       'finished', 'g', 'g', '{}', null, null, 'pack',   null,   '2001', 12, null, true),
    ('D-FG03', 'Smoked meat pickle (DEMO)',   'finished', 'g', 'g', '{}', null, null, 'pack',   null,   '2001', 12, null, true),
    ('D-FG04', 'Chilli powder (DEMO)',        'finished', 'g', 'g', '{}', null, null, 'weight', 60000,  '0904', 5,  'Also sold loose by weight (price per kg)', true),
    ('D-FG05', 'Rice flakes (DEMO)',          'finished', 'g', 'g', '{}', null, null, 'pack',   null,   '1904', 5,  null, true),
    ('D-FG06', 'Mango pulp (DEMO)',           'finished', 'g', 'g', '{}', null, null, 'pack',   null,   '2007', 12, null, true),
    ('D-BP01', 'Fish bones (DEMO)',           'byproduct', 'g', 'g', '{}', null, 'discarded', null, null, null, null, null, true),
    ('D-BP02', 'Chicken skin (DEMO)',         'byproduct', 'g', 'g', '{}', null, 'sellable', 'weight', 8000, null, null, null, true),
    ('D-BP03', 'Meat trimmings (DEMO)',       'byproduct', 'g', 'g', '{}', null, 'sellable', 'weight', 15000, null, null, null, true),
    ('D-PK01', 'Glass bottle, 200 g (DEMO)',  'packaging', 'pc', 'box', '{}', null, null, null, null, '7010', 18, null, true),
    ('D-PK02', 'Glass bottle, 500 g (DEMO)',  'packaging', 'pc', 'box', '{}', null, null, null, null, '7010', 18, null, true),
    ('D-PK03', 'Stand-up pouch, 250 g (DEMO)','packaging', 'pc', 'pc',  '{}', null, null, null, null, '3923', 18, null, true),
    ('D-PK04', 'Stand-up pouch, 1 kg (DEMO)', 'packaging', 'pc', 'pc',  '{}', null, null, null, null, '3923', 18, null, true);
  update items r set prepared_item_id = w.id from (values
    ('D-RM01', 'D-WP01'), ('D-RM02', 'D-WP02'), ('D-RM03', 'D-WP03'), ('D-RM06', 'D-WP04'),
    ('D-RM07', 'D-WP05'), ('D-RM08', 'D-WP06')) m(raw, wip)
  join items w on w.code = m.wip where r.code = m.raw;

  -- Pack types and what each product holds in them
  insert into pack_types (code, name, kind, packaging_item_id, is_demo)
  select v.code, v.name, v.kind, (select id from items where code = v.pk), true
  from (values ('D-PT1', '200 g bottle (DEMO)', 'bottle', 'D-PK01'), ('D-PT2', '500 g bottle (DEMO)', 'bottle', 'D-PK02'),
               ('D-PT3', '250 g pouch (DEMO)', 'pouch', 'D-PK03'),  ('D-PT4', '1 kg pouch (DEMO)', 'pouch', 'D-PK04')) v(code, name, kind, pk);
  insert into product_packs (item_id, pack_type_id, net_qty, retail_price_paise, trader_price_paise, online_price_paise, is_demo)
  select (select id from items where code = v.item), (select id from pack_types where code = v.pack), v.qty,
         v.retail, v.trader, v.online, true
  from (values
    ('D-FG01', 'D-PT1', 200,  28000, 24000, 30000), ('D-FG01', 'D-PT2', 500,  65000, 56000, 69000),
    ('D-FG02', 'D-PT1', 200,  26000, 22000, 28000), ('D-FG02', 'D-PT2', 500,  60000, 52000, 64000),
    ('D-FG03', 'D-PT1', 200,  35000, 30000, 37000),
    ('D-FG04', 'D-PT1', 100,   9000,  7500,  9500), ('D-FG04', 'D-PT4', 1000, 55000, 48000, 58000),
    ('D-FG05', 'D-PT1', 120,   6000,  5000,  6500), ('D-FG05', 'D-PT3', 250,  11000,  9500, 12000),
    ('D-FG06', 'D-PT2', 450,  22000, 19000, 24000)) v(item, pack, qty, retail, trader, online);

  -- Customers (one retail customer has opted in to promotions)
  insert into customers (code, kind, name, phone, send_promotions, promotions_consent_at, address, email, gstin,
                         contact_person, credit_limit_paise, credit_days, is_demo) values
    ('DEMO-C01', 'retail', 'Anita Sharma (DEMO)',      '9810000001', true,  now(), null, null, null, null, null, null, true),
    ('DEMO-C02', 'retail', 'Rahul Verma (DEMO)',       '9810000002', false, null, null, null, null, null, null, null, true),
    ('DEMO-C03', 'retail', 'Meena Iyer (DEMO)',        null,         false, null, null, null, null, null, null, null, true),
    ('DEMO-C04', 'retail', 'Joseph D''Souza (DEMO)',   '9810000004', true,  now(), 'Bandra, Mumbai', 'joseph@example.com', null, null, null, null, true),
    ('DEMO-C05', 'retail', 'Farah Khan (DEMO)',        '9810000005', false, null, null, null, null, null, null, null, true),
    ('DEMO-C06', 'trader', 'Sai Provision Store (DEMO)',  '9820000006', false, null, 'Dadar Market, Mumbai', null, null, 'Mr Sai', 2000000, 15, true),
    ('DEMO-C07', 'trader', 'Konkan Foods (DEMO)',        '9820000007', false, null, 'Ratnagiri', 'orders@example.com', '27AAAAA0000A1Z5', 'Ms Patil', 5000000, 30, true),
    ('DEMO-C08', 'trader', 'Green Basket Mart (DEMO)',   '9820000008', false, null, 'Thane', null, null, 'Mr Rao', 1500000, 7, true),
    ('DEMO-C09', 'trader', 'Hill Top Caterers (DEMO)',   '9820000009', false, null, 'Pune', null, null, 'Mrs Joshi', 1000000, 15, true),
    ('DEMO-C10', 'trader', 'Coastal Delights (DEMO)',    '9820000010', false, null, 'Alibag', null, null, 'Mr Naik', 2500000, 30, true);

  -- Suppliers
  insert into suppliers (code, kind, name, phone, address, gstin, contact_person, credit_days, usually_no_bill, is_demo) values
    ('DEMO-S01', 'fisherman', 'Raju Koli, fisherman (DEMO)',   '9830000001', 'Sassoon Dock', null, null, 0, true, true),
    ('DEMO-S02', 'fisherman', 'Suresh Tandel, fisherman (DEMO)','9830000002', 'Versova', null, null, 0, true, true),
    ('DEMO-S03', 'local',     'Fresh Chicken Centre (DEMO)',   '9830000003', 'Andheri', null, 'Imran', 0, false, true),
    ('DEMO-S04', 'local',     'Highland Meats (DEMO)',          '9830000004', 'Dharavi', null, null, 7, false, true),
    ('DEMO-S05', 'farmer',    'Patil Farm Produce (DEMO)',      '9830000005', 'Nashik', null, null, 0, true, true),
    ('DEMO-S06', 'company',   'Sharma Spices Pvt Ltd (DEMO)',   '9830000006', 'Vashi APMC', '27BBBBB1111B1Z2', 'Mr Sharma', 30, false, true),
    ('DEMO-S07', 'company',   'Kalpana Oils (DEMO)',            '9830000007', 'Navi Mumbai', '27CCCCC2222C1Z3', null, 15, false, true),
    ('DEMO-S08', 'company',   'Clearview Glass Bottles (DEMO)', '9830000008', 'Bhiwandi', '27DDDDD3333D1Z4', 'Ms Gupta', 30, false, true),
    ('DEMO-S09', 'company',   'FlexiPack Pouches (DEMO)',       '9830000009', 'Vasai', '27EEEEE4444E1Z5', null, 30, false, true),
    ('DEMO-S10', 'local',     'Gas Agency Andheri (DEMO)',      '9830000010', 'Andheri', null, null, 0, false, true);

  -- A DEMO department, renamed from a date, to show how history is kept.
  insert into departments (code, original_name, name, is_demo) values ('CC090', 'Food fairs (DEMO)', 'Food fairs (DEMO)', true)
  returning id into d_evt;
  insert into dept_events (dept_id, kind, new_name, effective_from, note, is_demo)
  values (d_evt, 'rename', 'Events and food fairs (DEMO)', '2026-11-01', 'Example: renamed from 01-Nov-2026', true);
  perform rb_dept_refresh(d_evt);

  -- DEMO journals in Oct and Nov 2026
  select id into d_kit from departments where code = 'CC001';
  select id into d_ret from departments where code = 'CC002';
  select id into d_trd from departments where code = 'CC003';
  select id into d_adm from departments where code = 'CC005';
  select (e->>'id')::int into p1 from app_settings s, jsonb_array_elements(s.partners) with ordinality x(e, n) where n = 1;
  select (e->>'id')::int into p2 from app_settings s, jsonb_array_elements(s.partners) with ordinality x(e, n) where n = 2;
  select (e->>'id')::int into p3 from app_settings s, jsonb_array_elements(s.partners) with ordinality x(e, n) where n = 3;
  p2 := coalesce(p2, p1); p3 := coalesce(p3, p1);

  perform rb_post_engine(jsonb_build_object('journal_date', '2026-10-01', 'source', 'opening', 'is_demo', true,
    'narration', 'Opening capital in cash, partner ' || coalesce(rb_partner_name(p1), '1') || ' (DEMO)',
    'department_id', d_adm, 'entered_by', v_acc, 'approved_by', v_ds),
    jsonb_build_array(jsonb_build_object('rule', 'opening.cash', 'amount_paise', 1000000),
                      jsonb_build_object('rule', 'opening.capital', 'amount_paise', 1000000, 'partner_id', p1)));
  perform rb_post_engine(jsonb_build_object('journal_date', '2026-10-01', 'source', 'opening', 'is_demo', true,
    'narration', 'Opening capital in cash, partner ' || coalesce(rb_partner_name(p2), '2') || ' (DEMO)',
    'department_id', d_adm, 'entered_by', v_acc, 'approved_by', v_ds),
    jsonb_build_array(jsonb_build_object('rule', 'opening.cash', 'amount_paise', 1000000),
                      jsonb_build_object('rule', 'opening.capital', 'amount_paise', 1000000, 'partner_id', p2)));
  perform rb_post_engine(jsonb_build_object('journal_date', '2026-10-01', 'source', 'opening', 'is_demo', true,
    'narration', 'Opening capital in cash, partner ' || coalesce(rb_partner_name(p3), '3') || ' (DEMO)',
    'department_id', d_adm, 'entered_by', v_acc, 'approved_by', v_ds),
    jsonb_build_array(jsonb_build_object('rule', 'opening.cash', 'amount_paise', 1000000),
                      jsonb_build_object('rule', 'opening.capital', 'amount_paise', 1000000, 'partner_id', p3)));
  perform rb_post_engine(jsonb_build_object('journal_date', '2026-10-05', 'source', 'manual', 'is_demo', true,
    'narration', 'Cash paid into the bank (DEMO)', 'department_id', d_adm, 'entered_by', v_acc, 'approved_by', v_ds),
    jsonb_build_array(jsonb_build_object('account_code', '10010205', 'debit_paise', 1500000),
                      jsonb_build_object('account_code', '10010110', 'credit_paise', 1500000)));
  perform rb_post_engine(jsonb_build_object('journal_date', '2026-10-31', 'source', 'manual', 'is_demo', true,
    'narration', 'Kitchen rent for October, paid by bank (DEMO)', 'department_id', d_kit, 'entered_by', v_acc, 'approved_by', v_ds),
    jsonb_build_array(jsonb_build_object('rule', 'expense.rent_kitchen', 'amount_paise', 600000),
                      jsonb_build_object('account_code', '10010205', 'credit_paise', 600000)));
  perform rb_post_engine(jsonb_build_object('journal_date', '2026-10-31', 'source', 'manual', 'is_demo', true,
    'narration', 'Bank charges for October (DEMO)', 'department_id', d_adm, 'entered_by', v_acc, 'approved_by', v_ds),
    jsonb_build_array(jsonb_build_object('rule', 'expense.bank_charges', 'amount_paise', 5900),
                      jsonb_build_object('account_code', '10010205', 'credit_paise', 5900)));
  perform rb_post_engine(jsonb_build_object('journal_date', '2026-11-03', 'source', 'manual', 'is_demo', true,
    'narration', 'Two gas cylinders for the kitchen, cash (DEMO)', 'department_id', d_kit, 'entered_by', v_acc, 'approved_by', v_ds),
    jsonb_build_array(jsonb_build_object('rule', 'expense.gas_power', 'amount_paise', 220000),
                      jsonb_build_object('account_code', '10010110', 'credit_paise', 220000)));
  perform rb_post_engine(jsonb_build_object('journal_date', '2026-11-07', 'source', 'manual', 'is_demo', true,
    'narration', 'Printed price labels and leaflets, cash (DEMO)', 'department_id', d_ret, 'entered_by', v_acc, 'approved_by', v_ds),
    jsonb_build_array(jsonb_build_object('account_code', '80030105', 'debit_paise', 120000),
                      jsonb_build_object('account_code', '10010110', 'credit_paise', 120000)));
  perform rb_post_engine(jsonb_build_object('journal_date', '2026-11-10', 'source', 'manual', 'is_demo', true,
    'narration', 'Drawings by a partner, cash (DEMO)', 'department_id', d_adm, 'entered_by', v_acc, 'approved_by', v_ds),
    jsonb_build_array(jsonb_build_object('rule', 'drawings.partner_current', 'amount_paise', 200000, 'partner_id', p2),
                      jsonb_build_object('rule', 'drawings.cash', 'amount_paise', 200000)));
  -- A trader opening balance through the customer subledger
  select id into v_cus from customers where code = 'DEMO-C06';
  perform rb_post_engine(jsonb_build_object('journal_date', '2026-11-12', 'source', 'manual', 'is_demo', true,
    'narration', 'Sai Provision Store: pickles supplied at the October fair, billed on credit (DEMO)', 'department_id', d_trd,
    'entered_by', v_acc, 'approved_by', v_ds),
    jsonb_build_array(jsonb_build_object('rule', 'sale.receivable', 'amount_paise', 480000, 'customer_id', v_cus),
                      jsonb_build_object('rule', 'sale.revenue_trader', 'amount_paise', 480000)));
  -- A supplier bill for the gas agency, paid later
  select id into v_sup from suppliers where code = 'DEMO-S10';
  perform rb_post_engine(jsonb_build_object('journal_date', '2026-11-15', 'source', 'manual', 'is_demo', true,
    'narration', 'Gas agency: cylinder deposit on credit (DEMO)', 'department_id', d_kit, 'entered_by', v_acc, 'approved_by', v_ds),
    jsonb_build_array(jsonb_build_object('account_code', '20050130', 'debit_paise', 300000),
                      jsonb_build_object('account_code', '30010105', 'credit_paise', 300000, 'supplier_id', v_sup)));
  -- A mistake, then its reversal
  v_j := rb_post_engine(jsonb_build_object('journal_date', '2026-11-18', 'source', 'manual', 'is_demo', true,
    'narration', 'Office supplies, entered twice by mistake (DEMO)', 'department_id', d_adm, 'entered_by', v_acc, 'approved_by', v_ds),
    jsonb_build_array(jsonb_build_object('account_code', '80020120', 'debit_paise', 50000),
                      jsonb_build_object('account_code', '10010110', 'credit_paise', 50000)));
  declare v_rev bigint;
  begin
    insert into journals (journal_date, source, source_ref, narration, status, reversal_of, reverse_reason, entered_by, is_demo, is_training)
    select '2026-11-18', 'reversal', journal_no, 'Reversal of ' || journal_no || ': entered twice (DEMO)', 'draft', id,
           'Entered twice', v_acc, true, true from journals where id = v_j
    returning id into v_rev;
    insert into journal_lines (journal_id, line_no, journal_date, account_code, department_id, debit_paise, credit_paise, is_demo, is_training)
    select v_rev, line_no, journal_date, account_code, department_id, credit_paise, debit_paise, true, true
    from journal_lines where journal_id = v_j;
    update journals set total_paise = 50000 where id = v_rev;
    perform rb_finish_post(v_rev, v_ds);
    perform set_config('rb.ledger', 'on', true);
    update journals set status = 'reversed', reversed_by = v_rev, reverse_reason = 'Entered twice' where id = v_j;
    perform set_config('rb.ledger', 'off', true);
  end;
  -- A draft waiting for approval
  insert into journals (journal_date, source, narration, status, entered_by, is_demo, is_training)
  values ('2026-11-20', 'manual', 'Mobile phone recharge for orders, cash (DEMO)', 'draft', v_acc, true, true)
  returning id into v_j;
  perform rb_write_lines(v_j, jsonb_build_array(
    jsonb_build_object('account_code', '80020115', 'debit_paise', 39900),
    jsonb_build_object('account_code', '10010110', 'credit_paise', 39900)), d_adm);
end $$;

-- End of 02_masters.sql
