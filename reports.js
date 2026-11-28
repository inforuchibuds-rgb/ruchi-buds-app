// =====================================================================
// RUCHI BUDS APP · reports.js · Version 1.0 · 27-Nov-2026
// Module 8 screen "Reports" (Director, FC and Accountant): the live
// dashboard with charts, sales, purchases, stock, customer and loan
// reports, the financial statements under Indian AS (balance sheet,
// statement of profit and loss, AS 3 cash flow statement, notes), the
// statement lines, the year-end close and the Looker Studio report fed
// by the weekly Google Sheets copy.
// =====================================================================
(function () {
  'use strict';
  const RB = window.RB, $ = RB.$, $$ = RB.$$, esc = RB.esc;
  const R = (RB.reports = { demo: true });

  const on = (root, sel, fn, ev) => { const b = $(sel, root); if (b) b.addEventListener(ev || 'click', fn); };
  const amt = (p) => (p == null || Number(p) === 0 ? '' : RB.rupees(p));
  const fact = (label, value, sub) => '<div><small>' + esc(label) + '</small><b>' + value + '</b>' + (sub ? '<small>' + sub + '</small>' : '') + '</div>';
  const today = () => RB.today();
  const fyStart = (d) => { const y = Number(d.slice(0, 4)), m = Number(d.slice(5, 7)); return (m >= 4 ? y : y - 1) + '-04-01'; };
  const addDays = (d, n) => { const x = new Date(d + 'T00:00:00Z'); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };
  const monthStart = (d) => d.slice(0, 8) + '01';
  const monthEnd = (d) => { const x = new Date(Date.UTC(Number(d.slice(0, 4)), Number(d.slice(5, 7)), 0)); return x.toISOString().slice(0, 10); };
  const prevMonth = (d) => addDays(monthStart(d), -1);
  const marginOk = () => RB.has('reports.margin') || RB.has('accounts.view');
  const money = (f, title, extra) => Object.assign({ title, field: f, hozAlign: 'right', headerFilter: false, formatter: (c) => amt(c.getValue()),
    bottomCalc: 'sum', bottomCalcFormatter: (c) => RB.rupees(c.getValue() || 0) }, extra || {});
  const KIND = { retail: 'Retail', trader: 'Trader', online: 'Online', staff: 'Staff', other: 'Other' };

  function tabs(body, list) {
    body.innerHTML = '<div class="tabs">' + list.map(([k, t]) => '<button data-tab="' + k + '">' + t + '</button>').join('') + '</div><div id="tab-body"></div>';
    const show = async (k) => {
      R.tab = k;
      $$('.tabs button', body).forEach((b) => b.classList.toggle('on', b.dataset.tab === k));
      // A fresh box for each showing, so a slower earlier load cannot draw over the tab now chosen.
      const tb = document.createElement('div'); tb.innerHTML = '<p class="muted">Loading…</p>';
      $('#tab-body', body).replaceChildren(tb);
      try { await list.find((x) => x[0] === k)[2](tb); } catch (e) { tb.innerHTML = '<div class="msg error">' + esc(e.message) + '</div>'; }
    };
    $$('.tabs button', body).forEach((b) => b.addEventListener('click', () => show(b.dataset.tab)));
    R.reload = () => show(R.tab);
    show(R.tab && list.some((x) => x[0] === R.tab) ? R.tab : list[0][0]);
  }

  // A "From / To" bar with quick choices and the DEMO tick.
  function periodBar(tb, key, opts) {
    const o = Object.assign({ from: true, presets: true }, opts || {});
    const p = R[key] || (R[key] = o.from ? { from: o.defFrom || monthStart(today()), to: today() } : { to: today() });
    tb.insertAdjacentHTML('afterbegin', '<div class="row no-print" style="align-items:flex-end">' +
      (o.from ? RB.field('pb-from', 'From', '<input type="date" id="pb-from" value="' + p.from + '">') : '') +
      RB.field('pb-to', o.from ? 'To' : 'As at', '<input type="date" id="pb-to" value="' + p.to + '">') +
      (o.from && o.presets ? RB.field('pb-pre', 'Quick choice', RB.sel('pb-pre', [['', '(choose)'], ['month', 'This month'], ['last', 'Last month'],
        ['fy', 'This year to date'], ['lastfy', 'Last financial year']], '')) : '') +
      '<div class="field" style="flex:0 1 auto"><label class="check"><input type="checkbox" id="pb-demo"' + (R.demo ? ' checked' : '') + '> Include DEMO entries</label>' +
      '<button class="primary" id="pb-go">Show</button>' + (o.extra || '') + '</div></div>');
    const read = () => { if (o.from) p.from = $('#pb-from', tb).value; p.to = $('#pb-to', tb).value; R.demo = $('#pb-demo', tb).checked; return p; };
    on(tb, '#pb-pre', () => {
      const v = $('#pb-pre', tb).value, t = today();
      const set = (f, to) => { $('#pb-from', tb).value = f; $('#pb-to', tb).value = to; };
      if (v === 'month') set(monthStart(t), t);
      if (v === 'last') set(monthStart(prevMonth(t)), prevMonth(t));
      if (v === 'fy') set(fyStart(t), t);
      if (v === 'lastfy') { const s = fyStart(t); set((Number(s.slice(0, 4)) - 1) + '-04-01', addDays(s, -1)); }
    }, 'change');
    return read;
  }

  // ===================================================================
  // Charts (plain SVG, brand colours, hover shows the figure)
  // ===================================================================
  const C1 = '#971B1E', C2 = '#E0A21A';
  const short = (p) => { const r = Number(p) / 100; const a = Math.abs(r);
    return (r < 0 ? '−' : '') + '₹' + (a >= 1e7 ? (a / 1e7).toFixed(1) + ' cr' : a >= 1e5 ? (a / 1e5).toFixed(1) + ' L' : a >= 1e3 ? (a / 1e3).toFixed(1) + 'k' : a.toFixed(0)); };
  function tip(el) {
    let t = $('.chart-tip', el);
    if (!t) { t = document.createElement('div'); t.className = 'chart-tip'; el.appendChild(t); }
    return t;
  }
  function hover(el, svg) {
    const t = tip(el);
    svg.addEventListener('mousemove', (e) => {
      const g = e.target.closest('[data-tip]');
      if (!g) { t.style.display = 'none'; return; }
      t.innerHTML = g.dataset.tip; t.style.display = 'block';
      const r = el.getBoundingClientRect();
      t.style.left = Math.min(e.clientX - r.left + 12, r.width - 170) + 'px'; t.style.top = (e.clientY - r.top - 10) + 'px';
    });
    svg.addEventListener('mouseleave', () => { t.style.display = 'none'; });
  }
  // Vertical bars: rows [{label, values: [..]}], series [{name, color}].
  function barChart(el, rows, series, opts) {
    const o = Object.assign({ h: 220, every: 1 }, opts || {});
    const W = Math.max(el.clientWidth || 600, 280), H = o.h, L = 52, B = 26, T = 10;
    const vals = rows.flatMap((r) => r.values.map(Number));
    const max = Math.max(0, ...vals), min = Math.min(0, ...vals);
    const span = (max - min) || 1, y = (v) => T + (max - v) / span * (H - T - B);
    const n = rows.length, slot = (W - L - 6) / Math.max(n, 1), k = series.length;
    const bw = Math.max(Math.min((slot - 4) / k - 2, 28), 3);
    const ticks = [0, 1, 2, 3].map((i) => min + span * i / 3);
    let s = '<svg width="' + W + '" height="' + H + '" role="img" aria-label="' + esc(o.label || 'chart') + '">';
    ticks.forEach((v) => { s += '<line x1="' + L + '" x2="' + (W - 4) + '" y1="' + y(v) + '" y2="' + y(v) + '" class="grid"/><text x="' + (L - 6) + '" y="' + (y(v) + 4) + '" class="ax" text-anchor="end">' + short(v) + '</text>'; });
    rows.forEach((r, i) => {
      const x0 = L + 3 + i * slot + (slot - k * (bw + 2)) / 2;
      const tipText = '<b>' + esc(r.label) + '</b>' + series.map((se, j) => '<br>' + esc(se.name) + ': ' + RB.rupees(r.values[j])).join('');
      s += '<g data-tip="' + esc(tipText) + '"><rect x="' + (L + i * slot) + '" y="' + T + '" width="' + slot + '" height="' + (H - T - B) + '" fill="transparent"/>';
      r.values.forEach((v, j) => {
        const top = y(Math.max(v, 0)), bot = y(Math.min(v, 0)), hgt = Math.max(bot - top, Number(v) ? 1 : 0);
        s += '<rect x="' + (x0 + j * (bw + 2)) + '" y="' + top + '" width="' + bw + '" height="' + hgt + '" rx="' + Math.min(4, bw / 2) + '" fill="' + series[j].color + '"/>';
      });
      s += '</g>';
      if (i % o.every === 0) s += '<text x="' + (L + i * slot + slot / 2) + '" y="' + (H - 8) + '" class="ax" text-anchor="middle">' + esc(r.short || r.label) + '</text>';
    });
    s += '<line x1="' + L + '" x2="' + (W - 4) + '" y1="' + y(0) + '" y2="' + y(0) + '" class="base"/></svg>';
    el.innerHTML = (series.length > 1 ? '<div class="legend">' + series.map((se) => '<span><i style="background:' + se.color + '"></i>' + esc(se.name) + '</span>').join('') + '</div>' : '') + s;
    hover(el, $('svg', el));
  }
  // Horizontal bars with the figure written at the end: rows [{label, value, note}].
  function hbarChart(el, rows) {
    if (!rows.length) { el.innerHTML = '<p class="muted">No sales yet this month.</p>'; return; }
    const max = Math.max(...rows.map((r) => Math.abs(Number(r.value))), 1);
    el.innerHTML = '<div class="hbars">' + rows.map((r) => '<div class="hb" data-tip="' + esc('<b>' + esc(r.label) + '</b><br>' + RB.rupees(r.value) + (r.note ? '<br>' + esc(r.note) : '')) + '">' +
      '<span class="hb-l">' + esc(r.label) + '</span><span class="hb-bar"><i style="width:' + (Math.abs(Number(r.value)) / max * 100).toFixed(1) + '%"></i></span>' +
      '<span class="hb-v">' + short(r.value) + '</span></div>').join('') + '</div>';
    hover(el, $('.hbars', el));
  }

  // ===================================================================
  // The screen
  // ===================================================================
  RB.screens.reports = async (body) => {
    const list = [['dash', 'Dashboard', dashTab], ['sales', 'Sales', salesTab], ['purch', 'Purchases', purchTab], ['stock', 'Stock', stockTab],
      ['cust', 'Customers', custTab], ['loans', 'Loans and leases', loansTab], ['fs', 'Financial statements', fsTab],
      ['lines', 'Statement lines', linesTab], ['ye', 'Year-end close', yeTab], ['looker', 'Analysis (Looker Studio)', lookerTab]];
    tabs(body, list);
  };

  // ===================================================================
  // Dashboard
  // ===================================================================
  async function dashTab(tb) {
    tb.innerHTML = '<div id="db-body"></div>';
    const read = periodBar(tb, 'dash', { from: false });
    const load = async () => {
      const p = read();
      const x = await RB.rpc('rb_report_dashboard', { p_date: p.to, p_demo: R.demo });
      const box = $('#db-body', tb), m = x.margin_ok;
      const pct = (a, b) => (Number(b) ? (Number(a) / Number(b) * 100).toFixed(1) + '%' : '—');
      box.innerHTML = '<div class="kpis">' +
        fact('Sales this month', RB.rupees(x.sales_mtd), 'Last month ' + RB.rupees(x.sales_prev_month)) +
        (m ? fact('Gross margin this month', RB.rupees(x.margin_mtd), pct(x.margin_mtd, x.sales_mtd) + ' of sales') : '') +
        fact('Cash and bank', RB.rupees(x.cash_bank), 'All cash and bank accounts') +
        fact('Customers owe', RB.rupees(x.customers_owe), (Number(x.customers_overdue) ? RB.rupees(x.customers_overdue) + ' overdue' : 'Nothing overdue')) +
        fact('Owed to suppliers', RB.rupees(x.suppliers_owed), (Number(x.suppliers_overdue) ? RB.rupees(x.suppliers_overdue) + ' overdue' : 'Nothing overdue')) + '</div>' +
        '<div class="row facts card">' + fact('Sales this year', RB.rupees(x.sales_ytd)) + (m ? fact('Margin this year', RB.rupees(x.margin_ytd), pct(x.margin_ytd, x.sales_ytd)) : '') +
        fact('Sales today', RB.rupees(x.sales_today)) + fact('Stock value', RB.rupees(x.stock_value)) +
        fact('Loans and leases owed', RB.rupees(x.loans_owed)) + fact('Expenses this month', RB.rupees(x.expenses_mtd), 'Operating expenses (8000 accounts)') + '</div>' +
        '<div class="charts"><div class="card"><h2>Sales, last 30 days</h2><div class="chart" id="ch-daily"></div></div>' +
        '<div class="card"><h2>Sales' + (m ? ' and margin' : '') + ', last 12 months</h2><div class="chart" id="ch-month"></div></div>' +
        '<div class="card"><h2>Top products this month</h2><div class="chart" id="ch-top"></div></div>' +
        '<div class="card"><h2>Sales this month by customer type</h2><div class="chart" id="ch-kind"></div></div></div>' +
        '<p class="muted">Sales are after returns and before GST. ' + (x.demo ? 'DEMO entries are included.' : 'DEMO entries are left out.') + ' ' +
        (x.sheets_copy ? 'Last copy to Google Sheets: ' + RB.fmtDate(String(x.sheets_copy.at).slice(0, 10)) + ' (' + esc(x.sheets_copy.status) + ').' : 'No copy to Google Sheets yet.') +
        (x.links && x.links.report_sheet_url ? ' <a href="' + esc(x.links.report_sheet_url) + '" target="_blank" rel="noopener">Open the reporting sheet</a>.' : '') + '</p>';
      const drawAll = () => {
        barChart($('#ch-daily', box), x.daily.map((r) => ({ label: RB.fmtDate(r.d), short: r.d.slice(8), values: [r.net] })), [{ name: 'Sales', color: C1 }],
          { every: 5, label: 'Daily sales' });
        barChart($('#ch-month', box), x.monthly.map((r) => ({ label: RB.fmtDate(r.m).slice(3), short: RB.fmtDate(r.m).slice(3, 6), values: m ? [r.net, r.margin] : [r.net] })),
          m ? [{ name: 'Sales', color: C1 }, { name: 'Margin', color: C2 }] : [{ name: 'Sales', color: C1 }], { label: 'Monthly sales' });
        hbarChart($('#ch-top', box), x.top_products.map((r) => ({ label: r.item, value: r.net, note: m && r.margin != null ? 'Margin ' + RB.rupees(r.margin) : '' })));
        hbarChart($('#ch-kind', box), x.by_kind.map((r) => ({ label: KIND[r.k] || r.k, value: r.net })));
      };
      drawAll();
      R.redraw = drawAll;
    };
    on(tb, '#pb-go', () => load().catch((e) => RB.toast(e.message, true)));
    await load();
  }
  window.addEventListener('resize', () => { clearTimeout(R.rt); R.rt = setTimeout(() => { if (R.tab === 'dash' && R.redraw && $('#ch-daily')) R.redraw(); }, 250); });

  // ===================================================================
  // Sales, purchases, stock, customers, loans
  // ===================================================================
  async function salesTab(tb) {
    tb.innerHTML = '<div id="sl-body"></div>';
    const read = periodBar(tb, 'sales');
    const by = R.salesBy || 'item';
    $('#sl-body', tb).insertAdjacentHTML('beforebegin', '<div class="switch">' + [['item', 'By product'], ['d', 'By day'], ['customer_kind', 'By customer type'], ['channel', 'By channel'], ['all', 'Every line']]
      .map(([k, t]) => '<button data-by="' + k + '" class="' + (k === by ? 'on' : '') + '">' + t + '</button>').join('') + '</div>');
    let grid, rows = [];
    const draw = () => {
      const k = R.salesBy || 'item', m = marginOk();
      let data = rows;
      if (k !== 'all') {
        const g = {};
        rows.forEach((r) => { const key = r[k]; const t = g[key] || (g[key] = { key, net_paise: 0, cost_paise: 0, margin_paise: 0 });
          t.net_paise += Number(r.net_paise); t.cost_paise += Number(r.cost_paise || 0); t.margin_paise += Number(r.margin_paise || 0); });
        data = Object.values(g).sort((a, b) => (k === 'd' ? (a.key < b.key ? -1 : 1) : b.net_paise - a.net_paise));
      }
      const label = { item: 'Product', d: 'Day', customer_kind: 'Customer type', channel: 'Channel' }[k];
      const cols = k === 'all' ? [{ title: 'Date', field: 'd', formatter: (c) => RB.fmtDate(c.getValue()) }, { title: 'Channel', field: 'channel' },
        { title: 'Customer type', field: 'customer_kind', formatter: (c) => esc(KIND[c.getValue()] || c.getValue()) }, { title: 'Product', field: 'item', minWidth: 200 }]
        : [{ title: label, field: 'key', minWidth: 180, formatter: (c) => esc(k === 'd' ? RB.fmtDate(c.getValue()) : k === 'customer_kind' ? (KIND[c.getValue()] || c.getValue()) : c.getValue()) }];
      cols.push(money('net_paise', 'Sales (before GST)'));
      if (m) cols.push(money('cost_paise', 'Cost of goods'), money('margin_paise', 'Margin'),
        { title: 'Margin %', field: 'pct', hozAlign: 'right', headerFilter: false, mutator: (v, r) => (Number(r.net_paise) ? Number(r.margin_paise) / Number(r.net_paise) * 100 : null),
          formatter: (c) => (c.getValue() == null ? '' : c.getValue().toFixed(1) + '%') });
      grid = RB.grid($('#sl-body', tb), cols, data);
    };
    const load = async () => { const p = read(); rows = await RB.rpc('rb_report_sales', { p_from: p.from, p_to: p.to, p_demo: R.demo }); draw(); };
    $$('.switch button', tb).forEach((b) => b.addEventListener('click', () => { R.salesBy = b.dataset.by; $$('.switch button', tb).forEach((x) => x.classList.toggle('on', x === b)); draw(); }));
    on(tb, '#pb-go', () => load().catch((e) => RB.toast(e.message, true)));
    await load();
  }

  async function purchTab(tb) {
    tb.innerHTML = '<div class="card"><h2>Purchase bills</h2><div id="pu-grid"></div></div><div class="card"><h2>Supplier balances (at the To date)</h2><div id="pu-bal"></div></div>';
    const read = periodBar(tb, 'purch');
    let g1, g2;
    const load = async () => {
      const p = read();
      const [bills, bal] = await Promise.all([RB.rpc('rb_report_purchases', { p_from: p.from, p_to: p.to, p_demo: R.demo }),
        RB.rpc('rb_supplier_balances', { p_as_of: p.to, p_include_demo: R.demo })]);
      g1 = RB.grid($('#pu-grid', tb), [
        { title: 'Date', field: 'bill_date', formatter: (c) => RB.fmtDate(c.getValue()) },
        { title: 'Bill / PO', field: 'ref', formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
        { title: 'Supplier', field: 'supplier', minWidth: 180 }, { title: 'Item', field: 'item', minWidth: 160 },
        { title: 'Qty', field: 'qty', hozAlign: 'right', headerFilter: false, formatter: (c) => (c.getValue() == null ? '' : Number(c.getValue()).toLocaleString('en-IN') + ' ' + esc(c.getRow().getData().unit)) },
        money('taxable_paise', 'Before GST'), money('gst_paise', 'GST')], bills);
      g2 = RB.grid($('#pu-bal', tb), [
        { title: 'Supplier', field: 'name', minWidth: 200, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
        money('balance_paise', 'Owed'), money('overdue_paise', 'Overdue'),
        { title: 'Open bills', field: 'open_bills', hozAlign: 'right', headerFilter: false },
        { title: 'Oldest bill', field: 'oldest_bill', formatter: (c) => (c.getValue() ? RB.fmtDate(c.getValue()) : '') }], bal.filter((r) => Number(r.balance_paise)));
    };
    on(tb, '#pb-go', () => load().catch((e) => RB.toast(e.message, true)));
    await load();
  }

  async function stockTab(tb) {
    tb.innerHTML = '<div class="card"><h2>Stock on hand (at the To date)</h2><div id="st-grid"></div></div><div class="card"><h2>Wastage by stage (From to To)</h2><div id="st-waste"></div></div>';
    const read = periodBar(tb, 'stock');
    let g1, g2;
    const load = async () => {
      const p = read();
      const [soh, waste] = await Promise.all([RB.rpc('rb_stock_on_hand', { p_as_of: p.to }), RB.rpc('rb_wastage_report', { p_from: p.from, p_to: p.to })]);
      g1 = RB.grid($('#st-grid', tb), [{ title: 'Code', field: 'code' }, { title: 'Item', field: 'name', minWidth: 200 }, { title: 'Kind', field: 'kind' },
        { title: 'Quantity', field: 'qty_base', hozAlign: 'right', headerFilter: false, formatter: (c) => Number(c.getValue()).toLocaleString('en-IN') + ' ' + esc(c.getRow().getData().base_unit) },
        money('value_paise', 'Value')], soh.filter((r) => Number(r.qty_base) || Number(r.value_paise)));
      g2 = RB.grid($('#st-waste', tb), [{ title: 'Item', field: 'item', minWidth: 180 }, { title: 'Stage', field: 'stage' },
        { title: 'Batches', field: 'batches', hozAlign: 'right', headerFilter: false },
        { title: 'Input', field: 'input_qty', hozAlign: 'right', headerFilter: false, formatter: (c) => Number(c.getValue()).toLocaleString('en-IN') + ' ' + esc(c.getRow().getData().base_unit) },
        { title: 'Wastage', field: 'wastage_qty', hozAlign: 'right', headerFilter: false, formatter: (c) => Number(c.getValue()).toLocaleString('en-IN') + ' ' + esc(c.getRow().getData().base_unit) },
        { title: 'Wastage %', field: 'wastage_pct', hozAlign: 'right', headerFilter: false, formatter: (c) => (c.getValue() == null ? '' : Number(c.getValue()).toFixed(1) + '%') }], waste);
    };
    on(tb, '#pb-go', () => load().catch((e) => RB.toast(e.message, true)));
    await load();
  }

  async function custTab(tb) {
    tb.innerHTML = '<div id="cu-sum" class="row facts card"></div><div class="card"><h2>What customers owe, by age</h2><div id="cu-grid"></div></div>';
    const read = periodBar(tb, 'cust', { from: false });
    let g;
    const load = async () => {
      const p = read();
      const rows = (await RB.rpc('rb_customer_balances', { p_as_of: p.to, p_include_demo: R.demo })).filter((r) => Number(r.balance_paise));
      const s = (k) => rows.reduce((t, r) => t + Number(r[k] || 0), 0);
      $('#cu-sum', tb).innerHTML = fact('Total owed', RB.rupees(s('balance_paise'))) + fact('Not yet due', RB.rupees(s('not_due_paise'))) +
        fact('1 to 30 days late', RB.rupees(s('d1_30_paise'))) + fact('31 to 60', RB.rupees(s('d31_60_paise'))) + fact('61 to 90', RB.rupees(s('d61_90_paise'))) +
        fact('Over 90 days', RB.rupees(s('over_90_paise')));
      g = RB.grid($('#cu-grid', tb), [{ title: 'Customer', field: 'name', minWidth: 200, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
        { title: 'Type', field: 'kind', formatter: (c) => esc(KIND[c.getValue()] || c.getValue()) },
        money('balance_paise', 'Owed'), money('not_due_paise', 'Not due'), money('d1_30_paise', '1–30'), money('d31_60_paise', '31–60'),
        money('d61_90_paise', '61–90'), money('over_90_paise', 'Over 90'), money('on_account_paise', 'Not on an invoice'),
        { title: 'Oldest due', field: 'oldest_due', formatter: (c) => (c.getValue() ? RB.fmtDate(c.getValue()) : '') },
        { title: 'Over limit', field: 'over_limit', formatter: (c) => (c.getValue() ? RB.badge('locked', 'over limit') : '') }], rows);
    };
    on(tb, '#pb-go', () => load().catch((e) => RB.toast(e.message, true)));
    await load();
  }

  async function loansTab(tb) {
    tb.innerHTML = '<div id="lo-sum" class="row facts card"></div><div class="card"><h2>Loans and finance leases</h2><div id="lo-grid"></div></div>' +
      '<div class="card"><h2>Rented premises (operating leases)</h2><div id="lo-ol"></div></div><p class="muted">Payments, schedules and the AS 19 notes are on <a href="#/loans">Loans and leases</a>.</p>';
    const read = periodBar(tb, 'loans', { from: false });
    let g;
    const load = async () => {
      const p = read();
      const x = await RB.rpc('rb_loans_summary', { p_as_of: p.to });
      const live = x.loans.filter((l) => l.status !== 'draft');
      const s = (k) => live.reduce((t, r) => t + Number(r[k] || 0), 0);
      $('#lo-sum', tb).innerHTML = fact('Owed in all', RB.rupees(s('owed_paise'))) + fact('Due within 12 months', RB.rupees(s('within_12_paise'))) +
        fact('Due after 12 months', RB.rupees(s('owed_paise') - s('within_12_paise'))) + fact('Interest accrued, not paid', RB.rupees(s('accrued_paise')));
      g = RB.grid($('#lo-grid', tb), [{ title: 'No.', field: 'loan_no', formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
        { title: 'What for', field: 'name', minWidth: 200 }, { title: 'Lender', field: 'lender' },
        money('owed_paise', 'Owed'), money('within_12_paise', 'Due within 12 months'), money('accrued_paise', 'Interest accrued'),
        { title: 'Next due', field: 'next', formatter: (c) => { const n = c.getRow().getData().next_due; return n ? RB.fmtDate(n.due_date) + ' · ' + RB.rupees(n.payment_paise) : ''; } }], live);
      RB.grid($('#lo-ol', tb), [{ title: 'No.', field: 'lease_no', formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
        { title: 'What', field: 'name', minWidth: 200 }, { title: 'Ends', field: 'end_date', formatter: (c) => RB.fmtDate(c.getValue()) },
        money('rent_now_paise', 'Rent now'), money('deposit_paise', 'Deposit held')], x.op_leases.filter((l) => l.status !== 'draft'));
    };
    on(tb, '#pb-go', () => load().catch((e) => RB.toast(e.message, true)));
    await load();
  }

  // ===================================================================
  // Financial statements
  // ===================================================================
  const SECT = { EQ: "Owners' funds", NCL: 'Non-current liabilities', CL: 'Current liabilities', NCA: 'Non-current assets', CA: 'Current assets' };
  const CF = [
    ['A', 'A. Cash flow from operating activities', [
      ['A_pbt', 'Net profit before tax'], ['h', 'Adjustments for:'], ['A_adj_dep', 'Depreciation, amortisation and impairment'],
      ['A_adj_prov', 'Provision for doubtful debts'], ['A_adj_other', 'Other non-cash items'], ['A_adj_fin', 'Finance costs'], ['A_adj_inc', 'Interest and dividend income'],
      ['s:op', 'Operating profit before working capital changes', ['A_pbt', 'A_adj_dep', 'A_adj_prov', 'A_adj_other', 'A_adj_fin', 'A_adj_inc']],
      ['h', 'Changes in working capital:'], ['A_wc_inv', '(Increase) / decrease in inventories'], ['A_wc_tr', '(Increase) / decrease in trade receivables'],
      ['A_wc_assets', '(Increase) / decrease in loans, advances and other assets'], ['A_wc_tp', 'Increase / (decrease) in trade payables'],
      ['A_wc_liab', 'Increase / (decrease) in other liabilities and provisions'],
      ['s:gen', 'Cash generated from operations', ['A_pbt', 'A_adj_dep', 'A_adj_prov', 'A_adj_other', 'A_adj_fin', 'A_adj_inc', 'A_wc_inv', 'A_wc_tr', 'A_wc_assets', 'A_wc_tp', 'A_wc_liab']],
      ['A_tax', 'Income taxes paid (net of refunds)']]],
    ['B', 'B. Cash flow from investing activities', [['B_ppe_out', 'Purchase of property, plant and equipment and intangible assets'],
      ['B_ppe_in', 'Proceeds from sale of property, plant and equipment'], ['B_invest', 'Investments bought or sold (net)'],
      ['B_deposits', 'Deposits and loans given (net)'], ['B_income', 'Interest and dividends received'], ['B_other', 'Other investing activities (net)']]],
    ['C', 'C. Cash flow from financing activities', [['C_partners_in', 'Capital introduced by partners'], ['C_partners_out', 'Drawings and capital withdrawn by partners'],
      ['C_borrow_in', 'Proceeds from borrowings'], ['C_borrow_out', 'Repayment of borrowings'], ['C_lease_out', 'Repayment of finance lease obligations'],
      ['C_lease_in', 'Other finance lease movements'], ['C_interest', 'Interest and finance charges paid'], ['C_other', 'Other financing activities (net)']]]];

  async function fsTab(tb) {
    tb.innerHTML = '<div class="switch no-print">' + [['bs', 'Balance sheet'], ['pl', 'Profit and loss'], ['cf', 'Cash flow'], ['notes', 'Notes']]
      .map(([k, t]) => '<button data-v="' + k + '" class="' + (k === (R.fsView || 'bs') ? 'on' : '') + '">' + t + '</button>').join('') + '</div><div id="fs-body"></div>';
    if (!R.fs) R.fs = { from: fyStart(today()), to: today() };
    const read = periodBar(tb, 'fs', { extra: ' <button id="fs-xls">Download to Excel</button>' });
    let F, CFd;
    const draw = () => {
      const v = R.fsView || 'bs', box = $('#fs-body', tb);
      const head = '<div class="fs-head"><b>' + esc(F.firm.name) + '</b>' + (F.firm.reg_no ? ' · ' + esc(F.firm.reg_no) : '') + ' · ' + esc(F.firm.legal_form) +
        '<br><small>Indian AS (ICAI), in full. Amounts in ₹. ' + (F.demo ? RB.badge('demo', 'DEMO entries included') : '') + '</small></div>';
      const warn = (Number(F.bs_difference) ? '<div class="msg error">The balance sheet does not balance by ' + RB.rupees(F.bs_difference) + '. Please tell the FC.</div>' : '') +
        (Number(F.bs.lines.BS_SUSP || 0) ? '<div class="msg info">Suspense and clearing accounts hold ' + RB.rupees(F.bs.lines.BS_SUSP) + '. They should be nil before the accounts are final: see the notes.</div>' : '');
      if (v === 'bs') box.innerHTML = head + warn + bsTable(F);
      if (v === 'pl') box.innerHTML = head + plTable(F);
      if (v === 'cf') box.innerHTML = head + cfTable(CFd);
      if (v === 'notes') box.innerHTML = head + notesTables(F);
    };
    const load = async () => {
      const p = read();
      [F, CFd] = await Promise.all([RB.rpc('rb_financial_statements', { p_from: p.from, p_to: p.to, p_demo: R.demo }),
        RB.rpc('rb_cash_flow', { p_from: p.from, p_to: p.to, p_demo: R.demo })]);
      draw();
    };
    $$('.switch button', tb).forEach((b) => b.addEventListener('click', () => { R.fsView = b.dataset.v; $$('.switch button', tb).forEach((x) => x.classList.toggle('on', x === b)); if (F) draw(); }));
    on(tb, '#pb-go', () => load().catch((e) => RB.toast(e.message, true)));
    on(tb, '#fs-xls', () => {
      const wb = XLSX.utils.book_new(), tmp = document.createElement('div');
      [['Balance sheet', bsTable(F)], ['Profit and loss', plTable(F)], ['Cash flow', cfTable(CFd)], ['Notes', notesTables(F)]].forEach(([n, h]) => {
        tmp.innerHTML = h; const rows = [];
        $$('table', tmp).forEach((t) => { $$('tr', t).forEach((tr) => rows.push($$('th,td', tr).map((c) => { const s = c.textContent.trim(); const num = s.replace(/[₹,\s]/g, '').replace(/^\((.*)\)$/, '-$1').replace('−', '-'); return /^-?\d+(\.\d+)?$/.test(num) ? Number(num) : s; }))); rows.push([]); });
        XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(rows), n);
      });
      XLSX.writeFile(wb, 'Financial statements ' + RB.fmtDate(F.to) + '.xlsx');
    });
    await load();
  }
  const fmt = (p) => { const n = Number(p || 0); if (!n) return '–'; const s = RB.rupees(Math.abs(n)).replace('₹', ''); return n < 0 ? '(' + s + ')' : s; };
  const colHead = (F, pl) => '<tr><th></th><th>Note</th><th class="n">' + (pl ? RB.fmtDate(F.from) + ' to ' + RB.fmtDate(F.to) : 'As at ' + RB.fmtDate(F.to)) +
    '</th><th class="n">' + (pl ? RB.fmtDate(F.prev_from) + ' to ' + RB.fmtDate(F.prev_to) : 'As at ' + RB.fmtDate(F.bs_prev_date)) + '</th></tr>';
  // Note numbers: every line with a figure in either column, in order.
  function noteNos(F) {
    const n = {}; let i = 0;
    F.lines.forEach((l) => {
      const a = l.statement === 'BS' ? [F.bs.lines[l.code], F.bs_prev.lines[l.code]] : [F.pl[l.code], F.pl_prev[l.code]];
      if (a.some((x) => Number(x || 0))) n[l.code] = ++i;
    });
    return n;
  }
  function bsTable(F) {
    const nn = noteNos(F), line = (l) => '<tr><td class="ind">' + esc(l.name) + '</td><td>' + (nn[l.code] || '') + '</td><td class="n">' + fmt(F.bs.lines[l.code]) + '</td><td class="n">' + fmt(F.bs_prev.lines[l.code]) + '</td></tr>';
    const sum = (sects, d) => F.lines.filter((l) => sects.includes(l.section)).reduce((t, l) => t + Number(d.lines[l.code] || 0), 0);
    const block = (title, sects) => '<tr class="h1"><td colspan="4">' + title + '</td></tr>' + sects.map((s, i) => {
      const ls = F.lines.filter((l) => l.section === s && nn[l.code]);
      return '<tr class="h2"><td colspan="4">' + (i + 1) + '. ' + SECT[s] + '</td></tr>' + ls.map(line).join('') +
        '<tr class="sub"><td colspan="2"></td><td class="n">' + fmt(sum([s], F.bs)) + '</td><td class="n">' + fmt(sum([s], F.bs_prev)) + '</td></tr>';
    }).join('') + '<tr class="tot"><td colspan="2">Total</td><td class="n">' + fmt(sum(sects, F.bs)) + '</td><td class="n">' + fmt(sum(sects, F.bs_prev)) + '</td></tr>';
    return '<div class="grid-wrap"><table class="fs"><caption>Balance sheet as at ' + RB.fmtDate(F.to) + '</caption>' + colHead(F) +
      block('I. EQUITY AND LIABILITIES', ['EQ', 'NCL', 'CL']) + block('II. ASSETS', ['NCA', 'CA']) + '</table></div>';
  }
  function plTable(F) {
    const nn = noteNos(F), P = F.pl, Q = F.pl_prev;
    const r = (label, k, cls, no) => '<tr' + (cls ? ' class="' + cls + '"' : '') + '><td' + (cls ? '' : ' class="ind"') + '>' + label + '</td><td>' + (no || '') + '</td><td class="n">' + fmt(P[k]) + '</td><td class="n">' + fmt(Q[k]) + '</td></tr>';
    const L = (code) => F.lines.find((l) => l.code === code);
    const exp = ['PL_COM', 'PL_SIT', 'PL_CHG', 'PL_EMP', 'PL_FIN', 'PL_DEP', 'PL_OTH'].filter((c) => Number(P[c] || 0) || Number(Q[c] || 0));
    return '<div class="grid-wrap"><table class="fs"><caption>Statement of profit and loss for ' + RB.fmtDate(F.from) + ' to ' + RB.fmtDate(F.to) + '</caption>' + colHead(F, true) +
      r('I. Revenue from operations', 'PL_REV', 'h2', nn.PL_REV) + r('II. Other income', 'PL_OI', 'h2', nn.PL_OI) + r('III. Total income (I + II)', 'total_income', 'sub') +
      '<tr class="h2"><td colspan="4">IV. Expenses</td></tr>' + exp.map((c) => r(esc(L(c).name), c, '', nn[c])).join('') +
      r('Total expenses', 'total_expenses', 'sub') + r('V. Profit before exceptional and extraordinary items and tax (III − IV)', 'before_exceptional', 'h2') +
      (Number(P.PL_EXC) || Number(Q.PL_EXC) ? r('VI. Exceptional and extraordinary items', 'PL_EXC', '', nn.PL_EXC) : '') +
      r('VII. Profit before tax', 'before_tax', 'h2') + r('VIII. Tax expense', 'PL_TAX', '', nn.PL_TAX) +
      r('IX. Profit / (loss) for the period', 'profit', 'tot') + '</table></div>' +
      '<div class="grid-wrap"><table class="fs"><caption>Appropriation: share of each partner (profit-sharing ratio in Settings)</caption><tr><th>Partner</th><th class="n">Ratio</th><th class="n">Share of profit / (loss)</th></tr>' +
      F.partners.map((p) => '<tr><td>' + esc(p.name) + '</td><td class="n">' + p.weight + '</td><td class="n">' + fmt(p.share) + '</td></tr>').join('') +
      '</table></div><p class="muted">Expenses are shown by nature as Schedule III asks. Kitchen labour and overheads added to stock (module 6 step 1) are part of "Changes in inventories". ' +
      'The year-end close moves the profit to the partners\' current accounts; the statement still shows the year\'s profit after the close.</p>';
  }
  function cfTable(X) {
    const c = X.cur, p = X.prev, sumK = (o, ks) => ks.reduce((t, k) => t + Number(o[k] || 0), 0);
    const sectKeys = (rows) => rows.filter((r) => r[0] !== 'h' && !r[0].startsWith('s:')).map((r) => r[0]);
    let h = '<div class="grid-wrap"><table class="fs"><caption>Cash flow statement for ' + RB.fmtDate(X.from) + ' to ' + RB.fmtDate(X.to) + ' (AS 3, indirect method)</caption>' +
      '<tr><th></th><th class="n">' + RB.fmtDate(X.from) + ' to ' + RB.fmtDate(X.to) + '</th><th class="n">' + RB.fmtDate(X.prev_from) + ' to ' + RB.fmtDate(X.prev_to) + '</th></tr>';
    let net = 0, netp = 0;
    CF.forEach(([k, title, rows]) => {
      h += '<tr class="h2"><td colspan="3">' + title + '</td></tr>';
      rows.forEach((r) => {
        if (r[0] === 'h') { h += '<tr><td class="ind"><i>' + r[1] + '</i></td><td></td><td></td></tr>'; return; }
        if (r[0].startsWith('s:')) { h += '<tr class="sub"><td>' + r[1] + '</td><td class="n">' + fmt(sumK(c, r[2])) + '</td><td class="n">' + fmt(sumK(p, r[2])) + '</td></tr>'; return; }
        if (!Number(c[r[0]] || 0) && !Number(p[r[0]] || 0) && r[0] !== 'A_pbt') return;
        h += '<tr><td class="ind">' + r[1] + '</td><td class="n">' + fmt(c[r[0]]) + '</td><td class="n">' + fmt(p[r[0]]) + '</td></tr>';
      });
      const a = sumK(c, sectKeys(rows)), b = sumK(p, sectKeys(rows)); net += a; netp += b;
      h += '<tr class="sub"><td>Net cash from / (used in) ' + { A: 'operating', B: 'investing', C: 'financing' }[k] + ' activities</td><td class="n">' + fmt(a) + '</td><td class="n">' + fmt(b) + '</td></tr>';
    });
    h += '<tr class="h2"><td>Net increase / (decrease) in cash and cash equivalents (A + B + C)</td><td class="n">' + fmt(net) + '</td><td class="n">' + fmt(netp) + '</td></tr>' +
      '<tr><td class="ind">Cash and cash equivalents at the beginning of the period</td><td class="n">' + fmt(c.opening_cash) + '</td><td class="n">' + fmt(p.opening_cash) + '</td></tr>' +
      '<tr class="tot"><td>Cash and cash equivalents at the end of the period</td><td class="n">' + fmt(c.closing_cash) + '</td><td class="n">' + fmt(p.closing_cash) + '</td></tr></table></div>';
    if (Number(c.difference) || Number(p.difference)) h += '<div class="msg error">The cash flow does not agree with the change in cash by ' + RB.rupees(c.difference) + '. Please tell the FC.</div>';
    h += '<div class="grid-wrap"><table class="fs"><caption>Components of cash and cash equivalents at ' + RB.fmtDate(X.to) + '</caption>' +
      (c.cash_accounts.length ? c.cash_accounts.map((a) => '<tr><td class="ind">' + esc(a.code + ' ' + a.name) + '</td><td class="n">' + fmt(a.amount) + '</td></tr>').join('') : '<tr><td class="muted">None.</td><td></td></tr>') +
      '<tr class="tot"><td>Total</td><td class="n">' + fmt(c.closing_cash) + '</td></tr></table></div>' +
      '<p class="muted">Opening balances brought in at the start (take-on) are part of the cash at the beginning, not cash flows. ' +
      (Number(c.non_cash_investing) ? 'Non-cash transactions left out (AS 3 paragraph 43): assets acquired under finance leases and similar, ' + RB.rupees(c.non_cash_investing) + '. ' : '') +
      'Bank deposits that are not cash equivalents are shown under investing activities.</p>';
    return h;
  }
  function notesTables(F) {
    const nn = noteNos(F);
    const rows = (code) => {
      const l = F.lines.find((x) => x.code === code), bs = l.statement === 'BS';
      const cur = bs ? F.bs.accounts : F.pl.accounts, prev = bs ? F.bs_prev.accounts : F.pl_prev.accounts;
      const keys = {};
      cur.filter((a) => a.line === code).forEach((a) => { const k = a.code || a.name; (keys[k] = keys[k] || { code: a.code, name: a.name, c: 0, p: 0 }).c += Number(a.amount); });
      prev.filter((a) => a.line === code).forEach((a) => { const k = a.code || a.name; (keys[k] = keys[k] || { code: a.code, name: a.name, c: 0, p: 0 }).p += Number(a.amount); });
      let list = Object.values(keys).sort((a, b) => String(a.code || 'z').localeCompare(String(b.code || 'z')));
      let totC = bs ? F.bs.lines[code] : F.pl[code], totP = bs ? F.bs_prev.lines[code] : F.pl_prev[code];
      if (code === 'PL_COM') {
        list = list.concat([{ name: 'Less: purchases of stock-in-trade, shown separately', c: -Number(F.pl.PL_SIT || 0), p: -Number(F.pl_prev.PL_SIT || 0) },
          { name: 'Less: changes in inventories, shown separately', c: -Number(F.pl.PL_CHG || 0), p: -Number(F.pl_prev.PL_CHG || 0) }]);
      }
      return '<table class="fs"><caption>Note ' + nn[code] + ': ' + esc(l.name) + '</caption><tr><th></th><th class="n">' + (bs ? RB.fmtDate(F.to) : 'This period') + '</th><th class="n">' + (bs ? RB.fmtDate(F.bs_prev_date) : 'Previous period') + '</th></tr>' +
        list.filter((a) => a.c || a.p).map((a) => '<tr><td class="ind">' + esc((a.code ? a.code + ' ' : '') + a.name) + '</td><td class="n">' + fmt(a.c) + '</td><td class="n">' + fmt(a.p) + '</td></tr>').join('') +
        '<tr class="tot"><td>Total</td><td class="n">' + fmt(totC) + '</td><td class="n">' + fmt(totP) + '</td></tr></table>';
    };
    return '<p class="muted">Each note lists the accounts behind the line. Change which line an account goes to on the Statement lines tab.</p><div class="grid-wrap">' +
      F.lines.filter((l) => nn[l.code]).map((l) => rows(l.code)).join('') + '</div>';
  }

  // ===================================================================
  // Statement lines (account mapping)
  // ===================================================================
  async function linesTab(tb) {
    const x = await RB.rpc('rb_fs_map_list');
    const lineName = Object.fromEntries(x.lines.map((l) => [l.code, l.name + ' (' + (l.statement === 'BS' ? 'balance sheet' : 'profit and loss') + ')']));
    const canEdit = RB.has('accounts.edit');
    tb.innerHTML = '<p class="muted">Each account goes to one line of the financial statements. A rule covers every account whose code starts with its digits; the longest match wins. ' +
      'The lines follow Schedule III as ICAI\'s Guidance Note uses it for firms.' + (canEdit ? '' : ' Only the Accountant, the FC or a Director can change them.') + '</p>' +
      (canEdit ? '<div class="actions" style="margin:0 0 .75rem"><button class="primary" id="ln-add">+ Rule</button></div>' : '') +
      '<div class="card"><h2>Rules</h2><div id="ln-map"></div></div><div class="card"><h2>Every account and its line</h2><div id="ln-acc"></div></div>';
    const mg = RB.grid($('#ln-map', tb), [{ title: 'Accounts starting with', field: 'prefix' }, { title: 'Line', field: 'line', minWidth: 260, formatter: (c) => esc(lineName[c.getValue()]) },
      { title: 'Accounts', field: 'accounts', hozAlign: 'right', headerFilter: false }], x.map);
    RB.grid($('#ln-acc', tb), [{ title: 'Account', field: 'code' }, { title: 'Name', field: 'name', minWidth: 220 },
      { title: 'Line', field: 'line', minWidth: 260, formatter: (c) => esc(lineName[c.getValue()] || c.getValue()) },
      { title: 'Cash flow (AS 3)', field: 'cash_flow' }], x.accounts);
    const edit = (row) => {
      const m = RB.modal('<h2>' + (row ? 'Change the rule' : 'New rule') + '</h2><div class="m-msg"></div>' +
        RB.field('lm-pre', 'Accounts starting with', RB.inp('lm-pre', row ? row.prefix : '', ' inputmode="numeric" placeholder="e.g. 80050150 or 8005"' + (row ? ' readonly' : '')), 'An 8-digit code for one account, or fewer digits for a group.', true) +
        RB.field('lm-line', 'Line', RB.sel('lm-line', x.lines.map((l) => [l.code, lineName[l.code]]), row ? row.line : ''), null, true) +
        '<div class="actions"><button class="primary" id="lm-save">Save</button>' + (row ? '<button class="danger" id="lm-del">Delete the rule</button>' : '') + '<button data-close>Cancel</button></div>');
      on(m.el, '#lm-save', async () => { try { await RB.rpc('rb_save_fs_map', { p: { prefix: $('#lm-pre', m.el).value, line_code: $('#lm-line', m.el).value } }); RB.toast('Saved'); m.close(); R.reload(); } catch (e) { RB.modalMsg(m, e.message); } });
      on(m.el, '#lm-del', async () => { try { await RB.rpc('rb_delete_fs_map', { p_prefix: row.prefix }); RB.toast('Deleted'); m.close(); R.reload(); } catch (e) { RB.modalMsg(m, e.message); } });
    };
    if (canEdit) { on(tb, '#ln-add', () => edit(null)); mg.on('rowClick', (e, r) => edit(r.getData())); }
  }

  // ===================================================================
  // Year-end close
  // ===================================================================
  async function yeTab(tb) {
    const t = today(), fy = fyStart(t), lastEnd = addDays(fy, -1);
    const ends = [0, 1, 2, 3].map((i) => (Number(lastEnd.slice(0, 4)) - i) + '-03-31').concat([(Number(fy.slice(0, 4)) + 1) + '-03-31']).sort().reverse();
    if (!R.ye) R.ye = lastEnd;
    tb.innerHTML = '<div class="row" style="align-items:flex-end">' + RB.field('ye-fy', 'Financial year ending', RB.sel('ye-fy', ends.map((e) => [e, 'FY ' + (Number(e.slice(0, 4)) - 1) + '-' + e.slice(2, 4) + ' (ends ' + RB.fmtDate(e) + ')']), R.ye)) +
      '<div class="field" style="flex:0 1 auto"><button class="primary" id="ye-go">Show</button></div></div><div id="ye-body" class="card"></div>';
    const load = async () => {
      R.ye = $('#ye-fy', tb).value;
      const x = await RB.rpc('rb_year_end_preview', { p_fy_end: R.ye });
      const part = (y) => '<table class="fs"><tr><th>Partner</th><th class="n">Ratio</th><th class="n">Share</th></tr>' +
        y.partners.map((p) => '<tr><td>' + esc(p.name) + '</td><td class="n">' + p.weight + '</td><td class="n">' + fmt(p.share) + '</td></tr>').join('') + '</table>';
      const jl = x.real.journals.concat(x.demo.journals);
      const latest = jl.filter((j) => j.status === 'posted').sort((a, b) => b.id - a.id)[0];
      const open = Number(x.real.profit) || x.real.lines.length || x.demo.lines.length;
      $('#ye-body', tb).innerHTML = '<h2>Year-end close: ' + esc(x.label) + '</h2>' +
        '<p class="muted">Moves the year\'s profit or loss from every profit and loss account to the partners\' current accounts (50010135), in the profit-sharing ratio in Settings. ' +
        'The statement of profit and loss for the year still shows the profit afterwards. Posted on ' + RB.fmtDate(x.fy_end) + '. Entries made later in the closed year can be closed by running it again.</p>' +
        (!x.ended ? '<div class="msg info">This year has not ended yet. It can be closed from ' + RB.fmtDate(addDays(x.fy_end, 1)) + '.</div>' : '') +
        (x.unlocked_months.length ? '<div class="msg info">Lock the months before closing, so nothing is added later: ' + esc(x.unlocked_months.join(', ')) + ' are open. Keep March open until the close is posted, then lock it.</div>' : '') +
        (x.fy_end_locked ? '<div class="msg error">March is locked. Unlock it in Accounts to post the close, then lock it again.</div>' : '') +
        (Number(x.real.earlier_unclosed) ? '<div class="msg error">An earlier year still has profit or loss that is not closed (' + RB.rupees(-x.real.earlier_unclosed) + '). Close the earlier year first.</div>' : '') +
        '<div class="row facts">' + fact('Profit / (loss) still to close', fmt(x.real.profit)) + fact('Profit and loss accounts', Math.max(Number(x.real.accounts), 0)) +
        (x.demo.lines.length ? fact('DEMO entries to close', fmt(x.demo.profit)) : '') + '</div>' +
        (open ? part(x.real) : '<p>✅ Nothing left to close for this year.</p>') +
        (jl.length ? '<h3>Closing journals</h3><table class="fs"><tr><th>No.</th><th>Date</th><th class="n">Total</th><th>Status</th></tr>' +
          jl.map((j) => '<tr><td>' + esc(j.journal_no) + '</td><td>' + RB.fmtDate(j.date) + '</td><td class="n">' + fmt(j.total_paise) + '</td><td>' + esc(j.status) + '</td></tr>').join('') + '</table>' : '') +
        '<div class="actions">' + (x.can_post && x.ended && open ? '<button class="primary" id="ye-post">Close ' + esc(x.label) + '</button>' : '') +
        (!x.can_post ? '<p class="muted">The year is closed by the FC or a Director.</p>' : '') +
        (latest && RB.has('power.reverse_entries') ? '<button class="danger" id="ye-rev">Reverse the latest close</button>' : '') + '</div>';
      on(tb, '#ye-post', async () => {
        try {
          if (!(await RB.confirm('Close ' + x.label + '?', 'Posts ' + fmt(x.real.profit) + ' to the partners\' current accounts on ' + RB.fmtDate(x.fy_end) + '.'))) return;
          await RB.rpc('rb_post_year_end', { p_fy_end: x.fy_end }); RB.toast('Year closed'); load();
        } catch (e) { RB.toast(e.message, true); }
      });
      on(tb, '#ye-rev', async () => {
        try {
          const r = await RB.cashbank.askReason('Reverse ' + latest.journal_no, 'The closing journal is reversed on the date you choose. The year then shows as open again.', true); if (!r) return;
          await RB.rpc('rb_reverse_journal', { p_id: latest.id, p_date: r.date, p_reason: r.reason }); RB.toast('Reversed'); load();
        } catch (e) { RB.toast(e.message, true); }
      });
    };
    on(tb, '#ye-go', () => load().catch((e) => RB.toast(e.message, true)));
    await load();
  }

  // ===================================================================
  // Analysis: the Looker Studio report fed by the weekly Sheets copy
  // ===================================================================
  async function lookerTab(tb) {
    const x = await RB.rpc('rb_report_dashboard', { p_date: today(), p_demo: R.demo });
    const l = x.links || {}, s = x.sheets_copy;
    tb.innerHTML = '<div class="card"><h2>Weekly copy to Google Sheets</h2>' +
      (s ? '<p>Last copy: <b>' + RB.fmtDate(String(s.at).slice(0, 10)) + '</b>, ' + esc(s.status === 'ok' ? 'done' : 'FAILED') + (s.rows ? ', ' + Number(s.rows).toLocaleString('en-IN') + ' rows' : '') + '.' +
        (s.status !== 'ok' ? ' <span class="diff">' + esc(s.detail || '') + '</span>' : '') + '</p>' : '<p class="muted">No copy yet. The Apps Script makes it every Monday morning once it is set up (see the setup guide).</p>') +
      (l.report_sheet_url ? '<p><a href="' + esc(l.report_sheet_url) + '" target="_blank" rel="noopener">Open the reporting sheet</a> (only people it is shared with can open it).</p>' : '') + '</div>' +
      '<div class="card"><h2>Looker Studio report</h2>' +
      (l.looker_url ? '<p class="muted">Shown only to someone signed in to Google with an account the report is shared with.</p><div class="looker"><iframe src="' + esc(l.looker_url) + '" allowfullscreen sandbox="allow-storage-access-by-user-activation allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox"></iframe></div>'
        : '<p class="muted">No Looker Studio report is linked yet. Build it on the reporting sheet, share it with named Google accounts only, then paste its link here.</p>') +
      (RB.has('settings.edit') ? '<div class="row" style="align-items:flex-end">' + RB.field('lk-url', 'Looker Studio report link', RB.inp('lk-url', l.looker_url || '', ' placeholder="https://lookerstudio.google.com/reporting/…"')) +
        '<div class="field" style="flex:0 1 auto"><button class="primary" id="lk-save">Save the link</button></div></div>' : '') + '</div>';
    on(tb, '#lk-save', async () => { try { await RB.rpc('rb_save_report_links', { p: { looker_url: $('#lk-url', tb).value } }); RB.toast('Link saved'); R.reload(); } catch (e) { RB.toast(e.message, true); } });
  }
})();
