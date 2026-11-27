// =====================================================================
// RUCHI BUDS APP · backup.js · Version 1.0 · 27-Nov-2026
// Module 9 screen "Restore a backup" (Settings -> Restore a backup…),
// for Directors and the FC only. Load a backup file (from Settings ->
// Backup now) or a nightly Google Drive backup loaded by the Apps Script,
// see what it holds against the data now, download today's data first,
// then confirm with RESTORE and a reason. The data as it was just before
// the restore is kept, so the restore can be undone the same way.
// =====================================================================
(function () {
  'use strict';
  const RB = window.RB, $ = RB.$, esc = RB.esc;
  const CHUNK = 500;
  const SOURCE = { file: 'Backup file', drive: 'Google Drive (nightly)', undo: 'Undo copy', drill: 'Restore drill' };
  const STATUS = { loading: 'Loading', ready: 'Ready to restore', applied: 'Restored', failed: 'Does not check out', cancelled: 'Set aside' };
  const BADGE = { loading: 'invited', ready: 'protected', applied: 'active', failed: 'locked', cancelled: 'inactive' };
  const HOW = { replace: 'Replaced from the backup', append: 'Backup entries added (never wiped)', keep: 'Kept as it is (set up by the SQL files)',
    missing: 'Not in the backup: kept as it is', skip: 'Not in this version: left out' };
  const num = (n) => (n == null ? '—' : Number(n).toLocaleString('en-IN'));
  const when = (t) => (t ? RB.fmtDateTime(t) : 'date not known');
  const S = {};

  RB.screens.restore = async (body) => {
    if (!RB.has('power.restore')) {
      body.innerHTML = '<div class="msg error">Only a Director or the FC can restore a backup.</div>';
      return;
    }
    body.innerHTML =
      '<div class="msg info">A restore puts every table back as it was when the backup was taken. Everything entered since is replaced. ' +
      'The audit log and the backup log are kept, and the data as it is just before the restore is saved, so a restore can be undone.</div>' +
      '<div class="card"><h2>1. Load a backup</h2>' +
      '<p><b>A backup file</b> (from Settings → Backup now (file for restore)):</p>' +
      '<div class="row" style="align-items:flex-end"><div class="field"><label for="rs-file">Backup file (.json)</label><input type="file" id="rs-file" accept=".json,application/json"></div></div>' +
      '<p><b>A nightly backup from Google Drive:</b> open the Apps Script and run <b>stageLatestBackup</b> (see the setup guide). It appears below within a minute; press <b>Refresh</b>.</p>' +
      '<div id="rs-load"></div></div>' +
      '<div class="card"><h2>2. Backups loaded</h2><div class="actions" style="margin:0 0 .5rem"><button id="rs-refresh">Refresh</button></div><div id="rs-list"></div></div>' +
      '<div id="rs-job"></div>';
    $('#rs-file', body).addEventListener('change', (e) => loadFile(body, e.target.files[0]));
    $('#rs-refresh', body).addEventListener('click', () => drawList(body));
    await drawList(body);
  };

  // ---------- loading a backup file ----------
  async function loadFile(body, file) {
    const box = $('#rs-load', body);
    if (!file) return;
    const say = (cls, t) => { box.innerHTML = '<div class="msg ' + cls + '">' + t + '</div>'; };
    try {
      say('info', 'Reading ' + esc(file.name) + '…');
      let data;
      try { data = JSON.parse(await file.text()); } catch (e) { throw new Error('This file is not a backup file (it cannot be read as JSON).'); }
      if (!data || typeof data.tables !== 'object' || Array.isArray(data.tables)) throw new Error('This file is not a Ruchi Buds backup (it has no tables). Use a file from Settings → Backup now (file for restore).');
      const names = Object.keys(data.tables).filter((t) => Array.isArray(data.tables[t]));
      const counts = Object.fromEntries(names.map((t) => [t, data.tables[t].length]));
      const total = names.reduce((a, t) => a + counts[t], 0);
      const job = await RB.rpc('rb_restore_start', { p: { source: 'file', label: file.name, taken_at: data.taken_at || null, tables: counts } });
      let done = 0;
      for (const t of names) {
        const rows = data.tables[t];
        for (let i = 0, seq = 0; i < rows.length || (i === 0 && seq === 0); i += CHUNK, seq++) {
          await RB.rpc('rb_restore_add', { p_job: job, p_table: t, p_seq: seq, p_rows: rows.slice(i, i + CHUNK) });
          done += Math.min(CHUNK, rows.length - i);
          say('info', 'Loading the backup… ' + esc(t) + ' (' + num(done) + ' of ' + num(total) + ' rows)');
          if (!rows.length) break;
        }
      }
      const c = await RB.rpc('rb_restore_finish', { p_job: job });
      say(c.errors.length ? 'error' : 'info', c.errors.length ? 'The backup does not check out: ' + esc(c.errors[0]) : 'Loaded and checked. See it below.');
      $('#rs-file', body).value = '';
      await drawList(body, job);
    } catch (e) { say('error', esc(e.message)); }
  }

  // ---------- the list ----------
  async function drawList(body, open) {
    const box = $('#rs-list', body);
    try {
      S.jobs = await RB.rpc('rb_restore_list');
    } catch (e) { box.innerHTML = '<div class="msg error">' + esc(e.message) + '</div>'; return; }
    if (!S.jobs.length) { box.innerHTML = '<p class="muted">No backup has been loaded yet.</p>'; $('#rs-job', body).innerHTML = ''; return; }
    box.innerHTML = '<div class="rs-jobs">' + S.jobs.map((j) => '<div class="rs-job"><div class="rs-job-main"><b>' + esc(j.label) + '</b>' +
      '<small>Taken ' + when(j.taken_at) + ' · ' + esc(SOURCE[j.source] || j.source) + '</small>' +
      '<div>' + RB.badge(BADGE[j.status] || 'inactive', STATUS[j.status] || j.status) +
      (j.status === 'applied' ? ' <span class="muted">' + when(j.applied_at) + (j.applied_by ? ' by ' + esc(j.applied_by) : '') + '</span>' : '') +
      (j.status !== 'applied' && j.detail ? ' <span class="muted">' + esc(j.detail) + '</span>' : '') + '</div></div>' +
      (j.status === 'ready' || j.status === 'failed' ? '<button data-job="' + j.id + '">Open</button>' : '') + '</div>').join('') + '</div>';
    box.querySelectorAll('[data-job]').forEach((b) => b.addEventListener('click', () => drawJob(body, Number(b.dataset.job))));
    const first = Number(open) || (S.jobs.find((j) => j.status === 'ready' && j.source !== 'undo') || {}).id;
    if (first && S.jobs.some((j) => j.id === first && (j.status === 'ready' || j.status === 'failed'))) drawJob(body, first);
    else $('#rs-job', body).innerHTML = '';
  }

  // ---------- one backup: what it holds, and the restore ----------
  function drawJob(body, id) {
    const j = S.jobs.find((x) => x.id === id), box = $('#rs-job', body);
    if (!j) return;
    const c = j.checked || { tables: [], errors: [], warnings: [] };
    const changed = c.tables.filter((t) => t.how !== 'keep' || t.backup);
    box.innerHTML = '<div class="card"><h2>3. ' + (j.source === 'undo' ? 'Undo: ' : 'Restore: ') + esc(j.label) + '</h2>' +
      '<div class="row facts">' +
      '<div><small>Taken</small><b>' + when(j.taken_at) + '</b></div>' +
      '<div><small>From</small><b>' + esc(SOURCE[j.source] || j.source) + '</b></div>' +
      '<div><small>Rows to restore</small><b>' + num(c.rows) + '</b></div>' +
      '<div><small>Loaded by</small><b>' + esc(j.created_by || 'Apps Script') + '</b></div></div>' +
      c.errors.map((e) => '<div class="msg error">' + esc(e) + '</div>').join('') +
      c.warnings.map((w) => '<div class="msg info">' + esc(w) + '</div>').join('') +
      '<details><summary>Every table: rows in the backup and now</summary><div class="grid-wrap"><table class="ticks" style="min-width:0"><thead><tr><th>Table</th><th class="n">In the backup</th><th class="n">Now</th><th>What happens</th></tr></thead><tbody>' +
      changed.map((t) => '<tr><td>' + esc(t.table) + '</td><td class="n">' + num(t.backup) + '</td><td class="n">' + num(t.now) + '</td><td>' + esc(HOW[t.how] || t.how) + '</td></tr>').join('') +
      '</tbody></table></div></details>' +
      (j.status === 'ready' ? '<h3>Before you restore</h3>' +
        '<ol class="rs-steps"><li>Ask everyone to stop entering for a few minutes.</li>' +
        '<li>Download today\'s data, in case it is needed later: <button id="rs-today">Download today\'s data</button> <span id="rs-today-msg" class="muted"></span></li>' +
        '<li>Give the reason and press <b>Restore this backup</b>. You will be asked to type RESTORE.</li></ol>' +
        '<div class="field"><label for="rs-why">Reason (kept in the audit log)</label><input id="rs-why" placeholder="e.g. wrong entries posted on 20-Nov by mistake"></div>' +
        '<label class="check"><input type="checkbox" id="rs-have"> I have today\'s data downloaded (or do not need it)</label>' +
        '<div class="actions"><button class="danger" id="rs-go" disabled>Restore this backup</button><button id="rs-cancel">Set this backup aside</button></div><div id="rs-msg"></div>'
        : '<div class="actions"><button id="rs-cancel">Set this backup aside</button></div>') + '</div>';
    const have = $('#rs-have', box), go = $('#rs-go', box);
    if (have) have.addEventListener('change', () => { go.disabled = !have.checked; });
    const today = $('#rs-today', box);
    if (today) today.addEventListener('click', async () => {
      const m = $('#rs-today-msg', box);
      try {
        today.disabled = true;
        const r = await RB.backupDownload(false, (t, n) => { m.textContent = 'Taking backup… ' + n + ' rows'; });
        await RB.rpc('rb_log_backup', { p_kind: 'manual', p_status: 'ok', p_tables: r.tables.length, p_rows: r.rows, p_detail: 'JSON download before a restore' });
        m.textContent = '✓ Downloaded (' + num(r.rows) + ' rows).'; have.checked = true; go.disabled = false;
      } catch (e) { m.textContent = e.message; } finally { today.disabled = false; }
    });
    if (go) go.addEventListener('click', () => restore(body, j));
    $('#rs-cancel', box).addEventListener('click', async () => {
      if (!(await RB.confirm('Set this backup aside?', 'It is removed from the list of backups that can be restored. Nothing in the books changes.'))) return;
      try { await RB.rpc('rb_restore_cancel', { p_job: j.id }); RB.toast('Set aside'); drawList(body); } catch (e) { RB.toast(e.message, true); }
    });
  }

  async function restore(body, j) {
    const msg = $('#rs-msg', body), why = $('#rs-why', body).value.trim();
    if (why.length < 5) { msg.innerHTML = '<div class="msg error">Please give the reason for the restore.</div>'; return; }
    const word = await RB.confirmTyped('Restore "' + j.label + '"?',
      'Every table goes back to how it was on <b>' + esc(when(j.taken_at)) + '</b>. Everything entered since is replaced. The data as it is now is kept as an undo copy.', 'RESTORE');
    if (!word) return;
    try {
      msg.innerHTML = '<div class="msg info">Restoring… please wait and do not close this page.</div>';
      await RB.rpc('rb_restore_approve', { p_job: j.id, p_confirm: word, p_reason: why });
      const r = await RB.rpc('rb_restore_apply', { p_job: j.id });
      msg.innerHTML = '';
      const m = RB.modal('<h2>Restored</h2><p>' + num(r.tables) + ' tables and ' + num(r.rows) + ' rows were put back as they were on ' + esc(when(j.taken_at)) + '.</p>' +
        '<p>The data as it was just before is kept as an undo copy at the top of the list. Ask everyone to close the app and open it again.</p>' +
        '<div class="actions"><button class="primary" id="rs-reload">Reload the app</button></div>');
      $('#rs-reload', m.el).addEventListener('click', () => { location.hash = '#/settings'; location.reload(); });
    } catch (e) {
      const slow = /timeout|canceling statement/i.test(e.message);
      msg.innerHTML = '<div class="msg error">' + (slow
        ? 'The restore took too long for the app and nothing was changed. Within the next hour, open the Apps Script and run <b>applyRestore</b>: it finishes this confirmed restore.'
        : esc(e.message)) + '</div>';
      drawList(body, j.id);
    }
  }
})();
