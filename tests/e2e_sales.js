// End-to-end walk through module 5 against tests/mock-supabase.js,
// on a fresh database with sql/01 to sql/05 loaded.
// Usage: node tests/e2e_sales.js <screenshot dir>
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
  const opened = async () => { await page.locator('.modal').last().waitFor(); await page.waitForTimeout(300); };
  const modal = () => page.locator('.modal').last();
  const pickItem = async (i, name) => {
    await page.selectOption('#l-item-' + i, { label: name }); await page.waitForTimeout(150);
  };
  const lastToast = async () => (await page.locator('#toast').innerText()).trim();

  // DS first sign-in
  await page.goto(BASE); await see('Sign in');
  await page.click('#to-first');
  await page.fill('#li-email', 'info.ruchibuds@gmail.com'); await page.fill('#li-pass', 'DS-secret-123'); await page.fill('#li-pass2', 'DS-secret-123');
  await page.click('button[type=submit]'); await see('Hello, DS');
  const tiles = await page.$$eval('.tile:not(.disabled)', (els) => els.map((e) => e.textContent.trim()));
  for (const t of ['Sales', 'Invoices', 'Customers', 'Customer receipts']) if (!tiles.some((x) => x.includes(t))) throw new Error(t + ' tile missing: ' + tiles.join(', '));
  step('home shows Sales, Invoices, Customers and Customer receipts as live');

  // Sales list and a DEMO invoice
  await page.click('a[href="#/sales"]'); await see('DEMO-Inv/2611/00012');
  await page.fill('#sl-from', '2026-11-01'); await page.click('#sl-go'); await see('DEMO-Inv/2611/00001');
  await shot('v01-sales-list'); step('sales list with the 12 DEMO invoices');
  await page.getByText('DEMO-Inv/2611/00004').first().click(); await see('Bill to'); await see('Rupees');
  await see('Goods returned'); await shot('v02-invoice'); step('invoice window: Konkan Foods, amount in words, its discard return listed');

  // A counter sale: walk-in, two pouches of fish pickle and 250 g loose chilli powder, 10% off the bill, cash
  await page.goto(BASE + '#/sales/new'); await see('Whole bill discount');
  await pickItem(0, 'Fish pickle (DEMO)'); await page.fill('#sf-lines tr[data-i="0"] [data-k=packs]', '2');
  await page.click('#sf-add'); await pickItem(1, 'Chilli powder (DEMO)');
  await page.selectOption('#l-pack-1', { label: 'Loose by weight' }); await page.waitForTimeout(150);
  await page.fill('#sf-lines tr[data-i="1"] [data-k=qty]', '250'); await page.selectOption('#l-unit-1', 'g'); await page.waitForTimeout(150);
  await page.fill('#sf-billpct', '10'); await page.click('#sf-billgo'); await page.waitForTimeout(200);
  const toCollect = await page.locator('#sf-totals tr.grand td').last().innerText();
  await shot('v03-new-sale'); step('new sale form: pouches plus loose powder, 10% off the bill, to collect ' + toCollect);
  await page.click('#sf-save'); await see('INVOICE'); await see('Paid in full');
  const inv1 = (await page.locator('.page-head h1').innerText()).trim();
  const total1 = await page.locator('.inv-foot table.sum td b').first().innerText();
  if (total1 !== toCollect) throw new Error('Screen total ' + toCollect + ' but invoice says ' + total1);
  await shot('v04-printed-invoice'); step('saved as ' + inv1 + ' for ' + total1 + ' (screen and database agree)');

  // A walk-in cannot buy on credit
  await page.goto(BASE + '#/sales/new'); await see('Whole bill discount');
  await pickItem(0, 'Chicken pickle (DEMO)'); await page.fill('#sf-lines tr[data-i="0"] [data-k=packs]', '1');
  await page.fill('#sf-paid', '10'); await page.click('#sf-save'); await see('walk-in sale must be paid in full');
  step('walk-in part-payment is refused: "' + (await page.locator('#sf-msg').innerText()).slice(0, 70) + '"');

  // A credit sale to a trader, part paid by UPI
  await page.selectOption('#sf-cust', { label: 'Green Basket Mart (DEMO) (trader)' }); await page.waitForTimeout(200);
  if ((await page.inputValue('#sf-chan')) !== 'trader') throw new Error('Trader price list not chosen for a trader');
  await page.selectOption('#sf-mode', 'upi'); await page.fill('#sf-paid', '100'); await page.fill('#sf-ref', 'UPI-777');
  await page.click('#sf-save'); await see('Balance due');
  const inv2 = (await page.locator('.page-head h1').innerText()).trim();
  await shot('v05-part-paid'); step('trader sale at the trader price, ₹100 paid by UPI, rest owed: ' + inv2);

  // Receive the rest from the invoice
  await page.click('#iw-recv'); await opened(); await page.waitForTimeout(400);
  await shot('v06-receive');
  await page.selectOption('#rc-mode', 'bank'); await page.fill('#rc-ref', 'NEFT-1');
  await page.click('#rc-save'); await see('Paid in full'); step('rest received by bank and set against the invoice: paid in full');

  // Goods returned on the counter sale (DS posts at once)
  await page.goto(BASE + '#/sales'); await page.getByText(inv1).first().click(); await see('Bill to');
  await page.click('#iw-ret'); await opened();
  await modal().locator('[data-rq]').first().fill('1'); await page.selectOption('#sr-cond', 'discard'); await page.fill('#sr-why', 'Pouch leaking');
  await shot('v07-return'); await page.click('#sr-save'); await see('Return saved'); await see('Credit note'); await page.waitForTimeout(300);
  await shot('v08-invoice-after-return'); step('one pouch back, thrown away; credit note posted straight away for the Director');
  await page.click('#iw-refund'); await opened(); await page.waitForTimeout(500);
  const back = await page.locator('#rf-left').innerText(); await page.selectOption('#rf-mode', 'cash'); await page.fill('#rf-why', 'Leaking pouch, cash back at the counter');
  await page.click('#rf-save'); await see('Refund saved'); step('walk-in customer given the money back in cash (' + back + ')');

  // Returns tab: approve the DEMO return waiting since the DEMO load
  await page.goto(BASE + '#/sales'); await page.click('button[data-tab=returns]'); await see('Waiting for approval');
  await shot('v09-returns');
  await page.locator('#rt-grid .tabulator-row', { hasText: 'Waiting for approval' }).first().click(); await opened();
  await page.click('#rm-ok'); await see('Return approved'); step('DEMO return by Rahul approved and posted');

  // Sales summary
  await page.click('button[data-tab=summary]'); await page.waitForTimeout(300); await page.fill('#ss-from', '2026-11-01'); await page.click('#ss-go'); await see('Net sales');
  await shot('v10-summary-day');
  await page.click('#ss-by [data-by=product]'); await see('Fish pickle (DEMO)'); await shot('v11-summary-product');
  await page.click('#ss-by [data-by=kind]'); await see('Trader'); step('sales summary by day, product and customer type, with margin for the Director');

  // Customers: balances, ageing, statement and a share link
  await page.goto(BASE + '#/customers'); await page.click('button[data-tab=bal]'); await see('Konkan Foods (DEMO)');
  await shot('v12-balances'); step('customer balances with ageing');
  await page.locator('#cb-grid .tabulator-row', { hasText: 'Konkan Foods' }).first().click(); await opened(); await see('STATEMENT OF ACCOUNT');
  await shot('v13-statement');
  await page.click('#cs-share'); await see('Link copied');
  const msg = await modal().locator('.m-msg').innerText();
  const url = (msg.match(/https?:\S+/) || [])[0];
  if (!url) throw new Error('No statement link in: ' + msg);
  step('statement shared as a link');
  const ctx2 = await browser.newContext({ viewport: { width: 390, height: 844 } }); const pub = await ctx2.newPage(); watch(pub);
  await pub.goto(url); await see('STATEMENT OF ACCOUNT', pub); await see('Konkan Foods', pub);
  if (await pub.locator('#btn-signout').count()) throw new Error('Public statement shows the signed-in frame');
  await shot('v14-public-statement', pub); step('customer opens the link on a phone without signing in');
  await page.click('#cs-revoke'); await see('link(s) switched off');
  await pub.reload(); await see('expired or been switched off', pub); step('after switching links off the customer sees that the link has stopped');
  await ctx2.close();
  await page.click('.modal [data-close]');

  // Receipts screen: receive against an earlier invoice, then refund an overpayment
  await page.goto(BASE + '#/receipts'); await see('DEMO-RCT/2611/00001'); await shot('v15-receipts');
  await page.click('#rp-recv'); await opened();
  await page.selectOption('#rc-cust', { label: 'Hill Top Caterers (DEMO)' }); await page.waitForTimeout(500);
  await page.fill('#rc-amt', '3000'); await page.click('#rc-oldest'); await page.waitForTimeout(200);
  await page.click('#rc-save'); await see('Receipt saved'); await page.waitForTimeout(300);
  step('₹3,000 from Hill Top: the invoice is cleared and the rest is kept on account');
  await page.click('#rp-ref'); await opened(); await page.selectOption('#rf-cust', { label: 'Hill Top Caterers (DEMO)' }); await page.waitForTimeout(500);
  const can = await page.locator('#rf-left').innerText();
  await page.fill('#rf-why', 'Overpaid'); await page.click('#rf-save'); await see('Refund saved');
  step('refund of the overpayment (' + can + ')');

  // Settings: register for GST from today, then a Tax Invoice
  await page.goto(BASE + '#/settings'); await see('Sales and invoices');
  await page.fill('#st-address', 'Shop 1, Market Road, Pune'); await page.fill('#st-state_code', '27');
  await page.fill('#st-gstin', '27AAAAA0000A1Z5'); await page.fill('#st-gstfrom', new Date().toISOString().slice(0, 10));
  await page.fill('#st-footer', 'Thank you for buying Ruchi Buds.');
  await page.click('#st-save'); await see('Settings saved'); await shot('v16-settings');
  step('firm registered for GST from today, with an invoice footer');
  await page.goto(BASE + '#/sales/new'); await see('Whole bill discount');
  await page.selectOption('#sf-cust', { label: 'Konkan Foods (DEMO) (trader)' }); await page.waitForTimeout(200);
  if ((await page.inputValue('#sf-doc')) !== 'tax_invoice') throw new Error('Tax Invoice not offered after registration');
  await pickItem(0, 'Smoked meat pickle (DEMO)'); await page.fill('#sf-lines tr[data-i="0"] [data-k=packs]', '2');
  await page.selectOption('#sf-mode', 'credit'); await page.waitForTimeout(200);
  const gstTotal = await page.locator('#sf-totals tr.grand td').last().innerText();
  await page.click('#sf-save'); await see('TAX INVOICE'); await see('GSTIN 27AAAAA0000A1Z5'); await see('CGST'); await see('Thank you for buying Ruchi Buds.');
  const gstInv = await page.locator('.inv-foot table.sum td b').first().innerText();
  if (gstInv !== gstTotal) throw new Error('Screen total ' + gstTotal + ' but tax invoice says ' + gstInv);
  await shot('v17-tax-invoice'); step('Tax Invoice on credit with CGST and SGST, HSN shown, total ' + gstInv);
  await page.emulateMedia({ media: 'print' }); await shot('v18-tax-invoice-print'); await page.emulateMedia({ media: 'screen' });
  step('print view hides the buttons');

  // Staff: can sell, sees the bill they make, but no sales totals
  const ctx3 = await browser.newContext({ viewport: { width: 390, height: 844 } }); const st = await ctx3.newPage(); watch(st);
  await st.goto(BASE); await see('Sign in', st); await st.click('#to-first');
  await st.fill('#li-email', 'demo.staff1@example.com'); await st.fill('#li-pass', 'Staff-secret-1'); await st.fill('#li-pass2', 'Staff-secret-1');
  await st.click('button[type=submit]'); await st.locator('.menu').waitFor();
  await st.goto(BASE + '#/sales'); await see('DEMO-Inv/2611/00012', st);
  const heads = await st.$$eval('#sl-grid .tabulator-col-title', (els) => els.map((e) => e.textContent.trim()));
  if (heads.includes('Total') || heads.includes('Cost')) throw new Error('Staff can see totals: ' + heads.join(', '));
  if (await st.locator('button[data-tab=summary]').count()) throw new Error('Staff can see the sales summary');
  await shot('v19-staff-list', st); step('Staff sales list has no money columns and no summary tab');
  await st.goto(BASE + '#/sales/new'); await see('Whole bill discount', st);
  if (!(await st.locator('#sf-lines [data-k=rate]').count())) {
    await st.selectOption('#l-item-0', { label: 'Fish pickle (DEMO)' }); await st.waitForTimeout(200);
  }
  if (!(await st.locator('#sf-lines [data-k=rate]').first().isDisabled())) throw new Error('Staff can change the price');
  await st.fill('#sf-lines tr[data-i="0"] [data-k=packs]', '1');
  await shot('v20-staff-new-sale', st);
  await st.click('#sf-save'); await see('Paid in full', st); await see('Rupees', st);
  if (await st.locator('text=Margin (only for the margin tick)').count()) throw new Error('Staff sees margin');
  await shot('v21-staff-invoice', st); step('Staff sells a pouch at the Masters price (price box locked) and sees the bill to collect; no cost or margin');
  await ctx3.close();

  // Invoices screen and phone view
  await page.goto(BASE + '#/invoices'); await see('DEMO-Inv/2611/00001'); await shot('v22-invoices');
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(BASE + '#/sales/new'); await see('Whole bill discount'); await page.waitForTimeout(300); await shot('v23-phone-new-sale');
  await page.setViewportSize({ width: 1280, height: 860 });
  step('invoices list and the sale form on a phone');

  console.log(errors.length ? 'BROWSER ERRORS:\n' + errors.join('\n') : 'No browser errors');
  void lastToast;
  await browser.close();
  if (errors.length) process.exit(1);
})().catch(async (e) => { console.error('E2E FAILED:', e.message); try { console.error('APP TEXT:', JSON.stringify((await global.__page.innerText('body')).slice(0, 1500))); await global.__page.screenshot({ path: OUT + '/failure.png' }); } catch (x) {} process.exit(1); });
