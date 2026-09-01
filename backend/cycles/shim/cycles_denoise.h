/* M344 — the denoiser, because the one Cycles ships cannot come with us.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * ---------------------------------------------------------------------------
 * WHY THIS FILE EXISTS AT ALL
 * ---------------------------------------------------------------------------
 *
 * Cycles has two denoisers and this app can have neither. OptiX is NVIDIA's.
 * OpenImageDenoise is the one that would work — it has had a Metal backend
 * since 2.3 — but `lib/ios_arm64`, the precompiled dependency set Blender's
 * own `ios` branch is built against, does not ship it, which is why
 * `-DWITH_OPENIMAGEDENOISE=OFF` is in every one of this repo's Cycles builds:
 * `cycles_integrator` was otherwise compiling `denoiser_oidn.cpp` against a
 * library that is not there, and the link failed on `_oidnSetFilterImage`.
 *
 * Building OIDN for iOS is a real option and it is not this milestone's. It
 * needs ISPC in the build, a second set of weights in the bundle, and a CI
 * chain nobody has walked; and the whole point of M344 is a viewport that
 * updates WHILE YOU ORBIT, where a heavyweight neural filter would be the
 * wrong tool even if it were free — it is tuned to make a final frame perfect,
 * not to run thirty times a second.
 *
 * So: an edge-avoiding a-trous wavelet filter (Dammertz, Sewtz, Hanika &
 * Lensch, HPG 2010), guided by the albedo and normal buffers Cycles already
 * writes for exactly this purpose. It is the filter every real-time path
 * tracer used before the neural ones arrived, it is about two hundred lines,
 * and it costs a few milliseconds on a viewport-sized image.
 *
 * ---------------------------------------------------------------------------
 * THE OBJECTION THIS ANSWERS
 * ---------------------------------------------------------------------------
 *
 * Every Cycles build in this repo carries the comment that a denoiser "smears
 * exactly the crisp machined edges the render exists to show". That was a fair
 * description of a naive blur and it is not what happens here, for two
 * reasons, and they are the two ideas the filter is built out of.
 *
 * ALBEDO DEMODULATION. The filter never sees the picture. The colour is
 * divided by the surface albedo first, leaving only the LIGHTING — which is
 * smooth almost everywhere, which is why it can be filtered hard — and the
 * albedo is multiplied back afterwards, untouched. Every edge that comes from
 * the model being one colour here and another there, which on a CAD render is
 * nearly all of them, is therefore mathematically incapable of being blurred:
 * it is not in the buffer being filtered.
 *
 * EDGE STOPPING. What is left — the shading — is filtered with weights that
 * collapse across a discontinuity in the surface normal or the albedo. A
 * chamfer is a normal discontinuity, so the filter does not reach across it. A
 * shadow terminator is a discontinuity in the lighting itself, and that one is
 * held by the luminance weight, whose tolerance is tied to the sample count:
 * wide at four samples, where everything is noise, and vanishingly narrow at
 * two hundred, where a difference between neighbours is real.
 *
 * AND IT FADES OUT. `strength` is driven by convergence, and the caller drives
 * it to zero. The image you orbit with is filtered; the image you stop and
 * look at is the raw path trace, pixel for pixel, exactly as M343 rendered it.
 * There is no setting in which this file can damage a finished frame.
 */
#ifndef CYCLES_DENOISE_H
#define CYCLES_DENOISE_H

#include <cstddef>

namespace cyshim {

/* How many wavelet iterations. Each one doubles the reach, so three covers a
 * 17-pixel neighbourhood out of 75 taps rather than the 289 a single filter of
 * that width would cost. That is the whole point of the a-trous decomposition
 * and it is why this is affordable at viewport rates. */
const int kDenoiseIterations = 3;

/* Filter [color] in place.
 *
 * [color]   w*h*4 floats, RGBA, scene-referred linear. Alpha is copied
 *           through untouched — it is a coverage fraction, not a light
 *           measurement, and it carries no noise worth filtering.
 * [albedo]  w*h*3 floats, Cycles' PASS_DENOISING_ALBEDO, or null.
 * [normal]  w*h*3 floats, Cycles' PASS_DENOISING_NORMAL, or null.
 * [samples] how many samples [color] averages. Sets how far the luminance
 *           weight is willing to reach; more samples, less tolerance.
 * [strength] 0 to leave the image alone, 1 for the full filter. Anything
 *           between is a linear blend with the unfiltered pixels, which is
 *           what makes the fade-out on convergence continuous rather than a
 *           visible pop at some threshold.
 *
 * Does nothing at all when strength <= 0, when the image is smaller than the
 * kernel, or when there is no albedo buffer — the demodulation is not an
 * optimisation to skip, it is the thing that makes the filter safe, and a
 * version of this that ran without it would be the blur the comments warn
 * about. [normal] is genuinely optional: without it the filter keeps the
 * albedo and luminance guides and simply reaches further across geometry.
 *
 * [scratch] must hold at least [denoise_scratch_floats] floats. Passing it in
 * rather than allocating keeps this off the allocator on every frame of an
 * orbit — at viewport size the buffer is tens of megabytes and reallocating it
 * thirty times a second costs more than the filter does. Pass null to have it
 * allocate internally, which is what a test does. */
void denoise(float *color,
             const float *albedo,
             const float *normal,
             int width,
             int height,
             int samples,
             float strength,
             float *scratch);

/* How many floats [denoise] needs as scratch for a [width]x[height] image. */
size_t denoise_scratch_floats(int width, int height);

/* How hard to filter an image of [samples] out of [target].
 *
 * 1 while the frame is mostly noise, easing to 0 as it converges, and exactly
 * 0 once it has. Exposed so the shim and its tests agree on one curve rather
 * than each having an opinion, and so the fade can be checked without a GPU. */
float denoise_strength_for(int samples, int target);

}  // namespace cyshim

#endif /* CYCLES_DENOISE_H */
