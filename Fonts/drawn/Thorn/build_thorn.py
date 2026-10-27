#!/usr/bin/env python3
"""Lyra Thorn Drawn - gothic barbed capitals (small-cap lowercase) built with a simulated
broad-nib pen: width follows the stroke direction (thick verticals, hairline horizontals),
strokes taper to thorn points, barbs are tapered curved spikes. Ribbons are merged with
skia-pathops and re-fitted to smooth cubic curves, then converted to quadratics.
Run:  /tmp/fontvenv/bin/python build_thorn.py
"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pathops
import lyra_fontkit as K
import nibkit as N

HERE = os.path.dirname(os.path.abspath(__file__))
FAMILY, PS = 'Lyra Thorn Drawn', 'LyraThornDrawn-Regular'
OUT = os.path.join(HERE, 'LyraThornDrawn-Regular.ttf')

THICK, THIN = 84.0, 32.0
NIB = math.radians(12)
SC_H = 546.0                      # small-cap height (78 % of 700)

class Gb:
    def __init__(s, sx=1.0, sy=1.0, wm=1.0):
        s.sx, s.sy, s.wm, s.polys, s.bs = sx, sy, wm, [], 1.25
    def P(s, pts): return [(x * s.sx, y * s.sy) for x, y in pts]
    def stroke(s, pts, t0=0, t1=0, nib=NIB, w=None, thick=None, thin=None, closed=False):
        pts = s.P(pts)
        th = (thick or THICK) * s.wm; tn = (thin or THIN) * s.wm
        def wf(sv, L, phi):
            base = w * s.wm if w else tn + (th - tn) * abs(math.sin(phi - nib))
            f = 1.0
            if t0: f = min(f, (sv / t0) ** 0.9)
            if t1: f = min(f, ((L - sv) / t1) ** 0.9)
            return max(base * f, 1.6)
        s.polys += N.ribbon(pts, wf, closed)
    def line(s, p0, p1, **k): s.stroke(N.line_pts(p0, p1), **k)
    def arc(s, cx, cy, rx, ry, a0, a1, **k): s.stroke(N.arc_pts(cx, cy, rx, ry, a0, a1), **k)
    def ell(s, cx, cy, rx, ry, **k): s.stroke(N.arc_pts(cx, cy, rx, ry, 90, 450)[:-1], closed=True, **k)
    def curve(s, *pieces, **k): s.stroke(N.join(*pieces), **k)
    def barb(s, x, y, ang, length, w=32, curl=0, p=1.15):
        length *= s.bs; w *= 1.0 + (s.bs - 1) * 0.8
        pts = [(x, y)]; a = math.radians(ang); n = 14; st = length / n
        for i in range(n):
            a += math.radians(curl) / n
            x += math.cos(a) * st; y += math.sin(a) * st; pts.append((x, y))
        pts = s.P(pts)
        def wf(sv, L, phi): return max(w * s.wm * (1 - sv / L) ** p, 1.6)
        s.polys += N.ribbon(pts, wf)
    def stem(s, x, y0, y1, tb=95, tt=70, **k):
        s.line((x, y0), (x, y1), t0=tb, t1=tt, **k)
    def bar(s, x0, x1, y, t0=0, t1=0, **k): s.line((x0, y), (x1, y), t0=t0, t1=t1, **k)
    def path(s):
        return N.polys_to_path(s.polys)

# ---------------------------------------------------------------- helpers (cap space, H = 700)
def stemL(g, x, y0=0, y1=700, barb=True):
    g.stem(x, y0, y1)
    if barb: g.barb(x - 30, y0 + (y1 - y0) * 0.60, 212, 85, 30, curl=28)
def stemR(g, x, y0=0, y1=700, barb=True):
    g.stem(x, y0, y1)
    if barb: g.barb(x + 30, y0 + (y1 - y0) * 0.60, 328, 85, 30, curl=-28)
def bowl(g, x0, yt, yb, dx, rx, **k):
    cy = (yt + yb) / 2; ry = (yt - yb) / 2
    g.curve(N.line_pts((x0, yt), (x0 + dx, yt)), N.arc_pts(x0 + dx, cy, rx, ry, 90, -90), N.line_pts((x0 + dx, yb), (x0, yb)), **k)
def endbarb_down(g, x, y, L=90): g.barb(x, y - 8, 262, L, 28, curl=-22)
def endbarb_up(g, x, y, L=90): g.barb(x, y + 8, 82, L, 28, curl=22)

G = {}
# ---------------------------------------------------------------- capitals
def _A(g):
    g.line((0, 0), (270, 700), t0=95, nib=NIB)
    g.line((270, 700), (540, 0), t1=95)
    g.bar(115, 430, 225, 50, 50)
    g.barb(95, 270, 165, 80, 28, curl=-25)
G['A'] = _A
def _B(g):
    stemL(g, 0)
    bowl(g, 0, 685, 372, 170, 175)
    bowl(g, 0, 372, 15, 190, 195)
G['B'] = _B
def _C(g):
    g.arc(275, 350, 255, 335, 38, 322, t0=120, t1=120)
    g.barb(255, 698, 5, 0.1, 1)  # no-op placeholder
G['C'] = lambda g: g.arc(275, 350, 255, 335, 36, 324, t0=130, t1=130)
def _D(g):
    stemL(g, 0)
    g.curve(N.line_pts((0, 685), (110, 685)), N.arc_pts(110, 350, 300, 335, 90, -90), N.line_pts((110, 15), (0, 15)))
G['D'] = _D
def _E(g):
    stemL(g, 0)
    g.bar(0, 400, 685, 0, 70); endbarb_down(g, 395, 685)
    g.bar(0, 320, 365, 0, 70)
    g.bar(0, 420, 15, 0, 70); endbarb_up(g, 415, 15)
G['E'] = _E
def _F(g):
    stemL(g, 0)
    g.bar(0, 400, 685, 0, 70); endbarb_down(g, 395, 685)
    g.bar(0, 320, 365, 0, 70)
G['F'] = _F
def _G(g):
    g.arc(275, 350, 255, 335, 36, 360, t0=130)
    g.bar(300, 530, 350, 0, 60)
    g.barb(530, 345, 270, 120, 40, curl=0)
G['G'] = _G
def _H(g):
    stemL(g, 0); stemR(g, 450)
    g.bar(0, 450, 365, 40, 40)
G['H'] = _H
def _I(g):
    g.stem(0, 0, 700)
    g.bar(-85, 85, 685, 55, 55); g.bar(-85, 85, 15, 55, 55)
G['I'] = _I
def _J(g):
    stemR(g, 300, 150, 700, barb=False)
    g.arc(160, 150, 140, 135, 0, -160, t1=110)
G['J'] = _J
def _K(g):
    stemL(g, 0)
    g.line((0, 280), (350, 700), t0=0, t1=60, nib=NIB)
    g.line((95, 395), (400, 0), t1=95)
G['K'] = _K
def _L(g):
    stemL(g, 0)
    g.bar(0, 400, 15, 0, 70); endbarb_up(g, 395, 15)
G['L'] = _L
def _M(g):
    stemL(g, 0, barb=True); stemR(g, 640)
    g.line((0, 700), (320, 60), t1=0, t0=40)
    g.line((320, 60), (640, 700), t0=0, t1=40)
G['M'] = _M
def _N(g):
    stemL(g, 0); stemR(g, 490, barb=True)
    g.line((0, 700), (490, 0), t0=0, t1=0)
G['N'] = _N
G['O'] = lambda g: (g.ell(275, 350, 255, 335), g.barb(275, 690, 90, 0.1, 1) if False else None)
def _P(g):
    stemL(g, 0); bowl(g, 0, 685, 335, 170, 175)
G['P'] = _P
def _Q(g):
    G['O'](g); g.line((330, 130), (500, -70), t1=60, nib=-NIB)
G['Q'] = _Q
def _R(g):
    stemL(g, 0); bowl(g, 0, 685, 335, 170, 175)
    g.line((190, 335), (440, 0), t1=95)
G['R'] = _R
def _S(g):
    g.curve(N.arc_pts(250, 525, 205, 170, 28, 270), N.arc_pts(250, 190, 215, 175, 90, -152), t0=0, t1=0)
    # bevel the terminals with taper by redoing ends
G['S'] = lambda g: g.curve(N.arc_pts(245, 525, 205, 170, 32, 270), N.arc_pts(245, 190, 215, 175, 90, -148), t0=100, t1=100)
def _T(g):
    g.bar(0, 470, 685, 60, 60); endbarb_down(g, 5, 685); endbarb_down(g, 465, 685)
    g.stem(235, 0, 685, 95, 0)
    g.barb(205, 430, 205, 80, 28, curl=26)
G['T'] = _T
def _U(g):
    stemL(g, 0, 190, 700, barb=True); stemR(g, 470, 190, 700, barb=True)
    g.arc(235, 190, 235, 175, 180, 360, nib=NIB)
G['U'] = _U
def _V(g):
    g.line((0, 700), (260, 0), t0=60); g.line((260, 0), (520, 700), t1=60)
    g.barb(85, 450, 200, 75, 28, curl=26)
G['V'] = _V
def _W(g):
    g.line((0, 700), (190, 0), t0=60); g.line((190, 0), (360, 600), t0=0, t1=0)
    g.line((360, 600), (530, 0), t0=0, t1=0); g.line((530, 0), (720, 700), t1=60)
G['W'] = _W
def _X(g):
    g.line((0, 700), (480, 0), t0=70, t1=70); g.line((480, 700), (0, 0), t0=70, t1=70)
G['X'] = _X
def _Y(g):
    g.line((0, 700), (240, 330), t0=60); g.line((480, 700), (240, 330), t0=60)
    g.stem(240, 0, 340, 95, 0)
G['Y'] = _Y
def _Z(g):
    g.bar(0, 440, 685, 0, 60); endbarb_down(g, 435, 685)
    g.line((440, 685), (10, 15), nib=-NIB, t0=0, t1=0)
    g.bar(0, 460, 15, 60, 0); endbarb_up(g, 5, 15)
G['Z'] = _Z

# ---------------------------------------------------------------- digits
def _0(g):
    g.ell(205, 350, 190, 335); g.line((120, 200), (290, 500), t0=40, t1=40, w=26)
G['0'] = _0
def _1(g):
    g.stem(130, 0, 700, 95, 40)
    g.barb(115, 690, 205, 200, 40, curl=35)
    g.bar(10, 250, 15, 50, 50)
G['1'] = _1
def _2(g):
    g.curve(N.arc_pts(215, 510, 185, 175, 158, -30), N.line_pts((300, 405), (20, 20)), t0=70)
    g.bar(20, 430, 15, 0, 70); endbarb_up(g, 425, 15)
G['2'] = _2
def _3(g):
    g.arc(200, 520, 175, 165, 150, -100, t0=60)
    g.arc(205, 190, 205, 180, 100, -150, t1=60)
G['3'] = _3
def _4(g):
    g.stem(310, 0, 700, 95, 0)
    g.line((310, 700), (0, 200), t0=0, t1=0)
    g.bar(0, 430, 200, 30, 40)
G['4'] = _4
def _5(g):
    g.bar(80, 420, 685, 0, 60); endbarb_down(g, 415, 685, 70)
    g.line((70, 685), (50, 385), nib=NIB)
    g.arc(215, 215, 200, 195, 130, -150, t1=90)
G['5'] = _5
def _6(g):
    g.curve(N.bez_pts((370, 690), (160, 710), (12, 540), (12, 250)), t0=80)
    g.ell(215, 215, 200, 205)
G['6'] = _6
def _7(g):
    g.bar(0, 430, 685, 0, 60); endbarb_down(g, 425, 685)
    g.line((430, 685), (130, 0), nib=-NIB, t1=90)
G['7'] = _7
def _8(g):
    g.ell(200, 525, 150, 160); g.ell(200, 190, 185, 175)
G['8'] = _8
def _9(g):
    gg = Gb(g.sx, g.sy, g.wm)
    _6(gg)
    for poly in gg.polys:
        g.polys.append([(g.sx * 430 - x, g.sy * 700 - y) for x, y in poly][::-1])
G['9'] = _9

# ---------------------------------------------------------------- specials
def _AE(g):
    g.line((0, 0), (340, 700), t0=95)
    g.stem(340, 0, 700, 95, 0)
    g.bar(340, 720, 685, 0, 70); endbarb_down(g, 715, 685)
    g.bar(340, 620, 365, 0, 70)
    g.bar(340, 740, 15, 0, 70); endbarb_up(g, 735, 15)
    g.bar(120, 340, 225, 50, 0)
G['Æ'] = _AE
def _O_slash(g):
    G['O'](g); g.line((70, 60), (480, 640), t0=60, t1=60, nib=-NIB)
G['Ø'] = _O_slash
def _ss(g):
    stemL(g, 0)
    bowl(g, 0, 685, 372, 150, 170)
    g.curve(N.line_pts((0, 372), (150, 372)), N.arc_pts(160, 190, 190, 175, 90, -140), t1=95)
G['ß'] = _ss
G['ı'] = G['I']

# ---------------------------------------------------------------- punctuation (cap space)
def spike_down(g, x, ytop, ybot, w=50): g.stroke([(x, ytop), (x, ybot)], t1=ytop - ybot - 2, w=w)
def dot(g, x, y=0, h=92, w=66): g.stroke([(x, y), (x, y + h)], t1=h - 2, w=w, t0=14)
G[' '] = lambda g: None
G['.'] = lambda g: dot(g, 0)
G[','] = lambda g: (dot(g, 0), g.barb(0, 8, 262, 110, 44, curl=28))
G['!'] = lambda g: (g.stroke([(0, 700), (0, 215)], t1=470, w=64, t0=18), dot(g, 0))
def _q(g):
    g.curve(N.arc_pts(190, 510, 175, 170, 160, -30, ), N.bez_pts((300, 405), (240, 340), (200, 330), (200, 250)), t0=60, t1=0)
    dot(g, 200)
G['?'] = _q
G["'"] = lambda g: spike_down(g, 0, 700, 545)
G['"'] = lambda g: (spike_down(g, 0, 700, 545), spike_down(g, 120, 700, 545))
G['’'] = lambda g: (g.stroke([(0, 700), (0, 640)], w=52, t0=14) if False else None, g.barb(10, 700, 262, 150, 50, curl=-40))[0]
G['‘'] = lambda g: g.barb(-10, 545, 98, 150, 50, curl=40)
G['“'] = lambda g: (G['‘'](g), (lambda: g.barb(110, 545, 98, 150, 50, curl=40))())[0]
G['”'] = lambda g: (G['’'](g), (lambda: g.barb(130, 700, 262, 150, 50, curl=-40))())[0]
G['-'] = lambda g: g.stroke(N.line_pts((0, 330), (210, 330)), w=34, t0=40, t1=40)
G['–'] = lambda g: g.stroke(N.line_pts((0, 330), (380, 330)), w=34, t0=60, t1=60)
G['—'] = lambda g: g.stroke(N.line_pts((0, 330), (720, 330)), w=34, t0=80, t1=80)
G[':'] = lambda g: (dot(g, 0), dot(g, 0, 330))
G[';'] = lambda g: (dot(g, 0, 330), dot(g, 0), g.barb(0, 8, 262, 110, 44, curl=28))
def _amp(g):
    g.curve(N.line_pts((470, 0), (130, 440)), N.arc_pts(210, 540, 100, 150, 220, -50), N.line_pts((300, 470), (60, 190)),
            N.arc_pts(215, 190, 160, 175, 180, 400), t0=70)
G['&'] = _amp
def _par_l(g): g.arc(330, 320, 300, 460, 125, 235, t0=100, t1=100)
G['('] = _par_l
G[')'] = lambda g: g.arc(-30, 320, 300, 460, 55, -55, t0=100, t1=100)
G['/'] = lambda g: g.line((0, -70), (320, 760), t0=70, t1=70, nib=-NIB)
G['\\'] = lambda g: g.line((0, 760), (320, -70), t0=70, t1=70)
def _brk(g, right=False):
    xs = (200, 0) if not right else (0, 200)
    g.curve(N.line_pts((xs[0], 740), (xs[1], 740)), N.line_pts((xs[1], 740), (xs[1], -120)), N.line_pts((xs[1], -120), (xs[0], -120)), t0=0, t1=0, thick=60)
G['['] = lambda g: _brk(g, False)
G[']'] = lambda g: _brk(g, True)
def _brace(g, right=False):
    sg = 1 if not right else -1
    def X(x): return (x if not right else 200 - x)
    g.curve(N.bez_pts((X(190), 740), (X(100), 740), (X(100), 700), (X(100), 640)), N.line_pts((X(100), 640), (X(100), 440)),
            N.bez_pts((X(100), 440), (X(100), 380), (X(70), 360), (X(10), 350)), t0=0, t1=40)
    g.curve(N.bez_pts((X(10), 350), (X(70), 340), (X(100), 320), (X(100), 260)), N.line_pts((X(100), 260), (X(100), 60)),
            N.bez_pts((X(100), 60), (X(100), 0), (X(100), -40), (X(190), -40)), t0=40)
G['{'] = lambda g: _brace(g, False)
G['}'] = lambda g: _brace(g, True)
G['|'] = lambda g: g.stroke([(0, -170), (0, 780)], t0=100, t1=100)
G['#'] = lambda g: (g.line((110, 60), (150, 640), t0=30, t1=30), g.line((310, 60), (350, 640), t0=30, t1=30),
                    g.bar(20, 440, 240, 40, 40), g.bar(20, 440, 460, 40, 40))
G['@'] = lambda g: (g.ell(270, 300, 100, 110), g.stroke(N.join(N.line_pts((370, 400), (370, 200)), N.bez_pts((370, 200), (370, 150), (450, 170), (520, 140))), t1=0),
                    g.arc(270, 300, 290, 330, -30, 300, t0=0, t1=90))
G['%'] = lambda g: (g.ell(100, 570, 80, 95), g.ell(400, 130, 80, 95), g.line((470, 700), (30, 0), nib=-NIB, t0=50, t1=50))
G['+'] = lambda g: (g.bar(0, 300, 350, 50, 50), g.stroke([(150, 200), (150, 500)], t0=50, t1=50))
G['='] = lambda g: (g.bar(0, 340, 270, 50, 50), g.bar(0, 340, 430, 50, 50))
G['$'] = lambda g: (G['S'](g), g.stroke([(235, 790), (235, -90)], w=26, t0=80, t1=80))
G['*'] = lambda g: [g.stroke([(math.cos(a) * -120, 540 + math.sin(a) * -120), (math.cos(a) * 120, 540 + math.sin(a) * 120)], w=40, t0=60, t1=60)
                    for a in (math.radians(90), math.radians(30), math.radians(150))]
G['…'] = lambda g: (dot(g, 0), dot(g, 160), dot(g, 320))
G['_'] = lambda g: g.stroke(N.line_pts((0, -70), (520, -70)), w=30, t0=60, t1=60)
G['~'] = lambda g: g.stroke(N.bez_pts((0, 320), (60, 450), (140, 450), (210, 360)) + N.bez_pts((210, 360), (280, 270), (360, 270), (420, 400)), t0=70, t1=70, w=40)
G['^'] = lambda g: g.curve(N.line_pts((0, 440), (170, 690)), N.line_pts((170, 690), (340, 440)), t0=60, t1=60, nib=NIB)
G['<'] = lambda g: g.curve(N.line_pts((280, 590), (0, 350)), N.line_pts((0, 350), (280, 110)), t0=70, t1=70, w=34)
G['>'] = lambda g: g.curve(N.line_pts((0, 590), (280, 350)), N.line_pts((280, 350), (0, 110)), t0=70, t1=70, w=34)
G['`'] = lambda g: g.barb(0, 720, 300, 110, 44, curl=15)
G['¡'] = lambda g: (g.stroke([(0, 0), (0, 485)], t1=470, w=64, t0=18) if False else g.stroke([(0, -15), (0, 470)], t0=470, w=64), dot(g, 0, 640))
def _inv_q(g):
    gg = Gb(g.sx, g.sy, g.wm); _q(gg)
    for poly in gg.polys: g.polys.append([(g.sx * 400 - x, g.sy * 700 - y) for x, y in poly][::-1])
G['¿'] = _inv_q

# ---------------------------------------------------------------- accent marks
def marks(kind, cx, b, upper):
    top = b[3] if kind != 'cedilla' else 0
    g = Gb(1, 1, 1.0); g.bs = 1.0
    y = top + 62
    if kind == 'acute': g.barb(cx - 35, y, 38, 110, 44, curl=-10)
    elif kind == 'grave': g.barb(cx + 35, y, 142, 110, 44, curl=10)
    elif kind == 'circ':
        g.barb(cx, y + 95, 220, 85, 38, curl=0); g.barb(cx, y + 95, 320, 85, 38, curl=0)
    elif kind == 'tilde':
        g.stroke(N.bez_pts((cx - 70, y + 20), (cx - 40, y + 90), (cx - 12, y + 90), (cx, y + 52)) + N.bez_pts((cx, y + 52), (cx + 12, y + 14), (cx + 40, y + 14), (cx + 70, y + 84)), t0=30, t1=30, w=36)
    elif kind == 'diaer':
        g.stroke([(cx - 48, y + 70), (cx - 48, y)], t0=0, t1=66, w=46); g.stroke([(cx + 48, y + 70), (cx + 48, y)], t1=66, w=46)
    elif kind == 'ring':
        g.ell(cx, y + 48, 34, 44, w=30)
    elif kind == 'cedilla':
        g.barb(cx - 5, 8, 285, 120, 40, curl=-80)
    return N.polys_to_path(g.polys)

# ---------------------------------------------------------------- assembly
def clean(g):
    p = g.path(); p.simplify(fix_winding=True, keep_starting_points=False)
    return N.fit_path(p, err=1.8)

SB = lambda ch: 16 if ch in 'AVWXYT/\\' else (34 if ch in 'COQSGU08()' else 40)

def make(ch, fn, sc):
    g = Gb(0.86, SC_H / 700.0, 0.93) if sc else Gb()
    fn(g)
    return clean(g)

def build():
    glyphs, cmap = {}, {}
    shapes = {}
    for ch, fn in G.items():
        shapes[ch] = (ch, fn, False)
    for c in 'abcdefghijklmnopqrstuvwxyz':
        shapes[c] = (c, G[c.upper()], True)
    shapes['æ'] = ('æ', G['Æ'], True); shapes['ø'] = ('ø', G['Ø'], True)
    shapes['ı'] = ('ı', G['I'], True)
    # 'ß' stays full-height-ish small cap
    for ch, (c, fn, sc) in shapes.items():
        gn = K.gname(ch)
        if ch == ' ': glyphs[gn] = (pathops.Path(), 280); cmap[32] = gn; continue
        if ch == 'ß': sc = True; fn = G['ß']
        p = make(ch, fn, sc)
        b = p.bounds; sb = SB(ch)
        dx = sb - b[0]
        glyphs[gn] = (p.transform(1, 0, 0, 1, dx, 0), (b[2] - b[0]) + 2 * sb)
        cmap[ord(ch)] = gn
    cmap[0xA0] = 'space'
    # accent marks above small caps / caps: composition uses the base ink top
    K.compose_accents(glyphs, marks, cmap)
    glyphs['.notdef'] = (rect_notdef(), 600)
    order = ['.notdef'] + [n for n in glyphs if n != '.notdef']
    return glyphs, cmap, order

def rect_notdef():
    p = pathops.Path()
    p.moveTo(60, 0); p.lineTo(60, 700); p.lineTo(440, 700); p.lineTo(440, 0); p.close()
    p.moveTo(110, 50); p.lineTo(390, 50); p.lineTo(390, 650); p.lineTo(110, 650); p.close()
    return p

KERN_CHARS = [c for c in (K.BASIC + list('‘’“”–—…¡¿')) if c != ' ']

def main():
    meta = {'description': 'Original gothic barbed capitals with small-cap lowercase, generated with a nib-pen model.', 'xheight': 546}
    glyphs, cmap, order = build()
    tmp = OUT + '.tmp.ttf'
    K.build_ttf(tmp, FAMILY, PS, glyphs, cmap, meta, order=order)
    kern = K.auto_kern(tmp, KERN_CHARS, 105, max_kern=140, tol=15, window_units=40)
    rev = {}
    for ch, (base, kind) in K.ACCENT_SPEC.items(): rev.setdefault(base, []).append(ch)
    gk = {}
    def variants(c):
        v = [c] + rev.get(c, [])
        if c == 'i': v = ['i', 'ı']
        return v
    for (a, b), v in kern.items():
        for aa in variants(a):
            for bb in variants(b):
                ga, gb = K.gname(aa), K.gname(bb)
                if ga in glyphs and gb in glyphs: gk[(ga, gb)] = v
    K.build_ttf(OUT, FAMILY, PS, glyphs, cmap, meta, kern_pairs=gk, order=order)
    os.remove(tmp)
    print('built', OUT, 'kern', len(gk))
    size = K.make_specimen(OUT, os.path.join(HERE, 'specimen.png'), 'Lyra Thorn Drawn - Regular')
    problems, info = K.verify(OUT)
    print('specimen', size, 'problems', problems); print(info)

if __name__ == '__main__':
    main()
