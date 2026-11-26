# Ruchi Buds app: Module 4 test checklist

Version 1.0 · 27-Nov-2026

Tick each line on the real app before signing off module 4. You need DS's login and a second login. Move the module 1 test user to **Manager** for part C.

**Sign-off gate:** raw material goes through a preparation batch and a production batch into finished goods in packs; the yield report shows the wastage at each stage; a stock count is approved; the stock lists and the stock accounts in the trial balance agree.

## A. DEMO data

- [ ] Home shows **Stock** and **Production**. Production opens on a list of 13 DEMO batches, each with an orange **DEMO** badge.
- [ ] Open **DEMO-PRD/2611/00002** (fish pickle, prepared and produced together). It shows **Prepared in DEMO-PRP/…**; tap it. The preparation batch shows the wastage at each stage, the fish bones, the yield and **Used in**.
- [ ] **Yield report** (set **From** to 1-Apr-2026): each batch shows raw in, wastage % by stage, prepared out, yield %, and which finished goods it went into.
- [ ] **Wastage by stage** lists each stage with its wastage %.
- [ ] **Stock → Raw and prepared** lists the prepared ingredients batch by batch. **Stock → Finished goods** shows packs per product and pack.

## B. As DS: opening stock, preparation and production

- [ ] **Stock → + Opening stock**: enter 3 kg of a raw material at ₹100 a kg. Save, then **Approve and post**. Its stock shows 3 kg worth ₹300.
- [ ] **Production → + New batch → Preparation**: pick that raw material. Its stages appear. Enter 3 kg in, wastage at two stages, and the quantity out. The line under the form shows the yield as you type. Save: a **TRN-PRP/** number.
- [ ] Try a preparation needing more than is in stock. It is refused ("Not enough … in stock").
- [ ] **Final production**: pick a finished product, press **Copy what went into the last batch**, enter today's quantities, the number of bottles made, and the frying shrinkage. Save: a **TRN-PRD/** number, with the cost per pack. The bottles used have gone out of **Stock → Raw and prepared**.
- [ ] **Prepare and produce together**: both parts show on one screen. Save one: two linked batches, PRP and PRD.
- [ ] Enter a batch with an **unusual loss** and a reason. The batch window shows the loss charged separately.
- [ ] Prepare an item with a **sellable** by-product (chicken skin). The by-product appears in **Finished goods** at its selling price, and the main product costs less by that amount.

## C. As Manager

- [ ] The Manager can enter batches but sees **no costs** anywhere (no Cost columns, no ₹ in the batch window).
- [ ] **+ Stock count**: enter counts for a few lines, one different from the books, with a reason. Save. The Manager cannot approve their own count.
- [ ] **+ Write off** part of a prepared batch: it shows **Waiting for approval**.
- [ ] The Manager has no **+ Opening stock** and no **+ Write down**.

## D. As DS: approvals, reversals and the books

- [ ] Open the Manager's count and **Approve and post**. The difference shows in red, and the short or over value goes to Inventory Shrinkage Expense.
- [ ] Approve the Manager's write-off. The batch's stock goes down.
- [ ] **+ Write down** a finished product by a small amount. Its value drops; its packs stay the same.
- [ ] Prepared stock past its shelf life is in **red** on the Stock screen, and picking it in a production batch asks "Use prepared stock past its shelf life?".
- [ ] **Reverse batch** on a preparation batch that went into production: refused until the production batch is reversed. Reverse the production batch, then the preparation batch.
- [ ] Tap a stock line: the **movements** show every in and out with a running balance.
- [ ] **Accounts → Trial balance**: debits equal credits. Raw materials, packaging, work in progress and finished goods each equal the totals on the Stock screen.
- [ ] Lock last month in Accounts → Month lock, then try a batch dated in it. It is refused. Unlock it again.

## E. Learning phase and audit

- [ ] As DS, open a batch entered by someone in their learning phase: **Delete fully (learning phase)** removes it with its stock and journal.
- [ ] **Audit log** shows the batches, counts and write-offs with who and when.

## F. Phone

- [ ] On a phone, open the Production window (the switch wraps onto two lines), a batch window and the Stock screen.
