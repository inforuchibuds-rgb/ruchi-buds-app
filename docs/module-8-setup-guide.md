# Ruchi Buds app: Module 8 setup guide

Version 1.0 · 27-Nov-2026 · Module 8: Reports and the weekly Google Sheets copy

This update takes about 30 minutes, most of it for the Looker Studio report. You paste one file into Supabase and update the Apps Script. GitHub Pages updates the screens on its own once the pull request is merged.

## What module 8 gives you

Home → **Reports**. Only Directors, the FC and the Accountant see it. Each tab has a **From** and **To** date (or **As at**), a **Quick choice** (this month, last month, this year to date, last financial year) and an **Include DEMO entries** tick.

- **Dashboard**: live from the app.
  - The top row: sales this month, gross margin this month, cash and bank, what customers owe, and what is owed to suppliers.
  - Below: sales this year, margin this year, sales today, stock value, loans and leases owed, and expenses this month.
  - Charts: sales for the last 30 days, sales and margin for the last 12 months, the top products this month, and sales by customer type. Point at a bar (or tap it) to see the figures.
  - Margins show only to Directors, the FC and the Accountant.
- **Sales**: by product, by day, by customer type, by channel, or every line, with cost, margin and margin %. Sales are after returns and before GST. Downloads to Excel.
- **Purchases**: purchases for the period, and what each supplier is owed.
- **Stock**: stock on hand with its value, and wastage by stage.
- **Customers**: what each customer owes, split by how overdue it is.
- **Loans and leases**: the balances from module 7.
- **Financial statements**, prepared under Indian AS (ICAI) in full, with the previous period alongside:
  - **Balance sheet** in the Schedule III layout for firms. Loan instalments due within 12 months are moved to short-term borrowings.
  - **Profit and loss**: revenue, cost of materials, purchases of stock-in-trade, change in inventories, employee costs, finance costs, depreciation and other expenses. It shows how the profit is shared between the partners.
  - **Cash flow** (AS 3, indirect method): operating, investing and financing, agreeing to the cash and bank balances. Non-cash transactions, such as a finance lease starting, are left out and listed below it.
  - **Notes**: every line broken down by account.
  - **Download to Excel** (one sheet per statement), and **🖨 Print** at the top right.
- **Statement lines**: which line of the statements each account goes to. A rule covers every account starting with its digits; the longest match wins. The Accountant, the FC and Directors can add a rule, for example if the CA wants an account shown on another line.
- **Year-end close**: after 31 March, moves the year's profit or loss to the partners' current accounts in the profit-sharing ratio (Settings). The FC or a Director posts it.
- **Analysis (Looker Studio)**: the Looker Studio report, inside the app. It is fed by the weekly Google Sheets copy and shown only to Google accounts it is shared with.

**DEMO figures (November 2026, with DEMO entries ticked):** sales this month ₹19,890.00, gross margin ₹9,103.27 (45.8%), cash and bank ₹43,339.00. The balance sheet at 30-Nov-2026 totals ₹8,17,372.04 on both sides. The DEMO data leaves ₹3,96,548.39 in the opening-balance clearing account, so the screen shows a note about suspense accounts. That is expected for DEMO data.

## Decisions built in (please check them)

| Topic | What the app does | Why |
|---|---|---|
| Format | Schedule III (Division I) as the ICAI Guidance Note applies it to non-corporate entities: partners' capital and current accounts instead of share capital. | Indian AS, no small-entity exemptions. |
| Comparatives | Balance sheet: the day before the From date (for a year to date, 31 March). Profit and loss and cash flow: the same dates a year earlier for a year to date; otherwise the period just before, of the same length. | AS 1 and Schedule III comparatives. |
| Current maturities | Loan and lease principal due within 12 months is shown under short-term borrowings. | Schedule III. |
| Purchases of stock-in-trade | Bought-in goods sold as they are (for example, merchandise) are shown as purchases of stock-in-trade. Raw materials go under cost of materials consumed. | Schedule III. |
| Cash flow | Indirect method. Each account's cash-flow tag (operating, investing, financing) decides where it goes. Interest paid is financing; interest received is investing. Opening balances brought in are part of the opening cash, not a cash flow. | AS 3 paragraphs 18, 31 to 33, 43. |
| Two tag corrections | Accumulated depreciation and amortisation accounts are now tagged "non-cash", and Rent Equalisation (40020120) "operating". | Otherwise depreciation would be counted twice, and the rent spread would show as financing. |
| Year-end close | The year's profit or loss goes to the partners' current accounts (50010135) by the ratio in Settings, as one journal dated 31 March. The statement of profit and loss for the year still shows the profit. Running it again closes entries made late. An earlier year must be closed first. | Partnership accounts. |
| Taxes | The app does not work out income tax. The CA posts the tax provision as a journal before the close; it shows as tax expense. | The tax computation is the CA's. |
| Dashboard top row | Sales this month, gross margin this month, cash and bank, customers owe, owed to suppliers. | Spec section 10 asked which 3 to 5 numbers: these are the defaults until you choose. |
| Weekly Sheets copy | Every Monday, 4 to 5 AM. Amounts in rupees, DEMO rows marked. The copy replaces the tabs each week. | Spec section 10. |
| Who sees it | Directors, the FC and the Accountant. Managers and below see nothing. Only the FC or a Director can close a year or change the Looker link. | Spec sections 4 and 10. |

**For your CA (please ask them):**

1. Are they happy with the statement layout and the line each account goes to (**Reports → Statement lines**)?
2. Trade payables have to be split between micro and small enterprises (MSME) and others. Suppliers have no MSME field yet. Which suppliers are MSME? We can add the field.
3. Partners' salary and interest on capital (section 40(b)): what rates should be used? For now they are entered as journals.
4. **Still open from modules 6 and 7:** the provision percentages for each age band of overdue customer money, the kitchen's normal monthly output in kg, the list of current loans and leases, and which leases are finance leases.

**For you:**

1. Which Google accounts (the Director, the FC and the Accountant) should see the Looker Studio report?
2. Are the five numbers on the dashboard's top row the right ones?

## Step 1. Take a backup (1 minute)

In the app: **Settings → Backup now (file for restore)**. Keep the file.

## Step 2. Supabase: add the module 8 tables (3 minutes)

1. Open your project at [supabase.com/dashboard](https://supabase.com/dashboard), then **SQL Editor → New query**.
2. Open `sql/08_reports.sql` from the repository (on GitHub, click the file, then the **Copy raw file** button).
3. Paste it and press **Run**. If Supabase warns about "destructive operations", press **Run this query**. That is expected.
4. You should see **Success. No rows returned**.

The file is safe to run again. Running it again keeps any statement-line rules you added.

> **Important:** if `01` to `07` is ever run again, run every later file again straight after it, in order, ending with `08`.

## Step 3. The screens

Once the pull request is merged into **main**, GitHub Pages publishes the new screens within a couple of minutes. Reload the app. On a phone, close the app fully and open it again.

The home menu now shows **Reports** without a "Module 8" label.

## Step 4. The weekly Google Sheets copy (5 minutes)

1. Open the Ruchi Buds Apps Script (the one you set up in module 1, at [script.google.com](https://script.google.com)).
2. Open `Code.gs`. Delete what is in it, then paste in all of `apps-script/Code.gs` from the repository. Press **Save**.
3. At the top, choose **setupTriggers** and press **Run**. Allow the new permission it asks for (Google Sheets).
4. Choose **weeklySheetsCopy** and press **Run**. It makes a Google Sheet called **Ruchi Buds Reporting** in your Drive, with a tab for each set of data.
5. In the app, **Reports → Analysis (Looker Studio)** now shows the date of the last copy and a link to the sheet.

The secret key stays in the Script Properties, as before. Nothing new is needed there.

## Step 5. Looker Studio (15 minutes)

1. Open [lookerstudio.google.com](https://lookerstudio.google.com) with the same Google account and press **Blank report**.
2. Choose **Google Sheets**, then **Ruchi Buds Reporting**, then the **sales_lines** tab. Press **Add**.
3. Add charts as you like (for example, sales by month and by product). Use **Resource → Manage added data sources → Add a data source** for the other tabs (monthly_balances, purchase_lines, expenses, loans).
4. Press **Share**. Add only the named Google accounts of the Director, the FC and the Accountant. Under **Manage access**, keep link sharing **off**.
5. Share the **Ruchi Buds Reporting** sheet with the same accounts only, as **Viewer**.
6. Press **File → Embed report**, tick **Enable embedding**, and copy the link.
7. In the app (as a Director or the FC): **Reports → Analysis (Looker Studio)**, paste the link and press **Save the link**. The report shows in the app for anyone signed in to Google with one of those accounts. Others see a Google sign-in box instead.

## Step 6. Access (2 minutes)

**Users → Categories and access**: check the **Reports** row. By default:

- Managers and below have no access.
- The Accountant can view reports and margins.
- Directors and the FC can do everything, including closing the year.

## Files in this module

| File | What it is | Where it goes |
|---|---|---|
| `sql/08_reports.sql` | The database for module 8 | Paste into Supabase SQL Editor (step 2) |
| `reports.js` | The Reports screen | Already in the repository, served by GitHub Pages |
| `index.html`, `ruchi.css` | Updated (loads the new screen and its styles) | The same |
| `apps-script/Code.gs` | Version 1.1, adds the weekly Google Sheets copy | Google Apps Script (step 4) |
| `docs/module-8-test-checklist.md` | What to tick before sign-off | Read and tick |
| `tests/test_reports.sql`, `tests/e2e_reports.js` | The automatic checks used while building | Not needed in Supabase |

## If something goes wrong

- **"permission denied for function …"** on any screen: run `08_reports.sql` again (usually because an earlier file was run after it).
- **The balance sheet "does not balance"**: take a screenshot and send it in the project thread.
- **"The year can be closed once it has ended"**: the year-end close can only be posted from 1 April.
- **"An earlier year still has profit or loss that is not closed"**: close the earlier year first.
- **"The Looker Studio link must start with …"**: copy the link from **File → Embed report** in Looker Studio.
- **The Looker report shows a Google sign-in box**: sign in to Google in the same browser with an account the report is shared with.
- **The last Sheets copy shows FAILED**: open the Apps Script and run **weeklySheetsCopy** by hand. The error shows in the log and is emailed to ALERT_EMAIL.
- Anything else: take a screenshot and send it in the project thread.
