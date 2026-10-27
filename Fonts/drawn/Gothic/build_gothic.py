#!/usr/bin/env python3
"""Lyra Gothic generator: modern Textura-spirit blackletter.
Pen model: broad rectangular nib (100 x 16 units) held at 35 degrees, swept along
skeleton paths (hull-of-successive-pen-positions), boolean-unioned with skia-pathops.
Usage: /tmp/fontvenv/bin/python build_gothic.py"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fontkit import *

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = 'Lyra Gothic'

class Ctx:
    pen = rect_pen(106, 12, 37)
    step = 9
ctx = Ctx()
HAIR = rect_pen(34, 9, 35)          # hairline accent pen
P2 = rect_pen(70, 12, 35)           # secondary (symbols) pen
PT = rect_pen(54, 10, 35)           # tiny ticks
LAST=[None]
def mk():
    LAST[0]=Gb(ctx); return LAST[0]

XH, CAP, ASC, DESC = 500, 700, 780, -200
W = 210            # bowl width (centre to centre)
YT, YB = 465, 35   # centreline top/bottom of x-height letters
CH = 62            # chamfer

def oct_(x0, x1, ylo, yhi, ch=CH, ch2=None):
    ch2 = ch if ch2 is None else ch2
    return ("M %d %d L %d %d L %d %d L %d %d L %d %d L %d %d L %d %d L %d %d Z" % (
        x0, ylo+ch, x0, yhi-ch2, x0+ch2, yhi, x1-ch2, yhi, x1, yhi-ch2, x1, ylo+ch, x1-ch, ylo, x0+ch, ylo))

CT, CB = 665, 35
def stem(x, y0=35, y1=665):
    if y0 == 35 and LAST[0] is not None: LAST[0].poly(diamond(x, 44, 58, 44))
    return "M %d %d L %d %d" % (x, y0, x, y1)
def ST(x, y0, y1):
    if y0 == 35 and LAST[0] is not None: LAST[0].poly(diamond(x, 44, 58, 44))
    return "M %d %d L %d %d" % (x, y0, x, y1)

def head(g, x, y, s=1.0):
    """hairline diamond cap at the top-left of a stem"""
    g.poly([(x-58*s, y-8*s), (x-20*s, y+34*s), (x+22*s, y-2*s), (x-20*s, y-36*s)])

def foot(g, x, y, s=1.0):
    g.poly([(x+10*s, y+2*s), (x+52*s, y-34*s), (x+88*s, y-2*s), (x+50*s, y+30*s)]) if False else None

def arch(x0, x1, y, ch=CH):   # shoulder: from (x0, y-ch) up to the arch and down to (x1, y-ch)
    return "M %d %d L %d %d L %d %d L %d %d" % (x0, y-ch, x0+ch, y, x1-ch, y, x1, y-ch)

L = {}   # char/name -> (Gb, cat, kw)
def reg(key, g, cat='l', **kw): L[key] = (g, cat, kw)

# ------------------------------------------------------------ lowercase
def lc():
    def o_():
        g = mk(); g.stroke(oct_(0, W, YB, YT)); return g
    g = o_(); reg('o', g)
    g = o_(); g.stroke(ST(W, YB, YT)); head(g, W, 496) if False else None; reg('a', g)
    g = o_(); g.stroke(ST(W, YB, ASC-45)); reg('d', g)
    g = o_(); g.stroke(ST(0, YB, ASC-45)); reg('b', g)
    g = o_(); g.stroke(ST(0, -165, YT)); reg('p', g)
    g = o_(); g.stroke(ST(W, -165, YT)); reg('q', g)
    g = mk(); g.stroke("M %d %d L %d %d L %d %d L %d %d L %d %d L %d %d L %d %d" % (W, YT-60, W-CH, YT, CH, YT, 0, YT-CH, 0, YB+CH, CH, YB, W-CH, YB)); g.stroke("M %d %d L %d %d" % (W, YT-60, W, YT-130)); reg('c', g)
    g = mk(); g.stroke(oct_(0, W, YB, YT)); g.cut("M 20 255 L %d 255" % (W-10), rect_pen(1, 1, 0)) if False else None
    g = mk(); g.stroke("M %d 262 L %d %d L %d %d L %d %d L 0 %d L 0 %d L %d %d L %d %d L %d %d" % (
        W, W, YT-CH, W-CH, YT, CH, YT, YT-CH, YB+CH, CH, YB, W-CH, YB, W, YB+50))
    g.stroke("M -2 262 L %d 262" % (W+2), pen=HAIR, scale=None); reg('e', g)
    # n family
    def nn(g, n=1):
        g.stroke(ST(0, YB, YT))
        for i in range(n):
            x0 = i*W
            g.stroke(arch(x0, x0+W, YT))
            g.stroke(ST(x0+W, YB, YT))
        head(g, 0, 500)
    g = mk(); nn(g, 1); reg('n', g)
    g = mk(); nn(g, 2); reg('m', g)
    g = mk(); g.stroke(ST(0, YB, ASC-45)); g.stroke(arch(0, W, YT)); g.stroke(ST(W, YB, YT)); reg('h', g)
    g = mk(); g.stroke(ST(0, YB, YT)); g.stroke(arch(0, W, YT)[0:0] or "M 0 %d L %d %d L %d %d" % (YT-CH, CH, YT, int(W*0.62), YT)); head(g, 0, 500); reg('r', g)
    # u
    g = mk(); g.stroke("M 0 %d L 0 %d L %d %d L %d %d L %d %d" % (YT, YB+CH, CH, YB, W-CH, YB, W, YB+CH)); g.stroke(ST(W, YB, YT)); head(g, 0, 500); reg('u', g)
    # v, w, x, y, z
    g = mk(); g.stroke("M 0 %d L %d %d L %d %d" % (YT, W*0.5, YB, W, YT)); reg('v', g)
    g = mk(); g.stroke("M 0 %d L %d %d L %d %d L %d %d L %d %d" % (YT, W*0.5, YB, W, YT, W*1.5, YB, W*2, YT)); reg('w', g)
    g = mk(); g.stroke("M 0 %d L %d %d M %d %d L 0 %d" % (YT, W, YB, W, YT, YB)); reg('x', g)
    g = mk(); g.stroke("M 0 %d L %d %d" % (YT, W*0.5+10, YB+60)); g.stroke("M %d %d L %d %d L %d %d" % (W, YT, W*0.55, YB+20, W*0.22, -165)); reg('y', g)
    g = mk(); g.stroke("M 10 %d L %d %d L 0 %d L %d %d" % (YT, W-10, YT, YB, W, YB)); reg('z', g)
    # i j l t k f s g
    g = mk(); g.stroke(ST(0, YB, YT)); head(g, 0, 500); g.poly(diamond(0, 640, 46, 52)); reg('i', g)
    g = mk(); g.stroke("M 0 %d L 0 -100 L %d -165 L %d -165" % (YT, -55, -110)); g.poly(diamond(0, 640, 46, 52)); head(g, 0, 500); reg('j', g, anchor=0)
    g = mk(); g.stroke(ST(0, YB, ASC-45)); head(g, 0, 780); reg('l', g)
    g = mk(); g.stroke("M 0 %d L 0 %d L %d %d L %d %d" % (640, YB+CH, CH, YB, CH*2, YB)); g.stroke("M -70 %d L %d %d" % (YT, 90, YT)); reg('t', g)
    g = mk(); g.stroke(ST(0, YB, ASC-45)); g.stroke("M 40 280 L %d %d" % (W-20, YT)); g.stroke("M 105 330 L %d %d" % (W, YB)); reg('k', g)
    g = mk(); g.stroke("M 0 %d L 0 %d L %d %d L %d %d" % (YB, 690, 70, ASC-15, 150, ASC-15)); g.stroke("M -70 %d L 100 %d" % (YT, YT)); reg('f', g)
    g = mk(); g.stroke("M %d %d L %d %d L %d %d L %d %d L %d %d L %d %d L %d %d L %d %d L %d %d" % (
        W-5, YT-70, W-CH, YT, 70, YT, 5, YT-65, 5, 345, 60, 270, W-60, 215, W, 150, W, 95)) 
    g.stroke("M %d %d L %d %d L %d %d L 0 %d" % (W, 95, W-CH, YB, 70, YB, YB+65)); reg('s', g)
    g = o_(); g.stroke("M %d %d L %d -100 L %d -165 L %d -165 L 0 -100" % (W, YT, W, W-CH, CH)); reg('g', g)
    g = mk(); g.stroke(ST(0, YB, YT)); head(g, 0, 500); reg('dotlessi', g)
    # sharp s
    g = mk(); g.stroke(ST(0, YB, 700)); g.stroke("M 0 700 L %d %d L %d %d L %d %d L %d %d L %d 500 L 20 450" % (60, ASC-15, 160, ASC-15, W, 710, W, 600, W-60)); 
    g.stroke("M 20 450 L %d 400 L %d 335 L %d 150 L %d %d L %d %d L %d %d" % (W-30, W+10, W+10, W-50, YB, 60, YB, 8, YB+30))
    reg('germandbls', g)
    # ae oe etc built later
lc()

# ------------------------------------------------------------ capitals
CT, CB = 665, 35
def caps():
    def flagH(g, x, y=CT): g.poly([(x-70, y-22), (x-30, y+30), (x+8, y+2), (x-30, y-32)]) if False else head(g, x, CT+28, 1.0)
    def stem(x, y0=CB, y1=CT): return ST(x, y0, y1)
    # A
    g = mk(); g.stroke("M 0 %d L 205 %d L 410 %d" % (CB, CT, CB)); g.stroke("M 68 250 L 345 250", pen=HAIR); reg('A', g, 'U')
    g = mk(); g.stroke(stem(0)); g.stroke("M 0 %d L 175 %d L 235 %d L 235 %d L 175 365 L 0 365" % (CT, CT, CT-62, CT-170)) if False else None
    g.stroke("M 0 %d L 170 %d L 235 %d L 235 %d L 170 372 L 0 372" % (CT, CT, CT-62, CT-170))
    g.stroke("M 0 372 L 200 372 L 270 305 L 270 105 L 200 %d L 0 %d" % (CB, CB)); reg('B', g, 'U')
    g = mk(); g.stroke("M 250 %d L 250 %d L 188 %d L 62 %d L 0 %d L 0 %d L 62 %d L 188 %d L 250 %d" % (CT-110, CT-62, CT, CT, CT-62, CB+62, CB, CB, CB+62)); g.stroke("M 250 %d L 250 %d" % (CT-110, CT-170)); reg('C', g, 'U')
    g = mk(); g.stroke(stem(0)); g.stroke("M 0 %d L 195 %d L 270 %d L 270 %d L 195 %d L 0 %d" % (CT, CT, CT-70, CB+70, CB, CB)); reg('D', g, 'U')
    g = mk(); g.stroke(stem(0)); g.stroke("M 0 %d L 250 %d L 265 %d" % (CT, CT, CT-70)); g.stroke("M 0 %d L 215 %d" % (365, 365)); g.stroke("M 0 %d L 250 %d L 265 %d" % (CB, CB, CB+70)); reg('E', g, 'U')
    g = mk(); g.stroke(stem(0)); g.stroke("M 0 %d L 250 %d L 265 %d" % (CT, CT, CT-70)); g.stroke("M 0 %d L 215 %d" % (365, 365)); reg('F', g, 'U')
    g = mk(); g.stroke("M 250 %d L 250 %d L 188 %d L 62 %d L 0 %d L 0 %d L 62 %d L 188 %d L 250 %d L 250 345 L 140 345" % (CT-110, CT-62, CT, CT, CT-62, CB+62, CB, CB, CB+62)); g.stroke("M 250 %d L 250 %d" % (CT-110, CT-170)); reg('G', g, 'U')
    g = mk(); g.stroke(stem(0)); g.stroke(stem(290)); g.stroke("M 0 365 L 290 365"); reg('H', g, 'U')
    g = mk(); g.stroke(stem(0)); g.stroke("M -75 %d L 75 %d M -75 %d L 75 %d" % (CT, CT, CB, CB), pen=P2); reg('I', g, 'U')
    g = mk(); g.stroke("M 250 %d L 250 %d L 188 %d L 62 %d L 0 %d L 0 %d" % (CT, CB+62, CB, CB, CB+62, CB+170)); g.stroke("M 160 %d L 340 %d" % (CT, CT), pen=P2); reg('J', g, 'U')
    g = mk(); g.stroke(stem(0)); g.stroke("M 40 340 L 270 %d" % CT); g.stroke("M 120 400 L 285 %d" % CB); reg('K', g, 'U')
    g = mk(); g.stroke(stem(0)); g.stroke("M 0 %d L 255 %d L 270 %d" % (CB, CB, CB+75)); reg('L', g, 'U')
    g = mk(); g.stroke(stem(0)); g.stroke(stem(430)); g.stroke("M 0 %d L 215 120 L 430 %d" % (CT, CT)); g.stroke(stem(215, CB, 300)); reg('M', g, 'U')
    g = mk(); g.stroke(stem(0)); g.stroke(stem(320)); g.stroke("M 0 %d L 320 %d" % (CT, CB)); reg('N', g, 'U')
    g = mk(); g.stroke(oct_(0, 320, CB, CT, 80)); reg('O', g, 'U')
    g = mk(); g.stroke(stem(0)); g.stroke("M 0 %d L 170 %d L 235 %d L 235 %d L 170 %d L 0 %d" % (CT, CT, CT-62, CT-200, 340, 340)); reg('P', g, 'U')
    g = mk(); g.stroke(oct_(0, 320, CB, CT, 80)); g.stroke("M 190 150 L 350 -70"); reg('Q', g, 'U')
    g = mk(); g.stroke(stem(0)); g.stroke("M 0 %d L 170 %d L 235 %d L 235 %d L 170 %d L 0 %d" % (CT, CT, CT-62, CT-200, 345, 345)); g.stroke("M 130 345 L 270 %d" % CB); reg('R', g, 'U')
    g = mk(); g.stroke("M 245 %d L 180 %d L 70 %d L 5 %d L 5 %d L 70 420 L 190 305 L 255 215 L 255 120 L 190 %d L 70 %d L 0 %d" % (CT-95, CT, CT, CT-62, CT-170, CB, CB, CB+65)); reg('S', g, 'U')
    g = mk(); g.stroke(stem(145)); g.stroke("M 0 %d L 290 %d" % (CT, CT)); g.stroke("M 0 %d L 0 %d M 290 %d L 290 %d" % (CT, CT-90, CT, CT-90), pen=P2) ; reg('T', g, 'U')
    g = mk(); g.stroke("M 0 %d L 0 %d L 70 %d L 240 %d L 310 %d" % (CT, CB+70, CB, CB, CB+70)); g.stroke(stem(310)); reg('U', g, 'U')
    g = mk(); g.stroke("M 0 %d L 175 %d L 350 %d" % (CT, CB, CT)); reg('V', g, 'U')
    g = mk(); g.stroke("M 0 %d L 150 %d L 300 %d L 450 %d L 600 %d" % (CT, CB, CT, CB, CT)); reg('W', g, 'U')
    g = mk(); g.stroke("M 0 %d L 320 %d M 320 %d L 0 %d" % (CT, CB, CT, CB)); reg('X', g, 'U')
    g = mk(); g.stroke("M 0 %d L 170 340 L 340 %d" % (CT, CT)); g.stroke(stem(170, CB, 340)); reg('Y', g, 'U')
    g = mk(); g.stroke("M 0 %d L 290 %d L 0 %d L 300 %d" % (CT, CT, CB, CB)); reg('Z', g, 'U')
caps()

# ------------------------------------------------------------ digits
def digits():
    D = 240
    g = mk(); g.stroke(oct_(0, 200, CB, CT, 70)); reg('0', g, 'U')
    g = mk(); g.stroke(stem(0)); g.stroke("M -90 %d L 0 %d" % (CT-110, CT), pen=P2); g.stroke("M -80 %d L 80 %d" % (CB, CB), pen=P2); reg('1', g, 'U')
    g = mk(); g.stroke("M 0 %d L 70 %d L %d %d L %d %d L %d %d L 0 %d L %d %d" % (CT-90, CT, D-70, CT, D, CT-70, D, 480, CB, D, CB)); reg('2', g, 'U')
    g = mk(); g.stroke("M 0 %d L 70 %d L %d %d L %d %d L %d %d L %d %d L 80 365" % (CT-90, CT, D-70, CT, D, CT-70, D, 480, D-70, 395)); g.stroke("M 80 365 L %d 365 L %d 300 L %d 105 L %d %d L 70 %d L 0 %d" % (D-60, D, D, D-70, CB, CB, CB+90)); reg('3', g, 'U')
    g = mk(); g.stroke(stem(185)); g.stroke("M 185 %d L 0 220 L %d 220" % (CT, D+40)); reg('4', g, 'U')
    g = mk(); g.stroke("M %d %d L 25 %d L 25 400 L %d 420 L %d 355 L %d 105 L %d %d L 70 %d L 0 %d" % (D, CT, CT, D-70, D, D, D-70, CB, CB, CB+80)); reg('5', g, 'U')
    g = mk(); g.stroke(oct_(0, D-20, CB, 415, 62)); g.stroke("M 0 300 L 0 %d L 70 %d L %d %d" % (CT-70, CT, D-60, CT)); reg('6', g, 'U')
    g = mk(); g.stroke("M 0 %d L %d %d L 60 %d" % (CT, D, CT, CB)); reg('7', g, 'U')
    g = mk(); g.stroke(oct_(5, D, CB, 385, 62)); g.stroke(oct_(25, D-20, 340, CT, 62)); reg('8', g, 'U')
    g = mk(); g.stroke(oct_(20, D+0, 285, CT, 62)); g.stroke("M %d 400 L %d %d L %d %d L 20 %d" % (D, D, CB+70, D-70, CB, CB)) if False else None
    g.stroke("M %d 400 L %d %d L %d %d L 25 %d L -5 %d" % (D, D, CB+70, D-70, CB, CB, CB+65)); reg('9', g, 'U')
digits()

# ------------------------------------------------------------ punctuation
def dot(g, x, y, s=1.0):
    r = 50*s; g.poly(diamond(x, y+r, r*0.95, r*1.1))
def tpr(pts):
    n = len(pts); return [1.0 - 0.45*(i/(n-1)) for i in range(n)]
def amp_spec():
    return ("M 400 38 L 255 195 L 150 325 L 112 440 L 128 560 L 190 625 L 252 580 L 246 480 L 190 400 L 110 310 L 62 210 L 72 110 L 140 45 L 230 35 L 310 80 L 355 160")
def at_(mk):
    g = mk(); g.stroke("E 290 290 275 285 40 355", pen=P2); g.stroke("E 300 285 95 95 0 360", pen=P2); g.stroke("M 395 400 L 395 190 L 440 190 L 480 250", pen=P2)
    return g
PP = dict(cap=CAP, xh=XH, asc=ASC, desc=DESC, dot=dot, pen2=P2, pen3=PT, dr=100, tail=(40, 100), tailscale=[1.0, 0.7],
          taper=tpr, qspec="M -105 560 L -35 640 L 40 665 L 110 620 L 120 545 L 60 450 L 10 360 L 10 300", qh=170, qgap=100, tickscale=None,
          dashy=265, hy=190, en=360, em=720, ul=-70, uw=520, ellg=150, my=270, mw=230, eqg=140, ah=150, sl=(-60, 760, 280),
          bw=130, pw=140, tw=260, ty=300, cw=180, star=95, hw=360, hh=640, sw=300, amp=amp_spec(), pr=95, pw2=470, at=at_,
          sspec="M 290 500 L 260 600 L 170 650 L 80 610 L 40 520 L 100 430 L 200 365 L 285 285 L 285 190 L 210 100 L 120 70 L 30 110",
          mk=75, mgap=60, mup_u=40)

def build():
    spec = Spec()
    for key, (g, cat, kw) in L.items():
        cs = g.result()
        cp = ord(key) if len(key) == 1 else (0xDF if key == 'germandbls' else None)
        spec.add(gname(cp) if cp else key, cs, cp=cp, cat=cat, anchor=kw.get('anchor'))
    # punctuation
    for key, g in punct(mk, PP).items():
        spec.add(gname(ord(key)), g.result(), cp=ord(key), cat='p')
    spec.add('dotlessi_', [], cp=None) if False else None
    spec.g['dotlessi']['cp'] = 0x131
    return spec

def extras(spec):
    ligature(spec, 'A', 'E', 'AE', 0xC6, 90, 'U')
    ligature(spec, 'a', 'e', 'ae', 0xE6, 70, 'l')
    g = mk(); g.add_contours(spec.g['o']['cs']); g.stroke("M 20 20 L %d 480" % (W-20), pen=P2); spec.add('oslash', g.result(), cp=0xF8, cat='l')
    g = mk(); g.add_contours(spec.g['O']['cs']); g.stroke("M 25 -10 L 295 710", pen=P2); spec.add('Oslash', g.result(), cp=0xD8, cat='U')
    spec.add('space', [], cp=0x20, adv=230); spec.add('nbspace', [], cp=0xA0, adv=230)
    g = mk(); g.poly([(60, 0), (440, 0), (440, 700), (60, 700)]); g.cutpoly([(120, 60), (120, 640), (380, 640), (380, 60)])
    spec.add('.notdef', g.result(), cp=None, sb=(60, 60))
    return spec

KERN_PUNCT = ".,!?'\"\u2018\u2019\u201c\u201d-:;"

def main():
    spec = extras(build())
    finish_metrics(spec, S0=44, f=0.55, D=95, caps_S0=48)
    spec.g['space']['adv'] = 230; spec.g['nbspace']['adv'] = 230
    compose_accents(spec, PP, mk)
    # fixed-width bearings for composed .notdef etc handled in finish_metrics
    names = [gname(ord(c)) for c in LOWER + UPPER + DIGITS + KERN_PUNCT + ACC_UP + ACC_LO if gname(ord(c)) in spec.g]
    tl = ref_gap(spec, 'n', 'n'); tu = ref_gap(spec, 'H', 'H')
    pairs = kern_table(spec, names, tl, tu, mingap=34)
    print('kern pairs', len(pairs), 'ref gaps', round(tl), round(tu))
    fea = 'languagesystem DFLT dflt;\nlanguagesystem latn dflt;\n' + fea_kern(pairs)
    out = os.path.join(HERE, 'LyraGothic-Regular.ttf')
    build_ttf(spec, out, None, fea, dict(family=NAME, copyright='Copyright 2026 The Lyra Project Authors. Licensed under the SIL Open Font License 1.1.',
              description='Lyra Gothic: modern Textura-spirit blackletter display face, procedurally drawn.'))
    print('wrote', out)
    specimen(out, os.path.join(HERE, 'specimen.png'), 'Lyra Gothic Regular')
    print(verify(out))

if __name__ == '__main__':
    main()
