#!/usr/bin/env python3
"""M344 — is the environment map an HDRI, or a photograph of one?

An equirectangular image can have every property the README asks for — 2:1,
2048x1024, a studio, the right filename — and still light the scene flat. The
property that matters is not in the header: it is whether the light sources
are BRIGHTER THAN THE WALLS, by a factor of tens or hundreds.

A .hdr that has been through an 8-bit conversion at some point has values
that stop at 1.0, so the softbox and the white wall behind it are the same
number. Cycles will load it, the render will succeed, and the result will be
the uniform world M332 replaced: no highlight streak on a metal edge, because
nothing in the sphere is bright enough to draw one.

That failure is invisible from the file listing and expensive to find on a
device, so it is measured here, at build time. This prints; it never fails.
An asset that lights badly is a judgement call and belongs to whoever chose
it, not to a CI step.

Pure standard library on purpose: it runs in the packaging job, which has no
numpy, no OIIO and no reason to acquire either.
"""
import sys, os, struct

def read_radiance(path):
    """Radiance RGBE -> (width, height, [ (r,g,b) floats ]). None if unparsable."""
    with open(path, 'rb') as f:
        data = f.read()
    if not (data.startswith(b'#?RADIANCE') or data.startswith(b'#?RGBE')):
        return None
    # Header ends at a blank line; the resolution line follows it.
    i = data.find(b'\n\n')
    if i < 0:
        return None
    j = data.index(b'\n', i + 2)
    res = data[i + 2:j].split()
    if len(res) != 4 or res[0] != b'-Y' or res[2] != b'+X':
        return None                      # a rotated/flipped variant; not worth it
    h, w = int(res[1]), int(res[3])
    p = j + 1
    pix = bytearray(w * h * 4)
    for y in range(h):
        if p + 4 > len(data):
            return None
        row = y * w * 4
        if data[p] == 2 and data[p + 1] == 2 and (data[p + 2] << 8 | data[p + 3]) == w and w >= 8:
            p += 4                       # new-style RLE, one channel at a time
            for c in range(4):
                x = 0
                while x < w:
                    if p >= len(data):
                        return None
                    n = data[p]; p += 1
                    if n > 128:           # a run of one value
                        n -= 128
                        v = data[p]; p += 1
                        for k in range(n):
                            pix[row + (x + k) * 4 + c] = v
                    else:                 # n literal values
                        for k in range(n):
                            pix[row + (x + k) * 4 + c] = data[p + k]
                        p += n
                    x += n
                if x != w:
                    return None
        else:                             # flat, uncompressed scanline
            end = p + w * 4
            if end > len(data):
                return None
            pix[row:row + w * 4] = data[p:end]
            p = end
    return w, h, pix                      # raw RGBE; decoded per pixel below

def report(path):
    name = os.path.basename(path)
    size = os.path.getsize(path)
    print("HDRI CHECK: %s (%.1f MB)" % (name, size / 1048576.0))
    if name.lower().endswith('.exr'):
        print("  .exr — not parsed here (no OpenEXR in this job). The shim loads it"
              " through OpenImageIO; .hdr is preferred, see the README.")
        return
    got = read_radiance(path)
    if got is None:
        print("  NOT A RADIANCE FILE, or an encoding this reader does not cover.")
        print("  Cycles reads it through OpenImageIO and may well be fine. But if"
              " the extension is .hdr and this fails, check it was not saved as"
              " a PNG or JPEG under an .hdr name.")
        return
    w, h, pix = got
    print("  %d x %d, aspect %.3f%s" % (w, h, w / float(h),
          "" if abs(w / float(h) - 2.0) < 0.01 else "   <-- NOT 2:1, not equirectangular"))

    import math
    # ONE PASS, AND A HISTOGRAM RATHER THAN THE PIXELS.
    #
    # A 2K map is two million pixels. Keeping a luminance per pixel so it can
    # be sorted costs about 640 MB of Python objects to print six lines, which
    # is not a reasonable thing for a packaging step to do. Log-spaced buckets
    # answer "what share of the light is in the brightest 0.1% of the sphere"
    # to far better precision than the question deserves, in a fixed 4096
    # floats.
    #
    # Solid angle per pixel on an equirectangular sphere goes as sin(theta):
    # a row at the pole covers almost nothing and must not count as a row at
    # the equator does. Every number below is weighted by it.
    NB = 4096
    LO, HI = 1e-4, 1e6                    # a range no studio map leaves
    lgLO, lgSPAN = math.log10(LO), math.log10(HI) - math.log10(LO)
    hw = [0.0] * NB                       # solid angle in each bucket
    hl = [0.0] * NB                       # luminance * solid angle in each
    tot = 0.0; wsum = 0.0; peak = 0.0; over = 0.0
    exp2 = [0.0] * 256                    # 2**(e-136), once
    for e in range(1, 256):
        exp2[e] = 2.0 ** (e - 136)
    for y in range(h):
        sw = math.sin((y + 0.5) / h * math.pi)
        if sw <= 0.0:
            continue
        wsum += sw * w
        k = y * w * 4
        for _ in range(w):
            e = pix[k + 3]
            if e:
                sc = exp2[e]
                l = (0.2126 * pix[k] + 0.7152 * pix[k + 1] + 0.0722 * pix[k + 2]) * sc
            else:
                l = 0.0
            k += 4
            tot += l * sw
            if l > peak:
                peak = l
            if l > 1.0:
                over += sw
            if l > LO:
                b = int((math.log10(l) - lgLO) / lgSPAN * NB)
                if b < 0: b = 0
                elif b >= NB: b = NB - 1
            else:
                b = 0
            hw[b] += sw
            hl[b] += l * sw
    mean = tot / wsum if wsum else 0.0
    print("  mean luminance %.4f, peak %.1f  (peak is %.0fx the mean)"
          % (mean, peak, peak / mean if mean > 1e-9 else 0.0))
    print("  above 1.0: %.3f%% of the sphere" % (100.0 * over / wsum if wsum else 0.0))

    for frac in (0.001, 0.01):
        cut = frac * wsum; acc = 0.0; carried = 0.0
        for b in range(NB - 1, -1, -1):   # brightest bucket downwards
            if acc >= cut:
                break
            if hw[b] <= 0.0:
                continue
            take = cut - acc
            if hw[b] <= take:
                acc += hw[b]; carried += hl[b]
            else:                          # a part of this bucket, pro rata
                carried += hl[b] * (take / hw[b]); acc = cut
        print("  brightest %.1f%% of the sphere carries %.1f%% of the light"
              % (100 * frac, 100 * carried / tot if tot else 0.0))

    # The verdict. The threshold is not arbitrary: a source that is only a few
    # times the mean cannot cast a highlight that reads against its own
    # surroundings, which is the entire reason for using an environment.
    ratio = peak / mean if mean > 1e-9 else 0.0
    if peak <= 1.001:
        print("  VERDICT: NOT AN HDRI. Nothing exceeds 1.0, so this has been"
              " through an 8-bit conversion. The light sources and the white"
              " walls are the same value and the render will be flat.")
    elif ratio < 20:
        print("  VERDICT: LOW DYNAMIC RANGE for a studio (peak only %.0fx mean)."
              " Usable, but expect soft, even light and weak edge highlights." % ratio)
    else:
        print("  VERDICT: looks like a real HDRI — defined sources well above"
              " the surround, which is what draws a highlight on an edge.")

if __name__ == '__main__':
    if len(sys.argv) < 2 or not os.path.isfile(sys.argv[1]):
        print("HDRI CHECK: no environment map in this build.")
        sys.exit(0)
    try:
        report(sys.argv[1])
    except Exception as e:               # never fail the build over a report
        print("HDRI CHECK: could not read it (%s). Not fatal." % e)
    sys.exit(0)
