#!/usr/bin/env bash
set -euo pipefail

# Builds the Rust core for all required Apple targets, generates Swift bindings
# via UniFFI, packages each arch as a "static framework" (containing the staticlib,
# headers, and a Modules/module.modulemap), and combines them into a
# framework-style XCFramework. Xcode auto-discovers the cosign_coreFFI Clang
# module from the framework's modulemap, which makes it visible to consumers
# without manual SWIFT_INCLUDE_PATHS configuration.
#
# Run from the repo root.

cd "$(dirname "$0")/.."

CRATE_DIR="core"
LIB_NAME="libcosign_core.a"
# Framework directory name MUST match the Clang module name for Xcode's
# auto-discovery. The UniFFI-generated Swift does `import cosign_coreFFI`,
# so the framework, binary, and modulemap module name all use lowercase.
FRAMEWORK_NAME="cosign_coreFFI"
PROFILE="${PROFILE:-release}"
PROFILE_DIR="debug"
[[ "$PROFILE" == "release" ]] && PROFILE_DIR="release"

# 1. Build Rust for all Apple targets.
./scripts/build-rust.sh

# 2. Combine the two simulator slices into one fat library.
SIM_FAT_DIR="$CRATE_DIR/target/sim-fat/$PROFILE_DIR"
mkdir -p "$SIM_FAT_DIR"

lipo -create \
    "$CRATE_DIR/target/aarch64-apple-ios-sim/$PROFILE_DIR/$LIB_NAME" \
    "$CRATE_DIR/target/x86_64-apple-ios/$PROFILE_DIR/$LIB_NAME" \
    -output "$SIM_FAT_DIR/$LIB_NAME"

# 3. Generate Swift bindings via UniFFI.
GEN_DIR="Modules/CosignCore/Sources/Generated"
rm -rf "$GEN_DIR"
mkdir -p "$GEN_DIR"

(cd "$CRATE_DIR" && cargo run --quiet --bin uniffi-bindgen -- \
    generate src/cosign_core.udl \
    --language swift \
    --config uniffi.toml \
    --out-dir "../$GEN_DIR")

GEN_HEADER="$GEN_DIR/cosign_coreFFI.h"
if [[ ! -f "$GEN_HEADER" ]]; then
    echo "ERROR: generated header not found at $GEN_HEADER" >&2
    ls -la "$GEN_DIR" >&2
    exit 1
fi

# Drop UniFFI's emitted modulemap; we declare our own inside the framework.
rm -f "$GEN_DIR"/*.modulemap

# 4. Build a static framework for each arch slice.
build_framework() {
    local SLICE_NAME="$1"
    local STATIC_LIB="$2"
    local OUT_DIR="$CRATE_DIR/target/frameworks/$SLICE_NAME"
    local FW_DIR="$OUT_DIR/$FRAMEWORK_NAME.framework"

    rm -rf "$OUT_DIR"
    mkdir -p "$FW_DIR/Headers" "$FW_DIR/Modules"

    cp "$STATIC_LIB" "$FW_DIR/$FRAMEWORK_NAME"
    cp "$GEN_DIR/cosign_coreFFI.h" "$FW_DIR/Headers/"

    cat > "$FW_DIR/Modules/module.modulemap" <<EOF
framework module cosign_coreFFI {
    umbrella header "cosign_coreFFI.h"
    export *
    module * { export * }
}
EOF

    cat > "$FW_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>$FRAMEWORK_NAME</string>
    <key>CFBundleIdentifier</key><string>com.hackshare.cosign.cosigncoreffi</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$FRAMEWORK_NAME</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>MinimumOSVersion</key><string>17.0</string>
</dict>
</plist>
EOF

    echo "$FW_DIR"
}

DEVICE_FW=$(build_framework "ios-arm64" "$CRATE_DIR/target/aarch64-apple-ios/$PROFILE_DIR/$LIB_NAME")
SIM_FW=$(build_framework "ios-arm64_x86_64-simulator" "$SIM_FAT_DIR/$LIB_NAME")

# 5. Combine into a framework-style XCFramework.
XCF_OUT="Modules/CosignCore/Frameworks/CosignCore.xcframework"
rm -rf "$XCF_OUT"
mkdir -p "$(dirname "$XCF_OUT")"

xcodebuild -create-xcframework \
    -framework "$DEVICE_FW" \
    -framework "$SIM_FW" \
    -output "$XCF_OUT"

echo "==> XCFramework written to $XCF_OUT"
