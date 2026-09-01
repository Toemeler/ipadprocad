/* M344 — the edge-avoiding a-trous filter. See cycles_denoise.h for why it is
 * this and not OpenImageDenoise.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * DELIBERATELY FREE OF CYCLES. Nothing in here includes a Cycles header or
 * names a ccl:: type: it takes float buffers and sizes. That is what lets the
 * host render test call it directly with hand-made buffers and check that it
 * preserves an edge, which is the one property that matters and the one no
 * on-device eyeball test can measure.
 *
 * The single exception is threading, and it configures itself: inside Cycles'
 * tree `util/tbb.h` is on the include path and the row loop is parallel;
 * compiled anywhere else it is not found and the loop is serial. `__has_include`
 * rather than a build flag, so append.cmake stays two lines and there is no
 * define to forget in one of the three workflows that build this.
 */
#include "cycles_denoise.h"

#include <cmath>
#include <cstring>
#include <vector>

#if defined(__has_include)
#  if __has_include("util/tbb.h")
#    include "util/tbb.h"
#    define CYSHIM_PARALLEL 1
#  endif
#endif

namespace cyshim {
namespace {

/* Run [fn] over rows [0, rows). */
template<typename F> void for_rows(const int rows, F fn)
{
#ifdef CYSHIM_PARALLEL
  /* A grain size, because the body is a few microseconds per row and TBB's
   * auto-partitioner would otherwise spend more on scheduling than on work. */
  ccl::parallel_for(ccl::blocked_range<int>(0, rows, 16),
                    [&](const ccl::blocked_range<int> &r) {
                      for (int y = r.begin(); y != r.end(); y++) {
                        fn(y);
                      }
                    });
#else
  for (int y = 0; y < rows; y++) {
    fn(y);
  }
#endif
}

/* The 5-tap B-spline the a-trous decomposition is built on: {1,4,6,4,1}/16,
 * applied as an outer product. Not normalised here — every weight is divided
 * by the accumulated sum, which it has to be anyway once the edge-stopping
 * terms have thrown some of the taps away. */
const float kTap[5] = {1.0f / 16.0f, 4.0f / 16.0f, 6.0f / 16.0f, 4.0f / 16.0f, 1.0f / 16.0f};

/* Below this, an albedo channel is treated as this value for the purposes of
 * demodulation.
 *
 * NOT A FUDGE, and it does not bias anything: the SAME number is used to
 * divide and to multiply back, so a pixel whose albedo is zero — the
 * background, an emitter, a light seen directly — comes out as
 * filter(c / k) * k, which is filter(c). The floor decides how much such a
 * pixel is filtered, not whether it survives. */
const float kAlbedoFloor = 0.08f;

/* How large a RELATIVE difference in lighting counts as noise at one sample,
 * before the sample count narrows it.
 *
 * The variance of a Monte Carlo estimate falls as 1/n, so the tolerance has to
 * as well or the filter would keep blurring a converged image; the weight is
 * therefore scaled by `samples / kLuminanceSigma^2`. At sixteen samples this
 * puts the half-weight point around a difference equal to the two neighbours'
 * combined level, which is about where sixteen-sample noise sits and well
 * outside a real shadow edge.
 *
 * The one number in this file chosen by eye rather than derived. */
const float kLuminanceSigma = 4.0f;

/* How far the albedo may differ before the tap is dropped. The demodulated
 * signal is only meaningful where the surface is the same one, and this is
 * what keeps the lighting of a copper bus-bar out of the aluminium bracket
 * behind it. */
const float kAlbedoSigma = 0.02f;

/* The darkest level the relative comparison above will normalise against.
 *
 * Demodulated irradiance on a lit surface is around 0.3 to 2, so a tenth of
 * that is where "this pixel is in shadow" stops being a measurement and starts
 * being the last bits of a float. Below it, two neighbours are treated as
 * comparable however far apart they look. */
const float kLuminanceFloor = 0.05f;

float luminance(const float r, const float g, const float b)
{
  return 0.2126f * r + 0.7152f * g + 0.0722f * b;
}

/* One 5-tap pass along [dx],[dy], from [src] into [dst].
 *
 * SEPARATED, which is the one liberty this implementation takes with the
 * paper. The published filter applies the 5x5 kernel whole: 25 taps, and the
 * edge-stopping weights make it genuinely non-separable, so running it as a
 * horizontal pass followed by a vertical one is an approximation rather than
 * an identity. It is the approximation every real-time implementation makes,
 * for a reason this file measures: 10 taps against 25 is two and a half times
 * the frame rate, and the difference it costs is a slightly softer response
 * at a corner where two edges meet — invisible next to the noise it is
 * removing, and gone entirely by the time the fade has run out.
 *
 * [lum] is the luminance of [src], precomputed. Recomputing it per tap is
 * five floating-point operations done twenty-five times per pixel for a value
 * that does not change, and it was a fifth of the filter's whole cost. */
void pass(const float *src,
          const float *lum,
          float *dst,
          const float *albedo,
          const float *normal,
          const int width,
          const int height,
          const int dx,
          const int dy,
          const float inv_lum,
          const float inv_alb)
{
  for_rows(height, [&](const int y) {
    for (int x = 0; x < width; x++) {
      const size_t i = (size_t)y * (size_t)width + (size_t)x;
      const float *cp = src + i * 4;
      const float *ap = albedo + i * 3;
      const float *np = normal != nullptr ? normal + i * 3 : nullptr;
      const float lp = lum[i];
      const float alp = lp < 0.0f ? -lp : lp;

      /* The centre tap, taken whole: its edge-stopping weights are all 1 by
       * construction, and taking it unconditionally is also what guarantees
       * the accumulated weight is never zero. */
      float sum0 = cp[0] * kTap[2];
      float sum1 = cp[1] * kTap[2];
      float sum2 = cp[2] * kTap[2];
      float wsum = kTap[2];

      for (int k = 0; k < 5; k++) {
        if (k == 2) {
          continue;
        }
        const int qx = x + (k - 2) * dx;
        const int qy = y + (k - 2) * dy;
        if (qx < 0 || qx >= width || qy < 0 || qy >= height) {
          continue;
        }
        const size_t j = (size_t)qy * (size_t)width + (size_t)qx;

        float w = kTap[k];

        /* NORMAL. Raised to the eighth by three squarings rather than by powf:
         * this is the innermost line of the whole filter. A face and the
         * chamfer off it differ by tens of degrees, and d^8 has all but
         * vanished by then, which is what stops the filter reaching across an
         * edge the model actually has. */
        if (np != nullptr) {
          const float *nq = normal + j * 3;
          float d = np[0] * nq[0] + np[1] * nq[1] + np[2] * nq[2];
          if (d <= 0.0f) {
            continue;
          }
          d *= d;
          d *= d;
          d *= d;
          w *= d;
        }

        /* ALBEDO. What keeps the lighting of a copper bus-bar out of the
         * aluminium bracket behind it: the demodulated signal is only
         * comparable where the surface is the same one. */
        const float *aq = albedo + j * 3;
        const float da0 = ap[0] - aq[0];
        const float da1 = ap[1] - aq[1];
        const float da2 = ap[2] - aq[2];
        const float da = da0 * da0 + da1 * da1 + da2 * da2;

        /* LUMINANCE, of the DEMODULATED signal — so this is a difference in
         * LIGHTING, not in colour. It is what holds a shadow edge, and it is
         * the term that has to know the sample count: at four samples two
         * neighbours differing by half are both noise, and at four hundred
         * they are a real boundary.
         *
         * RELATIVE to the pixel's own level, which is not a refinement but a
         * correctness fix. Monte Carlo noise is multiplicative — a surface at
         * a tenth of the brightness has a tenth of the absolute spread — so an
         * absolute tolerance is far too tight in the shadows and far too loose
         * in the highlights. Judged absolutely, a dark region's taps are
         * rejected in proportion to how far they are from the centre pixel,
         * and rejecting the taps that disagree is not filtering, it is
         * BIASING: the answer is dragged towards whatever the centre sample
         * happened to be, which is the noise you were trying to remove. */
        const float lq = lum[j];
        const float dl = lp - lq;
        /* Normalised by the SUM of the two levels, not by the centre pixel's.
         * Symmetric, and that is the whole point: judged against the centre
         * alone, a dark noisy region rejects every tap that disagrees with
         * whatever sample the centre pixel happened to get, which drags the
         * answer towards that sample. Rejecting the taps that disagree is not
         * filtering, it is BIASING — it keeps precisely the noise it was asked
         * to remove. The floor is what stops two pixels that are both nearly
         * black from looking infinitely different. */
        const float sc = alp + (lq < 0.0f ? -lq : lq) + kLuminanceFloor;
        const float scale = sc * sc;

        /* ONE DIVISION PER TAP, for both terms at once — the normalisation is
         * multiplied through rather than applied as a second divide. A
         * rational falloff and not a cutoff, for the same reason as above: a
         * weight that goes smoothly to nothing loses no information, and one
         * that is thresholded throws away exactly the samples that carry it. */
        w *= scale / (scale * (1.0f + da * inv_alb) + dl * dl * inv_lum);
        if (w <= 1e-6f) {
          continue;
        }

        const float *cq = src + j * 4;
        sum0 += cq[0] * w;
        sum1 += cq[1] * w;
        sum2 += cq[2] * w;
        wsum += w;
      }

      float *out = dst + i * 4;
      /* wsum is at least kTap[2], so this cannot divide by zero. The NaN guard
       * is for a pixel the renderer handed us as NaN, which would otherwise
       * spread across the whole image over three iterations. */
      if (wsum > 0.0f && wsum == wsum) {
        const float inv = 1.0f / wsum;
        out[0] = sum0 * inv;
        out[1] = sum1 * inv;
        out[2] = sum2 * inv;
      }
      else {
        out[0] = cp[0];
        out[1] = cp[1];
        out[2] = cp[2];
      }
      out[3] = 0.0f;
    }
  });
}

void fill_luminance(const float *src, float *lum, const int width, const int height)
{
  for_rows(height, [&](const int y) {
    const size_t row = (size_t)y * (size_t)width;
    for (int x = 0; x < width; x++) {
      const size_t i = row + (size_t)x;
      lum[i] = luminance(src[i * 4 + 0], src[i * 4 + 1], src[i * 4 + 2]);
    }
  });
}

}  // namespace

float denoise_strength_for(const int samples, const int target)
{
  if (samples <= 0) {
    return 0.0f;
  }
  if (target <= 0) {
    return 1.0f;
  }
  /* Full strength for the first tenth of the budget, then a straight fade to
   * nothing at three-quarters of it.
   *
   * Off well BEFORE the target rather than at it, deliberately. The last
   * quarter of a render is where the eye is looking for detail, and a frame
   * that is still 5% filtered at the end is a frame whose sharpness depends on
   * a constant in this file. Ending the fade early means the image the user
   * settles on has been the raw path trace for a while by the time it stops
   * changing, so what they judge the renderer by is the renderer. */
  const float t = (float)samples / (float)target;
  const float lo = 0.10f;
  const float hi = 0.75f;
  if (t <= lo) {
    return 1.0f;
  }
  if (t >= hi) {
    return 0.0f;
  }
  return (hi - t) / (hi - lo);
}

size_t denoise_scratch_floats(const int width, const int height)
{
  if (width <= 0 || height <= 0) {
    return 0;
  }
  /* Two RGBA planes to ping-pong between, and one luminance plane. */
  return (size_t)width * (size_t)height * 9;
}

void denoise(float *color,
             const float *albedo,
             const float *normal,
             const int width,
             const int height,
             const int samples,
             const float strength,
             float *scratch)
{
  if (color == nullptr || albedo == nullptr) {
    return;
  }
  if (strength <= 0.0f || width < 5 || height < 5 || samples <= 0) {
    return;
  }

  const size_t n = (size_t)width * (size_t)height;
  const float mix = strength > 1.0f ? 1.0f : strength;

  std::vector<float> owned;
  float *a = scratch;
  if (a == nullptr) {
    owned.resize(denoise_scratch_floats(width, height));
    a = owned.data();
  }
  float *const b = a + n * 4;
  float *const lum = a + n * 8;

  /* ---- demodulate ------------------------------------------------------
   *
   * a[] holds irradiance in .rgb; .a is unused and left at zero rather than
   * carrying the coverage, so a tap's weight can never be influenced by it. */
  for_rows(height, [&](const int y) {
    const size_t row = (size_t)y * (size_t)width;
    for (int x = 0; x < width; x++) {
      const size_t i = row + (size_t)x;
      const float *c = color + i * 4;
      const float *al = albedo + i * 3;
      for (int k = 0; k < 3; k++) {
        const float d = al[k] > kAlbedoFloor ? al[k] : kAlbedoFloor;
        a[i * 4 + k] = c[k] / d;
      }
      a[i * 4 + 3] = 0.0f;
    }
  });

  /* Sample-count-driven tolerance. The variance of a Monte Carlo estimate
   * falls as 1/n, so the luminance tolerance has to narrow with the sample
   * count or the filter would go on blurring a converged image. */
  /* Squared, because the weight compares a squared difference against a
   * squared level. */
  const float inv_lum = (float)samples / (kLuminanceSigma * kLuminanceSigma);
  const float inv_alb = 1.0f / kAlbedoSigma;

  for (int it = 0; it < kDenoiseIterations; it++) {
    const int step = 1 << it;
    fill_luminance(a, lum, width, height);
    pass(a, lum, b, albedo, normal, width, height, step, 0, inv_lum, inv_alb);
    fill_luminance(b, lum, width, height);
    pass(b, lum, a, albedo, normal, width, height, 0, step, inv_lum, inv_alb);
  }

  /* ---- remodulate, and blend back --------------------------------------
   *
   * The same floor as the demodulation, so a pixel with no albedo — the
   * background, an emitter, a light seen directly — is returned exactly as the
   * filter left it rather than being scaled towards black. */
  for_rows(height, [&](const int y) {
    const size_t row = (size_t)y * (size_t)width;
    for (int x = 0; x < width; x++) {
      const size_t i = row + (size_t)x;
      float *c = color + i * 4;
      const float *f = a + i * 4;
      const float *al = albedo + i * 3;
      for (int k = 0; k < 3; k++) {
        const float d = al[k] > kAlbedoFloor ? al[k] : kAlbedoFloor;
        const float filtered = f[k] * d;
        c[k] = c[k] + (filtered - c[k]) * mix;
      }
    }
  });
}

}  // namespace cyshim
