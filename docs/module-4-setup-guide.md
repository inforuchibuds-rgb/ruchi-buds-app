# Ruchi Buds app: Module 4 setup guide

Version 1.0 · 27-Nov-2026 · Module 4: Stock and production

This update takes about 10 minutes. You paste one file into Supabase. GitHub Pages updates the screens on its own once the pull request is merged.

## What module 4 gives you

- **Production** (home → Production), with one **Production window** and a switch at the top:
  - **Preparation**: raw material in (for example 10 kg fish), the wastage at each stage (clean, boil and de-bone, fry), any by-products (skin, bones, trimmings) and the prepared ingredient out. The stages come from the item in Masters, and you can add more. The window shows the yield as you type. Numbered PRP/YYMM/00001.
  - **Final production**: prepared ingredients and other raw materials in (oil, spices), and finished goods out, entered as **packs made** (bottles and pouches), plus loose for items sold by weight. Frying shrinkage and packing wastage are entered here. Each pack takes one empty bottle or pouch out of stock. Numbered PRD/YYMM/00001.
  - **Prepare and produce together**: for same-day items such as fish and chicken. One entry makes both batches, linked to each other.
  - **Copy what went into the last batch** fills in the items of the previous batch of the same product, so you only type today's quantities.
  - An **unusual loss** (a tray dropped, a batch burnt) can be entered with a reason. Its cost is charged as a loss rather than added to the product.
- **Batch window**: what went in (and from which preparation batch), wastage at each stage, by-products, what came out, the cost per pack (for those allowed to see costs), and where a prepared batch was used. **Reverse batch** undoes it on a date you choose.
- **Stock** (home → Stock):
  - **Raw and prepared**: every raw material, bottle, pouch and prepared ingredient with its quantity, oldest batch and value. Below it, prepared ingredients **batch by batch** with the date prepared. Anything past its shelf life is in **red**. When a production batch picks it, the window warns before saving.
  - **Finished goods**: stock by product and pack (for example "Fish pickle, 200 g bottle: 40 packs"), and sellable by-products.
  - Tap any line to see its **movements**: every in and out with a running balance.
  - **Stock counts**: count what is on the shelves. The differences against the books are posted once someone other than the counter approves the count.
  - **Opening stock**: stock on hand at go-live, with what it cost.
  - **Write-offs** for spoilt, expired or damaged stock, and **write-downs** for stock that will sell for less than it cost.
- **Reports** on the Production screen: the **yield report** (raw → prepared → finished goods, batch by batch, with wastage % at each stage) and **wastage by stage**. Both download to Excel.
- **DEMO data** (November 2026): 13 batches made from the DEMO purchases, covering ginger, garlic and onion preparation; chilli powder in packs and loose; meat with trimmings; fish and chicken prepared and produced together; a smoked meat pickle; and a meat batch with an unusual loss. There are also a posted stock count, a count waiting for approval, a posted write-off and a write-off waiting for approval.

## Decisions built in (please check them)

| Topic | What the app does | Why |
|---|---|---|
| Stock valuation | Weighted average cost (the Settings choice from module 2). A batch's cost is the cost of everything that went in. | AS 2, Valuation of Inventories. |
| Normal wastage and shrinkage | Stays in the cost of what was made, so the cost per kg goes up. | AS 2: normal losses are part of cost. |
| Unusual loss | Its share of the cost is taken out of the batch and charged to **Inventory Write-down Expense** (70010150). | AS 2: abnormal waste is not part of the cost of stock. |
| By-products | A **sellable** by-product (set on the item in Masters) goes into stock at its loose selling price, and that value comes off the main product's cost. A **discarded** one is simply wastage. | AS 2 treatment of by-products. |
| Stock accounts | Raw materials 10030105, packaging 10030110, prepared ingredients (work in progress) 10030120, finished goods and by-products 10030125. Each always equals the stock lists. | Stock accounts move only through stock records. |
| Prepared ingredients | Kept batch by batch with the preparation date. A production batch takes the oldest first unless you pick a batch. | Shelf life checks, spec section 7. |
| Finished goods | Kept by product **and pack**, counted in packs. They leave stock only through an invoice (module 5). | Spec section 7. |
| Stock below zero | Never allowed, on the batch date or after later entries. | Spec section 7. |
| Count differences | Shortages and excesses go to **Inventory Shrinkage Expense** (70010155), at average cost. The person who counted cannot approve, except Directors, the FC and the Accountant. | Spec section 4. |
| Opening stock | Entered as a stock count with costs, and posted against **Opening Balance Migration Clearing** (97010105). Only those who can see costs can enter it. | Matches the opening balances from module 2. |
| Write-offs and write-downs | Both go to **Inventory Write-down Expense**. A Manager's write-off waits for approval. A write-down (lowering the cost to what it will sell for) is only for the Accountant, FC or a Director. | AS 2: stock at the lower of cost and net realisable value. |
| Who sees costs | Only those with the **margin** tick on Stock or Production (Accountant, FC, Directors). Managers and staff see quantities only. | Spec section 4. |
| Numbers | PRP, PRD, SC (stock count), OS (opening stock), WO (write-off) and WD (write-down) run on, YYMM from the date. Training entries start TRN-…, DEMO entries DEMO-…. | Spec section 8. |
| Learning-phase full delete | During someone's learning phase, a Director or the FC can fully delete their batch. | Spec section 4. |

**Not in this module, for your CA:** labour and kitchen overheads are not yet added to the cost of stock. Under AS 2 they belong there. Expenses arrive in module 6, so this can be a month-end step then. Please ask your CA how they would like it done.

## Step 1. Take a backup (1 minute)

In the app: **Settings → Backup now (file for restore)**. Keep the file.

## Step 2. Supabase: add the module 4 tables (3 minutes)

1. Open your project at [supabase.com/dashboard](https://supabase.com/dashboard), then **SQL Editor → New query**.
2. Open `sql/04_stock_production.sql` from the repository (on GitHub, click the file, then the **Copy raw file** button).
3. Paste it and press **Run**. If Supabase warns about "destructive operations", press **Run this query**. That is expected.
4. You should see **Success. No rows returned**.

The file is safe to run again. Running it again changes nothing and loses nothing.

> **Important:** if `01`, `02` or `03` is ever run again, run every later file again straight after it, in order (01, 02, 03, 04). Each file resets who may use the database functions, and the later files put their own back.

## Step 3. The screens

Once the pull request is merged into **main**, GitHub Pages publishes the new screens within a couple of minutes. Reload the app. On a phone, close the app fully and open it again.

The home menu now shows **Stock** and **Production** without a "Module 4" label.

## Step 4. Masters and access

1. **Masters → Items**: for each raw material, check its **stages** (for example Clean, Boil and de-bone, Fry) and its **prepared ingredient**. For each prepared ingredient, set its **shelf life** in days. For each by-product, choose **sellable** or **discarded**, and give sellable ones a loose selling price.
2. **Masters → Packs and prices**: each pack type needs its empty bottle or pouch, so production can take it out of stock.
3. **Users → Categories and access**: check **Stock** and **Production** for each category. By default Managers can view, add, edit and approve, without costs. The Accountant also has **margin** (sees costs).

## Files in this module

| File | What it is | Where it goes |
|---|---|---|
| `sql/04_stock_production.sql` | The database for module 4 | Paste into Supabase SQL Editor (step 2) |
| `stock.js` | The Stock and Production screens | Already in the repository, served by GitHub Pages |
| `index.html`, `ruchi.css`, `purchases.js` | Updated (loads the new screens, styles, a wording change) | The same |
| `docs/module-4-test-checklist.md` | What to tick before sign-off | Read and tick |
| `tests/test_stock.sql`, `tests/e2e_stock.js` | The automatic checks used while building | Not needed in Supabase |

## If something goes wrong

- **"permission denied for function …"** on any screen: run `04_stock_production.sql` again (usually because an earlier file was run after it).
- **"Not enough … in stock"**: stock can never go below zero. Check the purchase or the preparation batch was entered first, and its date is on or before this one.
- **"… is locked"**: the month is locked. A Director or the FC unlocks it in Accounts → Month lock, with a reason.
- **"Reverse … first"** when reversing a preparation batch: some of it went into a production batch. Reverse that one first.
- Anything else: take a screenshot and send it in the project thread.
