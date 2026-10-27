# Third-party notices

Lyra has no third-party code dependencies: it is written in Swift against Apple's system frameworks.
This file lists what it does use or talk to, and under what terms. It is a plain summary, not legal
advice; read the linked terms if you plan to distribute or build on this project.

## Services Lyra talks to

| Service | Used for | What is sent | Notes |
| --- | --- | --- | --- |
| [LRCLIB](https://lrclib.net) | Finding synced lyrics | Artist, title, album and length of the playing track | A free, community-run lyrics database. The lyric text belongs to its rights holders. Lyra keeps what it finds in a cache on your own Mac for your own use and does not redistribute it. Please read LRCLIB's own terms before building a service on top of it. |
| Apple iTunes Search (itunes.apple.com) | Cover art for tracks the music app cannot give a cover for (streamed Apple Music tracks) | Artist and album name (or title) | Optional: Settings → General → "Look up missing covers online". The artwork belongs to its rights holders and is only shown for the track that is playing. Apple's terms for the iTunes Search API apply. |

Nothing else leaves your Mac. There is no account, analytics or telemetry.

## Apple frameworks

Lyra uses AppKit, SwiftUI, Metal, Core Text, Core Audio, ScreenCaptureKit (an optional audio capture
fallback), Accelerate, AVFoundation, ImageIO, IOKit (to keep the Mac awake) and Carbon's hot key API
(for the global shortcut). These are part of macOS and are used under Apple's developer terms.

## Fonts

- **Fonts in this repository** (`Fonts/`): the Lyra Originals and the hand-drawn Lyra fonts are licensed
  under the [SIL Open Font License 1.1](https://openfontlicense.org). Each font file carries its own
  copyright and license notice in its name table; see `Fonts/LICENSE.txt` and `Fonts/README.md`.
- **System fonts** such as Avenir Next, Didot or Menlo are referenced by name and used from your
  Mac. They are not bundled with or redistributed by Lyra, and remain under Apple's license terms.
- **Fonts you import** stay yours. Lyra copies them into your own `~/Library/Application Support/Lyra/Fonts`
  and does not upload or redistribute them. Check the license of any font before you share a theme
  that uses it.

## Trademarks

Spotify and Apple Music are trademarks of their respective owners. Lyra is an independent project and
is not affiliated with, endorsed by or sponsored by them.
