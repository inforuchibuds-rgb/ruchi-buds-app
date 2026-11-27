// End-to-end walk through module 2 against tests/mock-supabase.js,
// on a fresh database with 01_core_users.sql and 02_masters.sql.
// Usage: node tests/e2e_masters.js <screenshot dir>
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
  const see = async (t) => { await page.getByText(t, { exact: false }).first().waitFor({ timeout: 6000 }); };
  const modal = () => page.locator('.modal').last();
  const opened = async () => { await page.locator('.modal').last().waitFor(); await page.waitForTimeout(150); };

  // DS first sign-in
  await page.goto(BASE); await see('Sign in');
  await page.click('#to-first');
  await page.fill('#li-email', 'info.ruchibuds@gmail.com'); await page.fill('#li-pass', 'DS-secret-123'); await page.fill('#li-pass2', 'DS-secret-123');
  await page.click('button[type=submit]'); await see('Hello, DS');
  const tiles = await page.$$eval('.tile:not(.disabled)', (els) => els.map((e) => e.textContent.trim()));
  console.log('  live tiles:', tiles.join(' | '));
  for (const t of ['Masters', 'Accounts and journals', 'Customers', 'Suppliers']) if (!tiles.some((x) => x.includes(t))) throw new Error('Tile missing: ' + t);
  await shot('m01-home'); step('home shows the four module 2 screens');

  // Masters: items
  await page.click('a[href="#/masters"]'); await see('Fish pickle (DEMO)'); await shot('m02-items'); step('items list with DEMO items');
  await page.click('#it-add'); await opened();
  await page.fill('#i-name', 'Prawns'); await page.selectOption('#i-kind', 'raw'); await page.fill('#i-stages', 'Clean, Devein, Fry');
  await shot('m03-item-form'); await page.click('#i-save'); await see('Item saved'); await see('RM0001'); step('added raw item Prawns (RM0001) with stages');
  await page.click('#it-add'); await opened();
  await page.fill('#i-name', 'Prawn pickle'); await page.selectOption('#i-kind', 'finished'); await page.fill('#i-hsn', '2001'); await page.fill('#i-gst', '12');
  await page.click('#i-save'); await see('FG0001'); step('added finished item Prawn pickle (FG0001)');
  await page.click('#it-add'); await opened();
  await page.fill('#i-name', 'Bones'); await page.selectOption('#i-kind', 'byproduct'); await page.click('#i-save');
  await see('Sellable or Discarded'); await page.click('.modal [data-close]'); step('by-product without Sellable/Discarded is refused');

  // Packs and prices
  await page.click('button[data-tab=packs]'); await see('Products in packs');
  await page.click('#pt-add'); await opened(); await page.fill('#pt-name', '200 g bottle'); await page.click('#pt-save'); await see('Pack type saved'); step('added pack type 200 g bottle');
  await page.click('#pp-add'); await opened();
  await page.selectOption('#pp-item', { label: 'Prawn pickle' }); await page.selectOption('#pp-pack', { label: '200 g bottle' });
  await page.fill('#pp-qty', '180'); await page.fill('#pp-r', '320'); await page.fill('#pp-t', '280');
  await page.click('#pp-save'); await see('₹320.00'); await shot('m04-packs'); step('Prawn pickle 180 g in a 200 g bottle at ₹320 retail');

  // Departments: rename from a date, merge, undo
  await page.click('button[data-tab=depts]'); await see('Kitchen and production');
  await page.getByText('Administration', { exact: true }).first().click(); await opened();
  await page.fill('#rn-name', 'Office and admin'); await page.check('input[name=rn-scope][value=date]'); await page.fill('#rn-date', '2026-11-01');
  await page.click('#rn-go'); await see('Renamed'); await see('Office and admin');
  await page.getByText('Trade sales', { exact: true }).first().click(); await opened();
  await page.selectOption('#mg-into', { label: 'CC002 Retail counter' });
  await page.click('#mg-go'); await page.click('#cf-ok'); await see('Merged into CC002'); await shot('m05-departments');
  await page.getByText('Merged into CC002').first().click(); await opened();
  await shot('m06-department-history');
  await page.click('[data-undo]'); await see('Undone'); step('renamed CC005 from 01-Nov-2026, merged CC003 into CC002, then undid the merge');

  // Customers
  await page.goto(BASE + '#/settings'); await see('Firm details');
  await page.check('[data-trader=gstin]'); await page.click('#st-save'); await see('Settings saved');
  await page.goto(BASE + '#/customers'); await see('Sai Provision Store (DEMO)');
  await page.click('#cu-add'); await opened();
  await page.selectOption('#c-kind', 'trader'); await page.fill('#c-name', 'Mumbai Pickle Mart'); await page.fill('#c-phone', '9876543210');
  await page.click('#c-save'); await see('gstin is required');
  await page.fill('#c-gstin', '27abcde1234f1z5'); await page.fill('#c-climit', '25000'); await page.fill('#c-cdays', '15');
  await page.click('#c-save'); await see('Customer saved'); await see('C00001'); step('trader needs GSTIN (ticked in Settings); saved as C00001');
  await page.click('#cu-promo'); await page.waitForTimeout(300);
  const promo = await page.$$eval('#cu-grid .tabulator-row', (r) => r.length);
  console.log('  promotions list rows:', promo); await shot('m07-customers-promotions');
  await page.click('#cu-promo');

  // Suppliers
  await page.goto(BASE + '#/suppliers'); await see('Raju Koli');
  await page.click('#su-add'); await opened();
  await page.fill('#s-name', 'Vinod Koli'); await page.selectOption('#s-kind', 'fisherman'); await page.check('#s-nobill');
  await page.click('#s-save'); await see('S00001'); await shot('m08-suppliers'); step('added fisherman supplier S00001');

  // Accounts and journals
  await page.goto(BASE + '#/accounts'); await see('Opening capital in cash'); await shot('m09-journals'); step('journals list shows DEMO journals');
  // Post the DEMO draft (entered by the demo Accountant)
  await page.getByText('Mobile phone recharge').first().click(); await opened();
  await page.click('#jm-post'); await see('Posted'); step('DS posted the DEMO draft entered by someone else');
  // New journal by DS
  await page.click('#jl-new'); await opened();
  await page.fill('#je-narr', 'Electricity bill for November, paid in cash');
  const acc = page.locator('[data-f=account]');
  await acc.nth(0).fill('80020110 Utilities'); await acc.nth(0).dispatchEvent('change');
  await page.locator('[data-f=debit]').nth(0).fill('850');
  await acc.nth(1).fill('10010110 Cash on Hand'); await acc.nth(1).dispatchEvent('change');
  await page.locator('[data-f=credit]').nth(1).fill('800');
  await see('Difference ₹50.00');
  await page.locator('[data-f=credit]').nth(1).fill('850'); await see('Balanced'); await shot('m10-journal-form');
  await page.click('#je-save'); await see('Draft saved'); await see('someone else with approval rights posts it');
  await shot('m11-journal-own-draft'); step('DS saved a balanced draft; the screen says someone else must post it');
  await page.click('.modal [data-close]');
  // Stock account is refused; AR needs the customer
  await page.click('#jl-new'); await opened();
  await page.fill('#je-narr', 'Opening balance owed by Mumbai Pickle Mart');
  await acc.nth(0).fill('10020105 Trade Receivables Control'); await acc.nth(0).dispatchEvent('change');
  await page.locator('[data-f=debit]').nth(0).fill('2500');
  await acc.nth(1).fill('97010105 Opening Balance Migration Clearing'); await acc.nth(1).dispatchEvent('change');
  await page.locator('[data-f=credit]').nth(1).fill('2500');
  await page.click('#je-save'); await see('needs the customer');
  await page.selectOption('[data-party=customer_id]', { label: 'C00001 Mumbai Pickle Mart' });
  await page.click('#je-save'); await see('Draft saved'); step('receivable line asks for the customer');
  await page.click('.modal [data-close]');

  // Turn off "second person" to post own journals, then post both drafts
  await page.click('button[data-tab=months]'); await see('Ledger settings');
  await page.uncheck('#ls-second'); await page.click('#ls-save'); await see('Ledger settings saved');
  await page.click('button[data-tab=journals]'); await see('Electricity bill for November');
  await page.getByText('Electricity bill for November').first().click(); await opened();
  await page.click('#jm-post'); await see('Posted as TRN/');
  await page.getByText('Opening balance owed by Mumbai').first().click(); await opened();
  await page.click('#jm-post'); await see('Posted as TRN/'); step('posted both journals as TRN/YYMM/nnnnn (training series)');
  // Reverse the electricity bill
  await page.getByText('Electricity bill for November').first().click(); await opened();
  await page.click('#jm-rev'); await opened(); await page.fill('#rv-why', 'Bill belongs to December'); await page.click('#rv-go'); await see('Reversed');
  await see('Reversal of TRN/'); step('reversed the electricity bill');
  // Reverse and correct: the receivable was ₹2,400, not ₹2,500
  await page.getByText('Opening balance owed by Mumbai').first().click(); await opened();
  await page.click('#jm-correct'); await opened(); await page.fill('#rc-why', 'Amount was ₹2,400'); await shot('m11a-reverse-and-correct');
  await page.click('#rc-go'); await see('Now correct the copy'); await see('Correct the copy of TRN/');
  if ((await page.locator('[data-party=customer_id]').inputValue()) === '') throw new Error('Copy lost the customer');
  await page.locator('[data-f=debit]').nth(0).fill('2400'); await page.locator('[data-f=credit]').nth(1).fill('2400'); await see('Balanced');
  await shot('m11b-correct-the-copy');
  await page.click('#je-save'); await see('Draft saved'); await see('Copied from TRN/');
  await page.click('#jm-post'); await see('Posted as TRN/'); step('Reverse and correct: reversed, then the corrected copy saved and posted');
  // Clone the (reversed) electricity bill into a new draft
  await page.getByText('Electricity bill for November').first().click(); await opened();
  await see('Copies:').catch(() => {});
  await page.click('#jm-copy'); await see('Copy of TRN/');
  if ((await page.locator('#je-narr').inputValue()) !== 'Electricity bill for November, paid in cash') throw new Error('Clone did not copy the narration');
  await page.fill('#je-narr', 'Electricity bill for December, paid in cash'); await shot('m11c-clone');
  await page.click('#je-save'); await see('Draft saved'); await see('Copied from TRN/'); await shot('m11d-clone-draft');
  await page.click('#jm-post'); await see('Posted as TRN/'); step('Clone: a copy of a journal saved as a new draft and posted');
  await page.click('button[data-tab=months]'); await see('Ledger settings');
  await page.check('#ls-second'); await page.click('#ls-save'); await see('Ledger settings saved');

  // Trial balance and ledger
  await page.click('button[data-tab=tb]'); await see('Balanced'); await shot('m12-trial-balance'); step('trial balance is balanced');
  await page.getByText('Trade Receivables Control').first().click(); await see('Opening balance owed by Mumbai');
  await shot('m13-ledger'); step('ledger opens from the trial balance');

  // Chart of accounts
  await page.click('button[data-tab=coa]'); await see('Petty Cash');
  const shownRows = await page.$$eval('#co-grid .tabulator-row', (r) => r.length);
  const codeFilter = page.locator('#co-grid .tabulator-header-filter input').first();
  await codeFilter.fill('200201'); await page.waitForTimeout(400);
  if (await page.getByText('Right-of-use Assets - Property').count()) throw new Error('ROU account should be hidden');
  await page.check('#co-hidden'); await see('Right-of-use Assets - Property'); await shot('m14-coa');
  await page.uncheck('#co-hidden'); await codeFilter.fill('');
  step('chart of accounts: Indian-AS view hides IFRS-only accounts (' + shownRows + ' rows on page 1)');
  await page.click('button[data-tab=rules]'); await see('Goods received: raw materials'); await shot('m15-posting-rules'); step('posting rules listed');

  // Month lock
  await page.click('button[data-tab=months]'); await see('Month lock');
  await page.locator('tr', { hasText: 'Oct-2026' }).locator('[data-lock]').click(); await page.click('#cf-ok'); await see('Month locked');
  await shot('m16-month-lock');
  await page.click('button[data-tab=journals]'); await see('Opening capital in cash');
  await page.click('#jl-new'); await opened();
  await page.fill('#je-date', '2026-10-20'); await page.fill('#je-narr', 'Late October bill');
  await acc.nth(0).fill('80020110 Utilities'); await acc.nth(0).dispatchEvent('change'); await page.locator('[data-f=debit]').nth(0).fill('10');
  await acc.nth(1).fill('10010110 Cash on Hand'); await acc.nth(1).dispatchEvent('change'); await page.locator('[data-f=credit]').nth(1).fill('10');
  await page.click('#je-save'); await see('Oct-2026 is locked'); await shot('m17-locked-month-refused');
  await page.click('.modal [data-close]'); step('journal dated in locked October is refused');

  // Audit log
  await page.goto(BASE + '#/audit'); await see('Posted journal'); await shot('m18-audit'); step('audit log shows postings');

  // Phone view
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(BASE + '#/masters'); await see('Fish pickle (DEMO)'); await shot('m19-phone-items');
  await page.goto(BASE + '#/accounts'); await see('Opening capital in cash'); await shot('m20-phone-journals');
  await page.setViewportSize({ width: 1280, height: 860 });

  // Remove demo data
  await page.goto(BASE + '#/settings'); await see('Demo data');
  await page.click('#dm-go'); await page.fill('#cf-word', 'REMOVE DEMO'); await page.click('#cf-yes'); await see('DEMO records removed');
  await page.goto(BASE + '#/masters'); await see('Prawn pickle');
  if (await page.getByText('Fish pickle (DEMO)').count()) throw new Error('DEMO items still shown');
  step('Remove demo data clears DEMO items and journals; real ones stay');

  console.log(errors.length ? 'BROWSER ERRORS:\n' + errors.join('\n') : 'No browser errors');
  await browser.close();
})().catch(async (e) => { console.error('E2E FAILED:', e.message); try { console.error('APP TEXT:', JSON.stringify((await global.__page.innerText('body')).slice(0, 1500))); await global.__page.screenshot({ path: OUT + '/failure.png' }); } catch (x) {} process.exit(1); });
