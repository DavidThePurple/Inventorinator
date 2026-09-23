# App lock (PIN)

An optional PIN screen for shared terminals. It is off by default and never
required. Nothing changes for anyone who does not set a PIN.

**This is a screen lock, not encryption.** It keeps the next person at the
terminal out of the app. It does not protect a copy of the database file, and
someone with access to your files can remove it (see below).

## Turning it on

Open **Personalization settings → App lock → Set PIN**. The PIN is 4 to 12 digits.
Setting it shows an **unlock key** once. Save it somewhere safe, away from this
computer. Inventorinator keeps only a hash of the PIN and of the key, so neither
can be looked up later.

Once a PIN is set:

- A **lock button** appears at the top right. Click it to lock. Everything else is
  hidden and the screen shows **Unlock with PIN**.
- Click **Unlock with PIN**, type the PIN, and you are back where you were.
- Inventorinator asks for the PIN once each time it starts.
- Remote Sync keeps running while the app is locked. The lock hides the screen; it
  does not pause syncing.

## Lock after inactivity

Under **App lock** choose a time from 1 minute to 1 hour, or **Never**. Any click,
touch or key press restarts the timer. It is off by default.

## If you lose the PIN

On the lock screen choose **Forgot PIN?**, enter the unlock key, then either set a
new PIN or turn the lock off. A new PIN comes with a new unlock key, which you must
confirm you have saved before the app opens. The old key stops working.

While the PIN is known you can make a new key at any time from
**App lock → New unlock key**.

If you have lost the PIN **and** the unlock key, close Inventorinator and remove the
lock settings from the database. This never touches your inventory:

```bash
sqlite3 ~/.local/share/media.everlasting.inventorinator/inventorinator.sqlite3 \
  "DELETE FROM preferences WHERE key LIKE 'app_lock_%'"
```

On Windows and Android the database is in the app's data folder. Because this works
for anyone who can open the file, do not rely on the lock to protect files from
someone with access to the computer's account.

## Wrong attempts

After five wrong PINs or keys in a row, attempts pause for 30 seconds. Each further
miss doubles the wait, up to 15 minutes. The count is stored, so restarting the app
does not reset it, and a correct PIN clears it.
