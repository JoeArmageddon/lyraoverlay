"""Lyra Forge Drawn: heavy-metal jagged capitals (serrated outer edges, spiked terminals).
Run: python build_forge.py"""
import os, sys, math, random
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from lyra_build import *


def spike(pts, k, width, rng):
    E = pts[k][:2]
    N = pts[1][:2] if k == 0 else pts[-2][:2]
    d = unit(N, E)                      # outward direction
    p = (-d[1], d[0])
    half = width / 2.0
    Ls = 0.55 * width
    r = rng.random()
    back = 6.0
    if r < 0.17:                        # barb: curled horn
        s = rng.choice((-1, 1))
        Lb = 1.45 * width
        P0 = E; P1 = (E[0] + d[0] * Lb, E[1] + d[1] * Lb)
        P2 = (E[0] + d[0] * Lb * 0.55 + p[0] * s * Lb * 0.95, E[1] + d[1] * Lb * 0.55 + p[1] * s * Lb * 0.95)
        left = []; right = []
        n = 12
        for i in range(n + 1):
            t = i / n
            mt = 1 - t
            cx = mt * mt * P0[0] + 2 * mt * t * P1[0] + t * t * P2[0]
            cy = mt * mt * P0[1] + 2 * mt * t * P1[1] + t * t * P2[1]
            tx = 2 * mt * (P1[0] - P0[0]) + 2 * t * (P2[0] - P1[0])
            ty = 2 * mt * (P1[1] - P0[1]) + 2 * t * (P2[1] - P1[1])
            L = math.hypot(tx, ty) or 1
            nx, ny = -ty / L, tx / L
            hw = half * (1 - t) ** 0.9
            left.append((cx + nx * hw, cy + ny * hw)); right.append((cx - nx * hw, cy - ny * hw))
        base = [(E[0] - d[0] * back + p[0] * half, E[1] - d[1] * back + p[1] * half)]
        base2 = [(E[0] - d[0] * back - p[0] * half, E[1] - d[1] * back - p[1] * half)]
        return base + left + right[::-1] + base2
    s = rng.choice((-1, 1))
    off = (half if r < 0.6 else 0.25 * half * s)      # diagonal cut vs centred point
    tip = (E[0] + d[0] * Ls + p[0] * off * (s if r < 0.6 else 1), E[1] + d[1] * Ls + p[1] * off * (s if r < 0.6 else 1))
    return [(E[0] - d[0] * back + p[0] * half, E[1] - d[1] * back + p[1] * half),
            (E[0] + p[0] * half, E[1] + p[1] * half), tip,
            (E[0] - p[0] * half, E[1] - p[1] * half),
            (E[0] - d[0] * back - p[0] * half, E[1] - d[1] * back - p[1] * half)]


class Forge(Style):
    name = 'Forge'; family = 'Lyra Forge Drawn'; ps = 'LyraForgeDrawn-Regular'
    description = "Heavy-metal jagged capitals with serrated outer edges and spiked terminals."
    w = 140; wl = 140
    dotr = 68; pgap = 56; dsp = 40
    DASHY = 330; COLONY = 400; USC = 60
    straightq = True
    iserif = 0.0
    hook = 0.15
    abar = 0.32; f4bar = 0.36
    wscale = 0.98; scw = 0.92; scwf = 0.92; SC = 560
    real_lower = False
    mode = 'chamfer'; nr = 0; mcap = 120
    cap = LineCap.BUTT_CAP; join = LineJoin.MITER_JOIN; miter = 6
    sb = 44; sb_p = 54; opt = 0.28; mind = 46
    space = 300
    sxheight = 560
    mark_wf = 0.72; mark_gap = 40; mark_h = 56; mark_hw = 64; mark_dotr = 40
    AMP = 34; PERIOD = 80; MARGIN = 18; CLEAR = 72

    def dot_shape(self, x, y, r):
        return poly_path([(x, y - 1.3 * r), (x + r, y), (x, y + 1.3 * r), (x - r, y)])


st_ = Forge()
Forge.spike = staticmethod(spike)


def serrate(path, rng, amp=None):
    amp = amp or Forge.AMP
    path = clean(path)
    cont = [flatten(c, 4) for c in path.contours]
    polys = [pl[0] for pl in cont if pl]
    # edges for clearance
    segs = []
    for ci, pl in enumerate(polys):
        n = len(pl)
        for i in range(n):
            segs.append((ci, i, pl[i], pl[(i + 1) % n]))
    A = np.array([s[2] for s in segs]); B = np.array([s[3] for s in segs])
    cid = np.array([s[0] for s in segs]); eid = np.array([s[1] for s in segs])
    cnt = {ci: len(pl) for ci, pl in enumerate(polys)}

    def clearance(m, ci, i):
        ab = B - A
        l2 = (ab ** 2).sum(1) + 1e-9
        t = np.clip(((m - A) * ab).sum(1) / l2, 0, 1)
        proj = A + ab * t[:, None]
        dd = np.hypot(*(proj - m).T)
        n = cnt[ci]
        mask = (cid == ci) & ((np.abs(eid - i) <= 1) | (np.abs(eid - i) >= n - 1))
        dd[mask] = 1e9
        return dd.min()

    out = Path()
    for ci, pl in enumerate(polys):
        n = len(pl)
        x = pl[:, 0]; y = pl[:, 1]
        area = 0.5 * np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y)
        pts = []
        if area < 0:                    # outer (clockwise)
            for i in range(n):
                p0 = pl[i]; p1 = pl[(i + 1) % n]
                pts.append(tuple(p0))
                Le = math.dist(p0, p1)
                u = ((p1 - p0) / max(Le, 1e-9))
                nrm = np.array([-u[1], u[0]])
                use = Le - 2 * Forge.MARGIN
                nt = int(use // Forge.PERIOD)
                if nt < 1:
                    continue
                pitch = use / nt
                for k in range(nt):
                    a = p0 + u * (Forge.MARGIN + k * pitch)
                    b = a + u * pitch
                    mid = (a + b) / 2
                    c = clearance(mid, ci, i)
                    A_k = amp * (0.75 + 0.5 * rng.random())
                    A_k = min(A_k, max(0.0, (c - Forge.CLEAR) / 2.0))
                    if A_k < 5:
                        continue
                    apex = a + u * pitch * (0.5 + 0.12 * (rng.random() - 0.5)) + nrm * A_k
                    pts += [tuple(a), tuple(apex), tuple(b)]
        else:
            pts = [tuple(q) for q in pl]
        out.moveTo(*pts[0])
        for q in pts[1:]:
            out.lineTo(*q)
        out.close()
    return clean(out)


def finish(path, ch, rng, items):
    return serrate(path, rng)


if __name__ == '__main__':
    st = Forge()
    ttf, order, gn = build_font(st, finish, HERE, 'LyraForgeDrawn-Regular.ttf')
    verify(ttf, st)
    specimen(ttf, os.path.join(HERE, 'specimen.png'), st, 'Lyra Forge Drawn')
    print('done', ttf)
