// End-to-end walk through module 7 against tests/mock-supabase.js,
// on a fresh database with sql/01 to sql/07 loaded.
// Usage: node tests/e2e_loans.js <screenshot dir>
'use strict';
const { chromium } = require('playwright');
const OUT = process.argv[2] || '.';
const BASE = 'http://localhost:8787/';

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
  const see = async (t, p) => { await (p || page).getByText(t, { exact: false }).first().waitFor({ timeout: 8000 }); };
  const opened = async (p) => { await (p || page).locator('.modal').last().waitFor(); await (p || page).waitForTimeout(400); };
  const modal = (p) => (p || page).locator('.modal').last();
  const toast = async (t, p) => { await (p || page).locator('#toast', { hasText: t }).waitFor({ timeout: 8000 }); };
  const tab = async (k, p) => { await (p || page).click('.tabs button[data-tab=' + k + ']'); await (p || page).waitForTimeout(600); };
  const msgOf = async (p) => ((await modal(p).locator('.m-msg').innerText()) || '').trim();
  const yes = async () => { await opened(); await modal().locator('#cf-ok').click(); };
  const reason = async (text, date) => { await opened(); if (date) await modal().locator('#ar-date').fill(date); await modal().locator('#ar-why').fill(text); await modal().locator('#ar-ok').click(); };
  const closeAll = async () => { while (await page.locator('.modal').count()) { await modal().locator('[data-close]').last().click(); await page.waitForTimeout(200); } };
  const today = await page.evaluate(() => new Date().toISOString().slice(0, 10)).catch(() => null);

  // DS first sign-in
  await page.goto(BASE); await see('Sign in');
  await page.click('#to-first');
  await page.fill('#li-email', 'info.ruchibuds@gmail.com'); await page.fill('#li-pass', 'DS-secret-123'); await page.fill('#li-pass2', 'DS-secret-123');
  await page.click('button[type=submit]'); await see('Hello, DS');
  const tiles = await page.$$eval('.tile:not(.disabled)', (els) => els.map((e) => e.textContent.trim()));
  if (!tiles.some((x) => x.includes('Loans and leases'))) throw new Error('Loans and leases tile missing: ' + tiles.join(', '));
  step('home shows Loans and leases as live');

  // Summary with the DEMO records
  await page.click('a[href="#/loans"]'); await see('Loans owed'); await see('DEMO-LN-001'); await see('DEMO-OL-002');
  await shot('l01-summary'); step('summary: DEMO bank loan, partner loan, van lease and two rented premises');

  // The DEMO bank loan
  await tab('loans'); await page.locator('#lt-grid .tabulator-row', { hasText: 'DEMO-LN-001' }).first().click(); await opened();
  await see('Brought in (take-on)'); await see('13,001'); await shot('l02-demo-loan');
  await closeAll(); step('DEMO bank loan: take-on, EMI ₹13,001, schedule and entries');

  // A new loan: preview, save, start
  await page.click('#ll-new'); await opened();
  await page.fill('#lf-name', 'Kitchen equipment loan'); await page.fill('#lf-lender', 'Canara Bank, Andheri');
  await page.fill('#lf-amt', '200000'); await page.fill('#lf-rate', '12'); await page.fill('#lf-n', '24'); await page.fill('#lf-fee', '2000');
  await modal().locator('#lf-preview').click(); await see('Total interest');
  const emiText = await modal().locator('#lf-prev').innerText();
  if (!/9,415/.test(emiText)) throw new Error('EMI for ₹2,00,000 at 12% over 24 months should be ₹9,415: ' + emiText.slice(0, 300));
  await shot('l03-new-loan-preview');
  await modal().locator('#lf-save').click(); await toast('draft'); await opened();
  await see('Start (approve and post)'); await modal().locator('#lw-start').click(); await yes(); await toast('Started');
  await opened(); await see('Pay instalment 1');
  const loanNo = (await modal().locator('h2').first().innerText()).split(/\s/)[0];
  if (!/^TRN-LN-/.test(loanNo) && !/^LN-/.test(loanNo)) throw new Error('Unexpected loan number ' + loanNo);
  step('new ₹2,00,000 loan at 12% for 24 months: EMI ₹9,415, started as ' + loanNo);

  // Pay EMI 1
  await modal().locator('#lw-pay').click(); await opened();
  await page.fill('#py-ref', 'NACH 1'); await shot('l04-pay-emi');
  await modal().locator('#py-save').click(); await toast('Payment saved'); await opened(); await see('Pay instalment 2');
  step('EMI 1 paid from the bank');

  // Part-pay ₹20,000, keep the EMI
  await modal().locator('#lw-pre').click(); await opened();
  await page.fill('#pp-pr', '20000'); await page.fill('#pp-ch', '400'); await modal().locator('#pp-save').click(); await toast('Part-payment saved'); await opened();
  await see('Part-payment or paid off'); step('part-payment of ₹20,000 with ₹400 charges; EMI kept, loan ends sooner');

  // Rate change
  await modal().locator('#lw-rate').click(); await opened();
  await page.fill('#rt-rate', '12.5'); await modal().locator('#rt-save').click(); await page.waitForTimeout(500);
  if (!/reason/i.test(await msgOf())) throw new Error('Rate change without a reason was not refused: ' + await msgOf());
  await page.fill('#rt-why', 'Bank letter: MCLR up'); await modal().locator('#rt-save').click(); await toast('Rate changed'); await opened();
  await see('Bank letter: MCLR up'); await shot('l05-loan-after-rate'); await closeAll();
  step('rate change needs a reason; saved and shown on the loan');

  // A finance lease: rate worked out from the fair value
  await page.click('#ll-fl'); await opened();
  await page.fill('#lf-name', 'Packing machine lease'); await page.fill('#lf-lender', 'Sai Leasing');
  await page.fill('#lf-asset', 'Pouch packing machine'); await page.selectOption('#lf-aacc', '20010125');
  await page.fill('#lf-fv', '150000'); await page.fill('#lf-n', '36'); await page.fill('#lf-emi', '5000'); await page.fill('#lf-life', '48');
  await modal().locator('#lf-preview').click(); await see('Rate used'); await see('looks like a');
  await shot('l06-finance-lease-preview');
  await modal().locator('#lf-save').click(); await toast('draft'); await opened();
  await modal().locator('#lw-start').click(); await yes(); await toast('Started'); await opened();
  await see('Asset at cost'); await closeAll();
  step('finance lease of a ₹1,50,000 packing machine: rate implicit worked out, asset and liability recorded');

  // Rented premises: save, start, deposit, rent
  await page.click('#ll-ol'); await opened();
  await page.fill('#of-name', 'Godown, Jogeshwari'); await page.fill('#of-lessor', 'Mr Patil');
  await page.selectOption('#of-cat', { index: 0 });
  await page.fill('#of-months', '24'); await page.fill('#of-lock', '12'); await page.fill('#of-rent', '8000'); await page.fill('#of-esc', '5'); await page.fill('#of-free', '1');
  await page.fill('#of-dep', '24000'); await see('Total rent over the lease');
  const sumText = await modal().locator('#of-sum').innerText();
  if (!/1,88,800/.test(sumText)) throw new Error('Total rent should be ₹1,88,800: ' + sumText);
  await shot('l07-rented-premises');
  await modal().locator('#of-save').click(); await toast('draft'); await opened();
  await modal().locator('#ow-start').click(); await yes(); await toast('Started'); await opened();
  await modal().locator('#ow-dpay').click(); await opened();
  await modal().locator('#dp-save').click(); await toast('Saved'); await opened();
  await see('Deposit paid');
  const rentBtns = await modal().locator('[data-rent]').count();
  if (rentBtns !== 23) throw new Error('Expected 23 months with rent to enter (one rent-free), got ' + rentBtns);
  await modal().locator('[data-rent="2"]').click(); await opened();
  await modal().locator('#rr-save').click(); await toast('Rent entered'); await opened();
  await shot('l08-rented-after-rent'); await closeAll();
  step('godown: 24 months, 1 rent-free, 5% after a year; ₹24,000 deposit paid and a month\'s rent entered as an expense');

  // Month-end for this month (real records now exist, so the DEMO ones are left alone)
  await tab('monthend'); await page.fill('#lm-month', (today || '2026-11-27').slice(0, 7)); await page.click('#lm-go'); await page.waitForTimeout(800);
  await see('Loans and leases for'); await shot('l09-month-end');
  if (!(await page.locator('#lm-post').count())) { await see('has ended'); step('this month can be previewed; posting waits until the month has ended (posting is covered by tests/test_loans.sql)'); }
  else {
    await page.click('#lm-post'); await yes(); await toast('Posted'); await see('Posted as');
    await page.click('#lm-rev'); await reason('Test reversal'); await toast('Reversed'); await see('Post (');
    step('month-end run posted, then reversed and ready to post again');
  }

  // Cash, bank and expenses month-end checklist shows the new line
  await page.goto(BASE + '#/cash_bank'); await see('Cash book'); await tab('monthend'); await see('loans and leases month-end');
  step('Cash, bank and expenses month-end checklist lists the loans and leases run before step 1');

  // AS 19 notes and the Excel download
  await page.goto(BASE + '#/loans'); await see('Month-end'); await tab('as19'); await see('Finance leases: minimum lease payments'); await see('Operating leases');
  await shot('l10-as19-notes');
  const [dl] = await Promise.all([page.waitForEvent('download'), page.click('#as-xls')]);
  if (!/AS 19 notes/.test(dl.suggestedFilename())) throw new Error('Unexpected download ' + dl.suggestedFilename());
  step('AS 19 notes shown and downloaded to Excel (' + dl.suggestedFilename() + ')');

  // Summary now shows the real records only
  await tab('summary'); await see('Kitchen equipment loan'); await see('Packing machine lease');
  if (await page.locator('#sm-grid .tabulator-row', { hasText: 'DEMO-LN-001' }).count()) step('summary still lists DEMO rows (shown with the DEMO badge)');
  await shot('l11-summary-after');

  // A Manager does not see Loans and leases
  const ctx2 = await browser.newContext({ viewport: { width: 390, height: 844 } }); const mg = await ctx2.newPage(); watch(mg);
  await mg.goto(BASE); await see('Sign in', mg); await mg.click('#to-first');
  await mg.fill('#li-email', 'demo.manager1@example.com'); await mg.fill('#li-pass', 'Mgr-secret-1'); await mg.fill('#li-pass2', 'Mgr-secret-1');
  await mg.click('button[type=submit]'); await mg.locator('.menu').waitFor();
  const mt = await mg.$$eval('.tile:not(.disabled)', (els) => els.map((e) => e.textContent.trim()));
  if (mt.some((x) => x.includes('Loans and leases'))) throw new Error('Manager sees Loans and leases');
  step('a Manager does not see Loans and leases');
  await ctx2.close();

  // Phone view of the loan window for the Director
  await page.setViewportSize({ width: 390, height: 844 }); await tab('loans');
  await page.locator('#lt-grid .tabulator-row', { hasText: 'Kitchen equipment loan' }).first().click(); await opened();
  await shot('l12-phone-loan'); await closeAll();
  step('loan window on a phone');

  console.log(errors.length ? 'BROWSER ERRORS:\n' + errors.join('\n') : 'No browser errors');
  await browser.close();
  if (errors.length) process.exit(1);
})().catch(async (e) => { console.error('E2E FAILED:', e.message); try { console.error('APP TEXT:', JSON.stringify((await global.__page.innerText('body')).slice(0, 1500))); await global.__page.screenshot({ path: OUT + '/failure.png' }); } catch (x) {} process.exit(1); });
