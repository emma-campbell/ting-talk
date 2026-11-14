#!/bin/sh
# Verify a built TingTalk.app has what macOS needs. Each of these can break
# silently: the app still builds and launches, but mic access, the menu-bar-only
# behaviour, or launching on older macOS quietly stops working.
#
#   scripts/check-app.sh [path/to/TingTalk.app]   (default: dist/TingTalk.app)
set -eu
cd "$(dirname "$0")/.."
APP="${1:-dist/TingTalk.app}"
PLIST="$APP/Contents/Info.plist"
BIN="$APP/Contents/MacOS/TingTalk"
failed=0

check() {  # check <description> <command...>
    desc="$1"; shift
    if "$@" >/dev/null 2>&1; then echo "ok    $desc"; else echo "FAIL  $desc"; failed=1; fi
}
plist_is() { [ "$(/usr/libexec/PlistBuddy -c "Print :$1" "$PLIST")" = "$2" ]; }
plist_set() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" | grep -q .; }

check "bundle id is dev.emmacampbell.TingTalk" plist_is CFBundleIdentifier dev.emmacampbell.TingTalk
check "menu-bar only (LSUIElement)" plist_is LSUIElement true
check "microphone usage description present (A5)" plist_set NSMicrophoneUsageDescription
check "version filled in" sh -c "! grep -q __VERSION__ '$PLIST'"
check "minimum macOS 14 in Info.plist" plist_is LSMinimumSystemVersion 14.0
check "binary is arm64 only" sh -c "[ \"\$(lipo -archs '$BIN')\" = arm64 ]"
check "binary runs on macOS 14" sh -c "vtool -show-build '$BIN' | grep -q 'minos 14.0'"
check "signature valid" codesign --verify --strict "$APP"
check "hardened runtime" sh -c "codesign -dv '$APP' 2>&1 | grep -q 'flags=.*runtime'"
check "audio-input entitlement (mic under hardened runtime)" \
    sh -c "codesign -d --entitlements - '$APP' 2>&1 | grep -q com.apple.security.device.audio-input"

exit $failed
