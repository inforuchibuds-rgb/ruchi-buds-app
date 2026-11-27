// =====================================================================
// RUCHI BUDS APP · help.js · Version 1.0 · 27-Nov-2026
// The short tip behind the "? Help" button on each screen. Plain words,
// a few lines each. Change the text here; nothing else needs to change.
// =====================================================================
(function () {
  'use strict';
  const COMMON = '<p class="muted">On every screen: <b>‹ Back</b> and <b>⌂ Home</b> move around, <b>⟳ Refresh</b> reloads the figures, <b>🖨 Print</b> and <b>⬇ Excel</b> take what you see, ' +
    '<b>🔍 Search</b> finds any invoice, purchase, journal, customer or supplier, and <b>🙈 Hide</b> blurs the screen. Tap the column titles to sort, and type in the boxes under them to filter.</p>';

  RB.HELP = {
    purchases: ['Purchases',
      'Order from a supplier (<b>+ New order</b>), receive the goods, enter the supplier\'s bill, then pay. Each step moves stock and posts to the books by itself.',
      'No order? Use <b>+ Direct purchase</b>. Large direct purchases wait for approval.',
      'Open a purchase to receive goods, enter the bill, pay, return goods or reverse it. Mistakes are reversed, never edited.'],
    suppliers: ['Suppliers',
      'Fishermen, farmers, shops and companies you buy from. Tap a supplier to change their details or open their ledger.',
      'The balance owed comes from Purchases and Cash, bank and expenses.'],
    stock: ['Stock',
      'What is on hand, item by item, at cost. Counts, wastage, write-downs and adjustments are entered here.',
      'Stock only moves through Purchases, Production, Sales and these stock steps, so stock and the books always agree.'],
    production: ['Production',
      'Each batch takes raw materials in and gives finished goods (and by-products) out. Costs follow the stock valuation set in Settings.',
      'Open a batch to see its inputs, outputs and cost, or to reverse it.'],
    sales: ['Sales',
      '<b>+ New sale</b> makes an invoice for a retail, trader or online customer. Returns and the sales summary are on their own tabs.',
      'Open a sale to print, share, receive payment, take a return or cancel it.'],
    invoices: ['Invoices',
      'Every invoice with what is still owed. Tap one to print it, send it, receive a payment or cancel it.',
      '<b>Receive a payment</b> records money from a customer against one or more invoices.'],
    customers: ['Customers',
      'Retail and trader customers. Tap a customer to see or change them. The Promotions list shows only those who agreed to messages.',
      '<b>Balances and statements</b> shows what each customer owes, with a statement you can print or send.'],
    receipts: ['Customer receipts',
      'Money received from customers, and refunds. Each receipt is matched to invoices. Reverse a receipt that was entered by mistake.'],
    cash_bank: ['Cash, bank and expenses',
      'Expenses with their bills and photos, money moved between cash and bank, bank reconciliation, and the month-end steps.',
      'Run the month-end steps in order once a month has ended. Each can be reversed with a reason and run again.'],
    loans: ['Loans and leases',
      'Loans taken, finance leases and operating leases (AS 19) with their schedules. Interest, rent and depreciation are posted by the monthly run.',
      'Run the loans and leases month-end before step 1 in Cash, bank and expenses.'],
    masters: ['Masters',
      'Items, packs and prices, departments and units. Changes here affect new entries only.',
      'Renaming or merging a department keeps its history, and can be undone.'],
    accounts: ['Accounts and journals',
      '<b>Journals</b>: every entry from every screen. <b>+ New journal</b> saves a draft that someone else posts. Open a journal to post, <b>Reverse</b>, <b>Reverse and correct</b> or <b>Clone</b> it.',
      '<b>Trial balance</b> and <b>Account ledger</b> for any dates. <b>Month lock</b> stops changes to a closed month.'],
    reports: ['Reports',
      'The dashboard, financial statements (balance sheet, profit and loss, cash flow with notes), sales and purchase reports, and the year-end close.',
      'Pick the dates at the top. Print or download any report.'],
    users: ['Users',
      'Invite people, choose their category and learning phase, reset passwords, and tick what each category may do.',
      'Directors and the FC always keep full access.'],
    settings: ['Settings',
      'Firm details, partners and their shares, GST, approval limits, wrong-password limit, automatic sign-out, backups and demo data.'],
    audit: ['Audit log',
      'Every change, who made it and when. Filter by date, person or action. Nothing here can be changed or deleted.'],
    restore: ['Restore',
      'Put back data from a backup file, with a second person\'s approval. Try it on a test copy first.'],
  };

  RB.showHelp = () => {
    const name = location.hash.replace(/^#\/?/, '').split('/')[0];
    const h = RB.HELP[name];
    const title = h ? h[0] : 'Help';
    const body = h ? h.slice(1).map((t) => '<p>' + t + '</p>').join('') : '<p>Tap a tile on the home menu to open a screen.</p>';
    RB.modal('<h2>' + RB.esc(title) + ': how it works</h2>' + body + COMMON +
      '<div class="actions"><button class="primary" data-close>Got it</button></div>');
  };
})();
