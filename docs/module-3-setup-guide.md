# Ruchi Buds app: Module 3 setup guide

Version 1.0 · 26-Nov-2026 · Module 3: Purchases and supplier balances (AP)

This update takes about 10 minutes. You paste one file into Supabase. GitHub Pages updates the screens on its own once the pull request is merged.

## What module 3 gives you

- **Purchases** (home → Purchases), one window per purchase:
  - **Order (PO)**: supplier (or **+ New** to add one), items, quantity, unit, agreed rate and GST %. Numbered PO/YYMM/00001.
  - **Receive goods (GRN)**: what actually came in, by weight or count, and anything damaged or refused at the door. Numbered GRN/YYMM/00001. Kept goods go into stock now. A purchase can arrive in more than one delivery.
  - **Supplier bill**: the bill number, date, billed quantity, rate and GST, typed exactly as the supplier wrote it. This raises the supplier balance.
  - **Match view**: order, goods received and bill side by side for each line. Any difference in quantity, weight, rate or tax shows in **red**.
- **Direct purchase (no PO)**: for fish, meat, small cash buys and urgent top-ups. Receive and bill are entered together, with a reason, the payment (cash, UPI, bank or credit), and either the supplier's bill number or **No supplier bill** plus a photo or note. With no bill, the GRN number is the reference. When a fisherman is picked, **No supplier bill** ticks itself.
- **Differences**: every difference is flagged, however small. For each one the reviewer chooses **Accept** (with a reason) or **Reject** with an action: return the goods, raise a debit note to the supplier (DN/YYMM/00001), keep it open for a later delivery, or correct the rate to the PO rate. The **Differences** tab lists all open ones with supplier, type, amount and age in days.
- **Returns** to the supplier (PRN/YYMM/00001): goods leave stock and the supplier balance goes down.
- **Payments** (PAY/YYMM/00001) against open bills, by cash, UPI or bank. Anything paid above the bills is kept **on account** and can be set against later bills.
- **Supplier balances** for any date, with unpaid bills, the oldest bill's age and the overdue amount. Tap a supplier to see their **ledger**. The Suppliers screen also shows each balance and has a **Ledger** button.
- **Reports**: supplier differences by month (short supply, overcharges, goods refused), direct purchases by month, and stock bought so far.
- **DEMO data**: 11 purchases from the DEMO suppliers in November 2026. Among them are matched bills, bills with open differences, a settled rate difference with a debit note, a return, four direct purchases (two fish purchases with no bill) and one waiting for approval, plus 5 payments.

## Decisions built in (please check them)

| Topic | What the app does | Why |
|---|---|---|
| When stock and the supplier balance move | Stock goes up at **GRN**, at the PO rate, against "Goods received not invoiced" (30010115). The supplier balance goes up at the **bill**. | Spec section 6. AS 2: stock is recorded when the goods come in. |
| Bill differs from the GRN | The difference is added to (or taken off) the cost of the stock. | AS 2: stock carries what it really cost. |
| GST on bills | If the firm's **GSTIN is filled in Settings**, GST goes to Input GST recoverable (10050105). If it is blank, GST is added to the cost of the stock. | AS 2: tax that cannot be claimed back is part of cost. **Please ask your CA**, then fill or leave the GSTIN. Change it before the first real purchase and keep it. |
| Who settles differences | Quantity differences at delivery (short, extra, damaged): anyone with **Purchases → Approve** (Manager and up). Money differences (rate, tax, quantity on the bill) and debit notes: only the **Accountant, FC or a Director**, through a new special right **Settle purchase money differences**. AP and staff can see them but not settle them. | Spec section 6: "staff can flag but not settle". |
| Nobody settles their own entry | The person who entered a purchase cannot settle its differences or approve it, except Directors, the FC and the Accountant. | Spec section 4. |
| Paying with open differences | A purchase with any open difference cannot be paid. A bill saved as **Cash, UPI or Bank** with differences is refused: save it as **Credit**, settle, then pay. | Spec section 6. |
| Direct purchase limit | **Settings → Entry rules → Direct purchases above this need approval**. Above it, the purchase waits; nothing goes into stock or the books until the Accountant, FC or a Director approves it. A Director's, FC's or Accountant's own purchase posts straight away. **Blank means no approval is needed.** | Spec section 6. Please set a figure, for example ₹5,000. |
| Units | A line can be bought in any unit of the same kind as the item's stock unit (kg or g for weight, l or ml for volume, pc for pieces). Bottles that come in a "box" are bought by the piece, since a box holds a different number each time. | Stock is kept in grams, ml and pieces so it never drifts. |
| What can be bought | Only raw materials and packaging. Prepared and finished goods come from production (module 4). | Keeps the stock flow raw → prepared → finished. |
| Corrections | **Reverse purchase** (Accountant, FC, Director) undoes every entry the purchase made on a date you choose, and takes its stock back out. Reverse its payments first. Purchase entries cannot be reversed from Accounts and journals, so stock and the books always agree. | Spec section 4. |
| Learning-phase full delete | During someone's learning phase, a Director or the FC can fully delete their purchase or payment. This is not in the audit log. | Spec section 4. |
| Numbers | PO, GRN, DN, PRN and PAY run on and never restart; YYMM follows the document date. In training mode they start TRN-…, and DEMO records DEMO-…, so the real series starts clean at go-live. | Spec section 8 numbering rule, applied to purchases. |
| Photos | A photo is shrunk to about 1280 pixels before it is saved (around 100–200 KB), so five years of fish slips fit in the free plan. | Supabase free plan limits. |

## Step 1. Take a backup (1 minute)

In the app: **Settings → Backup now (file for restore)**. Keep the file.

## Step 2. Supabase: add the module 3 tables (3 minutes)

1. Open your project at [supabase.com/dashboard](https://supabase.com/dashboard), then **SQL Editor → New query**.
2. Open `sql/03_purchases.sql` from the repository (on GitHub, click the file, then the **Copy raw file** button).
3. Paste it and press **Run**. If Supabase warns about "destructive operations", press **Run this query**. That is expected.
4. You should see **Success. No rows returned**.

The file is safe to run again. Running it again changes nothing and loses nothing.

> **Important:** if `01_core_users.sql` or `02_masters.sql` is ever run again, run every later file again straight after it, in order (02, then 03). Each file resets who may use the database functions, and the later files put their own back.

## Step 3. The screens

Once the pull request is merged into **main**, GitHub Pages publishes the new screens within a couple of minutes. Reload the app. On a phone, close the app fully and open it again.

The home menu now shows **Purchases** without a "Module 3" label.

## Step 4. Settings and access

1. **Settings → Entry rules**: set the **direct purchase approval limit**.
2. **Settings → Firm details**: fill the **GSTIN** only if the CA confirms the firm is registered (see the GST row above).
3. **Users → Categories and access**: check **Purchases** for each category. By default AP can view, add and edit; Managers can also approve (settle delivery differences); the Accountant has the new special right **Settle purchase money differences**.

## Files in this module

| File | What it is | Where it goes |
|---|---|---|
| `sql/03_purchases.sql` | The database for module 3 | Paste into Supabase SQL Editor (step 2) |
| `purchases.js` | The Purchases screen | Already in the repository, served by GitHub Pages |
| `index.html`, `ruchi.css`, `masters.js`, `settings.js` | Updated (balances and ledger on Suppliers, the limit's hint in Settings) | The same |
| `docs/module-3-test-checklist.md` | What to tick before sign-off | Read and tick |
| `tests/test_purchases.sql`, `tests/e2e_purchases.js` | The automatic checks used while building | Not needed in Supabase |

## If something goes wrong

- **"permission denied for function …"** on any screen: run `03_purchases.sql` again (usually because 01 or 02 was run after it).
- **"Unit … does not fit this item"**: choose a unit of the same kind as the item (kg for an item kept in grams, pc for bottles).
- **"… has differences to settle first"** when paying: open the purchase and Accept or Reject each red line (the Accountant, FC or a Director for money differences).
- **"This entry comes from the Purchases screen"** in Accounts and journals: reverse it from the purchase or payment instead.
- **"… is locked"**: the month is locked. A Director or the FC unlocks it in Accounts → Month lock, with a reason.
- Anything else: take a screenshot and send it in the project thread.
