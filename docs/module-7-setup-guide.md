# Ruchi Buds app: Module 7 setup guide

Version 1.0 · 27-Nov-2026 · Module 7: Loans and leases (AS 19)

This update takes about 15 minutes. You paste one file into Supabase. GitHub Pages updates the screens on its own once the pull request is merged.

## What module 7 gives you

Home → **Loans and leases**. At the top are three buttons: **+ Loan**, **+ Finance lease** and **+ Rented premises**. The screen has these tabs:

- **Summary**: everything the firm owes on loans and finance leases on any date. It shows the interest accrued but not yet paid, and splits each balance into **due within 12 months** and **due after 12 months**. That split is what the balance sheet needs. Rented premises are listed below, with the rent now, the rent charged each month, the rent equalisation and the deposit held. It downloads to Excel.
- **Loans**: bank loans, loans from partners and any other borrowing.
  - **+ Loan**: lender, amount, date received, rate (fixed or floating), how it is repaid (EMI, equal principal, or interest only with everything repaid at the end), how often, and the number of instalments. Leave the EMI blank and the app works it out, or type the bank's figure.
  - **Show the schedule** shows every instalment, split into interest and repayment, before you save.
  - A new loan is a **draft** until the Accountant, the FC or a Director presses **Start**. Starting it posts the money received, and any processing fee.
  - **A loan that was already running** before the app: tick the box at the top. Enter the balance still owed on the take-on date, the instalments still to pay, the next due date and the interest accrued since the last EMI.
  - Tap a loan to see its schedule (with Excel download) and its entries. From there:
    - **Pay instalment**: the split comes from the schedule; change it to match the bank statement if it differs.
    - **Part-pay or pay off**: choose to keep the EMI (the loan ends sooner) or keep the end date (the EMI goes down).
    - **Change the rate**: for floating-rate loans. A reason is required, and every change is kept on the loan.
- **Finance leases**: a lease that passes almost all the risks and rewards of an asset to the firm (for example, a van leased for most of its life).
  - **+ Finance lease**: the asset, its fair value (cash price), the lease payments, in advance or in arrears, and the asset's useful life.
  - Leave the rate blank and the app works out the **rate implicit in the lease**.
  - The preview says whether it looks like a finance lease: payments worth 90% or more of the fair value, or a term of 75% or more of the asset's life. If not, it suggests checking with the CA and entering it as rented premises instead.
  - **Start** records the asset and the lease liability.
  - Each payment is split into finance charge and repayment. The asset is depreciated every month.
  - When the asset goes back to the lessor at the end, **Asset returned: end the lease** takes it out of the books.
- **Rent (operating leases)**: the kitchen, the shop, a godown or rented equipment.
  - **+ Rented premises**: landlord, which expense the rent goes to (kitchen rent is part of stock cost, shop and office rent are not), start date, length in months, lock-in, monthly rent, any yearly increase, rent-free months and the security deposit.
  - The form shows the total rent over the lease and the rent charged to profit and loss each month.
  - Once started, record the **deposit paid** (and later **returned**). Press **Enter rent** against each month. That makes the rent an expense in Cash, bank and expenses, with the usual approval limit.
  - **End early** takes off the months after the last day.
- **Month-end** (Accountant, FC and Directors): one step a month. See the next section.
- **AS 19 notes**: the tables the CA needs for the notes to the accounts on any balance sheet date:
  - finance lease payments due within 1 year, 1 to 5 years and after 5 years, with the future finance charges and the present value;
  - leased assets at cost, depreciation and carrying amount;
  - operating lease payments still due under the lock-in;
  - lease and loan charges for the period;
  - loan principal falling due.
  It downloads to Excel, one sheet per table.

**DEMO data (November 2026):**

- **DEMO-LN-001**: a ₹4,00,000 kitchen equipment loan from Bank of Maharashtra, 10.5% floating, brought in as a running loan. EMI ₹13,001; the 5-Nov EMI is paid.
- **DEMO-LN-002**: a ₹1,00,000 loan from Partner 2 at 9%, interest only, repaid in full after 24 months.
- **DEMO-FL-001**: a Tata Ace delivery van on a finance lease. Fair value ₹2,40,000, 36 payments of ₹7,800 in advance, rate implicit 11.13%. The first payment is made.
- **DEMO-OL-001**: the kitchen, 11 months at ₹6,000 with a 6-month lock-in and an ₹18,000 deposit. The November rent is the module 6 DEMO kitchen rent expense.
- **DEMO-OL-002**: the shop, 36 months from 1-Oct-2026 at ₹15,000, 5% more each year, the first month rent-free, a 12-month lock-in and a ₹30,000 deposit.
- The November month-end run is posted: interest accrued, depreciation on the van, and the shop's rent spread.

## The month-end step

Run it **early in the following month**, for example on 2 December for November.

Run it **before step 1** on Cash, bank and expenses → Month-end, because depreciation of kitchen assets and kitchen rent are part of stock cost. The module 6 checklist now has a line for it. If step 1 is already posted and this run would change kitchen costs, the app stops you and says to reverse step 1 first.

For every loan and lease, the step posts:

1. **Interest and finance charges** from the last instalment to the month-end that are not yet paid (accrued interest, AS 16). The next instalment clears them.
2. **Depreciation** of leased assets: one month, straight line, over the lease term (or the useful life if the asset becomes the firm's at the end).
3. **Rent spread evenly** (AS 19): the difference between the rent charged evenly and the rent entered goes to the rent equalisation account.

Only the change since the last run is posted, so a missed month is caught up by the next run. The screen shows the figures before you press **Post**, and it can be posted only once the month has ended. A run can be reversed with a reason and posted again.

## Decisions built in (please check them)

| Topic | What the app does | Why |
|---|---|---|
| Short-term or low-value leases | There are no exemptions. Every lease that is not a finance lease is an operating lease, with the rent spread evenly. | AS 19 has no such exemptions (that is IFRS 16 / Ind AS 116). |
| Finance lease at the start | Asset and liability at the **lower of** the fair value and the present value of the minimum lease payments. The rate is the rate implicit in the lease, worked out from the fair value, unless you give one. Initial direct costs are added to the asset. | AS 19 paragraphs 11 to 13. |
| Finance charge | Spread at a constant rate on the balance owed. Each payment is split into finance charge and repayment. | AS 19 paragraph 17. |
| Depreciation of leased assets | Straight line, monthly. Over the lease term, or over the useful life if ownership passes at the end. Kitchen assets go to Production Depreciation (70030115) and are part of stock cost; others go to 80070105. | AS 19 paragraph 18, AS 10, AS 2. |
| Operating lease rent | Charged evenly over the lease term (straight line), so rent-free months and increases are spread. The difference is in **Rent Equalisation – Operating Leases** (40020120). "As paid" is allowed only with a reason, for the CA. | AS 19 paragraph 23. |
| Security deposits | Kept in Long-term Security Deposits (20050130) if the lease runs more than 12 months, otherwise in Security Deposits – Current (10020335). No discounting. | Indian AS has no rule to discount them. |
| Loan interest | Accrued every month-end to Interest Payable (30060130). | AS 16. |
| Processing fees | Charged as a finance cost when paid (91010115). Late and foreclosure charges go to 91010130. | AS 16 (borrowing costs as incurred). |
| Which account | Automatic: a bank loan of more than 12 months goes to Long-term Bank Loans (40010105); a loan from a partner to Related-party Loans (40010120); short loans to short-term borrowings. You can choose another. | Master COA. |
| Current and non-current | Each loan stays in one account. The **Summary** shows the part due within 12 months, to show under current liabilities in the balance sheet. | Schedule III presentation. |
| Loans already running | Brought in on the take-on date against the opening balances account (97010105), like other opening balances. | Same as modules 3 and 5. |
| EMI | Worked out to the nearest rupee, like banks do. The last instalment clears the paise. | Matches bank schedules. |
| Approval | A loan, lease or rented premises is a draft until the Accountant, the FC or a Director starts it. Payments, deposits and rent can be entered by anyone with Loans and leases → Add. | Spec section 9. |
| Who sees it | Managers do not see Loans and leases. The Accountant can do everything. The month-end step needs the **Month-end steps** power. Reversing needs **Reverse entries**. | Spec section 4. |
| Numbers | LN loans, FL finance leases, OL rented premises, LNE loan and lease entries, ME month-end runs. Training entries start with TRN-, and DEMO entries with DEMO-. | Same as other modules. |

**For your CA (please ask them):**

1. **The list of current loans and leases**, with the balance and next due date of each on the take-on date. These come in with the "already running" box.
2. For any lease of equipment or a vehicle: is it a finance lease or an operating lease? The preview shows the 90% and 75% tests to help.
3. Whether any operating lease should be charged "as paid" instead of evenly (rare: only if another basis is more representative).
4. **Still open from module 6:** the provision percentages for each age band of overdue customer money, and the kitchen's normal monthly output in kg.

## Step 1. Take a backup (1 minute)

In the app: **Settings → Backup now (file for restore)**. Keep the file.

## Step 2. Supabase: add the module 7 tables (3 minutes)

1. Open your project at [supabase.com/dashboard](https://supabase.com/dashboard), then **SQL Editor → New query**.
2. Open `sql/07_loans_leases.sql` from the repository (on GitHub, click the file, then the **Copy raw file** button).
3. Paste it and press **Run**. If Supabase warns about "destructive operations", press **Run this query**. That is expected.
4. You should see **Success. No rows returned**.

The file is safe to run again. Running it again changes nothing and loses nothing.

> **Important:** if `01` to `06` is ever run again, run every later file again straight after it, in order, ending with `07`.

## Step 3. The screens

Once the pull request is merged into **main**, GitHub Pages publishes the new screens within a couple of minutes. Reload the app. On a phone, close the app fully and open it again.

The home menu now shows **Loans and leases** without a "Module 7" label.

## Step 4. Set-up and access (10 minutes)

1. **Users → Categories and access**: check the **Loans and leases** row. By default:
   - Managers have no access.
   - The Accountant, FC and Directors can do everything.
2. If the firm has loans or leases already running, enter each one with the **already running** box ticked. Use the take-on date (usually the day the app starts). Then press **Start** on each.
3. Enter each rented premises (kitchen, shop, godown). For a lease that started before the app, tick **already running** and give the take-on date, so the deposit already paid comes in.

## Files in this module

| File | What it is | Where it goes |
|---|---|---|
| `sql/07_loans_leases.sql` | The database for module 7 | Paste into Supabase SQL Editor (step 2) |
| `loans.js` | The Loans and leases screen | Already in the repository, served by GitHub Pages |
| `index.html`, `cashbank.js` | Updated (loads the new screen; the module 6 month-end checklist has a line for the loans and leases run) | The same |
| `docs/module-7-test-checklist.md` | What to tick before sign-off | Read and tick |
| `tests/test_loans.sql`, `tests/e2e_loans.js` | The automatic checks used while building | Not needed in Supabase |

## If something goes wrong

- **"permission denied for function …"** on any screen: run `07_loans_leases.sql` again (usually because an earlier file was run after it).
- **"Run this once … has ended"**: the month-end step can only be posted after the month is over.
- **"Step 1 is already posted for this month …"**: reverse step 1 on Cash, bank and expenses → Month-end, post the loans and leases step, then post step 1 again.
- **"… already posted for a later month"**: months are run in order. Reverse the later month first.
- **"The instalment … does not even cover the interest"**: check the EMI, the amount and the rate.
- **"… is locked"**: the month is locked. A Director or the FC unlocks it in Accounts, with a reason.
- Anything else: take a screenshot and send it in the project thread.
