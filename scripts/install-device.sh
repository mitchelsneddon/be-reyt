#!/usr/bin/env bash
# Usage: scripts/install-device.sh [--release]
# Builds, installs and launches on the phone. Debug by default; --release for daily use.
set -euo pipefail

DEVICE="00008150-001958A83480401C"
BUNDLE_ID="local.mitchel.bereyt"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="Debug"
case "${1:-}" in
  "") ;;
  --release) CONFIG="Release" ;;
  *) echo "usage: $0 [--release]" >&2; exit 2 ;;
esac

xcodegen generate

xcodebuild -project BeReyt.xcodeproj -scheme BeReyt -configuration "$CONFIG" \
  -destination "id=$DEVICE" -allowProvisioningUpdates \
  -derivedDataPath build/DD build

APP="build/DD/Build/Products/$CONFIG-iphoneos/BeReyt.app"

xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID"
