// =====================================================================
// RUCHI BUDS APP · users.js · Version 1.1 · 26-Nov-2026
// Users, categories with the screen x action tick grid, per-user ticks,
// password resets and unlocks, and the audit log screen.
// =====================================================================
(function () {
  'use strict';
  const RB = window.RB, $ = RB.$, $$ = RB.$$, esc = RB.esc;
  const ACTIONS = [['view', 'View'], ['add', 'Add'], ['edit', 'Edit'], ['approve', 'Approve'], ['delete', 'Delete'], ['margin', 'See margin']];
  const STATUS = { active: 'Active', invited: 'Invited', locked: 'Locked', inactive: 'Switched off' };

  async function loadCatalogue() {
    const [screens, powers, categories, access] = await Promise.all([
      RB.loadScreens(),
      RB.select('powers', '*', (q) => q.order('sort')),
      RB.select('user_categories', '*', (q) => q.order('id')),
      RB.select('category_access', 'category_id,perm'),
    ]);
    const byCat = {};
    access.forEach((a) => { (byCat[a.category_id] = byCat[a.category_id] || new Set()).add(a.perm); });
    categories.forEach((c) => { c.perms = byCat[c.id] || new Set(); });
    return { screens, powers, categories };
  }

  // ===================================================================
  // Users screen
  // ===================================================================
  RB.screens.users = async (body) => {
    const tabs = [['list', 'Users'], ['cats', 'Categories and access']];
    if (RB.has('power.reset_passwords')) tabs.push(['resets', 'Password approvals']);
    body.innerHTML = '<div class="tabs">' + tabs.map(([k, t]) => '<button data-tab="' + k + '">' + t + '</button>').join('') + '</div><div id="tab-body"></div>';
    const show = async (k) => {
      $$('.tabs button', body).forEach((b) => b.classList.toggle('on', b.dataset.tab === k));
      const tb = $('#tab-body', body);
      tb.innerHTML = '<p class="muted">Loading…</p>';
      try { await ({ list: usersTab, cats: categoriesTab, resets: resetsTab })[k](tb); }
      catch (e) { tb.innerHTML = '<div class="msg error">' + esc(e.message) + '</div>'; }
    };
    $$('.tabs button', body).forEach((b) => b.addEventListener('click', () => show(b.dataset.tab)));
    show('list');
  };

  async function usersTab(tb) {
    const [cat, users] = await Promise.all([
      loadCatalogue(),
      RB.select('app_users', '*', (q) => q.order('created_at')),
    ]);
    const catName = Object.fromEntries(cat.categories.map((c) => [c.id, c.name]));
    tb.innerHTML =
      '<div class="actions" style="margin:0 0 .75rem">' +
      (RB.has('users.add') ? '<button class="primary" id="u-add">+ Add user</button>' : '') +
      '<button id="u-xls">Download to Excel</button></div>' +
      '<p class="muted">Tap a person to see or change their details and access.</p><div id="u-grid"></div>';
    const rows = users.map((u) => Object.assign({}, u, { category: catName[u.category_id] }));
    const grid = RB.grid($('#u-grid', tb), [
      { title: 'Name', field: 'full_name', formatter: (c) => esc(c.getValue()) + RB.demoBadge(c.getRow().getData()), minWidth: 170 },
      { title: 'Short', field: 'short_name', width: 80 },
      { title: 'Email', field: 'email' },
      { title: 'Category', field: 'category' },
      { title: 'Status', field: 'status', formatter: (c) => RB.badge(c.getValue(), STATUS[c.getValue()]),
        headerFilter: 'list', headerFilterParams: { values: { '': 'All', active: 'Active', invited: 'Invited', locked: 'Locked', inactive: 'Switched off' } } },
      { title: 'Learning phase ends', field: 'learning_phase_end', formatter: (c) => RB.fmtDate(c.getValue()), sorter: 'string' },
      { title: 'Last sign-in', field: 'last_login_at', formatter: (c) => RB.fmtDateTime(c.getValue()), headerFilter: false },
    ], rows, { selectableRows: false });
    grid.on('rowClick', (e, row) => userModal(row.getData(), cat, () => usersTab(tb)));
    $('#u-xls', tb).addEventListener('click', () => RB.downloadExcel(grid, 'Users'));
    if ($('#u-add', tb)) $('#u-add', tb).addEventListener('click', () => addUserModal(cat, () => usersTab(tb)));
  }

  function categoryOptions(cat, selected) {
    return cat.categories.map((c) => '<option value="' + c.id + '"' + (c.id === selected ? ' selected' : '') + '>' +
      esc(c.name) + (c.is_demo ? ' (DEMO)' : '') + '</option>').join('');
  }

  function addUserModal(cat, done) {
    const lp = RB.has('power.manage_access');
    const m = RB.modal('<h2>Add a user</h2><form id="au"><div id="au-msg"></div>' +
      '<div class="field"><label>Email <span class="req">*</span></label><input id="au-email" type="email" required></div>' +
      '<div class="row"><div class="field"><label>Full name <span class="req">*</span></label><input id="au-name" required></div>' +
      '<div class="field"><label>Short name or initials</label><input id="au-short" maxlength="12"></div></div>' +
      '<div class="row"><div class="field"><label>Phone</label><input id="au-phone" type="tel"></div>' +
      '<div class="field"><label>Category <span class="req">*</span></label><select id="au-cat">' + categoryOptions(cat, 8) + '</select></div></div>' +
      (lp ? '<div class="field"><label>Learning phase ends</label><input id="au-lp" type="date"><div class="hint">Until this date a Director or the FC can fully delete this person\'s posted entries. After it, entries can only be reversed.</div></div>' : '') +
      '<div class="actions"><button class="primary" type="submit">Add user</button><button type="button" data-close>Cancel</button></div></form>');
    $('#au', m.el).addEventListener('submit', async (e) => {
      e.preventDefault();
      try {
        await RB.rpc('rb_invite_user', {
          p_email: $('#au-email', m.el).value, p_full_name: $('#au-name', m.el).value,
          p_short_name: $('#au-short', m.el).value, p_phone: $('#au-phone', m.el).value,
          p_category: Number($('#au-cat', m.el).value),
          p_learning_phase_end: lp ? ($('#au-lp', m.el).value || null) : null,
        });
        const email = $('#au-email', m.el).value.trim();
        m.el.querySelector('.modal').innerHTML = '<h2>User added</h2><div class="msg ok">Now tell them:</div>' +
          '<ol><li>Open the Ruchi Buds app link.</li><li>Tap <b>First time here? Set up your password</b>.</li>' +
          '<li>Use the email <b>' + esc(email) + '</b> and choose their own password.</li></ol>' +
          '<p class="muted">Nobody else ever needs to know their password.</p><div class="actions"><button class="primary" id="au-ok">Done</button></div>';
        $('#au-ok', m.el).addEventListener('click', () => { m.close(); done(); });
      } catch (err) { $('#au-msg', m.el).innerHTML = '<div class="msg error">' + esc(err.message) + '</div>'; }
    });
  }

  function randomPassword() {
    const words = ['mango', 'chilli', 'ginger', 'garlic', 'pickle', 'tamarind', 'pepper', 'jaggery', 'cumin', 'lemon'];
    const a = new Uint32Array(3); crypto.getRandomValues(a);
    return words[a[0] % words.length] + '-' + words[a[1] % words.length] + '-' + (100 + (a[2] % 900));
  }

  function userModal(u, cat, refresh) {
    const me = RB.profile.id, self = u.id === me;
    const c = cat.categories.find((x) => x.id === u.category_id) || {};
    const canEdit = RB.has('users.edit') && !self;
    const lp = RB.has('power.manage_access');
    const m = RB.modal('<h2>' + esc(u.full_name) + RB.demoBadge(u) + ' ' + RB.badge(u.status, STATUS[u.status]) + '</h2>' +
      '<div id="um-msg"></div>' +
      (u.status === 'locked' ? '<div class="msg error">Locked since ' + RB.fmtDateTime(u.locked_at) + ': ' + esc(u.locked_reason || '') + '</div>' : '') +
      (u.status === 'invited' ? '<div class="msg info">Has not set up a password yet.' + (u.is_demo ? ' DEMO users are examples and cannot sign in.' : '') + '</div>' : '') +
      '<div class="field"><label>Email</label><input value="' + esc(u.email) + '" disabled></div>' +
      '<div class="row"><div class="field"><label>Full name</label><input id="um-name" value="' + esc(u.full_name) + '"' + (canEdit ? '' : ' disabled') + '></div>' +
      '<div class="field"><label>Short name</label><input id="um-short" value="' + esc(u.short_name || '') + '"' + (canEdit ? '' : ' disabled') + '></div></div>' +
      '<div class="row"><div class="field"><label>Phone</label><input id="um-phone" value="' + esc(u.phone || '') + '"' + (canEdit ? '' : ' disabled') + '></div>' +
      '<div class="field"><label>Category</label><select id="um-cat"' + (canEdit ? '' : ' disabled') + '>' + categoryOptions(cat, u.category_id) + '</select></div></div>' +
      '<div class="field"><label>Learning phase ends</label><input id="um-lp" type="date" value="' + esc(u.learning_phase_end || '') + '"' + (canEdit && lp ? '' : ' disabled') + '>' +
      '<div class="hint">' + (u.learning_phase_end ? 'Shown as ' + RB.fmtDate(u.learning_phase_end) + '. ' : '') + 'Only a Director or the FC can change this.</div></div>' +
      '<p class="muted">Added ' + RB.fmtDateTime(u.created_at) + (u.last_login_at ? ' · last signed in ' + RB.fmtDateTime(u.last_login_at) : '') + '</p>' +
      '<div class="actions">' +
      (canEdit ? '<button class="primary" id="um-save">Save changes</button>' : '') +
      '<button id="um-preview">What can they see?</button>' +
      (lp && !self && !c.is_protected ? '<button id="um-access">Change this person\'s ticks</button>' : '') +
      (u.status === 'locked' && RB.has('power.unlock_users') ? '<button id="um-unlock">Unlock</button>' : '') +
      (u.auth_id && !self && RB.has('power.reset_passwords') ? '<button id="um-reset">Give a temporary password</button>' : '') +
      (canEdit && u.status !== 'inactive' && u.status !== 'invited' ? '<button class="danger" id="um-off">Switch off</button>' : '') +
      (canEdit && u.status === 'inactive' ? '<button id="um-on">Switch back on</button>' : '') +
      (canEdit && u.status === 'invited' ? '<button class="danger" id="um-del">Delete invitation</button>' : '') +
      '<button data-close>Close</button></div>', { wide: true });
    const msg = (t, ok) => { $('#um-msg', m.el).innerHTML = '<div class="msg ' + (ok ? 'ok' : 'error') + '">' + t + '</div>'; };
    const run = async (fn, okText) => {
      try { await fn(); RB.toast(okText); m.close(); refresh(); } catch (e) { msg(esc(e.message)); }
    };
    const on = (id, fn) => { const b = $(id, m.el); if (b) b.addEventListener('click', fn); };
    on('#um-save', () => run(() => RB.rpc('rb_update_user', {
      p_user: u.id, p_full_name: $('#um-name', m.el).value, p_short_name: $('#um-short', m.el).value,
      p_phone: $('#um-phone', m.el).value, p_category: Number($('#um-cat', m.el).value),
      p_learning_phase_end: $('#um-lp', m.el).value || null,
    }), 'Saved'));
    on('#um-unlock', () => run(() => RB.rpc('rb_unlock_user', { p_user: u.id }), 'Unlocked'));
    on('#um-off', async () => {
      if (await RB.confirm('Switch off ' + u.full_name + '?', 'They will not be able to use the app. Their past entries stay. You can switch them back on later.'))
        run(() => RB.rpc('rb_set_user_active', { p_user: u.id, p_active: false }), 'Switched off');
    });
    on('#um-on', () => run(() => RB.rpc('rb_set_user_active', { p_user: u.id, p_active: true }), 'Switched back on'));
    on('#um-del', async () => {
      if (await RB.confirm('Delete this invitation?', 'Use this when the email was wrong. The person never signed in, so nothing else is affected.'))
        run(() => RB.rpc('rb_delete_invite', { p_user: u.id }), 'Invitation deleted');
    });
    on('#um-reset', () => {
      const pw = randomPassword();
      const r = RB.modal('<h2>Temporary password for ' + esc(u.full_name) + '</h2>' +
        (c.is_protected ? '<div class="msg info">This is a ' + esc(c.name) + ' account, so a second Director or the FC must approve before it works.</div>' : '') +
        '<div class="field"><label>Temporary password</label><input id="rp-pw" value="' + pw + '"><div class="hint">Tell it to them in person or by phone. They must choose their own password when they next sign in.</div></div>' +
        '<div id="rp-msg"></div><div class="actions"><button class="primary" id="rp-go">Set temporary password</button><button data-close>Cancel</button></div>');
      $('#rp-go', r.el).addEventListener('click', async () => {
        try {
          const res = await RB.rpc('rb_reset_password', { p_user: u.id, p_temp_password: $('#rp-pw', r.el).value });
          r.close(); m.close();
          RB.toast(res === 'pending' ? 'Waiting for a second Director or the FC to approve' : 'Temporary password set');
          refresh();
        } catch (e) { $('#rp-msg', r.el).innerHTML = '<div class="msg error">' + esc(e.message) + '</div>'; }
      });
    });
    on('#um-preview', async () => {
      try {
        const perms = new Set((await RB.rpc('rb_preview_user_perms', { p_user: u.id })) || []);
        const scr = cat.screens.filter((s) => s.in_menu && perms.has(s.code + '.view'));
        const pw = cat.powers.filter((p) => perms.has('power.' + p.code));
        RB.modal('<h2>What ' + esc(u.full_name) + ' can see</h2>' +
          '<h3>Home menu</h3><p>' + (scr.length ? scr.map((s) => esc(s.name) + (s.available ? '' : ' <span class="muted">(module ' + s.module + ')</span>')).join(', ') : 'Nothing yet') + '</p>' +
          '<h3>Margins</h3><p>' + (cat.screens.some((s) => perms.has(s.code + '.margin')) ? 'Can see margins on: ' + cat.screens.filter((s) => perms.has(s.code + '.margin')).map((s) => esc(s.name)).join(', ') : 'Cannot see margins') + '</p>' +
          '<h3>Special rights</h3><p>' + (pw.length ? pw.map((p) => esc(p.name)).join(', ') : 'None') + '</p>' +
          '<div class="actions"><button data-close class="primary">Close</button></div>');
      } catch (e) { msg(esc(e.message)); }
    });
    on('#um-access', () => { m.close(); userAccessModal(u, c, cat, refresh); });
  }

  // ---------- the tick grid, used for categories and for single users ----------
  function tickTable(cat, state, opts) {
    // state(perm) -> { checked, cls }
    const head = '<tr><th>Screen</th>' + ACTIONS.map((a) => '<th>' + a[1] + '</th>').join('') + '</tr>';
    const rows = cat.screens.map((s) => '<tr><th scope="row">' + esc(s.name) +
      (s.available ? '' : ' <span class="soon">module ' + s.module + '</span>') + '</th>' +
      ACTIONS.map((a) => {
        const perm = s.code + '.' + a[0], st = state(perm);
        return '<td class="' + (st.cls || '') + '"><input type="checkbox" data-perm="' + perm + '"' +
          (st.checked ? ' checked' : '') + (opts.disabled ? ' disabled' : '') +
          ' aria-label="' + esc(s.name + ' ' + a[1]) + '"></td>';
      }).join('') + '</tr>').join('');
    const powers = cat.powers.map((p) => {
      const perm = 'power.' + p.code, st = state(perm);
      return '<tr><th scope="row" colspan="6">' + esc(p.name) + '<br><span class="soon">' + esc(p.description) + '</span></th>' +
        '<td class="' + (st.cls || '') + '"><input type="checkbox" data-perm="' + perm + '"' + (st.checked ? ' checked' : '') +
        (opts.disabled ? ' disabled' : '') + ' aria-label="' + esc(p.name) + '"></td></tr>';
    }).join('');
    return '<div class="grid-wrap"><table class="ticks"><thead>' + head + '</thead><tbody>' + rows +
      '<tr><th colspan="7" style="background:var(--cream)">Special rights</th></tr>' + powers + '</tbody></table></div>';
  }

  function userAccessModal(u, c, cat, refresh) {
    let overrides = {};
    const m = RB.modal('<h2>Ticks for ' + esc(u.full_name) + '</h2><p class="muted">Starts from the <b>' + esc(c.name) +
      '</b> category. Green = extra access for this person only. Red = taken away for this person only. Each tick saves straight away.</p><div id="ua-body">Loading…</div>' +
      '<div class="actions"><button data-close class="primary">Done</button></div>', { wide: true });
    const draw = () => {
      $('#ua-body', m.el).innerHTML = tickTable(cat, (perm) => {
        const base = c.perms.has(perm), o = overrides[perm];
        const checked = o === undefined ? base : o;
        return { checked, cls: o === undefined ? '' : (o ? 'over-plus' : 'over-minus') };
      }, {});
      $$('input[data-perm]', m.el).forEach((box) => box.addEventListener('change', async () => {
        const perm = box.dataset.perm, base = c.perms.has(perm);
        const val = box.checked === base ? null : box.checked;
        try {
          await RB.rpc('rb_set_user_access', { p_user: u.id, p_perm: perm, p_allowed: val });
          if (val === null) delete overrides[perm]; else overrides[perm] = val;
          RB.toast('Saved'); draw();
        } catch (e) { box.checked = !box.checked; RB.toast(e.message, true); }
      }));
    };
    RB.select('user_access_overrides', 'perm,allowed', (q) => q.eq('user_id', u.id)).then((rows) => {
      rows.forEach((r) => { overrides[r.perm] = r.allowed; }); draw();
    }).catch((e) => { $('#ua-body', m.el).innerHTML = '<div class="msg error">' + esc(e.message) + '</div>'; });
    m.el.addEventListener('click', (e) => { if (e.target.hasAttribute('data-close')) refresh(); });
  }

  // ---------- categories ----------
  async function categoriesTab(tb, selectId) {
    const cat = await loadCatalogue();
    const users = await RB.select('app_users', 'category_id');
    const count = {}; users.forEach((u) => { count[u.category_id] = (count[u.category_id] || 0) + 1; });
    const manage = RB.has('power.manage_access');
    let current = cat.categories.find((c) => c.id === selectId) || cat.categories[0];
    tb.innerHTML = '<div class="row" style="align-items:flex-end">' +
      '<div class="field" style="flex:2 1 260px;margin:0"><label for="c-pick">Category</label><select id="c-pick">' +
      cat.categories.map((c) => '<option value="' + c.id + '">' + esc(c.name) + (c.is_demo ? ' (DEMO)' : '') + ' · ' + (count[c.id] || 0) + ' user(s)</option>').join('') +
      '</select></div><div class="actions" style="flex:3 1 300px;margin:0">' +
      (manage ? '<button id="c-new">+ New category</button><button id="c-ren">Rename</button><button class="danger" id="c-del">Remove</button>' : '') +
      '<button id="c-hist">Change history</button></div></div><div id="c-info" style="margin:.75rem 0"></div><div id="c-grid"></div>';
    const draw = () => {
      $('#c-pick', tb).value = current.id;
      $('#c-info', tb).innerHTML = (current.is_protected
        ? RB.badge('protected', 'Always full access') + ' <span class="muted">Director and Financial Controller always have every tick, so the firm can never be locked out of its own app.</span>'
        : '<span class="muted">' + (current.description ? esc(current.description) + '. ' : '') + 'Started from the ' + esc(current.template) + ' template.' +
          (manage ? ' Each tick saves straight away and is recorded in the change history.' : '') + '</span>');
      $('#c-grid', tb).innerHTML = tickTable(cat, (perm) => ({ checked: current.is_protected || current.perms.has(perm) }),
        { disabled: !manage || current.is_protected });
      $$('#c-grid input[data-perm]', tb).forEach((box) => box.addEventListener('change', async () => {
        try {
          await RB.rpc('rb_set_category_access', { p_category: current.id, p_perm: box.dataset.perm, p_allowed: box.checked });
          if (box.checked) current.perms.add(box.dataset.perm); else current.perms.delete(box.dataset.perm);
          RB.toast('Saved');
        } catch (e) { box.checked = !box.checked; RB.toast(e.message, true); }
      }));
    };
    $('#c-pick', tb).addEventListener('change', (e) => { current = cat.categories.find((c) => c.id === Number(e.target.value)); draw(); });
    const on = (id, fn) => { const b = $(id, tb); if (b) b.addEventListener('click', fn); };
    on('#c-new', () => {
      const m = RB.modal('<h2>New category</h2><div id="cn-msg"></div><div class="field"><label>Name</label><input id="cn-name" placeholder="e.g. Packing staff"></div>' +
        '<div class="field"><label>Start from template</label><select id="cn-tpl">' +
        ['Director', 'FC', 'Accountant', 'Manager', 'AR', 'AP', 'Sales', 'Staff'].map((t) => '<option' + (t === 'Staff' ? ' selected' : '') + '>' + t + '</option>').join('') +
        '</select><div class="hint">You can change any tick afterwards. A copy of Director or FC is not protected and can be changed.</div></div>' +
        '<div class="field"><label>Description</label><input id="cn-desc"></div>' +
        '<div class="actions"><button class="primary" id="cn-go">Create</button><button data-close>Cancel</button></div>');
      $('#cn-go', m.el).addEventListener('click', async () => {
        try {
          const id = await RB.rpc('rb_create_category', { p_name: $('#cn-name', m.el).value, p_template: $('#cn-tpl', m.el).value, p_description: $('#cn-desc', m.el).value || null });
          m.close(); RB.toast('Category created'); categoriesTab(tb, id);
        } catch (e) { $('#cn-msg', m.el).innerHTML = '<div class="msg error">' + esc(e.message) + '</div>'; }
      });
    });
    on('#c-ren', () => {
      const m = RB.modal('<h2>Rename category</h2><div id="cr-msg"></div><div class="field"><label>Name</label><input id="cr-name" value="' + esc(current.name) + '"></div>' +
        '<div class="field"><label>Description</label><input id="cr-desc" value="' + esc(current.description || '') + '"></div>' +
        '<p class="muted">For example rename Director to Partner. The people in it keep their access.</p>' +
        '<div class="actions"><button class="primary" id="cr-go">Save</button><button data-close>Cancel</button></div>');
      $('#cr-go', m.el).addEventListener('click', async () => {
        try { await RB.rpc('rb_rename_category', { p_category: current.id, p_name: $('#cr-name', m.el).value, p_description: $('#cr-desc', m.el).value || null }); m.close(); RB.toast('Renamed'); categoriesTab(tb, current.id); }
        catch (e) { $('#cr-msg', m.el).innerHTML = '<div class="msg error">' + esc(e.message) + '</div>'; }
      });
    });
    on('#c-del', async () => {
      if (!(await RB.confirm('Remove ' + current.name + '?', 'Only a category nobody uses can be removed.'))) return;
      try { await RB.rpc('rb_delete_category', { p_category: current.id }); RB.toast('Removed'); categoriesTab(tb); }
      catch (e) { RB.toast(e.message, true); }
    });
    on('#c-hist', async () => {
      try {
        const rows = await RB.select('audit_log', '*', (q) => q.in('table_name', ['category_access', 'user_categories', 'user_access_overrides'])
          .order('at', { ascending: false }).limit(500));
        const permName = (p) => {
          if (!p) return '';
          if (p.startsWith('power.')) { const pw = cat.powers.find((x) => 'power.' + x.code === p); return pw ? pw.name : p; }
          const [s, a] = p.split('.'); const sc = cat.screens.find((x) => x.code === s); const ac = ACTIONS.find((x) => x[0] === a);
          return (sc ? sc.name : s) + ' · ' + (ac ? ac[1] : a);
        };
        const lines = rows.map((r) => {
          const d = r.new_data || r.old_data || {};
          let what = '';
          if (r.table_name === 'category_access') {
            const c = cat.categories.find((x) => x.id === d.category_id);
            what = (r.action === 'INSERT' ? 'Ticked ' : 'Unticked ') + permName(d.perm) + ' for ' + (c ? c.name : 'a removed category');
          } else if (r.table_name === 'user_access_overrides') {
            what = (r.action === 'DELETE' ? 'Back to category default: ' : (d.allowed ? 'Extra for one person: ' : 'Taken away for one person: ')) + permName(d.perm);
          } else {
            what = { INSERT: 'Created category ', UPDATE: 'Changed category ', DELETE: 'Removed category ' }[r.action] + (d.name || '');
          }
          return { at: r.at, who: r.user_name, what };
        });
        const m = RB.modal('<h2>Access change history</h2><div id="ch-grid"></div><div class="actions"><button id="ch-xls">Download to Excel</button><button data-close class="primary">Close</button></div>', { wide: true });
        const g = RB.grid($('#ch-grid', m.el), [
          { title: 'When', field: 'at', formatter: (c) => RB.fmtDateTime(c.getValue()), headerFilter: false, width: 150 },
          { title: 'Who', field: 'who', width: 100 },
          { title: 'What changed', field: 'what' },
        ], lines, { height: '60vh', pagination: false });
        $('#ch-xls', m.el).addEventListener('click', () => RB.downloadExcel(g, 'Access changes'));
      } catch (e) { RB.toast(e.message, true); }
    });
    draw();
  }

  // ---------- password approvals ----------
  async function resetsTab(tb) {
    const [reqs, users] = await Promise.all([
      RB.select('password_reset_requests', 'id,target_user_id,requested_by,requested_at,status,decided_by,decided_at', (q) => q.order('requested_at', { ascending: false }).limit(50)),
      RB.select('app_users', 'id,full_name'),
    ]);
    const name = Object.fromEntries(users.map((u) => [u.id, u.full_name]));
    const me = RB.profile.id;
    tb.innerHTML = '<p class="muted">A temporary password for a Director or the FC only works after a second Director or the FC approves it here.</p>' +
      (reqs.length ? '<div class="grid-wrap"><table class="ticks"><thead><tr><th>For</th><th>Asked by</th><th>When</th><th>Status</th><th></th></tr></thead><tbody>' +
        reqs.map((r) => '<tr><td>' + esc(name[r.target_user_id]) + '</td><td>' + esc(name[r.requested_by]) + '</td><td>' + RB.fmtDateTime(r.requested_at) +
          '</td><td>' + esc(r.status) + (r.decided_by ? ' by ' + esc(name[r.decided_by]) : '') + '</td><td>' +
          (r.status === 'pending' && r.requested_by !== me && r.target_user_id !== me
            ? '<button class="primary" data-ok="' + r.id + '">Approve</button> <button data-no="' + r.id + '">Reject</button>'
            : (r.status === 'pending' ? '<span class="muted">Needs someone else</span>' : '')) + '</td></tr>').join('') +
        '</tbody></table></div>' : '<p>No requests.</p>');
    $$('[data-ok],[data-no]', tb).forEach((b) => b.addEventListener('click', async () => {
      try {
        await RB.rpc('rb_decide_password_reset', { p_request: Number(b.dataset.ok || b.dataset.no), p_approve: !!b.dataset.ok });
        RB.toast(b.dataset.ok ? 'Approved: the temporary password now works' : 'Rejected'); resetsTab(tb);
      } catch (e) { RB.toast(e.message, true); }
    }));
  }

  // ===================================================================
  // Audit log screen
  // ===================================================================
  const TABLE_NAMES = {
    app_users: 'Users', user_categories: 'Categories', category_access: 'Access grid',
    user_access_overrides: 'Per-user ticks', app_settings: 'Settings', password_reset_requests: 'Password resets',
    // module 2
    units: 'Units', items: 'Items', pack_types: 'Pack types', product_packs: 'Product packs', customers: 'Customers',
    suppliers: 'Suppliers', departments: 'Departments', dept_events: 'Department renames and merges', accounts: 'Chart of accounts',
    posting_rules: 'Posting rules', periods: 'Month lock', entities: 'Group entities', journals: 'Journals',
  };
  const ACTION_NAMES = {
    INSERT: 'Added', UPDATE: 'Changed', DELETE: 'Deleted', LOGIN: 'Signed in', LOGIN_FAILED: 'Wrong password',
    PASSWORD_RESET: 'Password reset', PASSWORD_CHANGED: 'Changed own password', REMOVE_DEMO: 'Removed demo data',
    POST_JOURNAL: 'Posted journal', REVERSE_JOURNAL: 'Reversed journal', REVERSE_AND_COPY: 'Reversed and copied journal (to correct)', DELETE_DRAFT: 'Deleted draft journal', IMPORT_COA: 'Imported chart of accounts',
  };

  function summarise(r) {
    if (r.action === 'UPDATE' && r.old_data && r.new_data) {
      const skip = ['updated_at', 'updated_by', 'changed_at', 'changed_by'];
      const ch = Object.keys(r.new_data).filter((k) => !skip.includes(k) && JSON.stringify(r.old_data[k]) !== JSON.stringify(r.new_data[k]));
      return ch.map((k) => k === 'wordmark_url' ? 'word mark changed' : k.replace(/_/g, ' ') + ': ' + fmtVal(r.old_data[k]) + ' → ' + fmtVal(r.new_data[k])).join('; ');
    }
    const d = r.new_data || r.old_data;
    if (d) return [d.journal_no, d.code, d.full_name || d.name || d.new_name || d.perm || d.email || d.narration].filter(Boolean).join(' ') || r.note || '';
    return r.note || '';
  }
  function fmtVal(v) {
    if (v === null || v === undefined || v === '') return '(blank)';
    if (typeof v === 'string' && /^\d{4}-\d{2}-\d{2}/.test(v)) return v.length > 10 ? RB.fmtDateTime(v) : RB.fmtDate(v);
    if (typeof v === 'object') return JSON.stringify(v);
    return String(v);
  }

  RB.screens.audit = async (body) => {
    body.innerHTML = '<div class="row" style="align-items:flex-end">' +
      '<div class="field"><label>From</label><input type="date" id="al-from"></div>' +
      '<div class="field"><label>To</label><input type="date" id="al-to"></div>' +
      '<div class="actions" style="margin-bottom:.85rem"><button class="primary" id="al-go">Show</button><button id="al-xls">Download to Excel</button></div></div>' +
      '<p class="muted">Every change, sign-in and wrong password is kept here. Nobody can edit or delete these lines. Tap a line for full details.</p><div id="al-grid"></div>';
    const d = new Date(); d.setDate(d.getDate() - 30);
    $('#al-from', body).value = d.toISOString().slice(0, 10);
    $('#al-to', body).value = RB.today();
    let grid;
    const load = async () => {
      const from = $('#al-from', body).value, to = $('#al-to', body).value;
      const rows = await RB.select('audit_log', '*', (q) => {
        q = q.order('at', { ascending: false }).limit(5000);
        if (from) q = q.gte('at', from + 'T00:00:00');
        if (to) q = q.lte('at', to + 'T23:59:59');
        return q;
      });
      const data = rows.map((r) => Object.assign({}, r, {
        what: TABLE_NAMES[r.table_name] || r.table_name || '',
        act: ACTION_NAMES[r.action] || r.action,
        detail: summarise(r) + (r.note && (r.old_data || r.new_data) ? ' · ' + r.note : ''),
      }));
      if (grid) grid.destroy();
      grid = RB.grid($('#al-grid', body), [
        { title: 'When', field: 'at', formatter: (c) => RB.fmtDateTime(c.getValue()), headerFilter: false, width: 150 },
        { title: 'Who', field: 'user_name', width: 100 },
        { title: 'Action', field: 'act', width: 150 },
        { title: 'Area', field: 'what', width: 140 },
        { title: 'Details', field: 'detail', minWidth: 260 },
      ], data);
      grid.on('rowClick', (e, row) => {
        const r = row.getData();
        RB.modal('<h2>' + esc(r.act) + ' · ' + esc(r.what) + '</h2><p>' + RB.fmtDateTime(r.at) + ' by ' + esc(r.user_name) + '</p>' +
          (r.note ? '<p>' + esc(r.note) + '</p>' : '') +
          (r.old_data ? '<h3>Before</h3><pre style="white-space:pre-wrap;font-size:.8rem">' + esc(JSON.stringify(r.old_data, null, 1)) + '</pre>' : '') +
          (r.new_data ? '<h3>After</h3><pre style="white-space:pre-wrap;font-size:.8rem">' + esc(JSON.stringify(r.new_data, null, 1)) + '</pre>' : '') +
          '<div class="actions"><button data-close class="primary">Close</button></div>', { wide: true });
      });
    };
    $('#al-go', body).addEventListener('click', () => load().catch((e) => RB.toast(e.message, true)));
    $('#al-xls', body).addEventListener('click', () => grid && RB.downloadExcel(grid, 'Audit log'));
    await load();
  };
})();
