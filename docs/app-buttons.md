# Ruchi Buds app: buttons on every screen

Version 1.1 · 27-Nov-2026

## How to install

1. Merge the pull request.
2. In Supabase **SQL Editor**, run these files again, one after the other, in this order: `01_core_users.sql`, `02_masters.sql`, `03_purchases.sql`, `04_stock_production.sql`, `05_sales_invoices.sql`, `06_cash_bank.sql`, `07_loans_leases.sql`, `08_reports.sql`, `09_backup.sql`. Each should end with **Success. No rows returned**. File 01 adds the automatic sign-out setting, and file 08 adds Quick search. The other files must follow because each one puts back its own rules after the earlier file.
3. Reload the app. On a computer press **Ctrl + Shift + R**. On a phone close the app fully and open it again.

The buttons work as soon as the app is reloaded. Quick search and the sign-out setting need step 2.

## The buttons

| Button | Where | What it does |
|---|---|---|
| **‹ Back** | Top left of every screen | Goes to the screen you were on before. If the app was just opened, it goes up one level: from a record (for example a purchase) to its list, and from a list to Home. Useful in the installed phone app, which has no browser Back button. |
| **‹ Purchases**, **‹ Sales** … | Next to Back, on a single record | Goes straight to that list. |
| **⌂ Home** | Top left of every screen | The home menu. Tapping the Ruchi Buds logo does the same. |
| **⟳ Refresh** | Below the screen title | Loads the figures again without leaving the screen. |
| **🖨 Print** | Below the screen title | Prints what is on the screen. Lists print every row that passes your filters, not only the first page. Buttons are left off the paper. |
| **⬇ Excel** | Below the screen title | Downloads every list and table on the screen (or in the open window) into one Excel file, one sheet each. Many lists also keep their own **Download to Excel** button. |
| **? Help** | Below the screen title | A short note on what the screen is for and how to use it. |
| **✕** | Top right of every pop-up window | Closes the window without saving. **Esc** on a keyboard does the same. |
| **🔍 Search** | Top bar | Finds an invoice, purchase, journal, customer or supplier by its number, name or phone. Tap a result to open it. Each person only sees results from the screens they may open. Keyboard: **Ctrl + K**. |
| **🙈 Hide** | Top bar | Blurs the whole screen so people nearby cannot read it. Tap or click anywhere (or press any key) to show it again. Keyboard: **Ctrl + Shift + H**. The screen also hides by itself after 3 minutes without use, and when you switch to another app. |
| **Sign out** | Top bar | Signs out now. The app also signs out by itself after **30 minutes** without use. Change this in **Settings → Sign out automatically after this many minutes** (0 means never, up to 480). |

On a phone, Search and Hide show only their icons (🔍 and 🙈) to save space.

## Test checklist

- [ ] Open Purchases, then a purchase. **‹ Back** returns to the list, and **⌂ Home** goes to the home menu.
- [ ] On a phone (installed app), open a purchase, close the app, then open it again on that purchase. Press **‹ Back** twice: purchase → list → Home.
- [ ] Open **+ New journal** and press **✕**. The window closes and nothing is saved. Do it again with **Esc**.
- [ ] Press **🙈 Hide**. The screen blurs. Tap it and the screen shows again.
- [ ] Leave the app untouched for 3 minutes. It hides itself.
- [ ] In **Accounts → Journals**, press **⟳ Refresh**, **? Help** and **⬇ Excel**. The list reloads, a help note opens, and an Excel file downloads.
- [ ] Press **🖨 Print** on a long list. Every row is on the paper, and no buttons are.
- [ ] Press **🔍 Search** and type an invoice number. Tap the result and the invoice opens. Try a supplier's name, then a journal number.
- [ ] Sign in as someone without Accounts access. Search does not show journals.
- [ ] **Settings**: set automatic sign-out to 1 minute and save. Leave the app for a minute and it signs out with a note. Set it back to 30.
