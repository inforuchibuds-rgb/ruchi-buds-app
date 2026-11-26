// End-to-end walk through module 3 against tests/mock-supabase.js,
// on a fresh database with 01_core_users.sql, 02_masters.sql and 03_purchases.sql.
// Usage: node tests/e2e_purchases.js <screenshot dir>
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
  page.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push('console: ' + m.text()); });
  const shot = (n) => page.screenshot({ path: OUT + '/' + n + '.png', fullPage: true });
  const step = (t) => console.log('• ' + t);
  const see = async (t) => { await page.getByText(t, { exact: false }).first().waitFor({ timeout: 8000 }); };
  const modal = () => page.locator('.modal').last();
  const opened = async () => { await page.locator('.modal').last().waitFor(); await page.waitForTimeout(200); };
  const pick = (sel, label) => page.selectOption(sel, { label });

  // DS first sign-in
  await page.goto(BASE); await see('Sign in');
  await page.click('#to-first');
  await page.fill('#li-email', 'info.ruchibuds@gmail.com'); await page.fill('#li-pass', 'DS-secret-123'); await page.fill('#li-pass2', 'DS-secret-123');
  await page.click('button[type=submit]'); await see('Hello, DS');
  const tiles = await page.$$eval('.tile:not(.disabled)', (els) => els.map((e) => e.textContent.trim()));
  if (!tiles.some((x) => x.includes('Purchases'))) throw new Error('Purchases tile missing');
  step('home shows Purchases as live');

  // List
  await page.click('a[href="#/purchases"]'); await see('DEMO-PO/2611/00002'); await shot('p01-list'); step('purchase list with DEMO purchases');
  await page.click('button[data-f=diffs]'); await page.waitForTimeout(300);
  const diffRows = await page.$$eval('#pl-grid .tabulator-row', (r) => r.length);
  if (diffRows !== 2) throw new Error('Expected 2 purchases with differences, got ' + diffRows);
  step('filter "With differences" shows the 2 DEMO purchases with open differences');
  await page.click('button[data-f=all]');

  // Purchase window with differences: glass bottles
  await page.getByText('DEMO-PO/2611/00002').first().click(); await see('Match: order, goods received and bill');
  if ((await page.locator('td.diff').count()) < 2) throw new Error('Differences not shown in red');
  await shot('p02-window-differences'); step('purchase window: PO, GRN and bill side by side, differences in red');
  await page.locator('[data-act=return]').first().click(); await opened();
  await page.fill('#st-why', 'Broken bottles sent back with the driver'); await page.click('#st-go'); await see('Difference settled');
  await page.locator('[data-act=debit_note]').first().click(); await opened();
  await page.fill('#st-why', 'Supplier agreed: 12 broken bottles not charged'); await page.click('#st-go'); await see('Difference settled');
  await see('DEMO-DN/2611/'); await see('Pay');
  await shot('p03-window-settled'); step('damaged bottles: returned; billed-for-broken: debit note DEMO-DN; purchase can now be paid');
  await page.click('#pw-pay'); await opened(); await page.waitForTimeout(400);
  await page.click('#pay-save'); await see('Payment saved'); await see('Paid');
  step('paid the settled bill from the purchase window');

  // New order, receive short, bill with a different rate
  await page.goto(BASE + '#/purchases'); await see('DEMO-PO/2611/00001');
  await page.click('#pu-new'); await opened();
  await pick('#po-sup', 'Sharma Spices Pvt Ltd (DEMO)');
  await pick('#pl-item-0', 'Dried red chilli (DEMO)'); await page.waitForTimeout(150);
  await page.fill('[data-f=qty][data-i="0"]', '10'); await page.fill('[data-f=rate][data-i="0"]', '300');
  await page.click('#po-add'); await pick('#pl-item-1', 'Glass bottle, 200 g (DEMO)'); await page.waitForTimeout(150);
  await page.fill('[data-f=qty][data-i="1"]', '50'); await page.fill('[data-f=rate][data-i="1"]', '12');
  await shot('p04-new-order'); await page.click('#po-save'); await see('Order saved'); await see('TRN-PO/');
  step('new order TRN-PO with two lines (chilli in kg, bottles in pieces)');
  await page.click('#pw-receive'); await opened();
  await page.locator('[data-rec="0"]').fill('9.5');
  await shot('p05-receive'); await page.click('#gr-save'); await see('Goods received'); await see('Part received');
  step('received 9.5 kg of 10: short flagged');
  await page.click('#pw-bill'); await opened();
  await page.fill('#bl-no', 'SS/6001'); await page.locator('[data-q="0"]').fill('10'); await page.locator('[data-r="0"]').fill('310');
  await shot('p06-bill'); await page.click('#bl-save'); await see('Bill saved'); await see('Supplier bill'); await page.waitForSelector('td.diff');
  if ((await page.locator('td.diff').count()) < 3) throw new Error('Bill differences not flagged');
  await shot('p07-bill-differences'); step('bill for 10 kg at ₹310: billed qty and rate flagged in red, no Pay button');
  if (await page.locator('#pw-pay').count()) throw new Error('Pay should be hidden while differences are open');

  // Direct purchase: fish, no bill
  await page.goto(BASE + '#/purchases'); await see('DEMO-PO/2611/00001');
  await page.click('#pu-direct'); await opened();
  await pick('#dp-sup', 'Raju Koli, fisherman (DEMO) (no bill)');
  if (!(await page.isChecked('#dp-nobill'))) throw new Error('No-bill should tick itself for a fisherman');
  await page.fill('#dp-reason', 'Daily fish catch');
  await pick('#dl-item-0', 'Fish, fresh (DEMO)'); await page.waitForTimeout(150);
  await page.fill('#dp-lines [data-f=qty][data-i="0"]', '6'); await page.fill('#dp-lines [data-f=rate][data-i="0"]', '450');
  await page.click('#dp-save'); await see('photo');
  await page.fill('#dp-note', 'Weighing slip 0533'); await shot('p08-direct'); await page.click('#dp-save'); await see('Purchase saved'); await see('Paid');
  await see('Received, no supplier bill'); await shot('p09-direct-window');
  step('direct purchase of fish with no bill: needs a photo or note, then posts and is paid in cash');

  // Approve the DEMO direct purchase waiting for approval
  await page.goto(BASE + '#/purchases'); await see('DEMO-PO/2611/00001');
  await page.click('button[data-f=approval]'); await page.waitForTimeout(300);
  await page.locator('#pl-grid .tabulator-row').first().click(); await see('Waiting for approval');
  await page.click('#pw-approve'); await page.click('#cf-ok'); await see('Approved and posted'); await see('Billed');
  step('Director approves the DEMO direct purchase above the limit');

  // Payments, balances and ledger, reports
  await page.goto(BASE + '#/purchases'); await see('Waiting for approval');
  await page.click('button[data-f=all]'); await see('DEMO-PO/2611/00001');
  step('the list remembers the chosen filter until another is picked');
  await page.click('#pu-pay'); await opened();
  await pick('#pay-sup', 'Highland Meats (DEMO)'); await page.waitForTimeout(600);
  await shot('p10-pay'); await page.click('#pay-save'); await see('Payment saved');
  step('paid Highland Meats against its open bills');
  await page.click('button[data-tab=payments]'); await see('DEMO-PAY/2611/00001'); await shot('p11-payments'); step('payments list');
  await page.click('button[data-tab=diffs]'); await see('Bill rate'); await shot('p12-differences'); step('open differences list with age in days');
  await page.click('button[data-tab=balances]'); await see('Balance owed'); await shot('p13-balances');
  await page.getByText('FlexiPack Pouches (DEMO)').first().click(); await opened(); await see('Supplier ledger: FlexiPack'); await see('Balance brought forward');
  await shot('p14-ledger'); await page.click('.modal [data-close]'); step('supplier balances and ledger');
  await page.click('button[data-tab=reports]'); await see('Supplier differences by month'); await page.waitForTimeout(500); await shot('p15-reports'); step('reports: differences by supplier, direct purchases, stock bought');

  // Suppliers screen shows balances and opens the ledger
  await page.goto(BASE + '#/suppliers'); await see('Balance owed');
  await page.getByText('Kalpana Oils (DEMO)').first().click(); await opened(); await page.click('#s-ledger'); await see('Supplier ledger: Kalpana');
  await page.click('.modal [data-close]'); step('suppliers screen shows the balance and opens the ledger');

  // Accounts: a purchases journal cannot be reversed there
  await page.goto(BASE + '#/accounts'); await see('Goods received');
  step('purchase postings appear in Accounts and journals');

  // Phone view
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(BASE + '#/purchases'); await see('Supplier differences by month');
  await page.click('button[data-tab=list]'); await see('DEMO-PO/2611/00001'); await shot('p16-phone-list');
  await page.click('#pu-direct'); await opened(); await shot('p17-phone-direct'); await page.click('.modal [data-close]');
  await page.goto(BASE + '#/purchases'); await see('DEMO-PO/2611/00003'); await page.getByText('DEMO-PO/2611/00003').first().click(); await see('Match');
  await shot('p18-phone-window');
  await page.setViewportSize({ width: 1280, height: 860 });
  step('phone views');

  console.log(errors.length ? 'BROWSER ERRORS:\n' + errors.join('\n') : 'No browser errors');
  await browser.close();
})().catch(async (e) => { console.error('E2E FAILED:', e.message); try { console.error('APP TEXT:', JSON.stringify((await global.__page.innerText('body')).slice(0, 1500))); await global.__page.screenshot({ path: OUT + '/failure.png' }); } catch (x) {} process.exit(1); });
