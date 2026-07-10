#!/usr/bin/env bash
# Build + (re)install Cosign builds onto the booted iOS simulator, so interactive
# testing stays in sync after code changes. Defaults to the devnet + demo builds;
# override with SCHEMES="Cosign CosignDemo" etc.
#   Usage: bash scripts/deploy-sim.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEMES="${SCHEMES:-Cosign CosignDemo}"

UDID="$(xcrun simctl list devices booted 2>/dev/null \
  | grep -oE '\([0-9A-Fa-f-]{36}\)' | tr -d '()' | head -1)"
if [ -z "$UDID" ]; then
  echo "No booted simulator. Open one (open -a Simulator) and retry." >&2
  exit 1
fi
echo "Simulator: $UDID"

# Build out-of-tree so 'tuist generate' (which wipes Derived/) can't clobber it.
DD="/tmp/cosign-sim-dd"
echo "Generating Tuist project..."
tuist generate --no-open >/dev/null

for SCHEME in $SCHEMES; do
  echo "Building $SCHEME..."
  xcodebuild -workspace "$ROOT/Cosign.xcworkspace" -scheme "$SCHEME" \
    -destination "id=$UDID" -derivedDataPath "$DD" -quiet build
  APP="$(find "$DD/Build/Products" -name "$SCHEME.app" -maxdepth 3 | head -1)"
  BID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
  xcrun simctl terminate "$UDID" "$BID" >/dev/null 2>&1 || true
  xcrun simctl install "$UDID" "$APP"
  echo "  installed $BID"
done

xcrun simctl status_bar "$UDID" override \
  --time "9:41" --batteryLevel 100 --wifiBars 3 >/dev/null 2>&1 || true

echo "Done. Builds are on the booted simulator ($SCHEMES) — launch from the home screen."
