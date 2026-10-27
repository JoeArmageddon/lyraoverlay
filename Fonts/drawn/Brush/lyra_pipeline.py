"""Spacing, kerning and font assembly pipeline shared by the Lyra drawn fonts."""
import math
import numpy as np
from lyra_common import *
from print_skel import ACC


def char_class(ch):
    if ch in UPPER or ch in ACCENT_UP:
        return "up"
    if ch in LOWER or ch in ACCENT_LO:
        return "lo"
    if ch in DIGITS:
        return "dig"
    return "pun"


def prepare(conts):
    """polygons -> cleaned, oriented float polygons"""
    out = []
    for c in conts:
        c2 = clean_contour(c)
        if len(c2) >= 3 and abs(area(c2)) > 4:
            out.append(c2)
    return orient(out)


def base_of(ch):
    return ACC[ch][0] if ch in ACC else ch


def assemble(raw, cfg, fixed_adv=None):
    """raw: ch -> list of polygons (any x origin).  cfg keys:
       S, k : dicts class->(S,k) ; depth ; adj : ch->(dl,dr); space ; kern (bool) ; kern_strength ; mingap
       fixed: set of chars whose x positions are already final (script lowercase) -> uses fixed_adv[ch], no shift
    """
    glyphs, adv, polys, profs = {}, {}, {}, {}
    fixed = cfg.get("fixed", set())
    for ch, conts in raw.items():
        conts = prepare(conts)
        xs = [p[0] for c in conts for p in c]
        ys = [p[1] for c in conts for p in c]
        cl = char_class(ch)
        if ch in fixed:
            sh = 0.0
            lsb = min(xs)
            adv[ch] = fixed_adv[ch]
        else:
            prof0 = raster_profile(conts)
            if cl == "up" or cl == "dig":
                band = (0, 700)
            elif cl == "lo":
                band = (0, 500)
            else:
                band = (max(min(ys), -200), min(max(ys), 750))
                if band[1] - band[0] < 40:
                    band = (min(ys), max(ys) + 40)
            S, k = cfg["S"][cl], cfg["k"][cl]
            dl, dr = auto_sidebearings(prof0, band[0], band[1], S, k, cfg.get("depth", 90))
            adjl, adjr = cfg.get("adj", {}).get(ch, (0, 0))
            dl += adjl
            dr += adjr
            minb = cfg.get("min_sb", 6)
            dl, dr = max(dl, minb), max(dr, minb)
            sh = dl - min(xs)
            adv[ch] = dl + (max(xs) - min(xs)) + dr
        conts = [[(x + sh, y) for x, y in c] for c in conts]
        polys[ch] = conts
        profs[ch] = raster_profile(conts)
    # kerning
    kern_pairs = {}
    if cfg.get("kern", True):
        letters = [c for c in (UPPER + LOWER + DIGITS + ".,'’”-:?!‘“") if c in polys]
        refs = cfg["kern_refs"]
        def mean_ref(pairs):
            vals = []
            for a, b in pairs:
                mn, mg = pair_gap(profs[a], adv[a], profs[b], (0, 750))
                vals.append(mg)
            return sum(vals) / len(vals)
        norms = {k: mean_ref(v) for k, v in refs.items()}
        strength = cfg.get("kern_strength", 0.7)
        mingap = cfg.get("mingap", 30)
        skip_lo_lo = cfg.get("skip_lo_lo", False)
        for a in letters:
            for b in letters:
                ca, cb = char_class(a), char_class(b)
                if skip_lo_lo and ca == "lo" and cb == "lo":
                    continue
                key = {("up", "up"): "uu", ("up", "lo"): "ul", ("lo", "up"): "lu", ("lo", "lo"): "ll"}.get((ca, cb))
                if key is None:
                    key = "uu" if ca != "lo" else "ll"
                mn, mg = pair_gap(profs[a], adv[a], profs[b], (-200, 750))
                if mn is None:
                    continue
                norm = norms[key]
                k = strength * (norm - mg)
                if k > 0:
                    k = min(k, cfg.get("max_loosen", 20))
                else:
                    k = max(k, -cfg.get("max_tighten", 150))
                k = max(k, mingap - mn)
                k = int(round(k / 5.0) * 5)
                if abs(k) >= 8:
                    kern_pairs[(a, b)] = k
    # TrueType contours
    for ch, conts in polys.items():
        glyphs[gname(ch)] = [to_quad_contour(c) for c in conts]
    advn = {gname(ch): v for ch, v in adv.items()}
    advn[".notdef"] = 500
    advn["space"] = cfg.get("space", 260)
    return glyphs, advn, kern_pairs, polys


def class_kern_fea(kern_pairs):
    """Convert char pair kerning to class-based kerning (accented variants follow their base)."""
    members = {}
    for ch in ALL_CHARS:
        b = base_of(ch)
        members.setdefault(b, []).append(gname(ch))
    lines = []
    for b, names in members.items():
        lines.append("@K_%s = [%s];" % (gname(b), " ".join(names)))
    return lines


def kern_fea(kern_pairs, cmapchars):
    members = {}
    for ch in cmapchars:
        if ch == " ":
            continue
        members.setdefault(base_of(ch), []).append(gname(ch))
    used = set()
    for (a, b) in kern_pairs:
        used.add(a); used.add(b)
    out = ["languagesystem DFLT dflt;", "languagesystem latn dflt;"]
    for b in sorted(used):
        out.append("@K_%s = [%s];" % (gname(b), " ".join(members[b])))
    out.append("feature kern {")
    for (a, b), v in sorted(kern_pairs.items()):
        out.append("  pos @K_%s @K_%s %d;" % (gname(a), gname(b), v))
    out.append("} kern;")
    return "\n".join(out)
