# Lyra Blade Drawn

Original display face for the Lyra app, drawn procedurally. Single weight, Regular; PostScript name `LyraBladeDrawn-Regular`; file `LyraBladeDrawn-Regular.ttf`.

## Build

`/tmp/fontvenv/bin/python build_blade.py` regenerates the .ttf and specimen.png (needs fontTools, skia-pathops, Pillow, numpy). `lyrakit.py`, `lyrabuild.py`, `lyraskel.py` are shared helper modules copied into this folder.

## Design spec

Razor sharp italic. Centre-line skeletons are stroked with a simulated flat broad-nib (nib angle 14 deg; stroke width = 11 + 73*|sin(angle-nib)|^1.35 units, so verticals are about 84 and horizontals about 25), free stroke ends taper over up to 190 units to a ~2 unit needle tip, joins are mitred, then the outline is sheared 16 degrees. Cap height 700, lowercase = small caps at 500, narrow-medium widths, round letters built from rounded rectangles with proportional corner radii. Original construction, nothing traced.

Metrics: UPM 1000, ascender 800, descender -200, cap height 700, lineGap 0; hhea, OS/2 typo and OS/2 win metrics (900/250) agree, USE_TYPO_METRICS set. Quadratic TrueType outlines, outer contours clockwise, overlaps merged. Full required character set (A-Z a-z 0-9, punctuation, Latin accents, Æ æ Ø ø ß) plus a dotless-i helper glyph; kerning in GPOS `kern` (class pairs).

## Weak spots (honest list)

- Numeral 3 and 2 have a flat top and read slightly like Z/J at 28 pt.
- Lowercase l (blade-footed stem) and capital I (plain spindle) are distinct, but I is very thin in the middle of long words.
- Thin horizontals (about 25 units) get weak at 28 pt over busy video.
- Accent marks are small and light; punctuation (quotes, dots) is small relative to the letters.
- Ampersand, @, % and braces are rough constructions; ß is only a plain build.
- Outlines are approximated by fine polylines smoothed to quadratic B-splines, not hand-placed extrema points; overlap check flags & } ß as possible touching contours.
- Kerning is auto-computed from outline profiles (about 4800 class pairs) and was only judged visually on the specimen.
- No hinting.

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
