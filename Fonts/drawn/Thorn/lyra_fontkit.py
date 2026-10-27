"""Shared helpers for the Lyra *Drawn font generators (outline cleanup, TTF assembly,
auto-kerning from rendered ink profiles, specimen rendering, verification).
Original code; SIL OFL 1.1 for the fonts it generates."""
import math, os
import numpy as np
import pathops
from fontTools.agl import UV2AGL
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.areaPen import AreaPen
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.reverseContourPen import ReverseContourPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.misc.bezierTools import splitCubicAtT, splitQuadraticAtT
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont

UPM = 1000
LICENSE_TEXT = """Copyright (c) 2026 Lyra Fonts Project (Reserved Font Name "Lyra").

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
"""

# ---------------------------------------------------------------- character set
BASIC = [chr(c) for c in range(0x20, 0x7F)]
PUNCT_EXTRA = list("‘’“”–—…¡¿")
ACCENT_SPEC = {  # char: (base, mark)
 'À':('A','grave'),'Á':('A','acute'),'Â':('A','circ'),'Ã':('A','tilde'),'Ä':('A','diaer'),'Å':('A','ring'),
 'Ç':('C','cedilla'),'È':('E','grave'),'É':('E','acute'),'Ê':('E','circ'),'Ë':('E','diaer'),
 'Ì':('I','grave'),'Í':('I','acute'),'Î':('I','circ'),'Ï':('I','diaer'),'Ñ':('N','tilde'),
 'Ò':('O','grave'),'Ó':('O','acute'),'Ô':('O','circ'),'Õ':('O','tilde'),'Ö':('O','diaer'),
 'Ù':('U','grave'),'Ú':('U','acute'),'Û':('U','circ'),'Ü':('U','diaer'),'Ý':('Y','acute'),
 'à':('a','grave'),'á':('a','acute'),'â':('a','circ'),'ã':('a','tilde'),'ä':('a','diaer'),'å':('a','ring'),
 'ç':('c','cedilla'),'è':('e','grave'),'é':('e','acute'),'ê':('e','circ'),'ë':('e','diaer'),
 'ì':('ı','grave'),'í':('ı','acute'),'î':('ı','circ'),'ï':('ı','diaer'),'ñ':('n','tilde'),
 'ò':('o','grave'),'ó':('o','acute'),'ô':('o','circ'),'õ':('o','tilde'),'ö':('o','diaer'),
 'ù':('u','grave'),'ú':('u','acute'),'û':('u','circ'),'ü':('u','diaer'),'ý':('y','acute'),'ÿ':('y','diaer'),
}
SPECIAL = list("ÆÑØæøß") + ['ı']
REQUIRED = BASIC + PUNCT_EXTRA + list(ACCENT_SPEC) + list("ÆØæøß")
# (ı is internal, base for ì í î ï)

def gname(ch):
    cp = ord(ch)
    if cp == 0x20: return 'space'
    n = UV2AGL.get(cp)
    if n and n.isascii(): return n
    return 'uni%04X' % cp

# ---------------------------------------------------------------- path helpers
def new_path(): return pathops.Path()

def copy_path(p):
    q = pathops.Path(); q.addPath(p); return q

def union(*paths):
    out = pathops.Path()
    for p in paths:
        if p is not None: out.addPath(p)
    out.simplify(fix_winding=True, keep_starting_points=False)
    return out

def bounds(p):
    b = p.bounds
    return b  # xmin,ymin,xmax,ymax

def translate(p, dx, dy):
    return p.transform(1, 0, 0, 1, dx, dy)

def affine(p, a, b, c, d, e, f):
    """x' = a*x + c*y + e ; y' = b*x + d*y + f"""
    return p.transform(a, b, c, d, e, f)

# ---------------------------------------------------------------- outline -> TrueType glyph
def _split_contours(value):
    cont, cur = [], []
    for op, args in value:
        if op == 'moveTo':
            cur = [(op, args)]
        elif op in ('closePath', 'endPath'):
            cur.append((op, args)); cont.append(cur); cur = []
        else:
            cur.append((op, args))
    if cur: cont.append(cur)
    return cont

def _add_extrema(value):
    out = []
    pos = None
    for op, args in value:
        if op == 'moveTo': out.append((op, args)); pos = args[0]
        elif op == 'lineTo': out.append((op, args)); pos = args[0]
        elif op == 'curveTo':
            segs = [(pos,) + tuple(args)]
            ts = set()
            p0, p1, p2, p3 = segs[0]
            for k in (0, 1):
                a = -p0[k] + 3*p1[k] - 3*p2[k] + p3[k]
                b = 2*(p0[k] - 2*p1[k] + p2[k]); c = p1[k] - p0[k]
                if abs(a) < 1e-9:
                    if abs(b) > 1e-9: ts.add(-c/b)
                else:
                    disc = b*b - 4*a*c
                    if disc >= 0:
                        s = math.sqrt(disc); ts.add((-b+s)/(2*a)); ts.add((-b-s)/(2*a))
            ts = sorted(t for t in ts if 0.02 < t < 0.98)
            pieces = splitCubicAtT(p0, p1, p2, p3, *ts) if ts else [segs[0]]
            for pc in pieces: out.append(('curveTo', tuple(pc[1:])))
            pos = args[-1]
        elif op == 'qCurveTo':
            if len(args) == 2:
                p0, p1, p2 = pos, args[0], args[1]
                ts = []
                for k in (0, 1):
                    d = p0[k] - 2*p1[k] + p2[k]
                    if abs(d) > 1e-9:
                        t = (p0[k] - p1[k]) / d
                        if 0.02 < t < 0.98: ts.append(t)
                ts = sorted(set(ts))
                pieces = splitQuadraticAtT(p0, p1, p2, *ts) if ts else [(p0, p1, p2)]
                for pc in pieces: out.append(('qCurveTo', tuple(pc[1:])))
            else:
                out.append((op, args))
            pos = args[-1]
        else:
            out.append((op, args))
    return out

def to_ttglyph(path, max_err=1.0):
    p = copy_path(path)
    p.simplify(fix_winding=True, keep_starting_points=False)
    rec = RecordingPen(); p.draw(rec)
    val = _add_extrema(rec.value)
    # decide orientation: biggest contour must be clockwise (negative area, y up)
    best, best_a = None, 0
    for c in _split_contours(val):
        ap = AreaPen(); rp = RecordingPen(); rp.value = c; rp.replay(ap)
        if abs(ap.value) > abs(best_a): best_a = ap.value
    flip = best_a > 0
    pen = TTGlyphPen(None)
    target = ReverseContourPen(pen) if flip else pen
    cu = Cu2QuPen(target, max_err, reverse_direction=False)
    rp = RecordingPen(); rp.value = val; rp.replay(cu)
    return pen.glyph()

# ---------------------------------------------------------------- font assembly
def build_ttf(out_path, family, ps, glyphs, cmap_extra, meta, kern_pairs=None, order=None,
              x_height=500, cap_height=700, is_mono=False):
    """glyphs: dict name -> (path, advance). cmap_extra: dict codepoint -> name."""
    names = ['.notdef'] + [n for n in (order or glyphs) if n != '.notdef']
    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(names)
    cmap = dict(cmap_extra)
    fb.setupCharacterMap(cmap)
    ttg, hmtx = {}, {}
    for n in names:
        path, adv = glyphs[n]
        g = to_ttglyph(path) if len(list(path.segments)) else TTGlyphPen(None).glyph()
        ttg[n] = g
    fb.setupGlyf(ttg)
    for n in names:
        g = fb.font['glyf'][n]
        adv = glyphs[n][1]
        g.recalcBounds(fb.font['glyf'])
        lsb = getattr(g, 'xMin', 0) if g.numberOfContours else 0
        hmtx[n] = (int(round(adv)), int(lsb))
    fb.setupHorizontalMetrics(hmtx)
    fb.setupHorizontalHeader(ascent=800, descent=-200, lineGap=0)
    full = family + ' Regular'
    fb.setupNameTable({
        'copyright': 'Copyright (c) 2026 Lyra Fonts Project. Reserved Font Name "Lyra".',
        'familyName': family, 'styleName': 'Regular',
        'uniqueFontIdentifier': '%s;1.000;%s' % (ps, 'LYRA'),
        'fullName': full, 'psName': ps, 'version': 'Version 1.000',
        'designer': 'Lyra Fonts Project (generated, original outlines)',
        'description': meta['description'],
        'licenseDescription': 'This Font Software is licensed under the SIL Open Font License, Version 1.1. This license is available with a FAQ at https://openfontlicense.org',
        'licenseInfoURL': 'https://openfontlicense.org',
        'vendorURL': 'https://openfontlicense.org',
    })
    fb.setupOS2(
        version=4,
        sTypoAscender=800, sTypoDescender=-200, sTypoLineGap=0,
        usWinAscent=900, usWinDescent=250,
        sxHeight=meta.get('xheight', x_height), sCapHeight=cap_height,
        fsSelection=(1 << 6) | (1 << 7),  # REGULAR + USE_TYPO_METRICS
        usWeightClass=400, usWidthClass=5, achVendID='LYRA',
        fsType=0, ulUnicodeRange1=0b11, ulCodePageRange1=1,
        usDefaultChar=0, usBreakChar=32, usMaxContext=2,
    )
    fb.setupPost(keepGlyphNames=True, isFixedPitch=1 if is_mono else 0)
    fb.font['head'].macStyle = 0
    fb.font['head'].fontRevision = 1.0
    if kern_pairs:
        lines = ['feature kern {']
        by_first = {}
        for (a, b), v in kern_pairs.items():
            if v: by_first.setdefault(a, []).append((b, v))
        for a in sorted(by_first):
            for b, v in sorted(by_first[a]):
                lines.append('  pos %s %s %d;' % (a, b, v))
        lines.append('} kern;')
        fb.addOpenTypeFeatures('\n'.join(lines) if len(lines) > 2 else '', tables=['GPOS'])  # noqa
    fb.save(out_path)
    return out_path

def add_features_text(fb, text, tables=None):
    from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
    addOpenTypeFeaturesFromString(fb.font, text, tables=tables)

# ---------------------------------------------------------------- assembling accents
def compose_accents(glyphs, mark_fn, cmap):
    """glyphs: name->(path,adv). mark_fn(kind, cx, base_bounds, is_upper) -> path positioned absolute."""
    for ch, (base, kind) in ACCENT_SPEC.items():
        bn = gname(base)
        bpath, adv = glyphs[bn]
        b = bpath.bounds
        cx = getattr(compose_accents, 'anchor', {}).get(base, (b[0] + b[2]) / 2)
        mk = mark_fn(kind, cx, b, base.isupper())
        glyphs[gname(ch)] = (union(bpath, mk), adv)
        cmap[ord(ch)] = gname(ch)

# ---------------------------------------------------------------- auto-kerning from ink profiles
def ink_profiles(ttf, chars, scale=0.4, ymin=-250, ymax=950):
    """returns dict ch -> (rsb_profile, lsb_profile, adv) sampled each 1/scale/... unit rows (row = 1/scale? )"""
    size = int(UPM * scale)
    font = ImageFont.truetype(ttf, size)
    tt = TTFont(ttf); hm = tt['hmtx']; cm = tt.getBestCmap()
    rows = int((ymax - ymin) * scale)
    prof = {}
    for ch in chars:
        gn = cm.get(ord(ch))
        if gn is None: continue
        adv = hm[gn][0]
        W = int((adv + 600) * scale) + 4
        pad = int(300 * scale)
        im = Image.new('L', (W + 2 * pad, int((ymax - ymin) * scale)), 0)
        d = ImageDraw.Draw(im)
        base_y = int(ymax * scale)
        d.text((pad, base_y), ch, font=font, fill=255, anchor='ls')
        a = np.array(im) > 90
        L = np.full(rows, np.inf); R = np.full(rows, np.inf)
        for r in range(rows):
            xs = np.nonzero(a[r])[0]
            if len(xs):
                L[r] = (xs[0] - pad) / scale
                R[r] = adv - (xs[-1] + 1 - pad) / scale
        prof[ch] = (R, L, adv)
    return prof, rows, scale

def auto_kern(ttf, chars, target, max_kern=160, tol=14, window_units=40, loosen_below=None, skip_pair=None,
              step=5):
    prof, rows, scale = ink_profiles(ttf, chars)
    w = max(1, int(window_units * scale))
    def dil(a):
        out = a.copy()
        for k in range(1, w + 1):
            out[k:] = np.minimum(out[k:], a[:-k]); out[:-k] = np.minimum(out[:-k], a[k:])
        return out
    dil_R = {c: dil(prof[c][0]) for c in prof}; dil_L = {c: dil(prof[c][1]) for c in prof}
    res = {}
    for a in prof:
        Ra, _, _ = prof[a]
        for b in prof:
            if skip_pair and skip_pair(a, b): continue
            _, Lb, _ = prof[b]
            g = np.minimum(dil_R[a] + Lb, Ra + dil_L[b])
            g = g[np.isfinite(g)]
            if not len(g): continue
            mg = g.min()
            t = target(a, b) if callable(target) else target
            if mg > t + tol:
                k = -min(mg - t, max_kern)
            elif loosen_below is not None and mg < loosen_below:
                k = min(loosen_below - mg, 60)
            else:
                continue
            k = int(round(k / step) * step)
            if k: res[(a, b)] = k
    return res

# ---------------------------------------------------------------- GPOS pair reader (for specimen / checks)
def read_kern(ttf):
    tt = TTFont(ttf)
    pairs = {}
    if 'GPOS' not in tt: return pairs
    gpos = tt['GPOS'].table
    for lk in gpos.LookupList.Lookup:
        subs = lk.SubTable
        for st in subs:
            if lk.LookupType == 9: st = st.ExtSubTable
            if getattr(st, 'LookupType', None) is None and not hasattr(st, 'Format'): continue
            if not hasattr(st, 'Coverage') or not hasattr(st, 'PairSet') and not hasattr(st, 'Class1Record'): continue
            if st.Format == 1:
                cov = st.Coverage.glyphs
                for gi, ps in zip(cov, st.PairSet):
                    for pvr in ps.PairValueRecord:
                        v = pvr.Value1.XAdvance if pvr.Value1 else 0
                        pairs[(gi, pvr.SecondGlyph)] = v
            elif st.Format == 2:
                cd1 = st.ClassDef1.classDefs; cd2 = st.ClassDef2.classDefs
                for g1 in st.Coverage.glyphs:
                    c1 = cd1.get(g1, 0)
                    for g2, c2 in cd2.items():
                        rec = st.Class1Record[c1].Class2Record[c2]
                        v = rec.Value1.XAdvance if rec.Value1 else 0
                        if v: pairs[(g1, g2)] = v
    return pairs

# ---------------------------------------------------------------- specimen
def layout(text, tt, kern, cm, size):
    sc = size / UPM
    x = 0.0; out = []
    prev = None
    for ch in text:
        gn = cm.get(ord(ch))
        if gn is None: continue
        if prev is not None: x += kern.get((prev, gn), 0) * sc
        out.append((ch, x)); x += tt['hmtx'][gn][0] * sc; prev = gn
    return out, x

def draw_text(draw, xy, text, font, tt, kern, cm, size, fill):
    items, w = layout(text, tt, kern, cm, size)
    x0, y = xy
    for ch, x in items:
        draw.text((x0 + x, y), ch, font=font, fill=fill, anchor='ls')
    return w

def make_specimen(ttf, out_png, title, bg=(14, 14, 20), fg=(238, 238, 244), dim=(130, 130, 150),
                  accent=None, W=2200):
    tt = TTFont(ttf); cm = tt.getBestCmap(); kern = read_kern(ttf)
    fonts = {}
    def F(sz):
        if sz not in fonts: fonts[sz] = ImageFont.truetype(ttf, sz)
        return fonts[sz]
    try:
        label_font = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 22)
    except Exception:
        label_font = ImageFont.load_default()
    sections = [
        ('UPPERCASE', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'),
        ('lowercase', 'abcdefghijklmnopqrstuvwxyz'),
        ('NUMERALS', '0123456789'),
        ('PUNCTUATION', ". , ! ? ' \" ‘ ’ “ ” - – — : ; & ( ) / \\ # @ % + = $ * … _ ~ ^ < > [ ] { } | ` ¡ ¿"),
        ('ACCENTS (UPPER)', 'ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÑÒÓÔÕÖØÙÚÛÜÝ'),
        ('ACCENTS (lower)', 'àáâãäåæçèéêëìíîïñòóôõöøùúûüýÿß'),
    ]
    tests = ["Midnight in the city lights", "HOLD ME CLOSER, TONIGHT!",
             "Quick zephyrs blow, vexing daft Jim. 0123456789", "Can't stop (won't stop) - 100% yours & mine?"]
    blocks = []  # (kind,text,size)
    for lab, s in sections: blocks.append(('label', lab, 0)); blocks.append(('text', s, 84))
    blocks.append(('label', 'TEST LINES  36 px', 0))
    for t in tests: blocks.append(('text', t, 36))
    blocks.append(('label', 'TEST LINES  96 px', 0))
    for t in tests: blocks.append(('text', t, 96))
    blocks.append(('label', 'LOOK-ALIKES & PAIRS', 0))
    blocks.append(('text', 'O0 I l 1 S5 B8 rn m  AV To LT ra fi yo Wa P.', 84))
    # measure
    margin = 70
    def wrapped(text, size):
        words = text.split(' '); lines = []; cur = ''
        for wd in words:
            t = (cur + ' ' + wd) if cur else wd
            if layout(t, tt, kern, cm, size)[1] > W - 2 * margin and cur:
                lines.append(cur); cur = wd
            else: cur = t
        lines.append(cur); return lines
    y = 70; plan = []
    plan.append(('title', title, y + 40)); y += 110
    for kind, text, size in blocks:
        if kind == 'label':
            y += 30; plan.append(('label', text, y)); y += 14
        else:
            for ln in wrapped(text, size):
                y += int(size * 1.18); plan.append(('text', ln, y, size))
            y += 6
    H = y + 70
    im = Image.new('RGB', (W, H), bg); d = ImageDraw.Draw(im)
    for item in plan:
        if item[0] == 'title':
            d.text((margin, item[2]), item[1], font=label_font, fill=dim, anchor='ls')
        elif item[0] == 'label':
            d.text((margin, item[2]), item[1], font=label_font, fill=dim, anchor='ls')
            d.line([(margin, item[2] + 8), (W - margin, item[2] + 8)], fill=(40, 40, 52), width=1)
        else:
            _, ln, yy, size = item
            draw_text(d, (margin, yy), ln, F(size), tt, kern, cm, size, fg)
    im.save(out_png)
    return im.size

# ---------------------------------------------------------------- verification
def verify(ttf, required=REQUIRED):
    tt = TTFont(ttf); cm = tt.getBestCmap(); gs = tt.getGlyphSet(); glyf = tt['glyf']
    problems = []
    for ch in required:
        gn = cm.get(ord(ch))
        if gn is None: problems.append('missing ' + repr(ch)); continue
        if ch != ' ' and glyf[gn].numberOfContours == 0: problems.append('empty ' + repr(ch))
    for n in tt.getGlyphOrder():
        g = glyf[n]
        if g.numberOfContours > 0:
            # orientation + sanity
            coords, ends, _ = g.getCoordinates(glyf)
            start = 0; areas = []
            for e in ends:
                pts = coords[start:e + 1]; start = e + 1
                a = 0
                for i in range(len(pts)):
                    x1, y1 = pts[i]; x2, y2 = pts[(i + 1) % len(pts)]
                    a += x1 * y2 - x2 * y1
                areas.append(a / 2)
            if max(areas, key=abs) > 0: problems.append('direction ' + n)
            if abs(min(areas, key=abs)) < 30 and len(areas) > 0 and n != '.notdef':
                if abs(min(areas, key=abs)) < 30: problems.append('tiny contour ' + n)
    os2 = tt['OS/2']; hh = tt['hhea']
    info = dict(upm=tt['head'].unitsPerEm, hhea=(hh.ascent, hh.descent, hh.lineGap),
                typo=(os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap),
                win=(os2.usWinAscent, os2.usWinDescent), fsSel=bin(os2.fsSelection),
                xh=os2.sxHeight, cap=os2.sCapHeight, nglyphs=len(tt.getGlyphOrder()),
                kernpairs=len(read_kern(ttf)))
    return problems, info
