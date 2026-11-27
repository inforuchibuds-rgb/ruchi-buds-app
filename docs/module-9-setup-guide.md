# Ruchi Buds app: Module 9 setup guide

Version 1.0 · 27-Nov-2026 · Module 9: Backup and restore

This update takes about 10 minutes, plus about 30 minutes once for the restore drill before go-live. You paste one file into Supabase and update the Apps Script. GitHub Pages updates the screens on its own once the pull request is merged.

## What module 9 gives you

The nightly backup to Google Drive, the keep-awake ping and **Backup now** have run since module 1. Module 9 adds the way back: **restoring a backup**.

- **Settings → Restore a backup…** (Directors and the FC only):
  1. **Load a backup**:
     - a backup file from **Settings → Backup now (file for restore)**; or
     - a nightly backup from Google Drive. Open the Apps Script and run **stageLatestBackup**, then press **Refresh** on the screen.
  2. **The check**: the app compares the backup with the data now. It shows when the backup was taken, how many rows each table has in the backup and now, and what happens to each table. It warns about anything to know. For example, a user set up after the backup will not be able to use the app until they are added again.
  3. **Before you restore**: ask everyone to stop entering, and press **Download today's data**, in case it is needed later.
  4. **Restore**: give the reason and type **RESTORE**. It is all or nothing: either every table is reloaded and every link between tables checks out, or nothing changes.
- **Undo**: the data as it was just before the restore is kept in the database for 30 days, as **Undo copy** at the top of the list. Restoring it undoes the restore, in the same way.
- The **audit log** and the **backup log** are never wiped. The restore and its reason are added to both.
- **Settings → Backups and keep-awake** now also shows the last restore and the last **restore drill**.
- **The restore drill** (spec section 12): the Apps Script reloads last night's backup into a separate **test copy** of the database and checks every table, without touching the live data. Do it once before go-live, and after that every few months.

## Decisions built in (please check them)

| Topic | What the app does | Why |
|---|---|---|
| Who can restore | Only Directors and the FC (a new right, **Restore a backup**, given to no category). The Accountant can still take backups. | Spec section 12: "after confirmation by Director or FC". |
| Confirmation | The person restoring types RESTORE and gives a reason. The confirmation lasts one hour. The Apps Script cannot confirm a restore of the live data, only on a test copy. | A restore replaces everything entered since the backup. |
| What is restored | Every table. The logs (audit log, backup log) are added to, never wiped. Screens, rights and statement lines are kept as the SQL files set them. | The audit trail must not be lost. The catalogue belongs to the app version, not to the data. |
| Older backups | A table missing from the backup (taken before a later module) is kept as it is. Columns or tables the app no longer has are left out. The check lists each one. | So a backup from before an update can still be restored. After restoring one, run the SQL files again from `01` to `09` in order. |
| Undo | The data just before each restore is kept for 30 days (only the newest copy). Loaded backups that are not restored are cleared after 7 days. | Space on the free Supabase plan. |
| Passwords | Not in any backup. A restore does not change anyone's password or sign-in. | Supabase keeps passwords apart from the data. |
| Size | A restore of up to about 1 lakh rows (several years of entries) runs from the app. A bigger one may take too long for the app. If so, nothing changes, and **applyRestore** in the Apps Script finishes it within the hour. | Supabase stops app requests after a few seconds. The Apps Script has no such limit. |

## Step 1. Take a backup (1 minute)

In the app: **Settings → Backup now (file for restore)**. Keep the file.

## Step 2. Supabase: add the module 9 tables (3 minutes)

1. Open your project at [supabase.com/dashboard](https://supabase.com/dashboard), then **SQL Editor → New query**.
2. Open `sql/09_backup.sql` from the repository (on GitHub, click the file, then the **Copy raw file** button).
3. Paste it and press **Run**. If Supabase warns about "destructive operations", press **Run this query**. That is expected.
4. You should see **Success. No rows returned**.

The file is safe to run again. Running it again changes nothing and loses nothing.

> **Important:** if `01` to `08` is ever run again, run every later file again straight after it, in order, ending with `09`.

## Step 3. The screens

Once the pull request is merged into **main**, GitHub Pages publishes the new screens within a couple of minutes. Reload the app. On a phone, close the app fully and open it again.

**Settings → Backups and keep-awake** now has the button **Restore a backup…** (for Directors and the FC).

## Step 4. The Apps Script (5 minutes)

1. Open the Ruchi Buds Apps Script at [script.google.com](https://script.google.com).
2. Open `Code.gs`. Delete what is in it, then paste in all of `apps-script/Code.gs` from the repository (version 1.2). Press **Save**.
3. Nothing else changes: the timers and Script Properties stay as they are.

The new functions are run by hand only when needed:

- **stageLatestBackup**: loads the newest nightly backup into the app for restore. To load another day, add the Script Property `RESTORE_DAY` = the folder name (for example `2026-11-26`). Remove it afterwards.
- **applyRestore**: only if the app said the restore took too long. It finishes the restore you confirmed in the app within the last hour.
- **restoreDrill**: the restore drill (step 5).

## Step 5. The restore drill, once before go-live (30 minutes)

The drill proves the backups work, using a separate free Supabase project as the test copy. The live data is not touched.

1. At [supabase.com/dashboard](https://supabase.com/dashboard), press **New project**. Name it **ruchi-buds-test**, choose the **Mumbai** region, and keep its database password somewhere safe.
2. In the new project's **SQL Editor**, run `sql/01_core_users.sql` to `sql/09_backup.sql`, in order, each in a new query (as you did for the live project).
3. Still in the test project's SQL Editor, run this one line, which marks it as a test copy:
   `select rb_mark_test_copy();`
4. In the test project, go to **Project Settings → API Keys** and copy its **Project URL** and its **secret** key (`sb_secret_…`).
5. In the Apps Script, **Project Settings → Script Properties**, add:
   - `TEST_SUPABASE_URL` = the test project's URL;
   - `TEST_SUPABASE_SERVICE_KEY` = the test project's secret key.

   Never put the live project's details in these two.
6. In the Editor, choose **restoreDrill** and press **Run**.
7. The log should say **Restore drill PASSED**. In the live app, **Settings → Backups and keep-awake** shows **Last restore drill: OK**.

You can keep the test project for the next drill. Run restoreDrill again every few months, or after a big update.

## Files in this module

| File | What it is | Where it goes |
|---|---|---|
| `sql/09_backup.sql` | The database for module 9 | Paste into Supabase SQL Editor (step 2) |
| `backup.js` | The Restore a backup screen | Already in the repository, served by GitHub Pages |
| `index.html`, `settings.js`, `ruchi.css` | Updated (loads the new screen; Settings shows the last restore and drill) | The same |
| `apps-script/Code.gs` | Version 1.2: stageLatestBackup, applyRestore and restoreDrill | Google Apps Script (step 4) |
| `docs/module-9-test-checklist.md` | What to tick before sign-off | Read and tick |
| `tests/test_backup.sql`, `tests/e2e_backup.js` | The automatic checks used while building | Not needed in Supabase |

## If something goes wrong

- **"permission denied for function …"** on any screen: run `09_backup.sql` again (usually because an earlier file was run after it).
- **"This file is not a Ruchi Buds backup"**: choose a `.json` file from **Settings → Backup now (file for restore)**, not the Excel one.
- **"… the backup lists … rows but … were loaded"**: the file or the Drive folder is incomplete. Load it again, or choose another day.
- **"The backup does not hold together …"**: the backup was taken while people were entering, so some rows point to rows it does not have. Nothing was changed. Use another backup (the nightly ones run at 2 AM, when nobody is entering).
- **"The restore took too long for the app"**: nothing was changed. Within the hour, run **applyRestore** in the Apps Script.
- **"A restore into the live database must be confirmed in the app …"**: check that `TEST_SUPABASE_URL` and `TEST_SUPABASE_SERVICE_KEY` are the test project's, and that `select rb_mark_test_copy();` was run there.
- Anything else: take a screenshot and send it in the project thread.
