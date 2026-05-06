#!/usr/bin/env bash
set -euo pipefail

# Builds the Rust core staticlib for all required Apple targets.
# Run from the repo root.

cd "$(dirname "$0")/.."

CRATE_DIR="core"
PROFILE="${PROFILE:-release}"
PROFILE_FLAG=""
PROFILE_DIR="debug"
IOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-17.0}"

if [[ "$PROFILE" == "release" ]]; then
    PROFILE_FLAG="--release"
    PROFILE_DIR="release"
fi

TARGETS=(
    "aarch64-apple-ios"
    "aarch64-apple-ios-sim"
    "x86_64-apple-ios"
)

for TARGET in "${TARGETS[@]}"; do
    echo "==> building for $TARGET ($PROFILE)"
    if [[ "$TARGET" == "aarch64-apple-ios" ]]; then
        SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
    else
        SDKROOT="$(xcrun --sdk iphonesimulator --show-sdk-path)"
    fi

    (
        cd "$CRATE_DIR"
        IPHONEOS_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" \
            SDKROOT="$SDKROOT" \
            cargo build $PROFILE_FLAG --lib --target "$TARGET"
    )
done

echo "==> rust build complete (profile=$PROFILE_DIR)"
