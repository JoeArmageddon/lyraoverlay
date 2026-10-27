# Lyra User Guide

Lyra lives in two places: a **menu bar icon** (♪) and a regular **Dock app** with a Player window.
Settings open with **⌘,**.

## Contents
1. [The menu bar menu](#the-menu-bar-menu)
2. [Desktop overlay](#desktop-overlay)
3. [Corner mode](#corner-mode)
4. [Player window](#player-window)
5. [Styles and animations](#styles-and-animations)
6. [Fonts](#fonts)
7. [Themes](#themes)
8. [Match the music](#match-the-music)
9. [Edge lighting](#edge-lighting)
10. [Sync offset](#sync-offset)
11. [Files and resetting](#files-and-resetting)

## The menu bar menu

Top lines show the current track, the lyrics status and the audio status. Below: **Open Player**,
**Full Screen Player**, **Settings…**, a **Theme** submenu, **Add Custom Font…**, then toggles for
**Show Lyrics**, **Edge Lighting**, **Corner Mode (⌃⌥L)**, **Corner Position** and **Match Album Colors**,
and **Sync Offset**. If audio is not arriving, **Allow Audio Access…** opens the right System Settings page.

## Desktop overlay

Lyrics are drawn across each display, click-through, with the current line highlighted word by word and
the next line previewed. It is also shown over other apps' native full-screen Spaces. Pick the window level
(floating, desktop, and so on) and whether all displays are used in **Settings → General**. While the
Player window is open the overlay steps aside (switchable in Settings → Player).

## Corner mode

A small caption card instead of full-screen lyrics. Toggle with **⌃⌥L** from any app (if another app owns
that shortcut, use the menu item). In Settings → General choose the corner, font size, card width, margin,
whether to show the next line, and the backdrop and its opacity. Corner mode always uses the Karaoke Line
style and turns edge lights off.

## Player window

Open from the menu or the Dock icon. Choose a **background** (built-in gradient, or your own picture or
video via the add button or by dropping a file; videos loop muted). Adjust dim and blur. The **border glow**
takes its gradient from the background's colors. The card shows the track and cover; the **progress bar**
scrubs the song (the lyrics jump with it); previous, play/pause and next sit below.
**Full screen** uses native macOS full screen. **Keep Mac awake** holds a power assertion while the window is
open and music is playing, and releases it afterward.

**Film look** (Settings → Player): letterbox (2.39:1, 2.00:1, 1.85:1), vignette, grain, beat flare.

## Styles and animations

| Style | Look |
|---|---|
| Karaoke Line | Current line, next line previewed |
| Scrolling List | A column of lines scrolling past |
| Typewriter | Words typed in |
| Pop | Words pop as sung |
| Wave | Words ride a wave |
| Word Focus | One word in focus |
| Cinematic | Each line is a shot: hero word, supporting words, camera moves, whip/zoom/cut transitions |

Settings → Animation sets how lines enter (12 kinds) and leave (5 kinds), duration and stagger.

## Fonts

The font picker previews every font in its own letters, grouped: **My Fonts**, **Lyra Originals**,
**Lyra Hand-Drawn**, system groups, and **More System Fonts** (novelty faces, never used by themes).

**Add your own:** click **Add Custom Font…** (menu bar menu or the picker), or drop font files on the picker.
Supported: `.ttf`, `.otf`, `.ttc`, `.otc`. Several at once is fine; duplicates of fonts that ship with Lyra or
macOS are reported and skipped. Fonts are copied to `~/Library/Application Support/Lyra/Fonts`. Right-click a
font in My Fonts for **Show in Finder** or **Remove…**. Respect each font's license.

Letter spacing, italic and letter case (as written, UPPER, lower, Title) are adjustable separately.
To design fonts, see [FontPrompts.md](FontPrompts.md) and [../Fonts/README.md](../Fonts/README.md).

## Themes

A theme bundles typeface, style, colors, glow, animation and lighting. Pick one in Settings → Themes or the
menu. **Save as theme** stores yours; themes can be exported to and imported from a JSON file.
Sync offset is not part of a theme.

## Match the music

Settings → Themes → **Match the music** (off by default). When on, Lyra restyles for each song:

1. **At track start** it uses the genre tag (Apple Music provides one; Spotify does not) and the cover art.
2. **After about 12 seconds** of audio it may refine the choice if the sound clearly points elsewhere
   (needs System Audio Recording).

It picks one of 12 moods (energetic, aggressive, party, romantic, chill, dreamy, melancholic, dark, epic,
retro, acoustic, playful) and maps it to a theme. The same song always gets the same theme. You can pin a theme
per mood, or restrict it to favorite themes. It changes at most twice per song, never near the end, and
**stops as soon as you pick a theme or edit the look yourself, until the next song.**
Enabling it mid-song takes effect on the next track. The status line shows what it saw
(for example "Rock · 128 BPM → Energetic → Pulse").

## Edge lighting

A rim glow that pulses on beats and swells with bass. Set intensity, thickness and colors, or follow the
album art. Without audio permission it breathes slowly instead. Lights draw only in the full-screen overlay,
not in corner mode.

## Sync offset

If words run early or late, adjust **Sync Offset** (menu or Settings → Lyrics). Positive shows lyrics later.

## Files and resetting

All data lives in `~/Library/Application Support/Lyra/`: `settings.json` (safe to edit; invalid values fall
back to defaults), `Themes/`, `Fonts/`, `Backgrounds/`, `LyricsCache/`. Delete `settings.json` to reset.
