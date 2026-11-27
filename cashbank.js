// =====================================================================
// RUCHI BUDS APP · cashbank.js · Version 1.1 · 27-Nov-2026
// Module 6 screen "Cash, bank and expenses": cash and bank balances and
// the cash book, expenses (paid at once or on credit, with a bill photo,
// approval above the Settings limit), other money received, moving money
// between cash and bank, partners' capital and drawings, the day-end cash
// count, the monthly bank reconciliation, the two month-end steps
// (labour and kitchen overheads into stock under AS 2; provision for
// doubtful debts) and the set-up.
// =====================================================================
(function () {
  'use strict';
  const RB = window.RB, $ = RB.$, $$ = RB.$$, esc = RB.esc;
  const C = (RB.cashbank = {});

  const MODES = { cash: 'Cash', upi: 'UPI', bank: 'Bank', credit: 'Credit (pay later)' };
  const STATUS = { awaiting_approval: 'Waiting for approval', posted: 'Posted', refused: 'Refused', reversed: 'Reversed' };
  const BADGE = { awaiting_approval: 'protected', posted: 'active', refused: 'inactive', reversed: 'inactive', draft: 'protected', done: 'active' };
  const METHOD = { kg: 'Kg produced', batches: 'Number of batches', hours: 'Hours worked', material: 'Value of materials' };
  const PARTNER_KIND = { capital_in: 'Capital brought in', capital_out: 'Capital taken out', drawings: 'Drawings' };
  const NOTES = [500, 200, 100, 50, 20, 10];

  const totalsOk = () => (RB.has('cash_bank.view') && RB.has('power.see_totals')) || RB.has('accounts.view');
  const monthEndOk = () => RB.has('power.month_end');
  const on = (root, sel, fn, ev) => { const b = $(sel, root); if (b) b.addEventListener(ev || 'click', fn); };
  const amt = (p) => (p == null || Number(p) === 0 ? '' : RB.rupees(p));
  const status = (s, map) => RB.badge(BADGE[s] || 'invited', (map || STATUS)[s] || s);
  const monthStart = (d) => (d || RB.today()).slice(0, 8) + '01';
  const lastMonth = () => { const t = RB.today(); const y = Number(t.slice(0, 4)), m = Number(t.slice(5, 7)); return m === 1 ? (y - 1) + '-12-01' : y + '-' + String(m - 1).padStart(2, '0') + '-01'; };
  const monthEnd = (m) => { const d = new Date(Number(m.slice(0, 4)), Number(m.slice(5, 7)), 0); return m.slice(0, 8) + String(d.getDate()).padStart(2, '0'); };
  const monthName = (m) => RB.fmtDate(m).replace(/^\d+-/, '');
  const fact = (label, value) => '<div><small>' + esc(label) + '</small><b>' + value + '</b></div>';
  const num = (v) => { const s = String(v == null ? '' : v).replace(/[,\s]/g, ''); if (s === '') return null; const n = Number(s); if (!isFinite(n)) throw new Error('"' + v + '" is not a number.'); return n; };

  // Lists the forms need, read once per visit to a tab.
  async function lists() {
    const d = await RB.masters.load(['departments', 'suppliers']);
    const [accts, cats, st] = await Promise.all([
      RB.select('money_accounts', '*', (x) => x.order('sort')),
      RB.select('expense_categories', '*', (x) => x.order('sort')),
      RB.select('app_settings', 'partners,expense_approval_limit_paise,gstin,gst_registered_from,absorption_method,normal_output_kg', (x) => x.eq('id', 1).single()).catch(() => ({})),
    ]);
    d.accts = accts; d.acct = Object.fromEntries(accts.map((a) => [a.id, a]));
    d.cats = cats; d.cat = Object.fromEntries(cats.map((c) => [c.id, c]));
    d.sup = Object.fromEntries(d.suppliers.map((s) => [s.id, s]));
    d.settings = st || {};
    d.partners = (d.settings.partners || []);
    d.depts = d.departments.filter((x) => x.is_active && !x.merged_into).map((x) => [x.id, x.code + ' ' + x.name]);
    d.deptByCode = (code) => { const k = d.departments.find((x) => x.code === code && x.is_active); return k ? k.id : ''; };
    d.acctOpts = (kind, val) => d.accts.filter((a) => (!kind || a.kind === kind) && (a.is_active || a.id === val)).map((a) => [a.id, a.name]);
    d.defaultAcct = (kind) => (d.accts.find((a) => a.kind === kind && a.is_default && a.is_active) || d.accts.find((a) => a.kind === kind && a.is_active) || {}).id;
    return d;
  }

  function tabs(body, list) {
    body.innerHTML = '<div class="tabs">' + list.map(([k, t]) => '<button data-tab="' + k + '">' + t + '</button>').join('') + '</div><div id="tab-body"></div>';
    const show = async (k) => {
      C.tab = k;
      $$('.tabs button', body).forEach((b) => b.classList.toggle('on', b.dataset.tab === k));
      const tb = $('#tab-body', body); tb.innerHTML = '<p class="muted">Loading…</p>';
      try { await list.find((x) => x[0] === k)[2](tb); } catch (e) { tb.innerHTML = '<div class="msg error">' + esc(e.message) + '</div>'; }
    };
    $$('.tabs button', body).forEach((b) => b.addEventListener('click', () => show(b.dataset.tab)));
    C.reload = () => show(C.tab);
    show(C.tab && list.some((x) => x[0] === C.tab) ? C.tab : list[0][0]);
  }
  const reload = () => (C.reload ? C.reload() : RB.route());

  // ===================================================================
  // The screen
  // ===================================================================
  RB.screens.cash_bank = async (body) => {
    const tools = $('#page-tools');
    if (tools) {
      tools.innerHTML = (RB.has('cash_bank.add') ? '<button class="primary" id="cb-new">+ Expense</button><button id="cb-in">+ Money received</button>' : '');
      on(tools, '#cb-new', () => expenseModal(null, 'out'));
      on(tools, '#cb-in', () => expenseModal(null, 'in'));
    }
    const list = [];
    if (totalsOk()) list.push(['money', 'Cash and bank', moneyTab]);
    list.push(['expenses', 'Expenses', expensesTab]);
    list.push(['transfers', 'Moving money', transfersTab]);
    list.push(['counts', 'Cash count', countsTab]);
    if (totalsOk()) list.push(['partners', 'Partners', partnersTab]);
    if (totalsOk()) list.push(['bank', 'Bank reconciliation', bankTab]);
    if (monthEndOk() || RB.has('accounts.view')) list.push(['monthend', 'Month-end', monthEndTab]);
    if (totalsOk()) list.push(['report', 'Expense report', reportTab]);
    if (RB.has('cash_bank.edit') || monthEndOk()) list.push(['setup', 'Set-up', setupTab]);
    tabs(body, list);
  };

  // ===================================================================
  // Cash and bank: balances and the cash book
  // ===================================================================
  async function moneyTab(tb) {
    const bal = await RB.rpc('rb_money_balances', { p_as_of: RB.today() });
    tb.innerHTML = '<div class="row facts card">' + bal.map((a) => fact(a.name + (a.is_active ? '' : ' (switched off)'),
      '<span style="font-size:1.25rem">' + RB.rupees(a.balance_paise) + '</span>' +
      (Number(a.day_in_paise) || Number(a.day_out_paise) ? '<small>Today in ' + RB.rupees(a.day_in_paise) + ' · out ' + RB.rupees(a.day_out_paise) + '</small>' : ''))).join('') + '</div>' +
      '<div class="card"><h2>Cash book</h2><div class="row" style="align-items:flex-end">' +
      RB.field('bk-acc', 'Account', RB.sel('bk-acc', bal.map((a) => [a.id, a.name]), (bal.find((a) => a.kind === 'cash') || bal[0] || {}).id)) +
      RB.field('bk-from', 'From', '<input type="date" id="bk-from" value="' + monthStart() + '">') +
      RB.field('bk-to', 'To', '<input type="date" id="bk-to" value="' + RB.today() + '">') +
      '<div class="field" style="flex:0 1 auto"><button id="bk-go">Show</button> <button id="bk-xls">Download to Excel</button></div></div>' +
      '<div id="bk-head"></div><div id="bk-grid"></div></div>';
    let grid;
    const load = async () => {
      const x = await RB.rpc('rb_cash_book', { p_account: Number($('#bk-acc', tb).value), p_from: $('#bk-from', tb).value, p_to: $('#bk-to', tb).value });
      const tin = x.lines.reduce((s, l) => s + Number(l.in_paise), 0), tout = x.lines.reduce((s, l) => s + Number(l.out_paise), 0);
      $('#bk-head', tb).innerHTML = '<div class="row facts">' + fact('Opening balance', RB.rupees(x.opening_paise)) + fact('Money in', RB.rupees(tin)) +
        fact('Money out', RB.rupees(tout)) + fact('Closing balance', RB.rupees(x.closing_paise)) + '</div>' +
        (x.counts.length ? '<p class="muted">Cash counted: ' + x.counts.map((c) => RB.fmtDate(c.date) + ' ' + RB.rupees(c.counted_paise) +
          (Number(c.difference_paise) ? ' (' + (c.difference_paise < 0 ? 'short ' : 'over ') + RB.rupees(Math.abs(c.difference_paise)) + ')' : ' ✓')).join(' · ') + '</p>' : '');
      const rows = x.lines.map((l) => Object.assign({}, l, { date: l.d }));
      grid = RB.grid($('#bk-grid', tb), [
        { title: 'Date', field: 'date', width: 110, formatter: (c) => RB.fmtDate(c.getValue()) },
        { title: 'Entry', field: 'ref', width: 170, formatter: (c) => esc(c.getValue() || c.getRow().getData().journal_no) + RB.demoBadge(c.getRow().getData()) },
        { title: 'Details', field: 'narration', minWidth: 260 },
        { title: 'Money in', field: 'in_paise', hozAlign: 'right', formatter: (c) => amt(c.getValue()) },
        { title: 'Money out', field: 'out_paise', hozAlign: 'right', formatter: (c) => amt(c.getValue()) },
        { title: 'Balance', field: 'balance_paise', hozAlign: 'right', formatter: (c) => RB.rupees(c.getValue()) },
      ], rows);
    };
    on(tb, '#bk-go', () => load().catch((e) => RB.toast(e.message, true)));
    on(tb, '#bk-acc', () => load().catch((e) => RB.toast(e.message, true)), 'change');
    on(tb, '#bk-xls', () => grid && RB.downloadExcel(grid, 'Cash book'));
    if (bal.length) await load();
  }

  // ===================================================================
  // Expenses and other money received
  // ===================================================================
  async function expensesTab(tb) {
    const d = await lists();
    const limit = d.settings.expense_approval_limit_paise;
    tb.innerHTML = '<div class="row" style="align-items:flex-end">' +
      RB.field('ex-from', 'From', '<input type="date" id="ex-from" value="' + monthStart() + '">') +
      RB.field('ex-to', 'To', '<input type="date" id="ex-to" value="' + RB.today() + '">') +
      '<div class="field" style="flex:0 1 auto"><button id="ex-go">Show</button> <button id="ex-xls">Download to Excel</button></div></div>' +
      '<p class="muted">Everything the business spends that is not stock: rent, gas, wages, repairs, transport and so on. ' +
      (limit != null ? 'Anything above <b>' + RB.rupees(limit) + '</b> waits for approval by the Accountant, the FC or a Director. ' : '') +
      'Tap a line to see it, approve it, pay a bill on credit or reverse it.</p><div id="ex-wait"></div><div id="ex-grid"></div>';
    let grid;
    const load = async () => {
      const rows = await RB.select('expenses', '*', (x) => x.gte('expense_date', $('#ex-from', tb).value).lte('expense_date', $('#ex-to', tb).value).order('expense_date', { ascending: false }).order('id', { ascending: false }));
      const waiting = await RB.select('expenses', 'id', (x) => x.eq('status', 'awaiting_approval'));
      $('#ex-wait', tb).innerHTML = waiting.length ? '<div class="msg info"><b>' + waiting.length + '</b> waiting for approval' +
        (RB.has('cash_bank.approve') ? '. Tap each one to approve or refuse it.' : '.') + '</div>' : '';
      const data = rows.map((e) => Object.assign({}, e, {
        cat: (d.cat[e.category_id] || {}).name, who: e.supplier_id ? (d.sup[e.supplier_id] || {}).name : e.payee,
        how: MODES[e.payment_mode] + (e.money_account_id && d.acct[e.money_account_id] ? ' · ' + d.acct[e.money_account_id].name : ''),
        st: STATUS[e.status], signed: e.direction === 'in' ? Number(e.total_paise) : -Number(e.total_paise),
      }));
      grid = RB.grid($('#ex-grid', tb), [
        { title: 'Date', field: 'expense_date', width: 110, formatter: (c) => RB.fmtDate(c.getValue()) },
        { title: 'No.', field: 'expense_no', width: 170, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
        { title: 'For', field: 'cat', minWidth: 160 },
        { title: 'Details', field: 'description', minWidth: 200 },
        { title: 'Paid to / from', field: 'who' },
        { title: 'How', field: 'how' },
        { title: 'Amount', field: 'total_paise', hozAlign: 'right', formatter: (c) => (c.getRow().getData().direction === 'in' ? '+ ' : '') + RB.rupees(c.getValue()) },
        { title: 'Still owed', field: 'outstanding_paise', hozAlign: 'right', formatter: (c) => amt(c.getValue()) },
        { title: 'Status', field: 'st', formatter: (c) => status(c.getRow().getData().status) },
      ], data);
      grid.on('rowClick', (e, row) => expenseWindow(row.getData().id));
    };
    on(tb, '#ex-go', () => load().catch((e) => RB.toast(e.message, true)));
    on(tb, '#ex-xls', () => grid && RB.downloadExcel(grid, 'Expenses'));
    await load();
  }

  // New expense (dir 'out') or other money received (dir 'in'); or change one waiting for approval.
  async function expenseModal(e, dir) {
    const d = await lists();
    dir = e ? e.direction : dir;
    const isIn = dir === 'in';
    e = e || { expense_date: RB.today(), payment_mode: 'cash' };
    const cats = d.cats.filter((c) => c.direction === dir && (c.is_active || c.id === e.category_id));
    const gstOn = !!(d.settings.gstin && d.settings.gst_registered_from);
    const m = RB.modal('<h2>' + (e.id ? 'Change ' + esc(e.expense_no) : isIn ? 'Money received' : 'New expense') + '</h2><div class="m-msg"></div>' +
      '<div class="row">' + RB.field('xe-cat', isIn ? 'What for' : 'What it was for', RB.sel('xe-cat', [['', 'Choose…']].concat(cats.map((c) => [c.id, c.name])), e.category_id), '<span id="xe-hint"></span>', true) +
      RB.field('xe-date', 'Date', '<input type="date" id="xe-date" value="' + esc(e.expense_date) + '">', null, true) + '</div>' +
      RB.field('xe-desc', 'Short note', RB.inp('xe-desc', e.description, ' placeholder="' + (isIn ? 'e.g. 20 empty cartons' : 'e.g. Gas, 2 cylinders') + '"'), null, true) +
      '<div class="row">' + RB.field('xe-amt', isIn ? 'Amount (₹)' : 'Amount before GST (₹)', RB.inp('xe-amt', RB.fromPaise(e.amount_paise), ' inputmode="decimal"'), null, true) +
      (isIn ? '' : RB.field('xe-gst', 'GST on the bill (₹)', RB.inp('xe-gst', e.gst_paise ? RB.fromPaise(e.gst_paise) : '', ' inputmode="decimal" placeholder="0"'),
        gstOn ? 'Claimed as input GST for bills from ' + RB.fmtDate(d.settings.gst_registered_from) + '.' : 'Not GST registered yet, so GST is part of the cost.')) +
      '<div class="field"><label>Total</label><p id="xe-tot" style="font-size:1.2rem;font-weight:700"></p></div></div>' +
      '<div class="row">' + RB.field('xe-mode', isIn ? 'Received by' : 'Paid by', RB.sel('xe-mode', Object.entries(MODES).filter(([k]) => !isIn || k !== 'credit'), e.payment_mode), null, true) +
      RB.field('xe-acc', 'Cash or bank account', '<select id="xe-acc"></select>') + '</div>' +
      '<div class="row">' + '<div class="field"><label for="xe-sup">Supplier <span class="req" id="xe-supreq">*</span></label><div style="display:flex;gap:.5rem">' +
      RB.sel('xe-sup', [['', '(none)']].concat(d.suppliers.filter((s) => s.is_active || s.id === e.supplier_id).map((s) => [s.id, s.name])), e.supplier_id) +
      (RB.has('suppliers.add') ? '<button type="button" id="xe-addsup">+ New</button>' : '') + '</div><div class="hint">Needed when it is on credit: the bill then stays in their balance until paid.</div></div>' +
      RB.field('xe-payee', isIn ? 'Received from' : 'Paid to (if no supplier)', RB.inp('xe-payee', e.payee, ' placeholder="e.g. the plumber"')) + '</div>' +
      '<div class="row">' + RB.field('xe-bill', 'Bill no.', RB.inp('xe-bill', e.bill_no)) +
      RB.field('xe-bdate', 'Bill date', '<input type="date" id="xe-bdate" value="' + esc(e.bill_date || '') + '">') +
      RB.field('xe-ref', 'Reference', RB.inp('xe-ref', e.reference, ' placeholder="UPI or cheque no."')) + '</div>' +
      '<div class="row">' + RB.field('xe-dept', 'Department', RB.sel('xe-dept', d.depts, e.department_id)) +
      (e.id ? '' : RB.field('xe-photo', 'Bill photo', '<input type="file" id="xe-photo" accept="image/*" capture="environment">', 'Optional. Or add it later.')) + '</div>' +
      '<p class="muted" id="xe-limit"></p>' +
      '<div class="actions"><button class="primary" id="xe-save">Save</button><button data-close>Cancel</button></div>', { wide: true });
    const v = (id) => $('#' + id, m.el);
    const fillAcc = () => {
      const mode = v('xe-mode').value, kind = mode === 'cash' ? 'cash' : 'bank';
      v('xe-acc').disabled = mode === 'credit';
      v('xe-acc').innerHTML = mode === 'credit' ? '<option value="">(paid later)</option>'
        : d.acctOpts(kind, e.money_account_id).map(([k, t]) => '<option value="' + k + '"' + (String(k) === String(e.money_account_id || d.defaultAcct(kind)) ? ' selected' : '') + '>' + esc(t) + '</option>').join('');
      v('xe-supreq').style.display = mode === 'credit' ? '' : 'none';
    };
    const total = () => {
      let a = 0, g = 0; try { a = RB.toPaise(v('xe-amt').value) || 0; g = isIn ? 0 : RB.toPaise(v('xe-gst').value) || 0; } catch (err) { /* shown on save */ }
      v('xe-tot').textContent = RB.rupees(a + g);
      const lim = d.settings.expense_approval_limit_paise;
      v('xe-limit').textContent = !isIn && lim != null && a + g > lim ? 'Above ' + RB.rupees(lim) + ': this waits for approval before it reaches the books.' : '';
    };
    const catChange = () => {
      const c = d.cat[v('xe-cat').value];
      v('xe-hint').textContent = c && c.hint ? c.hint : '';
      if (c && !e.id) { const dp = d.deptByCode(c.default_department_code); if (dp) v('xe-dept').value = dp; }
    };
    v('xe-mode').addEventListener('change', fillAcc); fillAcc();
    v('xe-cat').addEventListener('change', catChange); catChange();
    if (e.department_id) v('xe-dept').value = e.department_id;
    ['xe-amt', 'xe-gst'].forEach((id) => { if (v(id)) v(id).addEventListener('input', total); }); total();
    on(m.el, '#xe-addsup', () => RB.masters.supplierModal(null, async (newId) => {
      const sups = await RB.select('suppliers', '*', (x) => x.order('code'));
      v('xe-sup').innerHTML = [['', '(none)']].concat(sups.filter((s) => s.is_active).map((s) => [s.id, s.name])).map(([k, t]) =>
        '<option value="' + esc(k) + '"' + (String(k) === String(newId) ? ' selected' : '') + '>' + esc(t) + '</option>').join('');
    }));
    v('xe-save').addEventListener('click', async () => {
      try {
        const photo = v('xe-photo') && v('xe-photo').files[0] ? await RB.purchases.photoToDataUrl(v('xe-photo').files[0]) : null;
        const mode = v('xe-mode').value;
        const id = await RB.rpc('rb_save_expense', { p: {
          id: e.id || null, category_id: Number(v('xe-cat').value) || null, expense_date: v('xe-date').value, description: v('xe-desc').value,
          amount_paise: RB.toPaise(v('xe-amt').value), gst_paise: isIn ? 0 : RB.toPaise(v('xe-gst').value) || 0, payment_mode: mode,
          money_account_id: mode === 'credit' ? null : Number(v('xe-acc').value) || null, supplier_id: Number(v('xe-sup').value) || null,
          payee: v('xe-payee').value, bill_no: v('xe-bill').value, bill_date: v('xe-bdate').value || null, reference: v('xe-ref').value,
          department_id: Number(v('xe-dept').value) || null, photo } });
        const [row] = await RB.select('expenses', 'expense_no,status', (x) => x.eq('id', id));
        RB.toast((row ? row.expense_no + ' ' : '') + (row && row.status === 'awaiting_approval' ? 'saved: waiting for approval' : 'saved'));
        m.close(); reload();
      } catch (err) { RB.modalMsg(m, err.message); }
    });
  }

  // One expense: details, photos and what can be done with it.
  async function expenseWindow(id) {
    const d = await lists();
    const [e] = await RB.select('expenses', '*', (x) => x.eq('id', id));
    if (!e) return RB.toast('Expense not found.', true);
    let photos = [];
    try { photos = await RB.rpc('rb_expense_photos', { p_id: id }); } catch (err) { photos = []; }
    const c = d.cat[e.category_id] || {}, mine = RB.profile && e.entered_by === RB.profile.id;
    const canPay = e.status === 'posted' && e.payment_mode === 'credit' && Number(e.outstanding_paise) > 0 && (RB.has('cash_bank.add') || RB.has('purchases.add'));
    const m = RB.modal('<h2>' + esc(e.expense_no) + RB.demoBadge(e) + ' ' + status(e.status) + '</h2><div class="m-msg"></div>' +
      '<table class="kv"><tr><td>Date</td><td>' + RB.fmtDate(e.expense_date) + '</td></tr>' +
      '<tr><td>' + (e.direction === 'in' ? 'Money received for' : 'For') + '</td><td><b>' + esc(c.name) + '</b> (account ' + esc(e.account_code) + ')</td></tr>' +
      '<tr><td>Note</td><td>' + esc(e.description) + '</td></tr>' +
      (e.supplier_id || e.payee ? '<tr><td>' + (e.direction === 'in' ? 'From' : 'Paid to') + '</td><td>' + esc(e.supplier_id ? (d.sup[e.supplier_id] || {}).name : e.payee) + '</td></tr>' : '') +
      (e.bill_no ? '<tr><td>Bill</td><td>' + esc(e.bill_no) + (e.bill_date ? ' of ' + RB.fmtDate(e.bill_date) : '') + '</td></tr>' : '') +
      '<tr><td>Amount</td><td>' + RB.rupees(e.amount_paise) + (Number(e.gst_paise) ? ' + GST ' + RB.rupees(e.gst_paise) + (e.gst_claimed ? ' (claimed as input GST)' : ' (part of the cost)') : '') +
      ' = <b>' + RB.rupees(e.total_paise) + '</b></td></tr>' +
      '<tr><td>How</td><td>' + esc(MODES[e.payment_mode]) + (e.money_account_id && d.acct[e.money_account_id] ? ', ' + esc(d.acct[e.money_account_id].name) : '') + (e.reference ? ', ref ' + esc(e.reference) : '') + '</td></tr>' +
      (e.payment_mode === 'credit' && e.status === 'posted' ? '<tr><td>Paid so far</td><td>' + RB.rupees(e.paid_paise) + ' · still owed <b>' + RB.rupees(e.outstanding_paise) + '</b></td></tr>' : '') +
      (e.approved_at ? '<tr><td>Approved</td><td>' + RB.fmtDateTime(e.approved_at) + '</td></tr>' : '') +
      (e.refused_reason ? '<tr><td>Refused</td><td>' + esc(e.refused_reason) + '</td></tr>' : '') +
      (e.reverse_reason ? '<tr><td>Reversed</td><td>' + esc(e.reverse_reason) + '</td></tr>' : '') + '</table>' +
      '<h3>Bill photo</h3><div id="xw-photos">' + (photos.length ? photos.map((p) => '<a href="' + esc(p) + '" target="_blank" rel="noopener"><img src="' + esc(p) + '" alt="Bill photo" style="max-width:180px;max-height:180px;margin:.25rem;border:1px solid #ddd"></a>').join('') : '<p class="muted">No photo yet.</p>') + '</div>' +
      (RB.has('cash_bank.add') && e.status !== 'refused' ? '<div class="field"><label for="xw-file">Add a photo</label><input type="file" id="xw-file" accept="image/*" capture="environment"></div>' : '') +
      '<div class="actions">' +
      (e.status === 'awaiting_approval' && RB.has('cash_bank.approve') ? '<button class="primary" id="xw-ok">Approve</button><button id="xw-no">Refuse</button>' : '') +
      (e.status === 'awaiting_approval' && (mine || RB.has('cash_bank.edit')) ? '<button id="xw-edit">Change</button>' : '') +
      (canPay ? '<button class="primary" id="xw-pay">Pay this bill</button>' : '') +
      (e.status === 'posted' && RB.has('power.reverse_entries') ? '<button class="danger" id="xw-rev">Reverse</button>' : '') +
      (e.status !== 'reversed' && RB.has('cash_bank.delete') ? '<button class="danger" id="xw-del">Delete fully (learning phase)</button>' : '') +
      '<button data-close>Close</button></div>', { wide: true });
    const act = (fn) => async () => { try { await fn(); } catch (err) { RB.modalMsg(m, err.message); } };
    on(m.el, '#xw-file', act(async () => {
      const url = await RB.purchases.photoToDataUrl($('#xw-file', m.el).files[0]);
      await RB.rpc('rb_add_expense_photo', { p_id: id, p_data_url: url });
      RB.toast('Photo added'); m.close(); expenseWindow(id);
    }), 'change');
    on(m.el, '#xw-ok', act(async () => { await RB.rpc('rb_approve_expense', { p_id: id }); RB.toast('Approved and posted'); m.close(); reload(); }));
    on(m.el, '#xw-no', act(async () => {
      const why = await askReason('Refuse ' + e.expense_no, 'It will not reach the books. Say why, so the person who entered it knows.');
      if (!why) return;
      await RB.rpc('rb_refuse_expense', { p_id: id, p_reason: why }); RB.toast('Refused'); m.close(); reload();
    }));
    on(m.el, '#xw-edit', () => { m.close(); expenseModal(e); });
    on(m.el, '#xw-pay', () => { m.close(); RB.purchases.payModal({ supplier_id: e.supplier_id, expense_id: e.id }, reload); });
    on(m.el, '#xw-rev', act(async () => {
      const r = await askReason('Reverse ' + e.expense_no, 'A reversing entry is posted on the date you choose. The original stays on record.', true);
      if (!r) return;
      await RB.rpc('rb_reverse_expense', { p_id: id, p_date: r.date, p_reason: r.reason }); RB.toast('Reversed'); m.close(); reload();
    }));
    on(m.el, '#xw-del', act(async () => {
      if (!(await RB.confirmTyped('Delete ' + e.expense_no + ' fully?', 'Only for a mistake by someone in their learning phase. It disappears from the books as if never entered.', 'DELETE'))) return;
      await RB.rpc('rb_hard_delete_cash_entry', { p_kind: 'expense', p_id: id }); RB.toast('Deleted'); m.close(); reload();
    }));
  }

  // Ask for a reason (and a date, for reversals). Resolves null on cancel.
  function askReason(title, explain, withDate) {
    return new Promise((resolve) => {
      const m = RB.modal('<h2>' + esc(title) + '</h2><p>' + esc(explain) + '</p><div class="m-msg"></div>' +
        (withDate ? RB.field('ar-date', 'Date', '<input type="date" id="ar-date" value="' + RB.today() + '">', null, true) : '') +
        RB.field('ar-why', 'Reason', '<textarea id="ar-why"></textarea>', null, true) +
        '<div class="actions"><button class="primary" id="ar-ok">OK</button><button data-close>Cancel</button></div>');
      $('#ar-ok', m.el).addEventListener('click', () => {
        const why = $('#ar-why', m.el).value.trim();
        if (!why) return RB.modalMsg(m, 'Please give the reason.');
        m.close(); resolve(withDate ? { date: $('#ar-date', m.el).value, reason: why } : why);
      });
      $$('[data-close]', m.el).forEach((b) => b.addEventListener('click', () => resolve(null)));
    });
  }
  C.askReason = askReason;

  // ===================================================================
  // Moving money between cash and bank
  // ===================================================================
  async function transfersTab(tb) {
    const d = await lists();
    const rows = await RB.select('money_transfers', '*', (x) => x.order('transfer_date', { ascending: false }).order('id', { ascending: false }).limit(500));
    tb.innerHTML = '<div class="actions" style="margin:0 0 .75rem">' + (RB.has('cash_bank.add') ? '<button class="primary" id="tr-add">+ Move money</button>' : '') + '</div>' +
      '<p class="muted">Cash paid into the bank, cash drawn from the bank, or money moved between two bank accounts.</p><div id="tr-grid"></div>';
    const grid = RB.grid($('#tr-grid', tb), [
      { title: 'Date', field: 'transfer_date', width: 110, formatter: (c) => RB.fmtDate(c.getValue()) },
      { title: 'No.', field: 'transfer_no', formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
      { title: 'From', field: 'from_account_id', formatter: (c) => esc((d.acct[c.getValue()] || {}).name) },
      { title: 'To', field: 'to_account_id', formatter: (c) => esc((d.acct[c.getValue()] || {}).name) },
      { title: 'Amount', field: 'amount_paise', hozAlign: 'right', formatter: (c) => RB.rupees(c.getValue()) },
      { title: 'Note', field: 'note' },
      { title: 'Status', field: 'status', formatter: (c) => status(c.getValue()) },
    ], rows);
    grid.on('rowClick', (ev, row) => entryWindow('transfer', row.getData(), (t) => (d.acct[t.from_account_id] || {}).name + ' → ' + (d.acct[t.to_account_id] || {}).name));
    on(tb, '#tr-add', () => {
      const opts = d.acctOpts(null);
      const m = RB.modal('<h2>Move money</h2><div class="m-msg"></div>' +
        '<div class="row">' + RB.field('tr-from', 'From', RB.sel('tr-from', opts, d.defaultAcct('cash')), null, true) +
        RB.field('tr-to', 'To', RB.sel('tr-to', opts, d.defaultAcct('bank')), null, true) + '</div>' +
        '<div class="row">' + RB.field('tr-date', 'Date', '<input type="date" id="tr-date" value="' + RB.today() + '">', null, true) +
        RB.field('tr-amt', 'Amount (₹)', RB.inp('tr-amt', '', ' inputmode="decimal"'), null, true) + '</div>' +
        '<div class="row">' + RB.field('tr-ref', 'Reference', RB.inp('tr-ref', '', ' placeholder="deposit slip or cheque no."')) + RB.field('tr-note', 'Note', RB.inp('tr-note', '')) + '</div>' +
        '<div class="actions"><button class="primary" id="tr-save">Save</button><button data-close>Cancel</button></div>');
      $('#tr-save', m.el).addEventListener('click', async () => {
        try {
          await RB.rpc('rb_save_transfer', { p: { from_account_id: Number($('#tr-from', m.el).value), to_account_id: Number($('#tr-to', m.el).value),
            transfer_date: $('#tr-date', m.el).value, amount_paise: RB.toPaise($('#tr-amt', m.el).value), reference: $('#tr-ref', m.el).value, note: $('#tr-note', m.el).value } });
          RB.toast('Saved'); m.close(); reload();
        } catch (e) { RB.modalMsg(m, e.message); }
      });
    });
  }

  // A transfer, partner entry or count: reverse it, or delete it in the learning phase.
  function entryWindow(kind, r, describe) {
    const no = r.transfer_no || r.entry_no || r.count_no;
    const m = RB.modal('<h2>' + esc(no) + RB.demoBadge(r) + ' ' + status(r.status) + '</h2><div class="m-msg"></div><p>' + esc(describe(r)) + '</p>' +
      (r.reverse_reason ? '<p class="muted">Reversed: ' + esc(r.reverse_reason) + '</p>' : '') +
      '<div class="actions">' + (r.status === 'posted' && RB.has('power.reverse_entries') ? '<button class="danger" id="ew-rev">Reverse</button>' : '') +
      (r.status === 'posted' && RB.has('cash_bank.delete') ? '<button class="danger" id="ew-del">Delete fully (learning phase)</button>' : '') +
      '<button data-close>Close</button></div>');
    on(m.el, '#ew-rev', async () => {
      try {
        const x = await askReason('Reverse ' + no, 'A reversing entry is posted on the date you choose.', true); if (!x) return;
        await RB.rpc('rb_reverse_cash_entry', { p_kind: kind, p_id: r.id, p_date: x.date, p_reason: x.reason }); RB.toast('Reversed'); m.close(); reload();
      } catch (e) { RB.modalMsg(m, e.message); }
    });
    on(m.el, '#ew-del', async () => {
      try {
        if (!(await RB.confirmTyped('Delete ' + no + ' fully?', 'Only for a mistake by someone in their learning phase.', 'DELETE'))) return;
        await RB.rpc('rb_hard_delete_cash_entry', { p_kind: kind, p_id: r.id }); RB.toast('Deleted'); m.close(); reload();
      } catch (e) { RB.modalMsg(m, e.message); }
    });
  }

  // ===================================================================
  // Day-end cash count
  // ===================================================================
  async function countsTab(tb) {
    const d = await lists();
    const rows = await RB.select('cash_counts', '*', (x) => x.order('count_date', { ascending: false }).order('id', { ascending: false }).limit(500));
    tb.innerHTML = '<div class="actions" style="margin:0 0 .75rem">' + (RB.has('cash_bank.add') ? '<button class="primary" id="cc-add">+ Count the cash</button>' : '') + '</div>' +
      '<p class="muted">At the end of the day, count the cash in the till. Any difference from the books is posted at once, with its reason.</p><div id="cc-grid"></div>';
    const grid = RB.grid($('#cc-grid', tb), [
      { title: 'Date', field: 'count_date', width: 110, formatter: (c) => RB.fmtDate(c.getValue()) },
      { title: 'No.', field: 'count_no', formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
      { title: 'Account', field: 'money_account_id', formatter: (c) => esc((d.acct[c.getValue()] || {}).name) },
    ].concat(totalsOk() ? [{ title: 'In the books', field: 'book_paise', hozAlign: 'right', formatter: (c) => RB.rupees(c.getValue()) }] : []).concat([
      { title: 'Counted', field: 'counted_paise', hozAlign: 'right', formatter: (c) => RB.rupees(c.getValue()) },
      { title: 'Difference', field: 'difference_paise', hozAlign: 'right', formatter: (c) => (Number(c.getValue()) ? (c.getValue() < 0 ? 'Short ' : 'Over ') + RB.rupees(Math.abs(c.getValue())) : '✓') },
      { title: 'Reason', field: 'reason' },
      { title: 'Status', field: 'status', formatter: (c) => status(c.getValue()) },
    ]), rows);
    grid.on('rowClick', (ev, row) => entryWindow('count', row.getData(), (r) => 'Counted ' + RB.rupees(r.counted_paise) + ' on ' + RB.fmtDate(r.count_date)));
    on(tb, '#cc-add', async () => {
      const cashes = d.acctOpts('cash');
      const m = RB.modal('<h2>Count the cash</h2><div class="m-msg"></div>' +
        '<div class="row">' + RB.field('cc-acc', 'Cash account', RB.sel('cc-acc', cashes, d.defaultAcct('cash')), null, true) +
        RB.field('cc-date', 'Date', '<input type="date" id="cc-date" value="' + RB.today() + '">', null, true) + '</div>' +
        '<p class="muted">Count the notes and coins (or just type the total below).</p>' +
        '<div class="grid-wrap"><table class="ticks lines"><thead><tr><th>Note</th><th>How many</th><th>Value</th></tr></thead><tbody>' +
        NOTES.map((n) => '<tr><td>₹' + n + '</td><td><input data-note="' + n + '" inputmode="numeric"></td><td data-val="' + n + '"></td></tr>').join('') +
        '<tr><td>Coins (₹)</td><td><input id="cc-coins" inputmode="decimal"></td><td></td></tr></tbody></table></div>' +
        '<div class="row">' + RB.field('cc-total', 'Cash counted (₹)', RB.inp('cc-total', '', ' inputmode="decimal"'), null, true) +
        '<div class="field"><label>In the books</label><p id="cc-book" class="muted">' + (totalsOk() ? '…' : 'Not shown to you') + '</p></div></div>' +
        RB.field('cc-why', 'Reason for any difference', RB.inp('cc-why', '', ' placeholder="e.g. change given short"')) +
        '<div class="actions"><button class="primary" id="cc-save">Save the count</button><button data-close>Cancel</button></div>', { wide: true });
      const book = async () => {
        if (!totalsOk()) return;
        try {
          const x = await RB.rpc('rb_cash_book', { p_account: Number($('#cc-acc', m.el).value), p_from: $('#cc-date', m.el).value, p_to: $('#cc-date', m.el).value });
          $('#cc-book', m.el).textContent = RB.rupees(x.closing_paise);
        } catch (e) { $('#cc-book', m.el).textContent = ''; }
      };
      const sum = () => {
        let t = 0;
        $$('[data-note]', m.el).forEach((el) => { const n = Number(el.value) || 0; t += n * Number(el.dataset.note) * 100; $('[data-val="' + el.dataset.note + '"]', m.el).textContent = n ? RB.rupees(n * Number(el.dataset.note) * 100) : ''; });
        try { t += RB.toPaise($('#cc-coins', m.el).value) || 0; } catch (e) { /* later */ }
        if (t) $('#cc-total', m.el).value = RB.fromPaise(t);
      };
      $$('[data-note], #cc-coins', m.el).forEach((el) => el.addEventListener('input', sum));
      ['#cc-acc', '#cc-date'].forEach((s) => $(s, m.el).addEventListener('change', book)); book();
      $('#cc-save', m.el).addEventListener('click', async () => {
        try {
          const denominations = {}; $$('[data-note]', m.el).forEach((el) => { if (Number(el.value)) denominations[el.dataset.note] = Number(el.value); });
          if ($('#cc-coins', m.el).value) denominations.coins_paise = RB.toPaise($('#cc-coins', m.el).value);
          const id = await RB.rpc('rb_save_cash_count', { p: { money_account_id: Number($('#cc-acc', m.el).value), count_date: $('#cc-date', m.el).value,
            counted_paise: RB.toPaise($('#cc-total', m.el).value), reason: $('#cc-why', m.el).value, denominations } });
          const [r] = await RB.select('cash_counts', 'difference_paise', (x) => x.eq('id', id));
          RB.toast(r && Number(r.difference_paise) ? 'Saved. Difference of ' + RB.rupees(Math.abs(r.difference_paise)) + ' posted.' : 'Saved. The cash agrees with the books.');
          m.close(); reload();
        } catch (e) { RB.modalMsg(m, e.message); }
      });
    });
  }

  // ===================================================================
  // Partners: capital brought in or taken out, and drawings
  // ===================================================================
  async function partnersTab(tb) {
    const d = await lists();
    const [bal, rows] = await Promise.all([RB.rpc('rb_partner_balances', { p_as_of: RB.today() }),
      RB.select('partner_entries', '*', (x) => x.order('entry_date', { ascending: false }).order('id', { ascending: false }).limit(500))]);
    const pname = (id) => ((d.partners.find((p) => p.id === id) || {}).name || 'Partner ' + id);
    tb.innerHTML = '<div class="actions" style="margin:0 0 .75rem">' + (RB.has('cash_bank.edit') ? '<button class="primary" id="pt-add">+ Capital or drawings</button>' : '') + '</div>' +
      '<div class="card"><h2>Partners\' accounts</h2><div class="grid-wrap"><table class="ticks"><thead><tr><th>Partner</th><th>Capital account</th><th>Current account</th></tr></thead><tbody>' +
      bal.map((b) => '<tr><td>' + esc(b.name) + '</td><td>' + RB.rupees(b.capital_paise) + '</td><td>' + RB.rupees(b.current_paise) + '</td></tr>').join('') +
      '</tbody></table></div><p class="hint">Amounts the firm owes the partner. Drawings reduce the current account; the year\'s profit share is added at the year end.</p></div><div id="pt-grid"></div>';
    const grid = RB.grid($('#pt-grid', tb), [
      { title: 'Date', field: 'entry_date', width: 110, formatter: (c) => RB.fmtDate(c.getValue()) },
      { title: 'No.', field: 'entry_no', formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
      { title: 'Partner', field: 'partner_id', formatter: (c) => esc(pname(c.getValue())) },
      { title: 'What', field: 'kind', formatter: (c) => esc(PARTNER_KIND[c.getValue()]) },
      { title: 'Account', field: 'money_account_id', formatter: (c) => esc((d.acct[c.getValue()] || {}).name) },
      { title: 'Amount', field: 'amount_paise', hozAlign: 'right', formatter: (c) => RB.rupees(c.getValue()) },
      { title: 'Note', field: 'note' },
      { title: 'Status', field: 'status', formatter: (c) => status(c.getValue()) },
    ], rows);
    grid.on('rowClick', (ev, row) => entryWindow('partner', row.getData(), (r) => PARTNER_KIND[r.kind] + ': ' + pname(r.partner_id) + ', ' + RB.rupees(r.amount_paise)));
    on(tb, '#pt-add', () => {
      const m = RB.modal('<h2>Partner\'s capital or drawings</h2><div class="m-msg"></div>' +
        '<div class="row">' + RB.field('pt-kind', 'What', RB.sel('pt-kind', Object.entries(PARTNER_KIND), 'capital_in'), null, true) +
        RB.field('pt-who', 'Partner', RB.sel('pt-who', d.partners.map((p) => [p.id, p.name])), null, true) + '</div>' +
        '<div class="row">' + RB.field('pt-date', 'Date', '<input type="date" id="pt-date" value="' + RB.today() + '">', null, true) +
        RB.field('pt-amt', 'Amount (₹)', RB.inp('pt-amt', '', ' inputmode="decimal"'), null, true) +
        RB.field('pt-acc', 'Cash or bank account', RB.sel('pt-acc', d.acctOpts(null), d.defaultAcct('bank')), null, true) + '</div>' +
        '<div class="row">' + RB.field('pt-ref', 'Reference', RB.inp('pt-ref', '')) + RB.field('pt-note', 'Note', RB.inp('pt-note', '')) + '</div>' +
        '<div class="actions"><button class="primary" id="pt-save">Save</button><button data-close>Cancel</button></div>');
      $('#pt-save', m.el).addEventListener('click', async () => {
        try {
          await RB.rpc('rb_save_partner_entry', { p: { kind: $('#pt-kind', m.el).value, partner_id: Number($('#pt-who', m.el).value), entry_date: $('#pt-date', m.el).value,
            amount_paise: RB.toPaise($('#pt-amt', m.el).value), money_account_id: Number($('#pt-acc', m.el).value), reference: $('#pt-ref', m.el).value, note: $('#pt-note', m.el).value } });
          RB.toast('Saved'); m.close(); reload();
        } catch (e) { RB.modalMsg(m, e.message); }
      });
    });
  }

  // ===================================================================
  // Bank reconciliation: tick what is on the statement
  // ===================================================================
  async function bankTab(tb) {
    const d = await lists();
    const banks = d.accts.filter((a) => a.kind === 'bank' && a.is_active);
    tb.innerHTML = '<p class="muted">Once a month, tick each entry that appears on the bank statement and type the statement\'s closing balance. ' +
      'When the ticked entries agree with the statement, press Finish. Entries not yet on the statement (a cheque not yet cleared) carry to next month.</p>' +
      '<div class="row" style="align-items:flex-end">' + RB.field('br-acc', 'Bank account', RB.sel('br-acc', banks.map((a) => [a.id, a.name]))) +
      RB.field('br-month', 'Month', '<input type="month" id="br-month" value="' + lastMonth().slice(0, 7) + '">') +
      '<div class="field" style="flex:0 1 auto"><button id="br-go">Show</button></div></div><div id="br-body"></div>';
    const load = async () => {
      const acc = Number($('#br-acc', tb).value), month = $('#br-month', tb).value + '-01';
      const x = await RB.rpc('rb_bank_recon', { p_account: acc, p_month: month });
      const r = x.recon || {}, done = r.status === 'done', box = $('#br-body', tb);
      const prior = Number(x.cleared_balance_paise) - x.lines.filter((l) => l.cleared).reduce((s, l) => s + Number(l.in_paise) - Number(l.out_paise), 0);
      box.innerHTML = (x.earlier_open ? '<div class="msg info">' + x.earlier_open + ' earlier month(s) are not finished yet. Do those first.</div>' : '') +
        '<div class="card"><div class="row facts">' + fact('Balance in the books at ' + RB.fmtDate(x.month_end), RB.rupees(x.book_balance_paise)) +
        fact('Ticked entries come to', '<span id="br-cleared"></span>') + fact('Difference', '<span id="br-diff"></span>') +
        fact('Status', done ? status('done', { done: 'Reconciled' }) : status('draft', { draft: 'Not finished' })) + '</div>' +
        '<div class="row">' + RB.field('br-stmt', 'Closing balance on the statement (₹)', RB.inp('br-stmt', r.statement_balance_paise == null ? '' : RB.fromPaise(r.statement_balance_paise), ' inputmode="decimal"' + (done ? ' disabled' : '')), null, true) +
        RB.field('br-note', 'Note', RB.inp('br-note', r.note, done ? ' disabled' : '')) + '</div>' +
        '<div class="actions">' + (done ? (RB.has('cash_bank.approve') ? '<button id="br-reopen">Reopen</button>' : '') :
          '<button id="br-all">Tick all</button><button id="br-save">Save ticks</button><button class="primary" id="br-finish">Finish the month</button>') + '</div></div>' +
        '<div class="grid-wrap"><table class="ticks lines"><thead><tr><th>Date</th><th>On statement</th><th>Entry</th><th>Details</th><th>In</th><th>Out</th></tr></thead><tbody>' +
        (x.lines.length ? x.lines.map((l, i) => '<tr><td>' + RB.fmtDate(l.date) + '</td><td>' + (l.cleared_later ? '<small>later month</small>' :
          '<input type="checkbox" data-tick="' + i + '"' + (l.cleared ? ' checked' : '') + (done ? ' disabled' : '') + ' style="width:24px;height:24px">') + '</td>' +
          '<td>' + esc(l.ref || l.journal_no) + RB.demoBadge(l) + '</td><td style="text-align:left">' + esc(l.narration) + '</td><td>' + amt(l.in_paise) + '</td><td>' + amt(l.out_paise) + '</td></tr>').join('')
          : '<tr><td colspan="6" class="muted">No entries to reconcile.</td></tr>') + '</tbody></table></div>';
      const calc = () => {
        let t = prior;
        $$('[data-tick]', box).forEach((el) => { if (el.checked) { const l = x.lines[Number(el.dataset.tick)]; t += Number(l.in_paise) - Number(l.out_paise); } });
        $('#br-cleared', box).textContent = RB.rupees(t);
        let st = null; try { st = RB.toPaise($('#br-stmt', box).value); } catch (e) { st = null; }
        $('#br-diff', box).innerHTML = st == null ? '<span class="muted">enter the statement balance</span>' : st - t === 0 ? '<span style="color:var(--leaf)">₹0.00 ✓</span>' : '<span class="diff-count">' + RB.rupees(Math.abs(st - t)) + '</span>';
      };
      $$('[data-tick]', box).forEach((el) => el.addEventListener('change', calc));
      on(box, '#br-stmt', calc, 'input'); calc();
      const save = async (finish) => {
        const ticks = $$('[data-tick]', box).map((el) => ({ line_id: x.lines[Number(el.dataset.tick)].line_id, cleared: el.checked }));
        await RB.rpc('rb_save_bank_recon', { p: { account_id: acc, month, statement_balance_paise: RB.toPaise($('#br-stmt', box).value), note: $('#br-note', box).value, finish, ticks } });
        RB.toast(finish ? 'Month reconciled' : 'Ticks saved'); await load();
      };
      on(box, '#br-all', () => { $$('[data-tick]', box).forEach((el) => { el.checked = true; }); calc(); });
      on(box, '#br-save', () => save(false).catch((e) => RB.toast(e.message, true)));
      on(box, '#br-finish', () => save(true).catch((e) => RB.toast(e.message, true)));
      on(box, '#br-reopen', async () => {
        try {
          const why = await askReason('Reopen ' + monthName(month), 'The month can be changed again and must be finished again.'); if (!why) return;
          await RB.rpc('rb_reopen_bank_recon', { p_account: acc, p_month: month, p_reason: why }); await load();
        } catch (e) { RB.toast(e.message, true); }
      });
    };
    if (!banks.length) { $('#br-body', tb).innerHTML = '<p class="muted">No bank account is switched on. See Set-up.</p>'; return; }
    on(tb, '#br-go', () => load().catch((e) => RB.toast(e.message, true)));
    await load();
  }

  // ===================================================================
  // Month-end: checklist, labour and overheads into stock, provision
  // ===================================================================
  async function monthEndTab(tb) {
    tb.innerHTML = '<div class="row" style="align-items:flex-end">' + RB.field('me-month', 'Month', '<input type="month" id="me-month" value="' + (C.meMonth || lastMonth()).slice(0, 7) + '">') +
      '<div class="field" style="flex:0 1 auto"><button id="me-go">Show</button></div></div><div id="me-body"></div>';
    const load = async () => {
      const month = $('#me-month', tb).value + '-01'; C.meMonth = month;
      const box = $('#me-body', tb);
      const st = await RB.rpc('rb_month_end_status', { p_month: month });
      const tick = (ok, text) => '<li>' + (ok ? '✅ ' : '⬜ ') + text + '</li>';
      box.innerHTML = '<div class="card"><h2>Checklist for ' + esc(monthName(month)) + '</h2><ol style="padding-left:1.2rem">' +
        tick(st.waiting_expenses === 0, st.waiting_expenses ? st.waiting_expenses + ' expense(s) still waiting for approval' : 'No expenses waiting for approval') +
        tick(st.draft_journals === 0, st.draft_journals ? st.draft_journals + ' draft journal(s) in Accounts' : 'No draft journals') +
        st.cash.map((c) => tick(c.last_count && c.last_count >= st.month_end, esc(c.name) + ': ' + (c.last_count ? 'last counted ' + RB.fmtDate(c.last_count) : 'not counted yet'))).join('') +
        st.banks.map((b) => tick(b.status === 'done', esc(b.name) + ': bank reconciliation ' + (b.status === 'done' ? 'finished' : b.status === 'draft' ? 'started, not finished' : 'not started'))).join('') +
        (RB.screens.loans ? tick(st.runs.some((r) => r.kind === 'loans_leases' && r.status === 'posted'), 'Before step 1: loans and leases month-end (Loans and leases → Month-end)') : '') +
        tick(st.runs.some((r) => r.kind === 'absorption' && r.status === 'posted'), 'Step 1: kitchen labour and overheads added to stock (' + st.batches + ' batch(es) this month)') +
        tick(st.runs.some((r) => r.kind === 'doubtful_debts' && r.status === 'posted'), 'Step 2: provision for doubtful debts') +
        tick(st.locked, 'Lock the month (Accounts → Month lock), once everything above is done') + '</ol>' +
        '<p class="hint">Run the two steps early in the following month, after the last bills of the month are in, then lock the month.</p></div>' +
        '<div class="card" id="me-abs"><p class="muted">Loading step 1…</p></div><div class="card" id="me-prov"><p class="muted">Loading step 2…</p></div>';
      if (!monthEndOk()) {
        $('#me-abs', box).innerHTML = '<p class="muted">The month-end steps are run by the Accountant, the FC or a Director.</p>'; $('#me-prov', box).remove(); return;
      }
      await absorptionCard($('#me-abs', box), month, load);
      await provisionCard($('#me-prov', box), month, load);
    };
    on(tb, '#me-go', () => load().catch((e) => RB.toast(e.message, true)));
    await load();
  }

  C.hours = {};
  async function absorptionCard(el, month, again) {
    const hours = C.hours[month] || {};
    const x = await RB.rpc('rb_absorption_preview', { p_month: month, p_hours: hours });
    const t = x.detail, posted = x.posted;
    const methodCell = (k) => (x.compare[k] == null ? '<span class="muted">enter hours</span>' : RB.rupees(x.compare[k]));
    el.innerHTML = '<h2>Step 1 · Kitchen labour and overheads into stock (AS 2)</h2>' +
      (x.demo ? '<div class="msg info">This month has no real batches yet, so this works on the DEMO records.</div>' : '') +
      '<p class="muted">Stock is valued at what it cost to make: materials, and also the kitchen\'s wages, gas, rent and other production costs of the month. ' +
      'The part that belongs to goods still on hand at month-end goes into stock; the rest stays in profit and loss. Selling and office costs never go into stock.</p>' +
      '<div class="row facts">' + fact('Labour and overheads this month', RB.rupees(t.pool_paise)) +
      fact('Normal monthly output', x.normal_output_kg ? x.normal_output_kg + ' kg (made ' + t.actual_output_kg + ' kg)' : 'not set') +
      fact('Not shared (low output)', RB.rupees(t.under_absorbed_paise)) +
      fact('Into stock still on hand', '<span style="font-size:1.2rem">' + RB.rupees(t.capitalised_paise) + '</span>') + fact('Stays in profit and loss', RB.rupees(t.stays_in_pl_paise)) + '</div>' +
      '<h3>Shared by: ' + esc(METHOD[x.method]) + '</h3>' +
      '<div class="grid-wrap"><table class="ticks"><thead><tr><th>Method</th><th>Into stock</th></tr></thead><tbody>' +
      Object.keys(METHOD).map((k) => '<tr' + (k === x.method ? ' style="font-weight:700"' : '') + '><td>' + esc(METHOD[k]) + (k === x.method ? ' (in use)' : '') + '</td><td>' + methodCell(k) + '</td></tr>').join('') +
      '</tbody></table></div><p class="hint">The comparison is for information. One method is kept from month to month; a Director can change it in Set-up, with a reason.</p>' +
      '<details><summary>Accounts in the pool</summary><table class="ticks"><thead><tr><th>Account</th><th>Fixed or variable</th><th>Amount</th></tr></thead><tbody>' +
      t.pool.filter((p) => Number(p.amount_paise)).map((p) => '<tr><td>' + esc(p.code + ' ' + p.name) + '</td><td>' + esc(p.behaviour) + '</td><td>' + RB.rupees(p.amount_paise) + '</td></tr>').join('') + '</tbody></table></details>' +
      '<details' + (x.method === 'hours' ? ' open' : '') + '><summary>Batches of the month (' + t.batches.length + ')</summary><div class="grid-wrap"><table class="ticks lines"><thead><tr><th>Batch</th><th>Kind</th><th>Date</th><th>Kg</th><th>Materials</th><th>Hours worked</th><th>Share</th><th>Taken over</th></tr></thead><tbody>' +
      t.batches.map((b) => '<tr><td>' + esc(b.batch_no) + '<br><small>' + esc(b.label) + '</small></td><td>' + (b.kind === 'preparation' ? 'Preparation' : 'Production') + '</td><td>' + RB.fmtDate(b.batch_date) + '</td><td>' + esc(b.kg) + '</td><td>' + RB.rupees(b.material_paise) + '</td>' +
        '<td><input data-hrs="' + b.id + '" inputmode="decimal" value="' + esc(hours[b.id] == null ? (b.hours == null ? '' : b.hours) : hours[b.id]) + '"' + (posted ? ' disabled' : '') + ' style="max-width:90px"></td>' +
        '<td>' + RB.rupees(b.share_paise) + '</td><td>' + amt(b.received_paise) + '</td></tr>').join('') + '</tbody></table></div>' +
      (posted ? '' : '<button id="ab-hrs">Use these hours</button>') + '</details>' +
      '<details><summary>Where it goes</summary><table class="ticks"><thead><tr><th>Stock</th><th>Made</th><th>On hand at month-end</th><th>Share</th><th>Into stock</th></tr></thead><tbody>' +
      t.wip.map((w) => '<tr><td>' + esc(w.label) + ' (' + esc(w.batch_no) + ')</td><td>' + RB.stock.q(w.made, 'g') + '</td><td>' + RB.stock.q(w.on_hand, 'g') + '</td><td>' + RB.rupees(w.share_paise) + '</td><td>' + RB.rupees(w.capitalised_paise) + '</td></tr>').join('') +
      t.products.map((p) => '<tr><td>' + esc(p.label) + '</td><td>' + RB.stock.q(p.made, p.unit) + '</td><td>' + RB.stock.q(p.on_hand, p.unit) + '</td><td>' + RB.rupees(p.absorbed_paise) + '</td><td>' + RB.rupees(p.capitalised_paise) + '</td></tr>').join('') +
      '</tbody></table></details>' +
      '<div class="actions">' + (posted ? '<p>✅ Posted as <b>' + esc(posted.run_no) + '</b>: ' + RB.rupees(posted.amount_paise) + ' added to stock.</p><button class="danger" id="ab-rev">Reverse this run</button>'
        : '<button class="primary" id="ab-post"' + (Number(t.pool_paise) === 0 ? ' disabled' : '') + '>Post: add ' + RB.rupees(t.capitalised_paise) + ' to stock</button>') + '</div>';
    on(el, '#ab-hrs', () => {
      const h = {}; $$('[data-hrs]', el).forEach((i) => { try { const n = num(i.value); if (n != null) h[i.dataset.hrs] = n; } catch (e) { /* skipped */ } });
      C.hours[month] = h; absorptionCard(el, month, again).catch((e) => RB.toast(e.message, true));
    });
    on(el, '#ab-post', async () => {
      try {
        if (!(await RB.confirm('Post step 1 for ' + monthName(month) + '?', 'Adds ' + RB.rupees(t.capitalised_paise) + ' of kitchen labour and overheads to the stock still on hand at ' + RB.fmtDate(t.month_end) + '.'))) return;
        await RB.rpc('rb_post_absorption', { p_month: month, p_hours: C.hours[month] || {}, p_demo: x.demo }); RB.toast('Posted'); again();
      } catch (e) { RB.toast(e.message, true); }
    });
    on(el, '#ab-rev', async () => {
      try {
        const why = await askReason('Reverse ' + posted.run_no, 'Takes the overheads out of stock again, for example to correct a batch or a bill and run it again.'); if (!why) return;
        await RB.rpc('rb_reverse_month_end', { p_id: posted.id, p_reason: why }); RB.toast('Reversed'); again();
      } catch (e) { RB.toast(e.message, true); }
    });
  }

  async function provisionCard(el, month, again) {
    const x = await RB.rpc('rb_provision_preview', { p_month: month });
    const posted = x.posted, chg = Number(x.change_paise);
    el.innerHTML = '<h2>Step 2 · Provision for doubtful debts</h2>' +
      (x.demo ? '<div class="msg info">No real customer balances yet, so this works on the DEMO records.</div>' : '') +
      (x.rates_example ? '<div class="msg error">The rates below are only an example. Ask the CA for the rates and enter them in Settings → Expenses and month-end before posting for real.</div>' : '') +
      (x.rates_all_zero ? '<div class="msg info">All rates are 0%, so no provision is needed. Enter the CA\'s rates in Settings.</div>' : '') +
      '<p class="muted">Customer balances at ' + RB.fmtDate(x.month_end) + ', by how many days past the due date. The CA\'s rate for each band gives the provision needed; only the change from last time is posted.' +
      (x.rates_note ? ' Rates: ' + esc(x.rates_note.replace(/\.+$/, '')) + '.' : '') + '</p>' +
      '<div class="grid-wrap"><table class="ticks"><thead><tr><th>Age band</th><th>Owed</th><th>Rate</th><th>Provision</th></tr></thead><tbody>' +
      x.bands.map((b) => '<tr><td>' + esc(b.label) + '</td><td>' + RB.rupees(b.amount_paise) + '</td><td>' + Number(b.pct) + '%</td><td>' + RB.rupees(b.provision_paise) + '</td></tr>').join('') +
      '<tr><td>' + esc(x.other.label) + '</td><td>' + RB.rupees(x.other.amount_paise) + '</td><td>' + Number(x.other.pct) + '%</td><td>' + RB.rupees(x.other.provision_paise) + '</td></tr>' +
      '</tbody></table></div>' +
      '<div class="row facts">' + fact('Provision needed', RB.rupees(x.required_paise)) + fact('Already held', RB.rupees(x.existing_paise)) +
      fact(chg >= 0 ? 'To add (expense)' : 'To write back (income)', '<span style="font-size:1.2rem">' + RB.rupees(Math.abs(chg)) + '</span>') + '</div>' +
      (x.customers.length ? '<details><summary>By customer (' + x.customers.length + ')</summary><table class="ticks"><thead><tr><th>Customer</th><th>Balance</th><th>Provision</th></tr></thead><tbody>' +
        x.customers.map((c) => '<tr><td>' + esc(c.code + ' ' + c.name) + '</td><td>' + RB.rupees(c.balance_paise) + '</td><td>' + RB.rupees(c.provision_paise) + '</td></tr>').join('') + '</tbody></table></details>' : '') +
      '<div class="actions">' + (posted ? '<p>✅ Posted as <b>' + esc(posted.run_no) + '</b>.</p><button class="danger" id="pv-rev">Reverse this run</button>'
        : '<button class="primary" id="pv-post">Post the provision' + (chg ? ' (' + (chg > 0 ? '+' : '−') + RB.rupees(Math.abs(chg)) + ')' : '') + '</button>') + '</div>';
    on(el, '#pv-post', async () => {
      try {
        if (!(await RB.confirm('Post step 2 for ' + monthName(month) + '?', 'Sets the provision for doubtful debts to ' + RB.rupees(x.required_paise) + '.'))) return;
        await RB.rpc('rb_post_provision', { p_month: month, p_demo: x.demo }); RB.toast('Posted'); again();
      } catch (e) { RB.toast(e.message, true); }
    });
    on(el, '#pv-rev', async () => {
      try {
        const why = await askReason('Reverse ' + posted.run_no, 'Takes this provision change back out, for example to run it again with new rates.'); if (!why) return;
        await RB.rpc('rb_reverse_month_end', { p_id: posted.id, p_reason: why }); RB.toast('Reversed'); again();
      } catch (e) { RB.toast(e.message, true); }
    });
  }

  // ===================================================================
  // Expense report
  // ===================================================================
  async function reportTab(tb) {
    tb.innerHTML = '<div class="row" style="align-items:flex-end">' +
      RB.field('rp-from', 'From', '<input type="date" id="rp-from" value="' + monthStart() + '">') + RB.field('rp-to', 'To', '<input type="date" id="rp-to" value="' + RB.today() + '">') +
      '<div class="field" style="flex:0 1 auto"><button id="rp-go">Show</button> <button id="rp-xls">Download to Excel</button></div></div><div id="rp-grid"></div>';
    let grid;
    const load = async () => {
      const rows = await RB.rpc('rb_expense_report', { p_from: $('#rp-from', tb).value, p_to: $('#rp-to', tb).value });
      grid = RB.grid($('#rp-grid', tb), [
        { title: 'Month', field: 'month', formatter: (c) => esc(monthName(c.getValue())) },
        { title: 'In or out', field: 'direction', formatter: (c) => (c.getValue() === 'in' ? 'Money received' : 'Expense') },
        { title: 'Category', field: 'category', minWidth: 180, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
        { title: 'Account', field: 'account_code' },
        { title: 'Department', field: 'department' },
        { title: 'Entries', field: 'entries', hozAlign: 'right' },
        { title: 'Before GST', field: 'amount_paise', hozAlign: 'right', formatter: (c) => RB.rupees(c.getValue()), bottomCalc: 'sum', bottomCalcFormatter: (c) => RB.rupees(c.getValue()) },
        { title: 'GST', field: 'gst_paise', hozAlign: 'right', formatter: (c) => amt(c.getValue()) },
        { title: 'Total', field: 'total_paise', hozAlign: 'right', formatter: (c) => RB.rupees(c.getValue()) },
      ], rows);
    };
    on(tb, '#rp-go', () => load().catch((e) => RB.toast(e.message, true)));
    on(tb, '#rp-xls', () => grid && RB.downloadExcel(grid, 'Expense report'));
    await load();
  }

  // ===================================================================
  // Set-up: cash and bank accounts, categories, month-end set-up
  // ===================================================================
  async function setupTab(tb) {
    const d = await lists();
    const edit = RB.has('cash_bank.edit');
    let absAccts = [], accounts = [];
    if (monthEndOk()) {
      [absAccts, accounts] = await Promise.all([RB.select('absorption_accounts', '*', (x) => x.order('account_code')),
        RB.select('accounts', 'code,name,local_name,class,level,e002_active', (x) => x.gte('code', '70020000').lt('code', '70040000').eq('level', 'posting').order('code'))]);
    }
    const absOn = Object.fromEntries(absAccts.map((a) => [a.account_code, a.behaviour]));
    tb.innerHTML =
      '<div class="card"><h2>Cash and bank accounts</h2><p class="muted">Up to four bank accounts. The main one is used when no account is chosen (sales, purchases and UPI payments).</p>' +
      '<div class="grid-wrap"><table class="ticks lines"><thead><tr><th>Name</th><th>Kind</th><th>Account code</th><th>Bank</th><th>Status</th></tr></thead><tbody>' +
      d.accts.map((a, i) => '<tr class="' + (edit ? 'click' : '') + '" data-acc="' + i + '"><td>' + esc(a.name) + (a.is_default ? ' ' + RB.badge('active', 'Main') : '') + '</td><td>' + (a.kind === 'cash' ? 'Cash' : 'Bank') + '</td><td>' + esc(a.account_code) +
        '</td><td>' + esc([a.bank_name, a.account_last4 ? '…' + a.account_last4 : '', a.upi_id].filter(Boolean).join(' · ')) + '</td><td>' + RB.activeBadge(a.is_active) + '</td></tr>').join('') +
      '</tbody></table></div></div>' +
      '<div class="card"><h2>Expense categories</h2>' + (edit ? '<button id="su-cat-add">+ Add category</button>' : '') + '<div id="su-cats"></div></div>' +
      (monthEndOk() ? '<div class="card"><h2>Month-end step 1 set-up</h2>' +
        '<div class="row"><div class="field"><label>Sharing method</label><p><b>' + esc(METHOD[d.settings.absorption_method] || d.settings.absorption_method) + '</b></p>' +
        '<button id="su-method">Change the method (Director)</button></div>' +
        RB.field('su-norm', 'Normal monthly output (kg)', RB.inp('su-norm', d.settings.normal_output_kg, ' inputmode="decimal" placeholder="not set"'),
          'The output the kitchen makes in a normal month. In a slow month, the fixed costs for the unused part stay in profit and loss (AS 2). Leave blank to share everything.') + '</div>' +
        '<p class="muted">Tick the production cost accounts (7002 labour, 7003 production overheads) shared into stock. Fixed costs do not change with output; variable ones do.</p>' +
        '<div class="grid-wrap"><table class="ticks lines"><thead><tr><th>Account</th><th>Shared into stock</th><th>Fixed or variable</th></tr></thead><tbody>' +
        accounts.filter((a) => a.e002_active && (a.code.startsWith('7002') || a.code.startsWith('7003')) && a.code !== '70030140').map((a) =>
          '<tr><td>' + esc(a.code + ' ' + (a.local_name || a.name)) + '</td><td><input type="checkbox" data-abs="' + a.code + '"' + (absOn[a.code] ? ' checked' : '') + ' style="width:24px;height:24px"></td>' +
          '<td>' + RB.sel('abs-b-' + a.code, [['fixed', 'Fixed'], ['variable', 'Variable']], absOn[a.code] || 'fixed', ' data-absb="' + a.code + '"') + '</td></tr>').join('') +
        '</tbody></table></div><div class="actions"><button class="primary" id="su-abs-save">Save month-end set-up</button></div></div>' : '');
    $$('[data-acc]', tb).forEach((r) => r.addEventListener('click', () => edit && accountModal(d.accts[Number(r.dataset.acc)])));
    const catGrid = RB.grid($('#su-cats', tb), [
      { title: 'Name', field: 'name', minWidth: 220 },
      { title: 'In or out', field: 'direction', formatter: (c) => (c.getValue() === 'in' ? 'Money received' : 'Expense') },
      { title: 'Account', field: 'account_code' },
      { title: 'Department', field: 'default_department_code' },
      { title: 'Into stock at month-end', field: 'account_code', formatter: (c) => (absOn[c.getValue()] ? 'Yes' : '') },
      { title: 'Status', field: 'is_active', formatter: (c) => RB.activeBadge(c.getValue()) },
    ], d.cats);
    if (edit) catGrid.on('rowClick', (e, row) => categoryModal(row.getData(), d));
    on(tb, '#su-cat-add', () => categoryModal(null, d));
    on(tb, '#su-method', () => methodModal(d.settings.absorption_method));
    on(tb, '#su-abs-save', async () => {
      try {
        const list = $$('[data-abs]', tb).map((c) => ({ code: c.dataset.abs, include: c.checked, behaviour: $('[data-absb="' + c.dataset.abs + '"]', tb).value }));
        await RB.rpc('rb_save_absorption_setup', { p: { normal_output_kg: $('#su-norm', tb).value.trim(), accounts: list } });
        RB.toast('Saved'); reload();
      } catch (e) { RB.toast(e.message, true); }
    });
  }

  function accountModal(a) {
    const m = RB.modal('<h2>' + esc(a.name) + '</h2><div class="m-msg"></div><p class="muted">Account ' + esc(a.account_code) + ' (' + (a.kind === 'cash' ? 'cash' : 'bank') + ')</p>' +
      RB.field('ma-name', 'Name', RB.inp('ma-name', a.name), null, true) +
      (a.kind === 'bank' ? '<div class="row">' + RB.field('ma-bank', 'Bank', RB.inp('ma-bank', a.bank_name)) + RB.field('ma-last4', 'Last 4 digits', RB.inp('ma-last4', a.account_last4, ' maxlength="4" inputmode="numeric"')) +
        RB.field('ma-upi', 'UPI ID', RB.inp('ma-upi', a.upi_id)) + '</div>' : '') +
      '<label class="check"><input type="checkbox" id="ma-on"' + (a.is_active ? ' checked' : '') + '> Switched on</label>' +
      '<label class="check"><input type="checkbox" id="ma-def"' + (a.is_default ? ' checked disabled' : '') + '> Main ' + a.kind + ' account</label>' +
      '<div class="actions"><button class="primary" id="ma-save">Save</button><button data-close>Cancel</button></div>');
    $('#ma-save', m.el).addEventListener('click', async () => {
      try {
        const v = (id) => ($('#' + id, m.el) || {}).value;
        await RB.rpc('rb_save_money_account', { p: { id: a.id, name: v('ma-name'), bank_name: v('ma-bank'), account_last4: v('ma-last4'), upi_id: v('ma-upi'),
          is_active: $('#ma-on', m.el).checked, is_default: $('#ma-def', m.el).checked } });
        RB.toast('Saved'); m.close(); reload();
      } catch (e) { RB.modalMsg(m, e.message); }
    });
  }

  function categoryModal(c, d) {
    const isNew = !c; c = c || { direction: 'out', is_active: true };
    const m = RB.modal('<h2>' + (isNew ? 'Add a category' : esc(c.name)) + '</h2><div class="m-msg"></div>' +
      RB.field('ec-name', 'Name', RB.inp('ec-name', c.name), null, true) +
      '<div class="row">' + RB.field('ec-dir', 'In or out', RB.sel('ec-dir', [['out', 'Expense'], ['in', 'Money received']], c.direction, isNew ? '' : ' disabled')) +
      RB.field('ec-acc', 'Account code', RB.inp('ec-acc', c.account_code, ' inputmode="numeric" placeholder="e.g. 80060140"'), 'A posting account from the chart (Accounts → Chart).', true) +
      RB.field('ec-dept', 'Usual department', RB.sel('ec-dept', [['', '(main department)']].concat(d.departments.filter((x) => x.is_active).map((x) => [x.code, x.code + ' ' + x.name])), c.default_department_code)) + '</div>' +
      RB.field('ec-hint', 'Hint for the person entering', RB.inp('ec-hint', c.hint)) +
      (isNew ? '' : '<label class="check"><input type="checkbox" id="ec-on"' + (c.is_active ? ' checked' : '') + '> Switched on</label>') +
      '<div class="actions"><button class="primary" id="ec-save">Save</button><button data-close>Cancel</button></div>');
    $('#ec-save', m.el).addEventListener('click', async () => {
      try {
        await RB.rpc('rb_save_expense_category', { p: { id: c.id || null, name: $('#ec-name', m.el).value, direction: $('#ec-dir', m.el).value, account_code: $('#ec-acc', m.el).value.trim(),
          default_department_code: $('#ec-dept', m.el).value || null, hint: $('#ec-hint', m.el).value, is_active: $('#ec-on', m.el) ? $('#ec-on', m.el).checked : true } });
        RB.toast('Saved'); m.close(); reload();
      } catch (e) { RB.modalMsg(m, e.message); }
    });
  }

  function methodModal(current) {
    const m = RB.modal('<h2>Change the sharing method</h2><div class="m-msg"></div>' +
      '<p>Labour and overheads are shared between the month\'s batches by one method, kept from month to month so the stock values are comparable. ' +
      'Only a Director can change it, with a reason. The change is kept in the change log. The month-end screen shows all four side by side to help decide.</p>' +
      RB.field('mm-new', 'New method', RB.sel('mm-new', Object.entries(METHOD).filter(([k]) => k !== current)), null, true) +
      RB.field('mm-why', 'Reason', '<textarea id="mm-why" placeholder="e.g. CA advised: batches differ a lot in effort"></textarea>', null, true) +
      '<div class="actions"><button class="primary" id="mm-save">Change</button><button data-close>Cancel</button></div>');
    $('#mm-save', m.el).addEventListener('click', async () => {
      try {
        await RB.rpc('rb_set_absorption_method', { p_method: $('#mm-new', m.el).value, p_reason: $('#mm-why', m.el).value });
        RB.toast('Method changed'); m.close(); reload();
      } catch (e) { RB.modalMsg(m, e.message); }
    });
  }
})();
