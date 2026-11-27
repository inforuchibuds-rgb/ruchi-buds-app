// =====================================================================
// RUCHI BUDS APP · settings.js · Version 1.3 · 27-Nov-2026
// Firm details, partners and profit share, entry rules, word mark,
// training mode and go-live, demo data, backups and the keep-awake check.
// Module 6 adds: expense approval limit and the CA's rates for doubtful debts.
// =====================================================================
(function () {
  'use strict';
  const RB = window.RB, $ = RB.$, $$ = RB.$$, esc = RB.esc;
  const TRADER_FIELDS = [['phone', 'Phone'], ['address', 'Address'], ['email', 'Email'], ['gstin', 'GSTIN'],
    ['contact_person', 'Contact person'], ['credit_limit', 'Credit limit'], ['credit_days', 'Credit days']];

  RB.screens.settings = async (body) => {
    const s = await RB.select('app_settings', '*', (q) => q.eq('id', 1).single());
    const edit = RB.has('settings.edit'), dis = edit ? '' : ' disabled';
    const inp = (id, label, val, extra) => '<div class="field"><label for="st-' + id + '">' + label + '</label><input id="st-' + id + '" value="' + esc(val || '') + '"' + dis + (extra || '') + '></div>';

    body.innerHTML =
      (edit ? '' : '<div class="msg info">You can look at the settings. Only people with Settings → Edit can change them.</div>') +
      // ---- firm details
      '<section class="card"><h2>Firm details</h2><p class="muted">These appear on invoices.</p>' +
      '<div class="row">' + inp('firm_name', 'Firm name', s.firm_name) +
      '<div class="field"><label for="st-legal">Business type</label><select id="st-legal"' + dis + '>' +
      ['Partnership', 'LLP'].map((v) => '<option' + (s.legal_form === v ? ' selected' : '') + '>' + v + '</option>').join('') + '</select>' +
      '<div class="hint">Switch to LLP when the firm converts. Past entries stay as they are.</div></div></div>' +
      '<div class="row">' + inp('firm_reg_no', 'Firm Reg. no.', s.firm_reg_no) + inp('llpin', 'LLPIN (after LLP)', s.llpin) + inp('fssai_no', 'FSSAI no.', s.fssai_no) + '</div>' +
      '<div class="row">' + inp('gstin', 'GSTIN (if registered)', s.gstin) +
      '<div class="field"><label for="st-gstfrom">GST registered from</label><input id="st-gstfrom" type="date" value="' + esc(s.gst_registered_from || '') + '"' + dis + '>' +
      '<div class="hint">The effective date on the GST certificate. Purchase bills dated from this day claim GST back; earlier bills add GST to the cost of stock. Sales dated from this day can be Tax Invoices with GST; before it, invoices carry no GST.</div></div>' +
      inp('state_code', 'State code', s.state_code) + '</div>' +
      '<div class="field"><label for="st-address">Registered address</label><textarea id="st-address"' + dis + '>' + esc(s.address || '') + '</textarea></div>' +
      '<div class="row">' + inp('phone', 'Phone', s.phone) + inp('email', 'Email', s.email) + '</div>' +
      '<div class="row"><div class="field"><label>Entity code</label><input value="' + esc(s.entity_code) + '" disabled><div class="hint">Group code from the Master COA.</div></div>' +
      '<div class="field"><label>Currency</label><input value="' + esc(s.currency) + '" disabled></div>' +
      '<div class="field"><label>Financial year</label><input value="April to March" disabled></div></div></section>' +
      // ---- partners
      '<section class="card"><h2>Partners and profit share</h2><p class="muted">Profit and loss is shared in this ratio. Use whole numbers: 1, 1, 1 means one third each.</p>' +
      '<div id="st-partners"></div>' + (edit ? '<button type="button" id="st-addp">+ Add partner</button>' : '') +
      '<p id="st-ratio" class="muted" style="margin-top:.5rem"></p></section>' +
      // ---- rules
      '<section class="card"><h2>Entry rules</h2>' +
      '<h3>Trader customers: required fields</h3><p class="muted">Name is always required. Tick the other fields staff must fill for a trader.</p><div class="row">' +
      TRADER_FIELDS.map(([k, t]) => '<label class="check"><input type="checkbox" data-trader="' + k + '"' + ((s.trader_required_fields || []).includes(k) ? ' checked' : '') + dis + '> ' + t + '</label>').join('') +
      '</div><div class="row">' +
      '<div class="field"><label for="st-dplimit">Direct purchases above this need approval (₹)</label><input id="st-dplimit" type="number" min="0" step="1" value="' +
      (s.direct_purchase_approval_limit_paise == null ? '' : s.direct_purchase_approval_limit_paise / 100) + '"' + dis + '><div class="hint">Only the Accountant, FC or a Director can approve them. Blank means no approval is needed.</div></div>' +
      '<div class="field"><label for="st-flimit">Lock an account after this many wrong passwords</label><input id="st-flimit" type="number" min="3" max="20" value="' + s.failed_login_limit + '"' + dis + '></div>' +
      '</div></section>' +
      // ---- sales and invoices (once 05_sales_invoices.sql has run)
      (!('sale_prices_include_gst' in s) ? '' : '<section class="card"><h2>Sales and invoices</h2>' +
      '<label class="check"><input type="checkbox" id="st-incl"' + (s.sale_prices_include_gst !== false ? ' checked' : '') + dis + '> Prices in Masters include GST</label>' +
      '<div class="hint">Only matters once the firm is GST registered. Ticked: a ₹100 pouch costs the customer ₹100 and the GST is worked out of it. Not ticked: GST is added on top.</div>' +
      '<div class="field"><label for="st-footer">Line at the bottom of every invoice</label><textarea id="st-footer"' + dis + ' placeholder="e.g. Thank you! Goods once sold are taken back only if the seal is unbroken.">' + esc(s.invoice_footer || '') + '</textarea></div>' +
      '<div class="row"><div class="field" style="flex:0 1 260px"><label for="st-linkdays">Statement links work for (days)</label><input id="st-linkdays" type="number" min="1" max="365" value="' + esc(s.statement_link_days || 30) + '"' + dis + '>' +
      '<div class="hint">A customer can open a shared statement link without a password until it runs out. It can be switched off at any time.</div></div></div></section>') +
      // ---- expenses and month-end (once 06_cash_bank.sql has run)
      (!('doubtful_debt_bands' in s) ? '' : '<section class="card"><h2>Expenses and month-end</h2>' +
      '<div class="row"><div class="field" style="flex:0 1 320px"><label for="st-exlimit">Expenses above this need approval (₹)</label><input id="st-exlimit" type="number" min="0" step="1" value="' +
      (s.expense_approval_limit_paise == null ? '' : s.expense_approval_limit_paise / 100) + '"' + dis + '><div class="hint">Approved by the Accountant, the FC or a Director. Blank means no approval is needed.</div></div></div>' +
      '<h3>Provision for doubtful debts: the CA\'s rates</h3>' +
      (s.doubtful_debt_rates_example ? '<div class="msg error">These rates are only an example. Enter the rates the CA gives you and press Save settings.</div>' : '') +
      '<p class="muted">At each month-end, customer balances are grouped by how many days they are past the due date. Each group gets the CA\'s percentage. The last band is "and over".</p>' +
      '<div id="st-bands"></div>' + (edit ? '<button type="button" id="st-addband">+ Add a band</button>' : '') +
      '<div class="row" style="margin-top:.5rem"><div class="field" style="flex:0 1 320px"><label for="st-otherpct">Balances not on an invoice (%)</label><input id="st-otherpct" type="number" min="0" max="100" step="0.01" value="' + esc(s.doubtful_debt_other_pct) + '"' + dis + '>' +
      '<div class="hint">Opening balances and journal entries, which have no due date.</div></div>' +
      '<div class="field"><label for="st-ratesnote">Where the rates come from</label><input id="st-ratesnote" value="' + esc(s.doubtful_debt_rates_note || '') + '"' + dis + ' placeholder="e.g. CA letter of 5-Dec-2026"></div></div></section>') +
      // ---- word mark
      '<section class="card"><h2>Word mark</h2><p class="muted">Shown on the login screen, the banner and invoices. Replace it here when the designer sends the final file. A PNG or SVG with a see-through background, under 300 KB, works best.</p>' +
      '<div style="background:var(--ruchi-red);padding:1rem;border-radius:8px;display:inline-block"><img id="st-wm" src="' + esc(s.wordmark_url || 'assets/wordmark.png') + '" alt="Word mark" style="height:70px"></div>' +
      (edit ? '<div class="actions"><label class="btn" for="st-wmfile" style="margin:0">Choose image…</label><input id="st-wmfile" type="file" accept="image/png,image/svg+xml,image/jpeg,image/webp" class="hidden">' +
        '<button type="button" id="st-wmreset">Use the standard word mark</button></div>' : '') + '</section>' +
      (edit ? '<div class="actions" style="position:sticky;bottom:0;background:var(--bg);padding:.5rem 0;z-index:5"><button class="primary" id="st-save">Save settings</button><span id="st-saved" class="muted"></span></div>' : '') +
      // ---- training and go-live
      '<section class="card" id="st-golive"></section>' +
      // ---- demo
      '<section class="card" id="st-demo"></section>' +
      // ---- backups
      '<section class="card" id="st-backup"></section>';

    // partners editor
    // Each partner keeps their number (id), so their capital and current accounts stay linked when names change.
    let partners = (s.partners || []).map((p) => ({ id: p.id, name: p.name, weight: p.weight }));
    let wordmark = s.wordmark_url;
    const drawPartners = () => {
      $('#st-partners', body).innerHTML = partners.map((p, i) =>
        '<div class="row" style="align-items:flex-end"><div class="field" style="flex:3 1 200px"><label>Partner ' + (i + 1) + '</label><input data-pn="' + i + '" value="' + esc(p.name) + '"' + dis + '></div>' +
        '<div class="field" style="flex:1 1 90px"><label>Share</label><input data-pw="' + i + '" type="number" min="1" step="1" value="' + esc(p.weight) + '"' + dis + '></div>' +
        (edit && partners.length > 1 ? '<div class="field" style="flex:0 0 auto"><button type="button" data-pr="' + i + '" aria-label="Remove">✕</button></div>' : '') + '</div>').join('');
      const total = partners.reduce((a, p) => a + (Number(p.weight) || 0), 0);
      $('#st-ratio', body).textContent = 'Ratio ' + partners.map((p) => p.weight).join(' : ') + ' → ' +
        partners.map((p) => (p.name || '?') + ' ' + (total ? (100 * p.weight / total).toFixed(2) : 0) + '%').join(', ');
      $$('[data-pn]', body).forEach((el) => el.addEventListener('input', () => { partners[el.dataset.pn].name = el.value; drawPartnersRatio(); }));
      $$('[data-pw]', body).forEach((el) => el.addEventListener('input', () => { partners[el.dataset.pw].weight = Number(el.value); drawPartnersRatio(); }));
      $$('[data-pr]', body).forEach((el) => el.addEventListener('click', () => { partners.splice(Number(el.dataset.pr), 1); drawPartners(); }));
    };
    const drawPartnersRatio = () => {
      const total = partners.reduce((a, p) => a + (Number(p.weight) || 0), 0);
      $('#st-ratio', body).textContent = 'Ratio ' + partners.map((p) => p.weight).join(' : ') + ' → ' +
        partners.map((p) => (p.name || '?') + ' ' + (total ? (100 * p.weight / total).toFixed(2) : 0) + '%').join(', ');
    };
    drawPartners();

    // age bands for doubtful debts (module 6): days past due "up to", and the rate
    let bands = (s.doubtful_debt_bands || []).map((b) => ({ upto: b.upto, pct: b.pct }));
    const drawBands = () => {
      const el = $('#st-bands', body); if (!el) return;
      let lo = 0;
      el.innerHTML = '<div class="grid-wrap"><table class="ticks lines" style="min-width:0"><thead><tr><th>Days past the due date</th><th>Up to (days)</th><th>Rate %</th><th></th></tr></thead><tbody>' +
        bands.map((b, i) => {
          const last = i === bands.length - 1;
          const label = last ? (lo === 0 ? 'Any' : 'Over ' + (lo - 1)) : (Number(b.upto) === 0 && i === 0 ? 'Not yet due' : lo + ' to ' + b.upto);
          if (!last) lo = Number(b.upto) + 1;
          return '<tr><td>' + esc(label) + '</td><td>' + (last ? 'and over' : '<input data-bu="' + i + '" type="number" min="0" step="1" value="' + esc(b.upto) + '"' + dis + ' style="max-width:110px">') + '</td>' +
            '<td><input data-bp="' + i + '" type="number" min="0" max="100" step="0.01" value="' + esc(b.pct) + '"' + dis + ' style="max-width:110px"></td>' +
            '<td>' + (edit && bands.length > 2 ? '<button type="button" data-br="' + i + '" aria-label="Remove">✕</button>' : '') + '</td></tr>';
        }).join('') + '</tbody></table></div>';
      $$('[data-bu]', el).forEach((x) => x.addEventListener('change', () => { bands[x.dataset.bu].upto = x.value === '' ? null : Number(x.value); drawBands(); }));
      $$('[data-bp]', el).forEach((x) => x.addEventListener('input', () => { bands[x.dataset.bp].pct = x.value; }));
      $$('[data-br]', el).forEach((x) => x.addEventListener('click', () => { bands.splice(Number(x.dataset.br), 1); bands[bands.length - 1].upto = null; drawBands(); }));
    };
    drawBands();
    const addBand = $('#st-addband', body);
    if (addBand) addBand.addEventListener('click', () => {
      const prev = bands.length > 1 ? Number(bands[bands.length - 2].upto) : 0;
      bands.splice(bands.length - 1, 0, { upto: prev + 30, pct: 0 }); drawBands();
    });

    if (edit) {
      $('#st-addp', body).addEventListener('click', () => { partners.push({ name: 'Partner ' + (partners.length + 1), weight: 1 }); drawPartners(); });
      $('#st-wmfile', body).addEventListener('change', (e) => {
        const f = e.target.files[0];
        if (!f) return;
        if (f.size > 300 * 1024) { RB.toast('That image is over 300 KB. Please use a smaller file.', true); return; }
        const r = new FileReader();
        r.onload = () => { wordmark = r.result; $('#st-wm', body).src = wordmark; RB.toast('Press Save settings to keep the new word mark'); };
        r.readAsDataURL(f);
      });
      $('#st-wmreset', body).addEventListener('click', () => { wordmark = ''; $('#st-wm', body).src = 'assets/wordmark.png'; RB.toast('Press Save settings to keep this'); });
      $('#st-save', body).addEventListener('click', async () => {
        const v = (id) => $('#st-' + id, body).value;
        const limit = v('dplimit');
        try {
          if (partners.some((p) => !p.name || !(p.weight > 0))) throw new Error('Each partner needs a name and a share above zero.');
          if (v('gstin').trim() && !v('gstfrom')) throw new Error('Enter the date the GST registration starts (the effective date on the GST certificate).');
          await RB.rpc('rb_save_settings', { p: {
            firm_name: v('firm_name'), legal_form: v('legal'), firm_reg_no: v('firm_reg_no'), llpin: v('llpin'),
            fssai_no: v('fssai_no'), gstin: v('gstin'), state_code: v('state_code'), address: v('address'),
            phone: v('phone'), email: v('email'), partners,
            trader_required_fields: $$('[data-trader]', body).filter((c) => c.checked).map((c) => c.dataset.trader),
            direct_purchase_approval_limit_paise: limit === '' ? null : Math.round(Number(limit) * 100),
            failed_login_limit: Number(v('flimit')), wordmark_url: wordmark || '',
          } });
          if (v('gstin').trim() || s.gst_registered_from) await RB.rpc('rb_set_gst_registration', { p_gstin: v('gstin'), p_from: v('gstfrom') || null });
          if ($('#st-incl', body)) await RB.rpc('rb_save_sales_settings', { p: { sale_prices_include_gst: $('#st-incl', body).checked, invoice_footer: v('footer'),
            statement_link_days: Number(v('linkdays')) || 30 } });
          if ($('#st-exlimit', body)) {
            const ex = v('exlimit');
            const changed = JSON.stringify(bands.map((b) => [b.upto == null ? null : Number(b.upto), Number(b.pct) || 0])) !==
              JSON.stringify((s.doubtful_debt_bands || []).map((b) => [b.upto == null ? null : Number(b.upto), Number(b.pct) || 0])) ||
              Number(v('otherpct') || 0) !== Number(s.doubtful_debt_other_pct || 0);
            await RB.rpc('rb_save_cashbank_settings', { p: Object.assign({ expense_approval_limit_paise: ex === '' ? null : Math.round(Number(ex) * 100),
              doubtful_debt_rates_note: v('ratesnote') },
              changed ? { doubtful_debt_bands: bands.map((b, i) => ({ upto: i === bands.length - 1 ? null : b.upto, pct: Number(b.pct) || 0 })), doubtful_debt_other_pct: Number(v('otherpct') || 0) } : {}) });
          }
                    RB.cache.settings = Object.assign(RB.cache.settings || {}, { wordmark_url: wordmark || null, firm_name: v('firm_name') });
          const img = $('.banner .wordmark'); if (img) img.src = wordmark || 'assets/wordmark.png';
          $('#st-saved', body).textContent = 'Saved ' + RB.fmtDateTime(new Date());
          RB.toast('Settings saved');
        } catch (e) { RB.toast(e.message, true); }
      });
    }

    drawGoLive($('#st-golive', body), s);
    drawDemo($('#st-demo', body));
    drawBackup($('#st-backup', body));
  };

  // ---------- training mode and go-live ----------
  function drawGoLive(el, s) {
    el.innerHTML = '<h2>Training mode and go-live</h2>' + (s.training_mode
      ? '<p>The app is in <b>training mode</b>. Staff can practise freely. At go-live, all DEMO and training entries are deleted, ' +
        'training mode switches off, and real entries start from the opening balances.</p>' +
        (RB.has('power.go_live')
          ? '<div class="row" style="align-items:flex-end"><div class="field"><label for="gl-date">Go-live date</label><input type="date" id="gl-date" value="' + RB.today() + '"></div>' +
            '<div class="field"><button class="danger" id="gl-go">Go live…</button></div></div>'
          : '<p class="muted">Only a Director or the FC can go live.</p>')
      : '<p class="msg ok">Live since <b>' + RB.fmtDate(s.go_live_date) + '</b>.</p>');
    const b = $('#gl-go', el);
    if (b) b.addEventListener('click', async () => {
      const d = $('#gl-date', el).value;
      if (!d) return RB.toast('Choose the go-live date first.', true);
      const word = await RB.confirmTyped('Go live on ' + RB.fmtDate(d) + '?',
        'This <b>permanently deletes</b> every DEMO and training entry and switches training mode off. It cannot be undone. Take a backup first (below).', 'GO LIVE');
      if (!word) return;
      try { await RB.rpc('rb_go_live', { p_go_live: d, p_confirm: word }); RB.toast('The app is live'); RB.cache = {}; location.reload(); }
      catch (e) { RB.toast(e.message, true); }
    });
  }

  // ---------- demo data ----------
  async function drawDemo(el) {
    let n = 0;
    try { n = (await RB.select('app_users', 'id', (q) => q.eq('is_demo', true))).length; } catch (e) { /* no users.view */ }
    el.innerHTML = '<h2>Demo data</h2><p>Every example record is tagged ' + RB.badge('demo', 'DEMO') + '. Right now there ' +
      (n === 1 ? 'is 1 DEMO user' : 'are ' + n + ' DEMO users') + ' (later modules add DEMO purchases, batches and invoices).</p>' +
      (RB.has('power.remove_demo') ? '<button class="danger" id="dm-go">Remove demo data…</button>' : '<p class="muted">Only a Director or the FC can remove demo data.</p>');
    const b = $('#dm-go', el);
    if (b) b.addEventListener('click', async () => {
      const word = await RB.confirmTyped('Remove all demo data?', 'Every record tagged DEMO, in every module, is deleted. Real records are not touched.', 'REMOVE DEMO');
      if (!word) return;
      try {
        const res = await RB.rpc('rb_remove_demo_data', { p_confirm: word });
        const total = Object.values(res || {}).reduce((a, b2) => a + Number(b2), 0);
        RB.toast(total + ' DEMO records removed'); drawDemo(el);
      } catch (e) { RB.toast(e.message, true); }
    });
  }

  // ---------- backups ----------
  async function drawBackup(el) {
    let log = [];
    try { log = await RB.select('backup_log', '*', (q) => q.order('at', { ascending: false }).limit(200)); } catch (e) { /* ignore */ }
    const last = (k) => log.find((r) => r.kind === k);
    const nightly = last('nightly'), ping = last('ping'), manual = last('manual');
    const ageDays = (r) => r ? (Date.now() - new Date(r.at)) / 86400000 : Infinity;
    const line = (title, r, warnDays) => '<tr><th style="text-align:left">' + title + '</th><td style="text-align:left">' +
      (r ? (r.status === 'ok' && ageDays(r) <= warnDays ? RB.badge('active', 'OK') : RB.badge('locked', r.status === 'ok' ? 'Late' : 'Failed')) + ' ' +
        RB.fmtDateTime(r.at) + (r.rows != null ? ' · ' + r.tables + ' tables, ' + r.rows + ' rows' : '') + (r.status !== 'ok' ? ' · ' + esc(r.detail || '') : '')
        : RB.badge('locked', 'Never') + ' <span class="muted">Not set up yet</span>') + '</td></tr>';
    el.innerHTML = '<h2>Backups and keep-awake</h2>' +
      '<p class="muted">A Google Apps Script copies every table to Google Drive each night (last 30 days kept) and pings the database each morning so the free Supabase project never goes to sleep.</p>' +
      '<div class="grid-wrap"><table class="ticks" style="min-width:0"><tbody>' +
      line('Last nightly backup', nightly, 1.5) + line('Last keep-awake ping', ping, 1.5) + line('Last manual backup', manual, 9999) +
      '</tbody></table></div>' +
      (RB.has('power.backup_now') ? '<div class="actions"><button class="primary" id="bk-json">Backup now (file for restore)</button><button id="bk-xls">Backup now (Excel)</button></div>' +
        '<p class="muted">Take one before every module update and at each month-end. The file downloads to this device.</p><div id="bk-msg"></div>' : '');
    const run = async (excel) => {
      const msg = $('#bk-msg', el);
      msg.innerHTML = '<div class="msg info">Taking backup…</div>';
      try {
        const tables = await RB.rpc('rb_backup_tables');
        const out = {}; let rows = 0;
        for (const t of tables) {
          out[t] = [];
          for (let off = 0; ; off += 1000) {
            const page = await RB.rpc('rb_backup_rows', { p_table: t, p_offset: off, p_limit: 1000 });
            out[t].push(...page); rows += page.length;
            msg.innerHTML = '<div class="msg info">Taking backup… ' + esc(t) + ' (' + rows + ' rows so far)</div>';
            if (page.length < 1000) break;
          }
        }
        const stamp = new Date().toISOString().slice(0, 16).replace(/[:T]/g, '-');
        if (excel) {
          const wb = XLSX.utils.book_new();
          tables.forEach((t) => {
            const flat = out[t].map((r) => Object.fromEntries(Object.entries(r).map(([k, v]) => [k, v !== null && typeof v === 'object' ? JSON.stringify(v) : v])));
            XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(flat.length ? flat : [{}]), t.slice(0, 31));
          });
          XLSX.writeFile(wb, 'ruchi-buds-backup-' + stamp + '.xlsx');
        } else {
          const blob = new Blob([JSON.stringify({ app: 'Ruchi Buds', taken_at: new Date().toISOString(), tables: out }, null, 1)], { type: 'application/json' });
          const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = 'ruchi-buds-backup-' + stamp + '.json'; a.click();
          setTimeout(() => URL.revokeObjectURL(a.href), 5000);
        }
        await RB.rpc('rb_log_backup', { p_kind: 'manual', p_status: 'ok', p_tables: tables.length, p_rows: rows, p_detail: excel ? 'Excel download' : 'JSON download' });
        drawBackup(el);
        RB.toast('Backup downloaded: ' + tables.length + ' tables, ' + rows + ' rows');
      } catch (e) {
        msg.innerHTML = '<div class="msg error">' + esc(e.message) + '</div>';
        try { await RB.rpc('rb_log_backup', { p_kind: 'manual', p_status: 'failed', p_tables: null, p_rows: null, p_detail: e.message }); } catch (x) { /* ignore */ }
      }
    };
    const j = $('#bk-json', el), x = $('#bk-xls', el);
    if (j) j.addEventListener('click', () => run(false));
    if (x) x.addEventListener('click', () => run(true));
  }
})();
