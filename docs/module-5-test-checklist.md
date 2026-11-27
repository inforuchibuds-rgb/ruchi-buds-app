# Ruchi Buds app: Module 5 test checklist

Version 1.0 · 27-Nov-2026

Tick each line on the real app before signing off module 5. You need DS's login and a second login. Move the module 1 test user to **Staff** for part C and to **Manager** for part D.

**Sign-off gate:** a cash sale, a credit sale and a part-paid sale each print a correct invoice; a return becomes a credit note and the stock comes back; a customer payment clears an invoice; customer balances, the statement and Trade Receivables in the trial balance agree.

## A. DEMO data

- [ ] Home shows **Sales**, **Invoices**, **Customers** and **Customer receipts**. **Sales** lists 12 DEMO invoices (DEMO-Inv/2611/00001 to 00012), each with an orange **DEMO** badge. Set **From** to 1-Nov-2026 if they are not all showing.
- [ ] Open **DEMO-Inv/2611/00004** (Konkan Foods, on credit). It shows the lines, the discount, the amount in words and **Balance due**. Below it, the credit note for 2 pouches thrown away.
- [ ] **Sales → Returns**: one return by Rahul waits for approval; two are posted.
- [ ] **Customer receipts** lists DEMO-RCT/2611/00001 and 00002 and the refund DEMO-RFD/2611/00001.

## B. As DS: selling

- [ ] **+ New sale** with Walk-in customer: 2 pouches of a pickle and 250 g of a powder sold loose. The price fills in from Masters. Type 10 in **Whole bill discount** and press **Apply**. **To collect** shows the total. Save: a **TRN-Inv/** invoice opens and its total matches.
- [ ] **Print / Save as PDF**: the print preview shows only the invoice (no buttons), with the word mark, FSSAI no., Firm Reg. no. and the amount in words. Save it as a PDF.
- [ ] A walk-in sale with **Amount paid now** less than the bill is refused ("A walk-in sale must be paid in full").
- [ ] A sale to a trader picks the **Trader** price list. Pay ₹100 by UPI now: the invoice shows **Balance due** for the rest, and a due date from the trader's credit days.
- [ ] A credit sale that takes a trader over their credit limit is refused. Tick **Allow this sale over the customer's credit limit** and it saves.
- [ ] Change a price on a sale line: DS can. (In part C, Staff cannot.)

## C. As Staff

- [ ] Staff can make a sale. The price boxes are locked. They see the bill and **To collect**, and the invoice after saving.
- [ ] The Sales list has **no Total or Owed columns** and **no Sales summary** tab. There is no margin anywhere.
- [ ] Staff enter a return on their invoice (**Goods returned**): it shows **Waiting for approval**, with no credit note number yet.

## D. As Manager

- [ ] **Sales → Returns**: open the Staff return and **Approve and post**. It gets a **CN/** number. If it went back on the shelf, **Stock → Finished goods** shows the packs back.
- [ ] Refuse the DEMO return by Rahul, with a reason. It shows **Refused**.
- [ ] The Manager sees sales totals but **no costs** or margins.

## E. As DS: money in, returns and refunds

- [ ] From the part-paid invoice, **Receive payment**: the rest by bank. The invoice now shows **Paid in full**, and the receipt is listed under **Payments set against this invoice**.
- [ ] **Customer receipts → Receive a payment** from a trader for more than they owe. Press **Fill oldest first**. Save. The extra shows as **On account**. Tap the receipt and **Set against invoices** later.
- [ ] **Refund a customer** for that extra. A refund more than the customer has with us is refused.
- [ ] On the walk-in invoice, **Goods returned** for one pouch, thrown away. DS's return posts at once. Press **Refund the customer** and give the money back in cash.
- [ ] **Cancel invoice** on an invoice with no payments or returns: it stays in the list marked **Cancelled**, and the packs are back in stock. An invoice with a customer receipt set against it cannot be cancelled until that receipt is reversed.

## F. Customer balances and statements

- [ ] **Customers → Balances and statements**: each customer's balance, split into not yet due, 1–30, 31–60, 61–90 and over 90 days. The total row adds up.
- [ ] Tap a customer: their ledger and statement, with opening balance, every invoice, payment and credit note, a running balance and the unpaid invoices. **Print / Save as PDF** prints only the statement.
- [ ] **Share a link**: the link is copied. Open it on a phone where you are not signed in: the customer's statement shows, and nothing else.
- [ ] **Switch off links**, then reload the link on the phone: it says the link has expired or been switched off.

## G. GST (only once the firm has a GSTIN; otherwise try it in training and set it back)

- [ ] **Settings**: fill the GSTIN, **GST registered from**, address and state code, and an invoice footer. Save.
- [ ] **+ New sale** dated on or after that date offers **Tax Invoice (with GST)**. Dated before, only **Invoice (no GST)**.
- [ ] A Tax Invoice shows **TAX INVOICE**, the firm's GSTIN, place of supply, HSN codes, and CGST and SGST at half the rate each. A customer with another state's code gets IGST instead.

## H. The books

- [ ] **Accounts → Trial balance**: debits equal credits. **Trade Receivables Control** equals the total on Balances and statements. **Finished Goods Inventory** equals the Stock screen.
- [ ] **Sales → Sales summary** (by day, by product, by customer type) shows net sales, GST, cost and margin for DS. Returns show as minus figures.
- [ ] Lock last month in Accounts → Month lock, then try a sale dated in it. It is refused. Unlock it again.

## I. Learning phase, audit and phone

- [ ] As DS, open an invoice made by someone in their learning phase: **Delete fully (learning phase)** removes it with its stock and journal.
- [ ] **Audit log** shows the sales, returns, receipts, refunds and shared links with who and when.
- [ ] On a phone, make a sale, open an invoice and open a statement.
