#!/usr/bin/env bash
set -euo pipefail

# Post the TestFlight "What to Test" notes (TESTFLIGHT_NOTES.md) to a build via
# the App Store Connect REST API — no re-archive/upload. Useful when the deploy
# script's inline notes step times out waiting on Apple processing.
#
# Usage:
#   bash scripts/set-testflight-notes.sh            # latest build
#   bash scripts/set-testflight-notes.sh 1782522259 # a specific build (CFBundleVersion)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ -f "$ROOT/docs/local/asc.env" ] && set -a && . "$ROOT/docs/local/asc.env" && set +a

ASC_KEYCHAIN_SERVICE="${ASC_KEYCHAIN_SERVICE:-mycelium-asc-api}"
ASC_KEY_ID="${ASC_KEY_ID:-5ZH4Z7H96H}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-69a6de6f-81a9-47e3-e053-5b8c7c11a4d1}"
: "${APP_APPLE_ID:?Set APP_APPLE_ID in docs/local/asc.env first}"
BUILD_NUMBER="${1:-${BUILD_NUMBER:-}}"   # optional; empty → most recently uploaded build

TESTFLIGHT_NOTES_FILE="$ROOT/TESTFLIGHT_NOTES.md"
[ -s "$TESTFLIGHT_NOTES_FILE" ] || { echo "ERROR: $TESTFLIGHT_NOTES_FILE missing/empty" >&2; exit 1; }
NOTES=$(cat "$TESTFLIGHT_NOTES_FILE")

asc_key_pem() {
    security find-generic-password -s "$ASC_KEYCHAIN_SERVICE" -w ~/Library/Keychains/login.keychain-db | xxd -r -p
}

asc_key_pem | ASC_KEY_ID="$ASC_KEY_ID" ASC_ISSUER_ID="$ASC_ISSUER_ID" \
    APP_APPLE_ID="$APP_APPLE_ID" BUILD_NUMBER="$BUILD_NUMBER" NOTES="$NOTES" \
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

        app_id = ENV["APP_APPLE_ID"]; version = ENV["BUILD_NUMBER"]; notes = ENV["NOTES"]
        query = version.empty? ?
            "/v1/builds?filter%5Bapp%5D=#{app_id}&sort=-uploadedDate&limit=1" :
            "/v1/builds?filter%5Bapp%5D=#{app_id}&filter%5Bversion%5D=#{version}&limit=10"

        builds = []
        10.times do |i|
            code, body = api.(:get, query)
            raise "GET builds failed: HTTP #{code} #{body}" unless code == 200
            builds = JSON.parse(body)["data"]
            break unless builds.empty?
            STDERR.puts "  build not visible in ASC yet, waiting (attempt #{i + 1}/10)..."
            sleep 30
        end
        raise "No build found#{version.empty? ? "" : " for version #{version}"} — check Apple processing" if builds.empty?

        builds.each do |build|
            bid = build["id"]; bver = build.dig("attributes", "version")
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
            puts "  Notes set on build #{bid} (version #{bver})"
        end
    '

echo "Done."
