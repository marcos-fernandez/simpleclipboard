# SimpleClipboard

Clipboard manager for macOS, with optional backup and sync between Macs through iCloud Drive.
Items can be tagged into named, coloured collections; tagged items never expire.
Text and image history,
search and direct pasting with `⇧⌘V`. Anything copied from 1Password is kept in
memory only and disappears after 10 minutes.

## Requirements

- macOS 14 or later, Command Line Tools (`xcode-select --install`). Xcode is not needed.

## Install

1. Download `SimpleClipboard.zip` from the [latest release](../../releases/latest) (one build for Apple Silicon and
   Intel), unzip it and drag `SimpleClipboard.app` to Applications.
2. Open it. The app is not notarized by Apple, so macOS refuses the first time: go to System Settings > Privacy &
   Security and click "Open Anyway" (or run `xattr -dr com.apple.quarantine /Applications/SimpleClipboard.app`).
3. Grant the Accessibility permission when asked (see Permissions).

The app checks GitHub for a new release shortly after launch and then once a day. When there is one, the menu-bar
icon changes and the menu shows "Update Available", which opens the release page; nothing is downloaded or installed.
This is the only network request the app makes, and nothing from the clipboard is sent.

## Build and install

```bash
scripts/test.sh                # unit tests (sets the Swift Testing plugin path)
scripts/build-app.sh           # creates build/SimpleClipboard.app
osascript -e 'quit app "SimpleClipboard"' || true   # a normal quit, so the last changes are written
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

"Settings…" in the menu-bar menu (`⌘,` while the menu is open): open at login. With the Settings window in front,
an item picked from the history is only copied. "About SimpleClipboard" shows the version, the author and a link to
this repository.

## Data

`~/Library/Application Support/SimpleClipboard/` (`history.json`, `tags.json` and `images/`).
Changes are written in the background right after they happen; quitting the app writes any still on their way, and a
crash or power cut can only lose those (normally the last fraction of a second).
The last 1000 untagged items or 30 days. Tagged items are kept unless you delete them
(`⌘⌫`) or copy the same value from 1Password (it then becomes an in-memory-only
copy). "Clear History…" deletes only untagged items. Each save also writes a copy of
`history.json` and `tags.json` as `.prev`: if a file is found damaged at launch, it is moved to `.bak` and the
`.prev` copy is loaded instead. If `tags.json` cannot be recovered either, its items stay tagged
under tags named "Recovered …" until the real ones come back (from another Mac through sync, or a
repaired file).

Backup: `~/Library/Mobile Documents/com~apple~CloudDocs/SimpleClipboard/Backup/`,
automatic every hour when something changed, or from the menu ("Back Up Now",
"Restore…"). Anything copied from 1Password is never included. There is a single
backup: if two Macs back up, each one replaces the other's. "Restore" replaces the
local history and tags. On a new Mac, the existing backup is restored automatically
only while that Mac has nothing copied yet; once it does, the menu shows "Backup not restored" until you choose
between restoring ("Restore…") and making a new backup ("Back Up Now"). The automatic backup also waits for that
choice whenever the backup in iCloud Drive was not made or restored from this Mac, or a
damaged local file could not be recovered, so it never replaces the backup with less than it holds.

Sync between Macs: with "Sync Between Macs" turned on in each Mac (same iCloud account), the
history and the tags stay the same through `iCloud Drive/SimpleClipboard/Sync/`: whatever is
copied, deleted or tagged on one shows up on the other once iCloud Drive uploads and downloads the files (from
seconds to a couple of minutes). Anything copied from 1Password never leaves the Mac. A deletion reaches both Macs; to
undo it, "Restore…" brings the backup back on both. When it is first turned on
on a Mac, its history is joined with the others' without duplicating anything. Tags with the same name
are merged into one, even if you created them that way on purpose, and so are two tags when one is renamed to the
other's name. The app is installed on each Mac by building it there.

It used to be called Clipboard: on the first launch of SimpleClipboard,
`~/Library/Application Support/Clipboard/` and the `Clipboard` folder in iCloud Drive are moved
to their new names automatically, and the backup state is kept. Only folders that hold the old app's data
are moved (`history.json`; a `Backup` or `Sync` folder): another `Clipboard` folder is left alone. The Accessibility
permission and the login item have to be granted again.
