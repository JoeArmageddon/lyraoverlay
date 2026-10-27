# Releasing (maintainers)

1. Bump `CFBundleShortVersionString` in `Packaging/Info.plist`; update the changelog/release notes.
2. `swift test` in `LyraCore`, `LyraApp`, `Tools/FontFactory`.
3. Build with a **Developer ID Application** identity:
   `SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" Scripts/make-app.sh`
   (add `--options runtime` to the codesign call for notarization).
4. Notarize: `ditto -c -k --keepParent dist/Lyra.app Lyra.zip`, then
   `xcrun notarytool submit Lyra.zip --keychain-profile <profile> --wait`, then `xcrun stapler staple dist/Lyra.app`.
5. `SIGN_IDENTITY=... Scripts/make-dmg.sh` packs the stapled app into `dist/Lyra-<version>.dmg` (notarize and staple the dmg too if you can). Attach it to a GitHub release with the changelog and the printed SHA-256.
6. Sparkle auto-update is not set up yet.

Until notarized builds exist, the README tells users to build from source.
