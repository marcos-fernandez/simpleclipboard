# SimpleClipboard

Clipboard manager for macOS, with optional backup and sync between Macs through iCloud Drive.
Items can be tagged into named, coloured collections; tagged items never expire.
Text and image history,
search and direct pasting with `⇧⌘V`. Anything copied from 1Password is kept in
memory only and disappears after 10 minutes.

## Requirements

- macOS 14 or later, Command Line Tools (`xcode-select --install`). Xcode is not needed.

## Build and install

```bash
scripts/test.sh                # unit tests (sets the Swift Testing plugin path)
scripts/build-app.sh           # creates build/SimpleClipboard.app
pkill -x SimpleClipboard || true
ditto build/SimpleClipboard.app /Applications/SimpleClipboard.app
open /Applications/SimpleClipboard.app
```

To keep the Accessibility permission across rebuilds, create a certificate once in
Keychain Access > Certificate Assistant > Create a Certificate…
(Name: `Clipboard Local Signing`, Identity Type: Self Signed Root, Certificate Type:
Code Signing).

## Permissions

- **Accessibility**: needed to paste directly (it simulates `⌘V`). Without it, the
  item is only copied to the clipboard.
- If macOS asks about clipboard access, choose "Always Allow".

## Usage

`⇧⌘V` opens the history · `←` `→` navigate · type to search · `Enter` paste ·
`⌘⌫` delete · `Esc` close · `⌘←` `⌘→` switch tab · `⌘T` tag · right-click a card or a tab for more options.

## Data

`~/Library/Application Support/SimpleClipboard/` (`history.json`, `tags.json` and `images/`).
The last 1000 untagged items or 30 days. Tagged items are kept unless you delete them
(`⌘⌫`) or copy the same value from 1Password (it then becomes an in-memory-only
copy). "Clear History…" deletes only untagged items. Each save also writes a copy of
`history.json` and `tags.json` as `.prev`: if a file is found damaged at launch, it is moved to `.bak` and the
`.prev` copy is loaded instead. If `tags.json` cannot be recovered either, its items stay tagged
under tags named "Recovered …" until the real ones come back (from another Mac through sync, or a
repaired file).

Backup: `~/Library/Mobile Documents/com~apple~CloudDocs/SimpleClipboard/Backup/`,
automatic every hour when something changed, or from the menu ("Back Up Now",
"Restore from iCloud…"). Anything copied from 1Password is never included. There is a single
backup: if two Macs back up, each one replaces the other's. "Restore" replaces the
local history and tags. On a new Mac, the existing backup is restored automatically
only while that Mac has nothing copied yet; once it does, the menu asks you to choose between
restoring and making a new backup. The automatic backup also waits for that choice ("Back Up Now" or
"Restore from iCloud…") whenever the backup in iCloud was not made or restored from this Mac, or a
damaged local file could not be recovered, so it never replaces the backup with less than it holds.

Sync between Macs: with "Sync Between Macs" turned on in each Mac (same iCloud account), the
history and the tags stay the same through `iCloud Drive/SimpleClipboard/Sync/`: whatever is
copied, deleted or tagged on one shows up on the other once iCloud Drive uploads and downloads the files (from
seconds to a couple of minutes). Anything copied from 1Password never leaves the Mac. A deletion reaches both Macs; to
undo it, "Restore from iCloud…" brings the backup back on both. When it is first turned on
on a Mac, its history is joined with the others' without duplicating anything. Tags with the same name
are merged into one, even if you created them that way on purpose. The app is installed on each Mac by building it there.

It used to be called Clipboard: on the first launch of SimpleClipboard,
`~/Library/Application Support/Clipboard/` and the `Clipboard` folder in iCloud Drive are moved
to their new names automatically, and the backup state is kept. The Accessibility
permission and the login item have to be granted again.
