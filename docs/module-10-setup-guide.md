# Ruchi Buds app: Module 10 setup guide

Version 1.0 · 27-Nov-2026 · Module 10: Online shop

This update takes about 15 minutes. You paste two files into Supabase, update the Apps Script, and set up the shop in the app. GitHub Pages publishes the screens and the shop page on its own once the pull request is merged.

## What module 10 gives you

- **A public shop page** that customers open with no password:
  `https://inforuchibuds-rgb.github.io/ruchi-buds-app/shop.html`
  Share it on WhatsApp and Instagram. It shows the photo, product, pack size and price of each pack you choose. Stock is live: a pack with no free stock shows **SOLD OUT**.
- **Ordering:** the customer fills a cart, gives name, mobile number and address, and chooses **delivery** (charge by PIN code, added automatically) or **pickup**. Orders are numbered **ORD/YYMM/00001**.
- **Stock on hold:** the moment an order is placed, its packs are held. They cannot be sold at the counter or online. An unpaid UPI order lets go of them after the minutes you set (30 to start with).
- **Payment:**
  - **UPI:** the customer scans the QR code (or taps "Open my UPI app"), pays to the firm's UPI ID, and types the UPI reference (UTR). Staff check that the money reached **Bank account 1** and tick **Paid**. This books a customer receipt.
  - **Cash on delivery:** only when every item in the cart is ticked "Cash on delivery allowed". The packs are held until the order is dispatched. The cash is recorded when it comes in, and it goes to cash in hand.
  - No payment gateway for now (your choice). One can be added later.
- **Alerts:** paid and cash-on-delivery orders, and UPI payments to check, alert the staff categories you choose. They see a line on the home screen and a count on the tile. They also get an email, which their phone shows as a notification. WhatsApp messages are not automatic, but each order has a **Message on WhatsApp** button with the message ready.
- **Packing and dispatch:** staff press **Packed**, then **Dispatched** (or **Handed over** for pickup). That makes the invoice (channel Online, with the delivery charge on it), and the stock leaves finished goods. A paid order's receipt is set against the invoice.
- **Cancelling:** before dispatch, staff can cancel an order with a reason, and the packs are free again. If it was paid, the money stays on the customer's account, and the accounts team refunds it from **Invoices → Customers**. After dispatch, use a sales return on the invoice. Customers can cancel an unpaid order from their order page.
- **Stock → Finished goods** now shows **Total packs**, **On hold (online)** and **Free to sell**.
- **Online shop orders → Report:** orders, value, paid by UPI, cash on delivery and cancelled, by day and by product.

## Decisions built in (please check them)

| Topic | What the app does | Why |
|---|---|---|
| Who sets up the shop | Only Directors and the FC (a new right, **Set up the online shop**, given to no category): which packs show, photos, cash on delivery, delivery charges, UPI ID, alerts, opening and closing the shop. | Spec 8A: "The Director or FC chooses which products appear". |
| Who runs orders | Anyone with **Online shop orders → Edit**: Accountant, Manager and Sales to start with (change it in Users). They tick Paid, pack, dispatch, record cash and cancel. | Spec: staff tick Paid and pack the order. |
| Price | The **online price** of the pack in Masters (the retail price if no online price). The order keeps the price the customer saw. | |
| Delivery charge | From the PIN code list in **Shop set-up**. A line with PIN **\*** covers every other PIN code. Without it, the shop does not deliver to PIN codes not in the list. Staff can change the charge before payment (cash on delivery: before dispatch). On the invoice it is credited to **Delivery Charges Recovered (60060125)**. | Spec 8A. |
| GST | Until the firm is GST registered, orders are invoiced with no GST. After registration, online orders become Tax Invoices, and the delivery charge takes the GST rate of the goods. | **Check with your CA:** how online sales affect GST registration and invoices (for example, sales to other states). |
| Holding time | Unpaid UPI orders are held for 30 minutes (5 to 1440, in Shop set-up). A payment that arrives a little late is still accepted if the packs are still free. | |
| Misuse | At most 3 unpaid orders per mobile number (changeable), at most 50 of one pack per order, and at most 200 unpaid orders in all at a time. | So nobody can hold all the stock without paying. |
| Customers | The first order from a mobile number adds a retail customer with that number, so online sales show in the customer's statement. | |
| Photos | Picked on the phone or computer and made small automatically (about 600 pixels), kept in the database and in the backups. | No extra service needed. |
| Training mode | The DEMO products, DEMO delivery charges and 4 DEMO orders appear while the app is in training mode. "Remove demo data" and go-live remove them. Orders placed during training are cleared at go-live. | As in every module. |

## Step 1. Take a backup (1 minute)

In the app: **Settings → Backup now (file for restore)**. Keep the file.

## Step 2. Supabase: run two files (5 minutes)

1. Open your project at [supabase.com/dashboard](https://supabase.com/dashboard), then **SQL Editor → New query**.
2. Open `sql/05_sales_invoices.sql` from the repository (on GitHub, click the file, then the **Copy raw file** button). Paste it and press **Run**. It is version 1.2: it adds the delivery charge to invoices.
3. Because 05 was run again, run the later files again straight after it, in order, each in a new query: `06_cash_bank.sql`, `07_loans_leases.sql`, `08_reports.sql`, `09_backup.sql`.
4. Then run the new file, `sql/10_shop.sql`.
5. If Supabase warns about "destructive operations", press **Run this query**. That is expected. Each should end with **Success. No rows returned**.

Every file is safe to run again. Running it again changes nothing and loses nothing.

## Step 3. The screens and the shop page

Once the pull request is merged into **main**, GitHub Pages publishes the new screens and `shop.html` within a couple of minutes. Reload the app. On a phone, close the app fully and open it again. The home screen now has **Online shop orders**.

## Step 4. Set up the shop (5 minutes, as a Director or the FC)

Open **Online shop orders → Shop set-up**:

1. **UPI ID the money goes to:** the UPI ID of Bank account 1 (for example `ruchibuds@okaxis`), and the **name shown to the customer**.
2. **Pickup address** and the **phone number** customers can call.
3. **Alerts:** tick the categories that should be told about new orders (for example Sales and Manager).
4. **Delivery charges by PIN code:** add your PIN codes and charges. Remove or switch off the DEMO ones before go-live. Add a **\*** line if you deliver everywhere else.
5. Tick **Shop open** and press **Save**.

Then **Products online**: tap each pack you want to sell, tick **Show on the shop**, add a photo and a short description, and tick **Cash on delivery allowed** where it is.

Finally press **Copy the link** or **Share on WhatsApp** at the top of Shop set-up.

## Step 5. The Apps Script, for alert emails (3 minutes)

1. Open the Ruchi Buds Apps Script at [script.google.com](https://script.google.com).
2. Open `Code.gs`. Delete what is in it, then paste in all of `apps-script/Code.gs` from the repository (version 1.3). Press **Save**.
3. Choose **setupTriggers** and press **Run**. It sets the timers again, adding **shopAlerts** every 5 minutes. Allow the permission it asks for (sending email as you).

The free Gmail account can send emails to about 100 people a day. Each alert email counts once per person it goes to. One email collects all new alerts from the last 5 minutes. If the limit is reached, the alerts still show in the app.

## Step 6. On each staff phone (optional)

In **Online shop orders → Shop set-up**, press **Allow notifications here**. While the app is open, new orders then also pop up as a notification.

## Files in this module

| File | What it is | Where it goes |
|---|---|---|
| `sql/05_sales_invoices.sql` | Version 1.2: the delivery charge on invoices | Supabase SQL Editor (step 2) |
| `sql/10_shop.sql` | The database for module 10 | Supabase SQL Editor (step 2) |
| `shop.html`, `shopfront.js` | The public shop page | Already in the repository, served by GitHub Pages |
| `shop.js` | The Online shop orders screen and the home-screen alerts | The same |
| `index.html`, `core.js`, `stock.js`, `invoices.js`, `ruchi.css` | Updated (loads the screen; home alerts; On hold in Stock; delivery on invoices; shop styles) | The same |
| `vendor/qrcode.js` | Draws the UPI QR code (qrcode-generator 2.0.4, MIT licence) | The same |
| `apps-script/Code.gs` | Version 1.3: shopAlerts | Google Apps Script (step 5) |
| `docs/module-10-test-checklist.md` | What to tick before sign-off | Read and tick |
| `tests/test_shop.sql`, `tests/e2e_shop.js` | The automatic checks used while building | Not needed in Supabase |

## If something goes wrong

- **"permission denied for function …"** on any screen: run `10_shop.sql` again (usually because an earlier file was run after it).
- **The shop page says "The shop is closed just now"**: tick **Shop open** in Shop set-up and save.
- **A product does not show on the shop**: it needs **Show on the shop** ticked, an online or retail price in Masters, and the pack switched on. DEMO products show only in training mode.
- **"… held for online orders, so only N can be sold now"** at the counter: those packs belong to online orders. Dispatch or cancel the orders first.
- **"Sorry, we do not deliver to PIN code …"**: add that PIN code (or a **\*** line) in Shop set-up.
- **No alert emails**: check that categories are ticked under Alerts, that **setupTriggers** was run after pasting version 1.3, and the Apps Script's **Executions** list for errors.
- Anything else: take a screenshot and send it in the project thread.
