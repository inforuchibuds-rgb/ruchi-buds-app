// End-to-end check of the WhatsApp and email share buttons, against tests/mock-supabase.js
// on a freshly loaded database (sql/01-10 with the demo data).
// Usage: node tests/e2e_share.js <screenshot dir>
'use strict';
const { chromium } = require('playwright');
const OUT = process.argv[2] || '.';
const BASE = 'http://localhost:8787/';

(async () => {
  const browser = await chromium.launch();
  const errors = [];
  const page = await (await browser.newContext({ viewport: { width: 1280, height: 860 } })).newPage();
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  const shot = (n) => page.screenshot({ path: OUT + '/' + n + '.png', fullPage: true });
  const step = (t) => console.log('• ' + t);
  const see = (t) => page.getByText(t, { exact: false }).first().waitFor({ timeout: 6000 });
  const hrefs = async (sel) => { await page.locator(sel + ' a').first().waitFor({ timeout: 6000 }); return page.$$eval(sel + ' a', (as) => as.map((a) => a.getAttribute('href'))); };
  const expect = (ok, what) => { if (!ok) throw new Error('Expected: ' + what); };
  const text = (url) => decodeURIComponent((url.split(/[?&](?:text|body)=/)[1] || '').split('&')[0]);

  try {
    await page.goto(BASE); await see('Sign in');
    await page.click('#to-first');
    await page.fill('#li-email', 'info.ruchibuds@gmail.com'); await page.fill('#li-pass', 'DS-secret-123'); await page.fill('#li-pass2', 'DS-secret-123');
    await page.click('button[type=submit]'); await see('Hello, DS');

    // 1. User added: WhatsApp to the phone typed, email to the email typed.
    await page.goto(BASE + '#/users'); await see('Demo Director Two');
    await page.click('#u-add'); await page.waitForTimeout(150);
    await page.fill('#au-email', 'new.cook@example.com'); await page.fill('#au-name', 'Meena Cook'); await page.fill('#au-phone', '098765 43210');
    await page.selectOption('#au-cat', { label: 'Staff' });
    await page.click('#au button[type=submit]'); await see('User added');
    let h = await hrefs('.modal .actions');
    expect(h[0].startsWith('https://wa.me/919876543210?text='), 'WhatsApp to 919876543210, got ' + h[0]);
    expect(/First time here\? Set up your password/.test(text(h[0])) && /new\.cook@example\.com/.test(text(h[0])), 'sign-in steps in the WhatsApp text');
    expect(text(h[0]).includes('http://localhost:8787/'), 'app link in the text');
    expect(h[1].startsWith('mailto:new.cook@example.com?subject=Your%20Ruchi%20Buds%20app%20login&body='), 'email to new.cook, got ' + h[1]);
    await shot('sh-01-user-added'); step('User added: WhatsApp and email with the sign-in steps');
    await page.click('#au-ok'); await see('Meena Cook');

    // 2. Invited user: send the steps again.
    await page.getByText('Meena Cook').first().click(); await see('Send them the sign-in steps again');
    h = await hrefs('.modal .msg.info .actions');
    expect(h[0].startsWith('https://wa.me/919876543210?text='), 'resend WhatsApp');
    await shot('sh-02-invited-resend'); step('Invited user: resend buttons');
    await page.click('.modal [data-close]');

    // 3. Invoice: WhatsApp to the bill phone.
    await page.goto(BASE + '#/invoices/1'); await see('Bill to');
    h = await hrefs('#iw-share');
    expect(h[0].startsWith('https://wa.me/919810000001?text='), 'invoice WhatsApp to the customer, got ' + h[0]);
    expect(/DEMO-Inv\/2611\/00001/.test(text(h[0])), 'invoice number in the text');
    expect(h[1].startsWith('mailto:?subject='), 'email with no address on file opens blank');
    await shot('sh-03-invoice'); step('Invoice: WhatsApp and email');
    // No phone on file: WhatsApp opens and asks who to send it to.
    await page.goto(BASE + '#/invoices/2'); await see('Bill to');
    h = await hrefs('#iw-share');
    expect(h[0].startsWith('https://wa.me/?text='), 'no number: plain wa.me, got ' + h[0]);
    step('Invoice with no phone: WhatsApp asks for the contact');

    // 4. Statement link.
    await page.goto(BASE + '#/customers'); await page.click('button[data-tab=bal]'); await see('Konkan Foods (DEMO)');
    await page.getByText('Konkan Foods (DEMO)').first().click(); await see('Ledger and statement');
    await page.click('#cs-share'); await see('Link copied');
    h = await hrefs('.modal .m-msg .actions');
    expect(/#\/s\//.test(text(h[0])), 'statement link in the WhatsApp text');
    await shot('sh-04-statement'); step('Statement: share the link by WhatsApp or email');
    await page.click('.modal [data-close]');

    // 5. Customer receipt.
    await page.goto(BASE + '#/receipts'); await see('DEMO-RCT/2611/00001');
    await page.getByText('DEMO-RCT/2611/00001').first().click();
    h = await hrefs('#rm-share');
    expect(/we have received/.test(text(h[0])), 'receipt text');
    await shot('sh-05-receipt'); step('Receipt: thank-you message');
    await page.click('.modal [data-close]');

    // 6. Purchase order and supplier payment.
    await page.goto(BASE + '#/purchases/2'); await see('Match: order');
    await see('Send order on WhatsApp');
    h = await page.$$eval('a.btn.wa', (as) => as.map((a) => a.getAttribute('href')));
    expect(h[0].startsWith('https://wa.me/919830000008?text='), 'PO to the supplier phone, got ' + h[0]);
    expect(/DEMO-PO\/2611\/00002/.test(text(h[0])) && /1\. /.test(text(h[0])), 'PO number and lines in the text');
    await shot('sh-06-po'); step('Purchase order: send to the supplier');
    await page.goto(BASE + '#/purchases'); await page.click('button[data-tab=payments]');
    await see('DEMO-PAY/2611/00001'); await page.getByText('DEMO-PAY/2611/00001').first().click();
    h = await hrefs('#pm-share');
    expect(/has paid you/.test(text(h[0])), 'payment advice text');
    await shot('sh-07-payment'); step('Supplier payment: payment advice');
    await page.click('.modal [data-close]');

    // 7. Shop link.
    await page.goto(BASE + '#/shop'); await page.click('button[data-tab=setup]').catch(() => {});
    await see('The shop link');
    h = await page.$$eval('a.btn.wa', (as) => as.map((a) => a.getAttribute('href')));
    expect(h[0].startsWith('https://wa.me/?text=Order%20Ruchi%20Buds'), 'shop link WhatsApp');
    step('Shop link: WhatsApp and email');

    if (errors.length) { console.log('BROWSER ERRORS:\n' + errors.join('\n')); process.exitCode = 1; } else console.log('No browser errors');
  } catch (e) {
    console.log('E2E FAILED: ' + e.message);
    try { console.log('APP TEXT: ' + JSON.stringify((await page.innerText('body')).slice(0, 1200))); } catch (x) { /* ignore */ }
    process.exitCode = 1;
  } finally { await browser.close(); }
})();
