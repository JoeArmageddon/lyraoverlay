# Troubleshooting

First look at the menu bar icon: its menu shows the track, lyrics status and audio status.

## Nothing shows up
- Is the song playing in **Spotify** or **Music**? Other players are not supported.
- Did you allow **Automation** for Spotify/Music? Reset and re-ask: `tccutil reset AppleEvents app.lyra.mac`, then relaunch.
- Menu says lyrics unavailable: LRCLIB has no synced lyrics for that song.
- Run with diagnostics: `LYRA_DEBUG=1 dist/Lyra.app/Contents/MacOS/Lyra` prints what each player reports.

## Overlay missing over a full-screen app
Lyra draws over other apps' native full-screen Spaces. If it does not:
- Make sure **Show Lyrics** is on and a song is playing.
- Check that the Player window is not open with "hide overlay when open" on.
- Not supported: the **lock screen** (see [Spikes](../Spikes/README.md)).
- Untested: full-screen apps on a second display, and Mission Control transitions. Please report what you see
  with your macOS version.

## Lights don't pulse / permission prompt keeps returning
Lyra listens through a Core Audio tap and needs **System Audio Recording** only (not Screen Recording,
not the microphone).
- Menu says "no sound arriving": nothing is playing, or access is off. Use **Allow Audio Access…**, enable Lyra, restart Lyra.
- **The prompt comes back after every rebuild.** An ad-hoc signed build has a new identity each time, so macOS
  forgets the grant. Sign with a stable identity: `SIGN_IDENTITY="Apple Development: Name (TEAMID)" Scripts/make-app.sh`
  (see [BUILDING.md](BUILDING.md)). Running via `swift run` attributes the permission to your terminal app.
- Stuck grant: in System Settings → Privacy & Security → System Audio Recording, switch Lyra off and on (or remove it and relaunch to be asked again).

## Words early or late
Use **Sync Offset**. Lines are timed by LRCLIB; word timing inside a line is estimated.

## Auto theme does not switch
- Turn on **Settings → Themes → Match the music**.
- It applies from the next track, never after you chose a theme yourself for that song, and at most twice per song.
- Without a genre tag (Spotify) it relies on the cover art until audio is heard.

## Custom font not appearing
It must be `.ttf/.otf/.ttc/.otc` and not already installed on macOS or shipped with Lyra (the import reports why).
Fonts are stored in `~/Library/Application Support/Lyra/Fonts`.

## Player video background is black
Remove it and re-add; unsupported codecs will not play. H.264/HEVC `.mp4`/`.mov` work.

## After an update something looks wrong
Delete `~/Library/Application Support/Lyra/settings.json`.

## Still stuck
Open an issue with your macOS version, Lyra version (`CFBundleShortVersionString`), and the output of
`LYRA_DEBUG=1`. Do not include lyrics text.
