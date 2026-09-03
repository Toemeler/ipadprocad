/* M344 — the denoiser for a build that cannot carry Cycles' own.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * ---------------------------------------------------------------------------
 * M367 — WHAT THIS IS NOW: THE FALLBACK, AND WHEN IT RUNS
 * ---------------------------------------------------------------------------
 *
 * Cycles has two denoisers. OptiX is NVIDIA's. OpenImageDenoise is the one
 * that works here — it has had a Metal backend since 2.3 — and it is the one
 * Blender uses, so where the build has it, the shim lets CYCLES drive it:
 * `Integrator::set_use_denoise` and nothing in this file. See
 * configure_integrator in cycles_shim.cpp.
 *
 * `lib/ios_arm64`, the precompiled dependency set Blender's own `ios` branch
 * builds against, does not ship OIDN — that is why `-DWITH_OPENIMAGEDENOISE=OFF`
 * is in every iOS Cycles build here: `cycles_integrator` was otherwise
 * compiling `denoiser_oidn.cpp` against a library that is not there, and the
 * link failed on `_oidnSetFilterImage`. The macOS set DOES ship it, so the
 * host render test builds and runs the OIDN path on every push, and the iOS
 * probe turns it on the moment the library appears.
 *
 * So this file is what an iOS build denoises with today, and it is a real
 * denoiser rather than a placeholder: an edge-avoiding a-trous wavelet filter
 * (Dammertz, Sewtz, Hanika & Lensch, HPG 2010), guided by the albedo and
 * normal buffers Cycles writes for exactly this purpose.
 *
 * IT RUNS ONCE, ON THE FINISHED FRAME. M344 ran it on every frame handed to
 * the display and M353 removed it for that: 51 ms per frame at 480x320 and
 * around 450 ms at 1440x1080, against a poll every 14 ms. A filter in the path
 * of a progressive render is a frame-rate cost, and it was reported as one —
 * "it only goes in steps". Sampling has stopped by the time this is called
 * now, so the only thing waiting on it is the tail of a render that already
 * took seconds, and every frame before it is the raw path trace.
 *
 * ---------------------------------------------------------------------------
 * THE OBJECTION THIS ANSWERS
 * ---------------------------------------------------------------------------
 *
 * Every Cycles build in this repo carried the comment that a denoiser "smears
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
 * five hundred, where a difference between neighbours is real.
 *
 * THAT SAMPLE COUNT IS WHAT REPLACED THE FADE. Until M367 the caller ramped
 * `strength` down as samples climbed, because the filter was running the whole
 * way and had to hand the image back to the path tracer at some point. There
 * is no "whole way" any more — one call, at the end, at full strength — so the
 * ramp went with it, and `denoise_strength_for` with the ramp. What keeps a
 * well-sampled frame from being softened is the tolerance above: at 512
 * samples the luminance weight collapses across almost any real difference, so
 * the filter has almost nothing left to average and the image it returns is
 * very nearly the one it was given. That is a property of the filter rather
 * than of a curve outside it, which is the better place for it to live.
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
 *           weight is willing to reach; more samples, less tolerance. It is
 *           the whole of how this filter adapts to a converged image, so it
 *           has to be the count the frame ACTUALLY reached rather than the
 *           target it was aiming at — adaptive sampling routinely stops well
 *           short of the target, and a frame told it has 512 samples when it
 *           has 40 comes back still noisy.
 * [strength] 0 to leave the image alone, 1 for the full filter. Anything
 *           between is a linear blend with the unfiltered pixels. The shim
 *           passes 1: it calls this once, on a frame that is finished, and a
 *           partial blend of a final image is not a thing anybody asked for.
 *
 * Does nothing at all when strength <= 0, when the image is smaller than the
 * kernel, or when there is no albedo buffer — the demodulation is not an
 * optimisation to skip, it is the thing that makes the filter safe, and a
 * version of this that ran without it would be the blur the comments warn
 * about. [normal] is genuinely optional: without it the filter keeps the
 * albedo and luminance guides and simply reaches further across geometry.
 *
 * [scratch] must hold at least [denoise_scratch_floats] floats. Passing it in
 * rather than allocating saves a tens-of-megabytes allocation on the one frame
 * this runs on; the shim keeps one and reuses it. Pass null to have it
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

}  // namespace cyshim

#endif /* CYCLES_DENOISE_H */
