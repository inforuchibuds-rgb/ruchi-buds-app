// End-to-end walk through module 10 against tests/mock-supabase.js,
// on a fresh database with sql/01 to sql/10 loaded.
// Usage: node tests/e2e_shop.js <screenshot dir>
'use strict';
const { chromium } = require('playwright');
const path = require('path');
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
  const see = async (t, p) => { await (p || page).getByText(t, { exact: false }).first().waitFor({ timeout: 15000 }); };
  const opened = async (p) => { await (p || page).locator('.modal').last().waitFor(); await (p || page).waitForTimeout(300); };
  const modal = (p) => (p || page).locator('.modal').last();
  const sideways = async (p, what) => { if (await p.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 2)) errors.push('layout: ' + what + ' scrolls sideways on a phone'); };
  const signIn = async (p, email, pass) => {
    await p.goto(BASE); await see('Sign in', p); await p.click('#to-first');
    await p.fill('#li-email', email); await p.fill('#li-pass', pass); await p.fill('#li-pass2', pass);
    await p.click('button[type=submit]'); await p.locator('.menu').waitFor();
  };
  const tab = async (name, p) => { await (p || page).click('.tabs button:has-text("' + name + '")'); await (p || page).waitForTimeout(600); };
  const openOrder = async (no) => { await page.locator('.tabulator-row', { hasText: no }).first().click(); await opened(); };

  // DS opens the shop screen: the DEMO orders
  await signIn(page, 'info.ruchibuds@gmail.com', 'DS-secret-123');
  await page.goto(BASE + '#/shop'); await see('UPI payments to check'); await see('DEMO-ORD/');
  await shot('s01-orders-demo');
  step('Online shop orders: the DEMO orders, with what is to do');

  // Shop set-up: open the shop, UPI ID, alerts for Sales and Manager
  await tab('Shop set-up'); await see('The shop link');
  await page.check('#ss-open'); await page.fill('#ss-upiid', 'ruchibuds@okaxis'); await page.fill('#ss-upiname', 'Ruchi Buds');
  await page.fill('#ss-note', 'Fresh from our kitchen in Kochi. Orders before 2 PM go out the same day.');
  await page.fill('#ss-phone', '98470 00000'); await page.fill('#ss-pickaddr', 'Ruchi Buds kitchen, Kochi');
  for (const c of ['Sales', 'Manager']) await page.locator('label.check', { hasText: c }).locator('input').check();
  await page.click('#ss-form button[type=submit]'); await see('Saved'); await page.waitForTimeout(800);
  await see('The shop is'); await shot('s02-setup');
  step('Shop set-up saved: open, UPI ID, alerts for Sales and Manager; DEMO delivery charges listed');

  // Products online: a photo for the fish pickle
  await tab('Products online'); await see('Free');
  await page.locator('.tabulator-row', { hasText: '200 g bottle' }).filter({ hasText: 'Fish pickle' }).first().click(); await opened();
  await modal().locator('#pm-photo').setInputFiles(path.join(__dirname, '..', 'assets', 'icon-512.png'));
  await modal().locator('#pm-prev img').waitFor();
  await shot('s03-product');
  await modal().locator('#pm-save').click(); await see('Saved');
  await page.waitForTimeout(800); await shot('s04-products');
  step('Products online: photo added; Free / On hold / Total shown');

  // The customer, on a phone, with no sign-in
  const cctx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
  const cu = await cctx.newPage(); watch(cu);
  await cu.goto(BASE + 'shop.html'); await see('Order online', cu); await see('Fish pickle', cu);
  await cu.waitForTimeout(500); await shot('c01-shop-phone', cu); await sideways(cu, 'the shop page');
  const fish = cu.locator('.sf-card', { hasText: 'Fish pickle' }).first();
  await fish.locator('button:has-text("Add to cart")').click(); await fish.locator('[aria-label="One more"]').click();
  await see('2 items', cu);
  await cu.click('#sf-bar a'); await see('Your details', cu);
  await cu.fill('#sf-name', 'Lakshmi Pillai'); await cu.fill('#sf-phone', '98950 12345');
  await cu.fill('#sf-addr', '14 Temple Road, Ernakulam'); await cu.fill('#sf-pin', '682001'); await see('Delivery to 682001', cu);
  await shot('c02-cart', cu); await sideways(cu, 'the cart');
  await cu.click('#sf-go'); await see('Please pay by UPI', cu); await cu.locator('#sf-qr svg').waitFor();
  const orderNo = (await cu.locator('.sf-status small').innerText()).match(/(\S*ORD\/\d{4}\/\d{5})/)[1];
  await shot('c03-pay', cu); await sideways(cu, 'the order page');
  step('Customer orders 2 fish pickles for delivery (₹40 to 682001) and sees the UPI QR: ' + orderNo);
  await cu.fill('#sf-utr', '6331 2345 6789'); await cu.click('#sf-ref button[type=submit]');
  await see('checking your payment', cu); await shot('c04-checking', cu);
  step('Customer enters the UPI reference: waiting for the staff check');

  // A cash-on-delivery order takes the last free chilli powder pouch: then SOLD OUT
  await cu.goto(BASE + 'shop.html'); await see('Chilli powder', cu);
  const chilli = cu.locator('.sf-card', { hasText: 'Chilli powder' }).first();
  await chilli.locator('button:has-text("Add to cart")').click();
  await cu.click('#sf-bar a'); await see('Your details', cu);
  await cu.click('#sf-ful button[data-v="pickup"]'); await cu.check('input[name=sf-pay][value=cod]');
  await cu.click('#sf-go'); await see('Order received', cu); await see('in cash when you pick it up', cu);
  const codNo = (await cu.locator('.sf-status small').innerText()).match(/(\S*ORD\/\d{4}\/\d{5})/)[1];
  await cu.goto(BASE + 'shop.html'); await see('Chilli powder', cu);
  if (!(await cu.locator('.sf-card.out', { hasText: 'Chilli powder' }).count())) throw new Error('Chilli powder should be SOLD OUT');
  await shot('c05-sold-out', cu);
  step('Cash-on-delivery pickup order ' + codNo + ' takes the last free pouch: the shop shows SOLD OUT');

  // Staff: the home screen alert, check the payment, pack, dispatch
  await page.goto(BASE + '#/'); await see('Online shop:'); await see('to pack'); await shot('s05-home-alert');
  step('Home screen: the online shop line and the count on the tile');
  await page.goto(BASE + '#/shop'); await tab('Orders'); await see('UPI payments to check');
  await openOrder(orderNo); await see('Payment found');
  await shot('s06-check-payment');
  await modal().locator('#om-paid').click(); await see('Marked paid');
  await page.waitForTimeout(600); await openOrder(orderNo); await modal().locator('#om-pack').click(); await see('Packed');
  await page.waitForTimeout(600); await openOrder(orderNo); await modal().locator('#om-dispatch').click();
  await opened(); await modal().locator('#cf-ok').click(); await see('Invoice ');
  step('Staff tick Paid, Packed, then Dispatched: the invoice is made');
  await page.waitForTimeout(600);
  // Cash on delivery: dispatch, then the cash
  await openOrder(codNo); await modal().locator('#om-dispatch').click(); await opened(); await modal().locator('#cf-ok').click(); await see('Invoice ');
  await page.waitForTimeout(600); await openOrder(codNo); await see('Cash on delivery'); await shot('s07-cod-cash');
  await modal().locator('#om-cash').click(); await see('Cash recorded');
  step('Cash on delivery: handed over (invoice), then the cash recorded');

  // The customer sees it delivered
  await cu.goto(BASE + 'shop.html#o/' + (await page.evaluate(async (no) => (await RB.rpc('rb_shop_orders', { p_from: null, p_to: null, p_status: 'all' })).find((o) => o.order_no === no).token, orderNo)));
  await see('Thank you!', cu); await see('Invoice', cu); await shot('c06-delivered', cu);
  step('The customer\'s order page shows it delivered, with the invoice number');

  // The invoice
  await page.goto(BASE + '#/invoices'); await see('Lakshmi Pillai');
  step('The invoice is in Invoices');

  // Report and stock
  await page.goto(BASE + '#/shop'); await tab('Report'); await see('Paid by UPI'); await see('By product'); await shot('s08-report');
  step('Online orders report: orders, value, UPI, COD, cancelled; by day and by product');
  await page.goto(BASE + '#/stock'); await tab('Finished goods'); await see('On hold (online)'); await see('Free to sell');
  await shot('s09-stock');
  step('Stock → Finished goods shows Total packs, On hold and Free to sell');

  // The Accountant can run orders but not change the set-up
  const actx = await browser.newContext({ viewport: { width: 390, height: 844 } }); const ac = await actx.newPage(); watch(ac);
  await signIn(ac, 'demo.accounts@example.com', 'Acc-secret-1');
  await ac.goto(BASE + '#/shop'); await see('UPI payments to check', ac);
  await ac.waitForTimeout(500); await shot('a01-orders-phone', ac); await sideways(ac, 'the shop orders screen');
  await tab('Shop set-up', ac); await see('Only a Director or the FC can change the shop set-up', ac);
  if (await ac.locator('#ss-form button[type=submit]').count()) throw new Error('The Accountant can save the shop set-up');
  step('The Accountant runs orders but cannot change the shop set-up');

  console.log(errors.length ? 'BROWSER ERRORS:\n' + errors.join('\n') : 'No browser errors');
  await browser.close();
  if (errors.length) process.exit(1);
})().catch(async (e) => { console.error('E2E FAILED:', e.message); try { console.error('APP TEXT:', JSON.stringify((await global.__page.innerText('body')).slice(0, 1500))); await global.__page.screenshot({ path: OUT + '/failure.png' }); } catch (x) {} process.exit(1); });
