# Ruchi Buds app: Module 1 setup guide

Version 1.0 · 26-Nov-2026 · Module 1: Core and users (plus the nightly backup and keep-awake ping)

This guide covers where to paste and where to click, in order. It takes about 30 minutes. You never need to send anyone a password or the secret key.

## What module 1 gives you

- **Sign-in** for everyone, from phones and the shared PC. Staff choose their own password the first time.
- **Home menu.** Each person sees only the screens ticked for them. Screens from later modules show a "Module N" label until they are built.
- **Users.** Add people, change their category, switch them off when they leave, set each person's learning-phase end date, unlock accounts and give temporary passwords.
- **Categories and access.** The eight starting categories, and a tick grid of screens × actions (View, Add, Edit, Approve, Delete, See margin) plus special rights. You can also give one person extra ticks, or take ticks away from them. Every tick change is logged with who made it and when.
- **Settings.** Firm details for invoices, partners and their profit-sharing ratio (1 : 1 : 1 to start), trader required fields, the word mark, training mode and go-live, "Remove demo data", and "Backup now".
- **Audit log.** Every change, sign-in and wrong password, kept for good. Nobody can edit or delete it.
- **Backups.** Every night a copy of every table goes to Google Drive, and the last 30 days are kept. Every morning a small ping stops the free database from going to sleep.
- **DEMO data.** 10 example users and 1 example category, so you can try every screen.

## Decisions built in (please check them)

| Topic | What the app does | Why |
|---|---|---|
| Director and FC | Always have every tick. Their grid is locked. | Nobody can accidentally lock the firm out of its own app. |
| Handing out access | Nobody can give a category with more rights than they have. An Accountant can add a Staff user, for example, but not a Director. | Stops anyone promoting themselves or a friend. |
| Own account | Nobody can change their own category, ticks or on/off switch. | The same reason. |
| Password resets | A Director or the FC gives a temporary password, and the person must choose their own when they next sign in. For a **Director's or FC's** account, a second Director or the FC has to approve it first. | Section 3 of the spec. *My reading: "the other's approval" means a second Director or FC.* |
| Locking | The account locks after 5 wrong passwords. You can change the number in Settings. A Director, the FC or the Accountant unlocks it. | Section 3 of the spec. |
| Learning phase | Only a Director or the FC sets the end date. The home screen tells the person their date. | Section 4 of the spec. |
| Who can sign up | Only an email that was added in Users can create a password. Any other email is refused by the database itself. | Safe to leave Supabase sign-ups switched on. |
| Colours | Screens use the spec's Ruchi Red #971B1E and Ruchi Yellow #FCB315. | As recommended in the build plan. |
| Word mark | Uses the "fixed" word mark you shared, with its background removed. Replace it in Settings when the designer sends the final file. | Section 11 of the spec. |

## Step 1. Supabase: two settings (2 minutes)

1. Open your project at [supabase.com/dashboard](https://supabase.com/dashboard).
2. In the left menu, go to **Authentication**, then **Sign In / Providers** (on some screens it's **Providers → Email**).
3. Make sure **Allow new users to sign up** is **ON**. Only emails you have added in the app can sign up, so this is safe.
4. Under **Email**, switch **Confirm email** **OFF**, then press Save. Supabase's free email service only sends a few emails an hour, and only to the project's own team. If this stays on, staff could never finish setting up.
5. If there is a **Minimum password length** box, set it to 8.

## Step 2. Supabase: create the database tables (3 minutes)

1. In the left menu, open **SQL Editor** and press **New query**.
2. Open `sql/01_core_users.sql` from the repository (on GitHub, click the file, then the **Copy raw file** button).
3. Paste it into the editor and press **Run**.
4. You should see **Success. No rows returned**. If Supabase warns about "destructive operations", that is expected (the file replaces its own rules), so press **Run this query**.

The file is safe to run again. Running it a second time changes nothing and loses nothing.

> **`00_reset.sql`** wipes **everything** in the app. Run it only on purpose, and only after a backup.

## Step 3. GitHub Pages: put the app online (3 minutes)

1. Open the repository on GitHub (`inforuchibuds-rgb/ruchi-buds-app`).
2. Go to **Settings → Pages**.
3. Under **Build and deployment**, set **Source** to **Deploy from a branch**, **Branch** to **main**, and the folder to **/ (root)**. Press **Save**.
4. After a minute or two the page shows the link: **https://inforuchibuds-rgb.github.io/ruchi-buds-app/**. This is the app's address. Bookmark it.

`config.js` already holds your Project URL and publishable key. Both are meant to be public: the database decides what each login can see.

## Step 4. First sign-in as DS (2 minutes)

1. Open the app link.
2. Tap **First time here? Set up your password**.
3. Enter **info.ruchibuds@gmail.com** and choose a password of at least 8 characters. Type it twice.
4. You land on the home menu as **DS, Director**. The yellow strip says the app is in **training mode**.

**On a phone:** open the link in Chrome (Android) or Safari (iPhone), then choose **Add to Home screen**. The app then opens like a normal app, with the RB icon.

## Step 5. Add the other people

1. **Users → + Add user.** Enter their email, name, initials, phone, category and learning-phase end date.
2. Tell them: *open the app link, tap "First time here? Set up your password", and use this email*.
3. Their status changes from **Invited** to **Active** once they have done it.

If someone typed the wrong email, open them and choose **Delete invitation**. When someone leaves, choose **Switch off**. Their past entries stay.

## Step 6. Google Apps Script: nightly backup and keep-awake (10 minutes)

Do this signed in to the Google account that should hold the backups (for example info.ruchibuds@gmail.com).

1. Open [script.google.com](https://script.google.com) and press **New project**. Rename it **Ruchi Buds Backup** (click "Untitled project").
2. Delete what is in `Code.gs`, then paste in all of `apps-script/Code.gs` from the repository.
3. Click the **gear icon (Project Settings)** and tick **Show "appsscript.json" manifest file in editor**. Go back to the **Editor**, open `appsscript.json`, and replace its contents with `apps-script/appsscript.json` from the repository. This sets the time zone to India.
4. Still in **Project Settings**, scroll to **Script Properties → Add script property** and add:
   - `SUPABASE_URL` = `https://gsrcjcgqptcnnzbdulas.supabase.co`
   - `SUPABASE_SERVICE_KEY` = the **secret** key from Supabase → **Project Settings → API Keys → Secret keys** (it starts with `sb_secret_`; press the eye icon to reveal it, then copy it). **This key can read and change everything. Paste it only here. Never send it to anyone, Claude included.**
   - `ALERT_EMAIL` = the email that should get a message if a backup fails (optional; by default it is your own).
5. Press **Save script properties**.
6. Back in the **Editor**, choose **setupTriggers** in the function list at the top and press **Run**. Google asks for permission:
   - Choose your account, then on "Google hasn't verified this app" press **Advanced → Go to Ruchi Buds Backup (unsafe)** → **Allow**. This warning appears because you wrote the script yourself; it isn't from an outside company.
7. The log should say **Database is awake** and **Timers set**.
8. Now choose **nightlyBackup** and press **Run** once, to test it. Open Google Drive: there should be a folder **Ruchi Buds Backups**, with today's date inside, holding one file per table plus `_manifest.json`.
9. In the app, **Settings → Backups and keep-awake** should now show **OK** next to the nightly backup and the keep-awake ping.

From now on the backup runs every night between 2 and 3 AM, and the ping every morning between 6 and 7 AM (India time).

**What the backup does not hold:** passwords. They are kept by Supabase and never copied. After a restore, people would set their passwords again with "First time here?".

## Step 7. Manual backup before changes

**Settings → Backup now** downloads a complete copy to the device you are using:

- **file for restore** (`.json`): keep it, because the restore tool in module 9 reads this file.
- **Excel**: one sheet per table, so you can look through it.

Take one before every module update and at each month-end.

## Files in this module

| File | What it is | Where it goes |
|---|---|---|
| `sql/01_core_users.sql` | The database for module 1 | Paste into Supabase SQL Editor (step 2) |
| `sql/00_reset.sql` | Wipes everything (only on purpose) | Supabase SQL Editor, only when starting over |
| `index.html`, `core.js`, `users.js`, `settings.js`, `ruchi.css`, `config.js`, `manifest.webmanifest`, `assets/`, `vendor/` | The screens | Already in the GitHub repository, served by GitHub Pages |
| `apps-script/Code.gs`, `apps-script/appsscript.json` | Nightly backup and keep-awake | Google Apps Script (step 6) |
| `docs/module-1-test-checklist.md` | What to tick before sign-off | Read and tick |
| `tests/` | The automatic checks used while building | Not needed in Supabase or Google |

## If something goes wrong

| What you see | What to do |
|---|---|
| "This email has not been invited yet" | Add the person in **Users** first, and check the spelling of the email. |
| "Supabase is waiting for an email confirmation" | Step 1: switch **Confirm email** off. Then delete that user in Supabase → Authentication → Users and let them set up again. |
| "Your account is locked" | A Director, the FC or the Accountant opens the person in **Users** and presses **Unlock**. |
| Forgot password | A Director or the FC opens the person and presses **Give a temporary password**. |
| A Director or FC forgot their password | Another Director or the FC gives the temporary password, and a third person (a Director or the FC) approves it under **Users → Password approvals**. If nobody else can sign in yet, use Supabase → Authentication → Users → the person → **Send password recovery**, or ask Claude. |
| Settings shows the backup as **Late** or **Failed** | Open the Apps Script, check the Script Properties, and run **nightlyBackup** by hand. The error is shown in the log and emailed to ALERT_EMAIL. |
| Supabase says the project is **paused** | Press **Restore project** in Supabase, then check that the keep-awake timer exists (Apps Script → Triggers, the clock icon). |
