# Ruchi Buds app: Module 5 setup guide

Version 1.1 · 27-Nov-2026 · Module 5: Sales, invoices and AR

> **Already ran version 1.0 of `05_sales_invoices.sql`?** Run the new version once more (step 2). It adds bad debts and keeps everything you entered. Then reload the app.

This update takes about 10 minutes. You paste one file into Supabase. GitHub Pages updates the screens on its own once the pull request is merged.

## What module 5 gives you

- **Sales** (home → Sales):
  - **+ New sale**: choose the customer (Walk-in customer is already chosen) or add a new one with **+ New**. Add items by pack (bottle or pouch), or loose by weight for items sold that way. The price comes from **Masters → Packs and prices** for the customer's price list (retail, trader or online).
  - A discount on any line, as a % or in ₹, or **Whole bill discount** for the same % on every line.
  - **How paid**: cash, UPI, bank or credit. **Amount paid now** can be less than the bill (part paid); the rest is owed. A walk-in sale must be paid in full.
  - **Invoice** (no GST) until the firm is GST registered. From the "GST registered from" date in Settings, **Tax Invoice** (with GST) is offered and chosen for you.
  - Saving opens the invoice, ready to **Print / Save as PDF**.
  - **Sales** list (filters: owed, overdue, on credit, cancelled), **Returns** (with approval) and **Sales summary** by day, by product and by customer type. All download to Excel.
- **The invoice**: word mark, firm details, FSSAI no., Firm Reg. no. (LLPIN after conversion), GSTIN on Tax Invoices, customer and place of supply, each line with HSN (can be hidden), discount, CGST and SGST (or IGST for another state), totals, amount in words, and your footer line. Buttons on it:
  - **Goods returned**: what came back, whether it goes back on the shelf or is thrown away, and why. It becomes a numbered **credit note** (CN/…).
  - **Receive payment**, **Refund the customer** (after a return), **Cancel invoice** (keeps it, marked Cancelled) and, during someone's learning phase, **Delete fully**.
- **Invoices** (home → Invoices): every invoice, with the same window.
- **Customer receipts** (home → Customer receipts):
  - **Receive a payment**: choose the customer, see their open invoices, and set the money against them. **Fill oldest first** does it for you. Money beyond the invoices stays **on account** (an advance) and can be set against later invoices.
  - A balance from before the app (an opening balance) shows as **Earlier balance (not on an invoice)** and can be paid off the same way.
  - **Refund a customer**: pays back a credit note or an overpayment. Only the Accountant, FC and Directors have this.
  - **Customer balances** with ageing: not yet due, 1–30, 31–60, 61–90 and over 90 days, from each invoice's due date.
- **Bad debts** (only the FC and Directors):
  - **Write off as bad debt** on an unpaid invoice, with a reason. The invoice closes, the customer's balance drops, and the amount is charged to **Bad Debt Write-offs**.
  - **Customer receipts → Bad debts** lists every write-off. **Write off an earlier balance** handles an opening balance that is not on an invoice.
  - If the customer pays later, enter the money as a normal receipt. Then tap the write-off and press **Book money recovered**: it counts as other income.
  - Each write-off or recovery can be reversed.
- **Customers** (home → Customers) now has a second tab, **Balances and statements**. Tap a customer for their **ledger and statement**: print it, or **Share a link** that the customer can open on their phone without a password. The link stops after 30 days (Settings), or straight away with **Switch off links**.
- **Settings → Sales and invoices**: whether Masters prices include GST, the line at the bottom of every invoice, and how long statement links work.
- **DEMO data** (21 to 27 November 2026): 12 invoices to retail customers, traders and walk-ins (cash, UPI, bank, credit, part paid, discounts, loose powder, a by-product and a special trader price), 2 customer receipts, 2 posted returns (one thrown away, one back on the shelf and refunded) 1 return waiting for approval, and 1 bad debt (Coastal Delights) with ₹1,000 of it recovered.

## Decisions built in (please check them)

| Topic | What the app does | Why |
|---|---|---|
| Sales and discounts | Sales are posted at full price to **Product Sales** (Retail 60010120, Wholesale for traders 60010115, Online 60010125, by-products 60010130). Discounts go to **Sales Discounts** (60010140). | AS 9, Revenue Recognition. The discount stays visible in the accounts. |
| Cost of sales | Each sale takes the packs out of finished goods at weighted average cost into **Cost of Finished Goods Sold** (70010160). Stock can never go below zero. | AS 2. |
| Customer balances | All go through **Trade Receivables Control** (10020105), per customer. The balances screen and statements come from the books, so they always agree with the trial balance. | Control account rule. |
| Returns | A credit note goes to **Sales Returns and Allowances** (60010135) for the same share of the line, including its discount and GST. Goods back on the shelf return to stock at their cost. Goods thrown away are charged to **Inventory Write-down Expense** (70010150). | AS 9 and AS 2. |
| Who approves returns | Staff and Sales returns wait for a Manager, the Accountant, the FC or a Director. Those people's own returns post straight away. | Spec section 4. |
| Before GST registration | The document is called **Invoice** and carries no GST. | The firm has no GSTIN yet. |
| After GST registration | **Tax Invoice**. Prices in Masters are treated as **including GST** (a ₹100 pouch stays ₹100 to the customer); you can switch this in Settings. CGST + SGST within your state, IGST to another state (from the customer's state code or GSTIN). | GST law. |
| Credit limits | A sale that takes a customer over their credit limit is refused, unless someone with **Sales → Approve** ticks "Allow this sale over the credit limit". | Spec section 8. |
| Price changes | Prices come from Masters. Only people with **Sales → Edit** (Managers and above) can change a price on a sale. | Spec section 8. |
| Who sees money | Staff see the bill they are making, so they can collect it, but no sales totals, balances or costs. Costs and margins show only for the **margin** tick (Accountant, FC, Directors). | Spec section 4. |
| Numbers | Inv/YYMM/00001 for invoices, CN for credit notes, RCT for receipts and RFD for refunds. They run on and never restart. Training entries start TRN-…, DEMO entries DEMO-…. | Spec section 8. |
| Cancel or delete | **Cancel** keeps the invoice, marked Cancelled, and reverses the books and stock. **Delete fully** is only for invoices made by someone in their learning phase; after go-live it leaves a gap in the invoice numbers. | Spec section 4. |
| Bad debts | Written off to **Bad Debt Write-offs** (80080110), off the customer balance. Money recovered later goes to **Other Non-operating Income** (90010135). Only the FC and Directors, with a reason. Numbered BD/… and BDR/…. | AS 9 (revenue stays recognised; the loss is an expense). The month-end provision for doubtful debts comes with module 6. |
| Advances | Money received before an invoice stays in Trade Receivables as a minus balance. | Reclassified as a liability in the reports (module 8). |
| PDF | **Print / Save as PDF** uses the phone's or computer's own print. Choose "Save as PDF" as the printer. | Free, works on every device. |

**For your CA (please ask them):**

1. The provision for doubtful debts (module 6): what % of overdue money to set aside for each ageing band (for example 1–90, 91–180 and over 180 days).
2. Delivery charges are left for the online shop module (module 10).

## Step 1. Take a backup (1 minute)

In the app: **Settings → Backup now (file for restore)**. Keep the file.

## Step 2. Supabase: add the module 5 tables (3 minutes)

1. Open your project at [supabase.com/dashboard](https://supabase.com/dashboard), then **SQL Editor → New query**.
2. Open `sql/05_sales_invoices.sql` from the repository (on GitHub, click the file, then the **Copy raw file** button).
3. Paste it and press **Run**. If Supabase warns about "destructive operations", press **Run this query**. That is expected.
4. You should see **Success. No rows returned**.

The file is safe to run again. Running it again changes nothing and loses nothing.

> **Important:** if `01`, `02`, `03` or `04` is ever run again, run every later file again straight after it, in order (01, 02, 03, 04, 05). Each file resets who may use the database functions, and the later files put their own back.

## Step 3. The screens

Once the pull request is merged into **main**, GitHub Pages publishes the new screens within a couple of minutes. Reload the app. On a phone, close the app fully and open it again.

The home menu now shows **Sales**, **Invoices**, **Customers** and **Customer receipts** without a "Module 5" label.

## Step 4. Masters, settings and access

1. **Masters → Packs and prices**: each pack needs a retail price, and a trader price for traders (if blank, the retail price is used).
2. **Masters → Items**: items sold loose need their **loose price** per kg. Before GST registration, also fill each item's **HSN code** and **GST rate**, so Tax Invoices work from day one.
3. **Customers**: each trader needs a **credit limit** and **credit days** if they buy on credit. Add a **state code** for traders in another state.
4. **Settings → Firm details**: the registered address, state code (Maharashtra is 27), FSSAI no. and Firm Reg. no. all print on invoices. **Settings → Sales and invoices**: write your invoice footer line.
5. **Users → Categories and access**: check **Sales**, **Invoices**, **Customers** and **Customer receipts** for each category. By default Staff can view and add sales; Sales can also edit; Managers can approve returns and allow credit over the limit; AR receives payments; refunds are for the Accountant, FC and Directors. **Write off bad debts** is a new right, held only by the FC and Directors; tick it for another category only if you want them to write off debts.

## Files in this module

| File | What it is | Where it goes |
|---|---|---|
| `sql/05_sales_invoices.sql` | The database for module 5 | Paste into Supabase SQL Editor (step 2) |
| `sales.js`, `invoices.js` | The Sales, Invoices, Customer receipts and statement screens | Already in the repository, served by GitHub Pages |
| `index.html`, `core.js`, `ruchi.css`, `settings.js`, `masters.js` | Updated (loads the new screens, the customer's statement link, invoice and print styles, sales settings, the Customers tab) | The same |
| `docs/module-5-test-checklist.md` | What to tick before sign-off | Read and tick |
| `tests/test_sales.sql`, `tests/e2e_sales.js` | The automatic checks used while building | Not needed in Supabase |

## If something goes wrong

- **"permission denied for function …"** on any screen: run `05_sales_invoices.sql` again (usually because an earlier file was run after it).
- **"Not enough … in stock"**: stock can never go below zero. Check the production batch was entered first, and its date is on or before the sale.
- **"No retail price is set for …"**: add the price in Masters → Packs and prices.
- **"A Tax Invoice needs …"**: fill the GSTIN, "GST registered from", address and state code in Settings, and the item's HSN code and GST rate in Masters.
- **"This takes … over their credit limit"**: take a payment first, or ask a Manager to allow it.
- **"… is locked"**: the month is locked. A Director or the FC unlocks it in Accounts → Month lock, with a reason.
- Anything else: take a screenshot and send it in the project thread.
