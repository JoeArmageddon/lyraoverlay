# Privacy

Lyra has no account, no telemetry and no analytics.

## What it reads on your Mac
| What | How | Why |
|---|---|---|
| Current track, position, artwork, genre | AppleScript to Spotify/Music (Automation permission) | Show lyrics |
| System audio output | Core Audio process tap (System Audio Recording permission) | Beat-reactive lights and Match the music |

Audio is analyzed in memory into a few numbers (bass, beat, tempo, brightness). **It is never recorded,
stored or sent anywhere, and the microphone is never used.**

## What it sends over the network
1. **LRCLIB** (`lrclib.net`): artist, title, album and duration, to fetch lyrics.
2. **Apple iTunes Search** (optional): artist and album, only for tracks whose cover the player cannot supply
   (streamed Apple Music). Only matching results are used, and only images from Apple's image host are
   downloaded. Disable in Settings → General → "Look up missing covers online".

Nothing else. Both requests go over HTTPS with no identifiers beyond what any HTTP client sends.

## What it stores (locally)
`~/Library/Application Support/Lyra/`: settings, themes, imported fonts and backgrounds, and a cache of
downloaded lyrics. Delete the folder to remove everything. Lyric text is copyrighted by its owners; the cache
is for your personal use and is not redistributed.
