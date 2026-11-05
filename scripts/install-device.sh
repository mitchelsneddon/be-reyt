#!/usr/bin/env bash
set -euo pipefail

DEVICE="00008150-001958A83480401C"
BUNDLE_ID="local.mitchel.bereyt"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcodegen generate

xcodebuild -project BeReyt.xcodeproj -scheme BeReyt -configuration Debug \
  -destination "id=$DEVICE" -allowProvisioningUpdates \
  -derivedDataPath build/DD build

APP="build/DD/Build/Products/Debug-iphoneos/BeReyt.app"

xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID"
