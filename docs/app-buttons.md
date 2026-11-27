# Ruchi Buds app: buttons on every screen

Version 1.0 · 27-Nov-2026

No database step is needed for these. Once the pull request is merged, reload the app (on a computer press Ctrl + Shift + R; on a phone close the app fully and open it again).

| Button | Where | What it does |
|---|---|---|
| **‹ Back** | Top left of every screen | Goes to the screen you were on before. If the app was just opened, it goes up one level: from a record (for example a purchase) to its list, and from a list to Home. Useful in the installed phone app, which has no browser Back button. |
| **‹ Purchases**, **‹ Sales** … | Next to Back, on a single record | Goes straight to that list. |
| **⌂ Home** | Top left of every screen | The home menu. Tapping the Ruchi Buds logo does the same. |
| **✕** | Top right of every pop-up window | Closes the window without saving. **Esc** on a keyboard does the same. |
| **🙈 Hide** | Top bar | Blurs the whole screen so people nearby cannot read it. Tap or click anywhere (or press any key) to show it again. Keyboard: **Ctrl + Shift + H**. The screen also hides by itself after 3 minutes without use, and when you switch to another app. |

## Test checklist

- [ ] Open Purchases, then a purchase. **‹ Back** returns to the list, **⌂ Home** to the home menu.
- [ ] On a phone (installed app), open a purchase, close the app, open it again on that purchase, and press **‹ Back** twice: purchase → list → Home.
- [ ] Open **+ New journal** and press **✕**. The window closes and nothing is saved. Do it again with **Esc**.
- [ ] Press **🙈 Hide**. The screen blurs. Tap it: the screen shows again.
- [ ] Leave the app untouched for 3 minutes. It hides itself.
- [ ] Print any list: the buttons do not appear on paper.
