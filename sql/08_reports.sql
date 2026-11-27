-- =====================================================================
-- RUCHI BUDS APP · Module 8: Reports and Sheets copy
-- File: 08_reports.sql · Version 1.0 · 27-Nov-2026
--
-- What this file sets up:
--   The Reports screen (Director, FC and Accountant):
--   - a live dashboard: sales, margin, cash and bank, what customers owe
--     and what is owed to suppliers, stock, loans, with simple charts;
--   - the financial statements for any month or year, prepared in full
--     under Indian AS (ICAI) with no small-entity exemptions, in the
--     Schedule III layout that ICAI's Guidance Note on financial
--     statements of non-corporate entities uses: balance sheet,
--     statement of profit and loss, cash flow statement (AS 3, indirect
--     method), notes listing every account behind each line, and the
--     previous period alongside;
--   - the year-end close: the year's profit or loss is moved to the
--     partners' current accounts in the profit-sharing ratio set in
--     Settings;
--   - the weekly copy to Google Sheets (run by the Apps Script, Code.gs),
--     the long-term record that Looker Studio reads, and the link to the
--     Looker Studio report shown inside the app.
--
-- Each account is mapped to one line of the statements (fs_map, by code
-- prefix, longest match wins). The Accountant can change the mapping.
--
-- Run 01 to 07 first. Then: Supabase -> SQL Editor -> New query -> paste
-- this whole file -> Run. It is safe to run again; nothing you entered
-- is lost on a re-run. If an earlier file is ever run again, run the
-- later files again straight after it, in order, ending with this one.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Screen, rights and settings
-- ---------------------------------------------------------------------

update screens set available = true where code = 'reports';

-- New right: close the year. Not given to any category: Directors and
-- the FC always have every right.
insert into powers (code, name, description, sort) values
  ('year_end', 'Year-end close', 'Move the year''s profit or loss to the partners'' current accounts', 69)
on conflict (code) do nothing;
insert into permissions (code, kind, power_code, sort) values ('power.year_end', 'power', 'year_end', 10069)
on conflict (code) do nothing;

alter table app_settings add column if not exists looker_url text;
alter table app_settings add column if not exists report_sheet_url text;

-- The weekly Sheets copy is logged with the backups.
alter table backup_log drop constraint if exists backup_log_kind_check;
alter table backup_log add constraint backup_log_kind_check check (kind in ('nightly', 'manual', 'ping', 'restore', 'sheets'));

-- ---------------------------------------------------------------------
-- 2. Cash-flow categories (AS 3) that the statements depend on
-- ---------------------------------------------------------------------

-- Accumulated depreciation, amortisation and impairment allowances are
-- not cash: their change is the depreciation added back. The master
-- chart tags them "investing", which would count depreciation twice.
update accounts set cash_flow = 'non_cash'
where (code like '200102%' or code like '200302%') and cash_flow = 'investing';
-- The rent spread under AS 19 (module 7) is part of operating rent.
update accounts set cash_flow = 'operating' where code = '40020120' and cash_flow = 'financing';

-- ---------------------------------------------------------------------
-- 3. Lines of the statements and the account mapping
-- ---------------------------------------------------------------------

create table if not exists fs_lines (
  code       text primary key,
  statement  text not null check (statement in ('BS', 'PL')),
  section    text not null,
  name       text not null,
  sort       int not null
);

insert into fs_lines (code, statement, section, name, sort) values
  ('BS_CAP',  'BS', 'EQ',  'Partners'' capital accounts', 10),
  ('BS_CUR',  'BS', 'EQ',  'Partners'' current accounts', 20),
  ('BS_RES',  'BS', 'EQ',  'Reserves and surplus', 30),
  ('BS_LTB',  'BS', 'NCL', 'Long-term borrowings', 40),
  ('BS_DTL',  'BS', 'NCL', 'Deferred tax liabilities (net)', 50),
  ('BS_OLL',  'BS', 'NCL', 'Other long-term liabilities', 60),
  ('BS_LTP',  'BS', 'NCL', 'Long-term provisions', 70),
  ('BS_STB',  'BS', 'CL',  'Short-term borrowings', 80),
  ('BS_TP',   'BS', 'CL',  'Trade payables', 90),
  ('BS_OCL',  'BS', 'CL',  'Other current liabilities', 100),
  ('BS_STP',  'BS', 'CL',  'Short-term provisions', 110),
  ('BS_PPE',  'BS', 'NCA', 'Property, plant and equipment', 120),
  ('BS_INT',  'BS', 'NCA', 'Intangible assets', 130),
  ('BS_CWIP', 'BS', 'NCA', 'Capital work-in-progress', 140),
  ('BS_IUD',  'BS', 'NCA', 'Intangible assets under development', 150),
  ('BS_NCI',  'BS', 'NCA', 'Non-current investments', 160),
  ('BS_DTA',  'BS', 'NCA', 'Deferred tax assets (net)', 170),
  ('BS_LTLA', 'BS', 'NCA', 'Long-term loans and advances', 180),
  ('BS_ONCA', 'BS', 'NCA', 'Other non-current assets', 190),
  ('BS_CINV', 'BS', 'CA',  'Current investments', 200),
  ('BS_INV',  'BS', 'CA',  'Inventories', 210),
  ('BS_TR',   'BS', 'CA',  'Trade receivables', 220),
  ('BS_CASH', 'BS', 'CA',  'Cash and bank balances', 230),
  ('BS_STLA', 'BS', 'CA',  'Short-term loans and advances', 240),
  ('BS_OCA',  'BS', 'CA',  'Other current assets', 250),
  ('BS_SUSP', 'BS', 'CA',  'Suspense and clearing accounts (should be nil)', 260),
  ('PL_REV',  'PL', 'INC', 'Revenue from operations', 300),
  ('PL_OI',   'PL', 'INC', 'Other income', 310),
  ('PL_COM',  'PL', 'EXP', 'Cost of materials consumed', 320),
  ('PL_SIT',  'PL', 'EXP', 'Purchases of stock-in-trade', 330),
  ('PL_CHG',  'PL', 'EXP', 'Changes in inventories of finished goods, work-in-progress and stock-in-trade', 340),
  ('PL_EMP',  'PL', 'EXP', 'Employee benefits expense', 350),
  ('PL_FIN',  'PL', 'EXP', 'Finance costs', 360),
  ('PL_DEP',  'PL', 'EXP', 'Depreciation and amortisation expense', 370),
  ('PL_OTH',  'PL', 'EXP', 'Other expenses', 380),
  ('PL_EXC',  'PL', 'EXC', 'Exceptional and extraordinary items', 390),
  ('PL_TAX',  'PL', 'TAX', 'Tax expense', 400)
on conflict (code) do update set statement = excluded.statement, section = excluded.section, name = excluded.name, sort = excluded.sort;

create table if not exists fs_map (
  prefix      text primary key check (prefix ~ '^\d{1,8}$'),
  line_code   text not null references fs_lines(code),
  updated_at  timestamptz,
  updated_by  uuid
);

-- Starting mapping. A prefix the Accountant has changed is kept on a re-run.
insert into fs_map (prefix, line_code) values
  -- fall-backs by class, so no account is ever left out
  ('1', 'BS_OCA'), ('2', 'BS_ONCA'), ('3', 'BS_OCL'), ('4', 'BS_OLL'), ('5', 'BS_RES'),
  ('6', 'PL_REV'), ('7', 'PL_OTH'), ('8', 'PL_OTH'), ('90', 'PL_OI'), ('91', 'PL_FIN'), ('92', 'PL_TAX'), ('93', 'PL_EXC'),
  ('95', 'BS_SUSP'), ('96', 'BS_SUSP'), ('97', 'BS_SUSP'),
  -- owners' funds
  ('5001', 'BS_CAP'), ('50010135', 'BS_CUR'), ('50020125', 'BS_CUR'), ('5002', 'BS_RES'), ('5003', 'BS_RES'),
  -- non-current liabilities
  ('4001', 'BS_LTB'), ('40020110', 'BS_LTB'), ('40020115', 'BS_LTP'), ('40020120', 'BS_OLL'),
  ('4003', 'BS_OLL'), ('40030105', 'BS_DTL'), ('40030120', 'BS_LTP'), ('4004', 'BS_LTP'),
  ('40050105', 'BS_LTB'), ('40050110', 'BS_OLL'),
  -- current liabilities
  ('300101', 'BS_TP'), ('30070105', 'BS_TP'), ('3001', 'BS_OCL'), ('3002', 'BS_OCL'), ('3003', 'BS_OCL'),
  ('3004', 'BS_OCL'), ('3005', 'BS_OCL'), ('300601', 'BS_STB'), ('30060130', 'BS_OCL'), ('30070110', 'BS_STB'),
  ('3007', 'BS_OCL'), ('3008', 'BS_OCL'), ('3009', 'BS_STP'),
  -- non-current assets
  ('2001', 'BS_PPE'), ('20010155', 'BS_CWIP'), ('20010160', 'BS_CWIP'), ('2003', 'BS_INT'), ('20030145', 'BS_IUD'),
  ('2004', 'BS_LTLA'), ('20040110', 'BS_NCI'), ('20050105', 'BS_DTA'), ('2005', 'BS_ONCA'), ('20050130', 'BS_LTLA'),
  ('2006', 'BS_LTLA'), ('20060110', 'BS_NCI'),
  -- current assets
  ('1001', 'BS_CASH'), ('100103', 'BS_OCA'), ('1002', 'BS_TR'), ('100203', 'BS_STLA'), ('10020325', 'BS_OCA'),
  ('1003', 'BS_INV'), ('1004', 'BS_STLA'), ('10040220', 'BS_OCA'), ('1005', 'BS_STLA'),
  ('1006', 'BS_CASH'), ('10060110', 'BS_CINV'), ('10070105', 'BS_TR'), ('10070110', 'BS_STLA'), ('1007', 'BS_OCA'),
  -- profit and loss
  ('7001', 'PL_COM'), ('70030140', 'PL_COM'), ('7002', 'PL_EMP'), ('70030125', 'PL_EMP'), ('70030115', 'PL_DEP'),
  ('8001', 'PL_EMP'), ('80070105', 'PL_DEP'), ('80070115', 'PL_DEP')
on conflict (prefix) do nothing;

-- The line an account belongs to: the longest matching prefix.
create or replace function rb_fs_line(p_code text)
returns text language sql stable security definer set search_path = public as $$
  select line_code from fs_map where p_code like prefix || '%' order by length(prefix) desc limit 1
$$;

-- Inventory accounts used to work out the Schedule III expense lines.
create or replace function rb_rp_fg_codes()
returns text[] language sql immutable as $$ select array['10030120', '10030125', '10030130'] $$;
create or replace function rb_rp_merch_codes()
returns text[] language sql immutable as $$ select array['10030130'] $$;
create or replace function rb_rp_merch_cost_codes()
returns text[] language sql immutable as $$ select array['70010115'] $$;
create or replace function rb_rp_lease_codes()
returns text[] language sql immutable as $$ select array['40020110', '30060120'] $$;
create or replace function rb_rp_tax_codes()
returns text[] language sql immutable as $$ select array['30030140', '10050125'] $$;

-- ---------------------------------------------------------------------
-- 4. Building blocks
-- ---------------------------------------------------------------------

create or replace function rb_rp_require()
returns uuid language plpgsql stable security definer set search_path = public as $$
begin
  if not (rb_has('reports.view') or rb_has('accounts.view')) then
    raise exception 'You do not have the right to see reports.';
  end if;
  return rb_current_user_id();
end $$;

-- Per account, debit-positive:
--   open_bal  balance before p_from (every entry)
--   move      entries from p_from to p_to, without the year-end close
--   move_ops  the same, also without opening balances (take-on)
--   close_bal balance at p_to (every entry)
create or replace function rb_rp_acc(p_from date, p_to date, p_demo boolean)
returns table (code text, name text, statement text, cash_flow text, line_code text,
               open_bal bigint, move bigint, move_ops bigint, close_bal bigint)
language sql stable security definer set search_path = public as $$
  with l as (
    select jl.account_code c, jl.journal_date d, jl.debit_paise - jl.credit_paise v, j.source s
    from journal_lines jl join journals j on j.id = jl.journal_id
    where j.status in ('posted', 'reversed') and jl.journal_date <= p_to and (p_demo or not jl.is_demo)
  ), g as (
    select c,
           sum(case when d < p_from then v else 0 end) ob,
           sum(case when d >= p_from and s <> 'year_end' then v else 0 end) mv,
           sum(case when d >= p_from and s not in ('year_end', 'opening') then v else 0 end) mo,
           sum(v) cb
    from l group by c
  )
  select a.code, coalesce(a.local_name, a.name), a.statement, a.cash_flow, rb_fs_line(a.code),
         g.ob::bigint, g.mv::bigint, g.mo::bigint, g.cb::bigint
  from g join accounts a on a.code = g.c
  where g.ob <> 0 or g.mv <> 0 or g.cb <> 0 or g.mo <> 0
$$;

-- The previous period of the same length: whole months shift by months.
create or replace function rb_rp_prev(p_from date, p_to date)
returns table (prev_from date, prev_to date) language plpgsql immutable as $$
declare n int;
begin
  -- Year to date (from 1 April, less than a full year): the same dates a year earlier.
  if extract(month from p_from) = 4 and extract(day from p_from) = 1 and p_to < (p_from + interval '1 year')::date - 1 then
    prev_from := (p_from - interval '1 year')::date;
    prev_to := (p_to - interval '1 year')::date;
  elsif extract(day from p_from) = 1 and (p_to + 1) = date_trunc('month', p_to + 1)::date then
    n := (extract(year from p_to) * 12 + extract(month from p_to)) - (extract(year from p_from) * 12 + extract(month from p_from)) + 1;
    prev_from := (p_from - make_interval(months => n))::date;
    prev_to := p_from - 1;
  else
    prev_to := p_from - 1;
    prev_from := prev_to - (p_to - p_from);
  end if;
  return next;
end $$;

-- Principal of long-term loans and finance leases that falls due within
-- 12 months of p_date (Schedule III: shown under short-term borrowings).
create or replace function rb_rp_current_maturities(p_date date, p_demo boolean)
returns bigint language sql stable security definer set search_path = public as $$
  select coalesce(sum(least(greatest(b.owed, 0), coalesce(d.due, 0))), 0)::bigint
  from loans l
  cross join lateral rb_ll_bal(l.id, null, p_date) b
  left join lateral (
    select sum(s.principal_paise) due from loan_schedule s
    left join loan_entries e on e.id = s.paid_entry_id
    where s.loan_id = l.id and s.due_date > p_date and s.due_date <= (p_date + interval '12 months')::date
      and (s.paid_entry_id is null or e.entry_date > p_date)
  ) d on true
  where l.status in ('active', 'closed', 'ended') and (p_demo or not l.is_demo)
    and rb_fs_line(l.account_code) = 'BS_LTB'
$$;

-- Statement of profit and loss amounts for one period (expenses positive).
create or replace function rb_rp_pl(p_from date, p_to date, p_demo boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v jsonb := '{}'; r record; v_sit bigint; v_chg bigint; v_com bigint;
        v_rev bigint; v_oi bigint; v_emp bigint; v_fin bigint; v_dep bigint; v_oth bigint; v_exc bigint; v_tax bigint;
        v_ti bigint; v_te bigint;
begin
  if to_regclass('pg_temp.rb_tmp_pl') is null then
    create temp table rb_tmp_pl (code text, name text, statement text, cash_flow text, line_code text,
      open_bal bigint, move bigint, move_ops bigint, close_bal bigint) on commit drop;
  end if;
  delete from rb_tmp_pl;
  insert into rb_tmp_pl select * from rb_rp_acc(p_from, p_to, p_demo);
  select coalesce(-sum(move) filter (where line_code = 'PL_REV'), 0), coalesce(-sum(move) filter (where line_code = 'PL_OI'), 0),
         coalesce(sum(move) filter (where line_code = 'PL_EMP'), 0), coalesce(sum(move) filter (where line_code = 'PL_FIN'), 0),
         coalesce(sum(move) filter (where line_code = 'PL_DEP'), 0), coalesce(sum(move) filter (where line_code = 'PL_OTH'), 0),
         coalesce(sum(move) filter (where line_code = 'PL_EXC'), 0), coalesce(sum(move) filter (where line_code = 'PL_TAX'), 0),
         coalesce(sum(move) filter (where line_code in ('PL_COM', 'PL_SIT', 'PL_CHG')), 0),
         coalesce(sum(move) filter (where code = any (rb_rp_merch_cost_codes())), 0) + coalesce(sum(move_ops) filter (where code = any (rb_rp_merch_codes())), 0),
         coalesce(-sum(move_ops) filter (where code = any (rb_rp_fg_codes())), 0)
  into v_rev, v_oi, v_emp, v_fin, v_dep, v_oth, v_exc, v_tax, v_com, v_sit, v_chg
  from rb_tmp_pl;
  v_com := v_com - v_sit - v_chg;   -- what is left is the materials used
  v_ti := v_rev + v_oi;
  v_te := v_com + v_sit + v_chg + v_emp + v_fin + v_dep + v_oth;
  return jsonb_build_object('PL_REV', v_rev, 'PL_OI', v_oi, 'total_income', v_ti,
    'PL_COM', v_com, 'PL_SIT', v_sit, 'PL_CHG', v_chg, 'PL_EMP', v_emp, 'PL_FIN', v_fin, 'PL_DEP', v_dep, 'PL_OTH', v_oth,
    'total_expenses', v_te, 'before_exceptional', v_ti - v_te, 'PL_EXC', v_exc, 'before_tax', v_ti - v_te - v_exc,
    'PL_TAX', v_tax, 'profit', v_ti - v_te - v_exc - v_tax,
    'check', v_ti - v_te - v_exc - v_tax + (select coalesce(sum(move), 0) from rb_tmp_pl where statement = 'PL'),
    'accounts', coalesce((select jsonb_agg(jsonb_build_object('code', code, 'name', name, 'line', line_code,
        'amount', case when line_code in ('PL_REV', 'PL_OI') then -move else move end) order by code)
      from rb_tmp_pl where statement = 'PL' and move <> 0), '[]'));
end $$;

-- Balance sheet amounts at one date (liabilities and equity positive).
create or replace function rb_rp_bs(p_date date, p_demo boolean)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_cm bigint := rb_rp_current_maturities(p_date, p_demo); v_lines jsonb; v_pl bigint;
begin
  with a as (
    select x.code, x.name, x.statement, x.line_code, x.close_bal b, l.section
    from rb_rp_acc(p_date + 1, p_date, p_demo) x left join fs_lines l on l.code = x.line_code
    where x.close_bal <> 0
  ), bs as (
    select line_code, section, code, name,
           case when section in ('EQ', 'NCL', 'CL') then -b else b end amt
    from a where statement <> 'PL'
  )
  select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name, 'line', line_code, 'amount', amt) order by code), '[]'),
         (select coalesce(-sum(b), 0) from a where statement = 'PL')
  into v_lines, v_pl from bs;
  -- Profit not yet moved to the partners sits in reserves and surplus.
  if v_pl <> 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('code', null, 'name', 'Surplus in the statement of profit and loss (not yet transferred to partners)',
      'line', 'BS_RES', 'amount', v_pl));
  end if;
  if v_cm <> 0 then
    v_lines := v_lines || jsonb_build_array(
      jsonb_build_object('code', null, 'name', 'Less: current maturities, shown under short-term borrowings', 'line', 'BS_LTB', 'amount', -v_cm),
      jsonb_build_object('code', null, 'name', 'Current maturities of long-term borrowings and finance lease obligations', 'line', 'BS_STB', 'amount', v_cm));
  end if;
  return jsonb_build_object('date', p_date, 'accounts', v_lines,
    'lines', (select coalesce(jsonb_object_agg(k, s), '{}') from (
       select e->>'line' k, sum((e->>'amount')::bigint) s from jsonb_array_elements(v_lines) e group by 1) z),
    'current_maturities', v_cm);
end $$;

-- ---------------------------------------------------------------------
-- 5. Financial statements
-- ---------------------------------------------------------------------

create or replace function rb_financial_statements(p_from date, p_to date, p_demo boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_pf date; v_pt date; v_bs jsonb; v_bsp jsonb; v_pl jsonb; v_plp jsonb; v_tot_w numeric; v_parts jsonb; v_left bigint; v_n int; i int := 0;
        p jsonb; v_share bigint; v_profit bigint; v_assets bigint; v_liab bigint;
begin
  perform rb_rp_require();
  if p_from is null or p_to is null or p_from > p_to then raise exception 'Please choose a From date on or before the To date.'; end if;
  select prev_from, prev_to into v_pf, v_pt from rb_rp_prev(p_from, p_to);
  v_bs := rb_rp_bs(p_to, p_demo);
  v_bsp := rb_rp_bs(p_from - 1, p_demo);
  v_pl := rb_rp_pl(p_from, p_to, p_demo);
  v_plp := rb_rp_pl(v_pf, v_pt, p_demo);
  -- The profit shared by the partners' ratio (for the appropriation note).
  v_profit := (v_pl->>'profit')::bigint;
  select coalesce(sum((e->>'weight')::numeric), 0), count(*) into v_tot_w, v_n
  from app_settings s, jsonb_array_elements(s.partners) e where s.id = 1;
  v_parts := '[]'; v_left := v_profit;
  for p in select e from app_settings s, jsonb_array_elements(s.partners) e where s.id = 1 loop
    i := i + 1;
    v_share := case when i = v_n then v_left else round(v_profit * (p->>'weight')::numeric / nullif(v_tot_w, 0)) end;
    v_left := v_left - v_share;
    v_parts := v_parts || jsonb_build_array(jsonb_build_object('name', p->>'name', 'weight', (p->>'weight')::numeric, 'share', v_share));
  end loop;
  select coalesce(sum((value)::bigint) filter (where l.section in ('NCA', 'CA')), 0),
         coalesce(sum((value)::bigint) filter (where l.section in ('EQ', 'NCL', 'CL')), 0)
  into v_assets, v_liab
  from jsonb_each_text(v_bs->'lines') x join fs_lines l on l.code = x.key;
  return jsonb_build_object('from', p_from, 'to', p_to, 'prev_from', v_pf, 'prev_to', v_pt, 'bs_prev_date', p_from - 1, 'demo', p_demo,
    'firm', (select jsonb_build_object('name', firm_name, 'legal_form', legal_form, 'reg_no', coalesce(firm_reg_no, llpin)) from app_settings where id = 1),
    'lines', (select jsonb_agg(to_jsonb(l) order by l.sort) from fs_lines l),
    'bs', v_bs, 'bs_prev', v_bsp, 'pl', v_pl, 'pl_prev', v_plp, 'partners', v_parts,
    'total_assets', v_assets, 'total_liabilities', v_liab, 'bs_difference', v_assets - v_liab);
end $$;

-- ---------------------------------------------------------------------
-- 6. Cash flow statement (AS 3, indirect method)
-- ---------------------------------------------------------------------

-- Cash effect of each line = credit - debit. Every account except cash
-- and cash equivalents is placed in exactly one row, so the rows always
-- add up to the change in cash. Opening balances (take-on) and the
-- year-end close are not cash flows and are left out. A journal that
-- moves no cash and only swaps investing and financing items (a finance
-- lease starting) is left out and shown as a non-cash transaction.
create or replace function rb_rp_cfs(p_from date, p_to date, p_demo boolean)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb; v_open bigint; v_close bigint; v_rows jsonb; v_net bigint; v_nc bigint;
begin
  with l as (
    select jl.journal_id jid, a.code, a.statement st, a.cash_flow cf, rb_fs_line(a.code) ln,
           (jl.credit_paise - jl.debit_paise)::bigint amt
    from journal_lines jl join journals j on j.id = jl.journal_id join accounts a on a.code = jl.account_code
    where j.status in ('posted', 'reversed') and jl.journal_date between p_from and p_to
      and j.source not in ('opening', 'year_end') and (p_demo or not jl.is_demo)
  ), jn as (
    select jid, bool_or(cf = 'cash') has_cash,
           bool_or(st = 'BS' and cf in ('investing', 'financing')) has_if,
           bool_or(st = 'PL' and cf in ('investing', 'financing')) has_plif,
           sum(amt) filter (where st = 'BS' and cf in ('investing', 'financing')) if_sum
    from l group by jid
  ), x as (
    select l.*, (not jn.has_cash and jn.has_if and not jn.has_plif and coalesce(jn.if_sum, 0) = 0) noncash,
      case
        when l.cf = 'cash' then 'cash'
        when l.st = 'PL' and l.ln = 'PL_TAX' then 'A_tax'
        when l.st = 'BS' and l.code = any (rb_rp_tax_codes()) then 'A_tax'
        when l.st = 'PL' and l.cf = 'financing' then 'C_interest'
        when l.st = 'PL' and l.cf = 'investing' then 'B_income'
        when l.st = 'PL' then 'A_pbt'
        when l.cf in ('non_cash', 'none') and l.ln in ('BS_PPE', 'BS_INT', 'BS_CWIP', 'BS_IUD') then 'A_adj_dep'
        when l.cf in ('non_cash', 'none') and l.ln = 'BS_TR' then 'A_adj_prov'
        when l.cf in ('non_cash', 'none') then 'A_adj_other'
        when l.cf = 'operating' and l.ln = 'BS_INV' then 'A_wc_inv'
        when l.cf = 'operating' and l.ln = 'BS_TR' then 'A_wc_tr'
        when l.cf = 'operating' and l.ln = 'BS_TP' then 'A_wc_tp'
        when l.cf = 'operating' and fl.section in ('NCA', 'CA') then 'A_wc_assets'
        when l.cf = 'operating' then 'A_wc_liab'
        when l.cf = 'investing' and l.ln in ('BS_PPE', 'BS_INT', 'BS_CWIP', 'BS_IUD') then 'B_ppe'
        when l.cf = 'investing' and l.ln in ('BS_NCI', 'BS_CINV') then 'B_invest'
        when l.cf = 'investing' and l.ln in ('BS_LTLA', 'BS_STLA', 'BS_CASH', 'BS_OCA', 'BS_ONCA') then 'B_deposits'
        when l.cf = 'investing' then 'B_other'
        when l.cf = 'financing' and l.code = any (rb_rp_lease_codes()) then 'C_lease'
        when l.cf = 'financing' and l.ln in ('BS_LTB', 'BS_STB') then 'C_borrow'
        when l.cf = 'financing' and l.ln in ('BS_CAP', 'BS_CUR', 'BS_RES') then 'C_partners'
        when l.cf = 'financing' and l.ln = 'BS_OCL' then 'C_interest'
        else 'C_other' end grp
    from l join jn on jn.jid = l.jid left join fs_lines fl on fl.code = l.ln
  ), per_j as (   -- gross receipts and payments per journal for the investing and financing rows
    select grp, jid, sum(amt) s from x where not noncash and grp in ('B_ppe', 'C_borrow', 'C_lease', 'C_partners') group by grp, jid
  ), rows as (
    select grp k, sum(amt) s from x where grp not in ('cash', 'B_ppe', 'C_borrow', 'C_lease', 'C_partners')
      and not (noncash and grp like 'B\_%' or noncash and grp like 'C\_%') group by grp
    union all
    select grp || case when s < 0 then '_out' else '_in' end, sum(s) from per_j group by grp, s < 0
    union all  -- interest added back to profit, and income taken out, before working capital
    select 'A_pbt', sum(amt) from x where st = 'PL' and grp in ('C_interest', 'B_income')   -- profit before tax includes them
    union all
    select 'A_adj_fin', -sum(amt) from x where st = 'PL' and grp = 'C_interest'
    union all
    select 'A_adj_inc', -sum(amt) from x where st = 'PL' and grp = 'B_income'
  )
  select coalesce(jsonb_object_agg(k, s), '{}') into v_rows from (select k, coalesce(sum(s), 0)::bigint s from rows group by k) z;
  v_rows := (select jsonb_object_agg(k, 0) from unnest(array['A_pbt', 'A_adj_dep', 'A_adj_prov', 'A_adj_other', 'A_adj_fin', 'A_adj_inc',
    'A_wc_inv', 'A_wc_tr', 'A_wc_tp', 'A_wc_assets', 'A_wc_liab', 'A_tax', 'B_ppe_out', 'B_ppe_in', 'B_invest', 'B_deposits', 'B_income', 'B_other',
    'C_borrow_in', 'C_borrow_out', 'C_lease_in', 'C_lease_out', 'C_partners_in', 'C_partners_out', 'C_interest', 'C_other']) k) || v_rows;
  -- Assets bought under finance leases and other non-cash investing or financing.
  select coalesce(-sum(jl.credit_paise - jl.debit_paise), 0) into v_nc
  from journal_lines jl join journals j on j.id = jl.journal_id join accounts a on a.code = jl.account_code
  where j.status in ('posted', 'reversed') and jl.journal_date between p_from and p_to
    and j.source not in ('opening', 'year_end') and (p_demo or not jl.is_demo) and a.statement = 'BS' and a.cash_flow = 'investing'
    and not exists (select 1 from journal_lines k join accounts b on b.code = k.account_code where k.journal_id = j.id and b.cash_flow = 'cash')
    and not exists (select 1 from journal_lines k join accounts b on b.code = k.account_code where k.journal_id = j.id and b.statement = 'PL' and b.cash_flow in ('investing', 'financing'))
    and (select coalesce(sum(k.credit_paise - k.debit_paise), 0) from journal_lines k join accounts b on b.code = k.account_code
         where k.journal_id = j.id and b.statement = 'BS' and b.cash_flow in ('investing', 'financing')) = 0;
  -- Cash at the start, including take-on balances brought in during the period.
  select coalesce(sum(jl.debit_paise - jl.credit_paise) filter (where jl.journal_date < p_from or j.source = 'opening'), 0),
         coalesce(sum(jl.debit_paise - jl.credit_paise), 0)
  into v_open, v_close
  from journal_lines jl join journals j on j.id = jl.journal_id join accounts a on a.code = jl.account_code
  where j.status in ('posted', 'reversed') and jl.journal_date <= p_to and (p_demo or not jl.is_demo) and a.cash_flow = 'cash';
  select coalesce(sum(value::bigint), 0) into v_net from jsonb_each_text(v_rows);
  return v_rows || jsonb_build_object('opening_cash', v_open, 'closing_cash', v_close, 'net_change', v_net,
    'difference', v_open + v_net - v_close, 'non_cash_investing', v_nc,
    'cash_accounts', coalesce((select jsonb_agg(jsonb_build_object('code', a.code, 'name', coalesce(a.local_name, a.name), 'amount', s) order by a.code)
      from (select jl.account_code c, sum(jl.debit_paise - jl.credit_paise)::bigint s
            from journal_lines jl join journals j on j.id = jl.journal_id
            where j.status in ('posted', 'reversed') and jl.journal_date <= p_to and (p_demo or not jl.is_demo)
            group by 1) b join accounts a on a.code = b.c where a.cash_flow = 'cash' and b.s <> 0), '[]'));
end $$;

create or replace function rb_cash_flow(p_from date, p_to date, p_demo boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_pf date; v_pt date;
begin
  perform rb_rp_require();
  if p_from is null or p_to is null or p_from > p_to then raise exception 'Please choose a From date on or before the To date.'; end if;
  select prev_from, prev_to into v_pf, v_pt from rb_rp_prev(p_from, p_to);
  return jsonb_build_object('from', p_from, 'to', p_to, 'prev_from', v_pf, 'prev_to', v_pt, 'demo', p_demo,
    'cur', rb_rp_cfs(p_from, p_to, p_demo), 'prev', rb_rp_cfs(v_pf, v_pt, p_demo),
    'pbt', (rb_rp_pl(p_from, p_to, p_demo)->>'before_tax')::bigint, 'pbt_prev', (rb_rp_pl(v_pf, v_pt, p_demo)->>'before_tax')::bigint);
end $$;

-- ---------------------------------------------------------------------
-- 7. The line mapping (Accountant, FC, Directors)
-- ---------------------------------------------------------------------

create or replace function rb_save_fs_map(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('accounts.edit', 'change the statement lines'); v_pre text := trim(p->>'prefix');
        v_line fs_lines; v_bad text; v_old text;
begin
  if v_pre is null or v_pre !~ '^\d{1,8}$' then raise exception 'The account code (or the start of it) must be 1 to 8 digits.'; end if;
  select * into v_line from fs_lines where code = p->>'line_code';
  if v_line.code is null then raise exception 'Please choose the line.'; end if;
  if not exists (select 1 from accounts where code like v_pre || '%') then raise exception 'No account starts with %.', v_pre; end if;
  select string_agg(code, ', ' order by code) into v_bad from (
    select code from accounts where code like v_pre || '%' and level = 'posting'
      and (case when statement = 'PL' then 'PL' else 'BS' end) <> v_line.statement limit 5) z;
  if v_bad is not null then
    raise exception 'Accounts % are % accounts and cannot go to "%".', v_bad,
      case when v_line.statement = 'PL' then 'balance sheet' else 'profit and loss' end, v_line.name;
  end if;
  select line_code into v_old from fs_map where prefix = v_pre;
  insert into fs_map (prefix, line_code, updated_at, updated_by) values (v_pre, v_line.code, now(), v_me)
  on conflict (prefix) do update set line_code = excluded.line_code, updated_at = now(), updated_by = v_me;
  perform rb_audit_write('FS_MAP', 'fs_map', v_pre, jsonb_build_object('line', v_old), jsonb_build_object('line', v_line.code), null);
end $$;

create or replace function rb_delete_fs_map(p_prefix text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('accounts.edit', 'change the statement lines'); v_old text;
begin
  if length(p_prefix) = 1 or p_prefix in ('90', '91', '92', '93', '95', '96', '97') then
    raise exception 'This is a fall-back for a whole class of accounts and is kept. Change its line instead.';
  end if;
  delete from fs_map where prefix = p_prefix returning line_code into v_old;
  if v_old is null then raise exception 'Mapping % not found.', p_prefix; end if;
  perform rb_audit_write('FS_MAP_DELETE', 'fs_map', p_prefix, jsonb_build_object('line', v_old), null, null);
end $$;

-- Every account with its line, for the mapping screen.
create or replace function rb_fs_map_list()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform rb_rp_require();
  return jsonb_build_object(
    'lines', (select jsonb_agg(to_jsonb(l) order by l.sort) from fs_lines l),
    'map', (select coalesce(jsonb_agg(jsonb_build_object('prefix', m.prefix, 'line', m.line_code,
        'accounts', (select count(*) from accounts a where a.code like m.prefix || '%' and a.level = 'posting' and a.e002_active))
        order by m.prefix), '[]') from fs_map m),
    'accounts', (select jsonb_agg(jsonb_build_object('code', code, 'name', coalesce(local_name, name), 'statement', statement,
        'cash_flow', cash_flow, 'line', rb_fs_line(code)) order by code)
      from accounts where level = 'posting' and e002_active));
end $$;

-- ---------------------------------------------------------------------
-- 8. Year-end close
-- ---------------------------------------------------------------------

create or replace function rb_rp_fy_check(p_fy_end date)
returns date language plpgsql stable security definer set search_path = public as $$
declare v_start date := rb_fy_start(p_fy_end);
begin
  if p_fy_end is null or (v_start + interval '1 year' - interval '1 day')::date <> p_fy_end then
    raise exception 'Please choose the last day of a financial year (31-Mar).';
  end if;
  return v_start;
end $$;

-- What the close would post: every profit and loss account (by
-- department) back to nil, and the profit or loss to the partners.
create or replace function rb_rp_ye_lines(p_fy_end date, p_demo boolean)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_start date := rb_rp_fy_check(p_fy_end); v_lines jsonb; v_profit bigint; v_tot numeric; v_n int; i int := 0;
        v_left bigint; v_share bigint; p jsonb; v_parts jsonb := '[]'; v_dept int := rb_pur_default_dept(); v_earlier bigint;
begin
  with b as (
    select jl.account_code c,
           coalesce((select d.id from departments d where d.id = rb_dept_resolve(jl.department_id, p_fy_end) and d.is_active), v_dept) dep,
           sum(jl.debit_paise - jl.credit_paise) s
    from journal_lines jl join journals j on j.id = jl.journal_id join accounts a on a.code = jl.account_code
    where j.status in ('posted', 'reversed') and a.statement = 'PL' and jl.is_demo = p_demo
      and jl.journal_date between v_start and p_fy_end
    group by 1, 2 having sum(jl.debit_paise - jl.credit_paise) <> 0
  )
  select coalesce(jsonb_agg(jsonb_build_object('account_code', c, 'department_id', dep,
           'debit_paise', case when s < 0 then -s else 0 end, 'credit_paise', case when s > 0 then s else 0 end,
           'narration', 'Year-end close') order by c, dep), '[]'),
         coalesce(-sum(s), 0)
  into v_lines, v_profit from b;
  select coalesce(sum(jl.debit_paise - jl.credit_paise), 0) into v_earlier
  from journal_lines jl join journals j on j.id = jl.journal_id join accounts a on a.code = jl.account_code
  where j.status in ('posted', 'reversed') and a.statement = 'PL' and jl.is_demo = p_demo and jl.journal_date < v_start;
  select coalesce(sum((e->>'weight')::numeric), 0), count(*) into v_tot, v_n
  from app_settings s, jsonb_array_elements(s.partners) e where s.id = 1;
  if v_tot <= 0 then raise exception 'Set the partners and their profit-sharing ratio in Settings first.'; end if;
  v_left := v_profit;
  for p in select e from app_settings s, jsonb_array_elements(s.partners) e where s.id = 1 loop
    i := i + 1;
    v_share := case when i = v_n then v_left else round(v_profit * (p->>'weight')::numeric / v_tot) end;
    v_left := v_left - v_share;
    v_parts := v_parts || jsonb_build_array(jsonb_build_object('id', (p->>'id')::int, 'name', p->>'name', 'weight', (p->>'weight')::numeric, 'share', v_share));
    if v_share <> 0 then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('account_code', '50010135', 'department_id', v_dept,
        'partner_id', (p->>'id')::int, 'debit_paise', case when v_share < 0 then -v_share else 0 end,
        'credit_paise', case when v_share > 0 then v_share else 0 end,
        'narration', 'Share of ' || case when v_profit >= 0 then 'profit' else 'loss' end || ': ' || (p->>'name')));
    end if;
  end loop;
  return jsonb_build_object('profit', v_profit, 'lines', v_lines, 'accounts', jsonb_array_length(v_lines) - (select count(*) from jsonb_array_elements(v_parts) e where (e->>'share')::bigint <> 0),
    'partners', v_parts, 'earlier_unclosed', v_earlier,
    'journals', coalesce((select jsonb_agg(jsonb_build_object('id', j.id, 'journal_no', j.journal_no, 'date', j.journal_date, 'status', j.status,
        'total_paise', j.total_paise) order by j.id)
      from journals j where j.source = 'year_end' and j.source_ref = 'FY' || to_char(v_start, 'YYYY') and j.is_demo = p_demo and j.reversal_of is null), '[]'));
end $$;

create or replace function rb_year_end_preview(p_fy_end date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_start date;
begin
  perform rb_rp_require();
  v_start := rb_rp_fy_check(p_fy_end);
  return jsonb_build_object('fy_start', v_start, 'fy_end', p_fy_end, 'ended', current_date > p_fy_end,
    'label', 'FY ' || to_char(v_start, 'YYYY') || '-' || to_char(p_fy_end, 'YY'),
    'fy_end_locked', rb_period_locked(p_fy_end),
    'unlocked_months', (select coalesce(jsonb_agg(to_char(m, 'Mon-YYYY') order by m), '[]')
      from generate_series(v_start, p_fy_end - interval '1 month', interval '1 month') m where not rb_period_locked(m::date)),
    'real', rb_rp_ye_lines(p_fy_end, false), 'demo', rb_rp_ye_lines(p_fy_end, true),
    'can_post', rb_has('power.year_end'));
end $$;

-- Posts the close for the real books, and separately for any DEMO
-- entries (so "Remove demo data" later takes the DEMO close away too).
-- Running it again after late entries posts only what is still open.
create or replace function rb_post_year_end(p_fy_end date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('power.year_end', 'close the year'); v_start date := rb_rp_fy_check(p_fy_end);
        x jsonb; d boolean; v_ids jsonb := '[]'; v_id bigint; v_label text;
begin
  if current_date <= p_fy_end then raise exception 'The year can be closed once it has ended (from %).', to_char(p_fy_end + 1, 'DD-Mon-YYYY'); end if;
  v_label := 'FY ' || to_char(v_start, 'YYYY') || '-' || to_char(p_fy_end, 'YY');
  foreach d in array array[false, true] loop
    x := rb_rp_ye_lines(p_fy_end, d);
    if (x->>'earlier_unclosed')::bigint <> 0 and jsonb_array_length(x->'lines') > 0 then
      raise exception 'An earlier year still has profit or loss that is not closed%. Close the earlier year first.',
        case when d then ' (DEMO entries)' else '' end;
    end if;
    if jsonb_array_length(x->'lines') = 0 then continue; end if;
    v_id := rb_post_engine(jsonb_build_object('journal_date', p_fy_end, 'source', 'year_end', 'source_ref', 'FY' || to_char(v_start, 'YYYY'),
      'event_code', 'year_end', 'narration', v_label || ': year-end close, ' || case when (x->>'profit')::bigint >= 0 then 'profit' else 'loss' end ||
      ' moved to the partners'' current accounts', 'department_id', rb_pur_default_dept(), 'is_demo', d), x->'lines');
    v_ids := v_ids || to_jsonb(v_id);
  end loop;
  if jsonb_array_length(v_ids) = 0 then raise exception 'Nothing to close: every profit and loss account for % is already nil.', v_label; end if;
  perform rb_audit_write('YEAR_END', 'journals', v_label, null, jsonb_build_object('journals', v_ids), null);
  return v_ids;
end $$;

-- ---------------------------------------------------------------------
-- 9. Dashboard and report data
-- ---------------------------------------------------------------------

-- Sales after returns, by day, item, channel and customer kind.
create or replace function rb_rp_sales(p_from date, p_to date, p_demo boolean)
returns table (d date, channel text, customer_kind text, item_id int, item text, net bigint, cost bigint)
language sql stable security definer set search_path = public as $$
  select s.invoice_date, s.channel, c.kind, l.item_id, i.name, l.taxable_paise::bigint, l.cost_paise::bigint
  from sale_lines l join sales s on s.id = l.sale_id join customers c on c.id = s.customer_id join items i on i.id = l.item_id
  where s.status <> 'cancelled' and s.invoice_date between p_from and p_to and (p_demo or not s.is_demo)
  union all
  select r.return_date, s.channel, c.kind, l.item_id, i.name, -x.taxable_paise::bigint,
         -(case when r.condition = 'restock' then x.cost_paise else 0 end)::bigint
  from sales_return_lines x join sales_returns r on r.id = x.return_id join sale_lines l on l.id = x.sale_line_id
  join sales s on s.id = r.sale_id join customers c on c.id = s.customer_id join items i on i.id = l.item_id
  where r.status = 'posted' and r.return_date between p_from and p_to and (p_demo or not r.is_demo)
$$;

create or replace function rb_report_dashboard(p_date date default current_date, p_demo boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_m date := date_trunc('month', p_date)::date; v_fy date := rb_fy_start(p_date); v_margin boolean;
        v_pm date := (date_trunc('month', p_date) - interval '1 month')::date; v_12 date := (date_trunc('month', p_date) - interval '11 months')::date;
        v jsonb; v_cust record; v_sup record;
begin
  perform rb_rp_require();
  v_margin := rb_has('reports.margin') or rb_has('accounts.view');
  if to_regclass('pg_temp.rb_tmp_sales') is null then
    create temp table rb_tmp_sales (d date, channel text, customer_kind text, item_id int, item text, net bigint, cost bigint) on commit drop;
  end if;
  delete from rb_tmp_sales;
  insert into rb_tmp_sales select * from rb_rp_sales(least(v_12, v_fy, v_pm), p_date, p_demo);
  select coalesce(sum(balance_paise), 0) owed, coalesce(sum(d1_30_paise + d31_60_paise + d61_90_paise + over_90_paise), 0) overdue,
         coalesce(sum(over_90_paise), 0) over_90, count(*) filter (where balance_paise > 0) n
  into v_cust from rb_customer_balances(p_date, p_demo);
  select coalesce(sum(balance_paise), 0) owed, coalesce(sum(overdue_paise), 0) overdue, count(*) filter (where balance_paise > 0) n
  into v_sup from rb_supplier_balances(p_date, p_demo);
  v := jsonb_build_object('date', p_date, 'demo', p_demo, 'margin_ok', v_margin,
    'sales_today', (select coalesce(sum(net), 0) from rb_tmp_sales where d = p_date),
    'sales_mtd', (select coalesce(sum(net), 0) from rb_tmp_sales where d >= v_m),
    'sales_prev_month', (select coalesce(sum(net), 0) from rb_tmp_sales where d >= v_pm and d < v_m),
    'sales_ytd', (select coalesce(sum(net), 0) from rb_tmp_sales where d >= v_fy),
    'margin_mtd', case when v_margin then (select coalesce(sum(net - cost), 0) from rb_tmp_sales where d >= v_m) end,
    'margin_ytd', case when v_margin then (select coalesce(sum(net - cost), 0) from rb_tmp_sales where d >= v_fy) end,
    'cash_bank', (select coalesce(sum(jl.debit_paise - jl.credit_paise), 0) from journal_lines jl join journals j on j.id = jl.journal_id
                  join accounts a on a.code = jl.account_code
                  where a.cash_flow = 'cash' and j.status in ('posted', 'reversed') and jl.journal_date <= p_date and (p_demo or not jl.is_demo)),
    'customers_owe', v_cust.owed, 'customers_overdue', v_cust.overdue, 'customers_over_90', v_cust.over_90, 'customers_n', v_cust.n,
    'suppliers_owed', v_sup.owed, 'suppliers_overdue', v_sup.overdue, 'suppliers_n', v_sup.n,
    'stock_value', (select coalesce(sum(value_paise), 0) from rb_stock_on_hand(p_date)),
    'loans_owed', (select coalesce(sum(b.owed), 0) from loans l cross join lateral rb_ll_bal(l.id, null, p_date) b
                   where l.status in ('active', 'closed', 'ended') and (p_demo or not l.is_demo)),
    'expenses_mtd', (select coalesce(sum(jl.debit_paise - jl.credit_paise), 0) from journal_lines jl join journals j on j.id = jl.journal_id
                     where jl.account_code like '8%' and j.status in ('posted', 'reversed') and j.source <> 'year_end'
                       and jl.journal_date between v_m and p_date and (p_demo or not jl.is_demo)),
    'daily', (select coalesce(jsonb_agg(jsonb_build_object('d', g::date, 'net', coalesce(s.net, 0)) order by g), '[]')
              from generate_series(p_date - 29, p_date, interval '1 day') g
              left join (select d, sum(net) net from rb_tmp_sales group by d) s on s.d = g::date),
    'monthly', (select coalesce(jsonb_agg(jsonb_build_object('m', g::date, 'net', coalesce(s.net, 0),
                  'margin', case when v_margin then coalesce(s.net - s.cost, 0) end) order by g), '[]')
                from generate_series(v_12, v_m, interval '1 month') g
                left join (select date_trunc('month', d)::date m, sum(net) net, sum(cost) cost from rb_tmp_sales group by 1) s on s.m = g::date),
    'by_channel', (select coalesce(jsonb_agg(jsonb_build_object('k', channel, 'net', net) order by net desc), '[]')
                   from (select channel, sum(net) net from rb_tmp_sales where d >= v_m group by 1) z),
    'by_kind', (select coalesce(jsonb_agg(jsonb_build_object('k', customer_kind, 'net', net) order by net desc), '[]')
                from (select customer_kind, sum(net) net from rb_tmp_sales where d >= v_m group by 1) z),
    'top_products', (select coalesce(jsonb_agg(jsonb_build_object('item', item, 'net', net,
                       'margin', case when v_margin then net - cost end) order by net desc), '[]')
                     from (select item, sum(net) net, sum(cost) cost from rb_tmp_sales where d >= v_m group by 1 order by 2 desc limit 8) z),
    'sheets_copy', (select jsonb_build_object('at', at, 'status', status, 'rows', rows, 'detail', detail)
                    from backup_log where kind = 'sheets' order by at desc limit 1),
    'links', (select jsonb_build_object('looker_url', looker_url, 'report_sheet_url', report_sheet_url) from app_settings where id = 1));
  return v;
end $$;

-- Sales lines for the Sales report (margin only with the margin right).
create or replace function rb_report_sales(p_from date, p_to date, p_demo boolean default true)
returns table (d date, channel text, customer_kind text, item text, net_paise bigint, cost_paise bigint, margin_paise bigint)
language plpgsql stable security definer set search_path = public as $$
declare v_margin boolean;
begin
  perform rb_rp_require();
  if p_from is null or p_to is null or p_from > p_to then raise exception 'Please choose a From date on or before the To date.'; end if;
  v_margin := rb_has('reports.margin') or rb_has('accounts.view');
  return query
  select s.d, s.channel, s.customer_kind, s.item, sum(s.net)::bigint,
         case when v_margin then sum(s.cost)::bigint end, case when v_margin then sum(s.net - s.cost)::bigint end
  from rb_rp_sales(p_from, p_to, p_demo) s group by 1, 2, 3, 4 order by 1, 4;
end $$;

-- Purchase bills by supplier and item.
create or replace function rb_report_purchases(p_from date, p_to date, p_demo boolean default true)
returns table (bill_date date, ref text, supplier text, item text, unit text, qty numeric, taxable_paise bigint, gst_paise bigint, is_demo boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  perform rb_rp_require();
  if p_from is null or p_to is null or p_from > p_to then raise exception 'Please choose a From date on or before the To date.'; end if;
  return query
  select coalesce(p.bill_date, p.purchase_date, p.po_date), coalesce(nullif(p.bill_no, ''), p.po_no), s.name, i.name, l.unit_code,
         coalesce(l.bill_qty, l.received_qty), coalesce(l.bill_taxable_paise, 0)::bigint, coalesce(l.bill_gst_paise, 0)::bigint, p.is_demo
  from purchase_lines l join purchases p on p.id = l.purchase_id join suppliers s on s.id = p.supplier_id join items i on i.id = l.item_id
  where p.bill_journal_id is not null and p.status not in ('cancelled', 'refused')
    and coalesce(p.bill_date, p.purchase_date, p.po_date) between p_from and p_to and (p_demo or not p.is_demo)
  order by 1, 2, l.line_no;
end $$;

-- Links shown on the Reports screen (Director or FC).
create or replace function rb_save_report_links(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := rb_require('settings.edit', 'change the report links'); v_url text := nullif(trim(p->>'looker_url'), '');
begin
  if v_url is not null and v_url !~ '^https://(lookerstudio|datastudio)\.google\.com/' then
    raise exception 'The Looker Studio link must start with https://lookerstudio.google.com/';
  end if;
  if v_url is not null then v_url := regexp_replace(v_url, '^https://(lookerstudio|datastudio)\.google\.com/(u/\d+/)?reporting/', 'https://lookerstudio.google.com/embed/reporting/'); end if;
  update app_settings set looker_url = v_url, updated_at = now(), updated_by = v_me where id = 1;
  perform rb_audit_write('REPORT_LINKS', 'app_settings', '1', null, jsonb_build_object('looker_url', v_url), null);
end $$;

-- ---------------------------------------------------------------------
-- 10. Weekly copy to Google Sheets (called by the Apps Script)
-- ---------------------------------------------------------------------

create or replace function rb_sheets_datasets()
returns setof text language plpgsql stable security definer set search_path = public as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then perform rb_require('power.backup_now', 'copy the data to Google Sheets'); end if;
  return query select unnest(array['accounts', 'monthly_balances', 'sales_lines', 'purchase_lines', 'expenses', 'loans']);
end $$;

-- One page of a dataset as rows of plain values (amounts in rupees).
create or replace function rb_sheets_rows(p_name text, p_offset int default 0, p_limit int default 1000)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb; v_lim int := least(greatest(p_limit, 1), 5000); v_off int := greatest(p_offset, 0);
begin
  if coalesce(auth.role(), '') <> 'service_role' then perform rb_require('power.backup_now', 'copy the data to Google Sheets'); end if;
  if p_name = 'accounts' then
    select coalesce(jsonb_agg(r), '[]') into v from (
      select a.code account_code, coalesce(a.local_name, a.name) account_name, a.statement, a.cash_flow, rb_fs_line(a.code) fs_line,
             l.name fs_line_name, l.section fs_section
      from accounts a left join fs_lines l on l.code = rb_fs_line(a.code)
      where a.level = 'posting' and a.e002_active order by a.code limit v_lim offset v_off) r;
  elsif p_name = 'monthly_balances' then
    select coalesce(jsonb_agg(r), '[]') into v from (
      select to_char(date_trunc('month', jl.journal_date), 'YYYY-MM-DD') as month, jl.account_code, coalesce(a.local_name, a.name) account_name,
             rb_fs_line(jl.account_code) fs_line, d.code department, j.source,
             round(sum(jl.debit_paise) / 100.0, 2) debit, round(sum(jl.credit_paise) / 100.0, 2) credit,
             round(sum(jl.debit_paise - jl.credit_paise) / 100.0, 2) net, jl.is_demo
      from journal_lines jl join journals j on j.id = jl.journal_id join accounts a on a.code = jl.account_code
      left join departments d on d.id = jl.department_id
      where j.status in ('posted', 'reversed')
      group by 1, 2, 3, 4, 5, 6, jl.is_demo order by 1, 2, 5, 6, jl.is_demo limit v_lim offset v_off) r;
  elsif p_name = 'sales_lines' then
    select coalesce(jsonb_agg(r), '[]') into v from (
      select * from (
        select to_char(s.invoice_date, 'YYYY-MM-DD') date, s.invoice_no doc_no, 'sale' kind, s.channel, c.name customer, c.kind customer_kind,
               i.name item, l.qty_base qty, i.base_unit unit, round(l.taxable_paise / 100.0, 2) net,
               round((l.cgst_paise + l.sgst_paise + l.igst_paise) / 100.0, 2) gst, round(l.cost_paise / 100.0, 2) cost,
               round((l.taxable_paise - l.cost_paise) / 100.0, 2) margin, s.is_demo, s.id sid, l.id lid
        from sale_lines l join sales s on s.id = l.sale_id join customers c on c.id = s.customer_id join items i on i.id = l.item_id
        where s.status <> 'cancelled'
        union all
        select to_char(r.return_date, 'YYYY-MM-DD'), coalesce(r.return_no, s.invoice_no), 'return', s.channel, c.name, c.kind, i.name, -x.qty_base, i.base_unit,
               round(-x.taxable_paise / 100.0, 2), round(-(x.cgst_paise + x.sgst_paise + x.igst_paise) / 100.0, 2),
               round(-(case when r.condition = 'restock' then x.cost_paise else 0 end) / 100.0, 2),
               round(-(x.taxable_paise - case when r.condition = 'restock' then x.cost_paise else 0 end) / 100.0, 2), r.is_demo, r.id + 1000000000, x.id
        from sales_return_lines x join sales_returns r on r.id = x.return_id join sale_lines l on l.id = x.sale_line_id
        join sales s on s.id = r.sale_id join customers c on c.id = s.customer_id join items i on i.id = l.item_id
        where r.status = 'posted') z
      order by date, sid, lid limit v_lim offset v_off) r;
    v := (select coalesce(jsonb_agg(e - 'sid' - 'lid'), '[]') from jsonb_array_elements(v) e);
  elsif p_name = 'purchase_lines' then
    select coalesce(jsonb_agg(r), '[]') into v from (
      select to_char(coalesce(p.bill_date, p.purchase_date, p.po_date), 'YYYY-MM-DD') date, coalesce(nullif(p.bill_no, ''), p.po_no) doc_no,
             s.name supplier, i.name item, coalesce(l.bill_qty, l.received_qty) qty, l.unit_code unit,
             round(coalesce(l.bill_taxable_paise, 0) / 100.0, 2) taxable, round(coalesce(l.bill_gst_paise, 0) / 100.0, 2) gst, p.is_demo
      from purchase_lines l join purchases p on p.id = l.purchase_id join suppliers s on s.id = p.supplier_id join items i on i.id = l.item_id
      where p.bill_journal_id is not null and p.status not in ('cancelled', 'refused')
      order by 1, p.id, l.line_no limit v_lim offset v_off) r;
  elsif p_name = 'expenses' then
    select coalesce(jsonb_agg(r), '[]') into v from (
      select to_char(e.expense_date, 'YYYY-MM-DD') date, e.expense_no doc_no, e.direction, c.name category, e.account_code, d.code department,
             e.description, round(e.amount_paise / 100.0, 2) amount, round(e.gst_paise / 100.0, 2) gst, e.payment_mode, e.status, e.is_demo
      from expenses e join expense_categories c on c.id = e.category_id left join departments d on d.id = e.department_id
      where e.status in ('posted', 'reversed')
      order by e.expense_date, e.id limit v_lim offset v_off) r;
  elsif p_name = 'loans' then
    select coalesce(jsonb_agg(r), '[]') into v from (
      select l.loan_no, l.kind, l.name, l.lender, l.status, to_char(l.start_date, 'YYYY-MM-DD') start_date,
             coalesce(l.effective_rate, l.annual_rate) rate, round(b.owed / 100.0, 2) owed, round(b.accrued / 100.0, 2) interest_accrued,
             round(rb_rp_current_maturities_one(l.id, current_date) / 100.0, 2) due_within_12_months, l.is_demo
      from loans l cross join lateral rb_ll_bal(l.id, null, current_date) b
      where l.status <> 'draft' order by l.id limit v_lim offset v_off) r;
  else
    raise exception 'Unknown dataset %.', p_name;
  end if;
  return v;
end $$;

-- Principal of one loan due within 12 months (for the Sheets copy).
create or replace function rb_rp_current_maturities_one(p_loan bigint, p_date date)
returns bigint language sql stable security definer set search_path = public as $$
  select least(greatest(b.owed, 0), coalesce((
    select sum(s.principal_paise) from loan_schedule s left join loan_entries e on e.id = s.paid_entry_id
    where s.loan_id = p_loan and s.due_date > p_date and s.due_date <= (p_date + interval '12 months')::date
      and (s.paid_entry_id is null or e.entry_date > p_date)), 0))::bigint
  from rb_ll_bal(p_loan, null, p_date) b
$$;

-- The Apps Script records where the reporting sheet is.
create or replace function rb_set_report_sheet(p_url text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then perform rb_require('settings.edit', 'set the reporting sheet'); end if;
  if p_url !~ '^https://docs\.google\.com/spreadsheets/' then raise exception 'Not a Google Sheets link.'; end if;
  update app_settings set report_sheet_url = p_url where id = 1;
end $$;

-- ---------------------------------------------------------------------
-- 11. Row-level security and grants
-- ---------------------------------------------------------------------

alter table fs_lines enable row level security;
alter table fs_map enable row level security;
drop policy if exists fs_lines_read on fs_lines;
create policy fs_lines_read on fs_lines for select to authenticated using (rb_has('reports.view') or rb_has('accounts.view'));
drop policy if exists fs_map_read on fs_map;
create policy fs_map_read on fs_map for select to authenticated using (rb_has('reports.view') or rb_has('accounts.view'));
grant select on fs_lines, fs_map to authenticated;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure::text sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and (p.proname like 'rb\_rp\_%' or p.proname in (
             'rb_fs_line', 'rb_financial_statements', 'rb_cash_flow', 'rb_save_fs_map', 'rb_delete_fs_map', 'rb_fs_map_list',
             'rb_year_end_preview', 'rb_post_year_end', 'rb_report_dashboard', 'rb_report_sales', 'rb_report_purchases',
             'rb_save_report_links', 'rb_sheets_datasets', 'rb_sheets_rows', 'rb_set_report_sheet')) loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;
end $$;
grant execute on function
  rb_financial_statements(date, date, boolean), rb_cash_flow(date, date, boolean), rb_save_fs_map(jsonb), rb_delete_fs_map(text),
  rb_fs_map_list(), rb_year_end_preview(date), rb_post_year_end(date), rb_report_dashboard(date, boolean),
  rb_report_sales(date, date, boolean), rb_report_purchases(date, date, boolean), rb_save_report_links(jsonb),
  rb_sheets_datasets(), rb_sheets_rows(text, int, int), rb_set_report_sheet(text)
to authenticated;

-- End of 08_reports.sql
