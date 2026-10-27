"""lyrakit - shared glyph-construction toolkit for the Lyra "Drawn" fonts.

Skeleton strokes (centre-lines in a unit box) are turned into outlines with a
variable-width pen model, unioned with skia-pathops, optionally cut (stencil
bridges / notches), sheared (italic), spaced and kerned automatically, and
written to a TrueType font with fontTools.
"""
import math
import numpy as np
import pathops
from pathops import PathOp
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.fontBuilder import FontBuilder
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.agl import UV2AGL

# --------------------------------------------------------------------------
# character set
# --------------------------------------------------------------------------
UP = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
LOW = UP.lower()
DIG = "0123456789"
PUNCT = list(".,!?'\"‘’“”-–—:;&()/\\#@%+=$*…_~^<>[]{}|`¡¿")
ACC_UP = {
    "À": ("A", "grave"), "Á": ("A", "acute"), "Â": ("A", "circ"),
    "Ã": ("A", "tilde"), "Ä": ("A", "diaer"), "Å": ("A", "ring"),
    "Ç": ("C", "cedilla"),
    "È": ("E", "grave"), "É": ("E", "acute"), "Ê": ("E", "circ"), "Ë": ("E", "diaer"),
    "Ì": ("I", "grave"), "Í": ("I", "acute"), "Î": ("I", "circ"), "Ï": ("I", "diaer"),
    "Ñ": ("N", "tilde"),
    "Ò": ("O", "grave"), "Ó": ("O", "acute"), "Ô": ("O", "circ"),
    "Õ": ("O", "tilde"), "Ö": ("O", "diaer"),
    "Ù": ("U", "grave"), "Ú": ("U", "acute"), "Û": ("U", "circ"), "Ü": ("U", "diaer"),
    "Ý": ("Y", "acute"),
}
ACC_LOW = {
    "à": ("a", "grave"), "á": ("a", "acute"), "â": ("a", "circ"),
    "ã": ("a", "tilde"), "ä": ("a", "diaer"), "å": ("a", "ring"),
    "ç": ("c", "cedilla"),
    "è": ("e", "grave"), "é": ("e", "acute"), "ê": ("e", "circ"), "ë": ("e", "diaer"),
    "ì": ("ı", "grave"), "í": ("ı", "acute"), "î": ("ı", "circ"), "ï": ("ı", "diaer"),
    "ñ": ("n", "tilde"),
    "ò": ("o", "grave"), "ó": ("o", "acute"), "ô": ("o", "circ"),
    "õ": ("o", "tilde"), "ö": ("o", "diaer"),
    "ù": ("u", "grave"), "ú": ("u", "acute"), "û": ("u", "circ"), "ü": ("u", "diaer"),
    "ý": ("y", "acute"), "ÿ": ("y", "diaer"),
}
SPECIAL = ["Æ", "Ø", "æ", "ø", "ß"]
REQUIRED = [" "] + list(UP) + list(LOW) + list(DIG) + PUNCT + list(ACC_UP) + list(ACC_LOW) + SPECIAL
# space, accent chars; U+0131 is a helper glyph only (dotless i for i-accents)


def glyph_name(ch):
    cp = ord(ch)
    if ch == "ı":
        return "dotlessi"
    return UV2AGL.get(cp) or "uni%04X" % cp


# --------------------------------------------------------------------------
# small geometry helpers
# --------------------------------------------------------------------------
def area(poly):
    a = 0.0
    n = len(poly)
    for i in range(n):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % n]
        a += x0 * y1 - x1 * y0
    return a / 2


def sub(a, b): return (a[0] - b[0], a[1] - b[1])
def add(a, b): return (a[0] + b[0], a[1] + b[1])
def mul(a, s): return (a[0] * s, a[1] * s)
def ln(a): return math.hypot(a[0], a[1])
def cross(a, b): return a[0] * b[1] - a[1] * b[0]
def dot2(a, b): return a[0] * b[0] + a[1] * b[1]


def unit(a):
    l = ln(a)
    return (a[0] / l, a[1] / l) if l > 1e-9 else (1.0, 0.0)


def seg_dist(p, a, b):
    ab = sub(b, a)
    L2 = dot2(ab, ab)
    if L2 < 1e-9:
        return ln(sub(p, a))
    t = max(0.0, min(1.0, dot2(sub(p, a), ab) / L2))
    return ln(sub(p, (a[0] + ab[0] * t, a[1] + ab[1] * t)))


# --------------------------------------------------------------------------
# pen model
# --------------------------------------------------------------------------
class Pen:
    def __init__(self, tmin, tmax=None, nib=0.0, exp=1.0, taper=0.0, taper_pow=0.9,
                 tip=2.5, miter=3.0):
        self.tmin = tmin
        self.tmax = tmax if tmax is not None else tmin
        self.nib = math.radians(nib)
        self.exp = exp
        self.taper = taper
        self.taper_pow = taper_pow
        self.tip = tip
        self.miter = miter

    def width(self, d):
        th = math.atan2(d[1], d[0])
        return self.tmin + (self.tmax - self.tmin) * abs(math.sin(th - self.nib)) ** self.exp


def sample_centerline(P, closed, cfg, step):
    """P: list of (x,y,k) in real coords -> dense list of points (open: includes ends)."""
    n = len(P)
    core = []
    for i in range(n):
        x, y, k = P[i][0], P[i][1], P[i][2]
        interior = closed or (0 < i < n - 1)
        if not interior or k <= 0:
            core.append((x, y))
            continue
        prv = P[(i - 1) % n]
        nxt = P[(i + 1) % n]
        cur = (x, y)
        lp = ln(sub(prv, cur))
        lnx = ln(sub(nxt, cur))
        if lp < 1e-6 or lnx < 1e-6:
            core.append(cur)
            continue
        d = cfg.cut(k, lp, lnx)
        if d < 1.0:
            core.append(cur)
            continue
        E = add(cur, mul(sub(prv, cur), d / lp))
        X = add(cur, mul(sub(nxt, cur), d / lnx))
        if cfg.corner == "chamfer":
            core.extend([E, X])
        else:
            m = max(5, int(d * 1.6 / step) + 2)
            for j in range(m + 1):
                t = j / m
                a = (1 - t) ** 2
                b = 2 * t * (1 - t)
                c = t * t
                core.append((a * E[0] + b * cur[0] + c * X[0], a * E[1] + b * cur[1] + c * X[1]))
    # dedupe
    out = [core[0]]
    for p in core[1:]:
        if ln(sub(p, out[-1])) > 0.05:
            out.append(p)
    if closed and len(out) > 1 and ln(sub(out[0], out[-1])) < 0.05:
        out.pop()
    # densify
    dense = []
    m = len(out)
    rng = m if closed else m - 1
    for i in range(rng):
        a = out[i]
        b = out[(i + 1) % m]
        L = ln(sub(b, a))
        c = max(1, int(math.ceil(L / step)))
        for j in range(c):
            t = j / c
            dense.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    if not closed:
        dense.append(out[-1])
    return dense


def stroke_polys(pts, closed, free0, free1, pen):
    """Variable-width stroke -> list of convex-ish polygons (to be unioned)."""
    n = len(pts)
    if n < 2:
        return []
    nseg = n if closed else n - 1
    dirs = [unit(sub(pts[(j + 1) % n], pts[j])) for j in range(nseg)]
    # arc length
    S = [0.0]
    for j in range(nseg):
        S.append(S[-1] + ln(sub(pts[(j + 1) % n], pts[j])))
    L = S[-1]
    tl = min(pen.taper, 0.48 * L) if pen.taper > 0 else 0

    def tap(s):
        f = 1.0
        if tl > 0:
            if free0:
                f = min(f, (s / tl) ** pen.taper_pow if s < tl else 1.0)
            if free1:
                e = L - s
                f = min(f, (e / tl) ** pen.taper_pow if e < tl else 1.0)
        return f

    def wd(d, s):
        w = pen.width(d)
        f = tap(s)
        return max(pen.tip, w * f) if f < 1.0 else w

    # per vertex widths (left-of-vertex = end of seg i-1, right = start of seg i)
    wl = [0.0] * n
    wr = [0.0] * n
    sharp = [False] * n
    for i in range(n):
        d_prev = dirs[(i - 1) % nseg] if (closed or i > 0) else None
        d_next = dirs[i % nseg] if (closed or i < nseg) else None
        s = S[i]
        if d_prev is None:
            wl[i] = wr[i] = wd(d_next, s)
        elif d_next is None:
            wl[i] = wr[i] = wd(d_prev, s)
        else:
            turn = math.degrees(math.atan2(abs(cross(d_prev, d_next)), dot2(d_prev, d_next)))
            if turn > 25:
                sharp[i] = True
                wl[i] = wd(d_prev, s)
                wr[i] = wd(d_next, s)
            else:
                dm = unit(add(d_prev, d_next))
                wl[i] = wr[i] = wd(dm, s)
    polys = []
    for j in range(nseg):
        a = pts[j]
        b = pts[(j + 1) % n]
        d = dirs[j]
        nrm = (-d[1], d[0])
        w0 = wr[j] / 2
        w1 = wl[(j + 1) % n] / 2
        a2 = sub(a, mul(d, 0.45))
        b2 = add(b, mul(d, 0.45))
        w0 += 0.25
        w1 += 0.25
        polys.append([add(a2, mul(nrm, w0)), add(b2, mul(nrm, w1)),
                      sub(b2, mul(nrm, w1)), sub(a2, mul(nrm, w0))])
    rngv = range(n) if closed else range(1, n - 1)
    for i in rngv:
        d1 = dirs[(i - 1) % nseg]
        d2 = dirs[i % nseg]
        cr = cross(d1, d2)
        if abs(cr) < 1e-4 and dot2(d1, d2) > 0:
            continue
        c = pts[i]
        n1 = (-d1[1], d1[0])
        n2 = (-d2[1], d2[0])
        h1 = wl[i] / 2
        h2 = wr[i] / 2
        for sg in (1, -1):
            a = add(c, mul(n1, sg * h1))
            b = add(c, mul(n2, sg * h2))
            poly = [c, a, b]
            outer = (sg == (-1 if cr > 0 else 1))
            if outer and sharp[i] and abs(cr) > 1e-4:
                t = cross(sub(b, a), d2) / cr
                m = add(a, mul(d1, t))
                if ln(sub(m, c)) <= pen.miter * max(h1, h2):
                    poly = [c, a, m, b]
            polys.append(poly)
    return polys


# --------------------------------------------------------------------------
# glyph rendering
# --------------------------------------------------------------------------
def to_path(polys):
    path = pathops.Path()
    pen = path.getPen()
    for poly in polys:
        poly = [(round(x * 32) / 32, round(y * 32) / 32) for x, y in poly]
        # drop repeated points
        q = [poly[0]]
        for p in poly[1:]:
            if p != q[-1]:
                q.append(p)
        if len(q) > 1 and q[0] == q[-1]:
            q.pop()
        poly = q
        if len(poly) < 3:
            continue
        if area(poly) < 0:
            poly = poly[::-1]
        if abs(area(poly)) < 0.02:
            continue
        pen.moveTo(poly[0])
        for p in poly[1:]:
            pen.lineTo(p)
        pen.closePath()
    return path


def rect_poly(cx, cy, w, h):
    return [(cx - w / 2, cy - h / 2), (cx + w / 2, cy - h / 2), (cx + w / 2, cy + h / 2), (cx - w / 2, cy + h / 2)]


def path_contours(path):
    rec = RecordingPen()
    path.draw(rec)
    contours = []
    cur = []
    for op, args in rec.value:
        if op == "moveTo":
            cur = [args[0]]
        elif op == "lineTo":
            cur.append(args[0])
        elif op in ("closePath", "endPath"):
            if len(cur) >= 3 and abs(area(cur)) > 30:
                contours.append(cur)
            cur = []
        else:
            raise ValueError("unexpected op " + op)
    return contours


def render_strokes(strokes, frame, cfg, pen, cuts=None, clip=None):
    """strokes: list of skeleton strokes in unit coords. frame=(x0,y0,W,H).
    Returns pathops Path (union), in real coords, before shear."""
    x0, y0, W, H = frame
    inx, iny = cfg.inx, cfg.iny
    Wi, Hi = W - 2 * inx, H - 2 * iny

    def mp(p):
        return (x0 + inx + p[0] * Wi, y0 + iny + p[1] * Hi)

    prepared = []
    polys = []
    for st in strokes:
        if st and st[0] == "dot":
            cx, cy = x0 + st[1] * W, y0 + st[2] * H
            r = cfg.dot_r
            cy = max(cy, y0 + r) if st[2] <= 0.001 else (min(cy, y0 + H - r) if st[2] >= 0.999 else cy)
            polys.extend(cfg.dot(cx, cy))
            continue
        closed = False
        items = list(st)
        if items and items[0] == "C":
            closed = True
            items = items[1:]
        P = []
        flags = []
        for it in items:
            k = it[2] if len(it) > 2 else 0
            fl = it[3] if len(it) > 3 else ""
            rx, ry = mp(it)
            P.append((rx, ry, k))
            flags.append(fl)
        prepared.append((P, closed, flags))
    # joined-end detection needs dense polylines of other strokes
    dense = [sample_centerline(P, closed, cfg, cfg.step) for (P, closed, _f) in prepared]
    for idx, (P, closed, flags) in enumerate(prepared):
        pts = dense[idx]
        free0 = free1 = False
        if not closed and pen.taper > 0:
            ends = []
            for e, pt in ((0, pts[0]), (1, pts[-1])):
                fl = flags[0] if e == 0 else flags[-1]
                if fl == "f":
                    ends.append(True)
                    continue
                if fl == "j":
                    ends.append(False)
                    continue
                joined = False
                for jdx, other in enumerate(dense):
                    if jdx == idx:
                        # own stroke: check touching away from the end (e.g. loops)
                        continue
                    for a in range(len(other) - 1):
                        if seg_dist(pt, other[a], other[a + 1]) < cfg.join_tol:
                            joined = True
                            break
                    if joined:
                        break
                ends.append(not joined)
            free0, free1 = ends
        polys.extend(stroke_polys(pts, closed, free0, free1, pen))
    path = to_path(polys)
    path.simplify(fix_winding=True)
    if cuts:
        cp = to_path(cuts)
        path = pathops.op(path, cp, PathOp.DIFFERENCE, fix_winding=True)
    if clip:
        cp = to_path([clip])
        path = pathops.op(path, cp, PathOp.INTERSECTION, fix_winding=True)
    return path


# --------------------------------------------------------------------------
# outline conversion
# --------------------------------------------------------------------------
def rdp(pts, eps):
    if len(pts) < 3:
        return pts[:]
    a, b = pts[0], pts[-1]
    best, bi = -1, 0
    for i in range(1, len(pts) - 1):
        d = seg_dist(pts[i], a, b)
        if d > best:
            best, bi = d, i
    if best <= eps:
        return [a, b]
    l = rdp(pts[:bi + 1], eps)
    r = rdp(pts[bi:], eps)
    return l[:-1] + r


def rdp_closed(pts, eps):
    n = len(pts)
    if n < 4:
        return pts
    far = max(range(n), key=lambda i: ln(sub(pts[i], pts[0])))
    c1 = rdp(pts[:far + 1], eps)
    c2 = rdp(pts[far:] + [pts[0]], eps)
    return c1[:-1] + c2[:-1]


def classify_and_emit(poly, eps=0.45, smooth_turn=32, max_edge=70):
    """Return list of (x,y,on) points for a closed contour."""
    pts = rdp_closed(poly, eps)
    # drop duplicates
    res = []
    for p in pts:
        if not res or ln(sub(p, res[-1])) > 0.01:
            res.append(p)
    if len(res) > 1 and ln(sub(res[0], res[-1])) < 0.01:
        res.pop()
    n = len(res)
    out = []
    for i in range(n):
        a, b, c = res[i - 1], res[i], res[(i + 1) % n]
        e1, e2 = sub(b, a), sub(c, b)
        l1, l2 = ln(e1), ln(e2)
        turn = math.degrees(math.atan2(abs(cross(e1, e2)), dot2(e1, e2)))
        smooth = (turn < 32 and l1 < max_edge and l2 < max_edge) or turn < 3
        out.append((b[0], b[1], not smooth))
    return out


def glyph_from_contours(contours):
    pen = TTGlyphPen(None)
    for poly in contours:
        pts = classify_and_emit(poly)
        pts = [(round(x), round(y), on) for x, y, on in pts]
        # remove dup after rounding
        clean = []
        for p in pts:
            if clean and clean[-1][:2] == p[:2]:
                if p[2]:
                    clean[-1] = p
                continue
            clean.append(p)
        if len(clean) > 1 and clean[0][:2] == clean[-1][:2]:
            clean.pop()
        if len(clean) < 3:
            continue
        ons = [i for i, p in enumerate(clean) if p[2]]
        if not ons:
            pen.qCurveTo(*[(x, y) for x, y, _ in clean], None)
            pen.closePath()
            continue
        s = ons[0]
        seq = clean[s:] + clean[:s]
        pen.moveTo(seq[0][:2])
        offs = []
        for x, y, on in seq[1:]:
            if on:
                if offs:
                    pen.qCurveTo(*offs, (x, y))
                    offs = []
                else:
                    pen.lineTo((x, y))
            else:
                offs.append((x, y))
        if offs:
            pen.qCurveTo(*offs, seq[0][:2])
        pen.closePath()
    return pen.glyph()


def orient(contours):
    """Outer contours clockwise (negative shoelace area in y-up), holes the opposite."""
    if not contours:
        return contours
    big = max(contours, key=lambda c: abs(area(c)))
    if area(big) > 0:
        return [c[::-1] for c in contours]
    return contours


# --------------------------------------------------------------------------
# profiles for spacing & kerning
# --------------------------------------------------------------------------
BAND = 12


def profile(contours, top, band=BAND):
    """left/right extreme x per y band over [0, top]."""
    nb = int(math.ceil(top / band))
    lo = np.full(nb, np.inf)
    hi = np.full(nb, -np.inf)
    for poly in contours:
        n = len(poly)
        for i in range(n):
            a, b = poly[i], poly[(i + 1) % n]
            L = ln(sub(b, a))
            m = max(1, int(L / 2.5))
            for j in range(m + 1):
                t = j / m
                x = a[0] + (b[0] - a[0]) * t
                y = a[1] + (b[1] - a[1]) * t
                k = int(y // band)
                if 0 <= k < nb:
                    if x < lo[k]:
                        lo[k] = x
                    if x > hi[k]:
                        hi[k] = x
    return lo, hi


# --------------------------------------------------------------------------
# font assembly
# --------------------------------------------------------------------------
def build_ttf(cfg, glyph_data, kern_lines, out_path, extra_cmap=None):
    """glyph_data: dict ch -> (contours(list of polys, final coords, x>=0), advance)"""
    order = [".notdef"]
    cmap = {}
    glyphs = {}
    metrics = {}
    # .notdef: simple box
    nd = TTGlyphPen(None)
    nd.moveTo((60, 0)); nd.lineTo((60, 700)); nd.lineTo((440, 700)); nd.lineTo((440, 0)); nd.closePath()
    nd.moveTo((110, 50)); nd.lineTo((390, 50)); nd.lineTo((390, 650)); nd.lineTo((110, 650)); nd.closePath()
    glyphs[".notdef"] = nd.glyph()
    metrics[".notdef"] = (500, 60)
    for ch, (contours, adv) in glyph_data.items():
        gname = glyph_name(ch)
        order.append(gname)
        if ord(ch) != 0x131:
            cmap[ord(ch)] = gname
        if ch == " ":
            glyphs[gname] = TTGlyphPen(None).glyph()
            metrics[gname] = (adv, 0)
            continue
        g = glyph_from_contours(contours)
        glyphs[gname] = g
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyphs)
    glyf = fb.font["glyf"]
    for ch, (contours, adv) in glyph_data.items():
        gname = glyph_name(ch)
        if ch == " ":
            continue
        g = glyf[gname]
        g.recalcBounds(glyf)
        metrics[gname] = (adv, g.xMin)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=800, descent=-200, lineGap=0)
    if cfg.italic_angle:
        hh = fb.font["hhea"]
        hh.caretSlopeRise = 1000
        hh.caretSlopeRun = int(round(1000 * math.tan(math.radians(-cfg.italic_angle))))
    n = cfg.name_info
    fb.setupNameTable({
        "copyright": n["copyright"],
        "familyName": n["family"],
        "styleName": "Regular",
        "uniqueFontIdentifier": "%s;1.000;LYRA;%s" % (n["family"], n["ps"]),
        "fullName": n["family"] + " Regular",
        "version": "Version 1.000",
        "psName": n["ps"],
        "manufacturer": "Lyra",
        "designer": "Lyra (generated by build script)",
        "description": n["description"],
        "licenseDescription": n["license"],
        "licenseInfoURL": "https://openfontlicense.org",
    })
    fb.setupOS2(
        version=4,
        sTypoAscender=800, sTypoDescender=-200, sTypoLineGap=0,
        usWinAscent=900, usWinDescent=250,
        sxHeight=cfg.xheight, sCapHeight=700,
        fsSelection=0x40 | 0x80,
        usWeightClass=cfg.weight_class, usWidthClass=5,
        achVendID="LYRA", fsType=0,
        ulUnicodeRange1=0x8000008F, ulCodePageRange1=0x1,
        usFirstCharIndex=0x20, usLastCharIndex=0x2026,
    )
    fb.setupPost(italicAngle=cfg.italic_angle, underlinePosition=-100, underlineThickness=50)
    from fontTools.ttLib import newTable
    gasp = newTable("gasp")
    gasp.version = 1
    gasp.gaspRange = {65535: 0x000F}
    fb.font["gasp"] = gasp
    font = fb.font
    font["head"].macStyle = 0
    font["head"].flags |= 0x0001 | 0x0008
    fea = "languagesystem DFLT dflt;\nlanguagesystem latn dflt;\n" + kern_lines
    addOpenTypeFeaturesFromString(font, fea)
    font.save(out_path)
    return out_path


def kern_fea(classes_left, classes_right, pairs):
    """classes_*: dict base-char -> list of glyph names. pairs: dict (a,b)->value"""
    lines = []
    for k, gl in classes_left.items():
        lines.append("@L_%s = [%s];" % (glyph_name(k), " ".join(gl)))
    for k, gl in classes_right.items():
        lines.append("@R_%s = [%s];" % (glyph_name(k), " ".join(gl)))
    lines.append("feature kern {")
    for (a, b), v in sorted(pairs.items()):
        lines.append("  pos @L_%s @R_%s %d;" % (glyph_name(a), glyph_name(b), v))
    lines.append("} kern;")
    return "\n".join(lines) + "\n"


# --------------------------------------------------------------------------
# verification
# --------------------------------------------------------------------------
def verify(ttf_path, expect_xheight=None):
    from fontTools.ttLib import TTFont
    f = TTFont(ttf_path)
    cmap = f.getBestCmap()
    glyf = f["glyf"]
    hmtx = f["hmtx"]
    problems = []
    for ch in REQUIRED:
        if ord(ch) not in cmap:
            problems.append("missing " + repr(ch))
            continue
        gn = cmap[ord(ch)]
        g = glyf[gn]
        if ch != " " and g.numberOfContours == 0:
            problems.append("empty " + repr(ch))
    # overlap / orientation check
    from fontTools.pens.pointPen import SegmentToPointPen
    bad_orient = []
    overl = []
    for ch in REQUIRED:
        if ch == " " or ord(ch) not in cmap:
            continue
        gn = cmap[ord(ch)]
        path = pathops.Path()
        glyf[gn].draw(path.getPen(), glyf)
        n0 = len(list(path.contours))
        # orientation: sum of areas of contours by clockwise flag
        conts = list(path.contours)
        cw = [c.clockwise for c in conts]
        if not conts:
            continue
        big = max(conts, key=lambda c: abs(c.area))
        if not big.clockwise:
            bad_orient.append(ch)
        p2 = pathops.Path(path)
        p2.simplify(fix_winding=True)
        n1 = len(list(p2.contours))
        if n1 != n0:
            overl.append((ch, n0, n1))
    return {
        "glyphs": len(f.getGlyphOrder()),
        "problems": problems,
        "bad_orient": bad_orient,
        "overlap_suspects": overl,
        "upm": f["head"].unitsPerEm,
        "hhea": (f["hhea"].ascent, f["hhea"].descent, f["hhea"].lineGap),
        "typo": (f["OS/2"].sTypoAscender, f["OS/2"].sTypoDescender, f["OS/2"].sTypoLineGap),
        "win": (f["OS/2"].usWinAscent, f["OS/2"].usWinDescent),
        "fsSelection": bin(f["OS/2"].fsSelection),
        "has_gpos": "GPOS" in f,
    }


def gpos_pairs(ttf_path):
    """Return {(left_glyph,right_glyph): value} read back from GPOS."""
    from fontTools.ttLib import TTFont
    f = TTFont(ttf_path)
    res = {}
    if "GPOS" not in f:
        return res
    for lk in f["GPOS"].table.LookupList.Lookup:
        for st in lk.SubTable:
            if st.LookupType == 9:
                st = st.ExtSubTable
            if st.LookupType != 2:
                continue
            cov = st.Coverage.glyphs
            if st.Format == 1:
                for g, ps in zip(cov, st.PairSet):
                    for r in ps.PairValueRecord:
                        res[(g, r.SecondGlyph)] = r.Value1.XAdvance if r.Value1 else 0
            else:
                cd1 = st.ClassDef1.classDefs
                cd2 = st.ClassDef2.classDefs
                for g1 in cov:
                    c1 = cd1.get(g1, 0)
                    rec = st.Class1Record[c1]
                    for g2, c2 in cd2.items():
                        v = rec.Class2Record[c2].Value1
                        if v is not None and getattr(v, "XAdvance", 0):
                            res.setdefault((g1, g2), v.XAdvance)
    return res


# --------------------------------------------------------------------------
# specimen
# --------------------------------------------------------------------------
TEST_LINES = [
    "Midnight in the city lights",
    "HOLD ME CLOSER, TONIGHT!",
    "Quick zephyrs blow, vexing daft Jim. 0123456789",
    "Can't stop (won't stop) - 100% yours & mine?",
]


def make_specimen(ttf_path, png_path, title, bg=(14, 15, 20), fg=(236, 238, 244), accent=(120, 150, 255)):
    from PIL import Image, ImageDraw, ImageFont
    from fontTools.ttLib import TTFont
    f = TTFont(ttf_path)
    cmap = f.getBestCmap()
    hmtx = f["hmtx"]
    upm = f["head"].unitsPerEm
    kp = gpos_pairs(ttf_path)
    W = 2600
    margin = 80
    gap = 36

    def line_width(txt, px):
        w = 0
        prev = None
        for ch in txt:
            gn = cmap.get(ord(ch))
            if gn is None:
                continue
            if prev:
                w += kp.get((prev, gn), 0)
            w += hmtx[gn][0]
            prev = gn
        return w * px / upm

    def draw_line(d, txt, x, y_base, px, color):
        font = ImageFont.truetype(ttf_path, px)
        prev = None
        for ch in txt:
            gn = cmap.get(ord(ch))
            if gn is None:
                continue
            if prev:
                x += kp.get((prev, gn), 0) * px / upm
            if ch != " ":
                d.text((x, y_base), ch, font=font, fill=color, anchor="ls")
            x += hmtx[gn][0] * px / upm
            prev = gn
        return x

    def wrap(chars, px, maxw):
        lines, cur = [], ""
        for ch in chars:
            if line_width(cur + ch, px) > maxw:
                lines.append(cur)
                cur = ch
            else:
                cur += ch
        if cur:
            lines.append(cur)
        return lines

    groups = [
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        "abcdefghijklmnopqrstuvwxyz",
        "0123456789  .,!?'\"‘’“”-–—:;&()/\\#@%+=$*…_~^<>[]{}|`¡¿",
        "ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÑÒÓÔÕÖØÙÚÛÜÝ",
        "àáâãäåæçèéêëìíîïñòóôõöøùúûüýÿß",
    ]
    set_px = 120
    items = []  # (kind, text, px)
    items.append(("label", title + "  -  character set", 34))
    for g in groups:
        for l in wrap(g, set_px, W - 2 * margin):
            items.append(("text", l, set_px))
    for pt in (36, 96):
        items.append(("label", "%d pt (rendered at 2x: %d px)" % (pt, pt * 2), 34))
        for t in TEST_LINES:
            words, cur = t.split(" "), ""
            for w in words:
                if cur and line_width(cur + " " + w, pt * 2) > W - 2 * margin:
                    items.append(("text", cur, pt * 2))
                    cur = w
                else:
                    cur = (cur + " " + w) if cur else w
            items.append(("text", cur, pt * 2))
    # layout
    H = margin
    rows = []
    for kind, txt, px in items:
        if kind == "label":
            H += 40
            rows.append((kind, txt, px, H))
            H += 24
        else:
            asc = int(px * 0.98)
            H += asc
            rows.append((kind, txt, px, H))
            H += int(px * 0.34) + gap // 2
    H += margin
    img = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(img)
    try:
        lf = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 28)
    except Exception:
        lf = ImageFont.load_default()
    for kind, txt, px, y in rows:
        if kind == "label":
            d.text((margin, y), txt, font=lf, fill=accent, anchor="ls")
        else:
            draw_line(d, txt, margin, y, px, fg)
    img.save(png_path)
    return png_path


OFL_TEXT = """Copyright (c) 2026, Lyra (generated glyph outlines; see build script).

This Font Software is licensed under the SIL Open Font License, Version 1.1.
This license is copied below, and is also available with a FAQ at:
https://openfontlicense.org

-----------------------------------------------------------
SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007
-----------------------------------------------------------

PREAMBLE
The goals of the Open Font License (OFL) are to stimulate worldwide
development of collaborative font projects, to support the font creation
efforts of academic and linguistic communities, and to provide a free and
open framework in which fonts may be shared and improved in partnership
with others.

The OFL allows the licensed fonts to be used, studied, modified and
redistributed freely as long as they are not sold by themselves. The
fonts, including any derivative works, can be bundled, embedded,
redistributed and/or sold with any software provided that any reserved
names are not used by derivative works. The fonts and derivatives,
however, cannot be released under any other type of license. The
requirement for fonts to remain under this license does not apply
to any document created using the fonts or their derivatives.

DEFINITIONS
"Font Software" refers to the set of files released by the Copyright
Holder(s) under this license and clearly marked as such. This may
include source files, build scripts and documentation.

"Reserved Font Name" refers to any names specified as such after the
copyright statement(s).

"Original Version" refers to the collection of Font Software components as
distributed by the Copyright Holder(s).

"Modified Version" refers to any derivative made by adding to, deleting,
or substituting -- in part or in whole -- any of the components of the
Original Version, by changing formats or by porting the Font Software to a
new environment.

"Author" refers to any designer, engineer, programmer, technical
writer or other person who contributed to the Font Software.

PERMISSION & CONDITIONS
Permission is hereby granted, free of charge, to any person obtaining
a copy of the Font Software, to use, study, copy, merge, embed, modify,
redistribute, and sell modified and unmodified copies of the Font
Software, subject to the following conditions:

1) Neither the Font Software nor any of its individual components,
in Original or Modified Versions, may be sold by itself.

2) Original or Modified Versions of the Font Software may be bundled,
redistributed and/or sold with any software, provided that each copy
contains the above copyright notice and this license. These can be
included either as stand-alone text files, human-readable headers or
in the appropriate machine-readable metadata fields within text or
binary files as long as those fields can be easily viewed by the user.

3) No Modified Version of the Font Software may use the Reserved Font
Name(s) unless explicit written permission is granted by the corresponding
Copyright Holder. This restriction only applies to the primary font name as
presented to the users.

4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font
Software shall not be used to promote, endorse or advertise any
Modified Version, except to acknowledge the contribution(s) of the
Copyright Holder(s) and the Author(s) or with their explicit written
permission.

5) The Font Software, modified or unmodified, in part or in whole,
must be distributed entirely under this license, and must not be
distributed under any other license. The requirement for fonts to
remain under this license does not apply to any document created
using the Font Software.

TERMINATION
This license becomes null and void if any of the above conditions are
not met.

DISCLAIMER
THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT
OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE
COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL
DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM
OTHER DEALINGS IN THE FONT SOFTWARE.
"""
