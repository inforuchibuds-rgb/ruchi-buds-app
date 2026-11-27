-- Behaviour tests for 03_purchases.sql. Run against a throwaway database only,
-- after supabase_stub.sql, 01_core_users.sql, 02_masters.sql and 03_purchases.sql.
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
-- Book balance of an account (debit-positive), optionally for one supplier or item.
create or replace function public.t_bal(p_code text, p_sup int default null, p_item int default null) returns bigint language sql security definer as $$
  select coalesce(sum(l.debit_paise - l.credit_paise), 0)::bigint from journal_lines l join journals j on j.id = l.journal_id
  where l.account_code = p_code and j.status <> 'draft' and (p_sup is null or l.supplier_id = p_sup) and (p_item is null or l.item_id = p_item) $$;
create or replace function public.t_stock(p_item int default null) returns bigint language sql security definer as $$
  select coalesce(sum(value_paise), 0)::bigint from stock_moves where p_item is null or item_id = p_item $$;
create or replace function public.t_qty(p_item int) returns numeric language sql security definer as $$
  select coalesce(sum(qty_base), 0) from stock_moves where item_id = p_item $$;
create or replace function public.t_books_agree() returns boolean language sql security definer as $$
  select (select sum(debit_paise) = sum(credit_paise) from journal_lines)
     and t_stock() = t_bal('10030105') + t_bal('10030110')
     and (select coalesce(sum(outstanding_paise), 0) from purchases) = -t_bal('30010105')
         - coalesce((select sum(credit_paise - debit_paise) from journal_lines l join journals j on j.id = l.journal_id
                     where l.account_code = '30010105' and j.source = 'manual'), 0)
         + coalesce((select sum(s.amount_paise - coalesce((select sum(a.amount_paise) from payment_allocations a where a.payment_id = s.id), 0))
                     from supplier_payments s where s.status = 'posted'), 0) $$;
grant execute on function public.t_bal(text, int, int), public.t_stock(int), public.t_qty(int), public.t_books_agree() to authenticated;
set client_min_messages = notice;

-- 0. DEMO data
select t_ok((select count(*) from purchases where is_demo) >= 10, '10+ DEMO purchases');
select t_ok((select count(*) from purchases where is_demo and is_direct) = 4, 'Four DEMO direct purchases');
select t_ok((select count(*) from purchase_discrepancies where status = 'open') = 3, 'Three open DEMO differences');
select t_ok((select count(*) from supplier_payments where is_demo) = 5, 'Five DEMO supplier payments');
select t_ok((select po_no from purchases where is_demo order by id limit 1) = 'DEMO-PO/2611/00001', 'DEMO orders have their own DEMO-PO series');
select t_ok(t_bal('30010115') = 0, 'Goods received not invoiced is cleared once every DEMO bill is in');
select t_ok(t_books_agree(), 'Books balance; stock record = stock accounts; purchases owed = supplier control account');
select t_ok(t_bal('10010110') >= 0 and t_bal('10010205') >= 0, 'DEMO cash and bank never go below zero');
select t_ok((select status from purchases where is_demo and is_direct order by id desc limit 1) = 'awaiting_approval', 'One DEMO direct purchase waits for approval');
select t_ok((select count(*) from screens where code in ('purchases', 'suppliers') and available) = 2, 'Purchases and Suppliers screens are live');

-- People
insert into auth.users(id, email) values ('00000000-0000-0000-0000-0000000000d1', 'info.ruchibuds@gmail.com');
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
select rb_login_ok() is not null;
select rb_invite_user('acc@example.com', 'Real Accountant', 'RA', null, (select id from user_categories where name='Accountant'), '2027-01-31');
select rb_invite_user('ap@example.com', 'Real Payables', 'AP', null, (select id from user_categories where name='AP'), '2027-01-31');
select rb_invite_user('mgr@example.com', 'Real Manager', 'RM', null, (select id from user_categories where name='Manager'), null);
select rb_invite_user('staff@example.com', 'Real Staff', 'RS', null, (select id from user_categories where name='Staff'), null);
select rb_invite_user('dir2@example.com', 'Second Director', 'D2', null, (select id from user_categories where name='Director'), null);
reset role;
insert into auth.users(id, email) values
 ('00000000-0000-0000-0000-0000000000a1', 'acc@example.com'),
 ('00000000-0000-0000-0000-0000000000b1', 'ap@example.com'),
 ('00000000-0000-0000-0000-0000000000e1', 'mgr@example.com'),
 ('00000000-0000-0000-0000-0000000000c1', 'staff@example.com'),
 ('00000000-0000-0000-0000-0000000000d2', 'dir2@example.com');
-- Two test items and a supplier
insert into items (code, name, kind, base_unit, buy_unit, gst_rate) values
  ('T-RM1', 'Test prawns', 'raw', 'g', 'kg', 5), ('T-PK1', 'Test jar', 'packaging', 'pc', 'pc', 18), ('T-FG1', 'Test pickle', 'finished', 'g', 'g', 12);
insert into suppliers (code, name, kind, credit_days) values ('T-S1', 'Test Seafood Co', 'company', 15), ('T-S2', 'Test Fisherman', 'fisherman', 0);
set role authenticated;
\set sup '(select id from suppliers where code = ''T-S1'')'
\set fisher '(select id from suppliers where code = ''T-S2'')'
\set prawn '(select id from items where code = ''T-RM1'')'
\set jar '(select id from items where code = ''T-PK1'')'

-- 1. Staff cannot see or enter purchases
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
select t_ok((select count(*) from purchases) = 0 and (select count(*) from stock_moves) = 0, 'Staff cannot read purchases or stock moves');
select t_err($$select rb_save_purchase_order('{}')$$, 'right to enter purchase orders');
select t_err($$select rb_supplier_balances()$$, 'right to see supplier balances');
select t_err($$select rb_pur_refresh(1)$$, 'permission denied');
select t_err($$select rb_pur_pay('{}', null, false)$$, 'permission denied');
select t_err($$insert into purchases (supplier_id, department_id) values (1, 1)$$, 'permission denied');

-- 2. AP orders, receives and enters a bill that differs
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select t_err($$select rb_save_purchase_order(jsonb_build_object('supplier_id', (select id from suppliers where code='T-S1'), 'po_date', '2026-11-20',
  'lines', jsonb_build_array(jsonb_build_object('item_id', (select id from items where code='T-FG1'), 'qty', 1, 'rate_paise', 100))))$$, 'Only raw materials and packaging');
select t_err($$select rb_save_purchase_order(jsonb_build_object('supplier_id', (select id from suppliers where code='T-S1'), 'po_date', '2026-11-20',
  'lines', jsonb_build_array(jsonb_build_object('item_id', (select id from items where code='T-RM1'), 'unit_code', 'pc', 'qty', 1, 'rate_paise', 100))))$$, 'does not fit this item');
select rb_save_purchase_order(jsonb_build_object('supplier_id', :sup, 'po_date', '2026-11-20', 'lines', jsonb_build_array(
  jsonb_build_object('item_id', :prawn, 'unit_code', 'kg', 'qty', 10, 'rate_paise', 60000, 'gst_rate', 5),
  jsonb_build_object('item_id', :jar, 'unit_code', 'pc', 'qty', 100, 'rate_paise', 2000, 'gst_rate', 18)))) as po1 \gset
select t_ok((select po_no from purchases where id = :po1) = 'TRN-PO/2611/00001', 'Training-mode orders are numbered TRN-PO/YYMM/00001');
select t_ok((select order_total_paise from purchases where id = :po1) = 800000, 'Order total ₹8,000');
select t_err(format($$select rb_enter_supplier_bill(jsonb_build_object('purchase_id', %s, 'bill_no', 'X', 'bill_date', '2026-11-21'))$$, :po1), 'Receive the goods');
select t_err(format($$select rb_receive_goods(jsonb_build_object('purchase_id', %s, 'grn_date', '2026-11-19', 'lines', '[]'::jsonb))$$, :po1), 'before the order date');
-- 9.5 kg prawns came; 5 of 100 jars cracked
select rb_receive_goods(jsonb_build_object('purchase_id', :po1, 'grn_date', '2026-11-21', 'lines', jsonb_build_array(
  jsonb_build_object('line_id', (select id from purchase_lines where purchase_id = :po1 and line_no = 1), 'received_qty', 9.5),
  jsonb_build_object('line_id', (select id from purchase_lines where purchase_id = :po1 and line_no = 2), 'received_qty', 100, 'rejected_qty', 5, 'reject_reason', 'Cracked')))) as grn1 \gset
select t_ok((select grn_no from purchase_grns where id = :grn1) = 'TRN-GRN/2611/00001', 'GRN numbered TRN-GRN/YYMM/00001');
select t_ok(t_qty(:prawn) = 9500 and t_stock(:prawn) = 570000, 'Stock added at GRN: 9,500 g prawns at ₹5,700');
select t_ok(t_qty(:jar) = 95 and t_stock(:jar) = 190000, 'Only the 95 good jars go into stock');
select t_ok(t_bal('30010115') = -760000, 'GRN posts against goods received not invoiced');
select t_ok((select status from purchases where id = :po1) = 'part_received', 'Order is part received');
select t_ok((select count(*) from purchase_discrepancies where purchase_id = :po1 and status = 'open') = 2, 'Short prawns and cracked jars flagged');
select t_err(format($$select rb_save_purchase_order(jsonb_build_object('id', %s, 'supplier_id', (select id from suppliers where code='T-S1'), 'po_date', '2026-11-20',
  'lines', jsonb_build_array(jsonb_build_object('item_id', (select id from items where code='T-RM1'), 'qty', 1, 'rate_paise', 1))))$$, :po1), 'can no longer be changed');
-- The bill: prawns 10 kg at ₹620 (more than received, above the PO rate), jars 100 at ₹20, GST on jars at 18%, prawns GST ₹350 (5% of ₹6,200 is ₹310)
select t_err(format($$select rb_enter_supplier_bill(jsonb_build_object('purchase_id', %s, 'bill_no', 'TS-9', 'bill_date', '2026-11-22', 'payment_mode', 'cash',
  'lines', jsonb_build_array(
    jsonb_build_object('line_id', (select id from purchase_lines where purchase_id = %s and line_no = 1), 'qty', 10, 'rate_paise', 62000, 'gst_paise', 35000),
    jsonb_build_object('line_id', (select id from purchase_lines where purchase_id = %s and line_no = 2), 'qty', 100, 'rate_paise', 2000, 'gst_paise', 36000))))$$, :po1, :po1, :po1),
  'Save it as Credit');
select t_ok((select bill_posted_at is null from purchases where id = :po1), 'A cash bill with differences is not saved at all');
select rb_enter_supplier_bill(jsonb_build_object('purchase_id', :po1, 'bill_no', 'TS-9', 'bill_date', '2026-11-22', 'payment_mode', 'credit',
  'lines', jsonb_build_array(
    jsonb_build_object('line_id', (select id from purchase_lines where purchase_id = :po1 and line_no = 1), 'qty', 10, 'rate_paise', 62000, 'gst_paise', 35000),
    jsonb_build_object('line_id', (select id from purchase_lines where purchase_id = :po1 and line_no = 2), 'qty', 100, 'rate_paise', 2000, 'gst_paise', 36000))));
select t_ok((select bill_total_paise from purchases where id = :po1) = 891000, 'Bill total ₹8,910 (₹8,200 + GST ₹710)');
select t_ok(t_bal('30010105', :sup) = -891000, 'Supplier balance raised from the bill');
select t_ok(t_bal('30010115') = 0, 'Bill clears goods received not invoiced');
select t_ok(t_stock(:prawn) = 655000 and t_bal('10030105', null, :prawn) = 655000, 'Not GST registered: stock carries the bill cost incl. GST (₹6,200 + ₹350)');
select t_ok((select string_agg(stage || ':' || kind, ',' order by stage, kind) from purchase_discrepancies where purchase_id = :po1 and status = 'open')
            = 'bill:rate,bill:short,bill:short,bill:tax,receipt:damaged,receipt:short', 'Every difference flagged: short, damaged, billed > received (prawns and jars), rate, tax');
select t_ok((select amount_paise from purchase_discrepancies where purchase_id = :po1 and kind = 'rate') = 20000
        and (select amount_paise from purchase_discrepancies where purchase_id = :po1 and kind = 'tax') = 4000, 'Rate (₹200) and tax (₹40) differences valued');
select t_err(format($$select rb_enter_supplier_bill(jsonb_build_object('purchase_id', %s, 'bill_no', 'TS-9', 'bill_date', '2026-11-22', 'lines', '[]'::jsonb))$$, :po1), 'already entered');
-- AP can flag but not settle money differences, and cannot pay until settled
select t_err(format($$select rb_settle_discrepancy((select id from purchase_discrepancies where purchase_id = %s and kind = 'rate'), 'accept', 'ok')$$, :po1), 'settled only by the Accountant');
select t_err(format($$select rb_pay_supplier(jsonb_build_object('supplier_id', (select id from suppliers where code='T-S1'), 'pay_date', '2026-11-23', 'mode', 'bank', 'amount_paise', 100,
  'allocations', jsonb_build_array(jsonb_build_object('purchase_id', %s, 'amount_paise', 100))))$$, :po1), 'cannot be paid');

-- 3. Manager settles delivery differences; not money ones
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e1', false);
select t_err(format($$select rb_settle_discrepancy((select id from purchase_discrepancies where purchase_id = %s and kind = 'tax'), 'accept', 'ok')$$, :po1), 'settled only by the Accountant');
select t_err(format($$select rb_settle_discrepancy((select id from purchase_discrepancies where purchase_id = %s and stage='receipt' and kind = 'short'), 'return', 'x')$$, :po1), 'you can choose: accept, await_delivery');
select t_err(format($$select rb_settle_discrepancy((select id from purchase_discrepancies where purchase_id = %s and stage='receipt' and kind = 'short'), 'accept', '')$$, :po1), 'reason');
select rb_settle_discrepancy((select id from purchase_discrepancies where purchase_id = :po1 and stage = 'receipt' and kind = 'short'), 'accept', 'Normal weighing loss on ice');
select rb_settle_discrepancy((select id from purchase_discrepancies where purchase_id = :po1 and kind = 'damaged'), 'return', 'Cracked jars sent back with the driver', '2026-11-22');
select t_ok((select count(*) from purchase_returns where purchase_id = :po1 and not from_stock) = 1 and t_qty(:jar) = 95, 'Returning refused jars records the return; stock unchanged (they never came in)');

-- 4. Accountant settles the money differences
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select rb_settle_discrepancy((select id from purchase_discrepancies where purchase_id = :po1 and kind = 'rate'), 'correct_rate', 'PO rate ₹600 agreed', '2026-11-23');
select t_ok((select total_paise from purchase_notes where purchase_id = :po1 order by id desc limit 1) = 21129
        and (select note_no from purchase_notes where purchase_id = :po1 order by id desc limit 1) = 'TRN-DN/2611/00001', 'Rate corrected by debit note TRN-DN: ₹200 + GST share ₹11.29');
select rb_settle_discrepancy((select d.id from purchase_discrepancies d join purchase_lines l on l.id = d.purchase_line_id
  where d.purchase_id = :po1 and d.stage = 'bill' and d.kind = 'short' and l.line_no = 1), 'debit_note', 'Only 9.5 kg came', '2026-11-23');
select rb_settle_discrepancy((select id from purchase_discrepancies where purchase_id = :po1 and kind = 'tax'), 'debit_note', 'GST must be 5%', '2026-11-23');
select t_ok((select open_discrepancies from purchases where id = :po1) = 1, 'The jars billed but sent back are still open');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select rb_settle_discrepancy((select d.id from purchase_discrepancies d join purchase_lines l on l.id = d.purchase_line_id
  where d.purchase_id = :po1 and d.stage = 'bill' and d.kind = 'short' and l.line_no = 2), 'debit_note', '5 cracked jars returned', '2026-11-23');
select t_ok((select total_paise from purchase_notes where purchase_id = :po1 order by id desc limit 1) = 11800, 'Debit note for 5 jars: ₹100 + GST ₹18');
select t_ok((select count(*) from purchase_notes where purchase_id = :po1) = 4, 'Four debit notes');
select t_ok((select open_discrepancies from purchases where id = :po1) = 0, 'No open differences left');
select t_err(format($$select rb_settle_discrepancy((select id from purchase_discrepancies where purchase_id = %s and kind = 'tax'), 'accept', 'again')$$, :po1), 'already settled');
-- Prawns now carry ₹600 x 9.5 kg plus 5% GST: 5,700 + 285 = ₹5,985
select t_ok(t_stock(:prawn) = 598500, 'After the debit notes prawn stock cost is 9.5 kg at the PO rate plus GST (₹5,985)');
select t_ok((select outstanding_paise from purchases where id = :po1) = 598500 + 224200, 'Owed to the supplier: prawns ₹5,985 + 95 jars ₹2,242');
select t_ok(t_books_agree(), 'Books agree after the debit notes');

-- 5. AP pays the supplier; part on account
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select t_err(format($$select rb_pay_supplier(jsonb_build_object('supplier_id', (select id from suppliers where code='T-S1'), 'pay_date', '2026-11-24', 'mode', 'bank', 'amount_paise', 900000,
  'allocations', jsonb_build_array(jsonb_build_object('purchase_id', %s, 'amount_paise', 900000))))$$, :po1), 'only has ₹8,227.00 left');
select rb_pay_supplier(jsonb_build_object('supplier_id', :sup, 'pay_date', '2026-11-24', 'mode', 'upi', 'amount_paise', 900000, 'reference', 'UPI 77',
  'allocations', jsonb_build_array(jsonb_build_object('purchase_id', :po1, 'amount_paise', 822700)))) as pay1 \gset
select t_ok((select payment_no from supplier_payments where id = :pay1) = 'TRN-PAY/2611/00001', 'Payment numbered TRN-PAY/YYMM/00001');
select t_ok((select status from purchases where id = :po1) = 'paid', 'Purchase shows Paid');
select t_ok(t_bal('30010105', :sup) = 77300, 'Paying ₹773 more than owed leaves a debit (advance) on the supplier');
select t_ok((select balance_paise from rb_supplier_balances('2026-11-30') where code = 'T-S1') = -77300, 'Supplier balances list shows the advance');
select t_ok((select balance_paise from rb_supplier_ledger(:sup, '2026-11-01', '2026-11-30') order by line_date desc, journal_no desc nulls last limit 1) = -77300,
            'Supplier ledger ends on the same balance');
select t_ok((select count(*) from rb_supplier_ledger(:sup, '2026-11-01', '2026-11-30') where journal_no is not null) = 6, 'Ledger shows bill, four debit notes and the payment');
reset role;
select t_ok((select credit_paise from journal_lines where journal_id = (select journal_id from supplier_payments where id = :pay1) and account_code = '10010205') = 900000,
            'UPI payment is paid from the bank account');
set role authenticated;

-- 6. Direct purchases: fish with no bill
select t_err($$select rb_save_direct_purchase(jsonb_build_object('supplier_id', (select id from suppliers where code='T-S2'), 'purchase_date', '2026-11-25',
  'payment_mode', 'cash', 'no_supplier_bill', true, 'lines', jsonb_build_array(jsonb_build_object('item_id', (select id from items where code='T-RM1'), 'qty', 5, 'rate_paise', 40000))))$$, 'reason');
select t_err($$select rb_save_direct_purchase(jsonb_build_object('supplier_id', (select id from suppliers where code='T-S2'), 'purchase_date', '2026-11-25', 'reason', 'Daily catch',
  'payment_mode', 'cash', 'no_supplier_bill', true, 'lines', jsonb_build_array(jsonb_build_object('item_id', (select id from items where code='T-RM1'), 'qty', 5, 'rate_paise', 40000))))$$, 'photo');
select t_err($$select rb_save_direct_purchase(jsonb_build_object('supplier_id', (select id from suppliers where code='T-S2'), 'purchase_date', '2026-11-25', 'reason', 'Daily catch',
  'payment_mode', 'cash', 'lines', jsonb_build_array(jsonb_build_object('item_id', (select id from items where code='T-RM1'), 'qty', 5, 'rate_paise', 40000))))$$, 'bill number');
select rb_save_direct_purchase(jsonb_build_object('supplier_id', :fisher, 'purchase_date', '2026-11-25', 'reason', 'Daily catch',
  'payment_mode', 'cash', 'no_supplier_bill', true, 'photo', 'data:image/jpeg;base64,/9j/4AAQSkZJRg==',
  'lines', jsonb_build_array(jsonb_build_object('item_id', :prawn, 'unit_code', 'kg', 'qty', 5, 'rate_paise', 40000)))) as dp1 \gset
select t_ok((select status from purchases where id = :dp1) = 'paid' and (select bill_no from purchases where id = :dp1) like 'TRN-GRN/2611/%',
            'With no bill, the GRN number is the reference; paid in cash at once');
select t_ok((select count(*) from purchase_photos) = 0, 'Photos are not readable as a table (only one at a time)');
select t_ok(jsonb_array_length(rb_purchase_detail(:dp1)->'photos') = 1, 'Photo kept with the purchase');
select t_ok(rb_purchase_photo((rb_purchase_detail(:dp1)->'photos'->0->>'id')::bigint) like 'data:image/jpeg%', 'Photo opens from the purchase window');
select t_ok(t_bal('30010105', :fisher) = 0 and t_bal('10030105', null, :prawn) = 598500 + 200000, 'Supplier ledger nets to zero; stock up ₹2,000');
select t_ok((select purchases from rb_direct_purchase_report('2026-11-01', '2026-11-30') where supplier_name = 'Test Fisherman') = 1, 'Direct purchase report counts it');

-- 7. Approval above the Settings limit
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select rb_save_settings('{"direct_purchase_approval_limit_paise": 300000}');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select rb_save_direct_purchase(jsonb_build_object('supplier_id', :sup, 'purchase_date', '2026-11-25', 'reason', 'Urgent',
  'payment_mode', 'credit', 'bill_no', 'TS-12', 'lines', jsonb_build_array(jsonb_build_object('item_id', :jar, 'qty', 200, 'rate_paise', 2000, 'gst_paise', 72000)))) as dp2 \gset
select t_ok((select status from purchases where id = :dp2) = 'awaiting_approval' and t_qty(:jar) = 95, 'Above the limit: waits, nothing posted');
select t_err(format('select rb_approve_direct_purchase(%s)', :dp2), 'right to approve direct purchases');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e1', false);
select t_err(format('select rb_approve_direct_purchase(%s)', :dp2), 'right to approve direct purchases');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select rb_approve_direct_purchase(:dp2);
select t_ok((select status from purchases where id = :dp2) = 'billed' and t_qty(:jar) = 295, 'Accountant approves: posted, 200 jars in stock');
select t_err(format('select rb_approve_direct_purchase(%s)', :dp2), 'not waiting');
-- A Director's own big direct purchase posts straight away (spec section 4 exemption)
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select rb_save_direct_purchase(jsonb_build_object('supplier_id', :sup, 'purchase_date', '2026-11-25', 'reason', 'Urgent',
  'payment_mode', 'bank', 'bill_no', 'TS-13', 'lines', jsonb_build_array(jsonb_build_object('item_id', :prawn, 'unit_code', 'kg', 'qty', 10, 'rate_paise', 60000)))) as dp3 \gset
select t_ok((select status from purchases where id = :dp3) = 'paid', 'Director''s own direct purchase above the limit posts at once');
-- Refusing
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select rb_save_direct_purchase(jsonb_build_object('supplier_id', :sup, 'purchase_date', '2026-11-25', 'reason', 'Urgent',
  'payment_mode', 'credit', 'bill_no', 'TS-15', 'lines', jsonb_build_array(jsonb_build_object('item_id', :jar, 'qty', 500, 'rate_paise', 2000)))) as dp4 \gset
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d2', false);
select rb_refuse_direct_purchase(:dp4, 'Too many jars');
select t_ok((select status from purchases where id = :dp4) = 'refused', 'Second Director refuses one');

-- 8. GST registered: input GST becomes recoverable
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select rb_save_settings('{"gstin": "27AAAAA0000A1Z5", "direct_purchase_approval_limit_paise": 300000}');
reset role; select t_ok(not rb_pur_gst_claimable('2026-11-25'), 'A GSTIN with no start date claims nothing yet'); set role authenticated;
select rb_set_gst_registration('27AAAAA0000A1Z5', '2026-11-01');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select t_bal('10050105') as gst_before \gset
select rb_save_purchase_order(jsonb_build_object('supplier_id', :sup, 'po_date', '2026-11-25', 'lines', jsonb_build_array(
  jsonb_build_object('item_id', :jar, 'qty', 50, 'rate_paise', 2000, 'gst_rate', 18)))) as po2 \gset
select rb_receive_goods(jsonb_build_object('purchase_id', :po2, 'grn_date', '2026-11-25', 'lines', jsonb_build_array(
  jsonb_build_object('line_id', (select id from purchase_lines where purchase_id = :po2), 'received_qty', 50))));
select rb_enter_supplier_bill(jsonb_build_object('purchase_id', :po2, 'bill_no', 'TS-20', 'bill_date', '2026-11-25', 'payment_mode', 'cash',
  'lines', jsonb_build_array(jsonb_build_object('line_id', (select id from purchase_lines where purchase_id = :po2), 'qty', 50, 'rate_paise', 2000, 'gst_paise', 18000))));
select t_ok(t_bal('10050105') - :gst_before = 18000, 'Registered: ₹180 GST goes to Input GST recoverable');
select t_ok((select status from purchases where id = :po2) = 'paid', 'A matched bill can be paid in cash straight away');
select t_err(format($$select rb_enter_supplier_bill(jsonb_build_object('purchase_id', %s, 'bill_no', 'ts-20', 'bill_date', '2026-11-25', 'lines', '[]'::jsonb))$$, :po2), 'already entered');

-- 9. Returns after the bill
select t_err(format($$select rb_return_to_supplier(jsonb_build_object('purchase_id', %s, 'return_date', '2026-11-26', 'reason', 'x',
  'lines', jsonb_build_array(jsonb_build_object('line_id', (select id from purchase_lines where purchase_id = %s), 'qty', 51))))$$, :po2, :po2), 'only 50');
select rb_return_to_supplier(jsonb_build_object('purchase_id', :po2, 'return_date', '2026-11-26', 'reason', 'Wrong lid size',
  'lines', jsonb_build_array(jsonb_build_object('line_id', (select id from purchase_lines where purchase_id = :po2), 'qty', 10)))) as ret1 \gset
select t_ok((select total_paise from purchase_returns where id = :ret1) = 23600 and (select return_no from purchase_returns where id = :ret1) like 'TRN-PRN/2611/%',
            'Return of 10 jars: ₹200 + GST ₹36 (TRN-PRN)');
select t_ok(t_bal('10050105') - :gst_before = 18000 - 3600, 'Input GST given back on the return');
select t_ok(t_books_agree(), 'Books agree after returns');

-- 10. Reversal and the Accounts screen guard
select t_err(format($$select rb_reverse_purchase(%s, '2026-11-26', 'x')$$, :dp2), 'right to reverse');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select t_err(format($$select rb_reverse_journal((select bill_journal_id from purchases where id = %s), '2026-11-26', 'x')$$, :dp2), 'Reverse it there');
select t_err(format($$select rb_reverse_purchase(%s, '2026-11-26', 'x')$$, :po1), 'Reverse those payments first');
select t_qty(:jar) as jars_before \gset
select rb_reverse_purchase(:dp2, '2026-11-26', 'Entered on the wrong supplier');
select t_ok((select status from purchases where id = :dp2) = 'cancelled' and t_qty(:jar) = :jars_before - 200, 'Reversed purchase takes its 200 jars back out of stock');
select t_ok((select status from journals where id = (select bill_journal_id from purchases where id = :dp2)) = 'reversed', 'Its journal is reversed');
select t_ok(t_books_agree(), 'Books agree after the reversal');
-- Reverse a payment: the purchase is owed again
select rb_reverse_supplier_payment(:pay1, '2026-11-26', 'Bounced');
select t_ok((select status from purchases where id = :po1) = 'billed' and (select outstanding_paise from purchases where id = :po1) = 822700, 'Reversed payment: purchase owed again');

-- 11. Learning-phase delete (the Accountant and AP are in their learning phase)
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select t_err(format('select rb_hard_delete_purchase(%s)', :po2), 'right to fully delete');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select t_err(format('select rb_hard_delete_purchase(%s)', :dp3), 'learning phase');
select t_err(format('select rb_hard_delete_purchase(%s)', :po2), 'Payments are set against');
select rb_hard_delete_supplier_payment((select payment_id from payment_allocations where purchase_id = :po2));
select rb_hard_delete_purchase(:po2);
select t_ok(not exists (select 1 from purchases where id = :po2) and not exists (select 1 from stock_moves where purchase_id = :po2), 'Director fully deletes a learning-phase user''s purchase');
select t_ok(not exists (select 1 from audit_log where action ilike '%DELETE%' and record_id = :po2::text), 'Not in the audit log (spec section 4)');
select t_ok(t_books_agree(), 'Books agree after the delete');

-- 12. Locked month
select rb_lock_period('2026-10-01', true, 'October closed');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select t_err($$select rb_save_direct_purchase(jsonb_build_object('supplier_id', (select id from suppliers where code='T-S2'), 'purchase_date', '2026-10-20', 'reason', 'Late entry',
  'payment_mode', 'cash', 'no_supplier_bill', true, 'note', 'slip', 'lines', jsonb_build_array(jsonb_build_object('item_id', (select id from items where code='T-RM1'), 'qty', 1, 'rate_paise', 100))))$$,
  'is locked');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select rb_lock_period('2026-10-01', false, 'Reopened for the test');

-- 12b. GST registration moves to a later date: GST goes to cost before it, to input credit from it
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select t_err($$select rb_set_gst_registration('27ABCDE1234F1Z5', '2026-11-26')$$, 'change settings');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select t_err($$select rb_set_gst_registration('27ABCDE1234F1Z5', null)$$, 'date the GST registration starts');
select t_err($$select rb_set_gst_registration('27ABC', '2026-11-26')$$, '15 letters');
select rb_set_gst_registration('27abcde1234f1z5', '2026-11-26');
select t_bal('10050105') as itc0 \gset
select rb_save_direct_purchase(jsonb_build_object('supplier_id', :sup, 'purchase_date', '2026-11-25', 'reason', 'Before GST',
  'payment_mode', 'credit', 'bill_no', 'TS-G1', 'lines', jsonb_build_array(jsonb_build_object('item_id', :jar, 'qty', 10, 'rate_paise', 2000, 'gst_paise', 3600)))) as g1 \gset
select t_ok((select gstin from app_settings) = '27ABCDE1234F1Z5' and (select gst_registered_from from app_settings) = '2026-11-26', 'GSTIN and its start date saved');
select rb_save_direct_purchase(jsonb_build_object('supplier_id', :sup, 'purchase_date', '2026-11-25', 'reason', 'Bill before the date',
  'payment_mode', 'credit', 'bill_no', 'TS-G2', 'lines', jsonb_build_array(jsonb_build_object('item_id', :jar, 'qty', 10, 'rate_paise', 2000, 'gst_paise', 3600)))) as g2 \gset
select rb_save_direct_purchase(jsonb_build_object('supplier_id', :sup, 'purchase_date', '2026-11-26', 'reason', 'Bill from the date',
  'payment_mode', 'credit', 'bill_no', 'TS-G3', 'lines', jsonb_build_array(jsonb_build_object('item_id', :jar, 'qty', 10, 'rate_paise', 2000, 'gst_paise', 3600)))) as g3 \gset
select t_ok(not (select gst_claimed from purchases where id = :g1) and not (select gst_claimed from purchases where id = :g2),
            'Bills dated before the registration date add GST to stock cost');
select t_ok((select gst_claimed from purchases where id = :g3) and t_bal('10050105') = :itc0 + 3600, 'A bill dated from the registration date claims the GST');
select t_ok((select sum(value_paise) from stock_moves where purchase_id = :g2) = 23600 and (select sum(value_paise) from stock_moves where purchase_id = :g3) = 20000,
            'Stock carries GST only when it cannot be claimed (AS 2)');
select rb_return_to_supplier(jsonb_build_object('purchase_id', :g1, 'return_date', '2026-11-26', 'reason', 'Cracked',
  'lines', jsonb_build_array(jsonb_build_object('line_id', (select id from purchase_lines where purchase_id = :g1), 'qty', 5))));
select rb_return_to_supplier(jsonb_build_object('purchase_id', :g3, 'return_date', '2026-11-26', 'reason', 'Cracked',
  'lines', jsonb_build_array(jsonb_build_object('line_id', (select id from purchase_lines where purchase_id = :g3), 'qty', 5))));
select t_ok(t_bal('10050105') = :itc0 + 1800 and (select sum(value_paise) from stock_moves where purchase_id = :g1) = 11800,
            'Returns undo GST the way the bill booked it, whatever the registration is now');
select t_ok(t_books_agree(), 'Books agree across the GST registration date');
select rb_set_gst_registration('', null);
select t_ok((select gstin from app_settings) is null and (select gst_registered_from from app_settings) is null, 'Clearing the GSTIN clears its date');

-- 13. Reports and the purchase window
select t_ok((select count(*) from rb_open_discrepancies()) = 3, 'Open differences list (DEMO ones still open)');
select t_ok((select sum(short_count) from rb_supplier_discrepancy_report('2026-11-01', '2026-11-30') where supplier_name = 'Test Seafood Co') = 3
        and (select sum(overcharge_count) from rb_supplier_discrepancy_report('2026-11-01', '2026-11-30') where supplier_name = 'Test Seafood Co') = 2,
            'Supplier discrepancy report counts short supply and overcharges');
select t_ok((rb_purchase_detail(:po1)->'can'->>'reverse')::boolean = true and jsonb_array_length(rb_purchase_detail(:po1)->'discrepancies') = 6,
            'Purchase window data has its differences and the right buttons');
select t_ok((select count(*) from rb_stock_on_hand() where code = 'T-RM1') = 1, 'Stock on hand lists purchased items');
select t_ok((select count(*) from audit_log where action in ('SAVE_ORDER', 'RECEIVE_GOODS', 'SUPPLIER_BILL', 'SETTLE_DIFFERENCE', 'SUPPLIER_PAYMENT', 'DIRECT_PURCHASE')) >= 10,
            'Purchase steps are in the audit log');

-- 14. Remove demo data, then go live
-- Reverse and correct (module 2, version 1.1) is only for manual journals
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select t_err(format($$select rb_reverse_and_copy_journal(%s, '2026-11-27', 'wrong')$$,
  (select id from journals where source = 'purchases' and status = 'posted' order by id limit 1)), 'Reverse it there');
select t_ok((rb_journal_detail((select id from journals where source = 'purchases' and status = 'posted' order by id limit 1))->>'can_correct')::boolean is false,
            'The journal screen does not offer Reverse and correct for a purchase journal');
select rb_remove_demo_data('REMOVE DEMO');
select t_ok(not exists (select 1 from purchases where is_demo) and not exists (select 1 from stock_moves where is_demo)
        and not exists (select 1 from supplier_payments where is_demo), 'DEMO purchases, stock moves and payments removed');
select t_ok(exists (select 1 from purchases where id = :po1), 'Training purchases stay until go-live');
select rb_go_live('2027-04-01', 'GO LIVE');
select t_ok(not exists (select 1 from purchases) and not exists (select 1 from stock_moves) and not exists (select 1 from supplier_payments)
        and not exists (select 1 from journals), 'Go-live clears training purchases, stock and payments');
select rb_save_purchase_order(jsonb_build_object('supplier_id', :sup, 'po_date', '2027-04-02', 'lines', jsonb_build_array(
  jsonb_build_object('item_id', :prawn, 'unit_code', 'kg', 'qty', 1, 'rate_paise', 60000)))) as po9 \gset
select t_ok((select po_no from purchases where id = :po9) = 'PO/2704/00001', 'After go-live, orders start at PO/YYMM/00001');

reset role;
\echo ALL MODULE 3 TESTS PASSED
