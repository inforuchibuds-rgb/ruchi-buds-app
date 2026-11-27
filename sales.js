// =====================================================================
// RUCHI BUDS APP · sales.js · Version 1.0 · 27-Nov-2026
// Module 5 screen "Sales": the counter sale form (by pack or loose by
// weight, at the Masters price for the channel, line or whole-bill
// discount, cash, UPI, bank, credit or part paid, Invoice or Tax
// Invoice), the sales list, returns with approval, and the sales
// summary by day, product and customer type.
// Staff see the bill they are making, but no sales totals or costs.
// =====================================================================
(function () {
  'use strict';
  const RB = window.RB, $ = RB.$, $$ = RB.$$, esc = RB.esc;
  const SA = (RB.sales = {});

  SA.STATUS = { open: 'Owed', paid: 'Paid', cancelled: 'Cancelled' };
  SA.STATUS_BADGE = { open: 'invited', paid: 'active', cancelled: 'inactive' };
  SA.RET_STATUS = { awaiting_approval: 'Waiting for approval', posted: 'Posted', refused: 'Refused', reversed: 'Reversed' };
  SA.RET_BADGE = { awaiting_approval: 'protected', posted: 'active', refused: 'inactive', reversed: 'inactive' };
  SA.MODES = { cash: 'Cash', upi: 'UPI', bank: 'Bank', credit: 'Credit (pay later)' };
  SA.CHANNELS = { retail: 'Retail', trader: 'Trader', online: 'Online' };
  SA.DOC = { invoice: 'Invoice', tax_invoice: 'Tax Invoice' };

  const money = () => RB.has('power.see_totals');
  const amt = (p) => (p == null ? '' : RB.rupees(p));
  const num = (v) => { const s = String(v == null ? '' : v).replace(/[,\s]/g, ''); if (s === '') return null; const n = Number(s); if (!isFinite(n)) throw new Error('"' + v + '" is not a number.'); return n; };
  const trim = (n) => Number(n).toLocaleString('en-IN', { maximumFractionDigits: 3 });
  SA.q = (n, unit) => {
    if (n == null || n === '') return '';
    const v = Number(n);
    if ((unit === 'g' || unit === 'ml') && Math.abs(v) >= 1000) return trim(v / 1000) + ' ' + (unit === 'g' ? 'kg' : 'l');
    return trim(v) + ' ' + (unit || '');
  };
  const fy = () => { const t = RB.today(); return (Number(t.slice(5, 7)) >= 4 ? t.slice(0, 4) : String(Number(t.slice(0, 4)) - 1)) + '-04-01'; };
  const monthStart = () => RB.today().slice(0, 8) + '01';
  const on = (root, sel, fn, ev) => { const b = $(sel, root); if (b) b.addEventListener(ev || 'click', fn); };
  SA.on = on;

  // Lists the sale form needs.
  async function lists() {
    const d = await RB.masters.load(['items', 'units', 'productPacks', 'packTypes', 'customers']);
    d.item = Object.fromEntries(d.items.map((i) => [i.id, i]));
    d.unit = Object.fromEntries(d.units.map((u) => [u.code, u]));
    d.packType = Object.fromEntries(d.packTypes.map((p) => [p.id, p]));
    d.sellable = d.items.filter((i) => i.is_active && (i.kind === 'finished' || (i.kind === 'byproduct' && i.byproduct_use === 'sellable')));
    d.packsOf = (itemId) => d.productPacks.filter((p) => p.item_id === Number(itemId) && p.is_active)
      .map((p) => Object.assign({}, p, { name: (d.packType[p.pack_type_id] || {}).name || 'Pack' }))
      .sort((a, b) => Number(a.net_qty) - Number(b.net_qty));
    try {
      d.settings = await RB.select('app_settings', 'gstin,gst_registered_from,state_code,sale_prices_include_gst', (x) => x.eq('id', 1).single());
    } catch (e) { d.settings = {}; }
    return d;
  }
  // Masters price for a pack (or loose per kg / litre / piece) and channel.
  const listPrice = (d, itemId, packId, channel) => {
    if (packId) {
      const p = d.productPacks.find((x) => x.id === Number(packId)); if (!p) return null;
      if (channel === 'trader') return p.trader_price_paise != null ? p.trader_price_paise : p.retail_price_paise;
      if (channel === 'online') return p.online_price_paise != null ? p.online_price_paise : p.retail_price_paise;
      return p.retail_price_paise;
    }
    const it = d.item[itemId]; return it ? it.loose_price_paise : null;
  };
  const gstOk = (d, date) => !!(d.settings.gstin && d.settings.gst_registered_from && date && date >= String(d.settings.gst_registered_from).slice(0, 10));

  // ===================================================================
  // The Sales screen
  // ===================================================================
  RB.screens.sales = async (body, arg) => {
    if (arg === 'new') return saleForm(body);
    if (arg && /^\d+$/.test(arg)) return RB.invoices.window(body, Number(arg), 'sales');
    const tools = $('#page-tools');
    if (tools) tools.innerHTML = RB.has('sales.add') ? '<a class="btn primary" href="#/sales/new">+ New sale</a>' : '';
    const list = [['list', 'Sales', listTab], ['returns', 'Returns', returnsTab]];
    if (money()) list.push(['summary', 'Sales summary', summaryTab]);
    body.innerHTML = '<div class="tabs">' + list.map(([k, t]) => '<button data-tab="' + k + '">' + t + '</button>').join('') + '</div><div id="tab-body"></div>';
    const show = async (k) => {
      SA.tab = k;
      $$('.tabs button', body).forEach((b) => b.classList.toggle('on', b.dataset.tab === k));
      const tb = $('#tab-body', body); tb.innerHTML = '<p class="muted">Loading…</p>';
      try { await list.find((x) => x[0] === k)[2](tb); } catch (e) { tb.innerHTML = '<div class="msg error">' + esc(e.message) + '</div>'; }
    };
    $$('.tabs button', body).forEach((b) => b.addEventListener('click', () => show(b.dataset.tab)));
    show(SA.tab && list.some((x) => x[0] === SA.tab) ? SA.tab : 'list');
  };

  SA.dateBar = (tb, id, from, to) => '<div class="row" style="align-items:flex-end"><div class="field" style="flex:0 1 180px"><label for="' + id + '-from">From</label><input type="date" id="' + id + '-from" value="' + from + '"></div>' +
    '<div class="field" style="flex:0 1 180px"><label for="' + id + '-to">To</label><input type="date" id="' + id + '-to" value="' + to + '"></div>' +
    '<div class="field" style="flex:0 1 auto"><button id="' + id + '-go">Show</button> <button id="' + id + '-xls">Download to Excel</button></div></div>';

  // ---------- sales list (shared with the Invoices screen) ----------
  const FILTERS = [['all', 'All'], ['open', 'Owed'], ['overdue', 'Overdue'], ['credit', 'On credit'], ['cancelled', 'Cancelled']];
  SA.listTab = listTab;
  async function listTab(tb, base) {
    base = base || 'sales';
    tb.innerHTML = SA.dateBar(tb, 'sl', monthStart(), RB.today()) +
      '<div class="actions" style="margin:0 0 .75rem">' + FILTERS.map(([k, t]) => '<button data-f="' + k + '"' + (k === (SA.filter || 'all') ? ' class="primary"' : '') + '>' + t + '</button>').join('') + '</div>' +
      '<p class="muted">Tap an invoice to open, print or share it, take a return, or record a payment.</p><div id="sl-grid"></div>';
    let grid;
    const apply = (k) => {
      SA.filter = k;
      $$('[data-f]', tb).forEach((b) => b.classList.toggle('primary', b.dataset.f === k));
      const f = { all: null, open: (r) => r.status === 'open', overdue: (r) => r.overdue_days > 0, credit: (r) => r.payment_mode === 'credit',
        cancelled: (r) => r.status === 'cancelled' }[k];
      if (f) grid.setFilter(f); else grid.clearFilter();
    };
    const load = async () => {
      const rows = await RB.rpc('rb_sales_list', { p_from: $('#sl-from', tb).value || null, p_to: $('#sl-to', tb).value || null });
      const cols = [
        { title: 'Invoice', field: 'invoice_no', width: 190, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
        { title: 'Date', field: 'invoice_date', width: 115, formatter: (c) => RB.fmtDate(c.getValue()) },
        { title: 'Customer', field: 'customer_name', minWidth: 170 },
        { title: 'Type', field: 'doc_type', width: 110, formatter: (c) => esc(SA.DOC[c.getValue()]) },
        { title: 'How paid', field: 'payment_mode', width: 110, formatter: (c) => esc(SA.MODES[c.getValue()] || c.getValue()) },
        { title: 'Items', field: 'items', minWidth: 220 },
      ];
      if (money()) cols.push(
        { title: 'Total', field: 'total_paise', hozAlign: 'right', formatter: (c) => amt(c.getValue()), headerFilter: false },
        { title: 'Owed', field: 'outstanding_paise', hozAlign: 'right', formatter: (c) => (c.getValue() > 0 ? RB.rupees(c.getValue()) : ''), headerFilter: false });
      if (rows.some((r) => r.cost_paise != null)) cols.push(
        { title: 'Cost', field: 'cost_paise', hozAlign: 'right', formatter: (c) => amt(c.getValue()), headerFilter: false });
      cols.push(
        { title: 'Status', field: 'status', width: 120, formatter: (c) => RB.badge(SA.STATUS_BADGE[c.getValue()], SA.STATUS[c.getValue()]) },
        { title: 'Overdue (days)', field: 'overdue_days', hozAlign: 'right', headerFilter: false, formatter: (c) => (c.getValue() > 0 ? '<span class="diff">' + c.getValue() + '</span>' : '') },
        { title: 'By', field: 'entered_by_name', width: 110 });
      grid = RB.grid($('#sl-grid', tb), cols, rows);
      grid.on('tableBuilt', () => apply(SA.filter || 'all'));
      grid.on('rowClick', (e, row) => { location.hash = '#/' + base + '/' + row.getData().id; });
    };
    $$('[data-f]', tb).forEach((b) => b.addEventListener('click', () => grid && apply(b.dataset.f)));
    on(tb, '#sl-go', () => load().catch((e) => RB.toast(e.message, true)));
    on(tb, '#sl-xls', () => grid && RB.downloadExcel(grid, 'Sales'));
    await load();
  }

  // ---------- returns ----------
  async function returnsTab(tb) {
    const rows = await RB.rpc('rb_sales_returns_list');
    tb.innerHTML = '<div class="actions" style="margin:0 0 .75rem"><button id="rt-xls">Download to Excel</button></div>' +
      '<p class="muted">Goods customers brought back. A return made by Staff or Sales waits here until a Manager, the Accountant, the FC or a Director approves it; ' +
      'then its credit note is numbered and the books, stock and the customer balance are updated. To take a new return, open the invoice.</p><div id="rt-grid"></div>';
    const cols = [
      { title: 'Credit note', field: 'return_no', width: 180, formatter: (c) => esc(c.getValue() || '(not yet numbered)') + RB.demoBadge(c.getRow().getData()) },
      { title: 'Date', field: 'return_date', width: 115, formatter: (c) => RB.fmtDate(c.getValue()) },
      { title: 'Invoice', field: 'invoice_no', width: 180 },
      { title: 'Customer', field: 'customer_name', minWidth: 160 },
      { title: 'Items', field: 'items', minWidth: 200 },
      { title: 'Goods', field: 'condition', width: 130, formatter: (c) => (c.getValue() === 'restock' ? 'Back on the shelf' : 'Thrown away') },
      { title: 'Reason', field: 'reason', minWidth: 160 },
    ];
    if (money()) cols.push({ title: 'Value', field: 'total_paise', hozAlign: 'right', formatter: (c) => amt(c.getValue()), headerFilter: false });
    cols.push({ title: 'Status', field: 'status', width: 170, formatter: (c) => RB.badge(SA.RET_BADGE[c.getValue()], SA.RET_STATUS[c.getValue()]) },
      { title: 'By', field: 'entered_by_name', width: 110 });
    const grid = RB.grid($('#rt-grid', tb), cols, rows);
    grid.on('rowClick', (e, row) => SA.returnModal(row.getData(), () => returnsTab(tb)));
    on(tb, '#rt-xls', () => RB.downloadExcel(grid, 'Sales returns'));
  }

  SA.returnModal = (r, done) => {
    const m = RB.modal('<h2>' + esc(r.return_no || 'Return on ' + r.invoice_no) + RB.demoBadge(r) + '</h2><div class="m-msg"></div>' +
      '<p>' + esc(r.customer_name) + ' · ' + RB.fmtDate(r.return_date) + ' · invoice ' + esc(r.invoice_no) + '</p>' +
      '<p>' + esc(r.items || '') + '<br><span class="muted">' + (r.condition === 'restock' ? 'Goods go back on the shelf.' : 'Goods are thrown away (written off).') +
      ' Reason: ' + esc(r.reason || '') + '</span></p>' +
      (r.total_paise != null ? '<p>Credit to the customer: <b>' + RB.rupees(r.total_paise) + '</b></p>' : '') +
      '<p>' + RB.badge(SA.RET_BADGE[r.status], SA.RET_STATUS[r.status]) + (r.refused_reason ? ' ' + esc(r.refused_reason) : '') + '</p>' +
      '<div class="actions">' +
      (r.can_approve ? '<button class="primary" id="rm-ok">Approve and post</button><button class="danger" id="rm-no">Refuse</button>' : '') +
      (r.status === 'posted' && RB.has('power.reverse_entries') ? '<button class="danger" id="rm-rev">Reverse</button>' : '') +
      '<a class="btn" href="#/sales/' + r.sale_id + '">Open the invoice</a><button data-close>Close</button></div>');
    m.el.querySelector('a.btn').addEventListener('click', () => m.close());
    on(m.el, '#rm-ok', async () => {
      try { await RB.rpc('rb_approve_sales_return', { p_id: r.id }); RB.toast('Return approved and posted'); m.close(); done(); } catch (e) { RB.modalMsg(m, e.message); }
    });
    on(m.el, '#rm-no', () => { m.close(); SA.reasonModal('Refuse this return', 'Nothing is posted. Say why, so the person who entered it knows.',
      (why) => RB.rpc('rb_refuse_sales_return', { p_id: r.id, p_reason: why }), done); });
    on(m.el, '#rm-rev', () => { m.close(); SA.reverseModal('Reverse ' + (r.return_no || 'this return'),
      'The credit note is undone in the books: the customer owes the amount again and the stock movement is reversed.',
      (dt, why) => RB.rpc('rb_reverse_sales_return', { p_id: r.id, p_date: dt, p_reason: why }), done); });
  };

  // ---------- sales summary ----------
  async function summaryTab(tb) {
    tb.innerHTML = SA.dateBar(tb, 'ss', monthStart(), RB.today()) +
      '<div class="switch" id="ss-by"><button data-by="day" class="on">By day</button><button data-by="product">By product</button><button data-by="kind">By customer type</button></div>' +
      '<p class="muted">Net sales are after discount and before GST. Returns show as minus figures on the day they came back.' +
      (RB.has('sales.margin') || RB.has('invoices.margin') || RB.has('accounts.view') ? ' Cost is the weighted average cost of the stock sold.' : '') + '</p><div id="ss-grid"></div>';
    let rows = [], grid, by = 'day';
    const draw = () => {
      const key = { day: (r) => r.sale_date, product: (r) => r.item_name + (r.pack_name ? ', ' + r.pack_name : ' (loose)'), kind: (r) => (r.customer_kind === 'trader' ? 'Trader' : 'Retail') + ' · ' + SA.CHANNELS[r.channel] }[by];
      const g = {};
      rows.forEach((r) => {
        const k = key(r);
        const x = g[k] || (g[k] = { k, qty: 0, packs: 0, unit: r.base_unit, invoices: 0, gross: 0, disc: 0, net: 0, gst: 0, cost: null, margin: null, is_demo: false });
        x.qty += Number(r.qty_base || 0); x.packs += Number(r.packs || 0); x.invoices += r.invoices; x.gross += Number(r.gross_paise); x.disc += Number(r.discount_paise);
        x.net += Number(r.net_paise); x.gst += Number(r.gst_paise); x.is_demo = x.is_demo || r.is_demo;
        if (r.cost_paise != null) { x.cost = (x.cost || 0) + Number(r.cost_paise); x.margin = (x.margin || 0) + Number(r.margin_paise); }
      });
      const data = Object.values(g).sort((a, b) => (a.k < b.k ? -1 : 1));
      const cols = [{ title: by === 'day' ? 'Date' : by === 'product' ? 'Product' : 'Customer type', field: 'k', minWidth: 200,
        formatter: (c) => (by === 'day' ? RB.fmtDate(c.getValue()) : esc(c.getValue())) + RB.demoBadge(c.getRow().getData()) }];
      if (by === 'product') cols.push({ title: 'Packs', field: 'packs', hozAlign: 'right', headerFilter: false, formatter: (c) => (c.getValue() ? trim(c.getValue()) : '') },
        { title: 'Quantity', field: 'qty', hozAlign: 'right', headerFilter: false, formatter: (c) => SA.q(c.getValue(), c.getRow().getData().unit) });
      else cols.push({ title: 'Invoices', field: 'invoices', hozAlign: 'right', headerFilter: false });
      cols.push({ title: 'Gross', field: 'gross', hozAlign: 'right', headerFilter: false, formatter: (c) => RB.rupees(c.getValue()), bottomCalc: 'sum', bottomCalcFormatter: (c) => RB.rupees(c.getValue()) },
        { title: 'Discount', field: 'disc', hozAlign: 'right', headerFilter: false, formatter: (c) => RB.rupees(c.getValue()), bottomCalc: 'sum', bottomCalcFormatter: (c) => RB.rupees(c.getValue()) },
        { title: 'Net sales', field: 'net', hozAlign: 'right', headerFilter: false, formatter: (c) => '<b>' + RB.rupees(c.getValue()) + '</b>', bottomCalc: 'sum', bottomCalcFormatter: (c) => RB.rupees(c.getValue()) },
        { title: 'GST', field: 'gst', hozAlign: 'right', headerFilter: false, formatter: (c) => RB.rupees(c.getValue()), bottomCalc: 'sum', bottomCalcFormatter: (c) => RB.rupees(c.getValue()) });
      if (data.some((x) => x.cost != null)) cols.push(
        { title: 'Cost', field: 'cost', hozAlign: 'right', headerFilter: false, formatter: (c) => amt(c.getValue()), bottomCalc: 'sum', bottomCalcFormatter: (c) => RB.rupees(c.getValue()) },
        { title: 'Margin', field: 'margin', hozAlign: 'right', headerFilter: false, formatter: (c) => amt(c.getValue()), bottomCalc: 'sum', bottomCalcFormatter: (c) => RB.rupees(c.getValue()) },
        { title: 'Margin %', field: 'margin', hozAlign: 'right', headerFilter: false, formatter: (c) => { const x = c.getRow().getData(); return x.net ? trim(Math.round(1000 * x.margin / x.net) / 10) + '%' : ''; } });
      grid = RB.grid($('#ss-grid', tb), cols, data);
    };
    const load = async () => { rows = await RB.rpc('rb_sales_summary', { p_from: $('#ss-from', tb).value, p_to: $('#ss-to', tb).value }); draw(); };
    $$('#ss-by button', tb).forEach((b) => b.addEventListener('click', () => {
      by = b.dataset.by; $$('#ss-by button', tb).forEach((x) => x.classList.toggle('on', x === b)); draw();
    }));
    on(tb, '#ss-go', () => load().catch((e) => RB.toast(e.message, true)));
    on(tb, '#ss-xls', () => grid && RB.downloadExcel(grid, 'Sales summary'));
    await load();
  }

  // ===================================================================
  // New sale
  // ===================================================================
  async function saleForm(body) {
    if (!RB.has('sales.add')) { body.innerHTML = '<div class="msg error">You do not have the right to make sales.</div>'; return; }
    const back = $('.page-head .back'); if (back) { back.href = '#/sales'; back.textContent = '‹ Sales'; }
    const h1 = $('.page-head h1'); if (h1) h1.textContent = 'New sale';
    const d = await lists();
    const canRate = RB.has('sales.edit'), canOverride = RB.has('sales.approve');
    const walkIn = d.customers.find((c) => c.is_walk_in);
    const custOptions = () => d.customers.filter((c) => c.is_active).sort((a, b) => (b.is_walk_in - a.is_walk_in) || a.name.localeCompare(b.name))
      .map((c) => [c.id, c.name + (c.kind === 'trader' ? ' (trader)' : '')]);
    body.innerHTML = '<div class="card"><div class="m-msg" id="sf-msg"></div>' +
      '<div class="row">' + RB.field('sf-date', 'Date', '<input type="date" id="sf-date" value="' + RB.today() + '">', null, true) +
      '<div class="field" style="flex:2 1 260px"><label for="sf-cust">Customer <span class="req">*</span></label><div style="display:flex;gap:.5rem">' +
      RB.sel('sf-cust', custOptions(), walkIn ? walkIn.id : '') + (RB.has('customers.add') ? '<button type="button" id="sf-addc" title="Add a new customer">+ New</button>' : '') + '</div>' +
      '<div class="hint" id="sf-custinfo"></div></div>' +
      RB.field('sf-chan', 'Price list', RB.sel('sf-chan', Object.entries(SA.CHANNELS), 'retail')) + '</div>' +
      '<div class="row">' + RB.field('sf-doc', 'Document', RB.sel('sf-doc', [['invoice', 'Invoice (no GST)']], 'invoice'), '<span id="sf-dochint"></span>') +
      '<div class="field" id="sf-hsnbox"><label>&nbsp;</label><label class="check"><input type="checkbox" id="sf-hsn" checked> Show HSN codes on the invoice</label></div></div>' +
      '</div>' +
      '<div class="card"><h2>Items</h2><div class="grid-wrap"><table class="ticks lines" id="sf-lines"><thead><tr><th>Item</th><th>Pack</th><th>Quantity</th><th>Price ₹</th><th>Discount</th><th style="text-align:right">Amount</th><th></th></tr></thead><tbody></tbody></table></div>' +
      '<div class="actions"><button type="button" id="sf-add">+ Add a line</button>' +
      '<span style="display:inline-flex;gap:.4rem;align-items:center">Whole bill discount <input id="sf-billpct" inputmode="decimal" style="width:70px" placeholder="%"> <button type="button" id="sf-billgo">Apply</button></span></div>' +
      (canRate ? '' : '<p class="muted">Prices come from Masters. A Manager can change a price on a sale.</p>') +
      '<div id="sf-totals" class="totals"></div></div>' +
      '<div class="card"><h2>Payment</h2><div class="row">' +
      RB.field('sf-mode', 'How paid', RB.sel('sf-mode', Object.entries(SA.MODES), 'cash'), null, true) +
      RB.field('sf-paid', 'Amount paid now (₹)', RB.inp('sf-paid', '', ' inputmode="decimal"'), 'Leave blank when the whole bill is paid. Less than the bill leaves the rest owed (not for walk-in).') +
      RB.field('sf-ref', 'Reference', RB.inp('sf-ref', '', ' placeholder="UPI or bank ref"')) + '</div>' +
      (canOverride ? '<label class="check"><input type="checkbox" id="sf-over"> Allow this sale over the customer\'s credit limit</label>' : '') +
      RB.field('sf-note', 'Note on the invoice', RB.inp('sf-note', '')) +
      '<div class="actions"><button class="primary" id="sf-save">Save and open the invoice</button><a class="btn" href="#/sales">Cancel</a></div></div>';

    const cust = () => d.customers.find((c) => c.id === Number($('#sf-cust', body).value));
    let lines = [];
    const itemOptions = [['', 'Choose…']].concat(d.sellable.map((i) => [i.id, i.name + (i.kind === 'byproduct' ? ' (by-product)' : '')]));
    const blankLine = () => ({ item_id: '', pack_id: '', packs: '', qty: '', unit: '', rate: '', list: null, dpct: '', damt: '' });

    // GST choice follows the date: a Tax Invoice only once the firm is registered.
    const syncDoc = () => {
      const date = $('#sf-date', body).value, ok = gstOk(d, date), sel = $('#sf-doc', body), was = sel.value;
      sel.innerHTML = [['invoice', 'Invoice (no GST)']].concat(ok ? [['tax_invoice', 'Tax Invoice (with GST)']] : [])
        .map(([k, t]) => '<option value="' + k + '"' + ((ok && (was === 'tax_invoice' || !SA.docTouched)) && k === 'tax_invoice' ? ' selected' : '') + '>' + t + '</option>').join('');
      $('#sf-dochint', body).textContent = ok ? 'GST is charged on a Tax Invoice' + (d.settings.sale_prices_include_gst ? ' (prices include GST).' : ' (added on top of prices).')
        : 'The firm is not GST registered on this date, so no GST is charged.';
      $('#sf-hsnbox', body).classList.toggle('hidden', sel.value !== 'tax_invoice');
      draw();
    };
    const syncCust = () => {
      const c = cust(); if (!c) return;
      $('#sf-chan', body).value = c.kind === 'trader' ? 'trader' : ($('#sf-chan', body).value === 'trader' ? 'retail' : $('#sf-chan', body).value);
      $('#sf-chan', body).querySelector('option[value=trader]').disabled = c.kind !== 'trader';
      const bits = [];
      if (c.is_walk_in) bits.push('Walk-in: paid in full at the counter.');
      if (c.phone) bits.push(esc(c.phone));
      if (money() && c.credit_limit_paise != null) bits.push('Credit limit ' + RB.rupees(c.credit_limit_paise) + (c.credit_days ? ', ' + c.credit_days + ' days' : ''));
      $('#sf-custinfo', body).innerHTML = bits.join(' · ');
      if (c.is_walk_in && $('#sf-mode', body).value === 'credit') $('#sf-mode', body).value = 'cash';
      reprice();
    };
    const reprice = () => {
      const ch = $('#sf-chan', body).value;
      lines.forEach((l) => { if (!l.item_id) return; const lp = listPrice(d, l.item_id, l.pack_id, ch); if (l.rate === '' || l.rate === RB.fromPaise(l.list)) l.rate = RB.fromPaise(lp); l.list = lp; });
      draw();
    };
    // Work out a line the same way the database does (so the screen and the invoice agree).
    const calc = (l, docType) => {
      const it = d.item[l.item_id]; if (!it) return null;
      let rate; try { rate = RB.toPaise(l.rate); } catch (e) { return { error: e.message }; }
      if (rate == null) return { error: 'no price' };
      let gross;
      if (l.pack_id) { const n = Number(l.packs) || 0; gross = Math.round(n * rate); }
      else {
        const u = d.unit[l.unit || it.base_unit] || {}, base = d.unit[it.base_unit] || {};
        const qBase = (Number(l.qty) || 0) * (u.to_base || 1) / (base.to_base || 1);
        gross = Math.round(qBase * rate / (base.dimension === 'mass' || base.dimension === 'volume' ? 1000 : 1));
      }
      let disc = 0;
      if (String(l.dpct).trim() !== '') disc = Math.round(gross * (Number(l.dpct) || 0) / 100);
      else { try { disc = RB.toPaise(l.damt) || 0; } catch (e) { disc = 0; } }
      const net = gross - disc;
      let gst = 0, taxable = net;
      if (docType === 'tax_invoice' && it.gst_rate != null) {
        const r = Number(it.gst_rate);
        if (d.settings.sale_prices_include_gst) { taxable = Math.round(net * 100 / (100 + r)); gst = net - taxable; }
        else { gst = Math.round(taxable * r / 100); }
      }
      return { gross, disc, taxable, gst, total: taxable + gst };
    };
    const unitOpts = (base) => (base === 'g' ? ['kg', 'g'] : base === 'ml' ? ['l', 'ml'] : [base]);
    const draw = () => {
      const docType = $('#sf-doc', body).value, tbody = $('#sf-lines tbody', body);
      tbody.innerHTML = lines.map((l, i) => {
        const it = d.item[l.item_id], packs = it ? d.packsOf(it.id) : [];
        const packOpts = packs.map((p) => [p.id, p.name + ' (' + SA.q(p.net_qty, it.base_unit) + ')']).concat(it && it.sells_by !== 'pack' ? [['', 'Loose' + (it.sells_by === 'piece' ? ' (pieces)' : ' by weight')]] : []);
        const c = calc(l, docType);
        return '<tr data-i="' + i + '"><td style="min-width:180px">' + RB.sel('l-item-' + i, itemOptions, l.item_id, ' data-k="item_id"') + '</td>' +
          '<td style="min-width:140px">' + (it ? RB.sel('l-pack-' + i, packOpts, l.pack_id, ' data-k="pack_id"') : '') + '</td>' +
          '<td style="min-width:130px">' + (!it ? '' : l.pack_id ? '<input data-k="packs" inputmode="numeric" value="' + esc(l.packs) + '" placeholder="packs">' :
            '<div style="display:flex;gap:.3rem"><input data-k="qty" inputmode="decimal" value="' + esc(l.qty) + '" style="width:80px">' +
            RB.sel('l-unit-' + i, unitOpts(it.base_unit).map((u) => [u, u]), l.unit || unitOpts(it.base_unit)[0], ' data-k="unit"') + '</div>') + '</td>' +
          '<td style="min-width:110px">' + (it ? '<input data-k="rate" inputmode="decimal" value="' + esc(l.rate) + '"' + (canRate ? '' : ' disabled') + '>' +
            (!l.pack_id ? '<div class="hint">per ' + (it.sells_by === 'piece' ? 'piece' : it.base_unit === 'ml' ? 'litre' : 'kg') + '</div>' : '') +
            (l.list == null ? '<div class="diff">No price in Masters</div>' : '') : '') + '</td>' +
          '<td style="min-width:150px">' + (it ? '<div style="display:flex;gap:.3rem"><input data-k="dpct" inputmode="decimal" value="' + esc(l.dpct) + '" placeholder="%" style="width:60px">' +
            '<input data-k="damt" inputmode="decimal" value="' + esc(l.damt) + '" placeholder="₹" style="width:80px"' + (String(l.dpct).trim() !== '' ? ' disabled' : '') + '></div>' : '') + '</td>' +
          '<td style="text-align:right;white-space:nowrap">' + (c && !c.error ? RB.rupees(c.total) + (c.disc ? '<div class="hint">after ' + RB.rupees(c.disc) + ' off</div>' : '') : '') + '</td>' +
          '<td><button type="button" data-del="' + i + '" aria-label="Remove line">✕</button></td></tr>';
      }).join('');
      $$('[data-k]', tbody).forEach((el) => {
        const i = Number(el.closest('tr').dataset.i), k = el.dataset.k;
        el.addEventListener(el.tagName === 'SELECT' ? 'change' : 'input', () => {
          const l = lines[i]; l[k] = el.value;
          if (k === 'item_id') {
            const it = d.item[el.value], packs = it ? d.packsOf(it.id) : [];
            l.pack_id = it && (it.sells_by === 'pack' || packs.length) && packs[0] ? String(packs[0].id) : '';
            l.packs = l.pack_id ? '1' : ''; l.qty = ''; l.unit = it ? unitOpts(it.base_unit)[0] : '';
            l.list = it ? listPrice(d, it.id, l.pack_id, $('#sf-chan', body).value) : null; l.rate = RB.fromPaise(l.list);
            return draw();
          }
          if (k === 'pack_id') { l.list = listPrice(d, l.item_id, l.pack_id, $('#sf-chan', body).value); l.rate = RB.fromPaise(l.list); l.packs = l.pack_id ? '1' : ''; return draw(); }
          if (k === 'unit' || (k === 'dpct' && (el.value === '' || l.damt !== ''))) { if (k === 'dpct') l.damt = ''; return draw(); }
          totals(); const tr = el.closest('tr'), c = calc(l, $('#sf-doc', body).value);
          tr.children[5].innerHTML = c && !c.error ? RB.rupees(c.total) + (c.disc ? '<div class="hint">after ' + RB.rupees(c.disc) + ' off</div>' : '') : '';
          if (k === 'dpct') { const da = $('[data-k=damt]', tr); if (da) da.disabled = String(el.value).trim() !== ''; }
        });
      });
      $$('[data-del]', tbody).forEach((b) => b.addEventListener('click', () => { lines.splice(Number(b.dataset.del), 1); if (!lines.length) lines.push(blankLine()); draw(); }));
      totals();
    };
    const totals = () => {
      const docType = $('#sf-doc', body).value; let g = 0, ds = 0, tx = 0, gst = 0, tot = 0;
      lines.forEach((l) => { const c = calc(l, docType); if (c && !c.error) { g += c.gross; ds += c.disc; tx += c.taxable; gst += c.gst; tot += c.total; } });
      const c = cust(), intra = !c || !(c.state_code || (c.gstin || '').slice(0, 2)) || (c.state_code || (c.gstin || '').slice(0, 2)) === d.settings.state_code;
      $('#sf-totals', body).innerHTML = '<table class="sum"><tr><td>Price before discount</td><td>' + RB.rupees(g) + '</td></tr>' +
        (ds ? '<tr><td>Discount</td><td>− ' + RB.rupees(ds) + '</td></tr>' : '') +
        (docType === 'tax_invoice' ? '<tr><td>Taxable value</td><td>' + RB.rupees(tx) + '</td></tr><tr><td>' + (intra ? 'CGST + SGST' : 'IGST') + '</td><td>' + RB.rupees(gst) + '</td></tr>' : '') +
        '<tr class="grand"><td>To collect</td><td>' + RB.rupees(tot) + '</td></tr></table>';
    };
    lines.push(blankLine());
    on(body, '#sf-add', () => { lines.push(blankLine()); draw(); const sels = $$('#sf-lines [data-k=item_id]', body); if (sels.length) sels[sels.length - 1].focus(); });
    on(body, '#sf-billgo', () => {
      const v = $('#sf-billpct', body).value.trim();
      if (v === '' || !(Number(v) >= 0 && Number(v) <= 100)) return RB.toast('Enter a discount % between 0 and 100.', true);
      lines.forEach((l) => { if (l.item_id) { l.dpct = v; l.damt = ''; } }); draw();
    });
    on(body, '#sf-date', syncDoc, 'change');
    on(body, '#sf-doc', () => { SA.docTouched = true; $('#sf-hsnbox', body).classList.toggle('hidden', $('#sf-doc', body).value !== 'tax_invoice'); draw(); }, 'change');
    on(body, '#sf-cust', syncCust, 'change');
    on(body, '#sf-chan', reprice, 'change');
    on(body, '#sf-mode', () => { if ($('#sf-mode', body).value === 'credit') $('#sf-paid', body).value = ''; }, 'change');
    on(body, '#sf-addc', () => RB.masters.customerModal(null, async (newId) => {
      d.customers = await RB.select('customers', '*', (x) => x.order('code'));
      $('#sf-cust', body).innerHTML = custOptions().map(([k, t]) => '<option value="' + k + '"' + (String(k) === String(newId) ? ' selected' : '') + '>' + esc(t) + '</option>').join('');
      syncCust();
    }));
    SA.docTouched = false;
    syncDoc(); syncCust();

    const btn = $('#sf-save', body);
    btn.addEventListener('click', async () => {
      const msg = $('#sf-msg', body); msg.innerHTML = '';
      try {
        const mode = $('#sf-mode', body).value, paid = $('#sf-paid', body).value;
        const out = lines.filter((l) => l.item_id).map((l) => {
          const o = { item_id: Number(l.item_id) };
          if (l.pack_id) { o.pack_id = Number(l.pack_id); o.packs = num(l.packs); } else { o.qty = num(l.qty); o.unit = l.unit || null; }
          const r = RB.toPaise(l.rate); if (r !== l.list) o.rate_paise = r;
          if (String(l.dpct).trim() !== '') o.discount_pct = num(l.dpct); else if (String(l.damt).trim() !== '') o.discount_paise = RB.toPaise(l.damt);
          return o;
        });
        btn.disabled = true;
        const res = await RB.rpc('rb_save_sale', { p: {
          customer_id: Number($('#sf-cust', body).value) || null, invoice_date: $('#sf-date', body).value, doc_type: $('#sf-doc', body).value,
          channel: $('#sf-chan', body).value, show_hsn: $('#sf-hsn', body).checked, payment_mode: mode,
          paid_paise: mode === 'credit' || paid.trim() === '' ? null : RB.toPaise(paid), payment_ref: $('#sf-ref', body).value,
          note: $('#sf-note', body).value, override_credit_limit: $('#sf-over', body) ? $('#sf-over', body).checked : false, lines: out } });
        RB.toast('Saved ' + res.invoice_no);
        location.hash = '#/sales/' + res.id;
      } catch (e) { btn.disabled = false; msg.innerHTML = '<div class="msg error">' + esc(e.message) + '</div>'; window.scrollTo(0, 0); }
    });
  }

  // ---------- small shared modals ----------
  SA.reasonModal = (title, explain, run, done) => {
    const m = RB.modal('<h2>' + esc(title) + '</h2><div class="m-msg"></div><p>' + explain + '</p>' +
      RB.field('rs-why', 'Reason', '<textarea id="rs-why"></textarea>', null, true) +
      '<div class="actions"><button class="primary" id="rs-go">Confirm</button><button data-close>Back</button></div>');
    $('#rs-go', m.el).addEventListener('click', async () => {
      try { await run($('#rs-why', m.el).value); RB.toast('Done'); m.close(); if (done) done(); } catch (e) { RB.modalMsg(m, e.message); }
    });
  };
  SA.reverseModal = (title, explain, run, done, label) => {
    const m = RB.modal('<h2>' + esc(title) + '</h2><div class="m-msg"></div><p>' + explain + '</p>' +
      '<div class="row">' + RB.field('rv-date', 'Date', '<input type="date" id="rv-date" value="' + RB.today() + '">') + '</div>' +
      RB.field('rv-why', 'Reason', '<textarea id="rv-why"></textarea>', null, true) +
      '<div class="actions"><button class="danger" id="rv-go">' + esc(label || 'Reverse') + '</button><button data-close>Back</button></div>');
    $('#rv-go', m.el).addEventListener('click', async () => {
      try { await run($('#rv-date', m.el).value, $('#rv-why', m.el).value); RB.toast('Done'); m.close(); if (done) done(); } catch (e) { RB.modalMsg(m, e.message); }
    });
  };
})();
