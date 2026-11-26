// =====================================================================
// RUCHI BUDS APP · accounts.js · Version 1.0 · 26-Nov-2026
// Module 2 screen "Accounts and journals": manual journals with approval,
// reversal and learning-phase delete, trial balance, account ledger,
// chart of accounts (with import from the Master COA workbook), posting
// rules, and month lock.
// =====================================================================
(function () {
  'use strict';
  const RB = window.RB, $ = RB.$, $$ = RB.$$, esc = RB.esc;
  const STATUS = { draft: 'Draft', posted: 'Posted', reversed: 'Reversed' };
  const STATUS_BADGE = { draft: 'invited', posted: 'active', reversed: 'inactive' };
  const SOURCES = { manual: 'Manual journal', opening: 'Opening balance', reversal: 'Reversal', purchases: 'Purchases', stock: 'Stock',
    production: 'Production', sales: 'Sales', cash_bank: 'Cash and bank', loans: 'Loans and leases', shop: 'Online shop', year_end: 'Year end', system: 'System' };
  const CASH_FLOW = { cash: 'Cash and bank', operating: 'Operating', investing: 'Investing', financing: 'Financing', non_cash: 'Non-cash (add back)', none: 'Not in cash flow' };
  const CLASS_NAMES = { '10': 'Current assets', '20': 'Non-current assets', '30': 'Current liabilities', '40': 'Non-current liabilities',
    '50': 'Equity (partners)', '60': 'Revenue', '70': 'Direct costs', '80': 'Operating expenses', '90': 'Other income', '91': 'Finance costs',
    '92': 'Tax', '93': 'Other profit and loss', '95': 'Consolidation', '96': 'GAAP adjustments', '97': 'Control and suspense' };
  const CONTROL = { customer: 'Customer', supplier: 'Supplier', item: 'Stock item', partner: 'Partner', intercompany: 'Group business' };

  const fyStart = (d) => { const x = new Date(d + 'T00:00:00'); const y = x.getMonth() >= 3 ? x.getFullYear() : x.getFullYear() - 1; return y + '-04-01'; };
  const amt = (p) => (p == null || Number(p) === 0 ? '' : RB.rupees(p));

  let cache = null;
  async function lists(force) {
    if (cache && !force) return cache;
    const [accounts, departments, customers, suppliers, entities, settings] = await Promise.all([
      RB.select('accounts', '*', (q) => q.order('code')),
      RB.select('departments', '*', (q) => q.order('code')),
      RB.select('customers', 'id,code,name,kind,is_active', (q) => q.order('name')).catch(() => []),
      RB.select('suppliers', 'id,code,name,is_active', (q) => q.order('name')).catch(() => []),
      RB.select('entities', '*', (q) => q.order('code')),
      RB.select('app_settings', 'partners,manual_journal_second_person,stock_valuation,entity_code', (q) => q.eq('id', 1).single()),
    ]);
    cache = { accounts, departments, customers, suppliers, entities, settings,
      acc: Object.fromEntries(accounts.map((a) => [a.code, a])),
      partners: (settings.partners || []).filter((p) => p.id != null) };
    return cache;
  }
  const accName = (a) => a ? a.code + ' ' + (a.local_name || a.name) : '';

  RB.screens.accounts = async (body) => {
    cache = null;
    const list = [['journals', 'Journals', journalsTab], ['tb', 'Trial balance', tbTab], ['ledger', 'Account ledger', ledgerTab],
      ['coa', 'Chart of accounts', coaTab], ['rules', 'Posting rules', rulesTab], ['months', 'Month lock', monthsTab]];
    body.innerHTML = '<div class="tabs">' + list.map(([k, t]) => '<button data-tab="' + k + '">' + t + '</button>').join('') + '</div><div id="tab-body"></div>';
    const show = async (k, arg) => {
      $$('.tabs button', body).forEach((b) => b.classList.toggle('on', b.dataset.tab === k));
      const tb = $('#tab-body', body);
      tb.innerHTML = '<p class="muted">Loading…</p>';
      try { await list.find((x) => x[0] === k)[2](tb, arg, show); }
      catch (e) { tb.innerHTML = '<div class="msg error">' + esc(e.message) + '</div>'; }
    };
    $$('.tabs button', body).forEach((b) => b.addEventListener('click', () => show(b.dataset.tab)));
    show('journals');
  };

  // ===================================================================
  // Journals
  // ===================================================================
  async function journalsTab(tb) {
    const L = await lists();
    tb.innerHTML = '<div class="row" style="align-items:flex-end">' +
      RB.field('jl-from', 'From', '<input type="date" id="jl-from">') + RB.field('jl-to', 'To', '<input type="date" id="jl-to">') +
      '<div class="actions" style="margin-bottom:.85rem">' + (RB.has('accounts.add') ? '<button class="primary" id="jl-new">+ New journal</button>' : '') +
      '<button id="jl-xls">Download to Excel</button></div></div>' +
      '<p class="muted">Journals from every module land here. A manual journal is saved as a <b>draft</b>, then posted by someone with approval rights' +
      (L.settings.manual_journal_second_person ? ' other than the person who entered it' : '') + '. Posted journals are never edited: reverse them instead.</p><div id="jl-grid"></div>';
    $('#jl-from', tb).value = fyStart(RB.today()); $('#jl-to', tb).value = RB.today().slice(0, 8) + '31';
    let grid;
    const load = async () => {
      const from = $('#jl-from', tb).value, to = $('#jl-to', tb).value;
      const rows = await RB.select('journals', '*', (q) => {
        q = q.order('journal_date', { ascending: false }).order('id', { ascending: false }).limit(3000);
        if (from) q = q.gte('journal_date', from);
        if (to) q = q.lte('journal_date', to);
        return q;
      });
      const data = rows.map((j) => Object.assign({}, j, { status_t: STATUS[j.status], source_t: SOURCES[j.source] || j.source, total: RB.rupees(j.total_paise) }));
      if (grid) grid.destroy();
      grid = RB.grid($('#jl-grid', tb), [
        { title: 'Number', field: 'journal_no', width: 160, formatter: (c) => c.getValue() ? esc(c.getValue()) : '<span class="muted">(draft)</span>' },
        { title: 'Date', field: 'journal_date', formatter: (c) => RB.fmtDate(c.getValue()), width: 120 },
        { title: 'What for', field: 'narration', minWidth: 260, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
        { title: 'Amount', field: 'total', hozAlign: 'right', width: 130 },
        { title: 'Status', field: 'status_t', width: 120, formatter: (c) => RB.badge(STATUS_BADGE[c.getRow().getData().status], c.getValue()),
          headerFilter: 'list', headerFilterParams: { values: { '': 'All', Draft: 'Draft', Posted: 'Posted', Reversed: 'Reversed' } } },
        { title: 'From', field: 'source_t', width: 150 },
      ], data);
      grid.on('rowClick', (e, row) => journalModal(row.getData().id, load));
    };
    $('#jl-from', tb).addEventListener('change', load); $('#jl-to', tb).addEventListener('change', load);
    $('#jl-xls', tb).addEventListener('click', () => grid && RB.downloadExcel(grid, 'Journals'));
    const n = $('#jl-new', tb); if (n) n.addEventListener('click', () => journalEditor(null, load));
    await load();
  }

  async function journalModal(id, refresh) {
    let j;
    try { j = await RB.rpc('rb_journal_detail', { p_id: id }); } catch (e) { return RB.toast(e.message, true); }
    const dr = j.lines.reduce((a, l) => a + Number(l.debit_paise), 0), cr = j.lines.reduce((a, l) => a + Number(l.credit_paise), 0);
    const mine = j.entered_by === RB.profile.id;
    const m = RB.modal('<h2>' + esc(j.journal_no || 'Draft journal') + ' ' + RB.badge(STATUS_BADGE[j.status], STATUS[j.status]) + RB.demoBadge(j) + '</h2><div class="m-msg"></div>' +
      '<p><b>' + RB.fmtDate(j.journal_date) + '</b> · ' + esc(j.narration) + '</p>' +
      '<p class="muted">' + esc(SOURCES[j.source] || j.source) + ' · entered by ' + esc(j.entered_name || 'system') + ' ' + RB.fmtDateTime(j.entered_at) +
      (j.approved_name ? ' · posted by ' + esc(j.approved_name) + ' ' + RB.fmtDateTime(j.posted_at) : '') +
      (j.reverse_reason && j.status === 'reversed' ? '<br>Reversed: ' + esc(j.reverse_reason) : '') + (j.period_locked ? '<br>' + RB.badge('locked', 'Month locked') : '') + '</p>' +
      '<div class="grid-wrap"><table class="ticks"><thead><tr><th>Account</th><th>Department</th><th>For</th><th>Debit</th><th>Credit</th></tr></thead><tbody>' +
      j.lines.map((l) => '<tr><td style="text-align:left">' + esc(l.account_code + ' ' + l.account_name) + (l.narration ? '<br><span class="muted">' + esc(l.narration) + '</span>' : '') +
        '</td><td>' + esc(l.department || '') + '</td><td>' + esc(l.party || '') + '</td><td style="text-align:right">' + amt(l.debit_paise) + '</td><td style="text-align:right">' + amt(l.credit_paise) + '</td></tr>').join('') +
      '<tr><th style="text-align:left" colspan="3">Total</th><th style="text-align:right">' + RB.rupees(dr) + '</th><th style="text-align:right">' + RB.rupees(cr) + '</th></tr></tbody></table></div>' +
      (j.status === 'draft' && dr !== cr ? '<div class="msg error">Not balanced: difference ' + RB.rupees(Math.abs(dr - cr)) + '.</div>' : '') +
      (j.status === 'draft' && !j.can_post && RB.has('accounts.approve') ? '<p class="muted">' + (mine ? 'You entered this journal, so someone else with approval rights posts it.' : 'You cannot post this journal.') + '</p>' : '') +
      '<div class="actions">' +
      (j.can_post && !j.period_locked ? '<button class="primary" id="jm-post">Post (approve)</button>' : '') +
      (j.status === 'draft' && ['manual', 'opening'].includes(j.source) && RB.has('accounts.edit') && !j.period_locked ? '<button id="jm-edit">Change draft</button>' : '') +
      (j.status === 'draft' && (mine || RB.has('accounts.delete')) ? '<button class="danger" id="jm-deldraft">Delete draft</button>' : '') +
      (j.can_reverse ? '<button id="jm-rev">Reverse…</button>' : '') +
      (j.can_hard_delete && !j.period_locked ? '<button class="danger" id="jm-hard">Fully delete (learning phase)…</button>' : '') +
      '<button id="jm-print">Print</button><button data-close>Close</button></div>', { wide: true });
    // fn may return the message to show (e.g. the new journal number).
    const run = async (fn, ok) => { try { const t = await fn(); RB.toast(typeof t === 'string' ? t : ok); m.close(); refresh(); } catch (e) { RB.modalMsg(m, e.message); } };
    const on = (sel, fn) => { const b = $(sel, m.el); if (b) b.addEventListener('click', fn); };
    on('#jm-post', () => run(async () => 'Posted as ' + (await RB.rpc('rb_post_journal', { p_id: j.id })), 'Posted'));
    on('#jm-edit', () => { m.close(); journalEditor(j, refresh); });
    on('#jm-deldraft', async () => { if (await RB.confirm('Delete this draft?', 'The draft has not been posted, so nothing in the books changes.')) run(() => RB.rpc('rb_delete_draft_journal', { p_id: j.id }), 'Draft deleted'); });
    on('#jm-print', () => {
      const w = window.open('', '_blank');
      if (!w) return;
      w.document.write('<title>' + esc(j.journal_no || 'Draft') + '</title><style>body{font-family:sans-serif;color:#4A2923}table{border-collapse:collapse;width:100%}td,th{border:1px solid #ccc;padding:4px 6px;font-size:13px}</style>' +
        '<h2>Ruchi Buds · Journal ' + esc(j.journal_no || '(draft)') + '</h2><p>' + RB.fmtDate(j.journal_date) + ' · ' + esc(j.narration) + '</p>' + $('table', m.el).outerHTML +
        '<p>Entered by ' + esc(j.entered_name || '') + (j.approved_name ? ' · Posted by ' + esc(j.approved_name) : '') + '</p>');
      w.document.close(); w.print();
    });
    on('#jm-rev', () => {
      const r = RB.modal('<h2>Reverse ' + esc(j.journal_no) + '</h2><div class="m-msg"></div>' +
        '<p class="muted">A mirror journal is posted, so the original stays in the books and both show in the ledger.</p>' +
        RB.field('rv-date', 'Reversal date', '<input type="date" id="rv-date" value="' + (j.period_locked ? RB.today() : j.journal_date) + '">', 'Must be in an open month, on or after ' + RB.fmtDate(j.journal_date) + '.', true) +
        RB.field('rv-why', 'Reason', RB.inp('rv-why', ''), null, true) +
        '<div class="actions"><button class="primary" id="rv-go">Reverse</button><button data-close>Cancel</button></div>');
      $('#rv-go', r.el).addEventListener('click', async () => {
        try { await RB.rpc('rb_reverse_journal', { p_id: j.id, p_date: $('#rv-date', r.el).value, p_reason: $('#rv-why', r.el).value }); r.close(); m.close(); RB.toast('Reversed'); refresh(); }
        catch (e) { RB.modalMsg(r, e.message); }
      });
    });
    on('#jm-hard', async () => {
      const word = await RB.confirmTyped('Fully delete ' + j.journal_no + '?', 'It was entered by ' + esc(j.entered_name) + ', who is still in their learning phase. The journal disappears from the books completely. This cannot be undone.', 'DELETE');
      if (word) run(() => RB.rpc('rb_hard_delete_journal', { p_id: j.id }), 'Journal deleted');
    });
  }

  // The journal form: date, what for, default department, and lines.
  async function journalEditor(j, refresh) {
    const L = await lists();
    const postable = L.accounts.filter((a) => a.level === 'posting' && a.e002_active && a.status === 'Active' && a.statement !== 'CONSOL' && a.control_type !== 'item');
    const depts = L.departments.filter((d) => d.is_active);
    const deptOpts = depts.map((d) => [d.id, d.code + ' ' + d.name]);
    const defDept = (L.departments.find((d) => d.code === 'CC005' && d.is_active) || depts[0] || {}).id;
    let lines = j ? j.lines.map((l) => ({ account_code: l.account_code, department_id: l.department_id, debit: RB.fromPaise(l.debit_paise || null), credit: RB.fromPaise(l.credit_paise || null),
      customer_id: l.customer_id, supplier_id: l.supplier_id, partner_id: l.partner_id, counterparty_entity: l.counterparty_entity, narration: l.narration }))
      : [{}, {}];
    const m = RB.modal('<h2>' + (j ? 'Change draft journal' : 'New journal') + '</h2><div class="m-msg"></div>' +
      '<datalist id="je-accounts">' + postable.map((a) => '<option value="' + esc(accName(a)) + '">').join('') + '</datalist>' +
      '<div class="row">' + RB.field('je-date', 'Date', '<input type="date" id="je-date" value="' + esc(j ? j.journal_date : RB.today()) + '">', null, true) +
      RB.field('je-dept', 'Department (for every line unless changed)', RB.sel('je-dept', deptOpts, j && j.lines[0] ? j.lines[0].department_id : defDept)) +
      RB.field('je-kind', 'Kind', RB.sel('je-kind', [['manual', 'Manual journal'], ['opening', 'Opening balance']], j ? j.source : 'manual')) + '</div>' +
      RB.field('je-narr', 'What is this journal for?', RB.inp('je-narr', j ? j.narration : '', ' placeholder="e.g. Electricity bill for October, paid in cash"'), null, true) +
      '<div id="je-lines"></div><div class="actions"><button id="je-addline">+ Add line</button></div>' +
      '<p id="je-total" style="font-weight:600"></p>' +
      '<p class="muted">Stock accounts are not offered here: stock and its value move only through Purchases, Stock and Sales. Receivable, payable and partner accounts ask for the customer, supplier or partner.</p>' +
      '<div class="actions"><button class="primary" id="je-save">Save draft</button><button data-close>Cancel</button></div>', { wide: true });

    const partyCell = (l, i) => {
      const a = L.acc[l.account_code];
      if (!a || !a.control_type) return '';
      if (a.control_type === 'customer') return RB.sel('jl-party-' + i, [['', 'Choose customer…']].concat(L.customers.filter((c) => c.is_active || c.id === l.customer_id).map((c) => [c.id, c.code + ' ' + c.name])), l.customer_id, ' data-party="customer_id" data-i="' + i + '"');
      if (a.control_type === 'supplier') return RB.sel('jl-party-' + i, [['', 'Choose supplier…']].concat(L.suppliers.filter((c) => c.is_active || c.id === l.supplier_id).map((c) => [c.id, c.code + ' ' + c.name])), l.supplier_id, ' data-party="supplier_id" data-i="' + i + '"');
      if (a.control_type === 'partner') return RB.sel('jl-party-' + i, [['', 'Choose partner…']].concat(L.partners.map((p) => [p.id, p.name])), l.partner_id, ' data-party="partner_id" data-i="' + i + '"');
      if (a.control_type === 'intercompany') return RB.sel('jl-party-' + i, [['', 'Other group business…']].concat(L.entities.filter((e) => !e.is_self).map((e) => [e.code, e.code + ' ' + e.name])), l.counterparty_entity, ' data-party="counterparty_entity" data-i="' + i + '"');
      return '';
    };
    const draw = () => {
      $('#je-lines', m.el).innerHTML = '<div class="grid-wrap"><table class="ticks je"><thead><tr><th>Account</th><th>Debit ₹</th><th>Credit ₹</th><th>Customer / supplier / partner</th><th>Department</th><th>Line note</th><th></th></tr></thead><tbody>' +
        lines.map((l, i) => '<tr>' +
          '<td style="min-width:260px"><input list="je-accounts" data-f="account" data-i="' + i + '" data-drawn="' + (l.account_code || '') + '" value="' + esc(l.account_code ? accName(L.acc[l.account_code]) : '') + '" placeholder="type a code or name"></td>' +
          '<td style="min-width:110px"><input data-f="debit" data-i="' + i + '" inputmode="decimal" value="' + esc(l.debit || '') + '"></td>' +
          '<td style="min-width:110px"><input data-f="credit" data-i="' + i + '" inputmode="decimal" value="' + esc(l.credit || '') + '"></td>' +
          '<td style="min-width:180px">' + partyCell(l, i) + '</td>' +
          '<td style="min-width:170px">' + RB.sel('jl-dept-' + i, [['', '(same as above)']].concat(deptOpts), l.department_id && String(l.department_id) !== $('#je-dept', m.el).value ? l.department_id : '', ' data-f="dept" data-i="' + i + '"') + '</td>' +
          '<td style="min-width:160px"><input data-f="narration" data-i="' + i + '" value="' + esc(l.narration || '') + '"></td>' +
          '<td><button type="button" data-del="' + i + '" aria-label="Remove line">✕</button></td></tr>').join('') + '</tbody></table></div>';
      $$('[data-f]', m.el).forEach((el) => el.addEventListener(el.tagName === 'SELECT' ? 'change' : 'input', () => {
        const l = lines[el.dataset.i];
        if (el.dataset.f === 'account') {
          const code = (el.value.match(/^\s*(\d{8})/) || [])[1];
          l.account_code = code && L.acc[code] ? code : null;
        } else if (el.dataset.f === 'dept') l.department_id = el.value ? Number(el.value) : null;
        else l[el.dataset.f] = el.value;
        total();
      }));
      // Redraw (to show the right party picker) after the field has finished losing focus, never inside the blur itself.
      $$('[data-f=account]', m.el).forEach((el) => el.addEventListener('change', () => {
        const i = el.dataset.i;
        if (el.dataset.drawn === (lines[i].account_code || '')) return;
        setTimeout(() => {
          const act = document.activeElement, f = act && act.dataset ? act.dataset.f : null, fi = act && act.dataset ? act.dataset.i : null;
          draw();
          const back = (f && $('[data-f=' + f + '][data-i="' + fi + '"]', m.el)) || $('[data-f=debit][data-i="' + i + '"]', m.el);
          if (back) back.focus();
        }, 0);
      }));
      $$('[data-party]', m.el).forEach((el) => el.addEventListener('change', () => { const v = el.value; lines[el.dataset.i][el.dataset.party] = v === '' ? null : (el.dataset.party === 'counterparty_entity' ? v : Number(v)); }));
      $$('[data-del]', m.el).forEach((b) => b.addEventListener('click', () => { lines.splice(Number(b.dataset.del), 1); if (lines.length < 2) lines.push({}); draw(); }));
      total();
    };
    const total = () => {
      let dr = 0, cr = 0;
      try { lines.forEach((l) => { dr += RB.toPaise(l.debit) || 0; cr += RB.toPaise(l.credit) || 0; }); } catch (e) { $('#je-total', m.el).textContent = e.message; return; }
      $('#je-total', m.el).innerHTML = 'Debits ' + RB.rupees(dr) + ' · Credits ' + RB.rupees(cr) + ' · ' +
        (dr === cr && dr > 0 ? '<span style="color:var(--leaf)">Balanced</span>' : '<span style="color:var(--error)">Difference ' + RB.rupees(Math.abs(dr - cr)) + '</span>');
    };
    $('#je-addline', m.el).addEventListener('click', () => { lines.push({}); draw(); });
    $('#je-dept', m.el).addEventListener('change', draw);
    draw();
    $('#je-save', m.el).addEventListener('click', async () => {
      try {
        const bad = $$('[data-f=account]', m.el).find((el, i) => el.value.trim() && !lines[i].account_code);
        if (bad) throw new Error('Pick the account from the list: "' + bad.value + '" is not one.');
        const out = lines.map((l) => ({ account_code: l.account_code, debit_paise: RB.toPaise(l.debit), credit_paise: RB.toPaise(l.credit),
          department_id: l.department_id || null, customer_id: l.customer_id || null, supplier_id: l.supplier_id || null,
          partner_id: l.partner_id || null, counterparty_entity: l.counterparty_entity || null, narration: l.narration || null }));
        const id = await RB.rpc('rb_save_journal', { p: { id: j ? j.id : null, journal_date: $('#je-date', m.el).value, narration: $('#je-narr', m.el).value,
          source: $('#je-kind', m.el).value, department_id: Number($('#je-dept', m.el).value), lines: out } });
        m.close(); RB.toast('Draft saved'); refresh(); journalModal(id, refresh);
      } catch (e) { RB.modalMsg(m, e.message); m.el.scrollTop = 0; }
    });
  }

  // ===================================================================
  // Trial balance
  // ===================================================================
  async function tbTab(tb, arg, show) {
    const L = await lists();
    tb.innerHTML = '<div class="row" style="align-items:flex-end">' +
      RB.field('tb-from', 'From', '<input type="date" id="tb-from">') + RB.field('tb-to', 'To', '<input type="date" id="tb-to">') +
      RB.field('tb-dept', 'Department', RB.sel('tb-dept', [['', 'All departments']].concat(L.departments.filter((d) => !d.merged_into).map((d) => [d.id, d.code + ' ' + d.name])), '')) +
      '<div class="field"><label>&nbsp;</label><label class="check"><input type="checkbox" id="tb-demo" checked> Include DEMO entries</label></div>' +
      '<div class="actions" style="margin-bottom:.85rem"><button class="primary" id="tb-go">Show</button><button id="tb-xls">Download to Excel</button></div></div>' +
      '<div id="tb-sum"></div><div id="tb-grid"></div>' +
      '<p class="muted">Balances from posted journals. Profit and loss accounts start each financial year (April) at zero; earlier years\' profit shows in Retained Earnings until the year-end close in module 8. Tap an account for its ledger.</p>';
    $('#tb-from', tb).value = fyStart(RB.today()); $('#tb-to', tb).value = RB.today();
    let grid;
    const load = async () => {
      const rows = await RB.rpc('rb_trial_balance', { p_from: $('#tb-from', tb).value, p_to: $('#tb-to', tb).value,
        p_dept: $('#tb-dept', tb).value ? Number($('#tb-dept', tb).value) : null, p_include_demo: $('#tb-demo', tb).checked });
      let tdr = 0, tcr = 0, odr = 0, ocr = 0;
      const data = (rows || []).map((r) => {
        const c = Number(r.closing_paise), o = Number(r.opening_paise);
        if (c > 0) tdr += c; else tcr -= c;
        if (o > 0) odr += o; else ocr -= o;
        return Object.assign({}, r, { group: (r.class_code + ' ' + (CLASS_NAMES[r.class_code] || '')),
          open_dr: o > 0 ? o : null, open_cr: o < 0 ? -o : null, close_dr: c > 0 ? c : null, close_cr: c < 0 ? -c : null });
      });
      $('#tb-sum', tb).innerHTML = '<div class="msg ' + (tdr === tcr ? 'ok' : 'error') + '">' +
        (tdr === tcr ? '✓ Balanced: ' : 'NOT balanced: ') + 'debit balances ' + RB.rupees(tdr) + ', credit balances ' + RB.rupees(tcr) + '</div>';
      if (grid) grid.destroy();
      const money = (f) => ({ field: f, hozAlign: 'right', headerFilter: false, formatter: (c) => amt(c.getValue()), bottomCalc: 'sum', bottomCalcFormatter: (c) => RB.rupees(c.getValue() || 0) });
      grid = RB.grid($('#tb-grid', tb), [
        { title: 'Code', field: 'account_code', width: 100 },
        { title: 'Account', field: 'account_name', minWidth: 230 },
        Object.assign({ title: 'Opening Dr' }, money('open_dr')), Object.assign({ title: 'Opening Cr' }, money('open_cr')),
        Object.assign({ title: 'Debits' }, money('debit_paise')), Object.assign({ title: 'Credits' }, money('credit_paise')),
        Object.assign({ title: 'Closing Dr' }, money('close_dr')), Object.assign({ title: 'Closing Cr' }, money('close_cr')),
      ], data, { groupBy: 'group', pagination: false, columnCalcs: 'both' });
      grid.on('rowClick', (e, row) => show('ledger', { account: row.getData().account_code, from: $('#tb-from', tb).value, to: $('#tb-to', tb).value }));
    };
    $('#tb-go', tb).addEventListener('click', () => load().catch((e) => RB.toast(e.message, true)));
    $('#tb-xls', tb).addEventListener('click', () => grid && RB.downloadExcel(grid, 'Trial balance'));
    await load();
  }

  // ===================================================================
  // Account ledger
  // ===================================================================
  async function ledgerTab(tb, arg) {
    const L = await lists();
    const accs = L.accounts.filter((a) => a.level === 'posting' && (a.e002_active || a.source === 'local'));
    tb.innerHTML = '<datalist id="lg-accounts">' + accs.map((a) => '<option value="' + esc(accName(a)) + '">').join('') + '</datalist>' +
      '<div class="row" style="align-items:flex-end">' + RB.field('lg-acc', 'Account', '<input id="lg-acc" list="lg-accounts" placeholder="type a code or name">') +
      RB.field('lg-from', 'From', '<input type="date" id="lg-from">') + RB.field('lg-to', 'To', '<input type="date" id="lg-to">') + '</div>' +
      '<div class="row" style="align-items:flex-end" id="lg-party"></div>' +
      '<div class="actions" style="margin:0 0 .75rem"><button class="primary" id="lg-go">Show</button><button id="lg-xls">Download to Excel</button></div><div id="lg-grid"></div>';
    $('#lg-from', tb).value = (arg && arg.from) || fyStart(RB.today()); $('#lg-to', tb).value = (arg && arg.to) || RB.today();
    if (arg && arg.account) $('#lg-acc', tb).value = accName(L.acc[arg.account]);
    const code = () => ($('#lg-acc', tb).value.match(/^\s*(\d{8})/) || [])[1];
    const drawParty = () => {
      const a = L.acc[code()];
      const t = a && a.control_type;
      $('#lg-party', tb).innerHTML =
        (t === 'customer' ? RB.field('lg-p', 'Customer', RB.sel('lg-p', [['', 'All customers']].concat(L.customers.map((c) => [c.id, c.code + ' ' + c.name])), '')) : '') +
        (t === 'supplier' ? RB.field('lg-p', 'Supplier', RB.sel('lg-p', [['', 'All suppliers']].concat(L.suppliers.map((c) => [c.id, c.code + ' ' + c.name])), '')) : '') +
        (t === 'partner' ? RB.field('lg-p', 'Partner', RB.sel('lg-p', [['', 'All partners']].concat(L.partners.map((p) => [p.id, p.name])), '')) : '') +
        RB.field('lg-dept', 'Department', RB.sel('lg-dept', [['', 'All departments']].concat(L.departments.filter((d) => !d.merged_into).map((d) => [d.id, d.code + ' ' + d.name])), ''));
    };
    $('#lg-acc', tb).addEventListener('change', drawParty); drawParty();
    let grid;
    const load = async () => {
      const c = code();
      if (!c || !L.acc[c]) { $('#lg-grid', tb).innerHTML = '<p class="muted">Choose an account.</p>'; return; }
      const a = L.acc[c], p = $('#lg-p', tb) ? ($('#lg-p', tb).value || null) : null;
      const rows = await RB.rpc('rb_account_ledger', { p_account: c, p_from: $('#lg-from', tb).value, p_to: $('#lg-to', tb).value,
        p_customer: a.control_type === 'customer' && p ? Number(p) : null, p_supplier: a.control_type === 'supplier' && p ? Number(p) : null,
        p_partner: a.control_type === 'partner' && p ? Number(p) : null, p_dept: $('#lg-dept', tb).value ? Number($('#lg-dept', tb).value) : null });
      const bal = (v) => v == null ? '' : RB.rupees(Math.abs(v)) + (Number(v) > 0 ? ' Dr' : Number(v) < 0 ? ' Cr' : '');
      if (grid) grid.destroy();
      grid = RB.grid($('#lg-grid', tb), [
        { title: 'Date', field: 'journal_date', formatter: (x) => RB.fmtDate(x.getValue()), width: 120, headerFilter: false },
        { title: 'Number', field: 'journal_no', width: 160 },
        { title: 'What for', field: 'narration', minWidth: 240, formatter: (x) => esc(x.getValue()) + RB.demoBadge(x.getRow().getData()) },
        { title: 'For', field: 'party' },
        { title: 'Department', field: 'department' },
        { title: 'Debit', field: 'debit_paise', hozAlign: 'right', formatter: (x) => amt(x.getValue()), headerFilter: false },
        { title: 'Credit', field: 'credit_paise', hozAlign: 'right', formatter: (x) => amt(x.getValue()), headerFilter: false },
        { title: 'Balance', field: 'balance_paise', hozAlign: 'right', formatter: (x) => bal(x.getValue()), headerFilter: false },
      ], rows || [], { pagination: (rows || []).length > 200, paginationSize: 200 });
      grid.on('rowClick', (e, row) => { const id = row.getData().journal_id; if (id) journalModal(id, load); });
    };
    $('#lg-go', tb).addEventListener('click', () => load().catch((e) => RB.toast(e.message, true)));
    $('#lg-xls', tb).addEventListener('click', () => grid && RB.downloadExcel(grid, 'Ledger ' + (code() || '')));
    if (arg && arg.account) await load();
  }

  // ===================================================================
  // Chart of accounts
  // ===================================================================
  async function coaTab(tb) {
    const L = await lists(true);
    const edit = RB.has('accounts.edit');
    tb.innerHTML = '<div class="actions" style="margin:0 0 .75rem">' +
      '<label class="check" style="margin-right:1rem"><input type="checkbox" id="co-hidden"> Show accounts hidden for Ruchi Buds</label>' +
      (edit ? '<button id="co-add">+ Add a Ruchi Buds account</button><label class="btn" for="co-file" style="margin:0">Import Master COA workbook…</label><input id="co-file" type="file" accept=".xlsx,.xls,.csv" class="hidden">' : '') +
      '<button id="co-xls">Download to Excel</button></div><div id="co-msg"></div>' +
      '<p class="muted">The group\'s Master chart of accounts (8 digits: class, group, family, detail). Family codes ending 00 are headers and cannot be posted to. ' +
      'Accounts that exist only under IFRS (right-of-use assets, expected credit loss, contract assets, OCI reserves, share capital) and consolidation-only accounts are hidden, because Ruchi Buds reports under Indian AS. ' +
      'Each account has a cash-flow category, used for the AS 3 cash flow statement. Tap an account to change it.</p><div id="co-grid"></div>';
    const rows = L.accounts.filter((a) => a.level === 'posting').map((a) => Object.assign({}, a, {
      shown: a.e002_active ? 'Yes' : 'Hidden', cf: CASH_FLOW[a.cash_flow], ctl: CONTROL[a.control_type] || '', group: a.code.slice(0, 2) + ' ' + (CLASS_NAMES[a.code.slice(0, 2)] || ''),
      display: (a.local_name || a.name) + (a.local_name ? ' (' + a.name + ')' : ''), src: a.source === 'local' ? 'Ruchi Buds' : 'Group' }));
    const grid = RB.grid($('#co-grid', tb), [
      { title: 'Code', field: 'code', width: 100 },
      { title: 'Account', field: 'display', minWidth: 260 },
      { title: 'Class', field: 'class' },
      { title: 'Statement', field: 'statement', width: 90 },
      { title: 'Normal', field: 'normal_balance', width: 90 },
      { title: 'Subledger', field: 'subledger' },
      { title: 'Needs', field: 'ctl' },
      { title: 'Cash flow', field: 'cf' },
      { title: 'Ruchi Buds', field: 'shown', width: 100, formatter: (c) => c.getValue() === 'Yes' ? RB.badge('active', 'Shown') : RB.badge('inactive', 'Hidden') },
      { title: 'From', field: 'src', width: 100 },
    ], rows, { groupBy: 'group', paginationSize: 100 });
    const applyHidden = () => { if ($('#co-hidden', tb).checked) grid.removeFilter('shown', '=', 'Yes'); else grid.addFilter('shown', '=', 'Yes'); };
    grid.on('tableBuilt', applyHidden);
    $('#co-hidden', tb).addEventListener('change', applyHidden);
    grid.on('rowClick', (e, row) => accountModal(L.acc[row.getData().code], () => coaTab(tb)));
    $('#co-xls', tb).addEventListener('click', () => RB.downloadExcel(grid, 'Chart of accounts'));
    if (!edit) return;
    $('#co-add', tb).addEventListener('click', () => {
      const m = RB.modal('<h2>Add a Ruchi Buds account</h2><div class="m-msg"></div>' +
        '<p class="muted">Inside an existing family only (for example 80060155 in family 80060100). New families and groups are added by the group. Detail codes go up in steps of 05.</p>' +
        '<div class="row">' + RB.field('na-code', 'Code', RB.inp('na-code', '', ' inputmode="numeric" maxlength="8"'), null, true) + RB.field('na-name', 'Name', RB.inp('na-name', ''), null, true) + '</div>' +
        RB.field('na-cf', 'Cash-flow category', RB.sel('na-cf', [['', 'Same as the family']].concat(Object.entries(CASH_FLOW)), '')) +
        '<div class="actions"><button class="primary" id="na-go">Add</button><button data-close>Cancel</button></div>');
      $('#na-go', m.el).addEventListener('click', async () => {
        try { await RB.rpc('rb_add_local_account', { p: { code: $('#na-code', m.el).value.trim(), name: $('#na-name', m.el).value, cash_flow: $('#na-cf', m.el).value || null } }); RB.toast('Account added'); m.close(); coaTab(tb); }
        catch (e) { RB.modalMsg(m, e.message); }
      });
    });
    $('#co-file', tb).addEventListener('change', async (e) => {
      const f = e.target.files[0]; if (!f) return;
      const msg = $('#co-msg', tb);
      try {
        const wb = XLSX.read(await f.arrayBuffer(), { type: 'array' });
        const rows = [];
        wb.SheetNames.forEach((sn) => {
          const aoa = XLSX.utils.sheet_to_json(wb.Sheets[sn], { header: 1, defval: '' });
          const h = aoa.findIndex((r) => r.some((c) => /^account code$/i.test(String(c).trim())));
          if (h < 0) return;
          const head = aoa[h].map((c) => String(c).trim().toLowerCase());
          const col = (n) => head.indexOf(n);
          const ci = { code: col('account code'), name: col('account name'), class: col('class'), statement: col('statement'), normal: col('normal balance'),
            status: col('status'), subledger: col('subledger'), standard: col('standard') };
          aoa.slice(h + 1).forEach((r) => {
            const code = String(r[ci.code] || '').trim();
            if (!/^\d{8}$/.test(code)) return;
            rows.push({ code, name: String(r[ci.name] || '').trim(), class: ci.class >= 0 ? String(r[ci.class]).trim() : '', statement: ci.statement >= 0 ? String(r[ci.statement]).trim() : '',
              normal_balance: ci.normal >= 0 ? String(r[ci.normal]).trim() : '', status: ci.status >= 0 ? String(r[ci.status]).trim() : '',
              subledger: ci.subledger >= 0 ? String(r[ci.subledger]).trim() : '', standard: ci.standard >= 0 ? String(r[ci.standard]).trim() : '' });
          });
        });
        if (!rows.length) throw new Error('No sheet with an "Account Code" column was found in that file.');
        if (!(await RB.confirm('Import ' + rows.length + ' accounts?', 'New accounts are added (hidden until you switch them on) and names are refreshed. Nothing is deleted or renumbered.'))) return;
        const res = await RB.rpc('rb_import_accounts', { p_rows: rows });
        RB.toast('Imported: ' + res.added + ' added, ' + res.updated + ' updated');
        await coaTab(tb);
        $('#co-msg', tb).innerHTML = '<div class="msg ok">' + res.added + ' accounts added, ' + res.updated + ' updated, ' + res.skipped + ' rows skipped.</div>';
      } catch (err) { msg.innerHTML = '<div class="msg error">' + esc(err.message) + '</div>'; }
      e.target.value = '';
    });
  }

  function accountModal(a, done) {
    const edit = RB.has('accounts.edit'), dis = edit ? '' : ' disabled';
    const m = RB.modal('<h2>' + esc(a.code + ' ' + a.name) + '</h2><div class="m-msg"></div>' +
      '<p class="muted">' + esc(a.class) + ' · ' + esc(a.statement) + ' · normal balance ' + esc(a.normal_balance) + (a.subledger ? ' · subledger ' + esc(a.subledger) : '') +
      (a.standard ? ' · group reference ' + esc(a.standard) : '') + (a.control_type ? '<br>Every line needs: <b>' + esc(CONTROL[a.control_type]) + '</b>' : '') + '</p>' +
      (a.source === 'local' ? RB.field('ac-name', 'Name', RB.inp('ac-name', a.name, dis)) : '') +
      RB.field('ac-local', 'Ruchi Buds name (optional)', RB.inp('ac-local', a.local_name, dis), 'Shown instead of the group name on Ruchi Buds screens and reports. The group code and name stay for consolidation.') +
      RB.field('ac-cf', 'Cash-flow category (AS 3)', RB.sel('ac-cf', Object.entries(CASH_FLOW), a.cash_flow, dis)) +
      '<label class="check"><input type="checkbox" id="ac-on"' + (a.e002_active ? ' checked' : '') + dis + '> Used by Ruchi Buds (shown on entry screens)</label>' +
      '<div class="actions">' + (edit ? '<button class="primary" id="ac-save">Save</button>' : '') + '<button data-close>Close</button></div>');
    const b = $('#ac-save', m.el);
    if (b) b.addEventListener('click', async () => {
      try {
        await RB.rpc('rb_save_account', { p: { code: a.code, local_name: $('#ac-local', m.el).value, cash_flow: $('#ac-cf', m.el).value,
          e002_active: $('#ac-on', m.el).checked, name: $('#ac-name', m.el) ? $('#ac-name', m.el).value : null } });
        RB.toast('Saved'); m.close(); done();
      } catch (e) { RB.modalMsg(m, e.message); }
    });
  }

  // ===================================================================
  // Posting rules
  // ===================================================================
  async function rulesTab(tb) {
    const L = await lists();
    const rules = await RB.select('posting_rules', '*', (q) => q.order('sort'));
    const edit = RB.has('accounts.edit');
    const postable = L.accounts.filter((a) => a.level === 'posting' && a.e002_active);
    tb.innerHTML = '<p class="muted">Nobody picks an account code on the Purchases, Stock or Sales screens: each entry posts to the accounts below. ' +
      'These follow the build plan\'s posting map and are for the Accountant and CA to confirm. ' + (edit ? 'Tap a line to point it at another account; the change applies to new entries only.' : '') + '</p>' +
      '<datalist id="pr-accounts">' + postable.map((a) => '<option value="' + esc(accName(a)) + '">').join('') + '</datalist><div id="pr-grid"></div>';
    const data = rules.map((r) => Object.assign({}, r, { account: accName(L.acc[r.account_code]), side_t: r.side === 'debit' ? 'Debit' : 'Credit',
      group: 'Module ' + r.module + ' · ' + r.event_code.replace(/_/g, ' ') }));
    const grid = RB.grid($('#pr-grid', tb), [
      { title: 'Entry', field: 'label', minWidth: 260 },
      { title: 'Side', field: 'side_t', width: 90 },
      { title: 'Posts to', field: 'account', minWidth: 260 },
      { title: 'Key', field: 'line_key', width: 140 },
    ], data, { groupBy: 'group', pagination: false });
    if (!edit) return;
    grid.on('rowClick', (e, row) => {
      const r = row.getData();
      const m = RB.modal('<h2>' + esc(r.label) + '</h2><div class="m-msg"></div><p class="muted">' + esc(r.side_t) + ' side of “' + esc(r.event_code) + '” entries.</p>' +
        RB.field('pr-acc', 'Posts to', '<input id="pr-acc" list="pr-accounts" value="' + esc(r.account) + '">') +
        '<div class="actions"><button class="primary" id="pr-go">Save</button><button data-close>Cancel</button></div>');
      $('#pr-go', m.el).addEventListener('click', async () => {
        const code = ($('#pr-acc', m.el).value.match(/^\s*(\d{8})/) || [])[1];
        try { if (!code) throw new Error('Pick the account from the list.'); await RB.rpc('rb_set_posting_rule', { p_event: r.event_code, p_key: r.line_key, p_account: code }); RB.toast('Rule changed'); m.close(); rulesTab(tb); }
        catch (err) { RB.modalMsg(m, err.message); }
      });
    });
  }

  // ===================================================================
  // Month lock and ledger settings
  // ===================================================================
  async function monthsTab(tb) {
    const L = await lists(true);
    const periods = await RB.select('periods', '*');
    const byMonth = Object.fromEntries(periods.map((p) => [p.month, p]));
    const can = RB.has('power.lock_periods');
    const start = new Date(fyStart(RB.today()) + 'T00:00:00'); start.setFullYear(start.getFullYear() - 1);
    const months = [];
    for (let d = new Date(start); months.length < 26; d.setMonth(d.getMonth() + 1)) {
      months.push(d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-01');
    }
    const thisMonth = RB.today().slice(0, 8) + '01';
    tb.innerHTML = '<section class="card"><h2>Month lock</h2><p class="muted">Lock a month once it is closed, so its figures (and the monthly consolidation file) cannot change. ' +
      'Nothing can be posted, changed, reversed or deleted in a locked month; mistakes are corrected in an open month. ' + (can ? '' : 'Only a Director or the FC can lock or unlock.') + '</p>' +
      '<div class="grid-wrap"><table class="ticks" style="min-width:0"><thead><tr><th>Month</th><th>Status</th><th>Last change</th><th></th></tr></thead><tbody>' +
      months.filter((mo) => mo <= thisMonth || byMonth[mo]).reverse().map((mo) => {
        const p = byMonth[mo] || {}, label = new Date(mo + 'T00:00:00').toLocaleString('en-GB', { month: 'short', year: 'numeric' }).replace(' ', '-');
        return '<tr><th style="text-align:left">' + label + '</th><td>' + (p.is_locked ? RB.badge('locked', 'Locked') : RB.badge('active', 'Open')) + '</td><td style="text-align:left">' +
          (p.updated_at ? RB.fmtDateTime(p.updated_at) + (p.note ? ' · ' + esc(p.note) : '') : '') + '</td><td>' +
          (can ? (p.is_locked ? '<button data-unlock="' + mo + '">Unlock…</button>' : '<button data-lock="' + mo + '">Lock</button>') : '') + '</td></tr>';
      }).join('') + '</tbody></table></div></section>' +
      '<section class="card"><h2>Ledger settings</h2>' +
      '<label class="check"><input type="checkbox" id="ls-second"' + (L.settings.manual_journal_second_person ? ' checked' : '') + (RB.has('settings.edit') ? '' : ' disabled') + '> Manual journals must be posted by someone other than the person who entered them</label>' +
      '<div class="hint">Spec section 9A. Directors, the FC and the Accountant can approve their own entries on other screens.</div>' +
      RB.field('ls-val', 'Stock valuation method', RB.sel('ls-val', [['Weighted average', 'Weighted average cost'], ['FIFO', 'First in, first out (FIFO)']], L.settings.stock_valuation, RB.has('settings.edit') ? '' : ' disabled'), 'Used from module 3. Confirm with your CA (AS 2). Change it only before the first purchase is posted.') +
      (RB.has('settings.edit') ? '<button class="primary" id="ls-save">Save ledger settings</button>' : '') + '</section>';
    $$('[data-lock]', tb).forEach((b) => b.addEventListener('click', async () => {
      if (!(await RB.confirm('Lock ' + b.closest('tr').firstChild.textContent + '?', 'Nothing can be posted or changed in this month until a Director or the FC unlocks it.'))) return;
      try { await RB.rpc('rb_lock_period', { p_month: b.dataset.lock, p_lock: true, p_note: null }); RB.toast('Month locked'); monthsTab(tb); } catch (e) { RB.toast(e.message, true); }
    }));
    $$('[data-unlock]', tb).forEach((b) => b.addEventListener('click', () => {
      const m = RB.modal('<h2>Unlock ' + esc(b.closest('tr').firstChild.textContent) + '</h2><div class="m-msg"></div>' +
        RB.field('ul-why', 'Reason', RB.inp('ul-why', ''), 'Kept in the audit log.', true) +
        '<div class="actions"><button class="danger" id="ul-go">Unlock</button><button data-close>Cancel</button></div>');
      $('#ul-go', m.el).addEventListener('click', async () => {
        try { await RB.rpc('rb_lock_period', { p_month: b.dataset.unlock, p_lock: false, p_note: $('#ul-why', m.el).value }); m.close(); RB.toast('Month unlocked'); monthsTab(tb); }
        catch (e) { RB.modalMsg(m, e.message); }
      });
    }));
    const s = $('#ls-save', tb);
    if (s) s.addEventListener('click', async () => {
      try { await RB.rpc('rb_save_ledger_settings', { p: { manual_journal_second_person: $('#ls-second', tb).checked, stock_valuation: $('#ls-val', tb).value } }); cache = null; RB.toast('Ledger settings saved'); }
      catch (e) { RB.toast(e.message, true); }
    });
  }
})();
