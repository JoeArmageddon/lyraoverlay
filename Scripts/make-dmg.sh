#!/usr/bin/env bash
# Packs dist/Lyra.app into dist/Lyra-<version>.dmg (drag Lyra to Applications).
#
#   Scripts/make-dmg.sh          builds the app first if dist/Lyra.app is missing
#   SIGN_IDENTITY="Developer ID Application: ..." Scripts/make-dmg.sh   also signs the dmg
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/Lyra.app"
[ -d "$APP" ] || "$ROOT/Scripts/make-app.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/dist/Lyra-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Staging"
cp -R "$APP" "$STAGE/Lyra.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/LICENSE" "$STAGE/LICENSE.txt"

echo "==> Creating $DMG"
rm -f "$DMG"
hdiutil create -volname "Lyra" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG" >/dev/null

if [ -n "${SIGN_IDENTITY:-}" ]; then
    echo "==> Signing the dmg"
    codesign --force --sign "$SIGN_IDENTITY" "$DMG"
fi

hdiutil verify "$DMG" >/dev/null && echo "verified"
echo "sha256:  $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo "size:    $(du -h "$DMG" | cut -f1)"
echo "Built $DMG"
