"""Upright 'print' skeleton (centre-lines) shared by Lyra Brush and Lyra Tag,
plus punctuation / accent builders reused by Lyra Script.  Original geometry.

Each glyph spec: {'s': [strokes], 'dots': [(x,y)], 'ax': accent x, 'kind': 'up'|'lo'|'x'}
Coordinates are centre-lines in font units; p = half pen thickness used for insets.
"""
import math
from lyra_common import *

CAP, XH, ASC, DESC = 700, 500, 745, -150
RING_S = 1.0


class Geo:
    def __init__(self, p, dot_r=None, wscale=1.0, variant="tag"):
        self.p = p
        self.dot_r = dot_r or p
        self.ws = wscale
        self.variant = variant
        p_ = p
        self.T = CAP - p_
        self.B = p_
        self.X = XH - p_
        self.A = ASC - p_
        self.D = DESC + p_
        self.M = (self.T + self.B) / 2
        self.cy = (self.X + self.B) / 2
        self.ry = (self.X - self.B) / 2

    # ---------------------------------------------------------------- caps
    def caps(self):
        g = self
        T, B, M, ws = g.T, g.B, g.M, g.ws
        S = {}
        def put(ch, strokes, dots=(), kind="up", ax=None):
            xs = [x for s in strokes for x, y in s]
            if ax is None:
                ax = (min(xs) + max(xs)) / 2
            S[ch] = dict(s=strokes, dots=list(dots), ax=ax, kind=kind)
        W = lambda v: v * ws
        # A
        w = W(470); yb = B + (T - B) * 0.30
        put("A", [poly((0, B), (w / 2, T), (w, B)), poly((w * .2, yb), (w * .8, yb))])
        # B
        w = W(400); m = B + (T - B) * 0.54
        r1 = (T - m) / 2; r2 = (m - B) / 2
        put("B", [poly((0, T), (0, B)),
                  cat(poly((0, T), (w * .88 - w * .42, T)), arc(w * .88 - w * .42, T - r1, w * .42, r1, 90, -90), poly((w * .88 - w * .42, m), (0, m))),
                  cat(poly((0, m), (w - w * .46, m)), arc(w - w * .46, m - r2, w * .46, r2, 90, -90), poly((w - w * .46, B), (0, B)))])
        # C
        w = W(420)
        put("C", [arc(w / 2, M, w / 2, (T - B) / 2, 42, 318)])
        # D
        w = W(420); rx = w * .58
        put("D", [poly((0, T), (0, B)), cat(poly((0, T), (w - rx, T)), arc(w - rx, M, rx, (T - B) / 2, 90, -90), poly((w - rx, B), (0, B)))])
        # E
        w = W(350)
        put("E", [poly((0, T), (0, B)), poly((0, T), (w, T)), poly((0, M), (w * .84, M)), poly((0, B), (w, B))])
        # F
        w = W(340)
        put("F", [poly((0, T), (0, B)), poly((0, T), (w, T)), poly((0, M + 10), (w * .82, M + 10))])
        # G
        w = W(440)
        put("G", [cat(arc(w / 2, M, w / 2, (T - B) / 2, 42, 360), poly((w, M), (w * .52, M)))])
        # H
        w = W(430)
        put("H", [poly((0, T), (0, B)), poly((w, T), (w, B)), poly((0, M), (w, M))])
        # I (slab, distinguishes from l and 1)
        sb = 120
        put("I", [poly((0, T), (0, B)), poly((-sb / 2, T), (sb / 2, T)), poly((-sb / 2, B), (sb / 2, B))])
        # J
        w = W(330); r = w * .5
        put("J", [cat(poly((w, T), (w, B + r)), arc(w - r, B + r, r, r, 0, -180, ), poly((0, B + r), (0, B + r + 60)))])
        # K
        w = W(420); y0 = B + (T - B) * .42
        xa = w * .38; ya = y0 + (T - y0) * xa / w
        put("K", [poly((0, T), (0, B)), poly((w, T), (0, y0)), poly((xa, ya), (w, B))])
        # L
        w = W(340)
        put("L", [poly((0, T), (0, B), (w, B))])
        # M
        w = W(540)
        put("M", [poly((0, B), (0, T), (w / 2, B + (T - B) * .30), (w, T), (w, B))])
        # N
        w = W(440)
        put("N", [poly((0, B), (0, T), (w, B), (w, T))])
        # O
        w = W(460)
        put("O", [arc(w / 2, M, w / 2, (T - B) / 2, 0, 360)])
        # P
        w = W(390); pm = B + (T - B) * .42; rr = (T - pm) / 2; rx = w * .5
        put("P", [poly((0, T), (0, B)), cat(poly((0, T), (w - rx, T)), arc(w - rx, T - rr, rx, rr, 90, -90), poly((w - rx, pm), (0, pm)))])
        # Q
        w = W(460)
        put("Q", [arc(w / 2, M, w / 2, (T - B) / 2, 0, 360), poly((w * .56, B + 70), (w * 1.02, B - 38))])
        # R
        w = W(400)
        put("R", [poly((0, T), (0, B)), cat(poly((0, T), (w - rx, T)), arc(w - rx, T - rr, rx, rr, 90, -90), poly((w - rx, pm), (0, pm))),
                  poly((w * .38, pm), (w, B))])
        # S
        w = W(390)
        put("S", [spline([(w * .94, T - 78), (w * .62, T), (w * .26, T - 6), (w * .04, T - (T - B) * .24), (w * .2, M + 22),
                          (w * .52, M - 8), (w * .86, M - 40), (w * .98, B + (T - B) * .24), (w * .76, B + 4), (w * .36, B - 2), (w * .04, B + 78)])])
        # T
        w = W(430)
        put("T", [poly((0, T), (w, T)), poly((w / 2, T), (w / 2, B))])
        # U
        w = W(430); r = w * .5
        put("U", [cat(poly((0, T), (0, B + r)), arc(w / 2, B + r, w / 2, r, 180, 360), poly((w, B + r), (w, T)))])
        # V
        w = W(470)
        put("V", [poly((0, T), (w / 2, B), (w, T))])
        # W
        w = W(650)
        put("W", [poly((0, T), (w * .25, B), (w * .5, T - (T - B) * .30), (w * .75, B), (w, T))])
        # X
        w = W(450)
        put("X", [poly((0, T), (w, B)), poly((w, T), (0, B))])
        # Y
        w = W(450)
        put("Y", [poly((0, T), (w / 2, M + 30)), poly((w, T), (w / 2, M + 30)), poly((w / 2, M + 30), (w / 2, B))])
        # Z
        w = W(400)
        put("Z", [poly((0, T), (w, T), (0, B), (w, B))])
        return S

    # ----------------------------------------------------------- lowercase
    def lower(self):
        g = self
        X, B, A, D, cy, ry, ws = g.X, g.B, g.A, g.D, g.cy, g.ry, g.ws
        S = {}
        def put(ch, strokes, dots=(), kind="lo", ax=None):
            xs = [x for s in strokes for x, y in s]
            if ax is None:
                ax = (min(xs) + max(xs)) / 2
            S[ch] = dict(s=strokes, dots=list(dots), ax=ax, kind=kind)
        W = lambda v: v * ws
        wo = W(330)
        oval = lambda x0=0, w_=None: arc(x0 + (w_ or wo) / 2, cy, (w_ or wo) / 2, ry, 0, 360)
        put("o", [oval()])
        put("a", [oval(), poly((wo, X), (wo, B))])
        put("b", [poly((0, A), (0, B)), oval()])
        put("d", [oval(), poly((wo, A), (wo, B))])
        put("c", [arc(wo / 2, cy, wo / 2, ry, 40, 320)])
        put("e", [cat(poly((0, cy), (wo, cy)), arc(wo / 2, cy, wo / 2, ry, 0, 322))])
        # f
        r = 120; sx = 90
        put("f", [cat(arc(sx + r, A - r, r, r, 25, 180), poly((sx, A - r), (sx, B))), poly((sx - 90, X), (sx + 130, X))])
        # g
        rr = 105; xg = wo
        put("g", [oval(), cat(poly((wo, X), (wo, D + rr)), arc(wo - rr, D + rr, rr, rr, 0, -165))])
        # h
        wn = W(320); rn = wn * .5
        arch = lambda x0=0, w_=None: cat(arc(x0 + (w_ or wn) / 2, X - (w_ or wn) / 2 * 1.05, (w_ or wn) / 2, (w_ or wn) / 2 * 1.05, 180, 0), poly((x0 + (w_ or wn), X - (w_ or wn) / 2 * 1.05), (x0 + (w_ or wn), B)))
        put("h", [poly((0, A), (0, B)), arch()])
        # i
        put("i", [poly((0, X), (0, B))], dots=[(0, X + 140)])
        # j
        put("j", [cat(poly((0, X), (0, D + rr)), arc(-rr, D + rr, rr, rr, 0, -165))], dots=[(0, X + 140)])
        # k
        wk = W(330); ya = cy - 5
        xa = wk * .4; yb_ = ya + (X - ya) * xa / wk
        put("k", [poly((0, A), (0, B)), poly((wk, X), (0, ya)), poly((xa, yb_), (wk, B))])
        # l
        put("l", [poly((0, A), (0, B))])
        # m
        wm = W(270)
        put("m", [poly((0, X), (0, B)), arch(0, wm), arch(wm, wm)] if False else [poly((0, X), (0, B)), arch(0, wm), cat(arc(wm * 1.5, X - wm / 2 * 1.05, wm / 2, wm / 2 * 1.05, 180, 0), poly((wm * 2, X - wm / 2 * 1.05), (wm * 2, B)))])
        # n
        put("n", [poly((0, X), (0, B)), arch()])
        # p
        put("p", [poly((0, X), (0, D)), oval()])
        # q
        put("q", [poly((wo, X), (wo, D)), oval()])
        # r
        wr = W(260)
        put("r", [poly((0, X), (0, B)), cat(poly((0, X - 130), (0, X - 130)), arc(wr / 2, X - wr / 2 * 1.05, wr / 2, wr / 2 * 1.05, 180, 40))])
        # s
        w = W(300); Hs = X - B
        put("s", [spline([(w * .92, X - 62), (w * .6, X), (w * .22, X - 8), (w * .05, B + Hs * .74), (w * .22, B + Hs * .55),
                          (w * .6, B + Hs * .42), (w * .96, B + Hs * .26), (w * .78, B + 4), (w * .38, B - 2), (w * .05, B + 62)])])
        # t
        w = W(260); r = 100; tt = 620 - g.p
        put("t", [cat(poly((0, tt), (0, B + r)), arc(r, B + r, r, r, 180, 270 + 60)), poly((-85, X), (w * .62, X))], ax=40)
        # u
        put("u", [cat(poly((0, X), (0, B + wn / 2)), arc(wn / 2, B + wn / 2, wn / 2, wn / 2, 180, 360)), poly((wn, X), (wn, B))])
        # v
        w = W(340)
        put("v", [poly((0, X), (w / 2, B), (w, X))])
        # w
        w = W(520)
        put("w", [poly((0, X), (w * .25, B), (w * .5, X - (X - B) * .30), (w * .75, B), (w, X))])
        # x
        w = W(340)
        put("x", [poly((0, X), (w, B)), poly((w, X), (0, B))])
        # y
        w = W(340)
        put("y", [poly((0, X), (w * .5, B + 20)), poly((w, X), (w * .12, D + 8))])
        # z
        w = W(300)
        put("z", [poly((0, X), (w, X), (0, B), (w, B))])
        return S

    # -------------------------------------------------------------- digits
    def digits(self):
        g = self
        T, B, M = g.T, g.B, g.M
        S = {}
        def put(ch, strokes, dots=()):
            xs = [x for s in strokes for x, y in s]
            S[ch] = dict(s=strokes, dots=list(dots), ax=(min(xs) + max(xs)) / 2, kind="x")
        w = 350 * g.ws
        put("0", [arc(w / 2, M, w / 2, (T - B) / 2, 0, 360)])
        put("1", [poly((-w * .30, T - 110), (w * .12, T), (w * .12, B))])
        put("2", [cat(spline([(w * .04, T - 90), (w * .3, T), (w * .72, T - 4), (w * .94, T - 100), (w * .75, M + 20), (w * .3, B + 100)], t0=(.4, 1), t1=(-1, -1)), poly((w * .3, B + 100), (0, B), (w, B)))])
        put("3", [spline([(w * .06, T - 70), (w * .35, T), (w * .72, T - 6), (w * .88, T - 105), (w * .7, M + 40), (w * .35, M + 6)], t1=(-1, -0.1)),
                  spline([(w * .35, M + 6), (w * .78, M - 24), (w * .98, B + 130), (w * .76, B + 8), (w * .35, B - 2), (w * .04, B + 70)], t0=(1, -0.1))])
        put("4", [poly((w * .72, B), (w * .72, T), (0, B + (T - B) * .30), (w, B + (T - B) * .30))])
        put("5", [poly((w * .92, T), (w * .1, T), (w * .02, M + 20)), cat(spline([(w * .02, M + 20), (w * .4, M + 55), (w * .85, M + 4), (w * .98, B + 150), (w * .72, B + 6), (w * .34, B - 2), (0, B + 66)], t0=(1, 0.3))) ])
        put("6", [cat(spline([(w * .9, T - 40), (w * .5, T), (w * .12, M + 80), (w * .02, B + 150)], t1=(0, -1)),), arc(w / 2, B + (M - B) * .86, w / 2, (M - B) * .86 if False else (M - B) * .62 + 30, 0, 360)] if False else
            [spline([(w * .9, T - 40), (w * .52, T), (w * .14, M + 90), (w * .02, B + 170)], t1=(0, -1)), arc(w / 2, B + 190, w / 2, 190, 0, 360)])
        put("7", [poly((0, T), (w, T), (w * .3, B))])
        put("8", [arc(w / 2, B + (T - B) * .745, w * .41, (T - B) * .255, 0, 360), arc(w / 2, B + (T - B) * .27, w * .5, (T - B) * .27, 0, 360)])
        put("9", [spline([(w * .1, B + 40), (w * .48, B), (w * .86, B + (T - B) * .30), (w * .98, B + (T - B) * .6)], t0=(1, -.4), t0_=None) if False else
                  spline([(w * .1, B + 40), (w * .48, B), (w * .86, B + 120), (w * .98, T - 190)], t1=(0, 1)), arc(w / 2, T - 190, w / 2, 190, 0, 360)])
        return S

    # --------------------------------------------------------- punctuation
    def punct(self):
        g = self
        T, B, M, X, D, p = g.T, g.B, g.M, g.X, g.D, g.p
        dr = g.dot_r
        S = {}
        def put(ch, strokes=(), dots=(), ax=None):
            pts = [q for s in strokes for q in s] + [(x, y) for x, y in dots]
            xs = [q[0] for q in pts]
            S[ch] = dict(s=list(strokes), dots=list(dots), ax=ax if ax is not None else (min(xs) + max(xs)) / 2, kind="x")
        yd = dr  # centre of a baseline dot so it sits on the baseline
        put(".", dots=[(0, yd)])
        put(",", [spline([(0, yd), (-6, yd - 60), (-38, yd - 130)], t0=(0, -1))], dots=[(0, yd)])
        put(":", dots=[(0, yd), (0, X - dr + 12)])
        put(";", [spline([(0, yd), (-6, yd - 60), (-38, yd - 130)], t0=(0, -1))], dots=[(0, yd), (0, X - dr + 12)])
        put("!", [poly((0, T), (0, 220 + dr))], dots=[(0, yd)])
        put("¡", [poly((0, X + 40 - 0), (0, B + 0))] if False else [poly((0, T - 700 + 480 + 0 + 0 - 0), (0, B))] if False else [poly((0, 480 - 0), (0, B))], dots=[(0, T - dr + 0 - 0)] if False else [(0, 700 - dr)])
        qs = [spline([(-w_, T - 125), (-w_ + 8, T - 25), (w_ + 0, T)][::1]) for w_ in ()]
        put("?", [spline([(-130, T - 150), (-125, T - 45), (0, T), (125, T - 50), (118, T - 150), (45, M - 10), (0, 190 + dr)], t1=(0, -1))], dots=[(0, yd)])
        # inverted ? : rotate 180 about (0,(T+B)/2)
        q = S["?"]
        yy = T + B
        put("¿", [[(-x, yy - y) for x, y in s] for s in q["s"]], dots=[(-x, yy - y) for x, y in q["dots"]])
        # quotes
        qh = 150
        put("'", [poly((0, T), (-6, T - qh))])
        put('"', [poly((-62, T), (-68, T - qh)), poly((62, T), (56, T - qh))])
        def comma_up(x, y):  # raised comma shape (6/9 style)
            return [spline([(x, y), (x + 6, y - 55), (x + 40, y - 120)], t0=(0, -1))], (x, y)
        # right quote: dot on top with tail down-left ; left quote: rotated
        def rq(x):
            return spline([(x, T - dr), (x - 4, T - dr - 55), (x - 40, T - dr - 120)], t0=(0, -1))
        def lq(x):
            return spline([(x, T - dr - 120), (x + 4, T - dr - 55), (x - 0, T - dr)][::-1][::-1], t0=(0, 1)) if False else spline([(x + 38, T - dr), (x + 4, T - dr - 60), (x, T - dr - 120)][::-1], t0=(0.2, 1)) if False else None
        put("’", [rq(0)], dots=[(0, T - dr)])
        # opening quote: tail goes up-right
        put("‘", [spline([(0, T - 120 + 0), (6, T - 60), (40, T - dr)][::1], t0=(0, 1))], dots=[(0, T - 120)] )
        put("”", [rq(-62), rq(62)], dots=[(-62, T - dr), (62, T - dr)])
        put("“", [spline([(-62, T - 120), (-56, T - 60), (-22, T - dr)], t0=(0, 1)), spline([(62, T - 120), (68, T - 60), (102, T - dr)], t0=(0, 1))], dots=[(-62, T - 120), (62, T - 120)])
        # dashes
        yh = M - 20
        put("-", [poly((0, yh), (210, yh))])
        put("–", [poly((0, yh), (400, yh))])
        put("—", [poly((0, yh), (780, yh))])
        # ampersand
        w = 470; H = T - B
        put("&", [spline([(w * .98, B), (w * .62, B + H * .30), (w * .30, B + H * .70), (w * .34, T - 4), (w * .56, T - 16), (w * .64, B + H * .80), (w * .30, B + H * .52),
                          (w * .06, B + H * .26), (w * .24, B + 2), (w * .56, B + 6), (w * .80, B + H * .32), (w * .92, B + H * .42)], t0=(-1, 1), t1=(0.4, 1))] )
        # parentheses / brackets / braces
        ra = 160; cyp = (T + D) / 2; ryp = (T - D) / 2 + 20
        put("(", [arc(ra + 0, cyp, ra, ryp, 118, 242)])
        put(")", [arc(-ra + 0, cyp, ra, ryp, -62, 62)])
        bw = 130
        put("[", [poly((bw, T + 20), (0, T + 20), (0, D - 20 + 0), (bw, D - 20))])
        put("]", [poly((-bw, T + 20), (0, T + 20), (0, D - 20), (-bw, D - 20))])
        put("{", [spline([(100, T + 20), (20, T - 20), (20, cyp + 100)], t0=(-1, 0), t1=(0, -1)), spline([(20, cyp + 100), (20, cyp + 30), (-50, cyp)], t1=(-1, 0)), spline([(-50, cyp), (20, cyp - 30), (20, cyp - 100)], t0=(1, 0)), spline([(20, cyp - 100), (20, D + 20), (100, D - 20)], t1=(1, 0), t0=(0, -1))])
        put("}", [[(-x, y) for x, y in s] for s in S["{"]["s"]])
        put("/", [poly((0, D + 20), (340, T + 10))])
        put("\\", [poly((0, T + 10), (340, D + 20))])
        put("|", [poly((0, T + 10), (0, D - 0))])
        # math
        ym = M + 6; ar = 150
        put("+", [poly((-ar, ym), (ar, ym)), poly((0, ym - ar), (0, ym + ar))])
        put("=", [poly((-ar, ym + 70), (ar, ym + 70)), poly((-ar, ym - 70), (ar, ym - 70))])
        put("<", [poly((ar, ym + ar), (-ar, ym), (ar, ym - ar))])
        put(">", [poly((-ar, ym + ar), (ar, ym), (-ar, ym - ar))])
        # * asterisk
        ca = T - 130; rr_ = 112
        put("*", [poly((rr_ * math.cos(math.radians(a)) * -1, ca - rr_ * math.sin(math.radians(a))), (rr_ * math.cos(math.radians(a)), ca + rr_ * math.sin(math.radians(a)))) for a in (90, 30, -30)])
        put("_", [poly((0, D + 70), (520, D + 70))])
        put("…", dots=[(0, yd), (150, yd), (300, yd)])
        put("~", [spline([(0, M - 20), (65, M + 50), (160, M), (255, M - 50), (320, M + 20)], t0=(1, 1), t1=(1, 1))])
        put("^", [poly((-130, T - 210), (0, T - 40), (130, T - 210))])
        put("`", [poly((-60, T), (50, T - 110))])
        # # hash
        hw = 380
        put("#", [poly((hw * .28, T - 10), (hw * .14, B + 10)), poly((hw * .78, T - 10), (hw * .64, B + 10)), poly((0, B + (T - B) * .35), (hw, B + (T - B) * .35)), poly((hw * .06, B + (T - B) * .68), (hw * .92, B + (T - B) * .68))])
        # % percent
        pw = 560; rr2 = 85
        put("%", [arc(rr2 + 10, T - rr2 - 8, rr2, rr2 * 1.1, 0, 360), arc(pw - rr2 - 10, B + rr2 + 8, rr2, rr2 * 1.1, 0, 360), poly((pw * .9, T), (pw * .1, B))])
        # $ dollar
        sw = 330; Hs = T - B - 60; y0 = B + 30
        sp = spline([(sw * .92, y0 + Hs - 60), (sw * .58, y0 + Hs), (sw * .2, y0 + Hs - 6), (sw * .03, y0 + Hs * .74), (sw * .22, y0 + Hs * .56),
                     (sw * .6, y0 + Hs * .45), (sw * .98, y0 + Hs * .27), (sw * .76, y0 + 5), (sw * .38, y0), (sw * .03, y0 + 62)])
        put("$", [sp, poly((sw / 2, T + 20), (sw / 2, B - 22))])
        # @ at
        aw = 600; ar2 = 110
        put("@", [arc(aw / 2, M, aw / 2, (T - D * 0 - B + 0) / 2 - 10 + 0, 20, 335) if False else arc(aw / 2, M - 5, aw / 2, (T - B) / 2 - 10, 5, 330),
                  arc(aw * .5, M - 10, 100, 100 * 1.05, 0, 360), poly((aw * .5 + 100, M + 70), (aw * .5 + 100, M - 100), (aw * .5 + 120, M - 105)) if False else spline([(aw * .5 + 100, M + 80), (aw * .5 + 100, M - 90), (aw * .5 + 190, M - 70), (aw * .5 + 212, M + 20)], t0=(0, -1))])
        return S


# --------------------------------------------------------------- accents
def accent_marks(kind, cx, y0, s=1.0):
    """Return (strokes, dots) for an accent whose lowest centre-line is y0."""
    if kind == "acute":
        return [poly((cx - 38 * s, y0), (cx + 52 * s, y0 + 95 * s))], []
    if kind == "grave":
        return [poly((cx + 38 * s, y0), (cx - 52 * s, y0 + 95 * s))], []
    if kind == "circ":
        return [poly((cx - 66 * s, y0), (cx, y0 + 82 * s), (cx + 66 * s, y0))], []
    if kind == "tilde":
        return [spline([(cx - 74 * s, y0 + 10 * s), (cx - 34 * s, y0 + 58 * s), (cx + 4 * s, y0 + 36 * s), (cx + 40 * s, y0 + 14 * s), (cx + 76 * s, y0 + 62 * s)], t0=(1, 1), t1=(1, 1))], []
    if kind == "dia":
        return [], [(cx - 62 * s, y0 + 36 * s), (cx + 62 * s, y0 + 36 * s)]
    if kind == "ring":
        return [arc(cx, y0 + 42 * s * RING_S, 42 * s * RING_S, 42 * s * RING_S, 0, 360)], []
    if kind == "cedilla":
        return [spline([(cx, y0 + 40), (cx + 2, y0 - 6), (cx + 38, y0 - 28), (cx + 34, y0 - 80), (cx - 20, y0 - 96)], t0=(0, -1))], []
    raise KeyError(kind)

ACC = {
    "À": ("A", "grave"), "Á": ("A", "acute"), "Â": ("A", "circ"), "Ã": ("A", "tilde"), "Ä": ("A", "dia"), "Å": ("A", "ring"),
    "Ç": ("C", "cedilla"), "È": ("E", "grave"), "É": ("E", "acute"), "Ê": ("E", "circ"), "Ë": ("E", "dia"),
    "Ì": ("I", "grave"), "Í": ("I", "acute"), "Î": ("I", "circ"), "Ï": ("I", "dia"), "Ñ": ("N", "tilde"),
    "Ò": ("O", "grave"), "Ó": ("O", "acute"), "Ô": ("O", "circ"), "Õ": ("O", "tilde"), "Ö": ("O", "dia"),
    "Ù": ("U", "grave"), "Ú": ("U", "acute"), "Û": ("U", "circ"), "Ü": ("U", "dia"), "Ý": ("Y", "acute"),
    "à": ("a", "grave"), "á": ("a", "acute"), "â": ("a", "circ"), "ã": ("a", "tilde"), "ä": ("a", "dia"), "å": ("a", "ring"),
    "ç": ("c", "cedilla"), "è": ("e", "grave"), "é": ("e", "acute"), "ê": ("e", "circ"), "ë": ("e", "dia"),
    "ì": ("i", "grave"), "í": ("i", "acute"), "î": ("i", "circ"), "ï": ("i", "dia"), "ñ": ("n", "tilde"),
    "ò": ("o", "grave"), "ó": ("o", "acute"), "ô": ("o", "circ"), "õ": ("o", "tilde"), "ö": ("o", "dia"),
    "ù": ("u", "grave"), "ú": ("u", "acute"), "û": ("u", "circ"), "ü": ("u", "dia"), "ý": ("y", "acute"), "ÿ": ("y", "dia"),
}

def compose_accents(base, p, acc_scale=0.8, cap_gap=36, lo_gap=40, top_cap=CAP, top_lo=XH, i_top=None):
    """Add accented glyph specs to the dict `base`.  p = pen half thickness (outer extents)."""
    pa = p * acc_scale
    for ch, (b, kind) in ACC.items():
        src = base[b]
        strokes = [list(s) for s in src["s"]]
        dots = [] if b in "ij" else list(src["dots"])
        cx = src["ax"]
        if kind == "cedilla":
            y0 = p + 8
            ms, md = accent_marks(kind, cx + (20 if b == "C" else 10), y0, 0.9)
            ms = [mv(s, 0, 0) for s in ms]
            strokes += ms
        else:
            top = top_cap if ch.isupper() else top_lo
            gap = cap_gap if ch.isupper() else lo_gap
            y0 = top + gap + pa
            if b == "i":
                y0 = top + gap + pa
            ms, md = accent_marks(kind, cx + (10 if kind == "acute" else -10 if kind == "grave" else 0), y0, 1.0)
            strokes += ms
            dots += md
        base[ch] = dict(s=strokes, dots=dots, ax=cx, kind=src["kind"], acc=True, nb=len(src["s"]), nbd=len(dots) - len(md) if kind != 'cedilla' else len(dots))
    return base

def mv(s, dx, dy):
    return [(x + dx, y + dy) for x, y in s]

def build_all(g, compose=True, acc_scale=0.8, lo_gap=40, cap_gap=36):
    S = {}
    S.update(g.caps())
    S.update(g.lower())
    S.update(g.digits())
    S.update(g.punct())
    # slashed O / o, ae, AE, sharp s
    T, B, M, X, A, D, p = g.T, g.B, g.M, g.X, g.A, g.D, g.p
    ws = g.ws
    o = S["O"]
    wO = 460 * ws
    S["Ø"] = dict(s=o["s"] + [poly((wO * .95, T + 14), (wO * .05, B - 14))], dots=[], ax=o["ax"], kind="up")
    lo = S["o"]
    wo = 330 * ws
    S["ø"] = dict(s=lo["s"] + [poly((wo * .98, X + 6), (wo * .02, B - 6))], dots=[], ax=lo["ax"], kind="lo")
    # AE
    sx = 330 * ws; w2 = 330 * ws; yb = B + (T - B) * .32
    S["Æ"] = dict(s=[poly((0, B), (sx, T), (sx, B)), poly((sx * .26, yb), (sx, yb)), poly((sx, T), (sx + w2, T)), poly((sx, M), (sx + w2 * .84, M)), poly((sx, B), (sx + w2, B))],
                  dots=[], ax=sx, kind="up")
    # ae
    a = S["a"]; e = S["e"]
    wa = 330 * ws
    es = [[(x + wa, y) for x, y in s] for s in e["s"]]
    S["æ"] = dict(s=[a["s"][0], a["s"][1]] + es, dots=[], ax=wa, kind="lo")
    # sharp s
    r1 = 120; r2 = 135; Hh = A
    top = A - r1
    ws_ = ws
    S["ß"] = dict(s=[cat(poly((0, B), (0, A - r1)), arc(r1 + 0, A - r1, r1, r1, 180, -90)),
                     cat(arc(r1, A - 2 * r1 - r2 + 0.0, r2 * 1.05, r2, 90, -150))], dots=[], ax=r1, kind="lo")
    if compose:
        compose_accents(S, g.p, acc_scale, cap_gap=cap_gap, lo_gap=lo_gap)
    return S
