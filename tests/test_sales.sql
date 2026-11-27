-- Behaviour tests for 05_sales_invoices.sql. Run against a throwaway database only,
-- after supabase_stub.sql and sql/01 to sql/05.
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
create or replace function public.t_qty(p_item int, p_pack int default null) returns numeric language sql security definer as $$
  select coalesce(sum(qty_base), 0) from stock_moves where item_id = p_item and pack_id is not distinct from p_pack $$;
-- Books balance; each stock account = the stock record item by item; the customer
-- control account = the sum of the customer ledgers; every open invoice is in the books.
create or replace function public.t_books_agree() returns boolean language sql security definer as $$
  select (select sum(debit_paise) = sum(credit_paise) from journal_lines)
     and not exists (
       select 1 from (
         select i.id, case i.kind when 'raw' then '10030105' when 'packaging' then '10030110' when 'wip' then '10030120' else '10030125' end acc,
                coalesce((select sum(value_paise) from stock_moves m where m.item_id = i.id), 0) stock
         from items i) s
       where s.stock <> (select coalesce(sum(l.debit_paise - l.credit_paise), 0) from journal_lines l join journals j on j.id = l.journal_id
                         where l.account_code = s.acc and l.item_id = s.id and j.status <> 'draft'))
     and (select coalesce(sum(debit_paise - credit_paise), 0) from journal_lines where account_code like '100301%')
         = (select coalesce(sum(value_paise), 0) from stock_moves)
     and (select coalesce(sum(debit_paise - credit_paise), 0) from journal_lines where account_code = '10020105')
         = (select coalesce(sum(rb_sal_book_balance(id, null)), 0) from customers)
     and not exists (select 1 from customers c where rb_sal_free_credit(c.id) < 0)
     and not exists (select 1 from sales where outstanding_paise < 0) $$;
create or replace function public.t_free(p int) returns bigint language sql security definer as $$ select rb_sal_free_credit(p) $$;
create or replace function public.t_book(p int, p_as_of date) returns bigint language sql security definer as $$ select rb_sal_book_balance(p, p_as_of) $$;
grant execute on function public.t_free(int), public.t_book(int, date) to authenticated;
grant execute on function public.t_bal(text), public.t_val(int, int), public.t_qty(int, int), public.t_books_agree() to authenticated;
set client_min_messages = notice;

-- 0. DEMO data
select t_ok((select count(*) from sales where is_demo) >= 10, '10+ DEMO invoices');
select t_ok((select invoice_no from sales where is_demo order by id limit 1) = 'DEMO-Inv/2611/00001', 'DEMO invoices have their own DEMO-Inv series');
select t_ok((select bool_and(invoice_date >= lag) from (select invoice_date, lag(invoice_date, 1, '1900-01-01'::date) over (order by invoice_no) lag
             from sales where is_demo) x), 'DEMO invoice numbers follow the invoice dates');
select t_ok(t_books_agree(), 'Books balance; stock and customer ledgers agree with the books');
select t_ok((select count(*) from sales_returns where is_demo and status = 'posted') = 2
        and (select count(*) from sales_returns where is_demo and status = 'awaiting_approval') = 1, 'DEMO: two credit notes posted, one return waiting for approval');
select t_ok(exists (select 1 from customer_refunds where is_demo) and (select count(*) from customer_receipts where is_demo and coalesce(note, '') not like 'Online order%') = 3, 'DEMO receipts and a refund');
select t_ok((select count(*) from customer_write_offs where is_demo and status = 'posted') = 1
        and (select count(*) from bad_debt_recoveries where is_demo and status = 'posted') = 1
        and (select t_book(id, null) from customers where code = 'DEMO-C10') = 0
        and (select t_free(id) from customers where code = 'DEMO-C10') = 0, 'DEMO: a bad debt written off and ₹1,000 of it recovered');
select t_ok((select count(*) from screens where code in ('sales', 'invoices', 'customers', 'receipts') and available) = 4, 'Sales, Invoices, Customers and Receipts screens are live');
select t_ok(not exists (select 1 from stock_moves group by item_id, pack_id having sum(qty_base) < 0), 'No DEMO stock below zero');
select t_ok((select t_book(id, null) from customers where code = 'DEMO-C06') = 0
        and (select t_free(id) from customers where code = 'DEMO-C06') = 0,
            'DEMO: a receipt clears an invoice and a balance entered by journal (no money left on account)');

-- People
insert into auth.users(id, email) values ('00000000-0000-0000-0000-0000000000d1', 'info.ruchibuds@gmail.com');
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
select rb_login_ok() is not null;
select rb_invite_user('acc@example.com', 'Real Accountant', 'RA', null, (select id from user_categories where name='Accountant'), '2027-01-31');
select rb_invite_user('mgr@example.com', 'Real Manager', 'RM', null, (select id from user_categories where name='Manager'), null);
select rb_invite_user('staff@example.com', 'Real Staff', 'RS', null, (select id from user_categories where name='Staff'), null);
select rb_invite_user('sales@example.com', 'Real Sales', 'RSL', null, (select id from user_categories where name='Sales'), null);
select rb_invite_user('ar@example.com', 'Real AR', 'RAR', null, (select id from user_categories where name='AR'), null);
reset role;
insert into auth.users(id, email) values
 ('00000000-0000-0000-0000-0000000000a1', 'acc@example.com'),
 ('00000000-0000-0000-0000-0000000000e1', 'mgr@example.com'),
 ('00000000-0000-0000-0000-0000000000c1', 'staff@example.com'),
 ('00000000-0000-0000-0000-0000000000b1', 'sales@example.com'),
 ('00000000-0000-0000-0000-0000000000f1', 'ar@example.com');
-- Test products: a pickle sold in 250 g jars and loose (12% GST), a sellable by-product,
-- and a product with no HSN code yet.
insert into items (code, name, kind, base_unit, buy_unit) values ('T-PK', 'Test jar', 'packaging', 'pc', 'pc');
insert into items (code, name, kind, base_unit, buy_unit, sells_by, loose_price_paise, hsn_code, gst_rate) values
  ('T-FG', 'Test mango pickle', 'finished', 'g', 'g', 'weight', 80000, '2001', 12),
  ('T-NH', 'Test plain papad', 'finished', 'g', 'g', 'weight', 50000, null, null);
insert into items (code, name, kind, base_unit, buy_unit, byproduct_use, sells_by, loose_price_paise) values
  ('T-BP', 'Test mango skins', 'byproduct', 'g', 'g', 'sellable', 'weight', 5000);
insert into pack_types (code, name, kind, packaging_item_id) values ('T-PT', '250 g test jar', 'jar', (select id from items where code = 'T-PK'));
insert into product_packs (item_id, pack_type_id, net_qty, retail_price_paise, trader_price_paise, online_price_paise) values
  ((select id from items where code = 'T-FG'), (select id from pack_types where code = 'T-PT'), 250, 30000, 25000, 32000);
insert into customers (code, kind, name, phone) values ('T-R1', 'retail', 'Test Retail One', '9000000001');
insert into customers (code, kind, name, state_code, credit_limit_paise, credit_days) values ('T-TR1', 'trader', 'Test Trader Local', '27', 100000, 10);
insert into customers (code, kind, name, state_code, gstin, credit_days) values ('T-TR2', 'trader', 'Test Trader Karnataka', '29', '29AAAAA0000A1Z5', 30);
set role authenticated;
\set fg '(select id from items where code = ''T-FG'')'
\set nh '(select id from items where code = ''T-NH'')'
\set bp '(select id from items where code = ''T-BP'')'
\set jar '(select id from product_packs where item_id = (select id from items where code = ''T-FG''))'
\set walk '(select id from customers where is_walk_in)'
\set r1 '(select id from customers where code = ''T-R1'')'
\set tr1 '(select id from customers where code = ''T-TR1'')'
\set tr2 '(select id from customers where code = ''T-TR2'')'
\set dir '00000000-0000-0000-0000-0000000000d1'
\set acc '00000000-0000-0000-0000-0000000000a1'
\set mgr '00000000-0000-0000-0000-0000000000e1'
\set staff '00000000-0000-0000-0000-0000000000c1'
\set sal '00000000-0000-0000-0000-0000000000b1'
\set ar '00000000-0000-0000-0000-0000000000f1'

-- 1. Opening stock: 40 jars at ₹100, 5 kg loose at ₹300 a kg, 2 kg skins at ₹50 a kg, 3 kg papad at ₹200 a kg
select set_config('request.jwt.claim.sub', :'acc', false);
select rb_save_stock_count(jsonb_build_object('purpose', 'opening', 'count_date', '2026-11-20', 'lines', jsonb_build_array(
  jsonb_build_object('item_id', :fg, 'pack_id', :jar, 'packs', 40, 'rate_paise', 10000),
  jsonb_build_object('item_id', :fg, 'qty', 5, 'unit', 'kg', 'rate_paise', 30000),
  jsonb_build_object('item_id', :bp, 'qty', 2, 'unit', 'kg', 'rate_paise', 5000),
  jsonb_build_object('item_id', :nh, 'qty', 3, 'unit', 'kg', 'rate_paise', 20000)))) as os \gset
select set_config('request.jwt.claim.sub', :'dir', false);
select rb_post_stock_count(:os);
select t_ok(t_qty(:fg, :jar) = 10000 and t_val(:fg, :jar) = 400000 and t_val(:fg) = 150000, 'Opening stock in: 40 jars ₹4,000 and 5 kg loose ₹1,500');

-- 2. Staff at the counter
select set_config('request.jwt.claim.sub', :'staff', false);
select rb_save_sale(jsonb_build_object('customer_id', :walk, 'invoice_date', '2026-11-21', 'payment_mode', 'cash',
  'lines', jsonb_build_array(jsonb_build_object('item_id', :fg, 'pack_id', :jar, 'packs', 2)))) as s1 \gset
select t_ok((:'s1'::jsonb->>'invoice_no') = 'TRN-Inv/2611/00001', 'In training, invoices are numbered TRN-Inv/YYMM/00001');
select t_ok((:'s1'::jsonb->>'total_paise')::bigint = 60000, 'Two jars at the retail price: ₹600');
select t_err($$select rb_save_sale(jsonb_build_object('customer_id', (select id from customers where is_walk_in), 'invoice_date', '2026-11-21',
  'lines', jsonb_build_array(jsonb_build_object('item_id', (select id from items where code = 'T-FG'),
  'pack_id', (select id from product_packs where item_id = (select id from items where code = 'T-FG')), 'packs', 1, 'rate_paise', 20000))))$$,
  'only at the Masters price');
select t_err($$select rb_save_sale(jsonb_build_object('customer_id', (select id from customers where is_walk_in), 'invoice_date', '2026-11-21',
  'payment_mode', 'credit', 'lines', jsonb_build_array(jsonb_build_object('item_id', (select id from items where code = 'T-FG'),
  'pack_id', (select id from product_packs where item_id = (select id from items where code = 'T-FG')), 'packs', 1))))$$,
  'walk-in sale must be paid in full');
select t_err($$select rb_save_sale(jsonb_build_object('customer_id', (select id from customers where is_walk_in), 'invoice_date', '2026-11-21',
  'payment_mode', 'cash', 'paid_paise', 10000, 'lines', jsonb_build_array(jsonb_build_object('item_id', (select id from items where code = 'T-FG'),
  'pack_id', (select id from product_packs where item_id = (select id from items where code = 'T-FG')), 'packs', 1))))$$,
  'walk-in sale must be paid in full');
select t_err($$select rb_save_sale(jsonb_build_object('customer_id', (select id from customers where is_walk_in), 'invoice_date', '2026-11-21',
  'lines', jsonb_build_array(jsonb_build_object('item_id', (select id from items where code = 'T-FG'),
  'pack_id', (select id from product_packs where item_id = (select id from items where code = 'T-FG')), 'packs', 100))))$$,
  'Stock cannot go below zero');
select t_err($$select rb_save_sale(jsonb_build_object('customer_id', (select id from customers where is_walk_in), 'invoice_date', '2026-11-21',
  'lines', jsonb_build_array(jsonb_build_object('item_id', (select id from items where code = 'T-PK'), 'qty', 1, 'unit', 'pc'))))$$,
  'only finished goods');
select rb_save_sale(jsonb_build_object('customer_id', :walk, 'invoice_date', '2026-11-21', 'payment_mode', 'upi',
  'lines', jsonb_build_array(jsonb_build_object('item_id', :fg, 'pack_id', :jar, 'packs', 1, 'discount_pct', 10)))) as s2 \gset
select t_ok((:'s2'::jsonb->>'total_paise')::bigint = 27000, 'A 10% counter discount: ₹300 less ₹30 = ₹270');
select t_ok((select total_paise from rb_sales_list('2026-11-01', '2026-11-30') where id = (:'s1'::jsonb->>'id')::bigint) is null
        and (select status from rb_sales_list('2026-11-01', '2026-11-30') where id = (:'s1'::jsonb->>'id')::bigint) = 'paid',
            'Staff see their sales but no money totals');
select t_ok((select count(*) from sales) = 0, 'Staff cannot read the sales tables (they hold costs)');
select t_ok((rb_sale_detail((:'s1'::jsonb->>'id')::bigint)->'sale'->>'cost_paise') is null, 'Staff do not see the cost of what they sold');
select t_err($$select * from rb_customer_balances()$$, 'right to see customer balances');
select t_err($$select * from rb_sales_summary('2026-11-01', '2026-11-30')$$, 'right to see sales totals');
select t_err($$select rb_refund_customer('{}')$$, 'accounts team only');
select set_config('request.jwt.claim.sub', :'dir', false);
select t_ok((select cost_paise from sales where id = (:'s1'::jsonb->>'id')::bigint) = 20000, 'Cost of sales at weighted average: 2 jars × ₹100');
select t_ok(t_bal('60010120') = -90000 and t_bal('60010140') = 3000 and t_bal('70010160') = 30000, 'Retail sales ₹900 at full price, discount ₹30 shown separately, cost of sales ₹300');
select t_ok(t_bal('10020105') = 0, 'Paid at the counter: no balance left on the customer');
select t_ok(t_qty(:fg, :jar) = 9250, '3 jars left stock');
select t_ok(t_books_agree(), 'Books agree after counter sales');

-- 3. Loose by weight and a by-product, by the Sales person
select set_config('request.jwt.claim.sub', :'sal', false);
select rb_save_sale(jsonb_build_object('customer_id', :r1, 'invoice_date', '2026-11-22', 'payment_mode', 'upi', 'payment_ref', 'UPI 1',
  'lines', jsonb_build_array(jsonb_build_object('item_id', :fg, 'qty', 750, 'unit', 'g'),
                             jsonb_build_object('item_id', :bp, 'qty', 0.5, 'unit', 'kg')))) as s3 \gset
select t_ok((:'s3'::jsonb->>'total_paise')::bigint = 62500, '750 g loose at ₹800 a kg = ₹600, plus 500 g skins at ₹50 a kg = ₹25');
select t_err($$select rb_save_sale(jsonb_build_object('customer_id', (select id from customers where code = 'T-R1'), 'invoice_date', '2026-11-22',
  'channel', 'trader', 'lines', jsonb_build_array(jsonb_build_object('item_id', (select id from items where code = 'T-FG'), 'qty', 1, 'unit', 'kg'))))$$,
  'only for trader customers');
select t_ok((select margin_paise from rb_sales_summary('2026-11-22', '2026-11-22') limit 1) is null, 'The Sales person sees totals but not margins');
select set_config('request.jwt.claim.sub', :'dir', false);
select t_ok(t_bal('60010130') = -2500 and t_bal('60010120') = -150000, 'By-product sales go to "Product Sales - Other"; the pickle to retail sales');
select t_ok((select cost_paise from sales where id = (:'s3'::jsonb->>'id')::bigint) = 22500 + 2500, 'Loose cost: 750 g at ₹0.30 a g, skins at ₹0.05 a g');

-- 4. Trader on credit, with a credit limit of ₹1,000 and 10 days
select set_config('request.jwt.claim.sub', :'sal', false);
select t_err($$select rb_save_sale(jsonb_build_object('customer_id', (select id from customers where code = 'T-TR1'), 'invoice_date', '2026-11-23',
  'payment_mode', 'credit', 'lines', jsonb_build_array(jsonb_build_object('item_id', (select id from items where code = 'T-FG'),
  'pack_id', (select id from product_packs where item_id = (select id from items where code = 'T-FG')), 'packs', 5))))$$, 'over their credit limit');
select t_err($$select rb_save_sale(jsonb_build_object('customer_id', (select id from customers where code = 'T-TR1'), 'invoice_date', '2026-11-23',
  'payment_mode', 'credit', 'override_credit_limit', true, 'lines', jsonb_build_array(jsonb_build_object('item_id', (select id from items where code = 'T-FG'),
  'pack_id', (select id from product_packs where item_id = (select id from items where code = 'T-FG')), 'packs', 5))))$$, 'Sales → Approve');
select set_config('request.jwt.claim.sub', :'mgr', false);
select rb_save_sale(jsonb_build_object('customer_id', :tr1, 'invoice_date', '2026-11-23', 'payment_mode', 'credit', 'override_credit_limit', true,
  'lines', jsonb_build_array(jsonb_build_object('item_id', :fg, 'pack_id', :jar, 'packs', 5)))) as s4 \gset
select set_config('request.jwt.claim.sub', :'dir', false);
select t_ok((select total_paise from sales where id = (:'s4'::jsonb->>'id')::bigint) = 125000
        and (select outstanding_paise from sales where id = (:'s4'::jsonb->>'id')::bigint) = 125000
        and (select due_date from sales where id = (:'s4'::jsonb->>'id')::bigint) = '2026-12-03', 'Trader price ₹250 a jar, all on credit, due in 10 days');
select t_ok(t_bal('60010115') = -125000 and t_bal('10020105') = 125000, 'Trader sales and the customer balance are in the books');
select id as l4 from sale_lines where sale_id = (:'s4'::jsonb->>'id')::bigint \gset
select id as l1 from sale_lines where sale_id = (:'s1'::jsonb->>'id')::bigint \gset

-- 5. GST: no Tax Invoice until registered; then CGST + SGST in the state, IGST outside it
select t_err($$select rb_save_sale(jsonb_build_object('customer_id', (select id from customers where code = 'T-R1'), 'invoice_date', '2026-11-24',
  'doc_type', 'tax_invoice', 'lines', jsonb_build_array(jsonb_build_object('item_id', (select id from items where code = 'T-FG'), 'qty', 100, 'unit', 'g'))))$$,
  'Until then choose Invoice');
reset role;
update app_settings set state_code = '27', address = '1 Test Road, Mumbai' where id = 1;
set role authenticated;
select rb_set_gst_registration('27ABCDE1234F1Z5', '2026-12-01');
select t_err($$select rb_save_sale(jsonb_build_object('customer_id', (select id from customers where code = 'T-R1'), 'invoice_date', '2026-11-30',
  'doc_type', 'tax_invoice', 'lines', jsonb_build_array(jsonb_build_object('item_id', (select id from items where code = 'T-FG'), 'qty', 100, 'unit', 'g'))))$$,
  'on or after that date');
select t_err($$select rb_save_sale(jsonb_build_object('customer_id', (select id from customers where code = 'T-R1'), 'invoice_date', '2026-12-02',
  'doc_type', 'tax_invoice', 'lines', jsonb_build_array(jsonb_build_object('item_id', (select id from items where code = 'T-NH'), 'qty', 100, 'unit', 'g'))))$$,
  'HSN code and GST rate');
select rb_save_sale(jsonb_build_object('customer_id', :r1, 'invoice_date', '2026-12-02', 'doc_type', 'tax_invoice', 'payment_mode', 'cash',
  'lines', jsonb_build_array(jsonb_build_object('item_id', :fg, 'pack_id', :jar, 'packs', 1)))) as t1 \gset
select t_ok((select taxable_paise from sales where id = (:'t1'::jsonb->>'id')::bigint) = 26786
        and (select cgst_paise from sales where id = (:'t1'::jsonb->>'id')::bigint) = 1607
        and (select sgst_paise from sales where id = (:'t1'::jsonb->>'id')::bigint) = 1607
        and (select total_paise from sales where id = (:'t1'::jsonb->>'id')::bigint) = 30000,
            'Price includes GST: ₹300 = ₹267.86 + CGST ₹16.07 + SGST ₹16.07 (12%)');
select rb_save_sales_settings('{"sale_prices_include_gst": false}');
select rb_save_sale(jsonb_build_object('customer_id', :tr2, 'invoice_date', '2026-12-02', 'doc_type', 'tax_invoice', 'payment_mode', 'credit',
  'lines', jsonb_build_array(jsonb_build_object('item_id', :fg, 'pack_id', :jar, 'packs', 2, 'discount_pct', 10)))) as t2 \gset
select t_ok((select taxable_paise from sales where id = (:'t2'::jsonb->>'id')::bigint) = 45000
        and (select igst_paise from sales where id = (:'t2'::jsonb->>'id')::bigint) = 5400
        and (select cgst_paise + sgst_paise from sales where id = (:'t2'::jsonb->>'id')::bigint) = 0
        and (select total_paise from sales where id = (:'t2'::jsonb->>'id')::bigint) = 50400
        and (select inter_state from sales where id = (:'t2'::jsonb->>'id')::bigint),
            'Another state, GST on top of the price: 2 × ₹250 less 10% = ₹450 + IGST 12% ₹54');
select t_ok(t_bal('30030105') = -(3214 + 5400), 'Output GST is a liability, not revenue');
select t_ok(t_bal('60010120') = -(150000 + 26786) and t_bal('60010115') = -(125000 + 50000) and t_bal('60010140') = 3000 + 5000,
            'Revenue without GST, at full price, with the discount without GST shown separately');
select t_ok((rb_sale_detail((:'t1'::jsonb->>'id')::bigint)->'firm'->>'gstin') = '27ABCDE1234F1Z5'
        and (rb_sale_detail((:'t1'::jsonb->>'id')::bigint)->'lines'->0->>'hsn_code') = '2001', 'The Tax Invoice carries the GSTIN and HSN codes');
select rb_save_sales_settings('{"sale_prices_include_gst": true}');
select t_ok(t_books_agree(), 'Books agree after Tax Invoices');

-- 6. Customer receipts (AR)
select set_config('request.jwt.claim.sub', :'ar', false);
select t_err(format($$select rb_receive_from_customer(jsonb_build_object('customer_id', %s, 'receipt_date', '2026-11-25', 'mode', 'bank',
  'amount_paise', 100000, 'allocations', jsonb_build_array(jsonb_build_object('sale_id', %s, 'amount_paise', 125000))))$$, :tr1, :'s4'::jsonb->>'id'),
  'Only ₹1,000.00 of this');
select rb_receive_from_customer(jsonb_build_object('customer_id', :tr1, 'receipt_date', '2026-11-25', 'mode', 'bank', 'reference', 'NEFT 1',
  'amount_paise', 100000, 'allocations', jsonb_build_array(jsonb_build_object('sale_id', (:'s4'::jsonb->>'id')::bigint, 'amount_paise', 80000)))) as rc1 \gset
select t_ok((select doc_no from rb_customer_receipts_list() where id = :rc1 and kind = 'receipt') = 'TRN-RCT/2611/00001', 'Receipt numbered TRN-RCT/YYMM/00001 in training');
select t_ok((rb_customer_open_items(:tr1)->'invoices'->0->>'outstanding_paise')::bigint = 45000
        and (rb_customer_open_items(:tr1)->>'on_account_paise')::bigint = 20000, '₹800 set against the invoice, ₹200 on account');
select t_err(format($$select rb_allocate_customer_credit('receipt', %s, jsonb_build_array(jsonb_build_object('sale_id', %s, 'amount_paise', 30000)))$$,
  :rc1, :'s4'::jsonb->>'id'), 'Only ₹200.00');
select rb_allocate_customer_credit('receipt', :rc1, jsonb_build_array(jsonb_build_object('sale_id', (:'s4'::jsonb->>'id')::bigint, 'amount_paise', 20000)));
select t_ok((rb_customer_open_items(:tr1)->'invoices'->0->>'outstanding_paise')::bigint = 25000
        and (rb_customer_open_items(:tr1)->>'balance_paise')::bigint = 25000, 'Money on account set against the invoice later');
select t_ok((select on_account_paise from rb_customer_receipts_list() where id = :rc1 and kind = 'receipt') = 0, 'The receipt is now fully used');
select t_err($$select rb_refund_customer('{}')$$, 'accounts team only');
select t_err(format($$select rb_save_sale(jsonb_build_object('customer_id', %s, 'invoice_date', '2026-11-25', 'lines', '[]'::jsonb))$$, :r1), 'right to make sales');

-- 7. Returns and credit notes
select set_config('request.jwt.claim.sub', :'staff', false);
select rb_save_sales_return(jsonb_build_object('sale_id', (:'s4'::jsonb->>'id')::bigint, 'return_date', '2026-11-26', 'condition', 'restock',
  'reason', 'Wrong flavour', 'lines', jsonb_build_array(jsonb_build_object('sale_line_id', :l4, 'packs', 2)))) as rt1 \gset
select t_ok((select status from rb_sales_returns_list() where id = :rt1) = 'awaiting_approval'
        and (select return_no from rb_sales_returns_list() where id = :rt1) is null, 'A return entered by Staff waits for approval, with no credit note yet');
select t_err(format('select rb_approve_sales_return(%s)', :rt1), 'right to approve returns');
select t_err(format($$select rb_save_sales_return(jsonb_build_object('sale_id', %s, 'return_date', '2026-11-26', 'reason', 'x',
  'lines', jsonb_build_array(jsonb_build_object('sale_line_id', %s, 'packs', 4))))$$,
  :'s4'::jsonb->>'id', :l4), 'Only 3 pack(s)');
select set_config('request.jwt.claim.sub', :'mgr', false);
select t_ok((select can_approve from rb_sales_returns_list() where id = :rt1), 'The Manager may approve it');
select rb_approve_sales_return(:rt1);
select set_config('request.jwt.claim.sub', :'dir', false);
select t_ok((select return_no from sales_returns where id = :rt1) = 'TRN-CN/2611/00001' and (select total_paise from sales_returns where id = :rt1) = 50000,
            'Approved: credit note TRN-CN/YYMM/00001 for 2 jars at ₹250');
select t_ok(t_qty(:fg, :jar) = 9250 - 5 * 250 - 3 * 250 + 2 * 250, 'The 2 jars are back on the shelf');
select t_ok((select outstanding_paise from sales where id = (:'s4'::jsonb->>'id')::bigint) = 0
        and t_free(:tr1) = 25000 and t_book(:tr1, null) = -25000,
            'The credit note pays off the invoice first; ₹250 over is money on account');
select t_ok(t_bal('60010135') = 50000 and t_bal('70010160') = 30000 + 25000 + 50000 + 10000 + 20000 - 20000,
            'Sales returns ₹500; the jars'' cost (₹200) comes off cost of sales');
-- The Accountant may approve their own: a spoilt return posts at once and is charged as a stock loss.
select set_config('request.jwt.claim.sub', :'acc', false);
select rb_save_sales_return(jsonb_build_object('sale_id', (:'s1'::jsonb->>'id')::bigint, 'return_date', '2026-11-26', 'condition', 'discard',
  'reason', 'Lid broken, leaking', 'lines', jsonb_build_array(jsonb_build_object('sale_line_id', :l1, 'packs', 1)))) as rt2 \gset
select t_ok((select status from sales_returns where id = :rt2) = 'posted' and (select total_paise from sales_returns where id = :rt2) = 30000,
            'The Accountant''s own return posts at once');
select t_ok(t_bal('70010150') = 10000, 'Spoilt returned goods: their cost (₹100) is charged as a stock loss');
select t_ok(t_books_agree(), 'Books agree after returns');

-- 8. Refunds (accounts team only), never more than the customer has on account
select t_err(format($$select rb_refund_customer(jsonb_build_object('customer_id', %s, 'refund_date', '2026-11-27', 'mode', 'bank',
  'amount_paise', 30000, 'reason', 'Return'))$$, :tr1), 'only has ₹250.00');
select rb_refund_customer(jsonb_build_object('customer_id', :tr1, 'refund_date', '2026-11-27', 'mode', 'bank', 'amount_paise', 25000,
  'reason', 'Two jars returned', 'return_id', :rt1)) as rf1 \gset
select rb_refund_customer(jsonb_build_object('customer_id', :walk, 'refund_date', '2026-11-27', 'mode', 'cash', 'amount_paise', 30000,
  'reason', 'Leaking jar')) as rf2 \gset
select t_ok((select refund_no from customer_refunds where id = :rf1) = 'TRN-RFD/2611/00001' and t_book(:tr1, null) = 0
        and t_book(:walk, null) = 0, 'Refunds bring both customers back to nothing owed');
select set_config('request.jwt.claim.sub', :'dir', false);
select t_err(format($$select rb_reverse_sales_return(%s, '2026-11-27', 'test')$$, :rt1), 'already been refunded');
select t_err(format($$select rb_cancel_sale(%s, '2026-11-27', 'test')$$, :'s4'::jsonb->>'id'), 'Goods have been returned');

-- 9. Cancelling an invoice; the journal guard; reversing receipts
select rb_cancel_sale((:'s3'::jsonb->>'id')::bigint, '2026-11-27', 'Entered for the wrong customer');
select t_ok((select status from sales where id = (:'s3'::jsonb->>'id')::bigint) = 'cancelled' and t_val(:fg) = 150000 and t_qty(:bp) = 2000,
            'A cancelled invoice puts its stock back at the cost it left at');
select t_ok((select invoice_no from sales where id = (:'s3'::jsonb->>'id')::bigint) = 'TRN-Inv/2611/00003', 'The cancelled invoice keeps its number');
select t_ok(t_bal('60010130') = 0 and t_books_agree(), 'Its revenue is reversed; books agree');
select set_config('request.jwt.claim.sub', :'mgr', false);
select rb_save_sale(jsonb_build_object('customer_id', :tr1, 'invoice_date', '2026-11-27', 'payment_mode', 'credit',
  'lines', jsonb_build_array(jsonb_build_object('item_id', :fg, 'pack_id', :jar, 'packs', 1)))) as s5 \gset
select set_config('request.jwt.claim.sub', :'ar', false);
select rb_receive_from_customer(jsonb_build_object('customer_id', :tr1, 'receipt_date', '2026-11-27', 'mode', 'cash', 'amount_paise', 25000,
  'allocations', jsonb_build_array(jsonb_build_object('sale_id', (:'s5'::jsonb->>'id')::bigint, 'amount_paise', 25000)))) as rc2 \gset
select set_config('request.jwt.claim.sub', :'dir', false);
select t_err(format($$select rb_cancel_sale(%s, '2026-11-27', 'test')$$, :'s5'::jsonb->>'id'), 'Receipts are set against');
select t_err(format($$select rb_reverse_journal(%s, '2026-11-27', 'test')$$, (select journal_id from sales where id = (:'s5'::jsonb->>'id')::bigint)),
  'comes from the Sales screens');
select rb_reverse_customer_receipt(:rc2, '2026-11-27', 'Cash not received after all');
select t_ok((select outstanding_paise from sales where id = (:'s5'::jsonb->>'id')::bigint) = 25000, 'Reversing the receipt opens the invoice again');
select rb_cancel_sale((:'s5'::jsonb->>'id')::bigint, '2026-11-27', 'Order cancelled');
select t_ok(t_book(:tr1, null) = 0 and t_books_agree(), 'Then the invoice can be cancelled; books agree');

-- 10. Learning phase delete, period lock
select set_config('request.jwt.claim.sub', :'acc', false);
select rb_save_sale(jsonb_build_object('customer_id', :walk, 'invoice_date', '2026-11-27', 'payment_mode', 'cash',
  'lines', jsonb_build_array(jsonb_build_object('item_id', :fg, 'pack_id', :jar, 'packs', 1)))) as s6 \gset
select set_config('request.jwt.claim.sub', :'dir', false);
select t_err(format('select rb_hard_delete_sale(%s)', :'s4'::jsonb->>'id'), 'learning phase');
select rb_hard_delete_sale((:'s6'::jsonb->>'id')::bigint);
select t_ok(not exists (select 1 from sales where id = (:'s6'::jsonb->>'id')::bigint) and t_books_agree(),
            'A Director fully deletes a learning-phase user''s invoice; books agree');
select rb_lock_period('2026-10-01', true, 'Closed');
select set_config('request.jwt.claim.sub', :'staff', false);
select t_err(format($$select rb_save_sale(jsonb_build_object('customer_id', %s, 'invoice_date', '2026-10-15',
  'lines', jsonb_build_array(jsonb_build_object('item_id', %s, 'pack_id', %s, 'packs', 1))))$$, :walk, :fg, :jar), 'locked');
select set_config('request.jwt.claim.sub', :'dir', false);
select rb_lock_period('2026-10-01', false, 'Test over');

-- 11. Statements, shared as a link
select set_config('request.jwt.claim.sub', :'ar', false);
select (rb_create_statement_link(:tr1, '2026-11-01'))->>'token' as tok \gset
select t_ok(length(:'tok') = 36, 'A long random link token');
select t_ok(jsonb_array_length(rb_customer_statement(:tr1, '2026-11-01', '2026-11-30')->'links') = 1, 'The statement lists its open link');
set role anon;
select set_config('request.jwt.claim.sub', '', false);
select set_config('request.jwt.claim.role', 'anon', false);
select t_ok((rb_public_statement(:'tok')->'customer'->>'name') = 'Test Trader Local'
        and jsonb_array_length(rb_public_statement(:'tok')->'lines') >= 6
        and (rb_public_statement(:'tok')->>'closing_paise')::bigint = 0, 'The link opens that customer''s statement without signing in');
select t_err($$select * from rb_sales_list(null, null)$$, 'permission denied');
select t_err($$select rb_public_statement('nonsense')$$, 'expired or been switched off');
reset role;
set role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', false);
select set_config('request.jwt.claim.sub', :'ar', false);
select t_ok(rb_revoke_statement_links(:tr1) = 1, 'Links can be switched off');
set role anon;
select t_err(format($$select rb_public_statement('%s')$$, :'tok'), 'expired or been switched off');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', :'dir', false);

-- 12. Balances, ledger and the sales summary agree with the books
select t_ok((select sum(balance_paise) from rb_customer_balances('2026-12-31')) =
            (select coalesce(sum(debit_paise - credit_paise), 0) from journal_lines where account_code = '10020105'),
            'Customer balances add up to the Trade Receivables account');
select t_ok((select balance_paise from rb_customer_balances('2026-12-31') where code = 'T-TR2') = 50400
        and (select not_due_paise from rb_customer_balances('2026-12-31') where code = 'T-TR2') = 50400
        and (select over_90_paise from rb_customer_balances('2027-04-15') where code = 'T-TR2') = 50400, 'Ageing by due date');
select t_ok((rb_customer_statement(:tr2, '2026-11-01', '2026-12-31')->>'closing_paise')::bigint = 50400
        and jsonb_array_length(rb_customer_statement(:tr2, '2026-11-01', '2026-12-31')->'open_invoices') = 1, 'Statement: closing balance and open invoices');
select t_ok((select sum(net_paise) from rb_sales_summary('2026-11-01', '2026-12-31') where not is_demo) = -t_bal('6001%') - t_bal('60060%'),
            'The sales summary (returns as minus) equals revenue in the books');
select t_ok((select sum(margin_paise) from rb_sales_summary('2026-11-01', '2026-12-31') where not is_demo) is not null, 'Directors see margins');
select t_ok((select count(*) from audit_log where action in ('SALE', 'CUSTOMER_RECEIPT', 'SALES_RETURN', 'POST_SALES_RETURN', 'CUSTOMER_REFUND', 'CANCEL_INVOICE')) >= 12,
            'Sales, receipts, returns, refunds and cancellations are in the audit log');

-- 12b. Bad debts: written off by a Director or the FC, recovered later
select set_config('request.jwt.claim.sub', :'acc', false);
select t_err(format($$select rb_write_off_bad_debt(jsonb_build_object('customer_id', %s, 'sale_id', %s, 'write_off_date', '2026-12-31',
  'amount_paise', 100, 'reason', 'x'))$$, :tr2, (select id from sales where customer_id = (select id from customers where code = 'T-TR2') and status = 'open')),
  'write off bad debts');
select set_config('request.jwt.claim.sub', :'dir', false);
select id as s_bd from sales where customer_id = :tr2 and status = 'open' \gset
select t_err(format($$select rb_write_off_bad_debt(jsonb_build_object('customer_id', %s, 'sale_id', %s, 'write_off_date', '2026-12-31',
  'amount_paise', 60000, 'reason', 'Gone'))$$, :tr2, :s_bd), 'only has');
select t_err(format($$select rb_write_off_bad_debt(jsonb_build_object('customer_id', %s, 'sale_id', %s, 'write_off_date', '2026-12-31',
  'amount_paise', 50400))$$, :tr2, :s_bd), 'reason');
select rb_write_off_bad_debt(jsonb_build_object('customer_id', :tr2, 'sale_id', :s_bd, 'write_off_date', '2026-12-31',
  'amount_paise', 50400, 'reason', 'Shop closed, owner not reachable')) as bd1 \gset
select t_ok((select write_off_no from customer_write_offs where id = :bd1) = 'TRN-BD/2612/00001', 'Write-off numbered TRN-BD/YYMM/00001 in training');
select t_ok((select outstanding_paise from sales where id = :s_bd) = 0 and (select written_off_paise from sales where id = :s_bd) = 50400
        and t_book(:tr2, null) = 0 and t_bal('80080110') = 50400 and t_books_agree(),
            'The invoice is closed, the customer owes nothing, Bad Debt Write-offs is charged; books agree');
select t_ok((select over_90_paise from rb_customer_balances('2027-04-15') where code = 'T-TR2') is null, 'A written-off invoice leaves the ageing');
select t_ok((rb_sale_detail(:s_bd)->'write_offs'->0->>'amount_paise')::bigint = 50400, 'The invoice shows its write-off');
select t_err(format($$select rb_cancel_sale(%s, '2026-12-31', 'x')$$, :s_bd), 'written off');
select t_err(format($$select rb_record_bad_debt_recovery(jsonb_build_object('write_off_id', %s, 'recovery_date', '2027-01-05', 'amount_paise', 20000))$$, :bd1),
  'First enter the money');
select set_config('request.jwt.claim.sub', :'ar', false);
select rb_receive_from_customer(jsonb_build_object('customer_id', :tr2, 'receipt_date', '2027-01-05', 'mode', 'bank', 'amount_paise', 20000,
  'reference', 'Owner paid part')) as rc_bd \gset
select t_ok((rb_customer_open_items(:tr2)->>'on_account_paise')::bigint = 20000
        and jsonb_array_length(rb_customer_open_items(:tr2)->'write_offs') = 1, 'The money waits on account; the write-off is listed to recover');
select set_config('request.jwt.claim.sub', :'dir', false);
select t_err(format($$select rb_record_bad_debt_recovery(jsonb_build_object('write_off_id', %s, 'recovery_date', '2027-01-05', 'amount_paise', 60000))$$, :bd1),
  'is still written off');
select rb_record_bad_debt_recovery(jsonb_build_object('write_off_id', :bd1, 'recovery_date', '2027-01-05', 'amount_paise', 20000,
  'note', 'Part paid by the owner')) as rv1 \gset
select t_ok((select recovery_no from bad_debt_recoveries where id = :rv1) = 'TRN-BDR/2701/00001'
        and t_bal('90010135') = -20000 and t_book(:tr2, null) = 0 and t_free(:tr2) = 0 and t_books_agree(),
            'Recovery booked as other income; the money on account is used; books agree');
select t_ok((select left_paise from rb_bad_debts_list() where id = :bd1) = 30400
        and (select recovered_paise from rb_bad_debts_list() where id = :bd1) = 20000, 'Bad debts list: ₹200 recovered, ₹304 still written off');
select t_err(format($$select rb_reverse_customer_receipt(%s, '2027-01-06', 'x')$$, :rc_bd), 'Reverse the recovery first');
select t_err(format($$select rb_reverse_bad_debt(%s, '2027-01-06', 'x')$$, :bd1), 'Reverse the recovery first');
select t_err(format($$select rb_write_off_bad_debt(jsonb_build_object('customer_id', %s, 'write_off_date', '2027-01-06', 'amount_paise', 100, 'reason', 'x'))$$, :tr2),
  'earlier balance');
select rb_reverse_bad_debt_recovery(:rv1, '2027-01-06', 'Entered against the wrong write-off');
select t_ok(t_bal('90010135') = 0 and t_free(:tr2) = 20000 and t_books_agree(), 'Reversing the recovery puts the money back on account');
select rb_reverse_bad_debt(:bd1, '2027-01-06', 'Customer has agreed to pay');
select t_ok((select outstanding_paise from sales where id = :s_bd) = 50400 and (select status from sales where id = :s_bd) = 'open'
        and t_bal('80080110') = 0 and t_books_agree(), 'Reversing the write-off opens the invoice again');
select t_ok((select count(*) from audit_log where action in ('BAD_DEBT_WRITE_OFF', 'BAD_DEBT_RECOVERED', 'REVERSE_BAD_DEBT', 'REVERSE_BAD_DEBT_RECOVERY')) >= 4,
            'Write-offs and recoveries are in the audit log');

-- 13. Remove demo data, then go live
select rb_remove_demo_data('REMOVE DEMO');
select t_ok(not exists (select 1 from sales where is_demo) and not exists (select 1 from customer_receipts where is_demo)
        and not exists (select 1 from sales_returns where is_demo) and not exists (select 1 from customer_refunds where is_demo)
        and not exists (select 1 from customer_write_offs where is_demo), 'DEMO sales, receipts, returns, refunds and bad debts removed');
select t_ok(t_books_agree(), 'Books still agree without the DEMO data');
select rb_go_live('2027-04-01', 'GO LIVE');
select t_ok(not exists (select 1 from sales) and not exists (select 1 from customer_receipts) and not exists (select 1 from stock_moves),
            'Go-live clears training invoices, receipts and stock');
select set_config('request.jwt.claim.sub', :'acc', false);
select rb_save_stock_count(jsonb_build_object('purpose', 'opening', 'count_date', '2027-04-01', 'lines', jsonb_build_array(
  jsonb_build_object('item_id', :fg, 'pack_id', :jar, 'packs', 10, 'rate_paise', 10000)))) as os2 \gset
select set_config('request.jwt.claim.sub', :'dir', false);
select rb_post_stock_count(:os2);
select set_config('request.jwt.claim.sub', :'staff', false);
select rb_save_sale(jsonb_build_object('customer_id', :walk, 'invoice_date', '2027-04-02',
  'lines', jsonb_build_array(jsonb_build_object('item_id', :fg, 'pack_id', :jar, 'packs', 1)))) as s9 \gset
select t_ok((:'s9'::jsonb->>'invoice_no') = 'Inv/2704/00001', 'After go-live, invoices start at Inv/YYMM/00001');

reset role;
\echo ALL MODULE 5 TESTS PASSED
