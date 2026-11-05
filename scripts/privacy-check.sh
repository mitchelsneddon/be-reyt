#!/usr/bin/env bash
# Fails on networking, WebKit, PCC model or analytics usage (plan requirement 33).
# Usage: scripts/privacy-check.sh [--binary <path-to-binary>]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SELF="scripts/privacy-check.sh"
fail=0

PATTERNS=(
  'URLSession'
  'URLRequest'
  'NWConnection'
  'import Network'
  'import WebKit'
  'DocumentType\.html'
  'PrivateCloudComputeLanguageModel'
  'import (FirebaseAnalytics|Firebase|Amplitude|Mixpanel|Segment|Sentry|Crashlytics|AppCenter|PostHog|Datadog|Bugsnag|AppsFlyer|Adjust)'
)

for p in "${PATTERNS[@]}"; do
  if hits=$(grep -rnE --include='*.swift' --include='*.m' --include='*.h' "$p" App Packages 2>/dev/null | grep -v "$SELF" | grep -v '/\.build/'); then
    echo "privacy-check: banned pattern '$p':"
    echo "$hits"
    fail=1
  fi
done

if [[ "${1:-}" == "--binary" ]]; then
  BIN="${2:?usage: --binary <path>}"
  if linked=$(otool -L "$BIN" | grep -E 'Network\.framework|WebKit\.framework'); then
    echo "privacy-check: binary links banned framework:"
    echo "$linked"
    fail=1
  fi
fi

if [[ $fail -ne 0 ]]; then exit 1; fi
echo "privacy-check: ok"
