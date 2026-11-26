-- =====================================================================
-- RUCHI BUDS APP · Module 3: Purchases and supplier balances (AP)
-- File: 03_purchases.sql · Version 1.0 · 26-Nov-2026
--
-- What this file sets up:
--   One Purchase record that holds the order (PO), the goods received
--   (GRN) and the supplier's bill side by side; direct purchases with no
--   PO (fish, cash buys, urgent top-ups), with or without a supplier bill
--   and a photo or note; approval of direct purchases above the Settings
--   limit; the match of PO, GRN and Bill with every difference flagged
--   (no tolerance); Accept or Reject for each difference (return, debit
--   note, wait for the rest, correct the rate); purchase returns;
--   supplier payments against open purchases; supplier balances and
--   ledger; the discrepancy and direct-purchase reports; and the stock
--   movement record that module 4 (Stock and production) builds on.
--
-- Accounting (Indian AS, ICAI): stock is added at cost when goods are
-- received (AS 2), against "Goods received not invoiced". The supplier
-- balance is raised from the bill. A bill that differs from the GRN
-- value moves the difference into stock cost, so stock carries the real
-- purchase cost. GST on a bill is "Input GST recoverable" only when the
-- firm's GSTIN is filled in Settings; otherwise it is part of stock cost.
--
-- Run 01_core_users.sql and 02_masters.sql first. Then: Supabase ->
-- SQL Editor -> New query -> paste this whole file -> Run. It is safe to
-- run again; nothing you entered is lost on a re-run.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Screens and the new special right
-- ---------------------------------------------------------------------

update screens set available = true where code in ('purchases', 'suppliers');

do $$
begin
  -- New right: settle money differences on purchases. Given once to every
  -- Accountant category (Directors and the FC always have every right).
  if not exists (select 1 from permissions where code = 'power.purchase_values') then
    insert into powers (code, name, description, sort) values
      ('purchase_values', 'Settle purchase money differences',
       'Approve direct purchases above the Settings limit, accept rate, tax and billed-quantity differences, correct rates and issue debit notes', 65)
    on conflict (code) do nothing;
    insert into permissions (code, kind, power_code, sort) values ('power.purchase_values', 'power', 'purchase_values', 10065)
    on conflict (code) do nothing;
    insert into category_access (category_id, perm)
    select id, 'power.purchase_values' from user_categories where template = 'Accountant'
    on conflict do nothing;
  end if;
end $$;
update powers set name = 'Settle purchase money differences',
  description = 'Approve direct purchases above the Settings limit, accept rate, tax and billed-quantity differences, correct rates and issue debit notes'
where code = 'purchase_values';

-- ---------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------

-- One record per purchase: the order, what came in, and the supplier's bill.
create table if not exists purchases (
  id                  bigserial primary key,
  entity_code         text not null default 'E002' references entities(code),
  currency            text not null default 'INR',
  supplier_id         int not null references suppliers(id),
  department_id       int not null references departments(id),
  is_direct           boolean not null default false,
  po_no               text unique,
  po_date             date,
  expected_date       date,
  status              text not null default 'ordered' check (status in
                      ('ordered', 'part_received', 'received', 'billed', 'paid',
                       'awaiting_approval', 'refused', 'cancelled')),
  -- Direct purchases
  purchase_date       date,                 -- the day the goods came in (direct purchases)
  reason              text,                 -- why there is no PO
  no_supplier_bill    boolean not null default false,
  -- The supplier's bill
  bill_no             text,
  bill_date           date,
  bill_posted_at      timestamptz,
  bill_journal_id     bigint references journals(id) on delete set null,
  payment_mode        text not null default 'credit' check (payment_mode in ('credit', 'cash', 'upi', 'bank')),
  -- Running totals (kept up to date by rb_pur_refresh)
  order_total_paise   bigint not null default 0,
  grn_value_paise     bigint not null default 0,
  bill_taxable_paise  bigint not null default 0,
  bill_gst_paise      bigint not null default 0,
  bill_total_paise    bigint not null default 0,
  notes_paise         bigint not null default 0,  -- debit notes and returns after the bill (reduce what is owed)
  paid_paise          bigint not null default 0,
  outstanding_paise   bigint not null default 0,
  open_discrepancies  int not null default 0,
  note                text,
  approval_needed     boolean not null default false,
  approved_by         uuid references app_users(id),
  approved_at         timestamptz,
  refused_reason      text,
  cancel_reason       text,
  entered_by          uuid references app_users(id),
  entered_at          timestamptz not null default now(),
  is_demo             boolean not null default false,
  is_training         boolean not null default false,
  updated_at          timestamptz,
  updated_by          uuid
);
create index if not exists purchases_supplier_idx on purchases (supplier_id);
create index if not exists purchases_status_idx on purchases (status);

create table if not exists purchase_lines (
  id                 bigserial primary key,
  purchase_id        bigint not null references purchases(id) on delete cascade,
  line_no            int not null,
  item_id            int not null references items(id),
  unit_code          text not null references units(code),
  -- Order (PO)
  po_qty             numeric(14,3),
  po_rate_paise      bigint check (po_rate_paise >= 0),   -- per unit, before GST
  gst_rate           numeric(5,2) check (gst_rate between 0 and 40),
  -- Receipt (sum of all GRNs, kept up to date)
  grn_rate_paise     bigint not null default 0,            -- the rate goods are taken into stock at
  received_qty       numeric(14,3) not null default 0,
  rejected_qty       numeric(14,3) not null default 0,     -- damaged or refused at the door
  returned_qty       numeric(14,3) not null default 0,     -- sent back later from stock
  returned_before_bill_qty numeric(14,3) not null default 0,
  -- Bill
  bill_qty           numeric(14,3),
  bill_rate_paise    bigint check (bill_rate_paise >= 0),
  bill_taxable_paise bigint,
  bill_gst_paise     bigint check (bill_gst_paise >= 0),
  -- What was finally agreed with the supplier after differences were settled
  agreed_qty         numeric(14,3),
  agreed_rate_paise  bigint,
  gst_at_po_rate     boolean not null default false,
  is_demo            boolean not null default false,
  is_training        boolean not null default false,
  unique (purchase_id, line_no)
);
create index if not exists purchase_lines_purchase_idx on purchase_lines (purchase_id);

-- Goods received notes. A purchase can arrive in more than one delivery.
create table if not exists purchase_grns (
  id           bigserial primary key,
  purchase_id  bigint not null references purchases(id) on delete cascade,
  grn_no       text not null unique,
  grn_date     date not null,
  value_paise  bigint not null default 0,
  journal_id   bigint references journals(id) on delete set null,
  note         text,
  entered_by   uuid references app_users(id),
  entered_at   timestamptz not null default now(),
  is_demo      boolean not null default false,
  is_training  boolean not null default false
);
create index if not exists purchase_grns_purchase_idx on purchase_grns (purchase_id);

create table if not exists purchase_grn_lines (
  id                bigserial primary key,
  grn_id            bigint not null references purchase_grns(id) on delete cascade,
  purchase_line_id  bigint not null references purchase_lines(id) on delete cascade,
  received_qty      numeric(14,3) not null check (received_qty >= 0),
  rejected_qty      numeric(14,3) not null default 0 check (rejected_qty >= 0),
  reject_reason     text,
  rate_paise        bigint not null,
  value_paise       bigint not null,                       -- accepted quantity x rate
  is_demo           boolean not null default false,
  is_training       boolean not null default false,
  check (rejected_qty <= received_qty)
);

-- Every difference between PO, GRN and Bill, however small.
create table if not exists purchase_discrepancies (
  id                bigserial primary key,
  purchase_id       bigint not null references purchases(id) on delete cascade,
  purchase_line_id  bigint not null references purchase_lines(id) on delete cascade,
  stage             text not null check (stage in ('receipt', 'bill')),
  kind              text not null check (kind in ('short', 'excess', 'damaged', 'rate', 'tax')),
  qty_diff          numeric(14,3),            -- positive = more than expected
  amount_paise      bigint not null,          -- positive = the supplier asks for more than expected
  explain           text not null,
  status            text not null default 'open' check (status in ('open', 'accepted', 'rejected')),
  action            text check (action in ('accept', 'return', 'debit_note', 'await_delivery', 'correct_rate')),
  reason            text,
  decided_by        uuid references app_users(id),
  decided_at        timestamptz,
  first_seen        date not null default current_date,
  is_demo           boolean not null default false,
  is_training       boolean not null default false,
  unique (purchase_line_id, stage, kind)
);
create index if not exists purchase_discrepancies_open_idx on purchase_discrepancies (status);

-- Debit notes to suppliers (overcharges, short supply, wrong rate or tax).
create table if not exists purchase_notes (
  id                bigserial primary key,
  purchase_id       bigint not null references purchases(id) on delete cascade,
  purchase_line_id  bigint references purchase_lines(id) on delete cascade,
  discrepancy_id    bigint references purchase_discrepancies(id) on delete set null,
  note_no           text not null unique,
  note_date         date not null,
  taxable_paise     bigint not null default 0,
  gst_paise         bigint not null default 0,
  total_paise       bigint not null,
  reason            text not null,
  journal_id        bigint references journals(id) on delete set null,
  entered_by        uuid references app_users(id),
  entered_at        timestamptz not null default now(),
  is_demo           boolean not null default false,
  is_training       boolean not null default false
);

-- Goods sent back to the supplier.
create table if not exists purchase_returns (
  id               bigserial primary key,
  purchase_id      bigint not null references purchases(id) on delete cascade,
  discrepancy_id   bigint references purchase_discrepancies(id) on delete set null,
  return_no        text not null unique,
  return_date      date not null,
  reason           text not null,
  from_stock       boolean not null default true,   -- false = goods refused at the door, never in stock
  after_bill       boolean not null default false,
  taxable_paise    bigint not null default 0,
  gst_paise        bigint not null default 0,
  total_paise      bigint not null default 0,
  journal_id       bigint references journals(id) on delete set null,
  entered_by       uuid references app_users(id),
  entered_at       timestamptz not null default now(),
  is_demo          boolean not null default false,
  is_training      boolean not null default false
);
create table if not exists purchase_return_lines (
  id                bigserial primary key,
  return_id         bigint not null references purchase_returns(id) on delete cascade,
  purchase_line_id  bigint not null references purchase_lines(id) on delete cascade,
  qty               numeric(14,3) not null check (qty > 0),
  rate_paise        bigint not null,
  value_paise       bigint not null,
  gst_paise         bigint not null default 0,
  is_demo           boolean not null default false,
  is_training       boolean not null default false
);

-- Payments to suppliers, and which purchases each one settles.
create table if not exists supplier_payments (
  id                   bigserial primary key,
  payment_no           text not null unique,
  supplier_id          int not null references suppliers(id),
  pay_date             date not null,
  mode                 text not null check (mode in ('cash', 'upi', 'bank')),
  amount_paise         bigint not null check (amount_paise > 0),
  reference            text,
  note                 text,
  department_id        int references departments(id),
  status               text not null default 'posted' check (status in ('posted', 'reversed')),
  journal_id           bigint references journals(id) on delete set null,
  reversal_journal_id  bigint references journals(id) on delete set null,
  reverse_reason       text,
  entered_by           uuid references app_users(id),
  entered_at           timestamptz not null default now(),
  is_demo              boolean not null default false,
  is_training          boolean not null default false
);
create index if not exists supplier_payments_supplier_idx on supplier_payments (supplier_id);

create table if not exists payment_allocations (
  id            bigserial primary key,
  payment_id    bigint not null references supplier_payments(id) on delete cascade,
  purchase_id   bigint not null references purchases(id) on delete cascade,
  amount_paise  bigint not null check (amount_paise > 0),
  is_demo       boolean not null default false,
  is_training   boolean not null default false
);
create index if not exists payment_allocations_purchase_idx on payment_allocations (purchase_id);

-- A photo of the catch or weighing slip, or of a bill (stored small).
create table if not exists purchase_photos (
  id           bigserial primary key,
  purchase_id  bigint not null references purchases(id) on delete cascade,
  data_url     text not null check (data_url like 'data:image/%' and length(data_url) <= 700000),
  caption      text,
  added_by     uuid references app_users(id),
  added_at     timestamptz not null default now(),
  is_demo      boolean not null default false,
  is_training  boolean not null default false
);

-- Every movement of stock, in the item's base unit (grams, ml, pieces).
-- Purchases write receipts, returns and cost changes now; module 4
-- (Stock and production) adds preparation, production, counts and sales.
create table if not exists stock_moves (
  id            bigserial primary key,
  move_date     date not null,
  item_id       int not null references items(id),
  qty_base      numeric(16,3) not null,          -- + in, - out
  value_paise   bigint not null,                 -- + adds cost, - removes cost
  kind          text not null check (kind in ('grn', 'bill_adjust', 'debit_note', 'purchase_return', 'reversal',
                                              'preparation', 'production', 'wastage', 'count', 'sale', 'sales_return', 'opening')),
  doc_no        text,
  purchase_id   bigint references purchases(id) on delete cascade,
  journal_id    bigint references journals(id) on delete set null,
  department_id int references departments(id),
  note          text,
  created_at    timestamptz not null default now(),
  created_by    uuid,
  is_demo       boolean not null default false,
  is_training   boolean not null default false
);
create index if not exists stock_moves_item_idx on stock_moves (item_id, move_date);
create index if not exists stock_moves_purchase_idx on stock_moves (purchase_id) where purchase_id is not null;

-- ---------------------------------------------------------------------
-- 3. Posting rules for this module (in addition to module 2's list)
-- ---------------------------------------------------------------------

insert into posting_rules (event_code, line_key, side, account_code, module, label, sort) values
  ('grn',             'stock_variance',   'debit',  '10030105', 3, 'Bill differs from GRN value: change in raw-material cost', 23),
  ('grn',             'packaging_variance','debit', '10030110', 3, 'Bill differs from GRN value: change in packaging cost', 24),
  ('direct_purchase', 'stock_packaging',  'debit',  '10030110', 3, 'Direct purchase into packaging stock', 44),
  ('direct_purchase', 'input_gst',        'debit',  '10050105', 3, 'Input GST on a direct purchase', 44),
  ('debit_note',      'payable',          'debit',  '30010105', 3, 'Debit note: reduces the supplier balance', 50),
  ('debit_note',      'input_gst',        'credit', '10050105', 3, 'Debit note: input GST given back', 51),
  ('purchase_return', 'stock_packaging',  'credit', '10030110', 3, 'Packaging returned out of stock', 49),
  ('purchase_return', 'grni',             'debit',  '30010115', 3, 'Return before the bill: clears goods received not invoiced', 49),
  ('purchase_return', 'input_gst',        'credit', '10050105', 3, 'Return after the bill: input GST given back', 49)
on conflict (event_code, line_key) do nothing;

-- ---------------------------------------------------------------------
-- 4. Helpers (private: used by the functions below)
-- ---------------------------------------------------------------------

-- Number series: DEMO and training records get their own, so the real
-- PO/YYMM/00001 series starts clean at go-live.
create or replace function rb_pur_series(p_base text, p_demo boolean)
returns text language sql stable security definer set search_path = public as $$
  select case when p_demo then 'DEMO-' || p_base when rb_is_training() then 'TRN-' || p_base else p_base end
$$;

create or replace function rb_pur_amt(p_qty numeric, p_rate bigint)
returns bigint language sql immutable as $$ select round(coalesce(p_qty, 0) * coalesce(p_rate, 0))::bigint $$;

-- Quantity in the item's base unit (e.g. 2.5 kg -> 2500 g).
create or replace function rb_pur_base_qty(p_item int, p_unit text, p_qty numeric)
returns numeric language plpgsql stable security definer set search_path = public as $$
declare v_u units; v_b units;
begin
  select * into v_u from units where code = p_unit;
  select b.* into v_b from items i join units b on b.code = i.base_unit where i.id = p_item;
  if v_u.code is null or v_b.code is null then raise exception 'Unknown unit or item.'; end if;
  if v_u.dimension <> v_b.dimension then
    raise exception 'Unit % does not fit this item (it is counted in %).', v_u.code, v_b.code;
  end if;
  return round(p_qty * v_u.to_base / v_b.to_base, 3);
end $$;

-- GST is recoverable only when the firm is registered (GSTIN in Settings).
create or replace function rb_pur_gst_claimable()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select gstin is not null and trim(gstin) <> '' from app_settings where id = 1), false)
$$;

-- The stock rule for an item: raw materials or packaging.
create or replace function rb_pur_stock_key(p_item int)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_kind text;
begin
  select kind into v_kind from items where id = p_item;
  if v_kind = 'packaging' then return 'stock_packaging'; end if;
  if v_kind = 'raw' then return 'stock_raw'; end if;
  raise exception 'Only raw materials and packaging (bottles, pouches) are bought through Purchases.';
end $$;

-- The unit an item is usually bought in, when it converts to the stock unit
-- (a "box" of bottles does not, so bottles are bought by the piece).
create or replace function rb_pur_default_unit(p_item int)
returns text language sql stable security definer set search_path = public as $$
  select case when bu.dimension = b.dimension then i.buy_unit else i.base_unit end
  from items i join units b on b.code = i.base_unit left join units bu on bu.code = i.buy_unit where i.id = p_item
$$;

create or replace function rb_pur_default_dept()
returns int language sql stable security definer set search_path = public as $$
  select coalesce((select id from departments where code = 'CC001' and is_active),
                  (select id from departments where is_active order by code limit 1))
$$;

create or replace function rb_pur_fmt(p bigint)
returns text language sql immutable as $$ select '₹' || to_char(coalesce(p, 0) / 100.0, 'FM99,99,99,99,990.00') $$;

create or replace function rb_pur_label(p purchases)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(p.po_no, (select grn_no from purchase_grns g where g.purchase_id = p.id order by g.id limit 1), 'purchase ' || p.id)
$$;

-- Write a stock movement.
create or replace function rb_pur_stock(p_date date, p_item int, p_qty numeric, p_value bigint, p_kind text,
                                        p_doc text, p_purchase bigint, p_journal bigint, p_dept int, p_actor uuid, p_demo boolean)
returns void language sql security definer set search_path = public as $$
  insert into stock_moves (move_date, item_id, qty_base, value_paise, kind, doc_no, purchase_id, journal_id, department_id,
                           created_by, is_demo, is_training)
  select p_date, p_item, coalesce(p_qty, 0), coalesce(p_value, 0), p_kind, p_doc, p_purchase, p_journal, p_dept, p_actor,
         p_demo, rb_is_training()
  where coalesce(p_qty, 0) <> 0 or coalesce(p_value, 0) <> 0
$$;

-- Recompute a purchase: line totals, differences, money owed and status.
create or replace function rb_pur_refresh(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_p purchases; l purchase_lines; v_net numeric; v_diff numeric; v_amt bigint; v_exp bigint;
        v_has_grn boolean; v_billed boolean; v_all boolean := true; v_any boolean := false;
begin
  select * into v_p from purchases where id = p_id for update;
  if v_p.id is null then return; end if;

  -- Receipts and returns, per line
  update purchase_lines pl set
    received_qty = coalesce((select sum(g.received_qty) from purchase_grn_lines g where g.purchase_line_id = pl.id), 0),
    rejected_qty = coalesce((select sum(g.rejected_qty) from purchase_grn_lines g where g.purchase_line_id = pl.id), 0),
    returned_qty = coalesce((select sum(r.qty) from purchase_return_lines r join purchase_returns h on h.id = r.return_id
                             where r.purchase_line_id = pl.id and h.from_stock), 0),
    returned_before_bill_qty = coalesce((select sum(r.qty) from purchase_return_lines r join purchase_returns h on h.id = r.return_id
                             where r.purchase_line_id = pl.id and h.from_stock and not h.after_bill), 0)
  where pl.purchase_id = p_id;

  v_has_grn := exists (select 1 from purchase_grns where purchase_id = p_id);
  v_billed := v_p.bill_posted_at is not null;

  -- Differences (not for direct purchases: there is no PO to compare with,
  -- and receive and bill are entered together).
  if not v_p.is_direct and v_p.status not in ('cancelled') then
    for l in select * from purchase_lines where purchase_id = p_id order by line_no loop
      if v_has_grn then
        -- Received against ordered
        v_diff := l.received_qty - coalesce(l.po_qty, 0);
        perform rb_pur_flag(p_id, l.id, 'receipt', case when v_diff < 0 then 'short' else 'excess' end,
          v_diff, rb_pur_amt(v_diff, l.grn_rate_paise),
          case when v_diff < 0 then 'Received ' || trim_scale(-v_diff)::text || ' ' || l.unit_code || ' less than ordered'
               else 'Received ' || trim_scale(v_diff)::text || ' ' || l.unit_code || ' more than ordered' end);
        -- clear the opposite kind
        perform rb_pur_flag(p_id, l.id, 'receipt', case when v_diff < 0 then 'excess' else 'short' end, 0, 0, '');
        -- Damaged or refused at the door
        perform rb_pur_flag(p_id, l.id, 'receipt', 'damaged', -l.rejected_qty, -rb_pur_amt(l.rejected_qty, l.grn_rate_paise),
          trim_scale(l.rejected_qty)::text || ' ' || l.unit_code || ' damaged or refused at delivery');
      end if;
      if v_billed then
        v_net := l.received_qty - l.rejected_qty - l.returned_before_bill_qty;
        v_diff := coalesce(l.bill_qty, 0) - v_net;   -- + = billed for more than we kept
        perform rb_pur_flag(p_id, l.id, 'bill', case when v_diff > 0 then 'short' else 'excess' end,
          v_diff, rb_pur_amt(v_diff, coalesce(l.bill_rate_paise, l.grn_rate_paise)),
          case when v_diff > 0 then 'Billed for ' || trim_scale(v_diff)::text || ' ' || l.unit_code || ' more than was received'
               else 'Billed for ' || trim_scale(-v_diff)::text || ' ' || l.unit_code || ' less than was received' end);
        perform rb_pur_flag(p_id, l.id, 'bill', case when v_diff > 0 then 'excess' else 'short' end, 0, 0, '');
        -- Rate against the PO
        v_amt := rb_pur_amt(l.bill_qty, coalesce(l.bill_rate_paise, 0) - coalesce(l.po_rate_paise, 0));
        perform rb_pur_flag(p_id, l.id, 'bill', 'rate',
          null, v_amt,
          'Bill rate ' || rb_pur_fmt(l.bill_rate_paise) || ' per ' || l.unit_code || ', PO rate ' || rb_pur_fmt(l.po_rate_paise));
        -- Tax against the PO's GST rate
        v_exp := round(coalesce(l.bill_taxable_paise, 0) * coalesce(l.gst_rate, 0) / 100.0)::bigint;
        perform rb_pur_flag(p_id, l.id, 'bill', 'tax', null, coalesce(l.bill_gst_paise, 0) - v_exp,
          'Bill GST ' || rb_pur_fmt(l.bill_gst_paise) || ', expected ' || rb_pur_fmt(v_exp) || ' at ' ||
          to_char(coalesce(l.gst_rate, 0), 'FM990.##') || '%');
      end if;
    end loop;
  end if;

  -- Status of receipt
  for l in select * from purchase_lines where purchase_id = p_id loop
    if l.received_qty > 0 then v_any := true; end if;
    if l.received_qty < coalesce(l.po_qty, 0) then v_all := false; end if;
  end loop;

  update purchases p set
    order_total_paise = coalesce((select sum(rb_pur_amt(po_qty, po_rate_paise)) from purchase_lines where purchase_id = p_id), 0),
    grn_value_paise = coalesce((select sum(value_paise) from purchase_grns where purchase_id = p_id), 0),
    bill_taxable_paise = case when v_billed then coalesce((select sum(bill_taxable_paise) from purchase_lines where purchase_id = p_id), 0) else 0 end,
    bill_gst_paise = case when v_billed then coalesce((select sum(bill_gst_paise) from purchase_lines where purchase_id = p_id), 0) else 0 end,
    notes_paise = coalesce((select sum(total_paise) from purchase_notes where purchase_id = p_id), 0)
                + coalesce((select sum(total_paise) from purchase_returns where purchase_id = p_id and after_bill), 0),
    paid_paise = coalesce((select sum(a.amount_paise) from payment_allocations a join supplier_payments s on s.id = a.payment_id
                           where a.purchase_id = p_id and s.status = 'posted'), 0),
    open_discrepancies = (select count(*) from purchase_discrepancies where purchase_id = p_id and status = 'open')
  where id = p_id;
  update purchases set
    bill_total_paise = bill_taxable_paise + bill_gst_paise,
    outstanding_paise = case when bill_posted_at is null or status in ('cancelled', 'refused') then 0
                             else bill_taxable_paise + bill_gst_paise - notes_paise - paid_paise end
  where id = p_id;
  update purchases set status = case
      when status in ('cancelled', 'refused', 'awaiting_approval') then status
      when bill_posted_at is not null and outstanding_paise <= 0 then 'paid'
      when bill_posted_at is not null then 'billed'
      when v_any and v_all then 'received'
      when v_any then 'part_received'
      else 'ordered' end
  where id = p_id;
end $$;

-- Record, update or clear one difference. Called only by rb_pur_refresh.
-- p_qty null and p_amount 0 = no difference. A difference already decided stays as decided.
create or replace function rb_pur_flag(p_purchase bigint, p_line bigint, p_stage text, p_kind text,
                                       p_qty numeric, p_amount bigint, p_explain text)
returns void language plpgsql security definer set search_path = public as $$
declare v_d purchase_discrepancies; v_differs boolean; v_p purchases;
begin
  v_differs := coalesce(p_qty, 0) <> 0 or coalesce(p_amount, 0) <> 0;
  select * into v_d from purchase_discrepancies where purchase_line_id = p_line and stage = p_stage and kind = p_kind;
  if v_d.id is not null and v_d.status <> 'open' then return; end if;
  if not v_differs then
    if v_d.id is not null then delete from purchase_discrepancies where id = v_d.id; end if;
    return;
  end if;
  select * into v_p from purchases where id = p_purchase;
  if v_d.id is null then
    insert into purchase_discrepancies (purchase_id, purchase_line_id, stage, kind, qty_diff, amount_paise, explain, is_demo, is_training)
    values (p_purchase, p_line, p_stage, p_kind, p_qty, p_amount, p_explain, v_p.is_demo, v_p.is_training);
  else
    update purchase_discrepancies set qty_diff = p_qty, amount_paise = p_amount, explain = p_explain where id = v_d.id;
  end if;
end $$;

-- Post the GRN journal for receipts: stock in at cost, against goods received not invoiced.
create or replace function rb_pur_post_grn(p_grn bigint, p_actor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_g purchase_grns; v_p purchases; v_lines jsonb := '[]'; r record; v_total bigint := 0; v_j bigint; v_sup text;
begin
  select * into v_g from purchase_grns where id = p_grn;
  select * into v_p from purchases where id = v_g.purchase_id;
  select name into v_sup from suppliers where id = v_p.supplier_id;
  for r in select gl.*, pl.item_id, pl.unit_code from purchase_grn_lines gl join purchase_lines pl on pl.id = gl.purchase_line_id
           where gl.grn_id = p_grn order by pl.line_no loop
    if r.value_paise > 0 then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'grn.' || rb_pur_stock_key(r.item_id),
        'amount_paise', r.value_paise, 'item_id', r.item_id, 'supplier_id', v_p.supplier_id,
        'narration', trim_scale(r.received_qty - r.rejected_qty)::text || ' ' || r.unit_code || ' received'));
      v_total := v_total + r.value_paise;
    end if;
  end loop;
  if v_total > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'grn.grni', 'amount_paise', v_total,
      'supplier_id', v_p.supplier_id));
    v_j := rb_post_engine(jsonb_build_object('journal_date', v_g.grn_date, 'source', 'purchases', 'event_code', 'grn',
      'source_ref', v_g.grn_no, 'narration', 'Goods received ' || v_g.grn_no || ' from ' || v_sup || coalesce(' (' || v_p.po_no || ')', ''),
      'department_id', v_p.department_id, 'is_demo', v_p.is_demo, 'entered_by', p_actor, 'approved_by', p_actor), v_lines);
  end if;
  update purchase_grns set value_paise = v_total, journal_id = v_j where id = p_grn;
  for r in select gl.*, pl.item_id, pl.unit_code from purchase_grn_lines gl join purchase_lines pl on pl.id = gl.purchase_line_id
           where gl.grn_id = p_grn loop
    perform rb_pur_stock(v_g.grn_date, r.item_id, rb_pur_base_qty(r.item_id, r.unit_code, r.received_qty - r.rejected_qty),
      r.value_paise, 'grn', v_g.grn_no, v_p.id, v_j, v_p.department_id, p_actor, v_p.is_demo);
  end loop;
end $$;

-- Post the supplier's bill: clear goods received not invoiced, move any
-- difference into stock cost, input GST (if registered), raise the supplier balance.
create or replace function rb_pur_post_bill(p_id bigint, p_actor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_p purchases; l record; v_lines jsonb := '[]'; v_grni bigint; v_var bigint; v_gst_total bigint := 0;
        v_total bigint := 0; v_j bigint; v_claim boolean := rb_pur_gst_claimable(); v_sup text; v_key text;
        v_grni_total bigint := 0;
begin
  select * into v_p from purchases where id = p_id;
  select name into v_sup from suppliers where id = v_p.supplier_id;
  for l in select pl.*,
             coalesce((select sum(value_paise) from purchase_grn_lines g where g.purchase_line_id = pl.id), 0)
             - coalesce((select sum(r.value_paise) from purchase_return_lines r join purchase_returns h on h.id = r.return_id
                         where r.purchase_line_id = pl.id and h.from_stock and not h.after_bill), 0) as grni_value
           from purchase_lines pl where pl.purchase_id = p_id order by pl.line_no loop
    v_key := rb_pur_stock_key(l.item_id);
    v_grni := l.grni_value;
    v_var := coalesce(l.bill_taxable_paise, 0) - v_grni + case when v_claim then 0 else coalesce(l.bill_gst_paise, 0) end;
    v_grni_total := v_grni_total + v_grni;
    if v_var <> 0 then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object(
        'rule', case when v_key = 'stock_packaging' then 'grn.packaging_variance' else 'grn.stock_variance' end, 'amount_paise', v_var, 'item_id', l.item_id, 'supplier_id', v_p.supplier_id,
        'narration', 'Bill differs from GRN value' || case when not v_claim and coalesce(l.bill_gst_paise, 0) > 0 then ' (GST added to cost: not registered)' else '' end));
      perform rb_pur_stock(v_p.bill_date, l.item_id, 0, v_var, 'bill_adjust', v_p.bill_no, p_id, null,
        v_p.department_id, p_actor, v_p.is_demo);
    end if;
    if v_claim then v_gst_total := v_gst_total + coalesce(l.bill_gst_paise, 0); end if;
    v_total := v_total + coalesce(l.bill_taxable_paise, 0) + coalesce(l.bill_gst_paise, 0);
  end loop;
  if v_grni_total <> 0 then
    v_lines := jsonb_build_array(jsonb_build_object('rule', 'supplier_bill.grni', 'amount_paise', v_grni_total,
      'supplier_id', v_p.supplier_id)) || v_lines;
  end if;
  if v_gst_total > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'supplier_bill.input_gst', 'amount_paise', v_gst_total));
  end if;
  if v_total > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'supplier_bill.payable', 'amount_paise', v_total,
      'supplier_id', v_p.supplier_id));
  end if;
  if jsonb_array_length(v_lines) >= 2 then
    v_j := rb_post_engine(jsonb_build_object('journal_date', v_p.bill_date, 'source', 'purchases', 'event_code', 'supplier_bill',
      'source_ref', v_p.bill_no, 'narration', 'Supplier bill ' || v_p.bill_no || ' from ' || v_sup || coalesce(' (' || v_p.po_no || ')', ''),
      'department_id', v_p.department_id, 'is_demo', v_p.is_demo, 'entered_by', p_actor, 'approved_by', p_actor), v_lines);
    update stock_moves set journal_id = v_j where purchase_id = p_id and kind = 'bill_adjust' and journal_id is null;
  end if;
  update purchases set bill_journal_id = v_j, bill_posted_at = now() where id = p_id;
end $$;

-- A payment, with its allocations. Private: callers check rights first.
create or replace function rb_pur_pay(p jsonb, p_actor uuid, p_demo boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_sup int := rb_int(p, 'supplier_id'); v_date date := (p->>'pay_date')::date;
        v_mode text := coalesce(rb_txt(p, 'mode'), 'cash'); v_amt bigint := rb_int(p, 'amount_paise');
        a jsonb; v_pur purchases; v_alloc bigint := 0; v_no text; v_j bigint; v_sup_name text; v_dept int;
begin
  if v_sup is null then raise exception 'Please choose the supplier.'; end if;
  select name into v_sup_name from suppliers where id = v_sup;
  if v_sup_name is null then raise exception 'Supplier not found.'; end if;
  if v_date is null then raise exception 'Please choose the payment date.'; end if;
  if v_mode not in ('cash', 'upi', 'bank') then raise exception 'Choose how it was paid: cash, UPI or bank.'; end if;
  if coalesce(v_amt, 0) <= 0 then raise exception 'Please enter the amount paid.'; end if;
  perform rb_assert_period_open(v_date);
  v_dept := coalesce(rb_int(p, 'department_id')::int, rb_pur_default_dept());
  v_no := rb_next_doc_no(rb_pur_series('PAY', p_demo), v_date);
  insert into supplier_payments (payment_no, supplier_id, pay_date, mode, amount_paise, reference, note, department_id,
                                 entered_by, is_demo, is_training)
  values (v_no, v_sup, v_date, v_mode, v_amt, rb_txt(p, 'reference'), rb_txt(p, 'note'), v_dept, p_actor, p_demo, rb_is_training())
  returning id into v_id;
  for a in select * from jsonb_array_elements(coalesce(p->'allocations', '[]')) loop
    if coalesce(rb_int(a, 'amount_paise'), 0) = 0 then continue; end if;
    select * into v_pur from purchases where id = rb_int(a, 'purchase_id') for update;
    if v_pur.id is null or v_pur.supplier_id <> v_sup then raise exception 'That purchase is not from this supplier.'; end if;
    if v_pur.bill_posted_at is null then
      raise exception '% has no supplier bill yet, so it cannot be paid.', rb_pur_label(v_pur);
    end if;
    if v_pur.open_discrepancies > 0 then
      raise exception '% has % difference(s) to settle first (spec: a purchase with an unsettled difference cannot be paid).',
        rb_pur_label(v_pur), v_pur.open_discrepancies;
    end if;
    if rb_int(a, 'amount_paise') < 0 then raise exception 'Amounts cannot be negative.'; end if;
    if rb_int(a, 'amount_paise') > v_pur.outstanding_paise then
      raise exception '% only has % left to pay.', rb_pur_label(v_pur), rb_pur_fmt(v_pur.outstanding_paise);
    end if;
    insert into payment_allocations (payment_id, purchase_id, amount_paise, is_demo, is_training)
    values (v_id, v_pur.id, rb_int(a, 'amount_paise'), p_demo, rb_is_training());
    v_alloc := v_alloc + rb_int(a, 'amount_paise');
    perform rb_pur_refresh(v_pur.id);
  end loop;
  if v_alloc > v_amt then raise exception 'The amounts set against purchases (%) are more than the payment (%).', rb_pur_fmt(v_alloc), rb_pur_fmt(v_amt); end if;
  v_j := rb_post_engine(jsonb_build_object('journal_date', v_date, 'source', 'purchases', 'event_code', 'supplier_payment',
    'source_ref', v_no, 'narration', 'Paid ' || v_sup_name || ' by ' || upper(v_mode) || coalesce(', ref ' || rb_txt(p, 'reference'), '') ||
      case when v_alloc < v_amt then ' (' || rb_pur_fmt(v_amt - v_alloc) || ' on account)' else '' end,
    'department_id', v_dept, 'is_demo', p_demo, 'entered_by', p_actor, 'approved_by', p_actor),
    jsonb_build_array(
      jsonb_build_object('rule', 'supplier_payment.payable', 'amount_paise', v_amt, 'supplier_id', v_sup),
      jsonb_build_object('rule', 'supplier_payment.' || case when v_mode = 'cash' then 'cash' else 'bank' end, 'amount_paise', v_amt)));
  update supplier_payments set journal_id = v_j where id = v_id;
  perform rb_audit_write('SUPPLIER_PAYMENT', 'supplier_payments', v_id::text, null,
    jsonb_build_object('payment_no', v_no, 'supplier', v_sup_name, 'amount_paise', v_amt, 'mode', v_mode, 'allocated_paise', v_alloc), null);
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- 5. Purchase orders, receipts and bills (private versions take the actor,
--    so the DEMO data below can use them; the screens call the rb_ ones)
-- ---------------------------------------------------------------------

-- Save a new order or change one that has not been received yet.
-- p: id, supplier_id, po_date, expected_date, department_id, note,
--    lines [{item_id, unit_code, qty, rate_paise, gst_rate}]
create or replace function rb_pur_save_order(p jsonb, p_actor uuid, p_demo boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint := rb_int(p, 'id'); v_p purchases; v_date date := (p->>'po_date')::date; l jsonb; i int := 0;
        v_item items; v_dept int := coalesce(rb_int(p, 'department_id')::int, rb_pur_default_dept()); v_qty numeric;
begin
  if rb_int(p, 'supplier_id') is null then raise exception 'Please choose the supplier (or add a new one).'; end if;
  if not exists (select 1 from suppliers where id = rb_int(p, 'supplier_id') and is_active) then
    raise exception 'That supplier is switched off. Switch them on in Suppliers first.';
  end if;
  if v_date is null then raise exception 'Please choose the order date.'; end if;
  if jsonb_array_length(coalesce(p->'lines', '[]')) = 0 then raise exception 'Add at least one item to the order.'; end if;
  if v_id is null then
    insert into purchases (supplier_id, department_id, po_no, po_date, expected_date, status, note, payment_mode,
                           entered_by, is_demo, is_training, entity_code, currency)
    select rb_int(p, 'supplier_id'), v_dept, rb_next_doc_no(rb_pur_series('PO', p_demo), v_date), v_date,
           (p->>'expected_date')::date, 'ordered', rb_txt(p, 'note'), 'credit', p_actor, p_demo, rb_is_training(),
           s.entity_code, s.currency
    from app_settings s where s.id = 1
    returning id into v_id;
  else
    select * into v_p from purchases where id = v_id for update;
    if v_p.id is null then raise exception 'Purchase not found.'; end if;
    if v_p.is_direct then raise exception 'This is a direct purchase: it has no order to change.'; end if;
    if v_p.status <> 'ordered' or exists (select 1 from purchase_grns where purchase_id = v_id) then
      raise exception 'Goods have already been received against %, so the order can no longer be changed.', v_p.po_no;
    end if;
    update purchases set supplier_id = rb_int(p, 'supplier_id'), department_id = v_dept, po_date = v_date,
      expected_date = (p->>'expected_date')::date, note = rb_txt(p, 'note'), updated_at = now(), updated_by = p_actor
    where id = v_id;
    delete from purchase_lines where purchase_id = v_id;
  end if;
  for l in select * from jsonb_array_elements(p->'lines') loop
    if rb_int(l, 'item_id') is null and coalesce(rb_txt(l, 'qty'), '') = '' then continue; end if;
    i := i + 1;
    select * into v_item from items where id = rb_int(l, 'item_id');
    if v_item.id is null then raise exception 'Line %: please choose the item.', i; end if;
    perform rb_pur_stock_key(v_item.id);
    v_qty := (l->>'qty')::numeric;
    if coalesce(v_qty, 0) <= 0 then raise exception 'Line % (%): enter the quantity ordered.', i, v_item.name; end if;
    if rb_int(l, 'rate_paise') is null or rb_int(l, 'rate_paise') < 0 then raise exception 'Line % (%): enter the agreed rate.', i, v_item.name; end if;
    perform rb_pur_base_qty(v_item.id, coalesce(rb_txt(l, 'unit_code'), rb_pur_default_unit(v_item.id)), 1);
    insert into purchase_lines (purchase_id, line_no, item_id, unit_code, po_qty, po_rate_paise, gst_rate, grn_rate_paise,
                                is_demo, is_training)
    values (v_id, i, v_item.id, coalesce(rb_txt(l, 'unit_code'), rb_pur_default_unit(v_item.id)), v_qty, rb_int(l, 'rate_paise'),
            coalesce((l->>'gst_rate')::numeric, v_item.gst_rate, 0), rb_int(l, 'rate_paise'), p_demo, rb_is_training());
  end loop;
  if i = 0 then raise exception 'Add at least one item to the order.'; end if;
  perform rb_pur_refresh(v_id);
  select * into v_p from purchases where id = v_id;
  perform rb_audit_write('SAVE_ORDER', 'purchases', v_id::text, null,
    jsonb_build_object('po_no', v_p.po_no, 'supplier_id', v_p.supplier_id, 'total_paise', v_p.order_total_paise), null);
  return v_id;
end $$;

-- Receive goods (GRN) against an order.
-- p: purchase_id, grn_date, note, lines [{line_id, received_qty, rejected_qty, reject_reason}]
create or replace function rb_pur_receive(p jsonb, p_actor uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_p purchases; v_date date := (p->>'grn_date')::date; v_g bigint; l jsonb; v_l purchase_lines; v_rec numeric; v_rej numeric;
        v_n int := 0; v_no text;
begin
  select * into v_p from purchases where id = rb_int(p, 'purchase_id') for update;
  if v_p.id is null then raise exception 'Purchase not found.'; end if;
  if v_p.is_direct then raise exception 'A direct purchase is received when it is entered.'; end if;
  if v_p.status in ('cancelled', 'refused') then raise exception 'This purchase is cancelled.'; end if;
  if v_p.bill_posted_at is not null then raise exception 'The bill is already entered. Enter a new order for further goods.'; end if;
  if v_date is null then raise exception 'Please choose the date the goods came in.'; end if;
  if v_date < v_p.po_date then raise exception 'Goods cannot be received before the order date (%).', to_char(v_p.po_date, 'DD-Mon-YYYY'); end if;
  perform rb_assert_period_open(v_date);
  v_no := rb_next_doc_no(rb_pur_series('GRN', v_p.is_demo), v_date);
  insert into purchase_grns (purchase_id, grn_no, grn_date, note, entered_by, is_demo, is_training)
  values (v_p.id, v_no, v_date, rb_txt(p, 'note'), p_actor, v_p.is_demo, rb_is_training()) returning id into v_g;
  for l in select * from jsonb_array_elements(coalesce(p->'lines', '[]')) loop
    v_rec := coalesce(nullif(trim(l->>'received_qty'), '')::numeric, 0);
    v_rej := coalesce(nullif(trim(l->>'rejected_qty'), '')::numeric, 0);
    if v_rec = 0 and v_rej = 0 then continue; end if;
    select * into v_l from purchase_lines where id = rb_int(l, 'line_id') and purchase_id = v_p.id;
    if v_l.id is null then raise exception 'That line is not on this order.'; end if;
    if v_rec < 0 or v_rej < 0 then raise exception 'Line %: quantities cannot be negative.', v_l.line_no; end if;
    if v_rej > v_rec then raise exception 'Line %: damaged or refused cannot be more than received.', v_l.line_no; end if;
    if v_rej > 0 and rb_txt(l, 'reject_reason') is null then
      raise exception 'Line %: say why goods were refused (e.g. damaged, spoilt).', v_l.line_no;
    end if;
    insert into purchase_grn_lines (grn_id, purchase_line_id, received_qty, rejected_qty, reject_reason, rate_paise, value_paise,
                                    is_demo, is_training)
    values (v_g, v_l.id, v_rec, v_rej, rb_txt(l, 'reject_reason'), v_l.grn_rate_paise, rb_pur_amt(v_rec - v_rej, v_l.grn_rate_paise),
            v_p.is_demo, rb_is_training());
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then raise exception 'Enter the quantity received for at least one line.'; end if;
  perform rb_pur_post_grn(v_g, p_actor);
  perform rb_pur_refresh(v_p.id);
  perform rb_audit_write('RECEIVE_GOODS', 'purchase_grns', v_g::text, null,
    jsonb_build_object('grn_no', v_no, 'po_no', v_p.po_no, 'value_paise', (select value_paise from purchase_grns where id = v_g)), null);
  return v_g;
end $$;

-- Enter the supplier's bill against an order that has been received.
-- p: purchase_id, bill_no, bill_date, payment_mode, reference, lines [{line_id, qty, rate_paise, gst_paise}]
create or replace function rb_pur_bill(p jsonb, p_actor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_p purchases; v_date date := (p->>'bill_date')::date; l jsonb; v_l purchase_lines; v_mode text := coalesce(rb_txt(p, 'payment_mode'), 'credit');
        v_qty numeric; v_rate bigint; v_gst bigint;
begin
  select * into v_p from purchases where id = rb_int(p, 'purchase_id') for update;
  if v_p.id is null then raise exception 'Purchase not found.'; end if;
  if v_p.is_direct then raise exception 'A direct purchase takes its bill when it is entered.'; end if;
  if v_p.status in ('cancelled', 'refused') then raise exception 'This purchase is cancelled.'; end if;
  if v_p.bill_posted_at is not null then raise exception 'The bill for % is already entered.', v_p.po_no; end if;
  if not exists (select 1 from purchase_grns where purchase_id = v_p.id) then
    raise exception 'Receive the goods (GRN) first. Stock is added at GRN, and the bill is matched against it.';
  end if;
  if rb_txt(p, 'bill_no') is null then raise exception 'Enter the supplier''s bill number.'; end if;
  if v_date is null then raise exception 'Enter the bill date.'; end if;
  if v_mode not in ('credit', 'cash', 'upi', 'bank') then raise exception 'Choose the payment: credit, cash, UPI or bank.'; end if;
  if exists (select 1 from purchases where supplier_id = v_p.supplier_id and id <> v_p.id and status <> 'cancelled'
             and lower(bill_no) = lower(rb_txt(p, 'bill_no')) and not no_supplier_bill) then
    raise exception 'Bill % from this supplier is already entered on another purchase.', rb_txt(p, 'bill_no');
  end if;
  perform rb_assert_period_open(v_date);
  for l in select * from jsonb_array_elements(coalesce(p->'lines', '[]')) loop
    select * into v_l from purchase_lines where id = rb_int(l, 'line_id') and purchase_id = v_p.id;
    if v_l.id is null then raise exception 'That line is not on this purchase.'; end if;
    v_qty := coalesce(nullif(trim(l->>'qty'), '')::numeric, 0);
    v_rate := coalesce(rb_int(l, 'rate_paise'), 0);
    v_gst := coalesce(rb_int(l, 'gst_paise'), 0);
    if v_qty < 0 or v_rate < 0 or v_gst < 0 then raise exception 'Line %: amounts cannot be negative.', v_l.line_no; end if;
    update purchase_lines set bill_qty = v_qty, bill_rate_paise = v_rate, bill_taxable_paise = rb_pur_amt(v_qty, v_rate),
      bill_gst_paise = v_gst, agreed_qty = v_qty, agreed_rate_paise = v_rate where id = v_l.id;
  end loop;
  if exists (select 1 from purchase_lines where purchase_id = v_p.id and bill_qty is null) then
    raise exception 'Enter the billed quantity for every line (0 if it is not on the bill).';
  end if;
  update purchases set bill_no = rb_txt(p, 'bill_no'), bill_date = v_date, payment_mode = v_mode, updated_at = now(), updated_by = p_actor
  where id = v_p.id;
  perform rb_pur_post_bill(v_p.id, p_actor);
  perform rb_pur_refresh(v_p.id);
  select * into v_p from purchases where id = v_p.id;
  perform rb_audit_write('SUPPLIER_BILL', 'purchases', v_p.id::text, null,
    jsonb_build_object('po_no', v_p.po_no, 'bill_no', v_p.bill_no, 'total_paise', v_p.bill_total_paise,
                       'open_differences', v_p.open_discrepancies), null);
  if v_mode <> 'credit' then
    if v_p.open_discrepancies > 0 then
      raise exception 'This bill has % difference(s) with the order or the goods received. Save it as Credit, settle the differences, then pay it.',
        v_p.open_discrepancies;
    end if;
    perform rb_pur_pay(jsonb_build_object('supplier_id', v_p.supplier_id, 'pay_date', v_date, 'mode', v_mode,
      'amount_paise', v_p.outstanding_paise, 'reference', rb_txt(p, 'reference'), 'department_id', v_p.department_id,
      'allocations', jsonb_build_array(jsonb_build_object('purchase_id', v_p.id, 'amount_paise', v_p.outstanding_paise))),
      p_actor, v_p.is_demo);
  end if;
end $$;

-- Post a direct purchase: goods in and the bill in one journal, then the payment if paid now.
create or replace function rb_pur_post_direct(p_id bigint, p_actor uuid, p_approver uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_p purchases; v_g purchase_grns; l purchase_lines; v_lines jsonb := '[]'; v_claim boolean := rb_pur_gst_claimable();
        v_gst bigint := 0; v_total bigint := 0; v_val bigint; v_j bigint; v_sup text;
begin
  select * into v_p from purchases where id = p_id for update;
  select * into v_g from purchase_grns where purchase_id = p_id order by id limit 1;
  select name into v_sup from suppliers where id = v_p.supplier_id;
  perform rb_assert_period_open(v_p.purchase_date);
  for l in select * from purchase_lines where purchase_id = p_id order by line_no loop
    v_val := l.bill_taxable_paise + case when v_claim then 0 else coalesce(l.bill_gst_paise, 0) end;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'direct_purchase.' || rb_pur_stock_key(l.item_id),
      'amount_paise', v_val, 'item_id', l.item_id, 'supplier_id', v_p.supplier_id,
      'narration', trim_scale(l.received_qty)::text || ' ' || l.unit_code || ' at ' || rb_pur_fmt(l.bill_rate_paise)));
    if v_claim then v_gst := v_gst + coalesce(l.bill_gst_paise, 0); end if;
    v_total := v_total + l.bill_taxable_paise + coalesce(l.bill_gst_paise, 0);
  end loop;
  if v_gst > 0 then v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'direct_purchase.input_gst', 'amount_paise', v_gst)); end if;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'direct_purchase.payable', 'amount_paise', v_total,
    'supplier_id', v_p.supplier_id));
  v_j := rb_post_engine(jsonb_build_object('journal_date', v_p.purchase_date, 'source', 'purchases', 'event_code', 'direct_purchase',
    'source_ref', v_g.grn_no, 'narration', 'Direct purchase ' || v_g.grn_no || ' from ' || v_sup || ': ' || v_p.reason ||
      case when v_p.no_supplier_bill then ' (no supplier bill)' else ', bill ' || v_p.bill_no end,
    'department_id', v_p.department_id, 'is_demo', v_p.is_demo, 'entered_by', v_p.entered_by, 'approved_by', p_approver), v_lines);
  update purchase_grns set journal_id = v_j, value_paise = v_total - v_gst where id = v_g.id;
  update purchase_grn_lines gl set value_paise = l2.bill_taxable_paise + case when v_claim then 0 else coalesce(l2.bill_gst_paise, 0) end
  from purchase_lines l2 where l2.id = gl.purchase_line_id and gl.grn_id = v_g.id;
  for l in select * from purchase_lines where purchase_id = p_id loop
    perform rb_pur_stock(v_p.purchase_date, l.item_id, rb_pur_base_qty(l.item_id, l.unit_code, l.received_qty),
      l.bill_taxable_paise + case when v_claim then 0 else coalesce(l.bill_gst_paise, 0) end,
      'grn', v_g.grn_no, p_id, v_j, v_p.department_id, p_actor, v_p.is_demo);
  end loop;
  update purchases set bill_journal_id = v_j, bill_posted_at = now(), status = 'billed',
    approved_by = p_approver, approved_at = case when approval_needed then now() end
  where id = p_id;
  perform rb_pur_refresh(p_id);
  select * into v_p from purchases where id = p_id;
  if v_p.payment_mode <> 'credit' then
    perform rb_pur_pay(jsonb_build_object('supplier_id', v_p.supplier_id, 'pay_date', v_p.purchase_date, 'mode', v_p.payment_mode,
      'amount_paise', v_p.outstanding_paise, 'department_id', v_p.department_id, 'note', 'Paid with direct purchase ' || v_g.grn_no,
      'allocations', jsonb_build_array(jsonb_build_object('purchase_id', p_id, 'amount_paise', v_p.outstanding_paise))),
      v_p.entered_by, v_p.is_demo);
  end if;
end $$;

-- Save a direct purchase (no PO). Posts at once, or waits for approval
-- when it is above the Settings limit.
-- p: id (to change one awaiting approval), supplier_id, purchase_date, department_id, reason,
--    payment_mode, no_supplier_bill, bill_no, bill_date, note, photo (data URL),
--    lines [{item_id, unit_code, qty, rate_paise, gst_paise}]
create or replace function rb_pur_save_direct(p jsonb, p_actor uuid, p_demo boolean, p_can_self_approve boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint := rb_int(p, 'id'); v_p purchases; v_date date := (p->>'purchase_date')::date; l jsonb; i int := 0;
        v_item items; v_qty numeric; v_rate bigint; v_gst bigint; v_total bigint := 0; v_limit bigint;
        v_nobill boolean := coalesce((p->>'no_supplier_bill')::boolean, false); v_mode text := coalesce(rb_txt(p, 'payment_mode'), 'cash');
        v_grn bigint; v_grn_no text; v_unit text; v_needs boolean; v_lid bigint;
        v_dept int := coalesce(rb_int(p, 'department_id')::int, rb_pur_default_dept());
begin
  if rb_int(p, 'supplier_id') is null then raise exception 'Please choose the supplier (or add a new one).'; end if;
  if not exists (select 1 from suppliers where id = rb_int(p, 'supplier_id') and is_active) then
    raise exception 'That supplier is switched off. Switch them on in Suppliers first.';
  end if;
  if v_date is null then raise exception 'Please choose the date of the purchase.'; end if;
  if rb_txt(p, 'reason') is null then raise exception 'Please give the reason there is no order (e.g. daily fish catch, urgent).'; end if;
  if v_mode not in ('credit', 'cash', 'upi', 'bank') then raise exception 'Choose the payment: cash, UPI, bank or credit.'; end if;
  if not v_nobill and rb_txt(p, 'bill_no') is null then
    raise exception 'Enter the supplier''s bill number, or tick "No supplier bill".';
  end if;
  if v_nobill and rb_txt(p, 'note') is null and rb_txt(p, 'photo') is null
     and (v_id is null or not exists (select 1 from purchase_photos where purchase_id = v_id)) then
    raise exception 'With no supplier bill, add a photo (catch or weighing slip) or a note.';
  end if;
  perform rb_assert_period_open(v_date);
  if v_id is null then
    insert into purchases (supplier_id, department_id, is_direct, purchase_date, reason, no_supplier_bill, bill_no, bill_date,
                           payment_mode, note, status, entered_by, is_demo, is_training, entity_code, currency)
    select rb_int(p, 'supplier_id'), v_dept, true, v_date, rb_txt(p, 'reason'), v_nobill, rb_txt(p, 'bill_no'),
           coalesce((p->>'bill_date')::date, v_date), v_mode, rb_txt(p, 'note'), 'awaiting_approval', p_actor, p_demo,
           rb_is_training(), s.entity_code, s.currency
    from app_settings s where s.id = 1
    returning id into v_id;
    v_grn_no := rb_next_doc_no(rb_pur_series('GRN', p_demo), v_date);
    insert into purchase_grns (purchase_id, grn_no, grn_date, note, entered_by, is_demo, is_training)
    values (v_id, v_grn_no, v_date, 'Direct purchase', p_actor, p_demo, rb_is_training()) returning id into v_grn;
  else
    select * into v_p from purchases where id = v_id for update;
    if v_p.id is null or not v_p.is_direct then raise exception 'Direct purchase not found.'; end if;
    if v_p.status <> 'awaiting_approval' then raise exception 'This direct purchase is already posted. Reverse it to correct it.'; end if;
    select id, grn_no into v_grn, v_grn_no from purchase_grns where purchase_id = v_id order by id limit 1;
    update purchases set supplier_id = rb_int(p, 'supplier_id'), department_id = v_dept, purchase_date = v_date,
      reason = rb_txt(p, 'reason'), no_supplier_bill = v_nobill, bill_no = rb_txt(p, 'bill_no'),
      bill_date = coalesce((p->>'bill_date')::date, v_date), payment_mode = v_mode, note = rb_txt(p, 'note'),
      updated_at = now(), updated_by = p_actor
    where id = v_id;
    update purchase_grns set grn_date = v_date where id = v_grn;
    delete from purchase_lines where purchase_id = v_id;
  end if;
  if v_nobill then update purchases set bill_no = v_grn_no, bill_date = v_date where id = v_id; end if;
  for l in select * from jsonb_array_elements(coalesce(p->'lines', '[]')) loop
    if rb_int(l, 'item_id') is null and coalesce(rb_txt(l, 'qty'), '') = '' then continue; end if;
    i := i + 1;
    select * into v_item from items where id = rb_int(l, 'item_id');
    if v_item.id is null then raise exception 'Line %: please choose the item.', i; end if;
    perform rb_pur_stock_key(v_item.id);
    v_unit := coalesce(rb_txt(l, 'unit_code'), rb_pur_default_unit(v_item.id));
    perform rb_pur_base_qty(v_item.id, v_unit, 1);
    v_qty := nullif(trim(l->>'qty'), '')::numeric; v_rate := rb_int(l, 'rate_paise'); v_gst := coalesce(rb_int(l, 'gst_paise'), 0);
    if coalesce(v_qty, 0) <= 0 then raise exception 'Line % (%): enter the quantity or weight.', i, v_item.name; end if;
    if v_rate is null or v_rate < 0 then raise exception 'Line % (%): enter the rate.', i, v_item.name; end if;
    if v_gst < 0 then raise exception 'Line %: GST cannot be negative.', i; end if;
    if v_nobill and v_gst > 0 then raise exception 'Line %: with no supplier bill there is no GST to claim.', i; end if;
    insert into purchase_lines (purchase_id, line_no, item_id, unit_code, grn_rate_paise, received_qty, bill_qty, bill_rate_paise,
                                bill_taxable_paise, bill_gst_paise, agreed_qty, agreed_rate_paise, gst_rate, is_demo, is_training)
    values (v_id, i, v_item.id, v_unit, v_rate, v_qty, v_qty, v_rate, rb_pur_amt(v_qty, v_rate), v_gst, v_qty, v_rate,
            case when rb_pur_amt(v_qty, v_rate) > 0 then round(v_gst * 100.0 / rb_pur_amt(v_qty, v_rate), 2) else 0 end,
            p_demo, rb_is_training())
    returning id into v_lid;
    insert into purchase_grn_lines (grn_id, purchase_line_id, received_qty, rejected_qty, rate_paise, value_paise, is_demo, is_training)
    values (v_grn, v_lid, v_qty, 0, v_rate, rb_pur_amt(v_qty, v_rate), p_demo, rb_is_training());
    v_total := v_total + rb_pur_amt(v_qty, v_rate) + v_gst;
  end loop;
  if i = 0 then raise exception 'Add at least one item.'; end if;
  if rb_txt(p, 'photo') is not null then
    insert into purchase_photos (purchase_id, data_url, caption, added_by, is_demo, is_training)
    values (v_id, p->>'photo', case when v_nobill then 'Catch or weighing slip' else 'Bill' end, p_actor, p_demo, rb_is_training());
  end if;
  select direct_purchase_approval_limit_paise into v_limit from app_settings where id = 1;
  v_needs := (v_limit is not null and v_total > v_limit) or coalesce((p->>'ask_approval')::boolean, false);
  update purchases set approval_needed = v_needs where id = v_id;
  perform rb_audit_write('DIRECT_PURCHASE', 'purchases', v_id::text, null,
    jsonb_build_object('grn_no', v_grn_no, 'total_paise', v_total, 'reason', rb_txt(p, 'reason'), 'no_bill', v_nobill,
                       'needs_approval', v_needs), null);
  if not v_needs or p_can_self_approve then
    update purchases set status = 'received' where id = v_id;
    perform rb_pur_post_direct(v_id, p_actor, p_actor);
  else
    perform rb_pur_refresh(v_id);
  end if;
  return v_id;
end $$;

-- Raise a debit note to the supplier (reduces what is owed).
create or replace function rb_pur_debit_note(p_purchase bigint, p_line bigint, p_disc bigint, p_date date,
                                             p_taxable bigint, p_gst bigint, p_reason text, p_actor uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_p purchases; v_l purchase_lines; v_no text; v_id bigint; v_j bigint; v_claim boolean := rb_pur_gst_claimable();
        v_stock bigint; v_lines jsonb; v_sup text;
begin
  select * into v_p from purchases where id = p_purchase;
  select * into v_l from purchase_lines where id = p_line;
  select name into v_sup from suppliers where id = v_p.supplier_id;
  if coalesce(p_taxable, 0) + coalesce(p_gst, 0) <= 0 then raise exception 'There is nothing to claim back from the supplier here.'; end if;
  perform rb_assert_period_open(p_date);
  v_no := rb_next_doc_no(rb_pur_series('DN', v_p.is_demo), p_date);
  insert into purchase_notes (purchase_id, purchase_line_id, discrepancy_id, note_no, note_date, taxable_paise, gst_paise, total_paise,
                              reason, entered_by, is_demo, is_training)
  values (p_purchase, p_line, p_disc, v_no, p_date, coalesce(p_taxable, 0), coalesce(p_gst, 0), coalesce(p_taxable, 0) + coalesce(p_gst, 0),
          p_reason, p_actor, v_p.is_demo, rb_is_training())
  returning id into v_id;
  v_stock := coalesce(p_taxable, 0) + case when v_claim then 0 else coalesce(p_gst, 0) end;
  v_lines := jsonb_build_array(jsonb_build_object('rule', 'debit_note.payable', 'amount_paise', coalesce(p_taxable, 0) + coalesce(p_gst, 0),
    'supplier_id', v_p.supplier_id));
  if v_stock > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'purchase_return.' || rb_pur_stock_key(v_l.item_id),
      'amount_paise', v_stock, 'item_id', v_l.item_id, 'supplier_id', v_p.supplier_id, 'narration', 'Lower stock cost'));
  end if;
  if v_claim and coalesce(p_gst, 0) > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'debit_note.input_gst', 'amount_paise', p_gst));
  end if;
  v_j := rb_post_engine(jsonb_build_object('journal_date', p_date, 'source', 'purchases', 'event_code', 'debit_note',
    'source_ref', v_no, 'narration', 'Debit note ' || v_no || ' to ' || v_sup || ' on bill ' || v_p.bill_no || ': ' || p_reason,
    'department_id', v_p.department_id, 'is_demo', v_p.is_demo, 'entered_by', p_actor, 'approved_by', p_actor), v_lines);
  update purchase_notes set journal_id = v_j where id = v_id;
  perform rb_pur_stock(p_date, v_l.item_id, 0, -v_stock, 'debit_note', v_no, p_purchase, v_j, v_p.department_id, p_actor, v_p.is_demo);
  return v_id;
end $$;

-- Send goods back. p: purchase_id, return_date, reason, from_stock, lines [{line_id, qty}]
create or replace function rb_pur_return(p jsonb, p_actor uuid, p_disc bigint)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_p purchases; v_date date := (p->>'return_date')::date; v_id bigint; v_no text; l jsonb; v_l purchase_lines;
        v_qty numeric; v_rate bigint; v_val bigint; v_gst bigint; v_after boolean; v_from boolean := coalesce((p->>'from_stock')::boolean, true);
        v_claim boolean := rb_pur_gst_claimable(); v_lines jsonb := '[]'; v_tax bigint := 0; v_gst_t bigint := 0; v_stock_t bigint := 0;
        v_j bigint; v_sup text; v_n int := 0; r record;
begin
  select * into v_p from purchases where id = rb_int(p, 'purchase_id') for update;
  if v_p.id is null then raise exception 'Purchase not found.'; end if;
  if v_p.status in ('cancelled', 'refused', 'awaiting_approval') then raise exception 'Only a posted purchase can have a return.'; end if;
  if rb_txt(p, 'reason') is null then raise exception 'Please give the reason for the return.'; end if;
  if v_date is null then raise exception 'Please choose the return date.'; end if;
  perform rb_assert_period_open(v_date);
  select name into v_sup from suppliers where id = v_p.supplier_id;
  v_after := v_p.bill_posted_at is not null;
  v_no := rb_next_doc_no(rb_pur_series('PRN', v_p.is_demo), v_date);
  insert into purchase_returns (purchase_id, discrepancy_id, return_no, return_date, reason, from_stock, after_bill, entered_by, is_demo, is_training)
  values (v_p.id, p_disc, v_no, v_date, rb_txt(p, 'reason'), v_from, v_after and v_from, p_actor, v_p.is_demo, rb_is_training())
  returning id into v_id;
  for l in select * from jsonb_array_elements(coalesce(p->'lines', '[]')) loop
    v_qty := coalesce(nullif(trim(l->>'qty'), '')::numeric, 0);
    if v_qty = 0 then continue; end if;
    select * into v_l from purchase_lines where id = rb_int(l, 'line_id') and purchase_id = v_p.id;
    if v_l.id is null then raise exception 'That line is not on this purchase.'; end if;
    if v_qty < 0 then raise exception 'Line %: quantity cannot be negative.', v_l.line_no; end if;
    if v_from and v_qty > v_l.received_qty - v_l.rejected_qty - v_l.returned_qty then
      raise exception 'Line %: only % % is left from this purchase to return.', v_l.line_no,
        trim_scale(v_l.received_qty - v_l.rejected_qty - v_l.returned_qty)::text, v_l.unit_code;
    end if;
    if v_after and v_from and coalesce(v_l.agreed_qty, v_l.bill_qty, 0) > 0 then
      -- at the agreed rate, with the GST still claimed per unit after any debit notes
      v_rate := coalesce(v_l.agreed_rate_paise, v_l.bill_rate_paise); v_val := rb_pur_amt(v_qty, v_rate);
      v_gst := round(v_qty * (coalesce(v_l.bill_gst_paise, 0)
               - coalesce((select sum(gst_paise) from purchase_notes where purchase_line_id = v_l.id), 0))
               / coalesce(v_l.agreed_qty, v_l.bill_qty))::bigint;
    else
      v_rate := v_l.grn_rate_paise; v_val := rb_pur_amt(v_qty, v_rate); v_gst := 0;
    end if;
    if not v_from then v_val := 0; v_gst := 0; end if;
    insert into purchase_return_lines (return_id, purchase_line_id, qty, rate_paise, value_paise, gst_paise, is_demo, is_training)
    values (v_id, v_l.id, v_qty, v_rate, v_val, v_gst, v_p.is_demo, rb_is_training());
    v_n := v_n + 1;
    if v_from then
      v_tax := v_tax + v_val; v_gst_t := v_gst_t + v_gst;
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'purchase_return.' || rb_pur_stock_key(v_l.item_id),
        'amount_paise', v_val + case when v_claim then 0 else v_gst end, 'item_id', v_l.item_id, 'supplier_id', v_p.supplier_id,
        'narration', trim_scale(v_qty)::text || ' ' || v_l.unit_code || ' returned'));
      v_stock_t := v_stock_t + v_val + case when v_claim then 0 else v_gst end;
    end if;
  end loop;
  if v_n = 0 then raise exception 'Enter the quantity returned for at least one line.'; end if;
  update purchase_returns set taxable_paise = v_tax, gst_paise = v_gst_t, total_paise = v_tax + v_gst_t where id = v_id;
  if v_from and v_tax + v_gst_t > 0 then
    if v_after then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'purchase_return.payable', 'amount_paise', v_tax + v_gst_t,
        'supplier_id', v_p.supplier_id));
      if v_claim and v_gst_t > 0 then
        v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'purchase_return.input_gst', 'amount_paise', v_gst_t));
      end if;
    else
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'purchase_return.grni', 'amount_paise', v_tax,
        'supplier_id', v_p.supplier_id));
    end if;
    v_j := rb_post_engine(jsonb_build_object('journal_date', v_date, 'source', 'purchases', 'event_code', 'purchase_return',
      'source_ref', v_no, 'narration', 'Goods returned ' || v_no || ' to ' || v_sup || ': ' || rb_txt(p, 'reason'),
      'department_id', v_p.department_id, 'is_demo', v_p.is_demo, 'entered_by', p_actor, 'approved_by', p_actor), v_lines);
    update purchase_returns set journal_id = v_j where id = v_id;
  end if;
  if v_from then
    for r in select rl.*, pl.item_id, pl.unit_code from purchase_return_lines rl join purchase_lines pl on pl.id = rl.purchase_line_id
             where rl.return_id = v_id loop
      perform rb_pur_stock(v_date, r.item_id, -rb_pur_base_qty(r.item_id, r.unit_code, r.qty),
        -(r.value_paise + case when v_claim then 0 else r.gst_paise end), 'purchase_return', v_no, v_p.id, v_j,
        v_p.department_id, p_actor, v_p.is_demo);
    end loop;
  end if;
  perform rb_pur_refresh(v_p.id);
  perform rb_audit_write('PURCHASE_RETURN', 'purchase_returns', v_id::text, null,
    jsonb_build_object('return_no', v_no, 'purchase', rb_pur_label(v_p), 'total_paise', v_tax + v_gst_t, 'from_stock', v_from), rb_txt(p, 'reason'));
  return v_id;
end $$;

-- Settle one difference. p_action: accept, return, debit_note, await_delivery, correct_rate.
create or replace function rb_pur_settle(p_disc bigint, p_action text, p_reason text, p_date date, p_actor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_d purchase_discrepancies; v_p purchases; v_l purchase_lines; v_tax bigint; v_gst bigint; v_ok text[];
        v_unit_gst numeric;
begin
  select * into v_d from purchase_discrepancies where id = p_disc for update;
  if v_d.id is null then raise exception 'That difference was not found.'; end if;
  if v_d.status <> 'open' then raise exception 'This difference is already settled.'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason for your decision.'; end if;
  select * into v_p from purchases where id = v_d.purchase_id for update;
  select * into v_l from purchase_lines where id = v_d.purchase_line_id;
  -- What may be done with each kind of difference
  v_ok := case
    when v_d.stage = 'receipt' and v_d.kind = 'short'   then array['accept', 'await_delivery']
    when v_d.stage = 'receipt' and v_d.kind = 'excess'  then array['accept', 'return']
    when v_d.stage = 'receipt' and v_d.kind = 'damaged' then array['accept', 'return']
    when v_d.stage = 'bill' and v_d.kind = 'short'      then array['accept', 'debit_note', 'await_delivery']
    when v_d.kind in ('rate') and v_d.amount_paise > 0  then array['accept', 'correct_rate']
    when v_d.kind in ('tax') and v_d.amount_paise > 0   then array['accept', 'debit_note']
    else array['accept'] end;
  if not (p_action = any (v_ok)) then
    raise exception 'For this difference you can choose: %.', array_to_string(v_ok, ', ');
  end if;
  if p_action = 'return' and v_p.bill_posted_at is not null and v_d.stage = 'receipt' and v_d.kind = 'excess' then
    null; -- allowed: returned after the bill reduces what is owed
  end if;
  update purchase_discrepancies set status = case when p_action = 'accept' then 'accepted' else 'rejected' end,
    action = p_action, reason = trim(p_reason), decided_by = p_actor, decided_at = now()
  where id = p_disc;
  if p_action = 'return' then
    perform rb_pur_return(jsonb_build_object('purchase_id', v_p.id, 'return_date', coalesce(p_date, current_date),
      'reason', trim(p_reason), 'from_stock', v_d.kind <> 'damaged',
      'lines', jsonb_build_array(jsonb_build_object('line_id', v_l.id, 'qty', abs(v_d.qty_diff)))), p_actor, p_disc);
  elsif p_action in ('debit_note', 'correct_rate') then
    -- Change what is agreed for the line, then claim back the difference
    -- between what the supplier charged (less earlier notes) and the new
    -- agreed figure. Working from the agreed figure means rate, quantity
    -- and tax notes never double count, in whatever order they are made.
    if v_d.kind = 'short' then
      update purchase_lines set agreed_qty = coalesce(agreed_qty, bill_qty) - v_d.qty_diff where id = v_l.id;
    elsif v_d.kind = 'rate' then
      update purchase_lines set agreed_rate_paise = po_rate_paise where id = v_l.id;
    else
      update purchase_lines set gst_at_po_rate = true where id = v_l.id;
    end if;
    select * into v_l from purchase_lines where id = v_l.id;
    v_unit_gst := case when coalesce(v_l.bill_taxable_paise, 0) > 0 then coalesce(v_l.bill_gst_paise, 0)::numeric / v_l.bill_taxable_paise else 0 end;
    v_tax := rb_pur_amt(v_l.agreed_qty, v_l.agreed_rate_paise);           -- agreed taxable value
    v_gst := case when v_l.gst_at_po_rate then round(v_tax * coalesce(v_l.gst_rate, 0) / 100.0) else round(v_tax * v_unit_gst) end;
    v_tax := v_l.bill_taxable_paise - coalesce((select sum(taxable_paise) from purchase_notes where purchase_line_id = v_l.id), 0) - v_tax;
    v_gst := coalesce(v_l.bill_gst_paise, 0) - coalesce((select sum(gst_paise) from purchase_notes where purchase_line_id = v_l.id), 0) - v_gst;
    perform rb_pur_debit_note(v_p.id, v_l.id, p_disc, coalesce(p_date, current_date), greatest(v_tax, 0), greatest(v_gst, 0), trim(p_reason), p_actor);
  end if;
  perform rb_pur_refresh(v_p.id);
  perform rb_audit_write('SETTLE_DIFFERENCE', 'purchase_discrepancies', p_disc::text, to_jsonb(v_d),
    jsonb_build_object('action', p_action, 'purchase', rb_pur_label(v_p)), trim(p_reason));
end $$;

-- ---------------------------------------------------------------------
-- 6. What the screens call
-- ---------------------------------------------------------------------

create or replace function rb_save_purchase_order(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid;
begin
  v_me := rb_require(case when rb_int(p, 'id') is null then 'purchases.add' else 'purchases.edit' end,
                     case when rb_int(p, 'id') is null then 'enter purchase orders' else 'change purchase orders' end);
  return rb_pur_save_order(p, v_me, false);
end $$;

create or replace function rb_cancel_purchase_order(p_id bigint, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('purchases.edit', 'cancel purchase orders'); v_p purchases;
begin
  select * into v_p from purchases where id = p_id for update;
  if v_p.id is null then raise exception 'Purchase not found.'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason.'; end if;
  if v_p.is_direct or exists (select 1 from purchase_grns where purchase_id = p_id) then
    raise exception 'Goods have been received, so the order cannot be cancelled. Reverse the purchase instead.';
  end if;
  if v_p.status = 'cancelled' then raise exception 'Already cancelled.'; end if;
  update purchases set status = 'cancelled', cancel_reason = trim(p_reason), updated_at = now(), updated_by = v_me where id = p_id;
  perform rb_audit_write('CANCEL_ORDER', 'purchases', p_id::text, null, jsonb_build_object('po_no', v_p.po_no), trim(p_reason));
end $$;

create or replace function rb_receive_goods(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('purchases.add', 'receive goods');
begin
  return rb_pur_receive(p, v_me);
end $$;

create or replace function rb_enter_supplier_bill(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('purchases.add', 'enter supplier bills');
begin
  perform rb_pur_bill(p, v_me);
end $$;

create or replace function rb_save_direct_purchase(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid;
begin
  v_me := rb_require(case when rb_int(p, 'id') is null then 'purchases.add' else 'purchases.edit' end,
                     case when rb_int(p, 'id') is null then 'enter purchases' else 'change purchases' end);
  if rb_int(p, 'id') is not null and not exists (select 1 from purchases where id = rb_int(p, 'id') and entered_by = v_me)
     and not rb_has('power.purchase_values') then
    raise exception 'Only the person who entered it, or the accounts team, can change it.';
  end if;
  -- Directors, the FC and the Accountant may approve their own (spec section 4).
  return rb_pur_save_direct(p, v_me, false, rb_has('power.purchase_values') and rb_has('power.approve_own'));
end $$;

create or replace function rb_approve_direct_purchase(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.purchase_values', 'approve direct purchases above the limit'); v_p purchases;
begin
  select * into v_p from purchases where id = p_id for update;
  if v_p.id is null or not v_p.is_direct then raise exception 'Direct purchase not found.'; end if;
  if v_p.status <> 'awaiting_approval' then raise exception 'This purchase is not waiting for approval.'; end if;
  if v_p.entered_by = v_me and not rb_has('power.approve_own') then
    raise exception 'You cannot approve your own entries.';
  end if;
  update purchases set status = 'received' where id = p_id;
  perform rb_pur_post_direct(p_id, v_me, v_me);
  perform rb_audit_write('APPROVE_DIRECT_PURCHASE', 'purchases', p_id::text, null, jsonb_build_object('purchase', rb_pur_label(v_p)), null);
end $$;

create or replace function rb_refuse_direct_purchase(p_id bigint, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.purchase_values', 'refuse direct purchases'); v_p purchases;
begin
  select * into v_p from purchases where id = p_id for update;
  if v_p.id is null or v_p.status <> 'awaiting_approval' then raise exception 'This purchase is not waiting for approval.'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason.'; end if;
  update purchases set status = 'refused', refused_reason = trim(p_reason), updated_at = now(), updated_by = v_me where id = p_id;
  perform rb_audit_write('REFUSE_DIRECT_PURCHASE', 'purchases', p_id::text, null, jsonb_build_object('purchase', rb_pur_label(v_p)), trim(p_reason));
end $$;

create or replace function rb_add_purchase_photo(p_id bigint, p_data_url text, p_caption text)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('purchases.add', 'add photos to purchases'); v_p purchases; v_id bigint;
begin
  select * into v_p from purchases where id = p_id;
  if v_p.id is null then raise exception 'Purchase not found.'; end if;
  if p_data_url is null or p_data_url not like 'data:image/%' then raise exception 'That is not a photo.'; end if;
  if length(p_data_url) > 700000 then raise exception 'The photo is too big. Take it again a little further away.'; end if;
  insert into purchase_photos (purchase_id, data_url, caption, added_by, is_demo, is_training)
  values (p_id, p_data_url, nullif(trim(p_caption), ''), v_me, v_p.is_demo, rb_is_training()) returning id into v_id;
  return v_id;
end $$;

create or replace function rb_purchase_photo(p_id bigint)
returns text language plpgsql stable security definer set search_path = public as $$
begin
  perform rb_require('purchases.view', 'see purchases');
  return (select data_url from purchase_photos where id = p_id);
end $$;

-- Settle a difference. Quantity differences at delivery need Purchases
-- approve; money differences (anything on the bill) need the accounts
-- team (spec section 6). Nobody settles differences on their own entry
-- unless they may approve their own.
create or replace function rb_settle_discrepancy(p_id bigint, p_action text, p_reason text, p_date date default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('purchases.view', 'settle differences'); v_d purchase_discrepancies; v_p purchases;
begin
  select * into v_d from purchase_discrepancies where id = p_id;
  if v_d.id is null then raise exception 'That difference was not found.'; end if;
  select * into v_p from purchases where id = v_d.purchase_id;
  if v_d.stage = 'bill' or v_d.kind in ('rate', 'tax') or p_action in ('debit_note', 'correct_rate') then
    if not rb_has('power.purchase_values') then
      raise exception 'Money differences (rate, tax, billed quantity) are settled only by the Accountant, FC or a Director. You can see them flagged here.';
    end if;
  elsif not rb_has('purchases.approve') then
    raise exception 'You do not have the right to settle purchase differences.';
  end if;
  if not rb_can_approve('purchases', v_p.entered_by) and not (rb_has('power.purchase_values') and rb_has('power.approve_own')) then
    raise exception 'You entered this purchase, so someone else must settle its differences.';
  end if;
  perform rb_pur_settle(p_id, p_action, p_reason, p_date, v_me);
end $$;

create or replace function rb_return_to_supplier(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('purchases.add', 'return goods to suppliers');
begin
  return rb_pur_return(p, v_me, null);
end $$;

create or replace function rb_pay_supplier(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('purchases.add', 'pay suppliers');
begin
  return rb_pur_pay(p, v_me, false);
end $$;

-- Set an amount paid on account (an advance) against bills later.
create or replace function rb_allocate_payment(p_payment bigint, p_allocations jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('purchases.add', 'allocate payments'); v_s supplier_payments; a jsonb; v_pur purchases; v_left bigint;
begin
  select * into v_s from supplier_payments where id = p_payment for update;
  if v_s.id is null or v_s.status <> 'posted' then raise exception 'Payment not found.'; end if;
  v_left := v_s.amount_paise - coalesce((select sum(amount_paise) from payment_allocations where payment_id = p_payment), 0);
  for a in select * from jsonb_array_elements(coalesce(p_allocations, '[]')) loop
    if coalesce(rb_int(a, 'amount_paise'), 0) <= 0 then continue; end if;
    select * into v_pur from purchases where id = rb_int(a, 'purchase_id') for update;
    if v_pur.id is null or v_pur.supplier_id <> v_s.supplier_id then raise exception 'That purchase is not from this supplier.'; end if;
    if v_pur.bill_posted_at is null then raise exception '% has no bill yet.', rb_pur_label(v_pur); end if;
    if v_pur.open_discrepancies > 0 then raise exception '% has differences to settle first.', rb_pur_label(v_pur); end if;
    if rb_int(a, 'amount_paise') > v_pur.outstanding_paise then
      raise exception '% only has % left to pay.', rb_pur_label(v_pur), rb_pur_fmt(v_pur.outstanding_paise);
    end if;
    if rb_int(a, 'amount_paise') > v_left then raise exception 'Only % of this payment is left to set against bills.', rb_pur_fmt(v_left); end if;
    insert into payment_allocations (payment_id, purchase_id, amount_paise, is_demo, is_training)
    values (p_payment, v_pur.id, rb_int(a, 'amount_paise'), v_s.is_demo, rb_is_training());
    v_left := v_left - rb_int(a, 'amount_paise');
    perform rb_pur_refresh(v_pur.id);
  end loop;
  perform rb_audit_write('ALLOCATE_PAYMENT', 'supplier_payments', p_payment::text, null, p_allocations, null);
end $$;

-- Journals from this screen are reversed only here, so stock and the
-- supplier balance stay right.
create or replace function rb_pur_journal_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('rb.purchases', true), '') = 'on' then return coalesce(new, old); end if;
  if tg_op = 'UPDATE' and old.source = 'purchases' and old.status = 'posted' and new.status = 'reversed' then
    raise exception 'This entry comes from the Purchases screen. Reverse it there (open the purchase or payment), so stock and the supplier balance stay right.';
  end if;
  if tg_op = 'DELETE' and old.source = 'purchases' and old.status <> 'draft' and not old.is_demo
     and not (old.is_training and rb_is_training()) then
    raise exception 'This entry comes from the Purchases screen. Delete or reverse it there.';
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists rb_pur_journal_guard on journals;
create trigger rb_pur_journal_guard before update or delete on journals
  for each row execute function rb_pur_journal_guard();

-- Reverse a whole purchase: every journal it made, and its stock.
create or replace function rb_reverse_purchase(p_id bigint, p_date date, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.reverse_entries', 'reverse posted entries'); v_p purchases; v_j bigint; v_rev bigint;
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason for the reversal.'; end if;
  select * into v_p from purchases where id = p_id for update;
  if v_p.id is null then raise exception 'Purchase not found.'; end if;
  if v_p.status in ('cancelled', 'refused') then raise exception 'This purchase is already cancelled.'; end if;
  if v_p.status in ('ordered', 'awaiting_approval') then raise exception 'Nothing is posted yet: cancel or refuse it instead.'; end if;
  if v_p.paid_paise > 0 then
    raise exception 'Payments are set against this purchase. Reverse those payments first.';
  end if;
  perform rb_assert_period_open(p_date);
  perform set_config('rb.purchases', 'on', true);
  for v_j in select id from journals j where status = 'posted' and id in (
      select journal_id from purchase_grns where purchase_id = p_id
      union select bill_journal_id from purchases where id = p_id
      union select journal_id from purchase_notes where purchase_id = p_id
      union select journal_id from purchase_returns where purchase_id = p_id) order by id loop
    v_rev := rb_reverse_journal(v_j, p_date, 'Purchase ' || rb_pur_label(v_p) || ' reversed: ' || trim(p_reason));
  end loop;
  perform set_config('rb.purchases', 'off', true);
  insert into stock_moves (move_date, item_id, qty_base, value_paise, kind, doc_no, purchase_id, department_id, note, created_by, is_demo, is_training)
  select p_date, item_id, -sum(qty_base), -sum(value_paise), 'reversal', rb_pur_label(v_p), p_id, v_p.department_id, trim(p_reason), v_me,
         v_p.is_demo, rb_is_training()
  from stock_moves where purchase_id = p_id group by item_id
  having sum(qty_base) <> 0 or sum(value_paise) <> 0;
  update purchases set status = 'cancelled', cancel_reason = trim(p_reason), outstanding_paise = 0, updated_at = now(), updated_by = v_me
  where id = p_id;
  update purchase_discrepancies set status = 'rejected', action = coalesce(action, 'accept'), reason = coalesce(reason, 'Purchase reversed'),
    decided_by = coalesce(decided_by, v_me), decided_at = coalesce(decided_at, now())
  where purchase_id = p_id and status = 'open';
  update purchases set open_discrepancies = 0 where id = p_id;
  perform rb_audit_write('REVERSE_PURCHASE', 'purchases', p_id::text, null, jsonb_build_object('purchase', rb_pur_label(v_p), 'date', p_date), trim(p_reason));
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
  for v_pid in select distinct purchase_id from payment_allocations where payment_id = p_id loop
    perform rb_pur_refresh(v_pid);
  end loop;
  perform rb_audit_write('REVERSE_PAYMENT', 'supplier_payments', p_id::text, null, jsonb_build_object('payment_no', v_s.payment_no), trim(p_reason));
end $$;

-- Learning phase: a Director or the FC may fully delete a purchase (or
-- payment) entered by someone still in their learning phase. Not written
-- to the audit log (spec section 4).
create or replace function rb_hard_delete_purchase(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('purchases.delete', 'fully delete purchases'); v_p purchases; v_ids bigint[];
begin
  select * into v_p from purchases where id = p_id for update;
  if v_p.id is null then raise exception 'Purchase not found.'; end if;
  if not rb_can_hard_delete('purchases', v_p.entered_by) then
    raise exception 'Only purchases entered by someone still in their learning phase can be fully deleted. Reverse it instead.';
  end if;
  if exists (select 1 from payment_allocations a join supplier_payments s on s.id = a.payment_id where a.purchase_id = p_id and s.status = 'posted') then
    raise exception 'Payments are set against this purchase. Delete or reverse those first.';
  end if;
  select array_agg(x) into v_ids from (
    select journal_id x from purchase_grns where purchase_id = p_id
    union select bill_journal_id from purchases where id = p_id
    union select journal_id from purchase_notes where purchase_id = p_id
    union select journal_id from purchase_returns where purchase_id = p_id) s where x is not null;
  if exists (select 1 from journals where id = any (coalesce(v_ids, '{}')) and (reversed_by is not null)) then
    raise exception 'This purchase has been reversed. Reversed entries are kept.';
  end if;
  if exists (select 1 from journals j join periods pr on pr.month = date_trunc('month', j.journal_date)::date
             where j.id = any (coalesce(v_ids, '{}')) and pr.is_locked) then
    raise exception 'Part of this purchase is in a locked month.';
  end if;
  perform set_config('rb.ledger', 'on', true);
  perform set_config('rb.purchases', 'on', true);
  delete from stock_moves where purchase_id = p_id;
  delete from purchases where id = p_id;
  delete from journals where id = any (coalesce(v_ids, '{}'));
  perform set_config('rb.purchases', 'off', true);
  perform set_config('rb.ledger', 'off', true);
end $$;

create or replace function rb_hard_delete_supplier_payment(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('purchases.delete', 'fully delete payments'); v_s supplier_payments; v_pid bigint;
begin
  select * into v_s from supplier_payments where id = p_id for update;
  if v_s.id is null then raise exception 'Payment not found.'; end if;
  if not rb_can_hard_delete('purchases', v_s.entered_by) then
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
end $$;

-- ---------------------------------------------------------------------
-- 7. Reading: one purchase, supplier balances and ledger, reports
-- ---------------------------------------------------------------------

create or replace function rb_purchase_detail(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_p purchases; v jsonb;
begin
  perform rb_require('purchases.view', 'see purchases');
  select * into v_p from purchases where id = p_id;
  if v_p.id is null then raise exception 'Purchase not found.'; end if;
  select jsonb_build_object(
    'purchase', to_jsonb(v_p) || jsonb_build_object(
       'supplier_name', s.name, 'supplier_code', s.code, 'department', rb_dept_label(v_p.department_id, coalesce(v_p.po_date, v_p.purchase_date)),
       'entered_by_name', (select coalesce(short_name, full_name) from app_users where id = v_p.entered_by),
       'approved_by_name', (select coalesce(short_name, full_name) from app_users where id = v_p.approved_by),
       'label', rb_pur_label(v_p),
       'bill_journal_no', (select journal_no from journals where id = v_p.bill_journal_id)),
    'lines', coalesce((select jsonb_agg(to_jsonb(l) || jsonb_build_object('item_name', i.name, 'item_code', i.code, 'item_kind', i.kind,
               'po_amount_paise', rb_pur_amt(l.po_qty, l.po_rate_paise),
               'accepted_qty', l.received_qty - l.rejected_qty,
               'grn_value_paise', rb_pur_amt(l.received_qty - l.rejected_qty, l.grn_rate_paise),
               'expected_gst_paise', round(coalesce(l.bill_taxable_paise, 0) * coalesce(l.gst_rate, 0) / 100.0)::bigint)
               order by l.line_no) from purchase_lines l join items i on i.id = l.item_id where l.purchase_id = p_id), '[]'),
    'grns', coalesce((select jsonb_agg(to_jsonb(g) || jsonb_build_object('journal_no', j.journal_no,
               'lines', (select jsonb_agg(to_jsonb(gl)) from purchase_grn_lines gl where gl.grn_id = g.id)) order by g.id)
               from purchase_grns g left join journals j on j.id = g.journal_id where g.purchase_id = p_id), '[]'),
    'discrepancies', coalesce((select jsonb_agg(to_jsonb(d) || jsonb_build_object('line_no', l.line_no, 'item_name', i.name,
               'decided_by_name', (select coalesce(short_name, full_name) from app_users where id = d.decided_by),
               'age_days', current_date - d.first_seen) order by l.line_no, d.stage, d.kind)
               from purchase_discrepancies d join purchase_lines l on l.id = d.purchase_line_id join items i on i.id = l.item_id
               where d.purchase_id = p_id), '[]'),
    'notes', coalesce((select jsonb_agg(to_jsonb(n) || jsonb_build_object('journal_no', j.journal_no) order by n.id)
               from purchase_notes n left join journals j on j.id = n.journal_id where n.purchase_id = p_id), '[]'),
    'returns', coalesce((select jsonb_agg(to_jsonb(r) || jsonb_build_object('journal_no', j.journal_no,
               'lines', (select jsonb_agg(to_jsonb(rl)) from purchase_return_lines rl where rl.return_id = r.id)) order by r.id)
               from purchase_returns r left join journals j on j.id = r.journal_id where r.purchase_id = p_id), '[]'),
    'payments', coalesce((select jsonb_agg(jsonb_build_object('payment_id', sp.id, 'payment_no', sp.payment_no, 'pay_date', sp.pay_date,
               'mode', sp.mode, 'amount_paise', a.amount_paise, 'status', sp.status) order by sp.pay_date, sp.id)
               from payment_allocations a join supplier_payments sp on sp.id = a.payment_id where a.purchase_id = p_id), '[]'),
    'photos', coalesce((select jsonb_agg(jsonb_build_object('id', ph.id, 'caption', ph.caption, 'added_at', ph.added_at) order by ph.id)
               from purchase_photos ph where ph.purchase_id = p_id), '[]'),
    'gst_claimable', rb_pur_gst_claimable(),
    'can', jsonb_build_object(
       'edit_order', rb_has('purchases.edit') and not v_p.is_direct and v_p.status = 'ordered',
       'receive', rb_has('purchases.add') and not v_p.is_direct and v_p.bill_posted_at is null and v_p.status not in ('cancelled', 'refused'),
       'bill', rb_has('purchases.add') and not v_p.is_direct and v_p.bill_posted_at is null
               and exists (select 1 from purchase_grns where purchase_id = p_id) and v_p.status <> 'cancelled',
       'return', rb_has('purchases.add') and v_p.status not in ('ordered', 'cancelled', 'refused', 'awaiting_approval'),
       'pay', rb_has('purchases.add') and v_p.outstanding_paise > 0 and v_p.open_discrepancies = 0,
       'settle_qty', rb_has('purchases.approve') and (rb_can_approve('purchases', v_p.entered_by) or (rb_has('power.purchase_values') and rb_has('power.approve_own'))),
       'settle_money', rb_has('power.purchase_values') and (rb_can_approve('purchases', v_p.entered_by) or rb_has('power.approve_own')),
       'approve', rb_has('power.purchase_values') and v_p.status = 'awaiting_approval' and (v_p.entered_by is distinct from rb_current_user_id() or rb_has('power.approve_own')),
       'edit_direct', v_p.status = 'awaiting_approval' and (v_p.entered_by = rb_current_user_id() or rb_has('power.purchase_values')),
       'cancel', rb_has('purchases.edit') and v_p.status = 'ordered',
       'reverse', rb_has('power.reverse_entries') and v_p.status not in ('ordered', 'awaiting_approval', 'cancelled', 'refused') and v_p.paid_paise = 0,
       'hard_delete', rb_can_hard_delete('purchases', v_p.entered_by) and v_p.status <> 'cancelled'))
  into v from suppliers s where s.id = v_p.supplier_id;
  return v;
end $$;

-- What each supplier is owed (credit balance) on a date, from the books.
create or replace function rb_supplier_balances(p_as_of date default current_date, p_include_demo boolean default true)
returns table (supplier_id int, code text, name text, kind text, billed_paise bigint, paid_paise bigint, balance_paise bigint,
               open_bills int, oldest_bill date, oldest_days int, credit_days int, overdue_paise bigint, is_demo boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (rb_has('purchases.view') or rb_has('suppliers.view') or rb_has('accounts.view')) then
    raise exception 'You do not have the right to see supplier balances.';
  end if;
  return query
  with ap as (
    select l.supplier_id sid, sum(l.credit_paise)::bigint cr, sum(l.debit_paise)::bigint dr
    from journal_lines l join journals j on j.id = l.journal_id join accounts a on a.code = l.account_code
    where a.control_type = 'supplier' and j.status <> 'draft' and l.journal_date <= p_as_of
      and (p_include_demo or not l.is_demo)
    group by l.supplier_id),
  ob as (
    select p.supplier_id sid, count(*)::int n, min(coalesce(p.bill_date, p.purchase_date)) d,
           sum(case when coalesce(p.bill_date, p.purchase_date) + coalesce(s2.credit_days, 0) < p_as_of then p.outstanding_paise else 0 end)::bigint od
    from purchases p join suppliers s2 on s2.id = p.supplier_id
    where p.outstanding_paise > 0 and p.status in ('billed') and (p_include_demo or not p.is_demo)
    group by p.supplier_id)
  select s.id, s.code, s.name, s.kind, coalesce(ap.cr, 0), coalesce(ap.dr, 0), coalesce(ap.cr, 0) - coalesce(ap.dr, 0),
         coalesce(ob.n, 0), ob.d, (p_as_of - ob.d)::int, s.credit_days, coalesce(ob.od, 0), s.is_demo
  from suppliers s left join ap on ap.sid = s.id left join ob on ob.sid = s.id
  where ap.sid is not null or ob.sid is not null
  order by coalesce(ap.cr, 0) - coalesce(ap.dr, 0) desc, s.name;
end $$;

-- A supplier's ledger: every bill, debit note, return and payment, with a running balance (credit = we owe).
create or replace function rb_supplier_ledger(p_supplier int, p_from date, p_to date)
returns table (line_date date, journal_no text, doc_ref text, event text, narration text, bill_paise bigint, paid_paise bigint,
               balance_paise bigint, is_demo boolean)
language plpgsql stable security definer set search_path = public as $$
declare v_open bigint;
begin
  if not (rb_has('purchases.view') or rb_has('suppliers.view') or rb_has('accounts.view')) then
    raise exception 'You do not have the right to see the supplier ledger.';
  end if;
  select coalesce(sum(l.credit_paise - l.debit_paise), 0) into v_open
  from journal_lines l join journals j on j.id = l.journal_id join accounts a on a.code = l.account_code
  where a.control_type = 'supplier' and l.supplier_id = p_supplier and j.status <> 'draft' and l.journal_date < p_from;
  return query
  select p_from, null::text, null::text, 'opening'::text, 'Balance brought forward'::text, null::bigint, null::bigint, v_open, false
  union all
  select x.journal_date, x.journal_no, x.source_ref, x.event_code, x.narration, x.cr, x.dr,
         v_open + sum(x.cr - x.dr) over (order by x.journal_date, x.jid, x.lid)::bigint, x.is_demo
  from (select l.journal_date, j.journal_no, j.source_ref, coalesce(j.event_code, j.source) event_code,
               coalesce(l.narration, j.narration) narration, l.credit_paise cr, l.debit_paise dr, j.id jid, l.id lid, l.is_demo
        from journal_lines l join journals j on j.id = l.journal_id join accounts a on a.code = l.account_code
        where a.control_type = 'supplier' and l.supplier_id = p_supplier and j.status <> 'draft'
          and l.journal_date between p_from and p_to) x
  order by 1, 2 nulls first;
end $$;

-- Open differences across all purchases, oldest first.
create or replace function rb_open_discrepancies()
returns table (id bigint, purchase_id bigint, purchase_ref text, supplier_name text, supplier_id int, item_name text,
               stage text, kind text, explain text, qty_diff numeric, amount_paise bigint, age_days int, is_demo boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  perform rb_require('purchases.view', 'see purchase differences');
  return query
  select d.id, p.id, rb_pur_label(p), s.name, s.id, i.name, d.stage, d.kind, d.explain, d.qty_diff, d.amount_paise,
         (current_date - d.first_seen)::int, d.is_demo
  from purchase_discrepancies d join purchases p on p.id = d.purchase_id join suppliers s on s.id = p.supplier_id
  join purchase_lines l on l.id = d.purchase_line_id join items i on i.id = l.item_id
  where d.status = 'open'
  order by d.first_seen, d.id;
end $$;

-- Supplier discrepancy report: count and value of short supply, overcharge
-- and rejects per supplier, by month (spec section 6).
create or replace function rb_supplier_discrepancy_report(p_from date, p_to date)
returns table (month date, supplier_id int, supplier_name text, short_count int, short_paise bigint,
               overcharge_count int, overcharge_paise bigint, reject_count int, reject_paise bigint,
               excess_count int, open_count int)
language plpgsql stable security definer set search_path = public as $$
begin
  perform rb_require('purchases.view', 'see purchase reports');
  return query
  select date_trunc('month', coalesce(p.po_date, p.purchase_date))::date, s.id, s.name,
    count(*) filter (where d.kind = 'short')::int,
    coalesce(sum(abs(d.amount_paise)) filter (where d.kind = 'short'), 0)::bigint,
    count(*) filter (where d.kind in ('rate', 'tax') and d.amount_paise > 0)::int,
    coalesce(sum(d.amount_paise) filter (where d.kind in ('rate', 'tax') and d.amount_paise > 0), 0)::bigint,
    count(*) filter (where d.kind = 'damaged')::int,
    coalesce(sum(abs(d.amount_paise)) filter (where d.kind = 'damaged'), 0)::bigint,
    count(*) filter (where d.kind = 'excess')::int,
    count(*) filter (where d.status = 'open')::int
  from purchase_discrepancies d join purchases p on p.id = d.purchase_id join suppliers s on s.id = p.supplier_id
  where coalesce(p.po_date, p.purchase_date) between p_from and p_to and p.status <> 'cancelled'
  group by 1, 2, 3 order by 1, 3;
end $$;

-- Direct purchases by month and supplier, for the monthly review (spec section 6).
create or replace function rb_direct_purchase_report(p_from date, p_to date)
returns table (month date, supplier_id int, supplier_name text, purchases int, no_bill int, total_paise bigint,
               cash_paise bigint, credit_paise bigint, awaiting_approval int)
language plpgsql stable security definer set search_path = public as $$
begin
  perform rb_require('purchases.view', 'see purchase reports');
  return query
  select date_trunc('month', p.purchase_date)::date, s.id, s.name, count(*)::int,
    count(*) filter (where p.no_supplier_bill)::int,
    coalesce(sum(case when p.status = 'awaiting_approval'
                      then (select sum(bill_taxable_paise + coalesce(bill_gst_paise, 0)) from purchase_lines where purchase_id = p.id)
                      else p.bill_total_paise end), 0)::bigint,
    coalesce(sum(p.bill_total_paise) filter (where p.payment_mode <> 'credit'), 0)::bigint,
    coalesce(sum(p.bill_total_paise) filter (where p.payment_mode = 'credit'), 0)::bigint,
    count(*) filter (where p.status = 'awaiting_approval')::int
  from purchases p join suppliers s on s.id = p.supplier_id
  where p.is_direct and p.purchase_date between p_from and p_to and p.status not in ('cancelled', 'refused')
  group by 1, 2, 3 order by 1, 3;
end $$;

-- Stock on hand from purchases so far (module 4 adds production and sales).
create or replace function rb_stock_on_hand(p_as_of date default current_date)
returns table (item_id int, code text, name text, kind text, base_unit text, qty_base numeric, value_paise bigint, avg_cost_paise numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (rb_has('purchases.view') or rb_has('stock.view') or rb_has('accounts.view')) then
    raise exception 'You do not have the right to see stock.';
  end if;
  return query
  select i.id, i.code, i.name, i.kind, i.base_unit, sum(m.qty_base), sum(m.value_paise)::bigint,
         case when sum(m.qty_base) > 0 then round(sum(m.value_paise) / sum(m.qty_base), 4) end
  from stock_moves m join items i on i.id = m.item_id
  where m.move_date <= p_as_of
  group by i.id, i.code, i.name, i.kind, i.base_unit
  order by i.kind, i.name;
end $$;

-- ---------------------------------------------------------------------
-- 8. Row-level security and who may call what
-- ---------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array['purchases','purchase_lines','purchase_grns','purchase_grn_lines','purchase_discrepancies',
    'purchase_notes','purchase_returns','purchase_return_lines','supplier_payments','payment_allocations',
    'purchase_photos','stock_moves'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon, authenticated', t);
    execute format('grant select on %I to authenticated', t);
    execute format('grant all on %I to service_role', t);
    execute format('drop policy if exists rb_read on %I', t);
    if t = 'stock_moves' then
      execute format('create policy rb_read on %I for select to authenticated using (rb_has(''purchases.view'') or rb_has(''stock.view'') or rb_has(''accounts.view''))', t);
    elsif t = 'purchase_photos' then
      -- photos are read one at a time through rb_purchase_photo
      execute format('create policy rb_read on %I for select to authenticated using (false)', t);
    else
      execute format('create policy rb_read on %I for select to authenticated using (rb_has(''purchases.view'') or rb_has(''accounts.view''))', t);
    end if;
  end loop;
end $$;
revoke all on all sequences in schema public from anon, authenticated;

-- Nobody but these functions may run module 3's helpers.
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p
           where p.pronamespace = 'public'::regnamespace
             and (p.proname like 'rb\_pur\_%' or p.proname in (
               'rb_save_purchase_order','rb_cancel_purchase_order','rb_receive_goods','rb_enter_supplier_bill',
               'rb_save_direct_purchase','rb_approve_direct_purchase','rb_refuse_direct_purchase','rb_add_purchase_photo',
               'rb_purchase_photo','rb_settle_discrepancy','rb_return_to_supplier','rb_pay_supplier','rb_allocate_payment',
               'rb_reverse_purchase','rb_reverse_supplier_payment','rb_hard_delete_purchase','rb_hard_delete_supplier_payment',
               'rb_purchase_detail','rb_supplier_balances','rb_supplier_ledger','rb_open_discrepancies',
               'rb_supplier_discrepancy_report','rb_direct_purchase_report','rb_stock_on_hand')) loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;
end $$;
grant execute on function
  rb_save_purchase_order(jsonb), rb_cancel_purchase_order(bigint, text), rb_receive_goods(jsonb),
  rb_enter_supplier_bill(jsonb), rb_save_direct_purchase(jsonb), rb_approve_direct_purchase(bigint),
  rb_refuse_direct_purchase(bigint, text), rb_add_purchase_photo(bigint, text, text), rb_purchase_photo(bigint),
  rb_settle_discrepancy(bigint, text, text, date), rb_return_to_supplier(jsonb), rb_pay_supplier(jsonb),
  rb_allocate_payment(bigint, jsonb), rb_reverse_purchase(bigint, date, text), rb_reverse_supplier_payment(bigint, date, text),
  rb_hard_delete_purchase(bigint), rb_hard_delete_supplier_payment(bigint),
  rb_purchase_detail(bigint), rb_supplier_balances(date, boolean), rb_supplier_ledger(int, date, date),
  rb_open_discrepancies(), rb_supplier_discrepancy_report(date, date), rb_direct_purchase_report(date, date),
  rb_stock_on_hand(date)
  to authenticated;

-- ---------------------------------------------------------------------
-- 9. DEMO data: 11 purchases from the DEMO suppliers in Nov 2026, with
--    matched and unmatched bills, direct purchases with and without a
--    bill, one waiting for approval, a return, a debit note and payments.
--    Only added while the app is in training mode.
-- ---------------------------------------------------------------------

do $$
declare
  v_ds uuid := (select id from app_users where lower(email) = 'info.ruchibuds@gmail.com');
  v_acc uuid := (select id from app_users where email = 'demo.accounts@example.com');
  v_mgr uuid := coalesce((select id from app_users where email = 'demo.manager1@example.com'), v_acc);
  it jsonb; p bigint;
begin
  if not (select training_mode from app_settings where id = 1) or exists (select 1 from purchases where is_demo)
     or not exists (select 1 from suppliers where code = 'DEMO-S01') then
    return;
  end if;
  select jsonb_object_agg(code, id) into it from items where is_demo;

  -- 1. Mustard oil, ordered, received and billed exactly as ordered; paid by bank.
  p := rb_pur_save_order(jsonb_build_object('supplier_id', (select id from suppliers where code = 'DEMO-S07'), 'po_date', '2026-11-02',
    'note', 'Monthly oil (DEMO)', 'lines', jsonb_build_array(
      jsonb_build_object('item_id', it->'D-RM09', 'unit_code', 'l', 'qty', 25, 'rate_paise', 18000, 'gst_rate', 5))), v_mgr, true);
  perform rb_pur_receive(jsonb_build_object('purchase_id', p, 'grn_date', '2026-11-04', 'lines',
    (select jsonb_agg(jsonb_build_object('line_id', id, 'received_qty', 25)) from purchase_lines where purchase_id = p)), v_mgr);
  perform rb_pur_bill(jsonb_build_object('purchase_id', p, 'bill_no', 'KO/1187', 'bill_date', '2026-11-04', 'payment_mode', 'bank',
    'reference', 'NEFT 4411', 'lines', (select jsonb_agg(jsonb_build_object('line_id', id, 'qty', 25, 'rate_paise', 18000, 'gst_paise', 22500))
    from purchase_lines where purchase_id = p)), v_acc);

  -- 2. Glass bottles: 12 bottles broken on arrival, but the bill charges for all of them. Open differences.
  p := rb_pur_save_order(jsonb_build_object('supplier_id', (select id from suppliers where code = 'DEMO-S08'), 'po_date', '2026-11-03',
    'lines', jsonb_build_array(
      jsonb_build_object('item_id', it->'D-PK01', 'unit_code', 'pc', 'qty', 500, 'rate_paise', 1200, 'gst_rate', 18),
      jsonb_build_object('item_id', it->'D-PK02', 'unit_code', 'pc', 'qty', 300, 'rate_paise', 1800, 'gst_rate', 18))), v_mgr, true);
  perform rb_pur_receive(jsonb_build_object('purchase_id', p, 'grn_date', '2026-11-08', 'lines', jsonb_build_array(
    jsonb_build_object('line_id', (select id from purchase_lines where purchase_id = p and line_no = 1), 'received_qty', 500, 'rejected_qty', 12, 'reject_reason', 'Broken in transit'),
    jsonb_build_object('line_id', (select id from purchase_lines where purchase_id = p and line_no = 2), 'received_qty', 300))), v_mgr);
  perform rb_pur_bill(jsonb_build_object('purchase_id', p, 'bill_no', 'CG-2611-045', 'bill_date', '2026-11-09', 'payment_mode', 'credit',
    'lines', jsonb_build_array(
      jsonb_build_object('line_id', (select id from purchase_lines where purchase_id = p and line_no = 1), 'qty', 500, 'rate_paise', 1200, 'gst_paise', 108000),
      jsonb_build_object('line_id', (select id from purchase_lines where purchase_id = p and line_no = 2), 'qty', 300, 'rate_paise', 1800, 'gst_paise', 97200))), v_acc);

  -- 3. Pouches billed at a higher rate than the PO. An open rate difference.
  p := rb_pur_save_order(jsonb_build_object('supplier_id', (select id from suppliers where code = 'DEMO-S09'), 'po_date', '2026-11-05',
    'lines', jsonb_build_array(
      jsonb_build_object('item_id', it->'D-PK03', 'unit_code', 'pc', 'qty', 1000, 'rate_paise', 450, 'gst_rate', 18),
      jsonb_build_object('item_id', it->'D-PK04', 'unit_code', 'pc', 'qty', 500, 'rate_paise', 700, 'gst_rate', 18))), v_mgr, true);
  perform rb_pur_receive(jsonb_build_object('purchase_id', p, 'grn_date', '2026-11-10', 'lines',
    (select jsonb_agg(jsonb_build_object('line_id', id, 'received_qty', po_qty)) from purchase_lines where purchase_id = p)), v_mgr);
  perform rb_pur_bill(jsonb_build_object('purchase_id', p, 'bill_no', 'FP/889', 'bill_date', '2026-11-10', 'payment_mode', 'credit',
    'lines', jsonb_build_array(
      jsonb_build_object('line_id', (select id from purchase_lines where purchase_id = p and line_no = 1), 'qty', 1000, 'rate_paise', 480, 'gst_paise', 86400),
      jsonb_build_object('line_id', (select id from purchase_lines where purchase_id = p and line_no = 2), 'qty', 500, 'rate_paise', 700, 'gst_paise', 63000))), v_acc);

  -- 4. Dried chilli: 45 kg of 50 came; the rest is expected next week. Settled, then part paid.
  p := rb_pur_save_order(jsonb_build_object('supplier_id', (select id from suppliers where code = 'DEMO-S06'), 'po_date', '2026-11-06',
    'lines', jsonb_build_array(jsonb_build_object('item_id', it->'D-RM10', 'unit_code', 'kg', 'qty', 50, 'rate_paise', 28000, 'gst_rate', 0))), v_mgr, true);
  perform rb_pur_receive(jsonb_build_object('purchase_id', p, 'grn_date', '2026-11-11', 'lines',
    (select jsonb_agg(jsonb_build_object('line_id', id, 'received_qty', 45)) from purchase_lines where purchase_id = p)), v_mgr);
  perform rb_pur_settle((select id from purchase_discrepancies where purchase_id = p and kind = 'short'), 'await_delivery',
    'Supplier will send the last 5 kg next week (DEMO)', '2026-11-11', v_ds);
  perform rb_pur_bill(jsonb_build_object('purchase_id', p, 'bill_no', 'SS/5521', 'bill_date', '2026-11-12', 'payment_mode', 'credit',
    'lines', (select jsonb_agg(jsonb_build_object('line_id', id, 'qty', 45, 'rate_paise', 28000, 'gst_paise', 0)) from purchase_lines where purchase_id = p)), v_acc);
  perform rb_pur_pay(jsonb_build_object('supplier_id', (select id from suppliers where code = 'DEMO-S06'), 'pay_date', '2026-11-20',
    'mode', 'cash', 'amount_paise', 150000, 'reference', 'Cash voucher 17', 'allocations',
    jsonb_build_array(jsonb_build_object('purchase_id', p, 'amount_paise', 150000))), v_acc, true);

  -- 5. Meat: 20.4 kg came against 20 kg ordered (weighing), accepted. 1 kg spoilt, returned after the bill.
  p := rb_pur_save_order(jsonb_build_object('supplier_id', (select id from suppliers where code = 'DEMO-S04'), 'po_date', '2026-11-12',
    'lines', jsonb_build_array(jsonb_build_object('item_id', it->'D-RM03', 'unit_code', 'kg', 'qty', 20, 'rate_paise', 52000, 'gst_rate', 0))), v_mgr, true);
  perform rb_pur_receive(jsonb_build_object('purchase_id', p, 'grn_date', '2026-11-13', 'lines',
    (select jsonb_agg(jsonb_build_object('line_id', id, 'received_qty', 20.4)) from purchase_lines where purchase_id = p)), v_mgr);
  perform rb_pur_settle((select id from purchase_discrepancies where purchase_id = p and kind = 'excess'), 'accept',
    'Normal weighing difference (DEMO)', '2026-11-13', v_ds);
  perform rb_pur_bill(jsonb_build_object('purchase_id', p, 'bill_no', 'HM-221', 'bill_date', '2026-11-13', 'payment_mode', 'credit',
    'lines', (select jsonb_agg(jsonb_build_object('line_id', id, 'qty', 20.4, 'rate_paise', 52000, 'gst_paise', 0)) from purchase_lines where purchase_id = p)), v_acc);
  perform rb_pur_return(jsonb_build_object('purchase_id', p, 'return_date', '2026-11-14', 'reason', 'One packet spoilt, sent back (DEMO)',
    'lines', (select jsonb_agg(jsonb_build_object('line_id', id, 'qty', 1)) from purchase_lines where purchase_id = p)), v_mgr, null);

  -- 6. Ginger, garlic and onion: ordered, not yet received.
  perform rb_pur_save_order(jsonb_build_object('supplier_id', (select id from suppliers where code = 'DEMO-S05'), 'po_date', '2026-11-24',
    'expected_date', '2026-11-28', 'lines', jsonb_build_array(
      jsonb_build_object('item_id', it->'D-RM06', 'unit_code', 'kg', 'qty', 10, 'rate_paise', 12000, 'gst_rate', 0),
      jsonb_build_object('item_id', it->'D-RM07', 'unit_code', 'kg', 'qty', 10, 'rate_paise', 16000, 'gst_rate', 0),
      jsonb_build_object('item_id', it->'D-RM08', 'unit_code', 'kg', 'qty', 25, 'rate_paise', 3500, 'gst_rate', 0))), v_mgr, true);

  -- 7 and 8. Fish from fishermen: no bill, a note of the weighing slip; cash and UPI.
  perform rb_pur_save_direct(jsonb_build_object('supplier_id', (select id from suppliers where code = 'DEMO-S01'), 'purchase_date', '2026-11-15',
    'reason', 'Daily fish catch', 'payment_mode', 'cash', 'no_supplier_bill', true, 'note', 'Weighing slip no. 0412 kept in the file (DEMO)',
    'lines', jsonb_build_array(jsonb_build_object('item_id', it->'D-RM01', 'unit_code', 'kg', 'qty', 12, 'rate_paise', 45000))), v_mgr, true, true);
  perform rb_pur_save_direct(jsonb_build_object('supplier_id', (select id from suppliers where code = 'DEMO-S02'), 'purchase_date', '2026-11-18',
    'reason', 'Daily fish catch', 'payment_mode', 'upi', 'no_supplier_bill', true, 'note', 'Paid by UPI on the dock, 8.5 kg on the dock scale (DEMO)',
    'lines', jsonb_build_array(jsonb_build_object('item_id', it->'D-RM01', 'unit_code', 'kg', 'qty', 8.5, 'rate_paise', 48000))), v_mgr, true, true);

  -- 9. Urgent chicken with a shop bill, cash.
  perform rb_pur_save_direct(jsonb_build_object('supplier_id', (select id from suppliers where code = 'DEMO-S03'), 'purchase_date', '2026-11-19',
    'reason', 'Urgent: extra trader order', 'payment_mode', 'cash', 'bill_no', 'FCC/889',
    'lines', jsonb_build_array(jsonb_build_object('item_id', it->'D-RM02', 'unit_code', 'kg', 'qty', 10, 'rate_paise', 22000))), v_mgr, true, true);

  -- 10. Smoked dried meat on credit, above the approval limit: waiting for approval.
  p := rb_pur_save_direct(jsonb_build_object('supplier_id', (select id from suppliers where code = 'DEMO-S04'), 'purchase_date', '2026-11-25',
    'reason', 'Urgent top-up for the smoked meat pickle', 'payment_mode', 'credit', 'bill_no', 'HM-240',
    'ask_approval', true,
    'lines', jsonb_build_array(jsonb_build_object('item_id', it->'D-RM05', 'unit_code', 'kg', 'qty', 5, 'rate_paise', 140000, 'gst_paise', 35000))), v_mgr, true, false);

  -- 11. Mustard oil billed above the PO rate: the Accountant corrected it to the PO rate with a debit note.
  p := rb_pur_save_order(jsonb_build_object('supplier_id', (select id from suppliers where code = 'DEMO-S07'), 'po_date', '2026-11-16',
    'lines', jsonb_build_array(jsonb_build_object('item_id', it->'D-RM09', 'unit_code', 'l', 'qty', 20, 'rate_paise', 18000, 'gst_rate', 5))), v_mgr, true);
  perform rb_pur_receive(jsonb_build_object('purchase_id', p, 'grn_date', '2026-11-17', 'lines',
    (select jsonb_agg(jsonb_build_object('line_id', id, 'received_qty', 20)) from purchase_lines where purchase_id = p)), v_mgr);
  perform rb_pur_bill(jsonb_build_object('purchase_id', p, 'bill_no', 'KO/1203', 'bill_date', '2026-11-17', 'payment_mode', 'credit',
    'lines', (select jsonb_agg(jsonb_build_object('line_id', id, 'qty', 20, 'rate_paise', 19000, 'gst_paise', 19000)) from purchase_lines where purchase_id = p)), v_acc);
  perform rb_pur_settle((select id from purchase_discrepancies where purchase_id = p and kind = 'rate'), 'correct_rate',
    'Agreed rate is ₹180 a litre (DEMO)', '2026-11-18', v_ds);
end $$;

-- End of 03_purchases.sql
