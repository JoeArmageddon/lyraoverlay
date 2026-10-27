# Contributing to Lyra

Thanks for helping. This guide covers how to build and test the project, how the code is organized, and
how to add the things people most often add: a theme, a font, a lyric style.

Please read the [code of conduct](CODE_OF_CONDUCT.md). For security problems see
[SECURITY.md](SECURITY.md), not a public issue.

## What you need

- A Mac with Apple silicon running macOS 14 or later.
- Xcode with the macOS SDK and the Swift toolchain that matches it. The project is developed with
  Xcode 27.1 (Swift 6.4) and uses Swift 5 language mode. Older toolchains have not been tried.
- Nothing else. There are no third-party dependencies, no package manager steps and no Xcode project:
  everything is Swift Package Manager.
- Optional: Spotify and/or the Music app, for trying changes with real playback.

## Build, test, run

```bash
# Logic: parsing, timing, audio analysis, layout, styles, themes (no screen or permissions needed)
swift test --package-path LyraCore

# Drawing and windows: Metal renderer, overlay, player window, settings (the render tests need a GPU)
swift test --package-path LyraApp

# The font generator
swift test --package-path Tools/FontFactory

# Build the app bundle (dist/Lyra.app, signed ad hoc) and open it
Scripts/make-app.sh
open dist/Lyra.app
```

Every pull request should keep all three test suites green. Tests never need a screen, a music app or a
macOS permission prompt, with the exceptions called out in the test name or comment.

Launch the app the way a user does (`open dist/Lyra.app`). Running the binary straight from a shell
can place its windows on the wrong Space and is misleading when you test window behavior.

## How the code is organized

```
LyraCore/        Pure logic with tests. No windows, no drawing.
  Sources/LyraCore/
    NowPlaying/  Reading Spotify and Music (AppleScript), track monitor
    Lyrics/      LRC parsing, word timing, LRCLIB lookup, cache, cursor
    Audio/       System audio capture, FFT, beat and tempo detection
    Color/       Album art, palette extraction, artwork providers
    Layout/      Lyric styles, entrance and exit animations, lights, corner mode, cinema effects
    Mood/        Genre and audio based mood detection, automatic theme choice
    Theme/       Built-in themes and the theme store
    Background/  Player backgrounds library, keep-awake, player settings
    Control/     Play/pause/seek commands, the seek bar maths
  lyra-cli       A small command-line tool for poking at all of the above

LyraApp/         Everything that draws or shows a window
  Sources/LyraRender/   Metal renderer and shaders, overlay and player windows, settings window, fonts
  Sources/lyra-app/     The app's entry point and its debug flags

Tools/FontFactory/  Swift tool that writes the generated Lyra Originals font files
Fonts/              The font files the app ships with (and Fonts/drawn: the hand-drawn fonts' sources)
Packaging/          Info.plist template and the app icon generator
Scripts/            make-app.sh (build the app), install-fonts.sh (validate and install fonts)
Docs/               Guides, architecture notes and the font prompts
```

The rule that keeps this manageable: **decisions live in `LyraCore` as pure functions, drawing lives in
`LyraApp`.** A lyric style turns a lyrics frame into a list of `DrawItem`s (text, position, scale, color);
the renderer draws them. That is why almost everything can be tested without a screen. See
[Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) for the full picture.

## Conventions

- Swift 5 language mode, no third-party dependencies, macOS 14 as the minimum.
- New behavior comes with tests. Pure logic gets unit tests with synthetic data. Visual changes get a
  render test (see the `--render-*` flags of `lyra-app`) and a look at the result; say what you looked at in
  the pull request.
- **No song lyrics anywhere in the repository**: not in tests, docs, screenshots or sample files. Use
  invented sample lines. Lyric text belongs to its rights holders.
- Comments explain *why*, not what. Keep them short and true.
- Settings are saved as JSON and must decode tolerantly: a file from an older version, or one edited by
  hand, must still load. Use the `get(_:_:)` helper in the existing `init(from:)` implementations.
- Anything that talks to the network must be optional or clearly explained in
  [Docs/PRIVACY.md](Docs/PRIVACY.md), and must degrade quietly when offline.

## Adding things

**A theme.** Add an entry to the collection in `LyraCore/Sources/LyraCore/Theme/Theme.swift` using the
`make(...)` helper: an id (`builtin.<slug>`, never rename an existing one), a name, a lyric style id,
a font (a PostScript name), colors, lights and entrance/exit animations. Each theme uses its own font. Run
`swift test --package-path LyraCore`: the theme tests check ids, names, fonts and styles.

**A font.** Drop a `.ttf` into `Fonts/` and run `Scripts/install-fonts.sh Fonts/your-font.ttf` (it validates
the font: names, license, character coverage, metrics). Fonts must be your own work or carry a license
that allows redistribution, and must state it inside the file. New Lyra fonts appear in the app's font picker
automatically. Details in [Fonts/README.md](Fonts/README.md). To make fonts with an AI design tool, use the
prompts in [Docs/FontPrompts.md](Docs/FontPrompts.md).

**A lyric style.** Add a `LyricStyle` in `LyraCore/Sources/LyraCore/Layout/`, register it in
`LyricStyles.swift`, and add tests. Styles are pure: the same input gives the same output, with no hidden
state. Use an existing style such as `PopStyle` or `WaveStyle` as a template.

**A light effect or screen effect.** Pure parameter code goes in `LyraCore`, shader code in
`LyraApp/Sources/LyraRender/Metal/Shaders.swift`; keep Swift and Metal uniform structs in lockstep and
add a stride test.

## Taking screenshots safely

The app draws over your real screen, so be careful what you capture. Capture a single window rather than
the whole display (`screencapture -l <window id>`), or use the offscreen renders (`lyra-app --render-styles
out.png` and friends), which need no screen at all and show only invented text.

## Pull requests

Keep them focused. Describe what changed and why, and how you checked it. Fill in the template. A
maintainer will review; small fixes are usually merged quickly.
