/**
 * =====================================================================
 * RUCHI BUDS APP · Code.gs · Version 1.1 · 27-Nov-2026
 * One Google Apps Script for:
 *   - nightlyBackup(): copies every table to a dated folder in Google
 *     Drive ("Ruchi Buds Backups/2026-11-26") and keeps the last 30 days.
 *   - keepAwake(): a small daily read so the free Supabase project never
 *     pauses after 7 quiet days.
 *   - weeklySheetsCopy(): every Monday, copies the reporting data
 *     (accounts, monthly balances, sales, purchases, expenses, loans) to
 *     the Google Sheet "Ruchi Buds Reporting" that feeds Looker Studio.
 * Module 9 later adds the restore.
 *
 * Set-up (once): Project Settings -> Script Properties, add
 *   SUPABASE_URL          your Project URL
 *   SUPABASE_SERVICE_KEY  the secret key, sb_secret_... (keep it secret:
 *                         it lives only here, never in the app's files)
 *   ALERT_EMAIL           optional: who gets an email if a backup fails
 *   REPORT_SHEET_ID       optional: the reporting sheet to fill. Left out,
 *                         the first copy makes one and remembers it.
 * Then run setupTriggers() once and allow the permissions it asks for.
 * =====================================================================
 */

var BACKUP_FOLDER_NAME = 'Ruchi Buds Backups';
var KEEP_DAYS = 30;
var PAGE = 1000;

function config_() {
  var p = PropertiesService.getScriptProperties();
  var url = (p.getProperty('SUPABASE_URL') || '').replace(/\/+$/, '');
  var key = p.getProperty('SUPABASE_SERVICE_KEY') || '';
  if (!url || !key) throw new Error('Add SUPABASE_URL and SUPABASE_SERVICE_KEY in Project Settings -> Script Properties.');
  return { url: url, key: key, alert: p.getProperty('ALERT_EMAIL') || Session.getEffectiveUser().getEmail() };
}

/** Calls a database function (rb_...) and returns its result. */
function rpc_(name, args) {
  var c = config_();
  var res = UrlFetchApp.fetch(c.url + '/rest/v1/rpc/' + name, {
    method: 'post',
    contentType: 'application/json',
    // New-style secret keys (sb_secret_...) go in the apikey header only; old JWT keys also need Authorization.
    headers: /^eyJ/.test(c.key) ? { apikey: c.key, Authorization: 'Bearer ' + c.key } : { apikey: c.key },
    payload: JSON.stringify(args || {}),
    muteHttpExceptions: true
  });
  var code = res.getResponseCode(), text = res.getContentText();
  if (code >= 300) throw new Error(name + ' failed (' + code + '): ' + text.slice(0, 300));
  return text ? JSON.parse(text) : null;
}

/** Daily keep-awake ping. */
function keepAwake() {
  try {
    var at = rpc_('rb_ping', {});
    Logger.log('Database is awake: ' + at);
  } catch (e) {
    notify_('Ruchi Buds: keep-awake ping failed', e.message);
    throw e;
  }
}

/** Nightly backup of every table to Google Drive. */
function nightlyBackup() {
  var started = new Date();
  var tz = Session.getScriptTimeZone();
  var day = Utilities.formatDate(started, tz, 'yyyy-MM-dd');
  var root = getOrCreateFolder_(DriveApp.getRootFolder(), BACKUP_FOLDER_NAME);
  var old = root.getFoldersByName(day);
  while (old.hasNext()) old.next().setTrashed(true);   // re-running the same day replaces that day's copy
  var folder = root.createFolder(day);
  var totalRows = 0, tables = [];
  try {
    tables = rpc_('rb_backup_tables', {});
    var manifest = { app: 'Ruchi Buds', taken_at: started.toISOString(), tables: {} };
    tables.forEach(function (t) {
      var rows = [];
      for (var off = 0; ; off += PAGE) {
        var page = rpc_('rb_backup_rows', { p_table: t, p_offset: off, p_limit: PAGE });
        rows = rows.concat(page);
        if (page.length < PAGE) break;
      }
      folder.createFile(t + '.json', JSON.stringify(rows), 'application/json');
      manifest.tables[t] = rows.length;
      totalRows += rows.length;
    });
    folder.createFile('_manifest.json', JSON.stringify(manifest, null, 1), 'application/json');
    removeOldBackups_(root);
    rpc_('rb_log_backup', { p_kind: 'nightly', p_status: 'ok', p_tables: tables.length, p_rows: totalRows,
                            p_detail: 'Drive folder ' + BACKUP_FOLDER_NAME + '/' + day });
    Logger.log('Backup done: ' + tables.length + ' tables, ' + totalRows + ' rows into ' + day);
  } catch (e) {
    try { rpc_('rb_log_backup', { p_kind: 'nightly', p_status: 'failed', p_tables: tables.length, p_rows: totalRows, p_detail: e.message }); } catch (x) {}
    notify_('Ruchi Buds: nightly backup FAILED', 'The backup on ' + day + ' failed:\n\n' + e.message +
            '\n\nOpen the Apps Script, check the Script Properties, and run nightlyBackup by hand.');
    throw e;
  }
}

/**
 * Weekly copy of the reporting data to Google Sheets, one tab per dataset.
 * Each run replaces the tabs, so the sheet always matches the app.
 * Amounts are in rupees; DEMO rows are marked in the is_demo column.
 */
function weeklySheetsCopy() {
  var started = new Date(), totalRows = 0, sets = [];
  try {
    var ss = reportSheet_();
    sets = rpc_('rb_sheets_datasets', {});
    var counts = {};
    sets.forEach(function (name) {
      var rows = [];
      for (var off = 0; ; off += PAGE) {
        var page = rpc_('rb_sheets_rows', { p_name: name, p_offset: off, p_limit: PAGE });
        rows = rows.concat(page);
        if (page.length < PAGE) break;
      }
      writeTab_(ss, name, rows);
      counts[name] = rows.length;
      totalRows += rows.length;
    });
    var about = [['Ruchi Buds reporting data'], ['Copied at', started],
                 ['Made by the weekly Apps Script copy. Do not type in these tabs: the next copy replaces them.'], [''], ['Tab', 'Rows']];
    sets.forEach(function (n) { about.push([n, counts[n]]); });
    var a = ss.getSheetByName('_about') || ss.insertSheet('_about', 0);
    a.clear();
    about.forEach(function (r, i) { a.getRange(i + 1, 1, 1, r.length).setValues([r]); });
    var first = ss.getSheets()[0];
    if (first.getName() === 'Sheet1' && first.getLastRow() === 0) ss.deleteSheet(first);
    rpc_('rb_set_report_sheet', { p_url: ss.getUrl() });
    rpc_('rb_log_backup', { p_kind: 'sheets', p_status: 'ok', p_tables: sets.length, p_rows: totalRows,
                            p_detail: 'Google Sheet ' + ss.getName() });
    Logger.log('Sheets copy done: ' + sets.length + ' tabs, ' + totalRows + ' rows. ' + ss.getUrl());
  } catch (e) {
    try { rpc_('rb_log_backup', { p_kind: 'sheets', p_status: 'failed', p_tables: sets.length, p_rows: totalRows, p_detail: e.message }); } catch (x) {}
    notify_('Ruchi Buds: weekly Google Sheets copy FAILED', 'The copy failed:\n\n' + e.message +
            '\n\nOpen the Apps Script, check the Script Properties, and run weeklySheetsCopy by hand.');
    throw e;
  }
}

/** The reporting spreadsheet: REPORT_SHEET_ID, or a new one (remembered). */
function reportSheet_() {
  var p = PropertiesService.getScriptProperties();
  var id = p.getProperty('REPORT_SHEET_ID');
  if (id) return SpreadsheetApp.openById(id);
  var ss = SpreadsheetApp.create('Ruchi Buds Reporting');
  p.setProperty('REPORT_SHEET_ID', ss.getId());
  return ss;
}

/** Replaces one tab with the rows (objects), header from the first row's keys. */
function writeTab_(ss, name, rows) {
  var sh = ss.getSheetByName(name) || ss.insertSheet(name);
  sh.clear();
  if (!rows.length) { sh.getRange(1, 1).setValue('(no rows)'); return; }
  var head = Object.keys(rows[0]);
  var data = [head].concat(rows.map(function (r) {
    return head.map(function (k) {
      var v = r[k];
      if (v === null || v === undefined) return '';
      if (typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v)) return new Date(v + 'T00:00:00');   // a real date for Looker
      if (typeof v === 'object') return JSON.stringify(v);
      return v;
    });
  }));
  for (var i = 0; i < data.length; i += 5000) {
    var part = data.slice(i, i + 5000);
    sh.getRange(i + 1, 1, part.length, head.length).setValues(part);
  }
  sh.setFrozenRows(1);
  sh.getRange(1, 1, 1, head.length).setFontWeight('bold');
}

/** Keeps the newest KEEP_DAYS daily folders and bins the rest. */
function removeOldBackups_(root) {
  var cutoff = new Date(Date.now() - KEEP_DAYS * 86400000);
  var tz = Session.getScriptTimeZone();
  var cut = Utilities.formatDate(cutoff, tz, 'yyyy-MM-dd');
  var it = root.getFolders();
  while (it.hasNext()) {
    var f = it.next();
    if (/^\d{4}-\d{2}-\d{2}$/.test(f.getName()) && f.getName() < cut) f.setTrashed(true);
  }
}

function getOrCreateFolder_(parent, name) {
  var it = parent.getFoldersByName(name);
  return it.hasNext() ? it.next() : parent.createFolder(name);
}

function notify_(subject, body) {
  try { MailApp.sendEmail(config_().alert, subject, body); } catch (e) { Logger.log('Could not send alert: ' + e.message); }
}

/**
 * Run once. Creates the timers (India time):
 *   02:00-03:00 nightly backup, 06:00-07:00 keep-awake ping,
 *   Mondays 04:00-05:00 the weekly Google Sheets copy.
 * Running it again replaces the timers, so it is safe to repeat.
 */
function setupTriggers() {
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (['nightlyBackup', 'keepAwake', 'weeklySheetsCopy'].indexOf(t.getHandlerFunction()) >= 0) ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger('nightlyBackup').timeBased().everyDays(1).atHour(2).inTimezone('Asia/Kolkata').create();
  ScriptApp.newTrigger('keepAwake').timeBased().everyDays(1).atHour(6).inTimezone('Asia/Kolkata').create();
  ScriptApp.newTrigger('weeklySheetsCopy').timeBased().onWeekDay(ScriptApp.WeekDay.MONDAY).atHour(4).inTimezone('Asia/Kolkata').create();
  keepAwake();
  Logger.log('Timers set. The first backup runs tonight between 2 and 3 AM. Run nightlyBackup and weeklySheetsCopy now to test them.');
}
