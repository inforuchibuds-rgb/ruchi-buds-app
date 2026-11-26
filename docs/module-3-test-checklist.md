# Ruchi Buds app: Module 3 test checklist

Version 1.0 · 26-Nov-2026

Tick each line on the real app before signing off module 3. You need DS's login and a second login. Move the module 1 test user to **AP** for part B, then to **Accountant** for part C.

**Sign-off gate:** a purchase goes PO → GRN → bill with a difference flagged in red; the difference is settled; the purchase is paid; the supplier ledger, the stock and the trial balance all agree.

## A. DEMO data and the list

- [ ] Home shows **Purchases**. It opens on a list of 11 DEMO purchases, each with an orange **DEMO** badge.
- [ ] The filter buttons work: **Direct purchases** shows 4, **With differences** shows 2, **Waiting for approval** shows 1.
- [ ] Open **DEMO-PO/2611/00002** (glass bottles). The match view shows 12 bottles refused and the bill charging for 500, both in red.
- [ ] **Download to Excel** gives a file with the list.

## B. As AP: order, receive, bill

- [ ] **+ New order (PO)**: pick a DEMO supplier, add two lines (one in kg, one in pieces). The total shows as you type. Save: the order gets a **TRN-PO/** number.
- [ ] Try to add a line for a finished product. It is refused (only raw materials and packaging are bought).
- [ ] **Receive goods**: enter a little less than ordered on one line, and refuse a few on another with a reason. Save: a **TRN-GRN/** number, status **Part received**, the short and the refused lines in red.
- [ ] **Enter supplier bill**: change one rate and one quantity from the order. Choose **Cash**. Saving is refused ("Save it as Credit"). Choose **Credit** and save.
- [ ] The match view shows each difference in red, the **Pay** button is missing, and a red note says the purchase cannot be paid.
- [ ] Press **Accept** on a rate difference. It is refused (money differences are for the Accountant, FC or a Director).

## C. As Accountant (or DS): settle and pay

- [ ] The **Differences** tab lists the open differences with age in days.
- [ ] Short at delivery: **Accept** with a reason ("normal weighing loss"). It turns amber.
- [ ] Rate on the bill: **Reject: Correct the rate to the PO rate**. A debit note **TRN-DN/** appears under Documents, and **Still owed** goes down.
- [ ] Refused goods: **Reject: Return the goods**. A return appears; stock does not change (the goods never came in).
- [ ] Once nothing is red, **Pay** appears. Pay by UPI. Status becomes **Paid**.
- [ ] **Supplier balances**: the supplier shows the right balance. Tap it: the ledger shows bill, debit note and payment, ending on the same balance.
- [ ] **Suppliers** screen: the **Balance owed** column matches, and **Ledger** opens from the supplier.

## D. Direct purchases

- [ ] **+ Direct purchase (no PO)** with a fisherman: **No supplier bill** ticks itself. Save without a photo or note: refused. Add a photo (on a phone, the camera opens) or a note: saved, paid in cash, the GRN number is the reference.
- [ ] Open it: the photo opens from **Photos**.
- [ ] In **Settings → Entry rules** set the limit to ₹1,000. As AP, enter a direct purchase of ₹2,000 on credit: it shows **Waiting for approval** and nothing is in the stock report.
- [ ] As the Accountant (or DS), open it and **Approve and post**. Status **Billed**; the stock report shows the goods.
- [ ] **Reports → Direct purchases by month** shows these purchases.

## E. Returns, reversal and the books

- [ ] On a billed purchase, **Return goods** for part of a line. A **TRN-PRN/** return appears and the supplier balance goes down.
- [ ] As the Accountant, **Reverse purchase** on a purchase that has no payment. It becomes **Cancelled**, and its stock goes back out (Reports → Stock bought so far).
- [ ] On a paid purchase, **Reverse purchase** is refused until its payment is reversed (Payments tab → tap the payment → Reverse payment).
- [ ] In **Accounts and journals**, try to reverse a purchase journal. It is refused ("Reverse it there").
- [ ] **Accounts → Trial balance**: debits equal credits; Goods received not invoiced (30010115) is zero once every received purchase is billed.
- [ ] Lock last month in Accounts → Month lock, then try to enter a direct purchase dated in it. It is refused. Unlock it again.

## F. Learning phase and audit

- [ ] As DS, open a purchase entered by someone in their learning phase: **Delete fully (learning phase)** removes it with its stock and journals.
- [ ] **Audit log** shows the order, goods received, bill, settled differences and payments with who and when.

## G. Phone

- [ ] On a phone, open Purchases, a purchase window (the match table scrolls sideways) and the Direct purchase form.

## H. Clean up

- [ ] **Settings → Remove demo data** removes the DEMO purchases, payments and their stock. Your own TRN- entries stay until go-live.

Signed off by: ____________________ Date: ____________
