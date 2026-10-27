# Lyra Bubble

File: `LyraBubble-Regular.ttf` (TrueType, quadratic outlines, 1000 upm). Specimen: `specimen.png`. Rebuild: `/tmp/fontvenv/bin/python build_bubble.py` (needs fontTools, skia-pathops, numpy, pillow; deterministic, seeded).

## Design spec
Inflated bubble letters: round-capped, round-joined monoline strokes (caps 148 units, lowercase 116), capsule-shaped bowls, big round dots. Playful bounce: each glyph gets a small deterministic vertical offset (+-10) and tilt (+-1.8 deg) hashed from its character. Lowercase is real (single-storey a and g, tailed l).

Common: ascender 800, descender -200, cap height 700, hhea / OS/2 typo (800/-200/0) and win (900/250) agree, USE_TYPO_METRICS set. Glyphs are built from monoline skeletons stroked with skia-pathops, unioned (no overlaps), clockwise outers. Spacing is optical (computed from outline profiles) and kerning is a GPOS `kern` feature of auto-computed glyph pairs that enforces a minimum clearance (no collisions in the checked pairs such as A V, T o, L T, r a, f i, y o, W a, P .). Full required character set present; every glyph non-empty (checked by reload with fontTools).

## Known weak spots
- Puffiness comes only from heavy round strokes; there is no true variable-width swelling of stems, so it reads as a fat rounded monoline more than a balloon.
- Lowercase e and a counters are small at 28 pt (x-height is fixed at 500 with weight 116); they stay open but are tight.
- ß, & and @ are rough constructions; ß in particular is not a refined shape.
- Accent marks are simple strokes and sit close to heavy letters; ì/í/î/ï are dotless-i plus mark.
- Bounce tilt can look slightly uneven on single-glyph UI use.
- Not tested in Font Book/Core Text here (only fontTools and FreeType).

## License
SIL Open Font License 1.1 (https://openfontlicense.org). Copyright 2026 The Lyra Project Authors.

PREAMBLE: The goals of the Open Font License (OFL) are to stimulate worldwide development of collaborative font projects, to support the font creation efforts of academic and linguistic communities, and to provide a free and open framework in which fonts may be shared and improved in partnership with others.
The OFL allows the licensed fonts to be used, studied, modified and redistributed freely as long as they are not sold by themselves. The fonts, including any derivative works, can be bundled, embedded, redistributed and/or sold with any software provided that any reserved names are not used by derivative works. The fonts and derivatives, however, cannot be released under any other type of license. The requirement for fonts to remain under this license does not apply to any document created using the fonts or their derivatives.

PERMISSION & CONDITIONS: Permission is hereby granted, free of charge, to any person obtaining a copy of the Font Software, to use, study, copy, merge, embed, modify, redistribute, and sell modified and unmodified copies of the Font Software, subject to: 1) Neither the Font Software nor any of its individual components, in Original or Modified Versions, may be sold by itself. 2) Original or Modified Versions of the Font Software may be bundled, redistributed and/or sold with any software, provided that each copy contains the above copyright notice and this license. 3) No Modified Version of the Font Software may use the Reserved Font Name(s) unless explicit written permission is granted by the corresponding Copyright Holder. 4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font Software shall not be used to promote, endorse or advertise any Modified Version, except to acknowledge the contribution(s) of the Copyright Holder(s) and the Author(s) or with their explicit written permission. 5) The Font Software, modified or unmodified, in part or in whole, must be distributed entirely under this license, and must not be distributed under any other license.

TERMINATION: This license becomes null and void if any of the above conditions are not met.

DISCLAIMER: THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM OTHER DEALINGS IN THE FONT SOFTWARE.
