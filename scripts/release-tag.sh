#!/usr/bin/env bash
set -euo pipefail

# Cut and push a signed release tag. Pushing a v<version>+<build> tag triggers
# .github/workflows/release.yml, which builds, embeds + signs the BuildClaim,
# uploads to TestFlight, and publishes the provenance GitHub Release.
#
# Usage: scripts/release-tag.sh [version]
#   version defaults to MARKETING_VERSION in TargetFactory.swift.
#   The build number is the unix timestamp (matching deploy-testflight.sh).

cd "$(dirname "$0")/.."

VERSION="${1:-$(grep -oE '"MARKETING_VERSION": "[^"]+"' \
    Tuist/ProjectDescriptionHelpers/TargetFactory.swift | head -1 |
    sed -E 's/.*"([0-9.]+)".*/\1/')}"
[ -n "$VERSION" ] || { echo "could not determine version" >&2; exit 1; }

BUILD="$(date +%s)"
TAG="v${VERSION}+${BUILD}"

echo "Cutting signed tag $TAG"
git tag -s "$TAG" -m "Release $TAG"
git push origin "$TAG"
echo "Pushed $TAG — the release workflow will build, sign, and upload to TestFlight."
