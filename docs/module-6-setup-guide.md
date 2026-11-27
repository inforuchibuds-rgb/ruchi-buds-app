# Ruchi Buds app: Module 6 setup guide

Version 1.0 · 27-Nov-2026 · Module 6: Cash, bank and expenses (with the month-end steps)

This update takes about 15 minutes. You paste one file into Supabase. GitHub Pages updates the screens on its own once the pull request is merged.

## What module 6 gives you

Home → **Cash, bank and expenses**. The screen has these tabs:

- **Cash and bank**: the balance of each cash and bank account today, and the **cash book** of any account. The cash book shows the opening balance, every entry with a running balance, the closing balance and the day-end counts. It downloads to Excel.
- **Expenses**: everything the business spends that is not stock, such as rent, gas, wages, repairs, transport, ads and fees.
  - **+ Expense**: choose what it was for (the category), the amount, any GST on the bill and how it was paid. You can pay by cash, UPI, bank or **credit (pay later)**. Add a photo of the bill if you have one.
  - Below the limit in Settings (DEMO: ₹10,000), it goes straight into the books. Above the limit, it **waits for approval** by the Accountant, the FC or a Director.
  - **On credit**: choose the supplier. The bill stays in their balance until it is paid, with **Pay this bill** or the usual **Pay a supplier** window in Purchases. That window now lists expense bills as well as purchase bills.
  - **+ Money received**: other money that is not a sale, such as bank interest or empty cartons sold.
  - Tap any line to see it with its photo, then approve, refuse, pay, reverse or (learning phase) delete it.
- **Moving money**: cash paid into the bank, cash drawn from the bank, or money moved between two bank accounts.
- **Cash count**: count the till at the end of the day, with a helper for each note. If the count differs from the books, you must give a reason, and the difference is posted at once.
- **Partners**: each partner's capital and current account. **+ Capital or drawings** records capital brought in, capital taken out, or drawings.
- **Bank reconciliation**: once a month, tick each entry that is on the bank statement and type the statement's closing balance. When they agree to the paisa, press **Finish the month**. Entries not yet on the statement carry to the next month.
- **Month-end** has a checklist and the two month-end steps (see the next section).
- **Expense report**: totals by month, category and department, for Excel.
- **Set-up**:
  - Name the cash and bank accounts and switch them on (up to four banks).
  - Add or change expense categories.
  - The month-end set-up: which production cost accounts are shared into stock, fixed or variable, and the normal monthly output.
  - The sharing method. Only a Director can change it.
- **Settings → Expenses and month-end**: the approval limit, and the CA's rates for doubtful debts.

**DEMO data (November 2026):**

- 12 expenses, including:
  - a gas bill on credit, paid later from the bank;
  - a ₹4,500 accountant's bill still unpaid;
  - ₹18,000 of wages approved by the FC;
  - a ₹12,500 signboard waiting for approval.
- 2 entries of money received.
- 2 transfers between cash and bank.
- Capital brought in by Partner 1, and drawings by Partner 3.
- A cash count ₹40 short.
- A ₹6,500 opening balance for Hill Top Caterers.
- Both month-end steps posted for November:
  - ₹23,982 of labour and overheads added to stock;
  - a ₹650 provision.

## The two month-end steps

Run them **early in the following month**, after the month's last bills are in (for example, on 2 December for November). Then lock the month in Accounts. The checklist on the Month-end tab shows what is still open.

**Step 1: kitchen labour and overheads into stock (AS 2, in full).** Stock is valued at everything it cost to make. That means the materials, plus the kitchen's share of wages, gas, kitchen rent, repairs and other production costs.

1. The app adds up the month's **production costs**: accounts 7002 (labour) and 7003 (production overheads), as ticked in Set-up.
2. It shares them between the month's batches by the **sharing method**. The default is **kg produced**. The others are number of batches, hours worked, and value of materials.
3. When a prepared ingredient goes into a final product, its share goes with it.
4. Only the part that belongs to goods **still on hand at month-end** goes into stock. The rest belongs to goods already sold and stays in profit and loss.
5. If you set a **normal monthly output**, a slow month does not load all the fixed costs (such as rent) onto the little stock made. The unused part stays in profit and loss, as AS 2 requires.
6. The screen shows the result under all four methods side by side before you press **Post**.

**Step 2: provision for doubtful debts.**

1. Every customer's balance at month-end is grouped by how many days it is past its due date.
2. Each group gets the CA's percentage, set in Settings. Balances that are not on an invoice, such as opening balances, have their own percentage.
3. Only the **change** from the provision already held is posted. An increase is an expense; a decrease is written back.
4. The DEMO rates are **only an example**, and the screen says so in red until you enter the CA's rates.

Either step can be reversed with a reason and run again. While step 1 is posted for a month, that month's batches cannot be reversed. Reverse the step first, then the batch, then run the step again.

## Decisions built in (please check them)

| Topic | What the app does | Why |
|---|---|---|
| Cash and bank accounts | Cash in hand 10010110 (main), petty cash 10010105 (off), Bank account 1 10010205 (main, UPI) and banks 2 to 4 (10010210 to 10010220, off). Sales and purchase UPI or bank money goes to the main bank account. | Master COA. |
| Expense categories | 27 expense and 3 money-received categories, each tied to one account in the chart. Kitchen costs go to 7002 and 7003; shop, office, selling and finance costs go to 8000 accounts. You can add or change categories in Set-up. | Only production costs can go into stock (AS 2). |
| GST on expenses | Before the "GST registered from" date, GST is part of the cost. From that date, GST on bills is claimed as input GST (10050105). | Same rule as purchases. |
| Approval | Expenses above the Settings limit wait for the Accountant, the FC or a Director. Money received never waits. | Spec section 9A. |
| Wages | Entered as an expense (Kitchen wages, or Shop and office salaries). No payroll. | Spec: payroll is out of scope. |
| Partners | Capital in or out goes to Partners' Capital (50010130); drawings go to Partners' Current Account (50010135), per partner. Only people with Cash, bank and expenses → Edit can enter them. | Partnership accounts. |
| Cash differences | Short goes to Other Operating Expenses (80080135). Over goes to Other Non-operating Income (90010135). A reason is always required. | Spec section 9A. |
| Overheads into stock | Debit Work in Progress (10030120) or Finished Goods (10030125), credit **Manufacturing Overhead Absorption** (70030140). The costs stay visible in their own accounts. | AS 2, costs of conversion and normal capacity. |
| Sharing method | Kg produced by default. One method is kept; a change needs a Director, a reason, and an entry in the change log. | Spec section 7, Plan B. |
| Which stock is still on hand | The latest batches are taken to be the ones still on the shelf. | Matches weighted average stock in practice. |
| Provision | Credit **Provision for Doubtful Debts** (10020225, shown against customer balances); debit the expense account of the same name (80080140). Both are new local accounts. | AS 4 and prudence (Indian AS). |
| Numbers | EXP for expenses, OIN for money received, CTR transfers, PTR partner entries, CNT cash counts, ME month-end runs. Training entries start with TRN-, and DEMO entries with DEMO-. | Same as other modules. |
| Who sees money | Balances, the cash book, partners and bank reconciliation need the **see totals** tick, or Accounts. Manager categories can enter expenses, transfers and counts. Month-end is for the Accountant, the FC and Directors (new power: **Month-end steps**). | Spec section 4. |

**For your CA (please ask them):**

1. The percentage for each age band of overdue customer money, and for balances not on an invoice. Enter them in **Settings → Expenses and month-end**.
2. The kitchen's **normal monthly output** in kg (for AS 2 normal capacity). Until it is set, all the month's production costs are shared.
3. Whether the sharing method (kg produced) suits the product mix.

## Step 1. Take a backup (1 minute)

In the app: **Settings → Backup now (file for restore)**. Keep the file.

## Step 2. Supabase: add the module 6 tables (3 minutes)

1. Open your project at [supabase.com/dashboard](https://supabase.com/dashboard), then **SQL Editor → New query**.
2. Open `sql/06_cash_bank.sql` from the repository (on GitHub, click the file, then the **Copy raw file** button).
3. Paste it and press **Run**. If Supabase warns about "destructive operations", press **Run this query**. That is expected.
4. You should see **Success. No rows returned**.

The file is safe to run again. Running it again changes nothing and loses nothing.

> **Important:** module 6 takes over the supplier payment functions from module 3, so expense bills can be paid too. If `01` to `05` is ever run again, run every later file again straight after it, in order, ending with `06`.

## Step 3. The screens

Once the pull request is merged into **main**, GitHub Pages publishes the new screens within a couple of minutes. Reload the app. On a phone, close the app fully and open it again.

The home menu now shows **Cash, bank and expenses** without a "Module 6" label.

## Step 4. Set-up and access (10 minutes)

1. **Cash, bank and expenses → Set-up**: give each bank account its real name, bank and last 4 digits, and switch on the ones you use. Switch on **Petty cash** if you keep one.
2. **Set-up → Expense categories**: check the list. Add any you need (for example "Packaging design") with the right account.
3. **Set-up → Month-end step 1 set-up**: check which kitchen cost accounts are ticked. Enter the normal monthly output once the CA confirms it.
4. **Settings → Expenses and month-end**: set the approval limit (the DEMO uses ₹10,000). Enter the CA's rates when you have them, then press **Save settings**.
5. **Users → Categories and access**: check the **Cash, bank and expenses** row for each category. By default:
   - Managers can view and add.
   - The Accountant, FC and Directors can do everything.
   - The new power **Month-end steps** is held by the Accountant (and always by the FC and Directors).

## Files in this module

| File | What it is | Where it goes |
|---|---|---|
| `sql/06_cash_bank.sql` | The database for module 6 | Paste into Supabase SQL Editor (step 2) |
| `cashbank.js` | The Cash, bank and expenses screen | Already in the repository, served by GitHub Pages |
| `index.html`, `settings.js`, `purchases.js`, `stock.js` | Updated (loads the new screen, the Settings section, expense bills in Pay a supplier, the month-end line in stock movements) | The same |
| `docs/module-6-test-checklist.md` | What to tick before sign-off | Read and tick |
| `tests/test_cashbank.sql`, `tests/e2e_cashbank.js` | The automatic checks used while building | Not needed in Supabase |

## If something goes wrong

- **"permission denied for function …"** on any screen: run `06_cash_bank.sql` again (usually because an earlier file was run after it).
- **"An expense on credit needs the supplier"**: choose the supplier, or add them with **+ New**.
- **"The cash counted is … Please give the reason"**: type why the till is short or over.
- **"The ticked entries come to …"** on the bank reconciliation: something on the statement is not in the app yet (often bank charges or interest). Enter it as an expense or money received, then tick it.
- **"Run this once … has ended"**: the month-end steps can only be posted after the month is over.
- **"The labour and overheads for … are already in stock"** when reversing a batch: reverse month-end step 1 first.
- **"… is locked"**: the month is locked. A Director or the FC unlocks it in Accounts, with a reason.
- Anything else: take a screenshot and send it in the project thread.
