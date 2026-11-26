-- Behaviour tests for 04_stock_production.sql. Run against a throwaway database only,
-- after supabase_stub.sql, 01_core_users.sql, 02_masters.sql, 03_purchases.sql and 04_stock_production.sql.
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
create or replace function public.t_bal(p_code text, p_item int default null) returns bigint language sql security definer as $$
  select coalesce(sum(l.debit_paise - l.credit_paise), 0)::bigint from journal_lines l join journals j on j.id = l.journal_id
  where l.account_code = p_code and j.status <> 'draft' and (p_item is null or l.item_id = p_item) $$;
create or replace function public.t_val(p_item int, p_pack int default null) returns bigint language sql security definer as $$
  select coalesce(sum(value_paise), 0)::bigint from stock_moves where item_id = p_item and pack_id is not distinct from p_pack $$;
create or replace function public.t_qty(p_item int, p_pack int default null) returns numeric language sql security definer as $$
  select coalesce(sum(qty_base), 0) from stock_moves where item_id = p_item and pack_id is not distinct from p_pack $$;
-- Books balance, and every stock account equals the stock record of its items, item by item.
create or replace function public.t_books_agree() returns boolean language sql security definer as $$
  select (select sum(debit_paise) = sum(credit_paise) from journal_lines)
     and not exists (
       select 1 from (
         select i.id, case i.kind when 'raw' then '10030105' when 'packaging' then '10030110' when 'wip' then '10030120' else '10030125' end acc,
                coalesce((select sum(value_paise) from stock_moves m where m.item_id = i.id), 0) stock
         from items i) s
       where s.stock <> t_bal(s.acc, s.id))
     and (select coalesce(sum(debit_paise - credit_paise), 0) from journal_lines where account_code like '100301%')
         = (select coalesce(sum(value_paise), 0) from stock_moves) $$;
create or replace function public.t_lot(p_lot bigint) returns numeric language sql security definer as $$
  select coalesce(sum(qty_base), 0) from stock_moves where lot_batch_id = p_lot $$;
grant execute on function public.t_bal(text, int), public.t_val(int, int), public.t_qty(int, int), public.t_books_agree(), public.t_lot(bigint) to authenticated;
set client_min_messages = notice;

-- 0. DEMO data
select t_ok((select count(*) from production_batches where is_demo) >= 10, '10+ DEMO batches');
select t_ok((select count(*) from production_batches where is_demo and kind = 'preparation') = 8
        and (select count(*) from production_batches where is_demo and kind = 'production') = 5, 'DEMO has 8 preparation and 5 production batches');
select t_ok((select batch_no from production_batches where is_demo and kind = 'preparation' order by id limit 1) = 'DEMO-PRP/2611/00001'
        and (select batch_no from production_batches where is_demo and kind = 'production' order by id limit 1) = 'DEMO-PRD/2611/00001',
            'DEMO batches have their own DEMO-PRP and DEMO-PRD series');
select t_ok((select count(*) from production_batches where is_demo and linked_batch_id is not null) = 4, 'Two DEMO "prepare and produce together" pairs, linked both ways');
select t_ok(exists (select 1 from production_batches where is_demo and abnormal_value_paise > 0), 'A DEMO batch shows an unusual loss charged to expense');
select t_ok(t_books_agree(), 'Books balance; each stock account = the stock record, item by item');
select t_ok(not exists (select 1 from stock_moves group by item_id, pack_id having sum(qty_base) < 0), 'No DEMO stock below zero');
select t_ok(t_bal('10010110') >= 0 and t_bal('10010205') >= 0, 'DEMO cash and bank never go below zero');
select t_ok((select status from stock_counts where is_demo order by id limit 1) = 'posted'
        and (select status from stock_counts where is_demo order by id desc limit 1) = 'draft', 'One DEMO count posted, one waiting for approval');
select t_ok((select count(*) from stock_adjustments where is_demo and status = 'awaiting_approval') = 1, 'A DEMO write-off waits for approval');
select t_ok((select count(*) from screens where code in ('stock', 'production') and available) = 2, 'Stock and Production screens are live');
select t_ok(t_bal('70010150') > 0 and t_bal('70010155') <> 0, 'DEMO write-off, unusual loss and count differences reach the expense accounts');

-- People
insert into auth.users(id, email) values ('00000000-0000-0000-0000-0000000000d1', 'info.ruchibuds@gmail.com');
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
select rb_login_ok() is not null;
select rb_invite_user('acc@example.com', 'Real Accountant', 'RA', null, (select id from user_categories where name='Accountant'), '2027-01-31');
select rb_invite_user('mgr@example.com', 'Real Manager', 'RM', null, (select id from user_categories where name='Manager'), null);
select rb_invite_user('staff@example.com', 'Real Staff', 'RS', null, (select id from user_categories where name='Staff'), null);
reset role;
insert into auth.users(id, email) values
 ('00000000-0000-0000-0000-0000000000a1', 'acc@example.com'),
 ('00000000-0000-0000-0000-0000000000e1', 'mgr@example.com'),
 ('00000000-0000-0000-0000-0000000000c1', 'staff@example.com');
-- Test items: a raw material that becomes a prepared ingredient (2-day shelf life), a sellable
-- by-product at ₹50 a kg, oil, a jar, and a pickle sold in 250 g jars.
insert into items (code, name, kind, base_unit, buy_unit, shelf_life_days) values ('T-WP', 'Test prawns, cleaned', 'wip', 'g', 'g', 2);
insert into items (code, name, kind, base_unit, buy_unit, stages, prepared_item_id) values
  ('T-RM', 'Test prawns', 'raw', 'g', 'kg', '{Clean,Cut}', (select id from items where code = 'T-WP'));
insert into items (code, name, kind, base_unit, buy_unit, byproduct_use, sells_by, loose_price_paise) values
  ('T-BP', 'Test prawn shells', 'byproduct', 'g', 'g', 'sellable', 'weight', 5000);
insert into items (code, name, kind, base_unit, buy_unit) values ('T-OIL', 'Test oil', 'raw', 'ml', 'l'), ('T-PK', 'Test jar', 'packaging', 'pc', 'pc');
insert into items (code, name, kind, base_unit, buy_unit, sells_by) values ('T-FG', 'Test prawn pickle', 'finished', 'g', 'g', 'pack');
insert into pack_types (code, name, kind, packaging_item_id) values ('T-PT', '250 g test jar', 'jar', (select id from items where code = 'T-PK'));
insert into product_packs (item_id, pack_type_id, net_qty, retail_price_paise) values
  ((select id from items where code = 'T-FG'), (select id from pack_types where code = 'T-PT'), 250, 30000);
set role authenticated;
\set rm '(select id from items where code = ''T-RM'')'
\set wp '(select id from items where code = ''T-WP'')'
\set bp '(select id from items where code = ''T-BP'')'
\set oil '(select id from items where code = ''T-OIL'')'
\set pk '(select id from items where code = ''T-PK'')'
\set fg '(select id from items where code = ''T-FG'')'
\set jar '(select id from product_packs where item_id = (select id from items where code = ''T-FG''))'
\set dir '00000000-0000-0000-0000-0000000000d1'
\set acc '00000000-0000-0000-0000-0000000000a1'
\set mgr '00000000-0000-0000-0000-0000000000e1'
\set staff '00000000-0000-0000-0000-0000000000c1'

-- 1. Staff see no stock or production
select set_config('request.jwt.claim.sub', :'staff', false);
select t_err($$select * from rb_stock_list()$$, 'right to see stock');
select t_err($$select rb_save_preparation('{}')$$, 'right to enter production batches');
select t_ok((select count(*) from production_batches) = 0 and (select count(*) from stock_moves) = 0, 'Staff cannot read batches or stock moves');
select t_err($$select rb_stk_issue(current_date, 1, null, null, 1, 'count', null, null, null, null, 1, null, false, null)$$, 'permission denied');

-- 2. Opening stock, entered and approved by the accounts side
select set_config('request.jwt.claim.sub', :'mgr', false);
select t_err($$select rb_save_stock_count(jsonb_build_object('purpose', 'opening', 'count_date', '2026-11-20', 'lines', '[]'::jsonb))$$, 'entered by the Accountant');
select set_config('request.jwt.claim.sub', :'acc', false);
select rb_save_stock_count(jsonb_build_object('purpose', 'opening', 'count_date', '2026-11-20', 'lines', jsonb_build_array(
  jsonb_build_object('item_id', :rm, 'qty', 10, 'unit', 'kg', 'rate_paise', 10000),
  jsonb_build_object('item_id', :oil, 'qty', 2, 'unit', 'l', 'rate_paise', 15000),
  jsonb_build_object('item_id', :pk, 'qty', 40, 'unit', 'pc', 'rate_paise', 1000)))) as os \gset
select t_ok((select count_no from stock_counts where id = :os) = 'TRN-OS/2611/00001', 'Opening stock numbered TRN-OS/YYMM/00001 in training');
select set_config('request.jwt.claim.sub', :'dir', false);
select rb_post_stock_count(:os);
select t_ok(t_qty(:rm) = 10000 and t_val(:rm) = 100000 and t_val(:oil) = 30000 and t_val(:pk) = 40000, 'Opening stock in at cost: 10 kg prawns ₹1,000, 2 l oil ₹300, 40 jars ₹400');
select t_ok(t_bal('97010105') = -170000, 'Opening stock is credited to the opening balance clearing account');

-- 3. Manager prepares prawns: stages, a sellable by-product and an unusual loss
select set_config('request.jwt.claim.sub', :'mgr', false);
select t_err($$select rb_save_preparation(jsonb_build_object('batch_date', '2026-11-21', 'raw_item_id', (select id from items where code = 'T-RM'),
  'raw_qty', 20, 'raw_unit', 'kg', 'output_qty', 15, 'output_unit', 'kg'))$$, 'Not enough Test prawns');
select t_err($$select rb_save_preparation(jsonb_build_object('batch_date', '2026-11-21', 'raw_item_id', (select id from items where code = 'T-OIL'),
  'raw_qty', 1, 'raw_unit', 'l', 'output_qty', 1, 'output_unit', 'kg'))$$, 'prepared ingredient it becomes');
select t_err($$select rb_save_preparation(jsonb_build_object('batch_date', '2026-11-21', 'raw_item_id', (select id from items where code = 'T-RM'),
  'raw_qty', 6, 'raw_unit', 'kg', 'output_qty', 4, 'output_unit', 'kg', 'abnormal_qty', 200))$$, 'unusual loss');
select rb_save_preparation(jsonb_build_object('batch_date', '2026-11-21', 'raw_item_id', :rm, 'raw_qty', 6, 'raw_unit', 'kg',
  'output_qty', 4, 'output_unit', 'kg', 'waste_unit', 'g',
  'stages', jsonb_build_array(jsonb_build_object('stage', 'Clean', 'wastage', 500), jsonb_build_object('stage', 'Cut', 'wastage', 300)),
  'byproducts', jsonb_build_array(jsonb_build_object('item_id', :bp, 'stage', 'Clean', 'qty', 1, 'unit', 'kg')),
  'abnormal_qty', 200, 'abnormal_reason', 'Bucket spilt')) as l1 \gset
select t_ok((rb_batch_detail(:l1)->'batch'->>'batch_no') = 'TRN-PRP/2611/00001', 'Preparation numbered TRN-PRP/YYMM/00001 in training');
select t_ok((rb_batch_detail(:l1)->'batch'->>'output_item_id')::int = :wp, 'The prepared ingredient comes from the raw material''s set-up');
select t_ok((rb_batch_detail(:l1)->'batch'->>'output_value_paise') is null and (rb_batch_detail(:l1)->'can'->>'see_cost')::boolean = false,
            'The Manager does not see batch costs');
select t_ok((select count(*) from production_batches) = 0, 'The Manager cannot read the batch tables (they hold costs)');
select t_ok((select value_paise from rb_stock_list() where item_id = (select id from items where code = 'T-WP')) is null, 'The Manager sees stock quantities but not values');
select set_config('request.jwt.claim.sub', :'dir', false);
select t_ok((select input_value_paise from production_batches where id = :l1) = 60000, 'Raw material in at weighted average cost: 6 kg × ₹100 = ₹600');
select t_ok((select abnormal_value_paise from production_batches where id = :l1) = 2000, 'Unusual loss of 0.2 kg in 6 kg = ₹20, taken out of the batch cost');
select t_ok((select byproduct_value_paise from production_batches where id = :l1) = 5000 and t_val(:bp) = 5000 and t_qty(:bp) = 1000,
            'Sellable by-product into stock at its selling price: 1 kg × ₹50');
select t_ok((select output_value_paise from production_batches where id = :l1) = 53000 and t_val(:wp) = 53000 and t_qty(:wp) = 4000,
            'Prepared prawns carry the rest: ₹600 − ₹20 − ₹50 = ₹530 for 4 kg');
select t_ok(t_bal('70010150') = (select sum(abnormal_value_paise) from production_batches where status = 'posted')
                                + (select coalesce(sum(value_paise), 0) from stock_adjustments where status = 'posted'), 'Unusual losses are charged to Inventory Write-down Expense');
select t_ok((select string_agg(stage || '=' || trim_scale(wastage_qty_base), ',' order by stage_no) from batch_stages where batch_id = :l1) = 'Clean=500,Cut=300',
            'Wastage recorded at each stage');
select t_ok(t_books_agree(), 'Books agree after preparation');

-- A second, smaller preparation the next day (a second batch of the same prepared ingredient)
select set_config('request.jwt.claim.sub', :'mgr', false);
select rb_save_preparation(jsonb_build_object('batch_date', '2026-11-22', 'raw_item_id', :rm, 'raw_qty', 2, 'raw_unit', 'kg',
  'output_qty', 1500, 'output_unit', 'g')) as l2 \gset
select t_ok((select count(*) from rb_wip_lots('2026-11-22') where item_id = :wp) = 2, 'Prepared stock is kept batch by batch');
select t_ok((select expired from rb_wip_lots('2026-11-26') where lot_batch_id = :l2) and not (select expired from rb_wip_lots('2026-11-23') where lot_batch_id = :l2),
            'Prepared stock past its 2-day shelf life is flagged');
select t_ok((select expired_qty from rb_stock_list('2026-11-26') where item_id = :wp) = 5500, 'The stock list counts what is past its shelf life');

-- 4. Final production: prepared prawns (oldest batch first), oil, into 250 g jars; each jar uses one empty jar
select t_err(format($$select rb_save_production(jsonb_build_object('batch_date', '2026-11-23', 'output_item_id', %s,
  'inputs', jsonb_build_array(jsonb_build_object('item_id', %s, 'qty', 10, 'unit', 'kg')),
  'outputs', jsonb_build_array(jsonb_build_object('pack_id', %s, 'packs', 16))))$$, :fg, :wp, :jar), 'Not enough Test prawns, cleaned');
select t_err(format($$select rb_save_production(jsonb_build_object('batch_date', '2026-11-23', 'output_item_id', %s,
  'inputs', jsonb_build_array(jsonb_build_object('item_id', %s, 'lot_batch_id', %s, 'qty', 2, 'unit', 'kg')),
  'outputs', jsonb_build_array(jsonb_build_object('pack_id', %s, 'packs', 16))))$$, :fg, :wp, :l2, :jar), 'has only 1500');
select t_err(format($$select rb_save_production(jsonb_build_object('batch_date', '2026-11-23', 'output_item_id', %s,
  'inputs', jsonb_build_array(jsonb_build_object('item_id', %s, 'qty', 1, 'unit', 'kg')),
  'outputs', jsonb_build_array(jsonb_build_object('qty', 1, 'unit', 'kg'))))$$, :fg, :wp), 'sold only in packs');
select t_err(format($$select rb_save_production(jsonb_build_object('batch_date', '2026-11-23', 'output_item_id', %s,
  'inputs', jsonb_build_array(jsonb_build_object('item_id', %s, 'qty', 1, 'unit', 'kg')),
  'outputs', jsonb_build_array(jsonb_build_object('pack_id', %s, 'packs', 1.5))))$$, :fg, :wp, :jar), 'whole numbers');
select rb_save_production(jsonb_build_object('batch_date', '2026-11-23', 'output_item_id', :fg, 'waste_unit', 'g',
  'inputs', jsonb_build_array(jsonb_build_object('item_id', :wp, 'qty', 4.5, 'unit', 'kg'), jsonb_build_object('item_id', :oil, 'qty', 500, 'unit', 'ml')),
  'outputs', jsonb_build_array(jsonb_build_object('pack_id', :jar, 'packs', 16)), 'shrinkage_qty', 600, 'packing_waste_qty', 100)) as p1 \gset
select set_config('request.jwt.claim.sub', :'dir', false);
select t_ok((select batch_no from production_batches where id = :p1) = 'TRN-PRD/2611/00001', 'Production numbered TRN-PRD/YYMM/00001 in training');
select t_ok((select string_agg(coalesce(lot_batch_id::text, '-') || ':' || trim_scale(qty_base), ',' order by line_no) from batch_lines where batch_id = :p1 and role = 'input' and item_id = :wp)
            = :l1 || ':4000,' || :l2 || ':500', 'No batch picked: the oldest prepared batch is used first (4 kg, then 0.5 kg)');
select t_ok((select value_paise from batch_lines where batch_id = :p1 and role = 'input' and item_id = :wp and lot_batch_id = :l1)
          + (select value_paise from batch_lines where batch_id = :p1 and role = 'input' and item_id = :wp and lot_batch_id = :l2) = 59727,
            'Prepared prawns go in at weighted average cost: 4.5 kg of ₹730 for 5.5 kg = ₹597.27');
select t_ok((select packaging_value_paise from production_batches where id = :p1) = 16000 and t_qty(:pk) = 24, 'Sixteen jars used at ₹10 each');
select t_ok((select output_value_paise from production_batches where id = :p1) = 59727 + 7500 + 16000 and t_val(:fg, :jar) = 83227 and t_qty(:fg, :jar) = 4000,
            'Finished goods carry prawns + oil + jars: ₹832.27 for 16 jars (4 kg)');
select t_ok((select packs from rb_stock_list() where item_id = (select id from items where code = 'T-FG') and pack_id is not null) = 16, 'Finished goods are counted in jars');
select t_ok((select shrinkage_qty_base from production_batches where id = :p1) = 600 and (select packing_waste_qty_base from production_batches where id = :p1) = 100,
            'Frying shrinkage and packing wastage recorded');
select t_ok(t_books_agree(), 'Books agree after production');

-- 5. Prepare and produce together: both batches in one go, linked
select set_config('request.jwt.claim.sub', :'mgr', false);
select rb_save_prep_and_production(jsonb_build_object(
  'prep', jsonb_build_object('batch_date', '2026-11-24', 'raw_item_id', :rm, 'raw_qty', 2, 'raw_unit', 'kg', 'output_qty', 1.6, 'output_unit', 'kg',
          'stages', jsonb_build_array(jsonb_build_object('stage', 'Clean', 'wastage', 400))),
  'production', jsonb_build_object('output_item_id', :fg, 'inputs', jsonb_build_array(jsonb_build_object('item_id', :oil, 'qty', 0.2, 'unit', 'l')),
          'outputs', jsonb_build_array(jsonb_build_object('pack_id', :jar, 'packs', 6))))) as pair \gset
select set_config('request.jwt.claim.sub', :'dir', false);
select t_ok((select linked_batch_id from production_batches where id = (:'pair'::jsonb->>'preparation_id')::bigint) = (:'pair'::jsonb->>'production_id')::bigint
        and (select linked_batch_id from production_batches where id = (:'pair'::jsonb->>'production_id')::bigint) = (:'pair'::jsonb->>'preparation_id')::bigint,
            'Prepare and produce together makes two linked batches');
select t_ok((select batch_no from production_batches where id = (:'pair'::jsonb->>'preparation_id')::bigint) = 'TRN-PRP/2611/00003'
        and (select batch_no from production_batches where id = (:'pair'::jsonb->>'production_id')::bigint) = 'TRN-PRD/2611/00002', 'Each keeps its own running number');
select t_ok(t_lot((:'pair'::jsonb->>'preparation_id')::bigint) = 0, 'All of the same-day preparation went into production');

-- 6. Reversals
select set_config('request.jwt.claim.sub', :'mgr', false);
select t_err(format('select rb_reverse_batch(%s, ''2026-11-25'', ''wrong'')', :l1), 'right to reverse');
select set_config('request.jwt.claim.sub', :'acc', false);
select t_err(format('select rb_reverse_batch(%s, ''2026-11-25'', ''wrong'')', :l1), 'gone into a production batch');
select t_err(format('select rb_reverse_journal((select journal_id from production_batches where id = %s), ''2026-11-25'', ''x'')', :p1), 'Reverse it there');
select rb_reverse_batch(:p1, '2026-11-25', 'Wrong jar size entered');
select t_ok(t_qty(:fg, :jar) = 1500 and t_qty(:pk) = 34 and t_lot(:l1) = 4000,
            'Reversing production takes the jars back out and returns the prepared prawns to their batch');
select rb_reverse_batch(:l1, '2026-11-25', 'Entered on the wrong day');
select t_ok((select status from production_batches where id = :l1) = 'reversed' and t_qty(:bp) = 0 and t_qty(:rm) = 10000 - 2000 - 2000,
            'Then the preparation can be reversed: raw material back, by-product out');
select t_ok(t_books_agree(), 'Books agree after reversals');
select t_err(format('select rb_reverse_batch(%s, ''2026-11-25'', ''again'')', :l1), 'already reversed');

-- 7. Stock count: Manager counts, someone else approves
select set_config('request.jwt.claim.sub', :'mgr', false);
select rb_save_stock_count(jsonb_build_object('count_date', '2026-11-25', 'lines', jsonb_build_array(
  jsonb_build_object('item_id', :oil, 'qty', 1.7, 'unit', 'l', 'reason', 'Spilt'),
  jsonb_build_object('item_id', :pk, 'qty', 35, 'unit', 'pc'),
  jsonb_build_object('item_id', :fg, 'pack_id', :jar, 'packs', 6),
  jsonb_build_object('item_id', :rm, 'qty', '')))) as sc \gset
select t_ok(jsonb_array_length(rb_stock_count_detail(:sc)->'lines') = 3 and (rb_stock_count_detail(:sc)->'lines'->0->>'value_paise') is null, 'Lines left blank are not counted; the Manager sees no values');
select t_err(format('select rb_post_stock_count(%s)', :sc), 'cannot approve your own');
select set_config('request.jwt.claim.sub', :'acc', false);
select rb_post_stock_count(:sc);
select t_ok((select diff_qty_base from stock_count_lines where count_id = :sc and item_id = :oil) = -100
        and (select diff_qty_base from stock_count_lines where count_id = :sc and item_id = :pk) = 1
        and (select diff_qty_base from stock_count_lines where count_id = :sc and item_id = :fg) = 0, 'Differences against the books on the count date');
select t_ok((select short_paise from stock_counts where id = :sc) = 1500 and (select excess_paise from stock_counts where id = :sc) = 1000,
            'Shortage 100 ml oil at ₹0.15 a ml = ₹15; one extra jar at ₹10');
select t_ok(t_qty(:oil) = 1700 and t_qty(:pk) = 35, 'Stock now equals the count');
select t_ok(t_books_agree(), 'Books agree after the count');
select t_err(format('select rb_post_stock_count(%s)', :sc), 'already posted');

-- 8. Write-offs and write-downs
select set_config('request.jwt.claim.sub', :'mgr', false);
select rb_save_stock_adjustment(jsonb_build_object('kind', 'write_off', 'adj_date', '2026-11-26', 'item_id', :wp, 'lot_batch_id', :l2,
  'qty', 1.5, 'unit', 'kg', 'reason', 'Past its shelf life')) as wo \gset
select t_ok((select status from rb_stock_adjustment_list() where id = :wo) = 'awaiting_approval', 'A Manager''s write-off waits for approval');
select t_err(format('select rb_approve_stock_adjustment(%s)', :wo), 'cannot approve your own');
select t_err($$select rb_save_stock_adjustment(jsonb_build_object('kind', 'write_down', 'adj_date', '2026-11-26', 'item_id', (select id from items where code = 'T-FG'),
  'pack_id', (select id from product_packs where item_id = (select id from items where code = 'T-FG')), 'value_paise', 100, 'reason', 'x'))$$, 'entered by the Accountant');
select set_config('request.jwt.claim.sub', :'acc', false);
select rb_approve_stock_adjustment(:wo);
select t_ok((select status from stock_adjustments where id = :wo) = 'posted' and t_lot(:l2) = 0,
            'Approved: the expired batch is written off');
select set_config('request.jwt.claim.sub', :'dir', false);
select rb_save_stock_adjustment(jsonb_build_object('kind', 'write_down', 'adj_date', '2026-11-26', 'item_id', :fg, 'pack_id', :jar,
  'value_paise', 5000, 'reason', 'Selling price cut below cost')) as wd \gset
select t_ok((select status from stock_adjustments where id = :wd) = 'posted' and t_qty(:fg, :jar) = 1500, 'A Director''s write-down posts at once and leaves the quantity');
select t_err($$select rb_save_stock_adjustment(jsonb_build_object('kind', 'write_down', 'adj_date', '2026-11-26', 'item_id', (select id from items where code = 'T-FG'),
  'pack_id', (select id from product_packs where item_id = (select id from items where code = 'T-FG')), 'value_paise', 99999999, 'reason', 'x'))$$, 'more than the stock');
select t_ok(t_books_agree(), 'Books agree after write-offs and write-downs');
select rb_reverse_stock_entry('adjustment', :wd, '2026-11-26', 'Price cut cancelled');
select t_ok((select status from stock_adjustments where id = :wd) = 'reversed', 'A write-down can be reversed');
select t_ok(t_books_agree(), 'Books agree after reversing the write-down');

-- 9. Learning phase delete, period lock
select set_config('request.jwt.claim.sub', :'acc', false);
select rb_save_preparation(jsonb_build_object('batch_date', '2026-11-26', 'raw_item_id', :rm, 'raw_qty', 1, 'raw_unit', 'kg', 'output_qty', 0.8, 'output_unit', 'kg')) as ld \gset
select set_config('request.jwt.claim.sub', :'dir', false);
select t_err(format('select rb_hard_delete_batch(%s)', (:'pair'::jsonb->>'production_id')), 'learning phase');
select rb_hard_delete_batch(:ld);
select t_ok(not exists (select 1 from production_batches where id = :ld) and t_qty(:rm) = 6000, 'Director fully deletes a learning-phase user''s batch, stock back');
select t_ok(t_books_agree(), 'Books agree after the delete');
select rb_lock_period('2026-10-01', true, 'Closed');
select set_config('request.jwt.claim.sub', :'mgr', false);
select t_err(format($$select rb_save_preparation(jsonb_build_object('batch_date', '2026-10-15', 'raw_item_id', %s, 'raw_qty', 1, 'raw_unit', 'kg', 'output_qty', 1, 'output_unit', 'kg'))$$, :rm), 'locked');
select set_config('request.jwt.claim.sub', :'dir', false);
select rb_lock_period('2026-10-01', false, 'Test over');

-- 10. Reports and lists
select t_ok((select stages->0->>'pct' from rb_yield_report('2026-11-01', '2026-11-30') where batch_id = (:'pair'::jsonb->>'preparation_id')::bigint) = '20.0',
            'Yield report: wastage % at each stage (400 g of 2 kg = 20%)');
select t_ok((select yield_pct from rb_yield_report('2026-11-01', '2026-11-30') where batch_id = (:'pair'::jsonb->>'preparation_id')::bigint) = 80.0
        and jsonb_array_length((select finished from rb_yield_report('2026-11-01', '2026-11-30') where batch_id = (:'pair'::jsonb->>'preparation_id')::bigint)) = 1,
            'Yield report traces raw → prepared (80%) → the finished batch it went into');
select t_ok(exists (select 1 from rb_wastage_report('2026-11-01', '2026-11-30') where item = 'Test prawns' and stage = 'Clean'), 'Wastage by stage report');
select t_ok((select count(*) from rb_batch_list('2026-11-01', '2026-11-30') where batch_no like 'TRN-%') = 5, 'Batch list');
select t_ok((select count(*) from rb_stock_movements(:oil, null, '2026-11-01', '2026-11-30')) = 6
        and (select balance_qty from rb_stock_movements(:oil, null, '2026-11-01', '2026-11-30') order by move_date desc, balance_qty limit 1) = 1700,
            'Item movements with a running balance');
select t_ok((select count(*) from audit_log where action in ('PREPARATION', 'PRODUCTION', 'POST_STOCK_COUNT', 'POST_STOCK_ADJUSTMENT', 'REVERSE_BATCH')) >= 8,
            'Batches, counts and adjustments are in the audit log');

-- 11. Remove demo data, then go live
select rb_remove_demo_data('REMOVE DEMO');
select t_ok(not exists (select 1 from production_batches where is_demo) and not exists (select 1 from stock_moves where is_demo)
        and not exists (select 1 from stock_counts where is_demo) and not exists (select 1 from stock_adjustments where is_demo), 'DEMO batches, counts and stock removed');
select t_ok(t_books_agree(), 'Books still agree without the DEMO data');
select rb_go_live('2027-04-01', 'GO LIVE');
select t_ok(not exists (select 1 from production_batches) and not exists (select 1 from stock_moves) and not exists (select 1 from stock_counts),
            'Go-live clears training batches, counts and stock');
select set_config('request.jwt.claim.sub', :'acc', false);
select rb_save_stock_count(jsonb_build_object('purpose', 'opening', 'count_date', '2027-04-01', 'lines', jsonb_build_array(
  jsonb_build_object('item_id', :rm, 'qty', 1, 'unit', 'kg', 'rate_paise', 10000)))) as os2 \gset
select set_config('request.jwt.claim.sub', :'dir', false);
select rb_post_stock_count(:os2);
select set_config('request.jwt.claim.sub', :'mgr', false);
select rb_save_preparation(jsonb_build_object('batch_date', '2027-04-02', 'raw_item_id', :rm, 'raw_qty', 1, 'raw_unit', 'kg', 'output_qty', 0.9, 'output_unit', 'kg')) as l9 \gset
select set_config('request.jwt.claim.sub', :'dir', false);
select t_ok((select batch_no from production_batches where id = :l9) = 'PRP/2704/00001' and (select count_no from stock_counts where id = :os2) = 'OS/2704/00001',
            'After go-live, batches start at PRP/YYMM/00001');

reset role;
\echo ALL MODULE 4 TESTS PASSED
