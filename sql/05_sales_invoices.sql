-- =====================================================================
-- RUCHI BUDS APP · Module 5: Sales, invoices and customer balances (AR)
-- File: 05_sales_invoices.sql · Version 1.2 · 27-Nov-2026
-- 1.2: a delivery charge on an invoice, and an online order keeps the price
--      the customer was shown (used by the online shop, module 10).
-- 1.1: bad debts. An unpaid invoice (or an earlier balance) can be written
--      off with a reason by the FC or a Director, and money later
--      received from that customer can be booked as bad debts recovered.
--
-- What this file sets up:
--   Sales from finished-goods stock, by pack (e.g. 200 g bottle) or
--   loose by weight, at the retail, trader or online price, with a
--   discount per line as a % or an amount. Every sale is an invoice
--   numbered Inv/YYMM/00001: the running number never restarts and YYMM
--   follows the invoice date. Each invoice is an "Invoice" (no GST) or,
--   once the firm is GST registered, a "Tax Invoice" (CGST and SGST, or
--   IGST for another state). Paid at the counter (cash, UPI, bank), on
--   credit, or part of each. Returns entered by staff and approved by a
--   second person, each with its credit note CN/YYMM/00001; refunds by
--   the accounts team only. Customer receipts against open invoices,
--   money on account, customer balances with ageing, the customer ledger
--   and statements (printable, and shareable as a link), and a sales
--   summary by day, product and customer type. Bad debts written off
--   (BD/YYMM/00001) and bad debts recovered (BDR/YYMM/00001).
--
-- Accounting (Indian AS, ICAI): revenue is recognised when the goods are
-- handed over and the invoice is raised (AS 9). Sales are credited at
-- the full price before discount and the discount is shown separately;
-- GST charged is a liability (Output GST), never revenue. The cost of
-- the goods sold leaves finished-goods stock at weighted average cost
-- (AS 2). A return is booked as Sales returns, with its GST given back
-- and its stock put back at the cost it left at (or, if spoilt, charged
-- as a stock loss). The customer balance is the "Trade Receivables"
-- account kept per customer, so the customer ledger always agrees with
-- the books. A bad debt written off is charged to "Bad Debt
-- Write-offs" and taken off the customer balance; money later received
-- for it is income ("Other Non-operating Income", bad debts recovered).
-- The provision for doubtful debts at month-end comes with module 6.
--
-- GST: until the "GST registered from" date in Settings, no GST is
-- charged and only "Invoice" can be chosen. From that date, "Tax
-- Invoice" can be chosen; it needs the firm's GSTIN, address and state
-- code, and an HSN code and GST rate on each product.
--
-- Run 01, 02, 03 and 04 first. Then: Supabase -> SQL Editor -> New query
-- -> paste this whole file -> Run. It is safe to run again; nothing you
-- entered is lost on a re-run.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Screens and settings
-- ---------------------------------------------------------------------

update screens set available = true where code in ('sales', 'invoices', 'customers', 'receipts');

-- Are the selling prices in Masters what the customer pays, GST included
-- (like an MRP)? Only matters on a Tax Invoice.
alter table app_settings add column if not exists sale_prices_include_gst boolean not null default true;
-- Printed at the foot of every invoice (bank details, thank-you line).
alter table app_settings add column if not exists invoice_footer text;
-- How long a shared customer statement link stays open.
alter table app_settings add column if not exists statement_link_days int not null default 30;
-- New right: write off bad debts and book their recovery. Directors and
-- the FC always have every right; no other category gets it by default.
insert into powers (code, name, description, sort) values
  ('write_off_debts', 'Write off bad debts', 'Write off an unpaid invoice or balance as a bad debt, and book money later recovered', 67)
on conflict (code) do nothing;
insert into permissions (code, kind, power_code, sort) values ('power.write_off_debts', 'power', 'write_off_debts', 10067)
on conflict (code) do nothing;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'app_settings_statement_link_days_check') then
    alter table app_settings add constraint app_settings_statement_link_days_check check (statement_link_days between 1 and 365);
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------

-- One row per invoice.
create table if not exists sales (
  id                   bigserial primary key,
  invoice_no           text unique,
  doc_type             text not null default 'invoice' check (doc_type in ('invoice', 'tax_invoice')),
  invoice_date         date not null,
  entity_code          text not null default 'E002' references entities(code),
  currency             text not null default 'INR',
  customer_id          int not null references customers(id),
  channel              text not null check (channel in ('retail', 'trader', 'online')),
  department_id        int not null references departments(id),
  -- The customer's details as printed on the invoice
  bill_name            text not null,
  bill_phone           text,
  bill_address         text,
  bill_gstin           text,
  bill_state_code      text,
  place_of_supply      text,
  inter_state          boolean not null default false,
  show_hsn             boolean not null default true,
  prices_include_gst   boolean not null default false,
  -- Totals (the customer pays total_paise)
  gross_paise          bigint not null default 0,     -- before discount, as priced
  discount_paise       bigint not null default 0,
  taxable_paise        bigint not null default 0,
  cgst_paise           bigint not null default 0,
  sgst_paise           bigint not null default 0,
  igst_paise           bigint not null default 0,
  total_paise          bigint not null default 0,
  cost_paise           bigint not null default 0,     -- cost of the goods sold (AS 2)
  -- Payment
  payment_mode         text not null default 'cash' check (payment_mode in ('cash', 'upi', 'bank', 'credit')),
  paid_at_sale_paise   bigint not null default 0 check (paid_at_sale_paise >= 0),
  payment_ref          text,
  credited_paise       bigint not null default 0,     -- receipts and credit notes set against it later
  outstanding_paise    bigint not null default 0,
  due_date             date,
  status               text not null default 'open' check (status in ('open', 'paid', 'cancelled')),
  note                 text,
  credit_limit_override boolean not null default false,
  journal_id           bigint references journals(id) on delete set null,
  reversal_journal_id  bigint references journals(id) on delete set null,
  cancel_reason        text,
  cancelled_at         timestamptz,
  cancelled_by         uuid,
  entered_by           uuid references app_users(id),
  entered_at           timestamptz not null default now(),
  is_demo              boolean not null default false,
  is_training          boolean not null default false
);
create index if not exists sales_customer_idx on sales (customer_id);
create index if not exists sales_date_idx on sales (invoice_date);

create table if not exists sale_lines (
  id                 bigserial primary key,
  sale_id            bigint not null references sales(id) on delete cascade,
  line_no            int not null,
  item_id            int not null references items(id),
  pack_id            int references product_packs(id),
  packs              numeric(14,3),                -- pack lines: number of bottles or pouches
  qty_base           numeric(16,3) not null check (qty_base > 0),  -- grams, ml or pieces
  description        text not null,
  rate_paise         bigint not null check (rate_paise >= 0),      -- per pack, or per kg / litre / piece when loose
  list_rate_paise    bigint,                                       -- the Masters price on the day
  gross_paise        bigint not null,
  discount_pct       numeric(6,2),
  discount_paise     bigint not null default 0 check (discount_paise >= 0),
  hsn_code           text,
  gst_rate           numeric(5,2) not null default 0,
  taxable_paise      bigint not null,
  cgst_paise         bigint not null default 0,
  sgst_paise         bigint not null default 0,
  igst_paise         bigint not null default 0,
  total_paise        bigint not null,
  rev_gross_paise    bigint not null,              -- revenue before discount, without GST
  rev_discount_paise bigint not null default 0,    -- discount, without GST
  cost_paise         bigint not null default 0,
  is_demo            boolean not null default false,
  is_training        boolean not null default false,
  unique (sale_id, line_no)
);
create index if not exists sale_lines_sale_idx on sale_lines (sale_id);

-- Goods brought back, each with its credit note.
create table if not exists sales_returns (
  id                  bigserial primary key,
  return_no           text unique,                  -- the credit note number, CN/YYMM/00001
  sale_id             bigint not null references sales(id) on delete cascade,
  customer_id         int not null references customers(id),
  return_date         date not null,
  reason              text not null,
  condition           text not null default 'restock' check (condition in ('restock', 'discard')),
  taxable_paise       bigint not null default 0,
  cgst_paise          bigint not null default 0,
  sgst_paise          bigint not null default 0,
  igst_paise          bigint not null default 0,
  total_paise         bigint not null default 0,
  cost_paise          bigint not null default 0,
  status              text not null default 'awaiting_approval'
                      check (status in ('awaiting_approval', 'posted', 'refused', 'reversed')),
  department_id       int not null references departments(id),
  journal_id          bigint references journals(id) on delete set null,
  reversal_journal_id bigint references journals(id) on delete set null,
  refused_reason      text,
  reverse_reason      text,
  entered_by          uuid references app_users(id),
  entered_at          timestamptz not null default now(),
  approved_by         uuid references app_users(id),
  posted_at           timestamptz,
  is_demo             boolean not null default false,
  is_training         boolean not null default false
);
create index if not exists sales_returns_sale_idx on sales_returns (sale_id);

create table if not exists sales_return_lines (
  id             bigserial primary key,
  return_id      bigint not null references sales_returns(id) on delete cascade,
  sale_line_id   bigint not null references sale_lines(id) on delete cascade,
  packs          numeric(14,3),
  qty_base       numeric(16,3) not null check (qty_base > 0),
  taxable_paise  bigint not null,
  cgst_paise     bigint not null default 0,
  sgst_paise     bigint not null default 0,
  igst_paise     bigint not null default 0,
  total_paise    bigint not null,
  cost_paise     bigint not null default 0,
  is_demo        boolean not null default false,
  is_training    boolean not null default false
);

-- Money received from customers after the sale.
create table if not exists customer_receipts (
  id                  bigserial primary key,
  receipt_no          text not null unique,
  customer_id         int not null references customers(id),
  receipt_date        date not null,
  mode                text not null check (mode in ('cash', 'upi', 'bank')),
  amount_paise        bigint not null check (amount_paise > 0),
  reference           text,
  note                text,
  department_id       int references departments(id),
  status              text not null default 'posted' check (status in ('posted', 'reversed')),
  journal_id          bigint references journals(id) on delete set null,
  reversal_journal_id bigint references journals(id) on delete set null,
  reverse_reason      text,
  entered_by          uuid references app_users(id),
  entered_at          timestamptz not null default now(),
  is_demo             boolean not null default false,
  is_training         boolean not null default false
);
create index if not exists customer_receipts_customer_idx on customer_receipts (customer_id);

-- Money paid back to customers (accounts team only).
create table if not exists customer_refunds (
  id                  bigserial primary key,
  refund_no           text not null unique,
  customer_id         int not null references customers(id),
  return_id           bigint references sales_returns(id) on delete set null,
  refund_date         date not null,
  mode                text not null check (mode in ('cash', 'upi', 'bank')),
  amount_paise        bigint not null check (amount_paise > 0),
  reference           text,
  reason              text not null,
  department_id       int references departments(id),
  status              text not null default 'posted' check (status in ('posted', 'reversed')),
  journal_id          bigint references journals(id) on delete set null,
  reversal_journal_id bigint references journals(id) on delete set null,
  reverse_reason      text,
  entered_by          uuid references app_users(id),
  entered_at          timestamptz not null default now(),
  is_demo             boolean not null default false,
  is_training         boolean not null default false
);

-- Which invoices a receipt or a credit note settles. No invoice (sale_id
-- blank) = it settles an earlier balance with no invoice in the app, such
-- as an opening balance at go-live or one entered by journal.
create table if not exists ar_allocations (
  id            bigserial primary key,
  sale_id       bigint references sales(id) on delete cascade,
  receipt_id    bigint references customer_receipts(id) on delete cascade,
  return_id     bigint references sales_returns(id) on delete cascade,
  amount_paise  bigint not null check (amount_paise > 0),
  created_at    timestamptz not null default now(),
  created_by    uuid,
  is_demo       boolean not null default false,
  is_training   boolean not null default false,
  check ((receipt_id is null) <> (return_id is null))
);
alter table ar_allocations alter column sale_id drop not null;
create index if not exists ar_allocations_sale_idx on ar_allocations (sale_id);

-- Customer statement links that can be opened without signing in.
create table if not exists statement_links (
  token        text primary key,
  customer_id  int not null references customers(id) on delete cascade,
  from_date    date not null,
  expires_at   timestamptz not null,
  revoked_at   timestamptz,
  created_by   uuid references app_users(id),
  created_at   timestamptz not null default now(),
  opened_count int not null default 0,
  last_opened  timestamptz,
  is_demo      boolean not null default false,
  is_training  boolean not null default false
);

-- Bad debts written off: one invoice, or an earlier balance (sale_id blank).
create table if not exists customer_write_offs (
  id                  bigserial primary key,
  write_off_no        text not null unique,
  customer_id         int not null references customers(id),
  sale_id             bigint references sales(id) on delete cascade,
  write_off_date      date not null,
  amount_paise        bigint not null check (amount_paise > 0),
  reason              text not null,
  department_id       int references departments(id),
  status              text not null default 'posted' check (status in ('posted', 'reversed')),
  journal_id          bigint references journals(id) on delete set null,
  reversal_journal_id bigint references journals(id) on delete set null,
  reverse_reason      text,
  entered_by          uuid references app_users(id),
  entered_at          timestamptz not null default now(),
  is_demo             boolean not null default false,
  is_training         boolean not null default false
);
create index if not exists customer_write_offs_customer_idx on customer_write_offs (customer_id);
alter table sales add column if not exists written_off_paise bigint not null default 0;
-- 1.2: delivery charge billed on the invoice (without GST), and the GST on it.
alter table sales add column if not exists delivery_paise bigint not null default 0;
alter table sales add column if not exists delivery_gst_paise bigint not null default 0;

-- Money received later for a bad debt: booked as income, and the money on
-- account it came in as is set against it (allocations with recovery_id).
create table if not exists bad_debt_recoveries (
  id                  bigserial primary key,
  recovery_no         text not null unique,
  write_off_id        bigint not null references customer_write_offs(id) on delete cascade,
  customer_id         int not null references customers(id),
  recovery_date       date not null,
  amount_paise        bigint not null check (amount_paise > 0),
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
alter table ar_allocations add column if not exists recovery_id bigint;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'ar_allocations_recovery_fk') then
    alter table ar_allocations add constraint ar_allocations_recovery_fk foreign key (recovery_id) references bad_debt_recoveries(id) on delete cascade;
  end if;
end $$;

-- Stock movements now also name the invoice or return that made them.
alter table stock_moves add column if not exists sale_id bigint;
alter table stock_moves add column if not exists sales_return_id bigint;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'stock_moves_sale_fk') then
    alter table stock_moves add constraint stock_moves_sale_fk foreign key (sale_id) references sales(id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'stock_moves_sreturn_fk') then
    alter table stock_moves add constraint stock_moves_sreturn_fk foreign key (sales_return_id) references sales_returns(id) on delete cascade;
  end if;
end $$;
create index if not exists stock_moves_sale_idx on stock_moves (sale_id) where sale_id is not null;

-- ---------------------------------------------------------------------
-- 3. Posting rules for this module (module 2 listed the main ones)
-- ---------------------------------------------------------------------

insert into posting_rules (event_code, line_key, side, account_code, module, label, sort) values
  ('sale',            'revenue_byproduct', 'credit', '60010130', 5, 'By-product sales (skin, trimmings)', 85),
  ('sale',            'delivery',          'credit', '60060125', 5, 'Delivery charge billed on the invoice (without GST)', 86),
  ('sales_return',    'output_gst',        'debit',  '30030105', 5, 'Output GST given back on a credit note', 96),
  ('sales_return',    'stock_finished',    'debit',  '10030125', 5, 'Returned goods back into stock, at the cost they left at', 97),
  ('sales_return',    'cost_of_sales',     'credit', '70010160', 5, 'Cost of the returned goods taken off cost of sales', 98),
  ('sales_return',    'write_off',         'debit',  '70010150', 5, 'Returned goods spoilt: charged as a stock loss', 98),
  ('customer_refund', 'receivable',        'debit',  '10020105', 5, 'Refund to a customer (per customer)', 103),
  ('customer_refund', 'cash',              'credit', '10010110', 5, 'Refund paid in cash', 104),
  ('customer_refund', 'bank',              'credit', '10010205', 5, 'Refund paid by UPI or bank', 105),
  ('bad_debt',        'expense',           'debit',  '80080110', 5, 'Bad debt written off', 106),
  ('bad_debt',        'receivable',        'credit', '10020105', 5, 'Bad debt taken off the customer balance (per customer)', 107),
  ('bad_debt_recovery', 'receivable',      'debit',  '10020105', 5, 'Bad debt recovered: back on the customer balance, set against the money received', 108),
  ('bad_debt_recovery', 'income',          'credit', '90010135', 5, 'Bad debts recovered (other income)', 109)
on conflict (event_code, line_key) do nothing;
-- Refunds have their own entry now (above), so this one from module 2 is not used.
delete from posting_rules where event_code = 'sales_return' and line_key = 'refund_cash';
update posting_rules set label = 'Retail sales (before discount, without GST)' where event_code = 'sale' and line_key = 'revenue_retail';
update posting_rules set label = 'Trader (wholesale) sales (before discount, without GST)' where event_code = 'sale' and line_key = 'revenue_trader';
update posting_rules set label = 'Online sales (before discount, without GST)' where event_code = 'sale' and line_key = 'revenue_online';
update posting_rules set label = 'Discount given on the invoice (without GST)' where event_code = 'sale' and line_key = 'discount';
update posting_rules set label = 'Sales returns (credit notes, without GST)' where event_code = 'sales_return' and line_key = 'returns';
update posting_rules set label = 'Credit note: reduces the customer''s balance' where event_code = 'sales_return' and line_key = 'receivable';

-- ---------------------------------------------------------------------
-- 4. Helpers (private)
-- ---------------------------------------------------------------------

-- Who may see costs and margins (Directors, the FC, the Accountant).
create or replace function rb_sal_cost_ok()
returns boolean language sql stable security definer set search_path = public as $$
  select rb_has('sales.margin') or rb_has('invoices.margin') or rb_has('accounts.view')
$$;

-- Who may see money totals, customer balances and ledgers.
create or replace function rb_sal_money_ok()
returns boolean language sql stable security definer set search_path = public as $$
  select rb_has('power.see_totals') and (rb_has('sales.view') or rb_has('invoices.view') or rb_has('customers.view')
                                         or rb_has('receipts.view') or rb_has('accounts.view'))
$$;

-- The department a sale counts under, by channel.
create or replace function rb_sal_dept(p_channel text)
returns int language sql stable security definer set search_path = public as $$
  select coalesce((select id from departments where code = case p_channel when 'trader' then 'CC003' when 'online' then 'CC004'
                                                                          else 'CC002' end and is_active),
                  rb_pur_default_dept())
$$;

-- The Masters price of a pack (or loose per kg / litre / piece) for a channel.
create or replace function rb_sal_list_price(p_item int, p_pack int, p_channel text)
returns bigint language sql stable security definer set search_path = public as $$
  select case when p_pack is not null then
                (select case p_channel when 'trader' then coalesce(trader_price_paise, retail_price_paise)
                                       when 'online' then coalesce(online_price_paise, retail_price_paise)
                                       else retail_price_paise end from product_packs where id = p_pack)
              else (select loose_price_paise from items where id = p_item) end
$$;

-- Amount for a loose quantity: price is per kg (grams), per litre (ml) or per piece.
create or replace function rb_sal_loose_amount(p_item int, p_qty_base numeric, p_rate bigint)
returns bigint language sql stable security definer set search_path = public as $$
  select round(coalesce(p_qty_base, 0) * coalesce(p_rate, 0)
               / case when u.dimension in ('mass', 'volume') then 1000 else 1 end)::bigint
  from items i join units u on u.code = i.base_unit where i.id = p_item
$$;

-- Money given to or set against a customer that is not yet used:
-- receipts and credit notes not set against invoices, less refunds paid.
create or replace function rb_sal_free_credit(p_customer int)
returns bigint language sql stable security definer set search_path = public as $$
  select coalesce((select sum(r.amount_paise) from customer_receipts r where r.customer_id = p_customer and r.status = 'posted'), 0)
       + coalesce((select sum(t.total_paise) from sales_returns t where t.customer_id = p_customer and t.status = 'posted'), 0)
       - coalesce((select sum(a.amount_paise) from ar_allocations a
                   left join customer_receipts r on r.id = a.receipt_id left join sales_returns t on t.id = a.return_id
                   where coalesce(r.customer_id, t.customer_id) = p_customer
                     and coalesce(r.status, t.status) = 'posted'), 0)
       - coalesce((select sum(f.amount_paise) from customer_refunds f where f.customer_id = p_customer and f.status = 'posted'), 0)
$$;

-- What is left of one receipt or credit note to set against invoices.
create or replace function rb_sal_source_left(p_kind text, p_id bigint)
returns bigint language sql stable security definer set search_path = public as $$
  select case when p_kind = 'receipt' then
           coalesce((select amount_paise from customer_receipts where id = p_id and status = 'posted'), 0)
           - coalesce((select sum(amount_paise) from ar_allocations where receipt_id = p_id), 0)
         else
           coalesce((select total_paise from sales_returns where id = p_id and status = 'posted'), 0)
           - coalesce((select sum(amount_paise) from ar_allocations where return_id = p_id), 0) end
$$;

-- The customer balance from the books (positive = the customer owes us).
create or replace function rb_sal_book_balance(p_customer int, p_as_of date)
returns bigint language sql stable security definer set search_path = public as $$
  select coalesce(sum(l.debit_paise - l.credit_paise), 0)::bigint
  from journal_lines l join journals j on j.id = l.journal_id join accounts a on a.code = l.account_code
  where a.control_type = 'customer' and l.customer_id = p_customer and j.status <> 'draft'
    and (p_as_of is null or l.journal_date <= p_as_of)
$$;

-- The part of a customer's balance that is not on any invoice in the app
-- (an opening balance at go-live, or one entered by journal), still unpaid.
create or replace function rb_sal_other_balance(p_customer int)
returns bigint language sql stable security definer set search_path = public as $$
  select rb_sal_book_balance(p_customer, null)
       - coalesce((select sum(outstanding_paise) from sales where customer_id = p_customer and status = 'open'), 0)
       + rb_sal_free_credit(p_customer)
$$;

-- How much may be paid back to a customer: money on account, and never
-- more than the books say we owe them.
create or replace function rb_sal_refundable(p_customer int)
returns bigint language sql stable security definer set search_path = public as $$
  select greatest(least(rb_sal_free_credit(p_customer), -rb_sal_book_balance(p_customer, null)), 0)
$$;

-- Recompute what is still owed on an invoice and its status.
create or replace function rb_sal_refresh(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_s sales;
begin
  select * into v_s from sales where id = p_id for update;
  if v_s.id is null then return; end if;
  update sales set
    credited_paise = coalesce((select sum(a.amount_paise) from ar_allocations a
                               left join customer_receipts r on r.id = a.receipt_id left join sales_returns t on t.id = a.return_id
                               where a.sale_id = p_id and coalesce(r.status, t.status) = 'posted'), 0)
  where id = p_id;
  update sales set
    written_off_paise = coalesce((select sum(w.amount_paise) from customer_write_offs w where w.sale_id = p_id and w.status = 'posted'), 0)
  where id = p_id;
  update sales set
    outstanding_paise = case when status = 'cancelled' then 0 else total_paise - paid_at_sale_paise - credited_paise - written_off_paise end
  where id = p_id;
  update sales set status = case when status = 'cancelled' then 'cancelled' when outstanding_paise <= 0 then 'paid' else 'open' end
  where id = p_id;
end $$;

-- Check a receipt, credit note or refund has not been used for more than it is worth.
create or replace function rb_sal_assert_credit(p_customer int)
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if rb_sal_free_credit(p_customer) < 0 then
    raise exception 'This money has already been refunded or set against invoices. Reverse the refund (or take it off the invoices) first.';
  end if;
  if exists (select 1 from sales where customer_id = p_customer and status <> 'cancelled' and outstanding_paise < 0) then
    raise exception 'An invoice would be paid more than its total. Take the extra off it first.';
  end if;
end $$;

-- Set receipts or credit notes against invoices. p_alloc: [{sale_id, amount_paise}]
create or replace function rb_sal_allocate(p_kind text, p_id bigint, p_alloc jsonb, p_actor uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare a jsonb; v_s sales; v_left bigint := rb_sal_source_left(p_kind, p_id); v_cust int; v_demo boolean; v_amt bigint;
        v_done bigint := 0;
begin
  if p_kind = 'receipt' then select customer_id, is_demo into v_cust, v_demo from customer_receipts where id = p_id and status = 'posted';
  elsif p_kind = 'return' then select customer_id, is_demo into v_cust, v_demo from sales_returns where id = p_id and status = 'posted';
  else raise exception 'Unknown source.'; end if;
  if v_cust is null then raise exception 'That receipt or credit note was not found, or it is not posted.'; end if;
  for a in select * from jsonb_array_elements(coalesce(p_alloc, '[]')) loop
    v_amt := coalesce(rb_int(a, 'amount_paise'), 0);
    if v_amt = 0 then continue; end if;
    if v_amt < 0 then raise exception 'Amounts cannot be negative.'; end if;
    if rb_int(a, 'sale_id') is null then
      -- An earlier balance with no invoice in the app (opening balance or journal).
      if v_amt > rb_sal_other_balance(v_cust) then
        raise exception 'The earlier balance (not on an invoice) is only %.', rb_pur_fmt(greatest(rb_sal_other_balance(v_cust), 0));
      end if;
      if v_amt > v_left then raise exception 'Only % of this is left to set against invoices.', rb_pur_fmt(v_left); end if;
      insert into ar_allocations (sale_id, receipt_id, return_id, amount_paise, created_by, is_demo, is_training)
      values (null, case when p_kind = 'receipt' then p_id end, case when p_kind = 'return' then p_id end, v_amt, p_actor,
              v_demo, rb_is_training());
      v_left := v_left - v_amt; v_done := v_done + v_amt;
      continue;
    end if;
    select * into v_s from sales where id = rb_int(a, 'sale_id') for update;
    if v_s.id is null or v_s.customer_id <> v_cust then raise exception 'That invoice is not for this customer.'; end if;
    if v_s.status = 'cancelled' then raise exception '% is cancelled.', v_s.invoice_no; end if;
    if v_amt > v_s.outstanding_paise then
      raise exception '% only has % left to pay.', v_s.invoice_no, rb_pur_fmt(v_s.outstanding_paise);
    end if;
    if v_amt > v_left then raise exception 'Only % of this is left to set against invoices.', rb_pur_fmt(v_left); end if;
    if v_amt > rb_sal_free_credit(v_cust) then
      raise exception 'Part of this money has been refunded, so only % can be set against invoices.', rb_pur_fmt(rb_sal_free_credit(v_cust));
    end if;
    insert into ar_allocations (sale_id, receipt_id, return_id, amount_paise, created_by, is_demo, is_training)
    values (v_s.id, case when p_kind = 'receipt' then p_id end, case when p_kind = 'return' then p_id end, v_amt, p_actor,
            v_demo, rb_is_training());
    v_left := v_left - v_amt; v_done := v_done + v_amt;
    perform rb_sal_refresh(v_s.id);
  end loop;
  return v_done;
end $$;

-- ---------------------------------------------------------------------
-- 5. Sales (private versions take the actor, so the DEMO data can use
--    them; the screens call the rb_ ones in section 8)
-- ---------------------------------------------------------------------

-- Save and post a sale.
-- p: customer_id, invoice_date, doc_type ('invoice' | 'tax_invoice'), channel, department_id,
--    show_hsn, payment_mode, paid_paise (blank = all of it unless credit), payment_ref, note,
--    override_credit_limit,
--    lines [{item_id, pack_id, packs} or {item_id, qty, unit}, rate_paise, discount_pct or discount_paise]
create or replace function rb_sal_save(p jsonb, p_actor uuid, p_demo boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_date date := (p->>'invoice_date')::date; v_c customers; v_set app_settings;
        v_type text := coalesce(rb_txt(p, 'doc_type'), 'invoice'); v_channel text; v_dept int;
        v_mode text := coalesce(rb_txt(p, 'payment_mode'), 'cash'); v_paid bigint; v_incl boolean;
        v_inter boolean := false; v_pos text; l jsonb; i int := 0; v_it items; v_pp product_packs; v_pack_name text;
        v_packs numeric; v_q numeric; v_rate bigint; v_list bigint; v_gross bigint; v_disc bigint; v_net bigint;
        v_gr numeric; v_tax bigint; v_gst bigint; v_cg bigint; v_sg bigint; v_ig bigint; v_rg bigint; v_rd bigint;
        v_desc text; v_no text; v_tot record; v_lines jsonb := '[]'; v_j bigint; v_cost bigint; v_cost_total bigint := 0;
        v_mark bigint; v_rev_key text; r record; v_owed bigint; v_bal bigint; v_line_id bigint;
        v_dl bigint := coalesce(rb_int(p, 'delivery_paise'), 0); v_dtax bigint := 0; v_dgst bigint := 0; v_drate numeric;
begin
  if v_date is null then raise exception 'Please choose the invoice date.'; end if;
  if v_dl < 0 then raise exception 'A delivery charge cannot be negative.'; end if;
  perform rb_assert_period_open(v_date);
  select * into v_set from app_settings where id = 1;
  select * into v_c from customers where id = rb_int(p, 'customer_id');
  if v_c.id is null then raise exception 'Please choose the customer (or Walk-in customer).'; end if;
  if not v_c.is_active then raise exception '% is switched off. Switch them on in Customers first.', v_c.name; end if;
  if v_type not in ('invoice', 'tax_invoice') then raise exception 'Choose Invoice or Tax Invoice.'; end if;
  v_channel := coalesce(rb_txt(p, 'channel'), case when v_c.kind = 'trader' then 'trader' else 'retail' end);
  if v_channel not in ('retail', 'trader', 'online') then raise exception 'Choose retail, trader or online.'; end if;
  if v_channel = 'trader' and v_c.kind <> 'trader' then raise exception 'Trader prices are only for trader customers.'; end if;
  v_dept := coalesce(rb_int(p, 'department_id')::int, rb_sal_dept(v_channel));
  if v_mode not in ('cash', 'upi', 'bank', 'credit') then raise exception 'Choose how it was paid: cash, UPI, bank or credit.'; end if;
  if jsonb_array_length(coalesce(p->'lines', '[]')) = 0 then raise exception 'Add at least one item.'; end if;

  -- GST
  if v_type = 'tax_invoice' then
    if not rb_pur_gst_claimable(v_date) then
      raise exception 'A Tax Invoice needs the firm''s GSTIN and "GST registered from" date in Settings, and the invoice must be dated on or after that date. Until then choose Invoice (no GST).';
    end if;
    if v_set.state_code is null or v_set.address is null then
      raise exception 'A Tax Invoice needs the firm''s registered address and state code in Settings.';
    end if;
    v_pos := coalesce(nullif(trim(v_c.state_code), ''), left(nullif(trim(v_c.gstin), ''), 2), v_set.state_code);
    v_inter := v_pos is distinct from v_set.state_code;
    v_incl := v_set.sale_prices_include_gst;
  else
    v_incl := false;
  end if;

  v_no := rb_next_doc_no(rb_pur_series('Inv', p_demo), v_date);
  insert into sales (invoice_no, doc_type, invoice_date, customer_id, channel, department_id, bill_name, bill_phone, bill_address,
                     bill_gstin, bill_state_code, place_of_supply, inter_state, show_hsn, prices_include_gst, payment_mode,
                     payment_ref, note, credit_limit_override, entered_by, is_demo, is_training)
  values (v_no, v_type, v_date, v_c.id, v_channel, v_dept, coalesce(rb_txt(p, 'bill_name'), v_c.name), v_c.phone, v_c.address,
          v_c.gstin, v_c.state_code, v_pos, v_inter, coalesce((p->>'show_hsn')::boolean, true), v_incl, v_mode,
          rb_txt(p, 'payment_ref'), rb_txt(p, 'note'), coalesce((p->>'override_credit_limit')::boolean, false), p_actor, p_demo,
          rb_is_training())
  returning id into v_id;

  for l in select * from jsonb_array_elements(p->'lines') loop
    if rb_int(l, 'item_id') is null then continue; end if;
    select * into v_it from items where id = rb_int(l, 'item_id');
    if v_it.id is null then raise exception 'Item not found.'; end if;
    if not (v_it.kind = 'finished' or (v_it.kind = 'byproduct' and v_it.byproduct_use = 'sellable')) then
      raise exception '% cannot be sold: only finished goods and sellable by-products are sold.', v_it.name;
    end if;
    if not v_it.is_active then raise exception '% is switched off in Masters.', v_it.name; end if;
    v_pp := null; v_pack_name := null; v_packs := null;
    if rb_int(l, 'pack_id') is not null then
      select * into v_pp from product_packs where id = rb_int(l, 'pack_id');
      if v_pp.id is null or v_pp.item_id <> v_it.id then raise exception 'That pack is not set up for %.', v_it.name; end if;
      if not v_pp.is_active then raise exception 'That pack of % is switched off in Masters.', v_it.name; end if;
      select name into v_pack_name from pack_types where id = v_pp.pack_type_id;
      v_packs := nullif(trim(l->>'packs'), '')::numeric;
      if v_packs is null or v_packs = 0 then continue; end if;
      if v_packs < 0 or v_packs <> trunc(v_packs) then raise exception 'Packs are whole numbers.'; end if;
      v_q := v_packs * v_pp.net_qty;
      v_desc := v_it.name || ', ' || v_pack_name;
    else
      if v_it.sells_by = 'pack' then raise exception '% is sold only in packs. Choose the bottle or pouch.', v_it.name; end if;
      v_q := rb_stk_qty(v_it.id, l);
      if coalesce(v_q, 0) = 0 then continue; end if;
      v_desc := v_it.name || ' (loose)';
    end if;
    v_list := rb_sal_list_price(v_it.id, v_pp.id, v_channel);
    v_rate := coalesce(rb_int(l, 'rate_paise'), v_list);
    if v_rate is null then
      raise exception 'No % price is set for %. Add it in Masters → Packs and prices first.', v_channel, v_desc;
    end if;
    if v_rate < 0 then raise exception 'Prices cannot be negative.'; end if;
    -- An online order (module 10) keeps the price the customer was shown.
    if v_rate is distinct from v_list and not rb_user_has(p_actor, 'sales.edit')
       and coalesce(current_setting('rb.shop_order', true), '') = '' then
      raise exception 'You can sell % only at the Masters price (%). Ask a Manager to change the price.', v_desc, rb_pur_fmt(v_list);
    end if;
    v_gross := case when v_pp.id is not null then round(v_packs * v_rate)::bigint else rb_sal_loose_amount(v_it.id, v_q, v_rate) end;
    if rb_txt(l, 'discount_pct') is not null then
      if (l->>'discount_pct')::numeric < 0 or (l->>'discount_pct')::numeric > 100 then raise exception 'A discount % is between 0 and 100.', '%'; end if;
      v_disc := round(v_gross * (l->>'discount_pct')::numeric / 100)::bigint;
    else
      v_disc := coalesce(rb_int(l, 'discount_paise'), 0);
    end if;
    if v_disc < 0 then raise exception 'A discount cannot be negative.'; end if;
    if v_disc > v_gross then raise exception 'The discount on % is more than its price.', v_desc; end if;
    v_net := v_gross - v_disc;
    -- GST on the price after discount
    if v_type = 'tax_invoice' then
      if v_it.hsn_code is null or v_it.gst_rate is null then
        raise exception '% needs its HSN code and GST rate in Masters before it can go on a Tax Invoice.', v_it.name;
      end if;
      v_gr := v_it.gst_rate;
      if v_incl then
        v_tax := round(v_net * 100 / (100 + v_gr))::bigint;
        v_gst := v_net - v_tax;
        v_rg := round(v_gross * 100 / (100 + v_gr))::bigint;
      else
        v_tax := v_net;
        v_gst := round(v_tax * v_gr / 100)::bigint;
        v_rg := v_gross;
      end if;
    else
      v_gr := 0; v_tax := v_net; v_gst := 0; v_rg := v_gross;
    end if;
    v_rd := v_rg - v_tax;
    if v_inter then v_ig := v_gst; v_cg := 0; v_sg := 0;
    else v_cg := round(v_gst / 2.0)::bigint; v_sg := v_gst - v_cg; v_ig := 0; end if;
    i := i + 1;
    insert into sale_lines (sale_id, line_no, item_id, pack_id, packs, qty_base, description, rate_paise, list_rate_paise, gross_paise,
                            discount_pct, discount_paise, hsn_code, gst_rate, taxable_paise, cgst_paise, sgst_paise, igst_paise,
                            total_paise, rev_gross_paise, rev_discount_paise, is_demo, is_training)
    values (v_id, i, v_it.id, v_pp.id, v_packs, v_q, v_desc, v_rate, v_list, v_gross, nullif(l->>'discount_pct', '')::numeric, v_disc,
            v_it.hsn_code, v_gr, v_tax, v_cg, v_sg, v_ig, v_tax + v_gst, v_rg, v_rd, p_demo, rb_is_training())
    returning id into v_line_id;
    -- Out of finished-goods stock at weighted average cost; never below zero.
    v_mark := coalesce((select max(id) from stock_moves), 0);
    v_cost := rb_stk_issue(v_date, v_it.id, v_pp.id, null, v_q, 'sale', v_no, null, null, null, v_dept, p_actor, p_demo, null);
    update stock_moves set sale_id = v_id where id > v_mark and doc_no = v_no and kind = 'sale';
    update sale_lines set cost_paise = v_cost where id = v_line_id;
    v_cost_total := v_cost_total + v_cost;
    if v_cost > 0 then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'sale_cost.finished', 'amount_paise', v_cost,
        'item_id', v_it.id, 'narration', coalesce(trim_scale(v_packs) || ' × ', trim_scale(v_q) || ' ' || v_it.base_unit || ' ') || v_desc));
    end if;
  end loop;
  if i = 0 then raise exception 'Add at least one item with a quantity.'; end if;

  select coalesce(sum(gross_paise), 0) g, coalesce(sum(discount_paise), 0) d, coalesce(sum(taxable_paise), 0) t,
         coalesce(sum(cgst_paise), 0) cg, coalesce(sum(sgst_paise), 0) sg, coalesce(sum(igst_paise), 0) ig,
         coalesce(sum(total_paise), 0) tot into v_tot from sale_lines where sale_id = v_id;

  -- Delivery charge (1.2): on a Tax Invoice it takes the highest GST rate of
  -- the goods (a composite supply, the goods being the principal supply).
  if v_dl > 0 then
    if v_type = 'tax_invoice' then
      select max(gst_rate) into v_drate from sale_lines where sale_id = v_id;
      if v_incl then v_dtax := round(v_dl * 100 / (100 + v_drate))::bigint; v_dgst := v_dl - v_dtax;
      else v_dtax := v_dl; v_dgst := round(v_dl * v_drate / 100)::bigint; end if;
    else
      v_dtax := v_dl;
    end if;
    v_tot.t := v_tot.t + v_dtax;
    if v_inter then v_tot.ig := v_tot.ig + v_dgst;
    else v_tot.cg := v_tot.cg + round(v_dgst / 2.0)::bigint; v_tot.sg := v_tot.sg + v_dgst - round(v_dgst / 2.0)::bigint; end if;
    v_tot.tot := v_tot.tot + v_dtax + v_dgst;
  end if;

  -- Payment at the counter, and credit.
  v_paid := case when v_mode = 'credit' then 0 else coalesce(rb_int(p, 'paid_paise'), v_tot.tot) end;
  if v_paid < 0 then raise exception 'The amount paid cannot be negative.'; end if;
  if v_paid > v_tot.tot then raise exception 'The amount paid (%) is more than the invoice total (%).', rb_pur_fmt(v_paid), rb_pur_fmt(v_tot.tot); end if;
  v_owed := v_tot.tot - v_paid;
  if v_owed > 0 and v_c.is_walk_in then
    raise exception 'A walk-in sale must be paid in full. To sell on credit, choose or add the customer.';
  end if;
  if v_owed > 0 and v_c.credit_limit_paise is not null and coalesce(current_setting('rb.shop_order', true), '') = '' then
    v_bal := rb_sal_book_balance(v_c.id, null);
    if v_bal + v_owed > v_c.credit_limit_paise then
      if not coalesce((p->>'override_credit_limit')::boolean, false) then
        raise exception 'This takes % over their credit limit of %: they already owe %. Take a payment, or ask a Manager to allow it.',
          v_c.name, rb_pur_fmt(v_c.credit_limit_paise), rb_pur_fmt(v_bal);
      end if;
      if not rb_user_has(p_actor, 'sales.approve') then
        raise exception 'Only someone with Sales → Approve can go over a customer''s credit limit.';
      end if;
    end if;
  end if;

  -- The journal: revenue at full price, discount, output GST, customer balance, payment, cost of sales.
  v_rev_key := 'sale.revenue_' || v_channel;
  for r in select case when i2.kind = 'byproduct' then 'sale.revenue_byproduct' else v_rev_key end k,
                  sum(sl.rev_gross_paise) g, sum(sl.rev_discount_paise) d
           from sale_lines sl join items i2 on i2.id = sl.item_id where sl.sale_id = v_id group by 1 loop
    if r.g > 0 then
      v_lines := jsonb_build_array(jsonb_build_object('rule', r.k, 'amount_paise', r.g)) || v_lines;
    end if;
    if r.d > 0 then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'sale.discount', 'amount_paise', r.d));
    end if;
  end loop;
  if v_dtax > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'sale.delivery', 'amount_paise', v_dtax, 'narration', 'Delivery charge'));
  end if;
  if v_tot.cg + v_tot.sg + v_tot.ig > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'sale.output_gst', 'amount_paise', v_tot.cg + v_tot.sg + v_tot.ig,
      'narration', case when v_inter then 'IGST' else 'CGST + SGST' end));
  end if;
  if v_tot.tot > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'sale.receivable', 'amount_paise', v_tot.tot, 'customer_id', v_c.id,
      'narration', v_no));
  end if;
  if v_paid > 0 then
    v_lines := v_lines || jsonb_build_array(
      jsonb_build_object('rule', 'sale.' || case when v_mode = 'cash' then 'cash' else 'bank' end, 'amount_paise', v_paid,
        'narration', 'Paid at the sale by ' || upper(v_mode)),
      jsonb_build_object('rule', 'sale.receivable', 'amount_paise', -v_paid, 'customer_id', v_c.id,
        'narration', 'Paid at the sale by ' || upper(v_mode) || coalesce(', ref ' || rb_txt(p, 'payment_ref'), '')));
  end if;
  if v_cost_total > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'sale_cost.cost_of_sales', 'amount_paise', v_cost_total));
  end if;
  if jsonb_array_length(v_lines) >= 2 then
    v_j := rb_post_engine(jsonb_build_object('journal_date', v_date, 'source', 'sales', 'event_code', 'sale', 'source_ref', v_no,
      'narration', case when v_type = 'tax_invoice' then 'Tax Invoice ' else 'Invoice ' end || v_no || ' to ' || v_c.name,
      'department_id', v_dept, 'is_demo', p_demo, 'entered_by', p_actor, 'approved_by', p_actor), v_lines);
    update stock_moves set journal_id = v_j where sale_id = v_id;
  end if;
  update sales set gross_paise = v_tot.g, discount_paise = v_tot.d, taxable_paise = v_tot.t, cgst_paise = v_tot.cg,
    sgst_paise = v_tot.sg, igst_paise = v_tot.ig, total_paise = v_tot.tot, cost_paise = v_cost_total,
    paid_at_sale_paise = v_paid, journal_id = v_j, delivery_paise = v_dtax, delivery_gst_paise = v_dgst,
    due_date = case when v_owed > 0 then v_date + coalesce(v_c.credit_days, 0) end
  where id = v_id;
  perform rb_sal_refresh(v_id);
  perform rb_audit_write('SALE', 'sales', v_id::text, null,
    jsonb_build_object('invoice_no', v_no, 'customer', v_c.name, 'total_paise', v_tot.tot, 'paid_paise', v_paid, 'mode', v_mode), null);
  return jsonb_build_object('id', v_id, 'invoice_no', v_no, 'total_paise', v_tot.tot);
end $$;

-- ---------------------------------------------------------------------
-- 6. Returns and credit notes, receipts, refunds
-- ---------------------------------------------------------------------

-- Enter a return. p: sale_id, return_date, reason, condition ('restock' | 'discard'),
-- lines [{sale_line_id, packs} or {sale_line_id, qty, unit}]
create or replace function rb_sal_save_return(p jsonb, p_actor uuid, p_demo boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_s sales; v_date date := (p->>'return_date')::date; l jsonb; v_l sale_lines; v_q numeric; v_left numeric;
        v_cond text := coalesce(rb_txt(p, 'condition'), 'restock'); v_n int := 0; v_k numeric; v_net numeric;
        v_it items;
begin
  select * into v_s from sales where id = rb_int(p, 'sale_id') for update;
  if v_s.id is null then raise exception 'Invoice not found.'; end if;
  if v_s.status = 'cancelled' then raise exception '% is cancelled, so nothing can be returned on it.', v_s.invoice_no; end if;
  if v_date is null then raise exception 'Please choose the date the goods came back.'; end if;
  if v_date < v_s.invoice_date then raise exception 'Goods cannot come back before the invoice date.'; end if;
  perform rb_assert_period_open(v_date);
  if rb_txt(p, 'reason') is null then raise exception 'Please say why the goods came back.'; end if;
  if v_cond not in ('restock', 'discard') then raise exception 'Say whether the goods go back on the shelf or are thrown away.'; end if;
  insert into sales_returns (sale_id, customer_id, return_date, reason, condition, department_id, entered_by, is_demo, is_training)
  values (v_s.id, v_s.customer_id, v_date, rb_txt(p, 'reason'), v_cond, v_s.department_id, p_actor, p_demo, rb_is_training())
  returning id into v_id;
  for l in select * from jsonb_array_elements(coalesce(p->'lines', '[]')) loop
    select * into v_l from sale_lines where id = rb_int(l, 'sale_line_id') and sale_id = v_s.id;
    if v_l.id is null then raise exception 'That line is not on this invoice.'; end if;
    if v_l.pack_id is not null then
      v_k := nullif(trim(l->>'packs'), '')::numeric;
      if v_k is null or v_k = 0 then continue; end if;
      if v_k < 0 or v_k <> trunc(v_k) then raise exception 'Packs are whole numbers.'; end if;
      v_q := v_k * (v_l.qty_base / v_l.packs);
    else
      v_q := rb_stk_qty(v_l.item_id, l); v_k := null;
      if coalesce(v_q, 0) = 0 then continue; end if;
    end if;
    v_left := v_l.qty_base - coalesce((select sum(rl.qty_base) from sales_return_lines rl join sales_returns r on r.id = rl.return_id
                                        where rl.sale_line_id = v_l.id and r.status in ('posted', 'awaiting_approval')), 0);
    if v_q > v_left then
      select * into v_it from items where id = v_l.item_id;
      raise exception 'Only % of % is left to return on this invoice (counting returns already entered).',
        coalesce(trim_scale(round(v_left / nullif(v_l.qty_base / v_l.packs, 0), 3)) || ' pack(s)', rb_stk_fq(v_left, v_it.base_unit)), v_l.description;
    end if;
    -- The return is worth the same share of the line as the quantity (whole line = exact amounts).
    insert into sales_return_lines (return_id, sale_line_id, packs, qty_base, taxable_paise, cgst_paise, sgst_paise, igst_paise,
                                    total_paise, cost_paise, is_demo, is_training)
    select v_id, v_l.id, v_k, v_q, x.tx, x.cg, x.sg, x.ig, x.tx + x.cg + x.sg + x.ig, x.co, p_demo, rb_is_training()
    from (select case when v_q = v_l.qty_base then v_l.taxable_paise else round(v_l.taxable_paise * v_q / v_l.qty_base)::bigint end tx,
                 case when v_q = v_l.qty_base then v_l.cgst_paise else round(v_l.cgst_paise * v_q / v_l.qty_base)::bigint end cg,
                 case when v_q = v_l.qty_base then v_l.sgst_paise else round(v_l.sgst_paise * v_q / v_l.qty_base)::bigint end sg,
                 case when v_q = v_l.qty_base then v_l.igst_paise else round(v_l.igst_paise * v_q / v_l.qty_base)::bigint end ig,
                 case when v_q = v_l.qty_base then v_l.cost_paise else round(v_l.cost_paise * v_q / v_l.qty_base)::bigint end co) x;
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then raise exception 'Enter how much came back.'; end if;
  update sales_returns r set taxable_paise = x.tx, cgst_paise = x.cg, sgst_paise = x.sg, igst_paise = x.ig, total_paise = x.tot,
    cost_paise = x.co
  from (select sum(taxable_paise) tx, sum(cgst_paise) cg, sum(sgst_paise) sg, sum(igst_paise) ig, sum(total_paise) tot,
               sum(cost_paise) co from sales_return_lines where return_id = v_id) x
  where r.id = v_id;
  perform rb_audit_write('SALES_RETURN', 'sales_returns', v_id::text, null,
    jsonb_build_object('invoice_no', v_s.invoice_no, 'reason', rb_txt(p, 'reason'), 'condition', v_cond), null);
  return v_id;
end $$;

-- Post a return: its credit note, the journal, stock back, and the credit set against its invoice.
create or replace function rb_sal_post_return(p_id bigint, p_actor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_r sales_returns; v_s sales; v_no text; v_lines jsonb := '[]'; rl record; v_j bigint; v_mark bigint; v_cname text;
begin
  select * into v_r from sales_returns where id = p_id for update;
  if v_r.id is null then raise exception 'Return not found.'; end if;
  if v_r.status <> 'awaiting_approval' then raise exception 'This return is not waiting for approval.'; end if;
  select * into v_s from sales where id = v_r.sale_id for update;
  if v_s.status = 'cancelled' then raise exception '% has been cancelled, so this return cannot be posted. Refuse it instead.', v_s.invoice_no; end if;
  perform rb_assert_period_open(v_r.return_date);
  select name into v_cname from customers where id = v_r.customer_id;
  v_no := rb_next_doc_no(rb_pur_series('CN', v_r.is_demo), v_r.return_date);
  v_mark := coalesce((select max(id) from stock_moves), 0);
  for rl in select x.*, l.item_id, l.pack_id, l.description, i.base_unit from sales_return_lines x
            join sale_lines l on l.id = x.sale_line_id join items i on i.id = l.item_id where x.return_id = p_id order by x.id loop
    if v_r.condition = 'restock' then
      perform rb_stk_move(v_r.return_date, rl.item_id, rl.pack_id, null, rl.qty_base, rl.cost_paise, 'sales_return', v_no, null,
                          null, null, v_r.department_id, p_actor, v_r.is_demo, v_r.reason);
      if rl.cost_paise > 0 then
        v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'sales_return.stock_finished', 'amount_paise', rl.cost_paise,
          'item_id', rl.item_id, 'narration', coalesce(trim_scale(rl.packs) || ' × ', trim_scale(rl.qty_base) || ' ' || rl.base_unit || ' ')
            || rl.description || ' back on the shelf'));
      end if;
    end if;
  end loop;
  update stock_moves set sales_return_id = p_id where id > v_mark and doc_no = v_no and kind = 'sales_return';
  if v_r.taxable_paise > 0 then
    v_lines := jsonb_build_array(jsonb_build_object('rule', 'sales_return.returns', 'amount_paise', v_r.taxable_paise)) || v_lines;
  end if;
  if v_r.cgst_paise + v_r.sgst_paise + v_r.igst_paise > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'sales_return.output_gst',
      'amount_paise', v_r.cgst_paise + v_r.sgst_paise + v_r.igst_paise));
  end if;
  if v_r.total_paise > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'sales_return.receivable', 'amount_paise', v_r.total_paise,
      'customer_id', v_r.customer_id, 'narration', 'Credit note ' || v_no || ' on ' || v_s.invoice_no));
  end if;
  if v_r.cost_paise > 0 then
    if v_r.condition = 'discard' then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'sales_return.write_off', 'amount_paise', v_r.cost_paise,
        'narration', 'Returned goods thrown away: ' || v_r.reason));
    end if;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'sales_return.cost_of_sales', 'amount_paise', v_r.cost_paise));
  end if;
  if jsonb_array_length(v_lines) >= 2 then
    v_j := rb_post_engine(jsonb_build_object('journal_date', v_r.return_date, 'source', 'sales', 'event_code', 'sales_return',
      'source_ref', v_no, 'narration', 'Credit note ' || v_no || ' to ' || v_cname || ' for goods returned on ' || v_s.invoice_no,
      'department_id', v_r.department_id, 'is_demo', v_r.is_demo, 'entered_by', v_r.entered_by, 'approved_by', p_actor), v_lines);
    update stock_moves set journal_id = v_j where sales_return_id = p_id;
  end if;
  update sales_returns set return_no = v_no, status = 'posted', journal_id = v_j, approved_by = p_actor, posted_at = now() where id = p_id;
  -- The credit settles its own invoice first; anything over is money on account (to refund or use later).
  perform rb_sal_refresh(v_s.id);
  select * into v_s from sales where id = v_s.id;
  if least(v_r.total_paise, v_s.outstanding_paise) > 0 then
    perform rb_sal_allocate('return', p_id, jsonb_build_array(jsonb_build_object('sale_id', v_s.id,
      'amount_paise', least(v_r.total_paise, v_s.outstanding_paise))), p_actor);
  end if;
  perform rb_audit_write('POST_SALES_RETURN', 'sales_returns', p_id::text, null,
    jsonb_build_object('credit_note', v_no, 'invoice_no', v_s.invoice_no, 'total_paise', v_r.total_paise), null);
end $$;

-- A receipt from a customer, with what it settles. p: customer_id, receipt_date, mode,
-- amount_paise, reference, note, allocations [{sale_id, amount_paise}]
create or replace function rb_sal_receive(p jsonb, p_actor uuid, p_demo boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_c customers; v_date date := (p->>'receipt_date')::date; v_mode text := coalesce(rb_txt(p, 'mode'), 'cash');
        v_amt bigint := rb_int(p, 'amount_paise'); v_no text; v_j bigint; v_dept int; v_alloc bigint;
begin
  select * into v_c from customers where id = rb_int(p, 'customer_id');
  if v_c.id is null then raise exception 'Please choose the customer.'; end if;
  if v_date is null then raise exception 'Please choose the date the money came in.'; end if;
  if v_mode not in ('cash', 'upi', 'bank') then raise exception 'Choose how it was paid: cash, UPI or bank.'; end if;
  if coalesce(v_amt, 0) <= 0 then raise exception 'Please enter the amount received.'; end if;
  perform rb_assert_period_open(v_date);
  v_dept := coalesce(rb_int(p, 'department_id')::int, rb_sal_dept(case when v_c.kind = 'trader' then 'trader' else 'retail' end));
  v_no := rb_next_doc_no(rb_pur_series('RCT', p_demo), v_date);
  insert into customer_receipts (receipt_no, customer_id, receipt_date, mode, amount_paise, reference, note, department_id,
                                 entered_by, is_demo, is_training)
  values (v_no, v_c.id, v_date, v_mode, v_amt, rb_txt(p, 'reference'), rb_txt(p, 'note'), v_dept, p_actor, p_demo, rb_is_training())
  returning id into v_id;
  v_j := rb_post_engine(jsonb_build_object('journal_date', v_date, 'source', 'sales', 'event_code', 'customer_receipt',
    'source_ref', v_no, 'narration', 'Received from ' || v_c.name || ' by ' || upper(v_mode) || coalesce(', ref ' || rb_txt(p, 'reference'), ''),
    'department_id', v_dept, 'is_demo', p_demo, 'entered_by', p_actor, 'approved_by', p_actor),
    jsonb_build_array(
      jsonb_build_object('rule', 'customer_receipt.' || case when v_mode = 'cash' then 'cash' else 'bank' end, 'amount_paise', v_amt),
      jsonb_build_object('rule', 'customer_receipt.receivable', 'amount_paise', v_amt, 'customer_id', v_c.id, 'narration', v_no)));
  update customer_receipts set journal_id = v_j where id = v_id;
  v_alloc := rb_sal_allocate('receipt', v_id, p->'allocations', p_actor);
  perform rb_audit_write('CUSTOMER_RECEIPT', 'customer_receipts', v_id::text, null,
    jsonb_build_object('receipt_no', v_no, 'customer', v_c.name, 'amount_paise', v_amt, 'mode', v_mode, 'allocated_paise', v_alloc), null);
  return v_id;
end $$;

-- A refund to a customer, from money they have on account (a credit note or an overpayment).
-- p: customer_id, refund_date, mode, amount_paise, reference, reason, return_id
create or replace function rb_sal_refund(p jsonb, p_actor uuid, p_demo boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_c customers; v_date date := (p->>'refund_date')::date; v_mode text := coalesce(rb_txt(p, 'mode'), 'cash');
        v_amt bigint := rb_int(p, 'amount_paise'); v_no text; v_j bigint; v_dept int; v_free bigint;
begin
  select * into v_c from customers where id = rb_int(p, 'customer_id') for update;
  if v_c.id is null then raise exception 'Please choose the customer.'; end if;
  if v_date is null then raise exception 'Please choose the date of the refund.'; end if;
  if v_mode not in ('cash', 'upi', 'bank') then raise exception 'Choose how it was paid back: cash, UPI or bank.'; end if;
  if coalesce(v_amt, 0) <= 0 then raise exception 'Please enter the amount paid back.'; end if;
  if rb_txt(p, 'reason') is null then raise exception 'Please give the reason for the refund.'; end if;
  perform rb_assert_period_open(v_date);
  v_free := rb_sal_refundable(v_c.id);
  if v_amt > v_free then
    raise exception '% only has % to come back (credit notes and overpayments not yet used, and not more than the books say we owe them), so no more than that can be refunded.',
      v_c.name, rb_pur_fmt(v_free);
  end if;
  v_dept := coalesce(rb_int(p, 'department_id')::int, rb_sal_dept(case when v_c.kind = 'trader' then 'trader' else 'retail' end));
  v_no := rb_next_doc_no(rb_pur_series('RFD', p_demo), v_date);
  insert into customer_refunds (refund_no, customer_id, return_id, refund_date, mode, amount_paise, reference, reason, department_id,
                                entered_by, is_demo, is_training)
  values (v_no, v_c.id, rb_int(p, 'return_id'), v_date, v_mode, v_amt, rb_txt(p, 'reference'), rb_txt(p, 'reason'), v_dept,
          p_actor, p_demo, rb_is_training())
  returning id into v_id;
  v_j := rb_post_engine(jsonb_build_object('journal_date', v_date, 'source', 'sales', 'event_code', 'customer_refund',
    'source_ref', v_no, 'narration', 'Refund to ' || v_c.name || ' by ' || upper(v_mode) || ': ' || rb_txt(p, 'reason'),
    'department_id', v_dept, 'is_demo', p_demo, 'entered_by', p_actor, 'approved_by', p_actor),
    jsonb_build_array(
      jsonb_build_object('rule', 'customer_refund.receivable', 'amount_paise', v_amt, 'customer_id', v_c.id, 'narration', v_no),
      jsonb_build_object('rule', 'customer_refund.' || case when v_mode = 'cash' then 'cash' else 'bank' end, 'amount_paise', v_amt)));
  update customer_refunds set journal_id = v_j where id = v_id;
  perform rb_audit_write('CUSTOMER_REFUND', 'customer_refunds', v_id::text, null,
    jsonb_build_object('refund_no', v_no, 'customer', v_c.name, 'amount_paise', v_amt, 'mode', v_mode), rb_txt(p, 'reason'));
  return v_id;
end $$;

-- A customer's statement (shared by the screens and the public link).
create or replace function rb_sal_statement(p_customer int, p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_c customers; v_open bigint; v jsonb;
begin
  select * into v_c from customers where id = p_customer;
  if v_c.id is null then raise exception 'Customer not found.'; end if;
  v_open := rb_sal_book_balance(p_customer, p_from - 1);
  select jsonb_build_object(
    'firm', (select jsonb_build_object('firm_name', firm_name, 'address', address, 'phone', phone, 'email', email,
               'gstin', gstin, 'fssai_no', fssai_no, 'firm_reg_no', firm_reg_no, 'llpin', llpin, 'legal_form', legal_form,
               'wordmark_url', wordmark_url) from app_settings where id = 1),
    'customer', jsonb_build_object('id', v_c.id, 'code', v_c.code, 'name', v_c.name, 'kind', v_c.kind, 'address', v_c.address,
               'phone', v_c.phone, 'gstin', v_c.gstin, 'credit_days', v_c.credit_days, 'is_demo', v_c.is_demo),
    'from', p_from, 'to', p_to, 'opening_paise', v_open,
    'lines', coalesce((select jsonb_agg(x order by x.line_date, x.jid, x.lid) from (
        select l.journal_date line_date, j.source_ref ref, coalesce(j.event_code, j.source) event,
               coalesce(case when j.source = 'sales' then j.narration end, l.narration, j.narration) narration,
               l.debit_paise debit_paise, l.credit_paise credit_paise, j.id jid, l.id lid,
               v_open + sum(l.debit_paise - l.credit_paise) over (order by l.journal_date, j.id, l.id) balance_paise
        from journal_lines l join journals j on j.id = l.journal_id join accounts a on a.code = l.account_code
        where a.control_type = 'customer' and l.customer_id = p_customer and j.status <> 'draft'
          and l.journal_date between p_from and p_to) x), '[]'::jsonb),
    'closing_paise', rb_sal_book_balance(p_customer, p_to),
    'open_invoices', coalesce((select jsonb_agg(jsonb_build_object('invoice_no', s.invoice_no, 'invoice_date', s.invoice_date,
               'due_date', s.due_date, 'total_paise', s.total_paise, 'outstanding_paise', s.outstanding_paise,
               'days_overdue', greatest(p_to - coalesce(s.due_date, s.invoice_date), 0)) order by s.invoice_date, s.id)
             from sales s where s.customer_id = p_customer and s.status = 'open' and s.invoice_date <= p_to), '[]'::jsonb),
    'on_account_paise', greatest(rb_sal_free_credit(p_customer), 0))
  into v;
  return v;
end $$;

-- ---------------------------------------------------------------------
-- 6b. Bad debts: written off, and recovered later
-- ---------------------------------------------------------------------

-- How much of a write-off has not yet been recovered.
create or replace function rb_sal_wo_left(p_id bigint)
returns bigint language sql stable security definer set search_path = public as $$
  select coalesce((select amount_paise from customer_write_offs where id = p_id and status = 'posted'), 0)
       - coalesce((select sum(amount_paise) from bad_debt_recoveries where write_off_id = p_id and status = 'posted'), 0)
$$;

-- Write off a bad debt: one invoice (sale_id) or an earlier balance with no invoice in the app.
-- p: customer_id, sale_id, write_off_date, amount_paise, reason
create or replace function rb_sal_write_off(p jsonb, p_actor uuid, p_demo boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_c customers; v_s sales; v_date date := (p->>'write_off_date')::date; v_amt bigint := rb_int(p, 'amount_paise');
        v_no text; v_j bigint; v_dept int; v_max bigint;
begin
  select * into v_c from customers where id = rb_int(p, 'customer_id') for update;
  if v_c.id is null then raise exception 'Please choose the customer.'; end if;
  if v_date is null then raise exception 'Please choose the date of the write-off.'; end if;
  if rb_txt(p, 'reason') is null then raise exception 'Please give the reason the money cannot be collected.'; end if;
  if coalesce(v_amt, 0) <= 0 then raise exception 'Please enter the amount to write off.'; end if;
  perform rb_assert_period_open(v_date);
  if rb_int(p, 'sale_id') is not null then
    select * into v_s from sales where id = rb_int(p, 'sale_id') for update;
    if v_s.id is null or v_s.customer_id <> v_c.id then raise exception 'That invoice is not for this customer.'; end if;
    if v_s.status <> 'open' then raise exception '% has nothing left to pay, so nothing can be written off.', v_s.invoice_no; end if;
    if v_date < v_s.invoice_date then raise exception 'A write-off cannot be dated before the invoice.'; end if;
    v_max := v_s.outstanding_paise;
    if v_amt > v_max then raise exception '% only has % left to pay.', v_s.invoice_no, rb_pur_fmt(v_max); end if;
    v_dept := v_s.department_id;
  else
    v_max := greatest(rb_sal_other_balance(v_c.id), 0);
    if v_amt > v_max then
      raise exception 'The earlier balance (not on an invoice) of % is only %. To write off an invoice, open it.', v_c.name, rb_pur_fmt(v_max);
    end if;
    v_dept := rb_sal_dept(case when v_c.kind = 'trader' then 'trader' else 'retail' end);
  end if;
  v_no := rb_next_doc_no(rb_pur_series('BD', p_demo), v_date);
  insert into customer_write_offs (write_off_no, customer_id, sale_id, write_off_date, amount_paise, reason, department_id,
                                   entered_by, is_demo, is_training)
  values (v_no, v_c.id, v_s.id, v_date, v_amt, rb_txt(p, 'reason'), v_dept, p_actor, p_demo, rb_is_training())
  returning id into v_id;
  v_j := rb_post_engine(jsonb_build_object('journal_date', v_date, 'source', 'sales', 'event_code', 'bad_debt',
    'source_ref', v_no, 'narration', 'Bad debt written off: ' || v_c.name || coalesce(', ' || v_s.invoice_no, ', earlier balance') || ': ' || rb_txt(p, 'reason'),
    'department_id', v_dept, 'is_demo', p_demo, 'entered_by', p_actor, 'approved_by', p_actor),
    jsonb_build_array(
      jsonb_build_object('rule', 'bad_debt.expense', 'amount_paise', v_amt),
      jsonb_build_object('rule', 'bad_debt.receivable', 'amount_paise', v_amt, 'customer_id', v_c.id, 'narration', v_no)));
  update customer_write_offs set journal_id = v_j where id = v_id;
  if v_s.id is not null then perform rb_sal_refresh(v_s.id); end if;
  perform rb_audit_write('BAD_DEBT_WRITE_OFF', 'customer_write_offs', v_id::text, null,
    jsonb_build_object('write_off_no', v_no, 'customer', v_c.name, 'invoice_no', v_s.invoice_no, 'amount_paise', v_amt), rb_txt(p, 'reason'));
  return v_id;
end $$;

-- Money later received for a bad debt. The money is first entered as a
-- customer receipt (it then sits on account); this books it as income.
-- p: write_off_id, recovery_date, amount_paise, note
create or replace function rb_sal_recover(p jsonb, p_actor uuid, p_demo boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_w customer_write_offs; v_c customers; v_date date := (p->>'recovery_date')::date;
        v_amt bigint := rb_int(p, 'amount_paise'); v_left bigint; v_no text; v_j bigint; r record; v_take bigint; v_rest bigint;
begin
  select * into v_w from customer_write_offs where id = rb_int(p, 'write_off_id') for update;
  if v_w.id is null or v_w.status <> 'posted' then raise exception 'That write-off was not found, or it has been reversed.'; end if;
  select * into v_c from customers where id = v_w.customer_id for update;
  if v_date is null then raise exception 'Please choose the date the money came in.'; end if;
  if v_date < v_w.write_off_date then raise exception 'A recovery cannot be dated before the write-off.'; end if;
  if coalesce(v_amt, 0) <= 0 then raise exception 'Please enter the amount recovered.'; end if;
  perform rb_assert_period_open(v_date);
  v_left := rb_sal_wo_left(v_w.id);
  if v_amt > v_left then raise exception 'Only % of % is still written off.', rb_pur_fmt(v_left), v_w.write_off_no; end if;
  if v_amt > (select coalesce(sum(rb_sal_source_left('receipt', x.id)), 0) from customer_receipts x
              where x.customer_id = v_c.id and x.status = 'posted') or v_amt > rb_sal_free_credit(v_c.id) then
    raise exception 'First enter the money received from % as a customer receipt (Customer receipts → Receive a payment). It then waits on account to be booked here.', v_c.name;
  end if;
  v_no := rb_next_doc_no(rb_pur_series('BDR', p_demo), v_date);
  insert into bad_debt_recoveries (recovery_no, write_off_id, customer_id, recovery_date, amount_paise, note, entered_by, is_demo, is_training)
  values (v_no, v_w.id, v_c.id, v_date, v_amt, rb_txt(p, 'note'), p_actor, p_demo, rb_is_training())
  returning id into v_id;
  v_j := rb_post_engine(jsonb_build_object('journal_date', v_date, 'source', 'sales', 'event_code', 'bad_debt_recovery',
    'source_ref', v_no, 'narration', 'Bad debt recovered from ' || v_c.name || ' (written off in ' || v_w.write_off_no || ')',
    'department_id', v_w.department_id, 'is_demo', p_demo, 'entered_by', p_actor, 'approved_by', p_actor),
    jsonb_build_array(
      jsonb_build_object('rule', 'bad_debt_recovery.receivable', 'amount_paise', v_amt, 'customer_id', v_c.id, 'narration', v_no),
      jsonb_build_object('rule', 'bad_debt_recovery.income', 'amount_paise', v_amt)));
  update bad_debt_recoveries set journal_id = v_j where id = v_id;
  -- Use the money on account, oldest receipt first.
  v_rest := v_amt;
  for r in select x.id, rb_sal_source_left('receipt', x.id) left_paise from customer_receipts x
           where x.customer_id = v_c.id and x.status = 'posted' and rb_sal_source_left('receipt', x.id) > 0
           order by x.receipt_date, x.id loop
    exit when v_rest <= 0;
    v_take := least(v_rest, r.left_paise);
    insert into ar_allocations (sale_id, receipt_id, recovery_id, amount_paise, created_by, is_demo, is_training)
    values (null, r.id, v_id, v_take, p_actor, p_demo, rb_is_training());
    v_rest := v_rest - v_take;
  end loop;
  perform rb_sal_assert_credit(v_c.id);
  perform rb_audit_write('BAD_DEBT_RECOVERED', 'bad_debt_recoveries', v_id::text, null,
    jsonb_build_object('recovery_no', v_no, 'write_off_no', v_w.write_off_no, 'customer', v_c.name, 'amount_paise', v_amt), rb_txt(p, 'note'));
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- 7. Journal guard: entries from the Sales screens are reversed there
-- ---------------------------------------------------------------------

create or replace function rb_sal_journal_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('rb.sales', true), '') = 'on' then return coalesce(new, old); end if;
  if tg_op = 'UPDATE' and old.source = 'sales' and old.status = 'posted' and new.status = 'reversed' then
    raise exception 'This entry comes from the Sales screens. Cancel or reverse it there (open the invoice, return, receipt or refund), so stock and the customer balance stay right.';
  end if;
  if tg_op = 'DELETE' and old.source = 'sales' and old.status <> 'draft' and not old.is_demo
     and not (old.is_training and rb_is_training()) then
    raise exception 'This entry comes from the Sales screens. Delete or reverse it there.';
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists rb_sal_journal_guard on journals;
create trigger rb_sal_journal_guard before update or delete on journals
  for each row execute function rb_sal_journal_guard();

-- ---------------------------------------------------------------------
-- 8. What the screens call
-- ---------------------------------------------------------------------

create or replace function rb_save_sale(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return rb_sal_save(p, rb_require('sales.add', 'make sales'), false);
end $$;

-- Cancel an invoice made in error: its journal, its stock and any
-- payment taken at the sale are all reversed. The number stays used.
create or replace function rb_cancel_sale(p_id bigint, p_date date, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.reverse_entries', 'cancel invoices'); v_s sales; v_rev bigint; v_items int[];
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason for cancelling.'; end if;
  select * into v_s from sales where id = p_id for update;
  if v_s.id is null then raise exception 'Invoice not found.'; end if;
  if v_s.status = 'cancelled' then raise exception 'This invoice is already cancelled.'; end if;
  if p_date is null or p_date < v_s.invoice_date then raise exception 'The cancel date cannot be before the invoice date.'; end if;
  perform rb_assert_period_open(p_date);
  if exists (select 1 from sales_returns where sale_id = p_id and status in ('posted', 'awaiting_approval')) then
    raise exception 'Goods have been returned on this invoice. Reverse or refuse those returns first.';
  end if;
  if exists (select 1 from ar_allocations a join customer_receipts r on r.id = a.receipt_id where a.sale_id = p_id and r.status = 'posted') then
    raise exception 'Receipts are set against this invoice. Reverse those receipts first.';
  end if;
  if exists (select 1 from customer_write_offs where sale_id = p_id and status = 'posted') then
    raise exception 'Part of this invoice is written off as a bad debt. Reverse the write-off first.';
  end if;
  select array_agg(distinct item_id) into v_items from stock_moves where sale_id = p_id;
  insert into stock_moves (move_date, item_id, pack_id, packs, qty_base, value_paise, kind, doc_no, sale_id, department_id, note,
                           created_by, is_demo, is_training)
  select p_date, item_id, pack_id, -sum(packs), -sum(qty_base), -sum(value_paise), 'reversal', v_s.invoice_no, p_id, v_s.department_id,
         trim(p_reason), v_me, v_s.is_demo, rb_is_training()
  from stock_moves where sale_id = p_id group by item_id, pack_id having sum(qty_base) <> 0 or sum(value_paise) <> 0;
  if v_s.journal_id is not null then
    perform set_config('rb.sales', 'on', true);
    v_rev := rb_reverse_journal(v_s.journal_id, p_date, 'Invoice ' || v_s.invoice_no || ' cancelled: ' || trim(p_reason));
    perform set_config('rb.sales', 'off', true);
    update stock_moves set journal_id = v_rev where sale_id = p_id and kind = 'reversal' and journal_id is null;
  end if;
  update sales set status = 'cancelled', outstanding_paise = 0, reversal_journal_id = v_rev, cancel_reason = trim(p_reason),
    cancelled_at = now(), cancelled_by = v_me where id = p_id;
  update sales_returns set status = 'refused', refused_reason = 'Invoice cancelled' where sale_id = p_id and status = 'awaiting_approval';
  perform rb_sal_assert_credit(v_s.customer_id);
  perform rb_audit_write('CANCEL_INVOICE', 'sales', p_id::text, null, jsonb_build_object('invoice_no', v_s.invoice_no, 'date', p_date), trim(p_reason));
end $$;

-- Learning phase: a Director or the FC may fully delete an invoice entered
-- by someone still in their learning phase. Not written to the audit log (spec section 4).
create or replace function rb_hard_delete_sale(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('sales.delete', 'fully delete invoices'); v_s sales; v_items int[];
begin
  select * into v_s from sales where id = p_id for update;
  if v_s.id is null then raise exception 'Invoice not found.'; end if;
  if not rb_can_hard_delete('sales', v_s.entered_by) then
    raise exception 'Only invoices entered by someone still in their learning phase can be fully deleted. Cancel it instead.';
  end if;
  if v_s.status = 'cancelled' then raise exception 'This invoice has been cancelled. Cancelled invoices are kept.'; end if;
  if exists (select 1 from sales_returns where sale_id = p_id and status <> 'refused') then
    raise exception 'Goods have been returned on this invoice. Delete or reverse those first.';
  end if;
  if exists (select 1 from ar_allocations where sale_id = p_id) then
    raise exception 'Receipts are set against this invoice. Delete or reverse those first.';
  end if;
  if exists (select 1 from customer_write_offs where sale_id = p_id) then
    raise exception 'Part of this invoice was written off as a bad debt. It is kept.';
  end if;
  perform rb_assert_period_open(v_s.invoice_date);
  select array_agg(distinct item_id) into v_items from stock_moves where sale_id = p_id;
  perform set_config('rb.ledger', 'on', true);
  perform set_config('rb.sales', 'on', true);
  delete from stock_moves where sale_id = p_id;
  delete from sales where id = p_id;
  delete from journals where id = v_s.journal_id;
  perform set_config('rb.sales', 'off', true);
  perform set_config('rb.ledger', 'off', true);
end $$;

create or replace function rb_save_sales_return(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('sales.add', 'enter returns'); v_id bigint;
begin
  v_id := rb_sal_save_return(p, v_me, false);
  -- Someone who may approve returns posts it straight away (spec section 4: not their own,
  -- except Directors, the FC and the Accountant).
  if rb_can_approve('sales', v_me) then perform rb_sal_post_return(v_id, v_me); end if;
  return v_id;
end $$;

create or replace function rb_approve_sales_return(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('sales.approve', 'approve returns'); v_r sales_returns;
begin
  select * into v_r from sales_returns where id = p_id;
  if v_r.id is null then raise exception 'Return not found.'; end if;
  if not rb_can_approve('sales', v_r.entered_by) then raise exception 'You entered this return, so someone else must approve it.'; end if;
  perform rb_sal_post_return(p_id, v_me);
end $$;

create or replace function rb_refuse_sales_return(p_id bigint, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('sales.approve', 'refuse returns'); v_r sales_returns;
begin
  select * into v_r from sales_returns where id = p_id for update;
  if v_r.id is null or v_r.status <> 'awaiting_approval' then raise exception 'This return is not waiting for approval.'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason.'; end if;
  update sales_returns set status = 'refused', refused_reason = trim(p_reason) where id = p_id;
  perform rb_audit_write('REFUSE_SALES_RETURN', 'sales_returns', p_id::text, null, jsonb_build_object('sale_id', v_r.sale_id), trim(p_reason));
end $$;

create or replace function rb_reverse_sales_return(p_id bigint, p_date date, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.reverse_entries', 'reverse credit notes'); v_r sales_returns; v_rev bigint; v_items int[];
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason for the reversal.'; end if;
  select * into v_r from sales_returns where id = p_id for update;
  if v_r.id is null or v_r.status <> 'posted' then raise exception 'Only a posted credit note can be reversed.'; end if;
  if p_date is null or p_date < v_r.return_date then raise exception 'The reversal date cannot be before the return date.'; end if;
  perform rb_assert_period_open(p_date);
  select array_agg(distinct item_id) into v_items from stock_moves where sales_return_id = p_id;
  insert into stock_moves (move_date, item_id, pack_id, packs, qty_base, value_paise, kind, doc_no, sales_return_id, department_id,
                           note, created_by, is_demo, is_training)
  select p_date, item_id, pack_id, -sum(packs), -sum(qty_base), -sum(value_paise), 'reversal', v_r.return_no, p_id, v_r.department_id,
         trim(p_reason), v_me, v_r.is_demo, rb_is_training()
  from stock_moves where sales_return_id = p_id group by item_id, pack_id having sum(qty_base) <> 0 or sum(value_paise) <> 0;
  perform rb_stk_assert_not_negative(coalesce(v_items, '{}'));
  if v_r.journal_id is not null then
    perform set_config('rb.sales', 'on', true);
    v_rev := rb_reverse_journal(v_r.journal_id, p_date, 'Credit note ' || v_r.return_no || ' reversed: ' || trim(p_reason));
    perform set_config('rb.sales', 'off', true);
    update stock_moves set journal_id = v_rev where sales_return_id = p_id and kind = 'reversal' and journal_id is null;
  end if;
  update sales_returns set status = 'reversed', reversal_journal_id = v_rev, reverse_reason = trim(p_reason) where id = p_id;
  perform rb_sal_refresh(sale_id) from (select distinct sale_id from ar_allocations where return_id = p_id) x;
  perform rb_sal_assert_credit(v_r.customer_id);
  perform rb_audit_write('REVERSE_SALES_RETURN', 'sales_returns', p_id::text, null, jsonb_build_object('credit_note', v_r.return_no), trim(p_reason));
end $$;

create or replace function rb_receive_from_customer(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
begin
  return rb_sal_receive(p, rb_require('receipts.add', 'record customer receipts'), false);
end $$;

-- Set a receipt or credit note (money on account) against invoices.
-- p_kind: 'receipt' or 'return'; p_allocations: [{sale_id, amount_paise}]
create or replace function rb_allocate_customer_credit(p_kind text, p_id bigint, p_allocations jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('receipts.add', 'set money against invoices'); v bigint;
begin
  v := rb_sal_allocate(p_kind, p_id, p_allocations, v_me);
  perform rb_audit_write('ALLOCATE_CUSTOMER_CREDIT', case when p_kind = 'receipt' then 'customer_receipts' else 'sales_returns' end,
    p_id::text, null, p_allocations, null);
  return v;
end $$;

create or replace function rb_reverse_customer_receipt(p_id bigint, p_date date, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.reverse_entries', 'reverse receipts'); v_r customer_receipts; v_rev bigint;
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason for the reversal.'; end if;
  select * into v_r from customer_receipts where id = p_id for update;
  if v_r.id is null or v_r.status <> 'posted' then raise exception 'Only a posted receipt can be reversed.'; end if;
  if p_date is null or p_date < v_r.receipt_date then raise exception 'The reversal date cannot be before the receipt date.'; end if;
  if exists (select 1 from ar_allocations a join bad_debt_recoveries b on b.id = a.recovery_id where a.receipt_id = p_id and b.status = 'posted') then
    raise exception 'This money is booked as a bad debt recovered. Reverse the recovery first.';
  end if;
  perform set_config('rb.sales', 'on', true);
  v_rev := rb_reverse_journal(v_r.journal_id, p_date, 'Receipt ' || v_r.receipt_no || ' reversed: ' || trim(p_reason));
  perform set_config('rb.sales', 'off', true);
  update customer_receipts set status = 'reversed', reversal_journal_id = v_rev, reverse_reason = trim(p_reason) where id = p_id;
  perform rb_sal_refresh(sale_id) from (select distinct sale_id from ar_allocations where receipt_id = p_id) x;
  perform rb_sal_assert_credit(v_r.customer_id);
  perform rb_audit_write('REVERSE_CUSTOMER_RECEIPT', 'customer_receipts', p_id::text, null, jsonb_build_object('receipt_no', v_r.receipt_no), trim(p_reason));
end $$;

create or replace function rb_hard_delete_customer_receipt(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('receipts.delete', 'fully delete receipts'); v_r customer_receipts; v_sales bigint[];
begin
  select * into v_r from customer_receipts where id = p_id for update;
  if v_r.id is null then raise exception 'Receipt not found.'; end if;
  if not rb_can_hard_delete('receipts', v_r.entered_by) then
    raise exception 'Only receipts entered by someone still in their learning phase can be fully deleted. Reverse it instead.';
  end if;
  if v_r.status <> 'posted' then raise exception 'This receipt has been reversed. Reversed entries are kept.'; end if;
  if exists (select 1 from ar_allocations where receipt_id = p_id and recovery_id is not null) then
    raise exception 'This money is booked as a bad debt recovered. Reverse the recovery first.';
  end if;
  perform rb_assert_period_open(v_r.receipt_date);
  select array_agg(distinct sale_id) into v_sales from ar_allocations where receipt_id = p_id;
  perform set_config('rb.ledger', 'on', true);
  perform set_config('rb.sales', 'on', true);
  delete from customer_receipts where id = p_id;
  delete from journals where id = v_r.journal_id;
  perform set_config('rb.sales', 'off', true);
  perform set_config('rb.ledger', 'off', true);
  perform rb_sal_refresh(x) from unnest(coalesce(v_sales, '{}')) x;
  perform rb_sal_assert_credit(v_r.customer_id);
end $$;

create or replace function rb_refund_customer(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
begin
  return rb_sal_refund(p, rb_require('power.refunds', 'give refunds (accounts team only)'), false);
end $$;

create or replace function rb_reverse_customer_refund(p_id bigint, p_date date, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.reverse_entries', 'reverse refunds'); v_f customer_refunds; v_rev bigint;
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason for the reversal.'; end if;
  select * into v_f from customer_refunds where id = p_id for update;
  if v_f.id is null or v_f.status <> 'posted' then raise exception 'Only a posted refund can be reversed.'; end if;
  if p_date is null or p_date < v_f.refund_date then raise exception 'The reversal date cannot be before the refund date.'; end if;
  perform set_config('rb.sales', 'on', true);
  v_rev := rb_reverse_journal(v_f.journal_id, p_date, 'Refund ' || v_f.refund_no || ' reversed: ' || trim(p_reason));
  perform set_config('rb.sales', 'off', true);
  update customer_refunds set status = 'reversed', reversal_journal_id = v_rev, reverse_reason = trim(p_reason) where id = p_id;
  perform rb_audit_write('REVERSE_CUSTOMER_REFUND', 'customer_refunds', p_id::text, null, jsonb_build_object('refund_no', v_f.refund_no), trim(p_reason));
end $$;

-- Bad debts (FC and Directors, or anyone given "Write off bad debts").
create or replace function rb_write_off_bad_debt(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
begin
  return rb_sal_write_off(p, rb_require('power.write_off_debts', 'write off bad debts'), false);
end $$;

create or replace function rb_reverse_bad_debt(p_id bigint, p_date date, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.write_off_debts', 'reverse bad debt write-offs'); v_w customer_write_offs; v_rev bigint;
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason for the reversal.'; end if;
  select * into v_w from customer_write_offs where id = p_id for update;
  if v_w.id is null or v_w.status <> 'posted' then raise exception 'Only a posted write-off can be reversed.'; end if;
  if p_date is null or p_date < v_w.write_off_date then raise exception 'The reversal date cannot be before the write-off date.'; end if;
  if exists (select 1 from bad_debt_recoveries where write_off_id = p_id and status = 'posted') then
    raise exception 'Money has been recovered on this write-off. Reverse the recovery first.';
  end if;
  perform rb_assert_period_open(p_date);
  perform set_config('rb.sales', 'on', true);
  v_rev := rb_reverse_journal(v_w.journal_id, p_date, 'Bad debt ' || v_w.write_off_no || ' reversed: ' || trim(p_reason));
  perform set_config('rb.sales', 'off', true);
  update customer_write_offs set status = 'reversed', reversal_journal_id = v_rev, reverse_reason = trim(p_reason) where id = p_id;
  if v_w.sale_id is not null then perform rb_sal_refresh(v_w.sale_id); end if;
  perform rb_audit_write('REVERSE_BAD_DEBT', 'customer_write_offs', p_id::text, null, jsonb_build_object('write_off_no', v_w.write_off_no), trim(p_reason));
end $$;

create or replace function rb_record_bad_debt_recovery(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
begin
  return rb_sal_recover(p, rb_require('power.write_off_debts', 'book bad debts recovered'), false);
end $$;

create or replace function rb_reverse_bad_debt_recovery(p_id bigint, p_date date, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.write_off_debts', 'reverse bad debt recoveries'); v_r bad_debt_recoveries; v_rev bigint;
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason for the reversal.'; end if;
  select * into v_r from bad_debt_recoveries where id = p_id for update;
  if v_r.id is null or v_r.status <> 'posted' then raise exception 'Only a posted recovery can be reversed.'; end if;
  if p_date is null or p_date < v_r.recovery_date then raise exception 'The reversal date cannot be before the recovery date.'; end if;
  perform rb_assert_period_open(p_date);
  perform set_config('rb.sales', 'on', true);
  v_rev := rb_reverse_journal(v_r.journal_id, p_date, 'Bad debt recovery ' || v_r.recovery_no || ' reversed: ' || trim(p_reason));
  perform set_config('rb.sales', 'off', true);
  update bad_debt_recoveries set status = 'reversed', reversal_journal_id = v_rev, reverse_reason = trim(p_reason) where id = p_id;
  -- The money goes back on account.
  delete from ar_allocations where recovery_id = p_id;
  perform rb_audit_write('REVERSE_BAD_DEBT_RECOVERY', 'bad_debt_recoveries', p_id::text, null, jsonb_build_object('recovery_no', v_r.recovery_no), trim(p_reason));
end $$;

-- Every bad debt written off, with what has been recovered.
create or replace function rb_bad_debts_list()
returns table (id bigint, write_off_no text, write_off_date date, customer_id int, customer_name text, sale_id bigint, invoice_no text,
               amount_paise bigint, recovered_paise bigint, left_paise bigint, reason text, status text, reverse_reason text,
               entered_by_name text, recoveries jsonb, is_demo boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not rb_sal_money_ok() then raise exception 'You do not have the right to see bad debts.'; end if;
  return query
  select w.id, w.write_off_no, w.write_off_date, w.customer_id, c.name, w.sale_id, s.invoice_no, w.amount_paise,
         coalesce((select sum(r.amount_paise) from bad_debt_recoveries r where r.write_off_id = w.id and r.status = 'posted'), 0)::bigint,
         case when w.status = 'posted' then rb_sal_wo_left(w.id) else 0 end,
         w.reason, w.status, w.reverse_reason,
         (select coalesce(u.short_name, u.full_name) from app_users u where u.id = w.entered_by),
         coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'recovery_no', r.recovery_no, 'recovery_date', r.recovery_date,
                     'amount_paise', r.amount_paise, 'status', r.status, 'note', r.note) order by r.id)
                   from bad_debt_recoveries r where r.write_off_id = w.id), '[]'::jsonb),
         w.is_demo
  from customer_write_offs w join customers c on c.id = w.customer_id left join sales s on s.id = w.sale_id
  order by w.write_off_date desc, w.id desc;
end $$;

-- Statement links, opened without signing in.
create or replace function rb_create_statement_link(p_customer int, p_from date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_current_user_id(); v_token text; v_c customers; v_exp timestamptz;
begin
  if not rb_sal_money_ok() or not (rb_has('receipts.view') or rb_has('invoices.view') or rb_has('accounts.view')) then
    raise exception 'You do not have the right to share customer statements.';
  end if;
  select * into v_c from customers where id = p_customer;
  if v_c.id is null then raise exception 'Customer not found.'; end if;
  if v_c.is_walk_in then raise exception 'The walk-in customer has no statement.'; end if;
  if p_from is null then raise exception 'Choose the date the statement starts from.'; end if;
  v_token := encode(extensions.gen_random_bytes(18), 'hex');
  v_exp := now() + make_interval(days => (select statement_link_days from app_settings where id = 1));
  insert into statement_links (token, customer_id, from_date, expires_at, created_by, is_demo, is_training)
  values (v_token, p_customer, p_from, v_exp, v_me, v_c.is_demo, rb_is_training());
  perform rb_audit_write('SHARE_STATEMENT', 'customers', p_customer::text, null,
    jsonb_build_object('customer', v_c.name, 'from', p_from, 'expires_at', v_exp), null);
  return jsonb_build_object('token', v_token, 'expires_at', v_exp);
end $$;

create or replace function rb_revoke_statement_links(p_customer int)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not rb_sal_money_ok() then raise exception 'You do not have the right to manage customer statements.'; end if;
  update statement_links set revoked_at = now() where customer_id = p_customer and revoked_at is null and expires_at > now();
  get diagnostics n = row_count;
  perform rb_audit_write('REVOKE_STATEMENT_LINKS', 'customers', p_customer::text, null, jsonb_build_object('links', n), null);
  return n;
end $$;

-- Anyone holding a valid link sees that one customer's statement, nothing else.
create or replace function rb_public_statement(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_l statement_links;
begin
  select * into v_l from statement_links where token = p_token;
  if v_l.token is null or v_l.revoked_at is not null or v_l.expires_at < now() then
    raise exception 'This statement link has expired or been switched off. Please ask Ruchi Buds for a new one.';
  end if;
  update statement_links set opened_count = opened_count + 1, last_opened = now() where token = p_token;
  return rb_sal_statement(v_l.customer_id, v_l.from_date, current_date) || jsonb_build_object('expires_at', v_l.expires_at);
end $$;

create or replace function rb_save_sales_settings(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('settings.edit', 'change settings'); v_old jsonb;
begin
  select jsonb_build_object('sale_prices_include_gst', sale_prices_include_gst, 'invoice_footer', invoice_footer,
                            'statement_link_days', statement_link_days) into v_old from app_settings where id = 1;
  update app_settings set
    sale_prices_include_gst = coalesce((p->>'sale_prices_include_gst')::boolean, sale_prices_include_gst),
    invoice_footer = case when p ? 'invoice_footer' then nullif(trim(p->>'invoice_footer'), '') else invoice_footer end,
    statement_link_days = coalesce(rb_int(p, 'statement_link_days')::int, statement_link_days),
    updated_at = now(), updated_by = v_me
  where id = 1;
  perform rb_audit_write('SALES_SETTINGS', 'app_settings', '1', v_old, p, null);
end $$;

-- ---------------------------------------------------------------------
-- 9. Reading: invoices, returns, receipts, balances, ledger, reports.
--    Money totals need the "See money totals" right; costs need the margin tick.
-- ---------------------------------------------------------------------

create or replace function rb_sales_list(p_from date, p_to date)
returns table (id bigint, invoice_no text, doc_type text, invoice_date date, customer_id int, customer_name text, channel text,
               payment_mode text, items text, total_paise bigint, paid_paise bigint, outstanding_paise bigint, cost_paise bigint,
               status text, due_date date, overdue_days int, entered_by_name text, is_demo boolean)
language plpgsql stable security definer set search_path = public as $$
declare v_money boolean := rb_has('power.see_totals'); v_cost boolean := rb_sal_cost_ok();
begin
  if not (rb_has('sales.view') or rb_has('invoices.view') or rb_has('receipts.view') or rb_has('accounts.view')) then
    raise exception 'You do not have the right to see sales.';
  end if;
  return query
  select s.id, s.invoice_no, s.doc_type, s.invoice_date, s.customer_id, s.bill_name, s.channel, s.payment_mode,
         (select string_agg(coalesce(trim_scale(l.packs) || ' × ', '') || l.description, '; ' order by l.line_no) from sale_lines l where l.sale_id = s.id),
         case when v_money then s.total_paise end, case when v_money then s.paid_at_sale_paise + s.credited_paise end,
         case when v_money then s.outstanding_paise end, case when v_cost then s.cost_paise end,
         s.status, s.due_date,
         case when s.status = 'open' and s.due_date < current_date then (current_date - s.due_date)::int end,
         (select coalesce(u.short_name, u.full_name) from app_users u where u.id = s.entered_by), s.is_demo
  from sales s
  where s.invoice_date between coalesce(p_from, '1900-01-01') and coalesce(p_to, '2999-12-31')
  order by s.invoice_date desc, s.id desc;
end $$;

-- One invoice, ready to show or print.
create or replace function rb_sale_detail(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_s sales; v_cost boolean := rb_sal_cost_ok(); v_me uuid := rb_current_user_id();
begin
  if not (rb_has('sales.view') or rb_has('invoices.view') or rb_has('receipts.view') or rb_has('accounts.view')) then
    raise exception 'You do not have the right to see invoices.';
  end if;
  select * into v_s from sales where id = p_id;
  if v_s.id is null then raise exception 'Invoice not found.'; end if;
  return jsonb_build_object(
    'sale', to_jsonb(v_s) - case when v_cost then 'x' else 'cost_paise' end
            || jsonb_build_object('entered_by_name', (select coalesce(short_name, full_name) from app_users where id = v_s.entered_by),
                                  'customer_code', (select code from customers where id = v_s.customer_id),
                                  'customer_kind', (select kind from customers where id = v_s.customer_id),
                                  'is_walk_in', (select is_walk_in from customers where id = v_s.customer_id)),
    'lines', coalesce((select jsonb_agg(to_jsonb(l) - case when v_cost then 'x' else 'cost_paise' end
                         || jsonb_build_object('base_unit', i.base_unit, 'kind', i.kind,
                              'returned_qty_base', coalesce((select sum(rl.qty_base) from sales_return_lines rl join sales_returns r on r.id = rl.return_id
                                                    where rl.sale_line_id = l.id and r.status = 'posted'), 0),
                              'pending_qty_base', coalesce((select sum(rl.qty_base) from sales_return_lines rl join sales_returns r on r.id = rl.return_id
                                                    where rl.sale_line_id = l.id and r.status = 'awaiting_approval'), 0))
                         order by l.line_no)
                       from sale_lines l join items i on i.id = l.item_id where l.sale_id = p_id), '[]'::jsonb),
    'returns', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'return_no', r.return_no, 'return_date', r.return_date,
                           'reason', r.reason, 'condition', r.condition, 'total_paise', r.total_paise, 'status', r.status,
                           'refused_reason', r.refused_reason, 'is_demo', r.is_demo) order by r.id)
                         from sales_returns r where r.sale_id = p_id), '[]'::jsonb),
    'payments', coalesce((select jsonb_agg(jsonb_build_object('kind', case when a.receipt_id is not null then 'receipt' else 'credit_note' end,
                           'ref', coalesce(c.receipt_no, t.return_no), 'date', coalesce(c.receipt_date, t.return_date),
                           'amount_paise', a.amount_paise, 'status', coalesce(c.status, t.status)) order by a.id)
                          from ar_allocations a left join customer_receipts c on c.id = a.receipt_id
                          left join sales_returns t on t.id = a.return_id where a.sale_id = p_id), '[]'::jsonb),
    'write_offs', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'write_off_no', w.write_off_no, 'write_off_date', w.write_off_date,
                           'amount_paise', w.amount_paise, 'reason', w.reason, 'status', w.status, 'reverse_reason', w.reverse_reason,
                           'recovered_paise', coalesce((select sum(r.amount_paise) from bad_debt_recoveries r where r.write_off_id = w.id and r.status = 'posted'), 0),
                           'is_demo', w.is_demo) order by w.id)
                         from customer_write_offs w where w.sale_id = p_id and rb_sal_money_ok()), '[]'::jsonb),
    'firm', (select jsonb_build_object('firm_name', firm_name, 'address', address, 'phone', phone, 'email', email,
               'gstin', gstin, 'state_code', state_code, 'fssai_no', fssai_no, 'firm_reg_no', firm_reg_no, 'llpin', llpin,
               'legal_form', legal_form, 'wordmark_url', wordmark_url, 'invoice_footer', invoice_footer)
             from app_settings where id = 1),
    'can', jsonb_build_object(
      'see_cost', v_cost,
      'cancel', rb_has('power.reverse_entries') and v_s.status <> 'cancelled',
      'delete', v_s.status <> 'cancelled' and rb_can_hard_delete('sales', v_s.entered_by),
      'return', rb_has('sales.add') and v_s.status <> 'cancelled',
      'receive', rb_has('receipts.add') and v_s.status = 'open',
      'write_off', rb_has('power.write_off_debts') and v_s.status = 'open'));
end $$;

create or replace function rb_sales_returns_list()
returns table (id bigint, return_no text, return_date date, sale_id bigint, invoice_no text, customer_id int, customer_name text,
               reason text, condition text, items text, total_paise bigint, status text, entered_by uuid, entered_by_name text,
               refused_reason text, can_approve boolean, is_demo boolean)
language plpgsql stable security definer set search_path = public as $$
declare v_money boolean := rb_has('power.see_totals');
begin
  if not (rb_has('sales.view') or rb_has('invoices.view') or rb_has('receipts.view') or rb_has('accounts.view')) then
    raise exception 'You do not have the right to see returns.';
  end if;
  return query
  select r.id, r.return_no, r.return_date, s.id, s.invoice_no, r.customer_id, s.bill_name, r.reason, r.condition,
         (select string_agg(coalesce(trim_scale(x.packs) || ' × ', '') || l.description, '; ' order by l.line_no)
          from sales_return_lines x join sale_lines l on l.id = x.sale_line_id where x.return_id = r.id),
         case when v_money then r.total_paise end, r.status, r.entered_by,
         (select coalesce(u.short_name, u.full_name) from app_users u where u.id = r.entered_by), r.refused_reason,
         r.status = 'awaiting_approval' and rb_can_approve('sales', r.entered_by), r.is_demo
  from sales_returns r join sales s on s.id = r.sale_id
  order by (r.status = 'awaiting_approval') desc, r.return_date desc, r.id desc;
end $$;

create or replace function rb_customer_receipts_list()
returns table (id bigint, kind text, doc_no text, doc_date date, customer_id int, customer_name text, mode text, amount_paise bigint,
               allocated_paise bigint, on_account_paise bigint, reference text, note text, status text, entered_by uuid, is_demo boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not ((rb_has('receipts.view') or rb_has('accounts.view')) and rb_has('power.see_totals')) then
    raise exception 'You do not have the right to see customer receipts.';
  end if;
  return query
  select r.id, 'receipt'::text, r.receipt_no, r.receipt_date, r.customer_id, c.name, r.mode, r.amount_paise,
         coalesce((select sum(a.amount_paise) from ar_allocations a where a.receipt_id = r.id), 0)::bigint,
         case when r.status = 'posted' then rb_sal_source_left('receipt', r.id) else 0 end,
         r.reference, r.note, r.status, r.entered_by, r.is_demo
  from customer_receipts r join customers c on c.id = r.customer_id
  union all
  select f.id, 'refund', f.refund_no, f.refund_date, f.customer_id, c.name, f.mode, f.amount_paise, null, null, f.reference, f.reason,
         f.status, f.entered_by, f.is_demo
  from customer_refunds f join customers c on c.id = f.customer_id
  order by 4 desc, 1 desc;
end $$;

-- What a customer has open: unpaid invoices, and money on account to set against them.
create or replace function rb_customer_open_items(p_customer int)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not rb_sal_money_ok() then raise exception 'You do not have the right to see customer balances.'; end if;
  return jsonb_build_object(
    'balance_paise', rb_sal_book_balance(p_customer, null),
    'on_account_paise', greatest(rb_sal_free_credit(p_customer), 0),
    'refundable_paise', rb_sal_refundable(p_customer),
    'other_balance_paise', greatest(rb_sal_other_balance(p_customer), 0),
    'invoices', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'invoice_no', s.invoice_no, 'invoice_date', s.invoice_date,
                 'due_date', s.due_date, 'total_paise', s.total_paise, 'outstanding_paise', s.outstanding_paise, 'is_demo', s.is_demo)
                 order by s.invoice_date, s.id) from sales s where s.customer_id = p_customer and s.status = 'open'), '[]'::jsonb),
    'credits', coalesce((select jsonb_agg(x order by x.date, x.id) from (
        select 'receipt' kind, r.id, r.receipt_no ref, r.receipt_date date, rb_sal_source_left('receipt', r.id) left_paise
        from customer_receipts r where r.customer_id = p_customer and r.status = 'posted' and rb_sal_source_left('receipt', r.id) > 0
        union all
        select 'return', t.id, t.return_no, t.return_date, rb_sal_source_left('return', t.id)
        from sales_returns t where t.customer_id = p_customer and t.status = 'posted' and rb_sal_source_left('return', t.id) > 0) x), '[]'::jsonb),
    'write_offs', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'write_off_no', w.write_off_no, 'write_off_date', w.write_off_date,
                 'amount_paise', w.amount_paise, 'left_paise', rb_sal_wo_left(w.id), 'invoice_no', (select invoice_no from sales where id = w.sale_id))
                 order by w.write_off_date, w.id)
                 from customer_write_offs w where w.customer_id = p_customer and w.status = 'posted' and rb_sal_wo_left(w.id) > 0), '[]'::jsonb));
end $$;

-- Customer balances from the books, with ageing of open invoices by due date.
create or replace function rb_customer_balances(p_as_of date default current_date, p_include_demo boolean default true)
returns table (customer_id int, code text, name text, kind text, phone text, balance_paise bigint, on_account_paise bigint,
               not_due_paise bigint, d1_30_paise bigint, d31_60_paise bigint, d61_90_paise bigint, over_90_paise bigint,
               open_invoices int, oldest_due date, credit_limit_paise bigint, credit_days int, over_limit boolean, is_demo boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not rb_sal_money_ok() then raise exception 'You do not have the right to see customer balances.'; end if;
  return query
  with ar as (
    select l.customer_id cid, sum(l.debit_paise - l.credit_paise)::bigint bal
    from journal_lines l join journals j on j.id = l.journal_id join accounts a on a.code = l.account_code
    where a.control_type = 'customer' and j.status <> 'draft' and l.journal_date <= p_as_of and (p_include_demo or not l.is_demo)
    group by l.customer_id),
  inv as (
    select s.customer_id cid, s.outstanding_paise o, p_as_of - coalesce(s.due_date, s.invoice_date) od, coalesce(s.due_date, s.invoice_date) due
    from sales s where s.status = 'open' and s.invoice_date <= p_as_of and (p_include_demo or not s.is_demo)),
  ag as (
    select cid, count(*)::int n, min(due) oldest,
           sum(o) filter (where od <= 0)::bigint nd, sum(o) filter (where od between 1 and 30)::bigint a1,
           sum(o) filter (where od between 31 and 60)::bigint a2, sum(o) filter (where od between 61 and 90)::bigint a3,
           sum(o) filter (where od > 90)::bigint a4
    from inv group by cid)
  select c.id, c.code, c.name, c.kind, c.phone, coalesce(ar.bal, 0), greatest(rb_sal_free_credit(c.id), 0),
         coalesce(ag.nd, 0), coalesce(ag.a1, 0), coalesce(ag.a2, 0), coalesce(ag.a3, 0), coalesce(ag.a4, 0),
         coalesce(ag.n, 0), ag.oldest, c.credit_limit_paise, c.credit_days,
         c.credit_limit_paise is not null and coalesce(ar.bal, 0) > c.credit_limit_paise, c.is_demo
  from customers c left join ar on ar.cid = c.id left join ag on ag.cid = c.id
  where (ar.cid is not null and ar.bal <> 0) or ag.cid is not null or rb_sal_free_credit(c.id) > 0
  order by coalesce(ar.bal, 0) desc, c.name;
end $$;

create or replace function rb_customer_statement(p_customer int, p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not rb_sal_money_ok() then raise exception 'You do not have the right to see customer statements.'; end if;
  return rb_sal_statement(p_customer, coalesce(p_from, rb_fy_start(current_date)), coalesce(p_to, current_date))
         || jsonb_build_object('links', coalesce((select jsonb_agg(jsonb_build_object('token', token, 'from_date', from_date,
              'expires_at', expires_at, 'opened_count', opened_count, 'last_opened', last_opened) order by created_at desc)
              from statement_links where customer_id = p_customer and revoked_at is null and expires_at > now()), '[]'::jsonb));
end $$;

-- Sales by day, product and customer type (returns as minus rows on their own date).
create or replace function rb_sales_summary(p_from date, p_to date)
returns table (sale_date date, channel text, customer_kind text, item_id int, item_name text, pack_name text, base_unit text,
               qty_base numeric, packs numeric, invoices int, gross_paise bigint, discount_paise bigint, net_paise bigint,
               gst_paise bigint, cost_paise bigint, margin_paise bigint, is_demo boolean)
language plpgsql stable security definer set search_path = public as $$
declare v_cost boolean := rb_sal_cost_ok();
begin
  if not rb_has('power.see_totals') or not (rb_has('sales.view') or rb_has('invoices.view') or rb_has('reports.view') or rb_has('accounts.view')) then
    raise exception 'You do not have the right to see sales totals.';
  end if;
  return query
  with x as (
    select s.invoice_date d, s.channel ch, c.kind ck, l.item_id iid, l.pack_id pid, l.qty_base q, l.packs pk, s.id sid,
           l.rev_gross_paise g, l.rev_discount_paise dc, l.taxable_paise n, l.cgst_paise + l.sgst_paise + l.igst_paise t, l.cost_paise co,
           s.is_demo dm
    from sale_lines l join sales s on s.id = l.sale_id join customers c on c.id = s.customer_id
    where s.status <> 'cancelled' and s.invoice_date between p_from and p_to
    union all
    select r.return_date, s.channel, c.kind, l.item_id, l.pack_id, -x.qty_base, -x.packs, null, 0, 0, -x.taxable_paise,
           -(x.cgst_paise + x.sgst_paise + x.igst_paise), -case when r.condition = 'restock' then x.cost_paise else 0 end, r.is_demo
    from sales_return_lines x join sales_returns r on r.id = x.return_id join sale_lines l on l.id = x.sale_line_id
    join sales s on s.id = r.sale_id join customers c on c.id = s.customer_id
    where r.status = 'posted' and r.return_date between p_from and p_to)
  select x.d, x.ch, x.ck, x.iid, i.name, pt.name, i.base_unit, sum(x.q)::numeric, sum(x.pk)::numeric, count(distinct x.sid)::int,
         sum(x.g)::bigint, sum(x.dc)::bigint, sum(x.n)::bigint, sum(x.t)::bigint,
         case when v_cost then sum(x.co)::bigint end, case when v_cost then (sum(x.n) - sum(x.co))::bigint end, bool_or(x.dm)
  from x join items i on i.id = x.iid left join product_packs pp on pp.id = x.pid left join pack_types pt on pt.id = pp.pack_type_id
  group by x.d, x.ch, x.ck, x.iid, i.name, pt.name, i.base_unit, pp.net_qty
  order by x.d, i.name, pp.net_qty nulls last;
end $$;

-- ---------------------------------------------------------------------
-- 10. Row-level security and who may call what
-- ---------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array['sales', 'sale_lines', 'sales_returns', 'sales_return_lines', 'customer_receipts', 'customer_refunds',
                           'ar_allocations', 'statement_links', 'customer_write_offs', 'bad_debt_recoveries'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon, authenticated', t);
    execute format('grant select on %I to authenticated', t);
    execute format('grant all on %I to service_role', t);
    execute format('drop policy if exists rb_read on %I', t);
    if t = 'statement_links' then
      -- the link tokens are read only through rb_customer_statement
      execute format('create policy rb_read on %I for select to authenticated using (false)', t);
    else
      -- These hold costs, so only the margin tick reads them directly; the
      -- screens read through the rb_ functions above, which hide costs and totals.
      execute format('create policy rb_read on %I for select to authenticated using (rb_sal_cost_ok())', t);
    end if;
  end loop;
end $$;
-- Stock movements: the sales screens read stock through rb_stock_list.
drop policy if exists rb_read on stock_moves;
create policy rb_read on stock_moves for select to authenticated
  using (rb_stk_cost_ok() or (purchase_id is not null and rb_has('purchases.view')));
revoke all on all sequences in schema public from anon, authenticated;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p
           where p.pronamespace = 'public'::regnamespace
             and (p.proname like 'rb\_sal\_%' or p.proname in (
               'rb_save_sale', 'rb_cancel_sale', 'rb_hard_delete_sale', 'rb_save_sales_return', 'rb_approve_sales_return',
               'rb_refuse_sales_return', 'rb_reverse_sales_return', 'rb_receive_from_customer', 'rb_allocate_customer_credit',
               'rb_reverse_customer_receipt', 'rb_hard_delete_customer_receipt', 'rb_refund_customer', 'rb_reverse_customer_refund',
               'rb_create_statement_link', 'rb_revoke_statement_links', 'rb_public_statement', 'rb_save_sales_settings',
               'rb_sales_list', 'rb_sale_detail', 'rb_sales_returns_list', 'rb_customer_receipts_list', 'rb_customer_open_items',
               'rb_customer_balances', 'rb_customer_statement', 'rb_sales_summary', 'rb_write_off_bad_debt', 'rb_reverse_bad_debt',
               'rb_record_bad_debt_recovery', 'rb_reverse_bad_debt_recovery', 'rb_bad_debts_list')) loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;
end $$;
-- Used inside row-level security, so it must stay callable (it only says yes or no).
grant execute on function rb_sal_cost_ok() to authenticated;
-- The one function anyone with a statement link may call.
grant execute on function rb_public_statement(text) to anon, authenticated;
grant execute on function
  rb_save_sale(jsonb), rb_cancel_sale(bigint, date, text), rb_hard_delete_sale(bigint),
  rb_save_sales_return(jsonb), rb_approve_sales_return(bigint), rb_refuse_sales_return(bigint, text),
  rb_reverse_sales_return(bigint, date, text), rb_receive_from_customer(jsonb), rb_allocate_customer_credit(text, bigint, jsonb),
  rb_reverse_customer_receipt(bigint, date, text), rb_hard_delete_customer_receipt(bigint), rb_refund_customer(jsonb),
  rb_reverse_customer_refund(bigint, date, text), rb_create_statement_link(int, date), rb_revoke_statement_links(int),
  rb_save_sales_settings(jsonb), rb_sales_list(date, date), rb_sale_detail(bigint), rb_sales_returns_list(),
  rb_customer_receipts_list(), rb_customer_open_items(int), rb_customer_balances(date, boolean),
  rb_customer_statement(int, date, date), rb_sales_summary(date, date),
  rb_write_off_bad_debt(jsonb), rb_reverse_bad_debt(bigint, date, text), rb_record_bad_debt_recovery(jsonb),
  rb_reverse_bad_debt_recovery(bigint, date, text), rb_bad_debts_list()
  to authenticated;

-- ---------------------------------------------------------------------
-- 11. DEMO data: 12 invoices in Nov 2026 from the DEMO finished goods
--     (counter sales in cash and UPI with a discount, trader sales on
--     credit, a part payment, a loose sale by weight, a by-product sale),
--     receipts against invoices and on account, a credit note for
--     damaged goods, a return waiting for approval, and a refund.
--     Only added while the app is in training mode.
-- ---------------------------------------------------------------------

do $$
declare
  v_ds uuid := (select id from app_users where lower(email) = 'info.ruchibuds@gmail.com');
  v_acc uuid := (select id from app_users where email = 'demo.accounts@example.com');
  v_mgr uuid := coalesce((select id from app_users where email = 'demo.manager1@example.com'), v_acc);
  v_sal uuid := coalesce((select id from app_users where email = 'demo.sales@example.com'), v_mgr);
  v_stf uuid := coalesce((select id from app_users where email = 'demo.staff1@example.com'), v_sal);
  v_ar  uuid := coalesce((select id from app_users where email = 'demo.ar@example.com'), v_acc);
  it jsonb; pk jsonb; cu jsonb; v_walk int; x jsonb; s3 bigint; s4 bigint; s8 bigint; v_r bigint;
begin
  if not (select training_mode from app_settings where id = 1) or exists (select 1 from sales where is_demo)
     or not exists (select 1 from production_batches where is_demo) then
    return;
  end if;
  select jsonb_object_agg(code, id) into it from items where is_demo;
  select jsonb_object_agg(code, id) into cu from customers where is_demo;
  select jsonb_object_agg(i.code || '/' || pt.code, pp.id) into pk
  from product_packs pp join items i on i.id = pp.item_id join pack_types pt on pt.id = pp.pack_type_id where pp.is_demo;
  select id into v_walk from customers where is_walk_in limit 1;

  -- 1. Anita Sharma: a 1 kg pouch of chilli powder and 500 g loose, by UPI.
  perform rb_sal_save(jsonb_build_object('customer_id', cu->'DEMO-C01', 'invoice_date', '2026-11-21', 'payment_mode', 'upi',
    'payment_ref', 'UPI 6620114', 'lines', jsonb_build_array(
      jsonb_build_object('item_id', it->'D-FG04', 'pack_id', pk->'D-FG04/D-PT4', 'packs', 1),
      jsonb_build_object('item_id', it->'D-FG04', 'qty', 500, 'unit', 'g'))), v_stf, true);
  -- 2. Counter sale to a walk-in: 2 bottles of smoked meat pickle, 10% festival discount, cash.
  perform rb_sal_save(jsonb_build_object('customer_id', v_walk, 'invoice_date', '2026-11-22', 'payment_mode', 'cash',
    'note', 'Counter sale (DEMO)', 'lines', jsonb_build_array(
      jsonb_build_object('item_id', it->'D-FG03', 'pack_id', pk->'D-FG03/D-PT1', 'packs', 2, 'discount_pct', 10))), v_stf, true);
  -- 3. Sai Provision Store (trader, 15 days' credit): pickles and small chilli packs on credit.
  x := rb_sal_save(jsonb_build_object('customer_id', cu->'DEMO-C06', 'invoice_date', '2026-11-22', 'payment_mode', 'credit',
    'lines', jsonb_build_array(
      jsonb_build_object('item_id', it->'D-FG03', 'pack_id', pk->'D-FG03/D-PT1', 'packs', 10),
      jsonb_build_object('item_id', it->'D-FG04', 'pack_id', pk->'D-FG04/D-PT1', 'packs', 20))), v_sal, true);
  s3 := (x->>'id')::bigint;
  -- 4. Konkan Foods (trader, 30 days): chilli powder pouches, pickles and 2 kg loose chilli, on credit.
  x := rb_sal_save(jsonb_build_object('customer_id', cu->'DEMO-C07', 'invoice_date', '2026-11-23', 'payment_mode', 'credit',
    'lines', jsonb_build_array(
      jsonb_build_object('item_id', it->'D-FG04', 'pack_id', pk->'D-FG04/D-PT4', 'packs', 5),
      jsonb_build_object('item_id', it->'D-FG03', 'pack_id', pk->'D-FG03/D-PT1', 'packs', 8),
      jsonb_build_object('item_id', it->'D-FG04', 'qty', 2, 'unit', 'kg', 'discount_paise', 6000))), v_sal, true);
  s4 := (x->>'id')::bigint;
  -- 5. Rahul Verma: one bottle, cash.
  perform rb_sal_save(jsonb_build_object('customer_id', cu->'DEMO-C02', 'invoice_date', '2026-11-24', 'payment_mode', 'cash',
    'lines', jsonb_build_array(jsonb_build_object('item_id', it->'D-FG03', 'pack_id', pk->'D-FG03/D-PT1', 'packs', 1))), v_stf, true);
  -- 6. Green Basket Mart: ₹1,000 paid by bank at the sale, the rest on credit.
  perform rb_sal_save(jsonb_build_object('customer_id', cu->'DEMO-C08', 'invoice_date', '2026-11-24', 'payment_mode', 'bank',
    'paid_paise', 100000, 'payment_ref', 'IMPS 88123', 'lines', jsonb_build_array(
      jsonb_build_object('item_id', it->'D-FG04', 'pack_id', pk->'D-FG04/D-PT1', 'packs', 20))), v_sal, true);
  -- 7. A by-product sold loose: 1 kg of meat trimmings to a walk-in, cash.
  perform rb_sal_save(jsonb_build_object('customer_id', v_walk, 'invoice_date', '2026-11-25', 'payment_mode', 'cash',
    'lines', jsonb_build_array(jsonb_build_object('item_id', it->'D-BP03', 'qty', 1, 'unit', 'kg'))), v_stf, true);
  -- 8. Farah Khan: smoked meat pickle and chilli powder, ₹20 off the bill, UPI.
  perform rb_sal_save(jsonb_build_object('customer_id', cu->'DEMO-C05', 'invoice_date', '2026-11-26', 'payment_mode', 'upi',
    'lines', jsonb_build_array(
      jsonb_build_object('item_id', it->'D-FG03', 'pack_id', pk->'D-FG03/D-PT1', 'packs', 1, 'discount_paise', 2000),
      jsonb_build_object('item_id', it->'D-FG04', 'pack_id', pk->'D-FG04/D-PT1', 'packs', 2))), v_stf, true);

  -- 9. Joseph D'Souza: fish and chicken pickle, by UPI.
  x := rb_sal_save(jsonb_build_object('customer_id', cu->'DEMO-C04', 'invoice_date', '2026-11-27', 'payment_mode', 'upi',
    'payment_ref', 'UPI 7731902', 'lines', jsonb_build_array(
      jsonb_build_object('item_id', it->'D-FG01', 'pack_id', pk->'D-FG01/D-PT1', 'packs', 2),
      jsonb_build_object('item_id', it->'D-FG02', 'pack_id', pk->'D-FG02/D-PT1', 'packs', 1))), v_stf, true);
  s8 := (x->>'id')::bigint;
  -- 10. Hill Top Caterers: 500 g bottles for an event, on credit.
  perform rb_sal_save(jsonb_build_object('customer_id', cu->'DEMO-C09', 'invoice_date', '2026-11-27', 'payment_mode', 'credit',
    'lines', jsonb_build_array(
      jsonb_build_object('item_id', it->'D-FG01', 'pack_id', pk->'D-FG01/D-PT2', 'packs', 2),
      jsonb_build_object('item_id', it->'D-FG02', 'pack_id', pk->'D-FG02/D-PT2', 'packs', 3))), v_sal, true);
  -- 11. Coastal Delights: 10 fish pickle bottles at the trader price, a special rate agreed by the Manager.
  perform rb_sal_save(jsonb_build_object('customer_id', cu->'DEMO-C10', 'invoice_date', '2026-11-27', 'payment_mode', 'credit',
    'note', 'Opening order: ₹230 a bottle agreed (DEMO)', 'lines', jsonb_build_array(
      jsonb_build_object('item_id', it->'D-FG01', 'pack_id', pk->'D-FG01/D-PT1', 'packs', 10, 'rate_paise', 23000))), v_mgr, true);
  -- 12. Walk-in: two bottles of chicken pickle, cash.
  perform rb_sal_save(jsonb_build_object('customer_id', v_walk, 'invoice_date', '2026-11-27', 'payment_mode', 'cash',
    'lines', jsonb_build_array(jsonb_build_object('item_id', it->'D-FG02', 'pack_id', pk->'D-FG02/D-PT1', 'packs', 2))), v_stf, true);
  -- Receipts: Sai Provision Store pays invoice 3 and its October balance (entered by journal in module 2).
  perform rb_sal_receive(jsonb_build_object('customer_id', cu->'DEMO-C06', 'receipt_date', '2026-11-26', 'mode', 'bank',
    'amount_paise', (select total_paise from sales where id = s3) + 480000, 'reference', 'NEFT SAI-2611',
    'note', 'Invoice and the October fair balance (DEMO)',
    'allocations', jsonb_build_array(jsonb_build_object('sale_id', s3, 'amount_paise', (select total_paise from sales where id = s3)),
                                     jsonb_build_object('sale_id', null, 'amount_paise', 480000))), v_ar, true);
  -- Konkan Foods pays ₹2,000 in cash towards invoice 4.
  perform rb_sal_receive(jsonb_build_object('customer_id', cu->'DEMO-C07', 'receipt_date', '2026-11-25', 'mode', 'cash',
    'amount_paise', 200000, 'reference', 'Cash receipt book 14',
    'allocations', jsonb_build_array(jsonb_build_object('sale_id', s4, 'amount_paise', 200000))), v_ar, true);

  -- Returns: Konkan Foods sends back 2 bottles with broken lids (thrown away); the Accountant posts it.
  v_r := rb_sal_save_return(jsonb_build_object('sale_id', s4, 'return_date', '2026-11-26', 'condition', 'discard',
    'reason', 'Two bottles arrived with broken lids (DEMO)', 'lines', jsonb_build_array(
      jsonb_build_object('sale_line_id', (select id from sale_lines where sale_id = s4 and line_no = 2), 'packs', 2))), v_acc, true);
  perform rb_sal_post_return(v_r, v_acc);
  -- Joseph D'Souza brings back the chicken pickle unopened; the Manager approves it and the Accountant refunds by UPI.
  v_r := rb_sal_save_return(jsonb_build_object('sale_id', s8, 'return_date', '2026-11-27', 'condition', 'restock',
    'reason', 'Bought by mistake, unopened (DEMO)', 'lines', jsonb_build_array(
      jsonb_build_object('sale_line_id', (select id from sale_lines where sale_id = s8 and line_no = 2), 'packs', 1))), v_stf, true);
  perform rb_sal_post_return(v_r, v_mgr);
  perform rb_sal_refund(jsonb_build_object('customer_id', cu->'DEMO-C04', 'refund_date', '2026-11-27', 'mode', 'upi',
    'amount_paise', (select total_paise from sales_returns where id = v_r), 'return_id', v_r, 'reference', 'UPI refund 99012',
    'reason', 'Unopened bottle returned (DEMO)'), v_acc, true);
  -- Rahul Verma brings back his bottle: entered at the counter, waiting for approval.
  perform rb_sal_save_return(jsonb_build_object('sale_id', (select id from sales where is_demo and customer_id = (cu->>'DEMO-C02')::int limit 1),
    'return_date', '2026-11-27', 'condition', 'restock', 'reason', 'Customer changed their mind, seal intact (DEMO)',
    'lines', (select jsonb_agg(jsonb_build_object('sale_line_id', l.id, 'packs', 1)) from sale_lines l join sales s on s.id = l.sale_id
              where s.is_demo and s.customer_id = (cu->>'DEMO-C02')::int)), v_stf, true);
end $$;

-- ---------------------------------------------------------------------
-- 12. DEMO bad debt (added in 1.1, so it also arrives on a re-run):
--     Coastal Delights closes down; the FC writes off its invoice, then
--     ₹1,000 comes in from the owner and is booked as recovered.
-- ---------------------------------------------------------------------

do $$
declare
  v_fc uuid := coalesce((select id from app_users where email = 'demo.fc@example.com'),
                        (select id from app_users where lower(email) = 'info.ruchibuds@gmail.com'));
  v_ar uuid := coalesce((select id from app_users where email = 'demo.ar@example.com'), v_fc);
  v_c int := (select id from customers where code = 'DEMO-C10' and is_demo);
  v_s sales; v_w bigint;
begin
  if not (select training_mode from app_settings where id = 1) or exists (select 1 from customer_write_offs where is_demo) then
    return;
  end if;
  select * into v_s from sales where is_demo and customer_id = v_c and status = 'open' order by id limit 1;
  if v_s.id is null then return; end if;
  v_w := rb_sal_write_off(jsonb_build_object('customer_id', v_c, 'sale_id', v_s.id, 'write_off_date', '2026-11-27',
    'amount_paise', v_s.outstanding_paise, 'reason', 'Restaurant closed down, owner not reachable (DEMO)'), v_fc, true);
  perform rb_sal_receive(jsonb_build_object('customer_id', v_c, 'receipt_date', '2026-11-27', 'mode', 'upi', 'amount_paise', 100000,
    'reference', 'UPI from the owner', 'note', 'Part of the written-off invoice (DEMO)'), v_ar, true);
  perform rb_sal_recover(jsonb_build_object('write_off_id', v_w, 'recovery_date', '2026-11-27', 'amount_paise', 100000,
    'note', 'Owner paid part by UPI (DEMO)'), v_fc, true);
end $$;

-- End of 05_sales_invoices.sql
