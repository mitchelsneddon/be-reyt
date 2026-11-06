#!/usr/bin/env bash
# Usage: scripts/testflight.sh [--upload]
# Archives a Release build and exports it for App Store Connect. With --upload it sends the build to
# App Store Connect (TestFlight) using the Apple ID signed in to Xcode; without it, it only exports the .ipa
# to build/export so you can check signing.
set -euo pipefail

TEAM_ID="C76RQ9NG73"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DESTINATION="export"
case "${1:-}" in
  "") ;;
  --upload) DESTINATION="upload" ;;
  *) echo "usage: $0 [--upload]" >&2; exit 2 ;;
esac

# Every upload needs a build number higher than the last one; a UTC timestamp always is.
BUILD_NUMBER="$(date -u +%Y%m%d%H%M)"
ARCHIVE="build/BeReyt.xcarchive"
OPTIONS="build/ExportOptions.plist"

xcodegen generate
rm -rf "$ARCHIVE" build/export

xcodebuild -project BeReyt.xcodeproj -scheme BeReyt -configuration Release \
  -destination "generic/platform=iOS" -allowProvisioningUpdates \
  -derivedDataPath build/DD -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" archive

cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>$DESTINATION</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTIONS" \
  -exportPath build/export -allowProvisioningUpdates

echo "build $BUILD_NUMBER: $DESTINATION done"
