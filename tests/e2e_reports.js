// End-to-end walk through module 8 against tests/mock-supabase.js,
// on a fresh database with sql/01 to sql/08 loaded.
// Usage: node tests/e2e_reports.js <screenshot dir>
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
    p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|lookerstudio/.test(m.text())) errors.push('console: ' + m.text()); });
    p.on('dialog', (d) => { errors.push('dialog: ' + d.message()); d.dismiss(); });
  };
  watch(page);
  const shot = (n, p) => (p || page).screenshot({ path: OUT + '/' + n + '.png', fullPage: true });
  const step = (t) => console.log('• ' + t);
  const see = async (t, p) => { await (p || page).getByText(t, { exact: false }).first().waitFor({ timeout: 8000 }); };
  const opened = async (p) => { await (p || page).locator('.modal').last().waitFor(); await (p || page).waitForTimeout(400); };
  const modal = (p) => (p || page).locator('.modal').last();
  const toast = async (t, p) => { await (p || page).locator('#toast', { hasText: t }).waitFor({ timeout: 8000 }); };
  const tab = async (k, p) => { await (p || page).click('.tabs button[data-tab=' + k + ']'); await (p || page).waitForTimeout(700); };
  const noError = async (where, p) => { const t = await (p || page).locator('#tab-body .msg.error').allInnerTexts(); if (t.length) throw new Error(where + ': ' + t.join(' | ')); };
  const showRange = async (from, to, demo) => {
    if (from) await page.fill('#pb-from', from); await page.fill('#pb-to', to);
    if (demo != null) await page.locator('#pb-demo').setChecked(demo);
    await page.click('#pb-go'); await page.waitForTimeout(900);
  };
  const signIn = async (p, email, pass) => {
    await p.goto(BASE); await see('Sign in', p); await p.click('#to-first');
    await p.fill('#li-email', email); await p.fill('#li-pass', pass); await p.fill('#li-pass2', pass);
    await p.click('button[type=submit]'); await p.locator('.menu').waitFor();
  };

  // DS first sign-in: Reports is live on the home menu
  await signIn(page, 'info.ruchibuds@gmail.com', 'DS-secret-123'); await see('Hello, DS');
  const tiles = await page.$$eval('.tile:not(.disabled)', (els) => els.map((e) => e.textContent.trim()));
  if (!tiles.some((x) => x.includes('Reports'))) throw new Error('Reports tile missing: ' + tiles.join(', '));
  step('home shows Reports as live');

  // Dashboard with DEMO entries for November 2026
  await page.click('a[href="#/reports"]'); await see('Sales this month');
  await showRange(null, '2026-11-30', true); await noError('dashboard');
  await see('Gross margin this month'); await see('Top products this month');
  const bars = await page.locator('#ch-month svg rect[rx]').count();
  if (bars < 2) throw new Error('12-month chart has no bars');
  await page.locator('#ch-month g[data-tip]').last().hover(); await page.waitForTimeout(200);
  if (!(await page.locator('#ch-month .chart-tip').isVisible())) throw new Error('Chart hover shows no figures');
  await shot('r01-dashboard'); step('dashboard: tiles, 30-day and 12-month charts with hover figures, top products');

  // Sales report, grouped several ways, with Excel download
  await tab('sales'); await showRange('2026-11-01', '2026-11-30', true); await noError('sales');
  if (!(await page.locator('#sl-body .tabulator-row').count())) throw new Error('No sales rows for November DEMO');
  await page.click('.switch button[data-by=customer_kind]'); await page.waitForTimeout(300); await see('Customer type');
  await page.click('.switch button[data-by=d]'); await page.waitForTimeout(300);
  await shot('r02-sales-by-day');
  const [dl1] = await Promise.all([page.waitForEvent('download'), page.click('#sl-xls')]);
  step('sales report by product, customer type and day; Excel ' + dl1.suggestedFilename());

  // Purchases, stock, customers, loans
  await tab('purch'); await showRange('2026-11-01', '2026-11-30', true); await noError('purchases'); await shot('r03-purchases');
  step('purchases and supplier balances');
  await tab('stock'); await page.waitForTimeout(500); await noError('stock'); await shot('r04-stock');
  step('stock on hand and wastage by stage');
  await tab('cust'); await page.waitForTimeout(500); await noError('customers'); await shot('r05-customers');
  step('customer outstanding and ageing');
  await tab('loans'); await page.waitForTimeout(500); await noError('loans'); await see('DEMO-LN-001'); await shot('r06-loans');
  step('loan and lease balances');

  // Financial statements: balance sheet, P&L, cash flow, notes
  await tab('fs'); await showRange('2026-04-01', '2026-11-30', true); await noError('statements');
  await see('Balance sheet'); await see('Total');
  if (await page.locator('#fs-body .msg.error', { hasText: 'does not balance' }).count()) throw new Error('Balance sheet does not balance');
  await shot('r07-balance-sheet');
  await page.click('.switch button[data-v=pl]'); await page.waitForTimeout(400); await see('Revenue from operations'); await shot('r08-profit-loss');
  await page.click('.switch button[data-v=cf]'); await page.waitForTimeout(800); await see('operating activities');
  const cfText = await page.locator('#fs-body').innerText();
  if (/does not agree|difference of/i.test(cfText)) throw new Error('Cash flow does not agree with cash: ' + cfText.slice(0, 400));
  await shot('r09-cash-flow');
  await page.click('.switch button[data-v=notes]'); await page.waitForTimeout(500); await shot('r10-notes');
  const [dl2] = await Promise.all([page.waitForEvent('download'), page.click('#fs-xls')]);
  step('balance sheet balances, P&L, AS 3 cash flow agrees with cash, notes; Excel ' + dl2.suggestedFilename());

  // Statement lines: add a rule and delete it
  await tab('lines'); await see('Every account and its line');
  await page.click('#ln-add'); await opened();
  await page.fill('#lm-pre', '80050150'); await modal().locator('#lm-line').selectOption('PL_OTH');
  await modal().locator('#lm-save').click(); await toast('Saved'); await page.waitForTimeout(600);
  await page.locator('#ln-map .tabulator-header-filter input').first().fill('80050150'); await page.locator('#ln-map .tabulator-header-filter input').first().press('End'); await page.waitForTimeout(600);
  await page.locator('#ln-map .tabulator-row', { hasText: '80050150' }).first().click(); await opened();
  await modal().locator('#lm-del').click(); await toast('Deleted');
  step('statement-line rule added and deleted');

  // Year-end close: FY 2025-26 has nothing real to close; the preview shows
  await tab('ye'); await see('Year-end close'); await noError('year-end'); await shot('r11-year-end');
  step('year-end close preview for FY 2025-26');

  // Looker Studio link
  await tab('looker'); await see('Weekly copy to Google Sheets');
  await page.fill('#lk-url', 'https://example.com/report'); await page.click('#lk-save'); await toast('lookerstudio');
  await page.fill('#lk-url', 'https://lookerstudio.google.com/reporting/abc123/page/p1'); await page.click('#lk-save'); await toast('Link saved');
  await page.waitForTimeout(700);
  const src = await page.locator('.looker iframe').getAttribute('src');
  if (!/\/embed\/reporting\/abc123/.test(src)) throw new Error('Looker link not turned into an embed link: ' + src);
  await shot('r12-looker'); step('Looker Studio link refused for another site, saved as an embed link');

  // Accountant: sees margins, cannot close the year or change the Looker link
  const ctx3 = await browser.newContext({ viewport: { width: 1280, height: 860 } }); const ac = await ctx3.newPage(); watch(ac);
  await signIn(ac, 'demo.accounts@example.com', 'Acc-secret-1');
  await ac.click('a[href="#/reports"]'); await see('Gross margin this month', ac);
  await ac.click('.tabs button[data-tab=ye]'); await ac.waitForTimeout(800);
  if (await ac.locator('#ye-post').count()) throw new Error('Accountant can close the year');
  await ac.click('.tabs button[data-tab=looker]'); await ac.waitForTimeout(800);
  if (await ac.locator('#lk-save').count()) throw new Error('Accountant can change the Looker link');
  step('Accountant sees margins but cannot close the year or change the Looker link');
  await ctx3.close();

  // A Manager does not see Reports
  const ctx2 = await browser.newContext({ viewport: { width: 390, height: 844 } }); const mg = await ctx2.newPage(); watch(mg);
  await signIn(mg, 'demo.manager1@example.com', 'Mgr-secret-1');
  const mt = await mg.$$eval('.tile:not(.disabled)', (els) => els.map((e) => e.textContent.trim()));
  if (mt.some((x) => x.includes('Reports'))) throw new Error('Manager sees Reports');
  step('a Manager does not see Reports');
  await ctx2.close();

  // Phone view of the dashboard and balance sheet
  await page.setViewportSize({ width: 390, height: 844 }); await tab('dash'); await page.waitForTimeout(800);
  await shot('r13-phone-dashboard');
  await tab('fs'); await page.click('.switch button[data-v=bs]'); await page.waitForTimeout(500); await shot('r14-phone-balance-sheet');
  const wide = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 2);
  if (wide) errors.push('layout: the page scrolls sideways on a phone');
  step('dashboard and balance sheet on a phone');

  console.log(errors.length ? 'BROWSER ERRORS:\n' + errors.join('\n') : 'No browser errors');
  await browser.close();
  if (errors.length) process.exit(1);
})().catch(async (e) => { console.error('E2E FAILED:', e.message); try { console.error('APP TEXT:', JSON.stringify((await global.__page.innerText('body')).slice(0, 1500))); await global.__page.screenshot({ path: OUT + '/failure.png' }); } catch (x) {} process.exit(1); });
