// =====================================================================
// RUCHI BUDS APP · shop.js · Version 1.1 · 27-Nov-2026 (1.1: shop link by email too)
// Module 10 screen "Online shop orders": the orders from the public shop
// (check UPI payments and tick Paid, pack, dispatch into an invoice,
// record cash on delivery, cancel), the products on the shop with Free /
// On hold / Total stock, the shop set-up (link to share, payment,
// delivery charges by PIN code, staff alerts) and the online orders
// report. Also the alerts on the home screen while the app is open.
// =====================================================================
(function () {
  'use strict';
  const RB = window.RB, $ = RB.$, $$ = RB.$$, esc = RB.esc;
  const S = (RB.shop = { tab: null, filter: 'open', lastAlert: null });

  const STATUS = { placed: 'Waiting for UPI payment', payment_check: 'Check the UPI payment', paid: 'Paid: to pack', cod: 'Cash on delivery: to pack',
    packed: 'Packed: to dispatch', dispatched: 'Dispatched: cash to collect', delivered: 'Done', cancelled: 'Cancelled', expired: 'Time ran out (not paid)' };
  const BADGE = { placed: 'invited', payment_check: 'protected', paid: 'locked', cod: 'locked', packed: 'protected', dispatched: 'protected',
    delivered: 'active', cancelled: 'inactive', expired: 'inactive' };
  const money = (p) => (p == null ? '' : RB.rupees(p));
  const setup = () => RB.has('power.shop_setup');
  const on = (root, sel, fn, ev) => { const el = $(sel, root); if (el) el.addEventListener(ev || 'click', fn); };
  const paise = (v) => { const s = String(v == null ? '' : v).replace(/[₹,\s]/g, ''); if (s === '') return null; const n = Number(s); if (!isFinite(n) || n < 0) throw new Error('"' + v + '" is not an amount.'); return Math.round(n * 100); };
  const shopUrl = () => location.origin + location.pathname.replace(/[^/]*$/, '') + 'shop.html';
  const monthStart = () => RB.today().slice(0, 8) + '01';

  function tabs(body, list) {
    body.innerHTML = '<div class="tabs">' + list.map(([k, t]) => '<button data-tab="' + k + '">' + t + '</button>').join('') + '</div><div id="tab-body"></div>';
    const show = async (k) => {
      S.tab = k;
      $$('.tabs button', body).forEach((b) => b.classList.toggle('on', b.dataset.tab === k));
      const tb = $('#tab-body', body); tb.innerHTML = '<p class="muted">Loading…</p>';
      try { await list.find((x) => x[0] === k)[2](tb); } catch (e) { tb.innerHTML = '<div class="msg error">' + esc(e.message) + '</div>'; }
    };
    $$('.tabs button', body).forEach((b) => b.addEventListener('click', () => show(b.dataset.tab)));
    show(S.tab && list.some((x) => x[0] === S.tab) ? S.tab : list[0][0]);
  }

  RB.screens.shop = async (body) => {
    tabs(body, [['orders', 'Orders', ordersTab], ['products', 'Products online', productsTab], ['setup', 'Shop set-up', setupTab], ['report', 'Report', reportTab]]);
  };

  // ===================================================================
  // Orders
  // ===================================================================
  async function ordersTab(tb) {
    const [a, rows] = await Promise.all([RB.rpc('rb_shop_my_alerts'), RB.rpc('rb_shop_orders', {
      p_from: S.filter === 'open' ? null : ($('#so-from', tb) || {}).value || monthStart(), p_to: S.filter === 'open' ? null : ($('#so-to', tb) || {}).value || RB.today(),
      p_status: S.filter })]);
    tb.innerHTML = '<div class="kpis">' +
      '<div><small>UPI payments to check</small><b>' + a.to_check + '</b></div>' +
      '<div><small>Orders to pack</small><b>' + a.to_pack + '</b></div>' +
      '<div><small>Packed, to dispatch</small><b>' + a.to_dispatch + '</b></div>' +
      '<div><small>Cash on delivery to collect</small><b>' + a.cash_due + '</b></div></div>' +
      '<div class="switch" id="so-filter">' + [['open', 'To do'], ['all', 'All orders'], ['cancelled', 'Cancelled'], ['expired', 'Not paid in time']]
        .map(([k, t]) => '<button data-f="' + k + '"' + (S.filter === k ? ' class="on"' : '') + '>' + t + '</button>').join('') + '</div>' +
      (S.filter === 'open' ? '' : '<div class="row" style="align-items:flex-end"><div class="field" style="flex:0 1 180px"><label for="so-from">From</label><input type="date" id="so-from" value="' + (S.from || monthStart()) + '"></div>' +
        '<div class="field" style="flex:0 1 180px"><label for="so-to">To</label><input type="date" id="so-to" value="' + (S.to || RB.today()) + '"></div>' +
        '<div class="field" style="flex:0 1 auto"><button id="so-go">Show</button></div></div>') +
      '<div class="actions" style="margin:0 0 .5rem"><button id="so-refresh">Refresh</button><button id="so-xls">Download to Excel</button></div>' +
      '<p class="muted">Tap an order to check the payment, pack it, dispatch it (it becomes an invoice) or cancel it.</p><div id="so-grid"></div>';
    const grid = RB.grid($('#so-grid', tb), [
      { title: 'Order', field: 'order_no', width: 170, formatter: (c) => '<b>' + esc(c.getValue()) + '</b>' + RB.demoBadge(c.getRow().getData()) },
      { title: 'Placed', field: 'placed_at', width: 140, formatter: (c) => RB.fmtDateTime(c.getValue()) },
      { title: 'Status', field: 'status', width: 210, formatter: (c) => RB.badge(BADGE[c.getValue()], STATUS[c.getValue()]) },
      { title: 'Customer', field: 'cust_name', minWidth: 150 },
      { title: 'Phone', field: 'cust_phone', width: 120 },
      { title: 'Items', field: 'items', minWidth: 220 },
      { title: 'Pay', field: 'pay_method', width: 80, formatter: (c) => (c.getValue() === 'cod' ? 'COD' : 'UPI') },
      { title: 'Delivery / pickup', field: 'fulfil', width: 140, formatter: (c) => (c.getValue() === 'pickup' ? 'Pickup' : 'Delivery ' + esc(c.getRow().getData().pin_code || '')) },
      { title: 'Total', field: 'total_paise', hozAlign: 'right', headerFilter: false, formatter: (c) => '<b>' + money(c.getValue()) + '</b>' },
      { title: 'Invoice', field: 'invoice_no', width: 170 },
    ], rows);
    grid.on('rowClick', (e, row) => orderModal(row.getData(), () => ordersTab(tb)));
    $$('#so-filter button', tb).forEach((b) => b.addEventListener('click', () => { S.filter = b.dataset.f; ordersTab(tb).catch((x) => RB.toast(x.message, true)); }));
    on(tb, '#so-go', () => { S.from = $('#so-from', tb).value; S.to = $('#so-to', tb).value; ordersTab(tb).catch((x) => RB.toast(x.message, true)); });
    on(tb, '#so-refresh', () => ordersTab(tb).catch((x) => RB.toast(x.message, true)));
    on(tb, '#so-xls', () => RB.downloadExcel(grid, 'Online orders'));
  }

  function waText(o) {
    const link = shopUrl() + '#o/' + o.token;
    const t = {
      placed: 'Hello ' + o.cust_name + ', thank you for your order ' + o.order_no + ' (' + money(o.total_paise) + '). Please pay by UPI here: ' + link,
      payment_check: 'Hello ' + o.cust_name + ', we are checking your UPI payment for order ' + o.order_no + '. ' + link,
      paid: 'Hello ' + o.cust_name + ', your payment for order ' + o.order_no + ' is confirmed. We are packing it now. ' + link,
      cod: 'Hello ' + o.cust_name + ', we have your order ' + o.order_no + '. Please keep ' + money(o.total_paise) + ' ready to pay in cash. ' + link,
      packed: 'Hello ' + o.cust_name + ', your order ' + o.order_no + ' is packed' + (o.fulfil === 'pickup' ? ' and ready for pickup.' : ' and will be on its way soon.') + ' ' + link,
      dispatched: 'Hello ' + o.cust_name + ', your order ' + o.order_no + ' is on its way. Please keep ' + money(o.total_paise) + ' ready to pay in cash. ' + link,
      delivered: 'Hello ' + o.cust_name + ', thank you for ordering from Ruchi Buds! ' + link,
      cancelled: 'Hello ' + o.cust_name + ', your order ' + o.order_no + ' has been cancelled. ' + (o.receipt_no ? 'Your payment will be refunded.' : ''),
      expired: 'Hello ' + o.cust_name + ', the time to pay for order ' + o.order_no + ' ran out. Please order again here: ' + shopUrl(),
    };
    return RB.waUrl(o.cust_phone, t[o.status] || link);
  }

  function orderModal(o, done) {
    const edit = RB.has('shop.edit'), s = o.status, cod = o.pay_method === 'cod';
    const canDl = edit && (s === 'placed' || (cod && (s === 'cod' || s === 'packed')));
    const m = RB.modal('<h2>' + esc(o.order_no) + RB.demoBadge(o) + '</h2><div class="m-msg"></div>' +
      '<p>' + RB.badge(BADGE[s], STATUS[s]) + (o.hold_until && s === 'placed' ? ' <span class="muted">held until ' + RB.fmtDateTime(o.hold_until) + '</span>' : '') + '</p>' +
      '<div class="row facts"><div><small>Customer</small><b>' + esc(o.cust_name) + '</b><br><a href="tel:' + esc(o.cust_phone) + '">' + esc(o.cust_phone) + '</a></div>' +
      '<div><small>' + (o.fulfil === 'pickup' ? 'Pickup' : 'Deliver to') + '</small><b>' + (o.fulfil === 'pickup' ? 'Picks up from the kitchen' : esc(o.cust_address) + ' ' + esc(o.pin_code)) + '</b></div>' +
      '<div><small>Payment</small><b>' + (cod ? 'Cash on delivery' : 'UPI') + '</b>' + (o.upi_ref ? '<br>Ref ' + esc(o.upi_ref) : '') + '</div>' +
      '<div><small>Placed</small><b>' + RB.fmtDateTime(o.placed_at) + '</b></div></div>' +
      (o.cust_note ? '<div class="msg info">Customer\'s note: ' + esc(o.cust_note) + '</div>' : '') +
      (o.staff_note ? '<div class="msg info">' + esc(o.staff_note) + '</div>' : '') +
      (o.cancel_reason ? '<div class="msg info">Cancelled: ' + esc(o.cancel_reason) + '</div>' : '') +
      '<div class="grid-wrap"><table class="ticks" style="min-width:0"><thead><tr><th>Item</th><th class="n">Packs</th><th class="n">Price</th><th class="n">Amount</th></tr></thead><tbody>' +
      o.lines.map((l) => '<tr><td>' + esc(l.description) + '</td><td class="n">' + l.packs + '</td><td class="n">' + money(l.rate_paise) + '</td><td class="n">' + money(l.amount_paise) + '</td></tr>').join('') +
      '<tr><td>Delivery</td><td></td><td></td><td class="n">' + money(o.delivery_paise) + '</td></tr>' +
      (o.gst_paise ? '<tr><td>GST</td><td></td><td></td><td class="n">' + money(o.gst_paise) + '</td></tr>' : '') +
      '<tr><td><b>Total</b></td><td></td><td></td><td class="n"><b>' + money(o.total_paise) + '</b></td></tr></tbody></table></div>' +
      '<p class="muted">' + [o.receipt_no ? 'UPI receipt ' + esc(o.receipt_no) : '', o.invoice_no ? 'Invoice ' + esc(o.invoice_no) : '', o.cash_receipt_no ? 'Cash receipt ' + esc(o.cash_receipt_no) : ''].filter(Boolean).join(' · ') + '</p>' +
      (edit && (s === 'placed' || s === 'payment_check' || s === 'expired') && !cod ? '<h3>UPI payment</h3>' +
        '<p class="muted">Open the bank or UPI app of <b>Bank account 1</b> and look for ' + money(o.total_paise) + (o.upi_ref ? ' with reference <b>' + esc(o.upi_ref) + '</b>' : '') + '.</p>' +
        '<div class="row"><div class="field"><label for="om-ref">UPI reference</label><input id="om-ref" value="' + esc(o.upi_ref || '') + '"></div>' +
        '<div class="field"><label for="om-date">Date received</label><input type="date" id="om-date" value="' + RB.today() + '"></div></div>' +
        '<div class="actions" style="margin-top:0"><button class="primary" id="om-paid">Payment found: mark Paid</button>' +
        (s === 'payment_check' ? '<button id="om-notfound">Not found: ask the customer again</button>' : '') + '</div>' : '') +
      (edit && s === 'dispatched' ? '<h3>Cash on delivery</h3><div class="row"><div class="field"><label for="om-mode">Paid by</label><select id="om-mode"><option value="cash">Cash</option><option value="upi">UPI at the door</option></select></div>' +
        '<div class="field"><label for="om-cdate">Date received</label><input type="date" id="om-cdate" value="' + RB.today() + '"></div>' +
        '<div class="field"><label for="om-cref">Reference (UPI)</label><input id="om-cref"></div></div>' +
        '<div class="actions" style="margin-top:0"><button class="primary" id="om-cash">' + money(o.total_paise) + ' received</button></div>' : '') +
      (canDl ? '<details><summary>Change the delivery charge</summary><div class="row" style="align-items:flex-end"><div class="field"><label for="om-dl">Delivery charge (₹)</label><input id="om-dl" inputmode="decimal" value="' + (o.delivery_paise / 100) + '"></div>' +
        '<div class="field" style="flex:0 1 auto"><button id="om-dl-save">Save</button></div></div></details>' : '') +
      '<div class="actions">' +
      (edit && (s === 'paid' || s === 'cod') ? '<button class="primary" id="om-pack">Packed</button>' : '') +
      (edit && ['paid', 'cod', 'packed'].includes(s) ? '<button class="primary" id="om-dispatch">' + (o.fulfil === 'pickup' ? 'Handed over' : 'Dispatched') + ': make the invoice</button>' : '') +
      '<a class="btn" target="_blank" rel="noopener" href="' + esc(waText(o)) + '">Message on WhatsApp</a>' +
      (edit && !['dispatched', 'delivered', 'cancelled'].includes(s) ? '<button class="danger" id="om-cancel">Cancel order</button>' : '') +
      '<button data-close>Close</button></div>', { wide: true });
    const act = async (fn, ok) => { try { const r = await fn(); m.close(); RB.toast(typeof r === 'string' ? r : ok); done(); } catch (e) { RB.modalMsg(m, e.message); } };
    on(m.el, '#om-paid', () => act(() => RB.rpc('rb_shop_mark_paid', { p_id: o.id, p_ref: $('#om-ref', m.el).value, p_date: $('#om-date', m.el).value }), 'Marked paid. The staff to pack it are alerted.'));
    on(m.el, '#om-notfound', () => act(() => RB.rpc('rb_shop_payment_not_found', { p_id: o.id }), 'The order waits for payment again. Message the customer on WhatsApp.'));
    on(m.el, '#om-cash', () => act(() => RB.rpc('rb_shop_cash_received', { p_id: o.id, p_mode: $('#om-mode', m.el).value, p_date: $('#om-cdate', m.el).value, p_ref: $('#om-cref', m.el).value }), 'Cash recorded. The invoice is paid.'));
    on(m.el, '#om-dl-save', () => act(() => RB.rpc('rb_shop_set_delivery', { p_id: o.id, p_charge_paise: paise($('#om-dl', m.el).value) }), 'Delivery charge changed'));
    on(m.el, '#om-pack', () => act(() => RB.rpc('rb_shop_pack', { p_id: o.id }), 'Packed'));
    on(m.el, '#om-dispatch', async () => {
      if (!(await RB.confirm('Make the invoice for ' + o.order_no + '?', 'The goods leave finished-goods stock and the invoice is posted' + (cod ? '. The cash is recorded when it comes in.' : ', paid by the UPI receipt.')))) return;
      act(() => RB.rpc('rb_shop_dispatch', { p_id: o.id, p_date: RB.today() }).then((r) => 'Invoice ' + r.invoice_no + ' made'));
    });
    on(m.el, '#om-cancel', () => {
      const c = RB.modal('<h2>Cancel ' + esc(o.order_no) + '?</h2><div class="m-msg"></div><p>The items are free to sell again.' +
        (o.receipt_no ? ' The ' + money(o.total_paise) + ' already paid stays on the customer\'s account: the accounts team refunds it from Invoices → Customers.' : '') + '</p>' +
        '<div class="field"><label for="oc-why">Reason</label><input id="oc-why"></div>' +
        '<div class="actions"><button class="danger" id="oc-yes">Cancel the order</button><button data-close>Keep it</button></div>');
      on(c.el, '#oc-yes', async () => {
        try { const r = await RB.rpc('rb_shop_cancel', { p_id: o.id, p_reason: $('#oc-why', c.el).value }); c.close(); m.close(); RB.toast(r); done(); }
        catch (e) { RB.modalMsg(c, e.message); }
      });
    });
  }

  // ===================================================================
  // Products on the shop: which packs show, photos, Free / On hold / Total
  // ===================================================================
  async function productsTab(tb) {
    const rows = await RB.rpc('rb_shop_products');
    tb.innerHTML = '<p class="muted">Every finished-goods pack. <b>On hold</b> = packs in online orders not yet dispatched: they cannot be sold at the counter. ' +
      (setup() ? 'Tap a pack to put it on the shop, hide it, add a photo or allow cash on delivery.' : 'A Director or the FC chooses which packs appear on the shop.') + '</p>' +
      '<div class="actions" style="margin:0 0 .5rem"><button id="sp-xls">Download to Excel</button></div><div id="sp-grid"></div>';
    const grid = RB.grid($('#sp-grid', tb), [
      { title: 'Photo', field: 'photo', width: 84, headerFilter: false, formatter: (c) => (c.getValue() ? '<img class="sh-photo" src="' + esc(c.getValue()) + '" alt="">' : '') },
      { title: 'Product', field: 'name', minWidth: 180, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
      { title: 'Pack', field: 'pack', minWidth: 140 },
      { title: 'On the shop', field: 'visible', width: 120, formatter: (c) => (c.getValue() ? RB.badge('active', 'Shown') : RB.badge('inactive', 'Hidden')) },
      { title: 'COD', field: 'cod_allowed', width: 80, formatter: (c) => (c.getValue() ? 'Yes' : '') },
      { title: 'Online price', field: 'price_paise', hozAlign: 'right', headerFilter: false, formatter: (c) => money(c.getValue()) },
      { title: 'Free', field: 'free', hozAlign: 'right', headerFilter: false, formatter: (c) => '<b>' + c.getValue() + '</b>' + (c.getValue() <= 0 && c.getRow().getData().visible ? ' <span class="diff">SOLD OUT</span>' : '') },
      { title: 'On hold', field: 'held', hozAlign: 'right', headerFilter: false },
      { title: 'Total', field: 'total', hozAlign: 'right', headerFilter: false },
    ], rows.map((r) => Object.assign({}, r, { photo: r.photo })));
    if (setup()) grid.on('rowClick', (e, row) => productModal(row.getData(), () => productsTab(tb)));
    on(tb, '#sp-xls', () => RB.downloadExcel(grid, 'Online shop products'));
  }

  // A photo from the phone or computer, made small (600 px, JPEG) so the shop page loads fast.
  const shrink = (file) => new Promise((resolve, reject) => {
    const img = new Image(), url = URL.createObjectURL(file);
    img.onload = () => {
      const k = Math.min(1, 600 / Math.max(img.width, img.height)), c = document.createElement('canvas');
      c.width = Math.round(img.width * k); c.height = Math.round(img.height * k);
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
      URL.revokeObjectURL(url);
      let q = 0.8, d = c.toDataURL('image/jpeg', q);
      while (d.length > 300000 && q > 0.3) { q -= 0.15; d = c.toDataURL('image/jpeg', q); }
      resolve(d);
    };
    img.onerror = () => reject(new Error('That file is not a picture this browser can read. Use a JPG or PNG.'));
    img.src = url;
  });

  function productModal(r, done) {
    let photo; // undefined = keep, '' = remove, data: = new
    const m = RB.modal('<h2>' + esc(r.name) + ', ' + esc(r.pack) + RB.demoBadge(r) + '</h2><div class="m-msg"></div>' +
      (r.price_paise == null ? '<div class="msg error">No online or retail price yet. Add it in Masters → Packs and prices.</div>' : '<p>Online price <b>' + money(r.price_paise) + '</b> (from Masters → Packs and prices). Free now: <b>' + r.free + '</b>.</p>') +
      (r.hsn_ok ? '' : '<div class="msg info">No HSN code or GST rate in Masters yet. Once the firm is GST registered, it cannot be ordered online without them.</div>') +
      '<label class="check"><input type="checkbox" id="pm-vis"' + (r.visible ? ' checked' : '') + '> Show on the shop</label>' +
      '<label class="check"><input type="checkbox" id="pm-cod"' + (r.cod_allowed ? ' checked' : '') + '> Cash on delivery allowed</label>' +
      '<div class="field"><label for="pm-desc">Short description (on the shop)</label><input id="pm-desc" maxlength="300" value="' + esc(r.description || '') + '"></div>' +
      '<div class="field" style="max-width:160px"><label for="pm-sort">Order on the page</label><input id="pm-sort" inputmode="numeric" value="' + r.sort + '"></div>' +
      '<div class="field"><label for="pm-photo">Photo</label><div class="row" style="align-items:center"><div style="flex:0 0 auto" id="pm-prev">' + (r.photo ? '<img class="sh-photo" style="width:120px;height:90px" src="' + esc(r.photo) + '" alt="">' : '<span class="muted">No photo</span>') + '</div>' +
      '<div><input type="file" id="pm-photo" accept="image/*">' + (r.photo ? '<button type="button" id="pm-nophoto">Remove the photo</button>' : '') + '</div></div><div class="hint">A square or 4:3 photo of the bottle or pouch looks best. It is made smaller automatically.</div></div>' +
      '<div class="actions"><button class="primary" id="pm-save">Save</button><button data-close>Cancel</button></div>');
    on(m.el, '#pm-photo', async (e) => {
      try { photo = await shrink(e.target.files[0]); $('#pm-prev', m.el).innerHTML = '<img class="sh-photo" style="width:120px;height:90px" src="' + photo + '" alt="">'; }
      catch (x) { RB.modalMsg(m, x.message); }
    }, 'change');
    on(m.el, '#pm-nophoto', () => { photo = ''; $('#pm-prev', m.el).innerHTML = '<span class="muted">No photo</span>'; });
    on(m.el, '#pm-save', async () => {
      const p = { pack_id: r.pack_id, visible: $('#pm-vis', m.el).checked, cod_allowed: $('#pm-cod', m.el).checked, description: $('#pm-desc', m.el).value, sort: $('#pm-sort', m.el).value };
      if (photo !== undefined) p.photo = photo;
      try { await RB.rpc('rb_shop_save_product', { p }); m.close(); RB.toast('Saved'); done(); } catch (e) { RB.modalMsg(m, e.message); }
    });
  }

  // ===================================================================
  // Shop set-up: link, payment, delivery charges, alerts
  // ===================================================================
  async function setupTab(tb) {
    const s = await RB.rpc('rb_shop_settings'), can = setup(), dis = can ? '' : ' disabled';
    const url = shopUrl();
    const chk = (id, v, t) => '<label class="check"><input type="checkbox" id="' + id + '"' + (v ? ' checked' : '') + dis + '> ' + t + '</label>';
    tb.innerHTML = '<div class="card"><h2>The shop link</h2><p>Share this link on WhatsApp and Instagram. Customers need no password.</p>' +
      '<p class="sh-link"><b>' + esc(url) + '</b></p><div class="actions"><button id="ss-copy">Copy the link</button>' +
      RB.shareButtons({ subject: 'Order Ruchi Buds online', text: 'Order Ruchi Buds online: ' + url }) +
      '<a class="btn" target="_blank" rel="noopener" href="' + esc(url) + '">Open the shop</a></div>' +
      '<p>The shop is <b>' + (s.shop_open ? 'open' : 'closed') + '</b>.</p></div>' +
      (can ? '' : '<div class="msg info">Only a Director or the FC can change the shop set-up.</div>') +
      '<form class="card" id="ss-form"><h2>Shop and payment</h2>' +
      chk('ss-open', s.shop_open, '<b>Shop open</b> (customers can order)') +
      '<div class="field"><label for="ss-note">Message at the top of the shop</label><input id="ss-note" maxlength="500" value="' + esc(s.shop_note || '') + '" placeholder="e.g. Orders placed before 2 PM are delivered the same day in Kochi"' + dis + '></div>' +
      '<div class="row"><div class="field"><label for="ss-phone">Phone number customers can call</label><input id="ss-phone" value="' + esc(s.shop_phone || '') + '"' + dis + '></div>' +
      '<div class="field"><label for="ss-hold">Keep unpaid UPI orders for (minutes)</label><input id="ss-hold" inputmode="numeric" value="' + s.shop_hold_minutes + '"' + dis + '><div class="hint">After this, the items are free to sell again.</div></div>' +
      '<div class="field"><label for="ss-max">Unpaid orders allowed per phone number</label><input id="ss-max" inputmode="numeric" value="' + s.shop_max_unpaid + '"' + dis + '></div></div>' +
      '<h3>UPI</h3>' + chk('ss-upi', s.shop_pay_upi, 'Customers can pay by UPI') +
      '<div class="row"><div class="field"><label for="ss-upiid">UPI ID the money goes to</label><input id="ss-upiid" value="' + esc(s.shop_upi_id || '') + '" placeholder="e.g. ruchibuds@okaxis"' + dis + '>' +
      '<div class="hint">The UPI ID of <b>Bank account 1</b>: UPI payments are booked there.' + (s.upi_accounts.length ? ' In Cash and bank: ' + esc(s.upi_accounts.join(', ')) : '') + '</div></div>' +
      '<div class="field"><label for="ss-upiname">Name shown to the customer</label><input id="ss-upiname" value="' + esc(s.shop_upi_name || '') + '" placeholder="Ruchi Buds"' + dis + '></div></div>' +
      '<h3>Cash on delivery</h3>' + chk('ss-cod', s.shop_pay_cod, 'Cash on delivery (only for packs ticked "Cash on delivery allowed")') +
      '<h3>Delivery and pickup</h3>' + chk('ss-del', s.shop_delivery, 'Home delivery (charges by PIN code below)') + chk('ss-pick', s.shop_pickup, 'Pickup') +
      '<div class="field"><label for="ss-pickaddr">Pickup address</label><input id="ss-pickaddr" value="' + esc(s.shop_pickup_address || '') + '"' + dis + '></div>' +
      '<h3>Alerts for new paid and cash-on-delivery orders</h3><p class="muted">The people in these categories see an alert in the app and get an email (which their phone shows as a notification). WhatsApp is not automatic: use the <b>Message on WhatsApp</b> button on an order.</p>' +
      '<div class="row">' + s.categories.map((c) => '<label class="check" style="flex:0 1 220px"><input type="checkbox" data-cat="' + c.id + '"' + (s.shop_alert_categories.includes(c.id) ? ' checked' : '') + dis + '> ' + esc(c.name) + '</label>').join('') + '</div>' +
      (can ? '<div id="ss-msg"></div><div class="actions"><button class="primary" type="submit">Save</button></div>' : '') + '</form>' +
      '<div class="card"><h2>Delivery charges by PIN code</h2><p class="muted">Added to the order automatically. <b>*</b> means every other PIN code; without it, the shop does not deliver to PIN codes not in the list. Staff can change the charge on an order before it is paid.</p>' +
      '<div id="ss-areas"></div>' + (can ? '<div class="actions"><button id="ss-add">Add a PIN code</button></div>' : '') + '</div>' +
      '<div class="card"><h2>Notifications on this device</h2><p class="muted">While the app is open, new paid and cash-on-delivery orders also show as a notification on this phone or computer.</p>' +
      '<button id="ss-notify">Allow notifications here</button> <span id="ss-notify-msg" class="muted"></span></div>' +
      (s.with_gst ? '' : '<div class="msg info"><b>Check with your CA:</b> how online sales affect GST registration and invoices (for example, selling to other states). Until the firm is GST registered, online orders are invoiced without GST.</div>');
    on(tb, '#ss-copy', async () => { try { await navigator.clipboard.writeText(url); RB.toast('Link copied'); } catch (e) { RB.toast(url); } });
    on(tb, '#ss-notify', async () => {
      const msg = $('#ss-notify-msg', tb);
      if (!('Notification' in window)) { msg.textContent = 'This browser cannot show notifications.'; return; }
      const r = await Notification.requestPermission();
      msg.textContent = r === 'granted' ? 'Notifications are on for this device.' : 'Notifications are blocked in this browser\'s settings.';
    });
    const grid = RB.grid($('#ss-areas', tb), [
      { title: 'PIN code', field: 'pin_code', width: 120, formatter: (c) => (c.getValue() === '*' ? '<b>*</b> every other' : esc(c.getValue())) + RB.demoBadge(c.getRow().getData()) },
      { title: 'Area', field: 'area_name', minWidth: 160 },
      { title: 'Charge', field: 'charge_paise', hozAlign: 'right', headerFilter: false, formatter: (c) => (c.getValue() ? money(c.getValue()) : 'Free') },
      { title: 'Status', field: 'is_active', width: 100, headerFilter: false, formatter: (c) => (c.getValue() ? RB.badge('active', 'On') : RB.badge('inactive', 'Off')) },
    ], s.areas);
    if (can) {
      grid.on('rowClick', (e, row) => areaModal(row.getData(), () => setupTab(tb)));
      on(tb, '#ss-add', () => areaModal({ is_active: true }, () => setupTab(tb)));
      on(tb, '#ss-form', async (e) => {
        e.preventDefault();
        const v = (id) => $('#' + id, tb).value, c = (id) => $('#' + id, tb).checked;
        try {
          await RB.rpc('rb_shop_save_settings', { p: { shop_open: c('ss-open'), shop_note: v('ss-note'), shop_phone: v('ss-phone'), shop_hold_minutes: v('ss-hold'),
            shop_max_unpaid: v('ss-max'), shop_pay_upi: c('ss-upi'), shop_upi_id: v('ss-upiid'), shop_upi_name: v('ss-upiname'), shop_pay_cod: c('ss-cod'),
            shop_delivery: c('ss-del'), shop_pickup: c('ss-pick'), shop_pickup_address: v('ss-pickaddr'),
            shop_alert_categories: $$('[data-cat]', tb).filter((x) => x.checked).map((x) => Number(x.dataset.cat)) } });
          RB.toast('Saved'); setupTab(tb);
        } catch (x) { $('#ss-msg', tb).innerHTML = '<div class="msg error">' + esc(x.message) + '</div>'; }
      }, 'submit');
    }
  }

  function areaModal(a, done) {
    const m = RB.modal('<h2>' + (a.id ? 'Delivery to ' + esc(a.pin_code) : 'Add a PIN code') + '</h2><div class="m-msg"></div>' +
      '<div class="row"><div class="field"><label for="am-pin">PIN code (* = every other)</label><input id="am-pin" maxlength="6" value="' + esc(a.pin_code || '') + '"></div>' +
      '<div class="field"><label for="am-name">Area name</label><input id="am-name" value="' + esc(a.area_name || '') + '"></div>' +
      '<div class="field"><label for="am-chg">Charge (₹, 0 = free)</label><input id="am-chg" inputmode="decimal" value="' + (a.charge_paise != null ? a.charge_paise / 100 : '') + '"></div></div>' +
      '<label class="check"><input type="checkbox" id="am-on"' + (a.is_active ? ' checked' : '') + '> Deliver here</label>' +
      '<div class="actions"><button class="primary" id="am-save">Save</button>' + (a.id ? '<button class="danger" id="am-del">Remove</button>' : '') + '<button data-close>Cancel</button></div>');
    on(m.el, '#am-save', async () => {
      try {
        await RB.rpc('rb_shop_save_area', { p: { id: a.id || null, pin_code: $('#am-pin', m.el).value, area_name: $('#am-name', m.el).value,
          charge_paise: paise($('#am-chg', m.el).value), is_active: $('#am-on', m.el).checked } });
        m.close(); RB.toast('Saved'); done();
      } catch (e) { RB.modalMsg(m, e.message); }
    });
    on(m.el, '#am-del', async () => { try { await RB.rpc('rb_shop_delete_area', { p_id: a.id }); m.close(); done(); } catch (e) { RB.modalMsg(m, e.message); } });
  }

  // ===================================================================
  // Report: orders, value, paid by UPI, COD, cancelled, by day and product
  // ===================================================================
  async function reportTab(tb) {
    tb.innerHTML = '<div class="row" style="align-items:flex-end"><div class="field" style="flex:0 1 180px"><label for="sr-from">From</label><input type="date" id="sr-from" value="' + monthStart() + '"></div>' +
      '<div class="field" style="flex:0 1 180px"><label for="sr-to">To</label><input type="date" id="sr-to" value="' + RB.today() + '"></div>' +
      '<div class="field" style="flex:0 1 auto"><button id="sr-go">Show</button></div></div><div id="sr-body"></div>';
    const load = async () => {
      const r = await RB.rpc('rb_shop_report', { p_from: $('#sr-from', tb).value, p_to: $('#sr-to', tb).value }), t = r.totals, box = $('#sr-body', tb);
      box.innerHTML = '<div class="kpis">' +
        '<div><small>Orders</small><b>' + t.orders + '</b><small>' + t.invoiced + ' invoiced</small></div>' +
        '<div><small>Value</small><b>' + money(t.value_paise) + '</b></div>' +
        '<div><small>Paid by UPI</small><b>' + money(t.upi_paise) + '</b><small>' + t.upi_orders + ' orders</small></div>' +
        '<div><small>Cash on delivery</small><b>' + money(t.cod_paise) + '</b><small>' + t.cod_orders + ' orders</small></div>' +
        '<div><small>Cancelled</small><b>' + t.cancelled + '</b><small>' + money(t.cancelled_paise) + '; ' + t.expired + ' not paid in time</small></div></div>' +
        '<div class="card"><h2>By day</h2><div class="actions" style="margin:0 0 .5rem"><button id="sr-dx">Download to Excel</button></div><div id="sr-day"></div></div>' +
        '<div class="card"><h2>By product</h2><div class="actions" style="margin:0 0 .5rem"><button id="sr-px">Download to Excel</button></div><div id="sr-prod"></div></div>';
      const g1 = RB.grid($('#sr-day', box), [
        { title: 'Day', field: 'day', width: 130, formatter: (c) => RB.fmtDate(c.getValue()) },
        { title: 'Orders', field: 'orders', hozAlign: 'right', headerFilter: false },
        { title: 'Value', field: 'value_paise', hozAlign: 'right', headerFilter: false, formatter: (c) => money(c.getValue()) },
        { title: 'Paid by UPI', field: 'upi_paise', hozAlign: 'right', headerFilter: false, formatter: (c) => money(c.getValue()) },
        { title: 'Cash on delivery', field: 'cod_paise', hozAlign: 'right', headerFilter: false, formatter: (c) => money(c.getValue()) },
        { title: 'Cancelled', field: 'cancelled', hozAlign: 'right', headerFilter: false },
        { title: 'Not paid in time', field: 'expired', hozAlign: 'right', headerFilter: false },
      ], r.by_day);
      const g2 = RB.grid($('#sr-prod', box), [
        { title: 'Product', field: 'product', minWidth: 220, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
        { title: 'Packs', field: 'packs', hozAlign: 'right', headerFilter: false },
        { title: 'Orders', field: 'orders', hozAlign: 'right', headerFilter: false },
        { title: 'Value', field: 'value_paise', hozAlign: 'right', headerFilter: false, formatter: (c) => money(c.getValue()) },
      ], r.by_product);
      on(box, '#sr-dx', () => RB.downloadExcel(g1, 'Online orders by day'));
      on(box, '#sr-px', () => RB.downloadExcel(g2, 'Online orders by product'));
    };
    on(tb, '#sr-go', () => load().catch((e) => RB.toast(e.message, true)));
    await load();
  }

  // ===================================================================
  // Alerts while the app is open: a line on the home screen, a count on
  // the tile, and a notification when a new paid or COD order comes in.
  // ===================================================================
  RB.shopAlerts = async (home) => {
    if (!RB.has('shop.view')) return;
    let a;
    try { a = await RB.rpc('rb_shop_my_alerts'); } catch (e) { return; }
    if (!a) return;
    if (S.lastAlert != null && a.last_id > S.lastAlert && a.alerted) {
      RB.toast('Online shop: ' + a.last_message);
      try { if ('Notification' in window && Notification.permission === 'granted') new Notification('Ruchi Buds online shop', { body: a.last_message, icon: 'assets/icon-192.png' }); } catch (e) { /* not allowed here */ }
    }
    S.lastAlert = a.last_id || 0;
    const n = a.to_check + a.to_pack + a.to_dispatch + a.cash_due;
    const tile = $('a.tile[href="#/shop"]');
    if (tile && n) { const old = $('.count', tile); if (old) old.remove(); tile.insertAdjacentHTML('beforeend', '<span class="count">' + n + ' to do</span>'); }
    if (home && n && !$('#sh-home')) {
      const menu = $('nav.menu');
      if (menu) menu.insertAdjacentHTML('beforebegin', '<div class="msg info sh-alert" id="sh-home"><span><b>Online shop:</b> ' +
        [a.to_check ? a.to_check + ' UPI payment' + (a.to_check > 1 ? 's' : '') + ' to check' : '', a.to_pack ? a.to_pack + ' to pack' : '',
          a.to_dispatch ? a.to_dispatch + ' to dispatch' : '', a.cash_due ? a.cash_due + ' cash on delivery to collect' : ''].filter(Boolean).join(', ') +
        '</span><a class="btn" href="#/shop">Open the orders</a></div>');
    }
  };
  setInterval(() => { if (RB.profile && !document.hidden) RB.shopAlerts(false); }, 60000);
})();
