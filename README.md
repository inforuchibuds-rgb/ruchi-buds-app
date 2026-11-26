# Ruchi Buds app

Operations and accounts for Ruchi Buds (entity E002): purchases, stock, production, sales, invoices and the ledgers behind them. It runs on free services only: Supabase for the database and logins, GitHub Pages for the screens, and Google Apps Script for backups.

**App link:** https://inforuchibuds-rgb.github.io/ruchi-buds-app/

## Modules

| # | Module | Database file | Screens | Status |
|---|---|---|---|---|
| 1 | Core and users | `sql/01_core_users.sql` | `core.js`, `users.js`, `settings.js` | Built, awaiting sign-off |
| 2 | Masters, COA and ledger | `02_masters.sql` | `masters.js` | Next |
| 3 | Purchases and AP | `03_purchases.sql` | `purchases.js` | |
| 4 | Stock and production | `04_stock_production.sql` | `stock.js` | |
| 5 | Sales, invoices and AR | `05_sales_invoices.sql` | `sales.js`, `invoices.js` | |
| 6 | Cash, bank and expenses | `06_cash_bank.sql` | `cashbank.js` | |
| 7 | Loans and leases (AS 19) | `07_loans_leases.sql` | `loans.js` | |
| 8 | Reports and Sheets copy | `08_reports.sql` | `reports.js` | |
| 9 | Backup and restore | `09_backup.sql` | `apps-script/Code.gs` | Nightly backup and keep-awake already live from module 1 |
| 10 | Online shop | | | |

## Setting up and testing

- [Module 1 setup guide](docs/module-1-setup-guide.md)
- [Module 1 test checklist](docs/module-1-test-checklist.md)

## Rules every module follows

- Each SQL file can be run twice without harm, and starts with its module name, version and date.
- Screens never write to tables directly. Every change goes through an `rb_` database function that checks the person's ticks and writes the audit log.
- Every record carries `is_demo` (and later `is_training`), so "Remove demo data" and go-live are one safe step each.
- Dates show as dd-mmm-yyyy. Money is stored in whole paise.
- `config.js` holds only the public Project URL and publishable key. The secret key lives only in the Apps Script's Script Properties.

## For developers

`tests/` holds a Supabase stand-in (`supabase_stub.sql`), SQL behaviour tests (`test_core.sql`), a local mock of the Supabase API (`mock-supabase.js`) and a Playwright walk-through (`e2e.js`). Run them against a throwaway local Postgres only. Third-party libraries are copied into `vendor/` (supabase-js 2.119.0, Tabulator 6.3.1, SheetJS 0.18.5) so the app doesn't depend on a CDN; their licences are alongside.
