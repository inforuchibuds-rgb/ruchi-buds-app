// =====================================================================
// RUCHI BUDS APP · masters.js · Version 1.2 · 27-Nov-2026
// Module 2 screens: Masters (items, packs and prices, departments,
// units), Customers and Suppliers. The Add customer / Add supplier forms
// are shared, so the Sales and Purchase screens can open them later.
// =====================================================================
(function () {
  'use strict';
  const RB = window.RB, $ = RB.$, $$ = RB.$$, esc = RB.esc;
  const M = (RB.masters = {});

  const KINDS = { raw: 'Raw material', wip: 'Prepared (WIP)', finished: 'Finished goods', byproduct: 'By-product', packaging: 'Packaging' };
  const CUST_KINDS = { retail: 'Retail', trader: 'Trader' };
  const SUP_KINDS = { fisherman: 'Fisherman', farmer: 'Farmer', local: 'Local supplier', company: 'Company', other: 'Other' };
  const DIMS = { mass: 'Weight', volume: 'Volume', piece: 'Pieces', box: 'Boxes' };

  // ---------- shared helpers (also used by accounts.js) ----------
  // "1,234.50" -> 123450 paise; '' -> null
  RB.toPaise = (v) => {
    const s = String(v == null ? '' : v).replace(/[₹,\s]/g, '');
    if (s === '') return null;
    const n = Number(s);
    if (!isFinite(n)) throw new Error('"' + v + '" is not an amount.');
    return Math.round(n * 100);
  };
  RB.fromPaise = (p) => (p == null ? '' : (Number(p) / 100).toFixed(2));
  RB.qty = (n, unit) => n == null ? '' : Number(n).toLocaleString('en-IN', { maximumFractionDigits: 3 }) + ' ' + (unit || '');
  // Show a message inside a modal.
  RB.modalMsg = (m, text, ok) => { $('.m-msg', m.el).innerHTML = '<div class="msg ' + (ok ? 'ok' : 'error') + '">' + esc(text) + '</div>'; };
  RB.field = (id, label, input, hint, req) => '<div class="field"><label for="' + id + '">' + label + (req ? ' <span class="req">*</span>' : '') + '</label>' + input +
    (hint ? '<div class="hint">' + hint + '</div>' : '') + '</div>';
  RB.inp = (id, val, extra) => '<input id="' + id + '" value="' + esc(val == null ? '' : val) + '"' + (extra || '') + '>';
  RB.sel = (id, options, val, extra) => '<select id="' + id + '"' + (extra || '') + '>' +
    options.map(([k, t]) => '<option value="' + esc(k) + '"' + (String(k) === String(val == null ? '' : val) ? ' selected' : '') + '>' + esc(t) + '</option>').join('') + '</select>';
  RB.activeBadge = (on) => on ? RB.badge('active', 'Active') : RB.badge('inactive', 'Switched off');

  M.load = async (what) => {
    const map = {
      units: () => RB.select('units', '*', (q) => q.order('sort')),
      items: () => RB.select('items', '*', (q) => q.order('code')),
      packTypes: () => RB.select('pack_types', '*', (q) => q.order('code')),
      productPacks: () => RB.select('product_packs', '*', (q) => q.order('id')),
      departments: () => RB.select('departments', '*', (q) => q.order('code')),
      deptEvents: () => RB.select('dept_events', '*', (q) => q.order('id', { ascending: false })),
      customers: () => RB.select('customers', '*', (q) => q.order('code')),
      suppliers: () => RB.select('suppliers', '*', (q) => q.order('code')),
    };
    const out = {};
    await Promise.all(what.map(async (k) => { out[k] = await map[k](); }));
    return out;
  };

  function tabs(body, list, start) {
    body.innerHTML = '<div class="tabs">' + list.map(([k, t]) => '<button data-tab="' + k + '">' + t + '</button>').join('') + '</div><div id="tab-body"></div>';
    const show = async (k) => {
      $$('.tabs button', body).forEach((b) => b.classList.toggle('on', b.dataset.tab === k));
      const tb = $('#tab-body', body);
      tb.innerHTML = '<p class="muted">Loading…</p>';
      try { await list.find((x) => x[0] === k)[2](tb); }
      catch (e) { tb.innerHTML = '<div class="msg error">' + esc(e.message) + '</div>'; }
    };
    $$('.tabs button', body).forEach((b) => b.addEventListener('click', () => show(b.dataset.tab)));
    show(start || list[0][0]);
  }

  // ===================================================================
  // Masters screen
  // ===================================================================
  RB.screens.masters = async (body) => {
    tabs(body, [
      ['items', 'Items', itemsTab],
      ['packs', 'Packs and prices', packsTab],
      ['depts', 'Departments', deptsTab],
      ['units', 'Units', unitsTab],
    ]);
  };

  // ---------- items ----------
  async function itemsTab(tb) {
    const d = await M.load(['items', 'units']);
    const byId = Object.fromEntries(d.items.map((i) => [i.id, i]));
    tb.innerHTML = '<div class="actions" style="margin:0 0 .75rem">' +
      (RB.has('masters.add') ? '<button class="primary" id="it-add">+ Add item</button>' : '') +
      '</div>' +
      '<p class="muted">Raw materials, prepared ingredients (work in progress), finished goods, by-products and packaging. Tap an item to see or change it.</p><div id="it-grid"></div>';
    const rows = d.items.map((i) => Object.assign({}, i, {
      kind_t: KINDS[i.kind], stages_t: (i.stages || []).join(' → '),
      becomes: i.prepared_item_id && byId[i.prepared_item_id] ? byId[i.prepared_item_id].name : '',
      status: i.is_active ? 'Active' : 'Switched off',
    }));
    const grid = RB.grid($('#it-grid', tb), [
      { title: 'Code', field: 'code', width: 90 },
      { title: 'Name', field: 'name', minWidth: 200, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
      { title: 'Kind', field: 'kind_t', headerFilter: 'list', headerFilterParams: { values: Object.assign({ '': 'All' }, Object.fromEntries(Object.values(KINDS).map((k) => [k, k]))) } },
      { title: 'Unit', field: 'base_unit', width: 70 },
      { title: 'Stages', field: 'stages_t' },
      { title: 'Becomes', field: 'becomes' },
      { title: 'Shelf life (days)', field: 'shelf_life_days', hozAlign: 'right' },
      { title: 'By-product', field: 'byproduct_use' },
      { title: 'HSN', field: 'hsn_code', width: 80 },
      { title: 'GST %', field: 'gst_rate', hozAlign: 'right', width: 80 },
      { title: 'Status', field: 'status', formatter: (c) => RB.activeBadge(c.getRow().getData().is_active) },
    ], rows);
    grid.on('rowClick', (e, row) => itemModal(byId[row.getData().id], d, () => itemsTab(tb)));
    const add = $('#it-add', tb); if (add) add.addEventListener('click', () => itemModal(null, d, () => itemsTab(tb)));
  }

  function itemModal(it, d, done) {
    const isNew = !it, edit = isNew ? RB.has('masters.add') : RB.has('masters.edit'), dis = edit ? '' : ' disabled';
    it = it || { kind: 'raw', base_unit: 'g', buy_unit: 'kg', stages: [], is_active: true };
    const unitOpts = d.units.map((u) => [u.code, u.code + ' (' + u.name + ')']);
    const wipOpts = [['', '(none)']].concat(d.items.filter((i) => i.kind === 'wip' && i.is_active).map((i) => [i.id, i.name]));
    const m = RB.modal('<h2>' + (isNew ? 'Add an item' : esc(it.name) + RB.demoBadge(it)) + '</h2><div class="m-msg"></div>' +
      '<div class="row">' + RB.field('i-name', 'Name', RB.inp('i-name', it.name, dis), null, true) +
      RB.field('i-code', 'Code', RB.inp('i-code', it.code, dis + ' placeholder="made for you"'), 'Leave blank for the next RM / WP / FG / BP / PK number.') + '</div>' +
      '<div class="row">' + RB.field('i-kind', 'Kind', RB.sel('i-kind', Object.entries(KINDS), it.kind, dis), null, true) +
      RB.field('i-unit', 'Stock unit', RB.sel('i-unit', unitOpts, it.base_unit, dis), 'Stock is kept in this unit: grams for weight, ml for liquids, pieces for bottles.', true) +
      RB.field('i-buy', 'Usually bought in', RB.sel('i-buy', unitOpts, it.buy_unit || it.base_unit, dis)) + '</div>' +
      '<div data-for="raw">' + RB.field('i-stages', 'Preparation stages', RB.inp('i-stages', (it.stages || []).join(', '), dis + ' placeholder="e.g. Clean, Boil and de-bone, Fry"'),
        'In order, separated by commas. Wastage is recorded at each stage in the Production window.') +
      RB.field('i-becomes', 'Becomes (prepared ingredient)', RB.sel('i-becomes', wipOpts, it.prepared_item_id, dis)) + '</div>' +
      '<div data-for="wip">' + RB.field('i-shelf', 'Shelf life (days)', RB.inp('i-shelf', it.shelf_life_days, dis + ' type="number" min="1"'),
        'Older stock shows in red on the Stock tab and is warned about in the Production window.') + '</div>' +
      '<div data-for="byproduct">' + RB.field('i-use', 'By-product is', RB.sel('i-use', [['', 'Choose…'], ['sellable', 'Sellable (goes to stock)'], ['discarded', 'Discarded (goes to wastage)']], it.byproduct_use, dis), null, true) + '</div>' +
      '<div data-for="finished byproduct"><div class="row">' +
      RB.field('i-sells', 'Sold by', RB.sel('i-sells', [['pack', 'Pack (bottle or pouch)'], ['weight', 'Weight (grams)'], ['piece', 'Piece']], it.sells_by || 'pack', dis)) +
      RB.field('i-loose', 'Loose price (₹ per kg or piece)', RB.inp('i-loose', RB.fromPaise(it.loose_price_paise), dis + ' inputmode="decimal"'), 'Only when sold loose by weight. Pack prices are on the Packs and prices tab.') + '</div></div>' +
      '<div class="row">' + RB.field('i-hsn', 'HSN code', RB.inp('i-hsn', it.hsn_code, dis)) +
      RB.field('i-gst', 'GST rate %', RB.inp('i-gst', it.gst_rate, dis + ' type="number" min="0" max="40" step="0.01"'), 'Needed only for Tax Invoices.') + '</div>' +
      RB.field('i-notes', 'Notes', '<textarea id="i-notes"' + dis + '>' + esc(it.notes || '') + '</textarea>') +
      (isNew ? '' : '<p class="muted">Status: ' + RB.activeBadge(it.is_active) + '</p>') +
      '<div class="actions">' + (edit ? '<button class="primary" id="i-save">Save</button>' : '') +
      (!isNew && RB.has('masters.edit') ? '<button id="i-onoff">' + (it.is_active ? 'Switch off' : 'Switch back on') + '</button>' : '') +
      (!isNew && RB.has('masters.delete') ? '<button class="danger" id="i-del">Delete</button>' : '') +
      '<button data-close>Close</button></div>', { wide: true });
    const sync = () => {
      const k = $('#i-kind', m.el).value;
      $$('[data-for]', m.el).forEach((el) => el.classList.toggle('hidden', !el.dataset.for.split(' ').includes(k)));
    };
    $('#i-kind', m.el).addEventListener('change', sync); sync();
    const on = (id, fn) => { const b = $(id, m.el); if (b) b.addEventListener('click', fn); };
    on('#i-save', async () => {
      try {
        const v = (id) => $('#' + id, m.el).value;
        await RB.rpc('rb_save_item', { p: {
          id: it.id || null, code: v('i-code'), name: v('i-name'), kind: v('i-kind'), base_unit: v('i-unit'), buy_unit: v('i-buy'),
          stages: v('i-stages').split(',').map((s) => s.trim()).filter(Boolean), prepared_item_id: v('i-becomes') || null,
          shelf_life_days: v('i-shelf') || null, byproduct_use: v('i-use') || null, sells_by: v('i-sells'),
          loose_price_paise: RB.toPaise(v('i-loose')), hsn_code: v('i-hsn'), gst_rate: v('i-gst'), notes: v('i-notes'),
        } });
        RB.toast('Item saved'); m.close(); done();
      } catch (e) { RB.modalMsg(m, e.message); }
    });
    on('#i-onoff', async () => {
      try { await RB.rpc('rb_set_item_active', { p_id: it.id, p_active: !it.is_active }); RB.toast(it.is_active ? 'Switched off' : 'Switched back on'); m.close(); done(); }
      catch (e) { RB.modalMsg(m, e.message); }
    });
    on('#i-del', async () => {
      if (!(await RB.confirm('Delete ' + it.name + '?', 'Only an item that was never used can be deleted. Otherwise switch it off.'))) return;
      try { await RB.rpc('rb_delete_item', { p_id: it.id }); RB.toast('Deleted'); m.close(); done(); }
      catch (e) { RB.modalMsg(m, e.message); }
    });
  }

  // ---------- packs and prices ----------
  async function packsTab(tb) {
    const d = await M.load(['items', 'packTypes', 'productPacks', 'units']);
    const item = Object.fromEntries(d.items.map((i) => [i.id, i]));
    const pack = Object.fromEntries(d.packTypes.map((p) => [p.id, p]));
    const add = RB.has('masters.add');
    tb.innerHTML =
      '<section class="card"><h2>Products in packs, with prices</h2>' +
      '<p class="muted">The same bottle can hold different weights of different products. Stock of finished goods is counted in these packs. Trader and online prices are optional; when blank, the retail price is used.</p>' +
      '<div class="actions" style="margin:0 0 .75rem">' + (add ? '<button class="primary" id="pp-add">+ Add product pack</button>' : '') + '</div><div id="pp-grid"></div></section>' +
      '<section class="card"><h2>Pack types</h2><p class="muted">Bottles and pouches. Link each one to its empty bottle or pouch (a packaging item), so final production can use them up from stock.</p>' +
      '<div class="actions" style="margin:0 0 .75rem">' + (add ? '<button id="pt-add">+ Add pack type</button>' : '') + '</div><div id="pt-grid"></div></section>';
    const ppRows = d.productPacks.map((p) => {
      const i = item[p.item_id] || {};
      return Object.assign({}, p, { product: i.name, pack: (pack[p.pack_type_id] || {}).name, holds: RB.qty(p.net_qty, i.base_unit),
        retail: RB.rupees(p.retail_price_paise), trader: RB.rupees(p.trader_price_paise), online: RB.rupees(p.online_price_paise) });
    });
    const ppGrid = RB.grid($('#pp-grid', tb), [
      { title: 'Product', field: 'product', minWidth: 180, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
      { title: 'Pack', field: 'pack' },
      { title: 'Holds', field: 'holds', hozAlign: 'right' },
      { title: 'Retail price', field: 'retail', hozAlign: 'right' },
      { title: 'Trader price', field: 'trader', hozAlign: 'right' },
      { title: 'Online price', field: 'online', hozAlign: 'right' },
      { title: 'Status', field: 'is_active', formatter: (c) => RB.activeBadge(c.getValue()), headerFilter: false },
    ], ppRows);
    ppGrid.on('rowClick', (e, row) => productPackModal(d.productPacks.find((x) => x.id === row.getData().id), d, () => packsTab(tb)));
    const ptRows = d.packTypes.map((p) => Object.assign({}, p, { empty: p.packaging_item_id && item[p.packaging_item_id] ? item[p.packaging_item_id].name : '' }));
    const ptGrid = RB.grid($('#pt-grid', tb), [
      { title: 'Code', field: 'code', width: 90 },
      { title: 'Pack', field: 'name', formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
      { title: 'Kind', field: 'kind' },
      { title: 'Empty bottle / pouch in stock', field: 'empty' },
      { title: 'Status', field: 'is_active', formatter: (c) => RB.activeBadge(c.getValue()), headerFilter: false },
    ], ptRows);
    ptGrid.on('rowClick', (e, row) => packTypeModal(d.packTypes.find((x) => x.id === row.getData().id), d, () => packsTab(tb)));
    const a1 = $('#pp-add', tb); if (a1) a1.addEventListener('click', () => productPackModal(null, d, () => packsTab(tb)));
    const a2 = $('#pt-add', tb); if (a2) a2.addEventListener('click', () => packTypeModal(null, d, () => packsTab(tb)));
  }

  function packTypeModal(pt, d, done) {
    const isNew = !pt, edit = isNew ? RB.has('masters.add') : RB.has('masters.edit'), dis = edit ? '' : ' disabled';
    pt = pt || { kind: 'bottle', is_active: true };
    const empties = [['', '(none yet)']].concat(d.items.filter((i) => i.kind === 'packaging').map((i) => [i.id, i.name]));
    const m = RB.modal('<h2>' + (isNew ? 'Add a pack type' : esc(pt.name)) + '</h2><div class="m-msg"></div>' +
      '<div class="row">' + RB.field('pt-name', 'Name', RB.inp('pt-name', pt.name, dis + ' placeholder="e.g. 200 g bottle"'), null, true) +
      RB.field('pt-code', 'Code', RB.inp('pt-code', pt.code, dis + ' placeholder="made for you"')) + '</div>' +
      '<div class="row">' + RB.field('pt-kind', 'Kind', RB.sel('pt-kind', [['bottle', 'Bottle'], ['pouch', 'Pouch'], ['jar', 'Jar'], ['box', 'Box'], ['other', 'Other']], pt.kind, dis)) +
      RB.field('pt-empty', 'Empty bottle / pouch item', RB.sel('pt-empty', empties, pt.packaging_item_id, dis), 'Add it first under Items, kind Packaging.') + '</div>' +
      (isNew ? '' : '<label class="check"><input type="checkbox" id="pt-active"' + (pt.is_active ? ' checked' : '') + dis + '> Active</label>') +
      '<div class="actions">' + (edit ? '<button class="primary" id="pt-save">Save</button>' : '') + '<button data-close>Close</button></div>');
    const b = $('#pt-save', m.el);
    if (b) b.addEventListener('click', async () => {
      try {
        await RB.rpc('rb_save_pack_type', { p: { id: pt.id || null, name: $('#pt-name', m.el).value, code: $('#pt-code', m.el).value,
          kind: $('#pt-kind', m.el).value, packaging_item_id: $('#pt-empty', m.el).value || null,
          is_active: $('#pt-active', m.el) ? $('#pt-active', m.el).checked : true } });
        RB.toast('Pack type saved'); m.close(); done();
      } catch (e) { RB.modalMsg(m, e.message); }
    });
  }

  function productPackModal(pp, d, done) {
    const isNew = !pp, edit = isNew ? RB.has('masters.add') : RB.has('masters.edit'), dis = edit ? '' : ' disabled';
    pp = pp || { is_active: true };
    const products = d.items.filter((i) => (i.kind === 'finished' || (i.kind === 'byproduct' && i.byproduct_use === 'sellable')) && (i.is_active || i.id === pp.item_id));
    const unitOf = Object.fromEntries(d.items.map((i) => [i.id, i.base_unit]));
    const m = RB.modal('<h2>' + (isNew ? 'Add a product pack' : 'Product pack') + '</h2><div class="m-msg"></div>' +
      '<div class="row">' + RB.field('pp-item', 'Product', RB.sel('pp-item', [['', 'Choose…']].concat(products.map((i) => [i.id, i.name])), pp.item_id, dis + (isNew ? '' : ' disabled')), null, true) +
      RB.field('pp-pack', 'Pack', RB.sel('pp-pack', [['', 'Choose…']].concat(d.packTypes.filter((p) => p.is_active || p.id === pp.pack_type_id).map((p) => [p.id, p.name])), pp.pack_type_id, dis), null, true) + '</div>' +
      RB.field('pp-qty', 'One pack holds (<span id="pp-unit">' + esc(unitOf[pp.item_id] || 'g') + '</span>)', RB.inp('pp-qty', pp.net_qty, dis + ' type="number" min="0" step="any"'), 'For example a 200 g bottle may hold 200 g of pickle but only 100 g of chilli powder.', true) +
      '<div class="row">' + RB.field('pp-r', 'Retail price (₹)', RB.inp('pp-r', RB.fromPaise(pp.retail_price_paise), dis + ' inputmode="decimal"')) +
      RB.field('pp-t', 'Trader price (₹)', RB.inp('pp-t', RB.fromPaise(pp.trader_price_paise), dis + ' inputmode="decimal"')) +
      RB.field('pp-o', 'Online price (₹)', RB.inp('pp-o', RB.fromPaise(pp.online_price_paise), dis + ' inputmode="decimal"')) + '</div>' +
      (isNew ? '' : '<label class="check"><input type="checkbox" id="pp-active"' + (pp.is_active ? ' checked' : '') + dis + '> Active</label>') +
      '<div class="actions">' + (edit ? '<button class="primary" id="pp-save">Save</button>' : '') + '<button data-close>Close</button></div>');
    $('#pp-item', m.el).addEventListener('change', (e) => { $('#pp-unit', m.el).textContent = unitOf[e.target.value] || 'g'; });
    const b = $('#pp-save', m.el);
    if (b) b.addEventListener('click', async () => {
      try {
        await RB.rpc('rb_save_product_pack', { p: { id: pp.id || null, item_id: $('#pp-item', m.el).value || null, pack_type_id: $('#pp-pack', m.el).value || null,
          net_qty: $('#pp-qty', m.el).value, retail_price_paise: RB.toPaise($('#pp-r', m.el).value),
          trader_price_paise: RB.toPaise($('#pp-t', m.el).value), online_price_paise: RB.toPaise($('#pp-o', m.el).value),
          is_active: $('#pp-active', m.el) ? $('#pp-active', m.el).checked : true } });
        RB.toast('Saved'); m.close(); done();
      } catch (e) { RB.modalMsg(m, e.message); }
    });
  }

  // ---------- departments ----------
  async function deptsTab(tb) {
    const d = await M.load(['departments', 'deptEvents']);
    const byId = Object.fromEntries(d.departments.map((x) => [x.id, x]));
    tb.innerHTML = '<div class="actions" style="margin:0 0 .75rem">' + (RB.has('masters.add') ? '<button class="primary" id="dp-add">+ Add department</button>' : '') +
      '</div>' +
      '<p class="muted">Every journal line carries a department or cost centre. Renames and merges never rewrite past entries: reports apply them, and each one can be undone. Only a Director or the FC can rename, merge or delete.</p><div id="dp-grid"></div>';
    const rows = d.departments.map((x) => Object.assign({}, x, {
      status: x.merged_into ? 'Merged into ' + (byId[x.merged_into] || {}).code : (x.is_active ? 'Active' : 'Switched off'),
      changes: d.deptEvents.filter((e) => e.dept_id === x.id && !e.undone_at).length,
    }));
    const grid = RB.grid($('#dp-grid', tb), [
      { title: 'Code', field: 'code', width: 90 },
      { title: 'Name for new entries', field: 'name', minWidth: 220, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
      { title: 'First name', field: 'original_name' },
      { title: 'Status', field: 'status', formatter: (c) => { const r = c.getRow().getData(); return r.merged_into ? RB.badge('invited', c.getValue()) : RB.activeBadge(r.is_active); } },
      { title: 'Renames / merges', field: 'changes', hozAlign: 'right', headerFilter: false },
    ], rows);
    grid.on('rowClick', (e, row) => deptModal(byId[row.getData().id], d, () => deptsTab(tb)));
    const a = $('#dp-add', tb);
    if (a) a.addEventListener('click', () => {
      const m = RB.modal('<h2>Add a department</h2><div class="m-msg"></div><div class="row">' +
        RB.field('nd-code', 'Code', RB.inp('nd-code', '', ' placeholder="e.g. CC006"'), 'From the group\'s shared department list.', true) +
        RB.field('nd-name', 'Name', RB.inp('nd-name', ''), null, true) + '</div>' +
        '<div class="actions"><button class="primary" id="nd-go">Add</button><button data-close>Cancel</button></div>');
      $('#nd-go', m.el).addEventListener('click', async () => {
        try { await RB.rpc('rb_add_department', { p_code: $('#nd-code', m.el).value, p_name: $('#nd-name', m.el).value }); RB.toast('Department added'); m.close(); deptsTab(tb); }
        catch (e) { RB.modalMsg(m, e.message); }
      });
    });
  }

  function scopeField(prefix) {
    return '<div class="field"><label>Apply to</label>' +
      '<label class="check"><input type="radio" name="' + prefix + '-scope" value="all" checked> All history (past entries too)</label>' +
      '<label class="check"><input type="radio" name="' + prefix + '-scope" value="date"> Entries from this date onwards: <input type="date" id="' + prefix + '-date" style="width:auto;margin-left:.5rem" value="' + RB.today() + '"></label></div>';
  }
  const scopeDate = (m, prefix) => ($('input[name=' + prefix + '-scope]:checked', m.el).value === 'all' ? null : ($('#' + prefix + '-date', m.el).value || null));

  function deptModal(dp, d, done) {
    const byId = Object.fromEntries(d.departments.map((x) => [x.id, x]));
    const pw = RB.has('power.departments');
    const hist = d.deptEvents.filter((e) => e.dept_id === dp.id || e.into_dept_id === dp.id);
    const open = d.departments.filter((x) => x.id !== dp.id && x.is_active && !x.merged_into);
    const m = RB.modal('<h2>' + esc(dp.code + ' ' + dp.name) + RB.demoBadge(dp) + '</h2><div class="m-msg"></div>' +
      (dp.merged_into ? '<div class="msg info">Merged into ' + esc(byId[dp.merged_into].code + ' ' + byId[dp.merged_into].name) + '. Undo the merge below to open it again.</div>' : '') +
      (pw && !dp.merged_into ? '<section class="card"><h3>Rename</h3><div class="row">' + RB.field('rn-name', 'New name', RB.inp('rn-name', dp.name), null, true) + '</div>' + scopeField('rn') +
        '<button class="primary" id="rn-go">Rename</button></section>' +
        '<section class="card"><h3>Merge into another department</h3><p class="muted">This department closes. Its entries report under the one you choose.</p>' +
        RB.field('mg-into', 'Merge into', RB.sel('mg-into', [['', 'Choose…']].concat(open.map((x) => [x.id, x.code + ' ' + x.name])), '')) + scopeField('mg') +
        '<button id="mg-go">Merge</button></section>' : '') +
      '<h3>History</h3>' + (hist.length ? '<div class="grid-wrap"><table class="ticks" style="min-width:0"><thead><tr><th>When</th><th>Change</th><th>Applies to</th><th></th></tr></thead><tbody>' +
        hist.map((e) => '<tr' + (e.undone_at ? ' style="opacity:.55"' : '') + '><td>' + RB.fmtDateTime(e.created_at) + '</td><td style="text-align:left">' +
          (e.kind === 'rename' ? 'Renamed ' + esc(byId[e.dept_id] ? byId[e.dept_id].code : '') + ' to “' + esc(e.new_name) + '”'
            : esc((byId[e.dept_id] || {}).code) + ' merged into ' + esc((byId[e.into_dept_id] || {}).code)) +
          (e.note ? '<br><span class="muted">' + esc(e.note) + '</span>' : '') + '</td><td>' + (e.effective_from ? 'From ' + RB.fmtDate(e.effective_from) : 'All history') + '</td><td>' +
          (e.undone_at ? 'Undone ' + RB.fmtDate(e.undone_at) : (pw ? '<button data-undo="' + e.id + '">Undo</button>' : '')) + '</td></tr>').join('') +
        '</tbody></table></div>' : '<p class="muted">No renames or merges.</p>') +
      '<div class="actions">' +
      (RB.has('masters.edit') && !dp.merged_into ? '<button id="dp-onoff">' + (dp.is_active ? 'Switch off' : 'Switch back on') + '</button>' : '') +
      (pw ? '<button class="danger" id="dp-del">Delete</button>' : '') + '<button data-close>Close</button></div>', { wide: true });
    const run = async (fn, ok) => { try { await fn(); RB.toast(ok); m.close(); done(); } catch (e) { RB.modalMsg(m, e.message); } };
    const on = (id, fn) => { const b = $(id, m.el); if (b) b.addEventListener('click', fn); };
    on('#rn-go', () => run(() => RB.rpc('rb_rename_department', { p_dept: dp.id, p_name: $('#rn-name', m.el).value, p_from: scopeDate(m, 'rn'), p_note: null }), 'Renamed'));
    on('#mg-go', async () => {
      const into = $('#mg-into', m.el).value;
      if (!into) return RB.modalMsg(m, 'Choose the department to merge into.');
      if (!(await RB.confirm('Merge ' + dp.code + '?', dp.code + ' closes for new entries. You can undo this later.'))) return;
      run(() => RB.rpc('rb_merge_department', { p_from_dept: dp.id, p_into: Number(into), p_from: scopeDate(m, 'mg'), p_note: null }), 'Merged');
    });
    on('#dp-onoff', () => run(() => RB.rpc('rb_set_department_active', { p_dept: dp.id, p_active: !dp.is_active }), dp.is_active ? 'Switched off' : 'Switched back on'));
    on('#dp-del', async () => {
      if (!(await RB.confirm('Delete ' + dp.code + '?', 'Only a department that was never used can be deleted. Otherwise merge it or switch it off.'))) return;
      run(() => RB.rpc('rb_delete_department', { p_dept: dp.id }), 'Deleted');
    });
    $$('[data-undo]', m.el).forEach((b) => b.addEventListener('click', () => run(() => RB.rpc('rb_undo_department_change', { p_event: Number(b.dataset.undo) }), 'Undone')));
  }

  // ---------- units ----------
  async function unitsTab(tb) {
    const d = await M.load(['units']);
    tb.innerHTML = '<div class="actions" style="margin:0 0 .75rem">' + (RB.has('masters.edit') ? '<button class="primary" id="un-add">+ Add unit</button>' : '') + '</div>' +
      '<p class="muted">Stock is kept in grams, millilitres, pieces or boxes. Other units convert to these, e.g. 1 kg = 1000 g.</p><div id="un-grid"></div>';
    const grid = RB.grid($('#un-grid', tb), [
      { title: 'Code', field: 'code', width: 90 },
      { title: 'Name', field: 'name' },
      { title: 'Measures', field: 'dimension', formatter: (c) => DIMS[c.getValue()] },
      { title: 'Equals (base units)', field: 'to_base', hozAlign: 'right' },
    ], d.units, { pagination: false });
    const modal = (u) => {
      const isNew = !u; u = u || { dimension: 'mass', to_base: 1 };
      const m = RB.modal('<h2>' + (isNew ? 'Add a unit' : esc(u.name)) + '</h2><div class="m-msg"></div><div class="row">' +
        RB.field('un-code', 'Code', RB.inp('un-code', u.code, isNew ? ' placeholder="e.g. dozen"' : ' disabled'), null, true) +
        RB.field('un-name', 'Name', RB.inp('un-name', u.name), null, true) + '</div><div class="row">' +
        RB.field('un-dim', 'Measures', RB.sel('un-dim', Object.entries(DIMS), u.dimension)) +
        RB.field('un-base', 'One of these equals (g, ml, pieces or boxes)', RB.inp('un-base', u.to_base, ' type="number" min="0" step="any"')) + '</div>' +
        '<div class="actions"><button class="primary" id="un-save">Save</button><button data-close>Close</button></div>');
      $('#un-save', m.el).addEventListener('click', async () => {
        try { await RB.rpc('rb_save_unit', { p: { code: $('#un-code', m.el).value, name: $('#un-name', m.el).value, dimension: $('#un-dim', m.el).value, to_base: $('#un-base', m.el).value } }); RB.toast('Saved'); m.close(); unitsTab(tb); }
        catch (e) { RB.modalMsg(m, e.message); }
      });
    };
    if (RB.has('masters.edit')) grid.on('rowClick', (e, row) => modal(row.getData()));
    const a = $('#un-add', tb); if (a) a.addEventListener('click', () => modal(null));
  }

  // ===================================================================
  // Customers screen
  // ===================================================================
  const TRADER_LABELS = { phone: 'Phone', address: 'Address', email: 'Email', gstin: 'GSTIN', contact_person: 'Contact person', credit_limit: 'Credit limit', credit_days: 'Credit days' };

  RB.screens.customers = async (body, arg) => {
    const d = await M.load(['customers']);
    let promoOnly = false;
    // On its own screen the buttons go in the heading's second row; inside the Customers tab they sit under the tabs.
    const btns = (RB.has('customers.add') ? '<button class="primary" id="cu-add">+ Add customer</button>' : '') + '<button id="cu-promo">Promotions list</button>';
    const tools = body.id === 'page-body' && $('#page-tools');
    if (tools) tools.innerHTML = btns;
    body.innerHTML = (tools ? '' : '<div class="actions" style="margin:0 0 .75rem">' + btns + '</div>') +
      '<p class="muted">Retail and trader customers. Tap a customer to see or change them. Balances, ledgers and statements are on the Balances and statements tab.</p><div id="cu-grid"></div>';
    const rows = d.customers.map((c) => Object.assign({}, c, { kind_t: CUST_KINDS[c.kind], promo: c.send_promotions ? 'Yes' : '', credit: RB.rupees(c.credit_limit_paise) }));
    const grid = RB.grid($('#cu-grid', body), [
      { title: 'Code', field: 'code', width: 100 },
      { title: 'Name', field: 'name', minWidth: 200, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) + (c.getRow().getData().is_walk_in ? ' ' + RB.badge('protected', 'Standing') : '') },
      { title: 'Type', field: 'kind_t', headerFilter: 'list', headerFilterParams: { values: { '': 'All', Retail: 'Retail', Trader: 'Trader' } } },
      { title: 'Phone', field: 'phone' },
      { title: 'Promotions', field: 'promo', width: 110 },
      { title: 'GSTIN', field: 'gstin' },
      { title: 'Contact', field: 'contact_person' },
      { title: 'Credit limit', field: 'credit', hozAlign: 'right' },
      { title: 'Credit days', field: 'credit_days', hozAlign: 'right' },
      { title: 'Status', field: 'is_active', formatter: (c) => RB.activeBadge(c.getValue()), headerFilter: false },
    ], rows);
    grid.on('rowClick', (e, row) => M.customerModal(d.customers.find((x) => x.id === row.getData().id), () => RB.route()));
    $('#cu-promo').addEventListener('click', (e) => {
      promoOnly = !promoOnly;
      if (promoOnly) grid.setFilter('promo', '=', 'Yes'); else grid.clearFilter();
      e.target.classList.toggle('primary', promoOnly);
      e.target.textContent = promoOnly ? 'Show everyone' : 'Promotions list';
    });
    const a = $('#cu-add'); if (a) a.addEventListener('click', () => M.customerModal(null, () => RB.route()));
    const pick = arg && d.customers.find((x) => String(x.id) === String(arg));  // from Quick search
    if (pick) M.customerModal(pick, () => RB.route());
  };

  // Add or change a customer. done(id) runs after saving. Used by the Sales screen later.
  M.customerModal = async (c, done, defaults) => {
    let req = [];
    try { req = (await RB.select('app_settings', 'trader_required_fields', (q) => q.eq('id', 1).single())).trader_required_fields || []; } catch (e) { /* ignore */ }
    const isNew = !c, edit = isNew ? RB.has('customers.add') : RB.has('customers.edit'), dis = edit ? '' : ' disabled';
    c = c || Object.assign({ kind: 'retail', is_active: true }, defaults || {});
    const money = RB.has('power.see_totals') || RB.has('customers.edit');
    const star = (f) => '<span class="req tr-req" data-req="' + f + '"' + (req.includes(f) ? '' : ' hidden') + '>*</span>';
    const m = RB.modal('<h2>' + (isNew ? 'Add a customer' : esc(c.code + ' ' + c.name)) + RB.demoBadge(c) + '</h2><div class="m-msg"></div>' +
      '<div class="row">' + RB.field('c-kind', 'Type', RB.sel('c-kind', Object.entries(CUST_KINDS), c.kind, dis + (c.is_walk_in ? ' disabled' : '')), null, true) +
      RB.field('c-name', 'Name', RB.inp('c-name', c.name, dis), null, true) + '</div>' +
      '<div class="row"><div class="field"><label for="c-phone">Phone ' + star('phone') + '</label>' + RB.inp('c-phone', c.phone, dis + ' type="tel"') + '</div>' +
      '<div class="field"><label>&nbsp;</label><label class="check"><input type="checkbox" id="c-promo"' + (c.send_promotions ? ' checked' : '') + dis + '> Send promotions (the customer agrees)</label>' +
      '<div class="hint">Only ticked customers appear in the promotions list. Needs a phone number.</div></div></div>' +
      '<div class="field"><label for="c-address">Address ' + star('address') + '</label><textarea id="c-address"' + dis + '>' + esc(c.address || '') + '</textarea></div>' +
      '<div class="row"><div class="field"><label for="c-email">Email ' + star('email') + '</label>' + RB.inp('c-email', c.email, dis + ' type="email"') + '</div>' +
      '<div class="field" data-trader><label for="c-gstin">GSTIN ' + star('gstin') + '</label>' + RB.inp('c-gstin', c.gstin, dis) + '</div></div>' +
      '<div class="row" data-trader><div class="field"><label for="c-contact">Contact person ' + star('contact_person') + '</label>' + RB.inp('c-contact', c.contact_person, dis) + '</div>' +
      RB.field('c-state', 'State code', RB.inp('c-state', c.state_code, dis + ' placeholder="e.g. 27"')) + '</div>' +
      (money ? '<div class="row" data-trader><div class="field"><label for="c-climit">Credit limit (₹) ' + star('credit_limit') + '</label>' + RB.inp('c-climit', RB.fromPaise(c.credit_limit_paise), dis + ' inputmode="decimal"') + '</div>' +
        '<div class="field"><label for="c-cdays">Credit days ' + star('credit_days') + '</label>' + RB.inp('c-cdays', c.credit_days, dis + ' type="number" min="0"') + '</div></div>' : '') +
      RB.field('c-notes', 'Notes', RB.inp('c-notes', c.notes, dis)) +
      (isNew || c.is_walk_in ? '' : '<label class="check"><input type="checkbox" id="c-active"' + (c.is_active ? ' checked' : '') + dis + '> Active</label>') +
      '<p class="muted" id="c-reqnote"></p>' +
      '<div class="actions">' + (edit ? '<button class="primary" id="c-save">Save</button>' : '') + '<button data-close>Close</button></div>', { wide: true });
    const sync = () => {
      const trader = $('#c-kind', m.el).value === 'trader';
      $$('[data-trader]', m.el).forEach((el) => el.classList.toggle('hidden', !trader && !el.querySelector('input').value));
      $$('.tr-req', m.el).forEach((el) => { el.hidden = !(trader && req.includes(el.dataset.req)); });
      $('#c-reqnote', m.el).textContent = trader && req.length ? 'For traders, Settings makes these required: ' + req.map((f) => TRADER_LABELS[f] || f).join(', ') + '.' : '';
    };
    $('#c-kind', m.el).addEventListener('change', sync); sync();
    const b = $('#c-save', m.el);
    if (b) b.addEventListener('click', async () => {
      const v = (id) => ($('#' + id, m.el) ? $('#' + id, m.el).value : '');
      try {
        const p = { id: c.id || null, kind: v('c-kind'), name: v('c-name'), phone: v('c-phone'), send_promotions: $('#c-promo', m.el).checked,
          address: v('c-address'), email: v('c-email'), gstin: v('c-gstin'), contact_person: v('c-contact'), state_code: v('c-state'),
          credit_days: v('c-cdays'), notes: v('c-notes'), is_active: $('#c-active', m.el) ? $('#c-active', m.el).checked : true };
        if ($('#c-climit', m.el)) { p.credit_limit_paise = RB.toPaise(v('c-climit')); p.credit_limit = v('c-climit'); }
        else { p.credit_limit_paise = c.credit_limit_paise; p.credit_limit = c.credit_limit_paise; p.credit_days = c.credit_days; }
        const id = await RB.rpc('rb_save_customer', { p });
        RB.toast('Customer saved'); m.close(); if (done) done(id);
      } catch (e) { RB.modalMsg(m, e.message); }
    });
  };

  // ===================================================================
  // Suppliers screen
  // ===================================================================
  RB.screens.suppliers = async (body, arg) => {
    const d = await M.load(['suppliers']);
    const owed = {};
    if (RB.purchases && (RB.has('purchases.view') || RB.has('suppliers.view'))) {
      try { (await RB.rpc('rb_supplier_balances', { p_as_of: RB.today() })).forEach((b) => { owed[b.supplier_id] = b.balance_paise; }); } catch (e) { /* balances are optional here */ }
    }
    const tools = $('#page-tools');
    if (tools) tools.innerHTML = RB.has('suppliers.add') ? '<button class="primary" id="su-add">+ Add supplier</button>' : '';
    body.innerHTML =
      '<p class="muted">Fishermen, farmers, local shops and companies. Tap a supplier to see or change them, or to open their ledger. Purchases and payments are in the Purchases screen.</p><div id="su-grid"></div>';
    const rows = d.suppliers.map((s) => Object.assign({}, s, { kind_t: SUP_KINDS[s.kind], nobill: s.usually_no_bill ? 'No bill' : '', owed: owed[s.id] == null ? null : owed[s.id] }));
    const grid = RB.grid($('#su-grid', body), [
      { title: 'Code', field: 'code', width: 100 },
      { title: 'Name', field: 'name', minWidth: 220, formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()) },
      { title: 'Kind', field: 'kind_t' },
      { title: 'Phone', field: 'phone' },
      { title: 'Bills', field: 'nobill', width: 90 },
      { title: 'GSTIN', field: 'gstin' },
      { title: 'Credit days', field: 'credit_days', hozAlign: 'right' },
      { title: 'Balance owed', field: 'owed', hozAlign: 'right', headerFilter: false, formatter: (c) => (c.getValue() == null ? '' : RB.rupees(c.getValue())) },
      { title: 'Status', field: 'is_active', formatter: (c) => RB.activeBadge(c.getValue()), headerFilter: false },
    ], rows);
    grid.on('rowClick', (e, row) => M.supplierModal(d.suppliers.find((x) => x.id === row.getData().id), () => RB.route()));
    const a = $('#su-add'); if (a) a.addEventListener('click', () => M.supplierModal(null, () => RB.route()));
    const pick = arg && d.suppliers.find((x) => String(x.id) === String(arg));  // from Quick search
    if (pick) M.supplierModal(pick, () => RB.route());
  };

  // Add or change a supplier. done(id) runs after saving. Used by the Purchase window later.
  M.supplierModal = (s, done, defaults) => {
    const isNew = !s, edit = isNew ? RB.has('suppliers.add') : RB.has('suppliers.edit'), dis = edit ? '' : ' disabled';
    s = s || Object.assign({ kind: 'local', is_active: true }, defaults || {});
    const m = RB.modal('<h2>' + (isNew ? 'Add a supplier' : esc(s.code + ' ' + s.name)) + RB.demoBadge(s) + '</h2><div class="m-msg"></div>' +
      '<div class="row">' + RB.field('s-name', 'Name', RB.inp('s-name', s.name, dis), null, true) +
      RB.field('s-kind', 'Kind', RB.sel('s-kind', Object.entries(SUP_KINDS), s.kind, dis)) + '</div>' +
      '<div class="row">' + RB.field('s-phone', 'Phone', RB.inp('s-phone', s.phone, dis + ' type="tel"')) +
      RB.field('s-contact', 'Contact person', RB.inp('s-contact', s.contact_person, dis)) + '</div>' +
      RB.field('s-address', 'Address', '<textarea id="s-address"' + dis + '>' + esc(s.address || '') + '</textarea>') +
      '<div class="row">' + RB.field('s-email', 'Email', RB.inp('s-email', s.email, dis + ' type="email"')) +
      RB.field('s-gstin', 'GSTIN', RB.inp('s-gstin', s.gstin, dis)) + RB.field('s-state', 'State code', RB.inp('s-state', s.state_code, dis)) + '</div>' +
      '<div class="row">' + RB.field('s-cdays', 'Credit days', RB.inp('s-cdays', s.credit_days, dis + ' type="number" min="0"'), '0 = pays on the spot.') +
      '<div class="field"><label>&nbsp;</label><label class="check"><input type="checkbox" id="s-nobill"' + (s.usually_no_bill ? ' checked' : '') + dis + '> Usually gives no bill (e.g. fishermen)</label></div></div>' +
      RB.field('s-notes', 'Notes', RB.inp('s-notes', s.notes, dis)) +
      (isNew ? '' : '<label class="check"><input type="checkbox" id="s-active"' + (s.is_active ? ' checked' : '') + dis + '> Active</label>') +
      '<div class="actions">' + (edit ? '<button class="primary" id="s-save">Save</button>' : '') +
      (!isNew && RB.purchases && RB.has('purchases.view') ? '<button id="s-ledger">Ledger</button>' : '') + '<button data-close>Close</button></div>', { wide: true });
    const lg = $('#s-ledger', m.el);
    if (lg) lg.addEventListener('click', () => { m.close(); RB.purchases.ledgerModal(s.id, s.name); });
    const b = $('#s-save', m.el);
    if (b) b.addEventListener('click', async () => {
      const v = (id) => $('#' + id, m.el).value;
      try {
        const id = await RB.rpc('rb_save_supplier', { p: { id: s.id || null, name: v('s-name'), kind: v('s-kind'), phone: v('s-phone'),
          contact_person: v('s-contact'), address: v('s-address'), email: v('s-email'), gstin: v('s-gstin'), state_code: v('s-state'),
          credit_days: v('s-cdays'), usually_no_bill: $('#s-nobill', m.el).checked, notes: v('s-notes'),
          is_active: $('#s-active', m.el) ? $('#s-active', m.el).checked : true } });
        RB.toast('Supplier saved'); m.close(); if (done) done(id);
      } catch (e) { RB.modalMsg(m, e.message); }
    });
  };
})();
