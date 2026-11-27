# Ruchi Buds app: Module 6 test checklist

Version 1.0 · 27-Nov-2026

Tick each line on the real app before signing off module 6. You need DS's login and a second login. Move the module 1 test user to **Manager** for part D.

**Sign-off gate:**

- A cash expense, a credit expense paid later, and an expense above the limit all reach the books correctly.
- A day-end count and a bank reconciliation both agree.
- Both month-end steps post, and can be reversed.
- The cash book, partner balances and the trial balance agree.

## A. DEMO data

- [ ] Home shows **Cash, bank and expenses**. The **Cash and bank** tab shows Cash in hand and Bank account 1 with balances.
- [ ] Set the cash book **From** date to 1-Nov-2026 and press **Show**. You see the opening balance, entries with a running balance, the closing balance, and the DEMO count (₹40 short).
- [ ] **Expenses** (From 1-Nov-2026) lists DEMO-EXP/2611/00001 to 00012 and DEMO-OIN 00001 and 00002, each with a **DEMO** badge. "1 waiting for approval" shows (the ₹12,500 signboard).
- [ ] The Mehta & Co bill (₹4,500, on credit) shows ₹4,500 **Still owed**. The gas bill (on credit) shows nothing owed, because it was paid on 24-Nov.
- [ ] **Partners**: Partner 1 has ₹50,000 of capital, and Partner 3's current account shows −₹3,000 (drawings).
- [ ] **Month-end** for November 2026: step 1 (₹23,982.38 into stock) and step 2 (₹650 provision) both show **Posted**. Step 2 shows the red "only an example" warning.

## B. As DS: expenses and money

- [ ] **+ Expense**: "Shop or office electricity and water", ₹1,200, cash. It saves as a **TRN-EXP/** number and shows **Posted**. The cash book shows ₹1,200 out.
- [ ] Add a photo to it (tap the line, then **Add a photo**). The photo shows in the window.
- [ ] **+ Expense** for ₹15,000 by bank. The form warns that it will wait. It shows **Waiting for approval**, and the cash book does not change.
- [ ] Tap it and **Approve** it (or refuse it with a reason). Once approved, the bank shows ₹15,000 out.
- [ ] **+ Expense** on credit with no supplier is refused. With a supplier, a bill no. and ₹360 GST, it saves. The GST is part of the cost (not registered yet), and the bill shows **Still owed**.
- [ ] Tap it, then **Pay this bill**. The window lists the bill. Choose UPI and **Paid from** Bank account 1, then save. The bill shows nothing owed. **Purchases → Supplier balances** agrees.
- [ ] **+ Money received**: "Bank interest received", ₹45, bank. It shows with a **+**.
- [ ] **Moving money → + Move money**: ₹1,000 from Cash in hand to Bank account 1. Both balances change on the Cash and bank tab.
- [ ] **Cash count → + Count the cash**: fill the notes. "In the books" shows the cash book balance.
  - Type ₹10 less than the books with no reason: refused.
  - Add a reason: saved, and "Difference of ₹10.00 posted".
  - A second count of the same account on the same day is refused.
- [ ] **Partners → + Capital or drawings**: drawings of ₹500 for Partner 2 from cash. The partner's current account goes down by ₹500.
- [ ] **Reverse** one transfer (tap it). It shows **Reversed**, with the reason.

## C. Bank reconciliation and month-end

- [ ] **Bank reconciliation**: Bank account 1, November 2026, then **Show**.
  - Press **Tick all** and type a wrong statement balance. **Finish the month** is refused with the difference.
  - Type the balance shown under "Balance in the books". The difference shows ₹0.00 ✓.
  - **Finish the month**: it shows **Reconciled**.
- [ ] **Reopen** it (with a reason). It shows **Not finished** again.
- [ ] **Month-end**, November 2026: the checklist ticks the bank reconciliation and both steps.
- [ ] Step 1 shows the method in use (Kg produced) and all four methods side by side. Open **Batches of the month** and **Where it goes**.
- [ ] Step 2: **Reverse this run** (with a reason), then **Post the provision** again.
- [ ] **Settings → Expenses and month-end**: change the "not on an invoice" rate to 12% and press **Save settings**. The red "example" warning goes. Month-end step 2 now shows the new rate.
- [ ] **Set-up → Change the method (Director)**: refused without a reason. With a reason, the method changes. Change it back to Kg produced.
- [ ] **Accounts → Trial balance**: Cash in hand (10010110) and Bank account 1 (10010205) equal the closing balances on the Cash and bank tab. Partners' Capital (50010130) equals the Partners tab.

## D. As a Manager (test user moved to Manager)

- [ ] Can enter an expense, a transfer and a cash count.
- [ ] Sees no **Month-end** or **Set-up** tab, and cannot approve expenses (no Approve button).
- [ ] Cannot enter partners' capital or drawings (no button).
- [ ] On a phone, the **+ Expense** form fits the screen and the bill photo opens the camera.

## E. Clean-up

- [ ] **Settings → Remove demo data** clears every DEMO expense, transfer, count and month-end run. The books still balance (trial balance totals agree).

Signed off by: ____________________ Date: ____________
