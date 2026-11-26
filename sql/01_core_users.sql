-- =====================================================================
-- RUCHI BUDS APP · Module 1: Core and users
-- File: 01_core_users.sql · Version 1.0 · 26-Nov-2026
--
-- What this file sets up:
--   Firm settings, user categories (roles), the screen x action tick
--   grid, special rights, per-user overrides, logins, password resets
--   and unlocks, learning phase, document numbering, the audit log,
--   demo-data and go-live helpers, and the backup / keep-awake support.
--
-- How to run: Supabase -> SQL Editor -> New query -> paste this whole
-- file -> Run. It is safe to run again; nothing is lost on a re-run.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------

-- One row of firm-wide settings.
create table if not exists app_settings (
  id                      int primary key default 1 check (id = 1),
  entity_code             text not null default 'E002',
  currency                text not null default 'INR',
  firm_name               text not null default 'Ruchi Buds',
  legal_form              text not null default 'Partnership'
                          check (legal_form in ('Partnership', 'LLP')),
  firm_reg_no             text,
  llpin                   text,
  fssai_no                text default '21326126000762',
  gstin                   text,
  state_code              text,
  address                 text,
  phone                   text,
  email                   text default 'info.ruchibuds@gmail.com',
  fy_start_month          int not null default 4,
  -- Profit-sharing ratio as weights, e.g. 1 : 1 : 1 = one third each.
  partners                jsonb not null default
    '[{"name":"Partner 1","weight":1},{"name":"Partner 2","weight":1},{"name":"Partner 3","weight":1}]',
  trader_required_fields  text[] not null default '{}',
  direct_purchase_approval_limit_paise bigint,
  failed_login_limit      int not null default 5 check (failed_login_limit between 3 and 20),
  training_mode           boolean not null default true,
  go_live_date            date,
  wordmark_url            text,
  updated_at              timestamptz,
  updated_by              uuid
);
insert into app_settings (id) values (1) on conflict (id) do nothing;

-- Screens of the app. Later modules switch "available" on as they ship.
create table if not exists screens (
  code       text primary key,
  name       text not null,
  module     int not null,
  sort       int not null,
  in_menu    boolean not null default true,
  available  boolean not null default false,
  icon       text
);

-- Special rights that are not tied to a single screen.
create table if not exists powers (
  code        text primary key,
  name        text not null,
  description text not null,
  sort        int not null
);

-- Every tickable permission: "<screen>.<action>" or "power.<code>".
create table if not exists permissions (
  code        text primary key,
  kind        text not null check (kind in ('screen', 'power')),
  screen_code text references screens(code) on delete cascade,
  action      text,
  power_code  text references powers(code) on delete cascade,
  sort        int not null
);

-- User categories (Director, FC, ... and any added later).
create table if not exists user_categories (
  id           smallserial primary key,
  name         text not null unique,
  template     text not null check (template in
               ('Director','FC','Accountant','Manager','AR','AP','Sales','Staff')),
  is_protected boolean not null default false,
  description  text,
  is_demo      boolean not null default false,
  created_at   timestamptz not null default now(),
  created_by   uuid,
  updated_at   timestamptz,
  updated_by   uuid
);

-- The tick grid: a row here means "this category has this permission".
create table if not exists category_access (
  category_id smallint not null references user_categories(id) on delete cascade,
  perm        text not null references permissions(code) on delete cascade,
  changed_at  timestamptz not null default now(),
  changed_by  uuid,
  primary key (category_id, perm)
);

-- People who can use the app.
create table if not exists app_users (
  id                   uuid primary key default gen_random_uuid(),
  auth_id              uuid unique,
  email                text not null,
  full_name            text not null,
  short_name           text,
  phone                text,
  category_id          smallint not null references user_categories(id),
  status               text not null default 'invited'
                       check (status in ('invited','active','locked','inactive')),
  learning_phase_end   date,
  must_change_password boolean not null default false,
  failed_logins        int not null default 0,
  locked_at            timestamptz,
  locked_reason        text,
  last_login_at        timestamptz,
  is_demo              boolean not null default false,
  created_at           timestamptz not null default now(),
  created_by           uuid,
  updated_at           timestamptz,
  updated_by           uuid
);
create unique index if not exists app_users_email_key on app_users (lower(email));

-- Per-user ticks that override the category: allowed = true adds, false removes.
create table if not exists user_access_overrides (
  user_id    uuid not null references app_users(id) on delete cascade,
  perm       text not null references permissions(code) on delete cascade,
  allowed    boolean not null,
  changed_at timestamptz not null default now(),
  changed_by uuid,
  primary key (user_id, perm)
);

-- Password resets for Director / FC accounts wait here for a second approver.
create table if not exists password_reset_requests (
  id                 bigserial primary key,
  target_user_id     uuid not null references app_users(id) on delete cascade,
  requested_by       uuid not null references app_users(id),
  requested_at       timestamptz not null default now(),
  temp_password_hash text,
  status             text not null default 'pending'
                     check (status in ('pending','approved','rejected','cancelled')),
  decided_by         uuid references app_users(id),
  decided_at         timestamptz
);

-- Running document numbers (PO, GRN, PRP, PRD, Inv, ORD, DEMO ...).
-- The number never restarts; only the YYMM part follows the document date.
create table if not exists doc_counters (
  series  text primary key,
  last_no bigint not null default 0
);

-- Who did what, and when. Rows are never edited or deleted by the app.
create table if not exists audit_log (
  id          bigserial primary key,
  at          timestamptz not null default now(),
  user_id     uuid,
  user_name   text,
  action      text not null,
  table_name  text,
  record_id   text,
  old_data    jsonb,
  new_data    jsonb,
  note        text
);
create index if not exists audit_log_at_idx on audit_log (at desc);
create index if not exists audit_log_table_idx on audit_log (table_name, record_id);

-- Nightly backups, manual backups and keep-awake pings.
create table if not exists backup_log (
  id         bigserial primary key,
  at         timestamptz not null default now(),
  kind       text not null check (kind in ('nightly','manual','ping','restore')),
  status     text not null check (status in ('ok','failed')),
  tables     int,
  rows       bigint,
  detail     text
);
create index if not exists backup_log_at_idx on backup_log (at desc);

-- ---------------------------------------------------------------------
-- 2. Catalogue: screens, actions, special rights
-- ---------------------------------------------------------------------

insert into screens (code, name, module, sort, in_menu, available, icon) values
  ('purchases',  'Purchases',              3,  10, true,  false, 'cart'),
  ('suppliers',  'Suppliers',              3,  20, true,  false, 'truck'),
  ('stock',      'Stock',                  4,  30, true,  false, 'boxes'),
  ('production', 'Production',             4,  40, true,  false, 'pot'),
  ('sales',      'Sales',                  5,  50, true,  false, 'tag'),
  ('invoices',   'Invoices',               5,  60, true,  false, 'receipt'),
  ('customers',  'Customers',              5,  70, true,  false, 'people'),
  ('receipts',   'Customer receipts',      5,  80, true,  false, 'coins'),
  ('cash_bank',  'Cash, bank and expenses',6,  90, true,  false, 'wallet'),
  ('loans',      'Loans and leases',       7, 100, true,  false, 'bank'),
  ('masters',    'Masters',                2, 110, true,  false, 'list'),
  ('accounts',   'Accounts and journals',  2, 120, true,  false, 'book'),
  ('reports',    'Reports',                8, 130, true,  false, 'chart'),
  ('shop',       'Online shop orders',    10, 140, true,  false, 'bag'),
  ('users',      'Users',                  1, 150, true,  true,  'user'),
  ('settings',   'Settings',               1, 160, true,  true,  'gear'),
  ('audit',      'Audit log',              1, 170, true,  true,  'clock')
on conflict (code) do update set
  name = excluded.name, module = excluded.module, sort = excluded.sort,
  in_menu = excluded.in_menu, icon = excluded.icon,
  available = screens.available or excluded.available;

insert into powers (code, name, description, sort) values
  ('manage_access',   'Manage access',         'Create, rename and remove categories, tick the access grid, give per-user ticks and set learning-phase dates', 10),
  ('reset_passwords', 'Reset passwords',       'Give a user a temporary password', 20),
  ('unlock_users',    'Unlock users',          'Unlock a user locked after too many wrong passwords', 30),
  ('approve_own',     'Approve own entries',   'Approve entries this person entered themselves', 40),
  ('reverse_entries', 'Reverse posted entries','Reverse a posted entry', 50),
  ('refunds',         'Refunds',               'Process customer refunds', 60),
  ('lock_periods',    'Lock months',           'Lock a month once it is closed', 70),
  ('go_live',         'Go live',               'Switch off training mode and set the go-live date', 80),
  ('remove_demo',     'Remove demo data',      'Delete every DEMO record in one step', 90),
  ('backup_now',      'Backup now',            'Download a full backup from Settings', 100),
  ('see_totals',      'See money totals',      'See amounts and totals on sales screens (Staff do not by default)', 110)
on conflict (code) do update set
  name = excluded.name, description = excluded.description, sort = excluded.sort;

insert into permissions (code, kind, screen_code, action, sort)
select s.code || '.' || a.action, 'screen', s.code, a.action, s.sort * 10 + a.n
from screens s
cross join (values ('view',1),('add',2),('edit',3),('approve',4),('delete',5),('margin',6)) as a(action, n)
on conflict (code) do nothing;

insert into permissions (code, kind, power_code, sort)
select 'power.' || p.code, 'power', p.code, 10000 + p.sort from powers p
on conflict (code) do nothing;

-- The eight starting categories. Director and FC are protected: they
-- always have every tick, so nobody can lock the firm out of its own app.
insert into user_categories (name, template, is_protected, description) values
  ('Director',             'Director',   true,  'Everything; grants access and resets passwords'),
  ('Financial Controller', 'FC',         true,  'Everything; grants access and resets passwords'),
  ('Accountant',           'Accountant', false, 'All accounting screens, refunds, creates users, unlocks passwords'),
  ('Manager',              'Manager',    false, 'Operations: purchases, stock, production, sales'),
  ('AR',                   'AR',         false, 'Customers, receipts, customer statements'),
  ('AP',                   'AP',         false, 'Suppliers, purchases, payments'),
  ('Sales',                'Sales',      false, 'Sales, returns, invoices'),
  ('Staff',                'Staff',      false, 'Retail counter sales, without money totals')
on conflict (name) do nothing;

-- Default ticks for each template (used when a category is first created).
create or replace function rb_template_perms(p_template text)
returns setof text language sql immutable set search_path = public as $$
  with grid(template, screen, actions) as (values
    ('Accountant','purchases', '{view,add,edit,approve,margin}'::text[]),
    ('Accountant','suppliers', '{view,add,edit,approve,margin}'),
    ('Accountant','stock',     '{view,add,edit,approve,margin}'),
    ('Accountant','production','{view,add,edit,approve,margin}'),
    ('Accountant','sales',     '{view,add,edit,approve,margin}'),
    ('Accountant','invoices',  '{view,add,edit,approve,margin}'),
    ('Accountant','customers', '{view,add,edit,approve,margin}'),
    ('Accountant','receipts',  '{view,add,edit,approve,margin}'),
    ('Accountant','cash_bank', '{view,add,edit,approve,margin}'),
    ('Accountant','loans',     '{view,add,edit,approve,margin}'),
    ('Accountant','masters',   '{view,add,edit,approve,margin}'),
    ('Accountant','accounts',  '{view,add,edit,approve,margin}'),
    ('Accountant','reports',   '{view,margin}'),
    ('Accountant','shop',      '{view,add,edit,approve,margin}'),
    ('Accountant','users',     '{view,add,edit}'),
    ('Accountant','settings',  '{view}'),
    ('Accountant','audit',     '{view}'),
    ('Manager','purchases',    '{view,add,edit,approve}'),
    ('Manager','suppliers',    '{view,add,edit}'),
    ('Manager','stock',        '{view,add,edit,approve}'),
    ('Manager','production',   '{view,add,edit,approve}'),
    ('Manager','sales',        '{view,add,edit,approve}'),
    ('Manager','invoices',     '{view,add,edit}'),
    ('Manager','customers',    '{view,add,edit}'),
    ('Manager','masters',      '{view}'),
    ('Manager','shop',         '{view,add,edit}'),
    ('AR','customers',         '{view,add,edit}'),
    ('AR','receipts',          '{view,add,edit}'),
    ('AR','invoices',          '{view}'),
    ('AP','suppliers',         '{view,add,edit}'),
    ('AP','purchases',         '{view,add,edit}'),
    ('Sales','sales',          '{view,add,edit}'),
    ('Sales','invoices',       '{view,add,edit}'),
    ('Sales','customers',      '{view,add,edit}'),
    ('Sales','shop',           '{view,edit}'),
    ('Staff','sales',          '{view,add}'),
    ('Staff','customers',      '{view,add}')
  ), pw(template, powers) as (values
    ('Accountant', '{unlock_users,approve_own,reverse_entries,refunds,backup_now,see_totals}'::text[]),
    ('Manager',    '{see_totals}'),
    ('AR',         '{see_totals}'),
    ('AP',         '{see_totals}'),
    ('Sales',      '{see_totals}'),
    ('Staff',      '{}')
  )
  select code from permissions where p_template in ('Director','FC')
  union
  select g.screen || '.' || a from grid g, unnest(g.actions) a where g.template = p_template
  union
  select 'power.' || x from pw, unnest(pw.powers) x where pw.template = p_template
$$;

-- Give each starting category its default ticks, only the first time.
insert into category_access (category_id, perm)
select c.id, t.perm
from user_categories c
cross join lateral rb_template_perms(c.template) as t(perm)
where not exists (select 1 from category_access a where a.category_id = c.id)
on conflict do nothing;

-- ---------------------------------------------------------------------
-- 3. Who is signed in, and what may they do
-- ---------------------------------------------------------------------

-- The app_users row of the person signed in, only while their status is active.
create or replace function rb_current_user_id()
returns uuid language sql stable security definer set search_path = public as $$
  select id from app_users where auth_id = auth.uid() and status = 'active'
$$;

-- Every permission a user effectively has (category ticks plus overrides).
create or replace function rb_user_perms(p_user uuid)
returns setof text language sql stable security definer set search_path = public as $$
  select p.code
  from app_users u
  join user_categories c on c.id = u.category_id
  cross join permissions p
  left join user_access_overrides o on o.user_id = u.id and o.perm = p.code
  where u.id = p_user
    and case
          when c.is_protected then true
          when o.allowed is not null then o.allowed
          else exists (select 1 from category_access a
                       where a.category_id = u.category_id and a.perm = p.code)
        end
$$;

create or replace function rb_has(p_perm text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from rb_user_perms(rb_current_user_id()) x where x = p_perm)
$$;

create or replace function rb_user_has(p_user uuid, p_perm text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from rb_user_perms(p_user) x where x = p_perm)
$$;

-- Stop with a plain-English message unless the signed-in user has the permission.
create or replace function rb_require(p_perm text, p_what text)
returns uuid language plpgsql stable security definer set search_path = public as $$
declare v_me uuid := rb_current_user_id();
begin
  if v_me is null then
    raise exception 'You are not signed in, or your account is locked or switched off.';
  end if;
  if not rb_has(p_perm) then
    raise exception 'You do not have the right to %.', p_what;
  end if;
  return v_me;
end $$;

-- True while that user's learning phase is running (their posted entries may be hard-deleted).
create or replace function rb_in_learning_phase(p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select learning_phase_end >= current_date from app_users where id = p_user), false)
$$;

-- For later modules: may the signed-in user hard-delete an entry on this screen made by p_entered_by?
create or replace function rb_can_hard_delete(p_screen text, p_entered_by uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select rb_has(p_screen || '.delete') and rb_in_learning_phase(p_entered_by)
$$;

-- For later modules: may the signed-in user approve an entry made by p_entered_by?
create or replace function rb_can_approve(p_screen text, p_entered_by uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select rb_has(p_screen || '.approve')
     and (p_entered_by is distinct from rb_current_user_id() or rb_has('power.approve_own'))
$$;

-- For later modules: flags every new record should carry.
create or replace function rb_is_training()
returns boolean language sql stable security definer set search_path = public as $$
  select training_mode from app_settings where id = 1
$$;

-- Everything the screens need about the signed-in person, in one call.
create or replace function rb_my_profile()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  select jsonb_build_object(
    'id', u.id, 'email', u.email, 'full_name', u.full_name, 'short_name', u.short_name,
    'status', u.status, 'category', c.name, 'template', c.template,
    'must_change_password', u.must_change_password,
    'learning_phase_end', u.learning_phase_end,
    'permissions', coalesce((select jsonb_agg(x) from rb_user_perms(u.id) x), '[]'::jsonb),
    'settings', (select jsonb_build_object(
        'firm_name', s.firm_name, 'entity_code', s.entity_code, 'currency', s.currency,
        'legal_form', s.legal_form, 'training_mode', s.training_mode,
        'go_live_date', s.go_live_date) from app_settings s where s.id = 1))
  into v
  from app_users u join user_categories c on c.id = u.category_id
  where u.auth_id = auth.uid();
  return v;  -- null when this login was never invited
end $$;

-- Firm name and word mark for the login screen (readable before sign-in).
create or replace function rb_public_branding()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('firm_name', firm_name, 'wordmark_url', wordmark_url,
                            'training_mode', training_mode)
  from app_settings where id = 1
$$;

-- ---------------------------------------------------------------------
-- 4. Audit log
-- ---------------------------------------------------------------------

create or replace function rb_audit_write(p_action text, p_table text, p_record text,
                                          p_old jsonb, p_new jsonb, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_name text;
begin
  select id, coalesce(short_name, full_name) into v_id, v_name
  from app_users where auth_id = auth.uid();
  insert into audit_log (user_id, user_name, action, table_name, record_id, old_data, new_data, note)
  values (v_id, coalesce(v_name, 'system'), p_action, p_table, p_record, p_old, p_new, p_note);
end $$;

create or replace function rb_audit_trigger()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_old jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) - 'temp_password_hash' end;
  v_new jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) - 'temp_password_hash' end;
  v_rec text;
  v_noise text[] := array['last_login_at','failed_logins','updated_at','updated_by','changed_at','changed_by'];
begin
  -- Keep big images out of the log: store a short fingerprint instead.
  if v_old ? 'wordmark_url' and v_old->>'wordmark_url' is not null then
    v_old := jsonb_set(v_old, '{wordmark_url}', to_jsonb('image ' || left(md5(v_old->>'wordmark_url'), 8)));
  end if;
  if v_new ? 'wordmark_url' and v_new->>'wordmark_url' is not null then
    v_new := jsonb_set(v_new, '{wordmark_url}', to_jsonb('image ' || left(md5(v_new->>'wordmark_url'), 8)));
  end if;
  -- Skip updates that only touch housekeeping columns (logins are logged separately).
  if tg_op = 'UPDATE' and (v_old - v_noise) = (v_new - v_noise) then
    return new;
  end if;
  v_rec := coalesce(v_new, v_old) ->> 'id';
  if v_rec is null then
    v_rec := concat_ws('/', coalesce(v_new, v_old) ->> 'category_id',
                            coalesce(v_new, v_old) ->> 'user_id',
                            coalesce(v_new, v_old) ->> 'perm');
  end if;
  perform rb_audit_write(tg_op, tg_table_name, v_rec, v_old, v_new, null);
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array['app_settings','user_categories','category_access','app_users',
                           'user_access_overrides','password_reset_requests'] loop
    execute format('drop trigger if exists rb_audit on %I', t);
    execute format('create trigger rb_audit after insert or update or delete on %I
                    for each row execute function rb_audit_trigger()', t);
  end loop;
end $$;

-- The audit log itself can only grow.
create or replace function rb_audit_protect()
returns trigger language plpgsql as $$
begin
  raise exception 'The audit log cannot be changed or deleted.';
end $$;
drop trigger if exists rb_audit_protect on audit_log;
create trigger rb_audit_protect before update or delete on audit_log
  for each row execute function rb_audit_protect();

-- ---------------------------------------------------------------------
-- 5. Logins: first-time set-up, failed attempts, password changes
-- ---------------------------------------------------------------------

-- Runs when someone creates a login. Only invited emails may do so.
create or replace function rb_on_auth_user_created()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_user app_users;
begin
  select * into v_user from app_users where lower(email) = lower(new.email);
  if v_user.id is null or v_user.status <> 'invited' then
    raise exception 'RB_NOT_INVITED: % has not been invited to the Ruchi Buds app.', new.email;
  end if;
  update app_users set auth_id = new.id, status = 'active', updated_at = now()
  where id = v_user.id;
  return new;
end $$;
drop trigger if exists rb_on_auth_user_created on auth.users;
create trigger rb_on_auth_user_created before insert on auth.users
  for each row execute function rb_on_auth_user_created();

-- Called by the login screen after a wrong password. Locks the account at the limit.
create or replace function rb_login_failed(p_email text)
returns void language plpgsql security definer set search_path = public as $$
declare v_user app_users; v_limit int;
begin
  select failed_login_limit into v_limit from app_settings where id = 1;
  update app_users set failed_logins = failed_logins + 1
  where lower(email) = lower(trim(p_email)) and status = 'active'
  returning * into v_user;
  if v_user.id is null then return; end if;
  perform rb_audit_write('LOGIN_FAILED', 'app_users', v_user.id::text, null, null,
                         'Wrong password, attempt ' || v_user.failed_logins);
  if v_user.failed_logins >= v_limit then
    update app_users set status = 'locked', locked_at = now(),
           locked_reason = 'Too many wrong passwords'
    where id = v_user.id;
  end if;
end $$;

-- Called by the app after a successful sign-in.
create or replace function rb_login_ok()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  update app_users set failed_logins = 0, last_login_at = now()
  where auth_id = auth.uid() and status = 'active'
  returning id into v_id;
  if v_id is not null then
    perform rb_audit_write('LOGIN', 'app_users', v_id::text, null, null, null);
  end if;
  return rb_my_profile();
end $$;

-- Called after the user has chosen a new password in the app.
create or replace function rb_password_changed()
returns void language plpgsql security definer set search_path = public as $$
begin
  update app_users set must_change_password = false, updated_at = now()
  where auth_id = auth.uid();
  perform rb_audit_write('PASSWORD_CHANGED', 'app_users',
    (select id::text from app_users where auth_id = auth.uid()), null, null, null);
end $$;

-- ---------------------------------------------------------------------
-- 6. Users
-- ---------------------------------------------------------------------

-- Nobody may hand out a category that has rights they do not have themselves.
create or replace function rb_assert_can_assign(p_category smallint)
returns void language plpgsql stable security definer set search_path = public as $$
declare v_missing text;
begin
  select string_agg(p.code, ', ') into v_missing
  from (select code from permissions p
        where exists (select 1 from user_categories c where c.id = p_category and c.is_protected)
           or exists (select 1 from category_access a where a.category_id = p_category and a.perm = p.code)) p
  where not rb_has(p.code);
  if v_missing is not null then
    raise exception 'You cannot give someone a category with more rights than your own (missing: %).', v_missing;
  end if;
end $$;

create or replace function rb_invite_user(p_email text, p_full_name text, p_short_name text,
  p_phone text, p_category smallint, p_learning_phase_end date default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('users.add', 'add users'); v_id uuid; v_auth uuid;
begin
  if coalesce(trim(p_email), '') = '' or position('@' in p_email) = 0 then
    raise exception 'Please enter a valid email address.';
  end if;
  if coalesce(trim(p_full_name), '') = '' then raise exception 'Please enter the person''s name.'; end if;
  if exists (select 1 from app_users where lower(email) = lower(trim(p_email))) then
    raise exception 'A user with the email % already exists.', p_email;
  end if;
  perform rb_assert_can_assign(p_category);
  if p_learning_phase_end is not null and not rb_has('power.manage_access') then
    raise exception 'Only a Director or FC can set the learning-phase date.';
  end if;
  insert into app_users (email, full_name, short_name, phone, category_id, learning_phase_end, created_by)
  values (lower(trim(p_email)), trim(p_full_name), nullif(trim(p_short_name), ''),
          nullif(trim(p_phone), ''), p_category, p_learning_phase_end, v_me)
  returning id into v_id;
  -- If a login with this email already exists (e.g. after a reset), link it now.
  select id into v_auth from auth.users where lower(email) = lower(trim(p_email));
  if v_auth is not null then
    update app_users set auth_id = v_auth, status = 'active' where id = v_id;
  end if;
  return v_id;
end $$;

create or replace function rb_update_user(p_user uuid, p_full_name text, p_short_name text,
  p_phone text, p_category smallint, p_learning_phase_end date)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('users.edit', 'change users'); v_old app_users;
begin
  select * into v_old from app_users where id = p_user;
  if v_old.id is null then raise exception 'User not found.'; end if;
  if p_category is distinct from v_old.category_id then
    if p_user = v_me then raise exception 'You cannot change your own category.'; end if;
    perform rb_assert_can_assign(v_old.category_id);  -- may not demote someone above you
    perform rb_assert_can_assign(p_category);
  end if;
  if p_learning_phase_end is distinct from v_old.learning_phase_end
     and not rb_has('power.manage_access') then
    raise exception 'Only a Director or FC can change the learning-phase date.';
  end if;
  update app_users set full_name = trim(p_full_name), short_name = nullif(trim(p_short_name), ''),
         phone = nullif(trim(p_phone), ''), category_id = p_category,
         learning_phase_end = p_learning_phase_end, updated_at = now(), updated_by = v_me
  where id = p_user;
end $$;

-- Switch a user off (left the firm) or back on.
create or replace function rb_set_user_active(p_user uuid, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('users.edit', 'switch users on or off'); v_u app_users;
begin
  select * into v_u from app_users where id = p_user;
  if v_u.id is null then raise exception 'User not found.'; end if;
  if p_user = v_me then raise exception 'You cannot switch off your own account.'; end if;
  perform rb_assert_can_assign(v_u.category_id);
  update app_users set
    status = case when p_active then case when auth_id is null then 'invited' else 'active' end
                  else 'inactive' end,
    updated_at = now(), updated_by = v_me
  where id = p_user;
end $$;

-- Delete a user who never signed in (e.g. a typo in the email).
create or replace function rb_delete_invite(p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('users.edit', 'remove invitations');
begin
  if not exists (select 1 from app_users where id = p_user and status = 'invited') then
    raise exception 'Only an invitation that was never used can be deleted. Switch the user off instead.';
  end if;
  delete from app_users where id = p_user;
end $$;

create or replace function rb_unlock_user(p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.unlock_users', 'unlock users');
begin
  update app_users set status = 'active', failed_logins = 0, locked_at = null,
         locked_reason = null, updated_at = now(), updated_by = v_me
  where id = p_user and status = 'locked';
  if not found then raise exception 'That user is not locked.'; end if;
end $$;

create or replace function rb_apply_password(p_user uuid, p_hash text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare v_auth uuid;
begin
  select auth_id into v_auth from app_users where id = p_user;
  if v_auth is null then raise exception 'This user has not set up a login yet.'; end if;
  update auth.users set encrypted_password = p_hash, updated_at = now() where id = v_auth;
  update app_users set must_change_password = true, failed_logins = 0,
         status = case when status = 'locked' then 'active' else status end,
         locked_at = null, locked_reason = null, updated_at = now()
  where id = p_user;
end $$;

-- Give a user a temporary password. They must choose their own at next sign-in.
-- A Director's or FC's account needs a second Director or FC to approve.
create or replace function rb_reset_password(p_user uuid, p_temp_password text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare
  v_me uuid := rb_require('power.reset_passwords', 'reset passwords');
  v_protected boolean;
  v_hash text;
begin
  if length(coalesce(p_temp_password, '')) < 8 then
    raise exception 'The temporary password must be at least 8 characters.';
  end if;
  if p_user = v_me then
    raise exception 'To change your own password use "Change my password" on the home screen.';
  end if;
  select c.is_protected into v_protected
  from app_users u join user_categories c on c.id = u.category_id where u.id = p_user;
  if v_protected is null then raise exception 'User not found.'; end if;
  v_hash := extensions.crypt(p_temp_password, extensions.gen_salt('bf'));
  if v_protected then
    update password_reset_requests set status = 'cancelled', decided_at = now(), decided_by = v_me
    where target_user_id = p_user and status = 'pending';
    insert into password_reset_requests (target_user_id, requested_by, temp_password_hash)
    values (p_user, v_me, v_hash);
    return 'pending';
  end if;
  perform rb_apply_password(p_user, v_hash);
  perform rb_audit_write('PASSWORD_RESET', 'app_users', p_user::text, null, null, null);
  return 'done';
end $$;

create or replace function rb_decide_password_reset(p_request bigint, p_approve boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare v_me uuid := rb_require('power.reset_passwords', 'approve password resets');
        v_r password_reset_requests;
begin
  select * into v_r from password_reset_requests where id = p_request and status = 'pending';
  if v_r.id is null then raise exception 'That request is no longer waiting.'; end if;
  if v_me in (v_r.requested_by, v_r.target_user_id) then
    raise exception 'A different Director or FC must approve this reset.';
  end if;
  update password_reset_requests
  set status = case when p_approve then 'approved' else 'rejected' end,
      decided_by = v_me, decided_at = now(), temp_password_hash = null
  where id = p_request;
  if p_approve then
    perform rb_apply_password(v_r.target_user_id, v_r.temp_password_hash);
    perform rb_audit_write('PASSWORD_RESET', 'app_users', v_r.target_user_id::text, null, null,
                           'Approved request ' || p_request);
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 7. Categories and the tick grid
-- ---------------------------------------------------------------------

create or replace function rb_create_category(p_name text, p_template text, p_description text default null)
returns smallint language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.manage_access', 'create categories'); v_id smallint;
begin
  if coalesce(trim(p_name), '') = '' then raise exception 'Please enter a name.'; end if;
  insert into user_categories (name, template, description, created_by)
  values (trim(p_name), p_template, p_description, v_me) returning id into v_id;
  insert into category_access (category_id, perm, changed_by)
  select v_id, t, v_me from rb_template_perms(p_template) t
  where p_template not in ('Director','FC');  -- copies of protected templates start from Accountant-level ticks
  if p_template in ('Director','FC') then
    insert into category_access (category_id, perm, changed_by)
    select v_id, code, v_me from permissions on conflict do nothing;
  end if;
  return v_id;
exception when unique_violation then
  raise exception 'A category called % already exists.', p_name;
end $$;

create or replace function rb_rename_category(p_category smallint, p_name text, p_description text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.manage_access', 'rename categories');
begin
  if coalesce(trim(p_name), '') = '' then raise exception 'Please enter a name.'; end if;
  update user_categories set name = trim(p_name), description = p_description,
         updated_at = now(), updated_by = v_me
  where id = p_category;
exception when unique_violation then
  raise exception 'A category called % already exists.', p_name;
end $$;

create or replace function rb_delete_category(p_category smallint)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.manage_access', 'remove categories');
begin
  if exists (select 1 from user_categories where id = p_category and is_protected) then
    raise exception 'The Director and Financial Controller categories cannot be removed.';
  end if;
  if exists (select 1 from app_users where category_id = p_category) then
    raise exception 'This category is still used by at least one user. Move them first.';
  end if;
  delete from user_categories where id = p_category;
end $$;

-- Tick or untick one box of a category's grid.
create or replace function rb_set_category_access(p_category smallint, p_perm text, p_allowed boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.manage_access', 'change the access grid');
begin
  if exists (select 1 from user_categories where id = p_category and is_protected) then
    raise exception 'Director and Financial Controller always have every tick, so the firm can never be locked out.';
  end if;
  if not exists (select 1 from permissions where code = p_perm) then
    raise exception 'Unknown permission %.', p_perm;
  end if;
  if p_allowed then
    insert into category_access (category_id, perm, changed_by) values (p_category, p_perm, v_me)
    on conflict do nothing;
  else
    delete from category_access where category_id = p_category and perm = p_perm;
  end if;
end $$;

-- Per-user tick: true = extra access, false = taken away, null = follow the category.
create or replace function rb_set_user_access(p_user uuid, p_perm text, p_allowed boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.manage_access', 'change a user''s access');
begin
  if p_user = v_me then raise exception 'You cannot change your own access.'; end if;
  if exists (select 1 from app_users u join user_categories c on c.id = u.category_id
             where u.id = p_user and c.is_protected) then
    raise exception 'Directors and the Financial Controller always have full access.';
  end if;
  if p_allowed is null then
    delete from user_access_overrides where user_id = p_user and perm = p_perm;
  else
    insert into user_access_overrides (user_id, perm, allowed, changed_by)
    values (p_user, p_perm, p_allowed, v_me)
    on conflict (user_id, perm) do update
      set allowed = excluded.allowed, changed_at = now(), changed_by = v_me;
  end if;
end $$;

-- What a given user can see, for the "Preview as this user" button.
create or replace function rb_preview_user_perms(p_user uuid)
returns setof text language plpgsql stable security definer set search_path = public as $$
begin
  perform rb_require('users.view', 'see users');
  return query select * from rb_user_perms(p_user);
end $$;

-- ---------------------------------------------------------------------
-- 8. Settings, training mode, go-live, demo data
-- ---------------------------------------------------------------------

create or replace function rb_save_settings(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('settings.edit', 'change settings');
begin
  update app_settings set
    firm_name   = coalesce(nullif(trim(p->>'firm_name'), ''), firm_name),
    legal_form  = coalesce(p->>'legal_form', legal_form),
    firm_reg_no = nullif(trim(p->>'firm_reg_no'), ''),
    llpin       = nullif(trim(p->>'llpin'), ''),
    fssai_no    = nullif(trim(p->>'fssai_no'), ''),
    gstin       = nullif(upper(trim(p->>'gstin')), ''),
    state_code  = nullif(trim(p->>'state_code'), ''),
    address     = nullif(trim(p->>'address'), ''),
    phone       = nullif(trim(p->>'phone'), ''),
    email       = nullif(trim(p->>'email'), ''),
    partners    = coalesce(p->'partners', partners),
    trader_required_fields = coalesce(
      (select array_agg(x) from jsonb_array_elements_text(p->'trader_required_fields') x),
      case when p ? 'trader_required_fields' then '{}'::text[] else trader_required_fields end),
    direct_purchase_approval_limit_paise = (p->>'direct_purchase_approval_limit_paise')::bigint,
    failed_login_limit = coalesce((p->>'failed_login_limit')::int, failed_login_limit),
    wordmark_url = case when p ? 'wordmark_url' then nullif(p->>'wordmark_url', '') else wordmark_url end,
    updated_at = now(), updated_by = v_me
  where id = 1;
  if exists (select 1 from app_settings, jsonb_array_elements(partners) e
             where id = 1 and coalesce((e->>'weight')::numeric, 0) <= 0) then
    raise exception 'Each partner''s share must be more than zero.';
  end if;
end $$;

-- Deletes every DEMO record in every table that has an is_demo column.
create or replace function rb_remove_demo_data(p_confirm text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := rb_require('power.remove_demo', 'remove demo data');
  v_tables text[]; t text; n bigint; v_total bigint := 0; v_progress boolean; v_left int;
  v_result jsonb := '{}';
begin
  if p_confirm is distinct from 'REMOVE DEMO' then
    raise exception 'Type REMOVE DEMO to confirm.';
  end if;
  select array_agg(table_name::text) into v_tables
  from information_schema.columns
  where table_schema = 'public' and column_name = 'is_demo';
  -- Tables refer to each other, so keep going round until nothing is left.
  for i in 1..10 loop
    v_progress := false; v_left := 0;
    foreach t in array v_tables loop
      begin
        execute format('delete from %I where is_demo', t);
        get diagnostics n = row_count;
        if n > 0 then
          v_progress := true; v_total := v_total + n;
          v_result := v_result || jsonb_build_object(t, coalesce((v_result->>t)::bigint, 0) + n);
        end if;
      exception when foreign_key_violation then
        v_left := v_left + 1;
      end;
    end loop;
    exit when v_left = 0 or not v_progress;
  end loop;
  if v_left > 0 then
    raise exception 'Some DEMO records are still used by real records and could not be removed.';
  end if;
  perform rb_audit_write('REMOVE_DEMO', null, null, null, v_result, v_total || ' records removed');
  return v_result;
end $$;

-- Go live: remove DEMO and training records, switch training mode off, set the date.
create or replace function rb_go_live(p_go_live date, p_confirm text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.go_live', 'set the go-live date'); t text;
begin
  if p_confirm is distinct from 'GO LIVE' then raise exception 'Type GO LIVE to confirm.'; end if;
  if p_go_live is null then raise exception 'Please choose the go-live date.'; end if;
  if not (select training_mode from app_settings where id = 1) then
    raise exception 'The app is already live.';
  end if;
  perform rb_remove_demo_data('REMOVE DEMO');
  for t in select table_name from information_schema.columns
           where table_schema = 'public' and column_name = 'is_training' loop
    execute format('delete from %I where is_training', t);
  end loop;
  update app_settings set training_mode = false, go_live_date = p_go_live,
         updated_at = now(), updated_by = v_me where id = 1;
end $$;

-- Next document number, e.g. rb_next_doc_no('PO', '2026-11-26') -> 'PO/2611/00001'.
-- One running number per series that never restarts; YYMM follows the document date.
create or replace function rb_next_doc_no(p_series text, p_doc_date date)
returns text language plpgsql security definer set search_path = public as $$
declare v_no bigint;
begin
  insert into doc_counters (series, last_no) values (p_series, 1)
  on conflict (series) do update set last_no = doc_counters.last_no + 1
  returning last_no into v_no;
  return p_series || '/' || to_char(p_doc_date, 'YYMM') || '/' || lpad(v_no::text, 5, '0');
end $$;

-- ---------------------------------------------------------------------
-- 9. Backup and keep-awake support (used by the Google Apps Script)
-- ---------------------------------------------------------------------

create or replace function rb_backup_tables()
returns setof text language plpgsql stable security definer set search_path = public as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    perform rb_require('power.backup_now', 'take a backup');
  end if;
  return query select table_name::text from information_schema.tables
               where table_schema = 'public' and table_type = 'BASE TABLE'
               order by table_name;
end $$;

-- One page of a table's rows as JSON, for backups (the Apps Script and "Backup now").
create or replace function rb_backup_rows(p_table text, p_offset int default 0, p_limit int default 1000)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    perform rb_require('power.backup_now', 'take a backup');
  end if;
  if not exists (select 1 from information_schema.tables where table_schema = 'public'
                 and table_type = 'BASE TABLE' and table_name = p_table) then
    raise exception 'Unknown table %.', p_table;
  end if;
  execute format('select coalesce(jsonb_agg(to_jsonb(t) - ''temp_password_hash''), ''[]''::jsonb)
                  from (select * from %I order by 1 limit %s offset %s) t',
                 p_table, least(greatest(p_limit, 1), 5000), greatest(p_offset, 0)) into v;
  return v;
end $$;

create or replace function rb_ping()
returns timestamptz language plpgsql security definer set search_path = public as $$
begin
  insert into backup_log (kind, status, detail) values ('ping', 'ok', 'Keep-awake ping');
  delete from backup_log where kind = 'ping' and at < now() - interval '90 days';
  return now();
end $$;

create or replace function rb_log_backup(p_kind text, p_status text, p_tables int, p_rows bigint, p_detail text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    perform rb_require('power.backup_now', 'record a backup');
  end if;
  insert into backup_log (kind, status, tables, rows, detail)
  values (p_kind, p_status, p_tables, p_rows, left(p_detail, 2000));
end $$;

-- ---------------------------------------------------------------------
-- 10. Row-level security: who can read what. All changes go through the
--     rb_ functions above, so the screens never write to tables directly.
-- ---------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array['app_settings','screens','powers','permissions','user_categories',
    'category_access','app_users','user_access_overrides','password_reset_requests',
    'doc_counters','audit_log','backup_log'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon, authenticated', t);
    execute format('grant select on %I to authenticated', t);
    execute format('grant all on %I to service_role', t);
  end loop;
end $$;
revoke all on all sequences in schema public from anon, authenticated;

drop policy if exists rb_read on app_settings;
create policy rb_read on app_settings for select to authenticated
  using (rb_current_user_id() is not null);

drop policy if exists rb_read on screens;
create policy rb_read on screens for select to authenticated using (rb_current_user_id() is not null);
drop policy if exists rb_read on powers;
create policy rb_read on powers for select to authenticated using (rb_current_user_id() is not null);
drop policy if exists rb_read on permissions;
create policy rb_read on permissions for select to authenticated using (rb_current_user_id() is not null);
drop policy if exists rb_read on user_categories;
create policy rb_read on user_categories for select to authenticated using (rb_current_user_id() is not null);
drop policy if exists rb_read on category_access;
create policy rb_read on category_access for select to authenticated using (rb_current_user_id() is not null);

drop policy if exists rb_read on app_users;
create policy rb_read on app_users for select to authenticated
  using (auth_id = auth.uid() or rb_has('users.view'));

drop policy if exists rb_read on user_access_overrides;
create policy rb_read on user_access_overrides for select to authenticated
  using (user_id = rb_current_user_id() or rb_has('users.view'));

drop policy if exists rb_read on password_reset_requests;
create policy rb_read on password_reset_requests for select to authenticated
  using (rb_has('power.reset_passwords'));
revoke select on password_reset_requests from authenticated;
grant select (id, target_user_id, requested_by, requested_at, status, decided_by, decided_at)
  on password_reset_requests to authenticated;

drop policy if exists rb_read on audit_log;
create policy rb_read on audit_log for select to authenticated using (rb_has('audit.view'));

drop policy if exists rb_read on backup_log;
create policy rb_read on backup_log for select to authenticated using (rb_has('settings.view'));

-- doc_counters: no direct reading; numbers come from rb_next_doc_no inside each posting.
revoke select on doc_counters from authenticated;

-- Functions: nobody may call them unless granted below.
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on all functions in schema public to service_role;
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
-- Internal helpers stay private: rb_apply_password, rb_audit_write, rb_next_doc_no,
-- rb_assert_can_assign, rb_require, rb_ping (Apps Script uses the service key).

-- ---------------------------------------------------------------------
-- 11. First admin and DEMO data
-- ---------------------------------------------------------------------

-- DS, Director: the first person to sign in. DS then invites everyone else.
insert into app_users (email, full_name, short_name, category_id)
select 'info.ruchibuds@gmail.com', 'DS', 'DS', id from user_categories where name = 'Director'
on conflict ((lower(email))) do nothing;

-- After a reset, people who already had a login are linked again straight away.
update app_users u set auth_id = a.id, status = 'active'
from auth.users a
where lower(a.email) = lower(u.email) and u.auth_id is null and u.status = 'invited' and not u.is_demo;

-- One extra DEMO category, to show a renamed copy of a template.
insert into user_categories (name, template, description, is_demo)
values ('Senior Staff (DEMO)', 'Staff', 'Example: Staff who may also see totals and add purchases', true)
on conflict (name) do nothing;
insert into category_access (category_id, perm)
select c.id, p from user_categories c,
  unnest(array['sales.view','sales.add','customers.view','customers.add',
               'purchases.view','purchases.add','power.see_totals']) p
where c.name = 'Senior Staff (DEMO)'
  and not exists (select 1 from category_access a where a.category_id = c.id)
on conflict do nothing;

-- Ten DEMO users across the categories. They are invitations only (they cannot sign in)
-- and show how the Users screen looks. "Remove demo data" deletes them.
insert into app_users (email, full_name, short_name, phone, category_id, status,
                       learning_phase_end, is_demo)
select d.email, d.full_name, d.short_name, d.phone, c.id, d.status, d.lpe::date, true
from (values
  ('demo.director2@example.com', 'Demo Director Two',  'DD2', '9800000001', 'Director',             'invited',  null),
  ('demo.fc@example.com',        'Demo Controller',    'DFC', '9800000002', 'Financial Controller', 'invited',  null),
  ('demo.accounts@example.com',  'Demo Accountant',    'DAC', '9800000003', 'Accountant',           'invited',  '2027-01-31'),
  ('demo.manager1@example.com',  'Demo Manager One',   'DM1', '9800000004', 'Manager',              'invited',  '2027-01-31'),
  ('demo.manager2@example.com',  'Demo Manager Two',   'DM2', '9800000005', 'Manager',              'inactive', '2026-12-31'),
  ('demo.ar@example.com',        'Demo Receivables',   'DAR', '9800000006', 'AR',                   'invited',  '2027-02-28'),
  ('demo.ap@example.com',        'Demo Payables',      'DAP', '9800000007', 'AP',                   'invited',  '2027-02-28'),
  ('demo.sales@example.com',     'Demo Sales',         'DSL', '9800000008', 'Sales',                'invited',  '2027-02-28'),
  ('demo.staff1@example.com',    'Demo Counter Staff', 'DS1', '9800000009', 'Staff',                'invited',  '2027-03-31'),
  ('demo.staff2@example.com',    'Demo Senior Staff',  'DS2', '9800000010', 'Senior Staff (DEMO)',  'invited',  '2027-03-31')
) as d(email, full_name, short_name, phone, category, status, lpe)
join user_categories c on c.name = d.category
on conflict ((lower(email))) do nothing;

-- One DEMO per-user override: Demo Manager One may also see margins on Sales.
insert into user_access_overrides (user_id, perm, allowed)
select id, 'sales.margin', true from app_users where email = 'demo.manager1@example.com'
on conflict do nothing;

-- End of 01_core_users.sql
