// End-to-end walk through module 6 against tests/mock-supabase.js,
// on a fresh database with sql/01 to sql/06 loaded.
// Usage: node tests/e2e_cashbank.js <screenshot dir>
'use strict';
const { chromium } = require('playwright');
const OUT = process.argv[2] || '.';
const BASE = 'http://localhost:8787/';

(async () => {
  const browser = await chromium.launch();
  const errors = [];
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 860 } });
  const page = await ctx.newPage(); global.__page = page;
  const watch = (p) => {
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
    p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push('console: ' + m.text()); });
    p.on('dialog', (d) => { errors.push('dialog: ' + d.message()); d.dismiss(); });
  };
  watch(page);
  const shot = (n, p) => (p || page).screenshot({ path: OUT + '/' + n + '.png', fullPage: true });
  const step = (t) => console.log('• ' + t);
  const see = async (t, p) => { await (p || page).getByText(t, { exact: false }).first().waitFor({ timeout: 8000 }); };
  const opened = async (p) => { await (p || page).locator('.modal').last().waitFor(); await (p || page).waitForTimeout(300); };
  const modal = (p) => (p || page).locator('.modal').last();
  const toast = async (t, p) => { await (p || page).locator('#toast', { hasText: t }).waitFor({ timeout: 8000 }); };
  const tab = async (k, p) => { await (p || page).click('.tabs button[data-tab=' + k + ']'); await (p || page).waitForTimeout(500); };
  const msgOf = async (p) => ((await modal(p).locator('.m-msg').innerText()) || '').trim();

  // DS first sign-in
  await page.goto(BASE); await see('Sign in');
  await page.click('#to-first');
  await page.fill('#li-email', 'info.ruchibuds@gmail.com'); await page.fill('#li-pass', 'DS-secret-123'); await page.fill('#li-pass2', 'DS-secret-123');
  await page.click('button[type=submit]'); await see('Hello, DS');
  const tiles = await page.$$eval('.tile:not(.disabled)', (els) => els.map((e) => e.textContent.trim()));
  if (!tiles.some((x) => x.includes('Cash, bank and expenses'))) throw new Error('Cash, bank and expenses tile missing: ' + tiles.join(', '));
  step('home shows Cash, bank and expenses as live');

  // Balances and the cash book
  await page.click('a[href="#/cash_bank"]'); await see('Cash book'); await see('Bank account 1 (main, UPI)');
  await page.fill('#bk-from', '2026-11-01'); await page.click('#bk-go'); await see('Opening balance'); await see('DEMO-CNT/2611/00001');
  await shot('w01-cash-book'); step('cash and bank balances, and the cash book with the DEMO cash count');

  // Expenses list, the DEMO signboard waiting for approval
  await tab('expenses'); await page.fill('#ex-from', '2026-11-01'); await page.click('#ex-go'); await see('DEMO-EXP/2611/00001');
  await see('waiting for approval'); await shot('w02-expenses'); step('expenses list: DEMO entries, one waiting for approval');
  await page.locator('#ex-grid .tabulator-row', { hasText: 'Waiting for approval' }).first().click(); await opened();
  await see('Approve'); await shot('w03-expense-waiting');
  await modal().locator('#xw-ok').click(); await toast('Approved');
  step('the Director approves the ₹12,500 signboard');

  // A new expense, paid in cash, below the limit
  await page.click('#cb-new'); await opened();
  await page.selectOption('#xe-cat', { label: 'Shop or office electricity and water' });
  await page.fill('#xe-desc', 'Shop electricity, November'); await page.fill('#xe-amt', '1200');
  await shot('w04-new-expense');
  await modal().locator('#xe-save').click(); await toast('saved');
  await page.click('#ex-go'); await see('Shop electricity, November');
  const [cashExp] = await page.$$eval('#ex-grid .tabulator-row', (rs) => rs.filter((r) => r.textContent.includes('Shop electricity, November')).map((r) => r.textContent));
  if (!/TRN-EXP\/\d{4}\/00001/.test(cashExp)) throw new Error('Training expense not numbered TRN-EXP: ' + cashExp);
  step('new cash expense saved as TRN-EXP/…/00001 and posted at once');

  // A big one waits for approval
  await page.click('#cb-new'); await opened();
  await page.selectOption('#xe-cat', { label: 'Marketing and printing' });
  await page.fill('#xe-desc', 'Stall at the food fair'); await page.fill('#xe-amt', '15000'); await page.selectOption('#xe-mode', 'bank');
  await see('waits for approval'); await modal().locator('#xe-save').click(); await toast('waiting for approval');
  step('₹15,000 by bank: the form warns, and it waits for approval');

  // On credit without a supplier is refused; with one it stays open
  await page.click('#cb-new'); await opened();
  await page.selectOption('#xe-cat', { label: 'Accounting and audit fees' });
  await page.fill('#xe-desc', 'GST registration advice'); await page.fill('#xe-amt', '2000'); await page.fill('#xe-gst', '360'); await page.selectOption('#xe-mode', 'credit');
  await modal().locator('#xe-save').click(); await page.waitForTimeout(500);
  if (!/needs the supplier/.test(await msgOf())) throw new Error('Credit expense without a supplier was not refused: ' + await msgOf());
  await page.selectOption('#xe-sup', { label: 'Mehta & Co, Chartered Accountants (DEMO)' }); await page.fill('#xe-bill', 'MC-88');
  await modal().locator('#xe-save').click(); await toast('saved');
  step('a credit bill needs the supplier; saved for Mehta & Co with ₹360 GST (part of the cost: not registered)');

  // Pay the Mehta bills from the expense window
  await page.click('#ex-go'); await page.locator('#ex-grid .tabulator-row', { hasText: 'GST registration advice' }).first().click(); await opened();
  await see('still owed'); await modal().locator('#xw-pay').click(); await opened();
  await see('Open bills'); await see('GST registration advice'); await shot('w05-pay-expense-bill');
  await modal().locator('#pay-save').click(); await toast('Payment saved');
  await page.click('#ex-go'); await page.waitForTimeout(400);
  const owed = await page.$$eval('#ex-grid .tabulator-row', (rs) => rs.filter((r) => r.textContent.includes('GST registration advice')).map((r) => r.textContent));
  if (owed[0].includes('2,360')) {
    const cells = owed[0].split('₹'); if (cells.length > 2) throw new Error('Advice bill still shows money owed: ' + owed[0]);
  }
  step('paid from Bank account 1 through the supplier payment window; the bill is cleared');

  // Moving money
  await tab('transfers'); await page.click('#tr-add'); await opened();
  await page.fill('#tr-amt', '1000'); await modal().locator('#tr-save').click(); await toast('Saved');
  await see('TRN-CTR/'); await shot('w06-transfers'); step('₹1,000 cash paid into the bank');

  // Day-end cash count, ₹10 short
  await tab('counts'); await page.click('#cc-add'); await opened(); await page.waitForTimeout(600);
  const bookTxt = (await page.locator('#cc-book').innerText()).replace(/[₹,]/g, '');
  const book = Math.round(Number(bookTxt) * 100);
  await page.fill('#cc-total', String((book - 1000) / 100));
  await modal().locator('#cc-save').click(); await page.waitForTimeout(500);
  if (!/reason/.test(await msgOf())) throw new Error('A short count without a reason was not refused: ' + await msgOf());
  await page.fill('#cc-why', 'Change given short'); await shot('w07-cash-count');
  await modal().locator('#cc-save').click(); await toast('Difference of ₹10.00 posted');
  step('cash count ₹10 short: the reason is required, then the difference is posted');

  // Partners
  await tab('partners'); await see('Partner 1'); await see('DEMO-PTR/');
  await page.click('#pt-add'); await opened(); await page.selectOption('#pt-kind', 'drawings'); await page.fill('#pt-amt', '500');
  await modal().locator('#pt-save').click(); await toast('Saved'); await shot('w08-partners'); step('partners\' capital and current accounts; drawings of ₹500 entered');

  // Bank reconciliation, November
  await tab('bank'); await see('On statement'); await page.fill('#br-month', '2026-11'); await page.click('#br-go'); await see('at 30-Nov-2026');
  const bookBal = (await page.locator('.facts div').first().locator('b').innerText()).replace(/[₹,]/g, '');
  await page.click('#br-all'); await page.fill('#br-stmt', '1'); await page.waitForTimeout(200);
  await page.click('#br-finish'); await toast('difference of');
  await page.fill('#br-stmt', bookBal); await page.waitForTimeout(200); await see('₹0.00 ✓');
  await shot('w09-bank-recon');
  await page.click('#br-finish'); await toast('Month reconciled'); await see('Reconciled');
  step('bank reconciliation: a wrong statement balance is refused; all ticked at ₹' + bookBal + ' and finished');

  // Month-end, November (DEMO)
  await tab('monthend'); await page.fill('#me-month', '2026-11'); await page.click('#me-go');
  await see('Checklist for'); await see('Step 1'); await see('Step 2'); await see('Posted as DEMO-ME/');
  await page.locator('#me-abs details').nth(1).locator('summary').click();
  await shot('w10-month-end'); step('month-end checklist, step 1 (kg produced, all four methods compared) and step 2 both posted on the DEMO records');
  await page.locator('#pv-rev').click(); await opened(); await page.fill('#ar-why', 'Run again after checking the rates'); await modal().locator('#ar-ok').click();
  await toast('Reversed'); await see('Post the provision'); await page.click('#pv-post'); await opened(); await modal().locator('#cf-ok').click(); await toast('Posted');
  step('step 2 reversed and posted again');

  // Set-up: method change is for a Director, with a reason
  await tab('setup'); await see('Cash and bank accounts'); await see('Month-end step 1 set-up');
  await shot('w11-setup');
  await page.click('#su-method'); await opened(); await page.selectOption('#mm-new', 'batches');
  await modal().locator('#mm-save').click(); await page.waitForTimeout(400);
  if (!/reason/.test(await msgOf())) throw new Error('Method change without a reason was not refused');
  await page.fill('#mm-why', 'Trying batches for the demo'); await modal().locator('#mm-save').click(); await toast('Method changed');
  await see('Number of batches'); step('the Director changes the sharing method with a reason');

  // Expense report
  await tab('report'); await page.fill('#rp-from', '2026-11-01'); await page.click('#rp-go'); await see('Kitchen wages'); await shot('w12-report');
  step('expense report by month, category and department');

  // Settings: the CA's rates
  await page.goto(BASE + '#/settings'); await see('Expenses and month-end'); await see('only an example');
  await page.fill('#st-otherpct', '12'); await page.fill('#st-ratesnote', 'Test rates'); await page.click('#st-save'); await toast('Settings saved');
  await page.reload(); await see('Expenses and month-end');
  if (await page.locator('text=These rates are only an example').count()) throw new Error('Example warning still shown after saving the rates');
  await shot('w13-settings'); step('Settings: approval limit and the CA\'s rates saved; the "example" warning goes');

  // Accountant approves the waiting fair stall; Manager cannot see totals tabs
  const ctx2 = await browser.newContext({ viewport: { width: 390, height: 844 } }); const mg = await ctx2.newPage(); watch(mg);
  await mg.goto(BASE); await see('Sign in', mg); await mg.click('#to-first');
  await mg.fill('#li-email', 'demo.manager1@example.com'); await mg.fill('#li-pass', 'Mgr-secret-1'); await mg.fill('#li-pass2', 'Mgr-secret-1');
  await mg.click('button[type=submit]'); await mg.locator('.menu').waitFor();
  await mg.goto(BASE + '#/cash_bank'); await see('Expenses', mg);
  const mtabs = await mg.$$eval('.tabs button', (els) => els.map((e) => e.dataset.tab));
  for (const t of ['monthend', 'setup']) if (mtabs.includes(t)) throw new Error('Manager sees the ' + t + ' tab');
  await mg.click('#cb-new'); await opened(mg); await shot('w14-phone-new-expense', mg);
  await mg.selectOption('#xe-cat', { label: 'Kitchen gas' }); await mg.fill('#xe-desc', 'Gas, 1 cylinder'); await mg.fill('#xe-amt', '950');
  await modal(mg).locator('#xe-save').click(); await toast('saved', mg);
  step('a Manager on a phone enters the gas; no month-end or set-up tabs');
  await ctx2.close();

  console.log(errors.length ? 'BROWSER ERRORS:\n' + errors.join('\n') : 'No browser errors');
  await browser.close();
  if (errors.length) process.exit(1);
})().catch(async (e) => { console.error('E2E FAILED:', e.message); try { console.error('APP TEXT:', JSON.stringify((await global.__page.innerText('body')).slice(0, 1500))); await global.__page.screenshot({ path: OUT + '/failure.png' }); } catch (x) {} process.exit(1); });
