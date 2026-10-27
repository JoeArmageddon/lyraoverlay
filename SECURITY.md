# Security policy

## Reporting a vulnerability

Please do not open a public issue for a security problem. Use GitHub's private reporting instead:
on the repository page choose **Security → Report a vulnerability**. Include what you found, how to
reproduce it, and which version of Lyra and macOS you were using. You will get an answer as soon as a
maintainer can look at it.

## What Lyra can see and do

Knowing the boundaries makes problems easier to judge:

- **Network:** Lyra sends the artist, title, album and length of the playing track to
  [LRCLIB](https://lrclib.net) to find lyrics, and, only for tracks whose cover the player can't
  provide, the artist and album name to Apple's public iTunes Search. Both are described in
  [Docs/PRIVACY.md](Docs/PRIVACY.md). Lyra has no account system, analytics or telemetry.
- **Audio:** Lyra analyzes the audio that is playing on your Mac to drive the edge lights. The audio is
  analyzed in memory and is never recorded, stored or sent anywhere. It never uses the microphone.
- **Automation:** Lyra asks Spotify and Music for the current track and sends play/pause, previous, next
  and seek commands, through AppleScript. macOS asks for your permission once per app.
- **Files:** Lyra writes settings, themes, imported fonts, imported backgrounds and a lyrics cache under
  `~/Library/Application Support/Lyra`. It reads only the files you choose to import.

## Supported versions

Security fixes go into the latest release.
