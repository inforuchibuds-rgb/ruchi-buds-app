-- =====================================================================
-- RUCHI BUDS APP · Module 10: Online shop
-- File: 10_shop.sql · Version 1.0 · 27-Nov-2026
--
-- What this file sets up (spec section 8A):
--   - a public shop page (shop.html) built from finished-goods stock:
--     photo, product, pack size and price. A Director or the FC chooses
--     which packs appear, and can hide any. A pack with no free stock
--     shows SOLD OUT;
--   - an order with name, phone and address, numbered ORD/YYMM/00001,
--     for delivery (charge by PIN code, from a list in Settings) or
--     pickup. The quantity ordered is held at once: it cannot be sold at
--     the counter or online. An unpaid order lets go of the hold after
--     the minutes set in Settings;
--   - payment by UPI (the customer pays to the firm's UPI ID and enters
--     the UPI reference; staff check it and tick Paid), or cash on
--     delivery when every item in the cart allows it;
--   - paid and cash-on-delivery orders alert the staff categories chosen
--     in Settings, in the app and by email (the Apps Script sends it);
--   - staff pack the order. On dispatch it becomes an invoice and the
--     stock leaves finished goods. Cash on delivery is recorded when it
--     comes in. A cancelled order lets go of the hold; money already paid
--     stays on the customer's account for the accounts team to refund;
--   - the online orders report, and Free / On hold / Total stock.
--
-- Run 01 to 09 first. Then: Supabase -> SQL Editor -> New query -> paste
-- this whole file -> Run. It is safe to run again; nothing you entered
-- is lost on a re-run. If an earlier file is ever run again, run the
-- later files again straight after it, in order, ending with this one.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Screen, rights and settings
-- ---------------------------------------------------------------------

update screens set available = true where code = 'shop';

-- New right: set up the shop (which packs appear, photos, delivery
-- charges, payment and alerts). Given to no category: Directors and the
-- FC always have every right.
insert into powers (code, name, description, sort) values
  ('shop_setup', 'Set up the online shop', 'Choose the products on the online shop, delivery charges, payment and alerts', 115)
on conflict (code) do update set name = excluded.name, description = excluded.description, sort = excluded.sort;
insert into permissions (code, kind, power_code, sort) values ('power.shop_setup', 'power', 'shop_setup', 10115)
on conflict (code) do nothing;

alter table app_settings add column if not exists shop_open boolean not null default false;
alter table app_settings add column if not exists shop_hold_minutes int not null default 30;
alter table app_settings drop constraint if exists app_settings_shop_hold_minutes_check;
alter table app_settings add constraint app_settings_shop_hold_minutes_check check (shop_hold_minutes between 5 and 1440);
alter table app_settings add column if not exists shop_upi_id text;
alter table app_settings add column if not exists shop_upi_name text;
alter table app_settings add column if not exists shop_pay_upi boolean not null default true;
alter table app_settings add column if not exists shop_pay_cod boolean not null default true;
alter table app_settings add column if not exists shop_pickup boolean not null default true;
alter table app_settings add column if not exists shop_pickup_address text;
alter table app_settings add column if not exists shop_delivery boolean not null default true;
alter table app_settings add column if not exists shop_note text;
alter table app_settings add column if not exists shop_phone text;
alter table app_settings add column if not exists shop_max_unpaid int not null default 3;
alter table app_settings add column if not exists shop_alert_categories smallint[] not null default '{}';

-- ---------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------

-- Which packs appear on the shop page, with a photo and a short line.
create table if not exists shop_products (
  pack_id      int primary key references product_packs(id) on delete cascade,
  visible      boolean not null default false,
  cod_allowed  boolean not null default false,
  description  text,
  photo        text check (photo is null or (photo like 'data:image/%' and length(photo) <= 400000)),
  sort         int not null default 100,
  updated_at   timestamptz,
  updated_by   uuid,
  is_demo      boolean not null default false
);

-- Delivery charge by PIN code. PIN '*' = every other PIN code.
create table if not exists shop_delivery_areas (
  id            serial primary key,
  pin_code      text not null unique check (pin_code = '*' or pin_code ~ '^[1-9][0-9]{5}$'),
  area_name     text,
  charge_paise  bigint not null default 0 check (charge_paise >= 0),
  is_active     boolean not null default true,
  updated_at    timestamptz,
  updated_by    uuid,
  is_demo       boolean not null default false
);

create table if not exists shop_orders (
  id               bigserial primary key,
  order_no         text not null unique,
  token            text not null unique,              -- the customer's link to the order page
  placed_at        timestamptz not null default now(),
  order_date       date not null default ((now() at time zone 'Asia/Kolkata')::date),  -- the date in India
  cust_name        text not null,
  cust_phone       text not null,
  cust_address     text,
  pin_code         text,
  cust_note        text,
  fulfil           text not null check (fulfil in ('delivery', 'pickup')),
  pay_method       text not null check (pay_method in ('upi', 'cod')),
  -- placed: waiting for UPI payment (held until hold_until);
  -- payment_check: the customer gave a UPI reference, staff to check;
  -- paid / cod: ready to pack; packed; dispatched (invoice made);
  -- delivered (cash on delivery received, or handed over); cancelled; expired.
  status           text not null default 'placed'
                   check (status in ('placed', 'payment_check', 'paid', 'cod', 'packed', 'dispatched', 'delivered', 'cancelled', 'expired')),
  hold_until       timestamptz,
  with_gst         boolean not null default false,    -- the firm was GST registered when the order was placed
  prices_incl_gst  boolean not null default true,
  goods_paise      bigint not null default 0,
  delivery_paise   bigint not null default 0,         -- before GST
  gst_paise        bigint not null default 0,         -- GST added on top (none when prices include GST)
  total_paise      bigint not null default 0,
  upi_ref          text,
  upi_ref_at       timestamptz,
  paid_at          timestamptz,
  paid_by          uuid,
  customer_id      int references customers(id) on delete set null,
  receipt_id       bigint references customer_receipts(id) on delete set null,
  sale_id          bigint references sales(id) on delete set null,
  cash_receipt_id  bigint references customer_receipts(id) on delete set null,
  packed_at        timestamptz,
  packed_by        uuid,
  dispatched_at    timestamptz,
  dispatched_by    uuid,
  delivered_at     timestamptz,
  delivered_by     uuid,
  cancel_reason    text,
  cancelled_at     timestamptz,
  cancelled_by     uuid,
  staff_note       text,
  is_demo          boolean not null default false,
  is_training      boolean not null default false
);
create index if not exists shop_orders_status_idx on shop_orders (status);
create index if not exists shop_orders_phone_idx on shop_orders (cust_phone);
create index if not exists shop_orders_date_idx on shop_orders (order_date);

create table if not exists shop_order_lines (
  id            bigserial primary key,
  order_id      bigint not null references shop_orders(id) on delete cascade,
  line_no       int not null,
  item_id       int not null references items(id),
  pack_id       int not null references product_packs(id),
  description   text not null,
  packs         int not null check (packs > 0),
  qty_base      numeric(16,3) not null,
  rate_paise    bigint not null check (rate_paise >= 0),
  amount_paise  bigint not null,
  gst_rate      numeric(5,2) not null default 0,
  gst_paise     bigint not null default 0,
  is_demo       boolean not null default false,
  is_training   boolean not null default false,
  unique (order_id, line_no)
);
create index if not exists shop_order_lines_pack_idx on shop_order_lines (pack_id);

-- Alerts to staff: shown in the app, and emailed by the Apps Script.
create table if not exists shop_alerts (
  id          bigserial primary key,
  at          timestamptz not null default now(),
  order_id    bigint references shop_orders(id) on delete cascade,
  kind        text not null check (kind in ('payment_check', 'paid', 'cod')),
  message     text not null,
  emailed_at  timestamptz,
  is_demo     boolean not null default false,
  is_training boolean not null default false
);
create index if not exists shop_alerts_at_idx on shop_alerts (at desc);

-- ---------------------------------------------------------------------
-- 3. Helpers (private)
-- ---------------------------------------------------------------------

-- Packs of one product pack held by online orders (optionally leaving one order out).
create or replace function rb_shop_held(p_pack int, p_except bigint default null)
returns bigint language sql stable security definer set search_path = public as $$
  select coalesce(sum(l.packs), 0)::bigint
  from shop_order_lines l join shop_orders o on o.id = l.order_id
  where l.pack_id = p_pack and o.id is distinct from p_except
    and (o.status in ('payment_check', 'paid', 'cod', 'packed') or (o.status = 'placed' and o.hold_until > now()))
$$;

-- Whole packs on hand now (every movement, including later-dated ones).
create or replace function rb_shop_on_hand(p_pack int)
returns bigint language sql stable security definer set search_path = public as $$
  select coalesce(floor(sum(m.qty_base) / max(pp.net_qty)), 0)::bigint
  from product_packs pp left join stock_moves m on m.item_id = pp.item_id and m.pack_id = pp.id
  where pp.id = p_pack
$$;

create or replace function rb_shop_free(p_pack int, p_except bigint default null)
returns bigint language sql stable security definer set search_path = public as $$
  select greatest(rb_shop_on_hand(p_pack) - rb_shop_held(p_pack, p_except), 0)
$$;

-- Unpaid orders past their time let go of their hold.
create or replace function rb_shop_expire()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update shop_orders set status = 'expired' where status = 'placed' and hold_until <= now();
  get diagnostics n = row_count;
  return n;
end $$;

-- A phone number as 10 digits, or null.
create or replace function rb_shop_phone(p text)
returns text language sql immutable as $$
  select case when d ~ '^[6-9][0-9]{9}$' then d
              when d ~ '^91[6-9][0-9]{9}$' then right(d, 10)
              when d ~ '^0[6-9][0-9]{9}$' then right(d, 10) end
  from (select regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') d) x
$$;

-- The delivery charge for a PIN code (null = no delivery there).
create or replace function rb_shop_delivery_for(p_pin text)
returns bigint language sql stable security definer set search_path = public as $$
  select coalesce((select charge_paise from shop_delivery_areas where pin_code = p_pin and is_active),
                  (select charge_paise from shop_delivery_areas where pin_code = '*' and is_active))
$$;

-- Recompute an order's totals from its lines and delivery charge.
-- GST is added on top only when the firm was registered and prices do
-- not include GST, the same way the invoice is worked out.
create or replace function rb_shop_recalc(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare o shop_orders; v_goods bigint; v_gst bigint; v_rate numeric; v_dgst bigint := 0;
begin
  select * into o from shop_orders where id = p_id;
  update shop_order_lines set gst_paise = case when o.with_gst and not o.prices_incl_gst
                                               then round(amount_paise * gst_rate / 100)::bigint else 0 end
  where order_id = p_id;
  select coalesce(sum(amount_paise), 0), coalesce(sum(gst_paise), 0), max(gst_rate) into v_goods, v_gst, v_rate
  from shop_order_lines where order_id = p_id;
  if o.with_gst and not o.prices_incl_gst and o.delivery_paise > 0 then
    v_dgst := round(o.delivery_paise * coalesce(v_rate, 0) / 100)::bigint;
  end if;
  update shop_orders set goods_paise = v_goods, gst_paise = v_gst + v_dgst,
         total_paise = v_goods + v_gst + v_dgst + delivery_paise
  where id = p_id;
end $$;

create or replace function rb_shop_alert(p_id bigint, p_kind text)
returns void language plpgsql security definer set search_path = public as $$
declare o shop_orders;
begin
  select * into o from shop_orders where id = p_id;
  insert into shop_alerts (order_id, kind, message, is_demo, is_training)
  values (o.id, p_kind,
    case p_kind
      when 'payment_check' then 'Check the UPI payment for ' || o.order_no || ' (' || rb_pur_fmt(o.total_paise) || ', ref ' || coalesce(o.upi_ref, '-') || ') from ' || o.cust_name
      when 'paid' then o.order_no || ' is paid (' || rb_pur_fmt(o.total_paise) || '): please pack it. ' || o.cust_name || ', ' || initcap(o.fulfil)
      else o.order_no || ' is cash on delivery (' || rb_pur_fmt(o.total_paise) || '): please pack it. ' || o.cust_name || ', ' || initcap(o.fulfil)
    end, o.is_demo, o.is_training);
end $$;

-- The customer for an order: found by phone, or added.
create or replace function rb_shop_customer(p_id bigint, p_actor uuid)
returns int language plpgsql security definer set search_path = public as $$
declare o shop_orders; v_c int;
begin
  select * into o from shop_orders where id = p_id;
  if o.customer_id is not null then return o.customer_id; end if;
  select id into v_c from customers
  where phone = o.cust_phone and kind = 'retail' and not is_walk_in and is_active and is_demo = o.is_demo
  order by id limit 1;
  if v_c is null then
    insert into customers (code, kind, name, phone, address, notes, is_demo, created_by)
    values (case when o.is_demo then 'DEMO-' else '' end || rb_next_code(case when o.is_demo then 'DEMO-CUSTOMER' else 'CUSTOMER' end, 'C', 5),
            'retail', o.cust_name, o.cust_phone,
            nullif(concat_ws(', ', o.cust_address, o.pin_code), ''), 'Added by the online shop (' || o.order_no || ')', o.is_demo, p_actor)
    returning id into v_c;
  elsif o.fulfil = 'delivery' and o.cust_address is not null then
    update customers set address = concat_ws(', ', o.cust_address, o.pin_code), updated_at = now(), updated_by = p_actor where id = v_c;
  end if;
  update shop_orders set customer_id = v_c where id = p_id;
  return v_c;
end $$;

-- Lock and read an order for a staff action.
create or replace function rb_shop_get(p_id bigint)
returns shop_orders language plpgsql security definer set search_path = public as $$
declare o shop_orders;
begin
  perform rb_shop_expire();
  select * into o from shop_orders where id = p_id for update;
  if o.id is null then raise exception 'Order not found.'; end if;
  return o;
end $$;

-- Selling a pack at the counter (or dispatching another order) may not
-- eat into the packs held for online orders.
create or replace function rb_shop_guard_stock()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_on numeric; v_held bigint; v_net numeric; v_except bigint := nullif(current_setting('rb.shop_order', true), '')::bigint;
begin
  if new.kind <> 'sale' or new.qty_base >= 0 or new.pack_id is null then return new; end if;
  perform pg_advisory_xact_lock(hashtext('rb_shop_stock'));
  v_held := rb_shop_held(new.pack_id, v_except);
  if v_held = 0 then return new; end if;
  select net_qty into v_net from product_packs where id = new.pack_id;
  select coalesce(sum(qty_base), 0) into v_on from stock_moves where item_id = new.item_id and pack_id = new.pack_id;
  if v_on + new.qty_base < v_held * v_net then
    raise exception '% packs of % are held for online orders, so only % can be sold now.',
      v_held, rb_stk_label(new.item_id, new.pack_id), greatest(floor(v_on / v_net) - v_held, 0);
  end if;
  return new;
end $$;
drop trigger if exists rb_shop_guard_stock on stock_moves;
create trigger rb_shop_guard_stock before insert on stock_moves for each row execute function rb_shop_guard_stock();

-- ---------------------------------------------------------------------
-- 4. The public shop page (no sign-in)
-- ---------------------------------------------------------------------

-- Everything the shop page shows.
create or replace function rb_shop_catalogue()
returns jsonb language plpgsql security definer set search_path = public as $$
declare s app_settings; v_gst boolean;
begin
  perform rb_shop_expire();
  select * into s from app_settings where id = 1;
  v_gst := rb_pur_gst_claimable(current_date);
  return jsonb_build_object(
    'open', s.shop_open, 'firm_name', s.firm_name, 'note', s.shop_note, 'phone', coalesce(s.shop_phone, s.phone),
    'fssai_no', s.fssai_no, 'training', s.training_mode,
    'pickup', s.shop_pickup, 'pickup_address', s.shop_pickup_address, 'delivery', s.shop_delivery,
    'pay_upi', s.shop_pay_upi and s.shop_upi_id is not null, 'pay_cod', s.shop_pay_cod,
    'with_gst', v_gst, 'prices_incl_gst', s.sale_prices_include_gst, 'hold_minutes', s.shop_hold_minutes,
    'areas', coalesce((select jsonb_agg(jsonb_build_object('pin_code', pin_code, 'area_name', area_name, 'charge_paise', charge_paise)
                                        order by pin_code = '*', pin_code)
                       from shop_delivery_areas where is_active and (s.training_mode or not is_demo)), '[]'::jsonb),
    'products', case when not s.shop_open then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'pack_id', pp.id, 'item_id', i.id, 'name', i.name, 'pack', pt.name, 'description', sp.description, 'photo', sp.photo,
        'price_paise', rb_sal_list_price(i.id, pp.id, 'online'), 'gst_rate', case when v_gst then i.gst_rate end,
        'cod_allowed', sp.cod_allowed, 'free', least(rb_shop_free(pp.id), 99)) order by sp.sort, i.name, pp.net_qty)
      from shop_products sp join product_packs pp on pp.id = sp.pack_id join items i on i.id = pp.item_id
      join pack_types pt on pt.id = pp.pack_type_id
      where sp.visible and pp.is_active and i.is_active and rb_sal_list_price(i.id, pp.id, 'online') is not null
        and (s.training_mode or not pp.is_demo)), '[]'::jsonb) end);
end $$;

-- Place an order.
-- p: name, phone, fulfil ('delivery' | 'pickup'), address, pin_code, note,
--    pay_method ('upi' | 'cod'), lines [{pack_id, packs}]
create or replace function rb_shop_place(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s app_settings; v_phone text := rb_shop_phone(p->>'phone'); v_name text := left(rb_txt(p, 'name'), 80);
        v_fulfil text := coalesce(rb_txt(p, 'fulfil'), 'delivery'); v_pay text := coalesce(rb_txt(p, 'pay_method'), 'upi');
        v_addr text := left(rb_txt(p, 'address'), 300); v_pin text := regexp_replace(coalesce(p->>'pin_code', ''), '\s', '', 'g');
        v_dl bigint := 0; l jsonb; v_pp product_packs; v_it items; v_sp shop_products; v_n int; v_free bigint; v_rate bigint;
        v_id bigint; v_no text; v_demo boolean; v_real boolean := false; v_fake boolean := false; i int := 0; v_gst boolean;
        v_seen int[] := '{}'; o shop_orders; v_pt text;
begin
  perform rb_shop_expire();
  select * into s from app_settings where id = 1;
  if not s.shop_open then raise exception 'The shop is closed just now. Please try again later.'; end if;
  if v_name is null then raise exception 'Please enter your name.'; end if;
  if v_phone is null then raise exception 'Please enter a 10-digit mobile number.'; end if;
  if v_fulfil not in ('delivery', 'pickup') then raise exception 'Choose delivery or pickup.'; end if;
  if v_fulfil = 'delivery' and not s.shop_delivery then raise exception 'Delivery is not available just now. Please choose pickup.'; end if;
  if v_fulfil = 'pickup' and not s.shop_pickup then raise exception 'Pickup is not available just now. Please choose delivery.'; end if;
  if v_fulfil = 'delivery' then
    if v_addr is null then raise exception 'Please enter the delivery address.'; end if;
    if v_pin !~ '^[1-9][0-9]{5}$' then raise exception 'Please enter the 6-digit PIN code.'; end if;
    v_dl := rb_shop_delivery_for(v_pin);
    if v_dl is null then
      raise exception 'Sorry, we do not deliver to PIN code % yet. Please choose pickup, or call us.', v_pin;
    end if;
  else
    v_pin := null;
  end if;
  if v_pay not in ('upi', 'cod') then raise exception 'Choose how you will pay.'; end if;
  if v_pay = 'upi' and not (s.shop_pay_upi and s.shop_upi_id is not null) then raise exception 'UPI payment is not available just now.'; end if;
  if v_pay = 'cod' and not s.shop_pay_cod then raise exception 'Cash on delivery is not available just now.'; end if;
  if jsonb_array_length(coalesce(p->'lines', '[]')) = 0 then raise exception 'Your cart is empty.'; end if;
  if jsonb_array_length(p->'lines') > 30 then raise exception 'Please order at most 30 different items at a time.'; end if;
  if (select count(*) from shop_orders where cust_phone = v_phone
        and (status = 'payment_check' or (status = 'placed' and hold_until > now()))) >= s.shop_max_unpaid then
    raise exception 'This number already has % orders waiting for payment. Please pay for those first, or call us.', s.shop_max_unpaid;
  end if;
  if (select count(*) from shop_orders where status = 'placed' and hold_until > now()) >= 200 then
    raise exception 'The shop is very busy just now. Please try again in a few minutes.';
  end if;

  -- One order at a time, so two customers cannot both get the last bottle.
  perform pg_advisory_xact_lock(hashtext('rb_shop_stock'));
  v_gst := rb_pur_gst_claimable(current_date);
  for l in select * from jsonb_array_elements(p->'lines') loop
    select * into v_pp from product_packs where id = rb_int(l, 'pack_id');
    select * into v_sp from shop_products where pack_id = v_pp.id;
    select * into v_it from items where id = v_pp.item_id;
    if v_pp.id is null or v_sp.pack_id is null or not v_sp.visible or not v_pp.is_active or not v_it.is_active
       or (v_pp.is_demo and not s.training_mode) then
      raise exception 'One of the items in your cart is no longer on the shop. Please reload the page.';
    end if;
    if v_pp.id = any (v_seen) then continue; end if;
    v_seen := v_seen || v_pp.id;
    v_n := nullif(trim(l->>'packs'), '')::numeric::int;
    if v_n is null or v_n <= 0 then continue; end if;
    if v_n > 50 then raise exception 'Please order at most 50 of one item. For bigger orders, call us.'; end if;
    select name into v_pt from pack_types where id = v_pp.pack_type_id;
    v_free := rb_shop_free(v_pp.id);
    if v_free < v_n then
      raise exception '%', case when v_free = 0 then v_it.name || ', ' || v_pt || ' has just sold out.'
                                else 'Only ' || v_free || ' of ' || v_it.name || ', ' || v_pt || ' are left.' end;
    end if;
    if v_pay = 'cod' and not v_sp.cod_allowed then
      raise exception '% cannot be paid for on delivery. Please pay by UPI, or take it out of the cart.', v_it.name;
    end if;
    if v_gst and (v_it.hsn_code is null or v_it.gst_rate is null) then
      raise exception '% cannot be ordered online just now. Please call us.', v_it.name;
    end if;
    v_rate := rb_sal_list_price(v_it.id, v_pp.id, 'online');
    if v_rate is null then raise exception '% has no price just now. Please call us.', v_it.name; end if;
    if v_pp.is_demo then v_fake := true; else v_real := true; end if;
    if v_id is null then
      v_demo := v_pp.is_demo;
      v_no := rb_next_doc_no(rb_pur_series('ORD', v_demo), (now() at time zone 'Asia/Kolkata')::date);
      insert into shop_orders (order_no, token, cust_name, cust_phone, cust_address, pin_code, cust_note, fulfil, pay_method, status,
                               hold_until, with_gst, prices_incl_gst, delivery_paise, is_demo, is_training)
      values (v_no, encode(extensions.gen_random_bytes(16), 'hex'), v_name, v_phone, case when v_fulfil = 'delivery' then v_addr end,
              v_pin, left(rb_txt(p, 'note'), 300), v_fulfil, v_pay, case when v_pay = 'cod' then 'cod' else 'placed' end,
              case when v_pay = 'upi' then now() + make_interval(mins => s.shop_hold_minutes) end,
              v_gst, s.sale_prices_include_gst, v_dl, v_demo, rb_is_training())
      returning id into v_id;
    end if;
    i := i + 1;
    insert into shop_order_lines (order_id, line_no, item_id, pack_id, description, packs, qty_base, rate_paise, amount_paise, gst_rate,
                                  is_demo, is_training)
    values (v_id, i, v_it.id, v_pp.id, v_it.name || ', ' || v_pt, v_n, v_n * v_pp.net_qty, v_rate, v_n * v_rate,
            case when v_gst then v_it.gst_rate else 0 end, v_demo, rb_is_training());
  end loop;
  if v_id is null then raise exception 'Your cart is empty.'; end if;
  if v_real and v_fake then raise exception 'DEMO products cannot be ordered together with real ones.'; end if;
  perform rb_shop_recalc(v_id);
  select * into o from shop_orders where id = v_id;
  if o.pay_method = 'cod' then perform rb_shop_alert(v_id, 'cod'); end if;
  perform rb_audit_write('SHOP_ORDER', 'shop_orders', v_id::text, null,
    jsonb_build_object('order_no', o.order_no, 'name', o.cust_name, 'total_paise', o.total_paise, 'pay', o.pay_method), 'Online order');
  return jsonb_build_object('order_no', o.order_no, 'token', o.token, 'total_paise', o.total_paise);
end $$;

-- The customer's order page.
create or replace function rb_shop_order(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o shop_orders; s app_settings;
begin
  perform rb_shop_expire();
  select * into o from shop_orders where token = p_token;
  if o.id is null or coalesce(p_token, '') = '' then raise exception 'Order not found. Please check the link.'; end if;
  select * into s from app_settings where id = 1;
  return jsonb_build_object('order_no', o.order_no, 'placed_at', o.placed_at, 'status', o.status, 'hold_until', o.hold_until,
    'name', o.cust_name, 'phone', o.cust_phone, 'address', o.cust_address, 'pin_code', o.pin_code, 'fulfil', o.fulfil,
    'pay_method', o.pay_method, 'goods_paise', o.goods_paise, 'delivery_paise', o.delivery_paise, 'gst_paise', o.gst_paise,
    'total_paise', o.total_paise, 'with_gst', o.with_gst, 'prices_incl_gst', o.prices_incl_gst, 'upi_ref', o.upi_ref,
    'invoice_no', (select invoice_no from sales where id = o.sale_id), 'firm_name', s.firm_name, 'phone_us', coalesce(s.shop_phone, s.phone),
    'pickup_address', case when o.fulfil = 'pickup' then s.shop_pickup_address end,
    'upi_id', case when o.status = 'placed' then s.shop_upi_id end, 'upi_name', coalesce(s.shop_upi_name, s.firm_name),
    'is_demo', o.is_demo,
    'lines', (select jsonb_agg(jsonb_build_object('description', description, 'packs', packs, 'rate_paise', rate_paise,
                                                  'amount_paise', amount_paise) order by line_no)
              from shop_order_lines where order_id = o.id));
end $$;

-- The customer has paid by UPI and gives the reference (UTR) number.
create or replace function rb_shop_submit_ref(p_token text, p_ref text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o shop_orders; v_ref text := upper(regexp_replace(coalesce(p_ref, ''), '\s', '', 'g')); l record; v_phone text;
begin
  perform rb_shop_expire();
  select * into o from shop_orders where token = p_token for update;
  if o.id is null or coalesce(p_token, '') = '' then raise exception 'Order not found. Please check the link.'; end if;
  if o.pay_method <> 'upi' then raise exception 'This order is cash on delivery.'; end if;
  if v_ref !~ '^[A-Z0-9]{6,35}$' then raise exception 'Please enter the UPI reference (UTR) number from your UPI app: 12 digits.'; end if;
  if o.status = 'payment_check' then raise exception 'We already have your reference %. We will check it shortly.', o.upi_ref; end if;
  if o.status = 'expired' then
    -- Paid a little late: take it if the stock is still free.
    perform pg_advisory_xact_lock(hashtext('rb_shop_stock'));
    for l in select pack_id, packs, description from shop_order_lines where order_id = o.id loop
      if rb_shop_free(l.pack_id, o.id) < l.packs then
        select coalesce(shop_phone, phone) into v_phone from app_settings where id = 1;
        raise exception 'This order expired at % and % is no longer held for it. If you have already paid, please call us%, with your UPI reference.',
          to_char(o.hold_until at time zone 'Asia/Kolkata', 'HH12:MI AM'), l.description, coalesce(' on ' || v_phone, '');
      end if;
    end loop;
  elsif o.status <> 'placed' then
    raise exception 'This order is no longer waiting for payment.';
  end if;
  update shop_orders set status = 'payment_check', upi_ref = v_ref, upi_ref_at = now() where id = o.id;
  perform rb_shop_alert(o.id, 'payment_check');
  return rb_shop_order(p_token);
end $$;

-- The customer cancels an order not yet paid.
create or replace function rb_shop_public_cancel(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o shop_orders;
begin
  perform rb_shop_expire();
  select * into o from shop_orders where token = p_token for update;
  if o.id is null or coalesce(p_token, '') = '' then raise exception 'Order not found. Please check the link.'; end if;
  if o.status not in ('placed', 'cod', 'expired') then
    raise exception 'This order can no longer be cancelled here. Please call us.';
  end if;
  update shop_orders set status = 'cancelled', cancel_reason = 'Cancelled by the customer', cancelled_at = now() where id = o.id;
  return rb_shop_order(p_token);
end $$;

-- ---------------------------------------------------------------------
-- 5. Staff actions (private versions take the actor, so the DEMO data
--    can use them; the screens call the rb_shop_ ones in section 6)
-- ---------------------------------------------------------------------

-- Staff tick Paid: the UPI money is booked as a receipt from the customer.
create or replace function rb_shop_do_paid(p_id bigint, p_ref text, p_date date, p_actor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare o shop_orders := rb_shop_get(p_id); v_c int; v_r bigint; v_ref text := nullif(upper(regexp_replace(coalesce(p_ref, ''), '\s', '', 'g')), '');
begin
  if o.pay_method <> 'upi' then raise exception 'This order is cash on delivery: record the cash when it comes in.'; end if;
  if o.status not in ('placed', 'payment_check', 'expired') then raise exception '% is not waiting for payment.', o.order_no; end if;
  v_ref := coalesce(v_ref, o.upi_ref);
  if v_ref is null then raise exception 'Please enter the UPI reference you can see in the bank account.'; end if;
  if o.status = 'expired' then
    if exists (select 1 from shop_order_lines l where l.order_id = o.id and rb_shop_free(l.pack_id, o.id) < l.packs) then
      raise exception 'The hold on % has run out and some items were sold. Cancel the order and refund the money.', o.order_no;
    end if;
  end if;
  v_c := rb_shop_customer(o.id, p_actor);
  v_r := rb_sal_receive(jsonb_build_object('customer_id', v_c, 'receipt_date', coalesce(p_date, current_date), 'mode', 'upi',
    'amount_paise', o.total_paise, 'reference', v_ref, 'department_id', rb_sal_dept('online'),
    'note', 'Online order ' || o.order_no), p_actor, o.is_demo);
  update shop_orders set status = 'paid', upi_ref = v_ref, paid_at = now(), paid_by = p_actor, receipt_id = v_r where id = o.id;
  perform rb_shop_alert(o.id, 'paid');
  perform rb_audit_write('SHOP_PAID', 'shop_orders', o.id::text, null, jsonb_build_object('order_no', o.order_no, 'ref', v_ref,
    'amount_paise', o.total_paise), null);
end $$;

create or replace function rb_shop_do_pack(p_id bigint, p_actor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare o shop_orders := rb_shop_get(p_id);
begin
  if o.status not in ('paid', 'cod') then raise exception '% is not ready to pack (it must be paid, or cash on delivery).', o.order_no; end if;
  update shop_orders set status = 'packed', packed_at = now(), packed_by = p_actor where id = o.id;
end $$;

-- Dispatch: the order becomes an invoice and the stock leaves finished goods.
create or replace function rb_shop_do_dispatch(p_id bigint, p_date date, p_actor uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o shop_orders := rb_shop_get(p_id); v_c int; v_sale jsonb; v_sid bigint; v_left bigint; v_out bigint;
begin
  if o.status not in ('paid', 'cod', 'packed') then raise exception '% cannot be dispatched now.', o.order_no; end if;
  if o.status = 'packed' and o.receipt_id is null and o.pay_method = 'upi' then raise exception '% is not paid yet.', o.order_no; end if;
  v_c := rb_shop_customer(o.id, p_actor);
  perform set_config('rb.shop_order', o.id::text, true);
  v_sale := rb_sal_save(jsonb_build_object(
    'customer_id', v_c, 'invoice_date', coalesce(p_date, current_date),
    'doc_type', case when o.with_gst then 'tax_invoice' else 'invoice' end, 'channel', 'online',
    'payment_mode', 'credit', 'bill_name', o.cust_name, 'delivery_paise', o.delivery_paise,
    'note', 'Online order ' || o.order_no || case when o.fulfil = 'pickup' then ' (pickup)' else '' end,
    'lines', (select jsonb_agg(jsonb_build_object('item_id', item_id, 'pack_id', pack_id, 'packs', packs, 'rate_paise', rate_paise)
                               order by line_no) from shop_order_lines where order_id = o.id)), p_actor, o.is_demo);
  perform set_config('rb.shop_order', '', true);
  v_sid := (v_sale->>'id')::bigint;
  if o.receipt_id is not null then
    v_left := rb_sal_source_left('receipt', o.receipt_id);
    select outstanding_paise into v_out from sales where id = v_sid;
    if least(v_left, v_out) > 0 then
      perform rb_sal_allocate('receipt', o.receipt_id,
        jsonb_build_array(jsonb_build_object('sale_id', v_sid, 'amount_paise', least(v_left, v_out))), p_actor);
    end if;
  end if;
  update shop_orders set status = case when o.pay_method = 'upi' then 'delivered' else 'dispatched' end,
         sale_id = v_sid, dispatched_at = now(), dispatched_by = p_actor,
         packed_at = coalesce(packed_at, now()), packed_by = coalesce(packed_by, p_actor),
         delivered_at = case when o.pay_method = 'upi' then now() end, delivered_by = case when o.pay_method = 'upi' then p_actor end
  where id = o.id;
  return v_sale;
end $$;

-- Cash on delivery: the money has come in (cash, or UPI at the door or counter).
create or replace function rb_shop_do_cash(p_id bigint, p_mode text, p_date date, p_ref text, p_actor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare o shop_orders := rb_shop_get(p_id); v_out bigint; v_r bigint; v_mode text := coalesce(p_mode, 'cash');
begin
  if o.pay_method <> 'cod' or o.status <> 'dispatched' then raise exception '% is not waiting for cash on delivery.', o.order_no; end if;
  if v_mode not in ('cash', 'upi') then raise exception 'Choose cash or UPI.'; end if;
  select outstanding_paise into v_out from sales where id = o.sale_id;
  if coalesce(v_out, 0) > 0 then
    v_r := rb_sal_receive(jsonb_build_object('customer_id', o.customer_id, 'receipt_date', coalesce(p_date, current_date), 'mode', v_mode,
      'amount_paise', v_out, 'reference', nullif(trim(coalesce(p_ref, '')), ''), 'department_id', rb_sal_dept('online'),
      'note', 'Cash on delivery, online order ' || o.order_no,
      'allocations', jsonb_build_array(jsonb_build_object('sale_id', o.sale_id, 'amount_paise', v_out))), p_actor, o.is_demo);
  end if;
  update shop_orders set status = 'delivered', cash_receipt_id = v_r, paid_at = now(), paid_by = p_actor,
         delivered_at = now(), delivered_by = p_actor where id = o.id;
end $$;

create or replace function rb_shop_do_cancel(p_id bigint, p_reason text, p_actor uuid)
returns text language plpgsql security definer set search_path = public as $$
declare o shop_orders := rb_shop_get(p_id);
begin
  if nullif(trim(coalesce(p_reason, '')), '') is null then raise exception 'Please give the reason for cancelling.'; end if;
  if o.status in ('dispatched', 'delivered') then
    raise exception '% has been invoiced (%). To take goods back, enter a sales return on the invoice.', o.order_no,
      (select invoice_no from sales where id = o.sale_id);
  end if;
  if o.status = 'cancelled' then raise exception '% is already cancelled.', o.order_no; end if;
  update shop_orders set status = 'cancelled', cancel_reason = trim(p_reason), cancelled_at = now(), cancelled_by = p_actor where id = o.id;
  perform rb_audit_write('SHOP_CANCEL', 'shop_orders', o.id::text, null, jsonb_build_object('order_no', o.order_no), trim(p_reason));
  if o.receipt_id is not null then
    return 'Cancelled. The ' || rb_pur_fmt(o.total_paise) || ' paid stays on the customer''s account: the accounts team refunds it from Invoices → Customers.';
  end if;
  return 'Cancelled. The items are free to sell again.';
end $$;

-- ---------------------------------------------------------------------
-- 6. What the staff screen calls
-- ---------------------------------------------------------------------

create or replace function rb_shop_mark_paid(p_id bigint, p_ref text, p_date date)
returns void language plpgsql security definer set search_path = public as $$
begin perform rb_shop_do_paid(p_id, p_ref, p_date, rb_require('shop.edit', 'mark online orders paid')); end $$;

-- The UPI money was not found: the order waits for payment again.
create or replace function rb_shop_payment_not_found(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('shop.edit', 'check online payments'); o shop_orders := rb_shop_get(p_id);
begin
  if o.status <> 'payment_check' then raise exception '% is not waiting for a payment check.', o.order_no; end if;
  update shop_orders set status = 'placed', staff_note = 'UPI reference ' || o.upi_ref || ' not found',
         upi_ref = null, hold_until = now() + make_interval(mins => (select shop_hold_minutes from app_settings where id = 1))
  where id = o.id;
end $$;

-- Staff may change the delivery charge before the order is paid
-- (cash on delivery: before dispatch).
create or replace function rb_shop_set_delivery(p_id bigint, p_charge_paise bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('shop.edit', 'change delivery charges'); o shop_orders := rb_shop_get(p_id);
begin
  if coalesce(p_charge_paise, -1) < 0 then raise exception 'Please enter the delivery charge (0 or more).'; end if;
  if not (o.status = 'placed' or (o.pay_method = 'cod' and o.status in ('cod', 'packed'))) then
    raise exception 'The delivery charge can only be changed before the order is paid.';
  end if;
  update shop_orders set delivery_paise = p_charge_paise where id = o.id;
  perform rb_shop_recalc(o.id);
  perform rb_audit_write('SHOP_DELIVERY', 'shop_orders', o.id::text, jsonb_build_object('delivery_paise', o.delivery_paise),
    jsonb_build_object('delivery_paise', p_charge_paise), o.order_no);
end $$;

create or replace function rb_shop_pack(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin perform rb_shop_do_pack(p_id, rb_require('shop.edit', 'pack online orders')); end $$;

create or replace function rb_shop_dispatch(p_id bigint, p_date date)
returns jsonb language plpgsql security definer set search_path = public as $$
begin return rb_shop_do_dispatch(p_id, p_date, rb_require('shop.edit', 'dispatch online orders')); end $$;

create or replace function rb_shop_cash_received(p_id bigint, p_mode text, p_date date, p_ref text)
returns void language plpgsql security definer set search_path = public as $$
begin perform rb_shop_do_cash(p_id, p_mode, p_date, p_ref, rb_require('shop.edit', 'record cash on delivery')); end $$;

create or replace function rb_shop_cancel(p_id bigint, p_reason text)
returns text language plpgsql security definer set search_path = public as $$
begin return rb_shop_do_cancel(p_id, p_reason, rb_require('shop.edit', 'cancel online orders')); end $$;

-- Orders, newest first. p_status: 'open' (still to do), 'all', or one status.
create or replace function rb_shop_orders(p_from date, p_to date, p_status text default 'open')
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('shop.view', 'see online orders');
begin
  perform rb_shop_expire();
  return coalesce((select jsonb_agg(x order by x.placed_at desc) from (
    select o.id, o.order_no, o.token, o.placed_at, o.order_date, o.cust_name, o.cust_phone, o.cust_address, o.pin_code, o.cust_note, o.fulfil,
           o.pay_method, o.status, o.hold_until, o.goods_paise, o.delivery_paise, o.gst_paise, o.total_paise, o.with_gst,
           o.prices_incl_gst, o.upi_ref, o.upi_ref_at, o.paid_at, o.cancel_reason, o.staff_note, o.is_demo, o.sale_id,
           (select invoice_no from sales where id = o.sale_id) invoice_no,
           (select receipt_no from customer_receipts where id = o.receipt_id) receipt_no,
           (select receipt_no from customer_receipts where id = o.cash_receipt_id) cash_receipt_no,
           (select string_agg(l.packs || ' × ' || l.description, '; ' order by l.line_no) from shop_order_lines l where l.order_id = o.id) items,
           (select jsonb_agg(jsonb_build_object('description', l.description, 'packs', l.packs, 'rate_paise', l.rate_paise,
                                                'amount_paise', l.amount_paise, 'gst_paise', l.gst_paise) order by l.line_no)
            from shop_order_lines l where l.order_id = o.id) lines
    from shop_orders o
    where case when coalesce(p_status, 'open') = 'open' then o.status in ('placed', 'payment_check', 'paid', 'cod', 'packed', 'dispatched')
               when p_status = 'all' then o.order_date between coalesce(p_from, '2000-01-01') and coalesce(p_to, '2999-12-31')
               else o.status = p_status and o.order_date between coalesce(p_from, '2000-01-01') and coalesce(p_to, '2999-12-31') end
    limit 2000) x), '[]'::jsonb);
end $$;

-- Every finished-goods pack, with its shop settings and Free / On hold / Total.
create or replace function rb_shop_products()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_me uuid;
begin
  if not (rb_has('shop.view') or rb_has('stock.view')) then raise exception 'You do not have the right to see online shop products.'; end if;
  perform rb_shop_expire();
  return coalesce((select jsonb_agg(jsonb_build_object(
      'pack_id', pp.id, 'item_id', i.id, 'code', i.code, 'name', i.name, 'pack', pt.name, 'is_demo', pp.is_demo,
      'active', pp.is_active and i.is_active, 'price_paise', rb_sal_list_price(i.id, pp.id, 'online'),
      'hsn_ok', i.hsn_code is not null and i.gst_rate is not null,
      'visible', coalesce(sp.visible, false), 'cod_allowed', coalesce(sp.cod_allowed, false), 'description', sp.description,
      'has_photo', sp.photo is not null, 'photo', sp.photo, 'sort', coalesce(sp.sort, 100),
      'total', rb_shop_on_hand(pp.id), 'held', rb_shop_held(pp.id), 'free', rb_shop_free(pp.id))
      order by coalesce(sp.sort, 100), i.name, pp.net_qty)
    from product_packs pp join items i on i.id = pp.item_id join pack_types pt on pt.id = pp.pack_type_id
    left join shop_products sp on sp.pack_id = pp.id
    where i.kind = 'finished'), '[]'::jsonb);
end $$;

-- Packs held by online orders, for the Stock screen.
create or replace function rb_shop_holds()
returns table (pack_id int, held bigint) language plpgsql security definer set search_path = public as $$
begin
  if not (rb_has('shop.view') or rb_has('stock.view')) then raise exception 'You do not have the right to see stock.'; end if;
  perform rb_shop_expire();
  return query select l.pack_id, sum(l.packs)::bigint from shop_order_lines l join shop_orders o on o.id = l.order_id
    where o.status in ('payment_check', 'paid', 'cod', 'packed') or (o.status = 'placed' and o.hold_until > now())
    group by l.pack_id;
end $$;

-- p: pack_id, visible, cod_allowed, description, sort, photo (a data:image link; '' removes it; left out keeps it)
create or replace function rb_shop_save_product(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.shop_setup', 'choose the products on the online shop'); v_pp product_packs; v_it items;
begin
  select * into v_pp from product_packs where id = rb_int(p, 'pack_id');
  select * into v_it from items where id = v_pp.item_id;
  if v_pp.id is null or v_it.kind <> 'finished' then raise exception 'Only finished-goods packs can go on the shop.'; end if;
  if coalesce((p->>'visible')::boolean, false) and rb_sal_list_price(v_it.id, v_pp.id, 'online') is null then
    raise exception '% has no online or retail price. Add it in Masters → Packs and prices first.', v_it.name;
  end if;
  insert into shop_products (pack_id, visible, cod_allowed, description, photo, sort, updated_at, updated_by, is_demo)
  values (v_pp.id, coalesce((p->>'visible')::boolean, false), coalesce((p->>'cod_allowed')::boolean, false),
          left(rb_txt(p, 'description'), 300), nullif(p->>'photo', ''), coalesce(rb_int(p, 'sort')::int, 100), now(), v_me, v_pp.is_demo)
  on conflict (pack_id) do update set visible = excluded.visible, cod_allowed = excluded.cod_allowed,
    description = excluded.description, sort = excluded.sort, updated_at = now(), updated_by = v_me,
    photo = case when p ? 'photo' then excluded.photo else shop_products.photo end;
  perform rb_audit_write('SHOP_PRODUCT', 'shop_products', v_pp.id::text, null, p - 'photo', null);
end $$;

-- The shop settings, delivery areas and staff categories, for the screen.
create or replace function rb_shop_settings()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('shop.view', 'see the online shop settings'); s app_settings;
begin
  select * into s from app_settings where id = 1;
  return jsonb_build_object('shop_open', s.shop_open, 'shop_hold_minutes', s.shop_hold_minutes, 'shop_upi_id', s.shop_upi_id,
    'shop_upi_name', s.shop_upi_name, 'shop_pay_upi', s.shop_pay_upi, 'shop_pay_cod', s.shop_pay_cod, 'shop_pickup', s.shop_pickup,
    'shop_pickup_address', s.shop_pickup_address, 'shop_delivery', s.shop_delivery, 'shop_note', s.shop_note, 'shop_phone', s.shop_phone,
    'shop_max_unpaid', s.shop_max_unpaid, 'shop_alert_categories', to_jsonb(s.shop_alert_categories),
    'with_gst', rb_pur_gst_claimable(current_date),
    'upi_accounts', coalesce((select jsonb_agg(upi_id) from money_accounts where upi_id is not null and is_active), '[]'::jsonb),
    'categories', (select jsonb_agg(jsonb_build_object('id', id, 'name', name) order by id) from user_categories),
    'areas', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'pin_code', pin_code, 'area_name', area_name,
                         'charge_paise', charge_paise, 'is_active', is_active, 'is_demo', is_demo) order by pin_code = '*', pin_code)
                       from shop_delivery_areas), '[]'::jsonb));
end $$;

create or replace function rb_shop_save_settings(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.shop_setup', 'change the online shop settings'); v_upi text := lower(rb_txt(p, 'shop_upi_id'));
begin
  if v_upi is not null and v_upi !~ '^[a-z0-9._-]{2,99}@[a-z][a-z0-9.-]{1,60}$' then
    raise exception 'That does not look like a UPI ID (it is like ruchibuds@okaxis).';
  end if;
  if coalesce((p->>'shop_hold_minutes')::int, 30) not between 5 and 1440 then
    raise exception 'Hold unpaid orders for 5 to 1440 minutes.';
  end if;
  update app_settings set
    shop_open = coalesce((p->>'shop_open')::boolean, shop_open),
    shop_hold_minutes = coalesce((p->>'shop_hold_minutes')::int, shop_hold_minutes),
    shop_upi_id = v_upi, shop_upi_name = rb_txt(p, 'shop_upi_name'),
    shop_pay_upi = coalesce((p->>'shop_pay_upi')::boolean, shop_pay_upi),
    shop_pay_cod = coalesce((p->>'shop_pay_cod')::boolean, shop_pay_cod),
    shop_pickup = coalesce((p->>'shop_pickup')::boolean, shop_pickup),
    shop_pickup_address = rb_txt(p, 'shop_pickup_address'),
    shop_delivery = coalesce((p->>'shop_delivery')::boolean, shop_delivery),
    shop_note = left(rb_txt(p, 'shop_note'), 500), shop_phone = rb_txt(p, 'shop_phone'),
    shop_max_unpaid = greatest(1, least(20, coalesce((p->>'shop_max_unpaid')::int, shop_max_unpaid))),
    shop_alert_categories = coalesce((select array_agg(distinct x::smallint) from jsonb_array_elements_text(p->'shop_alert_categories') x
                                      where exists (select 1 from user_categories c where c.id = x::smallint)),
                                     case when p ? 'shop_alert_categories' then '{}'::smallint[] else shop_alert_categories end),
    updated_at = now(), updated_by = v_me
  where id = 1;
  if (select shop_open and not shop_pickup and not shop_delivery from app_settings where id = 1) then
    raise exception 'Choose delivery, pickup or both.';
  end if;
  if (select shop_open and not (shop_pay_upi and shop_upi_id is not null) and not shop_pay_cod from app_settings where id = 1) then
    raise exception 'Choose a way to pay: UPI (with the UPI ID) or cash on delivery.';
  end if;
  perform rb_audit_write('SHOP_SETTINGS', 'app_settings', '1', null, p, null);
end $$;

-- p: id (blank = new), pin_code ('*' = every other PIN), area_name, charge_paise, is_active
create or replace function rb_shop_save_area(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.shop_setup', 'set delivery charges'); v_pin text := trim(coalesce(p->>'pin_code', ''));
begin
  if v_pin <> '*' and v_pin !~ '^[1-9][0-9]{5}$' then raise exception 'Enter a 6-digit PIN code, or * for every other PIN code.'; end if;
  if coalesce(rb_int(p, 'charge_paise'), -1) < 0 then raise exception 'Enter the delivery charge (0 for free delivery).'; end if;
  if exists (select 1 from shop_delivery_areas where pin_code = v_pin and id is distinct from rb_int(p, 'id')::int) then
    raise exception 'PIN code % is already in the list.', v_pin;
  end if;
  if rb_int(p, 'id') is null then
    insert into shop_delivery_areas (pin_code, area_name, charge_paise, is_active, updated_at, updated_by)
    values (v_pin, rb_txt(p, 'area_name'), rb_int(p, 'charge_paise'), coalesce((p->>'is_active')::boolean, true), now(), v_me);
  else
    update shop_delivery_areas set pin_code = v_pin, area_name = rb_txt(p, 'area_name'), charge_paise = rb_int(p, 'charge_paise'),
           is_active = coalesce((p->>'is_active')::boolean, true), updated_at = now(), updated_by = v_me
    where id = rb_int(p, 'id');
  end if;
end $$;

create or replace function rb_shop_delete_area(p_id int)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.shop_setup', 'set delivery charges');
begin
  delete from shop_delivery_areas where id = p_id;
end $$;

-- The online orders report: orders, value, paid by UPI, COD, cancelled,
-- by day and by product.
create or replace function rb_shop_report(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('shop.view', 'see the online orders report');
begin
  perform rb_shop_expire();
  return jsonb_build_object(
    'totals', (select jsonb_build_object(
        'orders', count(*) filter (where status not in ('cancelled', 'expired')),
        'value_paise', coalesce(sum(total_paise) filter (where status not in ('cancelled', 'expired')), 0),
        'upi_orders', count(*) filter (where pay_method = 'upi' and receipt_id is not null and status <> 'cancelled'),
        'upi_paise', coalesce(sum(total_paise) filter (where pay_method = 'upi' and receipt_id is not null and status <> 'cancelled'), 0),
        'cod_orders', count(*) filter (where pay_method = 'cod' and status not in ('cancelled', 'expired')),
        'cod_paise', coalesce(sum(total_paise) filter (where pay_method = 'cod' and status not in ('cancelled', 'expired')), 0),
        'cancelled', count(*) filter (where status = 'cancelled'),
        'cancelled_paise', coalesce(sum(total_paise) filter (where status = 'cancelled'), 0),
        'expired', count(*) filter (where status = 'expired'),
        'invoiced', count(*) filter (where sale_id is not null))
      from shop_orders where order_date between p_from and p_to),
    'by_day', coalesce((select jsonb_agg(d order by d.day) from (
        select order_date as day,
               count(*) filter (where status not in ('cancelled', 'expired')) orders,
               coalesce(sum(total_paise) filter (where status not in ('cancelled', 'expired')), 0) value_paise,
               coalesce(sum(total_paise) filter (where pay_method = 'upi' and receipt_id is not null and status <> 'cancelled'), 0) upi_paise,
               coalesce(sum(total_paise) filter (where pay_method = 'cod' and status not in ('cancelled', 'expired')), 0) cod_paise,
               count(*) filter (where status = 'cancelled') cancelled,
               count(*) filter (where status = 'expired') expired
        from shop_orders where order_date between p_from and p_to group by order_date) d), '[]'::jsonb),
    'by_product', coalesce((select jsonb_agg(x order by x.value_paise desc) from (
        select l.description product, sum(l.packs) packs, sum(l.amount_paise) value_paise, count(distinct o.id) orders,
               bool_or(l.is_demo) is_demo
        from shop_order_lines l join shop_orders o on o.id = l.order_id
        where o.order_date between p_from and p_to and o.status not in ('cancelled', 'expired')
        group by l.description) x), '[]'::jsonb));
end $$;

-- For the home screen: what is waiting, and the newest alert for this person.
create or replace function rb_shop_my_alerts()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_current_user_id(); v_cat smallint;
begin
  if v_me is null or not rb_has('shop.view') then return null; end if;
  perform rb_shop_expire();
  select category_id into v_cat from app_users where id = v_me;
  return jsonb_build_object(
    'to_check', (select count(*) from shop_orders where status = 'payment_check'),
    'to_pack', (select count(*) from shop_orders where status in ('paid', 'cod')),
    'to_dispatch', (select count(*) from shop_orders where status = 'packed'),
    'cash_due', (select count(*) from shop_orders where status = 'dispatched'),
    'alerted', v_cat in (select unnest(shop_alert_categories) from app_settings where id = 1),
    'last_id', (select max(id) from shop_alerts),
    'last_message', (select message from shop_alerts order by id desc limit 1));
end $$;

-- For the Apps Script (every 5 minutes): alerts not yet emailed, and the
-- staff to email (active users in the categories chosen in Settings).
create or replace function rb_shop_pending_alerts()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'Only the Apps Script sends shop alerts.'; end if;
  perform rb_shop_expire();
  return jsonb_build_object(
    'to', coalesce((select jsonb_agg(distinct u.email) from app_users u
                    where u.status = 'active' and u.email is not null
                      and u.category_id in (select unnest(shop_alert_categories) from app_settings where id = 1)), '[]'::jsonb),
    'firm_name', (select firm_name from app_settings where id = 1),
    'alerts', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'at', a.at, 'kind', a.kind, 'message', a.message,
                          'order_no', o.order_no, 'is_demo', a.is_demo) order by a.id)
                        from shop_alerts a left join shop_orders o on o.id = a.order_id
                        where a.emailed_at is null and a.at > now() - interval '1 day'), '[]'::jsonb));
end $$;

create or replace function rb_shop_alerts_emailed(p_ids bigint[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'Only the Apps Script sends shop alerts.'; end if;
  update shop_alerts set emailed_at = now() where id = any (p_ids);
  -- Old alerts that were never emailed (no categories chosen) are let go.
  update shop_alerts set emailed_at = now() where emailed_at is null and at <= now() - interval '1 day';
end $$;

-- ---------------------------------------------------------------------
-- 7. Row-level security and who may call what
-- ---------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array['shop_products', 'shop_delivery_areas', 'shop_orders', 'shop_order_lines', 'shop_alerts'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon, authenticated', t);
    execute format('grant all on %I to service_role', t);
    execute format('drop policy if exists rb_read on %I', t);
  end loop;
end $$;
-- The screens read through the rb_shop_ functions, so nobody reads these tables directly.
revoke all on all sequences in schema public from anon, authenticated;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p
           where p.pronamespace = 'public'::regnamespace and p.proname like 'rb\_shop\_%' loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;
end $$;
-- The shop page (anyone, no sign-in).
grant execute on function rb_shop_catalogue(), rb_shop_place(jsonb), rb_shop_order(text), rb_shop_submit_ref(text, text),
  rb_shop_public_cancel(text) to anon, authenticated;
-- The staff screen.
grant execute on function rb_shop_mark_paid(bigint, text, date), rb_shop_payment_not_found(bigint),
  rb_shop_set_delivery(bigint, bigint), rb_shop_pack(bigint), rb_shop_dispatch(bigint, date),
  rb_shop_cash_received(bigint, text, date, text), rb_shop_cancel(bigint, text), rb_shop_orders(date, date, text),
  rb_shop_products(), rb_shop_holds(), rb_shop_save_product(jsonb), rb_shop_settings(), rb_shop_save_settings(jsonb),
  rb_shop_save_area(jsonb), rb_shop_delete_area(int), rb_shop_report(date, date), rb_shop_my_alerts()
  to authenticated;

-- ---------------------------------------------------------------------
-- 8. DEMO data: four DEMO packs on the shop, two delivery charges, and
--    four orders (one waiting for the UPI check, one paid and ready to
--    pack, one cash on delivery, one cancelled). Only added while the
--    app is in training mode.
-- ---------------------------------------------------------------------

do $$
declare
  v_acc uuid := (select id from app_users where email = 'demo.accounts@example.com');
  v_mgr uuid := coalesce((select id from app_users where email = 'demo.manager1@example.com'), v_acc);
  pk jsonb; x jsonb; v_id bigint; v_open boolean;
begin
  if not (select training_mode from app_settings where id = 1) or exists (select 1 from shop_orders where is_demo)
     or not exists (select 1 from product_packs where is_demo) or v_mgr is null then
    return;
  end if;
  select jsonb_object_agg(i.code || '/' || pt.code, pp.id) into pk
  from product_packs pp join items i on i.id = pp.item_id join pack_types pt on pt.id = pp.pack_type_id where pp.is_demo;
  insert into shop_products (pack_id, visible, cod_allowed, description, sort, is_demo)
  select (pk->>k)::int, true, c, d, s, true from (values
    ('D-FG01/D-PT1', true,  'Seer fish in gingelly oil, Kerala style (DEMO)', 10),
    ('D-FG02/D-PT1', true,  'Country chicken, slow cooked (DEMO)', 20),
    ('D-FG03/D-PT1', false, 'Smoked pork, Kodava style (DEMO)', 30),
    ('D-FG04/D-PT4', true,  'Sun-dried Kashmiri chilli, stone ground (DEMO)', 40)) v(k, c, d, s)
  where pk ? k
  on conflict (pack_id) do nothing;
  insert into shop_delivery_areas (pin_code, area_name, charge_paise, is_demo) values
    ('682001', 'Kochi (DEMO)', 4000, true), ('*', 'Anywhere else (DEMO)', 8000, true)
  on conflict (pin_code) do nothing;

  -- The shop must be open to take the DEMO orders.
  select shop_open into v_open from app_settings where id = 1;
  update app_settings set shop_open = true, shop_upi_id = coalesce(shop_upi_id, 'ruchibuds.demo@okaxis'),
         shop_pickup_address = coalesce(shop_pickup_address, 'Ruchi Buds kitchen (DEMO address)') where id = 1;

  -- 1. Paid by UPI, waiting for the staff to check the reference.
  x := rb_shop_place(jsonb_build_object('name', 'Meera Nair (DEMO)', 'phone', '9800000101', 'fulfil', 'delivery',
    'address', '12 Marine Drive (DEMO)', 'pin_code', '682001', 'pay_method', 'upi',
    'lines', jsonb_build_array(jsonb_build_object('pack_id', pk->'D-FG01/D-PT1', 'packs', 2))));
  perform rb_shop_submit_ref(x->>'token', '633012345678');
  -- 2. Paid by UPI and checked: ready to pack.
  x := rb_shop_place(jsonb_build_object('name', 'Rahul Menon (DEMO)', 'phone', '9800000102', 'fulfil', 'pickup',
    'pay_method', 'upi', 'lines', jsonb_build_array(jsonb_build_object('pack_id', pk->'D-FG02/D-PT1', 'packs', 1),
      jsonb_build_object('pack_id', pk->'D-FG04/D-PT4', 'packs', 1))));
  perform rb_shop_submit_ref(x->>'token', '633012349999');
  select id into v_id from shop_orders where token = x->>'token';
  perform rb_shop_do_paid(v_id, null, current_date, v_acc);
  -- 3. Cash on delivery.
  perform rb_shop_place(jsonb_build_object('name', 'Fathima K (DEMO)', 'phone', '9800000103', 'fulfil', 'delivery',
    'address', 'Near the church, Thrissur (DEMO)', 'pin_code', '680001', 'pay_method', 'cod',
    'lines', jsonb_build_array(jsonb_build_object('pack_id', pk->'D-FG04/D-PT4', 'packs', 2))));
  -- 4. Cancelled by the staff.
  x := rb_shop_place(jsonb_build_object('name', 'Arjun (DEMO)', 'phone', '9800000104', 'fulfil', 'pickup', 'pay_method', 'upi',
    'lines', jsonb_build_array(jsonb_build_object('pack_id', pk->'D-FG01/D-PT1', 'packs', 1))));
  select id into v_id from shop_orders where token = x->>'token';
  perform rb_shop_do_cancel(v_id, 'Customer called to cancel (DEMO)', v_mgr);
  update app_settings set shop_open = v_open where id = 1;
end $$;

-- End of 10_shop.sql
