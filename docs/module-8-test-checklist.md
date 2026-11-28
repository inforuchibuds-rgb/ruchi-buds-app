# Ruchi Buds app: Module 8 test checklist

Version 1.0 · 27-Nov-2026

Tick each line on the real app before signing off module 8. You need DS's login, the Accountant's login and a second login. Move the module 1 test user to **Manager** for part F.

**Sign-off gate:**

- The balance sheet balances, and its figures agree with the trial balance on the same date.
- The cash flow statement agrees with the cash and bank balances.
- The year-end close moves the profit to the partners' current accounts and can be reversed.
- The weekly Google Sheets copy runs, and the Looker Studio report shows in the app only for the named Google accounts.

## A. Dashboard and reports (DEMO data)

- [ ] Home shows **Reports**. The **Dashboard** opens.
- [ ] Set **As at** to 30-Nov-2026, tick **Include DEMO entries** and press **Show**. Sales this month ₹19,890.00, gross margin ₹9,103.27 (45.8% of sales), cash and bank ₹43,339.00.
- [ ] Point at (or tap) the November bar in "Sales and margin, last 12 months": it shows the sales and the margin. The top products and sales by customer type show.
- [ ] **Sales**, 01-Nov-2026 to 30-Nov-2026: the product rows add up to ₹19,890.00. **By day**, **By customer type** and **By channel** regroup them. **⬇ Excel** (top right) gives a file.
- [ ] **Purchases**, **Stock**, **Customers** and **Loans and leases** each show their figures without an error. Loans and leases lists DEMO-LN-001.

## B. Financial statements

- [ ] **Financial statements**, 01-Apr-2026 to 30-Nov-2026, DEMO ticked. **Balance sheet**: both totals are ₹8,17,372.04. There is a note about suspense and clearing accounts (expected with DEMO data). The comparative column is "As at 31-Mar-2026".
- [ ] **Profit and loss**: revenue, expenses and the loss for the period show. The comparative is 01-Apr-2025 to 30-Nov-2025.
- [ ] **Cash flow**: the cash at the end of the period is ₹43,339.00, the same as cash and bank on the balance sheet. The note below lists the van lease (₹2,40,000.00) as a non-cash transaction.
- [ ] **Notes**: each line is broken down by account.
- [ ] **Accounts → Trial balance** on 30-Nov-2026: cash and bank, trade payables and the loan accounts agree with the balance sheet notes.
- [ ] **Download to Excel** gives one sheet per statement. **🖨 Print** (top right) shows only the statement.
- [ ] Untick DEMO and press **Show**: the statements still balance (they may be nil).

## C. Statement lines

- [ ] **Statement lines** → **+ Rule**: accounts starting with 80050150, line "Other expenses". It saves and shows under Rules.
- [ ] Try a balance sheet line for a profit and loss account (for example 80050150 to "Trade payables"): it is refused.
- [ ] Tap the rule → **Delete the rule**. It goes.

## D. Year-end close (as DS)

- [ ] **Year-end close** → FY 2025-26: "Nothing left to close" (or the profit to close, with each partner's share by the ratio in Settings).
- [ ] FY 2026-27: "This year has not ended yet". There is no close button.
- [ ] After 31-Mar-2027 (or on a copy): close the year. The partners' current accounts (50010135) go up by their shares, and every profit and loss account is nil after 31 March. **Reverse the latest close** (with a reason) puts it back.

## E. Weekly Google Sheets copy and Looker Studio

- [ ] In the Apps Script, run **weeklySheetsCopy**. The **Ruchi Buds Reporting** sheet has the tabs _about, accounts, monthly_balances, sales_lines, purchase_lines, expenses and loans.
- [ ] **Analysis (Looker Studio)** shows the date of the last copy, "done", and a link to the sheet.
- [ ] **Apps Script → Triggers** (the clock icon) shows weeklySheetsCopy, weekly on Monday.
- [ ] Paste a link that is not Looker Studio (for example https://example.com): it is refused. Paste the Looker Studio embed link: the report shows in the app.
- [ ] Open the app in a browser signed in to a Google account the report is **not** shared with: the report does not show.

## F. Access

- [ ] As the Accountant: Reports shows, with margins. **Year-end close** has no close button, and **Analysis** has no box to change the link.
- [ ] As a Manager (test user moved to Manager): the home menu does not show **Reports**.

## G. Clean-up

- [ ] **Settings → Remove demo data** clears the DEMO entries. The financial statements with DEMO unticked are unchanged, and the balance sheet still balances.

Signed off by: ____________________ Date: ____________
