-- Behaviour tests for 10_shop.sql. Run against a throwaway database only,
-- after supabase_stub.sql and sql/01 to sql/10, from the tests/ folder.
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
grant execute on function public.t_err(text, text) to anon, authenticated, service_role;
create or replace function public.t_ok(p boolean, p_what text) returns void language plpgsql as $$
begin if not coalesce(p, false) then raise exception 'FAIL: %', p_what; end if; raise notice 'ok: %', p_what; end $$;
grant execute on function public.t_ok(boolean, text) to anon, authenticated, service_role;
create or replace function public.t_bal(p_code text) returns bigint language sql security definer as $$
  select coalesce(sum(l.debit_paise - l.credit_paise), 0)::bigint from journal_lines l join journals j on j.id = l.journal_id
  where l.account_code like p_code and j.status <> 'draft' and not l.is_demo $$;
create or replace function public.t_qty(p_item int, p_pack int default null) returns numeric language sql security definer as $$
  select coalesce(sum(qty_base), 0) from stock_moves where item_id = p_item and pack_id is not distinct from p_pack $$;
create or replace function public.t_books_agree() returns boolean language sql security definer as $$
  select (select sum(debit_paise) = sum(credit_paise) from journal_lines)
     and (select coalesce(sum(debit_paise - credit_paise), 0) from journal_lines where account_code like '100301%')
         = (select coalesce(sum(value_paise), 0) from stock_moves)
     and (select coalesce(sum(debit_paise - credit_paise), 0) from journal_lines where account_code = '10020105')
         = (select coalesce(sum(rb_sal_book_balance(id, null)), 0) from customers)
     and not exists (select 1 from customers c where rb_sal_free_credit(c.id) < 0)
     and not exists (select 1 from sales where outstanding_paise < 0) $$;
-- Read an order as the test (the tables are closed to the screens).
create or replace function public.t_o(p_token text) returns shop_orders language sql security definer set search_path = public as $$
  select * from shop_orders where token = p_token $$;
create or replace function public.t_free(p int) returns bigint language sql security definer as $$ select rb_shop_free(p) $$;
create or replace function public.t_held(p int) returns bigint language sql security definer as $$ select rb_shop_held(p) $$;
create or replace function public.t_cfree(p int) returns bigint language sql security definer as $$ select rb_sal_free_credit(p) $$;
grant execute on function public.t_bal(text), public.t_qty(int, int), public.t_books_agree(), public.t_o(text), public.t_free(int),
  public.t_held(int), public.t_cfree(int) to anon, authenticated, service_role;
set client_min_messages = notice;

-- 0. DEMO data
select t_ok((select available from screens where code = 'shop'), 'The Online shop orders screen is live');
select t_ok((select count(*) from shop_orders where is_demo) = 4, 'Four DEMO orders');
select t_ok((select string_agg(status, ',' order by id) from shop_orders where is_demo) = 'payment_check,paid,cod,cancelled',
            'DEMO orders: waiting for the UPI check, paid, cash on delivery, cancelled');
select t_ok((select order_no from shop_orders where is_demo order by id limit 1) ~ '^DEMO-ORD/[0-9]{4}/00001$', 'DEMO orders are numbered DEMO-ORD/YYMM/00001');
select t_ok((select count(*) from shop_alerts where is_demo) = 4, 'DEMO alerts: two payment checks, one paid, one cash on delivery');
select t_ok(not (select shop_open from app_settings), 'The shop stays closed until a Director or the FC opens it');
select t_ok((select count(*) from customer_receipts where note like 'Online order DEMO-ORD%') = 1, 'The paid DEMO order has its UPI receipt');

-- People
insert into auth.users(id, email) values ('00000000-0000-0000-0000-0000000000d1', 'info.ruchibuds@gmail.com');
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
select rb_login_ok() is not null;
select rb_invite_user('acc@example.com', 'Real Accountant', 'RA', null, (select id from user_categories where name='Accountant'), null);
select rb_invite_user('mgr@example.com', 'Real Manager', 'RM', null, (select id from user_categories where name='Manager'), null);
select rb_invite_user('staff@example.com', 'Real Staff', 'RS', null, (select id from user_categories where name='Staff'), null);
select rb_invite_user('sales@example.com', 'Real Sales', 'RSL', null, (select id from user_categories where name='Sales'), null);
reset role;
insert into auth.users(id, email) values
 ('00000000-0000-0000-0000-0000000000a1', 'acc@example.com'),
 ('00000000-0000-0000-0000-0000000000e1', 'mgr@example.com'),
 ('00000000-0000-0000-0000-0000000000c1', 'staff@example.com'),
 ('00000000-0000-0000-0000-0000000000b1', 'sales@example.com');
insert into items (code, name, kind, base_unit, buy_unit) values ('T-PK', 'Test jar', 'packaging', 'pc', 'pc');
insert into items (code, name, kind, base_unit, buy_unit, sells_by, loose_price_paise, hsn_code, gst_rate) values
  ('T-FG', 'Test mango pickle', 'finished', 'g', 'g', 'weight', 80000, '2001', 12);
insert into pack_types (code, name, kind, packaging_item_id) values ('T-PT', '250 g test jar', 'jar', (select id from items where code = 'T-PK'));
insert into product_packs (item_id, pack_type_id, net_qty, retail_price_paise, trader_price_paise, online_price_paise) values
  ((select id from items where code = 'T-FG'), (select id from pack_types where code = 'T-PT'), 250, 30000, 25000, 32000);
select (select id from items where code = 'T-FG') as fg, (select id from product_packs where item_id = (select id from items where code = 'T-FG')) as jar,
       (select id from customers where is_walk_in) as walk \gset
\set dir '00000000-0000-0000-0000-0000000000d1'
\set acc '00000000-0000-0000-0000-0000000000a1'
\set mgr '00000000-0000-0000-0000-0000000000e1'
\set staff '00000000-0000-0000-0000-0000000000c1'
\set sal '00000000-0000-0000-0000-0000000000b1'
set role authenticated;

-- 1. Opening stock: 40 jars
select set_config('request.jwt.claim.sub', :'acc', false);
select rb_save_stock_count(jsonb_build_object('purpose', 'opening', 'count_date', '2026-11-20', 'lines', jsonb_build_array(
  jsonb_build_object('item_id', :fg, 'pack_id', :jar, 'packs', 40, 'rate_paise', 10000)))) as os \gset
select set_config('request.jwt.claim.sub', :'dir', false);
select rb_post_stock_count(:os);

-- 2. Set-up: only a Director or the FC
select set_config('request.jwt.claim.sub', :'acc', false);
select t_err($$select rb_shop_save_settings('{"shop_open": true}')$$, 'right to change the online shop settings');
select t_err(format($$select rb_shop_save_product('{"pack_id": %s, "visible": true}')$$, :jar), 'right to choose the products');
select t_err($$select rb_shop_save_area('{"pin_code": "560001", "charge_paise": 5000}')$$, 'right to set delivery charges');
select set_config('request.jwt.claim.sub', :'dir', false);
select t_err($$select rb_shop_save_settings('{"shop_open": true, "shop_upi_id": "not a upi id"}')$$, 'does not look like a UPI ID');
select t_err($$select rb_shop_save_settings('{"shop_open": true, "shop_pay_cod": false, "shop_pay_upi": true}')$$, 'Choose a way to pay');
select rb_shop_save_settings(jsonb_build_object('shop_open', true, 'shop_upi_id', 'RuchiBuds@okaxis', 'shop_upi_name', 'Ruchi Buds',
  'shop_hold_minutes', 30, 'shop_pay_upi', true, 'shop_pay_cod', true, 'shop_pickup', true, 'shop_delivery', true,
  'shop_pickup_address', 'Kitchen, Kochi', 'shop_max_unpaid', 3,
  'shop_alert_categories', jsonb_build_array((select id from user_categories where name = 'Sales'), (select id from user_categories where name = 'Manager'))));
select t_ok((select shop_upi_id from app_settings) = 'ruchibuds@okaxis', 'Shop settings saved (the UPI ID in small letters)');
select t_err($$select rb_shop_save_area('{"pin_code": "56001", "charge_paise": 5000}')$$, '6-digit PIN code');
select rb_shop_save_area('{"pin_code": "560001", "area_name": "Bengaluru centre", "charge_paise": 5000}');
select t_err($$select rb_shop_save_area('{"pin_code": "560001", "charge_paise": 6000}')$$, 'already in the list');
select rb_shop_save_product(jsonb_build_object('pack_id', :jar, 'visible', true, 'cod_allowed', false, 'description', 'Raw mango, Kerala style',
  'photo', 'data:image/jpeg;base64,AAAA'));
select t_ok((rb_shop_products()->0) is not null, 'Products list for the staff screen');
-- Hide the DEMO areas so the "*" (every other PIN) DEMO charge does not apply in these tests
reset role;
update shop_delivery_areas set is_active = false where is_demo;
set role anon;
select set_config('request.jwt.claim.sub', '', false);
select set_config('request.jwt.claim.role', 'anon', false);

-- 3. The shop page, with no sign-in
select t_ok((select bool_or((p->>'pack_id')::int = :jar and (p->>'free')::int = 40 and (p->>'price_paise')::int = 32000
                            and p->>'photo' like 'data:image/%')
             from jsonb_array_elements(rb_shop_catalogue()->'products') p), 'Shop page: the jar at the online price ₹320, 40 free, with its photo');
select t_ok((rb_shop_catalogue()->>'pay_upi')::boolean and (rb_shop_catalogue()->>'pay_cod')::boolean, 'Shop page offers UPI and cash on delivery');
\set cart '''[{"pack_id": ' :jar ', "packs": 5}]'''
select t_err(format($$select rb_shop_place('{"name": "Asha", "phone": "12345", "fulfil": "pickup", "pay_method": "upi", "lines": %s}')$$, :cart), '10-digit mobile');
select t_err(format($$select rb_shop_place('{"name": "Asha", "phone": "9876500001", "fulfil": "delivery", "address": "1 MG Road", "pin_code": "110001", "pay_method": "upi", "lines": %s}')$$, :cart), 'do not deliver to PIN code 110001');
select t_err(format($$select rb_shop_place('{"name": "Asha", "phone": "9876500001", "fulfil": "delivery", "pin_code": "560001", "pay_method": "upi", "lines": %s}')$$, :cart), 'delivery address');
select t_err(format($$select rb_shop_place('{"name": "Asha", "phone": "9876500001", "fulfil": "pickup", "pay_method": "cod", "lines": %s}')$$, :cart), 'cannot be paid for on delivery');
select t_err(format($$select rb_shop_place('{"name": "Asha", "phone": "9876500001", "fulfil": "pickup", "pay_method": "upi", "lines": [{"pack_id": %s, "packs": 41}]}')$$, :jar), 'Only 40');
select t_err($$select rb_shop_orders(null, null)$$, 'permission denied');
select t_err($$select count(*) from shop_orders$$, 'permission denied');
select t_err($$select rb_shop_mark_paid(1, 'X', null)$$, 'permission denied');

-- 4. Order A: 5 jars by UPI, delivery to 560001 (₹50). Held at once.
select rb_shop_place(jsonb_build_object('name', 'Asha Rao', 'phone', '+91 98765 00001', 'fulfil', 'delivery', 'address', '1 MG Road',
  'pin_code', '560 001', 'pay_method', 'upi', 'lines', jsonb_build_array(jsonb_build_object('pack_id', :jar, 'packs', 5))))->>'token' as ta \gset
select t_ok((t_o(:'ta')).order_no ~ '^TRN-ORD/[0-9]{4}/[0-9]{5}$' and (t_o(:'ta')).status = 'placed' and (t_o(:'ta')).cust_phone = '9876500001',
            'Order placed: numbered (TRN- while training), phone kept as 10 digits');
select t_ok((t_o(:'ta')).total_paise = 165000 and (t_o(:'ta')).delivery_paise = 5000, 'Order total: 5 × ₹320 + ₹50 delivery = ₹1,650');
select t_ok(t_held(:jar) = 5 and t_free(:jar) = 35, 'The 5 jars are held at once: 35 free');
select t_ok((rb_shop_order(:'ta')->>'upi_id') = 'ruchibuds@okaxis', 'The order page shows the UPI ID to pay to');

-- Order C: 1 jar, then the customer cancels it; Order D: 2 jars, paid, then cancelled by the staff
select rb_shop_place(jsonb_build_object('name', 'Chitra', 'phone', '9876500003', 'fulfil', 'pickup', 'pay_method', 'upi',
  'lines', jsonb_build_array(jsonb_build_object('pack_id', :jar, 'packs', 1))))->>'token' as tc \gset
select t_ok(t_free(:jar) = 34, 'Order C holds 1 more');
select rb_shop_public_cancel(:'tc') is not null;
select t_ok((t_o(:'tc')).status = 'cancelled' and t_free(:jar) = 35, 'The customer cancels: the jar is free again');
select rb_shop_place(jsonb_build_object('name', 'Dev', 'phone', '9876500004', 'fulfil', 'pickup', 'pay_method', 'upi',
  'lines', jsonb_build_array(jsonb_build_object('pack_id', :jar, 'packs', 2))))->>'token' as td \gset
select t_err(format($$select rb_shop_submit_ref(%L, 'abc')$$, :'td'), 'UPI reference');
select (rb_shop_submit_ref(:'td', '6330 1111 2222')->>'status') = 'payment_check';
select t_ok((t_o(:'td')).upi_ref = '633011112222', 'The customer gives the UPI reference: waiting for the staff check');

-- 5. Counter sales cannot touch the held jars
set role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', false);
select set_config('request.jwt.claim.sub', :'staff', false);
select t_err(format($$select rb_save_sale('{"customer_id": %s, "invoice_date": "2026-11-27", "payment_mode": "cash", "lines": [{"item_id": %s, "pack_id": %s, "packs": 34}]}')$$,
  :walk, :fg, :jar), 'held for online orders, so only 33 can be sold');
select rb_save_sale(jsonb_build_object('customer_id', :walk, 'invoice_date', '2026-11-27', 'payment_mode', 'cash',
  'lines', jsonb_build_array(jsonb_build_object('item_id', :fg, 'pack_id', :jar, 'packs', 28))))->>'id' is not null;
select t_ok(t_qty(:fg, :jar) = 12 * 250 and t_free(:jar) = 5, 'The counter sells 28; 12 left, 7 held, 5 free');

-- 6. Staff check order D's payment, then cancel it: the money stays on account
select set_config('request.jwt.claim.sub', :'sal', false);
select rb_shop_mark_paid((t_o(:'td')).id, null, '2026-11-27');
select t_ok((t_o(:'td')).status = 'paid' and (t_o(:'td')).receipt_id is not null and (t_o(:'td')).customer_id is not null,
            'Sales staff tick Paid: a UPI receipt from a new customer found by phone');
select t_ok((select phone from customers where id = (t_o(:'td')).customer_id) = '9876500004', 'The new customer has the phone number');
reset role;
select t_ok((select count(*) from shop_alerts a where a.order_id = (t_o(:'td')).id and a.kind = 'paid') = 1, 'Paid: the staff are alerted');
set role authenticated;
select t_err(format($$select rb_shop_cancel(%s, '')$$, (t_o(:'td')).id), 'reason');
select rb_shop_cancel((t_o(:'td')).id, 'Customer changed their mind') like '%stays on the customer''s account%';
select t_ok((t_o(:'td')).status = 'cancelled' and t_free(:jar) = 7, 'Cancelled after paying: the 2 jars are free again');
reset role;
select t_ok(t_cfree((t_o(:'td')).customer_id) = 64000, 'The ₹640 paid stays on the customer''s account for a refund');
set role authenticated;

-- 7. Order B: 5 jars cash on delivery (once the jar allows it); then the jar is SOLD OUT
select set_config('request.jwt.claim.sub', :'dir', false);
select rb_shop_save_product(jsonb_build_object('pack_id', :jar, 'visible', true, 'cod_allowed', true, 'description', 'Raw mango, Kerala style'));
reset role;
select t_ok((select photo is not null from shop_products where pack_id = :jar), 'Saving without a photo keeps the photo');
set role authenticated;
set role anon;
select set_config('request.jwt.claim.role', 'anon', false);
select set_config('request.jwt.claim.sub', '', false);
select t_err(format($$select rb_shop_place('{"name": "Bala", "phone": "9876500002", "fulfil": "pickup", "pay_method": "cod", "lines": [{"pack_id": %s, "packs": 8}]}')$$, :jar), 'Only 7');
select rb_shop_place(jsonb_build_object('name', 'Bala', 'phone', '9876500002', 'fulfil', 'delivery', 'address', '5 Brigade Road',
  'pin_code', '560001', 'pay_method', 'cod', 'lines', jsonb_build_array(jsonb_build_object('pack_id', :jar, 'packs', 7))))->>'token' as tb \gset
select t_ok((t_o(:'tb')).status = 'cod' and (t_o(:'tb')).hold_until is null and (t_o(:'tb')).total_paise = 229000,
            'Cash on delivery: ready to pack at once, held with no time limit, ₹2,290');
select t_ok((select (p->>'free')::int from jsonb_array_elements(rb_shop_catalogue()->'products') p where (p->>'pack_id')::int = :jar) = 0,
            'The shop page now shows the jar with 0 free (SOLD OUT)');

-- 8. Order A runs out of time, then is paid late while the stock is free
reset role;
update shop_orders set hold_until = now() - interval '1 minute' where token = :'ta';
set role anon;
select t_ok(t_free(:jar) = 5, 'Past its time, order A lets go of its 5 jars');
select (rb_shop_submit_ref(:'ta', '633099998888')->>'status') = 'payment_check';
select t_ok((t_o(:'ta')).status = 'payment_check' and t_free(:jar) = 0, 'Paid a little late, while the jars were still free: held again');
select t_err(format($$select rb_shop_public_cancel(%L)$$, :'ta'), 'can no longer be cancelled here');

-- 9. Staff: reference not found, the customer tries again, then Paid
set role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', false);
select set_config('request.jwt.claim.sub', :'mgr', false);
select rb_shop_payment_not_found((t_o(:'ta')).id);
select t_ok((t_o(:'ta')).status = 'placed' and (t_o(:'ta')).upi_ref is null and (t_o(:'ta')).hold_until > now(), 'Not found: waiting for payment again, held for another 30 minutes');
select rb_shop_set_delivery((t_o(:'ta')).id, 3000);
select t_ok((t_o(:'ta')).total_paise = 163000, 'Staff change the delivery charge before payment: ₹1,630');
select rb_shop_mark_paid((t_o(:'ta')).id, '633099998888', '2026-11-27');
select t_err(format($$select rb_shop_set_delivery(%s, 0)$$, (t_o(:'ta')).id), 'before the order is paid');
select t_err(format($$select rb_shop_cash_received(%s, 'cash', null, null)$$, (t_o(:'ta')).id), 'not waiting for cash on delivery');
select t_ok((select to_check from (select (rb_shop_my_alerts()->>'to_check')::int to_check) x) = 1
        and (rb_shop_my_alerts()->>'to_pack')::int = 4 and (rb_shop_my_alerts()->>'alerted')::boolean,
            'Home screen for the Manager: 1 DEMO payment to check, 4 orders to pack, and alerts are on');

-- 10. Pack and dispatch order A: the invoice, the stock and the money
select rb_shop_pack((t_o(:'ta')).id);
select t_ok((t_o(:'ta')).status = 'packed', 'Packed');
select rb_shop_dispatch((t_o(:'ta')).id, '2026-11-27')->>'invoice_no' as inv_a \gset
select t_ok((t_o(:'ta')).status = 'delivered' and (t_o(:'ta')).sale_id is not null, 'Dispatched: invoice ' || :'inv_a');
reset role;
select t_ok((select channel = 'online' and total_paise = 163000 and delivery_paise = 3000 and outstanding_paise = 0 and status = 'paid'
                and bill_name = 'Asha Rao' and doc_type = 'invoice' and rate_ok
             from sales s cross join lateral (select bool_and(rate_paise = 32000) rate_ok from sale_lines where sale_id = s.id) r
             where id = (t_o(:'ta')).sale_id), 'The invoice: online, ₹1,630 with ₹30 delivery, paid by the UPI receipt');
select t_ok(t_qty(:fg, :jar) = 7 * 250, 'The 5 jars have left finished goods (7 left, all held for order B)');
select t_ok((select sum(credit_paise) from journal_lines l join sales s on s.journal_id = l.journal_id
             where s.id = (t_o(:'ta')).sale_id and l.account_code = '60060125') = 3000, 'Delivery charge credited to Delivery Charges Recovered');
select t_ok((select sum(credit_paise) from journal_lines l join sales s on s.journal_id = l.journal_id
             where s.id = (t_o(:'ta')).sale_id and l.account_code = '60010125') = 160000, 'Goods credited to Product Sales – Online');
select t_ok(t_books_agree(), 'Books balance; stock and customer ledgers agree with the books');
set role authenticated;
select t_err(format($$select rb_shop_cancel(%s, 'Too late')$$, (t_o(:'ta')).id), 'enter a sales return');

-- 11. Order B (cash on delivery): free delivery, dispatch, cash
select set_config('request.jwt.claim.sub', :'sal', false);
select rb_shop_set_delivery((t_o(:'tb')).id, 0);
select rb_shop_dispatch((t_o(:'tb')).id, '2026-11-27') is not null;
select t_ok((t_o(:'tb')).status = 'dispatched', 'Cash on delivery: dispatched, waiting for the cash');
reset role;
select t_ok((select outstanding_paise from sales where id = (t_o(:'tb')).sale_id) = 224000 and t_qty(:fg, :jar) = 0, 'Invoice of ₹2,240 owed; the stock is out');
select t_bal('10010110') as cash_before \gset
set role authenticated;
select rb_shop_cash_received((t_o(:'tb')).id, 'cash', '2026-11-27', null);
reset role;
select t_ok((t_o(:'tb')).status = 'delivered' and (select status from sales where id = (t_o(:'tb')).sale_id) = 'paid'
        and t_bal('10010110') = :cash_before + 224000, 'Cash received: invoice paid, ₹2,240 into cash');
select t_ok(t_books_agree(), 'Books still balance');
set role authenticated;

-- 12. The report
select set_config('request.jwt.claim.sub', :'mgr', false);
select rb_shop_report('2026-01-01', '2027-12-31') as rp \gset
select t_ok(((:'rp')::jsonb->'totals'->>'cancelled')::int >= 3 and ((:'rp')::jsonb->'totals'->>'cod_paise')::bigint >= 224000
        and jsonb_array_length((:'rp')::jsonb->'by_product') >= 1 and jsonb_array_length((:'rp')::jsonb->'by_day') >= 1,
            'Online orders report: totals, cancelled, COD, by day and by product');
select set_config('request.jwt.claim.sub', :'staff', false);
select t_err($$select rb_shop_report('2026-01-01', '2026-12-31')$$, 'right to see the online orders report');
select t_ok(rb_shop_my_alerts() is null, 'Staff (no shop tick) see no shop alerts');

-- 13. The Stock screen: held packs
select set_config('request.jwt.claim.sub', :'mgr', false);
select t_ok(exists (select 1 from rb_shop_holds()), 'Held packs for the Stock screen (the DEMO orders)');

-- 14. Emails for the Apps Script
reset role;
select set_config('request.jwt.claim.role', 'service_role', false);
set role service_role;
select rb_shop_pending_alerts() as pa \gset
select t_ok((:'pa')::jsonb->'to' ? 'sales@example.com' and (:'pa')::jsonb->'to' ? 'mgr@example.com'
        and not ((:'pa')::jsonb->'to' ? 'acc@example.com') and jsonb_array_length((:'pa')::jsonb->'alerts') >= 5,
            'Alerts to email go to the Sales and Manager staff only');
select rb_shop_alerts_emailed(array(select (a->>'id')::bigint from jsonb_array_elements((:'pa')::jsonb->'alerts') a));
select t_ok(jsonb_array_length(rb_shop_pending_alerts()->'alerts') = 0, 'Once emailed, not sent again');
reset role;
select set_config('request.jwt.claim.role', 'authenticated', false);
set role authenticated;
select t_err($$select rb_shop_pending_alerts()$$, 'permission denied');
reset role;

-- 15. Too many unpaid orders from one phone
update app_settings set shop_max_unpaid = 1;
insert into stock_moves (move_date, item_id, pack_id, qty_base, value_paise, kind, doc_no) values ('2026-11-27', :fg, :jar, 1000, 40000, 'opening', 'T-TOPUP');
set role anon;
select rb_shop_place(jsonb_build_object('name', 'Esha', 'phone', '9876500005', 'fulfil', 'pickup', 'pay_method', 'upi',
  'lines', jsonb_build_array(jsonb_build_object('pack_id', :jar, 'packs', 1)))) is not null;
select t_err(format($$select rb_shop_place('{"name": "Esha", "phone": "9876500005", "fulfil": "pickup", "pay_method": "upi", "lines": [{"pack_id": %s, "packs": 1}]}')$$, :jar), 'already has 1 orders waiting');
reset role;
update app_settings set shop_open = false;
set role anon;
select t_err(format($$select rb_shop_place('{"name": "Fay", "phone": "9876500006", "fulfil": "pickup", "pay_method": "upi", "lines": [{"pack_id": %s, "packs": 1}]}')$$, :jar), 'shop is closed');
select t_ok(jsonb_array_length(rb_shop_catalogue()->'products') = 0, 'A closed shop shows no products');
reset role;

-- 16. Running 10 again keeps the orders
\i ../sql/10_shop.sql
select t_ok((select count(*) from shop_orders) = 9, 'Re-running 10 keeps every order');

-- 17. Remove demo data takes the DEMO shop rows too
set role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', false);
select set_config('request.jwt.claim.sub', :'dir', false);
select rb_remove_demo_data('REMOVE DEMO') is not null;
reset role;
select t_ok(not exists (select 1 from shop_orders where is_demo) and not exists (select 1 from shop_products where is_demo)
        and not exists (select 1 from shop_delivery_areas where is_demo), 'Remove demo data removes the DEMO orders, products and areas');

select 'ALL MODULE 10 TESTS PASSED';
