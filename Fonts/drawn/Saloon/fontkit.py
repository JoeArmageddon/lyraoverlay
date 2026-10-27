"""fontkit: shared procedural type-design toolkit (pen sweeping, boolean ops,
auto spacing, auto kerning, TTF assembly, specimen).  Original code, OFL-1.1."""
import math, random, re
import numpy as np
import pathops
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.recordingPen import RecordingPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools import agl

# --------------------------------------------------------------- geometry
def hull(pts):
    pts = sorted(set((round(x, 4), round(y, 4)) for x, y in pts))
    if len(pts) <= 2:
        return pts
    def cr(o, a, b):
        return (a[0]-o[0])*(b[1]-o[1]) - (a[1]-o[1])*(b[0]-o[0])
    lo = []
    for p in pts:
        while len(lo) >= 2 and cr(lo[-2], lo[-1], p) <= 0: lo.pop()
        lo.append(p)
    up = []
    for p in reversed(pts):
        while len(up) >= 2 and cr(up[-2], up[-1], p) <= 0: up.pop()
        up.append(p)
    return lo[:-1] + up[:-1]          # CCW

def rect_pen(w, h, ang):
    a = math.radians(ang); c, s = math.cos(a), math.sin(a)
    return [(px*c - py*s, px*s + py*c)
            for px, py in [(-w/2, -h/2), (w/2, -h/2), (w/2, h/2), (-w/2, h/2)]]

def ellipse_pen(rx, ry, ang=0, n=20):
    a = math.radians(ang); c, s = math.cos(a), math.sin(a)
    out = []
    for i in range(n):
        t = 2*math.pi*i/n
        px, py = rx*math.cos(t), ry*math.sin(t)
        out.append((px*c - py*s, px*s + py*c))
    return out

def superellipse_pen(rx, ry, p=3.0, n=32):
    out = []
    for i in range(n):
        t = 2*math.pi*i/n
        ct, st = math.cos(t), math.sin(t)
        out.append((rx*math.copysign(abs(ct)**(2/p), ct), ry*math.copysign(abs(st)**(2/p), st)))
    return out

def bez(p0, p1, p2, p3, step):
    L = math.dist(p0, p1) + math.dist(p1, p2) + math.dist(p2, p3)
    n = max(3, int(L/step))
    out = []
    for i in range(1, n+1):
        t = i/n; u = 1-t
        out.append((u**3*p0[0]+3*u*u*t*p1[0]+3*u*t*t*p2[0]+t**3*p3[0],
                    u**3*p0[1]+3*u*u*t*p1[1]+3*u*t*t*p2[1]+t**3*p3[1]))
    return out

def qbez(p0, p1, p2, step):
    return bez(p0, ((p0[0]+2*p1[0])/3, (p0[1]+2*p1[1])/3),
               ((p2[0]+2*p1[0])/3, (p2[1]+2*p1[1])/3), p2, step)

def catmull(pts, step):
    P = [pts[0]] + list(pts) + [pts[-1]]
    out = []
    for i in range(1, len(P)-2):
        p0, p1, p2, p3 = P[i-1], P[i], P[i+1], P[i+2]
        c1 = (p1[0]+(p2[0]-p0[0])/6, p1[1]+(p2[1]-p0[1])/6)
        c2 = (p2[0]-(p3[0]-p1[0])/6, p2[1]-(p3[1]-p1[1])/6)
        out += bez(p1, c1, c2, p2, step)
    return out

def arcpts(cx, cy, rx, ry, a0, a1, step):
    L = abs(math.radians(a1-a0)) * max(rx, ry)
    n = max(4, int(L/step))
    return [(cx+rx*math.cos(math.radians(a0+(a1-a0)*i/n)),
             cy+ry*math.sin(math.radians(a0+(a1-a0)*i/n))) for i in range(n+1)]

def parse(spec, step=8):
    """SVG-like absolute path: M L C Q K(spline thru pts) E(ellipse arc) Z -> list of polylines"""
    toks = re.findall(r"[A-Za-z]|-?\d*\.?\d+(?:e-?\d+)?", spec)
    subs = []; cur = None; i = 0; cmd = None
    def nums(k):
        nonlocal i
        v = [float(toks[i+j]) for j in range(k)]; i += k; return v
    def isnum():
        return i < len(toks) and not toks[i].isalpha()
    while i < len(toks):
        if toks[i].isalpha():
            cmd = toks[i]; i += 1
            if cmd == 'M':
                cur = [tuple(nums(2))]; subs.append(cur); continue
            if cmd == 'Z':
                cur.append(cur[0]); continue
            if cmd == 'K':
                pts = [cur[-1]]
                while isnum(): pts.append(tuple(nums(2)))
                cur += catmull(pts, step)[:]; continue
        if cmd == 'L':
            while isnum(): cur.append(tuple(nums(2)))
        elif cmd == 'C':
            while isnum():
                a = nums(6); cur += bez(cur[-1], (a[0], a[1]), (a[2], a[3]), (a[4], a[5]), step)
        elif cmd == 'Q':
            while isnum():
                a = nums(4); cur += qbez(cur[-1], (a[0], a[1]), (a[2], a[3]), step)
        elif cmd == 'E':
            a = nums(6)
            pts = arcpts(*a, step)
            if cur is None: cur = [pts[0]]; subs.append(cur)
            cur += pts if math.dist(cur[-1], pts[0]) > 0.5 else pts[1:]
        elif cmd in ('M',):
            cur = [tuple(nums(2))]; subs.append(cur)
        else:
            raise ValueError(spec)
    return subs

# --------------------------------------------------------------- shape ops
def path_from(contours):
    p = pathops.Path()
    for c in contours:
        if len(c) < 3: continue
        p.moveTo(*c[0])
        for q in c[1:]: p.lineTo(*q)
        p.close()
    return p

def contours_of(path):
    rp = RecordingPen(); path.draw(rp)
    out = []; cur = []
    for op, a in rp.value:
        if op == 'moveTo': cur = [a[0]]
        elif op == 'lineTo': cur.append(a[0])
        elif op in ('closePath', 'endPath'):
            if len(cur) >= 3: out.append(cur)
            cur = []
        else: raise ValueError(op)
    return out

def union(contours, clockwise=False):
    p = path_from(contours)
    p.simplify(fix_winding=True, keep_starting_points=False, clockwise=clockwise)
    return contours_of(p)

def difference(a, b):
    pa, pb = path_from(a), path_from(b)
    pa.simplify(fix_winding=True); pb.simplify(fix_winding=True)
    r = pathops.op(pa, pb, pathops.PathOp.DIFFERENCE, fix_winding=True,
                   keep_starting_points=False, clockwise=False)
    return contours_of(r)

def intersect(a, b):
    pa, pb = path_from(a), path_from(b)
    pa.simplify(fix_winding=True); pb.simplify(fix_winding=True)
    r = pathops.op(pa, pb, pathops.PathOp.INTERSECTION, fix_winding=True,
                   keep_starting_points=False, clockwise=False)
    return contours_of(r)

def translate(cs, dx, dy):
    return [[(x+dx, y+dy) for x, y in c] for c in cs]

def xform(cs, f):
    return [[f(x, y) for x, y in c] for c in cs]

def bbox(cs):
    xs = [x for c in cs for x, y in c]; ys = [y for c in cs for x, y in c]
    return min(xs), min(ys), max(xs), max(ys)

def sweep(pts, pen, scales=None):
    polys = []; prev = None
    for i, (x, y) in enumerate(pts):
        s = scales[i] if scales else 1.0
        cur = [(x+px*s, y+py*s) for px, py in pen]
        polys.append(hull(cur))
        if prev is not None: polys.append(hull(prev+cur))
        prev = cur
    return polys

def dp(pts, tol):
    """Douglas-Peucker on a closed ring"""
    n = len(pts)
    if n < 6: return pts
    # anchor at two far points
    i0 = 0
    far = max(range(n), key=lambda i: math.dist(pts[i], pts[0]))
    def rec(a, b, seq):
        # seq includes endpoints
        if len(seq) <= 2: return [seq[0]]
        (x1, y1), (x2, y2) = seq[0], seq[-1]
        dx, dy = x2-x1, y2-y1; L = math.hypot(dx, dy)
        best, bi = -1, 0
        for k in range(1, len(seq)-1):
            x, y = seq[k]
            d = abs(dx*(y1-y)-(x1-x)*dy)/L if L > 1e-9 else math.dist(seq[k], seq[0])
            if d > best: best, bi = d, k
        if best > tol:
            return rec(a, b, seq[:bi+1]) + rec(a, b, seq[bi:])
        return [seq[0]]
    A = pts[:far+1]; B = pts[far:] + [pts[0]]
    return rec(0, 0, A) + rec(0, 0, B)

def cleanup(cs, tol=0.7):
    out = []
    for c in cs:
        c = dp(c, tol)
        c = [(round(x), round(y)) for x, y in c]
        d = [c[0]]
        for q in c[1:]:
            if q != d[-1]: d.append(q)
        if len(d) > 1 and d[0] == d[-1]: d.pop()
        if len(d) >= 3: out.append(d)
    r = union(out, clockwise=True)
    r2 = []
    for c in r:
        c = [(round(x), round(y)) for x, y in c]
        d = [c[0]]
        for q in c[1:]:
            if q != d[-1]: d.append(q)
        if len(d) > 1 and d[0] == d[-1]: d.pop()
        # drop collinear
        e = []
        for k in range(len(d)):
            a, b, cc = d[k-1], d[k], d[(k+1) % len(d)]
            if (b[0]-a[0])*(cc[1]-b[1]) - (b[1]-a[1])*(cc[0]-b[0]) != 0: e.append(b)
        if len(e) >= 3: r2.append(e)
    return r2

# --------------------------------------------------------------- builder
class Gb:
    """Accumulates stroked / filled shapes for one glyph."""
    def __init__(self, ctx):
        self.ctx = ctx; self.adds = []; self.cuts = []
    def stroke(self, spec, pen=None, scale=None, step=None):
        pen = pen or self.ctx.pen
        step = step or self.ctx.step
        for pts in parse(spec, step):
            sc = scale(pts) if callable(scale) else scale
            self.adds += sweep(pts, pen, sc)
        return self
    def cut(self, spec, pen, step=None):
        for pts in parse(spec, step or self.ctx.step):
            self.cuts += sweep(pts, pen)
        return self
    def poly(self, pts):
        h = hull(pts) if False else pts
        self.adds.append(self._ccw(pts)); return self
    def cutpoly(self, pts):
        self.cuts.append(self._ccw(pts)); return self
    @staticmethod
    def _ccw(pts):
        a = sum(pts[i][0]*pts[(i+1) % len(pts)][1]-pts[(i+1) % len(pts)][0]*pts[i][1] for i in range(len(pts)))
        return list(pts) if a > 0 else list(reversed(pts))
    def add_contours(self, cs):
        self.adds += cs; return self
    def result(self):
        r = union(self.adds)
        if self.cuts:
            r = difference(r, union(self.cuts))
        return r

def diamond(cx, cy, hw, hh):
    return [(cx-hw, cy), (cx, cy-hh), (cx+hw, cy), (cx, cy+hh)]

def circle_pts(cx, cy, r, n=28):
    return [(cx+r*math.cos(2*math.pi*i/n), cy+r*math.sin(2*math.pi*i/n)) for i in range(n)]

# --------------------------------------------------------------- profiles / spacing
def edges_of(cs):
    E = []
    for c in cs:
        for i in range(len(c)):
            E.append((*c[i], *c[(i+1) % len(c)]))
    return np.array(E, float)

def profile(cs, ys):
    E = edges_of(cs)
    x0, y0, x1, y1 = E.T
    lo = np.full(len(ys), np.nan); hi = np.full(len(ys), np.nan)
    for k, y in enumerate(ys):
        m = ((y0 <= y) & (y1 > y)) | ((y1 <= y) & (y0 > y))
        if not m.any(): continue
        xs = x0[m] + (y-y0[m])*(x1[m]-x0[m])/(y1[m]-y0[m])
        lo[k] = xs.min(); hi[k] = xs.max()
    return lo, hi

def auto_sb(cs, zone, S0, f, D, minsb=14):
    ys = np.arange(zone[0]+5, zone[1], 10.0)
    lo, hi = profile(cs, ys)
    x0, _, x1, _ = bbox(cs)
    dl = np.where(np.isnan(lo), D, np.minimum(lo-x0, D))
    dr = np.where(np.isnan(hi), D, np.minimum(x1-hi, D))
    return max(minsb, S0 - f*dl.mean()), max(minsb, S0 - f*dr.mean())

# --------------------------------------------------------------- font assembly
def gname(cp):
    if cp == 0x20: return 'space'
    if cp == 0xA0: return 'nbspace'
    n = agl.UV2AGL.get(cp)
    return n if n else 'uni%04X' % cp

class Spec:
    """collection of glyph records"""
    def __init__(self):
        self.g = {}          # name -> dict(cs=raw contours, cp, cat, zone, sb)
        self.order = []
    def add(self, name, cs, cp=None, cat='l', zone=None, sb=None, adv=None, anchor=None):
        self.g[name] = dict(cs=cs, cp=cp, cat=cat, zone=zone, sb=sb, adv=adv, anchor=anchor)
        self.order.append(name)

def finish_metrics(spec, S0, f, D, jitter=0.0, seed=1, caps_S0=None, minsb=14):
    rnd = random.Random(seed)
    for name in spec.order:
        r = spec.g[name]
        cs = r['cs']
        if not cs:
            r['final'] = []; r['lsb'] = 0; r['adv'] = r['adv'] or 250; continue
        if r.get('follow'):
            continue
        x0, y0, x1, y1 = bbox(cs)
        zone = r['zone'] or (0, 500 if r['cat'] == 'l' else 700)
        if r['cat'] == 'p' and not r['zone']: zone = (y0, y1)
        s0 = caps_S0 if (caps_S0 and r['cat'] == 'U') else S0
        if r['cat'] == 'p': s0 = S0*0.8
        if r['sb']:
            l, rr = r['sb']
        else:
            l, rr = auto_sb(cs, zone, s0, f, D, minsb)
        if jitter:
            l += rnd.uniform(-jitter, jitter); rr += rnd.uniform(-jitter, jitter)
        r['shift'] = l - x0
        r['final'] = translate(cs, r['shift'], 0)
        r['lsb'] = l
        r['adv'] = (x1-x0) + l + rr if not r['adv'] else r['adv']

def kern_table(spec, names, tgt_l, tgt_u, mingap, maxneg=-110, scale=0.55, cap=2.0, ys=None):
    ys = ys if ys is not None else np.arange(-200, 801, 20) + 0.5
    P = {}
    for n in names:
        r = spec.g[n]
        lo, hi = profile(r['final'], ys)
        P[n] = (r['adv'], lo, hi, r['cat'])
    pairs = []
    for a in names:
        adv, _, hiA, ca = P[a]
        for b in names:
            _, loB, _, cb = P[b]
            d = (adv - hiA) + loB
            ok = ~np.isnan(d)
            if ok.sum() < 3: continue
            tgt = (tgt_u if ca == 'U' else tgt_l)*0.5 + (tgt_u if cb == 'U' else tgt_l)*0.5
            dd = d[ok]
            mean = np.minimum(dd, tgt*cap).mean()
            k_mean = min(scale*(tgt-mean), 0)
            k_min = mingap - dd.min()
            k = max(k_min, k_mean, maxneg)
            k = min(k, 90)
            k = int(round(k/2.0)*2)
            if abs(k) >= 6: pairs.append((a, b, k))
    return pairs

def ref_gap(spec, a, b):
    ys = np.arange(0, 700, 20) + 0.5
    ra, rb = spec.g[a], spec.g[b]
    _, hiA = profile(ra['final'], ys); loB, _ = profile(rb['final'], ys)
    d = (ra['adv']-hiA) + loB
    return float(np.nanmean(d))

def build_ttf(spec, path, names, features, naming, upm=1000, keep_cs=None):
    """names: dict of metadata. spec.order glyph order"""
    glyph_order = ['.notdef'] + [n for n in spec.order if n != '.notdef']
    fb = FontBuilder(upm, isTTF=True)
    fb.setupGlyphOrder(glyph_order)
    cmap = {}
    for n in spec.order:
        cp = spec.g[n]['cp']
        if cp is not None: cmap[cp] = n
    fb.setupCharacterMap(cmap)
    glyphs = {}; metrics = {}
    for n in glyph_order:
        r = spec.g[n]
        pen = TTGlyphPen(None)
        r['final'] = cleanup(r['final']) if r['final'] else []
        for c in r['final']:
            pen.moveTo(c[0])
            for q in c[1:]: pen.lineTo(q)
            pen.closePath()
        g = pen.glyph()
        glyphs[n] = g
    fb.setupGlyf(glyphs)
    for n in glyph_order:
        g = fb.font['glyf'][n]
        g.recalcBounds(fb.font['glyf'])
        metrics[n] = (int(round(spec.g[n]['adv'])), getattr(g, 'xMin', 0) if g.numberOfContours else 0)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=800, descent=-200, lineGap=0)
    fam = naming['family']
    fb.setupNameTable({
        'copyright': naming['copyright'], 'familyName': fam, 'styleName': 'Regular',
        'uniqueFontIdentifier': '%s-Regular;1.000;LYRA' % fam.replace(' ', ''),
        'fullName': fam, 'version': 'Version 1.000',
        'psName': fam.replace(' ', '') + '-Regular',
        'manufacturer': 'Lyra', 'designer': 'Lyra generated type design',
        'description': naming['description'],
        'licenseDescription': 'This Font Software is licensed under the SIL Open Font License, Version 1.1. This license is available with a FAQ at: https://openfontlicense.org',
        'licenseInfoURL': 'https://openfontlicense.org',
    })
    fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, sTypoLineGap=0,
                usWinAscent=900, usWinDescent=250, sxHeight=500, sCapHeight=700,
                version=4, fsSelection=0x00C0, achVendID='LYRA', usWeightClass=400, usWidthClass=5,
                fsType=0, ulUnicodeRange1=1, ulCodePageRange1=1,
                usFirstCharIndex=0x20, usLastCharIndex=0x2026)
    fb.setupPost(keepGlyphNames=True, isFixedPitch=0, underlinePosition=-100, underlineThickness=50)
    fb.setupDummyDSIG = None
    font = fb.font
    font['head'].macStyle = 0
    font['head'].flags |= 0x1 | 0x8
    addOpenTypeFeaturesFromString(font, features)
    fb.save(path)

def fea_kern(pairs):
    lines = ['feature kern {']
    for a, b, k in pairs: lines.append('  pos %s %s %d;' % (a, b, k))
    lines.append('} kern;')
    return '\n'.join(lines)

LICENSE_OFL = """SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007

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

# --------------------------------------------------------------- charset
LOWER = 'abcdefghijklmnopqrstuvwxyz'
UPPER = LOWER.upper()
DIGITS = '0123456789'
PUNCT = ".,!?'\"‘’“”-–—:;&()/\\#@%+=$*…_~^<>[]{}|`¡¿"
ACC_UP = 'ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÑÒÓÔÕÖØÙÚÛÜÝ'
ACC_LO = 'àáâãäåæçèéêëìíîïñòóôõöøùúûüýÿß'
REQUIRED = LOWER + UPPER + DIGITS + ' ' + PUNCT + ACC_UP + ACC_LO

# base letter + mark for composed accents
COMPOSE = {
 'À':('A','grave'),'Á':('A','acute'),'Â':('A','circ'),'Ã':('A','tilde'),'Ä':('A','diaer'),'Å':('A','ring'),
 'Ç':('C','cedil'),'È':('E','grave'),'É':('E','acute'),'Ê':('E','circ'),'Ë':('E','diaer'),
 'Ì':('I','grave'),'Í':('I','acute'),'Î':('I','circ'),'Ï':('I','diaer'),'Ñ':('N','tilde'),
 'Ò':('O','grave'),'Ó':('O','acute'),'Ô':('O','circ'),'Õ':('O','tilde'),'Ö':('O','diaer'),
 'Ù':('U','grave'),'Ú':('U','acute'),'Û':('U','circ'),'Ü':('U','diaer'),'Ý':('Y','acute'),
 'à':('a','grave'),'á':('a','acute'),'â':('a','circ'),'ã':('a','tilde'),'ä':('a','diaer'),'å':('a','ring'),
 'ç':('c','cedil'),'è':('e','grave'),'é':('e','acute'),'ê':('e','circ'),'ë':('e','diaer'),
 'ì':('dotlessi','grave'),'í':('dotlessi','acute'),'î':('dotlessi','circ'),'ï':('dotlessi','diaer'),'ñ':('n','tilde'),
 'ò':('o','grave'),'ó':('o','acute'),'ô':('o','circ'),'õ':('o','tilde'),'ö':('o','diaer'),
 'ù':('u','grave'),'ú':('u','acute'),'û':('u','circ'),'ü':('u','diaer'),'ý':('y','acute'),'ÿ':('y','diaer'),
}

# --------------------------------------------------------------- generic punctuation / marks
def punct(mk, P):
    """mk() -> new Gb.  P: dict(cap, xh, asc, desc, dot(g,x,y,s), pen2, taper(fn), s(scale))
    returns dict name->(Gb, extra) for punctuation glyph keys (unicode chars)."""
    cap, xh = P['cap'], P['xh']; dot = P['dot']; p2 = P['pen2']; R = {}
    def new(): return mk()
    # period, comma
    g = new(); dot(g, 0, 0); R['.'] = g
    g = new(); dot(g, 0, 0); g.stroke("M 0 %d L %d %d" % (P['dr']-10, -P['tail'][0], -P['tail'][1]), pen=p2, scale=P['tailscale']); R[','] = g
    g = new(); dot(g, 0, 0); dot(g, 0, xh*0.62); R[':'] = g
    g = new(); dot(g, 0, 0); g.stroke("M 0 %d L %d %d" % (P['dr']-10, -P['tail'][0], -P['tail'][1]), pen=p2, scale=P['tailscale']); dot(g, 0, xh*0.62); R[';'] = g
    g = new(); dot(g, 0, 0); g.stroke("M 0 %d L 0 %d" % (P['dr']*2+40, cap-20), scale=P['taper'])
    R['!'] = g
    g = new(); dot(g, 0, 0); g.stroke(P['qspec'], scale=None); R['?'] = g
    # inverted
    def flip(gb, cy):
        gg = new(); gg.adds = [ _rev(c) for c in xform(gb.adds, lambda x, y: (-x, 2*cy-y))]
        gg.cuts = [ _rev(c) for c in xform(gb.cuts, lambda x, y: (-x, 2*cy-y))]; return gg
    R['¡'] = flip(R['!'], 300+0)
    R['¿'] = flip(R['?'], 300)
    # quotes
    t = P['qh']
    def tick(g, x, y, lean):
        g.stroke("M %d %d L %d %d" % (x, y, x - lean, y - t), scale=P['tickscale'], pen=P['pen3'])
    g = new(); tick(g, 0, cap-10, 0); R["'"] = g
    g = new(); tick(g, 0, cap-10, 0); tick(g, P['qgap'], cap-10, 0); R['"'] = g
    def comma_q(g, x, up):
        y0 = cap - 10
        if up:   # 66 style: dot + tail up-right  ( "‘" )
            g.stroke("M %d %d L %d %d" % (x, y0-t, x+int(t*0.35), y0), scale=P['tickscale'], pen=P['pen3'])
        else:
            g.stroke("M %d %d L %d %d" % (x, y0, x-int(t*0.35), y0-t), scale=P['tickscale'], pen=P['pen3'])
    g = new(); comma_q(g, 0, True); R['‘'] = g
    g = new(); comma_q(g, 0, False); R['’'] = g
    g = new(); comma_q(g, 0, True); comma_q(g, P['qgap'], True); R['“'] = g
    g = new(); comma_q(g, 0, False); comma_q(g, P['qgap'], False); R['”'] = g
    # dashes
    y = P['dashy']
    g = new(); g.stroke("M 0 %d L %d %d" % (y, P['hy'], y), pen=p2); R['-'] = g
    g = new(); g.stroke("M 0 %d L %d %d" % (y, P['en'], y), pen=p2); R['–'] = g
    g = new(); g.stroke("M 0 %d L %d %d" % (y, P['em'], y), pen=p2); R['—'] = g
    g = new(); g.stroke("M 0 %d L %d %d" % (P['ul'], P['uw'], P['ul']), pen=p2); R['_'] = g
    g = new(); dot(g, 0, 0); dot(g, P['ellg'], 0); dot(g, 2*P['ellg'], 0); R['…'] = g
    # math
    my = P['my']; mw = P['mw']
    g = new(); g.stroke("M 0 %d L %d %d M %d %d L %d %d" % (my, mw, my, mw//2, my-mw//2, mw//2, my+mw//2), pen=p2); R['+'] = g
    g = new(); g.stroke("M 0 %d L %d %d M 0 %d L %d %d" % (my+P['eqg']//2, mw, my+P['eqg']//2, my-P['eqg']//2, mw, my-P['eqg']//2), pen=p2); R['='] = g
    ah = P['ah']
    g = new(); g.stroke("M %d %d L 0 %d L %d %d" % (mw, my+ah, my, mw, my-ah), pen=p2); R['<'] = g
    g = new(); g.stroke("M 0 %d L %d %d L 0 %d" % (my+ah, mw, my, my-ah), pen=p2); R['>'] = g
    g = new(); g.stroke("M 0 %d L %d %d" % (P['sl'][0], P['sl'][2], P['sl'][1]), pen=p2); R['/'] = g
    g = new(); g.stroke("M 0 %d L %d %d" % (P['sl'][1], P['sl'][2], P['sl'][0]), pen=p2); R['\\'] = g
    g = new(); g.stroke("M 0 %d L 0 %d" % (P['desc']+10, P['asc']-10), pen=p2); R['|'] = g
    # brackets
    top, bot = P['asc']-20, P['desc']+30; bw = P['bw']
    g = new(); g.stroke("M %d %d L 0 %d L 0 %d L %d %d" % (bw, top, top, bot, bw, bot), pen=p2); R['['] = g
    g = new(); g.stroke("M 0 %d L %d %d L %d %d L 0 %d" % (top, bw, top, bw, bot, bot), pen=p2); R[']'] = g
    pw = P['pw']; mid = (top+bot)/2
    g = new(); g.stroke("M %d %d C %d %d %d %d %d %d" % (pw, top, 0, top-180, 0, bot+180, pw, bot) , pen=p2); R['('] = g
    g = new(); g.stroke("M 0 %d C %d %d %d %d 0 %d" % (top, pw, top-180, pw, bot+180, bot), pen=p2); R[')'] = g
    k = bw*0.6
    g = new(); g.stroke("M %d %d C %d %d %d %d %d %d C %d %d %d %d %d %d C %d %d %d %d %d %d C %d %d %d %d %d %d" % (
        bw, top, k, top, k, top, k, top-60, k, mid+80, k, mid+50, 0, mid, k, mid-50, k, mid-80, k, bot+60, k, bot, k, bot, bw, bot), pen=p2); R['{'] = g
    g = new(); g.stroke("M 0 %d C %d %d %d %d %d %d C %d %d %d %d %d %d C %d %d %d %d %d %d C %d %d %d %d %d %d" % (
        top, bw-k, top, bw-k, top, bw-k, top-60, bw-k, mid+80, bw-k, mid+50, bw, mid, bw-k, mid-50, bw-k, mid-80, bw-k, bot+60, bw-k, bot, bw-k, bot, 0, bot), pen=p2); R['}'] = g
    # ~ ^ `
    wv = P['tw']; ty = P['ty']
    g = new(); g.stroke("M 0 %d C %d %d %d %d %d %d C %d %d %d %d %d %d" % (ty-10, wv*0.2, ty+70, wv*0.35, ty+70, wv*0.5, ty, wv*0.65, ty-70, wv*0.8, ty-70, wv, ty+10), pen=p2); R['~'] = g
    g = new(); g.stroke("M 0 %d L %d %d L %d %d" % (cap-150, P['cw']//2, cap-10, P['cw'], cap-150), pen=p2); R['^'] = g
    g = new(); g.stroke("M 0 %d L %d %d" % (cap-10, P['cw']//2, cap-130), pen=p2); R['`'] = g
    # asterisk
    r_ = P['star']; cy = cap-190
    spec = ""
    for a in (90, 150, 210):
        dx, dy = r_*math.cos(math.radians(a)), r_*math.sin(math.radians(a))
        spec += "M %.1f %.1f L %.1f %.1f " % (-dx, cy-dy, dx, cy+dy)
    g = new(); g.stroke(spec, pen=p2); R['*'] = g
    # hash
    hw_, hh = P['hw'], P['hh']
    g = new()
    for x in (hw_*0.3, hw_*0.7):
        g.stroke("M %d %d L %d %d" % (x-14, 20, x+14, hh), pen=p2)
    for y in (hh*0.32, hh*0.68):
        g.stroke("M 0 %d L %d %d" % (y, hw_, y), pen=p2)
    R['#'] = g
    # dollar
    g = new(); sw_ = P['sw']
    g.stroke(P['sspec'], pen=p2 if P.get('s_p2') else None)
    g.stroke("M %d %d L %d %d" % (sw_/2, -70, sw_/2, cap+60), pen=p2)
    R['$'] = g
    # ampersand
    s = P['amp']
    g = new(); g.stroke(s); R['&'] = g
    # percent
    g = new(); rr = P['pr']
    g.stroke("M %d %d E %d %d %d %d 0 360" % (rr*2, 560, rr*1.0+0, 560, rr, rr*1.0 if True else rr), pen=p2) if False else None
    g.stroke("E %d %d %d %d 0 360" % (rr+10, cap-rr-30, rr, rr), pen=p2)
    g.stroke("E %d %d %d %d 0 360" % (P['pw2']-rr-10, rr+30, rr, rr), pen=p2)
    g.stroke("M %d %d L %d %d" % (P['pw2']-40, cap-10, 40, 10), pen=p2)
    R['%'] = g
    # at
    R['@'] = P['at'](mk)
    return R

def _rev(c): return list(reversed(c))

MARK_KINDS = ('grave', 'acute', 'circ', 'tilde', 'diaer', 'ring', 'cedil')

def mark(mk, P, kind, cx, y0):
    g = mk(); p2 = P['pen2']; m = P['mk']      # m: scale of the mark
    if kind == 'grave':
        g.stroke("M %d %d L %d %d" % (cx-0.45*m, y0+1.15*m, cx+0.3*m, y0+0.15*m), pen=p2)
    elif kind == 'acute':
        g.stroke("M %d %d L %d %d" % (cx+0.45*m, y0+1.15*m, cx-0.3*m, y0+0.15*m), pen=p2)
    elif kind == 'circ':
        g.stroke("M %d %d L %d %d L %d %d" % (cx-0.7*m, y0+0.2*m, cx, y0+1.1*m, cx+0.7*m, y0+0.2*m), pen=p2)
    elif kind == 'tilde':
        g.stroke("M %d %d C %d %d %d %d %d %d C %d %d %d %d %d %d" % (cx-0.8*m, y0+0.35*m, cx-0.5*m, y0+1.05*m, cx-0.2*m, y0+1.0*m, cx, y0+0.65*m,
                 cx+0.2*m, y0+0.3*m, cx+0.5*m, y0+0.25*m, cx+0.8*m, y0+0.95*m), pen=p2)
    elif kind == 'diaer':
        P['dot'](g, cx-0.55*m, y0+0.6*m, 0.62); P['dot'](g, cx+0.55*m, y0+0.6*m, 0.62)
    elif kind == 'ring':
        g.stroke("E %d %d %d %d 0 360" % (cx, y0+0.7*m, 0.55*m, 0.55*m), pen=p2)
    elif kind == 'cedil':
        g.stroke("M %d 5 C %d -5 %d -70 %d -95" % (cx, cx+0.8*m, cx+0.9*m, cx-0.5*m), pen=p2)
    return g.result()

def compose_accents(spec, P, mk):
    for ch, (base, kind) in COMPOSE.items():
        b = spec.g[base]
        x0, y0, x1, y1 = bbox(b['cs'])
        cx = b['anchor'] if b['anchor'] is not None else (x0+x1)/2
        top = P['cap'] if b['cat'] == 'U' else P['xh']
        if kind == 'cedil': ym = 0
        else: ym = top + P['mgap'] + (P['mup_u'] if b['cat'] == 'U' else 0)
        m = mark(mk, P, kind, cx, ym)
        cs = union(b['cs'] + m)
        r = dict(b); r['cs'] = cs; r['cp'] = ord(ch)
        r['final'] = translate(cs, b['shift'], 0)
        spec.g[gname(ord(ch))] = r; spec.order.append(gname(ord(ch)))
    return spec

def ligature(spec, a, b, name, cp, overlap, cat):
    A, B = spec.g[a], spec.g[b]
    ax0, ay0, ax1, ay1 = bbox(A['cs']); bx0, by0, bx1, by1 = bbox(B['cs'])
    cs = union(A['cs'] + translate(B['cs'], ax1 - bx0 - overlap, 0))
    spec.add(name, cs, cp=cp, cat=cat)

# --------------------------------------------------------------- specimen
def read_kern(ttf):
    from fontTools.ttLib import TTFont
    f = TTFont(ttf); K = {}
    if 'GPOS' not in f: return K
    for lk in f['GPOS'].table.LookupList.Lookup:
        for st in lk.SubTable:
            if getattr(st, 'LookupType', 2) == 9: st = st.ExtSubTable
            if st.__class__.__name__ != 'PairPos' or st.Format != 1: continue
            for g1, ps in zip(st.Coverage.glyphs, st.PairSet):
                for pv in ps.PairValueRecord:
                    v = pv.Value1.XAdvance if pv.Value1 is not None and hasattr(pv.Value1, 'XAdvance') else 0
                    K[(g1, pv.SecondGlyph)] = v
    return K

def specimen(ttf, out, title, size_big=96, seqfn=None, draw_font=None):
    """Draws glyph by glyph using advances + GPOS kern read from the actual .ttf"""
    from PIL import Image, ImageDraw, ImageFont
    from fontTools.ttLib import TTFont
    BG, FG, DIM = (18, 18, 24), (244, 238, 222), (130, 130, 150)
    tt = TTFont(ttf); cm = tt.getBestCmap(); hm = tt['hmtx']; K = read_kern(ttf)
    dfont = draw_font or ttf
    if seqfn is None:
        seqfn = lambda t: [(c, cm.get(ord(c))) for c in t]
    W = 2200
    tests = ['Midnight in the city lights', 'HOLD ME CLOSER, TONIGHT!',
             'Quick zephyrs blow, vexing daft Jim. 0123456789', "Can't stop (won't stop) - 100% yours & mine?"]
    sets = [LOWER, UPPER, DIGITS + ' ' + PUNCT, ACC_UP, ACC_LO]
    pangr = ['The quick brown fox jumps over the lazy dog', 'Sphinx of black quartz, judge my vow']
    items = [('title', title, 56)]
    for s in sets: items.append(('set', s, 64))
    for t in pangr: items.append(('t', t, 48))
    for sz in (36, size_big):
        items.append(('lab', '%d pt' % sz, 22))
        for t in tests: items.append(('t', t, sz))
    heights = [int(sz*1.5) if k != 'lab' else 34 for k, t, sz in items]
    H = sum(heights) + 120
    im = Image.new('RGB', (W, H), BG); d = ImageDraw.Draw(im)
    y = 40
    for (k, t, sz), h in zip(items, heights):
        if k == 'lab':
            d.text((60, y+6), t, fill=DIM, font=ImageFont.load_default())
        else:
            f = ImageFont.truetype(dfont, sz)
            x = 60.0
            if k == 'set':
                for chn in t:
                    d.text((x, y), chn, font=f, fill=FG)
                    x += max(f.getlength(chn), sz*0.2) + sz*0.22
            else:
                seq = seqfn(t) if k != 'title' else [(c, cm.get(ord(c))) for c in t]
                col = DIM if k == 'title' else FG
                for i, (ch, gn) in enumerate(seq):
                    d.text((x, y), ch, font=f, fill=col)
                    adv = hm[gn][0] if gn in hm.metrics else 250
                    kv = K.get((gn, seq[i+1][1]), 0) if i+1 < len(seq) else 0
                    x += (adv + kv) * sz / 1000.0
        y += h
    im.save(out)

def verify(ttf, required=REQUIRED):
    from fontTools.ttLib import TTFont
    from fontTools.pens.areaPen import AreaPen
    f = TTFont(ttf); cmap = f.getBestCmap(); gs = f.getGlyphSet(); probs = []
    for ch in required:
        if ord(ch) not in cmap: probs.append('missing %r' % ch); continue
        n = cmap[ord(ch)]
        if ch != ' ':
            g = f['glyf'][n]
            if g.numberOfContours == 0: probs.append('empty %r' % ch)
    # contour direction + overlap check
    for n in f.getGlyphOrder():
        g = f['glyf'][n]
        if g.numberOfContours <= 0: continue
        p = pathops.Path(); gs[n].draw(p.getPen())
        a0 = p.area
        q = pathops.Path(p); q.simplify(fix_winding=True)
        if abs(abs(q.area) - abs(a0)) > 0.01*abs(q.area) + 5: probs.append('overlap/area %s %.0f %.0f' % (n, a0, q.area))
        ap = AreaPen(gs); gs[n].draw(ap)
        if ap.value > 0: probs.append('winding %s' % n)
    return probs
