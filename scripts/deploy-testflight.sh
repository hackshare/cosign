#!/usr/bin/env bash
set -euo pipefail

# Build + upload Cosign to TestFlight in one command. iOS only.
# Usage: bash scripts/deploy-testflight.sh
#
# Archives the `Cosign` scheme (bundle id com.hackshare.cosign) and uploads it to
# TestFlight. NOTE: that target currently ships DEVNET content under the mainnet
# bundle id with the DEVNET-ribbon icon — the intended first TestFlight build.
# Switch its relayURL/environmentName/appIconName back to mainnet in Project.swift
# when shipping real mainnet.
#
# No fastlane: raw xcodebuild archive + export + `xcrun altool` upload, then the
# App Store Connect REST API to post "What to Test".
#
# ── ONE-TIME SETUP ────────────────────────────────────────────────────────────
# Signing + upload reuse the SAME account-wide App Store Connect API key as the
# other apps on this Apple account (com.hackshare.*). The key lives in the login
# keychain under `mycelium-asc-api`; verify with:
#     security find-generic-password -s mycelium-asc-api -w >/dev/null && echo OK
#
# The bundle id is registered automatically (-allowProvisioningUpdates), but the
# App Store Connect *app record* for com.hackshare.cosign must exist before the
# first upload (create it once at App Store Connect → Apps → +, or it 409s).
#
# APP_APPLE_ID is Cosign's numeric id from App Store Connect (App → App
# Information → "Apple ID"). The upload routes by bundle id and does NOT need it;
# it's only used to post the "What to Test" notes. Put it in docs/local/asc.env
# (gitignored) or leave unset to skip that step and post notes manually.
# ──────────────────────────────────────────────────────────────────────────────

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

G='\033[32m'; C='\033[36m'; D='\033[2m'; R='\033[0m'
step() { echo -e "\n${C}==> $1${R}"; }
info() { echo -e "  ${D}$1${R}"; }

TEAM_ID="${DEVELOPMENT_TEAM:-85ZZHRDM2S}"
SCHEME="Cosign"
WORKSPACE="$ROOT/Cosign.xcworkspace"
BUILD="$ROOT/build"
ARCHIVE="$BUILD/Cosign.xcarchive"
EXPORT_DIR="$BUILD/export"

MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%s)}"   # monotonic; override to pin (e.g. BUILD_NUMBER=1)
GIT_SHA=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo "nogit")

# Local, gitignored overrides (notably APP_APPLE_ID) so the notes step runs
# without the caller having to export anything by hand.
[ -f "$ROOT/docs/local/asc.env" ] && set -a && . "$ROOT/docs/local/asc.env" && set +a

# App Store Connect API credentials (account-wide; shared across com.hackshare.* apps).
ASC_KEYCHAIN_SERVICE="${ASC_KEYCHAIN_SERVICE:-mycelium-asc-api}"
ASC_KEY_ID="${ASC_KEY_ID:-5ZH4Z7H96H}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-69a6de6f-81a9-47e3-e053-5b8c7c11a4d1}"
APP_APPLE_ID="${APP_APPLE_ID:-}"   # Cosign's ASC numeric id; unset → skip notes step

# Stream the .p8 from the keychain (security -w returns hex for newline-containing values).
asc_key_pem() {
    security find-generic-password -s "$ASC_KEYCHAIN_SERVICE" -w ~/Library/Keychains/login.keychain-db | xxd -r -p
}

# altool reads the .p8 from ./private_keys only — materialize into a 0700 scratch dir.
ALTOOL_SCRATCH=$(mktemp -d -t cosign-deploy)
trap 'rm -rf "$ALTOOL_SCRATCH"' EXIT
mkdir "$ALTOOL_SCRATCH/private_keys"
asc_key_pem > "$ALTOOL_SCRATCH/private_keys/AuthKey_${ASC_KEY_ID}.p8"
chmod 600 "$ALTOOL_SCRATCH/private_keys/AuthKey_${ASC_KEY_ID}.p8"

# TestFlight notes: hand-curated, regenerated per release. Fail loudly if missing.
TESTFLIGHT_NOTES_FILE="$ROOT/TESTFLIGHT_NOTES.md"
if [ ! -s "$TESTFLIGHT_NOTES_FILE" ]; then
    echo "ERROR: $TESTFLIGHT_NOTES_FILE is missing or empty." >&2
    echo "These notes appear in TestFlight as 'What to Test'. Write it before deploying." >&2
    exit 1
fi
RELEASE_NOTES=$(cat "$TESTFLIGHT_NOTES_FILE")

info "version $MARKETING_VERSION ($BUILD_NUMBER) · git $GIT_SHA · team $TEAM_ID"
info "asc key $ASC_KEY_ID via keychain '$ASC_KEYCHAIN_SERVICE'"

# ---------- Generate + archive ----------
step "Generating Tuist project"
tuist generate --no-open >/dev/null

# ---------- Build provenance: generate + sign the BuildClaim ----------
# Requires the local release key at .build-claim/release-key.env (gitignored).
# Without it, the build ships without an embedded claim (EMBED_BUILD_CLAIM=NO).
BUILD_CLAIM_DIR="$BUILD/build-claim"
EMBED_BUILD_CLAIM=NO
KEY_ENV="$ROOT/.build-claim/release-key.env"
if [ -f "$KEY_ENV" ]; then
    step "Generating + signing BuildClaim (provenance)"
    rm -rf "$BUILD_CLAIM_DIR"; mkdir -p "$BUILD_CLAIM_DIR"
    set -a; . "$KEY_ENV"; set +a
    APP_VERSION="$MARKETING_VERSION" APP_BUILD="$BUILD_NUMBER" \
        BUILD_CLAIM_KEY_ID="${BUILD_CLAIM_KEY_ID:-cosign-release-2026-06}" \
        COSIGN_TAG="v${MARKETING_VERSION}+${BUILD_NUMBER}" \
        COSIGN_REPOSITORY="hackshare/cosign" \
        python3 "$ROOT/ci/create_build_claim.py" "$BUILD_CLAIM_DIR/BuildClaim.json" >/dev/null
    xcrun swiftc "$ROOT/Tools/SignBuildClaim.swift" -o "$BUILD/sign-build-claim" 2>/dev/null
    "$BUILD/sign-build-claim" "$BUILD_CLAIM_DIR/BuildClaim.json" "$BUILD_CLAIM_DIR/BuildClaim.sig"
    EMBED_BUILD_CLAIM=YES
    info "build claim signed with ${BUILD_CLAIM_KEY_ID:-cosign-release-2026-06}"
else
    info "no .build-claim/release-key.env — building WITHOUT provenance (EMBED_BUILD_CLAIM=NO)"
fi

step "Archiving $SCHEME (Release, build $BUILD_NUMBER)"
rm -rf "$ARCHIVE"
xcodebuild archive \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    MARKETING_VERSION="$MARKETING_VERSION" \
    EMBED_BUILD_CLAIM="$EMBED_BUILD_CLAIM" \
    BUILD_CLAIM_DIR="$BUILD_CLAIM_DIR" \
    -quiet

if [ "$EMBED_BUILD_CLAIM" = "YES" ]; then
    step "Verifying embedded BuildClaim"
    APP_IN_ARCHIVE="$ARCHIVE/Products/Applications/Cosign.app"
    cmp "$BUILD_CLAIM_DIR/BuildClaim.json" "$APP_IN_ARCHIVE/BuildClaim.json"
    cmp "$BUILD_CLAIM_DIR/BuildClaim.sig" "$APP_IN_ARCHIVE/BuildClaim.sig"
    codesign --verify --deep --strict "$APP_IN_ARCHIVE"
    info "BuildClaim sealed into the archive + signature valid"
fi

step "Exporting IPA"
mkdir -p "$BUILD"
cat > "$BUILD/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
PLIST
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$BUILD/ExportOptions.plist" \
    -allowProvisioningUpdates \
    -quiet

IPA="$(find "$EXPORT_DIR" -name '*.ipa' | head -1)"
[ -n "$IPA" ] || { echo "ERROR: no .ipa produced in $EXPORT_DIR" >&2; exit 1; }

step "Uploading to TestFlight"
(cd "$ALTOOL_SCRATCH" && xcrun altool --upload-app \
    --type ios \
    --file "$IPA" \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID")
echo -e "  ${G}Uploaded to TestFlight (build $BUILD_NUMBER)${R}"
if [ "$EMBED_BUILD_CLAIM" = "YES" ]; then
    TAG="v${MARKETING_VERSION}+${BUILD_NUMBER}"
    echo -e "  ${D}Provenance: tag this release to match the embedded claim:${R}"
    echo -e "  ${D}  git tag -s $TAG -m \"Release $TAG\" && git push origin $TAG${R}"
fi

# ---------- Post "What to Test" ----------
if [ -z "$APP_APPLE_ID" ]; then
    echo -e "\n  ${D}APP_APPLE_ID unset; skipping the notes step. Set 'What to Test' manually in ASC,"
    echo -e "  or re-run with APP_APPLE_ID=<numeric id> once the build finishes processing.${R}"
    echo -e "\n${G}Done. Build $BUILD_NUMBER ($GIT_SHA)${R}"
    exit 0
fi

step "Setting 'What to Test' via App Store Connect API (polls until the build appears)"
asc_key_pem | ASC_KEY_ID="$ASC_KEY_ID" ASC_ISSUER_ID="$ASC_ISSUER_ID" \
    APP_APPLE_ID="$APP_APPLE_ID" BUILD_NUMBER="$BUILD_NUMBER" NOTES="$RELEASE_NOTES" \
    ruby -ropenssl -rbase64 -rjson -rnet/http -e '
        ec = OpenSSL::PKey.read(STDIN.read)
        now = Time.now.to_i
        header  = JSON.dump(alg: "ES256", kid: ENV["ASC_KEY_ID"], typ: "JWT")
        payload = JSON.dump(iss: ENV["ASC_ISSUER_ID"], iat: now, exp: now + 1200, aud: "appstoreconnect-v1")
        b64u = ->(s) { Base64.urlsafe_encode64(s).delete("=") }
        unsigned = "#{b64u.(header)}.#{b64u.(payload)}"
        asn1 = OpenSSL::ASN1.decode(ec.sign(OpenSSL::Digest.new("SHA256"), unsigned))
        r = asn1.value[0].value.to_s(2).rjust(32, "\x00".b)[-32, 32]
        s = asn1.value[1].value.to_s(2).rjust(32, "\x00".b)[-32, 32]
        jwt = "#{unsigned}.#{b64u.(r + s)}"

        base = URI("https://api.appstoreconnect.apple.com")
        http = Net::HTTP.new(base.hostname, base.port).tap { |h| h.use_ssl = true }
        api = lambda do |method, path, body = nil|
            klass = {get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch}.fetch(method)
            req = klass.new(path)
            req["Authorization"] = "Bearer #{jwt}"
            if body then req["Content-Type"] = "application/json"; req.body = body end
            res = http.request(req)
            [res.code.to_i, res.body]
        end

        app_id  = ENV["APP_APPLE_ID"]; version = ENV["BUILD_NUMBER"]; notes = ENV["NOTES"]
        builds = []
        10.times do |i|
            code, body = api.(:get, "/v1/builds?filter%5Bapp%5D=#{app_id}&filter%5Bversion%5D=#{version}&limit=10")
            raise "GET builds failed: HTTP #{code} #{body}" unless code == 200
            builds = JSON.parse(body)["data"]
            break unless builds.empty?
            STDERR.puts "  build not visible in ASC yet, waiting (attempt #{i + 1}/10)..."
            sleep 30
        end
        raise "No build found for version #{version} after 5 minutes — check Apple processing" if builds.empty?

        builds.each do |build|
            bid = build["id"]
            code, body = api.(:get, "/v1/builds/#{bid}/betaBuildLocalizations")
            raise "GET localizations failed: HTTP #{code} #{body}" unless code == 200
            locs = JSON.parse(body)["data"]
            if locs.any?
                loc_id = locs.first["id"]
                payload = JSON.dump(data: {type: "betaBuildLocalizations", id: loc_id, attributes: {whatsNew: notes}})
                code, body = api.(:patch, "/v1/betaBuildLocalizations/#{loc_id}", payload)
            else
                payload = JSON.dump(data: {type: "betaBuildLocalizations",
                                            attributes: {locale: "en-US", whatsNew: notes},
                                            relationships: {build: {data: {type: "builds", id: bid}}}})
                code, body = api.(:post, "/v1/betaBuildLocalizations", payload)
            end
            raise "Failed to set notes on build #{bid}: HTTP #{code} #{body}" unless [200, 201].include?(code)
            puts "  Notes set on build #{bid}"
        end
    '

echo -e "\n${G}Done. Build $BUILD_NUMBER ($GIT_SHA) uploaded and notes posted.${R}"
