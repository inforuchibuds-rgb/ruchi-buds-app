# Ruchi Buds app: Module 2 test checklist

Version 1.2 · 27-Nov-2026

Tick each line on the real app before signing off module 2. You need DS's login and a second login with Accountant or FC rights (the test user from module 1 can be moved to Accountant for this).

**Sign-off gate (from the build plan):** a hand-keyed test journal posts, shows in a trial balance and is blocked once its month is locked.

## A. Items, packs and prices

- [ ] **Masters → Items** lists DEMO items with an orange **DEMO** badge.
- [ ] Add a raw item (for example Prawns, base unit g) with preparation stages "Clean, Devein, Fry". It gets a code RM0001.
- [ ] Add a finished item (for example Prawn pickle) with HSN and GST rate. It gets a code FG0001.
- [ ] Add a by-product without choosing **Sellable** or **Discarded**. It is refused.
- [ ] Add a packaging item (an empty 200 g bottle), then a pack type **200 g bottle** linked to it.
- [ ] Add a product pack: Prawn pickle, 180 g, in the 200 g bottle, with retail, trader and online prices. The prices show in ₹.
- [ ] Switch an item off. It disappears from the pick lists, but stays in the list with **Inactive**.

## B. Departments

- [ ] **Masters → Departments** shows the five starting departments. Rename or merge them to the real list.
- [ ] Rename one with **Effective from** blank. Old journals show the new name.
- [ ] Rename one with a date. Journals before that date keep the old name.
- [ ] Merge two departments. Journals of the merged one now count under the other in the trial balance.
- [ ] **History** shows each change. **Undo** the last one, and it goes back.
- [ ] Signed in as someone without the **Departments** special right, renaming is refused.

## C. Customers and suppliers

- [ ] Add a trader customer without a field you ticked as required in Settings. It is refused and names the field.
- [ ] Add a retail customer who agrees to promotions without a phone. It is refused.
- [ ] **Promotions list** shows only customers who agreed, and downloads to Excel.
- [ ] Add a supplier with GSTIN and credit days.

## D. The gate: journal, trial balance, month lock

- [ ] **Accounts → Journals → + New journal** as DS: date today, department, "Test journal: electricity paid in cash", Debit 80020110 Utilities ₹850, Credit 10010110 Cash on Hand ₹850. **Save draft**.
- [ ] The draft says someone else must post it. DS cannot post it.
- [ ] Try a line on a receivable account. The line asks for the customer.
- [ ] Try an inventory account. It is not offered.
- [ ] Try an unbalanced journal. Posting is refused and shows the difference.
- [ ] Sign in as the Accountant or FC and **Post** it. It gets a number TRN/YYMM/00001 (training mode).
- [ ] The posted journal has no **Change** button, and cannot be edited.
- [ ] **Trial balance** for this month shows Utilities debit ₹850 and Cash on Hand credit ₹850, and says **Balanced**.
- [ ] Click Utilities in the trial balance. The **Account ledger** opens with the journal.
- [ ] **Reverse** the journal with a reason. A reversing journal appears, and the trial balance goes back to zero for both lines.
- [ ] **Month lock**: lock last month (or the month of the test journal after posting a second one). Try to post, reverse or delete a journal dated in that month. Each is refused with "This month is locked".
- [ ] Unlock it: a reason is required. The audit log shows the lock and unlock with the reason.

## E. Chart of accounts and posting rules

- [ ] **Chart of accounts** shows the Indian AS view. Tick **Show accounts hidden for Ruchi Buds** and the IFRS-only accounts (for example right-of-use assets) appear, marked hidden.
- [ ] **+ Add a Ruchi Buds account** under a family adds an account with the next free code.
- [ ] **Import Master COA workbook…** with the Master COA file: it reports how many accounts were added, updated and skipped.
- [ ] The FC looks over the **Cash flow** column and corrects any tag that is wrong.
- [ ] **Posting rules** lists each event (purchases, production, sales, receipts and so on) with its account. Change one and change it back. The audit log shows both.

## F. Phones

- [ ] On a phone, Items, Customers and Journals lists scroll sideways and every button can be tapped.

## G. Demo data (do this last)

- [ ] **Settings → Remove demo data**, type REMOVE DEMO. DEMO items, customers, suppliers and journals disappear. Your real entries stay.
- [ ] If it says some DEMO records are still used, change your real record to use a real item or pack type, and try again.

## H. Clone, and Reverse and correct (version 1.2)

Use two logins with approval rights (for example DS and the FC or Accountant). Do this before G if you still have demo data, or with a test journal.

- [ ] Post a test journal: Debit 80020110 Utilities ₹500, Credit 10010110 Cash on Hand ₹500, "Test: gas bill".
- [ ] Open it and press **Reverse and correct…**. Leave the reason empty and press the button: it asks for the reason, and nothing changes.
- [ ] Give a date in an open month and the reason "Bill was ₹450". The original now shows **Reversed**, a reversal journal is posted, and a **Correct the copy** form opens with the same lines.
- [ ] Change both amounts to ₹450 and **Save draft**. The draft shows **Copied from** with the original's number. The original shows it under **Copies**.
- [ ] The person who saved the copy cannot post it (unless the second-person switch is off). Sign in as the other person and **Post** it.
- [ ] **Trial balance**: Utilities shows ₹450 for this test, not ₹500 or ₹950.
- [ ] Open the original again: there is no **Reverse and correct** button now, but **Clone** is there.
- [ ] Press **Clone**. A **Copy of …** form opens with today's date and the same lines. Change the description to "Test: gas bill, next month" and **Save draft**. It shows **Copied from**. Delete this draft (or post it and reverse it).
- [ ] Open a journal made by another screen (for example a purchase, if module 3 has demo data). It has **Clone** but no **Reverse and correct**.
- [ ] A Staff login (no journal rights) sees neither button.
- [ ] **Audit log** shows "Reversed and copied journal (to correct)" with the reason.

## Sign-off

| Role | Name | Date | Signed |
|---|---|---|---|
| Director | | | |
| Financial Controller | | | |

Notes or problems found:
