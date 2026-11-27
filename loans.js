// =====================================================================
// RUCHI BUDS APP · loans.js · Version 1.0 · 27-Nov-2026
// Module 7 screen "Loans and leases": loans (EMI schedule, payments,
// part-payments and closing early, rate changes), finance leases under
// AS 19 (asset and liability at the start, payments split into finance
// charge and repayment, depreciation), operating leases (rent spread
// evenly, deposits, each month's rent entered as an expense), the
// month-end step, the summary with what falls due within 12 months, and
// the AS 19 notes for the accounts.
// =====================================================================
(function () {
  'use strict';
  const RB = window.RB, $ = RB.$, $$ = RB.$$, esc = RB.esc;
  const L = (RB.loans = {});

  const KIND = { loan: 'Loan', finance_lease: 'Finance lease' };
  const STATUS = { draft: 'Draft (not started)', active: 'Running', closed: 'Paid off', ended: 'Ended', cancelled: 'Cancelled' };
  const BADGE = { draft: 'protected', active: 'active', closed: 'invited', ended: 'inactive', cancelled: 'inactive', posted: 'active', reversed: 'inactive' };
  const LENDER = { bank: 'Bank', nbfc: 'Finance company (NBFC)', related: 'Partner or related party', other: 'Other' };
  const METHOD = { emi: 'Equal instalments (EMI)', equal_principal: 'Equal principal plus interest', bullet: 'Interest only, all repaid at the end' };
  const FREQ = { 1: 'Monthly', 3: 'Quarterly', 6: 'Half-yearly', 12: 'Yearly' };
  const ENTRY = { start: 'Start', takeon: 'Brought in (take-on)', payment: 'Payment', prepayment: 'Part-payment or paid off', month_end: 'Month-end',
    deposit_paid: 'Deposit paid', deposit_returned: 'Deposit returned', lease_end: 'Lease ended' };
  const MODES = { bank: 'Bank', upi: 'UPI', cash: 'Cash', credit: 'Credit (pay later)' };
  const LOAN_ACCOUNTS = [['', 'Automatic (by lender and length)'], ['40010105', '40010105 Long-term bank loans'], ['40010110', '40010110 Other long-term borrowings'],
    ['40010120', '40010120 Related-party loans (partners, family)'], ['30060110', '30060110 Short-term bank borrowings'], ['30060135', '30060135 Other short-term financing']];
  const ASSETS = [['20010125', 'Kitchen and production equipment'], ['20010120', 'Plant and machinery'], ['20010145', 'Vehicles'],
    ['20010130', 'Office equipment'], ['20010135', 'Computers'], ['20010140', 'Furniture and fixtures'], ['20010110', 'Buildings'],
    ['20010115', 'Leasehold improvements']];
  const BANDS = ['Within 1 year', '1 to 5 years', 'After 5 years'];

  const on = (root, sel, fn, ev) => { const b = $(sel, root); if (b) b.addEventListener(ev || 'click', fn); };
  const amt = (p) => (p == null || Number(p) === 0 ? '' : RB.rupees(p));
  const badge = (s, map) => RB.badge(BADGE[s] || 'invited', (map || STATUS)[s] || s);
  const fact = (label, value) => '<div><small>' + esc(label) + '</small><b>' + value + '</b></div>';
  const lastMonth = () => { const t = RB.today(); const y = Number(t.slice(0, 4)), m = Number(t.slice(5, 7)); return m === 1 ? (y - 1) + '-12-01' : y + '-' + String(m - 1).padStart(2, '0') + '-01'; };
  const monthName = (m) => RB.fmtDate(m).replace(/^\d+-/, '');
  const pct = (v) => (v == null ? '' : Number(v).toLocaleString('en-IN', { maximumFractionDigits: 4 }) + '%');
  const num = (v) => { const s = String(v == null ? '' : v).replace(/[,\s%]/g, ''); if (s === '') return null; const n = Number(s); if (!isFinite(n)) throw new Error('"' + v + '" is not a number.'); return n; };
  const int = (v) => { const n = num(v); return n == null ? null : Math.round(n); };
  const val = (root, sel) => { const e = $(sel, root); return e ? e.value : ''; };
  const ticked = (root, sel) => { const e = $(sel, root); return !!(e && e.checked); };
  const fyStart = () => { const t = RB.today(); const y = Number(t.slice(0, 4)), m = Number(t.slice(5, 7)); return (m >= 4 ? y : y - 1) + '-04-01'; };
  const askReason = (title, explain, withDate) => RB.cashbank.askReason(title, explain, withDate);
  const canTotals = () => RB.has('loans.view') || RB.has('accounts.view');

  async function lists() {
    const d = await RB.masters.load(['departments', 'suppliers']);
    const [accts, cats] = await Promise.all([
      RB.select('money_accounts', '*', (x) => x.order('sort')),
      RB.select('expense_categories', '*', (x) => x.eq('direction', 'out').order('sort')),
    ]);
    d.accts = accts; d.acct = Object.fromEntries(accts.map((a) => [a.id, a]));
    d.cats = cats; d.cat = Object.fromEntries(cats.map((c) => [c.id, c]));
    d.depts = d.departments.filter((x) => x.is_active && !x.merged_into).map((x) => [x.id, x.code + ' ' + x.name]);
    d.deptByCode = (code) => { const k = d.departments.find((x) => x.code === code && x.is_active); return k ? k.id : ''; };
    d.acctOpts = (kind, cur) => d.accts.filter((a) => (!kind || a.kind === kind) && (a.is_active || a.id === cur)).map((a) => [a.id, a.name]);
    d.defaultBank = (d.accts.find((a) => a.kind === 'bank' && a.is_default && a.is_active) || d.accts.find((a) => a.kind === 'bank' && a.is_active) || {}).id;
    return d;
  }

  function tabs(body, list) {
    body.innerHTML = '<div class="tabs">' + list.map(([k, t]) => '<button data-tab="' + k + '">' + t + '</button>').join('') + '</div><div id="tab-body"></div>';
    const show = async (k) => {
      L.tab = k;
      $$('.tabs button', body).forEach((b) => b.classList.toggle('on', b.dataset.tab === k));
      // A fresh box for each showing, so a slower earlier load cannot draw over the tab now chosen.
      const tb = document.createElement('div'); tb.innerHTML = '<p class="muted">Loading…</p>';
      $('#tab-body', body).replaceChildren(tb);
      try { await list.find((x) => x[0] === k)[2](tb); } catch (e) { tb.innerHTML = '<div class="msg error">' + esc(e.message) + '</div>'; }
    };
    $$('.tabs button', body).forEach((b) => b.addEventListener('click', () => show(b.dataset.tab)));
    L.reload = () => show(L.tab);
    show(L.tab && list.some((x) => x[0] === L.tab) ? L.tab : list[0][0]);
  }
  const reload = () => (L.reload ? L.reload() : RB.route());

  // ===================================================================
  // The screen
  // ===================================================================
  RB.screens.loans = async (body) => {
    const tools = $('#page-tools');
    if (tools) {
      tools.innerHTML = RB.has('loans.add') ? '<button class="primary" id="ll-new">+ Loan</button><button id="ll-fl">+ Finance lease</button><button id="ll-ol">+ Rented premises</button>' : '';
      on(tools, '#ll-new', () => loanForm('loan'));
      on(tools, '#ll-fl', () => loanForm('finance_lease'));
      on(tools, '#ll-ol', () => olForm());
    }
    const list = [['summary', 'Summary', summaryTab], ['loans', 'Loans', (tb) => listTab(tb, 'loan')],
      ['fl', 'Finance leases', (tb) => listTab(tb, 'finance_lease')], ['ol', 'Rent (operating leases)', olTab]];
    if (RB.has('power.month_end') || RB.has('accounts.view')) list.push(['monthend', 'Month-end', monthEndTab]);
    if (canTotals()) list.push(['as19', 'AS 19 notes', as19Tab]);
    tabs(body, list);
  };

  // ===================================================================
  // Summary: what is owed, and what falls due within 12 months
  // ===================================================================
  async function summaryTab(tb) {
    tb.innerHTML = '<div class="row" style="align-items:flex-end">' + RB.field('sm-date', 'As at', '<input type="date" id="sm-date" value="' + (L.smDate || RB.today()) + '">') +
      '<div class="field" style="flex:0 1 auto"><button id="sm-go">Show</button> <button id="sm-xls">Download to Excel</button></div></div><div id="sm-body"></div>';
    let grid;
    const load = async () => {
      L.smDate = $('#sm-date', tb).value;
      const x = await RB.rpc('rb_loans_summary', { p_as_of: L.smDate });
      const live = x.loans.filter((l) => l.status !== 'draft');
      const sum = (k, f) => live.filter(f || (() => true)).reduce((s, l) => s + Number(l[k] || 0), 0);
      const box = $('#sm-body', tb);
      box.innerHTML = '<div class="row facts card">' + fact('Loans owed', RB.rupees(sum('owed_paise', (l) => l.kind === 'loan'))) +
        fact('Finance lease liability', RB.rupees(sum('owed_paise', (l) => l.kind === 'finance_lease'))) +
        fact('Interest accrued, not yet paid', RB.rupees(sum('accrued_paise'))) +
        fact('Due within 12 months', '<span style="font-size:1.2rem">' + RB.rupees(sum('within_12_paise')) + '</span>') +
        fact('Due after 12 months', RB.rupees(sum('owed_paise') - sum('within_12_paise'))) + '</div>' +
        '<p class="muted">In the balance sheet, the part due within 12 months is shown under current liabilities (current maturities of long-term borrowings and of finance lease obligations); the rest is non-current. Tap a line to open it.</p>' +
        '<div class="card"><h2>Loans and finance leases</h2><div id="sm-grid"></div></div>' +
        '<div class="card"><h2>Rented premises and equipment (operating leases)</h2><div id="sm-ol"></div></div>';
      grid = RB.grid($('#sm-grid', box), [
        { title: 'No.', field: 'loan_no', width: 140, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
        { title: 'Kind', field: 'kind', formatter: (c) => esc(KIND[c.getValue()]) },
        { title: 'What for', field: 'name', minWidth: 200 },
        { title: 'Lender', field: 'lender' },
        { title: 'Rate', field: 'annual_rate', hozAlign: 'right', formatter: (c) => { const r = c.getRow().getData(); return pct(r.kind === 'finance_lease' && r.effective_rate != null ? Number(r.effective_rate).toFixed(2) : c.getValue()); } },
        { title: 'Owed', field: 'owed_paise', hozAlign: 'right', formatter: (c) => RB.rupees(c.getValue()) },
        { title: 'Interest accrued', field: 'accrued_paise', hozAlign: 'right', formatter: (c) => amt(c.getValue()) },
        { title: 'Due within 12 months', field: 'within_12_paise', hozAlign: 'right', formatter: (c) => RB.rupees(c.getValue()) },
        { title: 'After 12 months', field: 'after', hozAlign: 'right', mutator: (v, r) => Number(r.owed_paise) - Number(r.within_12_paise), formatter: (c) => RB.rupees(c.getValue()) },
        { title: 'Next due', field: 'next', formatter: (c) => { const n = c.getRow().getData().next_due; return n ? RB.fmtDate(n.due_date) + ' · ' + RB.rupees(n.payment_paise) : ''; } },
        { title: 'Overdue', field: 'overdue', formatter: (c) => (Number(c.getValue()) ? RB.badge('locked', c.getValue() + ' overdue') : '') },
        { title: 'Status', field: 'status', formatter: (c) => badge(c.getValue()) },
      ], x.loans);
      grid.on('rowClick', (e, row) => loanWindow(row.getData().id));
      const og = RB.grid($('#sm-ol', box), [
        { title: 'No.', field: 'lease_no', width: 140, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
        { title: 'What', field: 'name', minWidth: 200 },
        { title: 'Landlord', field: 'lessor' },
        { title: 'Ends', field: 'end_date', formatter: (c) => RB.fmtDate(c.getValue()) },
        { title: 'Rent now', field: 'rent_now_paise', hozAlign: 'right', formatter: (c) => RB.rupees(c.getValue()) },
        { title: 'Charged each month', field: 'straight_line_paise', hozAlign: 'right', formatter: (c) => (c.getRow().getData().basis === 'as_paid' ? 'as paid' : RB.rupees(c.getValue())) },
        { title: 'Rent equalisation', field: 'equalisation_paise', hozAlign: 'right', formatter: (c) => amt(c.getValue()) },
        { title: 'Deposit held', field: 'deposit_paise', hozAlign: 'right', formatter: (c) => amt(c.getValue()) },
        { title: 'Rent not entered', field: 'rent_not_entered', formatter: (c) => (Number(c.getValue()) ? RB.badge('protected', c.getValue() + ' month(s)') : '') },
        { title: 'Status', field: 'status', formatter: (c) => badge(c.getValue()) },
      ], x.op_leases);
      og.on('rowClick', (e, row) => olWindow(row.getData().id));
    };
    on(tb, '#sm-go', () => load().catch((e) => RB.toast(e.message, true)));
    on(tb, '#sm-xls', () => grid && RB.downloadExcel(grid, 'Loans and leases'));
    await load();
  }

  // ===================================================================
  // Loans / finance leases list
  // ===================================================================
  async function listTab(tb, kind) {
    const x = await RB.rpc('rb_loans_summary', { p_as_of: RB.today() });
    const rows = x.loans.filter((l) => l.kind === kind);
    tb.innerHTML = '<div class="actions" style="margin:0 0 .75rem">' + (RB.has('loans.add') ? '<button class="primary" id="lt-add">' +
      (kind === 'loan' ? '+ Loan' : '+ Finance lease') + '</button>' : '') + '</div>' +
      '<p class="muted">' + (kind === 'loan'
        ? 'Bank loans, loans from partners or anyone else. Each has its EMI schedule. A new loan is a draft until the Accountant, the FC or a Director starts it.'
        : 'A lease that passes almost all the risks and rewards of the asset to the firm (AS 19): for example a van or a machine on a lease for most of its life. The asset and the lease liability are both in the books. For rented premises, use <b>+ Rented premises</b>.') +
      ' Tap a line to open it.</p><div id="lt-grid"></div>';
    const grid = RB.grid($('#lt-grid', tb), [
      { title: 'No.', field: 'loan_no', width: 140, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
      { title: 'What for', field: 'name', minWidth: 200 },
      { title: kind === 'loan' ? 'Lender' : 'Lessor', field: 'lender' },
      { title: 'Rate', field: 'annual_rate', hozAlign: 'right', formatter: (c) => { const r = c.getRow().getData(); return pct(r.kind === 'finance_lease' && r.effective_rate != null ? Number(r.effective_rate).toFixed(2) : c.getValue()); } },
      { title: kind === 'loan' ? 'EMI' : 'Payment', field: 'emi_paise', hozAlign: 'right', formatter: (c) => amt(c.getValue()) },
      { title: 'Owed', field: 'owed_paise', hozAlign: 'right', formatter: (c) => RB.rupees(c.getValue()) },
      { title: 'Next due', field: 'next', formatter: (c) => { const n = c.getRow().getData().next_due; return n ? RB.fmtDate(n.due_date) : ''; } },
      { title: 'Status', field: 'status', formatter: (c) => badge(c.getValue()) },
    ], rows);
    grid.on('rowClick', (e, row) => loanWindow(row.getData().id));
    on(tb, '#lt-add', () => loanForm(kind));
  }

  // ===================================================================
  // New loan or finance lease (or change a draft)
  // ===================================================================
  async function loanForm(kind, old) {
    const d = await lists();
    const lease = kind === 'finance_lease';
    const v = old || { start_date: RB.today(), frequency_months: 1, rate_type: 'fixed', method: 'emi', lender_type: lease ? 'nbfc' : 'bank', in_advance: true,
      money_account_id: d.defaultBank, department_id: d.deptByCode(lease ? 'CC001' : 'CC005') };
    const kitchen = old ? old.dep_account === '70030115' : true;
    const money = (p) => (p == null ? '' : RB.fromPaise(p));
    const m = RB.modal('<h2>' + (old ? 'Change ' + esc(old.loan_no) : lease ? 'New finance lease' : 'New loan') + '</h2><div class="m-msg"></div>' +
      '<label class="check"><input type="checkbox" id="lf-takeon"' + (v.is_takeon ? ' checked' : '') + '> ' + (lease ? 'This lease' : 'This loan') +
      ' was already running before the app (bring in its balances)</label>' +
      '<div class="row">' + RB.field('lf-name', lease ? 'What it is' : 'What the loan is for', RB.inp('lf-name', v.name, ' placeholder="' + (lease ? 'e.g. Delivery van lease' : 'e.g. Kitchen equipment loan') + '"'), null, true) +
      RB.field('lf-lender', lease ? 'Lessor (leasing company)' : 'Lender', RB.inp('lf-lender', v.lender, ' placeholder="' + (lease ? 'e.g. Sai Leasing' : 'e.g. State Bank of India, Andheri') + '"'), null, true) + '</div>' +
      (lease ? '' : '<div class="row">' + RB.field('lf-type', 'Who lent it', RB.sel('lf-type', Object.entries(LENDER), v.lender_type)) +
        RB.field('lf-acc', 'Kept in account', RB.sel('lf-acc', LOAN_ACCOUNTS, old ? v.account_code : ''), 'Automatic: over 12 months from a bank → long-term bank loans; from a partner → related-party loans.') + '</div>') +
      (lease ? '<div class="row">' + RB.field('lf-asset', 'The asset', RB.inp('lf-asset', v.asset_name, ' placeholder="e.g. Tata Ace delivery van"'), null, true) +
        RB.field('lf-aacc', 'Kind of asset', RB.sel('lf-aacc', ASSETS, v.asset_account || '20010125'), null, true) + '</div>' +
        '<label class="check"><input type="checkbox" id="lf-kitchen"' + (kitchen ? ' checked' : '') + '> Used in the kitchen to make the products (its depreciation is part of stock cost, AS 2)</label>' : '') +
      '<div class="row">' + RB.field('lf-start', lease ? 'Lease starts' : 'Money received on', '<input type="date" id="lf-start" value="' + esc(v.start_date || '') + '">', null, true) +
      '<div class="field ll-takeon"><label for="lf-tdate">Take-on date <span class="req">*</span></label><input type="date" id="lf-tdate" value="' + esc(v.takeon_date || '') + '"><div class="hint">The date the balances below are at, usually the day the app starts.</div></div></div>' +
      '<div class="row">' +
      (lease ? '<div class="field ll-new"><label for="lf-fv">Fair value of the asset (₹) <span class="req">*</span></label>' + RB.inp('lf-fv', money(v.fair_value_paise), ' inputmode="decimal"') + '<div class="hint">Its cash price on the start date.</div></div>' : '') +
      '<div class="field ' + (lease ? 'll-takeon' : '') + '"><label for="lf-amt" id="lf-amt-l">' + (lease ? 'Lease liability still owed (₹)' : 'Amount borrowed (₹)') + ' <span class="req">*</span></label>' + RB.inp('lf-amt', money(v.principal_paise), ' inputmode="decimal"') + '</div>' +
      RB.field('lf-rate', 'Interest rate (% a year)', RB.inp('lf-rate', v.annual_rate == null ? '' : v.annual_rate, ' inputmode="decimal"'),
        lease ? 'Leave blank to work out the rate implicit in the lease from the fair value. Or give the rate in the lease, or the rate the firm would pay to borrow.' : null) +
      (lease ? '' : RB.field('lf-rtype', 'Rate', RB.sel('lf-rtype', [['fixed', 'Fixed'], ['floating', 'Floating (can change)']], v.rate_type))) + '</div>' +
      '<div class="row">' + (lease ? '' : RB.field('lf-method', 'Repaid by', RB.sel('lf-method', Object.entries(METHOD), v.method))) +
      RB.field('lf-freq', 'Paid', RB.sel('lf-freq', Object.entries(FREQ), v.frequency_months)) +
      '<div class="field"><label for="lf-n" id="lf-n-l">Number of instalments <span class="req">*</span></label>' + RB.inp('lf-n', v.instalments, ' inputmode="numeric"') + '</div></div>' +
      '<div class="row">' + RB.field('lf-emi', lease ? 'Each lease payment (₹)' : 'EMI from the bank (₹)', RB.inp('lf-emi', money(v.emi_paise), ' inputmode="decimal"'),
        lease ? null : 'Optional. Leave blank to work it out; type the bank\'s figure if it differs.', lease) +
      (lease ? RB.field('lf-adv', 'Payments made', RB.sel('lf-adv', [['true', 'In advance (the first on the start date)'], ['false', 'In arrears (at the end of each period)']], String(v.in_advance !== false))) : '') +
      '<div class="field" id="lf-first-f"><label for="lf-first" id="lf-first-l">First instalment due</label><input type="date" id="lf-first" value="' + esc(v.first_due_date || '') + '"><div class="hint" id="lf-first-h">Blank: one period after the start.</div></div></div>' +
      '<div class="row ll-takeon">' + RB.field('lf-accr', 'Interest accrued but not yet due on the take-on date (₹)', RB.inp('lf-accr', money(v.takeon_accrued_paise), ' inputmode="decimal" placeholder="0"'),
        'From the last instalment date to the take-on date. It is cleared by the next instalment.') + '</div>' +
      (lease ? '<div class="row">' + RB.field('lf-res', 'Guaranteed residual value (₹)', RB.inp('lf-res', money(v.residual_paise), ' inputmode="decimal" placeholder="0"'), 'Only if the firm guarantees a value at the end.') +
        RB.field('lf-life', 'Useful life of the asset (months)', RB.inp('lf-life', v.useful_life_months, ' inputmode="numeric"'), null, true) +
        RB.field('lf-salv', 'Value left at the end of its use (₹)', RB.inp('lf-salv', money(v.salvage_paise), ' inputmode="decimal" placeholder="0"')) + '</div>' +
        '<label class="check"><input type="checkbox" id="lf-own"' + (v.ownership_transfers ? ' checked' : '') + '> The asset becomes the firm\'s own at the end (or there is a bargain purchase option): depreciate over its useful life</label>' +
        '<div class="row ll-new">' + RB.field('lf-idc', 'Initial direct costs (₹)', RB.inp('lf-idc', money(v.direct_costs_paise), ' inputmode="decimal" placeholder="0"'), 'Paid by the firm to arrange the lease (added to the asset).') + '</div>' +
        '<div class="row ll-takeon">' + RB.field('lf-cost', 'Cost the asset was recorded at (₹)', RB.inp('lf-cost', money(v.asset_cost_paise), ' inputmode="decimal"'), null, true) +
        RB.field('lf-accdep', 'Depreciation to the take-on date (₹)', RB.inp('lf-accdep', money(v.takeon_acc_dep_paise), ' inputmode="decimal"'), null, true) +
        RB.field('lf-depm', 'Months of depreciation still to go', RB.inp('lf-depm', v.dep_months, ' inputmode="numeric"'), null, true) + '</div>' : '') +
      '<div class="row">' + (lease ? '' : '<div class="field ll-new"><label for="lf-fee">Processing fee (₹)</label>' + RB.inp('lf-fee', money(v.fee_paise), ' inputmode="decimal" placeholder="0"') + '<div class="hint">Taken from the money received; charged as a finance cost (AS 16).</div></div>') +
      '<div class="field ll-new"><label for="lf-macc">' + (lease ? 'Direct costs paid from' : 'Money received into') + '</label>' + RB.sel('lf-macc', [['', '(choose)']].concat(d.acctOpts(null, v.money_account_id)), v.money_account_id) + '</div>' +
      RB.field('lf-dept', 'Department', RB.sel('lf-dept', d.depts, v.department_id)) + '</div>' +
      RB.field('lf-note', 'Note', RB.inp('lf-note', v.note, ' placeholder="e.g. sanction letter no."')) +
      '<div id="lf-prev" class="card" style="display:none"></div>' +
      '<div class="actions"><button id="lf-preview">Show the schedule</button><button class="primary" id="lf-save">Save as draft</button><button data-close>Cancel</button></div>', { wide: true });
    const sync = () => {
      const t = ticked(m.el, '#lf-takeon');
      $$('.ll-takeon', m.el).forEach((e) => { e.style.display = t ? '' : 'none'; });
      $$('.ll-new', m.el).forEach((e) => { e.style.display = t ? 'none' : ''; });
      if (!lease) $('#lf-amt-l', m.el).innerHTML = (t ? 'Amount still owed on the take-on date (₹)' : 'Amount borrowed (₹)') + ' <span class="req">*</span>';
      $('#lf-n-l', m.el).innerHTML = (t ? 'Instalments still to pay' : 'Number of instalments') + ' <span class="req">*</span>';
      const adv = lease && val(m.el, '#lf-adv') === 'true';
      $('#lf-first-f', m.el).style.display = adv && !t ? 'none' : '';
      $('#lf-first-l', m.el).textContent = t ? 'Next instalment due' : 'First instalment due';
      $('#lf-first-h', m.el).textContent = t ? 'Needed for a take-on.' : 'Blank: one period after the start.';
    };
    ['#lf-takeon', '#lf-adv'].forEach((s) => on(m.el, s, sync, 'change')); sync();
    const read = () => {
      const t = ticked(m.el, '#lf-takeon');
      const p = { kind, name: val(m.el, '#lf-name'), lender: val(m.el, '#lf-lender'), start_date: val(m.el, '#lf-start'), is_takeon: t,
        takeon_date: t ? val(m.el, '#lf-tdate') : null, annual_rate: num(val(m.el, '#lf-rate')), frequency_months: Number(val(m.el, '#lf-freq')),
        instalments: int(val(m.el, '#lf-n')), first_due_date: val(m.el, '#lf-first') || null, emi_paise: RB.toPaise(val(m.el, '#lf-emi')),
        takeon_accrued_paise: t ? RB.toPaise(val(m.el, '#lf-accr')) : 0, money_account_id: val(m.el, '#lf-macc') ? Number(val(m.el, '#lf-macc')) : null,
        department_id: Number(val(m.el, '#lf-dept')), note: val(m.el, '#lf-note') };
      if (old) p.id = old.id;
      if (lease) {
        Object.assign(p, { asset_name: val(m.el, '#lf-asset'), asset_account: val(m.el, '#lf-aacc'), kitchen: ticked(m.el, '#lf-kitchen'),
          in_advance: val(m.el, '#lf-adv') === 'true', residual_paise: RB.toPaise(val(m.el, '#lf-res')) || 0, useful_life_months: int(val(m.el, '#lf-life')),
          salvage_paise: RB.toPaise(val(m.el, '#lf-salv')) || 0, ownership_transfers: ticked(m.el, '#lf-own') });
        if (t) Object.assign(p, { principal_paise: RB.toPaise(val(m.el, '#lf-amt')), asset_cost_paise: RB.toPaise(val(m.el, '#lf-cost')),
          takeon_acc_dep_paise: RB.toPaise(val(m.el, '#lf-accdep')), dep_months: int(val(m.el, '#lf-depm')) });
        else Object.assign(p, { fair_value_paise: RB.toPaise(val(m.el, '#lf-fv')), direct_costs_paise: RB.toPaise(val(m.el, '#lf-idc')) || 0 });
      } else {
        Object.assign(p, { principal_paise: RB.toPaise(val(m.el, '#lf-amt')), lender_type: val(m.el, '#lf-type'), account_code: val(m.el, '#lf-acc') || null,
          rate_type: val(m.el, '#lf-rtype'), method: val(m.el, '#lf-method'), fee_paise: t ? 0 : (RB.toPaise(val(m.el, '#lf-fee')) || 0) });
      }
      return p;
    };
    on(m.el, '#lf-preview', async () => {
      try {
        const x = await RB.rpc('rb_loan_preview', { p: read() });
        const box = $('#lf-prev', m.el); box.style.display = '';
        box.innerHTML = '<h3>The schedule</h3><div class="row facts">' +
          (lease ? fact('Recorded at (asset and liability)', RB.rupees(x.principal_paise)) + fact('Rate used', pct(Number(x.effective_rate).toFixed(2))) : fact('Amount', RB.rupees(x.principal_paise))) +
          fact(lease ? 'Each payment' : 'EMI', x.emi_paise ? RB.rupees(x.emi_paise) : 'varies') + fact('Instalments', x.instalments) +
          fact('Total interest', RB.rupees(x.total_interest_paise)) + fact('Total paid', RB.rupees(x.total_payments_paise)) +
          (x.account_code ? fact('Kept in', esc(x.account_code + ' ' + (x.account_name || ''))) : '') + '</div>' +
          (lease && !x.is_takeon ? '<p class="muted">Present value of the payments: ' + RB.rupees(x.pv_paise) + ' (' + esc(x.pv_pct_of_fv) + '% of the fair value). Lease term: ' +
            x.term_months + ' months (' + esc(x.term_pct_of_life) + '% of the asset\'s life). ' +
            (Number(x.pv_pct_of_fv) >= 90 || Number(x.term_pct_of_life) >= 75 || x.ownership_transfers ? 'This looks like a <b>finance lease</b> under AS 19.'
              : '<b>This may be an operating lease</b>: the payments are well below the asset\'s value and the term is short. Check with the CA; if so, enter it under + Rented premises.') +
            ' Depreciated over ' + x.dep_months + ' months.</p>' : '') +
          '<div class="grid-wrap" style="max-height:260px;overflow:auto"><table class="ticks lines"><thead><tr><th>#</th><th>Due</th><th>Owed before</th><th>Interest</th><th>Repaid</th><th>Payment</th><th>Owed after</th></tr></thead><tbody>' +
          x.rows.map((r) => '<tr><td>' + r.n + '</td><td>' + RB.fmtDate(r.due_date) + '</td><td>' + RB.rupees(r.opening_paise) + '</td><td>' + RB.rupees(r.interest_paise) + '</td><td>' +
            RB.rupees(r.principal_paise) + '</td><td>' + RB.rupees(r.payment_paise) + '</td><td>' + RB.rupees(r.closing_paise) + '</td></tr>').join('') + '</tbody></table></div>';
        RB.modalMsg(m, 'Check the schedule against the ' + (lease ? 'lease agreement' : 'bank\'s sanction letter or repayment schedule') + ', then save.', true);
      } catch (e) { RB.modalMsg(m, e.message); }
    });
    on(m.el, '#lf-save', async () => {
      try {
        const id = await RB.rpc('rb_save_loan', { p: read() });
        RB.toast('Saved as a draft'); m.close(); reload(); loanWindow(id);
      } catch (e) { RB.modalMsg(m, e.message); }
    });
  }

  // ===================================================================
  // One loan or finance lease
  // ===================================================================
  async function loanWindow(id) {
    const x = await RB.rpc('rb_loan_detail', { p_id: id });
    const v = x.loan, lease = v.kind === 'finance_lease', st = v.status;
    const next = x.schedule.find((s) => !s.paid_entry_id);
    const mine = RB.profile && v.entered_by === RB.profile.id;
    const lastEntry = x.entries.filter((e) => e.status === 'posted' && e.kind !== 'month_end').slice(-1)[0];
    const onlyStart = x.entries.filter((e) => e.status === 'posted').length === 1 && lastEntry && ['start', 'takeon'].includes(lastEntry.kind);
    const m = RB.modal('<h2>' + esc(v.loan_no) + RB.demoBadge(v) + ' ' + badge(st) + '</h2><div class="m-msg"></div>' +
      '<p><b>' + esc(v.name) + '</b>, ' + esc(lease ? 'leased from ' : 'from ') + esc(v.lender) + (lease ? ': ' + esc(v.asset_name) : '') + '</p>' +
      '<div class="row facts">' + fact(lease ? 'Lease liability' : 'Owed', '<span style="font-size:1.2rem">' + RB.rupees(x.owed_paise) + '</span>') +
      fact('Interest accrued (to the last month-end)', RB.rupees(x.accrued_paise)) +
      fact('Rate', pct(lease ? Number(v.effective_rate).toFixed(2) : v.annual_rate) + (v.rate_type === 'floating' ? ' floating' : '')) +
      fact(lease ? 'Each payment' : 'EMI', v.emi_paise ? RB.rupees(v.emi_paise) : METHOD[v.method]) +
      fact('Next due', next ? RB.fmtDate(next.due_date) + ' · ' + RB.rupees(next.payment_paise) : '—') +
      (lease ? fact('Asset at cost / value now', RB.rupees(x.asset_paise) + ' / ' + RB.rupees(x.carrying_paise)) : '') + '</div>' +
      '<table class="kv"><tr><td>' + (v.is_takeon ? 'Started / brought in' : 'Started') + '</td><td>' + RB.fmtDate(v.start_date) + (v.is_takeon ? ' / ' + RB.fmtDate(v.takeon_date) : '') + '</td></tr>' +
      '<tr><td>Kept in</td><td>' + esc(v.account_code + ' ' + (x.account_name || '')) + '</td></tr>' +
      '<tr><td>Instalments</td><td>' + esc(FREQ[v.frequency_months]) + ', ' + v.instalments + ' in all' + (lease ? (v.in_advance ? ', in advance' : ', in arrears') : '') + '</td></tr>' +
      (lease ? '<tr><td>Fair value / PV of payments</td><td>' + RB.rupees(v.fair_value_paise) + ' / ' + RB.rupees(v.pv_paise) + '</td></tr>' +
        '<tr><td>Depreciation</td><td>' + v.dep_months + ' months to ' + esc(v.dep_account === '70030115' ? '70030115 Production depreciation (kitchen)' : v.dep_account) +
        (v.ownership_transfers ? '; the asset becomes the firm\'s own at the end' : '; the asset goes back at the end') + '</td></tr>' : '') +
      (x.money_account ? '<tr><td>Bank account</td><td>' + esc(x.money_account) + '</td></tr>' : '') +
      (v.note ? '<tr><td>Note</td><td>' + esc(v.note) + '</td></tr>' : '') +
      (x.rate_changes.length ? '<tr><td>Rate changes</td><td>' + x.rate_changes.map((r) => RB.fmtDate(r.from_date) + ': ' + pct(r.old_rate) + ' → ' + pct(r.new_rate) + ' (' + esc(r.reason) + ')').join('<br>') + '</td></tr>' : '') +
      '</table>' +
      '<div class="actions">' +
      (st === 'draft' && (mine || RB.has('loans.edit')) ? '<button id="lw-edit">Change</button>' : '') +
      (st === 'draft' && RB.has('loans.approve') ? '<button class="primary" id="lw-start">Start (approve and post)</button>' : '') +
      (st === 'draft' && (mine || RB.has('loans.edit')) ? '<button class="danger" id="lw-del">Delete draft</button>' : '') +
      (st === 'active' && next && RB.has('loans.add') ? '<button class="primary" id="lw-pay">Pay instalment ' + next.n + '</button>' : '') +
      (st === 'active' && !lease && RB.has('loans.add') ? '<button id="lw-pre">Part-pay or pay off</button>' : '') +
      (st === 'active' && !lease && RB.has('loans.edit') ? '<button id="lw-rate">Change the rate</button>' : '') +
      (lease && ['active', 'closed'].includes(st) && !v.ownership_transfers && Number(x.owed_paise) === 0 && RB.has('loans.edit') ? '<button id="lw-end">Asset returned: end the lease</button>' : '') +
      '<button id="lw-xls">Schedule to Excel</button><button data-close>Close</button></div>' +
      '<h3>Schedule</h3><div id="lw-sched"></div>' +
      '<h3>Entries</h3><div class="grid-wrap"><table class="ticks"><thead><tr><th>Date</th><th>No.</th><th>What</th><th>Repaid / (borrowed)</th><th>Interest charged</th><th>Paid</th><th>Status</th><th></th></tr></thead><tbody>' +
      (x.entries.length ? x.entries.map((e) => '<tr><td>' + RB.fmtDate(e.entry_date) + '</td><td>' + esc(e.entry_no) + '</td><td>' + esc(ENTRY[e.kind]) + (e.schedule_n ? ' ' + e.schedule_n : '') +
        (e.reference ? '<br><small>' + esc(e.reference) + '</small>' : '') + '</td><td>' + amt(-e.principal_paise) + '</td><td>' + amt(Number(e.interest_paise) + (e.kind === 'payment' || e.kind === 'prepayment' ? -Number(e.accrued_paise) : 0)) +
        '</td><td>' + amt(-e.cash_paise) + '</td><td>' + badge(e.status) + (e.reverse_reason ? '<br><small>' + esc(e.reverse_reason) + '</small>' : '') + '</td><td>' +
        (lastEntry && e.id === lastEntry.id && RB.has('power.reverse_entries') && (e.kind !== 'start' && e.kind !== 'takeon' || onlyStart)
          ? '<button class="danger" data-rev="' + e.id + '">' + (['start', 'takeon'].includes(e.kind) ? 'Cancel ' + (lease ? 'lease' : 'loan') : 'Reverse') + '</button>' : '') + '</td></tr>').join('')
        : '<tr><td colspan="8" class="muted">Nothing posted yet.</td></tr>') + '</tbody></table></div>', { wide: true });
    const sched = RB.grid($('#lw-sched', m.el), [
      { title: '#', field: 'n', width: 60, headerFilter: false },
      { title: 'Due', field: 'due_date', formatter: (c) => RB.fmtDate(c.getValue()) },
      { title: 'Owed before', field: 'opening_paise', hozAlign: 'right', formatter: (c) => RB.rupees(c.getValue()) },
      { title: 'Interest', field: 'interest_paise', hozAlign: 'right', formatter: (c) => RB.rupees(c.getValue()) },
      { title: 'Repaid', field: 'principal_paise', hozAlign: 'right', formatter: (c) => RB.rupees(c.getValue()) },
      { title: 'Payment', field: 'payment_paise', hozAlign: 'right', formatter: (c) => RB.rupees(c.getValue()) },
      { title: 'Owed after', field: 'closing_paise', hozAlign: 'right', formatter: (c) => RB.rupees(c.getValue()) },
      { title: 'Paid', field: 'paid_on', formatter: (c) => (c.getValue() ? '✓ ' + RB.fmtDate(c.getValue()) : (c.getRow().getData().due_date < RB.today() && st === 'active' ? RB.badge('locked', 'overdue') : '')) },
    ], x.schedule, { height: 300, pagination: false });
    const act = (fn) => async () => { try { await fn(); } catch (e) { RB.modalMsg(m, e.message); } };
    on(m.el, '#lw-xls', () => RB.downloadExcel(sched, 'Schedule ' + v.loan_no));
    on(m.el, '#lw-edit', () => { m.close(); loanForm(v.kind, v); });
    on(m.el, '#lw-start', act(async () => {
      if (!(await RB.confirm('Start ' + v.loan_no + '?', v.is_takeon ? 'Brings its balances into the books at ' + RB.fmtDate(v.takeon_date) + '.'
        : lease ? 'Records the asset and the lease liability at ' + RB.rupees(v.principal_paise) + '.' : 'Posts the ' + RB.rupees(v.principal_paise) + ' received from ' + esc(v.lender) + '.'))) return;
      await RB.rpc('rb_start_loan', { p_id: id }); RB.toast('Started and posted'); m.close(); reload(); loanWindow(id);
    }));
    on(m.el, '#lw-del', act(async () => {
      if (!(await RB.confirm('Delete the draft ' + v.loan_no + '?', 'Nothing has been posted for it.'))) return;
      await RB.rpc('rb_delete_draft_loan', { p_id: id }); RB.toast('Deleted'); m.close(); reload();
    }));
    on(m.el, '#lw-pay', () => { m.close(); payModal(x, next); });
    on(m.el, '#lw-pre', () => { m.close(); prepayModal(x); });
    on(m.el, '#lw-rate', () => { m.close(); rateModal(x); });
    on(m.el, '#lw-end', act(async () => {
      const r = await askReason('End ' + v.loan_no, 'The asset goes back to the lessor. It comes out of the books; any value left is written off as depreciation.', true); if (!r) return;
      await RB.rpc('rb_end_finance_lease', { p: { loan_id: id, end_date: r.date, reason: r.reason } }); RB.toast('Lease ended'); m.close(); reload();
    }));
    $$('[data-rev]', m.el).forEach((b) => b.addEventListener('click', act(async () => {
      const r = await askReason('Reverse this entry', 'A reversing entry is posted on the date you choose. The original stays on record.', true); if (!r) return;
      await RB.rpc('rb_reverse_loan_entry', { p_id: Number(b.dataset.rev), p_date: r.date, p_reason: r.reason }); RB.toast('Reversed'); m.close(); reload(); loanWindow(id);
    })));
  }

  async function payModal(x, s) {
    const d = await lists(), v = x.loan, lease = v.kind === 'finance_lease';
    const m = RB.modal('<h2>' + esc(v.loan_no) + ': pay ' + (lease ? 'lease payment ' : 'EMI ') + s.n + ' of ' + v.instalments + '</h2><div class="m-msg"></div>' +
      '<p class="muted">Due ' + RB.fmtDate(s.due_date) + '. The split is from the schedule; change it to match the ' + (lease ? 'lessor\'s' : 'bank\'s') + ' statement if it differs. The rest of the schedule is then worked out again.</p>' +
      '<div class="row">' + RB.field('py-date', 'Paid on', '<input type="date" id="py-date" value="' + (s.due_date <= RB.today() ? s.due_date : RB.today()) + '">', null, true) +
      RB.field('py-acc', 'Paid from', RB.sel('py-acc', d.acctOpts(null, v.money_account_id), v.money_account_id || d.defaultBank), null, true) + '</div>' +
      '<div class="row">' + RB.field('py-pr', 'Repayment (₹)', RB.inp('py-pr', RB.fromPaise(s.principal_paise), ' inputmode="decimal"')) +
      RB.field('py-int', lease ? 'Finance charge (₹)' : 'Interest (₹)', RB.inp('py-int', RB.fromPaise(s.interest_paise), ' inputmode="decimal"')) +
      RB.field('py-ch', 'Late or penal charges (₹)', RB.inp('py-ch', '', ' inputmode="decimal" placeholder="0"')) + '</div>' +
      '<p>Total: <b id="py-tot"></b></p>' + RB.field('py-ref', 'Reference', RB.inp('py-ref', '', ' placeholder="ECS, NACH or cheque no."')) +
      '<div class="actions"><button class="primary" id="py-save">Save payment</button><button data-close>Cancel</button></div>');
    const tot = () => { try { $('#py-tot', m.el).textContent = RB.rupees((RB.toPaise(val(m.el, '#py-pr')) || 0) + (RB.toPaise(val(m.el, '#py-int')) || 0) + (RB.toPaise(val(m.el, '#py-ch')) || 0)); } catch (e) { /* typing */ } };
    $$('#py-pr, #py-int, #py-ch', m.el).forEach((e) => e.addEventListener('input', tot)); tot();
    on(m.el, '#py-save', async () => {
      try {
        await RB.rpc('rb_pay_loan', { p: { loan_id: v.id, pay_date: val(m.el, '#py-date'), money_account_id: Number(val(m.el, '#py-acc')),
          principal_paise: RB.toPaise(val(m.el, '#py-pr')), interest_paise: RB.toPaise(val(m.el, '#py-int')), charges_paise: RB.toPaise(val(m.el, '#py-ch')) || 0,
          reference: val(m.el, '#py-ref') } });
        RB.toast('Payment saved'); m.close(); reload(); loanWindow(v.id);
      } catch (e) { RB.modalMsg(m, e.message); }
    });
  }

  async function prepayModal(x) {
    const d = await lists(), v = x.loan;
    const m = RB.modal('<h2>' + esc(v.loan_no) + ': part-pay or pay off</h2><div class="m-msg"></div>' +
      '<p class="muted">Owed now: <b>' + RB.rupees(x.owed_paise) + '</b>. Interest accrued at the last month-end: ' + RB.rupees(x.accrued_paise) + '.</p>' +
      '<label class="check"><input type="checkbox" id="pp-all"> Pay off the whole loan</label>' +
      '<div class="row">' + RB.field('pp-date', 'Paid on', '<input type="date" id="pp-date" value="' + RB.today() + '">', null, true) +
      RB.field('pp-acc', 'Paid from', RB.sel('pp-acc', d.acctOpts(null, v.money_account_id), v.money_account_id || d.defaultBank), null, true) + '</div>' +
      '<div class="row">' + RB.field('pp-pr', 'Loan amount repaid (₹)', RB.inp('pp-pr', '', ' inputmode="decimal"'), null, true) +
      RB.field('pp-int', 'Interest to date charged by the bank (₹)', RB.inp('pp-int', '', ' inputmode="decimal" placeholder="0"'), 'Interest since the last EMI, if the bank charged it now.') +
      RB.field('pp-ch', 'Part-payment or foreclosure charges (₹)', RB.inp('pp-ch', '', ' inputmode="decimal" placeholder="0"')) + '</div>' +
      (v.method === 'emi' ? '<div class="field" id="pp-keep-f"><label>After a part-payment</label><label class="check"><input type="radio" name="pp-keep" value="emi" checked> Keep the EMI: the loan ends sooner</label>' +
        '<label class="check"><input type="radio" name="pp-keep" value="tenure"> Keep the end date: the EMI goes down</label></div>' : '') +
      RB.field('pp-ref', 'Reference', RB.inp('pp-ref', '')) +
      '<div class="actions"><button class="primary" id="pp-save">Save</button><button data-close>Cancel</button></div>');
    on(m.el, '#pp-all', () => {
      const all = ticked(m.el, '#pp-all'); $('#pp-pr', m.el).value = all ? RB.fromPaise(x.owed_paise) : ''; $('#pp-pr', m.el).disabled = all;
      const k = $('#pp-keep-f', m.el); if (k) k.style.display = all ? 'none' : '';
    }, 'change');
    on(m.el, '#pp-save', async () => {
      try {
        const k = $('input[name=pp-keep]:checked', m.el);
        await RB.rpc('rb_prepay_loan', { p: { loan_id: v.id, pay_date: val(m.el, '#pp-date'), money_account_id: Number(val(m.el, '#pp-acc')),
          close: ticked(m.el, '#pp-all'), principal_paise: RB.toPaise(val(m.el, '#pp-pr')), interest_paise: RB.toPaise(val(m.el, '#pp-int')) || 0,
          charges_paise: RB.toPaise(val(m.el, '#pp-ch')) || 0, keep: k ? k.value : 'tenure', reference: val(m.el, '#pp-ref') } });
        RB.toast(ticked(m.el, '#pp-all') ? 'Loan paid off' : 'Part-payment saved'); m.close(); reload(); loanWindow(v.id);
      } catch (e) { RB.modalMsg(m, e.message); }
    });
  }

  function rateModal(x) {
    const v = x.loan;
    const m = RB.modal('<h2>' + esc(v.loan_no) + ': new interest rate</h2><div class="m-msg"></div>' +
      '<p class="muted">Now ' + pct(v.annual_rate) + '. The instalments still to come are worked out again at the new rate.</p>' +
      '<div class="row">' + RB.field('rt-rate', 'New rate (% a year)', RB.inp('rt-rate', '', ' inputmode="decimal"'), null, true) +
      RB.field('rt-from', 'Applies from', '<input type="date" id="rt-from" value="' + RB.today() + '">', null, true) + '</div>' +
      (v.method === 'emi' ? '<div class="field"><label class="check"><input type="radio" name="rt-keep" value="emi" checked> Keep the EMI: the number of instalments changes</label>' +
        '<label class="check"><input type="radio" name="rt-keep" value="tenure"> Keep the end date: the EMI changes</label></div>' : '') +
      RB.field('rt-why', 'Reason', RB.inp('rt-why', '', ' placeholder="e.g. Bank letter of 1-Dec: repo rate change"'), null, true) +
      '<div class="actions"><button class="primary" id="rt-save">Save</button><button data-close>Cancel</button></div>');
    on(m.el, '#rt-save', async () => {
      try {
        const k = $('input[name=rt-keep]:checked', m.el);
        await RB.rpc('rb_change_loan_rate', { p: { loan_id: v.id, new_rate: num(val(m.el, '#rt-rate')), from_date: val(m.el, '#rt-from'), keep: k ? k.value : 'tenure', reason: val(m.el, '#rt-why') } });
        RB.toast('Rate changed'); m.close(); reload(); loanWindow(v.id);
      } catch (e) { RB.modalMsg(m, e.message); }
    });
  }

  // ===================================================================
  // Operating leases (rented premises and equipment)
  // ===================================================================
  async function olTab(tb) {
    const x = await RB.rpc('rb_loans_summary', { p_as_of: RB.today() });
    tb.innerHTML = '<div class="actions" style="margin:0 0 .75rem">' + (RB.has('loans.add') ? '<button class="primary" id="ot-add">+ Rented premises</button>' : '') + '</div>' +
      '<p class="muted">The kitchen, the shop, a godown or rented equipment (AS 19 operating leases). The rent is charged evenly over the lease, so a rent-free month or a yearly increase is spread out. ' +
      'Each month\'s rent is entered as an expense from here. Tap a line to open it.</p><div id="ot-grid"></div>';
    const grid = RB.grid($('#ot-grid', tb), [
      { title: 'No.', field: 'lease_no', width: 140, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
      { title: 'What', field: 'name', minWidth: 200 },
      { title: 'Landlord', field: 'lessor' },
      { title: 'From', field: 'start_date', formatter: (c) => RB.fmtDate(c.getValue()) },
      { title: 'To', field: 'end_date', formatter: (c) => RB.fmtDate(c.getValue()) },
      { title: 'Rent now', field: 'rent_now_paise', hozAlign: 'right', formatter: (c) => RB.rupees(c.getValue()) },
      { title: 'Rent not entered', field: 'rent_not_entered', formatter: (c) => (Number(c.getValue()) ? RB.badge('protected', c.getValue() + ' month(s)') : '') },
      { title: 'Status', field: 'status', formatter: (c) => badge(c.getValue()) },
    ], x.op_leases);
    grid.on('rowClick', (e, row) => olWindow(row.getData().id));
    on(tb, '#ot-add', () => olForm());
  }

  async function olForm(old) {
    const d = await lists();
    const v = old || { start_date: RB.today(), months: 11, escalation_every: 12, basis: 'straight_line', category_id: (d.cats.find((c) => c.name === 'Kitchen rent') || {}).id };
    const cats = d.cats.filter((c) => c.is_active || c.id === v.category_id);
    const money = (p) => (p == null ? '' : RB.fromPaise(p));
    const m = RB.modal('<h2>' + (old ? 'Change ' + esc(old.lease_no) : 'Rented premises or equipment') + '</h2><div class="m-msg"></div>' +
      '<label class="check"><input type="checkbox" id="of-takeon"' + (v.is_takeon ? ' checked' : '') + '> Already running before the app (bring in its deposit and rent equalisation)</label>' +
      '<div class="row">' + RB.field('of-name', 'What is rented', RB.inp('of-name', v.name, ' placeholder="e.g. Kitchen premises, Andheri"'), null, true) +
      RB.field('of-lessor', 'Landlord', RB.inp('of-lessor', v.lessor), null, true) + '</div>' +
      '<div class="row">' + RB.field('of-cat', 'Rent goes to', RB.sel('of-cat', cats.map((c) => [c.id, c.name + ' (' + c.account_code + ')']), v.category_id), 'Kitchen rent is part of stock cost (AS 2); shop and office rent is not.', true) +
      RB.field('of-dept', 'Department', RB.sel('of-dept', [['', '(the category\'s)']].concat(d.depts), v.department_id)) +
      RB.field('of-sup', 'Landlord as a supplier', RB.sel('of-sup', [['', '(none)']].concat(d.suppliers.filter((s) => s.is_active || s.id === v.supplier_id).map((s) => [s.id, s.name])), v.supplier_id), 'Only needed if rent is ever entered on credit.') + '</div>' +
      '<div class="row">' + RB.field('of-start', 'Lease starts', '<input type="date" id="of-start" value="' + esc(v.start_date || '') + '">', null, true) +
      RB.field('of-months', 'Length (months)', RB.inp('of-months', v.months, ' inputmode="numeric"'), 'An 11-month leave and licence is 11.', true) +
      RB.field('of-lock', 'Lock-in (months)', RB.inp('of-lock', v.lock_in_months || '', ' inputmode="numeric" placeholder="0"'), 'Months the firm cannot leave. Used for the AS 19 note.') +
      '<div class="field of-takeon"><label for="of-tdate">Take-on date <span class="req">*</span></label><input type="date" id="of-tdate" value="' + esc(v.takeon_date || '') + '"></div></div>' +
      '<div class="row">' + RB.field('of-rent', 'Monthly rent (₹)', RB.inp('of-rent', money(v.rent_paise), ' inputmode="decimal"'), 'In the first year.', true) +
      RB.field('of-esc', 'Increase (%)', RB.inp('of-esc', v.escalation_pct || '', ' inputmode="decimal" placeholder="0"')) +
      RB.field('of-every', 'Every (months)', RB.inp('of-every', v.escalation_every, ' inputmode="numeric"')) +
      RB.field('of-free', 'Rent-free months at the start', RB.inp('of-free', v.rent_free_months || '', ' inputmode="numeric" placeholder="0"')) + '</div>' +
      '<div class="row">' + RB.field('of-dep', 'Security deposit (₹)', RB.inp('of-dep', money(v.deposit_paise), ' inputmode="decimal" placeholder="0"'), 'Enter the payment itself on the lease once started.') +
      RB.field('of-basis', 'Rent charged', RB.sel('of-basis', [['straight_line', 'Evenly over the lease (AS 19 straight line)'], ['as_paid', 'As paid (only with the CA\'s reason)']], v.basis)) + '</div>' +
      '<div class="field" id="of-why-f">' + '<label for="of-why">Why another basis is more representative</label>' + RB.inp('of-why', v.basis_reason) + '</div>' +
      RB.field('of-note', 'Note', RB.inp('of-note', v.note, ' placeholder="e.g. agreement registered on …"')) +
      '<p id="of-sum" class="muted"></p>' +
      '<div class="actions"><button class="primary" id="of-save">Save as draft</button><button data-close>Cancel</button></div>', { wide: true });
    const sync = () => {
      $$('.of-takeon', m.el).forEach((e) => { e.style.display = ticked(m.el, '#of-takeon') ? '' : 'none'; });
      $('#of-why-f', m.el).style.display = val(m.el, '#of-basis') === 'as_paid' ? '' : 'none';
      try {
        const n = int(val(m.el, '#of-months')) || 0, r = RB.toPaise(val(m.el, '#of-rent')) || 0, e = num(val(m.el, '#of-esc')) || 0;
        const ev = int(val(m.el, '#of-every')) || 12, f = int(val(m.el, '#of-free')) || 0;
        let tot = 0; for (let i = 1; i <= n; i++) tot += i <= f ? 0 : Math.round(r * Math.pow(1 + e / 100, Math.floor((i - 1) / ev)));
        $('#of-sum', m.el).innerHTML = n ? 'Total rent over the lease: <b>' + RB.rupees(tot) + '</b>. Charged to profit and loss each month: <b>' + RB.rupees(Math.round(tot / n)) + '</b>' +
          (val(m.el, '#of-basis') === 'as_paid' ? ' (straight line; you chose as paid)' : '') + '.' : '';
      } catch (err) { /* typing */ }
    };
    $$('input, select', m.el).forEach((e) => e.addEventListener('input', sync)); on(m.el, '#of-takeon', sync, 'change'); on(m.el, '#of-basis', sync, 'change'); sync();
    on(m.el, '#of-save', async () => {
      try {
        const t = ticked(m.el, '#of-takeon');
        const id = await RB.rpc('rb_save_op_lease', { p: { id: old ? old.id : null, name: val(m.el, '#of-name'), lessor: val(m.el, '#of-lessor'),
          category_id: Number(val(m.el, '#of-cat')), department_id: val(m.el, '#of-dept') ? Number(val(m.el, '#of-dept')) : null,
          supplier_id: val(m.el, '#of-sup') ? Number(val(m.el, '#of-sup')) : null, start_date: val(m.el, '#of-start'), months: int(val(m.el, '#of-months')),
          lock_in_months: int(val(m.el, '#of-lock')) || 0, rent_paise: RB.toPaise(val(m.el, '#of-rent')), escalation_pct: num(val(m.el, '#of-esc')) || 0,
          escalation_every: int(val(m.el, '#of-every')) || 12, rent_free_months: int(val(m.el, '#of-free')) || 0, deposit_paise: RB.toPaise(val(m.el, '#of-dep')) || 0,
          basis: val(m.el, '#of-basis'), basis_reason: val(m.el, '#of-why'), is_takeon: t, takeon_date: t ? val(m.el, '#of-tdate') : null, note: val(m.el, '#of-note') } });
        RB.toast('Saved as a draft'); m.close(); reload(); olWindow(id);
      } catch (e) { RB.modalMsg(m, e.message); }
    });
  }

  async function olWindow(id) {
    const x = await RB.rpc('rb_op_lease_detail', { p_id: id });
    const v = x.lease, st = v.status, mine = RB.profile && v.entered_by === RB.profile.id;
    const lastEntry = x.entries.filter((e) => e.status === 'posted' && e.kind !== 'month_end').slice(-1)[0];
    const today = RB.today();
    const entered = (r) => r.expense_id && ['posted', 'awaiting_approval'].includes(r.expense_status);
    const m = RB.modal('<h2>' + esc(v.lease_no) + RB.demoBadge(v) + ' ' + badge(st) + '</h2><div class="m-msg"></div>' +
      '<p><b>' + esc(v.name) + '</b>, from ' + esc(v.lessor) + '. Rent goes to ' + esc(x.category) + ' (' + esc(x.expense_account) + ').</p>' +
      '<div class="row facts">' + fact('Lease', RB.fmtDate(v.start_date) + ', ' + v.months + ' months' + (v.lock_in_months ? ' (' + v.lock_in_months + ' locked in)' : '')) +
      fact('Total rent', RB.rupees(x.total_rent_paise)) + fact('Charged each month', v.basis === 'as_paid' ? 'as paid' : RB.rupees(x.straight_line_paise)) +
      fact('Rent equalisation', RB.rupees(x.equalisation_paise)) + fact('Deposit held', RB.rupees(x.deposit_paise)) + '</div>' +
      (v.basis === 'as_paid' ? '<p class="muted">Charged as paid: ' + esc(v.basis_reason) + '</p>' : '') +
      (v.end_reason ? '<p class="muted">' + (st === 'cancelled' ? 'Cancelled: ' : 'Ended ' + RB.fmtDate(v.ended_date) + ': ') + esc(v.end_reason) + '</p>' : '') +
      '<div class="actions">' +
      (st === 'draft' && (mine || RB.has('loans.edit')) ? '<button id="ow-edit">Change</button>' : '') +
      (st === 'draft' && RB.has('loans.approve') ? '<button class="primary" id="ow-start">Start (approve)</button>' : '') +
      (st === 'draft' && (mine || RB.has('loans.edit')) ? '<button class="danger" id="ow-del">Delete draft</button>' : '') +
      (['active', 'ended'].includes(st) && RB.has('loans.add') ? '<button id="ow-dpay">Deposit paid</button><button id="ow-dret">Deposit returned</button>' : '') +
      (st === 'active' && RB.has('loans.edit') ? '<button id="ow-end">End early</button><button class="danger" id="ow-cancel">Cancel (started by mistake)</button>' : '') +
      '<button data-close>Close</button></div>' +
      '<h3>Rent month by month</h3><div class="grid-wrap" style="max-height:300px;overflow:auto"><table class="ticks lines"><thead><tr><th>#</th><th>Month from</th><th>Rent</th><th>Entered</th><th></th></tr></thead><tbody>' +
      x.rents.map((r) => '<tr><td>' + r.n + '</td><td>' + RB.fmtDate(r.period_start) + '</td><td>' + (Number(r.rent_paise) ? RB.rupees(r.rent_paise) : 'rent-free') + '</td><td>' +
        (r.before_takeon ? '<span class="muted">before the app</span>' : entered(r) ? '✓ ' + esc(r.expense_no) + (r.expense_status === 'awaiting_approval' ? ' (waiting for approval)' : '') : (Number(r.rent_paise) && r.period_start <= today ? RB.badge('protected', 'not entered') : '')) + '</td><td>' +
        (['active', 'ended'].includes(st) && RB.has('loans.add') && !r.before_takeon && Number(r.rent_paise) && !entered(r) ? '<button data-rent="' + r.n + '">Enter rent</button>' : '') + '</td></tr>').join('') +
      '</tbody></table></div>' +
      '<h3>Entries</h3><div class="grid-wrap"><table class="ticks"><thead><tr><th>Date</th><th>No.</th><th>What</th><th>Amount</th><th>Status</th><th></th></tr></thead><tbody>' +
      (x.entries.length ? x.entries.map((e) => '<tr><td>' + RB.fmtDate(e.entry_date) + '</td><td>' + esc(e.entry_no) + '</td><td>' + esc(ENTRY[e.kind]) + '</td><td>' +
        (e.kind === 'month_end' ? 'Rent spread: ' + RB.rupees(e.equalisation_paise) : e.kind === 'takeon' ? 'Deposit ' + RB.rupees(e.deposit_paise) + ', equalisation ' + RB.rupees(e.equalisation_paise) : RB.rupees(Math.abs(e.deposit_paise))) + '</td><td>' + badge(e.status) + '</td><td>' +
        (lastEntry && e.id === lastEntry.id && RB.has('power.reverse_entries') && e.kind !== 'takeon' ? '<button class="danger" data-rev="' + e.id + '">Reverse</button>' : '') + '</td></tr>').join('')
        : '<tr><td colspan="6" class="muted">Nothing posted yet.</td></tr>') + '</tbody></table></div>', { wide: true });
    const act = (fn) => async () => { try { await fn(); } catch (e) { RB.modalMsg(m, e.message); } };
    on(m.el, '#ow-edit', () => { m.close(); olForm(v); });
    on(m.el, '#ow-start', act(async () => {
      if (!(await RB.confirm('Start ' + v.lease_no + '?', v.is_takeon ? 'Brings in the deposit and the rent equalisation at ' + RB.fmtDate(v.takeon_date) + '.' : 'Nothing is posted now; enter the deposit and each month\'s rent from here.'))) return;
      await RB.rpc('rb_start_op_lease', { p_id: id }); RB.toast('Started'); m.close(); reload(); olWindow(id);
    }));
    on(m.el, '#ow-del', act(async () => {
      if (!(await RB.confirm('Delete the draft ' + v.lease_no + '?', 'Nothing has been posted for it.'))) return;
      await RB.rpc('rb_delete_draft_op_lease', { p_id: id }); RB.toast('Deleted'); m.close(); reload();
    }));
    on(m.el, '#ow-cancel', act(async () => {
      const why = await askReason('Cancel ' + v.lease_no, 'Only for a lease started by mistake, with nothing posted for it.'); if (!why) return;
      await RB.rpc('rb_cancel_op_lease', { p_id: id, p_reason: why }); RB.toast('Cancelled'); m.close(); reload();
    }));
    on(m.el, '#ow-end', act(async () => {
      const r = await askReason('End ' + v.lease_no + ' early', 'Choose the last day of the lease. The months after it are taken off, and the next month-end run settles the rent equalisation.', true); if (!r) return;
      await RB.rpc('rb_end_op_lease', { p: { lease_id: id, end_date: r.date, reason: r.reason } }); RB.toast('Lease ended'); m.close(); reload(); olWindow(id);
    }));
    const deposit = (kind) => async () => {
      const d = await lists();
      const dm = RB.modal('<h2>Deposit ' + kind + ': ' + esc(v.lease_no) + '</h2><div class="m-msg"></div>' +
        '<div class="row">' + RB.field('dp-date', 'Date', '<input type="date" id="dp-date" value="' + RB.today() + '">', null, true) +
        RB.field('dp-amt', 'Amount (₹)', RB.inp('dp-amt', RB.fromPaise(kind === 'paid' ? Math.max(Number(v.deposit_paise) - Number(x.deposit_paise), 0) || null : x.deposit_paise), ' inputmode="decimal"'), null, true) + '</div>' +
        '<div class="row">' + RB.field('dp-acc', kind === 'paid' ? 'Paid from' : 'Received into', RB.sel('dp-acc', d.acctOpts(null), d.defaultBank), null, true) +
        RB.field('dp-ref', 'Reference', RB.inp('dp-ref', '')) + '</div>' +
        '<p class="hint">Kept in ' + esc(x.deposit_account) + (x.deposit_account === '20050130' ? ' Long-term Security Deposits' : ' Security Deposits - Current') + '.</p>' +
        '<div class="actions"><button class="primary" id="dp-save">Save</button><button data-close>Cancel</button></div>');
      on(dm.el, '#dp-save', async () => {
        try {
          await RB.rpc('rb_lease_deposit', { p: { lease_id: id, kind, entry_date: val(dm.el, '#dp-date'), amount_paise: RB.toPaise(val(dm.el, '#dp-amt')),
            money_account_id: Number(val(dm.el, '#dp-acc')), reference: val(dm.el, '#dp-ref') } });
          RB.toast('Saved'); dm.close(); m.close(); reload(); olWindow(id);
        } catch (e) { RB.modalMsg(dm, e.message); }
      });
    };
    on(m.el, '#ow-dpay', deposit('paid'));
    on(m.el, '#ow-dret', deposit('returned'));
    $$('[data-rent]', m.el).forEach((b) => b.addEventListener('click', async () => {
      const r = x.rents.find((y) => String(y.n) === b.dataset.rent);
      const d = await lists();
      const rm = RB.modal('<h2>Rent for ' + RB.fmtDate(r.period_start) + '</h2><div class="m-msg"></div>' +
        '<p>' + esc(v.name) + ': <b>' + RB.rupees(r.rent_paise) + '</b>, entered as an expense in ' + esc(x.category) + '. Above the approval limit it waits for approval, like any expense.</p>' +
        '<div class="row">' + RB.field('rr-date', 'Date paid', '<input type="date" id="rr-date" value="' + (r.period_start <= today ? r.period_start : today) + '">', null, true) +
        RB.field('rr-mode', 'Paid by', RB.sel('rr-mode', Object.entries(MODES), 'bank'), v.supplier_id ? null : 'Credit needs the landlord as a supplier on the lease.') + '</div>' +
        '<div class="row">' + RB.field('rr-acc', 'Cash or bank account', RB.sel('rr-acc', d.acctOpts(null), d.defaultBank)) +
        RB.field('rr-ref', 'Reference', RB.inp('rr-ref', '', ' placeholder="UPI or cheque no."')) + '</div>' +
        '<div class="actions"><button class="primary" id="rr-save">Save</button><button data-close>Cancel</button></div>');
      on(rm.el, '#rr-save', async () => {
        try {
          const mode = val(rm.el, '#rr-mode');
          await RB.rpc('rb_record_lease_rent', { p: { lease_id: id, n: r.n, expense_date: val(rm.el, '#rr-date'), payment_mode: mode,
            money_account_id: mode === 'credit' ? null : Number(val(rm.el, '#rr-acc')), reference: val(rm.el, '#rr-ref') } });
          RB.toast('Rent entered'); rm.close(); m.close(); reload(); olWindow(id);
        } catch (e) { RB.modalMsg(rm, e.message); }
      });
    }));
    $$('[data-rev]', m.el).forEach((b) => b.addEventListener('click', act(async () => {
      const r = await askReason('Reverse this entry', 'A reversing entry is posted on the date you choose.', true); if (!r) return;
      await RB.rpc('rb_reverse_loan_entry', { p_id: Number(b.dataset.rev), p_date: r.date, p_reason: r.reason }); RB.toast('Reversed'); m.close(); reload(); olWindow(id);
    })));
  }

  // ===================================================================
  // Month-end step
  // ===================================================================
  async function monthEndTab(tb) {
    tb.innerHTML = '<div class="row" style="align-items:flex-end">' + RB.field('lm-month', 'Month', '<input type="month" id="lm-month" value="' + (L.meMonth || lastMonth()).slice(0, 7) + '">') +
      '<div class="field" style="flex:0 1 auto"><button id="lm-go">Show</button></div></div><div id="lm-body" class="card"></div>';
    const load = async () => {
      const month = $('#lm-month', tb).value + '-01'; L.meMonth = month;
      const x = await RB.rpc('rb_loans_month_preview', { p_month: month });
      const el = $('#lm-body', tb), posted = x.posted;
      const tot = Number(x.interest_paise) + Number(x.depreciation_paise) + Number(x.equalisation_paise);
      el.innerHTML = '<h2>Loans and leases for ' + esc(monthName(month)) + '</h2>' +
        (x.demo ? '<div class="msg info">There are no real loans or leases yet, so this works on the DEMO records.</div>' : '') +
        '<p class="muted">Run this <b>before step 1</b> on Cash, bank and expenses → Month-end, because depreciation of kitchen assets and kitchen rent are part of stock cost. ' +
        'It posts, for every loan and lease: interest and finance charges up to ' + RB.fmtDate(x.month_end) + ' not yet paid, a month of depreciation on leased assets, and the rent spread evenly (AS 19). Only the change since the last run is posted.</p>' +
        (x.last_run && x.last_run < month.slice(0, 8) + '01' && monthName(x.last_run) !== monthName(new Date(Number(month.slice(0, 4)), Number(month.slice(5, 7)) - 2, 1).toISOString().slice(0, 10))
          ? '<div class="msg info">The last run was for ' + esc(monthName(x.last_run)) + '. This run catches up the months in between.</div>' : '') +
        (x.later_run ? '<div class="msg error">A later month (' + esc(monthName(x.later_run)) + ') is already posted. Months are run in order.</div>' : '') +
        (x.absorption_posted && Number(x.pool_paise) ? '<div class="msg error">Step 1 is already posted for this month, and this run changes kitchen costs that step 1 shares into stock. Reverse step 1 first, post this, then post step 1 again.</div>' : '') +
        '<div class="grid-wrap"><table class="ticks"><thead><tr><th>No.</th><th>What</th><th>Interest or finance charge accrued</th><th>Depreciation</th><th>Rent spread (AS 19)</th></tr></thead><tbody>' +
        (x.items.length ? x.items.map((i) => '<tr><td>' + esc(i.no) + '</td><td>' + esc(i.name) + '</td><td>' + amt(i.interest_change) + '</td><td>' + amt(i.dep_change) + '</td><td>' + amt(i.eq_change) + '</td></tr>').join('')
          : '<tr><td colspan="5" class="muted">Nothing to post for this month.</td></tr>') +
        '<tr style="font-weight:700"><td></td><td>Total</td><td>' + RB.rupees(x.interest_paise) + '</td><td>' + RB.rupees(x.depreciation_paise) + '</td><td>' + RB.rupees(x.equalisation_paise) + '</td></tr></tbody></table></div>' +
        '<p class="hint">A negative figure is written back (for example interest accrued last month and cleared by this month\'s EMI is already in the books).</p>' +
        '<div class="actions">' + (posted ? '<p>✅ Posted as <b>' + esc(posted.run_no) + '</b>.</p>' + (RB.has('power.month_end') ? '<button class="danger" id="lm-rev">Reverse this run</button>' : '')
          : !RB.has('power.month_end') ? '<p class="muted">Run by the Accountant, the FC or a Director.</p>'
            : RB.today() <= x.month_end ? '<p class="muted">Post this once ' + esc(monthName(month)) + ' has ended (from ' + RB.fmtDate(new Date(new Date(x.month_end + 'T00:00:00Z').getTime() + 864e5).toISOString().slice(0, 10)) + '). The figures above are a preview.</p>'
              : '<button class="primary" id="lm-post"' + (x.items.length ? '' : ' disabled') + '>Post (' + RB.rupees(tot) + ')</button>') + '</div>';
      on(el, '#lm-post', async () => {
        try {
          if (!(await RB.confirm('Post loans and leases for ' + monthName(month) + '?', 'Interest ' + RB.rupees(x.interest_paise) + ', depreciation ' + RB.rupees(x.depreciation_paise) + ', rent spread ' + RB.rupees(x.equalisation_paise) + '.'))) return;
          await RB.rpc('rb_post_loans_month', { p_month: month, p_demo: x.demo }); RB.toast('Posted'); load();
        } catch (e) { RB.toast(e.message, true); }
      });
      on(el, '#lm-rev', async () => {
        try {
          const why = await askReason('Reverse ' + posted.run_no, 'Takes this month\'s run back out, for example to correct a payment and run it again.'); if (!why) return;
          await RB.rpc('rb_reverse_month_end', { p_id: posted.id, p_reason: why }); RB.toast('Reversed'); load();
        } catch (e) { RB.toast(e.message, true); }
      });
    };
    on(tb, '#lm-go', () => load().catch((e) => RB.toast(e.message, true)));
    await load();
  }

  // ===================================================================
  // AS 19 notes for the accounts
  // ===================================================================
  async function as19Tab(tb) {
    tb.innerHTML = '<div class="row" style="align-items:flex-end">' + RB.field('as-from', 'From', '<input type="date" id="as-from" value="' + (L.asFrom || fyStart()) + '">') +
      RB.field('as-to', 'Balance sheet date', '<input type="date" id="as-to" value="' + (L.asTo || RB.today()) + '">') +
      '<div class="field" style="flex:0 1 auto"><button id="as-go">Show</button> <button id="as-xls">Download to Excel</button></div></div><div id="as-body"></div>';
    const load = async () => {
      L.asFrom = $('#as-from', tb).value; L.asTo = $('#as-to', tb).value;
      const x = await RB.rpc('rb_lease_disclosure', { p_from: L.asFrom, p_to: L.asTo });
      const band = (kind, b, k) => { const r = x.schedules.find((s) => s.kind === kind && Number(s.band) === b); return r ? Number(r[k]) : 0; };
      const rowsFor = (kind, keys) => [1, 2, 3].map((b) => '<tr><td>' + BANDS[b - 1] + '</td>' + keys.map((k) => '<td>' + RB.rupees(band(kind, b, k)) + '</td>').join('') + '</tr>').join('') +
        '<tr style="font-weight:700"><td>Total</td>' + keys.map((k) => '<td>' + RB.rupees([1, 2, 3].reduce((s, b) => s + band(kind, b, k), 0)) + '</td>').join('') + '</tr>';
      const opf = (b) => { const r = x.operating_future.find((s) => Number(s.band) === b); return r ? Number(r.payments_paise) : 0; };
      $('#as-body', tb).innerHTML = (x.demo ? '<div class="msg info">There are no real loans or leases yet, so this shows the DEMO records.</div>' : '') +
        '<p class="muted">Figures for the notes to the accounts at ' + RB.fmtDate(x.to) + ' (AS 19 paragraphs 22 and 25), for the CA. Amounts due are by the date each payment falls due.</p>' +
        '<div class="card"><h2>Finance leases: minimum lease payments</h2><table class="ticks" data-sheet="Finance leases"><thead><tr><th></th><th>Minimum lease payments</th><th>Future finance charges</th><th>Present value</th></tr></thead><tbody>' +
        rowsFor('finance_lease', ['payments_paise', 'interest_paise', 'principal_paise']) + '</tbody></table>' +
        '<h3>Leased assets (net carrying amount)</h3><table class="ticks" data-sheet="Leased assets"><thead><tr><th>Asset</th><th>Cost</th><th>Depreciation</th><th>Carrying amount</th></tr></thead><tbody>' +
        (x.leased_assets.length ? x.leased_assets.map((a) => '<tr><td>' + esc(a.account + ' ' + a.name) + '</td><td>' + RB.rupees(a.cost_paise) + '</td><td>' + RB.rupees(a.depreciation_paise) + '</td><td>' + RB.rupees(a.carrying_paise) + '</td></tr>').join('')
          : '<tr><td colspan="4" class="muted">None.</td></tr>') + '</tbody></table>' +
        '<p>For the period: finance charges <b>' + RB.rupees(x.finance_charge_paise) + '</b>; depreciation on leased assets <b>' + RB.rupees(x.depreciation_paise) + '</b>.</p></div>' +
        '<div class="card"><h2>Operating leases</h2><table class="ticks" data-sheet="Operating leases"><thead><tr><th>Future payments under non-cancellable leases (lock-in)</th><th>Amount</th></tr></thead><tbody>' +
        [1, 2, 3].map((b) => '<tr><td>' + BANDS[b - 1] + '</td><td>' + RB.rupees(opf(b)) + '</td></tr>').join('') +
        '<tr style="font-weight:700"><td>Total</td><td>' + RB.rupees(opf(1) + opf(2) + opf(3)) + '</td></tr></tbody></table>' +
        '<p>Lease payments charged to profit and loss for the period: <b>' + RB.rupees(x.operating_charge_paise) + '</b>.' +
        (Number(x.cancellable_leases) ? ' ' + x.cancellable_leases + ' lease(s) have no lock-in, so they are cancellable and not in the table.' : '') + '</p></div>' +
        '<div class="card"><h2>Loans: principal falling due</h2><table class="ticks" data-sheet="Loans"><thead><tr><th></th><th>Principal</th><th>Interest in the instalments</th></tr></thead><tbody>' +
        rowsFor('loan', ['principal_paise', 'interest_paise']) + '</tbody></table>' +
        '<p>Loan interest for the period: <b>' + RB.rupees(x.loan_interest_paise) + '</b> (AS 16).</p></div>';
    };
    on(tb, '#as-go', () => load().catch((e) => RB.toast(e.message, true)));
    on(tb, '#as-xls', () => {
      const wb = XLSX.utils.book_new();
      $$('#as-body table[data-sheet]', tb).forEach((t) => XLSX.utils.book_append_sheet(wb, XLSX.utils.table_to_sheet(t), t.dataset.sheet));
      XLSX.writeFile(wb, 'AS 19 notes ' + RB.fmtDate(L.asTo) + '.xlsx');
    });
    await load();
  }
})();
