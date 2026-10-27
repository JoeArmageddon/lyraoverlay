# Lyra Script

Original display typeface for the Lyra lyrics app. Regular only. File: `LyraScript-Regular.ttf`. Specimen: `specimen.png`.

## Design spec
- Construction: single-pass pointed-pen simulation. Every stroke is a spline centre-line; a round pen whose radius follows stroke direction (thin 30 units on upstrokes/horizontals, up to 86 on downstrokes) is swept and unioned. Everything is slanted 12 degrees about the join height. Lowercase is stretched wide for open loops and generous counters.
- Joins: every lowercase glyph starts at (0, 44) and ends at (advance, 44) with the same rising tangent, so any pair (including ff, fi, th, tt, ll) joins on one continuous hairline. No `calt` is needed or used, so the font looks the same in apps that ignore OpenType features.
- Capitals: larger, round-hand, modest entry/exit curls, do not connect. Numerals: upright old-style (0 1 2 at x-height, 3 4 5 7 9 descend, 6 8 ascend). Punctuation shares the same pen. Mood: romantic late-night ballad.

## Known weak spots (honest list)
- This is the weakest of the three. Letterforms are generated from hand-placed point lists, not drawn by a calligrapher; some shapes are clumsy: `v`/`w` read close to `u`/`uu`, `s`, `z` and `x` are awkward, `r` is short and `t` crossbar is thin.
- Caps are decent but several (E, F, G, M, N, Q, R) are plain rather than ornate, and the Y/J descenders are small.
- Join hairlines are long between narrow letters after stretching, giving a slightly loose rhythm; double-letter joins (`ee`, `oo`) show a visible hairline hop.
- Ascender/descender loops (l, k, b, h, f, g, y, j) are tight and can crowd neighbouring letters at 28 pt; f's descender loop overlaps the previous join.
- Hairlines (30 units) are thin for 28 pt over video; consider a glow. Digits and punctuation are not hand-tuned beyond automatic spacing. No stylistic alternates or `calt`.
- Accented capitals with swashes/lowercase accents sit close but were not individually tuned.

## Technical
- unitsPerEm 1000; ascender 800, descender -200, capHeight 700, xHeight 500, lineGap 0. hhea, OS/2 typo (800/-200/0) and win (900/250) agree; USE_TYPO_METRICS set. OS/2 version 4.
- TrueType quadratic outlines (glyf), 163 glyphs, full required character set (A-Z a-z 0-9, space, all listed punctuation, Latin accents, ae/AE, o-slash, sharp s). Outer contours clockwise, counters counter-clockwise, overlaps merged with skia-pathops.
- Kerning in GPOS `kern` (class-based; accented glyphs follow their base letter), generated automatically by measuring rasterised side profiles of every letter pair and tightening/loosening toward a reference spacing, with a minimum-gap guard.
- Built reproducibly: `/tmp/fontvenv/bin/python build_script.py` (fontTools, skia-pathops, pillow, numpy; seeded). Shared modules lyra_common.py, lyra_pipeline.py, print_skel.py sit beside the script.
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
