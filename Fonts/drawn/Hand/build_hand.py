#!/usr/bin/env python3
"""Lyra Hand generator: casual felt-pen handwriting.
Pen model: slightly oblique elliptical felt tip with pressure taper, swept along Catmull-Rom
skeletons; every glyph point is jittered with a seeded RNG; 10 common letters have two
extra drawn variants (.alt1 / .alt2) cycled by the OpenType 'calt' feature (also exposed as salt/ss01).
Usage: /tmp/fontvenv/bin/python build_hand.py"""
import math, os, sys, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fontkit import *

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = 'Lyra Hand'
class Ctx:
    pen = ellipse_pen(33, 28, 30, 18)
    step = 8
ctx = Ctx()
P2 = ellipse_pen(28, 24, 30, 16)
PT = ellipse_pen(26, 22, 30, 14)
mk = lambda: Gb(ctx)
SLANT = 0.07

def press(pts):
    n = len(pts)
    return [0.82 + 0.24*math.sin(math.pi*min(1, (i+0.5)/n)) for i in range(n)]

class R:
    """per-glyph randomiser / variant transform"""
    def __init__(self, seed, v=0):
        self.r = random.Random(seed); self.v = v
        self.amp = [3.0, 6.0, 6.5][v]
        self.sx = [1.0, 0.94, 1.07][v]; self.rot = [0, -0.05, 0.05][v]
    def pt(self, x, y):
        x = x*self.sx; c, s = math.cos(self.rot), math.sin(self.rot)
        x, y = x*c - y*s, x*s + y*c
        x += self.r.gauss(0, self.amp); y += self.r.gauss(0, self.amp)
        return x + SLANT*y, y

def K(rr, *pts):
    """spline stroke spec through points"""
    p = [rr.pt(*q) for q in pts]
    return "M %.1f %.1f K " % p[0] + " ".join("%.1f %.1f" % q for q in p[1:])

def ov(cx, cy, rx, ry, a0, a1, n=9):
    return [(cx + rx*math.cos(math.radians(a0 + (a1-a0)*i/(n-1))), cy + ry*math.sin(math.radians(a0 + (a1-a0)*i/(n-1)))) for i in range(n)]

def draw(g, rr, *strokes, pen=None):
    for s in strokes: g.stroke(K(rr, *s), pen=pen, scale=press)
def dotc(g, rr, x, y, r=42):
    cx, cy = rr.pt(x, y); g.poly(circle_pts(cx + rr.r.uniform(-4, 6), cy, r, 22))

def letter(ch, v, seed):
    rr = R(seed, v); g = mk(); b = 0
    o = lambda cx=130, cy=250, rx=108, ry=222, a0=80, a1=450: ov(cx, cy, rx, ry, a0, a1, 11)
    if ch == 'o': draw(g, rr, o(a0=75 + 15*v, a1=440 + 10*v))
    elif ch == 'a':
        draw(g, rr, o(a0=70, a1=430), [(252, 470), (256, 300), (254, 120), (262, 45)] + ([(296, 32)] if v != 1 else [(290, 20)]))
    elif ch == 'd': draw(g, rr, o(a0=70, a1=430), [(255, 735 - 25*v), (256, 500), (256, 250), (254, 90), (262, 45), (296, 32)])
    elif ch == 'b': draw(g, rr, [(30, 735), (22, 500), (14, 250), (15, 40)], ov(140, 250, 112, 222, 190, -170, 11))
    elif ch == 'p': draw(g, rr, [(28, 480), (22, 250), (18, -90), (20, -190)], ov(140, 250, 112, 222, 190, -170, 11))
    elif ch == 'q': draw(g, rr, o(a0=70, a1=430), [(255, 480), (258, 200), (256, -90), (262, -190)])
    elif ch == 'c': draw(g, rr, ov(135, 250, 112, 222, 40, 325, 10))
    elif ch == 'e':
        draw(g, rr, [(30, 245 + 15*v), (130, 262), (232, 300 + 10*v)] + ov(130, 250, 108, 225, 20, 335 - 12*v, 10)[1:])
    elif ch == 'f': draw(g, rr, [(228, 690), (160, 745), (100, 690), (88, 520), (85, 250), (84, 20)], [(5, 480), (90, 485), (180, 492)])
    elif ch == 'g': draw(g, rr, o(a0=70, a1=430), [(255, 480), (258, 200), (250, -60), (190, -165), (80, -180), (20, -130)])
    elif ch == 'h': draw(g, rr, [(22, 735), (18, 400), (18, 20)], [(20, 330), (70, 450), (130, 475), (210, 420), (240, 250), (243, 20)])
    elif ch == 'i':
        draw(g, rr, [(130, 470), (128, 250), (132, 45), (152, 25)]); dotc(g, rr, 135, 650, 34)
    elif ch == 'j':
        draw(g, rr, [(130, 470), (128, 250), (122, -60), (80, -165), (10, -170)]); dotc(g, rr, 135, 650, 34)
    elif ch == 'k': draw(g, rr, [(22, 735), (18, 400), (18, 20)], [(230, 470), (130, 360), (35, 250)], [(80, 290), (160, 150), (250, 25)])
    elif ch == 'l': draw(g, rr, [(80, 740), (74, 500), (70, 250), (76, 45), (110, 22)] if v != 1 else [(82, 740), (74, 500), (70, 250), (80, 50), (105, 25), (130, 40)])
    elif ch == 'm': draw(g, rr, [(20, 480), (18, 250), (18, 20)], [(20, 330), (75, 470), (140, 465), (165, 250), (166, 20)], [(166, 330), (225, 475), (295, 465), (315, 250), (318, 20)])
    elif ch == 'n': draw(g, rr, [(20, 480), (18, 250), (18, 20)], [(20, 335), (75, 470), (150, 470), (215, 400), (240, 250), (243, 20)])
    elif ch == 'r': draw(g, rr, [(20, 480), (18, 250), (18, 20)], [(20, 335), (75, 470), (150, 480), (215, 440 - 10*v)])
    elif ch == 's': draw(g, rr, [(215, 435), (150, 492), (70, 472), (52, 390), (120, 300), (205, 215), (215, 100), (140, 15), (55, 38), (20, 105)])
    elif ch == 't': draw(g, rr, [(95, 650), (88, 300), (95, 60), (150, 22), (210, 48 + 10*v)], [(10, 470), (100, 476 + 6*v), (195, 484)])
    elif ch == 'u': draw(g, rr, [(20, 480), (24, 200), (80, 30), (165, 25), (235, 120), (243, 480)], [(243, 480), (246, 250), (250, 40), (280, 25)])
    elif ch == 'v': draw(g, rr, [(10, 480), (50, 250), (115, 28), (170, 250), (225, 480)])
    elif ch == 'w': draw(g, rr, [(10, 480), (45, 250), (90, 28), (130, 250), (170, 480)], [(170, 480), (210, 250), (255, 28), (290, 250), (330, 480)])
    elif ch == 'x': draw(g, rr, [(20, 480), (130, 250), (240, 25)], [(235, 480), (130, 250), (30, 25)])
    elif ch == 'y': draw(g, rr, [(20, 480), (70, 250), (130, 28), (165, 40)], [(245, 480), (200, 200), (140, -40), (60, -170), (8, -160)])
    elif ch == 'z': draw(g, rr, [(20, 465), (130, 490), (230, 482), (150, 300), (30, 40), (140, 22), (250, 30)])
    elif ch == 'dotlessi': draw(g, rr, [(130, 470), (128, 250), (132, 45), (152, 25)])
    elif ch == 'germandbls':
        draw(g, rr, [(20, 20), (25, 400), (40, 640), (110, 740), (200, 700), (215, 600), (120, 510), (60, 480)], [(120, 490), (230, 430), (245, 250), (200, 60), (100, 20), (40, 70)])
    return g

def capital(ch, seed):
    rr = R(seed, 0); g = mk(); T = 677; B = 23
    c = lambda cx=150, cy=350, rx=132, ry=326, a0=45, a1=315, n=11: ov(cx, cy, rx, ry, a0, a1, n)
    D = {
     'A': [[(20, 25), (150, 685), (280, 25)], [(70, 230), (240, 238)]],
     'B': [[(30, 677), (26, 20)], [(28, 675), (160, 690), (240, 600), (220, 460), (100, 375), (28, 365)], [(110, 365), (250, 300), (270, 150), (160, 30), (28, 25)]],
     'C': [c()], 'D': [[(30, 677), (26, 20)], [(28, 680), (220, 640), (290, 360), (210, 60), (30, 25)]],
     'E': [[(250, 670), (130, 690), (35, 650), (25, 350), (35, 40), (130, 15), (260, 50)], [(40, 360), (160, 375)]],
     'F': [[(30, 25), (28, 677), (150, 685), (260, 670)], [(30, 380), (110, 388), (190, 385)]],
     'G': [c(a1=325), [(275, 300), (215, 296), (160, 300)]],
     'H': [[(30, 677), (26, 20)], [(270, 677), (266, 20)], [(30, 360), (150, 375), (266, 350)]],
     'I': [[(110, 677), (108, 350), (108, 20)], [(40, 680), (110, 685), (180, 678)], [(40, 22), (110, 20), (180, 24)]],
     'J': [[(240, 677), (235, 400), (230, 150), (180, 25), (80, 40), (30, 120)]],
     'K': [[(30, 677), (26, 20)], [(260, 677), (150, 500), (40, 320)], [(110, 390), (190, 220), (265, 20)]],
     'L': [[(30, 677), (28, 350), (28, 25), (150, 28), (270, 30)]],
     'M': [[(25, 25), (35, 677), (160, 150), (285, 677), (290, 25)]],
     'N': [[(25, 25), (30, 677), (150, 350), (260, 25), (268, 677)]],
     'O': [ov(150, 350, 135, 326, 80, 450, 13)],
     'P': [[(30, 677), (26, 20)], [(28, 680), (190, 690), (260, 560), (190, 400), (30, 370)]],
     'Q': [ov(150, 350, 135, 326, 80, 450, 13), [(190, 150), (250, 60), (310, -40)]],
     'R': [[(30, 677), (26, 20)], [(28, 680), (190, 690), (260, 570), (190, 410), (30, 375)], [(110, 375), (180, 250), (270, 25)]],
     'S': [[(250, 610), (180, 680), (80, 665), (40, 570), (120, 430), (230, 330), (260, 190), (190, 50), (80, 30), (25, 100)]],
     'T': [[(20, 670), (150, 680), (280, 675)], [(150, 677), (148, 350), (148, 25)]],
     'U': [[(30, 677), (32, 400), (32, 200), (100, 35), (200, 35), (262, 200), (268, 677)]],
     'V': [[(20, 677), (85, 350), (150, 25), (215, 350), (280, 677)]],
     'W': [[(10, 677), (50, 350), (90, 25), (135, 270), (180, 520), (225, 270), (270, 25), (310, 350), (350, 677)]],
     'X': [[(30, 677), (150, 350), (270, 25)], [(270, 677), (150, 350), (30, 25)]],
     'Y': [[(20, 677), (85, 500), (150, 350), (215, 500), (280, 677)], [(150, 350), (148, 25)]],
     'Z': [[(30, 670), (150, 685), (260, 675), (150, 350), (35, 30), (150, 22), (270, 25)]],
     '0': [ov(130, 350, 105, 326, 80, 450, 13)],
     '1': [[(60, 560), (110, 640), (150, 677), (148, 350), (145, 25)]],
     '2': [[(30, 570), (100, 670), (200, 650), (235, 540), (150, 330), (30, 30), (150, 22), (260, 40)]],
     '3': [[(30, 640), (130, 685), (230, 620), (150, 400), (100, 380)], [(110, 385), (240, 300), (250, 140), (160, 30), (30, 60)]],
     '4': [[(200, 677), (110, 450), (30, 220), (150, 228), (270, 235)], [(205, 500), (205, 250), (205, 25)]],
     '5': [[(240, 670), (140, 668), (50, 665), (35, 400), (150, 430), (250, 330), (240, 120), (130, 25), (30, 70)]],
     '6': [[(230, 670), (110, 560), (40, 300), (40, 120), (130, 25), (230, 90), (230, 250), (130, 350), (40, 260)]],
     '7': [[(30, 670), (150, 680), (260, 675), (180, 350), (110, 25)]],
     '8': [ov(130, 190, 108, 168, 270, 270 + 380, 12), ov(130, 520, 92, 158, 90, 90 + 380, 12)],
     '9': [ov(130, 510, 105, 160, 80, 450, 13), [(235, 500), (228, 300), (190, 150), (120, 40), (50, 25)]],
    }
    draw(g, rr, *D[ch]); return g

def build():
    spec = Spec()
    for ch in LOWER + 'dotlessi'.replace('dotlessi', '') :
        spec.add(gname(ord(ch)), letter(ch, 0, ord(ch)).result(), cp=ord(ch), cat='l')
    spec.add('dotlessi', letter('dotlessi', 0, 301).result(), cp=0x131, cat='l')
    spec.add('germandbls', letter('germandbls', 0, 223).result(), cp=0xDF, cat='l')
    for ch in UPPER + DIGITS:
        spec.add(gname(ord(ch)), capital(ch, ord(ch)).result(), cp=ord(ch), cat='U')
    for ch in ALT:
        for v in (1, 2):
            spec.add('%s.alt%d' % (ch, v), letter(ch, v, ord(ch)*7 + v).result(), cp=None, cat='l')
    for key, g in punct(mk, PP).items():
        spec.add(gname(ord(key)), g.result(), cp=ord(key), cat='p')
    ligature(spec, 'A', 'E', 'AE', 0xC6, 50, 'U')
    ligature(spec, 'a', 'e', 'ae', 0xE6, 12, 'l')
    g = mk(); g.add_contours(spec.g['o']['cs']); g.stroke("M 10 20 L 230 480", pen=P2); spec.add('oslash', g.result(), cp=0xF8, cat='l')
    g = mk(); g.add_contours(spec.g['O']['cs']); g.stroke("M 10 0 L 300 700", pen=P2); spec.add('Oslash', g.result(), cp=0xD8, cat='U')
    spec.add('space', [], cp=0x20, adv=230); spec.add('nbspace', [], cp=0xA0, adv=230)
    g = mk(); g.poly([(60, 0), (440, 0), (440, 700), (60, 700)]); g.cutpoly([(120, 60), (120, 640), (380, 640), (380, 60)])
    spec.add('.notdef', g.result(), sb=(60, 60))
    return spec
ALT = 'aeostrnild'

def dot(g, x, y, s=1.0): g.poly(circle_pts(x + 3, y + 38*s, 38*s, 20))
def tpr(pts):
    n = len(pts); return [1.0 - 0.3*(i/(n-1)) for i in range(n)]
def at_(mk_):
    g = mk_(); g.stroke("E 290 290 275 285 40 355", pen=P2); g.stroke("E 300 285 95 95 0 360", pen=P2); g.stroke("M 395 400 L 395 190 L 440 190 L 480 250", pen=P2); return g
PP = dict(cap=700, xh=500, asc=780, desc=-200, dot=dot, pen2=P2, pen3=PT, dr=60, tail=(35, 100), tailscale=[1.0, 0.8], taper=tpr,
          qspec="M -105 570 C -105 650 -40 682 20 682 C 90 682 130 640 130 570 C 130 480 40 440 20 360 L 20 320", qh=170, qgap=100, tickscale=None,
          dashy=270, hy=170, en=330, em=640, ul=-70, uw=480, ellg=110, my=270, mw=230, eqg=140, ah=150, sl=(-60, 760, 260),
          bw=120, pw=130, tw=260, ty=300, cw=180, star=95, hw=340, hh=640, sw=300, pr=82, pw2=420, at=at_,
          amp="M 330 20 L 230 160 L 140 290 L 110 420 L 125 540 L 180 620 L 235 570 L 230 470 L 170 380 L 100 290 L 60 200 L 70 105 L 130 40 L 215 28 L 285 70 L 320 140",
          sspec="M 270 500 L 250 590 L 160 640 L 70 600 L 40 520 L 100 430 L 200 370 L 270 290 L 270 190 L 200 100 L 110 75 L 30 110",
          mk=75, mgap=55, mup_u=38, s_p2=True)

KERN_PUNCT = ".,!?'\"‘’“”-:;"
def seq_cycle(text, cm):
    """emulate the calt cycle: base, alt1, alt2, base ..."""
    out = []; prev = None
    for chn in text:
        gn = cm.get(ord(chn)); out.append([chn, gn]); 
    names = [g for _, g in out]
    res = []; state = []
    for i, (chn, gn) in enumerate(out):
        if gn is None or len(gn) != 1 or gn not in ALT:
            res.append((chn, gn)); continue
        pv = res[i-1][1] if i else None
        if pv and (pv.endswith('.alt1')): res.append((chn, gn + '.alt2'))
        elif pv and (pv.endswith('.alt2')): res.append((chn, gn))
        elif pv and pv[0].islower() and (pv.split('.')[0].isalpha() and len(pv.split('.')[0]) == 1): res.append((chn, gn + '.alt1'))
        else: res.append((chn, gn))
    return res

def main():
    spec = build()
    finish_metrics(spec, S0=50, f=0.6, D=100, jitter=5, seed=3, caps_S0=44)
    for n in spec.order:        # alts use the same spacing as the base
        if n.endswith('.alt1') or n.endswith('.alt2'): pass
    spec.g['space']['adv'] = 230; spec.g['nbspace']['adv'] = 230
    compose_accents(spec, PP, mk)
    names = [gname(ord(c)) for c in LOWER + UPPER + DIGITS + KERN_PUNCT + ACC_UP + ACC_LO if gname(ord(c)) in spec.g] + [n for n in spec.order if '.alt' in n]
    tl = ref_gap(spec, 'n', 'n'); tu = ref_gap(spec, 'H', 'H')
    pairs = kern_table(spec, names, tl, tu, mingap=30)
    print('kern', len(pairs), round(tl), round(tu))
    setg = ' '.join(ALT); a1 = ' '.join(c + '.alt1' for c in ALT); a2 = ' '.join(c + '.alt2' for c in ALT)
    lower = ' '.join(c for c in LOWER) + ' dotlessi germandbls'
    fea = f"""languagesystem DFLT dflt;
languagesystem latn dflt;
@set = [{setg}];
@alt1 = [{a1}];
@alt2 = [{a2}];
@lower = [{lower}];
lookup CYCLE {{
  sub @alt1 @set' by @alt2;
  sub @lower @set' by @alt1;
}} CYCLE;
feature calt {{ lookup CYCLE; }} calt;
feature salt {{ sub @set by @alt1; }} salt;
feature ss01 {{ sub @set by @alt2; }} ss01;
""" + fea_kern(pairs)
    out = os.path.join(HERE, 'LyraHand-Regular.ttf')
    build_ttf(spec, out, None, fea, dict(family=NAME, copyright='Copyright 2026 The Lyra Project Authors. Licensed under the SIL Open Font License 1.1.',
              description='Lyra Hand: casual felt-pen handwriting with calt alternates, procedurally drawn.'))
    # specimen: temp copy with PUA codepoints for alts so the alternates can be drawn
    from fontTools.ttLib import TTFont
    f = TTFont(out); pua = {}; cp = 0xF000
    for n in f.getGlyphOrder():
        if '.alt' in n:
            pua[n] = chr(cp)
            for t in f['cmap'].tables:
                if t.isUnicode(): t.cmap[cp] = n
            cp += 1
    tmp = os.path.join(os.environ.get('TMPDIR', '/tmp'), 'hand_pua.ttf')
    f.save(tmp)
    cm = TTFont(out).getBestCmap()
    def seqfn(t):
        return [(pua.get(g, c), g) for c, g in seq_cycle(t, cm)]
    specimen(out, os.path.join(HERE, 'specimen.png'), 'Lyra Hand Regular', seqfn=seqfn, draw_font=tmp)
    print(verify(out))

if __name__ == '__main__':
    main()
