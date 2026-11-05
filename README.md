# be reyt

a little space for your day. A private, single-user iPhone journal.

## Requirements

- Xcode 27.0, iOS 27.0 SDK, Swift 6
- `brew install xcodegen`
- Signing: free Personal Team `C76RQ9NG73` (automatic)

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

The phone must be unlocked, trusted, and in Developer Mode.

## 7-day re-sign

A free Personal Team provisioning profile expires after 7 days, after which the app will not open. Run `scripts/install-device.sh` again to reinstall over the top (same bundle id and team keeps your data). Do not delete the app: that deletes local data.

## Checks

```sh
swift format lint --strict --recursive App Packages
scripts/privacy-check.sh
```

## Dev notes

- Debug builds accept `-skipLock`, which bypasses the app lock (the simulator has no Face ID enrolled by default). Release builds ignore it.

## Device checklist

### Install and launch
_to be filled in_

### Face ID lock
_to be filled in_

### HealthKit workouts
_to be filled in_

### Reminders
_to be filled in_

### Backup and restore
_to be filled in_

## Opening a backup on a Mac (disaster recovery)

Backups (`.aea`) are Apple Encrypted Archives using the scrypt password profile. To open one without the app:

```sh
aea decrypt -i be-reyt-export-YYYY-MM-DD-xxxxxxxx.aea -o backup.aar -password-value 'PASSWORD'
aa extract -i backup.aar -d backup/
```

`PASSWORD` is your backup passphrase, **plus the suffix ` | be reyt backup` if your passphrase is shorter than 20 bytes** (Apple's engine rejects shorter passwords, so the app appends this fixed suffix). Example: passphrase `sunny dog` → password `sunny dog | be reyt backup`. The extracted folder holds `manifest.json`, `data.json` and `attachments/`.
