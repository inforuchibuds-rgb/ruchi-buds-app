-- =====================================================================
-- RUCHI BUDS APP · Module 4: Stock and production
-- File: 04_stock_production.sql · Version 1.0.1 · 27-Nov-2026
--
-- What this file sets up:
--   The Production window's two batch types: Preparation (raw material
--   in, prepared ingredient out, wastage and by-products at each stage)
--   and Final production (prepared ingredients and raw materials in,
--   finished goods out in bottles and pouches, frying shrinkage and
--   packing wastage), plus "Prepare and produce together" for same-day
--   items, with the two batches linked. Running numbers PRP/YYMM/00001
--   and PRD/YYMM/00001. Prepared ingredients are kept batch by batch
--   with their preparation date, so stock past its shelf life shows in
--   red and is warned about when picked. Stock counts (with approval)
--   and opening stock, write-offs and write-downs, the stock lists
--   (raw materials and prepared; finished goods by pack), item
--   movements, the yield report and wastage by stage.
--
-- Accounting (Indian AS, ICAI; AS 2 Valuation of Inventories): stock is
-- valued at weighted average cost (the Settings choice from module 2).
-- A batch's cost is the cost of what went in. Normal wastage stays in
-- the batch cost; an unusual loss is taken out of it and charged to
-- "Inventory Write-down Expense". Sellable by-products are valued at
-- their selling price (net realisable value) and that value is taken
-- off the main product's cost (AS 2, by-products). Count differences go
-- to "Inventory Shrinkage Expense"; a write-down to net realisable value
-- goes to "Inventory Write-down Expense". Stock accounts are posted only
-- through stock records, so stock and the books always agree.
--
-- Run 01, 02 and 03 first. Then: Supabase -> SQL Editor -> New query
-- -> paste this whole file -> Run. It is safe to run again; nothing you
-- entered is lost on a re-run.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Screens
-- ---------------------------------------------------------------------

update screens set available = true where code in ('stock', 'production');

-- ---------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------

-- A preparation or final production batch.
create table if not exists production_batches (
  id                     bigserial primary key,
  batch_no               text unique,
  kind                   text not null check (kind in ('preparation', 'production')),
  batch_date             date not null,
  department_id          int not null references departments(id),
  output_item_id         int not null references items(id),
  input_qty_base         numeric(16,3) not null default 0,  -- preparation: raw material in (base unit)
  output_qty_base        numeric(16,3) not null default 0,  -- prepared or finished quantity made (base unit)
  wastage_qty_base       numeric(16,3) not null default 0,  -- preparation: all stages; production: shrinkage + packing
  shrinkage_qty_base     numeric(16,3) not null default 0,  -- production: frying shrinkage
  packing_waste_qty_base numeric(16,3) not null default 0,  -- production: packing wastage
  byproduct_qty_base     numeric(16,3) not null default 0,
  abnormal_qty_base      numeric(16,3) not null default 0,  -- unusual loss, outside normal wastage
  abnormal_reason        text,
  input_value_paise      bigint not null default 0,         -- cost of everything that went in (packaging too)
  packaging_value_paise  bigint not null default 0,
  byproduct_value_paise  bigint not null default 0,
  abnormal_value_paise   bigint not null default 0,
  output_value_paise     bigint not null default 0,
  linked_batch_id        bigint references production_batches(id) on delete set null,
  note                   text,
  status                 text not null default 'posted' check (status in ('posted', 'reversed')),
  journal_id             bigint references journals(id) on delete set null,
  reversal_journal_id    bigint references journals(id) on delete set null,
  reverse_reason         text,
  reversed_at            timestamptz,
  reversed_by            uuid,
  entered_by             uuid references app_users(id),
  entered_at             timestamptz not null default now(),
  is_demo                boolean not null default false,
  is_training            boolean not null default false
);
create index if not exists production_batches_date_idx on production_batches (batch_date);

-- What went in and came out of a batch. WIP inputs name the preparation
-- batch they were taken from (one row per batch used).
create table if not exists batch_lines (
  id            bigserial primary key,
  batch_id      bigint not null references production_batches(id) on delete cascade,
  line_no       int not null,
  role          text not null check (role in ('input', 'output', 'byproduct', 'packaging')),
  item_id       int not null references items(id),
  pack_id       int references product_packs(id),
  lot_batch_id  bigint references production_batches(id) on delete set null,
  packs         numeric(14,3),
  qty_base      numeric(16,3) not null,
  stage         text,
  byproduct_use text,
  value_paise   bigint not null default 0,
  is_demo       boolean not null default false,
  is_training   boolean not null default false
);
create index if not exists batch_lines_batch_idx on batch_lines (batch_id);
create index if not exists batch_lines_lot_idx on batch_lines (lot_batch_id) where lot_batch_id is not null;

-- Wastage recorded at each preparation stage.
create table if not exists batch_stages (
  id               bigserial primary key,
  batch_id         bigint not null references production_batches(id) on delete cascade,
  stage_no         int not null,
  stage            text not null,
  wastage_qty_base numeric(16,3) not null default 0 check (wastage_qty_base >= 0),
  is_demo          boolean not null default false,
  is_training      boolean not null default false
);

-- Physical stock counts, and opening stock at go-live.
create table if not exists stock_counts (
  id                  bigserial primary key,
  count_no            text unique,
  purpose             text not null default 'count' check (purpose in ('count', 'opening')),
  count_date          date not null,
  department_id       int not null references departments(id),
  note                text,
  status              text not null default 'draft' check (status in ('draft', 'posted', 'cancelled', 'reversed')),
  short_paise         bigint not null default 0,
  excess_paise        bigint not null default 0,
  journal_id          bigint references journals(id) on delete set null,
  reversal_journal_id bigint references journals(id) on delete set null,
  cancel_reason       text,
  reverse_reason      text,
  entered_by          uuid references app_users(id),
  entered_at          timestamptz not null default now(),
  approved_by         uuid references app_users(id),
  posted_at           timestamptz,
  updated_at          timestamptz,
  updated_by          uuid,
  is_demo             boolean not null default false,
  is_training         boolean not null default false
);

create table if not exists stock_count_lines (
  id               bigserial primary key,
  count_id         bigint not null references stock_counts(id) on delete cascade,
  line_no          int not null,
  item_id          int not null references items(id),
  pack_id          int references product_packs(id),
  counted_qty_base numeric(16,3) not null check (counted_qty_base >= 0),
  system_qty_base  numeric(16,3),               -- filled when posted (stock on the count date)
  diff_qty_base    numeric(16,3),
  unit_cost_paise  numeric(16,4),               -- opening stock: cost per base unit
  value_paise      bigint not null default 0,
  reason           text,
  is_demo          boolean not null default false,
  is_training      boolean not null default false
);
create index if not exists stock_count_lines_count_idx on stock_count_lines (count_id);

-- Write-offs (spoilt, expired, damaged) and write-downs to net realisable value.
create table if not exists stock_adjustments (
  id                  bigserial primary key,
  adj_no              text unique,
  kind                text not null check (kind in ('write_off', 'write_down')),
  adj_date            date not null,
  item_id             int not null references items(id),
  pack_id             int references product_packs(id),
  lot_batch_id        bigint references production_batches(id) on delete set null,
  qty_base            numeric(16,3) not null default 0 check (qty_base >= 0),
  value_paise         bigint not null default 0 check (value_paise >= 0),
  reason              text not null,
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

-- Stock movements (from module 3) now also carry the pack, the
-- preparation batch a prepared ingredient belongs to, and the record
-- that made them.
alter table stock_moves add column if not exists pack_id int references product_packs(id);
alter table stock_moves add column if not exists packs numeric(14,3);
alter table stock_moves add column if not exists lot_batch_id bigint;
alter table stock_moves add column if not exists batch_id bigint;
alter table stock_moves add column if not exists count_id bigint;
alter table stock_moves add column if not exists adjustment_id bigint;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'stock_moves_lot_fk') then
    alter table stock_moves add constraint stock_moves_lot_fk foreign key (lot_batch_id) references production_batches(id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'stock_moves_batch_fk') then
    alter table stock_moves add constraint stock_moves_batch_fk foreign key (batch_id) references production_batches(id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'stock_moves_count_fk') then
    alter table stock_moves add constraint stock_moves_count_fk foreign key (count_id) references stock_counts(id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'stock_moves_adj_fk') then
    alter table stock_moves add constraint stock_moves_adj_fk foreign key (adjustment_id) references stock_adjustments(id) on delete cascade;
  end if;
end $$;
alter table stock_moves drop constraint if exists stock_moves_kind_check;
alter table stock_moves add constraint stock_moves_kind_check check (kind in
  ('grn', 'bill_adjust', 'debit_note', 'purchase_return', 'reversal', 'preparation', 'production', 'wastage',
   'write_down', 'count', 'sale', 'sales_return', 'opening',
   'overhead'));  -- 'overhead' comes from module 6; listed here so a re-run of this file keeps working
create index if not exists stock_moves_key_idx on stock_moves (item_id, pack_id, move_date);
create index if not exists stock_moves_lot_idx on stock_moves (lot_batch_id) where lot_batch_id is not null;
create index if not exists stock_moves_batch_idx on stock_moves (batch_id) where batch_id is not null;

-- ---------------------------------------------------------------------
-- 3. Posting rules for this module (module 2 listed the main ones)
-- ---------------------------------------------------------------------

insert into posting_rules (event_code, line_key, side, account_code, module, label, sort) values
  ('preparation',  'byproduct',       'debit',  '10030125', 4, 'Sellable by-products into stock (at selling price, AS 2)', 52),
  ('preparation',  'abnormal_loss',   'debit',  '70010150', 4, 'Unusual loss in preparation (not normal wastage)', 53),
  ('production',   'abnormal_loss',   'debit',  '70010150', 4, 'Unusual loss in production (not normal wastage)', 64),
  ('wastage',      'stock_packaging', 'credit', '10030110', 4, 'Bottles and pouches written off', 72),
  ('wastage',      'stock_wip',       'credit', '10030120', 4, 'Prepared ingredients written off', 73),
  ('wastage',      'stock_finished',  'credit', '10030125', 4, 'Finished goods or by-products written off', 74),
  ('stock_count',  'stock_raw',       'debit',  '10030105', 4, 'Count difference: raw materials', 77),
  ('stock_count',  'stock_packaging', 'debit',  '10030110', 4, 'Count difference: bottles and pouches', 78),
  ('stock_count',  'stock_wip',       'debit',  '10030120', 4, 'Count difference: prepared ingredients', 79),
  ('stock_count',  'stock_finished',  'debit',  '10030125', 4, 'Count difference: finished goods and by-products', 79),
  ('write_down',   'expense',         'debit',  '70010150', 4, 'Stock written down to net realisable value (AS 2)', 80),
  ('write_down',   'stock_raw',       'credit', '10030105', 4, 'Write-down: raw materials', 80),
  ('write_down',   'stock_packaging', 'credit', '10030110', 4, 'Write-down: bottles and pouches', 80),
  ('write_down',   'stock_wip',       'credit', '10030120', 4, 'Write-down: prepared ingredients', 80),
  ('write_down',   'stock_finished',  'credit', '10030125', 4, 'Write-down: finished goods and by-products', 80),
  ('opening_stock','stock_raw',       'debit',  '10030105', 4, 'Opening stock at go-live: raw materials', 81),
  ('opening_stock','stock_packaging', 'debit',  '10030110', 4, 'Opening stock at go-live: bottles and pouches', 81),
  ('opening_stock','stock_wip',       'debit',  '10030120', 4, 'Opening stock at go-live: prepared ingredients', 81),
  ('opening_stock','stock_finished',  'debit',  '10030125', 4, 'Opening stock at go-live: finished goods', 81),
  ('opening_stock','clearing',        'credit', '97010105', 4, 'Opening balance clearing (cleared when all opening balances are in)', 82)
on conflict (event_code, line_key) do nothing;
update posting_rules set label = 'Raw materials written off' where event_code = 'wastage' and line_key = 'stock';
update posting_rules set label = 'Stock written off (spoilt, expired, damaged) or unusual loss'
where event_code = 'wastage' and line_key = 'abnormal_loss';

-- ---------------------------------------------------------------------
-- 4. Helpers (private)
-- ---------------------------------------------------------------------

-- Which stock group an item belongs to: raw, packaging, wip or finished
-- (by-products are kept with finished goods).
create or replace function rb_stk_key(p_item int)
returns text language sql stable security definer set search_path = public as $$
  select case kind when 'byproduct' then 'finished' else kind end from items where id = p_item
$$;

-- The posting-rule key for a stock line of an item, e.g. 'stock_wip'.
create or replace function rb_stk_rule(p_event text, p_item int)
returns text language sql stable security definer set search_path = public as $$
  select p_event || '.' || case when p_event = 'wastage' and rb_stk_key(p_item) = 'raw' then 'stock'
                                else 'stock_' || rb_stk_key(p_item) end
$$;

-- "Fish pickle, 200 g bottle" or "Fish pickle (loose)".
create or replace function rb_stk_label(p_item int, p_pack int)
returns text language sql stable security definer set search_path = public as $$
  select i.name || coalesce(', ' || pt.name, case when i.kind = 'finished' then ' (loose)' else '' end)
  from items i left join product_packs pp on pp.id = p_pack left join pack_types pt on pt.id = pp.pack_type_id
  where i.id = p_item
$$;

-- Quantity and value of an item (and pack) in stock, optionally for one
-- preparation batch (p_lot; 0 = stock not tied to a batch), up to a date.
create or replace function rb_stk_bal(p_item int, p_pack int, p_lot bigint, p_date date,
                                      out qty numeric, out value bigint)
language sql stable security definer set search_path = public as $$
  select coalesce(sum(qty_base), 0)::numeric, coalesce(sum(value_paise), 0)::bigint
  from stock_moves
  where item_id = p_item and pack_id is not distinct from p_pack
    and (p_lot is null or (p_lot = 0 and lot_batch_id is null) or lot_batch_id = p_lot)
    and (p_date is null or move_date <= p_date)
$$;

-- Weighted average cost per base unit on a date. When nothing is in
-- stock, the average of everything ever received is used.
create or replace function rb_stk_unit_cost(p_item int, p_pack int, p_date date)
returns numeric language plpgsql stable security definer set search_path = public as $$
declare v_q numeric; v_v bigint;
begin
  select qty, value into v_q, v_v from rb_stk_bal(p_item, p_pack, null, p_date);
  if v_q > 0 then return v_v / v_q; end if;
  return coalesce((select sum(value_paise) / nullif(sum(qty_base), 0) from stock_moves
                   where item_id = p_item and pack_id is not distinct from p_pack and qty_base > 0), 0);
end $$;

-- Net realisable value of a by-product quantity: its loose selling price
-- (per kg, per litre or per piece).
create or replace function rb_stk_nrv(p_item int, p_qty numeric)
returns bigint language sql stable security definer set search_path = public as $$
  select coalesce(round(coalesce(p_qty, 0) * u.to_base / case when u.dimension in ('mass', 'volume') then 1000 else 1 end
                        * i.loose_price_paise)::bigint, 0)
  from items i join units u on u.code = i.base_unit where i.id = p_item
$$;

create or replace function rb_stk_default_dept()
returns int language sql stable security definer set search_path = public as $$
  select rb_pur_default_dept()
$$;

-- Who may see costs and values (margin is for Directors, the FC and the Accountant).
create or replace function rb_stk_cost_ok()
returns boolean language sql stable security definer set search_path = public as $$
  select rb_has('stock.margin') or rb_has('production.margin') or rb_has('accounts.view')
$$;

-- Write a stock movement.
create or replace function rb_stk_move(p_date date, p_item int, p_pack int, p_lot bigint, p_qty numeric, p_value bigint,
                                       p_kind text, p_doc text, p_batch bigint, p_count bigint, p_adj bigint,
                                       p_dept int, p_actor uuid, p_demo boolean, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare v_net numeric;
begin
  if coalesce(p_qty, 0) = 0 and coalesce(p_value, 0) = 0 then return; end if;
  select net_qty into v_net from product_packs where id = p_pack;
  insert into stock_moves (move_date, item_id, pack_id, packs, lot_batch_id, qty_base, value_paise, kind, doc_no, batch_id,
                           count_id, adjustment_id, department_id, note, created_by, is_demo, is_training)
  values (p_date, p_item, p_pack, case when v_net > 0 then round(coalesce(p_qty, 0) / v_net, 3) end, nullif(p_lot, 0),
          coalesce(p_qty, 0), coalesce(p_value, 0), p_kind, p_doc, p_batch, p_count, p_adj, p_dept, p_note, p_actor,
          p_demo, rb_is_training());
end $$;

-- 4300 g -> "4.3 kg", 350 g -> "350 g", 1500 ml -> "1.5 l", for messages.
create or replace function rb_stk_fq(p_q numeric, p_unit text)
returns text language sql immutable as $$
  select case when p_unit in ('g', 'ml') and abs(coalesce(p_q, 0)) >= 1000
              then trim_scale(round(p_q / 1000, 3))::text || case p_unit when 'g' then ' kg' else ' l' end
              else trim_scale(coalesce(p_q, 0))::text || ' ' || p_unit end
$$;

-- Take stock out at weighted average cost. Stock may never go below
-- zero, on the date or after later entries. Prepared ingredients are
-- taken from the batch named (p_lot), or from the oldest batches first.
-- Returns the cost taken out (a positive number).
create or replace function rb_stk_issue(p_date date, p_item int, p_pack int, p_lot bigint, p_qty numeric,
                                        p_kind text, p_doc text, p_batch bigint, p_count bigint, p_adj bigint,
                                        p_dept int, p_actor uuid, p_demo boolean, p_note text)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_q numeric; v_v bigint; v_qn numeric; v_vn bigint; v_total bigint; v_left numeric; v_take numeric;
        v_val bigint; v_done bigint := 0; r record; v_item items; v_lq numeric; v_lv bigint; v_lot_no text;
begin
  if coalesce(p_qty, 0) <= 0 then raise exception 'The quantity taken out must be more than zero.'; end if;
  select * into v_item from items where id = p_item for update;
  if v_item.id is null then raise exception 'Item not found.'; end if;
  select qty, value into v_q, v_v from rb_stk_bal(p_item, p_pack, null, p_date);
  select qty, value into v_qn, v_vn from rb_stk_bal(p_item, p_pack, null, null);
  if v_q < p_qty or v_qn < p_qty then
    raise exception 'Not enough % in stock: % % on hand%, % % needed. Stock cannot go below zero.',
      rb_stk_label(p_item, p_pack), rb_stk_fq(least(v_q, v_qn), v_item.base_unit), '',
      case when v_qn < v_q then ' after later entries' else ' on ' || to_char(p_date, 'DD-Mon-YYYY') end,
      rb_stk_fq(p_qty, v_item.base_unit), '';
  end if;
  v_total := case when p_qty = v_q then v_v else round(p_qty * v_v / v_q)::bigint end;
  if v_item.kind <> 'wip' then
    perform rb_stk_move(p_date, p_item, p_pack, null, -p_qty, -v_total, p_kind, p_doc, p_batch, p_count, p_adj,
                        p_dept, p_actor, p_demo, p_note);
    return v_total;
  end if;
  if p_lot is not null then
    select qty, value into v_lq, v_lv from rb_stk_bal(p_item, null, p_lot, null);
    if v_lq < p_qty then
      select batch_no into v_lot_no from production_batches where id = p_lot;
      raise exception '% from batch % has only % % left.', v_item.name, coalesce(v_lot_no, 'without a batch'),
        trim_scale(v_lq), v_item.base_unit;
    end if;
    perform rb_stk_move(p_date, p_item, null, p_lot, -p_qty, -v_total, p_kind, p_doc, p_batch, p_count, p_adj,
                        p_dept, p_actor, p_demo, p_note);
    return v_total;
  end if;
  v_left := p_qty;
  for r in select m.lot_batch_id, sum(m.qty_base) q from stock_moves m
           left join production_batches b on b.id = m.lot_batch_id
           where m.item_id = p_item and m.pack_id is null
           group by m.lot_batch_id, b.batch_date having sum(m.qty_base) > 0
           order by b.batch_date nulls first, m.lot_batch_id nulls first loop
    exit when v_left <= 0;
    v_take := least(v_left, r.q);
    v_left := v_left - v_take;
    v_val := case when v_left = 0 then v_total - v_done else round(v_total * v_take / p_qty)::bigint end;
    perform rb_stk_move(p_date, p_item, null, coalesce(r.lot_batch_id, 0), -v_take, -v_val, p_kind, p_doc, p_batch,
                        p_count, p_adj, p_dept, p_actor, p_demo, p_note);
    v_done := v_done + v_val;
  end loop;
  if v_left > 0 then raise exception 'The batches of % do not add up. Please tell the Accountant.', v_item.name; end if;
  return v_total;
end $$;

-- Stock may not go below zero after a reversal or deletion takes stock
-- back out: check every item, pack and preparation batch touched.
create or replace function rb_stk_assert_not_negative(p_items int[])
returns void language plpgsql stable security definer set search_path = public as $$
declare r record;
begin
  select item_id, pack_id, lot_batch_id, sum(qty_base) q into r from stock_moves
  where item_id = any (p_items) group by item_id, pack_id, lot_batch_id having sum(qty_base) < 0 limit 1;
  if found then
    raise exception 'This would leave % below zero (% %): some of it has already been used or sold. Reverse those entries first.',
      rb_stk_label(r.item_id, r.pack_id) || coalesce(', batch ' || (select batch_no from production_batches where id = r.lot_batch_id), ''),
      trim_scale(r.q), (select base_unit from items where id = r.item_id);
  end if;
end $$;

-- Quantity in an item's base unit, from what the screen sent: either
-- qty + unit, or packs of a product pack.
create or replace function rb_stk_qty(p_item int, l jsonb, p_qty_key text default 'qty', p_unit_key text default 'unit')
returns numeric language plpgsql stable security definer set search_path = public as $$
declare v_q numeric := nullif(trim(l->>p_qty_key), '')::numeric; v_u text := rb_txt(l, p_unit_key);
begin
  if v_q is null then return null; end if;
  if v_q < 0 then raise exception 'Quantities cannot be negative.'; end if;
  return rb_pur_base_qty(p_item, coalesce(v_u, (select base_unit from items where id = p_item)), v_q);
end $$;

-- A wastage figure typed on the screen, in the item's base unit (blank = 0).
create or replace function rb_stk_wq(p_item int, p_unit text, p_val text)
returns numeric language sql stable security definer set search_path = public as $$
  select case when nullif(trim(p_val), '') is null then 0 else rb_pur_base_qty(p_item, p_unit, trim(p_val)::numeric) end
$$;

-- ---------------------------------------------------------------------
-- 5. Preparation and final production (private versions take the actor,
--    so the DEMO data can use them; the screens call the rb_ ones)
-- ---------------------------------------------------------------------

-- Preparation: one raw material in, one prepared ingredient (WIP) out.
-- p: batch_date, department_id, raw_item_id, raw_qty, raw_unit, output_item_id,
--    output_qty, output_unit, waste_unit, stages [{stage, wastage}],
--    byproducts [{item_id, stage, qty, unit}], abnormal_qty, abnormal_reason, note
create or replace function rb_stk_save_prep(p jsonb, p_actor uuid, p_demo boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_date date := (p->>'batch_date')::date; v_raw items; v_out items; v_bp items;
        v_dept int := coalesce(rb_int(p, 'department_id')::int, rb_stk_default_dept());
        v_in numeric; v_outq numeric; v_abn numeric; v_wu text := coalesce(rb_txt(p, 'waste_unit'), 'g');
        s jsonb; b jsonb; i int := 0; v_w numeric; v_wsum numeric := 0; v_bq numeric; v_bpsum numeric := 0;
        v_cost bigint; v_bpval bigint := 0; v_abnval bigint := 0; v_outval bigint; v_val bigint; v_no text;
        v_lines jsonb := '[]'; v_j bigint; r record;
begin
  if v_date is null then raise exception 'Please choose the date.'; end if;
  perform rb_assert_period_open(v_date);
  select * into v_raw from items where id = rb_int(p, 'raw_item_id');
  if v_raw.id is null then raise exception 'Please choose the raw material.'; end if;
  if v_raw.kind <> 'raw' then raise exception 'Preparation starts from a raw material.'; end if;
  select * into v_out from items where id = coalesce(rb_int(p, 'output_item_id')::int, v_raw.prepared_item_id);
  if v_out.id is null then
    raise exception 'Choose the prepared ingredient it becomes (or set it on the raw material in Masters → Items).';
  end if;
  if v_out.kind <> 'wip' then raise exception '% is not a prepared ingredient (work in progress).', v_out.name; end if;
  if not v_out.is_active then raise exception '% is switched off in Masters.', v_out.name; end if;
  v_in := rb_stk_qty(v_raw.id, p, 'raw_qty', 'raw_unit');
  if coalesce(v_in, 0) <= 0 then raise exception 'Enter how much % went in.', v_raw.name; end if;
  v_outq := rb_stk_qty(v_out.id, p, 'output_qty', 'output_unit');
  if coalesce(v_outq, 0) <= 0 then raise exception 'Enter how much % came out.', v_out.name; end if;
  v_abn := rb_stk_wq(v_raw.id, v_wu, p->>'abnormal_qty');
  if v_abn < 0 then raise exception 'Quantities cannot be negative.'; end if;
  if v_abn > 0 and rb_txt(p, 'abnormal_reason') is null then
    raise exception 'Say what the unusual loss was (for example "tray dropped").';
  end if;

  v_no := rb_next_doc_no(rb_pur_series('PRP', p_demo), v_date);
  insert into production_batches (batch_no, kind, batch_date, department_id, output_item_id, input_qty_base, output_qty_base,
                                  abnormal_qty_base, abnormal_reason, note, entered_by, is_demo, is_training)
  values (v_no, 'preparation', v_date, v_dept, v_out.id, v_in, v_outq, v_abn, rb_txt(p, 'abnormal_reason'),
          rb_txt(p, 'note'), p_actor, p_demo, rb_is_training())
  returning id into v_id;

  -- Wastage at each stage (stays in the batch cost: it is normal).
  for s in select * from jsonb_array_elements(coalesce(p->'stages', '[]')) loop
    v_w := rb_stk_wq(v_raw.id, v_wu, s->>'wastage');
    if v_w < 0 then raise exception 'Wastage cannot be negative.'; end if;
    if rb_txt(s, 'stage') is null then continue; end if;
    i := i + 1;
    insert into batch_stages (batch_id, stage_no, stage, wastage_qty_base, is_demo, is_training)
    values (v_id, i, rb_txt(s, 'stage'), v_w, p_demo, rb_is_training());
    v_wsum := v_wsum + v_w;
  end loop;

  -- The raw material goes in at weighted average cost.
  v_cost := rb_stk_issue(v_date, v_raw.id, null, null, v_in, 'preparation', v_no, v_id, null, null, v_dept, p_actor, p_demo, null);
  insert into batch_lines (batch_id, line_no, role, item_id, qty_base, value_paise, is_demo, is_training)
  values (v_id, 1, 'input', v_raw.id, v_in, v_cost, p_demo, rb_is_training());
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'preparation.stock_raw', 'amount_paise', v_cost,
    'item_id', v_raw.id, 'narration', trim_scale(v_in) || ' ' || v_raw.base_unit || ' ' || v_raw.name || ' in'));

  -- An unusual loss is taken out of the batch cost (AS 2: abnormal waste is not inventory cost).
  if v_abn > 0 then v_abnval := round(v_cost * v_abn / v_in)::bigint; end if;

  -- By-products: sellable ones into stock at their selling price, taken off the main cost.
  i := 1;
  for b in select * from jsonb_array_elements(coalesce(p->'byproducts', '[]')) loop
    if rb_int(b, 'item_id') is null then continue; end if;
    select * into v_bp from items where id = rb_int(b, 'item_id');
    if v_bp.kind <> 'byproduct' then raise exception '% is not a by-product item.', coalesce(v_bp.name, 'That item'); end if;
    v_bq := rb_stk_qty(v_bp.id, b);
    if coalesce(v_bq, 0) <= 0 then raise exception 'Enter the quantity of %.', v_bp.name; end if;
    v_val := case when v_bp.byproduct_use = 'sellable' then rb_stk_nrv(v_bp.id, v_bq) else 0 end;
    v_val := least(v_val, greatest(v_cost - v_abnval - v_bpval, 0));
    i := i + 1;
    insert into batch_lines (batch_id, line_no, role, item_id, qty_base, stage, byproduct_use, value_paise, is_demo, is_training)
    values (v_id, i, 'byproduct', v_bp.id, v_bq, rb_txt(b, 'stage'), coalesce(v_bp.byproduct_use, 'discarded'), v_val, p_demo, rb_is_training());
    v_bpsum := v_bpsum + v_bq;
    if v_bp.byproduct_use = 'sellable' then
      perform rb_stk_move(v_date, v_bp.id, null, null, v_bq, v_val, 'preparation', v_no, v_id, null, null, v_dept, p_actor, p_demo, null);
      if v_val > 0 then
        v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'preparation.byproduct', 'amount_paise', v_val,
          'item_id', v_bp.id, 'narration', trim_scale(v_bq) || ' ' || v_bp.base_unit || ' ' || v_bp.name || ' (by-product)'));
      end if;
      v_bpval := v_bpval + v_val;
    end if;
  end loop;

  -- The prepared ingredient carries the rest of the cost, as its own batch.
  v_outval := v_cost - v_abnval - v_bpval;
  i := i + 1;
  insert into batch_lines (batch_id, line_no, role, item_id, qty_base, value_paise, lot_batch_id, is_demo, is_training)
  values (v_id, i, 'output', v_out.id, v_outq, v_outval, v_id, p_demo, rb_is_training());
  perform rb_stk_move(v_date, v_out.id, null, v_id, v_outq, v_outval, 'preparation', v_no, v_id, null, null, v_dept, p_actor, p_demo, null);
  if v_outval > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'preparation.wip', 'amount_paise', v_outval,
      'item_id', v_out.id, 'narration', trim_scale(v_outq) || ' ' || v_out.base_unit || ' ' || v_out.name || ' made'));
  end if;
  if v_abnval > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'preparation.abnormal_loss', 'amount_paise', v_abnval,
      'narration', 'Unusual loss: ' || rb_txt(p, 'abnormal_reason')));
  end if;
  if v_cost > 0 then
    v_j := rb_post_engine(jsonb_build_object('journal_date', v_date, 'source', 'production', 'event_code', 'preparation',
      'source_ref', v_no, 'narration', 'Preparation ' || v_no || ': ' || v_raw.name || ' into ' || v_out.name,
      'department_id', v_dept, 'is_demo', p_demo, 'entered_by', p_actor, 'approved_by', p_actor), v_lines);
    update stock_moves set journal_id = v_j where batch_id = v_id;
  end if;
  update production_batches set wastage_qty_base = v_wsum, byproduct_qty_base = v_bpsum, input_value_paise = v_cost,
    byproduct_value_paise = v_bpval, abnormal_value_paise = v_abnval, output_value_paise = v_outval, journal_id = v_j
  where id = v_id;
  perform rb_audit_write('PREPARATION', 'production_batches', v_id::text, null,
    jsonb_build_object('batch_no', v_no, 'raw', v_raw.name, 'in', v_in, 'out', v_outq, 'prepared', v_out.name), null);
  return v_id;
end $$;

-- Final production: prepared ingredients, raw materials (and extra
-- packaging such as labels) in; one finished product out, in packs
-- and / or loose. Each pack uses one empty bottle or pouch.
-- p: batch_date, department_id, output_item_id, inputs [{item_id, lot_batch_id, qty, unit}],
--    outputs [{pack_id, packs} or {pack_id: null, qty, unit}], waste_unit, shrinkage_qty,
--    packing_waste_qty, abnormal_qty, abnormal_reason, note, linked_batch_id
create or replace function rb_stk_save_production(p jsonb, p_actor uuid, p_demo boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_date date := (p->>'batch_date')::date; v_fg items; v_it items; v_pp product_packs;
        v_dept int := coalesce(rb_int(p, 'department_id')::int, rb_stk_default_dept());
        v_wu text := coalesce(rb_txt(p, 'waste_unit'), 'g'); l jsonb; i int := 0; v_q numeric; v_val bigint;
        v_content bigint := 0; v_pack_total bigint := 0; v_outq numeric := 0; v_abn numeric; v_abnval bigint := 0;
        v_shr numeric; v_pkw numeric; v_no text; v_lines jsonb := '[]'; v_j bigint; v_mark bigint;
        v_pk_item int; v_pk_val bigint; v_share bigint; v_done bigint := 0; v_n int; v_k int := 0; r record;
        v_outs jsonb := '[]'; v_inq numeric := 0;
begin
  if v_date is null then raise exception 'Please choose the date.'; end if;
  perform rb_assert_period_open(v_date);
  select * into v_fg from items where id = rb_int(p, 'output_item_id');
  if v_fg.id is null then raise exception 'Please choose the finished product.'; end if;
  if v_fg.kind <> 'finished' then raise exception '% is not a finished product.', v_fg.name; end if;
  if not v_fg.is_active then raise exception '% is switched off in Masters.', v_fg.name; end if;
  if jsonb_array_length(coalesce(p->'inputs', '[]')) = 0 then raise exception 'Add what went in.'; end if;

  -- What comes out, checked before anything is taken from stock.
  for l in select * from jsonb_array_elements(coalesce(p->'outputs', '[]')) loop
    if rb_int(l, 'pack_id') is not null then
      select * into v_pp from product_packs where id = rb_int(l, 'pack_id');
      if v_pp.id is null or v_pp.item_id <> v_fg.id then raise exception 'That pack is not set up for %.', v_fg.name; end if;
      if not v_pp.is_active then raise exception 'That pack of % is switched off in Masters.', v_fg.name; end if;
      v_q := nullif(trim(l->>'packs'), '')::numeric;
      if v_q is null or v_q = 0 then continue; end if;
      if v_q < 0 or v_q <> trunc(v_q) then raise exception 'Packs are whole numbers.'; end if;
      v_outs := v_outs || jsonb_build_array(jsonb_build_object('pack_id', v_pp.id, 'packs', v_q, 'qty', v_q * v_pp.net_qty));
      v_outq := v_outq + v_q * v_pp.net_qty;
    else
      v_q := rb_stk_qty(v_fg.id, l);
      if coalesce(v_q, 0) = 0 then continue; end if;
      if v_fg.sells_by = 'pack' then
        raise exception '% is sold only in packs. Add its loose sale in Masters (sold by weight) first.', v_fg.name;
      end if;
      v_outs := v_outs || jsonb_build_array(jsonb_build_object('pack_id', null, 'qty', v_q));
      v_outq := v_outq + v_q;
    end if;
  end loop;
  if v_outq <= 0 then raise exception 'Enter how many packs (or how much loose) of % were made.', v_fg.name; end if;
  v_shr := rb_stk_wq(v_fg.id, v_wu, p->>'shrinkage_qty');
  v_pkw := rb_stk_wq(v_fg.id, v_wu, p->>'packing_waste_qty');
  v_abn := rb_stk_wq(v_fg.id, v_wu, p->>'abnormal_qty');
  if v_shr < 0 or v_pkw < 0 or v_abn < 0 then raise exception 'Quantities cannot be negative.'; end if;
  if v_abn > 0 and rb_txt(p, 'abnormal_reason') is null then
    raise exception 'Say what the unusual loss was (for example "batch burnt").';
  end if;

  v_no := rb_next_doc_no(rb_pur_series('PRD', p_demo), v_date);
  insert into production_batches (batch_no, kind, batch_date, department_id, output_item_id, output_qty_base, wastage_qty_base,
                                  shrinkage_qty_base, packing_waste_qty_base, abnormal_qty_base, abnormal_reason, note,
                                  linked_batch_id, entered_by, is_demo, is_training)
  values (v_no, 'production', v_date, v_dept, v_fg.id, v_outq, v_shr + v_pkw, v_shr, v_pkw, v_abn, rb_txt(p, 'abnormal_reason'),
          rb_txt(p, 'note'), rb_int(p, 'linked_batch_id'), p_actor, p_demo, rb_is_training())
  returning id into v_id;

  -- Inputs at weighted average cost (prepared ones batch by batch).
  for l in select * from jsonb_array_elements(p->'inputs') loop
    if rb_int(l, 'item_id') is null then continue; end if;
    select * into v_it from items where id = rb_int(l, 'item_id');
    if v_it.kind not in ('raw', 'wip', 'packaging') then
      raise exception '% cannot go into production (only raw materials, prepared ingredients and packaging).', v_it.name;
    end if;
    if v_it.id = v_fg.id then raise exception 'A product cannot go into itself.'; end if;
    v_q := rb_stk_qty(v_it.id, l);
    if coalesce(v_q, 0) <= 0 then raise exception 'Enter how much % went in.', v_it.name; end if;
    v_mark := coalesce((select max(id) from stock_moves), 0);
    v_val := rb_stk_issue(v_date, v_it.id, null, case when v_it.kind = 'wip' then rb_int(l, 'lot_batch_id') end, v_q,
                          'production', v_no, v_id, null, null, v_dept, p_actor, p_demo, null);
    for r in select lot_batch_id, -qty_base q, -value_paise v from stock_moves
             where id > v_mark and batch_id = v_id and item_id = v_it.id order by id loop
      i := i + 1;
      insert into batch_lines (batch_id, line_no, role, item_id, lot_batch_id, qty_base, value_paise, is_demo, is_training)
      values (v_id, i, 'input', v_it.id, r.lot_batch_id, r.q, r.v, p_demo, rb_is_training());
    end loop;
    if v_it.kind = 'packaging' then v_pack_total := v_pack_total + v_val; else v_content := v_content + v_val; end if;
    v_inq := v_inq + case when v_it.kind = 'packaging' then 0 else v_q end;
    if v_val > 0 then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object(
        'rule', 'production.' || case v_it.kind when 'wip' then 'wip' when 'packaging' then 'packaging' else 'stock_raw' end,
        'amount_paise', v_val, 'item_id', v_it.id, 'narration', trim_scale(v_q) || ' ' || v_it.base_unit || ' ' || v_it.name || ' in'));
    end if;
  end loop;

  -- An unusual loss is charged to expense, in proportion to the product made.
  if v_abn > 0 then v_abnval := round(v_content * v_abn / (v_outq + v_abn))::bigint; end if;

  -- Outputs: contents shared by weight; each pack adds its own bottle or pouch.
  v_n := jsonb_array_length(v_outs);
  for l in select * from jsonb_array_elements(v_outs) loop
    v_k := v_k + 1;
    v_q := (l->>'qty')::numeric;
    v_share := case when v_k = v_n then v_content - v_abnval - v_done
                    else round((v_content - v_abnval) * v_q / v_outq)::bigint end;
    v_done := v_done + v_share;
    v_pk_val := 0; v_pk_item := null;
    if rb_int(l, 'pack_id') is not null then
      select pt.packaging_item_id into v_pk_item from product_packs pp join pack_types pt on pt.id = pp.pack_type_id
      where pp.id = rb_int(l, 'pack_id');
      if v_pk_item is not null then
        v_pk_val := rb_stk_issue(v_date, v_pk_item, null, null, (l->>'packs')::numeric, 'production', v_no, v_id, null, null,
                                 v_dept, p_actor, p_demo, 'Packs for ' || rb_stk_label(v_fg.id, rb_int(l, 'pack_id')::int));
        i := i + 1;
        insert into batch_lines (batch_id, line_no, role, item_id, pack_id, packs, qty_base, value_paise, is_demo, is_training)
        values (v_id, i, 'packaging', v_pk_item, rb_int(l, 'pack_id'), (l->>'packs')::numeric, (l->>'packs')::numeric, v_pk_val,
                p_demo, rb_is_training());
        v_pack_total := v_pack_total + v_pk_val;
        if v_pk_val > 0 then
          v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'production.packaging', 'amount_paise', v_pk_val,
            'item_id', v_pk_item, 'narration', trim_scale((l->>'packs')::numeric) || ' ' || (select name from items where id = v_pk_item) || ' used'));
        end if;
      end if;
    end if;
    i := i + 1;
    insert into batch_lines (batch_id, line_no, role, item_id, pack_id, packs, qty_base, value_paise, is_demo, is_training)
    values (v_id, i, 'output', v_fg.id, rb_int(l, 'pack_id'), nullif(l->>'packs', '')::numeric, v_q, v_share + v_pk_val,
            p_demo, rb_is_training());
    perform rb_stk_move(v_date, v_fg.id, rb_int(l, 'pack_id')::int, null, v_q, v_share + v_pk_val, 'production', v_no, v_id,
                        null, null, v_dept, p_actor, p_demo, null);
    if v_share + v_pk_val > 0 then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'production.finished', 'amount_paise', v_share + v_pk_val,
        'item_id', v_fg.id, 'narration', coalesce(trim_scale((l->>'packs')::numeric) || ' × ', trim_scale(v_q) || ' ' || v_fg.base_unit || ' ')
          || rb_stk_label(v_fg.id, rb_int(l, 'pack_id')::int) || ' made'));
    end if;
  end loop;
  if v_abnval > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'production.abnormal_loss', 'amount_paise', v_abnval,
      'narration', 'Unusual loss: ' || rb_txt(p, 'abnormal_reason')));
  end if;
  if v_content + v_pack_total > 0 then
    v_j := rb_post_engine(jsonb_build_object('journal_date', v_date, 'source', 'production', 'event_code', 'production',
      'source_ref', v_no, 'narration', 'Production ' || v_no || ': ' || v_fg.name,
      'department_id', v_dept, 'is_demo', p_demo, 'entered_by', p_actor, 'approved_by', p_actor), v_lines);
    update stock_moves set journal_id = v_j where batch_id = v_id;
  end if;
  update production_batches set input_qty_base = v_inq, input_value_paise = v_content + v_pack_total,
    packaging_value_paise = v_pack_total, abnormal_value_paise = v_abnval,
    output_value_paise = v_content + v_pack_total - v_abnval, journal_id = v_j
  where id = v_id;
  if rb_int(p, 'linked_batch_id') is not null then
    update production_batches set linked_batch_id = v_id where id = rb_int(p, 'linked_batch_id') and kind = 'preparation';
  end if;
  perform rb_audit_write('PRODUCTION', 'production_batches', v_id::text, null,
    jsonb_build_object('batch_no', v_no, 'product', v_fg.name, 'made', v_outq), null);
  return v_id;
end $$;

-- Prepare and produce together (same-day items such as fish and chicken):
-- the preparation batch, then the production batch that uses it.
-- p: { prep: {...as rb_stk_save_prep}, production: {...as rb_stk_save_production},
--      used_qty, used_unit (default: all that was prepared) }
create or replace function rb_stk_save_combined(p jsonb, p_actor uuid, p_demo boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_prep bigint; v_prod bigint; v_b production_batches; v_used numeric; v_pr jsonb := p->'production';
begin
  if p->'prep' is null or v_pr is null then raise exception 'Fill in both the preparation and the production part.'; end if;
  if (p->'prep'->>'batch_date') is distinct from (v_pr->>'batch_date') and v_pr->>'batch_date' is not null then
    raise exception 'Prepare and produce together is for the same day: use one date.';
  end if;
  v_prep := rb_stk_save_prep(p->'prep', p_actor, p_demo);
  select * into v_b from production_batches where id = v_prep;
  v_used := coalesce(rb_stk_qty(v_b.output_item_id, p, 'used_qty', 'used_unit'), v_b.output_qty_base);
  if v_used > v_b.output_qty_base then raise exception 'You cannot use more than was prepared.'; end if;
  v_pr := v_pr || jsonb_build_object('batch_date', v_b.batch_date, 'linked_batch_id', v_prep,
    'department_id', coalesce(v_pr->'department_id', to_jsonb(v_b.department_id)),
    'inputs', jsonb_build_array(jsonb_build_object('item_id', v_b.output_item_id, 'lot_batch_id', v_prep, 'qty', v_used, 'unit',
              (select base_unit from items where id = v_b.output_item_id))) || coalesce(v_pr->'inputs', '[]'));
  v_prod := rb_stk_save_production(v_pr, p_actor, p_demo);
  return jsonb_build_object('preparation_id', v_prep, 'production_id', v_prod);
end $$;

-- ---------------------------------------------------------------------
-- 6. Stock counts, opening stock, write-offs and write-downs
-- ---------------------------------------------------------------------

-- Save a count (draft). p: id, purpose, count_date, department_id, note,
-- lines [{item_id, pack_id, packs | qty + unit, rate_paise (opening: cost per unit), reason}]
create or replace function rb_stk_save_count(p jsonb, p_actor uuid, p_demo boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint := rb_int(p, 'id'); v_c stock_counts; v_date date := (p->>'count_date')::date; l jsonb; i int := 0;
        v_it items; v_pp product_packs; v_q numeric; v_purpose text := coalesce(rb_txt(p, 'purpose'), 'count');
        v_rate numeric; v_unitq numeric; v_dept int := coalesce(rb_int(p, 'department_id')::int, rb_stk_default_dept());
begin
  if v_date is null then raise exception 'Please choose the date of the count.'; end if;
  if v_purpose not in ('count', 'opening') then raise exception 'Unknown kind of count.'; end if;
  perform rb_assert_period_open(v_date);
  if v_id is not null then
    select * into v_c from stock_counts where id = v_id for update;
    if v_c.id is null then raise exception 'Count not found.'; end if;
    if v_c.status <> 'draft' then raise exception 'Only a count that is not posted yet can be changed.'; end if;
    update stock_counts set count_date = v_date, purpose = v_purpose, department_id = v_dept, note = rb_txt(p, 'note'),
      updated_at = now(), updated_by = p_actor where id = v_id;
    delete from stock_count_lines where count_id = v_id;
  else
    insert into stock_counts (count_no, purpose, count_date, department_id, note, entered_by, is_demo, is_training)
    values (rb_next_doc_no(rb_pur_series(case when v_purpose = 'opening' then 'OS' else 'SC' end, p_demo), v_date),
            v_purpose, v_date, v_dept, rb_txt(p, 'note'), p_actor, p_demo, rb_is_training())
    returning id into v_id;
  end if;
  for l in select * from jsonb_array_elements(coalesce(p->'lines', '[]')) loop
    if rb_int(l, 'item_id') is null then continue; end if;
    if nullif(trim(l->>'packs'), '') is null and nullif(trim(l->>'qty'), '') is null then continue; end if;  -- not counted
    select * into v_it from items where id = rb_int(l, 'item_id');
    if v_it.id is null then raise exception 'Item not found.'; end if;
    v_pp := null;
    if rb_int(l, 'pack_id') is not null then
      select * into v_pp from product_packs where id = rb_int(l, 'pack_id') and item_id = v_it.id;
      if v_pp.id is null then raise exception 'That pack is not set up for %.', v_it.name; end if;
      v_q := nullif(trim(l->>'packs'), '')::numeric * v_pp.net_qty;
    else
      v_q := rb_stk_qty(v_it.id, l);
    end if;
    if v_q is null or v_q < 0 then raise exception 'Line %: enter the quantity counted (0 if there is none).', i + 1; end if;
    if exists (select 1 from stock_count_lines where count_id = v_id and item_id = v_it.id and pack_id is not distinct from v_pp.id) then
      raise exception '% is on the count twice.', rb_stk_label(v_it.id, v_pp.id);
    end if;
    v_rate := null;
    if v_purpose = 'opening' then
      if nullif(trim(l->>'rate_paise'), '') is null then raise exception 'Opening stock needs the cost of %.', rb_stk_label(v_it.id, v_pp.id); end if;
      -- the rate is per pack, or per unit the quantity was given in
      v_unitq := case when v_pp.id is not null then v_pp.net_qty
                      else rb_pur_base_qty(v_it.id, coalesce(rb_txt(l, 'unit'), v_it.base_unit), 1) end;
      v_rate := (l->>'rate_paise')::numeric / v_unitq;
      if v_rate < 0 then raise exception 'Costs cannot be negative.'; end if;
    end if;
    i := i + 1;
    insert into stock_count_lines (count_id, line_no, item_id, pack_id, counted_qty_base, unit_cost_paise, value_paise, reason,
                                   is_demo, is_training)
    values (v_id, i, v_it.id, v_pp.id, v_q, v_rate, case when v_rate is not null then round(v_q * v_rate)::bigint else 0 end,
            rb_txt(l, 'reason'), p_demo, rb_is_training());
  end loop;
  if i = 0 then raise exception 'Enter at least one counted quantity.'; end if;
  return v_id;
end $$;

-- Post a count: each difference against stock on the count date is
-- taken out (shortage) or added (excess) at weighted average cost.
-- Opening stock adds what was counted at the cost given.
create or replace function rb_stk_post_count(p_id bigint, p_actor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_c stock_counts; l stock_count_lines; v_sys numeric; v_sv bigint; v_diff numeric; v_val bigint; v_cost numeric;
        v_lines jsonb := '[]'; v_short bigint := 0; v_excess bigint := 0; v_j bigint; v_open bigint := 0;
begin
  select * into v_c from stock_counts where id = p_id for update;
  if v_c.id is null then raise exception 'Count not found.'; end if;
  if v_c.status <> 'draft' then raise exception 'This count is already posted or cancelled.'; end if;
  perform rb_assert_period_open(v_c.count_date);
  for l in select * from stock_count_lines where count_id = p_id order by line_no loop
    select qty, value into v_sys, v_sv from rb_stk_bal(l.item_id, l.pack_id, null, v_c.count_date);
    if v_c.purpose = 'opening' then
      v_val := l.value_paise;
      perform rb_stk_move(v_c.count_date, l.item_id, l.pack_id, null, l.counted_qty_base, v_val, 'opening', v_c.count_no,
                          null, p_id, null, v_c.department_id, p_actor, v_c.is_demo, 'Opening stock');
      update stock_count_lines set system_qty_base = v_sys, diff_qty_base = l.counted_qty_base where id = l.id;
      if v_val > 0 then
        v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', rb_stk_rule('opening_stock', l.item_id), 'amount_paise', v_val,
          'item_id', l.item_id, 'narration', 'Opening stock: ' || trim_scale(l.counted_qty_base) || ' ' || rb_stk_label(l.item_id, l.pack_id)));
        v_open := v_open + v_val;
      end if;
      continue;
    end if;
    v_diff := l.counted_qty_base - v_sys;
    v_val := 0;
    if v_diff < 0 then
      v_val := -rb_stk_issue(v_c.count_date, l.item_id, l.pack_id, null, -v_diff, 'count', v_c.count_no, null, p_id, null,
                             v_c.department_id, p_actor, v_c.is_demo, coalesce(l.reason, 'Count shortage'));
      v_short := v_short - v_val;
    elsif v_diff > 0 then
      v_cost := rb_stk_unit_cost(l.item_id, l.pack_id, v_c.count_date);
      v_val := round(v_diff * v_cost)::bigint;
      perform rb_stk_move(v_c.count_date, l.item_id, l.pack_id, null, v_diff, v_val, 'count', v_c.count_no, null, p_id, null,
                          v_c.department_id, p_actor, v_c.is_demo, coalesce(l.reason, 'Count excess'));
      v_excess := v_excess + v_val;
    end if;
    update stock_count_lines set system_qty_base = v_sys, diff_qty_base = v_diff, value_paise = v_val where id = l.id;
    if v_val <> 0 then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', rb_stk_rule('stock_count', l.item_id), 'amount_paise', v_val,
        'item_id', l.item_id, 'narration', rb_stk_label(l.item_id, l.pack_id) || ': counted ' || trim_scale(l.counted_qty_base) ||
          ', books ' || trim_scale(v_sys)));
    end if;
  end loop;
  if v_short > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'stock_count.shortage', 'amount_paise', v_short));
  end if;
  if v_excess > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'stock_count.excess', 'amount_paise', v_excess));
  end if;
  if v_open > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('rule', 'opening_stock.clearing', 'amount_paise', v_open));
  end if;
  if jsonb_array_length(v_lines) >= 2 then
    v_j := rb_post_engine(jsonb_build_object('journal_date', v_c.count_date, 'source', 'stock',
      'event_code', case when v_c.purpose = 'opening' then 'opening_stock' else 'stock_count' end,
      'source_ref', v_c.count_no, 'narration', case when v_c.purpose = 'opening' then 'Opening stock ' else 'Stock count ' end || v_c.count_no,
      'department_id', v_c.department_id, 'is_demo', v_c.is_demo, 'entered_by', v_c.entered_by, 'approved_by', p_actor), v_lines);
    update stock_moves set journal_id = v_j where count_id = p_id;
  end if;
  update stock_counts set status = 'posted', approved_by = p_actor, posted_at = now(), journal_id = v_j,
    short_paise = v_short, excess_paise = v_excess + v_open where id = p_id;
  perform rb_audit_write('POST_STOCK_COUNT', 'stock_counts', p_id::text, null,
    jsonb_build_object('count_no', v_c.count_no, 'shortage_paise', v_short, 'excess_paise', v_excess, 'opening_paise', v_open), null);
end $$;

-- Save a write-off or write-down. Posts at once when the person may
-- approve their own entries; otherwise it waits for approval.
-- p: kind, adj_date, item_id, pack_id, lot_batch_id, qty + unit (or packs), value_paise (write-down), reason, department_id
create or replace function rb_stk_save_adjustment(p jsonb, p_actor uuid, p_demo boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_kind text := rb_txt(p, 'kind'); v_date date := (p->>'adj_date')::date; v_it items; v_pp product_packs;
        v_q numeric := 0; v_v bigint := 0; v_dept int := coalesce(rb_int(p, 'department_id')::int, rb_stk_default_dept());
        v_bq numeric; v_bv bigint;
begin
  if v_kind not in ('write_off', 'write_down') then raise exception 'Choose write-off or write-down.'; end if;
  if v_date is null then raise exception 'Please choose the date.'; end if;
  if rb_txt(p, 'reason') is null then raise exception 'Please give the reason.'; end if;
  perform rb_assert_period_open(v_date);
  select * into v_it from items where id = rb_int(p, 'item_id');
  if v_it.id is null then raise exception 'Please choose the item.'; end if;
  if rb_int(p, 'pack_id') is not null then
    select * into v_pp from product_packs where id = rb_int(p, 'pack_id') and item_id = v_it.id;
    if v_pp.id is null then raise exception 'That pack is not set up for %.', v_it.name; end if;
  end if;
  select qty, value into v_bq, v_bv from rb_stk_bal(v_it.id, v_pp.id, null, v_date);
  if v_kind = 'write_off' then
    v_q := case when v_pp.id is not null and nullif(trim(p->>'packs'), '') is not null
                then (p->>'packs')::numeric * v_pp.net_qty else rb_stk_qty(v_it.id, p) end;
    if coalesce(v_q, 0) <= 0 then raise exception 'Enter how much is written off.'; end if;
    if v_q > v_bq then raise exception 'Only % % of % is in stock.', trim_scale(v_bq), v_it.base_unit, rb_stk_label(v_it.id, v_pp.id); end if;
  else
    v_v := rb_int(p, 'value_paise');
    if coalesce(v_v, 0) <= 0 then raise exception 'Enter the amount to write the stock down by.'; end if;
    if v_v > v_bv then raise exception 'The write-down cannot be more than the stock''s cost (%).', rb_pur_fmt(v_bv); end if;
  end if;
  insert into stock_adjustments (adj_no, kind, adj_date, item_id, pack_id, lot_batch_id, qty_base, value_paise, reason,
                                 department_id, entered_by, is_demo, is_training)
  values (rb_next_doc_no(rb_pur_series(case when v_kind = 'write_off' then 'WO' else 'WD' end, p_demo), v_date),
          v_kind, v_date, v_it.id, v_pp.id, case when v_it.kind = 'wip' then rb_int(p, 'lot_batch_id') end, v_q, v_v,
          rb_txt(p, 'reason'), v_dept, p_actor, p_demo, rb_is_training())
  returning id into v_id;
  return v_id;
end $$;

create or replace function rb_stk_post_adjustment(p_id bigint, p_actor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_a stock_adjustments; v_val bigint; v_j bigint; v_lines jsonb;
begin
  select * into v_a from stock_adjustments where id = p_id for update;
  if v_a.id is null then raise exception 'Not found.'; end if;
  if v_a.status <> 'awaiting_approval' then raise exception 'This is not waiting for approval.'; end if;
  perform rb_assert_period_open(v_a.adj_date);
  if v_a.kind = 'write_off' then
    v_val := rb_stk_issue(v_a.adj_date, v_a.item_id, v_a.pack_id, v_a.lot_batch_id, v_a.qty_base, 'wastage', v_a.adj_no,
                          null, null, p_id, v_a.department_id, p_actor, v_a.is_demo, v_a.reason);
    v_lines := jsonb_build_array(
      jsonb_build_object('rule', 'wastage.abnormal_loss', 'amount_paise', v_val, 'narration', v_a.reason),
      jsonb_build_object('rule', rb_stk_rule('wastage', v_a.item_id), 'amount_paise', v_val, 'item_id', v_a.item_id,
        'narration', trim_scale(v_a.qty_base) || ' ' || rb_stk_label(v_a.item_id, v_a.pack_id) || ' written off'));
  else
    v_val := v_a.value_paise;
    if v_val > (select value from rb_stk_bal(v_a.item_id, v_a.pack_id, null, v_a.adj_date)) then
      raise exception 'The write-down is now more than the stock''s cost.';
    end if;
    perform rb_stk_move(v_a.adj_date, v_a.item_id, v_a.pack_id, null, 0, -v_val, 'write_down', v_a.adj_no, null, null, p_id,
                        v_a.department_id, p_actor, v_a.is_demo, v_a.reason);
    v_lines := jsonb_build_array(
      jsonb_build_object('rule', 'write_down.expense', 'amount_paise', v_val, 'narration', v_a.reason),
      jsonb_build_object('rule', rb_stk_rule('write_down', v_a.item_id), 'amount_paise', v_val, 'item_id', v_a.item_id,
        'narration', rb_stk_label(v_a.item_id, v_a.pack_id) || ' written down to net realisable value'));
  end if;
  if v_val > 0 then
    v_j := rb_post_engine(jsonb_build_object('journal_date', v_a.adj_date, 'source', 'stock',
      'event_code', case when v_a.kind = 'write_off' then 'wastage' else 'write_down' end, 'source_ref', v_a.adj_no,
      'narration', case when v_a.kind = 'write_off' then 'Write-off ' else 'Write-down ' end || v_a.adj_no || ': ' || v_a.reason,
      'department_id', v_a.department_id, 'is_demo', v_a.is_demo, 'entered_by', v_a.entered_by, 'approved_by', p_actor), v_lines);
    update stock_moves set journal_id = v_j where adjustment_id = p_id;
  end if;
  update stock_adjustments set status = 'posted', value_paise = v_val, approved_by = p_actor, posted_at = now(), journal_id = v_j
  where id = p_id;
  perform rb_audit_write('POST_STOCK_ADJUSTMENT', 'stock_adjustments', p_id::text, null,
    jsonb_build_object('adj_no', v_a.adj_no, 'kind', v_a.kind, 'value_paise', v_val), v_a.reason);
end $$;

-- ---------------------------------------------------------------------
-- 7. What the screens call
-- ---------------------------------------------------------------------

create or replace function rb_save_preparation(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
begin
  return rb_stk_save_prep(p, rb_require('production.add', 'enter production batches'), false);
end $$;

create or replace function rb_save_production(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
begin
  return rb_stk_save_production(p, rb_require('production.add', 'enter production batches'), false);
end $$;

create or replace function rb_save_prep_and_production(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return rb_stk_save_combined(p, rb_require('production.add', 'enter production batches'), false);
end $$;

-- Journals from these screens are reversed only there, so stock and the
-- books stay in step.
create or replace function rb_stk_journal_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('rb.stock', true), '') = 'on' then return coalesce(new, old); end if;
  if tg_op = 'UPDATE' and old.source in ('production', 'stock') and old.status = 'posted' and new.status = 'reversed' then
    raise exception 'This entry comes from the % screen. Reverse it there, so stock and the books stay in step.',
      case when old.source = 'production' then 'Production' else 'Stock' end;
  end if;
  if tg_op = 'DELETE' and old.source in ('production', 'stock') and old.status <> 'draft' and not old.is_demo
     and not (old.is_training and rb_is_training()) then
    raise exception 'This entry comes from the % screen. Delete or reverse it there.',
      case when old.source = 'production' then 'Production' else 'Stock' end;
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists rb_stk_journal_guard on journals;
create trigger rb_stk_journal_guard before update or delete on journals
  for each row execute function rb_stk_journal_guard();

-- Reverse a batch: its journal and its stock, on the date chosen. Not
-- allowed once what it made has been used or sold.
create or replace function rb_reverse_batch(p_id bigint, p_date date, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.reverse_entries', 'reverse posted entries'); v_b production_batches; v_rev bigint;
        v_items int[];
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason for the reversal.'; end if;
  select * into v_b from production_batches where id = p_id for update;
  if v_b.id is null then raise exception 'Batch not found.'; end if;
  if v_b.status <> 'posted' then raise exception 'This batch is already reversed.'; end if;
  if p_date is null or p_date < v_b.batch_date then raise exception 'The reversal date cannot be before the batch date.'; end if;
  perform rb_assert_period_open(p_date);
  if exists (select 1 from batch_lines l join production_batches b on b.id = l.batch_id
             where l.lot_batch_id = p_id and l.batch_id <> p_id and b.status = 'posted') then
    raise exception 'Some of this preparation has gone into a production batch. Reverse that batch first.';
  end if;
  select array_agg(distinct item_id) into v_items from stock_moves where batch_id = p_id;
  insert into stock_moves (move_date, item_id, pack_id, packs, lot_batch_id, qty_base, value_paise, kind, doc_no, batch_id,
                           department_id, note, created_by, is_demo, is_training)
  select p_date, item_id, pack_id, -sum(packs), lot_batch_id, -sum(qty_base), -sum(value_paise), 'reversal', v_b.batch_no, p_id,
         v_b.department_id, trim(p_reason), v_me, v_b.is_demo, rb_is_training()
  from stock_moves where batch_id = p_id group by item_id, pack_id, lot_batch_id
  having sum(qty_base) <> 0 or sum(value_paise) <> 0;
  perform rb_stk_assert_not_negative(v_items);
  if v_b.journal_id is not null then
    perform set_config('rb.stock', 'on', true);
    v_rev := rb_reverse_journal(v_b.journal_id, p_date, 'Batch ' || v_b.batch_no || ' reversed: ' || trim(p_reason));
    perform set_config('rb.stock', 'off', true);
    update stock_moves set journal_id = v_rev where batch_id = p_id and kind = 'reversal' and journal_id is null;
  end if;
  update production_batches set status = 'reversed', reversal_journal_id = v_rev, reverse_reason = trim(p_reason),
    reversed_at = now(), reversed_by = v_me where id = p_id;
  perform rb_audit_write('REVERSE_BATCH', 'production_batches', p_id::text, null,
    jsonb_build_object('batch_no', v_b.batch_no, 'date', p_date), trim(p_reason));
end $$;

-- Learning phase: a Director or the FC may fully delete a batch entered by
-- someone still in their learning phase. Not written to the audit log (spec section 4).
create or replace function rb_hard_delete_batch(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('production.delete', 'fully delete production batches'); v_b production_batches; v_items int[];
begin
  select * into v_b from production_batches where id = p_id for update;
  if v_b.id is null then raise exception 'Batch not found.'; end if;
  if not rb_can_hard_delete('production', v_b.entered_by) then
    raise exception 'Only batches entered by someone still in their learning phase can be fully deleted. Reverse it instead.';
  end if;
  if v_b.status <> 'posted' then raise exception 'This batch has been reversed. Reversed entries are kept.'; end if;
  perform rb_assert_period_open(v_b.batch_date);
  if exists (select 1 from batch_lines where lot_batch_id = p_id and batch_id <> p_id) then
    raise exception 'Some of this preparation has gone into a production batch. Delete that batch first.';
  end if;
  select array_agg(distinct item_id) into v_items from stock_moves where batch_id = p_id;
  perform set_config('rb.ledger', 'on', true);
  perform set_config('rb.stock', 'on', true);
  update production_batches set linked_batch_id = null where linked_batch_id = p_id;
  delete from stock_moves where batch_id = p_id;
  delete from production_batches where id = p_id;
  delete from journals where id = v_b.journal_id;
  perform set_config('rb.stock', 'off', true);
  perform set_config('rb.ledger', 'off', true);
  perform rb_stk_assert_not_negative(v_items);
end $$;

create or replace function rb_save_stock_count(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid;
begin
  v_me := rb_require(case when rb_int(p, 'id') is null then 'stock.add' else 'stock.edit' end, 'enter stock counts');
  if coalesce(rb_txt(p, 'purpose'), 'count') = 'opening' and not rb_stk_cost_ok() then
    raise exception 'Opening stock carries costs, so it is entered by the Accountant, FC or a Director.';
  end if;
  return rb_stk_save_count(p, v_me, false);
end $$;

create or replace function rb_post_stock_count(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('stock.approve', 'approve stock counts'); v_c stock_counts;
begin
  select * into v_c from stock_counts where id = p_id;
  if v_c.id is null then raise exception 'Count not found.'; end if;
  if not rb_can_approve('stock', v_c.entered_by) then raise exception 'You cannot approve your own count. Ask someone else to approve it.'; end if;
  if v_c.purpose = 'opening' and not rb_stk_cost_ok() then
    raise exception 'Opening stock is approved by the Accountant, FC or a Director.';
  end if;
  perform rb_stk_post_count(p_id, v_me);
end $$;

create or replace function rb_cancel_stock_count(p_id bigint, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('stock.edit', 'cancel stock counts'); v_c stock_counts;
begin
  select * into v_c from stock_counts where id = p_id for update;
  if v_c.id is null or v_c.status <> 'draft' then raise exception 'Only a count that is not posted yet can be cancelled.'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason.'; end if;
  update stock_counts set status = 'cancelled', cancel_reason = trim(p_reason), updated_at = now(), updated_by = v_me where id = p_id;
  perform rb_audit_write('CANCEL_STOCK_COUNT', 'stock_counts', p_id::text, null, jsonb_build_object('count_no', v_c.count_no), trim(p_reason));
end $$;

create or replace function rb_save_stock_adjustment(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('stock.add', 'write stock off'); v_id bigint;
begin
  if rb_txt(p, 'kind') = 'write_down' and not rb_stk_cost_ok() then
    raise exception 'A write-down changes the stock''s cost, so it is entered by the Accountant, FC or a Director.';
  end if;
  v_id := rb_stk_save_adjustment(p, v_me, false);
  -- Directors, the FC and the Accountant may approve their own (spec section 4).
  if rb_can_approve('stock', v_me) then perform rb_stk_post_adjustment(v_id, v_me); end if;
  return v_id;
end $$;

create or replace function rb_approve_stock_adjustment(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('stock.approve', 'approve write-offs'); v_a stock_adjustments;
begin
  select * into v_a from stock_adjustments where id = p_id;
  if v_a.id is null then raise exception 'Not found.'; end if;
  if not rb_can_approve('stock', v_a.entered_by) then raise exception 'You cannot approve your own entries.'; end if;
  if v_a.kind = 'write_down' and not rb_stk_cost_ok() then raise exception 'Write-downs are approved by the Accountant, FC or a Director.'; end if;
  perform rb_stk_post_adjustment(p_id, v_me);
end $$;

create or replace function rb_refuse_stock_adjustment(p_id bigint, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('stock.approve', 'refuse write-offs'); v_a stock_adjustments;
begin
  select * into v_a from stock_adjustments where id = p_id for update;
  if v_a.id is null or v_a.status <> 'awaiting_approval' then raise exception 'This is not waiting for approval.'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason.'; end if;
  update stock_adjustments set status = 'refused', refused_reason = trim(p_reason) where id = p_id;
  perform rb_audit_write('REFUSE_STOCK_ADJUSTMENT', 'stock_adjustments', p_id::text, null, jsonb_build_object('adj_no', v_a.adj_no), trim(p_reason));
end $$;

-- Reverse a posted count, opening stock, write-off or write-down.
-- p_kind: 'count' or 'adjustment'
create or replace function rb_reverse_stock_entry(p_kind text, p_id bigint, p_date date, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.reverse_entries', 'reverse posted entries'); v_no text; v_j bigint; v_status text;
        v_date date; v_rev bigint; v_items int[]; v_demo boolean; v_dept int;
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please give the reason for the reversal.'; end if;
  if p_kind = 'count' then
    select count_no, journal_id, status, count_date, is_demo, department_id into v_no, v_j, v_status, v_date, v_demo, v_dept
    from stock_counts where id = p_id for update;
  elsif p_kind = 'adjustment' then
    select adj_no, journal_id, status, adj_date, is_demo, department_id into v_no, v_j, v_status, v_date, v_demo, v_dept
    from stock_adjustments where id = p_id for update;
  else raise exception 'Unknown entry.'; end if;
  if v_no is null then raise exception 'Not found.'; end if;
  if v_status <> 'posted' then raise exception 'Only a posted entry can be reversed.'; end if;
  if p_date is null or p_date < v_date then raise exception 'The reversal date cannot be before the entry''s own date.'; end if;
  perform rb_assert_period_open(p_date);
  select array_agg(distinct item_id) into v_items from stock_moves
  where (p_kind = 'count' and count_id = p_id) or (p_kind = 'adjustment' and adjustment_id = p_id);
  insert into stock_moves (move_date, item_id, pack_id, packs, lot_batch_id, qty_base, value_paise, kind, doc_no, count_id,
                           adjustment_id, department_id, note, created_by, is_demo, is_training)
  select p_date, item_id, pack_id, -sum(packs), lot_batch_id, -sum(qty_base), -sum(value_paise), 'reversal', v_no,
         case when p_kind = 'count' then p_id end, case when p_kind = 'adjustment' then p_id end, v_dept, trim(p_reason), v_me,
         v_demo, rb_is_training()
  from stock_moves where (p_kind = 'count' and count_id = p_id) or (p_kind = 'adjustment' and adjustment_id = p_id)
  group by item_id, pack_id, lot_batch_id having sum(qty_base) <> 0 or sum(value_paise) <> 0;
  perform rb_stk_assert_not_negative(coalesce(v_items, '{}'));
  if v_j is not null then
    perform set_config('rb.stock', 'on', true);
    v_rev := rb_reverse_journal(v_j, p_date, v_no || ' reversed: ' || trim(p_reason));
    perform set_config('rb.stock', 'off', true);
  end if;
  if p_kind = 'count' then
    update stock_counts set status = 'reversed', reversal_journal_id = v_rev, reverse_reason = trim(p_reason) where id = p_id;
  else
    update stock_adjustments set status = 'reversed', reversal_journal_id = v_rev, reverse_reason = trim(p_reason) where id = p_id;
  end if;
  perform rb_audit_write('REVERSE_STOCK_ENTRY', case when p_kind = 'count' then 'stock_counts' else 'stock_adjustments' end,
    p_id::text, null, jsonb_build_object('number', v_no, 'date', p_date), trim(p_reason));
end $$;

-- ---------------------------------------------------------------------
-- 8. Reading: stock lists, batches, movements, reports. Costs are shown
--    only to people with the margin tick (Directors, FC, Accountant).
-- ---------------------------------------------------------------------

-- Every stock line: item (and pack, for finished goods) with quantity,
-- packs, value and average cost; active items with no stock show as zero.
create or replace function rb_stock_list(p_as_of date default current_date)
returns table (item_id int, pack_id int, code text, name text, pack_name text, kind text, base_unit text, net_qty numeric,
               qty_base numeric, packs numeric, value_paise bigint, avg_cost_paise numeric, last_move date,
               oldest_lot date, expired_qty numeric, is_active boolean, is_demo boolean)
language plpgsql stable security definer set search_path = public as $$
declare v_cost boolean := rb_stk_cost_ok();
begin
  if not (rb_has('stock.view') or rb_has('production.view') or rb_has('accounts.view')) then
    raise exception 'You do not have the right to see stock.';
  end if;
  return query
  with keys as (
    select i.id item_id, null::int pack_id from items i where i.kind in ('raw', 'packaging', 'wip', 'byproduct')
      and (i.is_active or exists (select 1 from stock_moves m where m.item_id = i.id))
      and (i.kind <> 'byproduct' or i.byproduct_use = 'sellable' or exists (select 1 from stock_moves m where m.item_id = i.id))
    union
    select pp.item_id, pp.id from product_packs pp join items i on i.id = pp.item_id
      where (pp.is_active and i.is_active) or exists (select 1 from stock_moves m where m.pack_id = pp.id)
    union
    select i.id, null from items i where i.kind = 'finished'
      and (i.sells_by in ('weight', 'piece') or exists (select 1 from stock_moves m where m.item_id = i.id and m.pack_id is null))
  ), bal as (
    select m.item_id, m.pack_id, sum(m.qty_base) q, sum(m.value_paise)::bigint v, max(m.move_date) last_move
    from stock_moves m where m.move_date <= p_as_of group by m.item_id, m.pack_id
  ), lots as (
    select m.item_id, b.batch_date, sum(m.qty_base) q from stock_moves m join production_batches b on b.id = m.lot_batch_id
    where m.move_date <= p_as_of group by m.item_id, m.lot_batch_id, b.batch_date having sum(m.qty_base) > 0
  )
  select k.item_id, k.pack_id, i.code, i.name, pt.name, i.kind, i.base_unit, pp.net_qty,
         coalesce(b.q, 0)::numeric, case when pp.net_qty > 0 then round(coalesce(b.q, 0) / pp.net_qty, 3) end,
         case when v_cost then coalesce(b.v, 0) end,
         case when v_cost and b.q > 0 then round(b.v / b.q, 4) end,
         b.last_move,
         (select min(l.batch_date) from lots l where l.item_id = k.item_id),
         (select sum(l.q) from lots l where l.item_id = k.item_id and i.shelf_life_days is not null
            and l.batch_date + i.shelf_life_days < p_as_of),
         i.is_active and coalesce(pp.is_active, true), i.is_demo
  from keys k join items i on i.id = k.item_id
  left join product_packs pp on pp.id = k.pack_id left join pack_types pt on pt.id = pp.pack_type_id
  left join bal b on b.item_id = k.item_id and b.pack_id is not distinct from k.pack_id
  order by case i.kind when 'raw' then 1 when 'packaging' then 2 when 'wip' then 3 when 'finished' then 4 else 5 end,
           i.name, pp.net_qty nulls last;
end $$;

-- Prepared ingredients batch by batch, with age and shelf-life warning.
create or replace function rb_wip_lots(p_as_of date default current_date)
returns table (item_id int, item_name text, lot_batch_id bigint, batch_no text, prep_date date, qty_base numeric,
               base_unit text, age_days int, shelf_life_days int, expires_on date, expired boolean, is_demo boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (rb_has('stock.view') or rb_has('production.view') or rb_has('accounts.view')) then
    raise exception 'You do not have the right to see stock.';
  end if;
  return query
  select i.id, i.name, m.lot_batch_id, b.batch_no, b.batch_date, sum(m.qty_base)::numeric, i.base_unit,
         case when b.batch_date is not null then (p_as_of - b.batch_date)::int end, i.shelf_life_days,
         b.batch_date + i.shelf_life_days,
         coalesce(b.batch_date + i.shelf_life_days < p_as_of, false), bool_or(m.is_demo)
  from stock_moves m join items i on i.id = m.item_id left join production_batches b on b.id = m.lot_batch_id
  where i.kind = 'wip' and m.move_date <= p_as_of
  group by i.id, i.name, m.lot_batch_id, b.batch_no, b.batch_date, i.base_unit, i.shelf_life_days
  having sum(m.qty_base) > 0
  order by i.name, b.batch_date nulls first;
end $$;

-- Batches in a date range.
create or replace function rb_batch_list(p_from date, p_to date)
returns table (id bigint, batch_no text, kind text, batch_date date, output_item text, output_qty_base numeric, base_unit text,
               input_summary text, output_summary text, wastage_qty_base numeric, yield_pct numeric, cost_paise bigint,
               linked_batch_no text, status text, entered_by_name text, is_demo boolean)
language plpgsql stable security definer set search_path = public as $$
declare v_cost boolean := rb_stk_cost_ok();
begin
  if not (rb_has('production.view') or rb_has('stock.view') or rb_has('accounts.view')) then
    raise exception 'You do not have the right to see production.';
  end if;
  return query
  select b.id, b.batch_no, b.kind, b.batch_date, i.name, b.output_qty_base, i.base_unit,
         (select string_agg(trim_scale(l.qty_base) || ' ' || li.base_unit || ' ' || li.name, ', ' order by l.line_no)
            from batch_lines l join items li on li.id = l.item_id where l.batch_id = b.id and l.role = 'input'),
         (select string_agg(coalesce(trim_scale(l.packs) || ' × ' || pt.name, trim_scale(l.qty_base) || ' ' || i.base_unit || ' loose'), ', ' order by l.line_no)
            from batch_lines l left join product_packs pp on pp.id = l.pack_id left join pack_types pt on pt.id = pp.pack_type_id
            where l.batch_id = b.id and l.role = 'output'),
         b.wastage_qty_base,
         case when b.kind = 'preparation' and b.input_qty_base > 0 then round(100 * b.output_qty_base / b.input_qty_base, 1)
              when b.kind = 'production' and b.input_qty_base > 0 then round(100 * b.output_qty_base / b.input_qty_base, 1) end,
         case when v_cost then b.output_value_paise end,
         (select x.batch_no from production_batches x where x.id = b.linked_batch_id),
         b.status, (select coalesce(u.short_name, u.full_name) from app_users u where u.id = b.entered_by), b.is_demo
  from production_batches b join items i on i.id = b.output_item_id
  where b.batch_date between p_from and p_to
  order by b.batch_date desc, b.id desc;
end $$;

-- One batch, everything the batch window shows.
create or replace function rb_batch_detail(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_b production_batches; v_cost boolean := rb_stk_cost_ok(); v jsonb; v_used numeric; v_left numeric;
begin
  if not (rb_has('production.view') or rb_has('stock.view') or rb_has('accounts.view')) then
    raise exception 'You do not have the right to see production.';
  end if;
  select * into v_b from production_batches where id = p_id;
  if v_b.id is null then raise exception 'Batch not found.'; end if;
  select coalesce(sum(l.qty_base), 0) into v_used from batch_lines l join production_batches x on x.id = l.batch_id
  where l.lot_batch_id = p_id and l.batch_id <> p_id and x.status = 'posted';
  select qty into v_left from rb_stk_bal(v_b.output_item_id, null, p_id, null);
  v := jsonb_build_object(
    'batch', to_jsonb(v_b) - case when v_cost then '{}'::text[] else
             array['input_value_paise', 'packaging_value_paise', 'byproduct_value_paise', 'abnormal_value_paise', 'output_value_paise'] end
      || jsonb_build_object(
        'output_item', (select name from items where id = v_b.output_item_id),
        'base_unit', (select base_unit from items where id = v_b.output_item_id),
        'department', rb_dept_label(v_b.department_id, v_b.batch_date),
        'entered_by_name', (select coalesce(short_name, full_name) from app_users where id = v_b.entered_by),
        'journal_no', (select journal_no from journals where id = v_b.journal_id),
        'reversal_journal_no', (select journal_no from journals where id = v_b.reversal_journal_id),
        'linked_batch_no', (select batch_no from production_batches where id = v_b.linked_batch_id),
        'linked_kind', (select kind from production_batches where id = v_b.linked_batch_id),
        'used_qty_base', v_used, 'left_qty_base', case when v_b.kind = 'preparation' then v_left end,
        'shelf_life_days', (select shelf_life_days from items where id = v_b.output_item_id)),
    'lines', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'line_no', l.line_no, 'role', l.role, 'item_id', l.item_id,
        'item_name', i.name, 'kind', i.kind, 'base_unit', i.base_unit, 'pack_id', l.pack_id, 'pack_name', pt.name, 'packs', l.packs,
        'qty_base', l.qty_base, 'stage', l.stage, 'byproduct_use', l.byproduct_use,
        'lot_batch_id', l.lot_batch_id, 'lot_batch_no', lb.batch_no, 'lot_date', lb.batch_date,
        'value_paise', case when v_cost then l.value_paise end) order by l.line_no)
      from batch_lines l join items i on i.id = l.item_id left join product_packs pp on pp.id = l.pack_id
      left join pack_types pt on pt.id = pp.pack_type_id left join production_batches lb on lb.id = l.lot_batch_id and l.lot_batch_id <> p_id
      where l.batch_id = p_id), '[]'),
    'stages', coalesce((select jsonb_agg(to_jsonb(s) order by s.stage_no) from batch_stages s where s.batch_id = p_id), '[]'),
    'used_in', coalesce((select jsonb_agg(jsonb_build_object('batch_id', x.id, 'batch_no', x.batch_no, 'batch_date', x.batch_date,
        'product', (select name from items where id = x.output_item_id), 'qty_base', l.qty_base, 'status', x.status) order by x.batch_date, x.id)
      from batch_lines l join production_batches x on x.id = l.batch_id where l.lot_batch_id = p_id and l.batch_id <> p_id), '[]'),
    'can', jsonb_build_object(
      'reverse', v_b.status = 'posted' and rb_has('power.reverse_entries'),
      'hard_delete', v_b.status = 'posted' and rb_can_hard_delete('production', v_b.entered_by),
      'see_cost', v_cost));
  return v;
end $$;

-- An item's movements with a running balance.
create or replace function rb_stock_movements(p_item int, p_pack int, p_from date, p_to date)
returns table (move_date date, kind text, doc_no text, batch_no text, note text, qty_base numeric, value_paise bigint,
               balance_qty numeric, balance_value bigint, is_demo boolean)
language plpgsql stable security definer set search_path = public as $$
declare v_cost boolean := rb_stk_cost_ok(); v_q numeric; v_v bigint;
begin
  if not (rb_has('stock.view') or rb_has('production.view') or rb_has('accounts.view')) then
    raise exception 'You do not have the right to see stock.';
  end if;
  select qty, value into v_q, v_v from rb_stk_bal(p_item, p_pack, null, p_from - 1);
  return query
  select z.d, z.k, z.doc, z.bn, z.nt, z.q, z.v, z.bq, z.bv, z.demo from (
    select p_from - 1 d, 'brought_forward'::text k, null::text doc, null::text bn, 'Balance brought forward'::text nt,
           null::numeric q, null::bigint v, v_q bq, case when v_cost then v_v end bv, false demo, 0::bigint ord
    union all
    select m.move_date, m.kind, m.doc_no, b.batch_no, m.note, m.qty_base, case when v_cost then m.value_paise end,
           v_q + sum(m.qty_base) over w, case when v_cost then (v_v + sum(m.value_paise) over w)::bigint end, m.is_demo, m.id
    from stock_moves m left join production_batches b on b.id = m.lot_batch_id
    where m.item_id = p_item and m.pack_id is not distinct from p_pack and m.move_date between p_from and p_to
    window w as (order by m.move_date, m.id rows between unbounded preceding and current row)) z
  order by z.d, z.ord;
end $$;

-- Counts and write-offs, with their lines, for the Stock screen.
create or replace function rb_stock_count_detail(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_c stock_counts; v_cost boolean := rb_stk_cost_ok();
begin
  if not (rb_has('stock.view') or rb_has('accounts.view')) then raise exception 'You do not have the right to see stock.'; end if;
  select * into v_c from stock_counts where id = p_id;
  if v_c.id is null then raise exception 'Count not found.'; end if;
  return jsonb_build_object(
    'count', to_jsonb(v_c) - case when v_cost then '{}'::text[] else array['short_paise', 'excess_paise'] end || jsonb_build_object(
      'entered_by_name', (select coalesce(short_name, full_name) from app_users where id = v_c.entered_by),
      'approved_by_name', (select coalesce(short_name, full_name) from app_users where id = v_c.approved_by),
      'journal_no', (select journal_no from journals where id = v_c.journal_id)),
    'lines', coalesce((select jsonb_agg(jsonb_build_object('item_id', l.item_id, 'pack_id', l.pack_id,
        'label', rb_stk_label(l.item_id, l.pack_id), 'base_unit', i.base_unit, 'net_qty', pp.net_qty,
        'counted_qty_base', l.counted_qty_base, 'system_qty_base', coalesce(l.system_qty_base,
          (select qty from rb_stk_bal(l.item_id, l.pack_id, null, v_c.count_date))),
        'diff_qty_base', l.diff_qty_base, 'reason', l.reason,
        'unit_cost_paise', case when v_cost then l.unit_cost_paise end,
        'value_paise', case when v_cost then l.value_paise end) order by l.line_no)
      from stock_count_lines l join items i on i.id = l.item_id left join product_packs pp on pp.id = l.pack_id
      where l.count_id = p_id), '[]'),
    'can', jsonb_build_object(
      'edit', v_c.status = 'draft' and rb_has('stock.edit'),
      'post', v_c.status = 'draft' and rb_can_approve('stock', v_c.entered_by) and (v_c.purpose = 'count' or v_cost),
      'reverse', v_c.status = 'posted' and rb_has('power.reverse_entries')));
end $$;

create or replace function rb_stock_adjustment_list()
returns table (id bigint, adj_no text, kind text, adj_date date, item_id int, label text, base_unit text, lot_batch_no text,
               qty_base numeric, value_paise bigint, reason text, status text, entered_by_name text, approved_by_name text,
               refused_reason text, reverse_reason text, can_approve boolean, can_reverse boolean, is_demo boolean)
language plpgsql stable security definer set search_path = public as $$
declare v_cost boolean := rb_stk_cost_ok();
begin
  if not (rb_has('stock.view') or rb_has('accounts.view')) then raise exception 'You do not have the right to see stock.'; end if;
  return query
  select a.id, a.adj_no, a.kind, a.adj_date, a.item_id, rb_stk_label(a.item_id, a.pack_id), i.base_unit,
         (select x.batch_no from production_batches x where x.id = a.lot_batch_id), a.qty_base,
         case when v_cost then a.value_paise end, a.reason, a.status,
         (select coalesce(short_name, full_name) from app_users where app_users.id = a.entered_by),
         (select coalesce(short_name, full_name) from app_users where app_users.id = a.approved_by),
         a.refused_reason, a.reverse_reason,
         a.status = 'awaiting_approval' and rb_can_approve('stock', a.entered_by) and (a.kind = 'write_off' or v_cost),
         a.status = 'posted' and rb_has('power.reverse_entries'), a.is_demo
  from stock_adjustments a join items i on i.id = a.item_id
  order by a.adj_date desc, a.id desc;
end $$;

create or replace function rb_stock_count_list()
returns table (id bigint, count_no text, purpose text, count_date date, lines int, short_paise bigint, excess_paise bigint,
               status text, entered_by_name text, approved_by_name text, note text, is_demo boolean)
language plpgsql stable security definer set search_path = public as $$
declare v_cost boolean := rb_stk_cost_ok();
begin
  if not (rb_has('stock.view') or rb_has('accounts.view')) then raise exception 'You do not have the right to see stock.'; end if;
  return query
  select c.id, c.count_no, c.purpose, c.count_date, (select count(*)::int from stock_count_lines l where l.count_id = c.id),
         case when v_cost then c.short_paise end, case when v_cost then c.excess_paise end, c.status,
         (select coalesce(short_name, full_name) from app_users where app_users.id = c.entered_by),
         (select coalesce(short_name, full_name) from app_users where app_users.id = c.approved_by), c.note, c.is_demo
  from stock_counts c order by c.count_date desc, c.id desc;
end $$;

-- Yield report: raw material -> prepared -> finished goods, with
-- wastage % at each stage, one row per preparation batch.
create or replace function rb_yield_report(p_from date, p_to date)
returns table (batch_id bigint, batch_no text, batch_date date, raw_item text, raw_qty numeric, stages jsonb,
               wastage_qty numeric, wastage_pct numeric, byproduct_qty numeric, abnormal_qty numeric, prepared_item text,
               prepared_qty numeric, yield_pct numeric, other_change_qty numeric, used_qty numeric, left_qty numeric,
               finished jsonb, base_unit text, status text, is_demo boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (rb_has('production.view') or rb_has('stock.view') or rb_has('accounts.view')) then
    raise exception 'You do not have the right to see production.';
  end if;
  return query
  select b.id, b.batch_no, b.batch_date, ri.name, b.input_qty_base,
         coalesce((select jsonb_agg(jsonb_build_object('stage', s.stage, 'qty', s.wastage_qty_base,
                     'pct', round(100 * s.wastage_qty_base / nullif(b.input_qty_base, 0), 1)) order by s.stage_no)
                   from batch_stages s where s.batch_id = b.id), '[]'),
         b.wastage_qty_base, round(100 * b.wastage_qty_base / nullif(b.input_qty_base, 0), 1),
         b.byproduct_qty_base, b.abnormal_qty_base, oi.name, b.output_qty_base,
         round(100 * b.output_qty_base / nullif(b.input_qty_base, 0), 1),
         b.input_qty_base - b.wastage_qty_base - b.byproduct_qty_base - b.abnormal_qty_base - b.output_qty_base,
         coalesce((select sum(l.qty_base) from batch_lines l join production_batches x on x.id = l.batch_id
                   where l.lot_batch_id = b.id and l.batch_id <> b.id and x.status = 'posted'), 0),
         (select qty from rb_stk_bal(b.output_item_id, null, b.id, null)),
         coalesce((select jsonb_agg(jsonb_build_object('batch_no', x.batch_no, 'product', fi.name, 'used', l.qty_base,
                     'made', x.output_qty_base, 'shrinkage', x.shrinkage_qty_base, 'packing', x.packing_waste_qty_base) order by x.id)
                   from batch_lines l join production_batches x on x.id = l.batch_id join items fi on fi.id = x.output_item_id
                   where l.lot_batch_id = b.id and l.batch_id <> b.id and x.status = 'posted'), '[]'),
         ri.base_unit, b.status, b.is_demo
  from production_batches b join items oi on oi.id = b.output_item_id
  join batch_lines il on il.batch_id = b.id and il.role = 'input' join items ri on ri.id = il.item_id
  where b.kind = 'preparation' and b.batch_date between p_from and p_to
  order by b.batch_date, b.id;
end $$;

-- Wastage by stage: per raw material and stage (preparation), and per
-- product for frying shrinkage, packing wastage and unusual losses.
create or replace function rb_wastage_report(p_from date, p_to date)
returns table (item text, stage text, batches int, input_qty numeric, wastage_qty numeric, wastage_pct numeric, base_unit text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (rb_has('production.view') or rb_has('stock.view') or rb_has('accounts.view')) then
    raise exception 'You do not have the right to see production.';
  end if;
  return query
  with prep as (
    select b.id, ri.name item, ri.base_unit, b.input_qty_base inq, b.abnormal_qty_base abn
    from production_batches b join batch_lines il on il.batch_id = b.id and il.role = 'input' join items ri on ri.id = il.item_id
    where b.kind = 'preparation' and b.status = 'posted' and b.batch_date between p_from and p_to
  ), prod as (
    select b.*, fi.name item, fi.base_unit from production_batches b join items fi on fi.id = b.output_item_id
    where b.kind = 'production' and b.status = 'posted' and b.batch_date between p_from and p_to
  ), rows_ as (
    select p.item, s.stage, min(s.stage_no) ord, count(*)::int n, sum(p.inq) inq, sum(s.wastage_qty_base) w, p.base_unit
    from prep p join batch_stages s on s.batch_id = p.id group by p.item, s.stage, p.base_unit
    union all
    select p.item, 'Unusual loss', 900, count(*)::int, sum(p.inq), sum(p.abn), p.base_unit from prep p where p.abn > 0 group by p.item, p.base_unit
    union all
    select d.item, 'Frying shrinkage', 901, count(*)::int, sum(d.output_qty_base + d.wastage_qty_base + d.abnormal_qty_base), sum(d.shrinkage_qty_base), d.base_unit
    from prod d group by d.item, d.base_unit having sum(d.shrinkage_qty_base) > 0
    union all
    select d.item, 'Packing wastage', 902, count(*)::int, sum(d.output_qty_base + d.wastage_qty_base + d.abnormal_qty_base), sum(d.packing_waste_qty_base), d.base_unit
    from prod d group by d.item, d.base_unit having sum(d.packing_waste_qty_base) > 0
    union all
    select d.item, 'Unusual loss', 903, count(*)::int, sum(d.output_qty_base + d.wastage_qty_base + d.abnormal_qty_base), sum(d.abnormal_qty_base), d.base_unit
    from prod d group by d.item, d.base_unit having sum(d.abnormal_qty_base) > 0
  )
  select r.item, r.stage, r.n, r.inq, r.w, round(100 * r.w / nullif(r.inq, 0), 1), r.base_unit
  from rows_ r order by r.item, r.ord;
end $$;

-- Stock on hand (module 3's report), now with production; costs of
-- prepared and finished goods only for the margin tick.
create or replace function rb_stock_on_hand(p_as_of date default current_date)
returns table (item_id int, code text, name text, kind text, base_unit text, qty_base numeric, value_paise bigint, avg_cost_paise numeric)
language plpgsql stable security definer set search_path = public as $$
declare v_cost boolean := rb_stk_cost_ok();
begin
  if not (rb_has('purchases.view') or rb_has('stock.view') or rb_has('accounts.view')) then
    raise exception 'You do not have the right to see stock.';
  end if;
  return query
  select i.id, i.code, i.name, i.kind, i.base_unit, sum(m.qty_base),
         case when v_cost or i.kind in ('raw', 'packaging') then sum(m.value_paise)::bigint end,
         case when (v_cost or i.kind in ('raw', 'packaging')) and sum(m.qty_base) > 0 then round(sum(m.value_paise) / sum(m.qty_base), 4) end
  from stock_moves m join items i on i.id = m.item_id
  where m.move_date <= p_as_of
  group by i.id, i.code, i.name, i.kind, i.base_unit
  order by i.kind, i.name;
end $$;

-- ---------------------------------------------------------------------
-- 9. Row-level security and who may call what
-- ---------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array['production_batches', 'batch_lines', 'batch_stages', 'stock_counts', 'stock_count_lines',
                           'stock_adjustments'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon, authenticated', t);
    execute format('grant select on %I to authenticated', t);
    execute format('grant all on %I to service_role', t);
    execute format('drop policy if exists rb_read on %I', t);
    -- These hold costs, so only the margin tick reads them directly; the
    -- screens read through the rb_ functions above, which hide costs.
    execute format('create policy rb_read on %I for select to authenticated using (rb_stk_cost_ok())', t);
  end loop;
end $$;
-- Stock movements carry costs of prepared and finished goods too.
drop policy if exists rb_read on stock_moves;
create policy rb_read on stock_moves for select to authenticated
  using (rb_stk_cost_ok() or (purchase_id is not null and rb_has('purchases.view')));
revoke all on all sequences in schema public from anon, authenticated;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p
           where p.pronamespace = 'public'::regnamespace
             and (p.proname like 'rb\_stk\_%' or p.proname in (
               'rb_save_preparation', 'rb_save_production', 'rb_save_prep_and_production', 'rb_reverse_batch',
               'rb_hard_delete_batch', 'rb_save_stock_count', 'rb_post_stock_count', 'rb_cancel_stock_count',
               'rb_save_stock_adjustment', 'rb_approve_stock_adjustment', 'rb_refuse_stock_adjustment',
               'rb_reverse_stock_entry', 'rb_stock_list', 'rb_wip_lots', 'rb_batch_list', 'rb_batch_detail',
               'rb_stock_movements', 'rb_stock_count_detail', 'rb_stock_adjustment_list', 'rb_stock_count_list',
               'rb_yield_report', 'rb_wastage_report', 'rb_stock_on_hand')) loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;
end $$;
-- Used inside row-level security, so it must stay callable (it only says yes or no).
grant execute on function rb_stk_cost_ok() to authenticated;
grant execute on function
  rb_save_preparation(jsonb), rb_save_production(jsonb), rb_save_prep_and_production(jsonb),
  rb_reverse_batch(bigint, date, text), rb_hard_delete_batch(bigint),
  rb_save_stock_count(jsonb), rb_post_stock_count(bigint), rb_cancel_stock_count(bigint, text),
  rb_save_stock_adjustment(jsonb), rb_approve_stock_adjustment(bigint), rb_refuse_stock_adjustment(bigint, text),
  rb_reverse_stock_entry(text, bigint, date, text),
  rb_stock_list(date), rb_wip_lots(date), rb_batch_list(date, date), rb_batch_detail(bigint),
  rb_stock_movements(int, int, date, date), rb_stock_count_detail(bigint), rb_stock_adjustment_list(), rb_stock_count_list(),
  rb_yield_report(date, date), rb_wastage_report(date, date), rb_stock_on_hand(date)
  to authenticated;

-- ---------------------------------------------------------------------
-- 10. DEMO data: 12 batches in Nov 2026 from the DEMO purchases (fish
--     bought with no bill, prepared, fried, packed into 200 g bottles),
--     two of them entered as "prepare and produce together", one with an
--     unusual loss; a posted stock count and one waiting for approval;
--     a write-off waiting for approval. Only added in training mode.
-- ---------------------------------------------------------------------

do $$
declare
  v_ds uuid := (select id from app_users where lower(email) = 'info.ruchibuds@gmail.com');
  v_acc uuid := (select id from app_users where email = 'demo.accounts@example.com');
  v_mgr uuid := coalesce((select id from app_users where email = 'demo.manager1@example.com'),
                         (select id from app_users where email = 'demo.accounts@example.com'));
  it jsonb; pk jsonb; v_g bigint; v_ga bigint; v_on bigint; v_m bigint; v_f bigint; v_c bigint; x jsonb;
begin
  if not (select training_mode from app_settings where id = 1) or exists (select 1 from production_batches where is_demo)
     or not exists (select 1 from purchases where is_demo) then
    return;
  end if;
  select jsonb_object_agg(code, id) into it from items where is_demo;
  select jsonb_object_agg(i.code || '/' || pt.code, pp.id) into pk
  from product_packs pp join items i on i.id = pp.item_id join pack_types pt on pt.id = pp.pack_type_id where pp.is_demo;

  -- Ginger, garlic and onion bought at the farm gate on credit (no bill), for the preparation examples.
  perform rb_pur_save_direct(jsonb_build_object('supplier_id', (select id from suppliers where code = 'DEMO-S05'), 'purchase_date', '2026-11-08',
    'reason', 'Farm produce, paid at month end', 'payment_mode', 'credit', 'no_supplier_bill', true, 'note', 'Farm gate, weighed on our scale (DEMO)',
    'lines', jsonb_build_array(
      jsonb_build_object('item_id', it->'D-RM06', 'unit_code', 'kg', 'qty', 5, 'rate_paise', 12000),
      jsonb_build_object('item_id', it->'D-RM07', 'unit_code', 'kg', 'qty', 5, 'rate_paise', 16000),
      jsonb_build_object('item_id', it->'D-RM08', 'unit_code', 'kg', 'qty', 10, 'rate_paise', 3500))), v_mgr, true, true);

  -- 1-3. Ginger and garlic peeled on 9 Nov (shelf life 14 days, so past it by 26 Nov); onion on 20 Nov.
  v_g := rb_stk_save_prep(jsonb_build_object('batch_date', '2026-11-09', 'raw_item_id', it->'D-RM06', 'raw_qty', 5, 'raw_unit', 'kg',
    'output_qty', 4.3, 'output_unit', 'kg', 'waste_unit', 'g',
    'stages', jsonb_build_array(jsonb_build_object('stage', 'Wash', 'wastage', 100), jsonb_build_object('stage', 'Peel', 'wastage', 600))), v_mgr, true);
  v_ga := rb_stk_save_prep(jsonb_build_object('batch_date', '2026-11-09', 'raw_item_id', it->'D-RM07', 'raw_qty', 5, 'raw_unit', 'kg',
    'output_qty', 4, 'output_unit', 'kg', 'waste_unit', 'g',
    'stages', jsonb_build_array(jsonb_build_object('stage', 'Peel', 'wastage', 900), jsonb_build_object('stage', 'Chop', 'wastage', 100))), v_mgr, true);
  v_on := rb_stk_save_prep(jsonb_build_object('batch_date', '2026-11-20', 'raw_item_id', it->'D-RM08', 'raw_qty', 10, 'raw_unit', 'kg',
    'output_qty', 9, 'output_unit', 'kg', 'waste_unit', 'g',
    'stages', jsonb_build_array(jsonb_build_object('stage', 'Peel', 'wastage', 800), jsonb_build_object('stage', 'Chop', 'wastage', 200))), v_mgr, true);

  -- 4. Chilli powder ground straight from dried chilli: 100 g bottles, 1 kg pouches and some loose.
  perform rb_stk_save_production(jsonb_build_object('batch_date', '2026-11-12', 'output_item_id', it->'D-FG04', 'waste_unit', 'g',
    'inputs', jsonb_build_array(jsonb_build_object('item_id', it->'D-RM10', 'qty', 20, 'unit', 'kg')),
    'outputs', jsonb_build_array(jsonb_build_object('pack_id', pk->'D-FG04/D-PT1', 'packs', 60),
                                 jsonb_build_object('pack_id', pk->'D-FG04/D-PT4', 'packs', 10),
                                 jsonb_build_object('pack_id', null, 'qty', 3.6, 'unit', 'kg')),
    'shrinkage_qty', 200, 'packing_waste_qty', 200, 'note', 'Grinding loss recorded as shrinkage (DEMO)'), v_mgr, true);

  -- 5. Meat deboned, dried, crushed and shredded; trimmings kept to sell.
  v_m := rb_stk_save_prep(jsonb_build_object('batch_date', '2026-11-14', 'raw_item_id', it->'D-RM03', 'raw_qty', 15, 'raw_unit', 'kg',
    'output_qty', 8.3, 'output_unit', 'kg', 'waste_unit', 'g',
    'stages', jsonb_build_array(jsonb_build_object('stage', 'Debone', 'wastage', 800), jsonb_build_object('stage', 'Dry', 'wastage', 4500),
                                jsonb_build_object('stage', 'Crush', 'wastage', 100), jsonb_build_object('stage', 'Shred', 'wastage', 100)),
    'byproducts', jsonb_build_array(jsonb_build_object('item_id', it->'D-BP03', 'stage', 'Debone', 'qty', 1.2, 'unit', 'kg')),
    'note', 'Stored while drying (DEMO)'), v_mgr, true);

  -- 6-7. Fish from the fishermen (bought with no bill): cleaned, boiled and de-boned, fried,
  --      then made into fish pickle in 200 g and 500 g bottles the same day, in one entry.
  x := rb_stk_save_combined(jsonb_build_object(
    'prep', jsonb_build_object('batch_date', '2026-11-16', 'raw_item_id', it->'D-RM01', 'raw_qty', 12, 'raw_unit', 'kg',
      'output_qty', 6.5, 'output_unit', 'kg', 'waste_unit', 'g',
      'stages', jsonb_build_array(jsonb_build_object('stage', 'Clean', 'wastage', 1500), jsonb_build_object('stage', 'Boil and de-bone', 'wastage', 800),
                                  jsonb_build_object('stage', 'Fry', 'wastage', 2200)),
      'byproducts', jsonb_build_array(jsonb_build_object('item_id', it->'D-BP01', 'stage', 'Clean', 'qty', 1, 'unit', 'kg'))),
    'production', jsonb_build_object('output_item_id', it->'D-FG01', 'waste_unit', 'g',
      'inputs', jsonb_build_array(jsonb_build_object('item_id', it->'D-RM09', 'qty', 3, 'unit', 'l'),
                                  jsonb_build_object('item_id', it->'D-WP05', 'lot_batch_id', v_ga, 'qty', 500, 'unit', 'g'),
                                  jsonb_build_object('item_id', it->'D-WP04', 'lot_batch_id', v_g, 'qty', 300, 'unit', 'g')),
      'outputs', jsonb_build_array(jsonb_build_object('pack_id', pk->'D-FG01/D-PT1', 'packs', 30),
                                   jsonb_build_object('pack_id', pk->'D-FG01/D-PT2', 'packs', 6)),
      'shrinkage_qty', 600, 'packing_waste_qty', 100, 'note', 'Same-day fish pickle (DEMO)')), v_mgr, true);
  v_f := (x->>'production_id')::bigint;

  -- 8-9. The second catch: prepared on its own, then produced in a separate entry.
  v_c := rb_stk_save_prep(jsonb_build_object('batch_date', '2026-11-18', 'raw_item_id', it->'D-RM01', 'raw_qty', 8.5, 'raw_unit', 'kg',
    'output_qty', 4.5, 'output_unit', 'kg', 'waste_unit', 'g',
    'stages', jsonb_build_array(jsonb_build_object('stage', 'Clean', 'wastage', 1000), jsonb_build_object('stage', 'Boil and de-bone', 'wastage', 600),
                                jsonb_build_object('stage', 'Fry', 'wastage', 1700)),
    'byproducts', jsonb_build_array(jsonb_build_object('item_id', it->'D-BP01', 'stage', 'Clean', 'qty', 0.7, 'unit', 'kg'))), v_mgr, true);
  perform rb_stk_save_production(jsonb_build_object('batch_date', '2026-11-18', 'output_item_id', it->'D-FG01', 'waste_unit', 'g',
    'inputs', jsonb_build_array(jsonb_build_object('item_id', it->'D-WP01', 'lot_batch_id', v_c, 'qty', 4.5, 'unit', 'kg'),
                                jsonb_build_object('item_id', it->'D-RM09', 'qty', 2, 'unit', 'l')),
    'outputs', jsonb_build_array(jsonb_build_object('pack_id', pk->'D-FG01/D-PT1', 'packs', 30)),
    'shrinkage_qty', 200, 'packing_waste_qty', 100), v_mgr, true);

  -- 10-11. Chicken: skinned (skin kept to sell), boiled, deboned and shredded, into chicken pickle the same day.
  perform rb_stk_save_combined(jsonb_build_object(
    'prep', jsonb_build_object('batch_date', '2026-11-19', 'raw_item_id', it->'D-RM02', 'raw_qty', 10, 'raw_unit', 'kg',
      'output_qty', 5.4, 'output_unit', 'kg', 'waste_unit', 'g',
      'stages', jsonb_build_array(jsonb_build_object('stage', 'Skin', 'wastage', 200), jsonb_build_object('stage', 'Boil', 'wastage', 1500),
                                  jsonb_build_object('stage', 'Debone', 'wastage', 2000), jsonb_build_object('stage', 'Shred', 'wastage', 100)),
      'byproducts', jsonb_build_array(jsonb_build_object('item_id', it->'D-BP02', 'stage', 'Skin', 'qty', 0.8, 'unit', 'kg'))),
    'production', jsonb_build_object('output_item_id', it->'D-FG02', 'waste_unit', 'g',
      'inputs', jsonb_build_array(jsonb_build_object('item_id', it->'D-RM09', 'qty', 2.5, 'unit', 'l'),
                                  jsonb_build_object('item_id', it->'D-WP05', 'lot_batch_id', v_ga, 'qty', 400, 'unit', 'g'),
                                  jsonb_build_object('item_id', it->'D-WP04', 'lot_batch_id', v_g, 'qty', 300, 'unit', 'g')),
      'outputs', jsonb_build_array(jsonb_build_object('pack_id', pk->'D-FG02/D-PT1', 'packs', 25),
                                   jsonb_build_object('pack_id', pk->'D-FG02/D-PT2', 'packs', 4)),
      'shrinkage_qty', 1200, 'packing_waste_qty', 100)), v_mgr, true);

  -- 12. Smoked meat pickle from the dried meat and onion.
  perform rb_stk_save_production(jsonb_build_object('batch_date', '2026-11-21', 'output_item_id', it->'D-FG03', 'waste_unit', 'g',
    'inputs', jsonb_build_array(jsonb_build_object('item_id', it->'D-WP03', 'lot_batch_id', v_m, 'qty', 4, 'unit', 'kg'),
                                jsonb_build_object('item_id', it->'D-WP06', 'lot_batch_id', v_on, 'qty', 2, 'unit', 'kg'),
                                jsonb_build_object('item_id', it->'D-RM09', 'qty', 2, 'unit', 'l')),
    'outputs', jsonb_build_array(jsonb_build_object('pack_id', pk->'D-FG03/D-PT1', 'packs', 35)),
    'shrinkage_qty', 800, 'packing_waste_qty', 100), v_mgr, true);

  -- 13. The rest of the meat, with an unusual loss: a tray fell on the floor.
  perform rb_stk_save_prep(jsonb_build_object('batch_date', '2026-11-24', 'raw_item_id', it->'D-RM03', 'raw_qty', 4.4, 'raw_unit', 'kg',
    'output_qty', 2.2, 'output_unit', 'kg', 'waste_unit', 'g',
    'stages', jsonb_build_array(jsonb_build_object('stage', 'Debone', 'wastage', 300), jsonb_build_object('stage', 'Dry', 'wastage', 1300),
                                jsonb_build_object('stage', 'Crush', 'wastage', 50), jsonb_build_object('stage', 'Shred', 'wastage', 50)),
    'abnormal_qty', 500, 'abnormal_reason', 'Drying tray fell on the floor (DEMO)'), v_mgr, true);

  -- A stock count of oil and bottles on 25 Nov, approved by the Accountant: 150 ml of oil short, 2 bottles over.
  v_c := rb_stk_save_count(jsonb_build_object('count_date', '2026-11-25', 'note', 'Month-end count of oil and bottles (DEMO)',
    'lines', jsonb_build_array(
      jsonb_build_object('item_id', it->'D-RM09', 'qty', 35.35, 'unit', 'l', 'reason', 'Spillage while filling'),
      jsonb_build_object('item_id', it->'D-PK01', 'qty', 310, 'unit', 'pc', 'reason', 'Found in the store room'),
      jsonb_build_object('item_id', it->'D-PK02', 'qty', 290, 'unit', 'pc'))), v_mgr, true);
  perform rb_stk_post_count(v_c, v_acc);
  -- A count of finished goods, waiting for approval.
  perform rb_stk_save_count(jsonb_build_object('count_date', '2026-11-26', 'note', 'Finished goods shelf count (DEMO)',
    'lines', jsonb_build_array(
      jsonb_build_object('item_id', it->'D-FG01', 'pack_id', pk->'D-FG01/D-PT1', 'packs', 59, 'reason', 'One bottle cracked'),
      jsonb_build_object('item_id', it->'D-FG01', 'pack_id', pk->'D-FG01/D-PT2', 'packs', 6),
      jsonb_build_object('item_id', it->'D-FG02', 'pack_id', pk->'D-FG02/D-PT1', 'packs', 25))), v_mgr, true);
  -- Ginger past its shelf life: written off by the Manager, waiting for approval.
  perform rb_stk_save_adjustment(jsonb_build_object('kind', 'write_off', 'adj_date', '2026-11-26', 'item_id', it->'D-WP04',
    'lot_batch_id', v_g, 'qty', 1, 'unit', 'kg', 'reason', 'Past its 14-day shelf life, gone soft (DEMO)'), v_mgr, true);
  -- Chicken skin written off by the Accountant and posted (dogs got into the cold store).
  v_c := rb_stk_save_adjustment(jsonb_build_object('kind', 'write_off', 'adj_date', '2026-11-22', 'item_id', it->'D-BP02',
    'qty', 300, 'unit', 'g', 'reason', 'Spoilt: cold store door left open (DEMO)'), v_acc, true);
  perform rb_stk_post_adjustment(v_c, v_acc);
end $$;

-- End of 04_stock_production.sql
