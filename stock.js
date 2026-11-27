// =====================================================================
// RUCHI BUDS APP · stock.js · Version 1.2 · 27-Nov-2026
// Module 4 screens "Production" and "Stock". Production: the Production
// window (Preparation, Final production, or Prepare and produce
// together), the batch window, the batch list, the yield report and
// wastage by stage. Stock: raw materials and prepared ingredients (batch
// by batch, with shelf-life warnings), finished goods by pack, stock
// counts and opening stock, write-offs and write-downs, and each item's
// movements. Costs show only for the margin tick (Directors, FC, Accountant).
// =====================================================================
(function () {
  'use strict';
  const RB = window.RB, $ = RB.$, $$ = RB.$$, esc = RB.esc;
  const S = (RB.stock = {});

  const KIND = { raw: 'Raw material', packaging: 'Packaging', wip: 'Prepared (WIP)', finished: 'Finished goods', byproduct: 'By-product' };
  const MOVE = { grn: 'Goods received', bill_adjust: 'Bill difference', debit_note: 'Debit note', purchase_return: 'Returned to supplier',
    reversal: 'Reversal', preparation: 'Preparation', production: 'Production', wastage: 'Write-off', write_down: 'Write-down',
    count: 'Stock count', sale: 'Sale', sales_return: 'Sales return', opening: 'Opening stock', brought_forward: '',
    overhead: 'Labour and overheads (month-end)' };
  const ADJ_STATUS = { awaiting_approval: 'Waiting for approval', posted: 'Posted', refused: 'Refused', reversed: 'Reversed' };
  const COUNT_STATUS = { draft: 'Waiting for approval', posted: 'Posted', cancelled: 'Cancelled', reversed: 'Reversed' };
  const BADGE = { awaiting_approval: 'protected', draft: 'protected', posted: 'active', refused: 'inactive', cancelled: 'inactive', reversed: 'inactive' };

  const costOk = () => RB.has('stock.margin') || RB.has('production.margin') || RB.has('accounts.view');
  const num = (v) => { const s = String(v == null ? '' : v).replace(/[,\s]/g, ''); if (s === '') return null; const n = Number(s); if (!isFinite(n)) throw new Error('"' + v + '" is not a number.'); return n; };
  const trim = (n, d) => Number(n).toLocaleString('en-IN', { maximumFractionDigits: d == null ? 3 : d });
  // 4300 g -> "4.3 kg"; 350 g -> "350 g"; 1500 ml -> "1.5 l"; pieces as they are.
  S.q = (n, unit) => {
    if (n == null || n === '') return '';
    const v = Number(n);
    if ((unit === 'g' || unit === 'ml') && Math.abs(v) >= 1000) return trim(v / 1000) + ' ' + (unit === 'g' ? 'kg' : 'l');
    return trim(v) + ' ' + (unit || '');
  };
  const money = (p) => (p == null ? '' : RB.rupees(p));
  const pct = (v) => (v == null ? '' : trim(v, 1) + '%');
  const fy = () => { const t = RB.today(); return (Number(t.slice(5, 7)) >= 4 ? t.slice(0, 4) : String(Number(t.slice(0, 4)) - 1)) + '-04-01'; };
  const monthStart = () => RB.today().slice(0, 8) + '01';
  const bigUnit = (base) => (base === 'g' ? 'kg' : base === 'ml' ? 'l' : base);
  const unitsFor = (base) => (base === 'g' ? ['kg', 'g'] : base === 'ml' ? ['l', 'ml'] : [base]);
  const status = (s, map) => RB.badge(BADGE[s] || 'invited', map[s] || s);
  const on = (root, sel, fn, ev) => { const b = $(sel, root); if (b) b.addEventListener(ev || 'click', fn); };

  async function lists() {
    const d = await RB.masters.load(['items', 'units', 'departments', 'productPacks', 'packTypes']);
    d.item = Object.fromEntries(d.items.map((i) => [i.id, i]));
    d.packType = Object.fromEntries(d.packTypes.map((p) => [p.id, p]));
    d.packsOf = (itemId) => d.productPacks.filter((p) => p.item_id === Number(itemId) && p.is_active)
      .map((p) => Object.assign({}, p, { name: (d.packType[p.pack_type_id] || {}).name || 'Pack' }))
      .sort((a, b) => Number(a.net_qty) - Number(b.net_qty));
    d.depts = d.departments.filter((x) => x.is_active && !x.merged_into).map((x) => [x.id, x.code + ' ' + x.name]);
    const k = d.departments.find((x) => x.code === 'CC001' && x.is_active);
    d.defaultDept = k ? k.id : (d.departments[0] || {}).id;
    return d;
  }

  function tabs(body, key, list) {
    body.innerHTML = '<div class="tabs">' + list.map(([k, t]) => '<button data-tab="' + k + '">' + t + '</button>').join('') + '</div><div id="tab-body"></div>';
    const show = async (k) => {
      S[key] = k;
      $$('.tabs button', body).forEach((b) => b.classList.toggle('on', b.dataset.tab === k));
      const tb = $('#tab-body', body); tb.innerHTML = '<p class="muted">Loading…</p>';
      try { await list.find((x) => x[0] === k)[2](tb); } catch (e) { tb.innerHTML = '<div class="msg error">' + esc(e.message) + '</div>'; }
    };
    $$('.tabs button', body).forEach((b) => b.addEventListener('click', () => show(b.dataset.tab)));
    show(S[key] && list.some((x) => x[0] === S[key]) ? S[key] : list[0][0]);
  }

  function dateRange(tb, id, from, load) {
    tb.insertAdjacentHTML('afterbegin', '<div class="row" style="align-items:flex-end">' +
      '<div class="field" style="flex:0 1 180px"><label for="' + id + '-from">From</label><input type="date" id="' + id + '-from" value="' + from + '"></div>' +
      '<div class="field" style="flex:0 1 180px"><label for="' + id + '-to">To</label><input type="date" id="' + id + '-to" value="' + RB.today() + '"></div>' +
      '<div class="field" style="flex:0 1 auto"><button id="' + id + '-go">Show</button> <button id="' + id + '-xls">Download to Excel</button></div></div>');
    const get = () => [$('#' + id + '-from', tb).value, $('#' + id + '-to', tb).value];
    $('#' + id + '-go', tb).addEventListener('click', () => load(...get()).catch((e) => RB.toast(e.message, true)));
    return get;
  }

  // ===================================================================
  // Production screen
  // ===================================================================
  RB.screens.production = async (body, arg) => {
    if (arg === 'new') return productionWindow(body);
    if (arg && /^\d+$/.test(arg)) return batchWindow(body, Number(arg));
    const tools = $('#page-tools');
    if (tools) tools.innerHTML = RB.has('production.add')
      ? '<a class="btn primary" href="#/production/new" id="pr-new">+ New batch</a>' : '';
    tabs(body, 'ptab', [['batches', 'Batches', batchesTab], ['yield', 'Yield report', yieldTab], ['wastage', 'Wastage by stage', wastageTab]]);
  };

  async function batchesTab(tb) {
    tb.innerHTML = '<p class="muted">Preparation batches (PRP) turn raw materials into prepared ingredients; production batches (PRD) make finished goods. Tap a batch to open it.</p><div id="bl-grid"></div>';
    let grid;
    const get = dateRange(tb, 'bl', fy(), async (from, to) => {
      const rows = await RB.rpc('rb_batch_list', { p_from: from, p_to: to });
      const cols = [
        { title: 'Batch', field: 'batch_no', width: 190, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
        { title: 'Date', field: 'batch_date', width: 115, formatter: (c) => RB.fmtDate(c.getValue()) },
        { title: 'Type', field: 'kind', width: 120, formatter: (c) => (c.getValue() === 'preparation' ? 'Preparation' : 'Production') },
        { title: 'Made', field: 'output_item', minWidth: 190 },
        { title: 'Quantity', field: 'output_qty_base', hozAlign: 'right', headerFilter: false, formatter: (c) => S.q(c.getValue(), c.getRow().getData().base_unit) },
        { title: 'Packs', field: 'output_summary', minWidth: 160 },
        { title: 'From', field: 'input_summary', minWidth: 220 },
        { title: 'Yield', field: 'yield_pct', hozAlign: 'right', headerFilter: false, formatter: (c) => pct(c.getValue()) },
        { title: 'Linked', field: 'linked_batch_no', width: 170 },
        { title: 'Status', field: 'status', width: 100, formatter: (c) => status(c.getValue(), { posted: 'Posted', reversed: 'Reversed' }) },
      ];
      if (costOk()) cols.splice(5, 0, { title: 'Cost', field: 'cost_paise', hozAlign: 'right', headerFilter: false, formatter: (c) => money(c.getValue()) });
      grid = RB.grid($('#bl-grid', tb), cols, rows);
      grid.on('rowClick', (e, row) => { location.hash = '#/production/' + row.getData().id; });
    });
    $('#bl-xls', tb).addEventListener('click', () => grid && RB.downloadExcel(grid, 'Production batches'));
    await $('#bl-go', tb).click();

  }

  async function yieldTab(tb) {
    tb.innerHTML = '<p class="muted">Raw material → prepared ingredient → finished goods, batch by batch, with the wastage at each stage as a % of what went in. ' +
      '"Other change" is weight not explained by wastage, by-products or what came out (for example water taken up in boiling).</p><div id="yl-grid"></div>';
    let grid;
    dateRange(tb, 'yl', monthStart(), async (from, to) => {
      const rows = await RB.rpc('rb_yield_report', { p_from: from, p_to: to });
      const data = rows.map((r) => Object.assign({}, r, {
        stages_t: (r.stages || []).map((s) => s.stage + ' ' + S.q(s.qty, r.base_unit) + ' (' + pct(s.pct) + ')').join(' · '),
        finished_t: (r.finished || []).map((f) => f.batch_no + ': ' + S.q(f.used, r.base_unit) + ' into ' + f.product + ' (made ' + S.q(f.made, 'g') + ')').join(' · ') }));
      grid = RB.grid($('#yl-grid', tb), [
        { title: 'Batch', field: 'batch_no', width: 190, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) + (c.getRow().getData().status === 'reversed' ? ' ' + RB.badge('inactive', 'Reversed') : '') },
        { title: 'Date', field: 'batch_date', width: 115, formatter: (c) => RB.fmtDate(c.getValue()) },
        { title: 'Raw material', field: 'raw_item', minWidth: 160 },
        { title: 'In', field: 'raw_qty', hozAlign: 'right', headerFilter: false, formatter: (c) => S.q(c.getValue(), c.getRow().getData().base_unit) },
        { title: 'Wastage by stage', field: 'stages_t', minWidth: 300 },
        { title: 'Wastage', field: 'wastage_pct', hozAlign: 'right', headerFilter: false, formatter: (c) => pct(c.getValue()) },
        { title: 'By-products', field: 'byproduct_qty', hozAlign: 'right', headerFilter: false, formatter: (c) => (Number(c.getValue()) ? S.q(c.getValue(), c.getRow().getData().base_unit) : '') },
        { title: 'Unusual loss', field: 'abnormal_qty', hozAlign: 'right', headerFilter: false, formatter: (c) => (Number(c.getValue()) ? S.q(c.getValue(), c.getRow().getData().base_unit) : '') },
        { title: 'Prepared', field: 'prepared_item', minWidth: 170 },
        { title: 'Out', field: 'prepared_qty', hozAlign: 'right', headerFilter: false, formatter: (c) => S.q(c.getValue(), c.getRow().getData().base_unit) },
        { title: 'Yield', field: 'yield_pct', hozAlign: 'right', headerFilter: false, formatter: (c) => '<b>' + pct(c.getValue()) + '</b>' },
        { title: 'Other change', field: 'other_change_qty', hozAlign: 'right', headerFilter: false, formatter: (c) => (Number(c.getValue()) ? S.q(c.getValue(), c.getRow().getData().base_unit) : '') },
        { title: 'Into finished goods', field: 'finished_t', minWidth: 300 },
        { title: 'Left', field: 'left_qty', hozAlign: 'right', headerFilter: false, formatter: (c) => (Number(c.getValue()) ? S.q(c.getValue(), c.getRow().getData().base_unit) : '') },
      ], data);
      grid.on('rowClick', (e, row) => { location.hash = '#/production/' + row.getData().batch_id; });
    });
    $('#yl-xls', tb).addEventListener('click', () => grid && RB.downloadExcel(grid, 'Yield report'));
    await $('#yl-go', tb).click();
  }

  async function wastageTab(tb) {
    tb.innerHTML = '<p class="muted">Wastage at each preparation stage, frying shrinkage, packing wastage and unusual losses, as a % of what went into that step.</p><div id="ws-grid"></div>';
    let grid;
    dateRange(tb, 'ws', monthStart(), async (from, to) => {
      const rows = await RB.rpc('rb_wastage_report', { p_from: from, p_to: to });
      grid = RB.grid($('#ws-grid', tb), [
        { title: 'Item', field: 'item', minWidth: 200 },
        { title: 'Stage', field: 'stage', minWidth: 160 },
        { title: 'Batches', field: 'batches', hozAlign: 'right', headerFilter: false },
        { title: 'Went in', field: 'input_qty', hozAlign: 'right', headerFilter: false, formatter: (c) => S.q(c.getValue(), c.getRow().getData().base_unit) },
        { title: 'Wastage', field: 'wastage_qty', hozAlign: 'right', headerFilter: false, formatter: (c) => S.q(c.getValue(), c.getRow().getData().base_unit) },
        { title: 'Wastage %', field: 'wastage_pct', hozAlign: 'right', headerFilter: false, formatter: (c) => '<b>' + pct(c.getValue()) + '</b>' },
      ], rows);
    });
    $('#ws-xls', tb).addEventListener('click', () => grid && RB.downloadExcel(grid, 'Wastage by stage'));
    await $('#ws-go', tb).click();
  }

  // ---------- the Production window ----------
  async function productionWindow(body) {
    const back = $('.page-head .back'); if (back) { back.href = '#/production'; back.textContent = '‹ Production'; }
    const h1 = $('.page-head h1'); if (h1) h1.textContent = 'Production window';
    if (!RB.has('production.add')) { body.innerHTML = '<div class="msg error">You do not have the right to enter production batches.</div>'; return; }
    body.innerHTML = '<p class="muted">Loading…</p>';
    const [d, lots] = await Promise.all([lists(), RB.rpc('rb_wip_lots', { p_as_of: RB.today() })]);
    const raws = d.items.filter((i) => i.kind === 'raw' && i.is_active);
    const wips = d.items.filter((i) => i.kind === 'wip' && i.is_active);
    const fgs = d.items.filter((i) => i.kind === 'finished' && i.is_active);
    const bps = d.items.filter((i) => i.kind === 'byproduct' && i.is_active);
    const ins = d.items.filter((i) => ['raw', 'wip', 'packaging'].includes(i.kind) && i.is_active);
    const st = { mode: S.mode || 'production', prep: { stages: [], bps: [], unit: 'kg' }, prod: { inputs: [{}], packs: {}, unit: 'g' } };

    body.innerHTML =
      '<div class="card"><div class="switch" role="tablist">' +
      [['preparation', 'Preparation'], ['production', 'Final production'], ['combined', 'Prepare and produce together']].map(([k, t]) =>
        '<button type="button" data-mode="' + k + '">' + t + '</button>').join('') + '</div>' +
      '<p class="muted" id="pw-explain"></p><div class="m-msg"></div>' +
      '<div class="row">' + RB.field('pw-date', 'Date', '<input type="date" id="pw-date" value="' + RB.today() + '">', null, true) +
      RB.field('pw-dept', 'Department', RB.sel('pw-dept', d.depts, d.defaultDept)) + '</div></div>' +
      '<div class="card" id="pw-prep"></div><div class="card" id="pw-prod"></div>' +
      '<div class="card">' + RB.field('pw-note', 'Note', RB.inp('pw-note', '')) +
      '<div class="actions"><button class="primary" id="pw-save">Save batch</button><a class="btn" href="#/production">Cancel</a></div></div>';
    const m = { el: body };

    // ----- preparation part -----
    const drawPrep = () => {
      const p = st.prep, raw = d.item[p.raw];
      const units = raw ? unitsFor(raw.base_unit) : ['kg', 'g'];
      if (!units.includes(p.unit)) p.unit = units[0];
      const u = p.unit;
      $('#pw-prep', body).innerHTML = '<h2>Preparation</h2>' +
        '<div class="row">' + RB.field('pp-raw', 'Raw material in', RB.sel('pp-raw', [['', 'Choose…']].concat(raws.map((i) => [i.id, i.name])), p.raw), null, true) +
        RB.field('pp-unit', 'Weigh in', RB.sel('pp-unit', units.map((x) => [x, x]), u)) +
        RB.field('pp-in', 'Quantity in (' + u + ')', '<input id="pp-in" inputmode="decimal" value="' + esc(p.inq || '') + '">', null, true) + '</div>' +
        '<h3>Wastage at each stage (' + u + ')</h3>' +
        (p.stages.length ? '' : '<p class="muted">' + (raw ? 'This raw material has no stages set up (Masters → Items). Add them here if needed.' : 'Choose the raw material to see its stages.') + '</p>') +
        '<div class="grid-wrap"' + (p.stages.length ? '' : ' hidden') + '><table class="ticks lines"><thead><tr><th>Stage</th><th>Wastage (' + u + ')</th><th></th></tr></thead><tbody>' +
        p.stages.map((s, i) => '<tr><td><input data-st="' + i + '" data-f="stage" value="' + esc(s.stage) + '"></td>' +
          '<td><input data-st="' + i + '" data-f="w" inputmode="decimal" value="' + esc(s.w == null ? '' : s.w) + '"></td>' +
          '<td><button type="button" data-delst="' + i + '" aria-label="Remove stage">✕</button></td></tr>').join('') + '</tbody></table></div>' +
        '<div class="actions"><button type="button" id="pp-addst">+ Add a stage</button></div>' +
        '<h3>By-products (skin, bones, trimmings)</h3>' +
        (p.bps.length ? '<div class="grid-wrap"><table class="ticks lines"><thead><tr><th>By-product</th><th>At stage</th><th>Quantity (' + u + ')</th><th>Goes to</th><th></th></tr></thead><tbody>' +
          p.bps.map((b, i) => '<tr><td>' + RB.sel('pb-item-' + i, [['', 'Choose…']].concat(bps.map((x) => [x.id, x.name])), b.item, ' data-bp="' + i + '" data-f="item"') + '</td>' +
            '<td>' + RB.sel('pb-stage-' + i, [['', '–']].concat(p.stages.map((s) => [s.stage, s.stage])), b.stage, ' data-bp="' + i + '" data-f="stage"') + '</td>' +
            '<td><input data-bp="' + i + '" data-f="qty" inputmode="decimal" value="' + esc(b.qty || '') + '"></td>' +
            '<td>' + (d.item[b.item] ? (d.item[b.item].byproduct_use === 'sellable' ? 'Stock (sellable)' : 'Wastage (discarded)') : '') + '</td>' +
            '<td><button type="button" data-delbp="' + i + '" aria-label="Remove">✕</button></td></tr>').join('') + '</tbody></table></div>' : '') +
        '<div class="actions"><button type="button" id="pp-addbp">+ Add a by-product</button></div>' +
        '<div class="row">' + RB.field('pp-out-item', 'Prepared ingredient out', RB.sel('pp-out-item', [['', 'Choose…']].concat(wips.map((i) => [i.id, i.name + (i.shelf_life_days ? ' (keeps ' + i.shelf_life_days + ' days)' : '')])), p.out), null, true) +
        RB.field('pp-out', 'Quantity out (' + u + ')', '<input id="pp-out" inputmode="decimal" value="' + esc(p.outq || '') + '">', null, true) + '</div>' +
        '<details' + (p.abn ? ' open' : '') + '><summary>Unusual loss (not normal wastage)</summary><div class="row">' +
        RB.field('pp-abn', 'Quantity lost (' + u + ')', '<input id="pp-abn" inputmode="decimal" value="' + esc(p.abn || '') + '">', 'Its cost is charged as a loss instead of going into the prepared ingredient.') +
        RB.field('pp-abnwhy', 'What happened', RB.inp('pp-abnwhy', p.abnwhy || '', ' placeholder="e.g. tray dropped"')) + '</div></details>' +
        '<p id="pp-check" class="muted"></p>';
      on(body, '#pp-raw', (e) => {
        const it = d.item[e.target.value]; p.raw = it ? it.id : null;
        p.stages = it ? (it.stages || []).map((s) => ({ stage: s })) : [];
        p.bps = []; p.out = it && it.prepared_item_id ? it.prepared_item_id : p.out;
        drawPrep();
      }, 'change');
      on(body, '#pp-unit', (e) => { p.unit = e.target.value; drawPrep(); }, 'change');
      on(body, '#pp-in', (e) => { p.inq = e.target.value; checkPrep(); }, 'input');
      on(body, '#pp-out', (e) => { p.outq = e.target.value; checkPrep(); if (st.mode === 'combined') drawProd(); }, 'input');
      on(body, '#pp-out-item', (e) => { p.out = Number(e.target.value) || null; }, 'change');
      on(body, '#pp-abn', (e) => { p.abn = e.target.value; checkPrep(); }, 'input');
      on(body, '#pp-abnwhy', (e) => { p.abnwhy = e.target.value; }, 'input');
      on(body, '#pp-addst', () => { p.stages.push({ stage: '' }); drawPrep(); });
      on(body, '#pp-addbp', () => { p.bps.push({}); drawPrep(); });
      $$('[data-st]', body).forEach((el) => el.addEventListener('input', () => { p.stages[el.dataset.st][el.dataset.f] = el.value; checkPrep(); }));
      $$('[data-delst]', body).forEach((b) => b.addEventListener('click', () => { p.stages.splice(Number(b.dataset.delst), 1); drawPrep(); }));
      $$('[data-bp]', body).forEach((el) => el.addEventListener(el.tagName === 'SELECT' ? 'change' : 'input', () => {
        p.bps[el.dataset.bp][el.dataset.f] = el.value; if (el.dataset.f === 'item') drawPrep(); else checkPrep();
      }));
      $$('[data-delbp]', body).forEach((b) => b.addEventListener('click', () => { p.bps.splice(Number(b.dataset.delbp), 1); drawPrep(); }));
      checkPrep();
    };
    const checkPrep = () => {
      const p = st.prep, el = $('#pp-check', body); if (!el) return;
      let inq, w = 0, b = 0, out, abn;
      try {
        inq = num(p.inq); out = num(p.outq) || 0; abn = num(p.abn) || 0;
        p.stages.forEach((s) => { w += num(s.w) || 0; }); p.bps.forEach((x) => { b += num(x.qty) || 0; });
      } catch (e) { el.textContent = e.message; return; }
      if (!inq) { el.textContent = ''; return; }
      const other = inq - w - b - abn - out;
      el.innerHTML = 'In ' + trim(inq) + ' ' + p.unit + ' = wastage ' + trim(w) + ' + by-products ' + trim(b) + (abn ? ' + unusual loss ' + trim(abn) : '') +
        ' + out ' + trim(out) + (Math.abs(other) > 0.0005 ? ' <b>' + (other > 0 ? '+ other loss ' : '− other gain ') + trim(Math.abs(other)) + '</b>' : '') +
        ' · yield <b>' + pct(100 * out / inq) + '</b>';
    };

    // ----- production part -----
    const lotLabel = (l) => (l.batch_no ? l.batch_no + ', ' + RB.fmtDate(l.prep_date) : 'Without a batch') + ', ' + S.q(l.qty_base, l.base_unit) + ' left' + (l.expired ? ' · PAST SHELF LIFE' : '');
    const drawProd = () => {
      const p = st.prod, fg = d.item[p.fg], packs = fg ? d.packsOf(fg.id) : [];
      const prepIt = d.item[st.prep.out];
      $('#pw-prod', body).innerHTML = '<h2>Final production</h2>' +
        '<div class="row">' + RB.field('pd-fg', 'Finished product', RB.sel('pd-fg', [['', 'Choose…']].concat(fgs.map((i) => [i.id, i.name])), p.fg), null, true) + '</div>' +
        '<h3>What went in</h3>' +
        (st.mode === 'combined' ? '<div class="row">' + RB.field('pd-used', 'Prepared above, used here (' + st.prep.unit + ')',
          '<input id="pd-used" inputmode="decimal" placeholder="all of it" value="' + esc(p.used || '') + '">',
          (prepIt ? esc(prepIt.name) : 'The prepared ingredient') + '. Leave blank to use all of it; what is left stays in stock.') + '</div>' : '') +
        '<div class="grid-wrap"><table class="ticks lines"><thead><tr><th>Item</th><th>From batch (prepared only)</th><th>Quantity</th><th>Unit</th><th></th></tr></thead><tbody>' +
        p.inputs.map((l, i) => {
          const it = d.item[l.item], my = it && it.kind === 'wip' ? lots.filter((x) => x.item_id === it.id) : [];
          const lot = my.find((x) => String(x.lot_batch_id) === String(l.lot));
          return '<tr><td style="min-width:200px">' + RB.sel('pi-item-' + i, [['', 'Choose…']].concat(ins.map((x) => [x.id, x.name + (x.kind === 'wip' ? ' (prepared)' : '')])), l.item, ' data-in="' + i + '" data-f="item"') + '</td>' +
            '<td style="min-width:220px">' + (it && it.kind === 'wip'
              ? RB.sel('pi-lot-' + i, [['', 'Oldest first']].concat(my.map((x) => [x.lot_batch_id == null ? '' : x.lot_batch_id, lotLabel(x)])), l.lot, ' data-in="' + i + '" data-f="lot"') +
                (lot && lot.expired ? '<div class="diff">Past its ' + lot.shelf_life_days + '-day shelf life (prepared ' + RB.fmtDate(lot.prep_date) + ')</div>' : '') +
                (!l.lot && my.some((x) => x.expired) ? '<div class="diff">Some of this is past its shelf life</div>' : '')
              : '<span class="muted">–</span>') + '</td>' +
            '<td style="min-width:100px"><input data-in="' + i + '" data-f="qty" inputmode="decimal" value="' + esc(l.qty || '') + '"></td>' +
            '<td style="min-width:80px">' + RB.sel('pi-unit-' + i, (it ? unitsFor(it.base_unit) : ['kg', 'g']).map((x) => [x, x]), l.unit, ' data-in="' + i + '" data-f="unit"') + '</td>' +
            '<td><button type="button" data-delin="' + i + '" aria-label="Remove">✕</button></td></tr>';
        }).join('') + '</tbody></table></div>' +
        '<div class="actions"><button type="button" id="pd-addin">+ Add a line</button>' + (fg ? '<button type="button" id="pd-last">Copy what went into the last batch</button>' : '') + '</div>' +
        '<h3>What came out</h3>' +
        (fg ? (packs.length ? '<div class="grid-wrap"><table class="ticks lines"><thead><tr><th>Pack</th><th>Holds</th><th>Packs made</th><th>Quantity</th></tr></thead><tbody>' +
          packs.map((pp) => '<tr><td style="text-align:left">' + esc(pp.name) + '</td><td>' + S.q(pp.net_qty, fg.base_unit) + '</td>' +
            '<td style="min-width:100px"><input data-pack="' + pp.id + '" inputmode="numeric" value="' + esc(p.packs[pp.id] || '') + '"></td>' +
            '<td data-packq="' + pp.id + '"></td></tr>').join('') + '</tbody></table></div>'
          : '<p class="muted">No packs are set up for this product yet (Masters → Packs and prices).</p>') +
          (fg.sells_by !== 'pack' ? '<div class="row">' + RB.field('pd-loose', 'Loose, not packed (' + bigUnit(fg.base_unit) + ')', '<input id="pd-loose" inputmode="decimal" value="' + esc(p.loose || '') + '">', 'For sale by weight.') + '</div>' : '') +
          '<p class="muted">Each pack uses one empty bottle or pouch from stock.</p>' : '<p class="muted">Choose the finished product first.</p>') +
        '<div class="row">' + RB.field('pd-unit', 'Wastage in', RB.sel('pd-unit', [['g', 'g'], ['kg', 'kg']], p.unit)) +
        RB.field('pd-shr', 'Frying shrinkage', '<input id="pd-shr" inputmode="decimal" value="' + esc(p.shr || '') + '">') +
        RB.field('pd-pkw', 'Packing wastage', '<input id="pd-pkw" inputmode="decimal" value="' + esc(p.pkw || '') + '">') + '</div>' +
        '<details' + (p.abn ? ' open' : '') + '><summary>Unusual loss (not normal wastage)</summary><div class="row">' +
        RB.field('pd-abn', 'Quantity lost', '<input id="pd-abn" inputmode="decimal" value="' + esc(p.abn || '') + '">', 'Its cost is charged as a loss instead of going into the finished goods.') +
        RB.field('pd-abnwhy', 'What happened', RB.inp('pd-abnwhy', p.abnwhy || '', ' placeholder="e.g. batch burnt"')) + '</div></details>' +
        '<p id="pd-check" class="muted"></p>';
      on(body, '#pd-fg', (e) => { p.fg = Number(e.target.value) || null; p.packs = {}; drawProd(); }, 'change');
      on(body, '#pd-used', (e) => { p.used = e.target.value; }, 'input');
      on(body, '#pd-addin', () => { p.inputs.push({}); drawProd(); });
      on(body, '#pd-last', () => copyLast(fg).catch((e) => RB.toast(e.message, true)));
      on(body, '#pd-loose', (e) => { p.loose = e.target.value; checkProd(); }, 'input');
      ['unit', 'shr', 'pkw', 'abn', 'abnwhy'].forEach((k) => on(body, '#pd-' + k, (e) => { p[k] = e.target.value; checkProd(); }, k === 'unit' ? 'change' : 'input'));
      $$('[data-in]', body).forEach((el) => el.addEventListener(el.tagName === 'SELECT' ? 'change' : 'input', () => {
        const l = p.inputs[el.dataset.in]; l[el.dataset.f] = el.value;
        if (el.dataset.f === 'item') { const it = d.item[el.value]; l.unit = it ? unitsFor(it.base_unit)[0] : null; l.lot = ''; drawProd(); }
        else if (el.dataset.f === 'lot') drawProd();
      }));
      $$('[data-delin]', body).forEach((b) => b.addEventListener('click', () => { p.inputs.splice(Number(b.dataset.delin), 1); if (!p.inputs.length) p.inputs.push({}); drawProd(); }));
      $$('[data-pack]', body).forEach((el) => el.addEventListener('input', () => { p.packs[el.dataset.pack] = el.value; checkProd(); }));
      checkProd();
    };
    const checkProd = () => {
      const p = st.prod, fg = d.item[p.fg], el = $('#pd-check', body); if (!el || !fg) return;
      let total = 0;
      d.packsOf(fg.id).forEach((pp) => {
        const n = Number(p.packs[pp.id]) || 0; total += n * Number(pp.net_qty);
        const c = $('[data-packq="' + pp.id + '"]', body); if (c) c.textContent = n ? S.q(n * Number(pp.net_qty), fg.base_unit) : '';
      });
      const loose = (Number(p.loose) || 0) * (fg.base_unit === 'g' || fg.base_unit === 'ml' ? 1000 : 1);
      total += loose;
      el.innerHTML = total ? 'Made <b>' + S.q(total, fg.base_unit) + '</b> of ' + esc(fg.name) : '';
    };
    // Copy the inputs of the last batch of the same product (items only, not quantities).
    const copyLast = async (fg) => {
      const rows = await RB.rpc('rb_batch_list', { p_from: '2000-01-01', p_to: RB.today() });
      const last = rows.find((r) => r.kind === 'production' && r.output_item === fg.name && r.status === 'posted');
      if (!last) { RB.toast('No earlier batch of ' + fg.name); return; }
      const x = await RB.rpc('rb_batch_detail', { p_id: last.id });
      const seen = new Set();
      st.prod.inputs = x.lines.filter((l) => l.role === 'input' && !(st.mode === 'combined' && l.item_id === st.prep.out) && !seen.has(l.item_id) && seen.add(l.item_id))
        .map((l) => ({ item: l.item_id, unit: unitsFor(l.base_unit)[0] }));
      if (!st.prod.inputs.length) st.prod.inputs = [{}];
      drawProd(); RB.toast('Copied the items from ' + last.batch_no + '. Enter today\'s quantities.');
    };

    const setMode = (k) => {
      st.mode = S.mode = k;
      $$('[data-mode]', body).forEach((b) => b.classList.toggle('on', b.dataset.mode === k));
      $('#pw-explain', body).textContent = {
        preparation: 'Raw material in, prepared ingredient out, with the wastage at each stage. Numbered PRP/YYMM/00001. The prepared ingredient waits in stock (work in progress) for a later production batch.',
        production: 'Prepared ingredients and other raw materials in, finished goods out in bottles and pouches, with frying shrinkage and packing wastage. Numbered PRD/YYMM/00001.',
        combined: 'For same-day items such as fish and chicken: one entry makes the preparation batch (PRP) and the production batch (PRD) that uses it, linked to each other.',
      }[k];
      $('#pw-prep', body).hidden = k === 'production';
      $('#pw-prod', body).hidden = k === 'preparation';
      if (k !== 'production') drawPrep();
      if (k !== 'preparation') drawProd();
    };
    $$('[data-mode]', body).forEach((b) => b.addEventListener('click', () => setMode(b.dataset.mode)));
    setMode(st.mode);

    const prepJson = () => {
      const p = st.prep, u = p.unit;
      return { batch_date: $('#pw-date', body).value, department_id: Number($('#pw-dept', body).value) || null, raw_item_id: p.raw || null,
        raw_qty: num(p.inq), raw_unit: u, output_item_id: p.out || null, output_qty: num(p.outq), output_unit: u, waste_unit: u,
        stages: p.stages.filter((s) => s.stage).map((s) => ({ stage: s.stage, wastage: num(s.w) })),
        byproducts: p.bps.filter((b) => b.item).map((b) => ({ item_id: Number(b.item), stage: b.stage || null, qty: num(b.qty), unit: u })),
        abnormal_qty: num(p.abn), abnormal_reason: p.abnwhy || null, note: $('#pw-note', body).value };
    };
    const prodJson = () => {
      const p = st.prod, fg = d.item[p.fg];
      const outputs = fg ? d.packsOf(fg.id).filter((pp) => Number(p.packs[pp.id])).map((pp) => ({ pack_id: pp.id, packs: num(p.packs[pp.id]) })) : [];
      if (fg && num(p.loose)) outputs.push({ pack_id: null, qty: num(p.loose), unit: bigUnit(fg.base_unit) });
      return { batch_date: $('#pw-date', body).value, department_id: Number($('#pw-dept', body).value) || null, output_item_id: p.fg || null,
        inputs: p.inputs.filter((l) => l.item).map((l) => ({ item_id: Number(l.item), lot_batch_id: l.lot ? Number(l.lot) : null, qty: num(l.qty), unit: l.unit || null })),
        outputs, waste_unit: p.unit, shrinkage_qty: num(p.shr), packing_waste_qty: num(p.pkw), abnormal_qty: num(p.abn), abnormal_reason: p.abnwhy || null,
        note: $('#pw-note', body).value };
    };
    $('#pw-save', body).addEventListener('click', async () => {
      const btn = $('#pw-save', body);
      try {
        // Warn before using prepared stock past its shelf life.
        if (st.mode !== 'preparation') {
          const old = st.prod.inputs.filter((l) => d.item[l.item] && d.item[l.item].kind === 'wip').some((l) =>
            lots.some((x) => x.item_id === Number(l.item) && x.expired && (!l.lot || String(x.lot_batch_id) === String(l.lot))));
          if (old && !(await RB.confirm('Use prepared stock past its shelf life?', 'Some of the prepared ingredients picked are older than their shelf life (shown in red). Use them anyway?'))) return;
        }
        btn.disabled = true;
        let id;
        if (st.mode === 'preparation') id = await RB.rpc('rb_save_preparation', { p: prepJson() });
        else if (st.mode === 'production') id = await RB.rpc('rb_save_production', { p: prodJson() });
        else {
          const pr = prodJson(); delete pr.batch_date;
          const out = await RB.rpc('rb_save_prep_and_production', { p: { prep: prepJson(), production: pr, used_qty: num(st.prod.used), used_unit: st.prep.unit } });
          id = out.production_id;
        }
        RB.toast('Batch saved'); location.hash = '#/production/' + id;
      } catch (e) { btn.disabled = false; RB.modalMsg(m, e.message); window.scrollTo(0, 0); }
    });
  }

  // ---------- the batch window ----------
  async function batchWindow(body, id) {
    const back = $('.page-head .back'); if (back) { back.href = '#/production'; back.textContent = '‹ Production'; }
    body.innerHTML = '<p class="muted">Loading…</p>';
    const x = await RB.rpc('rb_batch_detail', { p_id: id });
    const b = x.batch, can = x.can, cost = can.see_cost, u = b.base_unit;
    const h1 = $('.page-head h1'); if (h1) h1.innerHTML = esc(b.batch_no) + RB.demoBadge(b);
    const prep = b.kind === 'preparation';
    const ins = x.lines.filter((l) => l.role === 'input'), outs = x.lines.filter((l) => l.role === 'output');
    const bps = x.lines.filter((l) => l.role === 'byproduct'), pk = x.lines.filter((l) => l.role === 'packaging');
    const inQty = prep ? Number(b.input_qty_base) : 0;
    const expired = prep && b.shelf_life_days && Number(b.left_qty_base) > 0 &&
      new Date(b.batch_date + 'T00:00:00').getTime() + b.shelf_life_days * 864e5 < new Date(RB.today() + 'T00:00:00').getTime();
    const table = (head, rows) => '<div class="grid-wrap"><table class="ticks"><thead><tr>' + head.map((h) => '<th>' + h + '</th>').join('') + '</tr></thead><tbody>' + rows.join('') + '</tbody></table></div>';
    const td = (v, right) => '<td' + (right ? ' style="text-align:right"' : ' style="text-align:left"') + '>' + v + '</td>';

    const head = '<div class="card"><div class="row facts">' +
      '<div><small>Type</small>' + (prep ? 'Preparation' : 'Final production') + '</div>' +
      '<div><small>Date</small>' + RB.fmtDate(b.batch_date) + '</div>' +
      '<div><small>Made</small>' + esc(b.output_item) + '<br><b>' + S.q(b.output_qty_base, u) + '</b></div>' +
      '<div><small>Status</small>' + status(b.status, { posted: 'Posted', reversed: 'Reversed' }) + '</div>' +
      (b.linked_batch_no ? '<div><small>' + (b.linked_kind === 'preparation' ? 'Prepared in' : 'Produced in') + '</small><a href="#/production/' + b.linked_batch_id + '">' + esc(b.linked_batch_no) + '</a><br><span class="muted">prepared and produced together</span></div>' : '') +
      '<div><small>Department</small>' + esc(b.department || '') + '</div>' +
      '<div><small>Entered by</small>' + esc(b.entered_by_name || '') + '</div>' +
      '<div><small>Journal</small>' + esc(b.journal_no || '–') + (b.reversal_journal_no ? '<br><span class="muted">reversed by ' + esc(b.reversal_journal_no) + '</span>' : '') + '</div>' +
      '</div>' + (b.note ? '<p class="muted">Note: ' + esc(b.note) + '</p>' : '') +
      (b.status === 'reversed' ? '<div class="msg error">Reversed: ' + esc(b.reverse_reason || '') + '</div>' : '') +
      (prep ? '<div class="row totals"><div><small>In</small>' + S.q(inQty, ins[0] ? ins[0].base_unit : u) + '</div>' +
        '<div><small>Wastage</small>' + S.q(b.wastage_qty_base, ins[0] ? ins[0].base_unit : u) + ' (' + pct(inQty ? 100 * b.wastage_qty_base / inQty : null) + ')</div>' +
        (Number(b.byproduct_qty_base) ? '<div><small>By-products</small>' + S.q(b.byproduct_qty_base, u) + '</div>' : '') +
        (Number(b.abnormal_qty_base) ? '<div><small>Unusual loss</small>' + S.q(b.abnormal_qty_base, u) + '</div>' : '') +
        '<div><small>Yield</small><b>' + pct(inQty ? 100 * b.output_qty_base / inQty : null) + '</b></div>' +
        '<div><small>Used in production</small>' + S.q(b.used_qty_base, u) + '</div>' +
        '<div><small>Left in stock</small>' + S.q(b.left_qty_base, u) + (expired ? '<br><span class="diff">past its ' + b.shelf_life_days + '-day shelf life</span>' : '') + '</div></div>'
        : '<div class="row totals"><div><small>Frying shrinkage</small>' + S.q(b.shrinkage_qty_base, u) + '</div><div><small>Packing wastage</small>' + S.q(b.packing_waste_qty_base, u) + '</div>' +
          (Number(b.abnormal_qty_base) ? '<div><small>Unusual loss</small>' + S.q(b.abnormal_qty_base, u) + '</div>' : '') + '</div>') +
      (Number(b.abnormal_qty_base) ? '<p class="muted">Unusual loss: ' + esc(b.abnormal_reason || '') + (cost ? ' · ' + money(b.abnormal_value_paise) + ' charged as a loss' : '') + '</p>' : '') +
      (cost ? '<div class="row totals"><div><small>Cost of what went in</small>' + money(b.input_value_paise) + '</div>' +
        (Number(b.packaging_value_paise) ? '<div><small>of which bottles and pouches</small>' + money(b.packaging_value_paise) + '</div>' : '') +
        (Number(b.byproduct_value_paise) ? '<div><small>By-products (at selling price)</small>−' + money(b.byproduct_value_paise) + '</div>' : '') +
        (Number(b.abnormal_value_paise) ? '<div><small>Unusual loss</small>−' + money(b.abnormal_value_paise) + '</div>' : '') +
        '<div><small>Cost of what was made</small><b>' + money(b.output_value_paise) + '</b>' +
        (Number(b.output_qty_base) ? '<br><span class="muted">' + money(Math.round(b.output_value_paise / b.output_qty_base * (u === 'g' || u === 'ml' ? 1000 : 1))) + ' per ' + bigUnit(u) + '</span>' : '') + '</div></div>' : '') +
      '</div>';

    const inT = '<div class="card"><h2>What went in</h2>' + table(['Item', 'From batch', 'Quantity'].concat(cost ? ['Cost'] : []),
      ins.concat(pk).map((l) => '<tr>' + td(esc(l.item_name) + (l.role === 'packaging' ? ' <span class="muted">(for ' + esc(l.pack_name || '') + ')</span>' : '')) +
        td(l.lot_batch_no ? '<a href="#/production/' + l.lot_batch_id + '">' + esc(l.lot_batch_no) + '</a> <span class="muted">' + RB.fmtDate(l.lot_date) + '</span>' : '') +
        td(S.q(l.qty_base, l.base_unit), true) + (cost ? td(money(l.value_paise), true) : '') + '</tr>')) + '</div>';
    const stT = prep && x.stages.length ? '<div class="card"><h2>Wastage at each stage</h2>' + table(['Stage', 'Wastage', '% of what went in'],
      x.stages.map((s) => '<tr>' + td(esc(s.stage)) + td(S.q(s.wastage_qty_base, ins[0] ? ins[0].base_unit : u), true) + td(pct(inQty ? 100 * s.wastage_qty_base / inQty : null), true) + '</tr>')) + '</div>' : '';
    const bpT = bps.length ? '<div class="card"><h2>By-products</h2>' + table(['By-product', 'At stage', 'Quantity', 'Goes to'].concat(cost ? ['Value'] : []),
      bps.map((l) => '<tr>' + td(esc(l.item_name)) + td(esc(l.stage || '')) + td(S.q(l.qty_base, l.base_unit), true) +
        td(l.byproduct_use === 'sellable' ? 'Stock (sellable)' : 'Wastage') + (cost ? td(money(l.value_paise), true) : '') + '</tr>')) + '</div>' : '';
    const outT = '<div class="card"><h2>What came out</h2>' + table(['Item', 'Pack', 'Packs', 'Quantity'].concat(cost ? ['Cost', 'Cost per pack'] : []),
      outs.map((l) => '<tr>' + td(esc(l.item_name)) + td(esc(l.pack_name || (prep ? '' : 'Loose'))) + td(l.packs != null ? trim(l.packs) : '', true) +
        td(S.q(l.qty_base, l.base_unit), true) + (cost ? td(money(l.value_paise), true) + td(l.packs ? money(Math.round(l.value_paise / l.packs)) : '', true) : '') + '</tr>')) + '</div>';
    const usedT = prep ? '<div class="card"><h2>Used in</h2>' + (x.used_in.length ? table(['Batch', 'Date', 'Product', 'Quantity used'],
      x.used_in.map((y) => '<tr>' + td('<a href="#/production/' + y.batch_id + '">' + esc(y.batch_no) + '</a>' + (y.status === 'reversed' ? ' ' + RB.badge('inactive', 'Reversed') : '')) +
        td(RB.fmtDate(y.batch_date)) + td(esc(y.product)) + td(S.q(y.qty_base, u), true) + '</tr>')) : '<p class="muted">Not used in a production batch yet.</p>') + '</div>' : '';

    body.innerHTML = '<div class="actions" style="margin:0 0 1rem">' +
      (RB.has('production.add') ? '<a class="btn primary" href="#/production/new">+ New batch</a>' : '') +
      (can.reverse ? '<button class="danger" id="bw-rev">Reverse batch</button>' : '') +
      (can.hard_delete ? '<button class="danger" id="bw-del">Delete fully (learning phase)</button>' : '') +
      '<button id="bw-print">Print</button></div>' + head + inT + stT + bpT + outT + usedT;
    on(body, '#bw-print', () => window.print());
    on(body, '#bw-rev', () => reverseModal('Reverse ' + b.batch_no, 'Its stock and its journal are reversed on the date you choose. ' +
      (prep ? 'If any of it went into a production batch, reverse that batch first.' : 'The finished goods must still be in stock.'),
      (dt, why) => RB.rpc('rb_reverse_batch', { p_id: id, p_date: dt, p_reason: why }), () => batchWindow(body, id)));
    on(body, '#bw-del', async () => {
      if (!(await RB.confirm('Delete this batch fully?', 'Only for entries by someone still in their learning phase. It disappears from stock and the books with no reversal.'))) return;
      try { await RB.rpc('rb_hard_delete_batch', { p_id: id }); RB.toast('Batch deleted'); location.hash = '#/production'; } catch (e) { RB.toast(e.message, true); }
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
  function reasonModal(title, explain, run, done) {
    const m = RB.modal('<h2>' + esc(title) + '</h2><div class="m-msg"></div><p>' + explain + '</p>' +
      RB.field('rs-why', 'Reason', '<textarea id="rs-why"></textarea>', null, true) +
      '<div class="actions"><button class="primary" id="rs-go">Confirm</button><button data-close>Back</button></div>');
    $('#rs-go', m.el).addEventListener('click', async () => {
      try { await run($('#rs-why', m.el).value); RB.toast('Done'); m.close(); if (done) done(); } catch (e) { RB.modalMsg(m, e.message); }
    });
  }

  // ===================================================================
  // Stock screen
  // ===================================================================
  RB.screens.stock = async (body) => {
    const tools = $('#page-tools');
    if (tools) tools.innerHTML = (RB.has('stock.add') ? '<button id="sk-count">+ Stock count</button><button id="sk-wo">+ Write off</button>' : '') +
      (RB.has('stock.add') && costOk() ? '<button id="sk-open">+ Opening stock</button>' : '') +
      (RB.has('production.view') ? '<a class="btn" href="#/production">Production</a>' : '');
    const refresh = () => RB.route();
    on(document, '#sk-count', () => countModal(null, 'count', refresh));
    on(document, '#sk-open', () => countModal(null, 'opening', refresh));
    on(document, '#sk-wo', () => adjustModal('write_off', refresh));
    tabs(body, 'stab', [['raw', 'Raw and prepared', rawTab], ['finished', 'Finished goods', finishedTab],
      ['counts', 'Stock counts', countsTab], ['adjust', 'Write-offs', adjustTab]]);
  };

  function asOf(tb, id, load) {
    tb.insertAdjacentHTML('afterbegin', '<div class="row" style="align-items:flex-end"><div class="field" style="flex:0 1 200px"><label for="' + id + '-date">Stock on</label>' +
      '<input type="date" id="' + id + '-date" value="' + RB.today() + '"></div><div class="field" style="flex:0 1 auto"><button id="' + id + '-go">Show</button> ' +
      '<button id="' + id + '-xls">Download to Excel</button></div></div>');
    $('#' + id + '-go', tb).addEventListener('click', () => load($('#' + id + '-date', tb).value).catch((e) => RB.toast(e.message, true)));
  }
  const stockCols = (fin) => {
    const cols = [
      { title: 'Code', field: 'code', width: 100 },
      { title: fin ? 'Product' : 'Item', field: 'name', minWidth: 200, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
    ];
    if (fin) cols.push({ title: 'Pack', field: 'pack_name', minWidth: 140, formatter: (c) => esc(c.getValue() || (c.getRow().getData().kind === 'byproduct' ? 'By-product' : 'Loose')) },
      { title: 'Packs', field: 'packs', hozAlign: 'right', headerFilter: false, formatter: (c) => (c.getValue() == null ? '' : '<b>' + trim(c.getValue()) + '</b>') });
    else cols.push({ title: 'Kind', field: 'kind_t', width: 140 });
    cols.push({ title: 'Quantity', field: 'qty_base', hozAlign: 'right', headerFilter: false, formatter: (c) => (fin ? '' : '<b>') + S.q(c.getValue(), c.getRow().getData().base_unit) + (fin ? '' : '</b>') });
    if (!fin) cols.push({ title: 'Oldest batch', field: 'oldest_lot', width: 130, headerFilter: false, formatter: (c) => RB.fmtDate(c.getValue()) },
      { title: 'Past shelf life', field: 'expired_qty', hozAlign: 'right', headerFilter: false, formatter: (c) => (Number(c.getValue()) ? '<span class="diff">' + S.q(c.getValue(), c.getRow().getData().base_unit) + '</span>' : '') });
    if (costOk()) cols.push({ title: 'Value', field: 'value_paise', hozAlign: 'right', headerFilter: false, formatter: (c) => money(c.getValue()) },
      { title: fin ? 'Cost per pack' : 'Average cost', field: 'avg_t', hozAlign: 'right', headerFilter: false });
    cols.push({ title: 'Last movement', field: 'last_move', width: 130, headerFilter: false, formatter: (c) => RB.fmtDate(c.getValue()) });
    return cols;
  };
  const withAvg = (r) => Object.assign({}, r, { kind_t: KIND[r.kind],
    avg_t: r.avg_cost_paise == null ? '' : (r.net_qty ? RB.rupees(Math.round(r.avg_cost_paise * r.net_qty)) + ' a pack'
      : RB.rupees(Math.round(r.avg_cost_paise * (r.base_unit === 'g' || r.base_unit === 'ml' ? 1000 : 1))) + ' a ' + bigUnit(r.base_unit)) });

  async function rawTab(tb) {
    tb.innerHTML = '<div class="card"><h2>Raw materials, bottles and pouches, prepared ingredients</h2><p class="muted">Tap an item to see its movements.</p><div id="rw-grid"></div></div>' +
      '<div class="card"><h2>Prepared ingredients, batch by batch</h2><p class="muted">With the date each was prepared. Batches past their shelf life (set on the item in Masters) are in <span class="diff">red</span>.</p><div id="rw-lots"></div></div>';
    let grid;
    asOf(tb, 'rw', async (dt) => {
      const [rows, lots] = await Promise.all([RB.rpc('rb_stock_list', { p_as_of: dt }), RB.rpc('rb_wip_lots', { p_as_of: dt })]);
      grid = RB.grid($('#rw-grid', tb), stockCols(false), rows.filter((r) => ['raw', 'packaging', 'wip'].includes(r.kind)).map(withAvg), {
        rowFormatter: (row) => { if (Number(row.getData().expired_qty)) row.getElement().classList.add('row-expired'); } });
      grid.on('rowClick', (e, row) => movesModal(row.getData()));
      const g2 = RB.grid($('#rw-lots', tb), [
        { title: 'Prepared ingredient', field: 'item_name', minWidth: 220, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
        { title: 'Batch', field: 'batch_no', width: 190, formatter: (c) => esc(c.getValue() || 'Without a batch') },
        { title: 'Prepared on', field: 'prep_date', width: 130, formatter: (c) => RB.fmtDate(c.getValue()) },
        { title: 'Left', field: 'qty_base', hozAlign: 'right', headerFilter: false, formatter: (c) => '<b>' + S.q(c.getValue(), c.getRow().getData().base_unit) + '</b>' },
        { title: 'Age (days)', field: 'age_days', hozAlign: 'right', headerFilter: false },
        { title: 'Shelf life', field: 'shelf_life_days', hozAlign: 'right', headerFilter: false, formatter: (c) => (c.getValue() ? c.getValue() + ' days' : '') },
        { title: 'Use by', field: 'expires_on', width: 130, headerFilter: false, formatter: (c) => (c.getRow().getData().expired ? '<span class="diff">' + RB.fmtDate(c.getValue()) + ' (past)</span>' : RB.fmtDate(c.getValue())) },
      ], lots, { rowFormatter: (row) => { if (row.getData().expired) row.getElement().classList.add('row-expired'); } });
      g2.on('rowClick', (e, row) => { if (row.getData().lot_batch_id) location.hash = '#/production/' + row.getData().lot_batch_id; });
    });
    $('#rw-xls', tb).addEventListener('click', () => grid && RB.downloadExcel(grid, 'Raw and prepared stock'));
    await $('#rw-go', tb).click();
  }

  async function finishedTab(tb) {
    tb.innerHTML = '<p class="muted">Finished goods are counted in bottles and pouches. They leave stock only through an invoice (module 5). ' +
      'Sellable by-products are listed too. <b>On hold</b> = packs in online orders not yet dispatched: they cannot be sold at the counter. Tap a line to see its movements.</p><div id="fn-grid"></div>';
    let grid;
    asOf(tb, 'fn', async (dt) => {
      const [rows, holds] = await Promise.all([RB.rpc('rb_stock_list', { p_as_of: dt }),
        RB.rpc('rb_shop_holds').catch(() => [])]);  // packs held by online orders (module 10)
      const held = Object.fromEntries((holds || []).map((h) => [h.pack_id, Number(h.held)]));
      const cols = stockCols(true);
      cols[3].title = 'Total packs';
      if (holds && holds.length !== undefined) cols.splice(4, 0,
        { title: 'On hold (online)', field: 'held', hozAlign: 'right', headerFilter: false, formatter: (c) => (c.getValue() ? trim(c.getValue()) : '') },
        { title: 'Free to sell', field: 'free', hozAlign: 'right', headerFilter: false, formatter: (c) => (c.getValue() == null ? '' : '<b>' + trim(c.getValue()) + '</b>') });
      grid = RB.grid($('#fn-grid', tb), cols, rows.filter((r) => ['finished', 'byproduct'].includes(r.kind)).map(withAvg)
        .map((r) => Object.assign(r, { held: held[r.pack_id] || 0, free: r.packs == null ? null : Math.max(0, Math.floor(Number(r.packs)) - (held[r.pack_id] || 0)) })));
      grid.on('rowClick', (e, row) => movesModal(row.getData()));
    });
    $('#fn-xls', tb).addEventListener('click', () => grid && RB.downloadExcel(grid, 'Finished goods stock'));
    await $('#fn-go', tb).click();
  }

  function movesModal(r) {
    const label = r.name + (r.pack_name ? ', ' + r.pack_name : '');
    const m = RB.modal('<h2>Movements: ' + esc(label) + '</h2><div class="m-msg"></div>' +
      '<div class="row" style="align-items:flex-end"><div class="field"><label for="mv-from">From</label><input type="date" id="mv-from" value="' + fy() + '"></div>' +
      '<div class="field"><label for="mv-to">To</label><input type="date" id="mv-to" value="' + RB.today() + '"></div>' +
      '<div class="field" style="flex:0 1 auto"><button id="mv-go">Show</button> <button id="mv-xls">Excel</button></div></div><div id="mv-grid"></div>' +
      '<div class="actions"><button data-close>Close</button></div>', { wide: true });
    let grid;
    const load = async () => {
      try {
        const rows = await RB.rpc('rb_stock_movements', { p_item: r.item_id, p_pack: r.pack_id, p_from: $('#mv-from', m.el).value, p_to: $('#mv-to', m.el).value });
        const cols = [
          { title: 'Date', field: 'move_date', width: 115, formatter: (c) => (c.getRow().getData().kind === 'brought_forward' ? '' : RB.fmtDate(c.getValue())) },
          { title: 'What', field: 'kind', width: 140, formatter: (c) => esc(MOVE[c.getValue()] != null ? MOVE[c.getValue()] : c.getValue()) },
          { title: 'Document', field: 'doc_no', width: 180 },
          { title: 'Batch', field: 'batch_no', width: 170 },
          { title: 'Note', field: 'note', minWidth: 180 },
          { title: 'In / out', field: 'qty_base', hozAlign: 'right', headerFilter: false, formatter: (c) => (c.getValue() == null ? '' : (c.getValue() > 0 ? '+' : '') + S.q(c.getValue(), r.base_unit)) },
          { title: 'Balance', field: 'balance_qty', hozAlign: 'right', headerFilter: false, formatter: (c) => '<b>' + S.q(c.getValue(), r.base_unit) + '</b>' },
        ];
        if (costOk()) cols.push({ title: 'Value', field: 'value_paise', hozAlign: 'right', headerFilter: false, formatter: (c) => money(c.getValue()) },
          { title: 'Value balance', field: 'balance_value', hozAlign: 'right', headerFilter: false, formatter: (c) => money(c.getValue()) });
        grid = RB.grid($('#mv-grid', m.el), cols, rows, { pagination: false, height: Math.min(440, 60 + rows.length * 34) });
      } catch (e) { RB.modalMsg(m, e.message); }
    };
    $('#mv-go', m.el).addEventListener('click', load);
    $('#mv-xls', m.el).addEventListener('click', () => grid && RB.downloadExcel(grid, 'Movements ' + label));
    load();
  }

  // ---------- stock counts ----------
  async function countsTab(tb) {
    const rows = await RB.rpc('rb_stock_count_list');
    tb.innerHTML = '<p class="muted">Count what is on the shelves; the differences against the books are posted as adjustments once someone other than the counter approves the count. ' +
      'Opening stock (at go-live) is entered the same way, with its cost.</p><div class="actions" style="margin:0 0 .75rem"><button id="ct-xls">Download to Excel</button></div><div id="ct-grid"></div>';
    const cols = [
      { title: 'Count', field: 'count_no', width: 190, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
      { title: 'Date', field: 'count_date', width: 115, formatter: (c) => RB.fmtDate(c.getValue()) },
      { title: 'Kind', field: 'purpose', width: 130, formatter: (c) => (c.getValue() === 'opening' ? 'Opening stock' : 'Stock count') },
      { title: 'Lines', field: 'lines', hozAlign: 'right', headerFilter: false },
      { title: 'Status', field: 'status', width: 180, formatter: (c) => status(c.getValue(), COUNT_STATUS) },
      { title: 'Counted by', field: 'entered_by_name', width: 130 },
      { title: 'Approved by', field: 'approved_by_name', width: 130 },
      { title: 'Note', field: 'note', minWidth: 200 },
    ];
    if (costOk()) cols.splice(4, 0, { title: 'Short', field: 'short_paise', hozAlign: 'right', headerFilter: false, formatter: (c) => (Number(c.getValue()) ? money(c.getValue()) : '') },
      { title: 'Over / opening', field: 'excess_paise', hozAlign: 'right', headerFilter: false, formatter: (c) => (Number(c.getValue()) ? money(c.getValue()) : '') });
    const grid = RB.grid($('#ct-grid', tb), cols, rows);
    grid.on('rowClick', (e, row) => countDetail(row.getData().id, () => countsTab(tb)));
    $('#ct-xls', tb).addEventListener('click', () => RB.downloadExcel(grid, 'Stock counts'));
  }

  async function countDetail(id, done) {
    let x;
    try { x = await RB.rpc('rb_stock_count_detail', { p_id: id }); } catch (e) { RB.toast(e.message, true); return; }
    const c = x.count, can = x.can, cost = costOk(), posted = c.status === 'posted' || c.status === 'reversed';
    const opening = c.purpose === 'opening';
    const showQ = (l, q) => (l.net_qty ? trim(q / l.net_qty) + ' packs' : S.q(q, l.base_unit));
    const m = RB.modal('<h2>' + esc(c.count_no) + RB.demoBadge(c) + '</h2><div class="m-msg"></div>' +
      '<p>' + (opening ? 'Opening stock' : 'Stock count') + ' · ' + RB.fmtDate(c.count_date) + ' · ' + status(c.status, COUNT_STATUS) +
      ' · counted by ' + esc(c.entered_by_name || '') + (c.approved_by_name ? ', approved by ' + esc(c.approved_by_name) : '') + (c.journal_no ? ' · ' + esc(c.journal_no) : '') + '</p>' +
      (c.note ? '<p class="muted">' + esc(c.note) + '</p>' : '') +
      (c.status === 'cancelled' ? '<div class="msg error">Cancelled: ' + esc(c.cancel_reason || '') + '</div>' : '') +
      (c.status === 'reversed' ? '<div class="msg error">Reversed: ' + esc(c.reverse_reason || '') + '</div>' : '') +
      (c.status === 'draft' && !opening ? '<p class="muted">Not posted yet. "In the books" is today\'s figure for the count date; it is fixed when the count is approved.</p>' : '') +
      '<div class="grid-wrap"><table class="ticks"><thead><tr><th>Item</th><th>Counted</th>' + (opening ? '' : '<th>In the books</th><th>Difference</th>') +
      (cost ? '<th>' + (opening ? 'Cost' : 'Value') + '</th>' : '') + '<th>Reason</th></tr></thead><tbody>' +
      x.lines.map((l) => {
        const diff = posted ? Number(l.diff_qty_base) : Number(l.counted_qty_base) - Number(l.system_qty_base);
        return '<tr><td style="text-align:left">' + esc(l.label) + '</td><td>' + showQ(l, l.counted_qty_base) + '</td>' +
          (opening ? '' : '<td>' + showQ(l, l.system_qty_base) + '</td><td class="' + (diff ? 'diff' : '') + '">' + (diff > 0 ? '+' : '') + (diff ? showQ(l, diff) : '–') + '</td>') +
          (cost ? '<td style="text-align:right">' + money(l.value_paise) + '</td>' : '') + '<td style="text-align:left">' + esc(l.reason || '') + '</td></tr>';
      }).join('') + '</tbody></table></div>' +
      (cost && posted && !opening ? '<p>Short <b>' + money(c.short_paise) + '</b> · over <b>' + money(c.excess_paise) + '</b> (Inventory Shrinkage Expense)</p>' : '') +
      '<div class="actions">' + (can.post ? '<button class="primary" id="cd-post">Approve and post</button>' : '') +
      (can.edit ? '<button id="cd-edit">Change</button><button class="danger" id="cd-cancel">Cancel count</button>' : '') +
      (can.reverse ? '<button class="danger" id="cd-rev">Reverse</button>' : '') + '<button data-close>Close</button></div>', { wide: true });
    if (c.status === 'draft' && !can.post && RB.has('stock.approve')) m.el.querySelector('.m-msg').innerHTML = '<div class="msg info">Someone other than the person who counted must approve it.</div>';
    on(m.el, '#cd-post', async () => {
      if (!(await RB.confirm('Approve and post?', opening ? 'The opening stock goes into stock and the books at the costs given.' : 'Every difference against the books is posted to stock and to Inventory Shrinkage Expense.'))) return;
      try { await RB.rpc('rb_post_stock_count', { p_id: id }); RB.toast('Count posted'); m.close(); done(); } catch (e) { RB.modalMsg(m, e.message); }
    });
    on(m.el, '#cd-edit', () => { m.close(); countModal(x, c.purpose, done); });
    on(m.el, '#cd-cancel', () => { m.close(); reasonModal('Cancel ' + c.count_no, 'Nothing is posted.', (why) => RB.rpc('rb_cancel_stock_count', { p_id: id, p_reason: why }), done); });
    on(m.el, '#cd-rev', () => { m.close(); reverseModal('Reverse ' + c.count_no, 'The stock adjustments and the journal are reversed on the date you choose.',
      (dt, why) => RB.rpc('rb_reverse_stock_entry', { p_kind: 'count', p_id: id, p_date: dt, p_reason: why }), done); });
  }

  // New or changed count (or opening stock): a count sheet of every stock line.
  async function countModal(x, purpose, done) {
    const opening = purpose === 'opening';
    const c = x ? x.count : { count_date: RB.today() };
    const [d, rows] = await Promise.all([lists(), RB.rpc('rb_stock_list', { p_as_of: c.count_date })]);
    const prev = {}; (x ? x.lines : []).forEach((l) => { prev[l.item_id + '/' + (l.pack_id || '')] = l; });
    const GROUPS = [['raw', 'Raw materials'], ['packaging', 'Bottles and pouches'], ['wip', 'Prepared'], ['finished', 'Finished goods'], ['byproduct', 'By-products']];
    const lines = rows.filter((r) => r.is_active || prev[r.item_id + '/' + (r.pack_id || '')]).map((r) => {
      const p = prev[r.item_id + '/' + (r.pack_id || '')];
      const unit = r.pack_id ? 'pack' : bigUnit(r.base_unit);
      const toUnit = (qb) => (r.pack_id ? qb / r.net_qty : (r.base_unit === 'g' || r.base_unit === 'ml') ? qb / 1000 : qb);
      return Object.assign({}, r, { unit, counted: p ? trim(toUnit(p.counted_qty_base)) : '', reason: p ? p.reason || '' : '',
        rate: p && p.unit_cost_paise != null ? RB.fromPaise(Math.round(p.unit_cost_paise * (r.pack_id ? r.net_qty : (r.base_unit === 'g' || r.base_unit === 'ml') ? 1000 : 1))) : '',
        books: toUnit(r.qty_base) });
    });
    let group = S.countGroup || 'raw', showBooks = false;
    const m = RB.modal('<h2>' + (x ? 'Change ' + esc(c.count_no) : opening ? 'Opening stock' : 'New stock count') + '</h2><div class="m-msg"></div>' +
      '<p class="muted">' + (opening ? 'Stock on hand at go-live, with what it cost. It is posted against "Opening balance clearing" when approved.'
        : 'Enter what is physically on the shelves. Leave a line blank if you did not count it; enter 0 if there is none. Someone other than you approves the count.') + '</p>' +
      '<div class="row">' + RB.field('cm-date', opening ? 'Go-live date' : 'Date of the count', '<input type="date" id="cm-date" value="' + esc(c.count_date) + '">', null, true) +
      RB.field('cm-dept', 'Department', RB.sel('cm-dept', d.depts, c.department_id || d.defaultDept)) +
      RB.field('cm-note', 'Note', RB.inp('cm-note', c.note || '')) + '</div>' +
      '<div class="actions" style="margin:.25rem 0 .5rem">' + GROUPS.map(([k, t]) => '<button type="button" data-g="' + k + '">' + t + '</button>').join('') +
      (opening ? '' : '<label style="margin-left:auto"><input type="checkbox" id="cm-books"> Show book quantities</label>') + '</div>' +
      '<div id="cm-lines"></div><p id="cm-sum" class="muted"></p>' +
      '<div class="actions"><button class="primary" id="cm-save">Save ' + (opening ? 'opening stock' : 'count') + '</button><button data-close>Cancel</button></div>', { wide: true });
    const draw = () => {
      $$('[data-g]', m.el).forEach((b) => b.classList.toggle('primary', b.dataset.g === group));
      const my = lines.filter((l) => l.kind === group);
      $('#cm-lines', m.el).innerHTML = my.length ? '<div class="grid-wrap"><table class="ticks lines"><thead><tr><th>Item</th><th>Counted</th><th>Unit</th>' +
        (showBooks ? '<th>In the books</th>' : '') + (opening ? '<th>Cost per unit ₹</th>' : '<th>Reason for a difference</th>') + '</tr></thead><tbody>' +
        my.map((l) => { const i = lines.indexOf(l); return '<tr><td style="text-align:left">' + esc(l.name) + (l.pack_name ? ', ' + esc(l.pack_name) : (l.kind === 'finished' ? ' (loose)' : '')) + RB.demoBadge(l) + '</td>' +
          '<td style="min-width:100px"><input data-c="' + i + '" data-f="counted" inputmode="decimal" value="' + esc(l.counted) + '"></td><td>' + esc(l.unit) + '</td>' +
          (showBooks ? '<td>' + trim(l.books) + '</td>' : '') +
          (opening ? '<td style="min-width:110px"><input data-c="' + i + '" data-f="rate" inputmode="decimal" value="' + esc(l.rate) + '"></td>'
            : '<td style="min-width:160px"><input data-c="' + i + '" data-f="reason" value="' + esc(l.reason) + '"></td>') + '</tr>'; }).join('') +
        '</tbody></table></div>' : '<p class="muted">Nothing of this kind in Masters.</p>';
      $$('[data-c]', m.el).forEach((el) => el.addEventListener('input', () => { lines[el.dataset.c][el.dataset.f] = el.value; sum(); }));
      sum();
    };
    const sum = () => { const n = lines.filter((l) => String(l.counted).trim() !== '').length; $('#cm-sum', m.el).textContent = n + ' line(s) counted so far, across all groups.'; };
    $$('[data-g]', m.el).forEach((b) => b.addEventListener('click', () => { group = S.countGroup = b.dataset.g; draw(); }));
    on(m.el, '#cm-books', (e) => { showBooks = e.target.checked; draw(); }, 'change');
    draw();
    $('#cm-save', m.el).addEventListener('click', async () => {
      try {
        const out = lines.filter((l) => String(l.counted).trim() !== '').map((l) => {
          const o = { item_id: l.item_id, pack_id: l.pack_id, reason: l.reason || null };
          if (l.pack_id) o.packs = num(l.counted); else { o.qty = num(l.counted); o.unit = l.unit; }
          if (opening) o.rate_paise = RB.toPaise(l.rate);
          return o;
        });
        const newId = await RB.rpc('rb_save_stock_count', { p: { id: x ? c.id : null, purpose, count_date: $('#cm-date', m.el).value,
          department_id: Number($('#cm-dept', m.el).value) || null, note: $('#cm-note', m.el).value, lines: out } });
        RB.toast(opening ? 'Opening stock saved' : 'Count saved'); m.close();
        S.stab = 'counts';
        if (done) done();
        countDetail(newId, done || (() => {}));
      } catch (e) { RB.modalMsg(m, e.message); m.el.scrollTop = 0; }
    });
  }

  // ---------- write-offs and write-downs ----------
  async function adjustTab(tb) {
    const rows = await RB.rpc('rb_stock_adjustment_list');
    tb.innerHTML = '<p class="muted">Write-offs take spoilt, expired or damaged stock out at its cost. Write-downs (Accountant, FC or a Director) lower the cost of stock that will sell for less than it cost (AS 2). ' +
      'Both are charged to Inventory Write-down Expense; a Manager\'s write-off waits for approval.</p>' +
      '<div class="actions" style="margin:0 0 .75rem">' + (RB.has('stock.add') && costOk() ? '<button id="aj-wd">+ Write down</button>' : '') + '<button id="aj-xls">Download to Excel</button></div><div id="aj-grid"></div>';
    const cols = [
      { title: 'Number', field: 'adj_no', width: 180, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
      { title: 'Date', field: 'adj_date', width: 115, formatter: (c) => RB.fmtDate(c.getValue()) },
      { title: 'Kind', field: 'kind', width: 110, formatter: (c) => (c.getValue() === 'write_off' ? 'Write-off' : 'Write-down') },
      { title: 'Item', field: 'label', minWidth: 200 },
      { title: 'Batch', field: 'lot_batch_no', width: 170 },
      { title: 'Quantity', field: 'qty_base', hozAlign: 'right', headerFilter: false, formatter: (c) => (Number(c.getValue()) ? S.q(c.getValue(), c.getRow().getData().base_unit) : '') },
      { title: 'Reason', field: 'reason', minWidth: 220 },
      { title: 'Status', field: 'status', width: 180, formatter: (c) => status(c.getValue(), ADJ_STATUS) },
      { title: 'Entered by', field: 'entered_by_name', width: 120 },
    ];
    if (costOk()) cols.splice(6, 0, { title: 'Value', field: 'value_paise', hozAlign: 'right', headerFilter: false, formatter: (c) => (Number(c.getValue()) ? money(c.getValue()) : '') });
    const grid = RB.grid($('#aj-grid', tb), cols, rows);
    const reload = () => adjustTab(tb);
    grid.on('rowClick', (e, row) => adjustDetail(row.getData(), reload));
    on(tb, '#aj-wd', () => adjustModal('write_down', reload));
    $('#aj-xls', tb).addEventListener('click', () => RB.downloadExcel(grid, 'Write-offs'));
  }

  function adjustDetail(a, done) {
    const m = RB.modal('<h2>' + esc(a.adj_no) + RB.demoBadge(a) + '</h2><div class="m-msg"></div>' +
      '<p>' + (a.kind === 'write_off' ? 'Write-off' : 'Write-down') + ' · ' + RB.fmtDate(a.adj_date) + ' · ' + status(a.status, ADJ_STATUS) + '</p>' +
      '<p><b>' + esc(a.label) + '</b>' + (a.lot_batch_no ? ' · batch ' + esc(a.lot_batch_no) : '') + (Number(a.qty_base) ? ' · ' + S.q(a.qty_base, a.base_unit) : '') +
      (a.value_paise != null && Number(a.value_paise) ? ' · ' + money(a.value_paise) : '') + '</p><p class="muted">' + esc(a.reason) + '</p>' +
      '<p class="muted">Entered by ' + esc(a.entered_by_name || '') + (a.approved_by_name ? ', approved by ' + esc(a.approved_by_name) : '') + '</p>' +
      (a.refused_reason ? '<div class="msg error">Refused: ' + esc(a.refused_reason) + '</div>' : '') +
      (a.reverse_reason ? '<div class="msg error">Reversed: ' + esc(a.reverse_reason) + '</div>' : '') +
      '<div class="actions">' + (a.can_approve ? '<button class="primary" id="ad-ok">Approve and post</button><button class="danger" id="ad-no">Refuse</button>' : '') +
      (a.can_reverse ? '<button class="danger" id="ad-rev">Reverse</button>' : '') + '<button data-close>Close</button></div>');
    on(m.el, '#ad-ok', async () => {
      try { await RB.rpc('rb_approve_stock_adjustment', { p_id: a.id }); RB.toast('Posted'); m.close(); done(); } catch (e) { RB.modalMsg(m, e.message); }
    });
    on(m.el, '#ad-no', () => { m.close(); reasonModal('Refuse ' + a.adj_no, 'Nothing is posted.', (why) => RB.rpc('rb_refuse_stock_adjustment', { p_id: a.id, p_reason: why }), done); });
    on(m.el, '#ad-rev', () => { m.close(); reverseModal('Reverse ' + a.adj_no, 'The stock comes back and the journal is reversed on the date you choose.',
      (dt, why) => RB.rpc('rb_reverse_stock_entry', { p_kind: 'adjustment', p_id: a.id, p_date: dt, p_reason: why }), done); });
  }

  async function adjustModal(kind, done) {
    const wo = kind === 'write_off';
    const [d, rows, lots] = await Promise.all([lists(), RB.rpc('rb_stock_list', { p_as_of: RB.today() }), RB.rpc('rb_wip_lots', { p_as_of: RB.today() })]);
    const have = rows.filter((r) => Number(r.qty_base) > 0 || (!wo && Number(r.value_paise) > 0));
    const key = (r) => r.item_id + '/' + (r.pack_id || '');
    const m = RB.modal('<h2>' + (wo ? 'Write off stock' : 'Write down stock to net realisable value') + '</h2><div class="m-msg"></div>' +
      '<p class="muted">' + (wo ? 'For stock that is spoilt, past its shelf life or damaged. It leaves stock at its cost. ' + (RB.has('power.approve_own') ? '' : 'It waits for approval by the Accountant, FC, a Director or a Manager other than you.')
        : 'For stock that will sell for less than it cost. The quantity stays; its cost goes down by the amount you enter.') + '</p>' +
      '<div class="row">' + RB.field('aj-date', 'Date', '<input type="date" id="aj-date" value="' + RB.today() + '">', null, true) +
      RB.field('aj-dept', 'Department', RB.sel('aj-dept', d.depts, d.defaultDept)) + '</div>' +
      RB.field('aj-item', 'Item', RB.sel('aj-item', [['', 'Choose…']].concat(have.map((r) => [key(r), r.name + (r.pack_name ? ', ' + r.pack_name : '') + ' — ' +
        (r.pack_id ? trim(r.packs) + ' packs' : S.q(r.qty_base, r.base_unit)) + ' in stock'])), ''), null, true) +
      '<div id="aj-more"></div>' +
      RB.field('aj-why', 'Reason', '<textarea id="aj-why" placeholder="' + (wo ? 'e.g. past its shelf life, gone soft' : 'e.g. selling price cut below cost') + '"></textarea>', null, true) +
      '<div class="actions"><button class="primary" id="aj-save">Save</button><button data-close>Cancel</button></div>');
    const more = () => {
      const r = have.find((x) => key(x) === $('#aj-item', m.el).value);
      if (!r) { $('#aj-more', m.el).innerHTML = ''; return; }
      const myLots = r.kind === 'wip' ? lots.filter((l) => l.item_id === r.item_id) : [];
      $('#aj-more', m.el).innerHTML = '<div class="row">' + (wo
        ? (myLots.length ? RB.field('aj-lot', 'Batch', RB.sel('aj-lot', [['', 'Oldest first']].concat(myLots.map((l) => [l.lot_batch_id == null ? '' : l.lot_batch_id,
            (l.batch_no || 'Without a batch') + ', ' + RB.fmtDate(l.prep_date) + ', ' + S.q(l.qty_base, l.base_unit) + (l.expired ? ' · PAST SHELF LIFE' : '')])),
            (myLots.find((l) => l.expired) || {}).lot_batch_id || '')) : '') +
          RB.field('aj-qty', 'Quantity written off', '<input id="aj-qty" inputmode="decimal">', null, true) +
          RB.field('aj-unit', 'Unit', r.pack_id ? '<input value="packs" disabled>' : RB.sel('aj-unit', unitsFor(r.base_unit).map((x) => [x, x]), unitsFor(r.base_unit)[0]))
        : RB.field('aj-val', 'Write down by ₹', '<input id="aj-val" inputmode="decimal">', r.value_paise != null ? 'Its cost now: ' + money(r.value_paise) : null, true)) + '</div>';
    };
    on(m.el, '#aj-item', more, 'change');
    $('#aj-save', m.el).addEventListener('click', async () => {
      try {
        const r = have.find((x) => key(x) === $('#aj-item', m.el).value);
        if (!r) throw new Error('Please choose the item.');
        const p = { kind, adj_date: $('#aj-date', m.el).value, department_id: Number($('#aj-dept', m.el).value) || null, item_id: r.item_id, pack_id: r.pack_id,
          reason: $('#aj-why', m.el).value };
        if (wo) {
          if (r.pack_id) p.packs = num($('#aj-qty', m.el).value); else { p.qty = num($('#aj-qty', m.el).value); p.unit = $('#aj-unit', m.el).value; }
          const lot = $('#aj-lot', m.el); if (lot && lot.value) p.lot_batch_id = Number(lot.value);
        } else p.value_paise = RB.toPaise($('#aj-val', m.el).value);
        await RB.rpc('rb_save_stock_adjustment', { p });
        RB.toast(wo ? 'Write-off saved' : 'Write-down posted'); m.close();
        S.stab = 'adjust'; if (done) done();
      } catch (e) { RB.modalMsg(m, e.message); }
    });
  }
})();
