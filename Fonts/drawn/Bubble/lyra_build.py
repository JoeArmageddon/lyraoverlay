"""Font assembly, spacing, kerning, validation and specimen rendering (companion of lyra_kit)."""
import math, random, os, sys
import numpy as np
from pathops import Path
from fontTools.fontBuilder import FontBuilder
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.ttLib import TTFont
from fontTools.misc.timeTools import timestampFromString
from lyra_kit import *


class Style:
    # defaults; styles override
    name = 'X'
    CAP = 700; XH = 500; ASC = 800; DESC = -200
    w = 130; wl = 110
    dotr = 80; pgap = 60; dsp = 50
    straightq = False
    DASHY = 300; COLONY = 420; USC = 70
    iserif = 0.0
    abar = 0.30; f4bar = 0.36
    wscale = 1.0; wscale_l = 1.0; scw = 1.0; scwf = 1.0; SC = 546
    ov = 0
    hook = 0.24
    real_lower = True
    mode = 'round'; kmul = 1.0; nr = 40; mcap = 10000
    cap = LineCap.ROUND_CAP; join = LineJoin.ROUND_JOIN; miter = 4
    spike = None
    IDOT = 650; TTOP = 650
    mark_wf = 0.75; mark_gap = 30; mark_h = 60; mark_hw = 60; mark_dotr = 46
    sb = 40; sb_p = 50; opt = 0.30; optcap = 120; mind = 30
    sb_over = {}
    kern_clamp = (-150, 100)

    def dot_shape(self, x, y, r):
        return circle_path(x, y, r)


def spacing(st, paths, order):
    """Compute (dx, advance) per glyph; shifts are applied by caller."""
    info = {}
    for ch in order:
        p = paths[ch]
        xmin, ymin, xmax, ymax = p.bounds
        mn, mx = profile(flatten(p))
        top = min(max(ymax, 300), 700)
        rows = (YS >= 0) & (YS <= top)
        capd = st.optcap
        dl = np.where(np.isnan(mn[rows]), capd, np.clip(mn[rows] - xmin, 0, capd)).mean()
        dr_ = np.where(np.isnan(mx[rows]), capd, np.clip(xmax - mx[rows], 0, capd)).mean()
        isp = ch in PUNCT
        base = st.sb_p if isp else st.sb
        lsb = max(0.3 * base, base - st.opt * dl)
        rsb = max(0.3 * base, base - st.opt * dr_)
        if ch in st.sb_over:
            a, b = st.sb_over[ch]
            lsb += a; rsb += b
        info[ch] = (lsb, rsb)
    return info


def compute_kerning(st, paths, adv, order, log=print):
    prof = {}
    for ch in order:
        mn, mx = profile(flatten(paths[ch]))
        xmin, ymin, xmax, ymax = paths[ch].bounds
        prof[ch] = (mn, mx, xmin, xmax, ymax)
    m = int(st.mind // 10)
    # targets
    def meangap(a, b, kern=0):
        mnA, mxA, x0A, x1A, tA = prof[a]
        mnB, mxB, x0B, x1B, tB = prof[b]
        top = max(min(tA, tB, 700), 380)
        rows = (YS >= 0) & (YS <= top)
        capd = st.optcap
        dR = np.where(np.isnan(mxA[rows]), capd, np.clip(x1A - mxA[rows], 0, capd))
        dL = np.where(np.isnan(mnB[rows]), capd, np.clip(mnB[rows] - x0B, 0, capd))
        return (adv[a] - x1A) + x0B + dR.mean() + dL.mean() + kern

    t_cap = meangap('H', 'H'); t_lc = meangap('n', 'n')
    pairs = {}
    ids = [ch for ch in order]
    for a in ids:
        mnA, mxA, x0A, x1A, tA = prof[a]
        for b in ids:
            mnB, mxB, x0B, x1B, tB = prof[b]
            # clearance slack
            slack = 1e9
            for s in range(-m, m + 1):
                req = math.sqrt(max(st.mind ** 2 - (10 * s) ** 2, 0.0))
                if s >= 0:
                    r_a = mxA[:len(YS) - s] if s else mxA
                    l_b = mnB[s:]
                else:
                    r_a = mxA[-s:]
                    l_b = mnB[:len(YS) + s]
                g = adv[a] + l_b - r_a - req
                if np.isfinite(g).any():
                    slack = min(slack, np.nanmin(g))
            if slack > 1e8:
                slack = 0
            ua = a.isupper() or a.isdigit(); ub = b.isupper() or b.isdigit()
            if ua and ub:
                tgt = t_cap
            elif (a.islower() and b.islower()) or (a in PUNCT or b in PUNCT) and (a.islower() or b.islower()):
                tgt = t_lc
            else:
                tgt = 0.5 * (t_cap + t_lc)
            k_opt = (tgt - meangap(a, b)) * 0.8
            if a in PUNCT or b in PUNCT:
                k_opt = min(k_opt, 0) * 0.6 if (a in "-–—" or b in "-–—") else k_opt * 0.7
            k = max(k_opt, -slack)
            k = max(st.kern_clamp[0], min(st.kern_clamp[1], k))
            # never allow clearance violation
            if slack + k < 0:
                k = -slack
            if abs(k) >= 10:
                pairs[(a, b)] = int(round(k))
    return pairs


def build_font(st, finish, outdir, ttf_name, seed=7, log=print, cmap_extra=None):
    items = make_glyphs(st)
    order = [ch for ch in REQUIRED if ch != ' ']
    paths = {}
    for ch in order:
        rng = random.Random("%s-%s" % (seed, ord(ch)))
        p = render_items(items[ch], st, rng)
        p = finish(p, ch, rng, items[ch])
        paths[ch] = clean(p)
    # spacing (accented glyphs inherit base advance/shift)
    sp = spacing(st, paths, [c for c in order if c not in ACCENTS])
    for ch, (b, mk) in ACCENTS.items():
        sp[ch] = sp[b]
    # apply shifts, define advances
    adv = {}; final = {}
    for ch in order:
        lsb, rsb = sp[ch]
        base_ch = ACCENTS[ch][0] if ch in ACCENTS else ch
        bp = paths[base_ch] if base_ch in paths else paths[ch]
        bx0, _, bx1, _ = bp.bounds
        # accent glyphs align on the *base* geometry to keep identical placement
        dx = lsb - bx0
        adv[ch] = (bx1 - bx0) + lsb + rsb
        final[ch] = paths[ch].transform(1, 0, 0, 1, dx, 0)
    # accented glyphs that extend beyond base bbox may poke out: widen advance if needed
    for ch in order:
        x0, _, x1, _ = final[ch].bounds
        if x0 < 0:
            final[ch] = final[ch].transform(1, 0, 0, 1, -x0, 0)
            adv[ch] += -x0
            x1 -= x0
        if x1 > adv[ch]:
            adv[ch] = x1 + 6
    for ch in adv:
        adv[ch] = int(round(adv[ch]))
    adv[' '] = int(st.space)
    log("computing kerning ...")
    pairs = compute_kerning(st, final, adv, order, log)
    log("kern pairs:", len(pairs))

    # ---- build font
    gnames = {ch: glyph_name(ch) for ch in order}
    gorder = ['.notdef', 'space'] + [gnames[c] for c in order]
    cmap = {ord(c): gnames[c] for c in order}
    cmap[32] = 'space'; cmap[0xA0] = 'space'
    glyphs = {}
    metrics = {}
    # .notdef: rectangle frame
    nd = Path()
    nd.moveTo(60, 0); nd.lineTo(60, 700); nd.lineTo(500, 700); nd.lineTo(500, 0); nd.close()
    nd2 = Path()
    nd2.moveTo(120, 60); nd2.lineTo(440, 60); nd2.lineTo(440, 640); nd2.lineTo(120, 640); nd2.close()
    nd = difference(nd, nd2)
    glyphs['.notdef'] = path_to_glyph(clean(nd))
    metrics['.notdef'] = (560, 60)
    from fontTools.pens.ttGlyphPen import TTGlyphPen as _P
    glyphs['space'] = _P(None).glyph()
    metrics['space'] = (adv[' '], 0)
    for ch in order:
        g = path_to_glyph(final[ch])
        glyphs[gnames[ch]] = g
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(gorder)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyphs)
    glf = fb.font['glyf']
    for ch in order:
        gl = glf[gnames[ch]]
        gl.recalcBounds(glf)
        metrics[gnames[ch]] = (adv[ch], gl.xMin)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=800, descent=-200, lineGap=0)
    ver = "Version 1.000"
    fb.setupNameTable({
        "copyright": "Copyright 2026 The Lyra Project Authors. Reserved Font Name none.",
        "familyName": st.family, "styleName": "Regular",
        "uniqueFontIdentifier": "%s:1.000" % st.ps,
        "fullName": "%s Regular" % st.family, "version": ver, "psName": st.ps,
        "designer": "Lyra (procedurally drawn)",
        "description": st.description,
        "licenseDescription": "This Font Software is licensed under the SIL Open Font License, Version 1.1. "
                              "This license is available with a FAQ at: https://openfontlicense.org",
        "licenseInfoURL": "https://openfontlicense.org",
    })
    xs = [m[0] for g, m in metrics.items() if g != '.notdef']
    fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, sTypoLineGap=0, usWinAscent=900, usWinDescent=250,
                sxHeight=int(st.sxheight), sCapHeight=700, fsType=0, fsSelection=0x00C0, usWeightClass=400,
                usWidthClass=5, xAvgCharWidth=int(sum(xs) / len(xs)), ySubscriptXSize=600, ySubscriptYSize=600,
                ySuperscriptXSize=600, ySuperscriptYSize=600, ySubscriptYOffset=75, ySuperscriptYOffset=350,
                yStrikeoutSize=60, yStrikeoutPosition=300, achVendID="LYRA", version=4)
    fb.setupPost(keepGlyphNames=True, italicAngle=getattr(st, 'italic_angle', 0))
    from fontTools.ttLib import newTable
    gasp = newTable('gasp'); gasp.version = 1; gasp.gaspRange = {65535: 0x000F}
    fb.font['gasp'] = gasp
    ts = timestampFromString("Tue Oct 27 12:00:00 2026")
    fb.updateHead(created=ts, modified=ts, fontRevision=1.0, lowestRecPPEM=8)
    # kerning
    lines = ["feature kern {"]
    for (a, b), v in sorted(pairs.items()):
        lines.append("  pos %s %s %d;" % (gnames[a], gnames[b], v))
    lines.append("} kern;")
    addOpenTypeFeaturesFromString(fb.font, "\n".join(lines))
    os.makedirs(outdir, exist_ok=True)
    path = os.path.join(outdir, ttf_name)
    fb.save(path)
    return path, order, gnames


# ----------------------------------------------------------------- verification
def verify(path, st, log=print):
    f = TTFont(path)
    cmap = f.getBestCmap()
    gs = f.getGlyphSet()
    bad = []
    for ch in REQUIRED:
        if ord(ch) not in cmap:
            bad.append(('missing', ch)); continue
        if ch == ' ':
            continue
        g = f['glyf'][cmap[ord(ch)]]
        if g.numberOfContours == 0:
            bad.append(('empty', ch))
    log("verify: %d problems" % len(bad), bad[:10])
    os2 = f['OS/2']; hh = f['hhea']
    log("hhea", hh.ascent, hh.descent, hh.lineGap, "typo", os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap,
        "win", os2.usWinAscent, os2.usWinDescent, "fsSel", bin(os2.fsSelection), "upm", f['head'].unitsPerEm)
    # contour direction + overlap check
    import pathops
    from fontTools.pens.recordingPen import RecordingPen
    nbad = 0
    ymax = -1e9; ymin = 1e9
    for ch in REQUIRED:
        if ch == ' ':
            continue
        n = cmap[ord(ch)]
        g = f['glyf'][n]
        if g.numberOfContours > 0:
            ymax = max(ymax, g.yMax); ymin = min(ymin, g.yMin)
        pen = FlatPen()
        gs[n].draw(pen)
        tot = 0
        for pl in pen.polys:
            x = pl[:, 0]; y = pl[:, 1]
            a = 0.5 * np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y)
            tot += a
        if tot >= 0:
            nbad += 1; log("direction? ", ch, tot)
    log("glyph y-range", ymin, ymax, "orientation problems:", nbad)
    # overlap check: re-simplify and compare area
    for ch in REQUIRED:
        if ch == ' ':
            continue
        n = cmap[ord(ch)]
        p = Path()
        gs[n].draw(p.getPen())
        a0 = sum(abs(c.area) for c in p.contours)
        q = Path(p); q.simplify(fix_winding=True)
        a1 = sum(abs(c.area) for c in q.contours)
        if abs(a0 - a1) > 0.01 * max(a1, 1) + 50 or len(list(p.contours)) != len(list(q.contours)):
            log("possible overlap/self-intersection:", ch, round(a0), round(a1), len(list(p.contours)), len(list(q.contours)))
    return f


def read_kern(font):
    pairs = {}
    gpos = font['GPOS'].table
    for lk in gpos.LookupList.Lookup:
        for st_ in lk.SubTable:
            if st_.LookupType == 9:
                st_ = st_.ExtSubTable
            if st_.Format == 1:
                cov = st_.Coverage.glyphs
                for g1, ps in zip(cov, st_.PairSet):
                    for rec in ps.PairValueRecord:
                        v = rec.Value1.XAdvance if rec.Value1 and hasattr(rec.Value1, 'XAdvance') else 0
                        pairs[(g1, rec.SecondGlyph)] = v
    return pairs


# ----------------------------------------------------------------- specimen
def specimen(ttf_path, png_path, st, title):
    from PIL import Image, ImageDraw, ImageFont
    f = TTFont(ttf_path)
    cmap = f.getBestCmap()
    hmtx = f['hmtx']
    kern = read_kern(f)
    upm = 1000

    def draw_line(d, x, y, text, size, color):
        font = ImageFont.truetype(ttf_path, size)
        scale = size / upm
        px = x
        prev = None
        for ch in text:
            if ord(ch) not in cmap:
                continue
            gn = cmap[ord(ch)]
            if prev:
                px += kern.get((prev, gn), 0) * scale
            if ch != ' ':
                d.text((px, y), ch, font=font, fill=color, anchor='ls')
            px += hmtx[gn][0] * scale
            prev = gn
        return px

    def width_of(text, size):
        scale = size / upm; px = 0; prev = None
        for ch in text:
            if ord(ch) not in cmap:
                continue
            gn = cmap[ord(ch)]
            if prev:
                px += kern.get((prev, gn), 0) * scale
            px += hmtx[gn][0] * scale; prev = gn
        return px

    pad = 70
    Wd = 2600
    for _t in ["Quick zephyrs blow, vexing daft Jim. 0123456789", "Can't stop (won't stop) - 100% yours & mine?"]:
        Wd = max(Wd, int(width_of(_t, 96)) + 2 * pad + 20)
    bg = (14, 14, 22); fg = (240, 240, 250); dim = (140, 140, 165)
    lab = ImageFont.load_default()
    try:
        lab = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 22)
    except Exception:
        pass
    blocks = []
    blocks.append(('', "".join(UPPER), 110))
    blocks.append(('', "".join(LOWER), 110))
    blocks.append(('', "".join(DIGITS) + "  " + "".join(PUNCT[:13]), 110))
    blocks.append(('', "".join(PUNCT[13:]), 100))
    blocks.append(('', "".join(ACC_UP), 100))
    blocks.append(('', "".join(ACC_LO), 100))
    tests = ["Midnight in the city lights", "HOLD ME CLOSER, TONIGHT!",
             "Quick zephyrs blow, vexing daft Jim. 0123456789", "Can't stop (won't stop) - 100% yours & mine?"]
    # wrap long charset lines
    rows = []
    for _, text, size in blocks:
        words = text
        line = ""
        for ch in words:
            if width_of(line + ch, size) > Wd - 2 * pad:
                rows.append((line, size)); line = ch
            else:
                line += ch
        rows.append((line, size))
    h = pad
    layout = []
    layout.append(('label', title + "   -   full character set", h)); h += 30
    for text, size in rows:
        h += int(size * 1.0)
        layout.append(('text', text, size, h)); h += int(size * 0.28)
    h += 20
    for sz in (36, 96, 28):
        layout.append(('label', "%d pt" % sz, h)); h += 12
        for t in tests:
            while width_of(t, sz) > Wd - 2 * pad and sz > 30:
                break
            h += int(sz * 1.15)
            layout.append(('text', t, sz, h)); h += int(sz * 0.18)
        h += 30
    h += pad
    img = Image.new('RGB', (Wd, h), bg)
    d = ImageDraw.Draw(img)
    for item in layout:
        if item[0] == 'label':
            d.text((pad, item[2]), item[1], font=lab, fill=dim, anchor='ls' if False else 'la')
        else:
            draw_line(d, pad, item[3], item[1], item[2], fg)
    img.save(png_path)
    return png_path
