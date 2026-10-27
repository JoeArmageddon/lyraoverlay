# Font prompts for AI design tools

Lyra ships eight original fonts that it generates itself, plus hand-drawn ones made from these prompts
(see `Fonts/README.md`). Some styles are
organic and hand-drawn, which code can't do well: scripts, brushes, tags, blackletter, wood type,
handwriting, bubble letters. These prompts are for asking an AI design tool
to make those fonts as real font files.

## How to use

1. Open one file from `Docs/font-prompts/ready/` (for example `Lyra-Script.txt`).
2. Paste the **whole file** into your design tool as one message. Each file is complete on its own:
   the shared requirements (file format, names, metrics, character set, quality bar, license) followed
   by that font's style description.
3. Ask it to build the font and give you the `.ttf`. If it can only produce SVG glyphs and a script,
   the prompt already tells it how to hand those over; run the script it gives you.
4. Check the specimen it produces. If a pair or glyph looks weak, tell it which and ask for a fix.
5. Add the font. To ship it with Lyra, put the `.ttf` (and the build script it gives you) in
   `Fonts/drawn/<Name>/` and run `Scripts/install-fonts.sh`, which audits it and copies it into `Fonts/`;
   it then appears in the picker with no code change (add a theme for it in `Theme.swift`; the tests ask for one).
   To use it on your own Mac only, click **Add Custom Font…** at the top of the font picker, or drag
   the file onto the picker. It is listed under **My Fonts**.

## The prompts

| File | Style | Good for |
| --- | --- | --- |
| `Lyra-Script.txt` | Elegant connected script | ballads, romance |
| `Lyra-Brush.txt` | Dry brush marker | punk, rock, hip-hop |
| `Lyra-Tag.txt` | Street tag lettering | hip-hop, urban |
| `Lyra-Gothic.txt` | Modern blackletter | metal, tattoo style |
| `Lyra-Saloon.txt` | Wild-west wood type | country, folk |
| `Lyra-Hand.txt` | Casual handwriting | indie, acoustic |
| `Lyra-Bubble.txt` | Inflated bubble letters | pop, kids |
| `Lyra-Retro.txt` | 80s sci-fi italic | synthwave |
| `Lyra-Forge.txt` | Heavy metal, jagged | metal |
| `Lyra-Blade.txt` | Razor-sharp italic | action, EDM |
| `Lyra-Stencil.txt` | Military stencil | rock, industrial |
| `Lyra-Circuit.txt` | Techno monoline | electronic |
| `Lyra-Neon.txt` | Neon tube | retro, pop |
| `Lyra-Pixel.txt` | Chunky bitmap | chiptune, games |
| `Lyra-Thorn.txt` | Gothic barbed caps | dark pop, goth |

All fifteen prompts have been used: each result is a `Lyra*` font in `Fonts/` (see `Fonts/README.md` for the
list). The last seven (Forge, Blade, Stencil, Circuit, Neon, Pixel, Thorn) are drawn alternatives to the
generated Lyra Originals, so their fonts are named "... Drawn" (for example `LyraForgeDrawn-Regular`) to
avoid clashing with the originals' PostScript names. Keep that rule for new variants: a PostScript name must be unique.

## Changing the prompts

The shared requirements are in `Docs/font-prompts/common.txt` and the style descriptions in
`Docs/font-prompts/briefs.txt` (one `=== Name | Title ===` block each). After editing either, run:

```bash
Docs/font-prompts/build.sh
```

to rebuild the files in `ready/`.

## Licensing note

The prompts ask for wholly original designs under the SIL Open Font License. Check that whatever
you get back really is original before shipping it with an app: AI tools can echo existing designs.
