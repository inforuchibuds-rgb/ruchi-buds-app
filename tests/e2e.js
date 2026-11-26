// End-to-end walk through module 1 against tests/mock-supabase.js.
// Usage: node tests/e2e.js <screenshot dir>
'use strict';
const { chromium } = require('playwright');
const OUT = process.argv[2] || '.';
const BASE = 'http://localhost:8787/';

(async () => {
  const browser = await chromium.launch();
  const errors = [];
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 860 }, acceptDownloads: true });
  const page = await ctx.newPage(); global.__page = page;
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  page.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
  const shot = (n) => page.screenshot({ path: OUT + '/' + n + '.png', fullPage: true });
  const step = (t) => console.log('• ' + t);
  const expectText = async (t) => { await page.getByText(t, { exact: false }).first().waitFor({ timeout: 5000 }); };

  await page.goto(BASE);
  await expectText('Sign in'); await shot('01-login'); step('login screen');

  // Stranger cannot create a login
  await page.click('#to-first');
  await page.fill('#li-email', 'stranger@example.com'); await page.fill('#li-pass', 'abcdefgh1'); await page.fill('#li-pass2', 'abcdefgh1');
  await page.click('button[type=submit]');
  await expectText('has not been invited'); step('stranger blocked');

  // DS first-time set-up
  await page.fill('#li-email', 'info.ruchibuds@gmail.com'); await page.fill('#li-pass', 'DS-secret-123'); await page.fill('#li-pass2', 'DS-secret-123');
  await page.click('button[type=submit]');
  await expectText('Hello, DS'); await shot('02-home-ds'); step('DS set password and sees home');

  // Users list
  await page.click('a[href="#/users"]'); await expectText('Demo Director Two'); await shot('03-users'); step('users list');
  await page.click('#u-add');
  await page.fill('#au-email', 'staff.one@example.com'); await page.fill('#au-name', 'Asha Staff'); await page.fill('#au-short', 'AS');
  await page.selectOption('#au-cat', { label: 'Staff' }); await page.fill('#au-lp', '2027-02-28');
  await page.click('#au button[type=submit]'); await expectText('User added'); await shot('04-user-added');
  await page.click('#au-ok'); await expectText('Asha Staff'); step('invited Asha (Staff)');

  // Category grid: tick "See money totals" off/on for Staff
  await page.click('button[data-tab=cats]'); await expectText('Always full access');
  await page.selectOption('#c-pick', { index: 7 });
  await expectText('Started from the Staff template');
  await page.check('#c-grid input[data-perm="stock.view"]'); await expectText('Saved');
  await shot('05-grid-staff'); step('ticked Stock view for Staff');
  await page.click('#c-hist'); await expectText('Ticked Stock · View for Staff'); await shot('06-history');
  await page.click('.modal [data-close]'); step('history shows the change');

  // Settings
  await page.goto(BASE + '#/settings'); await expectText('Firm details');
  await page.fill('#st-firm_reg_no', 'PF-12345'); await page.click('#st-save'); await expectText('Settings saved');
  await shot('07-settings'); step('settings saved');
  const dl = page.waitForEvent('download');
  await page.click('#bk-json'); const d = await dl; await d.saveAs(OUT + '/backup.json');
  await expectText('Backup downloaded'); step('manual backup downloaded: ' + d.suggestedFilename());

  // Audit
  await page.goto(BASE + '#/audit'); await expectText('Firm reg no: (blank) → PF-12345'); await shot('08-audit'); step('audit log shows settings change');

  // Sign out, Asha sets password and sees the Staff menu
  await page.click('#btn-signout'); await expectText('Sign in');
  await page.click('#to-first');
  await page.fill('#li-email', 'staff.one@example.com'); await page.fill('#li-pass', 'asha-pass-1'); await page.fill('#li-pass2', 'asha-pass-1');
  await page.click('button[type=submit]'); await expectText('Hello, Asha');
  const tiles = await page.$$eval('.tile', (els) => els.map((e) => e.textContent.trim()));
  console.log('  Asha tiles:', tiles.join(' | '));
  if (tiles.some((t) => /Users|Settings|Audit/.test(t))) throw new Error('Staff should not see Users/Settings/Audit');
  await page.goto(BASE + '#/users'); await expectText('You do not have access'); step('Staff blocked from Users');

  // Phone view
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(BASE + '#/'); await expectText('Hello, Asha'); await shot('09-phone-home-staff');
  // Wrong passwords lock Asha
  await page.click('#btn-signout'); await expectText('Sign in');
  for (let i = 0; i < 5; i++) { await page.fill('#li-email', 'staff.one@example.com'); await page.fill('#li-pass', 'wrong-pass'); await page.click('button[type=submit]'); await expectText('Wrong email or password'); }
  await page.fill('#li-pass', 'asha-pass-1'); await page.click('button[type=submit]'); await expectText('locked'); await shot('10-phone-locked'); step('Asha locked after 5 wrong passwords');

  // DS unlocks and gives Asha a temporary password
  await page.fill('#li-email', 'info.ruchibuds@gmail.com'); await page.fill('#li-pass', 'DS-secret-123'); await page.click('button[type=submit]');
  await expectText('Hello, DS');
  await page.goto(BASE + '#/users'); await page.getByText('Asha Staff').first().click();
  await page.click('#um-unlock'); await expectText('Unlocked');
  await page.getByText('Asha Staff').first().click(); await page.click('#um-reset');
  const temp = await page.inputValue('#rp-pw'); await page.click('#rp-go'); await expectText('Temporary password set');
  await shot('11-phone-users'); step('DS unlocked Asha and set temp password ' + temp);
  await page.click('#btn-signout');
  await page.fill('#li-email', 'staff.one@example.com'); await page.fill('#li-pass', temp); await page.click('button[type=submit]');
  await expectText('Choose a new password'); await shot('12-phone-forced-change');
  await page.fill('#pw1', 'asha-new-pass'); await page.fill('#pw2', 'asha-new-pass'); await page.click('#pw-form button[type=submit]');
  await expectText('Hello, Asha'); step('Asha forced to choose a new password');

  // Remove demo data as DS
  await page.click('#btn-signout');
  await page.fill('#li-email', 'info.ruchibuds@gmail.com'); await page.fill('#li-pass', 'DS-secret-123'); await page.click('button[type=submit]');
  await expectText('Hello, DS');
  await page.setViewportSize({ width: 1280, height: 860 });
  await page.goto(BASE + '#/settings'); await expectText('are 10 DEMO users');
  await page.click('#dm-go'); await page.fill('#cf-word', 'REMOVE DEMO'); await page.click('#cf-yes'); await expectText('DEMO records removed');
  await expectText('are 0 DEMO users'); step('demo data removed');

  console.log(errors.length ? 'BROWSER ERRORS:\n' + errors.join('\n') : 'No browser errors');
  await browser.close();
})().catch(async (e) => { console.error('E2E FAILED:', e.message); try { console.error('APP TEXT:', JSON.stringify(await global.__page.innerText('#app'))); await global.__page.screenshot({ path: OUT + '/failure.png' }); } catch (x) {} process.exit(1); });
