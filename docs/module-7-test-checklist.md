# Ruchi Buds app: Module 7 test checklist

Version 1.0 · 27-Nov-2026

Tick each line on the real app before signing off module 7. You need DS's login and a second login. Move the module 1 test user to **Manager** for part E.

**Sign-off gate:**

- A new loan's schedule matches a bank's EMI, and a payment, a part-payment and a rate change post correctly.
- A finance lease records the asset and the liability, and its schedule matches the lease.
- Rented premises spread the rent evenly, and the rent and deposit reach the books.
- The month-end step posts and can be reversed, and the Summary agrees with the trial balance.

## A. DEMO data

- [ ] Home shows **Loans and leases**. The **Summary** shows DEMO-LN-001, DEMO-LN-002 and DEMO-FL-001 under loans and finance leases, and DEMO-OL-001 and DEMO-OL-002 under rented premises, each with a **DEMO** badge.
- [ ] Set **As at** to 30-Nov-2026 and press **Show**. "Interest accrued, not yet paid" is no longer ₹0 (the November run is included). "Due within 12 months" plus "Due after 12 months" equals the total owed.
- [ ] **Loans** → DEMO-LN-001: EMI ₹13,001. The entries show **Brought in (take-on)** and the 5-Nov **Payment**. The schedule shows instalment 1 ticked as paid.
- [ ] **Finance leases** → DEMO-FL-001: rate about 11.13%. It shows the asset at cost and its value now, and depreciation over the lease term.
- [ ] **Rent (operating leases)** → DEMO-OL-002 (the shop): month 1 is rent-free, and the rent goes up 5% from month 13. "Charged each month" is the same every month.
- [ ] **Month-end**, November 2026: the run shows **Posted as DEMO-ME/2611/00003**.

## B. As DS: a loan

- [ ] **+ Loan**: "Kitchen equipment loan", any bank, ₹2,00,000, 12%, 24 instalments, a ₹2,000 processing fee. **Show the schedule**: EMI ₹9,415, 24 rows, the last one bringing the balance to ₹0.
- [ ] **Save as draft**: the window shows **Draft (not started)**. Nothing is in the bank yet.
- [ ] **Start (approve and post)**: the bank goes up by ₹1,98,000 (₹2,00,000 less the ₹2,000 fee). **Accounts → Trial balance**: Long-term Bank Loans (40010105) goes up by ₹2,00,000, and Bank Financing Charges (91010115) by ₹2,000.
- [ ] **Pay instalment 1** with a reference. The schedule ticks it, and the owed amount goes down by the repayment.
- [ ] **Part-pay or pay off**: ₹20,000 with ₹400 charges, **Keep the EMI**. The schedule now has fewer instalments.
- [ ] **Change the rate**: refused without a reason. With a reason, it saves, shows under **Rate changes**, and the rest of the schedule changes.
- [ ] **Reverse** the latest entry (with a date and reason). It shows **Reversed**, and the schedule goes back.
- [ ] **A loan already running**: tick the box at the top. Enter the balance still owed, the instalments still to pay, the next due date and the interest accrued. **Start** it: the balance comes in against Opening Balance Migration Clearing (97010105), and no money moves.

## C. As DS: a finance lease and rented premises

- [ ] **+ Finance lease**: a ₹1,50,000 machine, 36 payments of ₹5,000 in advance, useful life 48 months, rate left blank. **Show the schedule**: the rate is worked out, the payments total ₹1,80,000, and it says "This looks like a **finance lease**".
- [ ] Save and **Start**: the asset (for example 20010125) and the lease liability both go up by the amount shown. **Pay instalment 1**.
- [ ] **+ Rented premises**: a godown, 24 months, 12 months lock-in, ₹8,000, 5% increase every 12 months, 1 rent-free month, ₹24,000 deposit. The form shows a total rent of ₹1,88,800 and ₹7,866.67 a month.
- [ ] Save and **Start**. **Deposit paid**: ₹24,000 from the bank. It goes to Long-term Security Deposits (20050130).
- [ ] **Enter rent** for month 2. It shows ✓ with an **EXP** number, and the expense shows in Cash, bank and expenses → Expenses.

## D. Month-end and the AS 19 notes

- [ ] **Month-end** for the current month: the figures show, with "Post this once … has ended". After the month ends, **Post** it. It shows **Posted as …**.
- [ ] **Reverse this run** (with a reason), then **Post** again.
- [ ] **Cash, bank and expenses → Month-end** shows the line "Before step 1: loans and leases month-end", ticked once it is posted.
- [ ] **AS 19 notes**: the finance lease table (payments, future finance charges and present value by 1 year, 1 to 5 years and after 5 years), the leased assets, the operating leases under lock-in and the loans table all show. **Download to Excel** gives one sheet per table.
- [ ] **Accounts → Trial balance**: the loan, lease and deposit accounts agree with the **Summary** on the same date.

## E. As a Manager (test user moved to Manager)

- [ ] The home menu does not show **Loans and leases**.

## F. Clean-up

- [ ] **Settings → Remove demo data** clears every DEMO loan, lease, entry and month-end run. The books still balance (trial balance totals agree).

Signed off by: ____________________ Date: ____________
