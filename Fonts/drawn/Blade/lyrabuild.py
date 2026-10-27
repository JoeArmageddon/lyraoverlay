"""lyrabuild - turns a font config (skeletons + pen + style rules) into glyph data,
spacing and kerning.  Shared by the three Lyra Drawn generators."""
import copy
import math
import numpy as np
import pathops
from pathops import PathOp
import lyrakit as K
from lyrakit import (render_strokes, path_contours, orient, profile, rect_poly,
                     UP, LOW, DIG, PUNCT, ACC_UP, ACC_LOW, glyph_name)

NOCLIP = set(PUNCT) | {"i_lc", "j_lc"}
KSET = list(UP + LOW + DIG) + list(".,!?'’‘\"“”-:;()")


def skel_get(cfg, key, Wi, Hi):
    s = cfg.skel[key]
    if callable(s):
        s = s(Wi, Hi)
    return s


def mark_strokes(kind):
    # unit-box strokes for accents (x,y in 0..1)
    if kind == "grave":
        return [[(0.05, 1.0, 0, "f"), (0.95, 0.0, 0, "f")]]
    if kind == "acute":
        return [[(0.05, 0.0, 0, "f"), (0.95, 1.0, 0, "f")]]
    if kind == "circ":
        return [[(0.0, 0.0, 0, "f"), (0.5, 1.0), (1.0, 0.0, 0, "f")]]
    if kind == "diaer":
        return [("dot", 0.18, 0.5), ("dot", 0.82, 0.5)]
    if kind == "tilde":
        return [[(0.0, 0.2, 0, "f"), (0.3, 0.85, 1), (0.7, 0.15, 1), (1.0, 0.8, 0, "f")]]
    if kind == "ring":
        return [["C", (0.0, 0.0, 1), (1.0, 0.0, 1), (1.0, 1.0, 1), (0.0, 1.0, 1)]]
    if kind == "cedilla":
        return [[(0.35, 1.0, 0, "f"), (0.35, 0.3, 0, "j"), (0.9, 0.0, 0, "f")]]
    raise KeyError(kind)


def sheared(contours, slant):
    t = math.tan(math.radians(slant))
    return [[(x + y * t, y) for x, y in c] for c in contours]


def make_glyphs(cfg):
    """Returns dict ch -> (final contours, advance) plus kerning data."""
    raw = {}  # ch -> dict(contours(body, sheared), full(contours), top, kind)

    def spec(ch):
        """Return (key, small, W, H, marks, kind)"""
        wf = cfg.wf

        def w_(key, default):
            if key in cfg.wabs:
                return cfg.wabs[key]
            return cfg.W * wf.get(key, default)

        if ch in UP:
            return (ch, False, w_(ch, 1.0), cfg.H, [], "L")
        if ch == "ı":
            return ("I", True, w_("I", 1.0) * cfg.sc_w, cfg.hsc, [], "L")
        if ch in LOW:
            if ch == "l":
                return ("l_lc", False, w_("l_lc", 0.6), cfg.H, [], "L")
            if ch in "ij":
                return (ch + "_lc", True, w_(ch.upper(), 1.0) * cfg.sc_w, cfg.hsc, [], "L")
            u = ch.upper()
            return (u, True, w_(u, 1.0) * cfg.sc_w, cfg.hsc, [], "L")
        if ch in DIG:
            return (ch, False, w_(ch, 0.9), cfg.H, [], "L")
        if ch in ACC_UP:
            b, m = ACC_UP[ch]
            k, s, W, H, _, kd = spec(b)
            return (k, s, W, H, [m], kd)
        if ch in ACC_LOW:
            b, m = ACC_LOW[ch]
            k, s, W, H, _, kd = spec(b)
            return (k, s, W, H, [m], kd)
        if ch == "Æ":
            return ("AE", False, w_("AE", 1.55), cfg.H, [], "L")
        if ch == "æ":
            return ("AE", True, w_("AE", 1.55) * cfg.sc_w, cfg.hsc, [], "L")
        if ch == "Ø":
            return ("Oslash", False, w_("O", 1.0), cfg.H, [], "L")
        if ch == "ø":
            return ("Oslash", True, w_("O", 1.0) * cfg.sc_w, cfg.hsc, [], "L")
        if ch == "ß":
            return ("sz", False, w_("sz", 0.95), cfg.H, [], "L")
        if ch in PUNCT:
            return (ch, False, cfg.pwabs[ch] if ch in cfg.pwabs else cfg.W * cfg.pwf.get(ch, 0.5), cfg.H, [], "P")
        raise KeyError(ch)

    all_chars = list(UP + LOW + DIG) + PUNCT + list(ACC_UP) + list(ACC_LOW) + K.SPECIAL + ["ı"]
    cache = {}
    for ch in all_chars:
        key, small, W, H, marks, kind = spec(ch)
        ck = (key, small, round(W, 2), round(H, 2))
        if ck in cache:
            body_path = cache[ck]
        else:
            Wi, Hi = W - 2 * cfg.inx, H - 2 * cfg.iny
            if key == "Oslash" and key not in cfg.skel:
                strokes = skel_get(cfg, "O", Wi, Hi) + cfg.oslash(Wi, Hi)
            else:
                strokes = skel_get(cfg, key, Wi, Hi)
            cuts = []
            for (typ, ux, uy) in cfg.cuts.get(key, []):
                cx = cfg.inx + ux * Wi
                cy = cfg.iny + uy * Hi
                if typ == "v":
                    cuts.append(rect_poly(cx, cy, cfg.gap, cfg.cut_len))
                else:
                    cuts.append(rect_poly(cx, cy, cfg.cut_len, cfg.gap))
            clip = [(-300, cfg.clip_lo), (W + 600, cfg.clip_lo), (W + 600, H + cfg.clip_hi), (-300, H + cfg.clip_hi)]
            if key in NOCLIP:
                clip = None
            body_path = render_strokes(strokes, (0, 0, W, H), cfg, cfg.pen, cuts=cuts, clip=clip)
            cache[ck] = body_path
        body = path_contours(body_path)
        # marks
        full_path = pathops.Path(body_path)
        for m in marks:
            top = H
            mw = max(cfg.mark_wmin, min(cfg.mark_wmax, W * cfg.mark_wfrac))
            mh = cfg.mark_h
            mcfg = cfg.mcfg
            if m == "cedilla":
                frame = (W / 2 - mw / 2 * 0.6, -cfg.cedilla_h, mw * 0.6, cfg.cedilla_h)
            else:
                frame = (W / 2 - mw / 2, top + cfg.mark_gap, mw, mh)
                if m == "ring":
                    frame = (W / 2 - mh * 0.55, top + cfg.mark_gap, mh * 1.1, mh * 1.1)
                if m == "diaer":
                    frame = (W / 2 - mw / 2, top + cfg.mark_gap, mw, mh)
            mp = render_strokes(getattr(cfg, 'marks', {}).get(m) or mark_strokes(m), frame, mcfg, cfg.mark_pen)
            full_path = pathops.op(full_path, mp, PathOp.UNION, fix_winding=True)
        full = path_contours(full_path)
        # special dotless-i helper has no marks. Shear
        body_s = sheared(body, cfg.slant) if cfg.slant else body
        full_s = sheared(full, cfg.slant) if cfg.slant else full
        raw[ch] = dict(body=body_s, full=full_s, kind=kind, H=H, small=small)

    # ---- spacing ---------------------------------------------------------
    NB = int(math.ceil((cfg.H + 60) / K.BAND))
    result = {}
    prof = {}
    for ch, r in raw.items():
        body, full = r["body"], r["full"]
        xs = [p[0] for c in body for p in c]
        ys = [p[1] for c in body for p in c]
        fxs = [p[0] for c in full for p in c]
        xmin, xmax = min(xs), max(xs)
        fxmin, fxmax = min(fxs), max(fxs)
        sbx = cfg.sb_adj.get(ch, (0, 0))
        if r["kind"] == "L":
            lo, hi = profile(body, cfg.H + 60)
            top = r["H"]
            nb = int(top // K.BAND)
            nb = max(nb, 1)
            dl = np.where(np.isfinite(lo[:nb]), lo[:nb] - xmin, cfg.dcap)
            dr = np.where(np.isfinite(hi[:nb]), xmax - hi[:nb], cfg.dcap)
            dl = np.minimum(dl, cfg.dcap)
            dr = np.minimum(dr, cfg.dcap)
            lsb = max(cfg.minsb, cfg.S0 - cfg.depth_k * dl.mean()) + sbx[0]
            rsb = max(cfg.minsb, cfg.S0 - cfg.depth_k * dr.mean()) + sbx[1]
        else:
            lsb = cfg.psb.get(ch, cfg.S0 * 0.85) + sbx[0]
            rsb = cfg.psb.get(ch, cfg.S0 * 0.85) + sbx[1]
        shift = lsb - xmin
        if fxmin + shift < cfg.minsb * 0.6:
            shift = cfg.minsb * 0.6 - fxmin
        adv = shift + max(xmax, fxmax) + rsb
        final = [[(x + shift, y) for x, y in c] for c in full]
        final = orient(final)
        bodyf = [[(x + shift, y) for x, y in c] for c in body]
        result[ch] = (final, int(round(adv)))
        prof[ch] = (bodyf, int(round(adv)))
    # space
    result[" "] = ([], cfg.space)

    # ---- kerning ---------------------------------------------------------
    P = {}
    for ch in KSET:
        contours, adv = prof[ch]
        lo, hi = profile(contours, cfg.H + 60)
        ys = [p[1] for c in contours for p in c]
        P[ch] = (lo, hi, adv, max(0, int(min(ys) // K.BAND)), int(max(ys) // K.BAND))

    def pair_stats(a, b):
        loa, hia, adva, ba0, ba1 = P[a]
        lob, hib, advb, bb0, bb1 = P[b]
        k0, k1 = max(ba0, bb0), min(ba1, bb1)
        if k1 < k0:
            return None
        g = []
        mg = []
        for k in range(k0, k1 + 1):
            ia = np.isfinite(hia[k])
            ib = np.isfinite(lob[k])
            da = (adva - hia[k]) if ia else cfg.kcap
            db = lob[k] if ib else cfg.kcap
            g.append(min(da, cfg.kcap) + min(db, cfg.kcap))
            if ia and ib:
                mg.append(da + db)
        return float(np.mean(g)), (min(mg) if mg else None)

    t0 = pair_stats("H", "H")[0]
    t1 = pair_stats("n", "n")[0]
    target = (t0 + t1) / 2
    pairs = {}
    for a in KSET:
        for b in KSET:
            st = pair_stats(a, b)
            if st is None:
                continue
            mean_gap, min_gap = st
            tgt = target
            if a in ".,:;" or b in ".,:;":
                tgt = target * 0.8
            kv = cfg.kern_t * (tgt - mean_gap)
            if kv > 0:
                kv = min(kv * 0.5, cfg.kern_pos)
            kv = max(kv, -cfg.kern_max)
            if min_gap is not None and min_gap + kv < cfg.clear:
                kv = cfg.clear - min_gap
            kv = int(round(kv / 2.0) * 2)
            if abs(kv) >= cfg.kern_min:
                pairs[(a, b)] = kv
    # classes (base letter -> all glyph names using that base)
    classes = {}
    for ch in KSET:
        classes[ch] = [glyph_name(ch)]
    for ch, (b, m) in list(ACC_UP.items()) + list(ACC_LOW.items()):
        if b == "ı":
            continue
        classes[b].append(glyph_name(ch))
    classes["i"].extend(glyph_name(c) for c, (b, m) in ACC_LOW.items() if b == "ı")
    classes["A"].append(glyph_name("Æ"))
    classes["a"].append(glyph_name("æ"))
    classes["O"].append(glyph_name("Ø"))
    classes["o"].append(glyph_name("ø"))
    return result, classes, pairs
