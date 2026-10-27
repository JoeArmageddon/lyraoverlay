# Building

## Requirements
macOS 14+ on Apple silicon, Xcode or Command Line Tools with Swift 6 (Swift 5 language mode is used).
No third-party dependencies. Only SwiftPM is used.

## Build the app
```bash
Scripts/make-app.sh          # writes dist/Lyra.app
open dist/Lyra.app           # launch with open, not by running the binary from a shell
```
Or from source: `cd LyraApp && swift run -c release lyra-app`. (Launching the binary directly from a
background shell can put windows on the wrong Space; use `open`.)

## Signing and macOS permissions
By default the app is **ad-hoc signed**. macOS ties Automation and System Audio Recording grants to the code
signature, and an ad-hoc signature changes with every build, so permission prompts can return after each rebuild.
To avoid that, sign with a stable certificate (a free Apple Development certificate from Xcode works):

```bash
security find-identity -v -p codesigning        # find your identity
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" Scripts/make-app.sh
```
Distributing to other Macs needs Developer ID signing and notarization: see [RELEASING.md](RELEASING.md).

## Tests
```bash
swift test --package-path LyraCore
swift test --package-path LyraApp       # render tests need a Metal GPU; they skip without one
swift test --package-path Tools/FontFactory
```
Tests never touch real permissions or audio; capture logic is tested with synthetic audio and a fake clock.

## Useful tools
```bash
cd LyraCore
swift run lyra-cli lookup "Artist" "Title"   # fetch synced lyrics
swift run lyra-cli watch                     # follow what is playing
swift run lyra-cli audio 10 --backend tap    # audio features (triggers the permission prompt)
swift run lyra-cli palette                   # colors from the current cover
swift run lyra-cli mood                      # what Match the music would choose
cd ../LyraApp
swift run lyra-app --render-styles styles.png    # also --render-cinematic, --render-cinema, --render-corner, --render-lights, --render-animations
swift run lyra-app --overlay-demo corner         # overlay with sample lyrics (full|corner)
```
Fonts: `Scripts/install-fonts.sh [folder]` validates and installs fonts into `Fonts/`; `--check` audits only.
