#!/usr/bin/env python3
"""Lyra Pixel Drawn - chunky 5x7 bitmap face on a strict 100-unit square grid.
Glyphs are bitmap strings; each set pixel becomes a 100x100 square, merged by boolean union.
Kerning is derived from the bitmaps (pairs may tuck by whole pixels, never touching).
Run:  /tmp/fontvenv/bin/python build_pixel.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pathops
import lyra_fontkit as K

HERE = os.path.dirname(os.path.abspath(__file__))
FAMILY, PS = 'Lyra Pixel Drawn', 'LyraPixelDrawn-Regular'
OUT = os.path.join(HERE, 'LyraPixelDrawn-Regular.ttf')
PX = 100

# glyph: (rows top->bottom, y of bottom row in pixels; 0 = baseline, negative = descender)
def g(rows, bottom=0): return (rows, bottom)
GL = {}
caps = {
 'A': ".###.|#...#|#...#|#####|#...#|#...#|#...#",
 'B': "####.|#...#|#...#|####.|#...#|#...#|####.",
 'C': ".###.|#...#|#....|#....|#....|#...#|.###.",
 'D': "####.|#...#|#...#|#...#|#...#|#...#|####.",
 'E': "#####|#....|#....|####.|#....|#....|#####",
 'F': "#####|#....|#....|####.|#....|#....|#....",
 'G': ".###.|#...#|#....|#.###|#...#|#...#|.####",
 'H': "#...#|#...#|#...#|#####|#...#|#...#|#...#",
 'I': "#####|..#..|..#..|..#..|..#..|..#..|#####",
 'J': "..###|...#.|...#.|...#.|...#.|#..#.|.##..",
 'K': "#...#|#..#.|#.#..|##...|#.#..|#..#.|#...#",
 'L': "#....|#....|#....|#....|#....|#....|#####",
 'M': "#...#|##.##|#.#.#|#.#.#|#...#|#...#|#...#",
 'N': "#...#|##..#|##..#|#.#.#|#..##|#..##|#...#",
 'O': ".###.|#...#|#...#|#...#|#...#|#...#|.###.",
 'P': "####.|#...#|#...#|####.|#....|#....|#....",
 'Q': ".###.|#...#|#...#|#...#|#.#.#|#..#.|.##.#",
 'R': "####.|#...#|#...#|####.|#.#..|#..#.|#...#",
 'S': ".####|#....|#....|.###.|....#|....#|####.",
 'T': "#####|..#..|..#..|..#..|..#..|..#..|..#..",
 'U': "#...#|#...#|#...#|#...#|#...#|#...#|.###.",
 'V': "#...#|#...#|#...#|#...#|.#.#.|.#.#.|..#..",
 'W': "#...#|#...#|#...#|#.#.#|#.#.#|##.##|#...#",
 'X': "#...#|#...#|.#.#.|..#..|.#.#.|#...#|#...#",
 'Y': "#...#|#...#|.#.#.|..#..|..#..|..#..|..#..",
 'Z': "#####|....#|...#.|..#..|.#...|#....|#####",
 '0': ".###.|#...#|#...#|#.#.#|#...#|#...#|.###.",
 '1': "..#..|.##..|..#..|..#..|..#..|..#..|.###.",
 '2': ".###.|#...#|....#|...#.|..#..|.#...|#####",
 '3': "####.|....#|....#|.###.|....#|....#|####.",
 '4': "...#.|..##.|.#.#.|#..#.|#####|...#.|...#.",
 '5': "#####|#....|####.|....#|....#|#...#|.###.",
 '6': ".###.|#....|#....|####.|#...#|#...#|.###.",
 '7': "#####|....#|...#.|..#..|.#...|.#...|.#...",
 '8': ".###.|#...#|#...#|.###.|#...#|#...#|.###.",
 '9': ".###.|#...#|#...#|.####|....#|....#|.###.",
 'Æ': "..#####|.#.#...|#..#...|######.|#..#...|#..#...|#..####",
 'Ø': ".###.|#..##|#.#.#|#.#.#|#.#.#|##..#|.###.",
 'ß': ".###.|#...#|#..#.|#.##.|#...#|#...#|#.##.",
 '!': "#|#|#|#|#|.|#",
 '?': ".###.|#...#|....#|...#.|..#..|.....|..#..",
 '¿': "..#..|.....|..#..|.#...|#...#|#...#|.###.",
 '¡': "#|.|#|#|#|#|#",
 '&': ".##..|#..#.|#.#..|.#...|#.#.#|#..#.|.##.#",
 '#': ".#.#.|.#.#.|#####|.#.#.|#####|.#.#.|.#.#.",
 '@': ".###.|#...#|#.###|#.#.#|#.###|#....|.####",
 '%': "##..#|##.#.|...#.|..#..|.#...|.#.##|#..##",
 '$': "..#..|.####|#.#..|.###.|..#.#|####.|..#..",
 '/': "....#|...#.|...#.|..#..|.#...|.#...|#....",
 '\\': "#....|.#...|.#...|..#..|...#.|...#.|....#",
}
for k, v in caps.items(): GL[k] = g(v.split('|'), 0)
low = {
 'a': ".###.|....#|.####|#...#|.####",
 'c': ".###.|#...#|#....|#...#|.###.",
 'e': ".###.|#...#|#####|#....|.###.",
 'm': "##.#.|#.#.#|#.#.#|#.#.#|#.#.#",
 'n': "####.|#...#|#...#|#...#|#...#",
 'o': ".###.|#...#|#...#|#...#|.###.",
 'r': "#.##|##..|#...|#...|#...",
 's': ".####|#....|.###.|....#|####.",
 'u': "#...#|#...#|#...#|#..##|.##.#",
 'v': "#...#|#...#|#...#|.#.#.|..#..",
 'w': "#...#|#...#|#.#.#|#.#.#|.#.#.",
 'x': "#...#|.#.#.|..#..|.#.#.|#...#",
 'z': "#####|...#.|..#..|.#...|#####",
 'ı': "##.|.#.|.#.|.#.|###",
 'æ': ".##.##.|...#..#|.######|#..#...|.##.##.",
 'ø': ".###.|#..##|#.#.#|##..#|.###.",
}
for k, v in low.items(): GL[k] = g(v.split('|'), 0)
asc = {
 'b': "#....|#....|####.|#...#|#...#|#...#|####.",
 'd': "....#|....#|.####|#...#|#...#|#...#|.####",
 'f': "..##.|.#...|###..|.#...|.#...|.#...|.#...",
 'h': "#....|#....|####.|#...#|#...#|#...#|#...#",
 'i': ".#.|...|##.|.#.|.#.|.#.|###",
 'k': "#....|#....|#..#.|#.#..|##...|#.#..|#..#.",
 'l': "##.|.#.|.#.|.#.|.#.|.#.|.##",
 't': ".#..|###.|.#..|.#..|.#..|.##.",
}
for k, v in asc.items(): GL[k] = g(v.split('|'), 0)
GL['t'] = g(GL['t'][0], 0)
desc = {
 'g': ".####|#...#|#...#|#...#|.####|....#|.###.",
 'j': "..#|...|..#|..#|..#|..#|..#|..#|##.",
 'p': "####.|#...#|#...#|#...#|####.|#....|#....",
 'q': ".####|#...#|#...#|#...#|.####|....#|....#",
 'y': "#...#|#...#|#...#|#...#|.####|....#|.###.",
}
for k, v in desc.items():
    rows = v.split('|')
    GL[k] = g(rows, -2) if k != 'j' else g(rows, -2)
# j has dot row + gap: rows are 9 -> bottom -2 puts top at y6 ... fix: 5 stem rows+dot+gap+2 desc = 9 rows
punc = {
 '.': (["#"], 0), ',': (["#", "#"], -1), "'": (["#", "#"], 5), '"': (["#.#", "#.#"], 5),
 '’': ([".#", ".#", "#."], 4), '‘': ([".#", "#.", "#."], 4),
 '“': ([".#.#", "#.#.", "#.#."], 4), '”': ([".#.#", ".#.#", "#.#."], 4),
 '-': (["###"], 3), '–': (["#####"], 3), '—': (["#######"], 3),
 ':': (["#", ".", ".", ".", "#"], 0), ';': (["#", ".", ".", ".", "#", "#"], -1),
 '(': (["..#", ".#.", ".#.", "#..", "#..", "#..", ".#.", ".#.", "..#"], -1),
 ')': (["#..", ".#.", ".#.", "..#", "..#", "..#", ".#.", ".#.", "#.."], -1),
 '[': (["###", "#..", "#..", "#..", "#..", "#..", "#..", "#..", "###"], -1),
 ']': (["###", "..#", "..#", "..#", "..#", "..#", "..#", "..#", "###"], -1),
 '{': (["..##", ".#..", ".#..", ".#..", "#...", ".#..", ".#..", ".#..", "..##"], -1),
 '}': (["##..", "..#.", "..#.", "..#.", "...#", "..#.", "..#.", "..#.", "##.."], -1),
 '|': (["#"] * 9, -1),
 '+': (["..#..", "..#..", "#####", "..#..", "..#.."], 1),
 '=': (["#####", ".....", "#####"], 2),
 '*': (["#.#.#", ".###.", "#####", ".###.", "#.#.#"], 2),
 '…': (["#.#.#"], 0), '_': (["######"], -1),
 '~': ([".##.#", "#.##."], 3), '^': (["..#..", ".#.#.", "#...#"], 4),
 '<': (["..#", ".#.", "#..", ".#.", "..#"], 1), '>': (["#..", ".#.", "..#", ".#.", "#.."], 1),
 '`': (["#.", ".#"], 5),
}
GL.update(punc)
# dotted zero vs slashed O-stroke: dotted zero
GL['0'] = g([".###.", "#...#", "#...#", "#.#.#", "#...#", "#...#", ".###."], 0)

MARKS = {  # rows top->bottom
 'acute': ["..#", ".#."], 'grave': ["#..", ".#."], 'circ': [".#.", "#.#"],
 'tilde': [".##.#", "#.##."], 'diaer': ["#.#"], 'ring': ["###", "#.#"],
}
def norm(rows):
    w = max(len(r) for r in rows)
    return [r.ljust(w, '.') for r in rows]

def pixels(ch):
    rows, bottom = GL[ch]; rows = norm(rows); n = len(rows)
    s = set()
    for i, r in enumerate(rows):
        y = bottom + (n - 1 - i)
        for x, c in enumerate(r):
            if c == '#': s.add((x, y))
    return s, len(rows[0])

# accented glyph pixel sets
for ch, (base, kind) in K.ACCENT_SPEC.items():
    s, w = pixels(base)
    upper = base.isupper()
    if kind == 'cedilla':
        cx = w // 2
        s |= {(cx, -1), (cx - 1 if w > 3 else cx, -2)}
        GL[ch] = ('PIX', s, w); continue
    m = MARKS[kind]; mw = len(m[0]); off = (w - mw) // 2
    y_low = 8 if upper else 6          # lowest mark row (gap row below it)
    for i, r in enumerate(m):
        y = y_low + (len(m) - 1 - i)
        for x, c in enumerate(r):
            if c == '#': s.add((off + x, y))
    GL[ch] = ('PIX', s, w)

def get_pix(ch):
    v = GL[ch]
    if v[0] == 'PIX': return v[1], v[2]
    return pixels(ch)

def pix_path(s):
    # build per-row runs, then union
    p = pathops.Path()
    for (x, y) in sorted(s):
        p.moveTo(x * PX, y * PX); p.lineTo(x * PX, (y + 1) * PX)
        p.lineTo((x + 1) * PX, (y + 1) * PX); p.lineTo((x + 1) * PX, y * PX); p.close()
    p.simplify(fix_winding=True, keep_starting_points=False)
    return p

def kern_px(a, b, limit=2):
    sa, wa = get_pix(a); sb, wb = get_pix(b)
    best = 0
    for k in range(1, limit + 1):
        dx = wa + 1 - k
        ok = True
        for (x, y) in sb:
            X = x + dx
            for ox in (-2, -1, 0, 1, 2):
                for oy in (-2, -1, 0, 1, 2):
                    if (X + ox, y + oy) in sa: ok = False; break
                if not ok: break
            if not ok: break
        if ok: best = k
        else: break
    return best

def main():
    glyphs, cmap = {}, {}
    notdef = pix_path({(x, y) for x in range(5) for y in range(7) if x in (0, 4) or y in (0, 6)})
    glyphs['.notdef'] = (notdef, 600)
    chars = [c for c in K.BASIC + list(K.PUNCT_EXTRA) + list(K.ACCENT_SPEC) + list("ÆØæøßı")]
    seen = []
    for ch in chars:
        if ch in seen: continue
        seen.append(ch)
        gn = K.gname(ch)
        if ch == ' ':
            glyphs[gn] = (pathops.Path(), 400); cmap[32] = gn; continue
        s, w = get_pix(ch)
        glyphs[gn] = (pix_path(s), (w + 1) * PX); cmap[ord(ch)] = gn
    cmap[0xA0] = 'space'
    order = ['.notdef'] + [n for n in glyphs if n != '.notdef']
    # kerning
    base_chars = [c for c in K.BASIC if c != ' '] + list('‘’“”–—…¡¿')
    kb = {}
    for a in base_chars:
        for b in base_chars:
            if a.islower() and b.islower(): continue
            if a.isdigit() and b.isdigit(): continue
            if a in '.,:;\'"‘’“”…' and b in '.,:;\'"‘’“”…': continue
            if a in "'\"‘’“”" or b in "'\"‘’“”": continue
            k = kern_px(a, b)
            if k: kb[(a, b)] = -k * PX
    rev = {}
    for ch, (base, kind) in K.ACCENT_SPEC.items(): rev.setdefault(base, []).append(ch)
    rev['ı'] = []
    def var(c):
        v = [c] + rev.get(c, [])
        if c == 'i': v += rev.get('ı', []) + ['ı'] if False else []
        return v
    gk = {}
    for (a, b), v in kb.items():
        for aa in var(a):
            for bb in var(b):
                gk[(K.gname(aa), K.gname(bb))] = v
    meta = {'description': 'Original chunky 5x7 pixel face on a 100-unit grid.'}
    K.build_ttf(OUT, FAMILY, PS, glyphs, cmap, meta, kern_pairs=gk, order=order)
    print('built', OUT, 'kern', len(gk))
    size = K.make_specimen(OUT, os.path.join(HERE, 'specimen.png'), 'Lyra Pixel Drawn - Regular')
    problems, info = K.verify(OUT)
    print('specimen', size, 'problems', problems); print(info)

if __name__ == '__main__':
    main()
