# Lyra Brush

Original display typeface for the Lyra lyrics app. Regular only. File: `LyraBrush-Regular.ttf`. Specimen: `specimen.png`.

## Design spec
- Construction: flat chisel nib (138 long, 36 thick, angled 34 degrees) swept along upright skeleton strokes, giving thick verticals, thinner horizontals and thin diagonals along the nib angle. Slight 6 degree lean, tight spacing, per-stroke random wobble (rotation +/-1.6 degrees, offset +/-5) so the baseline feels uneven inside each glyph while metrics stay on the baseline.
- Texture: edges roughened with seeded two-scale noise; one or two thin tapered dry-brush slits per long stroke, entering from stroke tails. Full stops and dots are fat, round (radius 76).
- Bold capitals and lowercase, lining numerals, punctuation matching.

## Known weak spots (honest list)
- Dry-brush slits are hairline (about 5-7 units): they vanish at 28 pt and read as faint scratches at 96 pt; they could be bolder.
- Roughening is modest; the font reads as rough marker rather than heavy dirty brush. No overlapping ink-splatter or ragged stroke starts.
- Accents on lowercase are thin (chisel runs along the nib angle) and some acute/grave are faint; tilde and ring are small.
- Bracket, brace, backslash and slash glyphs are thin and look rough; `@`, `&`, `$`, `%` are simple constructions, `ß` is plain.
- Many outline points from roughening make the file larger (about 140 KB).

## Technical
- unitsPerEm 1000; ascender 800, descender -200, capHeight 700, xHeight 500, lineGap 0. hhea, OS/2 typo (800/-200/0) and win (900/250) agree; USE_TYPO_METRICS set. OS/2 version 4.
- TrueType quadratic outlines (glyf), 163 glyphs, full required character set (A-Z a-z 0-9, space, all listed punctuation, Latin accents, ae/AE, o-slash, sharp s). Outer contours clockwise, counters counter-clockwise, overlaps merged with skia-pathops.
- Kerning in GPOS `kern` (class-based; accented glyphs follow their base letter), generated automatically by measuring rasterised side profiles of every letter pair and tightening/loosening toward a reference spacing, with a minimum-gap guard.
- Built reproducibly: `/tmp/fontvenv/bin/python build_brush.py` (fontTools, skia-pathops, pillow, numpy; seeded). Shared modules lyra_common.py, lyra_pipeline.py, print_skel.py sit beside the script.
- Outlines are built from a skeleton (centre-lines) plus a pen model, not hand-drawn Beziers; curves are polygons converted to quadratic B-spline contours (smooth vertices become off-curve points, sharp corners stay on-curve). Extrema points are therefore not guaranteed on every curve, and files are larger than hand-optimised fonts.
- Not tested in Font Book / Core Text / Safari here; the specimen is rendered from the actual .ttf outlines by Pillow, not by Core Text. Only fontTools verification was run.

## License

Copyright 2026 The Lyra Project. Original design.

This Font Software is licensed under the SIL Open Font License, Version 1.1.
This license is copied below, and is also available with a FAQ at: https://openfontlicense.org

-----------------------------------------------------------
SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007
-----------------------------------------------------------

PREAMBLE
The goals of the Open Font License (OFL) are to stimulate worldwide development of collaborative font projects, to support the font creation efforts of academic and linguistic communities, and to provide a free and open framework in which fonts may be shared and improved in partnership with others.

The OFL allows the licensed fonts to be used, studied, modified and redistributed freely as long as they are not sold by themselves. The fonts, including any derivative works, can be bundled, embedded, redistributed and/or sold with any software provided that any reserved names are not used by derivative works. The fonts and derivatives, however, cannot be released under any other type of license. The requirement for fonts to remain under this license does not apply to any document created using the fonts or their derivatives.

DEFINITIONS
"Font Software" refers to the set of files released by the Copyright Holder(s) under this license and clearly marked as such. This may include source files, build scripts and documentation.

"Reserved Font Name" refers to any names specified as such after the copyright statement(s).

"Original Version" refers to the collection of Font Software components as distributed by the Copyright Holder(s).

"Modified Version" refers to any derivative made by adding to, deleting, or substituting -- in part or in whole -- any of the components of the Original Version, by changing formats or by porting the Font Software to a new environment.

"Author" refers to any designer, engineer, programmer, technical writer or other person who contributed to the Font Software.

PERMISSION & CONDITIONS
Permission is hereby granted, free of charge, to any person obtaining a copy of the Font Software, to use, study, copy, merge, embed, modify, redistribute, and sell modified and unmodified copies of the Font Software, subject to the following conditions:

1) Neither the Font Software nor any of its individual components, in Original or Modified Versions, may be sold by itself.

2) Original or Modified Versions of the Font Software may be bundled, redistributed and/or sold with any software, provided that each copy contains the above copyright notice and this license. These can be included either as stand-alone text files, human-readable headers or in the appropriate machine-readable metadata fields within text or binary files as long as those fields can be easily viewed by the user.

3) No Modified Version of the Font Software may use the Reserved Font Name(s) unless explicit written permission is granted by the corresponding Copyright Holder. This restriction only applies to the primary font name as presented to the users.

4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font Software shall not be used to promote, endorse or advertise any Modified Version, except to acknowledge the contribution(s) of the Copyright Holder(s) and the Author(s) or with their explicit written permission.

5) The Font Software, modified or unmodified, in part or in whole, must be distributed entirely under this license, and must not be distributed under any other license. The requirement for fonts to remain under this license does not apply to any document created using the Font Software.

TERMINATION
This license becomes null and void if any of the above conditions are not met.

DISCLAIMER
THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM OTHER DEALINGS IN THE FONT SOFTWARE.
