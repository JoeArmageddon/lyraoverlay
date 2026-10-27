#!/usr/bin/env python3
"""Lyra Script generator: pressure-sensitive pointed-pen model, 12 degree slant, baseline joins.
Run: /tmp/fontvenv/bin/python build_script.py"""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, "..", "_shared"))
from lyra_common import *
import print_skel
from print_skel import Geo, ACC, accent_marks, compose_accents
from lyra_pipeline import *
from script_skel import *

FAMILY, PSNAME = "Lyra Script", "LyraScript-Regular"
OUT = os.path.join(HERE, "LyraScript-Regular.ttf")
SLANT = 12.0
RMIN, RMAX = 15.0, 43.0
DOT_R = 29

def pressure_stroke(path, s, pw=1.0, rmin=RMIN, rmax=RMAX):
    if len(s) == 1:
        sweep([s[0]], [circle_poly(rmax * 0.7 * pw, 24)], path); return
    pts = resample(s, 5.0)
    n = len(pts)
    rs = []
    for i in range(n):
        a, b = pts[max(0, i - 2)], pts[min(n - 1, i + 2)]
        dx, dy = b[0] - a[0], b[1] - a[1]; l = math.hypot(dx, dy) or 1
        down = max(0.0, -dy / l)
        rs.append(rmin + (rmax - rmin) * down ** 1.25)
    sm = []
    for i in range(n):
        w = rs[max(0, i - 4): i + 5]
        sm.append(sum(w) / len(w))
    sweep(pts, [circle_poly(r * pw, 20) for r in sm], path)

def render(sp, pw=1.0):
    t = math.tan(math.radians(SLANT))
    sh = lambda q: (q[0] + (q[1] - J) * t, q[1])
    path = Path()
    nb = sp.get("nb", len(sp["s"]))
    for i, s in enumerate(sp["s"]):
        pressure_stroke(path, [sh(q) for q in s], pw * (1.0 if i < nb else 0.62))
    nbd = sp.get("nbd", len(sp["dots"]))
    for i, d in enumerate(sp["dots"]):
        sweep([sh(d)], [circle_poly(DOT_R * pw * (1 if i < nbd else 0.7), 24)], path)
    finish(path)
    return contours_of(path)

def build():
    low = lower(); cap = caps(); dig = digits()
    geo = Geo(24, dot_r=27)
    pun = geo.punct()
    spec = {}
    spec.update(low); spec.update(cap); spec.update(dig); spec.update(pun)
    # specials
    a, e, o = low["a"], low["e"], low["o"]
    spec["æ"] = dict(s=[a["s"][0], a["s"][1], a["s"][2][:-0 or None]] if False else [a["s"][0], a["s"][1], spline([(268, 492), (268, 250), (268, 100)], t0=(0, -1))] + [[(x + 268, y) for x, y in s] for s in e["s"][1:]], adv=268 + e["adv"], dots=[], ax=268, kind="lo")
    spec["ø"] = dict(s=o["s"] + [spline([(250, 420), (150, 250), (50, 70)])], adv=o["adv"], dots=[], ax=o["ax"], kind="lo")
    spec["ß"] = dict(s=[asc_loop(), spline([(106, 440), (190, 520), (270, 450), (245, 350), (130, 300)]), spline([(130, 300), (275, 255), (300, 130), (225, 30), (120, 12)]), ext(120, 8, 330)], adv=330, dots=[], ax=150, kind="lo")
    Aa, Ee = cap["A"], cap["E"]
    spec["Æ"] = dict(s=Aa["s"] + [[(x + 300, y) for x, y in s] for s in Ee["s"]], dots=[], ax=300, kind="up")
    spec["Ø"] = dict(s=cap["O"]["s"] + [spline([(400, 650), (230, 380), (70, 70)])], dots=[], ax=cap["O"]["ax"], kind="up")
    XS = {"lo": 1.38, "up": 1.22, "x": 1.3}
    for ch in list(spec):
        sp = spec[ch]
        if ch in LOWER or ch in "æøß" or ch in UPPER or ch in "ÆØ" or ch in DIGITS:
            f = XS["lo"] if (ch in LOWER or ch in "æøß") else XS["up"] if (ch in UPPER or ch in "ÆØ") else XS["x"]
            sp["s"] = [[(x * f, y) for x, y in st] for st in sp["s"]]
            sp["dots"] = [(x * f, y) for x, y in sp["dots"]]
            sp["ax"] = sp["ax"] * f
            if "adv" in sp: sp["adv"] *= f
    compose_accents(spec, 20, acc_scale=0.9, cap_gap=40, lo_gap=46)
    # accented lowercase inherit advance/exit from base
    for ch, (b, k) in ACC.items():
        if ch in ACCENT_LO:
            spec[ch]["adv"] = spec[b]["adv"]
    raw, fixed_adv = {}, {}
    for ch in ALL_CHARS:
        sp = spec[ch]
        pw = 1.12 if ch in UPPER or ch in ACCENT_UP else 1.18 if (ch in BASIC_PUNCT or ch in DIGITS) else 1.0
        raw[ch] = render(sp, pw)
        if "adv" in sp:
            fixed_adv[ch] = sp["adv"]
    fixed = set(ch for ch in ALL_CHARS if ch in fixed_adv)
    cfg = dict(S={"up": 34, "lo": 0, "dig": 40, "pun": 55}, k={"up": 0.3, "lo": 0, "dig": 0.3, "pun": 0.2},
               fixed=fixed, depth=110, space=240, mingap=22, kern_strength=0.8, skip_lo_lo=True,
               kern_refs={"uu": [("H", "H"), ("H", "O"), ("O", "H"), ("O", "O")], "ul": [("H", "n"), ("H", "o"), ("O", "n"), ("O", "o")],
                          "lu": [("n", "H"), ("o", "H"), ("n", "O"), ("o", "O")], "ll": [("n", "n"), ("n", "o"), ("o", "n"), ("o", "o")]},
               adj={}, max_tighten=160, max_loosen=15)
    glyphs, adv, kp, polys = assemble(raw, cfg, fixed_adv)
    fea = kern_fea(kp, ALL_CHARS + " ")
    meta = dict(description="Elegant connected script. Original design.", fea=fea)
    build_font(OUT, FAMILY, PSNAME, glyphs, adv, None, ALL_CHARS + " ", meta)
    return kp

TEST_LINES = ["Midnight in the city lights", "HOLD ME CLOSER, TONIGHT!", "Quick zephyrs blow, vexing daft Jim. 0123456789", "Can't stop (won't stop) - 100% yours & mine?"]
ROWS = [UPPER, LOWER, DIGITS + "  " + BASIC_PUNCT[:20], BASIC_PUNCT[20:], ACCENT_UP, ACCENT_LO, "ff fi th tt ll ee oo Hello Always"]

if __name__ == "__main__":
    kp = build(); print("kern pairs", len(kp))
    probs, info = verify(OUT, ALL_CHARS); print(probs, info)
    make_specimen(OUT, os.path.join(HERE, "specimen.png"), "Lyra Script", "Regular - OFL 1.1", TEST_LINES, ROWS)
