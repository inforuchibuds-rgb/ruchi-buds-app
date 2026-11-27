// =====================================================================
// RUCHI BUDS APP · shopfront.js · Version 1.0 · 27-Nov-2026
// Module 10: the public online shop (shop.html), no sign-in. Customers
// see the products a Director or the FC put on the shop, with live free
// stock (SOLD OUT when none is free), fill a cart, and order with name,
// phone and address, for delivery or pickup. They pay by UPI (QR code or
// UPI app, then enter the UPI reference for the staff to check) or cash
// on delivery. Their order page (shop.html#o/<link>) shows where the
// order is. Everything goes through the rb_shop_ database functions.
// =====================================================================
(function () {
  'use strict';
  const $ = (s, r) => (r || document).querySelector(s);
  const $$ = (s, r) => Array.from((r || document).querySelectorAll(s));
  const esc = (v) => String(v == null ? '' : v).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  const rs = (p) => '₹' + (Number(p || 0) / 100).toLocaleString('en-IN', { minimumFractionDigits: Number(p) % 100 ? 2 : 0, maximumFractionDigits: 2 });
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const when = (t) => { const d = new Date(t); return d.getDate() + '-' + MONTHS[d.getMonth()] + ' ' + String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0'); };
  const store = {
    get(k, d) { try { const v = localStorage.getItem(k); return v ? JSON.parse(v) : d; } catch (e) { return d; } },
    set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* private window: the cart lives only on this page */ } },
  };
  const S = { cat: null, cart: store.get('rb-shop-cart', {}), form: store.get('rb-shop-form', {}), timer: null };
  let sb;

  const toast = (t, bad) => {
    const el = $('#toast'); el.textContent = t; el.className = bad ? 'error' : '';
    clearTimeout(toast.t); toast.t = setTimeout(() => el.classList.add('hidden'), bad ? 6000 : 2500);
  };
  const friendly = (e) => {
    const m = (e && (e.message || e.msg)) || String(e || 'Something went wrong');
    if (/Failed to fetch|NetworkError/i.test(m)) return 'No internet connection. Please check it and try again.';
    return m.replace(/^ERROR:\s*/, '');
  };
  const rpc = async (name, args) => { const { data, error } = await sb.rpc(name, args || {}); if (error) throw new Error(friendly(error)); return data; };

  function shell(inner) {
    const c = S.cat || {};
    $('#app').innerHTML = '<header class="banner sf-banner"><a href="#" aria-label="Shop"><img class="wordmark" src="assets/wordmark.png" alt="Ruchi Buds"></a>' +
      '<div class="spacer"></div><a class="sf-head-link" href="#cart" id="sf-cart-link">Cart' + (count() ? ' (' + count() + ')' : '') + '</a></header>' +
      (c.training ? '<div class="training-strip">Practice shop: orders placed now are not real</div>' : '') +
      '<main id="page" class="sf-main">' + inner + '</main>';
  }
  const count = () => Object.values(S.cart).reduce((a, n) => a + n, 0);
  const saveCart = () => store.set('rb-shop-cart', S.cart);

  // ---------- start ----------
  async function start() {
    const c = window.RB_CONFIG || {};
    sb = supabase.createClient(c.SUPABASE_URL, c.SUPABASE_ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
    window.addEventListener('hashchange', route);
    await route();
  }

  async function route() {
    clearInterval(S.timer);
    const h = location.hash.replace(/^#\/?/, '');
    try {
      if (/^o\/[0-9a-f]{20,}$/.test(h)) return await orderPage(h.slice(2));
      S.cat = await rpc('rb_shop_catalogue');
      // Drop cart lines that are no longer on the shop.
      const ids = new Set(S.cat.products.map((p) => String(p.pack_id)));
      Object.keys(S.cart).forEach((k) => { if (!ids.has(k)) delete S.cart[k]; });
      saveCart();
      if (h === 'cart') return checkout();
      return catalogue();
    } catch (e) {
      shell('<div class="msg error">' + esc(e.message) + '</div><button onclick="location.reload()">Try again</button>');
    }
  }

  // ---------- the products ----------
  function priceNote(p) {
    const c = S.cat;
    if (!c.with_gst || p.gst_rate == null) return '';
    return c.prices_incl_gst ? 'incl. GST' : '+ GST ' + Number(p.gst_rate) + '%';
  }

  function catalogue() {
    const c = S.cat;
    const mine = store.get('rb-shop-orders', []);
    shell((c.open ? '' : '<div class="msg info"><b>The shop is closed just now.</b> Please come back a little later' + (c.phone ? ', or call us on ' + esc(c.phone) : '') + '.</div>') +
      '<div class="sf-intro"><h1>Order online</h1>' + (c.note ? '<p>' + esc(c.note) + '</p>' : '') +
      '<p class="muted">' + [c.delivery ? 'Home delivery' : '', c.pickup ? 'Pickup from our kitchen' : ''].filter(Boolean).join(' or ') +
      ' · ' + [c.pay_upi ? 'Pay by UPI' : '', c.pay_cod ? 'cash on delivery' : ''].filter(Boolean).join(' or ') + '</p>' +
      (mine.length ? '<p class="muted">Your recent orders: ' + mine.slice(0, 3).map((o) => '<a href="#o/' + esc(o.token) + '">' + esc(o.order_no) + '</a>').join(', ') + '</p>' : '') + '</div>' +
      (c.products.length ? '<div class="sf-grid">' + c.products.map(card).join('') + '</div>' : (c.open ? '<p class="muted">Nothing is on the shop just now.</p>' : '')) +
      '<div class="sf-bar' + (count() ? '' : ' hidden') + '" id="sf-bar"><span id="sf-bar-t"></span><a class="btn primary" href="#cart">View cart</a></div>');
    $$('[data-add]').forEach((b) => b.addEventListener('click', () => bump(Number(b.dataset.add), 1)));
    $$('[data-less]').forEach((b) => b.addEventListener('click', () => bump(Number(b.dataset.less), -1)));
    bar();
  }

  function card(p) {
    const n = S.cart[p.pack_id] || 0, out = p.free <= 0;
    return '<article class="sf-card' + (out ? ' out' : '') + '" data-pack="' + p.pack_id + '">' +
      '<div class="sf-photo">' + (p.photo ? '<img src="' + esc(p.photo) + '" alt="' + esc(p.name) + '" loading="lazy">' : '<span aria-hidden="true">🫙</span>') +
      (out ? '<span class="sf-sold">SOLD OUT</span>' : '') + '</div>' +
      '<div class="sf-body"><h2>' + esc(p.name) + '</h2><div class="muted">' + esc(p.pack) + '</div>' +
      (p.description ? '<p class="sf-desc">' + esc(p.description) + '</p>' : '') +
      '<div class="sf-price">' + rs(p.price_paise) + ' <small>' + esc(priceNote(p)) + '</small></div>' +
      '<div class="sf-tags">' + (!out && p.free <= 5 ? '<span class="badge protected">Only ' + p.free + ' left</span> ' : '') +
      (S.cat.pay_cod && p.cod_allowed ? '<span class="badge active">Cash on delivery</span>' : '') + '</div>' +
      (out ? '<button disabled>Sold out</button>' : (n
        ? '<div class="sf-qty"><button data-less="' + p.pack_id + '" aria-label="One less">−</button><b>' + n + '</b><button data-add="' + p.pack_id + '" aria-label="One more"' + (n >= Math.min(p.free, 50) ? ' disabled' : '') + '>+</button></div>'
        : '<button class="primary" data-add="' + p.pack_id + '">Add to cart</button>')) + '</div></article>';
  }

  function bump(id, d) {
    const p = S.cat.products.find((x) => x.pack_id === id);
    if (!p) return;
    const n = Math.max(0, Math.min((S.cart[id] || 0) + d, Math.min(p.free, 50)));
    if (n) S.cart[id] = n; else delete S.cart[id];
    saveCart();
    if (location.hash === '#cart') return checkout();
    const el = $('[data-pack="' + id + '"]');
    if (el) {
      el.outerHTML = card(p);
      const ne = $('[data-pack="' + id + '"]');
      $$('[data-add]', ne).forEach((b) => b.addEventListener('click', () => bump(id, 1)));
      $$('[data-less]', ne).forEach((b) => b.addEventListener('click', () => bump(id, -1)));
    }
    $('#sf-cart-link').textContent = 'Cart' + (count() ? ' (' + count() + ')' : '');
    bar();
  }

  function bar() {
    const b = $('#sf-bar'); if (!b) return;
    const t = totals(null);
    b.classList.toggle('hidden', !count());
    $('#sf-bar-t').textContent = count() + (count() === 1 ? ' item · ' : ' items · ') + rs(t.goods + t.gst);
  }

  // Same sums as the database (it has the final word).
  function totals(dl) {
    const c = S.cat; let goods = 0, gst = 0, top = 0;
    const addGst = c.with_gst && !c.prices_incl_gst;
    Object.entries(S.cart).forEach(([id, n]) => {
      const p = c.products.find((x) => String(x.pack_id) === id); if (!p) return;
      const a = n * p.price_paise; goods += a;
      if (addGst && p.gst_rate != null) { gst += Math.round(a * p.gst_rate / 100); top = Math.max(top, Number(p.gst_rate)); }
    });
    if (addGst && dl) gst += Math.round(dl * top / 100);
    return { goods, gst, dl: dl || 0, total: goods + gst + (dl || 0) };
  }

  // ---------- the cart and the order form ----------
  function deliveryFor(pin) {
    const a = S.cat.areas.find((x) => x.pin_code === pin) || S.cat.areas.find((x) => x.pin_code === '*');
    return a ? a.charge_paise : null;
  }

  function checkout() {
    const c = S.cat, f = S.form;
    const lines = Object.entries(S.cart).map(([id, n]) => ({ p: c.products.find((x) => String(x.pack_id) === id), n })).filter((x) => x.p);
    if (!lines.length) {
      shell('<h1>Your cart</h1><p>Your cart is empty.</p><a class="btn primary" href="#">See the products</a>');
      return;
    }
    if (!f.fulfil || (f.fulfil === 'delivery' && !c.delivery) || (f.fulfil === 'pickup' && !c.pickup)) f.fulfil = c.delivery ? 'delivery' : 'pickup';
    const codOk = c.pay_cod && lines.every((x) => x.p.cod_allowed);
    if (!f.pay || (f.pay === 'cod' && !codOk) || (f.pay === 'upi' && !c.pay_upi)) f.pay = c.pay_upi ? 'upi' : 'cod';
    shell('<div class="page-head"><a class="back" href="#">‹ More products</a><h1>Your cart</h1></div>' +
      '<div class="sf-check"><div class="card"><table class="sf-lines"><tbody>' + lines.map((x) =>
        '<tr><td><b>' + esc(x.p.name) + '</b><br><span class="muted">' + esc(x.p.pack) + ' · ' + rs(x.p.price_paise) + ' each</span></td>' +
        '<td><div class="sf-qty"><button data-less="' + x.p.pack_id + '" aria-label="One less">−</button><b>' + x.n + '</b><button data-add="' + x.p.pack_id + '" aria-label="One more"' + (x.n >= Math.min(x.p.free, 50) ? ' disabled' : '') + '>+</button></div></td>' +
        '<td class="n">' + rs(x.n * x.p.price_paise) + '</td></tr>').join('') + '</tbody></table></div>' +
      '<form class="card" id="sf-form" novalidate><h2>Your details</h2>' +
      '<div class="field"><label for="sf-name">Name</label><input id="sf-name" autocomplete="name" maxlength="80" value="' + esc(f.name) + '"></div>' +
      '<div class="field"><label for="sf-phone">Mobile number</label><input id="sf-phone" type="tel" inputmode="numeric" autocomplete="tel" maxlength="16" placeholder="10 digits" value="' + esc(f.phone) + '"></div>' +
      '<label>Delivery or pickup</label><div class="switch" id="sf-ful">' +
      (c.delivery ? '<button type="button" data-v="delivery"' + (f.fulfil === 'delivery' ? ' class="on"' : '') + '>Deliver to me</button>' : '') +
      (c.pickup ? '<button type="button" data-v="pickup"' + (f.fulfil === 'pickup' ? ' class="on"' : '') + '>I will pick it up</button>' : '') + '</div>' +
      '<div id="sf-del"' + (f.fulfil === 'delivery' ? '' : ' class="hidden"') + '>' +
      '<div class="field"><label for="sf-addr">Delivery address</label><textarea id="sf-addr" autocomplete="street-address" maxlength="300">' + esc(f.address) + '</textarea></div>' +
      '<div class="field" style="max-width:220px"><label for="sf-pin">PIN code</label><input id="sf-pin" inputmode="numeric" autocomplete="postal-code" maxlength="7" value="' + esc(f.pin) + '"></div>' +
      '<div id="sf-pin-msg" class="muted"></div></div>' +
      '<div id="sf-pick"' + (f.fulfil === 'pickup' ? '' : ' class="hidden"') + '><p class="muted">Pick up from: ' + esc(c.pickup_address || 'our kitchen (we will tell you where)') + '</p></div>' +
      '<h2>How you will pay</h2>' +
      (c.pay_upi ? '<label class="check"><input type="radio" name="sf-pay" value="upi"' + (f.pay === 'upi' ? ' checked' : '') + '> Pay now by UPI (Google Pay, PhonePe, Paytm, BHIM…)</label>' : '') +
      (c.pay_cod ? '<label class="check"><input type="radio" name="sf-pay" value="cod"' + (f.pay === 'cod' ? ' checked' : '') + (codOk ? '' : ' disabled') + '> Cash on delivery' +
        (codOk ? '' : ' <span class="muted">(not for every item in your cart)</span>') + '</label>' : '') +
      '<div class="field"><label for="sf-note">Anything we should know? (optional)</label><input id="sf-note" maxlength="300" value="' + esc(f.note) + '"></div>' +
      '<div class="sf-sum" id="sf-sum"></div>' +
      '<div id="sf-msg"></div><button class="primary sf-go" type="submit" id="sf-go">Place order</button>' +
      '<p class="muted" id="sf-hold"></p></form></div>');
    $$('[data-add]').forEach((b) => b.addEventListener('click', () => bump(Number(b.dataset.add), 1)));
    $$('[data-less]').forEach((b) => b.addEventListener('click', () => bump(Number(b.dataset.less), -1)));
    const keep = () => {
      Object.assign(S.form, { name: $('#sf-name').value, phone: $('#sf-phone').value, address: $('#sf-addr') ? $('#sf-addr').value : '', pin: $('#sf-pin') ? $('#sf-pin').value : '', note: $('#sf-note').value });
      const r = $$('[name=sf-pay]').find((x) => x.checked); if (r) S.form.pay = r.value;
      store.set('rb-shop-form', { name: S.form.name, phone: S.form.phone, address: S.form.address, pin: S.form.pin, fulfil: S.form.fulfil });
      sums();
    };
    $$('#sf-ful button').forEach((b) => b.addEventListener('click', () => {
      S.form.fulfil = b.dataset.v;
      $$('#sf-ful button').forEach((x) => x.classList.toggle('on', x === b));
      $('#sf-del').classList.toggle('hidden', S.form.fulfil !== 'delivery');
      $('#sf-pick').classList.toggle('hidden', S.form.fulfil !== 'pickup');
      keep();
    }));
    $$('#sf-form input, #sf-form textarea').forEach((i) => i.addEventListener('input', keep));
    $$('[name=sf-pay]').forEach((i) => i.addEventListener('change', keep));
    $('#sf-form').addEventListener('submit', (e) => { e.preventDefault(); keep(); place(); });
    sums();
  }

  function sums() {
    const c = S.cat, f = S.form;
    let dl = 0, pinMsg = '';
    if (f.fulfil === 'delivery') {
      const pin = String(f.pin || '').replace(/\s/g, '');
      if (/^[1-9]\d{5}$/.test(pin)) {
        dl = deliveryFor(pin);
        pinMsg = dl == null ? '<span class="diff">Sorry, we do not deliver to ' + esc(pin) + ' yet. Please choose pickup' + (c.phone ? ', or call us on ' + esc(c.phone) : '') + '.</span>'
          : 'Delivery to ' + esc(pin) + ': ' + (dl ? rs(dl) : 'free');
      } else if (pin) pinMsg = 'Enter the 6-digit PIN code.';
      $('#sf-pin-msg').innerHTML = pinMsg;
    }
    const t = totals(dl || 0);
    $('#sf-sum').innerHTML = '<div><span>Items</span><b>' + rs(t.goods) + '</b></div>' +
      (f.fulfil === 'delivery' ? '<div><span>Delivery</span><b>' + (dl == null ? '—' : dl ? rs(dl) : 'Free') + '</b></div>' : '') +
      (t.gst ? '<div><span>GST</span><b>' + rs(t.gst) + '</b></div>' : '') +
      '<div class="sf-total"><span>To pay</span><b>' + rs(t.total) + '</b></div>' +
      (c.with_gst && c.prices_incl_gst ? '<small class="muted">Prices include GST.</small>' : '');
    $('#sf-go').disabled = f.fulfil === 'delivery' && dl == null;
    $('#sf-hold').textContent = f.pay === 'upi' ? 'Your items are kept for you for ' + c.hold_minutes + ' minutes while you pay by UPI.' : '';
  }

  async function place() {
    const f = S.form, msg = $('#sf-msg'), go = $('#sf-go');
    msg.innerHTML = '';
    if (!String(f.name || '').trim()) { msg.innerHTML = '<div class="msg error">Please enter your name.</div>'; return; }
    if (String(f.phone || '').replace(/\D/g, '').length < 10) { msg.innerHTML = '<div class="msg error">Please enter your 10-digit mobile number.</div>'; return; }
    go.disabled = true; go.textContent = 'Placing your order…';
    try {
      const r = await rpc('rb_shop_place', { p: {
        name: f.name, phone: f.phone, fulfil: f.fulfil, address: f.fulfil === 'delivery' ? f.address : null, pin_code: f.fulfil === 'delivery' ? f.pin : null,
        note: f.note, pay_method: f.pay, lines: Object.entries(S.cart).map(([id, n]) => ({ pack_id: Number(id), packs: n })) } });
      S.cart = {}; saveCart(); S.form.note = '';
      const mine = store.get('rb-shop-orders', []); mine.unshift({ token: r.token, order_no: r.order_no }); store.set('rb-shop-orders', mine.slice(0, 10));
      location.hash = '#o/' + r.token;
    } catch (e) {
      msg.innerHTML = '<div class="msg error">' + esc(e.message) + '</div>';
      go.disabled = false; go.textContent = 'Place order';
      // Stock may have changed: refresh the free counts quietly.
      try { S.cat = await rpc('rb_shop_catalogue'); } catch (x) { /* keep the old list */ }
    }
  }

  // ---------- the customer's order page ----------
  const HEAD = {
    placed: ['Please pay by UPI', ''],
    payment_check: ['Thank you! We are checking your payment', 'We will start packing as soon as the payment is confirmed.'],
    paid: ['Paid. We are packing your order', ''],
    cod: ['Order received', ''],
    packed: ['Packed and ready', ''],
    dispatched: ['On its way', ''],
    delivered: ['Thank you!', ''],
    cancelled: ['This order was cancelled', ''],
    expired: ['The time to pay ran out', ''],
  };

  async function orderPage(token) {
    let o;
    try { o = await rpc('rb_shop_order', { p_token: token }); }
    catch (e) { shell('<div class="msg error">' + esc(e.message) + '</div><a class="btn" href="#">Go to the shop</a>'); return; }
    const pick = o.fulfil === 'pickup', cod = o.pay_method === 'cod';
    let sub = HEAD[o.status][1];
    if (o.status === 'cod') sub = 'Please pay ' + rs(o.total_paise) + ' in cash ' + (pick ? 'when you pick it up.' : 'when it arrives.') + ' We will let you know when it is ready.';
    if (o.status === 'paid') sub = 'Your payment of ' + rs(o.total_paise) + ' is confirmed.';
    if (o.status === 'packed') sub = pick ? 'Your order is ready for pickup' + (o.pickup_address ? ' at ' + o.pickup_address : '') + '.' : 'It will be on its way soon.';
    if (o.status === 'dispatched') sub = pick ? 'Handed over.' : (cod ? 'Please keep ' + rs(o.total_paise) + ' ready to pay in cash.' : '');
    if (o.status === 'delivered') sub = (pick ? 'Picked up' : 'Delivered') + (o.invoice_no ? '. Invoice ' + o.invoice_no : '') + '. We hope you enjoy it.';
    if (o.status === 'expired') sub = 'We did not receive the payment in time, so the items are no longer kept for you. If you have already paid, enter the UPI reference below.';
    const upiLink = o.upi_id ? 'upi://pay?pa=' + encodeURIComponent(o.upi_id) + '&pn=' + encodeURIComponent(o.upi_name || 'Ruchi Buds') +
      '&am=' + (o.total_paise / 100).toFixed(2) + '&cu=INR&tn=' + encodeURIComponent(o.order_no) : null;
    const askRef = !cod && (o.status === 'placed' || o.status === 'expired');
    shell('<div class="sf-order">' +
      '<div class="card sf-status ' + esc(o.status) + '"><small>Order ' + esc(o.order_no) + ' · ' + when(o.placed_at) + (o.is_demo ? ' · DEMO' : '') + '</small>' +
      '<h1>' + esc(HEAD[o.status][0]) + '</h1>' + (sub ? '<p>' + esc(sub) + '</p>' : '') +
      (o.status === 'placed' && o.hold_until ? '<p class="sf-timer">Please pay within <b id="sf-left"></b>.</p>' : '') + '</div>' +
      (o.status === 'placed' && upiLink ? '<div class="card sf-pay"><h2>Pay ' + rs(o.total_paise) + '</h2>' +
        '<div class="sf-qr" id="sf-qr" aria-label="UPI QR code"></div>' +
        '<p class="muted">Scan with any UPI app, or on this phone:</p>' +
        '<a class="btn primary" href="' + esc(upiLink) + '">Open my UPI app</a>' +
        '<p>UPI ID: <b>' + esc(o.upi_id) + '</b> <button type="button" id="sf-copy-upi">Copy</button><br><span class="muted">To: ' + esc(o.upi_name) + '. Please write ' + esc(o.order_no) + ' in the note.</span></p></div>' : '') +
      (askRef ? '<form class="card" id="sf-ref"><h2>After paying</h2><div class="field"><label for="sf-utr">UPI reference (UTR) number</label>' +
        '<input id="sf-utr" inputmode="numeric" autocomplete="off" maxlength="40" placeholder="12 digits, from your UPI app"><div class="hint">In your UPI app, open the payment: it is called UPI Ref. No., UTR or Transaction ID.</div></div>' +
        '<div id="sf-ref-msg"></div><button class="primary" type="submit">I have paid</button></form>' : '') +
      (o.status === 'payment_check' ? '<div class="card"><p>Your UPI reference: <b>' + esc(o.upi_ref) + '</b></p></div>' : '') +
      '<div class="card"><h2>Your order</h2><table class="sf-lines"><tbody>' + o.lines.map((l) =>
        '<tr><td>' + esc(l.description) + '<br><span class="muted">' + l.packs + ' × ' + rs(l.rate_paise) + '</span></td><td class="n">' + rs(l.amount_paise) + '</td></tr>').join('') +
      '</tbody></table><div class="sf-sum"><div><span>Items</span><b>' + rs(o.goods_paise) + '</b></div>' +
      (pick ? '' : '<div><span>Delivery</span><b>' + (o.delivery_paise ? rs(o.delivery_paise) : 'Free') + '</b></div>') +
      (o.gst_paise ? '<div><span>GST</span><b>' + rs(o.gst_paise) + '</b></div>' : '') +
      '<div class="sf-total"><span>' + (cod ? 'To pay in cash' : 'Total') + '</span><b>' + rs(o.total_paise) + '</b></div></div>' +
      '<p class="muted">' + esc(o.name) + ' · ' + esc(o.phone) + '<br>' + (pick ? 'Pickup' + (o.pickup_address ? ' from ' + esc(o.pickup_address) : '') : 'Deliver to: ' + esc(o.address) + ' ' + esc(o.pin_code)) + '</p></div>' +
      '<div class="card"><p class="muted">Keep this page to see where your order is.</p><div class="actions">' +
      '<button type="button" id="sf-copy">Copy the link</button>' +
      '<a class="btn" target="_blank" rel="noopener" href="https://wa.me/?text=' + encodeURIComponent('My ' + (o.firm_name || 'Ruchi Buds') + ' order ' + o.order_no + ': ' + location.href) + '">Save it on WhatsApp</a>' +
      '<button type="button" id="sf-refresh">Refresh</button>' +
      (['placed', 'cod', 'expired'].includes(o.status) ? '<button type="button" class="danger" id="sf-cancel">Cancel this order</button>' : '') + '</div>' +
      (o.phone_us ? '<p class="muted">Questions? Call us on <a href="tel:' + esc(o.phone_us) + '">' + esc(o.phone_us) + '</a>.</p>' : '') + '</div>' +
      '<a class="btn" href="#">Back to the shop</a></div>');
    if ($('#sf-qr')) {
      try { const q = qrcode(0, 'M'); q.addData(upiLink); q.make(); $('#sf-qr').innerHTML = q.createSvgTag({ cellSize: 6, margin: 2, scalable: true }); }
      catch (e) { $('#sf-qr').remove(); }
    }
    const copy = async (t) => { try { await navigator.clipboard.writeText(t); toast('Copied'); } catch (e) { toast(t); } };
    if ($('#sf-copy-upi')) $('#sf-copy-upi').addEventListener('click', () => copy(o.upi_id));
    $('#sf-copy').addEventListener('click', () => copy(location.href));
    $('#sf-refresh').addEventListener('click', () => orderPage(token));
    if ($('#sf-cancel')) $('#sf-cancel').addEventListener('click', async (e) => {
      const b = e.currentTarget;
      if (!b.dataset.sure) { b.dataset.sure = '1'; b.textContent = 'Tap again to cancel ' + o.order_no; return; }
      try { await rpc('rb_shop_public_cancel', { p_token: token }); orderPage(token); } catch (e) { toast(e.message, true); }
    });
    if ($('#sf-ref')) $('#sf-ref').addEventListener('submit', async (e) => {
      e.preventDefault();
      const m = $('#sf-ref-msg');
      try { await rpc('rb_shop_submit_ref', { p_token: token, p_ref: $('#sf-utr').value }); orderPage(token); }
      catch (x) { m.innerHTML = '<div class="msg error">' + esc(x.message) + '</div>'; }
    });
    clearInterval(S.timer);
    if (o.status === 'placed' && o.hold_until) {
      const tick = () => {
        const s = Math.max(0, Math.round((new Date(o.hold_until) - Date.now()) / 1000));
        const el = $('#sf-left'); if (el) el.textContent = Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
        if (!s) { clearInterval(S.timer); orderPage(token); }
      };
      tick(); S.timer = setInterval(tick, 1000);
    } else if (['payment_check', 'paid', 'cod', 'packed', 'dispatched'].includes(o.status)) {
      S.timer = setInterval(() => { if (!document.hidden) orderPage(token); }, 60000);
    }
  }

  start();
})();
