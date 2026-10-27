#!/usr/bin/env python3
"""Lyra Saloon generator: wild-west wood type (condensed Tuscan slab).
Pen model: rectangular pen 84 x 36 held flat (thick verticals, thinner horizontals),
swept along skeleton paths; bracketed slab serifs and tuscan spurs added as polygons;
inline slit cut from the big capitals; vertices jittered with a seeded RNG for inked roughness.
Usage: /tmp/fontvenv/bin/python build_saloon.py"""
import math, os, sys, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fontkit import *

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = 'Lyra Saloon'

class Ctx:
    pen = rect_pen(84, 36, 0)
    step = 8
ctx = Ctx()
P2 = rect_pen(52, 28, 0)
PT = rect_pen(42, 22, 0)
LAST = [None]; INLINE = [False]
def mk():
    LAST[0] = Gb(ctx); return LAST[0]

XH, CAP = 500, 700
TOP, BOT = 682, 18          # centerline limits for caps (pen half height 18)
xt, xb = 482, 18

def serif(g, x, y, up, w=78):
    """bracketed slab serif; y = outer edge (baseline or top line); up=True means serif sits on the baseline"""
    s = 1 if up else -1
    pts = [(x-w, y), (x+w, y), (x+w, y+s*30), (x+44, y+s*38), (x+40, y+s*70), (x-40, y+s*70), (x-44, y+s*38), (x-w, y+s*30)]
    g.poly(pts)
    # tuscan spur: pointed flare under the middle of the serif
    g.poly([(x-16, y), (x, y-s*20), (x+16, y)])

def spur(g, x, y, d):
    """small tuscan spur on a horizontal stroke; d=+1 points up, -1 down"""
    g.poly([(x-26, y), (x, y+d*28), (x+26, y)])

def ST(x, y0, y1, sb=True, st=True, w=78):
    g = LAST[0]
    if sb: serif(g, x, 0 if y0 < 100 else y0-18, True, w)
    if st: serif(g, x, y1+18, False, w)
    if INLINE[0] and (y1-y0) > 300:
        g.cutpoly([(x-4, y0+78), (x+4, y0+78), (x+4, y1-78), (x-4, y1-78)])
    return "M %d %d L %d %d" % (x, y0, x, y1)

def A(g, cx, cy, rx, ry, a0, a1, cut=True):
    g.stroke("E %.1f %.1f %.1f %.1f %.1f %.1f" % (cx, cy, rx, ry, a0, a1))
    if INLINE[0] and cut:
        lo, hi = min(a0, a1), max(a0, a1)
        for c0 in (-360, 0, 360):
            for (s0, s1) in ((-42+c0, 42+c0), (138+c0, 222+c0)):
                u, v = max(lo, s0), min(hi, s1)
                if v-u > 30:
                    u2, v2 = u+10, v-10
                    if v2-u2 > 10:
                        g.cut("E %.1f %.1f %.1f %.1f %.1f %.1f" % (cx, cy, rx, ry, u2, v2), rect_pen(8, 8, 0))

L = {}
def reg(key, g, cat='U', **kw): L[key] = (g, cat, kw)

def caps():
    global INLINE
    INLINE[0] = True
    cy = 350
    g = mk(); g.stroke("M 10 %d L 150 %d L 290 %d" % (BOT, TOP, BOT)); serif(g, 10, 0, True); serif(g, 290, 0, True); g.stroke("M 60 220 L 240 220"); reg('A', g)
    g = mk(); g.stroke(ST(0, BOT, TOP)); g.stroke("M 0 %d L 120 %d" % (TOP, TOP)); A(g, 120, 524, 115, 158, 90, -90); g.stroke("M 0 366 L 130 366"); A(g, 130, 192, 130, 174, 90, -90)
    g.stroke("M 130 18 L 0 18"); spur(g, 60, 700, 1) if False else None; reg('B', g)
    g = mk(); A(g, 170, 350, 170, 332, 40, 320); g.stroke("M 275 %d L 275 %d" % (TOP-170, TOP-80)) if False else None
    g.stroke("M 288 560 L 288 470"); g.stroke("M 288 140 L 288 220"); reg('C', g)
    g = mk(); g.stroke(ST(0, BOT, TOP)); g.stroke("M 0 %d L 110 %d" % (TOP, TOP)); A(g, 110, 350, 175, 332, 90, -90); g.stroke("M 110 18 L 0 18"); reg('D', g)
    def arms(g, w):
        g.stroke("M 0 %d L %d %d" % (TOP, w, TOP)); g.stroke("M %d %d L %d %d" % (w, TOP, w, TOP-95)); 
        g.stroke("M 0 %d L %d %d" % (BOT, w, BOT))
    g = mk(); g.stroke(ST(0, BOT, TOP)); arms(g, 230); g.stroke("M 230 18 L 230 110"); g.stroke("M 0 360 L 190 360"); g.stroke("M 190 300 L 190 420", pen=PT); spur(g, 115, 378, 1); reg('E', g)
    g = mk(); g.stroke(ST(0, BOT, TOP)); g.stroke("M 0 %d L 230 %d" % (TOP, TOP)); g.stroke("M 230 %d L 230 %d" % (TOP, TOP-95)); g.stroke("M 0 360 L 190 360"); g.stroke("M 190 300 L 190 420", pen=PT); reg('F', g)
    g = mk(); A(g, 170, 350, 170, 332, 40, 320); g.stroke("M 288 560 L 288 470"); g.stroke("M 335 140 L 335 350 L 190 350") if False else None
    g.stroke("M 288 140 L 288 350 L 190 350"); reg('G', g)
    g = mk(); g.stroke(ST(0, BOT, TOP)); g.stroke(ST(290, BOT, TOP)); g.stroke("M 0 360 L 290 360"); spur(g, 145, 378, 1); spur(g, 145, 342, -1); reg('H', g)
    g = mk(); g.stroke(ST(0, BOT, TOP, w=100)); reg('I', g)
    g = mk(); g.stroke("M 250 %d L 250 160 E 130 160 120 142 0 -180" % TOP); serif(g, 250, 700, False, 78); g.stroke("M 10 160 L 10 90") if False else None; reg('J', g)
    g = mk(); g.stroke(ST(0, BOT, TOP)); g.stroke("M 0 330 L 270 %d" % TOP); serif(g, 280, 700, False, 70); g.stroke("M 120 400 L 285 %d" % BOT); serif(g, 290, 0, True, 70); reg('K', g)
    g = mk(); g.stroke(ST(0, BOT, TOP)); g.stroke("M 0 %d L 250 %d L 250 100" % (BOT, BOT)); reg('L', g)
    g = mk(); g.stroke(ST(0, BOT, TOP)); g.stroke(ST(380, BOT, TOP)); g.stroke("M 0 %d L 190 200 L 380 %d" % (TOP, TOP)); reg('M', g)
    g = mk(); g.stroke(ST(0, BOT, TOP)); g.stroke(ST(310, BOT, TOP)); g.stroke("M 0 %d L 310 %d" % (TOP, BOT)); reg('N', g)
    g = mk(); A(g, 170, 350, 170, 332, 0, 360); reg('O', g)
    g = mk(); g.stroke(ST(0, BOT, TOP)); g.stroke("M 0 %d L 110 %d" % (TOP, TOP)); A(g, 110, 505, 150, 177, 90, -90); g.stroke("M 110 328 L 0 328"); reg('P', g)
    g = mk(); A(g, 170, 350, 170, 332, 0, 360); g.stroke("M 190 150 L 340 -60"); reg('Q', g)
    g = mk(); g.stroke(ST(0, BOT, TOP)); g.stroke("M 0 %d L 110 %d" % (TOP, TOP)); A(g, 110, 510, 140, 172, 90, -90); g.stroke("M 110 338 L 0 338"); g.stroke("M 130 338 L 290 %d" % BOT); serif(g, 295, 0, True, 70); reg('R', g)
    g = mk(); A(g, 165, 520, 150, 164, 20, 270, False); A(g, 165, 180, 150, 164, 90, -160, False); g.stroke("M 305 %d L 305 520" % 600) if False else None; reg('S', g)
    g = mk(); g.stroke(ST(150, BOT, TOP, st=False)); g.stroke("M 0 %d L 300 %d" % (TOP, TOP)); g.stroke("M 0 %d L 0 580" % TOP); g.stroke("M 300 %d L 300 580" % TOP); spur(g, 70, 700, 1) if False else None; reg('T', g)
    g = mk(); g.stroke("M 0 %d L 0 150 E 150 150 150 132 180 360" % TOP); g.stroke(ST(300, BOT, TOP, sb=False)); serif(g, 0, 700, False); reg('U', g)
    g = mk(); g.stroke("M 0 %d L 150 %d L 300 %d" % (TOP, BOT, TOP)); serif(g, 0, 700, False, 70); serif(g, 300, 700, False, 70); reg('V', g)
    g = mk(); g.stroke("M 0 %d L 120 %d L 240 %d L 360 %d L 480 %d" % (TOP, BOT, TOP-60, BOT, TOP)); serif(g, 0, 700, False, 70); serif(g, 480, 700, False, 70); serif(g, 240, 700, False, 50); reg('W', g)
    g = mk(); g.stroke("M 0 %d L 300 %d M 300 %d L 0 %d" % (TOP, BOT, TOP, BOT)); serif(g, 0, 700, False, 70); serif(g, 300, 700, False, 70); serif(g, 0, 0, True, 70); serif(g, 300, 0, True, 70); reg('X', g)
    g = mk(); g.stroke("M 0 %d L 160 340 L 320 %d" % (TOP, TOP)); g.stroke("M 160 340 L 160 %d" % BOT); serif(g, 0, 700, False, 70); serif(g, 320, 700, False, 70); serif(g, 160, 0, True); reg('Y', g)
    g = mk(); g.stroke("M 0 %d L 290 %d L 0 %d L 300 %d" % (TOP, TOP, BOT, BOT)); g.stroke("M 0 %d L 0 590" % TOP); g.stroke("M 300 %d L 300 100" % BOT); reg('Z', g)
    # digits
    g = mk(); A(g, 120, 350, 120, 332, 0, 360); reg('0', g)
    g = mk(); g.stroke(ST(100, BOT, TOP, st=False)); g.stroke("M 0 %d L 100 %d" % (560, TOP)); g.stroke("M 100 %d L 100 600" % TOP) if False else None; reg('1', g)
    g = mk(); A(g, 120, 515, 120, 167, 165, -30, False); g.stroke("M 232 450 L 0 %d L 250 %d" % (BOT, BOT)); g.stroke("M 250 18 L 250 100"); reg('2', g)
    g = mk(); A(g, 115, 525, 115, 157, 150, -90, False); A(g, 120, 190, 130, 172, 90, -150, False); reg('3', g)
    g = mk(); g.stroke(ST(190, BOT, TOP)); g.stroke("M 190 %d L 0 210 L 270 210" % TOP); reg('4', g)
    g = mk(); g.stroke("M 250 %d L 20 %d L 20 400" % (TOP, TOP)); A(g, 120, 215, 135, 190, 100, -140, False); g.stroke("M 20 400 L 110 405"); reg('5', g)
    g = mk(); A(g, 125, 200, 125, 182, 0, 360, False); g.stroke("M 0 200 L 0 480 E 130 480 130 190 180 90"); reg('6', g)
    g = mk(); g.stroke("M 0 %d L 260 %d L 90 %d" % (TOP, TOP, BOT)); g.stroke("M 0 %d L 0 590" % TOP); serif(g, 90, 0, True); reg('7', g)
    g = mk(); A(g, 120, 190, 130, 172, 0, 360, False); A(g, 120, 525, 108, 157, 0, 360, False); reg('8', g)
    g = mk(); A(g, 125, 500, 125, 182, 0, 360, False); g.stroke("M 250 500 L 250 220 E 120 220 130 202 0 -90"); reg('9', g)
    INLINE[0] = False
caps()

def lc():
    W = 260
    def bowl(g): g.stroke("E 130 250 130 232 0 360")
    g = mk(); bowl(g); reg('o', g, 'l')
    g = mk(); g.stroke("M 0 %d L 110 %d" % (xt, xt)); g.stroke("E 130 250 130 232 90 -90".replace('130 250', '110 250')); g.stroke("M 110 18 L 0 18"); g.stroke(ST(0, 18, 690, sb=True, st=True, w=70)); reg('b', g, 'l')
    g = mk(); g.stroke("M %d %d L %d %d" % (W, xt, W-110, xt)); g.stroke("E %d 250 130 232 90 270" % (W-110)); g.stroke("M %d 18 L %d 18" % (W-110, W)); g.stroke(ST(W, 18, 690, w=70)); reg('d', g, 'l')
    g = mk(); g.stroke("M %d %d L %d %d" % (W, xt, W-110, xt)); g.stroke("E %d 250 130 232 90 270" % (W-110)); g.stroke("M %d 18 L %d 18" % (W-110, W)); g.stroke(ST(W, 18, xt, sb=True, st=True, w=70)); reg('a', g, 'l')
    g = mk(); g.stroke("M 0 %d L 110 %d" % (xt, xt)); g.stroke("E 110 250 130 232 90 -90"); g.stroke("M 110 18 L 0 18"); g.stroke(ST(0, -170, xt, w=70)); reg('p', g, 'l')
    g = mk(); g.stroke("M %d %d L %d %d" % (W, xt, W-110, xt)); g.stroke("E %d 250 130 232 90 270" % (W-110)); g.stroke("M %d 18 L %d 18" % (W-110, W)); g.stroke(ST(W, -170, xt, w=70)); reg('q', g, 'l')
    g = mk(); g.stroke("E 130 250 130 232 40 320"); g.stroke("M 246 400 L 246 330"); g.stroke("M 246 100 L 246 170"); reg('c', g, 'l')
    g = mk(); g.stroke("M 0 250 L 260 250"); g.stroke("E 130 250 130 232 0 320"); reg('e', g, 'l')
    g = mk(); g.stroke(ST(0, 18, 560, w=70, st=False)); g.stroke("M 0 560 E 70 560 70 100 180 90"); g.stroke("M -70 482 L 120 482"); reg('f', g, 'l')
    g = mk(); g.stroke("M %d %d L %d %d" % (W, xt, W-110, xt)); g.stroke("E %d 270 130 214 90 270" % (W-110)); g.stroke("M %d 56 L %d 56" % (W-110, W)); g.stroke(ST(W, -40, xt, w=70)); g.stroke("M %d -40 E %d -50 110 125 0 -110" % (W, W-110)); reg('g', g, 'l')
    def arch(g, x0):
        g.stroke("M %d 370 E %d 360 130 124 180 0" % (x0, x0+130)); g.stroke(ST(x0+260, 18, 360, st=False, w=70))
    g = mk(); g.stroke(ST(0, 18, xt, w=70)); arch(g, 0); reg('n', g, 'l')
    g = mk(); g.stroke(ST(0, 18, xt, w=70)); arch(g, 0); arch(g, 260); reg('m', g, 'l')
    g = mk(); g.stroke(ST(0, 18, 690, w=70)); arch(g, 0); reg('h', g, 'l')
    g = mk(); g.stroke(ST(0, 18, xt, w=70)); g.stroke("M 0 360 E 130 360 130 124 180 50"); reg('r', g, 'l')
    g = mk(); g.stroke("M 0 %d L 0 130 E 130 130 130 112 180 360" % xt); g.stroke(ST(260, 18, xt, sb=True, st=True, w=70)); serif(g, 0, 500, False, 70); reg('u', g, 'l')
    g = mk(); g.stroke("M 0 %d L 130 18 L 260 %d" % (xt, xt)); serif(g, 0, 500, False, 62); serif(g, 260, 500, False, 62); reg('v', g, 'l')
    g = mk(); g.stroke("M 0 %d L 100 18 L 200 %d L 300 18 L 400 %d" % (xt, xt-50, xt)); serif(g, 0, 500, False, 62); serif(g, 400, 500, False, 62); reg('w', g, 'l')
    g = mk(); g.stroke("M 0 %d L 260 18 M 260 %d L 0 18" % (xt, xt)); serif(g, 0, 500, False, 62); serif(g, 260, 500, False, 62); serif(g, 0, 0, True, 62); serif(g, 260, 0, True, 62); reg('x', g, 'l')
    g = mk(); g.stroke("M 0 %d L 120 60" % xt); g.stroke("M 260 %d L 90 -170" % xt); serif(g, 0, 500, False, 62); serif(g, 260, 500, False, 62); reg('y', g, 'l')
    g = mk(); g.stroke("M 0 %d L 250 %d L 0 18 L 260 18" % (xt, xt)); g.stroke("M 0 %d L 0 420" % xt); g.stroke("M 260 18 L 260 90"); reg('z', g, 'l')
    g = mk(); g.stroke(ST(0, 18, xt, w=70)); g.poly([(-30, 590), (30, 590), (30, 650), (-30, 650)]); reg('i', g, 'l')
    g = mk(); g.stroke("M 0 %d L 0 -60 E -90 -60 90 110 0 -120" % xt); serif(g, 0, 500, False, 70); g.poly([(-30, 590), (30, 590), (30, 650), (-30, 650)]); reg('j', g, 'l', anchor=0)
    g = mk(); g.stroke(ST(0, 18, 690, w=70)); reg('l', g, 'l')
    g = mk(); g.stroke("M 0 %d L 0 120 E 80 120 80 102 180 270" % 600); g.stroke("M -60 482 L 110 482"); serif(g, 0, 700-90, False, 60); reg('t', g, 'l')
    g = mk(); g.stroke(ST(0, 18, 690, w=70)); g.stroke("M 0 220 L 250 %d" % xt); serif(g, 260, 500, False, 62); g.stroke("M 100 300 L 255 18"); serif(g, 262, 0, True, 62); reg('k', g, 'l')
    g = mk(); g.stroke(ST(0, 18, xt, w=70)); reg('dotlessi', g, 'l')
    g = mk(); g.stroke("M 0 560 L 0 100"); serif(g, 0, 600+80, False, 70) ; g.stroke("M 0 100 E 0 100 0 0 0 0") if False else None
    g.stroke("M 0 560 L 0 330"); g.stroke("M 0 330 L 0 330")
    g.stroke("M 0 700 L 0 100"); g.stroke("M 0 100 E 110 100 110 82 180 270"); g.stroke("M 0 640 E 80 640 100 60 90 0") if False else None
    g.stroke("M 0 640 L 110 640 E 110 540 100 100 90 -90"); g.stroke("M 0 330 L 110 330"); g.stroke("M 110 330 E 130 230 140 132 90 -90"); reg('germandbls', g, 'l')
    g = mk(); g.stroke("E 130 372 112 108 20 270"); g.stroke("E 130 128 112 108 90 -160"); reg('s', g, 'l')
lc()

dotp = lambda g, x, y, s=1.0: g.poly([(x-28*s, y+4*s), (x+28*s, y+4*s), (x+28*s, y+60*s), (x-28*s, y+60*s)])
def dot(g, x, y, s=1.0): g.poly([(x-30*s, y), (x+30*s, y), (x+30*s, y+60*s), (x-30*s, y+60*s)])
def tpr(pts):
    n = len(pts); return [1.0 - 0.35*(i/(n-1)) for i in range(n)]
def at_(mk_):
    g = mk_(); g.stroke("E 290 290 275 285 40 355", pen=P2); g.stroke("E 300 285 95 95 0 360", pen=P2); g.stroke("M 395 400 L 395 190 L 440 190 L 480 250", pen=P2); return g
PP = dict(cap=CAP, xh=XH, asc=780, desc=-200, dot=dot, pen2=P2, pen3=PT, dr=60, tail=(40, 110), tailscale=None, taper=tpr,
          qspec="M -105 570 C -105 650 -40 682 20 682 C 90 682 130 640 130 570 C 130 480 40 440 20 360 L 20 320", qh=170, qgap=110, tickscale=None,
          dashy=270, hy=170, en=340, em=700, ul=-70, uw=520, ellg=130, my=270, mw=230, eqg=140, ah=150, sl=(-60, 760, 260),
          bw=120, pw=130, tw=260, ty=300, cw=180, star=95, hw=340, hh=640, sw=300, pr=82, pw2=420, at=at_,
          amp="M 330 20 L 230 160 L 140 290 L 110 420 L 125 540 L 180 620 L 235 570 L 230 470 L 170 380 L 100 290 L 60 200 L 70 105 L 130 40 L 215 28 L 285 70 L 320 140",
          sspec="M 270 500 L 250 590 L 160 640 L 70 600 L 40 520 L 100 430 L 200 370 L 270 290 L 270 190 L 200 100 L 110 75 L 30 110",
          mk=75, mgap=55, mup_u=38, s_p2=True)

def rough(cs, rnd, amp=2.2):
    return [[(x+rnd.uniform(-amp, amp), y+rnd.uniform(-amp, amp)) for x, y in c] for c in cs]

def build():
    spec = Spec(); rnd = random.Random(7)
    for key, (g, cat, kw) in L.items():
        cs = g.result()
        cp = ord(key) if len(key) == 1 else (0xDF if key == 'germandbls' else None)
        spec.add(gname(cp) if cp else key, cs, cp=cp, cat=cat, anchor=kw.get('anchor'))
    for key, g in punct(mk, PP).items():
        spec.add(gname(ord(key)), g.result(), cp=ord(key), cat='p')
    spec.g['dotlessi']['cp'] = 0x131
    ligature(spec, 'A', 'E', 'AE', 0xC6, 20, 'U')
    ligature(spec, 'a', 'e', 'ae', 0xE6, 55, 'l')
    g = mk(); g.add_contours(spec.g['o']['cs']); g.stroke("M 20 20 L 240 480", pen=P2); spec.add('oslash', g.result(), cp=0xF8, cat='l')
    g = mk(); g.add_contours(spec.g['O']['cs']); g.stroke("M 10 0 L 330 700", pen=P2); spec.add('Oslash', g.result(), cp=0xD8, cat='U')
    spec.add('space', [], cp=0x20, adv=200); spec.add('nbspace', [], cp=0xA0, adv=200)
    g = mk(); g.poly([(60, 0), (400, 0), (400, 700), (60, 700)]); g.cutpoly([(120, 60), (120, 640), (340, 640), (340, 60)])
    spec.add('.notdef', g.result(), sb=(60, 60))
    return spec

KERN_PUNCT = ".,!?'\"‘’“”-:;"
def main():
    spec = build()
    finish_metrics(spec, S0=40, f=0.5, D=95, caps_S0=42)
    spec.g['space']['adv'] = 200; spec.g['nbspace']['adv'] = 200
    compose_accents(spec, PP, mk)
    rnd = random.Random(11)
    for n in spec.order:
        spec.g[n]['final'] = rough(spec.g[n]['final'], rnd) if spec.g[n]['final'] and n != '.notdef' else spec.g[n]['final']
    names = [gname(ord(c)) for c in LOWER + UPPER + DIGITS + KERN_PUNCT + ACC_UP + ACC_LO if gname(ord(c)) in spec.g]
    tl = ref_gap(spec, 'n', 'n'); tu = ref_gap(spec, 'H', 'H')
    pairs = kern_table(spec, names, tl, tu, mingap=32)
    print('kern pairs', len(pairs), round(tl), round(tu))
    fea = 'languagesystem DFLT dflt;\nlanguagesystem latn dflt;\n' + fea_kern(pairs)
    out = os.path.join(HERE, 'LyraSaloon-Regular.ttf')
    build_ttf(spec, out, None, fea, dict(family=NAME, copyright='Copyright 2026 The Lyra Project Authors. Licensed under the SIL Open Font License 1.1.',
              description='Lyra Saloon: wild-west wood-type display face, procedurally drawn.'))
    specimen(out, os.path.join(HERE, 'specimen.png'), 'Lyra Saloon Regular')
    print(verify(out))

if __name__ == '__main__':
    main()
