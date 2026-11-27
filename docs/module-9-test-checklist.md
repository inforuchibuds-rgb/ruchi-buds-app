# Ruchi Buds app: Module 9 test checklist

Version 1.0 · 27-Nov-2026

Tick each line on the real app before signing off module 9. You need DS's login and the Accountant's login. Do it while nobody else is entering, because part B puts the data back as it was.

**Sign-off gate:**

- A backup file restores, the data comes back exactly as it was, and the restore can be undone.
- A nightly Drive backup can be loaded and checked.
- The restore drill passes on a test copy.
- Only a Director or the FC can restore.

## A. Settings

- [ ] **Settings → Backups and keep-awake** shows the lines **Last restore drill** (Never, for now) and the button **Restore a backup…**.
- [ ] **Backup now (file for restore)**: a `.json` file downloads. Keep it: it is used in part B.

## B. Restore a backup file (as DS)

- [ ] After taking the backup in A, make one small change you will recognise. For example, add a test supplier called "Restore test".
- [ ] **Restore a backup…** → choose the file from A. It says **Loaded and checked**, the backup shows as **Ready to restore**, and part 3 shows when it was taken and the rows to restore.
- [ ] Open **Every table: rows in the backup and now**: suppliers shows one row fewer in the backup than now.
- [ ] **Restore this backup** stays greyed until you press **Download today's data** (a file downloads) or tick the box.
- [ ] Press **Restore this backup** without a reason: it asks for the reason. Give one, type **RESTORE**, and confirm. It says **Restored**, with the tables and rows.
- [ ] **Reload the app**. The "Restore test" supplier is gone, and everything else is as it was.
- [ ] **Audit log**: the restore shows with your reason. **Settings → Backups** shows **Last restore**.

## C. Undo

- [ ] **Restore a backup…**: the top of the list shows **Undo copy** ("Data as it was just before restoring …"), Ready to restore.
- [ ] **Open** it, download today's data, give a reason and restore it. The "Restore test" supplier is back.
- [ ] Load the file from A again and restore it, so the "Restore test" supplier is gone again.

## D. A nightly backup from Google Drive

- [ ] In the Apps Script, run **stageLatestBackup**. The log says it loaded the backup of last night.
- [ ] In the app, **Restore a backup… → Refresh**: "Nightly backup …" shows as **Ready to restore**, from Google Drive.
- [ ] **Set this backup aside** (you do not need to restore it). It shows as Set aside.

## E. Refusals

- [ ] Choose the **Excel** backup file, or any other file: "This file is not a Ruchi Buds backup".
- [ ] As the Accountant: Settings has **Backup now** but no **Restore a backup…**, and the Restore screen cannot be opened.

## F. The restore drill

- [ ] Set up the test project and the two TEST Script Properties (setup guide, step 5).
- [ ] Run **restoreDrill**: the log says **Restore drill PASSED**.
- [ ] In the live app, **Settings → Backups** shows **Last restore drill: OK**.
- [ ] The live data is unchanged.

Signed off by: ____________________ Date: ____________
