// =====================================================================
// RUCHI BUDS APP · purchases.js · Version 1.3 · 27-Nov-2026 (1.3: send orders and payment advice by WhatsApp or email)
// Module 3 screen "Purchases": the Purchase window (order, receive, bill,
// matched side by side), direct purchases with no PO, every difference
// with Accept or Reject, returns, supplier payments, supplier balances and
// ledger, the open-differences list and the purchase reports.
// =====================================================================
(function () {
  'use strict';
  const RB = window.RB, $ = RB.$, $$ = RB.$$, esc = RB.esc;
  const P = (RB.purchases = {});

  const STATUS = { ordered: 'Ordered', part_received: 'Part received', received: 'Received', billed: 'Billed', paid: 'Paid',
    awaiting_approval: 'Waiting for approval', refused: 'Refused', cancelled: 'Cancelled' };
  const STATUS_BADGE = { ordered: 'invited', part_received: 'invited', received: 'invited', billed: 'invited', paid: 'active',
    awaiting_approval: 'protected', refused: 'inactive', cancelled: 'inactive' };
  const MODES = { credit: 'Credit (pay later)', cash: 'Cash', upi: 'UPI', bank: 'Bank' };
  const KIND = { short: 'Short', excess: 'Excess', damaged: 'Damaged', rate: 'Rate', tax: 'Tax' };
  const STAGE = { receipt: 'at delivery', bill: 'on the bill' };
  const ACTIONS = { accept: 'Accept', return: 'Return the goods', debit_note: 'Debit note to the supplier',
    await_delivery: 'Keep open for a later delivery', correct_rate: 'Correct the rate to the PO rate' };
  const REASONS = ['Daily fish catch', 'Small cash buy', 'Urgent top-up', 'Supplier at the door'];

  const amt = (p) => (p == null || Number(p) === 0 ? '' : RB.rupees(p));
  const num = (v) => { const s = String(v == null ? '' : v).replace(/[,\s]/g, ''); if (s === '') return null; const n = Number(s); if (!isFinite(n)) throw new Error('"' + v + '" is not a number.'); return n; };
  const q = (n) => (n == null ? '' : Number(n).toLocaleString('en-IN', { maximumFractionDigits: 3 }));
  const statusBadge = (s) => RB.badge(STATUS_BADGE[s] || 'invited', STATUS[s] || s);
  const ref = (p) => p.po_no || p.bill_no || ('#' + p.id);
  const lineAmt = (qty, rate) => Math.round((Number(qty) || 0) * (Number(rate) || 0));

  // Lists the forms need.
  async function lists() {
    const d = await RB.masters.load(['items', 'units', 'suppliers', 'departments']);
    d.buyItems = d.items.filter((i) => (i.kind === 'raw' || i.kind === 'packaging') && i.is_active);
    d.item = Object.fromEntries(d.items.map((i) => [i.id, i]));
    d.unit = Object.fromEntries(d.units.map((u) => [u.code, u]));
    d.sup = Object.fromEntries(d.suppliers.map((s) => [s.id, s]));
    // The unit an item is usually bought in, if it can be converted to the stock unit (a "box" cannot).
    d.unitOf = (it) => {
      if (!it) return null;
      const bu = d.unit[it.buy_unit], base = d.unit[it.base_unit];
      return bu && base && bu.dimension === base.dimension ? it.buy_unit : it.base_unit;
    };
    d.unitsFor = (itemId) => {
      const it = d.item[itemId]; if (!it) return d.units;
      const dim = (d.unit[it.base_unit] || {}).dimension;
      return d.units.filter((u) => u.dimension === dim);
    };
    try { d.settings = await RB.select('app_settings', 'direct_purchase_approval_limit_paise,gstin', (x) => x.eq('id', 1).single()); } catch (e) { d.settings = {}; }
    return d;
  }

  // Supplier picker with an "Add new" button (opens the shared supplier form).
  function supplierPicker(d, id, val, dis) {
    return '<div class="field"><label for="' + id + '">Supplier <span class="req">*</span></label><div style="display:flex;gap:.5rem">' +
      RB.sel(id, [['', 'Choose…']].concat(d.suppliers.filter((s) => s.is_active || s.id === val).map((s) => [s.id, s.name + (s.usually_no_bill ? ' (no bill)' : '')])), val, dis) +
      (RB.has('suppliers.add') && !dis ? '<button type="button" data-addsup="' + id + '" title="Add a new supplier">+ New</button>' : '') + '</div></div>';
  }
  function wireSupplierAdd(m, d, onAdded) {
    $$('[data-addsup]', m.el).forEach((b) => b.addEventListener('click', () => {
      RB.masters.supplierModal(null, async (newId) => {
        d.suppliers = await RB.select('suppliers', '*', (x) => x.order('code'));
        d.sup = Object.fromEntries(d.suppliers.map((s) => [s.id, s]));
        const sel = $('#' + b.dataset.addsup, m.el);
        sel.innerHTML = [['', 'Choose…']].concat(d.suppliers.filter((s) => s.is_active).map((s) => [s.id, s.name])).map(([k, t]) =>
          '<option value="' + esc(k) + '"' + (String(k) === String(newId) ? ' selected' : '') + '>' + esc(t) + '</option>').join('');
        if (onAdded) onAdded(newId);
      });
    }));
  }
  const deptOptions = (d) => d.departments.filter((x) => x.is_active && !x.merged_into).map((x) => [x.id, x.code + ' ' + x.name]);
  const defaultDept = (d) => { const k = d.departments.find((x) => x.code === 'CC001' && x.is_active); return k ? k.id : (d.departments[0] || {}).id; };

  // Shrink a photo to about 1280 px so it stays small in the database.
  P.photoToDataUrl = (file) => new Promise((resolve, reject) => {
    if (!file) return resolve(null);
    const img = new Image(), url = URL.createObjectURL(file);
    img.onload = () => {
      const k = Math.min(1, 1280 / Math.max(img.width, img.height));
      const c = document.createElement('canvas'); c.width = Math.round(img.width * k); c.height = Math.round(img.height * k);
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
      URL.revokeObjectURL(url);
      let out = c.toDataURL('image/jpeg', 0.6);
      if (out.length > 680000) out = c.toDataURL('image/jpeg', 0.4);
      resolve(out);
    };
    img.onerror = () => reject(new Error('That file is not a photo the app can read.'));
    img.src = url;
  });

  // ===================================================================
  // The Purchases screen
  // ===================================================================
  RB.screens.purchases = async (body, arg) => {
    if (arg && /^\d+$/.test(arg)) return purchaseWindow(body, Number(arg));
    const tools = $('#page-tools');
    if (tools) tools.innerHTML =
      (RB.has('purchases.add') ? '<button class="primary" id="pu-new">+ New order (PO)</button><button class="primary" id="pu-direct">+ Direct purchase (no PO)</button>' +
        '<button id="pu-pay">Pay a supplier</button>' : '');
    const on = (id, fn) => { const b = $(id); if (b) b.addEventListener('click', fn); };
    on('#pu-new', () => orderModal(null));
    on('#pu-direct', () => directModal(null));
    on('#pu-pay', () => payModal(null));
    const list = [['list', 'Purchases', listTab], ['diffs', 'Differences', diffsTab], ['payments', 'Payments', paymentsTab],
      ['balances', 'Supplier balances', balancesTab], ['reports', 'Reports', reportsTab]];
    body.innerHTML = '<div class="tabs">' + list.map(([k, t]) => '<button data-tab="' + k + '">' + t + '</button>').join('') + '</div><div id="tab-body"></div>';
    const show = async (k) => {
      P.tab = k;
      $$('.tabs button', body).forEach((b) => b.classList.toggle('on', b.dataset.tab === k));
      const tb = $('#tab-body', body); tb.innerHTML = '<p class="muted">Loading…</p>';
      try { await list.find((x) => x[0] === k)[2](tb); } catch (e) { tb.innerHTML = '<div class="msg error">' + esc(e.message) + '</div>'; }
    };
    $$('.tabs button', body).forEach((b) => b.addEventListener('click', () => show(b.dataset.tab)));
    show(P.tab && list.some((x) => x[0] === P.tab) ? P.tab : 'list');
  };
  const open = (id) => { location.hash = '#/purchases/' + id; };

  // ---------- list ----------
  const FILTERS = [['all', 'All'], ['open', 'Orders not yet billed'], ['direct', 'Direct purchases'], ['approval', 'Waiting for approval'],
    ['diffs', 'With differences'], ['unpaid', 'Unpaid']];
  async function listTab(tb) {
    const [rows, sups] = await Promise.all([
      RB.select('purchases', '*', (x) => x.order('id', { ascending: false })),
      RB.select('suppliers', 'id,name', (x) => x.order('name'))]);
    const grnNo = {};
    try { (await RB.select('purchase_grns', 'purchase_id,grn_no', (x) => x.order('id'))).forEach((g) => { if (!grnNo[g.purchase_id]) grnNo[g.purchase_id] = g.grn_no; }); } catch (e) { /* ignore */ }
    const sup = Object.fromEntries(sups.map((s) => [s.id, s.name]));
    const data = rows.map((p) => Object.assign({}, p, {
      ref: p.po_no || grnNo[p.id] || ('#' + p.id), date: p.po_date || p.purchase_date, supplier: sup[p.supplier_id] || '',
      type: p.is_direct ? 'Direct' + (p.no_supplier_bill ? ', no bill' : '') : 'Order', status_t: STATUS[p.status],
      owed: p.outstanding_paise, value: p.bill_posted_at ? p.bill_total_paise : (p.is_direct ? null : p.order_total_paise) }));
    tb.innerHTML = '<div class="actions" style="margin:0 0 .75rem">' + FILTERS.map(([k, t]) => '<button data-f="' + k + '"' + (k === (P.filter || 'all') ? ' class="primary"' : '') + '>' + t + '</button>').join('') +
      '<button id="pl-xls">Download to Excel</button></div>' +
      '<p class="muted">Tap a purchase to open its window: order, goods received and bill side by side, with every difference in red.</p><div id="pl-grid"></div>';
    const grid = RB.grid($('#pl-grid', tb), [
      { title: 'Reference', field: 'ref', width: 170, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
      { title: 'Date', field: 'date', width: 120, formatter: (c) => RB.fmtDate(c.getValue()) },
      { title: 'Supplier', field: 'supplier', minWidth: 200 },
      { title: 'Type', field: 'type', width: 140 },
      { title: 'Status', field: 'status_t', width: 170, formatter: (c) => statusBadge(c.getRow().getData().status) },
      { title: 'Value', field: 'value', hozAlign: 'right', formatter: (c) => amt(c.getValue()), headerFilter: false },
      { title: 'Owed', field: 'owed', hozAlign: 'right', formatter: (c) => amt(c.getValue()), headerFilter: false },
      { title: 'Differences', field: 'open_discrepancies', hozAlign: 'center', headerFilter: false,
        formatter: (c) => (c.getValue() ? '<span class="diff-count">' + c.getValue() + ' open</span>' : '') },
    ], data);
    const apply = (k) => {
      P.filter = k;
      $$('[data-f]', tb).forEach((b) => b.classList.toggle('primary', b.dataset.f === k));
      const f = { all: null, open: (r) => !r.is_direct && ['ordered', 'part_received', 'received'].includes(r.status), direct: (r) => r.is_direct,
        approval: (r) => r.status === 'awaiting_approval', diffs: (r) => r.open_discrepancies > 0, unpaid: (r) => r.outstanding_paise > 0 }[k];
      if (f) grid.setFilter(f); else grid.clearFilter();
    };
    grid.on('tableBuilt', () => apply(P.filter || 'all'));
    $$('[data-f]', tb).forEach((b) => b.addEventListener('click', () => apply(b.dataset.f)));
    grid.on('rowClick', (e, row) => open(row.getData().id));
    $('#pl-xls', tb).addEventListener('click', () => RB.downloadExcel(grid, 'Purchases'));
  }

  // ---------- open differences ----------
  async function diffsTab(tb) {
    const rows = await RB.rpc('rb_open_discrepancies');
    tb.innerHTML = '<p class="muted">Every difference between the order, the goods received and the bill, however small, until someone accepts or rejects it. ' +
      'A purchase with an open difference cannot be paid.</p><div class="actions" style="margin:0 0 .75rem"><button id="df-xls">Download to Excel</button></div><div id="df-grid"></div>';
    const grid = RB.grid($('#df-grid', tb), [
      { title: 'Purchase', field: 'purchase_ref', width: 170, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
      { title: 'Supplier', field: 'supplier_name', minWidth: 180 },
      { title: 'Item', field: 'item_name', minWidth: 160 },
      { title: 'Type', field: 'kind', width: 100, formatter: (c) => '<span class="diff">' + esc(KIND[c.getValue()]) + '</span>' },
      { title: 'Where', field: 'stage', width: 120, formatter: (c) => STAGE[c.getValue()] },
      { title: 'What', field: 'explain', minWidth: 260 },
      { title: 'Amount', field: 'amount_paise', hozAlign: 'right', formatter: (c) => RB.rupees(Math.abs(c.getValue())), headerFilter: false },
      { title: 'Age (days)', field: 'age_days', hozAlign: 'right', headerFilter: false },
    ], rows.map((r) => Object.assign({}, r, { amount_abs: Math.abs(r.amount_paise) })));
    grid.on('rowClick', (e, row) => open(row.getData().purchase_id));
    $('#df-xls', tb).addEventListener('click', () => RB.downloadExcel(grid, 'Open purchase differences'));
  }

  // ---------- payments ----------
  async function paymentsTab(tb) {
    const [rows, sups] = await Promise.all([
      RB.select('supplier_payments', '*', (x) => x.order('id', { ascending: false })),
      RB.select('suppliers', 'id,name', (x) => x.order('name'))]);
    const alloc = await RB.select('payment_allocations', 'payment_id,amount_paise');
    const used = {}; alloc.forEach((a) => { used[a.payment_id] = (used[a.payment_id] || 0) + Number(a.amount_paise); });
    const sup = Object.fromEntries(sups.map((s) => [s.id, s.name]));
    const data = rows.map((r) => Object.assign({}, r, { supplier: sup[r.supplier_id], mode_t: MODES[r.mode],
      on_account: r.status === 'posted' ? Number(r.amount_paise) - (used[r.id] || 0) : 0 }));
    tb.innerHTML = '<div class="actions" style="margin:0 0 .75rem"><button id="py-xls">Download to Excel</button></div>' +
      '<p class="muted">"On account" is paid but not yet set against a bill (an advance). Tap a payment to set it against bills or to reverse it.</p><div id="py-grid"></div>';
    const grid = RB.grid($('#py-grid', tb), [
      { title: 'Payment', field: 'payment_no', width: 180, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
      { title: 'Date', field: 'pay_date', width: 120, formatter: (c) => RB.fmtDate(c.getValue()) },
      { title: 'Supplier', field: 'supplier', minWidth: 200 },
      { title: 'How', field: 'mode_t', width: 90 },
      { title: 'Reference', field: 'reference' },
      { title: 'Amount', field: 'amount_paise', hozAlign: 'right', formatter: (c) => RB.rupees(c.getValue()), headerFilter: false },
      { title: 'On account', field: 'on_account', hozAlign: 'right', formatter: (c) => amt(c.getValue()), headerFilter: false },
      { title: 'Status', field: 'status', width: 110, formatter: (c) => c.getValue() === 'posted' ? RB.badge('active', 'Posted') : RB.badge('inactive', 'Reversed') },
    ], data);
    grid.on('rowClick', (e, row) => paymentModal(row.getData(), () => paymentsTab(tb)));
    $('#py-xls', tb).addEventListener('click', () => RB.downloadExcel(grid, 'Supplier payments'));
  }

  function paymentModal(pay, done) {
    const m = RB.modal('<h2>' + esc(pay.payment_no) + RB.demoBadge(pay) + '</h2><div class="m-msg"></div>' +
      '<p>' + esc(pay.supplier) + ' · ' + RB.fmtDate(pay.pay_date) + ' · ' + esc(MODES[pay.mode]) + ' · <b>' + RB.rupees(pay.amount_paise) + '</b>' +
      (pay.reference ? ' · ref ' + esc(pay.reference) : '') + '</p>' +
      (pay.status !== 'posted' ? '<div class="msg info">Reversed: ' + esc(pay.reverse_reason || '') + '</div>' : '') +
      (pay.on_account > 0 ? '<p>' + RB.rupees(pay.on_account) + ' is on account (not set against a bill yet).</p>' : '') +
      (pay.status === 'posted' ? '<div class="actions" id="pm-share"></div>' : '') +
      '<div class="actions">' +
      (pay.status === 'posted' && pay.on_account > 0 && RB.has('purchases.add') ? '<button class="primary" id="pm-alloc">Set against bills</button>' : '') +
      (pay.status === 'posted' && RB.has('power.reverse_entries') ? '<button class="danger" id="pm-rev">Reverse payment</button>' : '') +
      (pay.status === 'posted' && RB.has('purchases.delete') ? '<button class="danger" id="pm-del">Delete fully (learning phase)</button>' : '') +
      '<button data-close>Close</button></div>');
    const on = (id, fn) => { const b = $(id, m.el); if (b) b.addEventListener('click', fn); };
    if (pay.status === 'posted') RB.contactOf('suppliers', pay.supplier_id).then((c) => {
      const box = $('#pm-share', m.el); if (!box) return;
      box.innerHTML = RB.shareButtons({ phone: c.phone, email: c.email, subject: 'Payment ' + pay.payment_no + ' from Ruchi Buds',
        text: 'Hello ' + pay.supplier + ', Ruchi Buds has paid you ' + RB.rupees(pay.amount_paise) + ' on ' + RB.fmtDate(pay.pay_date) + ' by ' + (MODES[pay.mode] || pay.mode) +
          (pay.reference ? ' (ref ' + pay.reference + ')' : '') + '. Our payment no. ' + pay.payment_no + '. Please confirm when received. Thank you.' });
    });
    on('#pm-alloc', () => { m.close(); payModal({ supplier_id: pay.supplier_id, allocateOnly: pay }, done); });
    on('#pm-rev', () => { m.close(); reverseModal('Reverse payment ' + pay.payment_no, 'The payment is undone in the books and the bills it paid are owed again.',
      (dt, why) => RB.rpc('rb_reverse_supplier_payment', { p_id: pay.id, p_date: dt, p_reason: why }), done); });
    on('#pm-del', async () => {
      if (!(await RB.confirm('Delete this payment fully?', 'Only for payments entered by someone still in their learning phase. It disappears from the books without a reversal.'))) return;
      try { await RB.rpc('rb_hard_delete_supplier_payment', { p_id: pay.id }); RB.toast('Payment deleted'); m.close(); done(); } catch (e) { RB.modalMsg(m, e.message); }
    });
  }

  // ---------- supplier balances and ledger ----------
  async function balancesTab(tb) {
    tb.innerHTML = '<div class="row" style="align-items:flex-end"><div class="field" style="flex:0 1 200px"><label for="sb-date">Balances on</label><input type="date" id="sb-date" value="' + RB.today() + '"></div>' +
      '<div class="field" style="flex:0 1 auto"><button id="sb-go">Show</button> <button id="sb-xls">Download to Excel</button></div></div>' +
      '<p class="muted">From the books (Trade payables, per supplier). A minus balance means the supplier owes us (an advance or a return). Tap a supplier for their ledger.</p><div id="sb-grid"></div>';
    let grid;
    const load = async () => {
      const rows = await RB.rpc('rb_supplier_balances', { p_as_of: $('#sb-date', tb).value || RB.today() });
      grid = RB.grid($('#sb-grid', tb), [
        { title: 'Code', field: 'code', width: 110 },
        { title: 'Supplier', field: 'name', minWidth: 220, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
        { title: 'Billed', field: 'billed_paise', hozAlign: 'right', formatter: (c) => amt(c.getValue()), headerFilter: false },
        { title: 'Paid and returned', field: 'paid_paise', hozAlign: 'right', formatter: (c) => amt(c.getValue()), headerFilter: false },
        { title: 'Balance owed', field: 'balance_paise', hozAlign: 'right', formatter: (c) => '<b>' + RB.rupees(c.getValue()) + '</b>', headerFilter: false },
        { title: 'Unpaid bills', field: 'open_bills', hozAlign: 'center', headerFilter: false },
        { title: 'Oldest (days)', field: 'oldest_days', hozAlign: 'right', headerFilter: false },
        { title: 'Overdue', field: 'overdue_paise', hozAlign: 'right', formatter: (c) => (c.getValue() > 0 ? '<span class="diff">' + RB.rupees(c.getValue()) + '</span>' : ''), headerFilter: false },
      ], rows);
      grid.on('rowClick', (e, row) => P.ledgerModal(row.getData().supplier_id, row.getData().name));
    };
    $('#sb-go', tb).addEventListener('click', load);
    $('#sb-xls', tb).addEventListener('click', () => grid && RB.downloadExcel(grid, 'Supplier balances'));
    await load();
  }

  const EVENTS = { supplier_bill: 'Bill', direct_purchase: 'Direct purchase', supplier_payment: 'Payment', debit_note: 'Debit note',
    purchase_return: 'Return', opening: '', manual: 'Journal', reversal: 'Reversal' };
  P.ledgerModal = (supplierId, name) => {
    const today = RB.today(), fy = (Number(today.slice(5, 7)) >= 4 ? today.slice(0, 4) : String(Number(today.slice(0, 4)) - 1)) + '-04-01';
    const m = RB.modal('<h2>Supplier ledger: ' + esc(name) + '</h2><div class="m-msg"></div>' +
      '<div class="row" style="align-items:flex-end"><div class="field"><label for="sl-from">From</label><input type="date" id="sl-from" value="' + fy + '"></div>' +
      '<div class="field"><label for="sl-to">To</label><input type="date" id="sl-to" value="' + today + '"></div>' +
      '<div class="field" style="flex:0 1 auto"><button id="sl-go">Show</button> <button id="sl-xls">Excel</button></div></div><div id="sl-grid"></div>' +
      '<div class="actions">' + (RB.has('purchases.add') ? '<button class="primary" id="sl-pay">Pay this supplier</button>' : '') + '<button data-close>Close</button></div>', { wide: true });
    let grid;
    const load = async () => {
      try {
        const rows = await RB.rpc('rb_supplier_ledger', { p_supplier: supplierId, p_from: $('#sl-from', m.el).value, p_to: $('#sl-to', m.el).value });
        grid = RB.grid($('#sl-grid', m.el), [
          { title: 'Date', field: 'line_date', width: 115, formatter: (c) => RB.fmtDate(c.getValue()) },
          { title: 'What', field: 'event', width: 120, formatter: (c) => esc(EVENTS[c.getValue()] != null ? EVENTS[c.getValue()] : c.getValue()) },
          { title: 'Document', field: 'doc_ref', width: 160 },
          { title: 'Details', field: 'narration', minWidth: 240 },
          { title: 'Bill (we owe)', field: 'bill_paise', hozAlign: 'right', formatter: (c) => amt(c.getValue()), headerFilter: false },
          { title: 'Paid / returned', field: 'paid_paise', hozAlign: 'right', formatter: (c) => amt(c.getValue()), headerFilter: false },
          { title: 'Balance', field: 'balance_paise', hozAlign: 'right', formatter: (c) => RB.rupees(c.getValue()), headerFilter: false },
        ], rows, { pagination: false, height: Math.min(420, 60 + rows.length * 34) });
      } catch (e) { RB.modalMsg(m, e.message); }
    };
    $('#sl-go', m.el).addEventListener('click', load);
    $('#sl-xls', m.el).addEventListener('click', () => grid && RB.downloadExcel(grid, 'Ledger ' + name));
    const pb = $('#sl-pay', m.el); if (pb) pb.addEventListener('click', () => { m.close(); payModal({ supplier_id: supplierId }); });
    load();
  };

  // ---------- reports ----------
  async function reportsTab(tb) {
    const today = RB.today(), fy = (Number(today.slice(5, 7)) >= 4 ? today.slice(0, 4) : String(Number(today.slice(0, 4)) - 1)) + '-04-01';
    tb.innerHTML = '<div class="row" style="align-items:flex-end"><div class="field" style="flex:0 1 180px"><label for="rp-from">From</label><input type="date" id="rp-from" value="' + fy + '"></div>' +
      '<div class="field" style="flex:0 1 180px"><label for="rp-to">To</label><input type="date" id="rp-to" value="' + today + '"></div>' +
      '<div class="field" style="flex:0 1 auto"><button id="rp-go">Show</button></div></div>' +
      '<div class="card"><h2>Supplier differences by month</h2><p class="muted">Count and value of short supply, overcharges (rate and tax above the PO) and goods refused at delivery, per supplier.</p>' +
      '<div class="actions" style="margin:0 0 .5rem"><button id="rp-x1">Download to Excel</button></div><div id="rp-g1"></div></div>' +
      '<div class="card"><h2>Direct purchases by month</h2><p class="muted">Purchases with no PO, for the monthly review.</p>' +
      '<div class="actions" style="margin:0 0 .5rem"><button id="rp-x2">Download to Excel</button></div><div id="rp-g2"></div></div>' +
      '<div class="card"><h2>Stock bought so far</h2><p class="muted">Quantity and cost of raw materials and packaging from purchases. Production is on the Production screen; sales come with module 5.</p>' +
      '<div class="actions" style="margin:0 0 .5rem"><button id="rp-x3">Download to Excel</button></div><div id="rp-g3"></div></div>';
    const month = (c) => { const v = c.getValue(); return v ? RB.fmtDate(v).slice(3) : ''; };
    let g1, g2, g3;
    const load = async () => {
      const from = $('#rp-from', tb).value, to = $('#rp-to', tb).value;
      const [r1, r2, r3] = await Promise.all([
        RB.rpc('rb_supplier_discrepancy_report', { p_from: from, p_to: to }),
        RB.rpc('rb_direct_purchase_report', { p_from: from, p_to: to }),
        RB.rpc('rb_stock_on_hand', { p_as_of: to })]);
      g1 = RB.grid($('#rp-g1', tb), [
        { title: 'Month', field: 'month', width: 110, formatter: month },
        { title: 'Supplier', field: 'supplier_name', minWidth: 200 },
        { title: 'Short (count)', field: 'short_count', hozAlign: 'right', headerFilter: false },
        { title: 'Short (₹)', field: 'short_paise', hozAlign: 'right', formatter: (c) => amt(c.getValue()), headerFilter: false },
        { title: 'Overcharge (count)', field: 'overcharge_count', hozAlign: 'right', headerFilter: false },
        { title: 'Overcharge (₹)', field: 'overcharge_paise', hozAlign: 'right', formatter: (c) => amt(c.getValue()), headerFilter: false },
        { title: 'Refused (count)', field: 'reject_count', hozAlign: 'right', headerFilter: false },
        { title: 'Refused (₹)', field: 'reject_paise', hozAlign: 'right', formatter: (c) => amt(c.getValue()), headerFilter: false },
        { title: 'Still open', field: 'open_count', hozAlign: 'right', headerFilter: false },
      ], r1);
      g2 = RB.grid($('#rp-g2', tb), [
        { title: 'Month', field: 'month', width: 110, formatter: month },
        { title: 'Supplier', field: 'supplier_name', minWidth: 200 },
        { title: 'Purchases', field: 'purchases', hozAlign: 'right', headerFilter: false },
        { title: 'With no bill', field: 'no_bill', hozAlign: 'right', headerFilter: false },
        { title: 'Total', field: 'total_paise', hozAlign: 'right', formatter: (c) => amt(c.getValue()), headerFilter: false },
        { title: 'Paid at once', field: 'cash_paise', hozAlign: 'right', formatter: (c) => amt(c.getValue()), headerFilter: false },
        { title: 'On credit', field: 'credit_paise', hozAlign: 'right', formatter: (c) => amt(c.getValue()), headerFilter: false },
        { title: 'Waiting approval', field: 'awaiting_approval', hozAlign: 'right', headerFilter: false },
      ], r2);
      g3 = RB.grid($('#rp-g3', tb), [
        { title: 'Code', field: 'code', width: 100 },
        { title: 'Item', field: 'name', minWidth: 200 },
        { title: 'Quantity', field: 'qty_base', hozAlign: 'right', formatter: (c) => RB.qty(c.getValue(), c.getRow().getData().base_unit), headerFilter: false },
        { title: 'Cost', field: 'value_paise', hozAlign: 'right', formatter: (c) => RB.rupees(c.getValue()), headerFilter: false },
      ], r3);
    };
    $('#rp-go', tb).addEventListener('click', () => load().catch((e) => RB.toast(e.message, true)));
    $('#rp-x1', tb).addEventListener('click', () => g1 && RB.downloadExcel(g1, 'Supplier differences'));
    $('#rp-x2', tb).addEventListener('click', () => g2 && RB.downloadExcel(g2, 'Direct purchases'));
    $('#rp-x3', tb).addEventListener('click', () => g3 && RB.downloadExcel(g3, 'Stock bought'));
    await load();
  }

  // ===================================================================
  // The Purchase window
  // ===================================================================
  async function purchaseWindow(body, id) {
    const h1 = $('.page-head h1'); const back = $('.page-head .back');
    if (back) { back.href = '#/purchases'; back.hidden = false; back.textContent = '‹ Purchases'; }
    body.innerHTML = '<p class="muted">Loading…</p>';
    const [d, x] = await Promise.all([lists(), RB.rpc('rb_purchase_detail', { p_id: id })]);
    const p = x.purchase, can = x.can, lines = x.lines;
    if (h1) h1.innerHTML = esc(p.label) + RB.demoBadge(p);
    const reload = () => purchaseWindow(body, id);
    const disc = x.discrepancies;
    const openD = (lineId, stage, kinds) => disc.find((z) => z.purchase_line_id === lineId && z.stage === stage && kinds.includes(z.kind) && z.status === 'open');
    const anyD = (lineId, stage, kinds) => disc.find((z) => z.purchase_line_id === lineId && z.stage === stage && kinds.includes(z.kind));
    const cell = (v, d1) => '<td class="' + (d1 ? (d1.status === 'open' ? 'diff' : 'diff-done') : '') + '"' + (d1 ? ' title="' + esc(d1.explain) + '"' : '') + '>' + v + '</td>';
    const billed = !!p.bill_posted_at;

    // Steps strip
    const step = (on, label) => '<span class="step' + (on ? ' done' : '') + '">' + (on ? '✓ ' : '') + label + '</span>';
    const steps = p.is_direct
      ? step(true, 'Direct purchase (no PO)') + step(billed, p.no_supplier_bill ? 'Received, no supplier bill' : 'Received and billed') + step(p.status === 'paid', 'Paid')
      : step(true, 'Ordered') + step(x.grns.length > 0, 'Received') + step(billed, 'Billed') + step(p.status === 'paid', 'Paid');

    const head =
      '<div class="card"><div class="steps">' + steps + '</div>' +
      '<div class="row facts">' +
      '<div><small>Supplier</small>' + esc(p.supplier_name) + '</div>' +
      '<div><small>Status</small>' + statusBadge(p.status) + '</div>' +
      (p.po_no ? '<div><small>Order</small>' + esc(p.po_no) + ' · ' + RB.fmtDate(p.po_date) + (p.expected_date ? '<br><span class="muted">expected ' + RB.fmtDate(p.expected_date) + '</span>' : '') + '</div>' : '') +
      (p.is_direct ? '<div><small>Bought on</small>' + RB.fmtDate(p.purchase_date) + '<br><span class="muted">' + esc(p.reason || '') + '</span></div>' : '') +
      '<div><small>Supplier bill</small>' + (billed ? (p.no_supplier_bill ? 'None (ref ' + esc(p.bill_no) + ')' : esc(p.bill_no) + ' · ' + RB.fmtDate(p.bill_date)) : '<span class="muted">not yet</span>') + '</div>' +
      '<div><small>Payment</small>' + esc(MODES[p.payment_mode] || '') + '</div>' +
      (billed && Number(p.bill_gst_paise) > 0 ? '<div><small>GST</small>' + (p.gst_claimed ? 'Input credit' : 'Added to stock cost<br><span class="muted">not GST registered on the bill date</span>') + '</div>' : '') +
      '<div><small>Department</small>' + esc(p.department || '') + '</div>' +
      '<div><small>Entered by</small>' + esc(p.entered_by_name || '') + (p.approved_by_name && p.approval_needed ? '<br><span class="muted">approved by ' + esc(p.approved_by_name) + '</span>' : '') + '</div>' +
      '</div>' +
      (p.note ? '<p class="muted">Note: ' + esc(p.note) + '</p>' : '') +
      (p.status === 'awaiting_approval' ? '<div class="msg info">Above the direct-purchase limit in Settings: the Accountant, FC or a Director must approve it before it posts. Nothing is in stock or the books yet.</div>' : '') +
      (p.status === 'refused' ? '<div class="msg error">Refused: ' + esc(p.refused_reason || '') + '</div>' : '') +
      (p.status === 'cancelled' ? '<div class="msg error">Cancelled: ' + esc(p.cancel_reason || '') + '</div>' : '') +
      '<div class="row totals">' +
      (p.is_direct ? '' : '<div><small>Ordered</small>' + RB.rupees(p.order_total_paise) + '</div>') +
      '<div><small>Received (stock value)</small>' + RB.rupees(p.grn_value_paise) + '</div>' +
      '<div><small>Bill total</small>' + (billed ? RB.rupees(p.bill_total_paise) : '–') + '</div>' +
      (p.notes_paise > 0 ? '<div><small>Debit notes and returns</small>−' + RB.rupees(p.notes_paise) + '</div>' : '') +
      '<div><small>Paid</small>' + RB.rupees(p.paid_paise) + '</div>' +
      '<div><small>Still owed</small><b>' + RB.rupees(p.outstanding_paise) + '</b></div>' +
      '</div></div>';

    // Match view: PO, GRN and Bill side by side per line
    const match =
      '<div class="card"><h2>' + (p.is_direct ? 'Items' : 'Match: order, goods received and bill') + '</h2>' +
      (p.is_direct ? '' : '<p class="muted">Any difference in quantity, rate or tax is in <span class="diff">red</span> until it is settled below (settled ones turn amber). There is no tolerance: every difference is flagged.</p>') +
      '<div class="grid-wrap"><table class="ticks match"><thead>' +
      (p.is_direct
        ? '<tr><th>Item</th><th>Quantity</th><th>Rate</th><th>Amount</th><th>GST</th><th>Returned</th></tr>'
        : '<tr><th rowspan="2">Item</th><th colspan="3" class="grp">Order (PO)</th><th colspan="3" class="grp">Received (GRN)</th><th colspan="4" class="grp">Bill</th></tr>' +
          '<tr><th>Qty</th><th>Rate</th><th>GST %</th><th>Received</th><th>Refused</th><th>Kept</th><th>Qty</th><th>Rate</th><th>Amount</th><th>GST</th></tr>') +
      '</thead><tbody>' +
      lines.map((l) => {
        const u = esc(l.unit_code);
        if (p.is_direct) return '<tr><td>' + esc(l.item_name) + '</td><td>' + q(l.received_qty) + ' ' + u + '</td><td>' + RB.rupees(l.bill_rate_paise) + '</td><td>' +
          RB.rupees(l.bill_taxable_paise) + '</td><td>' + amt(l.bill_gst_paise) + '</td><td>' + (Number(l.returned_qty) ? q(l.returned_qty) + ' ' + u : '') + '</td></tr>';
        const recD = anyD(l.id, 'receipt', ['short', 'excess']), dmgD = anyD(l.id, 'receipt', ['damaged']);
        const qtyD = anyD(l.id, 'bill', ['short', 'excess']), rateD = anyD(l.id, 'bill', ['rate']), taxD = anyD(l.id, 'bill', ['tax']);
        return '<tr><td>' + esc(l.item_name) + '</td>' +
          '<td>' + q(l.po_qty) + ' ' + u + '</td><td>' + RB.rupees(l.po_rate_paise) + '</td><td>' + q(l.gst_rate) + '%</td>' +
          (x.grns.length ? cell(q(l.received_qty) + ' ' + u, recD) + cell(Number(l.rejected_qty) ? q(l.rejected_qty) : '', dmgD) +
            '<td>' + q(l.accepted_qty) + (Number(l.returned_qty) ? '<br><span class="muted">' + q(l.returned_qty) + ' returned</span>' : '') + '</td>'
            : '<td colspan="3" class="muted">not received yet</td>') +
          (billed ? cell(q(l.bill_qty) + ' ' + u, qtyD) + cell(RB.rupees(l.bill_rate_paise), rateD) + '<td>' + RB.rupees(l.bill_taxable_paise) + '</td>' +
            cell(RB.rupees(l.bill_gst_paise), taxD) : '<td colspan="4" class="muted">no bill yet</td>') + '</tr>';
      }).join('') + '</tbody></table></div></div>';

    // Differences, with Accept / Reject
    const actionsFor = (z) => {
      if (z.stage === 'receipt' && z.kind === 'short') return ['accept', 'await_delivery'];
      if (z.stage === 'receipt' && (z.kind === 'excess' || z.kind === 'damaged')) return ['accept', 'return'];
      if (z.stage === 'bill' && z.kind === 'short') return ['accept', 'debit_note', 'await_delivery'];
      if (z.kind === 'rate' && z.amount_paise > 0) return ['accept', 'correct_rate'];
      if (z.kind === 'tax' && z.amount_paise > 0) return ['accept', 'debit_note'];
      return ['accept'];
    };
    const money = (z) => z.stage === 'bill' || z.kind === 'rate' || z.kind === 'tax';
    const diffs = disc.length ? '<div class="card"><h2>Differences</h2>' +
      (disc.some((z) => z.status === 'open' && money(z)) && !can.settle_money ? '<p class="muted">Money differences (rate, tax, billed quantity) are settled by the Accountant, FC or a Director.</p>' : '') +
      disc.map((z) => {
        const mayAct = z.status === 'open' && (money(z) ? can.settle_money : can.settle_qty);
        return '<div class="diff-row ' + (z.status === 'open' ? 'open' : 'done') + '">' +
          '<div><b class="' + (z.status === 'open' ? 'diff' : '') + '">' + esc(KIND[z.kind]) + ' ' + STAGE[z.stage] + '</b> · ' + esc(z.item_name) + ': ' + esc(z.explain) +
          ' · ' + RB.rupees(Math.abs(z.amount_paise)) +
          (z.status === 'open' ? ' <span class="muted">(' + z.age_days + ' days)</span>'
            : '<br><span class="muted">' + (z.status === 'accepted' ? 'Accepted' : 'Rejected: ' + esc(ACTIONS[z.action] || z.action)) + ' by ' + esc(z.decided_by_name || '') +
              ' on ' + RB.fmtDate(z.decided_at) + ' · ' + esc(z.reason || '') + '</span>') + '</div>' +
          (mayAct ? '<div class="actions" style="margin:.25rem 0 0">' + actionsFor(z).map((a) =>
            '<button data-settle="' + z.id + '" data-act="' + a + '"' + (a === 'accept' ? ' class="primary"' : '') + '>' + (a === 'accept' ? 'Accept' : 'Reject: ' + esc(ACTIONS[a])) + '</button>').join('') + '</div>' : '') +
          '</div>';
      }).join('') + '</div>' : '';

    // Documents
    const docs = [];
    x.grns.forEach((g) => docs.push([g.grn_date, 'Goods received', g.grn_no, RB.rupees(g.value_paise), g.journal_no]));
    if (billed && !p.is_direct) docs.push([p.bill_date, 'Supplier bill', p.bill_no, RB.rupees(p.bill_total_paise), p.bill_journal_no]);
    x.notes.forEach((n) => docs.push([n.note_date, 'Debit note', n.note_no, '−' + RB.rupees(n.total_paise), n.journal_no, n.reason]));
    x.returns.forEach((r) => docs.push([r.return_date, r.from_stock ? 'Return' : 'Refused goods sent back', r.return_no, r.total_paise ? '−' + RB.rupees(r.total_paise) : '', r.journal_no, r.reason]));
    x.payments.forEach((y) => docs.push([y.pay_date, 'Payment (' + MODES[y.mode] + ')' + (y.status !== 'posted' ? ' reversed' : ''), y.payment_no, RB.rupees(y.amount_paise), '']));
    docs.sort((a, b) => String(a[0]).localeCompare(String(b[0])));
    const docsHtml = docs.length ? '<div class="card"><h2>Documents</h2><div class="grid-wrap"><table class="ticks"><thead><tr><th>Date</th><th>What</th><th>Number</th><th>Amount</th><th>Journal</th><th>Why</th></tr></thead><tbody>' +
      docs.map((r) => '<tr><td>' + RB.fmtDate(r[0]) + '</td><td style="text-align:left">' + esc(r[1]) + '</td><td>' + esc(r[2]) + '</td><td style="text-align:right">' + r[3] + '</td><td>' + esc(r[4] || '') + '</td><td style="text-align:left">' + esc(r[5] || '') + '</td></tr>').join('') +
      '</tbody></table></div></div>' : '';
    const photos = '<div class="card"><h2>Photos</h2>' + (x.photos.length ? '<div class="actions">' + x.photos.map((ph) => '<button data-photo="' + ph.id + '">📷 ' + esc(ph.caption || 'Photo') + ' · ' + RB.fmtDate(ph.added_at) + '</button>').join('') + '</div>' : '<p class="muted">No photo yet.</p>') +
      (RB.has('purchases.add') && p.status !== 'cancelled' ? '<label class="btn" style="margin-top:.5rem">+ Add a photo<input type="file" accept="image/*" capture="environment" id="pw-photo" hidden></label>' : '') + '</div>';

    // Action buttons
    const btn = (on, id, label, cls) => (on ? '<button id="' + id + '"' + (cls ? ' class="' + cls + '"' : '') + '>' + label + '</button>' : '');
    const bar = '<div class="actions" style="margin:0 0 1rem">' +
      btn(can.receive, 'pw-receive', 'Receive goods (GRN)', 'primary') +
      btn(can.bill, 'pw-bill', 'Enter supplier bill', 'primary') +
      btn(can.approve, 'pw-approve', 'Approve and post', 'primary') +
      btn(can.edit_direct, 'pw-editdirect', 'Change') +
      btn(can.approve, 'pw-refuse', 'Refuse', 'danger') +
      btn(can.pay, 'pw-pay', 'Pay') +
      btn(can.edit_order, 'pw-edit', 'Change order') +
      btn(can.return, 'pw-return', 'Return goods') +
      btn(RB.has('suppliers.view') || RB.has('purchases.view'), 'pw-ledger', 'Supplier ledger') +
      btn(can.cancel, 'pw-cancel', 'Cancel order', 'danger') +
      btn(can.reverse, 'pw-reverse', 'Reverse purchase', 'danger') +
      btn(can.hard_delete, 'pw-delete', 'Delete fully (learning phase)', 'danger') + '</div>' +
      (p.po_no && !p.is_direct && !['cancelled', 'refused'].includes(p.status) ? (() => {
        const sp = d.sup[p.supplier_id] || {};
        const text = 'Hello ' + p.supplier_name + ', please supply the following for Ruchi Buds.\nPurchase order ' + p.po_no + ' dated ' + RB.fmtDate(p.po_date) +
          (p.expected_date ? ', needed by ' + RB.fmtDate(p.expected_date) : '') + ':\n' +
          lines.map((l, i) => (i + 1) + '. ' + l.item_name + ': ' + q(l.po_qty) + ' ' + l.unit_code + ' at ' + RB.rupees(l.po_rate_paise) +
            (Number(l.gst_rate) ? ' + GST ' + q(l.gst_rate) + '%' : '')).join('\n') +
          '\nOrder value: ' + RB.rupees(p.order_total_paise) + '.\nPlease quote ' + p.po_no + ' on your bill. Thank you.';
        return '<div class="actions" style="margin:-.5rem 0 1rem">' + RB.shareButtons({ phone: sp.phone, email: sp.email, subject: 'Purchase order ' + p.po_no + ' from Ruchi Buds', text,
          label: 'Send order on WhatsApp', mailLabel: 'Send order by email' }) + '</div>';
      })() : '') +
      (p.open_discrepancies > 0 && p.outstanding_paise > 0 ? '<div class="msg error">This purchase has ' + p.open_discrepancies + ' open difference(s). It cannot be paid until each one is accepted or rejected.</div>' : '');

    body.innerHTML = bar + head + match + diffs + docsHtml + photos;

    const on = (sel, fn) => { const b = $(sel, body); if (b) b.addEventListener('click', fn); };
    on('#pw-receive', () => receiveModal(x, reload));
    on('#pw-bill', () => billModal(x, reload));
    on('#pw-edit', () => orderModal(x, reload));
    on('#pw-editdirect', () => directModal(x, reload));
    on('#pw-pay', () => payModal({ supplier_id: p.supplier_id, purchase_id: p.id }, reload));
    on('#pw-return', () => returnModal(x, reload));
    on('#pw-ledger', () => P.ledgerModal(p.supplier_id, p.supplier_name));
    on('#pw-approve', async () => {
      if (!(await RB.confirm('Approve and post?', 'Goods go into stock and the purchase posts to the books' + (p.payment_mode !== 'credit' ? ', with the payment' : '') + '.'))) return;
      try { await RB.rpc('rb_approve_direct_purchase', { p_id: id }); RB.toast('Approved and posted'); reload(); } catch (e) { RB.toast(e.message, true); }
    });
    on('#pw-refuse', () => reasonModal('Refuse this purchase', 'Nothing is posted. Say why, so the person who entered it knows.', (why) => RB.rpc('rb_refuse_direct_purchase', { p_id: id, p_reason: why }), reload));
    on('#pw-cancel', () => reasonModal('Cancel this order', 'Nothing has been received, so nothing is posted. Give the reason.', (why) => RB.rpc('rb_cancel_purchase_order', { p_id: id, p_reason: why }), reload));
    on('#pw-reverse', () => reverseModal('Reverse ' + p.label, 'Every entry this purchase made (stock, bill, debit notes, returns) is reversed on the date you choose. The purchase is then cancelled.',
      (dt, why) => RB.rpc('rb_reverse_purchase', { p_id: id, p_date: dt, p_reason: why }), reload));
    on('#pw-delete', async () => {
      if (!(await RB.confirm('Delete this purchase fully?', 'Only for entries by someone still in their learning phase. It disappears from stock and the books with no reversal.'))) return;
      try { await RB.rpc('rb_hard_delete_purchase', { p_id: id }); RB.toast('Purchase deleted'); location.hash = '#/purchases'; } catch (e) { RB.toast(e.message, true); }
    });
    $$('[data-settle]', body).forEach((b) => b.addEventListener('click', () => settleModal(disc.find((z) => String(z.id) === b.dataset.settle), b.dataset.act, reload)));
    $$('[data-photo]', body).forEach((b) => b.addEventListener('click', async () => {
      try {
        const src = await RB.rpc('rb_purchase_photo', { p_id: Number(b.dataset.photo) });
        RB.modal('<h2>Photo</h2><img src="' + esc(src) + '" alt="Purchase photo" style="max-width:100%;border-radius:6px"><div class="actions"><button data-close>Close</button></div>', { wide: true });
      } catch (e) { RB.toast(e.message, true); }
    }));
    const ph = $('#pw-photo', body);
    if (ph) ph.addEventListener('change', async () => {
      try {
        const data = await P.photoToDataUrl(ph.files[0]);
        await RB.rpc('rb_add_purchase_photo', { p_id: id, p_data_url: data, p_caption: p.no_supplier_bill ? 'Catch or weighing slip' : 'Bill' });
        RB.toast('Photo added'); reload();
      } catch (e) { RB.toast(e.message, true); }
    });
  }

  // ---------- small shared modals ----------
  function reasonModal(title, explain, run, done) {
    const m = RB.modal('<h2>' + esc(title) + '</h2><div class="m-msg"></div><p>' + explain + '</p>' +
      RB.field('rs-why', 'Reason', '<textarea id="rs-why"></textarea>', null, true) +
      '<div class="actions"><button class="primary" id="rs-go">Confirm</button><button data-close>Back</button></div>');
    $('#rs-go', m.el).addEventListener('click', async () => {
      try { await run($('#rs-why', m.el).value); RB.toast('Done'); m.close(); if (done) done(); } catch (e) { RB.modalMsg(m, e.message); }
    });
  }
  function reverseModal(title, explain, run, done) {
    const m = RB.modal('<h2>' + esc(title) + '</h2><div class="m-msg"></div><p>' + explain + '</p>' +
      '<div class="row">' + RB.field('rv-date', 'Reversal date', '<input type="date" id="rv-date" value="' + RB.today() + '">') + '</div>' +
      RB.field('rv-why', 'Reason', '<textarea id="rv-why"></textarea>', null, true) +
      '<div class="actions"><button class="danger" id="rv-go">Reverse</button><button data-close>Back</button></div>');
    $('#rv-go', m.el).addEventListener('click', async () => {
      try { await run($('#rv-date', m.el).value, $('#rv-why', m.el).value); RB.toast('Reversed'); m.close(); if (done) done(); } catch (e) { RB.modalMsg(m, e.message); }
    });
  }

  function settleModal(z, act, done) {
    const what = {
      accept: z.stage === 'bill' ? 'The line stays at the billed figure; the supplier is paid what they billed.' : 'The difference is accepted as it is (for example a normal weighing loss).',
      return: z.kind === 'damaged' ? 'Records that the refused goods went back to the supplier. They never came into stock, so stock does not change.' : 'Sends the extra quantity back: it leaves stock and the supplier balance (or goods-received) goes down.',
      debit_note: 'Raises a debit note to the supplier for the difference. It lowers what we owe and the stock cost.',
      await_delivery: 'Keeps the difference as settled for now: the rest is expected in a later delivery.',
      correct_rate: 'Raises a debit note to bring the line back to the PO rate. It lowers what we owe and the stock cost.',
    }[act];
    const m = RB.modal('<h2>' + esc(act === 'accept' ? 'Accept' : 'Reject: ' + ACTIONS[act]) + '</h2><div class="m-msg"></div>' +
      '<p><b>' + esc(KIND[z.kind]) + ' ' + STAGE[z.stage] + '</b> · ' + esc(z.item_name) + ': ' + esc(z.explain) + ' (' + RB.rupees(Math.abs(z.amount_paise)) + ')</p>' +
      '<p class="muted">' + what + '</p>' +
      (['return', 'debit_note', 'correct_rate'].includes(act) ? '<div class="row">' + RB.field('st-date', 'Date', '<input type="date" id="st-date" value="' + RB.today() + '">') + '</div>' : '') +
      RB.field('st-why', 'Reason', '<textarea id="st-why" placeholder="' + (act === 'accept' ? 'e.g. normal weighing loss' : 'e.g. supplier agreed by phone') + '"></textarea>', null, true) +
      '<div class="actions"><button class="primary" id="st-go">Confirm</button><button data-close>Back</button></div>');
    $('#st-go', m.el).addEventListener('click', async () => {
      try {
        await RB.rpc('rb_settle_discrepancy', { p_id: z.id, p_action: act, p_reason: $('#st-why', m.el).value, p_date: $('#st-date', m.el) ? $('#st-date', m.el).value : null });
        RB.toast('Difference settled'); m.close(); done();
      } catch (e) { RB.modalMsg(m, e.message); }
    });
  }

  // ---------- order (PO) form ----------
  async function orderModal(x, done) {
    const d = await lists();
    const p = x ? x.purchase : { po_date: RB.today(), department_id: defaultDept(d) };
    let lines = x ? x.lines.map((l) => ({ item_id: l.item_id, unit_code: l.unit_code, qty: l.po_qty, rate: RB.fromPaise(l.po_rate_paise), gst: l.gst_rate })) : [{}];
    const m = RB.modal('<h2>' + (x ? 'Change order ' + esc(p.po_no) : 'New purchase order') + '</h2><div class="m-msg"></div>' +
      '<div class="row">' + supplierPicker(d, 'po-sup', p.supplier_id) +
      RB.field('po-date', 'Order date', '<input type="date" id="po-date" value="' + esc(p.po_date) + '">', null, true) +
      RB.field('po-exp', 'Expected delivery', '<input type="date" id="po-exp" value="' + esc(p.expected_date || '') + '">') + '</div>' +
      '<div class="row">' + RB.field('po-dept', 'Department', RB.sel('po-dept', deptOptions(d), p.department_id)) +
      RB.field('po-note', 'Note', RB.inp('po-note', p.note)) + '</div>' +
      '<div id="po-lines"></div><div class="actions"><button type="button" id="po-add">+ Add a line</button></div>' +
      '<p id="po-total" style="font-weight:600"></p>' +
      '<p class="muted">The PO number (PO/YYMM/00001) is given when you save. Rates are before GST.</p>' +
      '<div class="actions"><button class="primary" id="po-save">Save order</button><button data-close>Cancel</button></div>', { wide: true });
    wireSupplierAdd(m, d);
    const draw = () => {
      $('#po-lines', m.el).innerHTML = '<div class="grid-wrap"><table class="ticks lines"><thead><tr><th>Item</th><th>Unit</th><th>Quantity</th><th>Rate ₹ (per unit)</th><th>GST %</th><th>Amount</th><th></th></tr></thead><tbody>' +
        lines.map((l, i) => '<tr><td style="min-width:200px">' + RB.sel('pl-item-' + i, [['', 'Choose…']].concat(d.buyItems.map((it) => [it.id, it.name])), l.item_id, ' data-f="item_id" data-i="' + i + '"') + '</td>' +
          '<td style="min-width:90px">' + RB.sel('pl-unit-' + i, d.unitsFor(l.item_id).map((u) => [u.code, u.code]), l.unit_code, ' data-f="unit_code" data-i="' + i + '"') + '</td>' +
          '<td style="min-width:100px"><input data-f="qty" data-i="' + i + '" inputmode="decimal" value="' + esc(l.qty == null ? '' : l.qty) + '"></td>' +
          '<td style="min-width:110px"><input data-f="rate" data-i="' + i + '" inputmode="decimal" value="' + esc(l.rate == null ? '' : l.rate) + '"></td>' +
          '<td style="min-width:80px"><input data-f="gst" data-i="' + i + '" inputmode="decimal" value="' + esc(l.gst == null ? '' : l.gst) + '"></td>' +
          '<td style="text-align:right" data-amt="' + i + '"></td><td><button type="button" data-del="' + i + '" aria-label="Remove line">✕</button></td></tr>').join('') + '</tbody></table></div>';
      $$('[data-f]', m.el).forEach((el) => el.addEventListener(el.tagName === 'SELECT' ? 'change' : 'input', () => {
        const l = lines[el.dataset.i]; l[el.dataset.f] = el.value;
        if (el.dataset.f === 'item_id') {
          const it = d.item[el.value]; l.item_id = Number(el.value) || null;
          if (it) { l.unit_code = d.unitOf(it); if (l.gst == null || l.gst === '') l.gst = it.gst_rate == null ? '' : it.gst_rate; }
          draw(); return;
        }
        total();
      }));
      $$('[data-del]', m.el).forEach((b) => b.addEventListener('click', () => { lines.splice(Number(b.dataset.del), 1); if (!lines.length) lines.push({}); draw(); }));
      total();
    };
    const total = () => {
      let t = 0, g = 0;
      lines.forEach((l, i) => {
        let a = 0; try { a = lineAmt(num(l.qty), RB.toPaise(l.rate)); } catch (e) { a = 0; }
        t += a; g += Math.round(a * (Number(l.gst) || 0) / 100);
        const c = $('[data-amt="' + i + '"]', m.el); if (c) c.textContent = a ? RB.rupees(a) : '';
      });
      $('#po-total', m.el).textContent = 'Order total ' + RB.rupees(t) + ' + GST about ' + RB.rupees(g) + ' = ' + RB.rupees(t + g);
    };
    $('#po-add', m.el).addEventListener('click', () => { lines.push({}); draw(); });
    draw();
    $('#po-save', m.el).addEventListener('click', async () => {
      try {
        const out = lines.filter((l) => l.item_id || l.qty).map((l) => ({ item_id: l.item_id, unit_code: l.unit_code || null, qty: num(l.qty), rate_paise: RB.toPaise(l.rate), gst_rate: l.gst === '' || l.gst == null ? null : num(l.gst) }));
        const newId = await RB.rpc('rb_save_purchase_order', { p: { id: x ? p.id : null, supplier_id: Number($('#po-sup', m.el).value) || null,
          po_date: $('#po-date', m.el).value, expected_date: $('#po-exp', m.el).value || null, department_id: Number($('#po-dept', m.el).value) || null,
          note: $('#po-note', m.el).value, lines: out } });
        RB.toast('Order saved'); m.close();
        if (done) done(); else open(newId);
      } catch (e) { RB.modalMsg(m, e.message); m.el.scrollTop = 0; }
    });
  }

  // ---------- receive (GRN) form ----------
  function receiveModal(x, done) {
    const p = x.purchase;
    const m = RB.modal('<h2>Receive goods for ' + esc(p.po_no) + '</h2><div class="m-msg"></div>' +
      '<p class="muted">' + esc(p.supplier_name) + '. Enter what actually came in, by weight or count, and anything damaged or refused at the door. ' +
      'Kept goods go into stock now at the PO rate. A GRN number (GRN/YYMM/00001) is given when you save.</p>' +
      '<div class="row">' + RB.field('gr-date', 'Date received', '<input type="date" id="gr-date" value="' + RB.today() + '">', null, true) +
      RB.field('gr-note', 'Note (e.g. delivery challan no.)', RB.inp('gr-note', '')) + '</div>' +
      '<div class="grid-wrap"><table class="ticks lines"><thead><tr><th>Item</th><th>Ordered</th><th>Already received</th><th>Received now</th><th>Damaged / refused</th><th>Why refused</th></tr></thead><tbody>' +
      x.lines.map((l, i) => {
        const left = Math.max(0, Number(l.po_qty) - Number(l.received_qty));
        return '<tr><td style="text-align:left">' + esc(l.item_name) + '</td><td>' + q(l.po_qty) + ' ' + esc(l.unit_code) + '</td><td>' + q(l.received_qty) + '</td>' +
          '<td style="min-width:110px"><input data-rec="' + i + '" inputmode="decimal" value="' + (left ? left : '') + '"></td>' +
          '<td style="min-width:100px"><input data-rej="' + i + '" inputmode="decimal" value=""></td>' +
          '<td style="min-width:160px"><input data-why="' + i + '" value="" placeholder="e.g. broken"></td></tr>';
      }).join('') + '</tbody></table></div>' +
      '<div class="actions"><button class="primary" id="gr-save">Save goods received</button><button data-close>Cancel</button></div>', { wide: true });
    $('#gr-save', m.el).addEventListener('click', async () => {
      try {
        const lines = x.lines.map((l, i) => ({ line_id: l.id, received_qty: num($('[data-rec="' + i + '"]', m.el).value), rejected_qty: num($('[data-rej="' + i + '"]', m.el).value),
          reject_reason: $('[data-why="' + i + '"]', m.el).value }));
        await RB.rpc('rb_receive_goods', { p: { purchase_id: p.id, grn_date: $('#gr-date', m.el).value, note: $('#gr-note', m.el).value, lines } });
        RB.toast('Goods received'); m.close(); done();
      } catch (e) { RB.modalMsg(m, e.message); m.el.scrollTop = 0; }
    });
  }

  // ---------- bill form ----------
  function billModal(x, done) {
    const p = x.purchase;
    const m = RB.modal('<h2>Supplier bill for ' + esc(p.po_no) + '</h2><div class="m-msg"></div>' +
      '<p class="muted">Copy the bill exactly as the supplier wrote it, even where it differs from the order or what came in: the differences are flagged in red for the accounts team.</p>' +
      '<div class="row">' + RB.field('bl-no', 'Supplier\'s bill number', RB.inp('bl-no', ''), null, true) +
      RB.field('bl-date', 'Bill date', '<input type="date" id="bl-date" value="' + RB.today() + '">', null, true) +
      RB.field('bl-mode', 'Payment', RB.sel('bl-mode', Object.entries(MODES), 'credit'), 'Cash, UPI or bank pays it now (only if nothing differs).') +
      RB.field('bl-ref', 'Payment reference', RB.inp('bl-ref', '', ' placeholder="UPI or cheque no."')) + '</div>' +
      '<div class="grid-wrap"><table class="ticks lines"><thead><tr><th>Item</th><th>Kept (received)</th><th>PO rate</th><th>Billed qty</th><th>Bill rate ₹</th><th>Amount</th><th>GST ₹</th></tr></thead><tbody>' +
      x.lines.map((l, i) => {
        const kept = Number(l.accepted_qty) - Number(l.returned_before_bill_qty || 0);
        const gst = Math.round(lineAmt(kept, l.po_rate_paise) * Number(l.gst_rate || 0) / 100);
        return '<tr><td style="text-align:left">' + esc(l.item_name) + '</td><td>' + q(kept) + ' ' + esc(l.unit_code) + '</td><td>' + RB.rupees(l.po_rate_paise) + '</td>' +
          '<td style="min-width:100px"><input data-q="' + i + '" inputmode="decimal" value="' + q(kept).replace(/,/g, '') + '"></td>' +
          '<td style="min-width:100px"><input data-r="' + i + '" inputmode="decimal" value="' + RB.fromPaise(l.po_rate_paise) + '"></td>' +
          '<td data-a="' + i + '" style="text-align:right"></td>' +
          '<td style="min-width:100px"><input data-g="' + i + '" inputmode="decimal" value="' + RB.fromPaise(gst) + '"></td></tr>';
      }).join('') + '</tbody></table></div><p id="bl-total" style="font-weight:600"></p>' +
      '<div class="actions"><button class="primary" id="bl-save">Save bill</button><button data-close>Cancel</button></div>', { wide: true });
    const calc = () => {
      let t = 0, g = 0;
      x.lines.forEach((l, i) => {
        const qn = $('[data-q="' + i + '"]', m.el), rn = $('[data-r="' + i + '"]', m.el), gn = $('[data-g="' + i + '"]', m.el);
        let a = 0, gv = 0; try { a = lineAmt(num(qn.value), RB.toPaise(rn.value)); gv = RB.toPaise(gn.value) || 0; } catch (e) { /* shown on save */ }
        t += a; g += gv; $('[data-a="' + i + '"]', m.el).textContent = RB.rupees(a);
        const kept = Number(l.accepted_qty) - Number(l.returned_before_bill_qty || 0);
        qn.classList.toggle('diff-input', String(num(qn.value)) !== String(kept));
        rn.classList.toggle('diff-input', RB.toPaise(rn.value) !== Number(l.po_rate_paise));
        gn.classList.toggle('diff-input', (RB.toPaise(gn.value) || 0) !== Math.round(a * Number(l.gst_rate || 0) / 100));
      });
      $('#bl-total', m.el).textContent = 'Bill total ' + RB.rupees(t) + ' + GST ' + RB.rupees(g) + ' = ' + RB.rupees(t + g);
    };
    $$('input', m.el).forEach((el) => el.addEventListener('input', calc)); calc();
    $('#bl-save', m.el).addEventListener('click', async () => {
      try {
        const lines = x.lines.map((l, i) => ({ line_id: l.id, qty: num($('[data-q="' + i + '"]', m.el).value), rate_paise: RB.toPaise($('[data-r="' + i + '"]', m.el).value),
          gst_paise: RB.toPaise($('[data-g="' + i + '"]', m.el).value) }));
        await RB.rpc('rb_enter_supplier_bill', { p: { purchase_id: p.id, bill_no: $('#bl-no', m.el).value, bill_date: $('#bl-date', m.el).value,
          payment_mode: $('#bl-mode', m.el).value, reference: $('#bl-ref', m.el).value, lines } });
        RB.toast('Bill saved'); m.close(); done();
      } catch (e) { RB.modalMsg(m, e.message); m.el.scrollTop = 0; }
    });
  }

  // ---------- direct purchase form ----------
  async function directModal(x, done) {
    const d = await lists();
    const p = x ? x.purchase : { purchase_date: RB.today(), payment_mode: 'cash', department_id: defaultDept(d) };
    let lines = x ? x.lines.map((l) => ({ item_id: l.item_id, unit_code: l.unit_code, qty: l.received_qty, rate: RB.fromPaise(l.bill_rate_paise), gst: RB.fromPaise(l.bill_gst_paise) })) : [{}];
    const limit = d.settings.direct_purchase_approval_limit_paise;
    const m = RB.modal('<h2>' + (x ? 'Change direct purchase' : 'Direct purchase (no PO)') + '</h2><div class="m-msg"></div>' +
      '<p class="muted">For buys that cannot wait for an order: fish and meat from fishermen or local suppliers, small cash buys, urgent top-ups. ' +
      'Goods received and the bill are entered together.' + (limit != null ? ' Above ' + RB.rupees(limit) + ' it waits for approval by the Accountant, FC or a Director.' : '') + '</p>' +
      '<div class="row">' + supplierPicker(d, 'dp-sup', p.supplier_id) +
      RB.field('dp-date', 'Date', '<input type="date" id="dp-date" value="' + esc(p.purchase_date) + '">', null, true) +
      RB.field('dp-mode', 'Payment', RB.sel('dp-mode', [['cash', 'Cash'], ['upi', 'UPI'], ['bank', 'Bank'], ['credit', 'Credit (pay later)']], p.payment_mode), null, true) + '</div>' +
      '<div class="row">' + RB.field('dp-reason', 'Reason there is no order', '<input id="dp-reason" list="dp-reasons" value="' + esc(p.reason || '') + '"><datalist id="dp-reasons">' +
        REASONS.map((r) => '<option value="' + esc(r) + '">').join('') + '</datalist>', null, true) +
      RB.field('dp-dept', 'Department', RB.sel('dp-dept', deptOptions(d), p.department_id)) + '</div>' +
      '<label class="check"><input type="checkbox" id="dp-nobill"' + (p.no_supplier_bill ? ' checked' : '') + '> No supplier bill (e.g. fishermen)</label>' +
      '<div class="row" id="dp-billrow">' + RB.field('dp-billno', 'Supplier\'s bill number', RB.inp('dp-billno', p.no_supplier_bill ? '' : p.bill_no), null, true) +
      RB.field('dp-billdate', 'Bill date', '<input type="date" id="dp-billdate" value="' + esc(p.bill_date || p.purchase_date) + '">') + '</div>' +
      '<div id="dp-nobillrow" class="msg info">With no bill, the GRN number is the reference. Add a photo of the catch or the weighing slip, or a note.</div>' +
      '<div class="row">' + RB.field('dp-photo', 'Photo (catch, weighing slip or bill)', '<input type="file" id="dp-photo" accept="image/*" capture="environment">') +
      RB.field('dp-note', 'Note', RB.inp('dp-note', p.note, ' placeholder="e.g. weighing slip no. 0412"')) + '</div>' +
      '<div id="dp-lines"></div><div class="actions"><button type="button" id="dp-add">+ Add a line</button></div><p id="dp-total" style="font-weight:600"></p>' +
      '<div class="actions"><button class="primary" id="dp-save">Save purchase</button><button data-close>Cancel</button></div>', { wide: true });
    wireSupplierAdd(m, d, (sid) => { const s = d.sup[sid]; if (s && s.usually_no_bill) { $('#dp-nobill', m.el).checked = true; sync(); } });
    const nobill = () => $('#dp-nobill', m.el).checked;
    const sync = () => {
      $('#dp-billrow', m.el).classList.toggle('hidden', nobill());
      $('#dp-nobillrow', m.el).classList.toggle('hidden', !nobill());
      draw();
    };
    $('#dp-sup', m.el).addEventListener('change', (e) => { const s = d.sup[e.target.value]; if (s && !x) { $('#dp-nobill', m.el).checked = !!s.usually_no_bill; sync(); } });
    $('#dp-nobill', m.el).addEventListener('change', sync);
    const draw = () => {
      $('#dp-lines', m.el).innerHTML = '<div class="grid-wrap"><table class="ticks lines"><thead><tr><th>Item</th><th>Unit</th><th>Quantity or weight</th><th>Rate ₹</th><th>Amount</th>' +
        (nobill() ? '' : '<th>GST ₹</th>') + '<th></th></tr></thead><tbody>' +
        lines.map((l, i) => '<tr><td style="min-width:200px">' + RB.sel('dl-item-' + i, [['', 'Choose…']].concat(d.buyItems.map((it) => [it.id, it.name])), l.item_id, ' data-f="item_id" data-i="' + i + '"') + '</td>' +
          '<td style="min-width:90px">' + RB.sel('dl-unit-' + i, d.unitsFor(l.item_id).map((u) => [u.code, u.code]), l.unit_code, ' data-f="unit_code" data-i="' + i + '"') + '</td>' +
          '<td style="min-width:100px"><input data-f="qty" data-i="' + i + '" inputmode="decimal" value="' + esc(l.qty == null ? '' : l.qty) + '"></td>' +
          '<td style="min-width:100px"><input data-f="rate" data-i="' + i + '" inputmode="decimal" value="' + esc(l.rate == null ? '' : l.rate) + '"></td>' +
          '<td style="text-align:right" data-amt="' + i + '"></td>' +
          (nobill() ? '' : '<td style="min-width:90px"><input data-f="gst" data-i="' + i + '" inputmode="decimal" value="' + esc(l.gst == null ? '' : l.gst) + '"></td>') +
          '<td><button type="button" data-del="' + i + '" aria-label="Remove line">✕</button></td></tr>').join('') + '</tbody></table></div>';
      $$('#dp-lines [data-f]', m.el).forEach((el) => el.addEventListener(el.tagName === 'SELECT' ? 'change' : 'input', () => {
        const l = lines[el.dataset.i]; l[el.dataset.f] = el.value;
        if (el.dataset.f === 'item_id') { const it = d.item[el.value]; l.item_id = Number(el.value) || null; if (it) l.unit_code = d.unitOf(it); draw(); return; }
        total();
      }));
      $$('#dp-lines [data-del]', m.el).forEach((b) => b.addEventListener('click', () => { lines.splice(Number(b.dataset.del), 1); if (!lines.length) lines.push({}); draw(); }));
      total();
    };
    const total = () => {
      let t = 0;
      lines.forEach((l, i) => {
        let a = 0, g = 0; try { a = lineAmt(num(l.qty), RB.toPaise(l.rate)); g = nobill() ? 0 : (RB.toPaise(l.gst) || 0); } catch (e) { a = 0; }
        t += a + g; const c = $('[data-amt="' + i + '"]', m.el); if (c) c.textContent = a ? RB.rupees(a) : '';
      });
      $('#dp-total', m.el).innerHTML = 'Total ' + RB.rupees(t) + (limit != null && t > limit ? ' · <span class="diff">above the ' + RB.rupees(limit) + ' limit: needs approval</span>' : '');
    };
    $('#dp-add', m.el).addEventListener('click', () => { lines.push({}); draw(); });
    sync();
    $('#dp-save', m.el).addEventListener('click', async () => {
      const btn = $('#dp-save', m.el); btn.disabled = true;
      try {
        const photo = await P.photoToDataUrl($('#dp-photo', m.el).files[0]);
        const out = lines.filter((l) => l.item_id || l.qty).map((l) => ({ item_id: l.item_id, unit_code: l.unit_code || null, qty: num(l.qty), rate_paise: RB.toPaise(l.rate),
          gst_paise: nobill() ? 0 : RB.toPaise(l.gst) }));
        const newId = await RB.rpc('rb_save_direct_purchase', { p: { id: x ? p.id : null, supplier_id: Number($('#dp-sup', m.el).value) || null,
          purchase_date: $('#dp-date', m.el).value, payment_mode: $('#dp-mode', m.el).value, reason: $('#dp-reason', m.el).value,
          department_id: Number($('#dp-dept', m.el).value) || null, no_supplier_bill: nobill(), bill_no: nobill() ? null : $('#dp-billno', m.el).value,
          bill_date: nobill() ? null : $('#dp-billdate', m.el).value, note: $('#dp-note', m.el).value, photo, lines: out } });
        m.close(); RB.toast('Purchase saved');
        if (done) done(); else open(newId);
      } catch (e) { btn.disabled = false; RB.modalMsg(m, e.message); m.el.scrollTop = 0; }
    });
  }

  // ---------- return form ----------
  function returnModal(x, done) {
    const p = x.purchase;
    const m = RB.modal('<h2>Return goods to ' + esc(p.supplier_name) + '</h2><div class="m-msg"></div>' +
      '<p class="muted">Goods leave stock. ' + (p.bill_posted_at ? 'The bill is in, so the supplier balance goes down (with its GST).' : 'There is no bill yet, so the bill should come for the rest only.') +
      ' A return number (PRN/YYMM/00001) is given when you save.</p>' +
      '<div class="row">' + RB.field('rt-date', 'Return date', '<input type="date" id="rt-date" value="' + RB.today() + '">', null, true) + '</div>' +
      '<div class="grid-wrap"><table class="ticks lines"><thead><tr><th>Item</th><th>Can return</th><th>Return now</th></tr></thead><tbody>' +
      x.lines.map((l, i) => '<tr><td style="text-align:left">' + esc(l.item_name) + '</td><td>' + q(Number(l.received_qty) - Number(l.rejected_qty) - Number(l.returned_qty)) + ' ' + esc(l.unit_code) + '</td>' +
        '<td style="min-width:110px"><input data-rq="' + i + '" inputmode="decimal"></td></tr>').join('') + '</tbody></table></div>' +
      RB.field('rt-why', 'Reason', '<textarea id="rt-why" placeholder="e.g. spoilt, wrong size"></textarea>', null, true) +
      '<div class="actions"><button class="primary" id="rt-save">Save return</button><button data-close>Cancel</button></div>', { wide: true });
    $('#rt-save', m.el).addEventListener('click', async () => {
      try {
        const lines = x.lines.map((l, i) => ({ line_id: l.id, qty: num($('[data-rq="' + i + '"]', m.el).value) }));
        await RB.rpc('rb_return_to_supplier', { p: { purchase_id: p.id, return_date: $('#rt-date', m.el).value, reason: $('#rt-why', m.el).value, lines } });
        RB.toast('Return saved'); m.close(); done();
      } catch (e) { RB.modalMsg(m, e.message); }
    });
  }

  // ---------- pay a supplier ----------
  // o: { supplier_id, purchase_id or expense_id (start with this bill), allocateOnly (an existing payment's remainder) }
  // Lists purchase bills and expense bills on credit (module 6).
  async function payModal(o, done) {
    o = o || {};
    const d = await lists();
    const alloc = o.allocateOnly;
    const m = RB.modal('<h2>' + (alloc ? 'Set ' + esc(alloc.payment_no) + ' against bills' : 'Pay a supplier') + '</h2><div class="m-msg"></div>' +
      '<div class="row">' + (alloc ? '<div class="field"><label>Supplier</label><p>' + esc(alloc.supplier) + '</p></div>' : supplierPicker(d, 'pay-sup', o.supplier_id)) +
      (alloc ? '<div class="field"><label>Left to set against bills</label><p>' + RB.rupees(alloc.on_account) + '</p></div>' :
        RB.field('pay-date', 'Date paid', '<input type="date" id="pay-date" value="' + RB.today() + '">', null, true) +
        RB.field('pay-mode', 'How', RB.sel('pay-mode', [['cash', 'Cash'], ['upi', 'UPI'], ['bank', 'Bank']], 'bank'), null, true) +
        RB.field('pay-acc', 'Paid from', '<select id="pay-acc"></select>')) + '</div>' +
      (alloc ? '' : '<div class="row">' + RB.field('pay-amt', 'Amount paid (₹)', RB.inp('pay-amt', '', ' inputmode="decimal"'), 'Leave as filled to pay the bills ticked below. More than the bills is kept "on account".', true) +
        RB.field('pay-ref', 'Reference', RB.inp('pay-ref', '', ' placeholder="UPI, NEFT or cheque no."')) + '</div>') +
      '<h3>Open bills</h3><div id="pay-bills"><p class="muted">Choose the supplier.</p></div>' +
      '<div class="actions"><button class="primary" id="pay-save">' + (alloc ? 'Save' : 'Save payment') + '</button><button data-close>Cancel</button></div>', { wide: true });
    wireSupplierAdd(m, d);
    // Which cash or bank account the money came from (module 6).
    let accts = [];
    try { accts = await RB.select('money_accounts', 'id,name,kind,is_default,is_active', (x) => x.eq('is_active', true).order('sort')); } catch (e) { accts = []; }
    const fillAcc = () => {
      const sel = $('#pay-acc', m.el); if (!sel) return;
      const kind = $('#pay-mode', m.el).value === 'cash' ? 'cash' : 'bank';
      const list = accts.filter((a) => a.kind === kind);
      sel.innerHTML = list.length ? list.map((a) => '<option value="' + a.id + '"' + (a.is_default ? ' selected' : '') + '>' + esc(a.name) + '</option>').join('')
        : '<option value="">Main ' + kind + ' account</option>';
    };
    if (!alloc) { fillAcc(); $('#pay-mode', m.el).addEventListener('change', fillAcc); }
    let bills = [];
    const supId = () => (alloc ? alloc.supplier_id : Number($('#pay-sup', m.el).value) || null);
    const load = async () => {
      const sid = supId(); const box = $('#pay-bills', m.el);
      if (!sid) { box.innerHTML = '<p class="muted">Choose the supplier.</p>'; bills = []; return; }
      let rows = [];
      if (RB.has('purchases.view')) rows = await RB.select('purchases', 'id,po_no,bill_no,bill_date,purchase_date,outstanding_paise,open_discrepancies,status,is_demo', (x) => x.eq('supplier_id', sid).order('id'));
      bills = rows.filter((r) => r.outstanding_paise > 0 && ['billed'].includes(r.status)).map((r) => Object.assign({ kind: 'purchase' }, r));
      // Expense bills on credit (module 6), e.g. a repair or the gas bill.
      let exp = [];
      try { exp = await RB.select('expenses', 'id,expense_no,bill_no,bill_date,expense_date,description,outstanding_paise,is_demo', (x) => x.eq('supplier_id', sid).eq('status', 'posted').gt('outstanding_paise', 0).order('id')); } catch (e) { exp = []; }
      bills = bills.concat(exp.map((r) => ({ kind: 'expense', id: r.id, bill_no: r.bill_no, po_no: r.expense_no + ' · ' + r.description, bill_date: r.bill_date || r.expense_date,
        outstanding_paise: r.outstanding_paise, open_discrepancies: 0, is_demo: r.is_demo })));
      if (!bills.length) { box.innerHTML = '<p class="muted">No unpaid bills for this supplier' + (alloc ? '.' : '. A payment now is kept on account (an advance).') + '</p>'; return; }
      let left = alloc ? alloc.on_account : null;
      box.innerHTML = '<div class="grid-wrap"><table class="ticks lines"><thead><tr><th>Bill</th><th>Order or expense</th><th>Date</th><th>Owed</th><th>Pay now ₹</th></tr></thead><tbody>' +
        bills.map((b, i) => {
          const blocked = b.open_discrepancies > 0;
          let fill = '';
          const wanted = o.expense_id ? b.kind === 'expense' && String(b.id) === String(o.expense_id)
            : o.purchase_id ? b.kind === 'purchase' && String(b.id) === String(o.purchase_id) : true;
          if (!blocked && wanted) {
            const v = left == null ? b.outstanding_paise : Math.min(left, b.outstanding_paise);
            if (v > 0) { fill = RB.fromPaise(v); if (left != null) left -= v; }
          }
          return '<tr><td>' + esc(b.bill_no || '') + RB.demoBadge(b) + '</td><td>' + esc(b.po_no || '') + '</td><td>' + RB.fmtDate(b.bill_date || b.purchase_date) + '</td><td style="text-align:right">' + RB.rupees(b.outstanding_paise) + '</td>' +
            '<td style="min-width:120px">' + (blocked ? '<span class="diff">' + b.open_discrepancies + ' difference(s) to settle first</span>' : '<input data-pay="' + i + '" inputmode="decimal" value="' + fill + '">') + '</td></tr>';
        }).join('') + '</tbody></table></div>';
      const sum = () => {
        let t = 0; $$('[data-pay]', box).forEach((el) => { try { t += RB.toPaise(el.value) || 0; } catch (e) { /* later */ } });
        if (!alloc && $('#pay-amt', m.el)) $('#pay-amt', m.el).value = t ? RB.fromPaise(t) : '';
      };
      $$('[data-pay]', box).forEach((el) => el.addEventListener('input', sum)); sum();
    };
    if (!alloc) $('#pay-sup', m.el).addEventListener('change', () => load().catch((e) => RB.modalMsg(m, e.message)));
    await load().catch((e) => RB.modalMsg(m, e.message));
    $('#pay-save', m.el).addEventListener('click', async () => {
      try {
        const allocations = $$('[data-pay]', m.el).map((el) => {
          const b = bills[Number(el.dataset.pay)];
          return Object.assign(b.kind === 'expense' ? { expense_id: b.id } : { purchase_id: b.id }, { amount_paise: RB.toPaise(el.value) || 0 });
        }).filter((a) => a.amount_paise > 0);
        if (alloc) await RB.rpc('rb_allocate_payment', { p_payment: alloc.id, p_allocations: allocations });
        else await RB.rpc(RB.has('purchases.add') ? 'rb_pay_supplier' : 'rb_pay_expense_bill', { p: { supplier_id: supId(), pay_date: $('#pay-date', m.el).value,
          mode: $('#pay-mode', m.el).value, money_account_id: Number(($('#pay-acc', m.el) || {}).value) || null,
          amount_paise: RB.toPaise($('#pay-amt', m.el).value), reference: $('#pay-ref', m.el).value, allocations } });
        RB.toast(alloc ? 'Payment set against bills' : 'Payment saved'); m.close();
        if (done) done(); else RB.route();
      } catch (e) { RB.modalMsg(m, e.message); }
    });
  }
  P.payModal = payModal;
})();
