# Ruchi Buds app

Operations and accounts for Ruchi Buds (entity E002): purchases, stock, production, sales, invoices and the ledgers behind them. It runs on free services only: Supabase for the database and logins, GitHub Pages for the screens, and Google Apps Script for backups.

**App link:** https://inforuchibuds-rgb.github.io/ruchi-buds-app/

## Modules

| # | Module | Database file | Screens | Status |
|---|---|---|---|---|
| 1 | Core and users | `sql/01_core_users.sql` | `core.js`, `users.js`, `settings.js` | Signed off |
| 2 | Masters, COA and ledger | `sql/02_masters.sql` | `masters.js`, `accounts.js` | Signed off |
| 3 | Purchases and AP | `sql/03_purchases.sql` | `purchases.js` | Signed off |
| 4 | Stock and production | `sql/04_stock_production.sql` | `stock.js` | Signed off |
| 5 | Sales, invoices and AR | `sql/05_sales_invoices.sql` | `sales.js`, `invoices.js` | Signed off |
| 6 | Cash, bank and expenses (with the month-end steps) | `sql/06_cash_bank.sql` | `cashbank.js` | Built, awaiting sign-off |
| 7 | Loans and leases (AS 19) | `07_loans_leases.sql` | `loans.js` | |
| 8 | Reports and Sheets copy | `08_reports.sql` | `reports.js` | |
| 9 | Backup and restore | `09_backup.sql` | `apps-script/Code.gs` | Nightly backup and keep-awake already live from module 1 |
| 10 | Online shop | | | |

## Setting up and testing

- [Module 1 setup guide](docs/module-1-setup-guide.md)
- [Module 1 test checklist](docs/module-1-test-checklist.md)
- [Module 2 setup guide](docs/module-2-setup-guide.md)
- [Module 2 test checklist](docs/module-2-test-checklist.md)
- [Module 3 setup guide](docs/module-3-setup-guide.md)
- [Module 3 test checklist](docs/module-3-test-checklist.md)
- [Module 4 setup guide](docs/module-4-setup-guide.md)
- [Module 4 test checklist](docs/module-4-test-checklist.md)
- [Module 5 setup guide](docs/module-5-setup-guide.md)
- [Module 5 test checklist](docs/module-5-test-checklist.md)
- [Module 6 setup guide](docs/module-6-setup-guide.md)
- [Module 6 test checklist](docs/module-6-test-checklist.md)

Run the SQL files in number order. If an earlier file is ever run again, run every later file again straight after it.

## Rules every module follows

- Each SQL file can be run twice without harm, and starts with its module name, version and date.
- Screens never write to tables directly. Every change goes through an `rb_` database function that checks the person's ticks and writes the audit log.
- Every record carries `is_demo` (and later `is_training`), so "Remove demo data" and go-live are one safe step each.
- Dates show as dd-mmm-yyyy. Money is stored in whole paise.
- `config.js` holds only the public Project URL and publishable key. The secret key lives only in the Apps Script's Script Properties.

## For developers

`tests/` holds a Supabase stand-in (`supabase_stub.sql`), SQL behaviour tests (`test_core.sql`, `test_masters.sql`, `test_purchases.sql`, `test_stock.sql`, `test_sales.sql`, `test_cashbank.sql`), a local mock of the Supabase API (`mock-supabase.js`) and Playwright walk-throughs (`e2e.js`, `e2e_masters.js`, `e2e_purchases.js`, `e2e_stock.js`, `e2e_sales.js`, `e2e_cashbank.js`). Run them against a throwaway local Postgres only. Third-party libraries are copied into `vendor/` (supabase-js 2.119.0, Tabulator 6.3.1, SheetJS 0.18.5) so the app doesn't depend on a CDN; their licences are alongside.
