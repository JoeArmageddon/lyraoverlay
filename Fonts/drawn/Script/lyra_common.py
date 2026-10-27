"""Shared toolkit for the Lyra drawn fonts (Script / Brush / Tag).

Pen-model outline construction (skia-pathops boolean union), roughening,
TrueType quadratic conversion, auto spacing / kerning, font assembly,
specimen rendering and verification.  Copyright (c) 2026 Lyra. SIL OFL 1.1.
"""
import math, random, unicodedata
import numpy as np
from pathops import Path
from PIL import Image, ImageDraw, ImageFont
from fontTools.agl import UV2AGL

# ----------------------------------------------------------------- charset
BASIC_PUNCT = ".,!?'\"‘’“”-–—:;&()/\\#@%+=$*…_~^<>[]{}|`¡¿"
ACCENT_UP = "ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÑÒÓÔÕÖØÙÚÛÜÝ"
ACCENT_LO = "àáâãäåæçèéêëìíîïñòóôõöøùúûüýÿß"
UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
LOWER = "abcdefghijklmnopqrstuvwxyz"
DIGITS = "0123456789"
ALL_CHARS = UPPER + LOWER + DIGITS + BASIC_PUNCT + ACCENT_UP + ACCENT_LO

def gname(ch):
    cp = ord(ch)
    if ch == " ":
        return "space"
    return UV2AGL.get(cp, "uni%04X" % cp)

# ------------------------------------------------------------ curve helpers
def _d(a, b):
    return math.hypot(b[0] - a[0], b[1] - a[1])

def line(a, b, step=7.0):
    n = max(1, int(math.ceil(_d(a, b) / step)))
    return [(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n) for i in range(n + 1)]

def poly(*pts, step=7.0):
    out = []
    for i in range(len(pts) - 1):
        seg = line(pts[i], pts[i + 1], step)
        out += seg if not out else seg[1:]
    return out

def arc(cx, cy, rx, ry, a0, a1, step=7.0, rot=0.0):
    """Elliptical arc, angles in degrees (ccw positive, y up)."""
    length = abs(math.radians(a1 - a0)) * (rx + ry) / 2
    n = max(3, int(math.ceil(length / step)))
    cr, sr = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    out = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        x, y = rx * math.cos(a), ry * math.sin(a)
        out.append((cx + x * cr - y * sr, cy + x * sr + y * cr))
    return out

def _unit(v):
    l = math.hypot(*v)
    return (v[0] / l, v[1] / l) if l > 1e-9 else (0.0, 0.0)

def spline(pts, t0=None, t1=None, step=6.0):
    """Smooth curve through pts (cubic Beziers, tangent = bisector). t0/t1 optional end tangent vectors."""
    n = len(pts)
    tans = []
    for i in range(n):
        if i == 0:
            t = _unit(t0) if t0 else _unit((pts[1][0] - pts[0][0], pts[1][1] - pts[0][1]))
        elif i == n - 1:
            t = _unit(t1) if t1 else _unit((pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]))
        else:
            a = _unit((pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]))
            b = _unit((pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]))
            t = _unit((a[0] + b[0], a[1] + b[1]))
            if t == (0.0, 0.0):
                t = a
        tans.append(t)
    out = []
    for i in range(n - 1):
        p0, p3 = pts[i], pts[i + 1]
        d = _d(p0, p3)
        p1 = (p0[0] + tans[i][0] * d / 3, p0[1] + tans[i][1] * d / 3)
        p2 = (p3[0] - tans[i + 1][0] * d / 3, p3[1] - tans[i + 1][1] * d / 3)
        m = max(3, int(math.ceil(d / step)))
        for k in range(m + 1):
            if i > 0 and k == 0:
                continue
            t = k / m
            u = 1 - t
            out.append((u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
                        u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1]))
    return out

def cat(*strokes):
    out = []
    for s in strokes:
        if out and _d(out[-1], s[0]) < 1e-6:
            out += s[1:]
        else:
            out += s
    return out

def mvall(strokes, dx=0, dy=0):
    return [[(x + dx, y + dy) for x, y in s] for s in strokes]

def shear(strokes, deg, about_y=0.0):
    t = math.tan(math.radians(deg))
    return [[(x + (y - about_y) * t, y) for x, y in s] for s in strokes]

def scale_pts(strokes, sx, sy=None, cx=0.0, cy=0.0):
    sy = sx if sy is None else sy
    return [[(cx + (x - cx) * sx, cy + (y - cy) * sy) for x, y in s] for s in strokes]

def resample(pts, step):
    out = [pts[0]]
    acc = 0.0
    for i in range(1, len(pts)):
        a, b = pts[i - 1], pts[i]
        seg = _d(a, b)
        if seg == 0:
            continue
        pos = step - acc
        while pos <= seg:
            t = pos / seg
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
            pos += step
        acc = seg - (pos - step)
    if _d(out[-1], pts[-1]) > 1e-6:
        out.append(pts[-1])
    return out

# --------------------------------------------------------------- pen sweep
def hull(points):
    pts = sorted(set((round(x, 3), round(y, 3)) for x, y in points))
    if len(pts) <= 2:
        return pts
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo = []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    up = []
    for p in reversed(pts):
        while len(up) >= 2 and cross(up[-2], up[-1], p) <= 0:
            up.pop()
        up.append(p)
    return lo[:-1] + up[:-1]

_CIRC = {}
def circle_poly(r, n=24):
    key = n
    if key not in _CIRC:
        _CIRC[key] = [(math.cos(2 * math.pi * i / n), math.sin(2 * math.pi * i / n)) for i in range(n)]
    return [(r * c, r * s) for c, s in _CIRC[key]]

def add_poly(path, pts):
    path.moveTo(*pts[0])
    for p in pts[1:]:
        path.lineTo(*p)
    path.close()

def sweep(centers, polys, path=None):
    """Union of convex hulls between consecutive pen polygons placed at centers.
    polys[i] is the pen polygon (relative coords) at centers[i]."""
    path = path if path is not None else Path()
    placed = [[(c[0] + x, c[1] + y) for x, y in p] for c, p in zip(centers, polys)]
    if len(placed) == 1:
        h = hull(placed[0])
        add_poly(path, h)
        return path
    for i in range(len(placed) - 1):
        h = hull(placed[i] + placed[i + 1])
        if len(h) >= 3:
            add_poly(path, h)
    return path

def finish(path):
    path.simplify(fix_winding=True)
    return path

def contours_of(path):
    res = []
    for c in path.contours:
        pts = []
        for verb, ps in c.segments:
            if verb in ("moveTo", "lineTo"):
                pts.append((ps[0][0], ps[0][1]))
            elif verb in ("qCurveTo", "curveTo"):
                # flatten (should not occur: inputs are polygons)
                pts.append((ps[-1][0], ps[-1][1]))
        if len(pts) >= 3:
            res.append(pts)
    return res

def path_from_contours(conts):
    p = Path()
    for c in conts:
        add_poly(p, c)
    return p

def area(c):
    a = 0.0
    n = len(c)
    for i in range(n):
        x0, y0 = c[i]
        x1, y1 = c[(i + 1) % n]
        a += x0 * y1 - x1 * y0
    return a / 2

def point_in(c, pt):
    x, y = pt
    inside = False
    n = len(c)
    j = n - 1
    for i in range(n):
        xi, yi = c[i]
        xj, yj = c[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi:
            inside = not inside
        j = i
    return inside

def orient(conts):
    """TrueType: outer clockwise (negative area), counters counter-clockwise."""
    out = []
    for i, c in enumerate(conts):
        probe = c[0]
        # use a point guaranteed on boundary -> test centroid-ish: use midpoint of first edge nudged
        depth = 0
        mx = (c[0][0] + c[1][0]) / 2
        my = (c[0][1] + c[1][1]) / 2
        # nudge inward/outward unknown, so test against other contours using vertex 0 offset
        for j, o in enumerate(conts):
            if j == i:
                continue
            if abs(area(o)) > abs(area(c)) and point_in(o, (mx, my)):
                depth += 1
        want_cw = depth % 2 == 0
        a = area(c)
        if (a > 0) == want_cw:
            c = c[::-1]
        out.append(c)
    return out

# ------------------------------------------------------------- roughening
def _noise_fn(rng, length, scale, closed=True):
    n = max(3, int(length / scale))
    vals = [rng.uniform(-1, 1) for _ in range(n)]
    def f(s):
        u = (s / length) * n
        i = int(math.floor(u)) % n
        t = u - math.floor(u)
        t = (1 - math.cos(t * math.pi)) / 2
        return vals[i] * (1 - t) + vals[(i + 1) % n] * t
    return f

def subdivide(c, step):
    out = []
    n = len(c)
    for i in range(n):
        a, b = c[i], c[(i + 1) % n]
        out.append(a)
        k = int(_d(a, b) // step)
        for j in range(1, k + 1):
            if j * step < _d(a, b) - step * 0.4:
                t = j * step / _d(a, b)
                out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out

def roughen(conts, seed, amp_big=4.0, amp_small=1.6, scale_big=60.0, scale_small=13.0, step=7.0, skip=None):
    rng = random.Random(seed)
    out = []
    for c in conts:
        c = subdivide(c, step)
        n = len(c)
        L = sum(_d(c[i], c[(i + 1) % n]) for i in range(n))
        nb = _noise_fn(rng, L, scale_big)
        ns = _noise_fn(rng, L, scale_small)
        new = []
        s = 0.0
        for i in range(n):
            p0, p1, p2 = c[i - 1], c[i], c[(i + 1) % n]
            tx, ty = p2[0] - p0[0], p2[1] - p0[1]
            l = math.hypot(tx, ty) or 1
            nx, ny = ty / l, -tx / l
            d = amp_big * nb(s) + amp_small * ns(s)
            new.append((p1[0] + nx * d, p1[1] + ny * d))
            s += _d(p1, p2)
        out.append(new)
    return out

# ---------------------------------------------------------- offsets / rings
def grow(path_or_conts, r, n=16):
    """Grow shape by radius r (union with circle sweep along boundary)."""
    conts = path_or_conts if isinstance(path_or_conts, list) else contours_of(path_or_conts)
    p = path_from_contours(conts)
    circ = circle_poly(r, n)
    for c in conts:
        pts = resample(c + [c[0]], max(3.0, r * 0.6))
        sweep(pts, [circ] * len(pts), p)
    finish(p)
    return p

def outline_ring(conts, t, n=16):
    """Outline of thickness t (centred on boundary) as a Path."""
    p = Path()
    circ = circle_poly(t / 2, n)
    for c in conts:
        pts = resample(c + [c[0]], max(3.0, t * 0.5))
        sweep(pts, [circ] * len(pts), p)
    finish(p)
    return p

def pathop(a, b, kind):
    from pathops import op, PathOp
    k = {"diff": PathOp.DIFFERENCE, "union": PathOp.UNION, "inter": PathOp.INTERSECTION}[kind]
    return op(a, b, k, fix_winding=True)

def translate_conts(conts, dx, dy):
    return [[(x + dx, y + dy) for x, y in c] for c in conts]

# ------------------------------------------------ cleanup + quadratic output
def clean_contour(c, tol=0.12):
    c = [(round(x, 2), round(y, 2)) for x, y in c]
    out = []
    for p in c:
        if not out or _d(out[-1], p) > 0.05:
            out.append(p)
    if len(out) > 1 and _d(out[0], out[-1]) < 0.05:
        out.pop()
    # drop collinear points (greedy, non-cascading)
    if len(out) > 3:
        kept = [out[0]]
        n = len(out)
        for i in range(1, n):
            a_, b_ = kept[-1], out[i]
            c_ = out[(i + 1) % n]
            cr = abs((b_[0] - a_[0]) * (c_[1] - a_[1]) - (b_[1] - a_[1]) * (c_[0] - a_[0]))
            base = _d(a_, c_) or 1
            dot = (b_[0] - a_[0]) * (c_[0] - b_[0]) + (b_[1] - a_[1]) * (c_[1] - b_[1])
            if cr / base < tol and dot > 0:
                continue
            kept.append(b_)
        if len(kept) >= 3:
            out = kept
    return out

def turn_deg(a, b, c):
    v1 = (b[0] - a[0], b[1] - a[1])
    v2 = (c[0] - b[0], c[1] - b[1])
    ang = math.degrees(math.atan2(v1[0] * v2[1] - v1[1] * v2[0], v1[0] * v2[0] + v1[1] * v2[1]))
    return ang

def to_quad_contour(c, corner_deg=38.0):
    """Polygon -> TrueType contour [(x,y,on)].  Smooth vertices become off-curve
    control points of a quadratic B-spline; sharp vertices stay on-curve.
    Long edges are split so that curve fidelity stays high."""
    n = len(c)
    pts = []
    for i in range(n):
        a, b, d = c[i - 1], c[i], c[(i + 1) % n]
        ang = abs(turn_deg(a, b, d))
        pts.append([b[0], b[1], ang > corner_deg])
    # an off-curve vertex whose neighbour edges are long straight runs is fine:
    # but an off-curve adjacent to a long edge bends it. Make vertices at the ends of
    # edges longer than 40 units on-curve to keep straight sides straight.
    for i in range(n):
        j = (i + 1) % n
        if _d(c[i], c[j]) > 36:
            pts[i][2] = True
            pts[j][2] = True
    return [(p[0], p[1], p[2]) for p in pts]

def draw_contour(pen, tc):
    n = len(tc)
    on_idx = [i for i, p in enumerate(tc) if p[2]]
    if not on_idx:
        pen.qCurveTo(*[(round(p[0]), round(p[1])) for p in tc], None)
        pen.closePath()
        return
    s = on_idx[0]
    seq = tc[s:] + tc[:s]
    pen.moveTo((round(seq[0][0]), round(seq[0][1])))
    offs = []
    for p in seq[1:] + [seq[0]]:
        q = (round(p[0]), round(p[1]))
        if p[2]:
            if offs:
                pen.qCurveTo(*offs, q)
            else:
                pen.lineTo(q)
            offs = []
        else:
            offs.append(q)
    pen.closePath()

# -------------------------------------------------------- spacing / kerning
RES = 4  # units per raster pixel

def raster_profile(conts, ylo=-220, yhi=900):
    """Return (xl, xr) arrays per row (units), nan when empty."""
    if not conts:
        return None
    xs = [p[0] for c in conts for p in c]
    ys = [p[1] for c in conts for p in c]
    x0 = math.floor(min(xs) / RES) * RES - RES
    w = int((max(xs) - x0) / RES) + 3
    rows = (yhi - ylo) // RES
    img = Image.new("L", (w, rows), 0)
    dr = ImageDraw.Draw(img)
    for c in sorted(conts, key=lambda c: -abs(area(c))):
        pts = [((x - x0) / RES, (yhi - y) / RES) for x, y in c]
        dr.polygon(pts, fill=255 if area(c) < 0 else 0)
    a = np.array(img) > 127
    xl = np.full(rows, np.nan)
    xr = np.full(rows, np.nan)
    for r in range(rows):
        nz = np.nonzero(a[r])[0]
        if len(nz):
            xl[r] = x0 + nz[0] * RES
            xr[r] = x0 + (nz[-1] + 1) * RES
    return xl, xr  # row r covers y = yhi - r*RES (top edge)

def auto_sidebearings(prof, ylo_band, yhi_band, S, k, depth=90, ylo=-220, yhi=900):
    xl, xr = prof
    rows = len(xl)
    r0 = int((yhi - yhi_band) / RES)
    r1 = int((yhi - ylo_band) / RES)
    sl = xl[r0:r1]
    sr = xr[r0:r1]
    ok = ~np.isnan(sl)
    if not ok.any():
        return S, S
    xmin = np.nanmin(xl)
    xmax = np.nanmax(xr)
    dl = np.where(ok, np.minimum(sl - xmin, depth), depth)
    dr_ = np.where(ok, np.minimum(xmax - sr, depth), depth)
    return S - k * dl.mean(), S - k * dr_.mean()

def pair_gap(profA, advA, profB, band, cap=170, ylo=-220, yhi=900):
    """Return (min_gap or None, mean_gap) between right of A and left of B."""
    xlA, xrA = profA
    xlB, xrB = profB
    r0 = int((yhi - band[1]) / RES)
    r1 = int((yhi - band[0]) / RES)
    n = min(len(xrA), len(xlB))
    r1 = min(r1, n)
    ra = advA - xrA[r0:r1]
    lb = xlB[r0:r1]
    both = ~np.isnan(ra) & ~np.isnan(lb)
    gap = np.where(both, ra + lb, cap)
    anyink = ~np.isnan(ra) | ~np.isnan(lb)
    if not anyink.any():
        return None, float(cap)
    g = np.minimum(np.where(anyink, gap, cap), cap)
    mn = float(np.min(ra[both] + lb[both])) if both.any() else None
    return mn, float(g[anyink].mean())

# ---------------------------------------------------------- font assembly
def build_font(path_out, family, ps_name, glyphs, adv, kern_pairs, cmapchars, meta):
    """glyphs: name -> list of TrueType contours [(x,y,on)], adv: name->advance."""
    from fontTools.fontBuilder import FontBuilder
    from fontTools.pens.ttGlyphPen import TTGlyphPen
    from fontTools.feaLib.builder import addOpenTypeFeaturesFromString

    order = [".notdef", "space"] + [gname(c) for c in cmapchars if c != " "]
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(order)
    cmap = {ord(c): gname(c) for c in cmapchars}
    fb.setupCharacterMap(cmap)
    glyf = {}
    hmtx = {}
    for name in order:
        pen = TTGlyphPen(None)
        for tc in glyphs.get(name, []):
            draw_contour(pen, tc)
        g = pen.glyph()
        glyf[name] = g
        if name in glyphs and glyphs[name]:
            xs = [round(p[0]) for tc in glyphs[name] for p in tc]
            lsb = min(xs)
        else:
            lsb = 0
        hmtx[name] = (int(round(adv[name])), lsb)
    fb.setupGlyf(glyf)
    fb.setupHorizontalMetrics(hmtx)
    fb.setupHorizontalHeader(ascent=800, descent=-200, lineGap=0)
    nm = {
        "familyName": family,
        "styleName": "Regular",
        "uniqueFontIdentifier": "%s;1.000;%s" % (ps_name, "LYRA"),
        "fullName": family + " Regular",
        "version": "Version 1.000",
        "psName": ps_name,
        "copyright": "Copyright 2026 The Lyra Project. Original design.",
        "manufacturer": "The Lyra Project",
        "designer": "Lyra",
        "description": meta.get("description", ""),
        "licenseDescription": "This Font Software is licensed under the SIL Open Font License, Version 1.1. This license is available with a FAQ at: https://openfontlicense.org",
        "licenseInfoURL": "https://openfontlicense.org",
    }
    fb.setupNameTable(nm)
    fb.setupOS2(version=4, sTypoAscender=800, sTypoDescender=-200, sTypoLineGap=0,
                usWinAscent=900, usWinDescent=250, sxHeight=500, sCapHeight=700,
                fsSelection=(1 << 6) | (1 << 7), usWeightClass=meta.get("weight", 400),
                achVendID="LYRA", fsType=0)
    fb.setupPost(isFixedPitch=0, underlinePosition=-100, underlineThickness=60)
    fb.font["OS/2"].fsSelection = (1 << 6) | (1 << 7)  # REGULAR + USE_TYPO_METRICS
    fb.font["head"].macStyle = 0
    if meta.get("fea"):
        addOpenTypeFeaturesFromString(fb.font, meta["fea"])
    fb.save(path_out)

# ---------------------------------------------------------------- specimen
def glyph_polys(font, gs, name, flat=8):
    from fontTools.pens.recordingPen import DecomposingRecordingPen
    pen = DecomposingRecordingPen(gs)
    gs[name].draw(pen)
    contours = []
    cur = []
    last = None
    def quad(p0, c, p1):
        n = 6
        return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p1[0],
                 (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p1[1]) for t in [i / n for i in range(1, n + 1)]]
    for op_, args in pen.value:
        if op_ == "moveTo":
            cur = [args[0]]
            last = args[0]
        elif op_ == "lineTo":
            cur.append(args[0])
            last = args[0]
        elif op_ == "qCurveTo":
            pts = list(args)
            if pts[-1] is None:
                pts = pts[:-1]
                # closed all-off contour: start at midpoint of last and first
                start = ((pts[-1][0] + pts[0][0]) / 2, (pts[-1][1] + pts[0][1]) / 2)
                cur = [start]
                last = start
                pts = pts + [pts[0]]
                pts_iter = pts
                for i in range(len(pts_iter) - 1):
                    c = pts_iter[i]
                    e = ((pts_iter[i][0] + pts_iter[i + 1][0]) / 2, (pts_iter[i][1] + pts_iter[i + 1][1]) / 2)
                    cur += quad(last, c, e)
                    last = e
            else:
                offs, endp = pts[:-1], pts[-1]
                for i, c in enumerate(offs):
                    e = endp if i == len(offs) - 1 else ((c[0] + offs[i + 1][0]) / 2, (c[1] + offs[i + 1][1]) / 2)
                    cur += quad(last, c, e)
                    last = e
        elif op_ in ("closePath", "endPath"):
            if cur:
                contours.append(cur)
            cur = []
    return contours

def render_text(font, gs, cmap, hmtx, kern, text, px, color, bg_img, x, y, ss=3):
    """Draw text onto bg_img (RGB) at baseline y using real outlines. Returns end x."""
    scale = px / 1000.0
    # collect glyph polys
    items = []
    pen = 0.0
    prev = None
    for ch in text:
        gn = cmap.get(ord(ch))
        if gn is None:
            continue
        if prev is not None:
            pen += kern.get((prev, gn), 0) * scale
        items.append((gn, pen))
        pen += hmtx[gn][0] * scale
        prev = gn
    w = int(pen + px * 0.5) + 8
    h = int(px * 1.6) + 8
    mask = Image.new("L", (w * ss, h * ss), 0)
    base_y = int(px * 1.0)
    for gn, gx in items:
        polys = glyph_polys(font, gs, gn)
        if not polys:
            continue
        allp = [[((gx + p[0] * scale + 4) * ss, (base_y - p[1] * scale) * ss) for p in c] for c in polys]
        xs = [q[0] for c in allp for q in c]; ys = [q[1] for c in allp for q in c]
        x0, y0 = int(min(xs)) - 2, int(min(ys)) - 2
        x1, y1 = int(max(xs)) + 3, int(max(ys)) + 3
        m = Image.new("L", (x1 - x0, y1 - y0), 0)
        d = ImageDraw.Draw(m)
        for c, cp in sorted(zip(polys, allp), key=lambda t: -abs(area(t[0]))):
            d.polygon([(q[0] - x0, q[1] - y0) for q in cp], fill=255 if area(c) < 0 else 0)
        region = mask.crop((x0, y0, x1, y1))
        from PIL import ImageChops
        mask.paste(ImageChops.lighter(region, m), (x0, y0))
    mask = mask.resize((w, h), Image.LANCZOS)
    layer = Image.new("RGB", (w, h), color)
    bg_img.paste(layer, (int(x) - 4, int(y) - base_y), mask)
    return x + pen

def get_kern(fontpath):
    from fontTools.ttLib import TTFont
    f = TTFont(fontpath)
    kern = {}
    if "GPOS" in f:
        gpos = f["GPOS"].table
        for lk in gpos.LookupList.Lookup:
            for st in lk.SubTable:
                if st.__class__.__name__ == "ExtensionPos":
                    st = st.ExtSubTable
                if getattr(st, "LookupType", 0) == 2:
                    if st.Format == 1:
                        cov = st.Coverage.glyphs
                        for g1, ps in zip(cov, st.PairSet):
                            for pvr in ps.PairValueRecord:
                                v = getattr(pvr.Value1, "XAdvance", 0) if pvr.Value1 else 0
                                kern[(g1, pvr.SecondGlyph)] = v or 0
                    else:
                        cd1 = st.ClassDef1.classDefs; cd2 = st.ClassDef2.classDefs
                        glyphs1 = st.Coverage.glyphs
                        allg = f.getGlyphOrder()
                        for g1 in glyphs1:
                            c1 = cd1.get(g1, 0)
                            rec = st.Class1Record[c1]
                            for g2 in allg:
                                c2 = cd2.get(g2, 0)
                                if c2 == 0:
                                    continue
                                v = getattr(rec.Class2Record[c2].Value1, "XAdvance", 0) if rec.Class2Record[c2].Value1 else 0
                                if v:
                                    kern.setdefault((g1, g2), v)
    return kern

def make_specimen(fontpath, outpng, title, sub, test_lines, charset_rows):
    from fontTools.ttLib import TTFont
    f = TTFont(fontpath)
    gs = f.getGlyphSet()
    cmap = f.getBestCmap()
    hmtx = f["hmtx"]
    kern = get_kern(fontpath)
    W = 3000
    bg = (17, 17, 22)
    fg = (240, 236, 228)
    dim = (130, 130, 145)
    img = Image.new("RGB", (W, 6000), bg)
    d = ImageDraw.Draw(img)
    try:
        lab = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 26)
    except Exception:
        lab = ImageFont.load_default()
    y = 40
    d.text((60, y), title + "  -  " + sub, fill=dim, font=lab)
    y += 90
    # glyph rows (px 110)
    for row in charset_rows:
        y += 120
        render_text(f, gs, cmap, hmtx, kern, row, 110, fg, img, 60, y)
        y += 50
    y += 20
    d.text((60, y), "TEST LINES  (36 pt and 96 pt, shown at 1.15x: 41 px and 110 px)", fill=dim, font=lab)
    y += 40
    for pt in (36, 96):
        px = int(pt * 1.15)
        for t in test_lines:
            y += int(px * 0.95)
            render_text(f, gs, cmap, hmtx, kern, t, px, fg, img, 60, y)
            y += int(px * 0.35)
        y += 30
    # 28pt preview strip
    d.text((60, y), "28 pt next-line preview (1.15x = 32 px)", fill=dim, font=lab)
    y += 40
    y += 60
    render_text(f, gs, cmap, hmtx, kern, test_lines[0], 32, fg, img, 60, y)
    y += 90
    img = img.crop((0, 0, W, y + 40))
    img.save(outpng)
    return img

# ------------------------------------------------------------- verification
def verify(fontpath, required):
    from fontTools.ttLib import TTFont
    f = TTFont(fontpath)
    cmap = f.getBestCmap()
    gs = f.getGlyphSet()
    problems = []
    for ch in required:
        gn = cmap.get(ord(ch))
        if gn is None:
            problems.append("missing " + repr(ch))
            continue
        if ch == " ":
            continue
        g = f["glyf"][gn]
        if g.numberOfContours == 0:
            problems.append("empty " + gn)
    h = f["hhea"]; o = f["OS/2"]
    info = dict(upem=f["head"].unitsPerEm, asc=h.ascent, desc=h.descent, gap=h.lineGap,
                typo=(o.sTypoAscender, o.sTypoDescender, o.sTypoLineGap), win=(o.usWinAscent, o.usWinDescent),
                fsSel=bin(o.fsSelection), xh=o.sxHeight, cap=o.sCapHeight, names=f["name"].getDebugName(6),
                nglyphs=len(f.getGlyphOrder()))
    return problems, info
