# Ruchi Buds app: Module 2 setup guide

Version 1.2 · 27-Nov-2026 · Module 2: Masters, chart of accounts and ledger

## What's new in version 1.2: Clone, and Reverse and correct

Open any journal in **Accounts → Journals**:

- **Clone** makes a new draft with the same lines and description. Change what you need (date, amounts, accounts) and **Save draft**. It is posted (approved) like any other journal, so a second person still approves it. The draft shows **Copied from** with the original's number. Any journal can be cloned except a reversal. A copy of a journal from another screen (purchases, sales and so on) becomes a manual journal, so stock lines are refused when you save it.
- **Reverse and correct…** is on posted manual and opening-balance journals. Give one date (in an open month, on or after the original) and what was wrong. In one step the original is reversed, and a draft copy is saved on that date and opens for you to fix. If you close it, the draft waits in the journal list. Nothing happens if any part fails. It needs both the **Reverse posted entries** special right and **Accounts → Add**. Journals from other screens are still reversed in their own screen (for example open the purchase), so stock and party balances stay right.

Posted journals still cannot be edited, so the books always keep the original, its reversal and the correction.

**To install version 1.2 (about 10 minutes):**

1. Take a backup: **Settings → Backup now (file for restore)**.
2. In Supabase **SQL Editor**, run these files again, one after the other, in this order: `sql/02_masters.sql`, `sql/03_purchases.sql`, `sql/04_stock_production.sql`, `sql/05_sales_invoices.sql`, `sql/06_cash_bank.sql`, `sql/07_loans_leases.sql`. Each should end with **Success. No rows returned**. Nothing is lost; the later files must follow because each one puts back its own rules after the earlier file.
3. Reload the app once the pull request is merged.
4. Tick section H of the [test checklist](module-2-test-checklist.md).

`sql/04_stock_production.sql` also has a one-line fix in this update, so that running it again after module 6 no longer stops with a "stock_moves_kind_check" error.

## First-time setup

The first-time setup takes about 10 minutes. You paste one file into Supabase. GitHub Pages updates the screens on its own once the pull request is merged.

## What module 2 gives you

- **Masters** (home → Masters):
  - **Items**: raw materials, work in progress, finished goods, by-products (Sellable or Discarded) and packaging, each with its base unit (g, ml, pc or box), HSN, GST rate and preparation stages.
  - **Packs and prices**: pack types (bottles, pouches, jars), and product packs (for example Prawn pickle, 180 g in a 200 g bottle) with retail, trader and online prices.
  - **Departments**: add, rename and merge, with a dated history that you can undo. Old reports show the new name.
  - **Units**.
- **Customers**: retail, trader and online, with a Promotions list that shows only people who agreed to messages. Walk-in customer C00000 is ready for counter sales.
- **Suppliers**: with GSTIN, PAN, bank details and credit days.
- **Accounts**:
  - **Journals**: hand-keyed journals that are saved as a draft, posted, and reversed. A journal can never be edited after it is posted: use **Reverse and correct** or **Clone** (version 1.2).
  - **Trial balance**: for any date range, filtered by department.
  - **Account ledger**: for any account, filtered by customer, supplier, partner or department.
  - **Chart of accounts**: the Master COA (8-digit IFRS codes), with your own local accounts and an Excel import for updates.
  - **Posting rules**: which accounts each purchase, stock and sales event will post to, from module 3 onwards.
  - **Month lock**: once a month is locked, nothing can be posted, reversed or deleted in it.
- **DEMO data** to try every screen: 29 items, 10 product packs, 10 customers, 10 suppliers, a demo department with a rename, and 14 journals.

## Decisions built in (please check them)

| Topic | What the app does | Why |
|---|---|---|
| Second person on journals | A manual journal must be posted by a **different person** from the one who keyed it. You can switch this off in Accounts → Month lock → Ledger settings. | Spec section 9A: approval by a second person. |
| Stock accounts | Inventory accounts cannot be picked in a manual journal. Stock only moves through Purchases, Stock and Sales. | Stops the stock ledger and the books drifting apart. |
| Chart of accounts | 509 posting accounts in 73 families, from the Master COA. **79 IFRS-only or consolidation accounts are hidden** (for example right-of-use assets, OCI and NCI). You can unhide any of them. | Ruchi Buds reports under Indian AS (ICAI). AS 19 leases stay as operating or finance leases. |
| Extra account | Local account **70010160 Cost of Finished Goods Sold** was added, because the Master COA has no direct cost line for selling finished goods. | Needed for the sale cost posting in module 5. |
| Cash flow (AS 3) | Each account has a cash-flow tag (cash, operating, investing, financing, non-cash). The tags were set by rules from the account groups. Please ask the FC to look over them in Chart of accounts. | Full AS 3 cash flow statement in module 8. |
| Stock valuation | **Weighted average** is the default. FIFO can be chosen in Ledger settings. Choose before the first stock entry in module 3 and keep it (AS 2 needs the same method every year). | AS 2 allows either. Weighted average is simpler for pickles made in batches. |
| Starting departments | CC001 Kitchen and production, CC002 Retail counter, CC003 Trade sales, CC004 Online shop, CC005 Administration. | **This is my guess.** Rename or merge them to match the real list. The history keeps old reports right. |
| Prices | Each product pack holds three prices: retail, trader and online. | Section 6 of the spec. |
| Packaging | Empty bottles and pouches are items of kind **Packaging**. Each pack type links to one, so production can use them up from stock in module 4. | Packaging stock is counted like any other stock. |
| Journal numbers | JV/YYMM/00001 after go-live. In training mode, journals are numbered TRN/…, and DEMO journals DEMO/…. | Training and demo entries are wiped at go-live without leaving gaps in the real series. |
| Year end | The trial balance starts profit and loss again every 1 April. Until the year-end close in module 8, last year's profit shows in 50020105. | Matches the April–March financial year. |
| Learning-phase full delete | During someone's learning phase, a Director or FC can fully delete their journal. This is not written to the audit log. | Spec section 4. |
| Month lock | Unlocking a month needs a reason, and the reason is logged. A month with unposted drafts cannot be locked. | Keeps each month's figures and the monthly consolidation file stable. |

## Step 1. Take a backup (1 minute)

In the app: **Settings → Backup now (file for restore)**. Keep the file.

## Step 2. Supabase: add the module 2 tables (3 minutes)

1. Open your project at [supabase.com/dashboard](https://supabase.com/dashboard), then **SQL Editor → New query**.
2. Open `sql/02_masters.sql` from the repository (on GitHub, click the file, then the **Copy raw file** button).
3. Paste it and press **Run**. If Supabase warns about "destructive operations", press **Run this query**. That is expected, because the file replaces its own rules.
4. You should see **Success. No rows returned**. The file is large (the whole chart of accounts is inside it), so it can take up to a minute.

The file is safe to run again. Running it again changes nothing and loses nothing.

> **Important:** if `01_core_users.sql` is ever run again, run `02_masters.sql` straight after it. Module 1's file resets who may use each database function, and module 2's file puts its own back.

## Step 3. The screens

Once the pull request is merged into **main**, GitHub Pages publishes the new screens within a couple of minutes. Reload the app. If a phone still shows the old home menu, close the app fully and open it again.

The home menu now shows **Masters**, **Customers**, **Suppliers** and **Accounts** without a "Module N" label.

## Step 4. Give people access

In **Categories and access**, the new screens are already ticked for the starting categories as in the build plan. Check them, and in particular:

- **Accounts → Approve**: who may post another person's journal. By default Director, FC and Accountant.
- **Special rights → Departments**: who may rename and merge departments. By default only Director and FC.

## Step 5. Your real departments and accounts

1. **Masters → Departments**: rename or merge the five starting departments to the real list. Use **Effective from** blank to change the name for all of history, or a date to change it from that date only.
2. **Accounts → Chart of accounts**: if your auditor sends an updated Master COA in Excel, use **Import Master COA workbook…**. Only the names, groups and flags of Master accounts are updated. Your local accounts and anything already posted are not touched.

## Files in this module

| File | What it is | Where it goes |
|---|---|---|
| `sql/02_masters.sql` | The database for module 2 | Paste into Supabase SQL Editor (step 2) |
| `masters.js` | Masters, Customers and Suppliers screens | Already in the repository, served by GitHub Pages |
| `accounts.js`, `users.js` (audit label) | Accounts screen (journals with Clone and Reverse and correct, trial balance, ledger, COA, posting rules, month lock) | The same |
| `index.html`, `settings.js`, `users.js` | Updated to version 1.1 | The same |
| `docs/module-2-test-checklist.md` | What to tick before sign-off | Read and tick |
| `tests/test_masters.sql`, `tests/e2e_masters.js` | The automatic checks used while building | Not needed in Supabase |

## If something goes wrong

- **"permission denied for function …"** on any screen: `02_masters.sql` needs running again (usually because `01_core_users.sql` was run after it).
- **"Some DEMO records are still used by real records"** when removing demo data: a real record (for example a real product pack) uses a DEMO item or pack type. Change that real record to use a real one, then try again.
- **"This journal comes from another screen. Reverse it there…"** on Reverse and correct: open the purchase, invoice, payment or loan entry in its own screen and reverse it there, then enter the right one there.
- **"This month is locked"**: unlock it in Accounts → Month lock (a Director or FC, with a reason), post, then lock it again.
- Anything else: take a screenshot and send it in the project thread.
