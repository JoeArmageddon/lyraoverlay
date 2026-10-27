# Lyra Stencil Drawn

Original display face for the Lyra app, drawn procedurally. Single weight, Regular; PostScript name `LyraStencilDrawn-Regular`; file `LyraStencilDrawn-Regular.ttf`.

## Build

`/tmp/fontvenv/bin/python build_stencil.py` regenerates the .ttf and specimen.png (needs fontTools, skia-pathops, Pillow, numpy). `lyrakit.py`, `lyrabuild.py`, `lyraskel.py` are shared helper modules copied into this folder.

## Design spec

Heavy military stencil. Constant 118 unit monoline pen, rounded-square corners (centre-line radius 80), square butt terminals, wide proportions. Bridges are 34 unit gaps placed by rule: A at the apex, B/D/P/R in the right wall of each bowl, O/Q/0 at top and bottom centre, 4 on the diagonal, 6/9/8 in the loop wall. Lowercase = small caps at 560 (80 percent of cap height; OS/2 sxHeight is 560, not the 500 in the brief).

Metrics: UPM 1000, ascender 800, descender -200, cap height 700, lineGap 0; hhea, OS/2 typo and OS/2 win metrics (900/250) agree, USE_TYPO_METRICS set. Quadratic TrueType outlines, outer contours clockwise, overlaps merged. Full required character set (A-Z a-z 0-9, punctuation, Latin accents, Æ æ Ø ø ß) plus a dotless-i helper glyph; kerning in GPOS `kern` (class pairs).

## Weak spots (honest list)

- Capital I, lowercase l and 1 are similar heavy stems (l has a foot, 1 has a flag and base) - distinguishable but close at 28 pt.
- Bridges are only applied to the listed letters; Æ, ß, @, & have counters without bridges.
- O/0 are separated only by narrower width and no slash; the O vs 0 difference is weak.
- B bridges look slightly busy at small sizes.
- Accents are small and sit tight above caps (to about y=830).
- Heavy weight means counters in B, 8, & and @ fill in under a strong glow.
- Polyline-smoothed quadratic outlines, no hand-placed extrema; no hinting.
- Auto kerning judged visually only.

## License

Copyright (c) 2026, Lyra (generated glyph outlines; see build script).

This Font Software is licensed under the SIL Open Font License, Version 1.1.
This license is copied below, and is also available with a FAQ at:
https://openfontlicense.org

-----------------------------------------------------------
SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007
-----------------------------------------------------------

PREAMBLE
The goals of the Open Font License (OFL) are to stimulate worldwide
development of collaborative font projects, to support the font creation
efforts of academic and linguistic communities, and to provide a free and
open framework in which fonts may be shared and improved in partnership
with others.

The OFL allows the licensed fonts to be used, studied, modified and
redistributed freely as long as they are not sold by themselves. The
fonts, including any derivative works, can be bundled, embedded,
redistributed and/or sold with any software provided that any reserved
names are not used by derivative works. The fonts and derivatives,
however, cannot be released under any other type of license. The
requirement for fonts to remain under this license does not apply
to any document created using the fonts or their derivatives.

DEFINITIONS
"Font Software" refers to the set of files released by the Copyright
Holder(s) under this license and clearly marked as such. This may
include source files, build scripts and documentation.

"Reserved Font Name" refers to any names specified as such after the
copyright statement(s).

"Original Version" refers to the collection of Font Software components as
distributed by the Copyright Holder(s).

"Modified Version" refers to any derivative made by adding to, deleting,
or substituting -- in part or in whole -- any of the components of the
Original Version, by changing formats or by porting the Font Software to a
new environment.

"Author" refers to any designer, engineer, programmer, technical
writer or other person who contributed to the Font Software.

PERMISSION & CONDITIONS
Permission is hereby granted, free of charge, to any person obtaining
a copy of the Font Software, to use, study, copy, merge, embed, modify,
redistribute, and sell modified and unmodified copies of the Font
Software, subject to the following conditions:

1) Neither the Font Software nor any of its individual components,
in Original or Modified Versions, may be sold by itself.

2) Original or Modified Versions of the Font Software may be bundled,
redistributed and/or sold with any software, provided that each copy
contains the above copyright notice and this license. These can be
included either as stand-alone text files, human-readable headers or
in the appropriate machine-readable metadata fields within text or
binary files as long as those fields can be easily viewed by the user.

3) No Modified Version of the Font Software may use the Reserved Font
Name(s) unless explicit written permission is granted by the corresponding
Copyright Holder. This restriction only applies to the primary font name as
presented to the users.

4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font
Software shall not be used to promote, endorse or advertise any
Modified Version, except to acknowledge the contribution(s) of the
Copyright Holder(s) and the Author(s) or with their explicit written
permission.

5) The Font Software, modified or unmodified, in part or in whole,
must be distributed entirely under this license, and must not be
distributed under any other license. The requirement for fonts to
remain under this license does not apply to any document created
using the Font Software.

TERMINATION
This license becomes null and void if any of the above conditions are
not met.

DISCLAIMER
THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT
OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE
COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL
DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM
OTHER DEALINGS IN THE FONT SOFTWARE.
