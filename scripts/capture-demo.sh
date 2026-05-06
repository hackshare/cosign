#!/usr/bin/env bash
# Headless simulator screenshot capture for the Cosign demo app.
#
# Boots an iPhone simulator, pins the status bar to 9:41, runs the
# CosignDemoUITests walkthrough (which drives every screen and attaches
# screenshots), then exports the PNG attachments out of the .xcresult and
# renames them to the human-readable names the tests assign.
#
# Output: Derived/Screenshots/<timestamp>/  (plus a copy in screenshots/)
#
# Env overrides:
#   COSIGN_SCREENSHOT_SCHEME   Xcode scheme (default: CosignDemo)
#   COSIGN_SCREENSHOT_TEST     -only-testing identifier (default: CosignDemoUITests)
#   COSIGN_TUIST_GENERATE=1    regenerate the Tuist project before building

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
WORKSPACE="$ROOT/Cosign.xcworkspace"
SCHEME="${COSIGN_SCREENSHOT_SCHEME:-CosignDemo}"
TEST_ID="${COSIGN_SCREENSHOT_TEST:-CosignDemoUITests}"
DERIVED_DATA="$ROOT/Derived/ScreenshotDerivedData"
RESULT_BUNDLE="$ROOT/Derived/ScreenshotResults/demo-$TIMESTAMP.xcresult"
ATTACHMENTS_DIR="$ROOT/Derived/ScreenshotResults/demo-$TIMESTAMP-attachments"
OUTPUT_DIR="$ROOT/Derived/Screenshots/$TIMESTAMP"

rm -rf "$RESULT_BUNDLE" "$ATTACHMENTS_DIR"

# --- Resolve a simulator ----------------------------------------------------
# Prefer an already-booted device; otherwise pick the best available iPhone
# from a preference list and boot it.
resolve_udid() {
  xcrun simctl list devices available --json | /usr/bin/python3 -c '
import json,sys
data=json.load(sys.stdin)["devices"]
booted=None
prefs=["iPhone 17 Pro","iPhone 17","iPhone 16 Pro","iPhone 16","iPhone 15 Pro"]
def score(name):
    for i,p in enumerate(prefs):
        if name==p: return i
    return len(prefs)+1
best=None
for runtime,devs in data.items():
    if "iOS" not in runtime: continue
    for d in devs:
        if not d.get("isAvailable",False): continue
        name=d["name"]
        if not name.startswith("iPhone"): continue
        if d.get("state")=="Booted":
            booted=d["udid"]
        cand=(score(name),d["udid"])
        if best is None or cand[0]<best[0]:
            best=cand
print(booted or (best[1] if best else ""))
'
}

UDID="$(resolve_udid)"
if [ -z "$UDID" ]; then
  echo "ERROR: no available iPhone simulator found." >&2
  xcrun simctl list devices available >&2
  exit 1
fi

echo "Using simulator: $UDID"
DEST="platform=iOS Simulator,id=$UDID"

STATE="$(xcrun simctl list devices | grep "$UDID" | sed -E 's/.*\((Booted|Shutdown|[A-Za-z ]+)\).*/\1/' | head -1)"
if [ "$STATE" != "Booted" ]; then
  echo "Booting simulator..."
  xcrun simctl boot "$UDID"
fi
xcrun simctl bootstatus "$UDID" -b

cleanup() { xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1 || true; }
trap cleanup EXIT
xcrun simctl status_bar "$UDID" override \
  --time "9:41" --batteryLevel 100 --batteryState charged \
  --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 || true

if [ "${COSIGN_TUIST_GENERATE:-0}" = "1" ] && command -v tuist >/dev/null 2>&1; then
  echo "Generating Tuist project..."
  tuist generate --no-open
fi

mkdir -p "$(dirname "$RESULT_BUNDLE")" "$OUTPUT_DIR"

echo "Running Cosign demo walkthrough UITests ($TEST_ID)..."
set +e
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -destination "$DEST" \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -only-testing:"$TEST_ID" \
  test
XCB_STATUS=$?
set -e

if [ ! -e "$RESULT_BUNDLE" ]; then
  echo "ERROR: xcodebuild produced no result bundle (status $XCB_STATUS)." >&2
  exit 1
fi

echo "Exporting attachments..."
xcrun xcresulttool export attachments \
  --path "$RESULT_BUNDLE" \
  --output-path "$ATTACHMENTS_DIR"

MANIFEST="$ATTACHMENTS_DIR/manifest.json"
if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: no attachment manifest at $MANIFEST" >&2
  exit 1
fi

/usr/bin/python3 - "$MANIFEST" "$ATTACHMENTS_DIR" "$OUTPUT_DIR" <<'PY'
import json,os,shutil,sys,re
manifest,att_dir,out_dir=sys.argv[1],sys.argv[2],sys.argv[3]
data=json.load(open(manifest))

def attachments(obj):
    if isinstance(obj,dict):
        if "exportedFileName" in obj and "suggestedHumanReadableName" in obj:
            yield obj
        for v in obj.values():
            yield from attachments(v)
    elif isinstance(obj,list):
        for v in obj:
            yield from attachments(v)

copied=[]
seen=set()
for a in attachments(data):
    exported=a.get("exportedFileName")
    if not exported or not exported.lower().endswith(".png"): continue
    human=a.get("suggestedHumanReadableName") or exported
    # Only keep the explicit capture(name) screenshots, not XCTest's
    # auto-attached failure diagnostics ("UI Snapshot ...", "Synthesized ...").
    if not re.match(r"^\d+-", os.path.basename(human)): continue
    src=os.path.join(att_dir,exported)
    if not os.path.isfile(src): continue
    stem=os.path.splitext(os.path.basename(human))[0]
    stem=re.sub(r"_\d+_[0-9A-Fa-f-]{36}$","",stem)
    name=stem+".png"
    if name in seen: continue
    seen.add(name)
    shutil.copy2(src,os.path.join(out_dir,name))
    copied.append(name)

if not copied:
    print("ERROR: no screenshot attachments exported.",file=sys.stderr); sys.exit(1)
for p in sorted(copied):
    print(p)
PY

echo ""
echo "Screenshots written to: $OUTPUT_DIR"

# Mirror into a stable repo-root screenshots/ dir (Derived/ may be wiped).
STABLE_DIR="$ROOT/screenshots"
mkdir -p "$STABLE_DIR"
cp "$OUTPUT_DIR"/*.png "$STABLE_DIR/" 2>/dev/null && echo "Latest copied to: $STABLE_DIR"
