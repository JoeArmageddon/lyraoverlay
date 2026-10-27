#!/usr/bin/env python3
"""Lyra Brush generator.  Flat chisel-nib pen model + edge roughening + dry-brush streaks.
Run:  /tmp/fontvenv/bin/python build_brush.py   (needs fontTools, skia-pathops, pillow, numpy)
"""
import sys, os, math, random, zlib, pickle
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "_shared"))
from lyra_common import *
from print_skel import *
from lyra_pipeline import *

FAMILY, PSNAME = "Lyra Brush", "LyraBrush-Regular"
OUT = os.path.join(HERE, "LyraBrush-Regular.ttf")

P = 62            # skeleton inset (approx. half stem width)
DOT_R = 76        # fat round full stops
LEAN = 6.0
NIB_ANGLE = 34.0  # chisel angle (deg from horizontal)
NIB_LEN = 138.0
NIB_T = 36.0
ACC_P = 0.7

def nib_poly(scale=1.0):
    a = math.radians(NIB_ANGLE)
    L, t = NIB_LEN * scale / 2, NIB_T * scale / 2
    ux, uy = math.cos(a), math.sin(a)
    nx, ny = -uy, ux
    pts = []
    for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        pts.append((ux * L * sx + nx * t * sy, uy * L * sx + ny * t * sy))
    # slightly rounded corners for a worn brush
    out = []
    for i in range(4):
        a_, b_ = pts[i], pts[(i + 1) % 4]
        out.append((a_[0] * 0.94 + b_[0] * 0.06, a_[1] * 0.94 + b_[1] * 0.06))
        out.append((a_[0] * 0.06 + b_[0] * 0.94, a_[1] * 0.06 + b_[1] * 0.94))
    return out

def glyph_conts(ch, sp):
    rnd = random.Random(zlib.crc32(ch.encode()) ^ 0xB12)
    strokes = [list(s) for s in sp["s"]]
    dots = list(sp["dots"])
    nb = sp.get("nb", len(strokes))
    nbd = sp.get("nbd", len(dots))
    # per-stroke hand wobble (kept inside the glyph; metrics stay on the baseline)
    new = []
    for s in strokes:
        cx = sum(q[0] for q in s) / len(s); cy = sum(q[1] for q in s) / len(s)
        a = math.radians(rnd.uniform(-1.6, 1.6)); dy = rnd.uniform(-5, 5); dx = rnd.uniform(-4, 4)
        new.append([(cx + dx + (x - cx) * math.cos(a) - (y - cy) * math.sin(a), cy + dy + (x - cx) * math.sin(a) + (y - cy) * math.cos(a)) for x, y in s])
    strokes = new
    t = math.tan(math.radians(LEAN))
    strokes = [[(x + (y - 350) * t, y) for x, y in s] for s in strokes]
    dots = [(x + (y - 350) * t, y) for x, y in dots]
    path = Path()
    nib = nib_poly(); nib_a = nib_poly(ACC_P)
    for i, s in enumerate(strokes):
        pts = resample(s, 6.0) if len(s) > 1 else s
        pl = nib if i < nb else nib_a
        sweep(pts, [pl] * len(pts), path)
    for i, d_ in enumerate(dots):
        r = DOT_R if i < nbd else DOT_R * 0.6
        sweep([d_], [circle_poly(r, 32)], path)
    finish(path)
    conts = contours_of(path)
    conts = roughen(conts, zlib.crc32(ch.encode()), amp_big=4.2, amp_small=1.6, scale_big=55, scale_small=12, step=8)
    path = path_from_contours(conts)
    finish(path)
    # dry-brush streaks: thin slits entering from stroke tails
    cut = Path()
    for i, s in enumerate(strokes[:nb]):
        L = sum(math.hypot(s[k + 1][0] - s[k][0], s[k + 1][1] - s[k][1]) for k in range(len(s) - 1)) if len(s) > 1 else 0
        if L < 190 or math.hypot(s[0][0]-s[-1][0], s[0][1]-s[-1][1]) < 4:
            continue
        nstreak = 1 if L < 400 else 2
        pts = resample(s, 8.0)
        for k in range(nstreak):
            if rnd.random() < 0.25:
                continue
            fromend = rnd.random() < 0.6
            frac = rnd.uniform(0.2, 0.36)
            m = max(4, int(len(pts) * frac))
            seg = pts[-m:] if fromend else pts[:m]
            off = rnd.choice((-1, 1)) * rnd.uniform(14, 26)
            # offset along local normal, extend 40 units beyond the tail
            out = []
            for j in range(len(seg)):
                a_ = seg[max(0, j - 1)]; b_ = seg[min(len(seg) - 1, j + 1)]
                dx, dy = b_[0] - a_[0], b_[1] - a_[1]; l = math.hypot(dx, dy) or 1
                out.append((seg[j][0] - dy / l * off, seg[j][1] + dx / l * off))
            e = out[-1] if fromend else out[0]
            q = out[-2] if fromend else out[1]
            dx, dy = e[0] - q[0], e[1] - q[1]; l = math.hypot(dx, dy) or 1
            ext = (e[0] + dx / l * 60, e[1] + dy / l * 60)
            out = out + [ext] if fromend else [ext] + out
            w = rnd.uniform(4.5, 7.0)
            pp = resample(out, 5.0)
            rs = [circle_poly(w * (0.55 + 0.45 * math.sin(math.pi * min(1, (j + 1) / (len(pp) * 0.5)))) if False else w, 10) for j in range(len(pp))]
            # taper the slit towards its inner end so it ends in a point
            rs = []
            for j in range(len(pp)):
                u = j / (len(pp) - 1)
                u = u if not fromend else 1 - u
                # u=0 at the outer tail end (index 0 for fromend False) ; width fades towards inner end
                fade = 1.0 if fromend is False and u < 0.25 else 1.0
                tt = (j / (len(pp) - 1)) if not fromend else 1 - j / (len(pp) - 1)
                rs.append(circle_poly(max(1.5, w * (1.0 - 0.7 * tt)), 10))
            sweep(pp, rs, cut)
    finish(cut)
    res = pathop(path, cut, "diff")
    conts = [c for c in contours_of(res) if abs(area(c)) > 90]
    return conts

def build():
    import print_skel; print_skel.RING_S = 1.3
    geo = Geo(P, dot_r=DOT_R, wscale=1.08, variant="brush")
    spec = build_all(geo, acc_scale=ACC_P, lo_gap=50, cap_gap=12)
    raw = {ch: glyph_conts(ch, spec[ch]) for ch in ALL_CHARS}
    cfg = dict(
        S={"up": 30, "lo": 28, "dig": 30, "pun": 40}, k={"up": 0.3, "lo": 0.3, "dig": 0.3, "pun": 0.2},
        depth=100, space=230, mingap=18, kern_strength=0.75,
        kern_refs={"uu": [("H", "H"), ("H", "O"), ("O", "H"), ("O", "O")], "ul": [("H", "n"), ("H", "o"), ("O", "n"), ("O", "o")],
                   "lu": [("n", "H"), ("o", "H"), ("n", "O"), ("o", "O")], "ll": [("n", "n"), ("n", "o"), ("o", "n"), ("o", "o")]},
        adj={}, max_tighten=150, max_loosen=15)
    glyphs, adv, kp, polys = assemble(raw, cfg)
    fea = kern_fea(kp, ALL_CHARS + " ")
    meta = dict(description="Dry brush marker display face. Original design.", fea=fea, weight=700)
    build_font(OUT, FAMILY, PSNAME, glyphs, adv, None, ALL_CHARS + " ", meta)
    return kp

TEST_LINES = ["Midnight in the city lights", "HOLD ME CLOSER, TONIGHT!", "Quick zephyrs blow, vexing daft Jim. 0123456789", "Can't stop (won't stop) - 100% yours & mine?"]
ROWS = [UPPER, LOWER, DIGITS + "  " + BASIC_PUNCT[:20], BASIC_PUNCT[20:] , ACCENT_UP, ACCENT_LO]

if __name__ == "__main__":
    kp = build()
    print("kern pairs", len(kp))
    probs, info = verify(OUT, ALL_CHARS)
    print(probs, info)
    make_specimen(OUT, os.path.join(HERE, "specimen.png"), "Lyra Brush", "Regular - OFL 1.1", TEST_LINES, ROWS)
