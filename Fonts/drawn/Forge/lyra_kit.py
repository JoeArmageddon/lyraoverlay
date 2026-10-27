"""lyra_kit: shared glyph-construction + font-assembly toolkit for the Lyra drawn fonts.

Glyphs are described as monoline *skeletons* (polylines with fillet radii).  A style
object turns skeleton items into outlines (stroking with skia-pathops), post-processes
them (rounding, shear, slit, serration ...), and the kit then spaces, kerns and
compiles a TrueType font with fontTools.
"""
import math, random, unicodedata, datetime
import numpy as np
import pathops
from pathops import Path, PathOp, LineCap, LineJoin, FillType
from fontTools.agl import UV2AGL
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.basePen import BasePen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.ttLib import TTFont

# ----------------------------------------------------------------- character set
UPPER = [chr(c) for c in range(ord('A'), ord('Z') + 1)]
LOWER = [chr(c) for c in range(ord('a'), ord('z') + 1)]
DIGITS = list("0123456789")
PUNCT = list(".,!?'\"‘’“”-–—:;&()/\\#@%+=$*…_~^<>[]{}|`¡¿")
ACC_UP = list("ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÑÒÓÔÕÖØÙÚÛÜÝ")
ACC_LO = list("àáâãäåæçèéêëìíîïñòóôõöøùúûüýÿß")
REQUIRED = UPPER + LOWER + DIGITS + [' '] + PUNCT + ACC_UP + ACC_LO

# accented glyph -> (base letter, mark)
ACCENTS = {}
for _s, _m in [("ÀÈÌÒÙ", "grave"), ("ÁÉÍÓÚÝ", "acute"), ("ÂÊÎÔÛ", "circ"), ("ÃÑÕ", "tilde"),
               ("ÄËÏÖÜ", "diaer")]:
    for _ch in _s:
        ACCENTS[_ch] = (unicodedata.normalize('NFD', _ch)[0], _m)
for _s, _m in [("àèìòù", "grave"), ("áéíóúý", "acute"), ("âêîôû", "circ"), ("ãñõ", "tilde"),
               ("äëïöüÿ", "diaer")]:
    for _ch in _s:
        ACCENTS[_ch] = (unicodedata.normalize('NFD', _ch)[0], _m)
ACCENTS['Å'] = ('A', 'ring'); ACCENTS['å'] = ('a', 'ring')
ACCENTS['Ç'] = ('C', 'cedil'); ACCENTS['ç'] = ('c', 'cedil')


def glyph_name(ch):
    if ch == ' ':
        return 'space'
    u = ord(ch)
    n = UV2AGL.get(u)
    return n if n else 'uni%04X' % u


# ----------------------------------------------------------------- geometry helpers
def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def unit(a, b):
    d = dist(a, b)
    return ((b[0] - a[0]) / d, (b[1] - a[1]) / d) if d > 1e-9 else (1.0, 0.0)


def _resolve_radii(P, R, closed, st):
    """Return tangent-cut distance per vertex."""
    n = len(P)
    ends = set() if closed else {0, n - 1}
    req = [0.0] * n
    for i in range(n):
        if i in ends:
            continue
        r = R[i]
        pa, pb = P[i - 1], P[(i + 1) % n]
        la, lb = dist(P[i], pa), dist(P[i], pb)
        ia, ib = (i - 1) % n, (i + 1) % n
        ea = la if ia in ends else la / 2.0
        eb = lb if ib in ends else lb / 2.0
        if r is None:
            r = st.nr
        if r == 'm':
            r = min(st.mcap, ea, eb)
        elif isinstance(r, tuple):          # ('f', frac) fraction of max
            r = min(r[1] * min(ea, eb) * 2, ea, eb, st.mcap)
        req[i] = max(0.0, min(float(r), la, lb))
    # resolve conflicts on shared edges
    for _ in range(2):
        m = n if closed else n - 1
        for i in range(m):
            j = (i + 1) % n
            L = dist(P[i], P[j])
            s = req[i] + req[j]
            if s > L and s > 0:
                f = L / s
                req[i] *= f
                req[j] *= f
    return req


def rounded_path(pts, closed, st):
    P = [(p[0], p[1]) for p in pts]
    R = [p[2] if len(p) > 2 else None for p in pts]
    n = len(P)
    d = _resolve_radii(P, R, closed, st)
    path = Path()
    first = True

    def corner(i):
        pv, nx = P[i - 1], P[(i + 1) % n]
        ua = unit(P[i], pv)
        ub = unit(P[i], nx)
        T1 = (P[i][0] + ua[0] * d[i], P[i][1] + ua[1] * d[i])
        T2 = (P[i][0] + ub[0] * d[i], P[i][1] + ub[1] * d[i])
        return T1, T2, ua, ub

    def emit_corner(i, T1, T2, ua, ub):
        if d[i] < 0.5:
            path.lineTo(*P[i])
            return
        path.lineTo(*T1)
        if st.mode == 'chamfer':
            path.lineTo(*T2)
        else:
            dot = max(-1, min(1, ua[0] * ub[0] + ua[1] * ub[1]))
            interior = math.acos(dot)                # angle between edges
            alpha = math.pi - interior               # deflection
            ratio = (4.0 / 3.0) * math.tan(alpha / 4.0) / max(math.tan(alpha / 2.0), 1e-6)
            k = min(0.95, ratio * st.kmul)
            c1 = (T1[0] + (P[i][0] - T1[0]) * k, T1[1] + (P[i][1] - T1[1]) * k)
            c2 = (T2[0] + (P[i][0] - T2[0]) * k, T2[1] + (P[i][1] - T2[1]) * k)
            path.cubicTo(c1[0], c1[1], c2[0], c2[1], T2[0], T2[1])

    if closed:
        T1, T2, ua, ub = corner(0)
        if d[0] < 0.5:
            path.moveTo(*P[0])
        else:
            path.moveTo(*T2)
        for i in range(1, n):
            T1, T2, ua, ub = corner(i)
            emit_corner(i, T1, T2, ua, ub)
        T1, T2, ua, ub = corner(0)
        if d[0] >= 0.5:
            emit_corner(0, T1, T2, ua, ub)
        path.close()
    else:
        path.moveTo(*P[0])
        for i in range(1, n - 1):
            T1, T2, ua, ub = corner(i)
            emit_corner(i, T1, T2, ua, ub)
        path.lineTo(*P[-1])
    return path


def circle_path(cx, cy, r, ry=None):
    ry = r if ry is None else ry
    k = 0.5522847498
    p = Path()
    p.moveTo(cx + r, cy)
    p.cubicTo(cx + r, cy + k * ry, cx + k * r, cy + ry, cx, cy + ry)
    p.cubicTo(cx - k * r, cy + ry, cx - r, cy + k * ry, cx - r, cy)
    p.cubicTo(cx - r, cy - k * ry, cx - k * r, cy - ry, cx, cy - ry)
    p.cubicTo(cx + k * r, cy - ry, cx + r, cy - k * ry, cx + r, cy)
    p.close()
    return p


def poly_path(pts):
    p = Path()
    p.moveTo(*pts[0])
    for q in pts[1:]:
        p.lineTo(*q)
    p.close()
    return p


def clean(p, clockwise=True):
    q = Path(p)
    q.fillType = FillType.WINDING
    q.simplify(fix_winding=True, clockwise=clockwise)
    return q


def union(a, b):
    if a is None:
        return clean(b)
    if b is None:
        return a
    a2 = Path(a); b2 = Path(b)
    a2.fillType = FillType.WINDING
    b2.fillType = FillType.WINDING
    r = pathops.op(a2, b2, PathOp.UNION, fix_winding=True, keep_starting_points=False)
    need = max(abs(a2.area), abs(b2.area))
    if abs(r.area) < need - 2:
        for dx, dy in ((0.37, 0.21), (-0.41, 0.33), (0.9, -0.7)):
            b3 = b2.transform(1, 0, 0, 1, dx, dy)
            r = pathops.op(a2, b3, PathOp.UNION, fix_winding=True, keep_starting_points=False)
            if abs(r.area) >= need - 2:
                break
    return r


def difference(a, b):
    a2 = Path(a); b2 = Path(b)
    a2.fillType = FillType.WINDING
    b2.fillType = FillType.WINDING
    return pathops.op(a2, b2, PathOp.DIFFERENCE, fix_winding=True)


def stroke_of(path, width, cap=LineCap.ROUND_CAP, join=LineJoin.ROUND_JOIN, miter=4):
    p = Path(path)
    p.stroke(width, cap, join, miter)
    p.convertConicsToQuads(0.05)
    return clean(p)


def erode(path, r):
    band = stroke_of(path, 2 * r, LineCap.BUTT_CAP, LineJoin.ROUND_JOIN)
    return difference(path, band)


def dilate(path, r):
    band = stroke_of(path, 2 * r, LineCap.BUTT_CAP, LineJoin.ROUND_JOIN)
    return union(path, band)


def round_convex(path, r):
    """Morphological opening: rounds convex (outer) corners by radius r, keeps concave sharp."""
    path = clean(path)
    e = clean(erode(path, r))
    return clean(dilate(e, r))


def xform(path, sx=1, skx=0, sy=1, tx=0, ty=0, sky=0):
    return path.transform(sx, sky, skx, sy, tx, ty)


class FlatPen(BasePen):
    def __init__(self, steps=10):
        super().__init__(None)
        self.polys = []
        self.cur = None
        self.steps = steps

    def _moveTo(self, p):
        self.cur = [p]

    def _lineTo(self, p):
        self.cur.append(p)

    def _curveToOne(self, p1, p2, p3):
        p0 = self.cur[-1]
        for i in range(1, self.steps + 1):
            t = i / self.steps
            mt = 1 - t
            self.cur.append((mt**3 * p0[0] + 3 * mt * mt * t * p1[0] + 3 * mt * t * t * p2[0] + t**3 * p3[0],
                             mt**3 * p0[1] + 3 * mt * mt * t * p1[1] + 3 * mt * t * t * p2[1] + t**3 * p3[1]))

    def _qCurveToOne(self, p1, p2):
        p0 = self.cur[-1]
        for i in range(1, self.steps + 1):
            t = i / self.steps
            mt = 1 - t
            self.cur.append((mt * mt * p0[0] + 2 * mt * t * p1[0] + t * t * p2[0],
                             mt * mt * p0[1] + 2 * mt * t * p1[1] + t * t * p2[1]))

    def _closePath(self):
        if self.cur:
            self.polys.append(np.array(self.cur, float))
        self.cur = None

    def _endPath(self):
        self._closePath()


def flatten(path, steps=10):
    pen = FlatPen(steps)
    path.draw(pen)
    return pen.polys


YS = np.arange(-250, 950, 10.0) + 0.5


def profile(polys):
    """Left/right ink extents per scanline (NaN where empty)."""
    if not polys:
        return np.full(len(YS), np.nan), np.full(len(YS), np.nan)
    x0 = []; y0 = []; x1 = []; y1 = []
    for pl in polys:
        a = pl
        b = np.roll(pl, -1, axis=0)
        x0.append(a[:, 0]); y0.append(a[:, 1]); x1.append(b[:, 0]); y1.append(b[:, 1])
    x0 = np.concatenate(x0)[:, None]; y0 = np.concatenate(y0)[:, None]
    x1 = np.concatenate(x1)[:, None]; y1 = np.concatenate(y1)[:, None]
    ys = YS[None, :]
    cond = ((y0 <= ys) & (ys < y1)) | ((y1 <= ys) & (ys < y0))
    dy = np.where(y1 == y0, 1, y1 - y0)
    x = x0 + (ys - y0) * (x1 - x0) / dy
    x = np.where(cond, x, np.nan)
    with np.errstate(all='ignore'):
        import warnings
        with warnings.catch_warnings():
            warnings.simplefilter('ignore')
            return np.nanmin(x, axis=0), np.nanmax(x, axis=0)


# ----------------------------------------------------------------- skeleton items
class Ctx:
    pass


def mk_ctx(st, W, H, w, y0=0.0, ov=0.0):
    c = Ctx()
    c.st = st; c.W = W; c.H = H; c.w = w; c.t = w / 2.0; c.y0 = y0
    c.L = c.t; c.R = W - c.t
    c.B = y0 + c.t - ov; c.T = y0 + H - c.t + ov
    c.M = (c.B + c.T) / 2.0
    c.cx = W / 2.0
    return c


def _y(c, f):
    return c.B + f * (c.T - c.B)


def _x(c, f):
    return c.L + f * (c.R - c.L)


Ctx.y = _y
Ctx.x = _x


def S(c, pts, closed=False, wf=1.0):
    return ('s', [tuple(p) for p in pts], closed, c.w * wf)


def Dt(c, x, y, r=None, wf=1.0):
    return ('d', x, y, (c.st.dotr * wf) if r is None else r)


def xf_items(items, fn):
    out = []
    for it in items:
        if it[0] == 's':
            pts = []
            for p in it[1]:
                q = fn(p[0], p[1])
                pts.append((q[0], q[1]) + tuple(p[2:]))
            out.append(('s', pts, it[2], it[3]))
        elif it[0] == 'd':
            q = fn(it[1], it[2])
            out.append(('d', q[0], q[1], it[3]))
        elif it[0] == 'p':
            out.append(('p', [fn(*p) for p in it[1]]))
    return out


def shift_items(items, dx, dy=0):
    return xf_items(items, lambda x, y: (x + dx, y + dy))


def rot180(items, cx, cy):
    return xf_items(items, lambda x, y: (2 * cx - x, 2 * cy - y))


def mirror_x(items, cx):
    return xf_items(items, lambda x, y: (2 * cx - x, y))


def items_bbox(items, st):
    xs = []; ys = []
    for it in items:
        if it[0] == 's':
            h = it[3] / 2.0
            for p in it[1]:
                xs += [p[0] - h, p[0] + h]; ys += [p[1] - h, p[1] + h]
        elif it[0] == 'd':
            r = it[3]
            xs += [it[1] - r, it[1] + r]; ys += [it[2] - r, it[2] + r]
        elif it[0] == 'p':
            for p in it[1]:
                xs.append(p[0]); ys.append(p[1])
    return min(xs), min(ys), max(xs), max(ys)


# ----------------------------------------------------------------- skeleton library
def rbox(c, L, B, R, T, r='m', wf=1.0):
    return S(c, [(L, B, r), (R, B, r), (R, T, r), (L, T, r)], True, wf)


def build_caps(st):
    """Return dict ch -> (basewidth, fn(c)->items) for capitals and digits (proportions for H=700)."""
    G = {}

    def A(c):
        yb = c.y(st.abar)
        xl = c.L + (c.cx - c.L) * (yb - c.B) / (c.T - c.B)
        xr = c.R - (c.cx - c.L) * (yb - c.B) / (c.T - c.B)
        return [S(c, [(c.L, c.B, 0), (c.cx, c.T), (c.R, c.B, 0)]), S(c, [(xl, yb, 0), (xr, yb, 0)])]
    G['A'] = (760, A)

    def B(c):
        mb = c.y(0.51); rt = c.R - 0.07 * c.W
        return [S(c, [(c.L, mb, 0), (c.L, c.T, 0), (rt, c.T, 'm'), (rt, mb, 'm')], True),
                S(c, [(c.L, c.B, 0), (c.L, mb, 0), (c.R, mb, 'm'), (c.R, c.B, 'm')], True)]
    G['B'] = (660, B)

    def C(c):
        return [S(c, [(c.R, c.y(1 - st.hook)), (c.R, c.T, 'm'), (c.L, c.T, 'm'), (c.L, c.B, 'm'),
                      (c.R, c.B, 'm'), (c.R, c.y(st.hook))])]
    G['C'] = (690, C)

    def D(c):
        return [S(c, [(c.L, c.B, 0), (c.L, c.T, 0), (c.R, c.T, 'm'), (c.R, c.B, 'm')], True)]
    G['D'] = (710, D)

    def E(c):
        return [S(c, [(c.R, c.T), (c.L, c.T, 0), (c.L, c.B, 0), (c.R, c.B)]),
                S(c, [(c.L, c.M, 0), (c.R - 0.08 * c.W, c.M)])]
    G['E'] = (570, E)

    def F(c):
        return [S(c, [(c.R, c.T), (c.L, c.T, 0), (c.L, c.B)]),
                S(c, [(c.L, c.M, 0), (c.R - 0.08 * c.W, c.M)])]
    G['F'] = (550, F)

    def Gg(c):
        return [S(c, [(c.R, c.y(1 - st.hook)), (c.R, c.T, 'm'), (c.L, c.T, 'm'), (c.L, c.B, 'm'),
                      (c.R, c.B, 'm'), (c.R, c.M, 0), (c.cx + 0.02 * c.W, c.M)])]
    G['G'] = (730, Gg)

    def H(c):
        return [S(c, [(c.L, c.B), (c.L, c.T)]), S(c, [(c.R, c.B), (c.R, c.T)]),
                S(c, [(c.L, c.M, 0), (c.R, c.M, 0)])]
    G['H'] = (700, H)

    def I(c):
        it = [S(c, [(c.cx, c.B), (c.cx, c.T)])]
        if st.iserif:
            hw = st.iserif * c.W / 2.0
            it += [S(c, [(c.cx - hw, c.T), (c.cx + hw, c.T)]), S(c, [(c.cx - hw, c.B), (c.cx + hw, c.B)])]
        return it
    G['I'] = (380 if st.iserif else 260, I)

    def J(c):
        return [S(c, [(c.R, c.T), (c.R, c.B, 'm'), (c.L, c.B, 'm'), (c.L, c.y(0.30))])]
    G['J'] = (480, J)

    def K(c):
        return [S(c, [(c.L, c.B), (c.L, c.T)]), S(c, [(c.R, c.T), (c.L, c.y(0.42), 0)]),
                S(c, [(c.x(0.28), c.y(0.52), 0), (c.R, c.B)])]
    G['K'] = (680, K)

    def Lc(c):
        return [S(c, [(c.L, c.T), (c.L, c.B, 0), (c.R, c.B)])]
    G['L'] = (540, Lc)

    def M(c):
        return [S(c, [(c.L, c.B), (c.L, c.T, 0), (c.cx, c.y(0.36), 0), (c.R, c.T, 0), (c.R, c.B)])]
    G['M'] = (900, M)

    def N(c):
        return [S(c, [(c.L, c.B), (c.L, c.T, 0), (c.R, c.B, 0), (c.R, c.T)])]
    G['N'] = (740, N)

    def O(c):
        return [rbox(c, c.L, c.B, c.R, c.T)]
    G['O'] = (770, O)

    def P(c):
        mp = c.y(0.44)
        return [S(c, [(c.L, c.B), (c.L, mp)]),
                S(c, [(c.L, mp, 0), (c.L, c.T, 0), (c.R, c.T, 'm'), (c.R, mp, 'm')], True)]
    G['P'] = (640, P)

    def Q(c):
        return [rbox(c, c.L, c.B, c.R, c.T),
                S(c, [(c.x(0.58), c.y(0.26)), (c.R + 0.35 * c.t, c.B - 0.55 * c.t)])]
    G['Q'] = (790, Q)

    def R(c):
        mp = c.y(0.46)
        return [S(c, [(c.L, c.B), (c.L, mp)]),
                S(c, [(c.L, mp, 0), (c.L, c.T, 0), (c.R, c.T, 'm'), (c.R, mp, 'm')], True),
                S(c, [(c.x(0.38), mp, 0), (c.R, c.B)])]
    G['R'] = (680, R)

    def S_(c):
        hk = st.hook * (c.T - c.B); mu = c.y(0.52)
        return [S(c, [(c.R, c.T - hk), (c.R, c.T, 'm'), (c.L, c.T, 'm'), (c.L, mu, 'm'), (c.R, mu, 'm'),
                      (c.R, c.B, 'm'), (c.L, c.B, 'm'), (c.L, c.B + hk)])]
    G['S'] = (640, S_)

    def T(c):
        return [S(c, [(c.L, c.T), (c.R, c.T)]), S(c, [(c.cx, c.T, 0), (c.cx, c.B)])]
    G['T'] = (650, T)

    def U(c):
        return [S(c, [(c.L, c.T), (c.L, c.B, 'm'), (c.R, c.B, 'm'), (c.R, c.T)])]
    G['U'] = (710, U)

    def V(c):
        return [S(c, [(c.L, c.T), (c.cx, c.B), (c.R, c.T)])]
    G['V'] = (760, V)

    def W(c):
        return [S(c, [(c.L, c.T), (c.x(0.25), c.B), (c.cx, c.y(0.62)), (c.x(0.75), c.B), (c.R, c.T)])]
    G['W'] = (1060, W)

    def X(c):
        return [S(c, [(c.L, c.T), (c.R, c.B)]), S(c, [(c.R, c.T), (c.L, c.B)])]
    G['X'] = (730, X)

    def Y(c):
        return [S(c, [(c.L, c.T), (c.cx, c.y(0.46)), (c.R, c.T)]), S(c, [(c.cx, c.y(0.46), 0), (c.cx, c.B)])]
    G['Y'] = (730, Y)

    def Z(c):
        return [S(c, [(c.L, c.T), (c.R, c.T), (c.L, c.B), (c.R, c.B)])]
    G['Z'] = (650, Z)

    # digits
    def d0(c):
        return [rbox(c, c.L, c.B, c.R, c.T)]
    G['0'] = (600, d0)

    def d1(c):
        x1 = c.x(0.62)
        return [S(c, [(c.L + 0.02 * c.W, c.y(0.74)), (x1, c.T), (x1, c.B)]),
                S(c, [(c.L, c.B), (c.R, c.B)])]
    G['1'] = (500, d1)

    def d2(c):
        hk = 0.22 * (c.T - c.B)
        return [S(c, [(c.L, c.T - hk), (c.L, c.T, 'm'), (c.R, c.T, 'm'), (c.R, c.y(0.62), 'm'),
                      (c.L, c.B, 0), (c.R, c.B)])]
    G['2'] = (610, d2)

    def d3(c):
        mu = c.y(0.52); rt = c.R - 0.04 * c.W
        return [S(c, [(c.L, c.T), (rt, c.T, 'm'), (rt, mu, 'm'), (c.x(0.34), mu)]),
                S(c, [(c.x(0.34), mu), (c.R, mu, 'm'), (c.R, c.B, 'm'), (c.L, c.B)])]
    G['3'] = (610, d3)

    def d4(c):
        x4 = c.x(0.70); yb = c.y(st.f4bar)
        return [S(c, [(x4, c.T), (c.L, yb, 0), (c.R, yb)]), S(c, [(x4, c.T, 0), (x4, c.B)])]
    G['4'] = (650, d4)

    def d5(c):
        mq = c.y(0.55)
        return [S(c, [(c.R, c.T), (c.L, c.T, 0), (c.L, mq, 0), (c.R - 0.02 * c.W, mq, 'm'),
                      (c.R - 0.02 * c.W, c.B, 'm'), (c.L, c.B)])]
    G['5'] = (610, d5)

    def d6(c):
        mh = c.y(0.56)
        return [S(c, [(c.R, c.T), (c.L, c.T, 'm'), (c.L, mh)]),
                rbox(c, c.L, c.B, c.R, mh)]
    G['6'] = (620, d6)

    def d7(c):
        return [S(c, [(c.L, c.T), (c.R, c.T), (c.x(0.28), c.B)])]
    G['7'] = (590, d7)

    def d8(c):
        mu = c.y(0.54)
        return [rbox(c, c.x(0.04), mu, c.x(0.96), c.T), rbox(c, c.L, c.B, c.R, mu)]
    G['8'] = (630, d8)

    def d9(c):
        mh = c.y(0.44)
        return rot180(d6(c), c.cx, c.M)
    G['9'] = (620, d9)
    return G


def build_lower(st):
    """Real lowercase (used by bubble)."""
    G = {}
    # each fn takes (c) with H = x-height; ascender / descender extents come from st

    def tall(c):   # c for ascender-height boxes
        return mk_ctx(st, c.W, st.ASC, c.w)

    def a(c):
        rb = c.R - 0.45 * c.w
        return [rbox(c, c.L, c.B, rb, c.T), S(c, [(c.R, c.T), (c.R, c.B)])]
    G['a'] = (560, a)

    def b(c):
        ct = tall(c)
        return [S(c, [(c.L, c.B), (c.L, ct.T)]), rbox(c, c.L, c.B, c.R, c.T)]
    G['b'] = (570, b)

    def cc(c):
        return [S(c, [(c.R, c.y(0.74)), (c.R, c.T, 'm'), (c.L, c.T, 'm'), (c.L, c.B, 'm'),
                      (c.R, c.B, 'm'), (c.R, c.y(0.26))])]
    G['c'] = (510, cc)

    def d(c):
        ct = tall(c)
        return [S(c, [(c.R, c.B), (c.R, ct.T)]), rbox(c, c.L, c.B, c.R, c.T)]
    G['d'] = (570, d)

    def e(c):
        m = c.y(0.40)
        return [S(c, [(c.L, m, 0), (c.R, m, 'm'), (c.R, c.T, 'm'), (c.L, c.T, 'm'), (c.L, c.B, 'm'), (c.R, c.B)])]
    G['e'] = (560, e)

    def f(c):
        ct = tall(c)
        xs = c.x(0.40)
        return [S(c, [(xs, c.B), (xs, ct.T, 'm'), (c.R + 0.1 * c.W, ct.T)]),
                S(c, [(c.L - 0.05 * c.W, c.T), (c.R, c.T)])]
    G['f'] = (420, f)

    def g(c):
        D = st.DESC + c.t
        return [rbox(c, c.L, c.B, c.R, c.T), S(c, [(c.R, c.T), (c.R, D + 0.0, 150), (c.L + 0.04 * c.W, D)])]
    G['g'] = (570, g)

    def h(c):
        ct = tall(c)
        return [S(c, [(c.L, c.B), (c.L, ct.T)]), S(c, [(c.L, c.y(0.56)), (c.L, c.T, 'm'), (c.R, c.T, 'm'), (c.R, c.B)])]
    G['h'] = (550, h)

    def i(c):
        return [S(c, [(c.cx, c.B), (c.cx, c.T)]), Dt(c, c.cx, st.IDOT)]
    G['i'] = (260, i)

    def j(c):
        D = st.DESC + c.t
        return [S(c, [(c.R, c.T), (c.R, D + 0, 120), (c.L, D)]), Dt(c, c.R, st.IDOT)]
    G['j'] = (330, j)

    def k(c):
        ct = tall(c)
        return [S(c, [(c.L, c.B), (c.L, ct.T)]), S(c, [(c.R, c.T), (c.L, c.y(0.40), 0)]),
                S(c, [(c.x(0.30), c.y(0.46), 0), (c.R, c.B)])]
    G['k'] = (530, k)

    def l(c):
        ct = tall(c)
        return [S(c, [(c.x(0.3), ct.T), (c.x(0.3), c.B, 'm'), (c.R, c.B)])]
    G['l'] = (360, l)

    def m(c):
        return [S(c, [(c.L, c.B), (c.L, c.T)]),
                S(c, [(c.L, c.y(0.56)), (c.L, c.T, 'm'), (c.cx, c.T, 'm'), (c.cx, c.B)]),
                S(c, [(c.cx, c.y(0.56)), (c.cx, c.T, 'm'), (c.R, c.T, 'm'), (c.R, c.B)])]
    G['m'] = (860, m)

    def n(c):
        return [S(c, [(c.L, c.B), (c.L, c.T)]), S(c, [(c.L, c.y(0.56)), (c.L, c.T, 'm'), (c.R, c.T, 'm'), (c.R, c.B)])]
    G['n'] = (550, n)

    def o(c):
        return [rbox(c, c.L, c.B, c.R, c.T)]
    G['o'] = (570, o)

    def p(c):
        D = st.DESC + c.t
        return [S(c, [(c.L, D), (c.L, c.T)]), rbox(c, c.L, c.B, c.R, c.T)]
    G['p'] = (570, p)

    def q(c):
        D = st.DESC + c.t
        return [S(c, [(c.R, D), (c.R, c.T)]), rbox(c, c.L, c.B, c.R, c.T)]
    G['q'] = (570, q)

    def r(c):
        return [S(c, [(c.L, c.B), (c.L, c.T)]), S(c, [(c.L, c.y(0.5)), (c.L, c.T, 'm'), (c.R, c.T)])]
    G['r'] = (400, r)

    def s(c):
        hk = 0.24 * (c.T - c.B); mu = c.y(0.52)
        return [S(c, [(c.R, c.T - hk), (c.R, c.T, 'm'), (c.L, c.T, 'm'), (c.L, mu, 'm'), (c.R, mu, 'm'),
                      (c.R, c.B, 'm'), (c.L, c.B, 'm'), (c.L, c.B + hk)])]
    G['s'] = (490, s)

    def t(c):
        xs = c.x(0.40)
        return [S(c, [(xs, st.TTOP - c.t), (xs, c.B, 'm'), (c.R + 0.08 * c.W, c.B)]),
                S(c, [(c.L - 0.06 * c.W, c.T), (c.R, c.T)])]
    G['t'] = (420, t)

    def u(c):
        return [S(c, [(c.L, c.T), (c.L, c.B, 120), (c.R, c.B, 120)]), S(c, [(c.R, c.T), (c.R, c.B)])]
    G['u'] = (550, u)

    def v(c):
        return [S(c, [(c.L, c.T), (c.cx, c.B), (c.R, c.T)])]
    G['v'] = (560, v)

    def w(c):
        return [S(c, [(c.L, c.T), (c.x(0.25), c.B), (c.cx, c.y(0.6)), (c.x(0.75), c.B), (c.R, c.T)])]
    G['w'] = (820, w)

    def x(c):
        return [S(c, [(c.L, c.T), (c.R, c.B)]), S(c, [(c.R, c.T), (c.L, c.B)])]
    G['x'] = (550, x)

    def y(c):
        D = st.DESC + c.t
        return [S(c, [(c.L, c.T), (c.cx + 0.05 * c.W, c.B + 0.0)]),
                S(c, [(c.R, c.T), (c.x(0.2), D)])]
    G['y'] = (560, y)

    def z(c):
        return [S(c, [(c.L, c.T), (c.R, c.T), (c.L, c.B), (c.R, c.B)])]
    G['z'] = (500, z)
    return G


# ----------------------------------------------------------------- punctuation + marks
def build_punct(st, caps, c_cap):
    """Return dict ch -> items (absolute coordinates, origin x=0)."""
    G = {}
    w = st.w
    t = w / 2.0
    dr = st.dotr
    H = st.CAP

    def cp(W, y0=0.0, H_=None, wf=1.0):
        return mk_ctx(st, W, H if H_ is None else H_, w * wf, y0)

    # dot-like basics
    cx = dr + 4
    G['.'] = [('d', cx, dr, dr)]
    tail = lambda x, y: S(cp(10), [(x + 0.35 * dr, y - 0.4 * dr), (x - 0.55 * dr, y - 1.9 * dr)], False, 0.75)
    G[','] = [('d', cx, dr, dr), tail(cx, dr)]
    # exclam
    c = cp(max(2 * dr, w) + 10)
    cx = c.W / 2
    ytop = H - t
    ystem = 2 * dr + st.pgap + t
    G['!'] = [S(c, [(cx, ytop), (cx, ystem)]), ('d', cx, dr, dr)]
    # question
    c = cp(max(560, 0.8 * H))
    cx = c.cx
    sb_ = 2 * dr + st.pgap + t
    mq = sb_ + (c.T - sb_) * 0.40
    G['?'] = [S(c, [(c.L, c.T - 0.2 * (c.T - sb_)), (c.L, c.T, 'm'), (c.R, c.T, 'm'), (c.R, mq + 0.0, 'm'), (cx, mq - 0.0, 'm'),
                    (cx, sb_)]), ('d', cx, dr, dr)]
    G['¡'] = rot180(G['!'], cx=(max(2 * dr, w) + 10) / 2, cy=H / 2)
    G['¿'] = rot180(G['?'], cx=cx, cy=H / 2)
    # quotes
    qh = 0.30 * H
    def qmark(x, top):
        return S(cp(10), [(x, top - t), (x, top - qh)], False, 1.0)
    q1 = qmark(t + 5, H)
    G["'"] = [q1] if st.straightq else [('d', dr + 4, H - dr, dr), S(cp(10), [(dr + 4, H - dr), (dr + 4, H - qh - 60)], False, 0.9)]
    gapq = dr * 2.5 if not st.straightq else w * 1.35
    G['"'] = [qmark(t + 5, H), qmark(t + 5 + gapq, H)] if st.straightq else \
        G["'"] + shift_items(G["'"], gapq)
    def comma_up(x, ytop):   # right single quote: dot with tail down-left
        r = dr * 0.85
        return [('d', x, ytop - r, r),
                S(cp(10), [(x + 0.3 * r, ytop - 1.4 * r), (x - 0.6 * r, ytop - 3.3 * r)], False, 0.75)]
    G['’'] = comma_up(dr * 0.9 + 6, H)
    G['‘'] = rot180(G['’'], dr * 0.9 + 6, H - dr * 1.6)
    step = dr * 2.6
    G['”'] = G['’'] + shift_items(G['’'], step)
    G['“'] = G['‘'] + shift_items(G['‘'], step)
    # dashes
    ymid = st.DASHY
    for ch, Wd in (('-', 330), ('–', 560), ('—', 860)):
        c = cp(Wd)
        G[ch] = [S(c, [(c.L, ymid), (c.R, ymid)])]
    # colon / semicolon
    cx = dr + 4
    ydots = st.COLONY
    G[':'] = [('d', cx, dr, dr), ('d', cx, ydots, dr)]
    G[';'] = [('d', cx, ydots, dr), ('d', cx, dr, dr), tail(cx, dr)]
    # ellipsis
    sp = 2 * dr + st.dsp
    G['…'] = [('d', dr + 4 + i * sp, dr, dr) for i in range(3)]
    # underscore
    c = cp(620)
    G['_'] = [S(c, [(c.L, -st.USC), (c.R, -st.USC)])]
    # slash / backslash
    c = cp(520, st.DESC, H - st.DESC + 100 - 100)
    c = mk_ctx(st, 520, 900, w, -150)
    G['/'] = [S(c, [(c.R, c.T), (c.L, c.B)])]
    G['\\'] = [S(c, [(c.L, c.T), (c.R, c.B)])]
    # bar
    c = mk_ctx(st, w + 10, 1000, w, -200)
    G['|'] = [S(c, [(c.cx, c.T), (c.cx, c.B)])]
    # parens
    c = mk_ctx(st, 360, 1000, w * 0.95, -200)
    G['('] = [S(c, [(c.R, c.T), (c.L, c.M, 'm'), (c.R, c.B)])]
    G[')'] = [S(c, [(c.L, c.T), (c.R, c.M, 'm'), (c.L, c.B)])]
    c = mk_ctx(st, 330, 1000, w * 0.95, -200)
    G['['] = [S(c, [(c.R, c.T), (c.L, c.T, 0), (c.L, c.B, 0), (c.R, c.B)])]
    G[']'] = [S(c, [(c.L, c.T), (c.R, c.T, 0), (c.R, c.B, 0), (c.L, c.B)])]
    c = mk_ctx(st, 380, 1000, w * 0.9, -200)
    mid = c.M
    br = 70
    G['{'] = [S(c, [(c.R, c.T), (c.cx, c.T, br), (c.cx, mid, br), (c.L, mid)]),
              S(c, [(c.R, c.B), (c.cx, c.B, br), (c.cx, mid, br), (c.L, mid)])]
    G['}'] = [S(c, [(c.L, c.T), (c.cx, c.T, br), (c.cx, mid, br), (c.R, mid)]),
              S(c, [(c.L, c.B), (c.cx, c.B, br), (c.cx, mid, br), (c.R, mid)])]
    # operators
    sy = H * 0.5 - 20
    c = mk_ctx(st, 480, 480, w, sy - 240 + 20)
    G['+'] = [S(c, [(c.L, c.M), (c.R, c.M)]), S(c, [(c.cx, c.B), (c.cx, c.T)])]
    c = mk_ctx(st, 470, 470, w * 0.9, 0)
    g2 = 0.5 * 135 + 60
    G['='] = [S(c, [(c.L, sy + g2 * 0.55), (c.R, sy + g2 * 0.55)]), S(c, [(c.L, sy - g2 * 0.55), (c.R, sy - g2 * 0.55)])]
    c = mk_ctx(st, 460, 520, w, sy - 260 + 20)
    G['<'] = [S(c, [(c.R, c.T), (c.L, c.M), (c.R, c.B)])]
    G['>'] = [S(c, [(c.L, c.T), (c.R, c.M), (c.L, c.B)])]
    c = mk_ctx(st, 560, 300, w * 0.85, H - 300 + 20)
    G['^'] = [S(c, [(c.L, c.B), (c.cx, c.T), (c.R, c.B)])]
    cg = mk_ctx(st, 300, 200, w * 0.85, H - 30)
    G['`'] = [S(cg, [(cg.L, cg.T), (cg.R, cg.B)])]
    # tilde
    c = mk_ctx(st, 620, 300, w * 0.85, H * 0.5 - 150 + 60)
    a_ = 55
    G['~'] = [S(c, [(c.L, c.M - a_), (c.x(0.33), c.M + a_, 'm'), (c.x(0.66), c.M - a_, 'm'), (c.R, c.M + a_)])]
    # asterisk
    c = mk_ctx(st, 460, 460, w * 0.8, H - 460 + 30)
    ang = [math.pi / 2, math.pi / 2 + math.pi / 3, math.pi / 2 + 2 * math.pi / 3]
    rad = (c.R - c.L) / 2
    G['*'] = [S(c, [(c.cx + rad * math.cos(a), c.M + rad * math.sin(a)),
                    (c.cx - rad * math.cos(a), c.M - rad * math.sin(a))]) for a in ang]
    # hash
    c = mk_ctx(st, 640, 640, w * 0.85, 30)
    sl = 0.16 * c.W
    G['#'] = [S(c, [(c.x(0.36) + sl / 2, c.T), (c.x(0.36) - sl / 2, c.B)]),
              S(c, [(c.x(0.78) + sl / 2, c.T), (c.x(0.78) - sl / 2, c.B)]),
              S(c, [(c.L, c.y(0.34)), (c.R, c.y(0.34))]), S(c, [(c.L, c.y(0.70)), (c.R, c.y(0.70))])]
    # percent
    c = mk_ctx(st, 900, 700, w * 0.85, 0)
    rw = 270; rh = 270
    G['%'] = [rbox(c, c.L, c.T - rh, c.L + rw, c.T, 'm'), rbox(c, c.R - rw, c.B, c.R, c.B + rh, 'm'),
              S(c, [(c.R - 0.12 * c.W, c.T), (c.L + 0.12 * c.W, c.B)])]
    # dollar
    sfn = caps['S'][1]
    cS = mk_ctx(st, 600, 680, w * 0.95, 10)
    G['$'] = sfn(cS) + [S(cS, [(cS.cx, 790 - t), (cS.cx, -90 + t)], False, 0.75)]
    # ampersand
    c = mk_ctx(st, 760, 700, w, 0)
    uw = 0.46 * c.W
    mu = c.y(0.50)
    ul = c.L + 0.04 * c.W
    G['&'] = [rbox(c, ul + 0.02 * c.W, mu, ul + uw, c.T, 'm'),
              S(c, [(ul + 0.55 * uw, mu), (c.L, c.y(0.30), 'm'), (c.x(0.20), c.B, 'm'), (c.x(0.50), c.B)]),
              S(c, [(c.x(0.05) + 0.1 * c.W + 0.1 * uw, c.y(0.62)), (c.R, c.B)])]
    # at sign
    c = mk_ctx(st, 900, 760, w * 0.8, -30)
    iw = 0.30 * c.W
    cxi = c.cx
    yi0 = c.M - 0.17 * (c.T - c.B)
    yi1 = c.M + 0.17 * (c.T - c.B)
    ix = c.cx - 0.22 * c.W
    G['@'] = [S(c, [(c.R, c.y(0.36)), (c.R, c.T, 'm'), (c.L, c.T, 'm'), (c.L, c.B, 'm'), (c.R - 0.15 * c.W, c.B, 'm')]),
              rbox(c, ix, yi0, ix + 0.3 * c.W, yi1, 'm', 0.9),
              S(c, [(ix + 0.3 * c.W, yi1), (ix + 0.3 * c.W, yi0 - 10), (c.R, yi0 - 10, 'm'), (c.R, c.y(0.36))], False, 0.9)]
    return G


def build_marks(st, kind, cx, ytop_base):
    """Accent mark items centred at cx sitting above ytop_base."""
    w = st.w * st.mark_wf
    t = w / 2.0
    gap = st.mark_gap
    y0 = ytop_base + gap + t
    c = mk_ctx(st, 10, 10, w)
    h = st.mark_h
    hw = st.mark_hw
    if kind == 'acute':
        return [('s', [(cx - hw * 0.7, y0, 0), (cx + hw * 0.8, y0 + h)], False, w)]
    if kind == 'grave':
        return [('s', [(cx + hw * 0.7, y0, 0), (cx - hw * 0.8, y0 + h)], False, w)]
    if kind == 'circ':
        return [('s', [(cx - hw, y0, 0), (cx, y0 + h), (cx + hw, y0, 0)], False, w)]
    if kind == 'tilde':
        a = h * 0.32
        return [('s', [(cx - hw * 1.1, y0 + h * 0.3), (cx - hw * 0.35, y0 + h * 0.3 + a * 2, 'm'),
                       (cx + hw * 0.35, y0 + h * 0.3, 'm'), (cx + hw * 1.1, y0 + h * 0.3 + a * 2)], False, w * 0.9)]
    if kind == 'diaer':
        r = st.mark_dotr
        return [('d', cx - hw * 0.85, y0 + r - t + 3, r), ('d', cx + hw * 0.85, y0 + r - t + 3, r)]
    if kind == 'ring':
        r = h * 0.5
        return [('s', [(cx - hw * 0.62, y0, 'm'), (cx + hw * 0.62, y0, 'm'), (cx + hw * 0.62, y0 + h, 'm'),
                       (cx - hw * 0.62, y0 + h, 'm')], True, w * 0.8)]
    raise KeyError(kind)


def cedilla(st, cx):
    w = st.w * st.mark_wf
    return [('s', [(cx, -st.w * 0.2 + 18, 0), (cx, -w * 0.5 - 20, 0), (cx - st.mark_hw * 0.5, -w * 0.9 - 52)], False, w * 0.95)]


# ----------------------------------------------------------------- rendering of items
def render_items(items, st, rng=None):
    res = None
    for it in items:
        if it[0] == 's':
            _, pts, closed, width = it
            cen = rounded_path(pts, closed, st)
            sp = stroke_of(cen, width, st.cap, st.join, st.miter)
            res = union(res, sp)
            if not closed and st.spike is not None:
                for k in (0, -1):
                    poly = st.spike(pts, k, width, rng)
                    if poly:
                        res = union(res, clean(poly_path(poly)))
        elif it[0] == 'd':
            _, x, y, r = it
            res = union(res, clean(st.dot_shape(x, y, r)))
        elif it[0] == 'p':
            res = union(res, clean(poly_path(it[1])))
    return res


# ----------------------------------------------------------------- glyph production
def make_glyphs(st):
    caps = build_caps(st)
    lower = build_lower(st) if st.real_lower else None
    ctxC = mk_ctx(st, 10, st.CAP, st.w)
    punct = build_punct(st, caps, ctxC)
    base_items = {}      # ch -> (items, topY, cx)

    def cap_items(ch, scale_h=None, wf=1.0):
        bw, fn = caps[ch]
        H = st.CAP if scale_h is None else scale_h
        W = bw * st.wscale * (1.0 if scale_h is None else st.scw)
        c = mk_ctx(st, W, H, st.w * wf, 0.0, st.ov if ch in 'COQSGU0368' or ch in 'CGOQS' else 0.0)
        return fn(c), H, c.cx, W

    for ch in UPPER + DIGITS:
        base_items[ch] = cap_items(ch)
    for ch in LOWER:
        if st.real_lower:
            bw, fn = lower[ch]
            W = bw * st.wscale_l
            c = mk_ctx(st, W, st.XH, st.wl, 0.0, st.ov if ch in 'oecasgbdpq' else 0.0)
            it = fn(c)
            base_items[ch] = (it, st.XH, c.cx, W)
        else:
            base_items[ch] = cap_items(ch.upper(), st.SC, st.scwf)
    # special letters
    # ß
    def esszet():
        if st.real_lower:
            c = mk_ctx(st, 600 * st.wscale_l, st.ASC, st.wl)
            xm = c.x(0.40); mx = c.y(0.60)
            rt = c.R - 0.06 * c.W
            it = [S(c, [(c.L, c.B), (c.L, c.T - 0.18 * (c.T - c.B), 'm'), (c.x(0.2), c.T, 0), (rt, c.T, 'm'), (rt, mx, 'm'), (xm, mx)]),
                  S(c, [(xm, mx), (c.R, mx, 'm'), (c.R, c.B, 'm'), (c.x(0.25), c.B)])]
            it[0] = S(c, [(c.L, c.B), (c.L, c.T - 0.22 * (c.T - c.B), 'm'), (c.L + 0.28 * c.W, c.T, 'm'), (rt, c.T, 'm'), (rt, mx, 'm'), (xm, mx)])
            return it, st.ASC, c.cx, c.W
        c = mk_ctx(st, 640 * st.wscale * st.scwf, st.SC, st.w)
        xm = c.x(0.42); mx = c.y(0.58); rt = c.R - 0.05 * c.W
        it = [S(c, [(c.L, c.B), (c.L, c.T, 'm'), (rt, c.T, 'm'), (rt, mx, 'm'), (xm, mx)]),
              S(c, [(xm, mx), (c.R, mx, 'm'), (c.R, c.B, 'm'), (c.x(0.3), c.B)])]
        return it, st.SC, c.cx, c.W
    base_items['ß'] = esszet()

    # Æ / æ / Ø / ø
    def AE(H, upper=True, wf=1.0, wscl=1.0):
        W = 1100 * st.wscale * wscl
        c = mk_ctx(st, W, H, st.w * wf)
        xm = c.x(0.50)
        yb = c.y(st.abar)
        xl = c.L + (xm - c.L) * (yb - c.B) / (c.T - c.B)
        it = [S(c, [(c.L, c.B, 0), (xm, c.T, 0)]), S(c, [(xl, yb, 0), (xm, yb, 0)]),
              S(c, [(c.R, c.T), (xm, c.T, 0), (xm, c.B, 0), (c.R, c.B)]),
              S(c, [(xm, c.M, 0), (c.R - 0.06 * c.W, c.M)])]
        return it, H, c.cx, W
    if st.real_lower or True:
        base_items['Æ'] = AE(st.CAP)
    if st.real_lower:
        c = mk_ctx(st, 900 * st.wscale_l, st.XH, st.wl)
        xm = c.x(0.5)
        ca = mk_ctx(st, 10, st.XH, st.wl)
        rb = xm
        m = c.y(0.44)
        it = [rbox(c, c.L, c.B, rb - 0.0, c.T), S(c, [(rb, c.T), (rb, c.B)]) if False else
              S(c, [(xm, m, 0), (c.R, m, 'm'), (c.R, c.T, 'm'), (xm, c.T, 'm')]),
              S(c, [(xm, c.T, 'm'), (xm, c.B, 'm'), (c.R, c.B)])]
        # ae: left half is a-style bowl+stem sharing the middle stem; right half is an e
        it = [rbox(c, c.L, c.B, xm - 0.0, c.T), S(c, [(xm, c.T), (xm, c.B)]),
              S(c, [(xm, m, 0), (c.R, m, 'm'), (c.R, c.T, 'm'), (xm, c.T, 'm')]),
              S(c, [(xm, c.B, 'm'), (c.R, c.B)])]
        base_items['æ'] = (it, st.XH, c.cx, c.W)
    else:
        base_items['æ'] = AE(st.SC, False, st.scwf and 1.0, st.scw * 1.0)
    # Ø ø
    def slashed(ch_base):
        it, H, cx, W = base_items[ch_base]
        c = mk_ctx(st, W, H, (st.w if ch_base.isupper() or not st.real_lower else st.wl))
        ex = c.t * 0.3
        sl = S(c, [(c.R + ex, c.T + c.t * 0.1), (c.L - ex, c.B - c.t * 0.1)], False, 0.9)
        return it + [sl], H, cx, W
    base_items['Ø'] = slashed('O')
    base_items['ø'] = slashed('o')

    out = {}   # ch -> (items, topY)
    for ch, (it, H, cx, W) in base_items.items():
        out[ch] = it
    # dotless i for accented
    if st.real_lower:
        c = mk_ctx(st, 260, st.XH, st.wl)
        di_items = [S(c, [(c.cx, c.B), (c.cx, c.T)])]
        base_items['ı'] = (di_items, st.XH, c.cx, c.W)
    for ch, (b, mk) in ACCENTS.items():
        bb = 'ı' if (b == 'i' and st.real_lower) else b
        it, H, cx, W = base_items[bb]
        top = H
        if b in 'ij':
            top = st.XH if st.real_lower else H
        if b.isupper():
            top = st.CAP if b not in 'ÆØ' else st.CAP
        if bb == 'i' and not st.real_lower:
            top = st.SC
        if mk == 'cedil':
            m = cedilla(st, cx)
        else:
            m = build_marks(st, mk, cx, top)
        out[ch] = it + m
    for ch, it in punct.items():
        out[ch] = it
    return out


# ----------------------------------------------------------------- font assembly
def finalize_path(path):
    return clean(path)


def path_to_glyph(path):
    pen = TTGlyphPen(None)
    cp = Cu2QuPen(pen, max_err=0.8, reverse_direction=False)
    path.draw(cp)
    return pen.glyph()


def check_clockwise(path):
    """sanity: total signed area of outer contours should be negative in y-up (clockwise)."""
    pen = FlatPen()
    path.draw(pen)
    tot = 0
    for pl in pen.polys:
        x = pl[:, 0]; y = pl[:, 1]
        tot += 0.5 * np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y)
    return tot
