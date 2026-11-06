# be reyt

a little space for your day. A private, single-user iPhone journal.

## Requirements

- Xcode 27.0, iOS 27.0 SDK, Swift 6
- `brew install xcodegen`
- Signing: Apple Developer Program team `C76RQ9NG73` (automatic), Apple ID signed in to Xcode

## Build

```sh
xcodegen generate
swift test --package-path Packages/ReytKit
xcodebuild -project BeReyt.xcodeproj -scheme BeReyt \
  -destination 'platform=iOS Simulator,name=be reyt,OS=27.0' build
```

Create the simulator once: `xcrun simctl create "be reyt" "iPhone 17 Pro Max" com.apple.CoreSimulator.SimRuntime.iOS-27-0`

## Install on the phone

```sh
scripts/install-device.sh
```

The phone must be unlocked, trusted, and in Developer Mode. Add `--release` for a Release build (see "Daily use build" below).

## TestFlight

```sh
scripts/testflight.sh            # archive + export only, to check signing
scripts/testflight.sh --upload   # archive + upload to App Store Connect
```

The build number is a UTC timestamp, so every upload is higher than the last. Bump `MARKETING_VERSION` in `project.yml` for a new version. Needs the app record for `local.mitchel.bereyt` in App Store Connect. TestFlight builds expire after 90 days. Installing from TestFlight replaces a dev install in place (same bundle id and team keeps your data). Do not delete the app: that deletes local data.

## Checks

```sh
swift format lint --strict --recursive App Packages
scripts/privacy-check.sh
```

## Dev notes

- Debug builds accept `-skipLock`, which bypasses the app lock (the simulator has no Face ID enrolled by default). Release builds ignore it.

## Device checklist

Tick these on the phone; none of them can be proven in the simulator.

### Install and launch
- [ ] `scripts/install-device.sh` installs and launches; the app opens and shows today.
- [ ] Signing expiry: the settings "about" row shows the days left; the banner appears near expiry.

### Face ID lock
- [ ] Lock on, background the app, return: Face ID is asked; cancel leaves the lock screen.
- [ ] App switcher shows the cover, never journal text (also with a photo or a sheet open).

### HealthKit workouts
- [ ] Allow access: workouts appear on the day page; deny: the copy explains iOS never reveals a denial.

### Reminders
- [ ] 9 pm delivery on an empty day, and the delivered reminder is removed once the day has content.

### Backup and restore
- [ ] Automatic backups: pick an iCloud folder; "uploaded" and "waiting" states; airplane mode; evicted-snapshot listing; folder deleted; the "on my iphone" warning for a local folder.
- [ ] Passphrase change re-uploads the photos under the new key; `pending changes` clears after a run.
- [ ] Restore: an evicted snapshot, an older passphrase, undo, restore browser labels, the post-restore "use this backup's passphrase" question.
- [ ] Generated reflections: airplane-mode generation, AI-off copy, edits purge a stale narrative.
- [ ] Exports: share sheet, and Files opens the PDF and the zip.
- [ ] Apple Journal import of your real export: preview, confirm, history, re-import shows duplicates.
- [ ] Delete all data (only with a backup first): re-auth and typed confirm, journal empty afterwards, backup files untouched, passphrase cleared.

## Opening a backup on a Mac (disaster recovery)

Backups (`.aea`) are Apple Encrypted Archives using the scrypt password profile. To open one without the app:

```sh
aea decrypt -i be-reyt-export-YYYY-MM-DD-xxxxxxxx.aea -o backup.aar -password-value 'PASSWORD'
aa extract -i backup.aar -d backup/
```

`PASSWORD` is your backup passphrase, **plus the suffix ` | be reyt backup` if your passphrase is shorter than 20 bytes** (Apple's engine rejects shorter passwords, so the app appends this fixed suffix). Example: passphrase `sunny dog` → password `sunny dog | be reyt backup`. The extracted folder holds `manifest.json`, `data.json` and `attachments/`.

## Recovering an automatic backup on a Mac

The automatic backup folder (`be reyt backups/`) holds `snapshots/`, `pre-restore/` and `blobs/`.

**1. The snapshot (your entries and settings).** A snapshot is the same kind of file as a manual export, so use the same command and the same passphrase rule as above:

```sh
aea decrypt -i be-reyt-YYYY-MM-DD-xxxxxxxx.aea -o snapshot.aar -password-value 'PASSWORD'
aa extract -i snapshot.aar -d snapshot/
```

The extracted folder holds `manifest.json`, `data.json` and `dataKey.bin`. It has no photos: they are separate files.

**2. The photos.** Each photo is one encrypted file at `blobs/<first 2 characters>/<name>.aea`. They are encrypted with a random 256-bit key (not your passphrase). That key is `dataKey.bin` inside the snapshot, and it is a raw 32-byte file, so it can be passed straight to `aea`:

```sh
aea decrypt -i blobs/ab/abcdef....aea -o photo.heic -key snapshot/dataKey.bin
# or, with the key inline:
aea decrypt -i blobs/ab/abcdef....aea -o photo.heic -key-value "base64:$(base64 < snapshot/dataKey.bin)"
```

To know which blob is which photo, look in `manifest.json`: each `attachments` entry has the photo's `id`, `ext` and `blob` name (the file name without `.aea`). The decrypted bytes are the original photo file; name it `<id>.<ext>`. `data.json` ties each `id` to its day.

What is verified: the `aea decrypt ... -key` and `-key-value base64:...` syntax, and the blob profile (symmetric, no compression), were checked against a file made with the same profile using the `aea` command line. Decrypting a blob written by the app itself with the command line has not been tried yet, so do it once with a real backup before you rely on it.

## Daily use build

`scripts/install-device.sh` builds a Debug build by default. For daily use, install a Release build (faster, and without the Debug-only launch arguments):

```sh
scripts/install-device.sh --release
```

The development profile lasts a year; run it again to re-sign before it expires. Same bundle id and team, so your data stays.
