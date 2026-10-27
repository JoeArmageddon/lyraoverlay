"""Pen/nib stroker + polyline->curve fitter used by build_thorn.py (original code)."""
import math
import numpy as np
import pathops

def _norm(v):
    n = math.hypot(v[0], v[1]); return (v[0] / n, v[1] / n) if n > 1e-9 else (1.0, 0.0)

# ---------------------------------------------------------------- centre-line sampling
def line_pts(p0, p1, step=9.0):
    L = math.hypot(p1[0] - p0[0], p1[1] - p0[1]); n = max(2, int(L / step) + 1)
    return [(p0[0] + (p1[0] - p0[0]) * i / n, p0[1] + (p1[1] - p0[1]) * i / n) for i in range(n + 1)]

def arc_pts(cx, cy, rx, ry, a0, a1, step=6.0):
    t0, t1 = math.radians(a0), math.radians(a1)
    # approximate length
    L = 0; n0 = 40; prev = None
    for i in range(n0 + 1):
        t = t0 + (t1 - t0) * i / n0; p = (rx * math.cos(t), ry * math.sin(t))
        if prev: L += math.hypot(p[0] - prev[0], p[1] - prev[1])
        prev = p
    n = max(6, int(L / step))
    return [(cx + rx * math.cos(t0 + (t1 - t0) * i / n), cy + ry * math.sin(t0 + (t1 - t0) * i / n)) for i in range(n + 1)]

def bez_pts(p0, p1, p2, p3, step=6.0):
    pts = []
    n0 = 60
    L = 0; prev = p0
    for i in range(1, n0 + 1):
        t = i / n0; b = _bez(p0, p1, p2, p3, t); L += math.hypot(b[0] - prev[0], b[1] - prev[1]); prev = b
    n = max(6, int(L / step))
    return [_bez(p0, p1, p2, p3, i / n) for i in range(n + 1)]

def _bez(p0, p1, p2, p3, t):
    u = 1 - t
    return (u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
            u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1])

def join(*lists):
    out = []
    for l in lists:
        for p in l:
            if not out or math.hypot(p[0] - out[-1][0], p[1] - out[-1][1]) > 0.5: out.append(p)
    return out

# ---------------------------------------------------------------- ribbon
def _area(poly):
    a = 0
    for i in range(len(poly)):
        x1, y1 = poly[i]; x2, y2 = poly[(i + 1) % len(poly)]; a += x1 * y2 - x2 * y1
    return a / 2

def densify(pts, step=8.0, closed=False):
    out = []
    n = len(pts)
    rng = range(n if closed else n - 1)
    for i in rng:
        a, b = pts[i], pts[(i + 1) % n]
        L = math.hypot(b[0] - a[0], b[1] - a[1]); k = max(1, int(math.ceil(L / step)))
        for j in range(k): out.append((a[0] + (b[0] - a[0]) * j / k, a[1] + (b[1] - a[1]) * j / k))
    if not closed: out.append(pts[-1])
    return out

def ribbon(pts, wfun, closed=False):
    pts = densify(pts, closed=closed)
    """pts: dense centre-line; wfun(s, L, phi) -> full width. returns list of polygons (ccw outer, cw holes)."""
    n = len(pts)
    S = [0.0]
    for i in range(1, n): S.append(S[-1] + math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]))
    L = S[-1]
    left, right = [], []
    for i in range(n):
        if closed:
            a = pts[(i - 1) % n]; b = pts[(i + 1) % n]
        else:
            a = pts[max(i - 1, 0)]; b = pts[min(i + 1, n - 1)]
        tx, ty = _norm((b[0] - a[0], b[1] - a[1]))
        phi = math.atan2(ty, tx)
        w = wfun(S[i], L, phi) / 2
        nx, ny = -ty, tx
        left.append((pts[i][0] + nx * w, pts[i][1] + ny * w))
        right.append((pts[i][0] - nx * w, pts[i][1] - ny * w))
    if closed:
        la, ra = _area(left), _area(right)
        polys = [left, right]
        # outer = larger |area| ccw ; inner reversed
        res = []
        big, small = (left, right) if abs(la) >= abs(ra) else (right, left)
        if _area(big) < 0: big = big[::-1]
        if _area(small) > 0: small = small[::-1]
        return [big, small]
    poly = left + right[::-1]
    if _area(poly) < 0: poly = poly[::-1]
    return [poly]

def polys_to_path(polys):
    p = pathops.Path()
    for poly in polys:
        p.moveTo(*poly[0])
        for q in poly[1:]: p.lineTo(*q)
        p.close()
    return p

# ---------------------------------------------------------------- Schneider curve fitting
def _bezier_q(ctrl, t):
    u = 1 - t
    return (u**3)[:, None] * ctrl[0] + (3 * u * u * t)[:, None] * ctrl[1] + (3 * u * t * t)[:, None] * ctrl[2] + (t**3)[:, None] * ctrl[3]

def _bez1(ctrl, t):
    u = 1 - t
    return u**3 * ctrl[0] + 3 * u * u * t * ctrl[1] + 3 * u * t * t * ctrl[2] + t**3 * ctrl[3]

def _chord_param(pts):
    d = np.r_[0, np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))]
    return d / d[-1] if d[-1] > 0 else d

def _gen_bezier(pts, u, t1, t2):
    p0, p3 = pts[0], pts[-1]
    A1 = (3 * (1 - u)**2 * u)[:, None] * t1; A2 = (3 * (1 - u) * u**2)[:, None] * t2
    C = np.zeros((2, 2)); X = np.zeros(2)
    for i in range(len(pts)):
        a1, a2 = A1[i], A2[i]
        C[0, 0] += a1 @ a1; C[0, 1] += a1 @ a2; C[1, 1] += a2 @ a2
        b0 = (1 - u[i])**3 + 3 * (1 - u[i])**2 * u[i]; b3 = 3 * (1 - u[i]) * u[i]**2 + u[i]**3
        tmp = pts[i] - (p0 * b0 + p3 * b3)
        X[0] += a1 @ tmp; X[1] += a2 @ tmp
    C[1, 0] = C[0, 1]
    det = C[0, 0] * C[1, 1] - C[1, 0] * C[0, 1]
    seg = np.linalg.norm(p3 - p0)
    if abs(det) > 1e-12:
        al = (X[0] * C[1, 1] - X[1] * C[0, 1]) / det; ar = (C[0, 0] * X[1] - C[1, 0] * X[0]) / det
    else: al = ar = 0
    eps = 1e-6 * seg
    if al < eps or ar < eps: al = ar = seg / 3
    return np.array([p0, p0 + t1 * al, p3 + t2 * ar, p3])

def _reparam(ctrl, pts, u):
    out = u.copy()
    for i, t in enumerate(u):
        q = _bez1(ctrl, t)
        d1 = 3 * ((1 - t)**2 * (ctrl[1] - ctrl[0]) + 2 * (1 - t) * t * (ctrl[2] - ctrl[1]) + t * t * (ctrl[3] - ctrl[2]))
        d2 = 6 * ((1 - t) * (ctrl[2] - 2 * ctrl[1] + ctrl[0]) + t * (ctrl[3] - 2 * ctrl[2] + ctrl[1]))
        num = (q - pts[i]) @ d1; den = d1 @ d1 + (q - pts[i]) @ d2
        if abs(den) > 1e-12: out[i] = min(1, max(0, t - num / den))
    return out

def _fit_cubic(pts, t1, t2, err, depth=0):
    if len(pts) == 2:
        d = np.linalg.norm(pts[1] - pts[0]) / 3
        return [np.array([pts[0], pts[0] + t1 * d, pts[1] + t2 * d, pts[1]])]
    u = _chord_param(pts)
    ctrl = _gen_bezier(pts, u, t1, t2)
    def maxerr(ctrl, u):
        q = _bezier_q(ctrl, u); d = np.sum((q - pts)**2, axis=1); i = int(np.argmax(d)); return d[i], i
    e, split = maxerr(ctrl, u)
    if e < err * err: return [ctrl]
    if e < (err * 4)**2:
        for _ in range(12):
            u = _reparam(ctrl, pts, u); ctrl = _gen_bezier(pts, u, t1, t2)
            e, split = maxerr(ctrl, u)
            if e < err * err: return [ctrl]
    split = min(max(split, 1), len(pts) - 2)
    tc = pts[split - 1] - pts[split + 1]; tc = tc / (np.linalg.norm(tc) or 1)
    return _fit_cubic(pts[:split + 1], t1, tc, err, depth + 1) + _fit_cubic(pts[split:], -tc, t2, err, depth + 1)

def _tangent(pts, i, fwd, span=10.0):
    n = len(pts); acc = 0; j = i
    step = 1 if fwd else -1
    while 0 <= j + step < n and acc < span:
        acc += np.linalg.norm(pts[j + step] - pts[j]); j += step
    v = pts[j] - pts[i]
    nv = np.linalg.norm(v)
    return v / nv if nv > 1e-9 else np.array([1.0, 0])

def fit_path(path, err=2.0, corner_deg=32, min_edge=1.2):
    """polyline contours (from pathops) -> smooth cubic outlines"""
    out = pathops.Path()
    contours = []
    cur = None
    for verb, pts in path.segments:
        if verb == 'moveTo': cur = [pts[0]]; contours.append(cur)
        elif verb == 'lineTo': cur.append(pts[0])
        elif verb in ('closePath', 'endPath'): pass
        else:
            # curves already present: keep as-is by sampling endpoints (should not occur)
            cur.append(pts[-1])
    for c in contours:
        P = [np.array(p, float) for p in c]
        # drop duplicates / tiny edges
        Q = [P[0]]
        for p in P[1:]:
            if np.linalg.norm(p - Q[-1]) >= min_edge: Q.append(p)
        if len(Q) > 1 and np.linalg.norm(Q[0] - Q[-1]) < min_edge: Q.pop()
        if len(Q) < 3: continue
        if abs(_area([tuple(q) for q in Q])) < 120: continue
        P = np.array(Q); n = len(P)
        # corner detection
        corners = []
        for i in range(n):
            # use cumulative-distance windows for direction
            def dirto(i, fwd):
                acc = 0; j = i
                while acc < 9.0:
                    k = (j + (1 if fwd else -1)) % n
                    acc += np.linalg.norm(P[k] - P[j]); j = k
                    if k == i: break
                v = P[j] - P[i]; nv = np.linalg.norm(v); return v / nv if nv > 1e-9 else np.array([1.0, 0])
            a = dirto(i, False) * -1; b = dirto(i, True)
            ang = math.degrees(math.acos(max(-1, min(1, a @ b))))
            if ang > corner_deg: corners.append((ang, i))
        # keep local maxima of corner angle (merge neighbours within 3 vertices)
        cidx = []
        corners.sort(key=lambda t: -t[0])
        taken = set()
        for ang, i in corners:
            if any(((i - j) % n) <= 2 or ((j - i) % n) <= 2 for j in taken): continue
            taken.add(i)
        cidx = sorted(taken)
        if not cidx:
            # smooth closed contour: split in 4
            cidx = [int(n * k / 4) for k in range(4)]
            smooth_starts = True
        else: smooth_starts = False
        runs = []
        for k, i in enumerate(cidx):
            j = cidx[(k + 1) % len(cidx)]
            idx = list(range(i, j + 1)) if j > i else list(range(i, n)) + list(range(0, j + 1))
            if len(cidx) == 1: idx = list(range(i, n)) + list(range(0, i + 1))
            runs.append(idx)
        first = P[runs[0][0]]
        out.moveTo(*first)
        for ri, idx in enumerate(runs):
            seg = P[idx]
            if len(seg) == 2:
                out.lineTo(*seg[-1]); continue
            chord = seg[-1] - seg[0]; cl = np.linalg.norm(chord)
            if cl > 1e-6:
                dev = np.abs((seg[:, 0] - seg[0, 0]) * chord[1] - (seg[:, 1] - seg[0, 1]) * chord[0]) / cl
                if dev.max() < 1.3:
                    out.lineTo(*seg[-1]); continue
            if smooth_starts:
                t1 = _tangent_c(P, idx[0], True); t2 = -_tangent_c(P, idx[-1], False)
                t2 = -_tangent_c(P, idx[-1], True)
                t2 = -t2 * -1  # forward tangent at end, flipped below
                t2 = -_tangent_c(P, idx[-1], True)
            else:
                t1 = _tangent(seg, 0, True); t2 = _tangent(seg, len(seg) - 1, False)
            cubs = _fit_cubic(seg, t1, t2, err)
            lo = seg.min(axis=0) - 60; hi = seg.max(axis=0) + 60
            bad = any((c4[1:3] < lo).any() or (c4[1:3] > hi).any() or not np.isfinite(c4).all() for c4 in cubs)
            if bad:
                for q in seg[1:]: out.lineTo(*q)
            else:
                for c4 in cubs: out.cubicTo(*c4[1], *c4[2], *c4[3])
        out.close()
    return out

def _tangent_c(P, i, fwd, span=12.0):
    n = len(P); acc = 0; j = i; step = 1 if fwd else -1
    while acc < span:
        k = (j + step) % n; acc += np.linalg.norm(P[k] - P[j]); j = k
    # central direction
    a = P[(i - 1) % n]; 
    jb = i; acc = 0
    while acc < span:
        k = (jb - 1) % n; acc += np.linalg.norm(P[k] - P[jb]); jb = k
    jf = i; acc = 0
    while acc < span:
        k = (jf + 1) % n; acc += np.linalg.norm(P[k] - P[jf]); jf = k
    v = P[jf] - P[jb]; nv = np.linalg.norm(v)
    return v / nv
