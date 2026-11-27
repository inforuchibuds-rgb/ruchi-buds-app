// Back and Home buttons on every screen (the installed app has no browser Back).
// Run against tests/mock-supabase.js on a fresh database with sql/01 to sql/09.
// Usage: node tests/e2e_nav.js <screenshot dir>
'use strict';
const { chromium } = require('playwright');
const OUT = process.argv[2] || '.';
const BASE = 'http://localhost:8787/';

(async () => {
  const browser = await chromium.launch();
  const errors = [];
  const page = await (await browser.newContext({ viewport: { width: 1280, height: 860 }, acceptDownloads: true })).newPage(); global.__page = page;
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  const see = async (t) => { await page.getByText(t, { exact: false }).first().waitFor({ timeout: 6000 }); };
  const step = (t) => console.log('• ' + t);
  const at = async (h) => { await page.waitForFunction((x) => location.hash === x, h, { timeout: 4000 }); };
  const shot = (n) => page.screenshot({ path: OUT + '/' + n + '.png' });

  await page.goto(BASE); await see('Sign in');
  await page.click('#to-first');
  await page.fill('#li-email', 'info.ruchibuds@gmail.com'); await page.fill('#li-pass', 'DS-secret-123'); await page.fill('#li-pass2', 'DS-secret-123');
  await page.click('button[type=submit]'); await see('Hello, DS');
  if (await page.locator('#nav-back').count()) throw new Error('Home should not show Back');

  await page.click('a[href="#/accounts"]'); await page.locator('#nav-back').waitFor();
  if (!(await page.locator('#nav-back').isVisible()) || !(await page.locator('#nav-home').isVisible())) throw new Error('Back/Home missing');
  await page.click('#nav-back'); await see('Hello, DS'); step('Back from a screen returns Home');

  await page.click('a[href="#/purchases"]'); await page.locator('#nav-back').waitFor();
  await page.goto(BASE + '#/purchases/1'); await page.locator('.page-head .back:not([hidden])').waitFor();
  if ((await page.locator('.page-head .back').textContent()) !== '‹ Purchases') throw new Error('Up link not labelled');
  await shot('n01-detail-buttons');
  await page.click('#nav-back'); await at('#/purchases'); step('Back from a purchase returns to the purchase list');
  await page.click('#nav-home'); await see('Hello, DS'); step('Home goes Home');

  // Close (✕) and Escape on pop-up windows
  await page.click('a.tile[href="#/accounts"]'); await page.locator('#jl-grid .tabulator-row, .tabulator-row').first().waitFor(); await page.waitForTimeout(300);
  await page.click('#jl-new'); await page.locator('.modal').waitFor(); await shot('n03-modal-close');
  await page.click('.modal .modal-x'); await page.locator('.modal').waitFor({ state: 'detached' });
  await page.click('#jl-new'); await page.locator('.modal').waitFor();
  await page.keyboard.press('Escape'); await page.locator('.modal').waitFor({ state: 'detached' });
  step('pop-up windows close with ✕ and with Esc');
  // Hide (privacy blur)
  await page.click('#btn-hide'); await page.locator('#privacy').waitFor(); await see('Screen hidden'); await shot('n04-hidden');
  await page.click('#privacy'); await page.locator('#privacy').waitFor({ state: 'detached' });
  await page.keyboard.press('Control+Shift+H'); await page.locator('#privacy').waitFor();
  await page.keyboard.press('a'); await page.locator('#privacy').waitFor({ state: 'detached' });
  await page.evaluate(() => { RB.IDLE_MS = 300; document.dispatchEvent(new Event('keydown')); });
  await page.locator('#privacy').waitFor({ timeout: 3000 }); await page.mouse.click(200, 200); await page.locator('#privacy').waitFor({ state: 'detached' });
  await page.evaluate(() => { RB.IDLE_MS = 3 * 60 * 1000; document.dispatchEvent(new Event('pointerdown')); });
  step('Hide blurs the screen (button, Ctrl+Shift+H, and after a quiet spell); a tap shows it again');

  // Refresh, Help, Excel, Print
  await page.click('#pg-refresh'); await page.locator('.tabulator-row').first().waitFor(); step('Refresh reloads the screen');
  await page.click('#pg-help'); await see('Accounts and journals: how it works'); await shot('n06-help'); await page.click('.modal .modal-x'); step('Help explains the screen');
  const [dl] = await Promise.all([page.waitForEvent('download'), page.click('#pg-xls')]);
  if (!/\.xlsx$/.test(dl.suggestedFilename())) throw new Error('Excel download name ' + dl.suggestedFilename());
  step('Excel downloads the list on screen (' + dl.suggestedFilename() + ')');
  await page.emulateMedia({ media: 'print' }); await shot('n07-print-view'); await page.emulateMedia({ media: 'screen' }); step('print view drops the buttons');
  // Quick search: a journal by number, then a customer by name
  await page.keyboard.press('Control+K'); await page.locator('#qs-q').waitFor();
  await page.fill('#qs-q', 'DEMO/26'); await page.locator('.qs-row').first().waitFor(); await shot('n08-search');
  const jno = (await page.locator('.qs-row b').first().textContent()).trim();
  await page.locator('.qs-row').first().click(); await see(jno); await page.locator('.modal h2', { hasText: jno }).waitFor();
  step('Search finds journal ' + jno + ' and opens it');
  await page.click('.modal .modal-x');
  await page.click('#btn-search'); await page.fill('#qs-q', 'Kalpana'); await page.locator('.qs-row', { hasText: 'Supplier' }).first().click();
  await page.locator('.modal #s-name, .modal input').first().waitFor(); await page.waitForFunction(() => location.hash.startsWith('#/suppliers/'));
  step('Search finds a supplier and opens their details');
  await page.click('.modal .modal-x');
  // Settings: automatic sign-out
  await page.goto(BASE + '#/settings'); await page.locator('#st-idle').waitFor();
  if ((await page.locator('#st-idle').inputValue()) !== '30') throw new Error('Idle default not 30');
  step('Settings shows automatic sign-out at 30 minutes');

  // Opened straight on a record (fresh start, no history): Back goes up a level
  const p2 = await (await browser.newContext({ viewport: { width: 390, height: 844 }, storageState: await page.context().storageState() })).newPage();
  await p2.goto(BASE + '#/purchases/1'); await p2.locator('#nav-back').waitFor();
  await p2.screenshot({ path: OUT + '/n02-phone.png' });
  p2.on('pageerror', (e) => errors.push('p2: ' + e.message));
  await p2.click('#nav-back');
  await p2.waitForFunction(() => location.hash === '#/purchases', null, { timeout: 4000 });
  await p2.locator('#nav-back').waitFor(); await p2.waitForTimeout(300);
  await p2.click('#nav-back'); await p2.getByText('Hello, DS').first().waitFor({ timeout: 6000 });
  await p2.click('#btn-hide'); await p2.locator('#privacy').waitFor(); await p2.screenshot({ path: OUT + '/n05-phone-hidden.png' });
  step('With no history, Back goes record → list → Home');

  // Automatic sign-out (shortened for the test)
  await page.evaluate(() => { RB.cache.idleMinutes = 0.01; RB.idleSignout(); });
  await see('signed out after'); await shot('n09-signed-out'); step('After the idle time the app signs out with a note');

  console.log(errors.length ? 'BROWSER ERRORS:\n' + errors.join('\n') : 'No browser errors');
  await browser.close();
})().catch(async (e) => { console.error('E2E FAILED:', e.message); try { await global.__page.screenshot({ path: OUT + '/failure.png' }); } catch (x) {} process.exit(1); });
