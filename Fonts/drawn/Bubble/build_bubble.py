"""Lyra Bubble: inflated bubble letters, generated procedurally.  Run: python build_bubble.py"""
import os, sys, math, random, hashlib
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from lyra_build import *


class Bubble(Style):
    name = 'Bubble'; family = 'Lyra Bubble'; ps = 'LyraBubble-Regular'
    description = "Fat inflated bubble capitals and lowercase, round counters, playful bounce."
    w = 148; wl = 116
    dotr = 92; pgap = 56
    DASHY = 300; COLONY = 400; USC = 60
    iserif = 0.78
    abar = 0.30; f4bar = 0.34
    wscale = 1.0; wscale_l = 1.0
    ov = 8
    real_lower = True
    mode = 'round'; kmul = 1.0; nr = 70; mcap = 10000
    IDOT = 668; TTOP = 668
    sb = 36; sb_p = 46; opt = 0.30; mind = 34
    space = 270
    sxheight = 500
    mark_wf = 0.62; mark_gap = 44; mark_h = 62; mark_hw = 58; mark_dotr = 44
    seed_bounce = True


def finish(path, ch, rng, items):
    # playful bounce: small deterministic vertical offset and tilt per glyph
    h = int(hashlib.md5(ch.encode('utf-8')).hexdigest()[:6], 16)
    dy = ((h % 7) - 3) * 3.5
    ang = (((h >> 8) % 5) - 2) * 0.9
    x0, y0, x1, y1 = path.bounds
    cx, cy = (x0 + x1) / 2, 250
    a = math.radians(ang)
    ca, sa = math.cos(a), math.sin(a)
    if ch in "-–—_|":
        dy, a = 0, 0; ca, sa = 1, 0
    tx = cx - (ca * cx - sa * cy); ty = cy - (sa * cx + ca * cy) + dy
    return path.transform(ca, sa, -sa, ca, tx, ty)


if __name__ == '__main__':
    st = Bubble()
    ttf, order, gn = build_font(st, finish, HERE, 'LyraBubble-Regular.ttf')
    f = verify(ttf, st)
    specimen(ttf, os.path.join(HERE, 'specimen.png'), st, 'Lyra Bubble')
    print('done', ttf)
