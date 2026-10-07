#!/usr/bin/env python3
"""Draw "Rendered Steel - Modern" (style study direction 2M) in two sub-variants.

    python3 tools/icon_redesign/study/steel-modern/draw.py

writes  study/steel-modern/satin/<ref>.svg   (A · satin, gradient-id prefix "ra")
        study/steel-modern/crisp/<ref>.svg   (B · crisp, gradient-id prefix "rb")

The solids are drawn on the 2 : 1 dimetric lattice. Their silhouette corners get a soft fillet; a fillet
that an internal face edge runs into is split at its midpoint (de Casteljau, t = .5), so the two faces meet
on the curve with no notch and no overlap. Stdlib only.
"""
import colorsys
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
INK = '#D6D6D6'   # flat ink: arrows, sketch geometry (goes through _map like any ink)
SEC = '#8C8C8C'   # flat secondary ink: extension lines, radius, axis
ACC = '#6AA9ED'   # flat accent: sketch points, the dimension (goes to the accent bucket)


def grey(l, s=0.06, h=212):
    """A cool steel grey at HSL lightness l; s stays < .12 so _map treats it as neutral."""
    r, g, b = colorsys.hls_to_rgb(h / 360, l, s)
    return '#%02X%02X%02X' % tuple(round(c * 255) for c in (r, g, b))


def blue(l, s=0.66, h=211):
    r, g, b = colorsys.hls_to_rgb(h / 360, l, s)
    return '#%02X%02X%02X' % tuple(round(c * 255) for c in (r, g, b))


VARIANTS = {
    'satin': {
        'pfx': 'ra', 'r': 2.0, 'hair': False,
        # (start, end) lightness of each face; one key light upper left
        'steel': {'top': (.90, .79), 'lit': (.70, .58), 'shade': (.50, .41)},
        'acc': {'top': (.86, .76), 'lit': (.70, .58), 'shade': (.53, .44)},
        'acc_s': .50,
    },
    'crisp': {
        'pfx': 'rb', 'r': 0.6, 'hair': True,
        'steel': {'top': (.93, .89), 'lit': (.63, .60), 'shade': (.37, .35)},
        'acc': {'top': (.88, .84), 'lit': (.65, .62), 'shade': (.45, .42)},
        'acc_s': .54,
    },
}


def f(v):
    s = ('%.2f' % v).rstrip('0').rstrip('.')
    return '0' if s == '-0' else s


def pt(p):
    return '%s %s' % (f(p[0]), f(p[1]))


def add(a, b, k=1.0):
    return (a[0] + b[0] * k, a[1] + b[1] * k)


def unit(a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    d = math.hypot(dx, dy)
    return (dx / d, dy / d)


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


class Solid:
    """Faces of a polyhedral solid with a filleted silhouette."""

    def __init__(self, P, sil, radii):
        self.P = P
        self.sil = sil
        self.R = {}
        n = len(sil)
        for i, v in enumerate(sil):
            r = radii.get(v, 0)
            if r <= 0:
                continue
            V = P[v]
            pa, pb = sil[i - 1], sil[(i + 1) % n]
            p1 = add(V, unit(V, P[pa]), r)
            p2 = add(V, unit(V, P[pb]), r)
            mid = (.25 * p1[0] + .5 * V[0] + .25 * p2[0], .25 * p1[1] + .5 * V[1] + .25 * p2[1])
            self.R[v] = {pa: p1, pb: p2, 'mid': mid, 'V': V}

    def path(self, face):
        out = []
        n = len(face)
        for i, v in enumerate(face):
            u, w = face[i - 1], face[(i + 1) % n]
            if v not in self.R:
                out.append(('L', self.P[v]))
                continue
            c = self.R[v]
            V = c['V']
            if u in c and w in c:
                out += [('L', c[u]), ('Q', V, c[w])]
            elif u in c:
                out += [('L', c[u]), ('Q', lerp(c[u], V, .5), c['mid'])]
            elif w in c:
                out += [('L', c['mid']), ('Q', lerp(V, c[w], .5), c[w])]
            else:
                out.append(('L', c['mid']))
        s = ''
        for j, seg in enumerate(out):
            if seg[0] == 'L':
                s += ('M' if j == 0 else 'L') + pt(seg[1])
            else:
                s += 'Q' + pt(seg[1]) + ' ' + pt(seg[2])
        return s + 'Z'

    def outline(self):
        return self.path(self.sil)


class Icon:
    def __init__(self, var, key):
        self.v = VARIANTS[var]
        self.var = var
        self.id = '%s-%s' % (self.v['pfx'], key)
        self.defs = []
        self.body = []

    def grad(self, name, stops, x1=0, y1=0, x2=1, y2=1, user=False):
        gid = '%s-%s' % (self.id, name)
        if any('id="%s"' % gid in d for d in self.defs):
            return 'url(#%s)' % gid
        units = ' gradientUnits="userSpaceOnUse"' if user else ''
        st = ''.join('<stop offset="%s" stop-color="%s"%s/>' % (
            f(o), c, '' if op is None else ' stop-opacity="%s"' % f(op)) for o, c, op in stops)
        self.defs.append('<linearGradient id="%s"%s x1="%s" y1="%s" x2="%s" y2="%s">%s</linearGradient>' % (
            gid, units, f(x1), f(y1), f(x2), f(y2), st))
        return 'url(#%s)' % gid

    def mat(self, mat, face, **kw):
        """2-stop material gradient for a face of the steel or accent material."""
        a, b = self.v[mat][face]
        col = grey if mat == 'steel' else (lambda l: blue(l, self.v['acc_s']))
        if 'x1' not in kw:
            kw.update({'top': dict(x1=0, y1=0, x2=1, y2=1), 'lit': dict(x1=0, y1=0, x2=.4, y2=1),
                       'shade': dict(x1=0, y1=0, x2=.4, y2=1)}[face])
        return self.grad('%s%s' % (mat[0], face[0]), [(0, col(a), None), (1, col(b), None)], **kw)

    def hairline(self, d, x1, x2, op=(.8, .15)):
        """Crisp only: a hairline highlight on the lit edge (a 2-stop white gradient = material, not ink)."""
        g = self.grad('hl', [(0, '#FFFFFF', op[0]), (1, '#FFFFFF', op[1])], x1, 0, x2, 0, user=True)
        self.body.append('<path d="%s" stroke="%s" stroke-width=".6"/>' % (d, g))

    def add(self, s):
        self.body.append(s)

    def svg(self, lit=True):
        head = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 28 28" fill="none" stroke-linecap="round" '
                'stroke-linejoin="round"%s>' % (' data-lit="2"' if lit else ''))
        d = '<defs>%s</defs>\n' % '\n'.join(self.defs) if self.defs else ''
        return head + '\n' + d + '\n'.join(self.body) + '\n</svg>\n'


# ----------------------------------------------------------------------------------------- shared ink parts
def arrowhead(tip, direction, size=1.0):
    """The one arrowhead of the set: a slim filled triangle, 4.2 wide x 3.6 long, softened by a .5 round-join stroke."""
    ux, uy = direction
    d = math.hypot(ux, uy)
    ux, uy = ux / d, uy / d
    L, W = 3.4 * size, 2.0 * size
    base = (tip[0] - ux * L, tip[1] - uy * L)
    a = (base[0] - uy * W, base[1] + ux * W)
    b = (base[0] + uy * W, base[1] - ux * W)
    return 'M%sL%sL%sZ' % (pt(tip), pt(a), pt(b))


def ink_arrow(ic, a, b, col=INK, w=1.25):
    """Straight shaft a→b with the set's arrowhead at b."""
    u = unit(a, b)
    end = add(b, u, -3.0)
    ic.add('<path d="M%sL%s" stroke="%s" stroke-width="%s"/>' % (pt(a), pt(end), col, f(w)))
    ic.add('<path d="%s" fill="%s" stroke="%s" stroke-width=".5"/>' % (arrowhead(b, u), col, col))


# ----------------------------------------------------------------------------------------------- 3D icons
def extrude(var):
    ic = Icon(var, 'ex')
    r = ic.v['r']
    P = {'L': (7.5, 9.5), 'B': (16.75, 4.88), 'R': (26, 9.5), 'F': (16.75, 14.13),
         'Lb': (7.5, 20.5), 'Fb': (16.75, 25.13), 'Rb': (26, 20.5)}
    S = Solid(P, ['L', 'B', 'R', 'Rb', 'Fb', 'Lb'], {'L': r, 'B': r, 'R': r, 'Rb': r, 'Fb': r, 'Lb': r})
    ic.add('<path d="%s" fill="%s"/>' % (S.outline(), ic.mat('acc', 'shade')))
    ic.add('<path d="%s" fill="%s"/>' % (S.path(['L', 'F', 'Fb', 'Lb']), ic.mat('acc', 'lit')))
    ic.add('<path d="%s" fill="%s"/>' % (S.path(['F', 'R', 'Rb', 'Fb']), ic.mat('acc', 'shade')))
    ic.add('<path d="%s" fill="%s"/>' % (S.path(['L', 'B', 'R', 'F']), ic.mat('acc', 'top')))
    if ic.v['hair']:
        a, b = S.R['L']['mid'], S.R['R']['mid']
        ic.hairline('M%sL%sL%s' % (pt(a), pt(P['F']), pt(b)), a[0], b[0])
    ink_arrow(ic, (3.25, 24), (3.25, 3.5))
    return ic


def revolve(var):
    ic = Icon(var, 'rv')
    cx, cy, rx, ry, hgt = 14.5, 10.5, 10, 5, 10.5
    t1, t2 = 22, 108          # the removed wedge, front-right, in degrees (y down, 90 = front)

    def E(th, dy=0):
        a = math.radians(th)
        return (cx + rx * math.cos(a), cy + dy + ry * math.sin(a))
    C, Cb = (cx, cy), (cx, cy + hgt)
    arc = 'A%s %s 0 %d %d %s'
    # top face: material from t2 round through the back to t1 (large arc, sweep negative/positive per y-down)
    top = 'M%sL%s' % (pt(C), pt(E(t2))) + arc % (f(rx), f(ry), 1, 1, pt(E(t1 + 360))) + 'Z'
    # left curved side: t2 → 180 (front-left), visible
    side_l = ('M%s' % pt(E(t2)) + arc % (f(rx), f(ry), 0, 1, pt(E(180))) + 'L%s' % pt(E(180, hgt))
              + arc % (f(rx), f(ry), 0, 0, pt(E(t2, hgt))) + 'Z')
    # right sliver: 0 → t1
    side_r = ('M%s' % pt(E(0)) + arc % (f(rx), f(ry), 0, 1, pt(E(t1))) + 'L%s' % pt(E(t1, hgt))
              + arc % (f(rx), f(ry), 0, 0, pt(E(0, hgt))) + 'Z')
    cut_a = 'M%sL%sL%sL%sZ' % (pt(C), pt(E(t1)), pt(E(t1, hgt)), pt(Cb))   # faces front-left: lit
    cut_b = 'M%sL%sL%sL%sZ' % (pt(C), pt(E(t2)), pt(E(t2, hgt)), pt(Cb))   # faces right: shade
    ic.add('<path d="%s" fill="%s"/>' % (side_r, ic.mat('acc', 'shade', x1=0, y1=0, x2=0, y2=1)))
    ic.add('<path d="%s" fill="%s"/>' % (cut_b, ic.mat('acc', 'shade')))
    ic.add('<path d="%s" fill="%s"/>' % (cut_a, ic.mat('acc', 'lit')))
    # curved side: 2 stops, lit at the left, falling off toward the cut (no chrome band)
    g = ic.grad('cs', [(0, blue(ic.v['acc']['lit'][0] + .04, ic.v['acc_s']), None),
                       (1, blue(ic.v['acc']['shade'][0] + .02, ic.v['acc_s']), None)], cx - rx, 0, E(t2)[0], 0, user=True)
    ic.add('<path d="%s" fill="%s"/>' % (side_l, g))
    ic.add('<path d="%s" fill="%s"/>' % (top, ic.mat('acc', 'top')))
    if ic.v['hair']:
        a = E(178)
        ic.hairline('M%s' % pt(a) + arc % (f(rx), f(ry), 0, 0, pt(E(t2 + 2))), a[0], E(t2)[0], (.75, .2))
    # the sweep arrow, entering the removed wedge (no axis tick: at 28 pt it read as a burr, at 18 as noise)
    R2x, R2y = rx + 2.0, ry + 1.0
    a0, a1 = -70, 32

    def E2(th):
        a = math.radians(th)
        return (cx + R2x * math.cos(a), cy + R2y * math.sin(a))
    end = E2(a1)
    tang = (-R2x * math.sin(math.radians(a1)), R2y * math.cos(math.radians(a1)))
    stop = E2(a1 - 14)
    ic.add('<path d="M%s' % pt(E2(a0)) + arc % (f(R2x), f(R2y), 0, 1, pt(stop)) + '" stroke="%s" stroke-width="1.25"/>' % INK)
    ic.add('<path d="%s" fill="%s" stroke="%s" stroke-width=".5"/>' % (arrowhead(end, tang), INK, INK))
    return ic


def fillet(var):
    ic = Icon(var, 'fl')
    r = ic.v['r']
    k = .32
    P = {'L': (3, 11.5), 'B': (14, 6), 'R': (25, 11.5), 'F': (14, 17),
         'Lb': (3, 19.75), 'Fb': (14, 25.25), 'Rb': (25, 19.75)}
    P["F'"] = add(P['F'], (-11 * k, -5.5 * k))
    P["R'"] = add(P['R'], (-11 * k, -5.5 * k))
    P["F''"] = add(P['F'], (0, 11 * k))
    P["R''"] = add(P['R'], (0, 11 * k))
    S = Solid(P, ['L', 'B', "R'", "R''", 'Rb', 'Fb', 'Lb'], {'L': r, 'B': r, 'Rb': r, 'Fb': r, 'Lb': r})
    ic.add('<path d="%s" fill="%s"/>' % (S.outline(), ic.mat('steel', 'shade')))
    # left face, its top-right corner follows the fillet profile
    lf = S.path(['L', "F'", "F''", 'Fb', 'Lb'])
    lf = lf.replace('L%sL%s' % (pt(P["F'"]), pt(P["F''"])), 'L%sQ%s %s' % (pt(P["F'"]), pt(P['F']), pt(P["F''"])))
    ic.add('<path d="%s" fill="%s"/>' % (lf, ic.mat('steel', 'lit')))
    ic.add('<path d="%s" fill="%s"/>' % (S.path(["F''", "R''", 'Rb', 'Fb']), ic.mat('steel', 'shade')))
    ic.add('<path d="%s" fill="%s"/>' % (S.path(['L', 'B', "R'", "F'"]), ic.mat('steel', 'top')))
    # the fillet: a cylinder band, light along its upper edge, falling off toward the shade face (2 stops)
    band = 'M%sL%sQ%s %sL%sQ%s %sZ' % (pt(P["F'"]), pt(P["R'"]), pt(P['R']), pt(P["R''"]), pt(P["F''"]), pt(P['F']), pt(P["F'"]))
    a, b = ic.v['acc']['top'][0], ic.v['acc']['shade'][1]
    mid = lerp(P["F'"], P["R'"], .5)
    g = ic.grad('fb', [(0, blue(a, ic.v['acc_s']), None), (1, blue(b + .04, ic.v['acc_s']), None)],
                mid[0] - 1.2, mid[1] - 1.2, mid[0] + 2.4, mid[1] + 5.6, user=True)
    ic.add('<path d="%s" fill="%s"/>' % (band, g))
    if ic.v['hair']:
        a0 = S.R['L']['mid']
        ic.hairline('M%sL%s' % (pt(a0), pt(P["F'"])), a0[0], P["F'"][0])
    return ic


def hole(var):
    ic = Icon(var, 'ho')
    r = ic.v['r']
    P = {'L': (2.5, 12.75), 'B': (14, 7), 'R': (25.5, 12.75), 'F': (14, 18.5),
         'Lb': (2.5, 18), 'Fb': (14, 23.75), 'Rb': (25.5, 18)}
    S = Solid(P, ['L', 'B', 'R', 'Rb', 'Fb', 'Lb'], {'L': r, 'B': r, 'R': r, 'Rb': r, 'Fb': r, 'Lb': r})
    ic.add('<path d="%s" fill="%s"/>' % (S.outline(), ic.mat('steel', 'shade')))
    ic.add('<path d="%s" fill="%s"/>' % (S.path(['L', 'F', 'Fb', 'Lb']), ic.mat('steel', 'lit')))
    ic.add('<path d="%s" fill="%s"/>' % (S.path(['F', 'R', 'Rb', 'Fb']), ic.mat('steel', 'shade')))
    ic.add('<path d="%s" fill="%s"/>' % (S.path(['L', 'B', 'R', 'F']), ic.mat('steel', 'top')))
    cx, cy, hx, hy = 14, 12.75, 6.2, 3.1
    # the bore: inner wall in the accent material, dark under the back rim, lighter toward the front lip
    g = ic.grad('bo', [(0, blue(ic.v['acc']['shade'][1] - .06, ic.v['acc_s']), None),
                       (1, blue(ic.v['acc']['lit'][0], ic.v['acc_s']), None)], 0, cy - hy, 0, cy + hy, user=True)
    ic.add('<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="%s"/>' % (f(cx), f(cy), f(hx), f(hy), g))
    if ic.v['hair']:
        a = S.R['L']['mid']
        b = S.R['R']['mid']
        ic.hairline('M%sL%sL%s' % (pt(a), pt(P['F']), pt(b)), a[0], b[0])
    return ic


def plane(var):
    ic = Icon(var, 'pl')
    r = ic.v['r'] + .4
    P = {'a': (2.5, 21.5), 'b': (9.5, 6.5), 'c': (25.5, 6.5), 'd': (18.5, 21.5)}
    S = Solid(P, ['a', 'b', 'c', 'd'], {k: r for k in P})
    a, b = ic.v['acc']['top'][0] - .08, ic.v['acc']['lit'][1] - .07
    g = ic.grad('pf', [(0, blue(a, ic.v['acc_s']), None), (1, blue(b, ic.v['acc_s']), None)], 6, 6.5, 22, 21.5, user=True)
    ic.add('<path d="%s" fill="%s"/>' % (S.outline(), g))
    if ic.v['hair']:
        a, b = add(P['b'], unit(P['b'], P['c']), r), add(P['c'], unit(P['c'], P['b']), r)
        ic.hairline('M%sL%s' % (pt(a), pt(b)), a[0], b[0], (.85, .2))
    return ic


# ----------------------------------------------------------------------------------------------- 2D icons
def dot(ic, c, r, col):
    ic.add('<circle cx="%s" cy="%s" r="%s" fill="%s"/>' % (f(c[0]), f(c[1]), f(r), col))


def line(var):
    ic = Icon(var, 'ln')
    ic.add('<path d="M6 22L22 6" stroke="%s" stroke-width="1.5"/>' % INK)
    dot(ic, (6, 22), 1.9, INK)
    dot(ic, (22, 6), 2.4, ACC)
    return ic


def circle(var):
    ic = Icon(var, 'ci')
    ic.add('<circle cx="14" cy="14" r="10.5" stroke="%s" stroke-width="1.5"/>' % INK)
    ic.add('<path d="M14 14L21.42 6.58" stroke="%s" stroke-width="1.25"/>' % SEC)
    dot(ic, (14, 14), 2.4, ACC)
    return ic


def rect(var):
    ic = Icon(var, 're')
    ic.add('<path d="M5 21H23V7H5Z" stroke="%s" stroke-width="1.5"/>' % INK)
    dot(ic, (5, 21), 1.9, INK)
    dot(ic, (23, 7), 2.4, ACC)
    return ic


def coincident(var):
    ic = Icon(var, 'co')
    c = (13, 15.5)
    for far in ((2.5, 21.5), (23.5, 3.5)):
        near = add(c, unit(c, far), 6.0)
        ic.add('<path d="M%sL%s" stroke="%s" stroke-width="1.5"/>' % (pt(far), pt(near), INK))
    ic.add('<circle cx="13" cy="15.5" r="4.6" stroke="%s" stroke-width="1"/>' % ACC)
    dot(ic, c, 2.3, ACC)
    return ic


def dim(var):
    ic = Icon(var, 'dm')
    ic.add('<path d="M4.5 17.5V5.5M23.5 17.5V5.5" stroke="%s" stroke-width="1"/>' % SEC)
    ic.add('<path d="M9 10.5H19" stroke="%s" stroke-width="1.25"/>' % ACC)
    ic.add('<path d="%s" fill="%s" stroke="%s" stroke-width=".5"/>' % (arrowhead((5.2, 10.5), (-1, 0)), ACC, ACC))
    ic.add('<path d="%s" fill="%s" stroke="%s" stroke-width=".5"/>' % (arrowhead((22.8, 10.5), (1, 0)), ACC, ACC))
    ic.add('<path d="M4.5 21.5H23.5" stroke="%s" stroke-width="1.5"/>' % INK)
    dot(ic, (4.5, 21.5), 1.9, INK)
    dot(ic, (23.5, 21.5), 1.9, INK)
    return ic


DRAW = {'IC.line34': line, 'IC.circle34': circle, 'IC.rect34': rect, 'CN.coincident': coincident, 'CN.dim': dim,
        'CR.extrude': extrude, 'CR.revolve': revolve, 'MO.fillet': fillet, 'MO.hole': hole, 'WF.plane': plane}
SKETCH = {'IC.line34', 'IC.circle34', 'IC.rect34', 'CN.coincident', 'CN.dim'}


def main():
    for var in VARIANTS:
        d = os.path.join(HERE, var)
        os.makedirs(d, exist_ok=True)
        for ref, fn in DRAW.items():
            ic = fn(var)
            with open(os.path.join(d, ref + '.svg'), 'w', encoding='utf-8') as fh:
                fh.write(ic.svg(lit=ref not in SKETCH))
    print('wrote', ', '.join(VARIANTS))


if __name__ == '__main__':
    main()
