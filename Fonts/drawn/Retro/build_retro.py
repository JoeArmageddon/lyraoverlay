"""Lyra Retro: 80s synthwave italic with a horizontal slit.  Run: python build_retro.py"""
import os, sys, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from lyra_build import *

SLANT = math.tan(math.radians(14))
SLIT_Y0, SLIT_Y1 = 184.0, 214.0


class Retro(Style):
    name = 'Retro'; family = 'Lyra Retro'; ps = 'LyraRetro-Regular'
    description = "Wide 80s synthwave italic, rounded outer corners, signature horizontal slit."
    italic_angle = -14
    w = 128; wl = 128
    dotr = 64; pgap = 46; dsp = 40
    DASHY = 350; COLONY = 400; USC = 60
    straightq = True
    iserif = 0.0
    abar = 0.40; f4bar = 0.42
    wscale = 1.12; scw = 0.92; scwf = 0.96; SC = 546
    real_lower = False
    mode = 'round'; kmul = 1.25; nr = 0; mcap = 190
    cap = LineCap.BUTT_CAP; join = LineJoin.MITER_JOIN; miter = 10
    sb = 46; sb_p = 56; opt = 0.30; mind = 36
    space = 300
    sxheight = 546
    mark_wf = 0.8; mark_gap = 34; mark_h = 56; mark_hw = 74; mark_dotr = 42
    ROUND = 24

    def dot_shape(self, x, y, r):
        return poly_path([(x - r, y - r), (x + r, y - r), (x + r, y + r), (x - r, y + r)])


def finish(path, ch, rng, items):
    p = round_convex(path, Retro.ROUND)
    p = p.transform(1, 0, SLANT, 1, 0, 0)
    x0, y0, x1, y1 = p.bounds
    slit = poly_path([(x0 - 50, SLIT_Y0), (x1 + 50, SLIT_Y0), (x1 + 50, SLIT_Y1), (x0 - 50, SLIT_Y1)])
    return difference(p, slit)


if __name__ == '__main__':
    st = Retro()
    ttf, order, gn = build_font(st, finish, HERE, 'LyraRetro-Regular.ttf')
    verify(ttf, st)
    specimen(ttf, os.path.join(HERE, 'specimen.png'), st, 'Lyra Retro')
    print('done', ttf)
