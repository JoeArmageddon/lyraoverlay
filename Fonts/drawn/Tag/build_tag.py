#!/usr/bin/env python3
"""Lyra Tag generator.  Round-marker pen model + built-in offset outline (drop shadow).
Run:  /tmp/fontvenv/bin/python build_tag.py   (needs fontTools, skia-pathops, pillow, numpy)
"""
import sys, os, math, random, zlib, pickle
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "_shared"))
from lyra_common import *
from print_skel import *
from lyra_pipeline import *

FAMILY, PSNAME = "Lyra Tag", "LyraTag-Regular"
OUT = os.path.join(HERE, "LyraTag-Regular.ttf")

P = 47           # marker half-thickness
DOT_R = 58
LEAN = 9.0        # forward lean in degrees
SH_DX, SH_DY = 30, -30   # drop-shadow offset (lower right)
SH_T = 16         # shadow outline thickness
SH_GAP = 14       # clear gap between letter and shadow outline
ACC_P = 0.66      # accent pen scale

def exposed_ends(strokes, nb, r):
    res = []
    for i, s in enumerate(strokes[:nb]):
        ends = []
        if len(s) < 2:
            res.append(ends); continue
        closed = math.hypot(s[0][0] - s[-1][0], s[0][1] - s[-1][1]) < 2
        for which, pt in (("start", s[0]), ("end", s[-1])):
            if closed:
                continue
            near = False
            for j, o in enumerate(strokes[:nb]):
                if j == i:
                    # skip own points close in arclength; test only far part
                    cand = o[len(o) // 3: 2 * len(o) // 3] if len(o) > 12 else []
                else:
                    cand = o
                for q in cand:
                    if math.hypot(q[0] - pt[0], q[1] - pt[1]) < r * 1.35:
                        near = True
                        break
                if near:
                    break
            if not near:
                ends.append(which)
        res.append(ends)
    return res

def jitter(ch):
    rnd = random.Random(zlib.crc32(ch.encode()) ^ 0x7A6)
    return rnd.uniform(-18, 18), rnd.uniform(-3, 3)

def glyph_body(ch, sp):
    strokes = [list(s) for s in sp["s"]]
    dots = list(sp["dots"])
    nb = sp.get("nb", len(strokes))
    nbd = sp.get("nbd", len(dots))
    # bounce + lean (applied to centre-lines before inflating)
    dy, rot = jitter(ch)
    allp = [q for s in strokes for q in s] + dots
    cx = sum(q[0] for q in allp) / len(allp)
    cy = 350
    def tf(q):
        x, y = q
        a = math.radians(rot)
        x2 = cx + (x - cx) * math.cos(a) - (y - cy) * math.sin(a)
        y2 = cy + (x - cx) * math.sin(a) + (y - cy) * math.cos(a) + dy
        return (x2 + (y2 - 350) * math.tan(math.radians(LEAN)) , y2)
    strokes = [[tf(q) for q in s] for s in strokes]
    dots = [tf(q) for q in dots]
    ends = exposed_ends(strokes, nb, P)
    path = Path()
    for i, s in enumerate(strokes):
        r = P if i < nb else P * ACC_P
        pts = resample(s, 5.0) if len(s) > 1 else s
        circ = circle_poly(r, 28)
        sweep(pts, [circ] * len(pts), path)
        if i < nb and len(pts) > 2:
            for which in ends[i]:
                if which == "end":
                    e, pr = pts[-1], pts[-4]
                    sgn = 1
                else:
                    e, pr = pts[0], pts[3]
                    sgn = -1
                d = (e[0] - pr[0], e[1] - pr[1]); l = math.hypot(*d) or 1
                d = (d[0] / l, d[1] / l); nrm = (-d[1], d[0])
                tip = (e[0] + d[0] * r * 2.0 + nrm[0] * r * 0.75 * sgn, e[1] + d[1] * r * 2.0 + nrm[1] * r * 0.75 * sgn)
                h = hull([(e[0] + x, e[1] + y) for x, y in circle_poly(r, 28)] + [tip])
                add_poly(path, h)
    for i, d_ in enumerate(dots):
        r = DOT_R if i < nbd else DOT_R * 0.62
        sweep([d_], [circle_poly(r, 32)], path)
    finish(path)
    return path

def glyph_with_shadow(ch, sp):
    body = glyph_body(ch, sp)
    bc = contours_of(body)
    shifted = translate_conts(bc, SH_DX, SH_DY)
    ring = outline_ring(shifted, SH_T)
    cut = grow(bc, SH_GAP)
    vis = pathop(ring, cut, "diff")
    vc = [c for c in contours_of(vis) if abs(area(c)) > 140]
    final = pathop(body, path_from_contours(vc), "union")
    return contours_of(final)

def build():
    import print_skel; print_skel.RING_S = 1.2
    geo = Geo(P, dot_r=DOT_R, wscale=1.1, variant="tag")
    spec = build_all(geo, acc_scale=ACC_P, lo_gap=50, cap_gap=24)
    cache = os.path.join(HERE, ".cache.pkl")
    raw = {}
    for i, ch in enumerate([c for c in ALL_CHARS]):
        raw[ch] = glyph_with_shadow(ch, spec[ch])
    cfg = dict(
        S={"up": 42, "lo": 40, "dig": 42, "pun": 50}, k={"up": 0.32, "lo": 0.34, "dig": 0.32, "pun": 0.2},
        depth=100, space=250, mingap=30, kern_strength=0.7,
        kern_refs={"uu": [("H", "H"), ("H", "O"), ("O", "H"), ("O", "O")], "ul": [("H", "n"), ("H", "o"), ("O", "n"), ("O", "o")],
                   "lu": [("n", "H"), ("o", "H"), ("n", "O"), ("o", "O")], "ll": [("n", "n"), ("n", "o"), ("o", "n"), ("o", "o")]},
        adj={}, max_tighten=140, max_loosen=15)
    glyphs, adv, kp, polys = assemble(raw, cfg)
    fea = kern_fea(kp, ALL_CHARS + " ")
    meta = dict(description="Street tag lettering with built-in offset outline. Original design.", fea=fea)
    build_font(OUT, FAMILY, PSNAME, glyphs, adv, None, ALL_CHARS + " ", meta)
    return kp

TEST_LINES = ["Midnight in the city lights", "HOLD ME CLOSER, TONIGHT!", "Quick zephyrs blow, vexing daft Jim. 0123456789", "Can't stop (won't stop) - 100% yours & mine?"]
ROWS = [UPPER, LOWER, DIGITS + "  " + BASIC_PUNCT[:20], BASIC_PUNCT[20:] , ACCENT_UP, ACCENT_LO]

if __name__ == "__main__":
    kp = build()
    print("kern pairs", len(kp))
    probs, info = verify(OUT, ALL_CHARS)
    print(probs, info)
    make_specimen(OUT, os.path.join(HERE, "specimen.png"), "Lyra Tag", "Regular - OFL 1.1", TEST_LINES, ROWS)
