# Architecture

Two SwiftPM packages plus tools.

```
LyraCore/   pure logic, no UI, fully unit-tested
  NowPlaying/   Spotify and Music readers (osascript subprocess), clock interpolation
  Lyrics*       LRCLIB provider, cache, LRC parser, word-timing interpolation, cursor, Session
  Audio/        FFT, beat/tempo, FeaturesTracker, capture backends (Core Audio tap, ScreenCaptureKit fallback),
                silence detector and capture state machine
  Color/        k-means palette in Lab, theme resolution, artwork providers (player, iTunes Search)
  Layout/       lyric styles → DrawItems, animations, cinematic shots, corner overlay, film effects, lights
  Theme/        built-in themes, theme store (JSON import/export)
  Mood/         genre classifier, audio profile, mood engine, AutoThemeEngine
  Background/   player background library
LyraApp/
  LyraRender/   Metal renderer (runtime-compiled shaders), CoreText text textures, overlay + player windows,
                SwiftUI settings, AppController (wires everything together)
  lyra-app      the executable and its demo/render flags
Tools/FontFactory   Swift TrueType writer for the generated fonts
Packaging/ Scripts/ Fonts/ Docs/ Spikes/
```

## Data flow
`NowPlayingMonitor` → `LyricsSession` (lyrics from LRCLIB/cache, cursor, artwork + palette) → `AppController`
(a 0.4 s poll for activity and auto-theme; drawing runs at display rate) → `LyricsPipeline` (style layout,
then animator) → `[DrawItem]` → `MetalRenderer` (text quads, rim light, film passes, panel) → overlay or player view.
Audio capture → `FeaturesTracker` → beat/bass into styles and lights, and features into `AutoThemeEngine`.

## Key decisions
- **Layout is pure Swift** so styles are testable without a GPU; Metal only draws what layout says.
- **Audio via Core Audio tap** (narrow System Audio Recording permission, no re-consent nags). ScreenCaptureKit
  remains as a fallback backend.
- **osascript subprocess** for players: `NSAppleScript` stalled off the main thread.
- **Overlay windows are `NSPanel` (nonactivating)**: a plain `NSWindow` is never placed into another app's
  full-screen Space under the regular activation policy.
- **Fonts are data-driven**: any `Lyra*.ttf` in `Fonts/` beyond the eight generated originals becomes a hand-drawn entry.
- **Tolerant settings decoding** so old or hand-edited files never block launch.
- **Auto theme** weights genre 0.55, audio 0.30, cover 0.15, discounts by self-confidence, caps changes per track,
  and yields to any manual choice.

## Adding things
- A style: implement `LyricStyle`, register in `LyricStyles`, add a test.
- A theme: add to `Theme.swift`; tests require installed fonts and unique font usage for Lyra fonts.
- A font: see [Fonts/README.md](../Fonts/README.md).
