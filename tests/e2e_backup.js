// End-to-end walk through module 9 against tests/mock-supabase.js,
// on a fresh database with sql/01 to sql/09 loaded.
// Usage: node tests/e2e_backup.js <screenshot dir>
// Needs psql on the PATH to change the data between backup and restore.
'use strict';
const { chromium } = require('playwright');
const { execSync } = require('child_process');
const fs = require('fs');
const OUT = process.argv[2] || '.';
const BASE = 'http://localhost:8787/';
const DB = process.env.PGDATABASE || 'rbtest';
const sql = (q) => execSync('psql -h /var/tmp/pg -p 5433 -U postgres -d ' + DB + ' -Atc ' + JSON.stringify(q)).toString().trim();

(async () => {
  const browser = await chromium.launch();
  const errors = [];
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 860 }, acceptDownloads: true });
  const page = await ctx.newPage(); global.__page = page;
  const watch = (p) => {
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
    p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push('console: ' + m.text()); });
    p.on('dialog', (d) => { errors.push('dialog: ' + d.message()); d.dismiss(); });
  };
  watch(page);
  const shot = (n, p) => (p || page).screenshot({ path: OUT + '/' + n + '.png', fullPage: true });
  const step = (t) => console.log('• ' + t);
  const see = async (t, p) => { await (p || page).getByText(t, { exact: false }).first().waitFor({ timeout: 15000 }); };
  const opened = async (p) => { await (p || page).locator('.modal').last().waitFor(); await (p || page).waitForTimeout(300); };
  const modal = (p) => (p || page).locator('.modal').last();
  const signIn = async (p, email, pass) => {
    await p.goto(BASE); await see('Sign in', p); await p.click('#to-first');
    await p.fill('#li-email', email); await p.fill('#li-pass', pass); await p.fill('#li-pass2', pass);
    await p.click('button[type=submit]'); await p.locator('.menu').waitFor();
  };

  // DS takes a backup file from Settings
  await signIn(page, 'info.ruchibuds@gmail.com', 'DS-secret-123');
  await page.goto(BASE + '#/settings'); await see('Backups and keep-awake'); await see('Last restore drill');
  await see('Restore a backup…');
  const [dl] = await Promise.all([page.waitForEvent('download', { timeout: 60000 }), page.click('#bk-json')]);
  const file = OUT + '/' + dl.suggestedFilename(); await dl.saveAs(file);
  const bk = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (!bk.tables || !bk.tables.journals || bk.tables.restore_jobs) throw new Error('Backup file is not as expected');
  step('backup file downloaded from Settings (' + Object.keys(bk.tables).length + ' tables)');

  // The data changes after the backup
  const before = sql("select firm_name || '|' || (select count(*) from customers) from app_settings");
  sql("update app_settings set firm_name = 'Changed after backup'");
  step('data changed after the backup (firm name)');

  // Restore screen: load the file
  await page.click('a[href="#/restore"]'); await see('Load a backup');
  await page.setInputFiles('#rs-file', file);
  await see('Loaded and checked'); await see('Ready to restore'); await see('Rows to restore');
  await shot('b01-backup-loaded');
  step('backup file loaded and checked: shown as ready to restore');

  // Restore: download today's data, reason, RESTORE
  if (!(await page.locator('#rs-go').isDisabled())) throw new Error('Restore button should wait for today\'s data');
  const [dl2] = await Promise.all([page.waitForEvent('download', { timeout: 60000 }), page.click('#rs-today')]);
  await see('Downloaded ('); if (await page.locator('#rs-go').isDisabled()) throw new Error('Restore button still disabled after the download');
  step('today\'s data downloaded first (' + dl2.suggestedFilename() + ')');
  await page.click('#rs-go'); await see('Please give the reason');
  await page.fill('#rs-why', 'Testing the restore'); await page.click('#rs-go'); await opened();
  await shot('b02-confirm');
  await modal().locator('#cf-word').fill('RESTORE'); await modal().locator('#cf-yes').click();
  await see('Restored'); await see('undo copy'); await shot('b03-restored');
  const after = sql("select firm_name || '|' || (select count(*) from customers) from app_settings");
  if (after !== before) throw new Error('After the restore: ' + after + ', expected ' + before);
  step('restored: the data is back as it was in the backup');
  await modal().locator('#rs-reload').click(); await page.waitForTimeout(1500); await page.locator('.menu, h1').first().waitFor();

  // The undo copy and the logs
  await page.goto(BASE + '#/restore'); await see('Backups loaded'); await see('Undo copy'); await see('Restored');
  await shot('b04-list-with-undo');
  if (sql("select count(*) from backup_log where kind = 'restore' and status = 'ok'") !== '1') throw new Error('Restore not in the backup log');
  if (sql("select count(*) from audit_log where action = 'restore' and note = 'Testing the restore'") !== '1') throw new Error('Restore not in the audit log');
  await page.goto(BASE + '#/settings'); await see('Last restore'); step('restore shown in Settings, the backup log and the audit log; undo copy listed');

  // A file that is not a backup
  await page.goto(BASE + '#/restore'); await see('Load a backup');
  const junk = OUT + '/not-a-backup.json'; fs.writeFileSync(junk, '{"hello": 1}');
  await page.setInputFiles('#rs-file', junk); await see('not a Ruchi Buds backup');
  step('a file that is not a backup is refused');

  // The Accountant can take backups but not restore
  const ctx3 = await browser.newContext({ viewport: { width: 390, height: 844 } }); const ac = await ctx3.newPage(); watch(ac);
  await signIn(ac, 'demo.accounts@example.com', 'Acc-secret-1');
  await ac.goto(BASE + '#/settings'); await see('Backups and keep-awake', ac);
  if (await ac.locator('a[href="#/restore"]').count()) throw new Error('Accountant sees Restore a backup');
  await ac.goto(BASE + '#/restore'); await ac.waitForTimeout(1500);
  if (await ac.locator('#rs-file').count()) throw new Error('Accountant can open the Restore screen');
  step('the Accountant cannot restore');
  await ctx3.close();

  // Phone view of the restore screen
  await page.setViewportSize({ width: 390, height: 844 }); await page.goto(BASE + '#/restore'); await see('Backups loaded');
  await shot('b05-phone');
  const wide = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 2);
  if (wide) errors.push('layout: the restore screen scrolls sideways on a phone');
  step('restore screen on a phone');

  console.log(errors.length ? 'BROWSER ERRORS:\n' + errors.join('\n') : 'No browser errors');
  await browser.close();
  if (errors.length) process.exit(1);
})().catch(async (e) => { console.error('E2E FAILED:', e.message); try { console.error('APP TEXT:', JSON.stringify((await global.__page.innerText('body')).slice(0, 1500))); await global.__page.screenshot({ path: OUT + '/failure.png' }); } catch (x) {} process.exit(1); });
