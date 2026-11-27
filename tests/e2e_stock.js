// End-to-end walk through module 4 against tests/mock-supabase.js,
// on a fresh database with sql/01 to sql/04 loaded.
// Usage: node tests/e2e_stock.js <screenshot dir>
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
  const opened = async () => { await page.locator('.modal').last().waitFor(); await page.waitForTimeout(250); };
  const pick = (sel, label) => page.selectOption(sel, { label });
  const modal = () => page.locator('.modal').last();

  // DS first sign-in
  await page.goto(BASE); await see('Sign in');
  await page.click('#to-first');
  await page.fill('#li-email', 'info.ruchibuds@gmail.com'); await page.fill('#li-pass', 'DS-secret-123'); await page.fill('#li-pass2', 'DS-secret-123');
  await page.click('button[type=submit]'); await see('Hello, DS');
  const tiles = await page.$$eval('.tile:not(.disabled)', (els) => els.map((e) => e.textContent.trim()));
  if (!tiles.some((x) => x.includes('Production')) || !tiles.some((x) => x.includes('Stock'))) throw new Error('Production or Stock tile missing');
  step('home shows Production and Stock as live');

  // Production list and DEMO batches
  await page.click('a[href="#/production"]'); await see('DEMO-PRP/2611/00001'); await shot('s01-batches');
  step('batch list with the DEMO preparation and production batches');
  await page.getByText('DEMO-PRD/2611/00002').first().click(); await see('What came out'); await see('Prepared in');
  await shot('s02-batch-combined'); step('combined fish batch: production window links back to its preparation batch');
  await page.locator('a[href^="#/production/"]').filter({ hasText: 'DEMO-PRP' }).first().click(); await see('Wastage at each stage'); await see('Used in');
  await shot('s03-batch-prep'); step('preparation batch: stages, by-product, yield, used in');
  await page.goto(BASE + '#/production'); await see('DEMO-PRP/2611/00001');
  await page.click('button[data-tab=yield]'); await page.waitForTimeout(300); await page.fill('#yl-from', '2026-04-01'); await page.click('#yl-go'); await see('Ginger (DEMO)'); await shot('s04-yield');
  await page.click('button[data-tab=wastage]'); await page.waitForTimeout(300); await page.fill('#ws-from', '2026-04-01'); await page.click('#ws-go'); await see('Peel'); await shot('s05-wastage');
  step('yield report and wastage by stage');

  // Opening stock of raw ginger, then a preparation batch from it
  await page.goto(BASE + '#/stock'); await see('Raw materials, bottles and pouches');
  await shot('s06-stock-raw');
  if (!(await page.locator('#rw-lots .tabulator-row').count())) throw new Error('No prepared batches listed');
  step('stock: raw and prepared, batch by batch');
  await page.click('#sk-open'); await opened(); await see('Opening stock');
  const row = modal().locator('tr', { hasText: 'Ginger (DEMO)' }).filter({ hasNotText: 'peeled' }).first();
  await row.locator('[data-f=counted]').fill('3'); await row.locator('[data-f=rate]').fill('100');
  await shot('s07-opening'); await page.click('#cm-save'); await see('Approve and post');
  await page.click('#cd-post'); await page.click('#cf-ok'); await see('Count posted');
  step('opening stock: 3 kg of ginger at ₹100 a kg, approved by DS');

  await page.goto(BASE + '#/production/new'); await see('Production window');
  await page.click('[data-mode=preparation]'); await page.waitForTimeout(200);
  await pick('#pp-raw', 'Ginger (DEMO)'); await page.waitForTimeout(200);
  await page.fill('[data-st="0"][data-f=w]', '0.1'); await page.fill('[data-st="1"][data-f=w]', '0.3');
  await page.fill('#pp-in', '3'); await page.fill('#pp-out', '2.6');
  await see('yield'); await shot('s08-new-prep');
  await page.click('#pw-save'); await see('Batch saved'); await see('TRN-PRP/');
  await see('86.7%'); await shot('s09-prep-saved');
  step('preparation of ginger: 3 kg in, 0.4 kg wastage, 2.6 kg out, yield 86.7%');

  // Final production of smoked meat pickle
  await page.goto(BASE + '#/production/new'); await see('Production window');
  await page.click('[data-mode=production]'); await page.waitForTimeout(200);
  await pick('#pd-fg', 'Smoked meat pickle (DEMO)'); await page.waitForTimeout(200);
  await pick('#pi-item-0', 'Meat, dried and shredded (DEMO) (prepared)'); await page.waitForTimeout(200);
  await page.fill('[data-in="0"][data-f=qty]', '2');
  await page.click('#pd-addin'); await pick('#pi-item-1', 'Mustard oil (DEMO)'); await page.waitForTimeout(200);
  await page.fill('[data-in="1"][data-f=qty]', '0.5');
  await page.locator('[data-pack]').first().fill('10');
  await page.fill('#pd-shr', '500');
  await see('Made'); await shot('s10-new-production');
  await page.click('#pw-save'); await see('Batch saved'); await see('TRN-PRD/'); await see('Cost per pack');
  await shot('s11-production-saved');
  step('production: 2 kg dried meat and 0.5 l oil into 10 bottles of 200 g, bottles taken from stock');

  // Reverse it
  await page.click('#bw-rev'); await opened(); await page.fill('#rv-why', 'Entered by mistake'); await page.click('#rv-go'); await see('Reversed:');
  step('reversed the production batch');

  // Prepare and produce together: no raw fish in stock, so it is refused
  await page.goto(BASE + '#/production/new'); await see('Production window');
  await page.click('[data-mode=combined]'); await page.waitForTimeout(200);
  if (await page.locator('#pw-prep').isHidden() || await page.locator('#pw-prod').isHidden()) throw new Error('Combined mode must show both parts');
  await pick('#pp-raw', 'Fish, fresh (DEMO)'); await page.waitForTimeout(200);
  await page.fill('#pp-in', '5'); await page.fill('#pp-out', '3');
  await pick('#pd-fg', 'Fish pickle (DEMO)'); await page.waitForTimeout(200);
  await page.locator('[data-pack]').first().fill('15');
  await shot('s12-combined'); await page.click('#pw-save'); await page.locator('.msg.error').first().waitFor();
  step('combined entry is refused when there is not enough raw fish: "' + (await page.locator('.msg.error').first().innerText()).slice(0, 80) + '"');

  // Stock count of mustard oil
  await page.goto(BASE + '#/stock'); await page.click('button[data-tab=raw]'); await see('Raw materials, bottles and pouches');
  await page.click('#sk-count'); await opened();
  await page.check('#cm-books'); await page.waitForTimeout(200);
  const oil = modal().locator('tr', { hasText: 'Mustard oil (DEMO)' }).first();
  await oil.locator('[data-f=counted]').fill('35'); await oil.locator('[data-f=reason]').fill('Spilt while filling');
  await shot('s13-count'); await page.click('#cm-save'); await see('Approve and post');
  await page.click('#cd-post'); await page.click('#cf-ok'); await see('Count posted');
  await page.click('button[data-tab=counts]'); await see('DEMO-SC/2611/00001'); await shot('s14-counts');
  step('stock count: 35 l of oil counted, posted as a shortage');

  // Write-off from a prepared batch
  await page.click('#sk-wo'); await opened();
  await pick('#aj-item', (await page.$$eval('#aj-item option', (o) => o.map((x) => x.textContent))).find((t) => t.startsWith('Onion, chopped')));
  await page.waitForTimeout(200); await page.fill('#aj-qty', '0.5'); await page.fill('#aj-why', 'Gone soft');
  await shot('s15-write-off'); await page.click('#aj-save'); await see('Write-off saved');
  await page.click('button[data-tab=adjust]'); await see('Waiting for approval'); await shot('s16-write-offs');
  await page.locator('#aj-grid .tabulator-row', { hasText: 'Waiting for approval' }).first().click(); await opened();
  await page.click('#ad-ok'); await see('Posted');
  step('write-off of 0.5 kg chopped onion; DEMO ginger write-off approved');

  // Finished goods and movements
  await page.click('button[data-tab=finished]'); await see('Fish pickle (DEMO)'); await shot('s17-finished');
  await page.locator('#fn-grid .tabulator-row', { hasText: 'Fish pickle' }).first().click(); await opened(); await see('Movements: Fish pickle'); await page.waitForTimeout(400);
  await shot('s18-movements'); await page.click('.modal [data-close]');
  step('finished goods by pack and an item\'s movements');

  // Phone view
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(BASE + '#/production/new'); await see('Production window'); await page.click('[data-mode=preparation]'); await page.waitForTimeout(300); await shot('s19-phone-prep');
  await page.goto(BASE + '#/stock'); await page.click('button[data-tab=raw]'); await see('Raw materials, bottles and pouches'); await page.waitForTimeout(300); await shot('s20-phone-stock');
  await page.setViewportSize({ width: 1280, height: 860 });
  step('phone views');

  console.log(errors.length ? 'BROWSER ERRORS:\n' + errors.join('\n') : 'No browser errors');
  await browser.close();
  if (errors.length) process.exit(1);
})().catch(async (e) => { console.error('E2E FAILED:', e.message); try { console.error('APP TEXT:', JSON.stringify((await global.__page.innerText('body')).slice(0, 1500))); await global.__page.screenshot({ path: OUT + '/failure.png' }); } catch (x) {} process.exit(1); });
