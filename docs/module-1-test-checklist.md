# Ruchi Buds app: Module 1 test checklist

Version 1.0 · 26-Nov-2026

Tick each line on the real app before signing off module 1. You need two devices (for example the PC and a phone) and a second email address you can use as a test staff member.

**Sign-off gate (from the build plan):** DS can sign in, create the other users, and last night's backup is in Drive.

## A. Sign-in

- [ ] DS sets a password with **First time here?** using info.ruchibuds@gmail.com, and lands on the home menu.
- [ ] An email that was never added (for example a friend's) is refused with "This email has not been invited yet".
- [ ] The yellow **Training mode** strip shows on every screen.
- [ ] **Sign out**, then sign in again with the password. It works.
- [ ] **Change my password** works, and the old password stops working.
- [ ] On a phone: **Add to Home screen** shows the RB icon and opens the app full screen.

## B. Users

- [ ] **Users** lists DS plus 10 users with an orange **DEMO** badge.
- [ ] Add a real test user (your second email) as **Staff**, with a learning-phase end date. Their status shows **Invited**.
- [ ] On the phone, that person sets their password with **First time here?**. Their status in Users becomes **Active**.
- [ ] Their home shows only **Sales** and **Customers** (each marked "Module 5"), plus a learning-phase message with the date in dd-mmm-yyyy.
- [ ] Their phone cannot open Users, Settings or Audit log (typing `#/users` after the link says "You do not have access").
- [ ] Open the test user in Users and press **What can they see?**. It matches the previous line.
- [ ] **Download to Excel** gives a spreadsheet of the users list.
- [ ] Sort and filter the list by Category and Status.

## C. Categories and the tick grid

- [ ] **Categories and access**: Director and Financial Controller show **Always full access** and their ticks cannot be changed.
- [ ] Pick **Staff**, tick **Stock → View**. "Saved" appears. The test user's home now shows **Stock** after they sign out and back in.
- [ ] Untick it again.
- [ ] **+ New category**: create "Packing staff" from the Staff template, rename it, then **Remove** it.
- [ ] **Remove** on Staff is refused because users are in it.
- [ ] **Change history** lists each tick and untick with who did it and when.
- [ ] Rename **Director** to **Partner**, check the banner shows "Partner", then rename it back.

## D. Per-user ticks

- [ ] Open the test user and press **Change this person's ticks**. Tick **Sales → See margin**. The cell turns green. Untick **Customers → Add**. The cell turns red.
- [ ] **What can they see?** reflects both changes.
- [ ] Put both back. The colours disappear.

## E. Locking, unlocking, temporary passwords

- [ ] On the phone, type the test user's password wrong 5 times. The 6th try (even with the right password) says the account is **locked**.
- [ ] In Users the person shows **Locked**. Press **Unlock**. They can sign in again.
- [ ] Press **Give a temporary password**, then sign in with it on the phone. The app forces a new password before anything else.
- [ ] Audit log shows: wrong password ×5, unlock, password reset, password changed.

## F. Accountant limits (optional now; needs a second test email)

- [ ] Add a test user as **Accountant**. Signed in as them: they can add a Staff user, but adding a Director is refused ("more rights than your own").
- [ ] They cannot tick the category grid, and they cannot set a learning-phase date.

## G. Settings

- [ ] Enter the Firm Reg. no. and the address, then press **Save settings**. Reload the page and they are still there.
- [ ] Partners: rename Partner 1–3 to the real names. The ratio line shows 33.33% each.
- [ ] Tick a couple of trader required fields and save.
- [ ] Word mark: choose an image file under 300 KB, save, and the banner changes. **Use the standard word mark** and save puts it back.
- [ ] Audit log shows each settings change as "old → new".

## H. Backups and keep-awake

- [ ] Apps Script set up as in the guide, and **setupTriggers** run.
- [ ] **nightlyBackup** run by hand: Drive has **Ruchi Buds Backups / today's date** with a file per table.
- [ ] Next morning: Settings shows **OK** for **Last nightly backup** (dated overnight) and **Last keep-awake ping**.
- [ ] **Backup now (file for restore)** downloads a `.json` file. **Backup now (Excel)** downloads a workbook with one sheet per table.

## I. Demo data (do this last)

- [ ] **Settings → Remove demo data**, type REMOVE DEMO. The 10 DEMO users and the DEMO category disappear. Your real users stay.
- [ ] Do **not** press **Go live** yet. That comes after all modules are signed off.

## Sign-off

| Role | Name | Date | Signed |
|---|---|---|---|
| Director | | | |
| Financial Controller | | | |

Notes or problems found:
