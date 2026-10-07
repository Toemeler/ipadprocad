#!/usr/bin/env python3
"""Build docs/palette_proposals.html: candidate replacements for the default
Ember / Chalk palettes, each shown in the same faithful app mock (rail with the
real icons recoloured through icon_theme.dart's _map, floating model browser,
bottom tab bar, view cube, triad, shaded part, and a sketch state), with swatch
tables, WCAG contrast results and full Dart Palette literals.

Stdlib only.

    python3 tools/palette_proposals/build.py ICONS_JSON [OUT_HTML]

ICONS_JSON  output of tools/ribbon_icon_mockup/dump.dart:
            {"maps": {MAP: {key: svg}}, "singles": {name: svg}}
OUT_HTML    default: docs/palette_proposals.html

The baseline palettes (kEmber, kChalk), the token list and each token's
comment are parsed out of frontend/lib/theme.dart, so the baseline is always
what the app ships. The proposals below are CORE values per direction; every
other token is derived by derive() with the rules written next to it.
"""
import colorsys
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
THEME = os.path.join(ROOT, 'frontend', 'lib', 'theme.dart')
DEFAULT_OUT = os.path.join(ROOT, 'docs', 'palette_proposals.html')

KMIN_TEXT = 4.5
KMIN_GRAPHIC = 3.0

# ---------------------------------------------------------------- colour math


def rgb(h):
    h = h.lstrip('#')
    if len(h) == 8:
        h = h[2:]
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def alpha_of(h):
    h = h.lstrip('#')
    return int(h[:2], 16) / 255 if len(h) == 8 else 1.0


def hx(r, g, b):
    return '%02X%02X%02X' % tuple(max(0, min(255, round(v))) for v in (r, g, b))


def mix(a, b, t):
    """a -> b by t, opaque."""
    A, B = rgb(a), rgb(b)
    return hx(*[A[i] + (B[i] - A[i]) * t for i in range(3)])


def with_alpha(h, a):
    return '%02X%s' % (a, hx(*rgb(h)))


def blend(fg, bg):
    """alpha-composite an AARRGGBB over an opaque colour."""
    a = alpha_of(fg)
    F, B = rgb(fg), rgb(bg)
    return hx(*[F[i] * a + B[i] * (1 - a) for i in range(3)])


def lum(h):
    def ch(c):
        c /= 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = rgb(h)
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def contrast(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def lstar(h):
    y = lum(h)
    return 116 * (y ** (1 / 3) if y > 216 / 24389 else (24389 / 27 * y + 16) / 116) - 16


# OKLCH, for the Carbon Pro set: one lightness / chroma per role family is
# what makes semantic colours read as a system rather than as defaults.
def _lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _gam(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def _oklab_to_rgb(L, a, b):
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = l_ ** 3, m_ ** 3, s_ ** 3
    return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)


def oklch(L, C, h):
    """OKLCH -> RRGGBB, chroma bisected down until it is inside sRGB."""
    import math
    ca, sa = math.cos(math.radians(h)), math.sin(math.radians(h))

    def inside(c):
        return all(-1e-5 <= v <= 1 + 1e-5 for v in _oklab_to_rgb(L, c * ca, c * sa))
    if not inside(C):
        lo, hi = 0.0, C
        for _ in range(28):
            mid = (lo + hi) / 2
            lo, hi = (mid, hi) if inside(mid) else (lo, mid)
        C = lo
    return hx(*[_gam(max(0.0, min(1.0, v))) * 255 for v in _oklab_to_rgb(L, C * ca, C * sa)])


def to_oklch(h):
    import math
    R, G, B = [_lin(c / 255) for c in rgb(h)]
    l = (0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B) ** (1 / 3)
    m = (0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B) ** (1 / 3)
    s = (0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B) ** (1 / 3)
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return L, math.hypot(a, b), math.degrees(math.atan2(b, a)) % 360


# Flutter's HSLColor, ported 1:1 (same as the JS port in the page).
def hsl_from(h):
    R, G, B = [c / 255 for c in rgb(h)]
    mx, mn = max(R, G, B), min(R, G, B)
    d = mx - mn
    if mx == 0 or d == 0:
        hue = 0.0
    elif mx == R:
        hue = 60 * (((G - B) / d) % 6)
    elif mx == G:
        hue = 60 * (((B - R) / d) + 2)
    else:
        hue = 60 * (((R - G) / d) + 4)
    l = (mx + mn) / 2
    s = 0.0 if l == 1 else max(0.0, min(1.0, d / (1 - abs(2 * l - 1)) if d else 0.0))
    return hue, s, l


def hsl_to(h, s, l):
    c = (1 - abs(2 * l - 1)) * s
    x = c * (1 - abs(((h / 60) % 2) - 1))
    m = l - c / 2
    if h < 60:
        r, g, b = c, x, 0
    elif h < 120:
        r, g, b = x, c, 0
    elif h < 180:
        r, g, b = 0, c, x
    elif h < 240:
        r, g, b = 0, x, c
    elif h < 300:
        r, g, b = x, 0, c
    else:
        r, g, b = c, 0, x
    return hx((r + m) * 255, (g + m) * 255, (b + m) * 255)


def clamp(x, a, b):
    return max(a, min(b, x))


def map_icon(src, p):
    """icon_theme.dart _map for palette p (a full token dict)."""
    hue, s, l = hsl_from(src)
    light = not p['_dark']
    if s < 0.12:
        ll = 1 - l if light else l
        ih = hsl_from(p['ink'])[0]
        return hsl_to(ih, 0.04, clamp(ll, 0.12, 0.92))
    if 175 <= hue < 265:
        t = p['rawAccent']
    elif 75 <= hue < 175:
        t = p['ok']
    elif 18 <= hue < 75:
        t = p['projRef']
    else:
        t = p['err']
    th, ts, _ = hsl_from(t)
    ll = clamp(0.16 + l * 0.30, 0.16, 0.46) if light else clamp(l, 0.32, 0.82)
    return hsl_to(th, clamp(ts * 0.85 + s * 0.15, 0.25, 0.95), ll)


# ------------------------------------------------------- baseline from theme


def parse_theme():
    src = open(THEME, encoding='utf-8').read()
    cls = re.search(r'class Palette \{(.*?)const Palette\(\{', src, re.S).group(1)
    fields, comments = [], {}
    for m in re.finditer(r'^\s*final Color (\w+);(?:\s*//\s*(.*))?$', cls, re.M):
        fields.append(m.group(1))
        if m.group(2):
            comments[m.group(1)] = m.group(2).strip()
    # doc comments directly above a field (field / floor / errFill / aiStage)
    for m in re.finditer(r'((?:\s*///[^\n]*\n)+)\s*final Color (\w+);', cls):
        if m.group(2) not in comments:
            first = re.sub(r'^\s*///\s*', '', m.group(1).strip().split('\n')[0])
            comments[m.group(2)] = first
    pals = {}
    for name in ('kEmber', 'kChalk'):
        body = re.search(r'const Palette %s = Palette\((.*?)\n\);' % name, src, re.S).group(1)
        vals = dict(re.findall(r'(\w+): Color\(0x([0-9A-Fa-f]{8})\)', body))
        missing = [f for f in fields if f not in vals]
        if missing:
            sys.exit('%s: no value for %s' % (name, missing))
        pals[name] = {k: vals[k].upper() for k in fields}
        pals[name]['_dark'] = 'Brightness.dark' in body
        pals[name]['_name'] = re.search(r"name: '([^']+)'", body).group(1)
    accents = re.findall(r'^\s*(\w+)\(Color\(0x([0-9A-Fa-f]{8})\), Color\(0x([0-9A-Fa-f]{8})\)\)',
                         src, re.M)
    return fields, comments, pals, accents


# --------------------------------------------------------------- proposals
#
# CORE values per direction and scheme. Everything else is derive()d.
# Keys: bg panel fly field text dim sep panelSep accent hover viewport floor
#       ok okText err errFill errText projRef warn warnText chipBg chipStrong
#       disabled rawGrey constr snapOk grid axis dofFull dofUnder refDim
#       dofArrow ctrl dimLine dimText solid solidEdge previewFill okSolid
#       okSolidBright axisX axisY axisZ cube=(face, top, dim, edge, text)

DIRECTIONS = [
    {
        'id': 'graphite',
        'name': 'Graphite',
        'tag': 'Cool neutral graphite, Apple blue',
        'refs': 'Xcode, Final Cut Pro, Logic Pro, macOS/iPadOS system chrome',
        'why': [
            'Greys carry a barely-there blue cast (hue 220-230, saturation 3-6%): neutral next to a steel part, '
            'never brown, never green. This is the grey family of Apple\'s own pro apps.',
            'The accent is the system blue, so the Flutter chrome finally agrees with the UIKit glass '
            '(GlassBrowser and GlassToolBar already hard-code .systemBlue selection washes and the root cube is #007AFF). '
            'On the iPad this option removes a whole class of "two apps in one window" mismatches.',
            'Status and annotation colours are the Apple semantic set (green, red, orange), so an icon '
            'redesign can lean on SF Symbols conventions without fighting the palette.',
            'Elevation is luminance-only and evenly stepped: field < bg < viewport < panel < fly (raised popovers, '
            'like macOS dark), so a floating browser or dialog lifts off the canvas without needing a heavy shadow.',
        ],
        'dark': dict(
            bg='1B1C1F', panel='252629', fly='2E2F33', field='161719', text='ECEDF0', dim='9DA0A7',
            sep='0D0E10', panelSep='36383D', accent='4A9BFF', hover='8DC1FF', viewport='1E1F22', floor='2A2C30',
            ok='32C35A', okText='5FD37E', err='FF5A52', errFill='C9302A', errText='FF9C95',
            projRef='F5A524', warn='F5A524', warnText='FFC266', chipBg='1E3352', chipStrong='0A68D4',
            disabled='7D8088', rawGrey='81858D', constr='8FA2B6', snapOk='5FD37E', grid='2A2C30', axis='3A3D43',
            dofFull='FFFFFF', dofUnder='B3A4FF', refDim='5A5D64', dofArrow='F2CF5B', ctrl='E9C04E',
            dimLine='A6ACB5', dimText='E6E9EE', solid='A6AAB0', solidEdge='141518', previewFill='F0A050',
            okSolid='32C35A', okSolidBright='8EE6A6', axisX='FF5F57', axisY='32C35A', axisZ='4C8DFF',
            cube=('D9DBDF', 'F4F5F7', 'B8BBC1', '8B8F96', '3A3D43')),
        'light': dict(
            bg='E8E9EC', panel='F5F5F7', fly='FFFFFF', field='ECEDF0', text='1D1D1F', dim='5D6068',
            sep='CDD0D5', panelSep='E0E1E5', accent='0064D1', hover='5292E0', viewport='F7F8FA', floor='E3E5E9',
            ok='1E8A3C', okText='17732F', err='D21F2B', errFill='C51F2A', errText='A8121D',
            projRef='AD5A00', warn='AD5A00', warnText='8A4600', chipBg='DCE9FC', chipStrong='0064D1',
            disabled='868A92', rawGrey='868A92', constr='6D8197', snapOk='1E8A3C', grid='E4E6EA', axis='C9CDD3',
            dofFull='111214', dofUnder='5B45D6', refDim='A9ADB4', dofArrow='8A6A00', ctrl='8A5F00',
            dimLine='687080', dimText='2E333A', solid='BEC2C8', solidEdge='4A4E55', previewFill='C76A16',
            okSolid='2E9A48', okSolidBright='1E7A36', axisX='D2312A', axisY='1E8A3C', axisZ='1F63C9',
            cube=('FFFFFF', 'FFFFFF', 'E8E9EC', 'B9BCC2', '3A3D43')),
    },
    {
        'id': 'slate',
        'name': 'Slate',
        'tag': 'Blue-grey slate, Autodesk blue',
        'refs': 'Autodesk Fusion 2025 dark UI, Inventor 2025, Onshape',
        'why': [
            'A visibly blue-grey family (hue ~212, saturation 10-15%): the most "engineering software" of the four '
            'and the one Inventor/Fusion users will recognise instantly.',
            'The viewport is LIGHTER than the chrome on dark (#2A313A under #252B33 panels), the way Fusion\'s and '
            'Inventor\'s default canvases sit a step above their toolbars. Grey parts and dark edges read with more '
            'separation than on a near-black ground.',
            'The accent is a cyan-leaning Autodesk blue (#34A8E6 / #006EAF) and the annotation colour is Autodesk '
            'amber, so selection and reference geometry are as far apart in hue as they can be.',
            'Cost: the cast is strong enough that a user accent override such as amber or magenta looks less at '
            'home than on a true neutral, and the light variant reads cooler than most iPad apps.',
        ],
        'dark': dict(
            bg='1C2127', panel='252B33', fly='2E353F', field='171B20', text='E7ECF2', dim='9AA5B3',
            sep='0F1317', panelSep='343C47', accent='3AABE8', hover='8ACFF2', viewport='2A313A', floor='36404B',
            ok='43C17A', okText='6DD69A', err='F46A63', errFill='C4352F', errText='F7A19C',
            projRef='F5A623', warn='F5A623', warnText='FFC870', chipBg='173D55', chipStrong='0B76B6',
            disabled='7C8692', rawGrey='8E99A7', constr='93B3CA', snapOk='6DD69A', grid='323A44', axis='46505C',
            dofFull='FFFFFF', dofUnder='BBACFF', refDim='626C78', dofArrow='F2D060', ctrl='EBC24F',
            dimLine='AEBAC7', dimText='EAF0F6', solid='ADB3BA', solidEdge='151A20', previewFill='F5A54A',
            okSolid='43C17A', okSolidBright='97E8B6', axisX='F46A63', axisY='43C17A', axisZ='5AA2FF',
            cube=('DCE1E7', 'F5F7FA', 'BCC4CE', '8D97A3', '38414C')),
        'light': dict(
            bg='E1E5EA', panel='F0F3F6', fly='FFFFFF', field='E7EBF0', text='18202A', dim='525E6D',
            sep='C3CBD5', panelSep='D8DEE5', accent='0067A6', hover='3A8CC2', viewport='E9EDF2', floor='D4DAE2',
            ok='1A7F45', okText='166B3A', err='C4302A', errFill='C0302A', errText='A02420',
            projRef='9E5600', warn='9E5600', warnText='7E4500', chipBg='D3E8F5', chipStrong='0067A6',
            disabled='7E8894', rawGrey='7A8592', constr='5D7A92', snapOk='1A7F45', grid='D6DCE3', axis='BCC5CF',
            dofFull='0E141B', dofUnder='5A47CF', refDim='9EA8B4', dofArrow='7A5E00', ctrl='7A5400',
            dimLine='5A6878', dimText='26303C', solid='B8BEC6', solidEdge='47505B', previewFill='C26A16',
            okSolid='25934F', okSolidBright='1A733D', axisX='C4302A', axisY='1A7F45', axisZ='1F5FBF',
            cube=('FFFFFF', 'FFFFFF', 'E3E8ED', 'B5BEC8', '38414C')),
    },
    {
        'id': 'carbon',
        'name': 'Carbon',
        'tag': 'True-neutral near-black, one restrained indigo',
        'refs': 'Linear, Figma (UI3), Blender 4.x, Raycast',
        'why': [
            'Zero chroma in every surface (R=G=B within 1-3 units). The quietest possible frame: the only colour on '
            'screen is the model, the selection and the annotation.',
            'Darker than the others (bg L* 5, viewport L* 7), with the elevation ladder carried by small, even '
            'luminance steps the way Linear and Figma do it; hairlines do the rest.',
            'One restrained indigo accent (#7D83FF / #4C52D9). It is the most "software-brand" of the options and '
            'clearly distinct from Apple/Autodesk blue. Because indigo sits on the old violet, under-constrained '
            'geometry moves to orchid (#E58AE5 / #A33AA3) so the two never collide.',
            'Cost: the near-black canvas is dramatic and needs care on the iPad\'s glass (UIKit materials over '
            'pure neutral black look flat), and indigo icons are a bigger departure for an Inventor audience.',
        ],
        'dark': dict(
            bg='101011', panel='19191B', fly='222225', field='0B0B0C', text='EDEDEF', dim='909097',
            sep='050506', panelSep='2B2B2F', accent='7B8CEB', hover='B3BDF5', viewport='141415', floor='222225',
            ok='3FCF8E', okText='5EDBA2', err='F26464', errFill='C53B3B', errText='F8A3A3',
            projRef='F2A04F', warn='F2A04F', warnText='FFC48A', chipBg='232A4A', chipStrong='4F5DD0',
            disabled='727279', rawGrey='7C7C84', constr='8E9AAE', snapOk='5EDBA2', grid='212124', axis='303034',
            dofFull='FFFFFF', dofUnder='E58AE5', refDim='505056', dofArrow='F0D060', ctrl='E7BE4A',
            dimLine='A0A0A8', dimText='E8E8EC', solid='A8A8AC', solidEdge='0E0E10', previewFill='F2A04F',
            okSolid='3FCF8E', okSolidBright='9CEBC4', axisX='F26464', axisY='3FCF8E', axisZ='5C9DFF',
            cube=('DADADD', 'F4F4F6', 'B9B9BE', '8A8A90', '3A3A3F')),
        'light': dict(
            bg='F2F2F3', panel='FAFAFB', fly='FFFFFF', field='EFEFF1', text='18181B', dim='5F5F67',
            sep='DADADE', panelSep='E8E8EB', accent='4655D2', hover='7F86EC', viewport='FFFFFF', floor='EDEDF0',
            ok='16804F', okText='106A40', err='D12F2F', errFill='C62D2D', errText='A61F1F',
            projRef='A95510', warn='A95510', warnText='86430A', chipBg='E3E6FA', chipStrong='4655D2',
            disabled='8A8A91', rawGrey='8A8A92', constr='6E7C92', snapOk='16804F', grid='EBEBEE', axis='D1D1D6',
            dofFull='0C0C0E', dofUnder='A33AA3', refDim='AFAFB5', dofArrow='806300', ctrl='805800',
            dimLine='68686F', dimText='2A2A30', solid='C4C4C8', solidEdge='4A4A50', previewFill='C9681A',
            okSolid='22955D', okSolidBright='16764A', axisX='D12F2F', axisY='16804F', axisZ='2563EB',
            cube=('FFFFFF', 'FFFFFF', 'EBEBEE', 'BDBDC3', '3A3A3F')),
    },
    {
        'id': 'studio',
        'name': 'Studio',
        'tag': 'Refined warm studio grey, the teal kept',
        'refs': 'Logic Pro, Affinity, Procreate, Ember itself',
        'why': [
            'The evolution option: it keeps Ember\'s identity (petrol teal accent, copper annotation) and removes '
            'the mud. Surface saturation drops from Ember\'s 10-16% to 2-4%, so the greys read as warm '
            'graphite under a studio light rather than as brown.',
            'Smallest change for existing users and for the existing tests and screenshots: same hue relationships, '
            'same token semantics, every role just cleaner.',
            'The teal is lifted and de-greened slightly (#3BB3A8 / #0E7068) so it holds 4.5:1 on every surface.',
            'Cost: of the four it looks least like the reference apps; warm neutrals can still drift brown on '
            'cheap Windows panels with a warm white point.',
        ],
        'dark': dict(
            bg='1C1B1A', panel='252423', fly='2E2D2B', field='171615', text='EDEBE7', dim='A29E98',
            sep='0F0E0E', panelSep='363432', accent='3BB3A8', hover='8ADBD3', viewport='1F1E1D', floor='2B2A28',
            ok='5BBF66', okText='7FD388', err='F06A60', errFill='BE3A31', errText='F6A59E',
            projRef='E59A58', warn='E59A58', warnText='F2BD8A', chipBg='1C3F3B', chipStrong='1E7D77',
            disabled='7F7B75', rawGrey='84807A', constr='93B2AF', snapOk='7FD388', grid='2C2B29', axis='3C3A37',
            dofFull='FFFFFF', dofUnder='B1A6F5', refDim='5C5955', dofArrow='F0D27A', ctrl='E8C060',
            dimLine='B3AEA6', dimText='EAE6DF', solid='A6A4A1', solidEdge='141312', previewFill='EA9E5C',
            okSolid='4BC96A', okSolidBright='9AE8A6', axisX='EC6A5A', axisY='5BBF66', axisZ='5A97DE',
            cube=('DEDBD6', 'F5F3F0', 'C0BCB5', '99948C', '45423E')),
        'light': dict(
            bg='ECEAE7', panel='F6F5F3', fly='FFFFFF', field='EFEDEA', text='1F1E1C', dim='5E5A55',
            sep='D6D3CE', panelSep='E5E2DE', accent='0E7068', hover='3F9E96', viewport='FBFAF8', floor='E6E3DF',
            ok='2A7A33', okText='1F6127', err='B4303A', errFill='B4303A', errText='902430',
            projRef='A0541B', warn='A0541B', warnText='7A3F12', chipBg='D5E8E5', chipStrong='0E7068',
            disabled='8C8882', rawGrey='8C8882', constr='738786', snapOk='2A7A33', grid='E7E4E0', axis='D1CDC7',
            dofFull='141312', dofUnder='5A4CC4', refDim='ABA7A1', dofArrow='866818', ctrl='875C1C',
            dimLine='6C6862', dimText='36332F', solid='C2C3C4', solidEdge='55575A', previewFill='B4652A',
            okSolid='2E8B3E', okSolidBright='1D6B2A', axisX='B3332A', axisY='2A7A33', axisZ='1F5C9E',
            cube=('FFFFFF', 'FFFFFF', 'EAE7E3', 'BEBAB4', '3E3B38')),
    },
]

RECOMMENDED = 'graphite'

# --------------------------------------------------------------- Carbon Pro
#
# Carbon taken to "expensive Windows pro software". Every role is built in
# OKLCH from a handful of numbers per variant, so the system is visible in the
# source: one grey hue/chroma for every surface, one lightness ladder, one
# accent, and ONE lightness/chroma shared by ok / err / amber / violet / the
# triad. The viewport is a vertical gradient: `viewport` is its BOTTOM stop
# (the plain tab row sits on T.viewport, so the two meet without a seam) and
# `viewportTop` is the one new value a painter would need.

PRO_DIAGNOSIS = {
    'expensive': [
        ('Lifted charcoal, not black.',
         'Resolve, UE5, Photoshop and VS 2022 put their chrome at roughly #1E-#2E (OKLab L 0.23-0.30). Near-black '
         '(#101011, L 0.17) reads as a consumer dark mode; charcoal reads as a tool you sit in front of for ten hours.'),
        ('A ladder you can count.',
         'Field < shell < panel < popover, each a small, equal step (about 0.03 in OKLab L). The eye reads depth from '
         'regular steps, not from shadows. Carbon had a 0.04 jump from bg to panel and nothing between viewport and bg.'),
        ('Lines do the separating.',
         'Pro UIs separate with a 1px line that is darker than both neighbours on dark (a groove), plus a faint top '
         'highlight on raised panels. They do not rely on big soft shadows or large luminance gaps.'),
        ('A staged viewport.',
         'Inventor, SolidWorks and NX light the model against a vertical gradient (lighter at the top, like a studio '
         'backdrop). The chrome is darker than the stage, so the model, not the chrome, is the brightest thing.'),
        ('A real material on the part.',
         'A light-mid steel grey (L about 0.74), crisp near-black B-Rep edges at full opacity, a specular band on '
         'cylinders, a brighter top face and ambient darkening where parts meet. Pre-highlight and selection are '
         'two different colours (SolidWorks: amber pre-highlight, blue selection).'),
        ('One quiet accent.',
         'A calm engineering blue (Autodesk/Windows family, OKLCH C 0.11-0.13), used only for the active tool, focus, '
         'the primary button and selection. Selected rows get a desaturated wash (about 20% toward the accent) with a '
         'faint outline, not a coloured slab.'),
        ('Semantics as one family.',
         'Status colours (ok, err) share one OKLCH lightness and chroma, annotation colours (amber reference, violet '
         'under-constrained) share one step above them, and the triad shares a third. No single colour shouts, and '
         'none looks like a stock default.'),
        ('Text that does not glare.',
         'Primary text is off-white (#DEE0E2-ish, about 11.5:1 on the panel), secondary about 6:1, disabled about 3:1. '
         'Pure white at 17:1 on black is the main source of the "cheap" glare.'),
    ],
    'cheap': [
        'Dead-flat near-black viewport (#141415) with the chrome at almost the same value: the model floats in a void '
        'and the panels have nothing to sit on.',
        'Saturated indigo (#7B8CEB, HSL S 0.73) carried into every rail icon by _map: the rail turns into a strip of '
        'violet-blue candy, and indigo reads as a software brand rather than a tool.',
        'Selection painted as a periwinkle slab over the whole face with a bright outline, and a 1px saturated '
        'outline on the browser row. That is the look of a web app, not of CAD.',
        'Pure-black (#050506) hairlines on near-black surfaces: either invisible or a heavy black ring, never a crisp '
        'groove.',
        'Mint green, salmon red and orange at three different lightnesses and chromas (Tailwind-style defaults), so '
        'they look like stock colours, not a system.',
        'Pure-white text and fully-constrained geometry (#FFFFFF): the glare that makes dark UIs look amateur.',
        'Mock rendering: flat polygons, 60%-opacity edges, no specular and no contact shading. A cheap render hides '
        'a good palette.',
    ],
}

PRO_VARIANTS = [
    {
        'id': 'pro-steel',
        'name': 'Carbon Pro Steel',
        'short': 'Steel',
        'tag': 'Blue-steel charcoal, Autodesk blue, Inventor-style stage',
        'refs': 'Autodesk Inventor / AutoCAD 2025 dark, Siemens NX, SolidWorks 2025',
        'why': [
            'Surfaces carry a faint steel cast (OKLCH hue 250, chroma 0.008, which is about 2-3 RGB units). It is neutral '
            'enough for any user accent and still says "engineering software" the moment it is on screen.',
            'The viewport is a blue-grey studio gradient ({dark.^top} at the top to {dark.viewport} at the bottom), lighter than the chrome. '
            'The steel part reads as the brightest object and the browser sits on a clearly darker card.',
            'Accent: an Autodesk-family blue (OKLCH 0.725 / 0.115 / 240: {dark.rawAccent} on dark, {light.rawAccent} on light), '
            'calmer and more cyan than Carbon\'s indigo. Through _map it makes steel-blue rail icons rather than violet ones.',
        ],
        'grey': (250, 0.008), 'vp': (248, 0.016),
        'dark': dict(field=0.205, bg=0.232, panel=0.262, fly=0.298, sep=0.165, panelSep=0.345,
                     vpTop=0.355, vpBot=0.252, text=0.905, dim=0.735, dis=0.575,
                     acc=(0.725, 0.115, 240), chip=0.52, sem=(0.68, 0.165), semText=0.80, solid=(0.755, 0.010, 245)),
        'light': dict(field=0.993, bg=0.925, panel=0.966, fly=1.0, sep=0.835, panelSep=0.885,
                      vpTop=1.0, vpBot=0.93, text=0.235, dim=0.475, dis=0.640,
                      acc=(0.505, 0.125, 245), chip=0.505, sem=(0.53, 0.15), semText=0.475, solid=(0.815, 0.010, 245)),
    },
    {
        'id': 'pro-neutral',
        'name': 'Carbon Pro Neutral',
        'short': 'Neutral',
        'tag': 'True-neutral graphite, Windows blue, Resolve-style chrome',
        'refs': 'DaVinci Resolve, Adobe Photoshop / Premiere dark, Unreal Engine 5',
        'why': [
            'Zero-cast greys (chroma 0.002), the way Resolve and the Adobe dark UIs do it, lifted to charcoal '
            '(bg {dark.bg}, panel {dark.panel}, popover {dark.fly}).',
            'The viewport gradient is neutral grey ({dark.^top} to {dark.viewport}). It is the most colour-critical stage: material '
            'colours and appearance overrides read exactly as authored.',
            'Accent: the Windows 11 / Fluent blue family (OKLCH 0.72 / 0.12 / 252: {dark.rawAccent} on dark, {light.rawAccent} on light).',
        ],
        'grey': (260, 0.002), 'vp': (260, 0.004),
        'dark': dict(field=0.205, bg=0.235, panel=0.268, fly=0.302, sep=0.168, panelSep=0.345,
                     vpTop=0.35, vpBot=0.25, text=0.905, dim=0.735, dis=0.575,
                     acc=(0.72, 0.12, 252), chip=0.52, sem=(0.68, 0.165), semText=0.80, solid=(0.755, 0.003, 260)),
        'light': dict(field=0.993, bg=0.928, panel=0.967, fly=1.0, sep=0.840, panelSep=0.890,
                      vpTop=1.0, vpBot=0.935, text=0.235, dim=0.475, dis=0.640,
                      acc=(0.50, 0.135, 254), chip=0.50, sem=(0.53, 0.15), semText=0.475, solid=(0.815, 0.003, 260)),
    },
    {
        'id': 'pro-deep',
        'name': 'Carbon Pro Deep',
        'short': 'Deep',
        'tag': 'Deep graphite, cobalt blue, high-focus canvas',
        'refs': 'Visual Studio 2022, Unreal Engine 5, CATIA 3DEXPERIENCE dark',
        'why': [
            'The darkest of the three and closest to the original Carbon mood, but on charcoal, not black: bg {dark.bg}, '
            'panel {dark.panel}, popover {dark.fly}. It suits long sessions and dim rooms.',
            'The viewport gradient is low-key ({dark.^top} to {dark.viewport}) with a faint cool cast. The part pops by contrast, and '
            'the chrome almost disappears.',
            'Accent: a slightly deeper cobalt (OKLCH 0.70 / 0.135 / 258: {dark.rawAccent} / {light.rawAccent}) that still clears 4.5:1 on every surface. '
            'Cost: it is the most dramatic, and the light variant has to carry the identity on its own.',
        ],
        'grey': (262, 0.003), 'vp': (255, 0.012),
        'dark': dict(field=0.180, bg=0.212, panel=0.245, fly=0.282, sep=0.145, panelSep=0.325,
                     vpTop=0.32, vpBot=0.215, text=0.895, dim=0.725, dis=0.565,
                     acc=(0.70, 0.135, 258), chip=0.51, sem=(0.675, 0.17), semText=0.795, solid=(0.735, 0.004, 255)),
        'light': dict(field=0.993, bg=0.918, panel=0.962, fly=1.0, sep=0.825, panelSep=0.878,
                      vpTop=0.995, vpBot=0.932, text=0.225, dim=0.465, dis=0.630,
                      acc=(0.49, 0.145, 260), chip=0.49, sem=(0.525, 0.155), semText=0.47, solid=(0.805, 0.004, 255)),
    },
]

RECOMMENDED_PRO = 'pro-steel'


# Floors the Pro variants are SOLVED to clear, a little above m236_theme_test's
# own bars (grid 1.2 on both viewport stops, floor 1.15 on the viewport) so the
# shipped values never sit on the edge of a test.
GRID_MIN = 1.22
FLOOR_MIN = 1.17


def _floor(vp_l, vc, vh, vbot, dark):
    """The rendered view's floor: a step DARKER than the viewport's bottom stop,
    deep enough to read as a ground plane (FLOOR_MIN) and to catch a shadow."""
    l = vp_l + (-0.03 if dark else -0.06)
    while contrast(oklch(l, vc, vh), vbot) < FLOOR_MIN:
        l -= 0.005
    return oklch(l, vc, vh)


def pro_core(v, dark):
    """CORE dict (derive()'s input) + post-derive overrides for one Pro variant."""
    L = v['dark' if dark else 'light']
    gh, gc = v['grey']
    vh, vc = v['vp']
    if not dark:
        gc *= 0.6  # a cast that is quiet on charcoal turns into a tint on near-white
    G = lambda l, c=gc: oklch(l, c, gh)
    aL, aC, ah = L['acc']
    a = oklch(aL, aC, ah)
    sL, sC = L['sem']
    tL = L['semText']
    vbot = oklch(L['vpBot'], vc, vh)
    vtop = oklch(L['vpTop'], vc * (0.8 if dark else 1.4), vh)
    text = G(L['text'], gc * 0.5)
    # annotation tier (amber, violet): one shared step above the status pair on dark, where they sit on the lit top
    # of the gradient; the same lightness as ok/err on light
    nL, nC = (sL + 0.08, sC * 0.9) if dark else (sL - 0.012, sC)
    amber = oklch(nL, nC, 64 if dark else 56)
    c = dict(
        bg=G(L['bg']), panel=G(L['panel']), fly=G(L['fly']), field=G(L['field']), text=text, dim=G(L['dim']),
        sep=G(L['sep']), panelSep=G(L['panelSep']), accent=a,
        hover=oklch(aL + (0.10 if dark else 0.08), aC * 0.75, ah),
        viewport=vbot, floor=_floor(L['vpBot'], vc, vh, vbot, dark),
        ok=oklch(sL, sC, 152), okText=oklch(tL, sC * 0.92, 152),
        err=oklch(sL, sC, 24), errFill=oklch(0.545, 0.165, 26), errText=oklch(tL, sC * 0.92, 24),
        projRef=amber, warn=amber, warnText=oklch(tL + (0.04 if dark else -0.03), sC * 0.92, 66),
        chipBg=mix(G(L['field']), a, 0.24 if dark else 0.12),
        chipStrong=oklch(L['chip'], aC + 0.01, ah),
        disabled=G(L['dis']), rawGrey=G(0.63 if dark else 0.56),
        constr=oklch(0.72 if dark else 0.55, 0.035, ah), snapOk=oklch(tL, sC * 0.92, 152),
        dofFull=G(0.935 if dark else 0.20, gc * 0.5), dofUnder=oklch(nL, nC, 305),
        refDim=G(0.47 if dark else 0.76),
        dofArrow=oklch(0.86 if dark else 0.535, 0.135, 95), ctrl=oklch(0.82 if dark else 0.53, 0.13, 85),
        dimLine=G(0.75 if dark else 0.50), dimText=G(0.925 if dark else 0.26, gc * 0.5),
        solid=oklch(*L['solid']), solidEdge=G(0.17 if dark else 0.30),
        previewFill=amber, okSolid=oklch(sL, sC, 152), okSolidBright=oklch(0.86 if dark else 0.50, 0.11, 152),
        axisX=oklch(0.68 if dark else 0.56, 0.16, 25), axisY=oklch(0.74 if dark else 0.53, 0.16, 145),
        axisZ=oklch(0.68 if dark else 0.53, 0.15, 255),
    )
    # The grid and axis lines sit on the gradient, so they start a hair off
    # its middle and move toward the ink until they clear GRID_MIN against
    # BOTH stops: a grid tuned to the middle vanishes into the top stop on
    # dark and into the bottom stop on light. The axis keeps its step above
    # the grid.
    vmid = mix(vtop, vbot, 0.5)
    tg = 0.07 if dark else 0.10
    while min(contrast(mix(vmid, text, tg), vtop), contrast(mix(vmid, text, tg), vbot)) < GRID_MIN:
        tg += 0.005
        if tg > 0.6:
            sys.exit('%s: no grid clears %.2f on both viewport stops' % (v['id'], GRID_MIN))
    c['grid'] = mix(vmid, text, tg)
    c['axis'] = mix(vmid, text, tg + (0.09 if dark else 0.07))
    if dark:
        c['cube'] = (G(0.80), G(0.87), G(0.70), G(0.50), G(0.30))
    else:
        c['cube'] = (G(0.975), 'FFFFFF', G(0.915), G(0.74), G(0.33))
    W, K = 'FFFFFF', '000000'
    over = {
        # selection: a desaturated wash with a quiet outline, never a slab
        'mbActiveBg': 'FF' + mix(c['panel'], a, 0.20 if dark else 0.13),
        'mbActiveOutline': 'FF' + mix(c['panel'], a, 0.42 if dark else 0.38),
        'mbHover': with_alpha(text if dark else K, 0x0F if dark else 0x09),
        'rawConActiveBg': with_alpha(a, 0x2B if dark else 0x1C),
        'rawConActiveBorder': with_alpha(a, 0x6B if dark else 0x5C),
        'flyHov': 'FF' + (mix(c['fly'], text, 0.065) if dark else mix(c['fly'], c['bg'], 0.6)),
        # 3D selection: the accent, a step lighter; pre-highlight stays amber
        'faceHighlight': 'FF' + oklch(aL + (0.07 if dark else 0.10), aC * 0.85, ah),
        'shadow': with_alpha(K, 0x99 if dark else 0x24),
        'cardShadow': with_alpha(K, 0x59 if dark else 0x12),
        'border10': with_alpha(W if dark else K, 0x14 if dark else 0x17),
        'mbHead': 'FF' + (mix(c['panel'], text, 0.025) if dark else c['panel']),
    }
    return c, over, {'_vpTop': vtop, '_vpBot': vbot}


def derive_pro(v, dark, name):
    c, over, extra = pro_core(v, dark)
    t = derive(c, dark, name)
    for k, val in over.items():
        if k not in t:
            sys.exit('pro override for unknown token ' + k)
        t[k] = val
    t.update(extra)
    t['viewportTop'] = 'FF' + extra['_vpTop'].upper()
    return t


def derive(c, dark, name):
    """Full Palette token dict (AARRGGBB strings) from a CORE dict."""
    W, K = 'FFFFFF', '000000'
    a = c['accent']
    t = {}

    def op(k, v):
        t[k] = 'FF' + v.upper()

    def tr(k, v, al):
        t[k] = with_alpha(v, al)

    for k in ('bg', 'panel', 'fly', 'field', 'text', 'dim', 'sep', 'panelSep', 'hover', 'viewport',
              'floor', 'ok', 'okText', 'err', 'errFill', 'errText', 'projRef', 'warn', 'warnText', 'chipBg',
              'disabled', 'rawGrey', 'constr', 'snapOk', 'grid', 'axis', 'dofFull', 'dofUnder', 'refDim',
              'dofArrow', 'ctrl', 'dimLine', 'dimText', 'solid', 'solidEdge', 'previewFill', 'okSolid',
              'okSolidBright', 'axisX', 'axisY', 'axisZ'):
        op(k, c[k])
    op('rawAccent', a)
    op('rawChipStrong', c['chipStrong'])
    # hovered fly: one notch toward the text on dark, toward the shell on light
    op('flyHov', mix(c['fly'], c['text'], 0.07) if dark else mix(c['fly'], c['bg'], 0.55))
    tr('rawRibbonTop', a, 0xD9)
    tr('rawRibbonBottom', a, 0x73)
    # model browser: the panel family, its header a hair lifted
    op('mbBg', c['panel'])
    op('mbHead', mix(c['panel'], c['text'], 0.035) if dark else c['bg'])
    op('mbBorder', c['sep'])
    op('mbHeadBorder', c['field'] if dark else c['panelSep'])
    op('mbText', c['text'])
    op('mbDim', c['dim'])
    op('mbDimmed', mix(c['dim'], c['panel'], 0.28))  # a hidden body: >= 3:1 on mbBg
    op('mbActiveBg', mix(c['panel'], a, 0.24 if dark else 0.13))
    op('mbActiveOutline', mix(a, c['panel'], 0.30))
    if dark:
        tr('mbHover', c['text'], 0x14)
    else:
        tr('mbHover', K, 0x0A)
    # tab bar: the shell; the active tab sits on the panel
    op('tabbarBg', c['bg'])
    op('tabbarBorder', c['sep'])
    op('tabBg', c['bg'])
    op('tabOnBg', c['panel'])
    op('tabText', c['dim'])
    op('rawTabUnderline', a)
    # home
    op('cardBg', c['panel'] if dark else W)
    op('cardBorder', c['sep'] if dark else c['panelSep'])
    op('rawCardHoverBorder', a)
    op('homeH1', mix(c['text'], W if dark else K, 0.4))
    op('cardName', c['text'])
    op('cardDate', c['dim'])
    op('galleryBg', mix(c['bg'], K, 0.12) if dark else mix(c['bg'], W, 0.35))
    op('galleryThumb', c['viewport'])
    op('galleryTitle', mix(c['text'], W if dark else K, 0.4))
    op('galleryActionBg', t['flyHov'][2:] if dark else W)
    op('galleryActionBgHover', mix(t['flyHov'][2:], c['text'], 0.06) if dark else t['flyHov'][2:])
    tr('cardShadow', K, 0x66 if dark else 0x14)
    # sketch overlay
    op('projRefEdge', mix(c['projRef'], K, 0.42 if dark else 0.30))
    op('finishGreen', c['ok'])
    # neutral overlays: white on dark, black on light
    ov = W if dark else K
    tr('hover6', ov, 0x0F if dark else 0x0A)
    tr('hover7', ov, 0x12 if dark else 0x0D)
    tr('hover8', ov, 0x14 if dark else 0x12)
    tr('border10', ov, 0x1A)
    tr('rawConActiveBg', a, 0x2E if dark else 0x24)
    tr('rawConActiveBorder', a, 0x8C)
    # dialogs and controls
    tr('scrim', K, 0x73 if dark else 0x40)
    tr('shadow', K, 0x8C if dark else 0x1F)
    op('onAccent', W)
    op('disabledFill', mix(c['panel'], a, 0.10 if dark else 0.08))
    op('aiStageWarm', mix(c['panel'], a, 0.10) if dark else mix(W, a, 0.015))
    op('aiStageCool', mix(c['field'], a, 0.06) if dark else mix(W, a, 0.035))
    # viewport: the sketch
    op('ink', c.get('ink', c['text']))
    tr('inkDim', t['ink'][2:], 0x66)
    op('rawNode', a)
    # annotation
    tr('dimPlate', c['viewport'], 0xCC)
    tr('dimPlateHot', mix(c['viewport'], a, 0.18 if dark else 0.12), 0xCC)
    tr('hudBg', c['field'] if dark else W, 0xE0 if dark else 0xF0)
    tr('hudBgHot', mix(c['field'], a, 0.16) if dark else mix(W, a, 0.10), 0xF0)
    # the toast is a neutral HUD (macOS-style), not an amber strip
    tr('toastBg', c['fly'] if dark else W, 0xEB if dark else 0xF5)
    op('toastBorder', c['panelSep'] if dark else c['sep'])
    op('toastText', c['text'])
    # the solid
    op('edgeAccent', c['projRef'])
    op('faceHighlight', mix(a, W, 0.18) if dark else mix(a, W, 0.12))
    tr('previewEdge', mix(c['previewFill'], W if dark else K, 0.15 if dark else 0.25), 0xE6)
    for k, v in zip(('cubeFace', 'cubeFaceTop', 'cubeFaceDim', 'cubeEdge', 'cubeText'), c['cube']):
        op(k, v)
    # The viewport gradient's top stop. A plain direction has a flat ground;
    # derive_pro overrides it from its own vpTop.
    t['viewportTop'] = t['viewport']
    t['_dark'] = dark
    t['_name'] = name
    return t


# ------------------------------------------------------------------ checks


def pairs_text(p):
    b = lambda k: p[k][2:] if p[k].startswith('FF') or len(p[k]) == 6 else blend(p[k], p['viewport'])
    return [
        ('text on panel', 'text', 'panel'), ('text on bg', 'text', 'bg'), ('text on fly', 'text', 'fly'),
        ('text on field', 'text', 'field'),
        ('dim on panel', 'dim', 'panel'), ('dim on bg', 'dim', 'bg'), ('dim on field', 'dim', 'field'),
        ('dim on fly', 'dim', 'fly'),
        ('accent on panel', 'rawAccent', 'panel'), ('accent on viewport', 'rawAccent', 'viewport'),
        ('accent on bg', 'rawAccent', 'bg'), ('accent on fly', 'rawAccent', 'fly'),
        ('mbText on mbBg', 'mbText', 'mbBg'), ('mbDim on mbBg', 'mbDim', 'mbBg'),
        ('mbText on mbActiveBg', 'mbText', 'mbActiveBg'),
        ('tabText on tabbarBg', 'tabText', 'tabbarBg'), ('cardName on cardBg', 'cardName', 'cardBg'),
        ('cardDate on cardBg', 'cardDate', 'cardBg'), ('galleryTitle on galleryBg', 'galleryTitle', 'galleryBg'),
        ('onAccent on chipStrong', 'onAccent', 'rawChipStrong'), ('onAccent on errFill', 'onAccent', 'errFill'),
        ('errText on panel', 'errText', 'panel'), ('okText on panel', 'okText', 'panel'),
        ('warnText on panel', 'warnText', 'panel'), ('toastText on toastBg', 'toastText', '@toastBg'),
        ('ink on viewport', 'ink', 'viewport'), ('dofFull on viewport', 'dofFull', 'viewport'),
        ('dofUnder on viewport', 'dofUnder', 'viewport'), ('projRef on viewport', 'projRef', 'viewport'),
        ('edgeAccent on viewport', 'edgeAccent', 'viewport'), ('dimText on dimPlate', 'dimText', '@dimPlate'),
        ('cubeText on cubeFace', 'cubeText', 'cubeFace'), ('cubeText on cubeFaceDim', 'cubeText', 'cubeFaceDim'),
        ('ink on viewport top', 'ink', '^top'), ('accent on viewport top', 'rawAccent', '^top'),
        ('projRef on viewport top', 'projRef', '^top'), ('dofUnder on viewport top', 'dofUnder', '^top'),
    ]


def pairs_graphic(p):
    return [
        ('mbDimmed (hidden row) on mbBg', 'mbDimmed', 'mbBg'),
        ('constr on viewport', 'constr', 'viewport'), ('rawGrey on viewport', 'rawGrey', 'viewport'),
        ('dimLine on viewport', 'dimLine', 'viewport'), ('snapOk on viewport', 'snapOk', 'viewport'),
        ('dofArrow on viewport', 'dofArrow', 'viewport'), ('ctrl on viewport', 'ctrl', 'viewport'),
        ('ok on viewport', 'ok', 'viewport'), ('err on viewport', 'err', 'viewport'),
        ('hover on viewport', 'hover', 'viewport'),
        ('solidEdge on solid', 'solidEdge', 'solid'),
        ('axisX on viewport', 'axisX', 'viewport'), ('axisY on viewport', 'axisY', 'viewport'),
        ('axisZ on viewport', 'axisZ', 'viewport'), ('disabled on fly', 'disabled', 'fly'),
        ('accent on mbActiveBg', 'rawAccent', 'mbActiveBg'),
        ('solidEdge on solid (lit top face)', 'solidEdge', '%solidTop'),
        ('dimLine on viewport top', 'dimLine', '^top'), ('constr on viewport top', 'constr', '^top'),
        ('axisX on viewport top', 'axisX', '^top'), ('axisZ on viewport top', 'axisZ', '^top'),
        ('tabText on viewport (tab row)', 'tabText', 'viewport'),
    ]


# representative icon stops, as authored in svg_icons.dart (old blue / green /
# amber / red / grey ramp), mapped through _map and measured on the rail (bg)
ICON_STOPS = [('accent glyph #3D9BE9', '3D9BE9'), ('accent face #7FB8E2', '7FB8E2'),
              ('ok glyph #46B04A', '46B04A'), ('projRef glyph #C8843F', 'C8843F'),
              ('err glyph #E5484D', 'E5484D'), ('neutral glyph #C4C9CE', 'C4C9CE'),
              ('neutral line #AEB3B9', 'AEB3B9')]


def opaque(p, k):
    if k.startswith('@'):
        return blend(p[k[1:]], p['viewport'][2:])
    if k == '%solidTop':  # the mock's lit top face: solid 38% toward white
        return mix(p['solid'][2:], 'FFFFFF', 0.38)
    if k == '^top':
        return p.get('_vpTop', p['viewport'][2:])
    v = p[k]
    return v[2:] if len(v) == 8 else v


def check(p, accents):
    rows = []
    for label, f, b in pairs_text(p):
        fg, bg = opaque(p, f), opaque(p, b)
        rows.append(dict(group='text', label=label, fg=fg, bg=bg, ratio=round(contrast(fg, bg), 2), min=KMIN_TEXT))
    for label, f, b in pairs_graphic(p):
        fg, bg = opaque(p, f), opaque(p, b)
        rows.append(dict(group='graphic', label=label, fg=fg, bg=bg, ratio=round(contrast(fg, bg), 2),
                         min=KMIN_GRAPHIC))
    for label, src in ICON_STOPS:
        fg = map_icon(src, p)
        bg = opaque(p, 'bg')
        rows.append(dict(group='icon', label=label + ' (mapped) on rail', fg=fg, bg=bg,
                         ratio=round(contrast(fg, bg), 2), min=KMIN_GRAPHIC))
    for aid, light, darkv in accents:
        fg = (darkv if p['_dark'] else light)[2:]
        for k in ('panel', 'viewport'):
            bg = opaque(p, k)
            rows.append(dict(group='accent-enum', label='Accent.%s on %s' % (aid, k), fg=fg, bg=bg,
                             ratio=round(contrast(fg, bg), 2), min=KMIN_TEXT))
    # info only: the elevation ladder and the grid
    info = {k: round(lstar(opaque(p, k)), 1) for k in ('field', 'bg', 'viewport', 'panel', 'fly')}
    info['grid_on_viewport'] = round(contrast(opaque(p, 'grid'), opaque(p, 'viewport')), 2)
    info['vpTop'] = round(lstar(opaque(p, '^top')), 1)
    # info only: selection on the part is told apart by hue and edge weight, not by 3:1 luminance
    info['faceHighlight_on_solid'] = round(contrast(opaque(p, 'faceHighlight'), opaque(p, 'solid')), 2)
    info['edgeAccent_on_solid'] = round(contrast(opaque(p, 'edgeAccent'), opaque(p, 'solid')), 2)
    return rows, info


def accent_leaks(p, fields):
    """m236: a token whose RGB equals the accent must be one of the tinted raw* ones."""
    tinted = {'rawAccent', 'rawRibbonTop', 'rawRibbonBottom', 'rawTabUnderline', 'rawCardHoverBorder',
              'rawConActiveBg', 'rawConActiveBorder', 'rawChipStrong', 'rawNode'}
    acc = p['rawAccent'][2:]
    return [f for f in fields if f not in tinted and p[f][2:] == acc]


def dart_literal(var, p, fields):
    lines = ['const Palette %s = Palette(' % var, "  name: '%s'," % p['_name'],
             '  brightness: Brightness.%s,' % ('dark' if p['_dark'] else 'light')]
    for f in fields:
        lines.append('  %s: Color(0x%s),' % (f, p[f]))
    lines.append(');')
    if '_vpTop' in p and 'viewportTop' not in fields:
        lines.append('// Viewport gradient (not a Palette field yet): top 0xFF%s -> bottom = viewport 0xFF%s.'
                     % (p['_vpTop'], p['_vpBot']))
    return '\n'.join(lines)


# ------------------------------------------------------------------ icons

RAIL_PART = ['newSketchIcon', 'CR.extrude', 'CR.revolve', 'CR.sweep', 'CR.loft', 'CR.coil', '|',
             'MO.hole', 'MO.fillet', 'MO.chamfer', 'MO.shell', 'MO.combine', '|',
             'WF.plane', 'WF.axis', 'WF.point', '|', 'PT.rect', 'PT.circ', 'PT.mirror', '|',
             'MS.measure', '|', 'VW.shaded', 'VW.rendered', 'VW.section']
RAIL_SKETCH = ['finishIcon', '|', 'IC.line34', 'IC.circle34', 'IC.arc34', 'IC.rect34', 'IC.fillet18',
               'IC.point18', 'IC.projgeo', '|', 'CN.dim', 'CN.coincident', 'CN.horiz', 'CN.perp',
               'CN.tangent', 'CN.equal', 'CN.showcons', '|', 'MD.move', 'MD.trim', 'MD.moffset', '|',
               'IC.patrect', 'IC.patmir']
OTHER_ICONS = ['treeFolderIcon', 'treeCubeIcon', 'treeRootCubeIcon', 'endOfSketchIcon', 'tabHomeIcon',
               'homeTabIcon', 'sketchCubeIcon', 'CN.horiz', 'CN.perp', 'CN.coincident', 'CN.tangent',
               'CN.vert', 'CN.parallel', 'IC.circle34', 'originIcon', 'partCubeIcon']


def svg_of(icons, ref):
    if '.' in ref:
        m, k = ref.split('.', 1)
        return icons['maps'].get(m, {}).get(k)
    return icons['singles'].get(ref)


# ------------------------------------------------------------------- main


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    icons = json.load(open(sys.argv[1], encoding='utf-8'))
    out = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_OUT
    fields, comments, base, accents = parse_theme()

    pals = {}
    meta = []
    pals['ember'] = base['kEmber']
    pals['chalk'] = base['kChalk']
    meta.append(dict(id='baseline', name='Baseline', tag='Ember + Chalk, as shipped today',
                     refs='frontend/lib/theme.dart', dark='ember', light='chalk', why=[
                         'Ember (dark): warm brown charcoal (surface hue ~33, saturation 10-16%) with a petrol teal '
                         'accent and copper annotation. The brown cast is what reads as "muddy" next to a steel part, '
                         'and it fights every cool/neutral system surface UIKit draws around it.',
                         'Chalk (light): grey-cream paper with a dark teal. Better, but the cream still tints the '
                         'viewport and the cool grey solid looks blue against it.',
                     ], vars=('kEmber', 'kChalk')))
    leaks = {}
    for d in DIRECTIONS:
        for mode in ('dark', 'light'):
            pid = '%s-%s' % (d['id'], mode)
            nm = '%s %s' % (d['name'], 'Dark' if mode == 'dark' else 'Light')
            pals[pid] = derive(d[mode], mode == 'dark', nm)
            missing = set(fields) - set(k for k in pals[pid] if not k.startswith('_'))
            extra = set(k for k in pals[pid] if not k.startswith('_')) - set(fields)
            if missing or extra:
                sys.exit('%s: missing %s extra %s' % (pid, sorted(missing), sorted(extra)))
            lk = accent_leaks(pals[pid], fields)
            if lk:
                leaks[pid] = lk
        meta.append(dict(id=d['id'], name=d['name'], tag=d['tag'], refs=d['refs'], why=d['why'],
                         dark='%s-dark' % d['id'], light='%s-light' % d['id'],
                         vars=('k%sDark' % d['name'], 'k%sLight' % d['name'])))
    pro_meta = []
    for v in PRO_VARIANTS:
        for mode in ('dark', 'light'):
            pid = '%s-%s' % (v['id'], mode)
            nm = '%s %s' % (v['name'], 'Dark' if mode == 'dark' else 'Light')
            pals[pid] = derive_pro(v, mode == 'dark', nm)
            missing = set(fields) - set(k for k in pals[pid] if not k.startswith('_'))
            extra = set(k for k in pals[pid] if not k.startswith('_')) - set(fields)
            if missing or extra:
                sys.exit('%s: missing %s extra %s' % (pid, sorted(missing), sorted(extra)))
            lk = accent_leaks(pals[pid], fields)
            if lk:
                leaks[pid] = lk
        nm = v['name'].replace(' ', '')
        fill = lambda txt: re.sub(r'\{(dark|light)\.([\^\w]+)\}',
                                  lambda m: '#' + opaque(pals['%s-%s' % (v['id'], m.group(1))], m.group(2)), txt)
        pro_meta.append(dict(id=v['id'], name=v['name'], short=v['short'], tag=v['tag'], refs=v['refs'],
                             why=[fill(w) for w in v['why']], dark='%s-dark' % v['id'], light='%s-light' % v['id'],
                             vars=('k%sDark' % nm, 'k%sLight' % nm)))
    if leaks:
        sys.exit('accent RGB reused by a non-tinted token (m236 would fail): %s' % leaks)

    checks, infos, dart = {}, {}, {}
    fails_total = {}
    for pid, p in pals.items():
        rows, info = check(p, accents)
        checks[pid] = rows
        infos[pid] = info
        fails_total[pid] = [r for r in rows if r['ratio'] < r['min']]
    for m in meta + pro_meta:
        for pid, var in zip((m['dark'], m['light']), m['vars']):
            dart[pid] = dart_literal(var, pals[pid], fields)

    # icons the page needs
    refs = set(r for r in RAIL_PART + RAIL_SKETCH + OTHER_ICONS if r != '|')
    ic = {}
    for r in sorted(refs):
        s = svg_of(icons, r)
        if s is None:
            sys.exit('unresolved icon ' + r)
        ic[r] = s

    data = dict(fields=fields, comments=comments, pals=pals, meta=meta, checks=checks, infos=infos,
                dart=dart, icons=ic, railPart=RAIL_PART, railSketch=RAIL_SKETCH, recommended=RECOMMENDED,
                accents=accents, proMeta=pro_meta, proRec=RECOMMENDED_PRO, diag=PRO_DIAGNOSIS,
                oklch={pid: {k: [round(x, 3) for x in to_oklch(opaque(pals[pid], k))]
                             for k in ('bg', 'panel', 'fly', 'field', 'viewport', 'text', 'dim', 'disabled',
                                       'rawAccent', 'ok', 'err', 'projRef', 'dofUnder', 'solid')}
                       for pid in pals})
    blob = json.dumps(data, ensure_ascii=False, separators=(',', ':')).replace('</', '<\\/')
    tpl = open(os.path.join(HERE, 'template.html'), encoding='utf-8').read()
    html = tpl.replace('/*__DATA__*/null', blob)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, 'w', encoding='utf-8') as f:
        f.write(html)
    for v in PRO_VARIANTS:
        for mode in ('dark', 'light'):
            pp = pals['%s-%s' % (v['id'], mode)]
            print('%-18s ' % (v['id'] + '-' + mode) + ' '.join('%s=%s' % (k, opaque(pp, k)) for k in (
                'bg', 'panel', 'fly', 'field', '^top', 'viewport', 'text', 'dim', 'disabled', 'rawAccent',
                'mbActiveBg', 'faceHighlight', 'ok', 'err', 'projRef', 'solid', 'solidEdge', 'rawChipStrong',
                'sep', 'panelSep', 'grid')))
            print('    icons:', ' '.join(map_icon(src, pp) for _, src in ICON_STOPS),
                  ' hsl-hue accent %.0f' % hsl_from(opaque(pp, 'rawAccent'))[0])
    print('wrote %s (%d bytes, %d palettes)' % (out, len(html), len(pals)))
    for pid in pals:
        f = fails_total[pid]
        i = infos[pid]
        print('%-14s fails=%-2d  L*: field %5.1f bg %5.1f vp %5.1f panel %5.1f fly %5.1f  grid %.2f' % (
            pid, len(f), i['field'], i['bg'], i['viewport'], i['panel'], i['fly'], i['grid_on_viewport']))
        for r in f:
            print('    FAIL %-44s %5.2f < %.1f  (%s on %s)' % (r['label'], r['ratio'], r['min'], r['fg'], r['bg']))


if __name__ == '__main__':
    main()
