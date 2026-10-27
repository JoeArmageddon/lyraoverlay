#!/usr/bin/env bash
# Builds Lyra.app: a release build of LyraApp, wrapped in a signed app bundle with an icon.
#
#   Scripts/make-app.sh        writes dist/Lyra.app (from any directory)
#
# The bundle is ad-hoc signed unless SIGN_IDENTITY is set, which is enough to run on this Mac. Sharing it with other Macs needs
# a Developer ID signature and notarization; see the README.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Lyra.app"
PACKAGE="$ROOT/LyraApp"

echo "==> Building LyraApp (release)"
swift build -c release --package-path "$PACKAGE" --product lyra-app
BIN="$(swift build -c release --package-path "$PACKAGE" --show-bin-path)/lyra-app"
[ -x "$BIN" ] || { echo "error: built executable not found at $BIN" >&2; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST"
cp "$BIN" "$APP/Contents/MacOS/Lyra"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"

# Lyra's own fonts travel inside the app; it registers them at launch (FontCatalog.registerBundledFonts).
if compgen -G "$ROOT/Fonts/*.ttf" > /dev/null; then
    echo "==> Bundling the Lyra fonts"
    mkdir -p "$APP/Contents/Resources/Fonts"
    cp "$ROOT"/Fonts/*.ttf "$APP/Contents/Resources/Fonts/"
    [ -f "$ROOT/Fonts/LICENSE.txt" ] && cp "$ROOT/Fonts/LICENSE.txt" "$APP/Contents/Resources/Fonts/"
else
    echo "warning: no fonts in $ROOT/Fonts; run the font factory first (see Fonts/README.md)" >&2
fi

echo "==> Drawing the icon"
ICONSET="$DIST/AppIcon.iconset"
rm -rf "$ICONSET"
swiftc -O -o "$DIST/make-icon" "$ROOT/Packaging/make-icon.swift"
"$DIST/make-icon" "$ICONSET"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"

# SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" Scripts/make-app.sh keeps macOS permissions
# (Automation, System Audio Recording) across rebuilds; the default ad-hoc signature changes every build.
IDENTITY="${SIGN_IDENTITY:--}"
echo "==> Signing (${SIGN_IDENTITY:-ad hoc})"
codesign --force --deep --sign "$IDENTITY" "$APP"

echo "==> Verifying"
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "signature: $(codesign -dv "$APP" 2>&1 | grep -E 'Identifier|Signature' | tr '\n' ' ')"
echo "version:   $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
echo "icon:      $(iconutil -c iconset -o /tmp/lyra-icon-check.iconset "$APP/Contents/Resources/AppIcon.icns" >/dev/null 2>&1 && ls /tmp/lyra-icon-check.iconset | wc -l | tr -d ' ') sizes; $(du -h "$APP/Contents/Resources/AppIcon.icns" | cut -f1)"
rm -rf /tmp/lyra-icon-check.iconset

echo
echo "Built $APP"
echo "Run it with:  open \"$APP\""
