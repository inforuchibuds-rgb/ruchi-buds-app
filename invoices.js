// =====================================================================
// RUCHI BUDS APP · invoices.js · Version 1.2 · 27-Nov-2026
// Module 5 screens "Invoices", "Receipts" and the money side of
// "Customers": the printable invoice (Print / Save as PDF), returns and
// credit notes from an invoice, receiving money and setting it against
// invoices, refunds, customer balances with ageing, the customer ledger
// and statement, and a statement link a customer can open without
// signing in.
// =====================================================================
(function () {
  'use strict';
  const RB = window.RB, $ = RB.$, $$ = RB.$$, esc = RB.esc;
  const I = (RB.invoices = {});
  const SA = () => RB.sales;
  const on = (root, sel, fn, ev) => { const b = $(sel, root); if (b) b.addEventListener(ev || 'click', fn); };
  const money = () => RB.has('power.see_totals');
  const amt = (p) => (p == null || Number(p) === 0 ? '' : RB.rupees(p));
  const fy = () => { const t = RB.today(); return (Number(t.slice(5, 7)) >= 4 ? t.slice(0, 4) : String(Number(t.slice(0, 4)) - 1)) + '-04-01'; };
  const MODES3 = [['cash', 'Cash'], ['upi', 'UPI'], ['bank', 'Bank']];
  const STATES = { '01': 'Jammu and Kashmir', '02': 'Himachal Pradesh', '03': 'Punjab', '04': 'Chandigarh', '05': 'Uttarakhand', '06': 'Haryana',
    '07': 'Delhi', '08': 'Rajasthan', '09': 'Uttar Pradesh', '10': 'Bihar', '11': 'Sikkim', '12': 'Arunachal Pradesh', '13': 'Nagaland',
    '14': 'Manipur', '15': 'Mizoram', '16': 'Tripura', '17': 'Meghalaya', '18': 'Assam', '19': 'West Bengal', '20': 'Jharkhand', '21': 'Odisha',
    '22': 'Chhattisgarh', '23': 'Madhya Pradesh', '24': 'Gujarat', '26': 'Dadra and Nagar Haveli and Daman and Diu', '27': 'Maharashtra',
    '29': 'Karnataka', '30': 'Goa', '31': 'Lakshadweep', '32': 'Kerala', '33': 'Tamil Nadu', '34': 'Puducherry', '35': 'Andaman and Nicobar Islands',
    '36': 'Telangana', '37': 'Andhra Pradesh', '38': 'Ladakh' };
  const stateName = (c) => (c ? c + (STATES[c] ? ' ' + STATES[c] : '') : '');

  // ₹ amount in words, Indian style: "Rupees One Thousand Two Hundred and Fifty and Fifty Paise Only".
  const ONES = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen',
    'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
  const TENS = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
  const two = (n) => (n < 20 ? ONES[n] : TENS[Math.floor(n / 10)] + (n % 10 ? ' ' + ONES[n % 10] : ''));
  const three = (n) => (n >= 100 ? ONES[Math.floor(n / 100)] + ' Hundred' + (n % 100 ? ' and ' + two(n % 100) : '') : two(n));
  I.words = (paise) => {
    paise = Math.abs(Math.round(Number(paise) || 0));
    let r = Math.floor(paise / 100); const p = paise % 100;
    if (r === 0) return p ? two(p) + ' Paise Only' : 'Rupees Zero Only';
    const parts = [];
    const crore = Math.floor(r / 10000000); r %= 10000000;
    const lakh = Math.floor(r / 100000); r %= 100000;
    const thou = Math.floor(r / 1000); r %= 1000;
    if (crore) parts.push((crore >= 1000 ? I.words(crore * 100).replace(/^Rupees | Only$/g, '') : three(crore)) + ' Crore');
    if (lakh) parts.push(two(lakh) + ' Lakh');
    if (thou) parts.push(two(thou) + ' Thousand');
    if (r) parts.push(three(r));
    return (parts.length ? 'Rupees ' + parts.join(' ') : 'Rupees Zero') + (p ? ' and ' + two(p) + ' Paise' : '') + ' Only';
  };

  // ===================================================================
  // Invoices screen: the list, and the invoice window
  // ===================================================================
  RB.screens.invoices = async (body, arg) => {
    if (arg && /^\d+$/.test(arg)) return I.window(body, Number(arg), 'invoices');
    const tools = $('#page-tools');
    if (tools) tools.innerHTML = (RB.has('sales.add') ? '<a class="btn primary" href="#/sales/new">+ New sale</a>' : '') +
      (RB.has('receipts.add') ? '<button id="iv-recv">Receive a payment</button>' : '');
    on(document, '#iv-recv', () => I.receiveModal({}));
    body.innerHTML = '<div id="iv-body"></div>';
    await SA().listTab($('#iv-body', body), 'invoices');
  };

  const firmHead = (f, title) => '<div class="inv-head"><div class="inv-brand"><img src="' + esc(f.wordmark_url || 'assets/wordmark.png') + '" alt="' + esc(f.firm_name) + '"></div>' +
    '<div class="inv-firm"><b>' + esc(f.firm_name) + (f.legal_form === 'LLP' ? ' LLP' : '') + '</b>' + (f.address ? '<br>' + esc(f.address).replace(/\n/g, '<br>') : '') +
    ([f.phone ? 'Phone ' + esc(f.phone) : '', f.email ? esc(f.email) : ''].filter(Boolean).map((t, i) => (i ? ' · ' : '<br>') + t).join('')) +
    (f.fssai_no ? '<br>FSSAI no. ' + esc(f.fssai_no) : '') +
    (f.legal_form === 'LLP' && f.llpin ? '<br>LLPIN ' + esc(f.llpin) : f.firm_reg_no ? '<br>Firm Reg. no. ' + esc(f.firm_reg_no) : '') +
    (title.gstin && f.gstin ? '<br><b>GSTIN ' + esc(f.gstin) + '</b>' : '') + '</div>' +
    '<div class="inv-title">' + esc(title.text) + '</div></div>';

  I.window = async (body, id, base) => {
    const back = $('.page-head .back');
    if (back) { back.href = '#/' + base; back.hidden = false; back.textContent = '‹ ' + (base === 'invoices' ? 'Invoices' : 'Sales'); }
    const x = await RB.rpc('rb_sale_detail', { p_id: id });
    const s = x.sale, f = x.firm || {}, tax = s.doc_type === 'tax_invoice';
    const h1 = $('.page-head h1'); if (h1) h1.innerHTML = esc(s.invoice_no) + RB.demoBadge(s);
    const hsn = tax && s.show_hsn;
    const gstCols = tax ? (s.inter_state ? ['IGST'] : ['CGST', 'SGST']) : [];
    const lineRow = (l, n) => {
      const qtyTxt = l.packs != null ? RB.esc(Number(l.packs)) : SA().q(l.qty_base, l.base_unit);
      const rateTxt = RB.rupees(l.rate_paise) + (l.packs == null ? ' /' + (l.base_unit === 'pc' ? 'pc' : l.base_unit === 'ml' ? 'l' : 'kg') : '');
      const gst = tax ? (s.inter_state ? '<td class="n">' + RB.rupees(l.igst_paise) + '<small>' + Number(l.gst_rate) + '%</small></td>'
        : '<td class="n">' + RB.rupees(l.cgst_paise) + '<small>' + Number(l.gst_rate) / 2 + '%</small></td><td class="n">' + RB.rupees(l.sgst_paise) + '<small>' + Number(l.gst_rate) / 2 + '%</small></td>') : '';
      const ret = Number(l.returned_qty_base) > 0 ? '<div class="hint no-print">Returned: ' + SA().q(l.returned_qty_base, l.base_unit) + '</div>' : '';
      return '<tr><td>' + n + '</td><td>' + esc(l.description) + ret + '</td>' + (hsn ? '<td>' + esc(l.hsn_code || '') + '</td>' : '') +
        '<td class="n">' + qtyTxt + '</td><td class="n">' + rateTxt + '</td><td class="n">' + RB.rupees(l.gross_paise) + '</td>' +
        '<td class="n">' + (Number(l.discount_paise) ? RB.rupees(l.discount_paise) : '') + '</td>' +
        (tax ? '<td class="n">' + RB.rupees(l.taxable_paise) + '</td>' : '') + gst + '<td class="n"><b>' + RB.rupees(l.total_paise) + '</b></td></tr>';
    };
    const colsBefore = 5 + (hsn ? 1 : 0);
    const owed = Number(s.outstanding_paise);
    body.innerHTML =
      (s.status === 'cancelled' ? '<div class="msg error">Cancelled on ' + RB.fmtDate(s.cancelled_at) + ': ' + esc(s.cancel_reason || '') + '</div>' : '') +
      '<div class="actions no-print" id="iw-actions">' +
      '<button class="primary" id="iw-print">Print / Save as PDF</button>' +
      (x.can.return ? '<button id="iw-ret">Goods returned</button>' : '') +
      (x.can.receive ? '<button id="iw-recv">Receive payment</button>' : '') +
      (RB.has('power.refunds') && x.returns.some((r) => r.status === 'posted') ? '<button id="iw-refund">Refund the customer</button>' : '') +
      (x.can.write_off ? '<button class="danger" id="iw-wo">Write off as bad debt</button>' : '') +
      (RB.has('sales.add') ? '<a class="btn" href="#/sales/new">+ New sale</a>' : '') +
      (x.can.cancel ? '<button class="danger" id="iw-cancel">Cancel invoice</button>' : '') +
      (x.can.delete ? '<button class="danger" id="iw-del">Delete fully (learning phase)</button>' : '') + '</div>' +
      '<div class="invoice' + (s.status === 'cancelled' ? ' cancelled' : '') + '">' +
      firmHead(f, { text: tax ? 'TAX INVOICE' : 'INVOICE', gstin: tax }) +
      '<div class="inv-meta"><div><span class="muted">Bill to</span><br><b>' + esc(s.bill_name) + '</b>' +
      (s.bill_address ? '<br>' + esc(s.bill_address).replace(/\n/g, '<br>') : '') + (s.bill_phone ? '<br>Phone ' + esc(s.bill_phone) : '') +
      (s.bill_gstin ? '<br>GSTIN ' + esc(s.bill_gstin) : '') + '</div>' +
      '<div><table class="kv"><tr><td>Invoice no.</td><td><b>' + esc(s.invoice_no) + '</b></td></tr><tr><td>Date</td><td>' + RB.fmtDate(s.invoice_date) + '</td></tr>' +
      (tax ? '<tr><td>Place of supply</td><td>' + esc(stateName(s.place_of_supply)) + '</td></tr>' : '') +
      (s.due_date && owed > 0 ? '<tr><td>Due by</td><td>' + RB.fmtDate(s.due_date) + '</td></tr>' : '') +
      '<tr><td>Payment</td><td>' + esc(SA().MODES[s.payment_mode]) + (s.payment_ref ? ', ref ' + esc(s.payment_ref) : '') + '</td></tr></table></div></div>' +
      '<div class="grid-wrap"><table class="inv-lines"><thead><tr><th>#</th><th>Item</th>' + (hsn ? '<th>HSN</th>' : '') + '<th class="n">Qty</th><th class="n">Rate</th><th class="n">Amount</th><th class="n">Discount</th>' +
      (tax ? '<th class="n">Taxable</th>' : '') + gstCols.map((g) => '<th class="n">' + g + '</th>').join('') + '<th class="n">Total</th></tr></thead><tbody>' +
      x.lines.map((l, i) => lineRow(l, i + 1)).join('') +
      (Number(s.delivery_paise) ? '<tr><td></td><td>Delivery charge</td>' + (hsn ? '<td></td>' : '') + '<td></td><td></td><td class="n">' + RB.rupees(s.delivery_paise) + '</td><td></td>' +
        (tax ? '<td class="n">' + RB.rupees(s.delivery_paise) + '</td>' + (s.inter_state ? '<td class="n">' + RB.rupees(s.delivery_gst_paise) + '</td>'
          : '<td class="n">' + RB.rupees(Math.round(Number(s.delivery_gst_paise) / 2)) + '</td><td class="n">' + RB.rupees(Number(s.delivery_gst_paise) - Math.round(Number(s.delivery_gst_paise) / 2)) + '</td>') : '') +
        '<td class="n"><b>' + RB.rupees(Number(s.delivery_paise) + Number(s.delivery_gst_paise)) + '</b></td></tr>' : '') +
      '</tbody><tfoot><tr><td colspan="' + colsBefore + '" class="n">Totals</td>' +
      '<td class="n">' + RB.rupees(s.discount_paise) + '</td>' + (tax ? '<td class="n">' + RB.rupees(s.taxable_paise) + '</td>' : '') +
      (tax ? (s.inter_state ? '<td class="n">' + RB.rupees(s.igst_paise) + '</td>' : '<td class="n">' + RB.rupees(s.cgst_paise) + '</td><td class="n">' + RB.rupees(s.sgst_paise) + '</td>') : '') +
      '<td class="n"><b>' + RB.rupees(s.total_paise) + '</b></td></tr></tfoot></table></div>' +
      '<div class="inv-foot"><div><p><b>' + esc(I.words(s.total_paise)) + '</b></p>' +
      (tax ? '<p class="muted">' + (s.prices_include_gst ? 'Prices include GST.' : 'GST added to the prices.') + '</p>' : '<p class="muted">The firm is not registered under GST, so no GST is charged.</p>') +
      (s.note ? '<p>' + esc(s.note) + '</p>' : '') + (f.invoice_footer ? '<p>' + esc(f.invoice_footer).replace(/\n/g, '<br>') + '</p>' : '') + '</div>' +
      '<table class="sum"><tr><td>Invoice total</td><td><b>' + RB.rupees(s.total_paise) + '</b></td></tr>' +
      (Number(s.paid_at_sale_paise) ? '<tr><td>Paid at the sale</td><td>' + RB.rupees(s.paid_at_sale_paise) + '</td></tr>' : '') +
      (Number(s.credited_paise) ? '<tr><td>Paid later and credit notes</td><td>' + RB.rupees(s.credited_paise) + '</td></tr>' : '') +
      (Number(s.written_off_paise) ? '<tr class="no-print"><td>Written off as bad debt</td><td>' + RB.rupees(s.written_off_paise) + '</td></tr>' : '') +
      (s.status !== 'cancelled' ? '<tr class="grand"><td>' + (owed > 0 ? 'Balance due' : Number(s.written_off_paise) ? 'Closed' : 'Paid in full') + '</td><td>' + (owed > 0 ? RB.rupees(owed) : '✓') + '</td></tr>' : '') + '</table></div>' +
      '<p class="inv-sign">For ' + esc(f.firm_name) + '<br><br><br>Authorised signatory</p>' +
      '<p class="muted inv-small">This is a computer-generated ' + (tax ? 'tax invoice' : 'invoice') + '.</p></div>' +
      '<div class="no-print">' +
      (x.returns.length ? '<div class="card"><h2>Goods returned</h2><table class="ticks lines"><thead><tr><th>Credit note</th><th>Date</th><th>Reason</th><th>Goods</th>' + (money() ? '<th>Value</th>' : '') + '<th>Status</th></tr></thead><tbody>' +
        x.returns.map((r, i) => '<tr data-ret="' + i + '" class="click"><td>' + esc(r.return_no || '(not yet numbered)') + RB.demoBadge(r) + '</td><td>' + RB.fmtDate(r.return_date) + '</td><td>' + esc(r.reason) + '</td><td>' +
          (r.condition === 'restock' ? 'Back on the shelf' : 'Thrown away') + '</td>' + (money() ? '<td style="text-align:right">' + RB.rupees(r.total_paise) + '</td>' : '') +
          '<td>' + RB.badge(SA().RET_BADGE[r.status], SA().RET_STATUS[r.status]) + '</td></tr>').join('') + '</tbody></table></div>' : '') +
      ((x.write_offs || []).length ? '<div class="card"><h2>Written off as bad debt</h2><table class="ticks lines"><thead><tr><th>Write-off</th><th>Date</th><th>Reason</th><th>Amount</th><th>Recovered</th><th>Status</th></tr></thead><tbody>' +
        x.write_offs.map((w, i) => '<tr data-wo="' + i + '" class="click"><td>' + esc(w.write_off_no) + RB.demoBadge(w) + '</td><td>' + RB.fmtDate(w.write_off_date) + '</td><td>' + esc(w.reason) + '</td><td style="text-align:right">' +
          RB.rupees(w.amount_paise) + '</td><td style="text-align:right">' + amt(w.recovered_paise) + '</td><td>' + (w.status === 'posted' ? RB.badge('active', 'Posted') : RB.badge('inactive', 'Reversed')) + '</td></tr>').join('') +
        '</tbody></table></div>' : '') +
      (x.payments.length && money() ? '<div class="card"><h2>Payments set against this invoice</h2><table class="ticks lines"><thead><tr><th>Document</th><th>Date</th><th>Amount</th><th>Status</th></tr></thead><tbody>' +
        x.payments.map((p) => '<tr><td>' + esc(p.ref) + (p.kind === 'credit_note' ? ' (credit note)' : '') + '</td><td>' + RB.fmtDate(p.date) + '</td><td style="text-align:right">' + RB.rupees(p.amount_paise) + '</td><td>' +
          (p.status === 'posted' ? RB.badge('active', 'Posted') : RB.badge('inactive', 'Reversed')) + '</td></tr>').join('') + '</tbody></table></div>' : '') +
      (x.can.see_cost && s.cost_paise != null ? '<div class="card"><h2>Margin (only for the margin tick)</h2><p>Cost of the goods ' + RB.rupees(s.cost_paise) + ' · net sale ' + RB.rupees(s.taxable_paise) +
        ' · margin <b>' + RB.rupees(Number(s.taxable_paise) - Number(s.cost_paise)) + '</b></p></div>' : '') +
      '<p class="muted">Entered by ' + esc(s.entered_by_name || '') + ' on ' + RB.fmtDateTime(s.entered_at) + '.</p></div>';
    const reload = () => RB.route();
    on(body, '#iw-print', () => window.print());
    on(body, '#iw-ret', () => returnFromInvoice(x, reload));
    on(body, '#iw-recv', () => I.receiveModal({ customer_id: s.customer_id, sale_id: s.id }, reload));
    on(body, '#iw-wo', () => I.writeOffModal({ customer_id: s.customer_id, customer_name: s.bill_name, sale_id: s.id, invoice_no: s.invoice_no, owed }, reload));
    $$('[data-wo]', body).forEach((tr) => tr.addEventListener('click', async () => {
      const w = x.write_offs[Number(tr.dataset.wo)];
      const full = (await RB.rpc('rb_bad_debts_list')).find((z) => z.id === w.id);
      if (full) I.badDebtModal(full, reload);
    }));
    on(body, '#iw-refund', () => { const r = x.returns.filter((z) => z.status === 'posted').pop(); I.refundModal({ customer_id: s.customer_id, return_id: r.id }, reload); });
    on(body, '#iw-cancel', () => SA().reverseModal('Cancel ' + s.invoice_no,
      'The invoice stays in the list marked Cancelled, its number is not used again, the goods go back into stock and the books are reversed on the date below.',
      (dt, why) => RB.rpc('rb_cancel_sale', { p_id: s.id, p_date: dt, p_reason: why }), reload, 'Cancel invoice'));
    on(body, '#iw-del', async () => {
      if (!(await RB.confirm('Delete ' + s.invoice_no + ' fully?', 'Only for invoices entered by someone still in their learning phase. The invoice, its stock movement and its journal disappear. After go-live this leaves a gap in the invoice numbers.'))) return;
      try { await RB.rpc('rb_hard_delete_sale', { p_id: s.id }); RB.toast('Invoice deleted'); location.hash = '#/' + base; } catch (e) { RB.toast(e.message, true); }
    });
    $$('[data-ret]', body).forEach((tr) => tr.addEventListener('click', async () => {
      const r = x.returns[Number(tr.dataset.ret)];
      const all = await RB.rpc('rb_sales_returns_list');
      const full = all.find((z) => z.id === r.id);
      if (full) SA().returnModal(full, reload);
    }));
  };

  // ---------- goods returned on an invoice ----------
  function returnFromInvoice(x, done) {
    const s = x.sale;
    const rows = x.lines.map((l) => {
      const left = Number(l.qty_base) - Number(l.returned_qty_base) - Number(l.pending_qty_base);
      const per = l.packs != null ? Number(l.qty_base) / Number(l.packs) : null;
      return Object.assign({}, l, { left, packsLeft: per ? Math.round(left / per) : null });
    });
    const big = (u) => (u === 'g' ? 'kg' : u === 'ml' ? 'l' : u);
    const m = RB.modal('<h2>Goods returned on ' + esc(s.invoice_no) + '</h2><div class="m-msg"></div>' +
      '<p class="muted">Enter only what came back. The credit note is worth the same share of each line as the quantity, including its discount and GST. ' +
      (RB.has('sales.approve') || RB.has('power.approve_own') ? 'It posts straight away.' : 'A Manager, the Accountant, the FC or a Director approves it before it posts.') + '</p>' +
      '<div class="row">' + RB.field('sr-date', 'Date it came back', '<input type="date" id="sr-date" value="' + RB.today() + '">', null, true) +
      RB.field('sr-cond', 'What happens to the goods', RB.sel('sr-cond', [['restock', 'Back on the shelf (fit to sell)'], ['discard', 'Thrown away (damaged or spoilt)']], 'restock'), null, true) + '</div>' +
      RB.field('sr-why', 'Reason', '<textarea id="sr-why" placeholder="e.g. leaking pouch, wrong item, customer changed mind"></textarea>', null, true) +
      '<div class="grid-wrap"><table class="ticks lines"><thead><tr><th>Item</th><th>Sold</th><th>Can still come back</th><th>Came back</th></tr></thead><tbody>' +
      rows.map((l, i) => '<tr><td>' + esc(l.description) + '</td><td>' + (l.packs != null ? Number(l.packs) + ' pack(s)' : SA().q(l.qty_base, l.base_unit)) + '</td>' +
        '<td>' + (l.packs != null ? l.packsLeft + ' pack(s)' : SA().q(l.left, l.base_unit)) + '</td><td style="min-width:120px">' +
        (l.left <= 0 ? '<span class="muted">nothing left</span>' : l.packs != null ? '<input data-rq="' + i + '" inputmode="numeric" placeholder="packs">' :
          '<div style="display:flex;gap:.3rem"><input data-rq="' + i + '" inputmode="decimal" style="width:80px"><span>' + esc(big(l.base_unit)) + '</span></div>') + '</td></tr>').join('') +
      '</tbody></table></div><div class="actions"><button class="primary" id="sr-save">Save return</button><button data-close>Cancel</button></div>', { wide: true });
    on(m.el, '#sr-save', async () => {
      try {
        const lines = $$('[data-rq]', m.el).filter((el) => el.value.trim() !== '').map((el) => {
          const l = rows[Number(el.dataset.rq)];
          return l.packs != null ? { sale_line_id: l.id, packs: Number(el.value) } : { sale_line_id: l.id, qty: Number(el.value), unit: big(l.base_unit) };
        });
        await RB.rpc('rb_save_sales_return', { p: { sale_id: s.id, return_date: $('#sr-date', m.el).value, condition: $('#sr-cond', m.el).value, reason: $('#sr-why', m.el).value, lines } });
        RB.toast('Return saved'); m.close(); done();
      } catch (e) { RB.modalMsg(m, e.message); }
    });
  }

  // ===================================================================
  // Receive a payment, or set money on account against invoices
  // o: { customer_id, sale_id (start with this invoice), allocate: {kind, id, ref, left, customer_id, customer_name} }
  // ===================================================================
  I.receiveModal = async (o, done) => {
    o = o || {};
    const al = o.allocate;
    const custs = (await RB.select('customers', 'id,code,name,kind,is_walk_in,is_active,is_demo', (x) => x.order('name'))).filter((c) => !c.is_walk_in && (c.is_active || c.id === o.customer_id));
    const m = RB.modal('<h2>' + (al ? 'Set ' + esc(al.ref) + ' against invoices' : 'Receive a payment') + '</h2><div class="m-msg"></div>' +
      '<div class="row">' + (al ? '<div class="field"><label>Customer</label><p>' + esc(al.customer_name) + '</p></div><div class="field"><label>Left to set against invoices</label><p>' + RB.rupees(al.left) + '</p></div>'
        : RB.field('rc-cust', 'Customer', RB.sel('rc-cust', [['', 'Choose…']].concat(custs.map((c) => [c.id, c.name])), o.customer_id || ''), null, true) +
          RB.field('rc-date', 'Date received', '<input type="date" id="rc-date" value="' + RB.today() + '">', null, true) +
          RB.field('rc-mode', 'How', RB.sel('rc-mode', MODES3, 'upi'), null, true)) + '</div>' +
      (al ? '' : '<div class="row">' + RB.field('rc-amt', 'Amount received (₹)', RB.inp('rc-amt', '', ' inputmode="decimal"'), 'Fills in from the invoices ticked below. More than the invoices is kept on account (an advance).', true) +
        RB.field('rc-ref', 'Reference', RB.inp('rc-ref', '', ' placeholder="UPI, NEFT or cheque no."')) + RB.field('rc-note', 'Note', RB.inp('rc-note', '')) + '</div>') +
      '<h3>Open invoices</h3><div id="rc-open"><p class="muted">Choose the customer.</p></div>' +
      '<div class="actions"><button class="primary" id="rc-save">' + (al ? 'Save' : 'Save receipt') + '</button><button data-close>Cancel</button></div>', { wide: true });
    let items = [];
    const cid = () => (al ? al.customer_id : Number($('#rc-cust', m.el).value) || null);
    const load = async () => {
      const box = $('#rc-open', m.el), c = cid();
      if (!c) { box.innerHTML = '<p class="muted">Choose the customer.</p>'; items = []; return; }
      const x = await RB.rpc('rb_customer_open_items', { p_customer: c });
      items = x.invoices.map((v) => ({ sale_id: v.id, label: v.invoice_no, date: v.invoice_date, due: v.due_date, owed: Number(v.outstanding_paise), is_demo: v.is_demo }));
      if (Number(x.other_balance_paise) > 0) items.unshift({ sale_id: null, label: 'Earlier balance (not on an invoice)', date: null, owed: Number(x.other_balance_paise) });
      let left = al ? al.left : null;
      const wo = (x.write_offs || []).reduce((t, w) => t + Number(w.left_paise), 0);
      box.innerHTML = '<p>Owed in the books: <b>' + RB.rupees(x.balance_paise) + '</b>' + (Number(x.on_account_paise) > 0 && !al ? ' · already on account: ' + RB.rupees(x.on_account_paise) +
        ' (use the Receipts list to set it against invoices)' : '') + '</p>' +
        (wo > 0 && !al ? '<div class="msg info">' + RB.rupees(wo) + ' of this customer\'s debt is written off as bad. Money paid towards it: save it here (it stays on account), then book it in Customer receipts → Bad debts → Book money recovered.</div>' : '') +
        (!items.length ? '<p class="muted">Nothing open for this customer' + (al ? '.' : '. Money received now is kept on account (an advance).') + '</p>' :
          '<div class="grid-wrap"><table class="ticks lines"><thead><tr><th>Invoice</th><th>Date</th><th>Due</th><th>Owed</th><th>Set against now ₹</th></tr></thead><tbody>' +
          items.map((v, i) => {
            let fill = '';
            if (o.sale_id ? v.sale_id === o.sale_id : al) {
              const a = left == null ? v.owed : Math.min(left, v.owed);
              if (a > 0) { fill = RB.fromPaise(a); if (left != null) left -= a; }
            }
            const late = v.due && v.due < RB.today();
            return '<tr><td>' + esc(v.label) + RB.demoBadge(v) + '</td><td>' + RB.fmtDate(v.date) + '</td><td>' + (late ? '<span class="diff">' + RB.fmtDate(v.due) + '</span>' : RB.fmtDate(v.due)) + '</td>' +
              '<td style="text-align:right">' + RB.rupees(v.owed) + '</td><td style="min-width:120px"><input data-al="' + i + '" inputmode="decimal" value="' + fill + '"></td></tr>';
          }).join('') + '</tbody></table></div>' +
          (al ? '' : '<div class="actions"><button type="button" id="rc-oldest">Fill oldest first from the amount</button></div>'));
      const sum = () => {
        if (al) return; let t = 0;
        $$('[data-al]', box).forEach((el) => { try { t += RB.toPaise(el.value) || 0; } catch (e) { /* later */ } });
        if (t) $('#rc-amt', m.el).value = RB.fromPaise(t);
      };
      $$('[data-al]', box).forEach((el) => el.addEventListener('input', sum)); sum();
      on(box, '#rc-oldest', () => {
        let rest; try { rest = RB.toPaise($('#rc-amt', m.el).value) || 0; } catch (e) { return RB.modalMsg(m, e.message); }
        $$('[data-al]', box).forEach((el) => { const v = items[Number(el.dataset.al)], a = Math.min(rest, v.owed); el.value = a > 0 ? RB.fromPaise(a) : ''; rest -= Math.max(a, 0); });
      });
    };
    if (!al) on(m.el, '#rc-cust', () => load().catch((e) => RB.modalMsg(m, e.message)), 'change');
    await load().catch((e) => RB.modalMsg(m, e.message));
    on(m.el, '#rc-save', async () => {
      try {
        const allocations = $$('[data-al]', m.el).map((el) => ({ sale_id: items[Number(el.dataset.al)].sale_id, amount_paise: RB.toPaise(el.value) || 0 })).filter((a) => a.amount_paise > 0);
        if (al) await RB.rpc('rb_allocate_customer_credit', { p_kind: al.kind, p_id: al.id, p_allocations: allocations });
        else await RB.rpc('rb_receive_from_customer', { p: { customer_id: cid(), receipt_date: $('#rc-date', m.el).value, mode: $('#rc-mode', m.el).value,
          amount_paise: RB.toPaise($('#rc-amt', m.el).value), reference: $('#rc-ref', m.el).value, note: $('#rc-note', m.el).value, allocations } });
        RB.toast(al ? 'Set against invoices' : 'Receipt saved'); m.close();
        if (done) done(); else RB.route();
      } catch (e) { RB.modalMsg(m, e.message); }
    });
  };

  // ---------- refund to a customer ----------
  I.refundModal = async (o, done) => {
    o = o || {};
    const custs = (await RB.select('customers', 'id,name,is_walk_in,is_demo', (x) => x.order('name'))).sort((a, b) => b.is_walk_in - a.is_walk_in);
    const m = RB.modal('<h2>Refund a customer</h2><div class="m-msg"></div>' +
      '<p class="muted">Pays back money the customer has with us: a credit note or an overpayment not yet set against an invoice.</p>' +
      '<div class="row">' + RB.field('rf-cust', 'Customer', RB.sel('rf-cust', [['', 'Choose…']].concat(custs.map((c) => [c.id, c.name])), o.customer_id || ''), '<span id="rf-left"></span>', true) +
      RB.field('rf-date', 'Date paid back', '<input type="date" id="rf-date" value="' + RB.today() + '">', null, true) +
      RB.field('rf-mode', 'How', RB.sel('rf-mode', MODES3, 'upi'), null, true) + '</div>' +
      '<div class="row">' + RB.field('rf-amt', 'Amount (₹)', RB.inp('rf-amt', '', ' inputmode="decimal"'), null, true) + RB.field('rf-ref', 'Reference', RB.inp('rf-ref', '')) + '</div>' +
      RB.field('rf-why', 'Reason', '<textarea id="rf-why"></textarea>', null, true) +
      '<div class="actions"><button class="primary" id="rf-save">Save refund</button><button data-close>Cancel</button></div>');
    const show = async () => {
      const c = Number($('#rf-cust', m.el).value); if (!c) { $('#rf-left', m.el).textContent = ''; return; }
      const x = await RB.rpc('rb_customer_open_items', { p_customer: c });
      $('#rf-left', m.el).textContent = 'Can be refunded: ' + RB.rupees(x.refundable_paise);
      if (!$('#rf-amt', m.el).value && Number(x.refundable_paise) > 0) $('#rf-amt', m.el).value = RB.fromPaise(x.refundable_paise);
    };
    on(m.el, '#rf-cust', () => show().catch((e) => RB.modalMsg(m, e.message)), 'change');
    show().catch((e) => RB.modalMsg(m, e.message));
    on(m.el, '#rf-save', async () => {
      try {
        await RB.rpc('rb_refund_customer', { p: { customer_id: Number($('#rf-cust', m.el).value) || null, refund_date: $('#rf-date', m.el).value, mode: $('#rf-mode', m.el).value,
          amount_paise: RB.toPaise($('#rf-amt', m.el).value), reference: $('#rf-ref', m.el).value, reason: $('#rf-why', m.el).value, return_id: o.return_id || null } });
        RB.toast('Refund saved'); m.close(); if (done) done(); else RB.route();
      } catch (e) { RB.modalMsg(m, e.message); }
    });
  };

  // ===================================================================
  // Receipts screen
  // ===================================================================
  RB.screens.receipts = async (body) => {
    const tools = $('#page-tools');
    if (tools) tools.innerHTML = (RB.has('receipts.add') ? '<button class="primary" id="rp-recv">Receive a payment</button>' : '') +
      (RB.has('power.refunds') ? '<button id="rp-ref">Refund a customer</button>' : '');
    on(document, '#rp-recv', () => I.receiveModal({}));
    on(document, '#rp-ref', () => I.refundModal({}));
    const list = [['list', 'Receipts and refunds', receiptsTab], ['balances', 'Customer balances', I.balancesTab]];
    if (money()) list.push(['bad', 'Bad debts', badDebtsTab]);
    body.innerHTML = '<div class="tabs">' + list.map(([k, t]) => '<button data-tab="' + k + '">' + t + '</button>').join('') + '</div><div id="tab-body"></div>';
    const show = async (k) => {
      I.rtab = k;
      $$('.tabs button', body).forEach((b) => b.classList.toggle('on', b.dataset.tab === k));
      const tb = $('#tab-body', body); tb.innerHTML = '<p class="muted">Loading…</p>';
      try { await list.find((x) => x[0] === k)[2](tb); } catch (e) { tb.innerHTML = '<div class="msg error">' + esc(e.message) + '</div>'; }
    };
    $$('.tabs button', body).forEach((b) => b.addEventListener('click', () => show(b.dataset.tab)));
    show(I.rtab || 'list');
  };

  async function receiptsTab(tb) {
    const rows = await RB.rpc('rb_customer_receipts_list');
    tb.innerHTML = '<div class="actions" style="margin:0 0 .75rem"><button id="rl-xls">Download to Excel</button></div>' +
      '<p class="muted">Money in from customers, and refunds paid back. "On account" is received but not yet set against an invoice. Tap a row to set it against invoices or reverse it.</p><div id="rl-grid"></div>';
    const grid = RB.grid($('#rl-grid', tb), [
      { title: 'Document', field: 'doc_no', width: 190, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
      { title: 'What', field: 'kind', width: 100, formatter: (c) => (c.getValue() === 'refund' ? 'Refund' : 'Receipt') },
      { title: 'Date', field: 'doc_date', width: 115, formatter: (c) => RB.fmtDate(c.getValue()) },
      { title: 'Customer', field: 'customer_name', minWidth: 180 },
      { title: 'How', field: 'mode', width: 80, formatter: (c) => esc(String(c.getValue() || '').toUpperCase()) },
      { title: 'Reference', field: 'reference' },
      { title: 'Amount', field: 'amount_paise', hozAlign: 'right', headerFilter: false, formatter: (c) => (c.getRow().getData().kind === 'refund' ? '− ' : '') + RB.rupees(c.getValue()) },
      { title: 'On account', field: 'on_account_paise', hozAlign: 'right', headerFilter: false, formatter: (c) => amt(c.getValue()) },
      { title: 'Status', field: 'status', width: 110, formatter: (c) => (c.getValue() === 'posted' ? RB.badge('active', 'Posted') : RB.badge('inactive', 'Reversed')) },
    ], rows);
    grid.on('rowClick', (e, row) => receiptModal(row.getData(), () => receiptsTab(tb)));
    on(tb, '#rl-xls', () => RB.downloadExcel(grid, 'Customer receipts'));
  }

  function receiptModal(r, done) {
    const isRef = r.kind === 'refund';
    const m = RB.modal('<h2>' + esc(r.doc_no) + RB.demoBadge(r) + '</h2><div class="m-msg"></div>' +
      '<p>' + (isRef ? 'Refund to ' : 'Received from ') + esc(r.customer_name) + ' · ' + RB.fmtDate(r.doc_date) + ' · ' + esc(String(r.mode).toUpperCase()) + ' · <b>' + RB.rupees(r.amount_paise) + '</b>' +
      (r.reference ? ' · ref ' + esc(r.reference) : '') + '</p>' + (r.note ? '<p class="muted">' + esc(r.note) + '</p>' : '') +
      (r.status !== 'posted' ? '<div class="msg info">Reversed.</div>' : '') +
      (!isRef && r.on_account_paise > 0 ? '<p>' + RB.rupees(r.on_account_paise) + ' is on account (not yet set against an invoice).</p>' : '') +
      '<div class="actions">' +
      (!isRef && r.status === 'posted' && r.on_account_paise > 0 && RB.has('receipts.add') ? '<button class="primary" id="rm-al">Set against invoices</button>' : '') +
      (r.status === 'posted' && RB.has('power.reverse_entries') ? '<button class="danger" id="rm-rev">Reverse</button>' : '') +
      (!isRef && r.status === 'posted' && RB.has('receipts.delete') ? '<button class="danger" id="rm-del">Delete fully (learning phase)</button>' : '') +
      '<button data-close>Close</button></div>');
    on(m.el, '#rm-al', () => { m.close(); I.receiveModal({ allocate: { kind: 'receipt', id: r.id, ref: r.doc_no, left: Number(r.on_account_paise), customer_id: r.customer_id, customer_name: r.customer_name } }, done); });
    on(m.el, '#rm-rev', () => { m.close(); SA().reverseModal('Reverse ' + r.doc_no,
      isRef ? 'The refund is undone in the books: the money counts as still owed to the customer.' : 'The receipt is undone in the books and the invoices it paid are owed again.',
      (dt, why) => RB.rpc(isRef ? 'rb_reverse_customer_refund' : 'rb_reverse_customer_receipt', { p_id: r.id, p_date: dt, p_reason: why }), done); });
    on(m.el, '#rm-del', async () => {
      if (!(await RB.confirm('Delete this receipt fully?', 'Only for receipts entered by someone still in their learning phase. It disappears from the books without a reversal.'))) return;
      try { await RB.rpc('rb_hard_delete_customer_receipt', { p_id: r.id }); RB.toast('Receipt deleted'); m.close(); done(); } catch (e) { RB.modalMsg(m, e.message); }
    });
  }

  // ---------- customer balances with ageing (Receipts and Customers) ----------
  I.balancesTab = async (tb) => {
    tb.innerHTML = '<div class="row" style="align-items:flex-end"><div class="field" style="flex:0 1 200px"><label for="cb-date">Balances on</label><input type="date" id="cb-date" value="' + RB.today() + '"></div>' +
      '<div class="field" style="flex:0 1 auto"><button id="cb-go">Show</button> <button id="cb-xls">Download to Excel</button></div></div>' +
      '<p class="muted">From the books (Trade receivables, per customer). Overdue is counted from each invoice\'s due date. A minus balance means we owe the customer (an advance or a credit note). Tap a customer for their ledger and statement.</p><div id="cb-grid"></div>';
    let grid;
    const load = async () => {
      const rows = await RB.rpc('rb_customer_balances', { p_as_of: $('#cb-date', tb).value || RB.today(), p_include_demo: true });
      const m = (c) => amt(c.getValue()), sum = { bottomCalc: 'sum', bottomCalcFormatter: (c) => RB.rupees(c.getValue()) };
      grid = RB.grid($('#cb-grid', tb), [
        { title: 'Code', field: 'code', width: 100 },
        { title: 'Customer', field: 'name', minWidth: 200, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) + (c.getRow().getData().over_limit ? ' ' + RB.badge('inactive', 'Over limit') : '') },
        { title: 'Type', field: 'kind', width: 90, formatter: (c) => (c.getValue() === 'trader' ? 'Trader' : 'Retail') },
        Object.assign({ title: 'Balance', field: 'balance_paise', hozAlign: 'right', headerFilter: false, formatter: (c) => '<b>' + RB.rupees(c.getValue()) + '</b>' }, sum),
        Object.assign({ title: 'Not yet due', field: 'not_due_paise', hozAlign: 'right', headerFilter: false, formatter: m }, sum),
        Object.assign({ title: '1–30 days', field: 'd1_30_paise', hozAlign: 'right', headerFilter: false, formatter: m }, sum),
        Object.assign({ title: '31–60', field: 'd31_60_paise', hozAlign: 'right', headerFilter: false, formatter: m }, sum),
        Object.assign({ title: '61–90', field: 'd61_90_paise', hozAlign: 'right', headerFilter: false, formatter: m }, sum),
        Object.assign({ title: 'Over 90', field: 'over_90_paise', hozAlign: 'right', headerFilter: false, formatter: (c) => (c.getValue() > 0 ? '<span class="diff">' + RB.rupees(c.getValue()) + '</span>' : '') }, sum),
        { title: 'On account', field: 'on_account_paise', hozAlign: 'right', headerFilter: false, formatter: m },
        { title: 'Credit limit', field: 'credit_limit_paise', hozAlign: 'right', headerFilter: false, formatter: m },
        { title: 'Phone', field: 'phone' },
      ], rows);
      grid.on('rowClick', (e, row) => I.statementModal(row.getData().customer_id, row.getData().name));
    };
    on(tb, '#cb-go', () => load().catch((e) => RB.toast(e.message, true)));
    on(tb, '#cb-xls', () => grid && RB.downloadExcel(grid, 'Customer balances'));
    await load();
  };

  // ---------- statement (screen, print and the public link) ----------
  const EVENTS = { sale: 'Invoice', sale_cancel: 'Cancelled', sales_return: 'Credit note', customer_receipt: 'Payment', customer_refund: 'Refund',
    opening: 'Opening balance', manual: 'Adjustment', reversal: 'Reversal', bad_debt: 'Written off', bad_debt_recovery: 'Recovered' };
  I.statementHtml = (st) => {
    const f = st.firm || {}, c = st.customer || {};
    return '<div class="invoice statement">' + firmHead(f, { text: 'STATEMENT OF ACCOUNT' }) +
      '<div class="inv-meta"><div><span class="muted">Customer</span><br><b>' + esc(c.name) + '</b>' + (c.address ? '<br>' + esc(c.address).replace(/\n/g, '<br>') : '') +
      (c.phone ? '<br>Phone ' + esc(c.phone) : '') + (c.gstin ? '<br>GSTIN ' + esc(c.gstin) : '') + '</div>' +
      '<div><table class="kv"><tr><td>Period</td><td>' + RB.fmtDate(st.from) + ' to ' + RB.fmtDate(st.to) + '</td></tr>' +
      '<tr><td>Opening balance</td><td>' + RB.rupees(st.opening_paise) + '</td></tr><tr><td>Closing balance</td><td><b>' + RB.rupees(st.closing_paise) + '</b></td></tr></table></div></div>' +
      '<div class="grid-wrap"><table class="inv-lines"><thead><tr><th>Date</th><th>Document</th><th>Details</th><th class="n">Charged</th><th class="n">Paid / credited</th><th class="n">Balance</th></tr></thead><tbody>' +
      '<tr><td>' + RB.fmtDate(st.from) + '</td><td></td><td>Opening balance</td><td></td><td></td><td class="n">' + RB.rupees(st.opening_paise) + '</td></tr>' +
      (st.lines || []).map((l) => '<tr><td>' + RB.fmtDate(l.line_date) + '</td><td>' + esc(l.ref || '') + '</td><td>' +
        esc(['sale', 'sales_return'].includes(l.event) ? EVENTS[l.event] : EVENTS[l.event] ? EVENTS[l.event] + (l.narration ? ': ' + l.narration : '') : l.narration || '') + '</td>' +
        '<td class="n">' + amt(l.debit_paise) + '</td><td class="n">' + amt(l.credit_paise) + '</td><td class="n">' + RB.rupees(l.balance_paise) + '</td></tr>').join('') +
      '</tbody><tfoot><tr><td colspan="5" class="n">' + (Number(st.closing_paise) < 0 ? 'We owe you' : 'Balance due') + '</td><td class="n"><b>' + RB.rupees(Math.abs(Number(st.closing_paise))) + '</b></td></tr></tfoot></table></div>' +
      ((st.open_invoices || []).length ? '<h3>Unpaid invoices</h3><div class="grid-wrap"><table class="inv-lines"><thead><tr><th>Invoice</th><th>Date</th><th>Due</th><th class="n">Total</th><th class="n">Still owed</th><th class="n">Days overdue</th></tr></thead><tbody>' +
        st.open_invoices.map((v) => '<tr><td>' + esc(v.invoice_no) + '</td><td>' + RB.fmtDate(v.invoice_date) + '</td><td>' + RB.fmtDate(v.due_date) + '</td><td class="n">' + RB.rupees(v.total_paise) +
          '</td><td class="n">' + RB.rupees(v.outstanding_paise) + '</td><td class="n">' + (v.days_overdue > 0 ? v.days_overdue : '') + '</td></tr>').join('') + '</tbody></table></div>' : '') +
      (Number(st.on_account_paise) > 0 ? '<p>Money with us not yet set against an invoice: ' + RB.rupees(st.on_account_paise) + '</p>' : '') +
      '<p class="muted inv-small">Statement made on ' + RB.fmtDate(RB.today()) + '. Please tell us of any difference.</p></div>';
  };
  I.statementUrl = (token) => location.href.split('#')[0] + '#/s/' + token;

  I.statementModal = (customerId, name) => {
    const m = RB.modal('<h2>Ledger and statement: ' + esc(name) + '</h2><div class="m-msg"></div>' +
      '<div class="row no-print" style="align-items:flex-end"><div class="field"><label for="cs-from">From</label><input type="date" id="cs-from" value="' + fy() + '"></div>' +
      '<div class="field"><label for="cs-to">To</label><input type="date" id="cs-to" value="' + RB.today() + '"></div>' +
      '<div class="field" style="flex:0 1 auto"><button id="cs-go">Show</button></div></div>' +
      '<div class="actions no-print"><button class="primary" id="cs-print">Print / Save as PDF</button>' +
      '<button id="cs-share">Share a link</button><button id="cs-revoke">Switch off links</button>' +
      (RB.has('receipts.add') ? '<button id="cs-recv">Receive payment</button>' : '') + '<button data-close>Close</button></div>' +
      '<div id="cs-links" class="no-print"></div><div id="cs-body" class="print-area"><p class="muted">Loading…</p></div>', { wide: true });
    const load = async () => {
      try {
        const st = await RB.rpc('rb_customer_statement', { p_customer: customerId, p_from: $('#cs-from', m.el).value, p_to: $('#cs-to', m.el).value });
        $('#cs-body', m.el).innerHTML = I.statementHtml(st);
        $('#cs-links', m.el).innerHTML = (st.links || []).length ? '<p class="muted">Open links: ' + st.links.map((l) => 'from ' + RB.fmtDate(l.from_date) + ', ends ' + RB.fmtDate(l.expires_at) +
          ', opened ' + l.opened_count + ' time(s)').join('; ') + '</p>' : '';
      } catch (e) { RB.modalMsg(m, e.message); }
    };
    on(m.el, '#cs-go', load);
    on(m.el, '#cs-print', () => { document.body.classList.add('printing-modal'); window.print(); setTimeout(() => document.body.classList.remove('printing-modal'), 500); });
    on(m.el, '#cs-share', async () => {
      try {
        const r = await RB.rpc('rb_create_statement_link', { p_customer: customerId, p_from: $('#cs-from', m.el).value });
        const url = I.statementUrl(r.token);
        try { await navigator.clipboard.writeText(url); } catch (e) { /* not allowed: shown below */ }
        RB.modalMsg(m, 'Link copied. Send it to the customer by WhatsApp or email. It works until ' + RB.fmtDate(r.expires_at) + ', with no password: ' + url, true);
        load();
      } catch (e) { RB.modalMsg(m, e.message); }
    });
    on(m.el, '#cs-revoke', async () => {
      try { const n = await RB.rpc('rb_revoke_statement_links', { p_customer: customerId }); RB.modalMsg(m, n + ' link(s) switched off.', true); load(); } catch (e) { RB.modalMsg(m, e.message); }
    });
    on(m.el, '#cs-recv', () => { m.close(); I.receiveModal({ customer_id: customerId }); });
    load();
  };

  // The page a customer opens from a statement link (no sign-in).
  I.publicStatement = async (token) => {
    const app = $('#app');
    app.innerHTML = '<main id="page" class="public"><p class="muted">Loading your statement…</p></main>';
    try {
      const { data, error } = await RB.sb.rpc('rb_public_statement', { p_token: token });
      if (error) throw new Error(RB.friendly(error));
      $('#page').innerHTML = '<div class="actions no-print"><button class="primary" id="ps-print">Print / Save as PDF</button></div>' + I.statementHtml(data) +
        '<p class="muted no-print">This link works until ' + RB.fmtDate(data.expires_at) + '.</p>';
      on(app, '#ps-print', () => window.print());
    } catch (e) {
      $('#page').innerHTML = '<div class="login-wrap"><img class="wordmark" src="assets/wordmark.png" alt="Ruchi Buds"><div class="login-card"><p>' + esc(e.message) + '</p></div></div>';
    }
  };

  // ===================================================================
  // Bad debts: written off by the FC or a Director, recovered later
  // ===================================================================
  async function badDebtsTab(tb) {
    const rows = await RB.rpc('rb_bad_debts_list');
    const can = RB.has('power.write_off_debts');
    tb.innerHTML = '<div class="actions" style="margin:0 0 .75rem">' + (can ? '<button id="bd-new">Write off an earlier balance</button>' : '') + '<button id="bd-xls">Download to Excel</button></div>' +
      '<p class="muted">Money a customer will not pay, taken off their balance and charged to Bad Debt Write-offs. To write off an invoice, open it and press <b>Write off as bad debt</b>. ' +
      'If the customer pays later, first enter the money as a receipt, then tap the write-off here and press <b>Book money recovered</b> (it counts as other income).</p><div id="bd-grid"></div>';
    const grid = RB.grid($('#bd-grid', tb), [
      { title: 'Write-off', field: 'write_off_no', width: 180, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
      { title: 'Date', field: 'write_off_date', width: 115, formatter: (c) => RB.fmtDate(c.getValue()) },
      { title: 'Customer', field: 'customer_name', minWidth: 180 },
      { title: 'Invoice', field: 'invoice_no', width: 180, formatter: (c) => esc(c.getValue() || 'Earlier balance') },
      { title: 'Reason', field: 'reason', minWidth: 200 },
      { title: 'Written off', field: 'amount_paise', hozAlign: 'right', headerFilter: false, formatter: (c) => RB.rupees(c.getValue()) },
      { title: 'Recovered', field: 'recovered_paise', hozAlign: 'right', headerFilter: false, formatter: (c) => amt(c.getValue()) },
      { title: 'Status', field: 'status', width: 110, formatter: (c) => (c.getValue() === 'posted' ? RB.badge('active', 'Posted') : RB.badge('inactive', 'Reversed')) },
    ], rows);
    grid.on('rowClick', (e, row) => I.badDebtModal(row.getData(), () => badDebtsTab(tb)));
    on(tb, '#bd-xls', () => RB.downloadExcel(grid, 'Bad debts'));
    on(tb, '#bd-new', () => I.writeOffModal({}, () => badDebtsTab(tb)));
  }

  // o: { customer_id, customer_name, sale_id, invoice_no, owed } — no sale_id = an earlier balance
  I.writeOffModal = async (o, done) => {
    const inv = !!o.sale_id;
    const custs = inv ? [] : (await RB.select('customers', 'id,name,is_walk_in', (x) => x.order('name'))).filter((c) => !c.is_walk_in);
    const m = RB.modal('<h2>Write off as bad debt' + (inv ? ': ' + esc(o.invoice_no) : '') + '</h2><div class="m-msg"></div>' +
      '<p class="muted">Only when the money cannot be collected (for example the customer has closed down). The amount comes off the customer\'s balance and is charged to Bad Debt Write-offs. It can be reversed, and money paid later can be booked as recovered.</p>' +
      '<div class="row">' + (inv ? '<div class="field"><label>Customer</label><p>' + esc(o.customer_name) + '</p></div>'
        : RB.field('wo-cust', 'Customer', RB.sel('wo-cust', [['', 'Choose…']].concat(custs.map((c) => [c.id, c.name]))), '<span id="wo-left"></span>', true)) +
      RB.field('wo-date', 'Date', '<input type="date" id="wo-date" value="' + RB.today() + '">', null, true) +
      RB.field('wo-amt', 'Amount (₹)', RB.inp('wo-amt', inv ? RB.fromPaise(o.owed) : '', ' inputmode="decimal"'), inv ? 'Still owed on the invoice: ' + RB.rupees(o.owed) : 'Only a balance that is not on an invoice in the app (such as an opening balance).', true) + '</div>' +
      RB.field('wo-why', 'Reason', '<textarea id="wo-why" placeholder="e.g. shop closed, owner not reachable after three reminders"></textarea>', null, true) +
      '<div class="actions"><button class="danger" id="wo-go">Write off</button><button data-close>Cancel</button></div>');
    on(m.el, '#wo-cust', async () => {
      const c = Number($('#wo-cust', m.el).value); if (!c) return;
      try {
        const x = await RB.rpc('rb_customer_open_items', { p_customer: c });
        $('#wo-left', m.el).textContent = 'Earlier balance not on an invoice: ' + RB.rupees(x.other_balance_paise);
        $('#wo-amt', m.el).value = Number(x.other_balance_paise) > 0 ? RB.fromPaise(x.other_balance_paise) : '';
      } catch (e) { RB.modalMsg(m, e.message); }
    }, 'change');
    on(m.el, '#wo-go', async () => {
      try {
        await RB.rpc('rb_write_off_bad_debt', { p: { customer_id: inv ? o.customer_id : Number($('#wo-cust', m.el).value) || null, sale_id: o.sale_id || null,
          write_off_date: $('#wo-date', m.el).value, amount_paise: RB.toPaise($('#wo-amt', m.el).value), reason: $('#wo-why', m.el).value } });
        RB.toast('Written off'); m.close(); if (done) done();
      } catch (e) { RB.modalMsg(m, e.message); }
    });
  };

  I.badDebtModal = (w, done) => {
    const can = RB.has('power.write_off_debts'), posted = w.status === 'posted';
    const recs = (w.recoveries || []);
    const m = RB.modal('<h2>' + esc(w.write_off_no) + RB.demoBadge(w) + '</h2><div class="m-msg"></div>' +
      '<p>' + esc(w.customer_name) + ' · ' + esc(w.invoice_no || 'Earlier balance') + ' · ' + RB.fmtDate(w.write_off_date) + ' · written off <b>' + RB.rupees(w.amount_paise) + '</b></p>' +
      '<p class="muted">' + esc(w.reason) + (w.entered_by_name ? ' · by ' + esc(w.entered_by_name) : '') + '</p>' +
      (!posted ? '<div class="msg info">Reversed: ' + esc(w.reverse_reason || '') + '</div>' : '') +
      (recs.length ? '<h3>Money recovered</h3><table class="ticks lines"><thead><tr><th>Recovery</th><th>Date</th><th>Amount</th><th>Status</th><th></th></tr></thead><tbody>' +
        recs.map((r) => '<tr><td>' + esc(r.recovery_no) + '</td><td>' + RB.fmtDate(r.recovery_date) + '</td><td style="text-align:right">' + RB.rupees(r.amount_paise) + '</td><td>' +
          (r.status === 'posted' ? RB.badge('active', 'Posted') : RB.badge('inactive', 'Reversed')) + '</td><td>' +
          (can && r.status === 'posted' ? '<button data-rrev="' + r.id + '">Reverse</button>' : '') + '</td></tr>').join('') + '</tbody></table>' : '') +
      (posted ? '<p>Still written off: <b>' + RB.rupees(w.left_paise) + '</b></p>' : '') +
      '<div class="actions">' +
      (can && posted && Number(w.left_paise) > 0 ? '<button class="primary" id="bm-rec">Book money recovered</button>' : '') +
      (can && posted ? '<button class="danger" id="bm-rev">Reverse write-off</button>' : '') +
      (w.sale_id ? '<a class="btn" href="#/invoices/' + w.sale_id + '">Open the invoice</a>' : '') + '<button data-close>Close</button></div>');
    $$('a.btn', m.el).forEach((a) => a.addEventListener('click', () => m.close()));
    on(m.el, '#bm-rec', async () => {
      m.close();
      let onAcc = 0;
      try { onAcc = Number((await RB.rpc('rb_customer_open_items', { p_customer: w.customer_id })).on_account_paise); } catch (e) { /* shown on save */ }
      const r = RB.modal('<h2>Book money recovered on ' + esc(w.write_off_no) + '</h2><div class="m-msg"></div>' +
        '<p class="muted">The money must already be entered as a customer receipt (Receive a payment), where it waits on account. ' + esc(w.customer_name) + ' has ' + RB.rupees(onAcc) + ' on account now.</p>' +
        '<div class="row">' + RB.field('br-date', 'Date', '<input type="date" id="br-date" value="' + RB.today() + '">', null, true) +
        RB.field('br-amt', 'Amount (₹)', RB.inp('br-amt', RB.fromPaise(Math.min(onAcc, Number(w.left_paise))) || '', ' inputmode="decimal"'), 'Still written off: ' + RB.rupees(w.left_paise), true) + '</div>' +
        RB.field('br-note', 'Note', RB.inp('br-note', '')) +
        '<div class="actions"><button class="primary" id="br-go">Book as recovered</button><button data-close>Cancel</button></div>');
      on(r.el, '#br-go', async () => {
        try {
          await RB.rpc('rb_record_bad_debt_recovery', { p: { write_off_id: w.id, recovery_date: $('#br-date', r.el).value,
            amount_paise: RB.toPaise($('#br-amt', r.el).value), note: $('#br-note', r.el).value } });
          RB.toast('Booked as bad debt recovered'); r.close(); if (done) done();
        } catch (e) { RB.modalMsg(r, e.message); }
      });
    });
    on(m.el, '#bm-rev', () => { m.close(); SA().reverseModal('Reverse ' + w.write_off_no,
      'The customer owes the amount again' + (w.sale_id ? ' and the invoice opens again' : '') + '. The bad debt charge is reversed on the date below.',
      (dt, why) => RB.rpc('rb_reverse_bad_debt', { p_id: w.id, p_date: dt, p_reason: why }), done); });
    $$('[data-rrev]', m.el).forEach((b) => b.addEventListener('click', () => { m.close(); SA().reverseModal('Reverse the recovery',
      'The income is reversed and the money goes back on account for the customer.',
      (dt, why) => RB.rpc('rb_reverse_bad_debt_recovery', { p_id: Number(b.dataset.rrev), p_date: dt, p_reason: why }), done); }));
  };

  // ===================================================================
  // Customers screen: add balances and the ledger beside the list
  // ===================================================================
  const listScreen = RB.screens.customers;
  RB.screens.customers = async (body, arg) => {
    // Balances need module 5's database (05_sales_invoices.sql) and the "See money totals" tick.
    const live = (RB.cache.screens || []).some((x) => x.code === 'receipts' && x.available);
    if (!live || !RB.has('power.see_totals')) return listScreen(body, arg);
    body.innerHTML = '<div class="tabs"><button data-tab="list">Customers</button><button data-tab="bal">Balances and statements</button></div><div id="tab-body"></div>';
    const show = async (k) => {
      I.ctab = k;
      $$('.tabs button', body).forEach((b) => b.classList.toggle('on', b.dataset.tab === k));
      const tb = $('#tab-body', body); tb.innerHTML = '<p class="muted">Loading…</p>';
      try { if (k === 'list') await listScreen(tb, arg); else await I.balancesTab(tb); } catch (e) { tb.innerHTML = '<div class="msg error">' + esc(e.message) + '</div>'; }
    };
    $$('.tabs button', body).forEach((b) => b.addEventListener('click', () => show(b.dataset.tab)));
    show(I.ctab || 'list');
  };
})();
