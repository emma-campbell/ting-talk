#!/bin/sh
# Build TingTalk.app: an Apple silicon (arm64) release build wrapped in an app
# bundle and ad-hoc signed with the hardened runtime. No Intel build: there's
# no Intel hardware to test it on.
#
#   scripts/build-app.sh [version] [build-number]
#
# Output: dist/TingTalk.app and dist/TingTalk.zip. Used locally and by CI.
#
# Signing: ad-hoc by default (CI). macOS ties permissions like Accessibility to
# an ad-hoc app's exact build, so every rebuild has to be granted again. For
# local work, sign with your Apple Development certificate and the grant sticks:
#
#   SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/build-app.sh
#
# Distributing to other people without a Gatekeeper warning needs a Developer ID
# Application identity plus notarization (not set up yet).
set -eu
cd "$(dirname "$0")/.."

VERSION="${1:-0.0.0-dev}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
BUILD="${2:-1}"
APP=dist/TingTalk.app

swift build --package-path app -c release --arch arm64
BIN="$(swift build --package-path app -c release --arch arm64 --show-bin-path)/TingTalk"

rm -rf dist
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/TingTalk"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" \
    app/Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

codesign --force --sign "$SIGN_IDENTITY" --options runtime \
    --entitlements app/Resources/TingTalk.entitlements "$APP"
codesign --verify --strict "$APP"

# ditto keeps the bundle's structure and signature intact in the zip.
ditto -c -k --keepParent "$APP" dist/TingTalk.zip

lipo -archs "$APP/Contents/MacOS/TingTalk"
echo "built $APP ($VERSION, build $BUILD), signed: $SIGN_IDENTITY"
