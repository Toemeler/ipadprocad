#!/usr/bin/env python3
"""M367 — let the viewport show EVERY sample, instead of a handful of jumps.

WHAT THE REPORT WAS
-------------------

    "In Blender I see gradually how it renders. Here I see steps. Like sample
     24, then 50, then 100 and so on. I want to see every sample."

That is not a shim bug and it is not an FFI bug. It is `RenderScheduler`, and
it is doing exactly what it was written to do.

TWO KNOBS, BOTH IN render_scheduler.cpp, AND THEY COMPOUND
----------------------------------------------------------

  1. HOW MANY SAMPLES ARE TRACED PER WORK ITEM.
     `calculate_num_samples_per_update()` is

         samples_in_a_second * guess_display_update_interval_in_seconds()

     rounded UP to a power of two. On a GPU that manages a few hundred samples
     a second and an update interval that has climbed to two seconds, that is
     hundreds of samples in one packet.

  2. HOW OFTEN THE DISPLAY IS TOLD.
     `work_need_update_display()`, with adaptive sampling on, refuses an update
     unless `guess_display_update_interval_in_seconds_for_num_samples()` has
     elapsed. That function is a ladder — 0.1 s for the first second of render,
     then 0.25, 0.5, 1.0 and 2.0.

So a render that has been going for eight seconds traces two seconds' worth of
samples and then shows one frame. 24, then 50, then 100. Blender's viewport
does the same thing; it is simply rarely watched for long enough at a high
enough sample rate to notice, because a Blender viewport is usually denoising
and usually converging in the first second — the fast end of that ladder.

WHY IT IS A PATCH AND NOT A SHIM CHANGE
---------------------------------------

Neither knob is reachable from outside. `set_limit_samples_per_update` exists
and is public, but `PathTrace::render_pipeline` resets it to 0 at the top of
every iteration — it is scratch state for path guiding, not a setting. The
display cadence has no setter at all, and both functions are `protected`, so
subclassing `RenderScheduler` would not help either: `Session` holds one BY
VALUE and never asks anyone else.

So: one sticky integer, three edits, no behaviour change when it is left at
its default of zero. An unpatched tree still compiles the shim — the shim
tests `CYCLES_SHIM_SAMPLES_PER_UPDATE_CAP`, which only this file defines — it
simply renders in Cycles' own steps.

WHAT IT COSTS, WRITTEN DOWN HONESTLY
------------------------------------

A display update is a `copy_render_tile_from_device` plus a `get_pass_pixels`
of the whole frame. At one sample per update that is paid once per sample
instead of once per packet, and at a full-resolution iPad frame it is the
dominant per-sample cost rather than a rounding error.

Three things make that the right trade here and none of them are true of
Blender's viewport:

  * the target is 128 samples (`kRenderSamplesDefault`), not 4096, so the
    number of readbacks is bounded and small;
  * the app renders a standstill only — an orbit is RealityKit's, and the
    tracer is parked (M354) — so no readback ever competes with a gesture;
  * Apple silicon is unified memory, so "copy from device" is a memcpy inside
    one address space rather than a bus transfer.

If it ever needs backing off, it is one constant in the shim
(`kSamplesPerUpdate`) and not a change to this file.

SELF-VERIFYING, like ios_metal.py and host_macos.py: every anchor must appear
exactly once or this aborts. A silent no-op here is a build that looks fine
and steps exactly as before.
"""
import sys


def edit(path, replacements):
    """Apply (anchor, replacement, tag) edits to [path], exactly once each.

    THE ALREADY-APPLIED TEST IS `tag`, NOT `replacement in text`, and that is
    the one thing this helper does differently from its two siblings.

    ios_metal.py and host_macos.py can ask "is the replacement already here and
    the anchor gone?", because there every replacement DELETES the line it
    matched. Two of the edits below instead INSERT beside a line they keep, so
    the anchor is still present afterwards and that test says "not applied" on
    a tree that is. Running the script twice would then insert a second copy of
    a function definition, and the build would fail on a redefinition rather
    than on anything to do with this milestone.

    Every replacement carries `M367 (ipadprocad) <tag>` in a comment, so the
    tag is a marker that exists if and only if the edit has been made.
    """
    with open(path, encoding='utf-8') as f:
        s = f.read()
    for old, new, tag in replacements:
        marker = f'M367 (ipadprocad) {tag}'
        if marker not in new:
            sys.stderr.write(f'FATAL {path}: replacement {tag!r} carries no marker\n')
            sys.exit(1)
        if marker in s:
            print(f'{path}: {tag} already applied')
            continue
        n = s.count(old)
        if n != 1:
            sys.stderr.write(f'FATAL {path}: anchor {tag!r} found {n} times (need 1)\n')
            sys.exit(1)
        s = s.replace(old, new, 1)
        print(f'{path}: applied {tag}')
    with open(path, 'w', encoding='utf-8') as f:
        f.write(s)


RSH = 'blender/intern/cycles/integrator/render_scheduler.h'
RSC = 'blender/intern/cycles/integrator/render_scheduler.cpp'

edit(RSH, [
    # The feature test. Put at the top of the header rather than beside the
    # setter so the shim can ask about it without having read this far, and so
    # a tree that has lost the patch fails the `#ifdef` rather than the link.
    ('#pragma once\n'
     '\n'
     '#include "integrator/adaptive_sampling.h"\n',
     '#pragma once\n'
     '\n'
     '/* M367 (ipadprocad) feature-test-define — this tree carries\n'
     ' * set_samples_per_update_cap(); see backend/cycles/patches/progressive.py.\n'
     ' * The shim compiles with and without it. Without it, the viewport samples\n'
     ' * in Cycles\' own steps. */\n'
     '#define CYCLES_SHIM_SAMPLES_PER_UPDATE_CAP 1\n'
     '\n'
     '#include "integrator/adaptive_sampling.h"\n',
     'feature-test-define'),

    ('  void set_limit_samples_per_update(const int limit_samples);\n'
     '\n'
     ' protected:\n',
     '  void set_limit_samples_per_update(const int limit_samples);\n'
     '\n'
     '  /* M367 (ipadprocad) cap-setter-declaration — cap the samples traced per\n'
     '   * work item, and update the display after every one of them.\n'
     '   *\n'
     '   * Zero (the default) leaves the scheduler exactly as it was: batch size\n'
     '   * from the measured sample rate, display cadence from the 0.1/0.25/0.5/\n'
     '   * 1/2 second ladder. One means the viewport shows every sample.\n'
     '   *\n'
     '   * NOT `set_limit_samples_per_update`, which looks like the same thing\n'
     '   * and is not: PathTrace::render_pipeline resets that one to zero at the\n'
     '   * top of every iteration, because it is scratch state belonging to path\n'
     '   * guiding. This is a setting and survives reset(). */\n'
     '  void set_samples_per_update_cap(const int cap);\n'
     '\n'
     ' protected:\n',
     'cap-setter-declaration'),

    ('  /* If the number of samples per rendering progression should be limited because of path guiding\n'
     '   * being activated or is still inside its training phase */\n'
     '  int limit_samples_per_update_ = 0;\n'
     '};\n',
     '  /* If the number of samples per rendering progression should be limited because of path guiding\n'
     '   * being activated or is still inside its training phase */\n'
     '  int limit_samples_per_update_ = 0;\n'
     '\n'
     '  /* M367 (ipadprocad) cap-member — see set_samples_per_update_cap().\n'
     '   * Deliberately NOT inside `state_`, which reset() clears: it is a\n'
     '   * property of the caller and has to survive every camera move. */\n'
     '  int samples_per_update_cap_ = 0;\n'
     '};\n',
     'cap-member'),
])

edit(RSC, [
    ('void RenderScheduler::set_adaptive_sampling(const AdaptiveSampling &adaptive_sampling)\n',
     '/* M367 (ipadprocad) cap-setter-definition. A plain assignment, unlike\n'
     ' * set_limit_samples_per_update above, which min-combines because several\n'
     ' * callers narrow the same value within one iteration. This has one caller\n'
     ' * and one meaning. */\n'
     'void RenderScheduler::set_samples_per_update_cap(const int cap)\n'
     '{\n'
     '  samples_per_update_cap_ = cap > 0 ? cap : 0;\n'
     '}\n'
     '\n'
     'void RenderScheduler::set_adaptive_sampling(const AdaptiveSampling &adaptive_sampling)\n',
     'cap-setter-definition'),

    ('  if (limit_samples_per_update_) {\n'
     '    num_samples_to_render = min(limit_samples_per_update_, num_samples_to_render);\n'
     '  }\n',
     '  if (limit_samples_per_update_) {\n'
     '    num_samples_to_render = min(limit_samples_per_update_, num_samples_to_render);\n'
     '  }\n'
     '\n'
     '  /* M367 (ipadprocad) cap-applied-to-batch-size — the caller asked to see\n'
     '   * every sample.\n'
     '   *\n'
     '   * Applied BEFORE align_samples, which is safe in the one direction that\n'
     '   * matters: align_samples only ever clamps (every one of its returns is a\n'
     '   * min against num_samples), so it can shrink this further but never grow\n'
     '   * it back. A cap of 1 therefore traces exactly one sample. */\n'
     '  if (samples_per_update_cap_) {\n'
     '    num_samples_to_render = min(samples_per_update_cap_, num_samples_to_render);\n'
     '  }\n',
     'cap-applied-to-batch-size'),

    ('  /* When adaptive sampling is used, its possible that only handful of samples of a very simple\n'
     '   * scene will be scheduled to a powerful device (in order to not "miss" any of filtering points).\n'
     '   * We take care of skipping updates here based on when previous display update did happen. */\n'
     '  const double update_interval = guess_display_update_interval_in_seconds_for_num_samples(\n',
     '  /* M367 (ipadprocad) cap-forces-display-update — with a cap in force,\n'
     '   * the batch IS the update.\n'
     '   *\n'
     '   * Capping the batch size alone would have changed nothing visible: the\n'
     '   * scheduler would trace one sample at a time and then throw away every\n'
     '   * frame until the interval below had elapsed, which is the same steps\n'
     '   * with more overhead. The two knobs only work together. */\n'
     '  if (samples_per_update_cap_) {\n'
     '    return true;\n'
     '  }\n'
     '\n'
     '  /* When adaptive sampling is used, its possible that only handful of samples of a very simple\n'
     '   * scene will be scheduled to a powerful device (in order to not "miss" any of filtering points).\n'
     '   * We take care of skipping updates here based on when previous display update did happen. */\n'
     '  const double update_interval = guess_display_update_interval_in_seconds_for_num_samples(\n',
     'cap-forces-display-update'),
])

print('progressive sampling patches APPLIED OK')
