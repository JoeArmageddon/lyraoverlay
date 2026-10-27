# Lyra Retro

File: `LyraRetro-Regular.ttf` (TrueType, quadratic outlines, 1000 upm). Specimen: `specimen.png`. Rebuild: `/tmp/fontvenv/bin/python build_retro.py` (needs fontTools, skia-pathops, numpy, pillow; deterministic, seeded).

## Design spec
Wide 80s synthwave italic: extended proportions, 14 degree forward slant, stroke 128, round outer corners (radius 24 via morphological opening) with sharp inner corners, squarish rounded geometry, and a 30-unit horizontal slit (y 184-214) cut through every glyph at the same height so it forms a continuous line across words. Lowercase is small caps at 78% (546 units), so sxHeight is set to 546 rather than 500. Crossbars (A, 4, etc.) are placed above the slit; E/F/B/8 stay distinguishable.

Common: ascender 800, descender -200, cap height 700, hhea / OS/2 typo (800/-200/0) and win (900/250) agree, USE_TYPO_METRICS set. Glyphs are built from monoline skeletons stroked with skia-pathops, unioned (no overlaps), clockwise outers. Spacing is optical (computed from outline profiles) and kerning is a GPOS `kern` feature of auto-computed glyph pairs that enforces a minimum clearance (no collisions in the checked pairs such as A V, T o, L T, r a, f i, y o, W a, P .). Full required character set present; every glyph non-empty (checked by reload with fontTools).

## Known weak spots
- Lowercase are small caps: the lowercase i has no dot and l is a small L; xHeight is 546 not 500.
- At 28 pt the 30-unit slit is under 1 px and may vanish or alias.
- Extended widths make long lines wide.
- Italic angle is in the post table but the style is named Regular (no italic flag).
- Punctuation (&, @, %, braces, backtick) is functional but not refined; quotes are short straight bars.
- Not tested in Font Book/Core Text here.

## License
SIL Open Font License 1.1 (https://openfontlicense.org). Copyright 2026 The Lyra Project Authors.

PREAMBLE: The goals of the Open Font License (OFL) are to stimulate worldwide development of collaborative font projects, to support the font creation efforts of academic and linguistic communities, and to provide a free and open framework in which fonts may be shared and improved in partnership with others.
The OFL allows the licensed fonts to be used, studied, modified and redistributed freely as long as they are not sold by themselves. The fonts, including any derivative works, can be bundled, embedded, redistributed and/or sold with any software provided that any reserved names are not used by derivative works. The fonts and derivatives, however, cannot be released under any other type of license. The requirement for fonts to remain under this license does not apply to any document created using the fonts or their derivatives.

PERMISSION & CONDITIONS: Permission is hereby granted, free of charge, to any person obtaining a copy of the Font Software, to use, study, copy, merge, embed, modify, redistribute, and sell modified and unmodified copies of the Font Software, subject to: 1) Neither the Font Software nor any of its individual components, in Original or Modified Versions, may be sold by itself. 2) Original or Modified Versions of the Font Software may be bundled, redistributed and/or sold with any software, provided that each copy contains the above copyright notice and this license. 3) No Modified Version of the Font Software may use the Reserved Font Name(s) unless explicit written permission is granted by the corresponding Copyright Holder. 4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font Software shall not be used to promote, endorse or advertise any Modified Version, except to acknowledge the contribution(s) of the Copyright Holder(s) and the Author(s) or with their explicit written permission. 5) The Font Software, modified or unmodified, in part or in whole, must be distributed entirely under this license, and must not be distributed under any other license.

TERMINATION: This license becomes null and void if any of the above conditions are not met.

DISCLAIMER: THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM OTHER DEALINGS IN THE FONT SOFTWARE.
