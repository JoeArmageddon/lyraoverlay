#!/usr/bin/env python3
"""Lyra Neon Drawn - bent-glass neon tube monoline face.
Every glyph is a set of centre-line strokes (lines, arcs, rounded polylines) which are
stroked with a round-capped, round-joined pen of constant width (the 'tube') using
skia-pathops, merged by boolean union and written as a quadratic TrueType font.
Run:  /tmp/fontvenv/bin/python build_neon.py
"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pathops
import lyra_fontkit as K

HERE = os.path.dirname(os.path.abspath(__file__))
FAMILY, PS = 'Lyra Neon Drawn', 'LyraNeonDrawn-Regular'
OUT = os.path.join(HERE, 'LyraNeonDrawn-Regular.ttf')

S = 64.0            # tube diameter
T, Bt, M = 668.0, 32.0, 350.0   # cap top / bottom / mid (centre-line)
XT = 468.0          # x-height centre-line
ASC = 690.0         # ascender centre-line
DESC = -165.0       # descender centre-line
KAPPA = 0.5522847498

class B:
    """centre-line builder"""
    def __init__(s, width=None):
        s.p = pathops.Path(); s.cur = None; s.width = width; s.closed = False
    def m(s, x, y): s.p.moveTo(x, y); s.cur = (x, y); return s
    def l(s, x, y):
        if s.cur is None: return s.m(x, y)
        s.p.lineTo(x, y); s.cur = (x, y); return s
    def q(s, cx, cy, x, y): s.p.quadTo(cx, cy, x, y); s.cur = (x, y); return s
    def c(s, x1, y1, x2, y2, x, y): s.p.cubicTo(x1, y1, x2, y2, x, y); s.cur = (x, y); return s
    def arc(s, cx, cy, rx, ry, a0, a1):
        t0, t1 = math.radians(a0), math.radians(a1)
        n = max(1, int(math.ceil(abs(t1 - t0) / (math.pi / 2) - 1e-9)))
        pt = lambda t: (cx + rx * math.cos(t), cy + ry * math.sin(t))
        p0 = pt(t0)
        if s.cur is None: s.m(*p0)
        elif math.hypot(s.cur[0] - p0[0], s.cur[1] - p0[1]) > 0.5: s.l(*p0)
        d = (t1 - t0) / n
        al = 4.0 / 3.0 * math.tan(d / 4)
        for i in range(n):
            ta, tb = t0 + i * d, t0 + (i + 1) * d
            pa, pb = pt(ta), pt(tb)
            da = (-rx * math.sin(ta), ry * math.cos(ta)); db = (-rx * math.sin(tb), ry * math.cos(tb))
            s.c(pa[0] + al * da[0], pa[1] + al * da[1], pb[0] - al * db[0], pb[1] - al * db[1], pb[0], pb[1])
        return s
    def close(s): s.p.close(); s.closed = True; return s

def line(x0, y0, x1, y1): return B().m(x0, y0).l(x1, y1)
def _poly(pts, r):
    b = B(); b.m(*pts[0])
    for i in range(1, len(pts) - 1):
        a, c0, c1 = pts[i - 1], pts[i], pts[i + 1]
        l1 = math.hypot(c0[0] - a[0], c0[1] - a[1]); l2 = math.hypot(c1[0] - c0[0], c1[1] - c0[1])
        d1 = min(r, l1 / 2.2); d2 = min(r, l2 / 2.2)
        p1 = (c0[0] - (c0[0] - a[0]) / l1 * d1, c0[1] - (c0[1] - a[1]) / l1 * d1)
        p2 = (c0[0] + (c1[0] - c0[0]) / l2 * d2, c0[1] + (c1[1] - c0[1]) / l2 * d2)
        b.l(*p1); b.q(c0[0], c0[1], *p2)
    b.l(*pts[-1]); return b
def ell(cx, cy, rx, ry, a0=90): return B().arc(cx, cy, rx, ry, a0, a0 + 360).close()
def dot(x, y): return B().m(x, y).l(x + 0.02, y)
def arcs(cx, cy, rx, ry, a0, a1): return B().arc(cx, cy, rx, ry, a0, a1)

def stroke_all(strokes, default_w=S):
    out = pathops.Path()
    for b in strokes:
        p = pathops.Path(); p.addPath(b.p)
        p.stroke(b.width or default_w, pathops.LineCap.ROUND_CAP, pathops.LineJoin.ROUND_JOIN, 4)
        p.convertConicsToQuads(0.05)
        out.addPath(p)
    out.simplify(fix_winding=True, keep_starting_points=False)
    return out

def rot180(strokes, cx, cy):
    res = []
    for b in strokes:
        nb = B(b.width); nb.p = b.p.transform(-1, 0, 0, -1, 2 * cx, 2 * cy); res.append(nb)
    return res

def mirror_x(strokes, cx):
    res = []
    for b in strokes:
        nb = B(b.width); nb.p = b.p.transform(-1, 0, 0, 1, 2 * cx, 0); res.append(nb)
    return res

G = {}   # char -> list of strokes (centre-line, any x origin)
NOTES = {}

# ------------------------------------------------------------------ capitals
def bowl_right(x0, y_top, y_bot, bx, rx):
    """top-to-bottom D-like bowl starting/ending at stem x0"""
    cy = (y_top + y_bot) / 2; ry = (y_top - y_bot) / 2
    return B().m(x0, y_top).l(bx, y_top).arc(bx, cy, rx, ry, 90, -90).l(x0, y_bot)

G['A'] = lambda: [_poly([(0, Bt), (270, T), (540, Bt)], 60), line(95, 210, 445, 210)]
G['B'] = lambda: [line(0, Bt, 0, T), bowl_right(0, T, 372, 230, 190), bowl_right(0, 372, Bt, 240, 205)]
G['C'] = lambda: [arcs(290, M, 280, 320, 38, 322)]
G['D'] = lambda: [bowl_right(0, T, Bt, 130, 290), line(0, Bt, 0, T)]
G['E'] = lambda: [_poly([(440, T), (0, T), (0, Bt), (440, Bt)], 40), line(0, M, 380, M)]
G['F'] = lambda: [_poly([(430, T), (0, T), (0, Bt)], 40), line(0, 330, 370, 330)]
G['G'] = lambda: [arcs(290, M, 280, 320, 38, 360).l(295, M)]
G['H'] = lambda: [line(0, T, 0, Bt), line(480, T, 480, Bt), line(0, M, 480, M)]
G['I'] = lambda: [line(0, T, 0, Bt), line(-95, T, 95, T), line(-95, Bt, 95, Bt)]
G['J'] = lambda: [B().m(330, T).l(330, 200).arc(165, 200, 165, 170, 0, -170)]
G['K'] = lambda: [line(0, T, 0, Bt), _poly([(470, T), (0, 290)], 1), line(130, 410, 470, Bt)]
G['L'] = lambda: [_poly([(0, T), (0, Bt), (400, Bt)], 40)]
G['M'] = lambda: [_poly([(0, Bt), (0, T), (310, 230), (620, T), (620, Bt)], 60)]
G['N'] = lambda: [_poly([(0, Bt), (0, T), (490, Bt), (490, T)], 50)]
G['O'] = lambda: [ell(290, M, 280, 320)]
G['P'] = lambda: [line(0, Bt, 0, T), bowl_right(0, T, 295, 225, 195)]
G['Q'] = lambda: [ell(290, M, 280, 320), line(360, 130, 520, -45)]
G['R'] = lambda: [line(0, Bt, 0, T), bowl_right(0, T, 295, 215, 195), _poly([(200, 295), (260, 220), (470, Bt)], 40)]
def _S(cx, ytop, ybot, rxt, rxb, ymid=None, ta=32, ba=-148):
    ymid = ymid if ymid is not None else (ytop + ybot) / 2
    rt = (ytop - ymid) / 2; rb = (ymid - ybot) / 2
    return B().arc(cx, ymid + rt, rxt, rt, ta, 270).arc(cx, ymid - rb, rxb, rb, 90, ba)
G['S'] = lambda: [_S(240, T, Bt, 215, 235, 350, 32, -150)]
G['T'] = lambda: [line(0, T, 500, T), line(250, T, 250, Bt)]
G['U'] = lambda: [B().m(0, T).l(0, 260).arc(240, 260, 240, 230, 180, 360).l(480, T)]
G['V'] = lambda: [_poly([(0, T), (270, Bt), (540, T)], 60)]
G['W'] = lambda: [_poly([(0, T), (170, Bt), (340, 560), (510, Bt), (680, T)], 70)]
G['X'] = lambda: [line(0, T, 500, Bt), line(500, T, 290, 395), line(210, 305, 0, Bt)]
G['Y'] = lambda: [_poly([(0, T), (250, 330)], 1), line(500, T, 250, 330), line(250, 330, 250, Bt)]
G['Z'] = lambda: [_poly([(0, T), (460, T), (0, Bt), (470, Bt)], 36)]

# ------------------------------------------------------------------ lowercase
RX = 205.0; BY = (XT + Bt) / 2; RY = (XT - Bt) / 2     # bowl centre-line radii
def bowl(cx): return ell(cx, BY, RX, RY)
G['a'] = lambda: [bowl(RX), line(2 * RX, XT, 2 * RX, Bt)]
G['b'] = lambda: [line(0, ASC, 0, Bt), bowl(RX)]
G['c'] = lambda: [arcs(RX, BY, RX, RY, 42, 318)]
G['d'] = lambda: [line(2 * RX, ASC, 2 * RX, Bt), bowl(RX)]
G['e'] = lambda: [B().m(0, BY + 10).l(2 * RX, BY + 10).arc(RX, BY, RX, RY, 2.5, 322)]
G['f'] = lambda: [B().m(0, Bt).l(0, 520).arc(170, 520, 170, 170, 180, 60), line(-110, XT, 190, XT)]
G['g'] = lambda: [bowl(RX), B().m(2 * RX, XT).l(2 * RX, -20).arc(2 * RX - 150, -20, 150, 145, 0, -155)]
def arch(x0, rx, base=Bt):
    return B().m(x0, 300).arc(x0 + rx, 300, rx, XT - 300, 180, 0).l(x0 + 2 * rx, base)
G['h'] = lambda: [line(0, ASC, 0, Bt), arch(0, 190)]
G['i'] = lambda: [line(0, XT, 0, Bt), dot(0, 615)]
G['ı'] = lambda: [line(0, XT, 0, Bt)]
G['j'] = lambda: [B().m(0, XT).l(0, -20).arc(-150, -20, 150, 145, 0, -155), dot(0, 615)]
G['k'] = lambda: [line(0, ASC, 0, Bt), line(280, XT, 0, 225), line(110, 335, 290, Bt)]
G['l'] = lambda: [B().m(0, ASC).l(0, 170).arc(135, 170, 135, 140, 180, 300)]
G['m'] = lambda: [line(0, XT, 0, Bt), arch(0, 140), arch(280, 140)]
G['n'] = lambda: [line(0, XT, 0, Bt), arch(0, 190)]
G['o'] = lambda: [bowl(RX)]
G['p'] = lambda: [line(0, XT, 0, DESC), bowl(RX)]
G['q'] = lambda: [line(2 * RX, XT, 2 * RX, DESC), bowl(RX)]
G['r'] = lambda: [line(0, XT, 0, Bt), B().m(0, 300).arc(150, 300, 150, XT - 300, 180, 50)]
G['s'] = lambda: [_S(150, XT, Bt, 150, 165, 250, 35, -145)]
G['t'] = lambda: [B().m(0, 610).l(0, 160).arc(135, 160, 135, 130, 180, 300), line(-110, XT, 160, XT)]
G['u'] = lambda: [B().m(0, XT).l(0, 250).arc(190, 250, 190, 220, 180, 360), line(380, XT, 380, Bt)]
G['v'] = lambda: [_poly([(0, XT), (200, Bt), (400, XT)], 50)]
G['w'] = lambda: [_poly([(0, XT), (130, Bt), (260, 400), (390, Bt), (520, XT)], 50)]
G['x'] = lambda: [line(0, XT, 380, Bt), line(380, XT, 225, 275), line(155, 225, 0, Bt)]
G['y'] = lambda: [line(0, XT, 175, 100), B().m(360, XT).l(130, DESC)]
G['z'] = lambda: [_poly([(0, XT), (360, XT), (0, Bt), (370, Bt)], 30)]

# ------------------------------------------------------------------ digits
G['0'] = lambda: [ell(225, M, 215, 320), line(130, 250, 320, 450)]
G['1'] = lambda: [_poly([(-150, 520), (0, T), (0, Bt)], 30)]
G['2'] = lambda: [B().arc(230, 490, 225, 180, 165, -38).l(0, Bt + 25).l(0, Bt).l(460, Bt)]
G['3'] = lambda: [B().arc(220, 505, 205, 165, 150, -100), B().arc(225, 190, 235, 160, 100, -152)]
G['4'] = lambda: [_poly([(350, Bt), (350, T), (0, 200), (470, 200)], 36)]
G['5'] = lambda: [B().m(430, T).l(50, T).l(55, 335).arc(235, 215, 235, 185, 138, -150)]
G['6'] = lambda: [arcs(300, 350, 300, 320, 62, 180).l(0, 235), ell(225, 235, 225, 205)]
G['7'] = lambda: [_poly([(0, T), (450, T), (130, Bt)], 40)]
G['8'] = lambda: [ell(215, 513, 185, 157, 270), ell(215, 195, 215, 165, 90)]
G['9'] = lambda: rot180(G['6'](), 225, 350)

# ------------------------------------------------------------------ punctuation
G[' '] = lambda: []
G['.'] = lambda: [dot(0, Bt)]
G[','] = lambda: [B().m(0, Bt).q(0, -30, -45, -100)]
G['!'] = lambda: [line(0, T, 0, 250), dot(0, Bt)]
G['?'] = lambda: [B().arc(205, 495, 205, 175, 168, -40).q(205 + 110, 335, 205, 290).l(205, 245), dot(205, Bt)]
G["'"] = lambda: [line(0, T, 0, 520)]
G['"'] = lambda: [line(0, T, 0, 520), line(110, T, 110, 520)]
G['‘'] = lambda: rot180(G['’'](), 0, 600)
G['’'] = lambda: [dot(0, 635), B().m(0, 635).q(0, 585, -45, 525)]
G['“'] = lambda: (G['‘']() + [shift(b, 110) for b in G['‘']()])
G['”'] = lambda: (G['’']() + [shift(b, 110) for b in G['’']()])
def shift(b, dx, dy=0):
    nb = B(b.width); nb.p = b.p.transform(1, 0, 0, 1, dx, dy); return nb
G['-'] = lambda: [line(0, 330, 240, 330)]
G['–'] = lambda: [line(0, 330, 400, 330)]
G['—'] = lambda: [line(0, 330, 720, 330)]
G[':'] = lambda: [dot(0, Bt), dot(0, XT - 10)]
G[';'] = lambda: [dot(0, XT - 10), B().m(0, Bt).q(0, -30, -45, -100), dot(0, Bt)]
G['&'] = lambda: [B().m(460, Bt).l(105, 493).arc(200, 545, 105, 123, 205, -50).l(55, 170)
                  .arc(200, 170, 145, 138, 180, 405)]
G['('] = lambda: [arcs(330, 320, 300, 440, 128, 232)]
G[')'] = lambda: [arcs(-30, 320, 300, 440, 52, -52)]
G['/'] = lambda: [line(0, -70, 300, 740)]
G['\\'] = lambda: [line(0, 740, 300, -70)]
G['['] = lambda: [_poly([(200, 730), (0, 730), (0, -110), (200, -110)], 30)]
G[']'] = lambda: [_poly([(0, 730), (200, 730), (200, -110), (0, -110)], 30)]
G['{'] = lambda: [B().m(190, 730).q(100, 730, 100, 640).l(100, 450).q(100, 350, 10, 350)
                  .q(100, 350, 100, 250).l(100, 60).q(100, -30, 190, -30)]
G['}'] = lambda: mirror_x(G['{'](), 100)
G['|'] = lambda: [line(0, -170, 0, 770)]
G['#'] = lambda: [line(120, 100, 150, 600), line(320, 100, 350, 600), line(30, 230, 440, 230), line(30, 470, 440, 470)]
G['@'] = lambda: [ell(285, 295, 100, 110), B().m(385, 395).l(385, 215).c(385, 160, 470, 175, 540, 140),
                  B().arc(285, 300, 300, 320, -28, 305)]
G['%'] = lambda: [ell(105, 560, 85, 90), ell(425, 140, 85, 90), line(480, 700, 50, -10)]
G['+'] = lambda: [line(0, 350, 300, 350), line(150, 200, 150, 500)]
G['='] = lambda: [line(0, 270, 340, 270), line(0, 430, 340, 430)]
G['$'] = lambda: [_S(220, 600, 100, 190, 210, 350, 32, -150), line(215, 760, 215, 600), line(215, 100, 215, -60)]
G['*'] = lambda: [line(math.cos(a) * -110, 540 + math.sin(a) * -110, math.cos(a) * 110, 540 + math.sin(a) * 110)
                  for a in (math.radians(90), math.radians(30), math.radians(150))]
G['…'] = lambda: [dot(0, Bt), dot(150, Bt), dot(300, Bt)]
G['_'] = lambda: [line(0, -60, 520, -60)]
G['~'] = lambda: [B().m(0, 320).c(60, 440, 140, 440, 205, 355).c(270, 270, 350, 270, 410, 390)]
G['^'] = lambda: [_poly([(0, 440), (170, 660), (340, 440)], 30)]
G['<'] = lambda: [_poly([(270, 590), (0, 350), (270, 110)], 25)]
G['>'] = lambda: [_poly([(0, 590), (270, 350), (0, 110)], 25)]
G['`'] = lambda: [line(0, 700, 80, 590)]
G['¡'] = lambda: [line(0, 440, 0, Bt), dot(0, 640)]
G['¿'] = lambda: rot180(G['?'](), 205, 350)
G['Ø'] = lambda: [ell(290, M, 280, 320), line(110, 90, 470, 610)]
G['ø'] = lambda: [bowl(RX), line(90, 110, 320, 390)]
G['Æ'] = lambda: [line(0, Bt, 330, T), line(330, T, 330, Bt), _poly([(780, T), (330, T)], 1),
                  line(330, M, 700, M), line(330, Bt, 780, Bt), line(115, 190, 330, 190)]
G['æ'] = lambda: [ell(170, BY, 170, RY), line(340, XT, 340, Bt),
                  B().m(340, BY + 10).l(680, BY + 10).arc(510, BY, 170, RY, 3, 322)]
G['ß'] = lambda: [B().m(0, Bt).l(0, 540).arc(165, 540, 165, 150, 180, -50).l(150, 380)
                  .arc(185, 205, 185, 165, 105, -145)]

# ------------------------------------------------------------------ accent marks
def marks(kind, cx, base_b, is_upper):
    top = base_b[3] if kind != 'cedilla' else 0
    y0 = top + 85
    if kind == 'acute': st = [line(cx - 28, y0, cx + 36, y0 + 70)]
    elif kind == 'grave': st = [line(cx + 28, y0, cx - 36, y0 + 70)]
    elif kind == 'circ': st = [_poly([(cx - 52, y0), (cx, y0 + 60), (cx + 52, y0)], 20)]
    elif kind == 'tilde':
        st = [B().m(cx - 60, y0 + 15).c(cx - 35, y0 + 75, cx - 12, y0 + 75, cx, y0 + 40)
              .c(cx + 12, y0 + 5, cx + 35, y0 + 5, cx + 60, y0 + 65)]
    elif kind == 'diaer': st = [dot(cx - 52, y0 + 18), dot(cx + 52, y0 + 18)]
    elif kind == 'ring':
        b = ell(cx, y0 + 40, 40, 40); b.width = 44; st = [b]
    elif kind == 'cedilla':
        st = [B().m(cx - 12, 15).c(cx + 40, 0, cx + 62, -50, cx + 10, -105)]
    return stroke_all(st)

SB = {  # side bearings (ink to advance edge); default 78
    'round': 62, 'diag': 22, 'default': 78}
ROUND = set('CGOQScdeoq0368@%$')
ROUND_L = set('cegosOCGQ0689')
DIAG = set('AVWXYvwxy/\\')
def sb_for(ch):
    if ch in DIAG: return 24
    if ch in 'T': return 34
    if ch in ROUND: return 62
    if ch in '.,:;\'"‘’“”!¡|': return 90
    if ch in '…': return 70
    if ch in '-–—_': return 62
    return 78

def build():
    glyphs, cmap, order = {}, {}, []
    raw = {}
    for ch, fn in G.items():
        sts = fn()
        path = stroke_all(sts) if sts else pathops.Path()
        raw[ch] = path
    glyphs['.notdef'] = (rect_notdef(), 600)
    for ch in raw:
        path = raw[ch]
        gn = K.gname(ch)
        if ch == ' ':
            glyphs[gn] = (pathops.Path(), 320); cmap[32] = gn; order.append(gn); continue
        b = path.bounds
        sb = sb_for(ch)
        # optical tweak for punctuation sitting left of origin
        dx = sb - b[0]
        p = path.transform(1, 0, 0, 1, dx, 0)
        adv = (b[2] - b[0]) + 2 * sb
        glyphs[gn] = (p, adv)
        if ch != 'ı' or True: cmap[ord(ch)] = gn
        order.append(gn)
    cmap[0xA0] = K.gname(' ')
    K.compose_accents(glyphs, marks, cmap)
    order = ['.notdef'] + [n for n in glyphs if n != '.notdef']
    return glyphs, cmap, order

def rect_notdef():
    p = pathops.Path()
    p.moveTo(60, 0); p.lineTo(60, 700); p.lineTo(500, 700); p.lineTo(500, 0); p.close()
    p.moveTo(110, 50); p.lineTo(450, 50); p.lineTo(450, 650); p.lineTo(110, 650); p.close()
    return p

KERN_CHARS = [c for c in (K.BASIC + list('‘’“”–—…¡¿')) if c != ' ']

def main():
    meta = {'description': 'Original monoline neon-tube display face generated with an arc/line centre-line pen model.'}
    glyphs, cmap, order = build()
    tmp = OUT + '.tmp.ttf'
    K.build_ttf(tmp, FAMILY, PS, glyphs, cmap, meta, order=order)
    # auto kern: bring over-wide pairs towards the typical stem-to-stem gap
    def tgt(a, b): return 175
    kern = K.auto_kern(tmp, KERN_CHARS, tgt, max_kern=150, tol=18, window_units=45,
                       loosen_below=None, skip_pair=lambda a, b: False)
    # expand to accented variants
    rev = {}
    for ch, (base, kind) in K.ACCENT_SPEC.items(): rev.setdefault(base, []).append(ch)
    rev['i'] = ['i']
    gk = {}
    def variants(c):
        v = [c] + rev.get(c, [])
        if c == 'i': v = ['i', 'ı']
        return v
    for (a, b), v in kern.items():
        for aa in variants(a):
            for bb in variants(b):
                if aa in cmap.values(): pass
                ga, gb = K.gname(aa), K.gname(bb)
                if ga in glyphs and gb in glyphs: gk[(ga, gb)] = v
    K.build_ttf(OUT, FAMILY, PS, glyphs, cmap, meta, kern_pairs=gk, order=order)
    os.remove(tmp)
    print('built', OUT, 'kern pairs', len(gk))
    size = K.make_specimen(OUT, os.path.join(HERE, 'specimen.png'), 'Lyra Neon Drawn - Regular')
    problems, info = K.verify(OUT)
    print('specimen', size); print('problems:', problems); print(info)

if __name__ == '__main__':
    main()
